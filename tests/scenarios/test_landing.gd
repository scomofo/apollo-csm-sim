## Slice 3c's check (docs/ROADMAP.md, milestone 3): Eagle lands at
## Tranquility Base, on the real terrain (data/terrain/), navigating on the
## LGC's own state vector; and slice 3f's: the lunar_descent start phase
## lands there. In that phase Eagle has undocked in lunar orbit over the
## site and flown the DOI PAD for the landing pass. Fifteen minutes before
## PDI the ground's timeline uplinks its state vector with the PDI PAD,
## off by MSFN's tracking error: 250 m along track, 150 m to the side and
## 900 m high at PDI (mission.json "pdi"). Powered descent begins 470 km
## (ground range) before the site.
##
## The automatic run flies P63 braking, P64 approach and P65: when the
## landing radar's altitude comes good, the crew checks ΔH and keys V57,
## as Aldrin did, and the radar pulls the LGC's altitude and velocity in.
## It lands within 500 m of the site at under 1 m/s down and 0.5 m/s
## across. Without V57 the LGC flies into the ground. With the
## commander redesignating the landing point in P64 (LPD), Eagle lands on
## the site despite a 900 m error along the track. A run in P66 takes over
## at 150 m with the hand controller and the ROD switch. All start from one
## checkpoint taken before PDI.
extends SimTest

const SITE_LAT := 0.674
const SITE_LON := 23.473

var _before_pdi := ""
var _pad := {}
var _pdi := {}


func before_all() -> void:
	build("lunar_descent")
	_pad = rt.sequencer.pads["doi"]
	gut.p(Rtcc.pad_text(_pad) + "  landing at " + Units.hms(float(_pad["land_get"])))
	run_until(func() -> bool: return rt.sequencer.pads.has("pdi"), 600.0, 1.0)
	_pdi = rt.sequencer.pads.get("pdi", {})
	gut.p(str(Bus.get_value("mission.pad_text")))
	_before_pdi = JSON.stringify(rt.snapshot())


## Restore the checkpoint (with [param error], the PDI PAD's state vector
## is uplinked again off by that much at PDI, LVLH m), select P63 and fly it
## to ignition: PRO at V06N33, LGC MODE AUTO and PRO at V50N18, ENGINE ARM
## DES, PRO at V99.
func _to_ignition(error: Array = []) -> Lgc:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	if not error.is_empty():
		rt.mission.section("pdi")["state_error_lvlh_m"] = error
		rt.sequencer.request_pad("pdi")
	var lgc := rt.lgc()
	keys("V37E63E", lgc)
	assert_eq(lgc.program, 63, "P63")
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	return lgc


## The miss: the ground range from the site to where the LM sits, m.
func _miss() -> float:
	return rt.dynamics.lm.landed_pos.angle_to(rt.sequencer.landing_site()) * Bodies.R_MOON


## The LGC's state vector less truth, LVLH m (X along track, Y right, Z
## down).
func _nav_error(lgc: Lgc) -> Vector3:
	var t := rt.dynamics.lm.traj
	return Trajectory.lvlh_basis(t.pos(), t.vel()).inverse() * (lgc.nav.pos() - t.pos())


func test_the_lunar_orbit_doi_and_pdi_are_planned_for_the_site() -> void:
	build("lunar_orbit")
	var t_land := float(rt.mission.section("landing")["get_s"])
	var site := rt.sequencer.landing_site()
	assert_almost_eq(site.length() - Bodies.R_MOON, -1927.5, 1.0, "the site on the terrain, 1,927 m below the reference sphere")
	var h := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()
	assert_almost_eq(h.dot(Rtcc.site_at(site, t_land).normalized()), 0.0, 1e-6, "the orbit passes over the site at the landing time")
	assert_lt(h.dot(Bodies.moon_pole(t_land)), 0.0, "retrograde")
	assert_almost_eq(rad_to_deg(acos(-h.dot(Bodies.moon_pole(t_land)))), SITE_LAT, 0.01, "the site at the ground track's northernmost point")
	# The DOI PAD: the pass that lands nearest the landing time, with the
	# pericynthion 470 km before the site, 50,000 ft above it.
	assert_eq(str(_pad.get("name", "")), "DOI")
	assert_almost_eq(float(_pad["land_get"]), t_land, 3600.0, "within half a revolution of 102:45:40")
	assert_almost_eq(float(_pad["hp"]), 15240.0, 50.0, "pericynthion at 50,000 ft above the site")
	# The PDI PAD's state vector is off by the tracking error at PDI.
	assert_eq(str(_pdi.get("name", "")), "PDI")
	assert_almost_eq(float(_pdi["tig"]), float(_pad["hp_get"]), 30.0, "PDI at the pericynthion")
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	var lgc := rt.lgc()
	run(float(_pdi["tig"]) - SimClock.get_seconds)
	assert_almost_eq(_nav_error(lgc), Vector3(250.0, 150.0, -900.0), Vector3.ONE * 5.0, "the LGC's error at PDI")


func test_automatic_guidance_lands_at_tranquility_base() -> void:
	var lgc := _to_ignition()
	assert_almost_eq(lgc.pdi_tig, float(_pad["hp_get"]), 10.0, "P63 ignites where the DOI put the pericynthion")
	assert_true(Bus.get_value("lm.dsky.lamp.alt"), "ALT: no radar altitude yet")
	assert_eq(rt.sequencer.phase, "lunar_descent")
	assert_almost_eq(float(rt.sequencer.timeline_done.get("go_pdi", -1.0)), float(_pdi["tig"]) - 297.0, 6.0,
		"GO for powered descent 4 min 57 s before PDI, as Apollo 11 had it")
	var seen := {"programs": [], "ftp": false, "recovered": false, "hg": 0.0, "dh_hg": 0.0, "lamps_out": false}
	var t_ig := lgc.pdi_tig
	var landed := run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		if lgc.lr_update and not Bus.get_value("lm.dsky.lamp.alt") and not Bus.get_value("lm.dsky.lamp.vel"):
			seen["lamps_out"] = true
		if not lgc.program in seen["programs"]:
			seen["programs"].append(lgc.program)
			if lgc.program == 64:
				seen["hg"] = lgc._h
				seen["dh_hg"] = lgc.delta_h
				seen["err_hg"] = _nav_error(lgc)
		if lgc.program == 63 and lgc.step_name == "braking":
			if lgc.descent_throttle >= 1.0:
				seen["ftp"] = true
			elif seen["ftp"] and SimClock.get_seconds - t_ig > 60.0:
				seen["recovered"] = true
		return rt.dynamics.lm.landed, 1000.0, 1.0, false)
	assert_true(landed, "touchdown")
	run(SimClock.FIXED_DT, false)
	assert_eq(rt.sequencer.phase, "lunar_surface", "on the surface")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("Radar altitude good at %.0f m over the ground, ΔH %.0f m; at high gate ΔH %.0f m, LGC error %s" % [
		seen.get("dh0_agl", 0.0), seen.get("dh0", 0.0), seen["dh_hg"], seen.get("err_hg", Vector3.ZERO)])
	gut.p("Eagle landed %.0f m from the site, %.2f m/s down and %.2f m/s across, %.0f s after PDI, %.0f kg of DPS propellant left" % [
		_miss(), td["vertical_mps"], td["horizontal_mps"], float(td["get_s"]) - t_ig, float(Bus.get_value("lm.dps.prop_kg"))])
	assert_eq(seen["programs"], [63, 64, 65, 68], "braking, approach, automatic landing, touchdown")
	assert_true(seen["ftp"], "braking at full thrust")
	assert_true(seen["recovered"], "and throttling down before high gate")
	# The radar found the LGC about 900 m high (the tracking error, and the
	# ground along the approach lower than the site), and pulled it in.
	assert_between(float(seen.get("dh0", 0.0)), -1300.0, -700.0, "ΔH when the radar's altitude came good")
	assert_between(float(seen.get("dh0_agl", 0.0)), 7000.0, 12500.0, "within the radar's range")
	assert_true(seen["lamps_out"], "ALT and VEL out")
	assert_lt(absf(float(seen["dh_hg"])), 50.0, "ΔH at high gate")
	assert_between(float(seen["hg"]), 1500.0, 3000.0, "high gate")
	assert_lt(_miss(), 500.0, "within 500 m of the site")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_true(Bus.get_value("lm.contact_light"), "CONTACT LIGHT")
	assert_true(Bus.get_value("lm.dyn.landed"))
	assert_true(Bus.has_channel("mission.event.lm_landing"))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Tranquility")
	assert_gt(float(Bus.get_value("lm.dps.prop_kg")), 0.0, "propellant to spare")
	run(2.0, false)
	assert_eq(float(Bus.get_value("lm.dps.thrust_n")), 0.0, "P68: engine off")
	assert_true(rt.dynamics.lm.landed, "and still down")
	# A checkpoint on the surface brings back the touchdown and the light.
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(Bus.get_value("lm.touchdown", {}), JSON.parse_string(JSON.stringify(td)), "lm.touchdown restored")
	assert_true(Bus.get_value("lm.contact_light", false), "CONTACT LIGHT restored")
	# V06N43 shows where the LGC has Eagle: its own state vector, off by
	# what the radar couldn't see.
	var n43: Array = lgc.noun_values(43)
	assert_almost_eq(float(n43[0]), SITE_LAT, 0.02, "V06N43 latitude")
	assert_almost_eq(float(n43[1]), SITE_LON, 0.02, "and longitude")


func test_a_checkpoint_in_p63_before_ignition_keeps_the_burn_attitude() -> void:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	var lgc := rt.lgc()
	keys("V37E63E", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.step_name == "wait", 600.0, 1.0, false), "in the burn attitude")
	var target := lgc.auto_target
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(lgc.step_name, "wait")
	assert_lt(lgc.auto_target.angle_to(target), 1e-4, "the burn attitude comes back with it")
	# And PDI fires against the velocity over the surface.
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	run(30.0, false)
	var tr := rt.dynamics.lm.traj
	var rel := tr.vel() - Bodies.moon_omega(tr.t).cross(tr.pos())
	var thrust_axis := Basis(rt.dynamics.lm.attitude.q) * Vector3.RIGHT
	assert_gt(float(Bus.get_value("lm.dps.thrust_n")), 0.0, "the descent engine burning")
	assert_gt(rad_to_deg(thrust_axis.angle_to(rel)), 150.0, "retrograde")


## Slice 7c: the ground's landing site correction. After throttle-up MSFN
## finds how far along the track the LGC has Eagle from where it is (the
## PDI PAD's 250 m), CAPCOM reads it to the nearest 100 ft, and V21N69
## moves the site that far downrange, on its sphere, while P63 flies on.
## Before P63 the LGC won't take it.
func test_n69_moves_the_landing_site_downrange() -> void:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	var lgc0 := rt.lgc()
	keys("V21N69E+04200E", lgc0)
	assert_true(lgc0.dsky.lamps.get("opr_err", false), "OPR ERR before P63")
	var lgc := _to_ignition()
	assert_true(run_until(func() -> bool: return SimClock.get_seconds > lgc.pdi_tig + 60.0, 120.0, 1.0, false), "throttled up")
	var pad := rt.sequencer.request_pad("n69")
	var err := _nav_error(lgc)
	assert_eq(str(pad.get("name", "")), "N69")
	assert_almost_eq(float(pad["dz_ft"]), err.x / Units.FT, 60.0, "the LGC's error along the track, to 100 ft")
	var site0 := lgc.landing_site
	keys("V21N69E+%05dE" % int(absf(float(pad["dz_ft"]))) if float(pad["dz_ft"]) >= 0.0 else "V21N69E-%05dE" % int(absf(float(pad["dz_ft"]))), lgc)
	var moved := lgc.landing_site - site0
	var down := lgc.guidance_frame.z
	assert_almost_eq(moved.dot(down), float(pad["dz_ft"]) * Units.FT, 0.5, "the site moved downrange by R1")
	assert_almost_eq(moved.dot(lgc.guidance_frame.y), 0.0, 0.1, "and not across")
	assert_almost_eq(lgc.landing_site.length(), site0.length(), 0.01, "over its sphere")
	assert_eq(lgc.program, 63, "P63 flies on")
	run(1.0, false)
	assert_true(Bus.get_value("lm.guid.ls_corrected", false), "the LGC's site moved since its uplink")
	# A checkpoint keeps the moved site, and that it moved.
	var site1 := lgc.landing_site
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_true(rt.lgc().ls_corrected, "restored: noun 69 loaded")
	assert_lt((rt.lgc().landing_site - site1).length(), 0.01, "and the site where it moved it")
	gut.p("N69: the LGC %.0f m along the track from truth; CAPCOM's %+.0f ft moved the site %.1f m downrange" % [
		err.x, float(pad["dz_ft"]), moved.dot(down)])


func test_without_radar_updates_the_lgc_flies_into_the_ground() -> void:
	var lgc := _to_ignition()
	var seen := {"dh_hg": 0.0}
	var landed := run_until(func() -> bool:
		if lgc.program == 64 and seen["dh_hg"] == 0.0:
			seen["dh_hg"] = lgc.delta_h
			seen["h_hg"] = lgc._h
			seen["agl_hg"] = lm_agl()
		return rt.dynamics.lm.landed, 1000.0, 1.0, false)
	assert_true(landed, "it meets the ground")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("Without V57: at high gate the LGC had %.0f m, the ground was %.0f m below (ΔH %.0f m); it hit %.0f m from the site at %.1f m/s down" % [
		seen.get("h_hg", 0.0), seen.get("agl_hg", 0.0), seen["dh_hg"], _miss(), td["vertical_mps"]])
	assert_lt(float(seen["dh_hg"]), -900.0, "the LGC still a kilometre high at high gate")
	assert_true(td["hard"], "a hard landing")
	assert_gt(float(td["vertical_mps"]), 10.0, "at speed")
	assert_gt(_miss(), 2000.0, "well short of the site")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "hard landing")


func test_p64_redesignation_puts_eagle_on_the_site() -> void:
	# The LGC thinks Eagle is 900 m farther along than it is: left to
	# itself it would land about that far short.
	var lgc := _to_ignition([900.0, 0.0, 0.0])
	var seen := {}
	assert_true(run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		return lgc.program == 64, 900.0, 1.0, false), "P64")
	var n64: Array = lgc.noun_values(64)
	assert_almost_eq(float(n64[0]), 99000.0 + roundf(lgc._lpd), 1.0, "N64: 99+ s to redesignate, and the LPD angle")
	assert_between(lgc._lpd, 25.0, 70.0, "the LPD angle on the window's scale")
	var site := rt.sequencer.landing_site()
	var target0 := lgc.landing_site
	var short := target0.angle_to(site) * Bodies.R_MOON
	var clicks := lpd_pilot(lgc, site)
	var moved := lgc.landing_site.angle_to(target0) * Bodies.R_MOON
	assert_true(run_until(func() -> bool: return rt.dynamics.lm.landed, 400.0, 1.0, false), "touchdown")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("The LPD moved the landing point %.0f m in %d clicks; Eagle landed %.0f m from the site, %.2f m/s down" % [
		moved, clicks, _miss(), td["vertical_mps"]])
	assert_gt(clicks, 1, "the commander redesignated")
	assert_gt(moved, 500.0, "the landing point moved downrange")
	assert_lt(short, 50.0, "the LGC aimed at the site it had")
	assert_lt(_miss(), 60.0, "and Eagle landed on the one out of the window")
	assert_lt(float(td["vertical_mps"]), 1.0)
	assert_false(td["hard"])


func test_p66_lands_on_the_hand_controller_and_the_rod_switch() -> void:
	var lgc := _to_ignition()
	var seen := {}
	assert_true(run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		return lgc.program == 64 and lgc._h < 150.0, 900.0, 1.0, false), "P64 below 150 m")
	Bus.set_value("ctl.lm.mode", 1)
	var hdot := lgc._hdot
	rod_click(-1)
	assert_eq(lgc.program, 66, "the first ROD click takes over in P66")
	assert_almost_eq(lgc.rod_cmd, hdot - 0.3048, 0.2, "1 ft/s down on the rate it had")
	var t0 := SimClock.get_seconds
	while not rt.dynamics.lm.landed and SimClock.get_seconds - t0 < 400.0:
		fly_by_hand(lgc)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	# The LGC sees the touchdown at its next step.
	run(SimClock.FIXED_DT, false)
	assert_true(rt.dynamics.lm.landed, "touchdown")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("In P66, Eagle landed %.0f m from the site, %.2f m/s down and %.2f m/s across" % [
		_miss(), td["vertical_mps"], td["horizontal_mps"]])
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_lt(_miss(), 500.0, "near the site")
	assert_eq(lgc.program, 68)


func test_a_landed_lm_turns_with_the_moon_and_can_lift_off() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	# Set Eagle down at the site, upright.
	var lm := rt.dynamics.lm
	var cm := Dynamics.lm_cm_height("lm")
	var site_r := rt.sequencer.landing_site().length()
	var up := Rtcc.site_at(rt.sequencer.landing_site(), lm.traj.t).normalized()
	var pos := up * (site_r + cm)
	lm.traj.set_state("moon", lm.traj.t, pos, Bodies.moon_omega(lm.traj.t).cross(pos))
	var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	lm.attitude.q = Basis(up, side, up.cross(side)).get_rotation_quaternion()
	lm.attitude.omega = Vector3.ZERO
	lm.land(site_r + cm)
	var spot := lm.landed_pos
	var steps := SimClock.step_count
	run(3600.0)
	assert_true(lm.landed, "an hour on the surface")
	assert_lt(SimClock.step_count - steps, 1500, "coasting")
	assert_lt((Bodies.moon_fixed(lm.traj.t) * spot - lm.traj.pos()).length(), 1.0, "where the Moon has turned the spot")
	assert_almost_eq(lm.traj.vel().length(), Bodies.moon_omega(lm.traj.t).cross(lm.traj.pos()).length(), 1e-3, "moving with the surface")
	assert_lt(_miss(), 0.5, "at the site")
	# The landed LM comes back from a checkpoint where it was.
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lm = rt.dynamics.lm
	assert_true(lm.landed, "still on the surface")
	assert_lt((lm.landed_pos - spot).length(), 0.01)
	# Stage, and lift off on the ascent engine started by hand.
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	assert_eq(lm.config, "lm_ascent")
	assert_true(lm.landed, "the ascent stage sits on the descent stage")
	Bus.set_value("ctl.lm.engine_arm", 1)
	Bus.set_value("ctl.lm.eng_start", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.eng_start", false)
	# At full time acceleration: the engine running keeps the steps fine,
	# while its thrust builds on the surface and after.
	steps = SimClock.step_count
	run(10.0)
	assert_gt(SimClock.step_count - steps, 495, "fine steps from engine start")
	assert_false(lm.landed, "lift-off")
	var h := lm.traj.radius() - site_r
	assert_gt(h, 50.0, "climbing on the ascent engine")
	assert_gt(lm.traj.radial_rate(), 10.0)
	Bus.set_value("ctl.lm.eng_stop", true)
	run(3.0, false)
	assert_eq(float(Bus.get_value("lm.aps.thrust_n")), 0.0, "ENGINE STOP, after the tail-off")


func test_loi_turns_the_orbit_over_the_site() -> void:
	build("translunar_coast")
	# The midcourse correction takes the coast off TLI's free return, to 60
	# nmi on the node over the site, as Apollo 11's did.
	assert_false(rt.sequencer.request_pad("mcc").is_empty(), "an MCC")
	fly_pad()
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	var loi := rt.sequencer.request_pad("loi")
	assert_false(loi.is_empty(), "LOI solution")
	gut.p("LOI " + Rtcc.pad_text(loi))
	var dv: Vector3 = loi["dv_lvlh"]
	assert_ne(dv.y, 0.0, "an out-of-plane part")
	assert_lt(absf(dv.y), 60.0, "a small plane change")
	# The orbit the PAD leaves, flown as the RTCC flies it: from the state
	# MSFN tracked, the one the RTCC planned on, over the site; from the
	# truth, off it by what the tracking error makes (under 2 km).
	var t_land := float(rt.mission.section("landing")["get_s"])
	var s := Rtcc.site_at(rt.sequencer.landing_site(), t_land).normalized()
	for from in [loi["state"], rt.dynamics.traj]:
		var tr: Trajectory = (from as Trajectory).clone()
		tr.coast_to(float(loi["tig"]), 60.0)
		Rtcc.simulate_sps_burn(tr, rt.dynamics.mass, dv)
		var h := tr.pos().cross(tr.vel()).normalized()
		assert_lt(h.dot(Bodies.moon_pole(t_land)), 0.0, "retrograde")
		if from == loi["state"]:
			assert_almost_eq(h.dot(s), 0.0, 1e-5, "over the site at the landing time")
		else:
			gut.p("From the truth the orbit passes %.0f m from the site" % (absf(h.dot(s)) * Bodies.R_MOON))
			assert_lt(absf(h.dot(s)) * Bodies.R_MOON, 2000.0, "near the site")

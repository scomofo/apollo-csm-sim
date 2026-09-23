## Slice 3c's check (docs/ROADMAP.md, milestone 3): Eagle lands at
## Tranquility Base. In lunar orbit over the site, the LM undocks and flies
## the DOI PAD for the landing pass, and powered descent begins 470 km
## (ground range) before the site. The automatic run flies P63 braking,
## P64 approach and P65 to touchdown within 500 m of the site, at under
## 1 m/s down and 0.5 m/s across. A second run takes over in P66 at 150 m
## with the hand controller and the ROD switch. Both start from one
## checkpoint taken before PDI.
extends SimTest

const SITE_LAT := 0.674
const SITE_LON := 23.473

var _before_pdi := ""
var _pad := {}


func before_all() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	_pad = rt.sequencer.request_pad("doi")
	gut.p(Rtcc.pad_text(_pad) + "  landing at " + Units.hms(float(_pad["land_get"])))
	fly_lm_pad(40, 2)
	run(float(_pad["hp_get"]) - 900.0 - SimClock.get_seconds)
	_before_pdi = JSON.stringify(rt.snapshot())


## Restore the checkpoint, select P63 and fly it to ignition: PRO at
## V06N33, LGC MODE AUTO and PRO at V50N18, ENGINE ARM DES, PRO at V99.
func _to_ignition() -> Lgc:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
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


func test_the_lunar_orbit_and_doi_are_planned_for_the_site() -> void:
	build("lunar_orbit")
	var t_land := float(rt.mission.section("landing")["get_s"])
	var site := rt.sequencer.landing_site()
	var h := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()
	assert_almost_eq(h.dot(Rtcc.site_at(site, t_land).normalized()), 0.0, 1e-6, "the orbit passes over the site at the landing time")
	assert_lt(h.dot(Bodies.moon_normal()), 0.0, "retrograde")
	assert_almost_eq(rad_to_deg(acos(-h.dot(Bodies.moon_normal()))), SITE_LAT, 0.01, "the site at the ground track's northernmost point")
	# The DOI PAD: the pass that lands nearest the landing time, with the
	# pericynthion 470 km before the site.
	assert_eq(str(_pad.get("name", "")), "DOI")
	assert_almost_eq(float(_pad["land_get"]), t_land, 3600.0, "within half a revolution of 102:45:40")
	assert_almost_eq(float(_pad["hp"]), 15240.0, 50.0, "pericynthion at 50,000 ft")


func test_automatic_guidance_lands_at_tranquility_base() -> void:
	var lgc := _to_ignition()
	assert_almost_eq(lgc.pdi_tig, float(_pad["hp_get"]), 10.0, "P63 ignites where the DOI put the pericynthion")
	var seen := {"programs": [], "ftp": false, "recovered": false, "hg": 0.0}
	var t_ig := lgc.pdi_tig
	var landed := run_until(func() -> bool:
		if not lgc.program in seen["programs"]:
			seen["programs"].append(lgc.program)
			if lgc.program == 64:
				seen["hg"] = lgc._h
		if lgc.program == 63 and lgc.step_name == "braking":
			if lgc.descent_throttle >= 1.0:
				seen["ftp"] = true
			elif seen["ftp"] and SimClock.get_seconds - t_ig > 60.0:
				seen["recovered"] = true
		return rt.dynamics.lm.landed, 1000.0, 1.0, false)
	assert_true(landed, "touchdown")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("Eagle landed %.1f m from the site, %.2f m/s down and %.2f m/s across, %.0f s after PDI, %.0f kg of DPS propellant left" % [
		_miss(), td["vertical_mps"], td["horizontal_mps"], float(td["get_s"]) - t_ig, float(Bus.get_value("lm.dps.prop_kg"))])
	assert_eq(seen["programs"], [63, 64, 65, 68], "braking, approach, automatic landing, touchdown")
	assert_true(seen["ftp"], "braking at full thrust")
	assert_true(seen["recovered"], "and throttling down before high gate")
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
	var n43: Array = lgc.noun_values(43)
	assert_almost_eq(float(n43[0]), SITE_LAT, 0.02, "V06N43 latitude")
	assert_almost_eq(float(n43[1]), SITE_LON, 0.02, "and longitude")


func test_p66_lands_on_the_hand_controller_and_the_rod_switch() -> void:
	var lgc := _to_ignition()
	assert_true(run_until(func() -> bool: return lgc.program == 64 and lgc._h < 150.0, 900.0, 1.0, false), "P64 below 150 m")
	Bus.set_value("ctl.lm.mode", 1)
	var hdot := lgc._hdot
	_rod(-1)
	assert_eq(lgc.program, 66, "the first ROD click takes over in P66")
	assert_almost_eq(lgc.rod_cmd, hdot - 0.3048, 0.2, "1 ft/s down on the rate it had")
	var t0 := SimClock.get_seconds
	while not rt.dynamics.lm.landed and SimClock.get_seconds - t0 < 400.0:
		_fly_by_hand(lgc)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	assert_true(rt.dynamics.lm.landed, "touchdown")
	var td: Dictionary = rt.dynamics.lm.touchdown
	gut.p("In P66, Eagle landed %.1f m from the site, %.2f m/s down and %.2f m/s across" % [
		_miss(), td["vertical_mps"], td["horizontal_mps"]])
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_lt(_miss(), 500.0, "near the site")
	assert_eq(lgc.program, 68)


## One ROD click: +1 slows the descent by 1 ft/s, -1 speeds it up.
func _rod(dir: int) -> void:
	Bus.set_value("ctl.lm.rod", dir)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.rod", 0)
	run(SimClock.FIXED_DT, false)


## A fifth of a second of the pilot: the hand controller tilts the LM
## against its horizontal velocity, as the cross-pointers show it, to stop
## it in about 4 s and no more than 15° from upright; ROD clicks keep the
## descent at a metre a second for every 20 m of height, between 0.6 and
## 3 m/s.
func _fly_by_hand(lgc: Lgc) -> void:
	var r: Array = Bus.get_value("lm.dyn.r_m")
	var v: Array = Bus.get_value("lm.dyn.v_mps")
	var pos := Vector3(r[0], r[1], r[2])
	var rel := Vector3(v[0], v[1], v[2]) - Bodies.moon_omega().cross(pos)
	var up := pos.normalized()
	var h := pos.length() - Bodies.R_MOON - Dynamics.lm_cm_height("lm")
	var g := Bodies.MU_MOON / pos.length_squared()
	var ah := -(rel - up * rel.dot(up)) / 4.0
	var ah_max := g * tan(deg_to_rad(15.0))
	if ah.length() > ah_max:
		ah = ah.normalized() * ah_max
	var att: Quaternion = Bus.get_value("lm.dyn.att_q")
	var err := Basis(att).inverse() * (Basis(att) * Vector3.RIGHT).cross((up * g + ah).normalized())
	var rhc := (Vector3(0.0, err.y, err.z) / AgcCore.RATE_HOLD).clamp(-Vector3.ONE, Vector3.ONE)
	Bus.set_value("ctl.lm.rhc", rhc if rhc.length() >= 0.06 else Vector3.ZERO)
	var target := -clampf(h / 20.0, 0.6, 3.0)
	if lgc.rod_cmd < target - 0.2:
		_rod(1)
	elif lgc.rod_cmd > target + 0.2:
		_rod(-1)
	else:
		run(0.2, false)


func test_a_landed_lm_turns_with_the_moon_and_can_lift_off() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	# Set Eagle down at the site, upright.
	var lm := rt.dynamics.lm
	var cm := Dynamics.lm_cm_height("lm")
	var up := Rtcc.site_at(rt.sequencer.landing_site(), lm.traj.t).normalized()
	var pos := up * (Bodies.R_MOON + cm)
	lm.traj.set_state("moon", lm.traj.t, pos, Bodies.moon_omega().cross(pos))
	var side := up.cross(Vector3.UP if absf(up.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT).normalized()
	lm.attitude.q = Basis(up, side, up.cross(side)).get_rotation_quaternion()
	lm.attitude.omega = Vector3.ZERO
	lm.land(Bodies.R_MOON + cm)
	var spot := lm.landed_pos
	var steps := SimClock.step_count
	run(3600.0)
	assert_true(lm.landed, "an hour on the surface")
	assert_lt(SimClock.step_count - steps, 1500, "coasting")
	assert_lt((Bodies.moon_fixed(lm.traj.t) * spot - lm.traj.pos()).length(), 1.0, "where the Moon has turned the spot")
	assert_almost_eq(lm.traj.vel().length(), Bodies.moon_omega().cross(lm.traj.pos()).length(), 1e-3, "moving with the surface")
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
	run(10.0, false)
	assert_false(lm.landed, "lift-off")
	var h := lm.traj.radius() - Bodies.R_MOON
	assert_gt(h, 50.0, "climbing on the ascent engine")
	assert_gt(lm.traj.radial_rate(), 10.0)
	Bus.set_value("ctl.lm.eng_stop", true)
	run(3.0, false)
	assert_eq(float(Bus.get_value("lm.aps.thrust_n")), 0.0, "ENGINE STOP, after the tail-off")


func test_loi_turns_the_orbit_over_the_site() -> void:
	build("translunar_coast")
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	var loi := rt.sequencer.request_pad("loi")
	assert_false(loi.is_empty(), "LOI solution")
	gut.p("LOI " + Rtcc.pad_text(loi))
	var dv: Vector3 = loi["dv_lvlh"]
	assert_ne(dv.y, 0.0, "an out-of-plane part")
	assert_lt(absf(dv.y), 60.0, "a small plane change")
	# The orbit the PAD leaves, flown as the RTCC flies it.
	var tr := rt.dynamics.traj.clone()
	tr.coast_to(float(loi["tig"]), 60.0)
	Rtcc.simulate_sps_burn(tr, rt.dynamics.mass, dv)
	var h := tr.pos().cross(tr.vel()).normalized()
	var s := Rtcc.site_at(rt.sequencer.landing_site(), float(rt.mission.section("landing")["get_s"])).normalized()
	assert_almost_eq(h.dot(s), 0.0, 1e-5, "over the site at the landing time")
	assert_lt(h.dot(Bodies.moon_normal()), 0.0, "retrograde")

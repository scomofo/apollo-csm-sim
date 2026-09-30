## Slice 3f's checks (docs/ROADMAP.md, milestone 3): every checklist in
## data/missions/apollo_11/lm_checklists.json flown as a player at the
## desktop flies it (DesktopTest), until it shows complete: from Eagle's
## HUD (test_lm_checklists.gd and test_lm_checklists_rendezvous.gd), and
## from Eagle's cabin through the desktop rig (test_lm_cabin_checklists.gd
## and test_lm_cabin_checklists_rendezvous.gd, with in_cabin). The flights
## are the same: the DSKY is keyed, the switches set and the buttons
## clicked on the HUD or in the cabin, and the braking and the docking are
## flown on the hand controllers' keys; at the AOT, the P52s' marks and the
## P57's (slice 11b). Each checklist starts from its phase's start state,
## as test_lunar_mission.gd's segments do: the undocking and DOI from
## lunar_orbit, the landing from lunar_descent, the liftoff from
## lunar_surface, and the rendezvous from lunar_ascent, after the liftoff.
## The flights are the _fly_*() calls, the rendezvous's in files of its
## own for CI's parts (.github/scenario_seconds.txt).
class_name LmChecklistFlights
extends DesktopTest

## The checklists these flights fly; a checklist added to
## lm_checklists.json needs a flight here too. The malfunction procedures
## after them (data/lm_malfunctions.json) are tests/unit/test_failures.gd's.
const FLOWN := ["Undocking and DOI (P30 / P40)", "Powered descent (P63 to P68)",
	"Lunar surface and liftoff (P12)", "Rendezvous and docking (P20, P32 to P35)"]
## The braking gates, as test_rendezvous.gd flies them: the closing rate
## the commander allows from each range in, m and m/s, and a stop 40 m out.
const GATES := [[1852.0, 9.14], [914.0, 6.1], [457.0, 3.05], [152.0, 1.52], [40.0, 0.0]]


## Where the flights are flown from, for their reports.
func _from() -> String:
	return "the cabin" if in_cabin else "the HUD"


func _every_checklist_is_flown_here() -> void:
	var titles := ChecklistBook.load_lm().lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return not t.begins_with("Malfunction: "))
	assert_eq(titles, FLOWN)


func _event(id: String) -> Callable:
	return func() -> bool: return Bus.has_channel("mission.event." + id)


func _lgc_step(step: String) -> Callable:
	return func() -> bool: return rt.lgc().step_name == step


## What the LGC's DSKY shows in VERB and NOUN.
func _vn() -> Array:
	return [rt.lgc().dsky.verb, rt.lgc().dsky.noun]


func _capcom() -> String:
	return hud._capcom.get_parsed_text()


func _fly_undocking_and_doi() -> void:
	await start("lunar_orbit")
	assert_eq(main.vehicles.vehicle, "csm", "docked: in Columbia")
	assert_eq(hud.book.list().title, "Lunar orbit and TEI", "with Columbia's checklist")
	# Columbia drifts, so the day to the undocking runs fast.
	await set_switch("ctl.cmc.mode", 0)
	var go := 100.0 * 3600.0
	assert_true(await fly_until(_event("timeline_go_undocking"), go + 60.0 - SimClock.get_seconds, 3600.0), "GO for undocking")
	assert_string_contains(_capcom(), "GO for undocking")
	await click("UNDOCK", 1.0)
	await wait_process_frames(2)
	assert_eq(main.vehicles.vehicle, "lm", "aboard Eagle as it undocks")
	assert_eq(hud.book.list().title, FLOWN[0], "with its checklist for lunar orbit")
	if in_cabin:
		assert_eq(cabin(), main.lm_cabin, "in Eagle's cabin")
	await expect_step("LGC MODE - FREE: drift to DOI")
	await set_switch("ctl.lm.mode", 0)
	await expect_step("Mission Control: the DOI PAD")
	assert_true(await fly_until(_event("pad_doi"), 900.0, 60.0), "the DOI PAD")
	assert_string_contains(_capcom(), "uplinking DOI PAD")
	var lgc := rt.lgc()
	await expect_step("V37E 30E")
	await type("V37E30E")
	await expect_step("Verify TIG (N33)")
	assert_eq(_vn(), ["06", "33"], "P30 shows TIG")
	await type("PPP")
	assert_true(lgc.maneuver_valid, "TIG and ΔV accepted")
	var tig := lgc.maneuver_tig
	# The flight's stars at 101:15, Acrux and Antares (MSC-00171, Table
	# 9.6-I).
	var p52 := await _fly_p52([25, 33])
	gut.p("P52 after undocking from %s: N05 %.3f, N93 %s" % [_from(), p52["sad"], p52["torque"]])
	assert_lt(float(p52["sad"]), 0.05, "N05 as small as the flown 0.03")
	await expect_step("Houston: GO for DOI")
	assert_true(await fly_until(_event("timeline_go_doi"), tig - SimClock.get_seconds, 600.0), "GO for DOI")
	await expect_step("LGC MODE - AUTO")
	await fly(tig - 900.0 - SimClock.get_seconds, 60.0)
	await set_switch("ctl.lm.mode", 2)
	await expect_step("V37E 40E")
	await type("V37E40E")
	await expect_step("V50N18 flashing")
	assert_eq(_vn(), ["50", "18"], "asks to maneuver to the burn attitude")
	await type("P")
	await expect_step("ENG ARM - DES")
	await set_switch("ctl.lm.engine_arm", 2)
	await expect_step("At TIG-5 s V99N40")
	await fly(tig - 12.0 - SimClock.get_seconds, 60.0, false)
	assert_true(await fly_until(_lgc_step("v99"), 10.0, 1.0, false), "V99 at TIG-5 s")
	assert_eq(_vn(), ["99", "40"], "asks for engine-on enable")
	await type("P")
	assert_true(await fly_until(_lgc_step("burn"), 10.0, 0.5, false), "ignition at TIG")
	await expect_step("Monitor V16N40")
	assert_true(await fly_until(_lgc_step("post"), 120.0, 1.0, false), "DPS cutoff")
	await expect_step("ENG ARM - OFF")
	await set_switch("ctl.lm.engine_arm", 0)
	await expect_step("Trim N85")
	assert_eq(_vn(), ["16", "85"], "the residuals on the DSKY")
	await type("P")
	await expect_step("LGC MODE - FREE: drift to PDI")
	await set_switch("ctl.lm.mode", 0)
	await expect_complete(FLOWN[0])
	# The pericynthion the LM will reach, flown to: the Moon's field keeps
	# the conic of the moment kilometres off it.
	var hp := Rtcc.next_periapsis_alt(rt.dynamics.lm.traj.clone()) + Bodies.R_MOON - rt.sequencer.landing_site().length()
	gut.p("DOI flown from %s: pericynthion %.0f m above the site" % [_from(), hp])
	assert_almost_eq(hp, 15240.0, 300.0, "the pericynthion 50,000 ft above the site")
	await fly(60.0)
	assert_eq(rt.sequencer.phase, "lunar_descent")
	press(KEY_L)
	await wait_process_frames(1)
	assert_eq(hud.book.list().title, "Lunar orbit and TEI", "L: Columbia's checklist where it stood")


func _fly_powered_descent_to_the_landing() -> void:
	await start("lunar_descent")
	assert_eq(main.vehicles.vehicle, "lm", "the descent starts in Eagle")
	assert_eq(hud.book.list().title, FLOWN[1], "with its checklist for the descent")
	var lgc := rt.lgc()
	await expect_step("Mission Control: the PDI PAD")
	assert_true(await fly_until(_event("pad_pdi"), 600.0, 60.0), "the PDI PAD")
	await expect_step("V37E 63E")
	await fly(float(rt.sequencer.plan["pdi_tig"]) - 600.0 - SimClock.get_seconds, 60.0)
	await type("V37E63E")
	await expect_step("Verify TIG (V06N33)")
	assert_eq(_vn(), ["06", "33"], "P63 shows its TIG")
	await type("P")
	await expect_step("LGC MODE - AUTO")
	await set_switch("ctl.lm.mode", 2)
	await expect_step("V50N18 flashing")
	await type("P")
	await expect_step("ENG ARM - DES")
	await set_switch("ctl.lm.engine_arm", 2)
	await expect_step("Houston: GO for powered descent")
	var tig := lgc.pdi_tig
	assert_true(await fly_until(_event("timeline_go_pdi"), tig - SimClock.get_seconds, 60.0), "GO for PDI")
	await expect_step("At TIG-5 s V99N68")
	await fly(tig - 12.0 - SimClock.get_seconds, 60.0, false)
	assert_true(await fly_until(_lgc_step("v99"), 10.0, 1.0, false), "V99 at TIG-5 s")
	assert_eq(_vn(), ["99", "68"])
	await type("P")
	assert_true(await fly_until(func() -> bool: return lgc.step_name == "braking", 10.0, 0.5, false), "ignition")
	await expect_step("V57E")
	# Aldrin's V57, once the radar's altitude is good: the ALT lamp out.
	assert_true(await fly_until(func() -> bool:
		return not bool(Bus.get_value("lm.dsky.lamp.alt", true)) and lgc.delta_h != 0.0, 600.0, 1.0, false),
		"the landing radar has the ground")
	await type("V57EK")
	await expect_step("High gate: P64")
	assert_true(await fly_until(func() -> bool: return lgc.program >= 64, 600.0, 1.0, false), "high gate")
	_check_lpd()
	await expect_step("P65 lands")
	assert_true(await fly_until(func() -> bool: return rt.dynamics.lm.landed, 600.0, 1.0, false), "touchdown")
	await expect_step("ENG ARM - OFF")
	assert_eq(lgc.program, 68, "P68")
	await set_switch("ctl.lm.engine_arm", 0)
	await expect_step("PRO: P00")
	await type("P")
	await expect_complete(FLOWN[1])
	assert_eq(lgc.program, 0)
	var miss := rt.dynamics.lm.landed_pos.angle_to(rt.sequencer.landing_site()) * Bodies.R_MOON
	gut.p("Landed from %s %.0f m from the site" % [_from(), miss])
	assert_lt(miss, 500.0, "at Tranquility Base")
	assert_eq(rt.sequencer.phase, "lunar_surface")


## In P64 the landing point is where the commander looks for it: seen from
## the commander's eye in Eagle's cabin (LmCabin.EYE_CDR), the site the
## LGC is landing on is as far down the window as the LPD angle N64 shows,
## and crosses the window at that mark of its scale.
func _check_lpd() -> void:
	var lgc := rt.lgc()
	var shown := int(float(lgc.noun_values(64)[0])) % 1000
	var lm := rt.dynamics.lm
	var att := lm.attitude.eci_from_body()
	var eye := lm.traj.pos() + att * (LmCabin.EYE_CDR + Vector3(Docking.lm_port_m(lm.config), 0, 0))
	var los := att.inverse() * (Bodies.moon_fixed(SimClock.get_seconds) * lgc.landing_site - eye)
	var seen := rad_to_deg(atan2(-los.x, los.z))
	gut.p("High gate: the site %.1f deg down the commander's window; N64 shows %d" % [seen, shown])
	assert_almost_eq(seen, float(shown), 1.0, "the site where N64 says to look")
	var through := LmCabin.EYE_CDR + los * ((LmCabin.FRONT_Z - LmCabin.EYE_CDR.z) / los.z)
	var window := PackedVector2Array(LmCabin.WINDOWS["CommanderWindow"])
	assert_true(Geometry2D.is_point_in_polygon(Vector2(through.y, through.x), window),
		"through the commander's window, at (%.3f, %.3f)" % [through.y, through.x])
	assert_almost_eq(through.x, LmCabin.lpd_mark(shown).x, 0.02, "on the scale, at its %d deg mark" % shown)


## From the ascent PAD in, down the surface checklist to insertion: P57
## half an hour before the liftoff (_fly_p57()), P12 twenty minutes before
## it, ABORT STAGE and ENG ARM ASC at V99, PRO, and after insertion P00 and
## free drift.
func _fly_liftoff() -> void:
	var lgc := rt.lgc()
	var tig := lgc.tig_load
	var p57 := await _fly_p57(tig)
	gut.p("P57 from %s: N05 %.3f, N93 %s" % [_from(), p57["sad"], p57["torque"]])
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.02, "the platform aligned for the ascent")
	await expect_step("V37E 12E")
	await fly(tig - 1200.0 - SimClock.get_seconds, 3600.0)
	await type("V37E12E")
	await expect_step("Verify TIG (V06N33)")
	assert_eq(_vn(), ["06", "33"], "P12 shows the liftoff time")
	await type("P")
	await expect_step("Verify targets")
	assert_eq(_vn(), ["06", "76"], "and the insertion targets")
	await type("P")
	await expect_step("LGC MODE - AUTO")
	await set_switch("ctl.lm.mode", 2)
	await expect_step("Houston: cleared for takeoff")
	assert_true(await fly_until(_event("timeline_go_liftoff"), tig - SimClock.get_seconds, 60.0), "cleared for takeoff")
	await expect_step("At TIG-5 s V99N74")
	await fly(tig - 12.0 - SimClock.get_seconds, 60.0)
	assert_true(await fly_until(_lgc_step("v99"), 10.0, 1.0, false), "V99 at TIG-5 s")
	assert_eq(_vn(), ["99", "74"])
	await click("ABORT STAGE", SimClock.FIXED_DT)
	await expect_step("ENG ARM - ASC")
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "staged")
	await set_switch("ctl.lm.engine_arm", 1)
	await expect_step("PRO: liftoff")
	await type("P")
	assert_true(await fly_until(_event("lm_liftoff"), 10.0, 1.0, false), "liftoff")
	await expect_step("Monitor V16N94")
	assert_true(await fly_until(_event("lm_insertion"), 900.0, 5.0, false), "insertion")
	await expect_step("ENG ARM - OFF")
	await set_switch("ctl.lm.engine_arm", 0)
	await expect_step("PRO: P00")
	await type("P")
	await expect_step("LGC MODE - FREE: drift to CSI")
	await set_switch("ctl.lm.mode", 0)
	await expect_complete(FLOWN[2])


func _fly_lunar_surface_to_orbit() -> void:
	await start("lunar_surface")
	assert_eq(hud.book.list().title, FLOWN[2], "Eagle's checklist for the surface")
	await expect_step("Houston: STAY for T3")
	assert_true(await fly_until(_event("timeline_stay_t3"), 7200.0, 600.0), "STAY for T3")
	await expect_step("Mission Control: the ascent PAD")
	assert_true(await fly_until(_event("pad_ascent"), 24.0 * 3600.0, 3600.0), "the ascent PAD")
	assert_string_contains(_capcom(), "your ascent PAD")
	await _fly_liftoff()
	var c := rt.dynamics.lm.traj.conic()
	var site_r := rt.sequencer.landing_site().length()
	var alts := Vector2(float(c["rp"]) - site_r, float(c["ra"]) - site_r) / Units.NMI
	gut.p("Inserted from %s into %.1f x %.1f nmi" % [_from(), alts.x, alts.y])
	assert_almost_eq(alts.x, 9.0, 1.0, "9 nmi perilune")
	assert_almost_eq(alts.y, 45.0, 2.0, "45 nmi apolune")
	assert_eq(rt.sequencer.phase, "lunar_ascent")


## Down the checklist's P52 (slice 11a): option 3, on [param stars] loaded
## by hand in the front detent (ENTER at V50N25 00015), as the crew chose
## them; for each the maneuver in AUTO (V50N18, ENTER at its end) and, at
## the AOT, the star put on its Y-line and MARK Y, on its X-line and MARK
## X, PRO; PRO at N05 and N93, ENTER for P00, and FREE unless
## [param free] is false (P20 follows the P52 after insertion in AUTO).
## Returns {"sad": N05, "torque": N93}.
func _fly_p52(stars: Array, free: bool = true) -> Dictionary:
	var lgc := rt.lgc()
	await expect_step("V37E 52E")
	await type("V37E52E")
	await type("V22E3EP")
	await type("E")
	await expect_step("Each star")
	for i in 2:
		assert_eq(lgc.step_name, "n70", "V01N70 for star %d" % (i + 1))
		await type("V21E%05dEE" % (LgcAlign.FRONT * 100 + int(stars[i])))
		await type("P")
		if i == 0:
			await set_switch("ctl.lm.mode", 2)
		await type("P")
		assert_true(await fly_until(_lgc_step("v50n18"), 600.0, 1.0, false), "the LGC turned Eagle to star %d" % (i + 1))
		await type("E")
		await type("P")
		assert_eq(lgc.step_name, "marks", "V54N71")
		if i == 0:
			await expect_step("At the AOT")
		var code := lgc.align.star()
		var d := lgc.align.detent()
		await _set_detent(d)
		await _aot(true)
		put_star_in_aot(code, d, Vector2(0.0, 1.0))
		await click("MARK Y", SimClock.FIXED_DT)
		put_star_in_aot(code, d, Vector2(1.0, 0.0))
		await click("MARK X", SimClock.FIXED_DT)
		await _aot(false)
		await type("P")
	await expect_step("V06N05")
	assert_eq(_vn(), ["06", "05"], "the star angle difference")
	var out := {"sad": lgc.align.sad_deg}
	await type("P")
	var n93: Array = lgc.noun_values(93)
	out["torque"] = Vector3(n93[0], n93[1], n93[2])
	await type("P")
	await type("E")
	assert_eq(lgc.program, 0, "P00")
	if free:
		await expect_step("LGC MODE - FREE")
		await set_switch("ctl.lm.mode", 0)
	return out


## Down the surface checklist's P57 (slice 11b), half an hour before the
## liftoff at [param tig]: option 4 and TALIGN the liftoff; technique 3,
## gravity read (PRO at V06N04) and the coarse align back (PRO at V06N22);
## a star R59 finds (AotCrew.surface_stars()), PRO at V06N79 and V01N71;
## at the AOT the detent R59 gave, MARK Y, and the counter's readings
## loaded, V21 the cursor and V22 the spiral; PRO at N05 and N93, ENTER for
## P00. Returns {"sad": N05, "torque": N93}.
func _fly_p57(tig: float) -> Dictionary:
	var lgc := rt.lgc()
	await expect_step("V37E 57E")
	await fly(tig - 1980.0 - SimClock.get_seconds, 3600.0)
	await type("V37E57E")
	await type("V22E4EP")
	assert_eq(_vn(), ["06", "34"], "TALIGN")
	await type("P")
	await expect_step("V05N06")
	await type("V22E3EP")
	assert_true(await fly_until(_lgc_step("n04"), 300.0, 1.0, false), "gravity read")
	await type("P")
	await expect_step("V06N22")
	await type("P")
	assert_true(await fly_until(_lgc_step("n70"), 120.0, 1.0, false), "the coarse align back")
	var star := int(AotCrew.surface_stars(self)[0])
	await type("V21E%05dEEP" % star)
	assert_eq(_vn(), ["06", "79"], "R59's detent, cursor and spiral")
	await type("P")
	await type("P")
	await expect_step("At the AOT")
	var d := int(lgc.surface.aotcode / 100.0)
	await _set_detent(d)
	await _aot(true)
	await click("MARK Y", SimClock.FIXED_DT)
	var r := AotCrew.reticle_readings(self, star, d)
	await type("V21E+%05dE" % roundi(r.x * 100.0))
	await type("V22E+%05dE" % roundi(r.y * 100.0))
	await _aot(false)
	await type("P")
	await expect_step("V06N05")
	var out := {"sad": lgc.surface.sad_deg}
	await type("P")
	var n93: Array = lgc.noun_values(93)
	out["torque"] = Vector3(n93[0], n93[1], n93[2])
	await type("P")
	await type("E")
	assert_eq(lgc.program, 0, "P00")
	return out


## The AOT's detent knob to detent [param d]: its HUD knob, or the cabin's.
func _set_detent(d: int) -> void:
	if in_cabin:
		await set_switch("ctl.lm.aot.detent", d)
		return
	var o: OptionButton = hud._aot_detent
	o.select(d - 1)
	o.item_selected.emit(d - 1)
	assert_eq(int(Bus.get_value("ctl.lm.aot.detent")), d, "the detent")


## At the AOT ([param open]) or away from it: its HUD panel (O); in the
## cabin its buttons are overhead.
func _aot(open: bool) -> void:
	if not in_cabin and hud.aot_open() != open:
		press(KEY_O)
		await wait_process_frames(1)


## The commander's braking on the TTCA's keys, as test_rendezvous.gd's
## _brake(): each second, hold the closing rate to the gate for the range
## and null the line of sight's drift, until Eagle has stopped 40 m from
## Columbia. Returns whether it did.
func _brake(max_s: float) -> bool:
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		var lm := rt.dynamics.lm.traj
		var rel := Rendezvous.rel_pos(lm, rt.dynamics.traj)
		var vrel := Rendezvous.rel_vel(lm, rt.dynamics.traj)
		var rng := rel.length()
		var u := rel / rng
		var closing := -vrel.dot(u)
		if rng <= 45.0 and vrel.length() < 0.02:
			return true
		var gate := INF
		for g in GATES:
			if rng <= float(g[0]):
				gate = float(g[1])
		var dv := Vector3.ZERO
		if rng <= 45.0:
			dv = vrel
		else:
			if closing > gate + 0.1:
				dv -= u * (closing - gate)
			var drift := vrel - u * vrel.dot(u)
			if drift.length() > 0.03 + rng * 1e-4:
				dv += drift
		if dv != Vector3.ZERO:
			await translate(body_axes().inverse() * dv)
		await fly(1.0, 1.0, false)
	return false


## Fly the maneuver the LGC has stored on P41 where Eagle is, down the
## rendezvous checklist, as Apollo 11's crew burned theirs with +Z on
## Columbia: P41 ten minutes before TIG (or at once, closer in), ENTER at
## V50N18 for no maneuver, PRO at V99, and PRO after cutoff. Returns the
## ΔV flown, m/s.
func _fly_p41() -> float:
	var lgc := rt.lgc()
	var tig := lgc.maneuver_tig
	await fly(maxf(tig - 600.0 - SimClock.get_seconds, 0.0), 600.0)
	await type("V37E41E")
	assert_eq(lgc.program, 41, "P41")
	await type("E")
	assert_true(lgc.burn_in_place, "no maneuver: where Eagle is")
	await fly(tig - 12.0 - SimClock.get_seconds, 60.0)
	assert_true(await fly_until(_lgc_step("v99"), 10.0, 1.0, false), "V99 at TIG-5 s")
	await type("P")
	assert_true(await fly_until(_lgc_step("post"), 300.0, 1.0, false), "RCS cutoff")
	var dv := lgc.dv_accum
	await expect_step("Trim N85")
	await type("P")
	await wait_process_frames(1)
	assert_false(lgc.maneuver_valid, "done with it")
	return dv


## Fly on until P20 has weighed in [param n] marks, or to GET [param t].
func _marks(n: int, t: float) -> void:
	var lgc := rt.lgc()
	await fly_until(func() -> bool: return lgc.p20.marks >= n, t - SimClock.get_seconds, 10.0)


## V32 at V16N45: the rendezvous program's solution again, PRO'd through
## to N45 (P34's from its TIG's N37, P35's from N81).
func _recycle() -> void:
	var lgc := rt.lgc()
	await type("V32E")
	if lgc.program == 34:
		await type("P")
	await type("P" if lgc.program == 35 else "PP")
	assert_eq(lgc.step_name, "n45", "P%d recycled to V16N45" % lgc.program)


func _fly_rendezvous_and_docking() -> void:
	await start("lunar_ascent")
	assert_eq(hud.book.list().title, FLOWN[2], "on the surface: the liftoff's checklist")
	await _fly_liftoff()
	await open_checklist(FLOWN[3])
	var lgc := rt.lgc()
	await expect_step("Mission Control: the CSI PAD")
	assert_true(await fly_until(_event("pad_csi"), 600.0, 60.0), "the CSI PAD")
	var pad: Dictionary = rt.sequencer.pads["csi"]
	# The flight's after insertion, at 124:51: Rigel and Acrux (ibid.).
	var p52 := await _fly_p52([12, 25], false)
	gut.p("P52 after insertion from %s: N05 %.3f, N93 %s" % [_from(), p52["sad"], p52["torque"]])
	# P20 as the G mission's procedures had it (SimTest.start_p20()).
	await expect_step("RNDZ RADAR - LGC")
	await set_switch("ctl.lm.rr_mode", 0)
	# LGC MODE is AUTO from the P52's turns: its step checks itself off.
	assert_eq(int(Bus.get_value("ctl.lm.mode", 0)), 2, "LGC MODE still AUTO")
	await expect_step("V95E")
	await type("V95E")
	await type("V67E")
	assert_eq(_vn(), ["06", "99"], "V06N99")
	await type("V25N99E+10000E+00100E+00015E")
	await type("P")
	await expect_step("V37E 20E")
	await type("V37E20E")
	if lgc.p20.phase == "r61":
		await type("P")
	assert_true(await fly_until(func() -> bool: return lgc.p20.phase == "n72", 600.0, 1.0, false), "the radar locked on")
	await expect_step("V50N72")
	await type("P")
	# From the lock-on the crew's standing answers take over: PRO at each
	# N49, and at R61's and R21's displays again (SimTest.lm_crew()).
	lm_crew()
	await fly(20.0, 20.0, false)
	await expect_step("V80E")
	await type("V80E")
	await expect_step("V37E 32E")
	var tig := float(pad["tig"])
	await fly(tig - 1500.0 - SimClock.get_seconds, 600.0)
	await type("V37E32E")
	assert_eq(_vn(), ["06", "11"], "P32: CSI's TIG")
	await type("PPP")
	assert_eq(_vn(), ["06", "75"], "ΔH and the times to CDH and TPI")
	await type("PP")
	# Houston's GO, 12 min 48 s before CSI as Apollo 11's, comes between
	# the recycle at 10 marks and the final computation.
	await expect_step("Houston: GO for CSI")
	await _marks(10, tig - 720.0)
	await _recycle()
	await fly(tig - 720.0 - SimClock.get_seconds, 60.0)
	assert_true(await fly_until(_event("timeline_go_csi"), 60.0, 1.0), "GO for CSI")
	await expect_step("At 10 marks")
	await _recycle()
	await type("P")
	assert_true(lgc.maneuver_valid, "CSI stored")
	await expect_step("V37E 41E - P41 RCS Thrusting")
	var burns := {"CSI": await _fly_p41()}
	await expect_step("V37E 33E")
	await type("V37E33EP")
	assert_eq(_vn(), ["06", "75"], "P33: V06N75")
	await type("PP")
	var cdh := lgc.rdv_cdh_tig
	await expect_step("At 4 marks V67E")
	await _marks(4, cdh - 900.0)
	await type("V67E")
	await type("V25N99E+02000E+00020E+00005E")
	await type("P")
	await expect_step("V32E at 3 and at 10 marks")
	for m in [3, 10]:
		await _marks(m, cdh - 900.0)
		await _recycle()
	await fly(cdh - 720.0 - SimClock.get_seconds, 60.0)
	await _recycle()
	await type("P")
	await expect_step("V37E 41E - P41 for CDH")
	burns["CDH"] = await _fly_p41()
	await expect_step("V37E 34E")
	await fly(float(pad["tpi_get"]) - 1800.0 - SimClock.get_seconds, 600.0)
	await type("V37E34EP")
	assert_eq(_vn(), ["06", "37"], "P34: TPI's time")
	await type("P")
	assert_eq(_vn(), ["06", "58"])
	await type("PP")
	await expect_step("At 4 marks V93E")
	await _marks(4, lgc.rdv_tpi_tig - 900.0)
	await type("V93E")
	await expect_step("V32E at 3 and at 10 marks")
	for m in [3, 10]:
		await _marks(m, lgc.rdv_tpi_tig - 900.0)
		await _recycle()
	await fly(lgc.rdv_tpi_tig - 720.0 - SimClock.get_seconds, 60.0)
	await _recycle()
	await type("P")
	await expect_step("V37E 41E - P41 for TPI")
	var tpi_tig := lgc.maneuver_tig
	burns["TPI"] = await _fly_p41()
	# Each midcourse correction's P35 from the burn before on, so that its
	# marks weigh in, and its final computation a P35 lead (TIG from then)
	# before the flight's time for it (SimTest.lm_coelliptic()).
	var lead := float(SpacecraftData.section("rendezvous_guidance")["tpm_lead_s"])
	for which in ["first", "second"]:
		await expect_step("V93E before the first mark")
		await type("V93E")
		await expect_step("V37E 35E - P35 %s midcourse" % which)
		await type("V37E35EP")
		var after: float = rt.mission.section("rendezvous")["tpm_after_tpi_s"][burns.size() - 3]
		await expect_step("%d min after TPI V32E" % roundi((after - lead) / 60.0))
		await fly(tpi_tig + after - lead - SimClock.get_seconds, 60.0)
		await _recycle()
		await type("P")
		await expect_step("V37E 41E - P41; ENTER")
		burns["TPM%d" % burns.size()] = await _fly_p41()
	await expect_step("Inside 18,000 ft")
	await fly_until(func() -> bool: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).length() < 18000.0 * Units.FT,
		1800.0, 10.0)
	await type("V56E")
	await set_switch("ctl.lm.rr_mode", 1)
	await expect_step("Braking by the gates")
	var t_brake := SimClock.get_seconds
	assert_true(await _brake(1800.0), "braked on the keys to station-keeping")
	gut.p("From %s: CSI %.1f ft/s (PAD %.1f), CDH %.1f, TPI %.1f (PAD %.1f), midcourses %.1f and %.1f ft/s; braking %.0f s" % [
		_from(), burns["CSI"] / Units.FT, float(pad["dv"]) / Units.FT, burns["CDH"] / Units.FT, burns["TPI"] / Units.FT,
		float(pad["tpi_dv"]) / Units.FT, burns["TPM3"] / Units.FT, burns["TPM4"] / Units.FT, SimClock.get_seconds - t_brake])
	await expect_step("Face Columbia")
	# Eagle turns its docking port to Columbia; then, L, Collins turns
	# Columbia's probe to Eagle and flies it into the drogue.
	assert_true(await face(func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj)), "Eagle faces Columbia")
	press(KEY_L)
	await wait_process_frames(1)
	assert_eq(main.vehicles.vehicle, "csm", "L: in Columbia")
	await set_switch("ctl.cmc.mode", 1)
	assert_true(await face(func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj)), "Columbia faces Eagle")
	await _move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(await _approach(0.1), "the probe met the drogue")
	var c := dock_contact()
	gut.p("Docked from %s at %s: %s" % [_from(), Units.hms(SimClock.get_seconds), Docking.describe(c)])
	assert_true(c["captured"], "within the capture limits")
	await wait_process_frames(1)
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	assert_eq(hud.lm_book.list().title, FLOWN[3])
	assert_true(hud.lm_book.list().done(), "Eagle's last step checked itself off as they docked")
	assert_eq(hud.book, main.book, "the HUD on Columbia's checklists")
	assert_eq(hud.book.list().title, "Lunar orbit and TEI")
	assert_almost_eq(burns["CSI"], float(pad["dv"]), 0.5, "CSI flown")
	# P20's filter (slice 11d) on the radar's errors drawn for Apollo 11:
	# TPI and the midcourse corrections within test_rendezvous.gd's limits.
	assert_almost_eq(burns["TPI"], float(pad["tpi_dv"]), 1.0, "TPI flown within 1 m/s of the PAD's")
	assert_lt(burns["TPM3"] + burns["TPM4"], 2.5, "midcourse corrections within 2.5 m/s together")


## Stop Columbia relative to Eagle on the THC's keys.
func _null_rates() -> void:
	for i in 2:
		await translate(dock_rel_vel())


## Bring Eagle's port to [param target] (Columbia's body axes) in about
## [param seconds] on the THC's keys, as SimTest.csm_move_to().
func _move_to(target: Vector3, seconds: float) -> void:
	for i in 2:
		await _null_rates()
		await translate((dock_rel_pos() - target) / seconds)
		await fly(seconds - 1.0, 1.0, false)
	await _null_rates()


## Close on Eagle at [param speed] on the THC's keys, as
## SimTest.csm_approach(): every second, trim the closing speed and steer
## the drogue back onto the probe's axis. Returns once the probe has met
## the drogue.
func _approach(speed: float, max_s: float = 300.0) -> bool:
	Bus.set_value("dock.contact", {})
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		if not dock_contact().is_empty():
			return true
		var p := dock_rel_pos()
		var want := Vector3(-speed, -p.y / 5.0, -p.z / 5.0).clamp(-Vector3.ONE * speed, Vector3.ONE * speed)
		await translate(dock_rel_vel() - want)
		await fly(1.0, 1.0, false)
	return false

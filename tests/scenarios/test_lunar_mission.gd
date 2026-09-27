extends SimTest
## The lunar mission flown through the crew interface: every burn is an
## RTCC PAD uplinked to the CMC and executed with P30/P40 on the DSKY.


func _moon_alts() -> Vector2:
	var c := rt.dynamics.traj.conic()
	return Vector2(float(c["rp"]) - Bodies.R_MOON, float(c["ra"]) - Bodies.R_MOON) / 1000.0


func test_midcourse_correction_and_lunar_orbit_insertion() -> void:
	build("translunar_coast")
	assert_eq(rt.sequencer.phase, "translunar_coast")
	var mcc := rt.sequencer.request_pad("mcc")
	if not mcc.is_empty():
		gut.p("MCC " + Rtcc.pad_text(mcc))
		assert_true(mcc["uplinked"], "the MCC PAD came up with the state vector (P27)")
		var dv := fly_pad()
		assert_almost_eq(dv, float(mcc["dv"]), 0.5, "MCC ΔV flown")
	# Coast to about 8 h before pericynthion, then get the LOI PAD.
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	gut.p("pericynthion after MCC: %.1f km" % ((float(ap["rp"]) - Bodies.R_MOON) / 1000.0))
	assert_between((float(ap["rp"]) - Bodies.R_MOON) / 1000.0, 60.0, 180.0, "MCC hit the pericynthion target")
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	# The coast's unmodelled forces moved the CSM off the CMC's state
	# vector; the LOI PAD's uplink takes that out.
	var drift := (rt.agc().nav.pos() - rt.dynamics.traj.pos()).length()
	var loi := rt.sequencer.request_pad("loi")
	assert_false(loi.is_empty(), "LOI solution")
	gut.p("LOI " + Rtcc.pad_text(loi))
	assert_true(loi["uplinked"], "the LOI PAD came up with the state vector (P27)")
	var left := (rt.agc().nav.pos() - rt.dynamics.traj.pos()).length()
	gut.p("before the LOI PAD the CMC was %.1f km off; the uplink left it %.2f km off" % [drift / 1000.0, left / 1000.0])
	assert_gt(drift, left, "the uplink took out the coast's drift")
	assert_lt(left, 2000.0, "to MSFN's tracking error")
	assert_between(float(loi["dv"]), 800.0, 1000.0, "LOI-1 ΔV (Apollo 11: 889 m/s)")
	var sps0 := float(Bus.get_value("sps.prop_kg"))
	var dv := fly_pad()
	assert_almost_eq(dv, float(loi["dv"]), 2.0)
	run(600.0)
	assert_eq(rt.sequencer.phase, "lunar_orbit")
	var alts := _moon_alts()
	gut.p("lunar orbit %.1f x %.1f km, SPS used %.0f kg" % [alts.x, alts.y, sps0 - float(Bus.get_value("sps.prop_kg"))])
	assert_between(alts.x, 60.0, 180.0, "perilune")
	assert_between(alts.y, 250.0, 400.0, "apolune (target 315 km)")
	# LOI-2 circularization.
	var circ := rt.sequencer.request_pad("circ")
	assert_false(circ.is_empty())
	fly_pad()
	alts = _moon_alts()
	gut.p("after LOI-2 %.1f x %.1f km" % [alts.x, alts.y])
	assert_lt(alts.y - alts.x, 60.0, "near-circular after LOI-2")
	assert_gt(alts.x, 30.0)


func test_transearth_injection_targets_the_entry_corridor() -> void:
	build("tei")
	assert_eq(rt.dynamics.config, "csm")
	var tei := rt.sequencer.request_pad("tei")
	assert_false(tei.is_empty(), "TEI solution")
	gut.p("TEI " + Rtcc.pad_text(tei))
	fly_pad()
	run(3600.0)
	assert_eq(rt.sequencer.phase, "transearth_coast")
	var er := Rtcc.earth_return(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	var hp := (float(er["rp"]) - Bodies.R_EARTH) / 1000.0
	gut.p("vacuum perigee after TEI: %.1f km" % hp)
	assert_between(hp, -300.0, 400.0, "TEI lands near the corridor")
	# Two transearth midcourse corrections, as the flights planned (MCC-5
	# and MCC-7): the second trims what the first's execution errors left,
	# if Mission Control finds anything left to trim.
	for wait_h in [10.0, 30.0]:
		run(wait_h * 3600.0)
		var mcc := rt.sequencer.request_pad("mcc")
		if not mcc.is_empty():
			gut.p("MCC " + Rtcc.pad_text(mcc))
			fly_pad()
	er = Rtcc.earth_return(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	hp = (float(er["rp"]) - Bodies.R_EARTH) / 1000.0
	gut.p("vacuum perigee after MCCs: %.1f km" % hp)
	assert_between(hp, 25.0, 50.0, "in the entry corridor")


func test_entry_and_splashdown() -> void:
	# Apollo 11's entry, to its target 1,500 nmi from entry interface, on the
	# CMC's P61 to P67 (tests/scenarios/test_entry.gd flies a shorter and a
	# longer range).
	build("entry")
	assert_eq(rt.dynamics.config, "csm")
	var f := fly_entry()
	var peaks: Array = f["peaks"]
	gut.p("programs %s, peaks %s g, N67 %s; max g %.2f, splash %.1f m/s at %s, %.2f nmi from the target; events %s" % [
		str(f["programs"]), str(peaks.map(func(x: float) -> float: return snappedf(x, 0.01))), str(f["n67"]),
		rt.dynamics.max_g, rt.dynamics.landed_speed, Units.hms(SimClock.get_seconds),
		float(Bus.get_value("mission.splash_miss_nmi", -1.0)), str(rt.sequencer.events.map(func(e): return e["id"]))])
	assert_true(rt.dynamics.landed, "reached the surface")
	assert_eq(rt.sequencer.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_true(rt.sequencer._has("phase_entry"))
	# "You'll get P65, but no P66" (the entry PAD's remarks, 191:43:57)
	# [published]: the up-control, then the final phase.
	assert_eq(f["programs"], [61, 62, 63, 64, 65, 67, 0], "P65 and no P66")
	# "Our first peak pulse was 6.5 [g] ... and the second one was 6.0"
	# (Armstrong, the technical debrief) [published].
	assert_almost_eq(float(peaks[0]), 6.5, 0.3, "the first peak")
	assert_almost_eq(float(peaks[1]), 6.0, 0.4, "the second, as P67 dumps the range to spare")
	# Down 1.7 nmi from the target by the CMC's reckoning, 13.30 N 169.15 W
	# (the Apollo 11 Mission Report, MSC-00171), at 195:18:35 [published].
	assert_lt(float(Bus.get_value("mission.splash_miss_nmi")), 3.0, "near the target")
	assert_almost_eq(SimClock.get_seconds, MissionSequencer._get_s("195:18:35"), 120.0, "splashdown's time")
	assert_lt(rt.dynamics.landed_speed, 12.0, "main-chute touchdown")

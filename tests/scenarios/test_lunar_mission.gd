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
		var dv := fly_pad()
		assert_almost_eq(dv, float(mcc["dv"]), 0.5, "MCC ΔV flown")
	# Coast to about 8 h before pericynthion, then get the LOI PAD.
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	gut.p("pericynthion after MCC: %.1f km" % ((float(ap["rp"]) - Bodies.R_MOON) / 1000.0))
	assert_between((float(ap["rp"]) - Bodies.R_MOON) / 1000.0, 60.0, 180.0, "MCC hit the pericynthion target")
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	var loi := rt.sequencer.request_pad("loi")
	assert_false(loi.is_empty(), "LOI solution")
	gut.p("LOI " + Rtcc.pad_text(loi))
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
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
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
	# and MCC-7): the second trims what the first's execution errors left.
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
	build("entry")
	assert_eq(rt.dynamics.config, "csm")
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(1.0, false)
	assert_eq(rt.dynamics.config, "cm")
	keys("V37E61E")
	assert_eq(rt.agc().program, 61)
	Bus.set_value("ctl.els.logic", true)
	Bus.set_value("ctl.els.auto", true)
	var landed := run_until(func() -> bool: return rt.dynamics.landed, 3.0 * 3600.0, 60.0)
	assert_true(landed, "reached the surface")
	gut.p("max g %.2f, splash %.1f m/s, events %s" % [rt.dynamics.max_g, rt.dynamics.landed_speed,
		str(rt.sequencer.events.map(func(e): return e["id"]))])
	assert_eq(rt.sequencer.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_between(rt.dynamics.max_g, 3.0, 8.0, "entry load")
	assert_lt(rt.dynamics.landed_speed, 12.0, "main-chute touchdown")
	assert_true(rt.sequencer._has("phase_entry"))

extends SimTest


func test_saturn_iu_flies_tli_and_reaches_the_moon() -> void:
	build("parking_orbit")
	var seq := rt.sequencer
	assert_eq(seq.phase, "parking_orbit")
	assert_false(seq.tli_pad.is_empty(), "RTCC found a TLI opportunity")
	var tig := float(seq.tli_pad["tig"])
	assert_between(tig / 3600.0, 2.3, 3.2, "TLI near the flown 2:44 GET")
	assert_true(run_until(func() -> bool: return seq._has("tli_cutoff"), tig - SimClock.get_seconds + 600.0, 60.0))
	var ign: float = Bus.get_value("mission.event.tli_ignition")
	assert_almost_eq(ign, tig, 0.05, "ignition on the planned TIG")
	var burn := float(Bus.get_value("mission.event.tli_cutoff")) - ign
	assert_between(burn, 250.0, 350.0, "J-2 burn duration")
	assert_eq(seq.phase, "translunar_coast")
	assert_gt(float(Bus.get_value("dyn.apo_alt_m")), 3.0e8, "apogee beyond the Moon's orbit")
	# Crew separates, T&D.
	Bus.set_value("ctl.seq.csm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.csm_sep", false)
	assert_eq(rt.dynamics.config, "csm_lm")
	# Coast to the Moon and compare with the plan.
	var planned := float(seq.tli_pad["pericynthion_get"])
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, planned + 86400.0)
	gut.p("predicted pericynthion %.0f km at %s (plan %s)" % [(float(ap["rp"]) - Bodies.R_MOON) / 1000.0,
		Units.hms(float(ap["t"])), Units.hms(planned)])
	assert_true(ap["reached"])
	assert_lt(absf(float(ap["t"]) - planned), 1800.0, "arrival time within 30 min of plan")
	assert_lt(float(ap["rp"]) - Bodies.R_MOON, 3000000.0, "passes within 3000 km: MCC can trim it")
	assert_false(ap["impact"])

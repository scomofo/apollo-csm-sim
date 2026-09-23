## Slice 2c's check (docs/ROADMAP.md): a midcourse correction PAD flown with
## P30 and P41 (P40 if it is 10 ft/s or more) using only the cabin's
## controls, each one clicked through the desktop rig from the commander's
## couch (CabinTest): the rig looks at the control, and a left click goes
## through its input handling to ControlBase.actuate_far(). Mission
## Control's uplink and the time rate come from outside the cabin, as they
## do in the 2D HUD.
extends CabinTest


func test_mcc_pad_flown_from_the_cabin() -> void:
	build("translunar_coast")
	await setup_cabin()
	var agc := rt.agc()
	# The coast starts on target, so no MCC would be needed: give TLI a
	# cutoff error of 0.8 m/s short, which misses the pericynthion target by
	# more than the RTCC's 20 km tolerance.
	var tr := rt.dynamics.traj
	tr.set_state(tr.primary, tr.t, tr.pos(), tr.vel() - tr.vel().normalized() * 0.8)
	rt.dynamics.publish_state()
	# Mission Control uplinks the PAD, as the HUD's MCC button asks it to.
	Bus.set_value("ctl.ground.pad_request", "mcc")
	var pad: Dictionary = rt.sequencer.last_pad
	assert_false(pad.is_empty(), "an MCC solution")
	gut.p("MCC " + Rtcc.pad_text(pad))
	await switch_to("P1_CMC_MODE", 2)
	assert_eq(Bus.get_value("ctl.cmc.mode"), 2, "CMC MODE AUTO")
	await type("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	assert_eq([dsky.fields["prog"].text, dsky.fields["verb"].text, dsky.fields["noun"].text], ["30", "06", "33"],
		"the cabin DSKY asks for TIG")
	await type("PPP")
	assert_true(agc.maneuver_valid, "TIG, ΔV and the apsides accepted; maneuver stored")
	var prog := 41 if agc.dv_lvlh_load.length() < 10.0 * Units.FT else 40
	gut.p("flying it with P%d" % prog)
	await type("V37E%dE" % prog)
	assert_eq(agc.program, prog, "P%d selected" % prog)
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["50", "18"], "asks to maneuver to the burn attitude")
	await type("P")
	await switch_to("P1_DV_THRUST_A", 1)
	await switch_to("P1_DV_THRUST_B", 1)
	assert_true(Bus.get_value("ctl.sps.arm_a") == true and Bus.get_value("ctl.sps.arm_b") == true, "ΔV THRUST A and B NORMAL")
	var tig := agc.maneuver_tig
	var ok := run_until(func() -> bool: return agc.step_name == "v99", tig - SimClock.get_seconds + 10.0, 30.0)
	assert_true(ok, "reached V99 before TIG")
	assert_true(SimClock.controls_locked(), "still at 1000x")
	await click(cabin.items["P1_DV_THRUST_A"])
	assert_eq(Bus.get_value("ctl.sps.arm_a"), true, "switches don't move while time runs fast")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["99", "40"], "asks for engine-on enable")
	await type("P")
	ok = run_until(func() -> bool: return agc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	assert_eq(dsky.fields["noun"].text, "85", "residuals")
	var dv := agc.dv_accum
	await type("P")
	await switch_to("P1_DV_THRUST_A", 0)
	await switch_to("P1_DV_THRUST_B", 0)
	await switch_to("P1_CMC_MODE", 1)
	assert_almost_eq(dv, float(pad["dv"]), 0.5, "MCC ΔV flown")
	assert_eq(agc.program, 0, "back in P00")
	assert_eq([Bus.get_value("ctl.sps.arm_a"), Bus.get_value("ctl.sps.arm_b"), Bus.get_value("ctl.cmc.mode")], [false, false, 1],
		"SPS safed, CMC MODE HOLD")

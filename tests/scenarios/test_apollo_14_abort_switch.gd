## Slice 12a's second part (docs/ROADMAP.md, milestone 12): Antares's ABORT
## switch, its contacts to the LGC shorted by a particle in it (the failure
## catalog's lm_abort_switch). From the lunar_descent start, 20 min before
## PDI, the crew fly P63 to its ignition as tests/scenarios/test_apollo_14.gd's
## do. Before PDI channel 30 shows the short (V11N10E 30E) and a tap on the
## panel clears it. Without the workaround, the short after the throttle-up
## starts P70, the descent engine at full thrust for the abort's insertion.
## With it keyed at the flown times (AbortSwitchCrew), P63 holds its
## attitude at 10 % past ZOOM until the commander's throttle-up and the
## crew's ZOOMFLAG, and the short, the pushbutton itself too, leave it
## flying [published: MSC-04112, pp. 8-10, 8-11 and section 14.2.2].
extends SimTest


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## Apollo 14's descent from the lunar_descent start to P63's ignition, the
## workaround's first entry keyed before it with [param workaround].
func _to_ignition(workaround: bool) -> Lgc:
	build("lunar_descent", "apollo_14")
	var sq := rt.sequencer
	var lgc := rt.lgc()
	run(float(sq.plan["pdi_tig"]) - 600.0 - SimClock.get_seconds)
	keys("V37E63E", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	if workaround:
		AbortSwitchCrew.before_pdi(self)
		assert_eq([lgc.erasable.modreg, lgc.dsky.prog, lgc.program], [71, "71", 63], "MODREG 71 on PROG, P63 running")
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	return lgc


func _fail_switch() -> void:
	assert_true(rt.failures.recur("lm_abort_switch"), "the switch shorted")


func test_channel_30_shows_the_short_and_a_tap_clears_it() -> void:
	build("lunar_descent", "apollo_14")
	var lgc := rt.lgc()
	assert_true(rt.failures.active.has("lm_abort_switch"), "the switch shorted on the way, at the flown times")
	assert_false(lgc.abort_short, "and the start takes it up tapped clear")
	# The start's uplink done (UPLINK ACTY out, the DSKY back to P00's).
	run(5.0, false)
	_fail_switch()
	run(1.0, false)
	assert_true(bool(Bus.get_value("lm.lgc.abort_bit")), "the LGC sees ABORT")
	keys("V11N10E30E", lgc)
	run(1.0, false)
	assert_eq([lgc.dsky.verb, lgc.dsky.noun], ["11", "10"], "V11N10 monitoring channel 30")
	assert_eq(lgc.dsky.r[0].strip_edges().to_int() % 2, 0, "its last digit even: bit 1, ABORT, present")
	Bus.set_value("ctl.lm.panel_tap", true)
	run(0.2, false)
	Bus.set_value("ctl.lm.panel_tap", false)
	run(1.0, false)
	assert_false(bool(Bus.get_value("lm.lgc.abort_bit")), "a tap on the panel clears it")
	assert_eq(lgc.dsky.r[0].strip_edges().to_int() % 2, 1, "and bit 1 is back")
	# It comes back: the switch still holds its particle.
	_fail_switch()
	run(0.2, false)
	assert_true(bool(Bus.get_value("lm.lgc.abort_bit")), "the short again")
	Bus.set_value("ctl.lm.abort", true)
	run(0.2, false)
	Bus.set_value("ctl.lm.abort", false)
	run(0.2, false)
	assert_false(bool(Bus.get_value("lm.lgc.abort_bit")), "the pushbutton's press clears it too")
	assert_false(lgc.program in Lgc.ABORTS, "no abort before PDI")


func test_the_short_after_the_throttle_up_aborts_the_landing() -> void:
	var lgc := _to_ignition(false)
	var t_ign := lgc.pdi_tig
	run(t_ign + 40.0 - SimClock.get_seconds, false)
	assert_eq([lgc.program, lgc.erasable.modreg], [63, 63], "P63")
	assert_true(lgc.erasable.letabort, "the aborts enabled since ignition")
	assert_true(lgc.erasable.zoomflag, "ZOOM at 26 s: full thrust and the guidance steering")
	_fail_switch()
	run(0.2, false)
	assert_eq(lgc.program, 70, "P70: the landing aborted")
	run(2.0, false)
	assert_gt(float(Bus.get_value("lm.dps.throttle_pct")), 90.0, "the descent engine at full thrust")


func test_the_workaround_flies_p63_through_the_short() -> void:
	var lgc := _to_ignition(true)
	var t_ign := lgc.pdi_tig
	var att := lgc.auto_target
	var done := {}
	run(t_ign + 27.0 - SimClock.get_seconds, false)
	# ZOOM came with MODREG at 71: no throttle-up, no steering.
	assert_false(lgc.erasable.zoomflag, "no ZOOMFLAG")
	assert_lt(float(Bus.get_value("lm.dps.throttle_pct")), 15.0, "the engine at the trim's 10 %")
	assert_lt(rad_to_deg(att.angle_to(lgc.auto_target)), 0.01, "the attitude held")
	var keyed := func() -> bool: return AbortSwitchCrew.after_ignition(self, SimClock.get_seconds - t_ign, done)
	assert_true(run_until(func() -> bool:
		keyed.call()
		return SimClock.get_seconds - t_ign >= 30.0, 5.0, 0.1, false))
	assert_gt(float(Bus.get_value("lm.dps.throttle_pct")), 90.0, "the commander's throttle-up over AUTO")
	assert_true(run_until(keyed, 60.0, 0.5, false), "the workaround keyed")
	assert_true(lgc.erasable.zoomflag, "ZOOMFLAG: the guidance steers")
	assert_false(lgc.erasable.letabort, "P70 and P71 locked out")
	assert_eq([lgc.erasable.modreg, lgc.dsky.prog], [63, "63"], "MODREG 63")
	assert_almost_eq(float(Bus.get_value("ctl.lm.throttle")), 0.1, 1e-6, "the throttle back at its minimum")
	run(2.0, false)
	assert_gt(float(Bus.get_value("lm.dps.throttle_pct")), 90.0, "the LGC holding full thrust")
	_fail_switch()
	run(2.0, false)
	assert_true(bool(Bus.get_value("lm.lgc.abort_bit")), "the short")
	Bus.set_value("ctl.lm.abort", true)
	run(0.2, false)
	Bus.set_value("ctl.lm.abort", false)
	run(2.0, false)
	assert_eq(lgc.program, 63, "P63 flies on: the short, and ABORT itself, passed by")

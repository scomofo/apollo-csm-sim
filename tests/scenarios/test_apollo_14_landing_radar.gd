## Slice 12a's third part (docs/ROADMAP.md, milestone 12): Antares's landing
## radar, its range scale switched to low 4 min 52 s before PDI (the failure
## catalog's lm_lr_scale, on Apollo 14's timeline). From the lunar_descent
## start the crew fly P63 as tests/scenarios/test_apollo_14.gd's do, but
## leave the radar's breaker in at Houston's call: ALT and VEL stay on down
## to 10,000 ft, where the mission rules called for an abort without the
## radar [published: MSC-04112, pp. 8-5 and 14-37; the descent's
## post-flight trajectory analysis, Appendix A]. The breaker's cycle, and
## the landing on the radar after it, are test_apollo_14.gd's.
extends SimTest


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


func test_without_the_breaker_cycle_the_radar_is_still_out_at_10000_ft() -> void:
	build("lunar_descent", "apollo_14")
	var sq := rt.sequencer
	var lgc := rt.lgc()
	var said: Array[String] = []
	sq.capcom.connect(func(w: String) -> void: said.append(w))
	run(float(sq.plan["pdi_tig"]) - 600.0 - SimClock.get_seconds)
	keys("V37E63E", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(rt.failures.active.has("lm_lr_scale"), "the range scale went low 4 min 52 s before PDI")
	assert_true(bool(Bus.get_value("lm.lr.low_scale")), "and stays low")
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	var down := run_until(func() -> bool: return lgc.program != 63 or lgc._h < 10000.0 * Units.FT, 900.0, 1.0, false)
	assert_true(down and lgc.program == 63, "P63 down to 10,000 ft")
	assert_true(said.any(func(w: String) -> bool: return w.contains(LandingRadarCrew.CALL)), "Houston called for the breaker's cycle on the way")
	assert_true(bool(Bus.get_value("lm.lr.low_scale")), "the scale still low, the breaker left in")
	assert_eq([Bus.get_value("lm.dsky.lamp.alt"), Bus.get_value("lm.dsky.lamp.vel")], [true, true],
		"ALT and VEL on at 10,000 ft: the mission rules' abort")
	assert_false(lgc.lr_update, "no radar updates")

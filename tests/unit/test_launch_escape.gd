## Slice 9d (docs/ROADMAP.md): the EDS and the launch escape system. A pad
## abort on the handle takes the CM out to sea on the tower: the pitch
## control motor in mode IA, the tower's jettison 14 s after the abort and
## the chutes on the ELS's timers. The EDS aborts on the rates and on two
## S-IC engines out, until the IU switches it off at the S-IC's centre
## engine's cutoff or the tower goes; the crew can switch it off, and the
## ground's ABORT then asks for the handle. After the tower the handle
## starts the SPS abort: the booster's cutoff, the SM's +X jets while it
## is held, and the CSM's separation 3 s after it. The modes are called as
## Apollo 11's were, and a checkpoint under the tower flies on to the same
## splashdown. The modes' landings are
## tests/scenarios/test_launch_aborts.gd's.
extends SimTest


func _eds() -> Eds:
	return rt.systems["eds"]


func _downrange_m() -> float:
	var l: Dictionary = rt.mission.section("launch")
	return Bodies.surface_angle(Vector2(l["pad_lat_deg"], l["pad_lon_deg"]), rt.sequencer.geographic()) * Bodies.R_EARTH


## Turn the abort handle: counterclockwise for [param hold_s], then back.
func _handle(hold_s: float = 0.1) -> void:
	Bus.set_value("ctl.abort", true)
	run(hold_s, false)
	Bus.set_value("ctl.abort", false)


func test_a_pad_abort_takes_the_cm_out_to_sea() -> void:
	build("launch")
	run(-10.0 - SimClock.get_seconds, false)
	_handle()
	var at := _eds().abort_get
	assert_almost_eq(at, -10.0, 0.05, "the handle on the pad")
	assert_eq(_eds().cause, "HANDLE")
	assert_eq(rt.sequencer.abort_mode, "IA")
	assert_eq(rt.dynamics.config, "cm_les", "the tower has the CM")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "mode IA")
	var times := {}
	var apogee := 0.0
	while not rt.dynamics.landed and SimClock.get_seconds < 400.0:
		run(0.1, false)
		apogee = maxf(apogee, rt.dynamics.traj.altitude())
		for pair in [["tower", rt.dynamics.config == "cm"], ["drogues", bool(Bus.get_value("els.drogue"))],
				["mains", bool(Bus.get_value("els.mains"))]]:
			if pair[1] and not times.has(pair[0]):
				times[pair[0]] = SimClock.get_seconds - at
	run(1.0, false)
	gut.p("pad abort: apogee %.0f m, tower at +%.1f s, drogues +%.1f, mains +%.1f; down %.0f m out, %.1f m/s, %.1f g" % [
		apogee, times["tower"], times["drogues"], times["mains"], _downrange_m(), rt.dynamics.landed_speed, rt.dynamics.max_g])
	# The AOH's low abort: the ELS armed with the canards 14 s after the
	# abort, below 24,000 ft at once; the drogues 2 s on; the mains 14 s on.
	assert_almost_eq(float(times["tower"]), 14.0, 0.15, "the tower goes at 14 s")
	assert_almost_eq(float(times["drogues"]), 16.0, 0.15, "the drogues at 16 s")
	assert_almost_eq(float(times["mains"]), 28.0, 0.15, "the mains at 28 s")
	assert_between(apogee, 800.0, 2000.0, "up clear of the pad")
	assert_between(_downrange_m(), 1000.0, 3000.0, "out to sea")
	assert_true(rt.dynamics.landed)
	assert_lt(rt.dynamics.landed_speed, 10.0, "on the mains")
	assert_eq(rt.sequencer.phase, "splashdown")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Mode IA")


func test_the_eds_aborts_on_the_rates_unless_switched_off_then_the_ground_asks() -> void:
	build("launch")
	rt.failures.arm_on("lv_guidance", "liftoff", 20.0)
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("eds.lv_guid_light")), 60.0, SimClock.FIXED_DT, false))
	assert_true(bool(Bus.get_value("eds.auto_enabled")), "EDS AUTO from the liftoff")
	assert_false(_eds().aborted, "not yet")
	assert_true(run_until(func() -> bool: return _eds().aborted, 5.0, SimClock.FIXED_DT, false), "the EDS aborts")
	var w: Vector3 = Bus.get_value("lv.rate_dps")
	var after := _eds().abort_get - float(rt.failures.active["lv_guidance"])
	gut.p("rates at the abort: %s deg/s, %.2f s after the failure" % [w, after])
	assert_eq(_eds().cause, "LV RATE")
	assert_gt(absf(w.y), 4.0, "past the 4 deg/s pitch limit")
	assert_between(after, 1.0, 3.0, "as the rates build")
	assert_eq(rt.dynamics.config, "cm_les")
	# With LV RATES off it doesn't: the ground's ABORT asks, and the handle.
	build("launch")
	Bus.set_value("ctl.eds.rates", false)
	rt.failures.arm_on("lv_guidance", "liftoff", 20.0)
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("eds.abort_light")), 60.0, 0.1, false), "ABORT")
	assert_false(_eds().aborted, "no automatic abort")
	assert_true(bool(Bus.get_value("eds.lv_rate_light")))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Abort. Abort. Mode One Alpha.")
	_handle()
	assert_eq(_eds().cause, "HANDLE")
	assert_eq(rt.sequencer.abort_mode, "IA")


func test_two_engines_out_abort_until_the_iu_switches_it_off() -> void:
	build("launch")
	rt.failures.arm_on("sic_engine_1", "liftoff", 60.0)
	rt.failures.arm_on("sic_engine_2", "liftoff", 70.0)
	run(65.0 - SimClock.get_seconds, false)
	assert_false(_eds().aborted, "one engine out flies on")
	assert_eq(int(Bus.get_value("lv.engines")), 4)
	run(71.0 - SimClock.get_seconds, false)
	assert_true(_eds().aborted, "the second: the EDS aborts")
	assert_eq(_eds().cause, "2 ENG OUT")
	assert_eq(rt.sequencer.abort_mode, "IB")
	assert_eq(rt.dynamics.config, "cm_les")
	assert_true(bool(Bus.get_value("lv.cut_off")), "the booster cut off, after 30 s")
	# After the S-IC's centre engine's cutoff the IU has switched it off.
	build("launch")
	rt.failures.arm_on("sic_engine_1", "sic_ceco", 1.0)
	rt.failures.arm_on("sic_engine_2", "sic_ceco", 1.0)
	assert_true(run_until(func() -> bool: return rt.failures.active.has("sic_engine_2"), 200.0, 1.0, false))
	run(2.0, false)
	assert_false(bool(Bus.get_value("eds.auto_enabled")), "the IU's switched it off")
	assert_false(_eds().aborted, "no abort")
	assert_eq(int(Bus.get_value("lv.engines_failed")), 2)


func test_after_the_tower_the_handle_separates_the_csm() -> void:
	build("launch")
	run(205.0 - SimClock.get_seconds, false)
	assert_false(bool(Bus.get_value("les.attached")), "the tower's gone")
	assert_false(bool(Bus.get_value("eds.auto_enabled")), "and the EDS's automatic aborts with it")
	assert_eq(str(Bus.get_value("mission.launch_mode")), "II")
	Bus.set_value("ctl.abort", true)
	run(SimClock.FIXED_DT, false)
	assert_eq(_eds().kind, "sps")
	assert_true(bool(Bus.get_value("lv.cut_off")), "the booster's cutoff")
	assert_eq(rt.dynamics.config, "saturn_v", "still on it")
	run(2.9, false)
	assert_eq(rt.dynamics.config, "saturn_v")
	run(0.2, false)
	assert_eq(rt.dynamics.config, "csm", "off 3 s after the handle")
	assert_almost_eq(rt.sequencer.event_get("csm_lv_sep") - _eds().abort_get, 3.0, 0.03)
	assert_false(rt.dynamics.has_lm(), "the LM left on the S-IVB")
	run(0.5, false)
	assert_true(bool(Bus.get_value("eds.ullage")), "+X on the SM's jets while held")
	assert_gt((Bus.get_value("rcs.force_body") as Vector3).x, 1000.0)
	Bus.set_value("ctl.abort", false)
	run(0.1, false)
	assert_false(bool(Bus.get_value("eds.ullage")), "until it's back at neutral")
	Bus.set_value("ctl.abort", true)
	run(0.1, false)
	assert_false(bool(Bus.get_value("eds.ullage")), "once")
	Bus.set_value("ctl.abort", false)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Mode II: CM/SM SEP")
	assert_eq(rt.sequencer.phase, "abort")


func test_the_modes_are_called_as_apollo_11s_were() -> void:
	build("launch")
	var said := {}
	rt.sequencer.capcom.connect(func(text: String) -> void: said[text] = SimClock.get_seconds)
	var modes := {}
	while SimClock.get_seconds < 200.0:
		run(1.0, false)
		var m := str(Bus.get_value("mission.launch_mode", ""))
		if not modes.has(m):
			modes[m] = SimClock.get_seconds
	gut.p("modes %s" % modes)
	assert_almost_eq(float(said.get("One Bravo.", -1.0)), 44.0, 1.0, "Armstrong's One Bravo at 0:44")
	assert_almost_eq(float(said.get("Mark. Mode One Charlie.", -1.0)), 118.0, 1.0, "Houston's mark at 1:58")
	assert_almost_eq(float(modes.get("IB", -1.0)), 42.0, 1.0, "IB after 42 s")
	assert_almost_eq(float(modes.get("IC", -1.0)), 118.0, 1.0)
	assert_almost_eq(float(modes.get("II", -1.0)), float(rt.systems["lv"].events["les_jettison"]), 1.0, "II with the tower gone")


func test_a_checkpoint_under_the_tower_flies_on_to_the_same_splashdown() -> void:
	build("launch")
	run(-10.0 - SimClock.get_seconds, false)
	_handle()
	run(5.0, false)
	var text := JSON.stringify(rt.snapshot())
	assert_true(run_until(func() -> bool: return rt.dynamics.landed, 400.0, 1.0, false))
	var first := rt.sequencer.geographic()
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_eq(rt.dynamics.config, "cm_les")
	assert_true(bool(Bus.get_value("les.abort")))
	assert_true(run_until(func() -> bool: return rt.dynamics.landed, 400.0, 1.0, false))
	var again := rt.sequencer.geographic()
	var off := Bodies.surface_angle(first, again) * Bodies.R_EARTH
	gut.p("restored under the tower: down %.2f m from the first" % off)
	assert_lt(off, 1.0, "the same splashdown")

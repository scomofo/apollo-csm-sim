extends SimTest


func test_sps_needs_an_armed_valve_bank() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.sps.thrust_on", true)
	run(1.0, false)
	assert_eq(float(Bus.get_value("sps.thrust_n")), 0.0, "disarmed: no thrust")
	Bus.set_value("ctl.sps.arm_b", true)
	run(2.0, false)
	assert_gt(float(Bus.get_value("sps.thrust_n")), 0.95 * 91190.0, "bank B alone fires the engine")
	Bus.set_value("ctl.sps.thrust_on", false)
	run(2.0, false)
	assert_lt(float(Bus.get_value("sps.thrust_n")), 1000.0, "shutdown transient")
	assert_eq(int(Bus.get_value("sps.ignitions")), 1)


func test_sps_cannot_fire_after_cm_sm_separation() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(0.1, false)
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(0.1, false)
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.thrust_on", true)
	run(1.0, false)
	assert_eq(float(Bus.get_value("sps.thrust_n")), 0.0)


func test_eps_reactant_use_and_apollo_13_failure() -> void:
	build("translunar_coast")
	var o2_0 := float(Bus.get_value("eps.o2_tank1_kg")) + float(Bus.get_value("eps.o2_tank2_kg"))
	run(3600.0)
	var o2_1 := float(Bus.get_value("eps.o2_tank1_kg")) + float(Bus.get_value("eps.o2_tank2_kg"))
	# ~1.9 kW for an hour at 0.36 kg/kWh plus the cabin draw.
	assert_almost_eq(o2_0 - o2_1, 1.9 * 0.36 + 0.1, 0.1)
	assert_almost_eq(float(Bus.get_value("eps.bus_a_v")), 28.3, 0.5)
	rt.systems["eps"].fail_o2_tank(2)
	run(600.0, false)
	assert_eq(float(Bus.get_value("eps.o2_tank2_kg")), 0.0, "tank 2 vented")
	assert_false(bool(Bus.get_value("eps.fc1_ok")))
	assert_false(bool(Bus.get_value("eps.fc3_ok")))
	assert_true(bool(Bus.get_value("eps.fc2_ok")))
	assert_true(bool(Bus.get_value("sys.master_alarm.eps")))
	# One fuel cell cannot carry the load: the batteries start draining.
	var batt0 := float(Bus.get_value("eps.batt_a_ah"))
	run(600.0, false)
	assert_lt(float(Bus.get_value("eps.batt_a_ah")), batt0)


func test_entry_batteries_power_the_cm() -> void:
	build("entry")
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(60.0, false)
	assert_true(bool(Bus.get_value("sys.powered")))
	assert_eq(float(Bus.get_value("eps.fc1_kw")), 0.0, "fuel cells left with the SM")
	assert_lt(float(Bus.get_value("eps.batt_a_ah")), 40.0)


func test_scs_rate_command_damps_rates() -> void:
	build("lunar_orbit")
	rt.dynamics.attitude.omega = Vector3(0.02, -0.01, 0.015)
	Bus.set_value("ctl.scs.att_source", 1)
	run(60.0, false)
	assert_lt(rt.dynamics.attitude.omega.length(), 0.001)


func test_cmc_hold_keeps_attitude_and_auto_maneuvers() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var q0 := rt.dynamics.attitude.q
	rt.dynamics.attitude.omega = Vector3(0.0, 0.004, 0.0)
	run(120.0, false)
	var err := rad_to_deg((q0.inverse() * rt.dynamics.attitude.q).get_angle())
	assert_lt(err, 3.0, "HOLD pulls the attitude back after a disturbance")
	# AUTO maneuver: 90° pitch, about the landing site REFSMMAT's Y axis (a
	# 90° yaw would turn the middle gimbal to 90°: gimbal lock).
	var agc := rt.agc()
	var target := q0 * Quaternion(Vector3(0, 1, 0), PI / 2.0)
	agc.auto_target = target
	agc.auto_active = true
	Bus.set_value("ctl.cmc.mode", 2)
	var ok := run_until(func() -> bool: return rad_to_deg((rt.dynamics.attitude.q.inverse() * target).get_angle()) < 1.0, 300.0, 1.0, false)
	assert_true(ok, "90° auto maneuver at 1°/s completes in under five minutes")


func test_rhc_direct_rotates_and_uses_propellant() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.scs.att_source", 2)
	var p0 := float(Bus.get_value("rcs.sm_prop_kg"))
	Bus.set_value("ctl.rhc", Vector3(0, 1, 0))
	run(5.0, false)
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	assert_gt(rt.dynamics.attitude.omega.y, 0.0)
	assert_lt(float(Bus.get_value("rcs.sm_prop_kg")), p0)


func test_coast_steps_are_long_only_while_nothing_acts() -> void:
	build("translunar_coast")
	SimClock.rate = 1000.0
	SimClock.advance(120.0)
	var n0 := SimClock.step_count
	SimClock.advance(600.0)
	assert_lt(SimClock.step_count - n0, 60, "coasting uses long steps")
	Bus.set_value("ctl.scs.att_source", 2)
	Bus.set_value("ctl.rhc", Vector3(1, 0, 0))
	n0 = SimClock.step_count
	SimClock.advance(10.0)
	assert_eq(SimClock.step_count - n0, 500, "firing jets forces 20 ms steps")


func test_interactive_fast_forward_stops_at_an_event_off_the_step_grid() -> void:
	# Coast steps land on the 20 ms grid short of the event, and the step
	# that passes it drops time acceleration back, though the event's owner
	# has scheduled its next by then.
	Bus.reset()
	SimClock.reset()
	Bus.set_value("sys.coast_ok", true)
	Bus.set_value("dyn.coast_dt_s", 60.0)
	var event := 1234.567
	Bus.set_value("guid.next_event_get_s", event)
	var reschedule := func(_dt: float) -> void:
		if SimClock.get_seconds >= event:
			Bus.set_value("guid.next_event_get_s", event + 600.0)
	SimClock.add_ticker(reschedule)
	SimClock.rate = 10000.0
	var frames := 0
	while SimClock.rate > 10.0 and frames < 100:
		SimClock.frame(1.0 / 60.0)
		frames += 1
	assert_eq(SimClock.rate, 10.0, "time acceleration dropped back")
	assert_between(SimClock.get_seconds, event, event + SimClock.FIXED_DT + 1e-6,
		"on the step that passed the event")
	SimClock.reset()


func test_interactive_fast_forward_stops_at_tli() -> void:
	build("parking_orbit")
	var tig := float(rt.sequencer.tli_pad["tig"])
	SimClock.rate = 10000.0
	while SimClock.get_seconds < tig - 1.0 and SimClock.rate > 10.0:
		SimClock.frame(1.0 / 60.0)
	assert_eq(SimClock.rate, 10.0, "time acceleration dropped at the event")
	assert_almost_eq(SimClock.get_seconds, tig, 0.05, "stopped on the TIG")

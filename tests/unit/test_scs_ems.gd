## Slice 9c (docs/ROADMAP.md): the SCS and the EMS. The SCS holds the
## attitude on its own gyros within its deadbands and commands rates at
## RATE LOW and HIGH; the GDC drifts from the IMU until GDC ALIGN, and the
## FDAIs show it with ATT SOURCE at SCS; its TVC holds the attitude on the
## SPS's gimbal, and MTVC turns the vehicle on it. The EMS's ΔV counter
## ends an SCS burn, and keeps THRUST ON from starting one below zero. A
## checkpoint keeps them. The TEI flown on them, and the EMS's entry
## scroll, are tests/scenarios/test_backups.gd's.
extends SimTest


func _scs(): return rt.systems["scs"]


func _ems(): return rt.systems["ems"]


func _hold_off_deg() -> float:
	return rad_to_deg((_scs() as Scs).error_to((_scs() as Scs).hold).length())


func test_the_scs_holds_the_attitude_within_its_deadband_and_commands_rates() -> void:
	build("transearth_coast")
	Bus.set_value("ctl.scs.att_source", 1)
	# RATE LOW: full deflection, 0.7°/s.
	Bus.set_value("ctl.rhc", Vector3(0.0, 1.0, 0.0))
	run(20.0, false)
	var w: Vector3 = Bus.get_value("dyn.omega")
	assert_almost_eq(rad_to_deg(w.y), 0.7, 0.21, "0.7°/s pitch at RATE LOW, within the rate deadband")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	run(60.0, false)
	var scs: Scs = _scs()
	assert_true(scs.holding, "released, it holds")
	assert_lt(_hold_off_deg(), 0.5, "within ATT DEADBAND MIN's 0.2° and the rate's")
	# RATE HIGH: 7°/s pitch, 20°/s roll at full deflection.
	Bus.set_value("ctl.scs.rate", 1)
	Bus.set_value("ctl.rhc", Vector3(1.0, 0.0, 0.0))
	run(15.0, false)
	w = Bus.get_value("dyn.omega")
	assert_gt(rad_to_deg(w.x), 15.0, "RATE HIGH rolls toward 20°/s")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	run(60.0, false)
	w = Bus.get_value("dyn.omega")
	assert_lt(rad_to_deg(w.length()), 2.5, "the rates damped inside HIGH's 2°/s deadband")
	# ATT DEADBAND MAX at RATE LOW lets the attitude wander 4.2°.
	Bus.set_value("ctl.scs.rate", 0)
	Bus.set_value("ctl.scs.att_db", 1)
	run(300.0, false)
	assert_lt(_hold_off_deg(), 4.6, "within MAX's 4.2°")


func test_the_gdc_drifts_until_aligned_and_the_fdais_follow_the_att_source() -> void:
	build("transearth_coast")
	var scs: Scs = _scs()
	run(1.0, false)
	var imu := Basis(Bus.get_value("guid.indicator.attitude") as Quaternion)
	assert_true(scs.align(), "GDC ALIGN to the IMU")
	assert_true(scs.gdc.is_equal_approx(imu), "the GDC on the IMU's attitude")
	run(3600.0)
	var drift := rad_to_deg(scs.error_to(Basis(Bus.get_value("guid.indicator.attitude") as Quaternion)).length())
	assert_between(drift, 0.1, 1.0, "the BMAGs' drift, an hour on: %.2f°" % drift)
	assert_true((Bus.get_value("scs.fdai.attitude") as Quaternion).is_equal_approx(
		Bus.get_value("guid.indicator.attitude") as Quaternion), "the FDAIs on the CMC's")
	Bus.set_value("ctl.scs.att_source", 1)
	run(1.0, false)
	assert_true((Bus.get_value("scs.fdai.attitude") as Quaternion).is_equal_approx(
		scs.gdc.get_rotation_quaternion()), "at SCS, on the GDC's")
	Bus.set_value("ctl.scs.gdc_align", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.scs.gdc_align", false)
	assert_lt(rad_to_deg(scs.error_to(Basis(Bus.get_value("guid.indicator.attitude") as Quaternion)).length()), 0.05,
		"GDC ALIGN takes the drift out")
	rt.failures.fail("cmc")
	run(1.0, false)
	assert_false(scs.align(), "no ALIGN with the CMC failed")


func test_the_ems_ends_an_scs_burn_and_mtvc_turns_on_the_gimbal() -> void:
	build("transearth_coast")
	var ems: Ems = _ems()
	Bus.set_value("ctl.scs.att_source", 1)
	Bus.set_value("ctl.sps.arm_a", true)
	# The gimbal motors, PITCH 1 and YAW 1 (slice 12c): START, then ON.
	for m in ["p1", "y1"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 2)
	run(SimClock.FIXED_DT, false)
	for m in ["p1", "y1"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 1)
	# Below zero, THRUST ON starts nothing.
	Bus.set_value("ctl.ems.function", Ems.Function.DV)
	ems.dv = -1.0
	Bus.set_value("ctl.sps.thrust_on", true)
	run(1.0, false)
	Bus.set_value("ctl.sps.thrust_on", false)
	run(SimClock.FIXED_DT, false)
	assert_false(bool(Bus.get_value("sps.on")), "the EMS's thrust-off holds it")
	# 100 ft/s: THRUST ON latches, the EMS ends it.
	ems.dv = 100.0
	var v0 := rt.dynamics.traj.vel()
	Bus.set_value("ctl.sps.thrust_on", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.sps.thrust_on", false)
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("sps.on")), 2.0, SimClock.FIXED_DT, false), "firing")
	# MTVC: the hand controller pitches the CSM on the gimbal.
	Bus.set_value("ctl.scs.tvc", 1)
	Bus.set_value("ctl.rhc", Vector3(0.0, 0.5, 0.0))
	run(1.5, false)
	var w: Vector3 = Bus.get_value("dyn.omega")
	var g: Vector2 = Bus.get_value("sps.gimbal_rad")
	gut.p("MTVC: pitch %.2f°/s, gimbal %.2f°" % [rad_to_deg(w.y), rad_to_deg(g.x)])
	assert_gt(rad_to_deg(w.y), 0.2, "MTVC pitches it")
	assert_ne(g.x, 0.0, "on the gimbal")
	assert_lt(absf(rad_to_deg(g.x)), 4.51, "within its ±4.5°")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	assert_true(run_until(func() -> bool: return not bool(Bus.get_value("sps.on")), 30.0, SimClock.FIXED_DT, false),
		"the EMS ends the burn")
	run(3.0, false)
	var dv := rt.dynamics.traj.vel().distance_to(v0) / Units.FT
	gut.p("EMS burn: %.1f ft/s for 100.0 set, counter %+.1f" % [dv, ems.dv])
	assert_between(dv, 100.0, 110.0, "100 ft/s and the tail-off")
	assert_lt(ems.dv, -0.1, "the counter past the thrust-off")
	assert_false(bool(Bus.get_value("scs.sps_on")))
	# Held THRUST ON with the EMS out of ΔV still runs the SPS while held.
	Bus.set_value("ctl.ems.function", Ems.Function.OFF)
	Bus.set_value("ctl.sps.thrust_on", true)
	run(1.0, false)
	assert_true(bool(Bus.get_value("sps.on")), "the manual backup")
	Bus.set_value("ctl.sps.thrust_on", false)
	run(1.0, false)
	assert_false(bool(Bus.get_value("sps.on")))


func test_the_ems_sets_on_its_rocker() -> void:
	build("transearth_coast")
	var ems: Ems = _ems()
	Bus.set_value("ctl.ems.function", Ems.Function.DV_SET)
	Bus.set_value("ctl.ems.set", 2)
	run(2.0, false)
	assert_almost_eq(ems.dv, 255.0, 1.0, "127.5 ft/s a second at the hard stop")
	Bus.set_value("ctl.ems.set", -1)
	run(4.0, false)
	assert_almost_eq(ems.dv, 254.0, 0.05, "0.25 a second at the soft stop")
	Bus.set_value("ctl.ems.set", 0)
	Bus.set_value("ctl.ems.function", Ems.Function.V0_SET)
	Bus.set_value("ctl.ems.set", 2)
	run(1.0, false)
	assert_almost_eq(ems.v, 480.0, 10.0, "the scroll at 480 ft/s a second")
	Bus.set_value("ctl.ems.set", 0)


func test_a_checkpoint_keeps_the_scs_the_gimbal_and_the_ems() -> void:
	build("transearth_coast")
	var scs: Scs = _scs()
	var ems: Ems = _ems()
	scs.align()
	Bus.set_value("ctl.scs.att_source", 1)
	run(5.0, false)
	ems.dv = 123.4
	ems.trace = [[36000.0, 0.5], [35900.0, 0.8]]
	var gdc := scs.gdc
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_true((_scs() as Scs).gdc.is_equal_approx(gdc), "the GDC")
	assert_true((_scs() as Scs).holding, "holding")
	assert_almost_eq((_ems() as Ems).dv, 123.4, 1e-9, "the ΔV counter")
	assert_eq((_ems() as Ems).trace.size(), 2, "the scroll's trace")

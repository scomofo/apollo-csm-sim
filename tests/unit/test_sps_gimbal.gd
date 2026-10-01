## Slice 12c (docs/ROADMAP.md, milestone 12): the SPS's servo loops. Each
## of the gimbal's actuators, pitch and yaw, has two loops, each with its
## own gimbal motor: SPS GIMBAL MOTORS starts and stops them, TVC GMBL DRIVE
## picks the loop that drives, AUTO taking loop 2 with the THC clockwise,
## and the GPI shows the gimbal; under the SCS the GPI's trim and MTVC move
## it before ignition, and under the CMC it goes to its null. Apollo 16's
## secondary yaw loop, its rate feedback open, swings the gimbal 1 deg
## either way at 2.4 Hz once a command moves it, and the thrust damps it
## (MSC-07230, section 14.1.10). Apollo 16's crew finding it is
## tests/scenarios/test_apollo_16.gd's; a checkpoint keeping it,
## tests/unit/test_checkpoint.gd's.
extends SimTest


func _sps() -> Sps:
	return rt.systems["sps"]


func _scs() -> Scs:
	return rt.systems["scs"]


func _gpi() -> Vector2:
	return Vector2(float(Bus.get_value("sps.gpi_p_deg")), float(Bus.get_value("sps.gpi_y_deg")))


## Start loop [param loop]'s gimbal motor: START, sprung back to ON.
func _start(loop: String) -> void:
	Bus.set_value("ctl.sps.gmbl_" + loop, 2)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.sps.gmbl_" + loop, 1)
	run(SimClock.FIXED_DT, false)


## The GPI's yaw (deg) from [param about] through [param seconds]: x its
## least, y its greatest and z how often it crosses it (Hz), from the
## first crossing to the last.
func _swing(seconds: float, about: float) -> Vector3:
	var out := Vector3(INF, -INF, 0.0)
	var crossed := PackedFloat64Array()
	var was := 0.0
	var t0 := SimClock.get_seconds
	while SimClock.get_seconds - t0 < seconds:
		run(SimClock.FIXED_DT, false)
		var y := _gpi().y - about
		out.x = minf(out.x, y)
		out.y = maxf(out.y, y)
		if was != 0.0 and (was < 0.0) != (y < 0.0):
			crossed.append(SimClock.get_seconds - SimClock.FIXED_DT * (1.0 - was / (was - y)))
		was = y
	if crossed.size() > 1:
		out.z = (crossed.size() - 1) / (2.0 * (crossed[-1] - crossed[0]))
	return out


func test_the_gimbal_motors_drive_the_loop_tvc_gmbl_drive_picks() -> void:
	build("transearth_coast")
	var sps := _sps()
	assert_eq(sps.motors, [false, false, false, false] as Array[bool], "the motors off")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i.ZERO, "no loop drives")
	# Under the SCS on RATE CMD, the GPI's yaw trim at 1 deg/s on its
	# rocker: no motor running, the gimbal stays where it stood.
	Bus.set_value("ctl.scs.att_source", 1)
	Bus.set_value("ctl.scs.tvc", 1)
	Bus.set_value("ctl.scs.gpi_trim_y", 1)
	run(1.5, false)
	Bus.set_value("ctl.scs.gpi_trim_y", 0)
	assert_almost_eq(rad_to_deg(_scs().trim.y), 1.5, 0.03, "the yaw trim")
	assert_almost_eq(float(Bus.get_value("scs.gpi_trim_y_deg")), 1.5, 0.03, "on its thumbwheel")
	run(1.0, false)
	assert_eq(_gpi(), Vector2.ZERO, "no motor: the gimbal at its null")
	# PITCH 1 and YAW 1: at AUTO loop 1 takes the gimbal to the trim at the
	# actuators' rate.
	_start("p1")
	_start("y1")
	assert_eq(sps.motors, [true, true, false, false] as Array[bool], "START, sprung back to ON, keeps them running")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 1), "loop 1 in both axes at AUTO")
	run(0.5, false)
	assert_almost_eq(_gpi().y, rad_to_deg(_scs().trim.y), 0.01, "the GPI on the trim")
	# MTVC: the hand controller moves the gimbal about the trim, half
	# deflection half the travel.
	Bus.set_value("ctl.rhc", Vector3(0.0, 0.5, 0.0))
	run(1.0, false)
	assert_almost_eq(_gpi().x, 2.25, 0.01, "MTVC in pitch")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	run(1.0, false)
	assert_almost_eq(_gpi().x, 0.0, 0.01, "back to the pitch trim")
	# SC CONT at CMC and the THC clockwise: the SCS's, on loop 2, whose
	# motors are off: no MTVC.
	Bus.set_value("ctl.scs.att_source", 0)
	Bus.set_value("ctl.thc_cw", true)
	run(SimClock.FIXED_DT, false)
	assert_eq(Scs.sc_cont(), 1, "the THC clockwise takes control to the SCS")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i.ZERO, "AUTO with the THC clockwise picks loop 2, its motors off")
	var at := _gpi()
	Bus.set_value("ctl.rhc", Vector3(0.0, 0.0, -0.5))
	run(1.0, false)
	assert_eq(_gpi(), at, "no MTVC")
	# PITCH 2 and YAW 2: loop 2 drives, and MTVC moves the gimbal.
	_start("p2")
	_start("y2")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(2, 2), "loop 2 in both axes")
	run(1.0, false)
	assert_almost_eq(_gpi().y, rad_to_deg(_scs().trim.y) - 2.25, 0.01, "MTVC on loop 2")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	# The THC back to neutral: the CMC's command, the null, on loop 1.
	Bus.set_value("ctl.thc_cw", false)
	run(1.0, false)
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 1))
	assert_almost_eq(_gpi(), Vector2.ZERO, Vector2.ONE * 0.01, "the GPI back to 0, 0")
	# TVC GMBL DRIVE YAW at 2 holds loop 2; its motor OFF, nothing drives
	# yaw.
	Bus.set_value("ctl.scs.tvc_drive_y", 2)
	run(SimClock.FIXED_DT, false)
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 2), "TVC GMBL DRIVE YAW at 2")
	Bus.set_value("ctl.sps.gmbl_y2", 0)
	run(SimClock.FIXED_DT, false)
	assert_eq(sps.motors, [true, true, true, false] as Array[bool], "YAW 2 off")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 0), "nothing drives yaw")


func test_an_open_rate_feedback_swings_the_gimbal_until_the_thrust_damps_it() -> void:
	build("transearth_coast")
	assert_true(rt.failures.fail("sps_yaw_servo_2"), "the secondary yaw loop's rate feedback open")
	assert_eq(Bus.get_value("sps.rate_open"), "y2")
	for m in ["p1", "y1", "p2", "y2"]:
		_start(m)
	Bus.set_value("ctl.scs.att_source", 1)
	Bus.set_value("ctl.scs.tvc", 1)
	_scs().trim = Vector2(deg_to_rad(0.5), deg_to_rad(1.2))
	run(1.0, false)
	# Loop 1 holds the trim steady.
	var s := _swing(2.0, 1.2)
	assert_lt(maxf(-s.x, s.y), 0.001, "loop 1 steady on the trim")
	# The THC clockwise: loop 2, steady until a command moves the gimbal.
	Bus.set_value("ctl.thc_cw", true)
	s = _swing(2.0, 1.2)
	assert_lt(maxf(-s.x, s.y), 0.001, "loop 2 steady until disturbed")
	# The yaw trim nudged: the swing builds to 1 deg either way at 2.4 Hz
	# about it, the pitch steady.
	_scs().trim.y = deg_to_rad(1.3)
	run(4.0, false)
	s = _swing(5.0, 1.3)
	gut.p("Loop 2's yaw: %+.3f to %+.3f deg about the trim, %.2f Hz" % [s.x, s.y, s.z])
	assert_almost_eq(s.y, 1.0, 0.05, "1 deg one way")
	assert_almost_eq(s.x, -1.0, 0.05, "and the other")
	assert_almost_eq(s.z, 2.4, 0.05, "at 2.4 Hz")
	assert_almost_eq(_gpi().x, 0.5, 0.001, "the pitch steady on loop 2")
	# THRUST ON with the EMS out of ΔV: the side load damps it in a few
	# seconds.
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.thrust_on", true)
	run(6.0, false)
	assert_true(bool(Bus.get_value("sps.on")), "the SPS firing")
	assert_lt(rad_to_deg(_sps().cycle.y), 0.05, "damped under thrust")
	Bus.set_value("ctl.sps.thrust_on", false)
	Bus.set_value("ctl.sps.arm_a", false)
	# Back to the trim after the cutoff, a command move: it swings again,
	# until loop 1 takes over.
	run(5.0, false)
	assert_gt(rad_to_deg(_sps().cycle.y), 0.9, "swinging again")
	Bus.set_value("ctl.thc_cw", false)
	Bus.set_value("ctl.scs.att_source", 1)
	run(SimClock.FIXED_DT, false)
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 1))
	assert_eq(_sps().cycle, Vector2.ZERO, "loop 1 holds it")

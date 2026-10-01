## Physical travel and motor isolation at the peak of a failed servo's swing.
extends GutTest

var sps: Sps


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	SpacecraftData.use_mission({})
	sps = Sps.new()
	add_child_autofree(sps)
	Bus.set_value("ctl.scs.att_source", 1)
	Bus.set_value("ctl.scs.tvc_drive_y", 2)
	Bus.set_value("ctl.sps.gmbl_y2", 2)
	sps.tick(SimClock.FIXED_DT)
	Bus.set_value("ctl.sps.gmbl_y2", 1)
	sps.fail("y2_rate")


func test_failed_servo_stays_inside_both_mechanical_stops() -> void:
	for sign in [-1.0, 1.0]:
		Bus.set_value("scs.gimbal_cmd", Vector2(0.0, sign * Scs.GIMBAL_MAX))
		for i in 500:
			SimClock.get_seconds += SimClock.FIXED_DT
			sps.tick(SimClock.FIXED_DT)
		var peak := 0.0
		for i in 100:
			SimClock.get_seconds += SimClock.FIXED_DT
			sps.tick(SimClock.FIXED_DT)
			peak = maxf(peak, absf(sps.position().y))
		assert_lte(peak, Scs.GIMBAL_MAX + 1e-6, "failed loop cannot drive past either 4.5-degree stop")


func _at_swing_peak() -> void:
	Bus.set_value("scs.gimbal_cmd", Vector2(0.0, deg_to_rad(1.0)))
	for i in 500:
		SimClock.get_seconds += SimClock.FIXED_DT
		sps.tick(SimClock.FIXED_DT)
	SimClock.get_seconds = (24.0 + 0.25) / Sps.CYCLE_HZ
	assert_gt(rad_to_deg(sps.position().y), 1.9, "failure established near the positive peak")


func test_motor_off_holds_the_actual_position_without_a_jump() -> void:
	_at_swing_peak()
	var at := sps.position()
	Bus.set_value("ctl.sps.gmbl_y2", 0)
	sps.tick(0.0)
	assert_almost_eq(sps.position(), at, Vector2.ONE * 1e-6, "OFF cannot move the engine with zero elapsed time")
	SimClock.get_seconds += 10.0
	sps.tick(10.0)
	assert_almost_eq(sps.position(), at, Vector2.ONE * 1e-6, "the stopped motor leaves the engine at its last position")


func test_healthy_loop_takes_over_at_the_actuator_rate() -> void:
	_at_swing_peak()
	var at := sps.position()
	Bus.set_value("ctl.sps.gmbl_y1", 2)
	Bus.set_value("ctl.scs.tvc_drive_y", 1)
	sps.tick(0.0)
	assert_almost_eq(sps.position(), at, Vector2.ONE * 1e-6, "loop transfer cannot snap the engine back to trim")
	sps.tick(SimClock.FIXED_DT)
	assert_lte(at.distance_to(sps.position()), Sps.GIMBAL_RATE * SimClock.FIXED_DT + 1e-6,
		"the healthy loop recovers at the actuator rate")


func test_power_loss_holds_the_position_through_a_checkpoint() -> void:
	_at_swing_peak()
	var at := sps.position()
	Bus.set_value("sys.powered", false)
	sps.tick(0.0)
	var saved := sps.snapshot()
	SimClock.get_seconds += 10.0
	var restored := Sps.new()
	add_child_autofree(restored)
	restored.restore(saved)
	assert_almost_eq(restored.position(), at, Vector2.ONE * 1e-6, "the checkpoint keeps the unpowered engine's deflection")
	restored.tick(10.0)
	assert_almost_eq(restored.position(), at, Vector2.ONE * 1e-6, "it stays there while unpowered")


func test_gimbal_malfunction_requires_every_motor_off() -> void:
	var book := ChecklistBook.load_default()
	book.select_title("Malfunction: SPS gimbal")
	book.list().next()
	for loop in ["p1", "y1", "p2"]:
		Bus.set_value("ctl.sps.gmbl_" + loop, 2)
	Bus.set_value("ctl.sps.gmbl_y2", 0)
	sps.tick(0.0)
	assert_false(book.list().update(), "stopping only the bad yaw motor does not complete all four OFF")
	for loop in Sps.LOOPS:
		Bus.set_value("ctl.sps.gmbl_" + loop, 0)
	sps.tick(0.0)
	assert_true(book.list().update(), "all four motors stopped completes the isolation step")

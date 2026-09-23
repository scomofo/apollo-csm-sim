## HandControllerInput: the keys and the XR thumbsticks drive the rotation
## and translation controllers through one path.
extends GutTest


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func _keys(down: Array) -> Callable:
	return func(k: Key) -> bool: return down.has(k)


func test_keyboard_keeps_the_desktop_key_map() -> void:
	var c := HandControllerInput.keyboard_commands(_keys([KEY_Q, KEY_S, KEY_D]))
	assert_eq(c[0], Vector3(-1, 1, 1), "roll left (Q), pitch up (S), yaw right (D)")
	assert_eq(c[1], Vector3.ZERO)
	c = HandControllerInput.keyboard_commands(_keys([KEY_E, KEY_W, KEY_A]))
	assert_eq(c[0], Vector3(1, -1, -1), "roll right (E), pitch down (W), yaw left (A)")
	c = HandControllerInput.keyboard_commands(_keys([KEY_SHIFT, KEY_W, KEY_R, KEY_LEFT, KEY_UP]))
	assert_almost_eq(c[0].y, -0.1, 1e-6, "Shift gives 10 % deflection")
	assert_eq(c[1], Vector3(1, -1, -1), "+X (R), -Y (Left), up = -Z (Up); Shift leaves the THC alone")
	c = HandControllerInput.keyboard_commands(_keys([KEY_F, KEY_RIGHT, KEY_DOWN]))
	assert_eq(c[1], Vector3(-1, 1, 1), "-X (F), +Y (Right), down = +Z (Down)")


func test_sticks_fly_rotation_and_the_left_grip_switches_them_to_translation() -> void:
	var c := HandControllerInput.stick_commands(Vector2(0.5, 0.0), Vector2(0.25, 1.0), false)
	assert_eq(c[0], Vector3(0.5, -1.0, 0.25), "left X roll; right stick forward = nose down; right X yaw")
	assert_eq(c[1], Vector3.ZERO)
	c = HandControllerInput.stick_commands(Vector2(0.5, 1.0), Vector2(0.25, -1.0), true)
	assert_eq(c[0], Vector3.ZERO, "grip held: no rotation")
	assert_eq(c[1], Vector3(-1.0, 0.5, -1.0), "right Y = X, left X = Y, left forward = up (-Z)")


func test_a_stick_off_centre_commands_nothing_until_past_the_deadzone() -> void:
	assert_eq(HandControllerInput.deadzone(Vector2(0.08, -0.12)), Vector2.ZERO, "a resting or drifting stick")
	assert_eq(HandControllerInput.deadzone(Vector2(0.1, 1.0)), Vector2(0.0, 1.0),
		"full forward with a little sideways error is pure pitch")
	var half := HandControllerInput.STICK_DEADZONE + 0.5 * (1.0 - HandControllerInput.STICK_DEADZONE)
	assert_almost_eq(HandControllerInput.deadzone(Vector2(-half, 0.0)).x, -0.5, 1e-6, "rescaled beyond it")
	assert_eq(HandControllerInput.deadzone(Vector2(1.0, -1.0)), Vector2(1.0, -1.0), "full scale kept")


func test_node_centres_without_input_and_zeroes_above_the_rate_limit() -> void:
	var hci := HandControllerInput.new()
	add_child_autofree(hci)
	Bus.set_value("ctl.rhc", Vector3.ONE)
	Bus.set_value("ctl.thc", Vector3.ONE)
	hci._process(0.0)
	assert_eq(Bus.get_value("ctl.rhc"), Vector3.ZERO, "no key, no headset: centred")
	assert_eq(Bus.get_value("ctl.thc"), Vector3.ZERO)
	Bus.set_value("ctl.rhc", Vector3.ONE)
	SimClock.rate = 1000.0
	assert_true(SimClock.controls_locked())
	hci._process(0.0)
	assert_eq(Bus.get_value("ctl.rhc"), Vector3.ZERO, "locked above the interactive rate")


func test_in_a_headset_it_reads_the_xr_rigs_hands() -> void:
	var rig: Node3D = add_child_autofree(preload("res://scenes/player/xr_rig.tscn").instantiate())
	var hci := HandControllerInput.for_xr_rig(rig)
	add_child_autofree(hci)
	assert_eq(hci._left, rig.get_node("LeftHand"), "the left thumbstick: roll, and the grip for translation")
	assert_eq(hci._right, rig.get_node("RightHand"), "the right thumbstick: pitch and yaw")

## Desktop inspection preserves camera position and routes zoom through the
## real unhandled-input path without operating cockpit controls. Ported from
## gemini-capsule at 40e449c; the head-movement cases are replaced because
## the Apollo rig has no keyboard head movement, and recenter is Home.
extends GutTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")

class SpyControl extends ControlBase:
	var actuations: Array[int] = []
	func actuate(direction: int) -> void:
		actuations.append(direction)

var viewport: SubViewport
var rig: Node3D
var camera: Camera3D


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	rig = RIG.instantiate()
	viewport.add_child(rig)
	rig.set_process(false)
	camera = rig.get_node("Camera3D")
	camera.current = true


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _control(position: Vector3) -> SpyControl:
	var control := SpyControl.new()
	viewport.add_child(control)
	control.global_position = position
	return control


func _physics_ready() -> void:
	for frame in 2:
		await get_tree().physics_frame
		await get_tree().process_frame


func _mouse(button: MouseButton, position: Vector2 = Vector2(400, 300), shifted: bool = false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.position = position
	event.global_position = position
	event.pressed = true
	event.factor = 1.0
	event.shift_pressed = shifted
	viewport.push_input(event, true)


func _key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	viewport.push_input(event, true)


func test_perspective_zoom_is_bounded_and_moves_neither_camera_nor_other_cameras() -> void:
	var other := Camera3D.new()
	other.fov = 73.0
	viewport.add_child(other)
	var original := camera.transform
	assert_almost_eq(rig.zoom_factor(), 1.0, 0.000001)
	rig.set_zoom_factor(2.0)
	assert_almost_eq(rig.zoom_factor(), 2.0, 0.000001)
	assert_almost_eq(camera.fov, rad_to_deg(2.0 * atan(0.5)), 0.00001)
	assert_true(rig.is_inspecting())
	rig.set_zoom_factor(100.0)
	assert_almost_eq(camera.fov, 12.0, 0.000001)
	assert_almost_eq(rig.zoom_factor(), 1.0 / tan(deg_to_rad(6.0)), 0.000001)
	assert_almost_eq(float(Bus.get_value("present.inspect.zoom_factor")), rig.zoom_factor(), 0.000001)
	rig.set_zoom_factor(-2.0)
	assert_almost_eq(camera.fov, 90.0, 0.000001)
	rig.set_zoom_factor(NAN)
	assert_almost_eq(camera.fov, 90.0, 0.000001)
	assert_true(camera.transform.is_equal_approx(original))
	assert_eq(other.fov, 73.0, "inspection modifies only this desktop camera")


func test_find_aims_at_installed_touch_centre_without_translation_and_returns_the_first_view() -> void:
	camera.position = Vector3(0.07, 0.04, 0.03)
	_mouse(MOUSE_BUTTON_RIGHT)
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(35, -18)
	viewport.push_input(motion, true)
	var original := camera.transform
	var a := _control(Vector3(-0.25, 0.15, -0.8))
	var b := _control(Vector3(0.3, -0.15, -0.9))
	var a_transform := a.transform
	assert_true(rig.focus_control(a))
	assert_eq(camera.position, original.origin, "Find does not teleport the viewer")
	assert_almost_eq(camera.unproject_position(a.get_node("Touch").global_position), Vector2(400, 300), Vector2.ONE * 0.001)
	assert_almost_eq(rig.zoom_factor(), 2.5, 0.000001)
	assert_eq(a.actuations.size(), 0)
	assert_eq(a.transform, a_transform)
	assert_true(rig.focus_control(b))
	assert_eq(camera.position, original.origin)
	assert_almost_eq(camera.unproject_position(b.get_node("Touch").global_position), Vector2(400, 300), Vector2.ONE * 0.001)
	rig.restore_view()
	assert_true(camera.transform.is_equal_approx(original), "repeated Find retains the original look and position")
	assert_almost_eq(camera.fov, 90.0, 0.000001)
	assert_false(rig.is_inspecting())
	assert_almost_eq(float(Bus.get_value("present.inspect.zoom_factor")), 1.0, 0.000001)
	assert_true(rig._captured, "returning the view preserves current mouse-look state")
	motion.relative = Vector2.ZERO
	viewport.push_input(motion, true)
	assert_true(camera.transform.is_equal_approx(original), "restored yaw/pitch agree with the visible view")


func test_z_uses_free_cursor_or_captured_centre_without_actuating_and_toggles_back() -> void:
	# Use the viewport's actual pointer position, as the production shortcut does.
	var cursor := viewport.get_mouse_position()
	var a := _control(camera.project_ray_origin(cursor) + camera.project_ray_normal(cursor) * 0.8)
	await _physics_ready()
	var original := camera.transform
	_key(KEY_Z)
	assert_true(viewport.is_input_handled())
	assert_true(rig.is_inspecting())
	assert_almost_eq(camera.unproject_position(a.get_node("Touch").global_position), Vector2(400, 300), Vector2.ONE * 0.001)
	assert_eq(a.actuations.size(), 0)
	_key(KEY_Z)
	assert_true(camera.transform.is_equal_approx(original))
	assert_false(rig.is_inspecting())
	var b := _control(Vector3(0, 0, -0.75))
	await _physics_ready()
	_mouse(MOUSE_BUTTON_RIGHT)
	_key(KEY_Z)
	assert_true(rig.is_inspecting())
	assert_almost_eq(camera.unproject_position(b.global_position), Vector2(400, 300), Vector2.ONE * 0.001)
	assert_eq(b.actuations.size(), 0)


func test_z_without_touch_volume_magnifies_current_look_instead_of_requiring_a_control() -> void:
	var original := camera.transform
	_key(KEY_Z)
	assert_true(rig.is_inspecting(), "passive faces and displays can still be read")
	assert_almost_eq(rig.zoom_factor(), 2.5, 0.000001)
	assert_true(camera.transform.is_equal_approx(original))
	_key(KEY_Z)
	assert_false(rig.is_inspecting())
	assert_almost_eq(rig.zoom_factor(), 1.0, 0.000001)


func test_shift_wheel_never_actuates_but_plain_wheel_and_click_keep_their_directions() -> void:
	var control := _control(Vector3(0, 0, -0.8))
	await _physics_ready()
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(400, 300), true)
	assert_true(viewport.is_input_handled())
	assert_gt(rig.zoom_factor(), 1.0)
	assert_eq(control.actuations.size(), 0, "Shift-wheel cannot reach far-field actuation")
	_mouse(MOUSE_BUTTON_WHEEL_DOWN, Vector2(400, 300), true)
	assert_eq(control.actuations.size(), 0)
	_mouse(MOUSE_BUTTON_WHEEL_UP)
	_mouse(MOUSE_BUTTON_WHEEL_DOWN)
	_mouse(MOUSE_BUTTON_LEFT)
	assert_eq(control.actuations, [1, -1, 0], "unmodified cockpit interactions are unchanged")


func test_actual_click_ray_uses_the_zoomed_projection() -> void:
	var pixel := Vector2(600, 300)
	var wide := _control(camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * 0.9)
	rig.set_zoom_factor(2.5)
	var narrow := _control(camera.project_ray_origin(pixel) + camera.project_ray_normal(pixel) * 0.9)
	rig.reset_zoom()
	await _physics_ready()
	_mouse(MOUSE_BUTTON_LEFT, pixel)
	assert_eq(wide.actuations, [0])
	assert_eq(narrow.actuations.size(), 0)
	rig.set_zoom_factor(2.5)
	_mouse(MOUSE_BUTTON_LEFT, pixel)
	assert_eq(wide.actuations, [0], "zoomed click cannot use the previous wide ray")
	assert_eq(narrow.actuations, [0], "same pixel now hits the actual narrowed camera ray")


func test_escape_returns_inspection_before_releasing_mouse_capture_and_menu_release_keeps_view() -> void:
	_mouse(MOUSE_BUTTON_RIGHT)
	assert_true(rig._captured)
	rig.set_zoom_factor(3.0)
	_key(KEY_ESCAPE)
	assert_true(viewport.is_input_handled())
	assert_false(rig.is_inspecting())
	assert_true(rig._captured, "first Esc returns the view")
	_key(KEY_ESCAPE)
	assert_false(rig._captured, "next Esc releases mouse look")
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	_mouse(MOUSE_BUTTON_RIGHT)
	rig.set_zoom_factor(2.0)
	var inspected := camera.transform
	rig.release_mouse_look()
	assert_false(rig._captured)
	assert_true(rig.is_inspecting(), "opening a checklist releases the cursor without losing inspection")
	assert_eq(camera.transform, inspected)
	assert_almost_eq(rig.zoom_factor(), 2.0, 0.000001)


func test_rotation_controller_keys_neither_move_the_head_nor_get_consumed() -> void:
	# W/A/S/D/Q/E fly the RHC in Apollo (HandControllerInput polls them), so
	# the rig must leave them alone.
	var original := camera.transform
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_Q, KEY_E]:
		_key(code)
		assert_false(viewport.is_input_handled(), "%s passes through" % OS.get_keycode_string(code))
		_key(code, false)
	assert_true(camera.transform.is_equal_approx(original))


func test_window_focus_loss_releases_capture_and_keeps_the_view() -> void:
	_mouse(MOUSE_BUTTON_RIGHT)
	rig.set_zoom_factor(2.0)
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_false(rig._captured)
	assert_eq(Input.mouse_mode, Input.MOUSE_MODE_VISIBLE)
	rig._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	assert_true(rig.is_inspecting(), "window focus loss retains a readable view but never recaptures the mouse")
	assert_false(rig._captured)


func test_gui_consumed_mouse_events_do_not_reach_zoom_or_cockpit_actuation() -> void:
	var control := _control(Vector3(0, 0, -0.8))
	var panel := Panel.new()
	panel.position = Vector2(300, 200)
	panel.size = Vector2(200, 200)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_force_pass_scroll_events = false
	viewport.add_child(panel)
	await _physics_ready()
	_mouse(MOUSE_BUTTON_WHEEL_UP, Vector2(400, 300), true)
	_mouse(MOUSE_BUTTON_LEFT)
	assert_eq(control.actuations.size(), 0)
	assert_almost_eq(rig.zoom_factor(), 1.0, 0.000001)
	assert_false(rig.is_inspecting())


func test_recenter_key_clears_saved_view_and_zoom_while_retaining_height_calibration() -> void:
	var control := _control(Vector3(0.3, 0.2, -0.8))
	rig.height_offset = 0.06
	assert_true(rig.focus_control(control))
	rig.set_zoom_factor(4.0)
	_key(KEY_HOME)
	assert_true(viewport.is_input_handled())
	assert_false(rig.is_inspecting())
	assert_almost_eq(camera.position, Vector3(0, 0.06, 0), Vector3.ONE * 0.000001)
	assert_almost_eq(camera.rotation, Vector3.ZERO, Vector3.ONE * 0.000001)
	assert_almost_eq(rig.zoom_factor(), 1.0, 0.000001)
	rig.end_inspection()
	assert_almost_eq(camera.position.y, 0.06, 0.000001, "old inspection pose cannot override recenter")

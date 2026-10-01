## Desktop fallback: mouse look from the design eye point (the rig's
## parent). Left click actuates the control under the cursor (cycle); plain
## scroll pushes it up or down. Shift-scroll magnifies the view. Z inspects a
## pointed control, or the current look direction, and Z/Esc returns to the
## original view. The "recenter" action (Home) resets the view.
## This desktop camera's FOV never changes the XR rig.
## Adapted from gemini-capsule at 40e449c (README.md lists the port). Its
## keyboard head movement is left out: W/A/S/D/Q/E fly the rotation
## controller here (HandControllerInput), and R, its recenter key, is the
## translation controller's +X.
extends Node3D

signal inspection_changed(active: bool, magnification: float)

const NORMAL_FOV := 90.0
const MIN_FOV := 12.0
const INSPECTION_ZOOM := 2.5
const WHEEL_ZOOM_STEP := 1.2

@export var look_sensitivity: float = 0.002
@export var click_range: float = 1.5

@onready var _camera: Camera3D = $Camera3D

## Seated-height calibration, metres above the design eye (same as the XR rig).
var height_offset := 0.0
var _yaw := 0.0
var _pitch := 0.0
var _captured := false
var _window_focused := true
var _inspecting := false
var _saved_view := Transform3D.IDENTITY
var _saved_fov := NORMAL_FOV
var _saved_yaw := 0.0
var _saved_pitch := 0.0


func _ready() -> void:
	recenter()


func recenter() -> void:
	_inspecting = false
	_yaw = 0.0
	_pitch = 0.0
	_camera.position = Vector3(0, height_offset, 0)
	_camera.rotation = Vector3.ZERO
	_camera.fov = NORMAL_FOV
	_publish_inspection()


func zoom_factor() -> float:
	return tan(deg_to_rad(NORMAL_FOV) * 0.5) / tan(deg_to_rad(_camera.fov) * 0.5)


func is_inspecting() -> bool:
	return _inspecting


func _publish_inspection() -> void:
	var magnification := zoom_factor()
	Bus.set_value("present.inspect.zoom_factor", magnification)
	inspection_changed.emit(_inspecting, magnification)


func _begin_inspection() -> void:
	if _inspecting:
		return
	_saved_view = _camera.transform
	_saved_fov = _camera.fov
	_saved_yaw = _yaw
	_saved_pitch = _pitch
	_inspecting = true


## Magnification follows the perspective projection, not a linear FOV ratio.
func set_zoom_factor(factor: float) -> void:
	if not is_finite(factor):
		return
	var maximum := tan(deg_to_rad(NORMAL_FOV) * 0.5) / tan(deg_to_rad(MIN_FOV) * 0.5)
	factor = clampf(factor, 1.0, maximum)
	if factor > 1.0:
		_begin_inspection()
	_camera.fov = clampf(rad_to_deg(2.0 * atan(tan(deg_to_rad(NORMAL_FOV) * 0.5) / factor)), MIN_FOV, NORMAL_FOV)
	_publish_inspection()


## Reset magnification while retaining the current direction. Use
## end_inspection() to restore the saved position and direction as well.
func reset_zoom() -> void:
	set_zoom_factor(1.0)


## Checklist Find uses the installed touch centre and never moves the head,
## the control, or the simulation. Repeated Finds retain the first view.
func focus_control(control: Node3D) -> bool:
	if not is_instance_valid(control) or not control.is_inside_tree() \
			or control.get_viewport() != get_viewport():
		return false
	var touch := control.get_node_or_null("Touch") as Node3D
	var target := touch.global_position if touch else control.global_position
	var direction := to_local(target) - _camera.position
	if direction.length_squared() < 0.000001:
		return false
	_begin_inspection()
	var horizontal := Vector2(direction.x, direction.z).length()
	if horizontal > 0.000001:
		_yaw = atan2(-direction.x, -direction.z)
	_pitch = atan2(direction.y, horizontal)
	_camera.rotation = Vector3(_pitch, _yaw, 0)
	set_zoom_factor(INSPECTION_ZOOM)
	return true


func end_inspection() -> void:
	if not _inspecting:
		return
	_camera.transform = _saved_view
	_camera.fov = _saved_fov
	_yaw = _saved_yaw
	_pitch = _saved_pitch
	_inspecting = false
	_publish_inspection()


func restore_view() -> void:
	end_inspection()


func release_mouse_look() -> void:
	_captured = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_window_focused = false
		release_mouse_look()
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_window_focused = true


func _unhandled_input(event: InputEvent) -> void:
	if not _window_focused:
		return
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.shift_pressed:
			if event.pressed:
				var steps := maxf(event.factor, 0.0) * (1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
				set_zoom_factor(zoom_factor() * pow(WHEEL_ZOOM_STEP, steps))
			get_viewport().set_input_as_handled()
			return
		if not event.pressed:
			return
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				_captured = not _captured
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _captured else Input.MOUSE_MODE_VISIBLE
				if _captured and get_viewport().gui_get_focus_owner():
					get_viewport().gui_get_focus_owner().release_focus()
			MOUSE_BUTTON_LEFT:
				_click(event.position, 0)
			MOUSE_BUTTON_WHEEL_UP:
				_click(event.position, 1)
			MOUSE_BUTTON_WHEEL_DOWN:
				_click(event.position, -1)
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _captured:
		_yaw -= event.relative.x * look_sensitivity
		_pitch = clampf(_pitch - event.relative.y * look_sensitivity, -PI / 2.0, PI / 2.0)
		_camera.rotation = Vector3(_pitch, _yaw, 0.0)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if _inspecting:
			end_inspection()
		elif _captured:
			release_mouse_look()
		else:
			return
		get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if not event.pressed or event.echo:
			return
		if get_viewport().gui_get_focus_owner():
			return
		if code == KEY_Z and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
			if _inspecting:
				end_inspection()
			else:
				var control := _control_at(get_viewport().get_mouse_position())
				if control == null or not focus_control(control):
					set_zoom_factor(INSPECTION_ZOOM)
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("recenter"):
			recenter()
			get_viewport().set_input_as_handled()


## Far-field actuation: ray from the camera through the cursor (or the screen
## centre when the mouse is captured) to the nearest control touch volume.
func _click(screen_pos: Vector2, dir: int) -> void:
	var control := _control_at(screen_pos)
	if control:
		control.actuate_far(dir)


func _control_at(screen_pos: Vector2) -> ControlBase:
	if _captured:
		screen_pos = get_viewport().get_visible_rect().size / 2.0
	var from := _camera.project_ray_origin(screen_pos)
	var to := from + _camera.project_ray_normal(screen_pos) * click_range
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var control := (hit.collider as Node).get_parent()
	return control as ControlBase


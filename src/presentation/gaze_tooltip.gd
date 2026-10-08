## Gaze tooltip (docs/VR_INTERACTION.md §5): look at a control for a moment
## and a small label above it gives its name and position, for learning
## the panels. It rides on the camera: the gaze ray is the camera's forward
## axis in a headset, and the pointer's ray (the free cursor, or the centre
## when the mouse is captured) on the desktop. Off in authentic mode.
## Taken from gemini-capsule's src/presentation/gaze_tooltip.gd at 40e449c
## (README.md lists the port); only these comments changed. Presentation
## only.
##
## Reads:  present.comfort.authentic
## Writes: present.tooltip.control (the control's node name, or ""),
##         present.tooltip.text
class_name GazeTooltip
extends Node3D

@export var reach: float = 1.5
@export var dwell_s: float = 0.4
@export var sample_s: float = 0.1
@export var enabled: bool = true
## Desktop uses the same free cursor / captured-centre ray as actuation.
## Leave unset in XR to retain the tracked head's gaze ray.
var pointer_camera: Camera3D

var _label: Label3D
var _candidate: ControlBase
var _dwell := 0.0
var _since_sample := 0.0
var _shown: ControlBase


func _ready() -> void:
	_label = Label3D.new()
	_label.name = "Tip"
	_label.font_size = 28
	_label.pixel_size = 0.0005
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.modulate = Color(1.0, 0.95, 0.7)
	_label.outline_size = 8
	_label.visible = false
	_label.top_level = true
	add_child(_label)


func _process(delta: float) -> void:
	_since_sample += delta
	if _since_sample < sample_s:
		return
	var dt := _since_sample
	_since_sample = 0.0
	observe(_gazed_control(), dt)


## Ray from the camera along its forward axis to the nearest control touch volume.
func _gazed_control() -> ControlBase:
	var from := global_position
	var to := from - global_transform.basis.z * reach
	if pointer_camera:
		var viewport := get_viewport()
		var screen_pos := viewport.get_visible_rect().size / 2.0
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			if viewport.gui_get_hovered_control() != null:
				return null
			screen_pos = viewport.get_mouse_position()
		from = pointer_camera.project_ray_origin(screen_pos)
		to = from + pointer_camera.project_ray_normal(screen_pos) * reach
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return null
	var c := (hit.collider as Node).get_parent()
	return c if c is ControlBase and c.is_visible_in_tree() else null


## Dwell logic, separated from the ray so tests can feed a control directly.
func observe(c: ControlBase, dt: float) -> void:
	var allowed := enabled and not bool(Bus.get_value("present.comfort.authentic", false))
	if c == null or not allowed:
		_candidate = null
		_dwell = 0.0
		_hide()
		return
	if c != _candidate:
		_candidate = c
		_dwell = 0.0
	_dwell += dt
	if _dwell >= dwell_s:
		_show(c)
	elif _shown != c:
		_hide()


static func state_text(c: ControlBase) -> String:
	if "closed" in c:
		return "CLOSED" if bool(c.get("closed")) else "OPEN"
	if "position_index" in c:
		var i := int(c.get("position_index"))
		var labels = c.get("labels")
		if labels != null and i >= 0 and i < Array(labels).size():
			return (labels as PackedStringArray)[i]
		return str(i)
	if "value" in c:
		if c.has_method("pull"):
			return "PULLED" if bool(c.get("value")) else "RELEASED"
		return "ON" if bool(c.get("value")) else "OFF"
	return ""


static func text_for(c: ControlBase) -> String:
	var name_text: String = c.label if c.label != "" else c.name
	var state := state_text(c)
	return "%s\n%s" % [name_text, state] if state != "" else name_text


func _show(c: ControlBase) -> void:
	_shown = c
	_label.text = text_for(c)
	_label.global_position = c.global_position + c.global_transform.basis.y * 0.03 + c.global_transform.basis.z * 0.02
	_label.visible = true
	Bus.set_value("present.tooltip.control", c.name)
	Bus.set_value("present.tooltip.text", _label.text)


func _hide() -> void:
	if _shown == null and not _label.visible:
		return
	_shown = null
	_label.visible = false
	Bus.set_value("present.tooltip.control", "")
	Bus.set_value("present.tooltip.text", "")

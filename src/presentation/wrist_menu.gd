## Wrist menu (docs/ROADMAP.md, slice 2d): the pushbuttons for what the 2D
## HUD offers beyond the cabin's panels: Mission Control's PAD requests,
## the time rate and pause, recentre and eye height, and the checklist. In
## a headset it rides on the left hand and shows when the palm faces the
## head, or on the left controller's menu button; on the desktop it rides
## on the camera and M shows it. A status line gives GET, the time rate
## and whether the clock is paused.
## Adapted from gemini-capsule's src/presentation/wrist_menu.gd at 40e449c
## (README.md lists the port): its comfort, guide and new-flight buttons
## stay behind, it doesn't save settings yet, and the PAD buttons write
## ctl.ground.pad_request, the channel the HUD's Mission Control buttons
## write. The buttons are presentation controls, so they work while time
## acceleration locks the panels.
##
## Writes: ctl.ground.pad_request, present.menu.visible,
##         present.checklist.highlight_enabled, player.eye_height_offset_m
class_name WristMenu
extends Node3D

const PUSHBUTTON := preload("res://scenes/controls/pushbutton.tscn")
const HEIGHT_STEP := 0.01
const HEIGHT_LIMIT := 0.15
## Button id -> label, in layout order.
const BUTTONS := [
	["mcc", "MCC"], ["loi", "LOI-1"], ["circ", "LOI-2"], ["tei", "TEI"],
	["slower", "RATE -"], ["faster", "RATE +"], ["pause", "PAUSE"], ["recenter", "RECENTRE"],
	["eye_up", "EYE +1cm"], ["eye_down", "EYE -1cm"], ["highlight", "HILITE"], ["hide", "HIDE"],
	["checklist", "CHECKLIST"], ["next", "NEXT STEP"],
]
## The PAD request each Mission Control button makes (MissionSequencer.request_pad).
const PAD_REQUESTS := ["mcc", "loi", "circ", "tei"]
const COLS := 4
const PITCH := Vector2(0.042, 0.034)
## Controller action that shows or hides the menu.
const TOGGLE_ACTION := "menu_button"
## Where the desktop menu rides, from the camera (m): low on the right,
## near enough to read its legends without zooming.
const DESKTOP_POSITION := Vector3(0.15, -0.10, -0.28)

## Hand-local axis out of the palm; the menu shows when it faces the head.
## XR controller poses put +X roughly through the left palm.
@export var palm_axis: Vector3 = Vector3.RIGHT
@export var show_dot: float = 0.55
@export var hide_dot: float = 0.35

var rig: Node3D
var head: Node3D
var hand: Node3D
var book: ChecklistBook
var status_label: Label3D
var _buttons: Dictionary = {}
var _touch_layers: Dictionary = {}
var _shown := false
## Shown by the key or the controller button rather than the palm.
var _pinned := false
## Rearm the palm gesture only after the hand turns away.
var _palm_dismissed := false


func _ready() -> void:
	@warning_ignore("integer_division")
	var rows := (BUTTONS.size() + COLS - 1) / COLS
	var back := MeshInstance3D.new()
	back.name = "Back"
	var bm := BoxMesh.new()
	bm.size = Vector3(PITCH.x * COLS + 0.01, PITCH.y * rows + 0.03, 0.004)
	back.mesh = bm
	back.position = Vector3(0, 0.008, -0.004)
	back.material_override = CabinMaterials.get_material("dsky_case")
	add_child(back)
	status_label = Label3D.new()
	status_label.name = "Status"
	status_label.font_size = 32
	status_label.pixel_size = 0.00018
	status_label.outline_size = 0
	status_label.modulate = Color(0.45, 1.0, 0.55)
	status_label.position = Vector3(0, PITCH.y * rows * 0.5 + 0.008, 0.001)
	add_child(status_label)
	for i in BUTTONS.size():
		var id: String = BUTTONS[i][0]
		var b: Node3D = PUSHBUTTON.instantiate()
		b.name = id
		b.set("label", BUTTONS[i][1])
		b.set("presentation_only", true)
		var touch := Area3D.new()
		touch.name = "Touch"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.036, 0.026, 0.02)
		shape.shape = box
		touch.add_child(shape)
		touch.position.z = 0.01
		b.add_child(touch)
		@warning_ignore("integer_division")
		var row := i / COLS
		var col := i % COLS
		b.position = Vector3((col - (COLS - 1) / 2.0) * PITCH.x, ((rows - 1) / 2.0 - row) * PITCH.y - 0.004, 0.0)
		var l := Label3D.new()
		l.name = "Legend"
		l.text = BUTTONS[i][1]
		l.font_size = 32
		l.pixel_size = 0.0002
		l.outline_size = 0
		l.modulate = CabinMaterials.lettering_colour()
		l.position = Vector3(0, 0.0145, 0.001)
		b.add_child(l)
		b.connect("activated", _on_button.bind(id))
		add_child(b)
		_buttons[id] = b
		_touch_layers[id] = touch.collision_layer
	_set_shown(false)


## Wire the menu to what it drives. [param hand_node] null means the
## desktop: the menu rides on [param head_node] and M shows it.
func setup(rig_node: Node3D, head_node: Node3D, hand_node: Node3D, p_book: ChecklistBook) -> void:
	rig = rig_node
	head = head_node
	hand = hand_node
	book = p_book
	if hand:
		hand.add_child(self)
		position = Vector3(0.0, 0.06, 0.0)
		rotation_degrees = Vector3(-90, 0, 0)
		if hand.has_signal("button_pressed"):
			hand.connect("button_pressed", _on_hand_button)
	else:
		head.add_child(self)
		# Face the eye from low on the right of the view.
		transform = Transform3D(Basis.looking_at(DESKTOP_POSITION, Vector3.UP), DESKTOP_POSITION)
	Bus.set_value("present.checklist.highlight_enabled", true)


func _process(_delta: float) -> void:
	if hand and head:
		var palm: Vector3 = hand.global_transform.basis * palm_axis
		var to_head: Vector3 = (head.global_position - hand.global_position).normalized()
		var d := palm.dot(to_head)
		if d < hide_dot:
			_palm_dismissed = false
		if not _shown and not _palm_dismissed and d > show_dot:
			_pinned = false
			_set_shown(true)
		elif _shown and d < hide_dot and not _pinned:
			_set_shown(false)
	if _shown:
		status_label.text = "GET %s   x%d%s" % [SimClock.get_display(), int(SimClock.rate), "   PAUSED" if SimClock.paused else ""]


## The controller's menu button shows and hides the menu whatever the palm does.
func _on_hand_button(action: String) -> void:
	if action == TOGGLE_ACTION:
		if _shown:
			_dismiss()
		else:
			_pinned = true
			_set_shown(true)


func _dismiss() -> void:
	_palm_dismissed = true
	_pinned = false
	_set_shown(false)


func _unhandled_input(event: InputEvent) -> void:
	if hand == null and event is InputEventKey and event.pressed and not event.echo \
			and (event.physical_keycode == KEY_M or event.keycode == KEY_M):
		_set_shown(not _shown)
		get_viewport().set_input_as_handled()


func _set_shown(on: bool) -> void:
	_shown = on
	visible = on
	for id in _buttons:
		var b: Node3D = _buttons[id]
		if not on:
			# A hidden button may never see the finger leave.
			b.set("_touching", null)
			b.call("release")
		var t: Area3D = b.get_node("Touch")
		t.monitoring = on
		t.monitorable = on
		# Hidden buttons must not stop the pointer on its way to the panels.
		t.collision_layer = int(_touch_layers[id]) if on else 0
	Bus.set_value("present.menu.visible", on)


func is_shown() -> bool:
	return _shown


func button(id: String) -> ControlBase:
	return _buttons.get(id)


## Act on a button by id, as its press does.
func activate(id: String) -> void:
	_on_button(id)


func _on_button(id: String) -> void:
	if id in PAD_REQUESTS:
		Bus.set_value("ctl.ground.pad_request", id)
		return
	match id:
		"slower":
			SimClock.slower()
		"faster":
			SimClock.faster()
		"pause":
			SimClock.paused = not SimClock.paused
		"recenter":
			if rig and rig.has_method("recenter"):
				rig.call("recenter")
		"eye_up", "eye_down":
			if rig:
				var h := clampf(float(rig.get("height_offset")) + (HEIGHT_STEP if id == "eye_up" else -HEIGHT_STEP),
					-HEIGHT_LIMIT, HEIGHT_LIMIT)
				rig.set("height_offset", h)
				Bus.set_value("player.eye_height_offset_m", h)
				if rig.has_method("recenter"):
					rig.call("recenter")
		"highlight":
			Bus.set_value("present.checklist.highlight_enabled",
				not bool(Bus.get_value("present.checklist.highlight_enabled", true)))
		"checklist":
			if book:
				book.cycle()
		"next":
			if book:
				book.next()
		"hide":
			_dismiss()

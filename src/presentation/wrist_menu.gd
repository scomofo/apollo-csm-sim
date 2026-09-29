## Wrist menu (docs/ROADMAP.md, slice 2d): the pushbuttons for what the 2D
## HUD offers beyond the cabin's panels: Mission Control's PAD requests,
## the time rate and pause, recentre, eye height and seat, the checklist,
## and the comfort aids. In a headset it rides on the left hand and shows
## when the palm faces the head, or on the left controller's menu button;
## on the desktop it rides on the camera and M shows it. A status line
## gives GET, the time rate, the worst recent frame time and the seat.
## Adapted from gemini-capsule's src/presentation/wrist_menu.gd at 40e449c
## (README.md lists the port): its guide button stays behind, its
## new-flight button is the FLIGHT page below, SEAT is new, it doesn't
## save settings yet, and the PAD buttons
## write ctl.ground.pad_request, the channel the HUD's Mission Control
## buttons write. They ask for the PADs of the vehicle flown (set_vehicle):
## Columbia's MCC, LOI-1, LOI-2 and TEI, or Eagle's DOI, PDI, ASCENT and
## CSI. The buttons are presentation controls, so they work while time
## acceleration locks the panels.
##
## FLIGHT turns it to its flight page (docs/ROADMAP.md, slice 8a): every
## mission under data/missions/ and its start phases, stepped through with
## < MISSION, MISSION >, < PHASE and PHASE > (FlightChoice), a line from
## the mission's data on each, START for that flight (flight_requested,
## which the main scene starts in place of this one) and BACK. show_flights()
## opens it there, as the main scene does at launch and on F1.
##
## Reads:  perf.frame_ms_max
## Writes: ctl.ground.pad_request, present.menu.visible,
##         present.checklist.highlight_enabled, player.eye_height_offset_m
class_name WristMenu
extends Node3D

## START on the flight page: the flight chosen.
signal flight_requested(mission_id: String, phase: String)

const PUSHBUTTON := preload("res://scenes/controls/pushbutton.tscn")
const HEIGHT_STEP := 0.01
const HEIGHT_LIMIT := 0.15
## Button id -> label, in layout order.
const BUTTONS := [
	["mcc", "MCC"], ["loi", "LOI-1"], ["circ", "LOI-2"], ["tei", "TEI"],
	["slower", "RATE -"], ["faster", "RATE +"], ["pause", "PAUSE"], ["recenter", "RECENTRE"],
	["eye_up", "EYE +1cm"], ["eye_down", "EYE -1cm"], ["seat", "SEAT"], ["hide", "HIDE"],
	["checklist", "CHECKLIST"], ["next", "NEXT STEP"], ["highlight", "HILITE"], ["vignette", "VIGNETTE"],
	["horizon", "HORIZON"], ["authentic", "AUTHENTIC"], ["flight", "FLIGHT"],
]
## The flight page's buttons, in layout order, under the choice's lines.
const FLIGHT_BUTTONS := [
	["mission_prev", "< MISSION"], ["mission_next", "MISSION >"], ["phase_prev", "< PHASE"], ["phase_next", "PHASE >"],
	["start", "START"], ["back", "BACK"],
]
## The PAD request each Mission Control button makes (MissionSequencer.request_pad),
## in Columbia: the first four buttons' ids.
const PAD_REQUESTS := ["mcc", "loi", "circ", "tei"]
## The four PAD buttons' [request, label] for each vehicle, as the HUD's
## Mission Control buttons.
const PADS := {
	"csm": [["mcc", "MCC"], ["loi", "LOI-1"], ["circ", "LOI-2"], ["tei", "TEI"]],
	"lm": [["doi", "DOI"], ["pdi", "PDI"], ["ascent", "ASCENT"], ["csi", "CSI"]],
}
const COLS := 4
const PITCH := Vector2(0.042, 0.034)
## The flight page's lines take the rows above its buttons.
const FLIGHT_TEXT_WIDTH_PX := 780
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
## Optional: the comfort aids its VIGNETTE, HORIZON and AUTHENTIC buttons
## switch, and the cabin whose seat SEAT changes.
var comfort: Comfort
var cabin: Cabin
## The vehicle flown, whose PADs the PAD buttons ask for: "csm" or "lm".
var vehicle: String = "csm"
## The flight page's missions and start phases, and the one chosen: the
## flight flown, until the page steps away from it.
var choice: FlightChoice
## The page showing: "main", or "flight".
var page: String = "main"
var status_label: Label3D
## The flight page's lines: the mission, the start phase and its note.
var choice_label: Label3D
var _buttons: Dictionary = {}
## Button id -> its page.
var _page_of: Dictionary = {}
var _touch_layers: Dictionary = {}
## The four PAD buttons, in order.
var _pad_buttons: Array[Node3D] = []
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
		@warning_ignore("integer_division")
		var b := _make_button(BUTTONS[i][0], BUTTONS[i][1], "main", i / COLS, i % COLS, rows)
		# A PAD button asks for whatever its vehicle's PAD is at the press.
		if i < PAD_REQUESTS.size():
			b.connect("activated", _on_pad.bind(i))
			_pad_buttons.append(b)
		else:
			b.connect("activated", _on_button.bind(BUTTONS[i][0]))
	# The flight page: its buttons in the bottom rows, its lines above.
	@warning_ignore("integer_division")
	var flight_rows := (FLIGHT_BUTTONS.size() + COLS - 1) / COLS
	for i in FLIGHT_BUTTONS.size():
		@warning_ignore("integer_division")
		var b := _make_button(FLIGHT_BUTTONS[i][0], FLIGHT_BUTTONS[i][1], "flight", rows - flight_rows + i / COLS,
			i % COLS, rows)
		b.connect("activated", _on_button.bind(FLIGHT_BUTTONS[i][0]))
	choice_label = Label3D.new()
	choice_label.name = "Choice"
	choice_label.font_size = 32
	choice_label.pixel_size = 0.00018
	choice_label.outline_size = 0
	choice_label.modulate = CabinMaterials.lettering_colour()
	choice_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	choice_label.width = FLIGHT_TEXT_WIDTH_PX
	choice_label.position = Vector3(0, ((rows - 1) / 2.0 - (rows - flight_rows - 1) / 2.0) * PITCH.y, 0.001)
	add_child(choice_label)
	_set_shown(false)
	set_vehicle(vehicle)


## Button [param id] lettered [param legend] on [param p_page], at
## [param row] and [param col] of the grid of [param rows].
func _make_button(id: String, legend: String, p_page: String, row: int, col: int, rows: int) -> Node3D:
	var b: Node3D = PUSHBUTTON.instantiate()
	b.name = id
	b.set("label", legend)
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
	b.position = Vector3((col - (COLS - 1) / 2.0) * PITCH.x, ((rows - 1) / 2.0 - row) * PITCH.y - 0.004, 0.0)
	var l := Label3D.new()
	l.name = "Legend"
	l.text = legend
	l.font_size = 32
	l.pixel_size = 0.0002
	l.outline_size = 0
	l.modulate = CabinMaterials.lettering_colour()
	l.position = Vector3(0, 0.0145, 0.001)
	b.add_child(l)
	add_child(b)
	_buttons[id] = b
	_touch_layers[id] = touch.collision_layer
	_page_of[id] = p_page
	return b


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
		status_label.text = "GET %s   x%d%s   %.1f ms   %s" % [SimClock.get_display(), int(SimClock.rate),
			"   PAUSED" if SimClock.paused else "", float(Bus.get_value("perf.frame_ms_max", 0.0)),
			cabin.seat if cabin != null else ""]


## The controller's menu button shows and hides the menu whatever the palm does.
func _on_hand_button(action: String) -> void:
	if action == TOGGLE_ACTION:
		if _shown:
			_dismiss()
		else:
			_pinned = true
			_set_shown(true)


## Close the menu, as HIDE does.
func close() -> void:
	_dismiss()


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
	_show_buttons()
	Bus.set_value("present.menu.visible", on)


## Only the page showing takes the finger and the pointer.
func _show_buttons() -> void:
	for id in _buttons:
		var b: Node3D = _buttons[id]
		var on: bool = _shown and _page_of[id] == page
		if not on:
			# A hidden button may never see the finger leave.
			b.set("_touching", null)
			b.call("release")
		b.visible = _page_of[id] == page
		var t: Area3D = b.get_node("Touch")
		t.monitoring = on
		t.monitorable = on
		# Hidden buttons must not stop the pointer on its way to the panels.
		t.collision_layer = int(_touch_layers[id]) if on else 0
	if choice_label:
		choice_label.visible = page == "flight"


## Turn to [param p_page]: "main" or "flight".
func show_page(p_page: String) -> void:
	page = p_page
	if page == "flight":
		if choice == null:
			choice = FlightChoice.new()
		choice_label.text = choice.text()
	_show_buttons()


## Open the menu on its flight page, pinned open as the controller's
## button pins it.
func show_flights() -> void:
	_pinned = true
	show_page("flight")
	_set_shown(true)


func is_shown() -> bool:
	return _shown


func button(id: String) -> ControlBase:
	return _buttons.get(id)


## Ask for [param v]'s PADs ("csm" or "lm") on the PAD buttons: each takes
## that vehicle's request as its id and its name as its legend.
func set_vehicle(v: String) -> void:
	vehicle = v
	var pads: Array = PADS[v]
	for i in _pad_buttons.size():
		var b := _pad_buttons[i]
		var old := str(b.name)
		var id: String = pads[i][0]
		var layer: int = _touch_layers[old]
		_buttons.erase(old)
		_touch_layers.erase(old)
		_page_of.erase(old)
		b.name = id
		b.set("label", pads[i][1])
		(b.get_node("Legend") as Label3D).text = pads[i][1]
		_buttons[id] = b
		_touch_layers[id] = layer
		_page_of[id] = "main"


## The PAD requests the PAD buttons make now.
func pad_requests() -> Array:
	return (PADS[vehicle] as Array).map(func(p: Array) -> String: return p[0])


## Act on a button by id, as its press does.
func activate(id: String) -> void:
	_on_button(id)


func _on_pad(i: int) -> void:
	Bus.set_value("ctl.ground.pad_request", PADS[vehicle][i][0])


func _on_button(id: String) -> void:
	if id in pad_requests():
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
		"seat":
			if cabin:
				cabin.next_seat()
		"highlight":
			Bus.set_value("present.checklist.highlight_enabled",
				not bool(Bus.get_value("present.checklist.highlight_enabled", true)))
		"vignette", "horizon", "authentic":
			if comfort:
				match id:
					"vignette": comfort.vignette_enabled = not comfort.vignette_enabled
					"horizon": comfort.horizon_aid = not comfort.horizon_aid
					"authentic": comfort.authentic = not comfort.authentic
				comfort.update_from_bus()
		"checklist":
			if book:
				book.cycle()
		"next":
			if book:
				book.next()
		"hide":
			_dismiss()
		"flight":
			show_page("flight")
		"back":
			show_page("main")
		"mission_prev", "mission_next", "phase_prev", "phase_next":
			if choice == null:
				choice = FlightChoice.new()
			var step := -1 if id.ends_with("prev") else 1
			if id.begins_with("mission"):
				choice.step_mission(step)
			else:
				choice.step_phase(step)
			choice_label.text = choice.text()
		"start":
			if choice != null:
				flight_requested.emit(choice.mission_id(), choice.phase())

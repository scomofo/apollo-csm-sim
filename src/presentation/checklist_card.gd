## The cabin's checklist card (docs/ROADMAP.md, slice 2d): the open
## checklist around its current step, the last PAD Mission Control uplinked
## and the CAPCOM log, printed on a card by the commander's left shoulder
## and readable from the couch. It renders the shared ChecklistBook and
## reads mission.pad_text and mission.capcom from the Bus. Presentation
## only; the wrist menu's CHECKLIST and NEXT STEP buttons drive the book.
class_name ChecklistCard
extends Node3D

## Card face (m).
const SIZE := Vector2(0.26, 0.30)
const MARGIN := 0.012
## Capital heights (m) [estimated]: legible at the card's 0.5 m.
const TITLE_HEIGHT := 0.0065
const TEXT_HEIGHT := 0.0050
const STEP_LINES := 8
const CAPCOM_LINES := 4
const PAPER := Color(0.92, 0.90, 0.82)
const INK := Color(0.06, 0.06, 0.08)
const DONE_INK := Color(0.42, 0.44, 0.42)
const CURRENT_BAR := Color(1.0, 0.78, 0.3)

var book: ChecklistBook
var title_label: Label3D
var step_labels: Array[Label3D] = []
var pad_label: Label3D
var capcom_label: Label3D
var _bar: MeshInstance3D
var _capcom: PackedStringArray = []
var _shown_key: Array = []


func _ready() -> void:
	var plate := MeshInstance3D.new()
	plate.name = "Plate"
	var pm := BoxMesh.new()
	pm.size = Vector3(SIZE.x, SIZE.y, 0.003)
	plate.mesh = pm
	var paper := StandardMaterial3D.new()
	paper.albedo_color = PAPER
	paper.roughness = 0.9
	plate.material_override = paper
	plate.position.z = -0.0015
	add_child(plate)
	_bar = MeshInstance3D.new()
	_bar.name = "CurrentStep"
	_bar.mesh = QuadMesh.new()
	var bar := StandardMaterial3D.new()
	bar.albedo_color = CURRENT_BAR
	bar.roughness = 0.9
	_bar.material_override = bar
	_bar.visible = false
	add_child(_bar)
	title_label = _text("Title", TITLE_HEIGHT)
	for i in STEP_LINES + 1:
		step_labels.append(_text("Step%d" % i, TEXT_HEIGHT))
	pad_label = _text("Pad", TEXT_HEIGHT)
	pad_label.text = "PAD  none uplinked"
	capcom_label = _text("Capcom", TEXT_HEIGHT)
	capcom_label.text = "CAPCOM"
	Bus.subscribe("mission.pad_text", _on_pad)
	Bus.subscribe("mission.capcom", _on_capcom)
	_layout()


func _text(node_name: String, height: float) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.font = ThemeDB.fallback_font
	l.font_size = 48
	l.pixel_size = height / 34.0
	l.outline_size = 0
	l.modulate = INK
	l.shaded = false
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.width = (SIZE.x - 2.0 * MARGIN) / l.pixel_size
	l.position.z = 0.0008
	add_child(l)
	return l


func _on_pad(v: Variant) -> void:
	pad_label.text = "PAD  " + str(v) if v != null and str(v) != "" else "PAD  none uplinked"
	_layout()


func _on_capcom(v: Variant) -> void:
	if v == null or str(v) == "":
		return
	_capcom.append(str(v))
	while _capcom.size() > CAPCOM_LINES:
		_capcom.remove_at(0)
	capcom_label.text = "CAPCOM\n" + "\n".join(_capcom)
	_layout()


func _process(_delta: float) -> void:
	if book == null or book.list() == null:
		return
	book.update()
	var key := [book.current, book.list().index]
	if key != _shown_key:
		_layout()


## Stack the title, the steps, the PAD and the CAPCOM log down the card,
## each as tall as its wrapped text.
func _layout() -> void:
	var y := SIZE.y * 0.5 - MARGIN
	var x := -SIZE.x * 0.5 + MARGIN
	var c: Checklist = book.list() if book != null else null
	title_label.text = "CHECKLIST  " + (c.title.to_upper() if c != null else "")
	y = _place(title_label, x, y) - 0.006
	var steps: Array[Dictionary] = []
	if c != null:
		steps = book.window(2, STEP_LINES)
	if c != null and c.done():
		steps.append({"text": "Checklist complete.", "state": "done", "manual": false})
	_bar.visible = false
	for i in step_labels.size():
		var l := step_labels[i]
		l.visible = i < steps.size()
		if not l.visible:
			continue
		var s: Dictionary = steps[i]
		var mark := "✓ " if s["state"] == "done" else ("▶ " if s["state"] == "current" else "    ")
		l.text = mark + str(s["text"]) + ("  (NEXT STEP)" if s["state"] == "current" and s["manual"] else "")
		l.modulate = DONE_INK if s["state"] == "done" else INK
		var top := y
		y = _place(l, x, y)
		if s["state"] == "current":
			_bar.visible = true
			(_bar.mesh as QuadMesh).size = Vector2(SIZE.x - MARGIN, top - y)
			_bar.position = Vector3(0.0, (top + y) * 0.5, 0.0004)
	y = _place(pad_label, x, y - 0.008)
	_place(capcom_label, x, y - 0.008)
	_shown_key = [book.current, c.index] if c != null else []


## Put [param l]'s top-left corner at (x, top); returns the y below it.
func _place(l: Label3D, x: float, top: float) -> float:
	l.position = Vector3(x, top, l.position.z)
	var size := l.font.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, l.width, l.font_size, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE)
	return top - size.y * l.pixel_size - 0.002

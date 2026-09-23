## Checklist highlight: a pulsing frame around the cabin control the open
## checklist's current step is done on. The step's "control" names it (an
## id in data/cockpit/controls.csv); without one, it is the control that
## writes the step's check channel. The wrist menu's HILITE button turns it
## off. Adapted from gemini-capsule's src/presentation/checklist_highlight.gd
## at 40e449c (README.md lists the port): Gemini's checklist assist names
## the control, and its frame is a fixed ring; here the frame fits the
## control's footprint, so it can go round the DSKY as well as a switch.
## Off in authentic mode, as in Gemini. Presentation only.
##
## Reads:  present.checklist.highlight_enabled, present.comfort.authentic
## Writes: present.checklist.next_control (the framed control's id, or ""),
##         present.checklist.highlight (whether the frame shows)
class_name ChecklistHighlight
extends Node3D

## Clearance between the control's footprint and the frame (m).
const MARGIN := 0.006
const BAR := 0.003
const COLOUR := Color(0.4, 0.95, 0.5)

var cabin: CmCabin
var book: ChecklistBook
var target_id: String = ""
var _frame: Node3D
var _bars: Array[MeshInstance3D] = []
var _mat: StandardMaterial3D
var _t := 0.0


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOUR
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.emission_enabled = true
	_mat.emission = COLOUR
	_frame = Node3D.new()
	_frame.name = "Frame"
	_frame.visible = false
	add_child(_frame)
	for i in 4:
		var bar := MeshInstance3D.new()
		bar.mesh = BoxMesh.new()
		bar.material_override = _mat
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame.add_child(bar)
		_bars.append(bar)


## The id of the cabin control [param target] (ChecklistBook.target()) is
## done on, or "".
static func resolve(cabin_node: CmCabin, target: Dictionary) -> String:
	var id := str(target.get("control", ""))
	if id != "":
		return id if cabin_node.items.has(id) else ""
	var channel := str(target.get("channel", ""))
	if channel == "":
		return ""
	for item_id in cabin_node.items:
		var node: Node = cabin_node.items[item_id]
		if node is ControlBase and str(node.get("channel")) == channel:
			return item_id
	return ""


func _process(delta: float) -> void:
	update()
	if _frame.visible:
		_t += delta
		_mat.emission_energy_multiplier = 1.0 + 0.8 * sin(_t * 4.0)


func update() -> void:
	var id := ""
	if cabin != null and book != null and bool(Bus.get_value("present.checklist.highlight_enabled", true)) \
			and not bool(Bus.get_value("present.comfort.authentic", false)):
		id = resolve(cabin, book.target())
	if id != target_id:
		target_id = id
		if id != "":
			_frame_round(cabin.items[id])
	_frame.visible = target_id != ""
	Bus.set_value("present.checklist.next_control", target_id)
	Bus.set_value("present.checklist.highlight", _frame.visible)


## Size the frame to the control's footprint, just in front of its panel.
func _frame_round(node: Node3D) -> void:
	var half := CockpitLayout.footprint_mm(node.get_meta("row")) / 1000.0 + Vector2(MARGIN, MARGIN)
	var panel := node.get_parent() as Node3D
	_frame.global_transform = panel.global_transform * Transform3D(Basis.IDENTITY, node.position + Vector3(0, 0, 0.03))
	var sides := [[Vector3(0, half.y, 0), Vector3(2.0 * half.x + BAR, BAR, BAR)],
		[Vector3(0, -half.y, 0), Vector3(2.0 * half.x + BAR, BAR, BAR)],
		[Vector3(-half.x, 0, 0), Vector3(BAR, 2.0 * half.y, BAR)],
		[Vector3(half.x, 0, 0), Vector3(BAR, 2.0 * half.y, BAR)]]
	for i in 4:
		_bars[i].position = sides[i][0]
		(_bars[i].mesh as BoxMesh).size = sides[i][1]

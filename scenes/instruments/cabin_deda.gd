## The DEDA on Eagle's panel 6 (slice 11e): the AGS's keyboard and its
## electroluminescent windows, laid out as the LM's (the address window
## above, OPR ERR beside the data window, the keys + 7 8 9 CLR, - 4 5 6
## READ OUT, 0 1 2 3 ENTR, and HOLD below) [published: LM/AGS Operating
## Manual, Flight Program 6, 11176-6033-T000 rev. 1, section 3; its
## dimensions estimated]. The windows read the channels the AGS publishes
## under [member channel] (addr, data, opr_err); each key is the
## pushbutton prefab, whose activated signal calls Ags.press(), the call
## the 2D DedaPanel and the tests make.
class_name CabinDeda
extends Node3D

const PUSHBUTTON := preload("res://scenes/controls/pushbutton.tscn")
const LAMP := preload("res://scenes/instruments/lamp.tscn")
## [key, column, row]: columns 0-4 from the left, rows down from the top.
const KEYS := [
	["+", 0, 0], ["7", 1, 0], ["8", 2, 0], ["9", 3, 0], ["CLR", 4, 0],
	["-", 0, 1], ["4", 1, 1], ["5", 2, 1], ["6", 3, 1], ["READOUT", 4, 1],
	["0", 0, 2], ["1", 1, 2], ["2", 2, 2], ["3", 3, 2], ["ENTR", 4, 2],
	["HOLD", 2, 3],
]
const KEY_PITCH := Vector2(0.026, 0.024)
const KEY_TOP := 0.004
const EL_GREEN := Color(0.45, 1.0, 0.55)
const CAUTION_AMBER := Color(1.0, 0.62, 0.12)
## Face size (m).
const SIZE := Vector2(0.15, 0.17)

## Channel prefix the AGS publishes the windows under.
@export var channel: String = "lm.deda"

## The AGS (Cabin.connect_runtime sets it): its press() takes the keys.
var ags: Object
## Key name -> pushbutton node.
var keys: Dictionary = {}
## "addr" and "data" -> Label3D.
var fields: Dictionary = {}
var opr_err: Node3D
var _mono: SystemFont


func _ready() -> void:
	_mono = SystemFont.new()
	_mono.font_names = PackedStringArray(["DejaVu Sans Mono", "Consolas", "Menlo", "Courier New", "monospace"])
	var case_mesh := BoxMesh.new()
	case_mesh.size = Vector3(SIZE.x, SIZE.y, 0.008)
	var body := MeshInstance3D.new()
	body.name = "Case"
	body.mesh = case_mesh
	body.material_override = CabinMaterials.get_material("dsky_case")
	add_child(body)
	_build_windows()
	_build_keys()
	for f in ["addr", "data"]:
		Bus.subscribe(channel + "." + f, _on_field.bind(f))


## Every channel the DEDA reads under [param prefix].
static func channels_read(prefix: String) -> PackedStringArray:
	return PackedStringArray([prefix + ".addr", prefix + ".data", prefix + ".opr_err"])


func _build_windows() -> void:
	for spec in [["AddrWindow", Vector2(0.046, 0.018), Vector2(0.0, 0.066)],
			["DataWindow", Vector2(0.086, 0.018), Vector2(0.018, 0.038)]]:
		var w := MeshInstance3D.new()
		w.name = spec[0]
		var m := QuadMesh.new()
		m.size = spec[1]
		w.mesh = m
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.03, 0.05, 0.035)
		dark.roughness = 0.3
		w.material_override = dark
		w.position = Vector3(spec[2].x, spec[2].y, 0.0042)
		add_child(w)
	fields["addr"] = _digits("Addr", Vector3(0.0, 0.066, 0.0045))
	fields["data"] = _digits("Data", Vector3(0.018, 0.038, 0.0045))
	opr_err = LAMP.instantiate()
	opr_err.name = "Lamp_opr_err"
	opr_err.set("channel", channel + ".opr_err")
	opr_err.set("test_channel", "")
	opr_err.set("colour", CAUTION_AMBER)
	opr_err.scale = Vector3.ONE * 0.6
	opr_err.position = Vector3(-0.050, 0.038, 0.004)
	add_child(opr_err)
	_text(opr_err, "Legend", "OPR\nERR", Vector3(0, 0, 0.0095), 0.0028 / 0.6, Color(0.08, 0.08, 0.08), true)


func _build_keys() -> void:
	for k in KEYS:
		var key_name: String = k[0]
		var b: Node3D = PUSHBUTTON.instantiate()
		b.name = "Key_" + key_name.replace("+", "PLUS").replace("-", "MINUS")
		b.set("label", key_name)
		b.set("lamp_colour", Color(0.6, 0.6, 0.62))
		# Keying stays open during time acceleration, as on the DSKY, and a
		# far-field click lets go quickly enough for the next digit.
		b.set("presentation_only", true)
		b.set("far_hold_s", 0.1)
		var touch := Area3D.new()
		touch.name = "Touch"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.023, 0.021, 0.012)
		shape.shape = box
		touch.add_child(shape)
		touch.position.z = 0.010
		b.add_child(touch)
		b.position = Vector3((float(k[1]) - 2.0) * KEY_PITCH.x, KEY_TOP - float(k[2]) * KEY_PITCH.y, 0.004)
		var legend := "READ\nOUT" if key_name == "READOUT" else key_name
		_text(b.get_node("Cap"), "Legend", legend, Vector3(0, 0, 0.0045), 0.0040 if legend.length() > 1 else 0.0065,
			CabinMaterials.lettering_colour(), false)
		b.connect("activated", _press.bind(key_name))
		add_child(b)
		keys[key_name] = b


func _press(key_name: String) -> void:
	if ags != null:
		ags.press(key_name)


func _digits(node_name: String, at: Vector3) -> Label3D:
	var l := _text(self, node_name, "", at, 0.0095, EL_GREEN, false)
	l.font = _mono
	return l


## Lettering [param height] m tall (capital height, roughly).
func _text(parent: Node, node_name: String, text: String, at: Vector3, height: float, colour: Color, shaded: bool) -> Label3D:
	var l := Label3D.new()
	l.name = node_name
	l.text = text
	l.font = ThemeDB.fallback_font
	l.font_size = 64
	l.pixel_size = height / 45.0
	l.outline_size = 0
	l.modulate = colour
	l.shaded = shaded
	l.double_sided = false
	l.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = at
	parent.add_child(l)
	return l


func _on_field(v: Variant, field: String) -> void:
	fields[field].text = str(v) if v != null else ""

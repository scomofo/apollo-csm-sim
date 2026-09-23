## The cabin DSKY on the main display console: the Block II DSKY's status
## and caution lamps, its electroluminescent display and its 19 keys.
## The display reads the channels the CMC publishes under [member channel]
## (prog, verb, noun, r1-r3, flash, comp_acty, lamp.<name>). Each key is the
## pushbutton prefab; its activated signal calls Dsky.press(), the call the
## 2D DskyPanel and the tests make. The lamp order and the keys' staggered
## columns follow the Block II DSKY; every dimension is [estimated].
class_name CabinDsky
extends Node3D

const PUSHBUTTON := preload("res://scenes/controls/pushbutton.tscn")
const LAMP := preload("res://scenes/instruments/lamp.tscn")
## [key, column, row]: columns 0-6 from the left, rows down from the top.
## VERB/NOUN and ENTR/RSET sit half a row off the digit keys.
const KEYS := [
	["VERB", 0, 0.5], ["NOUN", 0, 1.5],
	["+", 1, 0], ["7", 2, 0], ["8", 3, 0], ["9", 4, 0], ["CLR", 5, 0],
	["-", 1, 1], ["4", 2, 1], ["5", 3, 1], ["6", 4, 1], ["PRO", 5, 1],
	["0", 1, 2], ["1", 2, 2], ["2", 3, 2], ["3", 4, 2], ["KEY REL", 5, 2],
	["ENTR", 6, 0.5], ["RSET", 6, 1.5],
]
const KEY_PITCH := Vector2(0.027, 0.024)
const KEY_TOP := -0.046
const LAMP_PITCH := Vector2(0.028, 0.022)
const LAMP_TOP := 0.098
const EL_GREEN := Color(0.45, 1.0, 0.55)
const STATUS_WHITE := Color(1.0, 0.97, 0.9)
const CAUTION_AMBER := Color(1.0, 0.62, 0.12)
## Display fields, each a string channel under [member channel].
const FIELDS := ["prog", "verb", "noun", "r1", "r2", "r3"]
## Face size (m).
const SIZE := Vector2(0.20, 0.24)
## Verb and noun flash: on 0.8 s of every 1.2 s, as DskyPanel.
const BLINK_PERIOD := 1.2
const BLINK_ON := 0.8

## Channel prefix the CMC publishes the display under.
@export var channel: String = "dsky"

## The CMC's keyboard (CmCabin.connect_runtime sets it).
var dsky: Dsky
## Key name -> pushbutton node.
var keys: Dictionary = {}
## Lamp name -> lamp node.
var lamps: Dictionary = {}
## FIELDS -> Label3D.
var fields: Dictionary = {}
var flash: bool = false
var comp_acty: bool = false
var _blink: float = 0.0
var _comp_mat: StandardMaterial3D
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
	_build_lamps()
	_build_display()
	_build_keys()
	for f in FIELDS:
		Bus.subscribe(channel + "." + f, _on_field.bind(f))
	Bus.subscribe(channel + ".flash", _on_flash)
	Bus.subscribe(channel + ".comp_acty", _on_comp_acty)


## Every channel the DSKY reads under [param prefix].
static func channels_read(prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for f in FIELDS + ["flash", "comp_acty"]:
		out.append(prefix + "." + f)
	for row in DskyPanel.LAMP_ROWS:
		for lamp_name in row:
			out.append(prefix + ".lamp." + lamp_name)
	return out


func _build_lamps() -> void:
	for row in DskyPanel.LAMP_ROWS.size():
		for col in 2:
			var lamp_name: String = DskyPanel.LAMP_ROWS[row][col]
			var l: Node3D = LAMP.instantiate()
			l.name = "Lamp_" + lamp_name
			l.set("channel", channel + ".lamp." + lamp_name)
			l.set("test_channel", "")
			l.set("colour", CAUTION_AMBER if lamp_name in DskyPanel.LAMP_AMBER else STATUS_WHITE)
			l.scale = Vector3.ONE * 0.85
			l.position = Vector3(-0.072 + col * LAMP_PITCH.x, LAMP_TOP - row * LAMP_PITCH.y, 0.004)
			add_child(l)
			_text(l, "Legend", lamp_name.to_upper().replace("_", "\n"), Vector3(0, 0, 0.0095), 0.0028,
				Color(0.08, 0.08, 0.08), true)
			lamps[lamp_name] = l


func _build_display() -> void:
	var el := MeshInstance3D.new()
	el.name = "Display"
	var m := QuadMesh.new()
	m.size = Vector2(0.092, 0.136)
	el.mesh = m
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.03, 0.05, 0.035)
	dark.roughness = 0.3
	el.material_override = dark
	el.position = Vector3(0.050, 0.042, 0.0042)
	add_child(el)
	_comp_mat = StandardMaterial3D.new()
	_comp_mat.albedo_color = Color(0.05, 0.12, 0.06)
	_comp_mat.emission_enabled = true
	_comp_mat.emission = EL_GREEN
	_comp_mat.emission_energy_multiplier = 0.0
	var comp := MeshInstance3D.new()
	comp.name = "CompActy"
	var cm := QuadMesh.new()
	cm.size = Vector2(0.030, 0.020)
	comp.mesh = cm
	comp.material_override = _comp_mat
	comp.position = Vector3(0.027, 0.094, 0.0045)
	add_child(comp)
	_text(comp, "Legend", "COMP\nACTY", Vector3(0, 0, 0.0005), 0.0028, Color(0.02, 0.05, 0.02), true)
	for spec in [["PROG", "prog", Vector2(0.072, 0.100)], ["VERB", "verb", Vector2(0.027, 0.074)], ["NOUN", "noun", Vector2(0.072, 0.074)]]:
		_text(self, spec[0] + "Legend", spec[0], Vector3(spec[2].x, spec[2].y, 0.0045), 0.0030, EL_GREEN, false)
		fields[spec[1]] = _digits(spec[1].to_upper(), Vector3(spec[2].x, spec[2].y - 0.013, 0.0045))
	for i in 3:
		fields["r%d" % (i + 1)] = _digits("R%d" % (i + 1), Vector3(0.050, 0.036 - i * 0.022, 0.0045))


func _build_keys() -> void:
	for k in KEYS:
		var key_name: String = k[0]
		var b: Node3D = PUSHBUTTON.instantiate()
		b.name = "Key_" + key_name.replace(" ", "_").replace("+", "PLUS").replace("-", "MINUS")
		b.set("label", key_name)
		b.set("lamp_colour", Color(0.6, 0.6, 0.62))
		# Typing stays open during time acceleration, as on the 2D DSKY, and a
		# far-field click lets go quickly enough for the next digit.
		b.set("presentation_only", true)
		b.set("far_hold_s", 0.1)
		# A shallow touch volume around the cap, inside the key pitch: a
		# pointer from the commander's couch meets the DSKY at 45 degrees and
		# would otherwise clip the neighbouring key first.
		var touch := Area3D.new()
		touch.name = "Touch"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.024, 0.021, 0.012)
		shape.shape = box
		touch.add_child(shape)
		touch.position.z = 0.010
		b.add_child(touch)
		b.position = Vector3((float(k[1]) - 3.0) * KEY_PITCH.x, KEY_TOP - float(k[2]) * KEY_PITCH.y, 0.004)
		var legend := key_name.replace(" ", "\n")
		_text(b.get_node("Cap"), "Legend", legend, Vector3(0, 0, 0.0045), 0.0040 if legend.length() > 1 else 0.0065,
			CabinMaterials.lettering_colour(), false)
		b.connect("activated", _press.bind(key_name))
		add_child(b)
		keys[key_name] = b


func _press(key_name: String) -> void:
	if dsky != null:
		dsky.press(key_name)


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


func _on_flash(v: Variant) -> void:
	flash = bool(v)
	_blink = 0.0
	_update_flash()


func _on_comp_acty(v: Variant) -> void:
	comp_acty = bool(v)
	_comp_mat.emission_energy_multiplier = 2.0 if comp_acty else 0.0
	_comp_mat.albedo_color = EL_GREEN if comp_acty else Color(0.05, 0.12, 0.06)


func _process(delta: float) -> void:
	if flash:
		_blink = fmod(_blink + delta, BLINK_PERIOD)
		_update_flash()


## Verb and noun digits go dark in the off part of the flash.
func _update_flash() -> void:
	var on := not flash or _blink < BLINK_ON
	fields["verb"].visible = on
	fields["noun"].visible = on

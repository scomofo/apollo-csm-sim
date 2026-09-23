## Panel indicator lamp. Lit when the bus channel is truthy (bool, or a
## number above [member threshold]).
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends Node3D

@export var channel: String = ""
@export var label: String = ""
@export var colour: Color = Color(1.0, 0.6, 0.1)
@export var threshold: float = 0.5
## Bus channel (bool) that lights every lamp for a press-to-test.
@export var test_channel: String = "sys.lamp_test"

var lit: bool = false:
	set = set_lit
var _source_lit: bool = false
var _test: bool = false

@onready var _lens: MeshInstance3D = $Lens
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = colour.darkened(0.7)
	_mat.emission_enabled = true
	_mat.emission = colour
	_lens.material_override = _mat
	var bezel := get_node_or_null("Bezel") as MeshInstance3D
	if bezel:
		bezel.material_override = CabinMaterials.get_material("bezel")
	set_lit(false)
	if channel != "":
		Bus.subscribe(channel, _on_value)
	if test_channel != "":
		Bus.subscribe(test_channel, _on_test)


func _on_value(v: Variant) -> void:
	_source_lit = v if v is bool else float(v) > threshold
	set_lit(_source_lit or _test)


func _on_test(v: Variant) -> void:
	_test = bool(v)
	set_lit(_source_lit or _test)


func set_lit(value: bool) -> void:
	lit = value
	if _mat:
		_mat.emission_energy_multiplier = 3.0 if lit else 0.0
		_mat.albedo_color = colour if lit else colour.darkened(0.7)

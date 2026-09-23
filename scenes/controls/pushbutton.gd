## Pushbutton, momentary (true while held) or latching (toggles on each
## press). Publishes bool. Optional integral lamp lit from lamp_channel.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends ControlBase

## Emitted on every press (after the value and bus update).
signal activated

@export var latching: bool = false
@export var lamp_channel: String = ""
@export var lamp_colour: Color = Color(1.0, 0.85, 0.3)

var pressed: bool = false
var value: bool = false

@onready var _cap: Node3D = $Cap
var _cap_rest_z: float = 0.0
var _lamp_mat: StandardMaterial3D


func _ready() -> void:
	super()
	_cap_rest_z = _cap.position.z
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = lamp_colour.darkened(0.7)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = lamp_colour
	_lamp_mat.emission_energy_multiplier = 0.0
	$Cap/Mesh.material_override = _lamp_mat
	if lamp_channel != "":
		Bus.subscribe(lamp_channel, _on_lamp)
	if channel != "":
		Bus.set_value(channel, value)


func _touch_direction(v_local: Vector3) -> int:
	return -1 if v_local.z < 0.0 else 0   # only pushing into the panel presses


func actuate(_dir: int) -> void:
	press()


func press() -> void:
	if pressed:
		return
	pressed = true
	_cap.position.z = _cap_rest_z - 0.003
	value = (not value) if latching else true
	_publish()
	activated.emit()


func release() -> void:
	if not pressed:
		return
	pressed = false
	_cap.position.z = _cap_rest_z
	if not latching:
		value = false
		_publish()


func _publish() -> void:
	if channel != "":
		Bus.set_value(channel, value)


func _on_lamp(v: Variant) -> void:
	var lit := bool(v)
	_lamp_mat.emission_energy_multiplier = 3.0 if lit else 0.0
	_lamp_mat.albedo_color = lamp_colour if lit else lamp_colour.darkened(0.7)

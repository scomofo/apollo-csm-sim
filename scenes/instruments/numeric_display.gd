## Numeric readout (drum counter or digital) bound to a bus channel with a
## named unit conversion and printf format. Blank when unpowered.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends Node3D

@export var channel: String = ""
@export var converter: String = "none"
@export var format: String = "%5.0f"
@export var power_channel: String = ""
@export var power_min_volts: float = 20.0
@export var valid_channel: String = ""
@export var blank_text: String = "-----"

var value: float = 0.0
var _powered: bool = true
var _valid: bool = true

@onready var _label: Label3D = $Label


func _ready() -> void:
	if channel != "":
		Bus.subscribe(channel, _on_value)
	if power_channel != "":
		Bus.subscribe(power_channel, _on_power)
	if valid_channel != "":
		_valid = false
		Bus.subscribe(valid_channel, _on_valid)
	_update()


func _on_value(v: Variant) -> void:
	value = Units.convert(float(v), converter) if v != null else 0.0
	_update()


func _on_power(v: Variant) -> void:
	_powered = float(v) >= power_min_volts
	_update()


func text() -> String:
	return (format % value) if _powered and _valid else blank_text


func _on_valid(v: Variant) -> void:
	_valid = bool(v)
	_update()


func _update() -> void:
	if _label:
		_label.text = text()

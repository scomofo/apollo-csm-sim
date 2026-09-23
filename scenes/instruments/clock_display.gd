## Elapsed-time readout (hhh:mm:ss, or mm:ss for a timer) bound to a bus
## channel carrying seconds. Blank when unpowered.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends Node3D

@export var channel: String = ""
## "hhh:mm:ss" or "mm:ss"
@export var style: String = "hhh:mm:ss"
@export var power_channel: String = ""
@export var power_min_volts: float = 20.0
@export var blank_text: String = "---:--:--"

var seconds: float = 0.0
var _powered: bool = true

@onready var _label: Label3D = $Label


func _ready() -> void:
	if channel != "":
		Bus.subscribe(channel, _on_value)
	if power_channel != "":
		Bus.subscribe(power_channel, _on_power)
	_update()


func _on_value(v: Variant) -> void:
	seconds = float(v)
	_update()


func _on_power(v: Variant) -> void:
	_powered = float(v) >= power_min_volts
	_update()


static func format_seconds(s: float, style_: String) -> String:
	var t := int(floor(maxf(s, 0.0)))
	if style_ == "mm:ss":
		return "%02d:%02d" % [(t / 60) % 100, t % 60]
	return "%03d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]


func text() -> String:
	return format_seconds(seconds, style) if _powered else blank_text


func _update() -> void:
	if _label:
		_label.text = text()

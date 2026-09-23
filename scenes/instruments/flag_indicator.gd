## Two-state flag (e.g. the OFF or barber-pole flag in an instrument).
## Shows the flag when the channel is truthy, or falsy if [member inverted].
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends Node3D

@export var channel: String = ""
@export var inverted: bool = false
@export var threshold: float = 0.5

var shown: bool = false

@onready var _flag: Node3D = $Flag


func _ready() -> void:
	if channel != "":
		Bus.subscribe(channel, _on_value)
	_update()


func _on_value(v: Variant) -> void:
	var truthy := bool(v) if v is bool else float(v) > threshold
	shown = truthy != inverted
	_update()


func _update() -> void:
	if _flag:
		_flag.visible = shown

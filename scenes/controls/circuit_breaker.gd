## Push-pull circuit breaker. Pushed in = closed (bool true on the channel);
## pulled out = open, exposing the white band. Push (finger into the panel
## or wheel-down) closes, pull (wheel-up) opens, click toggles.
## Adapted from gemini-capsule at 40e449c (README.md lists the port): its
## "overhead" face style, drawn for Gemini's SC-4 overhead panel, is left out.
extends ControlBase

@export var rated_amps: float = 5.0
@export var initial_closed: bool = true

var closed: bool = true:
	set = set_closed

@onready var _stem: Node3D = $Stem


func _ready() -> void:
	super()
	set_closed(bool(Bus.get_value(channel, initial_closed)))
	if channel != "":
		Bus.subscribe(channel, _on_circuit_changed)


func _on_circuit_changed(value: Variant) -> void:
	# Automatic trips and sparse checkpoint restores move the physical handle.
	# Bus suppresses equal writes, so set_closed does not recurse indefinitely.
	set_closed(bool(value))


func set_closed(value: bool) -> void:
	closed = value
	if _stem:
		_stem.position.z = 0.004 if closed else 0.010
	if channel != "":
		Bus.set_value(channel, closed)


func _touch_direction(v_local: Vector3) -> int:
	return -1 if v_local.z < 0.0 else 1


func actuate(dir: int) -> void:
	match dir:
		-1: set_closed(true)
		1: set_closed(false)
		_: set_closed(not closed)

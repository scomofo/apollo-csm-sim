## Two- or three-position toggle switch. Position 0 is lever down.
## Publishes the integer position on [member channel], or the position's
## entry in [member values], or on a float channel in [member float_values].
##
## Variants (gemini-capsule's docs/VR_INTERACTION.md §3):
##  - guarded: a hinged guard covers the lever; the first push lifts the
##    guard, pushing down at position 0 with the guard open closes it.
##  - lever_lock: the lever must be pulled out first; the first actuation
##    unlocks for [member unlock_window_s], the second moves it.
##  - momentary positions spring back to [member rest_position] on release.
## Adapted from gemini-capsule at 40e449c (README.md lists the port): it
## starts from the position the Bus already holds (the simulation's state, a
## checkpoint, the HUD) instead of publishing initial_position over it, and
## follows later changes; publish_bool suits on/off channels, and values
## channels whose values aren't the positions in lever order.
extends ControlBase

@export var positions: int = 2
@export var labels: PackedStringArray = ["OFF", "ON"]
@export var throw_deg: float = 25.0
@export var initial_position: int = 0
@export var guarded: bool = false
@export var lever_lock: bool = false
@export var unlock_window_s: float = 1.5
## Positions that spring back to rest_position when released.
@export var momentary_positions: PackedInt32Array = []
@export var rest_position: int = 0
## Publish a bool (position 1 = true) instead of the position, for on/off
## channels that the HUD also writes as bool. Two-position switches only.
@export var publish_bool: bool = false
## The value each position publishes, lever down first, when it isn't the
## position itself: Eagle's ENG ARM is DES, OFF, ASC (2, 0, 1) and its rate
## of descent switch -1, 0, +1. A value outside the list on the channel
## leaves the lever where it is.
@export var values: PackedInt32Array = []
## On a float channel, the value each position publishes, lever down
## first: Eagle's TTCA throttle lever, its minimum and full (slice 12a). A
## value between them puts the lever at the nearer.
@export var float_values: PackedFloat64Array = []

var position_index: int = 0:
	set = set_position_index
var guard_open: bool = false:
	set = set_guard_open
var _unlocked_until: float = -1.0

@onready var _lever: Node3D = $Lever
@onready var _guard: Node3D = get_node_or_null("Guard")


func _ready() -> void:
	super()
	if _guard:
		_guard.visible = guarded
	if channel != "" and Bus.has_channel(channel):
		set_position_index(_index_of(Bus.get_value(channel)))
	else:
		set_position_index(initial_position)
	if channel != "":
		Bus.subscribe(channel, _on_channel)


func _index_of(v: Variant) -> int:
	if v is bool:
		return 1 if v else 0
	if not float_values.is_empty():
		var near := 0
		for i in float_values.size():
			if absf(float_values[i] - float(v)) < absf(float_values[near] - float(v)):
				near = i
		return near
	if values.is_empty():
		return int(v)
	var i := values.find(int(v))
	return i if i >= 0 else position_index


## The value position [param i] publishes.
func value_at(i: int) -> Variant:
	if not float_values.is_empty():
		return float_values[mini(i, float_values.size() - 1)]
	return values[i] if i < values.size() else i


func _on_channel(v: Variant) -> void:
	if _index_of(v) != position_index:
		set_position_index(_index_of(v))


func set_position_index(i: int) -> void:
	position_index = clampi(i, 0, positions - 1)
	if _lever:
		var t := 0.0 if positions == 1 else float(position_index) / float(positions - 1)
		_lever.rotation.x = deg_to_rad(lerpf(throw_deg, -throw_deg, t))
	if channel != "":
		Bus.set_value(channel, position_index == 1 if publish_bool else value_at(position_index))


func set_guard_open(open: bool) -> void:
	guard_open = open
	if _guard:
		_guard.rotation.x = deg_to_rad(-80.0) if open else 0.0


func is_unlocked() -> bool:
	return not lever_lock or Time.get_ticks_msec() / 1000.0 <= _unlocked_until


func actuate(dir: int) -> void:
	if guarded:
		if not guard_open:
			if dir >= 0:
				guard_open = true
			return
		if dir < 0 and position_index == 0:
			guard_open = false
			return
	if lever_lock and not is_unlocked():
		_unlocked_until = Time.get_ticks_msec() / 1000.0 + unlock_window_s
		return
	if dir == 0:
		set_position_index((position_index + 1) % positions)
	else:
		set_position_index(position_index + dir)
	if lever_lock:
		_unlocked_until = -1.0


func release() -> void:
	if momentary_positions.has(position_index):
		set_position_index(rest_position)

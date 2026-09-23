## Two- or three-position toggle switch. Position 0 is lever down.
## Publishes the integer position on [member channel].
##
## Variants (gemini-capsule's docs/VR_INTERACTION.md §3):
##  - guarded: a hinged guard covers the lever; the first push lifts the
##    guard, pushing down at position 0 with the guard open closes it.
##  - lever_lock: the lever must be pulled out first; the first actuation
##    unlocks for [member unlock_window_s], the second moves it.
##  - momentary positions spring back to [member rest_position] on release.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
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
	set_position_index(initial_position)


func set_position_index(i: int) -> void:
	position_index = clampi(i, 0, positions - 1)
	if _lever:
		var t := 0.0 if positions == 1 else float(position_index) / float(positions - 1)
		_lever.rotation.x = deg_to_rad(lerpf(throw_deg, -throw_deg, t))
	if channel != "":
		Bus.set_value(channel, position_index)


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

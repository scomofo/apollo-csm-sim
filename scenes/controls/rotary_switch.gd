## Rotary selector with detents. Publishes the integer position. Position 0
## is the counter-clockwise stop; each detent turns the knob clockwise by
## [member detent_deg]. A fingertip crossing left-to-right steps clockwise.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
extends ControlBase

@export var positions: int = 3
@export var labels: PackedStringArray = ["A", "B", "C"]
@export var detent_deg: float = 30.0
@export var initial_position: int = 0
## Angle of position 0 relative to straight up, degrees (negative = CCW).
@export var start_angle_deg: float = -30.0

var position_index: int = 0:
	set = set_position_index

@onready var _knob: Node3D = $Knob


func _ready() -> void:
	super()
	set_position_index(initial_position)


func set_position_index(i: int) -> void:
	position_index = clampi(i, 0, positions - 1)
	if _knob:
		_knob.rotation.z = -deg_to_rad(start_angle_deg + detent_deg * position_index)
	if channel != "":
		Bus.set_value(channel, position_index)


func _touch_direction(v_local: Vector3) -> int:
	return 1 if v_local.x > 0.0 else -1


func actuate(dir: int) -> void:
	if dir == 0:
		set_position_index((position_index + 1) % positions)
	else:
		set_position_index(position_index + dir)


func knob_angle_deg() -> float:
	return -rad_to_deg(_knob.rotation.z)

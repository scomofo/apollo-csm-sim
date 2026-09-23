## Fingertip interactor: an Area3D carried by a hand (or driven by the desktop
## rig). Controls detect it entering their touch volume and use its velocity
## to decide which way a switch was pushed. All interactors are in the
## "interactor" group.
## Taken from gemini-capsule at 40e449c (README.md lists the port).
class_name Interactor
extends Area3D

## World-space velocity of the fingertip, m/s, updated every physics frame.
var velocity: Vector3 = Vector3.ZERO
var _last_pos: Vector3 = Vector3.INF


func _ready() -> void:
	add_to_group("interactor")
	monitoring = false   # controls watch us, not the other way round
	monitorable = true
	if get_child_count() == 0:
		var shape := CollisionShape3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = 0.012
		shape.shape = sphere
		add_child(shape)


func _physics_process(delta: float) -> void:
	var p := global_position
	if _last_pos != Vector3.INF and delta > 0.0:
		velocity = (p - _last_pos) / delta
	_last_pos = p

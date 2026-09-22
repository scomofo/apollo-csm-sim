## Double-precision 3-vector. Godot's Vector3 is float32, which gives ~0.5 m
## resolution at Earth radius; the propagator therefore keeps its state in
## these. Convert to Vector3 only at the presenter.
class_name Vec3d
extends RefCounted

var x: float
var y: float
var z: float


func _init(px: float = 0.0, py: float = 0.0, pz: float = 0.0) -> void:
	x = px
	y = py
	z = pz


static func from_v3(v: Vector3) -> Vec3d:
	return Vec3d.new(v.x, v.y, v.z)


func to_v3() -> Vector3:
	return Vector3(x, y, z)


func add(o: Vec3d) -> Vec3d:
	return Vec3d.new(x + o.x, y + o.y, z + o.z)


func sub(o: Vec3d) -> Vec3d:
	return Vec3d.new(x - o.x, y - o.y, z - o.z)


func mul(s: float) -> Vec3d:
	return Vec3d.new(x * s, y * s, z * s)


func dot(o: Vec3d) -> float:
	return x * o.x + y * o.y + z * o.z


func cross(o: Vec3d) -> Vec3d:
	return Vec3d.new(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x)


func length() -> float:
	return sqrt(x * x + y * y + z * z)


func normalized() -> Vec3d:
	var l := length()
	return Vec3d.new(x / l, y / l, z / l) if l > 0.0 else Vec3d.new()


func distance_to(o: Vec3d) -> float:
	return sub(o).length()


## Rotate by a Godot Basis (float32 rotation, double vector).
func rotated(b: Basis) -> Vec3d:
	return Vec3d.new(
		b.x.x * x + b.y.x * y + b.z.x * z,
		b.x.y * x + b.y.y * y + b.z.y * z,
		b.x.z * x + b.y.z * y + b.z.z * z)


func _to_string() -> String:
	return "(%f, %f, %f)" % [x, y, z]

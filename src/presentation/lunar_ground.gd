## The ground below Eagle, from the height maps (Terrain), drawn in place
## of the Moon's sphere while the view is from the LM near the Moon
## (src/presentation/space_view.gd). The sphere's flat facets can lie 2 km
## below the surface they stand for, which from low over it is far below
## the LM, and the maps' relief isn't on it. This is a grid of RINGS rings
## of SEGMENTS points around the point below the LM: the first a tenth of
## its height out (MIN_RING_M at the least), each farther out by the same
## factor, to past the horizon, where RELIEF_M of relief could still show
## above it. Its heights are Terrain.height()'s, the ones the LM's gear
## lands on.
##
## A grid is built on a worker thread for where the LM is, and the last
## one is drawn, in its place on the Moon, until the new one is ready. A
## new one is built when the LM has moved a quarter of its height on from
## above the grid's centre, or its height has changed by half. place()
## puts it in the view at the Moon's render scale. [simplified: the ground
## is flat between the grid's points, which past the first rings are
## farther apart than the maps' posts, so relief away from the LM is
## smoothed, and it shifts a little as each new grid replaces the last.]
class_name LunarGround
extends MeshInstance3D

const RINGS := 96
const SEGMENTS := 96
const MIN_RING_M := 2.0
## How far above the ground below the LM relief beyond the horizon may
## rise and still show [estimated for the maria].
const RELIEF_M := 3000.0
## A new grid when the LM is this share of its height on from above the
## grid's centre...
const RECENTRE := 0.25
## ...or its height has changed by this factor.
const REHEIGHT := 1.5

## Build on a worker thread; false builds on the caller's (tests).
var threaded: bool = true
## The grid drawn: its centre (a Moon-fixed unit vector), its axes (up,
## east and north at the centre, in Moon-fixed axes), and the height above
## the ground it was built for.
var centre: PackedFloat64Array = PackedFloat64Array()
var frame: Basis = Basis.IDENTITY
var built_h: float = 0.0
## The drawn grid's points, in its axes (as build() returns them).
var points: PackedVector3Array = PackedVector3Array()

var _material: ShaderMaterial
var _task: int = -1
var _next: Dictionary = {}


func _init() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://src/presentation/shaders/lunar_ground.gdshader")
	visible = false


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Whether a grid is ready to draw.
func has_grid() -> bool:
	return not centre.is_empty()


## Keep a grid for the eye at [param eye_mf] (Moon-fixed, m), [param h] m
## above the ground, and place it: [param mf_to_view] turns Moon-fixed
## axes into the view's, and [param s] is the Moon's render scale. Returns
## whether a grid is drawn.
func follow(eye_mf: PackedFloat64Array, h: float, mf_to_view: Basis, s: float) -> bool:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_apply(_next)
	h = maxf(h, 1.0)
	if _task < 0 and _stale(eye_mf, h):
		var up := _unit(eye_mf)
		if threaded:
			Terrain.height(0.0, 0.0)  # the maps load here, not on the worker
			_task = WorkerThreadPool.add_task(func() -> void: _next = LunarGround.build(up, h))
		else:
			_apply(build(up, h))
	visible = has_grid()
	if visible:
		place(eye_mf, mf_to_view, s)
	return visible


## Put the grid in the view for the eye at [param eye_mf] (Moon-fixed, m):
## the eye at the origin, Moon-fixed axes turned into the view's by
## [param mf_to_view], and every length scaled by [param s].
func place(eye_mf: PackedFloat64Array, mf_to_view: Basis, s: float) -> void:
	var r := Bodies.R_MOON
	# The eye from the reference sphere's point below the grid's centre,
	# in doubles until it is small, then in the grid's axes.
	var d := Vector3(eye_mf[0] - centre[0] * r, eye_mf[1] - centre[1] * r,
		eye_mf[2] - centre[2] * r)
	var e := frame.transposed() * d
	var b := mf_to_view * frame
	transform = Transform3D(b * s, -(b * e) * s)


func _stale(eye_mf: PackedFloat64Array, h: float) -> bool:
	if not has_grid() or h > built_h * REHEIGHT or h < built_h / REHEIGHT:
		return true
	# How far the eye has moved on from above the centre (the cross
	# product keeps small angles exact).
	var u := _unit(eye_mf)
	var cx := u[1] * centre[2] - u[2] * centre[1]
	var cy := u[2] * centre[0] - u[0] * centre[2]
	var cz := u[0] * centre[1] - u[1] * centre[0]
	return Bodies.R_MOON * sqrt(cx * cx + cy * cy + cz * cz) > maxf(RECENTRE * built_h, 1.0)


func _apply(b: Dictionary) -> void:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b["arrays"])
	m.surface_set_material(0, _material)
	mesh = m
	centre = b["centre"]
	frame = b["frame"]
	built_h = float(b["h"])
	points = b["arrays"][Mesh.ARRAY_VERTEX]


## Where the LM's centre of mass is in the Moon-fixed frame, in doubles:
## from lm.dyn.r_m at time.get_s, or, landed, where it sits
## (lm.dyn.landed_pos_m, exact where its ECI position isn't).
static func lm_moon_fixed() -> PackedFloat64Array:
	if bool(Bus.get_value("lm.dyn.landed", false)):
		var p: Array = Bus.get_value("lm.dyn.landed_pos_m", [])
		if p.size() == 3:
			return PackedFloat64Array(p)
	var r: Array = Bus.get_value("lm.dyn.r_m", [Bodies.R_MOON, 0.0, 0.0])
	return Bodies.to_moon_fixed(r, float(Bus.get_value("time.get_s", 0.0)))


## How high the Moon-fixed point [param p] is over the ground below it, m.
static func height_over_ground(p: PackedFloat64Array) -> float:
	var r := sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
	return r - Terrain.radius_under(Vector3(p[0], p[1], p[2]))


static func _unit(v: PackedFloat64Array) -> PackedFloat64Array:
	var n := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	return PackedFloat64Array([v[0] / n, v[1] / n, v[2] / n])


## The ring radii, m, for an eye [param h] m above ground of radius
## [param r_ground]: the first MIN_RING_M or a tenth of the height out,
## the last past the horizon by as far as RELIEF_M of relief shows.
static func ring_radii(h: float, r_ground: float) -> PackedFloat64Array:
	var horizon := acos(r_ground / (r_ground + h))
	var far := Bodies.R_MOON * (horizon + acos(r_ground / (r_ground + RELIEF_M)))
	var near := maxf(MIN_RING_M, 0.1 * h)
	var growth := pow(far / near, 1.0 / (RINGS - 1))
	var radii := PackedFloat64Array()
	radii.resize(RINGS)
	for k in RINGS:
		radii[k] = near * pow(growth, k)
	return radii


## A grid around the Moon-fixed unit vector [param up] for an eye
## [param h] m above the ground: {"arrays": the mesh's, "centre": up,
## "frame": its axes, "h": h}. Points are in the grid's axes (X up, Y
## east, Z north) from the reference sphere's point below the centre, and
## UV is each one's latitude and east longitude (rad). Point 0 is the
## centre, then ring by ring, each from east round through north.
static func build(up: PackedFloat64Array, h: float) -> Dictionary:
	var r := Bodies.R_MOON
	# East and north at the centre (east along the equator at a pole).
	var ex := -up[1]
	var ey := up[0]
	var en := sqrt(ex * ex + ey * ey)
	if en < 1e-9:
		ex = 0.0
		ey = 1.0
		en = 1.0
	ex /= en
	ey /= en
	var nx := -up[2] * ey
	var ny := up[2] * ex
	var nz := up[0] * ey - up[1] * ex
	var lat0 := asin(clampf(up[2], -1.0, 1.0))
	var lon0 := atan2(up[1], up[0])
	var h0 := Terrain.height(rad_to_deg(lat0), rad_to_deg(lon0))
	var radii := ring_radii(h, r + h0)
	var n := 1 + RINGS * SEGMENTS
	var pos := PackedVector3Array()
	pos.resize(n)
	var uv := PackedVector2Array()
	uv.resize(n)
	pos[0] = Vector3(h0, 0.0, 0.0)
	uv[0] = Vector2(lat0, lon0)
	var cth := PackedFloat64Array()
	var sth := PackedFloat64Array()
	for j in SEGMENTS:
		cth.append(cos(TAU * j / SEGMENTS))
		sth.append(sin(TAU * j / SEGMENTS))
	for k in RINGS:
		var a := radii[k] / r
		var ca := cos(a)
		var sa := sin(a)
		var hs := sin(a * 0.5)
		for j in SEGMENTS:
			var ct := cth[j]
			var st := sth[j]
			var dx := up[0] * ca + (ex * ct + nx * st) * sa
			var dy := up[1] * ca + (ey * ct + ny * st) * sa
			var dz := up[2] * ca + nz * st * sa
			var lat := asin(clampf(dz, -1.0, 1.0))
			var lon := atan2(dy, dx)
			var hh := Terrain.height(rad_to_deg(lat), rad_to_deg(lon))
			# r * (dir - up) + dir * hh, in the grid's axes.
			var i := 1 + k * SEGMENTS + j
			pos[i] = Vector3(-2.0 * r * hs * hs + ca * hh, (r + hh) * sa * ct, (r + hh) * sa * st)
			uv[i] = Vector2(lat, lon)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pos
	arrays[Mesh.ARRAY_NORMAL] = _normals(pos)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = _triangles()
	var frame_mf := Basis(Vector3(up[0], up[1], up[2]), Vector3(ex, ey, 0.0), Vector3(nx, ny, nz))
	return {"arrays": arrays, "centre": up, "frame": frame_mf, "h": h}


## Each point's normal, across its neighbours out and round its ring.
static func _normals(pos: PackedVector3Array) -> PackedVector3Array:
	var nrm := PackedVector3Array()
	nrm.resize(pos.size())
	for k in RINGS:
		for j in SEGMENTS:
			var i := 1 + k * SEGMENTS + j
			var inner := 0 if k == 0 else i - SEGMENTS
			var outer := i + SEGMENTS if k < RINGS - 1 else i
			var ahead := 1 + k * SEGMENTS + (j + 1) % SEGMENTS
			var behind := 1 + k * SEGMENTS + (j + SEGMENTS - 1) % SEGMENTS
			nrm[i] = (pos[outer] - pos[inner]).cross(pos[ahead] - pos[behind]).normalized()
	var q := int(SEGMENTS / 4.0)
	nrm[0] = (pos[1] - pos[1 + 2 * q]).cross(pos[1 + q] - pos[1 + 3 * q]).normalized()
	return nrm


## The triangles, clockwise seen from above (Godot's front faces): a fan
## round the centre, then two to each cell between the rings.
static func _triangles() -> PackedInt32Array:
	var idx := PackedInt32Array()
	for j in SEGMENTS:
		idx.append_array([0, 1 + (j + 1) % SEGMENTS, 1 + j])
	for k in RINGS - 1:
		for j in SEGMENTS:
			var a0 := 1 + k * SEGMENTS + j
			var a1 := 1 + k * SEGMENTS + (j + 1) % SEGMENTS
			idx.append_array([a0, a1, a1 + SEGMENTS, a0, a1 + SEGMENTS, a0 + SEGMENTS])
	return idx

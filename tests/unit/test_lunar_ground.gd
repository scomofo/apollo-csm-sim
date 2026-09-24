## The ground below Eagle (LunarGround): the height maps' heights on a
## grid of rings around the point below the LM, out past the horizon,
## placed at the Moon's render scale with the eye at the origin, and built
## again as the LM moves on or comes down.
extends GutTest

## Tranquility Base (data/terrain/terrain.json).
const LAT := 0.67416
const LON := 23.47314

var ground: LunarGround


func before_each() -> void:
	ground = LunarGround.new()
	ground.threaded = false
	add_child_autofree(ground)


## The Moon-fixed point [param h] m above the ground at [param lat],
## [param lon] (degrees).
func _eye(lat: float, lon: float, h: float) -> PackedFloat64Array:
	var r := Bodies.R_MOON + Terrain.height(lat, lon) + h
	var la := deg_to_rad(lat)
	var lo := deg_to_rad(lon)
	return PackedFloat64Array([r * cos(la) * cos(lo), r * cos(la) * sin(lo), r * sin(la)])


func _unit(v: PackedFloat64Array) -> PackedFloat64Array:
	var n := sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2])
	return PackedFloat64Array([v[0] / n, v[1] / n, v[2] / n])


## Grid point [param p] (the grid's axes) in the Moon-fixed frame, in
## doubles.
func _moon_fixed(c: PackedFloat64Array, frame: Basis, p: Vector3) -> PackedFloat64Array:
	var d := frame * p
	var r := Bodies.R_MOON
	return PackedFloat64Array([c[0] * r + d.x, c[1] * r + d.y, c[2] * r + d.z])


## Longitude [param m] metres east of the site.
func _east(m: float) -> float:
	return LON + rad_to_deg(m / (Bodies.R_MOON * cos(deg_to_rad(LAT))))


func test_the_grid_carries_the_maps_heights_out_past_the_horizon() -> void:
	var h := 100.0
	var b := LunarGround.build(_unit(_eye(LAT, LON, h)), h)
	var pos: PackedVector3Array = b["arrays"][Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = b["arrays"][Mesh.ARRAY_TEX_UV]
	var nrm: PackedVector3Array = b["arrays"][Mesh.ARRAY_NORMAL]
	var c: PackedFloat64Array = b["centre"]
	var frame: Basis = b["frame"]
	assert_eq(pos.size(), 1 + LunarGround.RINGS * LunarGround.SEGMENTS)
	assert_almost_eq(pos[0], Vector3(Terrain.height(LAT, LON), 0, 0), Vector3.ONE * 1e-3,
		"the centre, below the eye")
	var worst := 0.0
	for i in range(0, pos.size(), 37):
		var p := _moon_fixed(c, frame, pos[i])
		var rad := sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
		var lat := rad_to_deg(asin(p[2] / rad))
		var lon := rad_to_deg(atan2(p[1], p[0]))
		worst = maxf(worst, absf(rad - Bodies.R_MOON - Terrain.height(lat, lon)))
		assert_almost_eq(Vector2(deg_to_rad(lat), deg_to_rad(lon)), uv[i], Vector2.ONE * 1e-6,
			"UV is where it is")
		assert_almost_eq(nrm[i].length(), 1.0, 1e-4)
		var up := frame.transposed() * Vector3(p[0], p[1], p[2]).normalized()
		assert_gt(nrm[i].dot(up), 0.9, "facing up, off a mare's gentle slopes")
	assert_lt(worst, 0.1, "every point at the maps' height where it is (m)")
	var rg := Bodies.R_MOON + Terrain.height(LAT, LON)
	var radii := LunarGround.ring_radii(h, rg)
	assert_almost_eq(radii[0], 10.0, 1e-9, "the first ring a tenth of the height out")
	assert_gt(radii[radii.size() - 1], rg * acos(rg / (rg + h)) * 2.0,
		"the last well past the horizon")


func test_it_is_placed_at_the_moons_scale_with_the_eye_at_the_origin() -> void:
	var h := 50.0
	var eye := _eye(LAT, LON, h)
	var turn := Basis(Vector3(0, 0, 1), 0.7) * Basis(Vector3(1, 0, 0), -0.3)
	var s := 0.001
	assert_true(ground.follow(eye, h, turn, s), "a grid, built at once")
	assert_true(ground.visible)
	var up := _unit(eye)
	var u := Vector3(up[0], up[1], up[2])
	var below: Vector3 = ground.global_transform * ground.points[0]
	assert_almost_eq(below, turn * (-u * h) * s, Vector3.ONE * 1e-6,
		"the ground straight below the eye, h down, at the Moon's scale")
	for i in [200, 3000, 7000]:
		var p := _moon_fixed(ground.centre, ground.frame, ground.points[i])
		var rel := Vector3(p[0] - eye[0], p[1] - eye[1], p[2] - eye[2])
		var at: Vector3 = ground.global_transform * ground.points[i]
		assert_almost_eq(at, turn * rel * s, Vector3.ONE * 1e-4, "point %d where it is from the eye" % i)


func test_a_new_grid_as_the_lm_moves_on_or_comes_down() -> void:
	var s := 0.001
	ground.follow(_eye(LAT, LON, 1000.0), 1000.0, Basis.IDENTITY, s)
	var first := ground.centre
	ground.follow(_eye(LAT, _east(200.0), 1000.0), 1000.0, Basis.IDENTITY, s)
	assert_eq(ground.centre, first, "200 m on, under a quarter of its height: the same grid")
	ground.follow(_eye(LAT, _east(300.0), 1000.0), 1000.0, Basis.IDENTITY, s)
	assert_ne(ground.centre, first, "300 m on, a new one")
	var second := ground.centre
	ground.follow(_eye(LAT, _east(300.0), 800.0), 800.0, Basis.IDENTITY, s)
	assert_eq(ground.centre, second, "800 m down: the same")
	ground.follow(_eye(LAT, _east(300.0), 600.0), 600.0, Basis.IDENTITY, s)
	assert_eq(ground.built_h, 600.0, "600 m: a new one, finer")


func test_on_a_worker_the_last_grid_stays_until_the_next_is_ready() -> void:
	ground.threaded = true
	var s := 0.001
	var eye := _eye(LAT, LON, 500.0)
	assert_false(ground.follow(eye, 500.0, Basis.IDENTITY, s),
		"nothing to draw until the first is built")
	assert_false(ground.visible)
	assert_true(await _built(eye, 500.0), "built on a worker thread")
	var first := ground.centre
	var on := _eye(LAT, _east(1000.0), 500.0)
	assert_true(ground.follow(on, 500.0, Basis.IDENTITY, s),
		"the last grid drawn while the next is built")
	assert_eq(ground.centre, first)
	var t0 := Time.get_ticks_msec()
	while ground.centre == first and Time.get_ticks_msec() - t0 < 20000:
		await wait_process_frames(1)
		ground.follow(on, 500.0, Basis.IDENTITY, s)
	assert_ne(ground.centre, first, "then the next")


func _built(eye: PackedFloat64Array, h: float) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 20000:
		if ground.follow(eye, h, Basis.IDENTITY, 0.001):
			return true
		await wait_process_frames(1)
	return false

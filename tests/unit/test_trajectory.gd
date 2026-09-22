extends GutTest


func _circular(primary: String, alt: float, t: float = 0.0) -> Trajectory:
	var r := Bodies.radius_of(primary) + alt
	var v := sqrt(Bodies.mu_of(primary) / r)
	var pl := Bodies.moon_plane()
	var tr := Trajectory.new()
	tr.set_state(primary, t, Vector3(pl[0], pl[1], pl[2]) * r, Vector3(pl[3], pl[4], pl[5]) * v)
	return tr


func before_each() -> void:
	Bodies.configure(28.5, 0.0, 3.3, -20.0)


func test_leo_orbit_closes_after_one_period() -> void:
	var tr := _circular("earth", 185000.0)
	var p0 := tr.pos()
	var period: float = tr.conic()["period"]
	tr.coast_to(period, 60.0)
	# Only the lunar tide (~1e-6 m/s²) perturbs a two-body closure.
	assert_lt(tr.pos().distance_to(p0), 200.0)
	assert_almost_eq(tr.altitude(), 185000.0, 100.0)


func test_step_size_independence() -> void:
	var a := _circular("earth", 185000.0)
	var b := a.clone()
	a.coast_to(3000.0, 0.5, 1.0)
	b.coast_to(3000.0, 60.0, 0.005)
	assert_lt(a.pos().distance_to(b.pos()), 5.0)


func test_low_lunar_orbit_is_stable() -> void:
	var tr := _circular("moon", 111000.0, 270000.0)
	var period: float = tr.conic()["period"]
	tr.coast_to(270000.0 + 3.0 * period, 30.0)
	assert_eq(tr.primary, "moon")
	assert_almost_eq(float(tr.conic()["rp"]) - Bodies.R_MOON, 111000.0, 3000.0)


func test_soi_switch_preserves_earth_relative_state() -> void:
	# Place the vehicle just outside the SOI, moving in, and step across.
	var m := Bodies.moon_state(0.0)
	var mp := Vector3(m[0], m[1], m[2])
	var mv := Vector3(m[3], m[4], m[5])
	var dir := -mp.normalized()
	var tr := Trajectory.new()
	tr.set_state("earth", 0.0, mp + dir * Bodies.MOON_SOI * 1.0005, mv - dir * 1000.0)
	var ref := tr.clone()
	for _i in 60:
		tr.step(20.0)
	assert_eq(tr.primary, "moon", "entered SOI")
	assert_eq(tr.soi_switches, 1)
	# Same physics either side of the boundary: a finer step sequence that
	# re-bases at a different instant must agree.
	for _i in 2400:
		ref.step(0.5)
	assert_eq(ref.primary, "moon")
	var e1 := tr.earth_state()
	var e2 := ref.earth_state()
	assert_lt(Vector3(e1[0] - e2[0], e1[1] - e2[1], e1[2] - e2[2]).length(), 1.0)
	assert_lt(Vector3(e1[3] - e2[3], e1[4] - e2[4], e1[5] - e2[5]).length(), 1e-3)


func test_conic_of_circular_orbit() -> void:
	var tr := _circular("earth", 185000.0)
	var c := tr.conic()
	assert_almost_eq(float(c["e"]), 0.0, 1e-6)
	assert_almost_eq(float(c["rp"]), Bodies.R_EARTH + 185000.0, 1.0)
	assert_almost_eq(float(c["period"]) / 60.0, 88.2, 0.3)


func test_lvlh_axes() -> void:
	var b := Trajectory.lvlh_basis(Vector3(7e6, 0, 0), Vector3(0, 7500, 0))
	assert_almost_eq(b.x.distance_to(Vector3(0, 1, 0)), 0.0, 1e-6, "X forward")
	assert_almost_eq(b.y.distance_to(Vector3(0, 0, -1)), 0.0, 1e-6, "Y = -orbit normal")
	assert_almost_eq(b.z.distance_to(Vector3(-1, 0, 0)), 0.0, 1e-6, "Z down")


func test_atmosphere_table() -> void:
	assert_almost_eq(Atmosphere.density(0.0), 1.225, 1e-6)
	assert_almost_eq(Atmosphere.density(50000.0), 0.001027, 1e-6)
	assert_gt(Atmosphere.density(45000.0), Atmosphere.density(55000.0))
	assert_eq(Atmosphere.density(2.0e6), 0.0)

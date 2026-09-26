## The CMC's navigation filter (src/systems/nav_filter.gd): its sightings'
## models against finite differences, the update, the transition matrix,
## the covariance carried between marks and a checkpoint.
extends GutTest


## A state some 300,000 km out on the way home.
func _cislunar() -> Trajectory:
	var tr := Trajectory.new()
	tr.set_state("earth", 250000.0, Vector3(2.5e8, 1.4e8, 6.0e7), Vector3(-900.0, -500.0, -150.0))
	return tr


## A star [param deg] from body [param body]'s centre as [param tr] sees it.
func _star_off(tr: Trajectory, body: String, deg: float) -> Vector3:
	var st := tr.earth_state() if body == "earth" else tr.moon_state_rel()
	var u := -Vector3(st[0], st[1], st[2]).normalized()
	var axis := u.cross(Vector3(0, 0, 1)).normalized()
	return u.rotated(axis, deg_to_rad(deg))


func test_the_star_horizon_angle_and_its_gradient() -> void:
	for body in ["earth", "moon"]:
		var tr := _cislunar()
		var star := _star_off(tr, body, 30.0)
		var m := NavFilter.star_horizon(tr, star, body)
		assert_false(m.is_empty(), body)
		var rho := float(m["radius"])
		assert_almost_eq(rad_to_deg(float(m["q"])), 30.0 - rad_to_deg(rho), 1e-4, "%s: the angle to the centre less the angular radius" % body)
		var h: Vector3 = m["horizon"]
		assert_almost_eq(h.angle_to(star), float(m["q"]), 1e-6, "%s: the horizon point is the angle away" % body)
		var b: PackedFloat64Array = m["b"]
		for i in 3:
			var tr2 := tr.clone()
			tr2.s[i] += 1000.0
			var fd := (float(NavFilter.star_horizon(tr2, star, body)["q"]) - float(m["q"])) / 1000.0
			assert_almost_eq(b[i], fd, absf(fd) * 0.01 + 1e-13, "%s: the gradient along axis %d" % [body, i])
		assert_eq([b[3], b[4], b[5]], [0.0, 0.0, 0.0], "a sighting doesn't see the velocity")
	# A star behind the Earth has no horizon to mark.
	var tr3 := _cislunar()
	assert_true(NavFilter.star_horizon(tr3, _star_off(tr3, "earth", 0.5), "earth").is_empty(), "behind the Earth")


func test_the_landmark_line_of_sight() -> void:
	var site := Vector3(1.0, 0.3, 0.1).normalized() * Bodies.R_MOON
	var tr := Trajectory.new()
	var t := 360000.0
	var over := Bodies.moon_fixed(t) * site
	tr.set_state("moon", t, over.normalized() * (Bodies.R_MOON + 110000.0) + over.normalized().cross(Vector3(0, 0, 1)).normalized() * 50000.0,
		Vector3(0, 0, 1600.0))
	var m := NavFilter.landmark_los(tr, site)
	var to_site := (over - tr.pos())
	assert_almost_eq(float(m["range"]), to_site.length(), 1.0, "the range")
	assert_almost_eq((m["los"] as Vector3).angle_to(to_site), 0.0, 1e-5, "along the line to the site")
	for e in ["e1", "e2"]:
		assert_almost_eq((m[e] as Vector3).dot(m["los"]), 0.0, 1e-6, "%s across it" % e)
	assert_almost_eq((m["e1"] as Vector3).dot(m["e2"]), 0.0, 1e-6)


func test_a_scalar_update_weighs_the_residual_by_the_variances() -> void:
	# The position known to 100 m and a measurement of X to 100 m: the
	# update goes halfway, and halves X's variance.
	var pm := NavFilter.diagonal(100.0 * 100.0, 1.0)
	pm[0 * 6 + 3] = 50.0
	pm[3 * 6 + 0] = 50.0
	var b := PackedFloat64Array([1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var u := NavFilter.scalar_update(pm, b, 40.0, 100.0 * 100.0)
	var dx: PackedFloat64Array = u["dx"]
	var p2: PackedFloat64Array = u["p"]
	assert_almost_eq(dx[0], 20.0, 1e-9, "halfway")
	assert_almost_eq(dx[3], 40.0 * 50.0 / 20000.0, 1e-12, "and the velocity by its correlation")
	assert_almost_eq(dx[1], 0.0, 1e-12, "not the other axes")
	assert_almost_eq(p2[0], 5000.0, 1e-6, "X's variance halved")
	assert_almost_eq(p2[7], 10000.0, 1e-6, "Y's as it was")
	assert_almost_eq(p2[1 * 6 + 0], p2[0 * 6 + 1], 1e-9, "symmetric")


func test_the_transition_matrix() -> void:
	# A minute's coast far out: the position moves with the velocity.
	var tr := _cislunar()
	var phi := NavFilter.transition(tr, tr.t + 60.0)
	for i in 3:
		assert_almost_eq(phi[i * 6 + i], 1.0, 1e-3, "position on position")
		assert_almost_eq(phi[i * 6 + i + 3], 60.0, 0.1, "position on velocity")
		assert_almost_eq(phi[(i + 3) * 6 + i + 3], 1.0, 1e-3, "velocity on velocity")


func test_the_filter_carries_its_covariance_and_takes_a_mark() -> void:
	var f := NavFilter.new()
	var tr := _cislunar()
	f.reinit(tr)
	var r0 := NavFilter.rms(f.p)
	assert_almost_eq(r0.x, NavFilter.POS_RMS_M, 1e-6)
	assert_almost_eq(r0.y, NavFilter.VEL_RMS_MPS, 1e-9)
	var later := tr.clone()
	later.coast_to(tr.t + 3600.0)
	var pm := f.carried(later)
	assert_gt(NavFilter.rms(pm).x, r0.x, "an hour's velocity error spreads the position")
	var dx := PackedFloat64Array([1000.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var x0 := later.s[0]
	f.accept(later, dx, pm)
	assert_almost_eq(later.s[0], x0 + 1000.0, 1e-6, "the state vector moved")
	assert_eq(f.anchor.t, later.t, "anchored where it was taken")
	f.stale = true
	f.carried(later)
	assert_almost_eq(NavFilter.rms(f.p).x, NavFilter.POS_RMS_M, 1e-6, "a burn since: from the RMS again")


func test_the_filter_comes_back_from_a_snapshot() -> void:
	var f := NavFilter.new()
	f.pos_rms = 5000.0
	f.reinit(_cislunar())
	var g := NavFilter.new()
	g.restore(JSON.parse_string(JSON.stringify(f.snapshot())))
	assert_eq(g.pos_rms, 5000.0)
	assert_eq(g.p, f.p)
	assert_false(g.stale)
	assert_eq(g.anchor.s, f.anchor.s)
	assert_eq(g.anchor.t, f.anchor.t)

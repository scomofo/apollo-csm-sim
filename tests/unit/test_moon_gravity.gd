## The Moon's gravity fields (slice 5b): GRAIL's recursion and R-2's
## against potentials summed directly, the reference orbit against the
## tool's own integration (tools/gravity/moon_gravity.py), the propagator's
## samples against the field where the trajectory is, and the onboard
## computers' models.
extends GutTest

const CHECK := "res://tests/fixtures/moon_gravity_check.json"


func before_each() -> void:
	Mission.load_default()


func after_all() -> void:
	Mission.load_default()


## GRAIL's potential beyond the central term at Moon-fixed (x, y, z), to
## degree [param nn]: GM/r sum (R/r)^n P_nm(sin lat) (C cos m lon + S sin
## m lon), from the unnormalised Legendre functions by columns.
static func _potential(x: float, y: float, z: float, nn: int) -> float:
	var r := sqrt(x * x + y * y + z * z)
	var u := z / r
	var cl := sqrt(maxf(0.0, 1.0 - u * u))
	var lon := atan2(y, x)
	var p := {}
	var pmm := 1.0
	for m in range(0, nn + 1):
		if m > 0:
			pmm *= float(2 * m - 1) * cl
		p[Vector2i(m, m)] = pmm
		if m + 1 <= nn:
			p[Vector2i(m + 1, m)] = float(2 * m + 1) * u * pmm
		for n in range(m + 2, nn + 1):
			p[Vector2i(n, m)] = (float(2 * n - 1) * u * p[Vector2i(n - 1, m)]
				- float(n + m - 1) * p[Vector2i(n - 2, m)]) / float(n - m)
	var total := 0.0
	for n in range(2, nn + 1):
		var sub := 0.0
		for m in range(0, n + 1):
			var i := n * (n + 1) / 2 + m - 3
			sub += float(p[Vector2i(n, m)]) * (MoonGravity.c[i] * cos(m * lon) + MoonGravity.s[i] * sin(m * lon))
		total += pow(MoonGravity.radius / r, n) * sub
	return MoonGravity.gm / r * total


## R-2's potential beyond the central term: the Moon's J2, J3, C22 and
## C31, written out.
static func _r2_potential(x: float, y: float, z: float, mu: float) -> float:
	var r := sqrt(x * x + y * y + z * z)
	var u := z / r
	var q := MoonGravity.R2_RADIUS / r
	var p2 := (3.0 * u * u - 1.0) / 2.0
	var p3 := (5.0 * u * u * u - 3.0 * u) / 2.0
	var c22 := 3.0 * (x * x - y * y) / (r * r)
	var c31 := 1.5 * (5.0 * u * u - 1.0) * x / r
	return mu / r * (-MoonGravity.R2_J2 * q * q * p2 - MoonGravity.R2_J3 * q * q * q * p3
		+ MoonGravity.R2_C22 * q * q * c22 + MoonGravity.R2_C31 * q * q * q * c31)


## The gradient of [param f](x, y, z) at [param pt] by central
## differences of [param h] m, in doubles.
static func _gradient(f: Callable, pt: Array, h: float) -> PackedFloat64Array:
	var g := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in 3:
		var up := pt.duplicate()
		var dn := pt.duplicate()
		up[i] += h
		dn[i] -= h
		g[i] = (float(f.call(up[0], up[1], up[2])) - float(f.call(dn[0], dn[1], dn[2]))) / (2.0 * h)
	return g


## |a - b| / |b| for three-float arrays.
static func _rel(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	var d := sqrt(pow(a[0] - b[0], 2) + pow(a[1] - b[1], 2) + pow(a[2] - b[2], 2))
	return d / sqrt(b[0] * b[0] + b[1] * b[1] + b[2] * b[2])


func test_the_mission_flies_grails_field_to_degree_30() -> void:
	assert_eq(MoonGravity.degree, 30, "degree 30")
	assert_eq(MoonGravity.model, "GL1800F_ME")
	assert_almost_eq(MoonGravity.gm, Bodies.MU_MOON, 1e3, "the central pull's GM is GRAIL's")
	assert_almost_eq(MoonGravity.radius, 1738000.0, 1e-6)
	Bodies.configure(28.5, 0.0, 3.3, -20.0)
	assert_eq(MoonGravity.degree, 0, "none on the circular model")


func test_the_recursion_is_its_potentials_gradient() -> void:
	# At 60 nmi, at DOI's 15 km and far out, to degrees 2, 10 and 30.
	for pt in [[1.849e6, 0.0, 2.0e4], [-1.2e6, 1.3e6, -3.1e5], [3.0e5, -1.7e6, 6.0e5], [5.0e6, 2.0e6, -1.0e6]]:
		for nn in [2, 10, 30]:
			var a := MoonGravity.accel_fixed(pt[0], pt[1], pt[2], nn)
			var fd := _gradient(func(x, y, z): return _potential(x, y, z, nn), pt, 20.0)
			assert_almost_eq(_rel(a, fd), 0.0, 1e-6, "degree %d at %s" % [nn, pt])
	# The mascons: beyond degree 2, a few hundred micrometres per second
	# squared at 60 nmi.
	var r := Bodies.R_MOON + 60.0 * 1852.0
	var worst := 0.0
	for i in 36:
		var lon := TAU * i / 36.0
		var a30 := MoonGravity.accel_fixed(r * cos(lon), r * sin(lon), 0.0, 30)
		var a2 := MoonGravity.accel_fixed(r * cos(lon), r * sin(lon), 0.0, 2)
		worst = maxf(worst, Vector3(a30[0] - a2[0], a30[1] - a2[1], a30[2] - a2[2]).length())
	gut.p("round the equator 60 nmi up, degrees 3 to 30 pull up to %.0f um/s2" % (worst * 1e6))
	assert_between(worst, 2e-4, 3e-3, "the mascons' pull")


func test_r2_is_its_potentials_gradient() -> void:
	var mu := Bodies.MU_MOON
	for pt in [[1.849e6, 0.0, 2.0e4], [-1.2e6, 1.3e6, -3.1e5], [3.0e5, -1.7e6, 6.0e5]]:
		var a := MoonGravity.r2_accel_fixed(pt[0], pt[1], pt[2], mu)
		var fd := _gradient(func(x, y, z): return _r2_potential(x, y, z, mu), pt, 20.0)
		assert_almost_eq(_rel(a, fd), 0.0, 1e-6, "at %s" % [pt])
	var far := MoonGravity.r2_accel_fixed(MoonGravity.R2_RANGE * 1.01, 0.0, 0.0, mu)
	assert_eq(far, PackedFloat64Array([0.0, 0.0, 0.0]), "none past RDM, 16,093 km")


func test_the_degree_fades_with_distance() -> void:
	assert_eq(MoonGravity.degree_at(Bodies.R_MOON + 111000.0), 30, "all of it at 60 nmi")
	assert_eq(MoonGravity.degree_at(2.0 * MoonGravity.radius), 11, "11 two lunar radii out")
	assert_eq(MoonGravity.degree_at(10.0 * MoonGravity.radius), 3, "3 ten out")


## The reference orbit, flown as the tool flies it: a Moon alone turning
## at its sidereal rate, RK4 at the fixture's step, the field at every
## stage.
func test_the_reference_orbit_flies_as_the_tools_integration() -> void:
	var f := FileAccess.open(CHECK, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	assert_eq(int(d["degree"]), MoonGravity.degree, "the fixture's degree")
	var gm := float(d["gm_m3s2"])
	var omega := float(d["omega_rad_s"])
	var h := float(d["step_s"])
	var s := PackedFloat64Array(d["start"])
	var t := 0.0
	var acc := func(tt: float, p: PackedFloat64Array) -> PackedFloat64Array:
		var th := omega * tt
		var c := cos(th)
		var sn := sin(th)
		var a := MoonGravity.accel_fixed(c * p[0] + sn * p[1], -sn * p[0] + c * p[1], p[2])
		var r3 := pow(p[0] * p[0] + p[1] * p[1] + p[2] * p[2], 1.5)
		return PackedFloat64Array([c * a[0] - sn * a[1] - gm * p[0] / r3, sn * a[0] + c * a[1] - gm * p[1] / r3,
			a[2] - gm * p[2] / r3])
	var along := func(p: PackedFloat64Array, v: PackedFloat64Array, k: float) -> PackedFloat64Array:
		return PackedFloat64Array([p[0] + v[0] * k, p[1] + v[1] * k, p[2] + v[2] * k])
	var worst := 0.0
	var radii := []
	for hour: Dictionary in d["hours"]:
		while t < float(hour["t_s"]) - 1e-6:
			var p := s.slice(0, 3)
			var v := s.slice(3, 6)
			var k1: PackedFloat64Array = acc.call(t, p)
			var p2: PackedFloat64Array = along.call(p, v, h / 2.0)
			var v2: PackedFloat64Array = along.call(v, k1, h / 2.0)
			var k2: PackedFloat64Array = acc.call(t + h / 2.0, p2)
			var p3: PackedFloat64Array = along.call(p, v2, h / 2.0)
			var v3: PackedFloat64Array = along.call(v, k2, h / 2.0)
			var k3: PackedFloat64Array = acc.call(t + h / 2.0, p3)
			var p4: PackedFloat64Array = along.call(p, v3, h)
			var v4: PackedFloat64Array = along.call(v, k3, h)
			var k4: PackedFloat64Array = acc.call(t + h, p4)
			for i in 3:
				s[i] = p[i] + h / 6.0 * (v[i] + 2.0 * v2[i] + 2.0 * v3[i] + v4[i])
				s[3 + i] = v[i] + h / 6.0 * (k1[i] + 2.0 * k2[i] + 2.0 * k3[i] + k4[i])
			t += h
		var want: Array = hour["state"]
		worst = maxf(worst, sqrt(pow(s[0] - want[0], 2) + pow(s[1] - want[1], 2) + pow(s[2] - want[2], 2)))
		radii.append(sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2]))
	var r0 := float(d["radius_m"])
	gut.p("12 h from a circular 60 nmi orbit: radius %.1f to %.1f km off, the tool's within %.4f m" % [
		(float(radii.min()) - r0) / 1000.0, (float(radii.max()) - r0) / 1000.0, worst])
	assert_lt(worst, 0.5, "the same orbit as the tool's integration")
	assert_gt(float(radii.max()) - float(radii.min()), 2000.0, "the field pulls it kilometres out of round")


## The propagator samples the field on a 30 s grid of time, where the
## trajectory will be at each interval's middle.
func test_the_propagator_samples_the_field_where_the_trajectory_is() -> void:
	var tr := Trajectory.new()
	var r := Bodies.R_MOON + 111000.0
	var v := sqrt(Bodies.MU_MOON / r)
	tr.set_state("moon", 300000.0, Vector3(r, 0.0, 0.0), Vector3(0.0, -v * 0.999, v * 0.04))
	tr.coast_to(300000.0 + 200.0, 1.0)
	var k := tr.field_k
	var samples := tr.field_a.duplicate()
	for j in 4:
		var mid := (float(k + j) + 0.5) * Trajectory.FIELD_HOLD
		var at := tr.clone()
		if mid < at.t:
			continue
		at.coast_to(mid, 0.5)
		var ax := Bodies.moon_fixed_axes(mid)
		var p := Bodies.to_moon_fixed([at.s[0], at.s[1], at.s[2]], mid)
		var g := MoonGravity.accel_fixed(p[0], p[1], p[2])
		var gi := Vector3(g[0] * ax[0] + g[1] * ax[3] + g[2] * ax[6], g[0] * ax[1] + g[1] * ax[4] + g[2] * ax[7],
			g[0] * ax[2] + g[1] * ax[5] + g[2] * ax[8])
		var got := Vector3(samples[3 * j], samples[3 * j + 1], samples[3 * j + 2])
		assert_almost_eq((got - gi).length() / gi.length(), 0.0, 1e-4, "interval %d's sample" % (k + j))
	# The pull between samples is the cubic through them: at a sample's
	# time, the sample.
	var t1 := (float(k + 1) + 0.5) * Trajectory.FIELD_HOLD
	var mid1: PackedFloat64Array = tr._field_at(t1, PackedFloat64Array())
	assert_almost_eq(Vector3(mid1[0], mid1[1], mid1[2]).distance_to(
		Vector3(tr.field_a[3], tr.field_a[4], tr.field_a[5])), 0.0, 1e-12)


## Inside the Moon, where a trajectory diving through the surface goes,
## the series would diverge: each field is evaluated straight above,
## under the lowest ground, instead.
func test_inside_the_moon_the_fields_stay_bounded() -> void:
	var lo := MoonGravity.FLOOR * MoonGravity.radius
	var u := Vector3(0.3, -0.5, 0.8).normalized()
	var at_floor := MoonGravity.accel_fixed(u.x * lo, u.y * lo, u.z * lo)
	for r in [0.9 * lo, 0.5 * lo, 1000.0]:
		var g := MoonGravity.accel_fixed(u.x * r, u.y * r, u.z * r)
		assert_almost_eq(Vector3(g[0], g[1], g[2]).distance_to(Vector3(at_floor[0], at_floor[1], at_floor[2])), 0.0,
			1e-12, "at %.0f km, the pull at the floor" % (r / 1000.0))
	var above := MoonGravity.accel_fixed(u.x * (lo + 1.0), u.y * (lo + 1.0), u.z * (lo + 1.0))
	assert_lt(Vector3(above[0], above[1], above[2]).distance_to(Vector3(at_floor[0], at_floor[1], at_floor[2])),
		1e-6, "continuous across the floor")
	assert_lt(Vector3(at_floor[0], at_floor[1], at_floor[2]).length(), 0.01, "bounded, some mm/s²")
	var r2 := MoonGravity.r2_accel_fixed(u.x * 1000.0, u.y * 1000.0, u.z * 1000.0, Bodies.MU_MOON)
	var r2_floor := MoonGravity.FLOOR * MoonGravity.R2_RADIUS
	var r2_at := MoonGravity.r2_accel_fixed(u.x * r2_floor, u.y * r2_floor, u.z * r2_floor, Bodies.MU_MOON)
	assert_almost_eq(Vector3(r2[0], r2[1], r2[2]).distance_to(Vector3(r2_at[0], r2_at[1], r2_at[2])), 0.0, 1e-12,
		"and R-2's alike")


## Under thrust the samples are taken where the thrust carries the
## trajectory: a minute ahead in powered descent, 3 m/s² against the
## motion 15 km up, it would be 5 km from where it would coast.
func test_a_thrusting_trajectorys_samples_follow_the_thrust() -> void:
	var r := Bodies.R_MOON + 15000.0
	var t0 := 369000.0 + 0.5 * Trajectory.FIELD_HOLD
	var ext := PackedFloat64Array([0.0, 3.0, 0.0])
	var tr := Trajectory.new()
	tr.set_state("moon", t0, Vector3(r, 0.0, 0.0), Vector3(0.0, -1690.0, 0.0))
	var k := int(floorf(t0 / Trajectory.FIELD_HOLD - 0.5))
	# The sample for two intervals on, 60 s ahead, with the thrust and
	# without it.
	var ahead := func(e: PackedFloat64Array) -> Vector3:
		var c := tr.clone()
		c._field_samples(k, e)
		return Vector3(c.field_a[6], c.field_a[7], c.field_a[8])
	var with_thrust: Vector3 = ahead.call(ext)
	var coasting: Vector3 = ahead.call(PackedFloat64Array())
	# The field where the trajectory does get to, flown with the thrust.
	var at := tr.clone()
	for i in 600:
		at.step(0.1, ext)
	var ax := Bodies.moon_fixed_axes(at.t)
	var p := Bodies.to_moon_fixed([at.s[0], at.s[1], at.s[2]], at.t)
	var g := MoonGravity.accel_fixed(p[0], p[1], p[2])
	var want := Vector3(g[0] * ax[0] + g[1] * ax[3] + g[2] * ax[6], g[0] * ax[1] + g[1] * ax[4] + g[2] * ax[7],
		g[0] * ax[2] + g[1] * ax[5] + g[2] * ax[8])
	gut.p("60 s ahead in powered descent: the sample %.1f um/s2 off with the thrust, %.1f without" % [
		(with_thrust - want).length() * 1e6, (coasting - want).length() * 1e6])
	assert_almost_eq(at.t, t0 + 2.0 * Trajectory.FIELD_HOLD, 1e-6, "the sample's time")
	assert_lt((with_thrust - want).length(), 0.01 * want.length(), "taken where the thrust carries it")
	assert_gt((coasting - want).length(), 5.0 * (with_thrust - want).length(), "not where it would coast")


## A burn begun or ended within one of the grid's intervals: the samples
## ahead of the trajectory, taken for the coast before it (or the burn),
## are taken again for the burn (or the coast), as a trajectory with none
## in hand would take them. Those behind it, where it went, stay.
func test_a_burns_start_and_end_take_the_samples_ahead_again() -> void:
	var r := Bodies.R_MOON + 15000.0
	var none := PackedFloat64Array()
	var thrust := PackedFloat64Array([0.0, 3.0, 0.0])
	var tr := Trajectory.new()
	tr.set_state("moon", 369000.0 + 0.5 * Trajectory.FIELD_HOLD, Vector3(r, 0.0, 0.0), Vector3(0.0, -1690.0, 0.0))
	# Ignition 10 s into an interval; cutoff a minute on, 10 s into another.
	for leg: Array in [["ignition", 10.0, none, thrust], ["cutoff", 60.0, thrust, none]]:
		var before: PackedFloat64Array = leg[2]
		var after: PackedFloat64Array = leg[3]
		var t_change := tr.t + float(leg[1])
		while tr.t < t_change - 1e-6:
			tr.step(0.1, before)
		var k := tr.field_k
		var held := tr.field_a.duplicate()
		var fresh := tr.clone()
		fresh.field_a = PackedFloat64Array()
		fresh._field_samples(k, after)
		var t_c := tr.t
		tr.step(0.1, after)
		assert_eq(tr.field_k, k, "the same intervals in hand at the %s" % leg[0])
		for j in 4:
			var got := Vector3(tr.field_a[3 * j], tr.field_a[3 * j + 1], tr.field_a[3 * j + 2])
			var ahead := (float(k + j) + 0.5) * Trajectory.FIELD_HOLD > t_c
			var src := fresh.field_a if ahead else held
			assert_almost_eq(got.distance_to(Vector3(src[3 * j], src[3 * j + 1], src[3 * j + 2])), 0.0, 1e-15,
				"at the %s, interval %d's sample %s" % [leg[0], k + j, "taken again" if ahead else "kept"])
		# The sample two intervals on, where the trajectory does get to.
		var mid := (float(k + 3) + 0.5) * Trajectory.FIELD_HOLD
		var at := tr.clone()
		while at.t < mid - 1e-6:
			at.step(minf(0.1, mid - at.t), after)
		var want := _field_where(at)
		var taken := Vector3(tr.field_a[9], tr.field_a[10], tr.field_a[11])
		var stale := Vector3(held[9], held[10], held[11])
		gut.p("%.0f s after the %s, the sample %.2f um/s2 off, %.1f as held before it" % [mid - t_c, leg[0],
			(taken - want).length() * 1e6, (stale - want).length() * 1e6])
		assert_lt((taken - want).length(), 0.01 * want.length(), "at the %s, taken where the trajectory goes" % leg[0])
		assert_gt((stale - want).length(), 5.0 * (taken - want).length(), "not where it went before the %s" % leg[0])


## The Moon's field (GRAIL's, inertial m/s²) where [param at] is.
func _field_where(at: Trajectory) -> Vector3:
	var ax := Bodies.moon_fixed_axes(at.t)
	var p := Bodies.to_moon_fixed([at.s[0], at.s[1], at.s[2]], at.t)
	var g := MoonGravity.accel_fixed(p[0], p[1], p[2])
	return Vector3(g[0] * ax[0] + g[1] * ax[3] + g[2] * ax[6], g[0] * ax[1] + g[1] * ax[4] + g[2] * ax[7],
		g[0] * ax[2] + g[1] * ax[5] + g[2] * ax[8])


func test_each_computer_flies_its_own_model() -> void:
	var r := Bodies.R_MOON + 111000.0
	var truth := Trajectory.new()
	truth.set_state("moon", 300000.0, Vector3(r, 0.0, 0.0), Vector3(0.0, -1600.0, 0.0))
	var cmc := truth.clone().as_onboard(Trajectory.Model.CMC)
	var lgc := truth.clone().as_onboard(Trajectory.Model.LGC)
	assert_eq(cmc.model, Trajectory.Model.CMC)
	assert_eq(cmc.clone().model, Trajectory.Model.CMC, "clones keep it")
	# Below 800 km the CMC has no Earth and no Sun; the LGC never has them.
	var none := PackedFloat64Array()
	var sun := Bodies.sun_position(300000.0)
	var mp := Bodies.moon_position(300000.0)
	sun[0] -= mp[0]; sun[1] -= mp[1]; sun[2] -= mp[2]
	var point := -Bodies.MU_MOON / (r * r)
	var a_t := truth._accel(300000.0, r, 0.0, 0.0, none, sun)
	var a_c := cmc._accel(300000.0, r, 0.0, 0.0, none, sun)
	assert_almost_eq(a_c[0], point, 1e-12, "the CMC's Moon alone, 60 nmi up")
	assert_gt(absf(a_t[0] - point) + absf(a_t[1]) + absf(a_t[2]), 1e-6, "truth's has the Earth and the Sun")
	var high := Bodies.R_MOON + 900000.0
	var a_ch := cmc._accel(300000.0, high, 0.0, 0.0, none, sun)
	var a_th := truth._accel(300000.0, high, 0.0, 0.0, none, sun)
	assert_almost_eq(Vector3(a_ch[0], a_ch[1], a_ch[2]).distance_to(Vector3(a_th[0], a_th[1], a_th[2])), 0.0, 1e-12,
		"900 km up the CMC has them")
	var a_lh := lgc._accel(300000.0, high, 0.0, 0.0, none, sun)
	assert_almost_eq(a_lh[0], -Bodies.MU_MOON / (high * high), 1e-12, "the LGC never")
	# Their Moon's field is R-2's, truth's GRAIL's.
	truth.coast_to(300000.0 + 1.0, 1.0)
	cmc.coast_to(300000.0 + 1.0, 1.0)
	assert_eq(truth.field_a.size(), 12)
	assert_eq(cmc.field_a.size(), 12)
	var gt := Vector3(truth.field_a[3], truth.field_a[4], truth.field_a[5])
	var gc := Vector3(cmc.field_a[3], cmc.field_a[4], cmc.field_a[5])
	gut.p("60 nmi up: GRAIL's pull beyond the point %.0f um/s2, R-2's %.0f um/s2, %.0f um/s2 apart" % [
		gt.length() * 1e6, gc.length() * 1e6, (gt - gc).length() * 1e6])
	assert_gt((gt - gc).length(), 5e-5, "the mascons R-2 lacks")

## Gravity beyond the two point masses (slice 5a): the Earth's zonal
## harmonics against their potential's gradient and J2's secular turning of
## an orbit's plane, the Sun's pull against its tide, the Earth's pole of
## date, and the mission turning them on.
extends GutTest


func before_each() -> void:
	Bodies.configure(28.5, 0.0, 3.3, -20.0)


func after_all() -> void:
	# Back to the mission's own Moon for the tests after these.
	Mission.load_default()


## The zonal harmonics' potential at (x, y, z) relative to the Earth, beyond
## the point mass: -mu/r sum J_n (R/r)^n P_n(u), u the sine of the latitude.
static func _zonal_potential(x: float, y: float, z: float) -> float:
	var p := Bodies.earth_pole
	var r := sqrt(x * x + y * y + z * z)
	var u := (x * p[0] + y * p[1] + z * p[2]) / r
	var q := Bodies.R_EARTH / r
	var p2 := (3.0 * u * u - 1.0) / 2.0
	var p3 := (5.0 * u * u * u - 3.0 * u) / 2.0
	var p4 := (35.0 * u * u * u * u - 30.0 * u * u + 3.0) / 8.0
	return -Bodies.MU_EARTH / r * (Bodies.EARTH_J2 * q * q * p2 + Bodies.EARTH_J3 * q * q * q * p3
		+ Bodies.EARTH_J4 * q * q * q * q * p4)


func test_the_zonal_acceleration_is_its_potentials_gradient() -> void:
	# About a tilted pole, at points north, south and on the equator.
	Bodies.earth_pole = PackedFloat64Array([0.1, -0.2, sqrt(1.0 - 0.05)])
	for pt in [Vector3(6.56e6, 1.2e6, 3.0e6), Vector3(-2.0e6, 4.0e6, -5.5e6), Vector3(7.0e6, 0.0, 0.0)]:
		var a := Trajectory._zonal(pt.x, pt.y, pt.z, pt.length_squared())
		var h := 10.0
		for i in 3:
			var d := Vector3.ZERO
			d[i] = h
			var up: Vector3 = pt + d
			var dn: Vector3 = pt - d
			var fd := (_zonal_potential(up.x, up.y, up.z) - _zonal_potential(dn.x, dn.y, dn.z)) / (2.0 * h)
			assert_almost_eq(a[i], fd, absf(fd) * 1e-5 + 1e-9, "axis %d at %s" % [i, pt])
	# At the equator J2 pulls in by 1.5 J2 of gravity, and J4 out by 15/8
	# J4 (J3's term is nil there).
	Bodies.earth_pole = PackedFloat64Array([0.0, 0.0, 1.0])
	var eq := Trajectory._zonal(Bodies.R_EARTH, 0.0, 0.0, Bodies.R_EARTH * Bodies.R_EARTH)
	var g := Bodies.MU_EARTH / (Bodies.R_EARTH * Bodies.R_EARTH)
	assert_almost_eq(eq[0], -1.5 * Bodies.EARTH_J2 * g + 1.875 * Bodies.EARTH_J4 * g, 1e-9, "at the equator")


func test_the_zonal_energy_is_conserved_with_the_orbits() -> void:
	# The zonal harmonics' potential energy is the negative of the potential
	# the acceleration is the gradient of, and nil without them.
	var pt := Vector3(6.1e6, -1.5e6, 2.8e6)
	assert_eq(Bodies.zonal_energy(pt.x, pt.y, pt.z), 0.0, "nil on the circular model")
	Bodies.perturbed = true
	assert_almost_eq(Bodies.zonal_energy(pt.x, pt.y, pt.z), -_zonal_potential(pt.x, pt.y, pt.z), 1e-6)
	# Round a parking orbit, the two-body energy swings by kilojoules and the
	# energy counting the oblate potential holds (the Moon's and the Sun's
	# tides aside).
	var r := Bodies.R_EARTH + 185200.0
	var v := sqrt(Bodies.MU_EARTH / r)
	var inc := deg_to_rad(32.5)
	var tr := Trajectory.new()
	tr.set_state("earth", 0.0, Vector3(r, 0.0, 0.0), Vector3(0.0, v * cos(inc), v * sin(inc)))
	var two_body := []
	var full := []
	for i in 12:
		tr.coast_to(tr.t + 450.0, 30.0)
		two_body.append(Sivb.energy_of(tr.s) - Bodies.zonal_energy(tr.s[0], tr.s[1], tr.s[2]))
		full.append(Sivb.energy_of(tr.s))
	var swing: float = two_body.max() - two_body.min()
	var held: float = full.max() - full.min()
	gut.p("round an orbit the two-body energy swings %.0f J/kg, the full one %.2f J/kg" % [swing, held])
	assert_gt(swing, 1000.0, "the two-body energy swings")
	assert_lt(held, swing / 1000.0, "the energy with the oblate potential holds")


func test_a_parking_orbits_plane_turns_west_at_j2s_rate() -> void:
	Bodies.perturbed = true
	# A circular 100 nmi orbit at 32.5 degrees, as Apollo 11's.
	var r := Bodies.R_EARTH + 185200.0
	var v := sqrt(Bodies.MU_EARTH / r)
	var inc := deg_to_rad(32.5)
	var tr := Trajectory.new()
	tr.set_state("earth", 0.0, Vector3(r, 0.0, 0.0), Vector3(0.0, v * cos(inc), v * sin(inc)))
	var n0 := _node_deg(tr)
	var period: float = tr.conic()["period"]
	# Two revolutions, measured at the same point in the orbit, where the
	# plane's short-period swing comes back.
	tr.coast_to(2.0 * period, 30.0)
	var turned := wrapf(_node_deg(tr) - n0, -180.0, 180.0)
	var n := sqrt(Bodies.MU_EARTH / (r * r * r))
	var rate := -1.5 * n * Bodies.EARTH_J2 * pow(Bodies.R_EARTH / r, 2.0) * cos(inc)
	var expect := rad_to_deg(rate * 2.0 * period)
	gut.p("node %.4f deg in two revolutions (J2's rate: %.4f deg; %.3f deg/h)" % [turned, expect, rad_to_deg(rate) * 3600.0])
	assert_almost_eq(turned, expect, absf(expect) * 0.03, "the node regresses at J2's rate")
	assert_lt(turned, 0.0, "westward")


func test_the_rtccs_vacuum_perigee_is_flown_through_the_oblateness() -> void:
	Bodies.perturbed = true
	# Returns that bottom out over the equator 40 km up, 2 km under the
	# surface and 60 km under it: from there, twelve hours back out, then
	# in again as the RTCC sees them. Under the surface the path is flown
	# on through the same field, so the perigee runs on smoothly past it.
	for alt in [40000.0, -2000.0, -60000.0]:
		var rp: float = Bodies.R_EARTH + alt
		var tr := _return_from(rp)
		var er := Rtcc.earth_return(tr.clone(), tr.t + 86400.0)
		var conic := _conic_perigee(tr)
		gut.p("perigee %.2f km; the RTCC's %.3f km, the conic's at 100,000 km %.3f km" % [
			alt / 1000.0, (float(er["rp"]) - Bodies.R_EARTH) / 1000.0, (conic - Bodies.R_EARTH) / 1000.0])
		assert_almost_eq(float(er["rp"]), rp, 100.0, "the vacuum perigee flown, %.0f km" % (alt / 1000.0))
		assert_gt(absf(conic - rp), 1000.0, "which the conic misses by kilometres")
		if alt == -2000.0:
			assert_gt(conic, Bodies.R_EARTH, "a conic above the surface for a path that goes under it")
	# A return far steeper than the corridor keeps the conic's perigee.
	var deep := _return_from(0.3 * Bodies.R_EARTH)
	var er_deep := Rtcc.earth_return(deep.clone(), deep.t + 86400.0)
	assert_lt(float(er_deep["rp"]), Rtcc.VACUUM_FLOOR, "below the floor")
	assert_almost_eq(float(er_deep["rp"]), _conic_perigee(deep), 1.0, "the conic's")


## A return that bottoms out at radius [param rp] over the equator,
## flown back twelve hours from there.
static func _return_from(rp: float) -> Trajectory:
	var vp := sqrt(2.0 * (-7.4e5 + Bodies.MU_EARTH / rp))
	var tr := Trajectory.new()
	tr.set_state("earth", 50000.0, Vector3(rp, 0.0, 0.0), Vector3(0.0, vp * cos(0.3), vp * sin(0.3)))
	while tr.t > 50000.0 - 12.0 * 3600.0:
		tr.step(-clampf(0.002 * tr.radius() / tr.speed(), 0.5, 60.0))
	return tr


## The conic perigee radius of [param tr] once it comes within 100,000 km.
static func _conic_perigee(tr: Trajectory) -> float:
	var at := tr.clone()
	at.coast_until(func(t2: Trajectory) -> bool: return t2.radius() < 1.0e8, at.t + 86400.0, Rtcc.MAX_DT, Rtcc.FRAC)
	return Trajectory.conic_of(at.earth_state(), Bodies.MU_EARTH)["rp"]


## The right ascension of the ascending node, degrees.
static func _node_deg(tr: Trajectory) -> float:
	var h: Vector3 = tr.conic()["h"]
	return rad_to_deg(atan2(h.x, -h.y))


func test_the_suns_pull_is_its_tide() -> void:
	# Near the Earth and at the Moon's distance, the Sun's pull on the
	# spacecraft less its pull on the primary is, to first order in r/d,
	# mu d^-3 (3 (d_hat . r) d_hat - r).
	var sun := PackedFloat64Array([1.2e11, -8.0e10, -3.5e10])
	var tr := Trajectory.new()
	tr.set_state("earth", 0.0, Vector3(7.0e6, 0.0, 0.0), Vector3.ZERO)
	for pt in [Vector3(6.6e6, 1.0e6, -2.0e6), Vector3(-2.5e8, 2.8e8, 1.0e8)]:
		var none := tr._accel(0.0, pt.x, pt.y, pt.z, PackedFloat64Array(), PackedFloat64Array())
		var with := tr._accel(0.0, pt.x, pt.y, pt.z, PackedFloat64Array(), sun)
		var got := Vector3(with[0] - none[0], with[1] - none[1], with[2] - none[2])
		var d := Vector3(sun[0], sun[1], sun[2])
		var dh := d.normalized()
		var tide: Vector3 = (dh * 3.0 * dh.dot(pt) - pt) * (Bodies.MU_SUN / pow(d.length(), 3.0))
		assert_almost_eq(got.distance_to(tide) / tide.length(), 0.0, 0.01, "at %s: %s against %s" % [pt, got, tide])


func test_the_mission_turns_them_on_about_the_pole_of_its_date() -> void:
	Mission.load_default()
	assert_true(Bodies.perturbed, "on with JPL's ephemeris")
	var p := Bodies.earth_pole
	var tilt := rad_to_deg(acos(p[2]))
	# 30.46 years of precession before J2000 at 2004.3 arc seconds a century.
	assert_almost_eq(tilt, 2004.3109 * 0.3046 / 3600.0, 0.002, "the pole of 1969, %.4f deg from J2000's" % tilt)
	assert_lt(p[0], 0.0, "toward -X, where the pole has precessed from")
	Bodies.configure(28.5, 0.0, 3.3, -20.0)
	assert_false(Bodies.perturbed, "off on the circular model")
	assert_eq(Bodies.earth_pole, PackedFloat64Array([0.0, 0.0, 1.0]))

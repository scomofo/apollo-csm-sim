## The Moon-fixed frame (slice 3c): synchronous rotation with the pole on
## the lunar orbit normal, and selenographic coordinates.
extends GutTest


func before_each() -> void:
	Bodies.configure(28.5, 0.0, 3.3, -20.0)


func test_the_moon_keeps_its_0_0_point_facing_the_earth() -> void:
	for t in [0.0, 75.0 * 3600.0, 102.76 * 3600.0, 200.0 * 3600.0]:
		var mf := Bodies.moon_fixed(t)
		var m := Bodies.moon_state(t)
		var to_earth := -Vector3(m[0], m[1], m[2]).normalized()
		assert_almost_eq(mf.x, to_earth, Vector3.ONE * 1e-6, "0° N, 0° E faces the Earth at GET %.0f" % t)
		assert_almost_eq(mf.z, Bodies.moon_normal(), Vector3.ONE * 1e-6, "the pole is the orbit normal")
		assert_almost_eq(mf.y, mf.z.cross(mf.x), Vector3.ONE * 1e-6, "Y is 90° E, right-handed")
		assert_almost_eq(mf.determinant(), 1.0, 1e-6)


func test_the_moon_turns_once_a_sidereal_month() -> void:
	var n := Bodies.moon_mean_motion()
	assert_almost_eq(TAU / n / 86400.0, 27.3, 0.1, "a sidereal month, days")
	var a := Bodies.moon_fixed(80.0 * 3600.0)
	var b := Bodies.moon_fixed(80.0 * 3600.0 + 3600.0)
	assert_almost_eq(a.x.angle_to(b.x), n * 3600.0, 1e-6, "an hour's turn")
	assert_almost_eq(Bodies.moon_omega(), Bodies.moon_normal() * n, Vector3.ONE * 1e-12)
	# A point on the surface moves as the Moon turns under it.
	var p := Bodies.selenographic_to_fixed(0.674, 23.473, Bodies.R_MOON)
	var v := (b * p - a * p) / 3600.0
	assert_almost_eq(v.length(), (Bodies.moon_omega().cross(a * p)).length(), 1e-3, "at 4.6 m/s")


func test_selenographic_coordinates_round_trip() -> void:
	var p := Bodies.selenographic_to_fixed(0.674, 23.473, Bodies.R_MOON)
	var s := Bodies.fixed_to_selenographic(p)
	assert_almost_eq(s.x, 0.674, 1e-5, "latitude")
	assert_almost_eq(s.y, 23.473, 1e-5, "east longitude")
	assert_almost_eq(s.z, Bodies.R_MOON, 0.5, "radius")
	assert_almost_eq(Bodies.selenographic_to_fixed(0.0, 90.0, 1.0), Vector3(0, 1, 0), Vector3.ONE * 1e-6, "90° E is +Y")
	assert_almost_eq(Bodies.selenographic_to_fixed(90.0, 0.0, 1.0), Vector3(0, 0, 1), Vector3.ONE * 1e-6, "the north pole is +Z")

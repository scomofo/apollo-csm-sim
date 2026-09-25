## JPL's ephemeris for Apollo 11 (slice 4a, data/ephemeris/): the Chebyshev
## series tools/ephemeris/fit_ephemeris.py fits, as Ephemeris and Bodies
## evaluate them, against JPL Horizons values held out of the fit
## (tests/fixtures/ephemeris_check.json). The slice asks for the Moon within
## 1 km and the Sun within 0.01°; the fit is far closer.
extends GutTest

const PATH := "res://data/ephemeris/apollo_11.json"
const CHECK := "res://tests/fixtures/ephemeris_check.json"
## Apollo 11's touchdown, 102:45:40 GET, and where.
const T_LAND := 369940.0
const SITE_LAT := 0.674
const SITE_LON := 23.473

var eph: Ephemeris
var points: Array


func before_all() -> void:
	eph = Ephemeris.load_file(PATH)
	points = JSON.parse_string(FileAccess.get_file_as_string(CHECK))["points"]


func before_each() -> void:
	Bodies.use_ephemeris(eph)


func after_all() -> void:
	# Back to the mission's own Moon for the tests after these.
	Mission.load_default()


static func _dist(a: PackedFloat64Array, b: Array, from: int) -> float:
	var s := 0.0
	for i in range(from, from + 3):
		s += (a[i] - float(b[i])) * (a[i] - float(b[i]))
	return sqrt(s)


## The angle between two directions given as doubles, degrees: from the
## cross product, which keeps its precision where acos of the dot product
## loses it.
static func _angle_deg(a: PackedFloat64Array, b: Array) -> float:
	var bx := float(b[0])
	var by := float(b[1])
	var bz := float(b[2])
	var cx := a[1] * bz - a[2] * by
	var cy := a[2] * bx - a[0] * bz
	var cz := a[0] * by - a[1] * bx
	return rad_to_deg(atan2(sqrt(cx * cx + cy * cy + cz * cz), a[0] * bx + a[1] * by + a[2] * bz))


func test_the_moon_and_the_sun_match_jpl_away_from_the_fitted_points() -> void:
	assert_eq(points.size(), 24, "three points in each of the eight segments")
	var worst := {"moon_m": 0.0, "moon_mps": 0.0, "sun_deg": 0.0}
	for p in points:
		var t := float(p["get_s"])
		var m := Bodies.moon_state(t)
		worst["moon_m"] = maxf(worst["moon_m"], _dist(m, p["moon"], 0))
		worst["moon_mps"] = maxf(worst["moon_mps"], _dist(m, p["moon"], 3))
		worst["sun_deg"] = maxf(worst["sun_deg"], _angle_deg(eph.sun_position(t), p["sun"]))
		assert_lt(rad_to_deg(Bodies.sun_direction(t).angle_to(Vector3(p["sun"][0], p["sun"][1], p["sun"][2]).normalized())),
			1e-4, "Bodies' Sun, in single precision")
	gut.p("Against JPL: the Moon within %.3f m and %s m/s, the Sun within %s°" % [
		worst["moon_m"], String.num_scientific(worst["moon_mps"]), String.num_scientific(worst["sun_deg"])])
	assert_lt(float(worst["moon_m"]), 1.0, "the Moon within a metre (the slice asks for 1 km)")
	assert_lt(float(worst["moon_mps"]), 1e-3, "and its velocity, the series' derivative, within 1 mm/s")
	assert_lt(float(worst["sun_deg"]), 1e-5, "the Sun's direction (the slice asks for 0.01°)")


func test_the_moon_fixed_frame_is_jpls_mean_earth_frame() -> void:
	for p in points:
		var t := float(p["get_s"])
		var ang := eph.moon_angles(t)
		for i in 3:
			assert_almost_eq(ang[i], float(p["moon_orientation"][i]), 1e-6, "the IAU model's angle %d at GET %.0f" % [i, t])
		# Where the Earth stands over the Moon, as Horizons has it.
		var a := Bodies.moon_fixed_axes(t)
		var m := Bodies.moon_state(t)
		var e := PackedFloat64Array()
		for k in 3:
			e.append(-(m[0] * a[3 * k] + m[1] * a[3 * k + 1] + m[2] * a[3 * k + 2]))
		var lon := rad_to_deg(atan2(e[1], e[0]))
		var lat := rad_to_deg(asin(e[2] / sqrt(e[0] * e[0] + e[1] * e[1] + e[2] * e[2])))
		assert_almost_eq(wrapf(lon - float(p["sub_earth"][0]), -180.0, 180.0), 0.0, 0.02, "sub-Earth longitude at GET %.0f" % t)
		assert_almost_eq(lat, float(p["sub_earth"][1]), 0.02, "sub-Earth latitude at GET %.0f" % t)
		assert_lt(absf(lon), 8.5, "the libration in longitude")
		assert_lt(absf(lat), 7.0, "and in latitude")
		assert_almost_eq(Bodies.moon_fixed(t).determinant(), 1.0, 1e-5, "a rotation")


func test_the_segments_join_smoothly() -> void:
	for s in eph.segments - 1:
		# The Sun's ends meet within metres at 150 million km: 1e-11 rad.
		for q in [["moon", 1.0, 1e-3], ["sun", 10.0, -1.0], ["moon_orientation", 1e-7, 1e-10]]:
			var series: Array = eph.get("_" + str(q[0]).replace("moon_orientation", "orient"))
			var rate: bool = float(q[2]) > 0.0
			var end := eph._evaluate(series, s + 1.0 - 1e-12, rate)
			var start := eph._evaluate(series, s + 1.0, rate)
			for i in end.size():
				var tol: float = q[1] if i < 3 else q[2]
				assert_almost_eq(end[i], start[i], tol, "%s component %d from segment %d to %d" % [q[0], i, s, s + 1])


func test_a_point_on_the_moon_moves_as_moon_omega_says() -> void:
	var p := Bodies.selenographic_to_fixed(SITE_LAT, SITE_LON, Bodies.R_MOON)
	for t in [0.0, 75.0 * 3600.0, T_LAND, 190.0 * 3600.0]:
		var h := 30.0
		var a := Bodies.moon_fixed_axes(t - h)
		var b := Bodies.moon_fixed_axes(t + h)
		var c := Bodies.moon_fixed_axes(t)
		var v := Vector3.ZERO
		var x := Vector3.ZERO
		for k in 3:
			v[k] = ((b[k] - a[k]) * p.x + (b[3 + k] - a[3 + k]) * p.y + (b[6 + k] - a[6 + k]) * p.z) / (2.0 * h)
			x[k] = c[k] * p.x + c[3 + k] * p.y + c[6 + k] * p.z
		var w := Bodies.moon_omega(t).cross(x)
		assert_almost_eq(v.distance_to(w), 0.0, 1e-4, "the site's velocity at GET %.0f, %.3f m/s" % [t, v.length()])


func test_the_sun_stands_where_apollo_11_found_it_at_touchdown() -> void:
	var site := Bodies.moon_fixed(T_LAND) * Bodies.selenographic_to_fixed(SITE_LAT, SITE_LON, 1.0)
	var s := eph.sun_position(T_LAND)
	var m := Bodies.moon_state(T_LAND)
	var sun := Vector3(s[0] - m[0], s[1] - m[1], s[2] - m[2]).normalized()
	var elevation := rad_to_deg(asin(site.dot(sun)))
	var pole := Bodies.moon_pole(T_LAND)
	var east := pole.cross(site).normalized()
	var azimuth := fposmod(rad_to_deg(atan2(sun.dot(east), sun.dot(site.cross(east)))), 360.0)
	gut.p("At touchdown the Sun stood %.2f° over Tranquility Base, at azimuth %.1f°" % [elevation, azimuth])
	assert_almost_eq(elevation, 10.8, 0.3, "the mission report's 10.8°: a low Sun behind the LM on the approach")
	assert_almost_eq(azimuth, 90.0, 5.0, "in the east")


func test_the_moons_pole_is_not_its_orbit_normal() -> void:
	var angle := rad_to_deg(Bodies.moon_pole(0.0).angle_to(Bodies.moon_normal()))
	assert_almost_eq(angle, 6.7, 0.2, "Cassini's laws: 1.5° to the ecliptic's pole, and the orbit 5.1° to the ecliptic")
	assert_almost_eq(TAU / Bodies.moon_mean_motion() / 86400.0, 27.32, 0.02, "it turns once a sidereal month")


func test_the_mission_chooses_the_model() -> void:
	var m := Mission.new()
	m.data = {"liftoff_jd": eph.epoch_jd_utc, "moon": {"ephemeris": PATH}}
	Bodies.configure(28.5, 0.0, 3.3, -20.0)
	m.apply_ephemeris()
	assert_eq(Bodies.ephemeris, eph, "a moon block that names the ephemeris flies on it")
	m.data["moon"] = {"inclination_deg": 28.5, "raan_deg": 0.0, "phase0_deg": 3.3, "sun_phase_deg": -20.0}
	m.apply_ephemeris()
	assert_null(Bodies.ephemeris, "and one of angles on the circular model")
	var r := Bodies.moon_state(1000.0)
	assert_almost_eq(Vector3(r[0], r[1], r[2]).length(), Bodies.MOON_DIST, 1.0, "at its constant distance")

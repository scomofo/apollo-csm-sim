## Slice 5d's models under the launch: the atmosphere's pressure and speed
## of sound, the Earth's turning and the air turning with it, and the IGM's
## integrals over a sequence of burns.
extends GutTest


func before_each() -> void:
	Mission.load_default()


func after_all() -> void:
	Mission.load_default()


## The 1976 U.S. Standard Atmosphere's own table at its layers' bases
## [published]: pressure, temperature and the speed of sound.
func test_the_atmosphere_is_the_1976_standards() -> void:
	for row in [[0.0, 101325.0, 288.15, 340.29], [11000.0, 22632.1, 216.65, 295.07], [20000.0, 5474.89, 216.65, 295.07],
			[32000.0, 868.019, 228.65, 303.13], [47000.0, 110.906, 270.65, 329.80], [71000.0, 3.95642, 214.65, 293.70]]:
		# The table's heights are geopotential; the model takes geometric.
		var h: float = row[0] * Bodies.R_EARTH / (Bodies.R_EARTH - row[0])
		var pt := Atmosphere.pressure_temperature(h)
		assert_almost_eq(pt.x, float(row[1]), float(row[1]) * 1e-3, "pressure at %.0f m" % row[0])
		assert_almost_eq(pt.y, float(row[2]), 0.01, "temperature at %.0f m" % row[0])
		assert_almost_eq(Atmosphere.sound_speed(h), float(row[3]), 0.05, "speed of sound at %.0f m" % row[0])
	assert_lt(Atmosphere.pressure(100000.0), 0.1, "next to nothing at 100 km")


## The Earth-fixed frame turns about the pole of date, once a sidereal day,
## and the air at rest on the ground moves with it.
func test_the_earth_turns_and_the_air_with_it() -> void:
	var a := Bodies.earth_fixed_axes(0.0)
	var pole := Bodies.earth_pole
	assert_almost_eq(Vector3(a[6], a[7], a[8]).angle_to(Vector3(pole[0], pole[1], pole[2])), 0.0, 1e-7, "Z the pole of date")
	var b := Bodies.earth_fixed_axes(3600.0)
	var turned := Vector3(a[0], a[1], a[2]).angle_to(Vector3(b[0], b[1], b[2]))
	assert_almost_eq(rad_to_deg(turned), rad_to_deg(Bodies.EARTH_OMEGA * 3600.0), 1e-4, "15.04 degrees an hour")
	# A point on the ground: its velocity is the Earth's turning, and the air
	# there is still.
	var p := Bodies.geographic_to_fixed(28.608389, -80.604333, Bodies.R_EARTH)
	var r0 := Bodies.earth_fixed_to_eci(p, 0.0)
	var before := Bodies.earth_fixed_to_eci(p, -0.5)
	var after := Bodies.earth_fixed_to_eci(p, 0.5)
	var v := Vector3(after[0] - before[0], after[1] - before[1], after[2] - before[2])
	var r := Vector3(r0[0], r0[1], r0[2])
	assert_almost_eq((v - Bodies.earth_omega().cross(r)).length(), 0.0, 0.01, "the ground moves with the Earth's turning")
	assert_almost_eq(v.length(), 408.1, 0.5, "408 m/s at Launch Complex 39A")
	assert_almost_eq(Atmosphere.air_velocity(r, Bodies.earth_omega().cross(r)).length(), 0.0, 1e-6, "the air there is still")
	var back := Bodies.eci_to_earth_fixed(r0, 0.0)
	assert_almost_eq(Vector3(back[0] - p[0], back[1] - p[1], back[2] - p[2]).length(), 0.0, 1e-4, "and back again")


## The pad's vertical against the one the launch REFSMMAT was taken on at
## GET 0 (mission.json, by tools/ephemeris/parking_orbit.py's Greenwich
## sidereal time and precession): the geodetic vertical, which the round
## Earth takes for the pad's radius, the Earth turned the same way.
func test_the_pad_is_where_the_launch_refsmmat_has_it() -> void:
	var m := Mission.load_default()
	var l := m.section("launch")
	var p := Bodies.geographic_to_fixed(float(l["pad_lat_deg"]), float(l["pad_lon_deg"]), Bodies.R_EARTH)
	var up := Bodies.earth_fixed_to_eci(p, 0.0)
	var z: Array = m.section("launch_refsmmat")["z"]
	var ang := rad_to_deg(Vector3(up[0], up[1], up[2]).angle_to(-Vector3(z[0], z[1], z[2])))
	gut.p("the pad's up is %.6f deg from the REFSMMAT's vertical" % ang)
	assert_lt(ang, 1e-4)


## The integrals of a sequence of burns with a coast between, against the
## acceleration integrated step by step: L its speed, J its moment, S the
## distance by the end, Q that distance's moment.
func test_the_igms_integrals_over_burns_in_sequence() -> void:
	var burns := [{"t0": 0.0, "T": 120.0, "F": 5.1e6, "mdot": 1234.5, "m0": 600000.0},
		{"t0": 120.0, "T": 80.0, "F": 3.06e6, "mdot": 732.0, "m0": 451860.0},
		{"t0": 204.0, "T": 150.0, "F": 901223.0, "mdot": 214.38, "m0": 166634.0}]
	var it := Sivb._integrals(burns)
	var h := 0.001
	var l := 0.0
	var j := 0.0
	var s := 0.0
	var q := 0.0
	var t := 0.0
	var t_end := 354.0
	while t < t_end - h / 2.0:
		var a := 0.0
		for b: Dictionary in burns:
			var dt: float = t + h / 2.0 - float(b["t0"])
			if dt >= 0.0 and dt < float(b["T"]):
				a = float(b["F"]) / (float(b["m0"]) - float(b["mdot"]) * dt)
		l += a * h
		j += a * (t + h / 2.0) * h
		s += l * h
		q += j * h
		t += h
	assert_almost_eq(float(it["T"]), t_end, 1e-9)
	assert_almost_eq(float(it["L"]), l, l * 1e-6, "L")
	assert_almost_eq(float(it["J"]), j, j * 1e-5, "J")
	assert_almost_eq(float(it["S"]), s, s * 1e-5, "S")
	assert_almost_eq(float(it["Q"]), q, q * 1e-5, "Q")

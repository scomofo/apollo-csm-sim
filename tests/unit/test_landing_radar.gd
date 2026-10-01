## The landing radar: slant range to the terrain along its altitude beam,
## its data-good ranges and its velocity over the turning surface; its
## range scale, and its breaker's cycle bringing Apollo 14's back from low
## scale (slice 12a); and the LGC's terrain model, which takes Apollo 15's
## altitude over the Apennines (slice 12b).
extends GutTest

const T := 367000.0

var lr: LandingRadar


func before_each() -> void:
	Bus.reset()
	Bodies.configure(28.5, 0.0, 3.3, -20.0)
	Bus.set_value("time.get_s", T)
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "moon")
	Bus.set_value("lm.dyn.landed", false)
	lr = LandingRadar.new()
	add_child_autofree(lr)


func after_all() -> void:
	# Back to the mission's own Moon for the tests after these.
	Mission.load_default()


## Put the LM [param height] m over the ground at Tranquility Base,
## [param east] m east of it, turned [param q] (LM axes to inertial), moving
## [param v_rel] over the surface (inertial). Returns the ground's radius
## below it.
func _place(height: float, q: Quaternion, v_rel: Vector3 = Vector3.ZERO, east: float = 0.0) -> float:
	var mf := Bodies.moon_fixed(T)
	var lon := 23.473 + east / (Bodies.R_MOON * PI / 180.0)
	var ground := Bodies.R_MOON + Terrain.height(0.674, lon)
	var r := mf * Bodies.selenographic_to_fixed(0.674, lon, ground + height)
	var v := v_rel + Bodies.moon_omega(T).cross(r)
	Bus.set_value("lm.dyn.r_m", [r.x, r.y, r.z])
	Bus.set_value("lm.dyn.v_mps", [v.x, v.y, v.z])
	Bus.set_value("lm.dyn.att_q", q)
	return ground


## The LM upright over the Moon-fixed point at the site: +X up, +Z east.
func _upright() -> Quaternion:
	var mf := Bodies.moon_fixed(T)
	var up := (mf * Bodies.selenographic_to_fixed(0.674, 23.473, 1.0)).normalized()
	var east := (mf * Vector3(0, 0, 1)).cross(up).normalized()
	return Basis(up, east.cross(up), east).get_rotation_quaternion()


func test_straight_down_it_measures_the_height_over_the_ground() -> void:
	Bus.set_value("lm.guid.lr_antenna", 2)
	_place(500.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.alt_good"))
	assert_almost_eq(float(Bus.get_value("lm.lr.range_m")), 500.0, 1.0, "the height, over level ground")
	assert_eq(Bus.get_value("lm.lr.beam_body"), Vector3(-1, 0, 0), "position 2: along -X")


func test_position_1_looks_down_and_ahead() -> void:
	# Braking, windows up: +X back along the track and a little up, +Z up.
	var mf := Bodies.moon_fixed(T)
	var up := (mf * Bodies.selenographic_to_fixed(0.674, 23.473, 1.0)).normalized()
	var east := (mf * Vector3(0, 0, 1)).cross(up).normalized()
	var x := (east * cos(deg_to_rad(20.0)) + up * sin(deg_to_rad(20.0)))
	var y := up.cross(x).normalized()
	var q := Basis(x, y, x.cross(y)).get_rotation_quaternion()
	Bus.set_value("lm.guid.lr_antenna", 1)
	_place(3000.0, q)
	lr.tick(0.02)
	# The beam is 45° from -X toward -Z: 65° below the horizon, westward.
	var slant := float(Bus.get_value("lm.lr.range_m"))
	assert_true(Bus.get_value("lm.lr.alt_good"))
	assert_almost_eq(slant * sin(deg_to_rad(65.0)), 3000.0, 60.0, "the slant range reaches the ground")
	var beam: Vector3 = Bus.get_value("lm.lr.beam_body")
	assert_almost_eq(beam, Vector3(-cos(PI / 4.0), 0.0, -sin(PI / 4.0)), Vector3.ONE * 1e-6)


func test_the_data_are_good_within_the_radars_range() -> void:
	Bus.set_value("lm.guid.lr_antenna", 2)
	var d := SpacecraftData.section("landing_radar")
	_place(float(d["alt_range_m"]) + 200.0, _upright())
	lr.tick(0.02)
	assert_false(Bus.get_value("lm.lr.alt_good"), "beyond the altitude beam's range")
	_place((float(d["alt_range_m"]) + float(d["vel_range_m"])) / 2.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.alt_good"), "altitude first")
	assert_false(Bus.get_value("lm.lr.vel_good"), "then velocity")
	_place(float(d["vel_range_m"]) - 200.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.vel_good"))
	# Docked, or on the surface, it has nothing.
	Bus.set_value("lm.dyn.landed", true)
	lr.tick(0.02)
	assert_false(Bus.get_value("lm.lr.alt_good"))
	assert_eq(float(Bus.get_value("lm.lr.range_m")), 0.0)


func test_it_measures_the_velocity_over_the_turning_surface_in_the_lms_axes() -> void:
	Bus.set_value("lm.guid.lr_antenna", 2)
	var q := _upright()
	var b := Basis(q)
	var v_rel := b * Vector3(-3.0, 0.5, 12.0)   # 3 m/s down, 12 m/s forward, 0.5 right
	_place(200.0, q, v_rel)
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.vel_good"))
	assert_almost_eq(Bus.get_value("lm.lr.vel_body"), Vector3(-3.0, 0.5, 12.0), Vector3.ONE * 0.01, "the Moon's turning taken out")


func test_the_beam_meets_the_real_ground() -> void:
	# Over West crater's floor the ground is about 30 m lower than at the
	# site: the radar sees it.
	Bus.set_value("lm.guid.lr_antenna", 2)
	var mf := Bodies.moon_fixed(T)
	var lat := 0.674 - 104.0 / (Bodies.R_MOON * PI / 180.0)
	var lon := 23.473 + 552.0 / (Bodies.R_MOON * PI / 180.0)
	var ground := Bodies.R_MOON + Terrain.height(lat, lon)
	var p := mf * Bodies.selenographic_to_fixed(lat, lon, 1.0)
	var r := p * (Bodies.R_MOON - 1927.5 + 300.0)
	Bus.set_value("lm.dyn.r_m", [r.x, r.y, r.z])
	var v := Bodies.moon_omega(T).cross(r)
	Bus.set_value("lm.dyn.v_mps", [v.x, v.y, v.z])
	var east := (mf * Vector3(0, 0, 1)).cross(p).normalized()
	Bus.set_value("lm.dyn.att_q", Basis(p, east.cross(p), east).get_rotation_quaternion())
	lr.tick(0.02)
	assert_almost_eq(float(Bus.get_value("lm.lr.range_m")), r.length() - ground, 1.0, "to the crater's floor")
	assert_gt(float(Bus.get_value("lm.lr.range_m")), 325.0, "25 m or more below the site's level")


func test_in_low_scale_it_takes_the_range_only_within_3500_ft() -> void:
	# Apollo 14's failure: the scale low with nothing measured.
	Bus.set_value("lm.guid.lr_antenna", 2)
	lr.fail("scale")
	_place(3000.0, _upright())
	lr.tick(0.02)
	assert_eq([Bus.get_value("lm.lr.alt_good"), Bus.get_value("lm.lr.vel_good")], [false, false],
		"at 3,000 m, well within the high scale's range, nothing")
	assert_true(Bus.get_value("lm.lr.low_scale"), "and the scale stays low")
	_place(1300.0, _upright())
	lr.tick(0.02)
	assert_eq([Bus.get_value("lm.lr.alt_good"), Bus.get_value("lm.lr.vel_good")], [false, true],
		"at 4,265 ft the velocity, within 4,600 ft of altitude, and not the range")
	_place(1000.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.alt_good"), "the range within 3,500 ft")
	assert_false(Bus.get_value("lm.lr.low_scale"), "measured beyond 2,800 ft, the scale goes back to high")
	_place(700.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.low_scale"), "below 2,500 ft, low again")
	_place(800.0, _upright())
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.low_scale"), "and low still between 2,500 and 2,800 ft")
	_place(900.0, _upright())
	lr.tick(0.02)
	assert_false(Bus.get_value("lm.lr.low_scale"), "high again above 2,800 ft")


func test_a_breaker_cycle_brings_it_back_in_high_scale() -> void:
	Bus.set_value("lm.guid.lr_antenna", 2)
	lr.fail("scale")
	_place(6000.0, _upright())
	lr.tick(0.02)
	assert_false(Bus.get_value("lm.lr.alt_good"), "in low scale, nothing at 6,000 m")
	Bus.set_value("ctl.lm.cb_ldg_rdr", false)
	lr.tick(0.02)
	assert_false(Bus.get_value("lm.lr.powered"), "the breaker out: the radar off")
	Bus.set_value("time.get_s", T + 2.0)
	Bus.set_value("ctl.lm.cb_ldg_rdr", true)
	lr.tick(0.02)
	assert_eq([Bus.get_value("lm.lr.powered"), Bus.get_value("lm.lr.low_scale")], [true, false], "back in: high scale")
	assert_false(Bus.get_value("lm.lr.vel_good"), "its trackers searching")
	Bus.set_value("time.get_s", T + 22.0)
	lr.tick(0.02)
	assert_eq([Bus.get_value("lm.lr.vel_good"), Bus.get_value("lm.lr.alt_good")], [true, false], "the velocity 20 s on")
	Bus.set_value("time.get_s", T + 24.0)
	lr.tick(0.02)
	assert_true(Bus.get_value("lm.lr.alt_good"), "and the range 22 s on")
	assert_almost_eq(float(Bus.get_value("lm.lr.range_m")), 6000.0, 30.0, "over the Moon that turned under it")


## Slice 12b: the LGC's terrain model (Lgc.terrain_height()), Luminary's,
## with Apollo 15's e-load: the ground's height over the landing site where
## the landing radar's beam meets it, along the track, from five slopes
## back to 181 km uprange, and SLOPE4 on past the site. Apollo 11's LGC
## has none: the ground the site's height.
func test_the_lgcs_terrain_model_is_apollo_15s_apennines() -> void:
	Mission.load_file(Mission.path_of("apollo_15"))
	assert_almost_eq(Lgc.terrain_height(0.0), 0.0, 1e-6, "level at the site")
	assert_almost_eq(Lgc.terrain_height(1000.0), 11.3, 0.05, "SLOPE4 on past it")
	assert_almost_eq(Lgc.terrain_height(-8900.16), -100.58, 0.05, "a dip 8.9 km uprange (ABSC4)")
	assert_almost_eq(Lgc.terrain_height(-20000.0), 2283.48, 0.05, "the Apennine front's slope")
	assert_almost_eq(Lgc.terrain_height(-27249.12), 3840.48, 0.05, "its crest 27 km uprange (ABSC3)")
	assert_almost_eq(Lgc.terrain_height(-32308.8), 2895.60, 0.05, "behind it (ABSC2)")
	assert_almost_eq(Lgc.terrain_height(-59740.8), 2895.60, 0.05, "level to ABSC1")
	assert_almost_eq(Lgc.terrain_height(-180746.4), 358.35, 0.05, "down 1.2 deg over the mare to ABSC0")
	assert_almost_eq(Lgc.terrain_height(-250000.0), 358.35, 0.05, "and level beyond")
	Mission.load_default()
	assert_eq(Lgc.terrain_height(-20000.0), 0.0, "Apollo 11's LGC has none")

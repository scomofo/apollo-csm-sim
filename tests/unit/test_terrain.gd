## The surface around Tranquility Base: NASA's elevation maps
## (data/terrain/), blended from the Apollo 11 site's 4 m terrain model out
## to LOLA's 1° map.
extends GutTest

const LM_LAT := 0.67416
const LM_LON := 23.47314
const M_PER_DEG := Bodies.R_MOON * PI / 180.0


## [param east] and [param north] metres from where the LM landed.
func _at(east: float, north: float) -> float:
	return Terrain.height(LM_LAT + north / M_PER_DEG, LM_LON + east / M_PER_DEG)


func test_tranquility_base_lies_1927_m_below_the_reference_sphere() -> void:
	assert_almost_eq(_at(0.0, 0.0), -1927.4, 0.5, "the LM's spot, LROC's terrain model")
	assert_eq(Terrain.source(LM_LAT, LM_LON), "site")
	# Where Eagle stood is nearly level over the LM's footprint.
	for p in [Vector2(5, 0), Vector2(-5, 0), Vector2(0, 5), Vector2(0, -5)]:
		assert_almost_eq(_at(p.x, p.y), _at(0.0, 0.0), 1.0, "level within 5 m")


func test_west_crater_lies_east_of_the_lm() -> void:
	var floor_h := _at(552.0, -104.0)
	assert_lt(floor_h, -1955.0, "West crater's floor")
	assert_almost_eq(_at(552.0 + 95.0, -104.0) - floor_h, 29.0, 6.0, "about 30 m deep to its rim")


func test_the_maps_blend_without_steps() -> void:
	assert_eq(Terrain.source(LM_LAT, LM_LON + 10000.0 / M_PER_DEG), "near", "SLDEM2015 at 59 m, 10 km out")
	assert_eq(Terrain.source(LM_LAT, LM_LON + 150000.0 / M_PER_DEG), "approach", "at 118 m, 150 km out")
	assert_eq(Terrain.source(45.0, 200.0), "moon", "LOLA at 1° elsewhere")
	# Across the site map's edges and the near map's: no step between posts.
	for line in [[Vector2(900, 0), Vector2(1400, 0)], [Vector2(0, 600), Vector2(0, 1100)],
			[Vector2(-1300, 0), Vector2(-1800, 0)], [Vector2(32000, 0), Vector2(36000, 0)]]:
		var a: Vector2 = line[0]
		var b: Vector2 = line[1]
		var n := int(a.distance_to(b) / 4.0)
		var worst := 0.0
		var prev := _at(a.x, a.y)
		for i in range(1, n + 1):
			var p := a.lerp(b, float(i) / n)
			var h := _at(p.x, p.y)
			worst = maxf(worst, absf(h - prev))
			prev = h
		assert_lt(worst, 2.5, "no step over 4 m from %s to %s" % [a, b])


func test_the_approach_follows_the_mare() -> void:
	# The ground along the approach, from SLDEM2015: lower than the site
	# 10 to 150 km out.
	assert_almost_eq(_at(10000.0, 0.0), -2015.0, 5.0)
	assert_almost_eq(_at(40000.0, 0.0), -2101.0, 5.0)
	assert_almost_eq(_at(150000.0, 0.0), -2206.0, 5.0)


func test_heights_under_a_moon_fixed_point() -> void:
	var p := Bodies.selenographic_to_fixed(LM_LAT, LM_LON, Bodies.R_MOON + 15000.0)
	assert_almost_eq(Terrain.height_under(p), _at(0.0, 0.0), 0.2, "straight below, from any height")
	assert_almost_eq(Terrain.radius_under(p), Bodies.R_MOON - 1927.4, 0.6)
	# And the lookup is cheap enough for the landing radar and the gear.
	var t0 := Time.get_ticks_usec()
	for i in 2000:
		Terrain.height(LM_LAT + i * 1e-5, LM_LON + i * 2e-5)
	var us := float(Time.get_ticks_usec() - t0) / 2000.0
	gut.p("Terrain.height(): %.1f µs" % us)
	assert_lt(us, 100.0, "µs per lookup")

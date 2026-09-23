## The LGC's powered ascent guidance (AscentGuidance): the insertion
## targets and one cycle of its steering.
extends GutTest

const SITE_R := Bodies.R_MOON - 1927.5

## The CSM's orbit normal: an equatorial orbit about +Z, which passes
## over the site on the X axis moving along +Y.
var plane := Vector3(0, 0, 1)
var tg: Dictionary


func before_each() -> void:
	tg = AscentGuidance.targets(SITE_R)


## A state [param h] m over the site on the X axis, climbing at
## [param rdot], moving [param vh] along the CSM's track (+Y) and
## [param y] m to the side of its plane (+Z, the side its normal points
## to).
func _steer(h: float, rdot: float, vh: float, y: float = 0.0, mass: float = 4821.0) -> Dictionary:
	var r := Vector3(SITE_R + h, 0.0, y)
	var v := Vector3(rdot, vh, 0.0)
	return AscentGuidance.steer(r, v, r.length(), rdot, plane, mass, tg, 0.0)


func test_the_targets_are_a_9_by_45_nmi_orbit() -> void:
	assert_almost_eq(float(tg["r"]) - SITE_R, 18288.0, 0.01, "insertion at 60,000 ft")
	assert_almost_eq(float(tg["rdot"]) / Units.FT, 32.0, 1e-3, "climbing at 32 ft/s")
	assert_almost_eq(float(tg["vh"]) / Units.FT, 5535.0, 3.0, "at about 5,535 ft/s")
	var st := PackedFloat64Array([float(tg["r"]), 0.0, 0.0, float(tg["rdot"]), float(tg["vh"]), 0.0])
	var c := Trajectory.conic_of(st, Bodies.MU_MOON)
	assert_almost_eq(float(c["ra"]) - SITE_R, 83340.0, 1.0, "apolune 45 nmi above the site")
	assert_almost_eq((float(c["rp"]) - SITE_R) / Units.NMI, 9.0, 0.1, "perilune 9 nmi")


func test_after_the_vertical_rise_it_pitches_over_along_the_track() -> void:
	var g := _steer(50.0, 12.2, 0.0)
	var u: Vector3 = g["u"]
	var pitch := rad_to_deg(u.angle_to(Vector3.RIGHT))
	gut.p("Pitch from the vertical after the rise: %.1f°, time to go %.0f s" % [pitch, g["tgo"]])
	assert_between(pitch, 40.0, 65.0, "well over toward the horizon")
	assert_gt(u.y, 0.0, "downrange, along the CSM's track")
	assert_almost_eq(u.z, 0.0, 1e-6, "in the plane")
	assert_between(float(g["tgo"]), 380.0, 440.0, "some seven minutes to go")


func test_it_steers_back_into_the_csms_plane() -> void:
	# 2 km off the plane, on the side its normal points to.
	var g := _steer(5000.0, 40.0, 600.0, 2000.0)
	var u: Vector3 = g["u"]
	assert_lt(u.z, 0.0, "back toward the plane")
	assert_gt(u.z, -0.1, "a small part of the thrust")


func test_at_insertion_there_is_nothing_left_to_gain() -> void:
	var g := _steer(18288.0, float(tg["rdot"]), float(tg["vh"]), 0.0, 2600.0)
	assert_lt((g["vg"] as Vector3).length(), 1e-3, "no velocity to be gained")
	assert_lt(float(g["tgo"]), 0.1, "no time to go")


func test_the_time_to_go_is_the_rocket_equations() -> void:
	# Level at the insertion radius and climb, short of the horizontal
	# velocity: gravity's share is all but gone there.
	var short := 300.0
	var g := _steer(18288.0, float(tg["rdot"]), float(tg["vh"]) - short, 0.0, 3000.0)
	var aps := SpacecraftData.section("aps")
	var ve := float(aps["isp_s"]) * Units.G0
	var burn := 3000.0 * ve / float(aps["thrust_n"]) * (1.0 - exp(-short / ve))
	assert_almost_eq(float(g["tgo"]), burn, burn * 0.05, "the time to burn the mass for the velocity short")

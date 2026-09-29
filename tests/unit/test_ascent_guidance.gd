## The LGC's powered ascent guidance (AscentGuidance): the insertion
## targets and one cycle of its steering; and the aborts' targets (slice
## 9e), whose apolune phases the LM for the rendezvous.
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


## Slice 9e: the aborts' targets from Eagle [param lead_deg] behind
## Columbia (negative: ahead of it), 15 km up at [param vh], for TPI
## [param tpi_s] from now: Columbia on a circular orbit 60 nmi up, on
## the DPS at full thrust.
func _abort_targets(lead_deg: float, tpi_s: float, vh: float = 1200.0) -> Dictionary:
	var r := Vector3(SITE_R + 15000.0, 0.0, 0.0)
	var rc := SITE_R + 60.0 * Units.NMI
	var csm_r := Vector3(rc, 0.0, 0.0).rotated(plane, deg_to_rad(lead_deg))
	var csm_v := plane.cross(csm_r.normalized()) * sqrt(Bodies.MU_MOON / rc)
	return AscentGuidance.abort_targets(r, Vector3(0.0, vh, 0.0), csm_r, csm_v, SITE_R, 0.0,
		tpi_s if tpi_s > 0.0 else -1.0, 12000.0, 45040.0, 311.0)


func test_the_aborts_phase_their_apolune_for_the_rendezvous() -> void:
	var p12 := _abort_targets(-7.0, -1.0)
	assert_eq(p12["vh"], tg["vh"], "without a TPI time, P12's orbit")
	assert_eq([p12["r"], p12["rdot"]], [tg["r"], tg["rdot"]], "and always P12's radius and radial rate")
	# Early in the descent Eagle is ahead: it must climb above Columbia to
	# fall behind it by TPI, as Apollo 11's no-PDI abort's 11 x 152 nmi did.
	var early := _abort_targets(-7.0, 9500.0)
	var ra_early := (float(early["ra"]) - SITE_R) / Units.NMI
	assert_between(ra_early, 60.0, 200.0, "an apolune above Columbia's")
	assert_gt(float(early["vh"]), float(tg["vh"]))
	var st := PackedFloat64Array([float(early["r"]), 0.0, 0.0, float(early["rdot"]), float(early["vh"]), 0.0])
	assert_almost_eq(float(Trajectory.conic_of(st, Bodies.MU_MOON)["ra"]), float(early["ra"]), 1.0, "its velocity's apolune")
	# The more Columbia leads, the lower; far ahead, P12's orbit, the floor.
	var later := _abort_targets(2.0, 9500.0)
	assert_lt(float(later["ra"]), float(early["ra"]), "Columbia ahead: lower")
	var behind := _abort_targets(25.0, 9500.0)
	assert_eq(behind["vh"], tg["vh"], "Columbia far ahead: P12's orbit")
	# A later TPI: a longer coelliptic flight below Columbia, gaining on it,
	# so farther behind first; no higher than the limit.
	var late := _abort_targets(-7.0, 16000.0)
	assert_gt(float(late["ra"]), float(early["ra"]), "a later TPI: higher")
	assert_lt(float(late["ra"]) - SITE_R, 200.0 * Units.NMI + 1.0, "200 nmi at most")

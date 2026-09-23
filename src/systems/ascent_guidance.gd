## The LGC's powered ascent guidance (P12), after Luminary's: E guidance
## (Cherry, MIT Instrumentation Laboratory, 1964). The LM flies to
## insertion at a radius, a radial rate and a horizontal velocity, in the
## CSM's orbital plane. The thrust's radial and out-of-plane parts follow
## acceleration profiles linear in time, which null the errors in radius
## and radial rate, and in the distance from the plane and the rate across
## it, as the time to go runs out. The rest of the thrust is horizontal.
## The time to go comes from the rocket equation, for the velocity still to
## be gained with gravity's share. The LGC flies it (Lgc, P12), and the
## RTCC flies the same law to time the liftoff (Rtcc.simulate_ascent).
## [simplified: the thrust acceleration is the engine's nominal, not
## measured.]
class_name AscentGuidance
extends RefCounted


## The insertion targets for a landing site [param site_radius] from the
## Moon's centre: {"r" (radius, m), "rdot" (radial rate, m/s), "vh"
## (horizontal velocity, m/s)}.
static func targets(site_radius: float) -> Dictionary:
	var d := SpacecraftData.section("ascent_guidance")
	var r := site_radius + float(d["insertion_alt_m"])
	var rdot := float(d["insertion_hdot_mps"])
	return {"r": r, "rdot": rdot, "vh": insertion_vh(r, rdot, site_radius + float(d["insertion_apolune_alt_m"]))}


## The horizontal velocity at radius [param r], climbing at [param rdot],
## of the orbit whose apoapsis is at radius [param ra].
static func insertion_vh(r: float, rdot: float, ra: float) -> float:
	var mu := Bodies.MU_MOON
	return sqrt((rdot * rdot + 2.0 * mu * (1.0 / ra - 1.0 / r)) / (r * r / (ra * ra) - 1.0))


## One guidance cycle. [param r] and [param v] are the LM's position and
## velocity (Moon-centred, inertial), [param radius] and [param rdot] its
## radius and radial rate (in doubles), [param plane] the CSM's orbit
## normal, [param mass] the LM's, [param tg] the targets() and
## [param tgo] the last cycle's time to go. Returns {"u" (the thrust
## direction), "tgo" (s), "vg" (the velocity still to be gained,
## inertial, m/s)}.
static func steer(r: Vector3, v: Vector3, radius: float, rdot: float, plane: Vector3, mass: float,
		tg: Dictionary, tgo: float) -> Dictionary:
	var aps := SpacecraftData.section("aps")
	var ve := float(aps["isp_s"]) * Units.G0
	var at := float(aps["thrust_n"]) / mass
	var mu := Bodies.MU_MOON
	var rd := float(tg["r"])
	var rdot_d := float(tg["rdot"])
	var vh_d := float(tg["vh"])
	var rh := r.normalized()
	var hh := plane.cross(rh).normalized()   # downrange, in the CSM's plane
	var wh := rh.cross(hh)                    # across it
	var vh := v.dot(hh)
	var y := r.dot(plane)
	var ydot := v.dot(plane)
	# Gravity less the centrifugal, now and at insertion.
	var geff := mu / (radius * radius) - vh * vh / radius
	var geff_d := mu / (rd * rd) - vh_d * vh_d / rd
	# The rocket equation: the engine burns its mass down in ve / at.
	var t := maxf(tgo, 0.0)
	for _i in 3:
		var need := Vector3(rdot_d - rdot + 0.5 * (geff + geff_d) * t, vh_d - vh, -ydot)
		t = ve / at * (1.0 - exp(-need.length() / ve))
	var tt := maxf(t, 1.0)
	var ar := 6.0 * (rd - radius - rdot * tt) / (tt * tt) - 2.0 * (rdot_d - rdot) / tt + geff
	var ay := 6.0 * (-y - ydot * tt) / (tt * tt) + 2.0 * ydot / tt + mu * y / (radius * radius * radius)
	var ah2 := at * at - ar * ar - ay * ay
	if ah2 < 0.0:
		# More than the engine has: keep the command's direction in the
		# vertical, with a little thrust downrange.
		var k := 0.999 * at / sqrt(ar * ar + ay * ay)
		ar *= k
		ay *= k
		ah2 = at * at - ar * ar - ay * ay
	return {"u": (rh * ar + hh * sqrt(ah2) + wh * ay).normalized(), "tgo": t,
		"vg": rh * (rdot_d - rdot) + hh * (vh_d - vh) - wh * ydot}

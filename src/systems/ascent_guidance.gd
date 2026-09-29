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
##
## The aborts from the powered descent (slice 9e: Lgc, P70 on the descent
## engine and P71 on the ascent engine) fly the same law to the same
## insertion's radius and radial rate [published: Luminary 099's HINJECT,
## 60,000 ft; its ABTRDOT is erasable and not at hand, so P12's 32 ft/s
## stands in, estimated]. Only the horizontal velocity differs: "the
## desired orbit insertion conditions targeted by programs P-70 and P-71
## vary as a function of phase relationship between the LM and CSM to
## establish rendezvous sequencing" [published: Bennett, NASA TM X-58040,
## 1970]. Early in the descent Eagle is ahead of the CSM, and must climb
## into an orbit with a high apolune to fall behind it, as Apollo 11's
## no-PDI abort's 11 by 152 nmi did; later the CSM is ahead. Luminary
## took the velocity from a cubic in the descent's time to go (ABTCOF),
## floored at VMIN; its coefficients are erasable and not at hand, so
## abort_targets() solves for the apolune they were fitted to give
## [derived]: the one that brings the coelliptic sequence (CSI at the
## first apolune, CDH half an orbit on, coelliptic below the CSM) to TPI
## at the time the PDI PAD gave, floored at P12's orbit.
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
## [param tgo] the last cycle's time to go; the engine's [param thrust_n]
## and [param isp_s], the ascent engine's if not given. Returns {"u" (the
## thrust direction), "tgo" (s), "vg" (the velocity still to be gained,
## inertial, m/s)}.
static func steer(r: Vector3, v: Vector3, radius: float, rdot: float, plane: Vector3, mass: float,
		tg: Dictionary, tgo: float, thrust_n: float = -1.0, isp_s: float = -1.0) -> Dictionary:
	var aps := SpacecraftData.section("aps")
	var ve := (isp_s if isp_s > 0.0 else float(aps["isp_s"])) * Units.G0
	var at := (thrust_n if thrust_n > 0.0 else float(aps["thrust_n"])) / mass
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


## The aborts' insertion targets (P70, P71): targets()' radius and radial
## rate above [param base], and the horizontal velocity of the orbit whose
## apolune phases the LM for TPI at GET [param t_tpi] (above). [param r]
## and [param v] are the LM's position and velocity at GET [param now],
## [param csm_r] and [param csm_v] the CSM's, [param mass] the LM's and
## [param thrust_n] and [param isp_s] its engine's. The model: the ascent
## to insertion takes the rocket equation's time to go, the LM flying at
## the mean of its horizontal velocity and the insertion's; then half an
## orbit to CSI at apolune, which raises perilune to the coelliptic
## height (coelliptic_dh_m below the CSM's mean radius), half that orbit
## to CDH, and coelliptic flight to TPI, where the CSM leads by the angle
## that puts it tpi_elevation_deg above the LM. The apolune lies between
## P12's (the floor) and abort_apolune_max_alt_m, and leaves
## abort_coelliptic_min_s of coelliptic flight at least. Returns
## targets() with "vh" the solved velocity and "ra" the apolune's radius;
## P12's without a TPI time.
static func abort_targets(r: Vector3, v: Vector3, csm_r: Vector3, csm_v: Vector3, base: float, now: float,
		t_tpi: float, mass: float, thrust_n: float, isp_s: float) -> Dictionary:
	var d := SpacecraftData.section("ascent_guidance")
	var tg := targets(base)
	var ra_min := base + float(d["insertion_apolune_alt_m"])
	tg["ra"] = ra_min
	if t_tpi <= now:
		return tg
	var mu := Bodies.MU_MOON
	var plane := csm_r.cross(csm_v).normalized()
	var a_c := 1.0 / (2.0 / csm_r.length() - csm_v.length_squared() / mu)
	var n_c := sqrt(mu / (a_c * a_c * a_c))
	var rg := SpacecraftData.section("rendezvous_guidance")
	var r_coel := a_c - float(rg["coelliptic_dh_m"])
	var n3 := sqrt(mu / (r_coel * r_coel * r_coel))
	var e := deg_to_rad(float(rg["tpi_elevation_deg"]))
	# The CSM's lead at TPI: tan E = (a_c cos φ - r_coel) / (a_c sin φ).
	var lead_tpi := acos(clampf(r_coel * cos(e) / a_c, -1.0, 1.0)) - e
	# The CSM's lead now, in its plane, along the LM's motion.
	var rp := (r - plane * r.dot(plane)).normalized()
	var cp := (csm_r - plane * csm_r.dot(plane)).normalized()
	var lead := atan2(rp.cross(cp).dot(plane), rp.dot(cp))
	var vh_now := v.dot(plane.cross(r.normalized()).normalized())
	var r_ins := float(tg["r"])
	var rdot := float(tg["rdot"])
	var tgo := float(steer(r, v, r.length(), v.dot(r.normalized()), plane, mass, tg, 0.0, thrust_n, isp_s)["tgo"])
	var t_left := t_tpi - (now + tgo)
	# [the lead at TPI less the lead the plan brings, the coelliptic time]
	var f := func(ra: float) -> Array:
		var vh := insertion_vh(r_ins, rdot, ra)
		var lead_ins := lead + n_c * tgo - 0.5 * (vh_now + vh) * tgo / (0.5 * (r.length() + r_ins))
		var p1 := TAU * sqrt(pow(0.5 * (r_ins + ra), 3.0) / mu)
		var p2 := TAU * sqrt(pow(0.5 * (ra + r_coel), 3.0) / mu)
		var coel := t_left - 0.5 * (p1 + p2)
		return [lead_ins + (n_c * 0.5 * p1 - PI) + (n_c * 0.5 * p2 - PI) - (n3 - n_c) * coel - lead_tpi, coel]
	var lo := ra_min
	var hi := base + float(d["abort_apolune_max_alt_m"])
	var coel_min := float(d["abort_coelliptic_min_s"])
	for _i in 20:
		if float(f.call(hi)[1]) >= coel_min or hi - lo < 1.0:
			break
		hi = 0.5 * (lo + hi)
	if float(f.call(lo)[0]) >= 0.0:
		return tg
	if float(f.call(hi)[0]) <= 0.0:
		lo = hi
	else:
		for _i in 40:
			var mid := 0.5 * (lo + hi)
			if float(f.call(mid)[0]) < 0.0:
				lo = mid
			else:
				hi = mid
	tg["vh"] = insertion_vh(r_ins, rdot, lo)
	tg["ra"] = lo
	return tg

## Real-Time Computer Complex: the ground trajectory computations Mission
## Control ran for every Apollo maneuver, reduced to what this simulator
## needs. Every solution is found by shooting with the same three-body
## propagator the vehicle flies (Trajectory) and the same burn laws the
## vehicle executes (S-IVB energy cutoff, CMC P40 LVLH-held thrust, LGC P40
## on the DPS's throttle schedule), so a PAD flown as uplinked lands close
## to its target; residuals are what midcourse corrections are for.
##
## A PAD is a Dictionary: {"name", "tig" (GET s), "dv_lvlh" (Vector3, m/s),
## "dv" (m/s), "burn_s", plus solution-specific predictions}.
class_name Rtcc
extends RefCounted

## Integration controls for planning (coarser than flight, still RK4).
const FRAC := 0.01
const MAX_DT := 600.0
## The deepest vacuum perigee, m from the Earth's centre, that earth_return()
## integrates to: a return steeper than that is the conic's, the
## perturbations' kilometres lost in thousands.
const VACUUM_FLOOR := 0.5 * Bodies.R_EARTH


static func sps_mdot() -> float:
	var d := SpacecraftData.section("sps")
	return float(d["thrust_n"]) / (float(d["isp_s"]) * Units.G0)


static func burn_time(mass: float, dv: float) -> float:
	var d := SpacecraftData.section("sps")
	var ve := float(d["isp_s"]) * Units.G0
	return mass * (1.0 - exp(-absf(dv) / ve)) / sps_mdot()


## Fly a CMC P40 burn on [param traj]: SPS thrust held along the
## [param dv_lvlh] direction in the moving LVLH frame until its magnitude
## has been gained (the same law the CMC flies). Returns the mass after.
static func simulate_sps_burn(traj: Trajectory, mass: float, dv_lvlh: Vector3, dt: float = 0.5) -> float:
	var d := SpacecraftData.section("sps")
	var f := float(d["thrust_n"])
	var mdot := sps_mdot()
	var u := dv_lvlh.normalized()
	var left := dv_lvlh.length()
	var m := mass
	while left > 1e-4:
		var acc := f / m
		var h := minf(dt, left / acc)
		var a := lvlh_to_inertial(traj, u) * acc
		traj.step(h, PackedFloat64Array([a.x, a.y, a.z]))
		left -= acc * h
		m -= mdot * h
	return m


## Fly an LGC P40 burn on the DPS on [param traj]: thrust held along the
## [param dv_lvlh] direction in the moving LVLH frame, at the start
## throttle for the first p40_start_s and the burn throttle after, until
## its magnitude has been gained (the law the LGC flies). Returns the mass
## after.
static func simulate_dps_burn(traj: Trajectory, mass: float, dv_lvlh: Vector3, dt: float = 0.5) -> float:
	var d := SpacecraftData.section("dps")
	var f := float(d["thrust_n"])
	var mdot := f / (float(d["isp_s"]) * Units.G0)
	var t_start := float(d["p40_start_s"])
	var u := dv_lvlh.normalized()
	var left := dv_lvlh.length()
	var m := mass
	var t := 0.0
	while left > 1e-4:
		var k := float(d["p40_start_throttle"]) if t < t_start else float(d["p40_throttle"])
		var acc := f * k / m
		var h := minf(dt, left / acc)
		if t < t_start:
			h = minf(h, t_start - t)
		var a := lvlh_to_inertial(traj, u) * acc
		traj.step(h, PackedFloat64Array([a.x, a.y, a.z]))
		left -= acc * h
		m -= mdot * k * h
		t += h
	return m


## How long an LGC P40 burn of [param dv] on the DPS lasts, s.
static func dps_burn_time(mass: float, dv: float) -> float:
	var d := SpacecraftData.section("dps")
	var ve := float(d["isp_s"]) * Units.G0
	var mdot := float(d["thrust_n"]) / ve
	var t_start := float(d["p40_start_s"])
	var m_start := mass - mdot * float(d["p40_start_throttle"]) * t_start
	var dv_start := ve * log(mass / m_start)
	if absf(dv) <= dv_start:
		return mass * (1.0 - exp(-absf(dv) / ve)) / (mdot * float(d["p40_start_throttle"]))
	return t_start + m_start * (1.0 - exp(-(absf(dv) - dv_start) / ve)) / (mdot * float(d["p40_throttle"]))


static func lvlh_to_inertial(traj: Trajectory, dv_lvlh: Vector3) -> Vector3:
	return Trajectory.lvlh_basis(traj.pos(), traj.vel()) * dv_lvlh


static func inertial_to_lvlh(traj: Trajectory, dv: Vector3) -> Vector3:
	return Trajectory.lvlh_basis(traj.pos(), traj.vel()).inverse() * dv


# --- lunar approach -----------------------------------------------------------

## Coast [param traj] (modified) until the closest approach to the Moon or
## [param t_max]. Returns {"t", "rp" (conic pericynthion radius), "f" (rp
## signed by the relative orbit's sense about the lunar orbit normal:
## negative = retrograde, the Apollo free-return sense), "impact"}.
static func lunar_approach(traj: Trajectory, t_max: float) -> Dictionary:
	var box := {"prev": INF, "closing": false}
	var n := Bodies.moon_normal()
	var stop := func(tr: Trajectory) -> bool:
		var m := tr.moon_state_rel()
		var d := Vector3(m[0], m[1], m[2]).length()
		if tr.primary == "earth" and tr.radius() < Bodies.R_EARTH:
			return true
		if d < Bodies.R_MOON:
			return true
		var passed: bool = d > box["prev"] and box["closing"] and d < 2.0 * Bodies.MOON_SOI
		box["closing"] = d < box["prev"]
		box["prev"] = d
		return passed
	var reached := traj.coast_until(stop, t_max, MAX_DT, FRAC)
	var rel := traj.moon_state_rel()
	var c := Trajectory.conic_of(rel, Bodies.MU_MOON)
	var h: Vector3 = c["h"]
	var sgn := -1.0 if h.dot(n) < 0.0 else 1.0
	var rnow := Vector3(rel[0], rel[1], rel[2]).length()
	var rp: float = minf(c["rp"], rnow)
	return {"t": traj.t, "rp": rp, "f": sgn * rp, "impact": rp < Bodies.R_MOON, "reached": reached}


## Coast until Earth-relative distance falls below 100,000 km or
## [param t_max]; then the vacuum perigee: integrated on in vacuum where the
## Earth is oblate (vacuum_perigee()), the conic's otherwise. Returns {"t"
## (at 100,000 km), "rp", "f"} with f signed by the sense of the
## Earth-relative orbit about the lunar orbit normal.
static func earth_return(traj: Trajectory, t_max: float) -> Dictionary:
	var near := func(tr: Trajectory) -> bool:
		return tr.primary == "earth" and tr.radius() < 1.0e8
	var reached := traj.coast_until(near, t_max, MAX_DT, FRAC)
	var st := traj.earth_state()
	var c := Trajectory.conic_of(st, Bodies.MU_EARTH)
	var h: Vector3 = c["h"]
	var sgn := -1.0 if h.dot(Bodies.moon_normal()) < 0.0 else 1.0
	var rp: float = c["rp"]
	if reached and Bodies.perturbed and rp > VACUUM_FLOOR:
		rp = vacuum_perigee(traj, rp)
	return {"t": traj.t, "rp": rp, "f": sgn * rp, "reached": reached}


## The perigee radius an inbound [param traj] (Earth-relative) comes to in
## vacuum, integrated on through the Earth's oblateness, whose pull on the
## way in moves it kilometres from the conic's (4.7 km lower on the entry
## start phase's return, with the Moon's and the Sun's). Below the surface
## too, through the same field, so a return's perigee runs on smoothly
## through the altitudes the CM could not reach; [param rp_conic], the
## conic's, where the path goes below VACUUM_FLOOR first. [param traj] is
## left where it was.
static func vacuum_perigee(traj: Trajectory, rp_conic: float) -> float:
	var tr := traj.clone()
	var rr_was := tr.radial_rate()
	while rr_was < 0.0:
		var r_was := tr.radius()
		var dt := clampf(FRAC * r_was / maxf(tr.speed(), 1.0), 0.5, MAX_DT)
		tr.step(dt)
		if tr.radius() < VACUUM_FLOOR:
			return rp_conic
		var rr := tr.radial_rate()
		if rr >= 0.0:
			# Through perigee within the step, where the radial rate runs
			# near straight: the parabola's bottom.
			return r_was - rr_was * rr_was * dt / (2.0 * (rr - rr_was))
		rr_was = rr
	return tr.radius()


# --- root finding -------------------------------------------------------------

## Scan x over [a, b] in [param n] samples for a sign change of g(x), then
## refine with bisection/secant. Returns x, or NAN when no bracket exists.
## g may return NAN for an invalid sample (e.g. the Moon was never
## reached); brackets touching such samples are skipped.
static func solve_scan(g: Callable, a: float, b: float, n: int, tol: float, max_iter: int = 40) -> float:
	var xs: Array[float] = []
	var gs: Array[float] = []
	for i in n + 1:
		var x := lerpf(a, b, float(i) / n)
		xs.append(x)
		gs.append(float(g.call(x)))
		if i > 0 and not is_nan(gs[i]) and not is_nan(gs[i - 1]) and signf(gs[i]) != signf(gs[i - 1]):
			return _refine(g, xs[i - 1], xs[i], gs[i - 1], gs[i], tol, max_iter)
	return NAN


static func _refine(g: Callable, x0: float, x1: float, g0: float, g1: float, tol: float, max_iter: int) -> float:
	# Illinois (regula falsi with halving): robust and fast.
	var side := 0
	for _i in max_iter:
		var x := x1 - g1 * (x1 - x0) / (g1 - g0)
		if absf(x1 - x0) < tol:
			return x
		var gx := float(g.call(x))
		if signf(gx) == signf(g1):
			x1 = x; g1 = gx
			if side == -1:
				g0 *= 0.5
			side = -1
		else:
			x0 = x; g0 = gx
			if side == 1:
				g1 *= 0.5
			side = 1
		if absf(gx) < 1.0:
			return x
	return x1 - g1 * (x1 - x0) / (g1 - g0)


# --- TLI --------------------------------------------------------------------------

## Coast [param traj] (modified) into the Moon's sphere of influence, or to
## its closest approach short of it, or to [param t_max]. Returns where the
## approach's osculating hyperbola about the Moon aims: {"t", "b" (the B
## vector, inertial, m: from the Moon's centre to where the incoming
## asymptote crosses the plane through it normal to the asymptote), "s"
## (the asymptote's direction), "v_inf" (m/s), "reached"}.
static func lunar_bplane(traj: Trajectory, t_max: float) -> Dictionary:
	var box := {"prev": INF, "closing": false}
	var stop := func(tr: Trajectory) -> bool:
		var m := tr.moon_state_rel()
		var d := sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
		var passed: bool = d > box["prev"] and box["closing"]
		box["closing"] = d < box["prev"]
		box["prev"] = d
		return d < Bodies.MOON_SOI or passed or (tr.primary == "earth" and tr.radius() < Bodies.R_EARTH)
	var reached := traj.coast_until(stop, t_max, MAX_DT, FRAC)
	var m := traj.moon_state_rel()
	var r := Vector3(m[0], m[1], m[2])
	var v := Vector3(m[3], m[4], m[5])
	var h := r.cross(v)
	var energy := v.length_squared() / 2.0 - Bodies.MU_MOON / r.length()
	if energy <= 0.0:
		return {"t": traj.t, "b": r - v.normalized() * r.dot(v.normalized()), "s": v.normalized(), "v_inf": v.length(),
			"reached": reached}
	var v_inf := sqrt(2.0 * energy)
	var e_vec := v.cross(h) / Bodies.MU_MOON - r.normalized()
	var e := e_vec.length()
	var p_hat := e_vec / e
	var q_hat := h.normalized().cross(p_hat)
	var s_hat := (p_hat + q_hat * sqrt(e * e - 1.0)) / e
	return {"t": traj.t, "b": s_hat.cross(h.normalized()) * (h.length() / v_inf), "s": s_hat, "v_inf": v_inf,
		"reached": reached}


## The B vector that passes the Moon at [param rp] from its centre, on the
## retrograde (free-return) side, for the approach [param bp]: in the plane
## that holds the landing site [param site_mf] at GET [param t_land], or
## without a site, in the plane of the Moon's orbit.
static func bplane_target(bp: Dictionary, rp: float, site_mf: Vector3, t_land: float) -> Vector3:
	var s: Vector3 = bp["s"]
	var v_inf: float = bp["v_inf"]
	var b := rp * sqrt(1.0 + 2.0 * Bodies.MU_MOON / (rp * v_inf * v_inf))
	var n := Bodies.moon_normal()
	var dir := s.cross(n).normalized()
	if site_mf != Vector3.ZERO:
		var site := site_at(site_mf, t_land).normalized()
		dir = (site - s * site.dot(s)).normalized()
	# The orbit's normal lies along B x S: against the Moon's orbit normal.
	if dir.cross(s).dot(n) > 0.0:
		dir = -dir
	return dir * b


## Solve the S-IVB's TLI ignition time and yaw so the stack reaches the
## Moon with the requested pericynthion altitude on the retrograde
## (free-return) side, in the plane that holds the landing site
## [param site_mf] at GET [param t_land] (or, without a site, the Moon's
## orbit plane): the aim a midcourse correction then keeps. The ignition
## time sets where the trajectory passes the Moon along its orbit, the yaw
## how far out of it. [param traj] is the parking-orbit state (Earth
## primary), not modified.
## [simplified: Apollo 11's IU shaped the transfer with iterative guidance
## and turned its plane 1.3 degrees at TLI. The energy-cutoff law turns it
## with a fixed yaw, 5.0 degrees for Apollo 11: a yaw held through the
## burn does less for the aim than the IU's steering, and with no Earth
## oblateness the parking orbit has not turned the 0.8 degrees west it did
## in flight before TLI, which puts the Moon 0.9 degrees out of its plane.]
static func plan_tli(traj: Trajectory, stack_mass: float, sivb_prop: float, energy: float,
		pericynthion_alt: float, earliest: float, site_mf: Vector3 = Vector3.ZERO, t_land: float = 0.0) -> Dictionary:
	var rp := Bodies.R_MOON + pericynthion_alt
	var period: float = traj.conic()["period"]
	var start := traj.clone()
	start.coast_to(earliest, 30.0, FRAC)
	var site := site_at(site_mf, t_land).normalized() if site_mf != Vector3.ZERO else Vector3.ZERO
	var fly := func(tig: float, yaw: float) -> Trajectory:
		var tr := start.clone()
		tr.coast_to(tig, 30.0, FRAC)
		Sivb.simulate_burn(tr, stack_mass, sivb_prop, energy, yaw)
		return tr
	# The B vector's miss from the aim, along the B-plane's T axis (in the
	# Moon's orbit plane) and its R axis.
	var miss := func(tig: float, yaw: float) -> Vector2:
		var bp := lunar_bplane(fly.call(tig, yaw), tig + 6.0 * 86400.0)
		if not bp["reached"]:
			return Vector2(NAN, NAN)
		var d: Vector3 = (bp["b"] as Vector3) - bplane_target(bp, rp, site_mf, t_land)
		var sh: Vector3 = bp["s"]
		var t_hat := sh.cross(Bodies.moon_normal()).normalized()
		return Vector2(d.dot(t_hat), d.dot(sh.cross(t_hat)))
	# The misses at the closest approach itself: the signed pericynthion,
	# and how far the orbit's plane passes from the site (or the B-plane's
	# R miss without one), m.
	var actual := func(tig: float, yaw: float) -> Vector2:
		var tr: Trajectory = fly.call(tig, yaw)
		var ap := lunar_approach(tr, tig + 6.0 * 86400.0)
		if not ap["reached"]:
			return Vector2(NAN, NAN)
		var off := 0.0
		if site != Vector3.ZERO:
			var rel := tr.moon_state_rel()
			off = Vector3(rel[0], rel[1], rel[2]).cross(Vector3(rel[3], rel[4], rel[5])).normalized().dot(site) * rp
		else:
			off = (miss.call(tig, yaw) as Vector2).y
		return Vector2(float(ap["f"]) + rp, off)
	# The window: where the miss along T changes sign, flying in plane.
	var tig := solve_scan(func(x: float) -> float: return (miss.call(x, 0.0) as Vector2).x,
		earliest, earliest + 1.5 * period, 18, 0.5)
	if is_nan(tig):
		return {}
	# Then the ignition time and the yaw together: first onto the B-plane
	# aim, whose misses run nearly straight with them, then onto the
	# closest approach's own.
	var yaw := 0.0
	for stage in 2:
		var f: Callable = miss if stage == 0 else actual
		var tol := 5000.0 if stage == 0 else 500.0
		for _i in 10:
			var m0: Vector2 = f.call(tig, yaw)
			if is_nan(m0.x):
				return {}
			if absf(m0.x) < tol and absf(m0.y) < tol:
				break
			var mt: Vector2 = ((f.call(tig + 0.5, yaw) as Vector2) - m0) / 0.5
			var my: Vector2 = ((f.call(tig, yaw + 0.002) as Vector2) - m0) / 0.002
			var det := mt.x * my.y - my.x * mt.y
			if absf(det) < 1e-9:
				return {}
			tig += clampf((-m0.x * my.y + m0.y * my.x) / det, -120.0, 120.0)
			yaw += clampf((-mt.x * m0.y + mt.y * m0.x) / det, -0.05, 0.05)
	var tr := start.clone()
	tr.coast_to(tig, 30.0, FRAC)
	var v0 := tr.speed()
	var left := Sivb.simulate_burn(tr, stack_mass, sivb_prop, energy, yaw)
	var cutoff := tr.t
	var dv := tr.speed() - v0
	var ap := lunar_approach(tr, tig + 6.0 * 86400.0)
	return {"name": "TLI", "tig": tig, "energy": energy, "yaw": yaw, "cutoff": cutoff,
		"dv": dv, "sivb_prop_left": left,
		"pericynthion_get": ap["t"], "pericynthion_alt": float(ap["rp"]) - Bodies.R_MOON}


# --- midcourse corrections ---------------------------------------------------

## Minimum-norm LVLH correction at [param tig] driving metric
## [param target_kind] ("moon": signed pericynthion; "earth": signed
## perigee) to [param target_f]. Toward the Moon with a landing site
## [param site_mf], it also keeps the approach's plane on the site at GET
## [param t_land], out of plane (Y) as need be. Returns a PAD; dv 0 when not
## required.
static func plan_mcc(traj: Trajectory, mass: float, tig: float, target_kind: String, target_f: float, t_max: float,
		site_mf: Vector3 = Vector3.ZERO, t_land: float = 0.0) -> Dictionary:
	var at := traj.clone()
	at.coast_to(tig, 60.0, FRAC)
	var plane := target_kind == "moon" and site_mf != Vector3.ZERO
	var site := site_at(site_mf, t_land).normalized() if plane else Vector3.ZERO
	var rp := absf(target_f)
	# The misses: the signed pericynthion (or perigee), and how far the
	# approach's plane passes from the site, m at the pericynthion's radius.
	var metric := func(dv_lvlh: Vector3) -> Vector2:
		var tr := at.clone()
		if dv_lvlh.length() > 1e-6:
			simulate_sps_burn(tr, mass, dv_lvlh)
		var res := lunar_approach(tr, t_max) if target_kind == "moon" else earth_return(tr, t_max)
		var off := 0.0
		if plane:
			var rel := tr.moon_state_rel()
			off = Vector3(rel[0], rel[1], rel[2]).cross(Vector3(rel[3], rel[4], rel[5])).normalized().dot(site) * rp
		return Vector2(float(res["f"]) - target_f, off)
	var dv := Vector3.ZERO
	var err: Vector2 = metric.call(dv)
	var tol := 20000.0 if target_kind == "moon" else 5000.0
	for _i in 8:
		if absf(err.x) < tol and absf(err.y) < tol:
			break
		var h := 0.5
		var gx: Vector2 = ((metric.call(dv + Vector3(h, 0, 0)) as Vector2) - err) / h
		var gy: Vector2 = ((metric.call(dv + Vector3(0, h, 0)) as Vector2) - err) / h
		var gz: Vector2 = ((metric.call(dv + Vector3(0, 0, h)) as Vector2) - err) / h
		# The least ΔV that zeroes the misses: J^T (J J^T)^-1 (-err).
		var a := gx.x * gx.x + gy.x * gy.x + gz.x * gz.x
		var b := gx.x * gx.y + gy.x * gy.y + gz.x * gz.y
		var c := gx.y * gx.y + gy.y * gy.y + gz.y * gz.y
		var step := Vector3.ZERO
		if plane:
			var det := a * c - b * b
			if absf(det) < 1e-9:
				break
			var lx := (-err.x * c + err.y * b) / det
			var ly := (err.x * b - err.y * a) / det
			step = Vector3(gx.x * lx + gx.y * ly, gy.x * lx + gy.y * ly, gz.x * lx + gz.y * ly)
		else:
			if a < 1e-9:
				break
			step = Vector3(gx.x, gy.x, gz.x) * (-err.x / a)
		if step.length() > 150.0:
			step = step.normalized() * 150.0
		dv += step
		err = metric.call(dv)
	return {"name": "MCC", "tig": tig, "dv_lvlh": dv, "dv": dv.length(),
		"burn_s": burn_time(mass, dv.length()), "residual_m": err.x, "plane_residual_m": err.y}


# --- lunar orbit ---------------------------------------------------------------

## LOI-1: retrograde External ΔV centred on pericynthion, sized (by
## bisection on the finite burn) to leave an orbit with the requested
## apolune. Apollo 11: 60 x 170 nmi. Given a landing site
## [param site_mf] (Moon-fixed) and landing time [param t_land], an
## out-of-plane component turns the orbit's plane about the burn point to
## pass over the site at the landing time.
static func plan_loi(traj: Trajectory, mass: float, apolune_alt: float, site_mf: Vector3 = Vector3.ZERO, t_land: float = 0.0) -> Dictionary:
	var tr := traj.clone()
	var ap := lunar_approach(tr, traj.t + 5.0 * 86400.0)
	if tr.primary != "moon" or ap["impact"]:
		return {}
	var t_peri: float = ap["t"]
	var r := tr.radius()
	var v := tr.speed()
	var ra := Bodies.R_MOON + apolune_alt
	var box := {"dvy": 0.0}
	var outcome := func(dvm: float) -> Dictionary:
		var dv := Vector3(-dvm, box["dvy"], 0)
		var tb := burn_time(mass, dv.length())
		var t2 := traj.clone()
		t2.coast_to(t_peri - tb / 2.0, 60.0, FRAC)
		simulate_sps_burn(t2, mass, dv)
		var c := t2.conic()
		var ra_now: float = c["ra"] if c["ra"] != INF else 1.0e12
		var h: Vector3 = c["h"]
		return {"tig": t_peri - tb / 2.0, "ra": ra_now, "rp": c["rp"], "tb": tb, "h": h.normalized()}
	# ra(dv) falls monotonically from unbound (too little ΔV) to the burn
	# radius (circular): bisect between those ends.
	var size := func() -> float:
		var lo := maxf(v - sqrt(2.0 * Bodies.MU_MOON / r), 0.0)
		var hi := (v - sqrt(Bodies.MU_MOON / r)) * 1.1
		for _i in 40:
			var mid := (lo + hi) / 2.0
			if float(outcome.call(mid)["ra"]) > ra:
				lo = mid
			else:
				hi = mid
			if hi - lo < 0.05:
				break
		return (lo + hi) / 2.0
	var dv: float = size.call()
	if site_mf != Vector3.ZERO:
		# Secant on the out-of-plane ΔV until the plane holds the site at the
		# landing time, re-sizing the retrograde part as it goes.
		var s := site_at(site_mf, t_land).normalized()
		var y0 := 0.0
		var f0: float = (outcome.call(dv)["h"] as Vector3).dot(s)
		var y1 := 10.0 * -signf(f0)
		for _i in 8:
			box["dvy"] = y1
			var f1: float = (outcome.call(dv)["h"] as Vector3).dot(s)
			if absf(f1) < 1e-7 or absf(f1 - f0) < 1e-12:
				break
			var y2 := y1 - f1 * (y1 - y0) / (f1 - f0)
			y0 = y1
			f0 = f1
			y1 = y2
		box["dvy"] = y1
		dv = size.call()
	var res: Dictionary = outcome.call(dv)
	var dv_lvlh := Vector3(-dv, box["dvy"], 0)
	return {"name": "LOI-1", "tig": res["tig"], "dv_lvlh": dv_lvlh, "dv": dv_lvlh.length(),
		"burn_s": res["tb"], "ha": float(res["ra"]) - Bodies.R_MOON, "hp": float(res["rp"]) - Bodies.R_MOON}


## Circularization (LOI-2 or any orbit trim) at the next periapsis or
## apoapsis ([param at]).
static func plan_circularize(traj: Trajectory, mass: float, at: String = "periapsis") -> Dictionary:
	var tr := traj.clone()
	var mu := Bodies.mu_of(tr.primary)
	var box := {"prev": tr.radial_rate()}
	var apsis := func(t2: Trajectory) -> bool:
		var rr := t2.radial_rate()
		var hit: bool = (at == "periapsis" and box["prev"] < 0.0 and rr >= 0.0) or (at == "apoapsis" and box["prev"] > 0.0 and rr <= 0.0)
		box["prev"] = rr
		return hit
	tr.coast_until(apsis, traj.t + 2.0 * float(traj.conic()["period"]), 20.0, 0.002)
	var dv := sqrt(mu / tr.radius()) - tr.speed()
	var tb := burn_time(mass, dv)
	return {"name": "CIRC", "tig": tr.t - tb / 2.0, "dv_lvlh": Vector3(dv, 0, 0), "dv": absf(dv), "burn_s": tb}


## LOI-2 as Apollo 11 flew it: at the next periapsis of [param traj]'s orbit
## about the Moon (the LOI-1 orbit's pericynthion), the in-plane ΔV that
## leaves an orbit with apocynthion and pericynthion radii [param ra] and
## [param rp], the burn point on its way down to the new pericynthion, some
## 90° on. Apollo 11 targeted 65.7 by 53.7 nmi, noncircular, for the Moon's
## field to round it toward 60 nmi by the rendezvous. Centred on the
## periapsis; its ΔV has a component down (+Z).
static func plan_loi2(traj: Trajectory, mass: float, ra: float, rp: float) -> Dictionary:
	var tr := traj.clone()
	var mu := Bodies.mu_of(tr.primary)
	var box := {"prev": tr.radial_rate()}
	var peri := func(t2: Trajectory) -> bool:
		var rr := t2.radial_rate()
		var hit: bool = box["prev"] < 0.0 and rr >= 0.0
		box["prev"] = rr
		return hit
	tr.coast_until(peri, traj.t + 2.0 * float(traj.conic()["period"]), 20.0, 0.002)
	var r := tr.radius()
	var v := sqrt(mu * (2.0 / r - 2.0 / (ra + rp)))
	var cos_g := clampf(sqrt(mu * 2.0 * ra * rp / (ra + rp)) / (r * v), -1.0, 1.0)
	var sin_g := -sqrt(1.0 - cos_g * cos_g)
	var vr := tr.radial_rate()
	var vh := sqrt(maxf(0.0, tr.speed() * tr.speed() - vr * vr))
	var dv := Vector3(v * cos_g - vh, 0.0, vr - v * sin_g)
	var tb := burn_time(mass, dv.length())
	return {"name": "LOI-2", "tig": tr.t - tb / 2.0, "dv_lvlh": dv, "dv": dv.length(), "burn_s": tb}


## The state (m, m/s, doubles) on the ellipse about a body of [param mu]
## with semi-major axis [param a] and eccentricity [param e], its
## periapsis toward [param pdir] and its normal [param h] (the motion
## right-handed about it), at mean anomaly [param m].
static func conic_state(mu: float, a: float, e: float, pdir: Vector3, h: Vector3, m: float) -> PackedFloat64Array:
	var ea := m
	for _i in 30:
		ea -= (ea - e * sin(ea) - m) / (1.0 - e * cos(ea))
	var nu := 2.0 * atan2(sqrt(1.0 + e) * sin(ea / 2.0), sqrt(1.0 - e) * cos(ea / 2.0))
	var p := a * (1.0 - e * e)
	var r := p / (1.0 + e * cos(nu))
	var k := sqrt(mu / p)
	var x := pdir.normalized()
	var y := h.normalized().cross(x)
	var cr := r * cos(nu)
	var sr := r * sin(nu)
	var cv := -k * sin(nu)
	var sv := k * (e + cos(nu))
	return PackedFloat64Array([x.x * cr + y.x * sr, x.y * cr + y.y * sr, x.z * cr + y.z * sr,
		x.x * cv + y.x * sv, x.y * cv + y.y * sv, x.z * cv + y.z * sv])


## The mean anomaly at true anomaly [param nu] on an ellipse of
## eccentricity [param e].
static func mean_anomaly(nu: float, e: float) -> float:
	var ea := 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))
	return ea - e * sin(ea)


## Coast [param traj] (modified) to its next periapsis, within a
## revolution and a half. Returns its altitude above the primary, m (the
## conic's there).
static func next_periapsis_alt(traj: Trajectory) -> float:
	var box := {"prev": traj.radial_rate()}
	var peri := func(t2: Trajectory) -> bool:
		var rr := t2.radial_rate()
		var hit: bool = box["prev"] < 0.0 and rr >= 0.0
		box["prev"] = rr
		return hit
	traj.coast_until(peri, traj.t + 1.5 * float(traj.conic()["period"]), 20.0, 0.002)
	return float(traj.conic()["rp"]) - Bodies.radius_of(traj.primary)


# --- the landing site ------------------------------------------------------------

## The landing site, [param site_mf] in the Moon-fixed frame, relative to
## the Moon at GET [param t] (inertial axes), m.
static func site_at(site_mf: Vector3, t: float) -> Vector3:
	return Bodies.moon_fixed(t) * site_mf


## The normal of a retrograde lunar orbit whose ground track reaches its
## northernmost (or southernmost) point over the site at GET [param t]:
## the plane stays over the site for revolutions either side.
static func site_orbit_normal(site_mf: Vector3, t: float) -> Vector3:
	var s := site_at(site_mf, t).normalized()
	var w := Bodies.moon_pole(t)
	var e := s - w * s.dot(w)
	if e.length() < 1e-9:
		return -w
	var lat := asin(clampf(s.dot(w), -1.0, 1.0))
	return (e.normalized() * sin(lat) - w * cos(lat)).normalized()


## The time [param traj] passes direction [param dir] (a unit vector near
## its orbit plane), on the first pass after GET [param after]. Coasts
## [param traj] (modified) to just past it.
static func time_at_direction(traj: Trajectory, dir: Vector3, after: float) -> float:
	if traj.t < after:
		traj.coast_to(after, 60.0, FRAC)
	var h := traj.pos().cross(traj.vel()).normalized()
	# Signed angle still to go to dir, in the direction of motion.
	var ahead := func(t2: Trajectory) -> float:
		var p := t2.pos().normalized()
		return atan2(p.cross(dir).dot(h), p.dot(dir))
	var box := {"prev": float(ahead.call(traj))}
	var passed := func(t2: Trajectory) -> bool:
		var a: float = ahead.call(t2)
		var hit: bool = box["prev"] > 0.0 and a <= 0.0 and box["prev"] - a < PI
		box["prev"] = a
		return hit
	traj.coast_until(passed, traj.t + 1.5 * float(traj.conic()["period"]), 20.0, 0.002)
	# The crossing lies within the last step: back up to it at the orbit's
	# angular rate.
	var a: float = ahead.call(traj)
	return traj.t + a / (traj.speed() / traj.radius())


## Size a retrograde DOI at [param at] (the state at ignition): the
## bisection on the finite burn, flown on the DPS as the LGC's P40 flies it,
## that puts the next pericynthion at [param pericynthion_alt]. Returns
## {"dv", "hp", "hp_get", "hp_pos" (where, relative to the Moon)}, or {}
## when even a burn that would reach the surface can't.
static func size_doi(at: Trajectory, mass: float, pericynthion_alt: float) -> Dictionary:
	var outcome := func(dvm: float) -> Array:
		var t2 := at.clone()
		simulate_dps_burn(t2, mass, Vector3(-dvm, 0, 0))
		return [next_periapsis_alt(t2), t2.t, t2.pos()]
	var lo := 0.0
	var hi := 0.5 * float(at.speed())
	if float(outcome.call(lo)[0]) < pericynthion_alt:
		return {}
	for _i in 60:
		var mid := (lo + hi) / 2.0
		if float(outcome.call(mid)[0]) > pericynthion_alt:
			lo = mid
		else:
			hi = mid
		if hi - lo < 0.001:
			break
	var dv := (lo + hi) / 2.0
	var res: Array = outcome.call(dv)
	return {"dv": dv, "hp": res[0], "hp_get": res[1], "hp_pos": res[2]}


## Descent orbit insertion for a landing at [param site_mf] (Moon-fixed):
## the LM's retrograde burn half a revolution before powered descent, on
## the pass that lands nearest GET [param t_land], and no earlier than
## [param earliest]. The burn is sized for a pericynthion
## [param pericynthion_alt] above the site (Apollo 11: 50,000 ft), and
## placed for the pericynthion to fall [param pdi_range] (ground range)
## before the site, where powered descent begins: about opposite it, but
## the Moon's field turns the descent orbit's apsides by degrees in its
## half revolution, so the burn is moved until the pericynthion does fall
## there. Powered descent lasts [param t_descent]. Returns a PAD with the
## pericynthion's height above the site ("hp") and time ("hp_get"), and
## the landing time it plans for ("land_get").
static func plan_doi(traj: Trajectory, mass: float, pericynthion_alt: float, site_mf: Vector3, t_land: float,
		pdi_range: float, t_descent: float, earliest: float) -> Dictionary:
	if traj.primary != "moon":
		return {}
	# size_doi works above the reference sphere.
	var site_h := site_mf.length() - Bodies.R_MOON
	var period := float(traj.conic()["period"])
	var t_l := maxf(t_land, earliest + period + t_descent)
	var base := traj.clone()
	if t_l - t_descent - 2.0 * period > base.t:
		base.coast_to(t_l - t_descent - 2.0 * period, 60.0, FRAC)
	var res := {"dv": 22.0}
	var t_doi := 0.0
	# How far past the point opposite the burn the pericynthion falls, rad.
	var lag := 0.0
	for _i in 8:
		var h := base.pos().cross(base.vel()).normalized()
		# The PDI point: the site where it stands at PDI, pdi_range back.
		var s := site_at(site_mf, t_l - t_descent)
		var sp := (s - h * s.dot(h)).normalized()
		var pdi_dir := sp.rotated(h, -pdi_range / Bodies.R_MOON)
		# The pass over the DOI point about half a revolution and the
		# descent before the landing.
		var probe := base.clone()
		t_doi = time_at_direction(probe, -pdi_dir.rotated(h, -lag), maxf(earliest, t_l - t_descent - period))
		var tb := dps_burn_time(mass, float(res["dv"]))
		var at := base.clone()
		at.coast_to(t_doi - tb / 2.0, 60.0, FRAC)
		res = size_doi(at, mass, pericynthion_alt + site_h)
		if res.is_empty():
			return {}
		var hp_dir: Vector3 = (res["hp_pos"] as Vector3).normalized()
		var off := atan2(pdi_dir.cross(hp_dir).dot(h), pdi_dir.dot(hp_dir))
		lag += off
		var t_next := float(res["hp_get"]) + t_descent
		var done := absf(t_next - t_l) < 1.0 and absf(off) * Bodies.R_MOON < 100.0
		t_l = t_next
		if done:
			break
	var dv := float(res["dv"])
	var tb2 := dps_burn_time(mass, dv)
	return {"name": "DOI", "tig": t_doi - tb2 / 2.0, "dv_lvlh": Vector3(-dv, 0, 0), "dv": dv,
		"burn_s": tb2, "hp": float(res["hp"]) - site_h, "hp_get": res["hp_get"], "land_get": t_l}


# --- lunar liftoff -----------------------------------------------------------------

## Fly the LGC's P12 on [param tr] (modified): the ascent stage sitting on
## the descent stage at ignition, turning with the Moon, and [param mass]
## its mass. The ascent engine starts; the LM lifts off when its thrust
## beats its weight (Dynamics' rule); it rises vertically, then flies
## AscentGuidance to [param tg] in the plane whose normal is
## [param plane], the steering held for the last seconds, and cuts off at
## the engine's tail-off lead. [simplified: the thrust axis turns toward
## the command at the DAP's rate limit.] [param tr] ends where the
## tail-off does. Returns {"mass" (after), "cutoff" (GET)}.
static func simulate_ascent(tr: Trajectory, mass: float, plane: Vector3, tg: Dictionary, dt: float = 0.1) -> Dictionary:
	var aps := SpacecraftData.section("aps")
	var d := SpacecraftData.section("ascent_guidance")
	var thrust := float(aps["thrust_n"])
	var mdot := thrust / (float(aps["isp_s"]) * Units.G0)
	var max_turn := deg_to_rad(float(d["auto_rate_dps"])) * dt
	var spot := Bodies.moon_fixed(tr.t).transposed() * tr.pos()
	var m := mass
	var level := 0.0
	var on := true
	var landed := true
	var lift_s := 0.0
	var x := tr.pos().normalized()
	var step := "vertical"
	var tgo := 0.0
	var cutoff := -1.0
	var u := x
	# An engine that can't lift the LM, or never reaches insertion, gives up.
	var t_end := tr.t + 1200.0
	while (on or level >= 1e-3) and tr.t < t_end:
		var up := tr.pos().normalized()
		if not landed:
			# The LGC: vertical rise, guidance, hold, cutoff.
			if step == "vertical" and tr.radial_rate() >= float(d["vertical_rise_hdot_mps"]):
				step = "ascent"
			u = up
			if step != "vertical" and on:
				var g := AscentGuidance.steer(tr.pos(), tr.vel(), tr.radius(), tr.radial_rate(), plane, m, tg, tgo)
				tgo = g["tgo"]
				if step == "ascent" and tgo < float(d["hold_s"]):
					step = "hold"
				if step == "ascent":
					u = g["u"]
				if tgo <= float(aps["tau_off_s"]):
					on = false
					cutoff = tr.t
			if step == "hold" or not on:
				u = x
		# The engine, then the LM.
		var tau := float(aps["tau_on_s"]) if on else float(aps["tau_off_s"])
		level += ((1.0 if on else 0.0) - level) * (1.0 - exp(-dt / tau))
		var f := thrust * level
		if landed:
			var gr := Bodies.MU_MOON / (tr.radius() * tr.radius())
			lift_s = lift_s + dt if f * x.dot(up) / m > gr * Dynamics.LIFTOFF_MARGIN else 0.0
			if lift_s < Dynamics.LIFTOFF_S:
				var p := Bodies.moon_fixed(tr.t + dt) * spot
				tr.set_state("moon", tr.t + dt, p, Bodies.moon_omega(tr.t + dt).cross(p))
				x = p.normalized()
				m -= mdot * level * dt
				continue
			landed = false
		var turn := x.angle_to(u)
		if turn > 1e-9:
			x = x.slerp(u, minf(max_turn / turn, 1.0)).normalized()
		var a := x * (f / m)
		tr.step(dt, PackedFloat64Array([a.x, a.y, a.z]))
		m -= mdot * level * dt
	return {"mass": m, "cutoff": cutoff}


## The lunar liftoff time: flying P12 (simulate_ascent) from the LM's spot
## [param site_mf] (Moon-fixed, on the ground) on an ascent stage of
## [param mass], the time that has the CSM ([param csm]) lead the LM by
## [param phase_deg] in its orbit at insertion, in the first window at or
## after GET [param earliest]. Returns a PAD: {"name": "ASCENT", "tig",
## "insertion_get", "phase_deg", "vh" and "hdot" (P12's targets), "xrng"
## (the LM's distance from the CSM's plane at liftoff), "ha", "hp" (the
## insertion orbit's apsides above the site), "burn_s", "dv", "prop_kg"
## (the APS propellant used)}, or {} without the CSM in lunar orbit.
static func plan_liftoff(site_mf: Vector3, mass: float, csm: Trajectory, phase_deg: float,
		earliest: float) -> Dictionary:
	if csm.primary != "moon":
		return {}
	var plane := csm.pos().cross(csm.vel()).normalized()
	var site_r := site_mf.length()
	var tg := AscentGuidance.targets(site_r)
	var cm := site_mf.normalized() * (site_r + Dynamics.lm_cm_height("lm_ascent"))
	var target := deg_to_rad(phase_deg)
	# The CSM gains on the spot at its orbital rate, and the Moon's turning.
	var rate := csm.speed() / csm.radius() - Bodies.moon_omega(csm.t).dot(plane)
	var base := csm.clone()
	if earliest > base.t:
		base.coast_to(earliest, 60.0, FRAC)
	var fly := func(tig: float) -> Dictionary:
		var tr := Trajectory.new()
		var p := Bodies.moon_fixed(tig) * cm
		tr.set_state("moon", tig, p, Bodies.moon_omega(tig).cross(p))
		var res := simulate_ascent(tr, mass, plane, tg)
		var c := base.clone()
		c.coast_to(tr.t, 60.0, FRAC)
		var l := tr.pos().normalized()
		var k := c.pos().normalized()
		res["tr"] = tr
		res["phase"] = atan2(l.cross(k).dot(plane), l.dot(k))
		return res
	var tig := earliest
	var res: Dictionary = fly.call(tig)
	if float(res["cutoff"]) < 0.0:
		return {}
	# The first window: the phase is short of the target by less than a turn.
	tig += fposmod(target - float(res["phase"]), TAU) / rate
	res = fly.call(tig)
	for _i in 6:
		var err := wrapf(float(res["phase"]) - target, -PI, PI)
		if absf(err) < 1e-5:
			break
		tig -= err / rate
		res = fly.call(tig)
	var ins: Trajectory = res["tr"]
	var c := ins.conic()
	var ve := float(SpacecraftData.section("aps")["isp_s"]) * Units.G0
	var p0 := Bodies.moon_fixed(tig) * cm
	return {"name": "ASCENT", "tig": tig, "insertion_get": ins.t, "phase_deg": rad_to_deg(float(res["phase"])),
		"vh": tg["vh"], "hdot": tg["rdot"], "xrng": p0.dot(plane), "ha": float(c["ra"]) - site_r,
		"hp": float(c["rp"]) - site_r, "burn_s": float(res["cutoff"]) - tig, "dv": ve * log(mass / float(res["mass"])),
		"prop_kg": mass - float(res["mass"])}


# --- rendezvous --------------------------------------------------------------------

## The rendezvous plan from [param lm] and [param csm] (both now, the LM in
## orbit after insertion, of [param mass]): CSI at the LM's next apolune,
## and the coelliptic sequence (Rendezvous) that brings TPI at GET
## [param t_tpi], with the CSM [param e_tpi] above the LM and a transfer of
## [param wt] (radians), flown impulsively. Returns a PAD for CSI: {"name":
## "CSI", "tig", "dv_lvlh", "dv", "burn_s" (on the LM RCS's +X jets),
## "cdh_get", "cdh_dv", "dh", "tpi_get", "tpi_dv", "intercept_get",
## "braking_dv" (the speed the LM arrives at relative to the CSM),
## "total_dv"}, or {} without a solution.
static func plan_rendezvous(lm: Trajectory, csm: Trajectory, mass: float, t_tpi: float, e_tpi: float,
		wt: float) -> Dictionary:
	if lm.primary != "moon" or csm.primary != "moon":
		return {}
	var l := lm.clone()
	Rendezvous.next_apsis(l, 60.0, "apo")
	var t_csi := l.t
	var csi := Rendezvous.plan_csi(lm, csm, t_csi, t_tpi, e_tpi)
	if not csi["ok"]:
		return {}
	var dv_csi := float(csi["dv"])
	# Fly the plan: CSI, CDH half a revolution on, and TPI.
	var c := csm.clone()
	c.coast_to(t_csi)
	var fwd := l.pos().cross(l.vel()).normalized().cross(l.pos().normalized())
	for i in 3:
		l.s[3 + i] += fwd[i] * dv_csi
	var t_cdh := float(csi["cdh_get"])
	l.coast_to(t_cdh)
	c.coast_to(t_cdh)
	var cdh: Vector3 = Rendezvous.cdh(l, c)["dv"]
	for i in 3:
		l.s[3 + i] += cdh[i]
	l.coast_to(t_tpi)
	c.coast_to(t_tpi)
	var t_arrive := Rendezvous.arrival(c, wt)
	var tpi := Rendezvous.transfer(l, c, t_arrive)
	var tpi_dv := (tpi["dv"] as Vector3).length()
	var d := SpacecraftData.section("lm_rcs")
	var accel := 2.0 * float(d["x_jets"]) * float(d["jet_thrust_n"]) / mass
	return {"name": "CSI", "tig": t_csi, "dv_lvlh": Vector3(dv_csi, 0.0, 0.0), "dv": absf(dv_csi),
		"burn_s": absf(dv_csi) / accel, "cdh_get": t_cdh, "cdh_dv": cdh.length(), "dh": csi["dh"],
		"tpi_get": t_tpi, "tpi_dv": tpi_dv, "intercept_get": t_arrive, "braking_dv": tpi["rel_v"],
		"total_dv": absf(dv_csi) + cdh.length() + tpi_dv + float(tpi["rel_v"])}


# --- TEI ------------------------------------------------------------------------

## Transearth injection from lunar orbit: prograde External ΔV of
## [param dv] m/s, ignition time solved so the return perigee (vacuum)
## sits at [param perigee_alt] - the entry corridor (≈ -6.5° at EI for
## 37 km). Either sense of return is accepted; the earliest wins.
static func plan_tei(traj: Trajectory, mass: float, dv: float, perigee_alt: float, earliest: float) -> Dictionary:
	var period: float = traj.conic()["period"]
	var start := traj.clone()
	start.coast_to(earliest, 30.0, FRAC)
	var tb := burn_time(mass, dv)
	var best := {}
	for sgn in [1.0, -1.0]:
		var target: float = sgn * (Bodies.R_EARTH + perigee_alt)
		var eval := func(tig: float) -> float:
			var tr := start.clone()
			tr.coast_to(tig, 30.0, FRAC)
			simulate_sps_burn(tr, mass, Vector3(dv, 0, 0))
			var er := earth_return(tr, tig + 6.0 * 86400.0)
			return float(er["f"]) - target if er["reached"] else NAN
		var tig := solve_scan(eval, earliest + tb, earliest + tb + period, 24, 0.05)
		if not is_nan(tig) and (best.is_empty() or tig < float(best["tig"])):
			var tr := start.clone()
			tr.coast_to(tig, 30.0, FRAC)
			simulate_sps_burn(tr, mass, Vector3(dv, 0, 0))
			var er := earth_return(tr, tig + 6.0 * 86400.0)
			best = {"name": "TEI", "tig": tig, "dv_lvlh": Vector3(dv, 0, 0), "dv": dv, "burn_s": tb,
				"perigee_alt": float(er["rp"]) - Bodies.R_EARTH, "sense": sgn, "target_f": target}
	return best


## PAD text as CAPCOM would read it up.
static func pad_text(pad: Dictionary) -> String:
	if pad.is_empty():
		return "NO SOLUTION"
	var dv: Vector3 = pad.get("dv_lvlh", Vector3.ZERO)
	return "%s PAD: TIG %s  N81 DVX %+.1f DVY %+.1f DVZ %+.1f ft/s  DVT %.1f ft/s  BURN %.0f s" % [
		pad["name"], Units.hms(float(pad["tig"])), dv.x / Units.FT, dv.y / Units.FT, dv.z / Units.FT,
		float(pad.get("dv", dv.length())) / Units.FT, float(pad.get("burn_s", 0.0))]

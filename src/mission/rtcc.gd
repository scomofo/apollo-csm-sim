## Real-Time Computer Complex: the ground trajectory computations Mission
## Control ran for every Apollo maneuver, reduced to what this simulator
## needs. Every solution is found by shooting with the same three-body
## propagator the vehicle flies (Trajectory) and the same burn laws the
## vehicle executes (S-IVB energy cutoff, CMC P40 LVLH-held thrust), so a PAD flown
## as uplinked lands close to its target; residuals are what midcourse
## corrections are for.
##
## A PAD is a Dictionary: {"name", "tig" (GET s), "dv_lvlh" (Vector3, m/s),
## "dv" (m/s), "burn_s", plus solution-specific predictions}.
class_name Rtcc
extends RefCounted

## Integration controls for planning (coarser than flight, still RK4).
const FRAC := 0.01
const MAX_DT := 600.0


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


## Coast until Earth-relative distance falls below 100,000 km (then use the
## conic perigee) or [param t_max]. Returns {"t", "rp", "f"} with f signed
## by the sense of the Earth-relative orbit about the lunar orbit normal.
static func earth_return(traj: Trajectory, t_max: float) -> Dictionary:
	var near := func(tr: Trajectory) -> bool:
		return tr.primary == "earth" and tr.radius() < 1.0e8
	var reached := traj.coast_until(near, t_max, MAX_DT, FRAC)
	var st := traj.earth_state()
	var c := Trajectory.conic_of(st, Bodies.MU_EARTH)
	var h: Vector3 = c["h"]
	var sgn := -1.0 if h.dot(Bodies.moon_normal()) < 0.0 else 1.0
	return {"t": traj.t, "rp": c["rp"], "f": sgn * float(c["rp"]), "reached": reached}


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

## Solve the S-IVB TLI ignition time so the stack reaches the Moon with the
## requested pericynthion altitude on the retrograde (free-return) side.
## [param traj] is the parking-orbit state (Earth primary), not modified.
static func plan_tli(traj: Trajectory, stack_mass: float, sivb_prop: float, energy: float,
		pericynthion_alt: float, earliest: float) -> Dictionary:
	var target := -(Bodies.R_MOON + pericynthion_alt)
	var period: float = traj.conic()["period"]
	var start := traj.clone()
	start.coast_to(earliest, 30.0, FRAC)
	var eval := func(tig: float) -> float:
		var tr := start.clone()
		tr.coast_to(tig, 30.0, FRAC)
		Sivb.simulate_burn(tr, stack_mass, sivb_prop, energy)
		var ap := lunar_approach(tr, tig + 6.0 * 86400.0)
		return float(ap["f"]) - target if ap["reached"] else NAN
	var tig := solve_scan(eval, earliest, earliest + 1.5 * period, 18, 0.05)
	if is_nan(tig):
		return {}
	var tr := start.clone()
	tr.coast_to(tig, 30.0, FRAC)
	var v0 := tr.speed()
	var left := Sivb.simulate_burn(tr, stack_mass, sivb_prop, energy)
	var cutoff := tr.t
	var dv := tr.speed() - v0
	var ap := lunar_approach(tr, tig + 6.0 * 86400.0)
	return {"name": "TLI", "tig": tig, "energy": energy, "cutoff": cutoff,
		"dv": dv, "sivb_prop_left": left,
		"pericynthion_get": ap["t"], "pericynthion_alt": float(ap["rp"]) - Bodies.R_MOON}


# --- midcourse corrections ---------------------------------------------------

## Minimum-norm LVLH (X, Z) correction at [param tig] driving metric
## [param target_kind] ("moon": signed pericynthion; "earth": signed
## perigee) to [param target_f]. Returns a PAD; dv 0 when not required.
static func plan_mcc(traj: Trajectory, mass: float, tig: float, target_kind: String, target_f: float, t_max: float) -> Dictionary:
	var at := traj.clone()
	at.coast_to(tig, 60.0, FRAC)
	var metric := func(dv_lvlh: Vector3) -> float:
		var tr := at.clone()
		if dv_lvlh.length() > 1e-6:
			simulate_sps_burn(tr, mass, dv_lvlh)
		var res := lunar_approach(tr, t_max) if target_kind == "moon" else earth_return(tr, t_max)
		return float(res["f"]) - target_f
	var dv := Vector3.ZERO
	var err: float = metric.call(dv)
	var tol := 20000.0 if target_kind == "moon" else 5000.0
	for _i in 6:
		if absf(err) < tol:
			break
		var h := 0.5
		var gx: float = (float(metric.call(dv + Vector3(h, 0, 0))) - err) / h
		var gz: float = (float(metric.call(dv + Vector3(0, 0, h))) - err) / h
		var g2 := gx * gx + gz * gz
		if g2 < 1e-9:
			break
		var step := Vector3(gx, 0, gz) * (-err / g2)
		if step.length() > 150.0:
			step = step.normalized() * 150.0
		dv += step
		err = metric.call(dv)
	return {"name": "MCC", "tig": tig, "dv_lvlh": dv, "dv": dv.length(),
		"burn_s": burn_time(mass, dv.length()), "residual_m": err}


# --- lunar orbit ---------------------------------------------------------------

## LOI-1: retrograde External ΔV centred on pericynthion, sized (by
## bisection on the finite burn) to leave an orbit with the requested
## apolune. Apollo 11: 60 x 170 nmi.
static func plan_loi(traj: Trajectory, mass: float, apolune_alt: float) -> Dictionary:
	var tr := traj.clone()
	var ap := lunar_approach(tr, traj.t + 5.0 * 86400.0)
	if tr.primary != "moon" or ap["impact"]:
		return {}
	var t_peri: float = ap["t"]
	var r := tr.radius()
	var v := tr.speed()
	var ra := Bodies.R_MOON + apolune_alt
	var outcome := func(dvm: float) -> Dictionary:
		var tb := burn_time(mass, dvm)
		var t2 := traj.clone()
		t2.coast_to(t_peri - tb / 2.0, 60.0, FRAC)
		simulate_sps_burn(t2, mass, Vector3(-dvm, 0, 0))
		var c := t2.conic()
		var ra_now: float = c["ra"] if c["ra"] != INF else 1.0e12
		return {"tig": t_peri - tb / 2.0, "ra": ra_now, "rp": c["rp"], "tb": tb}
	# ra(dv) falls monotonically from unbound (too little ΔV) to the burn
	# radius (circular): bisect between those ends.
	var lo := maxf(v - sqrt(2.0 * Bodies.MU_MOON / r), 0.0)
	var hi := (v - sqrt(Bodies.MU_MOON / r)) * 1.1
	var res: Dictionary = {}
	for _i in 40:
		var mid := (lo + hi) / 2.0
		res = outcome.call(mid)
		if float(res["ra"]) > ra:
			lo = mid
		else:
			hi = mid
		if hi - lo < 0.05:
			break
	var dv := (lo + hi) / 2.0
	res = outcome.call(dv)
	return {"name": "LOI-1", "tig": res["tig"], "dv_lvlh": Vector3(-dv, 0, 0), "dv": dv,
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

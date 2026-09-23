## The LM's rendezvous with the CSM, targeted as the LGC's P32 to P35
## target it and as the RTCC plans it: Apollo's coelliptic sequence.
##   CSI  a horizontal burn, sized so that after CDH the CSM stands at the
##        TPI elevation above the LM at the TPI time
##   CDH  half a revolution on, at the next apsis (CSI comes at one):
##        onto an orbit parallel to the CSM's, a constant height below it
##   TPI  when the CSM stands at that elevation: the transfer that meets
##        the CSM after it has flown the transfer angle (130°)
##   TPM  midcourse corrections, aimed at the same meeting again
## Every trajectory is flown on the propagator (Trajectory); the burns are
## impulsive [simplified: P41 flies them as finite burns, and the next
## program targets from where they left the LM].
class_name Rendezvous
extends RefCounted


## [param b]'s position less [param a]'s (at the same time, about the
## same body), m, taken in doubles.
static func rel_pos(a: Trajectory, b: Trajectory) -> Vector3:
	return Vector3(b.s[0] - a.s[0], b.s[1] - a.s[1], b.s[2] - a.s[2])


## [param b]'s velocity less [param a]'s, m/s.
static func rel_vel(a: Trajectory, b: Trajectory) -> Vector3:
	return Vector3(b.s[3] - a.s[3], b.s[4] - a.s[4], b.s[5] - a.s[5])


## The CSM's elevation seen from the LM: the line of sight's angle above
## the LM's local horizontal, measured from the way the LM flies, 0 to π
## (past π/2 the CSM is behind it).
static func elevation(lm: Trajectory, csm: Trajectory) -> float:
	var los := rel_pos(lm, csm)
	var up := lm.pos().normalized()
	var v := lm.vel()
	var fwd := (v - up * v.dot(up)).normalized()
	return atan2(los.dot(up), los.dot(fwd))


## Coast [param tr] (modified) to its next apsis, at least [param min_s]
## on: "apo" where the radial rate turns down, "peri" where it turns up,
## or either.
static func next_apsis(tr: Trajectory, min_s: float, kind: String = "") -> void:
	var t0 := tr.t
	var box := {"prev": tr.radial_rate()}
	var stop := func(t2: Trajectory) -> bool:
		var rr := t2.radial_rate()
		var down: bool = box["prev"] > 0.0 and rr <= 0.0
		var up: bool = box["prev"] < 0.0 and rr >= 0.0
		box["prev"] = rr
		return t2.t - t0 >= min_s and ((down and kind != "peri") or (up and kind != "apo"))
	tr.coast_until(stop, t0 + min_s + 1.5 * float(tr.conic()["period"]), 20.0)
	# Back up to where the radial rate is nought: it changes at the radial
	# acceleration, gravity less the centrifugal.
	var r := tr.radius()
	var rdot := tr.radial_rate()
	var rdd := (tr.speed() * tr.speed() - rdot * rdot) / r - Bodies.mu_of(tr.primary) / (r * r)
	if absf(rdd) > 1e-9:
		tr.step(-rdot / rdd)


## The coelliptic maneuver (CDH) at [param lm]'s point: the ΔV (inertial)
## that puts the LM on an orbit parallel to [param csm]'s (the CSM's state
## at the same time), a constant height below it. The height is the CSM's
## orbit's radius where it passes over the LM, less the LM's. The LM's new
## orbit has the CSM's semi-major axis less that height, and the CSM's
## radial velocity there, scaled by (a_csm / a_lm)^1.5. Returns {"dv",
## "dh"}.
static func cdh(lm: Trajectory, csm: Trajectory) -> Dictionary:
	var mu := Bodies.mu_of(csm.primary)
	var s := csm.s
	var rc := csm.radius()
	var v2 := s[3] * s[3] + s[4] * s[4] + s[5] * s[5]
	var rv := s[0] * s[3] + s[1] * s[4] + s[2] * s[5]
	var a_c := 1.0 / (2.0 / rc - v2 / mu)
	var k := v2 - mu / rc
	var ev := Vector3(k * s[0] - rv * s[3], k * s[1] - rv * s[4], k * s[2] - rv * s[5]) / mu
	var e := ev.length()
	var hc := csm.pos().cross(csm.vel()).normalized()
	var u := lm.pos().normalized()
	var p := a_c * (1.0 - e * e)
	var cos_f := u.dot(ev) / e if e > 1e-9 else 1.0
	var sin_f := ev.cross(u).dot(hc) / e if e > 1e-9 else 0.0
	var r_l := lm.radius()
	var dh := p / (1.0 + e * cos_f) - r_l
	var a_l := a_c - dh
	var vr := sqrt(mu / p) * e * sin_f * pow(a_c / a_l, 1.5)
	var vh := sqrt(maxf(mu * (2.0 / r_l - 1.0 / a_l) - vr * vr, 0.0))
	# The new velocity less the old, in doubles: Vector3's floats would lose
	# a tenth of a mm/s of 1.6 km/s, and TPI's geometry metres of it.
	var l := lm.s
	var up := [l[0] / r_l, l[1] / r_l, l[2] / r_l]
	var h := [l[1] * l[5] - l[2] * l[4], l[2] * l[3] - l[0] * l[5], l[0] * l[4] - l[1] * l[3]]
	var hn := sqrt(h[0] * h[0] + h[1] * h[1] + h[2] * h[2])
	var fwd := [(h[1] * up[2] - h[2] * up[1]) / hn, (h[2] * up[0] - h[0] * up[2]) / hn,
		(h[0] * up[1] - h[1] * up[0]) / hn]
	var dv := Vector3.ZERO
	for i in 3:
		dv[i] = up[i] * vr + fwd[i] * vh - l[3 + i]
	return {"dv": dv, "dh": dh}


## One trial of CSI: [param lm] and [param csm] at CSI, the LM given
## [param dv] (m/s) along its local horizontal, then CDH half its new
## orbit's period on, both coasted on to GET [param t_tpi]. Returns {"e"
## (the CSM's elevation then, NAN if CDH comes after it), "cdh_get",
## "cdh_dv", "dh"}. [Half a period, not the apsis found by coasting: when
## CSI all but circularizes the orbit, its apsides are too shallow to find,
## and CDH's time would jump from one trial to the next.]
static func _csi_trial(lm: Trajectory, csm: Trajectory, dv: float, t_tpi: float) -> Dictionary:
	var l := lm.clone()
	var c := csm.clone()
	var u := l.pos().normalized()
	var fwd := l.pos().cross(l.vel()).normalized().cross(u)
	for i in 3:
		l.s[3 + i] += fwd[i] * dv
	l.coast_to(l.t + 0.5 * float(l.conic()["period"]))
	c.coast_to(l.t)
	var d := cdh(l, c)
	var dvc: Vector3 = d["dv"]
	for i in 3:
		l.s[3 + i] += dvc[i]
	var t_cdh := l.t
	if t_tpi <= t_cdh:
		return {"e": NAN, "cdh_get": t_cdh, "cdh_dv": dvc, "dh": d["dh"]}
	l.coast_to(t_tpi)
	c.coast_to(t_tpi)
	return {"e": elevation(l, c), "cdh_get": t_cdh, "cdh_dv": dvc, "dh": d["dh"]}


## CSI (P32): the horizontal ΔV at GET [param t_csi] (m/s, posigrade
## positive) that, with CDH half a revolution on, has the CSM stand
## [param e_tpi] (radians) above the LM at GET [param t_tpi]. Secant from
## the ΔV that would circularize the orbit at CSI. Returns {"dv",
## "cdh_get", "cdh_dv" (inertial, predicted), "dh", "ok"}.
static func plan_csi(lm: Trajectory, csm: Trajectory, t_csi: float, t_tpi: float, e_tpi: float) -> Dictionary:
	var l := lm.clone()
	l.coast_to(t_csi)
	var c := csm.clone()
	c.coast_to(t_csi)
	var rdot := l.radial_rate()
	var vh := sqrt(maxf(l.speed() * l.speed() - rdot * rdot, 0.0))
	var x0 := sqrt(Bodies.mu_of(l.primary) / l.radius()) - vh
	var x1 := x0 + 0.5
	var f0 := float(_csi_trial(l, c, x0, t_tpi)["e"]) - e_tpi
	var res := _csi_trial(l, c, x1, t_tpi)
	var f1 := float(res["e"]) - e_tpi
	for _i in 20:
		if is_nan(f1) or is_nan(f0) or absf(f1) < 1e-7 or absf(f1 - f0) < 1e-12:
			break
		var x2 := clampf(x1 - f1 * (x1 - x0) / (f1 - f0), x1 - 5.0, x1 + 5.0)
		x0 = x1
		f0 = f1
		x1 = x2
		res = _csi_trial(l, c, x1, t_tpi)
		f1 = float(res["e"]) - e_tpi
	res["dv"] = x1
	res["ok"] = not is_nan(f1) and absf(f1) < 1e-4
	return res


## The time the CSM comes up to [param e_tpi] elevation (radians) above
## the LM, as the LM closes on it from below: the first after GET
## [param after] and before [param t_max], or -1.
static func tpi_time(lm: Trajectory, csm: Trajectory, e_tpi: float, after: float, t_max: float) -> float:
	var l := lm.clone()
	l.coast_to(after)
	var c := csm.clone()
	c.coast_to(after)
	var f := elevation(l, c) - e_tpi
	if f >= 0.0:
		return -1.0
	var h := 10.0
	while l.t < t_max:
		var l0 := l.clone()
		var c0 := c.clone()
		l.step(h)
		c.step(h)
		var f1 := elevation(l, c) - e_tpi
		if f1 >= 0.0:
			# Secant within the step.
			var a := 0.0
			var b := h
			var fa := f
			var fb := f1
			for _i in 4:
				var m := a - fa * (b - a) / (fb - fa)
				var lm2 := l0.clone()
				var cm2 := c0.clone()
				lm2.step(m)
				cm2.step(m)
				var fm := elevation(lm2, cm2) - e_tpi
				if fm < 0.0:
					a = m
					fa = fm
				else:
					b = m
					fb = fm
			return l0.t + a - fa * (b - a) / (fb - fa)
		f = f1
	return -1.0


## The velocity [param lm] needs to be where [param target] is (the CSM's
## state at GET [param t_arrive]) at that time: Newton on the miss, flown
## on the propagator. Returns {"v" (PackedFloat64Array), "miss" (m)}.
static func intercept(lm: Trajectory, target: Trajectory, t_arrive: float) -> Dictionary:
	var v := PackedFloat64Array([lm.s[3], lm.s[4], lm.s[5]])
	var miss := Vector3.INF
	for _i in 8:
		var end := _fly(lm, v, t_arrive)
		miss = rel_pos(target, end)
		if miss.length() < 0.5:
			break
		var j := Basis()
		for k in 3:
			var dv := v.duplicate()
			dv[k] += 0.01
			j[k] = rel_pos(end, _fly(lm, dv, t_arrive)) / 0.01
		var step := j.inverse() * miss
		for k in 3:
			v[k] -= step[k]
	return {"v": v, "miss": miss.length()}


## [param lm] at its time with velocity [param v], coasted to GET
## [param t] (a copy).
static func _fly(lm: Trajectory, v: PackedFloat64Array, t: float) -> Trajectory:
	var tr := lm.clone()
	for k in 3:
		tr.s[3 + k] = v[k]
	tr.coast_to(t)
	return tr


## The transfer (TPI, or a midcourse correction's) from [param lm] to
## meet [param csm] (at the same time) at GET [param t_arrive]. Returns
## {"dv" (inertial, now), "rel_v" (the speed the LM arrives at relative to
## the CSM, which braking takes out), "miss" (m)}.
static func transfer(lm: Trajectory, csm: Trajectory, t_arrive: float) -> Dictionary:
	var c := csm.clone()
	c.coast_to(t_arrive)
	var sol := intercept(lm, c, t_arrive)
	var v: PackedFloat64Array = sol["v"]
	var end := _fly(lm, v, t_arrive)
	return {"dv": Vector3(v[0] - lm.s[3], v[1] - lm.s[4], v[2] - lm.s[5]),
		"rel_v": rel_vel(c, end).length(), "miss": sol["miss"]}


## The GET at which the CSM, from [param csm], has flown [param wt]
## (radians) of its orbit.
static func arrival(csm: Trajectory, wt: float) -> float:
	return csm.t + wt / TAU * float(csm.conic()["period"])

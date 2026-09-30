## The LM crew at the alignment optical telescope (slice 11a), for the
## tests: Luminary's P52 keyed and marked as a crew does it, and the stars
## they could mark. SimTest's lm_realign(), visible_star_pair(),
## aot_marks() and put_star_in_aot() hand these their test (a SimTest,
## untyped here, since SimTest names this class).
class_name AotCrew
extends RefCounted


## The LM crew's P52 on the AOT (slice 11a), as Luminary 099 has it: V37E52E,
## option 3 (V22), PRO; at V50N25 00015 PRO for the LGC's stars (R56), or
## with [param stars] given ENTER, and each loaded by hand at V01N70 (V21:
## the front detent and the star); for each star PRO at V01N70, PRO at
## V50N18 for the maneuver in AUTO, ENTER once V50N18 is back, PRO at
## V01N71, [param pairs] pairs of marks (marks()) and PRO; PRO at N05,
## PRO at N93 to torque, ENTER at V50N25 00014 for P00. The DAP goes back
## to the mode it was in. Returns {"sad": N05 (deg), "torque": N93 (deg, as
## shown), "stars": the two codes, "get": the GET it torqued at}.
static func realign(st: Variant, stars: Array = [], pairs: int = 1) -> Dictionary:
	var lgc: Lgc = st.rt.lgc()
	var was := int(Bus.get_value("ctl.lm.mode", 1))
	Bus.set_value("ctl.lm.mode", 2)
	st.keys("V37E52E", lgc)
	st.assert_eq(lgc.program, 52, "LGC P52 selected")
	st.keys("V22E3EP", lgc)
	st.assert_eq(lgc.step_name, "acquire", "V50N25 00015")
	st.keys("P" if stars.is_empty() else "E", lgc)
	var codes := []
	for i in 2:
		st.assert_eq(lgc.step_name, "n70", "V01N70 for the %s star" % ["first", "second"][i])
		if not stars.is_empty():
			st.keys("V21E%05dEE" % (LgcAlign.FRONT * 100 + int(stars[i])), lgc)
		codes.append(lgc.align.star())
		st.keys("PP", lgc)   # the attitude that brings it; perform the maneuver
		var there: bool = st.run_until(func() -> bool: return lgc.step_name == "v50n18", 600.0, 1.0, false)
		st.assert_true(there, "the LGC turned the LM to star %d" % codes[i])
		st.keys("EP", lgc)   # there: on to V01N71, and the marks
		marks(st, codes[i], lgc.align.detent(), pairs)
		st.keys("P", lgc)
	st.assert_eq(lgc.step_name, "n05", "V06N05")
	var sad: float = lgc.align.sad_deg
	st.keys("P", lgc)
	var n93: Array = lgc.noun_values(93)
	st.keys("P", lgc)
	var t := SimClock.get_seconds
	st.assert_true(lgc.imu.aligned, "the LGC's platform aligned")
	st.keys("E", lgc)
	st.assert_eq(lgc.program, 0, "P52 done")
	Bus.set_value("ctl.lm.mode", was)
	return {"sad": sad, "torque": Vector3(n93[0], n93[1], n93[2]), "stars": codes, "get": t}


## Two navigation stars the LM's crew could mark now, as their flight
## plans chose them [aid: the test's choice]: clear of the Sun, the Earth
## and the Moon by R56's limits (LgcAlign.clear_stars()), more than
## R56_PAIR_MIN_DEG apart, and each brought into the front detent from
## the attitude before (VECPOINT, as R52 aims) with the middle gimbal under
## 50° (Luminary's KALCMANU takes 60° for gimbal lock); of those pairs,
## the one nearest 90° apart.
static func star_pair(st: Variant) -> Array:
	var lgc: Lgc = st.rt.lgc()
	var axis := Aot.optic_axis(Aot.azimuth(LgcAlign.FRONT))
	var aimed := func(from: Quaternion, code: int) -> Quaternion:
		return (Imu.arc(Basis(from) * axis, Stars.direction(code)) * from).normalized()
	var mga := func(q: Quaternion) -> float:
		return absf(wrapf(lgc.gimbal_angles_of(lgc.imu.attitude(q)).z, -180.0, 180.0))
	var usable := LgcAlign.clear_stars(st.rt.dynamics.lm.traj)
	var best := []
	var best_err := INF
	for a in usable:
		var qa: Quaternion = aimed.call(st.rt.dynamics.lm.attitude.q, a)
		if float(mga.call(qa)) > 50.0:
			continue
		for b in usable:
			var sep := rad_to_deg(Stars.direction(a).angle_to(Stars.direction(b)))
			if b == a or sep <= LgcAlign.R56_PAIR_MIN_DEG or absf(sep - 90.0) >= best_err:
				continue
			if float(mga.call(aimed.call(qa, b))) <= 50.0:
				best_err = absf(sep - 90.0)
				best = [a, b]
	st.assert_false(best.is_empty(), "two stars to mark")
	return best


## The crew's marks through the AOT on star [param code] in detent
## [param detent]: for each of [param pairs], the LM turned until the star
## lies on the Y-line a little above the centre, and MARK Y, then on the
## X-line a little right of it, and MARK X [simplified: the attitude set
## outright and held, not flown there on the ACA].
static func marks(st: Variant, code: int, detent: int, pairs: int = 1) -> void:
	for k in pairs:
		put_star(st, code, detent, Vector2(0.0, 1.0 + k))
		_press(st, "ctl.lm.aot.mark_y")
		put_star(st, code, detent, Vector2(1.0 + k, 0.0))
		_press(st, "ctl.lm.aot.mark_x")


## Turn the LM (its true attitude, the DAP holding it there) so that star
## [param code] lies in detent [param detent]'s field at [param off] (deg
## right and up of the centre, along the reticle's lines).
static func put_star(st: Variant, code: int, detent: int, off: Vector2) -> void:
	var lm: Vehicle = st.rt.dynamics.lm
	var lgc: Lgc = st.rt.lgc()
	var v := Aot.view_axes(detent)
	var q: Quaternion = lm.attitude.q
	var los := (Basis(q) * (v[2] as Vector3)).normalized()
	var centred := (Imu.arc(los, Stars.direction(code)) * q).normalized()
	var right := Basis(centred) * (v[0] as Vector3)
	var up := Basis(centred) * (v[1] as Vector3)
	# Turned about the view's up the star moves right, about its right down.
	var turn := Quaternion(up, deg_to_rad(off.x)) * Quaternion(right, -deg_to_rad(off.y))
	var q2 := (turn * centred).normalized()
	lm.attitude.q = q2
	lm.attitude.omega = Vector3.ZERO
	# The Bus too, which the DAP reads a step behind: else it fires to null
	# the rate it saw before, and a light ascent stage turns hundredths of
	# a degree off the line before the mark is read.
	Bus.set_value("lm.dyn.att_q", q2)
	Bus.set_value("lm.dyn.omega", Vector3.ZERO)
	lgc.hold_q = lgc.imu.attitude(q2)
	lgc.auto_active = false
	st.run(SimClock.FIXED_DT, false)


static func _press(st: Variant, ch: String) -> void:
	Bus.set_value(ch, true)
	st.run(SimClock.FIXED_DT, false)
	Bus.set_value(ch, false)
	st.run(SimClock.FIXED_DT, false)

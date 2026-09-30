## The LM crew at the alignment optical telescope (slice 11a), for the
## tests: Luminary's P52 keyed and marked as a crew does it, and the stars
## they could mark; on the surface P57, the stars sighted with the
## reticle (slice 11b). SimTest's lm_realign(), visible_star_pair(),
## aot_marks(), put_star_in_aot() and surface_align() hand these their
## test (a SimTest, untyped here, since SimTest names this class).
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


## The LM crew's P57 on the surface (slice 11b), as Luminary 099 has it:
## V37E57E; option [param option] at V04N06 (V22) and PRO, for 4 PRO at
## V06N34 on the TALIGN offered (the ascent's TIG) or [param talign];
## technique [param technique] at V05N06 (V22) and PRO. For 1 and 3
## gravity [param gravity] times, V32 at V06N04 between and PRO; PRO at
## V06N22 for a first pass's coarse align; for 2 and 3 each of
## [param stars] loaded at V01N70 (V21) and PRO, PRO at R59's V06N79 for
## its detent, PRO at V01N71 and [param marks] surface marks
## (surface_marks()); PRO at N05; at N93 PRO, or with [param torque]
## false V32; ENTER at V50N25 00014, and for 2 V34 at V06N89 (the site
## from gravity rejected, as Apollo 11's was). Returns {"n04": each
## N04 (deg), "sad": N05 (deg), "torque": N93 (deg, as shown), "detents":
## R59's, "site": N89's site (Moon-fixed) or zero, "get": the GET it
## ended at}.
static func surface_align(st: Variant, option: int = 3, technique: int = 3, stars: Array = [], gravity: int = 1,
		marks: int = 1, torque: bool = true, talign: float = -1.0) -> Dictionary:
	var lgc: Lgc = st.rt.lgc()
	var out := {"n04": [], "sad": -1.0, "torque": Vector3.ZERO, "detents": [], "site": Vector3.ZERO}
	st.keys("V37E57E", lgc)
	st.assert_eq(lgc.program, 57, "LGC P57 selected")
	st.keys("V22E%dEP" % option, lgc)
	if option == 4:
		st.assert_eq(lgc.step_name, "n34", "V06N34: TALIGN")
		if talign >= 0.0:
			var t := [floorf(talign / 3600.0), floorf(fmod(talign, 3600.0) / 60.0), roundf(fmod(talign, 60.0) * 100.0)]
			st.keys("V25E+%05dE+%05dE+%05dE" % t, lgc)
		st.keys("P", lgc)
	st.assert_eq(lgc.step_name, "technique", "V05N06: the technique")
	st.keys("V22E%dEP" % technique, lgc)
	var star_k := 0
	var gravity_left := gravity
	for guard in 40:
		match lgc.step_name:
			"gravity", "coarse":
				var s0: String = lgc.step_name
				var moved: bool = st.run_until(func() -> bool: return lgc.step_name != s0, 600.0, 1.0, false)
				st.assert_true(moved, "the LGC past its %s" % s0)
			"n04":
				out["n04"].append(lgc.surface.n04_deg)
				gravity_left -= 1
				st.keys("V32E" if gravity_left > 0 else "P", lgc)
			"n22":
				st.keys("P", lgc)
			"n70":
				st.keys("V21E%05dEEP" % int(stars[star_k]), lgc)
			"n79_acquire":
				out["detents"].append(lgc.surface.poscode)
				st.keys("P", lgc)
			"n71":
				st.keys("P", lgc)
			"marks":
				surface_marks(st, int(stars[star_k]), int(lgc.surface.aotcode / 100.0), marks)
				star_k += 1
			"n05":
				out["sad"] = lgc.surface.sad_deg
				st.keys("P", lgc)
			"n93":
				var n93: Array = lgc.noun_values(93)
				out["torque"] = Vector3(n93[0], n93[1], n93[2])
				st.keys("P" if torque else "V32E", lgc)
			"check":
				st.keys("E", lgc)
			"n89":
				out["site"] = lgc.surface.site_mf
				st.keys("V34E", lgc)
			_:
				break
		if lgc.program != 57:
			break
	st.assert_eq(lgc.program, 0, "P57 done")
	out["get"] = SimClock.get_seconds
	return out


## The navigation stars the crew could sight from the surface now, as
## their flight plans chose them [aid: the test's choice]: each in the
## first detent R59 tries whose field holds it, not the stowed rear, and
## within 20° of its centre (Apollo 12's crew could not see a star farther
## out, MSC-01855, section 8.6 [published]); the nearest the centre first.
static func surface_stars(st: Variant) -> Array:
	var body := Basis(st.rt.dynamics.lm.attitude.q).transposed()
	var found := []
	for code in Stars.codes():
		var s := body * Stars.direction(code)
		for d in range(1, 7):
			var off := rad_to_deg(s.angle_to(Aot.optic_axis(Aot.azimuth(d))))
			if off < LgcSurfaceAlign.FIELD_HALF_DEG:
				if d != Aot.CL and off < 20.0:
					found.append([off, code])
				break
	found.sort()
	st.assert_false(found.is_empty(), "a star to sight")
	return found.map(func(f: Array) -> int: return int(f[1]))


## The AOT's counter as the crew read it for star [param code] through
## detent [param detent], the LM where it truly sits: the Y-line turned
## onto the star (the cursor), then the spiral (the spiral angle), each to
## a hundredth of a degree [published: the counter's interpolation, the
## ALSJ's AOT page].
static func reticle_readings(st: Variant, code: int, detent: int) -> Vector2:
	var q: Quaternion = st.rt.dynamics.lm.attitude.q
	var cs := Aot.cursor_spiral(Basis(q).transposed() * Stars.direction(code), detent)
	return Vector2(fposmod(snappedf(cs.x, 0.01), 360.0), fposmod(snappedf(cs.y, 0.01), 360.0))


## [param count] surface marks on star [param code] through detent
## [param detent], from V54N71: MARK Y, the counter's readings loaded at
## V06N79 (V21 the cursor, V22 the spiral), V32 for the next and PRO
## after the last.
static func surface_marks(st: Variant, code: int, detent: int, count: int = 1) -> void:
	var lgc: Lgc = st.rt.lgc()
	for k in count:
		st.assert_eq(lgc.step_name, "marks", "V54N71 for mark %d" % (k + 1))
		_press(st, "ctl.lm.aot.mark_y")
		st.assert_eq(lgc.step_name, "n79", "V06N79 for its readings")
		var r := reticle_readings(st, code, detent)
		st.keys("V21E+%05dE" % roundi(r.x * 100.0), lgc)
		st.keys("V22E+%05dE" % roundi(r.y * 100.0), lgc)
		st.keys("V32E" if k < count - 1 else "P", lgc)

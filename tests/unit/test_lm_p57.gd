## Slice 11b (docs/ROADMAP.md, milestone 11): the AOT's reticle and
## Luminary 099's P57 on the surface, apart from a flight. The counter's
## cursor and spiral readings find a star again (SURFSTAR), and R59 reads
## them off the LGC's own view of the star as the reticle does; the knob
## turns the counter. P57 aligns Eagle's platform, knocked off on purpose,
## by gravity and the stored attitude (technique 1: the tilt, not the
## azimuth), by two stars (2: all of it) and by gravity and a star (3),
## with GVDETER's N04, the first pass's N22, R59's detents and the surface
## marks' alarms; option 4 turns REFSMMAT to the site at TALIGN. Eagle's
## P57s on the flight's stars are tests/scenarios/test_lm_surface_alignment.gd.
extends SimTest

## Eagle on the surface, 10 min after the landing.
var _surface := ""


func before_all() -> void:
	build("lunar_surface")
	_surface = JSON.stringify(rt.snapshot())


func _restore() -> Lgc:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_surface)), "")
	return rt.lgc()


func _shows(vn: Array, what: String) -> void:
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], vn, what)


func _press(ch: String) -> void:
	Bus.set_value(ch, true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value(ch, false)
	run(SimClock.FIXED_DT, false)


## The platform turned [param eps] (deg, stable member axes) off REFSMMAT.
func _knock(lgc: Lgc, eps: Vector3) -> void:
	lgc.imu.misalign(lgc.imu.refsmmat, eps * (PI / 180.0))


## The platform's misalignment, deg: its tilt off the local vertical as the
## LM sits, and the rest, about it.
func _tilt_and_azimuth(lgc: Lgc) -> Vector2:
	var m := lgc.imu.misalignment()
	var up := rt.dynamics.lm.traj.pos().normalized()
	var about := m.dot(up)
	return Vector2(rad_to_deg((m - up * about).length()), rad_to_deg(absf(about)))


## Stars the AOT sees from where Eagle sits, two at least.
func _stars_in_view(_lgc: Lgc) -> Array:
	var found := AotCrew.surface_stars(self)
	assert_gt(found.size(), 1, "stars in the detents")
	return found


func test_the_counter_readings_find_the_star_again() -> void:
	for d in [1, 2, 3, 4, 6]:
		var v := Aot.view_axes(d)
		for off in [1.0, 7.5, 18.0, 29.0]:
			for bearing in [0.0, 50.0, 135.0, 222.0, 310.0]:
				var b := deg_to_rad(bearing)
				var toward := (v[1] as Vector3) * cos(b) + (v[0] as Vector3) * sin(b)
				var s := ((v[2] as Vector3) * cos(deg_to_rad(off)) + toward * sin(deg_to_rad(off))).normalized()
				var cs := Aot.cursor_spiral(s, d)
				assert_almost_eq(wrapf(cs.x - bearing, -180.0, 180.0), 0.0, 1e-3, "the cursor: the star's bearing, clockwise from up")
				assert_almost_eq(wrapf(cs.y - cs.x - 12.0 * off, -180.0, 180.0), 0.0, 2e-3, "the spiral: twelve times its distance on")
				var back := LgcSurfaceAlign.surfstar(d, cs.x, cs.y)
				assert_lt(rad_to_deg(back.angle_to(s)), 1e-3, "SURFSTAR finds it again (detent %d, %s° off, %s°)" % [d, off, bearing])
				var r59 := LgcSurfaceAlign.r59_cursor_spiral(s, Aot.azimuth(d))
				assert_almost_eq(wrapf(r59.x - cs.x, -180.0, 180.0), 0.0, 2e-3, "R59's cursor from the LM's X axis and the azimuth")
				assert_almost_eq(wrapf(r59.y - cs.y, -180.0, 180.0), 0.0, 2e-3, "and its spiral")
	var oa := Aot.optic_axis(Aot.azimuth(2))
	assert_eq(LgcSurfaceAlign.r59_cursor_spiral(oa, 0.0), Vector2.ZERO, "on the axis: both zero")
	assert_lt(rad_to_deg(LgcSurfaceAlign.surfstar(2, 0.0, 0.0).angle_to(oa)), 1e-4, "and SURFSTAR puts it there")
	assert_eq(LgcSurfaceAlign.r59_cursor_spiral(-oa, 0.0), Vector2(-1.0, -1.0), "out of the field")


func test_the_reticle_knob_turns_the_counter() -> void:
	_restore()
	var aot: Aot = rt.systems["aot"]
	Bus.set_value("ctl.lm.aot.reticle", 2)
	run(1.0, false)
	assert_almost_eq(float(Bus.get_value("lm.aot.reticle_deg")), Aot.RETICLE_DEG_S[1], 0.05, "fast clockwise")
	Bus.set_value("ctl.lm.aot.reticle", -1)
	run(2.0, false)
	assert_almost_eq(aot.reticle_deg, Aot.RETICLE_DEG_S[1] - 2.0 * Aot.RETICLE_DEG_S[0], 0.05, "slow anticlockwise")
	Bus.set_value("ctl.lm.aot.reticle", -2)
	run(2.0, false)
	assert_almost_eq(aot.reticle_deg, 360.0 - Aot.RETICLE_DEG_S[1] - 2.0 * Aot.RETICLE_DEG_S[0], 0.05, "round past zero")
	Bus.set_value("ctl.lm.aot.reticle", 0)
	var was := aot.reticle_deg
	run(1.0, false)
	assert_eq(aot.reticle_deg, was, "the rocker let go")


func test_p57_needs_the_surface() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	var lgc := rt.lgc()
	keys("V37E57E", lgc)
	assert_eq(lgc.alarm_code, 1520, "no P57 in flight")
	assert_ne(lgc.program, 57)


func test_gravity_and_the_stored_attitude_level_the_platform() -> void:
	var lgc := _restore()
	_knock(lgc, Vector3(0.20, -0.15, 0.10))
	var before := _tilt_and_azimuth(lgc)
	var knock := lgc.imu.misalignment()
	keys("V37E57E", lgc)
	_shows(["04", "06"], "V04N06")
	assert_eq(lgc.noun_values(6), [1.0, 3.0, 0.0], "option 3 offered")
	keys("P", lgc)
	_shows(["05", "06"], "V05N06: the technique")
	assert_eq(lgc.noun_values(6), [10.0, 0.0, 100.0], "00010, technique 0, REFSMMAT's flag and no attitude stored")
	keys("V22E1EP", lgc)
	assert_true(lgc.surface.attitude_stored, "the attitude stored first, from REFSMMAT")
	assert_eq(lgc.step_name, "gravity", "GVDETER")
	assert_false(lgc.imu.aligned, "REFSMMAT's flag cleared")
	assert_true(run_until(func() -> bool: return lgc.step_name == "n04", 300.0, 1.0, false), "V06N04")
	_shows(["06", "04"], "V06N04")
	assert_almost_eq(lgc.surface.n04_deg, 90.0, 1e-3, "nothing to compare with: ACOS of nothing")
	keys("V32E", lgc)
	var t0 := SimClock.get_seconds
	assert_true(run_until(func() -> bool: return lgc.step_name == "n04", 300.0, 1.0, false), "gravity again")
	var took := SimClock.get_seconds - t0
	gut.p("GVDETER took %.0f s; N04 %.3f deg" % [took, lgc.surface.n04_deg])
	assert_between(took, 80.0, 140.0, "two reads of 40 s, and the turns")
	assert_lt(lgc.surface.n04_deg, 0.02, "the same gravity, to the CDUs' counts")
	var up_body := Basis(lgc._true_att()).transposed() * LgcSurfaceAlign.plumb_up(lgc.truth_traj())
	assert_lt(rad_to_deg(lgc.surface.gravity.angle_to(up_body)), 0.01, "up the plumb line, body axes")
	keys("P", lgc)
	_shows(["06", "22"], "the first pass, on the stored attitude: V06N22 for the coarse align")
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.step_name == "n05", 120.0, 1.0, false), "then technique 1's: V06N05")
	# The stored Z leans off the vertical by the knock's tilt about the
	# body's Y axis, where gravity and the body's Z don't.
	var y_body := Basis(lgc._true_att()) * Vector3(0, 1, 0)
	var lean := rad_to_deg(absf(knock.dot(y_body)))
	gut.p("N05 %.3f deg; the knock's tilt about the body's Y %.3f" % [lgc.surface.sad_deg, lean])
	assert_almost_eq(lgc.surface.sad_deg, lean, 0.01, "N05: the angles between the vertical and Z apart by that")
	keys("P", lgc)
	_shows(["06", "93"], "V06N93")
	keys("P", lgc)
	_shows(["50", "25"], "V50N25 00014")
	assert_true(lgc.imu.aligned, "REFSMMAT's flag set")
	keys("E", lgc)
	assert_eq(lgc.program, 0, "P00")
	var after := _tilt_and_azimuth(lgc)
	gut.p("Knocked off %.3f deg tilted and %.3f about the vertical; after, %.4f and %.3f" % [before.x, before.y, after.x, after.y])
	assert_lt(after.x, 0.05, "gravity levels the platform, but for the plumb line's lean off the radius")
	assert_almost_eq(after.y, before.y, 0.01, "but the stored attitude keeps its azimuth")


func test_two_stars_align_the_platform_and_place_the_site() -> void:
	var lgc := _restore()
	var stars := _stars_in_view(lgc)
	# Gravity first (technique 3), which technique 2's site takes.
	surface_align(3, 3, [stars[0]])
	_knock(lgc, Vector3(0.20, -0.15, 0.10))
	var r := surface_align(3, 2, [stars[0], stars[1]], 1, 2)
	gut.p("Two stars %s, detents %s: N05 %.4f, N93 %s; the platform %.4f deg off after; the site from gravity %.0f m from the LM" % [
		[stars[0], stars[1]], r["detents"], r["sad"], r["torque"], rad_to_deg(lgc.imu.misalignment().length()),
		(r["site"] as Vector3).distance_to(Bodies.moon_fixed(SimClock.get_seconds).transposed() * rt.dynamics.lm.traj.pos())])
	assert_eq((r["detents"] as Array).size(), 2, "R59 found each star's detent")
	assert_lt(float(r["sad"]), 0.02, "N05: the counter's hundredths")
	assert_almost_eq(r["torque"], Vector3(0.20, -0.15, 0.10), Vector3.ONE * 0.02, "N93: the platform's knock")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.02, "the platform back on REFSMMAT")
	var here := Bodies.moon_fixed(SimClock.get_seconds).transposed() * rt.dynamics.lm.traj.pos()
	assert_lt((r["site"] as Vector3).distance_to(here), 1000.0, "N89: the site from gravity, within a kilometre")


func test_gravity_and_a_star_after_the_stored_attitude() -> void:
	var lgc := _restore()
	var stars := _stars_in_view(lgc)
	surface_align(3, 2, [stars[0], stars[1]])
	_knock(lgc, Vector3(-0.1, 0.25, 0.05))
	var r := surface_align(3, 3, [stars[0]], 1, 3)
	gut.p("Gravity and star %d: N05 %.4f, N93 %s, the platform %.4f deg off after" % [stars[0], r["sad"], r["torque"],
		rad_to_deg(lgc.imu.misalignment().length())])
	assert_lt(float(r["sad"]), 0.02, "N05")
	assert_almost_eq(r["torque"], Vector3(-0.1, 0.25, 0.05), Vector3.ONE * 0.02,
		"N93: the knock since the attitude was stored, which the first pass kept")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.02, "the platform on REFSMMAT")


func test_the_marks_come_as_aotmark_takes_them_on_the_surface() -> void:
	var lgc := _restore()
	var stars := _stars_in_view(lgc)
	keys("V37E57EPV22E2EP", lgc)
	_shows(["01", "70"], "technique 2 with the attitude stored: straight to R59's V01N70")
	keys("V21E%05dEEP" % int(stars[0]), lgc)
	_shows(["06", "79"], "V06N79: the cursor, the spiral and the detent")
	var d := lgc.surface.poscode
	assert_between(d, 1, 6, "a detent")
	var body := Basis(lgc._true_att()).transposed() * Stars.direction(stars[0])
	var want := Aot.cursor_spiral(body, d)
	assert_almost_eq(wrapf(lgc.surface.cursor - want.x, -180.0, 180.0), 0.0, 0.05, "where the reticle finds it")
	keys("P", lgc)
	_shows(["01", "71"], "V01N71")
	assert_eq(lgc.surface.aotcode, d * 100 + int(stars[0]), "the detent in the code")
	keys("P", lgc)
	_shows(["54", "71"], "V54N71")
	_press("ctl.lm.aot.reject")
	assert_eq(lgc.alarm_code, 115, "nothing to reject: 00115")
	keys("P", lgc)
	assert_eq(lgc.alarm_code, 111, "PRO without a mark: 00111")
	_press("ctl.lm.aot.mark_x")
	_shows(["06", "79"], "a mark: V06N79 for the readings")
	lgc.alarm_code = 0
	_press("ctl.lm.aot.reject")
	assert_eq(lgc.alarm_code, 115, "the only mark can't go")
	for k in LgcSurfaceAlign.MAX_MARKS - 1:
		keys("V32E", lgc)
		_shows(["54", "71"], "V32: another mark")
		_press("ctl.lm.aot.mark_y")
	assert_eq(lgc.surface.marks.size(), LgcSurfaceAlign.MAX_MARKS - 1, "four taken, the fifth waiting")
	lgc.alarm_code = 0
	keys("V32E", lgc)
	assert_eq(lgc.alarm_code, 107, "no sixth: 00107")
	_shows(["06", "79"], "the fifth's readings still wanted")
	_press("ctl.lm.aot.reject")
	assert_eq(lgc.surface.pending, null, "REJECT drops the waiting fifth")
	_press("ctl.lm.aot.reject")
	assert_eq(lgc.surface.marks.size(), LgcSurfaceAlign.MAX_MARKS - 2, "and again, the fourth")


func test_alarms_for_a_technique_without_its_flags_and_a_star_out_of_sight() -> void:
	var lgc := _restore()
	lgc.imu.aligned = false
	lgc.surface.attitude_stored = false
	keys("V37E57EP", lgc)
	assert_eq(lgc.noun_values(6), [10.0, 0.0, 0.0], "neither flag")
	keys("V22E1EP", lgc)
	assert_eq(lgc.alarm_code, 701, "gravity and REFSMMAT without either: 00701")
	_shows(["05", "09"], "V05N09")
	keys("P", lgc)
	_shows(["05", "06"], "back to V05N06")
	keys("V34E", lgc)
	# R59 with the platform known: a star below the horizon is in no field.
	lgc.imu.aligned = true
	var body := Basis(lgc._true_att()).transposed()
	var low := -1
	for code in Stars.codes():
		if (body * Stars.direction(code)).x < -0.5:
			low = code
			break
	keys("V37E57EPV22E2EP", lgc)
	keys("V21E%05dEEP" % low, lgc)
	assert_eq(lgc.alarm_code, 404, "star %d under the LM: 00404" % low)
	_shows(["05", "09"], "V05N09")
	keys("V32E", lgc)
	_shows(["01", "70"], "V32: another star")


func test_option_4_turns_refsmmat_to_the_site_at_talign() -> void:
	var lgc := _restore()
	var was := lgc.imu.refsmmat
	var tig := lgc._now() + 3600.0
	lgc.tig_load = tig
	keys("V37E57EV22E4EP", lgc)
	_shows(["06", "34"], "V06N34")
	assert_almost_eq(float(lgc.noun_values(34)[0]), tig, 0.01, "the ascent's TIG offered")
	keys("P", lgc)
	_shows(["05", "06"], "V05N06")
	var x := Imu.axis(lgc.surface.orientation, 0)
	var lm := Bodies.moon_fixed(tig) * lgc.surface._rls_mf()
	assert_lt(rad_to_deg(x.angle_to(lm)), 1e-3, "X up through the LM at TALIGN")
	var z := Imu.axis(lgc.surface.orientation, 2)
	var h := lgc.csm_nav.pos().cross(lgc.csm_nav.vel())
	assert_lt(absf(rad_to_deg(z.angle_to(h)) - 90.0), 1e-3, "Z across the CSM's orbit's normal")
	var stars := _stars_in_view(lgc)
	keys("V22E3EP", lgc)
	assert_true(run_until(func() -> bool: return lgc.step_name not in ["gravity", "coarse"], 400.0, 1.0, false))
	for guard in 6:
		if lgc.step_name == "n22":
			keys("P", lgc)
			assert_true(run_until(func() -> bool: return lgc.step_name != "coarse", 120.0, 1.0, false))
		if lgc.step_name == "n04":
			keys("P", lgc)
	_shows(["01", "70"], "the first pass done, R59 for the star")
	gut.p("The first pass took REFSMMAT %.3f deg on, to the site an hour later" % rad_to_deg(
		Imu.rotation_vector(lgc.imu.refsmmat * was.transposed()).length()))
	assert_lt(rad_to_deg(Imu.axis(lgc.imu.refsmmat, 0).angle_to(lm)), 1e-3, "REFSMMAT the new orientation")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.05, "and the platform on it, by the stored attitude")

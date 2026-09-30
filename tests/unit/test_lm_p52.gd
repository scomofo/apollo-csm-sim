## Slice 11a (docs/ROADMAP.md, milestone 11): the alignment optical
## telescope's geometry and Luminary 099's P52 on its marks, apart from a
## flight. The AOT's six detents look out 45° from the LM's +X axis, 60°
## apart, the front one in the X-Z plane, each with its reticle's two mark
## planes about its line of sight (OANB and OPTAXIS). The marks follow
## AOTMARK: V54N71 takes either mark, V53 and V52 ask for the pair's other;
## a second mark on one line is alarm 00114, REJECT drops the last mark and
## at once again the rest of its pair (00115 with none), PRO without a
## whole pair is 00111, and a sixth pair 00107. Option 4 orients the
## platform to the landing site at the landing's time. The P52 after
## undocking on the flight's stars is tests/scenarios/test_lm_alignment.gd.
extends SimTest


func _shows(vn: Array, what: String) -> void:
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], vn, what)


func _press(ch: String) -> void:
	Bus.set_value(ch, true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value(ch, false)
	run(SimClock.FIXED_DT, false)


## Eagle undocked, in P52 option 3 on star 25 (Acrux) through the front
## detent, at V54N71 without the maneuver (ENTER at V50N18).
func _to_marks() -> Lgc:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	var lgc := rt.lgc()
	Bus.set_value("ctl.lm.mode", 2)
	keys("V37E52E", lgc)
	_shows(["04", "06"], "V04N06: the option")
	keys("V22E3EP", lgc)
	_shows(["50", "25"], "V50N25 00015: option 3 keeps REFSMMAT")
	keys("E", lgc)
	_shows(["01", "70"], "V01N70: the stars by hand")
	keys("V21E00225EE", lgc)
	assert_eq(int(lgc.noun_values(70)[0]), 225, "N70: the front detent and Acrux")
	keys("P", lgc)
	_shows(["50", "18"], "V50N18")
	keys("E", lgc)
	_shows(["01", "71"], "V01N71")
	keys("P", lgc)
	_shows(["54", "71"], "V54N71: mark X or Y")
	return lgc


func test_the_detents_look_out_45_degrees_off_x_60_apart() -> void:
	var want := {1: -60.0, 2: 0.0, 3: 60.0, 4: 120.0, 5: 180.0, 6: -120.0}
	for d in want:
		assert_almost_eq(wrapf(Aot.azimuth(d) - float(want[d]), -180.0, 180.0), 0.0, 1e-9, "detent %d's azimuth" % d)
		var p := Aot.planes(Aot.azimuth(d))
		var oa: Vector3 = p[0]
		assert_almost_eq(oa.length(), 1.0, 1e-6)
		assert_almost_eq(rad_to_deg(oa.angle_to(Vector3.RIGHT)), 45.0, 1e-4, "45° from +X")
		for n: Vector3 in [p[1], p[2]]:
			assert_almost_eq(n.length(), 1.0, 1e-6, "a mark plane's normal")
			assert_almost_eq(n.dot(oa), 0.0, 1e-6, "the line of sight in the plane")
		assert_almost_eq((p[1] as Vector3).dot(p[2]), 0.0, 1e-6, "the Y-line across the X-line")
	var front := Aot.optic_axis(Aot.azimuth(2))
	assert_almost_eq(front.y, 0.0, 1e-6, "the front detent in the X-Z plane")
	assert_gt(front.z, 0.0, "looking forward")
	var v := Aot.view_axes(2)
	assert_almost_eq((v[0] as Vector3), Vector3(0.0, 1.0, 0.0), Vector3.ONE * 1e-6, "in the front detent the Y-line's plane is the X-Z plane")


func test_the_shortest_turn_is_exact_however_small() -> void:
	var a := Vector3(0.3, -0.5, 0.8).normalized()
	var axis := a.cross(Vector3.UP).normalized()
	# To single precision's resolution: 1e-4° here, a little more near
	# half a turn, where the quaternion's w is small.
	for deg in [0.01, 0.05, 0.2, 10.0, 179.9]:
		var b := a.rotated(axis, deg_to_rad(deg))
		var q := Imu.arc(a, b)
		var tol := 1e-4 if deg < 90.0 else 2e-3
		assert_lt(rad_to_deg((q * a).angle_to(b)), tol, "%s°: onto the target" % deg)
		assert_almost_eq(rad_to_deg(2.0 * atan2(Vector3(q.x, q.y, q.z).length(), absf(q.w))), deg, tol, "the least turn")
		gut.p("%s°: Quaternion(a, b) misses by %.4f°" % [deg, rad_to_deg((Quaternion(a, b) * a).angle_to(b))])
	assert_lt(rad_to_deg((Imu.arc(a, -a) * a).angle_to(-a)), 1e-4, "half a turn")


func test_the_marks_come_as_aotmark_takes_them() -> void:
	var lgc := _to_marks()
	put_star_in_aot(25, 2, Vector2(0.0, 1.0))
	_press("ctl.lm.aot.mark_y")
	_shows(["52", "71"], "MARK Y: V52N71 for the pair's X")
	_press("ctl.lm.aot.mark_y")
	assert_eq(lgc.alarm_code, 114, "a second Y mark in the pair: 00114")
	put_star_in_aot(25, 2, Vector2(1.0, 0.0))
	_press("ctl.lm.aot.mark_x")
	_shows(["54", "71"], "a whole pair: V54N71")
	_press("ctl.lm.aot.reject")
	_shows(["52", "71"], "REJECT drops the last mark, the X")
	_press("ctl.lm.aot.reject")
	_shows(["54", "71"], "and at once again the pair's Y")
	_press("ctl.lm.aot.reject")
	assert_eq(lgc.alarm_code, 115, "nothing to reject: 00115")
	keys("P", lgc)
	assert_eq(lgc.alarm_code, 111, "PRO without a whole pair: 00111")
	assert_eq(lgc.step_name, "marks", "still marking")
	for k in LgcAlign.MAX_PAIRS:
		put_star_in_aot(25, 2, Vector2(0.0, 1.0 + 0.5 * k))
		_press("ctl.lm.aot.mark_y")
		put_star_in_aot(25, 2, Vector2(1.0 + 0.5 * k, 0.0))
		_press("ctl.lm.aot.mark_x")
	assert_eq(lgc.align.pairs.size(), LgcAlign.MAX_PAIRS, "five pairs")
	lgc.alarm_code = 0
	_press("ctl.lm.aot.mark_y")
	assert_eq(lgc.alarm_code, 107, "a sixth: 00107")
	keys("P", lgc)
	_shows(["01", "70"], "PRO: the star from its pairs, and V01N70 for the second")
	var measured: Vector3 = lgc.align.measured[0]
	var true_dir := lgc.imu.platform * Stars.direction(25)
	assert_lt(rad_to_deg(measured.angle_to(true_dir)), 0.01, "Acrux where the platform has it, to the CDUs' counts")


func test_on_an_aligned_platform_n93_is_nothing_to_torque() -> void:
	var lgc := _to_marks()
	lgc.imu.align(lgc.imu.refsmmat)
	for star in [25, 33]:
		if star == 33:
			keys("V21E00233EEPEP", lgc)
			_shows(["54", "71"], "the second star, Antares")
		aot_marks(star, 2, 2)
		keys("P", lgc)
	_shows(["06", "05"], "V06N05")
	assert_lt(lgc.align.sad_deg, 0.01, "N05: the stars' angle as the catalog has it")
	keys("P", lgc)
	_shows(["06", "93"], "V06N93")
	var n93: Array = lgc.noun_values(93)
	assert_lt(Vector3(n93[0], n93[1], n93[2]).length(), 0.01, "the torquing angles next to nothing")


func test_option_4_orients_the_platform_to_the_landing_site() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	var lgc := rt.lgc()
	# The landing's time and site, as the DOI PAD uplinks them (an
	# undocking this early brings none).
	lgc.landing_site = rt.sequencer.landing_site()
	lgc.tland = rt.sequencer.site_get()
	Bus.set_value("ctl.lm.mode", 2)
	keys("V37E52E", lgc)
	keys("V22E4EP", lgc)
	_shows(["06", "34"], "V06N34: the landing's time")
	assert_almost_eq(float(lgc.noun_values(34)[0]), lgc.tland, 0.01, "TLAND")
	keys("P", lgc)
	_shows(["06", "89"], "V06N89: the site")
	keys("P", lgc)
	_shows(["06", "22"], "V06N22: the gimbal angles there")
	keys("P", lgc)
	_shows(["50", "25"], "V50N25 00013: the coarse align")
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.step_name == "acquire", 120.0, 1.0, false), "on to the stars")
	var x := Imu.axis(lgc.imu.refsmmat, 0)
	var site := Bodies.moon_fixed(lgc.tland) * lgc.landing_site
	assert_lt(rad_to_deg(x.angle_to(site)), 0.01, "X up through the site at the landing's time")
	var z := Imu.axis(lgc.imu.refsmmat, 2)
	var h := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel())
	assert_lt(absf(rad_to_deg(z.angle_to(h)) - 90.0), 0.1, "Z downrange in Columbia's orbit")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 1.0, "the platform left to the fine align")

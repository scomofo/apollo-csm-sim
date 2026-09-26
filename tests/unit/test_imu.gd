## The IMU (src/systems/imu.gd), the navigation stars (src/dynamics/
## stars.gd), the optics (src/systems/optics.gd) and the DSKY's octal and
## three-decimal registers, which slice 4c's alignments are built on.
extends GutTest


func test_the_gimbal_angles_follow_the_gimbals_order() -> void:
	# Each angle alone reads back, and so do all three together.
	for deg in [Vector3(30, 0, 0), Vector3(0, 30, 0), Vector3(0, 0, 30), Vector3(20, 40, 60), Vector3(350, 200, 80)]:
		assert_almost_eq(Imu.gimbal_angles(Imu.gimbal_basis(deg)), deg, Vector3.ONE * Imu.CDU_DEG, "%s" % deg)
	# The outer gimbal is on the body's X axis: a roll turns it alone. The
	# inner is on the stable member's Y axis: the platform turned about Y
	# turns it alone.
	var g := Imu.gimbal_basis(Vector3(20, 40, 60))
	assert_almost_eq(Imu.gimbal_angles(g * Basis(Vector3(1, 0, 0), deg_to_rad(10.0))), Vector3(30, 40, 60),
		Vector3.ONE * Imu.CDU_DEG, "a roll: the outer gimbal")
	assert_almost_eq(Imu.gimbal_angles(Basis(Vector3(0, 1, 0), deg_to_rad(10.0)) * g), Vector3(20, 50, 60),
		Vector3.ONE * Imu.CDU_DEG, "the platform about Y: the inner gimbal")
	# To a CDU count.
	var a := Imu.gimbal_angles(Imu.gimbal_basis(Vector3(12.34567, 0, 0))).x
	assert_almost_eq(fposmod(a / Imu.CDU_DEG, 1.0), 0.0, 1e-6, "a whole number of counts")


func test_the_preferred_orientation_puts_the_burn_attitude_at_zero() -> void:
	var r := Vector3(7.0e6, 1.0e6, 0.5e6)
	var dv := Vector3(0.3, 0.9, -0.2).normalized()
	var m := Imu.preferred(dv, r)
	# Heads up along the thrust, as AgcCore.burn_attitude() flies it.
	var x := dv
	var down := -r.normalized()
	var z := (down - x * down.dot(x)).normalized()
	var att := Basis(x, z.cross(x), z)
	assert_almost_eq(Imu.gimbal_angles(m * att), Vector3.ZERO, Vector3.ONE * Imu.CDU_DEG)
	# REFSMMAT's rows are the stable member's axes.
	assert_almost_eq(Imu.axis(m, 0), dv, Vector3.ONE * 1e-6, "X along the thrust")
	assert_true(m.is_equal_approx(m.orthonormalized()), "a rotation")


func test_the_landing_site_orientation() -> void:
	var site := Vector3(1.0, 0.5, 0.2).normalized() * 1.736e6
	var h := site.cross(Vector3(0, 0, 1)).normalized()
	var m := Imu.landing_site(site, h)
	assert_almost_eq(Imu.axis(m, 0), site.normalized(), Vector3.ONE * 1e-6, "X up through the site")
	assert_almost_eq(Imu.axis(m, 2), h.cross(site).normalized(), Vector3.ONE * 1e-6, "Z downrange")
	assert_almost_eq(Imu.axis(m, 1), -h, Vector3.ONE * 1e-6, "Y against the orbit's normal")


func test_the_platform_drifts_and_the_computer_sees_through_it() -> void:
	var imu := Imu.new()
	imu.align(Basis.IDENTITY)
	imu.drift = Vector3(0.0, 0.0, deg_to_rad(0.02) / 3600.0)
	var body := Basis.IDENTITY
	# Ten hours in fixed steps: each step's drift is far below a float's
	# resolution, and still adds up.
	for i in 1800000:
		imu.step(0.02, body)
	assert_almost_eq(rad_to_deg(imu.misalignment().length()), 0.2, 1e-5, "0.02 deg/h for 10 h")
	# The attitude and the sensed ΔV turned alike: the body frame is not.
	var q := Quaternion(Vector3(0, 0, 1), 0.3)
	var dv := Basis(q) * Vector3(5.0, 0.0, 0.0)
	var seen := imu.sensed(dv)
	assert_almost_eq(Basis(imu.attitude(q)).inverse() * seen, Vector3(5.0, 0.0, 0.0), Vector3.ONE * 1e-5,
		"along the body's X, as the vehicle felt it")
	assert_almost_eq(rad_to_deg(seen.angle_to(dv)), 0.2, 1e-4, "but 0.2 deg off in ECI")
	# A fine align takes it out: the rotation from the platform to REFSMMAT.
	imu.torque(Imu.rotation_vector(imu.refsmmat * imu.platform.transposed()))
	assert_lt(rad_to_deg(imu.misalignment().length()), 1e-5, "torqued back")


func test_a_coarse_align_takes_time_and_lands_near_its_angles() -> void:
	var imu := Imu.new()
	imu.align(Basis.IDENTITY)
	imu.disperse(7, 0.0, 0.2)
	var body := Basis(Vector3(0, 0, 1), 0.5)
	var want := Vector3(10.0, 20.0, 30.0)
	var from := imu.icdu(body)
	var most := 0.0
	for i in 3:
		most = maxf(most, absf(wrapf(want[i] - from[i], -180.0, 180.0)))
	imu.coarse_align(Imu.gimbal_basis(want), body)
	assert_false(imu.operating(), "coarse align: NO ATT")
	var t := 0.0
	while not imu.operating() and t < 60.0:
		imu.step(0.02, body)
		t += 0.02
	gut.p("coarse align: %.1f s; at %s" % [t, imu.icdu(body)])
	assert_almost_eq(t, Imu.COARSE_SETTLE_S + most / Imu.COARSE_RATE_DEG_S, 0.05, "settle plus the largest angle at its rate")
	var got := imu.icdu(body)
	for i in 3:
		assert_almost_eq(got[i], want[i], 1.0, "within the coarse align's accuracy")


func test_gimbal_lock_lights_the_lamp_then_cages_the_imu() -> void:
	var imu := Imu.new()
	imu.align(Basis.IDENTITY)
	for yaw in [60.0, 75.0, 86.0]:
		var body := Basis(Vector3(0, 0, 1), deg_to_rad(yaw))
		imu.step(0.02, body)
		assert_eq(imu.lock_lamp(body), yaw > 70.0, "GIMBAL LOCK at %d deg" % int(yaw))
		assert_eq(imu.mode, "caged" if yaw > 85.0 else "operate", "caged past 85 deg")
	assert_false(imu.aligned, "the alignment lost")
	# Caged, the platform turns with the vehicle.
	var frozen := imu.icdu(Basis(Vector3(0, 0, 1), deg_to_rad(86.0)))
	var turned := Basis(Vector3(1, 0, 0), 0.4) * Basis(Vector3(0, 0, 1), deg_to_rad(86.0))
	imu.step(0.02, turned)
	assert_almost_eq(imu.icdu(turned), frozen, Vector3.ONE * Imu.CDU_DEG, "frozen gimbal angles")
	# An ideal IMU never loses its alignment.
	var ideal := Imu.new()
	ideal.ideal = true
	ideal.step(0.02, Basis(Vector3(0, 0, 1), deg_to_rad(88.0)))
	assert_true(ideal.aligned and ideal.operating(), "ideal")


func test_the_imu_comes_back_from_a_snapshot() -> void:
	var imu := Imu.new()
	imu.disperse(11, 0.015, 0.2)
	imu.align(Basis(Vector3(1, 2, 3).normalized(), 0.7))
	imu.torque(Vector3(0.001, -0.002, 0.0005))
	imu.coarse_align(Imu.gimbal_basis(Vector3(5, 6, 7)), Basis.IDENTITY)
	var copy := Imu.new()
	copy.restore(JSON.parse_string(JSON.stringify(imu.snapshot())))
	for i in 200:
		imu.step(0.05, Basis.IDENTITY)
		copy.step(0.05, Basis.IDENTITY)
	assert_eq(copy.mode, imu.mode)
	assert_true(copy.platform.is_equal_approx(imu.platform), "the same platform, the same coarse align error")
	assert_true(copy.refsmmat.is_equal_approx(imu.refsmmat))
	assert_almost_eq(copy.drift, imu.drift, Vector3.ONE * 1e-15)


func test_the_navigation_stars() -> void:
	var codes := Stars.codes()
	assert_eq(codes.size(), 37, "the 37 Apollo stars")
	assert_eq([codes[0], codes[-1]], [1, 45], "Alpheratz to Fomalhaut")
	for c in codes:
		assert_false(str(c).contains("8") or str(c).contains("9"), "%d: octal" % c)
		assert_almost_eq(Stars.direction(c).length(), 1.0, 1e-6)
	assert_eq(Stars.name_of(15), "Sirius")
	assert_eq(Stars.label(15), "00015")
	# Sirius at 6h 45m, -16.7 deg; Polaris near the pole.
	var s := Stars.direction(15)
	assert_almost_eq(rad_to_deg(atan2(s.y, s.x)), 101.29, 0.01, "Sirius's right ascension")
	assert_almost_eq(rad_to_deg(asin(s.z)), -16.71, 0.01, "and declination")
	assert_gt(Stars.direction(5).z, 0.9999, "Polaris")
	assert_false(Stars.has(8), "no star 8: the codes are octal")


func test_the_optics_line_of_sight() -> void:
	# The shaft axis: 32.5 deg from +Z toward +X.
	assert_almost_eq(Optics.los(0.0, 0.0), Vector3(sin(deg_to_rad(32.523)), 0.0, cos(deg_to_rad(32.523))),
		Vector3.ONE * 1e-9)
	for st in [Vector2(0, 10), Vector2(90, 30), Vector2(215, 45), Vector2(359, 57)]:
		var a := Optics.angles_for(Optics.los(st.x, st.y))
		assert_almost_eq(a, st, Vector2.ONE * 1e-4, "%s round trip" % st)
		var ax := Optics.view_axes(st.x, st.y)
		var b := Basis(ax[0], ax[1], -(ax[2] as Vector3))
		assert_true(b.is_equal_approx(b.orthonormalized()) and absf(b.determinant() - 1.0) < 1e-5,
			"right, up and back: a right-handed view")
	# The top of the trunnion's travel looks along the nose.
	assert_almost_eq(Optics.los(0.0, Optics.TRUNNION_MAX_DEG), Vector3(1, 0, 0), Vector3.ONE * 1e-3)


func test_the_optics_follow_their_modes() -> void:
	Bus.reset()
	var o: Optics = add_child_autofree(Optics.new())
	Bus.set_value("ctl.optics.zero", false)
	Bus.set_value("ctl.optics.mode", 0)
	Bus.set_value("ctl.optics.speed", 2)
	Bus.set_value("ctl.optics.hc", Vector3(1.0, 1.0, 0.0))
	o.tick(1.0)
	assert_almost_eq(Vector2(o.shaft_deg, o.trunnion_deg), Vector2(5.0, 5.0), Vector2.ONE * 1e-9, "HI: 5 deg/s")
	Bus.set_value("ctl.optics.hc", Vector3(0.0, 1.0, 0.0))
	o.tick(100.0)
	assert_eq(o.trunnion_deg, Optics.TRUNNION_MAX_DEG, "the trunnion stops at its limit")
	# CMC: driven to the computer's angles at the drive rate.
	Bus.set_value("ctl.optics.mode", 1)
	Bus.set_value("guid.optics.cmd", true)
	Bus.set_value("guid.optics.cmd_deg", Vector3(355.0, 20.0, 0.0))
	o.tick(1.0)
	assert_almost_eq(o.shaft_deg, 355.0, 1e-9, "the short way round")
	assert_almost_eq(o.trunnion_deg, Optics.TRUNNION_MAX_DEG - Optics.DRIVE_DEG_S, 1e-9)
	o.tick(10.0)
	assert_almost_eq(o.trunnion_deg, 20.0, 1e-9)
	# ZERO over both.
	Bus.set_value("ctl.optics.zero", true)
	o.tick(60.0)
	assert_eq([o.shaft_deg, o.trunnion_deg], [0.0, 0.0])
	assert_eq(Bus.get_value("optics.mode"), "zero")


func test_a_star_on_the_line_of_sight_is_at_the_centre_of_the_view() -> void:
	Bus.reset()
	Bus.set_value("dyn.att_q", Quaternion(Vector3(1, 1, 0).normalized(), 0.6))
	Bus.set_value("optics.shaft_deg", 40.0)
	Bus.set_value("optics.trunnion_deg", 25.0)
	var axes := OpticsView.view_axes_eci()
	var los: Vector3 = axes[2]
	var c := Vector2(100, 100)
	assert_almost_eq(OpticsView.project(los, axes, c, 80.0, 60.0), c, Vector2.ONE * 1e-3, "the centre")
	# Half the field off along the view's right is at its rim.
	var right := los.rotated(axes[1], -deg_to_rad(30.0))
	assert_almost_eq(OpticsView.project(right, axes, c, 80.0, 60.0), c + Vector2(80.0, 0.0), Vector2.ONE * 1e-3, "the rim")
	assert_null(OpticsView.project(-los, axes, c, 80.0, 60.0), "behind the eye")


func test_the_dsky_shows_and_loads_octal_and_three_decimals() -> void:
	assert_eq(Dsky.format_value(15.0, "o", 1.0), " 00015", "an octal code: no sign")
	assert_eq(Dsky.format_value(-0.1234, "d3", 1.0), "-00123")
	assert_almost_eq(Dsky.parse_value("+00123", "d3", 1.0), 0.123, 1e-9)
	var agc := Agc.new()
	autofree(agc)
	agc.change_program(52)   # the orientation is known: the option display
	var d := agc.dsky
	assert_eq([d.verb, d.noun, d.flashing], ["04", "06", true], "V04N06 asks for the option")
	for k in ["VERB", "2", "2", "ENTR"]:
		d.press(k)
	d.press("8")
	assert_true(d.lamps["opr_err"], "8 is no octal digit")
	d.press("RSET")
	d.press("4")
	d.press("ENTR")
	assert_eq(agc.align_option, 4, "option 4 loaded")
	assert_eq(d.r[1], " 00004")
	assert_eq([d.verb, d.noun], ["04", "06"], "back to the option display")


func test_v41_n20_coarse_aligns_to_the_angles_loaded() -> void:
	Bus.reset()
	SimClock.reset()
	var agc := Agc.new()
	add_child_autofree(agc)
	Bus.set_value("dyn.att_q", Quaternion(Vector3(0, 1, 0), 0.4))
	agc.imu.align(Basis.IDENTITY)
	var d := agc.dsky
	for k in ["VERB", "4", "1", "NOUN", "2", "0", "ENTR"]:
		d.press(k)
	assert_eq([d.verb, d.noun, d.flashing], ["25", "22", true], "V25N22 asks for the gimbal angles")
	for v in ["+01000", "+02000", "+03000"]:
		for ch in v:
			d.press(ch)
		d.press("ENTR")
	assert_eq(agc.imu.mode, "coarse", "driving the gimbals")
	assert_false(agc.imu.aligned, "REFSMMAT no longer holds")
	agc.tick(0.02)
	assert_true(d.lamps["no_att"], "NO ATT meanwhile")
	for i in 400:
		agc.sense(0.02)
	agc.tick(0.02)
	assert_true(agc.imu.operating(), "done")
	assert_false(d.lamps["no_att"])
	assert_almost_eq(agc.icdu(), Vector3(10.0, 20.0, 30.0), Vector3.ONE * Imu.CDU_DEG, "at the angles loaded")


## Whether attitudes [param a] and [param b] are within [param deg].
func _near(a: Quaternion, b: Quaternion, deg: float) -> bool:
	return 2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0)) < deg_to_rad(deg)


func test_the_auto_maneuver_is_planned_clear_of_gimbal_lock() -> void:
	Bus.reset()
	SimClock.reset()
	var agc := Agc.new()
	add_child_autofree(agc)
	agc.imu.align(Basis.IDENTITY)
	Bus.set_value("dyn.att_q", agc._at_gimbals(Vector3.ZERO))
	var now := agc._att()
	# The thrust axis all but reversed, 10 deg of middle gimbal at the end:
	# the short way round for it goes over the top, through 90 deg. So the
	# gimbals turn one at a time, the inner round first.
	agc.auto_target = agc._at_gimbals(Vector3(0, 180, 10))
	var x_now := Basis(now) * Vector3.RIGHT
	var x_to := Basis(agc.auto_target) * Vector3.RIGHT
	assert_gt(agc._peak_middle_gimbal(now, Quaternion(x_now, x_to) * now), 85.0, "the thrust axis's short way locks")
	agc._plan_via()
	assert_eq(agc.maneuver_vias.size(), 1, "a leg before the last")
	assert_true(_near(agc.maneuver_vias[0], agc._at_gimbals(Vector3(0, 180, 0)), 0.1), "the inner gimbal round first")
	var legs: Array[Quaternion] = [now]
	legs.append_array(agc.maneuver_vias)
	legs.append(agc.auto_target)
	var peak := 0.0
	for i in legs.size() - 1:
		peak = maxf(peak, agc._peak_middle_gimbal(legs[i], legs[i + 1]))
	assert_lt(peak, 10.1, "the middle gimbal never past its ends'")
	# A turn clear of lock: the thrust axis the short way onto the
	# target's, then the roll about it.
	agc.auto_target = agc._at_gimbals(Vector3(40, 30, 20))
	agc._plan_via()
	assert_eq(agc.maneuver_vias.size(), 1)
	var x_via := Basis(agc.maneuver_vias[0]) * Vector3.RIGHT
	assert_almost_eq(x_via.angle_to(Basis(agc.auto_target) * Vector3.RIGHT), 0.0, 1e-3, "the thrust axis on the target's")
	# The DAP steers to each leg's end in turn, and an ideal IMU (the
	# LGC's) needs no legs.
	assert_true(_near(agc._maneuver_target(), agc.maneuver_vias[0], 1e-3), "the first leg first")
	agc.imu.ideal = true
	agc._plan_via()
	assert_true(agc.maneuver_vias.is_empty(), "straight there")

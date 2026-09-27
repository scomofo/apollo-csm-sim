## Slice 4c's check (docs/ROADMAP.md, milestone 4): the CMC's IMU drifts,
## P52 and two star marks realign it to within a set limit, and a burn
## flown on a misaligned platform misses by as much as the misalignment
## says. Gimbal lock costs the alignment, and P51 finds the platform's
## orientation again from the stars. Holding attitude on the drifting
## platform through a long coast costs a few corrections, not a limit
## cycle.
extends SimTest

## What P52 leaves, deg: the marks and the gimbals are read to a CDU count
## (0.011 deg), and the crew centres the star on it.
const RESIDUAL_LIMIT_DEG := 0.02


func test_the_platform_drifts_and_p52_realigns_it() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	assert_almost_eq(misalignment_deg(), 0.0, 1e-6, "aligned at the start, to the launch pad REFSMMAT")
	Bus.set_value("ctl.cmc.mode", 0)
	run(12.0 * 3600.0)
	var drifted := misalignment_deg()
	var rate := rad_to_deg(agc.imu.drift.length()) * 3600.0
	gut.p("12 h: the platform has drifted %.3f deg (%.4f deg/h)" % [drifted, rate])
	assert_almost_eq(drifted, rate * 12.0, 0.01 * rate * 12.0, "at the gyros' drift")
	assert_gt(drifted, 0.05, "a drift worth realigning")
	# P52 option 3 (REFSMMAT): no coarse align, two marks, torque.
	Bus.set_value("ctl.cmc.mode", 1)
	var p52 := realign(3)
	var left := misalignment_deg()
	gut.p("P52 on %s and %s: N05 %.3f deg, N93 %s deg; %.4f deg left" % [
		Stars.name_of(p52["stars"][0]), Stars.name_of(p52["stars"][1]), p52["sad"], p52["torque"], left])
	assert_lt(float(p52["sad"]), 0.02, "N05: the marks agree with the catalog")
	assert_almost_eq((p52["torque"] as Vector3).length(), drifted, 0.02, "N93 takes out the drift")
	assert_lt(left, RESIDUAL_LIMIT_DEG, "realigned")
	assert_eq(agc.program, 0)
	assert_true(agc.imu.aligned)


func test_attitude_hold_on_a_drifting_platform_costs_little_propellant() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	Bus.set_value("ctl.cmc.mode", 1)
	run(1.0, false)
	var kg0 := float(Bus.get_value("rcs.sm_prop_kg"))
	# The drift carries the attitude the CMC holds away every few hours;
	# each time the DAP brings it back and nulls the rate, and between
	# times the coast runs in long steps.
	var seen := {"worst_deg": 0.0, "fine": 0}
	var watch := func(dt: float) -> void:
		seen["worst_deg"] = maxf(seen["worst_deg"], rad_to_deg(agc._error_vector(agc.hold_q).length()))
		if dt < SimClock.FIXED_DT * 1.5:
			seen["fine"] += 1
	SimClock.ticked.connect(watch)
	run(16.0 * 3600.0)
	SimClock.ticked.disconnect(watch)
	var used := kg0 - float(Bus.get_value("rcs.sm_prop_kg"))
	gut.p("16 h in HOLD on a drifting platform: %.3f kg of RCS propellant, the error at most %.3f deg, %d fine steps" % [
		used, seen["worst_deg"], seen["fine"]])
	assert_gt(float(seen["worst_deg"]), rad_to_deg(Agc.ATT_DEADBAND * 0.1) - 0.005, "the drift moved the attitude held")
	assert_lt(float(seen["worst_deg"]), rad_to_deg(Agc.ATT_DEADBAND * 0.2), "inside the deadband")
	assert_lt(used, 1.0, "a few corrections, no limit cycle")
	assert_lt(int(seen["fine"]), 20000, "the coast in long steps between them")


func dsky_lamp(lamp: String) -> bool:
	return bool(Bus.get_value("dsky.lamp." + lamp, false))


## TEI from the lunar_orbit start on a platform that doesn't drift, turned
## by [param tilt] (rad about the stable member's axes) and flown without a
## realign. Returns fly_pad()'s burn_log, with the CMC's misalignment at
## the burn ("m", rad, ECI) and its state vector after it ("nav").
func _tei(tilt: Vector3) -> Dictionary:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var agc := rt.agc()
	agc.imu.drift = Vector3.ZERO
	agc.imu.torque(tilt)
	assert_false(rt.sequencer.request_pad("tei").is_empty(), "a TEI PAD")
	fly_pad(0)
	var out := burn_log.duplicate()
	out["m"] = agc.imu.misalignment()
	out["nav"] = agc.current_traj()
	return out


func test_a_burn_on_a_misaligned_platform_misses_by_what_the_misalignment_predicts() -> void:
	var a := _tei(Vector3.ZERO)
	var b := _tei(Vector3(1.0, -1.0, 1.0).normalized() * deg_to_rad(0.5))
	var m: Vector3 = b["m"]
	# Both at one time just after both burns, and flight A had the burn
	# not been flown: A's ΔV is the difference.
	var t := maxf((a["after"] as Trajectory).t, (b["after"] as Trajectory).t) + 1.0
	var tr := {}
	for k in ["a", "b", "coast"]:
		var src: Trajectory = (a["after"] if k == "a" else b["after"] if k == "b" else a["before"])
		tr[k] = src.clone()
		(tr[k] as Trajectory).coast_to(t, 1.0)
	var dv_a: Vector3 = tr["a"].vel() - tr["coast"].vel()
	# The CMC flew its ΔV in its own reference, turned from ECI by the
	# misalignment: in truth the thrust went that much the other way.
	var predicted := Imu.rotation(-m) * dv_a - dv_a
	var got: Vector3 = tr["b"].vel() - tr["a"].vel()
	gut.p("TEI %.1f m/s on a platform %.3f deg off: %.2f m/s off the aligned flight, %.2f predicted, %.2f deg apart" % [
		dv_a.length(), rad_to_deg(m.length()), got.length(), predicted.length(), rad_to_deg(got.angle_to(predicted))])
	assert_almost_eq(rad_to_deg(m.length()), 0.5, 1e-3, "the platform was 0.5 deg off")
	assert_almost_eq(got.length(), predicted.length(), 0.03 * predicted.length(), "the miss is the misalignment's")
	assert_lt(rad_to_deg(got.angle_to(predicted)), 3.0, "and in its direction")
	# The CMC doesn't see it: its state vector has flown the plan, as
	# flight A's did (both drifting alike from the truth before it).
	var nav: Trajectory = b["nav"]
	nav.coast_to(t, 1.0)
	var nav_a: Trajectory = a["nav"]
	nav_a.coast_to(t, 1.0)
	assert_lt((nav.vel() - nav_a.vel()).length(), 0.2 * got.length(), "the CMC thinks it flew the aligned burn")
	# Where it takes the CSM: the Earth return's perigee.
	var ra := Rtcc.earth_return(tr["a"].clone(), t + 4.0 * 86400.0)
	var rb := Rtcc.earth_return(tr["b"].clone(), t + 4.0 * 86400.0)
	gut.p("Earth return perigee: aligned %.1f km, misaligned %.1f km" % [
		(float(ra["rp"]) - Bodies.R_EARTH) / 1000.0, (float(rb["rp"]) - Bodies.R_EARTH) / 1000.0])


## The stars the crew could mark with the optics from the CSM's true
## attitude: within the trunnion's reach, clear of the Earth and the Moon.
func _stars_in_reach() -> Array:
	var tr := rt.dynamics.traj
	var to_body := Basis(rt.dynamics.attitude.q).inverse()
	var near := Agc._near_bodies(tr)
	var out := []
	for c in Stars.codes():
		var s := Stars.direction(c)
		if Optics.angles_for(to_body * s).y > 45.0:
			continue
		var hidden := false
		for body in near:
			if rad_to_deg(s.angle_to(body[0])) < float(body[1]) + 5.0:
				hidden = true
		if not hidden:
			out.append(c)
	return out


func test_gimbal_lock_loses_the_alignment_and_p51_finds_it_again() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var agc := rt.agc()
	# A yaw in FREE turns the middle gimbal toward 90 deg on the landing
	# site REFSMMAT.
	Bus.set_value("ctl.cmc.mode", 0)
	rt.dynamics.attitude.omega = Vector3(0.0, 0.0, deg_to_rad(1.0))
	var lamp := run_until(func() -> bool: return dsky_lamp("gimbal_lock"), 120.0, 0.5, false)
	assert_true(lamp, "GIMBAL LOCK")
	var mg := absf(wrapf(agc.icdu().z, -180.0, 180.0))
	assert_between(mg, 70.0, 71.0, "at 70 deg of middle gimbal")
	assert_true(agc.imu.aligned, "still aligned")
	var caged := run_until(func() -> bool: return agc.imu.mode == "caged", 60.0, 0.5, false)
	assert_true(caged, "caged at 85 deg")
	assert_false(agc.imu.aligned, "the alignment is lost")
	run(1.0, false)
	assert_true(dsky_lamp("no_att"), "NO ATT")
	# HOLD damps the yaw on the gyros alone.
	Bus.set_value("ctl.cmc.mode", 1)
	run(30.0, false)
	assert_lt(rt.dynamics.attitude.omega.length(), deg_to_rad(0.02), "the rates damped")
	# Neither P52 nor a burn without the orientation: alarm 00220.
	keys("V37E52E")
	assert_eq(agc.program, 0, "no P52")
	assert_eq(agc.alarm_code, 220, "IMU orientation unknown")
	keys("R")
	# P51: the IMU run up at zero gimbal angles, then two stars the crew
	# finds and names.
	keys("V37E51E")
	assert_eq(agc.program, 51)
	var up := run_until(func() -> bool: return agc.step_name == "acquire", 60.0, 1.0, false)
	assert_true(up, "coarse aligned to zero")
	var g := agc.icdu()
	for i in 3:
		assert_lt(absf(wrapf(g[i], -180.0, 180.0)), 1.0, "gimbal %d at zero, to the coarse align's accuracy" % i)
	assert_false(dsky_lamp("no_att"), "NO ATT out")
	# The optics look out of the CM's +Z side, at the Moon: the crew rolls
	# heads down to find stars.
	var stars := _stars_in_reach()
	if stars.size() < 2:
		roll_over()
		stars = _stars_in_reach()
	assert_gt(stars.size(), 1, "stars in the optics' reach")
	var pair := [stars[0], stars[stars.size() - 1]]
	for c in pair:
		keys("P")   # V50N25: acquired
		assert_eq(agc.step_name, "mark", "V51")
		centre_star(c)
		mark()
		assert_eq(Bus.get_value("dsky.noun"), "71", "V01N71: which star")
		keys("V21E%dEP" % c)
	assert_eq(agc.step_name, "n05")
	gut.p("P51 on %s and %s: N05 %.3f deg" % [Stars.name_of(pair[0]), Stars.name_of(pair[1]), agc.align_sad_deg])
	assert_lt(agc.align_sad_deg, 0.02, "N05")
	keys("P")
	assert_eq(agc.program, 0, "P51 done")
	assert_true(agc.imu.aligned, "the orientation found")
	assert_lt(misalignment_deg(), RESIDUAL_LIMIT_DEG, "REFSMMAT describes the platform")
	# And P52 option 4 back to the landing site REFSMMAT.
	var p52 := realign(4)
	var ls := rt.sequencer.landing_site_refsmmat(agc.current_traj())
	assert_lt(rad_to_deg(Imu.rotation_vector(agc.imu.refsmmat * ls.transposed()).length()), 0.01, "on the landing site REFSMMAT")
	assert_lt(misalignment_deg(), RESIDUAL_LIMIT_DEG, "and aligned to it (N93 %s)" % p52["torque"])


func test_p52_aligns_to_the_preferred_orientation_for_a_burn() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var agc := rt.agc()
	assert_false(rt.sequencer.request_pad("tei").is_empty(), "a TEI PAD")
	keys("V37E30E")
	keys("PPP")
	assert_true(agc.preferred_valid, "P30 worked out the preferred orientation")
	var n22: Array = agc.noun_values(22)
	var p52 := realign(1)
	gut.p("P52 option 1: N22 was %s; N93 %s deg" % [n22, p52["torque"]])
	assert_lt(rad_to_deg(Imu.rotation_vector(agc.imu.refsmmat * agc.preferred_refsmmat.transposed()).length()), 1e-4,
		"REFSMMAT is the preferred orientation")
	assert_lt(misalignment_deg(), RESIDUAL_LIMIT_DEG, "and the platform on it")
	assert_lt((p52["torque"] as Vector3).length(), 1.0, "N93: the coarse align's error")
	# At the burn attitude the gimbals read zero.
	Bus.set_value("ctl.cmc.mode", 2)
	keys("V37E40E")
	keys("P")
	var there := run_until(func() -> bool: return agc.step_name == "wait", 600.0, 1.0, false)
	assert_true(there, "at the burn attitude")
	var g := agc.icdu()
	for i in 3:
		assert_lt(absf(wrapf(g[i], -180.0, 180.0)), 3.0, "gimbal %d near zero at the burn attitude" % i)


func test_p52_finds_no_stars_with_the_optics_on_the_moon() -> void:
	build("lunar_orbit")
	var agc := rt.agc()
	Bus.set_value("ctl.cmc.mode", 1)
	# The optics' shaft axis straight down at the Moon.
	var shaft := Optics.los(0.0, 0.0)
	var down := -rt.dynamics.traj.pos().normalized()
	var q := Quaternion(Basis(rt.dynamics.attitude.q) * shaft, down) * rt.dynamics.attitude.q
	rt.dynamics.attitude.q = q.normalized()
	rt.dynamics.publish_state()
	run(1.0, false)
	keys("V37E52EV22E3EPP")
	assert_eq(agc.step_name, "acquire", "no stars picked")
	assert_eq(agc.alarm_code, 405, "two stars not available")
	assert_true(dsky_lamp("prog"))


func test_p52_wont_coarse_align_into_gimbal_lock_and_p40_maneuvers_clear_of_it() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	Bus.set_value("ctl.cmc.mode", 0)
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	assert_false(rt.sequencer.request_pad("loi").is_empty(), "an LOI PAD")
	keys("V37E30EPPP")
	# The CSM with its middle gimbal at 66 deg on the launch pad REFSMMAT,
	# leaning toward the preferred orientation's Y axis.
	var y_old := Imu.axis(agc.imu.refsmmat, 1)
	var y_new := Imu.axis(agc.preferred_refsmmat, 1)
	var u := (y_new - y_old * y_new.dot(y_old)).normalized()
	var x := (u * cos(deg_to_rad(66.0)) + y_old * sin(deg_to_rad(66.0))).normalized()
	var z := x.cross(u).normalized()
	rt.dynamics.attitude.q = Basis(x, z.cross(x), z).get_rotation_quaternion()
	rt.dynamics.attitude.omega = Vector3.ZERO
	rt.dynamics.publish_state()
	Bus.set_value("ctl.cmc.mode", 1)
	run(1.0, false)
	assert_true(agc.imu.operating(), "clear of lock on the platform as it stands")
	keys("V37E52EV22E1EP")
	var mg := absf(wrapf(float(agc.noun_values(22)[2]), -180.0, 180.0))
	gut.p("N22's middle gimbal: %.1f deg, the platform's %.1f deg" % [mg, absf(wrapf(agc.icdu().z, -180.0, 180.0))])
	assert_gt(mg, Agc.LOCK_MANEUVER_DEG, "a new orientation in gimbal lock from here")
	keys("P")
	assert_eq([agc.step_name, agc.alarm_code], ["n22", 401], "no coarse align: alarm 00401")
	assert_true(agc.imu.operating() and agc.imu.aligned, "the platform left as it was")
	keys("R")
	turn_for_new_orientation()
	mg = absf(wrapf(float(agc.noun_values(22)[2]), -180.0, 180.0))
	gut.p("after the turn, N22's middle gimbal: %.1f deg" % mg)
	assert_lt(mg, 2.0, "clear")
	keys("P")
	var up := run_until(func() -> bool: return agc.step_name == "acquire", 120.0, 1.0, false)
	assert_true(up and agc.imu.operating(), "coarse aligned, not caged")
	keys("V37E00E")
	# P40's maneuver to the burn attitude, in two legs, never nears lock.
	Bus.set_value("ctl.cmc.mode", 2)
	keys("V37E40EP")
	assert_eq(agc.step_name, "maneuver", "maneuvering")
	var worst_mg := 0.0
	var t_end := SimClock.get_seconds + 900.0
	while SimClock.get_seconds < t_end and agc.step_name == "maneuver":
		run(1.0, false)
		worst_mg = maxf(worst_mg, absf(wrapf(agc.icdu().z, -180.0, 180.0)))
	gut.p("the maneuver to LOI's burn attitude: the middle gimbal at most %.1f deg" % worst_mg)
	assert_eq(agc.step_name, "wait", "at the burn attitude")
	assert_lt(worst_mg, Imu.LOCK_LAMP_DEG, "no GIMBAL LOCK on the way")
	assert_true(agc.imu.operating(), "never caged")

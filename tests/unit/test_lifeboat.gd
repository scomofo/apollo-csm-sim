## Slice 7d: the LM as a lifeboat. Docked, the LM is dark until its crew
## powers it up; then its batteries carry it, its LGC's platform comes up
## caged until a coarse align through the docking geometry, and its engine
## and jets fly the stack, on the PGNS or the AGS. The CM powers down to
## the emergency load, or to nothing, and takes the LM's power to charge
## its entry batteries; the SM's oxygen leaks away after Apollo 13's
## failure; LM JETT from the CM pushes it back. The flight itself is
## tests/scenarios/test_apollo_13.gd's.
extends SimTest


## The docked LM powered up by its crew (ctl.lm.power), the CMC's DAP
## free so that only the LM's autopilots fly the stack.
func _lm_up() -> void:
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.lm.power", true)
	run(1.0, false)


## The velocity the stack has gained on [param coast], its trajectory
## before, coasted to now: what its engines and jets gave it.
func _thrust_dv(coast: Trajectory) -> Vector3:
	coast.coast_to(rt.dynamics.traj.t, 1.0)
	return rt.dynamics.traj.vel() - coast.vel()


## V41N20 on [param c]: the gimbal angles [param g] (deg) loaded into N22.
func _coarse_align(c: AgcCore, g: Vector3) -> void:
	keys("V41N20E", c)
	for a in [g.x, g.y, g.z]:
		keys("+%05dE" % int(round(fposmod(a, 360.0) * 100.0)), c)


func test_the_docked_lm_is_dark_until_its_crew_powers_it_up() -> void:
	build("translunar_coast")
	assert_eq(Bus.get_value("dock.state"), "docked")
	assert_false(bool(Bus.get_value("lm.sys.powered")), "docked, the LM powered down")
	assert_false(rt.lgc().is_powered(), "the LGC dark")
	var ah0 := float(Bus.get_value("lm.eps.batt_ah"))
	assert_eq(ah0, 2192.0, "the LM's batteries full")
	_lm_up()
	assert_true(bool(Bus.get_value("lm.sys.powered")), "the LM's batteries on its buses")
	assert_true(rt.lgc().is_powered(), "the LGC up with the PGNS's breakers in")
	assert_eq(float(Bus.get_value("lm.eps.load_a")), 30.0, "30 A with the PGNS up")
	Bus.set_value("ctl.lm.pgns", false)
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	assert_false(rt.lgc().is_powered(), "the PGNS's breakers out")
	assert_eq(float(Bus.get_value("lm.eps.load_a")), 14.0, "12 A powered down, the AGS's 2")
	var ah1 := float(Bus.get_value("lm.eps.batt_ah"))
	run(3600.0)
	assert_almost_eq(ah1 - float(Bus.get_value("lm.eps.batt_ah")), 14.0, 0.1, "an hour on the batteries")
	# Its motion is the stack's, in its own axes.
	assert_eq(float(Bus.get_value("lm.dyn.mass_kg")), rt.dynamics.mass)
	var att: Quaternion = Bus.get_value("lm.dyn.att_q")
	assert_true(att.is_equal_approx((rt.dynamics.attitude.q * Docking.LM_IN_CSM).normalized()), "the LM's attitude")


func test_the_docked_lgcs_platform_is_caged_until_a_coarse_align() -> void:
	build("translunar_coast")
	var lgc := rt.lgc()
	var agc := rt.agc()
	_lm_up()
	assert_eq(lgc.imu.mode, "caged", "no attitude")
	assert_false(lgc.imu.aligned)
	_coarse_align(lgc, Docking.lm_gimbals(agc.icdu()))
	run(120.0, false)
	assert_true(lgc.imu.operating(), "coarse aligned")
	var off := Imu.rotation_vector(agc.imu.platform.transposed() * lgc.imu.platform).length()
	assert_lt(rad_to_deg(off), 1.0, "the LM's platform lying where the CM's does")
	assert_true(lgc.uplink_refsmmat(agc.imu.refsmmat), "the ground's REFSMMAT")
	assert_true(lgc.imu.aligned)
	assert_true(bool(Bus.get_value("lm.imu.aligned")))
	# Power lost, the platform's orientation is lost with it.
	Bus.set_value("ctl.lm.pgns", false)
	run(1.0, false)
	assert_eq(lgc.imu.mode, "caged")
	assert_false(lgc.imu.aligned)


## Apollo 13's crew turned Odyssey's N20 into Aquarius's by hand: the inner
## gimbal plus 180 degrees, the middle's negative (the Apollo Flight
## Journal, 058:03), as the docking geometry does.
func test_the_lms_gimbal_angles_through_the_docking() -> void:
	var cm := Vector3(355.57, 167.78, 351.87)
	var lm := Docking.lm_gimbals(cm)
	assert_almost_eq(lm.y, 347.78, 0.01, "the inner")
	assert_almost_eq(lm.z, 8.13, 0.01, "the middle")
	var b := Imu.gimbal_basis(lm)
	var want := Imu.gimbal_basis(cm) * Basis(Docking.LM_IN_CSM)
	assert_lt(Imu.rotation_vector(want.transposed() * b).length(), deg_to_rad(2.0 * Imu.CDU_DEG),
		"one platform, seen from each, to a CDU count")


func test_the_lms_engine_and_jets_fly_the_docked_stack() -> void:
	build("translunar_coast")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.lm.engine_arm", 2)
	Bus.set_value("ctl.lm.eng_start", true)
	run(1.0, false)
	Bus.set_value("ctl.lm.eng_start", false)
	assert_eq(float(Bus.get_value("lm.dps.thrust_n")), 0.0, "not with the LM dark")
	Bus.set_value("ctl.lm.power", true)
	run(1.0, false)
	Bus.set_value("ctl.lm.eng_start", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.eng_start", false)
	var coast := rt.dynamics.traj.clone()
	var x := rt.dynamics.attitude.eci_from_body() * Vector3.RIGHT
	run(5.0, false)
	assert_true(bool(Bus.get_value("lm.dps.on")), "started by hand")
	assert_almost_eq(float(Bus.get_value("lm.dps.throttle_pct")), 10.0, 0.5, "at the TTCA's minimum")
	assert_lt(_thrust_dv(coast).dot(x), -0.1, "pushing the stack along the CSM's -X")
	Bus.set_value("ctl.lm.eng_stop", true)
	run(2.0, false)
	Bus.set_value("ctl.lm.eng_stop", false)
	assert_false(bool(Bus.get_value("lm.dps.on")))
	# The LM's jets turn the stack.
	Bus.set_value("ctl.lm.mode", 0)
	Bus.set_value("ctl.lm.rhc", Vector3(0.0, 1.0, 0.0))
	run(2.0, false)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	var w: Vector3 = Bus.get_value("lm.dyn.omega")
	assert_gt(w.y, 1e-4, "pitching about the LM's Y")
	assert_almost_eq(w.x, 0.0, 1e-5)


func test_the_ags_holds_the_stack_and_counts_its_delta_v() -> void:
	build("translunar_coast")
	_lm_up()
	Bus.set_value("ctl.lm.pgns", false)
	Bus.set_value("ctl.lm.ags", true)
	Bus.set_value("ctl.lm.guid_cont", 1)
	Bus.set_value("ctl.lm.mode", 1)
	run(1.0, false)
	assert_true(bool(Bus.get_value("lm.ags.on")))
	rt.dynamics.attitude.omega = Vector3(0.0, 0.002, 0.0)
	run(120.0, false)
	assert_lt(rt.dynamics.attitude.omega.length(), 2e-4, "the AGS's hold")
	Bus.set_value("ctl.lm.ags_align", true)
	run(0.1, false)
	Bus.set_value("ctl.lm.ags_align", false)
	assert_almost_eq(float(Bus.get_value("lm.ags.dv_x_mps")), 0.0, 1e-6, "zeroed at the align")
	var coast := rt.dynamics.traj.clone()
	var lm_x := Basis(Bus.get_value("lm.dyn.att_q") as Quaternion).x
	Bus.set_value("ctl.lm.thc", Vector3(1.0, 0.0, 0.0))
	run(10.0, false)
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)
	run(1.0, false)
	var sensed := float(Bus.get_value("lm.ags.dv_x_mps"))
	assert_gt(sensed, 0.1, "the +X jets")
	assert_almost_eq(sensed, _thrust_dv(coast).dot(lm_x), 0.01, "the DEDA's 470")


func test_the_cm_powers_down_and_charges_from_the_lm() -> void:
	build("translunar_coast")
	Bus.set_value("ctl.cmc.mode", 0)
	run(1.0, false)
	assert_eq(float(Bus.get_value("eps.load_w")), 1900.0, "all the CM's loads")
	Bus.set_value("ctl.eps.cm_power", 1)
	run(1.0, false)
	assert_eq(float(Bus.get_value("eps.load_w")), 1200.0, "the emergency power-down's")
	assert_true(bool(Bus.get_value("sys.powered")))
	Bus.set_value("ctl.eps.cm_power", 0)
	run(1.0, false)
	assert_false(bool(Bus.get_value("sys.powered")), "the CM dark")
	assert_eq(float(Bus.get_value("eps.bus_a_v")), 0.0)
	assert_false(rt.agc().is_powered(), "the CMC dark")
	assert_eq(rt.agc().imu.mode, "caged", "its platform lost")
	var eps: Node = rt.systems["eps"]
	eps.batt_ah[0] = 30.0
	Bus.set_value("ctl.eps.lm_power", true)
	run(1.0, false)
	assert_eq(float(Bus.get_value("eps.lm_draw_a")), 0.0, "nothing from a dark LM")
	Bus.set_value("ctl.lm.power", true)
	run(1.0, false)
	assert_eq(float(Bus.get_value("eps.lm_draw_a")), 7.0, "7 A from the LM")
	assert_eq(float(Bus.get_value("lm.eps.load_a")), 37.0, "on the LM's load")
	run(3600.0)
	assert_almost_eq(float(eps.batt_ah[0]), 31.3, 0.05, "1.3 A into the least charged battery")


## Apollo 13's tank 1 leaked its oxygen away as fuel cell 2 carried the
## emergency power-down: the last fuel cell stopped 2 h 20 min after the
## failure (55:54:53 to 58:15:11).
func test_tank_1_leaks_away_after_tank_2_fails() -> void:
	build("translunar_coast")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.eps.cm_power", 1)
	run(1.0, false)
	var eps: Node = rt.systems["eps"]
	eps.fail_o2_tank(2)
	var t0 := SimClock.get_seconds
	assert_true(run_until(func() -> bool: return float(Bus.get_value("eps.fc2_kw", 1.0)) <= 0.0, 4.0 * 3600.0, 60.0),
		"fuel cell 2 stops")
	assert_almost_eq(SimClock.get_seconds - t0, eps.TANK1_LEAK_S, 300.0, "2 h 20 min on")
	assert_eq(float(Bus.get_value("eps.o2_tank1_kg")), 0.0, "tank 1 empty")


## LM JETT from the CM: the docking tunnel's pressure pushed Apollo 13's
## CM back 1.88 ft/s (MSC-02680, section 6.4.1).
func test_lm_jett_from_the_cm_pushes_it_back() -> void:
	build("translunar_coast")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.cm_sm_sep", false)
	assert_eq(rt.dynamics.config, "cm_lm", "the SM gone, the LM on the CM")
	assert_eq(Bus.get_value("dock.state"), "docked")
	var v0 := rt.dynamics.traj.vel()
	var x := rt.dynamics.attitude.eci_from_body() * Vector3.RIGHT
	Bus.set_value("ctl.seq.lm_jett", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	assert_eq(rt.dynamics.config, "cm")
	var push := (rt.dynamics.traj.vel() - v0).dot(x)
	var want := float(Docking.params()["tunnel_impulse_ns"]) / rt.dynamics.mass
	assert_almost_eq(push, -want, 0.01, "back along its -X")


func test_a_misaligned_platform_is_off_by_its_angles() -> void:
	var imu := Imu.new()
	var m := Basis(Vector3.UP, 0.3)
	var eps := Vector3(-0.062, -0.035, 0.344) * (PI / 180.0)
	imu.misalign(m, eps)
	assert_true(imu.aligned, "the computer takes REFSMMAT for the platform")
	assert_true(imu.refsmmat.is_equal_approx(m))
	assert_almost_eq(imu.misalignment().length(), eps.length(), 1e-6, "a third of a degree")


func test_a_burns_program_leaves_the_dap_holding_where_it_ended() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	agc.hold_q = Quaternion(Vector3.UP, 1.0)
	agc.auto_active = true
	agc.change_program(0)
	assert_true(agc.hold_q.is_equal_approx(rt.dynamics.attitude.q), "the attitude the maneuver left")


func test_the_throttle_schedule_steps_through_its_legs() -> void:
	# PC+2's: 5 s at 12.6 %, 21 s at 40 %, then full.
	var sch := Dps.p40_schedule([5.0, 0.126, 21.0, 0.4, 1.0])
	assert_eq(sch, [5.0, 0.126, 21.0, 0.4, 1.0])
	assert_eq(Dps.schedule_throttle(sch, 0.0), 0.126)
	assert_eq(Dps.schedule_throttle(sch, 10.0), 0.4)
	assert_eq(Dps.schedule_throttle(sch, 30.0), 1.0)
	assert_eq(Dps.schedule_next(sch, 0.0), 5.0)
	assert_eq(Dps.schedule_next(sch, 10.0), 26.0)
	assert_eq(Dps.schedule_next(sch, 30.0), INF)
	assert_eq(Dps.p40_schedule([1.0, 0.1]).size(), 3, "not a schedule: spacecraft.json's")


func test_a_checkpoint_keeps_the_lifeboat() -> void:
	build("translunar_coast")
	var lgc := rt.lgc()
	_lm_up()
	_coarse_align(lgc, Docking.lm_gimbals(rt.agc().icdu()))
	run(120.0, false)
	lgc.uplink_refsmmat(rt.agc().imu.refsmmat)
	Bus.set_value("ctl.eps.cm_power", 0)
	Bus.set_value("ctl.lm.mode", 1)
	run(60.0, false)
	var platform := lgc.imu.platform
	var ah := float(Bus.get_value("lm.eps.batt_ah"))
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_true(bool(Bus.get_value("lm.sys.powered")), "the LM powered")
	assert_true(lgc.is_powered())
	assert_true(lgc.imu.aligned, "its platform aligned")
	assert_eq(lgc.imu.mode, "operate", "not caged by the restore")
	assert_true(lgc.imu.platform.is_equal_approx(platform))
	assert_almost_eq(float(Bus.get_value("lm.eps.batt_ah")), ah, 1e-6)
	assert_false(bool(Bus.get_value("sys.powered")), "the CM still dark")
	run(10.0, false)
	assert_true(lgc.imu.aligned, "and it stays so")

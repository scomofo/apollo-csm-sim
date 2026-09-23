## The LM's own systems (slice 3b): its computer beside the CMC, its RCS
## (P41, P47), staging and the ascent engine (P42), and its digital
## autopilot. Each test undocks Eagle in lunar orbit first: the LGC powers
## up as the LM undocks.
extends SimTest

## One LM RCS jet, N (data/spacecraft.json "lm_rcs").
const JET_N := 444.8


func _undock() -> void:
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)


## The angle between two attitudes, degrees, good to small angles.
func _angle_deg(a: Quaternion, b: Quaternion) -> float:
	var e := (a.inverse() * b).normalized()
	return rad_to_deg(2.0 * asin(minf(Vector3(e.x, e.y, e.z).length(), 1.0)))


func _isp_dv_kg(mass: float, dv: float, isp: float) -> float:
	return mass * (1.0 - exp(-dv / (isp * Units.G0)))


func test_docked_the_lgc_is_dark_and_the_lm_inert() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.lm.rhc", Vector3(1.0, 0.0, 0.0))
	Bus.set_value("ctl.lm.thc", Vector3(1.0, 0.0, 0.0))
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(5.0, false)
	assert_eq(str(Bus.get_value("lm.dsky.prog")), "", "the LGC's DSKY is dark")
	assert_eq(Bus.get_value("lm.rcs.force_body"), Vector3.ZERO, "no LM jets fire")
	assert_eq(Bus.get_value("lm.rcs.torque_body"), Vector3.ZERO)
	assert_eq(float(Bus.get_value("lm.dps.thrust_n")), 0.0, "nor its engine")
	assert_almost_eq(float(Bus.get_value("lm.rcs.prop_kg")), 287.0, 1e-6, "its tanks untouched")
	assert_almost_eq(rt.dynamics.mass - SpacecraftData.total_mass("csm", float(Bus.get_value("sps.prop_kg")),
		float(Bus.get_value("rcs.sm_prop_kg")), float(Bus.get_value("rcs.cm_prop_kg")), 0.0), 15103.0, 1e-6,
		"the docked LM weighs its full 15,103 kg in the stack")
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)
	Bus.set_value("ctl.lm.engine_arm", 0)
	_undock()
	assert_eq(str(Bus.get_value("lm.dsky.prog")), "00", "undocked, the LGC powers up in P00")


func test_the_lgc_and_the_cmc_keep_their_own_dskys() -> void:
	build("lunar_orbit")
	_undock()
	var lgc := rt.lgc()
	keys("V37E30E", lgc)
	assert_eq(lgc.program, 30, "LGC P30")
	assert_eq([Bus.get_value("lm.dsky.prog"), Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")],
		["30", "06", "33"], "on the LGC's DSKY")
	assert_eq(int(Bus.get_value("lm.guid.program")), 30)
	assert_eq(rt.agc().program, 0, "the CMC stays in P00")
	assert_eq(str(Bus.get_value("dsky.prog")), "00")
	keys("V16N62E")
	assert_eq(str(Bus.get_value("dsky.noun")), "62", "V16N62 on the CMC")
	assert_eq(str(Bus.get_value("lm.dsky.noun")), "33", "leaves the LGC's display alone")
	keys("V34E", lgc)
	keys("V37E40E", lgc)
	assert_eq(lgc.program, 0, "no P40 without a maneuver")
	assert_true(Bus.get_value("lm.dsky.lamp.prog"), "PROG on the LGC's DSKY")
	assert_false(Bus.get_value("dsky.lamp.prog"), "not on the CMC's")


func test_undocked_the_lm_holds_the_attitude_it_undocked_in() -> void:
	build("lunar_orbit")
	_undock()
	var q0: Quaternion = rt.dynamics.lm.attitude.q
	var steps := SimClock.step_count
	run(600.0)
	assert_lt(_angle_deg(q0, rt.dynamics.lm.attitude.q), 1e-4, "held")
	assert_eq(rt.dynamics.lm.attitude.omega, Vector3.ZERO, "without a jet firing")
	assert_almost_eq(float(Bus.get_value("lm.rcs.prop_kg")), 287.0, 1e-6)
	assert_false(Bus.get_value("lm.guid.dap_busy"))
	assert_lt(SimClock.step_count - steps, 700, "and both vehicles coast")


func test_the_aca_turns_the_lm_and_the_dap_holds_it() -> void:
	build("lunar_orbit")
	_undock()
	var lm := rt.dynamics.lm
	Bus.set_value("ctl.lm.rhc", Vector3(0.0, 1.0, 0.0))
	run(10.0, false)
	assert_almost_eq(lm.attitude.omega.y, deg_to_rad(2.0), deg_to_rad(0.01), "pitching at 2°/s")
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(30.0, false)
	assert_lt(lm.attitude.omega.length(), deg_to_rad(0.01), "stopped")
	var held: Quaternion = lm.attitude.q
	run(600.0)
	assert_lt(_angle_deg(held, lm.attitude.q), 0.2, "and held within the deadband")
	# A knock: the DAP nulls it and brings the LM back.
	lm.attitude.omega = Vector3(0.01, -0.01, 0.005)
	run(60.0, false)
	assert_lt(lm.attitude.omega.length(), deg_to_rad(0.01), "rates nulled")
	assert_lt(_angle_deg(held, lm.attitude.q), 0.2, "back at its hold")
	assert_lt(float(Bus.get_value("lm.rcs.prop_kg")), 287.0, "on the LM's RCS")


func test_p41_burns_on_the_lm_rcs() -> void:
	build("lunar_orbit")
	_undock()
	var rcs0 := float(Bus.get_value("lm.rcs.prop_kg"))
	var m0 := rt.dynamics.lm.mass
	rt.lgc().uplink_maneuver(SimClock.get_seconds + 600.0, Vector3(0.5, 0.0, 0.0))
	var push := {"x": 0.0}
	var dv := fly_lm_pad(41, 0, func() -> void:
		var f: Vector3 = Bus.get_value("lm.rcs.force_body", Vector3.ZERO)
		push["x"] = maxf(push["x"], f.x))
	assert_almost_eq(dv, 0.5, 0.01, "0.5 m/s on the RCS")
	assert_almost_eq(float(push["x"]), 4.0 * JET_N, 0.1, "four +X jets, two from each system")
	assert_eq(int(Bus.get_value("lm.dps.ignitions")), 0, "the DPS stays cold")
	var used := rcs0 - float(Bus.get_value("lm.rcs.prop_kg"))
	assert_gt(used, _isp_dv_kg(m0, dv, 290.0), "the translation's propellant")
	assert_lt(used, 10.0, "and a little more for the auto maneuver")


func test_p47_monitors_a_translation_on_the_ttca() -> void:
	build("lunar_orbit")
	_undock()
	var lgc := rt.lgc()
	keys("V37E47E", lgc)
	assert_eq(str(Bus.get_value("lm.dsky.noun")), "83", "V16N83")
	var m := rt.dynamics.lm.mass
	var range0 := float(Bus.get_value("dock.range_m"))
	# Back away from Columbia's probe: -X, the LM's +X faces it.
	Bus.set_value("ctl.lm.thc", Vector3(-1.0, 0.0, 0.0))
	run(2.0, false)
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)
	run(1.0, false)
	assert_gt(float(Bus.get_value("dock.range_m")), range0 + 0.3, "Eagle backs away")
	var n83: Array = lgc.noun_values(83)
	assert_almost_eq(float(n83[0]), -4.0 * JET_N * 2.0 / m, 0.001, "-X ΔV for two seconds of -X translation")
	assert_almost_eq(float(n83[1]), 0.0, 0.001)
	assert_almost_eq(float(n83[2]), 0.0, 0.001)
	assert_eq(rt.agc().noun_values(83), [0.0, 0.0, 0.0], "the CMC felt none of it")


func test_staging_and_p42_on_the_ascent_engine() -> void:
	build("lunar_orbit")
	_undock()
	run(60.0)
	var d := rt.dynamics
	var port0: Vector3 = Docking.relative(d.traj, d.attitude, d.lm)["d"]
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	assert_eq(d.lm.config, "lm_ascent", "staged")
	assert_eq(str(Bus.get_value("lm.dyn.config")), "lm_ascent")
	assert_almost_eq(d.lm.mass, 4821.0, 1e-6, "the ascent stage with full tanks")
	var port1: Vector3 = Docking.relative(d.traj, d.attitude, d.lm)["d"]
	assert_lt((port1 - port0).length(), 0.002, "the docking port stays where it was")
	assert_true(Bus.has_channel("mission.event.lm_staging"))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "staging")
	Bus.set_value("ctl.lm.stage", false)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	assert_eq(rt.sequencer.events.filter(func(e: Dictionary) -> bool: return e["id"] == "lm_staging").size(), 1,
		"staging only once")
	var aps0 := float(Bus.get_value("lm.aps.prop_kg"))
	var m0 := d.lm.mass
	rt.lgc().uplink_maneuver(SimClock.get_seconds + 600.0, Vector3(10.0, 0.0, 0.0))
	var dv := fly_lm_pad(42, 1)
	assert_almost_eq(dv, 10.0, 0.05, "10 m/s on the APS")
	assert_eq(int(Bus.get_value("lm.aps.ignitions")), 1, "one APS start")
	assert_eq(int(Bus.get_value("lm.dps.ignitions")), 0, "the descent engine left behind unfired")
	var used := aps0 - float(Bus.get_value("lm.aps.prop_kg"))
	assert_almost_eq(used, _isp_dv_kg(m0, dv, 311.0), 0.5, "APS propellant as the rocket equation has it")
	assert_almost_eq(float(Bus.get_value("lm.dyn.apo_alt_m")) / 1000.0, 157.0, 3.0, "a higher apocynthion")

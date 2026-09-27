extends SimTest


func test_checkpoint_round_trip_through_json_reproduces_the_flight() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	rt.agc().uplink_maneuver(SimClock.get_seconds + 1800.0, Vector3(10.0, 0.0, 0.0))
	keys("V37E30EPPP")
	run(300.0)
	var text := JSON.stringify(rt.snapshot())
	run(900.0)
	var expect := rt.dynamics.traj.s.duplicate()
	var expect_t := SimClock.get_seconds
	# Rebuild from scratch and restore.
	build("")
	var err := rt.restore(JSON.parse_string(text))
	assert_eq(err, "")
	assert_true(rt.agc().maneuver_valid, "stored maneuver restored")
	assert_eq(rt.dynamics.config, "csm")
	run(900.0)
	# A restored run's first step is a fine one (SimClock.restore()), so
	# its coast steps fall 0.02 s off the original's; the Moon's field
	# makes the flights part by millimetres for it, and the steps' sum by
	# microseconds.
	assert_almost_eq(SimClock.get_seconds, expect_t, 1e-4)
	var d := Vector3(rt.dynamics.traj.s[0] - expect[0], rt.dynamics.traj.s[1] - expect[1], rt.dynamics.traj.s[2] - expect[2])
	assert_lt(d.length(), 1.0, "same trajectory after restore")


func test_restore_rejects_foreign_checkpoints() -> void:
	build("parking_orbit")
	var snap := rt.snapshot()
	snap["mission_id"] = "apollo_13"
	assert_string_contains(rt.restore(snap), "apollo_13")
	snap = rt.snapshot()
	snap["vehicles"]["csm"].erase("dynamics")
	assert_string_contains(rt.restore(snap), "vehicles.csm.dynamics")


func test_a_checkpoint_keeps_each_vehicle_under_its_name() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	assert_eq(snap["schema_version"], 11)
	assert_eq(snap["vehicles"].keys(), ["csm"], "docked, the LM is part of the CSM's csm_lm")
	assert_eq(snap["vehicles"]["csm"]["dynamics"]["config"], "csm_lm")
	assert_has(snap["vehicles"]["csm"]["systems"], "agc")
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	snap = rt.snapshot()
	assert_eq(snap["vehicles"].keys(), ["csm", "lm"], "the LM flies free")
	assert_eq(snap["vehicles"]["lm"]["dynamics"]["config"], "lm")


func test_a_checkpoint_from_before_the_vehicles_map_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 1 kept one vehicle's dynamics and systems at the top level.
	snap["schema_version"] = 1
	snap["dynamics"] = snap["vehicles"]["csm"]["dynamics"]
	snap["systems"] = snap["vehicles"]["csm"]["systems"]
	snap.erase("vehicles")
	assert_eq(rt.restore(snap), "checkpoint schema 1, expected 11")


func test_a_checkpoint_from_before_the_rendezvous_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 2's LGC had no rendezvous state.
	snap["schema_version"] = 2
	snap["vehicles"]["csm"]["systems"]["lgc"].erase("rendezvous")
	assert_eq(rt.restore(snap), "checkpoint schema 2, expected 11")


func test_a_checkpoint_from_before_the_timeline_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 3's Mission Control had no planned times or timeline.
	snap["schema_version"] = 3
	snap["mission"].erase("plan")
	snap["mission"].erase("timeline_done")
	assert_eq(rt.restore(snap), "checkpoint schema 3, expected 11")


func test_the_lms_systems_come_back_with_it() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	# Turn the LM a little on its RCS, stage it, and store a maneuver.
	Bus.set_value("ctl.lm.rhc", Vector3(0.0, 0.0, 1.0))
	run(3.0, false)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	Bus.set_value("ctl.lm.stage", true)
	run(1.0, false)
	rt.lgc().uplink_maneuver(SimClock.get_seconds + 1800.0, Vector3(3.0, 0.0, 0.0))
	keys("V37E30EPPP", rt.lgc())
	run(60.0)
	var rcs := float(Bus.get_value("lm.rcs.prop_kg"))
	var mass := rt.dynamics.lm.mass
	var tig := rt.lgc().maneuver_tig
	var text := JSON.stringify(rt.snapshot())
	run(900.0)
	var expect := rt.dynamics.lm.traj.s.duplicate()
	var expect_t := SimClock.get_seconds
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "the ascent stage")
	assert_almost_eq(rt.dynamics.lm.mass, mass, 1e-6)
	assert_lt(rcs, 287.0, "some RCS propellant used")
	assert_almost_eq(float(Bus.get_value("lm.rcs.prop_kg")), rcs, 1e-6, "and still used")
	assert_true(rt.lgc().maneuver_valid, "the LGC's stored maneuver")
	assert_almost_eq(rt.lgc().maneuver_tig, tig, 1e-6)
	assert_false(rt.agc().maneuver_valid, "the CMC's none")
	run(expect_t - SimClock.get_seconds)
	var lag := expect_t - SimClock.get_seconds
	var d := Vector3(rt.dynamics.lm.traj.s[0] - expect[0], rt.dynamics.lm.traj.s[1] - expect[1], rt.dynamics.lm.traj.s[2] - expect[2])
	d -= Vector3(rt.dynamics.lm.traj.s[3], rt.dynamics.lm.traj.s[4], rt.dynamics.lm.traj.s[5]) * lag
	assert_lt(d.length(), 1.0, "the LM flies on as it did")


func test_the_lgcs_rendezvous_state_comes_back_as_it_was() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	var lgc := rt.lgc()
	lgc.uplink_rendezvous(300000.0, 305000.0)
	lgc.rr_marks = 3
	var text := JSON.stringify(rt.snapshot())
	# Later, in the same runtime: P20 on, more marks and other times.
	lgc.rr_nav = true
	lgc.rr_marks = 9
	lgc.rdv_csi_tig = 310000.0
	lgc.rdv_cdh_tig = 312000.0
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_same(rt.lgc(), lgc, "the same LGC")
	assert_false(lgc.rr_nav, "P20 off, as it was")
	assert_eq(lgc.rr_marks, 3)
	assert_eq([lgc.rdv_csi_tig, lgc.rdv_tpi_tig], [300000.0, 305000.0], "the uplinked times")
	assert_eq(lgc.rdv_cdh_tig, 0.0, "no CDH time: the one set after the checkpoint is gone")


func test_the_lms_systems_ride_with_the_vehicle_that_carries_them() -> void:
	build("lunar_orbit")
	var systems: Dictionary = rt.snapshot()["vehicles"]["csm"]["systems"]
	for k in ["agc", "lgc", "lm_rcs", "dps", "aps", "lr", "rr"]:
		assert_has(systems, k, "docked, the CSM's entry carries the LM's systems")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	var snap := rt.snapshot()
	assert_eq(snap["vehicles"]["lm"]["systems"].keys(), ["lgc", "lm_rcs", "dps", "aps", "lr", "rr"], "free, the LM's own entry")
	assert_does_not_have(snap["vehicles"]["csm"]["systems"], "lgc")
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	assert_does_not_have(rt.snapshot()["vehicles"]["csm"]["systems"], "lgc", "after LM JETT, gone with the LM")
	# A docked LM that has used propellant keeps it through a checkpoint,
	# and the stack weighs it.
	build("lunar_orbit")
	rt.systems["lm_rcs"].restore({"systems": [100.0, 143.5]})
	run(SimClock.FIXED_DT, false)
	var mass := rt.dynamics.mass
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_almost_eq(float(Bus.get_value("lm.rcs.prop_kg")), 243.5, 1e-6, "the LM's RCS as it was")
	run(SimClock.FIXED_DT, false)
	assert_almost_eq(rt.dynamics.mass, mass, 0.01, "and the stack's mass with it")


func test_a_checkpoint_from_the_circular_moon_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 4's states were in the circular model's ECI, not the ICRF.
	snap["schema_version"] = 4
	assert_eq(rt.restore(snap), "checkpoint schema 4, expected 11")


func test_a_checkpoint_from_before_the_cmcs_own_state_vector_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 5's CMC read truth, and the flight had no dispersions.
	snap["schema_version"] = 5
	assert_eq(rt.restore(snap), "checkpoint schema 5, expected 11")


func test_a_checkpoint_from_before_the_imu_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 6's CMC read its attitude and sensed ΔV straight, on no platform.
	snap["schema_version"] = 6
	assert_eq(rt.restore(snap), "checkpoint schema 6, expected 11")


func test_a_checkpoint_from_before_the_navigation_filter_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 7's CMC had no filter, and P22 and P23 no state.
	snap["schema_version"] = 7
	assert_eq(rt.restore(snap), "checkpoint schema 7, expected 11")


func test_a_checkpoint_from_before_the_moons_field_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 8's trajectories held no sample of the Moon's field.
	snap["schema_version"] = 8
	assert_eq(rt.restore(snap), "checkpoint schema 8, expected 11")


func test_a_checkpoint_from_before_the_samples_thrust_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 9's field samples didn't say which thrust they were taken for.
	snap["schema_version"] = 9
	assert_eq(rt.restore(snap), "checkpoint schema 9, expected 11")


func test_a_checkpoint_from_before_the_iterative_guidance_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 10's IU held a yaw and an energy, not a target conic.
	snap["schema_version"] = 10
	assert_eq(rt.restore(snap), "checkpoint schema 10, expected 11")


func test_the_cmcs_state_vector_and_the_dispersions_come_back_from_a_checkpoint() -> void:
	build("translunar_coast")
	run(3600.0)
	var text := JSON.stringify(rt.snapshot())
	var nav := rt.agc().nav.s.duplicate()
	var nav_t := rt.agc().nav.t
	var vent := rt.dynamics.vent_force
	var jets := rt.dynamics.jet_imbalance
	# The next tracking error the ground would draw.
	var truth := rt.dynamics.traj.clone()
	var err := _error(rt.sequencer.tracked_state(truth), truth)
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	var agc := rt.agc()
	assert_almost_eq(agc.nav.t, nav_t, 1e-6, "the CMC's state vector's time")
	for i in 6:
		assert_almost_eq(agc.nav.s[i], nav[i], absf(nav[i]) * 1e-12 + 1e-9, "and its component %d" % i)
	assert_almost_eq(rt.dynamics.vent_force, vent, Vector3.ONE * 1e-9, "the CSM's vent force")
	assert_almost_eq(rt.dynamics.jet_imbalance, jets, Vector3.ONE * 1e-9, "and its jets' imbalance")
	truth = rt.dynamics.traj.clone()
	assert_almost_eq(_error(rt.sequencer.tracked_state(truth), truth), err, Vector3.ONE * 1e-6,
		"the ground draws the tracking error it would have")


func _error(tracked: Trajectory, truth: Trajectory) -> Vector3:
	return tracked.pos() - truth.pos()


func test_the_imu_and_a_p52_between_its_marks_come_back_from_a_checkpoint() -> void:
	build("translunar_coast")
	run(3600.0)
	var agc := rt.agc()
	keys("V37E52EV22E3EPP")
	assert_eq(agc.step_name, "star", "P52 option 3 has its stars")
	keys("P")
	centre_star(agc.align_stars[0])
	mark()
	assert_eq(agc.align_marks.size(), 1, "the first star marked")
	var text := JSON.stringify(rt.snapshot())
	var off := agc.imu.misalignment()
	var stars: Array = agc.align_stars.duplicate()
	var first: Vector3 = agc.align_marks[0]
	var shaft := optics().shaft_deg
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	agc = rt.agc()
	assert_eq([agc.program, agc.step_name], [52, "star"], "P52 at the second star")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun")], ["01", "70"], "V01N70 on the DSKY")
	assert_eq(agc.align_stars, stars)
	assert_almost_eq(agc.align_marks[0], first, Vector3.ONE * 1e-6, "the first mark")
	assert_almost_eq(agc.imu.misalignment(), off, Vector3.ONE * 1e-9, "the platform where it was")
	assert_almost_eq(optics().shaft_deg, shaft, 1e-9, "and the optics")
	# It carries on: the second star, N05, N93 and the torquing.
	keys("P")
	centre_star(stars[1])
	mark()
	keys("PP")
	assert_true(agc.imu.aligned)
	assert_lt(misalignment_deg(), 0.02, "realigned after the restore")


func test_the_navigation_filter_and_a_p23_mark_at_n49_come_back_from_a_checkpoint() -> void:
	build("transearth_coast")
	run(3600.0)
	var agc := rt.agc()
	var star := 0
	for c in Stars.codes():
		var m := NavFilter.star_horizon(rt.dynamics.traj, Stars.direction(c), "earth")
		if not m.is_empty() and rad_to_deg(float(m["q"])) > 15.0 and rad_to_deg(float(m["q"])) < 50.0:
			star = c
			break
	keys("V37E23E")
	p23_mark(star, 1)
	# The second mark, waiting at N49.
	keys("PP")
	assert_true(run_until(func() -> bool: return agc.step_name == "mark", 600.0, 1.0, false), "V51")
	superimpose(star, "earth")
	mark()
	assert_eq(agc.step_name, "n49")
	var text := JSON.stringify(rt.snapshot())
	var p: PackedFloat64Array = agc.nav_filter.p.duplicate()
	var dx: PackedFloat64Array = agc.sight_pending["dx"]
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	agc = rt.agc()
	assert_eq([agc.program, agc.step_name], [23, "n49"], "P23 at N49")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun"), Bus.get_value("dsky.flash")], ["06", "49", true], "V06N49")
	assert_eq([agc.sight_star, agc.sight_horizon, agc.sight_marks], [star, 1, 1])
	assert_false(agc.nav_filter.stale, "the filter as it was")
	for i in 36:
		assert_almost_eq(agc.nav_filter.p[i], p[i], absf(p[i]) * 1e-12 + 1e-12, "P[%d]" % i)
	for i in 6:
		assert_almost_eq((agc.sight_pending["dx"] as PackedFloat64Array)[i], dx[i], absf(dx[i]) * 1e-12 + 1e-12, "the update [%d]" % i)
	keys("P")
	assert_eq([agc.step_name, agc.sight_marks], ["n70", 2], "taken in after the restore")

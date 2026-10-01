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
	assert_eq(snap["schema_version"], 36)
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
	assert_eq(rt.restore(snap), "checkpoint schema 1, expected 36")


func test_a_checkpoint_from_before_the_rendezvous_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 2's LGC had no rendezvous state.
	snap["schema_version"] = 2
	snap["vehicles"]["csm"]["systems"]["lgc"].erase("rendezvous")
	assert_eq(rt.restore(snap), "checkpoint schema 2, expected 36")


func test_a_checkpoint_from_before_the_timeline_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 3's Mission Control had no planned times or timeline.
	snap["schema_version"] = 3
	snap["mission"].erase("plan")
	snap["mission"].erase("timeline_done")
	assert_eq(rt.restore(snap), "checkpoint schema 3, expected 36")


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
	rt.lgc().uplink_throttle([26.0, 0.1, 1.0])
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
	assert_eq(rt.lgc().p40_schedule, [26.0, 0.1, 1.0], "and its PAD's throttle schedule")
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
	lgc.p20.marks = 3
	var text := JSON.stringify(rt.snapshot())
	# Later, in the same runtime: P20 on, more marks and other times.
	lgc.rr_nav = true
	lgc.p20.marks = 9
	lgc.rdv_csi_tig = 310000.0
	lgc.rdv_cdh_tig = 312000.0
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_same(rt.lgc(), lgc, "the same LGC")
	assert_false(lgc.rr_nav, "P20 off, as it was")
	assert_eq(lgc.p20.marks, 3)
	assert_eq([lgc.rdv_csi_tig, lgc.rdv_tpi_tig], [300000.0, 305000.0], "the uplinked times")
	assert_eq(lgc.rdv_cdh_tig, 0.0, "no CDH time: the one set after the checkpoint is gone")


func test_the_lms_systems_ride_with_the_vehicle_that_carries_them() -> void:
	build("lunar_orbit")
	var systems: Dictionary = rt.snapshot()["vehicles"]["csm"]["systems"]
	for k in ["agc", "lm_eps", "lgc", "ags", "lm_rcs", "dps", "aps", "lr", "rr", "aot", "lm_cw"]:
		assert_has(systems, k, "docked, the CSM's entry carries the LM's systems")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	var snap := rt.snapshot()
	assert_eq(snap["vehicles"]["lm"]["systems"].keys(), ["lm_eps", "lgc", "ags", "lm_rcs", "dps", "aps", "lr", "rr", "aot", "lm_cw"],
		"free, the LM's own entry")
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
	assert_eq(rt.restore(snap), "checkpoint schema 4, expected 36")


func test_a_checkpoint_from_before_the_cmcs_own_state_vector_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 5's CMC read truth, and the flight had no dispersions.
	snap["schema_version"] = 5
	assert_eq(rt.restore(snap), "checkpoint schema 5, expected 36")


func test_a_checkpoint_from_before_the_imu_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 6's CMC read its attitude and sensed ΔV straight, on no platform.
	snap["schema_version"] = 6
	assert_eq(rt.restore(snap), "checkpoint schema 6, expected 36")


func test_a_checkpoint_from_before_the_navigation_filter_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 7's CMC had no filter, and P22 and P23 no state.
	snap["schema_version"] = 7
	assert_eq(rt.restore(snap), "checkpoint schema 7, expected 36")


func test_a_checkpoint_from_before_the_moons_field_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 8's trajectories held no sample of the Moon's field.
	snap["schema_version"] = 8
	assert_eq(rt.restore(snap), "checkpoint schema 8, expected 36")


func test_a_checkpoint_from_before_the_samples_thrust_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 9's field samples didn't say which thrust they were taken for.
	snap["schema_version"] = 9
	assert_eq(rt.restore(snap), "checkpoint schema 9, expected 36")


func test_a_checkpoint_from_before_the_iterative_guidance_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 10's IU held a yaw and an energy, not a target conic.
	snap["schema_version"] = 10
	assert_eq(rt.restore(snap), "checkpoint schema 10, expected 36")


func test_a_checkpoint_from_before_the_launch_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 11 had no launch vehicle.
	snap["schema_version"] = 11
	assert_eq(rt.restore(snap), "checkpoint schema 11, expected 36")


func test_a_checkpoint_from_before_cross_product_steering_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 12 had no steered thrust direction.
	snap["schema_version"] = 12
	assert_eq(rt.restore(snap), "checkpoint schema 12, expected 36")


func test_a_checkpoint_from_before_the_entry_programs_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 13 had no entry guidance, nor the CM's roll rate.
	snap["schema_version"] = 13
	assert_eq(rt.restore(snap), "checkpoint schema 13, expected 36")


func test_a_checkpoint_from_before_the_master_alarm_circuit_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 14 had no caution and warning system.
	snap["schema_version"] = 14
	assert_eq(rt.restore(snap), "checkpoint schema 14, expected 36")


func test_a_checkpoint_from_before_the_lgcs_throttle_schedule_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 15 had no throttle schedule uplinked with a DPS burn's PAD.
	snap["schema_version"] = 15
	assert_eq(rt.restore(snap), "checkpoint schema 15, expected 36")


func test_a_checkpoint_from_before_noun_69_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 16 kept no word of noun 69 moving the LGC's landing site.
	snap["schema_version"] = 16
	assert_eq(rt.restore(snap), "checkpoint schema 16, expected 36")


func test_a_checkpoint_from_before_the_lifeboat_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 17 kept no LM batteries, AGS, docked LGC's IMU or tank leak.
	snap["schema_version"] = 17
	assert_eq(rt.restore(snap), "checkpoint schema 17, expected 36")


func test_a_checkpoint_from_before_the_failure_catalog_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 18 kept no armed or failed failures, nor the systems' failed
	# parts, and armed Apollo 13's tank from the mission.
	snap["schema_version"] = 18
	assert_eq(rt.restore(snap), "checkpoint schema 18, expected 36")


func test_a_checkpoint_from_before_the_program_alarms_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 19 kept no LGC Executive, restarts or alarm registers, nor the
	# ground's answers to the alarms.
	snap["schema_version"] = 19
	assert_eq(rt.restore(snap), "checkpoint schema 19, expected 36")


func test_a_checkpoint_from_before_the_backups_is_rejected() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	# Schema 20 kept no SCS, SPS gimbal or EMS.
	snap["schema_version"] = 20
	assert_eq(rt.restore(snap), "checkpoint schema 20, expected 36")


func test_a_checkpoint_from_before_the_launch_aborts_is_rejected() -> void:
	build("launch")
	var snap := rt.snapshot()
	# Schema 21 kept no EDS, escape tower or launch vehicle failures.
	snap["schema_version"] = 21
	assert_eq(rt.restore(snap), "checkpoint schema 21, expected 36")


func test_a_checkpoint_from_before_the_lms_aborts_is_rejected() -> void:
	build("lunar_descent")
	var snap := rt.snapshot()
	# Schema 22 kept no abort programs, abort TPIs, LM caution and warning
	# or descent helium.
	snap["schema_version"] = 22
	assert_eq(rt.restore(snap), "checkpoint schema 22, expected 36")


func test_a_checkpoint_from_before_the_lightning_is_rejected() -> void:
	build("launch", "apollo_12")
	var snap := rt.snapshot()
	# Schema 23 kept no tripped fuel cells, no SCE and no tumbled platform.
	snap["schema_version"] = 23
	assert_eq(rt.restore(snap), "checkpoint schema 23, expected 36")
	Mission.load_default()


func test_a_checkpoint_from_before_the_centre_engine_is_rejected() -> void:
	build("launch", "apollo_13")
	run(200.0, false)
	var lv: LaunchVehicle = rt.systems["lv"]
	var dv := lv.s2_dv
	assert_gt(dv, 0.0, "the S-II's velocity gain sensed")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 24 kept no S-II velocity gain for the shift's criterion.
	snap["schema_version"] = 24
	assert_eq(rt.restore(snap), "checkpoint schema 24, expected 36")
	# Schema 25 keeps it, and the IU's command still to come.
	build("", "apollo_13")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lv = rt.systems["lv"]
	assert_almost_eq(lv.s2_dv, dv, 1e-6, "the gain kept")
	assert_eq(lv.emr_cmd_at, -1.0, "the command still to come")
	assert_true(lv.failed.is_empty(), "all five burning")
	assert_almost_eq(float(rt.failures.armed.get("s2_engine_5", -1.0)), 330.65, 0.05, "the pogo still to come, at 330.65 s")
	Mission.load_default()


func test_a_checkpoint_from_before_the_lgcs_platform_is_rejected() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	var lgc := rt.lgc()
	assert_false(lgc.imu.ideal, "the LGC's platform a real one")
	# P52 option 3 by hand, on Acrux in the front detent, without the
	# maneuver, and one Y mark taken.
	keys("V37E52EV22E3EPE", lgc)
	keys("V21E00225EEP", lgc)
	assert_eq(lgc.step_name, "v50n18")
	keys("EP", lgc)
	assert_eq(lgc.step_name, "marks")
	Bus.set_value("ctl.lm.aot.mark_y", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.aot.mark_y", false)
	run(SimClock.FIXED_DT, false)
	var cdus: Vector3 = lgc.align.pairs[0]["y"]
	var mis := lgc.imu.misalignment()
	var drift := lgc.imu.drift
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 25 kept the LGC's IMU ideal, without P52.
	snap["schema_version"] = 25
	assert_eq(rt.restore(snap), "checkpoint schema 25, expected 36")
	# Schema 26 keeps the P52 between its marks, and the platform.
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(lgc.program, 52)
	assert_eq(lgc.step_name, "marks")
	assert_eq(int(lgc.align.codes[0]), 225, "Acrux in the front detent")
	assert_eq(lgc.align.pairs.size(), 1)
	assert_eq(lgc.align.pairs[0]["x"], null, "no X mark yet")
	assert_lt(((lgc.align.pairs[0]["y"] as Vector3) - cdus).length(), 1e-4, "the Y mark's CDU angles")
	assert_eq(lgc.dsky.verb, "52", "V52: the X mark wanted")
	assert_false(lgc.imu.ideal)
	assert_lt((lgc.imu.misalignment() - mis).length(), 1e-6, "the platform where it was")
	assert_lt((lgc.imu.drift - drift).length(), 1e-12, "drifting as it was")


func test_a_checkpoint_from_before_p57_is_rejected() -> void:
	build("lunar_surface")
	var lgc := rt.lgc()
	# The reticle turned, and P57 with gravity and a star, mid-GVDETER.
	Bus.set_value("ctl.lm.aot.reticle", 2)
	run(1.5, false)
	Bus.set_value("ctl.lm.aot.reticle", 0)
	run(SimClock.FIXED_DT, false)
	var reticle: float = rt.systems["aot"].reticle_deg
	keys("V37E57EPV22E3EP", lgc)
	assert_eq(lgc.step_name, "gravity")
	assert_true(run_until(func() -> bool: return lgc.imu.operating(), 120.0, 1.0, false), "the first turn done")
	run(10.0, false)
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 26 kept no P57.
	snap["schema_version"] = 26
	assert_eq(rt.restore(snap), "checkpoint schema 26, expected 36")
	# Schema 27 on keeps it where it was, the attitude stored and the reticle.
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(lgc.program, 57)
	assert_eq(lgc.step_name, "gravity")
	assert_true(lgc.surface.attitude_stored, "the attitude stored")
	assert_eq(lgc.surface.technique, 3)
	assert_almost_eq(float(rt.systems["aot"].reticle_deg), reticle, 1e-4, "the reticle's counter")
	assert_true(run_until(func() -> bool: return lgc.step_name == "n04", 300.0, 1.0, false), "GVDETER goes on to N04")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun], ["06", "04"])


## Schema 28 (slice 11c): a checkpoint taken while KALCMANU turns the LM to
## P40's burn attitude keeps the turn, and the LM comes to the attitude
## when the uninterrupted turn did.
func test_a_checkpoint_from_before_luminarys_steering_is_rejected() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	var lgc := rt.lgc()
	lgc.uplink_maneuver(SimClock.get_seconds + 900.0, Vector3(-20.0, 0.0, 5.0))
	keys("V37E30E", lgc)
	keys("PPP", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("V37E40E", lgc)
	assert_eq(lgc.step_name, "v50n18")
	keys("P", lgc)
	assert_true(lgc.kal_turning(), "KALCMANU turning to the burn attitude")
	run(10.0, false)
	assert_true(lgc.kal_turning(), "still turning")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	assert_true(run_until(func() -> bool: return lgc.step_name == "wait", 600.0, 1.0, false), "the burn attitude")
	var there := SimClock.get_seconds
	# Schema 27 kept no turn.
	snap["schema_version"] = 27
	assert_eq(rt.restore(snap), "checkpoint schema 27, expected 36")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_true(lgc.kal_turning(), "the turn restored")
	assert_true(run_until(func() -> bool: return lgc.step_name == "wait", 600.0, 1.0, false), "the burn attitude")
	assert_almost_eq(SimClock.get_seconds, there, 1.0, "there when the uninterrupted turn was")


## Schema 29 (slice 11d): a checkpoint taken with P20's first mark waiting
## at V06N49 keeps the radar's lock, the filter and the mark's change, and
## the mark is taken in after the restore.
func test_a_checkpoint_from_before_the_rendezvous_radars_errors_is_rejected() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	run(2.0, false)
	# Eagle 8 km behind Columbia on its orbit; the ground's Columbia 1.5 km
	# ahead of where it is.
	var cm := rt.dynamics.traj
	var lm := rt.dynamics.lm
	var n := cm.pos().cross(cm.vel()).normalized()
	var a := 8000.0 / cm.pos().length()
	lm.traj.set_state(cm.primary, cm.t, cm.pos().rotated(n, -a), cm.vel().rotated(n, -a))
	# Moved at once through the docking port's plane: not a contact.
	rt.dynamics._arm_contact()
	var lgc := rt.lgc()
	lgc.imu.misalign(lgc.imu.refsmmat, Vector3.ZERO)
	lgc.init_nav(lm.traj)
	var off := cm.clone()
	off.set_state(cm.primary, cm.t, cm.pos() + cm.vel().normalized() * 1500.0, cm.vel())
	lgc.uplink_csm_state(off)
	Bus.set_value("ctl.lm.mode", 2)
	Bus.set_value("ctl.lm.rr_mode", 0)
	keys("V37E20E", lgc)
	if lgc.p20.phase == "r61":
		keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.p20.phase == "n72", 300.0, 1.0, false), "locked on")
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.p20.priority == "n49", 60.0, 1.0, false), "the first mark at N49")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	var e: PackedFloat64Array = (lgc.p20.pending["e"] as PackedFloat64Array).duplicate()
	var dx: PackedFloat64Array = (lgc.p20.pending["dx"] as PackedFloat64Array).duplicate()
	var rr: RendezvousRadar = rt.systems["rr"]
	var angles := Vector2(rr.shaft, rr.trunnion)
	# Schema 28 had no radar errors and no P20 filter.
	snap["schema_version"] = 28
	assert_eq(rt.restore(snap), "checkpoint schema 28, expected 36")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	rr = rt.systems["rr"]
	assert_eq([lgc.program, lgc.p20.phase, lgc.p20.priority], [20, "track", "n49"], "P20 at N49")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun], ["06", "49"], "V06N49")
	assert_true(rr.locked and rr.data_good, "the radar still locked on")
	assert_almost_eq(Vector2(rr.shaft, rr.trunnion), angles, Vector2.ONE * 1e-6, "on the same angles")
	var dx2: PackedFloat64Array = lgc.p20.pending["dx"]
	var e2: PackedFloat64Array = lgc.p20.pending["e"]
	for i in dx.size():
		assert_almost_eq(dx2[i], dx[i], absf(dx[i]) * 1e-12 + 1e-12, "the change [%d]" % i)
	for i in e.size():
		assert_almost_eq(e2[i], e[i], absf(e[i]) * 1e-12 + 1e-15, "E [%d]" % i)
	var err := lgc_rel_error()
	for i in 4:
		if lgc.p20.priority == "n49":
			keys("P", lgc)
	assert_eq(lgc.p20.marks, 1, "the mark taken in after the restore")
	assert_lt(lgc_rel_error(), err, "and Columbia nearer where it is")


func test_the_entry_guidance_comes_back_from_a_checkpoint_mid_roll() -> void:
	build("entry")
	var agc := rt.agc()
	keys("V37E61EPPP")
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.cmc.mode", 2)
	keys("PP")
	assert_true(run_until(func() -> bool: return agc.program >= 64, 3600.0, 30.0), "P64")
	# Hunting for the up-control, the CM rolling.
	assert_true(run_until(func() -> bool: return agc.entry.mode == "huntest" and absf(rt.dynamics.bank_rate) > 0.05,
		120.0, 0.5), "rolling in HUNTEST")
	var text := JSON.stringify(rt.snapshot())
	var e := agc.entry.snapshot()
	var bank := rt.dynamics.bank
	var rate := rt.dynamics.bank_rate
	var target := Vector2(agc.entry_lat, agc.entry_lng)
	run(20.0)
	var expect := rt.dynamics.traj.s.duplicate()
	var expect_t := SimClock.get_seconds
	var rollc := agc.entry.rollc
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	agc = rt.agc()
	assert_eq([agc.program, agc.entry.mode, agc.entry.program], [64, "huntest", 64], "P64, hunting")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun")], ["06", "74"], "V06N74")
	assert_eq(Vector2(agc.entry_lat, agc.entry_lng), target, "the target")
	for k in ["d0", "kat", "lewd", "diffold", "k2roll", "theta", "rollc"]:
		assert_almost_eq(float(agc.entry.get(k)), float(e[k]), absf(float(e[k])) * 1e-9 + 1e-12, k)
	assert_almost_eq(rt.dynamics.bank, bank, 1e-9, "the bank")
	assert_almost_eq(rt.dynamics.bank_rate, rate, 1e-9, "and its rate")
	run(expect_t - SimClock.get_seconds)
	var d := Vector3(rt.dynamics.traj.s[0] - expect[0], rt.dynamics.traj.s[1] - expect[1], rt.dynamics.traj.s[2] - expect[2])
	assert_lt(d.length(), 5.0, "the CM flies on as it did")
	assert_almost_eq(agc.entry.rollc, rollc, 1e-3, "rolled as it did")


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


func test_the_ags_comes_back_from_a_checkpoint_mid_initialization() -> void:
	build("lunar_ascent")
	var lgc := rt.lgc()
	run(float(rt.sequencer.plan["liftoff_tig"]) - 900.0 - SimClock.get_seconds)
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	AgsCrew.keys(self, "C413+10000E")
	AgsCrew.keys(self, "C400+30000E")
	run(2.0, false)
	keys("V47E", lgc)
	AgsCrew.keys(self, "C377+0000")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 29 had neither the AGS's flight program nor its DEDA nor R47.
	snap["schema_version"] = 29
	assert_eq(rt.restore(snap), "checkpoint schema 29, expected 36")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	var ags: Ags = rt.systems["ags"]
	assert_eq(lgc.r47.phase, "k", "R47 asking for the AGS's clock zero")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun, lgc.dsky.flashing], ["06", "16", true], "V06N16 flashing")
	assert_eq([ags.deda.addr_text, ags.deda.data_text], ["377", "+0000"], "the DEDA mid-entry")
	assert_true(ags.fp6.d21, "the surface flag")
	# The crew finish: the fifth digit, the DEDA's ENTR with V32E, PRO, and
	# 414+10000 while the downlist is on.
	AgsCrew.keys(self, "0")
	ags.press("ENTR")
	keys("V32E", lgc)
	keys("P", lgc)
	AgsCrew.keys(self, "C414+10000E")
	assert_true(run_until(func() -> bool: return ags.s14 == 0, 10.0, 0.5, false), "the downlist taken")
	assert_true(ags.fp6.initialized, "the AGS initialized")
	assert_almost_eq(ags.fp6.t, SimClock.get_seconds - lgc.r47.agsk, AgsFp6.CYCLE, "its clock zeroed at V32")
	var m := ags.frame.transposed()
	var s: PackedFloat64Array = rt.dynamics.lm.traj.s
	var truth := LgcR47._sm(m, s, 0, 1.0 / Units.FT)
	var off := Vector3(ags.fp6.r[0] - float(truth[0]), ags.fp6.r[1] - float(truth[1]), ags.fp6.r[2] - float(truth[2]))
	# The CDUs' angles, 40 arcsec a count, and the platform's own error.
	assert_lt(off.length(), 1500.0, "the AGS has Eagle within its alignment's error (ft)")


func test_r47s_downlist_comes_back_from_a_checkpoint_mid_send() -> void:
	build("lunar_ascent")
	var lgc := rt.lgc()
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	AgsCrew.keys(self, "C413+10000E")
	AgsCrew.keys(self, "C400+30000E")
	run(2.0, false)
	# The AEA clock's zero now (377+00000, its ENTR with V32E), and PRO.
	keys("V47E", lgc)
	AgsCrew.keys(self, "C377+00000")
	(rt.systems["ags"] as Ags).press("ENTR")
	keys("V32E", lgc)
	keys("P", lgc)
	run(4.0, false)
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 30 had R47 sending but not the state vectors it sent.
	snap["schema_version"] = 30
	assert_eq(rt.restore(snap), "checkpoint schema 30, expected 36")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	var ags: Ags = rt.systems["ags"]
	assert_eq(lgc.r47.phase, "send", "R47 sending")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun, lgc.dsky.flashing], ["06", "16", false], "V06N16 steady")
	assert_false((Bus.get_value("lm.lgc.ags_downlink", {}) as Dictionary).is_empty(), "the downlist back on")
	AgsCrew.keys(self, "C414+10000E")
	assert_true(run_until(func() -> bool: return ags.s14 == 0, 10.0, 0.5, false), "the downlist taken")
	assert_true(ags.fp6.initialized, "the AGS initialized")
	assert_almost_eq(ags.fp6.t, SimClock.get_seconds - lgc.r47.agsk, AgsFp6.CYCLE, "its clock from the zero")
	var s: PackedFloat64Array = rt.dynamics.lm.traj.s
	var truth := LgcR47._sm(ags.frame.transposed(), s, 0, 1.0 / Units.FT)
	var off := Vector3(ags.fp6.r[0] - float(truth[0]), ags.fp6.r[1] - float(truth[1]), ags.fp6.r[2] - float(truth[2]))
	assert_lt(off.length(), 1500.0, "the AGS has Eagle within its alignment's error (ft)")
	assert_true(run_until(func() -> bool: return lgc.r47.phase == "done", LgcR47.SEND_S, 1.0, false), "V50N16 after the 20 s")
	assert_true((Bus.get_value("lm.lgc.ags_downlink", {}) as Dictionary).is_empty(), "and the downlist off")


func test_the_lgcs_mode_register_and_the_abort_switch_come_back_from_a_checkpoint() -> void:
	build("lunar_descent")
	var lgc := rt.lgc()
	# MODREG 71, as Apollo 14's crew keyed it before PDI, LETABORT set, and
	# the ABORT switch shorted.
	keys("V21N01E1010E107E", lgc)
	keys("V25N07E105E400E1E", lgc)
	assert_true(rt.failures.fail("lm_abort_switch"))
	run(0.2, false)
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 31 had neither the mode register nor the switch's short.
	snap["schema_version"] = 31
	assert_eq(rt.restore(snap), "checkpoint schema 31, expected 36")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	run(0.2, false)
	assert_eq([lgc.erasable.modreg, lgc.dsky.prog], [71, "71"], "MODREG 71 on PROG")
	assert_true(lgc.erasable.letabort, "LETABORT set")
	assert_true(bool(Bus.get_value("lm.lgc.abort_bit")), "the switch still shorted")
	Bus.set_value("ctl.lm.panel_tap", true)
	run(0.2, false)
	Bus.set_value("ctl.lm.panel_tap", false)
	assert_false(bool(Bus.get_value("lm.lgc.abort_bit")), "a tap clears it")
	keys("V21N01E1010E77E", lgc)
	assert_eq([lgc.erasable.modreg, lgc.dsky.prog], [63, "63"], "MODREG 63")


func test_the_landing_radars_scale_and_its_breaker_come_back_from_a_checkpoint() -> void:
	build("lunar_descent", "apollo_14")
	var lr: LandingRadar = rt.systems["lr"]
	assert_true(rt.failures.recur("lm_lr_scale"), "Apollo 14's radar in low scale")
	run(1.0, false)
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 32 had neither the radar's scale nor its breaker's cycle.
	snap["schema_version"] = 32
	assert_eq(rt.restore(snap), "checkpoint schema 32, expected 36")
	build("", "apollo_14")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lr = rt.systems["lr"]
	run(1.0, false)
	assert_true(lr.low_scale, "the scale still low")
	# The breaker cycled: in high scale, its trackers searching.
	Bus.set_value("ctl.lm.cb_ldg_rdr", false)
	run(1.0, false)
	Bus.set_value("ctl.lm.cb_ldg_rdr", true)
	run(1.0, false)
	var power_get := lr.power_get
	assert_almost_eq(power_get, SimClock.get_seconds - 1.0, 0.05, "on again a second ago")
	text = JSON.stringify(rt.snapshot())
	build("", "apollo_14")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lr = rt.systems["lr"]
	assert_eq([lr.low_scale, lr.powered], [false, true], "high scale, on")
	assert_almost_eq(lr.power_get, power_get, 1e-6, "its search from the same moment")
	Mission.load_default()


func test_the_transposition_and_docking_comes_back_from_a_checkpoint_mid_retraction() -> void:
	build("parking_orbit", "apollo_14")
	var d := rt.dynamics
	rt.sequencer.call("_separate", true)
	assert_true(rt.failures.recur("csm_capture_latches"), "Kitty Hawk's capture latches failed")
	# Turned about in CMC MODE FREE, the probe 2 cm over the drogue,
	# closing at 0.05 m/s.
	Bus.set_value("ctl.cmc.mode", 0)
	var n := Basis(d.lm.attitude.q).x
	d.attitude.q = (d.attitude.q * Quaternion(Vector3(0, 0, 1), PI)).normalized()
	d.attitude.omega = Vector3.ZERO
	var at := d.lm.traj.pos() + n * (Docking.lm_port_m("lm_sivb") + 0.02 + float(Docking.params()["csm_port_m"]))
	var v := d.lm.traj.vel() - n * 0.05
	for i in 3:
		d.traj.s[i] = at[i]
		d.traj.s[3 + i] = v[i]
	d.call("_arm_contact")
	# Held in under +X, and PROBE RETRACT.
	Bus.set_value("ctl.thc", Vector3(1.0, 0.0, 0.0))
	run(2.0, false)
	assert_eq([str(Bus.get_value("dock.state")), str((Bus.get_value("dock.contact") as Dictionary).get("fault"))], ["tde", "latches"])
	Bus.set_value("ctl.seq.probe_retract", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.probe_retract", false)
	var pushed := SimClock.get_seconds
	run(2.0, false)
	assert_true(bool(Bus.get_value("dock.retracting")), "retracting")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 33 had neither the probe's latches nor the LM on the S-IVB.
	snap["schema_version"] = 33
	assert_eq(rt.restore(snap), "checkpoint schema 33, expected 36")
	build("", "apollo_14")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	d = rt.dynamics
	assert_eq([str(Bus.get_value("dock.state")), d.config, d.lm.config], ["tde", "csm", "lm_sivb"], "the LM on the S-IVB")
	assert_true(bool(Bus.get_value("dock.probe.latches_failed")), "the capture latches still failed")
	assert_true(bool(Bus.get_value("dock.retracting")), "still retracting")
	Bus.set_value("ctl.thc", Vector3(1.0, 0.0, 0.0))
	assert_true(run_until(func() -> bool: return str(Bus.get_value("dock.state")) == "docked", 5.0, SimClock.FIXED_DT, false),
		"hard dock")
	assert_almost_eq(SimClock.get_seconds - pushed, float(Docking.params()["retract_s"]), 0.05, "retract_s after the press")
	Bus.set_value("ctl.thc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_eq(d.config, "csm_lm")
	assert_false(bool(Bus.get_value("dock.probe.latches_failed")), "cleared at the hard dock")
	Mission.load_default()


func test_a_failed_main_parachute_and_a_vented_cabin_come_back_from_a_checkpoint() -> void:
	build("transearth_coast", "apollo_15")
	# Worden's EVA, the cabin vented (the timeline's "cabin"), and one of
	# the mains failed, as Apollo 15's on the way down.
	rt.sequencer.cabin_vented = true
	assert_true(rt.failures.fail("els_main"), "a main parachute")
	assert_almost_eq(float(Bus.get_value("els.main_cds_factor")), 0.79, 1e-6, "two mains' drag")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 34 had neither the ELS's failed main nor the cabin's venting.
	snap["schema_version"] = 34
	assert_eq(rt.restore(snap), "checkpoint schema 34, expected 36")
	build("", "apollo_15")
	assert_false(bool(Bus.get_value("els.main_failed")), "a new flight's mains")
	assert_false(bool(Bus.get_value("mission.cabin_vented")), "and its cabin")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_true(bool(Bus.get_value("els.main_failed")), "the main still failed")
	assert_almost_eq(float(Bus.get_value("els.main_cds_factor")), 0.79, 1e-6, "two mains' drag still")
	assert_eq(rt.failures.active.keys(), ["els_main"])
	assert_true(rt.sequencer.cabin_vented, "the cabin still vented")
	assert_true(bool(Bus.get_value("mission.cabin_vented")))
	Mission.load_default()


func test_the_sps_servo_loops_come_back_from_a_checkpoint() -> void:
	build("transearth_coast")
	# Apollo 16's secondary yaw loop, its rate feedback open, driving the
	# yaw gimbal and swinging, loop 1 the pitch; the GPI's trim set.
	assert_true(rt.failures.fail("sps_yaw_servo_2"), "the loop's rate feedback")
	for m in ["p1", "y2"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 2)
	run(SimClock.FIXED_DT, false)
	for m in ["p1", "y2"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 1)
	Bus.set_value("ctl.scs.tvc_drive_y", 2)
	Bus.set_value("ctl.scs.att_source", 1)
	var scs: Scs = rt.systems["scs"]
	scs.trim = Vector2(deg_to_rad(0.49), deg_to_rad(1.19))
	run(3.0, false)
	var sps: Sps = rt.systems["sps"]
	var cycle := sps.cycle
	assert_gt(cycle.y, 0.0, "swinging")
	var snap := rt.snapshot()
	var text := JSON.stringify(snap)
	# Schema 35 had neither the gimbal motors, the loops' failures and their
	# swing nor the GPI's trim.
	snap["schema_version"] = 35
	assert_eq(rt.restore(snap), "checkpoint schema 35, expected 36")
	build("")
	assert_eq((rt.systems["sps"] as Sps).motors, [false, false, false, false] as Array[bool], "a new flight's motors off")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	sps = rt.systems["sps"]
	assert_eq(sps.motors, [true, false, false, true] as Array[bool], "PITCH 1 and YAW 2 running")
	assert_eq(Array(sps.rate_open), ["y2"], "the loop's rate feedback still open")
	assert_almost_eq(sps.cycle.y, cycle.y, 1e-9, "and swinging as it was")
	assert_almost_eq((rt.systems["scs"] as Scs).trim, Vector2(deg_to_rad(0.49), deg_to_rad(1.19)), Vector2.ONE * 1e-9, "the trim")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 2), "TVC GMBL DRIVE YAW at 2 with it")
	assert_eq(rt.failures.active.keys(), ["sps_yaw_servo_2"])

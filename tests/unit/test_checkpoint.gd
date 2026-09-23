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
	assert_almost_eq(SimClock.get_seconds, expect_t, 1e-6)
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
	assert_eq(snap["schema_version"], 2)
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
	assert_eq(rt.restore(snap), "checkpoint schema 1, expected 2")

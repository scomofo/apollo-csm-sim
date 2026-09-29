## Slice 9a (docs/ROADMAP.md): the failure catalog. Each failure in
## data/failures.json, set in a headless flight, lights its caution, sounds
## the master alarm and changes its system as the catalog says; a
## checkpoint keeps the armed and the failed; a mission arms its own, as
## Apollo 13's tank; the instructor's page on the wrist menu fails any;
## and a failure opens its malfunction procedure. Apollo 13's flight, with
## its tank on the catalog, is tests/scenarios/test_apollo_13.gd's.
extends SimTest

const MAIN_SCENE := "res://scenes/main.tscn"
const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")


func after_all() -> void:
	Mission.load_default()


func test_the_catalog_names_what_the_flight_has() -> void:
	var procedures := {}
	for c: Checklist in Checklist.load_all(ChecklistBook.MALFUNCTIONS):
		procedures[c.title] = true
	var systems := {}
	for pair in SimRuntime.SYSTEMS + SimRuntime.LM_SYSTEMS:
		systems[pair[0]] = true
	var ids := {}
	for f: Dictionary in Failures.catalog():
		assert_false(ids.has(f["id"]), "%s: one entry" % f["id"])
		ids[f["id"]] = true
		assert_true(systems.has(f["system"]), "%s: a runtime system" % f["id"])
		assert_has(CautionWarning.LIGHTS, f["caution"], "%s: a caution light" % f["id"])
		assert_eq(CautionWarning.LEGENDS[f["caution"]], f["light"], "%s: its legend" % f["id"])
		assert_true(procedures.has(f["procedure"]), "%s: its procedure, %s" % [f["id"], f["procedure"]])
		for k in ["title", "part", "effect", "expect"]:
			assert_true(f.has(k), "%s: %s" % [f["id"], k])
	assert_eq(ids.size(), 10)


func test_each_failure_lights_its_caution_sounds_the_master_alarm_and_changes_its_system() -> void:
	for f: Dictionary in Failures.catalog():
		var id := str(f["id"])
		build("parking_orbit")
		run(10.0, false)
		assert_false(bool(Bus.get_value("cw." + str(f["caution"]))), "%s: dark before" % id)
		assert_false(bool(Bus.get_value("sys.master_alarm")), "%s: all well before" % id)
		assert_false(Checklist.holds(f["expect"]), "%s: the system as it was" % id)
		assert_true(rt.failures.fail(id), id)
		assert_false(rt.failures.fail(id), "%s: once" % id)
		var light := func() -> bool: return bool(Bus.get_value("cw." + str(f["caution"])))
		assert_true(run_until(light, 200.0, 5.0, false), "%s lights %s" % [id, f["light"]])
		assert_true(bool(Bus.get_value("sys.master_alarm")), "%s sounds the master alarm" % id)
		assert_true(run_until(func() -> bool: return Checklist.holds(f["expect"]), 200.0, 5.0, false),
			"%s: %s" % [id, f["effect"]])
		assert_eq(Bus.get_value("failures.active"), [id])
		rt.free_nodes()


func test_a_checkpoint_keeps_the_armed_and_the_failed() -> void:
	build("parking_orbit")
	rt.failures.fail("sm_rcs_quad_b")
	rt.failures.fail("imu")
	rt.failures.arm("fuel_cell_1", SimClock.get_seconds + 600.0)
	run(10.0, false)
	var armed_at: float = rt.failures.armed["fuel_cell_1"]
	var text := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	run(1.0, false)
	assert_true(bool(Bus.get_value("cw.sm_rcs_b")), "SM RCS B still lit")
	assert_false(bool(Bus.get_value("rcs.quad_b_live")), "and quad B still dead")
	assert_true(bool(Bus.get_value("cw.iss")), "ISS still lit")
	assert_true(rt.agc().imu.failed, "the IMU still failed")
	assert_eq(Bus.get_value("imu.mode"), "caged")
	assert_false(bool(Bus.get_value("cw.fc1")), "fuel cell 1 armed, not failed")
	# A coarse align can't bring a failed IMU back.
	keys("V41N20E")
	run(60.0, false)
	assert_eq(Bus.get_value("imu.mode"), "caged", "no coarse align")
	# The clock comes to the armed failure on its second.
	run(700.0)
	assert_almost_eq(float(rt.failures.active["fuel_cell_1"]), armed_at, 0.05, "failed at its GET")
	assert_true(bool(Bus.get_value("cw.fc1")))


func test_a_mission_arms_its_own() -> void:
	build("parking_orbit", "apollo_13")
	assert_eq(rt.failures.armed, {"o2_tank_2": 201293.0}, "Apollo 13's tank, at 55:54:53")
	assert_almost_eq(float(Bus.get_value("failures.next_event_get_s")), 201293.0, 1e-6, "for the clock to land on")
	build("parking_orbit", "apollo_11")
	assert_eq(rt.failures.armed, {}, "Apollo 11 has none")


func test_the_tank_fires_its_event_and_the_crews_call() -> void:
	build("translunar_coast")
	rt.failures.arm("o2_tank_2", SimClock.get_seconds + 30.0)
	run(60.0)
	assert_gt(rt.sequencer.event_get("o2_tank_2_failure"), 0.0, "the event")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "we've had a problem")


func test_the_instructors_page_fails_the_failure_it_shows() -> void:
	build("parking_orbit")
	var rig: Node3D = add_child_autofree(DESKTOP_RIG.instantiate())
	var menu := WristMenu.new()
	menu.failures = rt.failures
	menu.setup(rig, rig.get_node("Camera3D"), null, ChecklistBook.load_default())
	menu.show_flights()
	menu.activate("instructor")
	assert_eq(menu.page, "failures")
	assert_true(menu.button("fail").is_visible_in_tree())
	assert_string_contains(menu.choice_label.text, "INSTRUCTOR: FAILURE 1 OF 10")
	assert_string_contains(menu.choice_label.text, "Cryogenic oxygen tank 2: CRYO PRESS light")
	assert_string_contains(menu.choice_label.text, "READY")
	menu.activate("failure_next")
	menu.activate("failure_next")
	assert_string_contains(menu.choice_label.text, "Fuel cell 2")
	menu.activate("fail")
	assert_true(rt.failures.active.has("fuel_cell_2"), "FAIL: failed now")
	assert_string_contains(menu.choice_label.text, "FAILED at")
	menu.activate("failure_prev")
	menu.activate("failure_prev")
	menu.activate("failure_prev")
	assert_string_contains(menu.choice_label.text, "FAILURE 10 OF 10", "round to the last")
	menu.activate("failures_back")
	assert_eq(menu.page, "flight")


func test_a_failure_opens_its_malfunction_procedure() -> void:
	Bus.reset()
	SimClock.reset()
	var main: Node = load(MAIN_SCENE).instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(2)
	var titles: Array = main.book.lists.map(func(c: Checklist) -> String: return c.title)
	assert_has(titles, "Malfunction: CMC", "the CSM's book carries the procedures")
	assert_eq(main.lm_book.lists.filter(func(c: Checklist) -> bool: return c.title.begins_with("Malfunction")), [],
		"not the LM's")
	main.rt.failures.fail("cmc")
	assert_eq(main.book.list().title, "Malfunction: CMC", "open at the failure")
	SimClock.rate = 1.0
	SimClock.advance(1.0)
	assert_true(bool(Bus.get_value("cw.cmc")))
	main.book.update()
	main.book.next()
	assert_string_contains(main.book.list().steps[main.book.list().index]["text"], "MASTER ALARM")
	Bus.set_value("ctl.cw.master_alarm", true)
	SimClock.advance(0.1)
	Bus.set_value("ctl.cw.master_alarm", false)
	main.book.update()
	assert_string_contains(main.book.list().steps[main.book.list().index]["text"], "ATT SOURCE - SCS",
		"the alarm reset, on to the SCS")
	main.rt.free_nodes()

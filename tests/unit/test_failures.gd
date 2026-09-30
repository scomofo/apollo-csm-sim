## Slice 9a (docs/ROADMAP.md): the failure catalog. Each failure in
## data/failures.json, set in a headless flight, lights its caution, sounds
## the master alarm and changes its system as the catalog says; a
## checkpoint keeps the armed and the failed; a mission arms its own, as
## Apollo 13's tank; the instructor's page on the wrist menu fails any;
## and a failure opens its malfunction procedure. Apollo 13's flight, with
## its tank on the catalog, is tests/scenarios/test_apollo_13.gd's. The
## launch vehicle's (slice 9d) light the console's launch vehicle lights
## and change the vehicle, in its stage, and a failure armed on an event
## comes that long after it; the aborts they set off are
## tests/scenarios/test_launch_aborts.gd's. The LM's (slice 9e) light the
## LM's caution and warning lights and its master alarm, and open their
## procedures in the LM's book; the abort DES REG sets off is
## tests/scenarios/test_lm_aborts.gd's. Apollo 12's lightning (slice 10c):
## the SCE's, which no light shows, only changes its system; the launch
## they come in is tests/scenarios/test_apollo_12_launch.gd's. Apollo 13's
## S-II centre engine (slice 10d) is a launch vehicle failure; its launch
## is tests/scenarios/test_apollo_13_launch.gd's. Apollo 14's ABORT switch
## (slice 12a), which no light shows either, sets the LGC's abort bit; the
## descent it would abort is tests/scenarios/test_apollo_14_abort_switch.gd's.
## Its landing radar's low scale (slice 12a), with no light of its own but
## ALT and VEL, is tests/scenarios/test_apollo_14_landing_radar.gd's.
extends SimTest

const MAIN_SCENE := "res://scenes/main.tscn"
const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")


func after_all() -> void:
	Mission.load_default()


func test_the_catalog_names_what_the_flight_has() -> void:
	var procedures := {}
	for c: Checklist in Checklist.load_all(ChecklistBook.MALFUNCTIONS):
		procedures[c.title] = "csm"
	for c: Checklist in Checklist.load_all(ChecklistBook.LM_MALFUNCTIONS):
		procedures[c.title] = "lm"
	var systems := {}
	for pair in SimRuntime.SYSTEMS + SimRuntime.LM_SYSTEMS:
		systems[pair[0]] = true
	var lamps := {}
	for r in CockpitLayout.load_default().rows:
		if r["type"] == "lamp":
			lamps[r["channel"]] = true
	var ids := {}
	for f: Dictionary in Failures.catalog():
		assert_false(ids.has(f["id"]), "%s: one entry" % f["id"])
		ids[f["id"]] = true
		assert_true(systems.has(f["system"]), "%s: a runtime system" % f["id"])
		if f["vehicle"] == "lv":
			assert_true(lamps.has(f["lamp"]), "%s: a lamp on the console, %s" % [f["id"], f["lamp"]])
		elif f["vehicle"] == "lm" and f.has("caution"):
			assert_has(LmCautionWarning.LIGHTS, f["caution"], "%s: an LM caution light" % f["id"])
			assert_eq(LmCautionWarning.LEGENDS[f["caution"]], f["light"], "%s: its legend" % f["id"])
		elif f.has("caution"):
			assert_has(CautionWarning.LIGHTS, f["caution"], "%s: a caution light" % f["id"])
			assert_eq(CautionWarning.LEGENDS[f["caution"]], f["light"], "%s: its legend" % f["id"])
		else:
			assert_eq(f["light"], "", "%s: no light the crew sees, none named" % f["id"])
		assert_eq(procedures.get(f["procedure"], ""), "lm" if f["vehicle"] == "lm" else "csm",
			"%s: its procedure, %s, in its vehicle's book" % [f["id"], f["procedure"]])
		assert_true(str(f.get("launch", "")) in ["", "abort", "return"], "%s: what the ground does in the launch" % f["id"])
		for k in ["title", "part", "effect", "expect", "light"]:
			assert_true(f.has(k), "%s: %s" % [f["id"], k])
	assert_eq(ids.size(), 27)


func test_each_failure_lights_its_caution_sounds_the_master_alarm_and_changes_its_system() -> void:
	for f: Dictionary in Failures.catalog():
		var id := str(f["id"])
		if f["vehicle"] == "lv":
			continue
		# The LM's in its descent orbit, flying free, its descent engine armed
		# and, for its helium, burning at its minimum throttle.
		var lm: bool = f["vehicle"] == "lm"
		var cw := "lm.cw." if lm else "cw."
		var alarm := "lm.cw.master_alarm" if lm else "sys.master_alarm"
		# One the crew has no light for (the SCE's, slice 10c) only changes
		# its system.
		var caution := str(f.get("caution", ""))
		build("lunar_descent" if lm else "parking_orbit")
		if lm:
			Bus.set_value("ctl.lm.engine_arm", 2)
		run(10.0, false)
		assert_false(bool(Bus.get_value(cw + caution, false)), "%s: dark before" % id)
		assert_false(bool(Bus.get_value(alarm)), "%s: all well before" % id)
		assert_false(Checklist.holds(f["expect"]), "%s: the system as it was" % id)
		assert_true(rt.failures.fail(id), id)
		assert_false(rt.failures.fail(id), "%s: once" % id)
		if f["system"] == "dps":
			Bus.set_value("ctl.lm.eng_start", true)
			run(0.2, false)
			Bus.set_value("ctl.lm.eng_start", false)
		if caution != "":
			var light := func() -> bool: return bool(Bus.get_value(cw + caution, false))
			assert_true(run_until(light, 200.0, 5.0, false), "%s lights %s" % [id, f["light"]])
			assert_true(bool(Bus.get_value(alarm)), "%s sounds the master alarm" % id)
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


## Slice 9d: each launch vehicle failure, failed in the stage it fails,
## lights its lamp and changes the vehicle as the catalog says; one S-IC
## engine out, or any after the tower's gone, aborts nothing by itself.
func test_each_launch_vehicle_failure_lights_its_lamp_and_changes_the_vehicle() -> void:
	build("launch")
	var snaps := {}
	for at in [20.0, 200.0, 600.0]:
		run(at - SimClock.get_seconds, false)
		snaps[at] = rt.snapshot()
	var when := {"sic_engine_1": 20.0, "sic_engine_2": 20.0, "lv_guidance": 200.0, "s2_engine_5": 200.0, "s2_engines": 200.0,
		"s4_engine": 600.0}
	var n := 0
	for f: Dictionary in Failures.catalog():
		if f["vehicle"] != "lv":
			continue
		var id := str(f["id"])
		n += 1
		assert_eq(rt.restore(snaps[when[id]]), "", id)
		run(SimClock.FIXED_DT, false)
		assert_false(bool(Bus.get_value(f["lamp"])), "%s: dark before" % id)
		assert_false(Checklist.holds(f["expect"]), "%s: the vehicle as it was" % id)
		assert_true(rt.failures.fail(id), id)
		run(2.0, false)
		assert_true(bool(Bus.get_value(f["lamp"])), "%s lights %s" % [id, f["light"]])
		assert_true(Checklist.holds(f["expect"]), "%s: %s" % [id, f["effect"]])
		assert_false(bool(Bus.get_value("eds.abort")), "%s: no abort by itself" % id)
	assert_eq(n, 6)


## Slice 9d: a failure armed on a mission event comes that long after it,
## and a checkpoint keeps it armed.
func test_a_failure_armed_on_an_event_comes_that_long_after_it() -> void:
	build("launch")
	assert_true(rt.failures.arm_on("sic_engine_1", "liftoff", 10.0))
	assert_eq(rt.failures.state_line("sic_engine_1"), "ARMED 10 s after liftoff")
	var snap := JSON.stringify(rt.snapshot())
	build("")
	assert_eq(rt.restore(JSON.parse_string(snap)), "")
	assert_eq(rt.failures.armed_on.keys(), ["sic_engine_1"], "kept")
	run(15.0 - SimClock.get_seconds, false)
	var liftoff := rt.sequencer.event_get("liftoff")
	assert_almost_eq(float(rt.failures.active.get("sic_engine_1", -1.0)), liftoff + 10.0, SimClock.FIXED_DT + 1e-6,
		"10 s after the liftoff")
	assert_eq(int(Bus.get_value("lv.engines_failed")), 1)
	assert_true(bool(Bus.get_value("lv.eng_light_1")), "LV ENG 1")


func test_a_mission_arms_its_own() -> void:
	build("parking_orbit", "apollo_13")
	assert_eq(rt.failures.armed, {"o2_tank_2": 201293.0}, "Apollo 13's tank, at 55:54:53")
	assert_almost_eq(float(Bus.get_value("failures.next_event_get_s")), 201293.0, 1e-6, "for the clock to land on")
	build("parking_orbit", "apollo_11")
	assert_eq(rt.failures.armed, {}, "Apollo 11 has none")
	# Slice 10c: Apollo 12's lightning, armed on the liftoff, comes only in
	# its launch.
	build("launch", "apollo_12")
	assert_eq(rt.failures.armed_on.keys(), ["fc_bus_trip", "sce_norm", "imu_tumble"], "the lightning, on the liftoff")
	assert_string_contains(rt.failures.state_line("imu_tumble"), "ARMED 52 s after liftoff")
	build("parking_orbit", "apollo_12")
	assert_eq(rt.failures.armed_on, {}, "not past it")
	# Slice 10d: Apollo 13's S-II centre engine, armed on the liftoff too.
	build("launch", "apollo_13")
	assert_eq(rt.failures.armed_on.keys(), ["s2_engine_5"], "the pogo, on the liftoff")
	assert_string_contains(rt.failures.state_line("s2_engine_5"), "ARMED 330 s after liftoff")
	assert_eq(rt.failures.armed, {"o2_tank_2": 201293.0}, "and the tank, at its GET")
	build("parking_orbit", "apollo_13")
	assert_eq(rt.failures.armed_on, {}, "not past it")


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
	assert_string_contains(menu.choice_label.text, "INSTRUCTOR: FAILURE 1 OF 27")
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
	assert_string_contains(menu.choice_label.text, "FAILURE 27 OF 27", "round to the last")
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
	var lm_titles: Array = main.lm_book.lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return t.begins_with("Malfunction"))
	assert_eq(lm_titles, ["Malfunction: DES REG", "Malfunction: RCS A or B REG", "Malfunction: LGC or ISS", "Malfunction: ABORT switch",
		"Malfunction: landing radar"],
		"the LM's book its own")
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
	main.rt.failures.fail("lgc")
	assert_eq(main.lm_book.list().title, "Malfunction: LGC or ISS", "an LM failure opens the LM's book's")
	main.rt.free_nodes()

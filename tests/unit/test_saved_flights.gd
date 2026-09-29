## Slice 8b (docs/ROADMAP.md): saved flights and settings. The flight
## menu's SAVES page saves the flight flown, and a save resumes to the
## same state in a new runtime, as test_checkpoint.gd's round trip does;
## one this build can't restore is listed as unusable and never resumed;
## DELETE takes two presses; F5 and F9 keep a quick save among the rest;
## and the settings survive the app's restart. The app keeps its saves
## and settings in user://; a test's main scene keeps none unless the test
## gives it a directory and a file, as these do.
extends GutTest

const MAIN_SCENE := "res://scenes/main.tscn"
const SAVES := "user://test_saved_flights"
const SETTINGS := "user://test_settings.json"


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	_clear()


func after_all() -> void:
	_clear()
	Mission.load_default()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(SAVES):
		for f in DirAccess.get_files_at(SAVES):
			DirAccess.remove_absolute(SAVES.path_join(f))
		DirAccess.remove_absolute(SAVES)
	if FileAccess.file_exists(SETTINGS):
		DirAccess.remove_absolute(SETTINGS)


func _main(phase: String, mission: String = Mission.DEFAULT_ID, settings: String = "") -> Node:
	var main: Node = load(MAIN_SCENE).instantiate()
	main.mission_id = mission
	main.start_phase = phase
	main.saves_dir = SAVES
	main.settings_path = settings
	add_child(main)
	return main


## [param main]'s replacement, once the flight [param act] asks for has
## started in its place, or null.
func _replaced(main: Node, act: Callable) -> Node:
	var box := [null]
	main.flight_replaced.connect(func(r: Node) -> void: box[0] = r)
	act.call()
	await wait_process_frames(3)
	return box[0]


func _fly(seconds: float) -> void:
	SimClock.rate = 1000.0
	SimClock.advance(seconds)


func test_a_save_from_the_menu_resumes_to_the_same_state_in_a_new_runtime() -> void:
	var main := _main("lunar_orbit")
	await wait_process_frames(2)
	Bus.set_value("ctl.seq.lm_jett", true)
	SimClock.rate = 1.0
	SimClock.advance(1.0)
	_fly(300.0)
	var menu: WristMenu = main.menu
	menu.show_flights()
	menu.activate("saves")
	assert_eq(menu.page, "saves")
	assert_string_contains(menu.choice_label.text, "NO SAVED FLIGHTS")
	menu.activate("save")
	var saved_get := SimClock.get_seconds
	assert_eq(main.saves.entries.size(), 1, "one save")
	var e: Dictionary = main.saves.selected()
	assert_true(e["usable"])
	assert_eq(e["name"], "Apollo 11, LUNAR ORBIT, %s GET" % Units.hms(saved_get))
	assert_string_contains(menu.choice_label.text, "SAVED FLIGHT 1 OF 1")
	assert_string_contains(menu.choice_label.text, e["name"])
	_fly(900.0)
	var expect: Array = main.rt.dynamics.traj.s.duplicate()
	var expect_t := SimClock.get_seconds
	var old := weakref(main.rt.dynamics)
	var next := await _replaced(main, menu.activate.bind("resume"))
	assert_not_null(next, "RESUME started the saved flight in place")
	assert_null(old.get_ref(), "the flight flown gone")
	assert_eq(next.rt.mission.id(), "apollo_11")
	assert_almost_eq(SimClock.get_seconds, saved_get, 1e-6, "at the save's GET")
	assert_eq(next.rt.dynamics.config, "csm", "the LM jettisoned, as it was")
	assert_eq(next.book.list().title, "Lunar orbit and TEI", "the phase's checklist open")
	_fly(900.0)
	assert_almost_eq(SimClock.get_seconds, expect_t, 1e-4)
	var s: Array = next.rt.dynamics.traj.s
	var d := Vector3(s[0] - expect[0], s[1] - expect[1], s[2] - expect[2])
	assert_lt(d.length(), 1.0, "the same trajectory, m")
	next.rt.free_nodes()
	next.free()


func test_a_save_this_build_cant_restore_is_listed_as_unusable() -> void:
	var main := _main("parking_orbit")
	await wait_process_frames(2)
	var path: String = main.saves.save(main.rt, {})
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	d["schema_version"] = SimRuntime.SCHEMA_VERSION - 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	var menu: WristMenu = main.menu
	menu.show_flights()
	menu.activate("saves")
	var e: Dictionary = main.saves.selected()
	assert_false(e["usable"], "listed, not offered")
	assert_string_contains(e["why"], "older")
	assert_string_contains(menu.choice_label.text, "CAN'T RESUME")
	assert_string_contains(menu.choice_label.text, "schema %d" % (SimRuntime.SCHEMA_VERSION - 1))
	var next := await _replaced(main, menu.activate.bind("resume"))
	assert_null(next, "RESUME does nothing with it")
	assert_false(main.resume_flight(path), "nor does a call")
	main.rt.free_nodes()
	main.free()


func test_delete_takes_two_presses() -> void:
	var main := _main("parking_orbit")
	await wait_process_frames(2)
	var menu: WristMenu = main.menu
	menu.show_flights()
	menu.activate("saves")
	menu.activate("save")
	_fly(60.0)
	menu.activate("save")
	assert_eq(main.saves.entries.size(), 2)
	menu.activate("saved_next")
	var path: String = main.saves.selected_path()
	menu.activate("delete")
	assert_true(FileAccess.file_exists(path), "one press: not yet")
	assert_string_contains(menu.choice_label.text, "DELETE again")
	menu.activate("saved_prev")
	menu.activate("saved_next")
	menu.activate("delete")
	assert_true(FileAccess.file_exists(path), "another button in between: not yet")
	menu.activate("delete")
	assert_false(FileAccess.file_exists(path), "two presses: gone")
	assert_eq(main.saves.entries.size(), 1)
	assert_string_contains(menu.choice_label.text, "SAVED FLIGHT 1 OF 1")
	main.rt.free_nodes()
	main.free()


func test_f5_and_f9_keep_a_quick_save() -> void:
	var main := _main("lunar_orbit")
	await wait_process_frames(2)
	_fly(120.0)
	var saved_get := SimClock.get_seconds
	assert_ne(main.quick_save(), "", "F5")
	var e: Dictionary = main.saves.entry(main.saves.quick_path())
	assert_string_contains(e["name"], "Quick save (F5)")
	_fly(600.0)
	main.quick_load()
	assert_almost_eq(SimClock.get_seconds, saved_get, 1e-6, "F9: back to it in place")
	var other := await _replaced(main, main.start_flight.bind("apollo_8", "lunar_orbit"))
	assert_eq(other.rt.mission.id(), "apollo_8")
	var back := await _replaced(other, other.quick_load)
	assert_not_null(back, "F9 in another mission: its flight started in place")
	assert_eq(back.rt.mission.id(), "apollo_11")
	assert_almost_eq(SimClock.get_seconds, saved_get, 1e-6)
	back.rt.free_nodes()
	back.free()


func test_the_settings_survive_the_apps_restart() -> void:
	var main := _main("parking_orbit", Mission.DEFAULT_ID, SETTINGS)
	await wait_process_frames(2)
	var menu: WristMenu = main.menu
	for id in ["eye_up", "eye_up", "eye_up", "vignette", "horizon", "highlight", "sound_down", "sound_down"]:
		menu.activate(id)
	assert_true(FileAccess.file_exists(SETTINGS), "kept as they change")
	main.rt.free_nodes()
	main.free()
	Bus.reset()
	SimClock.reset()
	var again := _main("parking_orbit", Mission.DEFAULT_ID, SETTINGS)
	await wait_process_frames(2)
	assert_almost_eq(float(again.rig.get("height_offset")), 0.03, 1e-6, "the eye height")
	assert_false(again.comfort.vignette_enabled, "the vignette")
	assert_true(again.comfort.horizon_aid, "the horizon aid")
	assert_false(bool(Bus.get_value("present.checklist.highlight_enabled")), "the highlight")
	assert_almost_eq(float(Bus.get_value("player.sound_db")), -6.0, 1e-6, "the sound's level")
	again.rt.free_nodes()
	again.free()
	Bus.reset()
	SimClock.reset()
	var fresh := _main("parking_orbit")
	await wait_process_frames(2)
	assert_eq(float(fresh.rig.get("height_offset")), 0.0, "a main scene with no settings file keeps none")
	fresh.rt.free_nodes()
	fresh.free()

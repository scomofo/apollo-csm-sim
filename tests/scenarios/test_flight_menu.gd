## Slice 8a's check (docs/ROADMAP.md): the flight menu, clicked through
## the desktop rig. F1 opens the wrist menu's flight page in the cabin;
## its buttons step to Apollo 13's tank_failure, and START starts that
## flight in place of Apollo 11's, at 55:50:00 GET with Odyssey's failure
## checklist open. From there the menu goes on to Apollo 11's lunar_orbit,
## and none of the first two flights' nodes is left. Slice 8b's saves page,
## clicked through the same way: a flight saved, resumed and deleted.
extends DesktopTest

const SAVES := "user://test_flight_menu_saves"


func after_all() -> void:
	_clear()


func _clear() -> void:
	if DirAccess.dir_exists_absolute(SAVES):
		for f in DirAccess.get_files_at(SAVES):
			DirAccess.remove_absolute(SAVES.path_join(f))
		DirAccess.remove_absolute(SAVES)


## Click the menu's [param id] (START, RESUME) and take the flight that
## replaces this one as the one worked from here.
func _start_chosen(id: String = "start") -> void:
	var box := [null]
	main.flight_replaced.connect(func(r: Node) -> void: box[0] = r)
	await click_menu(id)
	for i in 600:
		if box[0] != null:
			break
		await wait_process_frames(1)
	assert_not_null(box[0], "%s started a new flight" % id.to_upper())
	main = box[0]
	rt = main.rt
	hud = main.hud
	await wait_process_frames(2)


func _open_flights() -> void:
	press(KEY_F1)
	await wait_process_frames(1)
	assert_true(main.menu.is_shown(), "F1 opens the menu")
	assert_eq(main.menu.page, "flight", "on its flight page")
	assert_eq(main.view.view_mode, 2, "in the cabin, where the pointer reaches it")


func _nodes_of(m: Node) -> Array[WeakRef]:
	var out: Array[WeakRef] = []
	for n in [m, m.rt.dynamics, m.rt.sequencer, m.rt.agc(), m.cabin, m.lm_cabin, m.rig, m.hud, m.menu, m.audio]:
		out.append(weakref(n))
	return out


func test_the_flight_menu_starts_another_flight_in_place() -> void:
	in_cabin = true
	await start("parking_orbit")
	var gone := _nodes_of(main)
	await _open_flights()
	assert_string_contains(main.menu.choice_label.text, "Apollo 11")
	assert_string_contains(main.menu.choice_label.text, "PARKING ORBIT", "the flight flown")
	await click_menu("mission_next")
	await click_menu("mission_next")
	await click_menu("phase_next")
	await click_menu("phase_next")
	assert_eq(main.menu.choice_label.text,
		"Apollo 13 - CSM Odyssey, LM Aquarius\nTANK FAILURE\n55:50 GET, five minutes before oxygen tank 2 fails")
	await _start_chosen()
	assert_eq(rt.mission.id(), "apollo_13")
	assert_almost_eq(SimClock.get_seconds, 55.0 * 3600.0 + 50.0 * 60.0, 1.0, "at 55:50:00 GET")
	assert_eq(rt.dynamics.config, "csm_lm", "Aquarius docked")
	assert_eq(main.book.list().title, "The oxygen tank failure and the lifeboat", "Odyssey's failure checklist open")
	assert_eq(main.card.book, main.book, "on the card")
	assert_eq(main.lm_book.list().title, "Activation and the docked alignment", "and Aquarius's on its")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "stir up your cryo tanks")
	for w in gone:
		assert_null(w.get_ref(), "Apollo 11's flight gone")
	gone = _nodes_of(main)
	await _open_flights()
	await click_menu("mission_prev")
	await click_menu("mission_prev")
	assert_string_contains(main.menu.choice_label.text, "Apollo 11")
	assert_string_contains(main.menu.choice_label.text, "LAUNCH",
		"Apollo 12 has no tank failure: its first start phase, the launch, which Apollo 11 has too")
	await click_menu("phase_next")
	await click_menu("phase_next")
	await click_menu("phase_next")
	assert_string_contains(main.menu.choice_label.text, "LUNAR ORBIT")
	await _start_chosen()
	assert_eq(rt.mission.id(), "apollo_11")
	assert_eq(Bus.get_value("mission.phase"), "lunar_orbit")
	assert_eq(main.book.list().title, "Lunar orbit and TEI")
	for w in gone:
		assert_null(w.get_ref(), "Apollo 13's flight gone")
	assert_eq(viewport.get_child_count(), 1, "one flight in the viewport")
	rt.free_nodes()


func test_a_flight_saved_from_the_menu_is_resumed_and_deleted_there() -> void:
	in_cabin = true
	saves_dir = SAVES
	_clear()
	await start("lunar_orbit")
	await _open_flights()
	await click_menu("saves")
	assert_eq(main.menu.page, "saves")
	assert_string_contains(main.menu.choice_label.text, "NO SAVED FLIGHTS")
	await click_menu("save")
	var saved_get := SimClock.get_seconds
	assert_string_contains(main.menu.choice_label.text, "SAVED FLIGHT 1 OF 1")
	assert_string_contains(main.menu.choice_label.text, "Apollo 11, LUNAR ORBIT, %s GET" % Units.hms(saved_get))
	run(600.0)
	await _start_chosen("resume")
	assert_eq(rt.mission.id(), "apollo_11")
	assert_almost_eq(SimClock.get_seconds, saved_get, 1e-6, "back at the save's GET")
	assert_eq(main.book.list().title, "Lunar orbit and TEI")
	await _open_flights()
	await click_menu("saves")
	var path: String = main.saves.selected_path()
	await click_menu("delete")
	assert_true(FileAccess.file_exists(path), "DELETE once: not yet")
	await click_menu("delete")
	assert_false(FileAccess.file_exists(path), "twice: gone")
	assert_string_contains(main.menu.choice_label.text, "NO SAVED FLIGHTS")
	rt.free_nodes()
	_clear()

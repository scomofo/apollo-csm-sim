extends GutTest


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func test_main_scene_builds_and_keyboard_drives_the_dsky() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(3)
	assert_not_null(main.hud)
	assert_not_null(main.view)
	assert_eq(Bus.get_value("mission.phase"), "lunar_orbit")
	for kc in [KEY_V, KEY_1, KEY_6, KEY_N, KEY_6, KEY_2, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.pressed = true
		main._unhandled_input(ev)
	assert_eq(main.rt.agc().dsky.verb, "16")
	assert_eq(main.rt.agc().dsky.noun, "62")
	main.rt.free_nodes()


func test_checklists_load_and_auto_advance() -> void:
	var lists := Checklist.load_all("res://data/missions/apollo_11/checklists.json")
	assert_eq(lists.size(), 4)
	var burn := lists[1]
	burn.next()
	assert_eq(burn.index, 1)
	Bus.set_value("guid.program", 30)
	burn.update()
	assert_eq(burn.index, 2, "P30 selected completes its step")

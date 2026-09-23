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
	assert_not_null(main.get_node_or_null("HandControllerInput"), "the keys reach ctl.rhc and ctl.thc through it")
	assert_eq(Bus.get_value("mission.phase"), "lunar_orbit")
	for kc in [KEY_V, KEY_1, KEY_6, KEY_N, KEY_6, KEY_2, KEY_ENTER]:
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.pressed = true
		main._unhandled_input(ev)
	assert_eq(main.rt.agc().dsky.verb, "16")
	assert_eq(main.rt.agc().dsky.noun, "62")
	main.rt.free_nodes()


func test_c_cycles_the_window_chase_and_cabin_views() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(2)
	var cabin: CmCabin = main.cabin
	assert_not_null(cabin, "the CM cabin is built")
	assert_true(cabin.items.has("P2_DSKY"), "with its panels")
	assert_eq(main.rig.get_parent(), cabin.anchor, "the desktop rig sits at the commander's eye")
	assert_false(main.xr, "no headset here")
	var rig_camera: Camera3D = main.rig.get_node("Camera3D")
	var expect := [[0, false], [1, false], [2, true], [0, false]]
	for step in expect.size():
		if step > 0:
			var ev := InputEventKey.new()
			ev.keycode = KEY_C
			ev.pressed = true
			main._unhandled_input(ev)
		var mode: int = expect[step][0]
		var in_cabin: bool = expect[step][1]
		assert_eq(main.view.view_mode, mode, "view %d" % mode)
		assert_eq(cabin.visible, in_cabin, "the cabin shows only in the cabin view")
		assert_eq(rig_camera.current, in_cabin, "the rig's camera")
		assert_eq(main.view.camera.current, not in_cabin, "the space view's camera")
		assert_eq(main.rig.is_processing_unhandled_input(), in_cabin, "the rig takes the mouse in the cabin")
		assert_eq(main.menu.is_processing_unhandled_input(), in_cabin, "and M opens the wrist menu there")
		assert_eq(main.hud.dsky_panel.visible, not in_cabin, "the 2D DSKY steps aside for the cabin's")
		await wait_process_frames(1)
		assert_eq(main.view._parts["cm"].visible, not in_cabin, "the CM model gives way to the cabin")
	main.rt.free_nodes()


func test_the_cabin_has_the_checklist_card_highlight_and_wrist_menu() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_eq(main.card.get_parent(), main.cabin.card_mount, "the card by the commander's shoulder")
	assert_eq(main.highlight.get_parent(), main.cabin)
	assert_eq(main.menu.get_parent(), main.rig.get_node("Camera3D"), "the desktop menu rides on the camera")
	assert_eq(main.hud.book, main.book, "the HUD and the cabin share one checklist book")
	assert_eq(main.book.list().title, "Lunar orbit and TEI", "opened for the phase")
	assert_eq(main.card.title_label.text, "CHECKLIST  LUNAR ORBIT AND TEI")
	var eye: Vector3 = main.cabin.anchor.global_position
	var to_eye: Vector3 = (eye - main.card.global_position).normalized()
	assert_gt(main.card.global_basis.z.dot(to_eye), 0.999, "the card faces the commander's eye")
	assert_almost_eq(eye.distance_to(main.card.global_position), 0.49, 0.01, "at reading distance")
	main.rt.free_nodes()


func test_undock_on_the_hud_frees_the_lm_for_the_view_and_the_hud_readout() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_false(main.view.lm_free.visible, "docked")
	var undock: Button
	for b in main.hud.find_children("*", "Button", true, false):
		if b.text == "UNDOCK":
			undock = b
	assert_not_null(undock, "the switch panel has UNDOCK")
	undock.button_down.emit()
	SimClock.advance(0.1)
	undock.button_up.emit()
	SimClock.advance(60.0)
	await wait_process_frames(2)
	assert_eq(str(Bus.get_value("dock.state")), "free")
	assert_true(main.view.lm_free.visible, "the view draws the free LM")
	assert_false(main.view._parts["lm"].visible, "not docked to the CSM")
	var text: String = main.hud._flight.text
	assert_string_contains(text, "LM RNG", "the HUD reads out the range to the LM")
	assert_string_contains(text, "%.1f ft" % (float(Bus.get_value("dock.range_m")) / Units.FT))
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

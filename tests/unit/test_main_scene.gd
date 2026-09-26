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
	assert_eq(Bus.get_value("player.vehicle"), "lm", "the commander moves to the LM")
	assert_eq(main.hud.book, main.hud.lm_book, "with Eagle's checklists")
	assert_eq(main.hud.book.list().title, "Undocking and DOI (P30 / P40)", "opened for lunar orbit")
	assert_eq(main.hud.book.list().index, 1, "the undocking checked off")
	_press(main, [KEY_L])
	assert_eq(main.hud.book, main.book, "Columbia's again")
	assert_eq(main.book.list().title, "Lunar orbit and TEI")
	await wait_process_frames(2)
	assert_true(main.view.lm_free.visible, "from the CSM, the view draws the free LM")
	assert_false(main.view._parts["lm"].visible, "not docked to the CSM")
	var text: String = main.hud._flight.text
	assert_string_contains(text, "LM RNG", "the HUD reads out the range to the LM")
	assert_string_contains(text, "%.1f ft" % (float(Bus.get_value("dock.range_m")) / Units.FT))
	main.rt.free_nodes()


func test_the_lm_phases_start_in_the_lm_and_l_changes_vehicles() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_descent"
	add_child_autofree(main)
	await wait_process_frames(2)
	assert_eq(str(Bus.get_value("dock.state")), "free", "the LM flies free")
	assert_eq(Bus.get_value("player.vehicle"), "lm", "with the commander in it")
	assert_eq(main.view.vehicle, "lm", "the view is from the LM")
	assert_true(main.hud.lgc_panel.visible, "the LGC's DSKY")
	assert_false(main.hud.dsky_panel.visible, "in place of the CMC's")
	assert_string_contains(main.hud._top.text, "EAGLE")
	assert_string_contains(main.hud._flight.text, "AGL", "the LM's flight data")
	assert_eq(main.hud.book.list().title, "Powered descent (P63 to P68)", "Eagle's checklist for the phase")
	assert_eq(main.book.list().title, "Lunar orbit and TEI", "and Columbia's, on its card")
	_press(main, [KEY_V, KEY_1, KEY_6, KEY_N, KEY_6, KEY_8, KEY_ENTER])
	assert_eq(main.rt.lgc().dsky.verb, "16", "the keys reach the LGC")
	assert_eq(main.rt.lgc().dsky.noun, "68")
	assert_ne(main.rt.agc().dsky.noun, "68", "not the CMC")
	for mode in [1, 2, 0]:
		_press(main, [KEY_C])
		assert_eq(main.view.view_mode, mode, "C: the LM's window, chase and cabin views")
	var arm: OptionButton = main.hud._options["ctl.lm.engine_arm"]
	arm.item_selected.emit(2)
	assert_eq(Bus.get_value("ctl.lm.engine_arm"), 2, "ENG ARM DES")
	# L: back to the CSM, with its DSKY and its three views.
	_press(main, [KEY_L])
	assert_eq(Bus.get_value("player.vehicle"), "csm")
	assert_eq(main.view.vehicle, "csm")
	assert_true(main.hud.dsky_panel.visible, "the CMC's DSKY")
	assert_false(main.hud.lgc_panel.visible)
	assert_eq(main.hud.book, main.book, "Columbia's checklists")
	await wait_process_frames(1)
	assert_string_contains(main.hud._top.text, "COLUMBIA")
	assert_eq(main.hud._check_title.get_item_text(main.hud._check_title.selected), "Lunar orbit and TEI")
	_press(main, [KEY_V, KEY_1, KEY_6, KEY_N, KEY_6, KEY_2, KEY_ENTER])
	assert_eq(main.rt.agc().dsky.noun, "62", "the keys reach the CMC")
	assert_eq(main.rt.lgc().dsky.noun, "68", "the LGC keeps its display")
	_press(main, [KEY_C, KEY_C])
	assert_eq(main.view.view_mode, 2, "the CM's cabin")
	assert_eq(main.rig.get_parent(), main.cabin.anchor, "the rig in Columbia's cabin")
	# L in the cabin view: into Eagle's cabin, with the card, the highlight
	# and the wrist menu.
	_press(main, [KEY_L])
	assert_eq(main.view.view_mode, 2, "still the cabin view")
	assert_true(main.lm_cabin.visible, "Eagle's cabin")
	assert_false(main.cabin.visible, "not Columbia's")
	assert_eq((main.cabin.items["P1_CMC_MODE"].get_node("Touch") as Area3D).collision_layer, 0,
		"Columbia's hidden controls let the pointer through to Eagle's")
	assert_ne((main.lm_cabin.items["P1_ENG_ARM"].get_node("Touch") as Area3D).collision_layer, 0)
	assert_eq(main.rig.get_parent(), main.lm_cabin.anchor, "the rig at Eagle's commander's station")
	assert_true((main.rig.get_node("Camera3D") as Camera3D).current)
	assert_eq(main.card.get_parent(), main.lm_cabin.card_mount)
	assert_eq(main.card.book, main.lm_book, "the card shows Eagle's checklists")
	assert_eq(main.highlight.get_parent(), main.lm_cabin)
	assert_eq(main.menu.cabin, main.lm_cabin, "SEAT moves between Eagle's stations")
	assert_eq(main.menu.book, main.lm_book)
	assert_not_null(main.menu.button("pdi"), "the wrist menu asks for Eagle's PADs")
	assert_eq(main.comfort.vehicle, "lm")
	assert_false(main.hud.lgc_panel.visible, "the LGC's 2D DSKY steps aside for the cabin's")
	main.rt.free_nodes()


func _press(main: Node, keys: Array) -> void:
	for kc in keys:
		var ev := InputEventKey.new()
		ev.keycode = kc
		ev.pressed = true
		main._unhandled_input(ev)


func test_checklists_load_and_auto_advance() -> void:
	var lists := Checklist.load_all("res://data/missions/apollo_11/checklists.json")
	assert_eq(lists.size(), 5)
	var burn := lists[1]
	Bus.set_value("ctl.cmc.up_tlm", true)
	burn.update()
	assert_eq(burn.index, 1, "UP TLM CM in ACCEPT completes its step")
	burn.next()
	assert_eq(burn.index, 2)
	Bus.set_value("ctl.cmc.up_tlm", false)
	Bus.set_value("guid.program", 30)
	burn.update()
	assert_eq(burn.index, 4, "UP TLM CM - BLOCK, then P30 selected, complete their steps")

## The CM and LM tours, through the main scene's crew inputs.
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
var main: Node
var viewport: SubViewport


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	SimClock.manual = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 600)
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	main = MAIN.instantiate()
	main.start_phase = "lunar_orbit"
	main.flight_given = true
	viewport.add_child(main)
	await wait_process_frames(2)


func after_each() -> void:
	main.rt.free_nodes()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _key(code: Key, physical: bool = false, shifted: bool = false, control: bool = false) -> void:
	var event := InputEventKey.new()
	if physical:
		event.physical_keycode = code
	else:
		event.keycode = code
	event.pressed = true
	event.shift_pressed = shifted
	event.ctrl_pressed = control
	main._unhandled_input(event)


func _next() -> void:
	_key(KEY_F3)


func test_keyboard_wrist_card_and_hud_share_one_progress_state() -> void:
	_key(KEY_F2, false, false, true)
	assert_false(main.guide.is_shown(), "Ctrl+F2 is not a guide shortcut")
	_key(KEY_F2, true)
	assert_true(main.guide.is_shown())
	assert_false(main.card.visible)
	assert_false(main.hud._check_panel.visible)
	_key(KEY_F2, false, true)
	assert_eq(main.guide.selector.selected, main.book.current)
	main.menu.activate("tour")
	assert_eq(main.view.view_mode, 2)
	assert_eq(main.book.list().title, "CM cockpit walkthrough")
	main.menu.activate("next")
	main.guide.refresh()
	assert_eq(main.book.list().index, 1)
	assert_string_contains(main.guide.current_label.text, "FDAI")
	_key(KEY_F3, true)
	assert_eq(main.book.list().index, 2)
	_key(KEY_F2)
	assert_true(main.card.visible)
	assert_true(main.hud._check_panel.visible)
	_next()
	assert_eq(main.book.list().index, 2, "F3 while hidden does nothing")
	main.menu.activate("walkthrough")
	assert_true(main.guide.is_shown())


func test_cm_tour_is_completable_while_paused_with_real_menu_and_dsky_keys() -> void:
	SimClock.paused = true
	var start_time := SimClock.get_seconds
	var program: int = main.rt.agc().program
	main.menu.activate("tour")
	_next()
	main.menu.activate("find_control")
	assert_true(main.rig.is_inspecting())
	_next()
	_next()
	assert_eq(main.book.list().index, 2, "Continue cannot skip opening the menu")
	var event := InputEventKey.new()
	event.keycode = KEY_M
	event.pressed = true
	main.menu._unhandled_input(event)
	main.guide.refresh()
	assert_eq(main.book.list().index, 3)
	main.menu.activate("seat")
	main.guide.refresh()
	assert_eq(main.cabin.seat, "CMP")
	assert_eq(main.book.list().index, 4)
	for code in [KEY_V, KEY_1, KEY_6, KEY_N, KEY_2, KEY_0, KEY_ENTER]:
		_key(code)
	main.guide.refresh()
	assert_eq(main.rt.agc().dsky.monitor_verb, 16)
	assert_eq(main.rt.agc().dsky.monitor_noun, 20)
	assert_string_contains(main.guide.state_label.text, "VERB 16 · NOUN 20")
	_next()
	_next()
	assert_eq(main.book.list().index, 6)
	main.menu.activate("seat")
	main.guide.refresh()
	assert_eq(main.cabin.seat, "LEB")
	assert_eq(main.book.list().index, 7)
	main.menu.activate("find_control")
	_next()
	main.menu.activate("seat")
	main.guide.refresh()
	assert_eq(main.cabin.seat, "CDR")
	assert_eq(main.book.list().index, 9)
	_next()
	assert_true(main.book.list().done())
	assert_eq(main.rt.agc().program, program)
	assert_eq(SimClock.get_seconds, start_time)
	assert_true(SimClock.paused)


func test_lm_tour_follows_the_active_vehicle_and_returns_to_csm_book() -> void:
	Bus.set_value("ctl.seq.undock", true)
	SimClock.advance(0.1)
	Bus.set_value("ctl.seq.undock", false)
	SimClock.advance(60.0)
	main.vehicles.update()
	assert_eq(main.guide.book, main.lm_book)
	main.menu.activate("tour")
	assert_eq(main.guide.book.list().title, "LM cockpit walkthrough")
	_next()
	_next()
	main.menu._set_shown(true)
	main.guide.refresh()
	main.menu.activate("seat")
	main.guide.refresh()
	assert_eq(main.lm_book.list().index, 4)
	main.menu.activate("find_control")
	assert_eq(main.guide.target(), main.lm_cabin.items["P6_DEDA"])
	assert_eq(main.lm_cabin.seat, "LMP")
	_next()
	main.menu.activate("seat")
	main.guide.refresh()
	assert_eq(main.lm_book.list().index, 6)
	_next()
	_next()
	assert_true(main.lm_book.list().done())
	_key(KEY_L)
	assert_eq(main.guide.book, main.book)
	assert_eq(main.guide.cabin, main.cabin)


func test_visible_hud_and_guide_leave_the_wrist_menu_clickable_after_find() -> void:
	main.guide.tour()
	_next()
	main.guide.find_control()
	main.menu._set_shown(true)
	await wait_process_frames(3)
	await wait_physics_frames(2)
	var camera: Camera3D = main.rig.get_node("Camera3D")
	var touch: Node3D = main.menu.button("seat").get_node("Touch")
	var point := camera.unproject_position(touch.global_position)
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = down
		viewport.push_input(event, true)
	assert_eq(main.cabin.seat, "CMP", "GUI did not swallow the wrist SEAT click")

## The wrist menu (docs/ROADMAP.md, slice 2d) asks Mission Control for
## PADs, sets the clock, recentres, calibrates eye height and works the
## checklist, and never touches a panel control. It shows on M on the
## desktop, and on the controller's menu button or when the palm faces the
## head in a headset. Adapted from gemini-capsule's
## tests/unit/test_wrist_menu.gd at 40e449c, without its comfort and guide
## cases.
extends GutTest

const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")

var _rig: Node3D
var _cam: Node3D
var _book: ChecklistBook
var _menu: WristMenu


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	_rig = add_child_autofree(DESKTOP_RIG.instantiate())
	_cam = _rig.get_node("Camera3D")
	_book = ChecklistBook.load_default()
	_menu = WristMenu.new()
	_menu.setup(_rig, _cam, null, _book)


func _key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	_menu._unhandled_input(ev)


func test_builds_every_button_hidden_and_m_shows_it_on_the_desktop() -> void:
	for b in WristMenu.BUTTONS:
		assert_not_null(_menu.button(b[0]), b[0])
	assert_eq(_menu.get_parent(), _cam, "the desktop menu rides on the camera")
	assert_false(_menu.is_shown(), "hidden until asked for")
	assert_false(Bus.get_value("present.menu.visible"))
	_key(KEY_M)
	assert_true(_menu.is_shown())
	assert_true(Bus.get_value("present.menu.visible"))
	_menu.button("hide").actuate_far(0)
	assert_false(_menu.is_shown(), "HIDE")
	_key(KEY_M)
	_key(KEY_M)
	assert_false(_menu.is_shown(), "M toggles")


func test_the_controller_menu_button_shows_and_hides_it() -> void:
	_menu._on_hand_button("menu_button")
	assert_true(_menu.is_shown())
	_menu._on_hand_button("trigger_click")
	assert_true(_menu.is_shown(), "other buttons are ignored")
	_menu._on_hand_button("menu_button")
	assert_false(_menu.is_shown())


func test_the_palm_shows_it_and_a_dismissal_holds_until_the_hand_turns_away() -> void:
	var hand := Node3D.new()
	_rig.add_child(hand)
	_menu.hand = hand
	hand.global_position = _cam.global_position - Vector3.RIGHT
	_menu._process(0.02)
	assert_true(_menu.is_shown(), "the palm faces the head")
	_menu.activate("hide")
	_menu._process(0.02)
	assert_false(_menu.is_shown(), "dismissed, it stays closed while the palm still faces the head")
	hand.rotation.y = PI
	_menu._process(0.02)
	hand.rotation.y = 0.0
	_menu._process(0.02)
	assert_true(_menu.is_shown(), "turning away and back shows it again")


func test_pad_buttons_ask_mission_control() -> void:
	var asked: Array = []
	var record := func(ch: String, v: Variant) -> void:
		if ch == "ctl.ground.pad_request":
			asked.append(v)
	Bus.value_changed.connect(record)
	for id in WristMenu.PAD_REQUESTS:
		_menu.activate(id)
	Bus.value_changed.disconnect(record)
	assert_eq(asked, ["mcc", "loi", "circ", "tei"], "the requests the HUD's Mission Control buttons make")


func test_in_eagle_the_pad_buttons_ask_for_eagles_pads() -> void:
	_menu.set_vehicle("lm")
	_menu._set_shown(true)
	var asked: Array = []
	var record := func(ch: String, v: Variant) -> void:
		if ch == "ctl.ground.pad_request":
			asked.append(v)
	Bus.value_changed.connect(record)
	for pad in WristMenu.PADS["lm"]:
		var b := _menu.button(pad[0])
		assert_not_null(b, "a %s button" % pad[1])
		assert_eq(b.label, pad[1])
		assert_eq((b.get_node("Legend") as Label3D).text, pad[1], "lettered %s" % pad[1])
		b.actuate_far(0)
		b.release()
	Bus.value_changed.disconnect(record)
	assert_eq(asked, ["doi", "pdi", "ascent", "csi"], "the requests Eagle's HUD makes")
	assert_null(_menu.button("mcc"), "not Columbia's")
	assert_eq(_menu.pad_requests(), ["doi", "pdi", "ascent", "csi"])
	_menu.set_vehicle("csm")
	assert_eq(_menu.button("mcc").label, "MCC", "Columbia's again")
	assert_eq(_menu.pad_requests(), WristMenu.PAD_REQUESTS)


func test_clock_buttons() -> void:
	_menu.activate("faster")
	assert_eq(SimClock.rate, 10.0)
	_menu.activate("slower")
	assert_eq(SimClock.rate, 1.0)
	_menu.activate("pause")
	assert_true(SimClock.paused)
	_menu.activate("pause")
	assert_false(SimClock.paused)


func test_the_buttons_work_while_time_acceleration_locks_the_panels() -> void:
	_menu._set_shown(true)
	for i in 3:
		SimClock.faster()
	assert_true(SimClock.controls_locked(), "1000x locks the panel controls")
	var slower := _menu.button("slower")
	slower.actuate_far(0)
	assert_eq(SimClock.rate, 100.0, "RATE - still works")
	slower.release()
	var pause := _menu.button("pause")
	pause.actuate_far(0)
	assert_true(SimClock.paused, "and PAUSE")
	pause.release()


func test_eye_height_calibration_recentres_and_is_clamped() -> void:
	_menu.activate("eye_up")
	_menu.activate("eye_up")
	assert_almost_eq(float(_rig.get("height_offset")), 0.02, 1e-9)
	assert_almost_eq(_cam.position.y, 0.02, 1e-9, "applied by recentring")
	assert_almost_eq(float(Bus.get_value("player.eye_height_offset_m")), 0.02, 1e-9)
	for i in 40:
		_menu.activate("eye_down")
	assert_almost_eq(float(_rig.get("height_offset")), -WristMenu.HEIGHT_LIMIT, 1e-9, "clamped")
	assert_almost_eq(_cam.position.x, 0.0, 1e-9, "only the height moves")


func test_recentre_restores_the_view() -> void:
	_cam.rotation = Vector3(0.3, -0.8, 0.0)
	_menu.activate("recenter")
	assert_almost_eq(_cam.rotation, Vector3.ZERO, Vector3.ONE * 1e-9)


func test_checklist_buttons_work_the_shared_book() -> void:
	_book.select_for_phase("translunar_coast")
	_menu.activate("next")
	assert_eq(_book.list().index, 1, "NEXT STEP acknowledges the read-only step")
	_menu.activate("checklist")
	assert_eq(_book.list().title, "Lunar orbit and TEI", "CHECKLIST opens the next one")
	assert_true(Bus.get_value("present.checklist.highlight_enabled"), "the highlight starts on")
	_menu.activate("highlight")
	assert_false(Bus.get_value("present.checklist.highlight_enabled"), "HILITE turns it off")


func test_hidden_buttons_ignore_input_and_let_the_pointer_through() -> void:
	var pause := _menu.button("pause")
	pause.actuate_far(0)
	assert_false(SimClock.paused, "a hidden button does nothing")
	assert_eq((pause.get_node("Touch") as Area3D).collision_layer, 0, "and doesn't stop the pointer")
	_menu._set_shown(true)
	assert_ne((pause.get_node("Touch") as Area3D).collision_layer, 0)
	pause.actuate_far(0)
	assert_true(SimClock.paused)

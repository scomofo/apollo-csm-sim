## Slice 2d's check (docs/ROADMAP.md): through the desktop rig, request a
## PAD from the wrist menu, then see UPLINK ACTY on the cabin DSKY and the
## PAD on the checklist card, and go on down the checklist from the menu
## and the DSKY. The menu rides on the camera, so its buttons are clicked
## where they are on the screen, as with a free mouse; panel controls are
## looked at and clicked, as in test_cabin_mcc.gd.
extends SimTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")
const CENTRE := Vector2(400, 300)

var viewport: SubViewport
var cabin: CmCabin
var rig: Node3D
var camera: Camera3D
var dsky: CabinDsky
var book: ChecklistBook
var card: ChecklistCard
var highlight: ChecklistHighlight
var menu: WristMenu


func _setup_cabin() -> void:
	viewport = SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	cabin = CmCabin.create()
	viewport.add_child(cabin)
	cabin.connect_runtime(rt)
	rig = RIG.instantiate()
	rig.set("click_range", CmCabin.CLICK_RANGE)
	cabin.anchor.add_child(rig)
	camera = rig.get_node("Camera3D")
	camera.current = true
	book = ChecklistBook.load_default()
	book.select_for_phase("translunar_coast")
	card = ChecklistCard.new()
	card.book = book
	cabin.card_mount.add_child(card)
	highlight = ChecklistHighlight.new()
	highlight.cabin = cabin
	highlight.book = book
	cabin.add_child(highlight)
	menu = WristMenu.new()
	menu.setup(rig, camera, null, book)
	dsky = cabin.items["P2_DSKY"]
	await wait_physics_frames(2)


func _press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	viewport.push_input(ev, true)
	await wait_physics_frames(1)


func _mouse(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	viewport.push_input(ev, true)


## Click the menu button [param id] where it shows on the screen.
func _click_menu(id: String) -> void:
	var b := menu.button(id)
	_mouse(camera.unproject_position(b.get_node("Touch").global_position))
	await _let_go(b)


## Look at a panel control and click it. The open menu turns with the
## camera, and the physics server moves its buttons at the next physics
## step, so the click waits for one, as a hand on a mouse always does.
func _click(control: ControlBase) -> void:
	assert_true(rig.focus_control(control), "looking at %s" % control.name)
	await wait_physics_frames(1)
	_mouse(CENTRE)
	rig.end_inspection()
	await _let_go(control)


func _let_go(control: ControlBase) -> void:
	for i in 600:
		if control.get("pressed") != true:
			return
		await wait_process_frames(1)


func _keys(seq: String) -> void:
	var names := {"V": "VERB", "N": "NOUN", "E": "ENTR", "P": "PRO"}
	for ch in seq:
		await _click(dsky.keys[names.get(ch, ch)])


func _current_step() -> String:
	for l in card.step_labels:
		if l.visible and l.text.begins_with("▶"):
			return l.text
	return ""


func test_request_a_pad_from_the_wrist_menu_and_fly_on_down_the_checklist() -> void:
	build("translunar_coast")
	# As in test_cabin_mcc.gd: a TLI cutoff error, so there is an MCC to plan.
	var tr := rt.dynamics.traj
	tr.set_state(tr.primary, tr.t, tr.pos(), tr.vel() - tr.vel().normalized() * 0.8)
	rt.dynamics.publish_state()
	await _setup_cabin()
	assert_string_starts_with(_current_step(), "▶ Mission Control: request the PAD")
	assert_false(dsky.lamps["uplink_acty"].get("lit"))
	await _press(KEY_M)
	assert_true(menu.is_shown(), "M shows the wrist menu")
	await _click_menu("mcc")
	assert_false(rt.sequencer.last_pad.is_empty(), "Mission Control solved an MCC")
	assert_true(dsky.lamps["uplink_acty"].get("lit"), "UPLINK ACTY on the cabin DSKY")
	assert_string_starts_with(card.pad_label.text, "PAD  MCC PAD: TIG ")
	assert_eq(card.pad_label.text, "PAD  " + str(Bus.get_value("mission.pad_text")), "the PAD on the card")
	assert_string_contains(card.capcom_label.text, "Houston, uplinking MCC PAD")
	await _click_menu("next")
	await wait_process_frames(1)
	assert_string_starts_with(_current_step(), "▶ V37E 30E", "NEXT STEP")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P2_DSKY", "the highlight moves to the DSKY")
	run(3.0, false)
	assert_false(dsky.lamps["uplink_acty"].get("lit"), "the uplink is done")
	await _keys("V37E30E")
	await wait_process_frames(1)
	assert_string_starts_with(_current_step(), "▶ Verify TIG", "typing P30 completed the step")
	# The clock from the menu, including out of the 1000x lock on the panels.
	for i in 3:
		await _click_menu("faster")
	assert_eq(SimClock.rate, 1000.0)
	assert_true(SimClock.controls_locked())
	await _click_menu("slower")
	assert_eq(SimClock.rate, 100.0, "RATE - works while the panels are locked")
	await _click_menu("pause")
	assert_true(SimClock.paused)
	await _click_menu("pause")
	assert_false(SimClock.paused)
	# Hidden, the menu lets clicks through to whatever is behind it.
	await _press(KEY_M)
	assert_false(menu.is_shown())
	var asked: Array = []
	var record := func(ch: String, v: Variant) -> void:
		if ch == "ctl.ground.pad_request":
			asked.append(v)
	Bus.value_changed.connect(record)
	_mouse(camera.unproject_position(menu.button("mcc").get_node("Touch").global_position))
	Bus.value_changed.disconnect(record)
	assert_eq(asked, [], "no PAD asked for through the hidden menu")

## Guidance shares the flight book and never operates a control for the crew.
extends GutTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")
var viewport: SubViewport
var cabin: CmCabin
var rig: Node3D
var camera: Camera3D
var book: ChecklistBook
var guide: CockpitGuide


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	viewport = SubViewport.new()
	viewport.size = Vector2i(1024, 600)
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	cabin = CmCabin.create()
	viewport.add_child(cabin)
	rig = RIG.instantiate()
	cabin.anchor.add_child(rig)
	camera = rig.get_node("Camera3D")
	camera.current = true
	book = ChecklistBook.load_default()
	book.add_walkthrough("csm")
	guide = CockpitGuide.new()
	viewport.add_child(guide)
	guide.setup(cabin, book, rig, false)


func after_each() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func test_continue_waits_for_checks_and_restart_only_rewinds_the_selected_checklist() -> void:
	book.select_for_phase("translunar_coast")
	Bus.set_value("ctl.cmc.up_tlm", false)
	guide.toggle()
	assert_true(guide.continue_button.disabled)
	guide.acknowledge()
	assert_eq(book.list().index, 0)
	Bus.set_value("ctl.cmc.up_tlm", true)
	guide.refresh()
	assert_eq(book.list().index, 1)
	assert_false(guide.continue_button.disabled)
	Bus.set_value("mission.pad_text", "MCC: TIG 004:04:18")
	Bus.set_value("mission.capcom", "Houston, uplinking MCC PAD")
	guide.refresh()
	assert_string_contains(guide.mission_label.text, "MCC: TIG 004:04:18")
	assert_string_contains(guide.mission_label.text, "Houston, uplinking MCC PAD")
	guide.continue_button.pressed.emit()
	assert_eq(book.list().index, 2)
	var flight := book.list()
	guide.tour()
	guide.acknowledge()
	var get_before := SimClock.get_seconds
	guide.restart()
	assert_eq(book.list().index, 0)
	assert_eq(flight.index, 2, "restart does not erase another checklist's progress")
	assert_true(Bus.get_value("ctl.cmc.up_tlm"), "restart never undoes crew actions")
	assert_eq(SimClock.get_seconds, get_before)
	guide.toggle()
	guide.acknowledge()
	assert_eq(book.list().index, 0, "hidden guide ignores Continue")


func test_find_reads_live_control_and_moves_only_the_desktop_view() -> void:
	guide.tour()
	book.list().index = 7
	guide.refresh()
	assert_eq(guide.target(), cabin.items["LEB_OPTICS_MODE"])
	assert_eq(guide.find_button.text, "Go to LEB + Find")
	var writes: Array[String] = []
	var record := func(channel: String, _value: Variant) -> void:
		if channel.begins_with("ctl."):
			writes.append(channel)
	Bus.value_changed.connect(record)
	guide.find_button.pressed.emit()
	Bus.value_changed.disconnect(record)
	assert_eq(writes.size(), 0, "finding does not actuate")
	assert_eq(cabin.seat, "LEB", "station change is explicit on the button")
	assert_almost_eq(rig.zoom_factor(), 2.5, 0.00001)
	var direction := (guide.target().global_position - camera.global_position).normalized()
	assert_gt((-camera.global_basis.z).dot(direction), 0.999)
	assert_string_contains(guide.state_label.text, "Positions: MAN / CMC")
	Bus.set_value("ctl.optics.mode", 1)
	guide.refresh()
	assert_string_contains(guide.state_label.text, "Current: CMC")
	var eye := camera.global_position
	rig.end_inspection()
	assert_eq(camera.global_position, eye, "Esc restores orientation and FOV within this station")
	assert_almost_eq(rig.zoom_factor(), 1.0, 0.00001)
	book.list().index = 1
	guide.find_control()
	assert_eq(guide.target(), cabin.items["P1_FDAI"], "non-interactive instruments can be found too")


func test_authentic_hides_guidance_but_allows_an_explicit_request() -> void:
	guide.tour()
	Bus.set_value("present.comfort.authentic", true)
	assert_false(guide.is_shown())
	guide.toggle()
	assert_true(guide.is_shown())
	assert_true(Bus.get_value("present.comfort.authentic"), "request leaves authentic mode intact")


func test_all_missions_offer_only_their_available_vehicle_tours_with_resolvable_targets() -> void:
	var lm := LmCabin.create()
	viewport.add_child(lm)
	for id in Mission.ids():
		for vehicle in ["csm", "lm"]:
			var b := ChecklistBook.load_default(id) if vehicle == "csm" else ChecklistBook.load_lm(id)
			var original_count := b.lists.size()
			b.add_walkthrough(vehicle)
			b.add_walkthrough(vehicle)
			assert_eq(b.lists.size(), original_count + (1 if original_count > 0 else 0), id + " " + vehicle)
			if b.lists.is_empty():
				continue
			for step in b.lists[-1].steps:
				if step.has("control"):
					var c: Cabin = cabin if vehicle == "csm" else lm
					assert_true(c.items.has(step["control"]), id + ": " + str(step["control"]))
	Mission.load_default()


func _mouse(button: MouseButton, at: Vector2, shifted: bool = false) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = button
		event.position = at
		event.global_position = at
		event.pressed = down
		event.factor = 1.0
		event.shift_pressed = shifted
		viewport.push_input(event, true)


func test_real_panel_buttons_and_scrolling_at_small_window_sizes() -> void:
	guide.tour()
	for size in [Vector2i(1024, 600), Vector2i(1280, 720)]:
		viewport.size = size
		await wait_process_frames(3)
		var bounds := Rect2(Vector2.ZERO, Vector2(size))
		assert_true(bounds.encloses(guide.panel.get_global_rect()), "panel fits %s: %s" % [size, guide.panel.get_global_rect()])
		assert_true(guide.panel.get_global_rect().encloses(guide.continue_button.get_global_rect()), "actions remain visible")
		assert_gt(guide.current_label.size.x, 200.0, "instructions have a readable line width")
		var scroll := guide.panel.find_child("StepsScroll", true, false) as ScrollContainer
		var pos := scroll.get_global_rect().get_center()
		_mouse(MOUSE_BUTTON_WHEEL_UP, pos, true)
		assert_almost_eq(rig.zoom_factor(), 1.0, 0.00001, "guide consumes Shift+wheel")
		_mouse(MOUSE_BUTTON_RIGHT, pos)
		assert_false(rig._captured, "guide consumes right-click too")
	guide.restart()
	var steps_scroll := guide.panel.find_child("StepsScroll", true, false) as ScrollContainer
	steps_scroll.scroll_vertical = 200
	_mouse(MOUSE_BUTTON_LEFT, guide.continue_button.get_global_rect().get_center())
	assert_eq(book.list().index, 1, "real GUI press acknowledges the note")
	assert_eq(steps_scroll.scroll_vertical, 0, "the next instruction returns to the top")
	_mouse(MOUSE_BUTTON_LEFT, guide.find_button.get_global_rect().get_center())
	assert_true(rig.is_inspecting(), "real Find button aims the camera")


func test_xr_find_never_changes_head_pose_fov_or_station_and_card_follows_vehicle() -> void:
	guide.free()
	guide = CockpitGuide.new()
	viewport.add_child(guide)
	guide.setup(cabin, book, rig, true)
	guide.tour()
	book.list().index = 7
	guide.refresh()
	var pose := camera.global_transform
	var fov := camera.fov
	guide.find_control()
	assert_eq(camera.global_transform, pose)
	assert_eq(camera.fov, fov)
	assert_eq(cabin.seat, "CDR", "XR Find never transports the crew")
	assert_string_contains(guide.xr_text.text, "Station: LEB")
	assert_null(guide.panel, "no 2D overlay in XR")
	var lm := LmCabin.create()
	viewport.add_child(lm)
	var lm_book := ChecklistBook.load_lm()
	lm_book.add_walkthrough("lm")
	guide.follow(lm, lm_book)
	guide.tour()
	assert_eq(guide.xr_card.get_parent(), lm.card_mount)
	assert_eq(guide.book, lm_book)
	assert_string_contains(guide.xr_text.text, "LM cockpit walkthrough")


func test_wrist_buttons_remain_visible_and_clickable_beside_the_guide_while_zoomed() -> void:
	var menu := WristMenu.new()
	menu.cabin = cabin
	menu.setup(rig, camera, null, book)
	menu.guide_panel = guide.panel
	menu._set_shown(true)
	guide.tour()
	for zoom in [1.0, 2.5, 8.0]:
		rig.set_zoom_factor(zoom)
		await wait_process_frames(3)
		await wait_physics_frames(2)
		for id in ["mcc", "tei", "pause", "seat", "walkthrough", "tour"]:
			var touch := menu.button(id).get_node("Touch") as Node3D
			var point := camera.unproject_position(touch.global_position)
			assert_true(Rect2(Vector2.ZERO, Vector2(viewport.size)).has_point(point), id + " stays on-screen")
			assert_false(guide.panel.get_global_rect().has_point(point), id + " stays clear of the guide")
		var before := cabin.seat
		_mouse(MOUSE_BUTTON_LEFT, camera.unproject_position(menu.button("seat").get_node("Touch").global_position))
		assert_ne(cabin.seat, before, "actual ray clicks SEAT at %s zoom" % zoom)
		await wait_seconds(0.3) # A far click holds a momentary button for 0.25 s.
	guide.toggle()
	await wait_process_frames(1)
	assert_eq(menu.position, WristMenu.DESKTOP_POSITION)
	assert_eq(menu.scale, Vector3.ONE)

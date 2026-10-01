## Slice 8a (docs/ROADMAP.md): the flight menu. The wrist menu's flight
## page lists every mission under data/missions/, in the order they flew,
## with its start phases and the line its data gives each; START asks the
## main scene for that flight, which starts in place of the one flown,
## every node of the old one gone and the Bus and the clock starting
## again, the headset session's channels, the player's settings and the
## headset recorder's evidence carried over. The whole flow, clicked
## through the desktop rig, is tests/scenarios/test_flight_menu.gd's.
extends GutTest

const MAIN_SCENE := "res://scenes/main.tscn"
const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func after_all() -> void:
	Mission.load_default()


func test_the_choice_lists_every_mission_in_the_order_they_flew() -> void:
	var c := FlightChoice.new()
	var ids := c.missions.map(func(m: Mission) -> String: return m.id())
	assert_eq(ids, ["apollo_8", "apollo_10", "apollo_11", "apollo_12", "apollo_13", "apollo_14", "apollo_15"])
	assert_eq(c.mission_id(), "apollo_11", "Apollo 11 by default")
	assert_eq(c.phase(), "launch", "its first start phase, on the pad")
	for m: Mission in c.missions:
		for p in m.data["start_phases"]:
			assert_ne(m.start_note(p), "", "%s's %s has its line" % [m.id(), p])
		for k: String in m.section("start_notes"):
			assert_true(k.begins_with("_") or k in m.data["start_phases"], "%s: a line for %s, a start phase" % [m.id(), k])


func test_it_steps_through_missions_and_their_start_phases() -> void:
	var c := FlightChoice.new("apollo_11", "lunar_orbit")
	assert_eq(c.phase(), "lunar_orbit", "the flight flown")
	c.step_mission(1)
	assert_eq(c.mission_id(), "apollo_12")
	assert_eq(c.phase(), "lunar_orbit", "the same phase, where the mission has it")
	c.step_mission(1)
	assert_eq(c.mission_id(), "apollo_13")
	assert_eq(c.phase(), "launch", "Apollo 13 has no lunar orbit: its first, the launch")
	c.step_mission(1)
	assert_eq(c.mission_id(), "apollo_14")
	assert_eq(c.phase(), "launch", "on the pad, as Apollo 13 was")
	c.step_mission(1)
	assert_eq(c.mission_id(), "apollo_15")
	assert_eq(c.phase(), "launch", "and Apollo 15")
	c.step_mission(1)
	assert_eq(c.mission_id(), "apollo_8", "round to the first")
	for i in 3:
		c.step_mission(-1)
	c.step_phase(-1)
	assert_eq(c.phase(), "tank_failure", "back round to the last")
	assert_eq(c.text(), "Apollo 13 - CSM Odyssey, LM Aquarius\nTANK FAILURE\n55:50 GET, five minutes before oxygen tank 2 fails")
	assert_eq(FlightChoice.phase_title("tei"), "TEI")


func test_the_wrist_menu_turns_to_its_flight_page_and_asks_for_the_flight() -> void:
	var rig: Node3D = add_child_autofree(DESKTOP_RIG.instantiate())
	var menu := WristMenu.new()
	menu.choice = FlightChoice.new("apollo_11", "parking_orbit")
	menu.setup(rig, rig.get_node("Camera3D"), null, ChecklistBook.load_default())
	menu._set_shown(true)
	for b in WristMenu.FLIGHT_BUTTONS:
		assert_false(menu.button(b[0]).is_visible_in_tree(), "%s: not on the main page" % b[0])
	menu.button("flight").actuate_far(0)
	assert_eq(menu.page, "flight")
	assert_false(menu.button("pause").is_visible_in_tree(), "the main page's buttons put away")
	assert_eq((menu.button("pause").get_node("Touch") as Area3D).collision_layer, 0, "and out of the pointer's way")
	assert_true(menu.button("start").is_visible_in_tree())
	assert_true(menu.choice_label.visible)
	assert_string_contains(menu.choice_label.text, "PARKING ORBIT")
	watch_signals(menu)
	# A pushbutton takes one press until it lets go; activate() is a press.
	menu.activate("mission_next")
	menu.activate("mission_next")
	# From its parking orbit back past its launch, round to its last.
	menu.activate("phase_prev")
	menu.activate("phase_prev")
	assert_string_contains(menu.choice_label.text, "Apollo 13")
	assert_string_contains(menu.choice_label.text, "TANK FAILURE")
	menu.button("start").actuate_far(0)
	assert_signal_emitted_with_parameters(menu, "flight_requested", ["apollo_13", "tank_failure"])
	menu.button("back").actuate_far(0)
	assert_eq(menu.page, "main")
	assert_true(menu.button("pause").is_visible_in_tree(), "BACK: the main page again")
	menu.close()
	menu.show_flights()
	assert_true(menu.is_shown(), "show_flights() opens it")
	assert_eq(menu.page, "flight", "on its flight page")


func test_the_recorder_carries_its_record_to_the_new_flight() -> void:
	var first := VrAcceptanceRecorder.new()
	add_child_autofree(first)
	Bus.set_value("present.menu.visible", true)
	first.record["recenters"].append({"at_s": 1.0})
	var carried := first.carry_state()
	var second := VrAcceptanceRecorder.new()
	second.carried = carried
	add_child_autofree(second)
	assert_true(second.record["menu_opened"], "what the first saw")
	assert_eq(second.record["recenters"].size(), 1)
	assert_eq(second.record["started_utc"], first.record["started_utc"], "one record of the session")


func test_start_flight_replaces_the_whole_flight_and_keeps_the_session() -> void:
	var main: Node = load(MAIN_SCENE).instantiate()
	main.start_phase = "lunar_orbit"
	add_child_autofree(main)
	await wait_process_frames(2)
	Bus.set_value("player.xr_session", true)
	main.rig.set("height_offset", 0.05)
	main.comfort.vignette_enabled = false
	var old_nodes: Array[WeakRef] = []
	for n in [main, main.rt.dynamics, main.rt.sequencer, main.cabin, main.lm_cabin, main.rig, main.hud, main.audio]:
		old_nodes.append(weakref(n))
	var box := [null]
	main.flight_replaced.connect(func(r: Node) -> void: box[0] = r)
	main.start_flight("apollo_8", "lunar_orbit")
	main.start_flight("apollo_10", "lunar_orbit")
	assert_null(box[0], "after the call, not in it")
	await wait_process_frames(2)
	var next: Node = box[0]
	assert_not_null(next, "a new flight")
	assert_eq(next.get_parent(), self, "in the old one's place")
	assert_eq(next.rt.mission.id(), "apollo_8", "the flight asked for first")
	assert_eq(Bus.get_value("mission.phase"), "lunar_orbit")
	assert_eq(next.rt.dynamics.config, "csm", "Apollo 8's CSM, alone")
	assert_true(bool(Bus.get_value("player.xr_session")), "the session's channels kept")
	assert_eq(float(next.rig.get("height_offset")), 0.05, "the eye height kept")
	assert_false(next.comfort.vignette_enabled, "and the comfort aids")
	for w in old_nodes:
		assert_null(w.get_ref(), "the old flight's nodes gone")
	next.rt.free_nodes()
	next.free()

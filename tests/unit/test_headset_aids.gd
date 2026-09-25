## Aids for the headset run (docs/ROADMAP.md, slice 2e): the comfort
## vignette and horizon ring, the gaze tooltip, the frame-time monitor and
## the seat switch that brings the DSKY within reach, with their wrist-menu
## buttons.
extends GutTest

const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func test_the_vignette_follows_body_rate_and_entry_g() -> void:
	var c: Comfort = add_child_autofree(Comfort.new())
	Bus.set_value("dyn.omega", Vector3(0.0, deg_to_rad(1.5), 0.0))
	c.update_from_bus()
	assert_eq(Bus.get_value("present.comfort.vignette"), 0.0, "maneuvering at the CMC's rates leaves the view alone")
	Bus.set_value("dyn.omega", Vector3(0.0, deg_to_rad(7.5), 0.0))
	c.update_from_bus()
	assert_almost_eq(float(Bus.get_value("present.comfort.vignette")), 0.5, 1e-6, "halfway from 3 to 12 deg/s")
	Bus.set_value("dyn.omega", Vector3.ZERO)
	Bus.set_value("dyn.g_load", 4.0)
	c.update_from_bus()
	assert_almost_eq(float(Bus.get_value("present.comfort.vignette")), 0.3, 1e-6, "entry: half of 60 % at 4 g")
	c.vignette_enabled = false
	c.update_from_bus()
	assert_eq(Bus.get_value("present.comfort.vignette"), 0.0, "VIGNETTE off")


func test_authentic_mode_turns_every_aid_off() -> void:
	var c: Comfort = add_child_autofree(Comfort.new())
	assert_false(c.horizon_aid, "the horizon aid starts off")
	Bus.set_value("dyn.omega", Vector3(0.0, deg_to_rad(20.0), 0.0))
	c.horizon_aid = true
	c.authentic = true
	c.update_from_bus()
	assert_eq(Bus.get_value("present.comfort.vignette"), 0.0)
	assert_false(Bus.get_value("present.comfort.horizon"))
	assert_true(Bus.get_value("present.comfort.authentic"))
	c.authentic = false
	c.update_from_bus()
	assert_true(Bus.get_value("present.comfort.horizon"))
	assert_eq(Bus.get_value("present.comfort.vignette"), 1.0)


func test_the_horizon_ring_stays_level_with_the_local_horizontal() -> void:
	var c: Comfort = add_child_autofree(Comfort.new())
	c.horizon_aid = true
	var ring: Node3D = c.get_node("HorizonRing")
	Bus.set_value("guid.indicator.attitude", Quaternion.IDENTITY)
	c.update_from_bus()
	assert_almost_eq(ring.global_basis.y, Vector3.UP, Vector3.ONE * 1e-6, "LVLH attitude: level with the cabin")
	# Nose 20 deg up: the local up leans 20 deg toward the nose (render -Z).
	Bus.set_value("guid.indicator.attitude", Quaternion(Vector3(0, 1, 0), deg_to_rad(20.0)))
	c.update_from_bus()
	var up := Vector3(0.0, cos(deg_to_rad(20.0)), -sin(deg_to_rad(20.0)))
	assert_almost_eq(ring.global_basis.y, up, Vector3.ONE * 1e-6)
	assert_almost_eq(ring.global_position, c.global_position, Vector3.ONE * 1e-9, "round the head")


func test_in_eagle_the_aids_follow_eagle() -> void:
	var c: Comfort = add_child_autofree(Comfort.new())
	c.vehicle = "lm"
	Bus.set_value("dyn.omega", Vector3(0.0, deg_to_rad(20.0), 0.0))
	Bus.set_value("dyn.g_load", 5.0)
	c.update_from_bus()
	assert_eq(Bus.get_value("present.comfort.vignette"), 0.0, "Columbia's rates and load are not Eagle's")
	Bus.set_value("lm.dyn.omega", Vector3(deg_to_rad(7.5), 0.0, 0.0))
	c.update_from_bus()
	assert_almost_eq(float(Bus.get_value("present.comfort.vignette")), 0.5, 1e-6, "Eagle's own rate")
	c.horizon_aid = true
	var ring: Node3D = c.get_node("HorizonRing")
	Bus.set_value("lm.guid.indicator.attitude", Frames.LM_LEVEL.get_rotation_quaternion())
	c.update_from_bus()
	assert_almost_eq(ring.global_basis.y, Vector3.UP, Vector3.ONE * 1e-6, "flying level: level with Eagle's cabin")
	# Windows 20 deg up (about Eagle's +Y): the local up leans 20 deg
	# toward the windows (render -Z).
	var up20 := Frames.LM_LEVEL * Basis(Vector3(0, 1, 0), deg_to_rad(20.0))
	Bus.set_value("lm.guid.indicator.attitude", up20.get_rotation_quaternion())
	c.update_from_bus()
	assert_almost_eq(ring.global_basis.y, Vector3(0.0, cos(deg_to_rad(20.0)), -sin(deg_to_rad(20.0))), Vector3.ONE * 1e-6)


func test_seat_moves_between_eagles_stations() -> void:
	var cabin := LmCabin.create()
	add_child_autofree(cabin)
	var rig: Node3D = DESKTOP_RIG.instantiate()
	cabin.anchor.add_child(rig)
	var cam: Node3D = rig.get_node("Camera3D")
	var menu := WristMenu.new()
	menu.cabin = cabin
	menu.setup(rig, cam, null, ChecklistBook.load_lm())
	menu.activate("seat")
	assert_eq(cabin.seat, "LMP", "to the LM pilot's station")
	assert_eq(Bus.get_value("player.seat"), "LMP")
	assert_almost_eq(cabin.anchor.position, LmCabin.EYE_LMP, Vector3.ONE * 1e-9)
	menu.activate("seat")
	assert_eq(cabin.seat, "CDR", "and back")


func test_the_gaze_tooltip_names_a_cabin_control_and_its_position() -> void:
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	var mode: ControlBase = cabin.items["P1_CMC_MODE"]
	Bus.set_value("ctl.cmc.mode", 1)
	assert_eq(GazeTooltip.text_for(mode), "CMC MODE\nHOLD")
	var source: ControlBase = cabin.items["P1_ATT_SOURCE"]
	assert_eq(GazeTooltip.text_for(source), "ATT SOURCE\nCMC")
	var tip: GazeTooltip = add_child_autofree(GazeTooltip.new())
	tip.observe(mode, 0.2)
	assert_eq(Bus.get_value("present.tooltip.control", ""), "", "not yet: the dwell is 0.4 s")
	tip.observe(mode, 0.3)
	assert_eq(Bus.get_value("present.tooltip.control"), "P1_CMC_MODE")
	Bus.set_value("present.comfort.authentic", true)
	tip.observe(mode, 1.0)
	assert_eq(Bus.get_value("present.tooltip.control"), "", "no tooltips in authentic mode")


func test_the_perf_monitor_measures_against_the_frame_budget() -> void:
	var p: PerfMonitor = add_child_autofree(PerfMonitor.new())
	p.set_process(false)
	p.sample(0.008)
	assert_almost_eq(float(Bus.get_value("perf.frame_ms")), 8.0, 1e-6)
	assert_false(Bus.get_value("perf.over_budget"), "8 ms is inside 90 Hz")
	p.sample(0.020)
	p.sample(0.008)
	assert_almost_eq(float(Bus.get_value("perf.frame_ms_max")), 20.0, 1e-6, "the worst of the last 90 frames")
	assert_true(Bus.get_value("perf.over_budget"), "20 ms is over 1.5 x 11.1 ms")


func test_the_seat_moves_the_player_and_the_card_but_not_the_cabin() -> void:
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	var dsky: Node3D = cabin.items["P2_DSKY"]
	var panel := cabin.panel_node("MDC2").global_transform
	var card_from_eye := cabin.card_mount.global_position - cabin.anchor.global_position
	var from_cdr := cabin.anchor.global_position.distance_to(dsky.global_position)
	assert_eq(Bus.get_value("player.seat"), "CDR", "the commander's couch to start")
	cabin.set_seat("CMP")
	assert_almost_eq(cabin.anchor.position, CmCabin.EYE_CMP, Vector3.ONE * 1e-9)
	assert_almost_eq(cabin.card_mount.global_position - cabin.anchor.global_position, card_from_eye, Vector3.ONE * 1e-6,
		"the card moves with the seat")
	assert_true(cabin.panel_node("MDC2").global_transform.is_equal_approx(panel), "the console stays put")
	var from_cmp := cabin.anchor.global_position.distance_to(dsky.global_position)
	assert_lt(from_cmp, 0.65, "the DSKY is straight ahead of the centre couch")
	assert_gt(from_cdr - from_cmp, 0.2, "and 0.2 m nearer than from the commander's")
	assert_eq(Bus.get_value("player.seat"), "CMP")
	cabin.set_seat("LMP")
	assert_eq(cabin.seat, "CMP", "only the modelled seats")


func test_wrist_menu_seat_and_comfort_buttons() -> void:
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	var rig: Node3D = DESKTOP_RIG.instantiate()
	cabin.anchor.add_child(rig)
	var cam: Node3D = rig.get_node("Camera3D")
	var comfort := Comfort.new()
	cam.add_child(comfort)
	var menu := WristMenu.new()
	menu.comfort = comfort
	menu.cabin = cabin
	menu.setup(rig, cam, null, ChecklistBook.load_default())
	menu.activate("seat")
	assert_eq(cabin.seat, "CMP")
	assert_eq(rig.get_parent(), cabin.anchor, "the rig rides the anchor to the new seat")
	menu.activate("seat")
	assert_eq(cabin.seat, "CDR")
	menu.activate("vignette")
	assert_false(comfort.vignette_enabled)
	menu.activate("horizon")
	assert_true(Bus.get_value("present.comfort.horizon"))
	menu.activate("authentic")
	assert_true(Bus.get_value("present.comfort.authentic"))
	assert_false(Bus.get_value("present.comfort.horizon"), "authentic overrides the aid")


func test_the_checklist_highlight_is_off_in_authentic_mode() -> void:
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	var book := ChecklistBook.load_default()
	book.select_for_phase("translunar_coast")
	book.next()
	var hl := ChecklistHighlight.new()
	hl.cabin = cabin
	hl.book = book
	cabin.add_child(hl)
	hl.update()
	assert_eq(hl.target_id, "P2_DSKY")
	Bus.set_value("present.comfort.authentic", true)
	hl.update()
	assert_eq(hl.target_id, "", "authentic mode")
	assert_false(Bus.get_value("present.checklist.highlight"))

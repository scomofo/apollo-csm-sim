## The cabin's panels come from data/cockpit/controls.csv (docs/ROADMAP.md,
## slice 2c): every row validates, builds onto its CmCabin panel and
## round-trips between its node and the Bus, every HUD switch has a cabin
## control, the cabin DSKY types into the CMC, and the desktop rig can
## click every control from the commander's couch.
extends SimTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")

var layout: CockpitLayout


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	layout = CockpitLayout.load_default()


func _cabin() -> CmCabin:
	var cabin := CmCabin.new()
	cabin.items = layout.build(cabin)
	add_child_autofree(cabin)
	return cabin


## Push a switch up the way a finger does until it reaches [param p]; a
## guarded switch's first push lifts the guard.
func _move(node: Node3D, p: int) -> void:
	for i in 3:
		if node.get("position_index") == p:
			return
		node.call("actuate", 1)


func _key(d: CabinDsky, key: String) -> void:
	d.keys[key].call("actuate", 0)
	d.keys[key].call("release")


func test_the_shipped_layout_validates() -> void:
	assert_gt(layout.channels.size(), 0, "channels.csv loaded")
	assert_gt(layout.rows.size(), 0, "controls.csv loaded")
	assert_true(layout.validate(), "\n".join(layout.errors))


func test_malformed_rows_are_reported() -> void:
	var bad := CockpitLayout.new()
	bad.load_channels(CockpitLayout.CHANNELS_PATH)
	bad.load_controls("res://tests/fixtures/bad_controls.csv")
	assert_false(bad.validate())
	var expect := {
		"GOOD_A": "duplicate id",
		"BAD_PANEL": "unknown panel 'MDC9'",
		"BAD_TYPE": "unknown type 'lever'",
		"BAD_CHANNEL": "channel 'ctl.eps.fc9' not in channels.csv",
		"BAD_WRITER": "a control publishes a crew ctl.* channel",
		"BAD_BIND": "a fdai can't bind the bool channel",
		"BAD_PLACE": "is off the MDC3 face",
		"BAD_OVERLAP": "overlaps",
		"BAD_INT": "positions=abc is not an integer",
		"BAD_PROP": "toggle has no property 'wobble'",
		"BAD_LABELS": "labels must name all 3 positions",
		"BAD_BOOL3": "a 3-position switch can't publish a bool",
		"BAD_ROTARY": "a rotary needs its position labels",
		"BAD_VALID": "a validated row needs confidence A or B",
		"BAD_ROLE": "role must be one of",
		"BAD_COLUMNS": "14 columns, the header has 13",
		"BAD_SCALE": "controls keep their size",
		"BAD_X": "y_mm must be a number",
		"BAD_SOURCE": "every row names its source",
	}
	for id in expect:
		var found := false
		for e in bad.errors:
			if ("(%s)" % id) in e and expect[id] in e:
				found = true
		assert_true(found, "%s: expected '%s' in\n%s" % [id, expect[id], "\n".join(bad.errors)])
	for e in bad.errors:
		assert_false(e.begins_with("row 4 (GOOD_A):"), "the good row passes: " + e)


func test_every_row_round_trips_between_its_node_and_the_bus() -> void:
	var cabin := _cabin()
	var checked := 0
	for r in layout.rows:
		var id: String = r["id"]
		var node: Node3D = cabin.items[id]
		assert_eq(node.get_parent(), cabin.panel_node(r["panel"]), "%s is on %s" % [id, r["panel"]])
		var ch: String = r["channel"]
		var as_bool := layout.channel_type(ch) == "bool"
		match r["type"]:
			"toggle", "rotary":
				var n: int = node.get("positions")
				for p in n:
					Bus.set_value(ch, (p == 1) if as_bool else p)
					assert_eq(node.get("position_index"), p, "%s follows the Bus to %d" % [id, p])
				Bus.set_value(ch, false if as_bool else 0)
				for p in range(1, n):
					_move(node, p)
					var v: Variant = Bus.get_value(ch)
					assert_eq(typeof(v), TYPE_BOOL if as_bool else TYPE_INT, "%s publishes its channel's type" % id)
					assert_eq(v, (p == 1) if as_bool else p, "%s sets the Bus to position %d" % [id, p])
			"pushbutton":
				node.call("actuate", 0)
				assert_eq(Bus.get_value(ch), true, "%s pressed" % id)
				node.call("release")
				assert_eq(Bus.get_value(ch), false, "%s released" % id)
			"lamp":
				Bus.set_value(ch, true)
				assert_true(node.get("lit"), "%s lit" % id)
				Bus.set_value(ch, false)
				assert_false(node.get("lit"), "%s out" % id)
			"numeric":
				Bus.set_value(ch, 28.37)
				assert_eq(node.call("text"), "28.4", "%s reads the Bus" % id)
			"clock":
				Bus.set_value("eps.bus_a_v", 28.0)
				Bus.set_value(ch, 3723.0)
				assert_eq(node.call("text"), "001:02:03", "%s reads the Bus" % id)
			"fdai":
				var ball: Node3D = node.get_node("Ball")
				Bus.set_value(ch, Quaternion(Vector3(0, 1, 0), 0.4))
				assert_false(ball.basis.is_equal_approx(Basis.IDENTITY), "%s turns its ball" % id)
				Bus.set_value(ch, Quaternion.IDENTITY)
				assert_true(ball.basis.is_equal_approx(Basis.IDENTITY), "%s levels its ball" % id)
			"dsky":
				var d := node as CabinDsky
				for f in CabinDsky.FIELDS:
					Bus.set_value(ch + "." + f, "+%05d" % f.length())
					assert_eq(d.fields[f].text, "+%05d" % f.length(), "%s shows %s" % [id, f])
				for lamp in d.lamps:
					Bus.set_value(ch + ".lamp." + lamp, true)
					assert_true(d.lamps[lamp].get("lit"), "%s lights %s" % [id, lamp])
				Bus.set_value(ch + ".comp_acty", true)
				assert_true(d.comp_acty, "%s shows COMP ACTY" % id)
			_:
				fail_test("%s: no round trip for type %s" % [id, r["type"]])
				continue
		checked += 1
	assert_eq(checked, layout.rows.size(), "every row checked")


func test_every_hud_switch_has_a_cabin_control() -> void:
	# Work every button of the HUD's switch panel and record what it writes.
	var hud := Hud.new()
	var panel: Control = hud.call("_switch_panel")
	var written := {}
	var record := func(ch: String, _v: Variant) -> void: written[ch] = true
	Bus.value_changed.connect(record)
	for b in panel.find_children("*", "BaseButton", true, false):
		if b is OptionButton:
			b.item_selected.emit(1)
		elif b is CheckButton:
			b.button_pressed = not b.button_pressed
		else:
			b.button_down.emit()
			b.button_up.emit()
	Bus.value_changed.disconnect(record)
	panel.free()
	hud.free()
	var cabin := {}
	for r in layout.rows:
		if CockpitLayout.TYPES[r["type"]]["control"]:
			cabin[r["channel"]] = r["id"]
	assert_eq(written.size(), 20, "the HUD's switch panel writes 20 channels")
	for ch in written:
		assert_true(cabin.has(ch), "the cabin has a control for %s" % ch)


func test_dsky_keys_type_into_the_cmc_and_it_shows_on_the_cabin_dsky() -> void:
	build("lunar_orbit")
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	cabin.connect_runtime(rt)
	var d: CabinDsky = cabin.items["P2_DSKY"]
	var names := []
	for row in DskyPanel.KEYS:
		for k in row:
			if k != "":
				names.append(k)
	names.sort()
	var have: Array = d.keys.keys()
	have.sort()
	assert_eq(have, names, "the 2D DSKY's 19 keys")
	for k in ["VERB", "1", "6", "NOUN", "6", "2", "ENTR"]:
		_key(d, k)
	assert_eq([rt.agc().dsky.verb, rt.agc().dsky.noun], ["16", "62"], "V16N62 keyed")
	assert_eq([d.fields["verb"].text, d.fields["noun"].text], ["16", "62"], "and shown")
	assert_eq(d.fields["r1"].text, rt.agc().dsky.r[0])
	for k in ["VERB", "3", "7", "ENTR", "3", "0", "ENTR"]:
		_key(d, k)
	assert_eq(d.fields["prog"].text, "30")
	assert_true(d.flash, "P30 asks for TIG")
	d._process(0.9)
	assert_false(d.fields["verb"].visible, "flash off")
	d._process(0.4)
	assert_true(d.fields["verb"].visible, "flash on")
	for k in ["VERB", "9", "9", "ENTR"]:
		_key(d, k)
	assert_true(d.lamps["opr_err"].get("lit"), "OPR ERR")
	_key(d, "RSET")
	assert_false(d.lamps["opr_err"].get("lit"), "RSET")


func test_the_desktop_rig_can_click_every_control_from_the_commanders_couch() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	var cabin := CmCabin.new()
	cabin.items = layout.build(cabin)
	viewport.add_child(cabin)
	var rig: Node3D = RIG.instantiate()
	rig.set("click_range", CmCabin.CLICK_RANGE)
	cabin.anchor.add_child(rig)
	rig.set_process_unhandled_input(false)
	(rig.get_node("Camera3D") as Camera3D).current = true
	await wait_physics_frames(2)
	var controls: Array[ControlBase] = []
	for id in cabin.items:
		if cabin.items[id] is ControlBase:
			controls.append(cabin.items[id])
		elif cabin.items[id] is CabinDsky:
			for k in cabin.items[id].keys:
				controls.append(cabin.items[id].keys[k])
	assert_eq(controls.size(), 20 + 19, "the switches, buttons and DSKY keys")
	for c in controls:
		assert_true(rig.focus_control(c), "looks at %s" % c.get_path())
		assert_eq(rig.call("_control_at", Vector2(400, 300)), c, "%s is under the pointer" % c.get_path())
		rig.end_inspection()


func test_the_commander_faces_the_console_inside_the_vessel() -> void:
	var cabin := _cabin()
	assert_true(cabin.anchor.global_basis.is_equal_approx(Basis.IDENTITY),
		"the rig looks along the render -Z, which is body +X, with the crew's up")
	assert_almost_eq(cabin.anchor.global_position, Frames.BODY_TO_GODOT * CmCabin.EYE_CDR, Vector3.ONE * 1e-6)
	for panel_name in CmCabin.PANELS:
		var p: Dictionary = CmCabin.PANELS[panel_name]
		var mount := cabin.panel_node(panel_name)
		var normal := mount.global_basis.z
		assert_gt(normal.dot(cabin.anchor.global_position - mount.global_position), 0.0, "%s faces the crew" % panel_name)
		var half: Vector2 = p["size"] * 0.5
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var c: Vector3 = p["centre"] + CmCabin.FACE_BASIS * Vector3(corner.x * half.x, corner.y * half.y, 0.0)
			assert_lt(Vector2(c.y, c.z).length(), CmCabin.wall_radius(c.x), "%s fits inside the wall" % panel_name)
	# The wall is open at the five windows and closed elsewhere: of its
	# 41 x 144 quads, the windows take 8 x 8 (twice), 8 x 4 (twice) and 7 x 6.
	var faces := (cabin.get_node("Wall") as MeshInstance3D).mesh.get_faces()
	var across := 0
	for i in range(0, faces.size(), 3):
		var m := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		if CmCabin.window_at(m.x, rad_to_deg(atan2(m.z, m.y))) != "":
			across += 1
	assert_eq(across, 0, "no wall across a window")
	assert_eq(faces.size() / 3, 2 * (41 * 144 - (2 * 64 + 2 * 32 + 42)), "the wall has the five openings")

## The cabins' panels come from data/cockpit/controls.csv (docs/ROADMAP.md,
## slice 2c) and, Eagle's, lm_controls.csv (slice 3f): every row validates,
## builds onto its panel and round-trips between its node and the Bus,
## every HUD switch has a cabin control, each cabin DSKY types into its
## computer, and the desktop rig can click every control from the
## commander's station.
extends SimTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")

var layout: CockpitLayout


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	layout = CockpitLayout.load_default()


func _cabin(p_layout: CockpitLayout = layout, lm: bool = false) -> Cabin:
	var cabin: Cabin = LmCabin.new() if lm else CmCabin.new()
	cabin.items = p_layout.build(cabin)
	add_child_autofree(cabin)
	return cabin


## Push a switch up the way a finger does until it reaches [param p]; a
## guarded switch's first push lifts the guard, and a lever-locked one's
## pulls the lever out before each move.
func _move(node: Node3D, p: int) -> void:
	for i in 6:
		if node.get("position_index") == p:
			return
		node.call("actuate", 1)


func _key(d: CabinDsky, key: String) -> void:
	d.keys[key].call("actuate", 0)
	d.keys[key].call("release")


func test_the_shipped_layouts_validate() -> void:
	assert_gt(layout.channels.size(), 0, "channels.csv loaded")
	assert_gt(layout.rows.size(), 0, "controls.csv loaded")
	assert_true(layout.validate(), "\n".join(layout.errors))
	var lm := CockpitLayout.load_lm()
	assert_eq(lm.panels, LmCabin.PANELS, "Eagle's rows go on Eagle's panels")
	assert_gt(lm.rows.size(), 0, "lm_controls.csv loaded")
	assert_true(lm.validate(), "\n".join(lm.errors))
	for r in lm.rows:
		assert_false(CmCabin.PANELS.has(r["panel"]), "%s: not on Columbia's console" % r["id"])


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
		"BAD_VALUES_N": "values must give all 3 positions a value",
		"BAD_VALUES_DUP": "two positions publish the same value",
		"BAD_VALUES_BOOL": "a switch on a bool channel publishes a bool, not values",
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
	_round_trip(layout, _cabin())
	var lm := CockpitLayout.load_lm()
	_round_trip(lm, _cabin(lm, true))


## The value [param node] publishes in position [param p].
func _value(node: Node3D, p: int) -> int:
	return node.call("value_at", p) if node.has_method("value_at") else p


func _round_trip(p_layout: CockpitLayout, cabin: Cabin) -> void:
	var checked := 0
	for r in p_layout.rows:
		var id: String = r["id"]
		var node: Node3D = cabin.items[id]
		assert_eq(node.get_parent(), cabin.panel_node(r["panel"]), "%s is on %s" % [id, r["panel"]])
		var ch: String = r["channel"]
		var as_bool := p_layout.channel_type(ch) == "bool"
		match r["type"]:
			"toggle", "rotary":
				var n: int = node.get("positions")
				for p in n:
					Bus.set_value(ch, (p == 1) if as_bool else _value(node, p))
					assert_eq(node.get("position_index"), p, "%s follows the Bus to %d" % [id, p])
				Bus.set_value(ch, false if as_bool else _value(node, 0))
				for p in range(1, n):
					_move(node, p)
					var v: Variant = Bus.get_value(ch)
					assert_eq(typeof(v), TYPE_BOOL if as_bool else TYPE_INT, "%s publishes its channel's type" % id)
					assert_eq(v, (p == 1) if as_bool else _value(node, p), "%s sets the Bus to position %d" % [id, p])
				if r["type"] == "toggle" and not (node.get("momentary_positions") as PackedInt32Array).is_empty():
					node.call("release")
					assert_eq(node.get("position_index"), node.get("rest_position"), "%s springs back" % id)
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
				var valid := str(node.get("valid_channel"))
				if valid != "":
					Bus.set_value(valid, false)
					Bus.set_value(ch, 28.37)
					assert_eq(node.call("text"), node.get("blank_text"), "%s blank without good data" % id)
					Bus.set_value(valid, true)
				Bus.set_value(ch, 28.37)
				var want := str(node.get("format")) % Units.convert(28.37, str(node.get("converter")))
				assert_eq(node.call("text"), want, "%s reads the Bus" % id)
				if id == "P3_BUS_A_VOLTS":
					assert_eq(want, "28.4")
			"clock":
				Bus.set_value("eps.bus_a_v", 28.0)
				Bus.set_value(ch, 3723.0)
				assert_eq(node.call("text"), "001:02:03", "%s reads the Bus" % id)
			"fdai":
				var ball: Node3D = node.get_node("Ball")
				var level := Frames.LM_LEVEL.get_rotation_quaternion() if node.get("vehicle") == "lm" else Quaternion.IDENTITY
				Bus.set_value(ch, level * Quaternion(Vector3(0, 1, 0), 0.4))
				assert_false(ball.basis.is_equal_approx(Basis.IDENTITY), "%s turns its ball" % id)
				Bus.set_value(ch, level)
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
	assert_eq(checked, p_layout.rows.size(), "every row checked")


func test_every_hud_switch_has_a_cabin_control() -> void:
	assert_eq(_hud_switches_without_a_control("_switch_panel", layout, 21), [], "Columbia's")
	assert_eq(_hud_switches_without_a_control("_lm_switch_panel", CockpitLayout.load_lm(), 8), [], "Eagle's")


## Work every button of the HUD's switch panel [param panel_method],
## record what it writes, and return the channels [param p_layout] has no
## control for. The panel writes [param expect] channels.
func _hud_switches_without_a_control(panel_method: String, p_layout: CockpitLayout, expect: int) -> Array:
	var hud := Hud.new()
	var panel: Control = hud.call(panel_method)
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
	for r in p_layout.rows:
		if CockpitLayout.TYPES[r["type"]]["control"]:
			cabin[r["channel"]] = r["id"]
	assert_eq(written.size(), expect, "%s writes %d channels" % [panel_method, expect])
	return written.keys().filter(func(ch: String) -> bool: return not cabin.has(ch))


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


func test_eagles_dsky_types_into_the_lgc_with_its_alt_and_vel_lamps() -> void:
	build("lunar_descent")
	var cabin := LmCabin.create()
	add_child_autofree(cabin)
	cabin.connect_runtime(rt)
	var d: CabinDsky = cabin.items["P4_DSKY"]
	assert_eq(d.dsky, rt.lgc().dsky, "panel 4's DSKY is the LGC's")
	assert_eq(d.keys.size(), 19)
	for lamp in ["uplink_acty", "temp", "no_att", "gimbal_lock", "stby", "prog", "key_rel", "restart", "opr_err", "tracker", "alt", "vel"]:
		assert_true(d.lamps.has(lamp), "the LGC's %s lamp" % lamp)
	for k in ["VERB", "1", "6", "NOUN", "6", "8", "ENTR"]:
		_key(d, k)
	assert_eq([rt.lgc().dsky.verb, rt.lgc().dsky.noun], ["16", "68"], "V16N68 keyed into the LGC")
	assert_ne(rt.agc().dsky.noun, "68", "not the CMC")
	assert_eq([d.fields["verb"].text, d.fields["noun"].text], ["16", "68"], "and shown")
	Bus.set_value("lm.dsky.lamp.alt", true)
	Bus.set_value("lm.dsky.lamp.vel", false)
	assert_true(d.lamps["alt"].get("lit"), "ALT: no landing radar altitude")
	assert_false(d.lamps["vel"].get("lit"))
	# Seven rows of lamps in the height of the CMC's five, clear of the keys.
	var lowest: Node3D = d.lamps["vel"]
	assert_gt(lowest.position.y - 0.010 * lowest.scale.y, d.keys["7"].position.y + 0.0125, "above the keys")
	assert_lt(d.lamps["uplink_acty"].position.y + 0.010 * lowest.scale.y, CabinDsky.SIZE.y * 0.5, "on the case")


func test_the_desktop_rig_can_click_every_control_from_the_commanders_station() -> void:
	await _click_every_control(CmCabin.new(), layout, 21 + 19)
	await _click_every_control(LmCabin.new(), CockpitLayout.load_lm(), 8 + 19)


## Build [param p_layout] onto [param cabin] in a viewport and point the
## desktop rig at each of its [param expect] controls from the commander's
## eye: each is the one under the pointer.
func _click_every_control(cabin: Cabin, p_layout: CockpitLayout, expect: int) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 600)
	viewport.own_world_3d = true
	add_child_autofree(viewport)
	cabin.items = p_layout.build(cabin)
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
	assert_eq(controls.size(), expect, "%s: the switches, buttons and DSKY keys" % cabin.name)
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

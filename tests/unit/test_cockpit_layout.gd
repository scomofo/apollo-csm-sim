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


## A key on a cabin DSKY or DEDA [param d], pressed and let go.
func _key(d: Node3D, key: String) -> void:
	var keys: Dictionary = d.get("keys")
	keys[key].call("actuate", 0)
	keys[key].call("release")


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
func _value(node: Node3D, p: int) -> Variant:
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
					var want: int = {"bool": TYPE_BOOL, "float": TYPE_FLOAT}.get(p_layout.channel_type(ch), TYPE_INT)
					assert_eq(typeof(v), want, "%s publishes its channel's type" % id)
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
			"deda":
				var dd := node as CabinDeda
				Bus.set_value(ch + ".addr", "377")
				Bus.set_value(ch + ".data", "+00012")
				assert_eq([dd.fields["addr"].text, dd.fields["data"].text], ["377", "+00012"], "%s shows its windows" % id)
				Bus.set_value(ch + ".opr_err", true)
				assert_true(dd.opr_err.get("lit"), "%s lights OPR ERR" % id)
				Bus.set_value(ch + ".opr_err", false)
			"optics":
				# The eyepieces show the optics' view, rendered off the panel.
				var view: OpticsView = node.get("view")
				assert_not_null(view, "%s has the optics' view" % id)
				assert_eq(Vector2i(view.size), node.get("viewport").size, "%s: the view fills its viewport" % id)
				var face: MeshInstance3D = node.get_node("Face")
				assert_eq((face.material_override as StandardMaterial3D).albedo_texture, node.get("viewport").get_texture(),
					"%s shows it on its face" % id)
			"aot":
				# The AOT's eyepiece shows its view, rendered off the panel.
				var view: AotView = node.get("view")
				assert_not_null(view, "%s has the AOT's view" % id)
				assert_eq(Vector2i(view.size), node.get("viewport").size, "%s: the view fills its viewport" % id)
				var face: MeshInstance3D = node.get_node("Face")
				assert_eq((face.material_override as StandardMaterial3D).albedo_texture, node.get("viewport").get_texture(),
					"%s shows it on its face" % id)
			_:
				fail_test("%s: no round trip for type %s" % [id, r["type"]])
				continue
		checked += 1
	assert_eq(checked, p_layout.rows.size(), "every row checked")


func test_every_hud_switch_has_a_cabin_control() -> void:
	# SPS THRUST ON is the HUD's manual backup: the cabin's is a lamp.
	assert_eq(_hud_switches_without_a_control("_switch_panel", layout, 47), ["ctl.sps.thrust_on"], "Columbia's")
	assert_eq(_hud_switches_without_a_control("_optics_panel", layout, 5), [], "the optics'")
	assert_eq(_hud_switches_without_a_control("_lm_switch_panel", CockpitLayout.load_lm(), 22), [], "Eagle's")
	assert_eq(_hud_switches_without_a_control("_aot_panel", CockpitLayout.load_lm(), 5), [], "the AOT's")


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


func test_the_dedas_keys_key_into_the_ags_and_it_shows_on_panel_6() -> void:
	build("lunar_ascent")
	var cabin := LmCabin.create()
	add_child_autofree(cabin)
	cabin.connect_runtime(rt)
	var d: CabinDeda = cabin.items["P6_DEDA"]
	assert_eq(d.ags, rt.systems["ags"], "panel 6's DEDA is the AGS's")
	var names: Array = Deda.KEYS.duplicate()
	names.sort()
	var have: Array = d.keys.keys()
	have.sort()
	assert_eq(have, names, "the DEDA's 16 keys")
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	for k in ["CLR", "4", "1", "0", "+", "3", "0", "0", "0", "0", "ENTR"]:
		_key(d, k)
	assert_eq(rt.systems["ags"].fp6.s10, 3, "410+30000: TPI search")
	for k in ["CLR", "4", "1", "0", "READOUT"]:
		_key(d, k)
	run(0.6, false)
	assert_eq([d.fields["addr"].text, d.fields["data"].text], ["410", "+30000"], "read out on panel 6")
	_key(d, "5")
	assert_true(d.opr_err.get("lit"), "a key during a readout: OPR ERR")
	_key(d, "CLR")
	assert_false(d.opr_err.get("lit"), "CLR")
	# The HUD's DEDA keys into the same AGS.
	var panel := DedaPanel.new()
	panel.setup(rt.systems["ags"], ThemeDB.fallback_font)
	add_child_autofree(panel)
	var buttons := {}
	for b: Button in panel.find_children("*", "Button", true, false):
		buttons[b.text.replace("\n", "")] = b
	assert_eq(buttons.size(), 16, "the HUD's DEDA has its 16 keys")
	for k in ["CLR", "4", "1", "0", "READOUT"]:
		buttons[k].pressed.emit()
	assert_eq(Bus.get_value("lm.deda.data"), "+30000", "and reads out on the HUD's")


func test_the_desktop_rig_can_click_every_control_from_its_station() -> void:
	# Columbia's console from the commander's couch; the optics' switches
	# and the second DSKY from the lower equipment bay. Eagle's from the
	# commander's station, the AOT's overhead among them, and panel 6's
	# DEDA and AGS STATUS from the LM pilot's.
	await _click_every_control(CmCabin.new(), layout, 47 + 19 + 6 + 19)
	await _click_every_control(LmCabin.new(), CockpitLayout.load_lm(), 24 + 5 + 19 + 16)


## Build [param p_layout] onto [param cabin] in a viewport and point the
## desktop rig at each of its [param expect] controls from the eye of its
## station (the lower equipment bay for the LEB panel's, the commander's
## for the rest): each is the one under the pointer.
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
	var panels: Array[String] = []
	for id in cabin.items:
		var panel := str((cabin.items[id].get_meta("row") as Dictionary)["panel"])
		if cabin.items[id] is ControlBase:
			controls.append(cabin.items[id])
			panels.append(panel)
		elif cabin.items[id] is CabinDsky or cabin.items[id] is CabinDeda:
			for k in cabin.items[id].keys:
				controls.append(cabin.items[id].keys[k])
				panels.append(panel)
	assert_eq(controls.size(), expect, "%s: the switches, buttons and DSKY and DEDA keys" % cabin.name)
	var home: String = cabin.seats().keys()[0]
	for i in controls.size():
		var c := controls[i]
		var station: String = {"LEB122": "LEB", "P6": "LMP"}.get(panels[i], home)
		if cabin.seat != station:
			cabin.set_seat(station)
			await wait_physics_frames(1)
		assert_true(rig.focus_control(c), "looks at %s from %s" % [c.get_path(), station])
		assert_eq(rig.call("_control_at", Vector2(400, 300)), c, "%s is under the pointer" % c.get_path())
		rig.end_inspection()


func test_the_commander_faces_the_console_inside_the_vessel() -> void:
	var cabin := _cabin()
	for panel_name in CmCabin.PANELS:
		var mount := cabin.panel_node(panel_name)
		var fasteners := mount.get_children().filter(func(n: Node) -> bool: return n.name.begins_with("Fastener"))
		assert_eq(fasteners.size(), 4,
			"%s has four raised panel fasteners" % panel_name)
		for edge in ["RevealTop", "RevealBottom", "RevealLeft", "RevealRight"]:
			assert_true(mount.has_node(edge), "%s has its %s" % [panel_name, edge])
<<<<<<< ours
<<<<<<< ours
=======
	for window_name in CmCabin.WINDOWS:
		var retainer := cabin.get_node(window_name + "Retainer")
		assert_eq(retainer.get_child_count(), 8, "%s has a gasket and four-piece retainer" % window_name)
>>>>>>> theirs
=======
	for window_name in CmCabin.WINDOWS:
		var retainer := cabin.get_node(window_name + "Retainer")
		assert_eq(retainer.get_child_count(), 8, "%s has a gasket and four-piece retainer" % window_name)
>>>>>>> theirs
	assert_true(cabin.anchor.global_basis.is_equal_approx(Basis.IDENTITY),
		"the rig looks along the render -Z, which is body +X, with the crew's up")
	assert_almost_eq(cabin.anchor.global_position, Frames.BODY_TO_GODOT * CmCabin.EYE_CDR, Vector3.ONE * 1e-6)
	var all := cabin.panels()
	for panel_name in all:
		var p: Dictionary = all[panel_name]
		var mount := cabin.panel_node(panel_name)
		var normal := mount.global_basis.z
		# The console faces the commander, the navigation panel its station.
		cabin.set_seat("LEB" if panel_name == "LEB122" else "CDR")
		assert_gt(normal.dot(cabin.anchor.global_position - mount.global_position), 0.0, "%s faces the crew" % panel_name)
		var half: Vector2 = p["size"] * 0.5
		for corner in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var c: Vector3 = p["centre"] + (p["basis"] as Basis) * Vector3(corner.x * half.x, corner.y * half.y, 0.0)
			assert_lt(Vector2(c.y, c.z).length(), CmCabin.wall_radius(c.x), "%s fits inside the wall" % panel_name)
	cabin.set_seat("CDR")
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


func test_navigation_panel_faces_the_navigator_at_the_lower_bay() -> void:
	var cabin := _cabin()
	cabin.set_seat("LEB")
	var mount := cabin.panel_node("LEB122")
	var to_panel := mount.global_position - cabin.anchor.global_position
	assert_gt(to_panel.normalized().dot(-cabin.anchor.global_basis.z), 0.999,
		"the panel is straight ahead when the navigator selects the bay")
	assert_gt(mount.global_basis.z.dot(-to_panel.normalized()), 0.999,
		"the navigation panel faces the navigator, not the couches")
	assert_gt(mount.global_basis.y.dot(cabin.anchor.global_basis.y), 0.999,
		"the optics, DSKY and legends are upright at the station")
	assert_between(to_panel.length(), 0.4, 0.65, "the panel is within a seated arm's reach")


func test_window_frames_follow_the_shell_without_floating_or_sinking() -> void:
	var cabin := _cabin()
	for window_name in CmCabin.WINDOWS:
		var root := cabin.get_node(window_name + "Retainer")
		var shallow := INF
		var deep := -INF
		for child in root.get_children():
			if child is MeshInstance3D:
				for p in (child as MeshInstance3D).mesh.get_faces():
					var depth := Vector2(p.y, p.z).length() - CmCabin.wall_radius(p.x)
					shallow = minf(shallow, depth)
					deep = maxf(deep, depth)
		# The previous centre-radius boxes floated by roughly 9 cm at one
		# end and disappeared into the shell at the other.
		assert_almost_eq(shallow, -0.014, 0.0001, "%s retainer follows the taper" % window_name)
		assert_almost_eq(deep, 0.055, 0.0001, "%s has a recessed liner" % window_name)
		var heads := root.get_node("FastenerHeads") as MultiMeshInstance3D
		assert_eq(heads.multimesh.instance_count, 12, "%s batches its fasteners" % window_name)
		# Godot 4.4's dummy renderer returns identity for every MultiMesh
		# transform. Run this additional check with a real renderer; the
		# shell-depth and aperture-triangle checks work headless as well.
		if DisplayServer.get_name() == "headless":
			continue
		for i in heads.multimesh.instance_count:
			var t := heads.multimesh.get_instance_transform(i)
			var radial := Vector3(0, t.origin.y, t.origin.z).normalized()
			var inward := -(Vector3.RIGHT * CmCabin.VESSEL_SLOPE + radial).normalized()
			assert_gt(t.basis.y.dot(inward), 0.999, "%s screw faces into the cabin" % window_name)


func test_window_surrounds_close_the_edges_and_keep_the_view_clear() -> void:
	var cabin := _cabin()
	for window_name in CmCabin.WINDOWS:
		var root := cabin.get_node(window_name + "Retainer")
		var faces := PackedVector3Array()
		for child in root.get_children():
			if child is MeshInstance3D:
				faces.append_array((child as MeshInstance3D).mesh.get_faces())
		# Check actual triangles, not just the construction parameters. The
		# left-side window also exercises the +/-180 degree seam.
		for uv in [Vector2.ZERO, Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(0.7, 0.7), Vector2(-0.7, 0.7)]:
			assert_false(_window_ray_hits(faces, window_name, uv, 0.0), "%s viewing aperture is clear at %s" % [window_name, uv])
		for uv in [Vector2(-1, 0), Vector2(1, 0), Vector2(0, -1), Vector2(0, 1),
				Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			assert_true(_window_ray_hits(faces, window_name, uv, 0.017), "%s frame closes the edge at %s" % [window_name, uv])


func _window_ray_hits(faces: PackedVector3Array, window_name: String, uv: Vector2, margin: float) -> bool:
	var from := CmCabin.window_point(window_name, uv, margin, -0.12)
	var to := CmCabin.window_point(window_name, uv, margin, 0.15)
	for i in range(0, faces.size(), 3):
		if Geometry3D.segment_intersects_triangle(from, to, faces[i], faces[i + 1], faces[i + 2]) != null:
			return true
	return false

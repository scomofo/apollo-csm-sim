## Read-only crew guidance over the shared ChecklistBook. Inspired by
## gemini-capsule's cockpit_guide.gd at 03ae202 (docs/WALKTHROUGH.md).
## Selection, restart and Find never operate flight controls or advance time.
class_name CockpitGuide
extends Node

signal cabin_view_requested
signal shown_changed(shown: bool)

const ACCENT := Color(0.50, 0.91, 0.74)
var book: ChecklistBook
var cabin: Cabin
var rig: Node3D
var xr := false
var panel: PanelContainer
var selector: OptionButton
var current_label: Label
var state_label: Label
var progress_label: Label
var nearby_label: Label
var mission_label: Label
var continue_button: Button
var find_button: Button
var reopen_button: Button
var xr_card: Node3D
var xr_text: Label3D
var _layer: CanvasLayer
var _shown := false
var _capture_visible := true
var _last_shown := false
var _elapsed := 0.0
var _scroll: ScrollContainer
var _shown_step := ""


func setup(c: Cabin, b: ChecklistBook, player: Node3D, headset: bool) -> void:
	cabin = c
	book = b
	rig = player
	xr = headset
	if xr:
		_build_xr()
	else:
		_build_desktop()
	Bus.subscribe("present.comfort.authentic", _authentic_changed)
	follow(c, b)


func _exit_tree() -> void:
	Bus.unsubscribe("present.comfort.authentic", _authentic_changed)
	if is_instance_valid(xr_card):
		xr_card.queue_free()


func follow(c: Cabin, b: ChecklistBook) -> void:
	cabin = c
	book = b
	if selector:
		selector.clear()
		for checklist in book.lists:
			selector.add_item(checklist.title)
	if xr_card:
		xr_card.reparent(c.card_mount, false)
	refresh()


func is_shown() -> bool:
	return _shown and _capture_visible


func toggle() -> void:
	_shown = not is_shown()
	if _shown and not xr:
		rig.release_mouse_look()
	refresh()


func _authentic_changed(value: Variant) -> void:
	if bool(value):
		_shown = false
	refresh()


func set_capture_visible(on: bool) -> void:
	_capture_visible = on
	refresh()


func select(index: int) -> void:
	book.select(index)
	refresh()


func next_guide() -> void:
	_shown = true
	select(book.current + 1)
	if not xr:
		rig.release_mouse_look()


func tour() -> void:
	for i in book.lists.size():
		if book.lists[i].title.ends_with("cockpit walkthrough"):
			_shown = true
			select(i)
			cabin_view_requested.emit()
			if not xr:
				rig.release_mouse_look()
			return


func restart() -> void:
	if book.list():
		book.list().index = 0
	refresh()


func acknowledge() -> void:
	if is_shown():
		book.next()
	refresh()


func target() -> Node3D:
	var id := ChecklistHighlight.resolve(cabin, book.target())
	return cabin.items.get(id)


func station_for(node: Node3D) -> String:
	var row: Dictionary = node.get_meta("row", {})
	match str(row.get("panel", "")):
		"LEB122": return "LEB"
		"P6": return "LMP"
		"MDC2": return "CMP"
	return "CDR"


func find_control() -> void:
	var node := target()
	if node == null:
		return
	_shown = true
	if xr:
		refresh()
		return
	cabin_view_requested.emit()
	var station := station_for(node)
	if cabin.seat != station:
		cabin.set_seat(station)
		if not xr:
			rig.recenter()
	if not xr:
		rig.focus_control(node)
		rig.release_mouse_look()
	refresh()


func control_text() -> String:
	var node := target()
	if node == null:
		return ""
	var row: Dictionary = node.get_meta("row", {})
	var text := "%s · %s\nStation: %s" % [str(row.get("label", node.name)), str(row.get("panel", "")), station_for(node)]
	if node is ControlBase:
		text += "\nCurrent: " + GazeTooltip.state_text(node)
		if "labels" in node:
			text += "\nPositions: " + " / ".join(node.get("labels"))
		if "guarded" in node and bool(node.get("guarded")):
			text += "\nLift the guard before operating."
		if "lever_lock" in node and bool(node.get("lever_lock")):
			text += "\nPull the locked lever before moving it."
	elif node is CabinDsky:
		text += "\nPROG %s · VERB %s · NOUN %s" % [Bus.get_value(node.channel + ".prog", "--"),
			Bus.get_value(node.channel + ".verb", "--"), Bus.get_value(node.channel + ".noun", "--")]
	return text


func status_text() -> String:
	var c := book.list()
	if c == null or c.done():
		return "Complete. Choose another checklist when ready."
	if not c.current().has("check"):
		return "Read and perform this instruction, then Continue."
	var check: Dictionary = c.current()["check"]
	var channel := str(check["channel"])
	var value: Variant = Bus.get_value(channel)
	var text := "Waiting for the checked condition. Continue cannot skip it."
	# Flight events and instrument readings have no switch position to show.
	if target() == null or not target() is ControlBase:
		text += "\nObserved: %s · Required: %s %s" % [str(value) if value != null else "not available",
			{"eq": "=", "ne": "not", "gt": ">", "ge": ">=", "lt": "<", "le": "<="}.get(check.get("op", "eq"), "="), str(check["value"])]
	if SimClock.controls_locked():
		text += "\nReduce time rate with [ or wrist RATE - to operate controls."
	return text


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1:
		_elapsed = 0.0
		refresh()


func refresh() -> void:
	if book == null:
		return
	book.update()
	var c := book.list()
	var visible_now := is_shown()
	if panel:
		panel.visible = visible_now
		reopen_button.visible = not visible_now and _capture_visible
	if xr_card:
		xr_card.visible = visible_now
	if visible_now != _last_shown:
		_last_shown = visible_now
		shown_changed.emit(visible_now)
	if c == null or not visible_now:
		return
	var progress := "%s · %d of %d completed" % ["LM" if cabin is LmCabin else "CM", mini(c.index, c.steps.size()), c.steps.size()]
	progress += " · PAUSED" if SimClock.paused else " · " + str(SimClock.rate) + "×"
	var instruction := str(c.current().get("text", "Checklist complete."))
	var state := status_text()
	var reading := control_text()
	if reading != "":
		state += "\n\n" + reading
	if panel:
		var step_key := c.title + ":" + str(c.index)
		if step_key != _shown_step:
			_scroll.scroll_vertical = 0
			_shown_step = step_key
		selector.select(book.current)
		progress_label.text = progress
		current_label.text = instruction
		state_label.text = state
		mission_label.text = "PAD\n" + str(Bus.get_value("mission.pad_text", "None uplinked.")) + "\n\nCAPCOM\n" + str(Bus.get_value("mission.capcom", "No call yet."))
		continue_button.disabled = c.done() or c.current().has("check")
		find_button.disabled = target() == null
		find_button.text = "Find control" if target() == null or station_for(target()) == cabin.seat else "Go to " + station_for(target()) + " + Find"
		var lines := PackedStringArray()
		for s in book.window(1, 5):
			lines.append(("✓ " if s["state"] == "done" else ("› " if s["state"] == "current" else "  ")) + str(s["text"]))
		nearby_label.text = "NEARBY STEPS\n\n" + "\n\n".join(lines)
	else:
		xr_text.text = c.title + "\n" + progress + "\n\n" + instruction + "\n\n" + state + "\n\nWrist: NEXT STEP · CHECKLIST · FIND CTRL\nWALKTHRU hides this guide for PAD / CAPCOM."
		# Fit long flight instructions onto the card without clipping.
		xr_text.pixel_size = 0.00011
		var height := xr_text.font.get_multiline_string_size(xr_text.text, HORIZONTAL_ALIGNMENT_LEFT, xr_text.width, xr_text.font_size).y
		xr_text.pixel_size = minf(0.00011, 0.35 / maxf(height, 1.0))


func _label(parent: Node, size: int, colour: Color = Color(0.91, 0.94, 0.96)) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.mouse_force_pass_scroll_events = false
	button.pressed.connect(action)
	parent.add_child(button)
	return button


func _build_desktop() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6
	add_child(_layer)
	panel = PanelContainer.new()
	panel.name = "WalkthroughPanel"
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_force_pass_scroll_events = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.070, 0.98)
	style.set_content_margin_all(16)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.43, 0.42)
	panel.add_theme_stylebox_override("panel", style)
	_layer.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var heading := _label(header, 17, ACCENT)
	heading.text = "FLIGHT WALKTHROUGH"
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "Hide [F2]", toggle)
	selector = OptionButton.new()
	selector.name = "ChecklistSelector"
	selector.fit_to_longest_item = false
	selector.focus_mode = Control.FOCUS_NONE
	selector.mouse_force_pass_scroll_events = false
	selector.custom_minimum_size.y = 34
	selector.item_selected.connect(select)
	body.add_child(selector)
	var choices := HBoxContainer.new()
	body.add_child(choices)
	_button(choices, "Cockpit tour", tour)
	_button(choices, "Restart checklist", restart)
	progress_label = _label(body, 14, ACCENT)
	var scroll := ScrollContainer.new()
	_scroll = scroll
	scroll.name = "StepsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.mouse_filter = Control.MOUSE_FILTER_STOP
	scroll.mouse_force_pass_scroll_events = false
	body.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	_label(content, 13, ACCENT).text = "CURRENT STEP"
	current_label = _label(content, 21)
	state_label = _label(content, 16)
	mission_label = _label(content, 14, Color(0.78, 0.85, 0.87))
	nearby_label = _label(content, 14, Color(0.65, 0.73, 0.78))
	var actions := HBoxContainer.new()
	body.add_child(actions)
	continue_button = _button(actions, "Continue [F3]", acknowledge)
	find_button = _button(actions, "Find control", find_control)
	_label(body, 13, Color(0.65, 0.73, 0.78)).text = "P pause · F1 flights · Shift+F2 next guide\nEsc restores inspection · Z / Shift+wheel zoom"
	reopen_button = _button(_layer, "Walkthrough [F2]", toggle)
	get_viewport().size_changed.connect(_layout)
	panel.minimum_size_changed.connect(_layout.call_deferred)
	_layout()


func _layout() -> void:
	var size := get_viewport().get_visible_rect().size
	var width := minf(390.0, size.x - 24.0)
	panel.position = Vector2(size.x - width - 12.0, 58.0)
	panel.size = Vector2(width, maxf(280.0, minf(710.0, size.y - 74.0)))
	reopen_button.position = Vector2(size.x - 184.0, size.y - 48.0)
	reopen_button.size = Vector2(172.0, 36.0)


func _build_xr() -> void:
	xr_card = Node3D.new()
	xr_card.name = "WalkthroughCard"
	add_child(xr_card)
	var plate := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.36, 0.40, 0.003)
	plate.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.035, 0.055, 0.07)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plate.material_override = mat
	xr_card.add_child(plate)
	xr_text = Label3D.new()
	xr_text.font = ThemeDB.fallback_font
	xr_text.font_size = 40
	xr_text.width = 2900
	xr_text.outline_size = 0
	xr_text.modulate = Color(0.91, 0.94, 0.96)
	xr_text.position = Vector3(-0.16, 0.18, 0.003)
	xr_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	xr_text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	xr_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	xr_text.double_sided = false
	xr_card.add_child(xr_text)

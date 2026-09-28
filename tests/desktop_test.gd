## Shared harness for the desktop scenario tests: the whole main scene
## (scenes/main.tscn) in its own viewport, worked the way a player at the
## desktop works it. The keys go through the viewport to the main scene's
## input handling (the DSKY keys, L, H); the HUD's buttons are clicked
## where they show, the viewport's GUI taking the click to them; a HUD
## switch or the checklist choice is set by picking a position on it; and
## the hand controllers fly on keys held down, which HandControllerInput
## reads. Time runs as SimTest's fly(), a frame between chunks so the HUD
## keeps up with the Bus. [Headless, the HUD's fonts fall back to wider
## ones than a desktop's, so its layout runs longer than on the screen:
## the renders in docs/images show it at the window's size.]
##
## With in_cabin, the player works the cabin of the vehicle flown instead
## (the cabin view, C): the rig looks at a control and a left click or the
## wheel goes through its input handling, the DSKY is typed on the cabin
## DSKY's keys, the checklist is read off the card and turned with the
## wrist menu, and the panels are unlocked with the menu's RATE - after a
## fast coast, as a player must. The same calls do either, so one flight
## can be flown from the HUD and from the cabin.
class_name DesktopTest
extends SimTest

const MAIN := preload("res://scenes/main.tscn")
## The screen the HUD lays out on.
const SCREEN := Vector2i(1600, 900)
## The DSKY keys by the letters SimTest.keys() uses (P is PRO: Space).
const DSKY_KEYS := {"V": KEY_V, "N": KEY_N, "E": KEY_ENTER, "P": KEY_SPACE, "C": KEY_BACKSPACE,
	"K": KEY_INSERT, "R": KEY_DELETE, "+": KEY_EQUAL, "-": KEY_MINUS}
## The translation controller's keys, [+, -] along each body axis: the
## CSM's X forward, Y right, Z down; the LM's X up, Y right, Z forward.
const CSM_THC_KEYS := [[KEY_R, KEY_F], [KEY_RIGHT, KEY_LEFT], [KEY_DOWN, KEY_UP]]
const LM_TTCA_KEYS := [[KEY_R, KEY_F], [KEY_RIGHT, KEY_LEFT], [KEY_UP, KEY_DOWN]]
## The rotation controller's keys, [+, -] about each body axis Y and Z:
## the CSM's pitch and yaw, the LM's pitch and roll.
const CSM_RHC_KEYS := {1: [KEY_S, KEY_W], 2: [KEY_D, KEY_A]}
const LM_ACA_KEYS := {1: [KEY_S, KEY_W], 2: [KEY_E, KEY_Q]}
## The cabin DSKY's keys by the letters SimTest.keys() uses.
const CABIN_KEYS := {"V": "VERB", "N": "NOUN", "E": "ENTR", "P": "PRO", "C": "CLR", "K": "KEY REL", "R": "RSET"}

var viewport: SubViewport
var main: Node
var hud: Hud
## Work the cabin of the vehicle flown, not the HUD.
var in_cabin: bool = false


## Start the main scene at [param phase], as --phase= does, with the help
## overlay put away (H), and in the cabin view with in_cabin.
func start(phase: String) -> void:
	Bus.reset()
	SimClock.reset()
	viewport = SubViewport.new()
	viewport.size = SCREEN
	viewport.own_world_3d = true
	viewport.handle_input_locally = true
	add_child_autofree(viewport)
	main = MAIN.instantiate()
	main.start_phase = phase
	viewport.add_child(main)
	rt = main.rt
	hud = main.hud
	await wait_process_frames(2)
	press(KEY_H)
	if in_cabin:
		for i in 3:
			if main.view.view_mode == 2:
				break
			press(KEY_C)
		assert_eq(main.view.view_mode, 2, "the cabin view")
		await wait_physics_frames(2)


# --- the keys and the mouse ----------------------------------------------------

## A key pressed and let go.
func press(code: Key) -> void:
	for down in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = code
		ev.physical_keycode = code
		ev.pressed = down
		viewport.push_input(ev, true)


## Type [param seq] on the DSKY of the vehicle flown, "V37E30E" style as
## SimTest.keys(): on the keys, or on the cabin DSKY's keys. Typing takes a
## moment of flight, a fixed step, in which the computer puts what the
## keys did on the Bus.
func type(seq: String) -> void:
	if in_cabin:
		var d := cabin_dsky()
		for ch in seq:
			var key: ControlBase = d.keys[CABIN_KEYS.get(ch, ch)]
			await let_go(key)
			await rig_click(key, 0, 0.0, false)
	else:
		for ch in seq:
			press(DSKY_KEYS[ch] if DSKY_KEYS.has(ch) else (KEY_0 + int(ch)) as Key)
	run(SimClock.FIXED_DT, false)


## The HUD button reading [param text] that shows, or null.
func button(text: String) -> BaseButton:
	for b in hud.find_children("*", "BaseButton", true, false):
		if b.text == text and b.is_visible_in_tree():
			return b
	return null


## Click the HUD button reading [param text] where it shows, or in the
## cabin the control lettered [param text], [param hold_s] seconds of
## flight passing while it is held down.
func click(text: String, hold_s: float = 0.0) -> void:
	if in_cabin:
		var c := cabin_control(text)
		assert_not_null(c, "%s is in %s" % [text, cabin().name])
		if c != null:
			await unlock_panels()
			await rig_click(c, 0, hold_s)
		return
	var b := button(text)
	assert_not_null(b, "%s shows on the HUD" % text)
	if b == null:
		return
	var downs := [0]
	var down := func() -> void: downs[0] += 1
	b.button_down.connect(down)
	var at := b.get_global_rect().get_center()
	_mouse(at, true)
	b.button_down.disconnect(down)
	assert_eq(downs[0], 1, "the click went to %s" % text)
	if hold_s > 0.0:
		run(hold_s, false)
	_mouse(at, false)


func _mouse(at: Vector2, down: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.global_position = at
	ev.pressed = down
	viewport.push_input(ev, true)


## Turn the HUD switch that writes [param channel] to [param position], as
## picking the position on it does; or in the cabin, push the control that
## writes it up or down, a wheel step at a time, until it reads the
## position (a lever-locked switch takes a pull before each move).
func set_switch(channel: String, position: int) -> void:
	if in_cabin:
		var id := ChecklistHighlight.resolve(cabin(), {"channel": channel})
		assert_ne(id, "", "a control in %s writes %s" % [cabin().name, channel])
		if id == "":
			return
		var c: ControlBase = cabin().items[id]
		var target := position
		for i in int(c.get("positions")):
			if (c.call("value_at", i) if c.has_method("value_at") else i) == position:
				target = i
		await unlock_panels()
		for i in 12:
			var at: int = c.get("position_index")
			if at == target:
				break
			await rig_click(c, 1 if target > at else -1)
		assert_eq(Bus.get_value(channel), position, "%s at %d" % [channel, position])
		return
	var o: OptionButton = hud._options[channel]
	assert_true(o.is_visible_in_tree(), "%s shows on the HUD" % channel)
	o.select(position)
	o.item_selected.emit(position)
	assert_eq(Bus.get_value(channel), position, "%s at %d" % [channel, position])


# --- the cabin ------------------------------------------------------------------

## The cabin of the vehicle flown.
func cabin() -> Cabin:
	return main.cabin_for(main.vehicles.vehicle)


## The cabin's DSKY.
func cabin_dsky() -> CabinDsky:
	for id in cabin().items:
		if cabin().items[id] is CabinDsky:
			return cabin().items[id]
	return null


## The cabin's control lettered [param text], or null.
func cabin_control(text: String) -> ControlBase:
	for id in cabin().items:
		var c: Node = cabin().items[id]
		if c is ControlBase and (c as ControlBase).label == text:
			return c
	return null


## Look at [param control] with the rig and click it (a left click cycles
## it, the wheel pushes it up or down, [param dir] +1 or -1), with
## [param hold_s] seconds of flight while a pushbutton is held down. The
## rig's look reaches the physics server a step later, so the click waits
## for one, as a hand on a mouse does. Unless [param wait_release] is
## false, it returns once a pushbutton has let go again.
func rig_click(control: ControlBase, dir: int = 0, hold_s: float = 0.0, wait_release: bool = true) -> void:
	assert_true(main.rig.focus_control(control), "looking at %s" % control.name)
	await wait_physics_frames(1)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT if dir == 0 else (MOUSE_BUTTON_WHEEL_UP if dir > 0 else MOUSE_BUTTON_WHEEL_DOWN)
	ev.position = Vector2(SCREEN) * 0.5
	ev.global_position = ev.position
	ev.pressed = true
	viewport.push_input(ev, true)
	main.rig.end_inspection()
	if hold_s > 0.0:
		run(hold_s, false)
	if wait_release:
		await let_go(control)


## Wait until a clicked pushbutton lets go, so the next click presses it
## again.
func let_go(control: ControlBase) -> void:
	for i in 600:
		if control.get("pressed") != true:
			return
		await wait_process_frames(1)


## Click the wrist-menu button [param id] where it shows, opening the menu
## with M first if it is closed.
func click_menu(id: String) -> void:
	if not main.menu.is_shown():
		press(KEY_M)
	await wait_physics_frames(1)
	var b: ControlBase = main.menu.button(id)
	var cam: Camera3D = main.rig.get_node("Camera3D")
	_mouse(cam.unproject_position(b.get_node("Touch").global_position), true)
	assert_true(b.get("pressed"), "%s pressed" % id)
	await let_go(b)


## Slow the clock with the wrist menu's RATE - until the panels unlock
## (100x or slower), as the crew must after a fast coast.
func unlock_panels() -> void:
	for i in 4:
		if not SimClock.controls_locked():
			return
		await click_menu("slower")
	assert_false(SimClock.controls_locked(), "RATE - unlocked the panels")


# --- the checklist ---------------------------------------------------------------

## Open the checklist [param title] on the HUD's checklist choice, or with
## the wrist menu's CHECKLIST.
func open_checklist(title: String) -> void:
	if in_cabin:
		for i in main.card.book.lists.size():
			if main.card.book.list().title == title:
				break
			await click_menu("checklist")
		assert_eq(main.card.book.list().title, title)
		return
	var o := hud._check_title
	for i in o.item_count:
		if o.get_item_text(i) == title:
			o.select(i)
			o.item_selected.emit(i)
	assert_eq(hud.book.list().title, title)


## The step the HUD's checklist, or the card, marks current, without its
## marker, or "" when the checklist is complete.
func current_step() -> String:
	if in_cabin:
		for l in main.card.step_labels:
			if l.visible and l.text.begins_with("▶ "):
				return l.text.trim_prefix("▶ ")
		return ""
	for line in hud._check_text.get_parsed_text().split("\n"):
		if line.begins_with("▶ "):
			return line.trim_prefix("▶ ")
	return ""


## The current step begins [param text], after a frame for the HUD or the
## card to catch up with the Bus.
func expect_step(text: String) -> void:
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), text)


## The open checklist is [param title], and it is complete: the HUD, or the
## card, says so.
func expect_complete(title: String) -> void:
	await wait_process_frames(1)
	var b: ChecklistBook = main.card.book if in_cabin else hud.book
	assert_eq(b.list().title, title)
	assert_true(b.list().done(), "%s: every step done" % title)
	if in_cabin:
		var shown: Array = main.card.step_labels.filter(func(l: Label3D) -> bool: return l.visible).map(
			func(l: Label3D) -> String: return l.text)
		assert_has(shown, "✓ Checklist complete.", "%s: the card says so" % title)
	else:
		assert_string_contains(hud._check_text.get_parsed_text(), "Checklist complete.", "%s: the HUD says so" % title)


# --- the hand controllers --------------------------------------------------------

## Hold [param code] down for [param steps] fixed steps of flight.
func pulse(code: Key, steps: int) -> void:
	await hold_key(code)
	run(steps * SimClock.FIXED_DT, false)
	await release_key(code)


## The ΔV one fixed step of full translation gives the LM along each body
## axis, m/s.
func lm_step_dv() -> Vector3:
	var f := float(SpacecraftData.section("lm_rcs")["jet_thrust_n"])
	return LM_JETS * (f * SimClock.FIXED_DT / rt.dynamics.lm.mass)


## The body axes of the vehicle flown, inertial.
func body_axes() -> Basis:
	var lm: bool = main.vehicles.vehicle == "lm"
	return rt.dynamics.lm.attitude.eci_from_body() if lm else rt.dynamics.attitude.eci_from_body()


## Give the vehicle flown the ΔV [param dv] (m/s, its body axes) on the
## translation controller's keys, axis by axis, each key held for the
## nearest whole number of fixed steps.
func translate(dv: Vector3) -> void:
	var lm: bool = main.vehicles.vehicle == "lm"
	var cap := lm_step_dv() if lm else csm_step_dv()
	for k in 3:
		var n := roundi(absf(dv[k]) / cap[k])
		if n > 0:
			var keys: Array = (LM_TTCA_KEYS if lm else CSM_THC_KEYS)[k]
			await pulse(keys[0] if dv[k] > 0.0 else keys[1], n)


## Turn the vehicle flown, the DAP in rate command, until its +X axis
## points along [param target] (a Callable giving the inertial direction)
## within half a degree: about its Y and Z axes in turn, each key held as
## long as the turn takes at the full-scale rate, or at a tenth of it
## with Shift for the last few degrees. Returns whether it did.
func face(target: Callable) -> bool:
	var lm: bool = main.vehicles.vehicle == "lm"
	var keys: Dictionary = LM_ACA_KEYS if lm else CSM_RHC_KEYS
	for i in 40:
		var b: Vector3 = body_axes().inverse() * (target.call() as Vector3).normalized()
		var angle := Vector3.RIGHT.angle_to(b)
		if angle < deg_to_rad(0.5):
			return true
		# Turning about Y and Z by these swings +X toward the target.
		var turn := Vector3(0.0, -b.z, b.y).normalized() * angle
		for axis in [1, 2]:
			var fine := absf(turn[axis]) < deg_to_rad(4.0)
			var rate := AgcCore.RATE_HOLD * (0.1 if fine else 1.0)
			var steps := roundi(absf(turn[axis]) / rate / SimClock.FIXED_DT)
			if steps == 0:
				continue
			if fine:
				await hold_key(KEY_SHIFT)
			await pulse(keys[axis][0] if turn[axis] > 0.0 else keys[axis][1], steps)
			if fine:
				await release_key(KEY_SHIFT)
			# The DAP stops the turn and holds.
			run(3.0, false)
	return false

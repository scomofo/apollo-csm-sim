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
## The LM's translation jets per body axis (src/systems/lm_rcs.gd).
const LM_JETS := Vector3(4, 2, 2)

var viewport: SubViewport
var main: Node
var hud: Hud


## Start the main scene at [param phase], as --phase= does, with the help
## overlay put away (H).
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
## SimTest.keys(). Typing takes a moment of flight, a fixed step, in which
## the computer puts what the keys did on the Bus.
func type(seq: String) -> void:
	for ch in seq:
		press(DSKY_KEYS[ch] if DSKY_KEYS.has(ch) else (KEY_0 + int(ch)) as Key)
	run(SimClock.FIXED_DT, false)


## The HUD button reading [param text] that shows, or null.
func button(text: String) -> BaseButton:
	for b in hud.find_children("*", "BaseButton", true, false):
		if b.text == text and b.is_visible_in_tree():
			return b
	return null


## Click the HUD button reading [param text] where it shows, [param hold_s]
## seconds of flight passing while it is held down.
func click(text: String, hold_s: float = 0.0) -> void:
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
## picking the position on it does.
func set_switch(channel: String, position: int) -> void:
	var o: OptionButton = hud._options[channel]
	assert_true(o.is_visible_in_tree(), "%s shows on the HUD" % channel)
	o.select(position)
	o.item_selected.emit(position)
	assert_eq(Bus.get_value(channel), position, "%s at %d" % [channel, position])


# --- the checklist ---------------------------------------------------------------

## Open the checklist [param title] on the HUD's checklist choice.
func open_checklist(title: String) -> void:
	var o := hud._check_title
	for i in o.item_count:
		if o.get_item_text(i) == title:
			o.select(i)
			o.item_selected.emit(i)
	assert_eq(hud.book.list().title, title)


## The step the HUD's checklist marks current, without its marker, or ""
## when the checklist is complete.
func current_step() -> String:
	for line in hud._check_text.get_parsed_text().split("\n"):
		if line.begins_with("▶ "):
			return line.trim_prefix("▶ ")
	return ""


## The HUD's current step begins [param text], after a frame for the HUD
## to catch up with the Bus.
func expect_step(text: String) -> void:
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), text)


## The HUD's open checklist is [param title], and it is complete.
func expect_complete(title: String) -> void:
	await wait_process_frames(1)
	assert_eq(hud.book.list().title, title)
	assert_true(hud.book.list().done(), "%s: every step done" % title)
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

## Shared harness for the cabin scenario tests: the CM cabin in its own
## viewport on the headless runtime, with the desktop rig at the
## commander's eye, the checklist book with its card and highlight, the
## wrist menu on the camera, and the hand controllers on the keys.
## Everything is worked the way a player on the desktop works it: the rig
## looks at a panel control and a left click goes through its input
## handling to ControlBase.actuate_far(); a wrist-menu button is clicked
## where it shows on the screen; the keys go through Input (SimTest's
## hold_key()).
class_name CabinTest
extends SimTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")
const CENTRE := Vector2(400, 300)
## The DSKY keys by the letters SimTest.keys() uses.
const KEY_NAMES := {"V": "VERB", "N": "NOUN", "E": "ENTR", "P": "PRO", "C": "CLR", "K": "KEY REL", "R": "RSET"}

var viewport: SubViewport
var cabin: CmCabin
var rig: Node3D
var camera: Camera3D
var dsky: CabinDsky
var book: ChecklistBook
var card: ChecklistCard
var highlight: ChecklistHighlight
var menu: WristMenu
var hands: HandControllerInput


## Build the cabin on the runtime build() made, with the checklist for
## [param phase] open.
func setup_cabin(phase: String = "") -> void:
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
	if phase != "":
		book.select_for_phase(phase)
	card = ChecklistCard.new()
	card.book = book
	cabin.card_mount.add_child(card)
	highlight = ChecklistHighlight.new()
	highlight.cabin = cabin
	highlight.book = book
	cabin.add_child(highlight)
	menu = WristMenu.new()
	menu.cabin = cabin
	menu.setup(rig, camera, null, book)
	hands = HandControllerInput.new()
	add_child_autofree(hands)
	dsky = cabin.items["P2_DSKY"]
	await wait_physics_frames(2)


# --- the desktop's inputs -------------------------------------------------------

## A key typed into the cabin's viewport (M for the wrist menu).
func press(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	viewport.push_input(ev, true)
	await wait_physics_frames(1)


func mouse(at: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = at
	ev.global_position = at
	ev.pressed = true
	viewport.push_input(ev, true)


## Look at a panel control and click it. The open menu turns with the
## camera, and the physics server moves its buttons at the next physics
## step, so the click waits for one, as a hand on a mouse always does.
## [param hold_s] seconds of flight pass while a pushbutton is held down,
## for the controls the sequencer reads on a step: CSM/LV SEP, LM JETT and
## CM/SM SEP. Unless [param wait_release] is false, the click returns once
## a pushbutton has let go again.
func click(control: ControlBase, hold_s: float = 0.0, wait_release: bool = true) -> void:
	assert_true(rig.focus_control(control), "looking at %s" % control.name)
	await wait_physics_frames(1)
	mouse(CENTRE)
	rig.end_inspection()
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


## Click the wrist-menu button [param id] where it shows on the screen,
## opening the menu with M first if it is closed. The camera may just have
## turned back from a panel control, so the click waits a physics step for
## the menu's buttons to follow it.
func click_menu(id: String) -> void:
	if not menu.is_shown():
		await press(KEY_M)
	await wait_physics_frames(1)
	var b := menu.button(id)
	mouse(camera.unproject_position(b.get_node("Touch").global_position))
	assert_true(b.get("pressed"), "%s pressed" % id)
	await let_go(b)


## Click RATE - on the wrist menu until the panel switches unlock (100x or
## slower), as the crew must after a fast coast before working a switch.
func slow_down() -> void:
	for i in 4:
		if not SimClock.controls_locked():
			return
		await click_menu("slower")
	assert_false(SimClock.controls_locked(), "RATE - unlocked the panels")


## The DSKY at the player's station: the lower equipment bay's there, the
## main display console's elsewhere.
func station_dsky() -> CabinDsky:
	return cabin.items["LEB_DSKY"] if cabin.seat == "LEB" else dsky


## Type on the cabin DSKY at the player's station, "V37E30E" style, as
## SimTest.keys(). A key is held for a moment after a click, so typing
## waits for it to let go only when it comes round again.
func type(seq: String) -> void:
	var d := station_dsky()
	for ch in seq:
		var key: ControlBase = d.keys[KEY_NAMES.get(ch, ch)]
		await let_go(key)
		await click(key, 0.0, false)


## SEAT on the wrist menu until the player is at [param seat_name].
func go_to_seat(seat_name: String) -> void:
	for i in cabin.seats().size():
		if cabin.seat == seat_name:
			return
		await click_menu("seat")
	assert_eq(cabin.seat, seat_name, "SEAT to %s" % seat_name)


## Fly the IMU realign checklist at the lower equipment bay: SEAT to the
## bay, OPTICS MODE CMC, P52 with [param option] on its DSKY, each star
## the CMC drives the optics to centred in MANUAL (the crew's hand on the
## optics hand controller: centre_star()) and MARK clicked, N05, N93 and
## the torquing; then P00, back to the commander's couch and to the
## checklist that was open. If the Moon or the Earth fills the optics
## (alarm 00405), the commander rolls heads down (roll_over()).
func realign_at_the_leb(option: int = 1) -> Dictionary:
	var agc := rt.agc()
	var was := book.list().title
	await open_checklist("IMU realign (P52)")
	await go_to_seat("LEB")
	await slow_down()
	if current_step().begins_with("At the LEB"):
		# In MANUAL since the last realign.
		await switch_to("LEB_OPTICS_MODE", 1)
	await expect_step("V37E 52E")
	await type("V37E52E")
	await expect_step("V04N06")
	await type("V22E%dEP" % option)
	if option != 3:
		await expect_step("V06N22")
		await type("P")
		if agc.step_name == "n22" and agc.alarm_code == 401:
			# The new orientation in gimbal lock here: the commander turns.
			await type("R")
			turn_for_new_orientation()
			await type("P")
		assert_true(await fly_until(func() -> bool: return agc.step_name == "acquire", 120.0, 1.0, false), "coarse aligned")
	await expect_step("V50N25 00015")
	await type("P")
	if agc.step_name == "acquire" and agc.alarm_code == 405:
		await type("R")
		roll_over()
		await type("P")
	for i in 2:
		await expect_step("Star %d" % (i + 1))
		await switch_to("LEB_OPTICS_MODE", 1)
		await type("P")
		await fly(2.0, 0.5, false)
		await switch_to("LEB_OPTICS_MODE", 0)
		centre_star(agc.align_stars[i])
		await click(cabin.items["LEB_MARK"], 0.1)
	await expect_step("V06N05")
	var sad := agc.align_sad_deg
	await type("P")
	await expect_step("V06N93")
	var torque := agc.align_torque * (180.0 / PI)
	await type("P")
	await expect_step("V50N25 00014")
	await switch_to("LEB_OPTICS_MODE", 1)
	await type("V37E00E")
	await expect_complete("IMU realign (P52)")
	await go_to_seat("CDR")
	await open_checklist(was)
	return {"sad": sad, "torque": torque, "stars": agc.align_stars.duplicate()}


## Click a switch until it reads [param position]; a guarded switch's
## first click lifts its guard.
func switch_to(id: String, position: int) -> void:
	var c: ControlBase = cabin.items[id]
	for i in 4:
		if c.get("position_index") == position:
			return
		await click(c)
	assert_eq(c.get("position_index"), position, "%s clicked to position %d" % [id, position])


# --- the checklist --------------------------------------------------------------

## The step the card marks current, without its marker, or "" when the
## checklist is complete.
func current_step() -> String:
	for l in card.step_labels:
		if l.visible and l.text.begins_with("▶ "):
			return l.text.trim_prefix("▶ ")
	return ""


## The card's current step begins [param text], after a frame for the card
## to catch up with the Bus.
func expect_step(text: String) -> void:
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), text)


## The open checklist is [param title], and it is complete on the card.
func expect_complete(title: String) -> void:
	await wait_process_frames(1)
	assert_eq(book.list().title, title)
	assert_true(book.list().done(), "%s: every step done" % title)
	var shown := card.step_labels.filter(func(l: Label3D) -> bool: return l.visible).map(func(l: Label3D) -> String: return l.text)
	assert_has(shown, "✓ Checklist complete.", "%s: the card says so" % title)


## Press CHECKLIST until [param title] is open.
func open_checklist(title: String) -> void:
	for i in book.lists.size():
		if book.list().title == title:
			return
		await click_menu("checklist")
	assert_eq(book.list().title, title)

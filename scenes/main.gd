## Entry point of the Apollo CSM simulator. Builds the headless simulation
## runtime exactly as the tests do, then attaches presentation: the 3D space
## view, the CM cabin with the player's rig at the commander's eye, and the
## cockpit HUD. HandControllerInput turns the keys and thumbsticks into
## ctl.rhc / ctl.thc; everything else goes through the HUD, the DSKY or the
## cabin's controls.
##
## On the desktop, C cycles the window, chase and cabin views, and the HUD
## stays as the fallback. With OpenXR running (start with --xr-mode on) the
## XR rig replaces the desktop rig and the cabin is the only view. In the
## cabin, the checklist card and highlight show the open checklist and the
## wrist menu (M on the desktop) requests PADs and sets the clock; the HUD
## shares the same ChecklistBook. The comfort aids, the gaze tooltip, the
## frame-time monitor and the headset acceptance recorder
## (docs/HEADSET_RUN.md) come up on both rigs; the recorder writes its
## record only in a headset. So does the audio director, the cabin's sound
## (docs/LISTENING_PASS.md); a checkpoint's load (F9) makes none.
##
## The player moves to the LM as it undocks (VehicleSwitch), and L changes
## vehicles while it flies free: the HUD, the space view, the hand
## controllers and the DSKY keys follow, and so do the rig, which goes to
## the vehicle's cabin (Eagle's is src/cabin/lm_cabin.gd), and the card,
## the highlight and the wrist menu, which work that vehicle's checklists
## and ask for its PADs. C cycles the LM's window, chase and cabin views;
## in a headset the player stands in Eagle's cabin. Each vehicle has its
## checklists (the HUD shows those of the vehicle flown): at the start both
## open the one for the flight phase (mission.phase), and as the docking
## state moves the player aboard one, the HUD opens its one for the phase
## then.
##
## Writes: player.rig ("xr" or "desktop"), player.xr_session,
##         player.xr_focus, player.xr_refresh_hz
##
## Mission: the exported mission_id, or "--mission=<id>" after "--" on the
## command line, a mission under data/missions/ (apollo_11, apollo_8,
## apollo_10, apollo_12), with its own checklists.
##
## Start phase: the exported start_phase, or "--phase=<name>" after "--" on
## the command line (launch, parking_orbit, translunar_coast, lunar_orbit,
## lunar_descent, lunar_surface, lunar_ascent, tei, transearth_coast,
## entry: the mission's start_phases). The LM's phases start in the LM.
## "--o2-failure-in=<s>" fails the SM's oxygen tank 2 that many seconds
## after the start, as Apollo 13's did: its fuel cells' lights sound the
## master alarm (the listening pass's, docs/LISTENING_PASS.md).
extends Node3D

const CHECKPOINT_PATH := "user://apollo_checkpoint.json"
const SpaceView := preload("res://src/presentation/space_view.gd")
const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")
const XR_RIG := preload("res://scenes/player/xr_rig.tscn")
const VIEW_CABIN := 2

@export var mission_id: String = Mission.DEFAULT_ID
@export var start_phase: String = "parking_orbit"

var rt: SimRuntime
var view: Node3D
## Columbia's cabin, and Eagle's.
var cabin: CmCabin
var lm_cabin: LmCabin
## The desktop rig, or the XR rig in a headset; a child of the PlayerAnchor
## of the cabin of the vehicle flown.
var rig: Node3D
var xr: bool = false
var hud: Hud
## Which vehicle the player flies (player.vehicle).
var vehicles: VehicleSwitch
## Columbia's checklists and which one is open, and Eagle's: the HUD, the
## card, the highlight and the wrist menu share the book of the vehicle
## flown.
var book: ChecklistBook
var lm_book: ChecklistBook
var card: ChecklistCard
var highlight: ChecklistHighlight
var menu: WristMenu
var comfort: Comfort
var tooltip: GazeTooltip
var perf: PerfMonitor
var recorder: VrAcceptanceRecorder
## The cabin's sound, on the desktop and in a headset alike.
var audio: AudioDirector
## The OpenXR interface, found at start. A test can set a stand-in first
## (initialised, with OpenXR's session signals) to run the headset branch
## without a runtime.
var xr_interface: XRInterface
var _looking: bool = false
var _t_held: bool = false
var _mark_held: bool = false
var _reject_held: bool = false


func _ready() -> void:
	var o2_failure_in := -1.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			start_phase = arg.trim_prefix("--phase=")
		elif arg.begins_with("--mission="):
			mission_id = arg.trim_prefix("--mission=")
		elif arg.begins_with("--o2-failure-in="):
			o2_failure_in = float(arg.trim_prefix("--o2-failure-in="))
	if not mission_id in Mission.ids():
		push_error("main: no mission '%s' under %s; flying %s" % [mission_id, Mission.DIR, Mission.DEFAULT_ID])
		mission_id = Mission.DEFAULT_ID
	rt = SimRuntime.build(self, Mission.path_of(mission_id))
	rt.sequencer.start(start_phase)
	if o2_failure_in >= 0.0:
		rt.mission.data["failures"] = rt.mission.section("failures").merged(
			{"o2_tank_2_get_s": SimClock.get_seconds + o2_failure_in}, true)
	view = SpaceView.new()
	view.name = "SpaceView"
	add_child(view)
	cabin = CmCabin.create()
	add_child(cabin)
	cabin.connect_runtime(rt)
	lm_cabin = LmCabin.create()
	lm_cabin.visible = false
	add_child(lm_cabin)
	lm_cabin.connect_runtime(rt)
	_place_rig()
	book = ChecklistBook.load_default(mission_id)
	lm_book = ChecklistBook.load_lm(mission_id)
	card = ChecklistCard.new()
	card.name = "ChecklistCard"
	card.book = book
	cabin.card_mount.add_child(card)
	highlight = ChecklistHighlight.new()
	highlight.name = "ChecklistHighlight"
	highlight.follow(cabin, book)
	var cam: Camera3D = rig.get_node("XRCamera3D") if xr else rig.get_node("Camera3D")
	view.eye_camera = cam
	comfort = Comfort.new()
	comfort.name = "Comfort"
	cam.add_child(comfort)
	tooltip = GazeTooltip.new()
	tooltip.name = "GazeTooltip"
	if not xr:
		tooltip.pointer_camera = cam
		tooltip.reach = CmCabin.CLICK_RANGE
	cam.add_child(tooltip)
	menu = WristMenu.new()
	menu.name = "WristMenu"
	menu.comfort = comfort
	menu.cabin = cabin
	menu.setup(rig, cam, rig.get_node("LeftHand") if xr else null, book)
	perf = PerfMonitor.new()
	perf.name = "PerfMonitor"
	add_child(perf)
	recorder = VrAcceptanceRecorder.new()
	recorder.name = "VrAcceptanceRecorder"
	recorder.rig = rig
	recorder.xr_interface = xr_interface if xr else null
	recorder.write_on_exit = xr
	add_child(recorder)
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(rt, book, lm_book)
	# Both vehicles' checklists open for the phase the flight starts in.
	var phase := str(Bus.get_value("mission.phase", start_phase))
	book.select_for_phase(phase)
	lm_book.select_for_phase(phase)
	# In a headset the thumbsticks fly the hand controllers too.
	var hci := HandControllerInput.for_xr_rig(rig) if xr else HandControllerInput.new()
	hci.name = "HandControllerInput"
	add_child(hci)
	set_view(VIEW_CABIN if xr else 0)
	vehicles = VehicleSwitch.new()
	vehicles.name = "VehicleSwitch"
	vehicles.changed.connect(_on_vehicle)
	vehicles.boarded.connect(_on_boarded)
	add_child(vehicles)
	# Last, so that nothing set up above clicks.
	audio = AudioDirector.new()
	audio.name = "AudioDirector"
	add_child(audio)


## The cabin of vehicle [param v]: Eagle's for "lm", Columbia's otherwise.
func cabin_for(v: String) -> Cabin:
	return lm_cabin if v == "lm" else cabin


## The player moved to [param v]: the HUD and the view follow, and the rig
## goes to the vehicle's cabin, at the seat it was left at, with the card,
## the highlight and the wrist menu, which work the vehicle's checklists
## and ask for its PADs.
func _on_vehicle(v: String) -> void:
	hud.set_vehicle(v)
	view.vehicle = v
	var c := cabin_for(v)
	var b := lm_book if v == "lm" else book
	rig.reparent(c.anchor, false)
	card.reparent(c.card_mount, false)
	card.set_book(b)
	highlight.follow(c, b)
	menu.cabin = c
	menu.book = b
	menu.set_vehicle(v)
	comfort.vehicle = v
	c.set_seat(c.seat)
	set_view(view.view_mode)


## The player went aboard [param _v], whose checklists the HUD now shows:
## the one for the flight phase opens, where it stands.
func _on_boarded(_v: String) -> void:
	hud.select_checklist_for(str(Bus.get_value("mission.phase", start_phase)))


## The DSKY of the computer in the vehicle the player flies.
func _dsky() -> Dsky:
	return rt.lgc().dsky if vehicles.vehicle == "lm" else rt.agc().dsky


func _place_rig() -> void:
	if xr_interface == null:
		xr_interface = XRServer.find_interface("OpenXR")
	xr = xr_interface != null and xr_interface.is_initialized()
	Bus.set_value("player.rig", "xr" if xr else "desktop")
	if xr:
		print("Main: OpenXR initialised, XR rig")
		get_viewport().use_xr = true
		# The runtime paces the headset's frames. V-Sync on the desktop
		# window would hold them to the monitor's refresh (60 Hz on most).
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		xr_interface.session_begun.connect(_on_xr_session_begun)
		xr_interface.session_stopping.connect(_on_xr_session_stopping)
		xr_interface.session_focussed.connect(func() -> void: Bus.set_value("player.xr_focus", true))
		xr_interface.session_visible.connect(func() -> void: Bus.set_value("player.xr_focus", false))
		rig = XR_RIG.instantiate()
	else:
		rig = DESKTOP_RIG.instantiate()
		rig.set("click_range", CmCabin.CLICK_RANGE)
	# Both cameras reach past the Earth and Moon, drawn RENDER_DIST away.
	var cam: Camera3D = rig.get_node("XRCamera3D") if xr else rig.get_node("Camera3D")
	cam.near = 0.05
	cam.far = SpaceView.RENDER_DIST * 3.0
	rig.name = "PlayerRig"
	cabin.anchor.add_child(rig)


## Pace frames to the headset's refresh when the runtime reports it.
func _on_xr_session_begun() -> void:
	var rate: float = xr_interface.get_display_refresh_rate() if xr_interface.has_method("get_display_refresh_rate") else 0.0
	if rate > 0.0:
		Engine.max_fps = int(round(rate))
		perf.frame_budget_ms = 1000.0 / rate
		Bus.set_value("player.xr_refresh_hz", rate)
	Bus.set_value("player.xr_session", true)
	print("Main: OpenXR session begun (%s Hz)" % (str(rate) if rate > 0.0 else "runtime default"))


func _on_xr_session_stopping() -> void:
	Bus.set_value("player.xr_session", false)
	Bus.set_value("player.xr_focus", false)


## 0 window, 1 chase, 2 cabin: the cabin of the vehicle flown. A headset
## has only the cabin.
func set_view(mode: int) -> void:
	if xr:
		mode = VIEW_CABIN
	var in_cabin := mode == VIEW_CABIN
	var lm := vehicles != null and vehicles.vehicle == "lm"
	view.view_mode = mode
	cabin.visible = in_cabin and not lm
	lm_cabin.visible = in_cabin and lm
	hud.set_cabin_view(in_cabin)
	if xr:
		(rig.get_node("XRCamera3D") as Camera3D).make_current()
		return
	# The desktop rig and its wrist menu take the mouse and M only in the
	# cabin.
	rig.set_process_unhandled_input(in_cabin)
	menu.set_process_unhandled_input(in_cabin)
	if in_cabin:
		(rig.get_node("Camera3D") as Camera3D).make_current()
	else:
		rig.call("release_mouse_look")
		view.camera.make_current()


func _process(_delta: float) -> void:
	if SimClock.controls_locked():
		return
	var t := Input.is_key_pressed(KEY_T) and vehicles.vehicle != "lm"
	if t != _t_held:
		_t_held = t
		Bus.set_value("ctl.sps.thrust_on", t)
	# At the optics: X is MARK, Y MARK REJECT, held like the buttons.
	var at_optics := hud.optics_open()
	var mark := Input.is_key_pressed(KEY_X) and at_optics
	if mark != _mark_held:
		_mark_held = mark
		Bus.set_value("ctl.optics.mark", mark)
	var reject := Input.is_key_pressed(KEY_Y) and at_optics
	if reject != _reject_held:
		_reject_held = reject
		Bus.set_value("ctl.optics.mark_reject", reject)


const DSKY_KEYS := {
	KEY_V: "VERB", KEY_N: "NOUN", KEY_ENTER: "ENTR", KEY_KP_ENTER: "ENTR",
	KEY_BACKSPACE: "CLR", KEY_SPACE: "PRO", KEY_INSERT: "KEY REL", KEY_DELETE: "RSET",
	KEY_EQUAL: "+", KEY_KP_ADD: "+", KEY_MINUS: "-", KEY_KP_SUBTRACT: "-",
}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_looking = event.pressed and view.view_mode != VIEW_CABIN
	elif event is InputEventMouseMotion and _looking:
		view.look(event.relative.x * 0.004, event.relative.y * 0.004)
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var kc: Key = event.keycode
	if DSKY_KEYS.has(kc):
		_dsky().press(DSKY_KEYS[kc])
	elif kc >= KEY_0 and kc <= KEY_9:
		_dsky().press(str(kc - KEY_0))
	elif kc >= KEY_KP_0 and kc <= KEY_KP_9:
		_dsky().press(str(kc - KEY_KP_0))
	else:
		match kc:
			KEY_BRACKETLEFT: SimClock.slower()
			KEY_BRACKETRIGHT: SimClock.faster()
			KEY_P: SimClock.paused = not SimClock.paused
			KEY_C: set_view((view.view_mode + 1) % 3)
			KEY_L: vehicles.toggle()
			KEY_H: hud.toggle_help()
			KEY_O: hud.toggle_optics()
			KEY_F5:
				var err := rt.save_file(CHECKPOINT_PATH)
				print("checkpoint saved" if err == OK else "checkpoint save failed: %s" % err)
			KEY_F9:
				var msg: String = audio.hush(rt.load_file.bind(CHECKPOINT_PATH))
				print("checkpoint loaded" if msg == "" else msg)

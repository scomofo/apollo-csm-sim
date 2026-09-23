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
## record only in a headset.
##
## On the desktop the player moves to the LM as it undocks (VehicleSwitch),
## and L changes vehicles while it flies free: the HUD, the space view, the
## hand controllers and the DSKY keys follow, and C cycles the LM's window
## and chase views. In a headset the player stays in the CM's cabin
## [simplified: the LM has no cabin yet].
##
## Writes: player.rig ("xr" or "desktop"), player.xr_session,
##         player.xr_focus, player.xr_refresh_hz
##
## Start phase: the exported start_phase, or "--phase=<name>" after "--" on
## the command line (parking_orbit, translunar_coast, lunar_orbit,
## lunar_descent, lunar_surface, lunar_ascent, transearth_coast, entry). The
## LM's phases start in the LM.
extends Node3D

const CHECKPOINT_PATH := "user://apollo_checkpoint.json"
const SpaceView := preload("res://src/presentation/space_view.gd")
const DESKTOP_RIG := preload("res://scenes/player/desktop_rig.tscn")
const XR_RIG := preload("res://scenes/player/xr_rig.tscn")
const VIEW_CABIN := 2

@export var start_phase: String = "parking_orbit"

var rt: SimRuntime
var view: Node3D
var cabin: CmCabin
## The desktop rig, or the XR rig in a headset; a child of the cabin's
## PlayerAnchor.
var rig: Node3D
var xr: bool = false
var hud: Hud
## Which vehicle the player flies (player.vehicle).
var vehicles: VehicleSwitch
## The checklists and which one is open: the HUD, the card, the highlight
## and the wrist menu share it.
var book: ChecklistBook
var card: ChecklistCard
var highlight: ChecklistHighlight
var menu: WristMenu
var comfort: Comfort
var tooltip: GazeTooltip
var perf: PerfMonitor
var recorder: VrAcceptanceRecorder
## The OpenXR interface, found at start. A test can set a stand-in first
## (initialised, with OpenXR's session signals) to run the headset branch
## without a runtime.
var xr_interface: XRInterface
var _looking: bool = false
var _t_held: bool = false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phase="):
			start_phase = arg.trim_prefix("--phase=")
	rt = SimRuntime.build(self)
	rt.sequencer.start(start_phase)
	view = SpaceView.new()
	view.name = "SpaceView"
	add_child(view)
	cabin = CmCabin.create()
	add_child(cabin)
	cabin.connect_runtime(rt)
	_place_rig()
	book = ChecklistBook.load_default()
	card = ChecklistCard.new()
	card.name = "ChecklistCard"
	card.book = book
	cabin.card_mount.add_child(card)
	highlight = ChecklistHighlight.new()
	highlight.name = "ChecklistHighlight"
	highlight.cabin = cabin
	highlight.book = book
	cabin.add_child(highlight)
	var cam: Camera3D = rig.get_node("XRCamera3D") if xr else rig.get_node("Camera3D")
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
	hud.setup(rt, book)
	hud.select_checklist_for(start_phase)
	# In a headset the thumbsticks fly the hand controllers too.
	var hci := HandControllerInput.for_xr_rig(rig) if xr else HandControllerInput.new()
	hci.name = "HandControllerInput"
	add_child(hci)
	set_view(VIEW_CABIN if xr else 0)
	vehicles = VehicleSwitch.new()
	vehicles.name = "VehicleSwitch"
	vehicles.csm_only = xr
	vehicles.changed.connect(_on_vehicle)
	add_child(vehicles)


## The player moved to [param v]: the HUD and the view follow. The LM has
## window and chase views, and no cabin.
func _on_vehicle(v: String) -> void:
	hud.set_vehicle(v)
	view.vehicle = v
	if v == "lm" and view.view_mode == VIEW_CABIN:
		set_view(0)


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


## 0 window, 1 chase, 2 cabin. A headset has only the cabin.
func set_view(mode: int) -> void:
	if xr:
		mode = VIEW_CABIN
	var in_cabin := mode == VIEW_CABIN
	view.view_mode = mode
	cabin.visible = in_cabin
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
			KEY_C: set_view((view.view_mode + 1) % (2 if vehicles.vehicle == "lm" else 3))
			KEY_L: vehicles.toggle()
			KEY_H: hud.toggle_help()
			KEY_F5:
				var err := rt.save_file(CHECKPOINT_PATH)
				print("checkpoint saved" if err == OK else "checkpoint save failed: %s" % err)
			KEY_F9:
				var msg := rt.load_file(CHECKPOINT_PATH)
				print("checkpoint loaded" if msg == "" else msg)

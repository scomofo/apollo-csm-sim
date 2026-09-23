## Entry point of the Apollo CSM simulator. Builds the headless simulation
## runtime exactly as the tests do, then attaches presentation: the 3D space
## view, the CM cabin with the player's rig at the commander's eye, and the
## cockpit HUD. HandControllerInput turns the keys and thumbsticks into
## ctl.rhc / ctl.thc; everything else goes through the HUD, the DSKY or the
## cabin's controls.
##
## On the desktop, C cycles the window, chase and cabin views, and the HUD
## stays as the fallback. With OpenXR running (start with --xr-mode on) the
## XR rig replaces the desktop rig and the cabin is the only view.
##
## Start phase: the exported start_phase, or "--phase=<name>" after "--" on
## the command line (parking_orbit, translunar_coast, lunar_orbit,
## transearth_coast, entry).
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
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(rt)
	hud.select_checklist_for(start_phase)
	var hci := HandControllerInput.new()
	hci.name = "HandControllerInput"
	add_child(hci)
	set_view(VIEW_CABIN if xr else 0)


func _place_rig() -> void:
	var openxr := XRServer.find_interface("OpenXR")
	xr = openxr != null and openxr.is_initialized()
	if xr:
		get_viewport().use_xr = true
		rig = XR_RIG.instantiate()
	else:
		rig = DESKTOP_RIG.instantiate()
		rig.set("click_range", CmCabin.CLICK_RANGE)
		var cam: Camera3D = rig.get_node("Camera3D")
		cam.near = 0.05
		cam.far = SpaceView.RENDER_DIST * 3.0
	rig.name = "PlayerRig"
	cabin.anchor.add_child(rig)


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
	# The desktop rig takes the mouse only in the cabin.
	rig.set_process_unhandled_input(in_cabin)
	if in_cabin:
		(rig.get_node("Camera3D") as Camera3D).make_current()
	else:
		rig.call("release_mouse_look")
		view.camera.make_current()


func _process(_delta: float) -> void:
	if SimClock.controls_locked():
		return
	var t := Input.is_key_pressed(KEY_T)
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
		rt.agc().dsky.press(DSKY_KEYS[kc])
	elif kc >= KEY_0 and kc <= KEY_9:
		rt.agc().dsky.press(str(kc - KEY_0))
	elif kc >= KEY_KP_0 and kc <= KEY_KP_9:
		rt.agc().dsky.press(str(kc - KEY_KP_0))
	else:
		match kc:
			KEY_BRACKETLEFT: SimClock.slower()
			KEY_BRACKETRIGHT: SimClock.faster()
			KEY_P: SimClock.paused = not SimClock.paused
			KEY_C: set_view((view.view_mode + 1) % 3)
			KEY_H: hud.toggle_help()
			KEY_F5:
				var err := rt.save_file(CHECKPOINT_PATH)
				print("checkpoint saved" if err == OK else "checkpoint save failed: %s" % err)
			KEY_F9:
				var msg := rt.load_file(CHECKPOINT_PATH)
				print("checkpoint loaded" if msg == "" else msg)

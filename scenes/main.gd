## Entry point of the Apollo CSM simulator (desktop). Builds the headless
## simulation runtime exactly as the tests do, then attaches presentation:
## the 3D space view and the cockpit HUD. HandControllerInput turns the keys
## into ctl.rhc / ctl.thc; everything else goes through the HUD or the DSKY.
##
## Start phase: the exported start_phase, or "--phase=<name>" after "--" on
## the command line (parking_orbit, translunar_coast, lunar_orbit,
## transearth_coast, entry).
extends Node3D

const CHECKPOINT_PATH := "user://apollo_checkpoint.json"
const SpaceView := preload("res://src/presentation/space_view.gd")

@export var start_phase: String = "parking_orbit"

var rt: SimRuntime
var view: Node3D
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
	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)
	hud.setup(rt)
	hud.select_checklist_for(start_phase)
	var hci := HandControllerInput.new()
	hci.name = "HandControllerInput"
	add_child(hci)


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
		_looking = event.pressed
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
			KEY_C: view.toggle_view()
			KEY_H: hud.toggle_help()
			KEY_F5:
				var err := rt.save_file(CHECKPOINT_PATH)
				print("checkpoint saved" if err == OK else "checkpoint save failed: %s" % err)
			KEY_F9:
				var msg := rt.load_file(CHECKPOINT_PATH)
				print("checkpoint loaded" if msg == "" else msg)

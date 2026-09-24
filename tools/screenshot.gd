## Renders the simulator and saves a PNG (the README images in docs/images/).
##   godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --out=res://docs/images/x.png
## --view: 0 window, 1 chase, 2 cabin. --yaw/--pitch (rad) turn the window
## view's look, the chase camera or, in the cabin, the desktop rig's head.
## --hud=0 leaves the HUD out. --menu=1 shows the wrist menu, and
## --pad=<kind> (mcc, loi, circ, tei) asks Mission Control for a PAD first.
## --undock=<s> undocks the LM and lets it drift for that many seconds.
## --vehicle=csm or lm: the vehicle seen from while the LM flies free (the
## player moves to the LM as it undocks, and its start phases start in it).
extends Node

var _frames := 0
var _out := "user://screenshot.png"
var _main: Node


func _ready() -> void:
	var phase := "parking_orbit"
	var view_mode := 0
	var yaw := 0.0
	var pitch := 0.0
	var hud := true
	var show_menu := false
	var pad := ""
	var undock := 0.0
	var vehicle := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--phase="):
			phase = a.trim_prefix("--phase=")
		elif a.begins_with("--view="):
			view_mode = int(a.trim_prefix("--view="))
		elif a.begins_with("--out="):
			_out = a.trim_prefix("--out=")
		elif a.begins_with("--yaw="):
			yaw = float(a.trim_prefix("--yaw="))
		elif a.begins_with("--pitch="):
			pitch = float(a.trim_prefix("--pitch="))
		elif a == "--hud=0":
			hud = false
		elif a == "--menu=1":
			show_menu = true
		elif a.begins_with("--pad="):
			pad = a.trim_prefix("--pad=")
		elif a.begins_with("--undock="):
			undock = float(a.trim_prefix("--undock="))
		elif a.begins_with("--vehicle="):
			vehicle = a.trim_prefix("--vehicle=")
	SimClock.manual = true
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_phase = phase
	add_child(_main)
	_main.set_view(view_mode)
	if view_mode == 2:
		(_main.rig.get_node("Camera3D") as Camera3D).rotation = Vector3(pitch, yaw, 0.0)
	elif view_mode == 1:
		_main.view.chase_yaw = yaw if yaw != 0.0 else 0.6
		_main.view.chase_pitch = pitch if pitch != 0.0 else 0.25
	else:
		_main.view.look_yaw = yaw
		_main.view.look_pitch = pitch
	_main.hud.toggle_help()
	_main.hud.visible = hud
	if show_menu:
		_main.menu.call("_set_shown", true)
	if pad != "":
		Bus.set_value("ctl.ground.pad_request", pad)
	if undock > 0.0:
		Bus.set_value("ctl.seq.undock", true)
		SimClock.advance(SimClock.FIXED_DT)
		Bus.set_value("ctl.seq.undock", false)
		SimClock.advance(undock)
	_main.vehicles.update()
	if vehicle != "" and _main.vehicles.vehicle != vehicle:
		_main.vehicles.toggle()
	var computer: AgcCore = _main.rt.lgc() if _main.vehicles.vehicle == "lm" else _main.rt.agc()
	for k in ["VERB", "1", "6", "NOUN", "6", "2", "ENTR"]:
		computer.dsky.press(k)
	SimClock.advance(1.0)


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 30:
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("saved ", path)
		get_tree().quit()

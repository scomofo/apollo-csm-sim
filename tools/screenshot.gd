## Renders the simulator and saves a PNG (the README images in docs/images/).
##   godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --out=res://docs/images/x.png
## --view: 0 window, 1 chase, 2 cabin. --yaw/--pitch (rad) turn the window
## view's look, the chase camera or, in the cabin, the desktop rig's head.
## --zoom=<factor> magnifies the desktop cabin camera for detail captures.
## --guide=1 includes the cockpit walkthrough (normally hidden in captures).
## --hud=0 leaves the HUD out. --menu=1 shows the wrist menu, and
## --pad=<kind> (mcc, loi, circ, tei) asks Mission Control for a PAD first.
## --undock=<s> undocks the LM and lets it drift for that many seconds.
## --vehicle=csm or lm: the vehicle seen from while the LM flies free (the
## player moves to the LM as it undocks, and its start phases start in it).
## --optics=<code> opens the optics on navigation star <code> (octal, as
## the DSKY shows it), or on the CMC's first P52 star with 0. --seat=<name>
## moves the cabin view to that seat (CDR, CMP, LEB). --p52=<hours> coasts
## that long in CMC MODE FREE, then starts P52 option 3 and shows the
## optics as the CMC drives them to its first star. --p23=<code> starts
## P23 on navigation star <code> (octal; 0 for the first 15° to 50° from
## the Earth's horizon), flies the auto maneuver and shows the optics with
## the star laid on the Earth's horizon. --coast=<s> flies on that many
## seconds before the shot (from the launch phase's pad, into the ascent).
extends Node

var _frames := 0
var _out := "user://screenshot.png"
var _main: Node


func _ready() -> void:
	var phase := "parking_orbit"
	var view_mode := 0
	var yaw := 0.0
	var pitch := 0.0
	var zoom := 1.0
	var walkthrough := false
	var hud := true
	var show_menu := false
	var pad := ""
	var undock := 0.0
	var vehicle := ""
	var optics := -1
	var seat := ""
	var p52_hours := 0.0
	var p23 := -1
	var coast := 0.0
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
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
		elif a == "--guide=1":
			walkthrough = true
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
		elif a.begins_with("--optics="):
			optics = int(a.trim_prefix("--optics="))
		elif a.begins_with("--seat="):
			seat = a.trim_prefix("--seat=")
		elif a.begins_with("--p52="):
			p52_hours = float(a.trim_prefix("--p52="))
		elif a.begins_with("--p23="):
			p23 = int(a.trim_prefix("--p23="))
		elif a.begins_with("--coast="):
			coast = float(a.trim_prefix("--coast="))
	SimClock.manual = true
	_main = load("res://scenes/main.tscn").instantiate()
	_main.start_phase = phase
	add_child(_main)
	_main.set_view(view_mode)
	_main.guide.set_capture_visible(walkthrough)
	if walkthrough:
		_main.guide.tour()
	if seat != "":
		_main.cabin.set_seat(seat)
	if view_mode == 2:
		(_main.rig.get_node("Camera3D") as Camera3D).rotation = Vector3(pitch, yaw, 0.0)
		_main.rig.set_zoom_factor(zoom)
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
	if coast > 0.0:
		SimClock.advance(coast)
	_main.vehicles.update()
	if vehicle != "" and _main.vehicles.vehicle != vehicle:
		_main.vehicles.toggle()
	var computer: AgcCore = _main.rt.lgc() if _main.vehicles.vehicle == "lm" else _main.rt.agc()
	for k in ["VERB", "1", "6", "NOUN", "6", "2", "ENTR"]:
		computer.dsky.press(k)
	SimClock.advance(1.0)
	if p52_hours > 0.0:
		Bus.set_value("ctl.cmc.mode", 0)
		SimClock.rate = 1000.0
		SimClock.advance(p52_hours * 3600.0)
		SimClock.rate = 1.0
		Bus.set_value("ctl.cmc.mode", 1)
		for k in ["VERB", "3", "7", "ENTR", "5", "2", "ENTR", "VERB", "2", "2", "ENTR", "3", "ENTR", "PRO", "PRO", "PRO"]:
			computer.dsky.press(k)
		SimClock.advance(8.0)
		_main.hud.toggle_optics(true)
	if p23 >= 0:
		_p23(computer as Agc, p23)
	if optics >= 0:
		_main.hud.toggle_optics(true)
		var agc: Agc = _main.rt.agc()
		if optics == 0 and agc._select_stars():
			optics = agc.align_stars[0]
		if Stars.has(optics):
			Bus.set_value("ctl.optics.mode", 0)
			var dir := Basis(Bus.get_value("dyn.att_q") as Quaternion).inverse() * Stars.direction(optics)
			(_main.rt.systems["optics"] as Optics).aim(dir)


## P23 on star [param code] (0: the first 15 to 50 deg from the Earth's
## horizon) as the crew runs it: the codes, PRO, and in CMC MODE AUTO PRO
## for the maneuver; at V51 the star laid on the horizon in MANUAL.
func _p23(agc: Agc, code: int) -> void:
	var tr: Trajectory = _main.rt.dynamics.traj
	if code == 0:
		for c in Stars.codes():
			var m := NavFilter.star_horizon(tr, Stars.direction(c), "earth")
			if not m.is_empty() and rad_to_deg(float(m["q"])) > 15.0 and rad_to_deg(float(m["q"])) < 50.0:
				code = c
				break
	Bus.set_value("ctl.cmc.mode", 2)
	var seq := ["VERB", "3", "7", "ENTR", "2", "3", "ENTR", "VERB", "2", "1", "ENTR"]
	for d in "%d" % code:
		seq.append(d)
	seq.append_array(["ENTR", "PRO", "PRO"])
	for k in seq:
		agc.dsky.press(k)
	var t := 0.0
	while agc.step_name != "mark" and t < 900.0:
		SimClock.advance(1.0)
		t += 1.0
	SimClock.advance(10.0)
	Bus.set_value("ctl.optics.mode", 0)
	var sight := NavFilter.star_horizon(_main.rt.dynamics.traj, Stars.direction(code), "earth")
	var o: Optics = _main.rt.systems["optics"]
	o.trunnion_deg = rad_to_deg(float(sight["q"]))
	SimClock.advance(SimClock.FIXED_DT)
	_main.hud.toggle_optics(true)
	print("P23 on star %d (%s), %.3f deg from the horizon" % [code, Stars.name_of(code), o.trunnion_deg])


func _process(_d: float) -> void:
	_frames += 1
	if _frames == 30:
		# An occluded desktop window may skip drawing; capture a rendered frame.
		RenderingServer.force_draw()
		var img := get_viewport().get_texture().get_image()
		var path := ProjectSettings.globalize_path(_out)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		img.save_png(path)
		print("saved ", path)
		get_tree().quit()

## Slice 2c's check (docs/ROADMAP.md): a midcourse correction PAD flown with
## P30 and P41 (P40 if it is 10 ft/s or more) using only the cabin's
## controls, each one clicked through the desktop rig from the commander's
## couch: the rig looks at the control, and a left click goes through its
## input handling to ControlBase.actuate_far(). Mission Control's uplink and
## the time rate come from outside the cabin, as they do in the 2D HUD.
extends SimTest

const RIG := preload("res://scenes/player/desktop_rig.tscn")
const CENTRE := Vector2(400, 300)

var viewport: SubViewport
var cabin: CmCabin
var rig: Node3D
var dsky: CabinDsky


func _setup_cabin() -> void:
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
	(rig.get_node("Camera3D") as Camera3D).current = true
	dsky = cabin.items["P2_DSKY"]
	await wait_physics_frames(2)


## Look at [param control] and left-click it. A pushbutton is held for its
## far_hold_s; wait until it lets go, so the next click presses it again.
func _click(control: ControlBase) -> void:
	assert_true(rig.focus_control(control), "looking at %s" % control.name)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = CENTRE
	ev.global_position = CENTRE
	ev.pressed = true
	viewport.push_input(ev, true)
	rig.end_inspection()
	for i in 600:
		if control.get("pressed") != true:
			break
		await wait_process_frames(1)


## Type on the cabin DSKY: "V37E30E" style, as SimTest.keys().
func _keys(seq: String) -> void:
	var names := {"V": "VERB", "N": "NOUN", "E": "ENTR", "P": "PRO", "C": "CLR", "K": "KEY REL", "R": "RSET"}
	for ch in seq:
		await _click(dsky.keys[names.get(ch, ch)])


## Click a switch until it reads [param position]; a guarded switch's first
## click lifts its guard.
func _switch_to(id: String, position: int) -> void:
	var c: ControlBase = cabin.items[id]
	for i in 4:
		if c.get("position_index") == position:
			return
		await _click(c)
	assert_eq(c.get("position_index"), position, "%s clicked to position %d" % [id, position])


func test_mcc_pad_flown_from_the_cabin() -> void:
	build("translunar_coast")
	await _setup_cabin()
	var agc := rt.agc()
	# The coast starts on target, so no MCC would be needed: give TLI a
	# cutoff error of 0.8 m/s short, which misses the pericynthion target by
	# more than the RTCC's 20 km tolerance.
	var tr := rt.dynamics.traj
	tr.set_state(tr.primary, tr.t, tr.pos(), tr.vel() - tr.vel().normalized() * 0.8)
	rt.dynamics.publish_state()
	# Mission Control uplinks the PAD, as the HUD's MCC button asks it to.
	Bus.set_value("ctl.ground.pad_request", "mcc")
	var pad: Dictionary = rt.sequencer.last_pad
	assert_false(pad.is_empty(), "an MCC solution")
	gut.p("MCC " + Rtcc.pad_text(pad))
	await _switch_to("P1_CMC_MODE", 2)
	assert_eq(Bus.get_value("ctl.cmc.mode"), 2, "CMC MODE AUTO")
	await _keys("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	assert_eq([dsky.fields["prog"].text, dsky.fields["verb"].text, dsky.fields["noun"].text], ["30", "06", "33"],
		"the cabin DSKY asks for TIG")
	await _keys("PPP")
	assert_true(agc.maneuver_valid, "TIG, ΔV and the apsides accepted; maneuver stored")
	var prog := 41 if agc.dv_lvlh_load.length() < 10.0 * Units.FT else 40
	gut.p("flying it with P%d" % prog)
	await _keys("V37E%dE" % prog)
	assert_eq(agc.program, prog, "P%d selected" % prog)
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["50", "18"], "asks to maneuver to the burn attitude")
	await _keys("P")
	await _switch_to("P1_DV_THRUST_A", 1)
	await _switch_to("P1_DV_THRUST_B", 1)
	assert_true(Bus.get_value("ctl.sps.arm_a") == true and Bus.get_value("ctl.sps.arm_b") == true, "ΔV THRUST A and B NORMAL")
	var tig := agc.maneuver_tig
	var ok := run_until(func() -> bool: return agc.step_name == "v99", tig - SimClock.get_seconds + 10.0, 30.0)
	assert_true(ok, "reached V99 before TIG")
	assert_true(SimClock.controls_locked(), "still at 1000x")
	await _click(cabin.items["P1_DV_THRUST_A"])
	assert_eq(Bus.get_value("ctl.sps.arm_a"), true, "switches don't move while time runs fast")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["99", "40"], "asks for engine-on enable")
	await _keys("P")
	ok = run_until(func() -> bool: return agc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	assert_eq(dsky.fields["noun"].text, "85", "residuals")
	var dv := agc.dv_accum
	await _keys("P")
	await _switch_to("P1_DV_THRUST_A", 0)
	await _switch_to("P1_DV_THRUST_B", 0)
	await _switch_to("P1_CMC_MODE", 1)
	assert_almost_eq(dv, float(pad["dv"]), 0.5, "MCC ΔV flown")
	assert_eq(agc.program, 0, "back in P00")
	assert_eq([Bus.get_value("ctl.sps.arm_a"), Bus.get_value("ctl.sps.arm_b"), Bus.get_value("ctl.cmc.mode")], [false, false, 1],
		"SPS safed, CMC MODE HOLD")

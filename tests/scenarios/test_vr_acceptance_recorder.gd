## The headset-run evidence recorder (docs/VR_ACCEPTANCE.md) runs on the
## desktop rig too, so its record and objective rows are checked here
## without hardware. The desktop rig reads as S1 FAIL, and a pointer click
## is not a touch. Fingertip crossings on CMC MODE, the DSKY and the wrist
## menu are. The thumbsticks' pitch and roll response is measured, the
## lock above 100x holds, and the tables are written.
## Adapted from gemini-capsule's tests/scenarios/test_vr_acceptance_recorder.gd
## at 40e449c.
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const OUT := "user://vr_acceptance_test"

var _main: Node
var _rec: VrAcceptanceRecorder


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	_main = MAIN.instantiate()
	_main.start_phase = "lunar_orbit"
	add_child_autofree(_main)
	_main.set_view(2)
	_rec = _main.recorder
	_rec.out_dir = OUT
	await get_tree().process_frame


func after_each() -> void:
	var dir := DirAccess.open(OUT)
	if dir:
		for f in dir.get_files():
			dir.remove(f)


## A fingertip crossing [param control] with [param v_local] (the control's
## axes), then leaving it.
func _touch(control: ControlBase, v_local: Vector3) -> void:
	var finger := Interactor.new()
	finger.set_physics_process(false)
	_main.add_child(finger)
	finger.velocity = control.global_basis * v_local
	control._on_area_entered(finger)
	control._on_area_exited(finger)
	finger.free()


func test_the_desktop_rig_reads_as_s1_fail_and_a_click_is_not_a_touch() -> void:
	assert_eq(_rec.record["rig"], "desktop")
	assert_eq(int(_rec.record["reference_space"]), VrAcceptanceRecorder.LOCAL_SPACE, "the seated Local space")
	assert_false(_rec.write_on_exit, "a desktop session writes no record")
	var mode: ControlBase = _main.cabin.items["P1_CMC_MODE"]
	mode.actuate_far(1)
	assert_eq(Bus.get_value("ctl.cmc.mode"), 2, "the click worked")
	assert_lt(float(_rec.record["switch_by_touch"]["at_s"]), 0.0, "but it was no touch")
	var md := _rec.markdown()
	assert_string_contains(md, "| S1 | OpenXR runtime detected; `--xr-mode on` starts the XR rig in the cabin | | evidence: FAIL (`player.rig` = desktop) |")
	assert_string_contains(md, "no panel switch touched")


func test_fingertip_crossings_on_a_switch_the_dsky_and_the_menu_count_as_touch() -> void:
	var mode: ControlBase = _main.cabin.items["P1_CMC_MODE"]
	_touch(mode, Vector3(0.0, 0.5, 0.0))
	assert_eq(Bus.get_value("ctl.cmc.mode"), 2, "pushed up from HOLD to AUTO")
	assert_eq(_rec.record["switch_by_touch"]["channel"], "ctl.cmc.mode")
	assert_eq(_rec.record["switch_by_touch"]["label"], "CMC MODE")
	var dsky: CabinDsky = _main.cabin.items["P2_DSKY"]
	for k in ["VERB", "1", "6", "NOUN", "2", "0", "ENTR"]:
		_touch(dsky.keys[k], Vector3(0.0, 0.0, -0.5))
	var typed: Dictionary = _rec.record["dsky_by_touch"]
	assert_eq([typed["typed"], typed["verb"], typed["noun"]], ["V16N20E", "16", "20"])
	await get_tree().process_frame
	assert_true(typed["shown"], "the CMC shows V16N20")
	_main.menu.call("_set_shown", true)
	_touch(_main.menu.button("next"), Vector3(0.0, 0.0, -0.5))
	assert_eq(_rec.record["menu_by_touch"]["label"], "NEXT STEP")
	assert_eq(int(_rec.record["touch"]["count"]), 9)
	var md := _rec.markdown()
	for row in ["| A1 |", "| A2 |", "| A7 |"]:
		var line: String = Array(md.split("\n")).filter(func(l: String) -> bool: return l.begins_with(row))[0]
		assert_string_contains(line, "evidence: pass", row)


func test_thumbstick_response_and_the_time_rate_lock_are_measured() -> void:
	var hci: Node = _main.get_node("HandControllerInput")
	hci.set_process(false)
	for rhc in [Vector3(0.0, 0.8, 0.0), Vector3(0.8, 0.0, 0.0)]:
		Bus.set_value("ctl.rhc", rhc)
		for i in 3:
			SimClock.advance(1.0)
			await get_tree().process_frame
		Bus.set_value("ctl.rhc", Vector3.ZERO)
	var s: Dictionary = _rec.record["sticks"]
	assert_almost_eq(float(s["max_pitch"]), 0.8, 1e-6)
	assert_gt(float(s["max_pitch_rate_deg_s"]), 0.5, "CMC MODE HOLD: the pitch rate followed the stick")
	assert_gt(float(s["max_roll_rate_deg_s"]), 0.5, "and the roll rate")
	assert_eq(int(_rec.record["origin_moves_outside_recenter"]), 0)
	hci.set_process(true)
	for i in 3:
		SimClock.faster()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(s["locked_seen"])
	assert_eq(float(s["max_while_locked"]), 0.0, "the hand controllers are locked above 100x")


func test_the_record_is_written_as_json_and_tables() -> void:
	Bus.set_value("present.menu.visible", true)
	assert_true(_rec.record["menu_opened"])
	assert_eq(_rec.record["comfort"]["horizon_at_start"], false, "the horizon aid starts off")
	var base := _rec.write()
	assert_true(FileAccess.file_exists(base + ".json"))
	assert_true(FileAccess.file_exists(base + ".md"))
	var d = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	assert_eq(d["rig"], "desktop")
	assert_gt(int(d["frames"]["count"]), 0)
	var md := FileAccess.get_file_as_string(base + ".md")
	for heading in ["## Session", "## Reach and cabin", "## Actuation", "## Comfort and pacing"]:
		assert_string_contains(md, heading)
	for row in ["S1", "S2", "S3", "S4", "S5", "S6", "R1", "R2", "R3", "R4", "A1", "A2", "A3", "A4", "A5", "A6", "A7",
			"C1", "C2", "C3", "C4", "C5"]:
		assert_string_contains(md, "| %s |" % row)
	Bus.set_value("player.seat", "CMP")
	assert_eq(_rec.write(), base, "a later write rewrites the same record")
	assert_eq(DirAccess.get_files_at(OUT).size(), 2)
	d = JSON.parse_string(FileAccess.get_file_as_string(base + ".json"))
	assert_has(d["seats"], "CMP", "with what happened since")

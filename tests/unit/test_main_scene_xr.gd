## The main scene's headset branch (docs/HEADSET_RUN.md), without a
## headset. A stand-in for Godot's OpenXR interface, initialised and with
## its session signals, puts the XR rig at the commander's eye: the comfort
## aids and the gaze tooltip on its camera, the wrist menu on the left hand,
## the thumbsticks on the hand controllers and the cabin as the only view.
## The session signals pace frames to the headset, and the recorder keeps
## one record of a session the runtime stops and restarts.
extends GutTest

const MAIN := preload("res://scenes/main.tscn")
const SpaceView := preload("res://src/presentation/space_view.gd")
const OUT := "user://vr_acceptance_xr_test"


## Stands in for OpenXRInterface: initialised from the start, with its
## session signals and the refresh rate the runtime reports.
class FakeOpenXr extends XRInterfaceExtension:
	signal session_begun
	signal session_stopping
	signal session_focussed
	signal session_visible

	func _get_name() -> StringName:
		return &"FakeOpenXR"

	func _is_initialized() -> bool:
		return true

	func get_display_refresh_rate() -> float:
		return 72.0


var _main: Node
var _xr: FakeOpenXr
var _vsync: DisplayServer.VSyncMode
var _max_fps: int


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	_vsync = DisplayServer.window_get_vsync_mode()
	_max_fps = Engine.max_fps
	_xr = FakeOpenXr.new()
	_main = MAIN.instantiate()
	_main.start_phase = "lunar_orbit"
	_main.xr_interface = _xr
	add_child_autofree(_main)
	_main.recorder.out_dir = OUT
	await get_tree().process_frame


func after_each() -> void:
	# The headset branch sets these for the whole application, and every
	# other test runs on the desktop.
	get_viewport().use_xr = false
	DisplayServer.window_set_vsync_mode(_vsync)
	Engine.max_fps = _max_fps
	var dir := DirAccess.open(OUT)
	if dir:
		for f in dir.get_files():
			dir.remove(f)


func test_the_headset_branch_puts_the_xr_rig_at_the_commanders_eye() -> void:
	assert_true(_main.xr)
	assert_eq(Bus.get_value("player.rig"), "xr")
	assert_true(get_viewport().use_xr, "the viewport renders to the headset")
	var rig: Node3D = _main.rig
	assert_true(rig is XROrigin3D, "the XR rig")
	assert_eq(rig.get_parent(), _main.cabin.anchor, "at the commander's eye")
	var cam: Camera3D = rig.get_node("XRCamera3D")
	assert_true(cam.current)
	assert_eq(cam.far, SpaceView.RENDER_DIST * 3.0, "it sees past the Earth and Moon")
	assert_eq(_main.comfort.get_parent(), cam, "the comfort aids ride the headset")
	assert_eq(_main.tooltip.get_parent(), cam)
	assert_null(_main.tooltip.pointer_camera, "the gaze is the head's")
	var left: Node3D = rig.get_node("LeftHand")
	assert_eq(_main.menu.hand, left, "the wrist menu is on the left hand")
	assert_false(_main.menu.is_shown())
	for tip in [left.get_node("Fingertip"), rig.get_node("RightHand/Fingertip")]:
		assert_true(tip is Interactor and tip.is_in_group("interactor"), "a fingertip on each hand")
	var hci: Node = _main.get_node("HandControllerInput")
	assert_eq(hci.left_hand_path, left.get_path(), "the thumbsticks fly the hand controllers")
	assert_eq(hci.right_hand_path, rig.get_node("RightHand").get_path())
	assert_true(_main.recorder.write_on_exit, "a headset run leaves a record")
	assert_eq(_main.recorder.xr_interface, _xr)
	assert_eq(_main.view.view_mode, 2, "the cabin")
	_main.set_view(0)
	assert_eq(_main.view.view_mode, 2, "is the only view")
	assert_true(cam.current)


func test_the_session_paces_frames_and_the_record_covers_a_restart() -> void:
	_xr.session_begun.emit()
	assert_eq(Engine.max_fps, 72, "frames paced to the headset's 72 Hz")
	assert_almost_eq(_main.perf.frame_budget_ms, 1000.0 / 72.0, 1e-6)
	assert_eq(Bus.get_value("player.xr_refresh_hz"), 72.0)
	assert_true(Bus.get_value("player.xr_session"))
	_xr.session_focussed.emit()
	assert_true(Bus.get_value("player.xr_focus"))
	_xr.session_visible.emit()
	assert_false(Bus.get_value("player.xr_focus"), "visible but not focused, as under the runtime's dashboard")
	var rec: VrAcceptanceRecorder = _main.recorder
	assert_true(rec.record["focus_seen"])
	# The headset comes off and the runtime stops the session, then starts
	# it again when it goes back on.
	_xr.session_stopping.emit()
	assert_false(Bus.get_value("player.xr_session"))
	assert_eq(DirAccess.get_files_at(OUT).size(), 2, "the record so far is written")
	_xr.session_begun.emit()
	_main.menu.activate("seat")
	_xr.session_stopping.emit()
	var files := DirAccess.get_files_at(OUT)
	assert_eq(files.size(), 2, "and rewritten, not doubled")
	var json: String = Array(files).filter(func(f: String) -> bool: return f.ends_with(".json"))[0]
	var d = JSON.parse_string(FileAccess.get_file_as_string(OUT + "/" + json))
	assert_eq(int(d["session_stops"]), 2)
	assert_has(d["seats"], "CMP", "with the whole run")
	var md := rec.markdown()
	assert_string_contains(md, "| S1 | OpenXR runtime detected; `--xr-mode on` starts the XR rig in the cabin | | evidence: pass (`player.rig` = xr) |")
	assert_string_contains(md, "| S5 | Clean session end and headset removal | | evidence: pass: 2 session stops, window not closed |")

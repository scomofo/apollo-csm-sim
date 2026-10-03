## Actual viewport keyboard/GUI recovery check, with isolated temporary saves.
## godot --path . tools/reading_recovery.tscn -- OUTPUT_DIRECTORY
extends Node

const SAVES := "user://reading_recovery_review"
var main: Node


func _ready() -> void:
	call_deferred("_run")


func _frames() -> void:
	for i in 5:
		await get_tree().process_frame


func _key(code: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code
		event.physical_keycode = code
		event.pressed = down
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _frames()


func _click(button: Button) -> void:
	var point := button.get_global_rect().get_center()
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		get_tree().root.push_input(event, true)
		await get_tree().process_frame
	await _frames()


func _run() -> void:
	Bus.reset()
	SimClock.reset()
	SimClock.manual = true
	get_tree().root.size = Vector2i(1024, 600)
	main = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	main.flight_given = true
	main.saves_dir = SAVES
	add_child(main)
	SimClock.paused = true
	var saved_get := SimClock.get_seconds
	await _frames()
	await _key(KEY_F2)
	if not _check(not main.hud._help.visible, "the startup key reference must clear the reading view"):
		return
	await _click(main.guide.tour_button)
	await _key(KEY_F3)
	if not _check(main.book.list().title == "CM cockpit walkthrough" and main.book.list().index == 1,
			"GUI tour + F3 must enter the actual reading step"):
		return
	await _key(KEY_F5)
	await _click(main.guide.continue_button)
	if not _check(main.book.list().index > 1, "advance the abandoned future before F9"):
		return
	await _key(KEY_F9)
	if not _check(main.book.list().index == 1 and main.guide.is_shown(), "guide F9 restores the lesson"):
		return
	if not _check(main.guide.book == main.card.book and main.guide.book == main.menu.book,
			"guide, cabin card and wrist share recovered reading state"):
		return
	if not _check(SimClock.get_seconds == saved_get and SimClock.paused, "the displayed reading pass cannot advance the paused flight"):
		return
	await _key(KEY_H)
	if not _check(main.hud._help.visible, "the crew can still reopen the key reference explicitly"):
		return
	await _key(KEY_H)
	var args := OS.get_cmdline_user_args()
	if args.size() and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(args[0])
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args[0].path_join("checklist-recovered.png"))
	_cleanup()
	print("Displayed tour, F3, GUI Continue, F5/F9, shared reading and paused flight recovery passed")
	get_tree().quit()


func _check(ok: bool, message: String) -> bool:
	if not ok:
		push_error(message)
		_cleanup()
		get_tree().quit(1)
	return ok


func _cleanup() -> void:
	if DirAccess.dir_exists_absolute(SAVES):
		for file in DirAccess.get_files_at(SAVES):
			DirAccess.remove_absolute(SAVES.path_join(file))
		DirAccess.remove_absolute(SAVES)

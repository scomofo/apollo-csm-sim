## Fixed crew-eye and supplemental inspection views of the actual CM cabin.
## Usage: godot --path . tools/couch_review.tscn -- OUTPUT_DIRECTORY
## No control, eye, panel or gameplay camera geometry is changed by the tool.
extends Node


func _ready() -> void:
	SimClock.manual = true
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() else "user://couch-review"
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.start_phase = "lunar_orbit"
	main.flight_given = true
	add_child(main)
	main.set_view(2)
	main.hud.visible = false
	main.guide.set_capture_visible(false)
	var cam: Camera3D = main.rig.get_node("Camera3D")
	var poses := {
		"couches-cdr": {"eye": CmCabin.EYE_CDR, "target": Vector3(0.52, 0.05, 0.30), "fov": 90.0},
		"couches-inspection": {"eye": Vector3(1.12, -0.95, -0.65), "target": Vector3(0.65, 0.0, 0.20), "fov": 65.0},
	}
	var records := []
	for view: String in poses:
		var pose: Dictionary = poses[view]
		cam.global_position = main.cabin.to_global(pose["eye"])
		cam.look_at(main.cabin.to_global(pose["target"]), main.cabin.global_basis * Vector3(0, 0, -1))
		cam.fov = pose["fov"]
		for i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := out.path_join(view + ".png")
		var img := get_viewport().get_texture().get_image()
		img.save_png(path)
		records.append({"file": view + ".png", "sha256": FileAccess.get_sha256(path),
			"size": [img.get_width(), img.get_height()], "fov_deg": cam.fov,
			"eye_body": _xyz(pose["eye"]), "target_body": _xyz(pose["target"]),
			"up_body": [0, 0, -1], "camera_body": _pose(main.cabin.global_transform.affine_inverse() * cam.global_transform)})
		print("saved " + path)
	var record := FileAccess.open(out.path_join("couch-captures.json"), FileAccess.WRITE)
	record.store_string(JSON.stringify({"version": 1, "get_s": SimClock.get_seconds,
		"phase": Bus.get_value("mission.phase"), "engine": Engine.get_version_info()["string"],
		"script_sha256": FileAccess.get_sha256("res://tools/couch_review.gd"),
		"cabin_sha256": FileAccess.get_sha256("res://src/cabin/cm_cabin.gd"),
		"captures": records}, "\t"))
	record.close()
	get_tree().quit()


func _xyz(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


func _pose(t: Transform3D) -> Dictionary:
	return {"origin": _xyz(t.origin), "basis": [_xyz(t.basis.x), _xyz(t.basis.y), _xyz(t.basis.z)]}

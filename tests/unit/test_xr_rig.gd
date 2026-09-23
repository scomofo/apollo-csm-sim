## OpenXR seated rig, headless: the scene instantiates without a runtime,
## recenter() moves the origin so the tracked head lands on the anchor with
## the user facing -Z, and the recenter binding is the B/Y action. Hardware
## behaviour (tracking, focus, refresh) stays a headset check
## (docs/ROADMAP.md, slice 2e). Ported from gemini-capsule at 40e449c.
extends GutTest

const XR_RIG := preload("res://scenes/player/xr_rig.tscn")


func before_each() -> void:
	Bus.reset()


func test_recenter_places_the_tracked_head_on_the_anchor() -> void:
	var anchor := Node3D.new()
	add_child_autofree(anchor)
	anchor.position = Vector3(0.3, 1.1, -0.2)   # design eye point
	var rig: XROrigin3D = XR_RIG.instantiate()
	anchor.add_child(rig)
	var cam: XRCamera3D = rig.get_node("XRCamera3D")
	# Without a runtime the camera stays where we put it: a seated user 0.2 m
	# right, 1.6 m up, 0.1 m back, turned 30 degrees left.
	cam.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(30.0)), Vector3(0.2, 1.6, 0.1))
	rig.recenter()
	var head_world := cam.global_position
	assert_almost_eq(head_world.distance_to(anchor.global_position), 0.0, 1e-4, "head on the design eye point")
	var forward := -cam.global_transform.basis.z
	assert_almost_eq(forward.x, 0.0, 1e-4, "facing -Z after recenter (no yaw)")
	assert_lt(forward.z, -0.99)
	assert_almost_eq(anchor.position.distance_to(Vector3(0.3, 1.1, -0.2)), 0.0, 1e-9, "cabin anchor never moved")
	assert_eq(Bus.get_value("player.recenter_count"), rig.recenter_count)


func test_controller_by_button_recenters_and_other_buttons_do_not() -> void:
	var rig: XROrigin3D = XR_RIG.instantiate()
	add_child_autofree(rig)
	await wait_process_frames(1)   # lets the deferred first recenter run
	var n0: int = rig.recenter_count
	rig.get_node("LeftHand").button_pressed.emit("trigger_click")
	assert_eq(rig.recenter_count, n0, "trigger does not recenter")
	rig.get_node("RightHand").button_pressed.emit(rig.RECENTER_ACTION)
	assert_eq(rig.recenter_count, n0 + 1, "B/Y recenters")
	assert_true(rig.has_node("LeftHand/Fingertip") and rig.has_node("RightHand/Fingertip"), "fingertip interactors on both hands")
	for hand in ["LeftHand", "RightHand"]:
		var shape := rig.get_node("%s/Fingertip/Shape" % hand) as CollisionShape3D
		assert_almost_eq((shape.shape as SphereShape3D).radius, 0.012, 1e-9, "the touch sphere is Gemini's")
		assert_true(rig.get_node("%s/Fingertip/Marker" % hand).visible, "and the tester can see where it is")

## The tall presentation uses the same gauge state and calibration contract.
## Ported from gemini-capsule at 40e449c.
extends GutTest

const GAUGE := preload("res://scenes/instruments/gauge_round.tscn")


func before_each() -> void:
	Bus.reset()


func _gauge(properties: Dictionary = {}) -> Node3D:
	var gauge := GAUGE.instantiate()
	for key in properties:
		gauge.set(key, properties[key])
	add_child_autofree(gauge)
	return gauge


func test_live_quantity_moves_pointer_across_linear_scale_and_clamps() -> void:
	var gauge := _gauge({"face_style": "vertical", "channel": "test.qty_pct", "face_caption": "QTY %"})
	for sample in [{"value": 0.0, "y": -0.052}, {"value": 50.0, "y": 0.0},
			{"value": 100.0, "y": 0.052}, {"value": 130.0, "y": 0.052}, {"value": -10.0, "y": -0.052}]:
		Bus.set_value("test.qty_pct", sample.value)
		assert_almost_eq(gauge.value, sample.value, 0.000001, "retains the live quantity")
		assert_almost_eq(gauge.get_node("Needle").position.y, sample.y, 0.000001, "pointer follows the scale")
		assert_almost_eq(gauge.get_node("Needle").rotation.z, 0.0, 0.000001, "linear presentation does not rotate")
	assert_eq(gauge.get_node("FaceCaption").text, "QTY %")
	assert_false(gauge.get_node("Needle2").visible)
	assert_true(gauge.get_node("Bezel").mesh is ArrayMesh, "round housing is replaced, not left inside the new face")
	assert_eq(gauge.get_node("Bezel").mesh.get_aabb().size, Vector3(0.070, 0.155, 0.014))
	assert_true(gauge.get_node("Dial").mesh is BoxMesh)
	assert_false(gauge.has_node("Hub"), "the old rotary hub is absent")
	assert_eq(gauge.get_node("ScaleMarks").multimesh.instance_count, 21)
	var pointer_faces: PackedVector3Array = gauge.get_node("Needle/Mesh").mesh.get_faces()
	assert_eq(pointer_faces.size(), 3)
	# Godot renders clockwise front faces. Supplied lighting normals cannot
	# make a back-facing triangle visible, so check the geometry itself.
	var pointer_normal := (pointer_faces[2] - pointer_faces[0]).cross(pointer_faces[1] - pointer_faces[0]).normalized()
	assert_gt(pointer_normal.dot(Vector3.BACK), 0.999, "live pointer faces the crew instead of being culled")
	var bezel_faces: PackedVector3Array = gauge.get_node("Bezel").mesh.get_faces()
	var lip_faces := 0
	var lip_faces_outward := true
	for i in range(0, bezel_faces.size(), 3):
		var a := bezel_faces[i]
		var b := bezel_faces[i + 1]
		var c := bezel_faces[i + 2]
		if is_equal_approx(a.z, 0.014) and is_equal_approx(b.z, 0.014) and is_equal_approx(c.z, 0.014):
			lip_faces += 1
			lip_faces_outward = lip_faces_outward and (c - a).cross(b - a).normalized().dot(Vector3.BACK) > 0.999
	assert_eq(lip_faces, 16, "all eight sides of the chamfered opening have a front lip")
	assert_true(lip_faces_outward, "bezel lip faces the crew")


func test_linear_calibration_and_units_survive_power_loss_and_recovery() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 0.8))
	curve.add_point(Vector2(1, 1))
	var gauge := _gauge({"face_style": "vertical", "channel": "test.pressure", "converter": "pa_to_psi",
		"max_value": 10.0, "calibration": curve, "power_channel": "test.power"})
	Bus.set_value("test.pressure", Units.psi_to_pa(5.0))
	assert_almost_eq(gauge.value, 5.0, 0.000001)
	assert_almost_eq(gauge.get_node("Needle").position.y, 0.0312, 0.0001, "same non-linear calibration maps to height")
	var numeral: Label3D = gauge.get_node("Numerals/N8")
	var fixed_position := numeral.position
	Bus.set_value("test.pressure", Units.psi_to_pa(4.0))
	assert_eq(numeral.text, "4")
	assert_almost_eq(fixed_position.y, gauge.get_node("Needle").position.y, 0.000001, "printed scale and live needle agree")
	Bus.set_value("test.power", 0.0)
	assert_almost_eq(gauge.get_node("Needle").position.y, -0.052, 0.000001)
	assert_eq(numeral.position, fixed_position, "printed scale stays fixed while unpowered")
	Bus.set_value("test.pressure", Units.psi_to_pa(10.0))
	assert_almost_eq(gauge.get_node("Needle").position.y, -0.052, 0.000001, "updates cannot unpark an unpowered gauge")
	Bus.set_value("test.power", 28.0)
	assert_almost_eq(gauge.get_node("Needle").position.y, 0.052, 0.000001, "recovery displays the latest value")


func test_linear_second_needle_keeps_independent_binding() -> void:
	var gauge := _gauge({"face_style": "vertical", "channel": "test.a", "channel2": "test.b"})
	Bus.set_value("test.a", 25.0)
	Bus.set_value("test.b", 75.0)
	assert_true(gauge.get_node("Needle2").visible)
	assert_almost_eq(gauge.get_node("Needle").position.y, -0.026, 0.000001)
	assert_almost_eq(gauge.get_node("Needle2").position.y, 0.026, 0.000001)


func test_default_round_profile_keeps_original_footprint_and_sweep() -> void:
	var gauge := _gauge({"channel": "test.round"})
	assert_eq(gauge.face_style, "round")
	assert_true(gauge.get_node("Bezel").mesh is ArrayMesh)
	var bounds: AABB = gauge.get_node("Bezel").mesh.get_aabb()
	assert_almost_eq(bounds.size.x, 0.060, 0.000001)
	assert_almost_eq(bounds.size.y, 0.060, 0.000001)
	assert_true(gauge.get_node("Dial").mesh is CylinderMesh)
	assert_true(gauge.has_node("Hub"))
	assert_eq(gauge.get_node("ScaleMarks").multimesh.instance_count, 11)
	Bus.set_value("test.round", 100.0)
	assert_almost_eq(rad_to_deg(gauge.get_node("Needle").rotation.z), -135.0, 0.0001)
	assert_almost_eq(gauge.get_node("Needle").position.y, 0.0, 0.000001)


func test_round_rim_does_not_cover_scale_or_sweeping_needles() -> void:
	var gauge := _gauge({"channel": "test.round", "channel2": "test.second"})
	var bezel: MeshInstance3D = gauge.get_node("Bezel")
	var faces := bezel.mesh.get_faces()
	# Probe the whole aperture, including the 25 mm outer scale-mark radius.
	# A filled cylinder or an inward lip would cut these front-to-face rays.
	var blocked := 0
	for radius: float in [0.0, 0.010, 0.023, 0.025]:
		for i in 48:
			var xy := Vector2(cos(TAU * i / 48.0), sin(TAU * i / 48.0)) * radius
			for j in range(0, faces.size(), 3):
				if Geometry3D.segment_intersects_triangle(Vector3(xy.x, xy.y, 0.02),
						Vector3(xy.x, xy.y, 0.0075), faces[j], faces[j + 1], faces[j + 2]) != null:
					blocked += 1
	assert_eq(blocked, 0, "rim leaves the complete printed scale and needle sweep open")
	var visible_bevels := 0
	for i in range(0, faces.size(), 3):
		var a := faces[i]
		var b := faces[i + 1]
		var c := faces[i + 2]
		if minf(a.z, minf(b.z, c.z)) >= 0.0085 - 0.00001:
			assert_gt((c - a).cross(b - a).normalized().z, 0.0,
				"exposed chamfer faces the crew instead of being culled")
			visible_bevels += 1
	assert_gt(visible_bevels, 48, "the probe checks actual annular bevel geometry")
	for value in [0.0, 25.0, 50.0, 75.0, 100.0]:
		Bus.set_value("test.round", value)
		Bus.set_value("test.second", 100.0 - value)
		assert_almost_eq(rad_to_deg(gauge.get_node("Needle").rotation.z),
			-gauge.angle_for(value), 0.0001)
		assert_almost_eq(rad_to_deg(gauge.get_node("Needle2").rotation.z),
			-gauge.angle_for(100.0 - value), 0.0001)

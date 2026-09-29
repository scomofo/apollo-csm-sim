## Eagle's cabin (docs/ROADMAP.md, slice 3f): the LM's crew compartment,
## built in its body axes from the docking port and kept about the centre
## of mass for its configuration, its panels facing the crew members who
## work them, its windows, and the landing point designator's scale on the
## commander's window.
extends SimTest


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func _cabin() -> LmCabin:
	var cabin := LmCabin.create()
	add_child_autofree(cabin)
	return cabin


## The area of [param mi]'s mesh, m².
func _area(mi: MeshInstance3D) -> float:
	var faces := mi.mesh.get_faces()
	var area := 0.0
	for i in range(0, faces.size(), 3):
		area += (faces[i + 1] - faces[i]).cross(faces[i + 2] - faces[i]).length() * 0.5
	return area


func _inside_shell(p: Vector3) -> bool:
	if p.z > LmCabin.CC_AFT_Z:
		return p.z <= LmCabin.FRONT_Z + 1e-6 and absf(p.y) <= LmCabin.half_width(p.x) and p.x >= LmCabin.FLOOR_X
	return p.z >= LmCabin.MID_AFT_Z and absf(p.y) <= LmCabin.MID_HALF_Y and p.x >= LmCabin.MID_FLOOR_X and p.x <= LmCabin.MID_TOP_X


func test_the_commander_stands_facing_the_windows() -> void:
	var cabin := _cabin()
	assert_true(cabin.anchor.global_basis.is_equal_approx(Basis.IDENTITY),
		"the rig looks along the render -Z, the LM's +Z, with the LM's +X up")
	var port := Docking.lm_port_m("lm")
	assert_almost_eq(cabin.anchor.global_position, Frames.LM_BODY_TO_GODOT * (LmCabin.EYE_CDR + Vector3(port, 0, 0)),
		Vector3.ONE * 1e-6, "the commander's eye from the LM's centre of mass")
	assert_almost_eq(LmCabin.EYE_CDR.x - LmCabin.FLOOR_X, 1.6, 1e-6, "standing, 1.6 m above the floor")
	assert_almost_eq(LmCabin.FRONT_Z - LmCabin.EYE_CDR.z, 0.3, 1e-6, "0.3 m behind the window")
	assert_eq(Bus.get_value("player.seat"), "CDR")


func test_every_panel_faces_its_crew_member_inside_the_shell() -> void:
	var cabin := _cabin()
	var eyes := [LmCabin.EYE_CDR, LmCabin.EYE_LMP]
	for panel_name in LmCabin.PANELS:
		var p: Dictionary = cabin.panels()[panel_name]
		var b: Basis = p["basis"]
		assert_almost_eq(b.determinant(), 1.0, 1e-6, "%s: a rotation" % panel_name)
		assert_almost_eq(b.x.x, 0.0, 1e-6, "%s: its lettering runs level" % panel_name)
		var centre: Vector3 = p["centre"]
		var seen := 0.0
		for eye in eyes:
			seen = maxf(seen, b.z.dot((eye - centre).normalized()))
		assert_gt(seen, 0.6, "%s faces a crew member, within 53 deg" % panel_name)
		var half: Vector2 = p["size"] * 0.5
		for c in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, -1), Vector2(1, 1)]:
			var corner: Vector3 = centre + b * Vector3(c.x * half.x, c.y * half.y, 0.0)
			assert_true(_inside_shell(corner), "%s's corner %s inside the cabin" % [panel_name, corner])
		# Its mount in the scene is where panels() says.
		var mount := cabin.panel_node(panel_name)
		assert_true(mount.transform.is_equal_approx(Transform3D(b, centre)), "%s mounted" % panel_name)


func test_the_bulkheads_are_whole_but_for_their_openings() -> void:
	var cabin := _cabin()
	# The cylinder's cross-section above the floor, reaching into the wall
	# all round: its area by the shoelace formula.
	var r := LmCabin.CC_R
	var outline := LmCabin.bulkhead_outline()
	var section := 0.0
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		section += (a.x * b.y - b.x * a.y) * 0.5
		if i < outline.size() - 1:
			var mid := (a + b) * 0.5 - Vector2(0.0, LmCabin.CC_AXIS_X)
			assert_gt(mid.length(), r, "past the wall between chord %d's ends" % i)
	section = absf(section)
	var windows := 0.0
	for w in LmCabin.WINDOWS:
		var t: Array = LmCabin.WINDOWS[w]
		windows += absf((t[1] - t[0]).cross(t[2] - t[0])) * 0.5
	assert_almost_eq(windows, 2.0 * 0.46 * 0.82 * 0.5, 1e-6)
	assert_almost_eq(_area(cabin.get_node("FrontBulkhead")), section - windows, 0.002,
		"the front bulkhead, less its two windows")
	var opening := 2.0 * LmCabin.MID_HALF_Y * (LmCabin.MID_TOP_X - LmCabin.MID_FLOOR_X)
	assert_almost_eq(_area(cabin.get_node("AftBulkhead")), section - opening, 0.002,
		"the aft bulkhead, less the way into the midsection")
	var ceiling := 2.0 * LmCabin.MID_HALF_Y * (LmCabin.CC_AFT_Z - LmCabin.MID_AFT_Z) - PI * pow(LmCabin.TUNNEL_R, 2)
	assert_almost_eq(_area(cabin.get_node("MidsectionCeiling")), ceiling, 0.005, "the ceiling, open to the tunnel")
	# The wall is open over the commander, at the overhead window, to a
	# step of its grid.
	var faces := (cabin.get_node("Wall") as MeshInstance3D).mesh.get_faces()
	var t_open: Vector2 = LmCabin.OVERHEAD["theta_deg"] + Vector2(LmCabin.WALL_STEP_DEG, -LmCabin.WALL_STEP_DEG)
	var z_open: Vector2 = LmCabin.OVERHEAD["z"] + Vector2(LmCabin.WALL_STEP_Z, -LmCabin.WALL_STEP_Z)
	var across := 0
	for i in range(0, faces.size(), 3):
		var m := (faces[i] + faces[i + 1] + faces[i + 2]) / 3.0
		var t := rad_to_deg(atan2(m.y, m.x - LmCabin.CC_AXIS_X))
		if t > t_open.x and t < t_open.y and m.z > z_open.x and m.z < z_open.y:
			across += 1
	assert_eq(across, 0, "no wall across the overhead window")
	var over := Vector3(LmCabin.CC_AXIS_X + r * cos(deg_to_rad(-15.0)), r * sin(deg_to_rad(-15.0)), 1.2)
	assert_lt(over.distance_to(LmCabin.EYE_CDR), 0.6, "the overhead window is above the commander")
	assert_gt(over.x, LmCabin.EYE_CDR.x, "above")


func test_the_lpd_marks_are_where_the_commander_looks_at_their_angles() -> void:
	var cabin := _cabin()
	var window := PackedVector2Array(LmCabin.WINDOWS["CommanderWindow"])
	assert_eq(cabin.lpd_marks.size(), LmCabin.LPD_MAX_DEG / LmCabin.LPD_STEP_DEG + 1)
	for deg in cabin.lpd_marks:
		var m := LmCabin.lpd_mark(deg)
		var d := m - LmCabin.EYE_CDR
		assert_almost_eq(rad_to_deg(atan2(-d.x, d.z)), float(deg), 1e-4,
			"%d deg below +Z, as the LGC's N64 measures it" % deg)
		assert_almost_eq(d.y, 0.0, 1e-9, "straight ahead of the commander")
		assert_true(Geometry2D.is_point_in_polygon(Vector2(m.y, m.x), window), "%d deg on the window" % deg)
		var node: Node3D = cabin.lpd_marks[deg]
		assert_almost_eq(node.position, m - Vector3(0, 0, 0.004), Vector3.ONE * 1e-6, "drawn on its inner pane")
	assert_not_null(cabin.get_node("LPD/Figure60"), "figures every 10 deg")


func test_the_seats_and_what_each_reaches() -> void:
	var cabin := _cabin()
	var dsky: Node3D = cabin.items["P4_DSKY"]
	var card_from_eye := cabin.card_mount.position - cabin.anchor.position
	assert_almost_eq(card_from_eye.length(), 0.44, 0.01, "the card at reading distance")
	assert_lt(card_from_eye.y, -0.3, "by the commander's left shoulder")
	var reach := {}
	for seat in ["CDR", "LMP"]:
		cabin.set_seat(seat)
		assert_eq(cabin.seat, seat)
		assert_almost_eq(cabin.anchor.position, LmCabin.SEATS[seat], Vector3.ONE * 1e-9)
		reach[seat] = cabin.anchor.global_position.distance_to(dsky.global_position)
		assert_lt(reach[seat], 0.95, "%s: the DSKY between the two stations" % seat)
	assert_almost_eq(reach["CDR"], reach["LMP"], 1e-6, "as far from either")
	var card_lmp := cabin.card_mount.position - cabin.anchor.position
	assert_almost_eq(card_lmp, Vector3(card_from_eye.x, -card_from_eye.y, card_from_eye.z), Vector3.ONE * 1e-6,
		"the LM pilot's card by the right shoulder")
	cabin.next_seat()
	assert_eq(cabin.seat, "CDR", "SEAT goes round the two")
	cabin.set_seat("CMP")
	assert_eq(cabin.seat, "CDR", "only Eagle's stations")
	var eye := cabin.anchor.global_position
	for id in ["P5_ENGINE_STOP", "P5_ENGINE_START", "P5_DES_RATE", "P1_ENG_ARM", "P1_ABORT_STAGE", "P3_LGC_MODE",
			"P3_RR_MODE"]:
		assert_lt(eye.distance_to(cabin.items[id].global_position), 0.9, "%s within the commander's reach" % id)


func test_the_cabin_stays_about_the_centre_of_mass_as_the_lm_stages() -> void:
	var cabin := _cabin()
	var datum := func(cfg: String) -> Vector3: return Frames.LM_BODY_TO_GODOT * Vector3(Docking.lm_port_m(cfg), 0, 0)
	assert_almost_eq(cabin.position, datum.call("lm"), Vector3.ONE * 1e-6, "the port 3.4 m above the LM's centre of mass")
	Bus.set_value("lm.dyn.config", "lm_ascent")
	cabin._process(0.0)
	assert_almost_eq(cabin.position, datum.call("lm_ascent"), Vector3.ONE * 1e-6, "and 1.5 m above the ascent stage's")
	assert_almost_eq(cabin.anchor.global_position.y, LmCabin.EYE_CDR.x + Docking.lm_port_m("lm_ascent"), 1e-6,
		"the eye level with the ascent stage's centre of mass")
	assert_true(cabin.global_basis.is_equal_approx(Frames.LM_BODY_TO_GODOT), "in the LM's axes")


func test_the_lm_axes_and_its_level_attitude() -> void:
	var b := Frames.LM_BODY_TO_GODOT
	assert_almost_eq(b.determinant(), 1.0, 1e-9)
	assert_eq(b * Vector3(0, 0, 1), Vector3(0, 0, -1), "LM +Z, out of the windows, is Godot forward")
	assert_eq(b * Vector3(1, 0, 0), Vector3(0, 1, 0), "LM +X is up")
	var level := Frames.LM_LEVEL
	assert_almost_eq(level.determinant(), 1.0, 1e-9)
	assert_eq(level * Vector3(0, 0, 1), Vector3(1, 0, 0), "flying level, the windows face along the track")
	assert_eq(level * Vector3(1, 0, 0), Vector3(0, 0, -1), "and its +X away from the body below")
	assert_true(Frames.level_turn(level.get_rotation_quaternion(), "lm").is_equal_approx(Basis.IDENTITY))
	# Windows up 20 deg (about the LM's +Y) turns the view as the CSM's nose up 20 deg does.
	var up20 := level * Basis(Vector3(0, 1, 0), deg_to_rad(20.0))
	var csm := Frames.level_turn(Quaternion(Vector3(0, 1, 0), deg_to_rad(20.0)), "csm")
	assert_true(Frames.level_turn(up20.get_rotation_quaternion(), "lm").is_equal_approx(csm))

## Apollo-side checks on the instrument prefabs taken from gemini-capsule:
## the FDAI shows attitude the way the flown instrument (and the 2D FDAI in
## src/presentation/fdai.gd) does, the clock formats GET, and the unit,
## frame and material helpers the prefabs rely on.
extends GutTest

const FDAI := preload("res://scenes/instruments/fdai.tscn")
const CLOCK := preload("res://scenes/instruments/clock_display.tscn")


func before_each() -> void:
	Bus.reset()


func _fdai(q: Quaternion) -> Node3D:
	var fdai := FDAI.instantiate()
	add_child_autofree(fdai)
	Bus.set_value("guid.indicator.attitude", q)
	return fdai


## Ball-local direction (ball +Y is the sky) seen at a point of the face,
## in the case's own axes: +Z is the centre, toward the crew; +X right; +Y up.
func _shown(fdai: Node3D, face_dir: Vector3) -> Vector3:
	var ball: Node3D = fdai.get_node("Ball")
	var case_to_ball := ball.global_transform.basis.inverse() * fdai.global_transform.basis
	return case_to_ball * face_dir.normalized()


func _deg(x: float) -> float:
	return deg_to_rad(x)


func test_fdai_level_shows_the_horizon_through_the_centre() -> void:
	var f := _fdai(Quaternion.IDENTITY)
	assert_almost_eq(_shown(f, Vector3(0, 0, 1)), Vector3(0, 0, 1), Vector3.ONE * 1e-6)


func test_fdai_nose_up_shows_sky_at_the_centre() -> void:
	# Pitch up 25 deg: a rotation about body +Y that turns +X toward -Z (up).
	var f := _fdai(Quaternion(Vector3(0, 1, 0), _deg(25.0)))
	assert_almost_eq(_shown(f, Vector3(0, 0, 1)), Vector3(0, sin(_deg(25.0)), cos(_deg(25.0))), Vector3.ONE * 1e-5,
		"the centre reads 25 deg above the horizon")


func test_fdai_right_roll_turns_the_horizon_counterclockwise() -> void:
	# Roll right 30 deg: a rotation about body +X that turns +Y (right) down.
	var f := _fdai(Quaternion(Vector3(1, 0, 0), _deg(30.0)))
	assert_lt(_shown(f, Vector3(sin(_deg(10.0)), 0, cos(_deg(10.0)))).y, 0.0, "right of centre drops below the horizon")
	assert_gt(_shown(f, Vector3(-sin(_deg(10.0)), 0, cos(_deg(10.0)))).y, 0.0, "left of centre rises into the sky")


func test_fdai_right_yaw_moves_the_ball_markings_left() -> void:
	# Yaw right 20 deg: a rotation about body +Z that turns +X toward +Y.
	var f := _fdai(Quaternion(Vector3(0, 0, 1), _deg(20.0)))
	assert_almost_eq(_shown(f, Vector3(0, 0, 1)), Vector3(sin(_deg(20.0)), 0, cos(_deg(20.0))), Vector3.ONE * 1e-5,
		"what sat 20 deg right of centre is now at the centre")


func test_fdai_reads_the_same_on_a_tilted_panel() -> void:
	var f := FDAI.instantiate()
	add_child_autofree(f)
	# Mounted on a panel tilted back 30 deg and turned 20 deg toward the crew.
	f.basis = Basis(Vector3(0, 1, 0), _deg(20.0)) * Basis(Vector3(1, 0, 0), _deg(-30.0))
	Bus.set_value("guid.indicator.attitude", Quaternion.IDENTITY)
	assert_almost_eq(_shown(f, Vector3(0, 0, 1)), Vector3(0, 0, 1), Vector3.ONE * 1e-5, "level: horizon across the centre")
	Bus.set_value("guid.indicator.attitude", Quaternion(Vector3(0, 1, 0), _deg(25.0)))
	assert_almost_eq(_shown(f, Vector3(0, 0, 1)), Vector3(0, sin(_deg(25.0)), cos(_deg(25.0))), Vector3.ONE * 1e-5)


func test_clock_formats_get_and_blanks_without_power() -> void:
	var clock := CLOCK.instantiate()
	clock.set("channel", "time.get_s")
	clock.set("power_channel", "eps.bus_a_v")
	add_child_autofree(clock)
	Bus.set_value("time.get_s", 102.0 * 3600.0 + 45.0 * 60.0 + 40.0)
	Bus.set_value("eps.bus_a_v", 28.0)
	assert_eq(clock.get_node("Label").text, "102:45:40")
	Bus.set_value("eps.bus_a_v", 0.0)
	assert_eq(clock.get_node("Label").text, "---:--:--")
	assert_eq(clock.format_seconds(330.0, "mm:ss"), "05:30")


func test_unit_conversions_by_name() -> void:
	assert_almost_eq(Units.convert(1852.0, "m_to_nmi"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(0.3048, "m_to_ft"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(0.3048, "mps_to_fps"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(Units.PSI, "pa_to_psi"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(Units.LBF, "n_to_lbf"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(Units.LBM, "kg_to_lbm"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(Units.G0, "mps2_to_g"), 1.0, 1e-9)
	assert_almost_eq(Units.convert(273.15, "k_to_f"), 32.0, 1e-9)
	assert_almost_eq(Units.convert(PI, "rad_to_deg"), 180.0, 1e-9)
	assert_eq(Units.convert(7.0, "none"), 7.0)
	assert_eq(Units.convert(7.0, "no_such_conversion"), 7.0, "unknown names pass the value through")
	assert_almost_eq(Units.nmi_to_m(Units.m_to_nmi(12345.0)), 12345.0, 1e-6)
	assert_almost_eq(Units.psi_to_pa(Units.pa_to_psi(101325.0)), 101325.0, 1e-6)


func test_body_to_godot_is_a_rotation_with_the_nose_forward() -> void:
	var b := Frames.BODY_TO_GODOT
	assert_almost_eq(b.determinant(), 1.0, 1e-9)
	assert_eq(b * Vector3(1, 0, 0), Vector3(0, 0, -1), "body +X (nose) is Godot forward")
	assert_eq(b * Vector3(0, 0, 1), Vector3(0, -1, 0), "body +Z (crew down) is Godot down")


func test_every_material_role_says_what_it_is_based_on() -> void:
	for role in CabinMaterials.roles():
		var p: Dictionary = CabinMaterials.PROVENANCE[role]
		assert_ne(str(p.get("basis", "")), "", "%s has a basis" % role)
		assert_ne(str(p.get("confidence", "")), "", "%s has a confidence" % role)
		var m := CabinMaterials.get_material(role) as StandardMaterial3D
		assert_ne(m.albedo_color, Color(1, 0, 1), "%s is built, not the unknown-role magenta" % role)
		assert_eq(CabinMaterials.get_material(role), m, "%s is one shared instance" % role)

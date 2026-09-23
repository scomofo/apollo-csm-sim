## The space view keeps the cabin fixed at the render origin and turns the
## world around it (docs/ROADMAP.md, slice 2b). gemini-capsule's
## tests/unit/test_world_presenter.gd checks the same rule for its cabin.
extends GutTest

const SpaceView := preload("res://src/presentation/space_view.gd")
const R := Bodies.R_EARTH + 185000.0
const V := 7793.0

var view: Node3D


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	view = SpaceView.new()
	add_child_autofree(view)
	# Circular Earth orbit: r along ECI +X, v along +Y.
	Bus.set_value("dyn.primary", "earth")
	Bus.set_value("dyn.r_m", [R, 0.0, 0.0])
	Bus.set_value("dyn.v_mps", [0.0, V, 0.0])
	Bus.set_value("time.get_s", 0.0)
	Bus.set_value("dyn.config", "csm")


## Body aligned with LVLH: +X along track, +Z toward the Earth.
func _lvlh() -> Quaternion:
	return Trajectory.lvlh_basis(Vector3(R, 0, 0), Vector3(0, V, 0)).get_rotation_quaternion()


func _render(q: Quaternion) -> void:
	Bus.set_value("dyn.att_q", q)
	view._process(0.0)


func _turned() -> Quaternion:
	# Pitch up 40 deg, then roll right 25 deg.
	return _lvlh() * Quaternion(Vector3(0, 1, 0), deg_to_rad(40.0)) * Quaternion(Vector3(1, 0, 0), deg_to_rad(25.0))


func test_earth_is_below_the_crew_in_lvlh_attitude() -> void:
	_render(_lvlh())
	assert_almost_eq(view.earth.position.normalized(), Vector3(0, -1, 0), Vector3.ONE * 1e-5,
		"crew down (body +Z) is Godot -Y")


func test_turning_the_vehicle_moves_the_world_but_not_the_camera_or_the_cabin() -> void:
	for mode in [0, 1]:
		view.view_mode = mode
		_render(_lvlh())
		var cam: Transform3D = view.camera.global_transform
		var cabin: Transform3D = view.csm.global_transform
		var earth: Vector3 = view.earth.position
		var moon: Vector3 = view.moon.position
		var sun: Vector3 = view.sun.global_transform.basis.z
		var sky: Basis = view.sky_material.get_shader_parameter("cabin_to_eci")
		_render(_turned())
		assert_true(view.camera.global_transform.is_equal_approx(cam), "camera never moved (view %d)" % mode)
		assert_true(view.csm.global_transform.is_equal_approx(cabin), "cabin never moved (view %d)" % mode)
		assert_gt(view.earth.position.distance_to(earth), 100.0, "the Earth moved")
		assert_gt(view.moon.position.distance_to(moon), 100.0, "the Moon moved")
		assert_lt(view.sun.global_transform.basis.z.dot(sun), 0.99, "the Sun moved")
		assert_false((view.sky_material.get_shader_parameter("cabin_to_eci") as Basis).is_equal_approx(sky), "the sky turned")


func test_world_directions_follow_the_attitude() -> void:
	var q := _turned() * Quaternion(Vector3(0, 0, 1), deg_to_rad(30.0))
	_render(q)
	var eci_to_cabin := Frames.BODY_TO_GODOT * Basis(q).inverse()
	assert_true(view.eci_to_cabin.is_equal_approx(eci_to_cabin))
	var to_earth := -Vector3(R, 0, 0)
	assert_almost_eq(view.earth.position.normalized(), (eci_to_cabin * to_earth).normalized(), Vector3.ONE * 1e-5)
	var m := Bodies.moon_state(0.0)
	var to_moon := Vector3(m[0], m[1], m[2]) - Vector3(R, 0, 0)
	assert_almost_eq(view.moon.position.normalized(), (eci_to_cabin * to_moon).normalized(), Vector3.ONE * 1e-5)
	# The light shines from the Sun: its +Z axis points at it.
	assert_almost_eq(view.sun.global_transform.basis.z, eci_to_cabin * Bodies.sun_direction(), Vector3.ONE * 1e-5)
	var glow_sun: Vector3 = (view.earth_glow.material_override as ShaderMaterial).get_shader_parameter("sun_dir")
	assert_almost_eq(glow_sun, eci_to_cabin * Bodies.sun_direction(), Vector3.ONE * 1e-5, "the glow is lit from the Sun")
	var sky: Basis = view.sky_material.get_shader_parameter("cabin_to_eci")
	assert_true(sky.is_equal_approx(eci_to_cabin.inverse()), "the stars stay fixed in ECI")
	# Body orientations: the Earth's pole is ECI +Z, the Moon faces the Earth,
	# and the faceted glow sphere keeps its ECI orientation.
	assert_almost_eq(view.earth.basis.orthonormalized() * Vector3(0, 0, 1), eci_to_cabin * Vector3(0, 0, 1), Vector3.ONE * 1e-5)
	var moon_to_earth := (to_earth - to_moon).normalized()
	assert_almost_eq(view.moon.basis.orthonormalized() * Vector3(0, 0, 1), eci_to_cabin * moon_to_earth, Vector3.ONE * 1e-5)
	assert_true(view.earth_glow.basis.orthonormalized().is_equal_approx(eci_to_cabin))


func test_window_camera_looks_out_along_the_nose_with_the_crew_up() -> void:
	view.view_mode = 0
	_render(_turned())
	var cam: Transform3D = view.camera.global_transform
	assert_almost_eq(-cam.basis.z, Frames.BODY_TO_GODOT * Vector3(1, 0, 0), Vector3.ONE * 1e-6, "looks along body +X")
	assert_almost_eq(cam.basis.y, Frames.BODY_TO_GODOT * Vector3(0, 0, -1), Vector3.ONE * 1e-6, "up is the crew's up, body -Z")
	view.look(0.3, 0.1)
	view._process(0.0)
	assert_false(view.camera.global_transform.is_equal_approx(cam), "the crew's own look still turns it")


func test_the_free_lm_is_drawn_where_it_flies_and_turned_as_it_is() -> void:
	var q := _turned()
	var lm: Node3D = view.get("_parts")["lm"]
	Bus.set_value("dyn.config", "csm_lm")
	Bus.set_value("dock.state", "docked")
	_render(q)
	assert_true(lm.visible, "docked, the LM is part of the stack")
	assert_false(view.lm_free.visible)
	var docked := lm.global_transform
	# Undocked in place: the LM's centre of mass a port-to-port span ahead
	# of the CSM's along its +X, turned as it was docked.
	var p := Docking.params()
	var span := float(p["csm_port_m"]) + float(p["lm_port_m"])
	var x := Basis(q) * Vector3.RIGHT
	Bus.set_value("dyn.config", "csm")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "earth")
	Bus.set_value("lm.dyn.r_m", [R + x.x * span, x.y * span, x.z * span])
	Bus.set_value("lm.dyn.att_q", q * Docking.LM_IN_CSM)
	_render(q)
	assert_false(lm.visible)
	assert_true(view.lm_free.visible, "the free LM is drawn")
	assert_true(view.lm_free.global_transform.is_equal_approx(docked), "undocked in place, it is drawn where it was docked")
	# 30 m off in ECI +Z and turned a quarter turn about its own +X.
	Bus.set_value("lm.dyn.r_m", [R + x.x * span, x.y * span, x.z * span + 30.0])
	var ql := q * Docking.LM_IN_CSM * Quaternion(Vector3(1, 0, 0), PI / 2.0)
	Bus.set_value("lm.dyn.att_q", ql)
	_render(q)
	var eci_to_cabin: Basis = view.eci_to_cabin
	var free: Node3D = view.lm_free
	var cg := Frames.BODY_TO_GODOT * Vector3(SpaceView.CSM_PORT_X - float(p["csm_port_m"]), 0, 0)
	var lm_at := Vector3(SpaceView.CSM_PORT_X + float(p["lm_port_m"]), 0, 0)
	var where := cg + eci_to_cabin * (x * span + Vector3(0, 0, 30))
	assert_almost_eq(free.global_transform * lm_at, where, Vector3.ONE * 1e-3, "its centre of mass where it flies")
	var up_axis := free.global_transform.basis * (Basis(Docking.LM_IN_CSM) * Vector3.RIGHT)
	assert_almost_eq(up_axis, eci_to_cabin * (Basis(ql) * Vector3.RIGHT), Vector3.ONE * 1e-5, "its +X turned with it")
	# 5 km away it is drawn nearer, at its apparent size, in front of the Moon.
	Bus.set_value("lm.dyn.r_m", [R, 5000.0, 0.0])
	_render(q)
	var far := eci_to_cabin * Vector3(0, 5000, 0) + cg
	var drawn := free.global_transform * lm_at
	assert_almost_eq(drawn.length(), SpaceView.LM_RENDER_MAX, 1e-2)
	assert_almost_eq(drawn.normalized(), far.normalized(), Vector3.ONE * 1e-5, "in its direction")
	assert_almost_eq(free.global_transform.basis.get_scale().x, SpaceView.LM_RENDER_MAX / far.length(), 1e-5, "scaled to its apparent size")


func test_the_staged_lm_is_drawn_without_its_descent_stage() -> void:
	var q := _turned()
	var p := Docking.params()
	var span := float(p["csm_port_m"]) + float(p["lm_port_m"])
	var x := Basis(q) * Vector3.RIGHT
	Bus.set_value("dyn.config", "csm")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "earth")
	Bus.set_value("lm.dyn.config", "lm")
	Bus.set_value("lm.dyn.r_m", [R + x.x * span, x.y * span, x.z * span])
	Bus.set_value("lm.dyn.att_q", q * Docking.LM_IN_CSM)
	_render(q)
	var free: Node3D = view.lm_free
	var descent: Node3D = free.get_node("Descent")
	assert_true(descent.visible, "the whole LM")
	var port := Vector3(SpaceView.CSM_PORT_X, 0, 0)
	var port_at := free.global_transform * port
	# Staged in place: the ascent stage's centre of mass nearer the port by
	# the difference of the two port distances; the port doesn't move.
	var lift := Docking.lm_port_m("lm") - Docking.lm_port_m("lm_ascent")
	var s := span - lift
	Bus.set_value("lm.dyn.config", "lm_ascent")
	Bus.set_value("lm.dyn.r_m", [R + x.x * s, x.y * s, x.z * s])
	_render(q)
	assert_false(descent.visible, "staged, the descent stage stays behind")
	assert_almost_eq(free.global_transform * port, port_at, Vector3.ONE * 1e-3, "the docking port where it was")
	# Docked again as the ascent stage, the stack's LM is drawn staged too.
	Bus.set_value("dyn.config", "csm_lm")
	Bus.set_value("dock.state", "docked")
	_render(q)
	var docked: Node3D = view.get("_parts")["lm"]
	assert_true(docked.visible)
	assert_false(docked.get_node("Descent").visible, "the docked ascent stage")

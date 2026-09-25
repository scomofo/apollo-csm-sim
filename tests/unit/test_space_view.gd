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


func test_from_the_lm_the_world_turns_with_it_and_the_csm_is_where_it_flies() -> void:
	var q := _turned()
	var p := Docking.params()
	var span := float(p["csm_port_m"]) + float(p["lm_port_m"])
	var x := Basis(q) * Vector3.RIGHT
	# The LM 30 m off its docked place and turned a quarter turn.
	Bus.set_value("dyn.config", "csm")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "earth")
	Bus.set_value("lm.dyn.config", "lm")
	Bus.set_value("lm.dyn.r_m", [R + x.x * span, x.y * span, x.z * span + 30.0])
	Bus.set_value("lm.dyn.v_mps", [0.0, V, 0.0])
	Bus.set_value("lm.dyn.alt_m", 185000.0)
	var ql := q * Docking.LM_IN_CSM * Quaternion(Vector3(1, 0, 0), PI / 2.0)
	Bus.set_value("lm.dyn.att_q", ql)
	view.view_mode = 1
	_render(q)
	var from_csm := _csm_to_lm()
	view.vehicle = "lm"
	_render(q)
	assert_true(view.eci_to_cabin.is_equal_approx(SpaceView.LM_BODY_TO_GODOT * Basis(ql).inverse()),
		"the world turns with the LM")
	var lm_at := Vector3(SpaceView.CSM_PORT_X + float(p["lm_port_m"]), 0, 0)
	assert_almost_eq(view.lm_free.global_transform * lm_at, Vector3.ZERO, Vector3.ONE * 1e-4,
		"the LM's centre of mass at the origin")
	assert_true(_csm_to_lm().is_equal_approx(from_csm),
		"the two vehicles as they are to each other, seen from either")
	assert_true(view.csm.visible and view.lm_free.visible, "both drawn in the chase view")
	assert_almost_eq(view.camera.global_transform.origin.length(), SpaceView.CHASE_DIST, 1e-3,
		"the chase camera around the LM")
	# The window: out of the LM's forward windows (+Z), its +X the crew's up.
	view.view_mode = 0
	view._process(0.0)
	var cam: Transform3D = view.camera.global_transform
	var lm_axes := SpaceView.LM_BODY_TO_GODOT
	assert_almost_eq(-cam.basis.z, lm_axes * Vector3(0, 0, 1), Vector3.ONE * 1e-6,
		"looks along the LM's +Z")
	assert_almost_eq(cam.basis.y, lm_axes * Vector3(1, 0, 0), Vector3.ONE * 1e-6, "up is its +X")
	assert_false(view.lm_free.visible, "from inside it, the LM isn't drawn")
	# Near the surface the chase view gives way to the window's.
	view.view_mode = 1
	Bus.set_value("lm.dyn.alt_m", 10000.0)
	view._process(0.0)
	assert_true(view.camera.global_transform.is_equal_approx(cam), "below 40 km, the window view")


func test_from_eagle_on_the_moon_the_ground_takes_the_spheres_place() -> void:
	# Eagle on its gear at Tranquility Base, below the reference sphere,
	# facing north; Columbia straight overhead.
	var lat := 0.67416
	var lon := 23.47314
	var cm := 3.6
	var site_r := Bodies.R_MOON + Terrain.height(lat, lon) + cm
	var site := Bodies.selenographic_to_fixed(lat, lon, site_r)
	var mf := Bodies.moon_fixed(0.0)
	var r := mf * site
	var up := r.normalized()
	var north := (mf.z - up * up.dot(mf.z)).normalized()
	var csm_r := up * (Bodies.R_MOON + 111000.0)
	Bus.set_value("dyn.primary", "moon")
	Bus.set_value("dyn.r_m", [csm_r.x, csm_r.y, csm_r.z])
	Bus.set_value("dyn.att_q", Quaternion.IDENTITY)
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "moon")
	Bus.set_value("lm.dyn.config", "lm")
	Bus.set_value("lm.dyn.r_m", [r.x, r.y, r.z])
	Bus.set_value("lm.dyn.landed", true)
	Bus.set_value("lm.dyn.landed_pos_m", [site.x, site.y, site.z])
	Bus.set_value("lm.dyn.att_q", Basis(up, north.cross(up), north).get_rotation_quaternion())
	view.vehicle = "lm"
	view.view_mode = 0
	view._process(0.0)
	assert_true(view.moon.visible,
		"the sphere, through the ground below Eagle, until the ground is built")
	assert_false(view.ground.visible)
	var t0 := Time.get_ticks_msec()
	while not view.ground.visible and Time.get_ticks_msec() - t0 < 20000:
		await wait_process_frames(1)
		view._process(0.0)
	assert_true(view.ground.visible, "the ground below Eagle")
	assert_false(view.moon.visible, "in place of the sphere")
	assert_eq(view.camera.global_transform.origin, Vector3.ZERO, "the eye at the centre of mass")
	var s := SpaceView.RENDER_DIST / r.length()
	# The eye's height over the ground below it (site is single precision).
	var n := sqrt(float(site.x) * site.x + float(site.y) * site.y + float(site.z) * site.z)
	var h := Terrain.height(rad_to_deg(asin(site.z / n)), rad_to_deg(atan2(site.y, site.x)))
	var agl := n - Bodies.R_MOON - h
	assert_almost_eq(agl, cm, 0.1)
	var below: Vector3 = view.ground.global_transform * view.ground.points[0]
	assert_almost_eq(below, Vector3(0, -agl * s, 0), Vector3.ONE * 2e-6,
		"the ground below the eye, as high as it is")
	assert_lt(view.camera.near, agl * s, "the near plane short of it")
	var cg := Vector3(SpaceView.CSM_PORT_X - float(Docking.params()["csm_port_m"]), 0, 0)
	var csm_at: Vector3 = view.csm.global_transform * cg
	assert_lt(csm_at.length(), cm * s, "Columbia drawn nearer than the ground")
	assert_gt(csm_at.normalized().y, 0.999, "straight overhead")


func test_from_eagles_cabin_the_ground_and_columbia_are_drawn_outside_it() -> void:
	# Eagle on its gear at Tranquility Base, facing north; Columbia
	# straight overhead. The commander's eye in Eagle's cabin.
	var lat := 0.67416
	var lon := 23.47314
	var cm := Dynamics.lm_cm_height("lm")
	var site := Bodies.selenographic_to_fixed(lat, lon, Bodies.R_MOON + Terrain.height(lat, lon) + cm)
	var mf := Bodies.moon_fixed(0.0)
	var r := mf * site
	var up := r.normalized()
	var north := (mf.z - up * up.dot(mf.z)).normalized()
	var csm_r := up * (Bodies.R_MOON + 111000.0)
	Bus.set_value("dyn.primary", "moon")
	Bus.set_value("dyn.r_m", [csm_r.x, csm_r.y, csm_r.z])
	Bus.set_value("dyn.att_q", Quaternion.IDENTITY)
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dyn.primary", "moon")
	Bus.set_value("lm.dyn.config", "lm")
	Bus.set_value("lm.dyn.r_m", [r.x, r.y, r.z])
	Bus.set_value("lm.dyn.landed", true)
	Bus.set_value("lm.dyn.landed_pos_m", [site.x, site.y, site.z])
	Bus.set_value("lm.dyn.att_q", Basis(up, north.cross(up), north).get_rotation_quaternion())
	var cabin := LmCabin.new()
	add_child_autofree(cabin)
	var eye := Node3D.new()
	add_child_autofree(eye)
	eye.global_position = cabin.anchor.global_position
	view.eye_camera = eye
	view.ground.threaded = false
	view.vehicle = "lm"
	view.view_mode = 2
	view._process(0.0)
	assert_true(view.ground.visible, "the ground below Eagle")
	assert_false(view.moon.visible, "in place of the sphere")
	assert_false(view.lm_free.visible, "inside Eagle, its model isn't drawn")
	assert_eq(view.sun.directional_shadow_max_distance, SpaceView.CABIN_SHADOW_M, "the Sun shadows only the cabin")
	# The eye about 5.5 m above the ground (3.6 m of gear to the centre of
	# mass, 1.9 m on to the eye, and the site's slope between them): the
	# ground drawn below it at the cabin's clearance, beneath its floor.
	var agl := LmCabin.EYE_CDR.x + Docking.lm_port_m("lm") + cm
	assert_almost_eq(SpaceView.CABIN_GROUND_M / view.ground_scale, agl, 0.3, "the scale for the eye's height")
	var below: Vector3 = view.ground.global_transform * view.ground.points[0]
	assert_almost_eq(below, eye.global_position + Vector3(0, -SpaceView.CABIN_GROUND_M, 0), Vector3.ONE * 0.02,
		"straight below the eye, as far down as the cabin allows")
	var floor_y := (cabin.global_transform * Vector3(LmCabin.FLOOR_X, 0, 0)).y
	assert_lt(below.y, floor_y - 0.5, "below the cabin's floor")
	# Columbia overhead, drawn about the eye beyond the cabin's walls.
	var cg := Vector3(SpaceView.CSM_PORT_X - float(Docking.params()["csm_port_m"]), 0, 0)
	var csm_at: Vector3 = view.csm.global_transform * cg - eye.global_position
	assert_almost_eq(csm_at.length(), SpaceView.CABIN_CSM_M, 1e-3, "at the cabin's clearance")
	assert_gt(csm_at.normalized().y, 0.999, "straight overhead")
	# The window view is from the centre of mass, as before.
	view.view_mode = 0
	view._process(0.0)
	var s := SpaceView.RENDER_DIST / r.length()
	assert_almost_eq(view.ground_scale, s, 1e-9, "at the Moon's scale")
	assert_almost_eq(view.ground.global_transform * view.ground.points[0], Vector3(0, -cm * s, 0), Vector3.ONE * 2e-4,
		"below the centre of mass")
	assert_eq(view.sun.directional_shadow_max_distance, SpaceView.SHADOW_M)


## The LM model's placement relative to the CSM model's.
func _csm_to_lm() -> Transform3D:
	return view.csm.global_transform.affine_inverse() * view.lm_free.global_transform

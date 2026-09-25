## 3D presentation: Earth, Moon, Sun and stars around the spacecraft, seen
## out of the CM window or from a chase camera. Presentation only: it reads
## the Bus and never feeds truth back (the same rule as in gemini-capsule,
## https://github.com/scomofo/gemini-capsule).
##
## The spacecraft is the rendering origin and the render axes are the
## cabin's (Frames.BODY_TO_GODOT: the nose is -Z, the crew's up is +Y). The
## cabin, the spacecraft model and the cameras never move with attitude;
## Earth, Moon, Sun and stars turn around them by the inverse of dyn.att_q
## (eci_to_cabin), so a headset camera can be left to the headset
## (docs/ROADMAP.md, slice 2b). Celestial bodies are drawn at a fixed render
## distance with their radius scaled to preserve apparent size, which keeps
## float32 rendering exact from low orbit to translunar distances.
##
## Flying the LM (vehicle "lm", while it flies free) the LM is the origin
## instead, in its own axes (LM_BODY_TO_GODOT: its windows are -Z, its +X
## the crew's up), and the CSM is drawn where it flies. The window view
## looks out of the LM's forward windows from its centre of mass, where
## the bodies' scaled distances are true. Near the Moon the ground below
## the LM (LunarGround, from the height maps) takes the place of the
## Moon's sphere, at the sphere's scale; the camera's near plane comes in
## toward it, and the CSM is drawn nearer than it, so the ground can't
## hide the CSM. Below CHASE_MIN_ALT_M the chase view gives way to the
## window view [simplified: a camera beside the LM would see the scaled
## Moon from far to one side of the LM, and near the surface from inside
## it]. In Eagle's cabin view (src/cabin/lm_cabin.gd) the player's eye
## (eye_camera) is 1 to 2 m from the centre of mass, and the cabin is
## drawn at true scale around it: the ground is drawn about the eye at the
## sphere's scale or, lower down, one that keeps it CABIN_GROUND_M below
## the eye, beneath the cabin's floor, and the CSM about the eye, no
## nearer than CABIN_CSM_M, outside the cabin, and nearer than the ground.
extends Node3D

const RENDER_DIST := 2000.0
const CHASE_DIST := 38.0
## Where the CSM's docking port is in the model (body axes, origin at the
## CM/SM interface): the end of the probe's base.
const CSM_PORT_X := 3.5
## A free LM farther than this is drawn at this distance, scaled to keep
## its apparent size, so it stays in front of the Earth and Moon (and the
## CSM, seen from the LM).
const LM_RENDER_MAX := 1000.0
## The LM's body axes in the render axes: +X (up) is +Y, +Y (right) is +X
## and +Z (forward, out of the windows) is -Z.
const LM_BODY_TO_GODOT: Basis = Frames.LM_BODY_TO_GODOT
## Below this height the LM's chase view gives way to its window view.
const CHASE_MIN_ALT_M := 40000.0
## Below this height the LM's view draws the ground (LunarGround).
const GROUND_MAX_ALT_M := 400000.0
## The camera's near plane, render units (m for the spacecraft), and how
## far in it may come toward the ground below the LM.
const NEAR := 0.05
const NEAR_MIN := 0.0005
## In Eagle's cabin, how near the eye the ground below it may be drawn (m):
## below the floor, 1.6 m under the eye; and how near the CSM may be:
## beyond the cabin's farthest wall, 2.7 m from the eye.
const CABIN_GROUND_M := 2.2
const CABIN_CSM_M := 2.8
## How far from the camera the Sun casts shadows (m): in Eagle's cabin only
## the cabin itself, so its shell, at true scale, casts none on the ground
## drawn at another [simplified: Eagle casts no shadow on the ground].
const SHADOW_M := 100.0
const CABIN_SHADOW_M := 3.0

var camera: Camera3D
var earth: MeshInstance3D
var moon: MeshInstance3D
var earth_glow: MeshInstance3D
var sun: DirectionalLight3D
var csm: Node3D
## The LM while it flies free (the docked LM is part of csm).
var lm_free: Node3D
## The ground below the LM, drawn from it near the Moon.
var ground: LunarGround
## 0 window, 1 chase, 2 cabin: the CM cabin (src/cabin/cm_cabin.gd) is
## drawn in place of the CM, or Eagle's in place of the LM, and the
## player's rig has the camera.
var view_mode: int = 0
## The vehicle the view is from: "csm", or "lm" while it flies free.
var vehicle: String = "csm"
## The player's eye in the cabin view: the rig's camera (main.gd sets it).
var eye_camera: Node3D
## The ground's render scale in the last frame.
var ground_scale: float = 0.0
var look_yaw: float = 0.0
var look_pitch: float = 0.0
var chase_yaw: float = 0.6
var chase_pitch: float = 0.25
## ECI to cabin (render) axes for the current attitude.
var eci_to_cabin: Basis = Frames.BODY_TO_GODOT
## The star sky; its cabin_to_eci uniform keeps the stars fixed in ECI.
var sky_material: ShaderMaterial

var _parts: Dictionary = {}


func _ready() -> void:
	_build_environment()
	earth = _body(Color(0.04, 0.13, 0.36), preload("res://src/presentation/shaders/earth.gdshader"))
	moon = _body(Color(0.42, 0.41, 0.4), preload("res://src/presentation/shaders/moon.gdshader"))
	earth_glow = MeshInstance3D.new()
	var gm := SphereMesh.new()
	gm.radius = 1.0
	gm.height = 2.0
	earth_glow.mesh = gm
	var glow := ShaderMaterial.new()
	glow.shader = preload("res://src/presentation/shaders/atmosphere.gdshader")
	earth_glow.material_override = glow
	add_child(earth_glow)
	csm = _build_csm()
	add_child(csm)
	lm_free = _build_lm()
	lm_free.visible = false
	add_child(lm_free)
	ground = LunarGround.new()
	add_child(ground)
	camera = Camera3D.new()
	camera.near = NEAR
	camera.far = RENDER_DIST * 3.0
	camera.fov = 60.0
	add_child(camera)
	camera.make_current()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky_material = ShaderMaterial.new()
	sky_material.shader = preload("res://src/presentation/shaders/stars.gdshader")
	sky.sky_material = sky_material
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.16, 0.16, 0.18)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	add_child(sun)


func _body(base: Color, shader: Shader) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = 96
	m.rings = 48
	mi.mesh = m
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", base)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


# --- spacecraft model ---------------------------------------------------------

func _mat(c: Color, metal: float = 0.6, rough: float = 0.35, emissive: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


## A cylinder/cone along body +X from [param x0] to [param x1].
func _along_x(parent: Node3D, r0: float, r1: float, x0: float, x1: float, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = absf(x1 - x0)
	cm.radial_segments = 48
	mi.mesh = cm
	mi.material_override = mat
	# CylinderMesh is along +Y; rotate so +Y maps to +X.
	mi.transform = Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3((x0 + x1) / 2.0, 0, 0))
	parent.add_child(mi)
	return mi


## Body frame: +X toward the CM apex (SPS thrust), the model origin at the
## CM/SM interface. Dimensions from the Apollo CSM [published, rounded].
func _build_csm() -> Node3D:
	var root := Node3D.new()
	var silver := _mat(Color(0.85, 0.86, 0.88), 0.35, 0.35)
	var white := _mat(Color(0.92, 0.92, 0.9), 0.1, 0.6)
	var dark := _mat(Color(0.15, 0.15, 0.16), 0.5, 0.5)
	var cm := Node3D.new()
	root.add_child(cm)
	_along_x(cm, 1.956, 0.4, 0.0, 3.2, silver)          # CM cone
	_along_x(cm, 0.4, 0.35, 3.2, 3.5, dark)             # docking probe base
	_along_x(cm, 1.97, 1.956, -0.25, 0.0, dark)         # heat-shield edge
	_parts["cm"] = cm
	var sm := Node3D.new()
	root.add_child(sm)
	_along_x(sm, 1.956, 1.956, -7.5, -0.25, silver)     # SM cylinder
	_along_x(sm, 1.25, 0.55, -10.3, -7.5, dark)         # SPS nozzle
	for i in 4:
		var q := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = Vector3(0.9, 0.35, 0.6)
		q.mesh = b
		q.material_override = white
		var ang := i * PI / 2.0 + PI / 4.0
		q.position = Vector3(-2.0, cos(ang) * 2.05, sin(ang) * 2.05)
		q.rotation = Vector3(ang, 0, 0)
		sm.add_child(q)
	var hga := MeshInstance3D.new()
	var d := CylinderMesh.new()
	d.top_radius = 0.0
	d.bottom_radius = 0.5
	d.height = 0.3
	hga.mesh = d
	hga.material_override = white
	hga.position = Vector3(-7.9, -2.9, 0)
	sm.add_child(hga)
	_parts["sm"] = sm
	var plume := _along_x(sm, 1.2, 4.0, -10.3, -22.0, _mat(Color(1.0, 0.75, 0.45, 0.45), 0.0, 1.0, 3.0))
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_parts["plume"] = plume
	var lm := _build_lm()
	root.add_child(lm)
	_parts["lm"] = lm
	# S-IVB and adapter behind the SM, for the launch stack.
	var sivb := Node3D.new()
	root.add_child(sivb)
	_along_x(sivb, 3.3, 1.956, -16.0, -7.5, white)
	_along_x(sivb, 3.3, 3.3, -33.8, -16.0, white)
	_parts["sivb"] = sivb
	_parts["main_chutes"] = _chutes(root, 3, 8.0, 18.0, Color(1.0, 0.45, 0.2))
	_parts["drogues"] = _chutes(root, 2, 2.5, 30.0, Color(1.0, 1.0, 1.0))
	return root


## The LM, simplified, as it sits docked ahead of the CM apex: in the CSM
## model's axes. Its descent stage is the child "Descent".
func _build_lm() -> Node3D:
	var lm := Node3D.new()
	var asc := MeshInstance3D.new()
	var ab := BoxMesh.new()
	ab.size = Vector3(2.8, 4.0, 4.0)
	asc.mesh = ab
	asc.material_override = _mat(Color(0.7, 0.7, 0.68), 0.5, 0.6)
	asc.position = Vector3(5.0, 0, 0)
	lm.add_child(asc)
	var desc := MeshInstance3D.new()
	var db := BoxMesh.new()
	db.size = Vector3(1.7, 4.2, 4.2)
	desc.mesh = db
	desc.material_override = _mat(Color(0.85, 0.65, 0.25), 0.9, 0.35)
	desc.position = Vector3(7.3, 0, 0)
	desc.name = "Descent"
	lm.add_child(desc)
	return lm


## The docked LM's body axes and centre of mass in the CSM model's axes,
## for its configuration [param cfg] (the ascent stage's, staged).
func _lm_docked(cfg: String = "lm") -> Transform3D:
	return Transform3D(Basis(Docking.LM_IN_CSM), Vector3(CSM_PORT_X + Docking.lm_port_m(cfg), 0, 0))


## Place the free LM where it flies relative to the CSM, and turned as it
## is, in the cabin's axes.
func _place_lm_free(q: Quaternion) -> void:
	var r: Array = Bus.get_value("dyn.r_m", [0.0, 0.0, 0.0])
	var rl: Array = Bus.get_value("lm.dyn.r_m", r)
	var rel := Vector3(rl[0] - r[0], rl[1] - r[1], rl[2] - r[2])
	var primary := str(Bus.get_value("dyn.primary", "earth"))
	if str(Bus.get_value("lm.dyn.primary", primary)) != primary:
		# One is relative to the Earth, the other to the Moon.
		var m := Bodies.moon_state(float(Bus.get_value("time.get_s", 0.0)))
		rel += Vector3(m[0], m[1], m[2]) * (1.0 if primary == "earth" else -1.0)
	var cg := Frames.BODY_TO_GODOT * Vector3(CSM_PORT_X - float(Docking.params()["csm_port_m"]), 0, 0)
	var at := cg + eci_to_cabin * rel
	var ql: Quaternion = Bus.get_value("lm.dyn.att_q", q)
	var turn := eci_to_cabin * Basis(ql)
	var d := at.length()
	if d > LM_RENDER_MAX:
		turn = turn.scaled(Vector3.ONE * (LM_RENDER_MAX / d))
		at *= LM_RENDER_MAX / d
	lm_free.transform = Transform3D(turn, at) * _lm_docked(str(Bus.get_value("lm.dyn.config", "lm"))).affine_inverse()


## Seen from the free LM: the CSM where it flies relative to the LM, and
## turned as it is, in the render axes. Farther than [param far] from
## [param eye] it is drawn at that distance from it, scaled to keep its
## apparent size.
func _place_csm_from_lm(far: float, eye: Vector3 = Vector3.ZERO) -> void:
	var r: Array = Bus.get_value("dyn.r_m", [0.0, 0.0, 0.0])
	var rl: Array = Bus.get_value("lm.dyn.r_m", r)
	var rel := Vector3(r[0] - rl[0], r[1] - rl[1], r[2] - rl[2])
	var primary := str(Bus.get_value("lm.dyn.primary", "moon"))
	if str(Bus.get_value("dyn.primary", primary)) != primary:
		var m := Bodies.moon_state(float(Bus.get_value("time.get_s", 0.0)))
		rel += Vector3(m[0], m[1], m[2]) * (1.0 if primary == "earth" else -1.0)
	var at := eci_to_cabin * rel - eye
	var turn := eci_to_cabin * Basis(Bus.get_value("dyn.att_q", Quaternion.IDENTITY) as Quaternion)
	var d := at.length()
	if d > far:
		turn = turn.scaled(Vector3.ONE * (far / d))
		at *= far / d
	# The model's origin is the CM/SM interface; the centre of mass is along
	# +X from it.
	var cg := Vector3(CSM_PORT_X - float(Docking.params()["csm_port_m"]), 0, 0)
	csm.transform = Transform3D(turn, eye + at) * Transform3D(Basis.IDENTITY, -cg)


func _chutes(parent: Node3D, n: int, r: float, dist: float, c: Color) -> Node3D:
	var g := Node3D.new()
	parent.add_child(g)
	for i in n:
		var ang := TAU * i / n
		var mi := MeshInstance3D.new()
		var s := SphereMesh.new()
		s.radius = r
		s.height = r
		s.is_hemisphere = true
		mi.mesh = s
		mi.material_override = _mat(c, 0.0, 0.9)
		mi.transform = Transform3D(Basis(Vector3(0, 0, 1), -PI / 2.0), Vector3(dist, cos(ang) * r * 0.9, sin(ang) * r * 0.9))
		g.add_child(mi)
	g.visible = false
	return g


# --- per frame -----------------------------------------------------------------

func _process(_delta: float) -> void:
	# The vehicle the view is from: its position, attitude and axes.
	var from_lm := vehicle == "lm" and str(Bus.get_value("dock.state", "")) == "free"
	var p := "lm." if from_lm else ""
	var primary := str(Bus.get_value(p + "dyn.primary", "earth"))
	var r: Array = Bus.get_value(p + "dyn.r_m", [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
	var t := float(Bus.get_value("time.get_s", 0.0))
	var rel := Vector3(r[0], r[1], r[2])
	var m := Bodies.moon_state(t)
	var moon_pos := Vector3(m[0], m[1], m[2])
	# Positions of the bodies relative to the spacecraft (ECI axes).
	var to_earth: Vector3
	var to_moon: Vector3
	if primary == "moon":
		to_moon = -rel
		to_earth = -rel - moon_pos
	else:
		to_earth = -rel
		to_moon = moon_pos - rel
	# The world turns around the fixed cabin: body axes are the cabin axes,
	# so an ECI vector is taken into the body frame and then to Godot axes.
	var q: Quaternion = Bus.get_value(p + "dyn.att_q", Quaternion.IDENTITY)
	var body := LM_BODY_TO_GODOT if from_lm else Frames.BODY_TO_GODOT
	eci_to_cabin = body * Basis(q).inverse()
	_place(earth, eci_to_cabin * to_earth, Bodies.R_EARTH)
	_place(earth_glow, eci_to_cabin * to_earth, Bodies.R_EARTH * 1.025)
	# In Eagle's cabin the eye is the player's, off the centre of mass.
	var cabin_view := from_lm and view_mode == 2
	var eye_at := eye_camera.global_position if cabin_view and eye_camera != null else Vector3.ZERO
	sun.directional_shadow_max_distance = CABIN_SHADOW_M if cabin_view else SHADOW_M
	# From the LM near the Moon: the eye's height over the ground below it,
	# the sphere through that ground, and the ground itself in its place.
	var near_moon := from_lm and primary == "moon"
	var agl := INF
	var s_moon := RENDER_DIST / to_moon.length()
	var drawn := false
	ground_scale = s_moon
	if near_moon:
		var mf_to_view := eci_to_cabin * Bodies.moon_fixed(t)
		var eye := LunarGround.lm_moon_fixed()
		var off := mf_to_view.inverse() * eye_at
		eye = PackedFloat64Array([eye[0] + off.x, eye[1] + off.y, eye[2] + off.z])
		agl = LunarGround.height_over_ground(eye)
		var ground_r := sqrt(eye[0] * eye[0] + eye[1] * eye[1] + eye[2] * eye[2]) - agl
		_place(moon, eci_to_cabin * to_moon, ground_r)
		if cabin_view:
			ground_scale = maxf(s_moon, CABIN_GROUND_M / maxf(agl, 1.0))
			# Low down, the sphere at its scale would come into the cabin.
			if agl * s_moon < CABIN_GROUND_M:
				moon.visible = false
		drawn = agl < GROUND_MAX_ALT_M and ground.follow(eye, agl, mf_to_view, ground_scale, eye_at)
	else:
		_place(moon, eci_to_cabin * to_moon, Bodies.R_MOON)
	ground.visible = drawn
	if drawn:
		moon.visible = false
	camera.near = clampf(0.3 * agl * s_moon, NEAR_MIN, NEAR) if near_moon else NEAR
	# The glow is a sphere, but a faceted one seen from close by: it keeps
	# its ECI orientation, as the Earth and Moon do, so its silhouette turns
	# with the world instead of staying fixed to the cabin.
	earth_glow.basis = eci_to_cabin.scaled(Vector3.ONE * earth_glow.scale.x)
	# Earth spins (Greenwich sidereal time); the Moon turns with its
	# Moon-fixed frame, a face to Earth. The mesh's +Z is the Moon's 0° N,
	# 0° E, its +Y the north pole and its +X 90° E.
	var jd := SimClock.julian_date()
	var gmst := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360.0))
	earth.basis = (eci_to_cabin * Basis(Vector3(0, 0, 1), gmst)).scaled(Vector3.ONE * earth.scale.x)
	var mf := Bodies.moon_fixed(t)
	moon.basis = (eci_to_cabin * Basis(mf.y, mf.z, mf.x)).scaled(Vector3.ONE * moon.scale.x)
	var sd := Bodies.sun_direction()
	sun.basis = eci_to_cabin * Basis.looking_at(-sd, Vector3(0, 0, 1) if absf(sd.z) < 0.99 else Vector3(1, 0, 0))
	(earth_glow.material_override as ShaderMaterial).set_shader_parameter("sun_dir", eci_to_cabin * sd)
	sky_material.set_shader_parameter("cabin_to_eci", eci_to_cabin.inverse())
	# Spacecraft: the one the view is from fixed, in its body axes.
	csm.transform = Transform3D(body, Vector3.ZERO)
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	_parts["sm"].visible = cfg != "cm"
	_parts["lm"].visible = cfg == "csm_lm"
	var staged := str(Bus.get_value("lm.dyn.config", "lm")) == "lm_ascent"
	_parts["lm"].get_node("Descent").visible = not staged
	lm_free.get_node("Descent").visible = not staged
	lm_free.visible = str(Bus.get_value("dock.state", "")) == "free"
	if from_lm:
		var far := LM_RENDER_MAX
		if cabin_view:
			far = clampf(0.5 * agl * ground_scale, CABIN_CSM_M, LM_RENDER_MAX) if near_moon else LM_RENDER_MAX
		elif near_moon:
			far = clampf(0.5 * agl * s_moon, 2.0 * camera.near, LM_RENDER_MAX)
		_place_csm_from_lm(far, eye_at)
		var lm_cfg := str(Bus.get_value("lm.dyn.config", "lm"))
		lm_free.transform = Transform3D(body, Vector3.ZERO) * _lm_docked(lm_cfg).affine_inverse()
	elif lm_free.visible:
		_place_lm_free(q)
	_parts["sivb"].visible = cfg == "stack"
	_parts["plume"].visible = float(Bus.get_value("sps.thrust_n", 0.0)) > 1000.0 or float(Bus.get_value("sivb.thrust_n", 0.0)) > 0.0
	_parts["plume"].scale = Vector3.ONE * clampf(float(Bus.get_value("sps.chamber_pct", 100.0)) / 100.0, 0.2, 1.0)
	_parts["drogues"].visible = bool(Bus.get_value("els.drogue", false))
	_parts["main_chutes"].visible = bool(Bus.get_value("els.mains", false))
	_parts["main_chutes"].scale = Vector3.ONE * lerpf(0.3, 1.0, float(Bus.get_value("els.main_fraction", 1.0)))
	_parts["cm"].visible = view_mode != 2 or from_lm
	# Camera, in body axes too, so only the crew's own look turns it.
	if cabin_view:
		# Inside Eagle: its cabin in place of its model, the rig's camera.
		csm.visible = true
		lm_free.visible = false
	elif from_lm:
		_lm_camera(body)
	elif view_mode == 2:
		csm.visible = true
	elif view_mode == 0:
		csm.visible = false
		# Looking out along +X (the rendezvous window line of sight),
		# crew "up" = body -Z, with free head turn.
		var fwd := body * Vector3(1, 0, 0)
		var up := body * Vector3(0, 0, -1)
		var right := fwd.cross(up).normalized()
		var b := Basis(right, up, -fwd)
		b = b * Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch)
		camera.transform = Transform3D(b, fwd * 3.6)
	else:
		csm.visible = true
		var up := body * Vector3(0, 0, -1)
		var off := body * (Basis(Vector3(0, 0, 1), chase_yaw) * Basis(Vector3(0, 1, 0), -chase_pitch) * Vector3(-1, 0, 0))
		var dist := CHASE_DIST * (2.2 if cfg == "stack" else 1.0)
		camera.transform = Transform3D(Basis.IDENTITY, off * dist).looking_at(Vector3.ZERO, up)


## The camera from the LM: its forward windows, or, above
## CHASE_MIN_ALT_M, the chase view around it.
func _lm_camera(body: Basis) -> void:
	csm.visible = true
	var up := body * Vector3(1, 0, 0)
	var fwd := body * Vector3(0, 0, 1)
	if view_mode == 1 and float(Bus.get_value("lm.dyn.alt_m", 0.0)) >= CHASE_MIN_ALT_M:
		var around := Basis(Vector3(1, 0, 0), chase_yaw) * Basis(Vector3(0, 1, 0), chase_pitch)
		var off := body * (around * Vector3(0, 0, -1))
		camera.transform = Transform3D(Basis.IDENTITY, off * CHASE_DIST) \
			.looking_at(Vector3.ZERO, up)
		return
	# Out of the forward windows, from the centre of mass, with free head
	# turn.
	lm_free.visible = false
	var right := fwd.cross(up).normalized()
	var b := Basis(right, up, -fwd) * Basis(Vector3.UP, look_yaw) * Basis(Vector3.RIGHT, look_pitch)
	camera.transform = Transform3D(b, Vector3.ZERO)


func _place(mi: MeshInstance3D, offset: Vector3, radius: float) -> void:
	var d := offset.length()
	if d <= radius * 1.0000001:
		mi.visible = false
		return
	mi.visible = true
	var s := RENDER_DIST / d
	mi.position = offset.normalized() * RENDER_DIST
	mi.scale = Vector3.ONE * radius * s


func look(dx: float, dy: float) -> void:
	if view_mode == 2:
		return
	if view_mode == 0:
		look_yaw = clampf(look_yaw - dx, -PI * 0.6, PI * 0.6)
		look_pitch = clampf(look_pitch - dy, -1.2, 1.2)
	else:
		chase_yaw -= dx
		chase_pitch = clampf(chase_pitch + dy, -1.4, 1.4)

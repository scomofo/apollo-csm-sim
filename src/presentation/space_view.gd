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
extends Node3D

const RENDER_DIST := 2000.0
const CHASE_DIST := 38.0

var camera: Camera3D
var earth: MeshInstance3D
var moon: MeshInstance3D
var earth_glow: MeshInstance3D
var sun: DirectionalLight3D
var csm: Node3D
var view_mode: int = 0   # 0 window, 1 chase
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
	camera = Camera3D.new()
	camera.near = 0.05
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
	var gold := _mat(Color(0.85, 0.65, 0.25), 0.9, 0.35)
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
	# Docked LM (ahead of the CM apex), simplified.
	var lm := Node3D.new()
	root.add_child(lm)
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
	desc.material_override = gold
	desc.position = Vector3(7.3, 0, 0)
	lm.add_child(desc)
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
	var primary := str(Bus.get_value("dyn.primary", "earth"))
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
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
	var q: Quaternion = Bus.get_value("dyn.att_q", Quaternion.IDENTITY)
	eci_to_cabin = Frames.BODY_TO_GODOT * Basis(q).inverse()
	_place(earth, eci_to_cabin * to_earth, Bodies.R_EARTH)
	_place(earth_glow, eci_to_cabin * to_earth, Bodies.R_EARTH * 1.025)
	_place(moon, eci_to_cabin * to_moon, Bodies.R_MOON)
	# The glow is a sphere, but a faceted one seen from close by: it keeps
	# its ECI orientation, as the Earth and Moon do, so its silhouette turns
	# with the world instead of staying fixed to the cabin.
	earth_glow.basis = eci_to_cabin.scaled(Vector3.ONE * earth_glow.scale.x)
	# Earth spins (Greenwich sidereal time); the Moon keeps a face to Earth.
	var jd := SimClock.julian_date()
	var gmst := deg_to_rad(fposmod(280.46061837 + 360.98564736629 * (jd - 2451545.0), 360.0))
	earth.basis = (eci_to_cabin * Basis(Vector3(0, 0, 1), gmst)).scaled(Vector3.ONE * earth.scale.x)
	var to_e := (to_earth - to_moon).normalized()
	moon.basis = (eci_to_cabin * Basis.looking_at(-to_e, Bodies.moon_normal())).scaled(Vector3.ONE * moon.scale.x)
	var sd := Bodies.sun_direction()
	sun.basis = eci_to_cabin * Basis.looking_at(-sd, Vector3(0, 0, 1) if absf(sd.z) < 0.99 else Vector3(1, 0, 0))
	(earth_glow.material_override as ShaderMaterial).set_shader_parameter("sun_dir", eci_to_cabin * sd)
	sky_material.set_shader_parameter("cabin_to_eci", eci_to_cabin.inverse())
	# Spacecraft: fixed, in body axes.
	var body := Frames.BODY_TO_GODOT
	csm.basis = body
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	_parts["sm"].visible = cfg != "cm"
	_parts["lm"].visible = cfg == "csm_lm"
	_parts["sivb"].visible = cfg == "stack"
	_parts["plume"].visible = float(Bus.get_value("sps.thrust_n", 0.0)) > 1000.0 or float(Bus.get_value("sivb.thrust_n", 0.0)) > 0.0
	_parts["plume"].scale = Vector3.ONE * clampf(float(Bus.get_value("sps.chamber_pct", 100.0)) / 100.0, 0.2, 1.0)
	_parts["drogues"].visible = bool(Bus.get_value("els.drogue", false))
	_parts["main_chutes"].visible = bool(Bus.get_value("els.mains", false))
	_parts["main_chutes"].scale = Vector3.ONE * lerpf(0.3, 1.0, float(Bus.get_value("els.main_fraction", 1.0)))
	# Camera, in body axes too, so only the crew's own look turns it.
	if view_mode == 0:
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


func _place(mi: MeshInstance3D, offset: Vector3, radius: float) -> void:
	var d := offset.length()
	if d <= radius * 1.0000001:
		mi.visible = false
		return
	mi.visible = true
	var s := RENDER_DIST / d
	mi.position = offset.normalized() * RENDER_DIST
	mi.scale = Vector3.ONE * radius * s


func toggle_view() -> void:
	view_mode = 1 - view_mode


func look(dx: float, dy: float) -> void:
	if view_mode == 0:
		look_yaw = clampf(look_yaw - dx, -PI * 0.6, PI * 0.6)
		look_pitch = clampf(look_pitch - dy, -1.2, 1.2)
	else:
		chase_yaw -= dx
		chase_pitch = clampf(chase_pitch + dy, -1.4, 1.4)

## Comfort aids (docs/VR_INTERACTION.md §4): a vignette that narrows the
## view at high body rates and in entry deceleration, and an optional
## horizon ring level with the local horizontal. Each can be switched off,
## and authentic mode turns them all off; none of them ever moves the
## camera. It rides on the player's camera.
## Adapted from gemini-capsule's src/presentation/comfort.gd at 40e449c
## (README.md lists the port): the body rate comes from dyn.omega, entry
## from dyn.g_load and the horizon from guid.indicator.lvlh, in place of
## Gemini's guid.rate.*, dynamic pressure and guid.att.lvlh. In Eagle
## ([member vehicle] "lm") they are Eagle's: lm.dyn.omega and the LGC's
## lm.guid.indicator.lvlh, with no entry. Presentation only.
##
## Reads:  dyn.omega, dyn.g_load, guid.indicator.lvlh, or in Eagle
##         lm.dyn.omega, lm.guid.indicator.lvlh
## Writes: present.comfort.vignette (0..1), present.comfort.horizon (bool),
##         present.comfort.authentic (bool)
class_name Comfort
extends Node3D

## The vignette starts at this body rate (deg/s) and is full at
## vignette_full_deg_s [estimated]: above the CMC's 2 deg/s hold rate, so
## ordinary maneuvers leave the view alone.
@export var vignette_start_deg_s: float = 3.0
@export var vignette_full_deg_s: float = 12.0
## Entry deceleration narrows the view from entry_start_g, to 60 % at
## entry_full_g [estimated]; Apollo 11's entry peaked near 6.5 g.
@export var entry_start_g: float = 2.0
@export var entry_full_g: float = 6.0
@export var vignette_enabled: bool = true
## Horizon ring, an inauthentic aid: off by default.
@export var horizon_aid: bool = false
## Authentic mode turns every aid off whatever the settings above say.
@export var authentic: bool = false
## The vehicle flown: "csm" or "lm".
var vehicle: String = "csm"

var vignette: float = 0.0
var _quad: MeshInstance3D
var _mat: ShaderMaterial
var _ring: MeshInstance3D


func _ready() -> void:
	# Full-screen quad just in front of the camera with a radial fade.
	_quad = MeshInstance3D.new()
	_quad.name = "Vignette"
	var qm := QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	_quad.mesh = qm
	_quad.position = Vector3(0, 0, -0.3)
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_mix, depth_test_disabled, cull_disabled, depth_draw_never;
uniform float amount = 0.0;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = smoothstep(1.2 - amount, 1.6 - amount, r) * amount;
	ALBEDO = vec3(0.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.visible = false
	add_child(_quad)
	# A 1 m ring round the head; its axis is the local vertical.
	_ring = MeshInstance3D.new()
	_ring.name = "HorizonRing"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.98
	tm.outer_radius = 1.0
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.4, 0.9, 0.5, 0.5)
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = rm
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.visible = false
	add_child(_ring)


func _process(_delta: float) -> void:
	update_from_bus()


## Pure update, so tests can drive it without frames.
func update_from_bus() -> void:
	var p := "lm." if vehicle == "lm" else ""
	var omega: Vector3 = Bus.get_value(p + "dyn.omega", Vector3.ZERO)
	var rate := rad_to_deg(omega.length())
	var v := clampf(inverse_lerp(vignette_start_deg_s, vignette_full_deg_s, rate), 0.0, 1.0)
	if vehicle != "lm":
		var g := float(Bus.get_value("dyn.g_load", 0.0))
		v = maxf(v, clampf(inverse_lerp(entry_start_g, entry_full_g, g), 0.0, 1.0) * 0.6)
	if authentic or not vignette_enabled:
		v = 0.0
	vignette = v
	_mat.set_shader_parameter("amount", v)
	_quad.visible = v > 0.01
	var horizon := horizon_aid and not authentic
	_ring.visible = horizon
	if horizon:
		# guid.indicator.lvlh turns LVLH-aligned body axes into the actual
		# ones; taken from the vehicle's level attitude (Frames.level_turn),
		# its inverse in render axes is the LVLH frame seen from the cabin.
		# The ring's axis is render +Y: the local up.
		var q = Bus.get_value(p + "guid.indicator.lvlh", null)
		if q is Quaternion:
			_ring.global_basis = Frames.level_turn(q as Quaternion, vehicle).inverse()
	Bus.set_value("present.comfort.vignette", v)
	Bus.set_value("present.comfort.horizon", horizon)
	Bus.set_value("present.comfort.authentic", authentic)

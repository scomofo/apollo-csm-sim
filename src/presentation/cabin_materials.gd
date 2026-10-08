## Shared cabin materials: one instance per role, and one line per role
## saying what the look is based on. The interface is gemini-capsule's
## CabinMaterials
## (https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/cabin_materials.gd),
## so the control and instrument prefabs taken from it work unchanged.
## The prefabs use "bezel"; the CM and LM cabins (src/cabin/) and their
## DSKYs use the rest, Eagle's in the CM's looks until its own are sourced.
## The values deliberately avoid perfectly flat colours: at cabin scale the
## difference between painted aluminium, anodised hardware and rubber is read
## mostly through roughness and specular response.  These are still procedural
## approximations (there are no scanned Apollo texture maps in the project).
class_name CabinMaterials
extends RefCounted

## Role -> {basis, confidence}.
const PROVENANCE := {
	"bezel": {"basis": "Satin dark-grey lamp and gauge bezels, kept from gemini-capsule until the CM panels are sourced", "confidence": "estimated"},
	"wall": {"basis": "Off-white cabin walls: a general impression of the CM interior, not yet matched to photographs", "confidence": "estimated"},
	"bulkhead": {"basis": "Light grey aft and forward bulkheads and tunnel: a general impression, not yet matched to photographs", "confidence": "estimated"},
	"panel_face": {"basis": "Medium-grey main display console faces with light legends: a general impression, not yet matched to photographs", "confidence": "estimated"},
	"couch": {"basis": "Pale couch pads: a general impression, not yet matched to photographs", "confidence": "estimated"},
	"dsky_case": {"basis": "Dark grey DSKY case and keys: a general impression, not yet matched to photographs", "confidence": "estimated"},
	"lpd": {"basis": "Landing point designator marks on the commander's window, drawn bright red-orange so they read against the ground; the flown scale's colour is not sourced", "confidence": "estimated"},
	"panel_edge": {"basis": "Dark edge reveal between removable MDC panels", "confidence": "estimated"},
	"fastener": {"basis": "Dull stainless panel fasteners", "confidence": "estimated"},
	"window_frame": {"basis": "Aluminium window frame: NASA TN D-6721 pp. 3-4; finish and dimensions estimated", "confidence": "estimated"},
	"window_seal": {"basis": "NASA TN D-6721 p. 4: black silicone over visible insulation for antiglare; roughness and colour estimated", "confidence": "estimated"},
	"couch_frame": {"basis": "Tubular metal couch structure", "confidence": "estimated"},
}

static var _cache: Dictionary = {}


static func get_material(role: String) -> Material:
	if not _cache.has(role):
		_cache[role] = _built(role)
	return _cache[role]


static func roles() -> Array:
	return PROVENANCE.keys()


static func _built(role: String) -> Material:
	match role:
		"bezel":
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.15, 0.16, 0.18)
			m.roughness = 0.38
			m.metallic = 0.5
			return m
		"wall":
			return _plain(Color(0.74, 0.73, 0.68), 0.88, true)
		"bulkhead":
			return _plain(Color(0.58, 0.59, 0.58), 0.65, true)
		"panel_face":
			return _metal(Color(0.25, 0.26, 0.27), 0.20, 0.55)
		"couch":
			return _plain(Color(0.88, 0.86, 0.80), 0.85)
		"dsky_case":
			return _plain(Color(0.16, 0.17, 0.18), 0.45)
		"panel_edge":
			return _plain(Color(0.025, 0.028, 0.03), 0.80)
		"fastener":
			return _metal(Color(0.52, 0.53, 0.52), 0.80, 0.22)
		"window_frame":
			var m := _metal(Color(0.55, 0.56, 0.54), 0.75, 0.28)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"window_seal":
			return _plain(Color(0.012, 0.014, 0.015), 0.98, true)
		"couch_frame":
			return _metal(Color(0.40, 0.41, 0.40), 0.70, 0.30)
		"lpd":
			var m := StandardMaterial3D.new()
			m.albedo_color = lpd_colour()
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			return m
	# Unknown role: magenta, obvious in any capture.
	var unknown := StandardMaterial3D.new()
	unknown.albedo_color = Color(1, 0, 1)
	return unknown


## Surfaces of revolution are seen from inside the cabin, so the vessel's
## roles draw both sides (Godot lights a back face with its normal flipped).
static func _plain(c: Color, roughness: float, both_sides: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = roughness
	if both_sides:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func _metal(c: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var m := _plain(c, roughness)
	m.metallic = metallic
	return m


## Lettering colour for panel labels and instrument scales [estimated].
static func lettering_colour() -> Color:
	return Color(0.96, 0.94, 0.88)


## The landing point designator's marks and figures [estimated].
static func lpd_colour() -> Color:
	return Color(1.0, 0.42, 0.22)

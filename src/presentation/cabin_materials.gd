## Shared cabin materials: one instance per role, and one line per role
## saying what the look is based on. The interface is gemini-capsule's
## CabinMaterials
## (https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/cabin_materials.gd),
## so the control and instrument prefabs taken from it work unchanged.
## Only the roles those prefabs use exist yet; the CM cabin adds its own
## (docs/ROADMAP.md, slice 2c). Every look here is [estimated].
class_name CabinMaterials
extends RefCounted

## Role -> {basis, confidence}.
const PROVENANCE := {
	"bezel": {"basis": "Satin dark-grey lamp and gauge bezels, kept from gemini-capsule until the CM panels are sourced", "confidence": "estimated"},
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
			m.albedo_color = Color(0.18, 0.18, 0.2)
			m.roughness = 0.45
			m.metallic = 0.4
			return m
	# Unknown role: magenta, obvious in any capture.
	var unknown := StandardMaterial3D.new()
	unknown.albedo_color = Color(1, 0, 1)
	return unknown


## Lettering colour for panel labels and instrument scales [estimated].
static func lettering_colour() -> Color:
	return Color(0.96, 0.94, 0.88)

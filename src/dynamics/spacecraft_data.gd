## Loads data/spacecraft.json once and answers mass and inertia questions
## per vehicle configuration. The CSM's configurations, in flight order:
##   stack   S-IVB + CSM + LM (parking orbit and TLI; the IU flies it)
##   csm_lm  CSM docked to the LM (after transposition and docking)
##   csm     CSM alone (after undocking or LM jettison)
##   cm      Command Module alone (after CM/SM separation)
## and the LM's, while it flies free of the CSM:
##   lm      the whole LM, as it undocks [simplified: its mass stays the
##           docked LM's until slice 3b gives it propellant]
class_name SpacecraftData
extends RefCounted

const PATH := "res://data/spacecraft.json"
const CONFIGS := ["stack", "csm_lm", "csm", "cm"]

static var _data: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		assert(f != null, "cannot open " + PATH)
		_data = JSON.parse_string(f.get_as_text())
	return _data


static func section(name: String) -> Dictionary:
	return data()[name]


static func config(name: String) -> Dictionary:
	return data()["configurations"][name]


## Total mass for [param cfg] given the propellant loads (kg).
static func total_mass(cfg: String, sps_kg: float, sm_rcs_kg: float, cm_rcs_kg: float, sivb_kg: float) -> float:
	var m: Dictionary = data()["mass"]
	var cm := float(m["cm_dry_kg"]) + cm_rcs_kg
	if cfg == "cm":
		return cm
	var csm := cm + float(m["sm_dry_kg"]) + sm_rcs_kg + sps_kg
	if cfg == "csm":
		return csm
	var csm_lm := csm + float(m["lm_kg"])
	if cfg == "csm_lm":
		return csm_lm
	return csm_lm + float(m["sivb_dry_kg"]) + sivb_kg


## The LM's mass, docked or free, kg.
static func lm_mass() -> float:
	return float(data()["mass"]["lm_kg"])


## Principal inertia scaled linearly with mass from the configuration's
## reference [estimated].
static func inertia(cfg: String, mass: float) -> Vector3:
	var c := config(cfg)
	var i: Array = c["inertia"]
	var k := mass / float(c["ref_mass_kg"])
	return Vector3(float(i[0]), float(i[1]), float(i[2])) * clampf(k, 0.3, 2.0)

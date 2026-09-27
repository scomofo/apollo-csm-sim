## Loads data/spacecraft.json once and answers mass and inertia questions
## per vehicle configuration. The CSM's configurations, in flight order:
##   saturn_v  the Saturn V on the pad and through the launch (its mass the
##             LaunchVehicle's; the IU flies it)
##   stack   S-IVB + CSM + LM (parking orbit and TLI; the IU flies it)
##   csm_lm  CSM docked to the LM (after transposition and docking)
##   csm     CSM alone (after undocking or LM jettison)
##   cm      Command Module alone (after CM/SM separation)
## and the LM's, while it flies free of the CSM:
##   lm         the whole LM
##   lm_ascent  its ascent stage, after staging
class_name SpacecraftData
extends RefCounted

const PATH := "res://data/spacecraft.json"
const CONFIGS := ["saturn_v", "stack", "csm_lm", "csm", "cm"]
const LM_CONFIGS := ["lm", "lm_ascent"]

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


## Total mass for [param cfg] given the propellant loads (kg), with the
## LM's mass [param lm_kg] (full tanks when negative).
static func total_mass(cfg: String, sps_kg: float, sm_rcs_kg: float, cm_rcs_kg: float, sivb_kg: float, lm_kg: float = -1.0) -> float:
	var m: Dictionary = data()["mass"]
	var cm := float(m["cm_dry_kg"]) + cm_rcs_kg
	if cfg == "cm":
		return cm
	var csm := cm + float(m["sm_dry_kg"]) + sm_rcs_kg + sps_kg
	if cfg == "csm":
		return csm
	var csm_lm := csm + (lm_kg if lm_kg >= 0.0 else lm_mass())
	if cfg == "csm_lm":
		return csm_lm
	return csm_lm + float(m["sivb_dry_kg"]) + sivb_kg


## The LM's mass in [param cfg] ("lm" or "lm_ascent") given its
## propellant loads (kg).
static func lm_total_mass(cfg: String, dps_kg: float, aps_kg: float, rcs_kg: float) -> float:
	var m: Dictionary = data()["mass"]
	var ascent := float(m["lm_ascent_dry_kg"]) + aps_kg + rcs_kg
	if cfg == "lm_ascent":
		return ascent
	return ascent + float(m["lm_descent_dry_kg"]) + dps_kg


## The LM's propellant loads with full tanks: [DPS, APS, RCS], kg.
static func lm_full_loads() -> Array[float]:
	return [float(section("dps")["propellant_kg"]), float(section("aps")["propellant_kg"]),
		2.0 * float(section("lm_rcs")["system_propellant_kg"])]


## The LM's mass with full tanks, kg.
static func lm_mass() -> float:
	var f := lm_full_loads()
	return lm_total_mass("lm", f[0], f[1], f[2])


## Principal inertia scaled linearly with mass from the configuration's
## reference [estimated].
static func inertia(cfg: String, mass: float) -> Vector3:
	var c := config(cfg)
	var i: Array = c["inertia"]
	var k := mass / float(c["ref_mass_kg"])
	return Vector3(float(i[0]), float(i[1]), float(i[2])) * clampf(k, 0.3, 2.0)

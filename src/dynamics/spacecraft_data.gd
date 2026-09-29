## Loads data/spacecraft.json once and answers mass and inertia questions
## per vehicle configuration. The CSM's configurations, in flight order:
##   saturn_v  the Saturn V on the pad and through the launch (its mass the
##             LaunchVehicle's; the IU flies it)
##   stack   S-IVB + CSM + LM (parking orbit and TLI; the IU flies it)
##   csm_lm  CSM docked to the LM (after transposition and docking)
##   csm     CSM alone (after undocking or LM jettison)
##   cm_lm   Command Module docked to the LM, the SM jettisoned (Apollo 13's
##           last hours, the LM flying them)
##   cm      Command Module alone (after CM/SM separation)
## and the LM's, while it flies free of the CSM:
##   lm         the whole LM
##   lm_ascent  its ascent stage, after staging
## A mission that carries no LM (mission.json "vehicles": mass.payload_kg,
## Apollo 8's test article) flies stack, then csm after CSM/LV SEP.
##
## The file's figures are Apollo 11's vehicles. A mission flies its own:
## its "vehicles" block replaces the keys it names, section by section
## (use_mission(), which Mission.load_file() calls).
class_name SpacecraftData
extends RefCounted

const PATH := "res://data/spacecraft.json"
const CONFIGS := ["saturn_v", "stack", "csm_lm", "csm", "cm_lm", "cm"]
const LM_CONFIGS := ["lm", "lm_ascent"]

static var _data: Dictionary = {}
## The mission's vehicles: its sections' keys over the file's.
static var _mission: Dictionary = {}
## Each section as the mission has it, merged on first use.
static var _sections: Dictionary = {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		assert(f != null, "cannot open " + PATH)
		_data = JSON.parse_string(f.get_as_text())
	return _data


## Fly the vehicles of the mission whose "vehicles" block is
## [param vehicles] (empty for the file's, Apollo 11's).
static func use_mission(vehicles: Dictionary) -> void:
	_mission = vehicles.duplicate(true)
	_sections = {}


static func section(name: String) -> Dictionary:
	if not _sections.has(name):
		var s: Dictionary = data()[name].duplicate() if data().has(name) else {}
		var over = _mission.get(name, {})
		if over is Dictionary:
			s.merge(over, true)
		_sections[name] = s
	return _sections[name]


static func config(name: String) -> Dictionary:
	return data()["configurations"][name]


## Total mass for [param cfg] given the propellant loads (kg), with the
## LM's mass [param lm_kg] (full tanks when negative), or without an LM
## the test article's.
static func total_mass(cfg: String, sps_kg: float, sm_rcs_kg: float, cm_rcs_kg: float, sivb_kg: float, lm_kg: float = -1.0) -> float:
	var m := section("mass")
	var cm := float(m["cm_dry_kg"]) + cm_rcs_kg
	if cfg == "cm":
		return cm
	if cfg == "cm_lm":
		return cm + (lm_kg if lm_kg >= 0.0 else payload_mass())
	var csm := cm + float(m["sm_dry_kg"]) + sm_rcs_kg + sps_kg
	if cfg == "csm":
		return csm
	var csm_lm := csm + (lm_kg if lm_kg >= 0.0 else payload_mass())
	if cfg == "csm_lm":
		return csm_lm
	return csm_lm + float(m["sivb_dry_kg"]) + sivb_kg


## The Service Module is still attached in configuration [param cfg].
static func sm_attached(cfg: String) -> bool:
	return not cfg in ["cm", "cm_lm"]


## The LM is docked in configuration [param cfg].
static func lm_docked(cfg: String) -> bool:
	return cfg in ["csm_lm", "cm_lm"]


## The mission carries an LM, in the S-IVB's adapter until transposition
## and docking; without one, the adapter holds a test article.
static func carries_lm() -> bool:
	return not section("mass").has("payload_kg")


## What rides in the S-IVB's adapter: the LM with full tanks, or the test
## article (with the adapter), kg.
static func payload_mass() -> float:
	return lm_mass() if carries_lm() else float(section("mass")["payload_kg"])


## The LM's mass in [param cfg] ("lm" or "lm_ascent") given its
## propellant loads (kg).
static func lm_total_mass(cfg: String, dps_kg: float, aps_kg: float, rcs_kg: float) -> float:
	var m := section("mass")
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

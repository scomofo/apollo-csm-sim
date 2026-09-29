## Owns the truth owners for one running mission and implements the
## snapshot/restore contract across them (same shape as the SimRuntime of
## gemini-capsule, https://github.com/scomofo/gemini-capsule, which this
## project derives from). Used by main.gd and, headless, by the tests.
class_name SimRuntime
extends RefCounted

## 2: the vehicles' dynamics and systems under "vehicles" (slice 3a).
## 3: the LGC's rendezvous state (slice 3e).
## 4: Mission Control's planned times and timeline (slice 3f).
## 5: ECI is the ICRF of JPL's ephemeris, and the S-IVB's TLI yaw (slice 4a).
## 6: the CMC's own state vector, the CSM's unmodelled forces and the
##    dispersions' seed and draws (slice 4b).
## 7: the CMC's IMU (REFSMMAT, the platform, its drift) and alignment
##    programs, and the optics (slice 4c).
## 8: the CMC's navigation filter, and P22's and P23's sightings (slice 4d).
## 9: the Moon's gravity field's samples each trajectory holds, the
##    truth's and the computers' state vectors' (slice 5b).
## 10: the thrust each trajectory's samples ahead were taken with, for
##    them to be taken again when a burn begins or ends (slice 5b).
## 11: the IU's target conic and its iterative guidance's state (slice 5c).
## 12: the launch vehicle's (slice 5d).
## 13: the CMC's steered thrust direction, which cross-product steering
##    holds in a burn's last seconds (slice 5e).
## 14: the CMC's entry programs and guidance, and the CM's roll rate
##    (slice 5f).
## 15: the master alarm circuit (slice 6a).
## 16: the LGC's throttle schedule for P40, uplinked with a DPS burn's PAD
##    (slice 7b).
## 17: whether noun 69 moved the LGC's landing site (slice 7c).
## 18: the LM as a lifeboat (slice 7d): its batteries, its AGS, the LGC's
##    IMU and coarse align, the CSM's O2 tank 1 leak.
const SCHEMA_VERSION := 18
## The CSM's systems (the S-IVB's among them, for the stack).
const SYSTEMS := [
	["eps", "res://src/systems/eps.gd"],
	["agc", "res://src/systems/agc.gd"],
	["rcs", "res://src/systems/rcs.gd"],
	["sps", "res://src/systems/sps.gd"],
	["lv", "res://src/systems/launch_vehicle.gd"],
	["sivb", "res://src/systems/sivb.gd"],
	["els", "res://src/systems/els.gd"],
	["optics", "res://src/systems/optics.gd"],
	["cw", "res://src/systems/caution_warning.gd"],
]
## The LM's systems. They come after the CSM's, so in each clock stage
## they tick after the CSM's.
const LM_SYSTEMS := [
	["lm_eps", "res://src/systems/lm_eps.gd"],
	["lgc", "res://src/systems/lgc.gd"],
	["ags", "res://src/systems/ags.gd"],
	["lm_rcs", "res://src/systems/lm_rcs.gd"],
	["dps", "res://src/systems/dps.gd"],
	["aps", "res://src/systems/aps.gd"],
	["lr", "res://src/systems/landing_radar.gd"],
	["rr", "res://src/systems/rendezvous_radar.gd"],
]
## Crew control defaults: CMC attitude source, HOLD, SPS disarmed, UP TLM
## CM in ACCEPT, the optics in CMC mode at MED speed, the CM's loads all on
## its own buses; the LM's DAP in HOLD, its engines disarmed and both RCS
## systems open, the PGNS's breakers in and its guidance in control, the
## AGS off, the TTCA's throttle at its minimum, and docked, the LM powered
## down.
const CONTROL_DEFAULTS := {
	"ctl.scs.att_source": 0, "ctl.cmc.mode": 1, "ctl.cmc.up_tlm": true,
	"ctl.optics.zero": false, "ctl.optics.mode": 1, "ctl.optics.speed": 1, "ctl.optics.hc": Vector3.ZERO,
	"ctl.optics.mark": false, "ctl.optics.mark_reject": false,
	"ctl.sps.arm_a": false, "ctl.sps.arm_b": false, "ctl.sps.thrust_on": false,
	"ctl.rhc": Vector3.ZERO, "ctl.thc": Vector3.ZERO,
	"ctl.els.logic": false, "ctl.els.auto": false, "ctl.cw.master_alarm": false,
	"ctl.eps.fc1": true, "ctl.eps.fc2": true, "ctl.eps.fc3": true, "ctl.eps.cm_power": 2, "ctl.eps.lm_power": false,
	"ctl.seq.csm_sep": false, "ctl.seq.undock": false, "ctl.seq.lm_jett": false, "ctl.seq.cm_sm_sep": false,
	"ctl.ground.pad_request": "",
	"ctl.lm.mode": 1, "ctl.lm.rhc": Vector3.ZERO, "ctl.lm.thc": Vector3.ZERO,
	"ctl.lm.engine_arm": 0, "ctl.lm.stage": false, "ctl.lm.rcs.sys_a": true, "ctl.lm.rcs.sys_b": true,
	"ctl.lm.eng_start": false, "ctl.lm.eng_stop": false, "ctl.lm.rod": 0,
	"ctl.lm.power": false, "ctl.lm.pgns": true, "ctl.lm.ags": false, "ctl.lm.ags_align": false, "ctl.lm.guid_cont": 0,
	"ctl.lm.throttle": 0.1,
}

var mission: Mission
var dynamics: Dynamics
var sequencer: MissionSequencer
var systems: Dictionary = {}
var nodes: Array[Node] = []


static func build(parent: Node, mission_path: String = "") -> SimRuntime:
	var rt := SimRuntime.new()
	rt.mission = Mission.load_file(mission_path) if mission_path != "" else Mission.load_default()
	SimClock.liftoff_jd = float(rt.mission.data.get("liftoff_jd", SimClock.liftoff_jd))
	for k in CONTROL_DEFAULTS:
		if not Bus.has_channel(k):
			Bus.set_value(k, CONTROL_DEFAULTS[k])
	rt.dynamics = Dynamics.new()
	rt.dynamics.name = "Dynamics"
	parent.add_child(rt.dynamics)
	rt.nodes.append(rt.dynamics)
	for pair in SYSTEMS + LM_SYSTEMS:
		var n: Node = load(pair[1]).new()
		n.name = str(pair[0]).to_upper()
		parent.add_child(n)
		rt.systems[pair[0]] = n
		rt.nodes.append(n)
	rt.sequencer = MissionSequencer.new()
	rt.sequencer.name = "MissionSequencer"
	rt.sequencer.mission = rt.mission
	rt.sequencer.dynamics = rt.dynamics
	rt.sequencer.systems = rt.systems
	parent.add_child(rt.sequencer)
	rt.nodes.append(rt.sequencer)
	return rt


## The CMC.
func agc() -> Agc:
	return systems["agc"]


## The LGC.
func lgc() -> Lgc:
	return systems["lgc"]


func free_nodes() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()


## The checkpoint: the clock, the mission, the crew's controls, and a map
## of vehicles, each with its dynamics and the systems it carries. The CSM
## is always there. The LM is there while it flies free; docked (or in the
## S-IVB's adapter) it is part of the CSM's configuration, and its systems
## are in the CSM's entry. After LM JETT they are gone with it.
func snapshot() -> Dictionary:
	var csm_systems := _systems_snapshot(SYSTEMS)
	var vehicles := {"csm": {"dynamics": dynamics.snapshot(), "systems": csm_systems}}
	if dynamics.lm != null:
		vehicles["lm"] = {"dynamics": dynamics.lm.snapshot(), "systems": _systems_snapshot(LM_SYSTEMS)}
	elif dynamics.has_lm():
		csm_systems.merge(_systems_snapshot(LM_SYSTEMS))
	var ctl := {}
	for c in Bus.channels():
		if c.begins_with("ctl."):
			var v = Bus.get_value(c)
			ctl[c] = [v.x, v.y, v.z] if v is Vector3 else v
	return {
		"schema_version": SCHEMA_VERSION,
		"mission_id": mission.id(),
		"clock": SimClock.snapshot(),
		"mission": sequencer.snapshot(),
		"vehicles": vehicles,
		"controls": ctl,
	}


func _systems_snapshot(list: Array) -> Dictionary:
	var out := {}
	for pair in list:
		out[pair[0]] = systems[pair[0]].snapshot()
	return out


func _systems_restore(list: Array, d: Dictionary) -> void:
	for pair in list:
		if d.has(pair[0]):
			systems[pair[0]].restore(d[pair[0]])


## Restore a snapshot (possibly round-tripped through JSON). Returns an
## error string, empty on success.
func restore(d: Dictionary) -> String:
	if not d.has("schema_version"):
		return "checkpoint missing 'schema_version'"
	if int(d["schema_version"]) != SCHEMA_VERSION:
		return "checkpoint schema %s, expected %d" % [d["schema_version"], SCHEMA_VERSION]
	for key in ["clock", "mission", "vehicles"]:
		if not d.has(key):
			return "checkpoint missing '%s'" % key
	var csm: Dictionary = d["vehicles"].get("csm", {})
	for key in ["dynamics", "systems"]:
		if not csm.has(key):
			return "checkpoint missing 'vehicles.csm.%s'" % key
	if str(d.get("mission_id", "")) != mission.id():
		return "checkpoint is for mission '%s'" % d.get("mission_id", "")
	for c in d.get("controls", {}):
		var v = d["controls"][c]
		Bus.set_value(c, Vector3(v[0], v[1], v[2]) if v is Array and v.size() == 3 else v)
	SimClock.restore(d["clock"])
	var lm: Dictionary = d["vehicles"].get("lm", {})
	dynamics.restore(csm["dynamics"], lm.get("dynamics", {}))
	_systems_restore(SYSTEMS, csm["systems"])
	_systems_restore(LM_SYSTEMS, lm.get("systems", csm["systems"]))
	# Again, with the LM's power known: docked and powered, its channels are
	# the stack's.
	dynamics.publish_state()
	sequencer.restore(d["mission"])
	return ""


func save_file(path: String) -> Error:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_string(JSON.stringify(snapshot(), "\t"))
	return OK


func load_file(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return "cannot open " + path
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return "checkpoint is not a JSON object"
	return restore(d)

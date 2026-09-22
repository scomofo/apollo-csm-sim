## Owns the truth owners for one running mission and implements the
## snapshot/restore contract across them (same shape as the Gemini
## template's SimRuntime). Used by main.gd and, headless, by the tests.
class_name SimRuntime
extends RefCounted

const SCHEMA_VERSION := 1
const SYSTEMS := [
	["eps", "res://src/systems/eps.gd"],
	["agc", "res://src/systems/agc.gd"],
	["rcs", "res://src/systems/rcs.gd"],
	["sps", "res://src/systems/sps.gd"],
	["sivb", "res://src/systems/sivb.gd"],
	["els", "res://src/systems/els.gd"],
]
## Crew control defaults: CMC attitude source, HOLD, SPS disarmed.
const CONTROL_DEFAULTS := {
	"ctl.scs.att_source": 0, "ctl.cmc.mode": 1,
	"ctl.sps.arm_a": false, "ctl.sps.arm_b": false, "ctl.sps.thrust_on": false,
	"ctl.rhc": Vector3.ZERO, "ctl.thc": Vector3.ZERO,
	"ctl.els.logic": false, "ctl.els.auto": false,
	"ctl.eps.fc1": true, "ctl.eps.fc2": true, "ctl.eps.fc3": true,
	"ctl.seq.csm_sep": false, "ctl.seq.lm_jett": false, "ctl.seq.cm_sm_sep": false,
	"ctl.ground.pad_request": "",
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
	for pair in SYSTEMS:
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


func agc() -> Agc:
	return systems["agc"]


func free_nodes() -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	nodes.clear()


func snapshot() -> Dictionary:
	var sys := {}
	for k in systems:
		sys[k] = systems[k].snapshot()
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
		"dynamics": dynamics.snapshot(),
		"systems": sys,
		"controls": ctl,
	}


## Restore a snapshot (possibly round-tripped through JSON). Returns an
## error string, empty on success.
func restore(d: Dictionary) -> String:
	for key in ["schema_version", "clock", "mission", "dynamics", "systems"]:
		if not d.has(key):
			return "checkpoint missing '%s'" % key
	if int(d["schema_version"]) != SCHEMA_VERSION:
		return "checkpoint schema %s, expected %d" % [d["schema_version"], SCHEMA_VERSION]
	if str(d.get("mission_id", "")) != mission.id():
		return "checkpoint is for mission '%s'" % d.get("mission_id", "")
	for c in d.get("controls", {}):
		var v = d["controls"][c]
		Bus.set_value(c, Vector3(v[0], v[1], v[2]) if v is Array and v.size() == 3 else v)
	SimClock.restore(d["clock"])
	dynamics.restore(d["dynamics"])
	for k in systems:
		if d["systems"].has(k):
			systems[k].restore(d["systems"][k])
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

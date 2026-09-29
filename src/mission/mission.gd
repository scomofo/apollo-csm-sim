## Mission profile loaded from data/missions/<id>/mission.json. Pure data
## plus accessors; the MissionSequencer runs it. Each mission is its own
## data: its dates and ephemeris, its vehicles, its orbits, Mission
## Control's timeline and the crew's call signs.
class_name Mission
extends RefCounted

const DIR := "res://data/missions/"
const DEFAULT_ID := "apollo_11"
const DEFAULT_PATH := DIR + DEFAULT_ID + "/mission.json"
## Each vehicle's call sign when the mission doesn't give it (mission.json
## "call_signs"): "mission" the flight's, "csm" the CSM's, "lm" the LM's,
## "lm_landed" the LM's on the surface.
const CALL_SIGNS := {"mission": "Apollo", "csm": "Apollo", "lm": "LM", "lm_landed": "LM"}

var data: Dictionary = {}


## The mission file for mission [param id].
static func path_of(id: String) -> String:
	return DIR + id + "/mission.json"


## The missions under data/missions/, by id.
static func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for d in DirAccess.get_directories_at(DIR):
		if FileAccess.file_exists(path_of(d)):
			out.append(d)
	return out


## Load a mission file, and fly its world and vehicles: its ephemeris
## (apply_ephemeris()) and its vehicles (SpacecraftData.use_mission()).
static func load_file(path: String) -> Mission:
	var m := Mission.new()
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open " + path)
	m.data = JSON.parse_string(f.get_as_text())
	m.apply_ephemeris()
	SpacecraftData.use_mission(m.section("vehicles"))
	return m


static func load_default() -> Mission:
	return load_file(DEFAULT_PATH)


## Mission [param id]'s data alone, the world and the vehicles flown left
## as they are: for the flight menu, which lists the missions without
## flying them.
static func read(id: String) -> Mission:
	var m := Mission.new()
	var f := FileAccess.open(path_of(id), FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			m.data = d
	return m


func id() -> String:
	return str(data.get("id", ""))


func section(name: String) -> Dictionary:
	return data.get(name, {})


## The line the mission's data gives its start phase [param phase]
## ("start_notes"), for the flight menu.
func start_note(phase: String) -> String:
	return str(section("start_notes").get(phase, ""))


## [param role]'s call sign ("mission", "csm", "lm", "lm_landed").
func call_sign(role: String) -> String:
	return str(section("call_signs").get(role, CALL_SIGNS.get(role, "")))


## [param text] with each vehicle's call sign put in for its {role}
## ("{csm}, Houston."), and [param more]'s entries for theirs.
func words(text: String, more: Dictionary = {}) -> String:
	var subs := more.duplicate()
	for role in CALL_SIGNS:
		subs[role] = call_sign(role)
	return text.format(subs)


## Set Bodies' Moon and Sun from the moon block: JPL's ephemeris for the
## mission when it names one ("ephemeris", a res:// path), with the Moon's
## gravity field when it names that ("gravity"), or else the circular
## model its angles give.
func apply_ephemeris() -> void:
	var m := section("moon")
	if m.has("ephemeris"):
		var e := Ephemeris.load_file(str(m["ephemeris"]))
		assert(absf(e.epoch_jd_utc - float(data["liftoff_jd"])) < 1e-9, "the ephemeris counts GET from the mission's liftoff_jd")
		Bodies.use_ephemeris(e)
		if m.has("gravity"):
			MoonGravity.load_field(str(m["gravity"]))
		else:
			MoonGravity.unload()
		return
	Bodies.configure(float(m.get("inclination_deg", 28.5)), float(m.get("raan_deg", 0.0)),
		float(m.get("phase0_deg", 0.0)), float(m.get("sun_phase_deg", -20.0)))

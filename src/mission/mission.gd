## Mission profile loaded from data/missions/<id>/mission.json. Pure data
## plus accessors; the MissionSequencer runs it.
class_name Mission
extends RefCounted

const DEFAULT_PATH := "res://data/missions/apollo_11/mission.json"

var data: Dictionary = {}


static func load_file(path: String) -> Mission:
	var m := Mission.new()
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open " + path)
	m.data = JSON.parse_string(f.get_as_text())
	m.apply_ephemeris()
	return m


static func load_default() -> Mission:
	return load_file(DEFAULT_PATH)


func id() -> String:
	return str(data.get("id", ""))


func section(name: String) -> Dictionary:
	return data.get(name, {})


func apply_ephemeris() -> void:
	var m := section("moon")
	Bodies.configure(float(m.get("inclination_deg", 28.5)), float(m.get("raan_deg", 0.0)),
		float(m.get("phase0_deg", 0.0)), float(m.get("sun_phase_deg", -20.0)))

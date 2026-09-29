## The flight menu's choice (docs/ROADMAP.md, slice 8a): the missions under
## data/missions/, in the order they flew, each with its start phases
## (mission.json "start_phases") and the line its data gives each
## ("start_notes"), and the mission and the start phase chosen. The wrist
## menu's flight page steps through them, and its START asks the main
## scene for that flight. It reads the missions' files and flies none.
class_name FlightChoice
extends RefCounted

## The missions with start phases, by liftoff.
var missions: Array[Mission] = []
var mission_index: int = 0
var phase_index: int = 0


## The choice starts at mission [param mission_id]'s start phase
## [param phase]: the flight flown.
func _init(mission_id: String = Mission.DEFAULT_ID, phase: String = "") -> void:
	for id in Mission.ids():
		var m := Mission.read(id)
		if not (m.data.get("start_phases", []) as Array).is_empty():
			missions.append(m)
	missions.sort_custom(func(a: Mission, b: Mission) -> bool:
		return float(a.data.get("liftoff_jd", 0.0)) < float(b.data.get("liftoff_jd", 0.0)))
	choose(mission_id, phase)


## Choose mission [param mission_id] and its start phase [param phase], or
## its first start phase when it has no such one.
func choose(mission_id: String, phase: String = "") -> void:
	for i in missions.size():
		if missions[i].id() == mission_id:
			mission_index = i
	phase_index = maxi(phases().find(phase), 0)


func mission() -> Mission:
	return missions[mission_index]


func mission_id() -> String:
	return mission().id()


## The chosen mission's start phases.
func phases() -> Array:
	return mission().data.get("start_phases", [])


func phase() -> String:
	var ps := phases()
	return str(ps[phase_index]) if not ps.is_empty() else ""


## The next mission, or with [param step] -1 the one before, keeping the
## start phase where it has it.
func step_mission(step: int) -> void:
	var was := phase()
	mission_index = posmod(mission_index + step, missions.size())
	phase_index = maxi(phases().find(was), 0)


## The mission's next start phase, or with [param step] -1 the one before.
func step_phase(step: int) -> void:
	phase_index = posmod(phase_index + step, maxi(phases().size(), 1))


## A start phase's name as the menu shows it: "LUNAR ORBIT", "TEI".
static func phase_title(p: String) -> String:
	return p.replace("_", " ").to_upper()


## The flight page's lines: the mission, the start phase and its note.
func text() -> String:
	return "%s\n%s\n%s" % [str(mission().data.get("title", mission_id())), phase_title(phase()),
		mission().start_note(phase())]

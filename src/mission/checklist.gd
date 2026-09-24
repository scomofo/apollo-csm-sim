## Flight-plan checklists (data/missions/<id>/checklists.json), in the same
## spirit as the procedure runner of gemini-capsule
## (https://github.com/scomofo/gemini-capsule, src/mission/procedure_runner.gd):
## each step reads as a crew action, and a step with a "check" completes
## itself when the Bus shows the action was done. Steps without a check are
## read-and-continue.
##
## check: {"channel": "...", "op": "eq"|"ne"|"gt"|"lt"|"ge"|"le", "value": v}
## phases: the flight phases (mission.phase) the checklist is for.
class_name Checklist
extends RefCounted

var title: String = ""
var phases: PackedStringArray = []
var steps: Array = []
var index: int = 0


static func load_all(path: String) -> Array[Checklist]:
	var out: Array[Checklist] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var d = JSON.parse_string(f.get_as_text())
	for c in d.get("checklists", []):
		var cl := Checklist.new()
		cl.title = str(c["title"])
		cl.phases = PackedStringArray(c.get("phases", []))
		cl.steps = c["steps"]
		out.append(cl)
	return out


static func holds(check: Dictionary) -> bool:
	var v = Bus.get_value(str(check["channel"]))
	if v == null:
		return false
	var want = check["value"]
	match str(check.get("op", "eq")):
		"eq":
			if want is bool or v is bool:
				return bool(v) == bool(want)
			if want is String or v is String:
				return str(v) == str(want)
			return absf(float(v) - float(want)) < 1e-6
		"ne":
			return str(v) != str(want)
		"gt":
			return float(v) > float(want)
		"lt":
			return float(v) < float(want)
		"ge":
			return float(v) >= float(want)
		"le":
			return float(v) <= float(want)
	return false


func done() -> bool:
	return index >= steps.size()


func current() -> Dictionary:
	return steps[index] if not done() else {}


## Advance past every step whose check now holds. Returns true on change.
func update() -> bool:
	var moved := false
	while not done():
		var s: Dictionary = steps[index]
		if s.has("check") and holds(s["check"]):
			index += 1
			moved = true
		else:
			break
	return moved


## Crew acknowledges a read-only step.
func next() -> void:
	if not done() and not current().has("check"):
		index += 1

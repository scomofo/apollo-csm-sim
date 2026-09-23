## The flight-plan checklists and which one is open, shared by the HUD's
## checklist panel, the cabin's checklist card, the checklist highlight and
## the wrist menu: a step acknowledged on one of them shows on all.
## Presentation state, like the HUD's before it: checkpoints don't save it.
class_name ChecklistBook
extends RefCounted

const PATH := "res://data/missions/apollo_11/checklists.json"
## The checklist that fits each flight phase.
const FOR_PHASE := {"parking_orbit": 0, "tli": 0, "translunar_coast": 1, "lunar_orbit": 2,
	"transearth_coast": 3, "entry": 3}

var lists: Array[Checklist] = []
## Index of the open checklist.
var current: int = 0


static func load_default() -> ChecklistBook:
	var b := ChecklistBook.new()
	b.lists = Checklist.load_all(PATH)
	return b


func list() -> Checklist:
	return lists[current] if current < lists.size() else null


## Open checklist [param i] from its first step.
func select(i: int) -> void:
	if lists.is_empty():
		return
	current = posmod(i, lists.size())
	lists[current].index = 0


## Open the checklist for [param phase] where it stands.
func select_for_phase(phase: String) -> void:
	var i: int = FOR_PHASE.get(phase, 0)
	if i < lists.size():
		current = i


## The next checklist, from its first step.
func cycle() -> void:
	select(current + 1)


## Acknowledge the current step if it has no check.
func next() -> void:
	if list() != null:
		list().next()


## Advance past every step whose check holds. Returns true on change.
func update() -> bool:
	return list().update() if list() != null else false


## Up to [param count] steps around the current one:
## [{text, state: "done" | "current" | "pending", manual: bool}].
func window(before: int = 2, count: int = 8) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var c := list()
	if c == null:
		return out
	var first := maxi(0, c.index - before)
	for i in range(first, mini(c.steps.size(), first + count)):
		var s: Dictionary = c.steps[i]
		var state := "done" if i < c.index else ("current" if i == c.index else "pending")
		out.append({"text": str(s["text"]), "state": state, "manual": not s.has("check")})
	return out


## What the current step is done on: its "control" (an id in
## data/cockpit/controls.csv) and its check channel, either possibly "".
func target() -> Dictionary:
	var c := list()
	if c == null or c.done():
		return {"control": "", "channel": ""}
	var s := c.current()
	var check: Dictionary = s.get("check", {})
	return {"control": str(s.get("control", "")), "channel": str(check.get("channel", ""))}

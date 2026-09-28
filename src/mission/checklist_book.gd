## The flight-plan checklists and which one is open, shared by the HUD's
## checklist panel, the cabin's checklist card, the checklist highlight and
## the wrist menu: a step acknowledged on one of them shows on all.
## The CSM's checklists are one book (load_default()) and the LM's another
## (load_lm()), each with its own open checklist, and each mission has its
## own (data/missions/<id>/): Apollo 8's has no LM book.
## Presentation state, like the HUD's before it: checkpoints don't save it.
class_name ChecklistBook
extends RefCounted

var lists: Array[Checklist] = []
## Index of the open checklist.
var current: int = 0


## The CSM's checklists for mission [param mission_id].
static func load_default(mission_id: String = Mission.DEFAULT_ID) -> ChecklistBook:
	return load_file(Mission.DIR + mission_id + "/checklists.json")


## The LM's checklists for mission [param mission_id]: none without an LM.
static func load_lm(mission_id: String = Mission.DEFAULT_ID) -> ChecklistBook:
	return load_file(Mission.DIR + mission_id + "/lm_checklists.json")


static func load_file(path: String) -> ChecklistBook:
	var b := ChecklistBook.new()
	b.lists = Checklist.load_all(path)
	return b


func list() -> Checklist:
	return lists[current] if current < lists.size() else null


## Open checklist [param i] where it stands, so the crew can turn to the
## SPS burn checklist and come back to the phase's. A finished checklist
## opens at its first step again, as the SPS burn one does for each burn.
func select(i: int) -> void:
	if lists.is_empty():
		return
	current = posmod(i, lists.size())
	if lists[current].done():
		lists[current].index = 0


## Open the checklist for [param phase] (the first whose phases have it)
## where it stands. With none for it, the open one stays open.
func select_for_phase(phase: String) -> void:
	for i in lists.size():
		if lists[i].phases.has(phase):
			current = i
			return


## The next checklist, where it stands.
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

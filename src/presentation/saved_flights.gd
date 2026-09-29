## Saved flights (docs/ROADMAP.md, slice 8b): checkpoints with names, one
## JSON file each in a directory (user://saves for the app), listed for
## the flight menu's SAVES page with their mission, phase and GET, newest
## first, and saved, resumed and deleted there. A file is
## SimRuntime.snapshot() with a "save" header beside it, which restore()
## doesn't read: the name, when it was saved, and the start phase the
## flight began in and its first flight phase, for the checklists that
## open when it is resumed. F5 and F9 keep one quick save (QUICK), listed
## with the rest. A save that this build can't restore (another schema, a
## mission no longer under data/missions/, a file that isn't one) is
## listed as unusable, with the reason, and never offered to resume.
class_name SavedFlights
extends RefCounted

## The app's directory.
const DIR := "user://saves"
## F5's and F9's file.
const QUICK := "quick.json"

## The directory the saves are in; "" keeps none (a test's main scene,
## unless the test gives it one).
var dir: String = ""
## The saves, newest first: {path, name, mission_id, phase, get_s,
## saved_unix, start_phase, first_phase, usable, why}.
var entries: Array[Dictionary] = []
## The save chosen on the SAVES page.
var index: int = 0


func _init(p_dir: String = "") -> void:
	dir = p_dir
	refresh()


## Read the directory again, keeping the save chosen where it is still there.
func refresh() -> void:
	var keep := selected_path()
	entries.clear()
	index = 0
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		if f.get_extension() == "json":
			entries.append(read_entry(dir.path_join(f)))
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["saved_unix"]) > float(b["saved_unix"]))
	select_path(keep)


## The listing of the save at [param path].
static func read_entry(path: String) -> Dictionary:
	var e := {"path": path, "name": path.get_file().get_basename(), "mission_id": "", "phase": "", "get_s": 0.0,
		"saved_unix": float(FileAccess.get_modified_time(path)), "start_phase": "", "first_phase": "",
		"usable": false, "why": ""}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not d is Dictionary:
		e["why"] = "not a saved flight"
		return e
	var h: Dictionary = d.get("save", {}) if d.get("save") is Dictionary else {}
	var m: Dictionary = d.get("mission", {}) if d.get("mission") is Dictionary else {}
	var c: Dictionary = d.get("clock", {}) if d.get("clock") is Dictionary else {}
	e["mission_id"] = str(d.get("mission_id", ""))
	e["phase"] = str(m.get("phase", ""))
	e["get_s"] = float(c.get("get_s", 0.0))
	e["name"] = str(h.get("name", e["name"]))
	e["saved_unix"] = float(h.get("saved_unix", e["saved_unix"]))
	e["start_phase"] = str(h.get("start_phase", e["phase"]))
	e["first_phase"] = str(h.get("first_phase", e["phase"]))
	var schema := int(d.get("schema_version", 0))
	if schema != SimRuntime.SCHEMA_VERSION:
		e["why"] = "saved by %s version (checkpoint schema %d, this one %d)" % [
			"an older" if schema < SimRuntime.SCHEMA_VERSION else "a newer", schema, SimRuntime.SCHEMA_VERSION]
	elif not e["mission_id"] in Mission.ids():
		e["why"] = "no mission '%s' under %s" % [e["mission_id"], Mission.DIR]
	else:
		e["usable"] = true
	return e


## Save [param rt]'s flight with [param header] (its "start_phase" and
## "first_phase"), named for its mission, phase and GET: in the quick-save
## file with [param quick], else in a new file. Returns the path, or ""
## when there is no directory or the file can't be written.
func save(rt: SimRuntime, header: Dictionary = {}, quick: bool = false) -> String:
	if dir == "":
		return ""
	DirAccess.make_dir_recursive_absolute(dir)
	var d := rt.snapshot()
	var h := header.duplicate()
	var line := "%s, %s, %s GET" % [rt.mission.call_sign("mission"),
		FlightChoice.phase_title(str(d["mission"]["phase"])), Units.hms(SimClock.get_seconds)]
	h["name"] = ("Quick save (F5): " + line) if quick else line
	h["saved_unix"] = Time.get_unix_time_from_system()
	d["save"] = h
	var path := dir.path_join(QUICK if quick else _new_file(rt.mission.id()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(JSON.stringify(d, "\t"))
	f.close()
	refresh()
	select_path(path)
	return path


## A file name not yet taken: the mission and the time it is saved.
func _new_file(mission_id: String) -> String:
	var stamp := Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "")
	var file := "%s_%s.json" % [mission_id, stamp]
	var n := 2
	while FileAccess.file_exists(dir.path_join(file)):
		file = "%s_%s_%d.json" % [mission_id, stamp, n]
		n += 1
	return file


## The quick save's path.
func quick_path() -> String:
	return dir.path_join(QUICK) if dir != "" else ""


## Delete the save at [param path], one of this directory's. Returns
## whether it did.
func delete(path: String) -> bool:
	if dir == "" or path.get_base_dir() != dir or not FileAccess.file_exists(path):
		return false
	var ok := DirAccess.remove_absolute(path) == OK
	refresh()
	return ok


## The listing of the save at [param path], or an empty one.
func entry(path: String) -> Dictionary:
	for e in entries:
		if e["path"] == path:
			return e
	return {}


func selected() -> Dictionary:
	return entries[index] if index < entries.size() else {}


func selected_path() -> String:
	return str(selected().get("path", ""))


func select_path(path: String) -> void:
	for i in entries.size():
		if entries[i]["path"] == path:
			index = i


## The next save, or with [param step] -1 the one before.
func step(p_step: int) -> void:
	index = posmod(index + p_step, maxi(entries.size(), 1))


## The SAVES page's lines: which save of how many, its name, and when it
## was saved or why it can't be resumed.
func text() -> String:
	if entries.is_empty():
		return "NO SAVED FLIGHTS\nSAVE keeps the flight flown now"
	var e := selected()
	var last := ("saved %s UTC" % Time.get_datetime_string_from_unix_time(int(e["saved_unix"]), true).left(16)) \
		if e["usable"] else "CAN'T RESUME: " + str(e["why"])
	return "SAVED FLIGHT %d OF %d\n%s\n%s" % [index + 1, entries.size(), e["name"], last]

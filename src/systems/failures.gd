## The failure catalog at work (docs/ROADMAP.md, slice 9a): the failures
## data/failures.json lists, armed at a GET by the mission's data
## (mission.json "failures": [{id, get_s}]) or by arm(), and failed at
## once by fail(), as the instructor's page on the wrist menu does. A
## failure that comes due goes to its system's fail(part), which changes
## the system as the catalog says; its caution light follows from the
## system's state (CautionWarning). It fires the mission event the catalog
## names and says the crew's words to Houston, where it has them.
##
## The sequencer fires its event and says its call (MissionSequencer's
## failures).
##
## It ticks in the MISSION stage, after the sequencer: a failure due at a
## GET changes its system before the systems step at that GET, and the
## clock lands a coast step on it (failures.next_event_get_s).
##
## Writes: failures.active (the ids failed), failures.next_event_get_s,
##         failure.<id> (the GET it failed at)
class_name Failures
extends Node

## Failure [param id] has just failed.
signal failed(id: String)

const CATALOG_PATH := "res://data/failures.json"

static var _catalog: Array = []

var systems: Dictionary = {}
var mission: Mission
## id -> the GET it is armed for.
var armed: Dictionary = {}
## id -> the GET it failed at.
var active: Dictionary = {}


## The catalog's failures, in its order.
static func catalog() -> Array:
	if _catalog.is_empty():
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
		_catalog = d.get("failures", []) if d is Dictionary else []
	return _catalog


## The catalog's failure [param id], or an empty one.
static func entry(id: String) -> Dictionary:
	for f: Dictionary in catalog():
		if f["id"] == id:
			return f
	return {}


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.MISSION)
	if mission != null:
		for f: Dictionary in mission.data.get("failures", []):
			arm(str(f["id"]), float(f["get_s"]))
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## Arm failure [param id] to fail at GET [param get_s]. Returns whether it
## did: not for a failure the catalog hasn't, or one already failed.
func arm(id: String, get_s: float) -> bool:
	if entry(id).is_empty():
		push_error("Failures: no failure '%s' in %s" % [id, CATALOG_PATH])
		return false
	if active.has(id):
		return false
	armed[id] = get_s
	_publish()
	return true


## Fail [param id] now. Returns whether it did: not for a failure already
## failed, or one whose system this flight hasn't.
func fail(id: String) -> bool:
	var e := entry(id)
	if e.is_empty() or active.has(id):
		return false
	var sys: Node = systems.get(str(e["system"]))
	if sys == null or not sys.has_method("fail"):
		return false
	armed.erase(id)
	sys.call("fail", str(e["part"]))
	active[id] = SimClock.get_seconds
	_publish()
	failed.emit(id)
	return true


func tick(_dt: float) -> void:
	var now := SimClock.get_seconds
	for id: String in armed.keys():
		if now >= float(armed[id]) - 1e-6:
			fail(id)
	Bus.set_value("failures.next_event_get_s", next_get(now))


## The GET of the next armed failure after [param now], or -1.
func next_get(now: float) -> float:
	var next := -1.0
	for id: String in armed:
		var t := float(armed[id])
		if t > now + 1e-6 and (next < 0.0 or t < next):
			next = t
	return next


## A line on failure [param id] as it stands: failed at a GET, armed for
## one, or ready.
func state_line(id: String) -> String:
	if active.has(id):
		return "FAILED at %s GET" % Units.hms(float(active[id]))
	if armed.has(id):
		return "ARMED for %s GET" % Units.hms(float(armed[id]))
	return "READY: FAIL fails it now"


func _publish() -> void:
	Bus.set_value("failures.active", active.keys())
	Bus.set_value("failures.next_event_get_s", next_get(SimClock.get_seconds))
	for id: String in active:
		Bus.set_value("failure." + id, float(active[id]))


func snapshot() -> Dictionary:
	return {"armed": armed.duplicate(), "active": active.duplicate()}


## The armed and the failed as they were; each system keeps its own failed
## parts in its own snapshot.
func restore(d: Dictionary) -> void:
	armed = (d.get("armed", {}) as Dictionary).duplicate()
	active = (d.get("active", {}) as Dictionary).duplicate()
	_publish()

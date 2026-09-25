## Which vehicle the player flies: player.vehicle, "csm" or "lm". The hand
## controllers, the DSKY keys, the HUD and the space view follow it. The
## player moves to the LM as it undocks, as its commander, and back to the
## CSM when it docks again or is jettisoned (docs/ROADMAP.md, milestone 3,
## "Who flies what"). While the LM flies free, toggle() switches between
## the two. Presentation state: checkpoints don't save it, and after a
## checkpoint load the docking state decides it again. The player boards
## the vehicle's cabin in a headset as on the desktop.
##
## Reads:  dock.state
## Writes: player.vehicle
class_name VehicleSwitch
extends Node

## The player flies [param vehicle] now: gone aboard it, or by L.
signal changed(vehicle: String)
## The player went aboard [param vehicle]: at the start, or as the docking
## state moved them. The vehicle's checklist for the phase opens then; L
## goes back to where the other vehicle's checklists stand.
signal boarded(vehicle: String)

var vehicle: String = ""
var _dock_was: String = ""


func _ready() -> void:
	_dock_was = _dock()
	_choose("lm" if _dock_was == "free" else "csm")
	boarded.emit(vehicle)


func _process(_delta: float) -> void:
	update()


## Follow the docking state: into the LM as it undocks, back to the CSM as
## it docks or goes.
func update() -> void:
	var d := _dock()
	if d != _dock_was:
		_dock_was = d
		var was := vehicle
		_choose("lm" if d == "free" else "csm")
		if vehicle != was:
			boarded.emit(vehicle)


## Change vehicles while the LM flies free. Returns whether it did.
func toggle() -> bool:
	if _dock() != "free":
		return false
	_choose("csm" if vehicle == "lm" else "lm")
	return true


func _dock() -> String:
	return str(Bus.get_value("dock.state", ""))


func _choose(v: String) -> void:
	Bus.set_value("player.vehicle", v)
	if v != vehicle:
		vehicle = v
		changed.emit(v)

## Which vehicle the player flies: player.vehicle, "csm" or "lm". The hand
## controllers, the DSKY keys, the HUD and the space view follow it. The
## player moves to the LM as it undocks, as its commander, and back to the
## CSM when it docks again or is jettisoned (docs/ROADMAP.md, milestone 3,
## "Who flies what"). While the LM flies free, toggle() switches between
## the two. Presentation state: checkpoints don't save it, and after a
## checkpoint load the docking state decides it again. With csm_only (in a
## headset, where the LM has no cabin yet) the player stays in the CSM.
##
## Reads:  dock.state
## Writes: player.vehicle
class_name VehicleSwitch
extends Node

signal changed(vehicle: String)

var vehicle: String = ""
## Keep the player in the CSM.
var csm_only: bool = false
var _dock_was: String = ""


func _ready() -> void:
	_dock_was = _dock()
	_choose("lm" if _dock_was == "free" else "csm")


func _process(_delta: float) -> void:
	update()


## Follow the docking state: into the LM as it undocks, back to the CSM as
## it docks or goes.
func update() -> void:
	var d := _dock()
	if d != _dock_was:
		_dock_was = d
		_choose("lm" if d == "free" else "csm")


## Change vehicles while the LM flies free. Returns whether it did.
func toggle() -> bool:
	if _dock() != "free" or csm_only:
		return false
	_choose("csm" if vehicle == "lm" else "lm")
	return true


func _dock() -> String:
	return str(Bus.get_value("dock.state", ""))


func _choose(v: String) -> void:
	if csm_only:
		v = "csm"
	Bus.set_value("player.vehicle", v)
	if v != vehicle:
		vehicle = v
		changed.emit(v)

## The CSM's docking probe (slice 12a): its three capture latches, which
## catch the LM's drogue at contact, and its retraction, which pulls the
## docking rings together to the twelve ring latches. Apollo 14's capture
## latches failed to engage on five attempts at transposition and docking
## (fail("latches"), the failure catalog's csm_capture_latches): their
## talkbacks showed them cocked, the plunger most probably held by debris.
## The crew docked by holding the probe in the drogue under +X and
## retracting it, and the mechanism worked normally at the lunar orbit's
## undocking and docking [published: MSC-04112, section 14.1.1 and
## p. 7-1]. [simplified: the debris clears at the first hard dock.]
##
## PROBE RETRACT (ctl.seq.probe_retract, pressed) with the probe held in
## the drogue (Dynamics' dock.seated) starts the retraction; retract_s on
## (data/spacecraft.json "docking") the rings are in (dock.probe.retracted)
## and Dynamics docks the vehicles hard, as Apollo 14's first ring latch
## came 4.9 s after its retraction began (MSC-04112, Table 14-I). The
## probe coming out of the drogue stops it.
##
## Reads:  dock.state, dock.seated, ctl.seq.probe_retract
## Writes: dock.probe.latches_failed, dock.retracting, dock.probe.retracted
class_name DockingProbe
extends Node

## The capture latches don't engage.
var latches_failed: bool = false
## When the retraction began, GET s, or -1.
var retract_get: float = -1.0
var _retract_was: bool = false
## The docking's state last step (Dynamics' dock.state).
var _state_was: String = ""


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The failure catalog's [param part] fails: "latches", the capture
## latches.
func fail(part: String) -> void:
	if part == "latches":
		latches_failed = true
	_publish()


## A hard dock, from flying free or at transposition and docking, clears
## the capture latches, and ends the retraction.
func tick(_dt: float) -> void:
	var state := str(Bus.get_value("dock.state", ""))
	if state == "docked" and _state_was in ["free", "tde"]:
		latches_failed = false
	_state_was = state
	var push := bool(Bus.get_value("ctl.seq.probe_retract", false))
	var seated := bool(Bus.get_value("dock.seated", false))
	if push and not _retract_was and seated and retract_get < 0.0:
		retract_get = SimClock.get_seconds
	_retract_was = push
	if not seated or not state in ["free", "tde"]:
		retract_get = -1.0
	_publish()


func _publish() -> void:
	Bus.set_value("dock.probe.latches_failed", latches_failed)
	Bus.set_value("dock.retracting", retract_get >= 0.0)
	Bus.set_value("dock.probe.retracted", retract_get >= 0.0
		and SimClock.get_seconds - retract_get >= float(Docking.params()["retract_s"]) - 1e-6)


func snapshot() -> Dictionary:
	return {"latches_failed": latches_failed, "retract_get": retract_get, "retract_was": _retract_was, "state_was": _state_was}


func restore(d: Dictionary) -> void:
	latches_failed = bool(d.get("latches_failed", false))
	retract_get = float(d.get("retract_get", -1.0))
	_retract_was = bool(d.get("retract_was", false))
	_state_was = str(d.get("state_was", ""))
	_publish()

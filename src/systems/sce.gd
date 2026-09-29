## The signal conditioning equipment (slice 10c): it conditions the CSM's
## sensors' signals for the telemetry the ground reads. Its SCE PWR switch
## (MDC-3, ctl.sce.power: 0 OFF, 1 NORM, 2 AUX) picks the supply it runs
## on. Apollo 12's first lightning strike dropped it out
## (fail("norm"), the failure catalog's sce_norm): at NORM the ground's
## telemetry read nonsense until EECOM's "SCE to AUX" brought it back
## [published: the Apollo 12 Mission Report, MSC-01855, section 7.2.1;
## the switch at NORM for the launch, the Launch Operations Checklist,
## p. L1-5]. [simplified: the onboard displays it also feeds aren't
## modelled, nor the nine measurements the strike lost for good.]
##
## Reads:  ctl.sce.power, sys.powered
## Writes: tm.valid (the ground reads the telemetry), sce.norm_failed
class_name Sce
extends Node

const OFF := 0
const NORM := 1
const AUX := 2

## The NORM supply lost.
var norm_failed: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The failure catalog's [param part] fails: "norm", the NORM supply.
func fail(part: String) -> void:
	if part == "norm":
		norm_failed = true


func tick(_dt: float) -> void:
	_publish()


## The ground reads the spacecraft's telemetry: the SCE runs, on a supply
## it has.
func telemetry() -> bool:
	var power := int(Bus.get_value("ctl.sce.power", NORM))
	return bool(Bus.get_value("sys.powered", false)) and (power == AUX or power == NORM and not norm_failed)


func _publish() -> void:
	Bus.set_value("tm.valid", telemetry())
	Bus.set_value("sce.norm_failed", norm_failed)


func snapshot() -> Dictionary:
	return {"norm_failed": norm_failed}


func restore(d: Dictionary) -> void:
	norm_failed = bool(d.get("norm_failed", false))
	_publish()

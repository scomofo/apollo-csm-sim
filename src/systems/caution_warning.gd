## Caution and warning: the systems' status lights and the master alarm
## [published: CSM Apollo Operations Handbook, SM2A-03-BLOCK II-(1), 2.10.2
## and 2.10.3].
## A status light comes on with its condition and stays on while it holds.
## Each one coming on turns the master alarm on: the MASTER ALARM
## switch-lights and the tone in the crew's headsets (the audio director's).
## Pressing a MASTER ALARM switch-light turns both off and re-arms the
## circuit for the next light, which sounds it again. The unit runs on the
## main buses: with them dead, it is dark.
##
## The lights are the EPS's, the only system with limits yet: FC 1 to FC 3
## (a fuel cell failed [simplified: for the flow, temperature and pH
## limits the handbook lists, ibid., p. 2.10-7]) and MN BUS A and B
## UNDERVOLT.
##
## Reads:  eps.fc1_ok to eps.fc3_ok, eps.bus_a_v, eps.bus_b_v, sys.powered,
##         ctl.cw.master_alarm (a MASTER ALARM switch-light, pressed)
## Writes: cw.<light> (each status light's), sys.master_alarm
class_name CautionWarning
extends Node

## A main bus's undervolt limit, V [published: ibid., p. 2.10-8, 26.25 ±
## 0.1 V dc].
const UNDERVOLT_V := 26.25
const LIGHTS := ["fc1", "fc2", "fc3", "mn_bus_a_undervolt", "mn_bus_b_undervolt"]

## The master alarm: its lights and tone.
var on: bool = false
## Each status light's condition at the last step.
var lights: Dictionary = {}
var _reset_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(_dt: float) -> void:
	var reset := bool(Bus.get_value("ctl.cw.master_alarm", false))
	if reset and not _reset_was:
		on = false
	_reset_was = reset
	for light: String in LIGHTS:
		var lit := _condition(light)
		if lit and not bool(lights.get(light, false)):
			on = true
		lights[light] = lit
	_publish()


func _condition(light: String) -> bool:
	match light:
		"mn_bus_a_undervolt":
			return float(Bus.get_value("eps.bus_a_v", 28.0)) < UNDERVOLT_V
		"mn_bus_b_undervolt":
			return float(Bus.get_value("eps.bus_b_v", 28.0)) < UNDERVOLT_V
	return not bool(Bus.get_value("eps.%s_ok" % light, true))


func _publish() -> void:
	var powered := bool(Bus.get_value("sys.powered", true))
	for light: String in LIGHTS:
		Bus.set_value("cw." + light, powered and bool(lights.get(light, false)))
	Bus.set_value("sys.master_alarm", powered and on)


func snapshot() -> Dictionary:
	return {"on": on, "lights": lights.duplicate()}


func restore(d: Dictionary) -> void:
	on = bool(d["on"])
	lights = d["lights"].duplicate()
	_reset_was = bool(Bus.get_value("ctl.cw.master_alarm", false))
	_publish()

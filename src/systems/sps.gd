## Service Propulsion System: the AJ10-137 engine at the base of the SM.
##
## The engine fires only while at least one DELTA-V THRUST switch (A or B:
## the redundant pilot-valve banks) is NORMAL, the buses are powered, the SM
## is attached and propellant remains, and either the CMC commands it
## (guid.sps_on) or the crew holds THRUST ON (ctl.sps.thrust_on, the manual
## backup). Thrust follows first-order start and shutdown transients.
##
## Reads:  ctl.sps.arm_a, ctl.sps.arm_b, ctl.sps.thrust_on, guid.sps_on,
##         sys.powered, dyn.config
## Writes: sps.thrust_n, sps.prop_kg, sps.chamber_pct, sps.ignitions,
##         sps.burn_time_s, sps.on
extends Node

var prop_kg: float = -1.0
var level: float = 0.0
var ignitions: int = 0
var burn_time: float = 0.0
var _was_on: bool = false


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("sps")["propellant_kg"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func commanded() -> bool:
	var armed := bool(Bus.get_value("ctl.sps.arm_a", false)) or bool(Bus.get_value("ctl.sps.arm_b", false))
	var cmd := bool(Bus.get_value("guid.sps_on", false)) or bool(Bus.get_value("ctl.sps.thrust_on", false))
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	return armed and cmd and prop_kg > 0.0 and bool(Bus.get_value("sys.powered", true)) \
		and (cfg == "csm" or cfg == "csm_lm")


func tick(dt: float) -> void:
	var d := SpacecraftData.section("sps")
	var on := commanded()
	if on and not _was_on:
		ignitions += 1
	_was_on = on
	var tau := float(d["tau_on_s"]) if on else float(d["tau_off_s"])
	var target := 1.0 if on else 0.0
	level += (target - level) * (1.0 - exp(-dt / tau)) if dt > 0.0 else 0.0
	if level < 1e-3 and not on:
		level = 0.0
	if level > 0.0:
		burn_time += dt
		var mdot := float(d["thrust_n"]) / (float(d["isp_s"]) * Units.G0)
		prop_kg = maxf(0.0, prop_kg - mdot * level * dt)
	_publish()


func thrust() -> float:
	return float(SpacecraftData.section("sps")["thrust_n"]) * level


func _publish() -> void:
	Bus.set_value("sps.thrust_n", thrust())
	Bus.set_value("sps.prop_kg", prop_kg)
	Bus.set_value("sps.chamber_pct", level * 100.0)
	Bus.set_value("sps.on", level > 0.05)
	Bus.set_value("sps.ignitions", ignitions)
	Bus.set_value("sps.burn_time_s", burn_time)


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	_was_on = bool(d.get("was_on", false))
	_publish()

## Service Propulsion System: the AJ10-137 engine at the base of the SM.
##
## The engine fires only while at least one DELTA-V THRUST switch (A or B:
## the redundant pilot-valve banks) is NORMAL, the buses are powered, the SM
## is attached and propellant remains, and either the CMC commands it
## (guid.sps_on), the SCS has THRUST ON latched under the EMS's ΔV
## (scs.sps_on, slice 9c), or the crew holds THRUST ON (ctl.sps.thrust_on,
## the manual backup), which the EMS's thrust-off inhibits in ΔV. Thrust
## follows first-order start and shutdown transients.
##
## The gimbal (slice 9c): while the SCS controls the vehicle, its TVC's
## pitch and yaw (scs.gimbal_cmd), within the actuators' ±4.5° and their
## rate [estimated]; otherwise at its trim, the thrust through the centre
## of mass (sps.gimbal_rad zero) [simplified: the CMC steers its burns on
## the jets].
##
## Reads:  ctl.sps.arm_a, ctl.sps.arm_b, ctl.sps.thrust_on, guid.sps_on,
##         scs.sps_on, scs.gimbal_cmd, ems.dv_mode, ems.thrust_off,
##         ctl.scs.att_source, sys.powered, dyn.config
## Writes: sps.thrust_n, sps.prop_kg, sps.chamber_pct, sps.ignitions,
##         sps.burn_time_s, sps.on, sps.gimbal_rad (pitch, yaw)
extends Node

## The gimbal actuators' rate, rad/s [estimated].
const GIMBAL_RATE := 10.0 * PI / 180.0

var prop_kg: float = -1.0
## The gimbal's pitch and yaw from its trim, rad.
var gimbal: Vector2 = Vector2.ZERO
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
	var inhibit := bool(Bus.get_value("ems.dv_mode", false)) and bool(Bus.get_value("ems.thrust_off", false))
	var cmd := bool(Bus.get_value("guid.sps_on", false)) or bool(Bus.get_value("scs.sps_on", false)) \
		or (bool(Bus.get_value("ctl.sps.thrust_on", false)) and not inhibit)
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
	var want := Vector2.ZERO
	if int(Bus.get_value("ctl.scs.att_source", 0)) == 1:
		want = Bus.get_value("scs.gimbal_cmd", Vector2.ZERO)
	var step := GIMBAL_RATE * dt
	gimbal = Vector2(gimbal.x + clampf(want.x - gimbal.x, -step, step), gimbal.y + clampf(want.y - gimbal.y, -step, step))
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
	Bus.set_value("sps.gimbal_rad", gimbal)


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on,
		"gimbal": [gimbal.x, gimbal.y]}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	var g: Array = d.get("gimbal", [0.0, 0.0])
	gimbal = Vector2(g[0], g[1])
	_was_on = bool(d.get("was_on", false))
	_publish()

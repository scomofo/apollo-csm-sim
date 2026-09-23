## Descent Propulsion System: the LM descent stage's throttleable engine.
##
## The engine fires only while the LM flies free with its descent stage,
## the ENGINE ARM switch is at DES, propellant remains, and the LGC
## commands it (lm.guid.dps_on). The LGC also sets the throttle
## (lm.guid.dps_throttle, a fraction of full thrust): the engine throttles
## between throttle_min and throttle_max, and a command above that range
## runs it at full thrust [simplified: the real engine's full-throttle
## position was 92.5 % of its rated thrust]. Thrust follows first-order
## start, throttle and shutdown transients. [simplified: no manual start,
## throttle or gimbal trim; the thrust acts through the centre of mass.]
##
## Reads:  ctl.lm.engine_arm (0 OFF, 1 ASC, 2 DES), lm.guid.dps_on,
##         lm.guid.dps_throttle, lm.sys.powered, lm.dyn.config, dock.state
## Writes: lm.dps.thrust_n, lm.dps.prop_kg, lm.dps.throttle_pct,
##         lm.dps.ignitions, lm.dps.burn_time_s, lm.dps.on
class_name Dps
extends Node

## ctl.lm.engine_arm position that arms the descent engine.
const ARM_DES := 2
## Thrust fraction above which the engine counts as firing (lm.dps.on).
const ON_LEVEL := 0.005

var prop_kg: float = -1.0
## Thrust as a fraction of full thrust.
var level: float = 0.0
var ignitions: int = 0
var burn_time: float = 0.0
var _was_on: bool = false


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("dps")["propellant_kg"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func commanded() -> bool:
	return int(Bus.get_value("ctl.lm.engine_arm", 0)) == ARM_DES and bool(Bus.get_value("lm.guid.dps_on", false)) \
		and prop_kg > 0.0 and bool(Bus.get_value("lm.sys.powered", true)) \
		and str(Bus.get_value("dock.state", "")) == "free" and str(Bus.get_value("lm.dyn.config", "")) == "lm"


## The thrust level the throttle command [param cmd] asks for.
static func throttle_target(cmd: float) -> float:
	var d := SpacecraftData.section("dps")
	var c := maxf(cmd, float(d["throttle_min"]))
	return c if c <= float(d["throttle_max"]) else 1.0


func tick(dt: float) -> void:
	var on := commanded()
	if not on and level == 0.0:
		_was_on = false
		return   # cold: nothing to publish anew
	if on and not _was_on:
		ignitions += 1
	_was_on = on
	var d := SpacecraftData.section("dps")
	var target := throttle_target(float(Bus.get_value("lm.guid.dps_throttle", 0.0))) if on else 0.0
	var tau := float(d["tau_on_s"]) if target > level else float(d["tau_off_s"])
	level += (target - level) * (1.0 - exp(-dt / tau)) if dt > 0.0 else 0.0
	if level < 1e-3 and not on:
		level = 0.0
	if level > 0.0:
		burn_time += dt
		var mdot := float(d["thrust_n"]) / (float(d["isp_s"]) * Units.G0)
		prop_kg = maxf(0.0, prop_kg - mdot * level * dt)
	_publish()


func thrust() -> float:
	return float(SpacecraftData.section("dps")["thrust_n"]) * level


func _publish() -> void:
	Bus.set_value("lm.dps.thrust_n", thrust())
	Bus.set_value("lm.dps.prop_kg", prop_kg)
	Bus.set_value("lm.dps.throttle_pct", level * 100.0)
	Bus.set_value("lm.dps.on", level > ON_LEVEL)
	Bus.set_value("lm.dps.ignitions", ignitions)
	Bus.set_value("lm.dps.burn_time_s", burn_time)


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	_was_on = bool(d.get("was_on", false))
	_publish()

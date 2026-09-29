## Descent Propulsion System: the LM descent stage's throttleable engine.
##
## The engine fires only while the LM's buses are powered with its
## descent stage on (flying free, or docked once its crew has powered it
## up, when it pushes the stack), the ENGINE ARM switch is at DES,
## propellant remains, ENGINE STOP isn't pressed, and the LGC commands it
## (lm.guid.dps_on, with the PGNS in control) or the crew started it
## (ENGINE START, which holds until ENGINE STOP or disarming). The LGC sets
## the throttle (lm.guid.dps_throttle, a fraction of full thrust); started
## by hand, the TTCA's throttle does (ctl.lm.throttle; its minimum, as
## Apollo 13's manual burn had it). The engine throttles between
## throttle_min and throttle_max, and a command above that range runs it
## at full thrust [simplified: the real engine's full-throttle position was
## 92.5 % of its rated thrust]. Thrust follows first-order start, throttle
## and shutdown transients. [simplified: no gimbal trim; the thrust acts
## through the centre of mass.]
##
## Slice 9e: the ABORT pushbutton arms the engine whatever ENG ARM says
## [published: "under abort or emergency conditions, the ABORT and ABORT
## STAGE pushbuttons are used to perform the arming function", LM Apollo
## Operations Handbook, LMA790-3-LM, section 2.1], until the crew sets ENG
## ARM to OFF [simplified: the pushbutton latched in until pressed again].
## ABORT STAGE shuts the engine down at once (Dynamics.stage_lm() leaves
## no descent stage to fire). The tanks' helium regulator holds them at
## he_psia; failed closed (fail("he_reg"), the failure catalog's
## dps_he_reg) the pressure falls as the engine draws its propellant, and
## the thrust with it (spacecraft.json "dps"). lm.dps.low_level is the
## low-level sensors' 5.6 % (DES QTY).
##
## Reads:  ctl.lm.engine_arm (0 OFF, 1 ASC, 2 DES), ctl.lm.eng_start,
##         ctl.lm.eng_stop, ctl.lm.throttle, ctl.lm.guid_cont, ctl.lm.abort,
##         lm.guid.dps_on, lm.guid.dps_throttle, lm.sys.powered,
##         lm.dyn.config, dock.state
## Writes: lm.dps.thrust_n, lm.dps.prop_kg, lm.dps.throttle_pct,
##         lm.dps.ignitions, lm.dps.burn_time_s, lm.dps.on, lm.dps.he_psia,
##         lm.dps.low_level, lm.dps.abort_armed
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
## Armed by the ABORT pushbutton, until ENG ARM goes to OFF.
var abort_armed: bool = false
## The helium regulator failed closed, and the pressure it leaves, psia.
var he_failed: bool = false
var he_psia: float = -1.0
var _was_on: bool = false
## Started by hand (ENGINE START), until ENGINE STOP or disarmed.
var manual: bool = false
var _start_was: bool = false
var _abort_was: bool = false
var _arm_was: int = 0


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("dps")["propellant_kg"])
	if he_psia < 0.0:
		he_psia = float(SpacecraftData.section("dps")["he_psia"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func commanded() -> bool:
	var arm := int(Bus.get_value("ctl.lm.engine_arm", 0))
	var abort := bool(Bus.get_value("ctl.lm.abort", false))
	if abort and not _abort_was or arm == 0 and _arm_was != 0:
		abort_armed = abort and not _abort_was
		Bus.set_value("lm.dps.abort_armed", abort_armed)
	_abort_was = abort
	_arm_was = arm
	var armed := arm == ARM_DES or abort_armed
	var start := bool(Bus.get_value("ctl.lm.eng_start", false))
	if not armed or bool(Bus.get_value("ctl.lm.eng_stop", false)):
		manual = false
	elif start and not _start_was:
		manual = true
	_start_was = start
	var guided := bool(Bus.get_value("lm.guid.dps_on", false)) and int(Bus.get_value("ctl.lm.guid_cont", 0)) == 0
	return armed and (guided or manual) and not bool(Bus.get_value("ctl.lm.eng_stop", false)) \
		and prop_kg > 0.0 and bool(Bus.get_value("lm.sys.powered", false)) \
		and str(Bus.get_value("dock.state", "")) in ["free", "docked"] and str(Bus.get_value("lm.dyn.config", "")) == "lm"


## P40's throttle schedule, [s1, throttle1, s2, throttle2, ..., throttle]:
## each throttle for its seconds after the last step, from ignition, then
## the last to the cutoff, each a fraction of full thrust (one above the
## throttleable range is full thrust). [param pad]'s, a PAD's own (Apollo
## 10's phasing burn: 26 s at 10 %, then full; Apollo 13's PC+2: 5 s at
## 12.6 %, 21 s at 40 %, then full), or given none spacecraft.json's
## (Apollo 11's DOI: 15 s at 10 %, then 40 %).
static func p40_schedule(pad: Array = []) -> Array:
	if pad.size() >= 3 and pad.size() % 2 == 1:
		return pad.map(func(v: Variant) -> float: return float(v))
	var d := SpacecraftData.section("dps")
	return [float(d["p40_start_s"]), float(d["p40_start_throttle"]), float(d["p40_throttle"])]


## The throttle schedule [param sch] (p40_schedule()) commands
## [param t] seconds after ignition.
static func schedule_throttle(sch: Array, t: float) -> float:
	var end := 0.0
	for i in range(0, sch.size() - 1, 2):
		end += float(sch[i])
		if t < end:
			return float(sch[i + 1])
	return float(sch[-1])


## When the throttle schedule [param sch] next changes after [param t]
## seconds from ignition, s; INF after its last step.
static func schedule_next(sch: Array, t: float) -> float:
	var end := 0.0
	for i in range(0, sch.size() - 1, 2):
		end += float(sch[i])
		if t < end:
			return end
	return INF


## The thrust level the throttle command [param cmd] asks for.
static func throttle_target(cmd: float) -> float:
	var d := SpacecraftData.section("dps")
	var c := maxf(cmd, float(d["throttle_min"]))
	return c if c <= float(d["throttle_max"]) else 1.0


## Fail [param part]: "he_reg", the tanks' helium regulator, closed.
func fail(part: String) -> void:
	if part == "he_reg":
		he_failed = true


## The thrust the tanks' pressure leaves, a fraction of the throttle's.
func _pressure_factor() -> float:
	var d := SpacecraftData.section("dps")
	var lo := float(d["he_min_psia"])
	return clampf((he_psia - lo) / (float(d["he_psia"]) - lo), 0.0, 1.0)


func tick(dt: float) -> void:
	var on := commanded()
	if not on and level == 0.0:
		_was_on = false
		return   # cold: nothing to publish anew
	if on and not _was_on:
		ignitions += 1
	_was_on = on
	var d := SpacecraftData.section("dps")
	var cmd := float(Bus.get_value("ctl.lm.throttle" if manual else "lm.guid.dps_throttle", 0.0))
	var target := throttle_target(cmd) if on else 0.0
	var tau := float(d["tau_on_s"]) if target > level else float(d["tau_off_s"])
	level += (target - level) * (1.0 - exp(-dt / tau)) if dt > 0.0 else 0.0
	if level < 1e-3 and not on:
		level = 0.0
	if level > 0.0:
		burn_time += dt
		var mdot := float(d["thrust_n"]) / (float(d["isp_s"]) * Units.G0)
		var draw := level * _pressure_factor()
		prop_kg = maxf(0.0, prop_kg - mdot * draw * dt)
		if he_failed:
			he_psia = maxf(float(d["he_min_psia"]), he_psia - float(d["he_decay_psi_s"]) * draw * dt)
	_publish()


func thrust() -> float:
	return float(SpacecraftData.section("dps")["thrust_n"]) * level * _pressure_factor()


func _publish() -> void:
	var d := SpacecraftData.section("dps")
	Bus.set_value("lm.dps.thrust_n", thrust())
	Bus.set_value("lm.dps.prop_kg", prop_kg)
	Bus.set_value("lm.dps.throttle_pct", level * _pressure_factor() * 100.0)
	Bus.set_value("lm.dps.on", level * _pressure_factor() > ON_LEVEL)
	Bus.set_value("lm.dps.ignitions", ignitions)
	Bus.set_value("lm.dps.burn_time_s", burn_time)
	Bus.set_value("lm.dps.he_psia", he_psia)
	Bus.set_value("lm.dps.low_level", prop_kg <= float(d["low_level_fraction"]) * float(d["propellant_kg"]))
	Bus.set_value("lm.dps.abort_armed", abort_armed)


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on,
		"manual": manual, "abort_armed": abort_armed, "he_failed": he_failed, "he_psia": he_psia,
		"abort_was": _abort_was, "arm_was": _arm_was}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	_was_on = bool(d.get("was_on", false))
	manual = bool(d.get("manual", false))
	abort_armed = bool(d.get("abort_armed", false))
	he_failed = bool(d.get("he_failed", false))
	he_psia = float(d.get("he_psia", SpacecraftData.section("dps")["he_psia"]))
	_abort_was = bool(d.get("abort_was", false))
	_arm_was = int(d.get("arm_was", 0))
	_publish()

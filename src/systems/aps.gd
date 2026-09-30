## Ascent Propulsion System: the LM ascent stage's fixed-thrust engine.
##
## The engine fires only while the ascent stage flies free (after
## staging, on the surface too), the ENGINE ARM switch is at ASC,
## propellant remains, ENGINE STOP isn't pressed, and the LGC commands it
## (lm.guid.aps_on, with the guidance control switch at PGNS), or the AGS
## does (lm.ags.engine_on, at AGS; slice 11e), or the crew started it
## (ENGINE START, which holds until ENGINE STOP or disarming). Thrust follows first-order start and
## shutdown transients. [simplified: the thrust acts through the centre of
## mass.]
##
## Slice 9e: the ABORT STAGE pushbutton arms the engine whatever ENG ARM
## says [published: LM Apollo Operations Handbook, LMA790-3-LM, section
## 2.1], until the crew sets ENG ARM to OFF [simplified: the pushbutton
## latched in until pressed again]; the LGC's P71 then fires it. [The
## hardware's sequence staged the LM as the ascent engine's on command
## came, after a delay that let the descent engine's thrust die away
## (ibid.); here the LM stages as the button is pressed.]
##
## Reads:  ctl.lm.engine_arm (0 OFF, 1 ASC, 2 DES), ctl.lm.eng_start,
##         ctl.lm.eng_stop, ctl.lm.stage (ABORT STAGE), lm.guid.aps_on,
##         ctl.lm.guid_cont, lm.ags.engine_on,
##         lm.sys.powered, lm.dyn.config, dock.state
## Writes: lm.aps.thrust_n, lm.aps.prop_kg, lm.aps.chamber_pct,
##         lm.aps.ignitions, lm.aps.burn_time_s, lm.aps.on,
##         lm.aps.abort_armed
extends Node

## ctl.lm.engine_arm position that arms the ascent engine.
const ARM_ASC := 1

var prop_kg: float = -1.0
var level: float = 0.0
var ignitions: int = 0
var burn_time: float = 0.0
## Armed by the ABORT STAGE pushbutton, until ENG ARM goes to OFF.
var abort_armed: bool = false
var _was_on: bool = false
## Started by hand (ENGINE START), until ENGINE STOP or disarmed.
var manual: bool = false
var _start_was: bool = false
var _stage_was: bool = false
var _arm_was: int = 0


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("aps")["propellant_kg"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func commanded() -> bool:
	var arm := int(Bus.get_value("ctl.lm.engine_arm", 0))
	var stage := bool(Bus.get_value("ctl.lm.stage", false))
	if stage and not _stage_was or arm == 0 and _arm_was != 0:
		abort_armed = stage and not _stage_was
		Bus.set_value("lm.aps.abort_armed", abort_armed)
	_stage_was = stage
	_arm_was = arm
	var armed := arm == ARM_ASC or abort_armed
	var start := bool(Bus.get_value("ctl.lm.eng_start", false))
	if not armed or bool(Bus.get_value("ctl.lm.eng_stop", false)):
		manual = false
	elif start and not _start_was:
		manual = true
	_start_was = start
	var pgns := int(Bus.get_value("ctl.lm.guid_cont", 0)) == 0
	var guided := bool(Bus.get_value("lm.guid.aps_on" if pgns else "lm.ags.engine_on", false))
	return armed and (guided or manual) and not bool(Bus.get_value("ctl.lm.eng_stop", false)) \
		and prop_kg > 0.0 and bool(Bus.get_value("lm.sys.powered", true)) \
		and str(Bus.get_value("dock.state", "")) == "free" and str(Bus.get_value("lm.dyn.config", "")) == "lm_ascent"


func tick(dt: float) -> void:
	var on := commanded()
	if not on and level == 0.0:
		_was_on = false
		return   # cold: nothing to publish anew
	if on and not _was_on:
		ignitions += 1
	_was_on = on
	var d := SpacecraftData.section("aps")
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
	return float(SpacecraftData.section("aps")["thrust_n"]) * level


func _publish() -> void:
	Bus.set_value("lm.aps.thrust_n", thrust())
	Bus.set_value("lm.aps.prop_kg", prop_kg)
	Bus.set_value("lm.aps.chamber_pct", level * 100.0)
	Bus.set_value("lm.aps.on", level > 0.05)
	Bus.set_value("lm.aps.ignitions", ignitions)
	Bus.set_value("lm.aps.burn_time_s", burn_time)
	Bus.set_value("lm.aps.abort_armed", abort_armed)


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on,
		"manual": manual, "abort_armed": abort_armed, "stage_was": _stage_was, "arm_was": _arm_was}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	_was_on = bool(d.get("was_on", false))
	manual = bool(d.get("manual", false))
	abort_armed = bool(d.get("abort_armed", false))
	_stage_was = bool(d.get("stage_was", false))
	_arm_was = int(d.get("arm_was", 0))
	_publish()

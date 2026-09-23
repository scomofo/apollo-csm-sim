## LM Guidance Computer (LGC) with its DSKY: the Luminary programs for the
## LM's burns in lunar orbit, on the AGC core the CMC shares
## (src/systems/agc_core.gd). It reads the LM's truth and writes its own
## channels: lm.dyn.* in, lm.guid.* and lm.dsky.* out.
##
##   P00  LGC idling
##   P30  External ΔV (the DOI PAD's TIG and ΔV)
##   P40  DPS thrusting: the engine starts at 10 % throttle and burns at
##        40 % after 15 s, as Apollo 11's DOI did [simplified: the crew
##        throttled up by hand]
##   P41  RCS thrusting: +X translation on the LM RCS
##   P42  APS thrusting (the ascent stage, after staging)
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##
## The LGC runs while the LM flies free [simplified: the LM powers up as it
## undocks; docked, and after LM JETT, the LGC is dark and the CSM flies
## the stack].
##
## Digital autopilot: ctl.lm.mode 0 FREE, 1 HOLD, 2 AUTO, as the CMC's,
## with the ACA (ctl.lm.rhc) about the LM's X, Y and Z axes: the LM crew's
## yaw, pitch and roll [simplified: the LM's PGNS MODE CONTROL is OFF,
## ATT HOLD and AUTO; no AGS]. Powering up, it holds the attitude the LM
## has.
##
## Writes: the core's channels under lm. (lm.guid.*, lm.dsky.*),
##         lm.guid.dps_on, lm.guid.dps_throttle, lm.guid.aps_on
class_name Lgc
extends AgcCore


func _init() -> void:
	super()
	prefix = "lm."


func programs() -> Array:
	return [0, 30, 40, 41, 42, 47]


func thrusting_programs() -> Array:
	return [40, 41, 42]


func engine_thrust(p: int) -> float:
	if p == 42:
		return float(SpacecraftData.section("aps")["thrust_n"])
	return float(SpacecraftData.section("dps")["thrust_n"]) * Dps.throttle_target(throttle())


func engine_tau_off(p: int) -> float:
	return float(SpacecraftData.section("aps" if p == 42 else "dps")["tau_off_s"])


func engine_running() -> bool:
	return bool(Bus.get_value("lm.dps.on", false)) or bool(Bus.get_value("lm.aps.on", false))


func publish_engine(on: bool) -> void:
	Bus.set_value("lm.guid.dps_on", on and program == 40)
	Bus.set_value("lm.guid.dps_throttle", throttle())
	Bus.set_value("lm.guid.aps_on", on and program == 42)


## The DPS throttle P40 commands, a fraction of full thrust: the start
## throttle for p40_start_s after ignition, then the burn throttle.
func throttle() -> float:
	var d := SpacecraftData.section("dps")
	if ignition_get < 0.0 or _now() - ignition_get < float(d["p40_start_s"]):
		return float(d["p40_start_throttle"])
	return float(d["p40_throttle"])


func mode() -> int:
	return int(Bus.get_value("ctl.lm.mode", 1))


func rhc() -> Vector3:
	return Bus.get_value("ctl.lm.rhc", Vector3.ZERO)


func is_powered() -> bool:
	return _free() and bool(Bus.get_value("lm.sys.powered", true))


## The DAP takes up the attitude the LM has as its hold.
func powered_up() -> void:
	_last_source = -1


func authority() -> Vector3:
	var cfg := str(Bus.get_value("lm.dyn.config", "lm"))
	var mass := float(Bus.get_value("lm.dyn.mass_kg", SpacecraftData.lm_mass()))
	var inertia := SpacecraftData.inertia(cfg if cfg in SpacecraftData.LM_CONFIGS else "lm", mass)
	var d := SpacecraftData.section("lm_rcs")
	# Both systems' jets about each axis.
	var t := float(d["jet_thrust_n"]) * float(d["arm_m"]) * float(d["rotation_jets"]) * 2.0
	return Vector3(t / inertia.x, t / inertia.y, t / inertia.z)


## The LM's accelerometers count only while it flies free.
func sense(dt: float) -> void:
	if _free():
		super.sense(dt)


func _free() -> bool:
	return str(Bus.get_value("dock.state", "")) == "free"

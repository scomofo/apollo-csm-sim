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
## The gimbal (slices 9c and 12c): while the SCS controls the vehicle, its
## TVC's pitch and yaw (scs.gimbal_cmd), within the actuators' ±4.5° and
## their rate [estimated]; otherwise at its trim, the thrust through the
## centre of mass (zero) [simplified: the CMC steers its burns on the
## jets]. Two servo loops drive each actuator, pitch and yaw, each with its
## own gimbal motor and clutches and its own position and rate transducers
## [published: AOH SM2A-03-BLOCK II-(1), pp. 2.4-14 to 2.4-17 and 2.3-41 to
## 2.3-44]. SPS GIMBAL MOTORS PITCH 1, YAW 1, PITCH 2 and YAW 2 (MDC-1)
## start each loop's motor (START, sprung back to ON) or stop it (OFF);
## TVC GMBL DRIVE PITCH and YAW pick the loop that drives, 1 or 2, or at
## AUTO loop 1, loop 2 with the THC clockwise [simplified: no fail sense
## from a motor's overcurrent, and the TVC servo power switches on MDC-7
## on]. A loop whose motor is stopped leaves the gimbal where it stands.
## The GPI shows the gimbal as the driving loop's position transducer reads
## it (sps.gpi_p_deg and sps.gpi_y_deg).
##
## The failure catalog's sps_yaw_servo_2 (slice 12c, Apollo 16's) opens
## loop yaw 2's rate feedback (fail("y2_rate")): with nothing to damp it,
## the loop overshoots its command at the actuator's rate each way, a limit
## cycle of ±1.0° at 2.4 Hz about it once a command moves the gimbal, which
## builds to that and holds [published: MSC-07230, section 14.1.10; its
## build-up estimated]: the rate-limited triangle at 2.4 Hz is ±1.04°, the
## flight's "slightly greater than ±1 degree" [derived]. The thrust's side
## load on the bell damps it in a few seconds [published: ibid., by
## simulation; its time constant estimated]. It is kept as its amplitude,
## its phase the clock's, so a coast step doesn't lose it.
##
## Reads:  ctl.sps.arm_a, ctl.sps.arm_b, ctl.sps.thrust_on, guid.sps_on,
##         scs.sps_on, scs.gimbal_cmd, ems.dv_mode, ems.thrust_off,
##         ctl.scs.att_source, ctl.thc_cw, ctl.sps.gmbl_<loop> (0 OFF,
##         1 ON, 2 START), ctl.scs.tvc_drive_p and _y (0 AUTO, 1, 2),
##         sys.powered, dyn.config
## Writes: sps.thrust_n, sps.prop_kg, sps.chamber_pct, sps.ignitions,
##         sps.burn_time_s, sps.on, sps.gimbal_rad (pitch, yaw), sps.gpi_p_deg,
##         sps.gpi_y_deg, sps.motor_<loop> (its gimbal motor running),
##         sps.motors_on (how many are),
##         sps.tvc_loops (the loop driving pitch and yaw, 0 for none),
##         sps.rate_open (the loops whose rate feedback has failed, by name,
##         comma-separated)
class_name Sps
extends Node

## The gimbal actuators' rate, rad/s [estimated].
const GIMBAL_RATE := 10.0 * PI / 180.0
## The servo loops, by their gimbal motors' names: pitch 1, yaw 1, pitch
## 2, yaw 2.
const LOOPS := ["p1", "y1", "p2", "y2"]
## A failed rate feedback's limit cycle: its amplitude, rad, and frequency,
## Hz [published: MSC-07230, section 14.1.10].
const CYCLE_AMP := 1.0 * PI / 180.0
const CYCLE_HZ := 2.4
## How fast a disturbed loop's oscillation builds to it, and how fast the
## thrust damps it, s [estimated: "divergent" in the crew's first checks,
## damped "in a few seconds"].
const CYCLE_GROW_S := 1.0
const CYCLE_DAMP_S := 1.5
## The command's move that sets it off, rad [estimated].
const CYCLE_KICK := 0.01 * PI / 180.0

var prop_kg: float = -1.0
## The gimbal's pitch and yaw from its null, rad, the actuators' rams
## without the limit cycle.
var gimbal: Vector2 = Vector2.ZERO
## Each loop's gimbal motor running, in LOOPS's order.
var motors: Array[bool] = [false, false, false, false]
## The loops whose rate feedback has failed, by LOOPS's names.
var rate_open: Array[String] = []
## The limit cycle's amplitude in pitch and yaw, rad.
var cycle: Vector2 = Vector2.ZERO
var level: float = 0.0
var ignitions: int = 0
var burn_time: float = 0.0
var _was_on: bool = false
var _want_was: Vector2 = Vector2.ZERO


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
	_motors()
	_drive(dt)
	if level > 0.0:
		burn_time += dt
		var mdot := float(d["thrust_n"]) / (float(d["isp_s"]) * Units.G0)
		prop_kg = maxf(0.0, prop_kg - mdot * level * dt)
	_publish()


func thrust() -> float:
	return float(SpacecraftData.section("sps")["thrust_n"]) * level


## The loop driving pitch (x) and yaw (y), 1 or 2, or 0 where the one TVC
## GMBL DRIVE picks has its motor stopped.
func driving() -> Vector2i:
	var cw := bool(Bus.get_value("ctl.thc_cw", false))
	var out := Vector2i.ZERO
	for a in 2:
		var sw := int(Bus.get_value("ctl.scs.tvc_drive_" + ["p", "y"][a], 0))
		var loop := sw if sw in [1, 2] else (2 if cw else 1)
		out[a] = loop if motors[a + 2 * (loop - 1)] else 0
	return out


## The gimbal as the GPI shows it, pitch and yaw, rad: the rams and the
## limit cycle's swing about them now.
func position() -> Vector2:
	return gimbal + cycle * sin(TAU * CYCLE_HZ * SimClock.get_seconds)


## Fail [param part]: "<loop>_rate", a loop's rate feedback open.
func fail(part: String) -> void:
	var loop := part.trim_suffix("_rate")
	if part.ends_with("_rate") and loop in LOOPS and not loop in rate_open:
		rate_open.append(loop)
	_publish()


## SPS GIMBAL MOTORS: START starts a loop's motor on the powered buses, OFF
## stops it, ON keeps it as it is.
func _motors() -> void:
	var powered := bool(Bus.get_value("sys.powered", true))
	for i in LOOPS.size():
		match int(Bus.get_value("ctl.sps.gmbl_" + LOOPS[i], 0)):
			0:
				motors[i] = false
			2:
				motors[i] = powered
		if not powered:
			motors[i] = false


## Each loop that drives takes its axis toward the command at the
## actuator's rate: the SCS's under the SCS, the null under the CMC. A loop
## with its rate feedback open swings about it.
func _drive(dt: float) -> void:
	var want := Vector2.ZERO
	if Scs.sc_cont() == 1:
		want = Bus.get_value("scs.gimbal_cmd", Vector2.ZERO)
	var loops := driving()
	var step := GIMBAL_RATE * dt
	for a in 2:
		if loops[a] == 0:
			cycle[a] = 0.0
			continue
		var moving := absf(want[a] - gimbal[a]) > 1e-6 or absf(want[a] - _want_was[a]) > CYCLE_KICK
		gimbal[a] += clampf(want[a] - gimbal[a], -step, step)
		if not LOOPS[a + 2 * (loops[a] - 1)] in rate_open:
			cycle[a] = 0.0
		elif level > 0.05:
			cycle[a] *= exp(-dt / CYCLE_DAMP_S)
		elif cycle[a] > 0.0 or moving:
			cycle[a] = maxf(cycle[a], CYCLE_KICK)
			cycle[a] += (CYCLE_AMP - cycle[a]) * (1.0 - exp(-dt / CYCLE_GROW_S))
	_want_was = want


func _publish() -> void:
	Bus.set_value("sps.thrust_n", thrust())
	Bus.set_value("sps.prop_kg", prop_kg)
	Bus.set_value("sps.chamber_pct", level * 100.0)
	Bus.set_value("sps.on", level > 0.05)
	Bus.set_value("sps.ignitions", ignitions)
	Bus.set_value("sps.burn_time_s", burn_time)
	var at := position()
	Bus.set_value("sps.gimbal_rad", at)
	Bus.set_value("sps.gpi_p_deg", rad_to_deg(at.x))
	Bus.set_value("sps.gpi_y_deg", rad_to_deg(at.y))
	for i in LOOPS.size():
		Bus.set_value("sps.motor_" + LOOPS[i], motors[i])
	Bus.set_value("sps.motors_on", motors.count(true))
	Bus.set_value("sps.tvc_loops", driving())
	Bus.set_value("sps.rate_open", ",".join(rate_open))


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "level": level, "ignitions": ignitions, "burn_time": burn_time, "was_on": _was_on,
		"gimbal": [gimbal.x, gimbal.y], "motors": motors.duplicate(), "rate_open": rate_open.duplicate(),
		"cycle": [cycle.x, cycle.y], "want_was": [_want_was.x, _want_was.y]}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	level = float(d["level"])
	ignitions = int(d["ignitions"])
	burn_time = float(d["burn_time"])
	var g: Array = d.get("gimbal", [0.0, 0.0])
	gimbal = Vector2(g[0], g[1])
	_was_on = bool(d.get("was_on", false))
	for i in LOOPS.size():
		motors[i] = bool(d["motors"][i])
	rate_open.assign(d["rate_open"])
	cycle = Vector2(d["cycle"][0], d["cycle"][1])
	_want_was = Vector2(d["want_was"][0], d["want_was"][1])
	_publish()

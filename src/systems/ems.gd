## The Entry Monitor System (slice 9c): the CSM's own ΔV counter and entry
## monitor, on its one sensor, an accelerometer along the X axis
## [published: CSM Apollo Operations Handbook, SM2A-03-BLOCK II-(1),
## section 2.3.7].
##
## FUNCTION (ctl.ems.function): 0 OFF, 1 ΔV SET, 2 ΔV, 3 RNG SET, 4 V0 SET,
## 5 ENTRY [simplified: the switch's twelve positions to these six; its
## self-tests and VHF ranging, and the MODE switch, left out].
## The ΔV/EMS SET rocker (ctl.ems.set: -2 and -1 the hard and soft DECR,
## +1 and +2 INCR, springing back to 0) changes the display in ΔV SET and
## RNG SET 0.25 units a second at the soft stop and 127.5 at the hard, and
## in V0 SET slews the scroll 30 ft/s a second soft and 480 hard
## [published: ibid., pp. 2.3-57 and 2.3-58].
##
## ΔV: the display (ft/s, from 14,000.0 down to -1,000.0, to a tenth)
## counts down with the ΔV the accelerometer senses along +X and up along
## -X; at -0.1 ft/s the EMS gives the SCS its thrust-off, and THRUST ON
## starts nothing below zero [published: ibid., p. 2.3-56].
##
## ENTRY: the 0.05 G light comes on when the accelerometer reads 0.05 g for
## a second (the scan reads "1 ± 0.5 seconds"), and goes out below 0.02 g.
## From it the scroll's velocity counts down from V0 by the ΔV sensed, its
## G axis follows the g read, and the range display counts down from the
## range set by that velocity. 10 s after 0.05 G the corridor lights say
## which way the lift must point: the upper over 0.262 g, the lower under;
## they go out when the G axis passes 2 g [published: ibid., pp. 2.3-53 to
## 2.3-55 and 2.3-60 to 2.3-61]. The scroll's trace keeps a point (V, G) a
## second [simplified: the roll stability indicator left out].
##
## Reads:  ctl.ems.function, ctl.ems.set, dyn.dv_step, dyn.att_q,
##         sys.powered
## Writes: ems.display (the ΔV/RANGE display: ft/s or nmi), ems.dv_mode,
##         ems.thrust_off, ems.lamp_05g, ems.corridor_up,
##         ems.corridor_down, ems.v_fps (the scroll's velocity), ems.g (its
##         G axis), ems.range_nmi
class_name Ems
extends Node

enum Function { OFF, DV_SET, DV, RNG_SET, V0_SET, ENTRY }

const DV_MAX := 14000.0
const DV_MIN := -1000.0
## The thrust-off point, ft/s.
const THRUST_OFF_FPS := -0.1
## ΔV/EMS SET's rates: the display's, units a second, and the scroll's,
## ft/s a second, at the soft and hard stops.
const SET_RATE := [0.25, 127.5]
const SCROLL_RATE := [30.0, 480.0]
const G05 := 0.05
const G05_OFF := 0.02
const G05_HOLD_S := 1.0
const CORRIDOR_S := 10.0
const CORRIDOR_G := 0.262
const CORRIDOR_OFF_G := 2.0
const G0_FPS2 := 32.174

## The ΔV counter, ft/s.
var dv: float = 0.0
## The range to go, nmi.
var range_nmi: float = 0.0
## The scroll's velocity, ft/s.
var v: float = 0.0
## The G axis, g.
var g: float = 0.0
var lamp_05g: bool = false
var corridor_up: bool = false
var corridor_down: bool = false
## From 0.05 G: the time it has been on, s, and the time above it before,
## s.
var entry_s: float = -1.0
## The scroll's trace: [V (ft/s), G] a second from 0.05 G.
var trace: Array = []
var _above_s: float = 0.0
var _corridor_done: bool = false
var _trace_s: float = 0.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func function() -> int:
	return int(Bus.get_value("ctl.ems.function", Function.OFF))


func tick(dt: float) -> void:
	var fn := function()
	if fn == Function.OFF or not bool(Bus.get_value("sys.powered", true)):
		_publish()
		return
	var sw := int(Bus.get_value("ctl.ems.set", 0))
	var hard := 1 if absi(sw) == 2 else 0
	var dir := signi(sw)
	match fn:
		Function.DV_SET:
			dv = clampf(dv + dir * float(SET_RATE[hard]) * dt, DV_MIN, DV_MAX)
		Function.RNG_SET:
			range_nmi = clampf(range_nmi + dir * float(SET_RATE[hard]) * dt, DV_MIN, DV_MAX)
		Function.V0_SET:
			v = maxf(v + dir * float(SCROLL_RATE[hard]) * dt, 0.0)
	var ax := sensed_x() / Units.FT
	match fn:
		Function.DV:
			dv = clampf(dv - ax, DV_MIN, DV_MAX)
		Function.ENTRY:
			_entry(dt, ax)
	_publish()


## The ΔV the accelerometer sensed along +X in the last step, m/s.
static func sensed_x() -> float:
	var d: Array = Bus.get_value("dyn.dv_step", [0.0, 0.0, 0.0])
	var att: Quaternion = Bus.get_value("dyn.att_q", Quaternion.IDENTITY)
	return (Basis(att).inverse() * Vector3(d[0], d[1], d[2])).x


func _entry(dt: float, dv_fps: float) -> void:
	var gee := dv_fps / (G0_FPS2 * dt) if dt > 0.0 else 0.0
	if entry_s < 0.0:
		_above_s = _above_s + dt if gee >= G05 else 0.0
		if _above_s >= G05_HOLD_S:
			entry_s = 0.0
			lamp_05g = true
		return
	entry_s += dt
	lamp_05g = gee >= G05_OFF
	g = maxf(gee, 0.0)
	v = maxf(v - dv_fps, 0.0)
	range_nmi -= v * Units.FT / 1852.0 * dt
	if not _corridor_done and entry_s >= CORRIDOR_S:
		_corridor_done = true
		corridor_up = g > CORRIDOR_G
		corridor_down = not corridor_up
	if g > CORRIDOR_OFF_G:
		corridor_up = false
		corridor_down = false
	_trace_s += dt
	if _trace_s >= 1.0 or trace.is_empty():
		_trace_s = 0.0
		trace.append([v, g])


## The display: the ΔV counter or the range.
func display() -> float:
	return range_nmi if function() in [Function.RNG_SET, Function.ENTRY] else dv


func _publish() -> void:
	var on := function() != Function.OFF and bool(Bus.get_value("sys.powered", true))
	Bus.set_value("ems.display", display() if on else 0.0)
	Bus.set_value("ems.dv_mode", on and function() == Function.DV)
	Bus.set_value("ems.thrust_off", on and function() == Function.DV and dv < THRUST_OFF_FPS)
	Bus.set_value("ems.lamp_05g", on and lamp_05g)
	Bus.set_value("ems.corridor_up", on and corridor_up)
	Bus.set_value("ems.corridor_down", on and corridor_down)
	Bus.set_value("ems.v_fps", v)
	Bus.set_value("ems.g", g)
	Bus.set_value("ems.range_nmi", range_nmi)


func snapshot() -> Dictionary:
	return {"dv": dv, "range": range_nmi, "v": v, "g": g, "lamp": lamp_05g, "up": corridor_up, "down": corridor_down,
		"entry_s": entry_s, "above_s": _above_s, "corridor_done": _corridor_done, "trace": trace.duplicate(true),
		"trace_s": _trace_s}


func restore(d: Dictionary) -> void:
	dv = float(d.get("dv", 0.0))
	range_nmi = float(d.get("range", 0.0))
	v = float(d.get("v", 0.0))
	g = float(d.get("g", 0.0))
	lamp_05g = bool(d.get("lamp", false))
	corridor_up = bool(d.get("up", false))
	corridor_down = bool(d.get("down", false))
	entry_s = float(d.get("entry_s", -1.0))
	_above_s = float(d.get("above_s", 0.0))
	_corridor_done = bool(d.get("corridor_done", false))
	trace = (d.get("trace", []) as Array).duplicate(true)
	_trace_s = float(d.get("trace_s", 0.0))
	_publish()

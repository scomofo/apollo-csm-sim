## The CSM's optics at the lower equipment bay: the sextant (SXT, 28 power,
## a FIELD_SXT_DEG field) and the scanning telescope (SCT, unity power, a
## FIELD_SCT_DEG field), on one line of sight, the star line [simplified:
## the SCT's own trunnion is left out]. The shaft turns the star line about
## the shaft axis, and the trunnion tilts it away from that axis, up to
## TRUNNION_MAX_DEG. The shaft axis lies in the body's X-Z plane,
## SHAFT_TILT_DEG from +Z toward +X: the optics look out of the CM's side,
## below the crew's feet.
##
## The sextant's second line of sight, the landmark line, lies along the
## shaft axis (landmark_line()), and its image lies over the star line's:
## the star line's image axes are the landmark line's turned about the
## trunnion axis by the trunnion angle. So with a star's image laid on a
## horizon's or a landmark's, the trunnion angle is the angle between them,
## however the CSM points, which P23 reads to SEXTANT_READ_DEG.
##
## ctl.optics.zero drives both angles to zero. Otherwise ctl.optics.mode 0
## (MANUAL) follows the optics hand controller (ctl.optics.hc: x the shaft,
## y the trunnion, each -1..1) at the rate ctl.optics.speed sets (0 LO,
## 1 MED, 2 HI), and 1 (CMC) drives them to the computer's command
## (guid.optics.cmd_deg: shaft, trunnion, while guid.optics.cmd is true) at
## DRIVE_DEG_S. The computer reads MARK and MARK REJECT itself.
##
## Reads:  ctl.optics.zero, ctl.optics.mode, ctl.optics.speed,
##         ctl.optics.hc, guid.optics.cmd, guid.optics.cmd_deg, sys.powered
## Writes: optics.shaft_deg, optics.trunnion_deg, optics.los_body (the line
##         of sight, a unit vector in body axes), optics.mode ("zero",
##         "manual", "cmc")
class_name Optics
extends Node

const SHAFT_TILT_DEG := 32.523
const TRUNNION_MAX_DEG := 57.5
const FIELD_SXT_DEG := 1.8
const FIELD_SCT_DEG := 60.0
## The sextant angle's reading, deg [estimated: about 7 arc seconds].
const SEXTANT_READ_DEG := 0.002
## Full deflection's rate at each OPTICS SPEED, deg/s [estimated].
const HC_RATES_DEG_S := [0.05, 0.5, 5.0]
## The CMC and ZERO drive rate, deg/s [estimated].
const DRIVE_DEG_S := 10.0

var shaft_deg: float = 0.0
var trunnion_deg: float = 0.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The line of sight for [param shaft] and [param trunnion] (deg), a unit
## vector in body axes.
static func los(shaft: float, trunnion: float) -> Vector3:
	var s := deg_to_rad(shaft)
	var t := deg_to_rad(trunnion)
	var o := Vector3(sin(t) * cos(s), sin(t) * sin(s), cos(t))
	return Basis(Vector3(0, 1, 0), deg_to_rad(SHAFT_TILT_DEG)) * o


## The sextant's landmark line: the shaft axis, a unit vector in body axes.
static func landmark_line() -> Vector3:
	return los(0.0, 0.0)


## The shaft and trunnion angles (deg: shaft 0-360, trunnion 0-180) that
## look along [param dir] (body axes).
static func angles_for(dir: Vector3) -> Vector2:
	var o := Basis(Vector3(0, 1, 0), -deg_to_rad(SHAFT_TILT_DEG)) * dir.normalized()
	var t := rad_to_deg(acos(clampf(o.z, -1.0, 1.0)))
	var s := fposmod(rad_to_deg(atan2(o.y, o.x)), 360.0) if t > 1e-9 else 0.0
	return Vector2(s, t)


## The view through the optics at [param shaft], [param trunnion]: body
## axes of its right (growing shaft) and its up (growing trunnion), and the
## line of sight.
static func view_axes(shaft: float, trunnion: float) -> Array:
	var s := deg_to_rad(shaft)
	var t := deg_to_rad(trunnion)
	var tilt := Basis(Vector3(0, 1, 0), deg_to_rad(SHAFT_TILT_DEG))
	var right := tilt * Vector3(-sin(s), cos(s), 0.0)
	var up := tilt * Vector3(cos(t) * cos(s), cos(t) * sin(s), -sin(t))
	return [right, up, los(shaft, trunnion)]


func line_of_sight() -> Vector3:
	return los(shaft_deg, trunnion_deg)


## Point the optics at [param dir] (body axes), as the crew centres a star.
func aim(dir: Vector3) -> void:
	var a := angles_for(dir)
	shaft_deg = a.x
	trunnion_deg = clampf(a.y, 0.0, TRUNNION_MAX_DEG)
	_publish()


func mode_name() -> String:
	if bool(Bus.get_value("ctl.optics.zero", false)):
		return "zero"
	return "cmc" if int(Bus.get_value("ctl.optics.mode", 1)) == 1 else "manual"


func tick(dt: float) -> void:
	if not bool(Bus.get_value("sys.powered", true)):
		_publish()
		return
	match mode_name():
		"zero":
			_drive_to(0.0, 0.0, dt)
		"cmc":
			if bool(Bus.get_value("guid.optics.cmd", false)):
				var c: Vector3 = Bus.get_value("guid.optics.cmd_deg", Vector3.ZERO)
				_drive_to(c.x, c.y, dt)
		"manual":
			var hc: Vector3 = Bus.get_value("ctl.optics.hc", Vector3.ZERO)
			var rate: float = HC_RATES_DEG_S[clampi(int(Bus.get_value("ctl.optics.speed", 1)), 0, 2)]
			shaft_deg = fposmod(shaft_deg + clampf(hc.x, -1.0, 1.0) * rate * dt, 360.0)
			trunnion_deg = clampf(trunnion_deg + clampf(hc.y, -1.0, 1.0) * rate * dt, 0.0, TRUNNION_MAX_DEG)
	_publish()


func _drive_to(shaft: float, trunnion: float, dt: float) -> void:
	var step := DRIVE_DEG_S * dt
	shaft_deg = fposmod(shaft_deg + clampf(wrapf(shaft - shaft_deg, -180.0, 180.0), -step, step), 360.0)
	var tt := clampf(trunnion, 0.0, TRUNNION_MAX_DEG)
	trunnion_deg += clampf(tt - trunnion_deg, -step, step)


func _publish() -> void:
	Bus.set_value("optics.shaft_deg", shaft_deg)
	Bus.set_value("optics.trunnion_deg", trunnion_deg)
	Bus.set_value("optics.los_body", line_of_sight())
	Bus.set_value("optics.mode", mode_name())


func snapshot() -> Dictionary:
	return {"shaft_deg": shaft_deg, "trunnion_deg": trunnion_deg}


func restore(d: Dictionary) -> void:
	shaft_deg = float(d.get("shaft_deg", 0.0))
	trunnion_deg = float(d.get("trunnion_deg", 0.0))
	_publish()

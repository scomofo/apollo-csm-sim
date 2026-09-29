## The launch escape system (slice 9d): the tower on the CM from the pad
## until its jettison, and its abort, mode I (CSM Apollo Operations
## Handbook, SM2A-03-BLOCK II-(1), section 2.9; spacecraft.json "les")
## [published unless marked].
##
## In an LES abort (abort()) the CM leaves the SM and the tower's launch
## escape motor pulls it away, the launch escape vehicle (the "cm_les"
## configuration), its thrust along the vehicle's +X, the tower's. In the
## first 42 s of the flight (mode IA) the pitch control motor tilts it
## downrange, out to sea. After the motor burns out the vehicle flies
## tower first, as it is stable in the air; 11 s after the abort the
## canards deploy, and below Mach 3.8 turn it blunt end forward. 3.0 s
## after them the ELS is armed (les.elsc_armed, Els); when its controller
## comes on below 24,000 ft, at once in a low abort, the tower is
## jettisoned (tower_jettisoned) and the CM falls on toward its chutes.
## Above that the crew may jettison it themselves once the motor has
## burned out (TWR JETT, ctl.les.tower_jett), as in mode IC, where the
## canards can't turn the vehicle in the thin air. The vehicle's attitude
## follows the motors, the air and the canards at estimated rates, not
## their moments [simplified]; its drag is its own, on the CM's heat
## shield's area.
##
## In a normal ascent the tower goes at its jettison on the IU's time base
## 3 (LaunchVehicle, jettison()).
##
## Reads:  dyn.config, dyn.r_m, dyn.v_mps, dyn.att_q, dyn.alt_m,
##         els.elsc_active, ctl.les.tower_jett, time.get_s
## Writes: les.attached, les.abort, les.thrust_n, les.dir, les.q,
##         les.mass_kg, les.canards, les.elsc_armed, les.blunt
class_name Les
extends Node

## The tower was jettisoned: [param aborted] in an abort.
signal tower_jettisoned(aborted: bool)

## The tower is on the CM.
var attached: bool = false
## Whether the abort has started, when (GET), and whether in mode IA.
var aborted: bool = false
var abort_get: float = -1.0
var mode_1a: bool = false
## The launch escape vehicle's +X (the tower's), and its Z, ECI.
var dir: Vector3 = Vector3.RIGHT
var z_axis: Vector3 = Vector3.BACK
## The canards have turned the vehicle blunt end forward.
var blunt: bool = false
## The pitch control motor's axis, ECI: it tilts the vehicle downrange.
var pcm_axis: Vector3 = Vector3.ZERO
var thrust: float = 0.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## On the pad: the tower on.
func arm() -> void:
	attached = true
	aborted = false
	abort_get = -1.0
	mode_1a = false
	blunt = false
	thrust = 0.0
	_publish()


## Off: no tower (a start after the launch).
func stow() -> void:
	attached = false
	aborted = false
	abort_get = -1.0
	thrust = 0.0
	_publish()


## The LES abort now, from the attitude the CM has, [param downrange]
## the flight's downrange direction (ECI) the pitch control motor tilts it
## toward in [param p_mode_1a].
func abort(p_mode_1a: bool, downrange: Vector3) -> void:
	if not attached or aborted:
		return
	aborted = true
	abort_get = float(Bus.get_value("time.get_s", 0.0))
	mode_1a = p_mode_1a
	var b := Basis(Bus.get_value("dyn.att_q", Quaternion.IDENTITY) as Quaternion)
	dir = b.x.normalized()
	z_axis = b.z.normalized()
	pcm_axis = dir.cross(downrange).normalized() if dir.cross(downrange).length() > 1e-6 else b.y
	blunt = false
	_publish()


## The tower goes: at its normal jettison, or in the abort.
func jettison() -> void:
	if not attached:
		return
	attached = false
	thrust = 0.0
	_publish()
	tower_jettisoned.emit(aborted)


## Seconds since the abort, or -1.
func since_abort() -> float:
	return float(Bus.get_value("time.get_s", 0.0)) - abort_get if aborted else -1.0


func tick(dt: float) -> void:
	if not attached or not aborted or str(Bus.get_value("dyn.config", "")) != "cm_les":
		thrust = 0.0
		_publish()
		return
	var d := SpacecraftData.section("les")
	var t := since_abort()
	var lem_s := float(d["lem_burn_s"])
	thrust = float(d["lem_thrust_n"]) if t < lem_s else 0.0
	var ra: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH, 0.0, 0.0])
	var va: Array = Bus.get_value("dyn.v_mps", [0.0, 0.0, 0.0])
	var r := Vector3(ra[0], ra[1], ra[2])
	var air := Atmosphere.air_velocity(r, Vector3(va[0], va[1], va[2]))
	var h := r.length() - Bodies.R_EARTH
	var q := 0.5 * Atmosphere.density(h) * air.length_squared()
	var mach := air.length() / Atmosphere.sound_speed(h)
	var canards := t >= float(d["canard_s"])
	if mode_1a and t < lem_s:
		# The pitch control motor's kick, carried through the motor's burn.
		dir = dir.rotated(pcm_axis, deg_to_rad(float(d["pcm_rate_dps"])) * dt).normalized()
	elif canards and mach < float(d["canard_mach"]) and air.length() > 1.0:
		_turn_toward(-air.normalized(), deg_to_rad(float(d["canard_dps"])) * dt)
		blunt = dir.angle_to(-air.normalized()) < deg_to_rad(10.0)
	elif q > float(d["weathervane_q_pa"]) and air.length() > 1.0 and not blunt:
		# Tower first, as the vehicle is stable in the air.
		_turn_toward(air.normalized(), deg_to_rad(float(d["weathervane_dps"])) * dt)
	z_axis = (z_axis - dir * z_axis.dot(dir))
	if z_axis.length() < 1e-6:
		z_axis = dir.cross(Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT)
	z_axis = z_axis.normalized()
	# The ELS's controller on: the tower goes; the crew may send it once the
	# motor has burned out.
	if t >= lem_s and (bool(Bus.get_value("els.elsc_active", false)) or bool(Bus.get_value("ctl.les.tower_jett", false))):
		jettison()
		return
	_publish()


func _turn_toward(target: Vector3, step: float) -> void:
	var ang := dir.angle_to(target)
	if ang <= step:
		dir = target
		return
	var axis := dir.cross(target)
	if axis.length() < 1e-9:
		axis = z_axis
	dir = dir.rotated(axis.normalized(), step).normalized()


## The tower's mass now, kg: its motor's propellant burns in the abort.
func mass_kg() -> float:
	if not attached:
		return 0.0
	var d := SpacecraftData.section("les")
	var m := float((SpacecraftData.section("saturn_v")["s_ii"] as Dictionary)["les_kg"])
	if not aborted:
		return m
	return m - float(d["lem_propellant_kg"]) * clampf(since_abort() / float(d["lem_burn_s"]), 0.0, 1.0)


## The launch escape vehicle's attitude, ECI from body.
func attitude() -> Quaternion:
	var y := z_axis.cross(dir).normalized()
	return Basis(dir, y, dir.cross(y)).orthonormalized().get_rotation_quaternion()


func _publish() -> void:
	var t := since_abort()
	var d := SpacecraftData.section("les")
	Bus.set_value("les.attached", attached)
	Bus.set_value("les.abort", aborted)
	Bus.set_value("les.thrust_n", thrust)
	Bus.set_value("les.dir", [dir.x, dir.y, dir.z])
	var q := attitude()
	Bus.set_value("les.q", [q.x, q.y, q.z, q.w])
	Bus.set_value("les.mass_kg", mass_kg())
	Bus.set_value("les.canards", attached and t >= float(d["canard_s"]))
	Bus.set_value("les.elsc_armed", aborted and t >= float(d["elsc_arm_s"]))
	Bus.set_value("les.blunt", blunt)


func snapshot() -> Dictionary:
	return {"attached": attached, "aborted": aborted, "abort_get": abort_get, "mode_1a": mode_1a, "dir": [dir.x, dir.y, dir.z],
		"z": [z_axis.x, z_axis.y, z_axis.z], "blunt": blunt, "pcm_axis": [pcm_axis.x, pcm_axis.y, pcm_axis.z],
		"thrust": thrust}


func restore(d: Dictionary) -> void:
	attached = bool(d.get("attached", false))
	aborted = bool(d.get("aborted", false))
	abort_get = float(d.get("abort_get", -1.0))
	mode_1a = bool(d.get("mode_1a", false))
	var a: Array = d.get("dir", [1.0, 0.0, 0.0])
	dir = Vector3(a[0], a[1], a[2])
	a = d.get("z", [0.0, 0.0, 1.0])
	z_axis = Vector3(a[0], a[1], a[2])
	blunt = bool(d.get("blunt", false))
	a = d.get("pcm_axis", [0.0, 0.0, 0.0])
	pcm_axis = Vector3(a[0], a[1], a[2])
	thrust = float(d.get("thrust", 0.0))
	_publish()

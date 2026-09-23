## The Apollo Guidance Computer's core, shared by the Command Module
## Computer (Colossus, src/systems/agc.gd) and the LM Guidance Computer
## (Luminary, src/systems/lgc.gd): the DSKY's verb/noun dialogue, the
## program table and alarms, the External ΔV programs (P30, the thrusting
## programs and P47) and the digital autopilot.
##
## A functional model, not an instruction-level emulator. Each computer
## reads its own vehicle's truth and writes its own channels: the CMC
## dyn.*, guid.* and dsky.*, the LGC lm.dyn.*, lm.guid.* and lm.dsky.*
## (prefix). A computer names its programs, its engines and its hand
## controller and mode switch; the core runs the rest.
##
##   P00  idling
##   P30  External ΔV: accepts TIG (N33) and LVLH ΔV (N81), shows the
##        predicted apsides and ΔV (N42), then stores the maneuver
##   Thrusting programs: V50N18 auto maneuver to burn attitude, V16N40
##        countdown, V99N40 engine-on enable at TIG-5 s, cutoff on velocity
##        to be gained, V16N85 residuals. Thrust is steered to hold the N81
##        direction in the rotating LVLH frame [simplified: stands in for
##        cross-product steering, which a long burn needs]. An RCS program
##        (P41) burns +X translation instead of an engine
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   V06/V16 display/monitor, V21-V25 load, V34 terminate, V35 lamp test,
##   V37 change program, V82 orbit parameters (V16N44)
##
## Navigation is ideal [simplified]: the state vector and IMU equal truth
## (no P52 alignment, no state-vector uplink drift). REFSMMAT is the ECI
## frame, so ICDU angles are inertial Euler angles.
##
## Digital autopilot, from the computer's mode switch:
##   0 FREE  hand controller commands acceleration, no hold
##   1 HOLD  hand controller rate command, attitude hold on release
##   2 AUTO  as HOLD, plus program-commanded maneuvers
##
## Writes (under the prefix): guid.rcs_rot_cmd, guid.program,
##         guid.next_event_get_s, guid.vg_mps, guid.maneuver_valid,
##         guid.maneuver_tig, guid.step, guid.dap_busy, guid.att_error_deg,
##         guid.rcs_trans_cmd, the engine command (the computer's),
##         guid.indicator.attitude (the FDAI's attitude: body relative to
##         LVLH), and the DSKY's display: dsky.prog, dsky.verb, dsky.noun,
##         dsky.r1-dsky.r3 (blank while unpowered), dsky.flash,
##         dsky.comp_acty, dsky.lamp.<lamp>
class_name AgcCore
extends Node

const RATE_HOLD := 0.0349066      ## rad/s, 2 °/s hand controller full-scale rate
const RATE_AUTO := 0.0174533      ## rad/s, 1 °/s auto-maneuver rate
const ATT_DEADBAND := 0.00873     ## rad, 0.5°

var dsky: Dsky
var program: int = 0
var step_name: String = ""
## Channel prefix of this computer's vehicle: "" for the CSM, "lm." for
## the LM.
var prefix: String = ""

# P30 load registers (what N33/N81 show) and the stored maneuver.
var tig_load: float = 0.0
var dv_lvlh_load: Vector3 = Vector3.ZERO
var maneuver_valid: bool = false
var maneuver_tig: float = 0.0
var maneuver_dv_inertial: Vector3 = Vector3.ZERO
var maneuver_dv_lvlh: Vector3 = Vector3.ZERO

# Thrusting program and P47 state.
var vg: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
var dv_accum: float = 0.0
## ΔV still to be gained along the steered thrust direction, m/s.
var vg_left: float = 0.0
var dv_body: Vector3 = Vector3.ZERO
var engine_enabled: bool = false
## The program commands the engine on.
var engine_on: bool = false
## An RCS program's +X translation in progress.
var rcs_burn: bool = false
var burn_dir: Vector3 = Vector3.RIGHT
## GET the engine was commanded on, for a throttle schedule.
var ignition_get: float = -1.0

# DAP state.
var hold_q: Quaternion = Quaternion.IDENTITY
var auto_target: Quaternion = Quaternion.IDENTITY
var auto_active: bool = false
var _rhc_was_active: bool = false
var _last_source: int = -1
var desired_q: Quaternion = Quaternion.IDENTITY

var alarm_code: int = 0
var _display_timer: float = 0.0
var _uplink_timer: float = 0.0
var _lamp_test_timer: float = 0.0
var _powered: bool = true


func _init() -> void:
	dsky = Dsky.new(self)
	dsky.changed.connect(_publish_dsky)


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.POWER_GUIDANCE)
	SimClock.add_ticker(sense, SimClock.Stage.DEPENDENT)
	hold_q = _att()
	change_program(0)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)
	SimClock.remove_ticker(sense)


# --- the computer's own (overridden by the CMC and the LGC) ---------------------

## The programs V37 selects.
func programs() -> Array:
	return [0, 30, 41, 47]


## The thrusting programs, which need a stored maneuver.
func thrusting_programs() -> Array:
	return [41]


## Full thrust (N) and shutdown time constant (s) of program [param p]'s
## engine, for the cutoff lead.
func engine_thrust(_p: int) -> float:
	return 0.0


func engine_tau_off(_p: int) -> float:
	return 0.0


## The engine still produces thrust (its tail-off not yet over).
func engine_running() -> bool:
	return false


## Publish the engine command [param on] (the program's engine).
func publish_engine(_on: bool) -> void:
	pass


## The mode switch, 0 FREE, 1 HOLD, 2 AUTO.
func mode() -> int:
	return 1


## The rotation hand controller (roll, pitch, yaw), -1..1.
func rhc() -> Vector3:
	return Vector3.ZERO


## The attitude source: 0 the computer. Any other leaves the DAP following
## the attitude; 1 (an SCS) keeps the clock to fixed steps while turning.
func att_source() -> int:
	return 0


## The computer runs this step: its buses are powered.
func is_powered() -> bool:
	return bool(Bus.get_value(_ch("sys.powered"), true))


## The computer has just powered up.
func powered_up() -> void:
	pass


## The DAP can fly the vehicle as it is.
func dap_enabled() -> bool:
	return true


## The DAP's rate limit for program-commanded maneuvers, rad/s.
func auto_rate() -> float:
	return RATE_AUTO


## Angular acceleration full jet authority gives about each body axis,
## rad/s².
func authority() -> Vector3:
	return Vector3.ONE


## Start a program the core doesn't know.
func start_program(_p: int) -> void:
	pass


## A program step the core doesn't run (entry guidance on the CMC).
func extra_step() -> void:
	pass


# --- truth access (ideal navigation) ---------------------------------------

func _ch(name: String) -> String:
	return prefix + name


func _now() -> float:
	return float(Bus.get_value("time.get_s", 0.0))


func _att() -> Quaternion:
	return Bus.get_value(_ch("dyn.att_q"), Quaternion.IDENTITY)


func _omega() -> Vector3:
	return Bus.get_value(_ch("dyn.omega"), Vector3.ZERO)


func current_traj() -> Trajectory:
	var t := Trajectory.new()
	var r: Array = Bus.get_value(_ch("dyn.r_m"), [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
	var v: Array = Bus.get_value(_ch("dyn.v_mps"), [0.0, 7790.0, 0.0])
	t.set_state_d(str(Bus.get_value(_ch("dyn.primary"), "earth")), _now(),
		PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]]))
	return t


## State predicted at GET [param tig] (coasting).
func predict(tig: float) -> Trajectory:
	var t := current_traj()
	if tig > t.t:
		t.coast_to(tig, 60.0)
	return t


# --- gimbal angles --------------------------------------------------------

## ICDU angles (outer, inner, middle gimbal) in degrees, 0-360, for an
## attitude quaternion (REFSMMAT = ECI).
static func gimbal_angles(q: Quaternion) -> Vector3:
	var e := Basis(q).get_euler(EULER_ORDER_XZY)
	return Vector3(fposmod(rad_to_deg(e.x), 360.0), fposmod(rad_to_deg(e.y), 360.0), fposmod(rad_to_deg(e.z), 360.0))


# --- DSKY interface ---------------------------------------------------------

func noun_values(n: int) -> Variant:
	var tr := current_traj()
	match n:
		9:
			return [alarm_code, 0, 0]
		17, 20:
			var g := gimbal_angles(_att())
			return [g.x, g.y, g.z]
		18:
			var g := gimbal_angles(desired_q)
			return [g.x, g.y, g.z]
		33:
			var t := maneuver_tig if _thrusting_program() and maneuver_valid else tig_load
			return [t, t, t]
		36:
			var now := _now()
			return [now, now, now]
		40:
			var tfi := _now() - maneuver_tig
			return [tfi, _vg_mag(), dv_accum]
		42:
			var p := _predicted_apsides()
			return [p[0], p[1], dv_lvlh_load.length()]
		44:
			var c := tr.conic()
			var rb := Bodies.radius_of(tr.primary)
			var ha: float = c["ra"] - rb if c["ra"] != INF else 9999.9 * Units.NMI
			return [minf(ha, 9999.9 * Units.NMI), c["rp"] - rb, 0.0]
		62:
			return [tr.speed(), tr.radial_rate(), tr.altitude()]
		64:
			return [float(Bus.get_value(_ch("dyn.g_load"), 0.0)), tr.speed(), tr.altitude()]
		81:
			return [dv_lvlh_load.x, dv_lvlh_load.y, dv_lvlh_load.z]
		83:
			return [dv_body.x, dv_body.y, dv_body.z]
		85:
			var b := Basis(_att()).inverse() * Vector3(vg[0], vg[1], vg[2])
			return [b.x, b.y, b.z]
	return null


func noun_load(n: int, idx: int, value: float) -> bool:
	match n:
		33:
			var parts := [floorf(tig_load / 3600.0) * 3600.0, floorf(fmod(tig_load, 3600.0) / 60.0) * 60.0, fmod(tig_load, 60.0)]
			parts[idx] = value
			tig_load = parts[0] + parts[1] + parts[2]
			return true
		81:
			dv_lvlh_load[idx] = value
			return true
	return false


func verb_noun(v: int, _n: int) -> bool:
	match v:
		34:
			change_program(0)
			return true
		82:
			dsky.show(16, 44, false, false)
			return true
	return false


func lamp_test() -> void:
	_lamp_test_timer = 5.0
	for l in Dsky.LAMPS:
		dsky.lamps[l] = true
	dsky.changed.emit()


func key_release() -> void:
	pass


## Load a maneuver PAD from the ground (the RTCC), as a real uplink would:
## it fills the P30 registers; the crew still runs P30 to accept it.
func uplink_maneuver(tig: float, dv_lvlh: Vector3) -> void:
	tig_load = tig
	dv_lvlh_load = dv_lvlh
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


# --- programs ---------------------------------------------------------------

func change_program(p: int) -> bool:
	if not p in programs():
		return false
	if p in thrusting_programs() and not maneuver_valid:
		_alarm(1703)   # no maneuver stored
		return false
	dsky.lamps["key_rel"] = false
	program = p
	step_name = ""
	auto_active = false
	engine_enabled = false
	engine_on = false
	rcs_burn = false
	ignition_get = -1.0
	dsky.set_prog(p)
	match p:
		0:
			dsky.blank()
		30:
			step_name = "n33"
			dsky.show(6, 33, true)
		47:
			dv_body = Vector3.ZERO
			dsky.show(16, 83)
		_:
			if p in thrusting_programs():
				_start_thrusting()
			else:
				start_program(p)
	_publish()
	return true


func proceed() -> void:
	if program == 30:
		match step_name:
			"n33":
				step_name = "n81"
				dsky.show(6, 81, true)
			"n81":
				step_name = "n42"
				dsky.show(6, 42, true)
			"n42":
				_store_maneuver()
				change_program(0)
	elif _thrusting_program():
		match step_name:
			"v50n18":
				step_name = "maneuver"
				auto_active = true
				dsky.show(6, 18)
			"v99":
				engine_enabled = true
				step_name = "ignition"
				dsky.show(16, 40)
			"post":
				maneuver_valid = false
				change_program(0)
	elif program == 47:
		change_program(0)


func _store_maneuver() -> void:
	var p := predict(tig_load)
	var b := Trajectory.lvlh_basis(p.pos(), p.vel())
	maneuver_dv_inertial = b * dv_lvlh_load
	maneuver_dv_lvlh = dv_lvlh_load
	maneuver_tig = tig_load
	maneuver_valid = dv_lvlh_load.length() > 0.0


func _predicted_apsides() -> Array:
	var p := predict(tig_load)
	var b := Trajectory.lvlh_basis(p.pos(), p.vel())
	var dv := b * dv_lvlh_load
	var st := p.s.duplicate()
	st[3] += dv.x; st[4] += dv.y; st[5] += dv.z
	var c := Trajectory.conic_of(st, Bodies.mu_of(p.primary))
	var rb := Bodies.radius_of(p.primary)
	var ha: float = c["ra"] - rb if c["ra"] != INF else 9999.9 * Units.NMI
	return [minf(ha, 9999.9 * Units.NMI), c["rp"] - rb]


func _start_thrusting() -> void:
	vg = PackedFloat64Array([maneuver_dv_inertial.x, maneuver_dv_inertial.y, maneuver_dv_inertial.z])
	vg_left = maneuver_dv_lvlh.length()
	dv_accum = 0.0
	burn_dir = maneuver_dv_inertial.normalized()
	auto_target = burn_attitude(burn_dir)
	desired_q = auto_target
	step_name = "v50n18"
	dsky.show(50, 18, true)


## Burn attitude: body +X (the thrust axis) along [param dir]; roll chosen
## so body +Z points as close to the local vertical (down) as possible
## ("heads up" for the CSM's crew, [simplified]).
func burn_attitude(dir: Vector3) -> Quaternion:
	var x := dir.normalized()
	var down := -current_traj().pos().normalized()
	var z := down - x * down.dot(x)
	if z.length() < 1e-3:
		z = x.cross(Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	z = z.normalized()
	var y := z.cross(x)
	return Basis(x, y, z).orthonormalized().get_rotation_quaternion()


## Hold the maneuver's LVLH direction as the frame rotates.
func _steer() -> void:
	var tr := current_traj()
	burn_dir = (Trajectory.lvlh_basis(tr.pos(), tr.vel()) * maneuver_dv_lvlh).normalized()
	auto_target = burn_attitude(burn_dir)
	desired_q = auto_target


func _vg_mag() -> float:
	return Vector3(vg[0], vg[1], vg[2]).length()


func _alarm(code: int) -> void:
	alarm_code = code
	dsky.set_lamp("prog", true)


# --- per-step --------------------------------------------------------------

func tick(dt: float) -> void:
	var was_powered := _powered
	_powered = is_powered()
	if _powered != was_powered:
		_publish_dsky()
		if _powered:
			powered_up()
	if not _powered:
		Bus.set_value(_ch("guid.rcs_rot_cmd"), Vector3.ZERO)
		publish_engine(false)
		dsky.set_lamp("no_att", true)
		return
	dsky.set_lamp("no_att", false)
	_timers(dt)
	_program_step()
	extra_step()
	_dap(dt)
	_publish()
	_publish_indicator()


## Stage DEPENDENT: integrate the accelerometers after Dynamics stepped.
func sense(_dt: float) -> void:
	var d: Array = Bus.get_value(_ch("dyn.dv_step"), [0.0, 0.0, 0.0])
	var step := Vector3(d[0], d[1], d[2])
	if step == Vector3.ZERO:
		return
	if _thrusting_program() and (step_name == "burn" or step_name == "tailoff" or step_name == "post"):
		if step_name == "post":
			# Residual trimming with the RCS works on the VG vector.
			for i in 3:
				vg[i] -= step[i]
		else:
			vg_left -= step.dot(burn_dir)
			var g := burn_dir * vg_left
			vg = PackedFloat64Array([g.x, g.y, g.z])
		dv_accum += step.length()
	if program == 47 or _thrusting_program():
		dv_body += Basis(_att()).inverse() * step


func _timers(dt: float) -> void:
	if _uplink_timer > 0.0:
		_uplink_timer -= dt
		if _uplink_timer <= 0.0:
			dsky.set_lamp("uplink_acty", false)
	if _lamp_test_timer > 0.0:
		_lamp_test_timer -= dt
		if _lamp_test_timer <= 0.0:
			for l in Dsky.LAMPS:
				dsky.lamps[l] = false
			dsky.changed.emit()
	_display_timer += dt
	if _display_timer >= 1.0:
		_display_timer = 0.0
		dsky.refresh()
	var mg := gimbal_angles(_att()).z
	dsky.set_lamp("gimbal_lock", absf(wrapf(mg, -180.0, 180.0)) > 85.0 and str(Bus.get_value(_ch("dyn.config"), "")) != "stack")


func _thrusting_program() -> bool:
	return program in thrusting_programs()


## The program burns on the RCS (+X translation) rather than an engine.
func _rcs_program() -> bool:
	return program == 41


func _program_step() -> void:
	if not _thrusting_program():
		Bus.set_value(_ch("guid.next_event_get_s"), -1.0)
		return
	var now := _now()
	match step_name:
		"maneuver":
			if _att_error(auto_target) < deg_to_rad(2.0) and _omega().length() < deg_to_rad(0.2):
				step_name = "wait"
				dsky.show(16, 40)
			if now >= maneuver_tig - 5.0:
				step_name = "v99"
				dsky.show(99, 40, true)
		"wait":
			if now >= maneuver_tig - 5.0:
				step_name = "v99"
				dsky.show(99, 40, true)
		"ignition":
			if now >= maneuver_tig - 1e-6:
				step_name = "burn"
				engine_on = not _rcs_program()
				rcs_burn = _rcs_program()
				ignition_get = now
				_steer()
		"burn":
			_steer()
			if _rcs_program():
				if vg_left <= 0.0:
					rcs_burn = false
					step_name = "post"
					dsky.show(16, 85, true)
				return
			var a := engine_thrust(program) / maxf(float(Bus.get_value(_ch("dyn.mass_kg"), 30000.0)), 1.0)
			var tail := a * engine_tau_off(program)
			if vg_left <= tail:
				engine_on = false
				step_name = "tailoff"
		"tailoff":
			if not engine_running():
				step_name = "post"
				dsky.show(16, 85, true)
	# Coast landing points: stop fast-forward one minute before TIG, then at
	# TIG-5 (V99).
	var next := -1.0
	if step_name in ["v50n18", "maneuver", "wait"]:
		next = maneuver_tig - 60.0 if now < maneuver_tig - 60.0 else maneuver_tig - 5.0
	Bus.set_value(_ch("guid.next_event_get_s"), next)


# --- digital autopilot -------------------------------------------------------

func _att_error(target: Quaternion) -> float:
	var e := (_att().inverse() * target).normalized()
	return 2.0 * acos(clampf(absf(e.w), 0.0, 1.0))


## Body-frame rotation vector (rad) from current attitude to [param target].
func _error_vector(target: Quaternion) -> Vector3:
	var e := (_att().inverse() * target).normalized()
	if e.w < 0.0:
		e = -e
	var s := Vector3(e.x, e.y, e.z)
	var sn := s.length()
	if sn < 1e-9:
		return Vector3.ZERO
	return s / sn * 2.0 * atan2(sn, e.w)


func _dap(_dt: float) -> void:
	var src := att_source()
	if src != 0 or not dap_enabled():
		hold_q = _att()
		_last_source = src
		Bus.set_value(_ch("guid.rcs_rot_cmd"), Vector3.ZERO)
		Bus.set_value(_ch("guid.dap_busy"), src == 1 and _omega().length() > 0.0005)
		return
	if _last_source != 0:
		hold_q = _att()
		_last_source = 0
	var m := mode()
	var hc := rhc()
	var w := _omega()
	var alpha := authority()
	var tau := 0.6
	var cmd := Vector3.ZERO
	var rhc_active := hc.length() > 0.05
	if m == 0:
		cmd = hc
		hold_q = _att()
	elif rhc_active:
		var w_des := hc * RATE_HOLD
		cmd = _rate_cmd(w_des - w, alpha, tau)
		hold_q = _att()
	else:
		var target := hold_q
		var max_rate := RATE_HOLD
		if m == 2 and auto_active:
			target = auto_target
			max_rate = auto_rate()
		if _rhc_was_active:
			hold_q = _att()
			target = hold_q if not (m == 2 and auto_active) else target
		var e := _error_vector(target)
		var w_des := Vector3.ZERO
		for i in 3:
			var ei := e[i]
			# Rate that can still be braked to zero over the error, capped.
			var brake := sqrt(2.0 * alpha[i] * 0.5 * absf(ei))
			w_des[i] = signf(ei) * minf(minf(absf(ei) * 0.4, brake), max_rate)
		if e.length() < ATT_DEADBAND * 0.2 and w.length() < 5e-5:
			w_des = w
		cmd = _rate_cmd(w_des - w, alpha, tau)
		if m == 2 and auto_active:
			desired_q = auto_target
	_rhc_was_active = rhc_active
	Bus.set_value(_ch("guid.rcs_rot_cmd"), cmd)
	# Busy while steering or outside the hold deadband: no coarse coast steps.
	var target_now := auto_target if (m == 2 and auto_active) else hold_q
	var busy := rhc_active or cmd.length() > 1e-4 or (m != 0 and _error_vector(target_now).length() > ATT_DEADBAND * 0.2)
	Bus.set_value(_ch("guid.dap_busy"), busy)
	Bus.set_value(_ch("guid.att_error_deg"), _error_vector(target_now) * (180.0 / PI) if m != 0 else Vector3.ZERO)


static func _rate_cmd(err: Vector3, alpha: Vector3, tau: float) -> Vector3:
	var c := Vector3.ZERO
	for i in 3:
		c[i] = clampf(err[i] / maxf(alpha[i] * tau, 1e-6), -1.0, 1.0)
	return c


func _publish() -> void:
	Bus.set_value(_ch("guid.program"), program)
	publish_engine(engine_on and engine_enabled)
	Bus.set_value(_ch("guid.rcs_trans_cmd"), Vector3(1, 0, 0) if rcs_burn and engine_enabled else Vector3.ZERO)
	Bus.set_value(_ch("guid.vg_mps"), _vg_mag())
	Bus.set_value(_ch("guid.maneuver_valid"), maneuver_valid)
	Bus.set_value(_ch("guid.maneuver_tig"), maneuver_tig)
	Bus.set_value(_ch("guid.step"), step_name)


## The attitude the FDAI shows: body relative to the local vertical frame
## (orbit-rate display), as the 2D FDAI in hud.gd draws it.
func _publish_indicator() -> void:
	var tr := current_traj()
	if tr.radius() < 1.0 or tr.pos().cross(tr.vel()).length() < 1e-6:
		return   # no trajectory yet (before a start phase is set up)
	var lvlh := Trajectory.lvlh_basis(tr.pos(), tr.vel())
	Bus.set_value(_ch("guid.indicator.attitude"), (lvlh.inverse() * Basis(_att())).get_rotation_quaternion())


## The DSKY's display on the Bus, for a cabin DSKY. The EL display is
## blank while the computer is unpowered; the lamps keep their own logic.
func _publish_dsky() -> void:
	var on := _powered
	Bus.set_value(_ch("dsky.prog"), dsky.prog if on else "")
	Bus.set_value(_ch("dsky.verb"), dsky.verb if on else "")
	Bus.set_value(_ch("dsky.noun"), dsky.noun if on else "")
	for i in 3:
		Bus.set_value(_ch("dsky.r%d" % (i + 1)), dsky.r[i] if on else "")
	Bus.set_value(_ch("dsky.flash"), on and dsky.flashing)
	Bus.set_value(_ch("dsky.comp_acty"), on and dsky.mode != "")
	for l in Dsky.LAMPS:
		Bus.set_value(_ch("dsky.lamp." + l), bool(dsky.lamps.get(l, false)))


func snapshot() -> Dictionary:
	return {
		"program": program, "step": step_name, "tig_load": tig_load,
		"dv_lvlh_load": [dv_lvlh_load.x, dv_lvlh_load.y, dv_lvlh_load.z],
		"maneuver_valid": maneuver_valid, "maneuver_tig": maneuver_tig,
		"maneuver_dv": [maneuver_dv_inertial.x, maneuver_dv_inertial.y, maneuver_dv_inertial.z],
		"maneuver_dv_lvlh": [maneuver_dv_lvlh.x, maneuver_dv_lvlh.y, maneuver_dv_lvlh.z], "vg_left": vg_left,
		"vg": Array(vg), "dv_accum": dv_accum, "engine_enabled": engine_enabled, "engine_on": engine_on,
		"ignition_get": ignition_get,
		"auto_active": auto_active, "hold_q": [hold_q.x, hold_q.y, hold_q.z, hold_q.w],
	}


func restore(d: Dictionary) -> void:
	tig_load = float(d["tig_load"])
	var l: Array = d["dv_lvlh_load"]
	dv_lvlh_load = Vector3(l[0], l[1], l[2])
	maneuver_valid = bool(d["maneuver_valid"])
	maneuver_tig = float(d["maneuver_tig"])
	var m: Array = d["maneuver_dv"]
	maneuver_dv_inertial = Vector3(m[0], m[1], m[2])
	var ml: Array = d.get("maneuver_dv_lvlh", [0, 0, 0])
	maneuver_dv_lvlh = Vector3(ml[0], ml[1], ml[2])
	var p := int(d["program"])
	change_program(p if not p in thrusting_programs() or maneuver_valid else 0)
	step_name = str(d["step"])
	vg = PackedFloat64Array(d["vg"])
	dv_accum = float(d["dv_accum"])
	vg_left = float(d.get("vg_left", 0.0))
	engine_enabled = bool(d["engine_enabled"])
	engine_on = bool(d.get("engine_on", d.get("sps_on", false)))
	ignition_get = float(d.get("ignition_get", -1.0))
	auto_active = bool(d["auto_active"])
	var h: Array = d["hold_q"]
	hold_q = Quaternion(h[0], h[1], h[2], h[3])
	_publish()

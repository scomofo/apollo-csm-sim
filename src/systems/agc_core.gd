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
## Navigation: each computer flies on its own state vector (nav), never
## truth. It coasts it with its own integration, and adds its vehicle's
## sensed ΔV (dyn.dv_step) only while Average-G runs (avg_g()). The ground's
## uplinks replace it (P27, V71) when the computer takes them
## (accepts_uplink()); until it has one it takes its vehicle's truth.
##
## The IMU (src/systems/imu.gd): the computer reads its vehicle's attitude
## and sensed ΔV through the stable member, taken to lie at REFSMMAT, so a
## misaligned platform turns both. Everything the computer flies, displays
## and navigates on sees them so turned; the ICDU angles (N20, and the
## FDAI's total attitude) are the vehicle's attitude relative to the stable
## member. While the IMU is in coarse align or caged NO ATT lights and the
## DAP only damps the rates. A thrusting program needs the IMU's
## orientation known (alarm 00220), and won't maneuver to a burn attitude
## past LOCK_MANEUVER_DEG of middle gimbal (alarm 00401): P52 to the
## preferred orientation first. Each auto maneuver is planned clear of
## gimbal lock on the way (_plan_via()). The LGC's IMU is ideal
## (real_imu()).
##
## Digital autopilot, from the computer's mode switch:
##   0 FREE  hand controller commands acceleration, no hold
##   1 HOLD  hand controller rate command, attitude hold on release
##   2 AUTO  as HOLD, plus program-commanded maneuvers
## The hold comes to rest inside a tenth of ATT_DEADBAND (0.05°), with the
## rate nulled to REST_RATE and the jets off, so the clock can coast; past
## that it corrects (a drifting platform moves the attitude it holds).
##
## Writes (under the prefix): guid.rcs_rot_cmd, guid.program,
##         guid.next_event_get_s, guid.vg_mps, guid.maneuver_valid,
##         guid.maneuver_tig, guid.step, guid.dap_busy, guid.att_error_deg,
##         guid.rcs_trans_cmd, the engine command (the computer's),
##         guid.indicator.attitude (the FDAI's attitude, indicator_attitude()),
##         guid.indicator.lvlh (body relative to LVLH, for the horizon aid),
##         imu.icdu_deg (the ICDU angles, deg), imu.aligned, imu.mode,
##         imu.preferred (REFSMMAT is P30's preferred orientation), and
##         the DSKY's display: dsky.prog, dsky.verb, dsky.noun,
##         dsky.r1-dsky.r3 (blank while unpowered), dsky.flash,
##         dsky.comp_acty, dsky.lamp.<lamp>
class_name AgcCore
extends Node

const RATE_HOLD := 0.0349066      ## rad/s, 2 °/s hand controller full-scale rate
const RATE_AUTO := 0.0174533      ## rad/s, 1 °/s auto-maneuver rate
const ATT_DEADBAND := 0.00873     ## rad, 0.5°
## The rate the hold nulls down to before it leaves the jets off, rad/s:
## the attitude moves about 0.02° an hour on what is left.
const REST_RATE := 1e-7
## The auto maneuver refuses a burn attitude whose middle gimbal angle is
## past this, deg (alarm 00401).
const LOCK_MANEUVER_DEG := 60.0

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
## The auto maneuver's legs still to fly before auto_target, on a real IMU
## (_plan_via()): the DAP steers to the first until it is inside the
## deadband.
var maneuver_vias: Array[Quaternion] = []
var _rhc_was_active: bool = false
var _last_source: int = -1
var desired_q: Quaternion = Quaternion.IDENTITY

## The computer's state vector; null until it has one.
var nav: Trajectory = null
## The IMU the computer reads its attitude and sensed ΔV through.
var imu := Imu.new()
## The preferred orientation P30 worked out for the stored maneuver (P52
## option 1), and whether there is one.
var preferred_refsmmat: Basis = Basis.IDENTITY
var preferred_valid: bool = false
## GET the ground's last state vector came up (P27), or -1.
var nav_uplink_get: float = -1.0

var alarm_code: int = 0
var _display_timer: float = 0.0
var _uplink_timer: float = 0.0
## P27 has the DSKY while UPLINK ACTY is lit (an uplink taken in P00).
var _p27_display: bool = false
var _lamp_test_timer: float = 0.0
var _powered: bool = true


func _init() -> void:
	dsky = Dsky.new(self)
	dsky.changed.connect(_publish_dsky)
	imu.ideal = not real_imu()


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


## The computer takes the ground's uplinks now (P27): it was powered at
## its last step.
func accepts_uplink() -> bool:
	return _powered


## Average-G runs: the vehicle's sensed ΔV goes into the state vector.
func avg_g() -> bool:
	return true


## The computer's IMU drifts, is aligned and can lock its gimbals; false
## for an ideal one.
func real_imu() -> bool:
	return false


## The attitude the FDAI shows, given the body's attitude relative to LVLH
## [param lvlh]: that, the orbit-rate display.
func indicator_attitude(lvlh: Quaternion) -> Quaternion:
	return lvlh


## A program step the core doesn't run (entry guidance on the CMC).
func extra_step() -> void:
	pass


# --- truth access (the vehicle's sensors, and the state before navigation) ---

func _ch(name: String) -> String:
	return prefix + name


func _now() -> float:
	return float(Bus.get_value("time.get_s", 0.0))


## The vehicle's attitude as the computer reads it, through the IMU.
func _att() -> Quaternion:
	return imu.attitude(_true_att())


## The vehicle's true attitude (body to ECI), what the IMU's gimbals sit on.
func _true_att() -> Quaternion:
	return Bus.get_value(_ch("dyn.att_q"), Quaternion.IDENTITY)


## The ICDU angles now (outer, inner, middle), deg.
func icdu() -> Vector3:
	return imu.icdu(Basis(_true_att()))


func _omega() -> Vector3:
	return Bus.get_value(_ch("dyn.omega"), Vector3.ZERO)


## The gravity model this computer's programs integrate a state vector
## with: the CMC's; Lgc overrides it.
func nav_model() -> Trajectory.Model:
	return Trajectory.Model.CMC


## The vehicle's true state, what the state vector starts from.
func truth_traj() -> Trajectory:
	var t := Trajectory.new()
	var r: Array = Bus.get_value(_ch("dyn.r_m"), [Bodies.R_EARTH + 185000.0, 0.0, 0.0])
	var v: Array = Bus.get_value(_ch("dyn.v_mps"), [0.0, 7790.0, 0.0])
	t.set_state_d(str(Bus.get_value(_ch("dyn.primary"), "earth")), _now(),
		PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]]))
	t.as_onboard(nav_model())
	return t


# --- navigation -------------------------------------------------------------

## The computer's state vector (a copy), or truth before it has one.
func current_traj() -> Trajectory:
	if nav == null:
		return truth_traj()
	return nav.clone()


## Set the state vector to [param tr] without an uplink (a start phase's).
func init_nav(tr: Trajectory) -> void:
	nav = tr.clone().as_onboard(nav_model())
	nav_uplink_get = -1.0


## The ground's state vector [param tr] replaces the computer's (P27,
## V71), which coasts it on from its time. Returns false, and leaves the
## state vector as it was, when the computer doesn't take uplinks now
## (accepts_uplink()).
func uplink_state(tr: Trajectory) -> bool:
	if not accepts_uplink():
		return false
	nav = tr.clone().as_onboard(nav_model())
	nav_uplink_get = _now()
	_uplink_shown()
	return true


## Stage DEPENDENT, after Dynamics stepped: coast the state vector to now,
## with this step's sensed ΔV [param dv] while Average-G runs. Without one,
## it takes the vehicle's truth.
func _navigate(dv: Vector3) -> void:
	if nav == null:
		nav = truth_traj()
		return
	var now := _now()
	var h := now - nav.t
	if h <= 0.0:
		return
	if h > 60.0:
		# Longer than a step (a state vector from before a start phase's
		# time): coast it up.
		nav.coast_to(now)
		return
	var ext := PackedFloat64Array()
	if avg_g() and dv != Vector3.ZERO:
		ext = PackedFloat64Array([dv.x / h, dv.y / h, dv.z / h])
	nav.step(h, ext)


## State predicted at GET [param tig] (coasting).
func predict(tig: float) -> Trajectory:
	var t := current_traj()
	if tig > t.t:
		t.coast_to(tig, 60.0)
	return t


# --- gimbal angles --------------------------------------------------------

## The ICDU angles (outer, inner, middle), deg, for attitude [param q] as
## the computer reads it: relative to REFSMMAT.
func gimbal_angles_of(q: Quaternion) -> Vector3:
	return Imu.gimbal_angles(imu.refsmmat * Basis(q))


## Attitude [param q] puts the middle gimbal past LOCK_MANEUVER_DEG: the
## auto maneuver won't fly there (alarm 00401). Never for an ideal IMU.
func _locks_gimbals(q: Quaternion) -> bool:
	return not imu.ideal and absf(wrapf(gimbal_angles_of(q).z, -180.0, 180.0)) > LOCK_MANEUVER_DEG


## Plan the auto maneuver to auto_target clear of gimbal lock, on a real
## IMU [aid: the sim's own routing]. The thrust axis (body X) turns the
## shortest way onto the target's, then the CSM rolls about it, which turns
## the outer gimbal alone. Where the first leg would take the middle gimbal
## past LOCK_MANEUVER_DEG, the gimbals turn one at a time instead: the
## inner (about the stable member's Y), the middle, then the outer. The
## middle gimbal then runs only between its two ends' angles.
func _plan_via() -> void:
	maneuver_vias.clear()
	if imu.ideal:
		return
	var now := _att()
	var x_now := Basis(now) * Vector3.RIGHT
	var x_to := Basis(auto_target) * Vector3.RIGHT
	if x_now.angle_to(x_to) < deg_to_rad(1.0):
		return
	var legs: Array[Quaternion] = [(Quaternion(x_now, x_to) * now).normalized()]
	if _peak_middle_gimbal(now, legs[0]) > LOCK_MANEUVER_DEG:
		var g0 := gimbal_angles_of(now)
		var g1 := gimbal_angles_of(auto_target)
		legs = [_at_gimbals(Vector3(g0.x, g1.y, g0.z)), _at_gimbals(Vector3(g0.x, g1.y, g1.z))]
	var from := now
	for q in legs:
		if _angle_between(from, q) > deg_to_rad(2.0) and _angle_between(q, auto_target) > deg_to_rad(2.0):
			maneuver_vias.append(q)
			from = q


## The largest middle gimbal angle (deg) on the way from attitude
## [param a] to [param b], the shortest way.
func _peak_middle_gimbal(a: Quaternion, b: Quaternion) -> float:
	var peak := 0.0
	for i in 17:
		peak = maxf(peak, absf(wrapf(gimbal_angles_of(a.slerp(b, i / 16.0)).z, -180.0, 180.0)))
	return peak


## The attitude at ICDU angles [param g] (outer, inner, middle; deg).
func _at_gimbals(g: Vector3) -> Quaternion:
	return (imu.refsmmat.transposed() * Imu.gimbal_basis(g)).get_rotation_quaternion()


static func _angle_between(a: Quaternion, b: Quaternion) -> float:
	return 2.0 * acos(clampf(absf(a.dot(b)), 0.0, 1.0))


## Where the auto maneuver steers now: its next leg's end, or auto_target.
func _maneuver_target() -> Quaternion:
	return maneuver_vias[0] if not maneuver_vias.is_empty() else auto_target


# --- DSKY interface ---------------------------------------------------------

func noun_values(n: int) -> Variant:
	var tr := current_traj()
	match n:
		9:
			return [alarm_code, 0, 0]
		17, 20:
			var g := icdu()
			return [g.x, g.y, g.z]
		18:
			var g := gimbal_angles_of(desired_q)
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
	for l in dsky.lamp_names:
		dsky.lamps[l] = true
	dsky.changed.emit()


func key_release() -> void:
	pass


## Load a maneuver PAD from the ground (the RTCC), as a real uplink would:
## it fills the P30 registers; the crew still runs P30 to accept it.
## Returns false, loading nothing, when the computer doesn't take uplinks
## now (accepts_uplink()).
func uplink_maneuver(tig: float, dv_lvlh: Vector3) -> bool:
	if not accepts_uplink():
		return false
	tig_load = tig
	dv_lvlh_load = dv_lvlh
	_uplink_shown()
	return true


## An uplink came in: UPLINK ACTY for a couple of seconds, and in P00 the
## DSKY shows P27 and the ground's V71 meanwhile.
func _uplink_shown() -> void:
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)
	if program == 0:
		_p27_display = true
		dsky.set_prog(27)
		dsky.show(71, -1)


# --- programs ---------------------------------------------------------------

func change_program(p: int) -> bool:
	if not p in programs():
		return false
	if p in thrusting_programs() and not maneuver_valid:
		_alarm(1703)   # no maneuver stored
		return false
	if p in thrusting_programs() and not imu.aligned:
		_alarm(220)    # IMU orientation unknown
		return false
	dsky.lamps["key_rel"] = false
	program = p
	step_name = ""
	_p27_display = false
	auto_active = false
	engine_enabled = false
	engine_on = false
	rcs_burn = false
	ignition_get = -1.0
	maneuver_vias.clear()
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
				if _locks_gimbals(auto_target):
					# The burn attitude is in gimbal lock on this REFSMMAT:
					# realign (P52 option 1) first.
					_alarm(401)
					return
				_plan_via()
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
	# The preferred orientation for it, which P52 option 1 aligns to.
	preferred_valid = maneuver_valid
	if preferred_valid:
		preferred_refsmmat = Imu.preferred(maneuver_dv_inertial, p.pos())
	_publish_imu()


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
	dsky.set_lamp("no_att", not imu.operating())
	_timers(dt)
	_program_step()
	extra_step()
	_dap(dt)
	_publish()
	_publish_indicator()


## Stage DEPENDENT: step the IMU and integrate its accelerometers after
## Dynamics stepped.
func sense(dt: float) -> void:
	imu.step(dt, Basis(_true_att()))
	var d: Array = Bus.get_value(_ch("dyn.dv_step"), [0.0, 0.0, 0.0])
	var step := imu.sensed(Vector3(d[0], d[1], d[2]))
	if step != Vector3.ZERO:
		_sense_step(step)
	_navigate(step)
	_publish_imu()


func _sense_step(step: Vector3) -> void:
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
			if _p27_display:
				# P27 done: back to P00's display.
				_p27_display = false
				if program == 0:
					dsky.set_prog(0)
					dsky.blank()
	if _lamp_test_timer > 0.0:
		_lamp_test_timer -= dt
		if _lamp_test_timer <= 0.0:
			for l in dsky.lamp_names:
				dsky.lamps[l] = false
			dsky.changed.emit()
	_display_timer += dt
	if _display_timer >= 1.0:
		_display_timer = 0.0
		dsky.refresh()
	dsky.set_lamp("gimbal_lock", imu.lock_lamp(Basis(_true_att())))


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
				maneuver_vias.clear()
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
	if not imu.operating():
		# No attitude reference (NO ATT): the hand controller as in FREE,
		# and otherwise the rates damped, to REST_RATE and the jets off as
		# the hold comes to rest (else they pulse on a trace of rate for
		# good, and the clock can't coast); the hold starts again where the
		# vehicle is once the IMU is back.
		hold_q = _att()
		if rhc_active:
			cmd = hc
		elif w.length() > REST_RATE:
			cmd = _rate_cmd(-w, alpha, tau)
		_rhc_was_active = rhc_active
		Bus.set_value(_ch("guid.rcs_rot_cmd"), cmd)
		Bus.set_value(_ch("guid.dap_busy"), rhc_active or cmd.length() > 1e-4)
		Bus.set_value(_ch("guid.att_error_deg"), Vector3.ZERO)
		return
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
			if not maneuver_vias.is_empty() and _error_vector(maneuver_vias[0]).length() < ATT_DEADBAND:
				maneuver_vias.pop_front()
			target = _maneuver_target()
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
		if e.length() < ATT_DEADBAND * 0.1 and w.length() < 5e-5:
			# At rest: null what rate is left, then leave the jets off (a
			# coast step needs them off). Resting only inside 0.05°, half
			# the 0.1° past which the DAP is busy, keeps a drifting
			# platform from chattering the jets at that edge.
			w_des = Vector3.ZERO if w.length() > REST_RATE else w
		cmd = _rate_cmd(w_des - w, alpha, tau)
		if m == 2 and auto_active:
			desired_q = auto_target
	_rhc_was_active = rhc_active
	Bus.set_value(_ch("guid.rcs_rot_cmd"), cmd)
	# Busy while steering or outside the hold deadband: no coarse coast steps.
	var target_now := hold_q
	if m == 2 and auto_active:
		target_now = _maneuver_target()
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


## The attitude the FDAI shows (indicator_attitude()), and the body's
## attitude relative to the local vertical frame from the state vector,
## which the horizon aid shows.
func _publish_indicator() -> void:
	var tr := current_traj()
	if tr.radius() < 1.0 or tr.pos().cross(tr.vel()).length() < 1e-6:
		return   # no trajectory yet (before a start phase is set up)
	var lvlh := Trajectory.lvlh_basis(tr.pos(), tr.vel())
	var rel := (lvlh.inverse() * Basis(_att())).get_rotation_quaternion()
	Bus.set_value(_ch("guid.indicator.lvlh"), rel)
	Bus.set_value(_ch("guid.indicator.attitude"), indicator_attitude(rel))


## The IMU's state on the Bus: the ICDU angles, whether the computer knows
## the platform's orientation, its mode, and whether REFSMMAT is the
## preferred orientation for the stored maneuver.
func _publish_imu() -> void:
	Bus.set_value(_ch("imu.icdu_deg"), icdu())
	Bus.set_value(_ch("imu.aligned"), imu.aligned)
	Bus.set_value(_ch("imu.mode"), imu.mode)
	Bus.set_value(_ch("imu.preferred"), preferred_valid and imu.aligned
		and Imu.rotation_vector(imu.refsmmat * preferred_refsmmat.transposed()).length() < 1e-6)


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
	for l in dsky.lamp_names:
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
		"vias": maneuver_vias.map(func(q: Quaternion) -> Array: return [q.x, q.y, q.z, q.w]),
		"auto_target": [auto_target.x, auto_target.y, auto_target.z, auto_target.w],
		"desired_q": [desired_q.x, desired_q.y, desired_q.z, desired_q.w],
		"nav": {"primary": nav.primary, "t": nav.t, "s": Array(nav.s), "field": nav.field_snapshot()} if nav != null else {},
		"nav_uplink_get": nav_uplink_get,
		"imu": imu.snapshot(),
		"preferred": Imu.rows_of(preferred_refsmmat) if preferred_valid else [],
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
	# The IMU first: a thrusting program needs its orientation known.
	imu.restore(d.get("imu", {}))
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
	# The attitude the program was flying to, which a restarted program
	# doesn't always work out again (P63 sets it once, before ignition).
	var at: Array = d.get("auto_target", [])
	if at.size() == 4:
		auto_target = Quaternion(at[0], at[1], at[2], at[3])
	var dq: Array = d.get("desired_q", [])
	if dq.size() == 4:
		desired_q = Quaternion(dq[0], dq[1], dq[2], dq[3])
	maneuver_vias.clear()
	for v in d.get("vias", []):
		maneuver_vias.append(Quaternion(v[0], v[1], v[2], v[3]))
	nav = null
	var nd: Dictionary = d.get("nav", {})
	if not nd.is_empty():
		nav = Trajectory.new().as_onboard(nav_model())
		nav.set_state_d(str(nd["primary"]), float(nd["t"]), PackedFloat64Array(nd["s"]))
		nav.restore_field(nd.get("field", {}))
	nav_uplink_get = float(d.get("nav_uplink_get", -1.0))
	var pr: Array = d.get("preferred", [])
	preferred_valid = pr.size() == 9
	if preferred_valid:
		preferred_refsmmat = Imu.from_rows(pr)
	_publish()

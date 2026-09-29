## The Stabilization and Control System (slice 9c): the CSM's backup to the
## CMC for its attitude and its thrust vector, on its own gyros
## [published: CSM Apollo Operations Handbook, SM2A-03-BLOCK II-(1),
## section 2.3].
##
## Attitude reference: the body-mounted attitude gyros (BMAGs) sense the
## body rates, each with a small drift [estimated]; the gyro display coupler
## (GDC) integrates them into an attitude. GDC ALIGN (ctl.scs.gdc_align)
## brings it to the IMU's, while the IMU is inertial and the CMC reads it
## [simplified: the handbook's GDC ALIGN drives it to the attitude set
## control panel's thumbwheels, which the crew set to the IMU's angles].
## With ATT SOURCE at SCS the FDAIs show the GDC's attitude (FDAI angles
## as the IMU's gimbal angles: scs.indicator.attitude), otherwise the
## CMC's (guid.indicator.attitude).
##
## Attitude control, ATT SOURCE at SCS: the rotational hand controller
## commands body rates in proportion to its deflection, 0.7°/s at full
## deflection with RATE LOW, 7°/s in pitch and yaw and 20°/s in roll with
## RATE HIGH. Released, the SCS holds the attitude the GDC had then, within
## the attitude deadband (ATT DEADBAND MIN: 0.2° with RATE LOW, 4° with
## HIGH; MAX: 4.2° and 8°), its rates within the rate deadband (0.2°/s LOW,
## 2°/s HIGH) [published: ibid., pp. 2.3-35 to 2.3-37]. As the handbook's
## switching amplifiers, the jets fire when the rate and the attitude
## error, scaled to the rate's deadband over the attitude's (1/s LOW,
## 0.5/s HIGH), add up past the rate deadband; MAX's limiter takes the
## first 4° of the error away. [simplified: ATT
## HOLD in all three axes; the MANUAL ATTITUDE switches' ACCEL CMD and MIN
## IMP, the limit cycle and the BMAG MODE switches left out]
##
## Thrust vector control: the SPS's gimbal, ±4.5° in pitch and yaw
## [published: ibid., p. 2.4-14]. Under the SCS, while the SPS fires, the
## gimbal holds the attitude (SCS TVC at AUTO), or the hand controller
## turns the vehicle on it (RATE CMD: MTVC, the BMAGs damping the rates);
## roll stays on the jets. Under the CMC the gimbal stays at its trim
## [simplified: the CMC steers its burns on the jets].
##
## SCS ΔV: THRUST ON, with the EMS's counter in ΔV at zero or more, starts
## the SPS and keeps it firing until the EMS's thrust-off (the counter below
## zero) or the ΔV THRUST switches go off [published: ibid., p. 2.3-56].
## Without the EMS in ΔV, THRUST ON fires the SPS while it is held.
##
## Reads:  ctl.scs.att_source, ctl.scs.rate (0 LOW, 1 HIGH),
##         ctl.scs.att_db (0 MIN, 1 MAX), ctl.scs.gdc_align,
##         ctl.scs.tvc (0 AUTO, 1 RATE CMD), ctl.rhc, ctl.sps.thrust_on,
##         ctl.sps.arm_a, ctl.sps.arm_b, dyn.omega, dyn.att_q, sps.on,
##         ems.thrust_off, ems.dv_mode, guid.indicator.attitude, imu.mode,
##         guid.fail, sys.powered
## Writes: scs.rot_cmd (the jets' duty cycles, as guid.rcs_rot_cmd),
##         scs.gimbal_cmd (the SPS gimbal, pitch and yaw, rad), scs.sps_on,
##         scs.busy (the clock keeps fine steps), scs.indicator.attitude,
##         scs.fdai.attitude (the FDAIs' source), scs.gdc_deg (the GDC's
##         angles as the FDAI shows them), scs.hold (attitude hold)
class_name Scs
extends Node

## Full-deflection rates, rad/s: RATE LOW (all axes), RATE HIGH (pitch and
## yaw; roll) [published: ibid., p. 2.3-37].
const RATE_LOW := 0.7 * PI / 180.0
const RATE_HIGH := 7.0 * PI / 180.0
const RATE_HIGH_ROLL := 20.0 * PI / 180.0
## Rate deadbands, rad/s, and attitude deadbands, rad: [MIN, MAX] for RATE
## LOW and HIGH [published: ibid., p. 2.3-35].
const RATE_DB := [0.2 * PI / 180.0, 2.0 * PI / 180.0]
const ATT_DB := [[0.2 * PI / 180.0, 4.2 * PI / 180.0], [4.0 * PI / 180.0, 8.0 * PI / 180.0]]
## ATT DEADBAND MAX's limiter, rad.
const DB_LIMITER := 4.0 * PI / 180.0
## The hand controller's detent, a fraction of full deflection.
const DETENT := 0.05
## The jets' duty cycle for a rate error, per rad/s [estimated: as the
## RCS's rate command].
const JET_GAIN := 25.0
## Above this body rate, rad/s, the SCS keeps the clock to fine steps.
const BUSY_RATE := 0.0005
## The SPS gimbal's travel, rad [published: ±4.5°].
const GIMBAL_MAX := 4.5 * PI / 180.0
## The TVC loop's time constants, s [estimated].
const TVC_TAU := 1.0
const TVC_RATE_TAU := 0.5

## The GDC's attitude: body to its reference, the IMU's stable member when
## it was aligned (as the IMU's gimbals, Imu.gimbals()).
var gdc: Basis = Basis.IDENTITY
## Each BMAG's drift, rad/s, body axes [estimated: a few tenths of a degree
## an hour].
var bmag_drift: Vector3 = Vector3(1.5e-6, -1.0e-6, 0.8e-6)
## The attitude held, as the GDC's (body to reference); valid while
## holding.
var hold: Basis = Basis.IDENTITY
var holding: bool = false
## THRUST ON latched under the EMS's ΔV.
var sps_latched: bool = false
var _align_was: bool = false
var _thrust_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish(Vector3.ZERO, Vector2.ZERO, false)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The IMU's attitude now, for GDC ALIGN, or null while the IMU isn't
## inertial or the CMC doesn't read it.
static func imu_attitude() -> Variant:
	if str(Bus.get_value("imu.mode", "")) != "operate" or bool(Bus.get_value("guid.fail", false)):
		return null
	if not Bus.has_channel("guid.indicator.attitude"):
		return null
	return Basis(Bus.get_value("guid.indicator.attitude") as Quaternion)


## Align the GDC to the IMU. Returns whether it could.
func align() -> bool:
	var a: Variant = imu_attitude()
	if a == null:
		return false
	gdc = a
	holding = false
	return true


func tick(dt: float) -> void:
	var w_true: Vector3 = Bus.get_value("dyn.omega", Vector3.ZERO)
	var w := w_true + bmag_drift
	if dt > 0.0 and w.length() > 0.0:
		gdc = (gdc * Basis(w.normalized(), w.length() * dt)).orthonormalized()
	var press := bool(Bus.get_value("ctl.scs.gdc_align", false))
	if press and not _align_was:
		align()
	_align_was = press
	var scs := int(Bus.get_value("ctl.scs.att_source", 0)) == 1 and bool(Bus.get_value("sys.powered", true))
	_thrust_logic(scs)
	if not scs:
		holding = false
		_publish(Vector3.ZERO, Vector2.ZERO, false)
		return
	var high := int(Bus.get_value("ctl.scs.rate", 0)) == 1
	var max_rate := Vector3(RATE_HIGH_ROLL, RATE_HIGH, RATE_HIGH) if high else Vector3.ONE * RATE_LOW
	var rate_db: float = RATE_DB[1 if high else 0]
	var gain: float = rate_db / float(ATT_DB[1 if high else 0][0])
	var limiter := DB_LIMITER if int(Bus.get_value("ctl.scs.att_db", 0)) == 1 else 0.0
	var rhc: Vector3 = Bus.get_value("ctl.rhc", Vector3.ZERO)
	var manual := absf(rhc.x) > DETENT or absf(rhc.y) > DETENT or absf(rhc.z) > DETENT
	var w_cmd := Vector3.ZERO
	if manual:
		w_cmd = rhc.clamp(-Vector3.ONE, Vector3.ONE) * max_rate
		holding = false
	else:
		if not holding:
			hold = gdc
			holding = true
		var e := error_to(hold)
		for i in 3:
			var beyond := signf(e[i]) * maxf(absf(e[i]) - limiter, 0.0)
			w_cmd[i] = clampf(beyond * gain, -max_rate[i], max_rate[i])
	var rot := Vector3.ZERO
	var gimbal := Vector2.ZERO
	var tvc := bool(Bus.get_value("sps.on", false))
	for i in 3:
		var err := w_cmd[i] - w[i]
		if tvc and i > 0:
			continue   # pitch and yaw on the gimbal
		if absf(err) > rate_db:
			rot[i] = clampf(err * JET_GAIN, -1.0, 1.0)
	if tvc:
		gimbal = _tvc(w, w_cmd, manual)
	_publish(rot, gimbal, manual or tvc or rot != Vector3.ZERO or w_true.length() > BUSY_RATE)


## The body-axes rotation (rad) from the GDC's attitude to [param target]
## (both body to reference).
func error_to(target: Basis) -> Vector3:
	var q := (gdc.inverse() * target).get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var s := Vector3(q.x, q.y, q.z)
	var sn := s.length()
	return Vector3.ZERO if sn < 1e-12 else s / sn * 2.0 * atan2(sn, q.w)


## The gimbal's pitch and yaw (rad) for the rates [param w_cmd] the SCS
## wants: the angular acceleration a deflection gives is the engine's
## thrust about its arm to the centre of mass, over the inertia. On AUTO
## the attitude loop's rates, on RATE CMD (MTVC) the hand controller's.
func _tvc(w: Vector3, w_cmd: Vector3, manual: bool) -> Vector2:
	var cfg := str(Bus.get_value("dyn.config", "csm"))
	var c := SpacecraftData.config(cfg)
	var arm := float(c.get("sps_gimbal_arm_m", 0.0))
	var thrust := float(SpacecraftData.section("sps")["thrust_n"])
	if arm <= 0.0:
		return Vector2.ZERO
	var inertia := SpacecraftData.inertia(cfg, float(Bus.get_value("dyn.mass_kg", c["ref_mass_kg"])))
	var want := w_cmd if manual or int(Bus.get_value("ctl.scs.tvc", 0)) == 0 else Vector3.ZERO
	var alpha := (want - w) / TVC_RATE_TAU
	var g := Vector2(alpha.y * inertia.y, alpha.z * inertia.z) / (thrust * arm)
	return Vector2(clampf(asin(clampf(g.x, -1.0, 1.0)), -GIMBAL_MAX, GIMBAL_MAX),
		clampf(asin(clampf(g.y, -1.0, 1.0)), -GIMBAL_MAX, GIMBAL_MAX))


## THRUST ON under the EMS's ΔV latches the SPS on until the EMS's
## thrust-off or the ΔV THRUST switches; the EMS's thrust-off keeps it
## from starting.
func _thrust_logic(scs: bool) -> void:
	var press := bool(Bus.get_value("ctl.sps.thrust_on", false))
	var armed := bool(Bus.get_value("ctl.sps.arm_a", false)) or bool(Bus.get_value("ctl.sps.arm_b", false))
	var dv_mode := bool(Bus.get_value("ems.dv_mode", false))
	var off := bool(Bus.get_value("ems.thrust_off", false))
	if press and not _thrust_was and dv_mode and not off and armed and scs:
		sps_latched = true
	_thrust_was = press
	if off or not armed or not dv_mode:
		sps_latched = false


func _publish(rot: Vector3, gimbal: Vector2, busy: bool) -> void:
	var scs := int(Bus.get_value("ctl.scs.att_source", 0)) == 1
	var q := gdc.get_rotation_quaternion()
	Bus.set_value("scs.rot_cmd", rot)
	Bus.set_value("scs.gimbal_cmd", gimbal)
	Bus.set_value("scs.sps_on", sps_latched)
	Bus.set_value("scs.busy", busy)
	Bus.set_value("scs.hold", holding)
	Bus.set_value("scs.indicator.attitude", q)
	Bus.set_value("scs.gdc_deg", Imu.gimbal_angles(gdc))
	Bus.set_value("scs.fdai.attitude", q if scs else Bus.get_value("guid.indicator.attitude", q))


func snapshot() -> Dictionary:
	return {"gdc": Imu.rows_of(gdc), "hold": Imu.rows_of(hold), "holding": holding,
		"drift": [bmag_drift.x, bmag_drift.y, bmag_drift.z], "latched": sps_latched}


func restore(d: Dictionary) -> void:
	gdc = Imu.from_rows(d.get("gdc", Imu.rows_of(Basis.IDENTITY)))
	hold = Imu.from_rows(d.get("hold", Imu.rows_of(Basis.IDENTITY)))
	holding = bool(d.get("holding", false))
	var dr: Array = d.get("drift", [bmag_drift.x, bmag_drift.y, bmag_drift.z])
	bmag_drift = Vector3(dr[0], dr[1], dr[2])
	sps_latched = bool(d.get("latched", false))
	_align_was = bool(Bus.get_value("ctl.scs.gdc_align", false))
	_thrust_was = bool(Bus.get_value("ctl.sps.thrust_on", false))
	_publish(Vector3.ZERO, Vector2.ZERO, false)

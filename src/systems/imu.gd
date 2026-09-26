## An Inertial Measurement Unit and what its computer knows of it: the
## stable member's true orientation (the platform), the orientation the
## computer holds for it (REFSMMAT), and the flag that says that holds
## (REFSMFLG). Both are kept the Apollo way round, as matrices from the
## reference frame (ECI) to stable member axes: their rows are the stable
## member's axes in ECI.
##
## The computer reads the vehicle's attitude through the gimbal angles
## (ICDU angles: outer about body X, inner about the stable member's Y,
## middle between them) and takes the stable member to lie at REFSMMAT, so
## it sees attitudes and sensed ΔV turned by the misalignment between the
## two (attitude(), sensed()). The gyros drift the platform away from
## REFSMMAT; the computer's alignments bring it back: a coarse align drives
## the gimbals to a set of angles, to within the servos' accuracy, and a
## fine align torques the gyros through small angles.
##
## Gimbal lock: past LOCK_LAMP_DEG of middle gimbal angle the computer
## lights GIMBAL LOCK, and past LOCK_CAGE_DEG it puts the IMU in coarse
## align to keep the gimbals from running away (Colossus's gimbal lock
## monitor). The platform then turns with the vehicle, frozen at its gimbal
## angles, and the alignment is lost until the crew coarse aligns it again
## and finds its orientation from the stars (P51).
##
## An ideal IMU (the LGC's [simplified: its alignments, P52 with the AOT
## and P57, are left for later]) has REFSMMAT the ECI frame, never drifts
## and never loses its alignment; its GIMBAL LOCK lamp lights past
## IDEAL_LAMP_DEG.
class_name Imu
extends RefCounted

## Middle gimbal angle beyond which GIMBAL LOCK lights, deg.
const LOCK_LAMP_DEG := 70.0
## Middle gimbal angle beyond which the computer cages the IMU, deg.
const LOCK_CAGE_DEG := 85.0
## An ideal IMU's GIMBAL LOCK lamp, deg.
const IDEAL_LAMP_DEG := 85.0
## A coarse align drives the gimbals at this rate, deg/s, and settles for
## COARSE_SETTLE_S [estimated].
const COARSE_RATE_DEG_S := 12.0
const COARSE_SETTLE_S := 2.0
## One count of a CDU: 2^-15 of a turn, deg.
const CDU_DEG := 360.0 / 32768.0

## Reference (ECI) to stable member: what the computer holds.
var refsmmat: Basis = Basis.IDENTITY
## Reference (ECI) to stable member: where the stable member truly is.
var platform: Basis = Basis.IDENTITY
## REFSMFLG: the computer knows the platform's orientation.
var aligned: bool = true
## Gyro drift: the platform's rate about its own axes, rad/s. A new rate
## drifts on from where the platform is.
var drift: Vector3 = Vector3.ZERO:
	set(v):
		_set_platform(platform)
		drift = v
## One standard deviation of a coarse align's error about each axis, deg.
var coarse_sigma_deg: float = 0.0
## "operate": inertial. "coarse": being driven to coarse_target (NO ATT).
## "caged": held at coarse_target after a gimbal lock (NO ATT).
var mode: String = "operate"
## Body to stable member: the gimbal angles a coarse align drives to, or
## holds while caged.
var coarse_target: Basis = Basis.IDENTITY
## Time left in the coarse align, s.
var coarse_left: float = 0.0
var ideal: bool = false
var _rng := RandomNumberGenerator.new()
## The platform's orientation when it was last set, and the time it has
## drifted since (s): a step's drift is far below a float's resolution
## (Basis is single precision), so the platform is worked out from these.
var _platform0: Basis = Basis.IDENTITY
var _drift_t: float = 0.0


## Draw the gyro drift about each axis from [param seed] (standard
## deviation [param drift_deg_h], deg/h) and seed the coarse aligns'
## errors, whose standard deviation is [param coarse_deg].
func disperse(seed: int, drift_deg_h: float, coarse_deg: float) -> void:
	_rng.seed = seed
	var s := deg_to_rad(drift_deg_h) / 3600.0
	drift = Vector3(_rng.randfn(0.0, s), _rng.randfn(0.0, s), _rng.randfn(0.0, s))
	coarse_sigma_deg = coarse_deg


## The platform at [param m], and REFSMMAT with it: a fresh alignment.
func align(m: Basis) -> void:
	refsmmat = m
	_set_platform(m)
	aligned = true
	mode = "operate"
	coarse_left = 0.0


## The platform set to [param b], where it drifts on from.
func _set_platform(b: Basis) -> void:
	platform = b.orthonormalized()
	_platform0 = platform
	_drift_t = 0.0


## The ICDU angles for body-to-stable-member [param g] (deg, 0-360, to a
## CDU count): outer, inner, middle.
static func gimbal_angles(g: Basis) -> Vector3:
	var e := g.orthonormalized().get_euler(EULER_ORDER_YZX)
	return Vector3(_cdu(e.x), _cdu(e.y), _cdu(e.z))


## An angle [param rad] as a CDU reads it: to a count, 0-360 deg.
static func _cdu(rad: float) -> float:
	return fposmod(snappedf(rad_to_deg(rad), CDU_DEG), 360.0)


## Body to stable member for ICDU angles [param deg] (outer, inner,
## middle).
static func gimbal_basis(deg: Vector3) -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z)), EULER_ORDER_YZX)


## A REFSMMAT whose stable member axes are [param x], [param y] and
## [param z] (ECI).
static func from_axes(x: Vector3, y: Vector3, z: Vector3) -> Basis:
	return Basis(x.normalized(), y.normalized(), z.normalized()).orthonormalized().transposed()


## The stable member's axis [param i] (0 X, 1 Y, 2 Z) in ECI for
## [param m].
static func axis(m: Basis, i: int) -> Vector3:
	return m.transposed()[i]


## The preferred orientation for a burn along [param dv] at [param r]:
## X along the thrust, Y along X × R, Z down, so the burn attitude (heads
## up, AgcCore.burn_attitude()) is at zero gimbal angles.
static func preferred(dv: Vector3, r: Vector3) -> Basis:
	var x := dv.normalized()
	var y := x.cross(r).normalized()
	return from_axes(x, y, x.cross(y))


## The nominal orientation: the local vertical frame at [param r],
## [param v] (X forward, Y against the orbit's normal, Z down).
static func nominal(r: Vector3, v: Vector3) -> Basis:
	return Trajectory.lvlh_basis(r, v).transposed()


## The landing site orientation: X up through the site at [param site]
## (from the Moon's centre, at the landing time), Z downrange in the orbit
## of angular momentum [param h], Y completing them.
static func landing_site(site: Vector3, h: Vector3) -> Basis:
	var x := site.normalized()
	var z := h.cross(x).normalized()
	return from_axes(x, z.cross(x), z)


## Body to stable member for body-to-ECI [param body]: the gimbals.
func gimbals(body: Basis) -> Basis:
	return platform * body


func icdu(body: Basis) -> Vector3:
	return gimbal_angles(gimbals(body))


## The attitude the computer reads for true attitude [param q].
func attitude(q: Quaternion) -> Quaternion:
	if ideal:
		return q
	return (refsmmat.transposed() * platform * Basis(q)).get_rotation_quaternion()


## The computer's view of ΔV [param dv] (ECI) that the platform's
## accelerometers sensed.
func sensed(dv: Vector3) -> Vector3:
	if ideal:
		return dv
	return refsmmat.transposed() * (platform * dv)


## How far the computer's reference is turned from ECI: the rotation
## vector (rad, ECI) of REFSMMAT's transpose times the platform.
func misalignment() -> Vector3:
	return rotation_vector(refsmmat.transposed() * platform)


static func rotation_vector(b: Basis) -> Vector3:
	var q := b.orthonormalized().get_rotation_quaternion()
	if q.w < 0.0:
		q = -q
	var s := Vector3(q.x, q.y, q.z)
	var n := s.length()
	if n < 1e-15:
		return Vector3.ZERO
	return s / n * 2.0 * atan2(n, q.w)


## A rotation of [param v] (axis times angle, rad).
static func rotation(v: Vector3) -> Basis:
	var a := v.length()
	if a < 1e-15:
		return Basis.IDENTITY
	return Basis(v / a, a)


## The IMU is on the platform's orientation, not in coarse align or caged.
func operating() -> bool:
	return mode == "operate"


## Drive the gimbals to body-to-stable-member [param target], with the
## vehicle at [param body].
func coarse_align(target: Basis, body: Basis) -> void:
	if ideal:
		return
	var now := gimbal_angles(gimbals(body))
	var want := gimbal_angles(target)
	var d := 0.0
	for i in 3:
		d = maxf(d, absf(wrapf(want[i] - now[i], -180.0, 180.0)))
	mode = "coarse"
	coarse_target = target
	coarse_left = COARSE_SETTLE_S + d / COARSE_RATE_DEG_S


## Torque the gyros through [param angles] (rad about the stable member's
## axes): a fine align.
func torque(angles: Vector3) -> void:
	if ideal:
		return
	_set_platform(rotation(angles) * platform)


## Step [param dt] with the vehicle at [param body] (body to ECI).
func step(dt: float, body: Basis) -> void:
	if ideal:
		return
	match mode:
		"operate":
			if drift != Vector3.ZERO:
				_drift_t += dt
				platform = (rotation(-drift * _drift_t) * _platform0).orthonormalized()
			if absf(wrapf(icdu(body).z, -180.0, 180.0)) > LOCK_CAGE_DEG:
				# Gimbal lock: caged where the gimbals are.
				mode = "caged"
				coarse_target = gimbals(body)
				aligned = false
		"coarse":
			_set_platform(coarse_target * body.inverse())
			coarse_left -= dt
			if coarse_left <= 0.0:
				coarse_left = 0.0
				mode = "operate"
				_set_platform(rotation(_coarse_error()) * platform)
		"caged":
			_set_platform(coarse_target * body.inverse())


func _coarse_error() -> Vector3:
	var s := deg_to_rad(coarse_sigma_deg)
	if s <= 0.0:
		return Vector3.ZERO
	return Vector3(_rng.randfn(0.0, s), _rng.randfn(0.0, s), _rng.randfn(0.0, s))


## GIMBAL LOCK for the vehicle at [param body].
func lock_lamp(body: Basis) -> bool:
	var mg := absf(wrapf(icdu(body).z, -180.0, 180.0))
	return mg > (IDEAL_LAMP_DEG if ideal else LOCK_LAMP_DEG)


static func rows_of(b: Basis) -> Array:
	var t := b.transposed()
	return [t.x.x, t.x.y, t.x.z, t.y.x, t.y.y, t.y.z, t.z.x, t.z.y, t.z.z]


static func from_rows(a: Array) -> Basis:
	return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8])).transposed()


func snapshot() -> Dictionary:
	return {
		"refsmmat": rows_of(refsmmat), "platform": rows_of(_platform0), "drift_t": _drift_t, "aligned": aligned,
		"drift": [drift.x, drift.y, drift.z], "coarse_sigma_deg": coarse_sigma_deg, "mode": mode,
		"coarse_target": rows_of(coarse_target), "coarse_left": coarse_left, "rng_state": str(_rng.state),
	}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	refsmmat = from_rows(d["refsmmat"])
	var a: Array = d["drift"]
	drift = Vector3(a[0], a[1], a[2])
	_set_platform(from_rows(d["platform"]))
	_drift_t = float(d.get("drift_t", 0.0))
	platform = (rotation(-drift * _drift_t) * _platform0).orthonormalized()
	aligned = bool(d["aligned"])
	coarse_sigma_deg = float(d["coarse_sigma_deg"])
	mode = str(d["mode"])
	coarse_target = from_rows(d["coarse_target"])
	coarse_left = float(d["coarse_left"])
	_rng.state = str(d["rng_state"]).to_int()

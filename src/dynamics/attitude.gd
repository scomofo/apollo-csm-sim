## Rigid-body attitude dynamics, adapted from src/dynamics/attitude.gd of
## gemini-capsule (https://github.com/scomofo/gemini-capsule) with sub-stepping
## for long coast steps. q is the rotation taking body-frame vectors to ECI;
## omega is the body rate vector in rad/s.
class_name Attitude
extends RefCounted

var q: Quaternion = Quaternion.IDENTITY   ## eci_from_body
var omega: Vector3 = Vector3.ZERO         ## body rates, rad/s (about X roll, Y pitch, Z yaw)
var inertia: Vector3 = Vector3(22000.0, 95000.0, 95000.0)  ## principal, kg·m² [estimated]

const MAX_SUBSTEP := 0.25


## Advance by dt with body torque [param torque_body] (N·m). Semi-implicit
## Euler on the rates, exact rotation for the kinematics, sub-stepped so a
## long coast step (up to a minute) does not destabilise torque-free
## nutation of an asymmetric body.
func step(dt: float, torque_body: Vector3 = Vector3.ZERO) -> void:
	var n := maxi(1, int(ceil(dt / MAX_SUBSTEP)))
	var h := dt / n
	for _i in n:
		var i_w := Vector3(inertia.x * omega.x, inertia.y * omega.y, inertia.z * omega.z)
		var gyro := omega.cross(i_w)
		var alpha := Vector3(
			(torque_body.x - gyro.x) / inertia.x,
			(torque_body.y - gyro.y) / inertia.y,
			(torque_body.z - gyro.z) / inertia.z)
		omega += alpha * h
		var w := omega.length()
		if w > 1e-12:
			q = (q * Quaternion(omega / w, w * h)).normalized()


func body_from_eci() -> Basis:
	return Basis(q).inverse()


func eci_from_body() -> Basis:
	return Basis(q)


## Align the body with a reference basis whose columns are body axes in ECI.
func align_to(basis_eci_from_body: Basis) -> void:
	q = basis_eci_from_body.orthonormalized().get_rotation_quaternion()

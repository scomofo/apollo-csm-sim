## The LM's alignment optical telescope (AOT), on the navigation base
## beside the IMU: a unity-power periscope with a FIELD_DEG field, its line
## of sight ELEVATION_DEG from the LM's +X axis, turned by the detent knob
## to six detents DETENT_STEP_DEG apart: 1 left front, 2 front (in the X-Z
## plane, looking forward and up), 3 right front, 4 right rear, 5 rear (CL,
## the stowed position: no view) and 6 left rear [published: the Apollo
## Lunar Module News Reference, on the Apollo Lunar Surface Journal's AOT
## page; the numbering, Apollo 12 Mission Report, MSC-01855, Table 8.6-I].
## Docked to the CSM the crews used the front detent alone [published:
## ibid.; the CSM's bulk in the other fields isn't drawn].
##
## The reticle: the Y-line, parallel to the LM's X axis in the front detent
## at the reticle's zero, and the X-line across it [simplified: the
## spirals and the reticle's rotation, for the surface's P57, are left for
## slice 11b]. In the other detents the field appears turned against the
## reticle, by the detent's azimuth from the front's, as Luminary allowed
## (AOTMARK's OPTAXIS) [published: Luminary 099]. A star on the Y-line lies
## in the plane through the line of sight whose normal is planes()[1], on
## the X-line in the one whose normal is planes()[2].
##
## MARK X, MARK Y and REJECT, on the computer control and reticle dimmer
## assembly, go to the LGC (channel 16), which reads them itself.
##
## Reads:  ctl.lm.aot.detent (1 to 6)
## Writes: lm.aot.detent, lm.aot.az_deg (the detent's azimuth, from +Z
##         toward +Y), lm.aot.los_body (the line of sight, body axes),
##         lm.aot.right_body and lm.aot.up_body (the view's right, along
##         the X-line, and up, along the Y-line, body axes)
class_name Aot
extends Node

const FIELD_DEG := 60.0
const ELEVATION_DEG := 45.0
const DETENT_STEP_DEG := 60.0
## The rear detent: the stowed position, the prism covered.
const CL := 5

var detent: int = 2


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## Detent [param d]'s azimuth, deg, from +Z toward +Y: -60 for 1, the left
## front, round to -120 for 6, the left rear.
static func azimuth(d: int) -> float:
	return wrapf((d - 2) * DETENT_STEP_DEG, -180.0, 180.0)


## The optic axis for azimuth [param az_deg] and elevation [param el_deg]
## (deg), a unit vector in the LM's body axes (Luminary's OANB).
static func optic_axis(az_deg: float, el_deg: float = ELEVATION_DEG) -> Vector3:
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	return Vector3(sin(el), cos(el) * sin(az), cos(el) * cos(az))


## The optic axis and the reticle's two mark planes' normals, body axes,
## for azimuth [param az_deg]: [the axis, the Y-line's plane's normal, the
## X-line's]. The planes turn about the axis by the field's apparent
## rotation, the front detent's azimuth less this one's (OANB and OPTAXIS).
static func planes(az_deg: float, el_deg: float = ELEVATION_DEG) -> Array:
	var oa := optic_axis(az_deg, el_deg)
	var az := deg_to_rad(az_deg)
	var uyp := Vector3(0.0, cos(az), -sin(az))
	var uxp := uyp.cross(oa).normalized()
	var rot := deg_to_rad(azimuth(2) - az_deg)
	return [oa, uyp * cos(rot) - uxp * sin(rot), uxp * cos(rot) + uyp * sin(rot)]


## The view through detent [param d]: its right (along the X-line), its up
## (along the Y-line) and its line of sight, body axes.
static func view_axes(d: int) -> Array:
	var p := planes(azimuth(d))
	return [p[1], p[2], p[0]]


func tick(_dt: float) -> void:
	detent = clampi(int(Bus.get_value("ctl.lm.aot.detent", 2)), 1, 6)
	_publish()


func _publish() -> void:
	var v := view_axes(detent)
	Bus.set_value("lm.aot.detent", detent)
	Bus.set_value("lm.aot.az_deg", azimuth(detent))
	Bus.set_value("lm.aot.right_body", v[0])
	Bus.set_value("lm.aot.up_body", v[1])
	Bus.set_value("lm.aot.los_body", v[2])


func snapshot() -> Dictionary:
	return {"detent": detent}


func restore(d: Dictionary) -> void:
	detent = int(d.get("detent", 2))
	_publish()

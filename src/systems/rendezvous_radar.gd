## Rendezvous radar: the LM's radar that tracks the transponder on the CSM.
## It measures the range to the CSM, the range rate, and the line of sight
## in the LM's axes, while the LM flies free, the CSM is within its range
## and the Moon isn't in the way. [simplified: noise-free; the antenna finds
## and follows the CSM wherever it is, without gimbal limits or a manual
## slew and lock-on.]
##
## It measures after Dynamics has stepped (stage DEPENDENT), so the LGC
## reads it next step against its state vectors for the same instant.
##
## Reads:  lm.dyn.primary, lm.dyn.r_m, lm.dyn.v_mps, lm.dyn.att_q,
##         dyn.primary, dyn.r_m, dyn.v_mps, lm.sys.powered, dock.state
## Writes: lm.rr.range_m (0 without data), lm.rr.range_rate_mps (positive
##         opening), lm.rr.los_body (the line of sight, LM axes),
##         lm.rr.data_good
class_name RendezvousRadar
extends Node

var range_m: float = 0.0
var range_rate: float = 0.0
var los_body: Vector3 = Vector3.ZERO
var data_good: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.DEPENDENT)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(_dt: float) -> void:
	var lm_r: Array = Bus.get_value("lm.dyn.r_m", [0.0, 0.0, 0.0])
	var cm_r: Array = Bus.get_value("dyn.r_m", [0.0, 0.0, 0.0])
	var on := str(Bus.get_value("dock.state", "")) == "free" and bool(Bus.get_value("lm.sys.powered", true)) \
		and str(Bus.get_value("lm.dyn.primary", "")) == "moon" and str(Bus.get_value("dyn.primary", "")) == "moon"
	# The line of sight, in doubles before it is a Vector3.
	var d := [float(cm_r[0]) - float(lm_r[0]), float(cm_r[1]) - float(lm_r[1]), float(cm_r[2]) - float(lm_r[2])]
	var rng := sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2])
	data_good = on and rng > 0.0 and rng <= float(SpacecraftData.section("rendezvous_radar")["range_max_m"]) \
		and not blocked(lm_r, d)
	if not data_good:
		range_m = 0.0
		range_rate = 0.0
		los_body = Vector3.ZERO
		_publish()
		return
	var los := Vector3(d[0], d[1], d[2]) / rng
	var lm_v: Array = Bus.get_value("lm.dyn.v_mps", [0.0, 0.0, 0.0])
	var cm_v: Array = Bus.get_value("dyn.v_mps", [0.0, 0.0, 0.0])
	var rel_v := Vector3(float(cm_v[0]) - float(lm_v[0]), float(cm_v[1]) - float(lm_v[1]),
		float(cm_v[2]) - float(lm_v[2]))
	range_m = rng
	range_rate = rel_v.dot(los)
	los_body = Basis(Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY)).inverse() * los
	_publish()


## The Moon stands between the LM at [param r] and the CSM [param d] from
## it (m, Moon-centred): the line between them passes inside its
## reference sphere.
static func blocked(r: Array, d: Array) -> bool:
	var dd := float(d[0]) * float(d[0]) + float(d[1]) * float(d[1]) + float(d[2]) * float(d[2])
	var rd := float(r[0]) * float(d[0]) + float(r[1]) * float(d[1]) + float(r[2]) * float(d[2])
	var k := clampf(-rd / maxf(dd, 1e-9), 0.0, 1.0)
	var p := [float(r[0]) + float(d[0]) * k, float(r[1]) + float(d[1]) * k, float(r[2]) + float(d[2]) * k]
	return p[0] * p[0] + p[1] * p[1] + p[2] * p[2] < Bodies.R_MOON * Bodies.R_MOON


func _publish() -> void:
	Bus.set_value("lm.rr.range_m", range_m)
	Bus.set_value("lm.rr.range_rate_mps", range_rate)
	Bus.set_value("lm.rr.los_body", los_body)
	Bus.set_value("lm.rr.data_good", data_good)


func snapshot() -> Dictionary:
	return {}


## Measure again, from the vehicles as restored (Dynamics restores them
## first): what the radar measured at the end of the step the checkpoint
## was taken after, which the LGC's next mark reads.
func restore(_d: Dictionary) -> void:
	tick(0.0)

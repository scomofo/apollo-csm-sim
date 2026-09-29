## LM Reaction Control System: sixteen jets in four quads on the ascent
## stage, fed by two independent systems, A and B.
##
## Jets are modelled per axis, not per nozzle, as the CSM's RCS is
## (src/systems/rcs.gd): each system fires rotation_jets jets about each
## rotation axis, x_jets for +/-X translation and yz_jets for each of
## +/-Y and +/-Z [estimated]. A system shut off (ctl.lm.rcs.sys_a or _b)
## or empty drops its share. Commands are continuous in [-1, 1] and stand
## for the jet duty cycle over the step (pulse-width modulation).
##
## Rotation comes from the guidance the guidance control switch selects
## (ctl.lm.guid_cont): the LGC's digital autopilot (lm.guid.rcs_rot_cmd)
## or the AGS's hold (lm.ags.rcs_rot_cmd) [simplified: no hardover or
## direct modes]; translation from the TTCA (ctl.lm.thc, past its detent)
## plus, under the PGNS, lm.guid.rcs_trans_cmd (P41's +X). The jets fire
## while the LM's buses are powered (lm.sys.powered: flying free, or docked
## once its crew has powered it up, when they fly the stack), and never
## across a coarse coast step.
##
## A system's helium regulator can fail (slice 9e: fail("a") or "b", the
## failure catalog's lm_rcs_a and lm_rcs_b): its pressure out of limits,
## the RCS A or B REG warning comes on (LmCautionWarning) and the system's
## jets stop [simplified: at once]; closing its main shutoff valves (the
## system's switch) puts the light out.
##
## Reads:  lm.guid.rcs_rot_cmd, lm.guid.rcs_trans_cmd, lm.ags.rcs_rot_cmd,
##         ctl.lm.guid_cont, ctl.lm.thc, ctl.lm.rcs.sys_a, ctl.lm.rcs.sys_b,
##         lm.sys.powered
## Writes: lm.rcs.force_body, lm.rcs.torque_body, lm.rcs.active_jets,
##         lm.rcs.sys_a_kg, lm.rcs.sys_b_kg, lm.rcs.prop_kg,
##         lm.rcs.sys_a_failed, lm.rcs.sys_b_failed, lm.rcs.sys_a_live,
##         lm.rcs.sys_b_live
extends Node

const SYSTEMS := ["a", "b"]
## The TTCA's detent: a smaller deflection commands nothing.
const DEADBAND := 0.05

var sys_kg: Array[float] = []
## Each system's regulator failed.
var failed: Array[bool] = [false, false]
## The jets were last published idle.
var _quiet: bool = false


func _ready() -> void:
	if sys_kg.is_empty():
		for s in SYSTEMS:
			sys_kg.append(float(SpacecraftData.section("lm_rcs")["system_propellant_kg"]))
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish(Vector3.ZERO, Vector3.ZERO, 0)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


static func _db(v: float) -> float:
	return 0.0 if absf(v) < DEADBAND else clampf(v, -1.0, 1.0)


func tick(dt: float) -> void:
	if not bool(Bus.get_value("lm.sys.powered", false)) or dt > SimClock.FIXED_DT * 1.5:
		if not _quiet:
			_publish(Vector3.ZERO, Vector3.ZERO, 0)
			_quiet = true
		return
	_quiet = false
	var d := SpacecraftData.section("lm_rcs")
	var pgns := int(Bus.get_value("ctl.lm.guid_cont", 0)) == 0
	var rot: Vector3 = Bus.get_value("lm.guid.rcs_rot_cmd" if pgns else "lm.ags.rcs_rot_cmd", Vector3.ZERO)
	rot = rot.clamp(-Vector3.ONE, Vector3.ONE)
	var thc: Vector3 = Bus.get_value("ctl.lm.thc", Vector3.ZERO)
	var trans: Vector3 = Vector3(_db(thc.x), _db(thc.y), _db(thc.z))
	if pgns:
		trans += Bus.get_value("lm.guid.rcs_trans_cmd", Vector3.ZERO)
	trans = trans.clamp(-Vector3.ONE, Vector3.ONE)
	var f := float(d["jet_thrust_n"])
	var n_rot := float(d["rotation_jets"])
	var n_x := float(d["x_jets"])
	var n_yz := float(d["yz_jets"])
	var mdot := f / (float(d["isp_s"]) * Units.G0)
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var jets := 0.0
	for i in SYSTEMS.size():
		if not _live(i):
			continue
		torque += rot * (f * float(d["arm_m"]) * n_rot)
		force += Vector3(trans.x * n_x, trans.y * n_yz, trans.z * n_yz) * f
		var duty := (absf(rot.x) + absf(rot.y) + absf(rot.z)) * n_rot + absf(trans.x) * n_x + (absf(trans.y) + absf(trans.z)) * n_yz
		jets += duty
		sys_kg[i] = maxf(0.0, sys_kg[i] - duty * mdot * dt)
	_publish(force, torque, int(round(jets)))


## Fail system [param part]'s regulator: "a" or "b".
func fail(part: String) -> void:
	var i := SYSTEMS.find(part)
	if i >= 0:
		failed[i] = true
		_publish(Vector3.ZERO, Vector3.ZERO, 0)


## System [param i] can fire: its valves open, its regulator working and
## its propellant left.
func _live(i: int) -> bool:
	return bool(Bus.get_value("ctl.lm.rcs.sys_" + SYSTEMS[i], true)) and not failed[i] and sys_kg[i] > 0.0


func _publish(force: Vector3, torque: Vector3, jets: int) -> void:
	Bus.set_value("lm.rcs.force_body", force)
	Bus.set_value("lm.rcs.torque_body", torque)
	Bus.set_value("lm.rcs.active_jets", jets)
	for i in SYSTEMS.size():
		Bus.set_value("lm.rcs.sys_%s_kg" % SYSTEMS[i], sys_kg[i])
		Bus.set_value("lm.rcs.sys_%s_failed" % SYSTEMS[i], failed[i])
		Bus.set_value("lm.rcs.sys_%s_live" % SYSTEMS[i], _live(i))
	Bus.set_value("lm.rcs.prop_kg", sys_kg[0] + sys_kg[1])


func snapshot() -> Dictionary:
	return {"systems": sys_kg.duplicate(), "failed": failed.duplicate()}


func restore(d: Dictionary) -> void:
	for i in SYSTEMS.size():
		sys_kg[i] = float(d["systems"][i])
		failed[i] = bool((d.get("failed", [false, false]) as Array)[i])
	_publish(Vector3.ZERO, Vector3.ZERO, 0)

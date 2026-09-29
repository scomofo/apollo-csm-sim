## Reaction Control Systems: four Service Module quads (A-D) while the SM is
## attached, the two Command Module rings after CM/SM separation (with the
## LM docked too, Apollo 13's).
##
## Jets are modelled per axis, not per nozzle: each rotation or translation
## axis is served by a fixed set of quads (roll by all four, pitch and +/-Z
## translation by A and C, yaw and +/-Y translation by B and D, +/-X by all
## four), each contributing one 100 lbf jet. A disabled or empty quad drops
## its share of authority. Commands are continuous in [-1, 1] and stand for
## the jet duty cycle over the step (pulse-width modulation).
##
## Rotation command source (ctl.scs.att_source):
##   0 CMC   the computer's digital autopilot (guid.rcs_rot_cmd)
##   1 SCS   Stabilization and Control System rate command from the RHC
##   2 DIRECT RHC straight to the jets (direct coils)
## Translation always comes from the THC (ctl.thc) plus guid.rcs_trans_cmd.
##
## The failure catalog (data/failures.json, slice 9a) fails a quad through
## fail("quad_<x>"): its helium fails, its secondary fuel pressure falls
## below the caution and warning limit (SM RCS <X>) and its jets stop
## [simplified: at once]. Its switch still reads as the crew left it.
##
## Writes: rcs.force_body, rcs.torque_body, rcs.quad_<x>_kg, rcs.sm_prop_kg,
##         rcs.cm_prop_kg, rcs.active_jets, rcs.quad_<x>_psia (the
##         secondary fuel pressure), rcs.quad_<x>_live (the quad feeds its
##         jets: switched on, with propellant and pressure)
extends Node

const QUADS := ["a", "b", "c", "d"]
## SCS rate-command gains: full RHC deflection commands this rate.
const SCS_MAX_RATE := 0.034906585  # 2 deg/s
const SCS_GAIN := 25.0
const DEADBAND := 0.05
## A quad's secondary fuel pressure in flight, psia [estimated: within the
## caution and warning limits, 145 to 215 psia, AOH p. 2.10-5].
const FUEL_PSIA := 180.0

var quad_kg: Array[float] = []
var ring_kg: Array[float] = []
## Each quad failed (its helium).
var failed: Array[bool] = [false, false, false, false]


func _ready() -> void:
	var sm := SpacecraftData.section("sm_rcs")
	var cm := SpacecraftData.section("cm_rcs")
	if quad_kg.is_empty():
		for q in QUADS:
			quad_kg.append(float(sm["quad_propellant_kg"]))
	if ring_kg.is_empty():
		ring_kg.append(float(cm["ring_propellant_kg"]))
		ring_kg.append(float(cm["ring_propellant_kg"]))
	for q in QUADS:
		if not Bus.has_channel("ctl.rcs.quad_" + q):
			Bus.set_value("ctl.rcs.quad_" + q, true)
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish(Vector3.ZERO, Vector3.ZERO, 0)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


static func _db(v: float) -> float:
	return 0.0 if absf(v) < DEADBAND else clampf(v, -1.0, 1.0)


static func _db3(v: Vector3) -> Vector3:
	return Vector3(_db(v.x), _db(v.y), _db(v.z))


## Rotation command for this step. The hand-controller deadband applies to
## crew inputs only; the CMC autopilot's duty cycles pass through unchanged.
func rotation_command() -> Vector3:
	var src := int(Bus.get_value("ctl.scs.att_source", 0))
	var rhc := _db3(Bus.get_value("ctl.rhc", Vector3.ZERO))
	match src:
		1:
			var w: Vector3 = Bus.get_value("dyn.omega", Vector3.ZERO)
			var err := rhc * SCS_MAX_RATE - w
			if err.length() < 0.0005:
				return Vector3.ZERO
			return (err * SCS_GAIN).clamp(-Vector3.ONE, Vector3.ONE)
		2:
			return rhc
		_:
			var c: Vector3 = Bus.get_value("guid.rcs_rot_cmd", Vector3.ZERO)
			return c.clamp(-Vector3.ONE, Vector3.ONE)


func tick(dt: float) -> void:
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	# Jets never fire across a coarse coast step: the clock only takes one
	# when nothing was firing, and a controller that wakes up mid-coast
	# fires on the next (fine) step instead.
	if cfg == "stack" or not bool(Bus.get_value("sys.powered", true)) or dt > SimClock.FIXED_DT * 1.5:
		_publish(Vector3.ZERO, Vector3.ZERO, 0)
		return
	var rot := rotation_command()
	var trans: Vector3 = _db3(Bus.get_value("ctl.thc", Vector3.ZERO)) + Bus.get_value("guid.rcs_trans_cmd", Vector3.ZERO)
	trans = trans.clamp(-Vector3.ONE, Vector3.ONE)
	var c := SpacecraftData.config(cfg)
	var arm_p := float(c["rcs_pitch_arm_m"])
	var arm_r := float(c["rcs_roll_arm_m"])
	var force := Vector3.ZERO
	var torque := Vector3.ZERO
	var jets := 0.0
	if not SpacecraftData.sm_attached(cfg):
		var cmd := SpacecraftData.section("cm_rcs")
		var f := float(cmd["jet_thrust_n"])
		var live := 0
		for k in ring_kg:
			if k > 0.0:
				live += 1
		# CM RCS provides rotation only (no translation jets), two jets per
		# axis direction per ring.
		torque = Vector3(rot.x * arm_r, rot.y * arm_p, rot.z * arm_p) * f * 2.0 * live
		jets = (absf(rot.x) + absf(rot.y) + absf(rot.z)) * 2.0 * live
		var mdot := jets * f / (float(cmd["isp_s"]) * Units.G0)
		if live > 0:
			for i in ring_kg.size():
				if ring_kg[i] > 0.0:
					ring_kg[i] = maxf(0.0, ring_kg[i] - mdot * dt / live)
	else:
		var sm := SpacecraftData.section("sm_rcs")
		var f := float(sm["jet_thrust_n"])
		var on := {}
		for i in QUADS.size():
			on[QUADS[i]] = 1.0 if live(i) else 0.0
		var duty := {"a": 0.0, "b": 0.0, "c": 0.0, "d": 0.0}
		# Roll: all quads, one jet each.
		for q in QUADS:
			torque.x += rot.x * f * arm_r * on[q]
			duty[q] += absf(rot.x) * on[q]
		# Pitch and Z translation: A and C.
		for q in ["a", "c"]:
			torque.y += rot.y * f * arm_p * on[q]
			force.z += trans.z * f * on[q]
			duty[q] += (absf(rot.y) + absf(trans.z)) * on[q]
		# Yaw and Y translation: B and D.
		for q in ["b", "d"]:
			torque.z += rot.z * f * arm_p * on[q]
			force.y += trans.y * f * on[q]
			duty[q] += (absf(rot.z) + absf(trans.y)) * on[q]
		# X translation (ullage and trim): all four.
		for q in QUADS:
			force.x += trans.x * f * on[q]
			duty[q] += absf(trans.x) * on[q]
		var mdot_per := f / (float(sm["isp_s"]) * Units.G0)
		for i in QUADS.size():
			var d: float = duty[QUADS[i]]
			jets += d
			quad_kg[i] = maxf(0.0, quad_kg[i] - d * mdot_per * dt)
	_publish(force, torque, int(round(jets)))


## Quad [param i] feeds its jets: switched on, with propellant, and not
## failed.
func live(i: int) -> bool:
	return bool(Bus.get_value("ctl.rcs.quad_" + QUADS[i], true)) and quad_kg[i] > 0.0 and not failed[i]


## The failure catalog's [param part] fails: "quad_a" to "quad_d".
func fail(part: String) -> void:
	var i := QUADS.find(part.trim_prefix("quad_"))
	if i >= 0:
		failed[i] = true
		_publish(Vector3.ZERO, Vector3.ZERO, 0)


func _publish(force: Vector3, torque: Vector3, jets: int) -> void:
	Bus.set_value("rcs.force_body", force)
	Bus.set_value("rcs.torque_body", torque)
	Bus.set_value("rcs.active_jets", jets)
	var total := 0.0
	for i in QUADS.size():
		Bus.set_value("rcs.quad_%s_kg" % QUADS[i], quad_kg[i])
		Bus.set_value("rcs.quad_%s_psia" % QUADS[i], 0.0 if failed[i] else FUEL_PSIA)
		Bus.set_value("rcs.quad_%s_live" % QUADS[i], live(i))
		total += quad_kg[i]
	Bus.set_value("rcs.sm_prop_kg", total)
	Bus.set_value("rcs.cm_prop_kg", ring_kg[0] + ring_kg[1])


func snapshot() -> Dictionary:
	return {"quads": quad_kg.duplicate(), "rings": ring_kg.duplicate(), "failed": failed.duplicate()}


func restore(d: Dictionary) -> void:
	for i in 4:
		quad_kg[i] = float(d["quads"][i])
	for i in 2:
		ring_kg[i] = float(d["rings"][i])
	var f: Array = d.get("failed", [false, false, false, false])
	for i in 4:
		failed[i] = bool(f[i])
	_publish(Vector3.ZERO, Vector3.ZERO, 0)

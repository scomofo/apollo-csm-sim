## The LM's Abort Guidance Section, as far as Apollo 13 flew with it: an
## attitude reference and an attitude hold, backing up the PGNS
## [simplified: none of its guidance (insertion, rendezvous, burn
## steering), and its DEDA's addresses are two switches].
##
## It runs while the LM's buses are powered and its breakers are in
## (ctl.lm.ags). Its attitude reference is its own, strapped down to the
## LM [simplified: its gyros ideal]: a body-axis align (ctl.lm.ags_align,
## the DEDA's 400+5, then 400+0) takes the LM's attitude then as its zero,
## and the error needles show the LM's attitude from it
## (lm.ags.att_error_deg). With the guidance control switch at AGS
## (ctl.lm.guid_cont 1) it flies the LM, or the docked stack, on the LM's
## jets: in HOLD or AUTO (ctl.lm.mode) it holds the attitude it had when the
## ACA was last released, the ACA commanding rate, and in FREE the ACA
## fires the jets itself [simplified: one mode control for both guidance
## systems; the flight's burns held yaw on the AGS, pitch and roll by hand,
## all three held here]. Its accelerometers count the ΔV along the LM's X
## axis since the last body-axis align (lm.ags.dv_x_mps: the DEDA's
## address 470, which Apollo 13's crew watched to stop their manual burns)
## [simplified: its accelerometers ideal].
##
## Reads:  ctl.lm.ags, ctl.lm.ags_align (momentary), ctl.lm.guid_cont,
##         ctl.lm.mode, ctl.lm.rhc, lm.sys.powered, lm.dyn.att_q,
##         lm.dyn.omega, lm.dyn.dv_step (and what Lgc.jet_authority()
##         reads)
## Writes: lm.ags.on, lm.ags.rcs_rot_cmd, lm.ags.dap_busy,
##         lm.ags.att_error_deg, lm.ags.dv_x_mps
extends Node

## The ACA's full-scale rate, rad/s (the LGC's own).
const RATE_HOLD := AgcCore.RATE_HOLD
const DEADBAND := AgcCore.ATT_DEADBAND
const REST_RATE := AgcCore.REST_RATE

## The body-axis alignment's attitude (body to ECI): the needles' zero.
var reference_q: Quaternion = Quaternion.IDENTITY
## The attitude the hold keeps.
var hold_q: Quaternion = Quaternion.IDENTITY
## The ΔV along the LM's X axis since the last body-axis align, m/s.
var dv_x: float = 0.0
var _on: bool = false
var _align_was: bool = false
var _rhc_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.POWER_GUIDANCE)
	_publish(Vector3.ZERO, false, Vector3.ZERO)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func _att() -> Quaternion:
	return Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY)


func tick(_dt: float) -> void:
	var on := bool(Bus.get_value("lm.sys.powered", false)) and bool(Bus.get_value("ctl.lm.ags", false))
	var q := _att()
	if on and not _on:
		# Its reference comes up where the LM is.
		reference_q = q
		hold_q = q
		dv_x = 0.0
	_on = on
	if not on:
		_publish(Vector3.ZERO, false, Vector3.ZERO)
		return
	var align := bool(Bus.get_value("ctl.lm.ags_align", false))
	if align and not _align_was:
		reference_q = q
		hold_q = q
		dv_x = 0.0
	_align_was = align
	var step: Array = Bus.get_value("lm.dyn.dv_step", [0.0, 0.0, 0.0])
	dv_x += (q.inverse() * Vector3(step[0], step[1], step[2])).x
	var needles := _error(q, reference_q) * (180.0 / PI)
	if int(Bus.get_value("ctl.lm.guid_cont", 0)) != 1:
		# The PGNS flies: the hold follows the LM.
		hold_q = q
		_publish(Vector3.ZERO, false, needles)
		return
	var hc: Vector3 = Bus.get_value("ctl.lm.rhc", Vector3.ZERO)
	var w: Vector3 = Bus.get_value("lm.dyn.omega", Vector3.ZERO)
	var alpha := Lgc.jet_authority()
	var active := hc.length() > 0.05
	var cmd := Vector3.ZERO
	if int(Bus.get_value("ctl.lm.mode", 1)) == 0:
		cmd = hc
		hold_q = q
	elif active:
		cmd = AgcCore._rate_cmd(hc * RATE_HOLD - w, alpha, 0.6)
		hold_q = q
	else:
		if _rhc_was:
			hold_q = q
		var e := _error(q, hold_q)
		var w_des := Vector3.ZERO
		for i in 3:
			var brake := sqrt(alpha[i] * absf(e[i]))
			w_des[i] = signf(e[i]) * minf(minf(absf(e[i]) * 0.4, brake), RATE_HOLD)
		if e.length() < DEADBAND * 0.1 and w.length() < 5e-5:
			w_des = Vector3.ZERO if w.length() > REST_RATE else w
		cmd = AgcCore._rate_cmd(w_des - w, alpha, 0.6)
	_rhc_was = active
	var busy := active or cmd.length() > 1e-4 or _error(q, hold_q).length() > DEADBAND * 0.2
	_publish(cmd, busy, needles)


## The body-frame rotation vector (rad) from attitude [param q] to
## [param target].
static func _error(q: Quaternion, target: Quaternion) -> Vector3:
	var e := (q.inverse() * target).normalized()
	if e.w < 0.0:
		e = -e
	var s := Vector3(e.x, e.y, e.z)
	var sn := s.length()
	if sn < 1e-9:
		return Vector3.ZERO
	return s / sn * 2.0 * atan2(sn, e.w)


func _publish(cmd: Vector3, busy: bool, needles: Vector3) -> void:
	Bus.set_value("lm.ags.on", _on)
	Bus.set_value("lm.ags.rcs_rot_cmd", cmd)
	Bus.set_value("lm.ags.dap_busy", busy)
	Bus.set_value("lm.ags.att_error_deg", needles)
	Bus.set_value("lm.ags.dv_x_mps", dv_x)


func snapshot() -> Dictionary:
	return {"reference": [reference_q.x, reference_q.y, reference_q.z, reference_q.w],
		"hold": [hold_q.x, hold_q.y, hold_q.z, hold_q.w], "on": _on, "align_was": _align_was, "rhc_was": _rhc_was,
		"dv_x": dv_x}


func restore(d: Dictionary) -> void:
	var r: Array = d.get("reference", [0.0, 0.0, 0.0, 1.0])
	reference_q = Quaternion(r[0], r[1], r[2], r[3])
	var h: Array = d.get("hold", [0.0, 0.0, 0.0, 1.0])
	hold_q = Quaternion(h[0], h[1], h[2], h[3])
	_on = bool(d.get("on", false))
	_align_was = bool(d.get("align_was", false))
	_rhc_was = bool(d.get("rhc_was", false))
	dv_x = float(d.get("dv_x", 0.0))
	_publish(Vector3.ZERO, false, Vector3.ZERO)

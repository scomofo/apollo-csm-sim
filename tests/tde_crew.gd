## Apollo 14's transposition and docking, for the tests (slice 12a): Kitty
## Hawk's crew separate from the S-IVB, pitch about to face Antares's
## drogue and close on it, attempt after attempt with the capture latches
## failed; and at the last, by Houston's procedure, hold +X with the probe
## in the drogue and retract it [published: MSC-04112, Table 14-I and
## p. 9-3; Apollo Flight Journal, 003:02:58 to 004:57:09]. SimTest's
## csm_* helpers and face_x() fly the CSM: [param st] is the test (a
## SimTest, untyped here, as RendezvousCrew's are).
class_name TdeCrew
extends RefCounted

## Houston's call for the probe's retraction.
const RETRACT_CALL := "retract the probe"
## From the sixth attempt's contact to its retraction, s.
const RETRACT_AFTER_S := 6.9
## The CSM's +X from the S-IVB after CSM/LV SEP, m/s [estimated: about
## 4 s on four jets].
const SEP_DV := 0.25
## Where the CSM waits between attempts, the drogue this far ahead on the
## probe's axis, m [estimated].
const STANDOFF_M := 10.0


## The drogue's axis out of its port, inertial: the target's +X.
static func drogue_axis(st: Variant) -> Vector3:
	return Basis(st.rt.dynamics.lm.attitude.q).x


## CSM/LV SEP at GET [param at] and the transposition: +X away from the
## S-IVB, a pitch up through 180 deg to face the drogue, and a stop
## STANDOFF_M out on its axis.
static func separate(st: Variant, at: float) -> void:
	st.run(at - SimClock.get_seconds)
	Bus.set_value("ctl.seq.csm_sep", true)
	st.run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.csm_sep", false)
	st.csm_translate(Vector3(SEP_DV, 0.0, 0.0))
	# Nose up first: the turn's end is straight behind.
	var up: Vector3 = -Basis(st.rt.dynamics.attitude.q).z
	st.face_x(false, func() -> Vector3: return up)
	st.face_x(false, func() -> Vector3: return -drogue_axis(st))
	st.csm_move_to(Vector3(STANDOFF_M, 0.0, 0.0), 60.0)


## An attempt: from STANDOFF_M out, close at [param speed] (m/s) to meet
## the drogue at about GET [param at] (at once if that's too soon), and
## hold +X [param hold_s] from the contact on, PROBE RETRACT pressed
## RETRACT_AFTER_S after it with [param retract]. Without a hard dock the
## CSM backs off to STANDOFF_M. Returns the contact (Docking.contact(),
## with Dynamics' get_s), and "docked_get" the hard dock's GET, or -1.
static func attempt(st: Variant, speed: float, at: float, hold_s: float = 0.0, retract: bool = false) -> Dictionary:
	var start := at - STANDOFF_M / speed
	st.run(maxf(start - 120.0 - SimClock.get_seconds, 0.0))
	st.csm_move_to(Vector3(STANDOFF_M, 0.0, 0.0), 30.0)
	st.run(maxf(start - SimClock.get_seconds, 0.0))
	var dyn: Dynamics = st.rt.dynamics
	var out := {"docked_get": -1.0}
	if not approach(st, speed, 3.0 * STANDOFF_M / speed):
		return out
	out.merge(st.dock_contact())
	var t0 := float(out.get("get_s", SimClock.get_seconds))
	var pushed := false
	Bus.set_value("ctl.thc", Vector3(1.0, 0.0, 0.0) if hold_s > 0.0 else Vector3.ZERO)
	while dyn.tde_in_progress() and SimClock.get_seconds < t0 + maxf(hold_s, RETRACT_AFTER_S if retract else 0.0):
		if retract and not pushed and SimClock.get_seconds >= t0 + RETRACT_AFTER_S - 1e-6:
			Bus.set_value("ctl.seq.probe_retract", true)
			st.run(SimClock.FIXED_DT, false)
			Bus.set_value("ctl.seq.probe_retract", false)
			pushed = true
		st.run(0.1, false)
	# The ring latches: retract_s on, the probe held in the drogue.
	if retract:
		st.run_until(func() -> bool: return not dyn.tde_in_progress(), 10.0, 0.1, false)
	Bus.set_value("ctl.thc", Vector3.ZERO)
	st.run(SimClock.FIXED_DT, false)
	if not dyn.tde_in_progress():
		out["docked_get"] = st.rt.sequencer.event_get("transposition_docking")
		return out
	st.csm_null_rates()
	st.csm_move_to(Vector3(STANDOFF_M, 0.0, 0.0), 30.0)
	return out


## Close on the drogue at [param speed] (m/s), as SimTest.csm_approach()
## does, trimming the closing speed and steering the drogue onto the
## probe's axis every second; the last metre a step at a time, so the +X
## that holds the probe in comes at the contact. Returns once the probe
## has met the drogue.
static func approach(st: Variant, speed: float, max_s: float) -> bool:
	Bus.set_value("dock.contact", {})
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		var p: Vector3 = st.dock_rel_pos()
		var want := Vector3(-speed, -p.y / 5.0, -p.z / 5.0).clamp(-Vector3.ONE * speed, Vector3.ONE * speed)
		st.csm_translate(st.dock_rel_vel() - want)
		if p.x > 1.0 + speed:
			st.run(1.0)
			continue
		for i in 50:
			st.run(SimClock.FIXED_DT, false)
			if not st.dock_contact().is_empty():
				return true
	return false

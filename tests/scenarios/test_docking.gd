## Slice 3a (docs/ROADMAP.md, milestone 3): the CSM and the LM as two
## vehicles. The LM undocks in lunar orbit; the CSM holds station behind it
## and flies an equiperiod separation, a burn down across its velocity
## (radial, on a round orbit) that changes the shape of its orbit but not
## the period, so the vehicles meet again a revolution later; a checkpoint
## taken mid-revolution flies on as the uninterrupted run did; and the CSM
## docks again, flown on the translation controller. Contacts outside the
## capture limits rebound. Slice 12a: where the mission flies transposition
## and docking, the crew's CSM/LV SEP leaves the LM on the S-IVB; with the
## capture latches failed, the probe held in the drogue under +X and
## retracted docks the vehicles.
extends SimTest


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


func _undock() -> void:
	Bus.set_value("ctl.seq.undock", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.undock", false)


func _retract() -> void:
	Bus.set_value("ctl.seq.probe_retract", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.probe_retract", false)


# --- the LM's local frame ---------------------------------------------------------

## The LM's local vertical frame, inertial axes: up, along (the way it
## flies) and normal to its orbit, and the rate the frame turns at
## (rad/s, as a vector).
func _frame() -> Dictionary:
	var r := rt.dynamics.lm.traj.pos()
	var v := rt.dynamics.lm.traj.vel()
	var h := r.cross(v)
	var up := r.normalized()
	var normal := h.normalized()
	return {"up": up, "along": normal.cross(up), "normal": normal, "w": h / r.length_squared()}


func _in(f: Dictionary, x: Vector3) -> Vector3:
	return Vector3(x.dot(f["up"]), x.dot(f["along"]), x.dot(f["normal"]))


func _out(f: Dictionary, x: Vector3) -> Vector3:
	return f["up"] * x.x + f["along"] * x.y + f["normal"] * x.z


## Where the CSM's centre of mass is from the LM's, and how it moves as
## seen in the LM's turning local frame: [up/along/normal m, m/s].
func _local() -> Array:
	var rel := Docking.relative_state(rt.dynamics.lm.traj, rt.dynamics.traj)
	var p := _vec(rel, 0)
	var f := _frame()
	var w: Vector3 = f["w"]
	return [_in(f, p), _in(f, _vec(rel, 3) - w.cross(p))]


## Fly the CSM to [param station] (m, the LM's local frame) in about
## [param seconds] and hold it there: still in the local frame, so the
## two vehicles fly the same orbit and don't drift apart.
func _station(station: Vector3, seconds: float) -> void:
	for i in 3:
		var l := _local()
		csm_translate(rt.dynamics.attitude.body_from_eci() * _out(_frame(), (station - l[0]) / seconds - l[1]))
		run(seconds - 2.0)
	for i in 2:
		var l := _local()
		csm_translate(rt.dynamics.attitude.body_from_eci() * _out(_frame(), -l[1]))


## Burn [param dv] m/s down across the CSM's velocity, in the orbit's
## plane, the thrust kept there as it turns (the CSM's attitude holds still
## meanwhile): the orbit's energy, and so its period, stay as they were.
## On a round orbit it is the local vertical; on the flown one, out of
## round, the vertical is off it by the flight path angle, and a burn on
## the vertical would change the period.
func _radial_burn(dv: float) -> void:
	var cap := csm_step_dv()
	var rate := minf(cap.y, cap.z) * 0.8
	var owed := Vector3.ZERO
	var given := 0.0
	for i in 20000:
		if given < dv:
			var r := rt.dynamics.traj.pos()
			var v := rt.dynamics.traj.vel()
			var down := -(r - v * (r.dot(v) / v.length_squared())).normalized()
			var inc := minf(rate, dv - given)
			owed += rt.dynamics.attitude.body_from_eci() * down * inc
			given += inc
		elif absf(owed.x) < cap.x * CSM_THC_DETENT and absf(owed.y) < cap.y * CSM_THC_DETENT and absf(owed.z) < cap.z * CSM_THC_DETENT:
			break
		owed = csm_translate_step(owed)
	Bus.set_value("ctl.thc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)


func _vec(s: PackedFloat64Array, from: int) -> Vector3:
	return Vector3(s[from], s[from + 1], s[from + 2])


# --- tests ---------------------------------------------------------------------

func test_undocking_splits_the_stack_and_conserves_its_momentum() -> void:
	build("lunar_orbit")
	var d := rt.dynamics
	d.attitude.omega = Vector3(0.0, 0.002, 0.0)   # the stack pitching slowly
	d.update_mass()
	var m := d.mass
	var s := d.traj.s.duplicate()
	var x := d.attitude.eci_from_body() * Vector3.RIGHT
	assert_true(d.undock(), "undocked")
	assert_false(d.undock(), "once")
	assert_eq(d.config, "csm")
	assert_eq(d.lm.config, "lm")
	var mc := d.mass
	var ml := d.lm.mass
	assert_almost_eq(ml, 15103.0, 1e-6, "the LM's mass")
	assert_almost_eq(mc + ml, m, 1e-6, "the two masses make the stack's")
	for i in 6:
		var joint := (mc * d.traj.s[i] + ml * d.lm.traj.s[i]) / m
		assert_almost_eq(joint, s[i], 1e-5 if i < 3 else 1e-7, "centre of mass and momentum, component %d" % i)
	var g := Docking.relative(d.traj, d.attitude, d.lm)
	assert_lt(float(g["range"]), 1e-4, "the ports start together")
	assert_almost_eq(float(g["misalign_deg"]), 0.0, 1e-3, "the LM faces the probe")
	assert_almost_eq(float(g["u"].dot(x)), 0.03, 1e-6, "the probe pushes them apart at 0.03 m/s")
	assert_eq(d.lm.attitude.omega, Vector3.ZERO, "the LM holds its attitude")
	assert_eq(d.attitude.omega, Vector3(0.0, 0.002, 0.0), "the CSM keeps turning with the stack's rate")
	assert_eq(str(Bus.get_value("dock.state")), "free")
	assert_eq(str(Bus.get_value("lm.dyn.config")), "lm")
	assert_almost_eq(float(Bus.get_value("lm.dyn.mass_kg")), 15103.0, 1e-6)


func test_the_undock_button_works_only_with_the_lm_docked() -> void:
	build("parking_orbit")
	_undock()
	assert_eq(rt.dynamics.config, "stack", "no LM to undock in the stack")
	assert_null(rt.dynamics.lm)
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(SimClock.FIXED_DT, false)
	_undock()
	assert_eq(rt.dynamics.config, "csm", "nor after LM JETT")
	assert_null(rt.dynamics.lm)
	assert_eq(str(Bus.get_value("dock.state")), "none")
	build("lunar_orbit")
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	_undock()
	assert_not_null(rt.dynamics.lm, "docked, it undocks")
	assert_true(Bus.has_channel("mission.event.undocking"))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "undocking")


func test_equiperiod_separation_a_revolution_and_docking_again() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	var stack_mass := rt.dynamics.mass
	_undock()
	# Stationkeep 20 m behind the LM, on its orbit.
	_station(Vector3(0.0, -20.0, 0.0), 60.0)
	var l: Array = _local()
	assert_lt((l[0] - Vector3(0.0, -20.0, 0.0)).length(), 0.2, "20 m behind the LM")
	assert_lt(l[1].length(), 0.0005, "holding station")
	# The equiperiod separation: 0.6 m/s radially down.
	_radial_burn(0.6)
	var t_sep := SimClock.get_seconds
	var at_sep: Vector3 = _local()[0]
	var period := float(rt.dynamics.lm.traj.conic()["period"])
	var n := TAU / period
	# Half a revolution on, the CSM is level with the LM and 4 dv/n farther
	# ahead, as the linear (Clohessy-Wiltshire) solution has it for a round
	# orbit: on the flown one, out of round by 0.006, to within a few times
	# that share of the motion's 1.4 km.
	var steps0 := SimClock.step_count
	run(t_sep + period / 2.0 - SimClock.get_seconds)
	# The LM's DAP trims the attitude its drifting platform moves (slice
	# 11a) now and then, on fine steps.
	assert_lt(SimClock.step_count - steps0, 2000, "both vehicles coast on long steps")
	var half: Vector3 = _local()[0]
	gut.p("Half a revolution after the separation, the CSM is %.0f m ahead of the LM and %.1f m above it" % [half.y, half.x])
	assert_almost_eq(half.y - at_sep.y, 4.0 * 0.6 / n, 0.01 * 4.0 * 0.6 / n, "4 dv/n farther ahead")
	assert_almost_eq(half.x, 0.0, 25.0, "level")
	assert_almost_eq(float(Bus.get_value("dock.range_m")), half.length(), 15.0, "the docking ports as far apart")
	# A checkpoint here flies on as the uninterrupted run does.
	var text := JSON.stringify(rt.snapshot())
	run(t_sep + period - SimClock.get_seconds)
	var t_end := SimClock.get_seconds
	var csm_end := rt.dynamics.traj.s.duplicate()
	var lm_end := rt.dynamics.lm.traj.s.duplicate()
	var back: Vector3 = _local()[0]
	gut.p("A revolution after the separation, the CSM is at %s m from the LM (%s after the burn)" % [back, at_sep])
	assert_lt((back - at_sep).length(), 5.0, "back where it was a revolution ago")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_not_null(rt.dynamics.lm, "the checkpoint has the LM flying free")
	assert_eq(str(Bus.get_value("dock.state")), "free")
	run(t_end - SimClock.get_seconds)
	# The restored run's steps fall differently: it can end a fraction of
	# a step off the uninterrupted run's time.
	var lag := t_end - SimClock.get_seconds
	assert_almost_eq(lag, 0.0, SimClock.FIXED_DT, "the same time, to within a step")
	var csm_now := _vec(rt.dynamics.traj.s, 0) + _vec(rt.dynamics.traj.s, 3) * lag
	var lm_now := _vec(rt.dynamics.lm.traj.s, 0) + _vec(rt.dynamics.lm.traj.s, 3) * lag
	assert_lt((csm_now - _vec(csm_end, 0)).length(), 1.0, "the CSM flies on as it did")
	assert_lt((lm_now - _vec(lm_end, 0)).length(), 1.0, "and so does the LM")
	assert_lt((_local()[0] - back).length(), 0.05, "to within 5 cm of each other")
	# Dock again: line up 10 m out, and close at 0.1 m/s.
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	var c := dock_contact()
	gut.p("Docked: %s" % Docking.describe(c))
	assert_true(c["captured"], "within the capture limits")
	assert_almost_eq(float(c["closing_mps"]), 0.1, 0.005, "closing at 0.1 m/s")
	assert_lt(float(c["miss_m"]), 0.05, "on the drogue's centre")
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	assert_eq(rt.dynamics.config, "csm_lm")
	assert_null(rt.dynamics.lm)
	assert_almost_eq(rt.dynamics.mass, stack_mass, 30.0, "the stack again, less the RCS propellant used")
	assert_lt(rt.dynamics.attitude.omega.length(), deg_to_rad(0.05), "no tumble from the capture")
	assert_true(Bus.has_channel("mission.event.docking"))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "hard dock")


func test_undocking_is_not_the_lm_jettison_on_the_checklist() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	var book := ChecklistBook.load_default()
	book.select_for_phase("lunar_orbit")
	var list := book.list()
	while not list.done() and not str(list.current().get("text", "")).begins_with("LM JETT"):
		list.update()
		list.next()
	assert_string_starts_with(str(list.current().get("text", "")), "LM JETT", "on the LM JETT step")
	_undock()
	list.update()
	assert_string_starts_with(str(list.current().get("text", "")), "LM JETT", "undocked, the LM hasn't gone")
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	assert_eq(str(Bus.get_value("dock.state")), "docked", "docked again")
	list.update()
	assert_string_starts_with(str(list.current().get("text", "")), "LM JETT", "still to jettison")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(SimClock.FIXED_DT, false)
	list.update()
	assert_string_starts_with(str(list.current().get("text", "")), "Request TEI PAD", "LM JETT done")


func test_capture_joins_the_vehicles_momentum_conserved() -> void:
	build("lunar_orbit")
	var d := rt.dynamics
	d.undock()
	d.lm.traj.s[3] += 0.05
	d.lm.attitude.omega = Vector3(0.0, 0.0, 0.001)
	var mc := d.mass
	var ml := d.lm.mass
	var joint := PackedFloat64Array()
	for i in 6:
		joint.append((mc * d.traj.s[i] + ml * d.lm.traj.s[i]) / (mc + ml))
	d.call("_capture")
	assert_eq(d.config, "csm_lm")
	assert_null(d.lm)
	for i in 6:
		assert_almost_eq(d.traj.s[i], joint[i], 1e-5 if i < 3 else 1e-7, "centre of mass and momentum, component %d" % i)
	assert_gt(absf(d.attitude.omega.z), 0.0, "the LM's yaw rate goes into the stack's")


func test_contacts_outside_the_capture_limits_rebound() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	_undock()
	csm_move_to(Vector3(8.0, 0.0, 0.0), 40.0)
	# Too fast: 0.5 m/s.
	assert_true(csm_approach(0.5), "the probe met the drogue")
	var c := dock_contact()
	assert_false(c["captured"])
	assert_eq(c["fault"], "closing")
	assert_almost_eq(float(c["closing_mps"]), 0.5, 0.005)
	assert_eq(Docking.describe(c), "no capture: closing at 1.64 ft/s")
	assert_eq(str(Bus.get_value("dock.state")), "free")
	run(1.0, false)
	assert_almost_eq(float(Bus.get_value("dock.range_rate_mps")), 0.25, 0.01, "rebounding at half the closing speed")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "contact, no capture: closing at 1.64 ft/s")
	# Misaligned by 20°, at a gentle 0.1 m/s.
	csm_null_rates()
	var d := rt.dynamics
	d.attitude.q = (d.attitude.q * Quaternion(Vector3(0, 0, 1), deg_to_rad(20.0))).normalized()
	run(SimClock.FIXED_DT, false)
	csm_move_to(Vector3(8.0, 0.0, 0.0), 40.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	c = dock_contact()
	assert_eq(c["fault"], "misaligned")
	assert_almost_eq(float(c["misalign_deg"]), 20.0, 0.1)
	assert_eq(Docking.describe(c), "no capture: 20° out of line")
	assert_eq(str(Bus.get_value("dock.state")), "free")


func test_the_crews_sep_leaves_the_lm_on_the_s_ivb_where_the_mission_flies_it() -> void:
	# Apollo 11's: transposition, docking and extraction at once.
	build("parking_orbit")
	rt.sequencer.call("_separate", true)
	run(SimClock.FIXED_DT, false)
	assert_eq([str(Bus.get_value("dock.state")), rt.dynamics.config], ["docked", "csm_lm"])
	# Apollo 14's: Kitty Hawk free, Antares on the S-IVB, the stack's centre
	# of mass and momentum kept.
	build("parking_orbit", "apollo_14")
	var d := rt.dynamics
	var sq := rt.sequencer
	Bus.set_value("sivb.prop_kg", 0.0)
	rt.systems["sivb"].prop_kg = 0.0
	d.update_mass()
	var m := d.mass
	var s0 := d.traj.s.duplicate()
	var x := d.attitude.eci_from_body() * Vector3.RIGHT
	sq.call("_separate", true)
	assert_eq([str(Bus.get_value("dock.state")), d.config, d.lm.config], ["tde", "csm", "lm_sivb"])
	assert_true(d.tde_in_progress())
	assert_almost_eq(d.mass + d.lm.mass, m, 1.0, "the stack's mass, split")
	for i in 6:
		var joint := (d.mass * d.traj.s[i] + d.lm.mass * d.lm.traj.s[i]) / m
		assert_almost_eq(joint, s0[i], 1e-4 if i < 3 else 1e-7, "centre of mass and momentum, component %d" % i)
	var apart := Vector3(d.traj.s[0] - d.lm.traj.s[0], d.traj.s[1] - d.lm.traj.s[1], d.traj.s[2] - d.lm.traj.s[2])
	assert_almost_eq(apart.dot(x), float(Docking.params()["tde_span_m"]), 1e-3, "the CSM ahead along the stack's +X")
	assert_almost_eq(float(Bus.get_value("dock.range_m")), apart.dot(x) + float(Docking.params()["csm_port_m"])
		- Docking.lm_port_m("lm_sivb"), 1e-3, "the probe on the CSM's nose, the drogue under its SM")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "turn around and dock with Antares")
	run(SimClock.FIXED_DT, false)
	assert_false(bool(Bus.get_value("lm.sys.powered")), "Antares unpowered in the adapter")
	# The ground's time for the extraction, the crew not docked: taken as done.
	sq.tli_cutoff_get = SimClock.get_seconds
	sq.call("_advance", SimClock.get_seconds + float(sq.mission.data["tde_delay_s"]) - 1.0)
	assert_eq(str(Bus.get_value("dock.state")), "tde", "not yet")
	run(3.0)
	assert_eq([str(Bus.get_value("dock.state")), d.config, d.lm], ["docked", "csm_lm", null])
	assert_gt(sq.event_get("transposition_docking"), 0.0)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "hard dock and LM extraction")


func test_with_the_capture_latches_failed_the_probe_held_in_and_retracted_docks() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	_undock()
	assert_true(rt.failures.fail("csm_capture_latches"))
	assert_true(bool(Bus.get_value("dock.probe.latches_failed")))
	csm_move_to(Vector3(8.0, 0.0, 0.0), 40.0)
	# PROBE RETRACT with the probe out of the drogue does nothing.
	_retract()
	assert_false(bool(Bus.get_value("dock.retracting")))
	assert_true(TdeCrew.approach(self, 0.1, 200.0), "the probe met the drogue")
	var c := dock_contact()
	assert_eq([c["captured"], c["fault"]], [false, "latches"])
	assert_eq(Docking.describe(c), "no capture: the capture latches didn't engage, at 0.33 ft/s")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "the capture latches didn't engage")
	# Held in the drogue under +X: no capture, the contacts one attempt.
	Bus.set_value("ctl.thc", Vector3(1.0, 0.0, 0.0))
	run(2.0, false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "held in, not captured")
	assert_eq(dock_contact(), c, "one attempt")
	# Retracted, then the probe let out before the ring latches: nothing.
	_retract()
	assert_true(bool(Bus.get_value("dock.retracting")))
	Bus.set_value("ctl.thc", Vector3.ZERO)
	csm_translate(Vector3(-0.1, 0.0, 0.0))
	run(3.0, false)
	assert_false(bool(Bus.get_value("dock.retracting")), "the probe out of the drogue")
	run(5.0, false)
	assert_eq(str(Bus.get_value("dock.state")), "free")
	# Again, held in until the ring latches fire.
	csm_null_rates()
	csm_move_to(Vector3(4.0, 0.0, 0.0), 20.0)
	assert_true(TdeCrew.approach(self, 0.1, 200.0), "the probe met the drogue again")
	Bus.set_value("ctl.thc", Vector3(1.0, 0.0, 0.0))
	run(2.0, false)
	_retract()
	var t := SimClock.get_seconds
	assert_true(run_until(func() -> bool: return str(Bus.get_value("dock.state")) == "docked", 10.0, SimClock.FIXED_DT, false),
		"hard dock")
	assert_almost_eq(SimClock.get_seconds - t, float(Docking.params()["retract_s"]), 0.1, "the ring latches retract_s on")
	Bus.set_value("ctl.thc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_eq(rt.dynamics.config, "csm_lm")
	assert_eq(Docking.describe(dock_contact()), "hard dock: the probe retracted, the ring latches fired")
	assert_false(bool(Bus.get_value("dock.probe.latches_failed")), "the latches back as the hard dock clears them")
	assert_false(bool(Bus.get_value("dock.retracting")))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Houston copies hard dock")

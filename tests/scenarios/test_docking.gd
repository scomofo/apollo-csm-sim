## Slice 3a (docs/ROADMAP.md, milestone 3): the CSM and the LM as two
## vehicles. The LM undocks in lunar orbit; the CSM holds station behind it
## and flies an equiperiod separation, a radial burn that changes the shape
## of its orbit but not the period, so the vehicles meet again a revolution
## later; a checkpoint taken mid-revolution flies on as the uninterrupted
## run did; and the CSM docks again, flown on the translation controller.
## Contacts outside the capture limits rebound.
extends SimTest


func _undock() -> void:
	Bus.set_value("ctl.seq.undock", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.seq.undock", false)


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


## Burn [param dv] m/s radially down, the thrust kept on the local
## vertical as it turns (the CSM's attitude holds still meanwhile).
func _radial_burn(dv: float) -> void:
	var cap := csm_step_dv()
	var rate := minf(cap.y, cap.z) * 0.8
	var owed := Vector3.ZERO
	var given := 0.0
	for i in 20000:
		if given < dv:
			var down := -rt.dynamics.traj.pos().normalized()
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
	# ahead, as the linear (Clohessy-Wiltshire) solution has it.
	var steps0 := SimClock.step_count
	run(t_sep + period / 2.0 - SimClock.get_seconds)
	assert_lt(SimClock.step_count - steps0, 1500, "both vehicles coast on long steps")
	var half: Vector3 = _local()[0]
	gut.p("Half a revolution after the separation, the CSM is %.0f m ahead of the LM and %.1f m above it" % [half.y, half.x])
	assert_almost_eq(half.y - at_sep.y, 4.0 * 0.6 / n, 0.01 * 4.0 * 0.6 / n, "4 dv/n farther ahead")
	assert_almost_eq(half.x, 0.0, 10.0, "level")
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

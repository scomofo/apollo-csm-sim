## Slice 4b's check (docs/ROADMAP.md, milestone 4): the CMC flies on its
## own state vector. In coast its Average-G is off, so the CSM's unmodelled
## forces (the SM's vents, its jets' imbalance) move the CSM off the state
## vector by a bounded amount; the ground's uplink, the state MSFN tracked,
## puts it back (P27, V71), taken in P00 with UP TLM CM in ACCEPT. A
## translation in P00 isn't in the state vector; in P47 it is.
extends SimTest


## The CMC's state vector less the truth: position (m) and velocity (m/s).
func _nav_error() -> Array:
	var nav := rt.agc().nav
	var tr := rt.dynamics.traj
	assert_almost_eq(nav.t, tr.t, 1e-6, "the state vector is kept at the time")
	return [nav.pos() - tr.pos(), nav.vel() - tr.vel()]


func test_the_cmc_drifts_in_coast_and_the_grounds_uplink_puts_it_back() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	var err := _nav_error()
	gut.p("At the start the CMC has the state MSFN tracked: %.0f m and %.3f m/s off" % [err[0].length(), err[1].length()])
	assert_between((err[0] as Vector3).length(), 1.0, 3500.0, "off by MSFN's tracking error at the start")
	assert_eq(agc.nav_uplink_get, -1.0, "set by the start, not uplinked")
	# From a perfect state, a day's coast in CMC MODE FREE: no jets fire, and
	# the vents alone move the CSM off it, as far as they move a copy of it.
	Bus.set_value("ctl.cmc.mode", 0)
	agc.init_nav(rt.dynamics.traj)
	var a := rt.dynamics.attitude.eci_from_body() * (rt.dynamics.vent_force / rt.dynamics.mass)
	var ref := rt.dynamics.traj.clone()
	var pushed := ref.clone()
	var end := ref.t + 86400.0
	while ref.t < end - 1e-9:
		var dt := minf(60.0, end - ref.t)
		ref.step(dt)
		pushed.step(dt, PackedFloat64Array([a.x, a.y, a.z]))
	run(86400.0)
	err = _nav_error()
	var expect := (pushed.pos() - ref.pos()).length()
	gut.p("After a day's coast the CMC is %.0f m and %.3f m/s off; the vents (%s m/s²) move a copy %.0f m" % [
		err[0].length(), err[1].length(), String.num_scientific(a.length()), expect])
	assert_between(expect, 100.0, 20000.0, "a drift worth an uplink, and bounded")
	assert_almost_eq((err[0] as Vector3).length(), expect, 0.05 * expect, "what the vents make")
	# The ground's uplink replaces it with the tracked state.
	var sv := rt.sequencer.request_pad("sv")
	assert_true(sv["uplinked"], "the CMC took the uplink")
	assert_almost_eq(agc.nav_uplink_get, SimClock.get_seconds, 1e-6, "at the time of the request")
	var st: Trajectory = sv["state"]
	for i in 6:
		assert_eq(agc.nav.s[i], st.s[i], "the state MSFN tracked, component %d" % i)
	assert_true(dsky_lamp("uplink_acty"), "UPLINK ACTY")
	assert_eq([Bus.get_value("dsky.prog"), Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun")], ["27", "71", ""],
		"P27 and the ground's V71 on the DSKY")
	run(3.0, false)
	assert_false(dsky_lamp("uplink_acty"), "the uplink is done")
	assert_eq([Bus.get_value("dsky.prog"), Bus.get_value("dsky.verb")], ["00", ""], "back to P00")
	err = _nav_error()
	gut.p("After the uplink the CMC is %.0f m and %.3f m/s off" % [err[0].length(), err[1].length()])
	assert_lt((err[0] as Vector3).length(), 3500.0, "off by MSFN's tracking error again")
	assert_lt((err[1] as Vector3).length(), 0.35, "and in velocity")


func dsky_lamp(lamp: String) -> bool:
	return bool(Bus.get_value("dsky.lamp." + lamp, false))


func test_the_cmc_takes_uplinks_in_p00_with_up_tlm_in_accept() -> void:
	build("translunar_coast")
	var agc := rt.agc()
	var before := agc.nav.s.duplicate()
	Bus.set_value("ctl.cmc.up_tlm", false)
	var sv := rt.sequencer.request_pad("sv")
	assert_false(sv["uplinked"], "UP TLM CM in BLOCK")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "UP TLM to ACCEPT")
	assert_eq(agc.nav_uplink_get, -1.0, "no uplink")
	# A PAD comes by voice: planned, but neither it nor the state vector loaded.
	var mcc := rt.sequencer.request_pad("mcc")
	if not mcc.is_empty():
		assert_false(mcc["uplinked"], "the MCC PAD by voice")
		assert_eq(agc.tig_load, 0.0, "nothing in P30's registers")
	Bus.set_value("ctl.cmc.up_tlm", true)
	keys("V37E30E")
	assert_false(rt.sequencer.request_pad("sv")["uplinked"], "in P30")
	keys("V37E00E")
	assert_eq(agc.program, 0)
	assert_true(rt.sequencer.request_pad("sv")["uplinked"], "in P00, with UP TLM CM in ACCEPT")
	assert_ne(agc.nav.s, before, "the state vector replaced")


func test_average_g_takes_a_translation_in_p47_but_not_in_p00() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.cmc.mode", 0)
	var agc := rt.agc()
	var dv := Vector3(0.5, 0.0, 0.0)
	# In P00 the accelerometers see it, the state vector doesn't.
	agc.init_nav(rt.dynamics.traj)
	csm_translate(dv)
	var err := _nav_error()
	gut.p("A 0.5 m/s translation in P00 leaves the CMC %.3f m/s off" % err[1].length())
	assert_almost_eq((err[1] as Vector3).length(), 0.5, 0.02, "the state vector missed it")
	# In P47 Average-G takes it in. The CMC's model of the Moon's field
	# isn't truth's: a copy of the state vector coasting beside a copy of
	# the truth parts from it as the CMC's does meanwhile.
	agc.init_nav(rt.dynamics.traj)
	var coast_nav := agc.nav.clone()
	var coast_truth := rt.dynamics.traj.clone()
	keys("V37E47E")
	assert_eq(agc.program, 47)
	csm_translate(dv)
	coast_nav.coast_to(rt.dynamics.traj.t, 1.0)
	coast_truth.coast_to(rt.dynamics.traj.t, 1.0)
	var drift := coast_nav.vel() - coast_truth.vel()
	err = _nav_error()
	gut.p("In P47 the CMC is %.4f m/s off, %.4f m/s of it its model's" % [err[1].length(), drift.length()])
	assert_lt((err[1] - drift).length(), 0.001, "the state vector took it in")
	assert_almost_eq(agc.dv_body.x, 0.5, 0.02, "N83 shows it")

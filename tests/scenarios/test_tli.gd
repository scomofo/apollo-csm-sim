extends SimTest


func test_saturn_iu_flies_tli_and_reaches_the_moon() -> void:
	build("parking_orbit")
	var seq := rt.sequencer
	assert_eq(seq.phase, "parking_orbit")
	assert_false(seq.tli_pad.is_empty(), "RTCC found a TLI opportunity")
	var tig := float(seq.tli_pad["tig"])
	assert_between(tig / 3600.0, 2.3, 3.2, "TLI near the flown 2:44 GET")
	assert_true(run_until(func() -> bool: return seq._has("tli_cutoff"), tig - SimClock.get_seconds + 600.0, 60.0))
	var ign: float = Bus.get_value("mission.event.tli_ignition")
	assert_almost_eq(ign, tig, 0.05, "ignition on the planned TIG")
	var burn := float(Bus.get_value("mission.event.tli_cutoff")) - ign
	assert_between(burn, 250.0, 350.0, "J-2 burn duration")
	assert_eq(seq.phase, "translunar_coast")
	assert_gt(float(Bus.get_value("dyn.apo_alt_m")), 3.0e8, "apogee beyond the Moon's orbit")
	# Crew separates, T&D.
	Bus.set_value("ctl.seq.csm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.csm_sep", false)
	assert_eq(rt.dynamics.config, "csm_lm")
	# Coast to the Moon and compare with the plan.
	var planned := float(seq.tli_pad["pericynthion_get"])
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, planned + 86400.0)
	gut.p("predicted pericynthion %.0f km at %s (plan %s)" % [(float(ap["rp"]) - Bodies.R_MOON) / 1000.0,
		Units.hms(float(ap["t"])), Units.hms(planned)])
	assert_true(ap["reached"])
	assert_lt(absf(float(ap["t"]) - planned), 1800.0, "arrival time within 30 min of plan")
	assert_lt(float(ap["rp"]) - Bodies.R_MOON, 3000000.0, "passes within 3000 km: MCC can trim it")
	assert_false(ap["impact"])


## Slice 5a's check: the Earth's oblateness turns the parking orbit's plane
## west at J2's rate for it, 0.32 deg an hour, which by Apollo 11's TLI,
## 2.54 h after insertion, comes to 0.8 deg.
func test_the_earths_oblateness_turns_the_parking_orbit_west() -> void:
	build("parking_orbit")
	var pad := rt.sequencer.tli_pad
	var tig := float(pad["tig"])
	var c0: Dictionary = rt.dynamics.traj.conic()
	var n0 := _node_deg(rt.dynamics.traj)
	var t0 := SimClock.get_seconds
	run(tig - 120.0 - t0)
	var hours := (SimClock.get_seconds - t0) / 3600.0
	var turned := wrapf(_node_deg(rt.dynamics.traj) - n0, -180.0, 180.0)
	var a: float = c0["a"]
	var n := sqrt(Bodies.MU_EARTH / (a * a * a))
	var rate := rad_to_deg(-1.5 * n * Bodies.EARTH_J2 * pow(Bodies.R_EARTH / a, 2.0) * cos(float(c0["i"]))) * 3600.0
	gut.p("the node turned %.3f deg in %.2f h (J2's rate %.3f deg/h: %.3f deg; by the flown TLI %.2f deg); TLI yaw %.2f deg, %.0f m/s" % [
		turned, hours, rate, rate * hours, rate * 2.541, rad_to_deg(float(pad["yaw"])), float(pad["dv"])])
	assert_almost_eq(turned, rate * hours, absf(rate * hours) * 0.05, "west at J2's rate")
	assert_almost_eq(rate * 2.541, -0.80, 0.02, "0.8 deg by Apollo 11's TLI")


## The right ascension of [param tr]'s ascending node, degrees.
static func _node_deg(tr: Trajectory) -> float:
	var h: Vector3 = tr.conic()["h"]
	return rad_to_deg(atan2(h.x, -h.y))

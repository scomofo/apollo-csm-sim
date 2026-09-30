## Slice 11c's check (docs/ROADMAP.md, milestone 11): Luminary's steering.
## The LGC's P40 to P42 steer as Luminary 099's did (S40.1, S40.8 and
## FINDCDUW): the velocity to be gained at TIG, turned through half the
## burn's arc on Luminary's own thrust constants, drawn down by the sensed
## ΔV, and the thrust held on it with the LM's roll left alone; the RTCC
## plans the LM's burns on the same law. DOI, whose 10 % start S40.1 leaves
## out, comes nearer its PAD's pericynthion on it than holding the ΔV's
## direction in the rotating LVLH frame does, as the simulator did before;
## a burn of an insertion's size on the ascent engine's steady thrust comes
## out as it did. KALCMANU turns the LM about a single axis at the 2 °/s
## Apollo 11's crew loaded, and a turn that would take the middle gimbal
## past 60° is routed clear of the lock zone, as the crews turned by hand.
extends SimTest


func _undock() -> void:
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)


## The LM's pericynthion above the landing site (x, m) and its GET (y),
## coasting on to where its altitude rate turns (test_doi.gd's).
func _pericynthion() -> Vector2:
	var box := {"prev": float(Bus.get_value("lm.dyn.alt_rate_mps")), "min": INF, "t": 0.0}
	var found := run_until(func() -> bool:
		var alt := float(Bus.get_value("lm.dyn.alt_m"))
		if alt < box["min"]:
			box["min"] = alt
			box["t"] = SimClock.get_seconds
		var rr := float(Bus.get_value("lm.dyn.alt_rate_mps"))
		var passed: bool = box["prev"] < 0.0 and rr >= 0.0
		box["prev"] = rr
		return passed, 7200.0, 10.0)
	assert_true(found, "passed the pericynthion")
	return Vector2(float(box["min"]) - (rt.sequencer.landing_site().length() - Bodies.R_MOON), float(box["t"]))


## The LM's apsides now, above the landing site's radius, km.
func _apsides() -> Vector2:
	var c := rt.dynamics.lm.traj.conic()
	var r := rt.sequencer.landing_site().length()
	return Vector2(float(c["rp"]) - r, float(c["ra"]) - r) / 1000.0


func test_doi_on_luminarys_steering_meets_its_pad() -> void:
	build("lunar_orbit")
	_undock()
	run(600.0)
	Bus.set_value("ctl.ground.pad_request", "doi")
	var pad: Dictionary = rt.sequencer.last_pad
	assert_eq(str(pad.get("name", "")), "DOI", "a DOI PAD")
	var before := rt.snapshot()
	var miss := {}
	for law in [true, false]:
		if not law:
			assert_eq(rt.restore(before), "")
		rt.lgc().cross_product_steering = law
		var dv := fly_lm_pad(40, 2)
		var hp := _pericynthion()
		miss[law] = hp.x - float(pad["hp"])
		gut.p("DOI on %s: %.2f ft/s; the pericynthion %.0f m above the site at %s (the PAD's %.0f m at %s)" % [
			"Luminary's steering" if law else "the LVLH direction held", dv / Units.FT, hp.x, Units.hms(hp.y),
			float(pad["hp"]), Units.hms(float(pad["hp_get"]))])
	assert_lt(absf(float(miss[true])), 10.0, "on its PAD's pericynthion, which the RTCC planned on the same law")
	assert_gt(absf(float(miss[false])), 2.0 * absf(float(miss[true])) + 5.0, "nearer it than the LVLH direction held")


func test_a_p42_on_the_ascent_engine_meets_its_plan() -> void:
	build("lunar_orbit")
	_undock()
	run(60.0)
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	var lgc := rt.lgc()
	var tig := SimClock.get_seconds + 900.0
	# The size of Apollo 10's insertion, 220.9 ft/s (MSC-00126, Table 6-IV),
	# posigrade and up here, where Snoopy's was from its phasing orbit.
	var dv := Vector3(55.8, 0.0, -37.6)
	lgc.uplink_maneuver(tig, dv)
	var before := rt.snapshot()
	var got := {}
	var plan := Vector2.ZERO
	for law in [true, false]:
		if not law:
			assert_eq(rt.restore(before), "")
		rt.lgc().cross_product_steering = law
		var flown := fly_lm_pad(42, 1)
		var t_after := SimClock.get_seconds
		got[law] = _apsides()
		if law:
			# The RTCC's model of it, from the LM's state at TIG.
			build("")
			assert_eq(rt.restore(before), "")
			var tr := rt.dynamics.lm.traj.clone()
			tr.coast_to(tig, 10.0)
			Rtcc.simulate_burn({"engine": "aps"}, tr, rt.dynamics.lm.mass, dv)
			tr.coast_to(t_after, 1.0)
			var c := tr.conic()
			var r := rt.sequencer.landing_site().length()
			plan = Vector2(float(c["rp"]) - r, float(c["ra"]) - r) / 1000.0
		gut.p("P42 on %s: %.2f ft/s; %.2f x %.2f km (the plan %.2f x %.2f)" % [
			"Luminary's steering" if law else "the LVLH direction held", flown / Units.FT, got[law].x, got[law].y,
			plan.x, plan.y])
	# The platform, off where the crew's docked alignment left it, turns
	# the thrust either way; the laws differ in the second order only on a
	# steady thrust.
	assert_lt(((got[true] as Vector2) - plan).length(), 1.0, "near the RTCC's plan")
	assert_lt(((got[true] as Vector2) - (got[false] as Vector2)).length(), 0.5, "as it came out on the LVLH direction held")


## KALCMANU turns the LM about a single axis, on its reference, at 2 °/s;
## a turn whose single axis would swing the thrust axis through the stable
## member's Y goes the long way round, clear of gimbal lock.
func test_kalcmanu_turns_about_a_single_axis_clear_of_gimbal_lock() -> void:
	build("lunar_orbit")
	_undock()
	run(60.0)
	var lgc := rt.lgc()
	Bus.set_value("ctl.lm.mode", 2)
	assert_lt(absf(wrapf(lgc.icdu().z, -180.0, 180.0)), 5.0, "the middle gimbal near zero")
	# 120° of pitch, about the LM's Y, which lies along the stable member's:
	# the inner gimbal alone turns.
	var now := lgc._att()
	lgc.auto_target = (now * Quaternion(Vector3.UP, deg_to_rad(120.0))).normalized()
	lgc._plan_via()
	lgc.auto_active = true
	assert_true(lgc.kal_turning(), "KALCMANU's turn")
	assert_true(lgc.maneuver_vias.is_empty(), "about a single axis")
	assert_almost_eq(rad_to_deg(lgc.kal_angle), 120.0, 0.1, "through 120°")
	var t0 := SimClock.get_seconds
	var box := {"off": 0.0, "peak": 0.0}
	while lgc.kal_turning():
		run(1.0, false)
		box["off"] = maxf(box["off"], rad_to_deg(lgc._att_error(lgc._kal_ref())))
		box["peak"] = maxf(box["peak"], absf(wrapf(lgc.icdu().z, -180.0, 180.0)))
	var took := SimClock.get_seconds - t0
	assert_true(run_until(func() -> bool: return lgc._att_error(lgc.auto_target) < deg_to_rad(0.5), 30.0, 1.0, false),
		"there")
	gut.p("KALCMANU: 120° in %.0f s, %.2f° off its reference at the most, the middle gimbal to %.1f°; there %.0f s on" % [
		took, box["off"], box["peak"], SimClock.get_seconds - t0 - took])
	assert_almost_eq(took, 60.0, 1.0, "at 2 °/s")
	assert_lt(float(box["off"]), 1.0, "on its reference")
	assert_lt(float(box["peak"]), 5.0, "the middle gimbal kept where it was")
	# 150° of yaw, about the LM's Z: on its single axis the thrust axis would
	# swing through the stable member's Y, 90° of middle gimbal.
	now = lgc._att()
	lgc.auto_target = (now * Quaternion(Vector3.BACK, deg_to_rad(150.0))).normalized()
	assert_almost_eq(absf(wrapf(lgc.gimbal_angles_of(lgc.auto_target).z, -180.0, 180.0)), 30.0, 5.0,
		"to an attitude 30° of middle gimbal off")
	lgc._plan_via()
	lgc.auto_active = true
	assert_false(lgc.kal_turning(), "not about its single axis")
	assert_false(lgc.maneuver_vias.is_empty(), "routed")
	box["peak"] = 0.0
	var arrived := run_until(func() -> bool:
		box["peak"] = maxf(box["peak"], absf(wrapf(lgc.icdu().z, -180.0, 180.0)))
		return lgc.maneuver_vias.is_empty() and lgc._att_error(lgc.auto_target) < deg_to_rad(0.5), 900.0, 1.0, false)
	gut.p("Routed: there, the middle gimbal to %.1f° at the most" % box["peak"])
	assert_true(arrived, "there")
	assert_lt(float(box["peak"]), AgcCore.LOCK_MANEUVER_DEG, "the middle gimbal kept under 60°")
	assert_eq(lgc.imu.mode, "operate", "the IMU never caged")

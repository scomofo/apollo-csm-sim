extends SimTest

## Slice 5e's check: LOI-1 on Colossus's cross-product steering leaves an
## orbit nearer the RTCC's plan than holding the ΔV's LVLH direction does,
## and a short burn comes out as it did.


func _alts() -> Vector2:
	var c := rt.dynamics.traj.conic()
	return Vector2(float(c["rp"]) - Bodies.R_MOON, float(c["ra"]) - Bodies.R_MOON) / Units.NMI


func test_loi_on_cross_product_steering_meets_the_rtccs_plan() -> void:
	build("translunar_coast")
	var mcc := rt.sequencer.request_pad("mcc")
	if not mcc.is_empty():
		fly_pad()
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	run(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds)
	var loi := rt.sequencer.request_pad("loi")
	assert_false(loi.is_empty(), "LOI-1 planned")
	var plan := Vector2(float(loi["hp"]), float(loi["ha"])) / Units.NMI
	var before := rt.snapshot()
	var in_orbit := {}
	# LOI-1 as Colossus flew it, and then as the simulator did before.
	var miss := {}
	var flown := {}
	for law in [true, false]:
		if not law:
			assert_eq(rt.restore(before), "")
		rt.agc().cross_product_steering = law
		var dv := fly_pad()
		run(600.0)
		flown[law] = _alts()
		miss[law] = flown[law] - plan
		gut.p("LOI-1 on %s: %.1f ft/s, %.2f x %.2f nmi (the plan %.2f x %.2f)" % [
			"cross-product steering" if law else "the LVLH direction held", dv / Units.FT, flown[law].x, flown[law].y,
			plan.x, plan.y])
		if law:
			in_orbit = rt.snapshot()
	gut.p("LOI-1's ΔV %.1f ft/s (Apollo 11: 2,917.5)" % (float(loi["dv"]) / Units.FT))
	# The perilune misses by the CMC's navigation, either way: it sets the
	# burn from its own state vector at TIG, and the plan came from MSFN's.
	assert_lt(absf(miss[true].x), 3.5, "the perilune near the plan's")
	assert_lt(absf(miss[true].y), 1.0, "the apolune on the plan's")
	assert_gt(absf(miss[false].y), 5.0, "held along the LVLH direction, the apolune misses the plan's")
	assert_gt(miss[false].length(), 2.0 * miss[true].length(), "nearer the plan than the LVLH direction held")
	# LOI-2, 15 s, both ways from the same orbit.
	var after := {}
	for law in [true, false]:
		assert_eq(rt.restore(in_orbit), "")
		rt.agc().cross_product_steering = law
		var circ := rt.sequencer.request_pad("circ")
		assert_false(circ.is_empty())
		fly_pad()
		after[law] = _alts()
	gut.p("LOI-2: %.3f x %.3f nmi on cross-product steering, %.3f x %.3f on the LVLH direction" % [after[true].x,
		after[true].y, after[false].x, after[false].y])
	assert_lt((after[true] - after[false]).length(), 0.2, "a short burn comes out as it did")


## A checkpoint taken in the burn's last seconds, where the steering has
## stopped with the thrust held, flies on to the same cutoff: the velocity
## to be gained and the held direction come back with it.
func test_a_checkpoint_in_the_burns_last_seconds_flies_on_to_the_same_cutoff() -> void:
	build("lunar_orbit")
	var agc := rt.agc()
	agc.uplink_maneuver(SimClock.get_seconds + 900.0, Vector3(-40.0, 0.0, 12.0))
	keys("V37E30E")
	keys("PPP")
	var tig := agc.maneuver_tig
	run(tig - 600.0 - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 2)
	keys("V37E40E")
	keys("P")
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.arm_b", true)
	run(tig - 12.0 - SimClock.get_seconds)
	assert_true(run_until(func() -> bool: return agc.step_name == "v99", 20.0, 1.0, false), "V99")
	keys("P")
	var a := agc.engine_thrust(40) / rt.dynamics.mass
	assert_true(run_until(func() -> bool: return agc.step_name == "burn" and agc.vg_left < a * 2.0, 60.0, 0.1, false),
		"into the last seconds")
	var held := agc.burn_dir
	var snap := rt.snapshot()
	var ends := []
	for i in 2:
		if i == 1:
			assert_eq(rt.restore(snap), "")
			assert_almost_eq(agc.burn_dir, held, Vector3.ONE * 1e-6, "the held direction came back")
		assert_true(run_until(func() -> bool: return agc.step_name == "post", 60.0, 0.1, false), "cut off")
		run(10.0, false)
		var tr := rt.dynamics.traj
		ends.append([tr.pos(), tr.vel(), Vector3(agc.vg[0], agc.vg[1], agc.vg[2])])
	gut.p("restored in the last seconds: %.3f m and %.5f m/s from the uninterrupted flight" % [
		(ends[0][0] - ends[1][0]).length(), (ends[0][1] - ends[1][1]).length()])
	assert_lt((ends[0][1] - ends[1][1]).length(), 1e-3, "the same cutoff")
	assert_lt((ends[0][2] - ends[1][2]).length(), 1e-3, "and the same residuals")

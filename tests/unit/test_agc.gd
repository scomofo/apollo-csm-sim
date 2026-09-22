extends SimTest


func test_p40_without_maneuver_is_a_program_alarm() -> void:
	build("lunar_orbit")
	keys("V37E40E")
	assert_eq(rt.agc().program, 0)
	assert_true(rt.agc().dsky.lamps["prog"])
	keys("V05N09E")   # unknown verb -> operator error
	assert_true(rt.agc().dsky.lamps["opr_err"])
	keys("R")
	assert_false(rt.agc().dsky.lamps["prog"])


func test_p30_accepts_crew_loaded_pad_and_predicts_apsides() -> void:
	build("lunar_orbit")
	var tig := SimClock.get_seconds + 1200.0
	keys("V37E30E")
	assert_eq(rt.agc().dsky.verb, "06")
	assert_eq(rt.agc().dsky.noun, "33")
	assert_true(rt.agc().dsky.flashing)
	var h := int(tig / 3600.0)
	var m := int(fmod(tig, 3600.0) / 60.0)
	var s := fmod(tig, 60.0)
	keys("V25E+%05dE+%05dE+%05dE" % [h, m, int(round(s * 100.0))])
	assert_almost_eq(rt.agc().tig_load, tig, 0.01)
	keys("P")
	assert_eq(rt.agc().dsky.noun, "81")
	keys("V25E+00500E+00000E+00000E")   # +50.0 ft/s posigrade
	keys("P")
	assert_eq(rt.agc().dsky.noun, "42")
	var ha := rt.agc().dsky.r[0].to_int() / 10.0
	var hp := rt.agc().dsky.r[1].to_int() / 10.0
	assert_between(ha, 90.0, 105.0, "posigrade 50 ft/s raises the far side ~38 nmi")
	assert_almost_eq(hp, 59.9, 1.5)
	keys("P")
	assert_true(rt.agc().maneuver_valid)
	assert_eq(rt.agc().program, 0)


func test_uplinked_small_burn_is_flown_to_within_half_a_foot_per_second() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var before := rt.dynamics.traj.conic()
	rt.agc().uplink_maneuver(SimClock.get_seconds + 900.0, Vector3(30.0, 0.0, 0.0))
	assert_true(rt.agc().dsky.lamps["uplink_acty"])
	var dv := fly_pad()
	assert_almost_eq(dv, 30.0, 0.15)
	var after := rt.dynamics.traj.conic()
	assert_gt(float(after["ra"]), float(before["ra"]) + 50000.0, "apolune raised")
	var res: Array = rt.agc().noun_values(85)
	assert_lt(Vector3(res[0], res[1], res[2]).length(), 0.3, "N85 residuals small")


func test_v82_shows_orbit_parameters() -> void:
	build("lunar_orbit")
	keys("V82E")
	assert_eq(rt.agc().dsky.noun, "44")
	assert_almost_eq(rt.agc().dsky.r[1].to_int() / 10.0, 59.9, 0.5)


func test_p41_rcs_burn_for_a_small_trim() -> void:
	build("lunar_orbit")
	rt.agc().uplink_maneuver(SimClock.get_seconds + 600.0, Vector3(0.9, 0.0, 0.0))
	var dv := fly_pad()
	assert_almost_eq(dv, 0.9, 0.05, "3 ft/s trim on the RCS")
	assert_eq(int(Bus.get_value("sps.ignitions")), 0, "SPS never lit")

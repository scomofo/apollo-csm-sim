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
	# 50 ft/s posigrade adds 70 km to the orbit's major axis, raising the
	# far side ~38 nmi; the burn's point becomes the pericynthion.
	var c := rt.dynamics.traj.conic()
	var sum_before := (float(c["ra"]) + float(c["rp"]) - 2.0 * Bodies.R_MOON) / Units.NMI
	assert_almost_eq(ha + hp - sum_before, 37.7, 1.5, "posigrade 50 ft/s raises the far side ~38 nmi")
	var at := rt.dynamics.traj.clone()
	at.coast_to(tig, 60.0)
	assert_almost_eq(hp, at.altitude() / Units.NMI, 1.5, "the pericynthion where the burn is")
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
	# The orbit after LOI-2, 65.7 by 53.8 nmi above the landing site's
	# radius, 1.04 nmi below the Moon's mean radius, the display's datum.
	assert_almost_eq(rt.agc().dsky.r[0].to_int() / 10.0, 64.7, 1.0, "HA")
	assert_almost_eq(rt.agc().dsky.r[1].to_int() / 10.0, 52.8, 1.0, "HP")


func test_p41_rcs_burn_for_a_small_trim() -> void:
	build("lunar_orbit")
	rt.agc().uplink_maneuver(SimClock.get_seconds + 600.0, Vector3(0.9, 0.0, 0.0))
	var dv := fly_pad()
	assert_almost_eq(dv, 0.9, 0.05, "3 ft/s trim on the RCS")
	assert_eq(int(Bus.get_value("sps.ignitions")), 0, "SPS never lit")


## Colossus's velocity to be gained for an External ΔV (slice 5e): the
## ΔV's part in the orbit's plane turned about its normal, the way the
## vehicle moves, through half the arc it sweeps in the burn at constant
## mass (Comanche 055's S40.1), its part out of the plane and its size as
## loaded. On a 60 nmi lunar orbit a retrograde 300 m/s burn held along
## it points within a fifth of a degree of the retrograde at the burn's
## middle, where the ΔV as loaded points 2.4° off.
func test_the_external_dv_is_centred_on_the_burn() -> void:
	var r0 := Bodies.R_MOON + 60.0 * Units.NMI
	var w := sqrt(Bodies.MU_MOON / r0) / r0
	var mass := 30000.0
	var sps := SpacecraftData.section("sps")
	var f := float(sps["thrust_n"])
	var dv := Vector3(0.0, -300.0, 20.0)
	var g := AgcCore.external_dv_vg(Vector3(r0, 0, 0), Vector3(0, w * r0, 0), dv, mass, f)
	var theta := 0.5 * w * mass * dv.length() / f
	assert_almost_eq(g.length(), dv.length(), 1e-3, "its size as loaded")
	assert_almost_eq(g.z, dv.z, 1e-4, "its part out of the plane as loaded")
	assert_almost_eq(atan2(g.x, -g.y), theta, 1e-5, "turned outward, the way the orbit carries the retrograde")
	var prograde := AgcCore.external_dv_vg(Vector3(r0, 0, 0), Vector3(0, w * r0, 0), Vector3(0, 300.0, 0), mass, f)
	assert_almost_eq(atan2(-prograde.x, prograde.y), 0.5 * w * mass * 300.0 / f, 1e-5, "and the prograde inward")
	# The burn's middle, from its time on the rocket equation.
	var tb := Rtcc.burn_time(mass, dv.length())
	var mid := w * tb / 2.0
	var retro_mid := Vector3(sin(mid), -cos(mid), 0.0)
	var in_plane := Vector3(g.x, g.y, 0.0)
	gut.p("turned %.3f deg; %.3f deg from the retrograde at the burn's middle, where the ΔV as loaded is %.3f deg off" % [
		rad_to_deg(theta), rad_to_deg(in_plane.angle_to(retro_mid)), rad_to_deg(Vector3(0, -1, 0).angle_to(retro_mid))])
	assert_lt(rad_to_deg(in_plane.angle_to(retro_mid)), 0.2)
	assert_gt(rad_to_deg(Vector3(0, -1, 0).angle_to(retro_mid)), 2.0)

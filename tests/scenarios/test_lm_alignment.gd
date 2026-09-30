## Slice 11a's check (docs/ROADMAP.md, milestone 11): the LGC's platform is
## a real one, and P52 aligns it on the alignment optical telescope's
## marks. Eagle undocks from Columbia at 100:12:00 with its platform on the
## landing site REFSMMAT, where its crew's docked alignment left it: off by
## what their first P52 found, less the drift until then, its gyros
## drifting as the mission report measured them. At 101:15 that P52, on
## stars 25 (Acrux) and 33 (Antares) through the front detent, marked as
## Armstrong did by turning the LM until each star crossed the reticle's
## Y-line and then its X-line, shows the flown star angle difference and
## torquing angles (N93 -0.292, +0.289 and -0.094 deg) and takes the
## platform back onto the REFSMMAT. DOI and the automatic landing then fly
## on it, drifting on; the landing comes within the ideal platform's limit
## of the site.
extends SimTest

const UNDOCKING := 100.0 * 3600.0 + 12.0 * 60.0
## The P52 starts at 101:12 [estimated: its marks came before 101:19:46,
## when Armstrong read N93 out].
const P52_START := 101.0 * 3600.0 + 12.0 * 60.0
const FLOWN_N93 := Vector3(-0.292, 0.289, -0.094)
const FLOWN_SAD := 0.03
## The platform after the P52's torquing, and at the touchdown, deg; the
## landing's miss from the site, m, test_landing.gd's for the ideal
## platform.
const ALIGNED_DEG := 0.01
const TOUCHDOWN_DEG := 0.2
const MISS_M := 500.0


func _undock() -> void:
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)


func test_eagles_p52_after_undocking_aligns_the_platform_and_the_landing_flies_on_it() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	var lgc := rt.lgc()
	var sq := rt.sequencer
	run(UNDOCKING - SimClock.get_seconds)
	_undock()
	assert_false(lgc.imu.ideal, "the LGC's platform a real one")
	assert_true(lgc.imu.aligned and lgc.imu.operating(), "aligned docked")
	assert_almost_eq(lgc.imu.drift / MissionSequencer.MERU_RAD_S, Vector3(4.5, -5.0, 0.4), Vector3.ONE * 1e-6,
		"Eagle's gyros drifting as the mission report measured, mERU")
	var mis0 := rad_to_deg(lgc.imu.misalignment().length())
	assert_between(mis0, 0.25, 0.40, "off by about the first P52's angles less the hour's drift")
	# The P52, an hour on: the LGC turns Eagle to each star in the front
	# detent, and the crew marks them.
	run(P52_START - SimClock.get_seconds)
	var p52 := lm_realign([25, 33])
	var n93: Vector3 = p52["torque"]
	gut.p("P52 on %s and %s at %s: N05 %.3f deg (flown %.2f), N93 %s (flown %s); the platform %.4f deg off after" % [
		Stars.name_of(25), Stars.name_of(33), Units.hms(p52["get"]), p52["sad"], FLOWN_SAD, n93, FLOWN_N93,
		rad_to_deg(lgc.imu.misalignment().length())])
	assert_eq(p52["stars"], [25, 33], "Acrux and Antares")
	assert_lt(float(p52["sad"]), FLOWN_SAD, "N05: the stars' angle as marked, within the flown's 0.03 deg")
	assert_almost_eq(n93, FLOWN_N93, Vector3.ONE * 0.015, "N93 as Armstrong read it out")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), ALIGNED_DEG, "the platform on the REFSMMAT")
	# DOI on the aligned platform, from the PAD that came after undocking.
	assert_true(sq.pads.has("doi"), "the DOI PAD")
	var doi: Dictionary = sq.pads["doi"]
	var dv := fly_lm_pad(40, 2)
	assert_almost_eq(dv, (doi["dv_lvlh"] as Vector3).length(), 0.05, "DOI's ΔV")
	# PDI, and the automatic landing with the radar's updates.
	assert_true(run_until(func() -> bool: return sq.pads.has("pdi"), 7200.0, 30.0), "the PDI PAD")
	keys("V37E63E", lgc)
	assert_eq(lgc.program, 63, "P63")
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	var mis_pdi := rad_to_deg(lgc.imu.misalignment().length())
	keys("P", lgc)
	var seen := {}
	var landed := run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		return rt.dynamics.lm.landed, 1000.0, 1.0, false)
	assert_true(landed, "touchdown")
	var td: Dictionary = rt.dynamics.lm.touchdown
	var miss := rt.dynamics.lm.landed_pos.angle_to(sq.landing_site()) * Bodies.R_MOON
	var mis_td := rad_to_deg(lgc.imu.misalignment().length())
	gut.p("The platform %.3f deg off at PDI and %.3f at touchdown; Eagle landed %.0f m from the site, %.2f m/s down and %.2f m/s across" % [
		mis_pdi, mis_td, miss, td["vertical_mps"], td["horizontal_mps"]])
	assert_lt(mis_td, TOUCHDOWN_DEG, "drifting on at Eagle's rates")
	assert_lt(miss, MISS_M, "near the site")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])

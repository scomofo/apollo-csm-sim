## Slice 11b's check (docs/ROADMAP.md, milestone 11): P57 on the surface.
## Eagle sits at Tranquility Base yawed 13° left of the way it came in, as
## it came to rest, its platform aligned 10 min after the landing (the
## lunar_surface start) and drifting at the rates the mission report
## measured on the surface. Its crew's P57s come as Apollo 11's did
## (MSC-00171, Table 9.6-I; the Apollo Lunar Surface Journal):
##   103:01  option 3, technique 1: gravity, twice as Houston asked, and
##           N93 not torqued (V34)
##   103:47  option 3, technique 2: Rigel through the left-rear detent and
##           Navi through the right-rear; the site from gravity rejected
##   104:16  option 4 to the landing site at T3 (104:39:47), technique 3
##           on Rigel
##   122:17  option 3, technique 3 on Capella: N93 the 18 hours' drift
##           (flown -0.699, +0.695 and -0.628)
##   123:49  option 4 to the site at the liftoff, technique 3 on Capella
## R59 finds each star in the detent the crew used, and P12 flies Eagle
## to its insertion on the last alignment.
extends SimTest

const T3 := 104.0 * 3600.0 + 39.0 * 60.0 + 47.0
const FLOWN_122 := Vector3(-0.699, 0.695, -0.628)
## The platform after each torquing, deg [estimated: the counter's
## hundredths, and the plumb line's lean off the landing site's radius].
const ALIGNED_DEG := 0.02


func _at(h: int, m: int) -> void:
	run(h * 3600.0 + m * 60.0 - SimClock.get_seconds)


func test_eagles_p57s_align_the_platform_and_the_ascent_flies_on_them() -> void:
	build("lunar_surface")
	var lgc := rt.lgc()
	var sq := rt.sequencer
	assert_almost_eq(lgc.imu.drift / MissionSequencer.MERU_RAD_S, Vector3(2.6, -2.6, 2.3), Vector3.ONE * 1e-6,
		"Eagle's gyros drifting as the report measured them on the surface, mERU")
	var rows := []
	# 103:01: gravity, twice; N93 left untorqued.
	_at(102, 58)
	var p1 := surface_align(3, 1, [], 2, 1, false)
	rows.append(["103:01", p1])
	assert_eq((p1["n04"] as Array).size(), 2, "gravity measured twice")
	assert_lt(float(p1["n04"][1]), 0.02, "N04: the second as the first")
	# 103:47: two stars; the site from gravity rejected.
	_at(103, 40)
	var p2 := surface_align(3, 2, [12, 3])
	rows.append(["103:47", p2])
	assert_eq(p2["detents"], [6, 4], "Rigel in the left rear, Navi in the right rear, as flown")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), ALIGNED_DEG, "aligned on the stars")
	var here := Bodies.moon_fixed(SimClock.get_seconds).transposed() * rt.dynamics.lm.traj.pos()
	gut.p("The site from gravity %.0f m from Eagle" % (p2["site"] as Vector3).distance_to(here))
	# 104:16: to the site at T3, on Rigel.
	_at(104, 10)
	var p3 := surface_align(4, 3, [12], 1, 1, true, T3)
	rows.append(["104:16", p3])
	assert_eq(p3["detents"], [6], "Rigel in the left rear")
	var x := Imu.axis(lgc.imu.refsmmat, 0)
	assert_lt(rad_to_deg(x.angle_to(Bodies.moon_fixed(T3) * lgc.nav_landed_mf)), 1e-3, "X up through Eagle at T3")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), ALIGNED_DEG, "aligned to it")
	# 122:17: the night's drift.
	_at(122, 10)
	var mis := lgc.imu.misalignment()
	var p4 := surface_align(3, 3, [13])
	rows.append(["122:17", p4])
	assert_eq(p4["detents"], [4], "Capella in the right rear")
	assert_almost_eq(p4["torque"], FLOWN_122, Vector3.ONE * 0.03, "N93: the drift since 104:16, as flown")
	assert_lt(((p4["torque"] as Vector3) - lgc.imu.refsmmat * mis * (180.0 / PI)).length(), 0.03,
		"the platform's own turn, stable member axes")
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), ALIGNED_DEG, "aligned again")
	# 123:49: to the site at the liftoff, the ascent PAD in since 122:22.
	_at(123, 45)
	var pad: Dictionary = sq.pads.get("ascent", {})
	assert_false(pad.is_empty(), "the ascent PAD in")
	var tig := float(pad.get("tig", 0.0))
	var p5 := surface_align(4, 3, [13])
	rows.append(["123:49", p5])
	assert_almost_eq(float(lgc.surface.talign), tig, 0.01, "TALIGN the ascent PAD's liftoff")
	assert_lt(rad_to_deg(Imu.axis(lgc.imu.refsmmat, 0).angle_to(Bodies.moon_fixed(tig) * lgc.nav_landed_mf)), 1e-3,
		"X up through Eagle at the liftoff")
	for r in rows:
		var p: Dictionary = r[1]
		gut.p("P57 at %s: N04 %s, N05 %.3f, N93 %s, R59's detents %s" % [r[0], p["n04"], p["sad"], p["torque"], p["detents"]])
	# The liftoff, on it.
	keys("V37E12E", lgc)
	keys("PP", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(tig - 12.0 - SimClock.get_seconds)
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	Bus.set_value("ctl.lm.engine_arm", 1)
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.step_name == "post", 600.0, 1.0, false), "insertion")
	var nav := lgc.current_traj()
	var tr := rt.dynamics.lm.traj
	var c := tr.conic()
	var site_r := sq.landing_site().length()
	var off := rad_to_deg(lgc.imu.misalignment().length())
	gut.p("Insertion: the LGC has Eagle at %.0f ft, %.1f ft/s up; truly %.0f ft, %.1f ft/s up, %.1f x %.1f nmi; the platform %.3f deg off" % [
		(nav.radius() - lgc.ascent_base) / Units.FT, nav.radial_rate() / Units.FT, (tr.radius() - lgc.ascent_base) / Units.FT,
		tr.radial_rate() / Units.FT, (float(c["rp"]) - site_r) / Units.NMI, (float(c["ra"]) - site_r) / Units.NMI, off])
	# The surface's drift from the P57 to the liftoff and the flight's to
	# the insertion, and the alignment's hundredths.
	var drifted := rad_to_deg(Vector3(2.6, 2.6, 2.3).length() * MissionSequencer.MERU_RAD_S * (tig - p5["get"])
		+ Vector3(4.5, 5.0, 0.4).length() * MissionSequencer.MERU_RAD_S * (SimClock.get_seconds - tig))
	assert_lt(off, drifted + 0.02, "the platform off by the drift since 123:49 (%.3f deg)" % drifted)
	assert_almost_eq((tr.radius() - lgc.ascent_base) / Units.FT, 60000.0, 800.0, "truly near 60,000 ft")
	assert_almost_eq((float(c["rp"]) - site_r) / Units.NMI, 9.0, 1.0, "perilune near 9 nmi")

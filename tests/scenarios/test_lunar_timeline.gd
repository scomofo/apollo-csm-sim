## Slice 3f (docs/ROADMAP.md, milestone 3): Mission Control's timeline from
## undocking to TEI (mission.json "lunar_timeline"), and the start phases
## flown on from the lunar orbit start: lunar_descent, lunar_surface and
## lunar_ascent. The landing from lunar_descent is tests/scenarios/
## test_landing.gd's, and the docking from lunar_ascent
## tests/scenarios/test_rendezvous.gd's.
extends SimTest

const UNDOCKING := 100.0 * 3600.0 + 12.0 * 60.0


func test_mission_control_calls_the_undocking_and_uplinks_doi() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	var sq := rt.sequencer
	run(100.0 * 3600.0 + 10.0 - SimClock.get_seconds)
	assert_almost_eq(float(sq.timeline_done.get("go_undocking", -1.0)), 100.0 * 3600.0, 10.0, "GO for undocking")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "GO for undocking")
	run(UNDOCKING - SimClock.get_seconds)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_true(run_until(func() -> bool: return sq.pads.has("doi"), 600.0, 1.0), "the DOI PAD")
	var doi: Dictionary = sq.pads["doi"]
	gut.p("%s, landing at %s" % [Rtcc.pad_text(doi), Units.hms(float(doi["land_get"]))])
	assert_almost_eq(SimClock.get_seconds - sq.event_get("undocking"), 509.0, 2.0, "8 min 29 s after undocking (Apollo 11)")
	assert_true(rt.lgc().landing_site != Vector3.ZERO, "the landing site uplinked with it")
	assert_eq(float(sq.plan["doi_tig"]), float(doi["tig"]))
	var land := float(rt.mission.section("landing")["get_s"])
	var period := float(rt.dynamics.traj.conic()["period"])
	assert_almost_eq(float(doi["land_get"]), land, 0.5 * period, "the pass that lands nearest 102:45:40")
	run(float(doi["tig"]) - 1101.0 + 10.0 - SimClock.get_seconds)
	assert_almost_eq(float(sq.timeline_done.get("go_doi", -1.0)), float(doi["tig"]) - 1101.0, 10.0,
		"GO for DOI 18 min 21 s before it (Apollo 11)")
	assert_eq(sq.phase, "lunar_orbit", "not descending before DOI")


func test_an_early_undocking_brings_no_doi_pad() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	run(900.0)
	assert_false(rt.sequencer.pads.has("doi"), "a day before the landing: practice")
	assert_eq(float(rt.sequencer.timeline_done.get("doi_pad", 0.0)), -1.0, "passed by")


func test_lunar_descent_starts_on_the_descent_orbit_before_pdi() -> void:
	build("lunar_descent")
	var sq := rt.sequencer
	var lm := rt.dynamics.lm
	var lgc := rt.lgc()
	var site := sq.landing_site()
	assert_eq(sq.phase, "lunar_descent")
	assert_eq(sq.event_get("undocking"), UNDOCKING, "undocked at Apollo 11's time")
	assert_almost_eq(sq.event_get("pad_doi") - UNDOCKING, 509.0, 1e-6, "and the DOI PAD after it")
	assert_almost_eq(SimClock.get_seconds, float(sq.plan["pdi_tig"]) - 1200.0, 1e-6, "20 min before PDI")
	var c := lm.traj.conic()
	assert_almost_eq(float(c["rp"]) - site.length(), 15240.0, 100.0, "the perilune 50,000 ft above the site")
	assert_eq(lgc.landing_site, site, "the LGC has the site")
	assert_lt((lgc.nav.pos() - lm.traj.pos()).length(), 1.0, "and its own state vector")
	var full := float(SpacecraftData.section("dps")["propellant_kg"])
	assert_between(full - float(Bus.get_value("lm.dps.prop_kg")), 80.0, 150.0, "DOI's propellant used")
	assert_eq(int(Bus.get_value("ctl.cmc.mode")), 0, "Columbia drifts")
	assert_true(sq.timeline_done.has("go_doi"), "DOI's calls behind")
	assert_false(sq.timeline_done.has("pdi_pad"), "PDI's ahead")


func test_lunar_surface_starts_on_the_ground_after_the_landing() -> void:
	build("lunar_surface")
	var sq := rt.sequencer
	var lm := rt.dynamics.lm
	var doi: Dictionary = sq.pads["doi"]
	assert_eq(sq.phase, "lunar_surface")
	assert_true(lm.landed, "Eagle on its gear")
	assert_lt(lm.landed_pos.angle_to(sq.landing_site()) * Bodies.R_MOON, 1.0, "at the site")
	assert_eq(sq.event_get("lm_landing"), float(doi["land_get"]), "when DOI planned it")
	assert_almost_eq(SimClock.get_seconds, float(doi["land_get"]) + 600.0, 1e-6, "10 min on")
	assert_almost_eq(float(Bus.get_value("lm.dps.prop_kg")), 687.0, 1e-6)
	assert_true(sq.timeline_done.has("stay_t2"), "STAY for T2 given")
	assert_true(sq.timeline_done.get("go_pdi", -1.0) > 0.0, "and GO for powered descent before it")
	# T3, and then the ascent PAD at 122:22:00 for the liftoff nearest
	# Apollo 11's 124:22:00.
	run(float(doi["land_get"]) + 5736.0 + 10.0 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "STAY for T3")
	run(122.0 * 3600.0 + 22.0 * 60.0 + 10.0 - SimClock.get_seconds)
	var pad: Dictionary = sq.pads.get("ascent", {})
	assert_eq(str(pad.get("name", "")), "ASCENT")
	var period := float(rt.dynamics.traj.conic()["period"])
	assert_almost_eq(float(pad["tig"]), 124.0 * 3600.0 + 22.0 * 60.0, 0.5 * period, "the window nearest 124:22:00")
	assert_eq(rt.lgc().tig_load, float(pad["tig"]), "the liftoff time uplinked")
	assert_true(rt.lgc().csm_nav != null, "with Columbia's state vector")


func test_lunar_ascent_starts_with_the_ascent_pad_in() -> void:
	build("lunar_ascent")
	var sq := rt.sequencer
	var tig := float(sq.plan["liftoff_tig"])
	assert_eq(sq.phase, "lunar_surface", "still on the surface")
	assert_almost_eq(SimClock.get_seconds, tig - 1200.0, 1e-6, "20 min before liftoff")
	assert_almost_eq(sq.event_get("pad_ascent"), 122.0 * 3600.0 + 22.0 * 60.0, 1e-6, "the PAD at 122:22:00")
	assert_true(sq.timeline_done.has("stay_t3"))
	assert_eq(rt.lgc().tig_load, tig, "P12's TIG")
	keys("V37E12E", rt.lgc())
	assert_eq(rt.lgc().program, 12, "P12 takes it")
	run(tig - 300.0 + 10.0 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "cleared for takeoff")


func test_the_timeline_goes_on_from_a_checkpoint_as_it_would_have() -> void:
	build("lunar_descent")
	run(120.0)
	var text := JSON.stringify(rt.snapshot())
	run(600.0)
	var done := rt.sequencer.timeline_done.duplicate()
	var plan := rt.sequencer.plan.duplicate()
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_false(rt.sequencer.timeline_done.has("pdi_pad"), "the PDI PAD still to come")
	run(600.0)
	# The same entries at the same times, give or take a fixed step (the
	# restored run's steps fall a step apart), and the same plan.
	_assert_times(rt.sequencer.timeline_done, done, 0.05, "the timeline")
	_assert_times(rt.sequencer.plan, plan, 0.01, "the plan")


func _assert_times(got: Dictionary, want: Dictionary, tol: float, what: String) -> void:
	assert_eq(got.size(), want.size(), "%s: as many entries" % what)
	for k in want:
		assert_true(got.has(k), "%s has %s" % [what, k])
		assert_almost_eq(float(got.get(k, INF)), float(want[k]), tol, "%s: %s" % [what, k])

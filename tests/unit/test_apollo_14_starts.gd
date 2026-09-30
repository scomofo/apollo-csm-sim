## Slice 12a (docs/ROADMAP.md, milestone 12): Apollo 14's LM start phases,
## which begin on the descent orbit Kitty Hawk's DOI left, and its ascent
## PAD for the direct rendezvous. The flights from them are
## tests/scenarios/test_apollo_14.gd's and test_apollo_14_return.gd's.
extends SimTest


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## Slice 12a: Apollo 14's LM start phases begin on the descent orbit
## Kitty Hawk's DOI left: Antares undocks on it at 103:47, Kitty Hawk climbs
## back to 60 nmi on the way (CIRC, the timeline's PAD at its 105:11:45
## TIG), PDI is on the landing pass the start planned, and the landing site
## goes to the LGC with the PDI PAD, two hours before PDI.
func test_apollo_14s_lunar_descent_starts_on_the_descent_orbit_kitty_hawk_left() -> void:
	build("lunar_descent", "apollo_14")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_descent", "Antares on the descent orbit")
	var lm := rt.dynamics.lm
	assert_not_null(lm, "undocked")
	var r := sq.landing_site().length()
	var c := lm.traj.conic()
	assert_almost_eq((float(c["ra"]) - r) / Units.NMI, 59.0, 3.0, "Antares's orbit: the high point where DOI was")
	assert_almost_eq((float(c["rp"]) - r) / Units.NMI, 8.5, 2.5, "and the low point about 9 nmi up")
	var k := rt.dynamics.traj.conic()
	assert_almost_eq((float(k["rp"]) - r) / Units.NMI, 55.5, 2.0, "Kitty Hawk circularized")
	assert_almost_eq(float(sq.pads["circ"]["tig"]), MissionSequencer._get_s("105:11:45.21"), 1.0, "at the CIRC PAD's TIG")
	assert_true(sq.pads.has("pdi"), "the PDI PAD")
	assert_almost_eq(float(sq.plan["pdi_tig"]), MissionSequencer._get_s("108:02:24.61"), 300.0, "PDI on the landing pass")
	assert_ne(rt.lgc().landing_site, Vector3.ZERO, "the landing site in the LGC")
	assert_between(float(sq.plan["pdi_tig"]) - SimClock.get_seconds, 900.0, 1500.0, "about 20 min before PDI")
	Mission.load_default()


## Slice 12a: Apollo 14's lunar_ascent start: Kitty Hawk's plane change
## over Antares, and the ascent PAD for the direct rendezvous, the liftoff
## timed for TPI 38 min after the insertion with Kitty Hawk 26.6 deg up,
## TPI's TIG uplinked with it (N37).
func test_apollo_14s_lunar_ascent_starts_for_the_direct_rendezvous() -> void:
	build("lunar_ascent", "apollo_14")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_surface")
	assert_true(sq.pads.has("plane") and sq.pads.has("ascent"), "the plane change's PAD and the ascent's")
	var asc: Dictionary = sq.pads["ascent"]
	var tig := float(sq.plan["liftoff_tig"])
	assert_almost_eq(tig, MissionSequencer._get_s("141:45:39.10"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(float(sq.plan["tpi_tig"]) - float(asc["insertion_get"]), 2279.0, 1e-6, "TPI 37 min 59 s after the insertion")
	assert_eq(rt.lgc().rdv_tpi_tig, float(sq.plan["tpi_tig"]), "TPI's TIG in the LGC")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.5, "LOPC-1 put the plane over Antares")
	assert_between(float(asc["phase_deg"]), 3.0, 15.0, "Kitty Hawk a few degrees ahead at the insertion")
	Mission.load_default()

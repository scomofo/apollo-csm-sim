## Slice 12b (docs/ROADMAP.md, milestone 12): Apollo 15's data. The J
## mission's vehicles and its books; its LM start phases, which begin on
## the descent orbit Endeavour's DOI left, after its trim; its ascent PAD
## for the direct rendezvous; and its TEI start, Endeavour's orbit shaped
## for the subsatellite; and the main parachute it lost on the way down.
## The flights from them are tests/scenarios/test_apollo_15.gd's,
## test_apollo_15_return.gd's and test_apollo_15_entry.gd's.
extends SimTest

const LB := 0.45359237


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## Slice 12b: the J mission's vehicles. Falcon's descent stage is heavier,
## its tanks longer and its batteries five, for three days at Hadley.
func test_apollo_15_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_15"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 15 carries Falcon")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack at the S-IVB's second ignition (MPR-SAT-FE-71-2, Table
	# 16-9), the CSM at transposition and docking, the CM after CM/SM SEP,
	# Falcon at its separation, lunar lift-off and landing (MSC-05161,
	# Table A-III) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 139552.0, 1.0, "139,552 kg at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 66885.0 * LB, 1.0, "66,885 lb at docking")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 12965.0 * LB, 1.0, "12,965 lb after CM/SM SEP")
	assert_almost_eq(SpacecraftData.lm_mass(), 36718.0 * LB, 1.0, "Falcon, 36,718 lb at its separation")
	assert_almost_eq(float(SpacecraftData.section("dps")["propellant_kg"]) / LB, 19561.5, 0.5, "the longer tanks' 19,561.5 lb")
	var rcs := 564.2 * LB
	assert_almost_eq(SpacecraftData.lm_total_mass("lm_ascent", 0.0, f[1], rcs), 10915.0 * LB, 1.0,
		"10,915 lb at lift-off, a full ascent load and the RCS's 564.2 lb")
	assert_almost_eq(SpacecraftData.lm_total_mass("lm", 1188.0 * LB, f[1], rcs), 18175.0 * LB, 120.0 * LB,
		"18,175 lb on the surface, the descent engine's 1,188 lb left")
	assert_almost_eq(float(SpacecraftData.section("lm_eps")["battery_ah"]), 2667.0, 1e-6, "five descent batteries and two ascent")
	assert_almost_eq(float(SpacecraftData.section("ascent_guidance")["insertion_hdot_mps"]) / Units.FT, 32.0, 0.01,
		"insertion climbing at the PAD's 32.0 ft/s")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


## Slice 12b: Apollo 15's books. Endeavour flies DOI with Falcon docked and
## circularizes after the undocking, then shapes its orbit for the
## subsatellite before TEI; Falcon's rendezvous is the direct one with no
## tweak, TPI on the ascent engine, and each of its steps checks itself off.
func test_apollo_15_has_its_own_checklists_for_the_three_day_stay() -> void:
	var csm := ChecklistBook.load_default("apollo_15")
	assert_eq(_flight_titles(csm), ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Falcon's landing and TEI", "Entry", "IMU realign (P52)"])
	var lm := ChecklistBook.load_lm("apollo_15")
	var lm_for := {"lunar_orbit": "Undocking and the P52 after it", "lunar_descent": "Powered descent (P63 to P68)",
		"lunar_surface": "Lunar surface and liftoff (P12)",
		"lunar_ascent": "Direct rendezvous and docking (P41, P20, P34 and P42, P35)"}
	assert_eq(lm.lists.size(), 9, "Falcon's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Falcon's for %s" % phase)
	var timeline: Array = Mission.load_file(Mission.path_of("apollo_15")).section("timeline")["entries"]
	var events := []
	for book in [csm, lm]:
		for c in book.lists:
			for step in c.steps:
				for other in ["Eagle", "Columbia", "Intrepid", "Yankee Clipper", "Antares", "Kitty Hawk"]:
					assert_false(str(step["text"]).contains(other), "%s: Apollo 15's" % c.title)
				if book == lm and c in _flight_lists(lm):
					assert_true(step.has("check"), "%s: \"%s\" has a check" % [c.title, step["text"]])
					assert_false(str(step["text"]).contains("P32") or str(step["text"]).contains("P33"), "%s: no CSI or CDH" % c.title)
				var ch := str(step.get("check", {}).get("channel", ""))
				if ch.begins_with("mission.event.timeline_"):
					events.append(ch.trim_prefix("mission.event.timeline_"))
					assert_true(timeline.any(func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
						"%s: %s is on the timeline" % [c.title, ch])
	assert_has(events, "no_tweak", "Houston's word that no tweak was needed")
	assert_has(events, "shaping_pad", "the shaping burn's PAD")
	Mission.load_default()


## Slice 12b: Apollo 15's LM start phases begin on the descent orbit
## Endeavour's DOI left, 60 by 10 nmi after its trim: Falcon undocks on it
## at 100:39:16, Endeavour climbs back to 60 nmi on the way (CIRC, the
## timeline's PAD at its 101:38:58 TIG), PDI is on the landing pass the
## start planned, and the landing site goes to the LGC with the PDI PAD,
## two hours before PDI.
func test_apollo_15s_lunar_descent_starts_on_the_descent_orbit_endeavour_left() -> void:
	build("lunar_descent", "apollo_15")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_descent", "Falcon on the descent orbit")
	var lm := rt.dynamics.lm
	assert_not_null(lm, "undocked")
	var r := sq.landing_site().length()
	var c := lm.traj.conic()
	assert_almost_eq((float(c["ra"]) - r) / Units.NMI, 60.0, 3.0, "Falcon's orbit: the high point where DOI was")
	assert_almost_eq((float(c["rp"]) - r) / Units.NMI, 9.0, 2.5, "and the low point about 9 nmi up")
	var k := rt.dynamics.traj.conic()
	assert_almost_eq((float(k["rp"]) - r) / Units.NMI, 54.3, 2.0, "Endeavour circularized")
	assert_almost_eq(float(sq.pads["circ"]["tig"]), MissionSequencer._get_s("101:38:58.19"), 1.0, "at the CIRC PAD's TIG")
	assert_true(sq.pads.has("pdi"), "the PDI PAD")
	assert_almost_eq(float(sq.plan["pdi_tig"]), MissionSequencer._get_s("104:30:08.54"), 300.0, "PDI on the landing pass")
	assert_ne(rt.lgc().landing_site, Vector3.ZERO, "the landing site in the LGC")
	assert_between(float(sq.plan["pdi_tig"]) - SimClock.get_seconds, 900.0, 1500.0, "about 20 min before PDI")
	Mission.load_default()


## Slice 12b: Apollo 15's lunar_ascent start: Endeavour's plane change
## over Falcon, and the ascent PAD for the direct rendezvous, the liftoff
## timed for TPI 45 min after the insertion, TPI's TIG uplinked with it
## (N37).
func test_apollo_15s_lunar_ascent_starts_for_the_direct_rendezvous() -> void:
	build("lunar_ascent", "apollo_15")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_surface")
	assert_true(sq.pads.has("plane") and sq.pads.has("ascent"), "the plane change's PAD and the ascent's")
	var asc: Dictionary = sq.pads["ascent"]
	var tig := float(sq.plan["liftoff_tig"])
	assert_almost_eq(tig, MissionSequencer._get_s("171:37:22.36"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(float(sq.plan["tpi_tig"]) - float(asc["insertion_get"]), 2704.9, 1e-6, "TPI 45 min 5 s after the insertion")
	assert_eq(rt.lgc().rdv_tpi_tig, float(sq.plan["tpi_tig"]), "TPI's TIG in the LGC")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.5, "LOPC-1 put the plane over Falcon")
	assert_between(float(asc["phase_deg"]), 3.0, 15.0, "Endeavour a few degrees ahead at the insertion")
	Mission.load_default()


## Slice 12b: Apollo 15's TEI start: Endeavour alone a minute before the
## TEI PAD, its orbit shaped for the subsatellite, 76 by 54 nmi, as the
## RTCC planned the burn at its PAD's TIG (the timeline's "shape").
func test_apollo_15s_tei_starts_with_endeavours_orbit_shaped() -> void:
	build("tei", "apollo_15")
	var sq := rt.sequencer
	assert_eq(rt.dynamics.config, "csm", "Endeavour alone")
	assert_almost_eq(SimClock.get_seconds, MissionSequencer._get_s("222:42:54") - 60.0, 1.0, "a minute before the TEI PAD")
	var r := sq.landing_site().length()
	var c := rt.dynamics.traj.conic()
	assert_almost_eq((float(c["ra"]) - r) / Units.NMI, 76.1, 2.0, "the orbit shaped for the subsatellite")
	assert_almost_eq((float(c["rp"]) - r) / Units.NMI, 54.3, 2.0, "and its perilune")
	Mission.load_default()


## Slice 12b: the main parachute Apollo 15 lost, armed on the mains' coming
## out (tests/scenarios/test_apollo_15_entry.gd flies the entry on two).
func test_apollo_15s_main_parachute_fails_99_s_after_the_mains_come_out() -> void:
	build("transearth_coast", "apollo_15")
	assert_eq(rt.failures.armed_on.get("els_main", {}), {"event": "main_chutes", "after_s": 99.0}, "armed on the mains")
	Bus.set_value("els.mains", true)
	run(1.0, false)
	var out := rt.sequencer.event_get("main_chutes")
	assert_gt(out, 0.0, "the mains out")
	assert_true(run_until(func() -> bool: return rt.failures.active.has("els_main"), 120.0, 1.0, false), "a main deflated")
	assert_almost_eq(float(rt.failures.active.get("els_main", 0.0)) - out, 99.0, 0.05, "99 s after they came out")
	assert_almost_eq(float(Bus.get_value("els.main_cds_factor")), 0.79, 1e-6, "two mains' drag")
	Mission.load_default()


## The checklists of [param book] that aren't malfunction procedures.
func _flight_lists(book: ChecklistBook) -> Array:
	return book.lists.filter(func(c: Checklist) -> bool: return not c.title.begins_with("Malfunction: "))


## The titles of [param book]'s flight checklists.
func _flight_titles(book: ChecklistBook) -> Array:
	return book.lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return not t.begins_with("Malfunction: "))

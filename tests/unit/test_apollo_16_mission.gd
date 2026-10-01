## Slice 12c (docs/ROADMAP.md, milestone 12): Apollo 16's data. Its
## vehicles and its books; the wave-off, which moves PDI and the landing
## three of the LM's revolutions on; its LM start phases, which begin on
## the descent orbit Casper's DOI left, its first circularization held and
## the second flown; its ascent PAD for the direct rendezvous; and its TEI
## start, a day early. The flights from them are tests/scenarios/
## test_apollo_16.gd's, test_apollo_16_return.gd's and
## test_apollo_16_entry.gd's.
extends SimTest

const LB := 0.45359237


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## Slice 12c: the J mission's vehicles, Casper and Orion as they flew.
func test_apollo_16_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_16"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 16 carries Orion")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack at the S-IVB's second ignition (MPR-SAT-FE-72-1, Table
	# 16-9), the CSM at transposition and docking, the CM after CM/SM SEP,
	# Orion at its separation, lunar lift-off and landing (MSC-07230, Table
	# A-IV) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 139139.0, 1.0, "139,139 kg at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 66923.0 * LB, 1.0, "66,923 lb at docking")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 13026.0 * LB, 1.0, "13,026 lb after CM/SM SEP")
	assert_almost_eq(SpacecraftData.lm_mass(), 36743.0 * LB, 1.0, "Orion, 36,743 lb at its separation")
	assert_almost_eq(float(SpacecraftData.section("dps")["propellant_kg"]) / LB, 19559.3, 0.5, "the DPS's 19,559.3 lb")
	var rcs := 561.4 * LB
	assert_almost_eq(SpacecraftData.lm_total_mass("lm_ascent", 0.0, f[1], rcs), 10949.0 * LB, 1.0,
		"10,949 lb at lift-off, a full ascent load with the RCS's 60 lb in it, and the RCS's 561.4 lb")
	assert_almost_eq(SpacecraftData.lm_total_mass("lm", 1128.0 * LB, f[1], rcs), 18208.0 * LB, 120.0 * LB,
		"18,208 lb on the surface, the descent engine's 1,128 lb left")
	assert_almost_eq(float(SpacecraftData.section("lm_eps")["battery_ah"]), 2617.0, 1e-6, "the descent stage's batteries and two ascent")
	assert_almost_eq(float(SpacecraftData.section("ascent_guidance")["insertion_hdot_mps"]) / Units.FT, 32.0, 0.01,
		"insertion climbing at the PAD's 32.0 ft/s")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


## Slice 12c: Apollo 16's books. Casper's first circularization is held
## and the landing waved off; it separates again and circularizes, and
## Orion's direct rendezvous starts with the tweak; each of Orion's steps
## checks itself off.
func test_apollo_16_has_its_own_checklists_for_the_wave_off() -> void:
	var csm := ChecklistBook.load_default("apollo_16")
	assert_eq(_flight_titles(csm), ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Orion's landing and TEI", "Entry", "IMU realign (P52)"])
	var lm := ChecklistBook.load_lm("apollo_16")
	var lm_for := {"lunar_orbit": "Undocking and the P52 after it", "lunar_descent": "Powered descent (P63 to P68)",
		"lunar_surface": "Lunar surface and liftoff (P12)",
		"lunar_ascent": "Direct rendezvous and docking (P41, P20, P34 and P42, P35)"}
	assert_eq(lm.lists.size(), 9, "Orion's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Orion's for %s" % phase)
	var timeline: Array = Mission.load_file(Mission.path_of("apollo_16")).section("timeline")["entries"]
	var events := []
	for book in [csm, lm]:
		for c in book.lists:
			for step in c.steps:
				for other in ["Eagle", "Columbia", "Intrepid", "Yankee Clipper", "Antares", "Kitty Hawk", "Falcon", "Endeavour"]:
					assert_false(str(step["text"]).contains(other), "%s: Apollo 16's" % c.title)
				if book == lm and c in _flight_lists(lm):
					assert_true(step.has("check"), "%s: \"%s\" has a check" % [c.title, step["text"]])
					assert_false(str(step["text"]).contains("P32") or str(step["text"]).contains("P33"), "%s: no CSI or CDH" % c.title)
				var ch := str(step.get("check", {}).get("channel", ""))
				if ch.begins_with("mission.event.timeline_"):
					events.append(ch.trim_prefix("mission.event.timeline_"))
					assert_true(timeline.any(func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
						"%s: %s is on the timeline" % [c.title, ch])
	for id in ["wave_off", "sep_pad2", "circ_pad2"]:
		assert_has(events, id, "the checklists follow the wave-off: %s" % id)
	Mission.load_default()


## Slice 12c: the wave-off. Apollo 16's timeline holds Casper's first
## CIRC PAD ("flown": false) and waves the landing off three of Orion's
## revolutions ("wave_off_revs"): the plan's PDI and landing move that
## much later, and the waved-off PDI PAD is no longer to be flown; the
## next PDI PAD finds rev 16's own PDI.
func test_the_wave_off_moves_pdi_and_the_landing_three_revolutions_on() -> void:
	var m := Mission.load_file(Mission.path_of("apollo_16"))
	var held: Array = m.section("timeline")["entries"].filter(func(e: Dictionary) -> bool: return not bool(e.get("flown", true)))
	assert_eq(held.map(func(e: Dictionary) -> String: return str(e["id"])), ["circ_pad"], "the first CIRC held")
	build("lunar_orbit", "apollo_16")
	var sq := rt.sequencer
	run(MissionSequencer._get_s("96:13:33") - SimClock.get_seconds)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_true(run_until(func() -> bool: return sq.pads.has("pdi"), 3600.0, 60.0), "the PDI PAD for rev 13")
	var pdi13 := float(sq.plan["pdi_tig"])
	var land13 := float(sq.plan["land_get"])
	assert_almost_eq(pdi13, MissionSequencer._get_s("98:35:04.68"), 240.0, "PDI planned for rev 13")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("wave_off"), 3.0 * 3600.0, 60.0), "the wave-off")
	var period := float(rt.dynamics.lm.traj.conic()["period"])
	assert_almost_eq(float(sq.plan["pdi_tig"]) - pdi13, 3.0 * period, 60.0, "PDI three revolutions on")
	assert_almost_eq(float(sq.plan["land_get"]) - land13, 3.0 * period, 60.0, "and the landing")
	assert_false(sq.pads.has("pdi"), "the waved-off PDI PAD gone")
	assert_false(sq.plan.has("pdi_pad_tig"), "nor held as pending")
	assert_true(run_until(func() -> bool: return sq.pads.has("pdi"), 5.0 * 3600.0, 60.0), "the PDI PAD for rev 16")
	assert_almost_eq(float(sq.pads["pdi"]["tig"]), MissionSequencer._get_s("104:17:23.29"), 240.0, "rev 16's own PDI")
	Mission.load_default()


## Slice 12c: Apollo 16's LM start phases begin on the descent orbit
## Casper's DOI left: Orion undocks on it at 96:13:33, Casper's first CIRC
## is held, the landing waves off, and Casper circularizes on the way, at
## the flown burn's place in its orbit near the second CIRC PAD's 103:21:42
## TIG; PDI is on rev 16, six hours after the one the start planned.
func test_apollo_16s_lunar_descent_starts_after_the_wave_off() -> void:
	build("lunar_descent", "apollo_16")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_descent", "Orion on the descent orbit")
	var lm := rt.dynamics.lm
	assert_not_null(lm, "undocked")
	assert_true(sq.timeline_done.has("wave_off"), "waved off on the way")
	var r := sq.landing_site().length()
	var c := lm.traj.conic()
	assert_almost_eq((float(c["ra"]) - r) / Units.NMI, 58.5, 3.0, "Orion's orbit: the high point where DOI was")
	assert_between((float(c["rp"]) - r) / Units.NMI, 6.0, 15.0, "and the low point about 11 nmi up")
	var k := rt.dynamics.traj.conic()
	assert_almost_eq((float(k["rp"]) - r) / Units.NMI, 53.1, 2.0, "Casper circularized")
	assert_almost_eq(float(sq.pads["circ"]["tig"]), MissionSequencer._get_s("103:21:42.43"), 300.0, "near the second CIRC PAD's TIG")
	assert_true(sq.pads.has("pdi"), "the PDI PAD")
	assert_almost_eq(float(sq.plan["pdi_tig"]), MissionSequencer._get_s("104:17:25"), 300.0, "PDI on rev 16")
	assert_ne(rt.lgc().landing_site, Vector3.ZERO, "the landing site in the LGC")
	assert_between(float(sq.plan["pdi_tig"]) - SimClock.get_seconds, 900.0, 1500.0, "about 20 min before PDI")
	Mission.load_default()


## Slice 12c: Apollo 16's lunar_ascent start: Casper's plane change over
## Orion, and the ascent PAD for the direct rendezvous, the liftoff timed
## for TPI 47 min after the insertion, TPI's TIG uplinked with it (N37).
func test_apollo_16s_lunar_ascent_starts_for_the_direct_rendezvous() -> void:
	build("lunar_ascent", "apollo_16")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_surface")
	assert_true(sq.pads.has("plane") and sq.pads.has("ascent"), "the plane change's PAD and the ascent's")
	var asc: Dictionary = sq.pads["ascent"]
	var tig := float(sq.plan["liftoff_tig"])
	assert_almost_eq(tig, MissionSequencer._get_s("175:31:47.18"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(float(sq.plan["tpi_tig"]) - float(asc["insertion_get"]), 2828.4, 1e-6, "TPI 47 min 8 s after the insertion")
	assert_eq(rt.lgc().rdv_tpi_tig, float(sq.plan["tpi_tig"]), "TPI's TIG in the LGC")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.5, "LOPC-1 put the plane over Orion")
	assert_between(float(asc["phase_deg"]), 3.0, 15.0, "Casper a few degrees ahead at the insertion")
	Mission.load_default()


## Slice 12c: Apollo 16's TEI start, a day early: Casper alone a minute
## before the TEI PAD, in the orbit its second CIRC left, 68.0 by 53.1 nmi
## [simplified: the plane change, which left 64.6 by 55.0, isn't flown],
## with no shaping burn (MSC-07230, Table 3-V(b)).
func test_apollo_16s_tei_starts_a_day_early() -> void:
	build("tei", "apollo_16")
	var sq := rt.sequencer
	assert_eq(rt.dynamics.config, "csm", "Casper alone")
	assert_almost_eq(SimClock.get_seconds, MissionSequencer._get_s("199:05:00") - 60.0, 1.0, "a minute before the TEI PAD")
	var r := sq.landing_site().length()
	var c := rt.dynamics.traj.conic()
	assert_between((float(c["ra"]) - r) / Units.NMI, 62.0, 75.0, "the orbit after the circularization, four days in the Moon's field on")
	assert_between((float(c["rp"]) - r) / Units.NMI, 45.0, 58.0, "and its perilune")
	Mission.load_default()


## The checklists of [param book] that aren't malfunction procedures.
func _flight_lists(book: ChecklistBook) -> Array:
	return book.lists.filter(func(c: Checklist) -> bool: return not c.title.begins_with("Malfunction: "))


## The titles of [param book]'s flight checklists.
func _flight_titles(book: ChecklistBook) -> Array:
	return book.lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return not t.begins_with("Malfunction: "))

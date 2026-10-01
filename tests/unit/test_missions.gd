## Slice 7a (docs/ROADMAP.md, milestone 7): each mission is data under
## data/missions/<id>/, not a code branch: its dates and ephemeris, its
## vehicles, Mission Control's timeline, the crew's call signs and
## checklists. Apollo 8 carries no LM: the S-IVB's adapter holds a test
## article, and the CSM flies alone. Its flight from the parking orbit to
## the splashdown is tests/scenarios/test_apollo_8.gd's. Apollo 10's LM
## (slice 7b) flies down to 8 nmi without landing, stages in orbit and
## flies the rendezvous: tests/scenarios/test_apollo_10.gd. Apollo 12's
## (slice 7c) lands beside Surveyor III: tests/scenarios/test_apollo_12.gd.
## Apollo 13's (slice 7d) is the lifeboat that brings its crew home after
## the SM's oxygen tank failed: tests/scenarios/test_apollo_13.gd. Apollo
## 14's CSM (slice 12a) flies DOI with the LM docked, and its LM lands at
## Fra Mauro and flies the direct rendezvous: tests/scenarios/
## test_apollo_14.gd and test_apollo_14_return.gd. Apollo 15's (slice 12b),
## the J mission's, stays three days at Hadley: tests/scenarios/
## test_apollo_15.gd, test_apollo_15_return.gd and test_apollo_15_entry.gd.
extends SimTest

const LB := 0.45359237


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


func test_the_missions_are_apollo_8_and_10_to_15() -> void:
	var ids := Mission.ids()
	assert_true("apollo_11" in ids, "Apollo 11")
	assert_true("apollo_10" in ids, "Apollo 10")
	assert_true("apollo_8" in ids, "Apollo 8")
	assert_true("apollo_12" in ids, "Apollo 12")
	assert_true("apollo_13" in ids, "Apollo 13")
	assert_true("apollo_14" in ids, "Apollo 14")
	assert_true("apollo_15" in ids, "Apollo 15")
	for id in ids:
		var m := Mission.load_file(Mission.path_of(id))
		assert_eq(m.id(), id, "%s's file names it" % id)
		assert_false(m.data.get("start_phases", []).is_empty(), "%s: its start phases" % id)
		for p in m.data.get("start_phases", []):
			assert_true(p in MissionSequencer.PHASES or p in MissionSequencer.START_ONLY, "%s: %s is a phase" % [id, p])
			assert_true(SpacecraftData.carries_lm() or not p in MissionSequencer.LM_PHASES, "%s: %s needs an LM" % [id, p])


func test_a_mission_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_8"))
	assert_false(SpacecraftData.carries_lm(), "Apollo 8 carries a test article")
	assert_eq(SpacecraftData.payload_mass(), 10820.0, "LTA-B, with the adapter")
	assert_eq(float(SpacecraftData.section("sps")["propellant_kg"]), 18523.0, "its own SPS load")
	assert_eq(float(SpacecraftData.section("sps")["thrust_n"]), 91190.0, "on Apollo 11's engine")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	# The stack at the S-IVB's second ignition (MPR-SAT-FE-69-1, section 7),
	# the CSM at its separation and the CM after CM/SM SEP (MSC-PA-R-69-1,
	# Table A.6-I) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 126867.0, 1.0, "126,867 kg at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 63524.0 * LB, 1.0, "63,524 lb at separation")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 12179.0 * LB, 1.0, "12,179 lb for the entry")
	Mission.load_default()
	assert_true(SpacecraftData.carries_lm(), "Apollo 11 carries Eagle")
	assert_eq(float(SpacecraftData.section("sps")["propellant_kg"]), 18413.0, "and the file's figures again")
	assert_eq(SpacecraftData.payload_mass(), SpacecraftData.lm_mass())


func test_apollo_10_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_10"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 10 carries Snoopy")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack at the S-IVB's second ignition (the S-IVB-505N flight
	# evaluation report, Table 8-1), the CSM before transposition and
	# docking, the CM after CM/SM SEP and the LM at its separation
	# (MSC-00126, Table A.4-I) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 292191.0 * LB, 1.0, "292,191 lb at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 63560.0 * LB, 1.0, "63,560 lb before docking")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 12138.0 * LB, 1.0, "12,138 lb for the entry")
	assert_almost_eq(SpacecraftData.lm_mass(), 31166.0 * LB, 1.0, "Snoopy, 31,166 lb at its separation")
	assert_almost_eq(f[1], 2631.0 * LB, 0.1, "its ascent engine's half load, 2,631 lb")
	assert_almost_eq(float(SpacecraftData.section("aps")["thrust_n"]) / Units.LBF, 3232.0, 1.0, "its thrust in the insertion")
	assert_eq(float(SpacecraftData.section("dps")["p40_throttle"]), 0.4, "the descent engine's P40 Apollo 11's")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


func test_apollo_12_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_12"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 12 carries Intrepid")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack at the S-IVB's second ignition (MPR-SAT-FE-70-1, Table
	# 17-10), the CSM at transposition and docking, the CM after CM/SM SEP,
	# Intrepid at its separation, lunar lift-off and landing (MSC-01855,
	# Table A-I) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 134986.0, 1.0, "134,986 kg at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 63535.6 * LB, 1.0, "63,535.6 lb at docking")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 12283.5 * LB, 1.0, "12,283.5 lb for the entry")
	assert_almost_eq(SpacecraftData.lm_mass(), 33985.5 * LB, 1.0, "Intrepid, 33,985.5 lb at its separation")
	var rcs := 459.0 * LB
	assert_almost_eq(SpacecraftData.lm_total_mass("lm_ascent", 0.0, f[1], rcs), 10749.6 * LB, 1.0,
		"10,749.6 lb at lift-off, a full ascent load and the RCS's 459 lb")
	assert_almost_eq(SpacecraftData.lm_total_mass("lm", 1175.0 * LB, f[1], rcs), 16564.2 * LB, 10.0 * LB,
		"16,564.2 lb on the surface, the descent engine's 1,175 lb left")
	assert_almost_eq(float(SpacecraftData.section("ascent_guidance")["insertion_hdot_mps"]) / Units.FT, 37.0, 0.01,
		"insertion climbing at the PAD's 37 ft/s")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


func test_apollo_13_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_13"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 13 carries Aquarius")
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack after the oxygen tank incident with the SPS's 40,529.7 lb
	# left, Aquarius at the docking, the CM after LM JETT (MSC-02680, Table
	# A-I and section 7) [published].
	assert_almost_eq(SpacecraftData.total_mass("csm_lm", 40529.7 * LB, sm, cm, 0.0), 96038.7 * LB, 1.0,
		"96,038.7 lb from the incident")
	assert_almost_eq(SpacecraftData.lm_mass(), 33499.1 * LB, 1.0, "Aquarius, 33,499.1 lb")
	assert_almost_eq(SpacecraftData.total_mass("cm", 0.0, 0.0, cm, 0.0), 12367.6 * LB, 1.0, "12,367.6 lb for the entry")
	assert_almost_eq(f[0], 18434.5 * LB, 0.1, "the descent engine's 18,434.5 lb")
	assert_eq(float(SpacecraftData.section("lm_eps")["battery_ah"]), 2179.0, "the LM's batteries, 2,179 A-h")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


func test_apollo_14_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_14"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 14 carries Antares")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	# The stack at the S-IVB's second ignition (MPR-SAT-FE-71-1, Table
	# 16-9), the CSM at transposition and docking, the CM after CM/SM SEP,
	# Antares at its separation, lunar lift-off and landing (MSC-04112,
	# Table A-II) [published].
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 136121.0, 1.0, "136,121 kg at TLI's ignition")
	assert_almost_eq(SpacecraftData.total_mass("csm", sps, sm, cm, 0.0), 64388.0 * LB, 1.0, "64,388.0 lb at docking")
	assert_almost_eq(SpacecraftData.total_mass("cm", sps, sm, cm, 0.0), 12715.1 * LB, 1.0, "12,715.1 lb for the entry")
	assert_almost_eq(SpacecraftData.lm_mass(), 34125.9 * LB, 1.0, "Antares, 34,125.9 lb at its separation")
	var rcs := 479.5 * LB
	assert_almost_eq(SpacecraftData.lm_total_mass("lm_ascent", 0.0, f[1], rcs), 10779.8 * LB, 1.0,
		"10,779.8 lb at lift-off, a full ascent load and the RCS's 479.5 lb")
	assert_almost_eq(SpacecraftData.lm_total_mass("lm", 794.0 * LB, f[1], rcs), 16371.7 * LB, 30.0 * LB,
		"16,371.7 lb on the surface, the descent engine's 794 lb left")
	assert_almost_eq(float(SpacecraftData.section("ascent_guidance")["insertion_hdot_mps"]) / Units.FT, 31.3, 0.01,
		"insertion climbing at the PAD's 31.3 ft/s")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


func test_capcom_calls_each_vehicle_by_its_call_sign() -> void:
	var a8 := Mission.load_file(Mission.path_of("apollo_8"))
	assert_eq(a8.words("{csm}, Houston. Welcome home, {mission}."), "Apollo 8, Houston. Welcome home, Apollo 8.")
	var a10 := Mission.load_file(Mission.path_of("apollo_10"))
	assert_eq(a10.words("{csm} and {lm} are docked. Welcome home, {mission}."),
		"Charlie Brown and Snoopy are docked. Welcome home, Apollo 10.")
	var a12 := Mission.load_file(Mission.path_of("apollo_12"))
	assert_eq(a12.words("{csm} and {lm} are docked. {lm_landed}, Houston."),
		"Yankee Clipper and Intrepid are docked. Intrepid, Houston.")
	var a13 := Mission.load_file(Mission.path_of("apollo_13"))
	assert_eq(a13.words("{csm} and {lm} are docked. Welcome home, {mission}."),
		"Odyssey and Aquarius are docked. Welcome home, Apollo 13.")
	var a14 := Mission.load_file(Mission.path_of("apollo_14"))
	assert_eq(a14.words("{csm} and {lm} are docked. {lm_landed}, Houston."),
		"Kitty Hawk and Antares are docked. Antares, Houston.")
	var a15 := Mission.load_file(Mission.path_of("apollo_15"))
	assert_eq(a15.words("{csm} and {lm} are docked. {lm_landed}, Houston."),
		"Endeavour and Falcon are docked. Falcon, Houston.")
	var a11 := Mission.load_default()
	assert_eq(a11.words("{csm} and {lm} are docked. {lm_landed}, Houston."),
		"Columbia and Eagle are docked. Tranquility Base, Houston.")
	assert_eq(a11.words("Liftoff at {liftoff}.", {"liftoff": "124:22:00"}), "Liftoff at 124:22:00.")


func test_every_timeline_entry_is_one_mission_control_can_make() -> void:
	for id in Mission.ids():
		var m := Mission.load_file(Mission.path_of(id))
		var entries: Array = m.section("timeline").get("entries", [])
		assert_false(entries.is_empty(), "%s has a timeline" % id)
		var seen := {}
		for e: Dictionary in entries:
			var what := "%s %s" % [id, e.get("id", "?")]
			assert_false(seen.has(e["id"]), "%s: once" % what)
			seen[e["id"]] = true
			assert_true(e.has("get") or e.has("after") or e.has("before"), "%s: its time" % what)
			var when := str(e.get("when", ""))
			assert_true(when in MissionSequencer.PHASES or when in MissionSequencer.CONDITIONS, "%s: when %s" % [what, when])
			assert_true(e.has("say") or e.has("pad") or e.has("fail") or e.has("cabin"),
				"%s: a call, a PAD, a failure or the cabin's pressure" % what)
			if e.has("cabin"):
				assert_true(str(e["cabin"]) in ["vented", "pressurized"], "%s: the cabin %s" % [what, e["cabin"]])
			if e.has("fail"):
				assert_false(Failures.entry(str(e["fail"])).is_empty(), "%s: fails %s, in the catalog" % [what, e["fail"]])
			if e.has("pad"):
				assert_true(str(e["pad"]) in MissionSequencer.PAD_KINDS, "%s: pad %s" % [what, e["pad"]])
			if e.has("n81_ft_s"):
				assert_true((e.has("tig") or e.has("tig_after")) and (e["n81_ft_s"] as Array).size() == 3,
					"%s: a fixed maneuver's TIG and N81" % what)
				assert_true(str(e.get("engine", "dps")) in ["dps", "aps"], "%s: the LM's engine" % what)
				assert_true((e.get("throttle", [0, 0, 0]) as Array).size() == 3, "%s: a throttle schedule of three" % what)
			if e.has("tig_after"):
				assert_true(e.has("tig_s"), "%s: how long after %s" % [what, e["tig_after"]])
			if e.has("say"):
				assert_false(m.words(str(e["say"])).contains("{"), "%s: every call sign known" % what)
		for sid in m.section("tli").get("aim_after", []):
			assert_true(seen.has(sid), "%s: TLI aims after %s, on the timeline" % [id, sid])
		var calls := m.section("start_calls")
		for phase: String in calls:
			if not phase.begins_with("_"):
				assert_true(phase in m.data["start_phases"] or phase == "launch", "%s: a call for %s, a start phase" % [id, phase])
				assert_false(m.words(str(calls[phase]), {"ascent_pad": "", "liftoff": ""}).contains("{"), "%s: %s" % [id, phase])


func test_apollo_8_has_its_own_checklists_and_no_lms() -> void:
	var csm := ChecklistBook.load_default("apollo_8")
	var titles := _flight_titles(csm)
	assert_eq(titles, ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)", "Lunar orbit and TEI",
		"Entry", "IMU realign (P52)"])
	for phase in ["launch", "parking_orbit", "translunar_coast", "lunar_orbit", "transearth_coast", "entry"]:
		csm.select_for_phase(phase)
		assert_true(csm.list().phases.has(phase), "one for %s" % phase)
	assert_true(ChecklistBook.load_lm("apollo_8").lists.is_empty(), "no LM, no LM checklists")
	var lm := RegEx.create_from_string("\\bLM\\b")
	for c in csm.lists:
		for s in c.steps:
			assert_null(lm.search(str(s["text"])), "%s: \"%s\" without an LM" % [c.title, s["text"]])


func test_apollo_10_has_its_own_checklists_for_a_flight_without_a_landing() -> void:
	var csm := ChecklistBook.load_default("apollo_10")
	var titles := _flight_titles(csm)
	assert_eq(titles, ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Snoopy's flight and TEI", "Entry", "IMU realign (P52)"])
	for phase in ["launch", "parking_orbit", "translunar_coast", "lunar_orbit", "lunar_descent", "lunar_ascent", "transearth_coast",
			"entry"]:
		csm.select_for_phase(phase)
		assert_true(csm.list().phases.has(phase), "Charlie Brown's for %s" % phase)
	var lm := ChecklistBook.load_lm("apollo_10")
	var lm_for := {"lunar_orbit": "Undocking and DOI (P30 / P40)", "lunar_descent": "The low pass, phasing and staging (P30 / P40)",
		"lunar_ascent": "Insertion and rendezvous (P42, P20, P32 to P35)"}
	assert_eq(lm.lists.size(), 8, "Snoopy's three, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Snoopy's for %s" % phase)
	for c in _flight_lists(lm):
		for step in c.steps:
			assert_true(step.has("check"), "%s: \"%s\" has a check" % [c.title, step["text"]])
			assert_false(str(step["text"]).contains("Eagle") or str(step["text"]).contains("Columbia"), "%s: Apollo 10's" % c.title)
			var ch := str(step["check"]["channel"])
			if ch.begins_with("mission.event.timeline_"):
				assert_true(Mission.load_file(Mission.path_of("apollo_10")).section("timeline")["entries"].any(
					func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
					"%s: %s is on the timeline" % [c.title, ch])
	Mission.load_default()


func test_apollo_12_has_its_own_checklists_with_the_landing_site_update() -> void:
	var csm := ChecklistBook.load_default("apollo_12")
	var titles := _flight_titles(csm)
	assert_eq(titles, ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Intrepid's landing and TEI", "Entry", "IMU realign (P52)"])
	for phase in ["launch", "parking_orbit", "translunar_coast", "lunar_orbit", "lunar_descent", "lunar_surface", "lunar_ascent",
			"transearth_coast", "entry"]:
		csm.select_for_phase(phase)
		assert_true(csm.list().phases.has(phase), "Yankee Clipper's for %s" % phase)
	var lm := ChecklistBook.load_lm("apollo_12")
	var lm_for := {"lunar_orbit": "Undocking and DOI (P30 / P40)", "lunar_descent": "Powered descent (P63 to P68)",
		"lunar_surface": "Lunar surface and liftoff (P12)", "lunar_ascent": "Rendezvous and docking (P20, P32 to P35)"}
	assert_eq(lm.lists.size(), 9, "Intrepid's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Intrepid's for %s" % phase)
	var timeline: Array = Mission.load_file(Mission.path_of("apollo_12")).section("timeline")["entries"]
	var n69 := 0
	for book in [csm, lm]:
		for c in book.lists:
			for step in c.steps:
				assert_false(str(step["text"]).contains("Eagle") or str(step["text"]).contains("Columbia"), "%s: Apollo 12's" % c.title)
				var ch := str(step.get("check", {}).get("channel", ""))
				if ch == "lm.guid.ls_corrected":
					n69 += 1
				if ch.begins_with("mission.event.timeline_"):
					assert_true(timeline.any(func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
						"%s: %s is on the timeline" % [c.title, ch])
	assert_eq(n69, 1, "the powered descent's noun 69")
	Mission.load_default()


## Slice 7d: Apollo 13's books open for the tank_failure start on the
## failure and Aquarius's activation (scenes/main.gd), and every step of
## Aquarius's checks itself off.
func test_apollo_13_has_its_own_checklists_for_the_lifeboat() -> void:
	var csm := ChecklistBook.load_default("apollo_13")
	var titles := _flight_titles(csm)
	assert_eq(titles, ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"The oxygen tank failure and the lifeboat", "The CM's power-up and entry", "IMU realign (P52)"])
	var csm_for := {"launch": "Launch", "parking_orbit": "Parking orbit and TLI", "translunar_coast": "SPS burn (P30 / P40)",
		"tank_failure": "The oxygen tank failure and the lifeboat", "transearth_coast": "The CM's power-up and entry",
		"entry": "The CM's power-up and entry"}
	for phase in csm_for:
		csm.select_for_phase(phase)
		assert_eq(csm.list().title, csm_for[phase], "Odyssey's for %s" % phase)
	var lm := ChecklistBook.load_lm("apollo_13")
	var lm_for := {"tank_failure": "Activation and the docked alignment",
		"translunar_coast": "Activation and the docked alignment", "transearth_coast": "Transearth: MCC-5 on the AGS"}
	assert_eq(lm.lists.size(), 9, "Aquarius's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Aquarius's for %s" % phase)
	var timeline: Array = Mission.load_file(Mission.path_of("apollo_13")).section("timeline")["entries"]
	for book in [csm, lm]:
		for c in book.lists:
			for step in c.steps:
				for other in ["Eagle", "Columbia", "Intrepid", "Yankee Clipper"]:
					assert_false(str(step["text"]).contains(other), "%s: Apollo 13's" % c.title)
				if book == lm and c in _flight_lists(lm):
					assert_true(step.has("check"), "%s: \"%s\" has a check" % [c.title, step["text"]])
				var ch := str(step.get("check", {}).get("channel", ""))
				if ch.begins_with("mission.event.timeline_"):
					assert_true(timeline.any(func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
						"%s: %s is on the timeline" % [c.title, ch])
	Mission.load_default()


## Slice 12a: Apollo 14's books. Kitty Hawk flies DOI with Antares docked
## and circularizes after the undocking; Antares's rendezvous is the direct
## one, the tweak after insertion and TPI on the ascent engine, with no CSI
## or CDH, and each of its steps checks itself off.
func test_apollo_14_has_its_own_checklists_for_the_direct_rendezvous() -> void:
	var csm := ChecklistBook.load_default("apollo_14")
	var titles := _flight_titles(csm)
	assert_eq(titles, ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Antares's landing and TEI", "Entry", "IMU realign (P52)"])
	for phase in ["launch", "parking_orbit", "translunar_coast", "lunar_orbit", "lunar_descent", "lunar_surface", "lunar_ascent",
			"transearth_coast", "entry"]:
		csm.select_for_phase(phase)
		assert_true(csm.list().phases.has(phase), "Kitty Hawk's for %s" % phase)
	var lm := ChecklistBook.load_lm("apollo_14")
	var lm_for := {"lunar_orbit": "Undocking and the P52 after it", "lunar_descent": "Powered descent (P63 to P68)",
		"lunar_surface": "Lunar surface and liftoff (P12)",
		"lunar_ascent": "Direct rendezvous and docking (P41, P20, P34 and P42, P35)"}
	assert_eq(lm.lists.size(), 9, "Antares's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Antares's for %s" % phase)
	var timeline: Array = Mission.load_file(Mission.path_of("apollo_14")).section("timeline")["entries"]
	var programs := []
	for book in [csm, lm]:
		for c in book.lists:
			for step in c.steps:
				for other in ["Eagle", "Columbia", "Intrepid", "Yankee Clipper"]:
					assert_false(str(step["text"]).contains(other), "%s: Apollo 14's" % c.title)
				if book == lm and c in _flight_lists(lm):
					assert_true(step.has("check"), "%s: \"%s\" has a check" % [c.title, step["text"]])
					assert_false(str(step["text"]).contains("P32") or str(step["text"]).contains("P33"), "%s: no CSI or CDH" % c.title)
				var ch := str(step.get("check", {}).get("channel", ""))
				if ch == "lm.guid.program":
					programs.append(int(step["check"]["value"]))
				if ch.begins_with("mission.event.timeline_"):
					assert_true(timeline.any(func(e: Dictionary) -> bool: return "timeline_" + str(e["id"]) == ch.trim_prefix("mission.event.")),
						"%s: %s is on the timeline" % [c.title, ch])
	assert_has(programs, 42, "TPI on the ascent engine")
	Mission.load_default()


## Slice 7c: Apollo 12's PDI PAD comes half an hour before PDI, before the
## lunar_descent start, whose LGC keeps the state vector it brought: off by
## 4,400 ft along the track and 145 m high at PDI (mission.json "pdi").
func test_apollo_12s_lunar_descent_keeps_the_pdi_pads_state_vector() -> void:
	build("lunar_descent", "apollo_12")
	var sq := rt.sequencer
	assert_true(sq.pads.has("pdi"), "the PDI PAD before the start")
	var lgc := rt.lgc()
	run(float(sq.plan["pdi_tig"]) - SimClock.get_seconds)
	var t := rt.dynamics.lm.traj
	var err := Trajectory.lvlh_basis(t.pos(), t.vel()).inverse() * (lgc.nav.pos() - t.pos())
	var e: Array = sq.mission.section("pdi")["state_error_lvlh_m"]
	assert_almost_eq(e[2], -145.0, 1e-6, "145 m high")
	assert_almost_eq(err, Vector3(e[0], e[1], e[2]), Vector3.ONE * 5.0, "the LGC's error at PDI")
	Mission.load_default()


## Slice 7c: the lunar_ascent start flies the CSM's plane change the
## timeline brings on the way (Apollo 12's first, 119:47): at the liftoff
## the RTCC times, Yankee Clipper's orbit passes over Intrepid.
func test_apollo_12s_lunar_ascent_starts_with_yankee_clipper_over_intrepid() -> void:
	build("lunar_ascent", "apollo_12")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_surface")
	assert_true(sq.pads.has("plane") and sq.pads.has("ascent"), "the plane change's PAD and the ascent's")
	assert_lt(float(Bus.get_value("sps.prop_kg")), float(SpacecraftData.section("sps")["propellant_kg"]) - 5000.0, "the SPS burned")
	var tr := rt.dynamics.traj.clone()
	var tig := float(sq.plan["liftoff_tig"])
	tr.coast_to(tig, 60.0)
	var off := tr.pos().cross(tr.vel()).normalized().dot(Bodies.moon_fixed(tig) * rt.dynamics.lm.landed_pos)
	gut.p("At the liftoff, %s, Intrepid is %.2f km from Yankee Clipper's plane" % [Units.hms(tig), off / 1000.0])
	assert_lt(absf(off), 1500.0, "over Intrepid for the liftoff")
	assert_almost_eq(tig, MissionSequencer._get_s("142:01:17.9"), 90.0, "the liftoff near the flight plan's")
	Mission.load_default()


func test_apollo_10s_lm_flies_the_grounds_fixed_burns_and_stages_in_orbit() -> void:
	build("lunar_descent", "apollo_10")
	var sq := rt.sequencer
	assert_eq(sq.phase, "lunar_descent", "Snoopy on the descent orbit")
	assert_true(run_until(func() -> bool: return sq.pads.has("phasing"), 1800.0, 60.0), "the phasing PAD")
	var ph: Dictionary = sq.pads["phasing"]
	assert_almost_eq(float(ph["tig"]) - float(sq.plan["pdi_tig"]), 879.7, 1e-6, "as long after the low point as the flight's")
	assert_eq(float(sq.plan["phasing_tig"]), float(ph["tig"]), "in the ground's plan")
	var lgc := rt.lgc()
	assert_true(lgc.dv_lvlh_load.is_equal_approx(Vector3(166.6, 0.0, -59.4) * Units.FT), "the PAD's N81 in the LGC's P30")
	assert_eq(lgc.p40_schedule, [26.0, 0.1, 1.0], "10 % for 26 s, then full: the PAD's throttle schedule")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Snoopy, uplinking your PHASING PAD")
	# The insertion PAD comes after the low point, its TIG timed from it.
	var ins_at := float(sq.plan["pdi_tig"]) + 1545.5
	run(ins_at + 1.0 - SimClock.get_seconds)
	var ins: Dictionary = sq.pads.get("insertion", {})
	assert_almost_eq(float(sq.timeline_done.get("insertion_pad", -1.0)), ins_at, 1.0, "the insertion PAD after the low point")
	assert_almost_eq(float(ins.get("tig", 0.0)) - float(sq.plan["pdi_tig"]), 7875.9, 1e-6, "its TIG")
	assert_eq(lgc.p40_schedule, [15.0, 0.1, 0.4], "no DPS schedule of its own")
	# Staged in orbit, the ascent stage flies: lunar_ascent, and its engine's
	# first burn, its cutoff with Snoopy in orbit, is the insertion.
	Bus.set_value("ctl.lm.stage", true)
	run(1.0, false)
	Bus.set_value("ctl.lm.stage", false)
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "staged")
	assert_eq(sq.phase, "lunar_ascent")
	assert_true(sq._has("lm_staging") and not sq._has("lm_insertion"), "no insertion before the ascent engine burns")
	Bus.set_value("ctl.lm.engine_arm", 1)
	Bus.set_value("ctl.lm.eng_start", true)
	run(2.0, false)
	Bus.set_value("ctl.lm.eng_start", false)
	Bus.set_value("ctl.lm.eng_stop", true)
	run(3.0, false)
	Bus.set_value("ctl.lm.eng_stop", false)
	Bus.set_value("ctl.lm.engine_arm", 0)
	assert_eq(int(Bus.get_value("lm.aps.ignitions")), 1, "the ascent engine burned")
	assert_true(sq._has("lm_insertion"), "the insertion")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Snoopy, you're in orbit")
	assert_false(sq._has("lm_liftoff") or sq._has("lm_landing"), "without a landing")


func test_without_an_lm_csm_lv_sep_leaves_the_csm_alone() -> void:
	build("", "apollo_8")
	var sq := rt.sequencer
	# The stack on its way after TLI, hand-set: the S-IVB done.
	rt.systems["sivb"].state = "done"
	rt.systems["sivb"].prop_kg = 0.0
	Bus.set_value("sivb.state", "done")
	Bus.set_value("sivb.prop_kg", 0.0)
	rt.dynamics.initialize("earth", 11000.0, Vector3(4.0e7, 0, 0), Vector3(0, 3000.0, 0), "stack")
	assert_false(rt.dynamics.has_lm(), "no LM in the adapter")
	var m0 := rt.dynamics.mass
	Bus.set_value("ctl.seq.csm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.csm_sep", false)
	assert_eq(rt.dynamics.config, "csm", "the CSM on its own")
	assert_true(sq._has("csm_lv_sep"), "CSM/LV SEP")
	assert_false(sq._has("transposition_docking"), "and nothing to dock with")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Apollo 8, you're on your own")
	assert_almost_eq(m0 - rt.dynamics.mass, 10820.0 + 14506.0, 1.0, "the test article and the S-IVB left behind")
	assert_eq(Bus.get_value("dock.state"), "none")


func test_an_apollo_8_checkpoint_keeps_its_mission() -> void:
	build("lunar_orbit", "apollo_8")
	run(600.0)
	var snap := rt.snapshot()
	assert_eq(snap["mission_id"], "apollo_8")
	assert_eq(snap["vehicles"].keys(), ["csm"], "no LM")
	assert_false(snap["vehicles"]["csm"]["systems"].has("lgc"), "nor its systems")
	var text := JSON.stringify(snap)
	var pos := rt.dynamics.traj.pos()
	build("", "apollo_8")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_lt((rt.dynamics.traj.pos() - pos).length(), 1.0, "where it was")
	assert_eq(rt.sequencer.phase, "lunar_orbit")
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "checkpoint is for mission 'apollo_8'", "not Apollo 11's")


## [param book]'s flight checklists: the malfunction procedures after
## them are every mission's (test_failures.gd).
func _flight_lists(book: ChecklistBook) -> Array:
	return book.lists.filter(func(c: Checklist) -> bool: return not c.title.begins_with("Malfunction: "))


## The titles of [param book]'s flight checklists.
func _flight_titles(book: ChecklistBook) -> Array:
	return book.lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return not t.begins_with("Malfunction: "))

## Slice 7a (docs/ROADMAP.md, milestone 7): each mission is data under
## data/missions/<id>/, not a code branch: its dates and ephemeris, its
## vehicles, Mission Control's timeline, the crew's call signs and
## checklists. Apollo 8 carries no LM: the S-IVB's adapter holds a test
## article, and the CSM flies alone. Its flight from the parking orbit to
## the splashdown is tests/scenarios/test_apollo_8.gd's.
extends SimTest

const LB := 0.45359237


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


func test_the_missions_are_apollo_8_and_apollo_11() -> void:
	var ids := Mission.ids()
	assert_true("apollo_11" in ids, "Apollo 11")
	assert_true("apollo_8" in ids, "Apollo 8")
	for id in ids:
		var m := Mission.load_file(Mission.path_of(id))
		assert_eq(m.id(), id, "%s's file names it" % id)
		assert_false(m.data.get("start_phases", []).is_empty(), "%s: its start phases" % id)
		for p in m.data.get("start_phases", []):
			assert_true(p in MissionSequencer.PHASES, "%s: %s is a phase" % [id, p])
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


func test_capcom_calls_each_vehicle_by_its_call_sign() -> void:
	var a8 := Mission.load_file(Mission.path_of("apollo_8"))
	assert_eq(a8.words("{csm}, Houston. Welcome home, {mission}."), "Apollo 8, Houston. Welcome home, Apollo 8.")
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
			assert_true(e.has("say") or e.has("pad"), "%s: a call or a PAD" % what)
			if e.has("pad"):
				assert_true(str(e["pad"]) in MissionSequencer.PAD_KINDS, "%s: pad %s" % [what, e["pad"]])
			if e.has("n81_ft_s"):
				assert_true(e.has("tig") and (e["n81_ft_s"] as Array).size() == 3, "%s: a fixed maneuver's TIG and N81" % what)
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
	var titles := csm.lists.map(func(c: Checklist) -> String: return c.title)
	assert_eq(titles, ["Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)", "Lunar orbit and TEI",
		"Entry", "IMU realign (P52)"])
	for phase in ["parking_orbit", "translunar_coast", "lunar_orbit", "transearth_coast", "entry"]:
		csm.select_for_phase(phase)
		assert_true(csm.list().phases.has(phase), "one for %s" % phase)
	assert_true(ChecklistBook.load_lm("apollo_8").lists.is_empty(), "no LM, no LM checklists")
	var lm := RegEx.create_from_string("\\bLM\\b")
	for c in csm.lists:
		for s in c.steps:
			assert_null(lm.search(str(s["text"])), "%s: \"%s\" without an LM" % [c.title, s["text"]])


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

## Slice 12d (docs/ROADMAP.md, milestone 12): Apollo 17's data. Its
## vehicles and its books; its LM start phases, which begin on
## the descent orbit America's DOI left; its ascent PAD for the direct
## rendezvous; and its TEI start.
extends SimTest

const LB := 0.45359237


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## Slice 12d: the J mission's vehicles, America and Challenger as they flew.
func test_apollo_17_flies_its_own_vehicles() -> void:
	Mission.load_file(Mission.path_of("apollo_17"))
	assert_true(SpacecraftData.carries_lm(), "Apollo 17 carries Challenger")
	var sps := float(SpacecraftData.section("sps")["propellant_kg"])
	var sm := 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])
	var cm := 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])
	var sivb := float(SpacecraftData.section("sivb")["propellant_kg"])
	var f := SpacecraftData.lm_full_loads()
	assert_almost_eq(SpacecraftData.total_mass("stack", sps, sm, cm, sivb), 139235.0, 1000.0, "139,235 kg at TLI's ignition")
	assert_almost_eq(float(SpacecraftData.section("dps")["propellant_kg"]) / LB, 19566.0, 100.0, "the DPS load")
	assert_almost_eq(float(SpacecraftData.section("lm_eps")["battery_ah"]), 2667.0, 1e-6, "the descent stage's batteries and two ascent")
	Mission.load_default()
	assert_almost_eq(SpacecraftData.lm_mass(), 15103.0, 1.0, "and Eagle again")


func test_apollo_17_has_its_own_checklists() -> void:
	var csm := ChecklistBook.load_default("apollo_17")
	assert_eq(_flight_titles(csm), ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "RCS burn (P30 / P41)",
		"Lunar orbit, Challenger's landing and TEI", "Entry", "IMU realign (P52)"])
	var lm := ChecklistBook.load_lm("apollo_17")
	var lm_for := {"lunar_orbit": "Undocking and the P52 after it", "lunar_descent": "Powered descent (P63 to P68)",
		"lunar_surface": "Lunar surface and liftoff (P12)",
		"lunar_ascent": "Direct rendezvous and docking (P41, P20, P34 and P42, P35)"}
	assert_eq(lm.lists.size(), 9, "Challenger's four, and the LM's five malfunction procedures")
	for phase in lm_for:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, lm_for[phase], "Challenger's for %s" % phase)
	Mission.load_default()


## The checklists of [param book] that aren't malfunction procedures.
func _flight_lists(book: ChecklistBook) -> Array:
	return book.lists.filter(func(c: Checklist) -> bool: return not c.title.begins_with("Malfunction: "))


## The titles of [param book]'s flight checklists.
func _flight_titles(book: ChecklistBook) -> Array:
	return book.lists.map(func(c: Checklist) -> String: return c.title).filter(
		func(t: String) -> bool: return not t.begins_with("Malfunction: "))

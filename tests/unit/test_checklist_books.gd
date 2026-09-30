## Columbia's and Eagle's checklists (slice 3f): each vehicle's book opens
## the checklist its phases name, and the HUD shows the book of the
## vehicle flown, with both keeping up with the Bus.
extends SimTest

const CSM_FOR := {"launch": "Launch", "parking_orbit": "Parking orbit and TLI", "tli": "Parking orbit and TLI",
	"translunar_coast": "SPS burn (P30 / P40)", "lunar_orbit": "Lunar orbit and TEI",
	"lunar_descent": "Lunar orbit and TEI", "lunar_surface": "Lunar orbit and TEI",
	"lunar_ascent": "Lunar orbit and TEI", "transearth_coast": "Entry", "entry": "Entry"}
const LM_FOR := {"lunar_orbit": "Undocking and DOI (P30 / P40)", "lunar_descent": "Powered descent (P63 to P68)",
	"lunar_surface": "Lunar surface and liftoff (P12)", "lunar_ascent": "Rendezvous and docking (P20, P32 to P35)"}


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func test_each_book_opens_the_checklist_for_the_phase() -> void:
	var csm := ChecklistBook.load_default()
	var lm := ChecklistBook.load_lm()
	assert_eq(lm.lists.size(), 9, "Eagle's four, and the LM's five malfunction procedures")
	for phase in CSM_FOR:
		csm.select_for_phase(phase)
		assert_eq(csm.list().title, CSM_FOR[phase], "Columbia in %s" % phase)
	for phase in LM_FOR:
		lm.select_for_phase(phase)
		assert_eq(lm.list().title, LM_FOR[phase], "Eagle in %s" % phase)
	lm.select_for_phase("translunar_coast")
	assert_eq(lm.list().title, LM_FOR["lunar_ascent"], "no checklist for the phase: the open one stays")
	csm.select_for_phase("splashdown")
	assert_eq(csm.list().title, "Entry")


func test_every_lm_step_checks_itself_off() -> void:
	for c in ChecklistBook.load_lm().lists.filter(func(l: Checklist) -> bool: return not l.title.begins_with("Malfunction: ")):
		assert_false(c.phases.is_empty(), "%s: its phases" % c.title)
		for s in c.steps:
			assert_true(s.has("check"), "%s: \"%s\" has a check" % [c.title, s["text"]])


## The HUD's checklist choice's titles, the malfunction procedures left out
## (test_failures.gd).
func _titles(hud: Hud) -> Array:
	var out := []
	for i in hud._check_title.item_count:
		if not hud._check_title.get_item_text(i).begins_with("Malfunction: "):
			out.append(hud._check_title.get_item_text(i))
	return out


func test_the_hud_shows_the_checklists_of_the_vehicle_flown() -> void:
	build("lunar_descent")
	var csm := ChecklistBook.load_default()
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.setup(rt, csm)
	assert_eq(hud.csm_book, csm, "Columbia's, shared with the cabin")
	assert_eq(hud.book, csm)
	hud.set_vehicle("lm")
	assert_eq(hud.book, hud.lm_book, "Eagle's")
	assert_eq(_titles(hud), LM_FOR.values())
	hud.select_checklist_for("lunar_descent")
	assert_eq(hud._check_title.selected, 1)
	hud._process(0.0)
	assert_string_contains(hud._check_text.text, "▶[/color] Mission Control: the PDI PAD")
	# Back in Columbia, its checklists where they stood, and Eagle's go on.
	hud.set_vehicle("csm")
	assert_eq(hud.book, csm)
	assert_eq(_titles(hud), ["Launch", "Parking orbit and TLI", "SPS burn (P30 / P40)", "Lunar orbit and TEI", "Entry",
		"IMU realign (P52)"])
	assert_eq(hud._check_title.selected, 0)
	Bus.set_value("mission.event.pad_pdi", SimClock.get_seconds)
	hud._process(0.0)
	assert_eq(hud.lm_book.list().index, 1, "Eagle's checklist checked the PAD off, out of sight")
	hud._check_title.item_selected.emit(2)
	assert_eq(csm.list().title, "SPS burn (P30 / P40)", "the choice turns Columbia's book")
	assert_eq(hud.lm_book.current, 1, "not Eagle's")
	hud._process(0.0)
	assert_eq(csm.list().index, 1, "UP TLM CM is in ACCEPT: its step is checked off")
	var next: Button = hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Next")[0]
	next.pressed.emit()
	assert_eq(csm.list().index, 2, "Next acknowledges Columbia's step")
	hud.set_vehicle("lm")
	assert_eq(hud._check_title.selected, 1, "Eagle's checklist as it was left")
	hud._process(0.0)
	assert_string_contains(hud._check_text.text, "▶[/color] V37E 63E")

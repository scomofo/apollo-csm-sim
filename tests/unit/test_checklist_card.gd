## The checklists in the cabin (docs/ROADMAP.md, slice 2d): one
## ChecklistBook shared by the HUD and the cabin's card, the card showing
## the open checklist, the PAD and the CAPCOM log, and the highlight
## framing the control the current step is done on.
extends SimTest

var book: ChecklistBook


func before_each() -> void:
	Bus.reset()
	SimClock.reset()
	book = ChecklistBook.load_default()


func _cabin() -> CmCabin:
	var cabin := CmCabin.create()
	add_child_autofree(cabin)
	return cabin


func _card() -> ChecklistCard:
	var card := ChecklistCard.new()
	card.book = book
	add_child_autofree(card)
	return card


func _step_texts(card: ChecklistCard) -> PackedStringArray:
	var out := PackedStringArray()
	for l in card.step_labels:
		if l.visible:
			out.append(l.text)
	return out


func test_the_book_opens_by_phase_cycles_and_acknowledges() -> void:
	assert_eq(book.lists.size(), 11, "six for the flight, five malfunction procedures")
	book.select_for_phase("translunar_coast")
	assert_eq(book.list().title, "SPS burn (P30 / P40)")
	var w := book.window()
	assert_eq(w[0]["state"], "current")
	assert_false(w[0]["manual"], "UP TLM CM - ACCEPT has a check")
	assert_eq(book.target(), {"control": "P2_UP_TLM_CM", "channel": "ctl.cmc.up_tlm"})
	book.next()
	assert_eq(book.list().index, 0, "NEXT doesn't pass a checked step")
	Bus.set_value("ctl.cmc.up_tlm", true)
	assert_true(book.update(), "the check holds")
	w = book.window()
	assert_eq([w[0]["state"], w[1]["state"], w[2]["state"]], ["done", "current", "pending"])
	assert_true(w[1]["manual"], "requesting the PAD has no check")
	book.next()
	assert_eq(book.list().index, 2, "NEXT acknowledges a read-only step")
	book.next()
	assert_eq(book.list().index, 2, "but not a checked one")
	Bus.set_value("ctl.cmc.up_tlm", false)
	assert_true(book.update(), "UP TLM CM - BLOCK")
	assert_eq(book.target(), {"control": "P2_DSKY", "channel": "guid.program"})
	Bus.set_value("guid.program", 30)
	assert_true(book.update())
	assert_eq(book.list().index, 4)
	book.cycle()
	assert_eq(book.list().title, "Lunar orbit and TEI")
	assert_eq(book.list().index, 0, "a checklist opens where it stands, at first its first step")
	book.select(-1)
	assert_eq(book.list().title, "Malfunction: ISS", "select wraps, to the last malfunction procedure")
	book.select(2)
	assert_eq(book.list().index, 4, "back to the SPS burn checklist where it was left")
	book.list().index = book.list().steps.size()
	book.cycle()
	book.select(2)
	assert_eq(book.list().index, 0, "a finished checklist starts again, for the next burn")


func test_the_hud_and_the_card_share_the_book() -> void:
	build("translunar_coast")
	var hud := Hud.new()
	add_child_autofree(hud)
	hud.setup(rt, book)
	hud.select_checklist_for("translunar_coast")
	hud._process(0.0)
	var card := _card()
	assert_string_starts_with(_step_texts(card)[1], "▶ Mission Control: request the PAD", "UP TLM CM is in ACCEPT")
	(hud.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Next")[0] as Button).pressed.emit()
	card._process(0.0)
	assert_string_starts_with(_step_texts(card)[2], "▶ UP TLM CM - BLOCK", "the HUD's Next moved the card")
	book.cycle()
	hud._process(0.0)
	assert_eq(hud._check_title.selected, book.current, "and the wrist menu's CHECKLIST moves the HUD")


func test_the_card_shows_the_checklist_the_pad_and_capcom() -> void:
	book.select_for_phase("translunar_coast")
	var card := _card()
	assert_eq(card.title_label.text, "CHECKLIST  SPS BURN (P30 / P40)")
	var steps := _step_texts(card)
	assert_eq(steps.size(), 8, "eight steps around the current one")
	assert_false(steps[0].ends_with("(NEXT STEP)"), "a checked step checks itself off")
	Bus.set_value("ctl.cmc.up_tlm", true)
	book.update()
	card._process(0.0)
	assert_string_ends_with(_step_texts(card)[1], "(NEXT STEP)", "a read-only step says how to go on")
	assert_eq(card.pad_label.text, "PAD  none uplinked")
	Bus.set_value("mission.pad_text", "MCC PAD: TIG 004:04:18")
	Bus.set_value("mission.capcom", "004:00:00  Houston, uplinking MCC PAD")
	assert_eq(card.pad_label.text, "PAD  MCC PAD: TIG 004:04:18")
	assert_string_contains(card.capcom_label.text, "Houston, uplinking MCC PAD")
	for i in 6:
		Bus.set_value("mission.capcom", "call %d" % i)
	assert_eq(card.capcom_label.text, "CAPCOM\ncall 2\ncall 3\ncall 4\ncall 5", "the last four calls")
	# Everything stacks inside the card, top to bottom.
	var stack: Array[Label3D] = [card.title_label]
	for l in card.step_labels:
		if l.visible:
			stack.append(l)
	stack.append_array([card.pad_label, card.capcom_label])
	var last := INF
	for l in stack:
		assert_lt(l.position.y, last, "%s below the one before" % l.name)
		last = l.position.y
	assert_gt(last, -ChecklistCard.SIZE.y * 0.5, "the CAPCOM log starts on the card")
	book.list().index = book.list().steps.size()
	card._process(0.0)
	assert_eq(_step_texts(card)[-1], "✓ Checklist complete.")


func test_every_step_names_a_cabin_control_or_one_writes_its_check() -> void:
	var cabin := _cabin()
	var ids := {}
	for id in cabin.items:
		ids[id] = true
	var framed := 0
	for c in book.lists:
		for s in c.steps:
			if s.has("control"):
				assert_true(ids.has(s["control"]), "%s: control %s is in controls.csv" % [s["text"], s["control"]])
			var channel := str(s.get("check", {}).get("channel", ""))
			var target := {"control": str(s.get("control", "")), "channel": channel}
			var id := ChecklistHighlight.resolve(cabin, target)
			if channel.begins_with("ctl."):
				assert_ne(id, "", "%s: a cabin control writes %s" % [s["text"], channel])
			if id != "":
				framed += 1
	assert_eq(framed, 51, "43 of the flight's steps point at a cabin control, and 8 of the malfunction procedures'")


func test_every_apollo_8_step_names_a_cabin_control_or_one_writes_its_check() -> void:
	var cabin := _cabin()
	var framed := 0
	for c in ChecklistBook.load_default("apollo_8").lists:
		for s in c.steps:
			if s.has("control"):
				assert_true(cabin.items.has(s["control"]), "%s: control %s is in controls.csv" % [s["text"], s["control"]])
			var channel := str(s.get("check", {}).get("channel", ""))
			var id := ChecklistHighlight.resolve(cabin, {"control": str(s.get("control", "")), "channel": channel})
			if channel.begins_with("ctl."):
				assert_ne(id, "", "%s: a cabin control writes %s" % [s["text"], channel])
			if id != "":
				framed += 1
	assert_eq(framed, 50, "42 of Apollo 8's steps point at a cabin control, and 8 of the malfunction procedures'")


func test_every_apollo_10_step_names_a_control_or_one_writes_its_check() -> void:
	var cabin := _cabin()
	var lm_cabin := LmCabin.create()
	add_child_autofree(lm_cabin)
	var framed := [0, 0]
	for book in [ChecklistBook.load_default("apollo_10"), ChecklistBook.load_lm("apollo_10")]:
		var lm: bool = book.lists[0].title.begins_with("Undocking")
		var cab: Node = lm_cabin if lm else cabin
		for c in book.lists:
			for s in c.steps:
				if s.has("control"):
					assert_true(cab.items.has(s["control"]), "%s: control %s is in its cabin" % [s["text"], s["control"]])
				var channel := str(s.get("check", {}).get("channel", ""))
				var id := ChecklistHighlight.resolve(cab, {"control": str(s.get("control", "")), "channel": channel})
				if channel.begins_with("ctl."):
					assert_ne(id, "", "%s: a cabin control writes %s" % [s["text"], channel])
				if id != "":
					framed[1 if lm else 0] += 1
	assert_eq(framed, [51, 59], "Charlie Brown's (8 of them the malfunction procedures') and Snoopy's steps that point at a cabin control")


func test_every_apollo_12_step_names_a_control_or_one_writes_its_check() -> void:
	var cabin := _cabin()
	var lm_cabin := LmCabin.create()
	add_child_autofree(lm_cabin)
	var framed := [0, 0]
	for book in [ChecklistBook.load_default("apollo_12"), ChecklistBook.load_lm("apollo_12")]:
		var lm: bool = book.lists[0].title.begins_with("Undocking")
		var cab: Node = lm_cabin if lm else cabin
		for c in book.lists:
			for s in c.steps:
				if s.has("control"):
					assert_true(cab.items.has(s["control"]), "%s: control %s is in its cabin" % [s["text"], s["control"]])
				var channel := str(s.get("check", {}).get("channel", ""))
				var id := ChecklistHighlight.resolve(cab, {"control": str(s.get("control", "")), "channel": channel})
				if channel.begins_with("ctl."):
					assert_ne(id, "", "%s: a cabin control writes %s" % [s["text"], channel])
				if id != "":
					framed[1 if lm else 0] += 1
	assert_eq(framed, [51, 58], "Yankee Clipper's (8 of them the malfunction procedures') and Intrepid's steps that point at a cabin control")


func test_every_eagle_step_names_one_of_its_controls_or_one_writes_its_check() -> void:
	var cabin := LmCabin.create()
	add_child_autofree(cabin)
	var framed := 0
	for c in ChecklistBook.load_lm().lists:
		for s in c.steps:
			if s.has("control"):
				assert_true(cabin.items.has(s["control"]), "%s: control %s is in lm_controls.csv" % [s["text"], s["control"]])
			var channel := str(s.get("check", {}).get("channel", ""))
			var id := ChecklistHighlight.resolve(cabin, {"control": str(s.get("control", "")), "channel": channel})
			if channel.begins_with("ctl.lm."):
				assert_ne(id, "", "%s: a control in Eagle's cabin writes %s" % [s["text"], channel])
			if id != "":
				framed += 1
	assert_eq(framed, 57, "57 of Eagle's steps point at a control in its cabin")


func test_the_highlight_follows_the_player_into_eagle() -> void:
	var cm := _cabin()
	var lm := LmCabin.create()
	add_child_autofree(lm)
	var lm_book := ChecklistBook.load_lm()
	lm_book.select_for_phase("lunar_descent")
	var hl := ChecklistHighlight.new()
	hl.follow(cm, book)
	hl.follow(lm, lm_book)
	assert_eq(hl.get_parent(), lm, "into Eagle's cabin")
	Bus.set_value("mission.event.pad_pdi", 1)
	lm_book.update()
	hl.update()
	assert_eq(hl.target_id, "P4_DSKY", "V37E 63E is typed on Eagle's DSKY")
	Bus.set_value("lm.guid.program", 63)
	Bus.set_value("lm.guid.step", "v50n18")
	lm_book.update()
	hl.update()
	assert_eq(hl.target_id, "P3_LGC_MODE", "LGC MODE - AUTO: the switch that writes ctl.lm.mode")


func test_the_highlight_frames_the_current_steps_control() -> void:
	var cabin := _cabin()
	book.select_for_phase("translunar_coast")
	var hl := ChecklistHighlight.new()
	hl.cabin = cabin
	hl.book = book
	cabin.add_child(hl)
	hl.update()
	assert_eq(hl.target_id, "P2_UP_TLM_CM", "UP TLM CM - ACCEPT")
	Bus.set_value("ctl.cmc.up_tlm", true)
	book.update()
	hl.update()
	assert_eq(Bus.get_value("present.checklist.next_control"), "", "requesting the PAD is not a cabin control")
	assert_false(Bus.get_value("present.checklist.highlight"))
	book.next()
	Bus.set_value("ctl.cmc.up_tlm", false)
	book.update()
	hl.update()
	assert_eq(hl.target_id, "P2_DSKY", "V37E 30E is typed on the DSKY")
	assert_true(Bus.get_value("present.checklist.highlight"))
	var frame: Node3D = hl.get_node("Frame")
	var dsky: Node3D = cabin.items["P2_DSKY"]
	var local := dsky.global_transform.affine_inverse() * frame.global_position
	assert_almost_eq(Vector2(local.x, local.y), Vector2.ZERO, Vector2.ONE * 1e-5, "centred on the DSKY")
	assert_gt(local.z, 0.0, "in front of it")
	var sides: Array = frame.get_children()
	assert_almost_eq((sides[0].mesh as BoxMesh).size.x, 0.2 + 2 * ChecklistHighlight.MARGIN + ChecklistHighlight.BAR, 1e-6,
		"as wide as the DSKY's footprint")
	for p in [30, 40]:
		Bus.set_value("guid.program", p)
		book.update()
	Bus.set_value("guid.maneuver_valid", true)
	book.update()
	hl.update()
	assert_eq(hl.target_id, "", "P52 is flown at the lower equipment bay, on its own checklist")
	Bus.set_value("imu.preferred", true)
	book.update()
	hl.update()
	assert_eq(hl.target_id, "P1_CMC_MODE", "CMC MODE - AUTO: the switch that writes ctl.cmc.mode")
	Bus.set_value("present.checklist.highlight_enabled", false)
	hl.update()
	assert_false(frame.visible, "HILITE off")
	assert_eq(Bus.get_value("present.checklist.next_control"), "")

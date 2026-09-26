## Slice 2d's check (docs/ROADMAP.md): through the desktop rig, request a
## PAD from the wrist menu, then see UPLINK ACTY on the cabin DSKY and the
## PAD on the checklist card, and go on down the checklist from the menu
## and the DSKY. The menu rides on the camera, so its buttons are clicked
## where they are on the screen, as with a free mouse; panel controls are
## looked at and clicked, as in test_cabin_mcc.gd.
extends CabinTest


func test_request_a_pad_from_the_wrist_menu_and_fly_on_down_the_checklist() -> void:
	build("translunar_coast")
	# As in test_cabin_mcc.gd: a TLI cutoff error, so there is an MCC to plan.
	var tr := rt.dynamics.traj
	tr.set_state(tr.primary, tr.t, tr.pos(), tr.vel() - tr.vel().normalized() * 0.8)
	rt.dynamics.publish_state()
	await setup_cabin("translunar_coast")
	assert_string_starts_with(current_step(), "Mission Control: request the PAD")
	assert_false(dsky.lamps["uplink_acty"].get("lit"))
	await press(KEY_M)
	assert_true(menu.is_shown(), "M shows the wrist menu")
	await click_menu("mcc")
	assert_false(rt.sequencer.last_pad.is_empty(), "Mission Control solved an MCC")
	assert_true(dsky.lamps["uplink_acty"].get("lit"), "UPLINK ACTY on the cabin DSKY")
	assert_string_starts_with(card.pad_label.text, "PAD  MCC PAD: TIG ")
	assert_eq(card.pad_label.text, "PAD  " + str(Bus.get_value("mission.pad_text")), "the PAD on the card")
	assert_string_contains(card.capcom_label.text, "Houston, uplinking your state vector and MCC PAD")
	await click_menu("next")
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), "UP TLM CM - BLOCK", "NEXT STEP")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P2_UP_TLM_CM", "the highlight moves to UP TLM CM")
	await switch_to("P2_UP_TLM_CM", 0)
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), "V37E 30E", "UP TLM CM in BLOCK")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P2_DSKY", "the highlight moves to the DSKY")
	run(3.0, false)
	assert_false(dsky.lamps["uplink_acty"].get("lit"), "the uplink is done")
	await type("V37E30E")
	await wait_process_frames(1)
	assert_string_starts_with(current_step(), "Verify TIG", "typing P30 completed the step")
	# The clock from the menu, including out of the 1000x lock on the panels.
	for i in 3:
		await click_menu("faster")
	assert_eq(SimClock.rate, 1000.0)
	assert_true(SimClock.controls_locked())
	await click_menu("slower")
	assert_eq(SimClock.rate, 100.0, "RATE - works while the panels are locked")
	await click_menu("pause")
	assert_true(SimClock.paused)
	await click_menu("pause")
	assert_false(SimClock.paused)
	# Hidden, the menu lets clicks through to whatever is behind it.
	await press(KEY_M)
	assert_false(menu.is_shown())
	var asked: Array = []
	var record := func(ch: String, v: Variant) -> void:
		if ch == "ctl.ground.pad_request":
			asked.append(v)
	Bus.value_changed.connect(record)
	mouse(camera.unproject_position(menu.button("mcc").get_node("Touch").global_position))
	Bus.value_changed.disconnect(record)
	assert_eq(asked, [], "no PAD asked for through the hidden menu")

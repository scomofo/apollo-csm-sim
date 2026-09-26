## The VR cockpit milestone's check (docs/ROADMAP.md, milestone 2): every
## checklist in data/missions/apollo_11/checklists.json worked from the
## commander's couch through the cabin, as a player on the desktop works it
## (CabinTest), until the card shows it complete. Mission Control's PADs
## are asked for on the wrist menu, read-only steps are acknowledged with
## its NEXT STEP and the checklists turned with its CHECKLIST, and the burn
## residuals are trimmed with the translation controller on the keys. Each
## phase starts from that phase's start state, as test_lunar_mission.gd's
## segments do.
extends CabinTest

## The checklists this file flies; a checklist added to checklists.json
## needs a flight here too.
const FLOWN := ["Parking orbit and TLI", "SPS burn (P30 / P40)", "Lunar orbit and TEI", "Entry"]


func test_every_checklist_is_flown_here() -> void:
	var titles := ChecklistBook.load_default().lists.map(func(c: Checklist) -> String: return c.title)
	assert_eq(titles, FLOWN)


func _sivb(state: String) -> Callable:
	return func() -> bool: return str(Bus.get_value("sivb.state", "")) == state


func test_parking_orbit_and_tli() -> void:
	build("parking_orbit")
	await setup_cabin("parking_orbit")
	await press(KEY_M)
	assert_true(menu.is_shown(), "the wrist menu is open")
	await expect_step("Watch the S-IVB/IU")
	await click_menu("next")
	await expect_step("TLI ignition")
	var tig := float(rt.sequencer.tli_pad["tig"])
	assert_true(await fly_until(_sivb("burning"), tig - SimClock.get_seconds + 60.0, 60.0), "the S-IVB lit")
	await expect_step("TLI cutoff")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P2_DSKY", "the highlight is on the DSKY")
	assert_true(await fly_until(_sivb("done"), 600.0, 10.0), "TLI cutoff")
	await type("V82E")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["16", "44"], "V82 shows the orbit")
	assert_eq(dsky.fields["r1"].text, "+99999", "apogee beyond the Moon: off the scale")
	await expect_step("CSM/LV SEP")
	await slow_down()
	await click(cabin.items["P1_CSM_LV_SEP"], 1.0)
	assert_eq(rt.dynamics.config, "csm_lm", "transposition, docking and LM extraction")
	await expect_complete("Parking orbit and TLI")


## N85, the velocity still to gain in body axes (m/s).
func _n85() -> Vector3:
	var v: Array = rt.agc().noun_values(85)
	return Vector3(v[0], v[1], v[2])


## Null the N85 residuals axis by axis with the translation controller on
## the keys (HandControllerInput): R and F for +X and -X, Right and Left
## for +Y and -Y, Down and Up for +Z and -Z, each held until its axis is
## inside 0.2 ft/s. Returns the residuals before the trim.
func _trim_residuals() -> Vector3:
	var keys_for := [[KEY_R, KEY_F], [KEY_RIGHT, KEY_LEFT], [KEY_DOWN, KEY_UP]]
	var before := _n85()
	for axis in 3:
		var r: float = _n85()[axis]
		if absf(r) < 0.2 * Units.FT:
			continue
		var key: Key = keys_for[axis][0 if r > 0.0 else 1]
		await hold_key(key)
		assert_ne(Bus.get_value("ctl.thc"), Vector3.ZERO, "the THC is deflected")
		for i in 600:
			run(0.1, false)
			var now: float = _n85()[axis]
			if absf(now) < 0.2 * Units.FT or signf(now) != signf(r):
				break
		await release_key(key)
	return before


## The simulator's SPS cutoff is ideal, where flown ones left a few tenths
## of a ft/s to trim. Leave the vehicle [param short] m/s short along the
## thrust at cutoff, a shortfall its accelerometers saw, as test_cabin_mcc
## gives TLI a cutoff error.
func _cut_off_short(short: float) -> void:
	var agc := rt.agc()
	var tr := rt.dynamics.traj
	tr.set_state(tr.primary, tr.t, tr.pos(), tr.vel() - agc.burn_dir * short)
	rt.dynamics.publish_state()
	for i in 3:
		agc.vg[i] += agc.burn_dir[i] * short
	agc.dv_accum -= short


## Fly the uplinked PAD down the SPS burn checklist from its second step,
## every action in the cabin, and return the ΔV flown (m/s). [param short]
## m/s are left to trim at cutoff.
func _fly_burn(short: float = 0.0) -> float:
	var agc := rt.agc()
	await expect_step("V37E 30E")
	await type("V37E30E")
	await expect_step("Verify TIG (N33)")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["06", "33"], "P30 shows TIG")
	await type("PPP")
	assert_true(agc.maneuver_valid, "TIG, ΔV and the apsides accepted")
	await expect_step("CMC MODE - AUTO")
	await slow_down()
	await switch_to("P1_CMC_MODE", 2)
	await expect_step("V37E 40E")
	assert_gt(agc.dv_lvlh_load.length(), 10.0 * Units.FT, "an SPS burn")
	# P40 comes a quarter of an hour before TIG, time for the maneuver to
	# the burn attitude. Until then the CMC holds attitude and the coast
	# runs fast; once P40 steers, every step is a fixed one.
	await fly(agc.maneuver_tig - 900.0 - SimClock.get_seconds, 3600.0)
	await type("V37E40E")
	await expect_step("V50N18 flashing")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["50", "18"], "asks to maneuver to the burn attitude")
	await type("P")
	await fly(1.0, 0.5, false)
	await expect_step("DELTA-V THRUST A - NORMAL")
	await switch_to("P1_DV_THRUST_A", 1)
	await expect_step("DELTA-V THRUST B - NORMAL")
	await switch_to("P1_DV_THRUST_B", 1)
	await expect_step("At TIG-5 s V99N40")
	var tig := agc.maneuver_tig
	await fly(tig - 12.0 - SimClock.get_seconds, 600.0)
	assert_true(await fly_until(func() -> bool: return agc.step_name == "v99", 10.0, 1.0, false), "V99 at TIG-5")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["99", "40"], "asks for engine-on enable")
	await type("P")
	assert_true(await fly_until(func() -> bool: return agc.step_name == "burn", 10.0, 0.5, false), "ignition at TIG")
	await expect_step("Monitor V16N40")
	assert_eq([dsky.fields["verb"].text, dsky.fields["noun"].text], ["16", "40"], "V16N40 through the burn")
	assert_true(await fly_until(func() -> bool: return agc.step_name == "post", 2000.0, 5.0, false), "SPS cutoff")
	# The CMC goes to post-burn as the chamber pressure falls; the thrust
	# dies away over the next second, and the crew trims after that.
	assert_true(await fly_until(func() -> bool: return float(Bus.get_value("sps.thrust_n", 0.0)) == 0.0, 5.0, 0.5, false),
		"the SPS's tail-off over")
	if short > 0.0:
		_cut_off_short(short)
	var dv := agc.dv_accum
	await expect_step("DELTA-V THRUST A and B - OFF")
	await switch_to("P1_DV_THRUST_A", 0)
	await switch_to("P1_DV_THRUST_B", 0)
	await expect_step("Trim N85 residuals")
	assert_eq(dsky.fields["noun"].text, "85", "the residuals on the DSKY")
	var before := await _trim_residuals()
	var after := _n85()
	gut.p("  residuals %s ft/s, trimmed to %s" % [before / Units.FT, after / Units.FT])
	if short > 0.0:
		assert_gt(before.x, 0.2 * Units.FT, "a residual to trim along X")
	for i in 3:
		assert_lt(absf(after[i]), 0.2 * Units.FT, "N85 axis %d inside 0.2 ft/s" % i)
	await fly(1.0, 1.0, false)
	assert_almost_eq(Dsky.parse_value(dsky.fields["r1"].text, "d1", 1.0 / Units.FT), after.x, 0.06 * Units.FT,
		"the DSKY shows the X residual, to a tenth of a ft/s")
	await type("P")
	await expect_complete("SPS burn (P30 / P40)")
	assert_eq(agc.program, 0, "back in P00")
	# Free drift until the next burn: in lunar orbit an attitude hold
	# limit-cycles, and the coast would run in fixed steps.
	await switch_to("P1_CMC_MODE", 0)
	return dv


## Open the SPS burn checklist, ask Mission Control for the [param kind]
## PAD on the wrist menu, and fly it, [param short] m/s short at cutoff.
## Returns the PAD with the ΔV flown.
func _burn(kind: String, short: float = 0.0) -> Dictionary:
	await open_checklist("SPS burn (P30 / P40)")
	await wait_process_frames(1)
	await slow_down()
	if current_step().begins_with("UP TLM CM - ACCEPT"):
		# BLOCK since the last burn.
		await switch_to("P2_UP_TLM_CM", 1)
	await expect_step("Mission Control: request the PAD")
	await click_menu(kind)
	var pad: Dictionary = rt.sequencer.last_pad
	assert_false(pad.is_empty(), "Mission Control solved %s" % kind)
	assert_true(dsky.lamps["uplink_acty"].get("lit"), "UPLINK ACTY")
	gut.p(Rtcc.pad_text(pad))
	await click_menu("next")
	await expect_step("UP TLM CM - BLOCK")
	await switch_to("P2_UP_TLM_CM", 0)
	# P30 about 20 minutes before TIG.
	await fly(float(pad["tig"]) - 1200.0 - SimClock.get_seconds, 3600.0)
	pad["flown"] = await _fly_burn(short)
	return pad


func _phase(p: String) -> Callable:
	return func() -> bool: return rt.sequencer.phase == p


func test_lunar_orbit_insertion_to_tei() -> void:
	build("translunar_coast")
	await setup_cabin("translunar_coast")
	await open_checklist("Lunar orbit and TEI")
	await expect_step("Request LOI PAD")
	# Coast to about 8 h before pericynthion.
	var ap := Rtcc.lunar_approach(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	await fly(float(ap["t"]) - 8.0 * 3600.0 - SimClock.get_seconds, 3600.0)
	var loi := await _burn("loi", 0.5 * Units.FT)
	assert_almost_eq(float(loi["flown"]), float(loi["dv"]), 2.0, "LOI-1 flown")
	await open_checklist("Lunar orbit and TEI")
	await expect_step("Request LOI PAD")
	await click_menu("next")
	assert_true(await fly_until(_phase("lunar_orbit"), 600.0, 60.0), "in lunar orbit")
	await expect_step("Request LOI-2 PAD")
	var circ := await _burn("circ")
	assert_almost_eq(float(circ["flown"]), float(circ["dv"]), 1.0, "LOI-2 flown")
	var c := rt.dynamics.traj.conic()
	var alts := Vector2(float(c["rp"]) - Bodies.R_MOON, float(c["ra"]) - Bodies.R_MOON) / 1000.0
	gut.p("lunar orbit %.1f x %.1f km" % [alts.x, alts.y])
	assert_lt(alts.y - alts.x, 60.0, "near-circular after LOI-2")
	await open_checklist("Lunar orbit and TEI")
	await expect_step("Request LOI-2 PAD")
	await click_menu("next")
	await expect_step("LM JETT")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P1_LM_JETT", "the highlight is on LM JETT")
	await slow_down()
	await click(cabin.items["P1_LM_JETT"], 1.0)
	assert_eq(rt.dynamics.config, "csm", "Eagle's ascent stage stays behind")
	await expect_step("Request TEI PAD")
	var tei := await _burn("tei")
	assert_almost_eq(float(tei["flown"]), float(tei["dv"]), 2.0, "TEI flown")
	await open_checklist("Lunar orbit and TEI")
	await expect_step("Request TEI PAD")
	await click_menu("next")
	assert_true(await fly_until(_phase("transearth_coast"), 3600.0, 60.0), "on the way home")
	await expect_complete("Lunar orbit and TEI")


func test_entry_to_splashdown() -> void:
	build("entry")
	await setup_cabin("entry")
	await expect_step("Request MCC PADs")
	# A quarter of an hour from entry interface, on the corridor the TEI
	# PAD aimed for, there's nothing left to trim.
	await click_menu("mcc")
	assert_true(rt.sequencer.last_pad.is_empty(), "no MCC PAD")
	assert_string_contains(card.capcom_label.text, "Houston: no MCC solution / burn not required.")
	await click_menu("next")
	await expect_step("CM/SM SEP")
	assert_eq(Bus.get_value("present.checklist.next_control"), "P1_CM_SM_SEP", "the highlight is on CM/SM SEP")
	await click(cabin.items["P1_CM_SM_SEP"], 1.0)
	assert_eq(rt.dynamics.config, "cm", "the command module alone")
	await expect_step("V37E 61E")
	await type("V37E61E")
	assert_eq([dsky.fields["prog"].text, dsky.fields["verb"].text, dsky.fields["noun"].text], ["61", "16", "64"],
		"P61 shows g, velocity and altitude")
	# ATT SOURCE is already at CMC, so its step checks itself off.
	assert_eq(cabin.items["P1_ATT_SOURCE"].get("position_index"), 0, "ATT SOURCE reads CMC")
	await expect_step("ELS LOGIC - ON")
	await switch_to("P1_ELS_LOGIC", 1)
	await expect_step("ELS AUTO")
	await switch_to("P1_ELS_AUTO", 1)
	await expect_step("0.05 g: P64")
	var agc := rt.agc()
	assert_true(await fly_until(func() -> bool: return agc.program >= 64, 1800.0, 30.0), "entry guidance at 0.05 g")
	await expect_step("Drogues at 24,000 ft")
	assert_eq(dsky.fields["prog"].text, "64", "P64 on the DSKY")
	assert_true(await fly_until(func() -> bool: return Bus.get_value("els.drogue") == true, 1800.0, 5.0), "drogues")
	await expect_step("Mains at 10,000 ft")
	assert_true(await fly_until(func() -> bool: return Bus.get_value("els.mains") == true, 600.0, 5.0), "mains")
	await expect_step("Splashdown")
	assert_true(await fly_until(func() -> bool: return rt.dynamics.landed, 1800.0, 10.0), "splashdown")
	gut.p("max g %.2f, splash %.1f m/s" % [rt.dynamics.max_g, rt.dynamics.landed_speed])
	assert_eq(Bus.get_value("mission.result"), "success")
	await expect_complete("Entry")

## Slice 12a's fourth part (docs/ROADMAP.md, milestone 12): Kitty Hawk's
## transposition and docking, flown. From the parking orbit the S-IVB flies
## TLI; the crew separate at the flown time, CSM/LV SEP leaving Antares on
## the S-IVB (mission.json tde_flown), turn about and close on its drogue.
## The capture latches failed (the timeline's capture_latches): contact
## after contact rebounds, and Houston's calls come at the flown times
## after the separation. On the sixth attempt the crew hold +X with the
## probe in the drogue and retract it, and the ring latches fire: hard dock
## (tests/tde_crew.gd) [published: MSC-04112, Tables 6-I and 14-I, section
## 14.1.1; Apollo Flight Journal, 003:02:58 to 004:57:09].
extends SimTest

## Apollo 14's attempts [published: MSC-04112, Table 14-I]: the GET of
## each one's first contact, its closing speed (ft/s), and how long the
## crew held +X after it (s); the sixth's probe retracted 6.9 s after its
## contact. Attempts 2 and 3 aren't flown here.
const ATTEMPTS := [["3:13:53.7", 0.1, 0.0], ["3:23:41.7", 0.45, 6.2], ["4:32:29.3", 0.25, 0.0], ["4:56:44.9", 0.2, 14.3]]
## Houston's calls, the flown GETs (Apollo Flight Journal).
const CALLS := [["3:18:06", "docking probe circuit breakers"], ["3:23:07", "hold plus-X for 3 seconds"],
	["4:14:34", "try the docking again with the normal procedures"], ["4:39:02", TdeCrew.RETRACT_CALL]]


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_kitty_hawk_docks_on_the_sixth_attempt_by_retracting_the_probe() -> void:
	build("parking_orbit", "apollo_14")
	var sq := rt.sequencer
	var dyn := rt.dynamics
	var said: Array = []
	sq.capcom.connect(func(w: String) -> void: said.append([SimClock.get_seconds, w]))
	Bus.set_value("ctl.cmc.mode", 0)
	run(float(sq.tli_pad["tig"]) - 30.0 - SimClock.get_seconds)
	assert_true(run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 3600.0, 60.0), "TLI")
	var rows := PackedStringArray()

	# CSM/LV SEP at 03:02:29.4 (MSC-04112, Table 6-III): Kitty Hawk free,
	# Antares still on the S-IVB.
	var sep := _get_s("3:02:29.4")
	TdeCrew.separate(self, sep)
	assert_almost_eq(sq.event_get("csm_lv_sep"), sep, 0.1, "CSM/LV SEP at the crew's press")
	assert_eq([str(Bus.get_value("dock.state")), dyn.config, dyn.lm.config], ["tde", "csm", "lm_sivb"])
	assert_almost_eq(dyn.lm.mass, SpacecraftData.lm_mass() + float(SpacecraftData.section("mass")["sivb_dry_kg"]), 1.0,
		"the target: the LM and the S-IVB, its propellant gone")
	assert_true(bool(Bus.get_value("dock.probe.latches_failed")), "the capture latches failed from the separation")
	assert_true(rt.failures.active.has("csm_capture_latches"))
	assert_almost_eq(float(Bus.get_value("dock.misalign_deg")), 0.0, 1.0, "turned about to face the drogue")
	rows.append("CSM/LV SEP | the crew's, at %s; turned about, %.1f ft out, %.1f° out of line, %s | 03:02:29.4" % [
		Units.hms(sep), float(Bus.get_value("dock.range_m")) / Units.FT, float(Bus.get_value("dock.misalign_deg")),
		Units.hms(SimClock.get_seconds)])

	# Five attempts in the flight, eight contacts: no capture.
	var contacts := PackedStringArray()
	var last := {}
	for a: Array in ATTEMPTS:
		var sixth: bool = a == ATTEMPTS[-1]
		last = TdeCrew.attempt(self, float(a[1]) * Units.FT, _get_s(a[0]), float(a[2]), sixth)
		if not last.has("get_s"):
			fail_test("the probe didn't meet the drogue at " + str(a[0]))
			return
		assert_almost_eq(float(last["get_s"]), _get_s(a[0]), 2.0, "the contact's time")
		assert_false(last["captured"], "no capture")
		assert_eq(last["fault"], "latches", "the capture latches didn't engage")
		assert_almost_eq(float(last["closing_mps"]) / Units.FT, float(a[1]), 0.02, "its closing speed")
		if not sixth:
			assert_eq(str(Bus.get_value("dock.state")), "tde", "backed off, still apart")
			contacts.append("%s at %.2f ft/s%s" % [Units.hms(float(last["get_s"])), float(last["closing_mps"]) / Units.FT,
				", +X %.1f s" % float(a[2]) if float(a[2]) > 0.0 else ""])
	rows.append("The attempts without capture | %s: the capture latches didn't engage | 3:13:53.7 at 0.1 ft/s, and seven more contacts to 4:32:29.3: 3:23:41.7 at 0.4 to 0.5 ft/s, +X 6.2 s; 4:32:29.3 at 0.25 ft/s" % "; ".join(contacts))

	# The sixth: +X held, the probe retracted 6.9 s after the contact, the
	# ring latches 11.8 s after it; hard dock at 04:56:56 (MSC-04112,
	# Tables 14-I and 6-I).
	var contact := float(last["get_s"])
	var docked := float(last["docked_get"])
	assert_gt(docked, 0.0, "hard dock")
	assert_almost_eq(docked - contact, TdeCrew.RETRACT_AFTER_S + float(Docking.params()["retract_s"]), 0.1,
		"the ring latches 11.8 s after the contact")
	assert_almost_eq(docked, _get_s("4:56:56"), 2.0, "hard dock at 04:56:56")
	assert_eq([str(Bus.get_value("dock.state")), dyn.config, dyn.lm_config], ["docked", "csm_lm", "lm"], "Antares docked, drawn out")
	assert_null(dyn.lm, "the S-IVB left behind")
	assert_false(bool(Bus.get_value("dock.probe.latches_failed")), "the latches as they were at the lunar orbit's docking")
	assert_false(bool(Bus.get_value("dock.retracting")))
	assert_eq(Docking.describe(Bus.get_value("dock.contact")), "hard dock: the probe retracted, the ring latches fired")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "hard dock and LM extraction")
	rows.append("The sixth attempt | contact %s at %.2f ft/s, +X held; PROBE RETRACT %.1f s on; hard dock %.1f s after the contact, %s | 4:56:44.9 at 0.2 ft/s, +X 14.3 s; the retraction 6.9 s on; the first ring latch 11.8 s after the contact; hard dock 04:56:56" % [
		Units.hms(contact), float(last["closing_mps"]) / Units.FT, TdeCrew.RETRACT_AFTER_S, docked - contact, Units.hms(docked)])

	# Houston's calls, each at its time after the separation.
	var heard := PackedStringArray()
	for c: Array in CALLS:
		var at := -1.0
		for s: Array in said:
			if str(s[1]).contains(str(c[1])):
				at = float(s[0])
				break
		assert_almost_eq(at, _get_s(c[0]), 1.0, "Houston: " + str(c[1]))
		heard.append(Units.hms(at))
	rows.append("Houston's calls | the probe's breakers %s; hold +X %s; the normal procedures again %s; the retraction %s | 003:18:06; 003:23:07; 004:14:34; 004:39:02" % Array(heard))
	gut.p("Fidelity rows (Apollo 14's transposition and docking):\n" + "\n".join(rows))

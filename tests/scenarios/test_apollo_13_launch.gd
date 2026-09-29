## Slice 10d (docs/ROADMAP.md, milestone 10): Apollo 13 flies from the pad
## on AS-508 from its data alone (data/missions/apollo_13/mission.json
## "launch" and "vehicles" "saturn_v"), at 19:13 UTC on 11 April 1970 from
## LC-39A. Pogo shuts the S-II's centre engine down at 330.65 s, the
## mission's failure, 132 s before the IU would have: its light comes on,
## and the IU's iterative guidance steers on the four outboard engines,
## pitching up as it re-plans. The S-II's shift to its low mixture ratio
## waits on the IU's velocity criterion and comes late; the four burn
## longer, the S-IVB longer after them, and the stack reaches the parking
## orbit late, and flies on through TLI. Flown again without the pogo, the
## burns come out as AS-508's were planned, so the pogo's toll can be read
## beside the flight's. The flown figures are the AS-508 flight evaluation
## report's (MPR-SAT-FE-70-2), the Apollo 13 Mission Report's (MSC-02680)
## and the Apollo Flight Journal's [published].
extends SimTest

## AS-508's events, GET s (MPR-SAT-FE-70-2, Table 2-2): the IU's command to
## shift the S-II to its low mixture ratio on its velocity criterion
## (emr_command) and the engines' shift (emr_shift); s2_ceco the centre
## engine's cutoff the IU still commanded, 132 s after the pogo [published].
const FLOWN := {
	"tilt": 12.6, "mach_1": 68.4, "max_q": 81.3, "sic_ceco": 135.18, "sic_oeco": 163.60, "staging": 164.3,
	"s2_ignition": 165.0, "interstage_jettison": 194.3, "les_jettison": 201.0, "igm": 204.5, "s2_ceco": 462.6,
	"emr_command": 534.7, "emr_shift": 537.5, "s2_oeco": 592.64, "s4_ignition": 596.9, "s4_cutoff": 749.83,
	"insertion": 759.83,
}
## At the cutoffs: altitude (km, geodetic), space-fixed velocity (m/s) and
## flight path angle (deg) (ibid., Table 4-2) [published].
const FLOWN_STATES := {
	"sic_ceco": [43.5, 1928.9, 23.612], "sic_oeco": [67.4, 2744.0, 19.480], "s2_oeco": [189.1, 6891.8, 0.657],
	"s4_cutoff": [191.6, 7790.8, 0.004],
}
## At the pogo's cutoff of the centre engine, 330.64 s (ibid.) [published].
const FLOWN_POGO := [159.6, 3919.6, 4.158]
## The pogo's toll, s: the IU's shift command 32.2 s later than predicted,
## the S-II's burn 34.93 s longer and the S-IVB's 9.3 s, insertion 44.07 s
## late (ibid., sections 4.1, 6.3, 6.5 and 7.4) [published]; each "due
## primarily to early CECO" [published], the rest of it the vehicle's
## performance and loading off their predictions.
const TOLL := {"emr_command": 32.2, "s2_burn": 34.93, "s4_burn": 9.3, "insertion": 44.07}

## CAPCOM's calls and the crew's as they came: [GET, words].
var calls: Array = []


func test_apollo_13_flies_on_four_s2_engines_into_its_parking_orbit_and_on_through_tli() -> void:
	build("launch", "apollo_13")
	var sq := rt.sequencer
	var lv: LaunchVehicle = rt.systems["lv"]
	sq.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	assert_eq(sq.phase, "launch")
	assert_true(rt.dynamics.has_lm(), "Aquarius in the adapter")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Apollo 13 is Go")
	assert_eq(rt.failures.armed_on.keys(), ["s2_engine_5"], "the pogo, armed on the liftoff")
	Bus.set_value("ctl.cmc.mode", 0)
	run(19.0, false)
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")

	# The flight: the state at the pogo's cutoff, and the thrust's pitch
	# above the horizon each second.
	var at_pogo := []
	sq.event_fired.connect(func(id: String) -> void:
		if id == "s2_engine_5_failure":
			at_pogo.append_array(ascent_state()))
	var pitch := {}
	var each := func() -> void:
		var r := rt.dynamics.traj.pos().normalized()
		pitch[roundf(SimClock.get_seconds)] = rad_to_deg(asin(clampf(lv.dir.dot(r), -1.0, 1.0)))
	var flight := fly_launch(800.0, each)
	var states: Dictionary = flight["states"]
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	gut.p(launch_table(flight, FLOWN, FLOWN_STATES))

	# The pogo at 330.65 s: the centre engine out, LV ENG 5 on, Lovell's
	# "Inboard." and Houston's word 4 s later (the Apollo Flight Journal:
	# 5:32 and 5:36).
	var pogo := float(rt.failures.active.get("s2_engine_5", -1.0))
	assert_almost_eq(pogo, 330.65, 0.1, "the centre engine out at 330.65 s")
	gut.p("the pogo at %.2f s: %.1f km, %.1f m/s, %.3f deg (flown 330.64 s: %.1f km, %.1f m/s, %.3f deg)" % [pogo,
		at_pogo[0], at_pogo[1], at_pogo[2], FLOWN_POGO[0], FLOWN_POGO[1], FLOWN_POGO[2]])
	assert_almost_eq(float(at_pogo[1]), FLOWN_POGO[1], 40.0, "its velocity")
	assert_almost_eq(float(at_pogo[2]), FLOWN_POGO[2], 1.0, "its flight path angle")
	assert_almost_eq(_call_get("Inboard.", 300.0), pogo, 0.1, "Lovell's call")
	assert_almost_eq(_call_get("We confirm inboard out", 300.0), 336.0, 1.0, "Houston's at 5:36")
	for c in [[331.0, "00001 00", "the centre engine out"], [462.0, "00001 00", "and on"],
			[464.0, "00001 00", "past the IU's own cutoff of it"], [540.0, "00001 00", "past the shift"]]:
		assert_eq(_lights_at(flight, c[0]), c[1], "%s: %s" % [c[2], c[0]])
	assert_eq(_lights_at(flight, 593.0), "11111 00", "the S-II cut off, before its separation at 593.5 s")
	assert_eq(lights_after(flight, "s4_ignition", 10.0), "00000 00", "the S-IVB at thrust, 5 out with the S-II")
	# The IU's guidance re-plans on the four at once: the vehicle pitches up
	# some 7 deg in its next seconds (ibid., Figure 9-4 [a plot reading]).
	var up := float(pitch[341.0]) - float(pitch[330.0])
	gut.p("the IGM's pitch-up after the pogo: %.2f deg (flown about 7)" % up)
	assert_between(up, 4.0, 10.0, "the IGM pitches up on four")

	# The Saturn's events: the IU's clock to the S-II, which the propellant
	# ends; the shift on the IU's velocity criterion, 32 s later than
	# planned (the no-pogo test below); the S-IVB's cutoff on its velocity.
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 31.2)" % q)
	assert_almost_eq(float(lv.events["tilt"]), FLOWN["tilt"], 0.1, "the roll and pitch program at 12.6 s")
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	for id in ["sic_oeco", "staging", "s2_ignition", "interstage_jettison", "les_jettison", "igm", "s2_ceco", "emr_command",
			"emr_shift"]:
		assert_almost_eq(float(lv.events[id]), FLOWN[id], 1.0, "%s: the S-IC burns out as flown, T3's events on it" % id)
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown, 35 s late")
	assert_almost_eq(float(lv.events["s4_ignition"]), FLOWN["s4_ignition"], 2.0, "the S-IVB's ignition")
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 6.0, "the S-IVB's velocity cutoff")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 6.0, "insertion at about 12:40")
	var s2_burn := float(lv.events["s2_oeco"]) - float(lv.events["s2_ignition"])
	var s4_burn := float(lv.events["s4_cutoff"]) - float(lv.events["s4_ignition"])
	gut.p("S-II burn %.2f s from its start command (flown 427.64), S-IVB burn %.2f s (flown 152.9)" % [s2_burn, s4_burn])
	assert_almost_eq(s2_burn, 427.64, 2.0, "the S-II's burn")
	assert_almost_eq(s4_burn, 152.9, 5.0, "the S-IVB's")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 6.0, "maximum dynamic pressure, on a standard atmosphere")
	assert_almost_eq(q, 31.2, 4.0, "the flown 31.2 kPa")
	for id in FLOWN_STATES:
		var s: Array = states[id]
		var f: Array = FLOWN_STATES[id]
		assert_almost_eq(float(s[1]), float(f[1]), 40.0, "%s: the velocity" % id)
		assert_almost_eq(float(s[2]), float(f[2]), 1.0, "%s: the flight path angle" % id)
	assert_true(flight["p11"], "the CMC in P11 through the ascent")

	# The parking orbit: Apollo 13's, 32.5 degrees and about 100 nmi, round
	# (MPR-SAT-FE-70-2, Table 4-5: 185.7 by 183.9 km, 32.525 deg); the
	# S-IVB with its propellant for TLI (73,447 kg at its second ignition,
	# the parking-orbit start's), TLI planned.
	run(20.0, false)
	assert_eq(sq.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	var sivb := float(Bus.get_value("sivb.prop_kg", 0.0))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (73,447 at its second ignition); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off, sivb,
		Units.hms(float(sq.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 185200.0, 1500.0, "about 100 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 32.525, 0.05, "32.5 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(sivb, 73447.0, 2000.0, "the S-IVB's propellant for TLI")
	assert_false(sq.tli_pad.is_empty(), "TLI planned")
	assert_false(bool(Bus.get_value("lv.eng_light_5")), "LV ENG 5 out in orbit")

	# On through TLI as the parking-orbit start flies it: the IU's TLI at
	# the RTCC's TIG, 2:35:46.4 for 350.8 s, C3 -1,376,274 m2/s2 at TLI, 10 s
	# on (MSC-02680, section 4.0; MPR-SAT-FE-70-2, section 7.8; D5-15560-8,
	# Table 4-IV); the free return past the Moon the parking-orbit start aims
	# for, 250.2 nmi up at 77:46:46 (mission.json "tli").
	var ok := run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 4.0 * 3600.0, 60.0)
	assert_true(ok, "TLI")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, SimClock.get_seconds + 5.0 * 86400.0)
	var peri := (float(ap["rp"]) - Bodies.R_MOON) / Units.NMI
	var peri_at := Rtcc._pericynthion_time(tr)
	gut.p("TLI at %s for %.1f s, C3 %.0f m2/s2; the pericynthion after it %.1f nmi at %s (flown 2:35:46.4 for 350.8 s, C3 -1,376,274; aimed 250.2 nmi at 77:46:46)" % [
		Units.hms(ign), cut - ign, c3, peri, Units.hms(peri_at)])
	assert_almost_eq(ign, MissionSequencer._get_s("2:35:46.4"), 60.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 350.8, 8.0, "its burn")
	assert_almost_eq(c3, -1376274.0, 20000.0, "C3")
	assert_almost_eq(peri, 250.2, 10.0, "the free return's pericynthion")
	assert_almost_eq(peri_at, MissionSequencer._get_s("77:46:46"), 60.0, "and when")

	# Without the pogo, the same vehicle flies AS-508's planned launch: the
	# IU's shift command, the S-II's cutoff and the S-IVB's come near their
	# predicted times (MPR-SAT-FE-70-2, Tables 2-2 and 4-2); beside it the
	# pogo's toll comes out as the report has it against the prediction.
	var hit := _burns(lv)
	build("launch", "apollo_13")
	rt.failures.disarm_on("liftoff")
	Bus.set_value("ctl.cmc.mode", 0)
	lv = rt.systems["lv"]
	fly_launch(800.0)
	assert_true(lv.events.has("insertion"), "insertion without the pogo")
	assert_eq(lv.s2_failed(), 0, "all five")
	var planned := _burns(lv)
	gut.p("without the pogo: the shift commanded at %.2f s (predicted 502.5), the S-II cut off at %.2f (558.11), the S-IVB at %.2f (705.76), insertion %.2f (715.76)" % [
		planned["emr_command"], planned["s2_oeco"], planned["s4_cutoff"], planned["insertion"]])
	assert_almost_eq(float(planned["emr_command"]), 534.7 - 32.2, 3.0, "the shift commanded near the predicted time")
	assert_almost_eq(float(planned["s2_oeco"]), 558.11, 3.0, "the S-II's cutoff near its prediction")
	assert_almost_eq(float(planned["s4_cutoff"]), 705.76, 6.0, "the S-IVB's")
	assert_almost_eq(float(planned["insertion"]), 715.76, 6.0, "insertion's")
	for k: String in TOLL:
		var toll := float(hit[k]) - float(planned[k])
		gut.p("the pogo's toll on %s: %.2f s (flown %.2f against the prediction)" % [k, toll, TOLL[k]])
		assert_almost_eq(toll, float(TOLL[k]), 4.0, "%s: the pogo's toll" % k)


## [param lv]'s launch as the pogo's toll reads it: the shift's command,
## the cutoffs and insertion (GET), and the S-II's and S-IVB's burns (s).
static func _burns(lv: LaunchVehicle) -> Dictionary:
	var e := lv.events
	return {"emr_command": float(e["emr_command"]), "s2_oeco": float(e["s2_oeco"]), "s4_cutoff": float(e["s4_cutoff"]),
		"insertion": float(e["insertion"]), "s2_burn": float(e["s2_oeco"]) - float(e["s2_ignition"]),
		"s4_burn": float(e["s4_cutoff"]) - float(e["s4_ignition"])}


## Panel 1's launch lights at GET [param at] in fly_launch()'s
## [param flight].
func _lights_at(flight: Dictionary, at: float) -> String:
	for l: Array in flight["lights"]:
		if float(l[0]) >= at - 1e-6:
			return l[1]
	return ""


## The GET of the first call with [param words] in it from GET
## [param after] on, or -1.
func _call_get(words: String, after: float = -INF) -> float:
	for c: Array in calls:
		if float(c[0]) >= after and str(c[1]).contains(words):
			return float(c[0])
	return -1.0

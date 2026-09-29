## Slice 10a (docs/ROADMAP.md, milestone 10): Apollo 8 flies from the pad.
## The first crewed Saturn V, AS-503, from its data alone
## (data/missions/apollo_8/mission.json "launch" and "vehicles"
## "saturn_v"), at 12:51 UTC on 21 December 1968 from LC-39A into Apollo
## 8's parking orbit, each stage burning near its flown times, and the
## flight on through TLI as the parking-orbit start flies it
## (tests/scenarios/test_apollo_8.gd). The flown figures are the AS-503
## flight evaluation report's (MPR-SAT-FE-69-1) and the Apollo 8 Mission
## Report's (MSC-PA-R-69-1) [published].
extends SimTest

## AS-503's events, GET s (MPR-SAT-FE-69-1, the sequence of events and
## section 4) [published].
const FLOWN := {
	"tilt": 12.11, "mach_1": 61.48, "max_q": 78.9, "sic_ceco": 125.93, "sic_oeco": 153.82, "staging": 154.47,
	"s2_ignition": 155.19, "interstage_jettison": 184.47, "les_jettison": 188.6, "igm": 196.22, "emr_shift": 443.45,
	"s2_oeco": 524.04, "s4_ignition": 528.29, "s4_cutoff": 684.98, "insertion": 694.98,
}
## At the cutoffs: altitude (km, geodetic), space-fixed velocity (m/s) and
## flight path angle (deg) (ibid., section 4) [published].
const FLOWN_STATES := {
	"sic_ceco": [41.48, 1893.96, 24.527], "sic_oeco": [65.75, 2712.65, 20.699], "s2_oeco": [191.54, 6821.15, 0.646],
	"s4_cutoff": [191.36, 7791.43, -0.001],
}


func test_apollo_8_flies_from_the_pad_into_its_parking_orbit_and_on_through_tli() -> void:
	build("launch", "apollo_8")
	var sq := rt.sequencer
	var lv: LaunchVehicle = rt.systems["lv"]
	assert_eq(sq.phase, "launch")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "all aspects we are still Go")
	Bus.set_value("ctl.cmc.mode", 0)
	# On the pad: the S-IC's start sequence at T-8.9 s, its five engines at
	# thrust by T-1.4 s.
	run(19.0, false)
	assert_true(bool(Bus.get_value("lv.held", false)), "held until the release")
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_almost_eq(float(lv.events.get("thrust_ok", 0.0)), -1.4, 0.1, "all engines running by T-1.4 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")
	var states := {}
	var lights: Array = []
	var p11 := false
	while not lv.events.has("insertion") and SimClock.get_seconds < 800.0:
		run(1.0, false)
		p11 = p11 or rt.agc().program == 11
		lights.append([SimClock.get_seconds, launch_lights()])
		for id in lv.events:
			if not states.has(id):
				states[id] = ascent_state()
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	var lines := PackedStringArray()
	for id in FLOWN:
		var s: Array = states.get(id, [0.0, 0.0, 0.0])
		lines.append("%-19s %7.2f s (flown %7.2f)  %6.1f km  %7.1f m/s  %6.3f deg%s" % [id, float(lv.events.get(id, -1.0)),
			float(FLOWN[id]), s[0], s[1], s[2],
			"  (flown %.1f km, %.1f m/s, %.3f deg)" % FLOWN_STATES[id] if FLOWN_STATES.has(id) else ""])
	gut.p("\n".join(lines))
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 37.2)" % q)
	# The IU's clock: the tilt at AS-503's flown start, the centre engine's
	# cutoff on T1; the cutoffs the propellant brings, to a second.
	assert_almost_eq(float(lv.events["tilt"]), FLOWN["tilt"], 0.1, "the roll and pitch program at 12.11 s")
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	for id in ["sic_oeco", "staging", "s2_ignition", "interstage_jettison", "les_jettison", "igm", "emr_shift"]:
		assert_almost_eq(float(lv.events[id]), FLOWN[id], 1.0, "%s: the S-IC burns out as flown, T3's events on it" % id)
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown")
	assert_almost_eq(float(lv.events["s4_ignition"]), FLOWN["s4_ignition"], 2.0, "the S-IVB's ignition")
	assert_false(lv.events.has("s2_ceco"), "AS-503's S-II burned on all five engines")
	# The S-IC and S-II leave the S-IVB some 40 m/s more to give than
	# AS-503's did (README.md's Fidelity table), and its burn runs long.
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 10.0, "the S-IVB's velocity cutoff near the flown")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 10.0, "insertion at about 11:35")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 8.0, "maximum dynamic pressure, on a standard atmosphere")
	assert_almost_eq(q, 37.2, 4.0, "the flown 37.2 kPa")
	for id in FLOWN_STATES:
		var s: Array = states[id]
		var f: Array = FLOWN_STATES[id]
		assert_almost_eq(float(s[1]), float(f[1]), 50.0, "%s: the velocity" % id)
		assert_almost_eq(float(s[2]), float(f[2]), 1.0, "%s: the flight path angle" % id)
	assert_true(p11, "the CMC in P11 through the ascent")
	for c in [["liftoff", 10.0, "00000 10", "LIFTOFF"], ["sic_ceco", 10.0, "00001 10", "the centre engine out"],
			["s2_ignition", 0.5, "11111 01", "the S-II's engines starting, S-II SEP"],
			["interstage_jettison", -5.0, "00000 01", "the S-II at thrust"],
			["interstage_jettison", 1.0, "00000 00", "the aft interstage gone"],
			["emr_shift", 10.0, "00000 00", "all five J-2s burning on"],
			["s4_ignition", 0.5, "10000 00", "the S-IVB starting"], ["s4_ignition", 10.0, "00000 00", "the S-IVB at thrust"],
			["s4_cutoff", 2.0, "10000 00", "the S-IVB cut off"]]:
		var at := float(lv.events[c[0]]) + float(c[1])
		var seen := ""
		for l: Array in lights:
			if float(l[0]) >= at:
				seen = l[1]
				break
		assert_eq(seen, c[2], "%s: %s" % [c[3], c[0]])

	# The parking orbit: Apollo 8's, 32.5 degrees and about 100 nmi,
	# round (ibid., Table 4-6: 185.18 by 184.41 km, 32.509 deg); the S-IVB
	# with its propellant for TLI (72,727 kg at the second ignition, ibid.,
	# Table 7-11), TLI planned.
	run(20.0, false)
	assert_eq(sq.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	assert_false(rt.dynamics.has_lm(), "the adapter holds LTA-B")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	var sivb := float(Bus.get_value("sivb.prop_kg", 0.0))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (flown 72,727 at its second ignition); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off, sivb,
		Units.hms(float(sq.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 185200.0, 1500.0, "about 100 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 32.509, 0.05, "32.5 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(sivb, 72727.0, 2000.0, "the S-IVB's propellant for TLI")
	assert_false(sq.tli_pad.is_empty(), "TLI planned")

	# On through TLI as the parking-orbit start flies it: GO for TLI at
	# 2:27:22, the IU's TLI at the RTCC's TIG, 2:50:37.1 to 2:55:55.5, 3,040
	# m/s gained (MSC-PA-R-69-1, Table 5-II), C3 -1,478,917 m2/s2 at TLI,
	# 10 s on (MPR-SAT-FE-69-1, Table 4-7).
	var ok := run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 4.0 * 3600.0, 60.0)
	assert_true(ok, "TLI")
	assert_true(sq.timeline_done.has("go_tli"), "GO for TLI")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	var tli: Dictionary = sq.tli_pad
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	gut.p("TLI at %s, %.0f m/s in %.1f s, C3 %.0f m2/s2 (flown 2:50:37.1, 3,040 m/s in 318.4 s, C3 -1,478,917)" % [
		Units.hms(ign), float(tli["dv"]), cut - ign, c3])
	assert_almost_eq(ign, MissionSequencer._get_s("2:50:37.1"), 60.0, "TLI's ignition")
	# The stack 1.5 t lighter than the parking-orbit start's: the S-IVB's
	# first burn, 7 s long, took it.
	assert_almost_eq(cut - ign, 318.4, 8.0, "its burn")
	assert_almost_eq(float(tli["dv"]), 3040.0, 15.0, "the speed it gave")
	assert_almost_eq(c3, -1478917.0, 70000.0, "C3")
	assert_eq(sq.phase, "translunar_coast")

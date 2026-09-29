## Slice 10b (docs/ROADMAP.md, milestone 10): Apollo 10 flies from the pad.
## AS-505 from its data alone (data/missions/apollo_10/mission.json
## "launch" and "vehicles" "saturn_v"), at 16:49 UTC on 18 May 1969 from
## LC-39B, the only Saturn V launched from it, into Apollo 10's parking
## orbit, each stage burning near its flown times, and the flight on
## through TLI as the parking-orbit start flies it
## (tests/scenarios/test_apollo_10.gd). The flown figures are the AS-505
## flight evaluation report's (MPR-SAT-FE-69-7) and the Apollo 10 Mission
## Report's (MSC-00126) [published].
extends SimTest

## AS-505's events, GET s (MPR-SAT-FE-69-7, Tables 2-2, 4-1 and 4-2)
## [published].
const FLOWN := {
	"tilt": 13.05, "mach_1": 66.8, "max_q": 82.6, "sic_ceco": 135.16, "sic_oeco": 161.63, "staging": 162.31,
	"s2_ignition": 163.05, "interstage_jettison": 192.3, "les_jettison": 197.8, "igm": 202.9, "s2_ceco": 460.61,
	"emr_shift": 488.48, "s2_oeco": 552.64, "s4_ignition": 556.81, "s4_cutoff": 703.76, "insertion": 713.76,
}
## At the cutoffs: altitude (km, geodetic), space-fixed velocity (m/s) and
## flight path angle (deg) (ibid., Table 4-2) [published].
const FLOWN_STATES := {
	"sic_ceco": [43.39, 1973.03, 22.807], "sic_oeco": [65.28, 2751.91, 18.946], "s2_ceco": [179.0, 5678.47, 1.029],
	"s2_oeco": [187.43, 6898.24, 0.741], "s4_cutoff": [191.47, 7791.42, -0.0064],
}


func test_apollo_10_flies_from_39b_into_its_parking_orbit_and_on_through_tli() -> void:
	build("launch", "apollo_10")
	var sq := rt.sequencer
	var lv: LaunchVehicle = rt.systems["lv"]
	assert_eq(sq.phase, "launch")
	assert_true(rt.dynamics.has_lm(), "Snoopy in the adapter")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Guidance internal")
	Bus.set_value("ctl.cmc.mode", 0)
	# On LC-39B: its pad, 1.4 nmi north of 39A's.
	var fixed := Bodies.eci_to_earth_fixed(Array(rt.dynamics.traj.earth_state()).slice(0, 3), rt.dynamics.traj.t)
	var pad := Bodies.geographic_to_fixed(28.627306, -80.620869, Bodies.R_EARTH + LaunchVehicle.PAD_HEIGHT_M)
	assert_almost_eq(Vector3(fixed[0] - pad[0], fixed[1] - pad[1], fixed[2] - pad[2]).length(), 0.0, 1.0, "on LC-39B")
	# The S-IC's start sequence at T-8.9 s, its five engines at thrust by
	# T-1.6 s.
	run(19.0, false)
	assert_true(bool(Bus.get_value("lv.held", false)), "held until the release")
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_almost_eq(float(lv.events.get("thrust_ok", 0.0)), -1.6, 0.1, "all engines running by T-1.6 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")
	var flight := fly_launch()
	var states: Dictionary = flight["states"]
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	gut.p(launch_table(flight, FLOWN, FLOWN_STATES))
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 33.2)" % q)
	# The IU's clock: the tilt at AS-505's flown start, the centre engine's
	# cutoff on T1; the cutoffs the propellant brings, to a second.
	assert_almost_eq(float(lv.events["tilt"]), FLOWN["tilt"], 0.1, "the roll and pitch program at 13.05 s")
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	for id in ["sic_oeco", "staging", "s2_ignition", "interstage_jettison", "les_jettison", "igm", "s2_ceco", "emr_shift"]:
		assert_almost_eq(float(lv.events[id]), FLOWN[id], 1.0, "%s: the S-IC burns out as flown, T3's events on it" % id)
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown")
	assert_almost_eq(float(lv.events["s4_ignition"]), FLOWN["s4_ignition"], 2.0, "the S-IVB's ignition")
	# The S-IC and S-II leave the S-IVB some 20 m/s more to give than
	# AS-505's did (README.md's Fidelity table), and its burn runs long.
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 6.0, "the S-IVB's velocity cutoff near the flown")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 6.0, "insertion at about 11:54")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 6.0, "maximum dynamic pressure, on a standard atmosphere")
	assert_almost_eq(q, 33.24, 4.0, "the flown 33.2 kPa")
	for id in FLOWN_STATES:
		var s: Array = states[id]
		var f: Array = FLOWN_STATES[id]
		assert_almost_eq(float(s[1]), float(f[1]), 40.0, "%s: the velocity" % id)
		assert_almost_eq(float(s[2]), float(f[2]), 1.0, "%s: the flight path angle" % id)
	assert_true(flight["p11"], "the CMC in P11 through the ascent")
	for c in [["liftoff", 10.0, "00000 10", "LIFTOFF"], ["sic_ceco", 10.0, "00001 10", "the centre engine out"],
			["s2_ignition", 0.5, "11111 01", "the S-II's engines starting, S-II SEP"],
			["interstage_jettison", 1.0, "00000 00", "the aft interstage gone"],
			["s2_ceco", 10.0, "00001 00", "the S-II's centre engine out"],
			["s4_ignition", 0.5, "10000 00", "the S-IVB starting"], ["s4_ignition", 10.0, "00000 00", "the S-IVB at thrust"],
			["s4_cutoff", 2.0, "10000 00", "the S-IVB cut off"]]:
		assert_eq(lights_after(flight, c[0], c[1]), c[2], "%s: %s" % [c[3], c[0]])

	# The parking orbit: Apollo 10's, 32.5 degrees and about 100 nmi, round
	# (ibid., Table 4-5: 185.79 by 184.66 km, 32.546 deg); the S-IVB with
	# its propellant for TLI (73,462 kg at the second ignition, the
	# S-IVB-505N flight evaluation report, Table 8-1), TLI planned.
	run(20.0, false)
	assert_eq(sq.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	var sivb := float(Bus.get_value("sivb.prop_kg", 0.0))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (73,462 at its second ignition); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off, sivb,
		Units.hms(float(sq.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 185200.0, 1500.0, "about 100 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 32.546, 0.05, "32.5 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(sivb, 73462.0, 2000.0, "the S-IVB's propellant for TLI")
	assert_false(sq.tli_pad.is_empty(), "TLI planned")

	# On through TLI as the parking-orbit start flies it: the IU's TLI at
	# the RTCC's TIG, 2:33:27.6 to 2:39:10.5, 10,025 ft/s gained (MSC-00126,
	# Table 6-II), C3 -1,308,471 m2/s2 at TLI, 10 s on (D5-15560-5, Table
	# 3-V); past the Moon 907.7 nmi up at 76:10:18.4 (MSC-00126, Table
	# 6-III).
	var ok := run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 4.0 * 3600.0, 60.0)
	assert_true(ok, "TLI")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	var tli: Dictionary = sq.tli_pad
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, SimClock.get_seconds + 5.0 * 86400.0)
	var peri := (float(ap["rp"]) - Bodies.R_MOON) / Units.NMI
	var peri_at := Rtcc._pericynthion_time(tr)
	gut.p("TLI at %s, %.0f m/s in %.1f s, C3 %.0f m2/s2; the pericynthion after it %.1f nmi at %s (flown 2:33:28, 3,056 m/s in 342.9 s, C3 -1,308,471; 907.7 nmi at 76:10:18)" % [
		Units.hms(ign), float(tli["dv"]), cut - ign, c3, peri, Units.hms(peri_at)])
	assert_almost_eq(ign, MissionSequencer._get_s("2:33:27.6"), 60.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 342.9, 5.0, "its burn")
	assert_almost_eq(float(tli["dv"]), 3055.6, 15.0, "the speed it gave")
	assert_almost_eq(c3, -1308471.0, 20000.0, "C3")
	assert_almost_eq(peri, 907.7, 10.0, "the free return's pericynthion")
	assert_almost_eq(peri_at, MissionSequencer._get_s("76:10:18.4"), 60.0, "and when")

## Slice 10c (docs/ROADMAP.md, milestone 10): Apollo 12 flies from the pad,
## through the lightning. AS-507 from its data alone
## (data/missions/apollo_12/mission.json "launch" and "vehicles"
## "saturn_v"), at 16:22 UTC on 14 November 1969 from LC-39A into the
## overcast. Lightning strikes it twice, the mission's failures: at 36.5 s
## the fuel cells trip off their buses and the SCE's NORM supply goes, and
## the telemetry it conditions with it; at 52 s the platform tumbles. The
## crew does as Apollo 12's did: SCE to AUX on EECOM's call, the fuel cells
## back on line on the ground's. The Saturn flies on untouched into the
## parking orbit, where P51 finds the platform again before TLI. The flown
## figures are the AS-507 flight evaluation report's (MPR-SAT-FE-70-1), the
## Apollo 12 Mission Report's (MSC-01855), the Mission Director's summary
## report's (M-932-69-12) and the Apollo Flight Journal's [published].
extends SimTest

## AS-507's events, GET s (MPR-SAT-FE-70-1, Table 2-2), the S-II's shift to
## the low mixture ratio as its engines made it (ibid., section 6.5)
## [published].
const FLOWN := {
	"tilt": 12.8, "mach_1": 66.1, "max_q": 81.1, "sic_ceco": 135.24, "sic_oeco": 161.74, "staging": 162.4,
	"s2_ignition": 163.1, "interstage_jettison": 192.4, "les_jettison": 197.9, "igm": 202.5, "s2_ceco": 460.75,
	"emr_shift": 490.0, "s2_oeco": 552.34, "s4_ignition": 556.6, "s4_cutoff": 693.91, "insertion": 703.91,
}
## At the cutoffs: altitude (km, geodetic), space-fixed velocity (m/s) and
## flight path angle (deg) (ibid., Table 4-2) [published].
const FLOWN_STATES := {
	"sic_ceco": [44.7, 1979.5, 23.944], "sic_oeco": [68.1, 2750.7, 20.513], "s2_ceco": [186.1, 5722.7, 0.502],
	"s2_oeco": [190.4, 6959.1, 0.442], "s4_cutoff": [190.9, 7790.8, -0.015],
}

## CAPCOM's calls as they came: [GET, words].
var calls: Array = []


func test_apollo_12_flies_through_the_lightning_into_its_parking_orbit_and_on_through_tli() -> void:
	build("launch", "apollo_12")
	var sq := rt.sequencer
	var lv: LaunchVehicle = rt.systems["lv"]
	var agc := rt.agc()
	sq.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	assert_eq(sq.phase, "launch")
	assert_true(rt.dynamics.has_lm(), "Intrepid in the adapter")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "We're still proceeding")
	assert_eq(int(Bus.get_value("ctl.sce.power")), Sce.NORM, "SCE PWR at NORM for the launch")
	Bus.set_value("ctl.cmc.mode", 0)
	# The S-IC's start sequence at T-8.9 s, its five engines at thrust by
	# T-1.4 s.
	run(19.0, false)
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_almost_eq(float(lv.events.get("thrust_ok", 0.0)), -1.4, 0.1, "all engines running by T-1.4 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")

	# The crew's part, a second at a time, and the panel at the GETs looked
	# at: SCE to AUX at 1:50 on the onboard tape (the Apollo Flight
	# Journal); the fuel cells back on line, 1 and 2 by 142.5 s and 3 at
	# 170.5 s (M-932-69-12, p. 15), each FC switch OFF and a second later ON.
	var panel := {}
	var crew := func() -> void:
		var now := roundf(SimClock.get_seconds)
		if now in [35.0, 38.0, 54.0, 111.0, 143.0, 171.0]:
			panel[now] = _panel()
		match now:
			110.0:
				Bus.set_value("ctl.sce.power", Sce.AUX)
			141.0, 142.0:
				for n in [1, 2]:
					Bus.set_value("ctl.eps.fc%d" % n, now == 142.0)
			169.0, 170.0:
				Bus.set_value("ctl.eps.fc3", now == 170.0)
	var flight := fly_launch(800.0, crew)
	var states: Dictionary = flight["states"]
	for at: float in panel:
		gut.p("%5.0f s  %s" % [at, str(panel[at])])

	# The strikes at 36.5 s, 6,400 ft up, and 52 s, 14,400 ft (MSC-01540,
	# p. 14): the first took all three fuel cells off their buses, the
	# entry batteries carrying the mains at about 24 V under the FC and
	# FC BUS DISCONNECT lights and both UNDERVOLTs, and dropped the SCE out;
	# the second tumbled the platform, ISS at about 50 s (MSC-01855, section
	# 9.2). The CMC ran on.
	assert_almost_eq(float(rt.failures.active.get("fc_bus_trip", -1.0)), 36.5, 0.1, "the first strike at 36.5 s")
	assert_almost_eq(float(rt.failures.active.get("sce_norm", -1.0)), 36.5, 0.1, "the SCE with it")
	assert_almost_eq(float(rt.failures.active.get("imu_tumble", -1.0)), 52.0, 0.1, "the second at 52 s")
	var before: Dictionary = panel[35.0]
	assert_eq(before["lit"], [], "all well before")
	assert_true(before["tm"], "the ground's telemetry good")
	var struck: Dictionary = panel[38.0]
	assert_eq(struck["lit"], ["fc1", "fc2", "fc3", "fc_bus_disconnect", "mn_bus_a_undervolt", "mn_bus_b_undervolt"],
		"the fuel cells off the line, the buses under their limit")
	assert_eq(struck["connected"], [false, false, false], "the talkbacks barber pole")
	assert_between(float(struck["volts"]), 25.0, CautionWarning.UNDERVOLT_V, "on the batteries, 24 V flown")
	assert_true(struck["powered"] and struck["alarm"], "the master alarm, the CMC running on")
	assert_false(struck["tm"], "the telemetry gone with the SCE")
	var tumbled: Dictionary = panel[54.0]
	assert_has(tumbled["lit"], "iss", "ISS")
	assert_eq(tumbled["imu"], "caged", "the platform tumbled")
	assert_true(tumbled["no_att"], "NO ATT")

	# EECOM's "SCE to AUX" at 1:36 and the crew's switch to it bring the
	# telemetry back; the ground's call to reset the fuel cells at 2:19,
	# once it showed them off the line (the Apollo Flight Journal).
	var sce_call := _call_get("Try SCE to Auxiliary")
	var fc_call := _call_get("Try to reset your fuel cells now")
	gut.p("SCE to AUX called at %.1f s (flown 96), the fuel cells' reset at %.1f s (flown 139)" % [sce_call, fc_call])
	assert_almost_eq(sce_call, 96.0, 1.0, "SCE to AUX at 1:36")
	assert_true(panel[111.0]["tm"], "the telemetry back on AUX")
	assert_almost_eq(fc_call, 139.0, 1.0, "the fuel cells' reset at 2:19")
	var reset: Dictionary = panel[143.0]
	assert_eq(reset["connected"], [true, true, false], "fuel cells 1 and 2 back on line")
	assert_false(reset["lit"].has("fc1") or reset["lit"].has("fc2"), "their lights out")
	assert_gt(float(reset["volts"]), CautionWarning.UNDERVOLT_V, "the buses back up")
	var all_back: Dictionary = panel[171.0]
	assert_eq(all_back["connected"], [true, true, true], "and 3")
	assert_eq(all_back["lit"], ["iss"], "all but the platform's light out")

	# The Saturn flew on through it untouched (MPR-SAT-FE-70-1, section
	# 12A): the IU's clock, the tilt at AS-507's flown start and the centre
	# engine's cutoff on T1; the cutoffs the propellant brings, to a
	# second.
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	gut.p(launch_table(flight, FLOWN, FLOWN_STATES))
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 32.7)" % q)
	assert_almost_eq(float(lv.events["tilt"]), FLOWN["tilt"], 0.1, "the roll and pitch program at 12.8 s")
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	for id in ["sic_oeco", "staging", "s2_ignition", "interstage_jettison", "les_jettison", "igm", "s2_ceco", "emr_shift"]:
		assert_almost_eq(float(lv.events[id]), FLOWN[id], 1.0, "%s: the S-IC burns out as flown, T3's events on it" % id)
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown")
	assert_almost_eq(float(lv.events["s4_ignition"]), FLOWN["s4_ignition"], 2.0, "the S-IVB's ignition")
	# The S-IC and S-II leave the S-IVB some 50 m/s more to give than
	# AS-507's did (README.md's Fidelity table), and its burn runs 9 s long.
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 10.0, "the S-IVB's velocity cutoff near the flown")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 10.0, "insertion at about 11:44")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 6.0, "maximum dynamic pressure, on a standard atmosphere")
	assert_almost_eq(q, 32.7, 4.0, "the flown 32.7 kPa")
	for id in FLOWN_STATES:
		var s: Array = states[id]
		var f: Array = FLOWN_STATES[id]
		assert_almost_eq(float(s[1]), float(f[1]), 50.0, "%s: the velocity" % id)
		assert_almost_eq(float(s[2]), float(f[2]), 1.0, "%s: the flight path angle" % id)
	assert_true(flight["p11"], "the CMC in P11 through the ascent")
	for c in [["liftoff", 10.0, "00000 10", "LIFTOFF"], ["sic_ceco", 10.0, "00001 10", "the centre engine out"],
			["s2_ignition", 0.5, "11111 01", "the S-II's engines starting, S-II SEP"],
			["interstage_jettison", 1.0, "00000 00", "the aft interstage gone"],
			["s2_ceco", 10.0, "00001 00", "the S-II's centre engine out"],
			["s4_ignition", 0.5, "10000 00", "the S-IVB starting"], ["s4_ignition", 10.0, "00000 00", "the S-IVB at thrust"],
			["s4_cutoff", 2.0, "10000 00", "the S-IVB cut off"]]:
		assert_eq(lights_after(flight, c[0], c[1]), c[2], "%s: %s" % [c[3], c[0]])

	# The parking orbit: Apollo 12's, 32.5 degrees and about 100 nmi, round
	# (MPR-SAT-FE-70-1, Table 4-5: 185.4 by 181.2 km, 32.540 deg); the
	# S-IVB with its propellant for TLI (73,775 kg to depletion at the
	# second ignition, the parking-orbit start's), TLI planned; the
	# platform still lost.
	run(20.0, false)
	assert_eq(sq.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	var sivb := float(Bus.get_value("sivb.prop_kg", 0.0))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (73,775 at its second ignition); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off, sivb,
		Units.hms(float(sq.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 185200.0, 1500.0, "about 100 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 32.540, 0.05, "32.5 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(sivb, 73775.0, 2000.0, "the S-IVB's propellant for TLI")
	assert_false(sq.tli_pad.is_empty(), "TLI planned")
	var orbit := _panel()
	assert_eq(orbit["lit"], ["iss"], "the platform's light on into orbit")
	assert_eq(orbit["imu"], "caged", "and the platform lost")

	# P51 in the parking orbit's first night, as the crew aligned the
	# platform again on two stars (MSC-01855, section 9.3: Rigel and Sirius,
	# 0.01 deg apart from the catalog's), before TLI: the ISS light out, the
	# REFSMMAT the platform's.
	run(MissionSequencer._get_s("0:45:00") - SimClock.get_seconds)
	var found := p51()
	gut.p("P51 at %s on %s and %s: N05 %.3f deg" % [Units.hms(SimClock.get_seconds), Stars.name_of(found["stars"][0]),
		Stars.name_of(found["stars"][1]), found["sad"]])
	assert_lt(float(found["sad"]), 0.02, "N05")
	assert_true(agc.imu.aligned, "the orientation found")
	assert_lt(misalignment_deg(), 0.02, "the REFSMMAT describes the platform")
	run(1.0, false)
	assert_eq(_panel()["lit"], [], "the ISS light out")
	assert_false(bool(Bus.get_value("dsky.lamp.no_att", false)), "NO ATT out")

	# On through TLI as the parking-orbit start flies it: the IU's TLI at
	# the RTCC's TIG, 2:47:22.7 for 341.3 s (MSC-01855, Table 5-IV), C3
	# -1,834,425 m2/s2 at TLI, 10 s on (MPR-SAT-FE-70-1, Table 4-6); the
	# free return past the Moon 280.2 nmi up at 83:44:04.4 (MSC-01855,
	# Table 5-IV).
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
	gut.p("TLI at %s for %.1f s, C3 %.0f m2/s2; the pericynthion after it %.1f nmi at %s (flown 2:47:22.7 for 341.3 s, C3 -1,834,425; 280.2 nmi at 83:44:04)" % [
		Units.hms(ign), cut - ign, c3, peri, Units.hms(peri_at)])
	assert_almost_eq(ign, MissionSequencer._get_s("2:47:22.7"), 60.0, "TLI's ignition")
	# The stack 1.6 t lighter than the parking-orbit start's: the S-IVB's
	# first burn, 9 s long, took it.
	assert_almost_eq(cut - ign, 341.3, 8.0, "its burn")
	assert_almost_eq(c3, -1834425.0, 20000.0, "C3")
	assert_almost_eq(peri, 280.2, 10.0, "the free return's pericynthion")
	assert_almost_eq(peri_at, MissionSequencer._get_s("83:44:04.4"), 60.0, "and when")


## The panel and the ground's telemetry now: the caution and warning
## lights lit ("lit"), main bus A's volts, the fuel cells' talkbacks
## ("connected"), whether the ground has telemetry ("tm"), the platform's
## mode and NO ATT, the main buses powered and the master alarm.
func _panel() -> Dictionary:
	var lit := []
	for light: String in CautionWarning.LIGHTS:
		if bool(Bus.get_value("cw." + light, false)):
			lit.append(light)
	var connected := []
	for n in [1, 2, 3]:
		connected.append(bool(Bus.get_value("eps.fc%d_connected" % n, false)))
	return {"lit": lit, "volts": float(Bus.get_value("eps.bus_a_v", 0.0)), "connected": connected,
		"tm": bool(Bus.get_value("tm.valid", false)), "imu": str(Bus.get_value("imu.mode", "")),
		"no_att": bool(Bus.get_value("dsky.lamp.no_att", false)), "powered": bool(Bus.get_value("sys.powered", false)),
		"alarm": bool(Bus.get_value("sys.master_alarm", false))}


## The GET of CAPCOM's first call with [param words] in it, or -1.
func _call_get(words: String) -> float:
	for c: Array in calls:
		if str(c[1]).contains(words):
			return float(c[0])
	return -1.0

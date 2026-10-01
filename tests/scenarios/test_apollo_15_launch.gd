## Slice 12b (docs/ROADMAP.md, milestone 12): Apollo 15 flies from the pad.
## AS-510 from its data alone (data/missions/apollo_15/mission.json
## "launch" and "vehicles" "saturn_v"), at 13:34:00 UTC on 26 July 1971
## from LC-39A, on time, on the 80.088 deg azimuth, the first J mission's
## heavier stack into a 90 nmi parking orbit. Houston marks the abort modes
## as the flight passes them, and the IU flies the stack into its parking
## orbit and on through TLI, not a free return. The flown figures are the
## AS-510 flight evaluation report's (MPR-SAT-FE-71-2), the Apollo 15
## Mission Report's (MSC-05161) and the Apollo Flight Journal's
## [published].
extends SimTest

## AS-510's events, GET s (MPR-SAT-FE-71-2, Table 2-2) [published].
const FLOWN := {
	"tilt": 12.2, "mach_1": 65.0, "max_q": 82.0, "sic_ceco": 135.96, "sic_oeco": 159.56, "staging": 161.2,
	"s2_ignition": 161.9, "interstage_jettison": 191.2, "les_jettison": 195.9, "igm": 202.6, "s2_ceco": 459.56,
	"emr_shift": 483.9, "s2_oeco": 549.06, "s4_ignition": 553.2, "s4_cutoff": 694.68, "insertion": 704.67,
}
## At the cutoffs: altitude (km, geodetic), space-fixed velocity (m/s) and
## flight path angle (deg) (ibid., Table 4-2) [published].
const FLOWN_STATES := {
	"sic_ceco": [46.8, 2044.7, 24.217], "sic_oeco": [68.4, 2756.4, 21.266], "s2_ceco": [178.2, 5713.4, -0.285],
	"s2_oeco": [176.3, 6995.0, 0.059], "s4_cutoff": [172.6, 7801.9, 0.013],
}

## CAPCOM's calls as they came: [GET, words].
var calls: Array = []


func test_apollo_15_flies_from_the_pad_into_its_parking_orbit_and_on_through_tli() -> void:
	build("launch", "apollo_15")
	var sq := rt.sequencer
	var lv: LaunchVehicle = rt.systems["lv"]
	sq.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	assert_eq(sq.phase, "launch")
	assert_true(rt.dynamics.has_lm(), "Falcon in the adapter")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "We are Go")
	Bus.set_value("ctl.cmc.mode", 0)
	# The S-IC's start sequence at T-8.9 s, its five engines at thrust by
	# T-1.4 s.
	run(19.0, false)
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_almost_eq(float(lv.events.get("thrust_ok", 0.0)), -1.4, 0.1, "all engines running by T-1.4 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")
	var flight := fly_launch(800.0)
	var states: Dictionary = flight["states"]

	# The IU's clock: the tilt at AS-510's flown start and the centre
	# engine's cutoff on T1; the cutoffs the propellant brings, to a second.
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	gut.p(launch_table(flight, FLOWN, FLOWN_STATES))
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 36.8)" % q)
	assert_almost_eq(float(lv.events["tilt"]), FLOWN["tilt"], 0.1, "the roll and pitch program at 12.2 s")
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	for id in ["sic_oeco", "staging", "s2_ignition", "interstage_jettison", "les_jettison", "igm", "s2_ceco", "emr_shift"]:
		assert_almost_eq(float(lv.events[id]), FLOWN[id], 1.0, "%s: the S-IC burns out as flown, T3's events on it" % id)
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown")
	assert_almost_eq(float(lv.events["s4_ignition"]), FLOWN["s4_ignition"], 2.0, "the S-IVB's ignition")
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 10.0, "the S-IVB's velocity cutoff near the flown")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 10.0, "insertion at about 11:45")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 6.0, "maximum dynamic pressure, on a standard atmosphere")
	assert_almost_eq(q, 36.8, 4.0, "the flown 36.8 kPa")
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

	# Houston's marks of the abort modes, Fullerton's: One Bravo at 0:42,
	# One Charlie at 1:57, mode II with the skirt's separation confirmed at
	# 3:18, the S-IVB to COI at 5:59 and to orbit at 6:46, mode IV at 9:15
	# (the Apollo Flight Journal) [published].
	for m in [[42.0, "One Bravo"], [117.0, "One Charlie"], [198.0, "Mode II"], [359.0, "S-IVB to COI"],
			[406.0, "S-IVB to orbit"], [555.0, "Mode IV"]]:
		assert_almost_eq(_call_get(str(m[1])), float(m[0]), 0.5, "%s at %.0f s" % [m[1], m[0]])

	# The parking orbit: Apollo 15's, 29.68 degrees and about 90 nmi,
	# round (MPR-SAT-FE-71-2, Table 4-4: 169.5 by 166.0 km, 29.679 deg);
	# the S-IVB with its propellant for TLI (75,960 kg to depletion at the
	# second ignition, the parking-orbit start's), TLI planned.
	run(20.0, false)
	assert_eq(sq.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	var sivb := float(Bus.get_value("sivb.prop_kg", 0.0))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (75,960 at its second ignition); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off, sivb,
		Units.hms(float(sq.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 167800.0, 1500.0, "about 90 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 29.679, 0.05, "29.68 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(sivb, 75960.0, 2000.0, "the S-IVB's propellant for TLI")
	assert_false(sq.tli_pad.is_empty(), "TLI planned")

	# On through TLI as the parking-orbit start flies it: the IU's TLI at
	# the RTCC's TIG, 2:50:02.8 for 350.8 s (MSC-05161, Table 3-V(a)), C3
	# -1,438,810 m2/s2 at TLI, 10 s on (MPR-SAT-FE-71-2, Table 4-5); past the
	# Moon 139 nmi up at 78:31:21 (MSC-05161, Table 3-V), not a free return.
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
	gut.p("TLI at %s for %.1f s, C3 %.0f m2/s2; the pericynthion after it %.1f nmi at %s (flown 2:50:02.8 for 350.8 s, C3 -1,438,810; 139 nmi at 78:31:21)" % [
		Units.hms(ign), cut - ign, c3, peri, Units.hms(peri_at)])
	assert_almost_eq(ign, MissionSequencer._get_s("2:50:02.8"), 60.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 350.8, 8.0, "its burn")
	assert_almost_eq(c3, -1438810.0, 20000.0, "C3")
	assert_almost_eq(peri, 139.0, 10.0, "the pericynthion")
	assert_almost_eq(peri_at, MissionSequencer._get_s("78:31:21"), 60.0, "and when")


## The GET of CAPCOM's first call with [param words] in it, or -1.
func _call_get(words: String) -> float:
	for c: Array in calls:
		if str(c[1]).contains(words):
			return float(c[0])
	return -1.0

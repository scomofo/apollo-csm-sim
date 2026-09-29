extends SimTest

## Apollo 11's event times and states from the AS-506 flight evaluation
## report (MPR-SAT-FE-69-9, Tables 2-2, 4-1 and 4-2) [published]: GET s,
## and at the cutoffs altitude (km), space-fixed velocity (m/s) and flight
## path angle (deg).
const FLOWN := {
	"mach_1": 66.3, "max_q": 83.0, "sic_ceco": 135.2, "sic_oeco": 161.63, "s2_ignition": 163.0,
	"interstage_jettison": 192.3, "les_jettison": 197.9, "igm": 204.1, "s2_ceco": 460.6, "emr_shift": 498.0,
	"s2_oeco": 548.22, "s4_ignition": 552.2, "s4_cutoff": 699.34, "insertion": 709.34,
}
const FLOWN_STATES := {
	"sic_ceco": [44.0, 1979.0, 22.957], "sic_oeco": [66.1, 2764.1, 19.114], "s2_ceco": [180.2, 5707.5, 0.897],
	"s2_oeco": [187.3, 6910.1, 0.608], "s4_cutoff": [191.1, 7791.2, 0.015],
}


## Slice 5d's check: from the pad, the Saturn V puts Apollo 11 into its
## parking orbit, each stage burning near the flown times, and the flight
## goes on into the parking orbit with TLI planned.
func test_the_saturn_v_flies_apollo_11_into_its_parking_orbit() -> void:
	build("launch")
	assert_eq(rt.sequencer.phase, "launch")
	var lv: LaunchVehicle = rt.systems["lv"]
	var fixed := Bodies.eci_to_earth_fixed(Array(rt.dynamics.traj.earth_state()).slice(0, 3), rt.dynamics.traj.t)
	# Held on the pad, turning with the Earth, until the holddown arms
	# release; the S-IC's start sequence, and its engines' lights out at
	# thrust.
	run(15.0, false)
	assert_eq(launch_lights(), "11111 00", "the engines not yet at thrust")
	run(4.0, false)
	assert_true(bool(Bus.get_value("lv.held", false)), "held until the release")
	var now := Bodies.eci_to_earth_fixed(Array(rt.dynamics.traj.earth_state()).slice(0, 3), rt.dynamics.traj.t)
	assert_almost_eq(Vector3(now[0] - fixed[0], now[1] - fixed[1], now[2] - fixed[2]).length(), 0.0, 0.01, "on the pad")
	assert_almost_eq(float(lv.events.get("ignition", 0.0)), -8.9, 0.1, "the start sequence at T-8.9 s")
	assert_almost_eq(float(lv.events.get("thrust_ok", 0.0)), -1.6, 0.1, "all engines at thrust by T-1.6 s")
	assert_eq(launch_lights(), "00000 00", "all five at thrust")
	var flight := fly_launch()
	var states: Dictionary = flight["states"]
	for id in FLOWN:
		assert_true(lv.events.has(id), id)
	gut.p(launch_table(flight, FLOWN, FLOWN_STATES))
	# The stages' events: the clock's to a step, the cutoffs of the
	# propellant and the guidance to seconds.
	assert_almost_eq(float(lv.events["sic_ceco"]), FLOWN["sic_ceco"], 0.1, "the centre engine's cutoff on the IU's clock")
	assert_almost_eq(float(lv.events["sic_oeco"]), FLOWN["sic_oeco"], 1.0, "the S-IC burns out as flown")
	assert_almost_eq(float(lv.events["s2_oeco"]), FLOWN["s2_oeco"], 2.0, "the S-II burns out as flown")
	assert_almost_eq(float(lv.events["s4_cutoff"]), FLOWN["s4_cutoff"], 4.0, "the S-IVB's velocity cutoff near the flown")
	assert_almost_eq(float(lv.events["insertion"]), FLOWN["insertion"], 4.0, "insertion at about 11:49")
	assert_almost_eq(float(lv.events["mach_1"]), FLOWN["mach_1"], 2.0, "Mach 1")
	assert_almost_eq(float(lv.events["max_q"]), FLOWN["max_q"], 6.0, "maximum dynamic pressure")
	var q := float(Bus.get_value("lv.max_q_pa", 0.0)) / 1000.0
	gut.p("maximum dynamic pressure %.1f kPa (flown 35.2)" % q)
	assert_almost_eq(q, 35.2, 4.0, "the flown 35.2 kPa")
	for id in FLOWN_STATES:
		var s: Array = states[id]
		var f: Array = FLOWN_STATES[id]
		# The report's altitudes are geodetic, over the ellipsoid; ours over
		# the round Earth of the equatorial radius, which near 30 degrees
		# north runs 5 to 6 km above it: compare the altitude over the pad.
		assert_almost_eq(float(s[1]), float(f[1]), 40.0, "%s: the velocity" % id)
		assert_almost_eq(float(s[2]), float(f[2]), 1.0, "%s: the flight path angle" % id)
	assert_true(flight["p11"], "the CMC in P11 through the ascent")
	# The main display console's launch lights through the ascent: LV ENGINE
	# 1 to 5, LIFTOFF, S-II SEP.
	for c in [["liftoff", 10.0, "00000 10", "LIFTOFF"], ["sic_ceco", 10.0, "00001 10", "the centre engine out"],
			["s2_ignition", 0.5, "11111 01", "the S-II's engines starting, S-II SEP"],
			["interstage_jettison", -5.0, "00000 01", "the S-II at thrust"],
			["interstage_jettison", 1.0, "00000 00", "the aft interstage gone"],
			["s2_ceco", 10.0, "00001 00", "the S-II's centre engine out"],
			["s4_ignition", 0.5, "10000 00", "the S-IVB starting"], ["s4_ignition", 10.0, "00000 00", "the S-IVB at thrust"],
			["s4_cutoff", 2.0, "10000 00", "the S-IVB cut off"]]:
		assert_eq(lights_after(flight, c[0], c[1]), c[2], "%s: %s" % [c[3], c[0]])
	# The parking orbit: Apollo 11's, 32.5 degrees and about 100 nmi,
	# round.
	run(20.0, false)
	assert_eq(rt.sequencer.phase, "parking_orbit")
	assert_eq(rt.dynamics.config, "stack")
	assert_eq(launch_lights(), "00000 00", "the launch lights out in orbit")
	var c: Dictionary = rt.dynamics.traj.conic()
	var h: Vector3 = c["h"]
	var incl := rad_to_deg(h.normalized().angle_to(Bodies.earth_omega().normalized()))
	var target: Dictionary = lv.target
	var off := rad_to_deg(h.normalized().angle_to(Vector3(target["n"][0], target["n"][1], target["n"][2])))
	gut.p("parking orbit %.1f x %.1f km, inclination %.3f deg, %.4f deg from the flown plane; the S-IVB left with %.0f kg (flown 74,452 at its second start); TLI at %s" % [
		(float(c["ra"]) - Bodies.R_EARTH) / 1000.0, (float(c["rp"]) - Bodies.R_EARTH) / 1000.0, incl, off,
		float(Bus.get_value("sivb.prop_kg", 0.0)), Units.hms(float(rt.sequencer.tli_pad.get("tig", -1.0)))])
	assert_almost_eq((float(c["ra"]) + float(c["rp"])) / 2.0 - Bodies.R_EARTH, 185000.0, 1500.0, "about 100 nmi")
	assert_lt(float(c["ra"]) - float(c["rp"]), 3000.0, "round")
	assert_almost_eq(incl, 32.52, 0.05, "32.5 degrees")
	assert_lt(off, 0.02, "in the flown plane")
	assert_almost_eq(float(Bus.get_value("sivb.prop_kg", 0.0)), 74452.0, 1000.0, "the S-IVB's propellant for TLI")
	assert_false(rt.sequencer.tli_pad.is_empty(), "TLI planned")
	assert_almost_eq(float(rt.sequencer.tli_pad["tig"]), 2.0 * 3600.0 + 44.0 * 60.0 + 16.2, 60.0, "TLI near the flown 2:44:16")


## A checkpoint taken on the S-II's burn flies on to the same insertion:
## the vehicle's program, its stages and its guidance come back with it.
func test_a_checkpoint_mid_launch_flies_on_to_the_same_insertion() -> void:
	build("launch")
	var lv: LaunchVehicle = rt.systems["lv"]
	run(300.0 - SimClock.get_seconds, false)
	assert_eq(lv.stage, "S-II")
	var snap := rt.snapshot()
	assert_true(run_until(func() -> bool: return lv.events.has("s4_cutoff"), 500.0, 1.0, false))
	var cut := float(lv.events["s4_cutoff"])
	var s1 := rt.dynamics.traj.earth_state()
	assert_eq(rt.restore(snap), "")
	assert_eq(lv.stage, "S-II")
	assert_true(run_until(func() -> bool: return lv.events.has("s4_cutoff"), 500.0, 1.0, false))
	var s2 := rt.dynamics.traj.earth_state()
	var dr := Vector3(s1[0] - s2[0], s1[1] - s2[1], s1[2] - s2[2]).length()
	var dv := Vector3(s1[3] - s2[3], s1[4] - s2[4], s1[5] - s2[5]).length()
	gut.p("restored mid-S-II: cutoff %.3f s apart, %.1f m and %.3f m/s from the uninterrupted flight" % [
		float(lv.events["s4_cutoff"]) - cut, dr, dv])
	assert_almost_eq(float(lv.events["s4_cutoff"]), cut, 0.05, "the same cutoff, within a step")
	assert_lt(dv, 0.1, "and the same velocity")


## Slice 5f: the CMC's entry programs, P61 to P67, on Colossus's entry
## guidance (src/systems/entry_guidance.gd). P61 predicts the entry as
## Apollo 11's entry PAD did, and from entry interface the CM comes down
## within SPLASH_LIMIT_NMI of its target from the range Apollo 11 had
## planned, shorter than the one it flew, and from a long one, which skips
## out through P66 (test_lunar_mission.gd flies Apollo 11's own, to its
## target 1,500 nmi from entry interface).
extends SimTest

## How near the target the CM comes down, nmi: Apollo splashdowns came
## within this of theirs, Apollo 11's 1.7 nmi from it by the CMC's own
## reckoning (the Apollo 11 Mission Report, MSC-00171) [published].
const SPLASH_LIMIT_NMI := 3.0


## The distance from the target (latitude, east longitude, deg) the CM
## came down, nmi.
func _miss_nmi(target: Vector2) -> float:
	return Bodies.surface_angle(rt.sequencer.geographic(), target) * Bodies.R_EARTH / Units.NMI


## Load the target (N61) at P61's first display, V25 over its latitude and
## longitude, and fly the entry.
func _fly_to(target: Vector2) -> Dictionary:
	var agc := rt.agc()
	keys("V37E61E")
	keys("V25E%+06dE%+06dE-00001E" % [roundi(target.x * 100.0), roundi(target.y * 100.0)])
	assert_almost_eq(Vector2(agc.entry_lat, agc.entry_lng), target, Vector2(0.006, 0.006), "N61 loaded")
	# fly_entry() keys V37E61E again, which starts P61 over with the target
	# kept.
	var f := fly_entry()
	gut.p("Target %s: programs %s, peaks %s, N67 %s; down %.2f nmi from it at %s" % [str(target), str(f["programs"]),
		str(f["peaks"].map(func(x: float) -> float: return snappedf(x, 0.01))), str(f["n67"]), _miss_nmi(target),
		Units.hms(SimClock.get_seconds)])
	assert_true(rt.dynamics.landed, "down")
	assert_eq(rt.sequencer.phase, "splashdown")
	assert_lt(rt.dynamics.max_g, 8.0, "the G limiter's 8 g")
	return f


func test_p61_predicts_the_entry_pad() -> void:
	build("entry")
	var agc := rt.agc()
	keys("V37E61E")
	assert_eq([agc.program, agc.dsky.verb, agc.dsky.noun, agc.dsky.flashing], [61, "06", "61", true])
	# N61: the target the entry PAD's uplink brought, and lift up.
	assert_eq(agc.dsky.r, ["+01332", "-16917", "-00001"] as Array[String], "13.32 N, 169.17 W, HEADSUP -1")
	keys("P")
	# N60 against Apollo 11's final entry PAD (191:43:57; the 194:16 update
	# took the load to 6.3 g and gamma to -6.48 deg) [published]: 6.4 g,
	# 36,194 ft/s at 400,000 ft, 6.49 deg down.
	var n60: Array = agc.noun_values(60)
	gut.p("N60 %s  N63 RTGO %.1f nmi, VIO %.0f ft/s" % [str(agc.dsky.r), float(agc.entry_pred["rtgo"]),
		float(agc.entry_pred["vio"]) / Units.FT])
	assert_almost_eq(float(n60[0]), 6.4, 0.5, "GMAX")
	assert_almost_eq(float(n60[1]) / Units.FT, 36194.0, 15.0, "VPRED")
	assert_almost_eq(float(n60[2]), -6.49, 0.1, "GAMMAEI")
	keys("P")
	# N63: the EMS's range to go and speed at 297,431 ft, 1,404.5 nmi and
	# 36,275 ft/s on the PAD; the range as Colossus's DISPTARG reckons it
	# comes some 2% longer [estimated: the RTCC's EMS range isn't the CMC's].
	var n63: Array = agc.noun_values(63)
	assert_almost_eq(float(n63[0]), 1404.5, 45.0, "RTGO")
	assert_almost_eq(float(n63[1]) / Units.FT, 36275.0, 15.0, "VIO")
	assert_lt(float(n63[2]), 0.0, "TTE counting down")
	keys("P")
	assert_eq([agc.program, agc.dsky.verb, agc.dsky.noun, agc.dsky.r[0]], [62, "50", "25", " 00041"],
		"P62: please perform CM/SM SEP")
	# The entry PAD's own prediction, from the state the ground tracked
	# (the entry start phase passes its time by).
	var pad := Rtcc.plan_entry(rt.dynamics.traj, 13.32, -169.17)
	assert_almost_eq(float(pad["gmax"]), float(n60[0]), 0.2)
	assert_string_contains(Rtcc.pad_text(pad), "ENTRY PAD: N61 LAT +13.32 LONG -169.17")
	# P63 to P67 follow the guidance: V37 doesn't take them.
	keys("V37E64E")
	assert_eq(agc.program, 62, "V37E64E refused")
	assert_true(agc.dsky.lamps["opr_err"])


func test_from_the_shorter_range_apollo_11_had_planned() -> void:
	# The target in Apollo 11's TEI PAD, before the weather moved it: 1,266
	# nmi from entry interface. No up-control: P64 hands over to P67.
	build("entry")
	var target := Vector2(11.03, -172.37)
	var f := _fly_to(target)
	assert_false(65 in f["programs"], "no P65")
	assert_eq(f["programs"].slice(0, 4), [61, 62, 63, 64])
	assert_true(67 in f["programs"])
	assert_lt(_miss_nmi(target), SPLASH_LIMIT_NMI, "down near the target")


func test_from_a_long_range_through_the_skip() -> void:
	# 2,000 nmi from entry interface along the ground track: the up-control
	# lifts the CM out of the air, and P66 flies the ballistic arc to the
	# final phase.
	build("entry")
	var target := Vector2(18.61, -162.42)
	var f := _fly_to(target)
	assert_eq(f["programs"].slice(0, 7), [61, 62, 63, 64, 65, 66, 67], "P65, P66, P67")
	assert_lt(_miss_nmi(target), SPLASH_LIMIT_NMI, "down near the target")

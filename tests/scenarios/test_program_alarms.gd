## Slice 9b's check (docs/ROADMAP.md, milestone 9): Apollo 11's landing
## with the rendezvous radar's mode switch as flown brings 1202 and 1201
## alarms 5 to 10 minutes after PDI, as it did, and still lands within the
## Fidelity table's limits; with the switch at LGC none come.
##
## The crew fly it as Apollo 11's did (the air-to-ground transcript and
## Eyles, "Tales from the Lunar Module Guidance Computer", 2004). Armstrong
## turns the radar's switch from AUTO TRACK to SLEW 2 min 33 s after PDI
## (102:35:38 GET), or, for the second flight, to LGC. Aldrin keys V16N68
## for ΔH once the landing radar's altitude is good, and V57 and V16N68
## again 54 s later; at each alarm he keys V05N09 for its code and RSET.
## A restart takes the crew's display away, and after the second he calls
## up N68 no more. In P64 KEY REL gives the program its display. Armstrong
## takes the attitude in ATT HOLD at 102:43:08, 10 min 3 s after PDI,
## zeroing the error needles by hand, and out of AUTO the LGC's landing
## point designator stops; at 430 ft he takes over in P66 and lands by
## hand. Both flights start from one checkpoint taken before PDI.
extends SimTest

const SITE_LAT := 0.674
const SITE_LON := 23.473
## When Armstrong turned the radar's switch and took the attitude in ATT
## HOLD, s after PDI [published: 102:35:38 and 102:43:08 GET, PDI at
## 102:33:05].
const SWITCH_S := 153.0
const ATT_HOLD_S := 603.0
## Armstrong's height at P66, m [published: 430 ft, 102:43:20].
const P66_M := 131.0
## V57 after the radar's altitude came good, s [published: 102:37:51 and
## 102:38:45 GET, the Apollo 11 Mission Report's table 5-I].
const V57_AFTER_S := 54.0

var _before_pdi := ""


func before_all() -> void:
	build("lunar_descent")
	run_until(func() -> bool: return rt.sequencer.pads.has("pdi"), 600.0, 1.0)
	_before_pdi = JSON.stringify(rt.snapshot())


## Fly the descent from the checkpoint with the radar's switch turned to
## [param rr_mode] as Armstrong turned it, the crew as Apollo 11's. Returns
## what happened: "alarms" [{code, t (s after PDI), program, n09}], "calls"
## (CAPCOM's), "peak_load", "lr_good" (s after PDI) and "t_ig".
func _fly(rr_mode: int) -> Dictionary:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	var lgc := rt.lgc()
	assert_false(lgc.rr_cdu_zeroed, "Apollo 11's Luminary 1A counts the radar's CDUs")
	assert_eq(int(Bus.get_value("ctl.lm.rr_mode")), 1, "AUTO TRACK, since the radar's test after DOI")
	var seen := {"alarms": [], "calls": [], "peak_load": 0.0, "lr_good": -1.0, "n68": 0}
	rt.sequencer.capcom.connect(func(text: String) -> void: seen["calls"].append(text))
	keys("V37E63E", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	var t_ig := lgc.pdi_tig
	seen["t_ig"] = t_ig
	var in_p64 := run_until(func() -> bool:
		_crew(lgc, seen, rr_mode, SimClock.get_seconds - t_ig)
		return lgc.program == 64 and SimClock.get_seconds - t_ig >= ATT_HOLD_S, 900.0, 1.0, false)
	assert_true(in_p64, "P64 at 102:43:08")
	# Armstrong: ATT HOLD, the error needles zeroed on the hand controller,
	# and at 430 ft the ROD switch takes P66.
	Bus.set_value("ctl.lm.mode", 1)
	while lgc.program == 64 and lgc._h > P66_M:
		var err: Vector3 = lgc._error_vector(lgc.desired_q)
		Bus.set_value("ctl.lm.rhc", (err / (2.0 * AgcCore.RATE_HOLD)).clamp(-Vector3.ONE, Vector3.ONE))
		run(0.2, false)
		_crew(lgc, seen, rr_mode, SimClock.get_seconds - t_ig)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	gut.p("P66 %.0f s after PDI, %.0f m up, %.0f m from the site" % [SimClock.get_seconds - t_ig, lgc._h, _miss()])
	rod_click(-1)
	assert_eq(lgc.program, 66, "P66")
	var t0 := SimClock.get_seconds
	while not rt.dynamics.lm.landed and SimClock.get_seconds - t0 < 400.0:
		fly_by_hand(lgc)
		seen["peak_load"] = maxf(float(seen["peak_load"]), lgc.executive.load)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_true(rt.dynamics.lm.landed, "touchdown")
	return seen


## Aldrin at the DSKY, and Armstrong at the radar's switch, [param t] s
## after PDI.
func _crew(lgc: Lgc, seen: Dictionary, rr_mode: int, t: float) -> void:
	if t >= SWITCH_S and int(Bus.get_value("ctl.lm.rr_mode")) != rr_mode:
		Bus.set_value("ctl.lm.rr_mode", rr_mode)
	if t > SWITCH_S + 1.0:
		seen["peak_load"] = maxf(float(seen["peak_load"]), float(Bus.get_value("lm.guid.exec_load", 0.0)))
	if lgc.restarts > seen["alarms"].size():
		# PROG: V05N09 for the code, then RSET.
		keys("V05N09E", lgc)
		seen["alarms"].append({"code": lgc.restart_alarm, "t": t, "program": lgc.program,
			"n09": Array(lgc.dsky.r)})
		keys("R", lgc)
	var alt_good := not bool(Bus.get_value("lm.dsky.lamp.alt", true)) and lgc.delta_h != 0.0
	if alt_good and seen["lr_good"] < 0.0:
		seen["lr_good"] = t
	# V16N68 for ΔH once the radar has it; V57 54 s later, as Aldrin keyed
	# it, and V16N68 again; not after that.
	if alt_good and lgc.program == 63 and seen["n68"] == 0:
		seen["n68"] = 1
		keys("V16N68E", lgc)
	elif seen["n68"] == 1 and t >= float(seen["lr_good"]) + V57_AFTER_S:
		seen["n68"] = 2
		keys("V57E", lgc)
		if lgc.program == 63:
			keys("V16N68E", lgc)
	# P64: the program's display back, N64 and the LPD.
	if lgc.program == 64 and lgc.dsky.lamps["key_rel"]:
		keys("K", lgc)


## Eagle's distance from the site on the surface, m.
func _miss() -> float:
	var at := Bodies.fixed_to_selenographic(Bodies.moon_fixed(SimClock.get_seconds).transposed()
		* rt.dynamics.lm.traj.pos())
	var d := Vector2(deg_to_rad(at.x - SITE_LAT), deg_to_rad(at.y - SITE_LON) * cos(deg_to_rad(SITE_LAT)))
	return d.length() * Bodies.R_MOON


func _landed_within_limits(seen: Dictionary) -> void:
	var td: Dictionary = rt.dynamics.lm.touchdown
	var t_ig := float(seen["t_ig"])
	gut.p("Eagle landed %.0f m from the site, %.2f m/s down and %.2f m/s across, %.0f s after PDI" % [
		_miss(), td["vertical_mps"], td["horizontal_mps"], float(td["get_s"]) - t_ig])
	assert_lt(_miss(), 500.0, "within 500 m of the site")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_between(float(td["get_s"]) - t_ig, 11.0 * 60.0, 14.0 * 60.0, "the descent's time, Apollo 11's 12 min 35 s")


func test_the_landing_as_flown_brings_1202_and_1201_alarms() -> void:
	var seen := _fly(2)
	for a: Dictionary in seen["alarms"]:
		gut.p("%.0f s after PDI, P%d: %d  (V05N09 %s)" % [a["t"], a["program"], a["code"], str(a["n09"])])
	gut.p("Radar altitude good %.0f s after PDI; the LGC's peak load %.0f %%" % [seen["lr_good"], 100.0 * seen["peak_load"]])
	var alarms: Array = seen["alarms"]
	var codes := alarms.map(func(a: Dictionary) -> int: return a["code"])
	assert_has(codes, 1202, "1202: no core sets")
	assert_has(codes, 1201, "1201: no VAC areas")
	for a: Dictionary in alarms:
		assert_between(float(a["t"]), 300.0, 600.0, "%d between 5 and 10 minutes after PDI" % a["code"])
		assert_eq(a["n09"][0], " %05d" % a["code"], "V05N09 shows it")
	assert_eq(alarms[0]["code"], 1202, "the first a 1202, with N68 up in P63")
	assert_eq(alarms[0]["program"], 63)
	assert_true(alarms.any(func(a: Dictionary) -> bool: return a["code"] == 1201 and a["program"] == 64), "a 1201 in P64")
	assert_eq(rt.lgc().restarts, alarms.size(), "each alarm a restart")
	var calls: Array = seen["calls"]
	assert_true(calls.any(func(c: String) -> bool: return c.contains("we're GO on that alarm")), "Houston's GO")
	assert_true(calls.any(func(c: String) -> bool: return c.contains("Same type")), "and on those after it")
	assert_gt(float(seen["peak_load"]), 1.0, "more than the LGC had")
	_landed_within_limits(seen)


func test_with_the_switch_at_lgc_none_come() -> void:
	var seen := _fly(0)
	gut.p("Radar altitude good %.0f s after PDI; the LGC's peak load %.0f %%" % [seen["lr_good"], 100.0 * seen["peak_load"]])
	assert_eq(seen["alarms"], [], "no alarms")
	assert_eq(rt.lgc().restarts, 0)
	assert_false(rt.lgc().dsky.lamps["prog"], "PROG dark")
	assert_between(float(seen["peak_load"]), 0.85, 0.95, "the descent's peak, about 90 % of the LGC")
	_landed_within_limits(seen)

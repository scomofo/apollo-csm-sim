## Shared harness for Apollo simulator tests: builds a headless runtime,
## drives the DSKY and steps simulated time deterministically.
class_name SimTest
extends GutTest

var rt: SimRuntime


func build(phase: String = "") -> SimRuntime:
	Bus.reset()
	SimClock.reset()
	rt = SimRuntime.build(self)
	for n in rt.nodes:
		autofree(n)
	if phase != "":
		rt.sequencer.start(phase)
	return rt


## Advance [param seconds] of simulated time. Coast steps are used when
## [param fast] (rate 1000), fixed 0.02 s steps otherwise.
func run(seconds: float, fast: bool = true) -> void:
	SimClock.rate = 1000.0 if fast else 1.0
	SimClock.advance(seconds)


## Step until [param cond] holds or [param max_s] passes; returns whether
## the condition was met.
func run_until(cond: Callable, max_s: float, chunk: float = 60.0, fast: bool = true) -> bool:
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		if cond.call():
			return true
		run(minf(chunk, end - SimClock.get_seconds), fast)
	return cond.call()


func keys(seq: String) -> void:
	# "V37E40E" style: V=VERB N=NOUN E=ENTR P=PRO C=CLR K=KEY REL R=RSET
	for ch in seq:
		match ch:
			"V": rt.agc().dsky.press("VERB")
			"N": rt.agc().dsky.press("NOUN")
			"E": rt.agc().dsky.press("ENTR")
			"P": rt.agc().dsky.press("PRO")
			"C": rt.agc().dsky.press("CLR")
			"K": rt.agc().dsky.press("KEY REL")
			"R": rt.agc().dsky.press("RSET")
			" ": pass
			_: rt.agc().dsky.press(ch)


## Fly an uplinked PAD the way the crew does: P30 accept, P40 (SPS) or,
## below 10 ft/s, P41 (RCS) with auto maneuver, SPS armed, PRO at V99, PRO
## after residuals. Returns the maneuver's sensed ΔV (m/s).
func fly_pad() -> float:
	var agc := rt.agc()
	Bus.set_value("ctl.cmc.mode", 2)
	keys("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	keys("PPP")
	assert_true(agc.maneuver_valid, "maneuver stored")
	var prog := 41 if agc.dv_lvlh_load.length() < 10.0 * Units.FT else 40
	keys("V37E%dE" % prog)
	assert_eq(agc.program, prog, "P40/P41 selected")
	keys("P")   # V50N18: perform auto maneuver
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.arm_b", true)
	var tig := agc.maneuver_tig
	var ok := run_until(func() -> bool: return agc.step_name == "v99", tig - SimClock.get_seconds + 10.0, 30.0)
	assert_true(ok, "reached V99 before TIG")
	keys("P")
	ok = run_until(func() -> bool: return agc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	var dv := agc.dv_accum
	keys("P")
	Bus.set_value("ctl.sps.arm_a", false)
	Bus.set_value("ctl.sps.arm_b", false)
	Bus.set_value("ctl.cmc.mode", 1)
	return dv

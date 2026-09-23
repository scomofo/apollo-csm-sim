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


## Key [param seq] into the CMC's DSKY, or [param computer]'s (the LGC's).
func keys(seq: String, computer: AgcCore = null) -> void:
	# "V37E40E" style: V=VERB N=NOUN E=ENTR P=PRO C=CLR K=KEY REL R=RSET
	var dsky := (computer if computer != null else rt.agc()).dsky
	for ch in seq:
		match ch:
			"V": dsky.press("VERB")
			"N": dsky.press("NOUN")
			"E": dsky.press("ENTR")
			"P": dsky.press("PRO")
			"C": dsky.press("CLR")
			"K": dsky.press("KEY REL")
			"R": dsky.press("RSET")
			" ": pass
			_: dsky.press(ch)


## Fly an uplinked PAD the way the crew does: P30 accept; a quarter of an
## hour before TIG, CMC MODE AUTO and P40 (SPS) or, below 10 ft/s, P41
## (RCS) with auto maneuver; SPS armed, PRO at V99, PRO after residuals.
## The spacecraft drifts in CMC MODE FREE until P40 and after the burn:
## P40's steering, or an attitude hold, keeps the clock to fixed steps.
## Returns the maneuver's sensed ΔV (m/s).
func fly_pad() -> float:
	var agc := rt.agc()
	keys("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	keys("PPP")
	assert_true(agc.maneuver_valid, "maneuver stored")
	var tig := agc.maneuver_tig
	Bus.set_value("ctl.cmc.mode", 0)
	run(maxf(tig - 900.0 - SimClock.get_seconds, 0.0))
	Bus.set_value("ctl.cmc.mode", 2)
	var prog := 41 if agc.dv_lvlh_load.length() < 10.0 * Units.FT else 40
	keys("V37E%dE" % prog)
	assert_eq(agc.program, prog, "P40/P41 selected")
	keys("P")   # V50N18: perform auto maneuver
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.arm_b", true)
	# Second by second from TIG-12 s, so PRO at V99 comes at TIG-5 s.
	run(maxf(tig - 12.0 - SimClock.get_seconds, 0.0))
	var ok := run_until(func() -> bool: return agc.step_name == "v99", 20.0, 1.0, false)
	assert_true(ok, "reached V99 before TIG")
	keys("P")
	ok = run_until(func() -> bool: return agc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	var dv := agc.dv_accum
	keys("P")
	Bus.set_value("ctl.sps.arm_a", false)
	Bus.set_value("ctl.sps.arm_b", false)
	Bus.set_value("ctl.cmc.mode", 0)
	return dv


## Fly a PAD uplinked to the LGC the way the LM crew does: P30 accept; a
## quarter of an hour before TIG, LGC MODE AUTO and the thrusting program
## [param prog] (P40 on the DPS, P41 on the RCS, P42 on the APS) with auto
## maneuver; ENGINE ARM at
## [param arm] (2 DES, 1 ASC, 0 for the RCS), PRO at V99, PRO after
## residuals; then ENGINE ARM OFF and MODE FREE. [param monitor], if
## given, is called at each second of the countdown and the burn. Returns
## the maneuver's sensed ΔV (m/s).
func fly_lm_pad(prog: int, arm: int, monitor: Callable = Callable()) -> float:
	var lgc := rt.lgc()
	keys("V37E30E", lgc)
	assert_eq(lgc.program, 30, "LGC P30 selected")
	keys("PPP", lgc)
	assert_true(lgc.maneuver_valid, "maneuver stored in the LGC")
	var tig := lgc.maneuver_tig
	run(maxf(tig - 900.0 - SimClock.get_seconds, 0.0))
	Bus.set_value("ctl.lm.mode", 2)
	keys("V37E%dE" % prog, lgc)
	assert_eq(lgc.program, prog, "P%d selected" % prog)
	keys("P", lgc)   # V50N18: perform auto maneuver
	Bus.set_value("ctl.lm.engine_arm", arm)
	run(maxf(tig - 12.0 - SimClock.get_seconds, 0.0))
	var ok := run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false)
	assert_true(ok, "reached V99 before TIG")
	keys("P", lgc)
	ok = run_until(func() -> bool:
		if monitor.is_valid():
			monitor.call()
		return lgc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	var dv := lgc.dv_accum
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	Bus.set_value("ctl.lm.mode", 0)
	return dv

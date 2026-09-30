## Shared harness for Apollo simulator tests: builds a headless runtime,
## drives the DSKY and steps simulated time deterministically. For the
## harnesses with presentation on top (CabinTest, DesktopTest) it flies in
## chunks with a frame between them, and holds keys down for
## HandControllerInput.
class_name SimTest
extends GutTest

## The THC's detent: a smaller deflection commands nothing (src/systems/rcs.gd).
const CSM_THC_DETENT := 0.05
## Translation jets per body axis: all four quads fire along X, two along
## Y and Z (src/systems/rcs.gd).
const CSM_JETS := Vector3(4, 2, 2)

## Translation jets per LM body axis, both systems: X four, Y and Z two;
## and the TTCA's detent (src/systems/lm_rcs.gd).
const LM_JETS := Vector3(4, 2, 2)
const LM_TTCA_DETENT := 0.05
## The LM commander's braking gates: the closing rate allowed from each
## range in, m and m/s: 30 ft/s from a mile, 20 from 3,000 ft, 10 from
## 1,500 ft, 5 from 500 ft, and a stop 40 m out [estimated].
const LM_BRAKING_GATES := [[1852.0, 9.14], [914.0, 6.1], [457.0, 3.05], [152.0, 1.52], [40.0, 0.0]]

var rt: SimRuntime
var _held_keys: Array[Key] = []
## fly_pad()'s last burn: the truth (Trajectory) at V99 ("before") and once
## the engine has stopped ("after").
var burn_log: Dictionary = {}


## A test that stopped with a key down leaves Input clean for the next,
## and one that ran the clock fast (run()) leaves it at real time: above
## the interactive rates SimClock locks the cabin's controls, for the tests
## in the files after it too.
func after_each() -> void:
	for k in _held_keys:
		_key_event(k, false)
	_held_keys.clear()
	SimClock.rate = 1.0


## Build the runtime for mission [param mission] (an id under
## data/missions/), started in [param phase] unless it's empty.
func build(phase: String = "", mission: String = Mission.DEFAULT_ID) -> SimRuntime:
	Bus.reset()
	SimClock.reset()
	rt = SimRuntime.build(self, Mission.path_of(mission))
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
		run(_chunk(chunk, end), fast)
	return cond.call()


## The next chunk toward GET [param end], at most [param chunk], and a
## step at least: the clock steps whole FIXED_DTs, so a shorter remainder
## would only pile up in its accumulator, a call at a time, until it made
## a step (17,500 calls for a microsecond's remainder).
func _chunk(chunk: float, end: float) -> float:
	return maxf(minf(chunk, end - SimClock.get_seconds), SimClock.FIXED_DT)


## Fly [param seconds], in chunks with a frame between them, so the
## presentation (the HUD, the cabin's card and highlight) and the hand
## controllers keep up with the Bus as they do in flight.
func fly(seconds: float, chunk: float = 60.0, fast: bool = true) -> void:
	await fly_until(func() -> bool: return false, seconds, chunk, fast)


## Fly until [param cond] holds or [param max_s] passes, as fly(); returns
## whether it held.
func fly_until(cond: Callable, max_s: float, chunk: float = 60.0, fast: bool = true) -> bool:
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end - 1e-6:
		if cond.call():
			return true
		run(_chunk(chunk, end), fast)
		await wait_process_frames(1)
	return cond.call()


## Hold a keyboard key down for HandControllerInput, which reads Input.
func hold_key(code: Key) -> void:
	_key_event(code, true)
	_held_keys.append(code)
	await wait_process_frames(2)


func release_key(code: Key) -> void:
	_key_event(code, false)
	_held_keys.erase(code)
	await wait_process_frames(2)


func _key_event(code: Key, down: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = down
	Input.parse_input_event(ev)


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


## The CSM's optics.
func optics() -> Optics:
	return rt.systems["optics"]


## The CMC's IMU misalignment, deg: how far its reference is turned from
## ECI.
func misalignment_deg() -> float:
	return rad_to_deg(rt.agc().imu.misalignment().length())


## Centre star [param code] in the sextant, as the crew does in MANUAL:
## on the star's true direction.
func centre_star(code: int) -> void:
	Bus.set_value("ctl.optics.mode", 0)
	optics().aim(Basis(rt.dynamics.attitude.q).inverse() * Stars.direction(code))


## Press MARK and let it go.
func mark() -> void:
	Bus.set_value("ctl.optics.mark", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.optics.mark", false)
	run(SimClock.FIXED_DT, false)


## Lay star [param code]'s image on [param body]'s ("earth" or "moon")
## horizon in the sextant, as the crew does in MANUAL for a P23 mark: the
## trunnion at the true angle between them, off by [param err_deg]
## [simplified: the crew's trims of the attitude and the shaft, which put
## the horizon under the star, aren't flown].
func superimpose(code: int, body: String, err_deg: float = 0.0) -> void:
	Bus.set_value("ctl.optics.mode", 0)
	var m := NavFilter.star_horizon(rt.dynamics.traj, Stars.direction(code), body)
	optics().trunnion_deg = rad_to_deg(float(m["q"])) + err_deg
	run(SimClock.FIXED_DT, false)


## One P23 mark as the crew makes it, from V05N70: star [param code] on
## [param horizon]'s horizon (1 the Earth's, 2 the Moon's) loaded; PRO for
## the sighting attitude, and in CMC MODE AUTO PRO for the maneuver; at V51
## the star laid on the horizon, off by [param err_deg], and marked; PRO at
## N49 takes it in; then OPTICS MODE CMC again. Returns N49's ΔR (m) and
## ΔV (m/s).
func p23_mark(code: int, horizon: int, err_deg: float = 0.0) -> Vector2:
	var agc := rt.agc()
	assert_eq(agc.step_name, "n70", "V05N70")
	keys("V21E%dE" % code)
	keys("V23E%dE" % horizon)
	keys("P")
	assert_eq(agc.step_name, "v50n18", "V50N18: the sighting attitude")
	Bus.set_value("ctl.cmc.mode", 2)
	keys("P")
	var there := run_until(func() -> bool: return agc.step_name == "mark", 900.0, 1.0, false)
	assert_true(there, "V51 at the sighting attitude")
	superimpose(code, "earth" if horizon == 1 else "moon", err_deg)
	mark()
	assert_eq(agc.step_name, "n49", "V06N49")
	var dx: PackedFloat64Array = agc.sight_pending.get("dx", PackedFloat64Array([0, 0, 0, 0, 0, 0]))
	keys("P")
	Bus.set_value("ctl.optics.mode", 1)
	return Vector2(Vector3(dx[0], dx[1], dx[2]).length(), Vector3(dx[3], dx[4], dx[5]).length())


## Centre P22's landmark in the sextant, as the crew does in MANUAL: on its
## true line of sight, off by [param err_deg] across it.
func centre_landmark(err_deg: float = 0.0) -> void:
	var m := NavFilter.landmark_los(rt.dynamics.traj, rt.agc().sight_landmark_mf)
	var d := (m["los"] as Vector3).rotated(m["e1"], deg_to_rad(err_deg))
	Bus.set_value("ctl.optics.mode", 0)
	optics().aim(Basis(rt.dynamics.attitude.q).inverse() * d)


## P37 as the crew runs it: V37E37E, PRO at N33 (TIG half an hour on) for
## the correction, PRO at N81 and N42 to store it. Returns the ΔV (LVLH,
## m/s).
func p37() -> Vector3:
	var agc := rt.agc()
	keys("V37E37E")
	assert_eq(agc.step_name, "n33", "V06N33: TIG")
	keys("P")
	assert_eq(agc.step_name, "n81", "V06N81: the correction")
	var dv := agc.dv_lvlh_load
	keys("PP")
	assert_eq(agc.program, 0, "stored; P00")
	return dv


## The entry from here, as its checklist flies it: V37E61E and PRO through
## P61's N61, N60 and N63; P62's V50N25 00041 answered with CM/SM SEP and
## PRO, its N61 with PRO in CMC MODE AUTO; ELS LOGIC and AUTO; PRO at P65's
## N69 and P67's N67; on to the splashdown, or [param max_s], [param chunk]
## seconds at a time in the atmosphere (30 s outside it), calling
## [param each] after each. Returns
## {"programs": the programs flown, in turn; "peaks": the load's peaks
## over 1 g (g), each pass's; "n67": N67's range to go, latitude and
## longitude}.
func fly_entry(max_s: float = 3.0 * 3600.0, each: Callable = Callable(), chunk: float = EntryGuidance.PASS_S) -> Dictionary:
	var agc := rt.agc()
	keys("V37E61E")
	keys("PPP")
	assert_eq([agc.program, agc.dsky.verb, agc.dsky.noun], [62, "50", "25"], "P62: V50N25 for CM/SM SEP")
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(1.0, false)
	assert_eq(rt.dynamics.config, "cm")
	keys("P")
	Bus.set_value("ctl.cmc.mode", 2)
	keys("P")
	Bus.set_value("ctl.els.logic", true)
	Bus.set_value("ctl.els.auto", true)
	var programs := [61, 62]
	var g: Array[float] = []
	var n67 := []
	var end := SimClock.get_seconds + max_s
	while not rt.dynamics.landed and SimClock.get_seconds < end:
		run(chunk if rt.dynamics.in_atmosphere() else 30.0)
		if each.is_valid():
			each.call()
		if agc.program != programs[-1]:
			programs.append(agc.program)
		g.append(rt.dynamics.g_load)
		if agc.step_name == "n67":
			n67 = agc.noun_values(67)
		if agc.step_name in ["n69", "n67"]:
			keys("P")
	# The sequencer ticks before the dynamics, so it sees a splashdown on a
	# chunk's last step only a step later.
	if rt.dynamics.landed:
		run(SimClock.FIXED_DT, false)
	var peaks := []
	for i in range(1, g.size() - 1):
		if g[i] > 1.0 and g[i] > g[i - 1] and g[i] >= g[i + 1]:
			peaks.append(g[i])
	return {"programs": programs, "peaks": peaks, "n67": n67}


## Roll the CSM half a turn about its X axis on the DAP (CMC MODE AUTO),
## as the crew turns the optics, on the CM's +Z side, away from the Moon or
## the Earth; then back to the mode it was in, holding.
func roll_over() -> void:
	var agc := rt.agc()
	_turn_to(agc._att() * Quaternion(Vector3(1, 0, 0), PI), "rolled over")


## Turn the CSM's nose (body X) straight away from the body that fills
## most of the sky, the Moon in lunar orbit, on the DAP as roll_over()
## does: in any roll the optics, 57 degrees off the nose, then look at the
## sky.
func nose_away() -> void:
	var agc := rt.agc()
	var near := Agc._near_bodies(rt.dynamics.traj)
	var big: Array = near[0] if float(near[0][1]) > float(near[1][1]) else near[1]
	var q := agc._att()
	var x := Basis(q) * Vector3.RIGHT
	_turn_to((Quaternion(x, -(big[0] as Vector3)) * q).normalized(), "nose away")


func _turn_to(target: Quaternion, what: String) -> void:
	var agc := rt.agc()
	var was := int(Bus.get_value("ctl.cmc.mode", 1))
	agc.auto_target = target
	agc._plan_via()
	agc.auto_active = true
	Bus.set_value("ctl.cmc.mode", 2)
	var done := run_until(func() -> bool: return agc._att_error(agc.auto_target) < deg_to_rad(1.0) \
		and rt.dynamics.attitude.omega.length() < deg_to_rad(0.05), 600.0, 1.0, false)
	assert_true(done, what)
	agc.auto_active = false
	agc.hold_q = agc._att()
	Bus.set_value("ctl.cmc.mode", was)


## Turn the CSM clear of gimbal lock on the platform as it stands and on
## the new orientation N22 shows (P52's alarm 00401), on the CMC's auto
## maneuver in CMC MODE AUTO: the thrust axis (body X) across both stable
## members' Y axes, where both middle gimbals read zero.
func turn_for_new_orientation() -> void:
	var agc := rt.agc()
	var y_old := Imu.axis(agc.imu.refsmmat, 1)
	var y_new := Imu.axis(agc.align_refsmmat, 1)
	var q := agc._att()
	var x := Basis(q) * Vector3.RIGHT
	var to := y_old.cross(y_new)
	if to.length() < 1e-3:
		to = x - y_old * x.dot(y_old)
	to = to.normalized() * signf(to.dot(x) + 1e-9)
	var was := int(Bus.get_value("ctl.cmc.mode", 1))
	agc.auto_target = (Quaternion(x, to) * q).normalized()
	agc._plan_via()
	agc.auto_active = true
	Bus.set_value("ctl.cmc.mode", 2)
	var done := run_until(func() -> bool: return agc._att_error(agc.auto_target) < deg_to_rad(1.0) \
		and rt.dynamics.attitude.omega.length() < deg_to_rad(0.05), 900.0, 1.0, false)
	assert_true(done, "turned clear of gimbal lock")
	agc.auto_active = false
	agc.hold_q = agc._att()
	Bus.set_value("ctl.cmc.mode", was)


## Realign the IMU with P52 [param option] as the crew does: the option
## (V22), PRO; for a new orientation PRO at N22 and the coarse align; PRO
## for the CMC's stars (rolling over first if the optics can reach none);
## for each, PRO at N70, the optics driven to it, the star centred in
## MANUAL and marked; PRO at N05, PRO at N93 to torque;
## then P00. N22's alarm 00401 (the new orientation in gimbal lock where
## the CSM is) is cleared by turn_for_new_orientation(). OPTICS MODE goes
## back to CMC. Returns {"sad": N05 (deg),
## "torque": N93 (deg), "stars": the two codes}.
func realign(option: int = 3) -> Dictionary:
	var agc := rt.agc()
	keys("V37E52E")
	assert_eq(agc.program, 52, "P52 selected")
	keys("V22E%dEP" % option)
	if option != 3:
		assert_eq(agc.step_name, "n22", "N22: the new orientation's gimbal angles")
		keys("P")
		if agc.step_name == "n22" and agc.alarm_code == 401:
			keys("R")
			turn_for_new_orientation()
			keys("P")
		var aligned := run_until(func() -> bool: return agc.step_name == "acquire", 120.0, 1.0, false)
		assert_true(aligned, "the coarse align finished")
	assert_eq(agc.step_name, "acquire", "V50N25 00015")
	keys("P")
	if agc.step_name == "acquire" and agc.alarm_code == 405:
		# No stars the optics can reach: the Moon or the Earth fills their
		# side of the sky. Roll heads down and try again.
		keys("R")
		roll_over()
		keys("P")
	if agc.step_name == "acquire" and agc.alarm_code == 405:
		# Still none: the nose points into the Moon, which fills the sky
		# round it in every roll. Turn it away.
		keys("R")
		nose_away()
		keys("P")
	assert_eq(agc.step_name, "star", "the CMC picked two stars")
	var stars: Array = agc.align_stars.duplicate()
	for i in 2:
		keys("P")
		run(2.0, false)
		centre_star(stars[i])
		mark()
	assert_eq(agc.step_name, "n05", "both marked")
	var sad := agc.align_sad_deg
	keys("P")
	var torque := agc.align_torque * (180.0 / PI)
	keys("P")
	assert_true(agc.imu.aligned, "aligned")
	keys("V37E00E")
	Bus.set_value("ctl.optics.mode", 1)
	return {"sad": sad, "torque": torque, "stars": stars}


## The stars the crew could mark with the optics from the CSM's true
## attitude: within the trunnion's reach, clear of the Earth and the Moon.
func stars_in_reach() -> Array:
	var tr := rt.dynamics.traj
	var to_body := Basis(rt.dynamics.attitude.q).inverse()
	var near := Agc._near_bodies(tr)
	var out := []
	for c in Stars.codes():
		var s := Stars.direction(c)
		if Optics.angles_for(to_body * s).y > 45.0:
			continue
		var hidden := false
		for body in near:
			if rad_to_deg(s.angle_to(body[0])) < float(body[1]) + 5.0:
				hidden = true
		if not hidden:
			out.append(c)
	return out


## P51 as the crew flies it: V37E51E; the IMU run up at zero gimbal angles
## ([param on_coarse] is called then); two stars the crew finds, rolling
## the CSM heads down first if the optics can reach none (the Moon or the
## Earth on their side), each acquired (PRO at V50N25), centred in the
## sextant, marked and named at V01N71; PRO at N05. Returns {"sad": N05
## (deg), "stars": the two codes}.
func p51(on_coarse: Callable = Callable()) -> Dictionary:
	var agc := rt.agc()
	keys("V37E51E")
	assert_eq(agc.program, 51, "P51")
	var up := run_until(func() -> bool: return agc.step_name == "acquire", 60.0, 1.0, false)
	assert_true(up, "coarse aligned to zero")
	if on_coarse.is_valid():
		on_coarse.call()
	var stars := stars_in_reach()
	if stars.size() < 2:
		roll_over()
		stars = stars_in_reach()
	assert_gt(stars.size(), 1, "stars in the optics' reach")
	var pair := [stars[0], stars[stars.size() - 1]]
	for c in pair:
		keys("P")   # V50N25: acquired
		assert_eq(agc.step_name, "mark", "V51")
		centre_star(c)
		mark()
		assert_eq(Bus.get_value("dsky.noun"), "71", "V01N71: which star")
		keys("V21E%dEP" % c)
	assert_eq(agc.step_name, "n05")
	var sad := agc.align_sad_deg
	keys("P")
	assert_eq(agc.program, 0, "P51 done")
	return {"sad": sad, "stars": pair}


## Fly an uplinked PAD the way the crew does: P30 accept; P52 with
## [param p52_option] (1, the preferred orientation P30 worked out; 0 for
## none) 25 minutes before TIG; a quarter of an hour before TIG, CMC MODE
## AUTO and P40 (SPS) or, below 10 ft/s, P41 (RCS) with auto maneuver; SPS
## armed, PRO at V99, PRO after residuals. The spacecraft drifts in CMC
## MODE FREE until P40 and after the burn: P40's steering, or an attitude
## hold, keeps the clock to fixed steps. P40 or P41 comes [param lead]
## seconds before TIG (the checklists' quarter of an hour, or less, which
## the auto maneuver's 1°/s allows). Returns the maneuver's sensed ΔV
## (m/s); burn_log has the truth at V99 and at the residuals.
func fly_pad(p52_option: int = 1, lead: float = 900.0) -> float:
	var agc := rt.agc()
	keys("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	keys("PPP")
	assert_true(agc.maneuver_valid, "maneuver stored")
	return fly_stored(p52_option, lead)


## Fly the maneuver the CMC has stored (P30's or P37's) from P52 on, as
## fly_pad() does.
func fly_stored(p52_option: int = 1, lead: float = 900.0) -> float:
	var agc := rt.agc()
	var tig := agc.maneuver_tig
	Bus.set_value("ctl.cmc.mode", 0)
	if p52_option > 0:
		run(maxf(tig - 1500.0 - SimClock.get_seconds, 0.0))
		Bus.set_value("ctl.cmc.mode", 1)
		realign(p52_option)
		Bus.set_value("ctl.cmc.mode", 0)
	run(maxf(tig - lead - SimClock.get_seconds, 0.0))
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
	burn_log = {"before": rt.dynamics.traj.clone()}
	keys("P")
	ok = run_until(func() -> bool: return agc.step_name == "post", 2000.0, 1.0, false)
	assert_true(ok, "burn completed")
	burn_log["after"] = rt.dynamics.traj.clone()
	var dv := agc.dv_accum
	keys("P")
	Bus.set_value("ctl.sps.arm_a", false)
	Bus.set_value("ctl.sps.arm_b", false)
	# HOLD until the DAP has nulled the rate the burn left (an SPS burn
	# leaves the stack rolling at up to a degree a second), so a long coast
	# in FREE after it doesn't tumble into gimbal lock.
	Bus.set_value("ctl.cmc.mode", 1)
	run_until(func() -> bool: return rt.dynamics.attitude.omega.length() < 1e-6 and not Bus.get_value("guid.dap_busy", false),
		300.0, 1.0, false)
	Bus.set_value("ctl.cmc.mode", 0)
	return dv


## Fly a PAD uplinked to the LGC the way the LM crew does: P30 accept; a
## quarter of an hour before TIG (or [param lead] seconds), LGC MODE AUTO
## and the thrusting program [param prog] (P40 on the DPS, P41 on the RCS,
## P42 on the APS) with auto maneuver; ENGINE ARM at
## [param arm] (2 DES, 1 ASC, 0 for the RCS), PRO at V99, PRO after
## residuals; then ENGINE ARM OFF and MODE FREE. [param monitor], if
## given, is called at each second of the countdown and the burn. Without
## [param from_p30] the maneuver is one the LGC stored itself (P32 to
## P35). With [param in_place], P41 burns where the LM is, ENTER at V50N18
## (a midcourse correction, as Apollo 11's crew burned theirs on N85).
## Returns the maneuver's sensed ΔV (m/s).
func fly_lm_pad(prog: int, arm: int, monitor: Callable = Callable(), from_p30: bool = true, lead: float = 900.0,
		in_place: bool = false) -> float:
	var lgc := rt.lgc()
	if from_p30:
		keys("V37E30E", lgc)
		assert_eq(lgc.program, 30, "LGC P30 selected")
		keys("PPP", lgc)
	assert_true(lgc.maneuver_valid, "maneuver stored in the LGC")
	var tig := lgc.maneuver_tig
	run(maxf(tig - lead - SimClock.get_seconds, 0.0))
	Bus.set_value("ctl.lm.mode", 2)
	keys("V37E%dE" % prog, lgc)
	assert_eq(lgc.program, prog, "P%d selected" % prog)
	keys("E" if in_place else "P", lgc)   # V50N18: perform auto maneuver, or not
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


## Set the free LM down at the landing site, upright, its +Z axis
## [param yaw_deg] to the left of the CSM's direction of motion [the landing
## itself is slice 3c's test].
func set_lm_down(yaw_deg: float = 0.0) -> void:
	var lm := rt.dynamics.lm
	var cm := Dynamics.lm_cm_height("lm")
	var site := rt.sequencer.landing_site()
	var up := Rtcc.site_at(site, lm.traj.t).normalized()
	var pos := up * (site.length() + cm)
	lm.traj.set_state("moon", lm.traj.t, pos, Bodies.moon_omega(lm.traj.t).cross(pos))
	var tr := rt.dynamics.traj
	var fwd := tr.pos().cross(tr.vel()).normalized().cross(up).normalized().rotated(up, deg_to_rad(yaw_deg))
	lm.attitude.q = Basis(up, fwd.cross(up), fwd).get_rotation_quaternion()
	lm.attitude.omega = Vector3.ZERO
	lm.land(site.length() + cm)


# --- the LM's platform: P52 on the AOT (tests/aot_crew.gd) ----------------------

## The crew's P52 on the AOT (AotCrew.realign()).
func lm_realign(stars: Array = [], pairs: int = 1) -> Dictionary:
	return AotCrew.realign(self, stars, pairs)


## Two stars the crew could mark now (AotCrew.star_pair()).
func visible_star_pair() -> Array:
	return AotCrew.star_pair(self)


## [param pairs] pairs of marks on a star (AotCrew.marks()).
func aot_marks(code: int, detent: int, pairs: int = 1) -> void:
	AotCrew.marks(self, code, detent, pairs)


## The LM turned to put a star in the AOT's field (AotCrew.put_star()).
func put_star_in_aot(code: int, detent: int, off: Vector2) -> void:
	AotCrew.put_star(self, code, detent, off)


# --- powered descent: the LM crew -------------------------------------------------

## Aldrin's part: once the landing radar's altitude is good (the ALT lamp
## out) and N63 shows ΔH, key V57 to permit radar updates. [param seen]
## gets ΔH then ("dh0") and the height over the ground ("dh0_agl").
func permit_lr_updates(lgc: Lgc, seen: Dictionary) -> void:
	if lgc.lr_update or bool(Bus.get_value("lm.dsky.lamp.alt", true)) or lgc.delta_h == 0.0:
		return
	seen["dh0"] = lgc.delta_h
	seen["dh0_agl"] = lm_agl()
	keys("V57EK", lgc)


## The LM's centre of mass over the ground below it, m.
func lm_agl() -> float:
	var tr := rt.dynamics.lm.traj
	return tr.radius() - Terrain.radius_under(Bodies.moon_fixed(tr.t).transposed() * tr.pos())


## The commander in P64: each second, compare where the LPD points (the
## LGC's landing point, along the window's reticle) with where
## [param target_mf] (Moon-fixed) is out of the window, and click the ACA
## once to bring the one toward the other: fore or aft for the LPD angle,
## right or left for azimuth; until the LPD time runs out, or the LGC's
## altitude is under [param down_to] (m). Returns the clicks.
func lpd_pilot(lgc: Lgc, target_mf: Vector3, down_to: float = 0.0) -> int:
	var clicks := 0
	while lgc.program == 64 and lgc.lpd_time() > 1.0 and lgc._h >= down_to:
		var att := Basis(Bus.get_value("lm.dyn.att_q") as Quaternion)
		var mf := Bodies.moon_fixed(SimClock.get_seconds)
		var seen := lpd_look(att.inverse() * (mf * target_mf - rt.dynamics.lm.traj.pos()))
		var lpd := lpd_look(att.inverse() * (mf * lgc.landing_site - lgc.nav.pos()))
		var aca := Vector3.ZERO
		if lpd.x - seen.x > 0.3:
			aca.y = -1.0   # fore: farther
		elif seen.x - lpd.x > 0.3:
			aca.y = 1.0    # aft: nearer
		elif seen.y - lpd.y > 1.2:
			aca.z = 1.0    # right
		elif lpd.y - seen.y > 1.2:
			aca.z = -1.0   # left
		if aca != Vector3.ZERO:
			Bus.set_value("ctl.lm.rhc", aca)
			run(SimClock.FIXED_DT, false)
			Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
			clicks += 1
		run(1.0, false)
	return clicks


## A line of sight in the LM's axes as the window shows it: its angle below
## the +Z axis and to the right, degrees.
static func lpd_look(los: Vector3) -> Vector2:
	return Vector2(rad_to_deg(atan2(-los.x, los.z)), rad_to_deg(atan2(los.y, los.z)))


## One ROD click: +1 slows the descent by 1 ft/s, -1 speeds it up.
func rod_click(dir: int) -> void:
	Bus.set_value("ctl.lm.rod", dir)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.rod", 0)
	run(SimClock.FIXED_DT, false)


## A fifth of a second of the pilot: the hand controller tilts the LM
## against its horizontal velocity, as the cross-pointers show it, to stop
## it in about 4 s and no more than 15° from upright; or, given a spot
## [param spot_mf] (Moon-fixed) out of the window, to fly toward it at a
## tenth of its distance a second, 5 m/s at most. ROD clicks keep the
## descent at a metre a second for every 20 m of height over the ground,
## between 0.6 and 3 m/s, and at half that while the spot is more than
## 30 m off.
func fly_by_hand(lgc: Lgc, spot_mf: Vector3 = Vector3.ZERO) -> void:
	var r: Array = Bus.get_value("lm.dyn.r_m")
	var v: Array = Bus.get_value("lm.dyn.v_mps")
	var pos := Vector3(r[0], r[1], r[2])
	var rel := Vector3(v[0], v[1], v[2]) - Bodies.moon_omega(SimClock.get_seconds).cross(pos)
	var up := pos.normalized()
	var h := lm_agl() - Dynamics.lm_cm_height("lm")
	var g := Bodies.MU_MOON / pos.length_squared()
	var want := Vector3.ZERO
	if spot_mf != Vector3.ZERO:
		var to := Bodies.moon_fixed(SimClock.get_seconds) * spot_mf - pos
		want = (to - up * to.dot(up)) / 10.0
		if want.length() > 5.0:
			want = want.normalized() * 5.0
	var ah := (want - (rel - up * rel.dot(up))) / 4.0
	var ah_max := g * tan(deg_to_rad(15.0))
	if ah.length() > ah_max:
		ah = ah.normalized() * ah_max
	var att: Quaternion = Bus.get_value("lm.dyn.att_q")
	var err := Basis(att).inverse() * (Basis(att) * Vector3.RIGHT).cross((up * g + ah).normalized())
	var rhc := (Vector3(0.0, err.y, err.z) / AgcCore.RATE_HOLD).clamp(-Vector3.ONE, Vector3.ONE)
	Bus.set_value("ctl.lm.rhc", rhc if rhc.length() >= 0.06 else Vector3.ZERO)
	var target := -clampf(h / 20.0, 0.6, 3.0)
	if want.length() > 3.0:
		target /= 2.0
	if lgc.rod_cmd < target - 0.2:
		rod_click(1)
	elif lgc.rod_cmd > target + 0.2:
		rod_click(-1)
	else:
		run(0.2, false)


# --- the CSM's translation controller, and docking --------------------------------

## The LM's docking port relative to the CSM's, and its velocity, CSM body
## axes: what the crew reads off the docking target.
func dock_rel_pos() -> Vector3:
	return Bus.get_value("dock.rel_pos", Vector3.ZERO)


func dock_rel_vel() -> Vector3:
	return Bus.get_value("dock.rel_vel", Vector3.ZERO)


## The ΔV one fixed step of full translation gives the CSM along each body
## axis, m/s.
func csm_step_dv() -> Vector3:
	var f := float(SpacecraftData.section("sm_rcs")["jet_thrust_n"])
	return CSM_JETS * (f * SimClock.FIXED_DT / rt.dynamics.mass)


## Translate for one fixed step toward the ΔV [param owed] (m/s, CSM body
## axes): each axis at the duty its share needs, or not at all below the
## detent. Returns what is still owed after the ΔV the step gave.
func csm_translate_step(owed: Vector3) -> Vector3:
	var cap := csm_step_dv()
	var thc := Vector3.ZERO
	for k in 3:
		var duty := clampf(owed[k] / cap[k], -1.0, 1.0)
		if absf(duty) >= CSM_THC_DETENT:
			thc[k] = duty
	Bus.set_value("ctl.thc", thc)
	run(SimClock.FIXED_DT, false)
	var dv: Array = Bus.get_value("dyn.dv_step", [0.0, 0.0, 0.0])
	return owed - rt.dynamics.attitude.body_from_eci() * Vector3(dv[0], dv[1], dv[2])


## Give the CSM the ΔV [param dv] (m/s, body axes) on the THC.
func csm_translate(dv: Vector3) -> void:
	var owed := dv
	for i in 20000:
		var cap := csm_step_dv()
		if absf(owed.x) < cap.x * CSM_THC_DETENT and absf(owed.y) < cap.y * CSM_THC_DETENT and absf(owed.z) < cap.z * CSM_THC_DETENT:
			break
		owed = csm_translate_step(owed)
	Bus.set_value("ctl.thc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)


## Stop relative to the LM.
func csm_null_rates() -> void:
	for i in 2:
		csm_translate(dock_rel_vel())


## Move the CSM so the LM's port ends up at [param target] (CSM body
## axes), in about [param seconds].
func csm_move_to(target: Vector3, seconds: float) -> void:
	for i in 2:
		csm_null_rates()
		var u := (dock_rel_pos() - target) / seconds
		csm_translate(u)
		run(seconds - 1.0)
	csm_null_rates()


## Close on the LM at [param speed], as a pilot does it: every second,
## trim the closing speed and steer the drogue back onto the probe's axis
## (the vehicles' orbits curve their paths apart). Returns once the probe
## has met the drogue.
func csm_approach(speed: float, max_s: float = 300.0) -> bool:
	Bus.set_value("dock.contact", {})
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		if not dock_contact().is_empty():
			return true
		var p := dock_rel_pos()
		var want := Vector3(-speed, -p.y / 5.0, -p.z / 5.0).clamp(-Vector3.ONE * speed, Vector3.ONE * speed)
		csm_translate(dock_rel_vel() - want)
		run(1.0, false)
	return false


## The last contact of the probe with the drogue (Docking.contact()).
func dock_contact() -> Dictionary:
	return Bus.get_value("dock.contact", {})


## The LM crew's rendezvous from the CSI PAD [param pad] to docking, as
## tests/scenarios/test_rendezvous.gd flies it step by step: a P52 on two
## stars they can see (visible_star_pair()), as Apollo 11's crew realigned
## after insertion; P20's marks; P32 25 min before CSI and P33 20 min before CDH, each flown on P41; P34
## half an hour before TPI and again 12 min before it, and P41; P35 before
## each midcourse correction, burned where Eagle is; braking by the gates;
## and Collins docking.
## With the descent stage still on (an abort on the descent engine), CSI,
## CDH and TPI burn on it (P40) when they need more than a few m/s.
## Returns the burns' sensed ΔV ("csi", "cdh", "tpi", "tpm" their sum, m/s),
## CDH's ΔH ("dh", m), TPI's TIG ("tpi_tig"), whether the LM stopped
## ("braked") and the probe met the drogue ("probe"), and the contact.
func fly_rendezvous(pad: Dictionary) -> Dictionary:
	var lgc := rt.lgc()
	var burn := func() -> float:
		if rt.dynamics.lm.config == "lm" and _vg_stored(lgc) > 3.0:
			return fly_lm_pad(40, 2, Callable(), false)
		return fly_lm_pad(41, 0, Callable(), false)
	lm_realign(visible_star_pair())
	keys("V37E20E", lgc)
	run(float(pad["tig"]) - 1500.0 - SimClock.get_seconds)
	keys("V37E32E", lgc)
	keys("PPP", lgc)
	keys("PP", lgc)
	var out := {"csi": burn.call()}
	run(lgc.rdv_cdh_tig - 1200.0 - SimClock.get_seconds)
	keys("V37E33EP", lgc)
	out["dh"] = lgc.rdv_dh
	keys("PP", lgc)
	out["cdh"] = burn.call()
	run(float(pad["tpi_get"]) - 1800.0 - SimClock.get_seconds)
	for lead in [0.0, 720.0]:
		if lead > 0.0:
			run(lgc.rdv_tpi_tig - lead - SimClock.get_seconds)
		keys("V37E34EP", lgc)
		keys("P", lgc)
		keys("PP", lgc)
	out["tpi_tig"] = lgc.rdv_tpi_tig
	out["tpi"] = burn.call()
	out["tpm"] = 0.0
	for after in rt.mission.section("rendezvous")["tpm_after_tpi_s"]:
		run(float(out["tpi_tig"]) + float(after) - 300.0 - SimClock.get_seconds)
		keys("V37E35EP", lgc)
		out["tpm"] += fly_lm_pad(41, 0, Callable(), false, 900.0, true)
	out["braked"] = lm_brake(1800.0)
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	out["probe"] = csm_approach(0.1)
	out["contact"] = dock_contact()
	return out


## The size of the maneuver the LGC has stored, m/s.
func _vg_stored(lgc: Lgc) -> float:
	return lgc.dv_lvlh_load.length()


## Give the LM the ΔV [param dv] (m/s, inertial) on the TTCA, a fixed step
## at a time: each axis at the duty its share needs, or not at all below
## the detent.
func lm_translate(dv: Vector3) -> void:
	var owed := dv
	var f := float(SpacecraftData.section("lm_rcs")["jet_thrust_n"])
	for i in 20000:
		var cap := LM_JETS * (f * SimClock.FIXED_DT / rt.dynamics.lm.mass)
		var body := Basis(rt.dynamics.lm.attitude.q).inverse() * owed
		var thc := Vector3.ZERO
		for k in 3:
			var duty := clampf(body[k] / cap[k], -1.0, 1.0)
			if absf(duty) >= LM_TTCA_DETENT:
				thc[k] = duty
		if thc == Vector3.ZERO:
			break
		Bus.set_value("ctl.lm.thc", thc)
		run(SimClock.FIXED_DT, false)
		owed -= rt.dynamics.lm.dv_step
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)


## The LM commander's braking, from after the last midcourse correction:
## each second, hold the closing rate to the gate for the range
## (LM_BRAKING_GATES) and null the line of sight's drift, on the TTCA,
## until the LM has stopped 40 m from the CSM. Returns whether it did.
func lm_brake(max_s: float) -> bool:
	Bus.set_value("ctl.lm.mode", 1)
	var end := SimClock.get_seconds + max_s
	while SimClock.get_seconds < end:
		var lm := rt.dynamics.lm.traj
		var rel := Rendezvous.rel_pos(lm, rt.dynamics.traj)
		var vrel := Rendezvous.rel_vel(lm, rt.dynamics.traj)
		var rng := rel.length()
		var u := rel / rng
		var closing := -vrel.dot(u)
		if rng <= 45.0 and vrel.length() < 0.02:
			return true
		var gate := INF
		for g in LM_BRAKING_GATES:
			if rng <= float(g[0]):
				gate = float(g[1])
		var dv := Vector3.ZERO
		if rng <= 45.0:
			dv = vrel
		else:
			if closing > gate + 0.1:
				dv -= u * (closing - gate)
			var drift := vrel - u * vrel.dot(u)
			if drift.length() > 0.03 + rng * 1e-4:
				dv += drift
		if dv != Vector3.ZERO:
			lm_translate(dv)
		run(1.0, false)
	return false


## Turn a vehicle on its hand controller, rate command in MODE HOLD, until
## its +X axis points at [param target] (a Callable giving the inertial
## direction), within half a degree: the LM (ACA) or the CSM (RHC).
func face_x(lm: bool, target: Callable) -> void:
	var rhc_ch := "ctl.lm.rhc" if lm else "ctl.rhc"
	Bus.set_value("ctl.lm.mode" if lm else "ctl.cmc.mode", 1)
	for i in 30000:
		var q: Quaternion = rt.dynamics.lm.attitude.q if lm else rt.dynamics.attitude.q
		var att := Basis(q)
		var want: Vector3 = target.call()
		var angle := att.x.angle_to(want)
		if angle < deg_to_rad(0.5):
			break
		var err := att.inverse() * (att.x.cross(want).normalized() * angle)
		var rhc := (err / (AgcCore.RATE_HOLD * 3.0)).clamp(-Vector3.ONE, Vector3.ONE)
		Bus.set_value(rhc_ch, Vector3(0.0, rhc.y, rhc.z))
		run(SimClock.FIXED_DT, false)
	Bus.set_value(rhc_ch, Vector3.ZERO)
	run(2.0, false)


## The main display console's launch lights now: LV ENGINE 1 to 5, then
## LIFTOFF and S-II SEP, as "10000 10".
func launch_lights() -> String:
	var s := ""
	for ch in ["lv.eng_light_1", "lv.eng_light_2", "lv.eng_light_3", "lv.eng_light_4", "lv.eng_light_5", " ",
			"lv.liftoff_light", "lv.s2_sep_light"]:
		s += " " if ch == " " else ("1" if bool(Bus.get_value(ch, false)) else "0")
	return s


## Fly the launch from where it is to insertion (or GET [param max_s]), a
## second at a time, calling [param each] after each (the crew's part):
## each launch vehicle event's ascent_state() as it came ("states"), panel
## 1's lights each second ("lights", [GET, launch_lights()]), and whether
## the CMC came up in P11 ("p11").
func fly_launch(max_s: float = 800.0, each: Callable = Callable()) -> Dictionary:
	var lv: LaunchVehicle = rt.systems["lv"]
	var states := {}
	var lights: Array = []
	var p11 := false
	while not lv.events.has("insertion") and SimClock.get_seconds < max_s:
		run(1.0, false)
		if each.is_valid():
			each.call()
		p11 = p11 or rt.agc().program == 11
		lights.append([SimClock.get_seconds, launch_lights()])
		for id in lv.events:
			if not states.has(id):
				states[id] = ascent_state()
	return {"states": states, "lights": lights, "p11": p11}


## Panel 1's launch lights [param after] s after the launch vehicle's
## event [param id], in fly_launch()'s [param flight].
func lights_after(flight: Dictionary, id: String, after: float) -> String:
	var at := float((rt.systems["lv"] as LaunchVehicle).events[id]) + after
	for l: Array in flight["lights"]:
		if float(l[0]) >= at:
			return l[1]
	return ""


## fly_launch()'s [param flight] against the flown: each event's GET
## beside [param flown]'s, and its state beside [param flown_states]'
## (altitude km, velocity m/s, flight path angle deg), a line each.
func launch_table(flight: Dictionary, flown: Dictionary, flown_states: Dictionary) -> String:
	var lv: LaunchVehicle = rt.systems["lv"]
	var lines := PackedStringArray()
	for id: String in flown:
		var s: Array = flight["states"].get(id, [0.0, 0.0, 0.0])
		lines.append("%-19s %7.2f s (flown %7.2f)  %6.1f km  %7.1f m/s  %6.3f deg%s" % [id, float(lv.events.get(id, -1.0)),
			float(flown[id]), s[0], s[1], s[2],
			"  (flown %.1f km, %.1f m/s, %.3f deg)" % flown_states[id] if flown_states.has(id) else ""])
	return "\n".join(lines)


## The launch's state now: altitude over the pad's radius (km), space-fixed
## speed (m/s) and flight path angle (deg).
func ascent_state() -> Array:
	var tr := rt.dynamics.traj
	var r := tr.pos()
	var v := tr.vel()
	return [(r.length() - Bodies.R_EARTH - LaunchVehicle.PAD_HEIGHT_M) / 1000.0, v.length(),
		rad_to_deg(asin(r.normalized().dot(v.normalized())))]

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

var rt: SimRuntime
var _held_keys: Array[Key] = []
## fly_pad()'s last burn: the truth (Trajectory) at V99 ("before") and once
## the engine has stopped ("after").
var burn_log: Dictionary = {}


## A test that stopped with a key down leaves Input clean for the next.
func after_each() -> void:
	for k in _held_keys:
		_key_event(k, false)
	_held_keys.clear()


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
## N69 and P67's N67; on to the splashdown, or [param max_s]. Returns
## {"programs": the programs flown, in turn; "peaks": the load's peaks
## over 1 g (g), each pass's; "n67": N67's range to go, latitude and
## longitude}.
func fly_entry(max_s: float = 3.0 * 3600.0) -> Dictionary:
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
		run(EntryGuidance.PASS_S if rt.dynamics.in_atmosphere() else 30.0)
		if agc.program != programs[-1]:
			programs.append(agc.program)
		g.append(rt.dynamics.g_load)
		if agc.step_name == "n67":
			n67 = agc.noun_values(67)
		if agc.step_name in ["n69", "n67"]:
			keys("P")
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


## Fly an uplinked PAD the way the crew does: P30 accept; P52 with
## [param p52_option] (1, the preferred orientation P30 worked out; 0 for
## none) 25 minutes before TIG; a quarter of an hour before TIG, CMC MODE
## AUTO and P40 (SPS) or, below 10 ft/s, P41 (RCS) with auto maneuver; SPS
## armed, PRO at V99, PRO after residuals. The spacecraft drifts in CMC
## MODE FREE until P40 and after the burn: P40's steering, or an attitude
## hold, keeps the clock to fixed steps. Returns the maneuver's sensed ΔV
## (m/s); burn_log has the truth at V99 and at the residuals.
func fly_pad(p52_option: int = 1) -> float:
	var agc := rt.agc()
	keys("V37E30E")
	assert_eq(agc.program, 30, "P30 selected")
	keys("PPP")
	assert_true(agc.maneuver_valid, "maneuver stored")
	return fly_stored(p52_option)


## Fly the maneuver the CMC has stored (P30's or P37's) from P52 on, as
## fly_pad() does.
func fly_stored(p52_option: int = 1) -> float:
	var agc := rt.agc()
	var tig := agc.maneuver_tig
	Bus.set_value("ctl.cmc.mode", 0)
	if p52_option > 0:
		run(maxf(tig - 1500.0 - SimClock.get_seconds, 0.0))
		Bus.set_value("ctl.cmc.mode", 1)
		realign(p52_option)
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
## quarter of an hour before TIG, LGC MODE AUTO and the thrusting program
## [param prog] (P40 on the DPS, P41 on the RCS, P42 on the APS) with auto
## maneuver; ENGINE ARM at
## [param arm] (2 DES, 1 ASC, 0 for the RCS), PRO at V99, PRO after
## residuals; then ENGINE ARM OFF and MODE FREE. [param monitor], if
## given, is called at each second of the countdown and the burn. Without
## [param from_p30] the maneuver is one the LGC stored itself (P32 to
## P35). Returns the maneuver's sensed ΔV (m/s).
func fly_lm_pad(prog: int, arm: int, monitor: Callable = Callable(), from_p30: bool = true) -> float:
	var lgc := rt.lgc()
	if from_p30:
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

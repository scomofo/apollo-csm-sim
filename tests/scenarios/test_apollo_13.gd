## Slice 7d (docs/ROADMAP.md, milestone 7): Apollo 13 flies from its data
## alone (data/missions/apollo_13/mission.json), from five minutes before
## its oxygen tank failed to the splashdown, the LM its lifeboat. Tank 2
## fails at 55:54:53 and tank 1 leaks away; the crew power the command
## module down and Aquarius up, coarse align its platform to the CM's
## through the docking geometry and take the ground's REFSMMAT, and the
## CSM goes dark. The LGC flies the stack's burns on the descent engine:
## back onto a free return, and PC+2, two hours past the Moon, whose
## platform error leaves the return missing the atmosphere as the flight's
## did; MCC-5 is flown by hand on the AGS, the engine started and stopped
## on the crew's word, MCC-7 on the LM's jets on the LGC again. The LM
## charges the CM's entry batteries; the SM goes, the CM powers up, aligns
## to the ground's angles and its stars, and leaves Aquarius an hour before
## the entry on P61 to P67. The flight's figures are the Fidelity table in
## README.md, each held here within set limits of Apollo 13's: the Apollo
## 13 Mission Report (MSC-02680) and its guidance supplement, the Mission
## Operations Report and the Apollo Flight Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s: time
## enough for the auto maneuver to turn the stack, and less than the
## checklists' quarter of an hour, for the suite's time.
const LEAD_S := 300.0
## The AGS's counter (the DEDA's 470) a second short of the PAD's ΔV at
## 10 % throttle, where the crew stopped MCC-5's engine, ft/s: a second of
## the engine on the stack [derived].
const STOP_SHORT_FT_S := 0.37

var sq: MissionSequencer


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func _hms(t: float) -> String:
	return Units.hms(t)


func _run_to(t: float, fast: bool = true) -> void:
	if t > SimClock.get_seconds:
		run(t - SimClock.get_seconds, fast)


## Until timeline entry [param id] has happened.
func _await(id: String) -> void:
	assert_true(run_until(func() -> bool: return sq.timeline_done.has(id), 60.0 * 3600.0, 60.0), id)


## The PAD of [param kind] timeline entry [param id] brought, or {} when
## the RTCC found no burn required.
func _await_pad(id: String, kind: String) -> Dictionary:
	sq.pads.erase(kind)
	_await(id)
	return sq.pads.get(kind, {})


## V41N20 on [param c]: the gimbal angles [param g] (deg) keyed in.
func _coarse_align(c: AgcCore, g: Vector3) -> void:
	keys("V41N20E", c)
	for a in [g.x, g.y, g.z]:
		keys("+%05dE" % int(round(fposmod(a, 360.0) * 100.0)), c)
	run(60.0, false)


## The pericynthion ahead: x its altitude (nmi), y its GET.
func _pericynthion() -> Vector2:
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, SimClock.get_seconds + 5.0 * 86400.0)
	return Vector2((float(ap["rp"]) - Bodies.R_MOON) / Units.NMI, Rtcc._pericynthion_time(tr))


## Where the stack's coast (not changed) meets the Earth: entry interface's
## GET, flight-path angle (deg) and speed (ft/s), or where the return
## passes perigee above it; and its vacuum perigee's altitude (nmi).
static func _return(from: Trajectory) -> Dictionary:
	var tr := from.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.primary == "earth" and (t2.altitude() < Rtcc.EI_ALT_M or (t2.radial_rate() > 0.0 and t2.radius() < 3.0e7))
	tr.coast_until(down, tr.t + 6.0 * 86400.0, 60.0, 0.002)
	var vp := Rtcc.vacuum_perigee(tr, float(tr.conic()["rp"]))
	return {"t": tr.t, "gamma": rad_to_deg(asin(tr.radial_rate() / tr.speed())), "speed": tr.speed() / Units.FT,
		"vp_nmi": (vp - Bodies.R_EARTH) / Units.NMI, "entry": tr.altitude() < Rtcc.EI_ALT_M + 1000.0}


## Fly the LGC's uplinked burn on program [param prog] with the engine
## armed at [param arm] (fly_lm_pad()). Returns the ΔV the LGC sensed
## (ft/s), the time from the ignition command to the cutoff (s) and the
## LM's gimbal angles at ignition.
func _lm_burn(prog: int, arm: int) -> Dictionary:
	var lgc := rt.lgc()
	var box := {"off": -1.0, "ign": -1.0}
	var dv := fly_lm_pad(prog, arm, func() -> void:
		if not box.has("icdu"):
			box["icdu"] = lgc.icdu()
		if lgc.ignition_get > 0.0:
			box["ign"] = lgc.ignition_get
		if lgc.step_name in ["tailoff", "post"] and box["off"] < 0.0:
			box["off"] = SimClock.get_seconds, true, LEAD_S)
	# The DAP holds the attitude the burn left the stack at.
	Bus.set_value("ctl.lm.mode", 1)
	return {"dv": dv / Units.FT, "s": float(box["off"]) - float(box["ign"]), "ign": float(box["ign"]),
		"icdu": box.get("icdu", Vector3.ZERO)}


## Point the docked LM's +X axis at [param want] (ECI) on the ACA, the AGS
## holding the stack: pitch and yaw rates the jets can brake over what is
## left of the turn, as the pilot flies the needles to zero, until within
## [param tol_deg] with the rates out.
func _lm_point_x(want: Vector3, tol_deg: float) -> void:
	var alpha := Lgc.jet_authority()
	for i in 200000:
		var att := Basis(Bus.get_value("lm.dyn.att_q") as Quaternion)
		var angle := att.x.angle_to(want)
		var w: Vector3 = Bus.get_value("lm.dyn.omega", Vector3.ZERO)
		if angle < deg_to_rad(tol_deg) and w.length() < deg_to_rad(0.01):
			break
		var err := att.inverse() * (att.x.cross(want).normalized() * angle)
		var hc := Vector3.ZERO
		for k in [1, 2]:
			var rate := signf(err[k]) * minf(minf(absf(err[k]) * 0.4, sqrt(alpha[k] * absf(err[k]))), AgcCore.RATE_HOLD)
			hc[k] = clampf(rate / AgcCore.RATE_HOLD, -1.0, 1.0)
		Bus.set_value("ctl.lm.rhc", hc)
		run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(2.0, false)


## The docked LM's jets along its X axis until the AGS's counter has moved
## [param dv_fts] (ft/s, signed).
func _lm_x(dv_fts: float) -> void:
	var start := float(Bus.get_value("lm.ags.dv_x_mps")) / Units.FT
	Bus.set_value("ctl.lm.thc", Vector3(signf(dv_fts), 0.0, 0.0))
	run_until(func() -> bool: return absf(float(Bus.get_value("lm.ags.dv_x_mps")) / Units.FT - start) >= absf(dv_fts),
		120.0, SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)
	run(1.0, false)


## The AGS's body-axis align (the DEDA's 400+5, then 400+0): its needles'
## zero and its counter's.
func _ags_align() -> void:
	Bus.set_value("ctl.lm.ags_align", true)
	run(0.1, false)
	Bus.set_value("ctl.lm.ags_align", false)


## The CM's entry batteries' charge, A-h.
static func _cm_batteries() -> float:
	return float(Bus.get_value("eps.batt_a_ah", 0.0)) + float(Bus.get_value("eps.batt_b_ah", 0.0)) \
		+ float(Bus.get_value("eps.batt_c_ah", 0.0))


func test_apollo_13_flies_home_on_its_lifeboat() -> void:
	build("tank_failure", "apollo_13")
	sq = rt.sequencer
	var agc := rt.agc()
	var lgc := rt.lgc()
	var rows := PackedStringArray()
	assert_eq(rt.dynamics.config, "csm_lm", "Aquarius docked since the transposition")
	assert_eq(sq.phase, "translunar_coast")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "stir up your cryo tanks")

	# The hybrid trajectory the first midcourse correction left: 60 nmi, the
	# PAD's (Apollo Flight Journal, 028:53:25), at 77:28:39; flown 63 nmi
	# (MSC-02680, Table 4-III).
	var p := _pericynthion()
	rows.append("The hybrid at the incident | pericynthion %.1f nmi at %s | 63 nmi at 77:28:39 (the PAD's 60)" % [p.x, _hms(p.y)])
	assert_almost_eq(p.x, 60.0, 5.0, "the hybrid's pericynthion")
	assert_almost_eq(p.y, _get_s("77:28:39"), 120.0, "and when")

	# Tank 2 fails at 55:54:53; fuel cells 1 and 3 go with it, and tank 1
	# leaks away until fuel cell 2 stops at 58:15:11 (MSC-02680, section
	# 14.1.1; Apollo Flight Journal). The emergency power-down at 56:16:08.
	assert_true(run_until(func() -> bool: return sq.event_get("o2_tank_2_failure") > 0.0, 900.0, 60.0), "the failure")
	var t_fail := sq.event_get("o2_tank_2_failure")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "we've had a problem")
	run(300.0)
	assert_false(bool(Bus.get_value("eps.fc1_ok")) or bool(Bus.get_value("eps.fc3_ok")), "fuel cells 1 and 3 lost")
	assert_true(bool(Bus.get_value("eps.fc2_ok")), "fuel cell 2 on")
	_await("power_down")
	Bus.set_value("ctl.eps.cm_power", 1)

	# The LM powered up at 57:41:47, its attitude control off while the CSM
	# holds the stack; the docked coarse align from the CM's gimbal angles
	# at 58:02: the CM's 355.57, 167.78, 351.87, the LM's +302.43, +347.78,
	# +008.13 (Apollo Flight Journal, 058:02:26 to 058:04:03).
	_run_to(_get_s("57:41:47"))
	Bus.set_value("ctl.lm.mode", 0)
	Bus.set_value("ctl.lm.power", true)
	_run_to(_get_s("58:02:26"))
	assert_true(bool(Bus.get_value("lm.sys.powered")), "Aquarius powered")
	var cm_n20 := agc.icdu()
	var lm_n20 := Docking.lm_gimbals(cm_n20)
	_coarse_align(lgc, lm_n20)
	assert_true(lgc.imu.operating(), "the LGC's platform coarse aligned")
	rows.append("The docked coarse align | the CM's N20 %.2f, %.2f, %.2f; the LM's V41N20 %.2f, %.2f, %.2f | 355.57, 167.78, 351.87; +302.43, +347.78, +008.13" % [
		cm_n20.x, cm_n20.y, cm_n20.z, lm_n20.x, lm_n20.y, lm_n20.z])
	assert_almost_eq(lm_n20.y, 347.78, 0.2, "the LM's inner gimbal")
	assert_almost_eq(lm_n20.z, 8.13, 0.2, "and middle")
	assert_true(run_until(func() -> bool: return float(Bus.get_value("eps.fc2_kw", 1.0)) <= 0.0, 3600.0, 10.0), "fuel cell 2 stops")
	var t_fc2 := SimClock.get_seconds
	rows.append("The oxygen tank | tank 2 failed at %s; fuel cell 2 carried the CSM until %s | 55:54:53; 58:15:11" % [
		_hms(t_fail), _hms(t_fc2)])
	assert_almost_eq(t_fail, _get_s("55:54:53"), 2.0, "the incident")
	assert_almost_eq(t_fc2, _get_s("58:15:11"), 60.0, "the last fuel cell")

	# The CSM completely powered down at 58:40, 99 A-h left in its entry
	# batteries (MSC-02680, section 7.1.6); the LGC's platform onto the CMC's
	# REFSMMAT at 58:44, but for the misalignment PC+2 would find.
	_await("csm_power_down")
	_run_to(_get_s("58:40:12"))
	Bus.set_value("ctl.eps.cm_power", 0)
	Bus.set_value("ctl.lm.mode", 1)
	var t_down := SimClock.get_seconds
	run(2.0, false)
	var cm_ah := _cm_batteries()
	assert_true(sq._lifeboat(), "the lifeboat")
	var rs := _await_pad("lgc_refsmmat_pad", "refsmmat")
	assert_true(bool(rs.get("uplinked", false)), "the LGC's REFSMMAT")
	assert_almost_eq(rad_to_deg(lgc.imu.misalignment().length()), 0.351, 0.001, "the platform off by the velocity check's 0.351 deg")
	rows.append("The CSM powered down | %s, %.0f A-h in the entry batteries | 58:40, 99 A-h" % [_hms(t_down), cm_ah])
	assert_almost_eq(cm_ah, 99.0, 10.0, "the entry batteries")

	# Back onto a free return on the DPS: the PAD's 38.0 ft/s at
	# 61:29:42.84, N81 -21.3, +4.1, -31.2 (Apollo Flight Journal, 060:53:09);
	# flown 37.8 ft/s in 34.2 s, 136 nmi past the Moon at 77:20:57
	# (MSC-02680, Tables 4-III and 6.4-I).
	var r0 := float(Bus.get_value("lm.rcs.prop_kg"))
	var dps0 := float(Bus.get_value("lm.dps.prop_kg"))
	var fr := _await_pad("free_return_pad", "mcc")
	assert_false(fr.is_empty(), "the free return's PAD")
	assert_true(bool(fr.get("uplinked", false)), "uplinked to the LGC")
	var fr_n81: Vector3 = fr["dv_lvlh"] / Units.FT
	var b := _lm_burn(40, 2)
	p = _pericynthion()
	rows.append("MCC-2, back to a free return | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s on the DPS; then %.1f nmi at %s | 61:29:43, N81 −21.3, +4.1, −31.2; 37.8 ft/s in 34.2 s; then 136 nmi at 77:20:57" % [
		_hms(float(b["ign"])), fr_n81.x, fr_n81.y, fr_n81.z, float(b["dv"]), float(b["s"]), p.x, _hms(p.y)])
	assert_almost_eq(float(b["ign"]), _get_s("61:29:43.49"), 5.0, "at the PAD's TIG")
	assert_almost_eq(float(b["dv"]), 37.8, 4.0, "the free return's ΔV")
	assert_almost_eq(float(b["s"]), 34.2, 6.0, "its burn")
	assert_almost_eq(p.x, 136.0, 10.0, "the flyby's pericynthion")
	assert_almost_eq(p.y, _get_s("77:20:57"), 180.0, "and when")

	# PC+2 on the DPS, 5 s at the minimum, 21 s at 40 % and the rest at full
	# thrust: the final PAD's 861.5 ft/s at 79:27:38.30, N81 +833.0, -50.9,
	# -213.9 (Apollo Flight Journal, 077:55:24); flown 860.5 ft/s in 263.8 s,
	# 95,424.0 to 87,456.0 lb (MSC-02680, Tables 6.4-I and A-I), the LM's
	# middle and inner gimbals 330.00 and 355.00 (the V49 angles, Apollo
	# Flight Journal, 073:56:46). The platform's error, 5.27 ft/s across the
	# burn (the guidance supplement), left the return missing the
	# atmosphere: its vacuum perigee 80.6 nmi (MSC-02680, Table 4-III).
	var pc2 := _await_pad("pc2_pad", "tei")
	assert_false(pc2.is_empty(), "the PC+2 PAD")
	assert_eq(sq.phase, "transearth_coast", "past the Moon")
	var pc2_n81: Vector3 = pc2["dv_lvlh"] / Units.FT
	var m0 := rt.dynamics.mass
	b = _lm_burn(40, 2)
	var ret := _return(rt.dynamics.traj)
	var g: Vector3 = b["icdu"]
	rows.append("PC+2 | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s on the DPS; %.0f to %.0f lb; the LM's gimbals %.1f, %.1f (middle, inner) | 79:27:39, N81 +833.0, −50.9, −213.9; 860.5 ft/s in 263.8 s; 95,424 to 87,456 lb; 330.0, 355.0" % [
		_hms(float(b["ign"])), pc2_n81.x, pc2_n81.y, pc2_n81.z, float(b["dv"]), float(b["s"]), m0 / Units.LBM,
		rt.dynamics.mass / Units.LBM, g.z, g.y])
	rows.append("The return after PC+2 | %s: vacuum perigee %.1f nmi | no entry: vacuum perigee 80.6 nmi" % [
		"entry" if bool(ret["entry"]) else "no entry", float(ret["vp_nmi"])])
	assert_almost_eq(float(b["ign"]), _get_s("79:27:38.95"), 5.0, "at the PAD's TIG")
	assert_almost_eq(float(b["dv"]), 860.5, 30.0, "PC+2's ΔV")
	assert_almost_eq(float(b["s"]), 263.8, 15.0, "its burn")
	assert_almost_eq(rt.dynamics.mass / Units.LBM, 87456.0, 800.0, "the stack after it")
	assert_almost_eq(g.z, 330.0, 3.0, "the burn attitude's middle gimbal")
	assert_false(bool(ret["entry"]), "the platform's error: no entry")
	assert_almost_eq(float(ret["vp_nmi"]), 80.6, 20.0, "the vacuum perigee")

	# The PGNS powered down at 82:03 (Apollo Flight Journal).
	_await("pgns_power_down")
	Bus.set_value("ctl.lm.pgns", false)
	run(2.0, false)
	assert_false(lgc._powered, "the LGC dark")

	# MCC-5 by hand on the AGS, the PAD read up by voice: 7.8 ft/s at 10 %,
	# the engine stopped a second short; flown at 105:18:28, 14 s, 7.4 on the
	# DEDA trimmed to 7.6 ft/s, the entry's angle to 6.52 deg (MSC-02680,
	# section 4; Apollo Flight Journal, 104:33:43 to 105:19:05). The crew
	# pointed the burn by the Earth's terminator; here straight along the
	# PAD's ΔV [simplified].
	var m5 := _await_pad("mcc5_pad", "mcc")
	assert_false(m5.is_empty(), "the MCC-5 PAD")
	assert_false(bool(m5.get("uplinked", true)), "read up by voice: the LGC is dark")
	_run_to(_get_s("104:50:03"))
	Bus.set_value("ctl.lm.ags", true)
	Bus.set_value("ctl.lm.guid_cont", 1)
	Bus.set_value("ctl.lm.mode", 1)
	run(5.0, false)
	var tig5 := _get_s("105:18:28")
	var at := rt.dynamics.traj.clone()
	at.coast_to(tig5, 30.0)
	var dir: Vector3 = (Trajectory.lvlh_basis(at.pos(), at.vel()) * (m5["dv_lvlh"] as Vector3)).normalized()
	_lm_point_x(dir, 0.2)
	_run_to(tig5 - 10.0)
	_ags_align()
	Bus.set_value("ctl.lm.thc", Vector3(1.0, 0.0, 0.0))
	run(10.0, false)
	Bus.set_value("ctl.lm.throttle", 0.1)
	Bus.set_value("ctl.lm.engine_arm", 2)
	Bus.set_value("ctl.lm.eng_start", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.eng_start", false)
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)
	var t_on := SimClock.get_seconds
	var want := float(m5["dv"]) / Units.FT
	run_until(func() -> bool: return float(Bus.get_value("lm.ags.dv_x_mps")) / Units.FT >= want - STOP_SHORT_FT_S,
		60.0, SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.eng_stop", true)
	var t_off := SimClock.get_seconds
	run(2.0, false)
	Bus.set_value("ctl.lm.eng_stop", false)
	Bus.set_value("ctl.lm.engine_arm", 0)
	var at_stop := float(Bus.get_value("lm.ags.dv_x_mps")) / Units.FT
	_lm_x(want - at_stop)
	var trimmed := float(Bus.get_value("lm.ags.dv_x_mps")) / Units.FT
	Bus.set_value("ctl.lm.ags", false)
	ret = _return(rt.dynamics.traj)
	rows.append("MCC-5, by hand on the AGS | PAD %.1f ft/s; the engine %s for %.1f s at 10 %%; the DEDA %.1f, trimmed to %.1f; the entry %.2f deg down | 7.8 ft/s; 105:18:28, 14 s; 7.4, trimmed to 7.6; 6.52 deg" % [
		want, _hms(t_on), t_off - t_on, at_stop, trimmed, -float(ret["gamma"])])
	assert_almost_eq(want, 7.8, 2.5, "MCC-5's ΔV")
	assert_almost_eq(t_on, tig5, 1.0, "at 105:18:28")
	assert_almost_eq(t_off - t_on, 14.0, 4.0, "its burn")
	assert_almost_eq(trimmed, want, 0.2, "trimmed on the jets")
	assert_true(bool(ret["entry"]), "back in the corridor")
	assert_almost_eq(float(ret["gamma"]), -6.52, 0.3, "the entry's angle")

	# The LM charges the CM's entry batteries from about 112 hours, to 118
	# A-h (MSC-02680, sections 7.1.6 and 7.2.5).
	_await("lm_charging")
	Bus.set_value("ctl.eps.lm_power", true)

	# The PGNS up at 133:30 for MCC-7, its platform on the ground's angles
	# and REFSMMAT [simplified: its Sun and Moon P52]; MCC-7 on the LM's
	# jets, the PAD's 3.1 ft/s at 137:39:48.39 (Apollo Flight Journal,
	# 136:05:46); flown 3.0 ft/s in 21.5 s from 137:39:51.5, the entry's
	# angle to 6.26 deg (MSC-02680, Tables 4-II and 4-III).
	_run_to(_get_s("133:30:00"))
	Bus.set_value("ctl.lm.pgns", true)
	Bus.set_value("ctl.lm.guid_cont", 0)
	Bus.set_value("ctl.lm.mode", 0)
	var cp := _await_pad("lgc_coarse_pad", "coarse")
	assert_false(cp.is_empty(), "the LGC's coarse align angles")
	_coarse_align(lgc, cp["angles"])
	assert_true(bool(_await_pad("lgc_refsmmat_pad2", "refsmmat").get("uplinked", false)), "and its REFSMMAT")
	Bus.set_value("ctl.lm.mode", 1)
	var m7 := _await_pad("mcc7_pad", "mcc")
	assert_false(m7.is_empty(), "MCC-7")
	assert_eq(str(m7.get("engine", "")), "lm_rcs", "on the LM's jets")
	b = _lm_burn(41, 0)
	ret = _return(rt.dynamics.traj)
	rows.append("MCC-7, on the LM's jets | GET %s, %.1f ft/s in %.1f s; the entry %.2f deg down | 137:39:52, 3.0 ft/s in 21.5 s; 6.26 deg" % [
		_hms(float(b["ign"])), float(b["dv"]), float(b["s"]), -float(ret["gamma"])])
	assert_almost_eq(float(b["ign"]), _get_s("137:39:48.39"), 5.0, "at the PAD's TIG")
	assert_lt(float(b["dv"]), 5.0, "a trim")
	assert_almost_eq(float(ret["gamma"]), -6.27, 0.3, "the corridor")

	# SM SEP on the AGS: 0.5 ft/s +X, the pyros, 0.5 ft/s -X, at 138:01:48;
	# the CM and LM 37,109.7 lb after it (MSC-02680, Tables 3-I and A-I).
	_run_to(_get_s("138:00:00"))
	Bus.set_value("ctl.lm.ags", true)
	Bus.set_value("ctl.lm.guid_cont", 1)
	Bus.set_value("ctl.lm.mode", 1)
	run(5.0, false)
	_ags_align()
	_run_to(_get_s("138:01:40"), false)
	_lm_x(0.5)
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.cm_sm_sep", false)
	var t_sep := sq.event_get("cm_sm_sep")
	assert_eq(rt.dynamics.config, "cm_lm", "the SM gone, the LM on the CM")
	var m_sep := rt.dynamics.mass
	_lm_x(-0.5)
	rows.append("SM SEP | %s; the CM and LM %.0f lb | 138:01:48; 37,110 lb" % [_hms(t_sep), m_sep / Units.LBM])
	assert_almost_eq(t_sep, _get_s("138:01:48"), 30.0, "SM SEP")
	assert_almost_eq(m_sep / Units.LBM, 37109.7, 1000.0, "the CM and the LM")

	# The CM's coarse align angles by voice (139:51:40), its power-up at
	# 140:10, the LM's power to it cut; its state vector (140:24:29), the
	# coarse align (140:43:18) and the REFSMMAT flag (140:44:55), and the
	# star P52 (140:52); 118 A-h in the entry batteries then (Apollo Flight
	# Journal; MSC-02680, section 7.1.6).
	var ccp := _await_pad("cm_coarse_pad", "coarse")
	assert_eq(str(ccp.get("computer", "")), "cmc", "for the CMC")
	_await("go_cm_power_up")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.eps.cm_power", 2)
	Bus.set_value("ctl.eps.lm_power", false)
	run(2.0, false)
	var cm_up := _cm_batteries()
	assert_true(bool(Bus.get_value("sys.powered")), "the CM powered")
	assert_false(sq._lifeboat(), "the lifeboat's hours over")
	assert_true(bool(_await_pad("cm_sv", "sv").get("uplinked", false)), "the CMC's state vector")
	_run_to(_get_s("140:43:18"))
	_coarse_align(agc, ccp["angles"])
	assert_true(bool(_await_pad("cm_refsmmat_pad", "refsmmat").get("uplinked", false)), "the CMC's REFSMMAT")
	var al := realign(3)
	rows.append("The CM's power-up | %.0f A-h in the entry batteries; P52 on stars %s, %.3f deg of star angle difference | 118 A-h; stars 36 and 40, 0.00" % [
		cm_up, str(al["stars"]), float(al["sad"])])
	assert_almost_eq(cm_up, 118.0, 6.0, "the entry batteries charged")
	assert_lt(misalignment_deg(), 0.05, "aligned for the entry")

	# LM JETT at 141:29:56 on the docking tunnel's pressure: 410 A-h left in
	# the LM's batteries, 10,091.6 lb in its descent stage, 467 lb of its
	# jets' 633 used (MSC-02680, sections 7.2.1, 7.2.2 and 7.2.5); the CM
	# sensed 1.54, 0.42, 1.00 ft/s, 12,367.6 lb after it (ibid., section
	# 6.4.1 and Table A-I).
	_await("go_lm_jett")
	var lm_ah := float(Bus.get_value("lm.eps.batt_ah"))
	var dps_left := float(Bus.get_value("lm.dps.prop_kg"))
	var rcs_used := r0 - float(Bus.get_value("lm.rcs.prop_kg"))
	_run_to(_get_s("141:29:56"))
	Bus.set_value("ctl.lm.ags", false)
	var v0 := rt.dynamics.traj.vel()
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	var push := (rt.dynamics.traj.vel() - v0).length() / Units.FT
	Bus.set_value("ctl.cmc.mode", 1)
	run(10.0)
	rows.append("Aquarius at LM JETT | %.0f A-h left; %.0f lb in the descent stage, %.0f lb of it used; %.0f lb of the jets' used | 410 A-h; 10,091.6 lb, 8,342.9 used; 467 lb" % [
		lm_ah, dps_left / Units.LBM, (dps0 - dps_left) / Units.LBM, rcs_used / Units.LBM])
	rows.append("LM JETT | %s; the CM pushed %.2f ft/s, %.1f lb | 141:30:00; 1.88 ft/s, 12,367.6 lb" % [
		_hms(sq.event_get("lm_jettison")), push, rt.dynamics.mass / Units.LBM])
	assert_eq(rt.dynamics.config, "cm")
	assert_almost_eq(lm_ah, 410.0, 150.0, "the LM's batteries")
	assert_almost_eq(dps_left / Units.LBM, 10091.6, 600.0, "the descent stage's propellant")
	assert_almost_eq(push, 1.88, 0.2, "the tunnel's push")
	assert_almost_eq(rt.dynamics.mass / Units.LBM, 12367.6, 5.0, "the CM")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Farewell, Aquarius")

	# The entry PAD, 141:48:23: 21.66 S 165.37 W; the final state vector at
	# 142:00:45. Entry interface 142:40:45.7, 36,210.6 ft/s, 6.269 deg down,
	# 28.23 S 173.44 E (MSC-02680, Table 4-II).
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(agc.entry_lat, agc.entry_lng), Vector2(-21.66, -165.37), "N61 uplinked")
	assert_true(bool(_await_pad("final_sv", "sv").get("uplinked", false)), "the final state vector")
	var ei := _return(rt.dynamics.traj)
	rows.append("Entry interface | %s, %.0f ft/s, %.3f deg down | 142:40:46, 36,210.6 ft/s, 6.269 deg down" % [
		_hms(float(ei["t"])), float(ei["speed"]), -float(ei["gamma"])])
	assert_almost_eq(float(ei["t"]), _get_s("142:40:45.7"), 300.0, "entry interface's time")
	assert_almost_eq(float(ei["speed"]), 36210.6, 30.0, "its speed")
	assert_almost_eq(float(ei["gamma"]), -6.269, 0.2, "the corridor")

	# The entry on P61 to P67 to 21.66 S 165.37 W, 5.2 g on the PAD; down at
	# 142:54:41, 21.64 S 165.36 W, about a mile from the target, 29 A-h left
	# in the entry batteries (MSC-02680, sections 1, 4 and 7.1.6).
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var here := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 5.2 g on the PAD" % [str(fe["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.2f S %.2f W, %.1f nmi from the target; %.0f A-h left in the entry batteries | 142:54:41, 21.64 S 165.36 W, about a mile from it; 29 A-h" % [
		_hms(land), -here.x, -here.y, miss, _cm_batteries()])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 13.")
	assert_almost_eq(rt.dynamics.max_g, 5.2, 1.0, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(land, _get_s("142:54:41"), 300.0, "splashdown's time")
	assert_almost_eq(_cm_batteries(), 29.0, 15.0, "the entry batteries at the end")

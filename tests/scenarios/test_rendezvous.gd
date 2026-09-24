## Slice 3e's check (docs/ROADMAP.md, milestone 3): from insertion to
## docking, and slice 3f's: the lunar_ascent start phase docks with
## Columbia. From that phase Eagle lifts off from Tranquility Base at the
## ascent PAD's time (slice 3d's check) into its 9 x 45 nmi orbit, 16.4°
## behind Columbia. Five minutes after insertion the ground's timeline
## uplinks the CSI PAD and Columbia's state vector, off by MSFN's tracking
## error; P20's rendezvous radar marks take the error out. The LGC targets
## CSI (P32), CDH (P33), TPI (P34) and two midcourse corrections (P35), and
## P41 flies each on the RCS. From a mile out the commander brakes on the
## TTCA by the gates, nulling the line of sight's drift, and stops 40 m
## from Columbia. Eagle turns its docking port to Columbia, and Collins
## flies the probe into the drogue, as he did. The timeline's last calls
## follow: GO for jettison, and the TEI PAD.
extends SimTest

## Translation jets per LM body axis, both systems: X four, Y and Z two;
## and the TTCA's detent (src/systems/lm_rcs.gd).
const LM_JETS := Vector3(4, 2, 2)
const TTCA_DETENT := 0.05
## The braking gates: the closing rate the commander allows from each
## range in, m and m/s: 30 ft/s from a mile, 20 from 3,000 ft, 10 from
## 1,500 ft, 5 from 500 ft, and a stop 40 m out [estimated].
const GATES := [[1852.0, 9.14], [914.0, 6.1], [457.0, 3.05], [152.0, 1.52], [40.0, 0.0]]

var _inserted := ""


func before_all() -> void:
	build("lunar_ascent")
	var lgc := rt.lgc()
	keys("V37E12E", lgc)
	keys("PP", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(float(rt.sequencer.plan["liftoff_tig"]) - 12.0 - SimClock.get_seconds)
	run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false)
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	Bus.set_value("ctl.lm.engine_arm", 1)
	keys("P", lgc)
	run_until(func() -> bool: return lgc.step_name == "post", 600.0, 1.0, false)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	Bus.set_value("ctl.lm.mode", 0)
	run(5.0, false)
	_inserted = JSON.stringify(rt.snapshot())


## Restore Eagle just inserted, and fly on to the CSI PAD, which the
## timeline uplinks five minutes after insertion.
func _csi_pad() -> Dictionary:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_inserted)), "")
	assert_true(run_until(func() -> bool: return rt.sequencer.pads.has("csi"), 600.0, 1.0), "the CSI PAD")
	return rt.sequencer.pads.get("csi", {})


## How far the LGC's CSM state vector is from the CSM, m.
func _csm_error(lgc: Lgc) -> float:
	return Rendezvous.rel_pos(rt.dynamics.traj, lgc.csm_nav).length()


## How far off the LGC has the CSM relative to the LM, m: its two state
## vectors' difference against the truth's. P20's marks take this out;
## what is left of [method _csm_error] is the LM's own navigation error,
## which the rendezvous doesn't feel.
func _rel_error(lgc: Lgc) -> float:
	var truth := Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj)
	return (Rendezvous.rel_pos(lgc.nav, lgc.csm_nav) - truth).length()


func test_the_ground_plans_csi_and_p20_takes_out_the_tracking_error() -> void:
	var pad := _csi_pad()
	gut.p(str(Bus.get_value("mission.pad_text")))
	assert_eq(str(pad.get("name", "")), "CSI")
	var ins := rt.sequencer.event_get("lm_insertion")
	assert_gt(ins, 0.0, "the insertion, from the checkpoint")
	assert_eq(float(Bus.get_value("mission.event.lm_insertion", -1.0)), ins, "and on the Bus again")
	assert_almost_eq(float(rt.sequencer.timeline_done.get("csi_pad", -1.0)) - ins, 300.0, 1.5, "the PAD 5 min after insertion")
	assert_eq(rt.sequencer.phase, "lunar_ascent")
	assert_between(float(pad["tig"]) - ins, 2700.0, 3600.0, "CSI at the first apolune (Apollo 11: 50 min 18 s after insertion)")
	assert_almost_eq(float(pad["tpi_get"]) - ins, 9275.0, 0.01, "TPI 2 h 35 min after insertion")
	assert_almost_eq(float(pad["dv"]) / Units.FT, 51.5, 3.0, "CSI (Apollo 11: 51.5 ft/s)")
	assert_almost_eq(float(pad["dh"]) / Units.NMI, 15.0, 1.0, "15 nmi below Columbia")
	assert_almost_eq(float(pad["tpi_dv"]) / Units.FT, 25.0, 3.0, "TPI (Apollo 11: 25 ft/s)")
	var lgc := rt.lgc()
	assert_eq(lgc.rdv_csi_tig, float(pad["tig"]), "N11 uplinked")
	assert_eq(lgc.rdv_tpi_tig, float(pad["tpi_get"]), "N37 uplinked")
	var err0 := _csm_error(lgc)
	assert_almost_eq(err0, Vector3(900.0, 60.0, -150.0).length(), 5.0, "Columbia's state vector off by MSFN's error")
	keys("V37E20E", lgc)
	assert_true(lgc.rr_nav, "P20")
	run(1.0, false)
	assert_true(Bus.get_value("lm.rr.data_good"), "the radar has Columbia")
	run(12.0 * 60.0 - 1.0)
	gut.p("After %d marks, the LGC has Columbia %.1f m from where it is relative to Eagle (%.0f m at the uplink), %.1f m absolutely; last update %.1f m, %.3f m/s" % [
		lgc.rr_marks, _rel_error(lgc), err0, _csm_error(lgc), lgc.rr_last_dr, lgc.rr_last_dv])
	assert_between(lgc.rr_marks, 11, 13, "a mark a minute")
	assert_lt(_rel_error(lgc), 5.0, "P20 took the error out")
	var n54: Array = lgc.noun_values(54)
	var rel := Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj)
	assert_almost_eq(float(n54[0]), rel.length(), 10.0, "N54: the range")


# --- the crew -------------------------------------------------------------------------

## Give the LM the ΔV [param dv] (m/s, inertial) on the TTCA, a fixed step
## at a time: each axis at the duty its share needs, or not at all below
## the detent.
func _lm_translate(dv: Vector3) -> void:
	var owed := dv
	var f := float(SpacecraftData.section("lm_rcs")["jet_thrust_n"])
	for i in 20000:
		var cap := LM_JETS * (f * SimClock.FIXED_DT / rt.dynamics.lm.mass)
		var body := Basis(rt.dynamics.lm.attitude.q).inverse() * owed
		var thc := Vector3.ZERO
		for k in 3:
			var duty := clampf(body[k] / cap[k], -1.0, 1.0)
			if absf(duty) >= TTCA_DETENT:
				thc[k] = duty
		if thc == Vector3.ZERO:
			break
		Bus.set_value("ctl.lm.thc", thc)
		run(SimClock.FIXED_DT, false)
		owed -= rt.dynamics.lm.dv_step
	Bus.set_value("ctl.lm.thc", Vector3.ZERO)


## The commander's braking, from after the last midcourse correction: each
## second, hold the closing rate to the gate for the range and null the
## line of sight's drift, on the TTCA, until Eagle has stopped 40 m from
## Columbia. Returns whether it did.
func _brake(max_s: float) -> bool:
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
		for g in GATES:
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
			_lm_translate(dv)
		run(1.0, false)
	return false


## Turn a vehicle on its hand controller, rate command in MODE HOLD, until
## its +X axis points at [param target] (a Callable giving the inertial
## direction), within half a degree: the LM (ACA) or the CSM (RHC).
func _face(lm: bool, target: Callable) -> void:
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


func test_from_insertion_to_docking() -> void:
	var pad := _csi_pad()
	var lgc := rt.lgc()
	var lm0 := rt.dynamics.lm.dv_total
	keys("V37E20E", lgc)
	# P32: CSI's TIG, the TPI elevation and time, then the solution.
	run(float(pad["tig"]) - 1500.0 - SimClock.get_seconds)
	var err_csi := _rel_error(lgc)
	keys("V37E32E", lgc)
	assert_eq(lgc.program, 32, "P32")
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], ["06", "11"], "V06N11: CSI's TIG")
	keys("PPP", lgc)
	assert_eq(lgc.step_name, "n75", "V06N75")
	var csi_lgc := lgc.dv_lvlh_load.x
	keys("PP", lgc)
	assert_eq(lgc.program, 0, "the maneuver stored")
	var burns := {"CSI": fly_lm_pad(41, 0, Callable(), false)}
	# P33 a quarter of an hour before CDH.
	run(lgc.rdv_cdh_tig - 1200.0 - SimClock.get_seconds)
	keys("V37E33EP", lgc)
	assert_eq(lgc.step_name, "n75", "P33: V06N75")
	var dh := lgc.rdv_dh
	keys("PP", lgc)
	burns["CDH"] = fly_lm_pad(41, 0, Callable(), false)
	# P34: the time the CSM comes up to 26.6°, and the transfer.
	run(float(pad["tpi_get"]) - 1800.0 - SimClock.get_seconds)
	keys("V37E34EP", lgc)
	assert_eq(lgc.step_name, "n37", "P34: V06N37, TPI's time")
	var tpi_tig := lgc.rdv_tpi_tig
	keys("P", lgc)
	assert_eq(lgc.step_name, "n58", "V06N58")
	keys("PP", lgc)
	burns["TPI"] = fly_lm_pad(41, 0, Callable(), false)
	# P35 five minutes before each midcourse correction.
	for after in rt.mission.section("rendezvous")["tpm_after_tpi_s"]:
		run(tpi_tig + float(after) - 300.0 - SimClock.get_seconds)
		keys("V37E35EP", lgc)
		burns["TPM%d" % burns.size()] = fly_lm_pad(41, 0, Callable(), false)
	var t_brake := SimClock.get_seconds
	assert_true(_brake(1800.0), "braked to station-keeping")
	var t_stop := SimClock.get_seconds
	var lm_dv := rt.dynamics.lm.dv_total - lm0
	gut.p("P20 had Columbia %.1f m off by CSI; CSI %.1f ft/s (LGC %.1f, PAD %.1f), CDH %.1f ft/s, dH %.1f nmi, TPI %s (PAD %s) %.1f ft/s, midcourses %.1f and %.1f ft/s; braking %.0f s; station-keeping at %s; the LM's ΔV %.1f ft/s against the plan's %.1f" % [
		err_csi, burns["CSI"] / Units.FT, csi_lgc / Units.FT, float(pad["dv"]) / Units.FT, burns["CDH"] / Units.FT,
		dh / Units.NMI, Units.hms(tpi_tig), Units.hms(float(pad["tpi_get"])), burns["TPI"] / Units.FT,
		burns["TPM3"] / Units.FT, burns["TPM4"] / Units.FT, t_stop - t_brake, Units.hms(t_stop), lm_dv / Units.FT,
		float(pad["total_dv"]) / Units.FT])
	# Collins docks: Eagle turns its docking port to Columbia, and Columbia
	# its probe to Eagle.
	_face(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	_face(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	var c := dock_contact()
	gut.p("Docked at %s: %s" % [Units.hms(SimClock.get_seconds), Docking.describe(c)])
	assert_true(c["captured"], "within the capture limits")
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	assert_eq(rt.sequencer.phase, "lunar_orbit", "docked again")
	# The timeline's last calls: GO for jettison two hours after docking
	# (Apollo 11: 2 h 5 min), and after LM JETT the TEI PAD, for the
	# opportunity nearest Apollo 11's 135:23:42.
	Bus.set_value("ctl.cmc.mode", 0)
	var docked := rt.sequencer.event_get("docking")
	run(docked + 7489.0 + 10.0 - SimClock.get_seconds)
	assert_almost_eq(float(rt.sequencer.timeline_done.get("go_jettison", -1.0)), docked + 7489.0, 10.0, "GO for jettison")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	assert_eq(rt.dynamics.config, "csm", "Eagle jettisoned")
	run(134.0 * 3600.0 + 76.0 + 10.0 - SimClock.get_seconds)
	var tei: Dictionary = rt.sequencer.pads.get("tei", {})
	assert_eq(str(tei.get("name", "")), "TEI", "the TEI PAD at 134:01:16")
	gut.p("GO for jettison at %s; %s" % [Units.hms(float(rt.sequencer.timeline_done["go_jettison"])), Rtcc.pad_text(tei)])
	var period := float(rt.dynamics.traj.conic()["period"])
	assert_almost_eq(float(tei.get("tig", 0.0)), 135.0 * 3600.0 + 23.0 * 60.0 + 42.0, 0.5 * period, "nearest Apollo 11's TEI")
	# The checks: the sequence as planned, and the ΔV within 20 % of the plan.
	assert_lt(err_csi, 5.0, "P20 had Columbia's state vector by CSI")
	assert_almost_eq(csi_lgc, float(pad["dv"]), 0.3, "the LGC's CSI agrees with the ground's")
	assert_almost_eq(burns["CSI"], float(pad["dv"]), 0.5, "CSI flown")
	assert_almost_eq(dh / Units.NMI, 15.0, 1.0, "coelliptic 15 nmi below")
	assert_almost_eq(tpi_tig, float(pad["tpi_get"]), 120.0, "TPI when the plan had it")
	assert_almost_eq(burns["TPI"], float(pad["tpi_dv"]), 0.5, "TPI flown")
	assert_lt(burns["TPM3"] + burns["TPM4"], 1.0, "small midcourse corrections")
	assert_between(lm_dv, float(pad["total_dv"]), 1.2 * float(pad["total_dv"]), "the LM's ΔV within 20 % of the plan")
	assert_true(Bus.has_channel("mission.event.docking"))

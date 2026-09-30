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
##
## The LGC's platform is a real one (slice 11a): aligned for the crew 33
## min before liftoff, as Apollo 11's last P57 was, it drifts through the
## ascent, and after insertion the crew realign it with P52 on Rigel and
## Acrux, as Armstrong and Aldrin did before P20's marks. The radar's line
## of sight reaches the LGC through the platform, so its drift since leaves
## Columbia off across the line of sight by as much.
extends SimTest

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


## Eagle's P52 after insertion, as Apollo 11's crew flew it once Houston
## called for it at 124:32:44, torquing at 124:51: on Rigel (12) and Acrux
## (25), both through the front detent, the star angle difference 0.00°
## and N93 -0.006, +0.064 and +0.137° [published: MSC-00171, Table 9.6-I;
## the Apollo Flight Journal]. The simulator's platform, drifting at the
## rates of Eagle's first alignments, torques its own angles.
func _p52() -> Dictionary:
	var p52 := lm_realign([12, 25])
	gut.p("P52 on %s and %s at %s: N05 %.3f° (flown 0.00), N93 %s (flown (-0.006, 0.064, 0.137))" % [
		Stars.name_of(12), Stars.name_of(25), Units.hms(p52["get"]), p52["sad"], p52["torque"]])
	assert_eq(p52["stars"], [12, 25], "Rigel and Acrux")
	assert_lt(float(p52["sad"]), 0.01, "N05: the stars' angle as marked")
	assert_lt(rad_to_deg(rt.lgc().imu.misalignment().length()), 0.01, "the platform on the REFSMMAT")
	return p52


## The largest error P20's marks leave in the LGC's relative state, m:
## the platform's misalignment turns the radar's line of sight, and the
## estimate with it, across the range.
func _p20_floor(lgc: Lgc) -> float:
	return 5.0 + Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).length() * lgc.imu.misalignment().length()


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
	gut.p("Inserted at %s; CSI %s after, %.1f nmi below Columbia at CDH" % [
		Units.hms(ins), Units.hms(float(pad["tig"]) - ins), float(pad["dh"]) / Units.NMI])
	assert_gt(ins, 0.0, "the insertion, from the checkpoint")
	assert_eq(float(Bus.get_value("mission.event.lm_insertion", -1.0)), ins, "and on the Bus again")
	assert_almost_eq(float(rt.sequencer.timeline_done.get("csi_pad", -1.0)) - ins, 300.0, 1.5, "the PAD 5 min after insertion")
	assert_eq(rt.sequencer.phase, "lunar_ascent")
	assert_between(float(pad["tig"]) - ins, 2700.0, 3600.0, "CSI at the first apolune (Apollo 11: 50 min 18 s after insertion)")
	assert_almost_eq(float(pad["tpi_get"]) - ins, 9275.0, 0.01, "TPI 2 h 35 min after insertion")
	assert_almost_eq(float(pad["dv"]) / Units.FT, 51.5, 3.0, "CSI (Apollo 11: 51.5 ft/s)")
	# 15 nmi, as the flight plan had it for round orbits; Columbia's orbit,
	# out of round (62 by 56 nmi), moves the height at CDH's point.
	assert_almost_eq(float(pad["dh"]) / Units.NMI, 15.0, 1.5, "15 nmi below Columbia")
	assert_almost_eq(float(pad["tpi_dv"]) / Units.FT, 25.0, 3.0, "TPI (Apollo 11: 25 ft/s)")
	var lgc := rt.lgc()
	assert_eq(lgc.rdv_csi_tig, float(pad["tig"]), "N11 uplinked")
	assert_eq(lgc.rdv_tpi_tig, float(pad["tpi_get"]), "N37 uplinked")
	var err0 := _csm_error(lgc)
	assert_almost_eq(err0, Vector3(900.0, 60.0, -150.0).length(), 5.0, "Columbia's state vector off by MSFN's error")
	_p52()
	keys("V37E20E", lgc)
	assert_true(lgc.rr_nav, "P20")
	run(1.0, false)
	assert_true(Bus.get_value("lm.rr.data_good"), "the radar has Columbia")
	run(12.0 * 60.0 - 1.0)
	gut.p("After %d marks, the LGC has Columbia %.1f m from where it is relative to Eagle (%.0f m at the uplink), %.1f m absolutely; last update %.1f m, %.3f m/s; the platform %.4f° off" % [
		lgc.rr_marks, _rel_error(lgc), err0, _csm_error(lgc), lgc.rr_last_dr, lgc.rr_last_dv,
		rad_to_deg(lgc.imu.misalignment().length())])
	assert_between(lgc.rr_marks, 11, 13, "a mark a minute")
	assert_lt(_rel_error(lgc), _p20_floor(lgc), "P20 took the error out, but for what the platform's drift makes")
	var n54: Array = lgc.noun_values(54)
	var rel := Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj)
	assert_almost_eq(float(n54[0]), rel.length(), 10.0, "N54: the range")


func test_from_insertion_to_docking() -> void:
	var pad := _csi_pad()
	var lgc := rt.lgc()
	var lm0 := rt.dynamics.lm.dv_total
	_p52()
	keys("V37E20E", lgc)
	# P32: CSI's TIG, the TPI elevation and time, then the solution.
	run(float(pad["tig"]) - 1500.0 - SimClock.get_seconds)
	var err_csi := _rel_error(lgc)
	var floor_csi := _p20_floor(lgc)
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
	# P34: the time the CSM comes up to 26.6°, and the transfer, half an
	# hour out; and the final computation 12 minutes before TIG, as Apollo
	# 11's crew recycled it [MSC-00171, section 5].
	run(float(pad["tpi_get"]) - 1800.0 - SimClock.get_seconds)
	for lead in [0.0, 720.0]:
		if lead > 0.0:
			run(lgc.rdv_tpi_tig - lead - SimClock.get_seconds)
		keys("V37E34EP", lgc)
		assert_eq(lgc.step_name, "n37", "P34: V06N37, TPI's time")
		keys("P", lgc)
		assert_eq(lgc.step_name, "n58", "V06N58")
		keys("PP", lgc)
	var tpi_tig := lgc.rdv_tpi_tig
	burns["TPI"] = fly_lm_pad(41, 0, Callable(), false)
	# P35 five minutes before each midcourse correction, burned where Eagle
	# is, the residuals nulled in body axes, as Apollo 11's crew burned them
	# (N85: 0.4 ft/s right and 0.9 down; 0.1 forward, 1.2 right and 0.5
	# down) [published: the Apollo Flight Journal, 127:18:31 and 127:33:31].
	for after in rt.mission.section("rendezvous")["tpm_after_tpi_s"]:
		run(tpi_tig + float(after) - 300.0 - SimClock.get_seconds)
		keys("V37E35EP", lgc)
		burns["TPM%d" % burns.size()] = fly_lm_pad(41, 0, Callable(), false, 900.0, true)
	var t_brake := SimClock.get_seconds
	assert_true(lm_brake(1800.0), "braked to station-keeping")
	var t_stop := SimClock.get_seconds
	var lm_dv := rt.dynamics.lm.dv_total - lm0
	gut.p("P20 had Columbia %.1f m off by CSI; CSI %.1f ft/s (LGC %.1f, PAD %.1f), CDH %.1f ft/s, dH %.1f nmi, TPI %s (PAD %s) %.1f ft/s, midcourses %.1f and %.1f ft/s; braking %.0f s; station-keeping at %s; the LM's ΔV %.1f ft/s against the plan's %.1f" % [
		err_csi, burns["CSI"] / Units.FT, csi_lgc / Units.FT, float(pad["dv"]) / Units.FT, burns["CDH"] / Units.FT,
		dh / Units.NMI, Units.hms(tpi_tig), Units.hms(float(pad["tpi_get"])), burns["TPI"] / Units.FT,
		burns["TPM3"] / Units.FT, burns["TPM4"] / Units.FT, t_stop - t_brake, Units.hms(t_stop), lm_dv / Units.FT,
		float(pad["total_dv"]) / Units.FT])
	# Collins docks: Eagle turns its docking port to Columbia, and Columbia
	# its probe to Eagle.
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	var c := dock_contact()
	gut.p("Docked at %s: %s" % [Units.hms(SimClock.get_seconds), Docking.describe(c)])
	assert_true(c["captured"], "within the capture limits")
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	assert_eq(rt.sequencer.phase, "lunar_orbit", "docked again")
	# The timeline's last calls: GO for jettison two hours after docking
	# (Apollo 11: 2 h 5 min), and after LM JETT the TEI PAD, for Apollo 11's
	# TEI at 135:23:41.56 (mission.json "tei").
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
	assert_almost_eq(float(tei.get("tig", 0.0)), MissionSequencer._get_s("135:23:41.56"), 0.01, "Apollo 11's TEI")
	# The checks: the sequence as planned, and the ΔV within 20 % of the plan.
	# The LGC flies on its own model of the Moon's field and its own state
	# vectors, the ground planned on the truth: with Columbia's orbit out of
	# round, Apollo 11's TPI came 6 min 39 s after the plan's, and its
	# midcourse corrections were 1.4 and 1.2 ft/s (the CMC's solutions)
	# [MSC-00171, section 5 and table 5-VII].
	# The platform (slice 11a) widens them. Its drift through the ascent
	# leaves Eagle's own state vector some 600 m and 1.3 m/s off, which
	# P20's marks, moving Columbia's (V81), don't take out; and its drift
	# after the P52, 0.25° by TPI, turns the radar's line of sight, which
	# P20's fixed gains take partly for velocity. With neither, CSI comes
	# out the PAD's, CDH's ΔH the PAD's, TPI 27.0 ft/s and the midcourse
	# corrections 2.5 ft/s together; slice 11d's filter is to bring them
	# back.
	assert_lt(err_csi, floor_csi, "P20 had Columbia's state vector by CSI, but for the platform's drift")
	assert_almost_eq(csi_lgc, float(pad["dv"]), 0.6, "the LGC's CSI near the ground's")
	assert_almost_eq(burns["CSI"], float(pad["dv"]), 0.5, "CSI flown")
	assert_almost_eq(dh, float(pad["dh"]), 2.5 * Units.NMI, "coelliptic near the PAD's ΔH")
	assert_almost_eq(tpi_tig, float(pad["tpi_get"]), 400.0, "TPI within minutes of the plan")
	assert_almost_eq(burns["TPI"], float(pad["tpi_dv"]), 2.0, "TPI flown near the PAD's")
	assert_lt(burns["TPM3"] + burns["TPM4"], 4.0, "midcourse corrections")
	assert_between(lm_dv, float(pad["total_dv"]), 1.2 * float(pad["total_dv"]), "the LM's ΔV within 20 % of the plan")
	assert_true(Bus.has_channel("mission.event.docking"))

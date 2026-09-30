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
## Acrux, as Armstrong and Aldrin did before P20's marks. Slice 11d's check:
## the radar is the flight's, noisy and biased, locked on after R61's turn
## and kept on Columbia by the LM's +Z; P20 is Luminary's, its filter
## moving Eagle's state vector (V80) and learning the radar's boresight
## biases, which take in the platform's drift since the P52; the crew fly
## the G mission's procedures (lm_coelliptic()), each burn where Eagle is.
##
## Slice 11e's check: the AGS, the rendezvous's backup. Aldrin brings it up
## a quarter of an hour before liftoff (AgsCrew.initialize(): the surface
## flag, the align to the platform, V47's state vectors), and it navigates
## the ascent on its own accelerometers. Before each of CSI, CDH and TPI
## the crew update it from the LGC (V47) and key its solution (the FP6
## operating manual's sections 23 to 25), as Apollo 11's crew did: the
## AGS's own targeting from the same state vectors, set against the LGC's.
extends SimTest

var _inserted := ""


func before_all() -> void:
	build("lunar_ascent")
	var lgc := rt.lgc()
	run(float(rt.sequencer.plan["liftoff_tig"]) - 900.0 - SimClock.get_seconds)
	AgsCrew.initialize(self, true)
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


## The AGS's solution for [param name] (CSI, CDH or TPI) at the LGC's
## final computation: the AGS updated from the LGC (V47), then its routine
## keyed (AgsCrew). Returns AgsCrew's solution checks, and the LGC's ΔV
## ("lgc", LVLH, ft/s).
func _ags_solution(name: String, pad: Dictionary) -> Dictionary:
	var lgc := rt.lgc()
	var tig := lgc.maneuver_tig
	var dv := lgc.dv_lvlh_load / Units.FT
	AgsCrew.update(self)
	var out := {}
	match name:
		"CSI":
			out = AgsCrew.csi(self, tig, float(pad["tpi_get"]))
		"CDH":
			out = AgsCrew.cdh(self, tig)
		"TPI":
			out = AgsCrew.tpi(self, tig)
	out["lgc"] = dv
	return out


## P20's filter's own RSS of the position error it holds, m (V06N99's R1).
func _rss(lgc: Lgc) -> float:
	return lgc.p20.filter.rss().x


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
	var err0 := lgc_rel_error()
	var p52 := _p52()
	var t0 := SimClock.get_seconds
	var lock := start_p20()
	var rng := Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).length()
	var start := SimClock.get_seconds
	run(12.0 * 60.0)
	var rss := _rss(lgc)
	gut.p("P20 locked on %.0f s after the P52 (%s), %.0f nmi from Columbia; after %d marks in 12 min the LGC has Columbia %.1f m and %.3f m/s from where it is relative to Eagle (%.0f m at the uplink); N99 %.0f ft, %.2f ft/s, %.4f rad; the radar's biases estimated %.4f°, %.4f° (truly %.4f°, %.4f°); the platform %.4f° off" % [
		lock - t0, Units.hms(float(p52["get"])), rng / Units.NMI, lgc.p20.marks, lgc_rel_error(), lgc_rel_v_error(), err0,
		rss / Units.FT, lgc.p20.filter.rss().y / Units.FT, lgc.p20.filter.rss().z,
		rad_to_deg(lgc.p20.bias.x), rad_to_deg(lgc.p20.bias.y), rad_to_deg(rt.systems["rr"].bias_shaft),
		rad_to_deg(rt.systems["rr"].bias_trunnion), rad_to_deg(lgc.imu.misalignment().length())])
	assert_lt(lock - t0, 300.0, "locked on within minutes of the P20 (Apollo 11: 1.6 min after the auto maneuver)")
	assert_between(lgc.p20.marks, 9, 12, "a mark about every 64 s")
	assert_lt(lgc_rel_error(), 3.0 * rss, "within the filter's own 3 sigma")
	assert_lt(lgc_rel_error(), 300.0, "P20 took the tracking error out")
	var n54: Array = lgc.noun_values(54)
	var rel := Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj)
	assert_almost_eq(float(n54[0]), rel.length(), 300.0, "N54: the range, from the state vectors")
	# N78: the radar's range, less this flight's bias (its limit, 500 ft
	# or 0.05 % of the range, as 3 sigma), within its noise (37 ft) and its
	# count (75 ft).
	var n78: Array = lgc.noun_values(78)
	var rr: RendezvousRadar = rt.systems["rr"]
	var limit := maxf(500.0 * Units.FT, 0.0005 * rel.length())
	assert_almost_eq(float(n78[0]) - rr.bias_range_k * limit / 3.0, rel.length(), 50.0, "N78: the radar's range")
	assert_true(start > 0.0)


func test_from_insertion_to_docking() -> void:
	var pad := _csi_pad()
	var lgc := rt.lgc()
	var lm0 := rt.dynamics.lm.dv_total
	# The AGS's orbit after its ascent against the truth's, both above the
	# landing site's radius (its 5J).
	var ags: Ags = rt.systems["ags"]
	var c := rt.dynamics.lm.traj.conic()
	var site_r := ags.fp6.j5 * Units.FT
	var orbit_ags := Vector2(AgsCrew.tenths(self, "315"), AgsCrew.tenths(self, "403"))
	var orbit := Vector2(float(c["ra"]) - site_r, float(c["rp"]) - site_r) / Units.NMI
	_p52()
	var ags_dv := {}
	var fly := func(name: String) -> float:
		if name in ["CSI", "CDH", "TPI"]:
			ags_dv[name] = _ags_solution(name, pad)
		return fly_lm_pad(41, 0, Callable(), false, 900.0 if name.begins_with("TPM") else 600.0, true)
	var got := lm_coelliptic(pad, fly)
	var burns := {"CSI": got["CSI"], "CDH": got["CDH"], "TPI": got["TPI"], "TPM3": got["TPM1"], "TPM4": got["TPM2"]}
	var err_csi := float(got["err_csi"])
	var errv_csi := float(got["errv_csi"])
	var rss_csi := float(got["rss_csi"])
	var csi_lgc := float(got["csi_lgc"])
	var csi_first := float(got["csi_first"])
	var marks_csi := int(got["marks_csi"])
	var dh := float(got["dh"])
	var tpi_tig := float(got["tpi_tig"])
	var t_brake := SimClock.get_seconds
	assert_true(lm_brake(1800.0), "braked to station-keeping")
	var t_stop := SimClock.get_seconds
	var lm_dv := rt.dynamics.lm.dv_total - lm0
	gut.p("P20 had Columbia %.1f m and %.3f m/s off by CSI (its own RSS %.1f m) after %d marks; CSI %.1f ft/s (LGC %.1f, first %.1f, PAD %.1f), CDH %.1f ft/s, dH %.1f nmi, TPI %s (PAD %s) %.1f ft/s, midcourses %.1f and %.1f ft/s; braking %.0f s; station-keeping at %s; the LM's ΔV %.1f ft/s against the plan's %.1f" % [
		err_csi, errv_csi, rss_csi, marks_csi, burns["CSI"] / Units.FT, csi_lgc / Units.FT, csi_first / Units.FT,
		float(pad["dv"]) / Units.FT, burns["CDH"] / Units.FT, dh / Units.NMI, Units.hms(tpi_tig),
		Units.hms(float(pad["tpi_get"])), burns["TPI"] / Units.FT, burns["TPM3"] / Units.FT, burns["TPM4"] / Units.FT,
		t_stop - t_brake, Units.hms(t_stop), lm_dv / Units.FT, float(pad["total_dv"]) / Units.FT])
	var csi_ags: Dictionary = ags_dv["CSI"]
	var cdh_ags: Dictionary = ags_dv["CDH"]
	var tpi_ags: Dictionary = ags_dv["TPI"]
	var csi_pgns: Vector3 = csi_ags["lgc"]
	var cdh_pgns: Vector3 = cdh_ags["lgc"]
	var tpi_pgns: Vector3 = tpi_ags["lgc"]
	var los := rad_to_deg(atan(1.0 / ags.fp6.j2))
	gut.p("The AGS: %.1f by %.1f nmi after the ascent (truth %.1f by %.1f); CSI %.1f ft/s (LGC %.1f), dH %.1f nmi; CDH %.1f and %.1f ft/s along and up (LGC %.1f and %.1f); TPI %.1f ft/s (LGC %.1f), the line of sight %.2f deg at the LGC's TIG (%.2f)" % [
		orbit_ags.x, orbit_ags.y, orbit.x, orbit.y, csi_ags["dv"], csi_pgns.x, csi_ags["dh"], cdh_ags["dv"],
		-float(cdh_ags["radial"]), cdh_pgns.x, -cdh_pgns.z, tpi_ags["dv"], tpi_pgns.length(), tpi_ags["angle"], los])
	# Collins docks: Eagle turns its docking port to Columbia, and Columbia
	# its probe to Eagle.
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	var contact := dock_contact()
	gut.p("Docked at %s: %s" % [Units.hms(SimClock.get_seconds), Docking.describe(contact)])
	assert_true(contact["captured"], "within the capture limits")
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
	# round, Apollo 11's TPI came 6 min 39 s after the plan's, and its LGC's
	# midcourse corrections were 0.98 and 1.30 ft/s [MSC-00171, table 5-VI].
	# All four of Apollo 11's CSI solutions agreed within 0.2 ft/s [ibid.,
	# section 4.15]. The platform drifts some 0.1°/h, as Eagle's did, and
	# turns the radar's line of sight by as much across the range; P20's
	# filter takes the radar's biases, and some of that, as boresight
	# biases. The midcourse corrections are what TPI's final computation
	# left in the state vectors: with the radar's errors drawn for Apollo
	# 11 (mission.json "dispersions"), 3.9 and 2.4 ft/s; the three other
	# draws tried came to 1.1, 3.1 and 1.1 ft/s together, and an ideal
	# radar to 0.8 [slice 11d's probe runs].
	assert_lt(err_csi, 3.0 * rss_csi, "P20's error at CSI within its own 3 sigma")
	assert_lt(err_csi, 300.0, "P20 had Columbia by CSI")
	assert_almost_eq(csi_lgc, float(pad["dv"]), 0.3, "the LGC's CSI with the ground's")
	assert_almost_eq(burns["CSI"], float(pad["dv"]), 0.5, "CSI flown")
	assert_almost_eq(dh, float(pad["dh"]), 2.5 * Units.NMI, "coelliptic near the PAD's ΔH")
	assert_almost_eq(tpi_tig, float(pad["tpi_get"]), 400.0, "TPI within minutes of the plan")
	assert_almost_eq(burns["TPI"], float(pad["tpi_dv"]), 1.0, "TPI flown within 1 m/s of the PAD's")
	assert_lt(burns["TPM3"] + burns["TPM4"], 2.5, "midcourse corrections within 2.5 m/s together")
	assert_between(lm_dv, float(pad["total_dv"]), 1.2 * float(pad["total_dv"]), "the LM's ΔV within 20 % of the plan")
	assert_true(Bus.has_channel("mission.event.docking"))
	# Slice 11e's: the AGS's orbit and solutions against the LGC's, from the
	# same state vectors (V47). Apollo 11's AGS had 46.6 by 9.5 nmi to the
	# PGNS's 47.3 by 9.5 after the ascent, and CSI 51.3 ft/s and ΔH 15.5 nmi
	# to the PGNS's 51.5 ft/s [the Apollo Flight Journal, 124:31:14 and
	# 124:39:24]. The AGS's own navigation carries its alignment's error, the
	# CDUs' angles (40 arcsec) off the platform: some 500 ft and 0.5 ft/s.
	assert_almost_eq(orbit_ags, orbit, Vector2(1.0, 0.5), "the AGS's orbit after the ascent")
	assert_almost_eq(float(csi_ags["dv"]), csi_pgns.x, 1.0, "the AGS's CSI within 1 ft/s of the LGC's")
	assert_almost_eq(Vector2(cdh_ags["dv"], cdh_ags["radial"]), Vector2(cdh_pgns.x, cdh_pgns.z), Vector2.ONE,
		"the AGS's CDH within 1 ft/s of the LGC's")
	assert_almost_eq(float(tpi_ags["dv"]), tpi_pgns.length(), 2.0, "the AGS's TPI within 2 ft/s of the LGC's")
	assert_almost_eq(float(tpi_ags["angle"]), los, 0.5, "the AGS's line of sight at the LGC's TPI")

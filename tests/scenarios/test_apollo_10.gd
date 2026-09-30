## Slice 7b (docs/ROADMAP.md, milestone 7): Apollo 10 flies from its data
## alone (data/missions/apollo_10/mission.json), from its parking orbit to
## the splashdown. The S-IVB flies TLI to the RTCC's plan, the stack flies
## its evasive maneuver and the midcourse corrections, and LOI-1 turns the
## orbit into the first landing's plane over Apollo Landing Site 2. Then
## the LM flies the landing mission without the landing: Snoopy undocks,
## Charlie Brown makes its separation maneuver, and DOI takes Snoopy down
## to 8 nmi over the site; the phasing burn on the DPS (the PAD's throttle
## schedule: 10 % for 26 s, then full) puts it in a dwell orbit; it stages
## in orbit, and the APS's insertion puts it where the first landing's
## ascent would have, for the coelliptic sequence (CSI, CDH, TPI, two
## midcourse corrections on P32 to P35), braking and docking. LM JETT, TEI,
## the transearth corrections and the entry on P61 to P67 follow. Each PAD
## Mission Control's timeline brings is flown as the crew flew it: the
## CSM's on P30 and P40 or P41, the LM's on P30 and P40, P41 or P42. The
## flight's figures are the Fidelity table in README.md, each held here
## within set limits of Apollo 10's: the Apollo 10 Mission Report
## (MSC-00126), the AS-505 postflight trajectory (Boeing D5-15560-5) and
## the Apollo Flight Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s: time
## enough for the auto maneuver's 1°/s to turn to any attitude, and less
## than the checklists' quarter of an hour, for the suite's time.
const LEAD_S := 300.0

var sq: MissionSequencer


## The PAD of [param kind] timeline entry [param id] brought, or {} when
## the RTCC found no burn required.
func _await_pad(id: String, kind: String) -> Dictionary:
	sq.pads.erase(kind)
	assert_true(run_until(func() -> bool: return sq.timeline_done.has(id), 150.0 * 3600.0, 60.0), id)
	return sq.pads.get(kind, {})


## Fly the CSM's [param pad] as the crew does (fly_pad(), a P52 first for
## option [param p52] unless 0). Returns the ΔV the CMC sensed (ft/s) and
## how long the SPS burned (s; none on the RCS).
func _fly(pad: Dictionary, p52: int = 1) -> Vector2:
	if pad.is_empty():
		return Vector2.ZERO
	var burned := float(Bus.get_value("sps.burn_time_s", 0.0))
	var dv := fly_pad(p52, LEAD_S)
	return Vector2(dv / Units.FT, float(Bus.get_value("sps.burn_time_s", 0.0)) - burned)


## Fly the LM's stored or uplinked burn on program [param prog] with the
## engine armed at [param arm] (fly_lm_pad()). Returns x the ΔV the LGC
## sensed (ft/s), y the engine's time from the ignition command to the
## cutoff command (s, to a second), z the DPS's throttle 10 s after
## ignition and w 35 s after (per cent). [param in_place] burns P41 where
## Snoopy is (a midcourse correction).
func _lm_burn(prog: int, arm: int, from_p30: bool = true, in_place: bool = false) -> Vector4:
	var lgc := rt.lgc()
	var box := {"off": -1.0, "ign": -1.0, "t10": -1.0, "t35": -1.0}
	var dv := fly_lm_pad(prog, arm, func() -> void:
		if lgc.ignition_get > 0.0:
			box["ign"] = lgc.ignition_get
			var since := SimClock.get_seconds - lgc.ignition_get
			if since >= 10.0 and box["t10"] < 0.0:
				box["t10"] = float(Bus.get_value("lm.dps.throttle_pct", 0.0))
			if since >= 35.0 and box["t35"] < 0.0:
				box["t35"] = float(Bus.get_value("lm.dps.throttle_pct", 0.0))
		if lgc.step_name in ["tailoff", "post"] and box["off"] < 0.0:
			box["off"] = SimClock.get_seconds, from_p30, LEAD_S, in_place)
	return Vector4(dv / Units.FT, float(box["off"]) - float(box["ign"]), box["t10"], box["t35"])


## The pericynthion ahead: x its altitude (nmi), y its GET.
func _pericynthion() -> Vector2:
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, SimClock.get_seconds + 5.0 * 86400.0)
	return Vector2((float(ap["rp"]) - Bodies.R_MOON) / Units.NMI, Rtcc._pericynthion_time(tr))


## [param tr]'s orbit about the Moon: apolune and perilune above the
## landing site's radius (the mission report's datum), nmi.
func _orbit(tr: Trajectory) -> Vector2:
	var c := tr.conic()
	var r := sq.landing_site().length()
	return Vector2(float(c["ra"]) - r, float(c["rp"]) - r) / Units.NMI


## The LM's height over the terrain under it, m.
func _lm_height() -> float:
	var tr := rt.dynamics.lm.traj
	var mf := Bodies.moon_fixed(tr.t).transposed() * tr.pos()
	return mf.length() - Terrain.radius_under(mf)


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_10_flies_its_data_from_the_parking_orbit_to_the_splashdown() -> void:
	build("parking_orbit", "apollo_10")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_true(rt.dynamics.has_lm(), "Snoopy in the adapter")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:33:27.6 to 2:39:10.5, 10,025
	# ft/s gained (MSC-00126, Table 6-II), C3 -1,308,471 m2/s2 at TLI, 10 s on
	# (D5-15560-5, Table 3-V); past the Moon 907.7 nmi up at 76:10:18.4
	# (MSC-00126, Table 6-III).
	assert_true(run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 4.0 * 3600.0, 60.0), "TLI")
	assert_string_contains(str(Bus.get_value("mission.capcom", "")), "TLI cutoff")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	var tli: Dictionary = sq.tli_pad
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	var p := _pericynthion()
	rows.append("TLI | GET %s, %.0f m/s in %.1f s, C3 %.0f m²/s²; the pericynthion after it %.1f nmi at %s | 2:33:28, 3,056 m/s in 342.9 s, C3 −1,308,471 m²/s²; 907.7 nmi at 76:10:18" % [
		_hms(ign), float(tli["dv"]), cut - ign, c3, p.x, _hms(p.y)])
	assert_almost_eq(ign, _get_s("2:33:27.6"), 60.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 342.9, 5.0, "its burn")
	assert_almost_eq(float(tli["dv"]), 3055.6, 15.0, "the speed it gave")
	assert_almost_eq(c3, -1308471.0, 20000.0, "C3")
	assert_almost_eq(p.x, 907.7, 10.0, "the free return's pericynthion")
	assert_almost_eq(p.y, _get_s("76:10:18.4"), 60.0, "and when")

	# CSM/LV SEP, transposition, docking and extraction after the scripted
	# delay; then the evasive maneuver on the SPS: the PAD's 19.7 ft/s,
	# N81 +5.1, 0, +19.0, flown 18.8 ft/s; the pericynthion after it 286.1
	# nmi at 76:40:01.4 (Table 6-III).
	var ev := _await_pad("evasive", "sep")
	assert_eq(rt.dynamics.config, "csm_lm", "Snoopy docked since the transposition")
	var evf := _fly(ev, 0)
	p = _pericynthion()
	rows.append("The evasive maneuver | %.1f ft/s on the SPS; the pericynthion after it %.1f nmi at %s | 18.8 ft/s (PAD 19.7); 286.1 nmi at 76:40:01" % [
		evf.x, p.x, _hms(p.y)])
	assert_almost_eq(evf.x, 19.7, 0.5, "the evasive maneuver")
	assert_almost_eq(p.x, 286.1, 40.0, "the pericynthion after it")
	assert_almost_eq(p.y, _get_s("76:40:01.4"), 300.0, "and when")

	# MCC-1 on the SPS: the PAD's 48.7 ft/s at 26:32:56.10, N81 -39.8, +10.9,
	# -25.8 (Apollo Flight Journal, 25:37:52), flown 49.2; 60.9 nmi at
	# 76:00:15.2 after it (Table 6-III). MCC-4, 5 h before LOI, the ground's
	# 2.8 ft/s not flown: the perilune was 60.7 nmi 3.5 h out (section 6.4).
	var mcc1 := _await_pad("mcc1_pad", "mcc")
	assert_false(mcc1.is_empty(), "MCC-1")
	var mcc1_n81: Vector3 = mcc1["dv_lvlh"] / Units.FT
	_fly(mcc1)
	p = _pericynthion()
	rows.append("MCC-1 | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 48.7 ft/s at 26:32:56, N81 −39.8, +10.9, −25.8 (flown 49.2); then 60.9 nmi at 76:00:15" % [
		float(mcc1["dv"]) / Units.FT, _hms(float(mcc1["tig"])), mcc1_n81.x, mcc1_n81.y, mcc1_n81.z, p.x, _hms(p.y)])
	assert_almost_eq(float(mcc1["dv"]) / Units.FT, 48.7, 5.0, "MCC-1")
	assert_almost_eq(p.x, 60.9, 7.0, "the pericynthion after it, off by MSFN's tracking error")
	assert_almost_eq(p.y, _get_s("76:00:15.2"), 60.0, "and when")
	var mcc4 := _await_pad("mcc4_pad", "mcc")
	_fly(mcc4)
	p = _pericynthion()
	rows.append("MCC-4 | %.1f ft/s; then %.1f nmi at %s | 2.8 ft/s, not flown; 60.7 nmi" % [float(mcc4.get("dv", 0.0)) / Units.FT, p.x, _hms(p.y)])
	assert_lt(float(mcc4.get("dv", 0.0)) / Units.FT, 6.0, "MCC-4, a trim")
	assert_almost_eq(p.x, 60.7, 2.0, "the pericynthion before LOI")
	assert_almost_eq(p.y, _get_s("76:00:15.2"), 30.0, "and when")

	# LOI-1 behind the Moon at the PAD's TIG, 75:55:53.31: N81 -2,913.8,
	# -561.2, +299.7 up, turning the orbit 6 deg into the plane over the site;
	# flown 2,982.4 ft/s in 356.1 s into 170.0 x 60.2 nmi (Table 6-IV), the
	# orbit 1.2 deg to the lunar equator as planned (MSC Internal Note
	# 69-FM-96, section 5.7).
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI-1")
	var loi_n81: Vector3 = loi["dv_lvlh"] / Units.FT
	run(_get_s("74:46:55") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you are Go for LOI")
	var flown := _fly(loi)
	var o := _orbit(rt.dynamics.traj)
	var rel := rt.dynamics.traj.moon_state_rel()
	var h := Vector3(rel[0], rel[1], rel[2]).cross(Vector3(rel[3], rel[4], rel[5])).normalized()
	var incl := rad_to_deg(acos(clampf(-h.dot(Bodies.moon_pole(rt.dynamics.traj.t)), -1.0, 1.0)))
	rows.append("LOI-1 | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; %.1f × %.1f nmi, %.2f deg to the lunar equator | 75:55:53, N81 −2,913.8, −561.2, −299.7; 2,982 ft/s in 356.1 s; 170.0 × 60.2 nmi, 1.2 deg planned" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(flown.x, 2982.4, 150.0, "LOI-1's ΔV")
	assert_lt(loi_n81.y, -300.0, "a plane change into the orbit over the site")
	assert_almost_eq(flown.y, 356.1, 30.0, "its burn")
	assert_almost_eq(o.x, 170.0, 3.0, "apolune")
	assert_almost_eq(o.y, 60.2, 3.0, "perilune")
	assert_almost_eq(incl, 1.2, 0.6, "the first landing's orbit")

	# LOI-2 two revolutions on: 139.0 ft/s at 80:25:08.1 into 61.0 x 59.2 nmi
	# (Table 6-IV).
	var loi2 := _await_pad("loi2_pad", "circ")
	flown = _fly(loi2)
	o = _orbit(rt.dynamics.traj)
	var t_loi2 := float(burn_log["before"].t)
	rows.append("LOI-2 | GET %s, %.1f ft/s; %.1f × %.1f nmi | 80:25:08, 139.0 ft/s; 61.0 × 59.2 nmi" % [_hms(t_loi2), flown.x, o.x, o.y])
	assert_almost_eq(t_loi2, _get_s("80:25:08.1"), 300.0, "LOI-2 at the perilune")
	assert_almost_eq(flown.x, 139.0, 5.0, "LOI-2's ΔV")
	assert_almost_eq(o.x, 61.0, 2.0, "apolune")
	assert_almost_eq(o.y, 59.2, 2.0, "perilune")

	# The CSM's separation PAD, docked, for after the undocking at 98:11:57:
	# 2.5 ft/s radially down at 98:47:16 on the SM RCS, into 62.9 x 57.7 nmi
	# (MSC-00126, section 4, Table 6-IV).
	var sep := _await_pad("sep_pad", "sep")
	assert_true(bool(sep.get("uplinked", false)), "the separation PAD in the CMC")
	run(_get_s("98:11:57") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Go for undocking")
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "undocked")
	Bus.set_value("ctl.lm.mode", 0)
	var sepf := fly_pad(0, LEAD_S) / Units.FT
	o = _orbit(rt.dynamics.traj)
	rows.append("The CSM's separation | %.1f ft/s radially down; Charlie Brown in %.1f × %.1f nmi | 2.5 ft/s; 62.9 × 57.7 nmi" % [sepf, o.x, o.y])
	assert_almost_eq(sepf, 2.5, 0.3, "the separation")
	assert_almost_eq(o.x, 62.9, 2.0, "Charlie Brown's apolune")
	assert_almost_eq(o.y, 57.7, 2.0, "and perilune")

	# Snoopy's first P52 (slice 11a), torqued at 99:20 on stars 33
	# (Antares) and 25 (Acrux): its star angle difference 0.09° and N93
	# -0.668, -0.195 and -0.055° (MSC-00126, Table 8.6-II). The platform
	# stood so at undocking, less the drift since (mission.json
	# "lgc": first_p52).
	run(_get_s("99:17:00") - SimClock.get_seconds)
	var p52 := lm_realign([33, 25])
	var n93: Vector3 = p52["torque"]
	rows.append("Snoopy's first P52 | GET %s on stars 33 and 25: N05 %.3f°, N93 %+.3f, %+.3f and %+.3f° | 99:20: 0.09°; −0.668, −0.195 and −0.055°" % [
		_hms(float(p52["get"])), p52["sad"], n93.x, n93.y, n93.z])
	assert_almost_eq(n93, Vector3(-0.668, -0.195, -0.055), Vector3.ONE * 0.015, "N93 as flown")
	assert_lt(float(p52["sad"]), 0.09, "N05 within the flown")
	assert_lt(rad_to_deg(rt.lgc().imu.misalignment().length()), 0.01, "the platform on the REFSMMAT")

	# DOI on the DPS, 15 s at 10 % and then 40 %: the PAD's 71.3 ft/s at
	# 99:46:00.89 (Apollo Flight Journal, 98:28:05); flown 71.3 ft/s in 27.4 s
	# into 60.9 x 8.5 nmi (Table 6-IV).
	var doi: Dictionary = sq.pads.get("doi", {})
	assert_false(doi.is_empty(), "the DOI PAD after undocking")
	var lm := rt.dynamics.lm
	var dps := _lm_burn(40, 2)
	o = _orbit(lm.traj)
	rows.append("DOI | GET %s, %.1f ft/s in %.0f s; %.1f × %.1f nmi | 99:46:01, 71.3 ft/s in 27.4 s; 60.9 × 8.5 nmi" % [
		_hms(float(doi["tig"])), dps.x, dps.y, o.x, o.y])
	assert_eq(sq.phase, "lunar_descent")
	assert_almost_eq(float(doi["tig"]), _get_s("99:46:00.89"), 180.0, "DOI's time")
	assert_almost_eq(dps.x, 71.3, 5.0, "DOI's ΔV")
	assert_almost_eq(dps.y, 27.4, 3.0, "its burn")
	assert_almost_eq(o.x, 60.9, 2.0, "Snoopy's apolune")
	assert_almost_eq(o.y, 8.5, 2.0, "and perilune: 8 nmi over the site")

	# The low pass over site 2, without a landing: 47,400 ft at the lowest by
	# the landing radar, 56,783 ft above the site's radius over it, the track
	# about 5 miles south of it (MSC-00126, sections 1, 6.5 and 8.8).
	var low := INF
	var site := sq.landing_site()
	var site_sel := Bodies.fixed_to_selenographic(site)
	var prev_lon := INF
	var cross := Vector2.INF
	while not sq.pads.has("phasing") or SimClock.get_seconds < float(sq.plan["phasing_tig"]) - 600.0:
		run(2.0)
		low = minf(low, _lm_height())
		var mf := Bodies.moon_fixed(lm.traj.t).transposed() * lm.traj.pos()
		var sel := Bodies.fixed_to_selenographic(mf)
		if prev_lon != INF and prev_lon >= site_sel.y and sel.y < site_sel.y:
			cross = Vector2(mf.length() - site.length(), (site_sel.x - sel.x) * PI / 180.0 * Bodies.R_MOON)
		prev_lon = sel.y
	rows.append("The low pass | %.0f ft over the terrain at the lowest; over the site %.0f ft up, %.1f nmi south of it | 47,400 ft by the landing radar; 56,783 ft, about 5 miles south" % [
		low / Units.FT, cross.x / Units.FT, cross.y / Units.NMI])
	assert_almost_eq(low / Units.FT, 47400.0, 5000.0, "the lowest")
	assert_almost_eq(cross.x / Units.FT, 56783.0, 5000.0, "over the site")
	assert_between(cross.y / Units.NMI, 0.0, 8.0, "a few miles south of it")

	# The phasing burn on the DPS, the PAD's: 176.9 ft/s at 100:58:25.20, 10 %
	# for 26 s then full (MSC Internal Note 69-FM-96, section 5.11.3); flown
	# 176.0 ft/s in 40.0 s, 13.1 % at 10 s and full at 35 s, into 190.1 x
	# 12.1 nmi (MSC-00126, Tables 6-IV and 8.8-I).
	var ph: Dictionary = sq.pads["phasing"]
	assert_almost_eq(float(ph["tig"]) - float(sq.plan["pdi_tig"]), 879.7, 0.01, "as long after the low point as flown")
	dps = _lm_burn(40, 2)
	o = _orbit(lm.traj)
	rows.append("The phasing burn | GET %s, %.1f ft/s in %.0f s, %.0f %% at 10 s and %.0f %% at 35 s; %.1f × %.1f nmi | 100:58:26, 176.0 ft/s in 40.0 s, 13.1 %% and full; 190.1 × 12.1 nmi" % [
		_hms(float(ph["tig"])), dps.x, dps.y, dps.z, dps.w, o.x, o.y])
	assert_almost_eq(dps.x, 176.9, 3.0, "the phasing burn")
	assert_almost_eq(dps.y, 40.0, 3.0, "its burn")
	assert_almost_eq(dps.z, 10.0, 1.0, "at the start throttle")
	assert_almost_eq(dps.w, 100.0, 1.0, "then at full thrust")
	assert_almost_eq(o.x, 190.1, 4.0, "the dwell orbit's apolune")
	assert_almost_eq(o.y, 12.1, 2.0, "and perilune")

	# Staging in orbit, 9 min 45 s before the insertion as flown (102:45:16.9):
	# the ascent stage 8,273 lb (Table A.4-I); then the insertion on the APS,
	# the PAD's 220.9 ft/s at 102:55:01.40 (Apollo Flight Journal,
	# 101:09:31), flown in 15.5 s into 46.5 x 11.0 nmi (Table 6-IV).
	var ins: Dictionary = _await_pad("insertion_pad", "insertion") if not sq.timeline_done.has("insertion_pad") \
		else sq.pads.get("insertion", {})
	assert_false(ins.is_empty(), "the insertion PAD")
	run(float(ins["tig"]) - 584.5 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for staging")
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	assert_eq(lm.config, "lm_ascent", "staged")
	assert_eq(sq.phase, "lunar_ascent", "the ascent stage flying")
	var staged := lm.mass / Units.LBM
	var aps := _lm_burn(42, 1)
	run(5.0, false)
	o = _orbit(lm.traj)
	var t_ins := sq.event_get("lm_insertion")
	rows.append("Staging and the insertion | the ascent stage %.0f lb; GET %s, %.1f ft/s in %.0f s; %.1f × %.1f nmi | 8,273 lb; 102:55:02, 220.9 ft/s in 15.5 s; 46.5 × 11.0 nmi" % [
		staged, _hms(float(ins["tig"])), aps.x, aps.y, o.x, o.y])
	assert_almost_eq(staged, 8273.0, 300.0, "the ascent stage")
	assert_gt(t_ins, float(ins["tig"]), "the insertion")
	assert_almost_eq(aps.x, 220.9, 2.0, "the insertion's ΔV")
	assert_almost_eq(aps.y, 15.5, 3.0, "its burn: the report's masses and thrust give 17.6 s")
	assert_almost_eq(o.x, 46.5, 2.0, "apolune")
	assert_almost_eq(o.y, 11.0, 2.0, "perilune")

	# The coelliptic sequence on the LGC's P32 to P35 and the LM RCS: CSI
	# 45.3 ft/s at 103:45:55.3 into 48.7 x 40.7 nmi; CDH 3.0 ft/s at
	# 104:43:53.3, 15.0 nmi below Charlie Brown; TPI 24.1 ft/s at 105:22:55.6;
	# two small midcourse corrections; docking at 106:22:02, Charlie Brown
	# active (MSC-00126, Tables 6-II and 6-IV).
	assert_true(run_until(func() -> bool: return sq.pads.has("csi"), 3600.0, 1.0), "the CSI PAD")
	var pad: Dictionary = sq.pads["csi"]
	var lgc := rt.lgc()
	var lm0 := lm.dv_total
	# The crew's P52 after insertion, before P20's marks, on two stars they
	# can see [estimated: as Apollo 11's crew flew theirs, the Apollo Flight
	# Journal, 124:32:44].
	lm_realign(visible_star_pair())
	# The coelliptic sequence on P20's marks as Apollo 11's crew flew it
	# (lm_coelliptic()), each burn where the LM is, its +Z on the CSM.
	var holder := {}
	var got := lm_coelliptic(pad, func(name: String) -> Vector4:
		var b := _lm_burn(41, 0, false, true)
		if name == "CSI":
			holder["o_csi"] = _orbit(lm.traj)
		return b)
	var csi: Vector4 = got["CSI"]
	var o_csi: Vector2 = holder["o_csi"]
	var dh := float(got["dh"])
	var t_cdh := float(got["cdh_tig"])
	var cdh: Vector4 = got["CDH"]
	var tpi_tig := float(got["tpi_tig"])
	var tpi: Vector4 = got["TPI"]
	var tpm := (got["TPM1"] as Vector4).x + (got["TPM2"] as Vector4).x
	assert_true(lm_brake(1800.0), "braked to station-keeping")
	var lm_dv := (lm.dv_total - lm0) / Units.FT
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	assert_true(dock_contact()["captured"], "within the capture limits")
	var docked := sq.event_get("docking")
	rows.append("CSI | GET %s, %.1f ft/s; %.1f × %.1f nmi | 103:45:55, 45.3 ft/s; 48.7 × 40.7 nmi" % [
		_hms(float(pad["tig"])), csi.x, o_csi.x, o_csi.y])
	rows.append("CDH | GET %s, %.1f ft/s, %.1f nmi below Charlie Brown | 104:43:53, 3.0 ft/s, 15.0 nmi" % [_hms(t_cdh), cdh.x, dh / Units.NMI])
	rows.append("TPI | GET %s, %.1f ft/s; the midcourse corrections %.1f ft/s | 105:22:56, 24.1 ft/s; small" % [_hms(tpi_tig), tpi.x, tpm])
	rows.append("Docking | GET %s, the LM's RCS %.0f ft/s from CSI | 106:22:02" % [_hms(docked), lm_dv])
	assert_almost_eq(csi.x, 45.3, 8.0, "CSI")
	assert_almost_eq(o_csi.y, 40.7, 2.0, "the orbit CSI left")
	assert_lt(cdh.x, 10.0, "CDH")
	assert_almost_eq(dh / Units.NMI, 15.0, 3.0, "coelliptic, about 15 nmi below")
	assert_almost_eq(tpi.x, 24.1, 6.0, "TPI")
	assert_almost_eq(tpi_tig, _get_s("105:22:55.6"), 900.0, "TPI's time")
	assert_lt(tpm, 10.0, "small midcourse corrections")
	assert_almost_eq(docked, _get_s("106:22:02"), 1800.0, "docked")
	assert_eq(sq.phase, "lunar_orbit", "docked again")

	# GO for jettison, LM JETT (108:24:36), and TEI: the TEI-31 PAD's
	# 137:36:28.21, N81 +3,625.2, +40.0, +188.0; flown 3,630.2 ft/s in
	# 164.8 s (MSC-00126, Table 7.6-V).
	Bus.set_value("ctl.cmc.mode", 0)
	run(docked + 6986.0 + 10.0 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "looking good for Sep")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	assert_eq(rt.dynamics.config, "csm", "Snoopy's ascent stage jettisoned")
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	var tei_n81: Vector3 = tei["dv_lvlh"] / Units.FT
	run(_get_s("136:57:55") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "everything looks Go for TEI")
	flown = _fly(tei)
	rows.append("TEI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s | 137:36:29, N81 +3,625.2, +40.0, +188.0; 3,630 ft/s in 164.8 s" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y])
	assert_almost_eq(float(tei["tig"]), _get_s("137:36:28.9"), 30.0, "TEI's time")
	assert_almost_eq(flown.x, 3630.2, 30.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 164.8, 15.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# The transearth midcourse corrections on the RCS: MCC-6's PAD for 1.2
	# ft/s, not flown; MCC-7, 2.2 ft/s at 188:49:58 (MSC-00126, Table 6-V).
	# MSFN's tracking error in the TEI PAD's state vector moves the return
	# far more than the flight's did (README, Simplifications).
	var mccs := []
	for id in ["mcc6_pad", "mcc7_pad"]:
		var m := _await_pad(id, "mcc")
		mccs.append(float(m.get("dv", 0.0)) / Units.FT)
		_fly(m)
	rows.append("Transearth midcourse corrections | MCC-6 %.1f ft/s, MCC-7 %.1f ft/s | MCC-6 not flown, MCC-7 2.2 ft/s" % mccs)
	assert_lt(float(mccs[0]) + float(mccs[1]), 25.0, "trims")
	assert_lt(float(mccs[1]), 8.0, "MCC-7, a trim")

	# The entry PAD's last update, 190:49:05: 15.07 S 164.67 W; then P52
	# before the entry, and GO for pyro arm.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(-15.07, -164.67), "N61 uplinked")
	run(_get_s("191:00:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_pyro_arm"), 3.0 * 3600.0, 60.0), "home")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You are Go for Pyro Arm")

	# Entry interface: 191:48:54.5, 36,314 ft/s, 6.54 deg down, at 23.60 S
	# 174.39 E (MSC-00126, Table 6-II).
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 3600.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f S %.2f E | 191:48:55, 36,314 ft/s, 6.54 deg down, 23.60 S 174.39 E" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, -geo.x, geo.y])
	assert_almost_eq(ei.t, _get_s("191:48:54.5"), 120.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36314.0, 20.0, "its speed")
	assert_almost_eq(ei_gamma, -6.54, 0.2, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(-23.60, 174.39)) * Bodies.R_EARTH / Units.NMI, 40.0, "where")

	# The entry on P61 to P67 to 15.07 S 164.67 W: 6.78 g at the peak; down
	# at 192:03:23, 15.06 S 164.65 W by the best estimate, 1.3 nmi from the
	# target (MSC-00126, section 7.6).
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 6.78 g" % [str(fe["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.2f S %.2f W, %.1f nmi from the target | 192:03:23, 15.06 S 164.65 W, 1.3 nmi from it" % [
		_hms(land), -at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 10.")
	assert_almost_eq(rt.dynamics.max_g, 6.78, 0.6, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(land, _get_s("192:03:23"), 180.0, "splashdown's time")
	assert_false(sq.events.any(func(e: Dictionary) -> bool: return e["id"] in ["lm_landing", "lm_liftoff", "landing_lm"]),
		"Snoopy never landed")

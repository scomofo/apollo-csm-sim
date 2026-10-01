## Slice 12c (docs/ROADMAP.md, milestone 12): Apollo 16 from Descartes to
## TEI, from the lunar_surface start (tests/scenarios/test_apollo_16.gd
## flies it there; tests/scenarios/test_apollo_16_entry.gd flies it home
## from the way back). Orion's three days at Descartes pass in Houston's
## calls, with the word that TEI will come a day early, the SPS kept to the
## burns it must fly; Casper's one plane change puts its orbit over Orion
## for the liftoff; the crew align the platform with P57 and lift off on
## the ground's direct rendezvous, the tweak a few minutes after the
## insertion, TPI on the ascent engine at the TIG the ascent PAD gave, and
## no CSI or CDH. Then the night docked, LM JETT the next day, and TEI onto
## the return, a day early. Each PAD is flown as the crew flew it: the
## CSM's on P30 and P40 or P41, the LM's on P57, P12, P41, P20, P34 and
## P42, and P35. The flight's figures are the Fidelity table in README.md,
## each held here within set limits of Apollo 16's: the Apollo 16 Mission
## Report (MSC-07230), the Apollo Flight Journal and the Apollo Lunar
## Surface Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s.
const LEAD_S := 300.0

var sq: MissionSequencer


func after_all() -> void:
	# Back to Apollo 11's world and vehicles for the tests after these.
	Mission.load_default()


## The PAD of [param kind] timeline entry [param id] brought, or {} when
## the RTCC found no burn required.
func _await_pad(id: String, kind: String) -> Dictionary:
	sq.pads.erase(kind)
	assert_true(run_until(func() -> bool: return sq.timeline_done.has(id), 150.0 * 3600.0, 60.0), id)
	return sq.pads.get(kind, {})


## Fly the CSM's [param pad] as the crew does (fly_pad(), a P52 first).
## Returns the ΔV the CMC sensed (ft/s) and how long the SPS burned (s).
func _fly(pad: Dictionary) -> Vector2:
	if pad.is_empty():
		return Vector2.ZERO
	var burned := float(Bus.get_value("sps.burn_time_s", 0.0))
	var dv := fly_pad(1, LEAD_S)
	return Vector2(dv / Units.FT, float(Bus.get_value("sps.burn_time_s", 0.0)) - burned)


## Fly the LM's stored or uplinked burn on program [param prog] with the
## engine armed at [param arm] (fly_lm_pad()). Returns x the ΔV the LGC
## sensed (ft/s) and y the engine's time from the ignition command to the
## cutoff command (s). [param in_place] burns P41 where Orion is.
func _lm_burn(prog: int, arm: int, from_p30: bool, in_place: bool) -> Vector2:
	var lgc := rt.lgc()
	var box := {"off": -1.0, "ign": -1.0}
	var dv := fly_lm_pad(prog, arm, func() -> void:
		if lgc.ignition_get > 0.0:
			box["ign"] = lgc.ignition_get
		if lgc.step_name in ["tailoff", "post"] and box["off"] < 0.0:
			box["off"] = SimClock.get_seconds, from_p30, LEAD_S, in_place)
	return Vector2(dv / Units.FT, float(box["off"]) - float(box["ign"]))


## [param tr]'s orbit about the Moon: apolune and perilune above the
## landing site's radius (the mission report's datum), nmi.
func _orbit(tr: Trajectory) -> Vector2:
	var c := tr.conic()
	var r := sq.landing_site().length()
	return Vector2(float(c["ra"]) - r, float(c["rp"]) - r) / Units.NMI


## The CSM from the LM at GET [param t] (now, or ahead as they coast): x
## the range (nmi), y the elevation (deg), z how far the LM is below it
## (nmi).
func _rel(t: float = -1.0) -> Vector3:
	var lm := rt.dynamics.lm.traj.clone()
	var cm := rt.dynamics.traj.clone()
	if t > SimClock.get_seconds:
		lm.coast_to(t, 20.0)
		cm.coast_to(t, 20.0)
	return Vector3(Rendezvous.rel_pos(lm, cm).length() / Units.NMI, rad_to_deg(Rendezvous.elevation(lm, cm)),
		(cm.radius() - lm.radius()) / Units.NMI)


func _n81(pad: Dictionary) -> Vector3:
	return pad["dv_lvlh"] / Units.FT


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_16_flies_from_descartes_to_tei_a_day_early() -> void:
	build("lunar_surface", "apollo_16")
	sq = rt.sequencer
	var lgc := rt.lgc()
	var lm := rt.dynamics.lm
	assert_true(lm.landed, "Orion at Descartes")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Stay")
	var rows := PackedStringArray()

	# The stays: T-1 and T-2 within minutes of the landing, T-3 36 min on
	# (the Apollo Lunar Surface Journal); and Roosa's word to Mattingly at
	# 129:41:56 that TEI would be about a day early, the second plane change
	# and the shaping burn deleted (Apollo Flight Journal; MSC-07230, p.
	# 5-5).
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("stay_t3"), 7200.0, 60.0), "the stay")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "stay for T-3")
	assert_almost_eq(float(sq.timeline_done["stay_t3"]) - sq.event_get("lm_landing"), 2139.0, 60.0, "36 min after the landing")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("tei_early"), 30.0 * 3600.0, 60.0), "TEI brought forward")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "TEI will be approximately a day early")

	# Casper's one plane change (LOPC-1), over Orion at the liftoff: the
	# PAD's N81 -1.5, -124.7, 0 at 169:05:51.49 into 64.5 x 55.3 nmi
	# (Apollo Flight Journal, 167:20:18, its TIG on the updated clock less
	# 11 min 48 s); flown 124.0 ft/s in 7.1 s into 64.6 x 55.0 nmi
	# (MSC-07230, Table 3-V(b)), Hartsfield's GO before the loss of signal at
	# 168:14:23.
	var lopc1 := _await_pad("lopc1_pad", "plane")
	assert_false(lopc1.is_empty(), "LOPC-1")
	var lopc1_n81 := _n81(lopc1)
	var flown := _fly(lopc1)
	assert_true(sq.timeline_done.has("go_lopc1"), "Go for the plane change")
	assert_lt(float(sq.timeline_done["go_lopc1"]), float(lopc1["tig"]), "before the burn")
	var o := _orbit(rt.dynamics.traj)
	rows.append("The plane change (LOPC-1) | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi | 169:05:52, N81 −1.5, −124.7, 0; 124.0 ft/s in 7.1 s; 64.6 × 55.0 nmi" % [
		_hms(float(lopc1["tig"])), lopc1_n81.x, lopc1_n81.y, lopc1_n81.z, flown.x, flown.y, o.x, o.y])
	assert_almost_eq(float(lopc1["tig"]), _get_s("169:05:51.49"), 300.0, "LOPC-1's time")
	assert_lt(lopc1_n81.y, -60.0, "the node the flight burned at")
	assert_almost_eq(flown.x, 124.0, 50.0, "LOPC-1's ΔV")
	assert_almost_eq(o.x, 66.0, 4.0, "apolune")
	assert_almost_eq(o.y, 55.0, 3.0, "perilune")

	# The ascent PAD for the direct rendezvous at 173:55:19: liftoff at
	# 175:31:47.18, N76 5,525.2 and 32.0 ft/s, crossrange +0.2 nmi; N37,
	# TPI's TIG, 176:26:04.00 (Apollo Lunar Surface Journal, its times on the
	# updated clock less 11 min 48 s); flown 175:31:47.9, 427.7 s on the APS
	# into 40.2 x 7.9 nmi (MSC-07230, Table 3-V(b); the APS's final flight
	# evaluation). Go for lift-off at 175:23:42.
	var asc := _await_pad("ascent_pad", "ascent")
	assert_false(asc.is_empty(), "the ascent PAD")
	var tig := float(asc["tig"])
	var tpi_pad := float(sq.plan["tpi_tig"])
	assert_eq(lgc.rdv_tpi_tig, tpi_pad, "TPI's TIG in the LGC (N37)")
	# The crew's last P57 before the liftoff, option 4 on gravity and a star.
	run(tig - 2400.0 - SimClock.get_seconds)
	var sighted := AotCrew.surface_stars(self)
	var p57 := surface_align(4, 3, [int(sighted[0])])
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.05, "the platform aligned for the ascent")
	keys("V37E12E", lgc)
	assert_eq(lgc.program, 12, "P12")
	keys("P", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(maxf(tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for lift-off")
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	Bus.set_value("ctl.lm.engine_arm", 1)
	keys("P", lgc)
	var cutoff := {"t": -1.0}
	assert_true(run_until(func() -> bool:
		if lgc.step_name in ["tailoff", "post"] and float(cutoff["t"]) < 0.0:
			cutoff["t"] = SimClock.get_seconds
		return lgc.step_name == "post", 900.0, 1.0, false), "insertion")
	var liftoff := sq.event_get("lm_liftoff")
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	Bus.set_value("ctl.lm.mode", 0)
	run(5.0, false)
	lm = rt.dynamics.lm
	o = _orbit(lm.traj)
	var at_ins := _rel()
	rows.append("The ascent | the P57 at %s, N05 %.2f; liftoff %s, N76 %.1f and %.1f ft/s, %+.2f nmi crossrange, TPI's TIG %s; %.0f s on the APS; %.1f × %.1f nmi, Casper %.0f nmi ahead | liftoff 175:31:48, N76 5,525.2 and 32.0 ft/s, +0.2 nmi, TPI 176:26:04; 427.7 s; 40.2 × 7.9 nmi" % [
		_hms(float(p57["get"])), p57["sad"], _hms(liftoff), float(asc["vh"]) / Units.FT, float(asc["hdot"]) / Units.FT,
		float(asc["xrng"]) / Units.NMI, _hms(tpi_pad), float(cutoff["t"]) - liftoff, o.x, o.y, at_ins.x])
	assert_almost_eq(liftoff, _get_s("175:31:47.9"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(tpi_pad - liftoff, _get_s("176:26:04.00") - _get_s("175:31:47.18"), 60.0, "TPI 54 min after it")
	assert_almost_eq(float(asc["vh"]) / Units.FT, 5525.2, 10.0, "N76's horizontal velocity")
	assert_almost_eq(float(asc["hdot"]) / Units.FT, 32.0, 0.1, "and its climb")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.0, "under a mile of crossrange: LOPC-1 put the plane over Orion")
	assert_almost_eq(float(cutoff["t"]) - liftoff, 427.7, 25.0, "the ascent's burn")
	assert_almost_eq(o.x, 40.2, 2.5, "apolune")
	assert_almost_eq(o.y, 7.9, 1.5, "perilune")

	# The direct rendezvous on the LGC's P41, P20, P34 and P35
	# (RendezvousCrew.direct()): the tweak, the PAD's -2.0, -0, -10.0 at
	# 175:42:17 (Apollo Flight Journal, 175:40:24); TPI on the APS at
	# 176:26:05, 78.0 ft/s in 2.5 s, N81 +78.0, +2.7, +0.7; the midcourse
	# corrections 1.0 and 0.9 ft/s; braking done (TPF) at 177:08:42, and
	# docking at 177:41:18 after the crews had inspected each other's craft
	# (MSC-07230, Tables 3-I, 3-V(b) and 7-VI; Apollo Flight Journal).
	var lm0 := lm.dv_total
	var box := {}
	var got := RendezvousCrew.direct(self, func(name: String) -> Vector2:
		if name == "TPI":
			box["at_tpi"] = _rel(tpi_pad)
			return _lm_burn(42, 1, false, false)
		return _lm_burn(41, 0, name == "TWEAK", true))
	var tweak: Dictionary = sq.pads["tweak"]
	var tw: Vector2 = got["TWEAK"]
	var tpi: Vector2 = got["TPI"]
	var at_tpi: Vector3 = box["at_tpi"]
	var tpm := (got["TPM1"] as Vector2).x + (got["TPM2"] as Vector2).x
	assert_true(lm_brake(1800.0), "braked to station-keeping")
	var lm_rcs := (lm.dv_total - lm0) / Units.FT - tpi.x
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	assert_true(dock_contact()["captured"], "within the capture limits")
	var docked := sq.event_get("docking")
	rows.append("The tweak | GET %s, %.1f ft/s on the RCS | 175:42:18, 10.2 ft/s, the insertion 33,000 ft further downrange than desired" % [
		_hms(float(tweak["tig"])), tw.x])
	rows.append("TPI on the APS | GET %s, %.1f ft/s in %.1f s; Casper %.1f nmi off, %.1f deg up, Orion %.1f nmi below | 176:26:05, 78.0 ft/s in 2.5 s" % [
		_hms(float(got["tpi_tig"])), tpi.x, tpi.y, at_tpi.x, at_tpi.y, at_tpi.z])
	rows.append("Midcourse corrections and docking | %.1f ft/s together; docked %s, the LM's RCS %.0f ft/s since the insertion | 1.0 and 0.9 ft/s; TPF 177:08:42, docked 177:41:18 after the inspections" % [
		tpm, _hms(docked), lm_rcs])
	assert_almost_eq(float(tweak["tig"]), _get_s("175:42:17"), 300.0, "the tweak's time")
	assert_lt(tw.x, 25.0, "the tweak, a vernier adjustment")
	assert_eq(float(got["tpi_tig"]), tpi_pad, "TPI at the ascent PAD's TIG")
	assert_almost_eq(tpi.x, 78.0, 20.0, "TPI")
	assert_lt(tpm, 10.0, "small midcourse corrections")
	assert_almost_eq(docked, _get_s("177:08:42"), 1200.0, "docked as the flight's braking ended, without the half hour's inspections")
	assert_eq(sq.phase, "lunar_orbit", "docked again")

	# Orion kept docked through the night: GO for Pyro Arm at 194:55:00 and
	# for LM JETT at 194:57:17, the jettison at 195:00:12 (MSC-07230, Table
	# 3-I; Apollo Flight Journal).
	Bus.set_value("ctl.cmc.mode", 0)
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_lm_jett"), 20.0 * 3600.0, 60.0), "Go for LM jett")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for LM jett")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	var jett := SimClock.get_seconds
	assert_eq(rt.dynamics.config, "csm", "Orion's ascent stage jettisoned")
	assert_almost_eq(jett - docked, _get_s("195:00:12") - _get_s("177:41:18"), 900.0, "the jettison's time, the next day")

	# TEI a day early: the TEI-64 PAD's TIG, 200:21:32.42, N81 +3,264.4,
	# +809.9, -225.7 (Apollo Flight Journal, 199:05:00, its TIG on the
	# updated clock less 11 min 48 s); flown 3,370.9 ft/s in 162.3 s after
	# 64 revolutions, the plan's on rev 76 at 222:20:32.8 (MSC-07230, Tables
	# 3-V(c) and 6-III; the final flight plan, Table 2-9), onto the return to
	# 0.71 S 156.18 W with entry interface at 265:37:31; the RTCC moves the
	# ignition to where the burn needs no part up or down, Casper coming
	# round to the flown TEI's place minutes early (mission.json "tei":
	# tig_free).
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	var tei_n81 := _n81(tei)
	run(_get_s("199:43:05") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you're Go for TEI")
	flown = _fly(tei)
	rows.append("TEI, a day early | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s | 200:21:33, N81 +3,264.4, +809.9, −225.7; 3,370.9 ft/s in 162.3 s, 21:59 before the plan's" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y])
	assert_almost_eq(float(tei["tig"]), _get_s("200:21:32.42"), 600.0, "TEI's time, where the burn needs no part up or down (tig_free)")
	assert_almost_eq(flown.x, 3370.9, 150.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 162.3, 20.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# Where the return comes in, as TEI left it: entry interface's GET and
	# angle (the RTCC's corridor, -6.5 deg; the flight's TEI gave -7.44 deg
	# at 265:36:52, MSC-07230, Table 3-V(c), and MCC-5 brought it back).
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 4.0 * 86400.0, 60.0, 0.002)
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	rows.append("The return after TEI | entry interface %s, %.2f deg down | 265:36:52, 7.44 deg down; the target 6.55" % [_hms(ei.t), -ei_gamma])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_almost_eq(ei.t, _get_s("265:37:31"), 600.0, "entry interface's time")
	assert_between(ei_gamma, -8.0, -5.5, "near the corridor, for the midcourse corrections to trim")

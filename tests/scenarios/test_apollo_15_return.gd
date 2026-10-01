## Slice 12b (docs/ROADMAP.md, milestone 12): Apollo 15 from Hadley to TEI,
## from the lunar_surface start (tests/scenarios/test_apollo_15.gd flies it
## there; tests/scenarios/test_apollo_15_entry.gd flies it home from the
## way back). Falcon's three days at Hadley pass in Houston's calls;
## Endeavour's plane change puts its orbit over Falcon for the liftoff; the
## crew align the platform with P57 and lift off on the ground's direct
## rendezvous, TPI 52 min after the liftoff with no tweak needed, on the
## ascent engine at the TIG the ascent PAD gave, and no CSI or CDH. Then
## LM JETT, a revolution late; the shaping burn the subsatellite's orbit
## wanted; and TEI onto the return. Each PAD is flown as the crew flew it:
## the CSM's on P30 and P40 or P41, the LM's on P57, P12, P20, P34 and P42,
## and P35. The flight's figures are the Fidelity table in README.md, each
## held here within set limits of Apollo 15's: the Apollo 15 Mission Report
## (MSC-05161), the flight controllers' postflight memos, the Apollo Flight
## Journal and the Apollo Lunar Surface Journal [published].
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


## Fly the LM's stored burn on program [param prog] with the engine armed
## at [param arm] (fly_lm_pad()). Returns x the ΔV the LGC sensed (ft/s)
## and y the engine's time from the ignition command to the cutoff command
## (s). [param in_place] burns P41 where Falcon is.
func _lm_burn(prog: int, arm: int, in_place: bool) -> Vector2:
	var lgc := rt.lgc()
	var box := {"off": -1.0, "ign": -1.0}
	var dv := fly_lm_pad(prog, arm, func() -> void:
		if lgc.ignition_get > 0.0:
			box["ign"] = lgc.ignition_get
		if lgc.step_name in ["tailoff", "post"] and box["off"] < 0.0:
			box["off"] = SimClock.get_seconds, false, LEAD_S, in_place)
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


func test_apollo_15_flies_from_hadley_to_tei() -> void:
	build("lunar_surface", "apollo_15")
	sq = rt.sequencer
	var lgc := rt.lgc()
	var lm := rt.dynamics.lm
	assert_true(lm.landed, "Falcon at Hadley")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Stay")
	var rows := PackedStringArray()

	# The stays: T1 and T2 within minutes of the landing, and the stay for
	# the three days 67 min on (the Apollo Lunar Surface Journal).
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("stay_t3"), 7200.0, 60.0), "the stay")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you have a Stay")
	assert_almost_eq(float(sq.timeline_done["stay_t3"]) - sq.event_get("lm_landing"), 4045.0, 60.0, "67 min after the landing")

	# Endeavour's plane change (LOPC-1), over Falcon at the liftoff, 3 deg:
	# the PAD's N81 -9.2, +330.3, +18.4 at 165:11:31.96 into 64.4 x 53.3 nmi
	# (Apollo Flight Journal, 163:26:31); flown 330.6 ft/s in 18.3 s into
	# 64.5 x 53.6 nmi (MSC-05161, Table 3-V).
	var lopc1 := _await_pad("lopc1_pad", "plane")
	assert_false(lopc1.is_empty(), "LOPC-1")
	var lopc1_n81 := _n81(lopc1)
	run(_get_s("164:12:40") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for plane change 1")
	var flown := _fly(lopc1)
	var o := _orbit(rt.dynamics.traj)
	rows.append("The plane change (LOPC-1) | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi | 165:11:32, N81 −9.2, +330.3, +18.4; 330.6 ft/s in 18.3 s; 64.5 × 53.6 nmi" % [
		_hms(float(lopc1["tig"])), lopc1_n81.x, lopc1_n81.y, lopc1_n81.z, flown.x, flown.y, o.x, o.y])
	assert_almost_eq(float(lopc1["tig"]), _get_s("165:11:31.96"), 300.0, "LOPC-1's time")
	assert_gt(lopc1_n81.y, 250.0, "the node the flight burned at")
	assert_almost_eq(flown.x, 330.6, 30.0, "LOPC-1's ΔV")
	assert_almost_eq(flown.y, 18.3, 3.0, "its burn")
	assert_almost_eq(o.x, 64.5, 2.0, "apolune")
	assert_almost_eq(o.y, 53.6, 2.0, "perilune")

	# The ascent PAD for the direct rendezvous at 170:40:39: liftoff at
	# 171:37:22.36, N76 5,530.4 and 32.0 ft/s, crossrange -0.4 nmi; N37,
	# TPI's TIG, 172:29:39.00 (Apollo Lunar Surface Journal); flown
	# 171:37:23.2, 431 s on the APS into 42.5 x 9.0 nmi (MSC-05161, Table
	# 3-V). Go for lift-off at 171:35:31.
	var asc := _await_pad("ascent_pad", "ascent")
	assert_false(asc.is_empty(), "the ascent PAD")
	var tig := float(asc["tig"])
	var tpi_pad := float(sq.plan["tpi_tig"])
	assert_eq(lgc.rdv_tpi_tig, tpi_pad, "TPI's TIG in the LGC (N37)")
	# The crew's last P57 before the liftoff, option 4 on gravity and a star
	# [published: the flight's platform stood some 0.08 deg off about Y at
	# the liftoff, most probably a gravity anomaly at the site (MSC-05161,
	# Supplement 1, p. 1-2)].
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
	rows.append("The ascent | the P57 at %s, N05 %.2f; liftoff %s, N76 %.1f and %.1f ft/s, %+.2f nmi crossrange, TPI's TIG %s; %.0f s on the APS; %.1f × %.1f nmi, Endeavour %.0f nmi ahead | liftoff 171:37:23, N76 5,530.4 and 32.0 ft/s, −0.4 nmi, TPI 172:29:39; 431 s; 42.5 × 9.0 nmi" % [
		_hms(float(p57["get"])), p57["sad"], _hms(liftoff), float(asc["vh"]) / Units.FT, float(asc["hdot"]) / Units.FT,
		float(asc["xrng"]) / Units.NMI, _hms(tpi_pad), float(cutoff["t"]) - liftoff, o.x, o.y, at_ins.x])
	assert_almost_eq(liftoff, _get_s("171:37:23.2"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(tpi_pad - liftoff, _get_s("172:29:39.00") - _get_s("171:37:22.36"), 60.0, "TPI 52 min after it")
	assert_almost_eq(float(asc["vh"]) / Units.FT, 5530.4, 10.0, "N76's horizontal velocity")
	assert_almost_eq(float(asc["hdot"]) / Units.FT, 32.0, 0.1, "and its climb")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.0, "under a mile of crossrange: LOPC-1 put the plane over Falcon")
	assert_almost_eq(float(cutoff["t"]) - liftoff, 431.0, 25.0, "the ascent's burn")
	assert_almost_eq(o.x, 42.5, 2.5, "apolune")
	assert_almost_eq(o.y, 9.0, 1.5, "perilune")

	# The direct rendezvous on the LGC's P20, P34 and P35 (RendezvousCrew.
	# direct()): no tweak needed ("No tweak", 171:46:16); TPI on the APS at
	# 172:29:40.0, 72.7 ft/s in 2.6 s, N81 +70.3, +5.9, -17.7; the midcourse
	# corrections 1.6 and 2.8 ft/s; docking at 173:36:25.5 (MSC-05161,
	# Tables 3-I, 3-V and 7-V).
	var lm0 := lm.dv_total
	var box := {}
	var got := RendezvousCrew.direct(self, func(name: String) -> Vector2:
		if name == "TPI":
			box["at_tpi"] = _rel(tpi_pad)
			return _lm_burn(42, 1, false)
		return _lm_burn(41, 0, true))
	assert_false(got.has("TWEAK"), "no tweak")
	assert_true(sq.timeline_done.has("no_tweak"), "Houston's word")
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
	rows.append("TPI on the APS | GET %s, %.1f ft/s in %.1f s; Endeavour %.1f nmi off, %.1f deg up, Falcon %.1f nmi below | 172:29:40, 72.7 ft/s in 2.6 s" % [
		_hms(float(got["tpi_tig"])), tpi.x, tpi.y, at_tpi.x, at_tpi.y, at_tpi.z])
	rows.append("Midcourse corrections and docking | %.1f ft/s together; docked %s, the LM's RCS %.0f ft/s since the insertion | 1.6 and 2.8 ft/s; 173:36:25" % [
		tpm, _hms(docked), lm_rcs])
	assert_eq(float(got["tpi_tig"]), tpi_pad, "TPI at the ascent PAD's TIG")
	assert_almost_eq(tpi.x, 72.7, 15.0, "TPI")
	assert_lt(tpm, 10.0, "small midcourse corrections")
	assert_almost_eq(docked, _get_s("173:36:25.5"), 1200.0, "docked")
	assert_eq(sq.phase, "lunar_orbit", "docked again")

	# GO for Pyro Arm, a revolution late, and LM JETT, 5 h 54 min after the
	# docking (179:30:01.4, MSC-05161, Table 3-III).
	Bus.set_value("ctl.cmc.mode", 0)
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_jettison"), 8.0 * 3600.0, 60.0), "Go for Pyro Arm")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for Pyro Arm")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	var jett := SimClock.get_seconds
	assert_eq(rt.dynamics.config, "csm", "Falcon's ascent stage jettisoned")
	assert_almost_eq(jett - docked, _get_s("179:30:01.4") - _get_s("173:36:25.5"), 600.0, "the jettison's time")

	# The shaping burn for the subsatellite's orbit: the PAD's N81 +17.0,
	# -0, -64.2 at 221:20:47.23 into 76.1 x 54.3 nmi (Apollo Flight Journal,
	# 220:34:55); flown 66.4 ft/s in 3.4 s into 76.0 x 54.3 (MSC-05161,
	# Table 3-V). The RTCC plans it for that orbit at that TIG from the orbit
	# Endeavour has come to, not the flight's: its ΔV differs.
	var shape := _await_pad("shaping_pad", "shape")
	assert_false(shape.is_empty(), "the shaping PAD")
	assert_eq(str(shape["name"]), "SHAPING")
	var shape_n81 := _n81(shape)
	flown = _fly(shape)
	assert_true(sq.timeline_done.has("go_shaping"), "Go for the shaping burn")
	o = _orbit(rt.dynamics.traj)
	rows.append("The shaping burn | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi | 221:20:48, N81 +17.0, −0, −64.2; 66.4 ft/s in 3.4 s; 76.0 × 54.3 nmi" % [
		_hms(float(shape["tig"])), shape_n81.x, shape_n81.y, shape_n81.z, flown.x, flown.y, o.x, o.y])
	assert_almost_eq(float(shape["tig"]), _get_s("221:20:47.23"), 1.0, "at the PAD's TIG")
	assert_lt(shape_n81.z, 0.0, "up, the burn point rising from the new pericynthion")
	assert_almost_eq(flown.x, 66.4, 40.0, "the shaping burn's ΔV")
	assert_almost_eq(o.x, 76.0, 1.5, "apolune")
	assert_almost_eq(o.y, 54.3, 1.5, "perilune")

	# TEI: the TEI-74 PAD's TIG, 223:48:45.05, N81 +2,945.2, -761.3, -171.4
	# (Apollo Flight Journal, 222:42:54); flown 3,046.8 ft/s in 140.9 s
	# (MSC-05161, Table 3-V), onto the return to 26.13 N 158.13 W with entry
	# interface at 294:58:55, the inclination 40 deg (MPAD, FM54 (71-143)).
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	var tei_n81 := _n81(tei)
	run(_get_s("223:23:20") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Set your sails for home")
	flown = _fly(tei)
	rows.append("TEI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s | 223:48:45, N81 +2,945.2, −761.3, −171.4; 3,046.8 ft/s in 140.9 s" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y])
	assert_almost_eq(float(tei["tig"]), _get_s("223:48:45.05"), 60.0, "TEI's time")
	assert_almost_eq(flown.x, 3046.8, 150.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 140.9, 20.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# Where the return comes in, as TEI left it: entry interface's GET and
	# angle (the RTCC's corridor, -6.5 deg; the flight's TEI gave -7.13 deg
	# at 294:57:45, MSC-05161, Table 3-V(c)).
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 4.0 * 86400.0, 60.0, 0.002)
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	rows.append("The return after TEI | entry interface %s, %.2f deg down | 294:57:45, 7.13 deg down; the target 6.50" % [_hms(ei.t), -ei_gamma])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_almost_eq(ei.t, _get_s("294:58:54.7"), 600.0, "entry interface's time")
	assert_between(ei_gamma, -7.5, -5.5, "in the corridor, for the midcourse corrections to trim")

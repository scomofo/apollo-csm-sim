## Slice 12a (docs/ROADMAP.md, milestone 12): Apollo 14 home from Fra Mauro,
## from the lunar_surface start (tests/scenarios/test_apollo_14.gd flies it
## there). Kitty Hawk's plane change puts its orbit over Antares; the crew
## align the platform with P57 and lift off on the ground's direct
## rendezvous, the first: the liftoff timed for TPI 38 min after the
## insertion, the tweak four minutes after it, TPI on the ascent engine at
## the TIG the ascent PAD gave, and no CSI or CDH. Then LM JETT, TEI onto
## the return, MCC-5, and the entry on P61 to P67 to the recovery area. Each
## PAD is flown as the crew flew it: the CSM's on P30 and P40 or P41, the
## LM's on P57, P12, P30 and P41, P20, P34 and P42, and P35. The flight's
## figures are the Fidelity table in README.md, each held here within set
## limits of Apollo 14's: the Apollo 14 Mission Report (MSC-04112), its
## trajectory reconstruction (MSC-04330), the Apollo Flight Journal and the
## Apollo Lunar Surface Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s.
const LEAD_S := 300.0

var sq: MissionSequencer


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
## cutoff command (s). [param in_place] burns P41 where Antares is.
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


func test_apollo_14_flies_home_from_fra_mauro_on_the_direct_rendezvous() -> void:
	build("lunar_surface", "apollo_14")
	sq = rt.sequencer
	var lgc := rt.lgc()
	var lm := rt.dynamics.lm
	assert_true(lm.landed, "Antares at Fra Mauro")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're STAY")
	var rows := PackedStringArray()

	# Kitty Hawk's plane change, over Antares at the liftoff: the LOPC-1
	# PAD's N81 -12.9, +370.7, -5.5 at 117:29:32.27 into 62.1 x 57.2 nmi
	# (Apollo Flight Journal, 116:57:51 updated); flown 370.8 ft/s (MSC-04112,
	# Table 6-V). The plane change's node nearest that time: the one before
	# it needs the same burn the other way.
	var lopc1 := _await_pad("lopc1_pad", "plane")
	assert_false(lopc1.is_empty(), "LOPC-1")
	var lopc1_n81 := _n81(lopc1)
	var flown := _fly(lopc1)
	var o := _orbit(rt.dynamics.traj)
	rows.append("The plane change (LOPC-1) | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi | 117:29:32, N81 −12.9, +370.7, −5.5; 370.8 ft/s; 62.1 × 57.2 nmi (the PAD's)" % [
		_hms(float(lopc1["tig"])), lopc1_n81.x, lopc1_n81.y, lopc1_n81.z, flown.x, flown.y, o.x, o.y])
	assert_almost_eq(float(lopc1["tig"]), _get_s("117:29:32.27"), 300.0, "LOPC-1's time")
	assert_gt(lopc1_n81.y, 300.0, "the node the flight burned at")
	assert_almost_eq(flown.x, 370.8, 25.0, "LOPC-1's ΔV")
	assert_almost_eq(o.x, 62.1, 2.0, "apolune")
	assert_almost_eq(o.y, 57.2, 2.0, "perilune")

	# The ascent PAD for the direct rendezvous at 139:56:38: liftoff at
	# 141:45:39.10, N76 5,542.9 and 31.3 ft/s, crossrange -0.3 nmi; N37,
	# TPI's TIG, 142:30:51.1 (Apollo Lunar Surface Journal, 140:36:40
	# updated); flown 141:45:40, 432.1 s on the APS into 51.7 x 8.5 nmi
	# (MSC-04112, Table 6-V). GO for liftoff: "direct rendezvous".
	var asc := _await_pad("ascent_pad", "ascent")
	assert_false(asc.is_empty(), "the ascent PAD")
	var tig := float(asc["tig"])
	var tpi_pad := float(sq.plan["tpi_tig"])
	assert_eq(lgc.rdv_tpi_tig, tpi_pad, "TPI's TIG in the LGC (N37)")
	# The crew's last P57 before the liftoff, option 4 on gravity and a star.
	run(tig - 2400.0 - SimClock.get_seconds)
	var sighted := AotCrew.surface_stars(self)
	var p57 := surface_align(4, 3, [int(sighted[0])])
	assert_lt(rad_to_deg(lgc.imu.misalignment().length()), 0.03, "the platform aligned for the ascent")
	keys("V37E12E", lgc)
	assert_eq(lgc.program, 12, "P12")
	keys("P", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(maxf(tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "direct rendezvous")
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
	rows.append("The ascent | the P57 at %s, N05 %.2f; liftoff %s, N76 %.1f and %.1f ft/s, %+.2f nmi crossrange, TPI's TIG %s; %.0f s on the APS; %.1f × %.1f nmi, Kitty Hawk %.0f nmi ahead | liftoff 141:45:40, N76 5,542.9 and 31.3 ft/s, −0.3 nmi, TPI 142:30:51; 432.1 s; 51.7 × 8.5 nmi" % [
		_hms(float(p57["get"])), p57["sad"], _hms(liftoff), float(asc["vh"]) / Units.FT, float(asc["hdot"]) / Units.FT,
		float(asc["xrng"]) / Units.NMI, _hms(tpi_pad), float(cutoff["t"]) - liftoff, o.x, o.y, at_ins.x])
	assert_almost_eq(liftoff, _get_s("141:45:40"), 300.0, "the liftoff near the flight's")
	assert_almost_eq(tpi_pad - liftoff, _get_s("142:30:51.1") - _get_s("141:45:39.10"), 30.0, "TPI 45 min after it")
	assert_almost_eq(float(asc["vh"]) / Units.FT, 5542.9, 1.0, "N76's horizontal velocity")
	assert_almost_eq(float(asc["hdot"]) / Units.FT, 31.3, 0.1, "and its climb")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.0, "under a mile of crossrange: LOPC-1 put the plane over Antares")
	assert_almost_eq(float(cutoff["t"]) - liftoff, 432.1, 25.0, "the ascent's burn")
	assert_almost_eq(o.x, 51.7, 2.0, "apolune")
	assert_almost_eq(o.y, 8.5, 1.5, "perilune")

	# The direct rendezvous on the LGC's P20, P34 and P35 (RendezvousCrew.
	# direct()): the tweak, 10.3 ft/s on the RCS at 141:56:49.4; TPI on the
	# APS at 142:30:51.1, 88.5 ft/s, N81 +62.1, +0.1, +63.1, the tweak having
	# put Antares 15 nmi below Kitty Hawk and 26.6 deg under it there; the
	# midcourse corrections 1.1 and 1.6 ft/s; docking at 143:32:50.5
	# (MSC-04112, Tables 6-V and 6-VI; MSC-04330, Appendix B).
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
	rows.append("The tweak | GET %s, %.1f ft/s on the RCS | 141:56:49, 10.3 ft/s" % [_hms(float(tweak["tig"])), tw.x])
	rows.append("TPI on the APS | GET %s, %.1f ft/s in %.1f s; Kitty Hawk %.1f nmi off, %.1f deg up, Antares %.1f nmi below | 142:30:51, 88.5 ft/s in 3.6 s; 26.6 deg, 15 nmi below" % [
		_hms(float(got["tpi_tig"])), tpi.x, tpi.y, at_tpi.x, at_tpi.y, at_tpi.z])
	rows.append("Midcourse corrections and docking | %.1f ft/s together; docked %s, the LM's RCS %.0f ft/s since the insertion | 1.1 and 1.6 ft/s; 143:32:51, some 45 ft/s" % [
		tpm, _hms(docked), lm_rcs])
	assert_almost_eq(float(tweak["tig"]), _get_s("141:56:48.1"), 300.0, "the tweak's time")
	assert_almost_eq(tw.x, 10.3, 5.0, "the tweak")
	assert_eq(float(got["tpi_tig"]), tpi_pad, "TPI at the ascent PAD's TIG")
	assert_almost_eq(at_tpi.y, 26.6, 1.0, "26.6 deg up at TPI")
	assert_almost_eq(at_tpi.z, 15.0, 2.0, "15 nmi below")
	assert_almost_eq(tpi.x, 88.5, 15.0, "TPI")
	assert_lt(tpm, 10.0, "small midcourse corrections")
	assert_almost_eq(docked, _get_s("143:32:50.5"), 1200.0, "docked")
	assert_eq(sq.phase, "lunar_orbit", "docked again")

	# GO for Pyro Arm, LM JETT (145:44:58); TEI: the TEI-34 PAD's TIG,
	# 148:36:01.40, N81 +3,013.3, +1,667.4, -340.3; flown 3,460.6 ft/s in
	# 149.2 s (MSC-04112, Table 6-V; Apollo Flight Journal, 147:39:39
	# updated).
	Bus.set_value("ctl.cmc.mode", 0)
	run(docked + 7037.0 + 10.0 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for Pyro Arm")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	assert_eq(rt.dynamics.config, "csm", "Antares's ascent stage jettisoned")
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	var tei_n81 := _n81(tei)
	flown = _fly(tei)
	rows.append("TEI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s | 148:36:01, N81 +3,013.3, +1,667.4, −340.3; 3,460.6 ft/s in 149.2 s" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y])
	assert_almost_eq(float(tei["tig"]), _get_s("148:36:01.40"), 60.0, "TEI's time")
	assert_almost_eq(flown.x, 3460.6, 150.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 149.2, 20.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# MCC-5 on the RCS, the PAD's 0.7 ft/s at 165:34:55.64, flown 0.5
	# (MSC-04112, Table 6-V; MSC-04330, Table VIII); the others not needed.
	var m5 := _await_pad("mcc5_pad", "mcc")
	var mcc5 := float(m5.get("dv", 0.0)) / Units.FT
	_fly(m5)
	rows.append("MCC-5 | %.1f ft/s | 0.5 ft/s (the PAD's 0.7)" % mcc5)
	assert_lt(mcc5, 8.0, "MCC-5, a trim")

	# The entry PAD, 211:05:31: 27.02 S 172.65 W; then P52 before the
	# entry, and GO for Pyro Arm.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(-27.02, -172.65), "N61 uplinked")
	run(_get_s("214:30:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_pyro_arm"), 3.0 * 3600.0, 60.0), "home")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You are Go for Pyro Arm")

	# Entry interface: 215:47:45.3, 36,170.2 ft/s, 6.37 deg down, at 36.36 S
	# 165.80 E (MSC-04112, Table 6-III), an hour after the GO for Pyro Arm.
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 7200.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	var to_go := Bodies.surface_angle(geo, Vector2(-27.02, -172.65)) * Bodies.R_EARTH / Units.NMI
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f S %.2f E, %.0f nmi from the target | 215:47:45, 36,170 ft/s, 6.37 deg down, 36.36 S 165.80 E, 1,229 nmi" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, -geo.x, geo.y, to_go])
	assert_almost_eq(ei.t, _get_s("215:47:45.3"), 120.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36170.0, 30.0, "its speed")
	assert_almost_eq(ei_gamma, -6.37, 0.5, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(-36.36, 165.80)) * Bodies.R_EARTH / Units.NMI, 150.0, "where")

	# The entry on P61 to P67 to 27.02 S 172.65 W, 6.2 g at the peak on the
	# PAD; down at 216:01:58.1, 27.01 S 172.65 W, 0.62 nmi from the target
	# (MSC-04112, sections 6 and 11; MSC-04330, p. 11).
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 6.2 g on the PAD" % [str(fe["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.2f S %.2f W, %.1f nmi from the target | 216:01:58, 27.01 S 172.65 W, 0.62 nmi from it" % [
		_hms(land), -at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 14.")
	assert_almost_eq(rt.dynamics.max_g, 6.2, 1.5, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(land - ei.t, _get_s("216:01:58.1") - _get_s("215:47:45.3"), 90.0, "the entry's time")
	assert_almost_eq(land, _get_s("216:01:58.1"), 300.0, "splashdown's time")

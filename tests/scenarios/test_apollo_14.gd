## Slice 12a (docs/ROADMAP.md, milestone 12): Apollo 14 flies from its data
## alone (data/missions/apollo_14/mission.json), from its parking orbit to
## the landing at Fra Mauro; tests/scenarios/test_apollo_14_return.gd flies
## it home from the surface. The S-IVB flies TLI onto the free return,
## MCC-2 takes the stack off it onto the hybrid trajectory, and LOI turns
## the orbit into the plane over the site. Kitty Hawk, the first CSM to do
## so, flies DOI with Antares docked, down to 9 nmi at the low point, and
## after the undocking climbs back to 60 nmi (CIRC). Antares's crew realign
## its platform with P52 on the stars they used, and it flies powered
## descent from the descent orbit Kitty Hawk left it on: the ground's
## landing site update (noun 69) takes out what its state vector had wrong
## along the track, and the commander, the automatic guidance taking him
## some 2,000 ft short, flies the rest by hand in P66 to the spot Antares
## came down on. Each PAD Mission Control's timeline brings is flown as the
## crew flew it: the CSM's on P30 and P40 or P41, the LM's on P63 to P66.
## The flight's figures are the Fidelity table in README.md, each held here
## within set limits of Apollo 14's: the Apollo 14 Mission Report
## (MSC-04112), the AS-509 flight evaluation report (MPR-SAT-FE-71-1), the
## Apollo Flight Journal and the Apollo Lunar Surface Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s: time
## enough for the auto maneuver's 1°/s to turn to any attitude, and less
## than the checklists' quarter of an hour, for the suite's time.
const LEAD_S := 300.0
## The commander holds Antares's height in P66 until the spot is this near,
## m: he flew some 2,000 ft there by hand, about 50 s of it level
## (MSC-04330, Appendix A).
const LEVEL_BEYOND_M := 250.0

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


## [param tr]'s orbit's inclination to the lunar equator, degrees.
func _inclination(tr: Trajectory) -> float:
	var h := tr.pos().cross(tr.vel()).normalized()
	return rad_to_deg(acos(clampf(-h.dot(Bodies.moon_pole(tr.t)), -1.0, 1.0)))


## The ground range between two Moon-fixed points, m.
static func _apart(a: Vector3, b: Vector3) -> float:
	return a.angle_to(b) * Bodies.R_MOON


## Where the LGC is taking the LM: its landing site less what its state
## vector has wrong, Moon-fixed.
func _aim(lgc: Lgc) -> Vector3:
	var mf := Bodies.moon_fixed(SimClock.get_seconds)
	return mf.transposed() * (mf * lgc.landing_site - (lgc.nav.pos() - rt.dynamics.lm.traj.pos()))


func _n81(pad: Dictionary) -> Vector3:
	return pad["dv_lvlh"] / Units.FT


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_14_flies_its_data_and_lands_at_fra_mauro() -> void:
	build("parking_orbit", "apollo_14")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_true(rt.dynamics.has_lm(), "Antares in the adapter")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:28:32.4 for 350.8 s, 10,366.5
	# ft/s gained (MSC-04112, Table 6-V(a)), C3 -1,678,092 m2/s2 at TLI, 10 s
	# on (MPR-SAT-FE-71-1, Table 4-5); the free return past the Moon 1,979
	# nmi up at 82:15:19 (MSC-04112, Table 6-V). What the J-2 gave: the
	# rocket equation on the propellant it burned.
	var tli: Dictionary = sq.tli_pad
	run(float(tli["tig"]) - 30.0 - SimClock.get_seconds)
	var m0 := float(Bus.get_value("dyn.mass_kg"))
	var p0 := float(Bus.get_value("sivb.prop_kg"))
	assert_true(run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 3600.0, 60.0), "TLI")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	var used := p0 - float(Bus.get_value("sivb.prop_kg"))
	var j2 := float(SpacecraftData.section("sivb")["isp_s"]) * Units.G0 * log(m0 / (m0 - used)) / Units.FT
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	var p := _pericynthion()
	rows.append("TLI | GET %s, %.0f ft/s in %.1f s, C3 %.0f m²/s²; the pericynthion after it %.1f nmi at %s | 2:28:32, 10,366.5 ft/s in 350.8 s, C3 −1,678,092 m²/s²; 1,979 nmi at 82:15:19" % [
		_hms(ign), j2, cut - ign, c3, p.x, _hms(p.y)])
	assert_almost_eq(ign, _get_s("2:28:32.4"), 30.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 350.8, 5.0, "its burn")
	assert_almost_eq(j2, 10366.5, 100.0, "what the J-2 gave")
	assert_almost_eq(c3, -1678092.0, 20000.0, "C3")
	assert_almost_eq(p.x, 1979.0, 10.0, "the free return's pericynthion")
	assert_almost_eq(p.y, _get_s("82:15:19"), 60.0, "and when")

	# CSM/LV SEP, transposition, docking and extraction after the scripted
	# delay [simplified: the six contacts before Kitty Hawk's latches caught
	# are slice 12a's fourth part]. MCC-2 on the SPS takes the stack off the
	# free return: the PAD's 71.4 ft/s at 30:36:07.01, N81 -25.9, +4.4, +66.4
	# (Apollo Flight Journal, 29:12:22); MCC-4, the PAD's 3.8 ft/s at
	# 76:58:11.08 (ibid., 76:05:52 updated), after which the pericynthion
	# was 60.7 nmi up at 82:00:33 (MSC-04112, p. 6-1 and Table 6-V).
	var mcc2 := _await_pad("mcc2_pad", "mcc")
	assert_eq(rt.dynamics.config, "csm_lm", "Antares docked since the transposition")
	assert_false(mcc2.is_empty(), "MCC-2")
	var mcc2_n81 := _n81(mcc2)
	_fly(mcc2)
	p = _pericynthion()
	rows.append("MCC-2, off the free return | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 71.4 ft/s at 30:36:07, N81 −25.9, +4.4, +66.4" % [
		float(mcc2["dv"]) / Units.FT, _hms(float(mcc2["tig"])), mcc2_n81.x, mcc2_n81.y, mcc2_n81.z, p.x, _hms(p.y)])
	assert_almost_eq(float(mcc2["dv"]) / Units.FT, 71.4, 8.0, "MCC-2")
	assert_almost_eq(p.x, 60.7, 7.0, "the pericynthion after it, off by MSFN's tracking error")
	assert_almost_eq(p.y, _get_s("82:00:33"), 60.0, "and when")
	var mcc4 := _await_pad("mcc4_pad", "mcc")
	_fly(mcc4)
	p = _pericynthion()
	rows.append("MCC-4 | %.1f ft/s; then %.1f nmi at %s | 3.8 ft/s at 76:58:11; then 60.7 nmi at 82:00:33" % [
		float(mcc4.get("dv", 0.0)) / Units.FT, p.x, _hms(p.y)])
	assert_lt(float(mcc4.get("dv", 0.0)) / Units.FT, 6.0, "MCC-4, a trim")
	assert_almost_eq(p.x, 60.7, 3.0, "the pericynthion before LOI")

	# LOI behind the Moon: the final PAD's N81 -2,804.9, -1,103.5, -227.0 at
	# 81:56:39.80, into 169.3 x 58.1 nmi (Apollo Flight Journal, 81:11:09
	# updated); flown 3,022.4 ft/s in 370.8 s into 169.0 x 58.1 nmi
	# (MSC-04112, Table 6-V). The RTCC centres the burn on the pericynthion
	# the midcourse corrections put in the plane over the site, 40 s after
	# the flight's TIG here: the burn runs longer.
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI")
	var loi_n81 := _n81(loi)
	run(_get_s("81:32:40") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "GO for LOI")
	var flown := _fly(loi)
	var o := _orbit(rt.dynamics.traj)
	var incl := _inclination(rt.dynamics.traj)
	rows.append("LOI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; %.1f × %.1f nmi, %.2f deg to the lunar equator | 81:56:40, N81 −2,804.9, −1,103.5, −227.0; 3,022.4 ft/s in 370.8 s; 169.0 × 58.1 nmi" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(float(loi["tig"]), _get_s("81:56:39.80"), 90.0, "LOI's time")
	assert_almost_eq(flown.x, 3022.4, 100.0, "LOI's ΔV")
	assert_lt(loi_n81.y, -900.0, "a plane change into the orbit over the site")
	assert_almost_eq(flown.y, 370.8, 30.0, "its burn")
	assert_almost_eq(o.x, 169.0, 4.0, "apolune")
	assert_almost_eq(o.y, 58.1, 3.0, "perilune")
	assert_almost_eq(incl, 14.4, 1.2, "the orbit over Fra Mauro")

	# DOI, the CSM's with Antares docked, the first: the PAD's N81 -206.4,
	# 0, -3.6 at 86:10:52.07 (Apollo Flight Journal, 85:32:20 updated),
	# flown in 20.6 s into 58.8 by 10.4 nmi as the crew read it (ibid.,
	# 86:51:18 updated). The RTCC sizes it to bring the orbit over the PDI
	# point on the landing pass at PDI's height (Rtcc.plan_doi_docked()),
	# flying it through the Moon's field all day: its pericynthion comes
	# round here minutes after the flight's.
	var doi := _await_pad("doi_pad", "doi")
	assert_false(doi.is_empty(), "DOI, docked")
	var doi_n81 := _n81(doi)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "uplinking your state vector and DOI")
	flown = _fly(doi)
	o = _orbit(rt.dynamics.traj)
	rows.append("DOI, Kitty Hawk with Antares docked | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi; PDI planned for %s | 86:10:52, N81 −206.4, 0, −3.6; 20.6 s; 58.8 × 10.4 nmi (the PAD's 58.8 × 9.1); PDI 108:02:25" % [
		_hms(float(doi["tig"])), doi_n81.x, doi_n81.y, doi_n81.z, flown.x, flown.y, o.x, o.y, _hms(float(doi["hp_get"]))])
	assert_eq(rt.dynamics.config, "csm_lm", "docked through DOI")
	assert_almost_eq(float(doi["tig"]), _get_s("86:10:52.07"), 240.0, "DOI's time")
	assert_almost_eq(flown.x, 206.4, 5.0, "DOI's ΔV")
	assert_almost_eq(flown.y, 20.6, 4.0, "its burn")
	assert_almost_eq(o.x, 58.8, 2.0, "apolune")
	assert_almost_eq(o.y, 9.1, 1.5, "perilune")
	assert_almost_eq(float(doi["hp_get"]), _get_s("108:02:24.61"), 180.0, "PDI planned on the landing pass")

	# The separation PAD, docked, for after the undocking at 103:47: 0.8
	# ft/s radially down at 103:47:28.10 on the SM RCS (MSC-04112, Table
	# 6-V).
	var sep := _await_pad("sep_pad", "sep")
	assert_true(bool(sep.get("uplinked", false)), "the separation PAD in the CMC")
	run(_get_s("103:47:00") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you have a Go for undock")
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "undocked")
	assert_eq(sq.phase, "lunar_descent", "Antares on the descent orbit")
	Bus.set_value("ctl.lm.mode", 0)
	var sepf := fly_pad(0, LEAD_S) / Units.FT
	rows.append("The CSM's separation | %.1f ft/s radially down | 0.8 ft/s" % sepf)
	assert_almost_eq(sepf, 0.8, 0.3, "the separation")

	# Kitty Hawk's circularization: the CIRC PAD's N81 +70.2, 0, -29.6 at
	# 105:11:45.21 into 63.3 x 55.5 nmi (Apollo Flight Journal, 105:14:38
	# updated); flown into 63.9 x 56.0 (ibid., 105:51:48 updated).
	var circ := _await_pad("circ_pad", "circ")
	assert_false(circ.is_empty(), "CIRC")
	assert_eq(str(circ["name"]), "CIRC", "the CSM's own")
	var circ_n81 := _n81(circ)

	# Antares's first P52, torqued at 104:46:37 on stars 22 (Regulus) and 16
	# (Procyon) through the left-front detent: N05 0.04°, N93 +0.097, +0.062
	# and -0.013° (MSC-04112, Table 8-I; Apollo Flight Journal, 106:17:22
	# updated). The platform stood so at undocking, less the drift since
	# (mission.json "lgc": first_p52), and the descent flies on the platform
	# it leaves.
	run(_get_s("104:44:00") - SimClock.get_seconds)
	var p52 := lm_realign([22, 16])
	var n93: Vector3 = p52["torque"]
	rows.append("Antares's first P52 | GET %s on stars 22 and 16: N05 %.3f°, N93 %+.3f, %+.3f and %+.3f° | 104:46:37: 0.04°; +0.097, +0.062 and −0.013°" % [
		_hms(float(p52["get"])), p52["sad"], n93.x, n93.y, n93.z])
	assert_almost_eq(n93, Vector3(0.097, 0.062, -0.013), Vector3.ONE * 0.015, "N93 as flown")
	assert_lt(float(p52["sad"]), 0.05, "N05 within the flown")
	assert_lt(rad_to_deg(rt.lgc().imu.misalignment().length()), 0.01, "the platform on the REFSMMAT")
	flown = _fly(circ)
	o = _orbit(rt.dynamics.traj)
	rows.append("CIRC | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s; Kitty Hawk in %.1f × %.1f nmi | 105:11:45, N81 +70.2, 0, −29.6 (76.2 ft/s); 63.9 × 56.0 nmi" % [
		_hms(float(circ["tig"])), circ_n81.x, circ_n81.y, circ_n81.z, flown.x, o.x, o.y])
	assert_almost_eq(float(circ["tig"]), _get_s("105:11:45.21"), 1.0, "at the PAD's TIG")
	assert_almost_eq(flown.x, 76.2, 8.0, "CIRC's ΔV")
	assert_almost_eq(o.x, 63.9, 2.0, "Kitty Hawk's apolune")
	assert_almost_eq(o.y, 56.0, 2.0, "and perilune")

	# Powered descent, from the PDI PAD's state vector, 2,800 ft off along
	# the track: the PAD 2 h 9 min before PDI, 108:02:24.61 (Apollo Lunar
	# Surface Journal, 105:53:23); Antares 47,355 ft up at ignition (the
	# PGNCS's). The ground's noun 69, plus 2,800 ft (108:04:18), keyed in
	# (V21N69), and V57 when the landing radar's altitude comes good
	# [simplified: Antares's radar, which came good only after its breaker
	# was cycled, is slice 12a's third part]. The crew fly Houston's
	# workaround for the ABORT switch at the flown times (AbortSwitchCrew):
	# the throttle-up by hand at 27.3 s, the steering from 44.5 s, at 47,503
	# ft, P70 and P71 locked out at 66.5 s, at 46,996 ft, and MODREG 63 at
	# 80.5 s, at 46,459 ft (71-FM22-36, Table A-I).
	var lgc := rt.lgc()
	var lm := rt.dynamics.lm
	assert_true(run_until(func() -> bool: return sq.pads.has("pdi"), 3600.0, 10.0), "the PDI PAD")
	var t_pad := sq.event_get("pad_pdi")
	run(float(sq.plan["pdi_tig"]) - 600.0 - SimClock.get_seconds)
	keys("V37E63E", lgc)
	assert_eq(lgc.program, 63, "P63")
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	AbortSwitchCrew.before_pdi(self)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for Fra Mauro")
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	var t_pdi := lgc.pdi_tig
	var site := sq.landing_site()
	var spot := sq._touchdown_site()
	var h_pdi := lm.traj.radius() - site.length()
	var seen := {"programs": []}
	var landed := run_until(func() -> bool:
		var since := SimClock.get_seconds - t_pdi
		AbortSwitchCrew.after_ignition(self, since, seen)
		for ev: Array in AbortSwitchCrew.FLOWN.slice(1, 4):
			if not seen.has(ev[1]) and since >= float(ev[0]):
				seen[ev[1]] = lm.traj.radius() - site.length()
		permit_lr_updates(lgc, seen)
		if sq.pads.has("n69") and not seen.has("n69"):
			var ft := float(sq.pads["n69"]["dz_ft"])
			seen["n69"] = ft
			seen["n69_after"] = SimClock.get_seconds - t_pdi
			keys("V21N69E%s%05dE" % ["+" if ft >= 0.0 else "-", int(absf(ft))], lgc)
		if not lgc.program in seen["programs"]:
			seen["programs"].append(lgc.program)
		return lgc.program == 64, 900.0, 1.0, false)
	assert_true(landed, "P64")
	var h_keyed: Array = AbortSwitchCrew.FLOWN.slice(1, 4).map(func(ev: Array) -> float: return float(seen[ev[1]]) / Units.FT)
	assert_eq([lgc.erasable.modreg, lgc.erasable.zoomflag, lgc.erasable.letabort], [64, true, false],
		"the workaround's end: P64 in MODREG, the guidance steering, P70 and P71 locked out")
	# P64 at 108:11:09 near 8,190 ft, the automatic guidance aiming 1,350 ft
	# short of the target after the noun 69; one LPD click, 350 ft south, at
	# 2,700 ft; the commander took over in P66 at 360 ft (108:13:09) about
	# 2,200 ft short and flew 2,000 ft downrange in 2 min, and Antares came
	# down at 108:15:09.3 with 794 lb of the DPS's propellant left
	# (MSC-04112, Table 8-V; MSC-04330, Appendix A; the Apollo Lunar Surface
	# Journal) [simplified: here no LPD click; the commander flies from the
	# LGC's aim].
	var t_p64 := SimClock.get_seconds
	var h_p64 := lgc._h
	var auto_aim := _aim(lgc)
	assert_true(run_until(func() -> bool: return lgc._h < 360.0 * Units.FT, 300.0, 0.2, false), "down to 360 ft")
	Bus.set_value("ctl.lm.mode", 1)
	rod_click(-1)
	assert_eq(lgc.program, 66, "P66")
	var t_p66 := SimClock.get_seconds
	var h_p66 := lgc._h
	var short := _apart(Bodies.moon_fixed(t_p66).transposed() * lm.traj.pos(), spot)
	while not lm.landed and SimClock.get_seconds - t_p66 < 400.0:
		fly_by_hand(lgc, spot, LEVEL_BEYOND_M)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_true(lm.landed, "touchdown")
	var td: Dictionary = lm.touchdown
	var t_land := float(td["get_s"])
	var dps_left := float(Bus.get_value("lm.dps.prop_kg"))
	rows.append("PDI | the PAD at %s; GET %s, %.0f ft over the site | the PAD at 105:53:23; 108:02:25, 47,355 ft (the PGNCS's)" % [
		_hms(t_pad), _hms(t_pdi), h_pdi / Units.FT])
	rows.append("The ABORT switch's workaround | MODREG 71 before PDI; the throttle-up by hand at +27.3 s; ZOOMFLAG at +44.5 s, %.0f ft; LETABORT reset at +66.5 s, %.0f ft; MODREG 63 at +80.5 s, %.0f ft | 47,503, 46,996 and 46,459 ft" % h_keyed)
	rows.append("Noun 69 and the landing radar | %+.0f ft %.0f s after PDI; ΔH %.0f ft at %.0f ft | +2,800 ft (108:04:18, 112 s after PDI)" % [
		float(seen["n69"]), float(seen["n69_after"]), float(seen["dh0"]) / Units.FT, float(seen["dh0_agl"]) / Units.FT])
	rows.append("P64 | GET %s at %.0f ft, aiming %.0f ft short of where Antares came down | 108:11:09 at 8,190 ft, aiming 1,350 ft short of the target" % [
		_hms(t_p64), h_p64 / Units.FT, _apart(auto_aim, spot) / Units.FT])
	rows.append("The landing | P66 at %s at %.0f ft, %.0f ft short; touchdown %s, %.0f ft from where Antares came down; %.0f lb of the DPS's propellant left | P66 at 108:13:09 at 360 ft, about 2,200 ft short; 108:15:09; 794 lb" % [
		_hms(t_p66), h_p66 / Units.FT, short / Units.FT, _hms(t_land), _apart(lm.landed_pos, spot) / Units.FT, dps_left / Units.LBM])
	assert_almost_eq(t_pad, _get_s("105:53:23.1"), 180.0, "the PDI PAD, two hours ahead")
	assert_almost_eq(t_pdi, _get_s("108:02:24.61"), 180.0, "PDI's time")
	assert_almost_eq(h_pdi / Units.FT, 47355.0, 3000.0, "PDI's height")
	for i in 3:
		assert_almost_eq(float(h_keyed[i]), [47503.0, 46996.0, 46459.0][i], 3000.0,
			"%s keyed at the flown height, as PDI's" % ["ZOOMFLAG", "LETABORT", "MODREG 63"][i])
	assert_almost_eq(float(seen["n69"]), 2800.0, 800.0, "noun 69, the landing site's move downrange")
	assert_almost_eq(float(seen["n69_after"]), 112.0, 2.0, "after throttle-up")
	assert_eq(seen["programs"], [63, 64], "braking, then the approach")
	assert_almost_eq(t_p64, _get_s("108:11:09"), 180.0, "P64's time")
	assert_almost_eq(h_p64 / Units.FT, 8190.0, 800.0, "P64's height")
	assert_almost_eq(_apart(auto_aim, spot) / Units.FT, 1350.0, 600.0, "the automatic guidance aiming short, as Antares's did")
	assert_almost_eq(h_p66 / Units.FT, 360.0, 20.0, "P66 at 360 ft")
	assert_between(short / Units.FT, 1000.0, 2600.0, "some 2,000 ft to fly by hand")
	assert_almost_eq(t_land, _get_s("108:15:09.3"), 180.0, "the landing's time")
	assert_lt(_apart(lm.landed_pos, spot), 30.0, "where Antares came down")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_between(dps_left / Units.LBM, 450.0, 1100.0, "the DPS's propellant as flown, give or take")
	run(2.0, false)
	assert_eq(sq.phase, "lunar_surface", "on the surface")
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	for row in rows:
		gut.p("Fidelity: " + row)

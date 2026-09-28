## Slice 7c (docs/ROADMAP.md, milestone 7): Apollo 12 flies from its data
## alone (data/missions/apollo_12/mission.json), from its parking orbit to
## the splashdown, and Intrepid lands beside Surveyor III. The S-IVB flies
## TLI onto the free return, MCC-2 takes the stack off it onto the hybrid
## trajectory, and LOI-1 turns the orbit into the plane over the site, 14.6
## deg to the lunar equator. Intrepid undocks and flies DOI and powered
## descent: the ground's landing site update (noun 69) takes out what its
## state vector had wrong along the track, the descent guidance steers out
## the miles the orbit's plane had drifted north of the site, and the
## commander redesignates onto the Surveyor crater in P64 and flies P66 to
## the spot Intrepid came down on, 535 ft from the Surveyor. Yankee
## Clipper's first plane change puts its orbit back over Intrepid for the
## liftoff a day and a half later; P12 flies the ascent, the coelliptic
## sequence the rendezvous, and the second plane change, TEI, the
## transearth corrections and the entry on P61 to P67 follow. Each PAD
## Mission Control's timeline brings is flown as the crew flew it: the
## CSM's on P30 and P40 or P41, the LM's on P30 and P40, P63 to P66, P12
## and P32 to P35. The flight's figures are the Fidelity table in README.md,
## each held here within set limits of Apollo 12's: the Apollo 12 Mission
## Report (MSC-01855), the AS-507 flight evaluation report
## (MPR-SAT-FE-70-1), the Apollo Flight Journal and the Apollo Lunar
## Surface Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s: time
## enough for the auto maneuver's 1°/s to turn to any attitude, and less
## than the checklists' quarter of an hour, for the suite's time.
const LEAD_S := 300.0
## Intrepid within this of Surveyor III, m: it came down 535 ft (163 m)
## from it, outside the 500 ft the planners had hoped for.
const SURVEYOR_LIMIT_M := 250.0

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
## sensed (ft/s) and y the engine's time from the ignition command to the
## cutoff command (s, to a second).
func _lm_burn(prog: int, arm: int, from_p30: bool = true) -> Vector2:
	var lgc := rt.lgc()
	var box := {"off": -1.0, "ign": -1.0}
	var dv := fly_lm_pad(prog, arm, func() -> void:
		if lgc.ignition_get > 0.0:
			box["ign"] = lgc.ignition_get
		if lgc.step_name in ["tailoff", "post"] and box["off"] < 0.0:
			box["off"] = SimClock.get_seconds, from_p30, LEAD_S)
	return Vector2(dv / Units.FT, float(box["off"]) - float(box["ign"]))


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


## When [param tr] (not changed) reaches entry interface.
static func _ei_get(tr: Trajectory) -> float:
	var ei := tr.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.primary == "earth" and t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 4.0 * 86400.0, 60.0, 0.002)
	return ei.t


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_12_flies_its_data_and_lands_beside_surveyor_iii() -> void:
	build("parking_orbit", "apollo_12")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_true(rt.dynamics.has_lm(), "Intrepid in the adapter")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:47:22.7 for 341.3 s, 10,515.0
	# ft/s gained (MSC-01855, Table 5-IV), C3 -1,834,425 m2/s2 at TLI, 10 s
	# on (MPR-SAT-FE-70-1, Table 4-6); the free return past the Moon 280.2
	# nmi up at 83:44:04.4 (MSC-01855, Table 5-IV). What the J-2 gave: the
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
	rows.append("TLI | GET %s, %.0f ft/s in %.1f s, C3 %.0f m²/s²; the pericynthion after it %.1f nmi at %s | 2:47:23, 10,515 ft/s in 341.3 s, C3 −1,834,425 m²/s²; 280.2 nmi at 83:44:04" % [
		_hms(ign), j2, cut - ign, c3, p.x, _hms(p.y)])
	assert_almost_eq(ign, _get_s("2:47:22.7"), 30.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 341.3, 5.0, "its burn")
	assert_almost_eq(j2, 10515.0, 100.0, "what the J-2 gave")
	assert_almost_eq(c3, -1834425.0, 20000.0, "C3")
	assert_almost_eq(p.x, 280.2, 10.0, "the free return's pericynthion")
	assert_almost_eq(p.y, _get_s("83:44:04.4"), 60.0, "and when")

	# CSM/LV SEP, transposition, docking and extraction after the scripted
	# delay (the S-IVB flew the evasive maneuver, not the CSM). MCC-2 on the
	# SPS takes the stack off the free return: the PAD's 61.7 ft/s at
	# 30:52:43.68, N81 -60.1, -12.6, +5.6 (Apollo Flight Journal, 29:01:46),
	# flown 61.8; 65.1 nmi at 83:28:38.8 after it, 0.71 N 161.97 E (MSC-01855,
	# Table 5-IV). MCC-4, 5 h before LOI, wasn't needed (the flight plan's
	# Table 1-5).
	var mcc2 := _await_pad("mcc2_pad", "mcc")
	assert_eq(rt.dynamics.config, "csm_lm", "Intrepid docked since the transposition")
	assert_false(mcc2.is_empty(), "MCC-2")
	var mcc2_n81: Vector3 = mcc2["dv_lvlh"] / Units.FT
	_fly(mcc2)
	p = _pericynthion()
	rows.append("MCC-2, off the free return | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 61.7 ft/s at 30:52:44, N81 −60.1, −12.6, +5.6 (flown 61.8); then 65.1 nmi at 83:28:39" % [
		float(mcc2["dv"]) / Units.FT, _hms(float(mcc2["tig"])), mcc2_n81.x, mcc2_n81.y, mcc2_n81.z, p.x, _hms(p.y)])
	assert_almost_eq(float(mcc2["dv"]) / Units.FT, 61.7, 8.0, "MCC-2")
	assert_almost_eq(p.x, 65.1, 7.0, "the pericynthion after it, off by MSFN's tracking error")
	assert_almost_eq(p.y, _get_s("83:28:38.8"), 60.0, "and when")
	var mcc4 := _await_pad("mcc4_pad", "mcc")
	_fly(mcc4)
	p = _pericynthion()
	rows.append("MCC-4 | %.1f ft/s; then %.1f nmi at %s | not needed" % [float(mcc4.get("dv", 0.0)) / Units.FT, p.x, _hms(p.y)])
	assert_lt(float(mcc4.get("dv", 0.0)) / Units.FT, 6.0, "MCC-4, a trim")
	assert_almost_eq(p.x, 65.1, 3.0, "the pericynthion before LOI")

	# LOI-1 behind the Moon at the PAD's TIG, 83:25:18.51: N81 -2,821.3,
	# +603.6, +112.4, turning the orbit into the plane over the site (Apollo
	# Flight Journal, 80:50:55); flown 2,889.5 ft/s in 352.3 s into 168.8 x
	# 62.6 nmi (MSC-01855, Table 5-VI), 14.6 deg to the lunar equator. The
	# free return TLI leaves here passes 4 deg north of the flight's, and the
	# approach the MCCs leave comes in 1.4 deg steeper: LOI-1 turns it more,
	# and the cutoff ends farther north, which tilts the orbit a degree less
	# (README, Simplifications).
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI-1")
	var loi_n81: Vector3 = loi["dv_lvlh"] / Units.FT
	run(_get_s("83:03:05") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Go for LOI")
	var flown := _fly(loi)
	var o := _orbit(rt.dynamics.traj)
	var incl := _inclination(rt.dynamics.traj)
	rows.append("LOI-1 | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; %.1f × %.1f nmi, %.2f deg to the lunar equator | 83:25:19, N81 −2,821.3, +603.6, +112.4; 2,889.5 ft/s in 352.3 s; 168.8 × 62.6 nmi, 14.6 deg" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(float(loi["tig"]), _get_s("83:25:18.51"), 1.0, "at the PAD's TIG")
	assert_almost_eq(flown.x, 2889.5, 100.0, "LOI-1's ΔV")
	assert_gt(loi_n81.y, 300.0, "a plane change into the orbit over the site")
	assert_almost_eq(flown.y, 352.3, 30.0, "its burn")
	assert_almost_eq(o.x, 168.8, 4.0, "apolune")
	assert_almost_eq(o.y, 62.6, 5.0, "perilune")
	assert_almost_eq(incl, 14.6, 1.2, "Apollo 12's orbit")

	# LOI-2 two revolutions on: the PAD's 165.5 ft/s at 87:48:47.39, N81
	# -139.2, +0.1, -89.5 (Apollo Flight Journal, 86:12:07); flown 165.2
	# ft/s into 66.1 x 54.3 nmi (MSC-01855, Table 5-VI), the burn point on
	# its way up from the new perilune. The LOI-1 orbit's perilune 2.7 nmi
	# lower here, LOI-2 takes more out of the climb.
	var loi2 := _await_pad("loi2_pad", "circ")
	var loi2_n81: Vector3 = loi2["dv_lvlh"] / Units.FT
	flown = _fly(loi2)
	o = _orbit(rt.dynamics.traj)
	var t_loi2 := float(burn_log["before"].t)
	rows.append("LOI-2 | GET %s, N81 %+.1f, %+.1f, %+.1f, %.1f ft/s; %.1f × %.1f nmi | 87:48:48, N81 −139.2, +0.1, −89.5, 165.2 ft/s; 66.1 × 54.3 nmi" % [
		_hms(t_loi2), loi2_n81.x, loi2_n81.y, loi2_n81.z, flown.x, o.x, o.y])
	assert_almost_eq(t_loi2, _get_s("87:48:48.1"), 300.0, "LOI-2 at the perilune")
	assert_almost_eq(flown.x, 165.2, 35.0, "LOI-2's ΔV")
	assert_almost_eq(o.x, 66.1, 2.0, "apolune")
	assert_almost_eq(o.y, 54.3, 2.0, "perilune")

	# The CSM's separation PAD, docked, for after the undocking at
	# 107:54:02: 2.5 ft/s radially down at 108:24:42 on the SM RCS (the
	# flight plan, Table 1-5), flown 2.4 ft/s into 63.5 x 56.3 nmi
	# (MSC-01855, Table 5-VI).
	var sep := _await_pad("sep_pad", "sep")
	assert_true(bool(sep.get("uplinked", false)), "the separation PAD in the CMC")
	run(_get_s("107:54:02") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Go for undocking")
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "undocked")
	Bus.set_value("ctl.lm.mode", 0)
	var sepf := fly_pad(0, LEAD_S) / Units.FT
	o = _orbit(rt.dynamics.traj)
	rows.append("The CSM's separation | %.1f ft/s radially down; Yankee Clipper in %.1f × %.1f nmi | 2.4 ft/s (PAD 2.5); 63.5 × 56.3 nmi" % [sepf, o.x, o.y])
	assert_almost_eq(sepf, 2.5, 0.3, "the separation")
	assert_almost_eq(o.x, 63.5, 2.0, "Yankee Clipper's apolune")
	assert_almost_eq(o.y, 56.3, 2.0, "and perilune")

	# DOI on the DPS, 15 s at 10 % and then 40 %: the PAD's 72.4 ft/s at
	# 109:23:39.41 (Apollo Lunar Surface Journal, 108:00:32); flown 72.4
	# ft/s in 29.0 s into 60.6 x 8.1 nmi (MSC-01855, Table 5-VI).
	var doi: Dictionary = sq.pads.get("doi", {})
	assert_false(doi.is_empty(), "the DOI PAD after undocking")
	var lm := rt.dynamics.lm
	var dps := _lm_burn(40, 2)
	o = _orbit(lm.traj)
	rows.append("DOI | GET %s, %.1f ft/s in %.0f s; %.1f × %.1f nmi | 109:23:40, 72.4 ft/s in 29.0 s; 60.6 × 8.1 nmi" % [
		_hms(float(doi["tig"])), dps.x, dps.y, o.x, o.y])
	assert_eq(sq.phase, "lunar_descent")
	assert_almost_eq(float(doi["tig"]), _get_s("109:23:39.41"), 240.0, "DOI's time")
	assert_almost_eq(dps.x, 72.4, 4.0, "DOI's ΔV")
	assert_almost_eq(dps.y, 29.0, 3.0, "its burn")
	assert_almost_eq(o.x, 60.6, 2.0, "Intrepid's apolune")
	assert_almost_eq(o.y, 8.1, 1.5, "and perilune")

	# Powered descent, from the PDI PAD's state vector, 4,400 ft off along
	# the track: PDI at 110:20:38.1, the site about 5 miles south of the
	# orbit's plane, which the descent guidance steered out, the lateral
	# velocity up to 78 ft/s about 5 min on (MSC-01855, sections 4.2 and
	# 5.3). The ground's noun 69, 4,200 ft downrange (110:21:57), keyed in
	# (V21N69); the landing radar's altitude at 41,438 ft, delta-H minus 918
	# and minus 1,000 ft as the crew first read it (110:24:12), and V57.
	var lgc := rt.lgc()
	assert_true(run_until(func() -> bool: return sq.pads.has("pdi"), 3600.0, 10.0), "the PDI PAD")
	run(float(sq.plan["pdi_tig"]) - 600.0 - SimClock.get_seconds)
	keys("V37E63E", lgc)
	assert_eq(lgc.program, 63, "P63")
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	var t_pdi := lgc.pdi_tig
	var site := sq.landing_site()
	var spot := sq._touchdown_site()
	var h0 := lm.traj.pos().cross(lm.traj.vel()).normalized()
	var south := h0.dot(Bodies.moon_fixed(t_pdi) * site)
	var seen := {"programs": [], "lateral": 0.0}
	var landed := run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		if sq.pads.has("n69") and not seen.has("n69"):
			var ft := float(sq.pads["n69"]["dz_ft"])
			seen["n69"] = ft
			seen["n69_after"] = SimClock.get_seconds - t_pdi
			keys("V21N69E%s%05dE" % ["+" if ft >= 0.0 else "-", int(absf(ft))], lgc)
		var tr := lm.traj
		var lateral := absf((tr.vel() - Bodies.moon_omega(tr.t).cross(tr.pos())).dot(h0))
		if lateral > float(seen["lateral"]):
			seen["lateral"] = lateral
			seen["lateral_after"] = SimClock.get_seconds - t_pdi
		if not lgc.program in seen["programs"]:
			seen["programs"].append(lgc.program)
		return lgc.program == 64, 900.0, 1.0, false)
	assert_true(landed, "P64")
	# P64 at 110:29:11 near 7,000 ft, left to itself landing 170 ft south
	# and 380 ft west of the Surveyor; the commander redesignated (the LPD)
	# onto the crater and took over in P66 at 400 ft (110:30:50), and
	# Intrepid came down at 110:32:36.2, 535 ft from the Surveyor, with
	# 1,175 lb of the DPS's propellant left (MSC-01855, sections 4.2, 4.3
	# and 8.13; Apollo Lunar Surface Journal).
	var t_p64 := SimClock.get_seconds
	var h_p64 := lgc._h
	var auto_aim := _aim(lgc)
	var clicks := lpd_pilot(lgc, spot, 400.0 * Units.FT)
	Bus.set_value("ctl.lm.mode", 1)
	rod_click(-1)
	assert_eq(lgc.program, 66, "P66")
	var t_p66 := SimClock.get_seconds
	var h_p66 := lgc._h
	while not lm.landed and SimClock.get_seconds - t_p66 < 400.0:
		fly_by_hand(lgc, spot)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_true(lm.landed, "touchdown")
	var td: Dictionary = lm.touchdown
	var t_land := float(td["get_s"])
	var from_surveyor := _apart(lm.landed_pos, site)
	var dps_left := float(Bus.get_value("lm.dps.prop_kg"))
	rows.append("PDI and the crossrange | GET %s; the site %.1f nmi south of the orbit's plane, the lateral velocity up to %.0f ft/s %.0f s on | 110:20:38; about 5 miles south, up to 78 ft/s about 5 min on" % [
		_hms(t_pdi), south / Units.NMI, float(seen["lateral"]) / Units.FT, float(seen["lateral_after"])])
	rows.append("Noun 69 and the landing radar | %+.0f ft %.0f s after PDI; ΔH %.0f ft at %.0f ft | +4,200 ft (110:21:57, 79 s after PDI); −918, −1,000 ft, the radar's altitude from 41,438 ft" % [
		float(seen["n69"]), float(seen["n69_after"]), float(seen["dh0"]) / Units.FT, float(seen["dh0_agl"]) / Units.FT])
	rows.append("P64 | GET %s at %.0f ft, aiming %.0f ft from the Surveyor; %d LPD clicks | 110:29:11 near 7,000 ft, aiming 416 ft from it (170 ft S, 380 ft W)" % [
		_hms(t_p64), h_p64 / Units.FT, _apart(auto_aim, site) / Units.FT, clicks])
	rows.append("The landing | P66 at %s at %.0f ft; touchdown %s, %.0f ft from Surveyor III, %.0f ft from where Intrepid came down; %.0f lb of the DPS's propellant left | P66 at 110:30:50 at 400 ft; 110:32:36, 535 ft from it; 1,175 lb" % [
		_hms(t_p66), h_p66 / Units.FT, _hms(t_land), from_surveyor / Units.FT, _apart(lm.landed_pos, spot) / Units.FT, dps_left / Units.LBM])
	assert_almost_eq(t_pdi, _get_s("110:20:38.1"), 120.0, "PDI's time")
	assert_between(south / Units.NMI, 2.0, 6.0, "the site miles south of the orbit's plane")
	assert_between(float(seen["lateral"]) / Units.FT, 50.0, 110.0, "steered out on the way down")
	assert_almost_eq(float(seen["n69"]), 4200.0, 800.0, "noun 69, the landing site's move downrange")
	assert_almost_eq(float(seen["n69_after"]), 79.0, 2.0, "after throttle-up")
	assert_almost_eq(float(seen["dh0"]) / Units.FT, -1000.0, 500.0, "ΔH when the radar's altitude came good")
	assert_eq(seen["programs"], [63, 64], "braking, then the approach")
	assert_almost_eq(t_p64, _get_s("110:29:11"), 60.0, "P64's time")
	assert_lt(_apart(auto_aim, site), 400.0, "P64 aiming near the Surveyor")
	assert_gt(clicks, 0, "the commander redesignated")
	assert_almost_eq(t_land, _get_s("110:32:36.2"), 90.0, "the landing's time")
	assert_lt(from_surveyor, SURVEYOR_LIMIT_M, "Intrepid beside Surveyor III")
	assert_lt(_apart(lm.landed_pos, spot), 30.0, "where Intrepid came down")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_between(dps_left / Units.LBM, 700.0, 2000.0, "propellant to spare")
	run(2.0, false)
	assert_eq(sq.phase, "lunar_surface", "on the surface")
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)

	# STAY for T1 and T3; Yankee Clipper's first plane change, over Intrepid
	# at the liftoff: the PAD's N81 -11.5, +349.6, 0 at 119:47:12.54 (Apollo
	# Flight Journal, 118:01:54), flown 349.9 ft/s in 18.2 s into 62.5 x 57.6
	# nmi (MSC-01855, Table 5-VI). An orbit a degree less inclined turns less
	# under the site as the Moon turns.
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("stay_t1"), 600.0, 10.0), "T1")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "stay for T1")
	var lopc1 := _await_pad("lopc1_pad", "plane")
	assert_false(lopc1.is_empty(), "LOPC-1")
	var lopc1_n81: Vector3 = lopc1["dv_lvlh"] / Units.FT
	flown = _fly(lopc1)
	o = _orbit(rt.dynamics.traj)
	rows.append("The first plane change (LOPC-1) | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi | 119:47:13, N81 −11.5, +349.6, 0; 349.9 ft/s in 18.2 s; 62.5 × 57.6 nmi" % [
		_hms(float(lopc1["tig"])), lopc1_n81.x, lopc1_n81.y, lopc1_n81.z, flown.x, flown.y, o.x, o.y])
	assert_almost_eq(float(lopc1["tig"]), _get_s("119:47:12.54"), 300.0, "LOPC-1's time")
	assert_almost_eq(flown.x, 349.9, 40.0, "LOPC-1's ΔV")
	assert_almost_eq(flown.y, 18.2, 3.0, "its burn")
	assert_almost_eq(o.x, 62.5, 2.0, "apolune")
	assert_almost_eq(o.y, 57.6, 2.0, "perilune")

	# The ascent PAD at 140:19:25: liftoff at 142:03:47.00, N76 5,535.0 and
	# 37.0 ft/s, 0.2 nmi of crossrange; liftoff at 142:03:47.78, 423.2 s on
	# the APS into 46.3 x 8.8 nmi (MSC-01855, Table 5-VI). The flight plan
	# had it at 142:01:17.9 (Table 1-6): Yankee Clipper came round later than
	# planned, where the simulator's comes round as planned.
	var asc := _await_pad("ascent_pad", "ascent")
	assert_false(asc.is_empty(), "the ascent PAD")
	var tig := float(asc["tig"])
	keys("V37E12E", lgc)
	assert_eq(lgc.program, 12, "P12")
	keys("P", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(maxf(tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "go to cast off")
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
	o = _orbit(lm.traj)
	var ins_plane := rad_to_deg(lm.traj.pos().cross(lm.traj.vel()).normalized().angle_to(
		rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()))
	rows.append("The ascent | liftoff %s, N76 %.1f and %.1f ft/s, %+.2f nmi crossrange; %.0f s on the APS; %.1f × %.1f nmi, %.2f deg from Yankee Clipper's plane | 142:03:48 (planned 142:01:18), N76 5,535.0 and 37.0 ft/s, +0.2 nmi; 423.2 s; 46.3 × 8.8 nmi" % [
		_hms(liftoff), float(asc["vh"]) / Units.FT, float(asc["hdot"]) / Units.FT, float(asc["xrng"]) / Units.NMI,
		float(cutoff["t"]) - liftoff, o.x, o.y, ins_plane])
	assert_almost_eq(liftoff, _get_s("142:01:17.9"), 60.0, "the liftoff near the planned one")
	assert_almost_eq(float(asc["vh"]) / Units.FT, 5535.0, 15.0, "N76's horizontal velocity")
	assert_lt(absf(float(asc["xrng"])) / Units.NMI, 1.0, "under a mile of crossrange: LOPC-1 put the plane over Intrepid")
	assert_almost_eq(float(cutoff["t"]) - liftoff, 423.2, 25.0, "the ascent's burn")
	assert_almost_eq(o.x, 46.3, 2.0, "apolune")
	assert_almost_eq(o.y, 8.8, 1.5, "perilune")
	assert_lt(ins_plane, 0.1, "in Yankee Clipper's plane")

	# The coelliptic sequence on the LGC's P32 to P35 and the LM RCS: CSI
	# 45.0 ft/s at 143:01:51 into 51.0 x 41.5 nmi; CDH 13.8 ft/s at
	# 144:00:02.6; TPI 29.0 ft/s at 144:36:26; docking at 145:36:20.2,
	# Yankee Clipper active (MSC-01855, Tables 5-VI and 5-VII).
	assert_true(run_until(func() -> bool: return sq.pads.has("csi"), 3600.0, 1.0), "the CSI PAD")
	var pad: Dictionary = sq.pads["csi"]
	var lm0 := lm.dv_total
	keys("V37E20E", lgc)
	run(float(pad["tig"]) - 1500.0 - SimClock.get_seconds)
	keys("V37E32E", lgc)
	keys("PPP", lgc)
	assert_eq(lgc.step_name, "n75", "P32: V06N75")
	keys("PP", lgc)
	var csi := _lm_burn(41, 0, false)
	var o_csi := _orbit(lm.traj)
	run(lgc.rdv_cdh_tig - 1200.0 - SimClock.get_seconds)
	keys("V37E33EP", lgc)
	var dh := lgc.rdv_dh
	var t_cdh := lgc.rdv_cdh_tig
	keys("PP", lgc)
	var cdh := _lm_burn(41, 0, false)
	run(float(pad["tpi_get"]) - 1800.0 - SimClock.get_seconds)
	for lead in [0.0, 720.0]:
		if lead > 0.0:
			run(lgc.rdv_tpi_tig - lead - SimClock.get_seconds)
		keys("V37E34EP", lgc)
		assert_eq(lgc.step_name, "n37", "P34: V06N37, TPI's time")
		keys("P", lgc)
		keys("PP", lgc)
	var tpi_tig := lgc.rdv_tpi_tig
	var tpi := _lm_burn(41, 0, false)
	var tpm := 0.0
	for after in sq.mission.section("rendezvous")["tpm_after_tpi_s"]:
		run(tpi_tig + float(after) - 300.0 - SimClock.get_seconds)
		keys("V37E35EP", lgc)
		tpm += _lm_burn(41, 0, false).x
	assert_true(lm_brake(1800.0), "braked to station-keeping")
	var lm_dv := (lm.dv_total - lm0) / Units.FT
	face_x(true, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())
	face_x(false, func() -> Vector3: return Rendezvous.rel_pos(rt.dynamics.traj, rt.dynamics.lm.traj).normalized())
	csm_move_to(Vector3(10.0, 0.0, 0.0), 60.0)
	assert_true(csm_approach(0.1), "the probe met the drogue")
	assert_true(dock_contact()["captured"], "within the capture limits")
	var docked := sq.event_get("docking")
	rows.append("CSI | GET %s, %.1f ft/s; %.1f × %.1f nmi | 143:01:51, 45.0 ft/s; 51.0 × 41.5 nmi" % [
		_hms(float(pad["tig"])), csi.x, o_csi.x, o_csi.y])
	rows.append("CDH | GET %s, %.1f ft/s, %.1f nmi below Yankee Clipper | 144:00:03, 13.8 ft/s" % [_hms(t_cdh), cdh.x, dh / Units.NMI])
	rows.append("TPI | GET %s, %.1f ft/s; the midcourse corrections %.1f ft/s | 144:36:26, 29.0 ft/s" % [_hms(tpi_tig), tpi.x, tpm])
	rows.append("Docking | GET %s, the LM's RCS %.0f ft/s from CSI | 145:36:20" % [_hms(docked), lm_dv])
	assert_almost_eq(csi.x, 45.0, 10.0, "CSI")
	assert_almost_eq(float(pad["tig"]), _get_s("143:01:51"), 600.0, "CSI's time")
	assert_lt(cdh.x, 25.0, "CDH")
	assert_almost_eq(tpi.x, 29.0, 8.0, "TPI")
	assert_almost_eq(tpi_tig, _get_s("144:36:26"), 900.0, "TPI's time")
	assert_lt(tpm, 10.0, "small midcourse corrections")
	assert_almost_eq(docked, _get_s("145:36:20.2"), 1800.0, "docked")
	assert_eq(sq.phase, "lunar_orbit", "docked again")

	# GO for Pyro Arm, LM JETT (147:59:32); the second plane change, for the
	# photographs: the PAD's N81 -13.6, +381.1, 0 at 159:04:44.78 (Apollo
	# Flight Journal, 157:32:01), flown 381.8 ft/s in 19.2 s into 64.7 x
	# 56.8 nmi (MSC-01855, Table 5-VI).
	Bus.set_value("ctl.cmc.mode", 0)
	run(docked + 7569.0 + 10.0 - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for Pyro Arm")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.lm_jett", false)
	assert_eq(rt.dynamics.config, "csm", "Intrepid's ascent stage jettisoned")
	var lopc2 := _await_pad("lopc2_pad", "plane")
	assert_false(lopc2.is_empty(), "LOPC-2")
	flown = _fly(lopc2)
	o = _orbit(rt.dynamics.traj)
	rows.append("The second plane change (LOPC-2) | GET %s, %.1f ft/s in %.1f s; %.1f × %.1f nmi | 159:04:46, 381.8 ft/s in 19.2 s; 64.7 × 56.8 nmi" % [
		_hms(float(lopc2["tig"])), flown.x, flown.y, o.x, o.y])
	assert_almost_eq(flown.x, 381.3, 2.0, "the PAD's 381.3 ft/s")
	assert_almost_eq(flown.y, 19.2, 3.0, "its burn")

	# TEI: the TEI-45 PAD's 172:27:16.14, N81 +3,027.2, +302.1, -25.3;
	# flown 3,042.0 ft/s in 130.3 s (MSC-01855, Table 5-VIII). The RTCC
	# moves the TIG to where the burn needs no part up or down, for Yankee
	# Clipper comes round to the flown TEI's place minutes early.
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	var tei_n81: Vector3 = tei["dv_lvlh"] / Units.FT
	flown = _fly(tei)
	var ei_tei := _ei_get(rt.dynamics.traj)
	rows.append("TEI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; entry interface after it at %s | 172:27:17, N81 +3,027.2, +302.1, −25.3; 3,042 ft/s in 130.3 s; 244:22:19" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y, _hms(ei_tei)])
	assert_almost_eq(float(tei["tig"]), _get_s("172:27:16.8"), 400.0, "TEI's time")
	assert_lt(absf(tei_n81.z), 2.0, "no part up or down")
	assert_almost_eq(flown.x, 3042.0, 40.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 130.3, 15.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# The transearth midcourse corrections on the RCS: MCC-5, 2.0 ft/s at
	# 188:27:16; MCC-7, 2.4 ft/s at 241:22:00 (MSC-01855, Table 5-VIII).
	# MSFN's tracking error in the TEI PAD's state vector moves the return
	# far more than the flight's did (README, Simplifications).
	var mccs := []
	for id in ["mcc5_pad", "mcc7_pad"]:
		var m := _await_pad(id, "mcc")
		mccs.append(float(m.get("dv", 0.0)) / Units.FT)
		_fly(m)
	rows.append("Transearth midcourse corrections | MCC-5 %.1f ft/s, MCC-7 %.1f ft/s | MCC-5 2.0 ft/s, MCC-7 2.4 ft/s" % mccs)
	assert_lt(float(mccs[0]) + float(mccs[1]), 25.0, "trims")
	assert_lt(float(mccs[1]), 8.0, "MCC-7, a trim")

	# The entry PAD, 239:31:59: 15.81 S 165.17 W; then P52 before the entry,
	# and GO for Pyro Arm.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(-15.81, -165.17), "N61 uplinked")
	run(_get_s("243:00:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_pyro_arm"), 3.0 * 3600.0, 60.0), "home")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You're Go for Pyro Arm")

	# Entry interface: 244:22:19.1, 36,116 ft/s, 6.48 deg down, at 13.80 S
	# 173.52 E (MSC-01855, Table 5-IX). MSFN's tracking error in the TEI
	# PAD's state vector, and the transearth corrections aimed at the
	# corridor alone, move it minutes and a degree or two here, and the
	# entry flies the difference out (README, Simplifications).
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 3600.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f S %.2f E | 244:22:19, 36,116 ft/s, 6.48 deg down, 13.80 S 173.52 E" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, -geo.x, geo.y])
	assert_almost_eq(ei.t, _get_s("244:22:19.1"), 300.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36116.0, 20.0, "its speed")
	assert_almost_eq(ei_gamma, -6.48, 0.2, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(-13.80, 173.52)) * Bodies.R_EARTH / Units.NMI, 150.0, "where")

	# The entry on P61 to P67 to 15.81 S 165.17 W, 6.1 g at the peak on the
	# PAD; down at 244:36:25, 15.78 S 165.15 W, within 2 miles of the target
	# (MSC-01855, section 5).
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 6.1 g on the PAD" % [str(fe["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.2f S %.2f W, %.1f nmi from the target | 244:36:25, 15.78 S 165.15 W, within 2 miles of it" % [
		_hms(land), -at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 12.")
	assert_almost_eq(rt.dynamics.max_g, 6.1, 0.8, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(land, _get_s("244:36:25"), 180.0, "splashdown's time")

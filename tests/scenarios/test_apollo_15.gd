## Slice 12b (docs/ROADMAP.md, milestone 12): Apollo 15 flies from its data
## alone (data/missions/apollo_15/mission.json), from its parking orbit to
## the landing at Hadley; tests/scenarios/test_apollo_15_return.gd flies it
## home from the surface. The S-IVB flies TLI onto a trajectory past the
## Moon 139 nmi up, not a free return; the SPS's test burn, flown as MCC-2,
## and MCC-4 bring the pericynthion down to 68 nmi in the plane over the
## site, and LOI turns the orbit into it, 26 deg to the lunar equator.
## Endeavour flies DOI with Falcon docked, down to 10 nmi at the low point,
## and after the undocking, 25 min late on a loose umbilical, climbs back
## to 60 nmi (CIRC). Falcon's crew realign its platform with P52 on the
## stars they used, and it flies powered descent on its LGC's own targets,
## Luminary 210's for Apollo 15, 25 deg steep past the Apennine front: the
## ground's noun 69 takes out what its state vector had wrong along the
## track, the landing radar's ΔH counts the Apennines' height by the LGC's
## terrain model, and the commander redesignates the landing point north
## and uprange and flies the last 400 ft in P66 to the spot Falcon came
## down on. Each PAD Mission Control's timeline brings is flown as the
## crew flew it: the CSM's on P30 and P40 or P41, the LM's on P63 to P66.
## The flight's figures are the Fidelity table in README.md, each held here
## within set limits of Apollo 15's: the Apollo 15 Mission Report
## (MSC-05161), the AS-510 flight evaluation report (MPR-SAT-FE-71-2), the
## flight controllers' postflight memos, the Apollo Flight Journal and the
## Apollo Lunar Surface Journal [published].
extends SimTest

## How long before TIG the crew select the thrusting program, s: time
## enough for the auto maneuver's 1°/s to turn to any attitude, and less
## than the checklists' quarter of an hour, for the suite's time.
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


func test_apollo_15_flies_its_data_and_lands_at_hadley() -> void:
	build("parking_orbit", "apollo_15")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_true(rt.dynamics.has_lm(), "Falcon in the adapter")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:50:02.8 for 350.8 s, 10,414.7
	# ft/s gained (MSC-05161, Table 3-V(a)), C3 -1,438,810 m2/s2 at TLI, 10 s
	# on (MPR-SAT-FE-71-2, Table 4-5); past the Moon 139 nmi up at 78:31:21
	# (MSC-05161, Table 3-V), not a free return. What the J-2 gave: the
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
	rows.append("TLI | GET %s, %.0f ft/s in %.1f s, C3 %.0f m²/s²; the pericynthion after it %.1f nmi at %s | 2:50:03, 10,414.7 ft/s in 350.8 s, C3 −1,438,810 m²/s²; 139 nmi at 78:31:21" % [
		_hms(ign), j2, cut - ign, c3, p.x, _hms(p.y)])
	assert_almost_eq(ign, _get_s("2:50:02.8"), 30.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 350.8, 5.0, "its burn")
	assert_almost_eq(j2, 10414.7, 100.0, "what the J-2 gave")
	assert_almost_eq(c3, -1438810.0, 20000.0, "C3")
	assert_almost_eq(p.x, 139.0, 10.0, "the pericynthion, not a free return")
	assert_almost_eq(p.y, _get_s("78:31:21"), 60.0, "and when")

	# Transposition, docking and extraction as the ground takes them at the
	# flight's extraction, 4:18:01. The SPS's test burn, flown as MCC-2 at
	# the PAD's 28:40:00.00 after the SPS THRUST light stayed on from TLI:
	# 5.3 ft/s on the SCS, the pericynthion then 63 nmi up at 78:35:15
	# (MSC-05161, Table 3-V and section 14.1.3; Apollo Flight Journal,
	# 027:58:26); MCC-4, the PAD's 5.4 ft/s at 73:31:14.02 (ibid., 072:43:50),
	# after which the pericynthion was 68.3 nmi up at 78:35:06 (MPAD's
	# postflight CSM maneuver analysis, p. 3).
	var mcc2 := _await_pad("mcc2_pad", "mcc")
	assert_eq(rt.dynamics.config, "csm_lm", "Falcon docked since the transposition")
	assert_false(mcc2.is_empty(), "MCC-2, the SPS's test")
	var mcc2_n81 := _n81(mcc2)
	_fly(mcc2)
	p = _pericynthion()
	rows.append("MCC-2, the SPS's test | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 5.3 ft/s at 28:40:22 on the SCS; then 63 nmi at 78:35:15" % [
		float(mcc2["dv"]) / Units.FT, _hms(float(mcc2["tig"])), mcc2_n81.x, mcc2_n81.y, mcc2_n81.z, p.x, _hms(p.y)])
	assert_lt(float(mcc2["dv"]) / Units.FT, 15.0, "MCC-2 a few ft/s, as the test's")
	assert_almost_eq(p.x, 68.3, 7.0, "the pericynthion after it, off by MSFN's tracking error")
	assert_almost_eq(p.y, _get_s("78:35:06"), 60.0, "and when")
	var mcc4 := _await_pad("mcc4_pad", "mcc")
	_fly(mcc4)
	p = _pericynthion()
	rows.append("MCC-4 | %.1f ft/s; then %.1f nmi at %s | 5.4 ft/s at 73:31:14; then 68.3 nmi at 78:35:06" % [
		float(mcc4.get("dv", 0.0)) / Units.FT, p.x, _hms(p.y)])
	assert_lt(float(mcc4.get("dv", 0.0)) / Units.FT, 8.0, "MCC-4, a trim")
	assert_almost_eq(p.x, 68.3, 3.0, "the pericynthion before LOI")

	# LOI behind the Moon: the final PAD's N81 -2,897.5, -776.4, -44.1 at
	# 78:31:45.91, into 169.6 x 58.4 nmi (Apollo Flight Journal, 077:31:04);
	# flown 3,000.1 ft/s in 398.4 s into 170.1 x 57.7 nmi (MSC-05161, Table
	# 3-V), the orbit 26 deg to the lunar equator over Hadley.
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI")
	var loi_n81 := _n81(loi)
	run(_get_s("78:03:50") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for LOI")
	var flown := _fly(loi)
	var o := _orbit(rt.dynamics.traj)
	var incl := _inclination(rt.dynamics.traj)
	rows.append("LOI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; %.1f × %.1f nmi, %.2f deg to the lunar equator | 78:31:46, N81 −2,897.5, −776.4, −44.1; 3,000.1 ft/s in 398.4 s; 170.1 × 57.7 nmi" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(float(loi["tig"]), _get_s("78:31:45.91"), 90.0, "LOI's time")
	assert_almost_eq(flown.x, 3000.1, 100.0, "LOI's ΔV")
	assert_almost_eq(flown.y, 398.4, 30.0, "its burn")
	assert_almost_eq(o.x, 170.1, 4.0, "apolune")
	assert_almost_eq(o.y, 57.7, 3.0, "perilune")
	assert_almost_eq(incl, 26.1, 1.2, "the orbit over Hadley")

	# DOI, the CSM's with Falcon docked: the PAD's N81 -208.4, -48.0, +2.0
	# at 82:39:48.29 (Apollo Flight Journal, 081:31:14), flown 213.9 ft/s in
	# 24.5 s into 58.5 x 9.6 nmi (MSC-05161, Table 3-V). The RTCC sizes it to
	# bring the orbit over the PDI point on the landing pass at PDI's height
	# (Rtcc.plan_doi_docked()), flying it through the Moon's field for the
	# day, with no plane change in it. Its perilune comes out 2 nmi higher
	# than the flight's, which decayed faster than predicted until the SM
	# RCS raised it 3.2 ft/s at 95:56:44.7 (the DOI trim, not flown here),
	# and each revolution some 15 s longer: PDI and the landing come 3 min
	# after the flight's [simplified].
	var doi := _await_pad("doi_pad", "doi")
	assert_false(doi.is_empty(), "DOI, docked")
	var doi_n81 := _n81(doi)
	flown = _fly(doi)
	o = _orbit(rt.dynamics.traj)
	rows.append("DOI, Endeavour with Falcon docked | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi; PDI planned for %s | 82:39:48, N81 −208.4, −48.0, +2.0; 213.9 ft/s in 24.5 s; 58.5 × 9.6 nmi; PDI 104:30:09" % [
		_hms(float(doi["tig"])), doi_n81.x, doi_n81.y, doi_n81.z, flown.x, flown.y, o.x, o.y, _hms(float(doi["hp_get"]))])
	assert_eq(rt.dynamics.config, "csm_lm", "docked through DOI")
	assert_almost_eq(float(doi["tig"]), _get_s("82:39:48.29"), 240.0, "DOI's time")
	assert_almost_eq(flown.x, 213.9, 15.0, "DOI's ΔV")
	assert_almost_eq(o.x, 58.5, 2.0, "apolune")
	assert_almost_eq(o.y, 9.6, 2.5, "perilune, higher: no trim")
	assert_almost_eq(float(doi["hp_get"]), _get_s("104:30:08.54"), 240.0, "PDI planned on the landing pass")

	# The separation PAD, docked, its TIG 100:13:56.00; the undocking came
	# 25 min late, the probe's umbilical loose (Apollo Flight Journal,
	# 098:41:59 and 100:18:21 to 100:39:37), and the separation, 1.1 ft/s
	# radially down on P47, right after it (MSC-05161, Table 3-I; the
	# post-launch mission operation report, Table 6). Here on P41 at the
	# timeline's TIG, 21 s after the undocking: Endeavour turns off Falcon
	# to the burn attitude as it burns, and senses more than the PAD's 1.0.
	var sep := _await_pad("sep_pad", "sep")
	assert_true(bool(sep.get("uplinked", false)), "the separation PAD in the CMC")
	run(_get_s("100:39:16") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "umbilical is probably not well connected")
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "undocked")
	assert_eq(sq.phase, "lunar_descent", "Falcon on the descent orbit")
	Bus.set_value("ctl.lm.mode", 0)
	var sepf := fly_pad(0, LEAD_S) / Units.FT
	rows.append("The CSM's separation | %.1f ft/s at 100:39:37 on P41, the PAD's 1.0 radially down | 1.1 ft/s on P47 right after the undocking at 100:39:16" % sepf)
	assert_almost_eq(sepf, 1.1, 0.4, "the separation, turning as it burns")

	# Endeavour's circularization: the CIRC PAD's N81 +68.3, -0.1, -0.7 at
	# 101:38:58.19 into 64.9 x 54.3 nmi (Apollo Flight Journal, 101:05:30);
	# flown 68.3 ft/s into 65.2 x 54.8 (MSC-05161, Table 3-V).
	var circ := _await_pad("circ_pad", "circ")
	assert_false(circ.is_empty(), "CIRC")
	assert_eq(str(circ["name"]), "CIRC", "the CSM's own")
	var circ_n81 := _n81(circ)

	# Falcon's first P52, at 101:16 on stars 41 (Dabih) and 01 (Alpheratz)
	# through the left-front detent: N05 0.01°, N93 -0.002, +0.076 and
	# -0.046° (MSC-05161, Table 7-I). The platform stood so at undocking,
	# less the drift since (mission.json "lgc": first_p52), and the descent
	# flies on the platform it leaves.
	run(_get_s("101:14:00") - SimClock.get_seconds)
	var p52 := lm_realign([41, 1])
	var n93: Vector3 = p52["torque"]
	rows.append("Falcon's first P52 | GET %s on stars 41 and 01: N05 %.3f°, N93 %+.3f, %+.3f and %+.3f° | 101:16: 0.01°; −0.002, +0.076 and −0.046°" % [
		_hms(float(p52["get"])), p52["sad"], n93.x, n93.y, n93.z])
	assert_almost_eq(n93, Vector3(-0.002, 0.076, -0.046), Vector3.ONE * 0.015, "N93 as flown")
	assert_lt(float(p52["sad"]), 0.05, "N05 within the flown")
	assert_lt(rad_to_deg(rt.lgc().imu.misalignment().length()), 0.01, "the platform on the REFSMMAT")
	flown = _fly(circ)
	o = _orbit(rt.dynamics.traj)
	rows.append("CIRC | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s; Endeavour in %.1f × %.1f nmi | 101:38:58, N81 +68.3, −0.1, −0.7; 65.2 × 54.8 nmi" % [
		_hms(float(circ["tig"])), circ_n81.x, circ_n81.y, circ_n81.z, flown.x, o.x, o.y])
	assert_almost_eq(float(circ["tig"]), _get_s("101:38:58.19"), 1.0, "at the PAD's TIG")
	assert_almost_eq(flown.x, 68.3, 8.0, "CIRC's ΔV")
	assert_almost_eq(o.x, 65.2, 2.0, "Endeavour's apolune")
	assert_almost_eq(o.y, 54.8, 2.0, "and perilune")

	# Powered descent on Luminary 210's own targets, from the PDI PAD's
	# state vector, 2,800 ft off along the track: the PAD at 102:27:58, its
	# TIG updated to 104:30:08.54 (Apollo Lunar Surface Journal); Falcon
	# about 50,000 ft up at ignition (the press kit's nominal 50,087). The
	# ground's noun 69, 2,800 ft downrange, 76.5 s after ignition, keyed in
	# (V21N69). The landing radar's altitude came good 3 min 29 s after
	# ignition at 42,000 ft of slant range (MSC-05161, p. 7-4 and Table
	# 7-IV), ΔH +3,400 ft, and with V57 the LGC took its altitude up by
	# 4,800 ft: the terrain model's 1 deg of slope over the mare, where the
	# mare had none, until the Apennine foothills (ibid., p. 7-8).
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
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for PDI")
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	var t_pdi := lgc.pdi_tig
	var site := sq.landing_site()
	var spot := sq._touchdown_site()
	var h_pdi := lm.traj.radius() - site.length()
	var seen := {"programs": [], "high": 0.0}
	var landed := run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		if seen.has("dh0") and not seen.has("lr_get"):
			seen["lr_get"] = SimClock.get_seconds - t_pdi
		if lgc.lr_update:
			# How far above the truth the radar's updates, by the terrain
			# model, take the LGC's altitude.
			seen["high"] = maxf(float(seen["high"]), lgc._h - (lm.traj.radius() - site.length() - Dynamics.lm_cm_height("lm")))
		if sq.pads.has("n69") and not seen.has("n69"):
			var ft := float(sq.pads["n69"]["dz_ft"])
			seen["n69"] = ft
			seen["n69_after"] = SimClock.get_seconds - t_pdi
			keys("V21N69E%s%05dE" % ["+" if ft >= 0.0 else "-", int(absf(ft))], lgc)
		if not seen.has("throttle_down") and seen.has("full") and lgc.descent_throttle < 0.65:
			seen["throttle_down"] = SimClock.get_seconds - t_pdi
		if lgc.descent_throttle > 0.99:
			seen["full"] = true
		if not lgc.program in seen["programs"]:
			seen["programs"].append(lgc.program)
		return lgc.program == 64, 900.0, 1.0, false)
	assert_true(landed, "P64")
	# P64 at 104:39:32, 9 min 22.8 s after ignition, at 7,000 ft; the
	# commander redesignated 18 times, 1,110 ft uprange and 1,341 ft north,
	# took over in P66 at 400 ft (104:41:08) and Falcon came down at
	# 104:42:29.3 with 1,188 lb of the DPS's propellant left (MSC-05161,
	# Tables 7-IV and p. 7-8, section 7.11.1; the Apollo Lunar Surface
	# Journal).
	var t_p64 := SimClock.get_seconds
	var h_p64 := lgc._h
	var h_err_p64 := lgc._h - (lm.traj.radius() - site.length() - Dynamics.lm_cm_height("lm"))
	var auto_aim := _aim(lgc)
	var clicks := lpd_pilot(lgc, spot, 400.0 * Units.FT)
	Bus.set_value("ctl.lm.mode", 1)
	rod_click(-1)
	assert_eq(lgc.program, 66, "P66")
	var t_p66 := SimClock.get_seconds
	var h_p66 := lgc._h
	var off := _apart(Bodies.moon_fixed(t_p66).transposed() * lm.traj.pos(), spot)
	while not lm.landed and SimClock.get_seconds - t_p66 < 400.0:
		fly_by_hand(lgc, spot)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	run(SimClock.FIXED_DT, false)
	assert_true(lm.landed, "touchdown")
	var td: Dictionary = lm.touchdown
	var t_land := float(td["get_s"])
	var dps_left := float(Bus.get_value("lm.dps.prop_kg"))
	rows.append("PDI | the PAD at %s; GET %s, %.0f ft over the site | the PAD at 102:27:58; 104:30:09, about 50,000 ft (the nominal 50,087)" % [
		_hms(t_pad), _hms(t_pdi), h_pdi / Units.FT])
	rows.append("Noun 69 | %+.0f ft %.0f s after PDI | 2,800 ft downrange 76.5 s after PDI, voiced −02800" % [float(seen["n69"]), float(seen["n69_after"])])
	rows.append("The landing radar and the terrain model | the altitude good %.0f s after PDI, ΔH %+.0f ft; the LGC's altitude taken %.0f ft above the truth, %+.0f ft at P64 | 3:29 after PDI, ΔH +3,400 ft; taken up 4,800 ft, converged over the Apennine foothills" % [
		float(seen["lr_get"]), float(seen["dh0"]) / Units.FT, float(seen["high"]) / Units.FT, h_err_p64 / Units.FT])
	rows.append("Throttle-down | %.0f s after PDI | 7:21.7" % float(seen["throttle_down"]))
	rows.append("P64, the 25 deg approach | GET %s, %.0f s after PDI, at %.0f ft, aiming %.0f ft from where Falcon came down; %d LPD clicks | 104:39:32, 9:22.8 after PDI, at 7,000 ft; 18 redesignations" % [
		_hms(t_p64), t_p64 - t_pdi, h_p64 / Units.FT, _apart(auto_aim, spot) / Units.FT, clicks])
	rows.append("The landing | P66 at %s at %.0f ft, %.0f ft off; touchdown %s, %.0f s after PDI, %.0f ft from where Falcon came down; %.0f lb of the DPS's propellant left | P66 at 104:41:08 at 400 ft; 104:42:29, 740 s after PDI; 1,188 lb" % [
		_hms(t_p66), h_p66 / Units.FT, off / Units.FT, _hms(t_land), t_land - t_pdi, _apart(lm.landed_pos, spot) / Units.FT, dps_left / Units.LBM])
	assert_almost_eq(t_pad, _get_s("102:27:58"), 240.0, "the PDI PAD, two hours ahead")
	assert_almost_eq(t_pdi, _get_s("104:30:08.54"), 240.0, "PDI's time, 3 min late")
	assert_almost_eq(h_pdi / Units.FT, 50087.0, 4000.0, "PDI's height")
	assert_almost_eq(float(seen["n69"]), 2800.0, 800.0, "noun 69, the landing site's move downrange")
	assert_almost_eq(float(seen["n69_after"]), 76.5, 2.0, "after throttle-up")
	assert_between(float(seen["high"]) / Units.FT, 1000.0, 7000.0, "the terrain model took the LGC's altitude up over the mare")
	assert_lt(absf(h_err_p64) / Units.FT, 500.0, "and over the foothills the radar brought it back")
	assert_almost_eq(float(seen["throttle_down"]), 441.7, 30.0, "the throttle-down")
	assert_eq(seen["programs"], [63, 64], "braking, then the approach")
	assert_almost_eq(t_p64 - t_pdi, 562.8, 30.0, "P64 at 9 min 23 s, the 25 deg approach's high gate")
	assert_almost_eq(h_p64 / Units.FT, 7000.0, 1500.0, "P64's height")
	assert_gt(clicks, 0, "the commander redesignated")
	assert_almost_eq(h_p66 / Units.FT, 400.0, 30.0, "P66 at 400 ft")
	assert_lt(off / Units.FT, 800.0, "the redesignations brought it near the spot")
	assert_almost_eq(t_land - t_pdi, _get_s("104:42:29.3") - _get_s("104:30:09.4"), 60.0, "the descent's time")
	assert_almost_eq(t_land, _get_s("104:42:29.3"), 240.0, "the landing's time")
	assert_lt(_apart(lm.landed_pos, spot), 30.0, "where Falcon came down")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_between(dps_left / Units.LBM, 600.0, 2000.0, "propellant to spare")
	run(2.0, false)
	assert_eq(sq.phase, "lunar_surface", "on the surface")
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	for row in rows:
		gut.p("Fidelity: " + row)

## Slice 7a (docs/ROADMAP.md, milestone 7): Apollo 8 flies from its data
## alone (data/missions/apollo_8/mission.json), from its parking orbit to
## the splashdown. The S-IVB flies TLI to the RTCC's plan; the CSM leaves it
## and its test article; and each PAD Mission Control's timeline brings is
## flown as the crew flew it (P30, P52, then P40 on the SPS or P41 on the
## RCS): the separation maneuvers, the midcourse corrections, LOI-1 and
## LOI-2, ten lunar orbits in the Moon's field, TEI, the transearth
## corrections, and the entry on P61 to P67. The flight's figures are the
## Fidelity table in README.md, each held here within set limits of Apollo
## 8's: the Apollo 8 Mission Report (MSC-PA-R-69-1), the AS-503 flight
## evaluation report (MPR-SAT-FE-69-1) and the Apollo Flight Journal
## [published].
extends SimTest

var sq: MissionSequencer


## The PAD of [param kind] timeline entry [param id] brought, or {} when
## the RTCC found no burn required.
func _await_pad(id: String, kind: String) -> Dictionary:
	sq.pads.erase(kind)
	assert_true(run_until(func() -> bool: return sq.timeline_done.has(id), 150.0 * 3600.0, 600.0), id)
	return sq.pads.get(kind, {})


## Fly [param pad] as the crew does (fly_pad(), a P52 first for option
## [param p52] unless 0). Returns the ΔV the CMC sensed (ft/s) and how
## long the SPS burned (s; none on the RCS).
func _fly(pad: Dictionary, p52: int = 1) -> Vector2:
	if pad.is_empty():
		return Vector2.ZERO
	var burned := float(Bus.get_value("sps.burn_time_s", 0.0))
	var dv := fly_pad(p52)
	return Vector2(dv / Units.FT, float(Bus.get_value("sps.burn_time_s", 0.0)) - burned)


## The pericynthion ahead: x its altitude (nmi), y its GET.
func _pericynthion() -> Vector2:
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, SimClock.get_seconds + 5.0 * 86400.0)
	return Vector2((float(ap["rp"]) - Bodies.R_MOON) / Units.NMI, Rtcc._pericynthion_time(tr))


## The lunar orbit's apolune and perilune above the Moon's mean radius
## (the mission report's datum for Apollo 8), nmi.
func _orbit() -> Vector2:
	var c := rt.dynamics.traj.conic()
	return Vector2(float(c["ra"]) - Bodies.R_MOON, float(c["rp"]) - Bodies.R_MOON) / Units.NMI


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_8_flies_its_data_from_the_parking_orbit_to_the_splashdown() -> void:
	build("parking_orbit", "apollo_8")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_false(rt.dynamics.has_lm(), "the adapter holds LTA-B")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Apollo 8, Houston. You are GO for TLI.")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:50:37.1 to 2:55:55.5, 3,040 m/s
	# gained (MSC-PA-R-69-1, Table 5-II), C3 -1,478,917 m2/s2 at TLI, 10 s
	# on (MPR-SAT-FE-69-1, Table 4-7).
	var ok := run_until(func() -> bool: return str(Bus.get_value("sivb.state")) == "done", 4.0 * 3600.0, 60.0)
	assert_true(ok, "TLI")
	assert_string_contains(str(Bus.get_value("mission.capcom", "")), "TLI cutoff")
	var ign := sq.event_get("tli_ignition")
	var cut := sq.event_get("tli_cutoff")
	var tli: Dictionary = sq.tli_pad
	run(cut + 10.0 - SimClock.get_seconds, false)
	var c3 := 2.0 * float(rt.dynamics.traj.conic()["energy"])
	rows.append("TLI | GET %s, %.0f m/s in %.1f s, C3 %.0f m²/s² | 2:50:37, 3,040 m/s in 318.4 s, C3 −1,478,917 m²/s²" % [
		_hms(ign), float(tli["dv"]), cut - ign, c3])
	assert_almost_eq(ign, _get_s("2:50:37.1"), 60.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 318.4, 5.0, "its burn")
	assert_almost_eq(float(tli["dv"]), 3040.0, 15.0, "the speed it gave")
	assert_almost_eq(c3, -1478917.0, 70000.0, "C3: the S-IVB's venting, unmodelled, carried the flight's on before it separated")

	# CSM/LV SEP after the scripted delay, then the two separation
	# maneuvers radially up, the second the unplanned one: the pericynthion
	# after them 458.1 nmi at 68:57:40 (Table 5-III), which the flight's
	# state at MCC-1's ignition passes at 464.0 nmi, 69:01:20, here.
	var sep1 := _fly(_await_pad("sep_1", "sep"), 0)
	assert_eq(rt.dynamics.config, "csm", "the CSM alone since CSM/LV SEP")
	assert_true(sq._has("csm_lv_sep") and not sq._has("transposition_docking"), "and nothing to dock with")
	var sep2 := _fly(_await_pad("sep_2", "sep"), 0)
	var p := _pericynthion()
	rows.append("The separation maneuvers | %.1f and %.1f ft/s radially up; the pericynthion after them %.1f nmi at %s | 1.1 and 7.7 ft/s; 458.1 nmi at 68:57:40" % [
		sep1.x, sep2.x, p.x, _hms(p.y)])
	assert_almost_eq(sep1.x, 1.1, 0.2, "the first separation maneuver")
	assert_almost_eq(sep2.x, 7.7, 0.2, "the second")
	assert_almost_eq(p.x, 458.1, 10.0, "the pericynthion after them")
	assert_almost_eq(p.y, _get_s("68:57:40"), 300.0, "and when")

	# MCC-1 on the SPS: the PAD's 24.8 ft/s at 10:59:58.30, N81 +13.6, -4.5,
	# +20.2 (Apollo Flight Journal, 9:58:29), flown 20.4 on the short burn's
	# low thrust; 66.3 nmi at 69:10:40 after it (Table 5-III).
	var mcc1 := _await_pad("mcc1_pad", "mcc")
	assert_false(mcc1.is_empty(), "MCC-1")
	var mcc1_n81: Vector3 = mcc1["dv_lvlh"] / Units.FT
	_fly(mcc1)
	p = _pericynthion()
	rows.append("MCC-1 | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 24.8 ft/s at 10:59:58, N81 +13.6, −4.5, +20.2 (flown 20.4); then 66.3 nmi at 69:10:40" % [
		float(mcc1["dv"]) / Units.FT, _hms(float(mcc1["tig"])), mcc1_n81.x, mcc1_n81.y, mcc1_n81.z, p.x, _hms(p.y)])
	assert_almost_eq(float(mcc1["dv"]) / Units.FT, 24.8, 3.0, "MCC-1")
	assert_almost_eq(p.x, 66.3, 4.0, "the pericynthion after it")
	assert_almost_eq(p.y, _get_s("69:10:40"), 60.0, "and when")

	# MCC-2 (the flight plan's MCC-4) on the RCS: the PAD's 2.0 ft/s at
	# 60:59:54.30, flown 1.4; 65.8 nmi at 69:10:39 after it (Table 5-III).
	var mcc2 := _await_pad("mcc2_pad", "mcc")
	_fly(mcc2)
	p = _pericynthion()
	rows.append("MCC-2 | %.1f ft/s; %.1f nmi at %s | 2.0 ft/s (flown 1.4); 65.8 nmi at 69:10:39" % [
		float(mcc2.get("dv", 0.0)) / Units.FT, p.x, _hms(p.y)])
	assert_lt(float(mcc2.get("dv", 0.0)) / Units.FT, 4.0, "MCC-2")
	assert_almost_eq(p.x, 65.8, 2.0, "the pericynthion before LOI")
	assert_almost_eq(p.y, _get_s("69:10:39"), 30.0, "and when")

	# LOI-1 behind the Moon, at the PAD's TIG, 69:08:19.52: N81 -2,984.0,
	# +239.0 (the plane change), +105.3; flown 2,997 ft/s in 246.9 s into
	# 168.5 x 60.0 nmi, 0.79 deg down at its cutoff (Table 5-II and section
	# 5.5), the orbit inclined 12.29 deg [derived from Table 5-II].
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI-1")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "LOI-1 PAD")
	var loi_n81: Vector3 = loi["dv_lvlh"] / Units.FT
	run(_get_s("68:04:10") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "At 68:04, you're GO for LOI.")
	var flown := _fly(loi)
	var o := _orbit()
	var tr := rt.dynamics.traj
	var gamma := rad_to_deg(asin(tr.radial_rate() / tr.speed()))
	var rel := tr.moon_state_rel()
	var h := Vector3(rel[0], rel[1], rel[2]).cross(Vector3(rel[3], rel[4], rel[5])).normalized()
	var incl := rad_to_deg(acos(clampf(-h.dot(Bodies.moon_pole(tr.t)), -1.0, 1.0)))
	rows.append("LOI-1 | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s, %.1f deg at cutoff; %.1f × %.1f nmi, %.2f deg to the lunar equator | 69:08:20, N81 −2,984.0, +239.0, +105.3; 2,997 ft/s in 246.9 s, −0.79 deg; 168.5 × 60.0 nmi, 12.29 deg" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, gamma, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(flown.x, 2997.0, 15.0, "LOI-1's ΔV")
	assert_almost_eq(loi_n81.y, 239.0, 30.0, "the plane change in it")
	assert_almost_eq(flown.y, 246.9, 10.0, "its burn")
	assert_almost_eq(gamma, -0.79, 0.5, "still descending at the cutoff")
	assert_almost_eq(o.x, 168.5, 3.0, "apolune")
	assert_almost_eq(o.y, 60.0, 3.0, "perilune")
	assert_almost_eq(incl, 12.29, 0.1, "the orbit's plane")

	# LOI-2 two revolutions on: 134.8 ft/s at 73:35:07 into 60.7 x 59.7 nmi
	# (Table 5-II, section 5.5).
	var loi2 := _await_pad("loi2_pad", "circ")
	run(_get_s("72:46:20") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "GO for LOI-2")
	flown = _fly(loi2)
	o = _orbit()
	var t_loi2 := float(burn_log["before"].t)
	rows.append("LOI-2 | GET %s, %.1f ft/s; %.1f × %.1f nmi | 73:35:07, 134.8 ft/s; 60.7 × 59.7 nmi" % [
		_hms(t_loi2), flown.x, o.x, o.y])
	assert_almost_eq(t_loi2, _get_s("73:35:07"), 300.0, "LOI-2 at the perilune LOI-1 left")
	assert_almost_eq(flown.x, 134.8, 3.0, "LOI-2's ΔV")
	assert_almost_eq(o.x, 60.7, 2.5, "apolune")
	assert_almost_eq(o.y, 59.7, 2.5, "perilune")

	# Ten revolutions; the Moon's field takes the orbit to 63.6 x 58.6 nmi
	# by TEI (section 5.5). TEI: the TEI-10 PAD's 89:19:15.67, N81
	# +3,518.6, -151.2, -52.0; flown 3,519 ft/s in 203.7 s (section 5.6).
	var tei := _await_pad("tei_pad", "tei")
	assert_false(tei.is_empty(), "TEI")
	o = _orbit()
	var revs := (float(tei["tig"]) - float(loi["tig"])) / float(rt.dynamics.traj.conic()["period"])
	var tei_n81: Vector3 = tei["dv_lvlh"] / Units.FT
	run(_get_s("88:03:40") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "You have a GO for TEI.")
	flown = _fly(tei)
	rows.append("The lunar orbit before TEI | %.1f × %.1f nmi after %.1f revolutions | 63.6 × 58.6 nmi after 10" % [o.x, o.y, revs])
	rows.append("TEI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s | 89:19:16, N81 +3,518.6, −151.2, −52.0; 3,519 ft/s in 203.7 s" % [
		_hms(float(tei["tig"])), tei_n81.x, tei_n81.y, tei_n81.z, flown.x, flown.y])
	assert_almost_eq(revs, 10.0, 0.3, "ten lunar orbits")
	assert_almost_eq(o.x, 63.6, 1.5, "apolune")
	assert_almost_eq(o.y, 58.6, 1.5, "perilune")
	assert_almost_eq(float(tei["tig"]), _get_s("89:19:16.6"), 30.0, "TEI's time")
	assert_almost_eq(flown.x, 3519.0, 20.0, "TEI's ΔV")
	assert_almost_eq(flown.y, 203.7, 15.0, "its burn")
	run(3600.0)
	assert_eq(sq.phase, "transearth_coast")

	# The transearth midcourse corrections on the RCS: MCC-5, 4.8 ft/s at
	# 103:59:54; MCC-6 and MCC-7 scrubbed, not required (the flight journal).
	var mccs := []
	for id in ["mcc5_pad", "mcc6_pad", "mcc7_pad"]:
		var m := _await_pad(id, "mcc")
		mccs.append(float(m.get("dv", 0.0)) / Units.FT)
		assert_lt(float(m.get("dv", 0.0)) / Units.FT, 6.0, "%s: a trim" % id)
		_fly(m)
	rows.append("Transearth midcourse corrections | MCC-5 %.1f, MCC-6 %.1f, MCC-7 %.1f ft/s | 4.8 ft/s, and none" % mccs)

	# The final entry PAD, 145:11:42: 8.13 N 165.03 W; then P52 before the
	# entry, and GO for pyro arm.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(8.13, -165.03), "N61 uplinked")
	run(_get_s("145:30:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")
	assert_true(run_until(func() -> bool: return rt.dynamics.traj.altitude() < 5.0e6, 3.0 * 3600.0, 60.0), "home")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "GO for Pyro Arm")

	# Entry interface: 146:46:12.8, 36,221 ft/s, 6.50 deg down (Table 5-V),
	# at 20.72 N 176.89 E by the CMC's state then (Table 6.9-III) [derived].
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 3600.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f N %.2f E | 146:46:13, 36,221 ft/s, 6.50 deg down, 20.72 N 176.89 E" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, geo.x, geo.y])
	assert_almost_eq(ei.t, _get_s("146:46:12.8"), 120.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36221.0, 20.0, "its speed")
	assert_almost_eq(ei_gamma, -6.50, 0.2, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(20.72, 176.89)) * Bodies.R_EARTH / Units.NMI, 60.0, "where")

	# The entry on P61 to P67 to 8.13 N 165.03 W: 6.84 g at the peak, with no
	# P65 on the entry PAD; drogues at 146:54:48; down at 147:00:42, 8.10 N
	# 165.01 W by the best estimate, 2.3 nmi from the target (Table 5-V).
	var f := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P64, P67, no P65; 6.84 g" % [str(f["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.2f N %.2f W, %.1f nmi from the target | 147:00:42, 8.10 N 165.01 W, 2.3 nmi from it" % [
		_hms(land), at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 8.")
	assert_almost_eq(rt.dynamics.max_g, 6.84, 0.5, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(land, _get_s("147:00:42"), 180.0, "splashdown's time")
	assert_false(sq.events.any(func(e: Dictionary) -> bool: return str(e["id"]).begins_with("lm_") or e["id"] == "undocking"),
		"no LM, no LM's events")

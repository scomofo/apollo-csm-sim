## Slice 12c (docs/ROADMAP.md, milestone 12): Apollo 16 flies from its data
## alone (data/missions/apollo_16/mission.json), from its parking orbit to
## the landing at Descartes; tests/scenarios/test_apollo_16_return.gd flies
## it home from the surface. TLI, one midcourse correction and LOI put the
## stack in the orbit over the site; Casper flies DOI with Orion docked.
## After the undocking Casper's circularization is held: the gimbal checks
## before it found its SPS's secondary yaw servo loop oscillating, and the
## flight rules wanted all four loops for the burn. Houston waves the
## landing off for three revolutions, almost six hours, while it shows the
## engine can be flown; then Casper separates again and circularizes, and
## Orion flies powered descent on rev 16 on its LGC's own targets, Luminary
## 210's for Apollo 16, from higher and farther out of plane than planned:
## the ground's noun 69 takes out what its state vector had wrong along the
## track, the landing radar's ΔH counts the highlands' height by the LGC's
## terrain model, and the commander redesignates the landing point south
## and flies the last 250 ft in P66 to the spot Orion came down on, about
## six hours late. Each PAD Mission Control's timeline brings is flown as
## the crew flew it: the CSM's on P30 and P40 or P41, the LM's on P63 to
## P66. The flight's figures are the Fidelity table in README.md, each held
## here within set limits of Apollo 16's: the Apollo 16 Mission Report
## (MSC-07230), the AS-511 flight evaluation report (MPR-SAT-FE-72-1), the
## spacecraft operational trajectory (MSC-06016), the Apollo Flight Journal
## and the Apollo Lunar Surface Journal [published].
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


## How far the site lies out of [param tr]'s orbital plane at its time,
## nmi: right of the track positive.
func _out_of_plane(tr: Trajectory) -> float:
	var site := Rtcc.site_at(sq.landing_site(), tr.t).normalized()
	var h := tr.pos().cross(tr.vel()).normalized()
	return -asin(clampf(site.dot(h), -1.0, 1.0)) * sq.landing_site().length() / Units.NMI


func _n81(pad: Dictionary) -> Vector3:
	return pad["dv_lvlh"] / Units.FT


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


## Start the SPS gimbal motor of servo loop [param loop] (Sps.LOOPS):
## START, sprung back to ON.
func _motor(loop: String) -> void:
	Bus.set_value("ctl.sps.gmbl_" + loop, 2)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.sps.gmbl_" + loop, 1)
	run(SimClock.FIXED_DT, false)


## The GPI's yaw through [param seconds]: x half its swing (deg), y how
## often it swings about its mean (Hz), from the first crossing of the mean
## to the last.
func _yaw_swing(seconds: float) -> Vector2:
	var ys := PackedFloat64Array()
	var t0 := SimClock.get_seconds
	while SimClock.get_seconds - t0 < seconds:
		run(SimClock.FIXED_DT, false)
		ys.append(float(Bus.get_value("sps.gpi_y_deg")))
	var lo: float = ys[0]
	var hi: float = ys[0]
	var mean := 0.0
	for y in ys:
		lo = minf(lo, y)
		hi = maxf(hi, y)
		mean += y / ys.size()
	var crossed := PackedFloat64Array()
	for i in range(1, ys.size()):
		var a: float = ys[i - 1] - mean
		var b: float = ys[i] - mean
		if (a < 0.0) != (b < 0.0):
			crossed.append((i - 1 + a / (a - b)) * SimClock.FIXED_DT)
	var hz := 0.0 if crossed.size() < 2 else (crossed.size() - 1) / (2.0 * (crossed[-1] - crossed[0]))
	return Vector2((hi - lo) / 2.0, hz)


func test_apollo_16_flies_its_data_waves_off_and_lands_at_descartes() -> void:
	build("parking_orbit", "apollo_16")
	sq = rt.sequencer
	assert_eq(rt.dynamics.config, "stack")
	assert_true(rt.dynamics.has_lm(), "Orion in the adapter")
	Bus.set_value("ctl.cmc.mode", 0)
	var rows := PackedStringArray()

	# TLI, the IU's own, at the RTCC's TIG: 2:33:36.5 for 341.9 s, 10,389.6
	# ft/s gained (MSC-07230, Table 3-V(a); MPR-SAT-FE-72-1, Table 2-2), C3
	# -1,574,297 m2/s2 at TLI, 10 s on (ibid., Table 4-5); past the Moon
	# 146.7 nmi up at 74:32:22 (MSC-07230, Table 3-V(a)). What the J-2
	# gave: the rocket equation on the propellant it burned.
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
	rows.append("TLI | GET %s, %.0f ft/s in %.1f s, C3 %.0f m²/s²; the pericynthion after it %.1f nmi at %s | 2:33:37, 10,389.6 ft/s in 341.9 s, C3 −1,574,297 m²/s²; 146.7 nmi at 74:32:22" % [
		_hms(ign), j2, cut - ign, c3, p.x, _hms(p.y)])
	assert_almost_eq(ign, _get_s("2:33:36.5"), 30.0, "TLI's ignition")
	assert_almost_eq(cut - ign, 341.9, 5.0, "its burn")
	assert_almost_eq(j2, 10389.6, 100.0, "what the J-2 gave")
	assert_almost_eq(c3, -1574297.0, 20000.0, "C3")
	assert_almost_eq(p.x, 146.7, 10.0, "the pericynthion")
	assert_almost_eq(p.y, _get_s("74:32:22"), 60.0, "and when")

	# Transposition, docking and extraction as the ground takes them at the
	# flight's ejection, 3:59:15. No MCC-1 (Peterson, 9:19:31); MCC-2, the
	# one midcourse correction on the way out: the PAD's 12.6 ft/s at
	# 30:39:00.01, N81 +8.9, -1.1, +8.9 (Apollo Flight Journal, 029:40:50),
	# flown 12.5 ft/s in 2.0 s on the SPS, the pericynthion then 71.7 nmi
	# up at 74:32:07 (MSC-07230, Table 3-V(a)); no MCC-3 or MCC-4.
	var mcc2 := _await_pad("mcc2_pad", "mcc")
	assert_eq(rt.dynamics.config, "csm_lm", "Orion docked since the transposition")
	assert_false(mcc2.is_empty(), "MCC-2")
	var mcc2_n81 := _n81(mcc2)
	var flown := _fly(mcc2)
	p = _pericynthion()
	rows.append("MCC-2 | %.1f ft/s at %s, N81 %+.1f, %+.1f, %+.1f; then %.1f nmi at %s | 12.5 ft/s at 30:39:01, N81 +8.9, −1.1, +8.9; then 71.7 nmi at 74:32:07" % [
		float(mcc2["dv"]) / Units.FT, _hms(float(mcc2["tig"])), mcc2_n81.x, mcc2_n81.y, mcc2_n81.z, p.x, _hms(p.y)])
	assert_almost_eq(float(mcc2["dv"]) / Units.FT, 12.6, 8.0, "MCC-2 a few ft/s")
	assert_almost_eq(p.x, 71.7, 7.0, "the pericynthion after it, off by MSFN's tracking error, and no MCC-4 to trim it")
	assert_almost_eq(p.y, _get_s("74:32:07"), 60.0, "and when")

	# LOI behind the Moon: the final PAD's N81 -2,781.6, -219.6, -256.2 at
	# 74:28:27.22, into 170.0 x 58.3 nmi (Apollo Flight Journal, 073:15:31);
	# flown 2,802.0 ft/s in 374.9 s into 170.3 x 58.1 nmi (MSC-07230, Table
	# 3-V(b)), the orbit 9 deg to the lunar equator over Descartes.
	var loi := _await_pad("loi_pad", "loi")
	assert_false(loi.is_empty(), "LOI")
	var loi_n81 := _n81(loi)
	run(_get_s("74:04:24") - SimClock.get_seconds)
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Go for LOI")
	flown = _fly(loi)
	var o := _orbit(rt.dynamics.traj)
	var incl := _inclination(rt.dynamics.traj)
	rows.append("LOI | GET %s, N81 %+.1f, %+.1f, %+.1f; %.0f ft/s in %.1f s; %.1f × %.1f nmi, %.2f deg to the lunar equator | 74:28:28, N81 −2,781.6, −219.6, −256.2; 2,802.0 ft/s in 374.9 s; 170.3 × 58.1 nmi" % [
		_hms(float(loi["tig"])), loi_n81.x, loi_n81.y, loi_n81.z, flown.x, flown.y, o.x, o.y, incl])
	assert_eq(sq.phase, "lunar_orbit")
	assert_almost_eq(float(loi["tig"]), _get_s("74:28:27.22"), 90.0, "LOI's time")
	assert_almost_eq(flown.x, 2802.0, 100.0, "LOI's ΔV")
	assert_almost_eq(flown.y, 374.9, 30.0, "its burn")
	assert_almost_eq(o.x, 170.3, 4.0, "apolune")
	assert_almost_eq(o.y, 58.1, 3.0, "perilune")
	assert_almost_eq(incl, 9.0, 1.2, "the orbit over Descartes, its approach due west")

	# DOI, the CSM's with Orion docked: the PAD's N81 -205.3, 0, -45.5 at
	# 78:33:44.39 (Apollo Flight Journal, 077:39:43), flown 209.5 ft/s in
	# 24.4 s into 58.5 x 10.9 nmi (MSC-07230, Table 3-V(b)). The RTCC sizes
	# it to bring the orbit over the PDI point on the planned landing pass,
	# rev 13, at the plan's 52,707 ft (Rtcc.plan_doi_docked()), flying it
	# through the Moon's field for the day: PDI planned for 98:34:40.9
	# (MSC-06016, Table 1-I).
	var doi := _await_pad("doi_pad", "doi")
	assert_false(doi.is_empty(), "DOI, docked")
	var doi_n81 := _n81(doi)
	flown = _fly(doi)
	o = _orbit(rt.dynamics.traj)
	rows.append("DOI, Casper with Orion docked | GET %s, N81 %+.1f, %+.1f, %+.1f; %.1f ft/s in %.1f s; %.1f × %.1f nmi; PDI planned for %s | 78:33:45, N81 −205.3, 0, −45.5; 209.5 ft/s in 24.4 s; 58.5 × 10.9 nmi; PDI 98:34:41" % [
		_hms(float(doi["tig"])), doi_n81.x, doi_n81.y, doi_n81.z, flown.x, flown.y, o.x, o.y, _hms(float(doi["hp_get"]))])
	assert_eq(rt.dynamics.config, "csm_lm", "docked through DOI")
	assert_almost_eq(float(doi["tig"]), _get_s("78:33:44.39"), 240.0, "DOI's time")
	assert_almost_eq(flown.x, 209.5, 15.0, "DOI's ΔV")
	assert_almost_eq(o.x, 58.5, 2.0, "apolune")
	assert_almost_eq(o.y, 10.9, 2.5, "perilune")
	assert_almost_eq(float(doi["hp_get"]), _get_s("98:34:40.9"), 240.0, "PDI planned on the landing pass, rev 13")

	# The separation PAD, docked, its N33 96:13:31.00; Casper released Orion
	# at 96:13:33 and backed away below it, 1 ft/s radially down (Apollo
	# Flight Journal, 095:14:13 and 096:13:33 to 096:13:59; the final flight
	# plan, Table 2-9). Here on P41 at the timeline's TIG, 17 s after the
	# undocking.
	var sep := _await_pad("sep_pad", "sep")
	assert_true(bool(sep.get("uplinked", false)), "the separation PAD in the CMC")
	run(_get_s("96:13:33") - SimClock.get_seconds)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	assert_eq(str(Bus.get_value("dock.state")), "free", "undocked")
	assert_eq(sq.phase, "lunar_descent", "Orion on the descent orbit")
	Bus.set_value("ctl.lm.mode", 0)
	var sepf := fly_pad(0, LEAD_S) / Units.FT
	rows.append("The CSM's separation | %.1f ft/s at 96:13:50 on P41, 1.0 radially down | 1.0 ft/s right after the undocking at 96:13:33" % sepf)
	assert_almost_eq(sepf, 1.0, 0.4, "the separation")

	# The PADs for the planned landing pass: Orion's PDI PAD at 96:43:04,
	# its TIG 98:35:04.68; Casper's CIRC PAD at 96:52:28, N81 +68.1, 0,
	# -58.0 at 97:40:17.16 into 67.4 x 51.6 nmi (Apollo Flight Journal).
	var lgc := rt.lgc()
	var lm := rt.dynamics.lm
	var pdi13 := _await_pad("pdi_pad_rev13", "pdi")
	assert_false(pdi13.is_empty(), "the PDI PAD for rev 13")
	var tig13 := float(pdi13["tig"])
	var circ1 := _await_pad("circ_pad", "circ")
	assert_false(circ1.is_empty(), "the first CIRC PAD")
	var circ1_n81 := _n81(circ1)
	assert_almost_eq(float(circ1["tig"]), _get_s("97:40:17.16"), 420.0, "at the flown burn's place in the orbit, near the PAD's TIG")

	# Orion's first P52, at 96:58 on stars 26 (Spica) and 33 (Antares)
	# through the front detent: N05 0.05°, N93 -0.060, +0.139 and -0.018°
	# (MSC-07230, Table 7-I). The platform stood so at undocking, less the
	# drift since (mission.json "lgc": first_p52), and the descent flies on
	# the platform it leaves.
	run(_get_s("96:56:00") - SimClock.get_seconds)
	var p52 := lm_realign([26, 33])
	var n93: Vector3 = p52["torque"]
	rows.append("Orion's first P52 | GET %s on stars 26 and 33: N05 %.3f°, N93 %+.3f, %+.3f and %+.3f° | 96:58: 0.05°; −0.060, +0.139 and −0.018°" % [
		_hms(float(p52["get"])), p52["sad"], n93.x, n93.y, n93.z])
	assert_almost_eq(n93, Vector3(-0.060, 0.139, -0.018), Vector3.ONE * 0.015, "N93 as flown")
	assert_lt(float(p52["sad"]), 0.07, "N05 within the flown")

	# The TVC checks before CIRC, behind the Moon from 97:31:50 (Apollo
	# Flight Journal): SC CONT at SCS on RATE CMD, the primary loops'
	# motors, the PAD's trims, +0.49 and +1.22 deg; then SC CONT at CMC, the
	# THC clockwise and the secondary loops' motors. Setting the yaw trim on
	# loop 2, the yaw gimbal oscillated, "an unstable yaw gimbal Number 2"
	# (097:35:10), limited at 1.0 deg either way at 2.4 Hz about the gimbal's
	# command (MSC-07230, section 14.1.10), the loop's rate feedback open
	# here since DOI (mission.json "failures"). The motors off at 097:39:04,
	# the GPI back to 0, 0 under the CMC first, here, for the burns to come.
	run(_get_s("97:31:50") - SimClock.get_seconds)
	assert_eq(Bus.get_value("sps.rate_open"), "y2", "the secondary yaw loop's rate feedback open")
	var scs: Scs = rt.systems["scs"]
	Bus.set_value("ctl.scs.tvc", 1)
	Bus.set_value("ctl.scs.att_source", 1)
	_motor("p1")
	_motor("y1")
	scs.trim = Vector2(deg_to_rad(0.49), deg_to_rad(1.22))
	run(2.0, false)
	var primary := _yaw_swing(3.0)
	assert_almost_eq(float(Bus.get_value("sps.gpi_y_deg")), 1.22, 0.01, "the primary yaw loop on the trim")
	assert_lt(primary.x, 0.001, "and steady")
	Bus.set_value("ctl.scs.att_source", 0)
	Bus.set_value("ctl.thc_cw", true)
	_motor("p2")
	_motor("y2")
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(2, 2), "the secondary loops drive")
	scs.trim.y = deg_to_rad(1.32)
	run(4.0, false)
	var secondary := _yaw_swing(5.0)
	rows.append("The secondary yaw servo loop | %.2f deg either way at %.2f Hz on the GPI, the primary loop steady | 1.0 deg either way at 2.4 Hz about the command, slightly more at the last check; the primary loop good" % [
		secondary.x, secondary.y])
	assert_almost_eq(secondary.x, 1.0, 0.05, "1 deg either way")
	assert_almost_eq(secondary.y, 2.4, 0.05, "at 2.4 Hz")
	Bus.set_value("ctl.thc_cw", false)
	run(1.0, false)
	assert_almost_eq(Vector2(float(Bus.get_value("sps.gpi_p_deg")), float(Bus.get_value("sps.gpi_y_deg"))), Vector2.ZERO,
		Vector2.ONE * 0.01, "the GPI at 0, 0 under the CMC")
	for m in ["y2", "p2", "y1", "p1"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 0)
	run(SimClock.FIXED_DT, false)
	assert_eq(int(Bus.get_value("sps.motors_on")), 0, "the gimbal motors off")

	# CIRC held: the crew doesn't fly it, the gimbal checks before it having
	# found the SPS's secondary yaw servo loop oscillating, an open in its
	# rate feedback, and the flight rules wanting all four servo loops for
	# the burn (MSC-07230, section 14.1.10). Houston waves the landing off
	# for three revolutions at 98:13:35, PDI then at 104:17:25, 5 h 42 min
	# 44 s after the plan's (ibid., Table 3-I; Apollo Flight Journal).
	run(float(circ1["tig"]) + 60.0 - SimClock.get_seconds)
	assert_almost_eq(_orbit(rt.dynamics.traj).y, 10.9, 3.0, "Casper still on the descent orbit, CIRC held")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("wave_off"), 3600.0, 10.0), "the wave-off")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Anticipate a wave-off")
	var period := float(lm.traj.conic()["period"])
	var tig16 := float(sq.plan["pdi_tig"])
	assert_almost_eq(tig16 - tig13, 3.0 * period, 60.0, "PDI three of Orion's revolutions later")
	assert_false(sq.pads.has("pdi"), "the waved-off PDI PAD no longer to fly")
	rows.append("The wave-off | PDI's TIG moved from %s to %s, three revolutions of %.1f min | 98:35:05 to 104:17:23, three revolutions; called at 98:13:35" % [
		_hms(tig13), _hms(tig16), period / 60.0])
	assert_almost_eq(tig13, _get_s("98:35:04.68"), 240.0, "the rev 13 PDI PAD's TIG")

	# The Go for rev 16, the PADs for it: Orion's PDI PAD at 102:08:14, its
	# TIG 104:17:23.29; Casper's second separation, 1 ft/s radially down at
	# 102:30:00 (Apollo Flight Journal, 102:09:57 and 102:51:33); its second
	# CIRC PAD at 102:11:18, N81 +69.1, 0, -43.5 at 103:21:42.43 into 68.0 x
	# 53.1 nmi; flown 81.6 ft/s in 4.66 s on the primary servo loops
	# (MSC-07230, Tables 3-V(b) and 6-III), 48 s past the apolune: the RTCC
	# here burns each CIRC at that place in the orbit (mission.json
	# "lunar_orbit": loi2_after_apolune_s).
	var pdi16 := _await_pad("pdi_pad", "pdi")
	assert_false(pdi16.is_empty(), "the PDI PAD for rev 16")
	var t_pad := float(sq.timeline_done["pdi_pad"])
	var sep2 := _await_pad("sep_pad2", "sep")
	assert_false(sep2.is_empty(), "the second separation")
	var circ := _await_pad("circ_pad2", "circ")
	assert_false(circ.is_empty(), "the second CIRC PAD")
	assert_eq(str(circ["name"]), "CIRC", "the CSM's own")
	var circ_n81 := _n81(circ)
	# The crew had both PADs: the separation's keyed into P30 for its burn at
	# 102:30 [here as an uplink], then CIRC's.
	assert_true(rt.agc().uplink_maneuver(float(sep2["tig"]), sep2["dv_lvlh"]), "the separation's PAD in P30")
	var sep2f := fly_pad(0, LEAD_S) / Units.FT
	rows.append("The second separation | %.1f ft/s at 102:30:00 on P41, 1.0 radially down | 1 ft/s radially in toward the Moon about 102:30" % sep2f)
	assert_almost_eq(sep2f, 1.0, 0.4, "the second separation")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_circ"), 3600.0, 10.0), "GO for CIRC")
	assert_true(rt.agc().uplink_maneuver(float(circ["tig"]), circ["dv_lvlh"]), "CIRC's PAD in P30")
	# The gimbal checks on the primary loops, the secondary yaw motor
	# started after them (MSC-07230, p. 9-16), the burn on the primary
	# loops under the CMC, the GPI at its null.
	for m in ["p1", "y1", "p2", "y2"]:
		_motor(m)
	assert_eq(Bus.get_value("sps.tvc_loops"), Vector2i(1, 1), "the primary loops drive")
	flown = _fly(circ)
	assert_eq(_yaw_swing(1.0).x, 0.0, "the yaw gimbal steady on loop 1")
	for m in ["y2", "p2", "y1", "p1"]:
		Bus.set_value("ctl.sps.gmbl_" + m, 0)
	o = _orbit(rt.dynamics.traj)
	rows.append("CIRC, held then flown | the first PAD's N81 %+.1f, %+.1f, %+.1f at %s, held; the second's %+.1f, %+.1f, %+.1f at %s, %.1f ft/s; Casper in %.1f × %.1f nmi | the first +68.1, 0, −58.0 at 97:40:17, held; the second +69.1, 0, −43.5 at 103:21:42, 81.6 ft/s; 68.0 × 53.1 nmi" % [
		circ1_n81.x, circ1_n81.y, circ1_n81.z, _hms(float(circ1["tig"])), circ_n81.x, circ_n81.y, circ_n81.z, _hms(float(circ["tig"])),
		flown.x, o.x, o.y])
	assert_almost_eq(float(circ["tig"]), _get_s("103:21:42.43"), 420.0, "at the flown burn's place in the orbit, near the PAD's TIG")
	assert_almost_eq(flown.x, 81.6, 10.0, "CIRC's ΔV")
	assert_almost_eq(o.x, 68.0, 2.0, "Casper's apolune")
	assert_almost_eq(o.y, 53.1, 2.0, "and perilune")

	# Powered descent on Luminary 210's own targets, from the PDI PAD's
	# state vector, 800 ft off along the track. At ignition Orion was 66,500
	# ft up, 13,800 ft higher than planned, and the site 3.56 nmi out of
	# its orbit's plane (MSC-07230, pp. 3-6 and 9-17) [the Moon's field here
	# raises the PDI point less in the three revolutions: simplified]. The
	# ground's noun 69, 800 ft downrange, voiced 100 s after ignition and
	# entered (V21N69) at 1 min 51 s, here as soon as it is voiced. The
	# landing radar's range came good 3 min 59 s after ignition at 48,700 ft
	# of slant range (ibid., p. 7-4 and Table 7-IV).
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
	var xr_pdi := _out_of_plane(lm.traj)
	var seen := {"programs": [], "high": 0.0}
	var landed := run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		if seen.has("dh0") and not seen.has("lr_get"):
			seen["lr_get"] = SimClock.get_seconds - t_pdi
		if lgc.lr_update:
			seen["high"] = maxf(float(seen["high"]), absf(lgc._h - (lm.traj.radius() - site.length() - Dynamics.lm_cm_height("lm"))))
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
	# P64 at 104:26:52, 9 min 27 s after ignition, at 7,200 ft, the
	# automatic guidance taking Orion past where it came down and north of
	# it (mission.json "pdi": site_error_m); the commander redesignated about
	# ten times, 620 ft uprange and 635 ft south in all (the LPD pilot here
	# clicks to the spot), took attitude hold at about 250 ft and P66 at
	# 104:28:42, and Orion came down at 104:29:35 with 1,128 lb of the
	# DPS's usable propellant left, about 102 s of hover (MSC-07230, Table
	# 7-IV, pp. 7-7, 9-18 and section 7.6.2).
	var t_p64 := SimClock.get_seconds
	var h_p64 := lgc._h
	var h_err_p64 := lgc._h - (lm.traj.radius() - site.length() - Dynamics.lm_cm_height("lm"))
	var auto_aim := _aim(lgc)
	var clicks := lpd_pilot(lgc, spot, 250.0 * Units.FT)
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
	rows.append("PDI | the PAD at %s; GET %s, %.0f ft over the site, the site %.1f nmi out of plane | the PAD at 102:08:14; 104:17:25, 66,500 ft (the plan 52,707), 3.56 nmi out of plane" % [
		_hms(t_pad), _hms(t_pdi), h_pdi / Units.FT, xr_pdi])
	rows.append("Noun 69 | %+.0f ft, keyed in %.0f s after PDI | +800 ft downrange, voiced 1:40 after PDI and entered at 1:51" % [float(seen["n69"]), float(seen["n69_after"])])
	rows.append("The landing radar and the terrain model | the altitude good %.0f s after PDI, ΔH %+.0f ft; the LGC's altitude off the truth by %.0f ft at most with the updates, %+.0f ft at P64 | range data good 3:59 after PDI at 48,700 ft of slant range" % [
		float(seen["lr_get"]), float(seen["dh0"]) / Units.FT, float(seen["high"]) / Units.FT, h_err_p64 / Units.FT])
	rows.append("Throttle-down | %.0f s after PDI | 7:29" % float(seen["throttle_down"]))
	rows.append("P64 | GET %s, %.0f s after PDI, at %.0f ft, aiming %.0f ft from where Orion came down; %d LPD clicks | 104:26:52, 9:27 after PDI, at 7,200 ft; about ten redesignations, south" % [
		_hms(t_p64), t_p64 - t_pdi, h_p64 / Units.FT, _apart(auto_aim, spot) / Units.FT, clicks])
	rows.append("The landing | P66 at %s at %.0f ft, %.0f ft off; touchdown %s, %.0f s after PDI, %.0f ft from where Orion came down, %s after the plan's; %.0f lb of the DPS's propellant left | P66 at 104:28:42 at about 250 ft; 104:29:35, 730 s after PDI, 5:42:53 after the plan's 98:46:42; 1,128 lb usable" % [
		_hms(t_p66), h_p66 / Units.FT, off / Units.FT, _hms(t_land), t_land - t_pdi, _apart(lm.landed_pos, spot) / Units.FT,
		_hms(t_land - _get_s("98:46:42.4")), dps_left / Units.LBM])
	assert_almost_eq(t_pad, _get_s("102:08:14"), 60.0, "the PDI PAD for rev 16, two hours ahead")
	assert_almost_eq(t_pdi, _get_s("104:17:25"), 240.0, "PDI's time, three revolutions late")
	assert_between(h_pdi / Units.FT, 50000.0, 70000.0, "PDI's height, between the plan's and the flight's")
	assert_lt(absf(xr_pdi), 4.5, "the site out of plane by a few miles")
	assert_almost_eq(float(seen["n69"]), 800.0, 400.0, "noun 69, the landing site's move downrange")
	assert_almost_eq(float(seen["n69_after"]), 100.3, 2.0, "after throttle-up")
	assert_lt(absf(h_err_p64) / Units.FT, 500.0, "and over the highlands the radar brought the LGC's altitude to the truth")
	assert_almost_eq(float(seen["throttle_down"]), 449.0, 40.0, "the throttle-down")
	assert_eq(seen["programs"], [63, 64], "braking, then the approach")
	assert_almost_eq(t_p64 - t_pdi, 567.0, 40.0, "P64 at 9 min 27 s, the approach's high gate")
	assert_almost_eq(h_p64 / Units.FT, 7200.0, 1500.0, "P64's height")
	assert_almost_eq(h_p66 / Units.FT, 250.0, 30.0, "P66 at 250 ft")
	assert_lt(off / Units.FT, 800.0, "the redesignations brought it near the spot")
	assert_almost_eq(t_land - t_pdi, 730.0, 60.0, "the descent's time")
	assert_almost_eq(t_land, _get_s("104:29:35"), 300.0, "the landing's time, about six hours late")
	assert_almost_eq(t_land - _get_s("98:46:42.4"), _get_s("5:42:53"), 300.0, "after the plan's landing")
	assert_lt(_apart(lm.landed_pos, spot), 30.0, "where Orion came down")
	assert_lt(float(td["vertical_mps"]), 1.0, "under 1 m/s down")
	assert_lt(float(td["horizontal_mps"]), 0.5, "under 0.5 m/s across")
	assert_false(td["hard"])
	assert_between(dps_left / Units.LBM, 500.0, 2000.0, "propellant to spare")
	run(2.0, false)
	assert_eq(sq.phase, "lunar_surface", "on the surface")
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 0)
	for row in rows:
		gut.p("Fidelity: " + row)

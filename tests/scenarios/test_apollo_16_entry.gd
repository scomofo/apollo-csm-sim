## Slice 12c (docs/ROADMAP.md, milestone 12): Apollo 16 home from the
## transearth coast, from the transearth_coast start ten hours after TEI
## (tests/scenarios/test_apollo_16_return.gd flies there from Descartes).
## MCC-5 on the SM RCS; Mattingly's EVA, the cabin vented; MCC-7, a foot
## and a half per second to keep the SM's footprint off Penrhyn; the entry
## PAD, a P52 and the GO for Pyro Arm; then the entry on P61 to P67 to the
## recovery area south of Christmas Island, a day earlier than planned.
## Each PAD is flown as the crew flew it, on P30 and P41. The flight's
## figures are the Fidelity table in README.md, each held here within set
## limits of Apollo 16's: the Apollo 16 Mission Report (MSC-07230) and the
## Apollo Flight Journal [published].
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


func _hms(t: float) -> String:
	return Units.hms(t)


func _get_s(s: String) -> float:
	return MissionSequencer._get_s(s)


func test_apollo_16_comes_home_from_the_transearth_coast() -> void:
	build("transearth_coast", "apollo_16")
	sq = rt.sequencer
	assert_eq(sq.phase, "transearth_coast")
	assert_eq(rt.dynamics.config, "csm", "Casper alone")
	var rows := PackedStringArray()

	# MCC-5 on the SM RCS, the PAD's 3.4 ft/s at 214:34:55.86, N81 +3.4, 0,
	# 0 (Apollo Flight Journal, 213:54:44, its TIG on the updated clock less
	# 24 h 46 min); flown 3.4 ft/s at 214:35:03 (MSC-07230, Table 3-V(c)),
	# the TEI having left the entry 7.44 deg steep. The start's TEI is the
	# RTCC's own, on the corridor: none needed here, or a trim.
	var m5 := _await_pad("mcc5_pad", "mcc")
	var mcc5 := float(m5.get("dv", 0.0)) / Units.FT
	if not m5.is_empty():
		fly_pad(1, LEAD_S)
	rows.append("MCC-5 | %.1f ft/s | 3.4 ft/s at 214:35:03" % mcc5)
	assert_lt(mcc5, 8.0, "MCC-5, a trim")

	# Mattingly's EVA to the SIM bay for the cameras' film: GO for cabin
	# depress at 218:37:31, the cabin vented from 218:39:46 to 220:03:28
	# (MSC-07230, Table 3-I; Apollo Flight Journal).
	assert_false(bool(Bus.get_value("mission.cabin_vented")), "the cabin at pressure")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("eva_start"), 12.0 * 3600.0, 60.0), "the EVA")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you're Go for cabin depress")
	assert_true(bool(Bus.get_value("mission.cabin_vented")), "the cabin vented")
	var eva: float = sq.timeline_done["eva_start"]
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("eva_end"), 3.0 * 3600.0, 60.0), "Mattingly back in")
	assert_false(bool(Bus.get_value("mission.cabin_vented")), "the cabin pressurized again")
	rows.append("Mattingly's EVA | the cabin vented %s to %s | 218:39:46 to 220:03:28" % [_hms(eva), _hms(sq.timeline_done["eva_end"])])
	assert_almost_eq(eva, _get_s("218:39:46"), 1.0, "the EVA's start")
	assert_almost_eq(float(sq.timeline_done["eva_end"]), _get_s("220:03:28"), 1.0, "and its end")

	# MCC-7 on the SM RCS, the PAD's 1.4 ft/s at 262:37:00.26, N81 -1.4, 0,
	# +0.1 (Apollo Flight Journal, 260:56:03), the SM's footprint taken off
	# Penrhyn; flown 1.4 ft/s at 262:37:21 (MSC-07230, Table 3-V(c)).
	var m7 := _await_pad("mcc7_pad", "mcc")
	var mcc7 := float(m7.get("dv", 0.0)) / Units.FT
	if not m7.is_empty():
		fly_pad(1, LEAD_S)
	rows.append("MCC-7 | %.1f ft/s | 1.4 ft/s at 262:37:21" % mcc7)
	assert_lt(mcc7, 8.0, "MCC-7, a trim")

	# GO for Pyro Arm at 264:40:37; the entry PAD at 264:45:53: 0.71 S
	# 156.18 W; then P52 before the entry.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_true(sq.timeline_done.has("go_pyro_arm"), "Go for Pyro Arm")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(-0.71, -156.18), "N61 uplinked")
	run(_get_s("264:50:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")

	# Entry interface: 265:37:31, 36,196.1 ft/s, 6.55 deg down, at 19.87 S
	# 162.13 W (MSC-07230, Table 3-III), 1,204 nmi from the target over the
	# ground [derived].
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 7200.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	var to_go := Bodies.surface_angle(geo, Vector2(-0.71, -156.18)) * Bodies.R_EARTH / Units.NMI
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f S %.2f W, %.0f nmi from the target | 265:37:31, 36,196 ft/s, 6.55 deg down, 19.87 S 162.13 W, 1,204 nmi" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, -geo.x, -geo.y, to_go])
	assert_almost_eq(ei.t, _get_s("265:37:31"), 120.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36196.0, 30.0, "its speed")
	assert_almost_eq(ei_gamma, -6.55, 0.5, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(-19.87, -162.13)) * Bodies.R_EARTH / Units.NMI, 150.0, "where")

	# The entry on P61 to P67 to 0.71 S 156.18 W, 7.1 g at the peak and the
	# landing 13:21 after entry interface on the PAD; down at 265:51:05,
	# 0 deg 42 min S 156 deg 12.8 min W by the onboard computer, 2.1 nmi
	# from the target [derived] ("about 3 miles"), 13:34 after entry
	# interface (MSC-07230, pp. 1-3 and 3-9, Table 3-I; Apollo Flight
	# Journal, 264:45:53).
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 7.1 g on the PAD" % [str(fe["programs"]), rt.dynamics.max_g])
	rows.append("Splashdown | %s, %.0f s after entry interface, %.2f S %.2f W, %.1f nmi from the target | 265:51:05, 814 s after it (the PAD's 801), 0.70 S 156.21 W, 2.1 nmi from it" % [
		_hms(land), land - ei.t, -at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 16.")
	assert_almost_eq(rt.dynamics.max_g, 7.1, 1.5, "the peak load")
	assert_lt(miss, 3.5, "near the target")
	assert_almost_eq(land - ei.t, _get_s("265:51:05") - _get_s("265:37:31"), 60.0, "the entry's time")
	assert_almost_eq(land, _get_s("265:51:05"), 300.0, "splashdown's time, a day earlier than planned")

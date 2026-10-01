## Slice 12b (docs/ROADMAP.md, milestone 12): Apollo 15 home from the
## transearth coast, from the transearth_coast start ten hours after TEI
## (tests/scenarios/test_apollo_15_return.gd flies there from Hadley).
## Worden's EVA, the cabin vented; MCC-7, the one midcourse correction the
## return needed, on the SM RCS; the entry PAD, a P52 and the GO for Pyro
## Arm; then the entry on P61 to P67 to the recovery area north of Hawaii,
## the heaviest command module to come home, on two main parachutes, the
## third failed. Each PAD is flown as the crew flew it, on P30 and P41.
## The flight's figures are the Fidelity table in README.md, each held here
## within set limits of Apollo 15's: the Apollo 15 Mission Report
## (MSC-05161), the retrofire officers' postflight memo (FC54 (71-142)) and
## the Apollo Flight Journal [published].
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


func test_apollo_15_comes_home_from_the_transearth_coast() -> void:
	build("transearth_coast", "apollo_15")
	sq = rt.sequencer
	assert_eq(sq.phase, "transearth_coast")
	assert_eq(rt.dynamics.config, "csm", "Endeavour alone")
	var rows := PackedStringArray()

	# Worden's EVA to the SIM bay for the cameras' film: GO for depress at
	# 241:55:31, the cabin vented from 241:57:12 to 242:36:19 (MSC-05161,
	# Table 3-I; Apollo Flight Journal).
	assert_false(bool(Bus.get_value("mission.cabin_vented")), "the cabin at pressure")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("eva_start"), 12.0 * 3600.0, 60.0), "the EVA")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "you have a Go for depress")
	assert_true(bool(Bus.get_value("mission.cabin_vented")), "the cabin vented")
	var eva: float = sq.timeline_done["eva_start"]
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("eva_end"), 3600.0, 60.0), "Worden back in")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Your seal looks good to us.")
	assert_false(bool(Bus.get_value("mission.cabin_vented")), "the cabin pressurized again")
	rows.append("Worden's EVA | the cabin vented %s to %s | 241:57:12 to 242:36:19" % [_hms(eva), _hms(sq.timeline_done["eva_end"])])
	assert_almost_eq(eva, _get_s("241:57:12"), 1.0, "the EVA's start")
	assert_almost_eq(float(sq.timeline_done["eva_end"]), _get_s("242:36:19"), 1.0, "and its end")

	# MCC-7 on the SM RCS, the PAD's 5.6 ft/s at 291:56:47.90, N81 -5.6,
	# -0, +0.2 (Apollo Flight Journal, 290:35:02); flown 5.6 ft/s in 22.3 s
	# (MSC-05161, Table 3-V(c)), MCC-5 and MCC-6 not needed.
	var m7 := _await_pad("mcc7_pad", "mcc")
	var mcc7 := float(m7.get("dv", 0.0)) / Units.FT
	if not m7.is_empty():
		fly_pad(1, LEAD_S)
	rows.append("MCC-7 | %.1f ft/s | 5.6 ft/s at 291:56:48" % mcc7)
	assert_lt(mcc7, 8.0, "MCC-7, a trim")

	# The entry PAD, 293:55:20: 26.13 N 158.13 W; then P52 before the entry,
	# and GO for Pyro Arm at 294:06:55.
	var ep := _await_pad("entry_pad", "entry")
	assert_false(ep.is_empty(), "the entry PAD")
	assert_eq(Vector2(rt.agc().entry_lat, rt.agc().entry_lng), Vector2(26.13, -158.13), "N61 uplinked")
	run(_get_s("293:57:00") - SimClock.get_seconds)
	Bus.set_value("ctl.cmc.mode", 1)
	realign(3)
	Bus.set_value("ctl.cmc.mode", 0)
	assert_lt(misalignment_deg(), 0.05, "the platform realigned for the entry")
	assert_true(run_until(func() -> bool: return sq.timeline_done.has("go_pyro_arm"), 3600.0, 60.0), "home")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Your Go for Pyro Arm")

	# Entry interface: 294:58:54.7, 36,096.4 ft/s, 6.51 deg down, at 14.23 N
	# 175.02 W (MSC-05161, Table 3-III), 1,189 nmi from the target over the
	# ground [derived].
	var ei := rt.dynamics.traj.clone()
	var down := func(t2: Trajectory) -> bool:
		return t2.altitude() < Rtcc.EI_ALT_M
	ei.coast_until(down, ei.t + 7200.0, 10.0, 0.002)
	var ecef := Bodies.eci_to_earth_fixed([ei.s[0], ei.s[1], ei.s[2]], ei.t)
	var geo := Bodies.fixed_to_geographic(Vector3(ecef[0], ecef[1], ecef[2]))
	var ei_gamma := rad_to_deg(asin(ei.radial_rate() / ei.speed()))
	var to_go := Bodies.surface_angle(geo, Vector2(26.13, -158.13)) * Bodies.R_EARTH / Units.NMI
	rows.append("Entry interface | %s, %.0f ft/s, %.2f deg down, %.2f N %.2f W, %.0f nmi from the target | 294:58:55, 36,096 ft/s, 6.51 deg down, 14.23 N 175.02 W, 1,189 nmi" % [
		_hms(ei.t), ei.speed() / Units.FT, -ei_gamma, geo.x, -geo.y, to_go])
	assert_almost_eq(ei.t, _get_s("294:58:54.7"), 120.0, "entry interface's time")
	assert_almost_eq(ei.speed() / Units.FT, 36096.0, 30.0, "its speed")
	assert_almost_eq(ei_gamma, -6.51, 0.5, "the corridor")
	assert_lt(Bodies.surface_angle(geo, Vector2(14.23, -175.02)) * Bodies.R_EARTH / Units.NMI, 150.0, "where")

	# The entry on P61 to P67 to 26.13 N 158.13 W, 6.2 g at the peak and the
	# landing 13:29 after entry interface on the PAD; down at 295:11:53,
	# 26 deg 07.8 min N 158 deg 08.4 min W, about a mile from the target, 32 s
	# earlier than predicted, on two main parachutes (MSC-05161, pp. 1-4, 3-9
	# and 11-5).
	var deflated := {}
	rt.failures.failed.connect(func(id: String) -> void:
		deflated[id] = [SimClock.get_seconds, float(Bus.get_value("dyn.alt_m"))])
	var fe := fly_entry()
	var miss := float(Bus.get_value("mission.splash_miss_nmi", -1.0))
	var land := sq.event_get("landing")
	var at := sq.geographic()
	rows.append("The entry | programs %s; %.2f g at the peak | P61 to P67; 6.2 g on the PAD" % [str(fe["programs"]), rt.dynamics.max_g])

	# The mains out at 295:07:34; one of them deflated to a fifth of its
	# diameter at about 6,000 ft, 99 s on, and two brought the CM down from
	# there at 37.5 ft/s on average [derived], 36 ft/s at the water on the
	# design's figures against three's 32 (MSC-05161, Table 3-I and section
	# 14.1.9; NASA TN D-7437, Fig. 2). The recovery helicopter Photo saw it
	# streaming at 295:09:54.
	var mains := sq.event_get("main_chutes")
	assert_has(deflated, "els_main", "a main deflated")
	var fail_at: Array = deflated.get("els_main", [0.0, 0.0])
	var rate := float(fail_at[1]) / (land - float(fail_at[0])) / Units.FT
	rows.append("The parachutes | the mains out at %s, one deflated %.0f s on at %.0f ft; two at %.1f ft/s on average from there, %.1f ft/s at the water | 295:07:34; about 99 s on, at about 6,000 ft; 37.5 ft/s on average, 36 ft/s at the water on two by design, 32 on three" % [
		_hms(mains), float(fail_at[0]) - mains, float(fail_at[1]) / Units.FT, rate, rt.dynamics.landed_speed / Units.FT])
	rows.append("Splashdown | %s, %.0f s after entry interface, %.2f N %.2f W, %.1f nmi from the target | 295:11:53, 778 s after it on two main parachutes (the PAD's 809 on three), 26.13 N 158.14 W, about 1 nmi from it" % [
		_hms(land), land - ei.t, at.x, -at.y, miss])
	for row in rows:
		gut.p("Fidelity: " + row)
	assert_eq(sq.phase, "splashdown")
	assert_eq(Bus.get_value("mission.result"), "success")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Welcome home, Apollo 15.")
	assert_almost_eq(rt.dynamics.max_g, 6.2, 1.5, "the peak load")
	assert_lt(miss, 3.0, "near the target")
	assert_almost_eq(float(fail_at[0]) - mains, 99.0, 0.5, "the main failed 99 s after they came out")
	assert_almost_eq(float(fail_at[1]) / Units.FT, 6000.0, 1000.0, "at about 6,000 ft")
	assert_almost_eq(rate, 37.5, 2.5, "two mains' rate of descent")
	assert_almost_eq(rt.dynamics.landed_speed / Units.FT, 36.0, 2.0, "at the water")
	assert_true(sq.timeline_done.get("streaming_main", -1.0) > 0.0, "Photo saw it streaming")
	assert_almost_eq(land - ei.t, _get_s("295:11:53") - _get_s("294:58:54.7"), 60.0, "the entry's time")
	assert_almost_eq(land, _get_s("295:11:53"), 300.0, "splashdown's time")

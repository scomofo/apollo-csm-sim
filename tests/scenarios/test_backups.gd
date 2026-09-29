## Slice 9c's check (docs/ROADMAP.md, milestone 9): with the CMC failed
## (9a), a transearth SPS burn flown on the SCS to the EMS's count comes
## within a set limit of its PAD; and the EMS's scroll follows the CMC's
## entry within its tolerance.
##
## TEI: Apollo 11's, from its start phase. Twenty minutes before TIG the
## crew aligns the GDC to the IMU, and the CMC fails; they take ATT SOURCE
## to SCS, as the malfunction procedure has it, turn to the PAD's burn
## attitude on the FDAI's GDC angles at RATE HIGH, hold it at RATE LOW and
## ATT DEADBAND MIN, set the EMS's ΔV counter to the PAD's ΔVC and press
## THRUST ON at TIG. The SCS holds the attitude on the SPS's gimbal and the
## EMS ends the burn.
##
## The entry: Apollo 11's, the CMC flying it. Before 0.05 G the crew sets
## the EMS's scroll to the entry PAD's VIO and its range to RTGO, and turns
## it to ENTRY.
extends SimTest

## The burn comes within this of its PAD's ΔV: in magnitude, ft/s, and in
## direction, deg [estimated: the EMS's count less the tail-off it can't
## know exactly, and the GDC's drift and the SCS's deadband].
const DV_LIMIT_FT_S := 3.0
const DIR_LIMIT_DEG := 1.0
## The scroll's tolerance on the CM's entry [estimated]: its G reads the
## load along X only, the aerodynamic force off it at the trim angle; its
## velocity leaves out the gravity along the path, which its accelerometer
## can't sense; its range counts down from RTGO by that velocity.
const G_TOLERANCE := 0.06
const V_TOLERANCE := 0.06
const RANGE_LIMIT_NMI := 25.0
## The scroll's velocity is compared above this, ft/s: its scale runs down
## to about here [estimated].
const SCROLL_LOW_FT_S := 10000.0


## Fly the SCS's hand controller toward [param target] (body to the GDC's
## reference, as Imu.gimbal_basis() of the FDAI's angles) until within
## [param within_deg], at RATE [param high]; then release it. Each axis
## off by more than that gets a deflection in proportion to its error, at
## least enough to command a rate past the rate deadband.
func _turn_on_scs(scs: Scs, target: Basis, within_deg: float, high: bool) -> float:
	Bus.set_value("ctl.scs.rate", 1 if high else 0)
	var max_rate := Scs.RATE_HIGH if high else Scs.RATE_LOW
	var least := 1.5 * float(Scs.RATE_DB[1 if high else 0]) / max_rate
	var t0 := SimClock.get_seconds
	while SimClock.get_seconds - t0 < 600.0:
		var e := scs.error_to(target)
		if rad_to_deg(e.length()) < within_deg:
			break
		var rhc := Vector3.ZERO
		for i in 3:
			if rad_to_deg(absf(e[i])) > within_deg / 2.0:
				rhc[i] = signf(e[i]) * clampf(absf(e[i]) / (max_rate * 4.0), least, 1.0)
		Bus.set_value("ctl.rhc", rhc)
		run(0.1, false)
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	run(5.0, false)
	return rad_to_deg(scs.error_to(target).length())


## Set the EMS's display to [param value] on the ΔV/EMS SET rocker: through
## the hard stop to within a step's worth, then the soft stop.
func _ems_set(value: float) -> void:
	var ems: Ems = rt.systems["ems"]
	for hard in [2, 1]:
		var rate := float(Ems.SET_RATE[hard - 1])
		while absf(ems.display() - value) > rate * SimClock.FIXED_DT:
			Bus.set_value("ctl.ems.set", hard * signf(value - ems.display()))
			run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.ems.set", 0)
	run(SimClock.FIXED_DT, false)


func test_a_tei_on_the_scs_ends_on_the_ems_count_within_its_pad() -> void:
	build("tei")
	assert_true(run_until(func() -> bool: return rt.sequencer.pads.has("tei"), 600.0, 10.0), "the TEI PAD")
	var pad: Dictionary = rt.sequencer.pads["tei"]
	gut.p(Rtcc.pad_text(pad))
	assert_true(pad.has("att_deg") and pad.has("dvc"), "the PAD's R, P, Y and ΔVC")
	var tig := float(pad["tig"])
	run(tig - 1200.0 - SimClock.get_seconds)
	# The GDC to the IMU, and the CMC fails.
	var scs: Scs = rt.systems["scs"]
	gut.p("The IMU's platform %.2f deg from REFSMMAT" % rad_to_deg(rt.agc().imu.misalignment().length()))
	Bus.set_value("ctl.scs.gdc_align", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.scs.gdc_align", false)
	assert_true(rt.failures.fail("cmc"), "the CMC fails")
	run(1.0, false)
	assert_eq(str(Bus.get_value("dsky.prog")), "", "its DSKY dark")
	Bus.set_value("ctl.scs.att_source", 1)
	# To the burn attitude on the GDC: fast, then fine.
	var target := Imu.gimbal_basis(pad["att_deg"])
	_turn_on_scs(scs, target, 2.0, true)
	var off := _turn_on_scs(scs, target, 0.05, false)
	gut.p("On the burn attitude to %.2f deg; GDC %s" % [off, str(Bus.get_value("scs.gdc_deg"))])
	assert_lt(off, 0.3, "on the PAD's attitude, within the deadband")
	assert_true(scs.holding, "the SCS holds it")
	# The EMS: ΔVC in, then ΔV.
	Bus.set_value("ctl.ems.function", Ems.Function.DV_SET)
	_ems_set(float(pad["dvc"]) / Units.FT)
	Bus.set_value("ctl.ems.function", Ems.Function.DV)
	assert_almost_eq(float(Bus.get_value("ems.display")), float(pad["dvc"]) / Units.FT, 0.05, "ΔVC on the counter")
	Bus.set_value("ctl.sps.arm_a", true)
	Bus.set_value("ctl.sps.arm_b", true)
	run(tig - SimClock.get_seconds, false)
	# THRUST ON at TIG; the EMS ends it.
	var v0 := rt.dynamics.traj.vel()
	var m0 := float(Bus.get_value("dyn.mass_kg"))
	var sensed := Vector3.ZERO
	Bus.set_value("ctl.sps.thrust_on", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.sps.thrust_on", false)
	assert_true(bool(Bus.get_value("scs.sps_on")), "THRUST ON latched under the EMS's ΔV")
	var peak_gimbal := 0.0
	var t0 := SimClock.get_seconds
	while (bool(Bus.get_value("sps.on", false)) or SimClock.get_seconds - t0 < 2.0) and SimClock.get_seconds - t0 < 600.0:
		run(SimClock.FIXED_DT, false)
		var d: Array = Bus.get_value("dyn.dv_step")
		sensed += Vector3(d[0], d[1], d[2])
		peak_gimbal = maxf(peak_gimbal, (Bus.get_value("sps.gimbal_rad") as Vector2).length())
	run(5.0, false)
	var d2: Array = Bus.get_value("dyn.dv_step")
	sensed += Vector3(d2[0], d2[1], d2[2])
	var burn_s := SimClock.get_seconds - t0
	assert_true(bool(Bus.get_value("ems.thrust_off")), "the EMS's thrust-off")
	assert_false(bool(Bus.get_value("scs.sps_on")))
	# The PAD's ΔV, inertial at TIG as the ground planned it.
	var at: Trajectory = (pad["state"] as Trajectory).clone()
	at.coast_to(tig)
	var want := Trajectory.lvlh_basis(at.pos(), at.vel()) * (pad["dv_lvlh"] as Vector3)
	want = AgcCore.external_dv_vg(at.pos(), at.vel(), want, m0,
		float(SpacecraftData.section("sps")["thrust_n"])).normalized() * want.length()
	var mag := (sensed.length() - want.length()) / Units.FT
	var ang := rad_to_deg(sensed.angle_to(want))
	gut.p("TEI on the SCS: %.1f ft/s (PAD %.1f), %.2f deg off its direction, %.0f s; EMS %+.1f; gimbal peak %.2f deg" % [
		sensed.length() / Units.FT, want.length() / Units.FT, ang, burn_s, float(Bus.get_value("ems.display")),
		rad_to_deg(peak_gimbal)])
	assert_lt(absf(mag), DV_LIMIT_FT_S, "the ΔV within %.0f ft/s of the PAD's" % DV_LIMIT_FT_S)
	assert_lt(ang, DIR_LIMIT_DEG, "and within %.0f° of its direction" % DIR_LIMIT_DEG)
	assert_gt(rt.dynamics.traj.vel().distance_to(v0), 900.0, "on its way home")


func test_the_ems_scroll_follows_the_cmcs_entry() -> void:
	build("entry")
	# The entry PAD, as the start phase's uplink planned it.
	var target := rt.sequencer.entry_target()
	var pad := Rtcc.plan_entry(rt.dynamics.traj, target.x, target.y)
	gut.p(Rtcc.pad_text(pad))
	var ems: Ems = rt.systems["ems"]
	Bus.set_value("ctl.ems.function", Ems.Function.V0_SET)
	var v0 := float(pad["vio"]) / Units.FT
	for hard in [2, 1]:
		var rate := float(Ems.SCROLL_RATE[hard - 1])
		while absf(ems.v - v0) > rate * SimClock.FIXED_DT:
			Bus.set_value("ctl.ems.set", hard * signf(v0 - ems.v))
			run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.ems.set", 0)
	Bus.set_value("ctl.ems.function", Ems.Function.RNG_SET)
	_ems_set(float(pad["rtgo"]))
	Bus.set_value("ctl.ems.function", Ems.Function.ENTRY)
	assert_almost_eq(ems.v, v0, 1.0, "the scroll at VIO")
	assert_almost_eq(ems.range_nmi, float(pad["rtgo"]), 0.05, "the range at RTGO")
	var seen := {"g05_truth": -1.0, "g05_ems": -1.0, "worst_v": 0.0, "worst_g": 0.0, "corridor": ""}
	var at_05g := {}
	var sample := func() -> void:
		var t := SimClock.get_seconds
		var gee := rt.dynamics.g_load
		if seen["g05_truth"] < 0.0 and gee >= Ems.G05:
			seen["g05_truth"] = t
		if seen["g05_ems"] < 0.0 and ems.lamp_05g:
			seen["g05_ems"] = t
			at_05g["v"] = rt.dynamics.traj.speed() / Units.FT
		var speed := rt.dynamics.traj.speed() / Units.FT
		if ems.entry_s > 0.0 and gee > 0.2 and speed > SCROLL_LOW_FT_S:
			seen["worst_v"] = maxf(float(seen["worst_v"]), absf(ems.v - speed) / speed)
			seen["worst_g"] = maxf(float(seen["worst_g"]), absf(ems.g - gee) / gee)
		if seen["corridor"] == "" and (ems.corridor_up or ems.corridor_down):
			seen["corridor"] = "%s %.1f s after 0.05 G" % ["LIFT UP" if ems.corridor_up else "LIFT DOWN", ems.entry_s]
	var r := fly_entry(3.0 * 3600.0, sample, 0.2)
	gut.p("EMS: 0.05 G %.1f s after the CM's (%.0f ft/s there, VIO %.0f); worst V %.1f %%, G %.1f %% off; corridor %s; range at the end %.1f nmi; %d scroll points" % [
		float(seen["g05_ems"]) - float(seen["g05_truth"]), at_05g.get("v", 0.0), v0, 100.0 * seen["worst_v"],
		100.0 * seen["worst_g"], seen["corridor"], ems.range_nmi, ems.trace.size()])
	assert_eq(r["programs"].slice(0, 3), [61, 62, 63], "the CMC flew it")
	assert_between(float(seen["g05_ems"]) - float(seen["g05_truth"]), 0.5, 2.0, "0.05 G a second after the CM reached it")
	assert_almost_eq(float(at_05g.get("v", 0.0)), v0, 30.0, "the scroll starts at the CM's speed")
	assert_string_contains(str(seen["corridor"]), "LIFT UP", "Apollo 11's entry, steeper than the overshoot boundary")
	assert_lt(float(seen["worst_g"]), G_TOLERANCE, "the scroll's G within %.0f %% of the CM's load" % (100.0 * G_TOLERANCE))
	assert_lt(float(seen["worst_v"]), V_TOLERANCE, "its velocity within %.0f %% of the CM's" % (100.0 * V_TOLERANCE))
	assert_lt(absf(ems.range_nmi), RANGE_LIMIT_NMI, "its range down to the splashdown")
	assert_gt(ems.trace.size(), 100, "the scroll's trace")

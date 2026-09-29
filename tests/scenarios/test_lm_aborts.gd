## Slice 9e's check (docs/ROADMAP.md, milestone 9): the LM's aborts from
## the powered descent. Aborts from P63 and from P66 at 500 ft each reach
## an orbit, and from it the rendezvous docks.
##
## Fifteen minutes before PDI the ground uplinks the LGC's state vectors,
## Eagle's and Columbia's, with the PDI PAD's abort TPIs, as Apollo 11's
## had them: 105:12:30 for an abort in the first 10 minutes, 107:11:30
## after. Three minutes into P63, with Eagle still ahead of Columbia, the
## crew press ABORT: P70 throttles the descent engine up and flies it into
## an orbit whose high apolune lets Eagle fall behind Columbia for the
## early TPI. In P66 at 500 ft, the descent engine's helium regulator
## fails (the failure catalog's dps_he_reg), DES REG lights with the
## master alarm and the engine's thrust dies away, and the crew press ABORT
## STAGE: P71 fires the ascent engine from the staged LM into an orbit for
## the late TPI. From each, five minutes after insertion the timeline
## uplinks the CSI PAD for the abort's TPI, and the crew fly the
## rendezvous (SimTest.fly_rendezvous()) to docking. A checkpoint in P70
## flies on to the same insertion.
extends SimTest

var _before_pdi := ""


func before_all() -> void:
	build("lunar_descent")
	run_until(func() -> bool: return rt.sequencer.pads.has("pdi"), 600.0, 1.0)
	gut.p(str(Bus.get_value("mission.pad_text")))
	_before_pdi = JSON.stringify(rt.snapshot())


## Restore the checkpoint before PDI and fly P63 to ignition, as
## tests/scenarios/test_landing.gd does.
func _to_ignition() -> Lgc:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_before_pdi)), "")
	var lgc := rt.lgc()
	keys("V37E63E", lgc)
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	keys("P", lgc)
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(maxf(lgc.pdi_tig - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	keys("P", lgc)
	return lgc


## How far Columbia leads Eagle along its orbit, degrees.
func _lead_deg() -> float:
	var l := rt.dynamics.lm.traj
	var c := rt.dynamics.traj
	var h := c.pos().cross(c.vel()).normalized()
	return rad_to_deg(l.pos().angle_to(c.pos())) * signf(l.pos().cross(c.pos()).dot(h))


## Press a pushbutton for a fifth of a second.
func _press(ch: String) -> void:
	Bus.set_value(ch, true)
	run(0.2, false)
	Bus.set_value(ch, false)


## Fly on to insertion; then PRO out of the abort program, the engine
## disarmed and the DAP free. Returns the orbit's perilune and apolune over
## the landing site's radius, nmi.
func _to_insertion(lgc: Lgc) -> Vector2:
	assert_true(run_until(func() -> bool: return rt.sequencer.event_get("lm_insertion") >= 0.0, 900.0, 1.0, false),
		"insertion")
	assert_eq(lgc.step_name, "post", "V16N85 at cutoff")
	var c: Dictionary = rt.dynamics.lm.traj.conic()
	var site := rt.sequencer.landing_site().length()
	keys("P", lgc)
	assert_eq(lgc.program, 0, "PRO: P00")
	Bus.set_value("ctl.lm.engine_arm", 0)
	Bus.set_value("ctl.lm.mode", 0)
	return Vector2(float(c["rp"]) - site, float(c["ra"]) - site) / Units.NMI


## From insertion, the CSI PAD five minutes on, for the abort's TPI, and
## the rendezvous to docking.
func _rendezvous_from_the_abort(tpi_want: float) -> Dictionary:
	assert_true(run_until(func() -> bool: return rt.sequencer.pads.has("csi"), 600.0, 1.0), "the CSI PAD")
	var pad: Dictionary = rt.sequencer.pads["csi"]
	assert_almost_eq(float(pad["tpi_get"]), tpi_want, 0.01, "TPI at the PDI PAD's time for the abort")
	var r := fly_rendezvous(pad)
	gut.p("CSI %.1f ft/s (PAD %.1f), CDH %.1f ft/s, ΔH %.1f nmi, TPI %s (PAD %s) %.1f ft/s, midcourses %.1f ft/s; docked at %s: %s" % [
		r["csi"] / Units.FT, float(pad["dv"]) / Units.FT, r["cdh"] / Units.FT, r["dh"] / Units.NMI,
		Units.hms(r["tpi_tig"]), Units.hms(float(pad["tpi_get"])), r["tpi"] / Units.FT, r["tpm"] / Units.FT,
		Units.hms(SimClock.get_seconds), Docking.describe(r["contact"])])
	assert_true(r["braked"], "braked to station-keeping")
	assert_true(r["probe"], "the probe met the drogue")
	assert_true(r["contact"].get("captured", false), "within the capture limits")
	assert_eq(str(Bus.get_value("dock.state")), "docked")
	# The coelliptic flight is two to three times the nominal rendezvous's
	# 45 min: CDH's ΔH, from the LGC's own model of the field, a mile off
	# the ground's, moves TPI by ten minutes and more.
	assert_almost_eq(float(r["tpi_tig"]), tpi_want, 1200.0, "TPI within 20 min of the plan")
	return r


func test_an_abort_in_p63_reaches_an_orbit_and_the_rendezvous_docks() -> void:
	var lgc := _to_ignition()
	var t_ig := lgc.pdi_tig
	var seen := {}
	run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		return SimClock.get_seconds >= t_ig + 180.0, 400.0, 1.0, false)
	var lead := _lead_deg()
	assert_lt(lead, 0.0, "Eagle ahead of Columbia")
	_press("ctl.lm.abort")
	assert_eq(lgc.program, 70, "ABORT: P70")
	assert_eq(rt.sequencer.phase, "lunar_ascent")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "abort")
	assert_eq(lgc.abort_tpi, float(rt.sequencer.plan["abort_tpi_early"]), "the early TPI")
	var ra_want := float(lgc.ascent_targets["ra"]) - lgc.ascent_base
	var t_abort := SimClock.get_seconds
	run(5.0, false)
	assert_almost_eq(float(Bus.get_value("lm.dps.throttle_pct")), 100.0, 1.0, "the descent engine at full thrust")
	var orbit := _to_insertion(lgc)
	gut.p("ABORT at PDI+%.0f s, %.0f m up, Columbia %.2f° behind: P70 to insertion in %.0f s, %.1f x %.1f nmi (targeted apolune %.1f), the DPS left %.0f kg" % [
		t_abort - t_ig, lm_agl(), -lead, rt.sequencer.event_get("lm_insertion") - t_abort, orbit.x, orbit.y,
		ra_want / Units.NMI, float(Bus.get_value("lm.dps.prop_kg"))])
	assert_eq(rt.dynamics.lm.config, "lm", "on the descent engine")
	assert_eq(int(Bus.get_value("lm.aps.ignitions")), 0)
	assert_between(orbit.x, 8.0, 11.0, "perilune near 60,000 ft")
	assert_almost_eq(orbit.y, ra_want / Units.NMI, 3.0, "the apolune the phasing asks for")
	assert_gt(orbit.y, 60.0, "above Columbia's, to fall behind it")
	var c := rt.dynamics.traj
	var l := rt.dynamics.lm.traj
	assert_lt(rad_to_deg(c.pos().cross(c.vel()).angle_to(l.pos().cross(l.vel()))), 0.2, "in Columbia's plane")
	_rendezvous_from_the_abort(float(rt.sequencer.plan["abort_tpi_early"]))


func test_a_des_reg_in_p66_brings_abort_stage_at_500_ft_and_the_rendezvous_docks() -> void:
	var lgc := _to_ignition()
	var t_ig := lgc.pdi_tig
	var seen := {}
	assert_true(run_until(func() -> bool:
		permit_lr_updates(lgc, seen)
		return lgc.program == 64 and lm_agl() < 200.0, 900.0, 1.0, false), "P64 below 200 m")
	Bus.set_value("ctl.lm.mode", 1)
	# A click in a restart's hold (Apollo 11's program alarms) is lost:
	# again until P66 takes it.
	for _i in 10:
		if lgc.program == 66:
			break
		rod_click(-1)
		run(0.5, false)
	assert_eq(lgc.program, 66, "P66")
	while lm_agl() > 190.0:
		fly_by_hand(lgc)
	assert_false(bool(Bus.get_value("lm.cw.des_reg")), "DES REG dark")
	assert_true(rt.failures.fail("dps_he_reg"))
	while not bool(Bus.get_value("lm.cw.des_reg")) and lm_agl() > 152.4:
		fly_by_hand(lgc)
	var light_agl := lm_agl()
	assert_true(bool(Bus.get_value("lm.cw.des_reg")), "DES REG")
	assert_true(bool(Bus.get_value("lm.cw.master_alarm")), "the master alarm")
	while lm_agl() > 152.4:
		fly_by_hand(lgc)
	Bus.set_value("ctl.lm.rhc", Vector3.ZERO)
	var abort_agl := lm_agl()
	var lead := _lead_deg()
	var t_abort := SimClock.get_seconds
	_press("ctl.lm.stage")
	Bus.set_value("ctl.lm.mode", 2)
	assert_eq(lgc.program, 71, "ABORT STAGE: P71")
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "staged")
	assert_eq(lgc.abort_tpi, float(rt.sequencer.plan["abort_tpi_late"]), "the late TPI")
	var ra_want := float(lgc.ascent_targets["ra"]) - lgc.ascent_base
	run(2.0, false)
	assert_true(bool(Bus.get_value("lm.aps.on")), "the ascent engine lit, armed by ABORT STAGE at ENG ARM DES")
	var low := {"agl": abort_agl}
	var check := func() -> bool:
		low["agl"] = minf(low["agl"], lm_agl())
		return rt.dynamics.lm.landed or rt.sequencer.event_get("lm_insertion") >= 0.0
	run_until(check, 900.0, 1.0, false)
	assert_false(rt.dynamics.lm.landed, "clear of the ground")
	var orbit := _to_insertion(lgc)
	gut.p("DES REG at %.0f ft, ABORT STAGE at %.0f ft (PDI+%.0f s), Columbia %.2f° ahead: P71 to insertion in %.0f s, no lower than %.0f ft, %.1f x %.1f nmi (targeted apolune %.1f), the APS left %.0f kg" % [
		light_agl / Units.FT, abort_agl / Units.FT, t_abort - t_ig, lead, rt.sequencer.event_get("lm_insertion") - t_abort,
		low["agl"] / Units.FT, orbit.x, orbit.y, ra_want / Units.NMI, float(Bus.get_value("lm.aps.prop_kg"))])
	assert_almost_eq(abort_agl / Units.FT, 500.0, 20.0, "at 500 ft")
	assert_between(orbit.x, 8.0, 11.0, "perilune near 60,000 ft")
	assert_almost_eq(orbit.y, ra_want / Units.NMI, 3.0, "the apolune the phasing asks for")
	assert_gt(float(Bus.get_value("lm.aps.prop_kg")), 0.0, "the APS not dry")
	_rendezvous_from_the_abort(float(rt.sequencer.plan["abort_tpi_late"]))


func test_a_checkpoint_in_p70_flies_on_to_the_same_insertion() -> void:
	var lgc := _to_ignition()
	run(lgc.pdi_tig + 180.0 - SimClock.get_seconds, false)
	_press("ctl.lm.abort")
	run(60.0, false)
	var text := JSON.stringify(rt.snapshot())
	var first := _to_insertion(lgc)
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	assert_eq(rt.lgc().program, 70)
	var again := _to_insertion(rt.lgc())
	gut.p("P70 restored: %.3f x %.3f nmi against %.3f x %.3f" % [again.x, again.y, first.x, first.y])
	assert_almost_eq(again, first, Vector2.ONE * 0.05, "the same orbit")

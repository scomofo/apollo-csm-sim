## Slice 3d's check (docs/ROADMAP.md, milestone 3): Eagle lifts off from
## Tranquility Base at the time the RTCC gives, and the LGC's P12 flies it
## to insertion into a 9 x 45 nmi orbit in Columbia's plane, with Columbia
## leading by the insertion phase angle (mission.json "ascent").
##
## In lunar orbit the LM undocks and is set down at the landing site,
## facing 20° off the CSM's track (the landing itself is slice 3c's
## test). The crew request the ascent PAD, select P12, PRO through the
## liftoff time (N33) and the targets (N76), and set LGC MODE AUTO. At
## V99, TIG-5 s, they stage (ABORT STAGE), arm the ascent engine and PRO,
## as Aldrin did. The LGC's platform (slice 11a) is aligned for them 33 min
## before the liftoff, as Apollo 11's last P57 was, and drifts on.
extends SimTest

## The LM's heading off the CSM's track on the surface, degrees.
const YAW := 20.0

var _surface := ""


func before_all() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	set_lm_down(YAW)
	run(60.0)
	_surface = JSON.stringify(rt.snapshot())


## Restore the LM on the surface and request the ascent PAD.
func _pad() -> Dictionary:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_surface)), "")
	return rt.sequencer.request_pad("ascent")


## The CSM's lead over the LM in its orbit, degrees.
func _phase() -> float:
	var n := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()
	var l := rt.dynamics.lm.traj.pos().normalized()
	var c := rt.dynamics.traj.pos().normalized()
	return rad_to_deg(atan2(l.cross(c).dot(n), l.dot(c)))


## The LM's orbit: {"ha", "hp"} above the landing site, m, and the angle
## between its plane and the CSM's, degrees.
func _orbit() -> Dictionary:
	var c := rt.dynamics.lm.traj.conic()
	var site_r := rt.sequencer.landing_site().length()
	var h: Vector3 = c["h"]
	var n := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()
	return {"ha": float(c["ra"]) - site_r, "hp": float(c["rp"]) - site_r, "plane": rad_to_deg(h.normalized().angle_to(n))}


## Select P12 and fly it to V99: PRO at N33 and N76, LGC MODE AUTO. At
## TIG-5 s the crew stage, arm the ascent engine and PRO.
func _to_liftoff(pad: Dictionary) -> Lgc:
	var lgc := rt.lgc()
	keys("V37E12E", lgc)
	assert_eq(lgc.program, 12, "P12")
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], ["06", "33"], "V06N33: the liftoff time")
	assert_eq(lgc.noun_values(33), [pad["tig"], pad["tig"], pad["tig"]])
	keys("P", lgc)
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], ["06", "76"], "V06N76: the targets")
	keys("P", lgc)
	Bus.set_value("ctl.lm.mode", 2)
	run(maxf(float(pad["tig"]) - 12.0 - SimClock.get_seconds, 0.0))
	assert_true(run_until(func() -> bool: return lgc.step_name == "v99", 20.0, 1.0, false), "V99 at TIG-5 s")
	assert_eq(float(Bus.get_value("lm.guid.next_event_get_s")), float(pad["tig"]), "the clock lands on TIG")
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	Bus.set_value("ctl.lm.engine_arm", 1)
	keys("P", lgc)
	return lgc


func test_the_rtcc_times_the_liftoff_for_the_rendezvous() -> void:
	var pad := _pad()
	var now := SimClock.get_seconds
	gut.p(str(Bus.get_value("mission.pad_text")))
	assert_eq(str(pad.get("name", "")), "ASCENT")
	var period := float(rt.dynamics.traj.conic()["period"])
	assert_between(float(pad["tig"]), now + 600.0, now + 600.0 + period, "the first window ten minutes out or later")
	assert_almost_eq(float(pad["phase_deg"]), 16.4, 0.01, "Columbia 16.4° ahead at insertion")
	assert_between(float(pad["burn_s"]), 400.0, 460.0, "about seven minutes to insertion (Apollo 11: 7 min 15 s)")
	assert_almost_eq(float(pad["vh"]) / Units.FT, 5535.0, 3.0, "N76: 5,535 ft/s")
	assert_almost_eq(float(pad["hdot"]) / Units.FT, 32.0, 0.01, "and 32 ft/s up")
	assert_almost_eq(float(pad["hp"]) / Units.NMI, 9.0, 0.5, "9 nmi perilune")
	assert_almost_eq(float(pad["ha"]) / Units.NMI, 45.0, 1.0, "45 nmi apolune")
	assert_lt(absf(float(pad["xrng"])), 2000.0, "the site near Columbia's plane")
	assert_between(float(pad["prop_kg"]), 2000.0, float(SpacecraftData.section("aps")["propellant_kg"]), "the ascent engine's propellant")
	# The ground's uplink to the LGC: the LM where it sits, the CSM, the
	# landing site and the liftoff time.
	var lgc := rt.lgc()
	assert_eq(lgc.tig_load, float(pad["tig"]), "N33")
	assert_not_null(lgc.csm_nav, "the CSM's state vector")
	assert_lt((lgc.nav.pos() - rt.dynamics.lm.traj.pos()).length(), 1.0, "the LM's")
	assert_almost_eq(lgc.landing_site.length(), rt.sequencer.landing_site().length(), 1.0, "the landing site")
	assert_true(Bus.get_value("lm.dsky.lamp.uplink_acty"), "UPLINK ACTY")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "your ascent PAD")


func test_p12_needs_the_surface_and_the_csm() -> void:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_surface)), "")
	var lgc := rt.lgc()
	keys("V37E12E", lgc)
	assert_eq(lgc.program, 0, "no CSM state vector yet")
	assert_true(Bus.get_value("lm.dsky.lamp.prog"), "PROG: alarm")
	assert_eq(lgc.alarm_code, 1520)


func test_p12_flies_eagle_to_insertion() -> void:
	var pad := _pad()
	var lgc := _to_liftoff(pad)
	var n74: Array = lgc.noun_values(74)
	assert_almost_eq(float(n74[1]), -YAW, 0.5, "N74: the yaw after the vertical rise, back to Columbia's track")
	assert_between(float(n74[2]), 40.0, 65.0, "and the pitch over")
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "staged")
	var seen := {"steps": [], "rise_s": 0.0, "rise_h": 0.0, "rate": 0.0}
	var tig := float(pad["tig"])
	var watch := func() -> bool:
		if SimClock.get_seconds - tig > 30.0:
			seen["rate"] = maxf(seen["rate"], rad_to_deg(rt.dynamics.lm.attitude.omega.length()))
		if not lgc.step_name in seen["steps"]:
			seen["steps"].append(lgc.step_name)
			if lgc.step_name == "tailoff":
				seen["cutoff"] = SimClock.get_seconds
			if lgc.step_name == "ascent":
				seen["rise_s"] = SimClock.get_seconds - tig
				seen["rise_h"] = lgc.current_traj().radius() - lgc.ascent_base
				seen["rise_yaw"] = lgc.noun_values(74)[1]
		return lgc.step_name == "post"
	# Second by second to the steering's hold; then finer, for the tail-off
	# lasts under a second.
	var held := run_until(func() -> bool:
		watch.call()
		return lgc.step_name in ["hold", "tailoff", "post"], 600.0, 1.0, false)
	assert_true(held, "the steering held for the cutoff")
	var inserted := run_until(watch, 60.0, 0.05, false)
	assert_true(inserted, "cutoff")
	var tr := rt.dynamics.lm.traj
	var up := tr.pos().normalized()
	var o := _orbit()
	var n := rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized()
	var vh := tr.vel().dot(n.cross(up).normalized())
	var t_ins := SimClock.get_seconds - tig
	var left := float(Bus.get_value("lm.aps.prop_kg"))
	var liftoff := float(Bus.get_value("mission.event.lm_liftoff"))
	gut.p("Liftoff %.1f s after TIG, vertical rise %.1f s to %.0f m; cutoff %.1f s after liftoff; at the end of the tail-off %.0f ft, %.1f ft/s up, %.1f ft/s across; %.2f x %.2f nmi above the site, %.3f° from Columbia's plane, Columbia %.2f° ahead; %.0f kg of APS propellant left" % [
		liftoff - tig, seen["rise_s"], seen["rise_h"], float(seen["cutoff"]) - liftoff, (tr.radius() - lgc.ascent_base) / Units.FT,
		tr.radial_rate() / Units.FT, vh / Units.FT, o["hp"] / Units.NMI, o["ha"] / Units.NMI, o["plane"], _phase(), left])
	assert_between(liftoff - tig, 0.0, 2.0, "liftoff as the engine comes up")
	assert_eq(seen["steps"], ["ignition", "vertical", "ascent", "hold", "tailoff", "post"])
	assert_between(float(seen["rise_s"]), 5.0, 15.0, "a vertical rise of some ten seconds")
	assert_between(float(seen["rise_h"]), 20.0, 150.0, "clear of the descent stage")
	assert_lt(float(seen["rate"]), 1.0, "a steady ride after the pitchover (deg/s)")
	# Windows down at insertion: the thrust along the track, +Z toward the
	# surface and +Y to the right of the track.
	var b := Basis(rt.dynamics.lm.attitude.q)
	assert_lt(rad_to_deg(b.z.angle_to(-up)), 5.0, "+Z down")
	assert_lt(rad_to_deg(b.y.angle_to(-rt.dynamics.traj.pos().cross(rt.dynamics.traj.vel()).normalized())), 1.0, "+Y to the right")
	assert_between(t_ins, 400.0, 460.0, "about seven minutes (Apollo 11: 7 min 15 s)")
	assert_almost_eq(t_ins, float(pad["insertion_get"]) - tig, 3.0, "when the RTCC predicted")
	# Within the target orbit's limits: 60,000 ft and 32 ft/s up where the
	# LGC has Eagle, which its guidance flies to; 9 x 45 nmi, in Columbia's
	# plane. The platform, drifting since the P57 33 min before liftoff,
	# turns the thrust and the LGC's measure of it alike: the truth is off
	# the LGC's by at most the misalignment's angle of the velocity gained,
	# and of the half of it the burn has flown on (Apollo 11's P52 after
	# insertion torqued 0.15°) [published: MSC-00171, Table 9.6-I].
	var nav := lgc.current_traj()
	var mis := lgc.imu.misalignment().length()
	var h_lgc := nav.radius() - lgc.ascent_base
	gut.p("The LGC has Eagle at %.0f ft, %.2f ft/s up; the platform %.3f° off" % [h_lgc / Units.FT, nav.radial_rate() / Units.FT, rad_to_deg(mis)])
	assert_almost_eq(h_lgc / Units.FT, 60000.0, 500.0, "insertion at 60,000 ft")
	assert_almost_eq(nav.radial_rate() / Units.FT, 32.0, 3.0, "climbing at 32 ft/s")
	assert_between(rad_to_deg(mis), 0.01, 0.2, "the platform off by its drift since the P57")
	assert_lt(absf(tr.radius() - lgc.ascent_base - h_lgc), mis * vh * t_ins / 2.0, "the height, off by what the platform makes of it")
	assert_lt(absf(tr.radial_rate() - nav.radial_rate()), mis * vh, "and the climb")
	assert_almost_eq(float(o["hp"]) / Units.NMI, 9.0, 0.5, "perilune 9 nmi")
	assert_almost_eq(float(o["ha"]) / Units.NMI, 45.0, 1.0, "apolune 45 nmi")
	assert_lt(float(o["plane"]), 0.05, "in Columbia's plane")
	assert_almost_eq(_phase(), float(rt.mission.section("ascent")["insertion_phase_deg"]), 0.3, "Columbia ahead as planned")
	assert_gt(left, 0.0, "propellant to spare")
	var n85: Array = lgc.noun_values(85)
	assert_lt(Vector3(n85[0], n85[1], n85[2]).length(), 1.0, "V16N85: residuals under 1 m/s")
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], ["16", "85"])
	assert_true(Bus.has_channel("mission.event.lm_liftoff"))
	run(2.0, false)
	assert_true(Bus.has_channel("mission.event.lm_insertion"), "Houston calls the insertion")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "in orbit")
	keys("P", lgc)
	assert_eq(lgc.program, 0, "P00")
	assert_eq(float(Bus.get_value("lm.aps.thrust_n")), 0.0, "the ascent engine off")
	var q: Quaternion = rt.dynamics.lm.attitude.q
	run(10.0, false)
	assert_lt(rad_to_deg(rt.dynamics.lm.attitude.q.angle_to(q)), 0.5, "holding the attitude it inserted in")


func test_a_checkpoint_mid_ascent_flies_on_to_the_same_insertion() -> void:
	var pad := _pad()
	var lgc := _to_liftoff(pad)
	run(float(pad["tig"]) + 200.0 - SimClock.get_seconds, false)
	assert_eq(lgc.step_name, "ascent")
	var text := JSON.stringify(rt.snapshot())
	assert_true(run_until(func() -> bool: return lgc.step_name == "post", 400.0, 1.0, false), "cutoff")
	var t1 := SimClock.get_seconds
	var o1 := _orbit()
	build("")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(lgc.program, 12)
	assert_eq(lgc.step_name, "ascent")
	assert_eq([Bus.get_value("lm.dsky.verb"), Bus.get_value("lm.dsky.noun")], ["16", "94"], "V16N94")
	assert_true(run_until(func() -> bool: return lgc.step_name == "post", 400.0, 1.0, false), "cutoff after the restore")
	var o2 := _orbit()
	gut.p("Uninterrupted: %.1f x %.1f m; restored: %.1f x %.1f m; cutoff %.2f s apart" % [
		o1["hp"], o1["ha"], o2["hp"], o2["ha"], SimClock.get_seconds - t1])
	assert_almost_eq(SimClock.get_seconds, t1, 1.0, "the same cutoff")
	assert_almost_eq(float(o2["ha"]), float(o1["ha"]), 50.0, "the same apolune")
	assert_almost_eq(float(o2["hp"]), float(o1["hp"]), 50.0, "and perilune")

## Slice 4d: the CMC navigates on its own. P23's star-horizon marks on the
## way home, from a TEI flown on a misaligned platform, and P37's
## corrections from the state they leave keep the entry corridor with no
## uplink; P22's landmark marks in lunar orbit; and the dialogue of each on
## the DSKY.
extends SimTest

## The crew's error laying a star on a horizon, deg (RMS) [estimated: some
## 10 arc seconds].
const NAV_MARK_ERR_DEG := 0.003

var _rng := RandomNumberGenerator.new()


## The CMC's state vector's error against truth now: position (m) and
## velocity (m/s), Earth-relative.
func _nav_error() -> Vector2:
	var a := rt.dynamics.traj.earth_state()
	var n := rt.agc().nav.clone()
	n.coast_to(rt.dynamics.traj.t)
	var b := n.earth_state()
	return Vector2(Vector3(a[0] - b[0], a[1] - b[1], a[2] - b[2]).length(),
		Vector3(a[3] - b[3], a[4] - b[4], a[5] - b[5]).length())


## Up to [param n] stars 15 to 50 deg from [param body]'s horizon as the
## CSM sees it now, their marks' directions well apart.
func _stars_for(body: String, n: int) -> Array:
	var tr := rt.dynamics.traj
	var out := []
	var dirs := []
	for c in Stars.codes():
		var m := NavFilter.star_horizon(tr, Stars.direction(c), body)
		if m.is_empty():
			continue
		var q := rad_to_deg(float(m["q"]))
		if q < 15.0 or q > 50.0:
			continue
		var b: PackedFloat64Array = m["b"]
		var g := Vector3(b[0], b[1], b[2]).normalized()
		var apart := true
		for d in dirs:
			if absf(g.dot(d)) > 0.8:
				apart = false
		if apart:
			out.append(c)
			dirs.append(g)
		if out.size() >= n:
			break
	return out


## The true vacuum perigee's altitude, km.
func _true_perigee_km() -> float:
	var er := Rtcc.earth_return(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	return (float(er["rp"]) - Bodies.R_EARTH) / 1000.0


func test_p23_on_the_dsky() -> void:
	build("transearth_coast")
	var agc := rt.agc()
	run(3600.0)
	# The CMC's state 50 km off the way the mark sees best: across the
	# line of sight to the Earth, toward the star.
	var star: int = _stars_for("earth", 1)[0]
	var b: PackedFloat64Array = NavFilter.star_horizon(agc.nav, Stars.direction(star), "earth")["b"]
	var off := Vector3(b[0], b[1], b[2]).normalized() * 50000.0
	for i in 3:
		agc.nav.s[i] += off[i]
	var before := _nav_error()
	keys("V37E23E")
	assert_eq(agc.program, 23, "P23")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun"), Bus.get_value("dsky.flash")], ["05", "70", true], "V05N70")
	# Codes it won't take: no such star, a landmark, no such horizon.
	keys("V21E77E")
	assert_true(agc.dsky.lamps["opr_err"], "star 77: OPR ERR")
	keys("R")
	keys("V22E1E")
	assert_true(agc.dsky.lamps["opr_err"], "a landmark: OPR ERR")
	keys("R")
	keys("V23E3E")
	assert_true(agc.dsky.lamps["opr_err"], "horizon 3: OPR ERR")
	keys("R")
	# A star behind the Earth, or out of the trunnion's reach: alarm 00404.
	var far := 0
	for c in Stars.codes():
		var m := NavFilter.star_horizon(rt.dynamics.traj, Stars.direction(c), "earth")
		if m.is_empty() or rad_to_deg(float(m["q"])) > Optics.TRUNNION_MAX_DEG + 5.0:
			far = c
			break
	assert_gt(far, 0, "a star the sextant can't lay on the horizon")
	keys("V21E%dE" % far)
	keys("V23E1EP")
	assert_eq(agc.alarm_code, 404, "alarm 00404")
	assert_eq(agc.step_name, "n70", "still at N70")
	keys("R")
	# A good one: the sighting attitude, the maneuver, V51.
	keys("V21E%dE" % star)
	keys("P")
	assert_eq(agc.step_name, "v50n18", "V50N18")
	var los := Basis(agc.auto_target) * Optics.landmark_line()
	var h: Vector3 = NavFilter.star_horizon(agc.current_traj(), Stars.direction(star), "earth")["horizon"]
	assert_almost_eq(rad_to_deg(los.angle_to(h)), 0.0, 1e-3, "the landmark line on the horizon under the star")
	Bus.set_value("ctl.cmc.mode", 2)
	keys("P")
	assert_eq(agc.step_name, "maneuver", "the auto maneuver")
	assert_true(run_until(func() -> bool: return agc.step_name == "mark", 900.0, 1.0, false), "V51")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.flash")], ["51", true], "V51 flashing")
	assert_true(bool(Bus.get_value("guid.optics.cmd")), "the CMC drives the optics to the star")
	run(10.0, false)
	var star_body := Basis(rt.dynamics.attitude.q).inverse() * Stars.direction(star)
	assert_lt(rad_to_deg(optics().line_of_sight().angle_to(star_body)), 1.0, "the star in the sextant")
	# A mark laid 0.1 deg off: V32 drops it.
	superimpose(star, "earth", 0.1)
	mark()
	assert_eq(agc.step_name, "n49", "V06N49")
	var bad: PackedFloat64Array = agc.sight_pending["dx"]
	assert_gt(Vector3(bad[0], bad[1], bad[2]).length(), 1000.0, "a bad mark moves it kilometres")
	var s_before := agc.nav.s.duplicate()
	keys("V32E")
	assert_eq(agc.step_name, "mark", "V32: mark again")
	assert_true(agc.sight_pending.is_empty(), "the bad mark dropped")
	assert_eq(agc.nav.s[0], s_before[0], "the state vector as it was")
	# A good mark, taken in.
	superimpose(star, "earth")
	mark()
	keys("P")
	assert_eq(agc.step_name, "n70", "back to N70")
	assert_eq(int(Bus.get_value("guid.nav_marks")), 1, "one mark taken in")
	var after := _nav_error()
	gut.p("CMC error %.1f km -> %.1f km" % [before.x / 1000.0, after.x / 1000.0])
	assert_lt(after.x, before.x / 2.0, "the mark brought the state vector nearer the truth")
	# V67: the filter's RMS errors, less than it started from; V93 and a
	# load start it again.
	keys("V67E")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun")], ["06", "99"], "V06N99")
	assert_lt(agc._rms_shown.x, NavFilter.POS_RMS_M, "the mark narrowed the position's RMS")
	keys("V21E+%dE" % int(20000.0 / Units.FT))
	assert_true(agc.nav_filter.stale, "a load starts the filter again")
	assert_almost_eq(agc.nav_filter.pos_rms, 20000.0, 1.0)
	keys("K")
	assert_eq(Bus.get_value("dsky.noun"), "70", "KEY REL: back to P23's N70")
	keys("V37E00E")
	assert_eq(int(Bus.get_value("guid.nav_marks")), 0)


## A P23 session as the crew flies it: P23, marks on [param per_body] stars
## on the Moon's horizon and as many on the Earth's, each laid to within
## the crew's error; P00, and CMC MODE FREE to drift on.
func _session(per_body: int) -> void:
	keys("V37E23E")
	for horizon in [2, 1]:
		for c in _stars_for("moon" if horizon == 2 else "earth", per_body):
			p23_mark(c, horizon, _rng.randfn(0.0, NAV_MARK_ERR_DEG))
	keys("V37E00E")
	Bus.set_value("ctl.cmc.mode", 0)


## Sessions every [param every_h] hours after TEI (GET [param t_tei]), from
## [param from_h] to [param to_h].
func _sessions(t_tei: float, from_h: float, to_h: float, every_h: float) -> void:
	var h := from_h
	while h <= to_h + 1e-6:
		run(t_tei + h * 3600.0 - SimClock.get_seconds)
		_session(3)
		var e := _nav_error()
		var r := NavFilter.rms(rt.agc().nav_filter.p)
		gut.p("%4.1f h after TEI: CMC error %.1f km %.3f m/s; filter RMS %.1f km %.3f m/s" % [
			(SimClock.get_seconds - t_tei) / 3600.0, e.x / 1000.0, e.y, r.x / 1000.0, r.y])
		h += every_h


## The vacuum perigee (km) truth would reach after the correction the RTCC's
## targeting works out from state vector [param nav] for TIG [param tig],
## flown on truth.
func _perigee_after(nav: Trajectory, tig: float) -> float:
	var t_max := tig + Agc.P37_SEARCH_S
	var probe := nav.clone()
	probe.coast_to(tig, 60.0)
	var er := Rtcc.earth_return(probe, t_max)
	var target: float = signf(float(er["f"])) * (Bodies.R_EARTH + Agc.P37_PERIGEE_ALT_M)
	var pad := Rtcc.plan_mcc(nav.clone(), rt.dynamics.mass, tig, "earth", target, t_max)
	var tr := rt.dynamics.traj.clone()
	tr.coast_to(tig, 60.0)
	Rtcc.simulate_sps_burn(tr, rt.dynamics.mass, pad["dv_lvlh"])
	return (float(Rtcc.earth_return(tr, t_max)["rp"]) - Bodies.R_EARTH) / 1000.0


func test_p23_marks_keep_the_entry_corridor_without_an_uplink() -> void:
	_rng.seed = 23
	build("lunar_orbit")
	Bus.set_value("ctl.seq.lm_jett", true)
	run(1.0, false)
	var agc := rt.agc()
	# TEI flown on a platform half a degree off (no P52 before it), which
	# no longer drifts.
	agc.imu.drift = Vector3.ZERO
	agc.imu.torque(Vector3(1.0, -1.0, 1.0).normalized() * deg_to_rad(0.5))
	assert_false(rt.sequencer.request_pad("tei").is_empty(), "the TEI PAD")
	fly_pad(0)
	var t_tei := SimClock.get_seconds
	var uplinked := agc.nav_uplink_get
	# No word from the ground from here on.
	Bus.set_value("ctl.cmc.up_tlm", false)
	var unmarked := agc.nav.clone()
	var p0 := _true_perigee_km()
	var er := Rtcc.earth_return(agc.nav.clone(), SimClock.get_seconds + 5.0 * 86400.0)
	var believed := (float(er["rp"]) - Bodies.R_EARTH) / 1000.0
	var e0 := _nav_error()
	gut.p("after TEI: vacuum perigee %.1f km, the CMC's %.1f km; its error %.2f km %.2f m/s" % [
		p0, believed, e0.x / 1000.0, e0.y])
	assert_gt(absf(p0 - 37.5), 100.0, "the TEI left the CSM far outside the corridor")
	assert_gt(e0.y, 5.0, "and the platform's half degree left the state vector metres per second off")
	# P23 every 4 h, then P37.
	_sessions(t_tei, 10.0, 38.0, 4.0)
	var tig := SimClock.get_seconds + agc.P37_LEAD_S
	var p_unmarked := _perigee_after(unmarked, ceilf(tig / 60.0) * 60.0)
	var dv1 := p37()
	var used1 := fly_stored(1)
	var p1 := _true_perigee_km()
	gut.p("P37 #1 at %.1f h: %.2f m/s (flew %.2f) -> vacuum perigee %.1f km; unmarked P37's %.1f km" % [
		(SimClock.get_seconds - t_tei) / 3600.0, dv1.length(), used1, p1, p_unmarked])
	assert_false(p_unmarked >= 25.0 and p_unmarked <= 50.0, "P37 from the unmarked state misses the corridor")
	# More marks as the Earth nears, and P37 again.
	var t_ei := float(Rtcc.earth_return(rt.dynamics.traj.clone(), SimClock.get_seconds + 5.0 * 86400.0)["t"])
	var last_h := (t_ei - t_tei) / 3600.0 - 8.0
	_sessions(t_tei, (SimClock.get_seconds - t_tei) / 3600.0 + 2.0, last_h, 4.0)
	var dv2 := p37()
	var used2 := 0.0
	if agc.maneuver_valid:
		used2 = fly_stored(1)
	var p2 := _true_perigee_km()
	gut.p("P37 #2 at %.1f h: %.2f m/s (flew %.2f) -> vacuum perigee %.1f km" % [
		(SimClock.get_seconds - t_tei) / 3600.0, dv2.length(), used2, p2])
	assert_between(p2, 25.0, 50.0, "the entry corridor, on the CMC's own navigation")
	assert_eq(agc.nav_uplink_get, uplinked, "no state vector uplinked since TEI")
	assert_lt(dv1.length() + dv2.length(), 10.0, "small corrections")


func test_p22_landmark_marks_correct_the_lunar_orbit_state() -> void:
	_rng.seed = 22
	build("lunar_orbit")
	run(1.0, false)
	var agc := rt.agc()
	agc.imu.drift = Vector3.ZERO
	keys("V37E22E")
	assert_eq(agc.step_name, "n89", "V06N89: the landmark")
	var lla: Array = agc.noun_values(89)
	assert_almost_eq(float(lla[0]), 0.674, 0.01, "the landing site's latitude")
	assert_almost_eq(float(lla[1]) * 2.0, 23.473, 0.01, "and its longitude, halved")
	keys("P")
	assert_eq(agc.step_name, "v50n18", "V50N18: the attitude for the pass")
	assert_gt(agc.sight_pass, SimClock.get_seconds, "the next pass")
	Bus.set_value("ctl.cmc.mode", 2)
	keys("P")
	assert_true(run_until(func() -> bool: return agc.step_name == "mark", 900.0, 1.0, false), "V51")
	# As the CSM comes up on it, the landmark comes into the sextant's
	# reach, and the CMC drives the optics to it.
	var seen := func() -> bool:
		var los: Vector3 = NavFilter.landmark_los(rt.dynamics.traj, agc.sight_landmark_mf)["los"]
		return Optics.angles_for(Basis(rt.dynamics.attitude.q).inverse() * los).y < Optics.TRUNNION_MAX_DEG - 5.0
	assert_true(run_until(seen, agc.sight_pass - SimClock.get_seconds, 5.0), "the landmark in the sextant's reach")
	assert_true(bool(Bus.get_value("guid.optics.cmd")), "the CMC drives the optics to it")
	# The CMC's state 2 km further along the orbit than the CSM is (its
	# model of the Moon's field has moved it some way off already).
	var ahead := rt.dynamics.traj.clone()
	ahead.coast_to(ahead.t + 2000.0 / ahead.speed())
	agc.nav.set_state_d(agc.nav.primary, rt.dynamics.traj.t, ahead.s)
	var before := _nav_error()
	for k in 5:
		centre_landmark(_rng.randfn(0.0, 0.01))
		mark()
		assert_eq(agc.step_name, "n49", "V06N49")
		keys("P")
		assert_eq(agc.step_name, "mark", "V51 for the next")
		Bus.set_value("ctl.optics.mode", 1)
		run(20.0, false)
	var after := _nav_error()
	gut.p("P22, five marks: CMC error %.2f km %.3f m/s -> %.3f km %.3f m/s" % [before.x / 1000.0, before.y,
		after.x / 1000.0, after.y])
	assert_gt(before.x, 2000.0, "kilometres off at the pass")
	assert_lt(after.x, 500.0, "the landmark brought the state vector near the truth")
	assert_lt(after.y, before.y / 2.0, "and its velocity")
	keys("V37E00E")
	assert_eq(Bus.get_value("guid.landmark_mf"), Vector3.ZERO, "no landmark out of P22")

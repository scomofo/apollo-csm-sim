## Slice 11d (docs/ROADMAP.md, milestone 11): Luminary 099's P20 apart from
## a flight, Eagle trailing Columbia by 8 km on its orbit. The filter's
## update is a Kalman filter's, in Joseph form, and its covariance coasts
## on the state vector's transition. V67 shows W's root sum squares and
## loads it anew, per axis; V93 gives it up; V80, V81 and V95 choose the
## state vector the marks move. After R61's turn R21 designates the radar
## and it locks on (V50N72); a mark whose change passes RMAX shows V06N49,
## where V32 drops the rest of the mark and marks again, PRO takes it and
## V34 ends P20; the marks take the error out of the ground's state vector
## for Columbia; V95 reads them without weighing them in. R23 is the lock-on
## by hand: the crew slew the antenna onto Columbia, peaking SIGNAL
## STRENGTH, lock on in AUTO TRACK and give the radar to the LGC. R21
## alarms 00503 when Columbia isn't where the state vectors put it. Apollo
## 11's rendezvous on P20 is tests/scenarios/test_rendezvous.gd.
extends SimTest

## Eagle behind Columbia on its orbit, m.
const TRAIL_M := 8000.0

var _free := ""


func before_all() -> void:
	build("lunar_orbit")
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)
	run(2.0, false)
	var cm := rt.dynamics.traj
	var lm := rt.dynamics.lm
	var n := cm.pos().cross(cm.vel()).normalized()
	var a := TRAIL_M / cm.pos().length()
	lm.traj.set_state(cm.primary, cm.t, cm.pos().rotated(n, -a), cm.vel().rotated(n, -a))
	# Moved at once through the docking port's plane: not a contact.
	rt.dynamics._arm_contact()
	var lgc := rt.lgc()
	lgc.imu.misalign(lgc.imu.refsmmat, Vector3.ZERO)
	lgc.init_nav(lm.traj)
	lgc.uplink_csm_state(cm)
	Bus.set_value("ctl.lm.mode", 2)
	run(3.0, false)
	_free = JSON.stringify(rt.snapshot())


func _restore() -> Lgc:
	build("")
	assert_eq(rt.restore(JSON.parse_string(_free)), "")
	return rt.lgc()


func _shows(vn: Array, what: String) -> void:
	assert_eq([rt.lgc().dsky.verb, rt.lgc().dsky.noun], vn, what)


## Eagle turned to [param q] and held there in AUTO.
func _hold(q: Quaternion) -> void:
	var lm := rt.dynamics.lm
	var lgc := rt.lgc()
	lm.attitude.q = q
	lm.attitude.omega = Vector3.ZERO
	Bus.set_value("lm.dyn.att_q", q)
	Bus.set_value("lm.dyn.omega", Vector3.ZERO)
	lgc.hold_q = lgc.imu.attitude(q)
	lgc.auto_active = false
	run(1.0, false)


## Eagle's attitude with its +Z axis [param off_deg] off the line of sight
## to Columbia, about its X axis.
func _off_columbia(off_deg: float) -> Quaternion:
	var lm := rt.dynamics.lm
	var los := Rendezvous.rel_pos(lm.traj, rt.dynamics.traj).normalized()
	return (LgcRendezvousNav._tracking_attitude(lm.attitude.q, los) * Quaternion(Vector3.RIGHT, deg_to_rad(off_deg))).normalized()


## The ground's state vector for Columbia moved [param ahead] m along its
## orbit, [param up] m up and [param side] m along its orbit's normal.
func _uplink_csm_off(ahead: float, up: float, side: float = 0.0) -> void:
	var cm := rt.dynamics.traj.clone()
	var n := cm.pos().cross(cm.vel()).normalized()
	cm.set_state(cm.primary, cm.t, cm.pos() + cm.vel().normalized() * ahead + cm.pos().normalized() * up + n * side,
		cm.vel())
	rt.lgc().uplink_csm_state(cm)


## Columbia's direction in Eagle's body axes, as the radar's angles.
func _columbia_angles() -> Vector2:
	var att := Basis(rt.dynamics.lm.attitude.q)
	return RendezvousRadar.angles_of(att.inverse() * Rendezvous.rel_pos(rt.dynamics.lm.traj, rt.dynamics.traj).normalized())


func test_the_filter_weighs_a_measurement_by_its_variance() -> void:
	var e := PackedFloat64Array()
	e.resize(RendezvousFilter.N * RendezvousFilter.N)
	var sd := [100.0, 100.0, 100.0, 1.0, 1.0, 1.0, 0.01, 0.01]
	for i in RendezvousFilter.N:
		e[i * RendezvousFilter.N + i] = sd[i] * sd[i]
	# A range along X: 50 m more than predicted, its variance 25 m².
	var b := PackedFloat64Array()
	b.resize(RendezvousFilter.N)
	b[0] = 1.0
	var u := RendezvousFilter.update(e, b, 50.0, 25.0)
	var k := 1e4 / (1e4 + 25.0)
	var dx: PackedFloat64Array = u["dx"]
	var out: PackedFloat64Array = u["e"]
	assert_almost_eq(dx[0], 50.0 * k, 1e-9, "the change: the gain on the residual")
	assert_almost_eq(dx[1], 0.0, 1e-12, "none where the measurement doesn't reach")
	assert_almost_eq(out[0], 1e4 * 25.0 / (1e4 + 25.0), 1e-9, "the variance along it: the scalar Kalman filter's")
	assert_almost_eq(out[9], 1e4, 1e-9, "across it, unchanged")
	# A shaft angle: its gradient through the position across the line of
	# sight and the bias, 8 km out; the update stays symmetric.
	b.fill(0.0)
	b[1] = 1.0
	b[6] = 8000.0
	u = RendezvousFilter.update(out, b, 12.0, 8000.0 * 8000.0 * 2e-6)
	out = u["e"]
	for i in RendezvousFilter.N:
		for j in RendezvousFilter.N:
			assert_almost_eq(out[i * RendezvousFilter.N + j], out[j * RendezvousFilter.N + i], 1e-9, "E symmetric")
	assert_lt(out[9], 1e4, "Y's variance down")
	assert_lt(out[6 * RendezvousFilter.N + 6], 1e-4, "and the shaft bias's")
	assert_lt(out[1 * RendezvousFilter.N + 6], 0.0, "the two now correlated: the residual either's")


func test_the_covariance_coasts_on_the_state_vector() -> void:
	var lgc := _restore()
	var f := RendezvousFilter.new()
	var tr := lgc.nav.clone()
	f.init(tr, 100.0, 1.0, 0.01)
	assert_almost_eq(f.rss().x, 100.0 * sqrt(3.0), 1e-3, "N99's R1: the three axes' root sum square")
	assert_almost_eq(f.rss().z, 0.01 * sqrt(2.0), 1e-8, "R3: the two biases'")
	var later := tr.clone()
	later.coast_to(tr.t + 60.0)
	f.carry(later)
	# 1 m/s on each axis is 60 m after a minute, less what the Moon's pull
	# on a 2-hour orbit bends of it.
	var p := f.e[0] + f.e[9] + f.e[18]
	assert_almost_eq(p, 3.0 * (1e4 + 3600.0), 0.03 * 3.0 * (1e4 + 3600.0), "the position's variance grown by the velocity's")
	assert_almost_eq(f.e[54], 1e-4, 1e-12, "the biases' constant")
	assert_eq(f.anchor.t, later.t, "anchored at the state vector's time")


func test_v67_shows_w_and_loads_it_anew_and_the_verbs_choose_the_state_vector() -> void:
	var lgc := _restore()
	var d := SpacecraftData.section("rendezvous_navigation")
	keys("V67E", lgc)
	_shows(["06", "99"], "V06N99")
	var n99: Array = lgc.noun_values(99)
	assert_almost_eq(float(n99[0]), float(d["wrendpos_m"]) * sqrt(3.0), 0.01, "R1: WRENDPOS's root sum square over three axes")
	assert_almost_eq(float(n99[1]), float(d["wrendvel_mps"]) * sqrt(3.0), 1e-4, "R2: WRENDVEL's")
	assert_almost_eq(float(n99[2]), float(d["wbias_rad"]) * sqrt(2.0), 1e-6, "R3: WSHAFT's and WTRUN's")
	# V34 leaves W as it was.
	keys("V25N99E+02000E+00020E+00005E", lgc)
	keys("V34E", lgc)
	assert_almost_eq(lgc.p20.w_pos, float(d["wrendpos_m"]), 0.01, "V34: the load dropped")
	# The load for CDH as Apollo 11's crew had it: 2,000 ft, 2 ft/s and 5
	# mrad, per axis [published: MSC CF-R-69-23].
	keys("V67E", lgc)
	keys("V25N99E+02000E+00020E+00005E", lgc)
	n99 = lgc.noun_values(99)
	assert_almost_eq(float(n99[0]), 2000.0 * Units.FT, 0.01, "R1 loaded")
	assert_almost_eq(float(n99[1]), 2.0 * Units.FT, 1e-4, "R2")
	assert_almost_eq(float(n99[2]), 0.005, 1e-6, "R3")
	keys("P", lgc)
	assert_eq(lgc.p20.priority, "", "PRO: the display answered")
	assert_almost_eq(lgc.p20.w_pos, 2000.0 * Units.FT, 0.01, "WRENDPOS the load")
	assert_almost_eq(lgc.p20.w_vel, 2.0 * Units.FT, 1e-4, "WRENDVEL")
	assert_almost_eq(lgc.p20.w_bias, 0.005, 1e-6, "WSHAFT and WTRUN")
	assert_false(lgc.p20.rendw, "W given up: the next mark starts it from the load")
	lgc.p20.rendw = true
	keys("V93E", lgc)
	assert_false(lgc.p20.rendw, "V93: W given up")
	for vu in [[95, "none"], [81, "csm"], [80, "lm"]]:
		keys("V%dE" % vu[0], lgc)
		assert_eq(Bus.get_value("lm.guid.rr_update"), vu[1], "V%d" % vu[0])


func test_p20_locks_on_and_its_marks_take_the_error_out_of_columbias_state_vector() -> void:
	var lgc := _restore()
	var d := SpacecraftData.section("rendezvous_navigation")
	# The ground has Columbia 1.5 km ahead of where it is, and 100 m high.
	_uplink_csm_off(1500.0, 100.0)
	var err0 := lgc_rel_error()
	_hold(_off_columbia(60.0))
	Bus.set_value("ctl.lm.rr_mode", 0)
	keys("V37E20E", lgc)
	assert_eq(lgc.program, 20, "P20")
	assert_eq(lgc.p20.phase, "r61", "R61: +Z 60° off the line of sight")
	_shows(["50", "18"], "V50N18: the turn")
	keys("P", lgc)
	var t0 := SimClock.get_seconds
	assert_true(run_until(func() -> bool: return lgc.p20.phase == "n72", 300.0, 1.0, false), "R21 designated it and it locked on")
	_shows(["50", "72"], "V50N72 at the lock-on")
	var n72: Array = lgc.noun_values(72)
	var at := _columbia_angles()
	assert_almost_eq(wrapf(float(n72[1]) - rad_to_deg(at.x), -180.0, 180.0), 0.0, 1.0, "N72: the shaft, on Columbia")
	assert_almost_eq(wrapf(float(n72[0]) + rad_to_deg(at.y), -180.0, 180.0), 0.0, 1.0, "and the trunnion (360° less it)")
	var lock_s := SimClock.get_seconds - t0
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.p20.priority == "n49", 60.0, 1.0, false), "the first mark's V06N49")
	_shows(["06", "49"], "V06N49")
	var n49: Array = lgc.noun_values(49)
	assert_gt(float(n49[0]), float(d["rmax_m"]), "ΔR past RMAX")
	assert_eq(int(n49[2]), 1, "source 1: the range")
	# V32: the rest of the mark dropped, and a mark again at once.
	keys("V32E", lgc)
	run(1.0, false)
	assert_eq(lgc.p20.priority, "n49", "N49 again, from the mark taken again")
	assert_eq(lgc.p20.marks, 0, "none counted")
	keys("P", lgc)
	lm_crew()
	assert_true(run_until(func() -> bool: return lgc.p20.marks >= 6, 600.0, 10.0), "six marks")
	var err := lgc_rel_error()
	gut.p("Locked on %.0f s after the turn's PRO; the first N49 %.0f m; after %d marks the LGC has Columbia %.1f m and %.3f m/s off (%.0f m at the uplink), N99 %.0f m" % [
		lock_s, float(n49[0]), lgc.p20.marks, err, lgc_rel_v_error(), err0, lgc.p20.filter.rss().x])
	assert_lt(err, 100.0, "the marks took the error out")
	assert_lt(err, 3.0 * lgc.p20.filter.rss().x, "within the filter's own 3 sigma")
	# V95: marks read, none weighed in.
	keys("V95E", lgc)
	var m := lgc.p20.marks
	run(150.0)
	assert_eq(lgc.p20.marks, m, "V95: none weighed in")
	# V34 at N49 ends P20: P00. The marks moved Eagle's state vector to
	# fit the ground's error in Columbia's; both anew, Columbia's 1.5 km
	# short along the line of sight.
	SimClock.remove_ticker(_lm_crew_tick)
	keys("V80E", lgc)
	lgc.init_nav(rt.dynamics.lm.traj)
	_uplink_csm_off(-1500.0, 0.0)
	assert_true(run_until(func() -> bool: return lgc.p20.priority == "n49", 120.0, 1.0), "N49 on the next mark")
	keys("V34E", lgc)
	assert_false(lgc.p20.running(), "V34: P20 ended")
	assert_eq(lgc.program, 0, "P00")


func test_by_hand_the_crew_slew_onto_columbia_lock_on_and_give_the_radar_to_the_lgc() -> void:
	var lgc := _restore()
	# Eagle's +Z 10° off Columbia, held.
	var lm := rt.dynamics.lm
	_hold(_off_columbia(10.0))
	Bus.set_value("ctl.lm.rr_mode", 2)
	run(1.0, false)
	keys("V37E20E", lgc)
	_shows(["50", "25"], "V50N25: RNDZ RADAR isn't at LGC")
	assert_eq(float(lgc.noun_values(25)[0]), 201.0, "00201")
	keys("E", lgc)
	_shows(["50", "25"], "R23: V50N25 00205")
	assert_eq(float(lgc.noun_values(25)[0]), 205.0, "00205")
	# SLEW: HI to within a degree, LO to peak the signal.
	var rr: RendezvousRadar = rt.systems["rr"]
	var peaked := false
	for i in 400:
		var e := _columbia_angles() - Vector2(rr.shaft, rr.trunnion)
		if e.length() < deg_to_rad(0.2):
			peaked = true
			break
		var lo := e.length() < deg_to_rad(1.0)
		Bus.set_value("ctl.lm.rr_slew_rate", 0 if lo else 1)
		var dead := deg_to_rad(0.1)
		Bus.set_value("ctl.lm.rr_slew_shaft", int(signf(e.x)) if absf(e.x) > dead else 0)
		Bus.set_value("ctl.lm.rr_slew_trunnion", int(signf(e.y)) if absf(e.y) > dead else 0)
		run(0.1, false)
	Bus.set_value("ctl.lm.rr_slew_shaft", 0)
	Bus.set_value("ctl.lm.rr_slew_trunnion", 0)
	assert_true(peaked, "slewed onto Columbia")
	var rng := Rendezvous.rel_pos(lm.traj, rt.dynamics.traj).length()
	var peak := 1.0 - 20.0 * log(rng / Units.NMI) / log(10.0) / 60.0
	assert_almost_eq(float(Bus.get_value("lm.rr.signal")), peak, 0.01, "SIGNAL STRENGTH at its peak")
	assert_true(bool(Bus.get_value("lm.rr.no_track")), "NO TRACK: no lock in SLEW")
	Bus.set_value("ctl.lm.rr_mode", 1)
	assert_true(run_until(func() -> bool: return not bool(Bus.get_value("lm.rr.no_track", true)), 30.0, 0.5, false),
		"AUTO TRACK: locked on, NO TRACK out")
	gut.p("By hand: SIGNAL STRENGTH %.3f (its peak %.3f); locked on, the range %.1f m (truly %.1f m)" % [
		float(Bus.get_value("lm.rr.signal")), peak, float(Bus.get_value("lm.rr.range_m")), rng])
	assert_almost_eq(float(Bus.get_value("lm.rr.range_m")), rng, 60.0, "the range, Columbia's")
	# The switch to LGC starts the range search again.
	Bus.set_value("ctl.lm.rr_mode", 0)
	run(1.0, false)
	assert_true(bool(Bus.get_value("lm.rr.no_track")), "LGC: the range search again")
	keys("P", lgc)
	assert_eq(lgc.p20.phase, "manual", "PRO waits for NO TRACK out")
	assert_true(run_until(func() -> bool: return not bool(Bus.get_value("lm.rr.no_track", true)), 30.0, 0.5, false),
		"NO TRACK out")
	keys("P", lgc)
	assert_eq(lgc.p20.priority, "", "PRO: R23 done")
	assert_true(run_until(func() -> bool: return lgc.p20.phase == "track", 10.0, 0.5, false), "R22's marks")
	lm_crew()
	assert_true(run_until(func() -> bool: return lgc.p20.marks >= 1, 120.0, 5.0), "a mark weighed in")


func test_r21_alarms_00503_when_columbia_isnt_where_the_state_vectors_put_it() -> void:
	var lgc := _restore()
	# The ground's Columbia 3 km out of its plane: 20° off at 8 km.
	_uplink_csm_off(0.0, 0.0, 3000.0)
	Bus.set_value("ctl.lm.rr_mode", 0)
	keys("V37E20E", lgc)
	if lgc.p20.phase == "r61":
		keys("P", lgc)
	assert_true(run_until(func() -> bool: return lgc.alarm_code == 503, 300.0, 1.0, false), "alarm 00503: 60 passes without a lock")
	assert_eq(lgc.p20.phase, "designate", "R21 designates again")
	assert_false(bool(Bus.get_value("lm.rr.data_good", true)), "no lock")

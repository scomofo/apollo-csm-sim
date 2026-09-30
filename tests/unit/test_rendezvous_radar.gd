## The rendezvous radar (slice 11d): its antenna on the shaft and the
## trunnion within mode 1's coverage, its lock on the transponder within
## its beam and the range search's 15 s, the LGC's designate and the
## crew's slew, what it measures and its errors, and when it has no data.
extends GutTest

const FT := 0.3048

var rr: RendezvousRadar


func before_each() -> void:
	Bus.reset()
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.sys.powered", true)
	Bus.set_value("lm.dyn.primary", "moon")
	Bus.set_value("dyn.primary", "moon")
	Bus.set_value("lm.dyn.att_q", Quaternion.IDENTITY)
	Bus.set_value("ctl.lm.rr_mode", 1)
	rr = RendezvousRadar.new()
	add_child_autofree(rr)


func _place(lm_r: Vector3, lm_v: Vector3, cm_r: Vector3, cm_v: Vector3) -> void:
	Bus.set_value("lm.dyn.r_m", [lm_r.x, lm_r.y, lm_r.z])
	Bus.set_value("lm.dyn.v_mps", [lm_v.x, lm_v.y, lm_v.z])
	Bus.set_value("dyn.r_m", [cm_r.x, cm_r.y, cm_r.z])
	Bus.set_value("dyn.v_mps", [cm_v.x, cm_v.y, cm_v.z])


## The radar ticked for [param s] seconds in steps of [param dt].
func _run(s: float, dt: float = 0.1) -> void:
	for i in int(round(s / dt)):
		rr.tick(dt)


## The CSM 20 km along the LM's +Z (inertial +Z with the LM unturned), 5
## km up its +X, closing at 10 m/s.
func _ahead() -> Vector3:
	var r := Bodies.R_MOON + 30000.0
	var d := Vector3(5000.0, 0.0, 20000.0)
	_place(Vector3(r, 0, 0), Vector3(0, 1600, 0), Vector3(r, 0, 0) + d, Vector3(0, 1600, 0) - d.normalized() * 10.0)
	return d


func test_in_auto_track_it_locks_on_and_measures_once_the_range_search_is_done() -> void:
	var d := _ahead()
	# The antenna along +Z holds; the CSM 14° off it is out of the beam.
	rr.tick(0.1)
	assert_false(Bus.get_value("lm.rr.locked"), "the CSM outside the beam")
	# The LM turned to bring the CSM within a degree of the boresight.
	var off := Vector3(0, 0, 1).angle_to(d)
	var q := Quaternion(Vector3(0, 1, 0), off - deg_to_rad(1.0))
	Bus.set_value("lm.dyn.att_q", q)
	# The gyros held the antenna along inertial +Z as the LM turned: slew
	# it onto the CSM by designating from the LGC... here, with the LM's
	# attitude the antenna's hold is 13° off; AUTO TRACK only locks within
	# the beam, so start the hold on the boresight again.
	rr.hold_dir = Basis(q) * Vector3(0, 0, 1)
	rr.tick(0.1)
	assert_true(Bus.get_value("lm.rr.locked"), "locked within the beam")
	assert_false(Bus.get_value("lm.rr.data_good"), "the range search")
	assert_true(Bus.get_value("lm.rr.no_track"), "NO TRACK lit")
	_run(15.0)
	assert_true(Bus.get_value("lm.rr.data_good"), "good 15 s on")
	assert_false(Bus.get_value("lm.rr.no_track"), "NO TRACK out")
	assert_almost_eq(float(Bus.get_value("lm.rr.range_m")), d.length(), 9.38 * FT, "the range, to a count")
	assert_almost_eq(float(Bus.get_value("lm.rr.range_rate_mps")), -10.0, 0.6278 * FT, "closing, to a count")
	var los: Vector3 = Bus.get_value("lm.rr.los_body")
	assert_lt(rad_to_deg(los.angle_to(Basis(q).inverse() * d.normalized())), 0.02, "on the CSM, to a CDU count")
	var a := RendezvousRadar.angles_of(los)
	assert_almost_eq(float(Bus.get_value("lm.rr.shaft_rad")), a.x, 1e-6, "its shaft")
	assert_almost_eq(float(Bus.get_value("lm.rr.trunnion_rad")), a.y, 1e-6, "its trunnion")


func test_its_angles_and_coverage() -> void:
	# At zero it looks along +Z; the shaft tips it toward +X, the trunnion
	# toward -Y [published: Luminary's RRNB].
	assert_almost_eq(RendezvousRadar.los_of(0.0, 0.0), Vector3(0, 0, 1), Vector3.ONE * 1e-6)
	assert_almost_eq(RendezvousRadar.los_of(PI / 2.0, 0.0), Vector3(1, 0, 0), Vector3.ONE * 1e-6)
	assert_almost_eq(RendezvousRadar.los_of(0.0, PI / 2.0), Vector3(0, -1, 0), Vector3.ONE * 1e-6)
	var a := Vector2(deg_to_rad(30.0), deg_to_rad(-20.0))
	assert_almost_eq(RendezvousRadar.angles_of(RendezvousRadar.los_of(a.x, a.y)), a, Vector2.ONE * 1e-6, "and back")
	assert_true(RendezvousRadar.in_coverage(Vector2(deg_to_rad(58.0), deg_to_rad(54.0))))
	assert_false(RendezvousRadar.in_coverage(Vector2(deg_to_rad(60.0), 0.0)), "past the shaft's +59°")
	assert_false(RendezvousRadar.in_coverage(Vector2(deg_to_rad(-71.0), 0.0)), "past its -70°")
	assert_false(RendezvousRadar.in_coverage(Vector2(0.0, deg_to_rad(56.0))), "past the trunnion's 55°")
	# The CSM behind the LM, out of the coverage: no lock, the antenna at
	# its stop.
	var r := Bodies.R_MOON + 30000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(r, 0, -20000.0), Vector3.ZERO)
	rr.hold_dir = Vector3(0, 0, -1)
	_run(1.0)
	assert_false(Bus.get_value("lm.rr.locked"), "behind the LM")


func test_the_lgc_designates_it_and_the_track_enable_closes_the_loop() -> void:
	var d := _ahead()
	Bus.set_value("ctl.lm.rr_mode", 0)
	var want := RendezvousRadar.angles_of(d)
	Bus.set_value("lm.guid.rr_designate", want)
	Bus.set_value("lm.guid.rr_designating", true)
	# 14° of shaft at up to 7°/s, and inside 7° at the error's rate.
	rr.tick(1.0)
	assert_almost_eq(rad_to_deg(rr.shaft), 7.0, 0.01, "7° in the first second")
	_run(6.0)
	assert_lt(rad_to_deg(Vector2(rr.shaft, rr.trunnion).distance_to(want)), 0.5, "on the designate")
	assert_false(Bus.get_value("lm.rr.locked"), "the loop open")
	Bus.set_value("lm.guid.rr_designating", false)
	Bus.set_value("lm.guid.rr_track_enable", true)
	rr.tick(0.1)
	assert_true(Bus.get_value("lm.rr.locked"), "the track enable: locked")
	_run(15.0)
	assert_true(Bus.get_value("lm.rr.data_good"))
	# Out of LGC, the range search starts again.
	Bus.set_value("ctl.lm.rr_mode", 1)
	rr.tick(0.1)
	assert_false(Bus.get_value("lm.rr.data_good"), "a turn of the switch")
	assert_true(Bus.get_value("lm.rr.locked"), "the angles still tracked")


func test_slewed_by_hand_it_peaks_the_signal_and_locks_in_auto_track() -> void:
	var d := _ahead()
	Bus.set_value("ctl.lm.rr_mode", 2)
	var s0 := float(Bus.get_value("lm.rr.signal", 0.0))
	# UP at HI, 7°/s, onto the CSM's 14° of shaft.
	Bus.set_value("ctl.lm.rr_slew_rate", 1)
	Bus.set_value("ctl.lm.rr_slew_shaft", 1)
	var best := 0.0
	var at_best := 0.0
	for i in 30:
		rr.tick(0.1)
		var sig := float(Bus.get_value("lm.rr.signal"))
		if sig > best:
			best = sig
			at_best = rr.shaft
	Bus.set_value("ctl.lm.rr_slew_shaft", 0)
	assert_false(Bus.get_value("lm.rr.locked"), "no tracking in SLEW")
	assert_gt(best, s0, "the signal rising toward the CSM")
	assert_almost_eq(rad_to_deg(at_best), rad_to_deg(RendezvousRadar.angles_of(d).x), 0.8, "peaking on it")
	# Back to the peak at LO, 1.33°/s, and AUTO TRACK.
	Bus.set_value("ctl.lm.rr_slew_rate", 0)
	Bus.set_value("ctl.lm.rr_slew_shaft", -1)
	var back := rr.shaft
	rr.tick(1.0)
	assert_almost_eq(rad_to_deg(back - rr.shaft), 1.33, 0.01, "LO")
	Bus.set_value("ctl.lm.rr_slew_shaft", 0)
	rr.hold_dir = Basis(Bus.get_value("lm.dyn.att_q") as Quaternion) * RendezvousRadar.los_of(at_best, 0.0)
	Bus.set_value("ctl.lm.rr_mode", 1)
	rr.tick(0.1)
	assert_true(Bus.get_value("lm.rr.locked"), "AUTO TRACK on the peak")


func test_its_errors_are_the_flights() -> void:
	var d := _ahead()
	rr.disperse(7)
	rr.hold_dir = d.normalized()
	_run(16.0)
	assert_true(Bus.get_value("lm.rr.data_good"))
	var sr := []
	var ss := []
	for i in 2000:
		rr.tick(0.05)
		sr.append(float(Bus.get_value("lm.rr.range_m")))
		ss.append(float(Bus.get_value("lm.rr.shaft_rad")))
	var mr := _mean(sr)
	var ms := _mean(ss)
	gut.p("Range bias %.1f ft, noise %.1f ft; shaft bias %.4f°, noise %.4f°" % [
		(mr - d.length()) / FT, _sd(sr, mr) / FT, rad_to_deg(ms - RendezvousRadar.angles_of(d).x), rad_to_deg(_sd(ss, ms))])
	# Near: 120 ft of bias at 3 sigma; 37 ft of noise on 9.38 ft counts.
	assert_almost_eq(mr - d.length(), rr.bias_range_k * 120.0 * FT / 3.0, 3.0 * FT, "this flight's range bias")
	assert_almost_eq(_sd(sr, mr) / FT, 37.0, 3.0, "Apollo 11's range noise")
	assert_almost_eq(ms - RendezvousRadar.angles_of(d).x, rr.bias_shaft, deg_to_rad(0.002), "the boresight's bias")
	assert_almost_eq(rad_to_deg(_sd(ss, ms)), 0.0105, 0.0015, "Apollo 11's angle noise, with the CDU's count")
	assert_lt(absf(rr.bias_shaft), 5.0 * 8e-3 / 3.0, "a bias of the AOH's size")
	# Another seed, another flight.
	var other := RendezvousRadar.new()
	other.disperse(8)
	assert_ne(other.bias_shaft, rr.bias_shaft)
	other.free()


static func _mean(a: Array) -> float:
	var s := 0.0
	for x in a:
		s += float(x)
	return s / a.size()


static func _sd(a: Array, m: float) -> float:
	var s := 0.0
	for x in a:
		s += (float(x) - m) * (float(x) - m)
	return sqrt(s / (a.size() - 1))


func test_the_moon_in_the_way_or_out_of_range_it_has_no_data() -> void:
	var r := Bodies.R_MOON + 20000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(-r, 0, 0), Vector3.ZERO)
	rr.hold_dir = Vector3(-1, 0, 0)
	_run(16.0)
	assert_false(Bus.get_value("lm.rr.data_good"), "the Moon between them")
	assert_eq(float(Bus.get_value("lm.rr.range_m")), 0.0)
	assert_true(RendezvousRadar.blocked([r, 0.0, 0.0], [-2.0 * r, 0.0, 0.0]))
	assert_false(RendezvousRadar.blocked([r, 0.0, 0.0], [0.0, 400000.0, 0.0]), "a line clear of the Moon")
	var far := float(SpacecraftData.section("rendezvous_radar")["range_max_m"]) + 1000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(r, 0, far), Vector3.ZERO)
	rr.hold_dir = Vector3(0, 0, 1)
	_run(16.0)
	assert_false(Bus.get_value("lm.rr.data_good"), "beyond 400 nmi")


func test_restored_it_reads_what_it_read_and_tracks_on() -> void:
	var d := _ahead()
	rr.disperse(3)
	rr.hold_dir = d.normalized()
	_run(16.0)
	var snap := rr.snapshot()
	var got := [Bus.get_value("lm.rr.range_m"), Bus.get_value("lm.rr.shaft_rad")]
	_run(5.0)
	var later := [Bus.get_value("lm.rr.range_m"), Bus.get_value("lm.rr.shaft_rad")]
	# A checkpoint: Dynamics puts the vehicles back first, then the radar.
	var other := RendezvousRadar.new()
	add_child_autofree(other)
	other.restore(snap)
	assert_eq([Bus.get_value("lm.rr.range_m"), Bus.get_value("lm.rr.shaft_rad")], got, "what it read")
	assert_true(other.locked and other.data_good, "still locked")
	for i in 50:
		other.tick(0.1)
	assert_eq([Bus.get_value("lm.rr.range_m"), Bus.get_value("lm.rr.shaft_rad")], later, "and on as it went")


func test_docked_or_unpowered_it_has_no_data() -> void:
	var d := _ahead()
	rr.hold_dir = d.normalized()
	_run(16.0)
	assert_true(Bus.get_value("lm.rr.data_good"), "flying free")
	Bus.set_value("dock.state", "docked")
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "docked")
	assert_false(Bus.get_value("lm.rr.no_track"), "unlit, off")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.sys.powered", false)
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "the LM powered down")

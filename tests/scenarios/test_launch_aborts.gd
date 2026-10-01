## Slice 9d's check (docs/ROADMAP.md): from a point in each abort mode's
## window of Apollo 11's launch, set off by a failure from the catalog,
## the CM comes down within its mode's landing area (Apollo 11 Mission
## Operation Report, M-932-69-11, pp. 55 to 57; mission.json
## "launch_aborts"), or mode IV reaches a safe orbit:
## - mode IB, a minute after the liftoff: S-IC engines 1 and 2 out; the
##   EDS aborts on its own and the tower takes the CM away, down between
##   the launch site and 520 nmi downrange;
## - mode II, at 4:00: the S-II's engines out; Houston's ABORT, the handle,
##   the CSM's separation and the CM's; full lift, down on the ground track
##   440 to 3,200 nmi downrange;
## - mode III, at 11:00: Apollo 13's O2 tank, which brings the crew home at
##   once; the handle, the SPS's retrograde burn on Houston's PAD, CM/SM
##   SEP and half lift to the south: down 3,000 to 3,350 nmi downrange,
##   about 70 nmi south of the track;
## - mode IV, at 10:30: the S-IVB's engine out; the handle and the SPS's
##   burn on Houston's PAD into an orbit with its perigee at least 75 nmi
##   up (MissionSequencer.SAFE_PERIGEE_M).
## Downrange runs along the nominal flight's ground track from the pad,
## and crossrange off it, south positive.
extends SimTest

## The nominal flight's ground track, latitude and east longitude (deg),
## every 30 s from the liftoff to 30 minutes, into the parking orbit
## [derived: the simulator's own Apollo 11 launch].
const TRACK := [
	[28.6084, -80.6043], [28.6079, -80.6042], [28.6101, -80.5938], [28.6274, -80.5299], [28.6803, -80.3385],
	[28.7905, -79.9359], [28.9571, -79.3159], [29.1388, -78.6200], [29.3295, -77.8610], [29.5276, -77.0351],
	[29.7338, -76.1332], [29.9489, -75.1455], [30.1730, -74.0614], [30.4062, -72.8687], [30.6482, -71.5534],
	[30.8981, -70.0991], [31.1533, -68.4929], [31.4069, -66.7421], [31.6509, -64.8611], [31.8765, -62.8712],
	[32.0731, -60.8215], [32.2380, -58.7104], [32.3684, -56.5367], [32.4612, -54.2993], [32.5125, -52.0100],
	[32.5176, -49.7149], [32.4763, -47.4208], [32.3887, -45.1301], [32.2551, -42.8456], [32.0757, -40.5695],
	[31.8512, -38.3039], [31.5820, -36.0512], [31.2688, -33.8117], [30.9127, -31.5905], [30.5145, -29.3877],
	[30.0749, -27.2034], [29.5955, -25.0419], [29.0773, -22.9030], [28.5209, -20.7862], [27.9284, -18.6951],
	[27.3004, -16.6275], [26.6388, -14.5866], [25.9443, -12.5700], [25.2191, -10.5804], [24.4636, -8.6151],
	[23.6796, -6.6752], [22.8690, -4.7616], [22.0322, -2.8714], [21.1709, -1.0053], [20.2865, 0.8374],
	[19.3803, 2.6576], [18.4536, 4.4559], [17.5077, 6.2334], [16.5438, 7.9909], [15.5631, 9.7295],
	[14.5669, 11.4503], [13.5562, 13.1543], [12.5323, 14.8427], [11.4957, 16.5178], [10.4487, 18.1785],
	[9.3919, 19.8271],
]
## The limits off the track [estimated]: the report's "on the ground
## track", and the half-lift landing's 70 nmi south of it.
const ON_TRACK_NMI := 25.0
const MODE_III_SOUTH_NMI := [30.0, 110.0]


static func _unit(g: Vector2) -> Vector3:
	var la := deg_to_rad(g.x)
	var lo := deg_to_rad(g.y)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la))


## Where [param geo] (latitude and east longitude, deg) is from the
## nominal ground track: Vector2(downrange along it from the pad, nmi;
## crossrange off it, nmi, south positive).
static func track_position(geo: Vector2) -> Vector2:
	var p := _unit(geo)
	var best := Vector2(INF, INF)
	var along := 0.0
	for i in TRACK.size() - 1:
		var a := _unit(Vector2(TRACK[i][0], TRACK[i][1]))
		var b := _unit(Vector2(TRACK[i + 1][0], TRACK[i + 1][1]))
		var seg := a.angle_to(b)
		if seg < 1e-9:
			continue
		var n := a.cross(b).normalized()
		var cross := asin(clampf(p.dot(n), -1.0, 1.0))
		var q := (p - n * p.dot(n)).normalized()
		var s := a.angle_to(q) * signf(a.cross(q).dot(n))
		if s >= -1e-6 and s <= seg + 1e-6 and absf(cross) < absf(best.y):
			# North of an eastbound track is along a x b: south is minus.
			best = Vector2((along + s) * Bodies.R_EARTH / Units.NMI, -cross * Bodies.R_EARTH / Units.NMI)
		along += seg
	return best


func _landed_at() -> Vector2:
	return track_position(rt.sequencer.geographic())


## The handle after Houston's ABORT, held through the separation and the
## ullage, then back at neutral.
func _abort_on_the_call(max_s: float) -> void:
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("eds.abort_light")), max_s, 1.0, false), "ABORT")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Abort. Abort.")
	Bus.set_value("ctl.abort", true)
	assert_true(run_until(func() -> bool: return rt.dynamics.config == "csm", 5.0, 0.1, false), "the CSM off")
	run(2.0, false)
	Bus.set_value("ctl.abort", false)


## CM/SM SEP and the ELS armed, as the crew does before the entry.
func _cm_sm_sep() -> void:
	Bus.set_value("ctl.seq.cm_sm_sep", true)
	run(0.5, false)
	Bus.set_value("ctl.seq.cm_sm_sep", false)
	Bus.set_value("ctl.els.logic", true)
	Bus.set_value("ctl.els.auto", true)
	assert_eq(rt.dynamics.config, "cm")


## Down to the splashdown, the peak load from here.
func _fly_down(max_s: float) -> void:
	rt.dynamics.max_g = 0.0
	assert_true(run_until(func() -> bool: return rt.dynamics.landed, max_s, 5.0, false), "down")
	run(1.0, false)
	assert_eq(rt.sequencer.phase, "splashdown")
	# On three mains about 32 ft/s, 9.8 m/s, at the landing weight the
	# design took (spacecraft.json "els"); on the drogues alone some 60.
	assert_lt(rt.dynamics.landed_speed, 11.0, "on the mains")


func test_mode_ib_the_tower_takes_the_cm_away_on_two_engines_out() -> void:
	build("launch")
	rt.failures.arm_on("sic_engine_1", "liftoff", 60.0)
	rt.failures.arm_on("sic_engine_2", "liftoff", 60.0)
	assert_true(run_until(func() -> bool: return rt.systems["eds"].aborted, 120.0, 1.0, false))
	assert_eq(rt.systems["eds"].cause, "2 ENG OUT", "the EDS on its own")
	assert_eq(rt.sequencer.abort_mode, "IB")
	var alt := rt.dynamics.traj.altitude()
	_fly_down(1200.0)
	var at := _landed_at()
	gut.p("mode IB from %.1f s, %.1f km up: down %.1f nmi downrange, %+.1f nmi off the track; %.1f g, %.1f m/s" % [
		rt.systems["eds"].abort_get, alt / 1000.0, at.x, at.y, rt.dynamics.max_g, rt.dynamics.landed_speed])
	assert_between(at.x, 0.0, 520.0, "mode I's area: the launch site to 520 nmi")
	assert_lt(absf(at.y), ON_TRACK_NMI, "on the track")


func test_mode_ii_full_lift_onto_the_track() -> void:
	build("launch")
	rt.failures.arm_on("s2_engines", "les_jettison", 43.0)
	_abort_on_the_call(300.0)
	assert_eq(rt.sequencer.abort_mode, "II")
	var from: float = rt.systems["eds"].abort_get
	run(8.0, false)
	_cm_sm_sep()
	_fly_down(2000.0)
	var at := _landed_at()
	gut.p("mode II from %s: down %.1f nmi downrange, %+.1f nmi off the track; %.1f g, %.1f m/s" % [Units.hms(from), at.x, at.y,
		rt.dynamics.max_g, rt.dynamics.landed_speed])
	assert_between(at.x, 440.0, 3200.0, "mode II's area: 440 to 3,200 nmi")
	assert_lt(absf(at.y), ON_TRACK_NMI, "on the track")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "Mode II")


func test_mode_iii_half_lift_short_of_africa() -> void:
	build("launch")
	rt.failures.arm_on("o2_tank_2", "s4_ignition", 108.0)
	_abort_on_the_call(900.0)
	assert_eq(rt.sequencer.abort_mode, "III", "home at once")
	var from: float = rt.systems["eds"].abort_get
	keys("V37E00E")
	var pad := rt.sequencer.request_pad("abort")
	assert_true(pad.get("uplinked", false), "the retrograde burn uplinked")
	# Retrograde on the SCS at RATE HIGH, then the CMC's P40.
	Bus.set_value("ctl.scs.att_source", 1)
	Bus.set_value("ctl.scs.rate", 1)
	var off := func() -> float: return rad_to_deg(rt.dynamics.attitude.eci_from_body().x.angle_to(-rt.dynamics.traj.vel()))
	Bus.set_value("ctl.rhc", Vector3(0.0, 1.0, 0.0))
	assert_true(run_until(func() -> bool: return float(off.call()) < 15.0, 60.0, SimClock.FIXED_DT, false), "retrograde")
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	run(3.0, false)
	Bus.set_value("ctl.scs.att_source", 0)
	Bus.set_value("ctl.scs.rate", 0)
	var dv := fly_pad(0, float(pad["tig"]) - SimClock.get_seconds - 5.0)
	_cm_sm_sep()
	# Half lift, rolled to the right: south of the northeastward track.
	var bank := deg_to_rad(float(rt.mission.section("launch_aborts")["half_lift_bank_deg"]))
	assert_true(run_until(func() -> bool: return rt.dynamics.in_atmosphere(), 3000.0, 10.0, false), "entry interface")
	Bus.set_value("ctl.rhc", Vector3(1.0, 0.0, 0.0))
	assert_true(run_until(func() -> bool: return rt.dynamics.bank >= bank - 0.005, 10.0, SimClock.FIXED_DT, false))
	Bus.set_value("ctl.rhc", Vector3.ZERO)
	_fly_down(3000.0)
	var at := _landed_at()
	gut.p("mode III from %s: %.1f m/s retrograde (PAD %.1f); down %.1f nmi downrange (planned %.1f from the pad), %+.1f nmi off the track; %.1f g, %.1f m/s" % [
		Units.hms(from), dv, float(pad["dv"]), at.x, float(pad["range_nmi"]), at.y, rt.dynamics.max_g, rt.dynamics.landed_speed])
	assert_between(at.x, 3000.0, 3350.0, "mode III's area: 3,000 to 3,350 nmi")
	assert_between(at.y, float(MODE_III_SOUTH_NMI[0]), float(MODE_III_SOUTH_NMI[1]), "south of the track")


func test_mode_iv_the_sps_takes_the_csm_into_orbit() -> void:
	build("launch")
	rt.failures.arm_on("s4_engine", "s4_ignition", 78.0)
	_abort_on_the_call(900.0)
	assert_eq(rt.sequencer.abort_mode, "IV")
	var from: float = rt.systems["eds"].abort_get
	keys("V37E00E")
	var pad := rt.sequencer.request_pad("abort")
	assert_true(pad.get("uplinked", false), "the burn into orbit uplinked")
	var dv := fly_pad(0, float(pad["tig"]) - SimClock.get_seconds - 5.0)
	var c: Dictionary = rt.dynamics.traj.conic()
	var hp := (float(c["rp"]) - Bodies.R_EARTH) / Units.NMI
	var ha := (float(c["ra"]) - Bodies.R_EARTH) / Units.NMI
	gut.p("mode IV from %s: %.1f m/s on the SPS (PAD %.1f), %.0f kg left; orbit %.1f by %.1f nmi" % [Units.hms(from), dv,
		float(pad["dv"]), float(Bus.get_value("sps.prop_kg")), ha, hp])
	assert_gt(hp, MissionSequencer.SAFE_PERIGEE_M / Units.NMI, "a safe orbit")
	assert_lt(ha - hp, 10.0, "round")
	run(3600.0)
	assert_eq(rt.sequencer.phase, "earth_orbit", "and still up an hour on")

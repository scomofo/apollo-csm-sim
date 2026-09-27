## Colossus's entry guidance (src/systems/entry_guidance.gd), the port of
## Comanche 055's REENTRY CONTROL the CMC flies P63 to P67 on, and P61's
## predictions (S61.2), piece by piece: slice 5f.
extends GutTest

const G := preload("res://src/systems/entry_guidance.gd")


## A guidance whose last pass measured [param v] (ft/s), [param rdot]
## (ft/s) and [param d] (ft/s²), [param th_nmi] from the target, in the
## middle of its phases (the lateral logic on).
static func _at(v: float, rdot: float, d: float, th_nmi: float) -> EntryGuidance:
	var e := EntryGuidance.new()
	e.lad = 0.3
	e.lod = 0.15
	e.ldcminr = e.lad * G.COS15
	e.klat = e.lad / 24.0
	e.v = v
	e.rdot = rdot
	e.d = d
	e.leq = (v / G.VSAT) * (v / G.VSAT) - 1.0
	e.theta = th_nmi / G.ATK
	e.gonepast = false
	return e


## A lunar return whose vacuum perigee is [param rp] m from the Earth's
## centre, flown back [param back_s] from there.
static func _return_from(rp: float, back_s: float) -> Trajectory:
	var vp := sqrt(2.0 * (-7.4e5 + Bodies.MU_EARTH / rp))
	var tr := Trajectory.new()
	tr.set_state("earth", 50000.0, Vector3(rp, 0.0, 0.0), Vector3(0.0, vp * cos(0.3), vp * sin(0.3)))
	while tr.t > 50000.0 - back_s:
		tr.step(-clampf(0.002 * tr.radius() / tr.speed(), 0.5, 60.0))
	return tr


func test_the_final_phase_table_is_the_listings() -> void:
	# Each table's first and last entries, unscaled from Comanche 055's
	# VREFER: the velocities by 2VSAT, the range and its partial in L/D by
	# 2,700 nmi, the drag by 805 ft/s², its partial by 2,700/805, the
	# altitude rate stored "B3" by VSAT/4 and its partial stored "B-3" by
	# 21,600/2VSAT.
	var vs2 := 2.0 * G.VSAT
	assert_almost_eq(float(G.REF_V[0]), 0.019288 * vs2, 0.01)
	assert_almost_eq(float(G.REF_RTOGO[12]), 0.294185185 * 2700.0, 0.01)
	assert_almost_eq(float(G.REF_DREF[0]), 0.051099 * 805.0, 0.01)
	assert_almost_eq(float(G.REF_DRDA[0]), -0.010337 * 2700.0 / 805.0, 1e-5)
	assert_almost_eq(float(G.REF_RDOT[0]), -0.0134001 * 8.0 * G.VSAT / 4.0, 0.01)
	assert_almost_eq(float(G.REF_DRDRDOT[0]), 0.0478599 / 8.0 * 21600.0 / vs2, 1e-6)
	assert_almost_eq(float(G.REF_DRDRDOT[12]), 5.813617 / 8.0 * 21600.0 / vs2, 1e-5)
	assert_almost_eq(float(G.REF_F3[0]), 0.004491 * 2700.0, 0.01)
	# Every partial within the scale GSOP 5.7's table of maxima gives it.
	for x in G.REF_DRDRDOT:
		assert_lt(float(x), 21600.0 / vs2, "the altitude rate's partial in its scale")
	for i in G.REF_V.size() - 1:
		assert_lt(float(G.REF_V[i]), float(G.REF_V[i + 1]), "the velocities rise")


func test_on_the_reference_trajectory_the_final_phase_flies_the_reference_lift() -> void:
	# At a table velocity, on the reference's drag and altitude rate, the
	# range the reference has to go is the range predicted: L/D is LOD.
	var k := 7
	var e := _at(float(G.REF_V[k]), float(G.REF_RDOT[k]), float(G.REF_DREF[k]), float(G.REF_RTOGO[k]))
	e._predict3()
	assert_almost_eq(e.predang, float(G.REF_RTOGO[k]), 0.01, "the range predicted")
	assert_almost_eq(e.dnrngerr, 0.0, 0.01, "no downrange error")
	assert_almost_eq(e.ld, e.lod, 1e-6, "the reference L/D")
	# Ten miles short: more lift, by 4 x 10 over the range's partial in L/D.
	e = _at(float(G.REF_V[k]), float(G.REF_RDOT[k]), float(G.REF_DREF[k]), float(G.REF_RTOGO[k]) + 10.0)
	e._predict3()
	assert_almost_eq(e.ld, e.lod + 40.0 / float(G.REF_F3[k]), 1e-6, "short: lift up")
	# Climbing 100 ft/s faster than the reference goes further, by the
	# altitude rate's partial: long.
	e = _at(float(G.REF_V[k]), float(G.REF_RDOT[k]) + 100.0, float(G.REF_DREF[k]), float(G.REF_RTOGO[k]))
	e._predict3()
	assert_almost_eq(e.dnrngerr, 100.0 * float(G.REF_DRDRDOT[k]), 1e-3, "long by the partial")
	assert_lt(e.ld, e.lod, "long: lift down")
	# Past the target: full lift down.
	e = _at(float(G.REF_V[k]), float(G.REF_RDOT[k]), float(G.REF_DREF[k]), 50.0)
	e.goneby = true
	e._predict3()
	assert_true(e.gonepast, "gone past, latched")
	assert_almost_eq(e.ld, -e.lad, 1e-9)


func test_the_initial_roll_flies_lift_up_into_a_steep_entry_and_down_into_a_shallow_one() -> void:
	# At 0.05 g on Apollo 11's entry, 36,276 ft/s and 6.2 deg down: lift up,
	# as its entry PAD had it. The constant drag level is D0 = 90 LEQ + 40.
	var e := _at(36276.0, -36276.0 * sin(deg_to_rad(6.2)), G.G05 + 0.1, 1400.0)
	e.g05sw = true
	e._initroll()
	assert_eq(e.program, 64)
	assert_almost_eq(e.ld, e.lad, 1e-9, "lift up")
	assert_almost_eq(e.d0, G.KA3 * e.leq + G.KA4, 1e-9)
	assert_almost_eq(e.kat, minf(G.KA1 * pow(e.leq, 3.0) + G.KA2, G.KALIM) * G.G, 1e-9)
	# Shallow, 2.4 deg: lift down, not to skip out.
	e = _at(36300.0, -36300.0 * sin(deg_to_rad(2.4)), G.G05 + 0.1, 1400.0)
	e.g05sw = true
	e._initroll()
	assert_almost_eq(e.ld, -e.lad, 1e-9, "lift down")
	# Under 27,000 ft/s at 0.05 g, straight to the final phase's wait.
	e = _at(26000.0, -1000.0, G.G05 + 0.1, 400.0)
	e.g05sw = true
	e._initroll()
	assert_eq(e.mode, "kep2")


func test_the_g_limiter_and_heavy_drag() -> void:
	# Past 8 g, full lift up whatever the final phase wants.
	var e := _at(20000.0, -800.0, G.GMAX + 5.0, 300.0)
	e.ld = -0.2
	e._glimiter()
	assert_almost_eq(e.ld, e.lad, 1e-9, "full lift up")
	# Above 175 ft/s², no negative lift, and a reversal rolls over the top
	# (LATSW cleared for the DAP).
	e = _at(30000.0, -500.0, G.C20 + 5.0, 1000.0)
	e.ld = -0.1
	e._negtests()
	assert_eq(e.ld, 0.0, "no negative lift")
	assert_false(e.latsw, "over the top")
	# Each pass starts with it set again, as the DAP leaves it.
	e.mode = "kep2"
	e.step(Vector3(6.5e6, 0.0, 0.0), Vector3(0.0, 7000.0, 0.0), Vector3.ZERO, 0.0)
	assert_true(e.latsw)


func test_the_lateral_logic_reverses_the_roll_past_the_crossrange_deadband() -> void:
	# The deadband: LAD/24 (V/VSAT)² rad plus LATBIAS.
	var e := _at(25000.0, -300.0, 60.0, 800.0)
	e.k2roll = -1.0
	var y := e.klat * pow(25000.0 / G.VSAT, 2.0) + G.LATBIAS / G.ATK
	e.ld = 0.15
	e.latang = -0.9 * y
	e._limit_ld()
	assert_eq(e.k2roll, -1.0, "inside the deadband: no reversal")
	assert_almost_eq(e.rollc, -acos(0.15 / 0.3), 1e-6, "rolled to its side")
	e.latang = -1.1 * y
	e._limit_ld()
	assert_eq(e.k2roll, 1.0, "past it: reversed")
	assert_almost_eq(e.rollc, acos(0.15 / 0.3), 1e-6)
	# Nearly full lift: the deadband halves, and on the far side the lift
	# holds in 15 deg to steer the crossrange.
	e = _at(25000.0, -300.0, 60.0, 800.0)
	e.k2roll = 1.0
	e.ld = 0.3
	e.latang = -0.001
	e._limit_ld()
	assert_almost_eq(e.ld1, e.ldcminr, 1e-9, "15 deg off full lift")
	assert_almost_eq(absf(e.rollc), acos(G.COS15), 1e-6)
	# Past the target, no lateral logic.
	e.gonepast = true
	e.latang = 1.0
	e.k2roll = 1.0
	e._limit_ld()
	assert_eq(e.k2roll, 1.0)


func test_the_roll_command_is_the_simulators_bank_turned_round() -> void:
	# Colossus's ROLLC is positive with the lift to the left; the
	# simulator's bank, to the right.
	var e := EntryGuidance.new()
	e.rollc = deg_to_rad(30.0)
	assert_almost_eq(e.bank_cmd_deg(), -30.0, 1e-9)
	assert_almost_eq(e.rollc_deg(), 30.0, 1e-9)
	e.rollc = deg_to_rad(-30.0)
	assert_almost_eq(e.rollc_deg(), 330.0, 1e-9, "the DSKY's 0-360")
	# HEADSUP -1 flies lift up into the air, +1 lift down.
	e.start(Vector3(6.5e6, 0.0, 0.0), Vector3(0.0, 11000.0, -1200.0), 0.0, 0.3, 0.15, G.target_of(10.0, 20.0), -1)
	assert_eq(e.rollc, 0.0)
	e.start(Vector3(6.5e6, 0.0, 0.0), Vector3(0.0, 11000.0, -1200.0), 0.0, 0.3, 0.15, G.target_of(10.0, 20.0), 1)
	assert_almost_eq(absf(e.rollc), PI, 1e-9)


func test_small_angles_and_distances_resolve() -> void:
	# A tenth of a mile, which single precision's arccosine can't tell
	# from nothing.
	var a := Vector3(1.0, 0.0, 0.0)
	var b := Vector3(cos(3e-5), sin(3e-5), 0.0)
	assert_almost_eq(G.angle(a, b), 3e-5, 1e-7)
	assert_almost_eq(Bodies.surface_angle(Vector2(13.32, -169.17), Vector2(13.32 + 0.1 / 60.0, -169.17)),
		deg_to_rad(0.1 / 60.0), 1e-8, "a tenth of a minute of latitude")
	var p := Bodies.geographic_to_fixed(13.32, -169.17, 1.0)
	var ll := Bodies.fixed_to_geographic(Vector3(p[0], p[1], p[2]))
	assert_almost_eq(ll, Vector2(13.32, -169.17), Vector2(1e-4, 1e-4), "latitude and longitude back")


func test_p61_predicts_the_entry_from_the_state_vector() -> void:
	# A return to the corridor's middle, a vacuum perigee 37 km up, half an
	# hour out.
	var tr := _return_from(Bodies.R_EARTH + 37000.0, 1800.0)
	var t0 := tr.t
	var p := G.predict(tr, G.target_of(0.0, 0.0))
	assert_false(p.is_empty())
	assert_eq(tr.t, t0, "the state vector itself not coasted")
	# Entry interface as the simulator's own coast finds it, closing in
	# on it in twentieths of a second.
	var c := tr.clone()
	c.coast_until(func(t2: Trajectory) -> bool: return t2.altitude() < G.ALT_400K + 20000.0, t0 + 3600.0, 60.0)
	c.coast_until(func(t2: Trajectory) -> bool: return t2.altitude() < G.ALT_400K, t0 + 3600.0, 0.05)
	assert_almost_eq(float(p["ei_get"]), c.t, 1.0, "entry interface's time")
	assert_almost_eq(float(p["vpred"]), c.speed(), 1.0, "its speed")
	assert_almost_eq(float(p["gammaei"]), rad_to_deg(asin(c.radial_rate() / c.speed())), 0.02, "its flight path angle")
	assert_between(float(p["gammaei"]), -7.0, -6.0, "the corridor's middle")
	# The EMS altitude after it, the speed there a few ft/s under the
	# vacuum's.
	assert_gt(float(p["tte_get"]), float(p["ei_get"]))
	assert_between(float(p["vio"]), float(p["vpred"]), float(p["vpred"]) + 60.0)
	# The peak load the formula expects, as Apollo 11's PAD had it (6.4 g),
	# and more for a steeper return.
	assert_between(float(p["gmax"]), 5.5, 7.5)
	var steep := G.predict(_return_from(Bodies.R_EARTH + 20000.0, 1800.0), G.target_of(0.0, 0.0))
	assert_gt(float(steep["gmax"]), float(p["gmax"]) + 0.5, "steeper, harder")
	# A return that misses the air has no entry.
	var miss := _return_from(Bodies.R_EARTH + 300000.0, 1800.0)
	assert_true(G.predict(miss, G.target_of(0.0, 0.0), 3600.0).is_empty())


func test_a_snapshot_restores_the_guidance() -> void:
	var e := EntryGuidance.new()
	e.start(Vector3(6.5e6, 1.0e5, 0.0), Vector3(-500.0, 11000.0, -1200.0), 100.0, 0.3, 0.15, G.target_of(13.32, -169.17))
	e.mode = "upcontrl"
	e.program = 65
	e.q7 = 34.0
	e.lewd = 0.171
	e.latsw = false
	# Through a checkpoint's JSON, to the last bits Godot's parser rounds.
	var copy := EntryGuidance.new()
	copy.restore(JSON.parse_string(JSON.stringify(e.snapshot(), "", true, true)))
	var a := e.snapshot()
	var b := copy.snapshot()
	assert_eq(b.keys(), a.keys())
	for k in a:
		if typeof(a[k]) == TYPE_FLOAT:
			assert_almost_eq(float(b[k]), float(a[k]), 1e-12 * maxf(absf(float(a[k])), 1.0), k)
		elif typeof(a[k]) == TYPE_ARRAY:
			for i in (a[k] as Array).size():
				assert_almost_eq(float(b[k][i]), float(a[k][i]), 1e-7, k)
		else:
			assert_eq(b[k], a[k], k)
			assert_eq(typeof(b[k]), typeof(a[k]), k)

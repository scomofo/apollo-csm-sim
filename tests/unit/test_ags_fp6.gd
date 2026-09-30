## The AGS's FP6 equations (AgsFp6) against two-body orbits: the ellipse
## predictor, the p-iterator along the LM's own orbit, CDH between
## coelliptic orbits, CSI flown through CDH to TPI, orbit insertion from the
## surface on a point mass, and the radar filter. Feet and seconds, in the
## AGS's frame: the orbits in its XZ plane, about -Y (FP6 takes y for the
## orbits' normal).
extends GutTest

const MU := AgsFp6.MU
## The Moon's radius at the landing site (5J) and the CSM's circular orbit,
## 60 nmi up, ft.
const R_SITE := 5693629.0
const R_CSM := R_SITE + 60.0 * 6076.115


## A state at radius [param r], [param lon_deg] from +X towards +Z,
## moving [param vh] horizontally (towards +Z at lon 0) and [param vr] up.
func _state(r: float, lon_deg: float, vh: float, vr: float = 0.0) -> Array:
	var c := cos(deg_to_rad(lon_deg))
	var s := sin(deg_to_rad(lon_deg))
	return [AgsFp6.vec(r * c, 0.0, r * s), AgsFp6.vec(vr * c - vh * s, 0.0, vr * s + vh * c)]


func _circular(r: float, lon_deg: float) -> Array:
	return _state(r, lon_deg, sqrt(MU / r))


## [param st] carried [param dt] seconds by RK4 on point-mass gravity.
func _rk4(st: Array, dt: float, h: float = 1.0) -> Array:
	var r: PackedFloat64Array = st[0]
	var v: PackedFloat64Array = st[1]
	var n := int(ceil(absf(dt / h)))
	var step := dt / n
	for _i in n:
		var k1r := v
		var k1v := _acc(r)
		var k2r := AgsFp6.add(v, AgsFp6.mul(k1v, step / 2))
		var k2v := _acc(AgsFp6.add(r, AgsFp6.mul(k1r, step / 2)))
		var k3r := AgsFp6.add(v, AgsFp6.mul(k2v, step / 2))
		var k3v := _acc(AgsFp6.add(r, AgsFp6.mul(k2r, step / 2)))
		var k4r := AgsFp6.add(v, AgsFp6.mul(k3v, step))
		var k4v := _acc(AgsFp6.add(r, AgsFp6.mul(k3r, step)))
		r = AgsFp6.add(r, AgsFp6.mul(AgsFp6.add(AgsFp6.add(k1r, AgsFp6.mul(k2r, 2)), AgsFp6.add(AgsFp6.mul(k3r, 2), k4r)), step / 6))
		v = AgsFp6.add(v, AgsFp6.mul(AgsFp6.add(AgsFp6.add(k1v, AgsFp6.mul(k2v, 2)), AgsFp6.add(AgsFp6.mul(k3v, 2), k4v)), step / 6))
	return [r, v]


func _acc(r: PackedFloat64Array) -> PackedFloat64Array:
	var rn := AgsFp6.length(r)
	return AgsFp6.mul(r, -MU / (rn * rn * rn))


## An AGS at AGS time [param t0] with the LM at [param lm] and the CSM at
## [param csm] ([r, v] each, at t0).
func _ags(t0: float, lm: Array, csm: Array) -> AgsFp6:
	var a := AgsFp6.new()
	a.t = t0
	a.initialize(lm[0], lm[1], t0, [csm[0], csm[1], t0])
	return a


func _axes() -> Array:
	return [AgsFp6.vec(1, 0, 0), AgsFp6.vec(0, 1, 0), AgsFp6.vec(0, 0, 1)]


func test_the_ellipse_predictor_matches_two_body_gravity() -> void:
	# Eagle's orbit after insertion, 9 by 45 nmi, from perilune.
	var rp := R_SITE + 9.0 * 6076.115
	var ra := R_SITE + 45.0 * 6076.115
	var a := (rp + ra) / 2.0
	var st := _state(rp, 20.0, sqrt(MU * (2.0 / rp - 1.0 / a)))
	for dt in [600.0, 1800.0, -900.0]:
		var want := _rk4(st, dt)
		var got := AgsFp6.ellipse(st[0], st[1], dt, AgsFp6.orbit_params(st[0], st[1]))
		assert_lt(AgsFp6.length(AgsFp6.sub(got[0], want[0])), 1.0, "position within a foot after %d s" % dt)
		assert_lt(AgsFp6.length(AgsFp6.sub(got[1], want[1])), 0.002, "velocity within 0.002 ft/s")


func test_a_transfer_along_the_lms_own_orbit_needs_no_dv() -> void:
	# The CSM 5 min ahead on the LM's own orbit, and the rendezvous offset
	# (3J) 5 min: the transfer is the LM's orbit itself.
	var rp := R_SITE + 12.0 * 6076.115
	var ra := R_SITE + 40.0 * 6076.115
	var a := (rp + ra) / 2.0
	var lm := _state(rp, 0.0, sqrt(MU * (2.0 / rp - 1.0 / a)))
	var csm := _rk4(lm, 300.0)
	var ags := _ags(1000.0, lm, csm)
	ags.j3 = 300.0
	ags.s10 = 4
	ags.t_ig = 1100.0
	ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	assert_lt(float(ags.disp["v_t"]), 0.5, "TPI and braking come to nothing: %.3f ft/s" % float(ags.disp["v_t"]))
	assert_lt(ags.vg_mag, 0.3, "V_G %.3f ft/s" % ags.vg_mag)


func test_cdh_between_coelliptic_circular_orbits_is_nothing() -> void:
	var lm := _circular(R_CSM - 15.0 * 6076.115, 0.0)
	var csm := _circular(R_CSM, 8.0)
	var ags := _ags(0.0, lm, csm)
	ags.s10 = 2
	ags.t_ig = 60.0
	ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	assert_almost_eq(float(ags.disp["dr"]), 15.0 * 6076.115, 20.0, "δr: the CSM 15 nmi above")
	assert_lt(absf(ags.j28_1), 0.05, "no horizontal ΔV: %.3f" % ags.j28_1)
	assert_lt(absf(ags.j28_3), 0.05, "no radial ΔV")


## CSI, flown through CDH half an orbit on to TPI's time on two-body
## gravity, leaves the CSM near the line of sight's angle 2J asked for.
func test_csi_then_cdh_bring_the_csm_to_the_tpi_angle() -> void:
	var rp := R_SITE + 9.0 * 6076.115
	var ra := R_SITE + 45.0 * 6076.115
	var a := (rp + ra) / 2.0
	# CSI at the LM's apolune; the CSM 8 deg ahead there, as it about was
	# at Apollo 11's.
	var lm := _state(ra, 0.0, sqrt(MU * (2.0 / ra - 1.0 / a)))
	var csm := _circular(R_CSM, 8.0)
	var t0 := 3000.0
	var ags := _ags(t0, lm, csm)
	ags.s10 = 1
	ags.t_ig = t0 + 40.0
	ags.j1 = t0 + 40.0 + 2.0 * 3600.0 - 600.0
	ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	var dv_csi := ags.j28_1
	assert_between(dv_csi, 30.0, 70.0, "CSI posigrade: %.1f ft/s" % dv_csi)
	assert_almost_eq(float(ags.disp["t_a0"]), PI / float(ags.csm_orbit["n"]), 300.0, "CDH about half an orbit on")
	# Fly CSI at its time: the LM and CSM carried there, the burn along the
	# horizontal.
	var l := _rk4(lm, ags.t_ig - t0 - 2.0)
	var c := _rk4(csm, ags.t_ig - t0 - 2.0)
	var u := AgsFp6.unit(l[0])
	var h := AgsFp6.unit(AgsFp6.cross(AgsFp6.cross(l[0], l[1]), u))
	l[1] = AgsFp6.add(l[1], AgsFp6.mul(h, dv_csi))
	var t_cdh: float = ags.t_ig + float(ags.disp["t_a0"])
	var t_tpi: float = ags.j1
	# CDH from a fresh AGS at its time.
	var dt1 := t_cdh - ags.t_ig
	l = _rk4(l, dt1)
	c = _rk4(c, dt1)
	var ags2 := _ags(t_cdh - 20.0, _rk4(l, -20.0), _rk4(c, -20.0))
	ags2.s10 = 2
	ags2.t_ig = t_cdh
	ags2.disp["t_a0"] = 0.0
	ags2.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	var u2 := AgsFp6.unit(l[0])
	var h2 := AgsFp6.unit(AgsFp6.cross(AgsFp6.cross(l[0], l[1]), u2))
	l[1] = AgsFp6.add(AgsFp6.add(l[1], AgsFp6.mul(h2, ags2.j28_1)), AgsFp6.mul(u2, -ags2.j28_3))
	var dh := float(ags2.disp["dr"])
	# Then to TPI's time: the CSM's elevation above the LM's horizontal.
	l = _rk4(l, t_tpi - t_cdh)
	c = _rk4(c, t_tpi - t_cdh)
	var rel := AgsFp6.sub(c[0], l[0])
	var up := AgsFp6.unit(l[0])
	var el := rad_to_deg(atan2(AgsFp6.dot(rel, up), AgsFp6.length(AgsFp6.sub(rel, AgsFp6.mul(up, AgsFp6.dot(rel, up))))))
	gut.p("CSI %.1f ft/s, CDH %.1f ft/s at %.1f nmi below, elevation at TPI %.2f deg" % [dv_csi, ags2.j28_1, dh / 6076.115, el])
	assert_almost_eq(el, rad_to_deg(atan(1.0 / ags.j2)), 1.5, "the CSM at 26.6 deg at TPI's time")


## Orbit insertion from the surface on a point mass: the vertical rise,
## then FP6's guidance law to the injection altitude and radial rate.
func test_insertion_from_the_surface_reaches_its_targets() -> void:
	# The CSM 4.5 deg ahead at liftoff: some 15 deg by insertion, as at
	# Apollo 11's.
	var lm := _state(R_SITE, 0.0, 0.0)
	var csm := _circular(R_CSM, 4.5)
	var ags := _ags(0.0, lm, csm)
	ags.d21 = true
	ags.s10 = 0
	var r: PackedFloat64Array = lm[0].duplicate()
	var v: PackedFloat64Array = lm[1].duplicate()
	var mass := 10900.0 / 32.174
	var thrust := 3500.0
	var mdot := thrust / (309.0 * 32.174)
	var vdx := 0.0
	var dir := AgsFp6.unit(r)
	var burning := true
	var tt := 0.0
	var dt := 0.02
	ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	ags.d21 = false
	ags.d2 = true
	var dv_cycle := AgsFp6.vec(0, 0, 0)
	var vdx_cycle := 0.0
	while burning and tt < 900.0:
		var acc := _acc(r)
		var at := thrust / mass
		var dv := AgsFp6.mul(dir, at * dt)
		v = AgsFp6.add(v, AgsFp6.add(AgsFp6.mul(acc, dt), dv))
		r = AgsFp6.add(r, AgsFp6.mul(v, dt))
		mass -= mdot * dt
		vdx += at * dt
		dv_cycle = AgsFp6.add(dv_cycle, dv)
		tt += dt
		if fmod(tt + 1e-6, 2.0) < dt:
			var axes := [dir, AgsFp6.vec(0, 1, 0), AgsFp6.unit(AgsFp6.cross(dir, AgsFp6.vec(0, 1, 0)))]
			ags.cycle(dv_cycle, vdx, axes)
			dv_cycle = AgsFp6.vec(0, 0, 0)
			vdx_cycle = vdx
			dir = ags.x_bd.duplicate()
		# The 40-ms countdown: the X axis's velocity to be gained less what
		# it has sensed since the cycle.
		var vg_body: PackedFloat64Array = ags.disp.get("vg_body", AgsFp6.vec(1e4, 0, 0))
		if vg_body[0] - (vdx - vdx_cycle) < 1.6875 and ags.vg_mag < 70.0:
			burning = false
	var rn := AgsFp6.length(r)
	var rdot := AgsFp6.dot(v, AgsFp6.unit(r))
	var o := AgsFp6.orbit_params(r, v)
	gut.p("insertion at %.0f s: %.0f ft, %.1f ft/s up, a %.0f nmi above the site (alpha_L %.0f nmi), theta_f %.2f deg" % [tt, rn - R_SITE, rdot, (float(o["a"]) - R_SITE) / 6076.115, (float(ags.disp["alpha_l"]) - R_SITE) / 6076.115, rad_to_deg(float(ags.disp["theta_f"]))])
	assert_lt(tt, 900.0, "the engine cut off")
	assert_almost_eq(rn - R_SITE, ags.j16, 3000.0, "at the injection altitude")
	assert_between(rdot, ags.j23 - 10.0, ags.j23 + 30.0, "rising at about 23J")


## Six range readings along the true line of sight take most of a 3,000
## ft error out of the LM's position in the CSM's plane.
func test_the_radar_filter_takes_ranges_in() -> void:
	var lm := _circular(R_CSM - 15.0 * 6076.115, 0.0)
	var csm := _circular(R_CSM, 3.0)
	var ags := _ags(0.0, [AgsFp6.add(lm[0], AgsFp6.vec(3000.0, 0.0, 0.0)), lm[1]], csm)
	ags.s17 = 1
	var l := lm
	var c := csm
	var err0 := 3000.0
	for k in 48:
		l = _rk4(l, 2.0)
		c = _rk4(c, 2.0)
		if k % 8 == 6:
			var rel := AgsFp6.sub(c[0], l[0])
			ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
			ags.mark(AgsFp6.unit(rel))
			ags.j18 = AgsFp6.length(rel)
		else:
			ags.cycle(AgsFp6.vec(0, 0, 0), 0.0, _axes())
	var err := AgsFp6.length(AgsFp6.sub(ags.r, l[0]))
	gut.p("position error %.0f ft after six ranges (from %.0f)" % [err, err0])
	assert_lt(err, err0 / 2.0, "the ranges take the error down")

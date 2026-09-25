## The LM's rendezvous targeting (Rendezvous): the CSM's elevation, the
## coelliptic sequence's maneuvers and TPI's transfer, flown on the
## propagator about the Moon. The orbits are in the XY plane, flown about
## +Z.
extends GutTest

const T0 := 280000.0
## The CSM's orbit radius: 60 nmi up.
const R_CSM := Bodies.R_MOON + 60.0 * Units.NMI

## The TPI elevation and transfer angle.
var e_tpi := deg_to_rad(26.6)
var wt := deg_to_rad(130.0)


func before_each() -> void:
	Bodies.configure(28.5, 0.0, 3.3, -20.0)


func after_all() -> void:
	# Back to the mission's own Moon for the tests after these.
	Mission.load_default()


## A state at GET T0, radius [param r] at [param lon_deg] from +X, moving
## at [param vh] horizontally and [param vr] up.
func _state(r: float, lon_deg: float, vh: float, vr: float = 0.0) -> Trajectory:
	var c := cos(deg_to_rad(lon_deg))
	var s := sin(deg_to_rad(lon_deg))
	var tr := Trajectory.new()
	tr.set_state_d("moon", T0, PackedFloat64Array([r * c, r * s, 0.0, vr * c - vh * s, vr * s + vh * c, 0.0]))
	return tr


func _circular(r: float, lon_deg: float) -> Trajectory:
	return _state(r, lon_deg, sqrt(Bodies.MU_MOON / r))


## [param tr]'s osculating orbit's radius in the direction [param u].
func _radius_at(tr: Trajectory, u: Vector3) -> float:
	var mu := Bodies.MU_MOON
	var r := tr.pos()
	var v := tr.vel()
	var ev := ((v.length_squared() - mu / r.length()) * r - r.dot(v) * v) / mu
	return r.cross(v).length_squared() / mu / (1.0 + ev.dot(u.normalized()))


func test_the_elevation_is_the_line_of_sights_angle_above_the_lms_horizontal() -> void:
	var r_lm := R_CSM - 15.0 * Units.NMI
	var lm := _circular(r_lm, 0.0)
	var th := deg_to_rad(3.0)
	var want := atan2(R_CSM * cos(th) - r_lm, R_CSM * sin(th))
	assert_almost_eq(Rendezvous.elevation(lm, _circular(R_CSM, 3.0)), want, 1e-6, "3° ahead, 15 nmi up")
	assert_almost_eq(Rendezvous.elevation(lm, _circular(R_CSM, 0.0)), PI / 2.0, 1e-6, "overhead")
	assert_gt(Rendezvous.elevation(lm, _circular(R_CSM, -1.0)), PI / 2.0, "past overhead: behind")
	var level := Rendezvous.elevation(lm, _circular(r_lm, 10.0))
	assert_almost_eq(level, deg_to_rad(-5.0), 1e-6, "on the LM's orbit, 10° ahead: half that below the horizon")


func test_next_apsis_finds_the_apolune_and_the_perilune() -> void:
	# 9 x 45 nmi, from its perilune.
	var rp := Bodies.R_MOON + 9.0 * Units.NMI
	var ra := Bodies.R_MOON + 45.0 * Units.NMI
	var a := 0.5 * (rp + ra)
	var tr := _state(rp, 0.0, sqrt(Bodies.MU_MOON * (2.0 / rp - 1.0 / a)))
	var apo := tr.clone()
	Rendezvous.next_apsis(apo, 60.0, "apo")
	assert_almost_eq(apo.radius(), ra, 50.0, "the apolune")
	assert_almost_eq(apo.radial_rate(), 0.0, 0.01, "the radial rate nought")
	var half := 0.5 * float(tr.conic()["period"])
	assert_almost_eq(apo.t - T0, half, 5.0, "half a revolution on")
	var peri := tr.clone()
	Rendezvous.next_apsis(peri, 60.0, "peri")
	assert_almost_eq(peri.t - T0, 2.0 * half, 10.0, "the next perilune: a revolution on")
	assert_almost_eq(peri.radius(), rp, 50.0)


func test_cdh_puts_the_lm_on_an_orbit_parallel_to_the_csms() -> void:
	# The CSM on a 57 x 63 nmi orbit, 40° past its perilune; the LM 16 nmi
	# below and 10° behind, climbing.
	var rp := Bodies.R_MOON + 57.0 * Units.NMI
	var ra := Bodies.R_MOON + 63.0 * Units.NMI
	var a := 0.5 * (rp + ra)
	var csm := _state(rp, 0.0, sqrt(Bodies.MU_MOON * (2.0 / rp - 1.0 / a)))
	csm.coast_to(T0 + 800.0)
	var lm := _state(R_CSM - 16.0 * Units.NMI, 30.0, 1630.0, 3.0)
	lm.t = csm.t
	var d := Rendezvous.cdh(lm, csm)
	var dh := float(d["dh"])
	assert_almost_eq(dh, _radius_at(csm, lm.pos()) - lm.radius(), 0.5, "ΔH: the CSM's orbit over the LM, less the LM")
	var dv: Vector3 = d["dv"]
	for i in 3:
		lm.s[3 + i] += dv[i]
	var worst := 0.0
	for k in 12:
		var u := Vector3(cos(k * PI / 6.0), sin(k * PI / 6.0), 0.0)
		worst = maxf(worst, absf(_radius_at(csm, u) - _radius_at(lm, u) - dh))
	gut.p("CDH %.2f m/s, ΔH %.2f nmi; the height between the orbits off ΔH by %.1f m at most" % [dv.length(), dh / Units.NMI, worst])
	assert_lt(worst, 5.0, "the same height below the CSM's orbit all the way round")


## Apollo 11's geometry at CSI: the LM at the apolune of its 9 x 45 nmi
## orbit, the CSM 60 nmi up and [param lead_deg] ahead.
func _at_csi(lead_deg: float) -> Array:
	var rp := Bodies.R_MOON + 9.0 * Units.NMI
	var ra := Bodies.R_MOON + 45.0 * Units.NMI
	var a := 0.5 * (rp + ra)
	return [_state(ra, 0.0, sqrt(Bodies.MU_MOON * (2.0 / ra - 1.0 / a))), _circular(R_CSM, lead_deg)]


func test_csi_has_the_csm_at_the_tpi_elevation_at_the_tpi_time() -> void:
	var st := _at_csi(9.0)
	var t_tpi := T0 + 6257.0   # Apollo 11: CSI 125:19:35, TPI 127:03:52
	var sol := Rendezvous.plan_csi(st[0], st[1], T0, t_tpi, e_tpi)
	gut.p("CSI %.2f ft/s, CDH at CSI + %.0f s, ΔH %.2f nmi" % [float(sol["dv"]) / Units.FT, float(sol["cdh_get"]) - T0,
		float(sol["dh"]) / Units.NMI])
	assert_true(sol["ok"], "a solution")
	# Fly it: CSI along the LM's horizontal, CDH (P33) at its time.
	var lm: Trajectory = st[0].clone()
	lm.s[4] += float(sol["dv"])
	lm.coast_to(sol["cdh_get"])
	var csm: Trajectory = st[1].clone()
	csm.coast_to(lm.t)
	var dv: Vector3 = Rendezvous.cdh(lm, csm)["dv"]
	for i in 3:
		lm.s[3 + i] += dv[i]
	lm.coast_to(t_tpi)
	csm.coast_to(t_tpi)
	assert_almost_eq(Rendezvous.elevation(lm, csm), e_tpi, 1e-4, "the CSM at 26.6° at the TPI time")
	assert_between(float(sol["dv"]) / Units.FT, 40.0, 65.0, "about circularizing (Apollo 11: 51.5 ft/s)")
	assert_between(float(sol["dh"]) / Units.NMI, 13.0, 17.0, "some 15 nmi below")
	var late := Rendezvous.plan_csi(st[0], st[1], T0, T0 + 1800.0, e_tpi)
	assert_false(late["ok"], "no solution with TPI before CDH")


## The LM on a circular orbit 15 nmi below the CSM, which leads it by
## [param lead_deg].
func _coelliptic(lead_deg: float) -> Array:
	return [_circular(R_CSM - 15.0 * Units.NMI, 0.0), _circular(R_CSM, lead_deg)]


func test_tpi_comes_when_the_csm_rises_to_the_elevation() -> void:
	var st := _coelliptic(4.0)
	var t := Rendezvous.tpi_time(st[0], st[1], e_tpi, T0 + 60.0, T0 + 3.0 * 3600.0)
	gut.p("TPI %.0f s on" % [t - T0])
	assert_between(t - T0, 1000.0, 3000.0, "the LM closes 2° from below in about half an hour")
	var lm: Trajectory = st[0].clone()
	lm.coast_to(t)
	var csm: Trajectory = st[1].clone()
	csm.coast_to(t)
	assert_almost_eq(Rendezvous.elevation(lm, csm), e_tpi, 1e-5, "26.6° then")
	var past := _coelliptic(1.0)
	assert_eq(Rendezvous.tpi_time(past[0], past[1], e_tpi, T0, T0 + 3600.0), -1.0, "none with the CSM already higher")


func test_tpi_meets_the_csm_after_it_has_flown_130_degrees() -> void:
	var st := _coelliptic(4.0)
	var t := Rendezvous.tpi_time(st[0], st[1], e_tpi, T0 + 60.0, T0 + 3.0 * 3600.0)
	var lm: Trajectory = st[0].clone()
	lm.coast_to(t)
	var csm: Trajectory = st[1].clone()
	csm.coast_to(t)
	var t_arrive := Rendezvous.arrival(csm, wt)
	assert_almost_eq(t_arrive - t, float(csm.conic()["period"]) * 130.0 / 360.0, 1e-6)
	var tr := Rendezvous.transfer(lm, csm, t_arrive)
	var dv: Vector3 = tr["dv"]
	gut.p("TPI %.1f ft/s, braking %.1f ft/s, miss %.2f m" % [dv.length() / Units.FT, float(tr["rel_v"]) / Units.FT, tr["miss"]])
	for i in 3:
		lm.s[3 + i] += dv[i]
	lm.coast_to(t_arrive)
	csm.coast_to(t_arrive)
	assert_lt(Rendezvous.rel_pos(lm, csm).length(), 1.0, "at the CSM")
	assert_almost_eq(Rendezvous.rel_vel(csm, lm).length(), float(tr["rel_v"]), 1e-3, "at the braking speed")
	assert_almost_eq(dv.length() / Units.FT, 25.0, 4.0, "Apollo 11: 25 ft/s")
	assert_almost_eq(float(tr["rel_v"]) / Units.FT, 31.0, 5.0, "Apollo 11 closed at 31 ft/s 0.7 mile out")

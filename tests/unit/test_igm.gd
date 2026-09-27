## The IU's iterative guidance mode (slice 5c): the S-IVB's second burn
## from Apollo 11's parking orbit, flown by Sivb.simulate_burn() (the law
## the IU flies) onto target conics that Rtcc.tli_target() builds.
extends GutTest

var mission: Mission


func before_each() -> void:
	mission = Mission.load_default()


func after_all() -> void:
	Mission.load_default()


## Apollo 11's parking orbit at insertion, as MissionSequencer builds it,
## coasted to [param get_s].
func _parking(get_s: float) -> Trajectory:
	var po := mission.section("parking_orbit")
	var r := Bodies.R_EARTH + float(po["alt_km"]) * 1000.0
	var v := sqrt(Bodies.MU_EARTH / r)
	var i := deg_to_rad(float(po["inclination_deg"]))
	var o := deg_to_rad(float(po["raan_deg"]))
	var p := Vector3(cos(o), sin(o), 0.0)
	var q := Vector3(-sin(o) * cos(i), cos(o) * cos(i), sin(i))
	var u := deg_to_rad(float(po["arg_lat_deg"]))
	var tr := Trajectory.new()
	tr.set_state("earth", float(po["insertion_get_s"]), (p * cos(u) + q * sin(u)) * r, (-p * sin(u) + q * cos(u)) * v)
	tr.coast_to(get_s, 30.0)
	return tr


static func _stack_mass() -> float:
	return SpacecraftData.total_mass("stack", float(SpacecraftData.section("sps")["propellant_kg"]), 560.0, 110.0,
		float(SpacecraftData.section("sivb")["propellant_kg"]))


## The plane of [param tr] (a parking orbit at the ignition) turned
## [param psi] rad about the burn's middle, a quarter of its arc on, as a
## minimum-propellant plane change turns it: its unit normal.
static func _turned(tr: Trajectory, psi: float) -> Vector3:
	var n := tr.pos().cross(tr.vel()).normalized()
	return n.rotated(tr.pos().normalized().rotated(n, deg_to_rad(13.5)), psi)


## The perigee radius of the flown conic mission.json's tli block gives.
static func _perigee_r(t: Dictionary) -> float:
	return -Bodies.MU_EARTH / float(t["c3_m2_per_s2"]) * (1.0 - float(t["eccentricity"]))


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


## From the flown TIG, onto conics whose planes are turned either way: the
## energy cut off on, the plane, and at the cutoff the radius and the
## flight path angle of the target conic where it is, its eccentricity and
## the orientation of its perigee.
func test_the_igm_flies_onto_the_conic_it_is_given() -> void:
	var t := mission.section("tli")
	var energy := float(t["c3_m2_per_s2"]) / 2.0
	var e := float(t["eccentricity"])
	var mass := _stack_mass()
	var prop := float(SpacecraftData.section("sivb")["propellant_kg"])
	var mu := Bodies.MU_EARTH
	var p := mu * (1.0 - e * e) / (-2.0 * energy)
	for psi_deg in [0.0, 1.3, -2.0]:
		var tr := _parking(2.0 * 3600.0 + 44.0 * 60.0 + 16.2)
		var tgt := Rtcc.tli_target(tr, mass, energy, _perigee_r(t), _turned(tr, deg_to_rad(psi_deg)))
		var n := _vec(tgt["n"])
		var pe := _vec(tgt["pe"])
		var t0 := tr.t
		var left := Sivb.simulate_burn(tr, mass, prop, tgt)
		var r := tr.pos()
		var v := tr.vel()
		var h := r.cross(v)
		var f := atan2(pe.cross(r).dot(n), pe.dot(r))
		var gam := rad_to_deg(asin(r.normalized().dot(v.normalized())))
		var gam_t := rad_to_deg(atan2(e * sin(f), 1.0 + e * cos(f)))
		var r_t := p / (1.0 + e * cos(f))
		var e_got := sqrt(1.0 + 2.0 * Sivb.energy_of(tr.s) * h.length_squared() / (mu * mu))
		var dv := float(SpacecraftData.section("sivb")["isp_s"]) * Units.G0 * log(mass / (mass - prop + left))
		gut.p("plane turned %.1f deg: %.1f s, %.1f m/s; cut off %.2f deg past the perigee, %.1f km up (the conic's %.1f), %.3f deg up (%.3f), e %.6f, %.4f deg from the plane" % [
			psi_deg, tr.t - t0, dv, rad_to_deg(f), (r.length() - Bodies.R_EARTH) / 1000.0, (r_t - Bodies.R_EARTH) / 1000.0,
			gam, gam_t, e_got, rad_to_deg(h.angle_to(n))])
		assert_almost_eq(Sivb.energy_of(tr.s), energy, 1.0, "on the target's energy, %.1f deg" % psi_deg)
		assert_lt(rad_to_deg(h.angle_to(n)), 0.005, "in the target's plane, %.1f deg" % psi_deg)
		assert_almost_eq(r.length(), r_t, 500.0, "at the conic's radius, %.1f deg" % psi_deg)
		assert_almost_eq(gam, gam_t, 0.01, "on the conic's flight path angle, %.1f deg" % psi_deg)
		assert_almost_eq(e_got, e, 2e-5, "the conic's eccentricity, %.1f deg" % psi_deg)
		assert_between(rad_to_deg(f), 5.0, 25.0, "cut off past the perigee, mid-burn, %.1f deg" % psi_deg)


## The time to go is worked out again at each pass: after the first few
## seconds each pass puts the cutoff within a second of where it comes.
func test_the_time_to_go_converges() -> void:
	var t := mission.section("tli")
	var mass := _stack_mass()
	var tr := _parking(2.0 * 3600.0 + 44.0 * 60.0 + 16.2)
	var tgt := Rtcc.tli_target(tr, mass, float(t["c3_m2_per_s2"]) / 2.0, _perigee_r(t), _turned(tr, deg_to_rad(1.3)))
	var trace := []
	Sivb.simulate_burn(tr, mass, float(SpacecraftData.section("sivb")["propellant_kg"]), tgt, trace)
	var worst := 0.0
	for step: Array in trace:
		if float(step[0]) - float(trace[0][0]) >= 5.0:
			worst = maxf(worst, absf(float(step[0]) + float(step[1]) - tr.t))
	var first := float(trace[0][0]) + float(trace[0][1]) - tr.t
	gut.p("%d passes: the first put the cutoff %.2f s off, the rest from 5 s on within %.3f s" % [trace.size(), first, worst])
	assert_gt(trace.size(), 300, "a pass a second")
	assert_lt(worst, 1.0, "the time to go within a second")

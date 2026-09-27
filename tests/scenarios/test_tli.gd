extends SimTest


## Slice 5c's check: the IU's iterative guidance flies TLI onto the conic
## the RTCC planned, in the flown TLI's plane, with the flown ΔV and burn,
## and leaves the stack on the free return Apollo 11's TLI left it on.
func test_saturn_iu_flies_tli_and_reaches_the_moon() -> void:
	build("parking_orbit")
	var seq := rt.sequencer
	assert_eq(seq.phase, "parking_orbit")
	assert_false(seq.tli_pad.is_empty(), "RTCC found a TLI opportunity")
	var pad := seq.tli_pad
	var tig := float(pad["tig"])
	assert_almost_eq(tig, 2.0 * 3600.0 + 44.0 * 60.0 + 16.2, 60.0, "TLI near the flown 2:44:16")
	run(tig - 30.0 - SimClock.get_seconds)
	var h0 := _momentum(rt.dynamics.traj)
	var m0 := float(Bus.get_value("dyn.mass_kg"))
	var p0 := float(Bus.get_value("sivb.prop_kg"))
	# A second at a time, for the state at the cutoff.
	assert_true(run_until(func() -> bool: return seq._has("tli_cutoff"), 700.0, 1.0))
	var ign: float = Bus.get_value("mission.event.tli_ignition")
	assert_almost_eq(ign, tig, 0.05, "ignition on the planned TIG")
	var burn := float(Bus.get_value("mission.event.tli_cutoff")) - ign
	# What the J-2 gave (the rocket equation on the propellant it burned)
	# and how far it turned the plane.
	var used := p0 - float(Bus.get_value("sivb.prop_kg"))
	var dv := float(SpacecraftData.section("sivb")["isp_s"]) * Units.G0 * log(m0 / (m0 - used))
	var h1 := _momentum(rt.dynamics.traj)
	var target: Dictionary = pad["target"]
	var flown := _vec(seq.mission.section("tli")["plane_normal"])
	var st := rt.dynamics.traj.earth_state()
	var r1 := Vector3(st[0], st[1], st[2])
	var v1 := Vector3(st[3], st[4], st[5])
	gut.p("TLI at %s: %.1f m/s from the J-2 in %.1f s, the plane turned %.2f deg, %.2f deg from the flown one; cut off %.1f km up at %.1f m/s, %.2f deg up (Apollo 11: 2:44:16, 3,182.4 m/s in 346.9 s, 1.20 deg; 320.9 km, 10,841.0 m/s, 6.91 deg)" % [
		Units.hms(ign), dv, burn, _angle_deg(h0, h1), rad_to_deg(_vec3(h1).angle_to(flown)),
		(r1.length() - Bodies.R_EARTH) / 1000.0, v1.length(), rad_to_deg(asin(r1.normalized().dot(v1.normalized())))])
	assert_almost_eq(burn, 346.9, 20.0, "the J-2's second burn, 346.9 s flown")
	assert_almost_eq(dv, 3182.4, 10.0, "the flown 10,441.0 ft/s (MSC-00171, Table 7-III)")
	assert_almost_eq(Sivb.energy_of(st), float(target["energy"]), 50.0, "cut off on the target's energy")
	assert_lt(rad_to_deg(_vec3(h1).angle_to(flown)), 0.01, "in the flown TLI's plane")
	assert_almost_eq(_angle_deg(h0, h1), 1.20, 0.05, "the plane turned as flown")
	# The RTCC's energy, against the report's C3 at TLI.
	var c3 := float(seq.mission.section("tli")["c3_m2_per_s2"])
	var dv_c3 := (2.0 * float(target["energy"]) - c3) / (2.0 * v1.length())
	gut.p("the RTCC's C3 %.0f m2/s2, %.2f m/s over the report's %.0f" % [2.0 * float(target["energy"]), dv_c3, c3])
	assert_lt(absf(dv_c3), 1.0, "within the metre a second the report's trajectory solutions spread")
	assert_eq(seq.phase, "translunar_coast")
	assert_gt(float(Bus.get_value("dyn.apo_alt_m")), 3.0e8, "apogee beyond the Moon's orbit")
	# Crew separates, T&D.
	Bus.set_value("ctl.seq.csm_sep", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.csm_sep", false)
	assert_eq(rt.dynamics.config, "csm_lm")
	# Coast to the Moon and back to the Earth: the free return, as the
	# mission report gives it after TLI (MSC-00171, Tables 7-III and 7-IV).
	var planned := float(pad["pericynthion_get"])
	var tr := rt.dynamics.traj.clone()
	var ap := Rtcc.lunar_approach(tr, planned + 86400.0)
	var t_peri := Rtcc._pericynthion_time(tr)
	var rel := tr.moon_state_rel()
	var mf := Bodies.moon_fixed(tr.t).transposed() * Vector3(rel[0], rel[1], rel[2])
	var lat := rad_to_deg(asin(mf.normalized().z))
	var lon := rad_to_deg(atan2(mf.y, mf.x))
	var er := Rtcc.earth_return(tr, tr.t + 6.0 * 86400.0)
	gut.p("pericynthion %.1f nmi at %s, %.2f deg N %.2f deg E (plan %.1f nmi at %s; Apollo 11: 896.3 nmi at 075:05:21, 0.11 deg S 174.13 deg W); back at the Earth at %s, vacuum perigee %.0f km (Apollo 11: captured, -5,149 km)" % [
		(float(ap["rp"]) - Bodies.R_MOON) / Units.NMI, Units.hms(t_peri), lat, lon, float(pad["pericynthion_alt"]) / Units.NMI,
		Units.hms(planned), Units.hms(float(er["t"])), (float(er["rp"]) - Bodies.R_EARTH) / 1000.0])
	assert_true(ap["reached"])
	assert_false(ap["impact"])
	assert_lt(float(ap["f"]), 0.0, "past the Moon on the retrograde side")
	assert_almost_eq((float(ap["rp"]) - Bodies.R_MOON) / Units.NMI, 896.3, 10.0, "the flown free return's 896.3 nmi")
	assert_almost_eq(t_peri, 75.0 * 3600.0 + 5.0 * 60.0 + 21.0, 60.0, "at the flown 75:05:21")
	# The pass's latitude turns with the plane, 100 degrees of it a degree
	# of the plane's tilt: within 3 degrees, the plane within 0.03.
	assert_almost_eq(lat, -0.11, 3.0, "where the flown one passed: its latitude")
	assert_almost_eq(lon, -174.13, 1.0, "and its longitude")
	# The entry the report gives, 36,076 ft/s at 64.06 deg down, is a
	# vacuum perigee 5,149 km below the surface: the free return captures.
	assert_true(er["reached"], "back at the Earth")
	assert_between((float(er["rp"]) - Bodies.R_EARTH) / 1000.0, -6000.0, -2000.0, "captured, as the flown free return")


## A checkpoint taken mid-TLI flies on to the same cutoff: the IU's
## target and its guidance's state come back with it.
func test_a_checkpoint_mid_tli_flies_on_to_the_same_cutoff() -> void:
	build("parking_orbit")
	var seq := rt.sequencer
	var tig := float(seq.tli_pad["tig"])
	run(tig + 150.0 - SimClock.get_seconds)
	assert_eq(str(Bus.get_value("sivb.state")), "burning")
	var snap := rt.snapshot()
	assert_true(run_until(func() -> bool: return seq._has("tli_cutoff"), 400.0, 60.0))
	var cut := float(Bus.get_value("mission.event.tli_cutoff"))
	var s1 := rt.dynamics.traj.earth_state()
	assert_eq(rt.restore(snap), "")
	assert_true(run_until(func() -> bool: return seq._has("tli_cutoff"), 400.0, 60.0))
	var s2 := rt.dynamics.traj.earth_state()
	var off := Vector3(s1[0] - s2[0], s1[1] - s2[1], s1[2] - s2[2]).length()
	var dv := Vector3(s1[3] - s2[3], s1[4] - s2[4], s1[5] - s2[5]).length()
	gut.p("restored mid-TLI: cutoff %.3f s apart, %.1f m and %.3f m/s from the uninterrupted flight" % [
		float(Bus.get_value("mission.event.tli_cutoff")) - cut, off, dv])
	# The restored run's steps fall up to a step (0.02 s) off the
	# uninterrupted run's, and the IGM's passes a second apart with them.
	assert_almost_eq(float(Bus.get_value("mission.event.tli_cutoff")), cut, 0.05, "the same cutoff, within a step")
	assert_lt(dv, 0.1, "and the same velocity")


## Slice 5a's check: the Earth's oblateness turns the parking orbit's plane
## west at J2's rate for it, 0.32 deg an hour, which by Apollo 11's TLI,
## 2.54 h after insertion, comes to 0.8 deg.
func test_the_earths_oblateness_turns_the_parking_orbit_west() -> void:
	build("parking_orbit")
	var pad := rt.sequencer.tli_pad
	var tig := float(pad["tig"])
	var c0: Dictionary = rt.dynamics.traj.conic()
	var n0 := _node_deg(rt.dynamics.traj)
	var t0 := SimClock.get_seconds
	run(tig - 120.0 - t0)
	var hours := (SimClock.get_seconds - t0) / 3600.0
	var turned := wrapf(_node_deg(rt.dynamics.traj) - n0, -180.0, 180.0)
	var a: float = c0["a"]
	var n := sqrt(Bodies.MU_EARTH / (a * a * a))
	var rate := rad_to_deg(-1.5 * n * Bodies.EARTH_J2 * pow(Bodies.R_EARTH / a, 2.0) * cos(float(c0["i"]))) * 3600.0
	gut.p("the node turned %.3f deg in %.2f h (J2's rate %.3f deg/h: %.3f deg; by the flown TLI %.2f deg); TLI turns the plane %.2f deg, %.0f m/s" % [
		turned, hours, rate, rate * hours, rate * 2.541, rad_to_deg(float(pad["turn"])), float(pad["dv"])])
	assert_almost_eq(turned, rate * hours, absf(rate * hours) * 0.05, "west at J2's rate")
	assert_almost_eq(rate * 2.541, -0.80, 0.02, "0.8 deg by Apollo 11's TLI")


## The angle between two vectors given in doubles, degrees.
static func _angle_deg(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return rad_to_deg(acos(clampf((a[0] * b[0] + a[1] * b[1] + a[2] * b[2])
		/ sqrt((a[0] * a[0] + a[1] * a[1] + a[2] * a[2]) * (b[0] * b[0] + b[1] * b[1] + b[2] * b[2])), -1.0, 1.0)))


static func _vec3(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2]).normalized()


static func _vec(a: Variant) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])).normalized()


## [param tr]'s angular momentum about the Earth, in doubles.
static func _momentum(tr: Trajectory) -> PackedFloat64Array:
	var s := tr.earth_state()
	return PackedFloat64Array([s[1] * s[5] - s[2] * s[4], s[2] * s[3] - s[0] * s[5], s[0] * s[4] - s[1] * s[3]])


## The right ascension of [param tr]'s ascending node, degrees.
static func _node_deg(tr: Trajectory) -> float:
	var h: Vector3 = tr.conic()["h"]
	return rad_to_deg(atan2(h.x, -h.y))

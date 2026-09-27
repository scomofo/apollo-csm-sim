## The Moon's gravity field (slice 5b). Apollo 11's orbit after LOI-2,
## 65.7 by 53.8 nmi, was targeted noncircular for the Moon's field to round
## it toward 60 nmi by the rendezvous: the ground's R-2 model said 59.9 by
## 59.3 at 126 h. The orbit stayed out of round, 62.4 by 56.6 [the mission
## report, MSC-00171, section 7.4.4]. Flown through GRAIL's field it does
## as the flight did; flown through R-2, the model the onboard computers
## carried, it rounds out as R-2 said [simplified: without the CSM's
## separation maneuver at 100:39:50, 2.7 ft/s, which the report's figures
## took in]. A round orbit, Apollo 10's approach, goes further out of
## round, as the report estimated; and the CMC's state vector, flying R-2,
## drifts from the truth.
extends SimTest

const NMI := 1852.0
## The times the ground's tracking gave the orbit (GET h), and what it
## gave (apocynthion, pericynthion, nmi) [published: the Apollo 11 Flight
## Journal's PAO commentary; the mission report's Table 7-V at 100:40 and
## section 7.4.4 at 126 h].
const FLOWN := [
	[83.0 + 40.0 / 60.0, 65.1, 54.2],
	[87.0 + 31.0 / 60.0, 64.7, 54.8],
	[93.0 + 29.0 / 60.0, 64.0, 55.5],
	[98.0 + 18.0 / 60.0, 63.5, 55.9],
	[100.0 + 40.0 / 60.0, 63.7, 56.0],
	[119.0 + 51.0 / 60.0, 62.0, 57.0],
	[126.0, 62.4, 56.6],
]


## The orbit's highest and lowest over the revolution from [param tr]'s
## time, nmi above the landing site's radius (the report's datum).
func _apsides(tr: Trajectory) -> Vector2:
	var r_site := rt.sequencer.landing_site().length()
	var t := tr.clone()
	var end := t.t + float(t.conic()["period"])
	var lo := INF
	var hi := 0.0
	while t.t < end:
		t.step(minf(10.0, end - t.t))
		lo = minf(lo, t.radius())
		hi = maxf(hi, t.radius())
	return Vector2(hi - r_site, lo - r_site) / NMI


func test_the_flown_orbit_stays_out_of_round_as_it_did_and_r2_rounds_it() -> void:
	build("lunar_orbit")
	var truth := rt.dynamics.traj.clone()
	var r2 := truth.clone().as_onboard(Trajectory.Model.CMC)
	var start := _apsides(truth)
	gut.p("after LOI-2, %s: %.1f by %.1f nmi (Apollo 11: 65.7 by 53.8)" % [Units.hms(truth.t), start.x, start.y])
	var grail := Vector2.ZERO
	var model := Vector2.ZERO
	for row: Array in FLOWN:
		var t := float(row[0]) * 3600.0
		truth.coast_to(t, 60.0, Rtcc.FRAC)
		r2.coast_to(t, 60.0, Rtcc.FRAC)
		grail = _apsides(truth)
		model = _apsides(r2)
		gut.p("%s: GRAIL's %.1f by %.1f, R-2's %.1f by %.1f; Apollo 11's %.1f by %.1f" % [Units.hms(t),
			grail.x, grail.y, model.x, model.y, row[1], row[2]])
		assert_almost_eq(grail.x, float(row[1]), 1.5, "the apocynthion at %s as flown" % Units.hms(t))
		assert_almost_eq(grail.y, float(row[2]), 1.0, "the pericynthion at %s as flown" % Units.hms(t))
	# At 126 h, as the report gives it: out of round by 5.8 nmi, and R-2's
	# prediction round.
	assert_almost_eq(grail.x, 62.4, 0.75, "GRAIL's apocynthion at 126 h: 62.4 nmi flown")
	assert_almost_eq(grail.y, 56.6, 0.75, "and pericynthion: 56.6")
	assert_almost_eq(model.x, 59.9, 0.75, "R-2's apocynthion at 126 h: 59.9 nmi, as R-2 predicted")
	assert_almost_eq(model.y, 59.3, 0.75, "and pericynthion: 59.3")
	assert_gt(grail.x - grail.y, 4.0, "GRAIL's orbit out of round")
	assert_lt(model.x - model.y, 1.5, "R-2's round")


func test_the_onboard_state_vector_drifts_kilometres_from_truth_in_lunar_orbit() -> void:
	# The CMC's model has R-2 for the mascons, and no Earth below 800 km.
	build("lunar_orbit")
	var truth := rt.dynamics.traj.clone()
	var cmc := truth.clone().as_onboard(Trajectory.Model.CMC)
	var t_end := truth.t + 4.0 * 3600.0
	truth.coast_to(t_end, 60.0)
	cmc.coast_to(t_end, 60.0)
	var off := truth.pos().distance_to(cmc.pos())
	gut.p("from the same state, in two revolutions the CMC's model comes %.2f km from truth" % (off / 1000.0))
	assert_between(off, 1000.0, 20000.0, "kilometres in two revolutions")


func test_a_round_orbit_would_have_gone_further_out_of_round() -> void:
	# Apollo 10's approach: LOI-2 onto a round 60 nmi orbit. By the
	# rendezvous it would have come to 55.7 by 67.3 nmi, 11.6 out of
	# round, where the flown one came to 5.8, the report estimated
	# [published: MSC-00171, sections 7.4.4 and 7.7]. The estimate took in
	# the CSM's separation maneuver, which isn't flown here: the check is
	# how far out of round the orbit goes.
	build("lunar_orbit")
	var tr := rt.dynamics.traj.clone()
	var r_site := rt.sequencer.landing_site().length()
	var u := tr.pos().normalized()
	var h := tr.pos().cross(tr.vel()).normalized()
	var r := r_site + 60.0 * NMI
	var s := PackedFloat64Array()
	var v := h.cross(u) * sqrt(Bodies.MU_MOON / r)
	for x in [u * r, v]:
		for i in 3:
			s.append(float(x[i]))
	tr.set_state_d(tr.primary, tr.t, s)
	tr.coast_to(126.0 * 3600.0, 60.0, Rtcc.FRAC)
	var ap := _apsides(tr)
	gut.p("a round 60 nmi orbit from LOI-2 comes to %.1f by %.1f nmi at 126 h (the report's estimate: 67.3 by 55.7)" % [ap.x, ap.y])
	assert_almost_eq(ap.x - ap.y, 11.6, 2.5, "out of round as the report estimated")
	assert_almost_eq((ap.x + ap.y) / 2.0, 60.0, 1.0, "about the height it started at")

## Slice 9b (docs/ROADMAP.md): the LGC's Executive. Its pool of eight core
## sets and five VAC areas, the alarm each brings when it runs out, the
## jobs run by priority, the rendezvous radar's CDUs counting only on
## Apollo 11's Luminary 1A away from LGC, the crew's monitor and the
## restart's display, and a checkpoint. Apollo 11's landing with its alarms
## is tests/scenarios/test_program_alarms.gd's.
extends SimTest


## A job every [param period_s] s that needs [param duty] of the time.
static func _job(period_s: float, duty: float, vac: bool, priority: int = 10) -> Dictionary:
	return {"period_s": period_s, "phase_s": 0.0, "priority": priority, "vac": vac, "duty": duty}


## Step [param ex] every 0.02 s for [param seconds] s from [param t0], the
## interrupts taking [param interrupts]; returns the first alarm and when.
static func _run(ex: LgcExecutive, wanted: Dictionary, seconds: float, interrupts: float, t0: float = 0.0) -> Array:
	var t := t0
	while t < t0 + seconds:
		var code := ex.step(0.02, t, wanted, interrupts)
		if code != 0:
			return [code, t]
		t += 0.02
	return [0, t]


func test_no_core_set_is_1202_and_no_vac_area_1201() -> void:
	# With the interrupts taking all its time, no job ends.
	var ex := LgcExecutive.new()
	var r := _run(ex, {"novac": _job(1.0, 0.1, false)}, 20.0, 1.0)
	assert_eq(r[0], LgcExecutive.NO_CORE_SETS, "1202 when the eight core sets are held")
	assert_almost_eq(float(r[1]), 8.0, 0.03, "at the ninth job")
	assert_eq(ex.jobs, [], "the restart drops every job")
	ex = LgcExecutive.new()
	r = _run(ex, {"vac": _job(1.0, 0.1, true)}, 20.0, 1.0)
	assert_eq(r[0], LgcExecutive.NO_VAC_AREAS, "1201 when the five VAC areas are held")
	assert_almost_eq(float(r[1]), 5.0, 0.03, "at the sixth")
	# A VAC job finds its VAC area before its core set, as FINDVAC does.
	ex = LgcExecutive.new()
	r = _run(ex, {"novac": _job(0.5, 0.1, false), "vac": _job(1.0, 0.1, true)}, 20.0, 1.0)
	assert_eq(r[0], LgcExecutive.NO_CORE_SETS, "the core sets go first with more jobs than VAC areas")


func test_the_highest_priority_job_runs_first() -> void:
	var ex := LgcExecutive.new()
	var wanted := {"low": _job(10.0, 0.05, false, 4), "high": _job(10.0, 0.05, false, 20)}
	ex.step(0.02, 0.0, wanted, 0.0)
	assert_eq(ex.jobs.map(func(j: Dictionary) -> String: return j["name"]), ["high", "low"])
	# 0.5 s of work each: the high one ends first, half a second in.
	_run(ex, wanted, 0.5, 0.0, 0.02)
	assert_eq(ex.jobs.map(func(j: Dictionary) -> String: return j["name"]), ["low"])
	assert_almost_eq(float(ex.jobs[0]["left"]), 0.48, 0.021, "the low one waited")


func test_a_load_within_the_computer_never_alarms() -> void:
	var ex := LgcExecutive.new()
	var jobs: Dictionary = SpacecraftData.section("lgc_executive")["jobs"]
	var wanted := {"servicer": (jobs["servicer"] as Dictionary).merged({"duty": 0.70}, true),
		"landing_radar": jobs["landing_radar"], "monitor": (jobs["monitor"] as Dictionary).merged({"duty": 0.04}, true)}
	var r := _run(ex, wanted, 120.0, 0.12)
	assert_eq(r[0], 0, "P63 with the radar and N68: 90 % of the LGC")
	assert_almost_eq(ex.load, 0.90, 1e-6)
	r = _run(ex, wanted, 60.0, 0.12 + 11100.0 * 1.17e-5, 120.0)
	assert_eq(r[0], LgcExecutive.NO_CORE_SETS, "and 13 % more is more than it has: the monitor's jobs pile up")
	assert_lt(float(r[1]) - 120.0, 20.0, "within seconds")


func test_the_radar_counts_on_luminary_1a_away_from_lgc() -> void:
	build("lunar_orbit", "apollo_11")
	var lgc := rt.lgc()
	assert_false(lgc.rr_cdu_zeroed, "Apollo 11: Luminary 1A")
	assert_eq(int(Bus.get_value("ctl.lm.rr_mode")), 1, "AUTO TRACK")
	var e := SpacecraftData.section("lgc_executive")
	var rr := float(e["rr_cdu_pps"]) * float(e["counter_pulse_s"])
	assert_almost_eq(rr, 0.13, 0.001, "13 % of the LGC, 11.7 µs a pulse")
	assert_lt(float(e["rr_cdu_pps_max"]) * float(e["counter_pulse_s"]), 0.151, "15 % at most")
	assert_almost_eq(lgc.interrupt_duty(), float(e["interrupt_duty"]) + rr, 1e-9)
	for mode in [2, 0]:
		Bus.set_value("ctl.lm.rr_mode", mode)
		assert_eq(lgc.rr_counting(), mode != 0, "SLEW counts, LGC doesn't")
	build("lunar_orbit", "apollo_12")
	assert_true(rt.lgc().rr_cdu_zeroed, "Apollo 12: Luminary 1B zeroes the CDUs")
	Bus.set_value("ctl.lm.rr_mode", 1)
	assert_false(rt.lgc().rr_counting())
	assert_almost_eq(rt.lgc().interrupt_duty(), float(e["interrupt_duty"]), 1e-9)


func test_the_crews_monitor_and_the_restarts_display() -> void:
	var d := Dsky.new()
	d.show(6, 63)
	assert_eq(d.crew_monitor(), 0, "the program's display")
	d.press("VERB")
	assert_true(d.lamps["key_rel"], "the crew takes the display")
	d.show(16, 68, false, false)
	assert_eq(d.crew_monitor(), 68, "V16N68, the crew's")
	d.restart_display()
	assert_eq([d.verb, d.noun], ["06", "63"], "the restart brings the program's display back")
	assert_false(d.lamps["key_rel"])
	assert_eq(d.crew_monitor(), 0)
	d.show(16, 64)
	assert_eq(d.crew_monitor(), 0, "the program's own V16")


func test_a_checkpoint_keeps_the_jobs_and_the_restarts() -> void:
	build("lunar_orbit", "apollo_11")
	var lgc := rt.lgc()
	var ex := lgc.executive
	_run(ex, {"servicer": _job(2.0, 0.7, true, 20), "monitor": _job(1.0, 0.04, false, 4)}, 3.1, 0.25)
	lgc.restarts = 2
	lgc.restart_get = 1234.5
	lgc.restart_alarm = 1202
	lgc.failreg = [1202, 1202, 0]
	var jobs := ex.jobs.duplicate(true)
	var next := ex.next_get.duplicate()
	var text := JSON.stringify(rt.snapshot())
	build("", "apollo_11")
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	lgc = rt.lgc()
	assert_eq(lgc.executive.jobs.size(), jobs.size(), "the jobs waiting")
	for i in jobs.size():
		assert_eq(lgc.executive.jobs[i]["name"], jobs[i]["name"])
		assert_almost_eq(float(lgc.executive.jobs[i]["left"]), float(jobs[i]["left"]), 1e-9)
	assert_eq(lgc.executive.next_get, next, "and when each comes next")
	assert_eq([lgc.restarts, lgc.restart_get, lgc.restart_alarm], [2, 1234.5, 1202])
	assert_eq(lgc.failreg, [1202, 1202, 0], "the alarm registers")
	assert_eq(int(Bus.get_value("lm.guid.restarts")), 2)

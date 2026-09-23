## Slice 3b's check (docs/ROADMAP.md, milestone 3): the LM's own computer
## flies descent orbit insertion. Eagle undocks in lunar orbit, Mission
## Control uplinks a DOI PAD to the LGC, and the crew flies it with P30 and
## P40 on the descent engine: 10 % throttle for 15 s, then 40 %, as Apollo
## 11 did. Half a revolution later Eagle passes its pericynthion at the
## PAD's 50,000 ft, while Columbia flies on in its own orbit.
extends SimTest

## The PAD's pericynthion target, m (mission.json "doi").
const TARGET_M := 15240.0


func _undock() -> void:
	Bus.set_value("ctl.cmc.mode", 0)
	Bus.set_value("ctl.seq.undock", true)
	run(1.0, false)
	Bus.set_value("ctl.seq.undock", false)


func test_a_doi_pad_flown_on_the_lgc_reaches_its_pericynthion() -> void:
	build("lunar_orbit")
	_undock()
	run(600.0)   # Eagle drifts clear of Columbia
	var csm_peri := float(Bus.get_value("dyn.peri_alt_m"))
	var csm_apo := float(Bus.get_value("dyn.apo_alt_m"))
	# The PAD goes to the LGC, not the CMC.
	Bus.set_value("ctl.ground.pad_request", "doi")
	var pad: Dictionary = rt.sequencer.last_pad
	assert_eq(str(pad.get("name", "")), "DOI", "a DOI PAD")
	gut.p(Rtcc.pad_text(pad))
	assert_almost_eq(float(pad["hp"]), TARGET_M, 50.0, "planned to 50,000 ft")
	var dv_lvlh: Vector3 = pad["dv_lvlh"]
	assert_lt(dv_lvlh.x, 0.0, "retrograde")
	assert_true(Bus.get_value("lm.dsky.lamp.uplink_acty"), "UPLINK ACTY on the LGC's DSKY")
	assert_false(Bus.get_value("dsky.lamp.uplink_acty"), "and not on the CMC's")
	assert_eq(rt.lgc().dv_lvlh_load, dv_lvlh, "in the LGC's P30 registers")
	assert_eq(rt.agc().dv_lvlh_load, Vector3.ZERO, "not the CMC's")
	var dps0 := float(Bus.get_value("lm.dps.prop_kg"))
	var m0 := rt.dynamics.lm.mass
	var tig := float(pad["tig"])
	var throttle := {}
	var dv := fly_lm_pad(40, 2, func() -> void:
		throttle[roundi(SimClock.get_seconds - tig)] = float(Bus.get_value("lm.dps.throttle_pct")))
	assert_almost_eq(float(throttle.get(5, 0.0)), 10.0, 0.5, "10 % throttle 5 s after ignition")
	assert_almost_eq(float(throttle.get(20, 0.0)), 40.0, 0.5, "40 % from 15 s")
	assert_almost_eq(dv, dv_lvlh.length(), 0.05, "the PAD's ΔV")
	assert_eq(int(Bus.get_value("lm.dps.ignitions")), 1, "one DPS start")
	assert_eq(int(Bus.get_value("lm.aps.ignitions")), 0, "the ascent engine stays cold")
	assert_eq(int(Bus.get_value("sps.ignitions")), 0, "and so does Columbia's SPS")
	var used := dps0 - float(Bus.get_value("lm.dps.prop_kg"))
	var ideal := m0 * (1.0 - exp(-dv / (float(SpacecraftData.section("dps")["isp_s"]) * Units.G0)))
	assert_almost_eq(used, ideal, 1.0, "DPS propellant as the rocket equation has it")
	# Coast to the pericynthion, half a revolution on.
	var box := {"prev": float(Bus.get_value("lm.dyn.alt_rate_mps")), "min": INF, "t": 0.0}
	var found := run_until(func() -> bool:
		var alt := float(Bus.get_value("lm.dyn.alt_m"))
		if alt < box["min"]:
			box["min"] = alt
			box["t"] = SimClock.get_seconds
		var rr := float(Bus.get_value("lm.dyn.alt_rate_mps"))
		var passed: bool = box["prev"] < 0.0 and rr >= 0.0
		box["prev"] = rr
		return passed, 7200.0, 10.0)
	assert_true(found, "passed the pericynthion")
	var hp: float = box["min"]
	gut.p("Eagle's pericynthion: %.0f m (%.0f ft) at %s; the PAD's: %.0f m at %s" % [hp, hp / Units.FT,
		Units.hms(box["t"]), float(pad["hp"]), Units.hms(float(pad["hp_get"]))])
	assert_almost_eq(hp, TARGET_M, 250.0, "at its pericynthion target")
	assert_almost_eq(float(box["t"]), float(pad["hp_get"]), 30.0, "when the PAD had it")
	# Columbia flew on in its own orbit.
	assert_almost_eq(float(Bus.get_value("dyn.peri_alt_m")), csm_peri, 1000.0, "Columbia's pericynthion")
	assert_almost_eq(float(Bus.get_value("dyn.apo_alt_m")), csm_apo, 1000.0, "and apocynthion")


func test_no_doi_pad_while_the_lm_is_docked() -> void:
	build("lunar_orbit")
	assert_true(rt.sequencer.request_pad("doi").is_empty(), "no DOI with Eagle docked")
	assert_string_contains(str(Bus.get_value("mission.capcom")), "no DOI solution")
	assert_false(rt.lgc().dsky.lamps["uplink_acty"], "nothing uplinked")

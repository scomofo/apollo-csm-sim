## Slice 6a: the audio director (src/presentation/audio_director.gd). Bus
## events start and stop its voices. Headless it plays nothing: it counts
## its one-shots (audio.events) and publishes its continuous voices' gains
## (audio.<voice>_gain), which these tests read.
extends SimTest


func before_each() -> void:
	Bus.reset()
	SimClock.reset()


func _director() -> AudioDirector:
	return add_child_autofree(AudioDirector.new())


func _events() -> Dictionary:
	return Bus.get_value("audio.events", {})


## [param voice]'s gain as the director's next frame sets it.
func _gain(a: AudioDirector, voice: String) -> float:
	a._process(0.0)
	return float(Bus.get_value("audio.%s_gain" % voice, -1.0))


func test_crew_controls_click_by_their_type() -> void:
	var a := _director()
	assert_false(a.enabled, "headless: counted, not played")
	Bus.set_value("ctl.els.logic", true)       # a toggle, both ways
	Bus.set_value("ctl.els.logic", false)
	Bus.set_value("ctl.scs.att_source", 1)     # a rotary
	Bus.set_value("ctl.els.drogue", true)      # a pushbutton's press
	Bus.set_value("ctl.els.drogue", false)     # and its silent release
	Bus.set_value("ctl.sps.thrust_on", true)   # the HUD's own hold-button
	Bus.set_value("ctl.sps.thrust_on", false)
	Bus.set_value("ctl.rhc", Vector3(0.5, 0.0, 0.0))
	Bus.set_value("ctl.optics.hc", Vector3(0.0, 0.2, 0.0))
	Bus.set_value("ctl.ground.pad_request", "tei")
	assert_eq(_events(), {"click": 2, "rotary": 1, "button": 2}, "no click from the hand controllers or the ground")
	assert_eq(Bus.get_value("audio.last"), "button")


func test_every_dsky_key_clicks() -> void:
	build("lunar_orbit")
	var a := _director()
	keys("V16N62E")
	assert_eq(a.counts.get("key", 0), 7, "V 1 6 N 6 2 E")
	assert_eq(int(Bus.get_value("dsky.key_presses")), 7)
	# Docked, Eagle's DSKY is heard from Columbia's cabin too.
	keys("V37E", rt.lgc())
	assert_eq(a.counts.get("key", 0), 11)


func test_each_cabin_hears_its_own() -> void:
	var a := _director()
	Bus.set_value("dock.state", "free")
	Bus.set_value("player.vehicle", "csm")
	# Eagle's, while the player is in Columbia: unheard.
	Bus.set_value("ctl.lm.engine_arm", 2)
	Bus.set_value("lm.dsky.key_presses", 1)
	Bus.set_value("lm.rcs.active_jets", 2)
	Bus.set_value("mission.event.lm_landing", 102.75 * 3600.0)
	Bus.set_value("lm.dps.thrust_n", 20000.0)
	Bus.set_value("lm.dps.throttle_pct", 60.0)
	assert_eq(_gain(a, "dps"), 0.0)
	assert_eq(_events(), {})
	Bus.set_value("player.vehicle", "lm")
	assert_gt(_gain(a, "dps"), 0.0, "aboard Eagle")
	Bus.set_value("ctl.lm.engine_arm", 0)
	Bus.set_value("lm.dsky.key_presses", 2)
	Bus.set_value("lm.rcs.active_jets", 4)
	Bus.set_value("mission.event.lm_staging", 124.3 * 3600.0)
	# Columbia's, from Eagle: unheard.
	Bus.set_value("ctl.cmc.mode", 2)
	Bus.set_value("sps.chamber_pct", 100.0)
	assert_eq(_gain(a, "sps"), 0.0)
	assert_eq(_events(), {"click": 1, "key": 1, "thump": 1, "pyro": 1})
	# Docked, either cabin's are heard.
	Bus.set_value("player.vehicle", "csm")
	Bus.set_value("dock.state", "docked")
	Bus.set_value("lm.dsky.key_presses", 3)
	assert_eq(_events()["key"], 2)
	# Undocking is heard in both.
	Bus.set_value("dock.state", "free")
	Bus.set_value("mission.event.undocking", 100.2 * 3600.0)
	assert_eq(_events()["latch"], 1)


func test_the_jets_thump_as_they_start_and_hiss_while_they_fire() -> void:
	var a := _director()
	assert_eq(_gain(a, "jets"), 0.0)
	Bus.set_value("rcs.active_jets", 2)
	assert_gt(_gain(a, "jets"), 0.0, "firing")
	Bus.set_value("rcs.active_jets", 4)        # two more start
	Bus.set_value("rcs.active_jets", 3)        # one stops: no thump
	Bus.set_value("rcs.active_jets", 0)
	assert_eq(_gain(a, "jets"), 0.0, "the hiss stops with the jets")
	Bus.set_value("rcs.active_jets", 1)
	assert_eq(_events(), {"thump": 3})


func test_the_engines_start_and_stop_their_voices() -> void:
	var a := _director()
	for voice: String in AudioDirector.LAYERS:
		assert_eq(_gain(a, voice), 0.0, "%s silent at first" % voice)
	# The Saturn V: the S-IC's five engines, four after the centre engine's
	# cutoff, the S-II's, and the S-IVB's J-2.
	Bus.set_value("lv.stage", "S-IC")
	Bus.set_value("lv.engines", 5)
	Bus.set_value("lv.thrust_n", 3.4e7)
	assert_almost_eq(_gain(a, "saturn"), 0.9, 1e-6)
	Bus.set_value("lv.engines", 4)
	assert_almost_eq(_gain(a, "saturn"), 0.72, 1e-6)
	Bus.set_value("lv.stage", "S-II")
	Bus.set_value("lv.engines", 5)
	assert_almost_eq(_gain(a, "saturn"), 0.45, 1e-6)
	Bus.set_value("lv.stage", "S-IVB")
	Bus.set_value("lv.engines", 1)
	assert_eq(_gain(a, "saturn"), 0.0, "the S-II gone")
	assert_gt(_gain(a, "sivb"), 0.0, "the S-IVB's first burn")
	Bus.set_value("lv.thrust_n", 0.0)
	assert_eq(_gain(a, "sivb"), 0.0, "insertion")
	Bus.set_value("sivb.thrust_n", 9.0e5)
	assert_gt(_gain(a, "sivb"), 0.0, "TLI")
	Bus.set_value("sivb.thrust_n", 0.0)
	assert_eq(_gain(a, "sivb"), 0.0)
	# The SPS, by its chamber pressure.
	Bus.set_value("sps.chamber_pct", 100.0)
	assert_almost_eq(_gain(a, "sps"), 0.6, 1e-6)
	Bus.set_value("sps.chamber_pct", 40.0)
	assert_almost_eq(_gain(a, "sps"), 0.24, 1e-6, "the shutdown's tail-off")
	Bus.set_value("sps.chamber_pct", 0.0)
	assert_eq(_gain(a, "sps"), 0.0)
	# Eagle's, aboard Eagle: the descent engine by its throttle, the ascent
	# engine by its chamber pressure.
	Bus.set_value("player.vehicle", "lm")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.dps.thrust_n", 4500.0)
	Bus.set_value("lm.dps.throttle_pct", 10.0)
	assert_almost_eq(_gain(a, "dps"), 0.235, 1e-6)
	Bus.set_value("lm.dps.throttle_pct", 100.0)
	assert_almost_eq(_gain(a, "dps"), 0.55, 1e-6)
	Bus.set_value("lm.dps.thrust_n", 0.0)
	assert_eq(_gain(a, "dps"), 0.0)
	Bus.set_value("lm.aps.chamber_pct", 100.0)
	assert_almost_eq(_gain(a, "aps"), 0.5, 1e-6)
	Bus.set_value("lm.aps.chamber_pct", 0.0)
	assert_eq(_gain(a, "aps"), 0.0)


func test_the_air_the_fans_the_breathing_and_the_pause() -> void:
	var a := _director()
	Bus.set_value("dyn.q_pa", 10000.0)
	assert_almost_eq(_gain(a, "rumble"), 0.4, 1e-6, "half of max-Q's rumble")
	Bus.set_value("dyn.q_pa", 0.0)
	assert_eq(_gain(a, "rumble"), 0.0)
	Bus.set_value("sys.powered", true)
	assert_gt(_gain(a, "fan"), 0.0, "the CM powered: its fans run")
	Bus.set_value("dyn.g_load", 5.0)
	assert_almost_eq(_gain(a, "breath"), 0.5, 1e-6, "breathing hard at 5 g")
	Bus.set_value("dyn.g_load", 3.0)
	assert_eq(_gain(a, "breath"), 0.0)
	# Paused, the world's voices hush.
	Bus.set_value("rcs.active_jets", 2)
	SimClock.paused = true
	for voice: String in ["fan", "jets"]:
		assert_eq(_gain(a, voice), 0.0, "%s paused" % voice)
	SimClock.paused = false
	assert_gt(_gain(a, "fan"), 0.0)
	Bus.set_value("sys.powered", false)
	assert_eq(_gain(a, "fan"), 0.0, "no power, no fans")
	# Eagle's fans, while it flies.
	Bus.set_value("player.vehicle", "lm")
	Bus.set_value("dock.state", "free")
	assert_gt(_gain(a, "fan"), 0.0)


func test_the_flights_events_and_the_parachutes() -> void:
	var a := _director()
	Bus.set_value("mission.event.max_q", 83.0)             # silent
	Bus.set_value("mission.event.staging", 162.0)          # the S-IC's separation
	Bus.set_value("mission.event.les_jettison", 197.9)
	Bus.set_value("mission.event.phase_entry", 194.8 * 3600.0)
	Bus.set_value("mission.event.cm_sm_sep", 194.8 * 3600.0)
	Bus.set_value("els.drogue", true)
	Bus.set_value("els.drogue", false)                     # released as the mains open
	Bus.set_value("els.mains", true)
	Bus.set_value("mission.event.landing", 195.3 * 3600.0)
	assert_eq(_events(), {"pyro": 3, "mortar": 2, "splash": 1})
	# Each docking's latches: the same event again, at a new time.
	Bus.set_value("mission.event.docking", 128.0 * 3600.0)
	Bus.set_value("mission.event.docking", 128.2 * 3600.0)
	assert_eq(_events()["latch"], 2)


func test_every_event_the_flight_fires_has_a_sound_or_none() -> void:
	var re := RegEx.create_from_string("(?:_fire|event_fired\\.emit)\\(\"([a-z0-9_]+)\"")
	var ids := {}
	for path in ["res://src/mission/mission_sequencer.gd", "res://src/systems/launch_vehicle.gd"]:
		for m in re.search_all(FileAccess.get_file_as_string(path)):
			ids[m.get_string(1)] = true
	# And the failure catalog's events, which Failures fires.
	for f: Dictionary in Failures.catalog():
		if f.has("event"):
			ids[str(f["event"])] = true
	assert_gt(ids.size(), 30, "the events found")
	for id: String in ids:
		var prefixed := AudioDirector.SILENT_PREFIXES.any(func(p: String) -> bool: return id.begins_with(p))
		assert_true(AudioDirector.EVENTS.has(id) or id in AudioDirector.SILENT_EVENTS or prefixed,
			"%s has a sound or is listed as silent" % id)
	for id: String in AudioDirector.EVENTS.keys() + AudioDirector.SILENT_EVENTS:
		assert_true(ids.has(id), "%s is an event the flight fires" % id)


func test_the_master_alarm_sounds_until_the_crew_resets_it() -> void:
	build("translunar_coast")
	var a := _director()
	run(60.0)
	assert_eq(_gain(a, "alarm"), 0.0, "all well")
	rt.systems["eps"].fail_o2_tank(2)
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("sys.master_alarm")), 120.0, 5.0, false),
		"CRYO PRESS lights as the tank's pressure falls")
	assert_almost_eq(_gain(a, "alarm"), 0.3, 1e-6, "the tone in the headsets")
	# MASTER ALARM pressed: the tone stops, CRYO PRESS stays lit.
	Bus.set_value("ctl.cw.master_alarm", true)
	run(0.1, false)
	Bus.set_value("ctl.cw.master_alarm", false)
	assert_eq(_gain(a, "alarm"), 0.0, "reset")
	assert_true(bool(Bus.get_value("cw.cryo_press")))
	assert_eq(a.counts.get("button", 0), 1, "the switch-light's own click")
	# FC 1's light comes on 90 s after the tank, and sounds it again.
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("cw.fc1")), 120.0, 5.0, false), "FC 1")
	assert_gt(_gain(a, "alarm"), 0.0, "sounding again")
	Bus.set_value("ctl.cw.master_alarm", true)
	run(0.1, false)
	Bus.set_value("ctl.cw.master_alarm", false)
	# FC 3's light comes on a minute later, and sounds it again.
	assert_true(run_until(func() -> bool: return bool(Bus.get_value("cw.fc3")), 120.0, 5.0, false), "FC 3")
	assert_gt(_gain(a, "alarm"), 0.0, "sounding again")


func test_a_checkpoints_load_is_silent() -> void:
	build("lunar_orbit")
	var snap := rt.snapshot()
	var a := _director()
	Bus.set_value("ctl.cmc.mode", 2)
	Bus.set_value("ctl.sps.arm_a", true)
	assert_eq(_events(), {"click": 2})
	assert_eq(a.hush(rt.restore.bind(snap)), "", "loaded")
	assert_eq(int(Bus.get_value("ctl.cmc.mode")), 1, "the switches back where they were")
	assert_eq(_events(), {"click": 2}, "without a sound")
	Bus.set_value("ctl.cmc.mode", 2)
	assert_eq(_events(), {"click": 3}, "and the cabin's sound goes on")


func test_the_voices_render_as_their_recipes_say() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	for kind: String in AudioDirector.ONE_SHOTS:
		var wav := AudioDirector.render_one_shot(AudioDirector.ONE_SHOTS[kind], rng)
		var s := _samples(wav)
		assert_eq(s.size(), int(float(AudioDirector.ONE_SHOTS[kind]["duration_s"]) * AudioDirector.SAMPLE_RATE), kind)
		assert_almost_eq(_peak(s), 0.9, 0.001, "%s peaks at 0.9" % kind)
		assert_lt(absf(s[s.size() - 1]), 0.1, "%s has died away" % kind)
	for voice: String in AudioDirector.LAYERS:
		var wav := AudioDirector.render_loop(AudioDirector.LAYERS[voice], rng)
		var s := _samples(wav)
		assert_eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, voice)
		assert_eq(wav.loop_end, s.size(), voice)
		assert_eq(s.size(), roundi(float(AudioDirector.LAYERS[voice]["loop_s"]) * AudioDirector.SAMPLE_RATE), voice)
		assert_lt(_peak(s), 0.999, "%s doesn't clip" % voice)
		# Seamless: the step from its end back to its start is no bigger than
		# a step within it.
		var biggest := 0.0
		for i in range(1, s.size()):
			biggest = maxf(biggest, absf(s[i] - s[i - 1]))
		assert_lte(absf(s[0] - s[s.size() - 1]), biggest, "%s loops without a seam" % voice)
	# The master alarm: 750 Hz for 0.4 s, then 2,000 Hz for 0.4 s.
	var alarm := _samples(AudioDirector.render_loop(AudioDirector.LAYERS["alarm"], rng))
	var half := alarm.size() / 2
	assert_almost_eq(_crossings(alarm.slice(0, half)) / 0.4 / 2.0, 750.0, 5.0, "750 Hz")
	assert_almost_eq(_crossings(alarm.slice(half)) / 0.4 / 2.0, 2000.0, 5.0, "then 2,000 Hz")


func _samples(wav: AudioStreamWAV) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(wav.data.size() / 2)
	for i in range(out.size()):
		out[i] = wav.data.decode_s16(i * 2) / 32767.0
	return out


func _peak(s: PackedFloat32Array) -> float:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v))
	return m


func _crossings(s: PackedFloat32Array) -> float:
	var n := 0
	for i in range(1, s.size()):
		if (s[i - 1] < 0.0) != (s[i] < 0.0):
			n += 1
	return float(n)

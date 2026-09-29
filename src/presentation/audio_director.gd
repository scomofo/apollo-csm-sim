## The audio director: the cabin's sound, from the Bus. Adapted from
## gemini-capsule's src/presentation/audio_director.gd at e0a5bd5 (README.md
## lists the port). Every voice is synthesised, with nothing recorded to
## license: Gemini's registry of recorded samples, its archive recordings,
## CAPCOM's quindar tones and its retro-rockets stay behind. Presentation
## only: it reads the Bus and writes nothing but audio.*.
##
## One-shots, each on its Bus event:
##   click, rotary, button  a crew control moving: a toggle's lever, a
##                          rotary's detent, a pushbutton's press (the type
##                          controls.csv or lm_controls.csv gives its
##                          channel); a pushbutton's release is silent
##   key                    a DSKY key (dsky.key_presses, lm.dsky.key_presses)
##   thump                  an attitude jet starting to fire (rcs.active_jets,
##                          lm.rcs.active_jets rising)
##   pyro, latch, shock,    the flight's events (mission.event.<id>, EVENTS):
##   splash                 separations and jettisons, docking and undocking,
##                          Eagle's touchdown, the splashdown
##   mortar                 a parachute's mortar (els.drogue, els.mains)
## Continuous voices, sounding while their channels hold them on (gains()):
##   saturn                 the S-IC and the S-II (lv.stage, lv.engines)
##   sivb                   the S-IVB's J-2 (lv.stage, sivb.thrust_n)
##   sps, dps, aps          the engines (sps.chamber_pct, lm.dps.throttle_pct,
##                          lm.aps.chamber_pct)
##   jets                   the attitude jets while any fire
##   rumble                 the air, by its dynamic pressure (dyn.q_pa)
##   fan                    the cabin's fans while it is powered
##   breath                 the crew's breathing above BREATH_G
##   alarm                  the master alarm's tone (sys.master_alarm)
## Each voice is heard in its vehicle's cabin (player.vehicle), and in either
## while the two are docked [simplified: through the tunnel, at full level].
## The continuous voices hush while the clock is paused. The cabin's bus
## plays at the player's sound level (player.sound_db, dB from as designed,
## the wrist menu's SOUND - and SOUND +).
##
## Headless (the tests), nothing plays: the director counts the one-shots
## (audio.events, audio.last) and publishes the continuous voices' gains
## (audio.<voice>_gain) all the same. Elsewhere it renders every voice once,
## on a worker thread as it starts, then plays the one-shots as they come
## and the continuous voices as seamless loops at their gains: nothing is
## synthesised per frame.
##
## Reads:  ctl.*, dsky.key_presses, lm.dsky.key_presses, rcs.active_jets,
##         lm.rcs.active_jets, mission.event.*, els.drogue, els.mains,
##         lv.thrust_n, lv.stage, lv.engines, sivb.thrust_n, sps.chamber_pct,
##         lm.dps.thrust_n, lm.dps.throttle_pct, lm.aps.chamber_pct,
##         dyn.q_pa, dyn.g_load, sys.powered, sys.master_alarm, dock.state,
##         player.vehicle, player.sound_db
## Writes: audio.events, audio.last, audio.<voice>_gain
class_name AudioDirector
extends Node

const SAMPLE_RATE := 22050.0
## One-shots [estimated: by ear, none measured; click, rotary, button,
## thump, shock and splash are Gemini's, with the low-pass added]:
## duration, tone, the noise's share against the tone, the decay's time
## constant as a fraction of the duration, the noise's low-pass corner (0:
## white), and the level it plays at.
const ONE_SHOTS := {
	"click": {"duration_s": 0.03, "frequency_hz": 3200.0, "noise_mix": 0.7, "decay_time_fraction": 0.35,
		"lowpass_hz": 0.0, "volume_db": -12.0},
	"rotary": {"duration_s": 0.04, "frequency_hz": 1800.0, "noise_mix": 0.5, "decay_time_fraction": 0.35,
		"lowpass_hz": 0.0, "volume_db": -12.0},
	"button": {"duration_s": 0.05, "frequency_hz": 1200.0, "noise_mix": 0.6, "decay_time_fraction": 0.35,
		"lowpass_hz": 0.0, "volume_db": -12.0},
	"key": {"duration_s": 0.02, "frequency_hz": 2600.0, "noise_mix": 0.5, "decay_time_fraction": 0.3,
		"lowpass_hz": 0.0, "volume_db": -14.0},
	"thump": {"duration_s": 0.12, "frequency_hz": 90.0, "noise_mix": 0.9, "decay_time_fraction": 0.35,
		"lowpass_hz": 600.0, "volume_db": -6.0},
	"pyro": {"duration_s": 0.5, "frequency_hz": 70.0, "noise_mix": 0.9, "decay_time_fraction": 0.25,
		"lowpass_hz": 1200.0, "volume_db": 0.0},
	"latch": {"duration_s": 0.25, "frequency_hz": 220.0, "noise_mix": 0.6, "decay_time_fraction": 0.3,
		"lowpass_hz": 2500.0, "volume_db": -4.0},
	"mortar": {"duration_s": 0.45, "frequency_hz": 55.0, "noise_mix": 0.85, "decay_time_fraction": 0.3,
		"lowpass_hz": 800.0, "volume_db": -2.0},
	"shock": {"duration_s": 0.3, "frequency_hz": 70.0, "noise_mix": 0.9, "decay_time_fraction": 0.35,
		"lowpass_hz": 700.0, "volume_db": -2.0},
	"splash": {"duration_s": 0.8, "frequency_hz": 50.0, "noise_mix": 1.0, "decay_time_fraction": 0.35,
		"lowpass_hz": 1500.0, "volume_db": 0.0},
}
## Continuous voices [estimated, but for the alarm's tone]: tones, noise
## (its RMS, and its low-pass corner), a slow random roughness in the
## level (an engine's), a sinusoidal swell (Gemini's breathing), and the
## loop's length. Fan and breath are Gemini's, low-passed.
const LAYERS := {
	"saturn": {"harmonics": [{"frequency_hz": 28.0, "amplitude": 0.3}, {"frequency_hz": 56.0, "amplitude": 0.15}],
		"noise_amplitude": 1.0, "lowpass_hz": 250.0, "roughness": 0.6, "loop_s": 3.0},
	"sivb": {"harmonics": [{"frequency_hz": 45.0, "amplitude": 0.15}], "noise_amplitude": 1.0, "lowpass_hz": 300.0,
		"roughness": 0.15, "loop_s": 3.0},
	"sps": {"harmonics": [{"frequency_hz": 36.0, "amplitude": 0.25}, {"frequency_hz": 72.0, "amplitude": 0.1}],
		"noise_amplitude": 1.0, "lowpass_hz": 220.0, "roughness": 0.1, "loop_s": 3.0},
	"dps": {"harmonics": [{"frequency_hz": 42.0, "amplitude": 0.1}], "noise_amplitude": 1.0, "lowpass_hz": 350.0,
		"roughness": 0.1, "loop_s": 3.0},
	"aps": {"harmonics": [{"frequency_hz": 55.0, "amplitude": 0.15}], "noise_amplitude": 1.0, "lowpass_hz": 600.0,
		"roughness": 0.35, "loop_s": 3.0},
	"jets": {"harmonics": [], "noise_amplitude": 1.0, "lowpass_hz": 2500.0, "loop_s": 2.0},
	"rumble": {"harmonics": [], "noise_amplitude": 1.0, "lowpass_hz": 500.0, "roughness": 0.3, "loop_s": 3.0},
	"fan": {"harmonics": [{"frequency_hz": 118.0, "amplitude": 0.5}, {"frequency_hz": 236.0, "amplitude": 0.25}],
		"noise_amplitude": 0.15, "lowpass_hz": 3000.0, "loop_s": 2.0},
	"breath": {"harmonics": [], "noise_amplitude": 0.6, "lowpass_hz": 1200.0, "modulation_frequency_hz": 0.4,
		"modulation_depth": 1.0, "loop_s": 5.0},
	## A square wave alternately 750 and 2,000 Hz, changing 2.5 times a
	## second [published: CSM Apollo Operations Handbook, SM2A-03-BLOCK
	## II-(1), 2.10.3, p. 2.10-2], band-limited to the sample rate.
	"alarm": {"square_hz": [750.0, 2000.0], "square_rate_hz": 2.5, "loop_s": 0.8},
}
## The flight's events that sound (mission.event.<id>): [one-shot, the
## vehicle whose cabin hears it, "both" for either]. Every other event the
## sequencer fires is in SILENT_EVENTS or starts with a SILENT_PREFIXES
## entry (test_audio_director.gd checks the sources against both).
const EVENTS := {
	"liftoff": ["shock", "csm"],                 # the holddown arms let go
	"staging": ["pyro", "csm"],                  # the S-IC's separation
	"interstage_jettison": ["pyro", "csm"],      # the S-II's aft interstage
	"les_jettison": ["pyro", "csm"],             # the launch escape tower
	"s2_staging": ["pyro", "csm"],               # the S-II's separation
	"transposition_docking": ["pyro", "csm"],    # CSM/LV SEP and the adapter's panels
	"csm_lv_sep": ["pyro", "csm"],               # the same, with no LM to dock with
	"docking_contact": ["latch", "both"],        # the probe meets the drogue
	"docking": ["latch", "both"],                # the capture latches
	"undocking": ["latch", "both"],
	"lm_jettison": ["pyro", "csm"],
	"lm_staging": ["pyro", "lm"],
	"lm_landing": ["shock", "lm"],
	"o2_tank_2_failure": ["shock", "csm"],       # Apollo 13's bang
	"cm_sm_sep": ["pyro", "csm"],
	"landing": ["splash", "csm"],
}
## Events with no sound of their own: an engine's start or stop is its
## continuous voice's.
const SILENT_EVENTS := ["ignition", "thrust_ok", "tilt", "mach_1", "max_q", "sic_ceco", "sic_oeco", "s2_ignition",
	"igm", "s2_ceco", "emr_shift", "s2_oeco", "s4_ignition", "s4_cutoff", "insertion", "tli_ignition", "tli_cutoff",
	"lm_liftoff", "lm_insertion"]
const SILENT_PREFIXES := ["start_", "phase_", "pad_", "timeline_"]
## Channels that move continuously (the hand controllers) or aren't the
## cabin's (the ground's): no click.
const QUIET_CONTROLS := ["ctl.rhc", "ctl.thc", "ctl.lm.rhc", "ctl.lm.thc", "ctl.optics.hc"]
const QUIET_CONTROL_PREFIXES := ["ctl.ground."]
## Breathing is audible above this load, g (Gemini's VR_INTERACTION.md §4).
const BREATH_G := 3.5
## The dynamic pressure at which the air's rumble is at its loudest, Pa
## (Gemini's).
const RUMBLE_Q_PA := 20000.0
## The audio bus the voices play on, which a hard limiter keeps from
## clipping when a pyro goes off over an engine.
const BUS := "Cabin"
## How fast a continuous voice comes up or goes down, s from silence to
## full: no click as a loop starts or stops.
const RAMP_S := 0.06
## A one-shot plays at most this often, s; a faster run of its events is
## counted all the same (the DAP's jets at a high time rate).
const REPEAT_S := 0.03

var counts: Dictionary = {}
var last: String = ""
## Off in headless tests: no rendering, no playback, only the counts and
## gains.
var enabled: bool = true
var _players: Dictionary = {}   # voice -> AudioStreamPlayer
var _level: Dictionary = {}     # continuous voice -> its level now, 0 to 1
var _played_ms: Dictionary = {} # one-shot -> when it last played
var _control_types: Dictionary = {}
var _seen: Dictionary = {}      # an edge channel -> its last value
var _hushed: bool = false
var _rng := RandomNumberGenerator.new()
var _render_task: int = -1
var _rendered: Dictionary = {}  # voice -> AudioStreamWAV, from the worker


func _ready() -> void:
	_rng.seed = 4
	enabled = DisplayServer.get_name() != "headless"
	for layout in [CockpitLayout.load_default(), CockpitLayout.load_lm()]:
		for r in layout.rows:
			if CockpitLayout.TYPES.has(r["type"]) and CockpitLayout.TYPES[r["type"]]["control"]:
				_control_types[r["channel"]] = r["type"]
	for ch in ["dsky.key_presses", "lm.dsky.key_presses", "rcs.active_jets", "lm.rcs.active_jets"]:
		_seen[ch] = int(Bus.get_value(ch, 0))
	for ch in ["els.drogue", "els.mains"]:
		_seen[ch] = bool(Bus.get_value(ch, false))
	Bus.value_changed.connect(_on_bus)
	if not enabled:
		return
	if AudioServer.get_bus_index(BUS) < 0:
		AudioServer.add_bus()
		var bus := AudioServer.bus_count - 1
		AudioServer.set_bus_name(bus, BUS)
		AudioServer.set_bus_send(bus, "Master")
		AudioServer.add_bus_effect(bus, AudioEffectHardLimiter.new())
	_apply_level()
	for voice in ONE_SHOTS.keys() + LAYERS.keys():
		var p := AudioStreamPlayer.new()
		p.name = voice.capitalize().replace(" ", "")
		p.bus = BUS
		if ONE_SHOTS.has(voice):
			p.max_polyphony = 4
			p.volume_db = float(ONE_SHOTS[voice]["volume_db"])
		add_child(p)
		_players[voice] = p
	_render_task = WorkerThreadPool.add_task(_render_all, false, "AudioDirector voices")


func _exit_tree() -> void:
	if _render_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_render_task)
		_render_task = -1


## The cabin's bus at the player's sound level.
func _apply_level() -> void:
	var bus := AudioServer.get_bus_index(BUS)
	if enabled and bus >= 0:
		AudioServer.set_bus_volume_db(bus, float(Bus.get_value("player.sound_db", 0.0)))


## Run [param f] (a checkpoint's load) without a sound: what it puts back on
## the Bus happened before. Returns what [param f] returns.
func hush(f: Callable) -> Variant:
	_hushed = true
	var out: Variant = f.call()
	_hushed = false
	return out


func _on_bus(channel: String, value: Variant) -> void:
	if channel == "player.sound_db":
		_apply_level()
	elif channel.begins_with("ctl."):
		_on_control(channel, value)
	elif channel.begins_with("mission.event."):
		var id := channel.trim_prefix("mission.event.")
		if EVENTS.has(id):
			_play(EVENTS[id][0], EVENTS[id][1])
	elif _seen.has(channel):
		var was: Variant = _seen[channel]
		_seen[channel] = value
		var vehicle := "lm" if channel.begins_with("lm.") else "csm"
		if channel.ends_with("key_presses"):
			if int(value) > int(was):
				_play("key", vehicle)
		elif channel.ends_with("active_jets"):
			if int(value) > int(was):
				_play("thump", vehicle)
		elif bool(value) and not bool(was):
			_play("mortar", "csm")


## A crew control moved: its cabin's click, by the type of control.
func _on_control(channel: String, value: Variant) -> void:
	if channel in QUIET_CONTROLS:
		return
	for p: String in QUIET_CONTROL_PREFIXES:
		if channel.begins_with(p):
			return
	var kind := "click"
	match str(_control_types.get(channel, "")):
		"rotary":
			kind = "rotary"
		"pushbutton":
			if not bool(value):
				return   # a pushbutton's release is silent
			kind = "button"
		"toggle":
			kind = "click"
		_:
			# The HUD's own (SPS THRUST ON): as Gemini's, by the value.
			if value is bool:
				if not value:
					return
				kind = "button"
	_play(kind, "lm" if channel.begins_with("ctl.lm.") else "csm")


## Whether the player hears [param vehicle]'s voices: aboard it, or with
## the two docked.
func _heard(vehicle: String) -> bool:
	if vehicle == "both":
		return true
	var aboard := str(Bus.get_value("player.vehicle", "csm"))
	if aboard == "":
		aboard = "csm"
	return vehicle == aboard or str(Bus.get_value("dock.state", "")) == "docked"


func _count(kind: String) -> void:
	counts[kind] = counts.get(kind, 0) + 1
	last = kind
	Bus.set_value("audio.events", counts.duplicate())
	Bus.set_value("audio.last", kind)


func _play(kind: String, vehicle: String) -> void:
	if _hushed or not _heard(vehicle):
		return
	_count(kind)
	if not enabled:
		return
	var p: AudioStreamPlayer = _players[kind]
	var now := Time.get_ticks_msec()
	if p.stream == null or now - int(_played_ms.get(kind, -100000)) < int(REPEAT_S * 1000.0):
		return
	_played_ms[kind] = now
	p.pitch_scale = _rng.randf_range(0.96, 1.04)
	p.play()


## Each continuous voice's gain now, 0 to 1 [estimated: the levels set by
## ear against each other].
func gains() -> Dictionary:
	var g := {}
	for v: String in LAYERS:
		g[v] = 0.0
	if SimClock.paused:
		return g
	var aboard := str(Bus.get_value("player.vehicle", "csm"))
	if _heard("csm"):
		var stage := str(Bus.get_value("lv.stage", ""))
		var boost := float(Bus.get_value("lv.thrust_n", 0.0)) > 0.0
		var engines := clampf(float(Bus.get_value("lv.engines", 0)) / 5.0, 0.0, 1.0)
		if boost and stage == "S-IC":
			g["saturn"] = 0.9 * engines
		elif boost and stage == "S-II":
			g["saturn"] = 0.45 * engines
		if (boost and stage == "S-IVB") or float(Bus.get_value("sivb.thrust_n", 0.0)) > 0.0:
			g["sivb"] = 0.35
		g["sps"] = 0.6 * clampf(float(Bus.get_value("sps.chamber_pct", 0.0)) / 100.0, 0.0, 1.0)
		g["rumble"] = 0.8 * clampf(float(Bus.get_value("dyn.q_pa", 0.0)) / RUMBLE_Q_PA, 0.0, 1.0)
	if _heard("lm"):
		if float(Bus.get_value("lm.dps.thrust_n", 0.0)) > 0.0:
			g["dps"] = 0.2 + 0.35 * clampf(float(Bus.get_value("lm.dps.throttle_pct", 0.0)) / 100.0, 0.0, 1.0)
		g["aps"] = 0.5 * clampf(float(Bus.get_value("lm.aps.chamber_pct", 0.0)) / 100.0, 0.0, 1.0)
	var jets := (int(Bus.get_value("rcs.active_jets", 0)) if _heard("csm") else 0) \
		+ (int(Bus.get_value("lm.rcs.active_jets", 0)) if _heard("lm") else 0)
	if jets > 0:
		g["jets"] = minf(0.1 + 0.04 * jets, 0.4)
	# The listener's own cabin: its fans, the crew's breathing, the CM's
	# master alarm in the headsets [simplified: no ECS, so the fans run
	# while the CM's buses are powered, and in Eagle while it flies].
	if aboard == "lm":
		g["fan"] = 0.25 if str(Bus.get_value("dock.state", "")) == "free" else 0.0
	else:
		g["fan"] = 0.25 if bool(Bus.get_value("sys.powered", false)) else 0.0
		g["breath"] = clampf((float(Bus.get_value("dyn.g_load", 0.0)) - BREATH_G) / 3.0, 0.0, 1.0)
		g["alarm"] = 0.3 if bool(Bus.get_value("sys.master_alarm", false)) else 0.0
	return g


func _process(delta: float) -> void:
	_take_rendered()
	var g := gains()
	for v: String in g:
		Bus.set_value("audio.%s_gain" % v, g[v])
	if not enabled:
		return
	for v: String in g:
		_drive(v, g[v], delta)


## Bring continuous voice [param voice] toward [param gain]: its loop starts
## as it comes up and stops once it has gone quiet.
func _drive(voice: String, gain: float, delta: float) -> void:
	var p: AudioStreamPlayer = _players[voice]
	if p.stream == null:
		return
	var level := move_toward(float(_level.get(voice, 0.0)), gain, delta / RAMP_S)
	_level[voice] = level
	if level <= 0.0:
		if p.playing:
			p.stop()
		return
	p.volume_db = linear_to_db(level)
	if not p.playing:
		p.play()


# --- rendering ---------------------------------------------------------------

## The worker's: every voice, from its recipe.
func _render_all() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var out := {}
	for kind: String in ONE_SHOTS:
		out[kind] = render_one_shot(ONE_SHOTS[kind], rng)
	for voice: String in LAYERS:
		out[voice] = render_loop(LAYERS[voice], rng)
	_rendered = out


func _take_rendered() -> void:
	if _render_task < 0 or not WorkerThreadPool.is_task_completed(_render_task):
		return
	WorkerThreadPool.wait_for_task_completion(_render_task)
	_render_task = -1
	for voice: String in _rendered:
		_players[voice].stream = _rendered[voice]
	_rendered = {}


## A one-shot: [param recipe]'s tone and low-passed noise under an
## exponential decay, peaking at 0.9.
static func render_one_shot(recipe: Dictionary, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var dur := float(recipe["duration_s"])
	var n := int(dur * SAMPLE_RATE)
	var noise := _noise(n, float(recipe.get("lowpass_hz", 0.0)), rng)
	var mix := float(recipe["noise_mix"])
	var freq := float(recipe["frequency_hz"])
	var tau := dur * float(recipe.get("decay_time_fraction", 0.35))
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var t := float(i) / SAMPLE_RATE
		out[i] = ((1.0 - mix) * sin(TAU * freq * t) + mix * noise[i]) * exp(-t / tau)
	return _wav(_scaled(out, 0.9, true), false)


## A continuous voice's loop, [param recipe]'s loop_s long: tones (each a
## whole number of cycles in the loop), low-passed noise and its roughness,
## crossfaded into its own start so that it repeats without a seam, at an
## RMS of 0.25 where its peaks allow. The alarm's is its square wave.
static func render_loop(recipe: Dictionary, rng: RandomNumberGenerator) -> AudioStreamWAV:
	var loop_s := float(recipe.get("loop_s", 2.0))
	var n := int(round(loop_s * SAMPLE_RATE))
	var out := PackedFloat32Array()
	if recipe.has("square_hz"):
		out = _alternating_square(recipe["square_hz"], float(recipe["square_rate_hz"]), n)
		return _wav(_level_loop(out), true)
	var fade := int(0.25 * SAMPLE_RATE)
	var total := n + fade
	var noise := _noise(total, float(recipe.get("lowpass_hz", 0.0)), rng)
	var rough := _noise(total, 6.0, rng)
	var roughness := float(recipe.get("roughness", 0.0))
	var depth := float(recipe.get("modulation_depth", 0.0))
	var swell_hz := float(recipe.get("modulation_frequency_hz", 0.0))
	var tones: Array = []
	for h: Dictionary in recipe.get("harmonics", []):
		tones.append([round(float(h["frequency_hz"]) * loop_s) / loop_s, float(h["amplitude"])])
	var raw := PackedFloat32Array()
	raw.resize(total)
	for i in range(total):
		var t := float(i) / SAMPLE_RATE
		var v := float(recipe.get("noise_amplitude", 0.0)) * noise[i]
		for tone: Array in tones:
			v += float(tone[1]) * sin(TAU * float(tone[0]) * t)
		v *= maxf(0.0, 1.0 + roughness * 0.5 * rough[i])
		v *= 1.0 - depth * 0.5 + depth * 0.5 * sin(TAU * swell_hz * t)
		raw[i] = v
	out.resize(n)
	for i in range(n):
		out[i] = raw[i]
	# The loop's end runs on into its start.
	for i in range(fade):
		var w := float(i) / float(fade)
		out[i] = raw[i] * w + raw[n + i] * (1.0 - w)
	return _wav(_level_loop(out), true)


## A square wave stepping through [param freqs] (Hz) [param rate] times a
## second, from its odd harmonics below the Nyquist frequency; each step
## starts in phase.
static func _alternating_square(freqs: Array, rate: float, n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var step := int(round(SAMPLE_RATE / rate))
	for i in range(n):
		var f := float(freqs[floori(float(i) / step) % freqs.size()])
		var t := float(i % step) / SAMPLE_RATE
		var v := 0.0
		var k := 1
		while k * f < SAMPLE_RATE * 0.5:
			v += sin(TAU * k * f * t) / k
			k += 2
		out[i] = v * 4.0 / PI
	return out


## [param n] samples of white noise through two one-pole low-passes at
## [param corner] Hz (none at 0), at unit RMS.
static func _noise(n: int, corner: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(n)
	var a := 1.0 - exp(-TAU * corner / SAMPLE_RATE) if corner > 0.0 else 1.0
	var y1 := 0.0
	var y2 := 0.0
	# Run the filters in first, so the noise starts at its level.
	var warm := int(SAMPLE_RATE / maxf(corner, 1.0)) if corner > 0.0 else 0
	for i in range(-warm, n):
		var x := rng.randf() * 2.0 - 1.0
		y1 += a * (x - y1)
		y2 += a * (y1 - y2)
		if i >= 0:
			out[i] = y2
	return _scaled(out, 1.0, false)


## [param s] at an RMS of 0.25, or lower if its peaks would pass 0.95.
static func _level_loop(s: PackedFloat32Array) -> PackedFloat32Array:
	var rms := 0.0
	var peak := 0.0
	for v in s:
		rms += v * v
		peak = maxf(peak, absf(v))
	rms = sqrt(rms / maxf(s.size(), 1))
	if rms <= 0.0:
		return s
	var k := minf(0.25 / rms, 0.95 / peak)
	for i in range(s.size()):
		s[i] *= k
	return s


## [param s] scaled to a peak ([param peak] true) or an RMS of [param to].
static func _scaled(s: PackedFloat32Array, to: float, peak: bool) -> PackedFloat32Array:
	var m := 0.0
	for v in s:
		m = maxf(m, absf(v)) if peak else m + v * v
	if not peak:
		m = sqrt(m / maxf(s.size(), 1))
	if m <= 0.0:
		return s
	var k := to / m
	for i in range(s.size()):
		s[i] *= k
	return s


static func _wav(s: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in range(s.size()):
		data.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = int(SAMPLE_RATE)
	wav.data = data
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = s.size()
	return wav

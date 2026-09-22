## Master simulation clock (same contract as the Gemini template).
##
## Drives every system at a fixed rate independent of the render frame rate
## and keeps Ground Elapsed Time (GET). Systems register with add_ticker()
## and receive tick(dt) in deterministic stage order. Time acceleration runs
## more steps per frame rather than enlarging dt, except while the vehicle
## coasts (sys.coast_ok): then the step grows to the propagator's
## recommended coast step (dyn.coast_dt_s), landing exactly on the next
## scheduled event (seq.next_event_get_s, guid.next_event_get_s).
extends Node

signal ticked(dt: float)
signal rate_changed(rate: float)
signal paused_changed(paused: bool)

## Fixed simulation step in seconds (50 Hz). Every powered or aerodynamic
## step uses it.
const FIXED_DT: float = 0.02
## Allowed time-acceleration rates. Translunar coast lasts three days, so
## the Apollo sim goes one decade beyond the Gemini template.
const RATES: Array[float] = [1.0, 10.0, 100.0, 1000.0, 10000.0]
## Coarse coast steps are only used at or above this rate.
const COAST_MIN_RATE: float = 100.0
## Upper bound for any coast step, seconds.
const COAST_DT_MAX: float = 60.0
## Above this rate interactive controls are locked; automation still runs.
const INTERACTIVE_MAX_RATE: float = 100.0
## When the vehicle stops coasting (engine start, atmosphere) at a higher
## rate, time acceleration drops back to this rate.
const POWERED_MAX_RATE: float = 10.0
## Cap on steps per render frame to avoid a spiral of death.
const MAX_STEPS_PER_FRAME: int = 2000

## Ground Elapsed Time, seconds since liftoff.
var get_seconds: float = 0.0
## Julian Date (UTC) of liftoff; GET 0. Default is Apollo 11 liftoff,
## 1969-07-16 13:32:00 UTC.
var liftoff_jd: float = 2440419.0638889
var rate: float = 1.0:
	set(value):
		rate = value
		rate_changed.emit(rate)
		Bus.set_value("sys.controls_locked", rate > INTERACTIVE_MAX_RATE)
var paused: bool = false:
	set(value):
		paused = value
		paused_changed.emit(paused)

## When true the engine frame loop does not advance the clock; only
## advance() and frame() do. Tests set this so wall time never leaks in.
var manual: bool = false

enum Stage { INPUT, MISSION, POWER_GUIDANCE, SYSTEMS, DYNAMICS, DEPENDENT }

var last_step_ms: float = 0.0
var step_count: int = 0

var _accumulator: float = 0.0
var _epoch_seen: int = 0
var _tickers: Array = [[], [], [], [], [], []]
var _rate_index: int = 0


func controls_locked() -> bool:
	return rate > INTERACTIVE_MAX_RATE


func _process(delta: float) -> void:
	if manual:
		return
	frame(delta)


## One render frame of wall time. Interactive: fast-forward stops when
## the vehicle stops coasting or reaches a scheduled event.
func frame(delta: float) -> void:
	if paused:
		return
	advance(delta * rate, MAX_STEPS_PER_FRAME, true)


## Advance simulation time by [param sim_seconds], running fixed or coast
## steps. Public so tests and scripted scenarios step deterministically.
## With [param interactive], time acceleration above POWERED_MAX_RATE drops
## back when a burn or entry starts, or a scheduled event is reached, and
## the rest of the frame's time is discarded.
func advance(sim_seconds: float, max_steps: int = -1, interactive: bool = false) -> void:
	_accumulator += sim_seconds
	var steps := 0
	while _accumulator >= FIXED_DT - 1e-9 and (max_steps < 0 or steps < max_steps):
		var dt := step_dt()
		if _accumulator < dt - 1e-9:
			dt = maxf(floorf(_accumulator / FIXED_DT + 1e-9) * FIXED_DT, FIXED_DT)
		_step(dt)
		_accumulator -= dt
		steps += 1
		if interactive and rate > POWERED_MAX_RATE and (not _coasting() or _at_event()):
			_set_rate_index(RATES.find(POWERED_MAX_RATE))
			_accumulator = 0.0
			break
	if max_steps >= 0 and steps >= max_steps and _accumulator >= FIXED_DT:
		_accumulator = 0.0


func _at_event() -> bool:
	for ch in ["seq.next_event_get_s", "guid.next_event_get_s"]:
		if absf(float(Bus.get_value(ch, -1.0)) - get_seconds) < 1e-6:
			return true
	return false


func _coasting() -> bool:
	return bool(Bus.get_value("sys.coast_ok", false))


## The step length the policy allows right now.
func step_dt() -> float:
	if rate < COAST_MIN_RATE or not _coasting():
		return FIXED_DT
	if Bus.command_epoch != _epoch_seen:
		return FIXED_DT
	var dt := clampf(float(Bus.get_value("dyn.coast_dt_s", 1.0)), FIXED_DT, COAST_DT_MAX)
	for ch in ["seq.next_event_get_s", "guid.next_event_get_s"]:
		var next_get := float(Bus.get_value(ch, -1.0))
		if next_get > get_seconds:
			var until := next_get - get_seconds
			if until < dt:
				dt = maxf(floorf(until / FIXED_DT + 1e-9) * FIXED_DT, FIXED_DT)
	return dt


func _step(dt: float = FIXED_DT) -> void:
	var t0 := Time.get_ticks_usec()
	get_seconds += dt
	Bus.set_value("time.get_s", get_seconds)
	for stage in _tickers:
		for t in stage:
			t.call(dt)
	ticked.emit(dt)
	_epoch_seen = Bus.command_epoch
	last_step_ms = (Time.get_ticks_usec() - t0) / 1000.0
	step_count += 1


func add_ticker(callback: Callable, stage: int = Stage.SYSTEMS) -> void:
	for st in _tickers:
		if st.has(callback):
			return
	_tickers[stage].append(callback)


func remove_ticker(callback: Callable) -> void:
	for st in _tickers:
		st.erase(callback)


func ticker_count() -> int:
	var n := 0
	for st in _tickers:
		n += st.size()
	return n


func julian_date() -> float:
	return liftoff_jd + get_seconds / 86400.0


func faster() -> void:
	_set_rate_index(_rate_index + 1)


func slower() -> void:
	_set_rate_index(_rate_index - 1)


func _set_rate_index(i: int) -> void:
	_rate_index = clampi(i, 0, RATES.size() - 1)
	rate = RATES[_rate_index]


func get_display() -> String:
	return Units.hms(get_seconds)


func reset(start_get: float = 0.0) -> void:
	get_seconds = start_get
	_accumulator = 0.0
	step_count = 0
	_set_rate_index(0)
	paused = false
	for st in _tickers:
		st.clear()
	Bus.set_value("time.get_s", get_seconds)


## Jump GET without touching tickers or rate (mission start states).
func set_time(get_s: float) -> void:
	get_seconds = get_s
	_accumulator = 0.0
	Bus.set_value("time.get_s", get_seconds)


func snapshot() -> Dictionary:
	return {"get_s": get_seconds, "liftoff_jd": liftoff_jd, "rate": rate, "paused": paused,
		"accumulator": _accumulator}


func restore(d: Dictionary) -> void:
	get_seconds = float(d["get_s"])
	liftoff_jd = float(d["liftoff_jd"])
	_set_rate_index(maxi(RATES.find(float(d.get("rate", 1.0))), 0))
	paused = bool(d.get("paused", false))
	_accumulator = float(d.get("accumulator", 0.0))
	# A restored run is a new command context: its first step is a fine one.
	_epoch_seen = -1
	Bus.set_value("time.get_s", get_seconds)

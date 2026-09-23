## Performance monitor: samples the frame time and rendering statistics each
## frame against the headset budget and publishes perf.*, which the wrist
## menu's status line and the headset acceptance recorder read. The
## procedural Earth, Moon and star shaders have never been measured at
## 90 Hz in stereo (docs/ROADMAP.md, milestone 2 risks); this is the gauge.
## Taken from gemini-capsule's src/presentation/perf_monitor.gd at 40e449c
## (README.md lists the port). Its draw-call and triangle budgets are
## gemini-capsule's ART_PIPELINE.md §9 (PC VR), kept until Apollo sets its
## own. Presentation only.
##
## Writes: perf.frame_ms, perf.frame_ms_max (worst of the last 90 frames),
##         perf.fps, perf.draw_calls, perf.primitives, perf.over_budget,
##         perf.memory_mb, perf.sim_ms_per_step
class_name PerfMonitor
extends Node

## 90 Hz => 11.1 ms; the XR session start sets the headset's own refresh.
@export var frame_budget_ms: float = 11.1
@export var draw_call_budget: int = 150
@export var primitive_budget: int = 1500000

var frame_ms: float = 0.0
var frame_ms_max: float = 0.0
var _window: Array[float] = []


func _process(delta: float) -> void:
	sample(delta)


## One frame's sample (tests feed it directly).
func sample(delta: float) -> void:
	frame_ms = delta * 1000.0
	_window.append(frame_ms)
	if _window.size() > 90:
		_window.pop_front()
	frame_ms_max = 0.0
	for f in _window:
		frame_ms_max = maxf(frame_ms_max, f)
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var over := frame_ms_max > frame_budget_ms * 1.5 or int(draws) > draw_call_budget or int(prims) > primitive_budget
	Bus.set_value("perf.frame_ms", frame_ms)
	Bus.set_value("perf.frame_ms_max", frame_ms_max)
	Bus.set_value("perf.fps", Engine.get_frames_per_second())
	Bus.set_value("perf.draw_calls", int(draws))
	Bus.set_value("perf.primitives", int(prims))
	Bus.set_value("perf.over_budget", over)
	Bus.set_value("perf.memory_mb", OS.get_static_memory_usage() / 1048576.0)
	Bus.set_value("perf.sim_ms_per_step", SimClock.last_step_ms)

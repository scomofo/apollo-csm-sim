## GUT pre-run hook: the simulation clock advances only when a test says
## so, never from the engine's frame loop between tests.
extends GutHookScript


func run() -> void:
	SimClock.manual = true

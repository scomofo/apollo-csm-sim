## Earth Landing System: drogue and main parachutes.
##
## With ELS LOGIC on and ELS AUTO selected, the baroswitches deploy the two
## drogues at 24,000 ft and the three mains at 10,000 ft (the drogues are
## released as the mains deploy). The crew can deploy either set manually
## (ctl.els.drogue / ctl.els.main pushbuttons) with ELS LOGIC on. Deploying
## a parachute above its structural limit shreds it [simplified: fixed
## dynamic-pressure limits].
##
## Reads:  ctl.els.logic, ctl.els.auto, ctl.els.drogue, ctl.els.main,
##         dyn.alt_m, dyn.speed_mps, dyn.config, dyn.primary
## The mains open reefed: their drag area grows over MAIN_DISREEF_S so the
## opening load stays near the ~4 g of the real staged disreefing.
##
## Writes: els.drogue, els.mains, els.main_fraction, els.failed
extends Node

const DROGUE_Q_LIMIT := 40000.0   ## Pa [estimated]
const MAIN_Q_LIMIT := 8000.0      ## Pa [estimated]
const MAIN_DISREEF_S := 10.0      ## s, reefed to full open [estimated]

var drogue: bool = false
var mains: bool = false
var failed: bool = false
var main_fraction: float = 0.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(dt: float) -> void:
	if mains and main_fraction < 1.0:
		main_fraction = minf(1.0, main_fraction + dt / MAIN_DISREEF_S)
	if str(Bus.get_value("dyn.config", "")) != "cm" or str(Bus.get_value("dyn.primary", "")) != "earth":
		return
	if not bool(Bus.get_value("ctl.els.logic", false)) or failed:
		_publish()
		return
	var d := SpacecraftData.section("els")
	var alt := float(Bus.get_value("dyn.alt_m", 1e9))
	var v := float(Bus.get_value("dyn.speed_mps", 0.0))
	var q := 0.5 * Atmosphere.density(alt) * v * v
	var auto := bool(Bus.get_value("ctl.els.auto", false))
	var want_drogue := bool(Bus.get_value("ctl.els.drogue", false)) or (auto and alt < float(d["drogue_alt_m"]))
	var want_main := bool(Bus.get_value("ctl.els.main", false)) or (auto and alt < float(d["main_alt_m"]))
	if want_drogue and not drogue and not mains:
		if q > DROGUE_Q_LIMIT:
			failed = true
		else:
			drogue = true
	if want_main and not mains:
		if q > MAIN_Q_LIMIT:
			failed = true
		else:
			mains = true
			drogue = false
			main_fraction = 0.02
	_publish()


func _publish() -> void:
	Bus.set_value("els.drogue", drogue)
	Bus.set_value("els.mains", mains)
	Bus.set_value("els.main_fraction", main_fraction)
	Bus.set_value("els.failed", failed)


func snapshot() -> Dictionary:
	return {"drogue": drogue, "mains": mains, "failed": failed, "main_fraction": main_fraction}


func restore(d: Dictionary) -> void:
	drogue = bool(d["drogue"])
	mains = bool(d["mains"])
	failed = bool(d["failed"])
	main_fraction = float(d.get("main_fraction", 1.0 if mains else 0.0))
	_publish()

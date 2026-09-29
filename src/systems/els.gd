## Earth Landing System: drogue and main parachutes.
##
## With ELS LOGIC on, or armed by an LES abort's canards (les.elsc_armed,
## slice 9d), and ELS AUTO selected, the ELS's controller comes on below
## the 24,000 ft baroswitch; 2.0 s later it deploys the two drogues, and
## below the 10,000 ft baroswitch, but not before 14.0 s after it came on,
## the three mains (the drogues are released as the mains deploy): in a
## low abort the controller comes on at once, and the timers carry the
## chutes through (spacecraft.json "els"). The crew can deploy either set
## manually (ctl.els.drogue / ctl.els.main pushbuttons) with ELS LOGIC on.
## Deploying a parachute above its structural limit shreds it
## [simplified: fixed dynamic-pressure limits].
##
## Reads:  ctl.els.logic, ctl.els.auto, ctl.els.drogue, ctl.els.main,
##         les.elsc_armed, dyn.alt_m, dyn.air_speed_mps, dyn.config,
##         dyn.primary
## The mains open reefed: their drag area grows over MAIN_DISREEF_S so the
## opening load stays near the ~4 g of the real staged disreefing.
##
## Writes: els.drogue, els.mains, els.main_fraction, els.failed,
##         els.elsc_active
extends Node

const DROGUE_Q_LIMIT := 40000.0   ## Pa [estimated]
const MAIN_Q_LIMIT := 8000.0      ## Pa [estimated]
const MAIN_DISREEF_S := 10.0      ## s, reefed to full open [estimated]

var drogue: bool = false
var mains: bool = false
var failed: bool = false
var main_fraction: float = 0.0
## Seconds since the ELS's controller came on, -1 before.
var elsc_s: float = -1.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(dt: float) -> void:
	if mains and main_fraction < 1.0:
		main_fraction = minf(1.0, main_fraction + dt / MAIN_DISREEF_S)
	var cfg := str(Bus.get_value("dyn.config", ""))
	if not cfg in ["cm", "cm_les"] or str(Bus.get_value("dyn.primary", "")) != "earth":
		return
	var armed := bool(Bus.get_value("ctl.els.logic", false)) or bool(Bus.get_value("les.elsc_armed", false))
	if not armed or failed:
		_publish()
		return
	var d := SpacecraftData.section("els")
	var alt := float(Bus.get_value("dyn.alt_m", 1e9))
	var auto := bool(Bus.get_value("ctl.els.auto", false))
	if elsc_s >= 0.0:
		elsc_s += dt
	elif auto and alt < float(d["drogue_alt_m"]):
		elsc_s = 0.0
	if cfg != "cm":
		# The tower still on: it goes first (Les).
		_publish()
		return
	var v := float(Bus.get_value("dyn.air_speed_mps", 0.0))
	var q := 0.5 * Atmosphere.density(alt) * v * v
	var logic := bool(Bus.get_value("ctl.els.logic", false))
	var want_drogue := (logic and bool(Bus.get_value("ctl.els.drogue", false))) or (auto and elsc_s >= float(d["drogue_s"]))
	var want_main := (logic and bool(Bus.get_value("ctl.els.main", false))) \
		or (auto and elsc_s >= float(d["main_s"]) and alt < float(d["main_alt_m"]))
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
	Bus.set_value("els.elsc_active", elsc_s >= 0.0)


func snapshot() -> Dictionary:
	return {"drogue": drogue, "mains": mains, "failed": failed, "main_fraction": main_fraction, "elsc_s": elsc_s}


func restore(d: Dictionary) -> void:
	drogue = bool(d["drogue"])
	mains = bool(d["mains"])
	failed = bool(d["failed"])
	main_fraction = float(d.get("main_fraction", 1.0 if mains else 0.0))
	elsc_s = float(d.get("elsc_s", 0.0 if drogue or mains else -1.0))
	_publish()

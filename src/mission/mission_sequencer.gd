## Runs the mission: builds the start state for a phase, tracks the flight
## phase from truth, performs the Saturn/IU automation (TLI), carries out
## crew separation commands, injects scripted failures, and plays Mission
## Control: PAD requests are solved by the RTCC and uplinked to the CMC.
##
## Reads:  ctl.seq.csm_sep, ctl.seq.lm_jett, ctl.seq.cm_sm_sep (crew
##         pushbuttons, edge-triggered), ctl.ground.pad_request (String)
## Writes: mission.phase, mission.capcom, mission.pad_text, mission.event.<id>,
##         mission.result, mission.tli_tig
class_name MissionSequencer
extends Node

signal event_fired(id: String)
signal capcom(text: String)

const PHASES := ["parking_orbit", "tli", "translunar_coast", "lunar_orbit",
	"transearth_coast", "entry", "splashdown", "lost"]

var mission: Mission
var dynamics: Dynamics
var systems: Dictionary = {}

var phase: String = ""
var events: Array = []
var visited_lunar_orbit: bool = false
var tli_pad: Dictionary = {}
var tli_cutoff_get: float = -1.0
var last_pad: Dictionary = {}
var _edges: Dictionary = {}
var _o2_failed: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.MISSION)
	for ch in ["ctl.seq.csm_sep", "ctl.seq.lm_jett", "ctl.seq.cm_sm_sep"]:
		_edges[ch] = bool(Bus.get_value(ch, false))
	Bus.subscribe("ctl.ground.pad_request", _on_pad_request)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)
	Bus.unsubscribe("ctl.ground.pad_request", _on_pad_request)


# --- start states ------------------------------------------------------------

func _parking_orbit_traj() -> Trajectory:
	var po := mission.section("parking_orbit")
	var r := Bodies.R_EARTH + float(po["alt_km"]) * 1000.0
	var v := sqrt(Bodies.MU_EARTH / r)
	var pl := Bodies.moon_plane()
	var p := Vector3(pl[0], pl[1], pl[2])
	var q := Vector3(pl[3], pl[4], pl[5])
	var u := deg_to_rad(float(po.get("arg_lat_deg", 0.0)))
	var tr := Trajectory.new()
	tr.set_state("earth", float(po["insertion_get_s"]), (p * cos(u) + q * sin(u)) * r, (-p * sin(u) + q * cos(u)) * v)
	return tr


func _stack_mass() -> float:
	return SpacecraftData.total_mass("stack", float(Bus.get_value("sps.prop_kg", 18413.0)),
		float(Bus.get_value("rcs.sm_prop_kg", 560.0)), float(Bus.get_value("rcs.cm_prop_kg", 110.0)),
		float(Bus.get_value("sivb.prop_kg", 75000.0)))


func _plan_tli(tr: Trajectory) -> Dictionary:
	var t := mission.section("tli")
	return Rtcc.plan_tli(tr, _stack_mass(), float(Bus.get_value("sivb.prop_kg", 75000.0)),
		float(t["energy_j_per_kg"]), float(t["pericynthion_alt_km"]) * 1000.0,
		maxf(float(t["earliest_get_s"]), tr.t + 600.0))


## Put the vehicle in the requested phase. Later phases are produced by
## flying the earlier ones through the RTCC's own solutions, so every start
## state is consistent with the mission it continues.
func start(p_phase: String) -> void:
	events.clear()
	visited_lunar_orbit = false
	tli_pad = {}
	tli_cutoff_get = -1.0
	var tr := _parking_orbit_traj()
	var cfg := "stack"
	var sps_prop := float(SpacecraftData.section("sps")["propellant_kg"])
	var sivb_prop := float(SpacecraftData.section("sivb")["propellant_kg"])
	if p_phase == "translunar_coast":
		var pad := _plan_tli(tr)
		assert(not pad.is_empty(), "no TLI solution")
		tr.coast_to(float(pad["tig"]), 30.0)
		sivb_prop = Sivb.simulate_burn(tr, _stack_mass(), sivb_prop, float(pad["energy"]))
		tr.coast_to(tr.t + float(mission.data.get("tde_delay_s", 3600.0)), 60.0)
		cfg = "csm_lm"
	if p_phase in ["lunar_orbit", "transearth_coast", "entry"]:
		visited_lunar_orbit = true
		cfg = "csm_lm"
		var r := Bodies.R_MOON + 111000.0
		var v := sqrt(Bodies.MU_MOON / r)
		var pl := Bodies.moon_plane()
		# Retrograde, in the lunar orbit plane.
		tr.set_state("moon", 75.0 * 3600.0 + 50.0 * 60.0, Vector3(pl[0], pl[1], pl[2]) * r, -Vector3(pl[3], pl[4], pl[5]) * v)
		var mass := SpacecraftData.total_mass("csm_lm", sps_prop, 560.0, 110.0, 0.0)
		sps_prop -= mass * (1.0 - exp(-900.0 / (float(SpacecraftData.section("sps")["isp_s"]) * Units.G0)))
	if p_phase in ["transearth_coast", "entry"]:
		cfg = "csm"
		var mass := SpacecraftData.total_mass("csm", sps_prop, 560.0, 110.0, 0.0)
		var tei := mission.section("tei")
		var pad := Rtcc.plan_tei(tr, mass, float(tei["dv_mps"]), float(tei["entry_perigee_alt_km"]) * 1000.0, tr.t + 600.0)
		assert(not pad.is_empty(), "no TEI solution")
		tr.coast_to(float(pad["tig"]), 30.0)
		var after := Rtcc.simulate_sps_burn(tr, mass, pad["dv_lvlh"])
		sps_prop -= mass - after
		if p_phase == "transearth_coast":
			tr.coast_to(tr.t + 10.0 * 3600.0, 60.0)
		else:
			var near := func(t2: Trajectory) -> bool:
				return t2.primary == "earth" and t2.altitude() < 5.0e6
			tr.coast_until(near, tr.t + 6.0 * 86400.0, 60.0, 0.002)
	SimClock.set_time(tr.t)
	Bus.set_value("sps.prop_kg", sps_prop)
	Bus.set_value("sivb.prop_kg", sivb_prop if cfg == "stack" else 0.0)
	if systems.has("sps"):
		systems["sps"].prop_kg = sps_prop
	if systems.has("sivb"):
		systems["sivb"].prop_kg = sivb_prop if cfg == "stack" else 0.0
		systems["sivb"].state = "idle" if cfg == "stack" else "done"
	dynamics.initialize(tr.primary, tr.t, tr.pos(), tr.vel(), cfg)
	dynamics.traj.s = tr.s.duplicate()
	dynamics.publish_state()
	phase = ""
	_update_phase()
	if cfg == "stack":
		tli_pad = _plan_tli(dynamics.traj)
		if not tli_pad.is_empty():
			systems["sivb"].arm_tli(float(tli_pad["tig"]), float(tli_pad["energy"]))
			Bus.set_value("mission.tli_tig", float(tli_pad["tig"]))
			_say("Apollo 11, Houston. You are GO for TLI. TIG %s, ΔV %.0f ft/s." % [
				Units.hms(float(tli_pad["tig"])), float(tli_pad["dv"]) / Units.FT])
	_fire("start_" + p_phase)
	match p_phase:
		"translunar_coast":
			_say("Columbia, Houston. Good trajectory. Request an MCC PAD when you are ready; LOI PAD about eight hours out.")
		"lunar_orbit":
			_say("Columbia, Houston. You are in a 60-mile orbit with Eagle docked. LM JETT, then request the TEI PAD.")
		"transearth_coast":
			_say("Houston: TEI was good. Request MCC PADs to put you in the entry corridor.")
		"entry":
			_say("Houston: entry interface in about fifteen minutes. CM/SM SEP, P61, ELS LOGIC and AUTO.")


# --- per step -------------------------------------------------------------------

func tick(_dt: float) -> void:
	_crew_commands()
	_automation()
	_update_phase()


func _crew_commands() -> void:
	for ch in _edges:
		var now := bool(Bus.get_value(ch, false))
		if now and not _edges[ch]:
			match ch:
				"ctl.seq.csm_sep":
					if dynamics.config == "stack" and str(Bus.get_value("sivb.state", "")) == "done":
						_transposition_and_docking()
				"ctl.seq.lm_jett":
					if dynamics.config == "csm_lm":
						dynamics.set_configuration("csm")
						_fire("lm_jettison")
						_say("Houston copies LM jettison.")
				"ctl.seq.cm_sm_sep":
					if dynamics.config == "csm" or dynamics.config == "csm_lm":
						dynamics.set_configuration("cm")
						_fire("cm_sm_sep")
						_say("CM/SM separation confirmed.")
		_edges[ch] = now


func _transposition_and_docking() -> void:
	dynamics.set_configuration("csm_lm")
	Bus.set_value("sivb.prop_kg", 0.0)
	systems["sivb"].prop_kg = 0.0
	_fire("transposition_docking")
	_say("Houston confirms hard dock and LM extraction. Columbia and Eagle are on their way.")


func _automation() -> void:
	var now := SimClock.get_seconds
	var st := str(Bus.get_value("sivb.state", ""))
	if dynamics.config == "stack":
		if st == "burning" and not _has("tli_ignition"):
			_fire("tli_ignition")
		if st == "done" and tli_cutoff_get < 0.0:
			tli_cutoff_get = now
			_fire("tli_cutoff")
			_say("TLI cutoff. Houston has you on a good trajectory. Separate from the S-IVB when ready.")
		# Transposition, docking and extraction happen without crew input
		# after the scripted delay if the crew has not already separated.
		if tli_cutoff_get >= 0.0 and now - tli_cutoff_get > float(mission.data.get("tde_delay_s", 3600.0)):
			_transposition_and_docking()
	var f := mission.section("failures")
	var o2 := float(f.get("o2_tank_2_get_s", -1.0))
	if o2 > 0.0 and now >= o2 and not _o2_failed and systems.has("eps"):
		_o2_failed = true
		systems["eps"].fail_o2_tank(2)
		_fire("o2_tank_2_failure")
		_say("Houston, we've had a problem. Main B bus undervolt; O2 tank 2 pressure reading zero.")
	if dynamics.landed and not _has("landing"):
		_fire("landing")


func _update_phase() -> void:
	var p := phase
	var tr := dynamics.traj
	if dynamics.landed:
		var ok := tr.primary == "earth" and dynamics.landed_speed < 15.0
		p = "splashdown" if ok else "lost"
	elif dynamics.config == "cm" and tr.primary == "earth" and tr.altitude() < 1.0e6:
		p = "entry"
	elif dynamics.config == "stack" and str(Bus.get_value("sivb.state", "")) != "done":
		p = "tli" if bool(Bus.get_value("sivb.burning", false)) else "parking_orbit"
	elif tr.primary == "moon" and float(tr.conic()["energy"]) < 0.0:
		p = "lunar_orbit"
		visited_lunar_orbit = true
	elif visited_lunar_orbit:
		p = "transearth_coast"
	else:
		p = "translunar_coast"
	if p != phase:
		phase = p
		Bus.set_value("mission.phase", phase)
		_fire("phase_" + phase)
		if phase == "lunar_orbit":
			_say("Columbia, Houston. We confirm lunar orbit.")
		elif phase == "splashdown":
			Bus.set_value("mission.result", "success")
			_say("Splashdown! Welcome home, Apollo 11. Peak load %.1f g, touchdown %.1f m/s." % [dynamics.max_g, dynamics.landed_speed])
		elif phase == "lost":
			Bus.set_value("mission.result", "lost")
			_say("Houston... we have lost the spacecraft.")


# --- Mission Control -----------------------------------------------------------

func _on_pad_request(kind: Variant) -> void:
	if kind == null or str(kind) == "":
		return
	request_pad(str(kind))
	Bus.set_value("ctl.ground.pad_request", "")


## Solve and uplink a maneuver PAD: "mcc", "loi", "circ", "tei".
func request_pad(kind: String) -> Dictionary:
	var tr := dynamics.traj.clone()
	var mass := dynamics.mass
	var now := SimClock.get_seconds
	var pad := {}
	match kind:
		"loi":
			pad = Rtcc.plan_loi(tr, mass, float(mission.section("loi")["apolune_alt_km"]) * 1000.0)
		"circ":
			pad = Rtcc.plan_circularize(tr, mass, "periapsis")
			pad["name"] = "LOI-2"
		"tei":
			var tei := mission.section("tei")
			pad = Rtcc.plan_tei(tr, mass, float(tei["dv_mps"]), float(tei["entry_perigee_alt_km"]) * 1000.0, now + 900.0)
		"mcc":
			var tig := now + 900.0
			if phase == "translunar_coast":
				var target := -(Bodies.R_MOON + float(mission.section("tli")["pericynthion_alt_km"]) * 1000.0)
				pad = Rtcc.plan_mcc(tr, mass, tig, "moon", target, now + 5.0 * 86400.0)
			elif phase == "transearth_coast":
				var probe := tr.clone()
				var er := Rtcc.earth_return(probe, now + 5.0 * 86400.0)
				var sense := signf(float(er["f"]))
				var target: float = sense * (Bodies.R_EARTH + float(mission.section("tei")["entry_perigee_alt_km"]) * 1000.0)
				pad = Rtcc.plan_mcc(tr, mass, tig, "earth", target, now + 5.0 * 86400.0)
	if pad.is_empty() or float(pad.get("dv", 0.0)) <= 0.0:
		_say("Houston: no %s solution / burn not required." % kind.to_upper())
		last_pad = {}
		return {}
	last_pad = pad
	if systems.has("agc"):
		systems["agc"].uplink_maneuver(float(pad["tig"]), pad["dv_lvlh"])
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	_say("Houston, uplinking " + text)
	_fire("pad_" + kind)
	return pad


# --- helpers ---------------------------------------------------------------------

func _has(id: String) -> bool:
	for e in events:
		if e["id"] == id:
			return true
	return false


func _fire(id: String) -> void:
	events.append({"id": id, "get_s": SimClock.get_seconds})
	Bus.set_value("mission.event." + id, SimClock.get_seconds)
	event_fired.emit(id)


func _say(text: String) -> void:
	Bus.set_value("mission.capcom", "%s  %s" % [Units.hms(SimClock.get_seconds), text])
	capcom.emit(text)


func snapshot() -> Dictionary:
	return {"phase": phase, "events": events.duplicate(true), "visited_lunar_orbit": visited_lunar_orbit,
		"tli_cutoff_get": tli_cutoff_get, "o2_failed": _o2_failed}


func restore(d: Dictionary) -> void:
	phase = str(d["phase"])
	events = d["events"].duplicate(true)
	visited_lunar_orbit = bool(d["visited_lunar_orbit"])
	tli_cutoff_get = float(d["tli_cutoff_get"])
	_o2_failed = bool(d.get("o2_failed", false))
	Bus.set_value("mission.phase", phase)

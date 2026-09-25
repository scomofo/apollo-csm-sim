## Runs the mission: builds the start state for a phase, tracks the flight
## phase from truth, performs the Saturn/IU automation (TLI), carries out
## crew separation commands, injects scripted failures, and plays Mission
## Control: PAD requests are solved by the RTCC and uplinked to the CMC, or
## to the LGC for the LM's burns, its descent and its ascent. It calls the
## LM's landing, liftoff and insertion. From undocking to TEI it follows
## its timeline (mission.json "lunar_timeline"): CAPCOM's calls and the
## PADs, each at its time, as Apollo 11 had them.
##
## In lunar orbit the flight phase follows the LM: lunar_descent from DOI
## (the LM's perilune brought low) to touchdown, lunar_surface while it is
## landed, and lunar_ascent from liftoff until it docks.
##
## Reads:  ctl.seq.csm_sep, ctl.seq.undock, ctl.seq.lm_jett,
##         ctl.seq.cm_sm_sep, ctl.lm.stage (crew pushbuttons,
##         edge-triggered), ctl.ground.pad_request (String)
## Writes: mission.phase, mission.capcom, mission.pad_text, mission.event.<id>,
##         mission.result, mission.tli_tig, mission.next_event_get_s (the
##         timeline's next entry, which SimClock drops time acceleration at)
class_name MissionSequencer
extends Node

signal event_fired(id: String)
signal capcom(text: String)

const PHASES := ["parking_orbit", "tli", "translunar_coast", "lunar_orbit", "lunar_descent",
	"lunar_surface", "lunar_ascent", "transearth_coast", "entry", "splashdown", "lost"]
## The start phases flown on from the lunar orbit start with the LM
## (_lm_start()).
const LM_PHASES := ["lunar_descent", "lunar_surface", "lunar_ascent"]
## A free LM whose orbit's perilune is below this height (above the
## reference sphere) is descending: DOI takes it to 15 km.
const DESCENT_PERILUNE_M := 50000.0
## A timeline entry this late (past its time by a coast step, or a PAD
## that came late) still happens; later than this, it is passed by.
const TIMELINE_GRACE_S := 600.0
## The planned time that marks each PAD as still to be flown: the timeline
## doesn't uplink one while the last is.
const PAD_PENDING := {"doi": "doi_tig", "pdi": "pdi_pad_tig", "ascent": "liftoff_tig", "csi": "csi_tig",
	"tei": "tei_tig"}
## The DOI PAD comes after an undocking only this close to the landing
## time: an undocking a day early is for practice.
const DESCENT_LEAD_S := 6.0 * 3600.0

var mission: Mission
var dynamics: Dynamics
var systems: Dictionary = {}

var phase: String = ""
var events: Array = []
var visited_lunar_orbit: bool = false
var tli_pad: Dictionary = {}
var tli_cutoff_get: float = -1.0
var last_pad: Dictionary = {}
## The last PAD of each kind (not in checkpoints).
var pads: Dictionary = {}
## The GETs the ground has planned, which the timeline counts back from:
## doi_tig, pdi_tig, liftoff_tig, csi_tig, tpi_tig, tei_tig.
var plan: Dictionary = {}
## The timeline's entries done: id to the GET each happened at, or -1 for
## one passed by (its condition didn't hold then, or the start came after).
var timeline_done: Dictionary = {}
var _edges: Dictionary = {}
var _o2_failed: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.MISSION)
	for ch in ["ctl.seq.csm_sep", "ctl.seq.undock", "ctl.seq.lm_jett", "ctl.seq.cm_sm_sep", "ctl.lm.stage"]:
		_edges[ch] = bool(Bus.get_value(ch, false))
	Bus.subscribe("ctl.ground.pad_request", _on_pad_request)
	if dynamics != null:
		dynamics.docking_contact.connect(_on_docking_contact)
		dynamics.lm_touchdown.connect(_on_lm_touchdown)
		dynamics.lm_liftoff.connect(_on_lm_liftoff)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)
	Bus.unsubscribe("ctl.ground.pad_request", _on_pad_request)
	if dynamics != null and dynamics.docking_contact.is_connected(_on_docking_contact):
		dynamics.docking_contact.disconnect(_on_docking_contact)
	if dynamics != null and dynamics.lm_touchdown.is_connected(_on_lm_touchdown):
		dynamics.lm_touchdown.disconnect(_on_lm_touchdown)
	if dynamics != null and dynamics.lm_liftoff.is_connected(_on_lm_liftoff):
		dynamics.lm_liftoff.disconnect(_on_lm_liftoff)


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
	if not PHASES.has(p_phase):
		# A typo in --phase= used to fall through silently and start in
		# parking orbit; say so loudly instead. Real but non-startable
		# phase names (e.g. "tli") still start from parking orbit and are
		# re-derived from the truth trajectory below.
		push_error("MissionSequencer.start: unknown phase '%s'; starting in parking orbit" % p_phase)
	events.clear()
	visited_lunar_orbit = false
	tli_pad = {}
	tli_cutoff_get = -1.0
	pads = {}
	plan = {}
	timeline_done = {}
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
	if p_phase in ["lunar_orbit", "transearth_coast", "entry"] + LM_PHASES:
		visited_lunar_orbit = true
		cfg = "csm_lm"
		var r := Bodies.R_MOON + 111000.0
		var v := sqrt(Bodies.MU_MOON / r)
		var pl := Bodies.moon_plane()
		# Retrograde, in the plane LOI puts it in: over the landing site at
		# the landing time, the site at the ground track's northernmost
		# point, the vehicle nearest where it was in the lunar orbit plane.
		var h := Rtcc.site_orbit_normal(landing_site(), float(mission.section("landing")["get_s"]))
		var p0 := Vector3(pl[0], pl[1], pl[2])
		var at := (p0 - h * p0.dot(h)).normalized()
		tr.set_state("moon", 75.0 * 3600.0 + 50.0 * 60.0, at * r, h.cross(at) * v)
		var mass := SpacecraftData.total_mass("csm_lm", sps_prop, 560.0, 110.0, 0.0)
		sps_prop -= mass * (1.0 - exp(-900.0 / (float(SpacecraftData.section("sps")["isp_s"]) * Units.G0)))
	if p_phase in LM_PHASES:
		# Docked until Apollo 11's undocking.
		tr.coast_to(_get_s(mission.section("lunar_timeline")["undocking_get"]), 60.0)
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
	if p_phase in LM_PHASES:
		_lm_start(p_phase)
	# What the timeline had due before the start is past.
	_timeline_pass_by(SimClock.get_seconds)
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
		"lunar_descent":
			_say("Eagle, Houston. You're on the descent orbit. Your state vector and GO for PDI are coming.")
		"lunar_surface":
			_say("Tranquility Base, Houston. You're STAY. The ascent PAD comes at %s." % Units.hms(
				_entry_time(_timeline_entry("ascent_pad"))))
		"lunar_ascent":
			_say("Eagle, Houston. Your ascent PAD is in: liftoff at %s. P12 when you're ready." % Units.hms(
				float(plan.get("liftoff_tig", 0.0))))
		"transearth_coast":
			_say("Houston: TEI was good. Request MCC PADs to put you in the entry corridor.")
		"entry":
			_say("Houston: entry interface in about fifteen minutes. CM/SM SEP, P61, ELS LOGIC and AUTO.")


# --- per step -------------------------------------------------------------------

func tick(_dt: float) -> void:
	_crew_commands()
	_automation()
	_timeline()
	_update_phase()


func _crew_commands() -> void:
	for ch in _edges:
		var now := bool(Bus.get_value(ch, false))
		if now and not _edges[ch]:
			match ch:
				"ctl.seq.csm_sep":
					if dynamics.config == "stack" and str(Bus.get_value("sivb.state", "")) == "done":
						_transposition_and_docking()
				"ctl.seq.undock":
					if dynamics.undock():
						_fire("undocking")
						_say("Houston copies undocking. Eagle is flying free.")
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
				"ctl.lm.stage":
					if dynamics.stage_lm():
						_fire("lm_staging")
						var flying := "" if dynamics.lm.landed else " Eagle's ascent stage is flying."
						_say("Houston copies staging." + flying)
		_edges[ch] = now


## The probe met the drogue: capture docks the LM again.
func _on_docking_contact(contact: Dictionary) -> void:
	if contact["captured"]:
		_fire("docking")
		_say("Houston copies hard dock. Columbia and Eagle are docked.")
	else:
		_fire("docking_contact")
		_say("Houston: contact, %s. Back off and try again." % Docking.describe(contact))


## Eagle's footpads met the surface.
func _on_lm_touchdown(touchdown: Dictionary) -> void:
	_fire("lm_landing")
	if touchdown["hard"]:
		_say("Houston: we saw a hard landing, %.1f ft/s down and %.1f ft/s across. Check your gear." % [
			float(touchdown["vertical_mps"]) / Units.FT, float(touchdown["horizontal_mps"]) / Units.FT])
	else:
		_say("Houston: Roger, Tranquility. We copy you on the ground.")


## The LM left the surface.
func _on_lm_liftoff(_get_s: float) -> void:
	_fire("lm_liftoff")
	_say("Houston: we have liftoff. Eagle, you're looking good.")


## After the liftoff, the ascent engine is off with the LM in orbit:
## insertion. The orbit's apsides are above the landing site.
func _check_insertion() -> void:
	var lm := dynamics.lm
	if lm == null or lm.landed or not _has("lm_liftoff") or _has("lm_insertion") or lm.traj.primary != "moon" \
			or bool(Bus.get_value("lm.aps.on", false)):
		return
	var c := lm.traj.conic()
	var site_r := landing_site().length()
	if float(c["energy"]) >= 0.0 or float(c["rp"]) <= site_r:
		return
	_fire("lm_insertion")
	_say("Houston: Eagle, you're in orbit, %.1f by %.1f." % [(float(c["rp"]) - site_r) / Units.NMI,
		(float(c["ra"]) - site_r) / Units.NMI])


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
	_check_insertion()


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
		p = _lunar_phase()
		visited_lunar_orbit = true
	elif visited_lunar_orbit:
		p = "transearth_coast"
	else:
		p = "translunar_coast"
	if p != phase:
		var was := phase
		phase = p
		Bus.set_value("mission.phase", phase)
		_fire("phase_" + phase)
		if phase == "lunar_orbit" and was in ["", "translunar_coast"]:
			_say("Columbia, Houston. We confirm lunar orbit.")
		elif phase == "splashdown":
			Bus.set_value("mission.result", "success")
			_say("Splashdown! Welcome home, Apollo 11. Peak load %.1f g, touchdown %.1f m/s." % [dynamics.max_g, dynamics.landed_speed])
		elif phase == "lost":
			Bus.set_value("mission.result", "lost")
			_say("Houston... we have lost the spacecraft.")


## In lunar orbit, the LM's part of the flight: its descent (from DOI, its
## perilune low, to touchdown), its stay on the surface, and its ascent
## (from liftoff until it docks); otherwise lunar orbit.
func _lunar_phase() -> String:
	var lm := dynamics.lm
	if lm == null:
		return "lunar_orbit"
	if lm.landed:
		return "lunar_surface"
	if _has("lm_liftoff"):
		return "lunar_ascent"
	if not _has("lm_landing") and lm.traj.primary == "moon" \
			and float(lm.traj.conic()["rp"]) - Bodies.R_MOON < DESCENT_PERILUNE_M:
		return "lunar_descent"
	return "lunar_orbit"


# --- Mission Control -----------------------------------------------------------

func _on_pad_request(kind: Variant) -> void:
	if kind == null or str(kind) == "":
		return
	request_pad(str(kind))
	Bus.set_value("ctl.ground.pad_request", "")


## Solve and uplink a maneuver PAD: "mcc", "loi", "circ", "tei" for the
## CMC; "doi" for the LGC, while the LM flies free; "pdi", the LGC's state
## vector for powered descent (pdi_pad()); "ascent", the liftoff time for
## the LGC's P12 (ascent_pad()); "csi", the rendezvous plan (csi_pad()).
## The TEI and the liftoff come no earlier than GET [param earliest].
func request_pad(kind: String, earliest: float = -1.0) -> Dictionary:
	if kind == "pdi":
		return pdi_pad()
	if kind == "ascent":
		return ascent_pad(earliest)
	if kind == "csi":
		return csi_pad()
	var tr := dynamics.traj.clone()
	var mass := dynamics.mass
	var now := SimClock.get_seconds
	var pad := {}
	match kind:
		"doi":
			if dynamics.lm != null and dynamics.lm.config == "lm":
				var g := SpacecraftData.section("descent_guidance")
				pad = Rtcc.plan_doi(dynamics.lm.traj.clone(), dynamics.lm.mass,
					float(mission.section("doi")["pericynthion_alt_km"]) * 1000.0, landing_site(),
					float(mission.section("landing")["get_s"]), float(g["pdi_range_m"]), float(g["descent_s"]), now + 600.0)
		"loi":
			pad = Rtcc.plan_loi(tr, mass, float(mission.section("loi")["apolune_alt_km"]) * 1000.0,
				landing_site(), float(mission.section("landing")["get_s"]))
		"circ":
			pad = Rtcc.plan_circularize(tr, mass, "periapsis")
			pad["name"] = "LOI-2"
		"tei":
			var tei := mission.section("tei")
			pad = Rtcc.plan_tei(tr, mass, float(tei["dv_mps"]), float(tei["entry_perigee_alt_km"]) * 1000.0,
				maxf(now + 900.0, earliest))
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
	pads[kind] = pad
	if kind == "doi":
		plan["doi_tig"] = pad["tig"]
		# PDI at the pericynthion, until the PDI PAD has its time.
		plan["pdi_tig"] = pad["hp_get"]
	elif kind == "tei":
		plan["tei_tig"] = pad["tig"]
	var computer := "lgc" if kind == "doi" else "agc"
	if systems.has(computer):
		systems[computer].uplink_maneuver(float(pad["tig"]), pad["dv_lvlh"])
	if kind == "doi" and systems.has("lgc"):
		systems["lgc"].uplink_landing_site(landing_site())
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	_say("Houston, uplinking " + text)
	_fire("pad_" + kind)
	return pad


## The PDI PAD, after DOI: the ground predicts PDI with the LGC's own
## ignition algorithm and uplinks the LM's state vector (P27) as MSFN
## tracked it. The tracking error is given where it matters, at PDI
## (mission.json "pdi", LVLH): the uplinked state is on the orbit that is
## off by that much there, coasted back to now. Returns {"name": "PDI",
## "tig"}, or {} without a free LM that has its landing site.
func pdi_pad() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	if dynamics.lm == null or dynamics.lm.config != "lm" or lgc == null or lgc.landing_site == Vector3.ZERO:
		_say("Houston: no PDI solution.")
		last_pad = {}
		return {}
	var now := dynamics.lm.traj.clone()
	var tig := Lgc.pdi_time(now, lgc.landing_site, float(SpacecraftData.section("descent_guidance")["pdi_range_m"]))
	var at := now.clone()
	at.coast_to(tig, 60.0)
	var e := mission.section("pdi")
	var lv := Trajectory.lvlh_basis(at.pos(), at.vel())
	var dp: Vector3 = lv * _v3(e.get("state_error_lvlh_m", [0.0, 0.0, 0.0]))
	var dv: Vector3 = lv * _v3(e.get("state_error_lvlh_mps", [0.0, 0.0, 0.0]))
	for i in 3:
		at.s[i] += dp[i]
		at.s[3 + i] += dv[i]
	# Back along that orbit to now, in the steps coasting takes forward.
	while at.t > now.t + 1e-9:
		at.step(-minf(clampf(0.005 * at.radius() / maxf(at.speed(), 1.0), 0.02, 60.0), at.t - now.t))
	lgc.uplink_state(at)
	var pad := {"name": "PDI", "tig": tig}
	last_pad = pad
	pads["pdi"] = pad
	plan["pdi_tig"] = tig
	plan["pdi_pad_tig"] = tig
	var text := "PDI PAD: TIG %s, state vector uplinked" % Units.hms(tig)
	Bus.set_value("mission.pad_text", text)
	_say("Houston: Eagle, we've uplinked your state vector. " + text)
	_fire("pad_pdi")
	return pad


## The ascent PAD, with the LM on the surface: the RTCC times the liftoff
## for the CSM to lead the LM by the insertion phase angle (mission.json
## "ascent") at insertion, flying P12's own guidance, in the first window
## ten minutes out or later, and no earlier than GET [param earliest]. The
## ground uplinks the LM's state vector and its spot as the landing site,
## the CSM's state vector, and the liftoff time [simplified: as MSFN
## tracked them, the truth]. Returns the PAD (Rtcc.plan_liftoff()), or {}
## without a landed LM.
func ascent_pad(earliest: float = -1.0) -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	var lm := dynamics.lm
	var pad := {}
	if lm != null and lm.landed and lgc != null:
		var site := lm.landed_pos.normalized() * Terrain.radius_under(lm.landed_pos)
		var f := SpacecraftData.lm_full_loads()
		var mass := SpacecraftData.lm_total_mass("lm_ascent", 0.0, float(Bus.get_value("lm.aps.prop_kg", f[1])),
			float(Bus.get_value("lm.rcs.prop_kg", f[2])))
		var phase_deg := float(mission.section("ascent")["insertion_phase_deg"])
		pad = Rtcc.plan_liftoff(site, mass, dynamics.traj.clone(), phase_deg,
			maxf(SimClock.get_seconds + 600.0, earliest))
		if not pad.is_empty():
			lgc.uplink_state(lm.traj)
			lgc.uplink_landing_site(site)
			lgc.uplink_csm_state(dynamics.traj)
			lgc.uplink_liftoff(float(pad["tig"]))
	last_pad = pad
	if pad.is_empty():
		_say("Houston: no ascent solution.")
		return {}
	pads["ascent"] = pad
	plan["liftoff_tig"] = pad["tig"]
	var text := "ASCENT PAD: TIG %s  N76 VH %.1f HDOT %.1f ft/s  XRNG %.2f nmi  INSERTION %s, %.1f x %.1f nmi" % [
		Units.hms(float(pad["tig"])), float(pad["vh"]) / Units.FT, float(pad["hdot"]) / Units.FT,
		float(pad["xrng"]) / Units.NMI, Units.hms(float(pad["insertion_get"])), float(pad["hp"]) / Units.NMI,
		float(pad["ha"]) / Units.NMI]
	Bus.set_value("mission.pad_text", text)
	_say("Houston: Eagle, your ascent PAD. " + text)
	_fire("pad_ascent")
	return pad


## The CSI PAD, with the LM in orbit after insertion: the RTCC's plan for
## the coelliptic sequence (Rtcc.plan_rendezvous()), with TPI as long after
## insertion as Apollo 11 had it (mission.json "rendezvous"). The ground
## uplinks CSI's and TPI's TIGs, and the CSM's state vector as MSFN tracked
## it, off by its tracking error. Returns the PAD, or {} without an LM in
## orbit.
func csi_pad() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	var lm := dynamics.lm
	var pad := {}
	var r := mission.section("rendezvous")
	if lm != null and not lm.landed and lgc != null:
		var g := SpacecraftData.section("rendezvous_guidance")
		var ins := event_get("lm_insertion")
		if ins < 0.0:
			ins = SimClock.get_seconds
		pad = Rtcc.plan_rendezvous(lm.traj, dynamics.traj, lm.mass, ins + float(r["tpi_after_insertion_s"]),
			deg_to_rad(float(g["tpi_elevation_deg"])), deg_to_rad(float(g["tpi_transfer_deg"])))
	last_pad = pad
	if pad.is_empty():
		_say("Houston: no CSI solution.")
		return {}
	pads["csi"] = pad
	plan["csi_tig"] = pad["tig"]
	plan["tpi_tig"] = pad["tpi_get"]
	lgc.uplink_rendezvous(float(pad["tig"]), float(pad["tpi_get"]))
	var csm := dynamics.traj.clone()
	var lv := Trajectory.lvlh_basis(csm.pos(), csm.vel())
	var dp: Vector3 = lv * _v3(r["csm_state_error_lvlh_m"])
	var dv: Vector3 = lv * _v3(r["csm_state_error_lvlh_mps"])
	for i in 3:
		csm.s[i] += dp[i]
		csm.s[3 + i] += dv[i]
	lgc.uplink_csm_state(csm)
	var text := "CSI PAD: TIG %s  N81 DVX %+.1f ft/s  BURN %.0f s  CDH %s %.1f ft/s  TPI %s %.1f ft/s  BRAKING %.1f ft/s" % [
		Units.hms(float(pad["tig"])), float(pad["dv"]) / Units.FT, float(pad["burn_s"]), Units.hms(float(pad["cdh_get"])),
		float(pad["cdh_dv"]) / Units.FT, Units.hms(float(pad["tpi_get"])), float(pad["tpi_dv"]) / Units.FT,
		float(pad["braking_dv"]) / Units.FT]
	Bus.set_value("mission.pad_text", text)
	_say("Houston: Eagle, your CSI PAD. " + text)
	_fire("pad_csi")
	return pad


# --- the timeline -------------------------------------------------------------------

func _timeline_entries() -> Array:
	return mission.section("lunar_timeline").get("entries", [])


func _timeline_entry(id: String) -> Dictionary:
	for e in _timeline_entries():
		if str(e["id"]) == id:
			return e
	return {}


## An entry's GET: its own, or its offset from a mission event or a planned
## time; -1 while that event hasn't happened or that time isn't planned.
func _entry_time(e: Dictionary) -> float:
	if e.has("get"):
		return _get_s(e["get"])
	if e.has("after"):
		var t := event_get(str(e["after"]))
		return t + float(e["s"]) if t >= 0.0 else -1.0
	if e.has("before"):
		var t := float(plan.get(str(e["before"]), -1.0))
		return t - float(e["s"]) if t >= 0.0 else -1.0
	return -1.0


## Mission Control's timeline, up to now: each entry that has come due
## happens if its condition holds, and is passed by if it doesn't, or if it
## is more than TIMELINE_GRACE_S late.
func _timeline() -> void:
	var now := SimClock.get_seconds
	for e in _timeline_entries():
		var id := str(e["id"])
		if timeline_done.has(id):
			continue
		var t := _entry_time(e)
		if t < 0.0 or now < t - 1e-6:
			continue
		var pending: bool = e.has("pad") and float(plan.get(PAD_PENDING.get(str(e["pad"]), ""), -1.0)) > now
		if now - t > TIMELINE_GRACE_S or pending or not _condition(str(e.get("when", ""))):
			timeline_done[id] = -1.0
			continue
		timeline_done[id] = now
		if e.has("say"):
			_say(str(e["say"]))
		if e.has("pad"):
			# With "near", the opportunity nearest that GET: the first after
			# half the CSM's orbit before it.
			var earliest := -1.0
			if e.has("near"):
				earliest = _get_s(e["near"]) - 0.5 * float(dynamics.traj.conic()["period"])
			request_pad(str(e["pad"]), earliest)
		_fire("timeline_" + id)
	Bus.set_value("mission.next_event_get_s", _timeline_next(now))


## The GET of the timeline's next entry after [param now] that would
## happen as things stand, or -1: time acceleration drops back there, and
## not at an entry that would be passed by.
func _timeline_next(now: float) -> float:
	var next := -1.0
	for e in _timeline_entries():
		var t := _entry_time(e)
		if timeline_done.has(str(e["id"])) or t <= now + 1e-6 or (next >= 0.0 and t >= next):
			continue
		var pending: bool = e.has("pad") and float(plan.get(PAD_PENDING.get(str(e["pad"]), ""), -1.0)) > t
		if not pending and _condition(str(e.get("when", ""))):
			next = t
	return next


## Pass by every entry due before GET [param t] that hasn't happened.
func _timeline_pass_by(t: float) -> void:
	for e in _timeline_entries():
		var id := str(e["id"])
		var te := _entry_time(e)
		if not timeline_done.has(id) and te >= 0.0 and te < t - 1e-6:
			timeline_done[id] = -1.0


## A timeline entry's condition ("when").
func _condition(when: String) -> bool:
	var lm := dynamics.lm
	var tr := dynamics.traj
	var in_orbit := tr.primary == "moon" and float(tr.conic()["energy"]) < 0.0
	var before_landing := lm != null and not lm.landed and not _has("lm_landing")
	var ok := true
	match when:
		"docked":
			# The whole LM docked, in lunar orbit.
			ok = in_orbit and dynamics.config == "csm_lm" and dynamics.lm_config == "lm"
		"lm_free":
			# The LM flying free, before it has landed.
			ok = before_landing
		"lm_descent":
			# ...and within DESCENT_LEAD_S of the landing time.
			ok = before_landing and SimClock.get_seconds > float(mission.section("landing")["get_s"]) - DESCENT_LEAD_S
		"lm_landed":
			ok = lm != null and lm.landed
		"lm_orbit":
			# The ascent stage in orbit.
			ok = lm != null and not lm.landed and _has("lm_insertion")
		"docked_ascent":
			ok = in_orbit and dynamics.config == "csm_lm" and dynamics.lm_config == "lm_ascent"
		"csm_orbit":
			# Columbia alone in lunar orbit, the LM jettisoned.
			ok = in_orbit and dynamics.config == "csm" and lm == null
	return ok


# --- the LM's start phases ---------------------------------------------------------

## The LM's start phases, flown on from the lunar orbit start, docked until
## Apollo 11's undocking, through the RTCC's own solutions and the
## timeline's PADs. Eagle undocks and flies the DOI PAD for the landing pass
## [simplified: the RTCC's model of P40's burn], and lunar_descent starts
## 20 minutes before PDI. Eagle lands at the site at the time DOI planned
## for, and lunar_surface starts 10 minutes after. The ascent PAD comes at
## its time, and lunar_ascent starts 20 minutes before the liftoff it
## gives.
func _lm_start(p_phase: String) -> void:
	var lgc: Lgc = systems["lgc"]
	# [simplified] Columbia drifts in CMC MODE FREE while Eagle flies.
	Bus.set_value("ctl.cmc.mode", 0)
	dynamics.undock()
	_fire("undocking")
	_advance(_entry_time(_timeline_entry("doi_pad")))
	if not plan.has("doi_tig"):
		request_pad("doi")
	var doi: Dictionary = pads["doi"]
	_advance(float(doi["tig"]))
	var lm := dynamics.lm
	var m0 := lm.mass
	var m1 := Rtcc.simulate_dps_burn(lm.traj, m0, doi["dv_lvlh"])
	var dps: Dps = systems["dps"]
	dps.restore({"prop_kg": dps.prop_kg - (m0 - m1), "level": 0.0, "ignitions": 1,
		"burn_time": float(doi["burn_s"])})
	lm.mass = m1
	_advance(lm.traj.t)
	if p_phase == "lunar_descent":
		_advance(float(plan["pdi_tig"]) - 1200.0)
		lgc.nav = lm.traj.clone()
		return
	var t_land := float(doi["land_get"])
	_advance(t_land)
	_set_lm_landed(t_land)
	var left := float(mission.section("landing")["dps_prop_left_kg"])
	lm.mass -= dps.prop_kg - left
	dps.restore({"prop_kg": left, "level": 0.0, "ignitions": 2,
		"burn_time": float(doi["burn_s"]) + float(SpacecraftData.section("descent_guidance")["descent_s"])})
	_fire("lm_landing")
	lgc.nav = lm.traj.clone()
	lgc.nav_landed_mf = Vector3.ZERO
	if p_phase == "lunar_surface":
		_advance(t_land + 600.0)
		return
	_advance(_entry_time(_timeline_entry("ascent_pad")))
	_advance(float(plan["liftoff_tig"]) - 1200.0)


## Coast both vehicles to GET [param t], the landed LM held on the surface,
## the timeline happening at each entry's time on the way.
func _advance(t: float) -> void:
	while SimClock.get_seconds < t - 1e-6:
		var next := t
		for e in _timeline_entries():
			var te := _entry_time(e)
			if not timeline_done.has(str(e["id"])) and te > SimClock.get_seconds + 1e-6 and te < next:
				next = te
		dynamics.traj.coast_to(next, 60.0)
		var lm := dynamics.lm
		if lm != null:
			if lm.landed:
				lm.hold_on_surface(next)
			else:
				lm.traj.coast_to(next, 60.0)
		SimClock.set_time(next)
		dynamics.publish_state()
		_timeline()


## Set Eagle down at the landing site at GET [param t], upright, facing
## along Columbia's track.
func _set_lm_landed(t: float) -> void:
	var lm := dynamics.lm
	var cm := Dynamics.lm_cm_height(lm.config)
	var site := landing_site()
	var up := Rtcc.site_at(site, t).normalized()
	var pos := up * (site.length() + cm)
	lm.traj.set_state("moon", t, pos, Bodies.moon_omega(t).cross(pos))
	var tr := dynamics.traj
	var fwd := tr.pos().cross(tr.vel()).normalized().cross(up).normalized()
	lm.attitude.q = Basis(up, fwd.cross(up), fwd).get_rotation_quaternion()
	lm.attitude.omega = Vector3.ZERO
	lm.land(site.length() + cm)
	dynamics.publish_state()


# --- helpers ---------------------------------------------------------------------

## A GET given in seconds, or as "hhh:mm:ss".
static func _get_s(v: Variant) -> float:
	if v is String:
		var parts := (v as String).split(":")
		return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
	return float(v)


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## The landing site in the Moon-fixed frame, on the surface there, m.
func landing_site() -> Vector3:
	var l := mission.section("landing")
	var lat := float(l["lat_deg"])
	var lon := float(l["lon_deg"])
	return Bodies.selenographic_to_fixed(lat, lon, Bodies.R_MOON + Terrain.height(lat, lon))


## The GET event [param id] fired at, or -1 if it hasn't.
func event_get(id: String) -> float:
	for e in events:
		if e["id"] == id:
			return float(e["get_s"])
	return -1.0


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
		"tli_cutoff_get": tli_cutoff_get, "o2_failed": _o2_failed, "plan": plan.duplicate(),
		"timeline_done": timeline_done.duplicate()}


func restore(d: Dictionary) -> void:
	phase = str(d["phase"])
	events = d["events"].duplicate(true)
	visited_lunar_orbit = bool(d["visited_lunar_orbit"])
	tli_cutoff_get = float(d["tli_cutoff_get"])
	_o2_failed = bool(d.get("o2_failed", false))
	plan = d.get("plan", {}).duplicate()
	timeline_done = d.get("timeline_done", {}).duplicate()
	pads = {}
	Bus.set_value("mission.phase", phase)
	for e in events:
		Bus.set_value("mission.event." + str(e["id"]), float(e["get_s"]))

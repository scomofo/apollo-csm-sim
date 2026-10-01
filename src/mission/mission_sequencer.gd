## Runs the mission: builds the start state for a phase, tracks the flight
## phase from truth, performs the Saturn/IU automation (TLI), carries out
## crew separation commands, and plays Mission
## Control: PAD requests are solved by the RTCC and uplinked to the CMC, or
## to the LGC for the LM's burns, its descent and its ascent. It calls the
## LM's landing, liftoff and insertion. It follows the mission's timeline
## (mission.json "timeline"): CAPCOM's calls and the PADs, each at its
## time, as the flight had them. CAPCOM calls each vehicle by its call
## sign (Mission.words()).
##
## A mission without an LM (SpacecraftData.carries_lm(), Apollo 8) flies
## the CSM alone from CSM/LV SEP, and its lunar orbit's plane is set by a
## site on its ground track (mission.json "lunar_site") where a landing
## mission's is set by its landing site.
##
## The ground knows the CSM as MSFN tracks it: its truth off by a tracking
## error drawn for each request (tracked_state()). The RTCC plans the
## CSM's PADs from that state, and uplinks it with them to the CMC (P27),
## which takes it in P00 with UP TLM CM in ACCEPT; otherwise CAPCOM reads
## the PAD up by voice. The flight's dispersions, those errors, the CSM's
## unmodelled forces (Dynamics.disperse()) and its IMU's gyro drift, come
## from the mission's seed (mission.json "dispersions").
##
## Each start phase starts the CMC's IMU freshly aligned to the REFSMMAT
## the crew would have had then (start_refsmmat()).
##
## In lunar orbit the flight phase follows the LM: lunar_descent from DOI
## (the LM's perilune brought low) to touchdown, lunar_surface while it is
## landed, and lunar_ascent from liftoff until it docks. An LM that doesn't
## land (Apollo 10) stages in orbit: lunar_ascent from staging, and its
## ascent engine's burn there is its insertion.
##
## The ground answers the LGC's software restarts (slice 9b): GO on the
## first Executive overflow alarm half a minute after it, as Apollo 11's
## came while Houston's guidance officer and his back room looked it up,
## and on each after it within seconds, "same type" [published: the Apollo
## 11 air-to-ground transcript, 102:38:53 and 102:42:25 GET, and Eyles,
## 2004].
##
## The launch's aborts (slice 9d): the ground marks the abort modes as
## Apollo 11's did (_launch_abort_mode(), mission.json "launch_aborts"),
## and lights ABORT a few seconds after a failure that ends the launch;
## an abort (Eds) cuts the launch vehicle off and, with the tower on,
## sends the CM away under it (Les), or separates the CSM 3 s later; the
## ground plans mode III's and IV's burns (_abort_pad()), and the flight
## ends at a splashdown down the range, or in orbit ("earth_orbit").
##
## The ground reads the CSM's telemetry (slice 10c, _ground_calls()): lost
## with the spacecraft powered, EECOM's "SCE to AUX" comes about a minute
## on, and fuel cells it shows tripped off their buses bring a call to
## reset them, as Apollo 12's lightning did.
##
## Reads:  ctl.seq.csm_sep, ctl.seq.undock, ctl.seq.lm_jett,
##         ctl.seq.cm_sm_sep, ctl.lm.stage (crew pushbuttons,
##         edge-triggered), ctl.ground.pad_request (String),
##         lm.guid.restarts, lm.guid.restart_get, lm.guid.restart_alarm,
##         tm.valid, sys.powered, eps.fc<n>_tripped
## Writes: mission.phase, mission.capcom, mission.pad_text, mission.event.<id>,
##         mission.result, mission.tli_tig, mission.next_event_get_s (the
##         timeline's next entry or the scripted failure, which SimClock
##         drops time acceleration at), mission.launch_mode (the abort mode
##         the launch is in), mission.abort_mode (its abort's),
##         mission.abort_downrange_nmi (the abort's splashdown's)
class_name MissionSequencer
extends Node

signal event_fired(id: String)
signal capcom(text: String)

const PHASES := ["launch", "parking_orbit", "tli", "translunar_coast", "lunar_orbit", "lunar_descent",
	"lunar_surface", "lunar_ascent", "tei", "transearth_coast", "entry", "splashdown", "lost"]
## Start phases that aren't flight phases: tank_failure, minutes before
## Apollo 13's oxygen tank failed (mission.json "tank_failure"), in its
## translunar coast.
const START_ONLY := ["tank_failure"]
## The start phases flown on from the lunar orbit start with the LM
## (_lm_start()).
const LM_PHASES := ["lunar_descent", "lunar_surface", "lunar_ascent"]
## A free LM whose orbit's perilune is below this height (above the
## reference sphere) is descending: DOI takes it to 15 km.
const DESCENT_PERILUNE_M := 50000.0
## Past a flyby's pericynthion (Apollo 13's), this far from the Moon's
## centre the flight is on its way home, m: beyond where an LOI burn,
## which straddles its pericynthion, can still be climbing.
const FLYBY_PAST_M := 2.0 * Bodies.R_MOON
## A timeline entry this late (past its time by a coast step, or a PAD
## that came late) still happens; later than this, it is passed by.
const TIMELINE_GRACE_S := 600.0
## How long after the LGC's restart the ground calls GO: the flight's
## first, and the later ones (Apollo 11's: 31 s and 7 s).
const ALARM_GO_FIRST_S := 30.0
const ALARM_GO_AGAIN_S := 7.0
## How long the ground takes to call "SCE to AUX" once the CSM's telemetry
## is lost with the spacecraft powered, and to call a reset of the fuel
## cells once its telemetry shows them off their buses [derived: Apollo
## 12's, the telemetry lost at the strike, 36.5 s, EECOM's "SCE to
## Auxiliary" at 1:36; the reset at 2:19, 29 s after the crew's "SCE to
## Aux" at 1:50 on the onboard tape (the Apollo Flight Journal); the
## Mission Director's report has the SCE working again at 97.5 s].
const TM_CALL_S := 59.5
const FC_RESET_CALL_S := 29.0
## The planned time that marks each PAD as still to be flown: the timeline
## doesn't uplink one while the last is.
const PAD_PENDING := {"doi": "doi_tig", "pdi": "pdi_pad_tig", "ascent": "liftoff_tig", "csi": "csi_tig",
	"tei": "tei_tig"}
## The DOI PAD comes after an undocking only this close to the landing
## time: an undocking a day early is for practice.
const DESCENT_LEAD_S := 6.0 * 3600.0
## The conditions a timeline entry may name ("when") besides a flight
## phase (_condition()).
const CONDITIONS := ["", "separated", "docked", "lm_free", "lm_descent", "lm_landed", "lm_orbit", "docked_ascent",
	"csm_orbit", "earth_return", "lifeboat", "tde"]
## The PADs a timeline entry may bring ("pad"): request_pad()'s, and for a
## maneuver the entry fixes itself (maneuver_pad()) "sep", the CSM's, or
## the LM's "phasing" and "insertion".
const PAD_KINDS := ["mcc", "loi", "circ", "plane", "shape", "tei", "sv", "lm_sv", "doi", "pdi", "n69", "ascent", "csi",
	"tweak", "entry", "coarse", "refsmmat", "sep", "phasing", "insertion"]
## The CSM's fixed maneuvers from this ΔV are the SPS's (P40), smaller ones
## the SM RCS's (P41), m/s.
const SPS_MIN_MPS := 10.0 * Units.FT
## A milli-earth-rate unit, the gyros' drift's unit: 0.015 deg/h, in rad/s.
const MERU_RAD_S := 0.015 * PI / 180.0 / 3600.0
## A launch abort's orbit is safe (phase "earth_orbit") with its perigee
## this high, m: 75 nmi [estimated].
const SAFE_PERIGEE_M := 75.0 * Units.NMI

var mission: Mission
var dynamics: Dynamics
var systems: Dictionary = {}
## The failure catalog at work (slice 9a): a failure's event and the crew's
## call are the flight's.
var failures: Failures:
	set(f):
		failures = f
		f.failed.connect(_on_failure)
		event_fired.connect(f.on_event)

var phase: String = ""
var events: Array = []
var visited_lunar_orbit: bool = false
## Where the lunar orbit start phase puts Columbia along its orbit (mean
## anomaly at its start, rad), found once in a process for each mission
## and model (_lunar_orbit_start()).
static var _start_phase_cache: Dictionary = {}
var tli_pad: Dictionary = {}
var tli_cutoff_get: float = -1.0
var last_pad: Dictionary = {}
## The last PAD of each kind (not in checkpoints).
var pads: Dictionary = {}
## The GETs the ground has planned, which the timeline counts from:
## doi_tig, pdi_tig, liftoff_tig, csi_tig, tpi_tig, tei_tig, and each fixed
## maneuver's, <its PAD's kind>_tig.
var plan: Dictionary = {}
## The timeline's entries done: id to the GET each happened at, or -1 for
## one passed by (its condition didn't hold then, or the start came after).
var timeline_done: Dictionary = {}
## The LGC's software restarts the ground has answered.
var alarms_answered: int = 0
## The launch's abort (slice 9d): the mode the ground called for it, or
## the flight was in ("IA" to "IV"), empty before; whether and when (GET)
## the ground will light ABORT for a failure, and whether that failure
## needs the crew home at once; and the launch's calls of the mode said.
var abort_mode: String = ""
var ground_abort_due: bool = false
var ground_abort_get: float = 0.0
var ground_abort_return: bool = false
var mode_calls_said: int = 0
## The ground's calls on the telemetry and power (_ground_calls()): the GET
## the CSM's telemetry was lost, and that its fuel cells were seen off
## their buses, or -1; and whether each has had its call.
var tm_lost_get: float = -1.0
var tm_call_said: bool = false
var fc_trip_get: float = -1.0
var fc_call_said: bool = false
## The seed the flight's dispersions are drawn from.
var dispersion_seed: int = 0
var _edges: Dictionary = {}
## MSFN's tracking errors, drawn from the seed request by request.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.MISSION)
	for ch in ["ctl.seq.csm_sep", "ctl.seq.undock", "ctl.seq.lm_jett", "ctl.seq.cm_sm_sep", "ctl.lm.stage"]:
		_edges[ch] = bool(Bus.get_value(ch, false))
	Bus.subscribe("ctl.ground.pad_request", _on_pad_request)
	if dynamics != null:
		dynamics.docking_contact.connect(_on_docking_contact)
		dynamics.lm_touchdown.connect(_on_lm_touchdown)
		dynamics.lm_liftoff.connect(_on_lm_liftoff)
	if systems.has("lv"):
		systems["lv"].event_fired.connect(_on_lv_event)
	if systems.has("eds"):
		systems["eds"].abort_started.connect(_on_abort)
		systems["eds"].csm_separated.connect(_on_abort_separation)
	if systems.has("les"):
		systems["les"].tower_jettisoned.connect(_on_tower_jettisoned)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)
	Bus.unsubscribe("ctl.ground.pad_request", _on_pad_request)
	if dynamics != null and dynamics.docking_contact.is_connected(_on_docking_contact):
		dynamics.docking_contact.disconnect(_on_docking_contact)
	if dynamics != null and dynamics.lm_touchdown.is_connected(_on_lm_touchdown):
		dynamics.lm_touchdown.disconnect(_on_lm_touchdown)
	if dynamics != null and dynamics.lm_liftoff.is_connected(_on_lm_liftoff):
		dynamics.lm_liftoff.disconnect(_on_lm_liftoff)
	if systems.has("lv") and is_instance_valid(systems["lv"]) and systems["lv"].event_fired.is_connected(_on_lv_event):
		systems["lv"].event_fired.disconnect(_on_lv_event)
	if systems.has("eds") and is_instance_valid(systems["eds"]) and systems["eds"].abort_started.is_connected(_on_abort):
		systems["eds"].abort_started.disconnect(_on_abort)
		systems["eds"].csm_separated.disconnect(_on_abort_separation)
	if systems.has("les") and is_instance_valid(systems["les"]) \
			and systems["les"].tower_jettisoned.is_connected(_on_tower_jettisoned):
		systems["les"].tower_jettisoned.disconnect(_on_tower_jettisoned)


# --- start states ------------------------------------------------------------

## The parking orbit at insertion: circular, in the plane the mission gives
## (inclination and ascending node in ECI), or without one in the lunar
## orbit plane, at the given argument of latitude.
func _parking_orbit_traj() -> Trajectory:
	var po := mission.section("parking_orbit")
	var r := Bodies.R_EARTH + float(po["alt_km"]) * 1000.0
	var v := sqrt(Bodies.MU_EARTH / r)
	var pl := Bodies.moon_plane()
	var p := Vector3(pl[0], pl[1], pl[2])
	var q := Vector3(pl[3], pl[4], pl[5])
	if po.has("raan_deg"):
		var i := deg_to_rad(float(po["inclination_deg"]))
		var o := deg_to_rad(float(po["raan_deg"]))
		p = Vector3(cos(o), sin(o), 0.0)
		q = Vector3(-sin(o) * cos(i), cos(o) * cos(i), sin(i))
	var u := deg_to_rad(float(po.get("arg_lat_deg", 0.0)))
	var tr := Trajectory.new()
	tr.set_state("earth", float(po["insertion_get_s"]), (p * cos(u) + q * sin(u)) * r, (-p * sin(u) + q * cos(u)) * v)
	return tr


func _stack_mass() -> float:
	return SpacecraftData.total_mass("stack", float(Bus.get_value("sps.prop_kg", _sps_load())),
		float(Bus.get_value("rcs.sm_prop_kg", _sm_rcs_load())), float(Bus.get_value("rcs.cm_prop_kg", _cm_rcs_load())),
		float(Bus.get_value("sivb.prop_kg", SpacecraftData.section("sivb")["propellant_kg"])))


## The propellant loaded, kg: the SPS's, the SM RCS's four quads', the CM
## RCS's two rings'.
static func _sps_load() -> float:
	return float(SpacecraftData.section("sps")["propellant_kg"])


static func _sm_rcs_load() -> float:
	return 4.0 * float(SpacecraftData.section("sm_rcs")["quad_propellant_kg"])


static func _cm_rcs_load() -> float:
	return 2.0 * float(SpacecraftData.section("cm_rcs")["ring_propellant_kg"])


## TLI, planned by the RTCC for the pericynthion the flown trajectory had
## (mission.json "tli": aim_pericynthion_nmi, at aim_pericynthion_get),
## after the timeline's maneuvers aim_after names, if any.
func _plan_tli(tr: Trajectory) -> Dictionary:
	var t := mission.section("tli")
	var c3 := float(t["c3_m2_per_s2"])
	var n: Array = t["plane_normal"]
	var aim := {"perigee_frac": float(t.get("perigee_arc_fraction", 0.5)), "after": []}
	for id in t.get("aim_after", []):
		aim["after"].append(_fixed_maneuver(_timeline_entry(str(id))))
	return Rtcc.plan_tli(tr, _stack_mass(), float(Bus.get_value("sivb.prop_kg", SpacecraftData.section("sivb")["propellant_kg"])),
		c3 / 2.0, -Bodies.MU_EARTH / c3 * (1.0 - float(t["eccentricity"])), Vector3(n[0], n[1], n[2]),
		float(t["aim_pericynthion_nmi"]) * Units.NMI, _get_s(t["aim_pericynthion_get"]),
		maxf(float(t["earliest_get_s"]), tr.t + 600.0), aim)


## Put the vehicle in the requested phase. Later phases are produced by
## flying the earlier ones through the RTCC's own solutions, so every start
## state is consistent with the mission it continues.
func start(p_phase: String) -> void:
	if not PHASES.has(p_phase) and not START_ONLY.has(p_phase):
		# A typo in --phase= used to fall through silently and start in
		# parking orbit; say so loudly instead. Real but non-startable
		# phase names (e.g. "tli") still start from parking orbit and are
		# re-derived from the truth trajectory below.
		push_error("MissionSequencer.start: unknown phase '%s'; starting in parking orbit" % p_phase)
	elif p_phase in LM_PHASES and not SpacecraftData.carries_lm():
		push_error("MissionSequencer.start: %s carries no LM; starting in lunar orbit" % mission.id())
		p_phase = "lunar_orbit"
	events.clear()
	visited_lunar_orbit = false
	abort_mode = ""
	Bus.set_value("mission.abort_mode", "")
	ground_abort_due = false
	ground_abort_return = false
	mode_calls_said = 0
	tm_lost_get = -1.0
	tm_call_said = false
	fc_trip_get = -1.0
	fc_call_said = false
	tli_pad = {}
	tli_cutoff_get = -1.0
	pads = {}
	plan = {}
	timeline_done = {}
	_disperse()
	var tr := _parking_orbit_traj()
	var cfg := "stack"
	# The CSM on its way, with the LM docked or alone.
	var docked := "csm_lm" if SpacecraftData.carries_lm() else "csm"
	var sps_prop := _sps_load()
	var sivb_prop := float(SpacecraftData.section("sivb")["propellant_kg"])
	if p_phase == "launch":
		# On the pad, the Saturn V turning with the Earth.
		cfg = "saturn_v"
		var l := mission.section("launch")
		var lv: LaunchVehicle = systems["lv"]
		lv.arm(l, _insertion_target())
		tr = Trajectory.new()
		tr.set_state_d("earth", float(l["start_get_s"]), lv.pad_state(float(l["start_get_s"])))
		# The escape tower on, the EDS ready, ELS AUTO as the launch has it.
		if systems.has("les"):
			systems["les"].arm()
		if systems.has("eds"):
			systems["eds"].arm()
		Bus.set_value("ctl.els.auto", true)
		for c: Array in mission.section("launch_aborts").get("calls", []):
			if float(c[0]) < float(l["start_get_s"]):
				mode_calls_said += 1
	elif systems.has("lv"):
		systems["lv"].state = "idle"
		if systems.has("les"):
			systems["les"].stow()
	if p_phase != "launch" and failures != null:
		# The failures the mission arms on the liftoff (Apollo 12's
		# lightning) come only in the launch.
		failures.disarm_on("liftoff")
	if p_phase == "translunar_coast":
		var pad := _plan_tli(tr)
		assert(not pad.is_empty(), "no TLI solution")
		tr.coast_to(float(pad["tig"]), 30.0)
		sivb_prop = Sivb.simulate_burn(tr, _stack_mass(), sivb_prop, pad["target"])
		tr.coast_to(tr.t + float(mission.data.get("tde_delay_s", 3600.0)), 60.0)
		cfg = docked
	if p_phase == "tank_failure":
		# TLI, and the coast out to minutes before the tank failed, through
		# the midcourse corrections the timeline had flown on the SPS by then
		# (mission.json "tank_failure": mcc, the timeline's entries).
		var pad := _plan_tli(tr)
		assert(not pad.is_empty(), "no TLI solution")
		tr.coast_to(float(pad["tig"]), 30.0)
		sivb_prop = Sivb.simulate_burn(tr, _stack_mass(), sivb_prop, pad["target"])
		cfg = docked
		var tf := mission.section("tank_failure")
		var mass := SpacecraftData.total_mass(docked, sps_prop, _sm_rcs_load(), _cm_rcs_load(), 0.0)
		for id in tf.get("mcc", []):
			var e := _timeline_entry(str(id))
			tr.coast_to(_entry_time(e), 60.0)
			var mcc := _plan_translunar_mcc(tr, mass, _get_s(e["tig"]))
			if not mcc.is_empty() and float(mcc["dv"]) > 0.0:
				tr.coast_to(float(mcc["tig"]), 30.0)
				var after := Rtcc.simulate_sps_burn(tr, mass, mcc["dv_lvlh"])
				sps_prop -= mass - after
				mass = after
		tr.coast_to(_get_s(tf["start_get"]), 60.0)
	if p_phase in ["lunar_orbit", "tei", "transearth_coast", "entry"] + LM_PHASES:
		visited_lunar_orbit = true
		cfg = docked
		tr = _lunar_orbit_start()
		# The SPS's burns to here: the midcourse corrections, LOI-1 and
		# LOI-2 (mission.json "lunar_orbit": sps_dv_mps).
		var lo := mission.section("lunar_orbit")
		var mass := SpacecraftData.total_mass(docked, sps_prop, _sm_rcs_load(), _cm_rcs_load(), 0.0)
		sps_prop -= mass * (1.0 - exp(-float(lo.get("sps_dv_mps", 900.0)) / (float(SpacecraftData.section("sps")["isp_s"]) * Units.G0)))
		if _docked_doi():
			# The start is on the descent orbit the CSM's DOI left (Apollo
			# 14's), placed for the landing pass: PDI and the landing as
			# planned.
			var t_land := float(mission.section("landing")["get_s"])
			plan["land_get"] = t_land
			plan["pdi_tig"] = t_land - float(SpacecraftData.section("descent_guidance")["descent_s"])
	if p_phase in ["tei", "transearth_coast", "entry"] and _docked_doi():
		# The CSM, alone after the undocking, lifts its orbit off the
		# descent orbit at its CIRC PAD's TIG (the timeline's "circ"), as the
		# RTCC planned it [simplified: its plane change isn't flown].
		var lo := mission.section("lunar_orbit")
		var mass := SpacecraftData.total_mass("csm", sps_prop, _sm_rcs_load(), _cm_rcs_load(), 0.0)
		var r_site := landing_site().length()
		var circ := Rtcc.plan_loi2(tr, mass, r_site + float(lo["loi2_apolune_nmi"]) * Units.NMI,
			r_site + float(lo["loi2_perilune_nmi"]) * Units.NMI, _get_s(lo["loi2_tig"]), bool(lo.get("loi2_rising", false)))
		assert(not circ.is_empty(), "no CIRC solution")
		tr.coast_to(float(circ["tig"]), 30.0)
		var after := Rtcc.simulate_sps_burn(tr, mass, circ["dv_lvlh"])
		sps_prop -= mass - after
		# And its orbit shaped before TEI as the timeline's PADs plan it
		# (_shape_burn()): Apollo 15's for the subsatellite.
		for e in _timeline_entries():
			if str(e.get("pad", "")) == "shape" and _get_s(e["tig"]) < _entry_time(_timeline_entry("tei_pad")):
				mass = SpacecraftData.total_mass("csm", sps_prop, _sm_rcs_load(), _cm_rcs_load(), 0.0)
				var shape := _shape_burn(tr, mass, e)
				assert(not shape.is_empty(), "no shaping solution")
				tr.coast_to(float(shape["tig"]), 30.0)
				sps_prop -= mass - Rtcc.simulate_sps_burn(tr, mass, shape["dv_lvlh"])
	if p_phase in LM_PHASES:
		# Docked until the flown undocking.
		tr.coast_to(_get_s(mission.section("timeline")["undocking_get"]), 60.0)
	if p_phase == "tei":
		# The CSM alone, a minute before the timeline's TEI PAD.
		cfg = "csm"
		tr.coast_to(_entry_time(_timeline_entry("tei_pad")) - 60.0, 30.0)
	if p_phase in ["transearth_coast", "entry"]:
		cfg = "csm"
		var mass := SpacecraftData.total_mass("csm", sps_prop, _sm_rcs_load(), _cm_rcs_load(), 0.0)
		var tei := mission.section("tei")
		if tei.has("tig_near"):
			tr.coast_to(_get_s(tei["tig_near"]) - 1800.0, 30.0)
		var pad := _plan_tei(tr, mass, tr.t + 600.0)
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
		systems["sivb"].state = "idle" if cfg in ["saturn_v", "stack"] else "done"
	dynamics.initialize(tr.primary, tr.t, tr.pos(), tr.vel(), cfg)
	dynamics.traj.s = tr.s.duplicate()
	dynamics.publish_state()
	if p_phase == "tank_failure":
		var tf := mission.section("tank_failure")
		# The stack's attitude: the CM's gimbal angles on the start's
		# REFSMMAT (cm_gimbals_deg).
		var g: Array = tf.get("cm_gimbals_deg", [])
		if g.size() == 3:
			var body := start_refsmmat(p_phase).transposed() * Imu.gimbal_basis(Vector3(g[0], g[1], g[2]))
			dynamics.attitude.q = body.get_rotation_quaternion()
			dynamics.publish_state()
		if systems.has("eps"):
			# The cryogenic tanks as they were at the incident.
			var eps: Dictionary = tf.get("eps", {})
			for i in 2:
				systems["eps"].o2_kg[i] = float(eps["o2_kg"][i])
				systems["eps"].h2_kg[i] = float(eps["h2_kg"][i])
	if p_phase in LM_PHASES:
		_lm_start(p_phase)
	elif systems.has("lgc"):
		# The LM starts dark (its crew may power it up docked, as Apollo
		# 13's did: a power-up from the first step).
		systems["lgc"].start_dark()
	# What the timeline had due before the start is past.
	_timeline_pass_by(SimClock.get_seconds)
	phase = ""
	_update_phase()
	# The CMC starts on the state the ground last tracked, its IMU aligned,
	# and with the site P52's option 4 aligns to.
	if systems.has("agc"):
		var agc: Agc = systems["agc"]
		agc.init_nav(tracked_state(dynamics.traj))
		agc.imu.align(start_refsmmat(p_phase))
		agc.landing_site_mf = landing_site()
		agc.landing_get = site_get()
		if SimClock.get_seconds > _entry_time(_timeline_entry("entry_pad")):
			# The target the entry PAD's uplink brought.
			var target := entry_target()
			agc.entry_lat = target.x
			agc.entry_lng = target.y
	if cfg == "stack":
		tli_pad = _plan_tli(dynamics.traj)
		if not tli_pad.is_empty():
			systems["sivb"].arm_tli(float(tli_pad["tig"]), tli_pad["target"])
			Bus.set_value("mission.tli_tig", float(tli_pad["tig"]))
			_say("{mission}, Houston. You are GO for TLI. TIG %s, ΔV %.0f ft/s." % [
				Units.hms(float(tli_pad["tig"])), float(tli_pad["dv"]) / Units.FT])
	_fire("start_" + p_phase)
	# CAPCOM's word for the start (mission.json "start_calls").
	var more := {}
	if p_phase == "lunar_surface":
		more["ascent_pad"] = Units.hms(_entry_time(_timeline_entry("ascent_pad")))
	elif p_phase == "lunar_ascent":
		more["liftoff"] = Units.hms(float(plan.get("liftoff_tig", 0.0)))
	var call := str(mission.section("start_calls").get(p_phase, ""))
	if call != "":
		_say(call, more)


# --- per step -------------------------------------------------------------------

func tick(_dt: float) -> void:
	_crew_commands()
	_automation()
	_launch_aborts()
	_timeline()
	_alarm_calls()
	_ground_calls()
	_update_phase()


## The ground's calls on the CSM's telemetry and power (slice 10c): with
## the spacecraft powered and its telemetry lost (the SCE's NORM supply
## gone, tm.valid false), EECOM's "SCE to AUX" TM_CALL_S on; with the
## telemetry good and fuel cells tripped off their buses, their reset
## FC_RESET_CALL_S after it shows them. Each once, until its condition
## clears.
func _ground_calls() -> void:
	var now := SimClock.get_seconds
	var tm := bool(Bus.get_value("tm.valid", true))
	if bool(Bus.get_value("sys.powered", false)) and not tm:
		if tm_lost_get < 0.0:
			tm_lost_get = now
		if not tm_call_said and now >= tm_lost_get + TM_CALL_S - 1e-6:
			_say("{mission}, Houston. Try SCE to Auxiliary. Over.")
			tm_call_said = true
	else:
		tm_lost_get = -1.0
		tm_call_said = false
	var tripped: Array[int] = []
	for i in range(1, 4):
		if bool(Bus.get_value("eps.fc%d_tripped" % i, false)):
			tripped.append(i)
	if tm and not tripped.is_empty():
		if fc_trip_get < 0.0:
			fc_trip_get = now
		if not fc_call_said and now >= fc_trip_get + FC_RESET_CALL_S - 1e-6:
			if tripped.size() == 1:
				_say("{mission}, Houston. Try to reset fuel cell %d now." % tripped[0])
			else:
				_say("{mission}, Houston. Try to reset your fuel cells now.")
			fc_call_said = true
	else:
		fc_trip_get = -1.0
		fc_call_said = false


## GO on the LGC's restarts not yet answered: ALARM_GO_FIRST_S after the
## flight's first, ALARM_GO_AGAIN_S after any later one.
func _alarm_calls() -> void:
	var n := int(Bus.get_value("lm.guid.restarts", 0))
	if n <= alarms_answered:
		return
	var wait := ALARM_GO_FIRST_S if alarms_answered == 0 else ALARM_GO_AGAIN_S
	if SimClock.get_seconds < float(Bus.get_value("lm.guid.restart_get", 0.0)) + wait - 1e-6:
		return
	if alarms_answered == 0:
		_say("Roger. We got you. {lm}, we're GO on that alarm.")
	else:
		_say("Roger. %d alarm. We're GO. Same type." % int(Bus.get_value("lm.guid.restart_alarm", 0)))
	alarms_answered = n


func _crew_commands() -> void:
	for ch in _edges:
		var now := bool(Bus.get_value(ch, false))
		if now and not _edges[ch]:
			match ch:
				"ctl.seq.csm_sep":
					if dynamics.config == "stack" and str(Bus.get_value("sivb.state", "")) == "done":
						_separate(true)
				"ctl.seq.undock":
					if dynamics.undock():
						_lgc_undocked()
						_fire("undocking")
						_say("Houston copies undocking. {lm} is flying free.")
				"ctl.seq.lm_jett":
					if dynamics.jettison_lm():
						_fire("lm_jettison")
						_say("Houston copies LM jettison.")
				"ctl.seq.cm_sm_sep":
					if dynamics.config in ["csm", "csm_lm"]:
						# With the LM docked (Apollo 13's), it stays on the CM.
						dynamics.set_configuration("cm_lm" if dynamics.config == "csm_lm" else "cm")
						_fire("cm_sm_sep")
						_say("CM/SM separation confirmed.")
				"ctl.lm.stage":
					if dynamics.stage_lm():
						_fire("lm_staging")
						var flying := "" if dynamics.lm.landed else " {lm}'s ascent stage is flying."
						_say("Houston copies staging." + flying)
		_edges[ch] = now


## The probe met the drogue: capture docks the LM again, and the flight
## phase is the docked vehicles' from that step (the sequencer ticks
## before Dynamics). At transposition and docking the hard dock draws the
## LM out of the S-IVB's adapter [simplified: at once].
func _on_docking_contact(contact: Dictionary) -> void:
	var tde := bool(contact.get("tde", false))
	if contact["captured"] and tde:
		_fire("transposition_docking")
		_say("Houston confirms hard dock and LM extraction. {csm} and {lm} are on their way.")
		_update_phase()
	elif contact["captured"]:
		_fire("docking")
		_say("Houston copies hard dock. {csm} and {lm} are docked.")
		_update_phase()
	else:
		_fire("docking_contact")
		_say("Houston: contact, %s. Back off and try again." % Docking.describe(contact))


## Eagle's footpads met the surface.
func _on_lm_touchdown(touchdown: Dictionary) -> void:
	_fire("lm_landing")
	_lgc_drift(true)
	if touchdown["hard"]:
		_say("Houston: we saw a hard landing, %.1f ft/s down and %.1f ft/s across. Check your gear." % [
			float(touchdown["vertical_mps"]) / Units.FT, float(touchdown["horizontal_mps"]) / Units.FT])
	else:
		_say("Houston: Roger, {lm_landed}. We copy you on the ground.")


## The LM left the surface.
func _on_lm_liftoff(_get_s: float) -> void:
	_fire("lm_liftoff")
	_lgc_drift(false)
	_say("Houston: we have liftoff. {lm}, you're looking good.")


## The LGC's abort from the powered descent (slice 9e): P70 or P71 under
## way. The ground takes the rendezvous from the orbit it reaches, TPI at
## the time the PDI PAD gave for the abort (plan "abort_tpi"; csi_pad()).
func _check_lm_abort() -> void:
	if _has("lm_abort") or not int(Bus.get_value("lm.guid.program", 0)) in Lgc.ABORTS:
		return
	var lgc: Lgc = systems.get("lgc")
	plan["abort_tpi"] = lgc.abort_tpi if lgc != null else -1.0
	_fire("lm_abort")
	_say("Houston: Roger, {lm}. We copy the abort.")


## After the liftoff, after an abort from the descent, or after staging in
## orbit once the ascent engine has burned, the engines are off with the
## LM in orbit: insertion. The orbit's apsides are above the landing site.
func _check_insertion() -> void:
	var lm := dynamics.lm
	var ascended := _has("lm_liftoff") or _has("lm_abort") \
		or (_has("lm_staging") and int(Bus.get_value("lm.aps.ignitions", 0)) > 0)
	if lm == null or lm.landed or not ascended or _has("lm_insertion") or lm.traj.primary != "moon" \
			or bool(Bus.get_value("lm.aps.on", false)) or bool(Bus.get_value("lm.dps.on", false)):
		return
	var c := lm.traj.conic()
	var site_r := landing_site().length()
	if float(c["energy"]) >= 0.0 or float(c["rp"]) <= site_r:
		return
	_fire("lm_insertion")
	_say("Houston: {lm}, you're in orbit, %.1f by %.1f." % [(float(c["rp"]) - site_r) / Units.NMI,
		(float(c["ra"]) - site_r) / Units.NMI])


## CSM/LV SEP: the CSM leaves the S-IVB, and with an LM turns about,
## docks with it and draws it out [simplified: transposition, docking and
## extraction at once]; without one it flies on alone, the test article
## left in the adapter. Where the mission flies transposition and docking
## (mission.json tde_flown) the crew's CSM/LV SEP leaves the CSM free of
## its target, the LM in the adapter (Dynamics.start_tde()), for the crew
## to turn about and dock (slice 12a).
func _separate(crew: bool = false) -> void:
	Bus.set_value("sivb.prop_kg", 0.0)
	systems["sivb"].prop_kg = 0.0
	if not SpacecraftData.carries_lm():
		dynamics.set_configuration("csm")
		_fire("csm_lv_sep")
		_say("Houston copies CSM/LV SEP. {csm}, you're on your own.")
		return
	if crew and bool(mission.data.get("tde_flown", false)) and dynamics.start_tde():
		_fire("csm_lv_sep")
		_say("Houston copies CSM/LV SEP. {csm}, turn around and dock with {lm}.")
		return
	dynamics.set_configuration("csm_lm")
	_fire("transposition_docking")
	_say("Houston confirms hard dock and LM extraction. {csm} and {lm} are on their way.")


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
		# The separation (and with an LM transposition, docking and
		# extraction) happens without crew input after the scripted delay
		# if the crew has not already separated.
		if tli_cutoff_get >= 0.0 and now - tli_cutoff_get > float(mission.data.get("tde_delay_s", 3600.0)):
			_separate()
	elif dynamics.tde_in_progress() and tli_cutoff_get >= 0.0 \
			and now - tli_cutoff_get > float(mission.data.get("tde_delay_s", 3600.0)):
		# The ground's time for the LM's extraction came before the crew
		# docked [simplified: their docking taken as done].
		dynamics.finish_tde()
		_fire("transposition_docking")
		_say("Houston confirms hard dock and LM extraction. {csm} and {lm} are on their way.")
	if dynamics.landed and not _has("landing"):
		_fire("landing")
	_check_lm_abort()
	_check_insertion()


func _update_phase() -> void:
	var p := phase
	var tr := dynamics.traj
	if dynamics.landed:
		var ok := tr.primary == "earth" and dynamics.landed_speed < 15.0
		p = "splashdown" if ok else "lost"
	elif dynamics.config == "saturn_v":
		p = "launch"
	elif dynamics.config == "cm_les":
		p = "abort"
	elif dynamics.config == "cm" and tr.primary == "earth" and tr.altitude() < 1.0e6:
		p = "entry"
	elif abort_mode != "" and tr.primary == "earth":
		# After a launch abort: into orbit on the SPS (mode IV), or down.
		p = "earth_orbit" if float(tr.conic()["rp"]) > Bodies.R_EARTH + SAFE_PERIGEE_M else "abort"
	elif dynamics.config == "stack" and str(Bus.get_value("sivb.state", "")) != "done":
		p = "tli" if bool(Bus.get_value("sivb.burning", false)) else "parking_orbit"
	elif tr.primary == "moon" and float(tr.conic()["energy"]) < 0.0:
		p = _lunar_phase()
		visited_lunar_orbit = true
	elif visited_lunar_orbit or (tr.primary == "moon" and tr.radial_rate() > 0.0 and tr.radius() > FLYBY_PAST_M):
		# Home: from lunar orbit, or well past a flyby's pericynthion
		# (Apollo 13's).
		visited_lunar_orbit = true
		p = "transearth_coast"
	else:
		p = "translunar_coast"
	if p != phase:
		var was := phase
		phase = p
		Bus.set_value("mission.phase", phase)
		_fire("phase_" + phase)
		if phase == "lunar_orbit" and was in ["", "translunar_coast"]:
			_say("{csm}, Houston. We confirm lunar orbit.")
		elif phase == "splashdown" and abort_mode != "":
			# A launch abort's: how far down the range from the pad.
			Bus.set_value("mission.result", "success")
			var l := mission.section("launch")
			var dr := Bodies.surface_angle(geographic(), Vector2(float(l["pad_lat_deg"]), float(l["pad_lon_deg"]))) \
				* Bodies.R_EARTH / Units.NMI
			Bus.set_value("mission.abort_downrange_nmi", dr)
			_say("Splashdown! Welcome home, {mission}. Mode %s, %.1f nmi downrange; peak load %.1f g, touchdown %.1f m/s." % [
				abort_mode, dr, dynamics.max_g, dynamics.landed_speed])
		elif phase == "splashdown":
			Bus.set_value("mission.result", "success")
			var miss := Bodies.surface_angle(geographic(), entry_target()) * Bodies.R_EARTH / Units.NMI
			Bus.set_value("mission.splash_miss_nmi", miss)
			_say("Splashdown! Welcome home, {mission}. %.1f nmi from the target; peak load %.1f g, touchdown %.1f m/s." % [
				miss, dynamics.max_g, dynamics.landed_speed])
		elif phase == "lost":
			Bus.set_value("mission.result", "lost")
			_say("Houston... we have lost the spacecraft.")


## The parking orbit's insertion the IU's guidance flies the launch to:
## the start phase's circular orbit, its radius, speed and plane
## (Sivb.igm_burns()'s terminal point).
func _insertion_target() -> Dictionary:
	var tr := _parking_orbit_traj()
	var n := tr.pos().cross(tr.vel()).normalized()
	var r := tr.pos().length()
	return {"rt": r, "vt": sqrt(Bodies.MU_EARTH / r), "gamma": 0.0, "n": [n.x, n.y, n.z]}


## The launch vehicle's events: Mission Control's calls (mission.json
## "launch": calls, by the event); at liftoff the
## CMC's P11 on the liftoff discrete, its state vector the pad's; at
## insertion the parking orbit.
func _on_lv_event(id: String) -> void:
	_fire(id)
	var calls: Dictionary = mission.section("launch").get("calls", {})
	if calls.has(id):
		_say(str(calls[id]))
	match id:
		"les_jettison":
			if systems.has("les"):
				systems["les"].jettison()
		"liftoff":
			if systems.has("agc"):
				var agc: Agc = systems["agc"]
				agc.init_nav(dynamics.traj)
				agc.change_program(11)
		"insertion":
			_insert()


## Insertion: the stack flies on into the parking orbit, the S-IVB with the
## propellant its first burn left less what it vents and burns before its
## second (mission.json "launch"), and Mission Control plans TLI.
func _insert() -> void:
	var lv: LaunchVehicle = systems["lv"]
	var fixed := SpacecraftData.total_mass("stack", float(Bus.get_value("sps.prop_kg", 0.0)),
		float(Bus.get_value("rcs.sm_prop_kg", 560.0)), float(Bus.get_value("rcs.cm_prop_kg", 110.0)), 0.0)
	var left := maxf(lv.mass - fixed - float(mission.section("launch")["parking_orbit_loss_kg"]), 0.0)
	systems["sivb"].prop_kg = left
	systems["sivb"].state = "idle"
	Bus.set_value("sivb.prop_kg", left)
	dynamics.set_configuration("stack")
	var c: Dictionary = dynamics.traj.conic()
	_say("Roger. Shutdown. We show an orbit of %.1f by %.1f." % [(float(c["ra"]) - Bodies.R_EARTH) / Units.NMI,
		(float(c["rp"]) - Bodies.R_EARTH) / Units.NMI])
	_update_phase()
	tli_pad = _plan_tli(dynamics.traj)
	if not tli_pad.is_empty():
		systems["sivb"].arm_tli(float(tli_pad["tig"]), tli_pad["target"])
		Bus.set_value("mission.tli_tig", float(tli_pad["tig"]))


## In lunar orbit, the LM's part of the flight: its descent (from DOI, its
## perilune low, to touchdown), its stay on the surface, and its ascent
## (from liftoff, from an abort in the descent, or from staging in orbit,
## until it docks); otherwise lunar orbit.
func _lunar_phase() -> String:
	var lm := dynamics.lm
	if lm == null:
		return "lunar_orbit"
	if lm.landed:
		return "lunar_surface"
	if _has("lm_liftoff") or _has("lm_abort") or lm.config == "lm_ascent":
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


## TEI, planned by the RTCC onto the mission's return (its "tei" section:
## the return's inclination, entry interface's GET, the corridor) at the
## first opportunity after [param earliest], and none before the one
## nearest the flown TEI. A TEI with its own ignition time ("tig", Apollo
## 13's PC+2 two hours past the pericynthion of its flyby) is solved there
## (_plan_return()), on [param engine] (Rtcc.simulate_burn(): the docked
## LM's DPS).
func _plan_tei(tr: Trajectory, mass: float, earliest: float, engine: Dictionary = {}) -> Dictionary:
	var tei := mission.section("tei")
	if tei.has("tig"):
		return _plan_return(tr, mass, _get_s(tei["tig"]), tei, str(tei.get("name", "TEI")), engine)
	var near := _get_s(tei["tig_near"]) if tei.has("tig_near") else -1.0
	if near >= 0.0:
		earliest = maxf(earliest, near - 0.5 * float(tr.conic()["period"]))
	var n81: Array = tei.get("n81_ft_s", [0.0, 0.0, 0.0])
	return Rtcc.plan_tei(tr, mass, float(tei["dv_mps"]), float(tei["entry_perigee_alt_km"]) * 1000.0, earliest,
		float(tei.get("return_inclination_deg", -1.0)), _get_s(tei["ei_get"]) if tei.has("ei_get") else -1.0, near,
		_v3(n81) * Units.FT, bool(tei.get("tig_free", false)))


## A burn at [param tig] onto the return mission section [param r]
## describes: its orbit about the Earth return_inclination_deg to the
## equator and entry interface at ei_get, its vacuum perigee in the
## corridor (entry_perigee_alt_km, "tei"'s unless its own), solved from
## the flown PAD's ΔV (n81_ft_s) on [param engine] (Rtcc.tei_components()):
## Apollo 13's PC+2 ("tei") and the midcourse correction that put it back
## on a free return ("free_return"). Returns a PAD named [param name].
func _plan_return(tr: Trajectory, mass: float, tig: float, r: Dictionary, name: String, engine: Dictionary) -> Dictionary:
	var perigee := float(r.get("entry_perigee_alt_km", mission.section("tei")["entry_perigee_alt_km"])) * 1000.0
	var sol := Rtcc.tei_components(tr, tig, mass, _v3(r["n81_ft_s"]) * Units.FT, perigee,
		float(r["return_inclination_deg"]), _get_s(r["ei_get"]), engine)
	if sol.is_empty():
		return {}
	var dv: Vector3 = sol["dv_lvlh"]
	return {"name": name, "tig": tig, "dv_lvlh": dv, "dv": dv.length(),
		"burn_s": Rtcc.burn_seconds(engine, mass, dv.length()), "ei_get": sol["ei_get"], "incl": sol["incl"]}


## Solve and uplink a maneuver PAD: "mcc", "loi", "circ", "plane" (the
## plane change that puts the CSM's orbit over the LM at its planned
## liftoff, mission.json "ascent": planned_liftoff_get), "shape" (the
## timeline entry [param e]'s orbit shaping, _shape_burn()), "tei" for the
## CMC, planned from the CSM's tracked state and uplinked with it (P27;
## the PAD's "uplinked" says whether the CMC took them); "sv", that state
## alone (sv_uplink()); "lm_sv", the LM's for the LGC (lm_sv_uplink());
## "doi" for the LGC, while the LM flies free; "pdi",
## the LGC's state vector for powered descent (pdi_pad()); "n69", the
## landing site correction in powered descent (_n69_pad()); "ascent", the
## liftoff time for the LGC's P12 (ascent_pad()); "csi", the rendezvous
## plan (csi_pad()). The TEI and the liftoff come no earlier than GET
## [param earliest], and a midcourse correction then, or a quarter of an
## hour from now if later.
func request_pad(kind: String, earliest: float = -1.0, e: Dictionary = {}) -> Dictionary:
	if kind == "entry":
		return entry_pad()
	if kind == "abort":
		return _abort_pad()
	if kind == "coarse":
		return _coarse_pad(str(e.get("computer", "")))
	if kind == "refsmmat":
		return _refsmmat_pad(str(e.get("computer", "")), bool(e.get("docked", false)))
	if kind == "pdi":
		return pdi_pad()
	if kind == "n69":
		return _n69_pad()
	if kind == "ascent":
		return ascent_pad(earliest)
	if kind == "csi":
		return csi_pad()
	if kind == "tweak":
		return _tweak_pad()
	if kind == "sv":
		return sv_uplink()
	if kind == "lm_sv":
		return lm_sv_uplink()
	var tracked: Trajectory = null
	if kind != "doi" or _docked_doi():
		tracked = tracked_state(dynamics.traj)
	var tr := tracked.clone() if tracked != null else dynamics.traj.clone()
	var mass := dynamics.mass
	var now := SimClock.get_seconds
	# In the lifeboat the docked LM's engine flies the ground's burns.
	var engine := {}
	if _lifeboat() and kind in ["mcc", "tei"]:
		engine = {"engine": "dps", "throttle": e.get("throttle", mission.section("tei").get("throttle", []))}
	var pad := {}
	match kind:
		"doi":
			var g := SpacecraftData.section("descent_guidance")
			var doi := mission.section("doi")
			if _docked_doi() and dynamics.lm == null and dynamics.config == "csm_lm":
				# The CSM's, docked, on the SPS (Apollo 14's): for the landing
				# pass a day of revolutions on.
				pad = Rtcc.plan_doi_docked(tr, mass, maxf(_get_s(doi["tig"]), now + 600.0),
					float(doi["pericynthion_alt_km"]) * 1000.0, landing_site(),
					float(mission.section("landing")["get_s"]) - float(g["descent_s"]), float(g["pdi_range_m"]),
					float(g["descent_s"]))
			elif dynamics.lm != null and dynamics.lm.config == "lm" and not _docked_doi():
				pad = Rtcc.plan_doi(dynamics.lm.traj.clone(), dynamics.lm.mass,
					float(doi["pericynthion_alt_km"]) * 1000.0, landing_site(),
					float(mission.section("landing")["get_s"]), float(g["pdi_range_m"]), float(g["descent_s"]), now + 600.0)
		"loi":
			var loi := mission.section("loi")
			pad = Rtcc.plan_loi(tr, mass, float(loi["apolune_alt_km"]) * 1000.0, landing_site(), site_get(),
				float(loi.get("perilune_alt_km", -1.0)) * 1000.0, _get_s(loi["tig"]) if loi.has("tig") else -1.0)
		"circ":
			# At the flown PAD's TIG if given ("loi2_tig"), the new
			# pericynthion behind the burn point with "loi2_rising".
			var lo := mission.section("lunar_orbit")
			var r_site := landing_site().length()
			pad = Rtcc.plan_loi2(tr, mass, r_site + float(lo["loi2_apolune_nmi"]) * Units.NMI,
				r_site + float(lo["loi2_perilune_nmi"]) * Units.NMI, _get_s(lo["loi2_tig"]) if lo.has("loi2_tig") else -1.0,
				bool(lo.get("loi2_rising", false)))
			if not pad.is_empty() and dynamics.config == "csm":
				# The CSM's own, after the undocking (Apollo 14's).
				pad["name"] = "CIRC"
		"plane":
			var asc := mission.section("ascent")
			if asc.has("planned_liftoff_get"):
				var lm := dynamics.lm
				var site := lm.landed_pos if lm != null and lm.landed else landing_site()
				pad = Rtcc.plan_plane_change(tr, mass, maxf(now + 900.0, earliest), site, _get_s(asc["planned_liftoff_get"]))
		"shape":
			pad = _shape_burn(tr, mass, e)
		"tei":
			pad = _plan_tei(tr, mass, maxf(now + 900.0, earliest), engine)
		"mcc":
			var tig := maxf(now + 900.0, earliest)
			if phase == "translunar_coast" and bool(e.get("free_return", false)):
				# Back onto a free return, from the way out: the return the
				# ground chose past the Moon (Apollo 13's MCC-2, mission.json
				# "free_return").
				pad = _plan_return(tr, mass, tig, mission.section("free_return"), "MCC", engine)
			elif phase == "translunar_coast":
				pad = _plan_translunar_mcc(tr, mass, tig)
			elif phase == "transearth_coast":
				var probe := tr.clone()
				var er := Rtcc.earth_return(probe, now + 5.0 * 86400.0)
				var sense := signf(float(er["f"]))
				var target: float = sense * (Bodies.R_EARTH + float(mission.section("tei")["entry_perigee_alt_km"]) * 1000.0)
				# The corridor held to the entry's own tolerance, if it has one.
				var tol := float(e.get("tolerance_km", -1.0)) * 1000.0
				if not engine.is_empty() and float(e.get("rcs_below_ft_s", 0.0)) > 0.0:
					# A small one on the LM's jets (Apollo 13's MCC-7).
					var probe_pad := Rtcc.plan_mcc(tr, mass, tig, "earth", target, now + 5.0 * 86400.0, Vector3.ZERO,
						0.0, -1.0, Vector3.ZERO, engine, tol)
					if not probe_pad.is_empty() and float(probe_pad["dv"]) < float(e["rcs_below_ft_s"]) * Units.FT:
						engine = {"engine": "lm_rcs"}
				pad = Rtcc.plan_mcc(tr, mass, tig, "earth", target, now + 5.0 * 86400.0, Vector3.ZERO, 0.0, -1.0,
					Vector3.ZERO, engine, tol)
	if pad.is_empty() or float(pad.get("dv", 0.0)) <= 0.0:
		_say("Houston: no %s solution / burn not required." % kind.to_upper())
		last_pad = {}
		return {}
	if kind == "tei":
		plan["tei_tig"] = pad["tig"]
	if not engine.is_empty():
		pad["engine"] = engine["engine"]
		return _uplink_lgc(kind, pad, engine.get("throttle", []) if engine["engine"] == "dps" else [], tracked)
	if kind == "doi" and _docked_doi():
		# The pass it plans PDI and the landing for, until the PDI PAD has
		# PDI's time.
		plan["doi_tig"] = pad["tig"]
		plan["pdi_tig"] = pad["hp_get"]
		plan["land_get"] = pad["land_get"]
		return _uplink(kind, pad, tracked)
	if kind != "doi":
		return _uplink(kind, pad, tracked)
	last_pad = pad
	pads[kind] = pad
	plan["doi_tig"] = pad["tig"]
	# PDI at the pericynthion, until the PDI PAD has its time.
	plan["pdi_tig"] = pad["hp_get"]
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	if systems.has("lgc"):
		systems["lgc"].uplink_maneuver(float(pad["tig"]), pad["dv_lvlh"])
		systems["lgc"].uplink_throttle([])
		systems["lgc"].uplink_landing_site(landing_site())
		systems["lgc"].tland = float(pad["land_get"])
	_say("Houston, uplinking " + text)
	_fire("pad_" + kind)
	return pad


## A translunar midcourse correction at [param tig] from [param tr] for
## [param mass] on the SPS: to the pericynthion the mission aims at
## (mission.json "tli": pericynthion_alt_km at pericynthion_get). Without
## a landing, or with nodal targeting (tli "node_targeting"), the site
## sets the orbit's whole plane: the pericynthion goes in it, where LOI-1
## turns the orbit into it.
func _plan_translunar_mcc(tr: Trajectory, mass: float, tig: float) -> Dictionary:
	var t := mission.section("tli")
	var target := -(Bodies.R_MOON + float(t["pericynthion_alt_km"]) * 1000.0)
	var plane_n := Vector3.ZERO
	if not mission.data.has("landing") or bool(t.get("node_targeting", false)):
		plane_n = _site_normal()
	return Rtcc.plan_mcc(tr, mass, tig, "moon", target, tr.t + 5.0 * 86400.0,
		landing_site(), site_get(), _get_s(t["pericynthion_get"]), plane_n)


## A maneuver the flight plan fixes rather than the RTCC solves: timeline
## entry [param e]'s ΔV ("n81_ft_s", LVLH) at its TIG (_fixed_tig()),
## named by its "name". The CSM's are uplinked to the CMC with its tracked
## state as the RTCC's PADs are [published for Apollo 8: the separation
## maneuvers from the S-IVB, radially up, which the crew flew on the THC by
## the EMS; simplified: P41 flies them from the PAD]. The LM's, which name
## its engine ("engine": "dps" or "aps"), are uplinked to the LGC with the
## DPS's throttle schedule ("throttle", Dps.p40_schedule()) [published for
## Apollo 10: the phasing and insertion PADs, which the ground solved for
## the rendezvous]. The PAD's GET goes in the plan, <its kind>_tig.
## Returns the PAD.
func maneuver_pad(e: Dictionary) -> Dictionary:
	var m := _fixed_maneuver(e)
	var kind := str(e["pad"])
	var pad := {"name": str(e.get("name", "MANEUVER")), "tig": _fixed_tig(e), "dv_lvlh": m["dv_lvlh"],
		"dv": (m["dv_lvlh"] as Vector3).length(), "burn_s": m["burn_s"]}
	plan[kind + "_tig"] = pad["tig"]
	if not e.has("engine"):
		return _uplink(kind, pad, tracked_state(dynamics.traj))
	return _uplink_lgc(kind, pad, e.get("throttle", []))


## Uplink [param pad] of [param kind] to the LGC (P30's loads), with the
## DPS's throttle schedule [param schedule] (Dps.p40_schedule()), and with
## the state MSFN tracked [param tracked] when given (P27: the lifeboat's,
## the stack's); the PAD's GET goes in the plan, <kind>_tig. With the LGC
## dark (Apollo 13's MCC-5, on the AGS) CAPCOM reads it up. Returns the
## PAD, with "uplinked".
func _uplink_lgc(kind: String, pad: Dictionary, schedule: Array = [], tracked: Trajectory = null) -> Dictionary:
	last_pad = pad
	pads[kind] = pad
	plan[kind + "_tig"] = pad["tig"]
	var lgc: Lgc = systems.get("lgc")
	pad["uplinked"] = lgc != null and (tracked == null or lgc.uplink_state(tracked)) \
		and lgc.uplink_maneuver(float(pad["tig"]), pad["dv_lvlh"])
	if pad["uplinked"]:
		lgc.uplink_throttle(schedule)
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	if pad["uplinked"]:
		_say("Houston: {lm}, uplinking your " + ("state vector and " if tracked != null else "") + text)
	else:
		_say("Houston: {lm}, by voice: " + text)
	_fire("pad_" + kind)
	return pad


## Timeline entry [param e]'s fixed maneuver: {"dv_lvlh", "burn_s", "t"
## (its middle, GET)}. The LM's on its engine ("engine"), the DPS on the
## entry's throttle schedule; the CSM's on the SPS from SPS_MIN_MPS, or
## on the SM RCS's four +X jets, for the CSM as it is, or as it will be
## after CSM/LV SEP (with the LM when it carries one).
func _fixed_maneuver(e: Dictionary) -> Dictionary:
	var dv := _v3(e["n81_ft_s"]) * Units.FT
	var burn := 0.0
	match str(e.get("engine", "")):
		"dps":
			burn = Rtcc.dps_burn_time(_lm_mass("lm"), dv.length(), e.get("throttle", []))
		"aps":
			var aps := SpacecraftData.section("aps")
			var ve := float(aps["isp_s"]) * Units.G0
			burn = _lm_mass("lm_ascent") * (1.0 - exp(-dv.length() / ve)) * ve / float(aps["thrust_n"])
		_:
			var mass := dynamics.mass
			if not dynamics.config in ["csm_lm", "csm"]:
				mass = SpacecraftData.total_mass("csm_lm" if SpacecraftData.carries_lm() else "csm", _sps_load(),
					_sm_rcs_load(), _cm_rcs_load(), 0.0)
			if dv.length() >= SPS_MIN_MPS:
				burn = Rtcc.burn_time(mass, dv.length())
			else:
				burn = mass * dv.length() / (4.0 * float(SpacecraftData.section("sm_rcs")["jet_thrust_n"]))
	return {"dv_lvlh": dv, "burn_s": burn, "t": _fixed_tig(e) + burn / 2.0}


## A fixed maneuver's TIG: its GET ("tig"), or "tig_s" seconds after a time
## the ground has planned ("tig_after", a key of plan: Apollo 10's phasing
## and insertion come after pdi_tig, the low point DOI aims the LM's orbit
## at); -1 while that time isn't planned.
func _fixed_tig(e: Dictionary) -> float:
	if e.has("tig_after"):
		var t := float(plan.get(str(e["tig_after"]), -1.0))
		return t + float(e["tig_s"]) if t >= 0.0 else -1.0
	return _get_s(e["tig"])


## Timeline entry [param e]'s orbit shaping (its PAD "shape"): the CSM's
## in-plane burn at the entry's TIG onto the orbit ha_nmi by hp_nmi above
## the landing site's radius, the new pericynthion behind the burn point
## with "rising" (Rtcc.plan_loi2()), planned on [param tr] of [param mass]:
## Apollo 15's for the subsatellite, flown 66.4 ft/s at the PAD's TIG into
## the PAD's orbit, whatever the orbit was before it. Named by the entry's
## "name".
func _shape_burn(tr: Trajectory, mass: float, e: Dictionary) -> Dictionary:
	var r_site := landing_site().length()
	var pad := Rtcc.plan_loi2(tr, mass, r_site + float(e["ha_nmi"]) * Units.NMI, r_site + float(e["hp_nmi"]) * Units.NMI,
		_get_s(e["tig"]), bool(e.get("rising", false)))
	if not pad.is_empty():
		pad["name"] = str(e.get("name", "SHAPING"))
	return pad


## The LM's mass in [param cfg] ("lm" or "lm_ascent") with the propellant
## it has now, kg.
func _lm_mass(cfg: String) -> float:
	var f := SpacecraftData.lm_full_loads()
	return SpacecraftData.lm_total_mass(cfg, float(Bus.get_value("lm.dps.prop_kg", f[0])),
		float(Bus.get_value("lm.aps.prop_kg", f[1])), float(Bus.get_value("lm.rcs.prop_kg", f[2])))


## Uplink [param pad] of [param kind] to the CMC with the CSM's
## [param tracked] state (P27), when it takes them, or read it up by
## voice. Returns the PAD, with "state" and "uplinked".
func _uplink(kind: String, pad: Dictionary, tracked: Trajectory) -> Dictionary:
	last_pad = pad
	pads[kind] = pad
	_scs_figures(pad, tracked)
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	var agc: AgcCore = systems.get("agc")
	pad["state"] = tracked
	pad["uplinked"] = agc != null and agc.uplink_state(tracked) and agc.uplink_maneuver(
		float(pad["tig"]), pad["dv_lvlh"])
	if pad["uplinked"]:
		_say("Houston, uplinking your state vector and " + text)
	else:
		_say("Houston: {csm}, we can't uplink, we need P00 and UP TLM to ACCEPT. By voice: " + text)
	_fire("pad_" + kind)
	return pad


## The PAD's figures for a burn flown on the SCS (slice 9c): the burn
## attitude, "att_deg", as the IMU's gimbal angles on the CMC's REFSMMAT
## (R, P, Y), the thrust along the velocity to be gained at ignition as P40
## flies it, heads up; and the EMS's ΔV counter setting, "dvc", the burn's
## ΔV less the ΔV of the SPS's tail-off after the thrust-off [published:
## the Maneuver PAD's R, P, Y and ΔVC lines].
func _scs_figures(pad: Dictionary, tracked: Trajectory) -> void:
	var agc: AgcCore = systems.get("agc")
	if agc == null or not pad.has("dv_lvlh") or not pad.has("tig") or tracked == null:
		return
	var at := tracked.clone()
	at.coast_to(float(pad["tig"]))
	var dv := Trajectory.lvlh_basis(at.pos(), at.vel()) * (pad["dv_lvlh"] as Vector3)
	if dv.length() <= 0.0:
		return
	var sps := SpacecraftData.section("sps")
	var thrust := float(sps["thrust_n"])
	var mass := float(Bus.get_value("dyn.mass_kg", 30000.0))
	var ut := AgcCore.external_dv_vg(at.pos(), at.vel(), dv, mass, thrust)
	pad["att_deg"] = Imu.gimbal_angles(agc.imu.refsmmat * Basis(agc.burn_attitude(ut.normalized(), at.pos())))
	var total := float(pad.get("dv", dv.length()))
	var tail := 0.0
	if total >= SPS_MIN_MPS:
		var m_end := mass * exp(-total / (float(sps["isp_s"]) * Units.G0))
		tail = thrust * float(sps["tau_off_s"]) / m_end
	pad["dvc"] = total - tail


## The CSM's state vector for the CMC (P27, V71): the state MSFN tracked.
## Returns {"name": "SV", "tig": the GET, "state": that Trajectory,
## "uplinked": whether the CMC took it (P00, UP TLM CM in ACCEPT)}.
func sv_uplink() -> Dictionary:
	var agc: AgcCore = systems.get("agc")
	var tracked := tracked_state(dynamics.traj)
	var pad := {"name": "SV", "tig": SimClock.get_seconds, "state": tracked,
		"uplinked": agc != null and agc.uplink_state(tracked)}
	last_pad = pad
	pads["sv"] = pad
	if pad["uplinked"]:
		Bus.set_value("mission.pad_text", "STATE VECTOR uplinked at %s" % Units.hms(SimClock.get_seconds))
		_say("Houston: {csm}, your state vector is in.")
	else:
		_say("Houston: {csm}, we have a state vector for you, P00 and UP TLM to ACCEPT please.")
	_fire("pad_sv")
	return pad


## The LM's state vector for the LGC (P27), while it flies free, or docked
## as the lifeboat (the stack's): the state MSFN tracked (tracked_state(),
## the CSM's tracking error [estimated]). Returns {"name": "LM SV", "tig":
## the GET, "state", "uplinked"}, or {} without a free LM or a lifeboat.
func lm_sv_uplink() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	var lm := dynamics.lm
	var docked := lm == null and _lifeboat()
	if lgc == null or (not docked and (lm == null or lm.landed)):
		last_pad = {}
		_say("Houston: we have no state vector for the LM.")
		return {}
	var tracked := tracked_state(dynamics.traj if docked else lm.traj)
	var pad := {"name": "LM SV", "tig": SimClock.get_seconds, "state": tracked, "uplinked": lgc.uplink_state(tracked)}
	last_pad = pad
	pads["lm_sv"] = pad
	Bus.set_value("mission.pad_text", "LM STATE VECTOR uplinked at %s" % Units.hms(SimClock.get_seconds))
	_say("Houston: {lm}, your state vector is in.")
	_fire("pad_lm_sv")
	return pad


## The entry PAD (Rtcc.plan_entry()) for the target (mission.json "entry"),
## from the state MSFN tracked, uplinked to the CMC with that state and the
## target (P27) when it takes them. Returns the PAD with "state" and
## "uplinked", or empty when the return doesn't come down to entry
## interface.
func entry_pad() -> Dictionary:
	var agc: Agc = systems.get("agc")
	var tracked := tracked_state(dynamics.traj)
	var target := entry_target()
	var pad := Rtcc.plan_entry(tracked, target.x, target.y)
	if pad.is_empty():
		_say("Houston: {csm}, no entry PAD: you're not coming down to entry interface.")
		return {}
	pad["state"] = tracked
	pad["uplinked"] = agc != null and agc.uplink_state(tracked) and agc.uplink_entry_target(target.x, target.y)
	last_pad = pad
	pads["entry"] = pad
	var text := Rtcc.pad_text(pad)
	Bus.set_value("mission.pad_text", text)
	if pad["uplinked"]:
		_say("Houston, uplinking your state vector and target. " + text)
	else:
		_say("Houston: {csm}, we can't uplink, we need P00 and UP TLM to ACCEPT. By voice: " + text)
	_fire("pad_entry")
	return pad


## The computer [param computer] names ("cmc" or "lgc"), or when empty the
## one flying the vehicle: the CMC while the CSM has power, else the LGC.
func _computer_of(computer: String) -> String:
	if computer != "":
		return computer
	return "cmc" if bool(Bus.get_value("sys.powered", true)) else "lgc"


## The ground's coarse align angles for [param computer]'s IMU (see
## _computer_of()): the gimbal angles, for its V41N20, that put its platform
## on the REFSMMAT the ground has picked for it: for an LM flying free or
## landed the lunar one (_lgc_refsmmat()), otherwise the local vertical
## frame now (P52's nominal orientation) [simplified: Apollo 13's entry
## REFSMMAT, and the LGC's for MCC-7], at the vehicle's attitude now, which
## the ground knew from the LM's platform and the AGS [simplified:
## exactly]. CAPCOM reads them up [published: Apollo 13's for the CM's
## power-up, 139:51:40]; the REFSMMAT itself comes up with the refsmmat
## PAD. Returns {"name": "COARSE ALIGN", "tig", "computer", "refsmmat",
## "angles" (deg)}.
func _coarse_pad(computer: String) -> Dictionary:
	var c := _computer_of(computer)
	var tr := tracked_state(dynamics.traj)
	var m := Imu.nominal(tr.pos(), tr.vel())
	if c == "lgc" and dynamics.lm != null:
		m = _lgc_refsmmat()
	var q := dynamics.attitude.q
	if c == "lgc":
		q = dynamics.lm.attitude.q if dynamics.lm != null else (q * Docking.LM_IN_CSM).normalized()
	var g := Imu.gimbal_angles(m * Basis(q))
	var pad := {"name": "COARSE ALIGN", "tig": SimClock.get_seconds, "computer": c, "refsmmat": m, "angles": g}
	last_pad = pad
	pads["coarse"] = pad
	var text := "COARSE ALIGN %s: V41 N20 %+07.2f %+07.2f %+07.2f" % [c.to_upper(), g.x, g.y, g.z]
	Bus.set_value("mission.pad_text", text)
	_say("Houston: " + ("{csm}" if c == "cmc" else "{lm}") + ", your " + text)
	_fire("pad_coarse")
	return pad


## The ground's REFSMMAT for [param computer]'s IMU (see _computer_of()),
## uplinked (P27) with the REFSMMAT flag set (AgcCore.uplink_refsmmat()):
## the one its coarse align went to (the coarse PAD's), for an LM flying
## free or landed the lunar one (_lgc_refsmmat()), or [param docked]
## the docked alignment's: the CMC's REFSMMAT, to which the crew coarse
## aligned the LGC's platform from the CMC's (Docking.lm_gimbals()), and
## the fine align's torquing, which the ground worked out from both
## vehicles' gimbal angles, taking the platform onto that REFSMMAT but for
## a misalignment (mission.json "lifeboat": docked_misalignment_deg, the
## angles that take the platform back onto REFSMMAT, so that it stands
## turned by their negative) [published: Apollo 13's, which the GNC
## supplement found at PC+2 from its burn's error, taken whole at the
## docked alignment; simplified: its fine align torquing read up at 058:44
## and its REFSMMAT uplinked at 059:28 come up together]. Returns
## {"name": "REFSMMAT", "tig", "computer", "uplinked"}.
func _refsmmat_pad(computer: String, docked: bool) -> Dictionary:
	var c := _computer_of(computer)
	var core: AgcCore = systems.get("agc" if c == "cmc" else "lgc")
	var m := Imu.nominal(dynamics.traj.pos(), dynamics.traj.vel())
	if c == "lgc" and dynamics.lm != null:
		m = _lgc_refsmmat()
	if docked and systems.has("agc"):
		m = systems["agc"].imu.refsmmat
	elif pads.has("coarse") and str(pads["coarse"]["computer"]) == c:
		m = pads["coarse"]["refsmmat"]
	var ok := core != null and core.uplink_refsmmat(m)
	if ok and docked:
		# The supplement's angles take the platform back onto the REFSMMAT:
		# it found them from the burn's residual, the velocity still to be
		# gained, so the platform stood turned the other way.
		var e: Array = mission.section("lifeboat").get("docked_misalignment_deg", [0.0, 0.0, 0.0])
		core.imu.misalign(m, -Vector3(deg_to_rad(e[0]), deg_to_rad(e[1]), deg_to_rad(e[2])))
		core.reference_changed()
	var pad := {"name": "REFSMMAT", "tig": SimClock.get_seconds, "computer": c, "uplinked": ok}
	last_pad = pad
	pads["refsmmat"] = pad
	Bus.set_value("mission.pad_text", "REFSMMAT %s at %s" % [c.to_upper(), Units.hms(SimClock.get_seconds)])
	var who := "{csm}" if c == "cmc" else "{lm}"
	if ok:
		_say("Houston: %s, your REFSMMAT is in; set your REFSMMAT flag." % who)
	else:
		_say("Houston: %s, we have a REFSMMAT for you, P00 and UP TLM to ACCEPT please." % who)
	_fire("pad_refsmmat")
	return pad


## Where the CSM is over the Earth: latitude and east longitude, deg.
func geographic() -> Vector2:
	var tr := dynamics.traj
	var p := Bodies.eci_to_earth_fixed([tr.s[0], tr.s[1], tr.s[2]], tr.t)
	return Bodies.fixed_to_geographic(Vector3(p[0], p[1], p[2]))


## The entry's target: latitude and east longitude, deg (mission.json
## "entry").
func entry_target() -> Vector2:
	var e := mission.section("entry")
	return Vector2(float(e["target_lat_deg"]), float(e["target_lon_deg"]))


## The state MSFN tracked for [param tr]: its truth, off by a tracking
## error drawn for this request (mission.json "msfn": standard deviations in
## LVLH, by the body [param tr]'s orbit is about).
func tracked_state(tr: Trajectory) -> Trajectory:
	var out := tr.clone()
	var e: Dictionary = mission.section("msfn").get(tr.primary, {})
	var sp: Array = e.get("pos_m", [0.0, 0.0, 0.0])
	var sv: Array = e.get("vel_mps", [0.0, 0.0, 0.0])
	var lv := Trajectory.lvlh_basis(out.pos(), out.vel())
	var dp := lv * Vector3(_rng.randfn(0.0, sp[0]), _rng.randfn(0.0, sp[1]), _rng.randfn(0.0, sp[2]))
	var dv := lv * Vector3(_rng.randfn(0.0, sv[0]), _rng.randfn(0.0, sv[1]), _rng.randfn(0.0, sv[2]))
	for i in 3:
		out.s[i] += dp[i]
		out.s[3 + i] += dv[i]
	return out


## Seed the flight's dispersions (mission.json "dispersions"): the CSM's
## unmodelled forces, MSFN's tracking errors to come, the IMUs' drift and
## the rendezvous radar's errors.
func _disperse() -> void:
	dispersion_seed = int(mission.section("dispersions").get("seed", 0))
	dynamics.disperse(dispersion_seed)
	_rng.seed = dispersion_seed + 1
	var imu := SpacecraftData.section("imu")
	if systems.has("agc"):
		systems["agc"].imu.disperse(dispersion_seed + 2, float(imu["drift_deg_per_h"]), float(imu["coarse_align_deg"]))
	if systems.has("lgc"):
		# The LGC's (slice 11a): its gyros drift as the flight's measured
		# where the mission has them (mission.json "lgc": drift_meru).
		var lm_imu := SpacecraftData.section("lm_imu")
		var lgc: Lgc = systems["lgc"]
		lgc.imu.disperse(dispersion_seed + 3, float(lm_imu["drift_deg_per_h"]), float(lm_imu["coarse_align_deg"]))
		var d: Array = mission.section("lgc").get("drift_meru", [])
		if not d.is_empty():
			lgc.imu.drift = Vector3(d[0], d[1], d[2]) * MERU_RAD_S
	if systems.has("rr"):
		# The rendezvous radar's biases and noise (slice 11d).
		systems["rr"].disperse(dispersion_seed + 4)


## The REFSMMAT a start phase's IMU is aligned to: the launch pad's until
## the lunar orbit (mission.json "launch_refsmmat"), the landing site's
## (or the lunar site's) there and while the LM flies, and on the way home
## the local vertical at the start (P52's nominal orientation); Apollo 13's
## at its tank's failure, the one its crew had aligned to for the coast
## (mission.json "tank_failure": refsmmat).
func start_refsmmat(p_phase: String) -> Basis:
	var tr := dynamics.traj
	if p_phase == "tank_failure":
		var r := mission.section("tank_failure")["refsmmat"] as Dictionary
		return Imu.from_axes(_v3(r["x"]), _v3(r["y"]), _v3(r["z"]))
	if p_phase in ["lunar_orbit", "tei"] + LM_PHASES:
		return landing_site_refsmmat(tr)
	if p_phase in ["transearth_coast", "entry"]:
		return Imu.nominal(tr.pos(), tr.vel())
	var m := mission.section("launch_refsmmat")
	return Imu.from_axes(_v3(m["x"]), _v3(m["y"]), _v3(m["z"]))


## The landing site REFSMMAT for the CSM's lunar orbit [param tr]: X up
## through the site at the landing time, Z downrange (P52 option 4).
## Without a landing, the lunar site's at its time [simplified: Apollo 8's
## lunar orbit REFSMMAT was LOI-2's burn attitude].
func landing_site_refsmmat(tr: Trajectory) -> Basis:
	return Imu.landing_site(Rtcc.site_at(landing_site(), site_get()), tr.pos().cross(tr.vel()))


## The LGC's REFSMMAT in lunar orbit (slice 11a): the landing site's (P52
## option 4), X up through the site at the landing time, Z downrange in the
## CSM's orbit; on the surface, once the ascent PAD has the liftoff, the
## spot the LM landed on at the liftoff's time (P57 option 4's, Apollo 11's
## last before its liftoff) [published: Apollo 11 Mission Report, MSC-00171,
## Table 9.6-I].
func _lgc_refsmmat() -> Basis:
	var h := dynamics.traj.pos().cross(dynamics.traj.vel())
	var lm := dynamics.lm
	if lm != null and lm.landed and plan.has("liftoff_tig"):
		return Imu.landing_site(Bodies.moon_fixed(float(plan["liftoff_tig"])) * lm.landed_pos, h)
	return landing_site_refsmmat(dynamics.traj)


## Undocked: the LGC's platform as its crew aligned it docked, at the
## landing site REFSMMAT, off by what the flight's first P52 after
## undocking found (its torquing angles, N93, at its time), less the drift
## between (mission.json "lgc": first_p52) [published: the mission
## reports' LM alignment tables]; exactly there without it. An undocking
## before the flight's (timeline "undocking_get") finds the platform as
## the flight's undocking did: the crew aligned it docked shortly before.
func _lgc_undocked() -> void:
	var lgc: Lgc = systems.get("lgc")
	if lgc == null:
		return
	var eps := Vector3.ZERO
	var f: Dictionary = mission.section("lgc").get("first_p52", {})
	if not f.is_empty():
		# N93 is the turn that takes the platform back onto REFSMMAT: at
		# the P52 the platform stood turned by it (misalign()'s sense), and
		# at undocking by that less the drift between.
		var a: Array = f["torque_deg"]
		var n93 := Vector3(deg_to_rad(a[0]), deg_to_rad(a[1]), deg_to_rad(a[2]))
		var t := SimClock.get_seconds
		var tl := mission.section("timeline")
		if tl.has("undocking_get"):
			t = maxf(t, _get_s(tl["undocking_get"]))
		eps = n93 + lgc.imu.drift * (_get_s(f["get"]) - t)
	lgc.imu.misalign(_lgc_refsmmat(), eps)
	lgc.reference_changed()


## The LGC's gyros on the surface drift as the flight's measured them there
## ([param landed]: mission.json "lgc": surface_drift_meru), and in flight
## as they did in flight ("drift_meru"): on the Moon their g-sensitive
## drift has a sixth of a g to act on [published: the mission reports' LM
## alignment tables]. Without the mission's rates the drawn one stays.
func _lgc_drift(landed: bool) -> void:
	var lgc: Lgc = systems.get("lgc")
	if lgc == null:
		return
	var d: Array = mission.section("lgc").get("surface_drift_meru" if landed else "drift_meru", [])
	if not d.is_empty():
		lgc.imu.drift = Vector3(d[0], d[1], d[2]) * MERU_RAD_S


## The crew's last alignment of the LGC's platform, exactly, to its REFSMMAT
## (_lgc_refsmmat()), at an LM start phase: the P52 or P57 before it. In a
## flight the crew align it themselves (P52, and on the surface P57).
func _lgc_align() -> void:
	var lgc: Lgc = systems.get("lgc")
	if lgc == null or lgc.imu.failed:
		return
	lgc.imu.align(_lgc_refsmmat())
	lgc.reference_changed()


## The PDI PAD, after DOI: the ground predicts PDI with the LGC's own
## ignition algorithm and uplinks the LM's state vector (P27) as MSFN
## tracked it. The tracking error is given where it matters, at PDI
## (mission.json "pdi", LVLH): the uplinked state is on the orbit that is
## off by that much there, coasted back to now through the LGC's own model
## of the Moon's field, so that the LGC, coasting it forward, comes to PDI
## off by just that. Returns {"name": "PDI", "tig"}, or {} without a free
## LM that has its landing site.
func pdi_pad() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	if _docked_doi() and lgc != null and lgc.landing_site == Vector3.ZERO and plan.has("land_get"):
		# DOI was the CSM's (Apollo 14's): the landing site and its time
		# come with this PAD.
		lgc.uplink_landing_site(_lgc_site())
		lgc.tland = float(plan["land_get"])
	if dynamics.lm == null or dynamics.lm.config != "lm" or lgc == null or lgc.landing_site == Vector3.ZERO:
		_say("Houston: no PDI solution.")
		last_pad = {}
		return {}
	var now := dynamics.lm.traj.clone()
	var from := now
	var period := float(now.conic()["period"])
	if float(plan.get("pdi_tig", -1.0)) - now.t > 0.5 * period:
		# The pass the plan has PDI on, a revolution or more ahead: Apollo
		# 14's PAD came two hours before it.
		from = now.clone()
		from.coast_to(float(plan["pdi_tig"]) - 0.25 * period, 60.0)
	var tig := Lgc.pdi_time(from, lgc.landing_site, float(SpacecraftData.section("descent_guidance")["pdi_range_m"]))
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
	at.as_onboard(lgc.nav_model())
	while at.t > now.t + 1e-9:
		at.step(-minf(clampf(0.005 * at.radius() / maxf(at.speed(), 1.0), 0.02, 60.0), at.t - now.t))
	lgc.uplink_state(at)
	# The CSM's too, off by MSFN's tracking error, for the aborts (P70 and
	# P71) to fly into its plane and phase the LM for the rendezvous; and
	# the aborts' TPI times (slice 9e).
	var csm := dynamics.traj.clone()
	var cv := Trajectory.lvlh_basis(csm.pos(), csm.vel())
	var r := mission.section("rendezvous")
	var cdp: Vector3 = cv * _v3(r.get("csm_state_error_lvlh_m", [0.0, 0.0, 0.0]))
	var cdv: Vector3 = cv * _v3(r.get("csm_state_error_lvlh_mps", [0.0, 0.0, 0.0]))
	for i in 3:
		csm.s[i] += cdp[i]
		csm.s[3 + i] += cdv[i]
	lgc.uplink_csm_state(csm)
	var pad := {"name": "PDI", "tig": tig}
	var aborts := ""
	if e.has("abort_tpi_early_s"):
		pad["abort_tpi_early"] = tig + float(e["abort_tpi_early_s"])
		pad["abort_tpi_late"] = tig + float(e["abort_tpi_late_s"])
		pad["abort_split"] = tig + float(e["abort_late_after_s"])
		for k in ["abort_tpi_early", "abort_tpi_late", "abort_split"]:
			plan[k] = pad[k]
		lgc.uplink_abort_tpi(pad["abort_tpi_early"], pad["abort_tpi_late"], pad["abort_split"])
		aborts = "  PDI ABORT <%.0f MIN TPI %s  >%.0f MIN TPI %s" % [float(e["abort_late_after_s"]) / 60.0,
			Units.hms(pad["abort_tpi_early"]), float(e["abort_late_after_s"]) / 60.0, Units.hms(pad["abort_tpi_late"])]
	last_pad = pad
	pads["pdi"] = pad
	plan["pdi_tig"] = tig
	plan["pdi_pad_tig"] = tig
	var text := "PDI PAD: TIG %s, state vectors uplinked%s" % [Units.hms(tig), aborts]
	Bus.set_value("mission.pad_text", text)
	_say("Houston: {lm}, we've uplinked your state vector. " + text)
	_fire("pad_pdi")
	return pad


## The landing site correction in powered descent, N69: MSFN's powered
## flight processor finds, from its tracking, how far along the ground
## track the LGC has the LM from where it is, and CAPCOM reads the site's
## move that makes up for it, to the nearest 100 ft, for the crew to load
## (V21N69, R1) [published: Apollo 12's, 4,200 ft downrange, 1.5 min
## after ignition, MSC-01855, section 4.2]. The processor's error along
## the track is drawn for the request (mission.json "pdi": n69_sigma_m)
## [estimated]; the crossrange part isn't read [simplified: as on Apollo
## 12, where it wasn't needed]. Returns {"name": "N69", "tig": the GET,
## "dz_ft"}, or {} unless the LGC flies P63 or P64.
func _n69_pad() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	var lm := dynamics.lm
	if lm == null or lm.landed or lgc == null or lgc.nav == null or not lgc.program in [63, 64]:
		_say("Houston: no landing site update.")
		last_pad = {}
		return {}
	# Along the LM's own track: the landing radar takes out the height the
	# LGC has wrong along the local vertical, and what it has wrong along
	# the track is left to land long or short by.
	var t := lm.traj
	var along := Trajectory.lvlh_basis(t.pos(), t.vel()).x
	var sigma := float(mission.section("pdi").get("n69_sigma_m", 0.0))
	var dz := (lgc.nav.pos() - t.pos()).dot(along) + _rng.randfn(0.0, sigma)
	var ft := roundf(dz / Units.FT / 100.0) * 100.0
	var pad := {"name": "N69", "tig": SimClock.get_seconds, "dz_ft": ft}
	last_pad = pad
	pads["n69"] = pad
	var reg := "%s%05d" % ["plus " if ft >= 0.0 else "minus ", int(absf(ft))]
	Bus.set_value("mission.pad_text", "NOUN 69: R1 %s%05d (downrange, ft)" % ["+" if ft >= 0.0 else "-", int(absf(ft))])
	_say("{lm}, Houston. Noun 69 " + reg + ". Over.")
	_fire("pad_n69")
	return pad


## The ascent PAD, with the LM on the surface: the RTCC times the liftoff
## for the CSM to lead the LM by the insertion phase angle (mission.json
## "ascent") at insertion, flying P12's own guidance, in the first window
## ten minutes out or later, and no earlier than GET [param earliest]. For
## a direct rendezvous (mission.json "rendezvous": direct, slice 12a) it
## times it for TPI a set time after the insertion instead
## (Rtcc.plan_liftoff_direct()), and TPI's time goes up with it (N37). The
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
		var r := mission.section("rendezvous")
		if bool(r.get("direct", false)):
			pad = Rtcc.plan_liftoff_direct(site, mass, dynamics.traj.clone(), float(r["tpi_after_insertion_s"]),
				deg_to_rad(float(SpacecraftData.section("rendezvous_guidance")["tpi_elevation_deg"])),
				maxf(SimClock.get_seconds + 600.0, earliest))
		else:
			var phase_deg := float(mission.section("ascent")["insertion_phase_deg"])
			pad = Rtcc.plan_liftoff(site, mass, dynamics.traj.clone(), phase_deg,
				maxf(SimClock.get_seconds + 600.0, earliest))
		if not pad.is_empty():
			lgc.uplink_state(lm.traj)
			lgc.uplink_landing_site(site)
			lgc.uplink_csm_state(dynamics.traj)
			lgc.uplink_liftoff(float(pad["tig"]))
			if pad.has("tpi_get"):
				lgc.uplink_rendezvous(-1.0, float(pad["tpi_get"]))
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
	if pad.has("tpi_get"):
		plan["tpi_tig"] = pad["tpi_get"]
		text += "  N37 TPI %s" % Units.hms(float(pad["tpi_get"]))
	Bus.set_value("mission.pad_text", text)
	_say("Houston: {lm}, your ascent PAD. " + text)
	_fire("pad_ascent")
	return pad


## The CSI PAD, with the LM in orbit after insertion: the RTCC's plan for
## the coelliptic sequence (Rtcc.plan_rendezvous()), with TPI as long after
## insertion as Apollo 11 had it (mission.json "rendezvous"), or after an
## abort from the descent when the PDI PAD gave it (slice 9e). The ground
## uplinks CSI's and TPI's TIGs, and the CSM's state vector as MSFN tracked
## it, off by its tracking error; after an abort, the LM's too. Returns the
## PAD, or {} without an LM in orbit.
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
		var t_tpi := ins + float(r["tpi_after_insertion_s"])
		if _has("lm_abort") and float(plan.get("abort_tpi", -1.0)) > ins:
			t_tpi = float(plan["abort_tpi"])
		pad = Rtcc.plan_rendezvous(lm.traj, dynamics.traj, lm.mass, t_tpi,
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
	if _has("lm_abort"):
		# After an abort MSFN has tracked the LM from the descent into its
		# orbit: its state vector goes up too, off by the same tracking
		# error [estimated: the LGC's own, integrated through the abort,
		# drifts kilometres from it on the abort's long, eccentric orbit].
		var l := lm.traj.clone()
		var ll := Trajectory.lvlh_basis(l.pos(), l.vel())
		var ldp: Vector3 = ll * _v3(r["csm_state_error_lvlh_m"])
		var ldv: Vector3 = ll * _v3(r["csm_state_error_lvlh_mps"])
		for i in 3:
			l.s[i] += ldp[i]
			l.s[3 + i] += ldv[i]
		lgc.uplink_state(l)
	var text := "CSI PAD: TIG %s  N81 DVX %+.1f ft/s  BURN %.0f s  CDH %s %.1f ft/s  TPI %s %.1f ft/s  BRAKING %.1f ft/s" % [
		Units.hms(float(pad["tig"])), float(pad["dv"]) / Units.FT, float(pad["burn_s"]), Units.hms(float(pad["cdh_get"])),
		float(pad["cdh_dv"]) / Units.FT, Units.hms(float(pad["tpi_get"])), float(pad["tpi_dv"]) / Units.FT,
		float(pad["braking_dv"]) / Units.FT]
	Bus.set_value("mission.pad_text", text)
	_say("Houston: {lm}, your CSI PAD. " + text)
	_fire("pad_csi")
	return pad


## The vernier adjustment after a direct rendezvous's insertion (the
## tweak, slice 12a): the RTCC's in-plane correction a few minutes after
## the insertion (mission.json "rendezvous": tweak_after_insertion_s) that
## brings TPI's nominal geometry at its time, the CSM the TPI elevation
## above the LM and tweak_dh_nmi above it (Rtcc.plan_tweak()). The ground
## uplinks it to the LGC for P41 with the CSM's state vector, off by MSFN's
## tracking error [simplified: Apollo 14's crew burned the LGC's own
## solution by hand in P47]. Returns the PAD, or {} without the LM in orbit
## after its insertion.
func _tweak_pad() -> Dictionary:
	var lgc: Lgc = systems.get("lgc")
	var lm := dynamics.lm
	var r := mission.section("rendezvous")
	var ins := event_get("lm_insertion")
	var pad := {}
	if lm != null and not lm.landed and lgc != null and ins >= 0.0 and r.has("tweak_after_insertion_s"):
		var t_tpi := float(plan.get("tpi_tig", ins + float(r["tpi_after_insertion_s"])))
		pad = Rtcc.plan_tweak(lm.traj, dynamics.traj, lm.mass,
			maxf(ins + float(r["tweak_after_insertion_s"]), SimClock.get_seconds + 60.0), t_tpi,
			deg_to_rad(float(SpacecraftData.section("rendezvous_guidance")["tpi_elevation_deg"])),
			float(r["tweak_dh_nmi"]) * Units.NMI)
	if pad.is_empty():
		_say("Houston: no tweak solution.")
		last_pad = {}
		return {}
	var csm := dynamics.traj.clone()
	var lv := Trajectory.lvlh_basis(csm.pos(), csm.vel())
	var dp: Vector3 = lv * _v3(r["csm_state_error_lvlh_m"])
	var dv: Vector3 = lv * _v3(r["csm_state_error_lvlh_mps"])
	for i in 3:
		csm.s[i] += dp[i]
		csm.s[3 + i] += dv[i]
	lgc.uplink_csm_state(csm)
	return _uplink_lgc("tweak", pad)


# --- the timeline -------------------------------------------------------------------

func _timeline_entries() -> Array:
	return mission.section("timeline").get("entries", [])


func _timeline_entry(id: String) -> Dictionary:
	for e in _timeline_entries():
		if str(e["id"]) == id:
			return e
	return {}


## An entry's GET: its own, or its offset from a mission event or a planned
## time (a key of plan, which "after" may name too); -1 while that event
## hasn't happened or that time isn't planned.
func _entry_time(e: Dictionary) -> float:
	if e.has("get"):
		return _get_s(e["get"])
	if e.has("after"):
		var k := str(e["after"])
		var t := float(plan[k]) if plan.has(k) else event_get(k)
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
		if e.has("fail") and failures != null:
			# A failure that comes and goes: Apollo 14's ABORT switch.
			failures.recur(str(e["fail"]))
		if e.has("n81_ft_s"):
			maneuver_pad(e)
		elif e.has("pad"):
			# With "near", the opportunity nearest that GET: the first after
			# half the CSM's orbit before it, or a quarter for a plane
			# change, which has one at each node; with "tig", a midcourse
			# correction's TIG.
			var earliest := -1.0
			if e.has("near"):
				var span := 0.25 if str(e["pad"]) == "plane" else 0.5
				earliest = _get_s(e["near"]) - span * float(dynamics.traj.conic()["period"])
			elif e.has("tig"):
				earliest = _get_s(e["tig"])
			request_pad(str(e["pad"]), earliest, e)
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


## A timeline entry's condition ("when"): a flight phase's name (the
## phase then), or one of those below.
func _condition(when: String) -> bool:
	if when in PHASES:
		return phase == when
	var lm := dynamics.lm
	var tr := dynamics.traj
	var in_orbit := tr.primary == "moon" and float(tr.conic()["energy"]) < 0.0
	var before_landing := lm != null and lm.config != "lm_sivb" and not lm.landed and not _has("lm_landing")
	var ok := true
	match when:
		"separated":
			# The CSM off the S-IVB, on its way out.
			ok = phase == "translunar_coast" and dynamics.config in ["csm_lm", "csm"]
		"docked":
			# The whole LM docked, in lunar orbit.
			ok = in_orbit and dynamics.config == "csm_lm" and dynamics.lm_config == "lm"
		"lm_free":
			# The LM flying free, before it has landed.
			ok = before_landing
		"lm_descent":
			# ...and within DESCENT_LEAD_S of the landing time.
			ok = before_landing and SimClock.get_seconds > site_get() - DESCENT_LEAD_S
		"lm_landed":
			ok = lm != null and lm.landed
		"lm_orbit":
			# The ascent stage in orbit.
			ok = lm != null and not lm.landed and _has("lm_insertion")
		"docked_ascent":
			ok = in_orbit and dynamics.config == "csm_lm" and dynamics.lm_config == "lm_ascent"
		"csm_orbit":
			# The CSM alone in lunar orbit, the LM jettisoned or never carried.
			ok = in_orbit and dynamics.config == "csm" and lm == null
		"earth_return":
			# The CSM on the way home, past the Moon's sphere of influence.
			ok = tr.primary == "earth" and dynamics.config == "csm" and visited_lunar_orbit
		"lifeboat":
			ok = _lifeboat()
		"tde":
			# The crew flying transposition and docking, the LM still in the
			# S-IVB's adapter.
			ok = dynamics.tde_in_progress()
	return ok


## The LM flies the docked stack, the CSM's power off and the LM's on:
## Apollo 13's lifeboat, from the CSM's power-down to its power-up for the
## entry.
func _lifeboat() -> bool:
	return SpacecraftData.lm_docked(dynamics.config) and bool(Bus.get_value("lm.sys.powered", false)) \
		and not bool(Bus.get_value("sys.powered", true))


# --- the LM's start phases ---------------------------------------------------------

## The LM's start phases, flown on from the lunar orbit start, docked until
## Apollo 11's undocking, through the RTCC's own solutions and the
## timeline's PADs. Eagle undocks and flies the DOI PAD for the landing pass
## [simplified: the RTCC's model of P40's burn], and lunar_descent starts
## 20 minutes before PDI. Eagle lands at the site at the time DOI planned
## for, and lunar_surface starts 10 minutes after. The CSM flies the plane
## changes the timeline brings before the ascent PAD (_advance_flying()),
## the ascent PAD comes at its time, and lunar_ascent starts 20 minutes
## before the liftoff it gives.
func _lm_start(p_phase: String) -> void:
	var lgc: Lgc = systems["lgc"]
	# [simplified] Columbia drifts in CMC MODE FREE while Eagle flies.
	Bus.set_value("ctl.cmc.mode", 0)
	dynamics.undock()
	_lgc_undocked()
	_fire("undocking")
	if _docked_doi():
		_lm_start_on_descent_orbit(p_phase)
		return
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
		_lgc_align()
		# The PDI PAD's state vector, if it came on the way (Apollo 12's
		# half an hour out), as the LGC would have it now.
		if pads.has("pdi"):
			pdi_pad()
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
		_lgc_align()
		return
	_advance_flying(_entry_time(_timeline_entry("ascent_pad")))
	_advance(float(plan["liftoff_tig"]) - 1200.0)
	_lgc_align()


## The LM's start phases when the CSM flew DOI docked (slice 12a: Apollo
## 14's): the LM undocks on the descent orbit, the CSM circularizes on the
## way (_advance_flying()), lunar_descent starts 20 minutes before PDI, and
## the LM lands at the time the lunar orbit start planned, as
## _lm_start()'s do.
func _lm_start_on_descent_orbit(p_phase: String) -> void:
	var lgc: Lgc = systems["lgc"]
	var lm := dynamics.lm
	if p_phase == "lunar_descent":
		_advance_flying(float(plan["pdi_tig"]) - 1200.0)
		# Apollo 14's crew tapped each of their ABORT switch's shorts clear
		# as Houston called it: the start takes the switch up clear.
		lgc.abort_short = false
		lgc.nav = lm.traj.clone()
		_lgc_align()
		if pads.has("pdi"):
			pdi_pad()
		return
	var t_land := float(plan["land_get"])
	_advance_flying(t_land)
	lgc.abort_short = false
	_set_lm_landed(t_land)
	var dps: Dps = systems["dps"]
	var left := float(mission.section("landing")["dps_prop_left_kg"])
	lm.mass -= dps.prop_kg - left
	dps.restore({"prop_kg": left, "level": 0.0, "ignitions": 1,
		"burn_time": float(SpacecraftData.section("descent_guidance")["descent_s"])})
	_fire("lm_landing")
	lgc.nav = lm.traj.clone()
	lgc.nav_landed_mf = Vector3.ZERO
	if p_phase == "lunar_surface":
		_advance(t_land + 600.0)
		_lgc_align()
		return
	_advance_flying(_entry_time(_timeline_entry("ascent_pad")))
	_advance(float(plan["liftoff_tig"]) - 1200.0)
	_lgc_align()


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


## _advance() to GET [param t], the CSM flying on the way each plane change
## and circularization the timeline's PADs bring (request_pad(): "plane",
## "circ") at its TIG, as the RTCC planned it [simplified: the RTCC's model
## of P40's burn]: Apollo 12's first plane change, which put Yankee
## Clipper's orbit back over Intrepid for the liftoff; Apollo 14's
## circularization after the undocking (slice 12a).
func _advance_flying(t: float) -> void:
	for e in _timeline_entries():
		var te := _entry_time(e)
		var kind := str(e.get("pad", ""))
		if not kind in ["plane", "circ"] or te < SimClock.get_seconds or te >= t:
			continue
		_advance(te)
		var pad: Dictionary = pads.get(kind, {})
		if pad.is_empty() or float(pad["tig"]) < SimClock.get_seconds or float(pad["tig"]) >= t:
			continue
		_advance(float(pad["tig"]))
		var m0 := dynamics.mass
		var m1 := Rtcc.simulate_sps_burn(dynamics.traj, m0, pad["dv_lvlh"])
		var sps_prop := float(Bus.get_value("sps.prop_kg", _sps_load())) - (m0 - m1)
		Bus.set_value("sps.prop_kg", sps_prop)
		systems["sps"].prop_kg = sps_prop
		dynamics.update_mass()
		_advance(dynamics.traj.t)
	_advance(t)


## Set the LM down where the flight's came down (_touchdown_site()) at GET
## [param t], upright, facing along the CSM's track, or turned left of it
## as the flight's came to rest (mission.json "landing": yaw_deg).
func _set_lm_landed(t: float) -> void:
	var lm := dynamics.lm
	var cm := Dynamics.lm_cm_height(lm.config)
	var site := _touchdown_site()
	var up := Rtcc.site_at(site, t).normalized()
	var pos := up * (site.length() + cm)
	lm.traj.set_state("moon", t, pos, Bodies.moon_omega(t).cross(pos))
	var tr := dynamics.traj
	var yaw := deg_to_rad(float(mission.section("landing").get("yaw_deg", 0.0)))
	var fwd := tr.pos().cross(tr.vel()).normalized().cross(up).normalized().rotated(up, yaw)
	lm.attitude.q = Basis(up, fwd.cross(up), fwd).get_rotation_quaternion()
	lm.attitude.omega = Vector3.ZERO
	lm.land(site.length() + cm)
	dynamics.publish_state()
	_lgc_drift(true)


# --- helpers ---------------------------------------------------------------------

## Columbia and Eagle in Apollo 11's orbit after LOI-2 (mission.json
## "lunar_orbit"): its apsides above the landing site's radius, its
## pericynthion over the longitude the mission report gives, retrograde in
## the plane LOI puts it in (over the landing site at the landing time,
## heading the mission's approach azimuth there: _site_normal()), and
## placed along it so that the flown timeline (undocking, DOI and PDI)
## lands at the landing time: Eagle lands a descent after PDI, at its
## descent orbit's pericynthion, pdi_range short of the site, and reaches
## it ahead of Columbia by the difference of their half periods, so
## Columbia passes over the site that much sooner. The Moon's field moves Columbia along
## its orbit by degrees in the day it coasts to there, so its place is
## found by flying it, once in a process.
func _lunar_orbit_start() -> Trajectory:
	var lo := mission.section("lunar_orbit")
	if not SpacecraftData.carries_lm():
		return _csm_orbit_start(lo)
	var t0 := _get_s(lo["start_get"])
	var site := landing_site()
	var r_site := site.length()
	var rp := r_site + float(lo["perilune_nmi"]) * Units.NMI
	var ra := r_site + float(lo["apolune_nmi"]) * Units.NMI
	var a := (rp + ra) / 2.0
	var e := (ra - rp) / (ra + rp)
	var mu := Bodies.MU_MOON
	var n := sqrt(mu / (a * a * a))
	var t_land := float(mission.section("landing")["get_s"])
	var g := SpacecraftData.section("descent_guidance")
	var peri_lm := r_site + float(mission.section("doi")["pericynthion_alt_km"]) * 1000.0
	var a_lm := (a + peri_lm) / 2.0
	var lead := PI / n - PI * sqrt(a_lm * a_lm * a_lm / mu)
	if _docked_doi():
		# The stack is on the descent orbit already, the LM stays on it.
		lead = 0.0
	var t_over := t_land - float(g["descent_s"]) + float(g["pdi_range_m"]) / Bodies.R_MOON / n + lead
	var h := _site_normal()
	var over := Rtcc.site_at(site, t_over).normalized()
	over = (over - h * over.dot(h)).normalized()
	# The pericynthion over its longitude on the equator, in the plane.
	var lon := deg_to_rad(float(lo["perilune_lon_deg"]))
	var pdir := Bodies.moon_fixed(t0) * Vector3(cos(lon), sin(lon), 0.0)
	pdir = (pdir - h * pdir.dot(h)).normalized()
	var key := "%s %.3f %d %s" % [mission.id(), t0, MoonGravity.degree, Bodies.ephemeris != null]
	var m0: float
	if _start_phase_cache.has(key):
		m0 = _start_phase_cache[key]
	else:
		# A conic's guess, then flown to the pass and moved by what it
		# missed by.
		m0 = Rtcc.mean_anomaly(pdir.signed_angle_to(over, h), e) - n * (t_over - t0)
		for _i in 5:
			var fly := Trajectory.new()
			fly.set_state_d("moon", t0, Rtcc.conic_state(mu, a, e, pdir, h, m0))
			fly.coast_to(t_over, 60.0, Rtcc.FRAC)
			var off := over.signed_angle_to(fly.pos().normalized(), h)
			m0 -= off
			if absf(off) < 1e-6:
				break
		_start_phase_cache[key] = m0
	var tr := Trajectory.new()
	tr.set_state_d("moon", t0, Rtcc.conic_state(mu, a, e, pdir, h, m0))
	return tr


## Without an LM, the CSM's orbit after LOI-2 [param lo] (mission.json
## "lunar_orbit"): its apsides above the lunar site's radius, in the plane
## over the site at its time (_site_normal()), from where it was at its start
## (start_lat_deg, start_lon_deg), put in the plane, its pericynthion
## there [simplified].
func _csm_orbit_start(lo: Dictionary) -> Trajectory:
	var t0 := _get_s(lo["start_get"])
	var r_site := landing_site().length()
	var rp := r_site + float(lo["perilune_nmi"]) * Units.NMI
	var ra := r_site + float(lo["apolune_nmi"]) * Units.NMI
	var h := _site_normal()
	var at := Bodies.selenographic_to_fixed(float(lo["start_lat_deg"]), float(lo["start_lon_deg"]), Bodies.R_MOON)
	var p := Rtcc.site_at(at, t0).normalized()
	p = (p - h * p.dot(h)).normalized()
	var tr := Trajectory.new()
	tr.set_state_d("moon", t0, Rtcc.conic_state(Bodies.MU_MOON, (rp + ra) / 2.0, (ra - rp) / (ra + rp), p, h, 0.0))
	return tr


## A GET given in seconds, or as "hhh:mm:ss".
static func _get_s(v: Variant) -> float:
	if v is String:
		var parts := (v as String).split(":")
		return float(parts[0]) * 3600.0 + float(parts[1]) * 60.0 + float(parts[2])
	return float(v)


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## DOI is the CSM's, flown on the SPS with the LM docked (mission.json
## "doi": by "csm", slice 12a: Apollo 14's), rather than the LM's on the DPS.
func _docked_doi() -> bool:
	return str(mission.section("doi").get("by", "lm")) == "csm"


## The landing site as the ground uplinks it to the LGC: the site, moved
## along the approach and to its right by the targeting's error
## (mission.json "pdi": site_error_m, m) [published for Apollo 14: its
## automatic guidance aimed 1,350 ft short of where it landed, a landmark
## offset error (MSC-04330, Appendix A)].
func _lgc_site() -> Vector3:
	var site := landing_site()
	var e: Array = mission.section("pdi").get("site_error_m", [0.0, 0.0])
	if float(e[0]) == 0.0 and float(e[1]) == 0.0:
		return site
	var up := site.normalized()
	var east := Vector3(0, 0, 1).cross(up).normalized()
	var north := up.cross(east)
	var az := deg_to_rad(float(mission.section("landing").get("approach_azimuth_deg", 270.0)))
	var along := north * cos(az) + east * sin(az)
	var right := north * cos(az + PI / 2.0) + east * sin(az + PI / 2.0)
	var moved := up * site.length() + along * float(e[0]) + right * float(e[1])
	return moved.normalized() * site.length()


## The landing site in the Moon-fixed frame, on the surface there, m. A
## mission without a landing sets its lunar orbit's plane by a site on its
## ground track instead (mission.json "lunar_site"), taken at the Moon's
## mean radius, which its orbit's altitudes count from [simplified].
func landing_site() -> Vector3:
	if not mission.data.has("landing"):
		var ls := mission.section("lunar_site")
		return Bodies.selenographic_to_fixed(float(ls["lat_deg"]), float(ls["lon_deg"]), Bodies.R_MOON)
	var l := mission.section("landing")
	var lat := float(l["lat_deg"])
	var lon := float(l["lon_deg"])
	return Bodies.selenographic_to_fixed(lat, lon, Bodies.R_MOON + Terrain.height(lat, lon))


## Where the LM stands in the surface's start phases, on the surface there
## (Moon-fixed, m): where the flight's came down (mission.json "landing":
## touchdown_lat_deg, touchdown_lon_deg), or else the landing site. Apollo
## 12's was the Surveyor's, and Intrepid came down 160 m from it.
func _touchdown_site() -> Vector3:
	var l := mission.section("landing")
	if not l.has("touchdown_lat_deg"):
		return landing_site()
	var lat := float(l["touchdown_lat_deg"])
	var lon := float(l["touchdown_lon_deg"])
	return Bodies.selenographic_to_fixed(lat, lon, Bodies.R_MOON + Terrain.height(lat, lon))


## When the lunar orbit's plane passes over the site (_site_normal()): the
## landing time, or the lunar site's time (mission.json "lunar_site":
## get).
func site_get() -> float:
	if not mission.data.has("landing"):
		return _get_s(mission.section("lunar_site")["get"])
	return float(mission.section("landing")["get_s"])


## The normal of the lunar orbit's plane over the site at its time
## (site_get()), its ground track heading the mission's approach azimuth
## there (mission.json "landing" or "lunar_site": approach_azimuth_deg),
## due west unless given (Rtcc.site_orbit_normal()).
func _site_normal() -> Vector3:
	var s := mission.section("landing") if mission.data.has("landing") else mission.section("lunar_site")
	return Rtcc.site_orbit_normal(landing_site(), site_get(), float(s.get("approach_azimuth_deg", 270.0)))


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


## Failure [param id] came: the event the catalog names, and the crew's
## words to Houston. In the launch, one the catalog says ends it
## ("launch") has the ground light ABORT (spacecraft.json "eds":
## ground_abort_s later).
func _on_failure(id: String) -> void:
	var e := Failures.entry(id)
	if e.has("event"):
		_fire(str(e["event"]))
	if e.has("call"):
		_say(str(e["call"]))
	var eds: Eds = systems.get("eds")
	if eds != null and eds.on_vehicle() and not eds.aborted and str(e.get("launch", "")) in ["abort", "return"]:
		ground_abort_return = ground_abort_return or str(e["launch"]) == "return"
		if not ground_abort_due:
			ground_abort_due = true
			ground_abort_get = SimClock.get_seconds + float(SpacecraftData.section("eds")["ground_abort_s"])


# --- The launch's aborts (slice 9d) --------------------------------------------

## The abort mode the flight is in now (mission.json "launch_aborts"): IA,
## IB and IC while the escape tower is on, II after it, and IV once the SPS
## can reach orbit, or with [param returning], when the crew must come
## home at once, III.
func _launch_abort_mode(returning: bool = false) -> String:
	var a := mission.section("launch_aborts")
	var now := SimClock.get_seconds
	if systems.has("les") and systems["les"].attached:
		if now < float(a.get("ib_get_s", 42.0)):
			return "IA"
		return "IB" if now < float(a.get("ic_get_s", 118.0)) else "IC"
	if returning and now >= float(a.get("iii_get_s", 540.0)):
		return "III"
	if not returning and now >= float(a.get("iv_get_s", 540.0)):
		return "IV"
	return "II"


## The ground's PAD for a launch abort's burn (slice 9d), after the CSM's
## separation: mode IV's into orbit (Rtcc.plan_mode_iv()), or mode III's
## retrograde burn to bring the CM's half-lift landing to the ground's
## aim (Rtcc.plan_mode_iii(), mission.json "launch_aborts"), from the
## CSM's tracked state, its ignition mode_iv_tig_s or mode_iii_tig_s after
## the separation, or a minute from now if later; uplinked with it (P27
## and P30) for P40, as the other PADs are. {} for mode I or II.
func _abort_pad() -> Dictionary:
	if not abort_mode in ["III", "IV"] or dynamics.config != "csm":
		last_pad = {}
		_say("Houston: no burn for your abort's mode %s." % (abort_mode if abort_mode != "" else "-"))
		return {}
	var a := mission.section("launch_aborts")
	var tracked := tracked_state(dynamics.traj)
	var tig := maxf(event_get("csm_lv_sep") + float(a.get("mode_%s_tig_s" % abort_mode.to_lower(), 120.0)),
		SimClock.get_seconds + 60.0)
	var pad := {}
	if abort_mode == "IV":
		pad = Rtcc.plan_mode_iv(tracked, dynamics.mass, tig)
	else:
		var l := mission.section("launch")
		pad = Rtcc.plan_mode_iii(tracked, dynamics.mass, tig, Vector2(float(l["pad_lat_deg"]), float(l["pad_lon_deg"])),
			float(a.get("mode_iii_target_nmi", 3200.0)), float(a.get("half_lift_bank_deg", 60.0)))
	if pad.is_empty():
		last_pad = {}
		_say("Houston: we have no mode %s solution for you." % abort_mode)
		return {}
	if float(pad["dv"]) < SPS_MIN_MPS:
		# Mode III lands short of the ground's aim without one.
		last_pad = pad
		pads["abort"] = pad
		_say("Houston: {csm}, no burn needed. CM/SM SEP and half lift; you'll land %.0f miles downrange." % float(
			pad.get("range_nmi", 0.0)))
		return pad
	return _uplink("abort", pad, tracked)


## The launch's calls of the mode as the flight passes them, and the
## ground's ABORT for a failure that ends the launch.
func _launch_aborts() -> void:
	var eds: Eds = systems.get("eds")
	if eds == null or not eds.on_vehicle():
		return
	Bus.set_value("mission.launch_mode", _launch_abort_mode(ground_abort_return))
	var now := SimClock.get_seconds
	var calls: Array = mission.section("launch_aborts").get("calls", [])
	if not eds.aborted and str(Bus.get_value("lv.state", "")) == "flight":
		while mode_calls_said < calls.size() and now >= float(calls[mode_calls_said][0]) - 1e-6:
			_say(str(calls[mode_calls_said][1]))
			mode_calls_said += 1
	if ground_abort_due and now >= ground_abort_get - 1e-6:
		ground_abort_due = false
		if not eds.aborted:
			abort_mode = _launch_abort_mode(ground_abort_return)
			Bus.set_value("mission.abort_mode", abort_mode)
			eds.request()
			_fire("abort_request")
			_say("Abort. Abort. Mode %s." % abort_mode.replace("IA", "One Alpha").replace("IB", "One Bravo") \
				.replace("IC", "One Charlie"))


## An abort started (Eds): in the mode the ground called, or the flight is
## in. The launch vehicle's engines cut off, but not in the first 30 s,
## for range safety; with the tower on, the CM leaves the SM and the escape
## motor pulls it away (Les), in mode IA tilted out to sea.
func _on_abort(kind: String) -> void:
	var eds: Eds = systems["eds"]
	if abort_mode == "":
		abort_mode = _launch_abort_mode(ground_abort_return)
	Bus.set_value("mission.abort_mode", abort_mode)
	_fire("launch_abort")
	var lv: LaunchVehicle = systems["lv"]
	if lv.state == "flight" and SimClock.get_seconds >= float(lv.events.get("liftoff", INF)) \
			+ float(SpacecraftData.section("eds")["beco_inhibit_s"]) - 1e-6:
		lv.cutoff()
	var why := {"2 ENG OUT": "two engines out", "LV RATE": "the rates", "HANDLE": "the handle"}
	if kind == "les":
		var a := lv.grr_axes
		var az := deg_to_rad(float(lv.launch.get("flight_azimuth_deg", 90.0)))
		var downrange := Vector3(a[3], a[4], a[5]) * cos(az) + Vector3(a[6], a[7], a[8]) * sin(az)
		var mode_1a := SimClock.get_seconds < float(SpacecraftData.section("les")["mode_1a_s"])
		dynamics.set_configuration("cm_les")
		systems["les"].abort(mode_1a, downrange)
		_fire("cm_sm_sep")
		_say("Abort, mode %s, on %s. The tower has you." % [abort_mode, why.get(eds.cause, eds.cause)])
	else:
		_say("Abort, mode %s, on %s. Booster cutoff; the CSM separates in 3 seconds." % [abort_mode,
			why.get(eds.cause, eds.cause)])


## The SPS abort's CSM/LV separation: the CSM flies on alone, the LM left
## on the S-IVB. The ground's word for the mode.
func _on_abort_separation() -> void:
	if dynamics.config != "saturn_v":
		return
	if systems.has("sivb"):
		systems["sivb"].state = "done"
		systems["sivb"].prop_kg = 0.0
	Bus.set_value("sivb.prop_kg", 0.0)
	dynamics.set_configuration("csm")
	_fire("csm_lv_sep")
	match abort_mode:
		"III":
			_say("Houston: {csm}, you're off. Mode III: P00 and ACCEPT for your retrograde burn's PAD, then CM/SM SEP and half lift.")
		"IV":
			_say("Houston: {csm}, you're off. Mode IV: P00 and ACCEPT for your PAD into orbit.")
		_:
			_say("Houston: {csm}, you're off. Mode II: CM/SM SEP when you're clear, full lift, ELS LOGIC and AUTO.")


## The escape tower's jettison: in an abort it leaves the CM to its chutes.
func _on_tower_jettisoned(aborted: bool) -> void:
	if not aborted or dynamics.config != "cm_les":
		return
	dynamics.set_configuration("cm")
	_fire("tower_jettison")
	_say("Tower jettison. Drogues next.")


func _fire(id: String) -> void:
	events.append({"id": id, "get_s": SimClock.get_seconds})
	Bus.set_value("mission.event." + id, SimClock.get_seconds)
	event_fired.emit(id)


## CAPCOM says [param text], each {role} in it the mission's call sign
## (Mission.words()), and [param more]'s entries for theirs.
func _say(text: String, more: Dictionary = {}) -> void:
	var words := mission.words(text, more)
	Bus.set_value("mission.capcom", "%s  %s" % [Units.hms(SimClock.get_seconds), words])
	capcom.emit(words)


func snapshot() -> Dictionary:
	return {"phase": phase, "events": events.duplicate(true), "visited_lunar_orbit": visited_lunar_orbit,
		"tli_cutoff_get": tli_cutoff_get, "plan": plan.duplicate(),
		"timeline_done": timeline_done.duplicate(), "seed": dispersion_seed, "rng_state": str(_rng.state),
		"alarms_answered": alarms_answered, "abort_mode": abort_mode, "ground_abort_due": ground_abort_due,
		"ground_abort_get": ground_abort_get,
		"ground_abort_return": ground_abort_return, "mode_calls_said": mode_calls_said,
		"tm_lost_get": tm_lost_get, "tm_call_said": tm_call_said, "fc_trip_get": fc_trip_get,
		"fc_call_said": fc_call_said}


func restore(d: Dictionary) -> void:
	phase = str(d["phase"])
	events = d["events"].duplicate(true)
	visited_lunar_orbit = bool(d["visited_lunar_orbit"])
	tli_cutoff_get = float(d["tli_cutoff_get"])
	plan = d.get("plan", {}).duplicate()
	timeline_done = d.get("timeline_done", {}).duplicate()
	alarms_answered = int(d.get("alarms_answered", 0))
	abort_mode = str(d.get("abort_mode", ""))
	Bus.set_value("mission.abort_mode", abort_mode)
	ground_abort_due = bool(d.get("ground_abort_due", false))
	ground_abort_get = float(d.get("ground_abort_get", 0.0))
	ground_abort_return = bool(d.get("ground_abort_return", false))
	mode_calls_said = int(d.get("mode_calls_said", 0))
	tm_lost_get = float(d.get("tm_lost_get", -1.0))
	tm_call_said = bool(d.get("tm_call_said", false))
	fc_trip_get = float(d.get("fc_trip_get", -1.0))
	fc_call_said = bool(d.get("fc_call_said", false))
	dispersion_seed = int(d.get("seed", 0))
	_rng.seed = dispersion_seed + 1
	_rng.state = str(d.get("rng_state", str(_rng.state))).to_int()
	pads = {}
	Bus.set_value("mission.phase", phase)
	for e in events:
		Bus.set_value("mission.event." + str(e["id"]), float(e["get_s"]))

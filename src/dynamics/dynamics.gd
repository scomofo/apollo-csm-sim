## Owns the truth state of the vehicles (trajectory + attitude +
## configuration) and steps it on the SimClock. Never touches scene nodes;
## publishes to the Bus and presentation reads it (same contract as the
## Dynamics of gemini-capsule, https://github.com/scomofo/gemini-capsule).
##
## The CSM (in any configuration, the docked LM included) publishes dyn.*.
## After undocking the LM flies free as a second vehicle, under its own
## engines and RCS, and publishes lm.dyn.*; the docking channels (dock.*)
## give the ports' relative state (src/dynamics/docking.gd). A contact
## between the ports within the capture limits docks the vehicles again;
## any other contact rebounds. The LM's mass, docked or free, follows its
## own propellant (its DPS, APS and RCS). The LM can land: CONTACT LIGHT
## when a probe touches the surface, touchdown when the footpads do, and
## then it sits on its gear, turning with the Moon, until its engine lifts
## it off.
##
## The CSM also feels small forces its computer doesn't model: the SM's
## vents, a steady force in body axes, and its attitude jets' net force
## while they fire, from their mismatched thrust (spacecraft.json
## "unmodelled", drawn from the mission's seed: disperse()). Its
## accelerometers sense them, but the CMC's state vector takes them in
## only while Average-G runs. They act through coast steps, which wait only
## for the commanded forces [simplified: the vent is steady, the LM and the
## S-IVB have none].
##
## Reads:  sps.thrust_n, rcs.force_body, rcs.torque_body, sivb.thrust_n,
##         sivb.dir, sps.prop_kg, rcs.sm_prop_kg, rcs.cm_prop_kg,
##         sivb.prop_kg, els.drogue, els.mains, guid.bank_cmd_deg,
##         guid.bank_auto, ctl.rhc, guid.dap_busy; the LM's lm.dps.thrust_n,
##         lm.aps.thrust_n, lm.rcs.force_body, lm.rcs.torque_body,
##         lm.dps.prop_kg, lm.aps.prop_kg, lm.rcs.prop_kg, lm.guid.dap_busy
## Writes: dyn.* (see publish_state), lm.dyn.* (the free LM's; docked,
##         lm.dyn.config alone: "lm", or "lm_ascent"), dock.state, dock.range_m,
##         dock.range_rate_mps, dock.rel_pos, dock.rel_vel (the LM's port
##         relative to the CSM's, CSM body axes), dock.misalign_deg,
##         dock.contact (the last contact, Docking.contact()),
##         lm.contact_light, lm.touchdown (Vehicle's), sys.coast_ok
class_name Dynamics
extends Node

## The probe met the drogue: [param contact] is Docking.contact()'s.
signal docking_contact(contact: Dictionary)
## The LM's footpads met the surface: [param touchdown] is Vehicle's.
signal lm_touchdown(touchdown: Dictionary)
## The landed LM left the surface at GET [param get_s].
signal lm_liftoff(get_s: float)

## Within this range of each other the vehicles take coast steps no longer
## than PROXIMITY_DT, so a contact between the ports is caught near where
## it happens.
const PROXIMITY_M := 200.0
const PROXIMITY_DT := 1.0
## Above this height over the reference sphere the LM is clear of any
## ground (the Moon's highest is 10.8 km).
const SURFACE_CHECK_M := 11000.0
## A landed LM lifts off on thrust beyond its weight by this factor, held
## this long.
const LIFTOFF_MARGIN := 1.1
const LIFTOFF_S := 0.5
## Above this height the Saturn V's drag is left out, m.
const LV_AERO_TOP_M := 150000.0
## The entry roll's time constant in its last degree, s: it settles on the
## command without hunting.
const BANK_SETTLE_S := 0.5

var traj: Trajectory = Trajectory.new()
var attitude: Attitude = Attitude.new()
var config: String = "stack"
var mass: float = 0.0
var landed: bool = false
var landed_speed: float = 0.0
## Entry bank angle (rad): the CM's lift-vector roll about the velocity,
## positive with the lift to the right; and its rate (rad/s).
var bank: float = 0.0
var bank_rate: float = 0.0
var g_load: float = 0.0
var max_g: float = 0.0
## Inertial non-gravitational ΔV accumulated since construction, m/s
## (what the IMU accelerometers integrate). Doubles.
var sensed_dv: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
## The CSM's unmodelled forces (disperse()): the vents' steady force, N,
## and the attitude jets' net force as a fraction of the force their
## torque takes, both in body axes.
var vent_force: Vector3 = Vector3.ZERO
var jet_imbalance: Vector3 = Vector3.ZERO
var last_force_body: Vector3 = Vector3.ZERO
var last_torque: Vector3 = Vector3.ZERO
## The LM while it flies free of the CSM; null while it is docked (part of
## the csm_lm configuration), before transposition and after LM JETT.
var lm: Vehicle = null
## The docked LM's configuration: "lm", or "lm_ascent" once staged.
var lm_config: String = "lm"
## The probe tip's height above the drogue, and its offset across it, at
## the last step: a contact is where the height crosses zero.
var _last_axial: float = 0.0
var _last_lateral: Vector3 = Vector3.ZERO


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.DYNAMICS)
	update_mass()
	publish_state()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func initialize(primary: String, get_s: float, pos: Vector3, vel: Vector3, cfg: String) -> void:
	traj.set_state(primary, get_s, pos, vel)
	config = cfg
	lm = null
	lm_config = "lm"
	landed = false
	bank = 0.0
	bank_rate = 0.0
	max_g = 0.0
	attitude.omega = Vector3.ZERO
	_align_prograde()
	update_mass()
	publish_state()


## Draw the CSM's unmodelled forces from [param seed]: each body axis's
## share of the vent force and of the jets' imbalance normal, at
## spacecraft.json "unmodelled"'s standard deviations.
func disperse(seed: int) -> void:
	var u := SpacecraftData.section("unmodelled")
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var sv := float(u.get("vent_force_n", 0.0))
	var sj := float(u.get("jet_imbalance", 0.0))
	vent_force = Vector3(rng.randfn(0.0, sv), rng.randfn(0.0, sv), rng.randfn(0.0, sv))
	jet_imbalance = Vector3(rng.randfn(0.0, sj), rng.randfn(0.0, sj), rng.randfn(0.0, sj))


## The CSM's unmodelled force now, body axes, N: its vents, and its
## attitude jets' imbalance while they fire [param torque]. None in the
## stack (the IU flies it) or for the CM alone.
func _unmodelled_force(torque: Vector3) -> Vector3:
	if config != "csm" and config != "csm_lm":
		return Vector3.ZERO
	var f := vent_force
	if torque != Vector3.ZERO and jet_imbalance != Vector3.ZERO:
		var c := SpacecraftData.config(config)
		var jets := absf(torque.x) / float(c["rcs_roll_arm_m"]) + (absf(torque.y) + absf(torque.z)) / float(c["rcs_pitch_arm_m"])
		f += jet_imbalance * jets
	return f


func set_configuration(cfg: String) -> void:
	assert(cfg in SpacecraftData.CONFIGS, "unknown configuration " + cfg)
	config = cfg
	if cfg == "cm":
		attitude.omega = Vector3.ZERO
	update_mass()
	Bus.set_value("dyn.config", config)


func update_mass() -> void:
	if config == "saturn_v":
		mass = float(Bus.get_value("lv.mass_kg", SpacecraftData.section("saturn_v")["liftoff_kg"]))
		attitude.inertia = SpacecraftData.inertia(config, mass)
		return
	mass = SpacecraftData.total_mass(config,
		float(Bus.get_value("sps.prop_kg", SpacecraftData.section("sps")["propellant_kg"])),
		float(Bus.get_value("rcs.sm_prop_kg", 4.0 * SpacecraftData.section("sm_rcs")["quad_propellant_kg"])),
		float(Bus.get_value("rcs.cm_prop_kg", 2.0 * SpacecraftData.section("cm_rcs")["ring_propellant_kg"])),
		float(Bus.get_value("sivb.prop_kg", SpacecraftData.section("sivb")["propellant_kg"])),
		_lm_mass(lm_config))
	attitude.inertia = SpacecraftData.inertia(config, mass)


## The LM's mass in [param cfg], from its systems' propellant (full tanks
## until they publish it).
func _lm_mass(cfg: String) -> float:
	var f := SpacecraftData.lm_full_loads()
	return SpacecraftData.lm_total_mass(cfg, float(Bus.get_value("lm.dps.prop_kg", f[0])),
		float(Bus.get_value("lm.aps.prop_kg", f[1])), float(Bus.get_value("lm.rcs.prop_kg", f[2])))


## The LM is still with the mission: in the S-IVB's adapter, docked, or
## flying free (not jettisoned).
func has_lm() -> bool:
	return lm != null or config == "saturn_v" or config == "stack" or config == "csm_lm"


## The speed through the air, which turns with the Earth, m/s.
func air_speed() -> float:
	return Atmosphere.air_velocity(traj.pos(), traj.vel()).length()


func in_atmosphere() -> bool:
	return traj.primary == "earth" and traj.altitude() < Bodies.ENTRY_INTERFACE_ALT


func tick(dt: float) -> void:
	if landed:
		_step_lm(dt)
		_publish_docking()
		_publish_coast(false)
		return
	update_mass()
	if config == "saturn_v" and bool(Bus.get_value("lv.held", false)):
		_hold_on_pad(dt)
		return
	var ecl := attitude.eci_from_body()
	var force_body := Vector3.ZERO
	var force_eci := Vector3.ZERO
	var torque := Vector3.ZERO
	if config == "saturn_v":
		var d: Array = Bus.get_value("lv.dir", [1.0, 0.0, 0.0])
		force_eci += Vector3(d[0], d[1], d[2]).normalized() * float(Bus.get_value("lv.thrust_n", 0.0))
	elif config != "stack":
		force_body.x += float(Bus.get_value("sps.thrust_n", 0.0)) if config != "cm" else 0.0
		force_body += Bus.get_value("rcs.force_body", Vector3.ZERO)
		torque = Bus.get_value("rcs.torque_body", Vector3.ZERO)
	else:
		var sivb_f := float(Bus.get_value("sivb.thrust_n", 0.0))
		if sivb_f > 0.0:
			var d: Array = Bus.get_value("sivb.dir", [1.0, 0.0, 0.0])
			force_eci += Vector3(d[0], d[1], d[2]).normalized() * sivb_f
	var aero_eci := Vector3.ZERO
	var aero := config == "cm" and in_atmosphere()
	if aero:
		aero_eci = _aero_force()
	elif config == "saturn_v" and traj.primary == "earth" and traj.altitude() < LV_AERO_TOP_M:
		aero_eci = _lv_drag()
	force_eci += ecl * force_body + aero_eci
	last_force_body = force_body
	last_torque = torque
	# A coast step waits for the commanded forces to stop; the unmodelled
	# ones act through it.
	var commanded := force_eci != Vector3.ZERO
	force_eci += ecl * _unmodelled_force(torque)
	var a := force_eci / mass
	var ext := PackedFloat64Array([a.x, a.y, a.z]) if force_eci != Vector3.ZERO else PackedFloat64Array()
	traj.step(dt, ext)
	if ext.size() == 3:
		for i in 3:
			sensed_dv[i] += ext[i] * dt
	g_load = a.length() / Units.G0
	max_g = maxf(max_g, g_load)
	# Attitude.
	if config == "saturn_v":
		_align_lv()
	elif config == "stack":
		_align_iu()
	elif aero:
		_entry_attitude(dt)
	else:
		attitude.step(dt, torque)
	if traj.altitude() <= 0.0:
		landed = true
		# Against the ground, which on the Earth turns with the air.
		landed_speed = air_speed() if traj.primary == "earth" else traj.speed()
		attitude.omega = Vector3.ZERO
	# A coast step may only be long when nothing acts on the vehicle AND no
	# autopilot is trying to (a controller cannot run at minute steps).
	var coasting := not commanded and torque == Vector3.ZERO and not aero and not landed \
		and not bool(Bus.get_value("guid.dap_busy", false))
	Bus.set_value("dyn.dv_step", [ext[0] * dt, ext[1] * dt, ext[2] * dt] if ext.size() == 3 else [0.0, 0.0, 0.0])
	_step_lm(dt)
	publish_state()
	_publish_coast(coasting and (lm == null or (lm.coasting and not bool(Bus.get_value("lm.guid.dap_busy", false)))))


## The coast-step policy holds for both vehicles: a coast step is taken
## only while both coast (nothing acts on either, and neither's autopilot
## is trying to), and it is no longer than either trajectory allows, or
## than PROXIMITY_DT while they are close.
func _publish_coast(coasting: bool) -> void:
	Bus.set_value("sys.coast_ok", coasting)
	var dt := traj.coast_dt()
	if lm != null:
		dt = minf(dt, lm.traj.coast_dt())
		if float(Docking.relative(traj, attitude, lm)["range"]) < PROXIMITY_M:
			dt = minf(dt, PROXIMITY_DT)
	Bus.set_value("dyn.coast_dt_s", dt)


# --- the LM and docking -----------------------------------------------------------

## Undock the LM: the stack splits into the CSM and the LM, each moving as
## its part of the stack did, and the probe pushes them apart along the
## docking axis, momentum conserved. Returns false unless the LM is docked.
func undock() -> bool:
	if config != "csm_lm":
		return false
	var p := Docking.params()
	var m_lm := _lm_mass(lm_config)
	update_mass()
	var m := mass
	var m_csm := m - m_lm
	var ecl := attitude.eci_from_body()
	var x := ecl * Vector3.RIGHT
	var w := ecl * attitude.omega
	var span := float(p["csm_port_m"]) + Docking.lm_port_m(lm_config)
	var push := float(p["undock_speed_mps"])
	# Each centre of mass from the stack's, and its velocity.
	var off_csm := -x * (span * m_lm / m)
	var off_lm := x * (span * m_csm / m)
	var dv_csm := w.cross(off_csm) - x * (push * m_lm / m)
	var dv_lm := w.cross(off_lm) + x * (push * m_csm / m)
	var s := traj.s.duplicate()
	for i in 3:
		s[i] += off_lm[i]
		s[3 + i] += dv_lm[i]
		traj.s[i] += off_csm[i]
		traj.s[3 + i] += dv_csm[i]
	lm = Vehicle.new("lm", lm_config, m_lm)
	lm.traj.set_state_d(traj.primary, traj.t, s)
	lm.attitude.q = (attitude.q * Docking.LM_IN_CSM).normalized()
	# [simplified] The LM's DAP nulls the stack's rates as it undocks: the
	# LM keeps none of them, and its DAP holds the attitude it undocked in.
	lm.attitude.omega = Vector3.ZERO
	config = "csm"
	update_mass()
	_arm_contact()
	publish_state()
	return true


## Step the free LM under its engines and RCS. On the surface it sits
## on its gear until its engine's thrust carries it off: thrust that beats
## its weight by LIFTOFF_MARGIN for LIFTOFF_S, not an engine tailing off
## after touchdown.
func _step_lm(dt: float) -> void:
	if lm == null:
		return
	lm.mass = _lm_mass(lm.config)
	lm.attitude.inertia = SpacecraftData.inertia(lm.config, lm.mass)
	var thrust := float(Bus.get_value("lm.dps.thrust_n", 0.0)) + float(Bus.get_value("lm.aps.thrust_n", 0.0))
	if lm.landed:
		var up := lm.traj.pos().normalized()
		var lift := (lm.attitude.eci_from_body() * Vector3(thrust, 0.0, 0.0)).dot(up) / lm.mass
		var g := Bodies.MU_MOON / (lm.traj.radius() * lm.traj.radius())
		lm.lift_s = lm.lift_s + dt if lift > g * LIFTOFF_MARGIN else 0.0
		if lm.lift_s < LIFTOFF_S:
			lm.hold_on_surface(lm.traj.t + dt)
			# An engine running keeps the steps fine: its thrust builds, or
			# tails off, over them.
			lm.coasting = thrust <= 0.0
			return
		lm.landed = false
		lm.lift_s = 0.0
		lm_liftoff.emit(lm.traj.t)
	var force := Vector3(thrust, 0.0, 0.0)
	force += Bus.get_value("lm.rcs.force_body", Vector3.ZERO)
	lm.step(dt, force, Bus.get_value("lm.rcs.torque_body", Vector3.ZERO))
	_check_surface()
	_check_contact()


## The LM's centre of mass above its footpads on the surface, m (the
## ascent stage's sits on the descent stage).
static func lm_cm_height(cfg: String) -> float:
	var h := float(SpacecraftData.section("lm_gear")["cm_height_m"])
	return h + (Docking.lm_port_m("lm") - Docking.lm_port_m("lm_ascent") if cfg == "lm_ascent" else 0.0)


## The LM's gear meets the surface (Terrain): CONTACT LIGHT when a probe
## touches, and touchdown when the footpads do. The touchdown's speeds are
## relative to the turning surface; beyond the gear's limits it is a hard
## landing [simplified: the gear meets the ground straight below the
## centre of mass, level; the LM doesn't tip over or break].
func _check_surface() -> void:
	if lm.traj.primary != "moon":
		return
	if lm.traj.radius() - Bodies.R_MOON > SURFACE_CHECK_M:
		Bus.set_value("lm.contact_light", false)
		return
	var gear := SpacecraftData.section("lm_gear")
	var cm := lm_cm_height(lm.config)
	var r := lm.traj.pos()
	var ground := Terrain.radius_under(Bodies.moon_fixed(lm.traj.t).transposed() * r)
	var alt := lm.traj.radius() - ground
	Bus.set_value("lm.contact_light", lm.config == "lm" and alt <= cm + float(gear["probe_m"]))
	if alt > cm:
		return
	var up := r.normalized()
	var rel := lm.traj.vel() - Bodies.moon_omega(lm.traj.t).cross(r)
	var down := -rel.dot(up)
	var across := (rel + up * down).length()
	lm.land(ground + cm)
	var at := Bodies.fixed_to_selenographic(lm.landed_pos)
	lm.touchdown = {"get_s": lm.traj.t, "vertical_mps": down, "horizontal_mps": across,
		"lat_deg": at.x, "lon_deg": at.y,
		"hard": down > float(gear["vertical_max_mps"]) or across > float(gear["horizontal_max_mps"])}
	Bus.set_value("lm.touchdown", lm.touchdown)
	lm_touchdown.emit(lm.touchdown)


## Stage the free LM: the ascent stage flies on from where its centre of
## mass was in the whole LM, moving and turning as the LM was, and the
## descent stage stays behind [simplified: it is no longer simulated].
## The docking port doesn't move. Returns false unless the whole LM flies
## free.
func stage_lm() -> bool:
	if lm == null or lm.config != "lm":
		return false
	var ecl := lm.attitude.eci_from_body()
	var off := ecl * Vector3(Docking.lm_port_m("lm") - Docking.lm_port_m("lm_ascent"), 0.0, 0.0)
	var dv := (ecl * lm.attitude.omega).cross(off)
	for i in 3:
		lm.traj.s[i] += off[i]
		lm.traj.s[3 + i] += dv[i]
	if lm.landed:
		# On the surface the ascent stage sits on the descent stage.
		lm.landed_pos += Bodies.moon_fixed(lm.traj.t).transposed() * off
	lm.config = "lm_ascent"
	lm.mass = _lm_mass(lm.config)
	lm.attitude.inertia = SpacecraftData.inertia(lm.config, lm.mass)
	_arm_contact()
	publish_state()
	return true


## Take the probe tip's place over the drogue as the start of the next
## step's contact check.
func _arm_contact() -> void:
	var g := Docking.relative(traj, attitude, lm)
	_last_axial = g["axial"]
	_last_lateral = g["lateral"]


## A contact is the probe tip reaching the drogue's face during the step,
## within the strike radius of its centre: within the capture limits it
## docks the vehicles, otherwise they rebound. The probe passing beside the
## LM touches nothing.
func _check_contact() -> void:
	var g := Docking.relative(traj, attitude, lm)
	var axial: float = g["axial"]
	var lateral: Vector3 = g["lateral"]
	if _last_axial > 0.0 and axial <= 0.0 and float(g["closing"]) > 1e-6:
		var f := _last_axial / (_last_axial - axial)
		var miss := _last_lateral.lerp(lateral, f).length()
		if miss <= float(Docking.params()["strike_radius_m"]):
			var c := Docking.contact(g, miss)
			if c["captured"]:
				_capture()
			else:
				_rebound(g)
			Bus.set_value("dock.contact", c)
			docking_contact.emit(c)
			return
	_last_axial = axial
	_last_lateral = lateral


## Capture: the vehicles are one again, the stack moving with their joint
## momentum and turning with their joint angular momentum about its centre
## of mass, in the CSM's attitude [simplified: the latches pull the LM
## straight].
func _capture() -> void:
	var m_csm := mass
	var m_lm := lm.mass
	var m := m_csm + m_lm
	var rel := Docking.relative_state(traj, lm.traj)
	var to_body := attitude.body_from_eci()
	var ic := attitude.inertia
	var il := lm.attitude.inertia
	var wl := lm.attitude.omega
	var h := Vector3(ic.x * attitude.omega.x, ic.y * attitude.omega.y, ic.z * attitude.omega.z)
	h += to_body * lm.attitude.eci_from_body() * Vector3(il.x * wl.x, il.y * wl.y, il.z * wl.z)
	h += to_body * Vector3(rel[0], rel[1], rel[2]).cross(Vector3(rel[3], rel[4], rel[5])) * (m_csm * m_lm / m)
	for i in 6:
		traj.s[i] += rel[i] * m_lm / m
	lm_config = lm.config
	lm = null
	# The LM's IMU senses nothing more of its own.
	Bus.set_value("lm.dyn.dv_step", [0.0, 0.0, 0.0])
	config = "csm_lm"
	update_mass()
	var i_s := attitude.inertia
	attitude.omega = Vector3(h.x / i_s.x, h.y / i_s.y, h.z / i_s.z)
	publish_state()


## A contact without capture: the probe rebounds from the drogue, taking
## back the restitution's share of the closing speed, momentum conserved
## [simplified: the vehicles' rates don't change].
func _rebound(g: Dictionary) -> void:
	var m_csm := mass
	var m_lm := lm.mass
	var m := m_csm + m_lm
	var n: Vector3 = g["n"]
	var dv := n * ((1.0 + float(Docking.params()["restitution"])) * float(g["closing"]))
	var back := n * -float(g["axial"])
	for i in 3:
		traj.s[i] += back[i] * m_lm / m
		traj.s[3 + i] += dv[i] * m_lm / m
		lm.traj.s[i] -= back[i] * m_csm / m
		lm.traj.s[3 + i] -= dv[i] * m_csm / m
	_arm_contact()


func _publish_docking() -> void:
	Bus.set_value("dock.state", "free" if lm != null else ("docked" if config == "csm_lm" else "none"))
	if lm == null:
		if config == "csm_lm":
			Bus.set_value("lm.dyn.config", lm_config)
		return
	lm.publish()
	var g := Docking.relative(traj, attitude, lm)
	var d: Vector3 = g["d"]
	var u: Vector3 = g["u"]
	var to_body := attitude.body_from_eci()
	Bus.set_value("dock.range_m", g["range"])
	Bus.set_value("dock.range_rate_mps", d.dot(u) / maxf(d.length(), 1e-6))
	Bus.set_value("dock.rel_pos", to_body * d)
	Bus.set_value("dock.rel_vel", to_body * u)
	Bus.set_value("dock.misalign_deg", g["misalign_deg"])


## On the pad, held by the holddown arms: the vehicle turns with the Earth,
## from its state at the step's end.
func _hold_on_pad(dt: float) -> void:
	var p: Array = Bus.get_value("lv.pad_fixed", [])
	if p.size() == 3:
		traj.set_state_d("earth", traj.t + dt, LaunchVehicle.pad_state_of(p, traj.t + dt))
	_align_lv()
	g_load = 1.0
	Bus.set_value("dyn.dv_step", [0.0, 0.0, 0.0])
	publish_state()
	_publish_coast(false)


## The Saturn V's drag through the turning air: its axial force
## coefficient at the Mach number on its cross-section (spacecraft.json
## "saturn_v"), along the air's velocity [simplified: the angle of attack's
## normal force left out], inertial N.
func _lv_drag() -> Vector3:
	var h := traj.altitude()
	var va := Atmosphere.air_velocity(traj.pos(), traj.vel())
	var sp := va.length()
	if sp < 1e-3:
		return Vector3.ZERO
	var d := SpacecraftData.section("saturn_v")
	var mach := sp / Atmosphere.sound_speed(h)
	var table: Array = d["cd_mach"]
	var cd := float(table[-1][1])
	for i in range(1, table.size()):
		if mach <= float(table[i][0]):
			var m0 := float(table[i - 1][0])
			cd = lerpf(float(table[i - 1][1]), float(table[i][1]), (mach - m0) / (float(table[i][0]) - m0))
			break
	return -va / sp * 0.5 * Atmosphere.density(h) * sp * sp * cd * float(d["reference_area_m2"])


## The Instrument Unit flies the Saturn V: the attitude is the one it
## publishes.
func _align_lv() -> void:
	var q: Array = Bus.get_value("lv.q", [])
	if q.size() == 4:
		attitude.q = Quaternion(q[0], q[1], q[2], q[3]).normalized()
	attitude.omega = Vector3.ZERO


## Aerodynamic + parachute force on the CM, inertial N, through the turning
## air.
func _aero_force() -> Vector3:
	var v := Atmosphere.air_velocity(traj.pos(), traj.vel())
	var sp := v.length()
	if sp < 1e-3:
		return Vector3.ZERO
	var rho := Atmosphere.density(traj.altitude())
	var q := 0.5 * rho * sp * sp
	var ad := SpacecraftData.section("cm_aero")
	var els := SpacecraftData.section("els")
	var vhat := v / sp
	var cds := float(ad["cd"]) * float(ad["reference_area_m2"])
	var lift := 0.0
	if bool(Bus.get_value("els.mains", false)):
		var frac := float(Bus.get_value("els.main_fraction", 1.0))
		cds += maxf(float(els["drogue_cds_m2"]) * (1.0 - frac), float(els["main_cds_m2"]) * frac)
	elif bool(Bus.get_value("els.drogue", false)):
		cds += float(els["drogue_cds_m2"])
	else:
		lift = float(ad["lift_to_drag"]) * cds
	var force := -vhat * q * cds
	if lift > 0.0:
		force += _lift_dir(vhat) * q * lift
	return force


## Lift direction for the current bank angle: bank 0 is lift up.
func _lift_dir(vhat: Vector3) -> Vector3:
	return lift_direction(traj.pos(), vhat, bank)


## The lift's direction at [param r] flying along [param vhat] (the air's
## velocity, a unit vector) banked [param p_bank] (rad): 0 is lift up,
## positive to the right.
static func lift_direction(r: Vector3, vhat: Vector3, p_bank: float) -> Vector3:
	var u := r.normalized()
	var up := u - vhat * u.dot(vhat)
	if up.length() < 1e-6:
		# Vertical descent: any horizontal direction will do.
		up = vhat.cross(Vector3.RIGHT if absf(vhat.x) < 0.9 else Vector3.UP)
	up = up.normalized()
	var side := vhat.cross(up)
	return (up * cos(p_bank) + side * sin(p_bank)).normalized()


## The CM's attitude trimmed in the air (body to ECI): the heat shield (−X)
## into the air's velocity [param vhat] at [param r], the lift banked
## [param p_bank] (rad), along body −Z.
static func trim_basis(r: Vector3, vhat: Vector3, p_bank: float) -> Basis:
	var x := -vhat
	var zb := -lift_direction(r, vhat, p_bank)
	var y := zb.cross(x).normalized()
	return Basis(x, y, x.cross(y))


## During entry the CM flies trimmed, heat shield (−X) forward; the only
## attitude freedom is bank about the velocity vector, driven by the CMC
## (guid.bank_cmd_deg while guid.bank_auto) or the RHC roll axis. The
## CMC's entry DAP rolls at up to max_bank_rate_dps, speeding up at
## bank_accel_dps2 and braking as one jet does, at half that; the shortest
## way round, or through lift up (never lift down) while
## guid.bank_over_top.
func _entry_attitude(dt: float) -> void:
	var ad := SpacecraftData.section("cm_aero")
	var rate := deg_to_rad(float(ad["max_bank_rate_dps"]))
	var cm_rcs := float(Bus.get_value("rcs.cm_prop_kg", 1.0)) > 0.0
	if not cm_rcs:
		bank_rate = 0.0
	elif bool(Bus.get_value("guid.bank_auto", false)):
		var acc := deg_to_rad(float(ad["bank_accel_dps2"]))
		var cmd := wrapf(deg_to_rad(float(Bus.get_value("guid.bank_cmd_deg", 0.0))), -PI, PI)
		var err := wrapf(cmd - bank, -PI, PI)
		if bool(Bus.get_value("guid.bank_over_top", false)):
			err = cmd - bank
		# The rate from which it still stops on the command, and within a
		# degree of it proportionally less.
		var want := signf(err) * minf(minf(rate, sqrt(acc * absf(err))), absf(err) / BANK_SETTLE_S)
		bank_rate = move_toward(bank_rate, want, acc * dt)
	else:
		var rhc: Vector3 = Bus.get_value("ctl.rhc", Vector3.ZERO)
		bank_rate = rhc.x * rate
	bank = wrapf(bank + bank_rate * dt, -PI, PI)
	var vhat := Atmosphere.air_velocity(traj.pos(), traj.vel()).normalized()
	attitude.align_to(trim_basis(traj.pos(), vhat, bank))
	attitude.omega = Vector3.ZERO


## The Instrument Unit holds the stack in a prograde, heads-down attitude
## (orbital-rate pitch) in parking orbit and during TLI.
func _align_iu() -> void:
	_align_prograde()
	attitude.omega = Vector3.ZERO


func _align_prograde() -> void:
	var r := traj.pos()
	var v := traj.vel()
	if v.length() < 1e-6:
		return
	var b := Trajectory.lvlh_basis(r, v)
	attitude.align_to(b)


func publish_state() -> void:
	Vehicle.publish_motion("", traj, attitude, mass, config)
	Bus.set_value("dyn.g_load", g_load)
	Bus.set_value("dyn.max_g", max_g)
	Bus.set_value("dyn.bank_deg", rad_to_deg(bank))
	Bus.set_value("dyn.landed", landed)
	Bus.set_value("dyn.landed_speed_mps", landed_speed)
	Bus.set_value("dyn.in_atmosphere", in_atmosphere())
	Bus.set_value("dyn.air_speed_mps", air_speed() if traj.primary == "earth" else traj.speed())
	var e := traj.earth_state()
	var m := traj.moon_state_rel()
	Bus.set_value("dyn.earth_dist_m", Vector3(e[0], e[1], e[2]).length())
	Bus.set_value("dyn.moon_dist_m", Vector3(m[0], m[1], m[2]).length())
	_publish_docking()


func snapshot() -> Dictionary:
	return {
		"primary": traj.primary, "t": traj.t, "s": Array(traj.s), "field": traj.field_snapshot(),
		"q": [attitude.q.x, attitude.q.y, attitude.q.z, attitude.q.w],
		"omega": [attitude.omega.x, attitude.omega.y, attitude.omega.z],
		"config": config, "landed": landed, "landed_speed": landed_speed,
		"bank": bank, "bank_rate": bank_rate, "max_g": max_g, "sensed_dv": Array(sensed_dv),
		"lm_config": lm_config,
		"vent_force": [vent_force.x, vent_force.y, vent_force.z],
		"jet_imbalance": [jet_imbalance.x, jet_imbalance.y, jet_imbalance.z],
	}


## Restore the CSM from [param d], and the free LM from [param lm_d] (empty
## while the LM is docked or gone).
func restore(d: Dictionary, lm_d: Dictionary = {}) -> void:
	traj.set_state_d(str(d["primary"]), float(d["t"]), PackedFloat64Array(d["s"]))
	traj.restore_field(d.get("field", {}))
	var q: Array = d["q"]
	attitude.q = Quaternion(q[0], q[1], q[2], q[3])
	var w: Array = d["omega"]
	attitude.omega = Vector3(w[0], w[1], w[2])
	config = str(d["config"])
	landed = bool(d["landed"])
	landed_speed = float(d.get("landed_speed", 0.0))
	bank = float(d.get("bank", 0.0))
	bank_rate = float(d.get("bank_rate", 0.0))
	max_g = float(d.get("max_g", 0.0))
	sensed_dv = PackedFloat64Array(d.get("sensed_dv", [0, 0, 0]))
	lm_config = str(d.get("lm_config", "lm"))
	var vf: Array = d.get("vent_force", [0.0, 0.0, 0.0])
	vent_force = Vector3(vf[0], vf[1], vf[2])
	var ji: Array = d.get("jet_imbalance", [0.0, 0.0, 0.0])
	jet_imbalance = Vector3(ji[0], ji[1], ji[2])
	update_mass()
	lm = Vehicle.from_snapshot(lm_d) if not lm_d.is_empty() else null
	if lm != null:
		_arm_contact()
	publish_state()
	# What _check_surface() published at touchdown: a landed LM's probes
	# still touch, and its last touchdown stands.
	if lm != null:
		if lm.landed:
			Bus.set_value("lm.contact_light", lm.config == "lm")
		if not lm.touchdown.is_empty():
			Bus.set_value("lm.touchdown", lm.touchdown)

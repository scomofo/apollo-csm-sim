## Owns the truth state of the vehicle (trajectory + attitude + configuration)
## and steps it on the SimClock. Never touches scene nodes; publishes to the
## Bus and presentation reads it (same contract as the Dynamics of
## gemini-capsule, https://github.com/scomofo/gemini-capsule).
##
## Reads:  sps.thrust_n, rcs.force_body, rcs.torque_body, sivb.thrust_n,
##         sivb.dir, sps.prop_kg, rcs.sm_prop_kg, rcs.cm_prop_kg,
##         sivb.prop_kg, els.drogue, els.mains, guid.bank_cmd_deg,
##         guid.bank_auto, ctl.rhc
## Writes: dyn.* (see publish_state), sys.coast_ok
class_name Dynamics
extends Node

var traj: Trajectory = Trajectory.new()
var attitude: Attitude = Attitude.new()
var config: String = "stack"
var mass: float = 0.0
var landed: bool = false
var landed_speed: float = 0.0
## Entry bank angle (rad): the CM's lift-vector roll about the velocity.
var bank: float = 0.0
var g_load: float = 0.0
var max_g: float = 0.0
## Inertial non-gravitational ΔV accumulated since construction, m/s
## (what the IMU accelerometers integrate). Doubles.
var sensed_dv: PackedFloat64Array = PackedFloat64Array([0, 0, 0])
var last_force_body: Vector3 = Vector3.ZERO
var last_torque: Vector3 = Vector3.ZERO


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.DYNAMICS)
	update_mass()
	publish_state()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func initialize(primary: String, get_s: float, pos: Vector3, vel: Vector3, cfg: String) -> void:
	traj.set_state(primary, get_s, pos, vel)
	config = cfg
	landed = false
	bank = 0.0
	max_g = 0.0
	attitude.omega = Vector3.ZERO
	_align_prograde()
	update_mass()
	publish_state()


func set_configuration(cfg: String) -> void:
	assert(cfg in SpacecraftData.CONFIGS, "unknown configuration " + cfg)
	config = cfg
	if cfg == "cm":
		attitude.omega = Vector3.ZERO
	update_mass()
	Bus.set_value("dyn.config", config)


func update_mass() -> void:
	mass = SpacecraftData.total_mass(config,
		float(Bus.get_value("sps.prop_kg", SpacecraftData.section("sps")["propellant_kg"])),
		float(Bus.get_value("rcs.sm_prop_kg", 4.0 * SpacecraftData.section("sm_rcs")["quad_propellant_kg"])),
		float(Bus.get_value("rcs.cm_prop_kg", 2.0 * SpacecraftData.section("cm_rcs")["ring_propellant_kg"])),
		float(Bus.get_value("sivb.prop_kg", SpacecraftData.section("sivb")["propellant_kg"])))
	attitude.inertia = SpacecraftData.inertia(config, mass)


func in_atmosphere() -> bool:
	return traj.primary == "earth" and traj.altitude() < Bodies.ENTRY_INTERFACE_ALT


func tick(dt: float) -> void:
	if landed:
		_publish_coast(false)
		return
	update_mass()
	var ecl := attitude.eci_from_body()
	var force_body := Vector3.ZERO
	var force_eci := Vector3.ZERO
	var torque := Vector3.ZERO
	if config != "stack":
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
	force_eci += ecl * force_body + aero_eci
	last_force_body = force_body
	last_torque = torque
	var a := force_eci / mass
	var ext := PackedFloat64Array([a.x, a.y, a.z]) if force_eci != Vector3.ZERO else PackedFloat64Array()
	traj.step(dt, ext)
	if ext.size() == 3:
		for i in 3:
			sensed_dv[i] += ext[i] * dt
	g_load = a.length() / Units.G0
	max_g = maxf(max_g, g_load)
	# Attitude.
	if config == "stack":
		_align_iu()
	elif aero:
		_entry_attitude(dt)
	else:
		attitude.step(dt, torque)
	if traj.altitude() <= 0.0:
		landed = true
		landed_speed = traj.speed()
		attitude.omega = Vector3.ZERO
	# A coast step may only be long when nothing acts on the vehicle AND no
	# autopilot is trying to (a controller cannot run at minute steps).
	var coasting := force_eci == Vector3.ZERO and torque == Vector3.ZERO and not aero and not landed \
		and not bool(Bus.get_value("guid.dap_busy", false))
	Bus.set_value("dyn.dv_step", [ext[0] * dt, ext[1] * dt, ext[2] * dt] if ext.size() == 3 else [0.0, 0.0, 0.0])
	publish_state()
	_publish_coast(coasting)


func _publish_coast(coasting: bool) -> void:
	Bus.set_value("sys.coast_ok", coasting)
	Bus.set_value("dyn.coast_dt_s", traj.coast_dt())


## Aerodynamic + parachute force on the CM, inertial N.
func _aero_force() -> Vector3:
	var v := traj.vel()
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
	var r := traj.pos().normalized()
	var up := r - vhat * r.dot(vhat)
	if up.length() < 1e-6:
		# Vertical descent: any horizontal direction will do.
		up = vhat.cross(Vector3.RIGHT if absf(vhat.x) < 0.9 else Vector3.UP)
	up = up.normalized()
	var side := vhat.cross(up)
	return (up * cos(bank) + side * sin(bank)).normalized()


## During entry the CM flies trimmed, heat shield (−X) forward; the only
## attitude freedom is bank about the velocity vector, driven by the CMC
## (guid.bank_cmd_deg while guid.bank_auto) or the RHC roll axis.
func _entry_attitude(dt: float) -> void:
	var rate := deg_to_rad(float(SpacecraftData.section("cm_aero")["max_bank_rate_dps"]))
	var cm_rcs := float(Bus.get_value("rcs.cm_prop_kg", 1.0)) > 0.0
	if cm_rcs:
		if bool(Bus.get_value("guid.bank_auto", false)):
			var cmd := deg_to_rad(float(Bus.get_value("guid.bank_cmd_deg", 0.0)))
			var err := wrapf(cmd - bank, -PI, PI)
			bank += clampf(err, -rate * dt, rate * dt)
		else:
			var rhc: Vector3 = Bus.get_value("ctl.rhc", Vector3.ZERO)
			bank += rhc.x * rate * dt
	bank = wrapf(bank, -PI, PI)
	var vhat := traj.vel().normalized()
	var x := -vhat
	var zb := -_lift_dir(vhat)
	var y := zb.cross(x).normalized()
	attitude.align_to(Basis(x, y, x.cross(y)))
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
	var c := traj.conic()
	var rb := Bodies.radius_of(traj.primary)
	Bus.set_value("dyn.primary", traj.primary)
	Bus.set_value("dyn.config", config)
	Bus.set_value("dyn.r_m", [traj.s[0], traj.s[1], traj.s[2]])
	Bus.set_value("dyn.v_mps", [traj.s[3], traj.s[4], traj.s[5]])
	Bus.set_value("dyn.alt_m", traj.altitude())
	Bus.set_value("dyn.speed_mps", traj.speed())
	Bus.set_value("dyn.alt_rate_mps", traj.radial_rate())
	Bus.set_value("dyn.peri_alt_m", float(c["rp"]) - rb)
	Bus.set_value("dyn.apo_alt_m", float(c["ra"]) - rb if c["ra"] != INF else INF)
	Bus.set_value("dyn.mass_kg", mass)
	Bus.set_value("dyn.att_q", attitude.q)
	Bus.set_value("dyn.omega", attitude.omega)
	Bus.set_value("dyn.g_load", g_load)
	Bus.set_value("dyn.max_g", max_g)
	Bus.set_value("dyn.bank_deg", rad_to_deg(bank))
	Bus.set_value("dyn.landed", landed)
	Bus.set_value("dyn.landed_speed_mps", landed_speed)
	Bus.set_value("dyn.in_atmosphere", in_atmosphere())
	var e := traj.earth_state()
	var m := traj.moon_state_rel()
	Bus.set_value("dyn.earth_dist_m", Vector3(e[0], e[1], e[2]).length())
	Bus.set_value("dyn.moon_dist_m", Vector3(m[0], m[1], m[2]).length())


func snapshot() -> Dictionary:
	return {
		"primary": traj.primary, "t": traj.t, "s": Array(traj.s),
		"q": [attitude.q.x, attitude.q.y, attitude.q.z, attitude.q.w],
		"omega": [attitude.omega.x, attitude.omega.y, attitude.omega.z],
		"config": config, "landed": landed, "landed_speed": landed_speed,
		"bank": bank, "max_g": max_g, "sensed_dv": Array(sensed_dv),
	}


func restore(d: Dictionary) -> void:
	traj.set_state_d(str(d["primary"]), float(d["t"]), PackedFloat64Array(d["s"]))
	var q: Array = d["q"]
	attitude.q = Quaternion(q[0], q[1], q[2], q[3])
	var w: Array = d["omega"]
	attitude.omega = Vector3(w[0], w[1], w[2])
	config = str(d["config"])
	landed = bool(d["landed"])
	landed_speed = float(d.get("landed_speed", 0.0))
	bank = float(d.get("bank", 0.0))
	max_g = float(d.get("max_g", 0.0))
	sensed_dv = PackedFloat64Array(d.get("sensed_dv", [0, 0, 0]))
	update_mass()
	publish_state()

## A vehicle flying free of the CSM: the LM after undocking. Dynamics owns
## it as it owns the CSM: its trajectory, attitude and mass are truth,
## stepped with the CSM's step on the SimClock, under the forces and
## torques of its own systems (the LM's engines and RCS). It publishes the
## channels the CSM publishes as dyn.*, under its own prefix (lm.dyn.r_m,
## lm.dyn.att_q; docs/ROADMAP.md, milestone 3).
class_name Vehicle
extends RefCounted

var id: String = ""
## Prefix of the vehicle's Bus channels: "lm." for lm.dyn.r_m.
var prefix: String = ""
var config: String = ""
var mass: float = 0.0
var traj: Trajectory = Trajectory.new()
var attitude: Attitude = Attitude.new()
## The last step's non-gravitational ΔV, inertial m/s (what its IMU's
## accelerometers sense).
var dv_step: Vector3 = Vector3.ZERO
## Nothing acted on the vehicle in the last step.
var coasting: bool = true
## On the surface: the LM sits on its gear and turns with the Moon.
var landed: bool = false
## Where it sits, and how it is turned, in the Moon-fixed frame.
var landed_pos: Vector3 = Vector3.ZERO
var landed_q: Quaternion = Quaternion.IDENTITY
## Its touchdown: {"get_s", "vertical_mps" (down), "horizontal_mps",
## "lat_deg", "lon_deg", "hard"}; empty until it lands.
var touchdown: Dictionary = {}
## Landed, how long its engine has pushed it up harder than its weight, s.
var lift_s: float = 0.0


func _init(p_id: String = "lm", p_config: String = "lm", p_mass: float = 0.0) -> void:
	id = p_id
	prefix = p_id + "."
	config = p_config
	mass = p_mass if p_mass > 0.0 else SpacecraftData.lm_mass()
	attitude.inertia = SpacecraftData.inertia(config, mass)


## Step [param dt] seconds under [param force_body] (N) and
## [param torque_body] (N·m), body axes.
func step(dt: float, force_body: Vector3 = Vector3.ZERO, torque_body: Vector3 = Vector3.ZERO) -> void:
	var a := attitude.eci_from_body() * force_body / mass
	var ext := PackedFloat64Array([a.x, a.y, a.z]) if force_body != Vector3.ZERO else PackedFloat64Array()
	traj.step(dt, ext)
	attitude.step(dt, torque_body)
	dv_step = a * dt if force_body != Vector3.ZERO else Vector3.ZERO
	coasting = force_body == Vector3.ZERO and torque_body == Vector3.ZERO


## Sit on the surface at GET [param t], where the Moon has turned the
## spot, turning with it.
func hold_on_surface(t: float) -> void:
	var mf := Bodies.moon_fixed(t)
	var r := mf * landed_pos
	traj.set_state("moon", t, r, Bodies.moon_omega().cross(r))
	attitude.q = (Quaternion(mf) * landed_q).normalized()
	attitude.omega = Basis(attitude.q).inverse() * Bodies.moon_omega()
	dv_step = Vector3.ZERO
	coasting = true


## Settle on the surface now, at [param radius] from the Moon's centre
## straight below where it is, as it is turned.
func land(radius: float) -> void:
	var mf := Bodies.moon_fixed(traj.t)
	landed_pos = mf.transposed() * (traj.pos().normalized() * radius)
	landed_q = (Quaternion(mf.transposed()) * attitude.q).normalized()
	landed = true
	hold_on_surface(traj.t)


## Body rates in inertial axes, rad/s.
func omega_eci() -> Vector3:
	return attitude.eci_from_body() * attitude.omega


func publish() -> void:
	publish_motion(prefix, traj, attitude, mass, config)
	Bus.set_value(prefix + "dyn.dv_step", [dv_step.x, dv_step.y, dv_step.z])
	Bus.set_value(prefix + "dyn.landed", landed)


## Publish the motion channels every vehicle has, under [param p]:
## p + "dyn.primary", "dyn.r_m", "dyn.att_q" and the rest.
static func publish_motion(p: String, tr: Trajectory, att: Attitude, m: float, cfg: String) -> void:
	var c := tr.conic()
	var rb := Bodies.radius_of(tr.primary)
	Bus.set_value(p + "dyn.primary", tr.primary)
	Bus.set_value(p + "dyn.config", cfg)
	Bus.set_value(p + "dyn.r_m", [tr.s[0], tr.s[1], tr.s[2]])
	Bus.set_value(p + "dyn.v_mps", [tr.s[3], tr.s[4], tr.s[5]])
	Bus.set_value(p + "dyn.alt_m", tr.altitude())
	Bus.set_value(p + "dyn.speed_mps", tr.speed())
	Bus.set_value(p + "dyn.alt_rate_mps", tr.radial_rate())
	Bus.set_value(p + "dyn.peri_alt_m", float(c["rp"]) - rb)
	Bus.set_value(p + "dyn.apo_alt_m", float(c["ra"]) - rb if c["ra"] != INF else INF)
	Bus.set_value(p + "dyn.mass_kg", m)
	Bus.set_value(p + "dyn.att_q", att.q)
	Bus.set_value(p + "dyn.omega", att.omega)


func snapshot() -> Dictionary:
	return {
		"id": id, "config": config, "mass": mass,
		"primary": traj.primary, "t": traj.t, "s": Array(traj.s),
		"q": [attitude.q.x, attitude.q.y, attitude.q.z, attitude.q.w],
		"omega": [attitude.omega.x, attitude.omega.y, attitude.omega.z],
		"landed": landed, "landed_pos": [landed_pos.x, landed_pos.y, landed_pos.z],
		"landed_q": [landed_q.x, landed_q.y, landed_q.z, landed_q.w], "touchdown": touchdown, "lift_s": lift_s,
	}


static func from_snapshot(d: Dictionary) -> Vehicle:
	var v := Vehicle.new(str(d["id"]), str(d["config"]), float(d["mass"]))
	v.traj.set_state_d(str(d["primary"]), float(d["t"]), PackedFloat64Array(d["s"]))
	var q: Array = d["q"]
	v.attitude.q = Quaternion(q[0], q[1], q[2], q[3])
	var w: Array = d["omega"]
	v.attitude.omega = Vector3(w[0], w[1], w[2])
	v.landed = bool(d.get("landed", false))
	var lp: Array = d.get("landed_pos", [0.0, 0.0, 0.0])
	v.landed_pos = Vector3(lp[0], lp[1], lp[2])
	var lq: Array = d.get("landed_q", [0.0, 0.0, 0.0, 1.0])
	v.landed_q = Quaternion(lq[0], lq[1], lq[2], lq[3])
	v.touchdown = d.get("touchdown", {})
	v.lift_s = float(d.get("lift_s", 0.0))
	return v

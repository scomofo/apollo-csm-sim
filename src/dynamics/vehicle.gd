## A vehicle flying free of the CSM: in slice 3a, the LM after undocking.
## Dynamics owns it as it owns the CSM: its trajectory, attitude and mass
## are truth, stepped with the CSM's step on the SimClock. It publishes the
## channels the CSM publishes as dyn.*, under its own prefix (lm.dyn.r_m,
## lm.dyn.att_q; docs/ROADMAP.md, milestone 3).
##
## The LM has no systems yet [simplified: until slice 3b gives it its RCS,
## engines and DAP, it coasts and holds the attitude it undocked in].
class_name Vehicle
extends RefCounted

var id: String = ""
## Prefix of the vehicle's Bus channels: "lm." for lm.dyn.r_m.
var prefix: String = ""
var config: String = ""
var mass: float = 0.0
var traj: Trajectory = Trajectory.new()
var attitude: Attitude = Attitude.new()


func _init(p_id: String = "lm", p_config: String = "lm", p_mass: float = 0.0) -> void:
	id = p_id
	prefix = p_id + "."
	config = p_config
	mass = p_mass if p_mass > 0.0 else SpacecraftData.lm_mass()
	attitude.inertia = SpacecraftData.inertia(config, mass)


## Coast [param dt] seconds: nothing acts on the vehicle.
func step(dt: float) -> void:
	traj.step(dt)
	attitude.step(dt)


## Body rates in inertial axes, rad/s.
func omega_eci() -> Vector3:
	return attitude.eci_from_body() * attitude.omega


func publish() -> void:
	publish_motion(prefix, traj, attitude, mass, config)


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
	}


static func from_snapshot(d: Dictionary) -> Vehicle:
	var v := Vehicle.new(str(d["id"]), str(d["config"]), float(d["mass"]))
	v.traj.set_state_d(str(d["primary"]), float(d["t"]), PackedFloat64Array(d["s"]))
	var q: Array = d["q"]
	v.attitude.q = Quaternion(q[0], q[1], q[2], q[3])
	var w: Array = d["omega"]
	v.attitude.omega = Vector3(w[0], w[1], w[2])
	return v

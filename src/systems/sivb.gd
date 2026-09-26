## S-IVB stage and Instrument Unit, from parking orbit through translunar
## injection (TLI).
##
## The IU flies the stack (Dynamics slaves the attitude while configuration
## is "stack"). For TLI it ignites the J-2 at the TIG it was given
## (arm_tli), thrusts along the Earth-relative velocity turned by a yaw out
## of the orbit plane, and cuts off when the Earth-relative specific orbital
## energy (energy_of()) reaches the target. The yaw turns the trajectory's plane to pass
## the Moon where the RTCC aims (Rtcc.plan_tli()). The RTCC uses the very
## same law (simulate_burn) when it computes the TIG and the yaw, so the
## flown burn reproduces the planned one
## [simplified: the real IU used iterative guidance; the energy-cutoff law
## at a fixed yaw is its cheap stand-in].
##
## Writes: sivb.thrust_n, sivb.dir, sivb.prop_kg, sivb.burning, sivb.state,
##         seq.next_event_get_s (the armed TIG)
class_name Sivb
extends Node

var prop_kg: float = -1.0
var tig: float = -1.0
var target_energy: float = 0.0
## Out of the orbit plane, toward its normal (r x v), rad.
var yaw: float = 0.0
## "idle" | "armed" | "burning" | "done"
var state: String = "idle"


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("sivb")["propellant_kg"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish(0.0, Vector3.RIGHT)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func arm_tli(p_tig: float, p_energy: float, p_yaw: float = 0.0) -> void:
	tig = p_tig
	target_energy = p_energy
	yaw = p_yaw
	state = "armed"
	Bus.set_value("seq.next_event_get_s", tig)


## The specific orbital energy about the Earth, J/kg, counting the oblate
## Earth's potential where the propagator does: the energy the stack
## carries on out to the Moon [estimated: the flown C3 read so brings the
## Moon at the flown 73 hours after TLI; read as a two-body energy at the
## cutoff, some 28 kJ/kg less once away from the Earth, 1.6 hours late].
static func energy_of(st: PackedFloat64Array) -> float:
	var v2 := st[3] * st[3] + st[4] * st[4] + st[5] * st[5]
	var r := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	return v2 / 2.0 - Bodies.MU_EARTH / r + Bodies.zonal_energy(st[0], st[1], st[2])


## The thrust direction as an inertial unit vector: prograde (the
## Earth-relative velocity) turned [param p_yaw] rad toward the orbit's
## normal (r x v).
static func guidance_dir(st: PackedFloat64Array, p_yaw: float = 0.0) -> Vector3:
	var v := Vector3(st[3], st[4], st[5]).normalized()
	if p_yaw == 0.0:
		return v
	var n := Vector3(st[0], st[1], st[2]).cross(Vector3(st[3], st[4], st[5])).normalized()
	return (v * cos(p_yaw) + n * sin(p_yaw)).normalized()


func tick(dt: float) -> void:
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	if cfg != "stack":
		_publish(0.0, Vector3.RIGHT)
		return
	var st := _state()
	var now := float(Bus.get_value("time.get_s", 0.0))
	if state == "armed" and now >= tig - 1e-6:
		state = "burning"
		Bus.set_value("seq.next_event_get_s", -1.0)
	if state == "burning":
		if energy_of(st) >= target_energy or prop_kg <= 0.0:
			state = "done"
			_publish(0.0, guidance_dir(st, yaw))
			return
		var d := SpacecraftData.section("sivb")
		var f := float(d["thrust_n"])
		prop_kg = maxf(0.0, prop_kg - f / (float(d["isp_s"]) * Units.G0) * dt)
		_publish(f, guidance_dir(st, yaw))
		return
	_publish(0.0, guidance_dir(st, yaw) if st.size() == 6 else Vector3.RIGHT)


func _state() -> PackedFloat64Array:
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH, 0.0, 0.0])
	var v: Array = Bus.get_value("dyn.v_mps", [0.0, 7800.0, 0.0])
	return PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]])


func _publish(thrust: float, dir: Vector3) -> void:
	Bus.set_value("sivb.thrust_n", thrust)
	Bus.set_value("sivb.dir", [dir.x, dir.y, dir.z])
	Bus.set_value("sivb.prop_kg", prop_kg)
	Bus.set_value("sivb.burning", thrust > 0.0)
	Bus.set_value("sivb.state", state)


## Fly the TLI law on [param traj] (Earth primary) from its current time
## with the given stack mass and [param p_yaw]: the same direction law and
## energy cutoff as tick(), with the last step shortened to land on the
## cutoff energy. Returns remaining S-IVB propellant.
static func simulate_burn(traj: Trajectory, stack_mass: float, sivb_prop: float, energy: float, p_yaw: float = 0.0,
		dt: float = 1.0) -> float:
	var d := SpacecraftData.section("sivb")
	var f := float(d["thrust_n"])
	var mdot := f / (float(d["isp_s"]) * Units.G0)
	var m := stack_mass
	var p := sivb_prop
	while energy_of(traj.s) < energy - 1e-3 and p > 0.0:
		var u := guidance_dir(traj.s, p_yaw)
		var acc := f / m
		# dE/dt = v·a, the thrust's part along v; shorten the last step onto
		# the target.
		var h := minf(dt, maxf((energy - energy_of(traj.s)) / (traj.speed() * acc * cos(p_yaw)), 1e-3))
		var a := u * acc
		traj.step(h, PackedFloat64Array([a.x, a.y, a.z]))
		m -= mdot * h
		p -= mdot * h
	return p


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "tig": tig, "energy": target_energy, "yaw": yaw, "state": state}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	tig = float(d["tig"])
	target_energy = float(d["energy"])
	yaw = float(d.get("yaw", 0.0))
	state = str(d["state"])
	Bus.set_value("seq.next_event_get_s", tig if state == "armed" else -1.0)

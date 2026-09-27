## S-IVB stage and Instrument Unit, from parking orbit through translunar
## injection (TLI).
##
## The IU flies the stack (Dynamics slaves the attitude while configuration
## is "stack"). For TLI it ignites the J-2 at the TIG it was given
## (arm_tli) and steers by its iterative guidance mode (igm()) onto the
## target conic the RTCC planned (Rtcc.plan_tli()): its energy,
## eccentricity, plane and perigee [published: Saturn V Launch Vehicle
## Guidance Equations, SA-504 (Boeing D5-15706-4, 1967), sections 4.1.3 to
## 4.1.10 and Table 4-IV]. It cuts off in the step where the Earth-relative
## specific orbital energy (energy_of(), half the C3) reaches the
## target's, as the IU's high-speed cutoff logic did on the energy
## [published: ibid., 4.1.7; simplified: the J-2 stops at once, and the
## target is the energy its thrust decay left the flown stack on]. The
## RTCC flies the very same law (simulate_burn) when it plans, so the
## flown burn reproduces the planned one.
##
## Writes: sivb.thrust_n, sivb.dir, sivb.prop_kg, sivb.burning, sivb.state,
##         seq.next_event_get_s (the armed TIG)
class_name Sivb
extends Node

## How often the IGM works out the steering, s; the thrust holds between
## [simplified: the LVDC's major loop took some 1.7 s, its minor loop
## steering between].
const CYCLE_S := 1.0
## The time to go under which the IGM steers for the terminal velocity
## alone, its K terms for the terminal position set to zero [published:
## the AS-506 flight evaluation report, MPR-SAT-FE-69-9, Table 10-4:
## terminal guidance from 28.6 s before the second cutoff].
const TERMINAL_S := 28.6
## The time to go under which the steering is frozen until cutoff, where
## the velocity to be gained runs out and its direction with it
## [estimated: AS-506 froze it 1.2 s before cutoff, ibid.; at a cycle of a
## second the IGM's last passes steer on a few m/s].
const FREEZE_S := 4.0
## How long before ignition the IU turns the stack to the IGM's steering,
## s [simplified: the attitude it would ignite at, worked out as for an
## ignition now].
const ALIGN_S := 60.0

var prop_kg: float = -1.0
var tig: float = -1.0
## The target conic: {"energy" (J/kg, as energy_of()), "e", "n" (the
## plane's unit normal, along r x v), "pe" (the perigee's unit vector)}.
var target: Dictionary = {}
## "idle" | "armed" | "burning" | "done"
var state: String = "idle"
## The IGM's time to go at its last pass, when that was (GET, s), and how
## many passes the burn has had.
var t_go: float = 0.0
var guided_at: float = -1.0
var passes: int = 0
## The thrust direction the IGM last commanded, inertial.
var dir: Vector3 = Vector3.RIGHT


func _ready() -> void:
	if prop_kg < 0.0:
		prop_kg = float(SpacecraftData.section("sivb")["propellant_kg"])
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish(0.0, Vector3.RIGHT)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func arm_tli(p_tig: float, p_target: Dictionary) -> void:
	tig = p_tig
	target = p_target.duplicate()
	state = "armed"
	guided_at = -1.0
	passes = 0
	Bus.set_value("seq.next_event_get_s", tig)


## The specific orbital energy about the Earth, J/kg, as the C3 the IU cut
## off on counts it, halved: the two-body V²/2 - μ/R at the stack
## [published: the flight evaluation report's C3 is V² - 2μ/R,
## MPR-SAT-FE-69-9, Table 4-2]. The oblate Earth's potential is left out,
## as it was of C3; the energy the stack carries on out to the Moon counts
## it (Bodies.zonal_energy()), and comes to some 27 kJ/kg less.
static func energy_of(st: PackedFloat64Array) -> float:
	var v2 := st[3] * st[3] + st[4] * st[4] + st[5] * st[5]
	var r := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	return v2 / 2.0 - Bodies.MU_EARTH / r


## A first time to go for a burn from [param st] (Earth-relative) onto
## [param tgt]'s energy on a stack of [param mass] kg: the rocket equation
## on the speed the energy asks for where the stack is.
static func first_t_go(st: PackedFloat64Array, mass: float, tgt: Dictionary) -> float:
	var d := SpacecraftData.section("sivb")
	var ve := float(d["isp_s"]) * Units.G0
	var tau := ve * mass / float(d["thrust_n"])
	var r := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	var v := sqrt(st[3] * st[3] + st[4] * st[4] + st[5] * st[5])
	var dv := sqrt(maxf(2.0 * (float(tgt["energy"]) + Bodies.MU_EARTH / r), 0.0)) - v
	return tau * (1.0 - exp(-maxf(dv, 1.0) / ve))


## One pass of the iterative guidance mode (IGM) for the out-of-orbit burn
## [published: D5-15706-4, Table 4-IV, for one stage]. From the state
## [param st] (Earth-relative, inertial), the stack's [param mass] and the
## time to go [param tgo] carried on from the last pass: where the burn
## ends on [param tgt]'s conic, and the steering there. Returns {"dir"
## (inertial unit vector), "t_go"}.
##
## Twice a pass: the range angle to go puts the terminal radius in the
## target plane, its true anomaly on the conic gives the terminal radius,
## speed and flight path angle, and the velocity to be gained (less the
## gravity on the way, the mean of here and there) corrects the time to go
## by the rocket equation. The steering is along that velocity to be
## gained (chi tilde), turned by the K terms, a linear-tangent change that
## leaves the velocity it gains alone, to bring the terminal radius in the
## plane (yaw) and at the conic's distance from the terminal velocity's
## line (pitch). The frame is the rotated terminal one of the out-of-orbit
## burn: zeta along the terminal velocity, xi across it in the plane, eta
## along the plane's normal.
static func igm(st: PackedFloat64Array, mass: float, tgt: Dictionary, tgo: float) -> Dictionary:
	var d := SpacecraftData.section("sivb")
	var ve := float(d["isp_s"]) * Units.G0
	var tau := ve * mass / float(d["thrust_n"])
	var mu := Bodies.MU_EARTH
	var r := Vector3(st[0], st[1], st[2])
	var v := Vector3(st[3], st[4], st[5])
	var n := _vec(tgt["n"])
	var pe := _vec(tgt["pe"])
	var e := float(tgt["e"])
	var energy := float(tgt["energy"])
	var p := mu * (1.0 - e * e) / (-2.0 * energy)
	var t := clampf(tgo, 1.0, 0.95 * tau)
	var rn := r.length()
	var up := (r - n * r.dot(n)).normalized()
	var down := n.cross(up)
	var xi := up
	var eta := n
	var zeta := down
	var g := Vector3.ZERO
	var rt := rn
	var gam := 0.0
	var dvg := Vector3.ZERO
	for _pass in 2:
		var l := ve * log(tau / (tau - t))
		var s := l * t - (l * tau - ve * t)
		# The range angle to go: the arc the burn still covers.
		var ang := (v.dot(down) * t + s) / rn
		var rt_hat := up * cos(ang) + down * sin(ang)
		var f := atan2(pe.cross(rt_hat).dot(n), pe.dot(rt_hat))
		rt = p / (1.0 + e * cos(f))
		gam = atan2(e * sin(f), 1.0 + e * cos(f))
		var vt := sqrt(maxf(2.0 * (energy + mu / rt), 0.0))
		var h_hat := n.cross(rt_hat)
		zeta = h_hat * cos(gam) + rt_hat * sin(gam)
		xi = rt_hat * cos(gam) - h_hat * sin(gam)
		g = (-r * (mu / (rn * rn * rn)) - rt_hat * (mu / (rt * rt))) * 0.5
		dvg = zeta * vt - v - g * t
		# The rocket equation's time for the speed still to gain.
		t = clampf(t + (dvg.length() - l) * (tau - t) / ve, 1.0, 0.95 * tau)
	var dxi := dvg.dot(xi)
	var deta := dvg.dot(eta)
	var dzeta := dvg.dot(zeta)
	var chi_y := atan2(deta, sqrt(dxi * dxi + dzeta * dzeta))
	var chi_p := atan2(dxi, dzeta)
	if t > TERMINAL_S:
		# The stage integrals: L the speed the burn gains, J its first
		# moment in time, S the distance its thrust covers, Q that
		# distance's moment.
		var l := ve * log(tau / (tau - t))
		var j := l * tau - ve * t
		var s := l * t - j
		var q := s * tau - ve * t * t / 2.0
		var dd := q - s * j / l
		# Yaw: the terminal radius into the target plane.
		var eta_off := r.dot(eta) + v.dot(eta) * t + g.dot(eta) * t * t / 2.0 + s * sin(chi_y)
		var k4 := -eta_off / (cos(chi_y) * dd)
		chi_y -= k4 * j / l
		# Pitch: the terminal radius at the conic's distance from the
		# terminal velocity's line, R cos(gamma).
		var xi_off := r.dot(xi) + v.dot(xi) * t + g.dot(xi) * t * t / 2.0 + s * cos(chi_y) * sin(chi_p)
		var k2 := (rt * cos(gam) - xi_off) / (cos(chi_p) * cos(chi_y) * dd)
		chi_p -= k2 * j / l
	var u := xi * (sin(chi_p) * cos(chi_y)) + eta * sin(chi_y) + zeta * (cos(chi_p) * cos(chi_y))
	return {"dir": u.normalized(), "t_go": t}


## [param a] (an Array or a Vector3) as a Vector3.
static func _vec(a: Variant) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func tick(dt: float) -> void:
	var cfg := str(Bus.get_value("dyn.config", "stack"))
	if cfg != "stack":
		_publish(0.0, Vector3.RIGHT)
		return
	var st := _state()
	var now := float(Bus.get_value("time.get_s", 0.0))
	if state == "armed" and now >= tig - 1e-6:
		state = "burning"
		passes = 0
		Bus.set_value("seq.next_event_get_s", -1.0)
	if state == "burning":
		var energy := energy_of(st)
		if energy >= float(target["energy"]) or prop_kg <= 0.0:
			state = "done"
			_publish(0.0, dir)
			return
		_guide(st, now)
		var d := SpacecraftData.section("sivb")
		var f := float(d["thrust_n"])
		# The high-speed cutoff: the part of this step that brings the
		# energy to the target, the rest at zero thrust (the J-2 at full
		# thrust adds some 3.6 kJ/kg a step at the end), and the J-2 off
		# after it (the two-body energy then sags as the stack climbs out
		# of the oblate Earth's pull, some 15 J/kg a second).
		var dv := f / maxf(float(Bus.get_value("dyn.mass_kg", 0.0)), 1.0) * dt
		var frac := _cutoff_fraction(st, energy, float(target["energy"]), dir * dv)
		prop_kg = maxf(0.0, prop_kg - f / (float(d["isp_s"]) * Units.G0) * dt * frac)
		if frac < 1.0:
			state = "done"
		_publish(f * frac, dir)
		return
	if state == "armed" and now >= tig - ALIGN_S:
		if guided_at < 0.0 or now >= guided_at + CYCLE_S - 1e-6:
			var mass := float(Bus.get_value("dyn.mass_kg", 0.0))
			dir = igm(st, mass, target, first_t_go(st, mass, target))["dir"]
			guided_at = now
		_publish(0.0, dir)
		return
	_publish(0.0, dir if state == "done" else _prograde(st))


## The IGM's pass when one is due: at ignition and every CYCLE_S after it,
## until the steering freezes near cutoff.
func _guide(st: PackedFloat64Array, now: float) -> void:
	if passes > 0 and now < tig + float(passes) * CYCLE_S - 1e-6:
		return
	var mass := float(Bus.get_value("dyn.mass_kg", 0.0))
	if passes == 0:
		t_go = first_t_go(st, mass, target)
	else:
		t_go -= now - guided_at
	guided_at = now
	passes += 1
	if t_go < FREEZE_S and passes > 1:
		return
	var g := igm(st, mass, target, t_go)
	dir = g["dir"]
	t_go = g["t_go"]


## The fraction of a step's velocity change [param dv] that takes the
## energy from [param energy] to [param target] at the state [param st]:
## 1 while the whole step falls short. The energy grows by v·dv + dv²/2.
static func _cutoff_fraction(st: PackedFloat64Array, energy: float, target: float, dv: Vector3) -> float:
	var v := Vector3(st[3], st[4], st[5])
	var need := target - energy
	var b := v.dot(dv)
	var a := dv.length_squared() / 2.0
	if b + a <= need or b <= 0.0:
		return 1.0
	return clampf((-b + sqrt(b * b + 4.0 * a * need)) / (2.0 * a), 0.0, 1.0)


static func _prograde(st: PackedFloat64Array) -> Vector3:
	if st.size() != 6:
		return Vector3.RIGHT
	return Vector3(st[3], st[4], st[5]).normalized()


func _state() -> PackedFloat64Array:
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH, 0.0, 0.0])
	var v: Array = Bus.get_value("dyn.v_mps", [0.0, 7800.0, 0.0])
	return PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]])


func _publish(thrust: float, u: Vector3) -> void:
	Bus.set_value("sivb.thrust_n", thrust)
	Bus.set_value("sivb.dir", [u.x, u.y, u.z])
	Bus.set_value("sivb.prop_kg", prop_kg)
	Bus.set_value("sivb.burning", thrust > 0.0)
	Bus.set_value("sivb.state", state)


## Fly the TLI on [param traj] (Earth primary) from its current time, the
## ignition, with the given stack mass and [param tgt]: the IGM's pass at
## ignition and every CYCLE_S after, as tick() makes them, and the energy
## cutoff, the last step shortened to land on it. Returns the remaining
## S-IVB propellant; each pass's GET and time to go go on [param trace],
## an Array, when one is given.
static func simulate_burn(traj: Trajectory, stack_mass: float, sivb_prop: float, tgt: Dictionary,
		trace: Variant = null) -> float:
	var d := SpacecraftData.section("sivb")
	var f := float(d["thrust_n"])
	var mdot := f / (float(d["isp_s"]) * Units.G0)
	var energy := float(tgt["energy"])
	var m := stack_mass
	var p := sivb_prop
	var tgo := first_t_go(traj.s, m, tgt)
	var u := Vector3.ZERO
	while energy_of(traj.s) < energy - 1e-3 and p > 0.0:
		if u == Vector3.ZERO or tgo >= FREEZE_S:
			var g := igm(traj.s, m, tgt, tgo)
			u = g["dir"]
			tgo = g["t_go"]
			if trace != null:
				(trace as Array).append([traj.t, tgo])
		var acc := f / m
		var a := u * acc
		var ext := PackedFloat64Array([a.x, a.y, a.z])
		# dE/dt = v·a, the thrust's part along v; the last step is shortened
		# onto the target, and a probe of it scales it onto the energy.
		var e0 := energy_of(traj.s)
		var h := minf(CYCLE_S, maxf((energy - e0) / maxf(traj.vel().dot(u) * acc, 1e-3), 1e-6))
		if h < CYCLE_S:
			var probe := traj.clone()
			probe.step(h, ext)
			var gained := energy_of(probe.s) - e0
			if gained > 0.0:
				h = maxf(h * (energy - e0) / gained, 1e-6)
		traj.step(h, ext)
		m -= mdot * h
		p -= mdot * h
		tgo -= h
	return p


func snapshot() -> Dictionary:
	return {"prop_kg": prop_kg, "tig": tig, "target": _target_snapshot(), "state": state, "t_go": t_go,
		"guided_at": guided_at, "passes": passes, "dir": [dir.x, dir.y, dir.z]}


func _target_snapshot() -> Dictionary:
	if target.is_empty():
		return {}
	var n := _vec(target["n"])
	var pe := _vec(target["pe"])
	return {"energy": float(target["energy"]), "e": float(target["e"]), "n": [n.x, n.y, n.z], "pe": [pe.x, pe.y, pe.z]}


func restore(d: Dictionary) -> void:
	prop_kg = float(d["prop_kg"])
	tig = float(d["tig"])
	target = d["target"].duplicate() if d.has("target") else {}
	state = str(d["state"])
	t_go = float(d.get("t_go", 0.0))
	guided_at = float(d.get("guided_at", -1.0))
	passes = int(d.get("passes", 0))
	var u: Array = d.get("dir", [1.0, 0.0, 0.0])
	dir = Vector3(float(u[0]), float(u[1]), float(u[2]))
	Bus.set_value("seq.next_event_get_s", tig if state == "armed" else -1.0)
	# The Bus carries the restored stage, not the flight it replaced: the
	# sequencer reads the state before the next tick publishes it.
	_publish(0.0, dir)

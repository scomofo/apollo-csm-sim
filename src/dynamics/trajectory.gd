## Spacecraft translational state in the Earth-Moon system. See README.md, "Fidelity".
##
## The state is kept relative to the current primary body ("earth" or
## "moon") in a non-rotating frame aligned with ECI, in double precision
## (PackedFloat64Array, not float32 Vector3). The equations of motion are
## always three-body: central gravity of the primary plus the third-body
## perturbation of the other body (direct and indirect terms). With
## Bodies.perturbed the Sun pulls as a third body too, and about the Earth
## its zonal harmonics (J2 to J4) act [simplified: not about the Moon,
## where they come to under 1e-9 m/s²]. Crossing the lunar sphere of
## influence re-bases the state onto the other body, which keeps precision
## near the Moon without changing the physics.
class_name Trajectory
extends RefCounted

var primary: String = "earth"
## GET of the state, s.
var t: float = 0.0
## [x, y, z, vx, vy, vz] relative to the primary, m and m/s.
var s: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
## Number of primary-body switches since construction (diagnostics).
var soi_switches: int = 0


func clone() -> Trajectory:
	var c := Trajectory.new()
	c.primary = primary
	c.t = t
	c.s = s.duplicate()
	return c


func set_state(p_primary: String, p_t: float, pos: Vector3, vel: Vector3) -> void:
	primary = p_primary
	t = p_t
	s = PackedFloat64Array([pos.x, pos.y, pos.z, vel.x, vel.y, vel.z])


func set_state_d(p_primary: String, p_t: float, state: PackedFloat64Array) -> void:
	primary = p_primary
	t = p_t
	s = state.duplicate()


# --- state accessors -----------------------------------------------------

func pos() -> Vector3:
	return Vector3(s[0], s[1], s[2])


func vel() -> Vector3:
	return Vector3(s[3], s[4], s[5])


func radius() -> float:
	return sqrt(s[0] * s[0] + s[1] * s[1] + s[2] * s[2])


func speed() -> float:
	return sqrt(s[3] * s[3] + s[4] * s[4] + s[5] * s[5])


func altitude() -> float:
	return radius() - Bodies.radius_of(primary)


## Radial velocity (altitude rate), m/s.
func radial_rate() -> float:
	return (s[0] * s[3] + s[1] * s[4] + s[2] * s[5]) / radius()


## State relative to Earth, doubles.
func earth_state() -> PackedFloat64Array:
	if primary == "earth":
		return s.duplicate()
	var m := Bodies.moon_state(t)
	var out := PackedFloat64Array()
	out.resize(6)
	for i in 6:
		out[i] = s[i] + m[i]
	return out


## State relative to the Moon, doubles.
func moon_state_rel() -> PackedFloat64Array:
	if primary == "moon":
		return s.duplicate()
	var m := Bodies.moon_state(t)
	var out := PackedFloat64Array()
	out.resize(6)
	for i in 6:
		out[i] = s[i] - m[i]
	return out


## Conic (two-body about the primary) summary: energy, a, e, periapsis and
## apoapsis radius (apoapsis INF when unbound), period (INF when unbound).
func conic() -> Dictionary:
	return conic_of(s, Bodies.mu_of(primary))


static func conic_of(st: PackedFloat64Array, mu: float) -> Dictionary:
	var r := Vector3(st[0], st[1], st[2])
	var rn := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	var v2 := st[3] * st[3] + st[4] * st[4] + st[5] * st[5]
	var hx := st[1] * st[5] - st[2] * st[4]
	var hy := st[2] * st[3] - st[0] * st[5]
	var hz := st[0] * st[4] - st[1] * st[3]
	var h2 := hx * hx + hy * hy + hz * hz
	var energy := v2 / 2.0 - mu / rn
	var p := h2 / mu
	var e := sqrt(maxf(0.0, 1.0 + 2.0 * energy * h2 / (mu * mu)))
	var rp := p / (1.0 + e)
	var ra := INF
	var a := INF
	var period := INF
	if energy < 0.0:
		a = -mu / (2.0 * energy)
		ra = a * (1.0 + e)
		period = TAU * sqrt(a * a * a / mu)
	elif energy > 0.0:
		a = -mu / (2.0 * energy)
	var hn := sqrt(h2)
	var inc := acos(clampf(hz / hn, -1.0, 1.0)) if hn > 0.0 else 0.0
	return {"energy": energy, "a": a, "e": e, "rp": rp, "ra": ra, "period": period,
		"h": Vector3(hx, hy, hz), "i": inc, "r": r}


## Recommended coast step: a small fraction of the local dynamical time
## r/v, bounded. RK4 at this step stays well under a metre per LEO orbit.
func coast_dt() -> float:
	return clampf(0.005 * radius() / maxf(speed(), 1.0), 0.02, 60.0)


# --- equations of motion ---------------------------------------------------

## Acceleration at relative position (x, y, z) and time [param tt], plus a
## constant external acceleration [param ext] (inertial m/s², may be empty),
## and the Sun's pull from [param sun], its position relative to the
## primary (empty for none).
func _accel(tt: float, x: float, y: float, z: float, ext: PackedFloat64Array, sun: PackedFloat64Array) -> PackedFloat64Array:
	var mu_p: float
	var mu_q: float
	var qx: float
	var qy: float
	var qz: float
	var m := Bodies.moon_position(tt)
	if primary == "earth":
		mu_p = Bodies.MU_EARTH
		mu_q = Bodies.MU_MOON
		qx = m[0]; qy = m[1]; qz = m[2]
	else:
		mu_p = Bodies.MU_MOON
		mu_q = Bodies.MU_EARTH
		qx = -m[0]; qy = -m[1]; qz = -m[2]
	var r2 := x * x + y * y + z * z
	var r3 := r2 * sqrt(r2)
	var ax := -mu_p * x / r3
	var ay := -mu_p * y / r3
	var az := -mu_p * z / r3
	# Third body: direct term toward the body minus the indirect term (the
	# acceleration of the primary itself toward the third body).
	var dx := qx - x
	var dy := qy - y
	var dz := qz - z
	var d2 := dx * dx + dy * dy + dz * dz
	var d3 := d2 * sqrt(d2)
	var q2 := qx * qx + qy * qy + qz * qz
	var q3 := q2 * sqrt(q2)
	ax += mu_q * (dx / d3 - qx / q3)
	ay += mu_q * (dy / d3 - qy / q3)
	az += mu_q * (dz / d3 - qz / q3)
	if sun.size() == 3:
		var sx := sun[0] - x
		var sy := sun[1] - y
		var sz := sun[2] - z
		var s2 := sx * sx + sy * sy + sz * sz
		var s3 := s2 * sqrt(s2)
		var p2 := sun[0] * sun[0] + sun[1] * sun[1] + sun[2] * sun[2]
		var p3 := p2 * sqrt(p2)
		ax += Bodies.MU_SUN * (sx / s3 - sun[0] / p3)
		ay += Bodies.MU_SUN * (sy / s3 - sun[1] / p3)
		az += Bodies.MU_SUN * (sz / s3 - sun[2] / p3)
	if Bodies.perturbed and primary == "earth":
		var zon := _zonal(x, y, z, r2)
		ax += zon[0]; ay += zon[1]; az += zon[2]
	if ext.size() == 3:
		ax += ext[0]; ay += ext[1]; az += ext[2]
	return PackedFloat64Array([ax, ay, az])


## The Earth's zonal harmonics' acceleration (J2 to J4) at (x, y, z)
## relative to it, [param r2] its squared radius: for each degree n,
## mu J_n R^n / r^(n+2) [((n+1) P_n(u) + u P_n'(u)) r_hat - P_n'(u) pole],
## u the sine of the latitude.
static func _zonal(x: float, y: float, z: float, r2: float) -> PackedFloat64Array:
	var p := Bodies.earth_pole
	var r := sqrt(r2)
	var u := (x * p[0] + y * p[1] + z * p[2]) / r
	var u2 := u * u
	var q := Bodies.R_EARTH / r
	var q2 := q * q
	var g := Bodies.MU_EARTH / r2
	var j2 := Bodies.EARTH_J2 * q2
	var j3 := Bodies.EARTH_J3 * q2 * q
	var j4 := Bodies.EARTH_J4 * q2 * q2
	var fr := g * (j2 * 1.5 * (5.0 * u2 - 1.0) + j3 * 0.5 * u * (35.0 * u2 - 15.0)
		+ j4 * (315.0 * u2 * u2 - 210.0 * u2 + 15.0) / 8.0) / r
	var fp := g * (j2 * 3.0 * u + j3 * 0.5 * (15.0 * u2 - 3.0) + j4 * 0.5 * u * (35.0 * u2 - 15.0))
	return PackedFloat64Array([fr * x - fp * p[0], fr * y - fp * p[1], fr * z - fp * p[2]])


## One RK4 step of [param dt] seconds. [param ext] is an inertial
## acceleration (thrust, drag) held constant over the step. The Sun, some
## 1e-5 rad on in a minute, is taken where it is at the step's middle.
func step(dt: float, ext: PackedFloat64Array = PackedFloat64Array()) -> void:
	var x := s[0]; var y := s[1]; var z := s[2]
	var vx := s[3]; var vy := s[4]; var vz := s[5]
	var h := dt / 2.0
	var sun := PackedFloat64Array()
	if Bodies.perturbed:
		sun = Bodies.sun_position(t + h)
		if primary == "moon":
			var mp := Bodies.moon_position(t + h)
			sun[0] -= mp[0]; sun[1] -= mp[1]; sun[2] -= mp[2]
	var a1 := _accel(t, x, y, z, ext, sun)
	var a2 := _accel(t + h, x + vx * h, y + vy * h, z + vz * h, ext, sun)
	var v2x := vx + a1[0] * h; var v2y := vy + a1[1] * h; var v2z := vz + a1[2] * h
	var a3 := _accel(t + h, x + v2x * h, y + v2y * h, z + v2z * h, ext, sun)
	var v3x := vx + a2[0] * h; var v3y := vy + a2[1] * h; var v3z := vz + a2[2] * h
	var a4 := _accel(t + dt, x + v3x * dt, y + v3y * dt, z + v3z * dt, ext, sun)
	var v4x := vx + a3[0] * dt; var v4y := vy + a3[1] * dt; var v4z := vz + a3[2] * dt
	var k := dt / 6.0
	s[0] = x + k * (vx + 2.0 * v2x + 2.0 * v3x + v4x)
	s[1] = y + k * (vy + 2.0 * v2y + 2.0 * v3y + v4y)
	s[2] = z + k * (vz + 2.0 * v2z + 2.0 * v3z + v4z)
	s[3] = vx + k * (a1[0] + 2.0 * a2[0] + 2.0 * a3[0] + a4[0])
	s[4] = vy + k * (a1[1] + 2.0 * a2[1] + 2.0 * a3[1] + a4[1])
	s[5] = vz + k * (a1[2] + 2.0 * a2[2] + 2.0 * a3[2] + a4[2])
	t += dt
	_check_soi()


## Re-base the state when the lunar sphere of influence is crossed. A 1 %
## hysteresis keeps a trajectory grazing the boundary from chattering.
func _check_soi() -> void:
	if primary == "earth":
		var mp := Bodies.moon_position(t)
		var dx := s[0] - mp[0]; var dy := s[1] - mp[1]; var dz := s[2] - mp[2]
		if dx * dx + dy * dy + dz * dz < Bodies.MOON_SOI * Bodies.MOON_SOI * 0.99 * 0.99:
			var m := Bodies.moon_state(t)
			for i in 6:
				s[i] -= m[i]
			primary = "moon"
			soi_switches += 1
	else:
		if s[0] * s[0] + s[1] * s[1] + s[2] * s[2] > Bodies.MOON_SOI * Bodies.MOON_SOI * 1.01 * 1.01:
			var m := Bodies.moon_state(t)
			for i in 6:
				s[i] += m[i]
			primary = "earth"
			soi_switches += 1


## Coast (no external force) to GET [param t_end] with adaptive steps no
## longer than [param max_dt]. Lands exactly on t_end.
func coast_to(t_end: float, max_dt: float = 60.0, frac: float = 0.005) -> void:
	while t < t_end - 1e-9:
		var dt := minf(clampf(frac * radius() / maxf(speed(), 1.0), 0.02, max_dt), t_end - t)
		step(dt)


## Coast until [param stop] (Callable(traj) -> bool) returns true or GET
## passes [param t_max]. Returns true when the condition fired.
func coast_until(stop: Callable, t_max: float, max_dt: float = 600.0, frac: float = 0.005) -> bool:
	while t < t_max:
		var dt := minf(clampf(frac * radius() / maxf(speed(), 1.0), 0.02, max_dt), t_max - t)
		step(dt)
		if stop.call(self):
			return true
	return false


## Apollo local-vertical/local-horizontal basis at the current state: +X
## forward (horizontal, along track), +Y right (-orbit normal), +Z down.
## Columns are the LVLH axes expressed in the inertial frame.
static func lvlh_basis(r: Vector3, v: Vector3) -> Basis:
	var z := -r.normalized()
	var y := -r.cross(v).normalized()
	var x := y.cross(z).normalized()
	return Basis(x, y, z)

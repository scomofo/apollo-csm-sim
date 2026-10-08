## Spacecraft translational state in the Earth-Moon system. See README.md, "Fidelity".
##
## The state is kept relative to the current primary body ("earth" or
## "moon") in a non-rotating frame aligned with ECI, in double precision
## (PackedFloat64Array, not float32 Vector3). The equations of motion are
## always three-body: central gravity of the primary plus the third-body
## perturbation of the other body (direct and indirect terms). With
## Bodies.perturbed the Sun pulls as a third body too, and about the Earth
## its zonal harmonics (J2 to J4) act [simplified: not about the Moon,
## where they come to under 1e-9 m/s²]. About the Moon its own gravity
## field acts when one is loaded (MoonGravity), sampled every FIELD_HOLD
## seconds and interpolated between. Crossing the lunar sphere of
## influence re-bases the state onto the other body, which keeps precision
## near the Moon without changing the physics.
##
## A trajectory flies truth's model, or an onboard computer's (model): the
## CMC's and the LGC's programs had the R-2 lunar model for the Moon's
## field, not GRAIL's, and no third bodies below 800 km over the primary,
## the LGC's none at all [simplified: their Earth is truth's, and their
## lunar GM GRAIL's, 5 parts in a million off Colossus's]. The RTCC flies
## truth's [simplified: the ground's flew R-2 too].
class_name Trajectory
extends RefCounted

## The spacing of the Moon's field's samples, s: a fixed grid of GET, the
## field sampled at each interval's middle where the trajectory will be
## then and interpolated between. A 60 nmi orbit comes 10 m from one
## sampled at every stage in a day, its apsides under a metre [estimated:
## tools/gravity/moon_gravity.py --hold], for a fraction of the cost.
const FIELD_HOLD := 30.0

## The change in a step's external acceleration, m/s², for which the
## field's samples ahead of the trajectory are taken again: a burn's
## start or end, or its throttle moved. A quarter of a m/s² held a
## minute leaves a sample 450 m from where the trajectory gets to; a
## DPS burn's 3 m/s², 5 km. Four RCS jets translating the docked stack
## (0.04 m/s²) don't reach it; translating the ascent stage after
## insertion (0.7 m/s²), they do.
const FIELD_EXT_TOL := 0.25

enum Model { TRUTH, CMC, LGC }

## The altitude over the primary below which the CMC's programs leave out
## the third bodies' pulls (RME, RMM: 800 km) [published: Comanche 055].
const CMC_THIRD_BODY_ALT := 800000.0

var primary: String = "earth"
## GET of the state, s.
var t: float = 0.0
## [x, y, z, vx, vy, vz] relative to the primary, m and m/s.
var s: PackedFloat64Array = PackedFloat64Array([0, 0, 0, 0, 0, 0])
## Number of primary-body switches since construction (diagnostics).
var soi_switches: int = 0
## The gravity this trajectory flies: truth's (and the RTCC's), or an
## onboard computer's model of it.
var model: Model = Model.TRUTH
## The field's samples in hand: inertial m/s², for the grid's intervals
## field_k to field_k + 3, twelve floats (none before the first sample).
var field_a: PackedFloat64Array = PackedFloat64Array()
var field_k: int = 0
## The external acceleration (m/s², empty for none) the samples ahead of
## the trajectory were taken with, all within FIELD_EXT_TOL of it.
var field_e: PackedFloat64Array = PackedFloat64Array()


func clone() -> Trajectory:
	var c := Trajectory.new()
	c.primary = primary
	c.t = t
	c.s = s.duplicate()
	c.model = model
	c.field_a = field_a.duplicate()
	c.field_k = field_k
	c.field_e = field_e.duplicate()
	return c


func set_state(p_primary: String, p_t: float, p_pos: Vector3, vel: Vector3) -> void:
	primary = p_primary
	t = p_t
	s = PackedFloat64Array([p_pos.x, p_pos.y, p_pos.z, vel.x, vel.y, vel.z])
	field_a = PackedFloat64Array()


func set_state_d(p_primary: String, p_t: float, state: PackedFloat64Array) -> void:
	primary = p_primary
	t = p_t
	s = state.duplicate()
	field_a = PackedFloat64Array()


## This trajectory as the state vector of the onboard computer whose
## gravity model is [param m]. Returns self.
func as_onboard(m: Model) -> Trajectory:
	model = m
	field_a = PackedFloat64Array()
	return self


## The field's samples in hand, for a checkpoint: {} when none.
func field_snapshot() -> Dictionary:
	if field_a.size() != 12:
		return {}
	return {"k": field_k, "a": Array(field_a), "e": Array(field_e)}


## Restore the field's samples from field_snapshot()'s [param d].
func restore_field(d: Dictionary) -> void:
	if d.is_empty():
		field_a = PackedFloat64Array()
		return
	field_a = PackedFloat64Array(d["a"])
	field_k = int(d["k"])
	field_e = PackedFloat64Array(d.get("e", []))


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
	if model != Model.TRUTH:
		var floor_r := Bodies.radius_of(primary) + CMC_THIRD_BODY_ALT
		if model == Model.LGC or r2 < floor_r * floor_r:
			if Bodies.perturbed and primary == "earth":
				var zon0 := _zonal(x, y, z, r2)
				ax += zon0[0]; ay += zon0[1]; az += zon0[2]
			if ext.size() == 3:
				ax += ext[0]; ay += ext[1]; az += ext[2]
			return PackedFloat64Array([ax, ay, az])
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
	# The Moon's field at each stage's time, with the step's external
	# acceleration.
	var e1 := ext
	var e2 := ext
	var e4 := ext
	if primary == "moon" and MoonGravity.degree >= 2:
		e1 = _plus(ext, _field_at(t, ext))
		e2 = _plus(ext, _field_at(t + h, ext))
		e4 = _plus(ext, _field_at(t + dt, ext))
	var sun := PackedFloat64Array()
	if Bodies.perturbed:
		sun = Bodies.sun_position(t + h)
		if primary == "moon":
			var mp := Bodies.moon_position(t + h)
			sun[0] -= mp[0]; sun[1] -= mp[1]; sun[2] -= mp[2]
	var a1 := _accel(t, x, y, z, e1, sun)
	var a2 := _accel(t + h, x + vx * h, y + vy * h, z + vz * h, e2, sun)
	var v2x := vx + a1[0] * h; var v2y := vy + a1[1] * h; var v2z := vz + a1[2] * h
	var a3 := _accel(t + h, x + v2x * h, y + v2y * h, z + v2z * h, e2, sun)
	var v3x := vx + a2[0] * h; var v3y := vy + a2[1] * h; var v3z := vz + a2[2] * h
	var a4 := _accel(t + dt, x + v3x * dt, y + v3y * dt, z + v3z * dt, e4, sun)
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
			field_a = PackedFloat64Array()
	else:
		if s[0] * s[0] + s[1] * s[1] + s[2] * s[2] > Bodies.MOON_SOI * Bodies.MOON_SOI * 1.01 * 1.01:
			var m := Bodies.moon_state(t)
			for i in 6:
				s[i] += m[i]
			primary = "earth"
			soi_switches += 1
			field_a = PackedFloat64Array()


static func _plus(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	if a.size() != 3:
		return b
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


## The Moon's field's pull (inertial m/s²) at GET [param tau]: a cubic
## through the samples at the middles of the grid's FIELD_HOLD-second
## intervals (Catmull-Rom's, from the two on each side), which makes it a
## smooth function of time whatever the steps, so RK4 flies it alike from
## any step's phase and a flight restored from a checkpoint flies as it
## did. Far from the Moon the degrees that have faded are left out. New
## samples are taken where the step's external acceleration [param ext]
## (a thrust's) carries the trajectory too, and when a burn begins or
## ends the samples ahead are taken again.
func _field_at(tau: float, ext: PackedFloat64Array) -> PackedFloat64Array:
	var u := tau / FIELD_HOLD - 0.5
	var k := int(floorf(u))
	var w := u - float(k)
	_field_samples(k - 1, ext)
	var a := field_a
	var w2 := w * w
	var w3 := w2 * w
	var c0 := -0.5 * w3 + w2 - 0.5 * w
	var c1 := 1.5 * w3 - 2.5 * w2 + 1.0
	var c2 := -1.5 * w3 + 2.0 * w2 + 0.5 * w
	var c3 := 0.5 * w3 - 0.5 * w2
	return PackedFloat64Array([
		c0 * a[0] + c1 * a[3] + c2 * a[6] + c3 * a[9],
		c0 * a[1] + c1 * a[4] + c2 * a[7] + c3 * a[10],
		c0 * a[2] + c1 * a[5] + c2 * a[8] + c3 * a[11]])


## Makes field_a hold the samples for the grid's intervals [param k] to
## k + 3, keeping those it has and taking the others (with [param ext],
## as _field_at()). When [param ext] has moved FIELD_EXT_TOL from the one
## the samples ahead were taken with, a burn has begun or ended since, and
## they're taken again.
func _field_samples(k: int, ext: PackedFloat64Array) -> void:
	if field_a.size() == 12 and absi(k - field_k) <= 1:
		if _ext_moved(ext):
			_retake_ahead(ext)
		if field_k == k - 1:
			field_a = field_a.slice(3, 12) + _field_sample(k + 3, ext)
			field_k = k
		elif field_k == k + 1:
			field_a = _field_sample(k, ext) + field_a.slice(0, 9)
			field_k = k
		return
	field_a = _field_sample(k, ext) + _field_sample(k + 1, ext) + _field_sample(k + 2, ext) \
		+ _field_sample(k + 3, ext)
	field_k = k
	field_e = ext.duplicate()


## Whether [param ext] is FIELD_EXT_TOL or more from field_e (either
## empty for none).
func _ext_moved(ext: PackedFloat64Array) -> bool:
	if ext.size() != 3 and field_e.size() != 3:
		return false
	var d := 0.0
	for i in 3:
		var x := (ext[i] if ext.size() == 3 else 0.0) - (field_e[i] if field_e.size() == 3 else 0.0)
		d += x * x
	return d >= FIELD_EXT_TOL * FIELD_EXT_TOL


## Takes the samples in hand that lie ahead of the trajectory again, with
## [param ext]: those taken before put the field where the trajectory
## would have gone without the change. Those behind it are where it went.
func _retake_ahead(ext: PackedFloat64Array) -> void:
	for j in 4:
		var h := (float(field_k + j) + 0.5) * FIELD_HOLD - t
		if h > 0.0:
			var a := _field_ahead(h, ext)
			field_a[3 * j] = a[0]
			field_a[3 * j + 1] = a[1]
			field_a[3 * j + 2] = a[2]
	field_e = ext.duplicate()


## The field's sample for the grid's interval [param k], at its middle.
func _field_sample(k: int, ext: PackedFloat64Array) -> PackedFloat64Array:
	return _field_ahead((float(k) + 0.5) * FIELD_HOLD - t, ext)


## The field's pull (inertial m/s²) where the trajectory will be in
## [param h] seconds, GRAIL's or, for an onboard model, R-2's: its
## position carried on by its velocity, the central pull and its rate (a
## third-order series), which a 60 nmi orbit's field and third bodies
## leave half a metre off in 30 s, and by [param ext], the step's
## external acceleration, held: a descent's thrust would otherwise leave
## it kilometres off a minute ahead.
func _field_ahead(h: float, ext: PackedFloat64Array) -> PackedFloat64Array:
	var r2 := s[0] * s[0] + s[1] * s[1] + s[2] * s[2]
	var r3 := r2 * sqrt(r2)
	var mu := Bodies.MU_MOON
	var rv := (s[0] * s[3] + s[1] * s[4] + s[2] * s[5]) / r2
	var ka := -0.5 * mu / r3 * h * h
	var kj := -mu / r3 * h * h * h / 6.0
	var px := s[0] + s[3] * h + s[0] * ka + kj * (s[3] - 3.0 * rv * s[0])
	var py := s[1] + s[4] * h + s[1] * ka + kj * (s[4] - 3.0 * rv * s[1])
	var pz := s[2] + s[5] * h + s[2] * ka + kj * (s[5] - 3.0 * rv * s[2])
	if ext.size() == 3:
		var kx := 0.5 * h * h
		px += ext[0] * kx
		py += ext[1] * kx
		pz += ext[2] * kx
	var a := Bodies.moon_fixed_axes(t + h)
	var fx := px * a[0] + py * a[1] + pz * a[2]
	var fy := px * a[3] + py * a[4] + pz * a[5]
	var fz := px * a[6] + py * a[7] + pz * a[8]
	var g: PackedFloat64Array
	if model == Model.TRUTH:
		g = MoonGravity.accel_fixed(fx, fy, fz, MoonGravity.degree_at(sqrt(fx * fx + fy * fy + fz * fz)))
	else:
		g = MoonGravity.r2_accel_fixed(fx, fy, fz, Bodies.MU_MOON)
	return PackedFloat64Array([
		g[0] * a[0] + g[1] * a[3] + g[2] * a[6],
		g[0] * a[1] + g[1] * a[4] + g[2] * a[7],
		g[0] * a[2] + g[1] * a[5] + g[2] * a[8]])


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

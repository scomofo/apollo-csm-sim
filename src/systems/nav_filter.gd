## The CMC's navigation filter for its optics marks (P22, P23): the state
## vector's error covariance P, 6 x 6 in ECI axes (m, m/s) [simplified:
## Colossus kept the W matrix, P's square root, and its erasable loads set
## where it starts; here P itself, whose starting RMS V67 shows and loads].
## P holds for the state vector it was last current for (the anchor). A
## mark's time takes it on by the trajectory's own transition matrix, found
## by coasting the anchor with each component nudged in turn, so the
## Earth's and the Moon's pulls both shape it. A mark's residual is then
## weighted in, a scalar at a time, in Joseph form.
##
## The sightings it weights in: the angle between a star and the near
## horizon of the Earth or the Moon (P23), and the line of sight to a
## landmark on the Moon (P22).
class_name NavFilter
extends RefCounted

## The starting RMS errors, m and m/s [estimated: wide enough for a state
## vector nobody has updated since a burn].
const POS_RMS_M := 30000.0
const VEL_RMS_MPS := 10.0
## The nudges the transition matrix is found with, m and m/s.
const NUDGE_POS_M := 1000.0
const NUDGE_VEL_MPS := 1.0
## Acceleration the state vector doesn't model (the SM's vents), RMS per
## axis, m/s², which P gains as it's carried [estimated].
const UNMODELLED_ACC := 1.0e-6
## A burn bigger than this, m/s, starts P again from its RMS; a smaller
## one's velocity gains this execution error, a fraction of the burn plus a
## floor [estimated].
const BIG_BURN_MPS := 50.0
const BURN_ERR_FRAC := 0.01
const BURN_ERR_MPS := 0.03

var pos_rms: float = POS_RMS_M
var vel_rms: float = VEL_RMS_MPS
## P at the anchor's time, row-major.
var p: PackedFloat64Array = PackedFloat64Array()
## The state vector P was last current for; null until the first reinit.
var anchor: Trajectory = null
## Set when a burn has moved the state vector since the anchor: the next
## mark starts P again from its RMS.
var stale: bool = true


## P from the starting RMS, current for state vector [param nav].
func reinit(nav: Trajectory) -> void:
	p = diagonal(pos_rms * pos_rms, vel_rms * vel_rms)
	anchor = nav.clone() if nav != null else null
	stale = false


## P carried to state vector [param nav]'s time (a copy). A stale or
## missing anchor starts it again from the RMS first.
func carried(nav: Trajectory) -> PackedFloat64Array:
	if stale or anchor == null:
		reinit(nav)
	var dt := nav.t - anchor.t
	if absf(dt) < 1.0:
		return p.duplicate()
	var phi := transition(anchor, nav.t)
	var out := mul(mul(phi, p), transpose(phi))
	# The vents' push, as a random acceleration over the interval.
	var q := UNMODELLED_ACC * UNMODELLED_ACC * absf(dt)
	for i in 3:
		out[(i + 3) * 6 + i + 3] += q
		out[i * 6 + i] += q * dt * dt / 3.0
		out[i * 6 + i + 3] += q * dt / 2.0
		out[(i + 3) * 6 + i] += q * dt / 2.0
	return out


## A burn of [param dv] m/s has just ended on state vector [param nav].
## A small one's P is carried to its end and gains its execution error; a
## big one's starts again from the RMS [simplified: its trajectory before
## the burn stands in for the burn's, which a small burn barely changes].
func after_burn(nav: Trajectory, dv: float) -> void:
	if stale or anchor == null or dv > BIG_BURN_MPS:
		reinit(nav)
		return
	p = carried(nav)
	var e := BURN_ERR_FRAC * dv + BURN_ERR_MPS
	for i in 3:
		p[(i + 3) * 6 + i + 3] += e * e
	anchor = nav.clone()


## A mark weighted in: [param nav] moves by [param dx] (ECI axes), and
## [param p_new] (its P) becomes P, the anchor [param nav].
func accept(nav: Trajectory, dx: PackedFloat64Array, p_new: PackedFloat64Array) -> void:
	for i in 6:
		nav.s[i] += dx[i]
	p = p_new.duplicate()
	anchor = nav.clone()


## The RMS position and velocity errors P [param pm] holds, m and m/s.
static func rms(pm: PackedFloat64Array) -> Vector2:
	return Vector2(sqrt((pm[0] + pm[7] + pm[14]) / 3.0), sqrt((pm[21] + pm[28] + pm[35]) / 3.0))


# --- the update ---------------------------------------------------------------

## A scalar measurement's update: residual [param dq] (measured less
## predicted), gradient [param b] (6: its change with each state
## component) and variance [param r], given P [param pm]. Returns
## {"dx": the state's change, "p": P after}.
static func scalar_update(pm: PackedFloat64Array, b: PackedFloat64Array, dq: float, r: float) -> Dictionary:
	var pb := PackedFloat64Array()
	pb.resize(6)
	for i in 6:
		var acc := 0.0
		for j in 6:
			acc += pm[i * 6 + j] * b[j]
		pb[i] = acc
	var s := r
	for i in 6:
		s += b[i] * pb[i]
	var k := PackedFloat64Array()
	k.resize(6)
	var dx := PackedFloat64Array()
	dx.resize(6)
	for i in 6:
		k[i] = pb[i] / s
		dx[i] = k[i] * dq
	# Joseph form: (I - k b') P (I - k b')' + r k k'.
	var a := identity()
	for i in 6:
		for j in 6:
			a[i * 6 + j] -= k[i] * b[j]
	var out := mul(mul(a, pm), transpose(a))
	for i in 6:
		for j in 6:
			out[i * 6 + j] += r * k[i] * k[j]
	return {"dx": dx, "p": out}


## The transition matrix of coasting [param from] to GET [param t]: how
## each component of the state then (Earth-relative, ECI axes) moves with
## each now, by coasting it with each nudged in turn.
static func transition(from: Trajectory, t: float) -> PackedFloat64Array:
	var base := from.clone()
	base.coast_to(t)
	var e0 := base.earth_state()
	var phi := PackedFloat64Array()
	phi.resize(36)
	for j in 6:
		var d := NUDGE_POS_M if j < 3 else NUDGE_VEL_MPS
		var tr := from.clone()
		tr.s[j] += d
		tr.coast_to(t)
		var e := tr.earth_state()
		for i in 6:
			phi[i * 6 + j] = (e[i] - e0[i]) / d
	return phi


# --- the sightings -------------------------------------------------------------

## The star-horizon sighting from state [param tr]: the angle (rad) between
## star [param star] (a unit vector, ECI) and [param body]'s ("earth" or
## "moon") near horizon, the limb point toward the star [simplified: the
## solid limb; the flown P23 marked on the Earth's atmosphere's horizon,
## some 30 km up]. Returns {"q", "b" (6: its gradient; the velocity's is
## zero), "horizon" (the limb point's direction, ECI), "radius" (the
## body's angular radius, rad)}; empty when the star is behind the body.
static func star_horizon(tr: Trajectory, star: Vector3, body: String) -> Dictionary:
	var st := tr.earth_state() if body == "earth" else tr.moon_state_rel()
	var big_r := Bodies.R_EARTH if body == "earth" else Bodies.R_MOON
	# In doubles throughout: a kilometre at 300,000 km is 3e-6 rad.
	var d := sqrt(st[0] * st[0] + st[1] * st[1] + st[2] * st[2])
	if d <= big_r:
		return {}
	# The unit vector to the body's centre, and the star's.
	var ux := -st[0] / d
	var uy := -st[1] / d
	var uz := -st[2] / d
	var sn := sqrt(float(star.x) * star.x + float(star.y) * star.y + float(star.z) * star.z)
	var sx := float(star.x) / sn
	var sy := float(star.y) / sn
	var sz := float(star.z) / sn
	var c := clampf(sx * ux + sy * uy + sz * uz, -1.0, 1.0)
	var theta := acos(c)
	var rho := asin(big_r / d)
	if theta <= rho or theta < 1e-6:
		return {}
	# Across the line to the centre, toward the star.
	var sin_t := sin(theta)
	var ex := (sx - ux * c) / sin_t
	var ey := (sy - uy * c) / sin_t
	var ez := (sz - uz * c) / sin_t
	var k := big_r / (d * sqrt(d * d - big_r * big_r))
	var b := PackedFloat64Array([ex / d - ux * k, ey / d - uy * k, ez / d - uz * k, 0.0, 0.0, 0.0])
	var horizon := Vector3(ux * cos(rho) + ex * sin(rho), uy * cos(rho) + ey * sin(rho), uz * cos(rho) + ez * sin(rho))
	return {"q": theta - rho, "b": b, "horizon": horizon.normalized(), "radius": rho}


## The line of sight from state [param tr] to the landmark at Moon-fixed
## [param site_mf] at the state's time. Returns {"los" (unit, ECI),
## "range" (m), "e1", "e2" (unit, across it)}.
static func landmark_los(tr: Trajectory, site_mf: Vector3) -> Dictionary:
	var st := tr.moon_state_rel()
	var site := Bodies.moon_fixed(tr.t) * site_mf
	var dx := float(site.x) - st[0]
	var dy := float(site.y) - st[1]
	var dz := float(site.z) - st[2]
	var rng := sqrt(dx * dx + dy * dy + dz * dz)
	var l := Vector3(dx / rng, dy / rng, dz / rng)
	var e1 := l.cross(Vector3(0, 0, 1) if absf(l.z) < 0.9 else Vector3(1, 0, 0)).normalized()
	return {"los": l, "range": rng, "e1": e1, "e2": l.cross(e1).normalized()}


# --- 6 x 6 matrices, row-major ----------------------------------------------------

static func identity() -> PackedFloat64Array:
	return diagonal(1.0, 1.0)


## A diagonal matrix: [param a] for the position, [param b] for the velocity.
static func diagonal(a: float, b: float) -> PackedFloat64Array:
	var m := PackedFloat64Array()
	m.resize(36)
	for i in 6:
		m[i * 6 + i] = a if i < 3 else b
	return m


static func mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var m := PackedFloat64Array()
	m.resize(36)
	for i in 6:
		for j in 6:
			var acc := 0.0
			for k in 6:
				acc += a[i * 6 + k] * b[k * 6 + j]
			m[i * 6 + j] = acc
	return m


static func transpose(a: PackedFloat64Array) -> PackedFloat64Array:
	var m := PackedFloat64Array()
	m.resize(36)
	for i in 6:
		for j in 6:
			m[j * 6 + i] = a[i * 6 + j]
	return m


# --- checkpoints -------------------------------------------------------------------

func snapshot() -> Dictionary:
	return {"pos_rms": pos_rms, "vel_rms": vel_rms, "p": Array(p), "stale": stale,
		"anchor": {"primary": anchor.primary, "t": anchor.t, "s": Array(anchor.s), "field": anchor.field_snapshot()} if anchor != null else {}}


func restore(d: Dictionary) -> void:
	pos_rms = float(d.get("pos_rms", POS_RMS_M))
	vel_rms = float(d.get("vel_rms", VEL_RMS_MPS))
	p = PackedFloat64Array(d.get("p", []))
	stale = bool(d.get("stale", true)) or p.size() != 36
	anchor = null
	var a: Dictionary = d.get("anchor", {})
	if not a.is_empty():
		anchor = Trajectory.new().as_onboard(Trajectory.Model.CMC)
		anchor.set_state_d(str(a["primary"]), float(a["t"]), PackedFloat64Array(a["s"]))
		anchor.restore_field(a.get("field", {}))

## Luminary's rendezvous navigation filter for P20 (slice 11d): the error
## covariance of the state vector P20 updates, the LM's or the CSM's,
## and of the rendezvous radar's boresight biases in shaft and trunnion.
## Luminary kept its square root, W, 9 x 9 in flight (the eight and a
## dummy), and updated it by Potter's method [published: Luminary 099,
## P20-P25 and MEASUREMENT_INCORPORATION; GSOP R-567 section 5.2]; here the
## covariance E = W W' itself, 8 x 8 in doubles, updated in Joseph form,
## which comes to the same [derived]. W was carried by gravity alone, with
## no process noise, and the biases' rows constant [published: GSOP R-567
## Eq. 2.2.18]: here E is carried by the state vector's own transition
## matrix (NavFilter.transition()) from the state vector it was last current
## for (the anchor), which the LM's burns don't move, as Luminary carried W
## through a burn on the state vector from before it [published: Luminary
## 099, AVETOMID].
class_name RendezvousFilter
extends RefCounted

const N := 8

## E, row-major: position (m), velocity (m/s), shaft and trunnion bias
## (rad).
var e: PackedFloat64Array = PackedFloat64Array()
## The state vector E is current for; null until init().
var anchor: Trajectory = null


## E from the per-axis standard deviations: [param pos] (m), [param vel]
## (m/s) and [param bias] (rad), uncorrelated, current for [param nav]
## (Luminary's WLINIT).
func init(nav: Trajectory, pos: float, vel: float, bias: float) -> void:
	e = PackedFloat64Array()
	e.resize(N * N)
	for i in N:
		var s := pos if i < 3 else (vel if i < 6 else bias)
		e[i * N + i] = s * s
	anchor = nav.clone()


## E carried to state vector [param nav]'s time: its position and velocity
## by the anchor's coast to then, the biases unchanged.
func carry(nav: Trajectory) -> void:
	if anchor == null or absf(nav.t - anchor.t) < 0.5:
		anchor = nav.clone()
		return
	var phi6 := NavFilter.transition(anchor, nav.t)
	var phi := PackedFloat64Array()
	phi.resize(N * N)
	for i in 6:
		for j in 6:
			phi[i * N + j] = phi6[i * 6 + j]
	phi[6 * N + 6] = 1.0
	phi[7 * N + 7] = 1.0
	e = mul(mul(phi, e), transpose(phi))
	anchor = nav.clone()


## A scalar measurement's update, given E [param em]: its gradient
## [param b] (8: the change of the scaled measurement with each state), the
## residual [param dq] (measured less predicted) and its variance
## [param r]. Returns {"dx": the state's change (8), "e": E after}.
static func update(em: PackedFloat64Array, b: PackedFloat64Array, dq: float, r: float) -> Dictionary:
	var eb := PackedFloat64Array()
	eb.resize(N)
	for i in N:
		var acc := 0.0
		for j in N:
			acc += em[i * N + j] * b[j]
		eb[i] = acc
	var s := r
	for i in N:
		s += b[i] * eb[i]
	var k := PackedFloat64Array()
	k.resize(N)
	var dx := PackedFloat64Array()
	dx.resize(N)
	for i in N:
		k[i] = eb[i] / s
		dx[i] = k[i] * dq
	# Joseph form: (I - k b') E (I - k b')' + r k k'.
	var a := PackedFloat64Array()
	a.resize(N * N)
	for i in N:
		a[i * N + i] = 1.0
		for j in N:
			a[i * N + j] -= k[i] * b[j]
	var out := mul(mul(a, em), transpose(a))
	for i in N:
		for j in N:
			out[i * N + j] += r * k[i] * k[j]
	return {"dx": dx, "e": out}


## The root sum squares of E's position, velocity and bias errors (m, m/s,
## rad), as V06N99 shows them [published: Luminary 099's V67WW, the root of
## each block's trace].
func rss() -> Vector3:
	if e.size() != N * N:
		return Vector3.ZERO
	return Vector3(sqrt(e[0] + e[9] + e[18]), sqrt(e[27] + e[36] + e[45]), sqrt(e[54] + e[63]))


static func mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var m := PackedFloat64Array()
	m.resize(N * N)
	for i in N:
		for j in N:
			var acc := 0.0
			for k in N:
				acc += a[i * N + k] * b[k * N + j]
			m[i * N + j] = acc
	return m


static func transpose(a: PackedFloat64Array) -> PackedFloat64Array:
	var m := PackedFloat64Array()
	m.resize(N * N)
	for i in N:
		for j in N:
			m[j * N + i] = a[i * N + j]
	return m


func snapshot() -> Dictionary:
	return {"e": Array(e), "anchor": {"primary": anchor.primary, "t": anchor.t, "s": Array(anchor.s),
		"field": anchor.field_snapshot()} if anchor != null else {}}


func restore(d: Dictionary) -> void:
	e = PackedFloat64Array(d.get("e", []))
	anchor = null
	var a: Dictionary = d.get("anchor", {})
	if not a.is_empty():
		anchor = Trajectory.new().as_onboard(Trajectory.Model.LGC)
		anchor.set_state_d(str(a["primary"]), float(a["t"]), PackedFloat64Array(a["s"]))
		anchor.restore_field(a.get("field", {}))

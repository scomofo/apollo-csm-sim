## The Moon's gravity fields beyond its central pull, in the Moon-fixed
## frame (the IAU's mean Earth/polar axis frame):
## - GRAIL's (data/gravity/, written by tools/gravity/moon_gravity.py),
##   truth's and the RTCC's. Its mascons, the mass concentrations under
##   the maria, pull a low orbit's apsides by kilometres a day.
## - The Boeing R-2 model the onboard computers carried: the Moon's J2,
##   J3, C22 and C31 alone.
##
## The acceleration is Cunningham's recursion as Montenbruck and Gill give
## it (Satellite Orbits, 2000, section 3.2), on unnormalised coefficients:
## from degree 2, since degree 0 is the central pull the propagator
## already has and degree 1 is nil about the centre of mass. Unnormalised,
## the recursion's terms stay within double precision to degree 80.
class_name MoonGravity
extends RefCounted

## The highest degree the unnormalised recursion keeps within doubles.
const MAX_DEGREE := 80
## The lowest radius the fields are evaluated at, as a fraction of their
## reference radius: under the Moon's lowest ground (Antoniadi's floor,
## 0.994). Inside the body the series diverge, degree 30's terms growing
## as (R/r)^31, thirty million times over at 1,000 km; only a trajectory
## diving through the surface goes there, a planning trial or a crash.
## Below this a field is evaluated straight above, at this radius:
## bounded, and continuous across it.
const FLOOR := 0.99

## The R-2 lunar potential model, as Colossus 2A (Comanche 055) and
## Luminary 1A (Luminary 099) flew it for Apollo 11: J2 and J3 in their
## OBLATE routine's tables, C22 and C31 in the padload (E3J22R2M,
## E32C31RM), unnormalised, about 1738.09 km [published: Risdal, Boeing
## D2-100819-1, 1966; the Comanche 055 and Luminary 099 listings and
## padloads]. Its J3 has the wrong sign: GRAIL's is +8.5e-6.
const R2_RADIUS := 1738090.0
const R2_J2 := 2.07108e-4
const R2_J3 := -2.1e-5
const R2_C22 := 2.0716e-5
const R2_C31 := 3.4e-5
## The computers apply R-2 within 16,093 km of the Moon (RDM).
const R2_RANGE := 16093440.0

## GRAIL's field's degree, 0 when none is loaded.
static var degree: int = 0
## GM (m³/s²) and reference radius (m) GRAIL's coefficients are relative
## to.
static var gm: float = 0.0
static var radius: float = 0.0
## GRAIL's coefficients, unnormalised, for n from 2 and m from 0 to n, in
## that order: index n(n+1)/2 + m - 3.
static var c: PackedFloat64Array = PackedFloat64Array()
static var s: PackedFloat64Array = PackedFloat64Array()
## The model's name, for the record.
static var model: String = ""

# R-2's coefficients in the same layout, to degree 3.
static var _r2_c: PackedFloat64Array = PackedFloat64Array([
	-R2_J2, 0.0, R2_C22,
	-R2_J3, R2_C31, 0.0, 0.0])
static var _r2_s: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
# The recursion's scratch, indexed n(n+1)/2 + m, sized for the highest
# degree loaded + 1.
static var _v: PackedFloat64Array = PackedFloat64Array()
static var _w: PackedFloat64Array = PackedFloat64Array()


## Loads GRAIL's field from [param path] (JSON with gm_m3s2, radius_m,
## degree and the fully normalised c and s from degree 2), keeping degrees
## up to [param max_degree] (-1 for the file's). Returns whether it
## loaded.
static func load_field(path: String, max_degree: int = -1) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("MoonGravity: cannot open %s" % path)
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		push_error("MoonGravity: %s is not a field" % path)
		return false
	var n_file := int(d["degree"])
	var n_max := n_file if max_degree < 0 else mini(max_degree, n_file)
	if n_max > MAX_DEGREE:
		push_error("MoonGravity: degree %d is past the recursion's %d" % [n_max, MAX_DEGREE])
		return false
	var cn: Array = d["c"]
	var sn: Array = d["s"]
	var count := (n_max + 1) * (n_max + 2) / 2 - 3
	c.resize(count)
	s.resize(count)
	for n in range(2, n_max + 1):
		for m in range(0, n + 1):
			var i := n * (n + 1) / 2 + m - 3
			# Unnormalise: sqrt((2 - delta_m0) (2n + 1) (n - m)! / (n + m)!).
			var f2 := (2.0 if m > 0 else 1.0) * float(2 * n + 1)
			for k in range(n - m + 1, n + m + 1):
				f2 /= float(k)
			var k_nm := sqrt(f2)
			c[i] = float(cn[i]) * k_nm
			s[i] = float(sn[i]) * k_nm
	gm = float(d["gm_m3s2"])
	radius = float(d["radius_m"])
	model = str(d.get("model", ""))
	degree = n_max
	_size_scratch(n_max)
	return true


## Drops GRAIL's field: truth's Moon pulls as a point.
static func unload() -> void:
	degree = 0
	c = PackedFloat64Array()
	s = PackedFloat64Array()


## GRAIL's degree worth summing at [param r] m from the Moon's centre:
## those whose (R/r)^n still exceeds e^-8, 3e-4, up to the field's. At 60
## nmi all of degree 30's; two lunar radii out, 11; ten out, 3.
static func degree_at(r: float) -> int:
	var q := log(r / radius)
	if q <= 8.0 / float(degree):
		return degree
	return clampi(int(8.0 / q), 2, degree)


## GRAIL's acceleration beyond the central pull, m/s², at Moon-fixed
## (x, y, z) m, in the Moon-fixed frame, to degree [param n_max] (-1 for
## the field's). Zero when none is loaded.
static func accel_fixed(x: float, y: float, z: float, n_max: int = -1) -> PackedFloat64Array:
	var nn := degree if n_max < 0 else mini(n_max, degree)
	if nn < 2:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	return _accel(c, s, nn, gm, radius, x, y, z)


## R-2's acceleration beyond the central pull, m/s², at Moon-fixed
## (x, y, z) m, in the Moon-fixed frame; zero beyond R2_RANGE. Its GM is
## [param mu], the central pull's.
static func r2_accel_fixed(x: float, y: float, z: float, mu: float) -> PackedFloat64Array:
	if x * x + y * y + z * z > R2_RANGE * R2_RANGE:
		return PackedFloat64Array([0.0, 0.0, 0.0])
	_size_scratch(3)
	return _accel(_r2_c, _r2_s, 3, mu, R2_RADIUS, x, y, z)


static func _size_scratch(n_max: int) -> void:
	var size := (n_max + 2) * (n_max + 3) / 2
	if _v.size() < size:
		_v.resize(size)
		_w.resize(size)


## The recursion: V and W to degree nn + 1, from V00 = R/r down each
## order's column, then the acceleration's sums over the unnormalised
## [param cc] and [param ss] to degree [param nn], scaled by GM/R².
static func _accel(cc: PackedFloat64Array, ss: PackedFloat64Array, nn: int, gm_: float, rad: float,
		x: float, y: float, z: float) -> PackedFloat64Array:
	var r2 := x * x + y * y + z * z
	var lo := FLOOR * rad
	if r2 < lo * lo:
		var up := lo / sqrt(maxf(r2, 1.0))
		x *= up
		y *= up
		z *= up
		r2 = lo * lo
	var x0 := rad * x / r2
	var y0 := rad * y / r2
	var z0 := rad * z / r2
	var rho := rad * rad / r2
	var v := _v
	var w := _w
	var top := nn + 1
	v[0] = rad / sqrt(r2)
	w[0] = 0.0
	for m in range(0, top + 1):
		var d := m * (m + 1) / 2 + m
		if m > 0:
			var p := (m - 1) * m / 2 + m - 1
			var k := float(2 * m - 1)
			v[d] = k * (x0 * v[p] - y0 * w[p])
			w[d] = k * (x0 * w[p] + y0 * v[p])
		if m < top:
			var i1 := (m + 1) * (m + 2) / 2 + m
			var k1 := float(2 * m + 1) * z0
			v[i1] = k1 * v[d]
			w[i1] = k1 * w[d]
			var i2 := i1
			var i3 := d
			for n in range(m + 2, top + 1):
				var i := n * (n + 1) / 2 + m
				var inv := 1.0 / float(n - m)
				var a := float(2 * n - 1) * z0 * inv
				var b := float(n + m - 1) * rho * inv
				v[i] = a * v[i2] - b * v[i3]
				w[i] = a * w[i2] - b * w[i3]
				i3 = i2
				i2 = i
	var ax := 0.0
	var ay := 0.0
	var az := 0.0
	for n in range(2, nn + 1):
		var b1 := (n + 1) * (n + 2) / 2
		var j := n * (n + 1) / 2 - 3
		var cn0 := cc[j]
		ax -= cn0 * v[b1 + 1]
		ay -= cn0 * w[b1 + 1]
		az -= float(n + 1) * cn0 * v[b1]
		for m in range(1, n + 1):
			var c_ := cc[j + m]
			var s_ := ss[j + m]
			var up := b1 + m + 1
			var dn := b1 + m - 1
			var fac := float((n - m + 1) * (n - m + 2))
			ax += 0.5 * (-c_ * v[up] - s_ * w[up] + fac * (c_ * v[dn] + s_ * w[dn]))
			ay += 0.5 * (-c_ * w[up] + s_ * v[up] + fac * (-c_ * w[dn] + s_ * v[dn]))
			az += float(n - m + 1) * (-c_ * v[b1 + m] - s_ * w[b1 + m])
	var g := gm_ / (rad * rad)
	return PackedFloat64Array([ax * g, ay * g, az * g])

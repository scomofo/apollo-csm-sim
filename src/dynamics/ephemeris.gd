## The Moon's and the Sun's geocentric positions and the Moon's orientation
## over a mission, as the Chebyshev series tools/ephemeris/fit_ephemeris.py
## fits to JPL's DE441 and the IAU's lunar rotation model
## (data/ephemeris/). Frame: the ICRF (the J2000 equator and equinox),
## Earth-centred. Time: GET, s. Bodies flies on it when the mission's moon
## block names a file; see README.md, "Fidelity".
##
## Every value is a double. Outside the span the file covers, the series is
## held at the nearest end and an error is pushed.
class_name Ephemeris
extends RefCounted

## How many recent answers each cache keeps: the propagator asks for the
## same GET several times a step, for each vehicle.
const CACHE := 4

static var _loaded: Dictionary = {}

## The mission's GET 0 as a UTC Julian date.
var epoch_jd_utc: float = 0.0
var start_get_s: float = 0.0
var segment_s: float = 1.0
var segments: int = 0
# [segment][component]: PackedFloat64Array of Chebyshev coefficients.
var _moon: Array = []
var _sun: Array = []
var _orient: Array = []
# Ring caches of GETs and answers, and where each writes next.
var _pos_t := PackedFloat64Array()
var _pos_v: Array = []
var _pos_i := 0
var _state_t := PackedFloat64Array()
var _state_v: Array = []
var _state_i := 0
var _axes_t := PackedFloat64Array()
var _axes_v: Array = []
var _axes_i := 0
var _warned := false


## The ephemeris in [param path], parsed once per run.
static func load_file(path: String) -> Ephemeris:
	if _loaded.has(path):
		return _loaded[path]
	var f := FileAccess.open(path, FileAccess.READ)
	assert(f != null, "cannot open " + path)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var e := Ephemeris.new()
	e.epoch_jd_utc = float(d["epoch_jd_utc"])
	e.start_get_s = float(d["start_get_s"])
	e.segment_s = float(d["segment_s"])
	e.segments = int(d["segments"])
	e._moon = _coefficients(d["moon"]["segments"])
	e._sun = _coefficients(d["sun"]["segments"])
	e._orient = _coefficients(d["moon_orientation"]["segments"])
	assert(e._moon.size() == e.segments and e._sun.size() == e.segments and e._orient.size() == e.segments)
	for ts in [e._pos_t, e._state_t, e._axes_t]:
		ts.resize(CACHE)
		ts.fill(NAN)
	e._pos_v.resize(CACHE)
	e._state_v.resize(CACHE)
	e._axes_v.resize(CACHE)
	_loaded[path] = e
	return e


static func _coefficients(segs: Array) -> Array:
	var out := []
	for seg in segs:
		var comps := []
		for c in seg:
			comps.append(PackedFloat64Array(c))
		out.append(comps)
	return out


## Whether GET [param t] lies in the span the series cover.
func covers(t: float) -> bool:
	return t >= start_get_s and t <= start_get_s + segments * segment_s


## Where GET [param t] falls, in segments from the start: its whole part is
## the segment, the rest how far into it. Held to the span.
func _where(t: float) -> float:
	var u := (t - start_get_s) / segment_s
	if u < 0.0 or u > segments:
		if not _warned:
			push_error("Ephemeris: GET %.0f s is outside the ephemeris (%.0f to %.0f s)" % [
				t, start_get_s, start_get_s + segments * segment_s])
			_warned = true
		u = clampf(u, 0.0, segments)
	return u


## The three series of segment [param u]'s whole part at its fraction, and
## with [param rate] their derivatives per second: [a, b, c] or
## [a, b, c, a', b', c'].
func _evaluate(series: Array, u: float, rate: bool) -> PackedFloat64Array:
	var s := mini(int(u), segments - 1)
	var x := 2.0 * (u - s) - 1.0
	var c: Array = series[s]
	var ca: PackedFloat64Array = c[0]
	var cb: PackedFloat64Array = c[1]
	var cc: PackedFloat64Array = c[2]
	var n := ca.size()
	var a := ca[0] + ca[1] * x
	var b := cb[0] + cb[1] * x
	var z := cc[0] + cc[1] * x
	var da := ca[1]
	var db := cb[1]
	var dz := cc[1]
	# T_k(x) by recurrence, and dT_k/dx = k U_(k-1)(x).
	var t0 := 1.0
	var t1 := x
	var u0 := 1.0
	var u1 := 2.0 * x
	var x2 := 2.0 * x
	for k in range(2, n):
		var t2 := x2 * t1 - t0
		a += ca[k] * t2
		b += cb[k] * t2
		z += cc[k] * t2
		t0 = t1
		t1 = t2
		if rate:
			var dk := k * u1
			da += ca[k] * dk
			db += cb[k] * dk
			dz += cc[k] * dk
			var u2 := x2 * u1 - u0
			u0 = u1
			u1 = u2
	if not rate:
		return PackedFloat64Array([a, b, z])
	var per_s := 2.0 / segment_s
	return PackedFloat64Array([a, b, z, da * per_s, db * per_s, dz * per_s])


## The Moon's position relative to the Earth at GET [param t], m: the
## propagator's question, twice a step, without the velocity's cost.
func moon_position(t: float) -> PackedFloat64Array:
	for i in CACHE:
		if _pos_t[i] == t:
			return _pos_v[i]
	var v := _evaluate(_moon, _where(t), false)
	_pos_i = (_pos_i + 1) % CACHE
	_pos_t[_pos_i] = t
	_pos_v[_pos_i] = v
	return v


## The Moon's position and velocity relative to the Earth at GET
## [param t]: [x, y, z, vx, vy, vz], m and m/s.
func moon_state(t: float) -> PackedFloat64Array:
	for i in CACHE:
		if _state_t[i] == t:
			return _state_v[i]
	var v := _evaluate(_moon, _where(t), true)
	_state_i = (_state_i + 1) % CACHE
	_state_t[_state_i] = t
	_state_v[_state_i] = v
	return v


## The Sun's position relative to the Earth at GET [param t], m.
func sun_position(t: float) -> PackedFloat64Array:
	return _evaluate(_sun, _where(t), false)


## The Moon's pole right ascension and declination and its prime
## meridian's angle W at GET [param t], degrees, and their rates, degrees
## per second.
func moon_angles(t: float) -> PackedFloat64Array:
	return _evaluate(_orient, _where(t), true)


## The Moon-fixed (mean Earth/polar axis) frame's axes in the ICRF at GET
## [param t]: PackedFloat64Array(9), X, then Y, then Z. X points to 0 N
## 0 E, the mean direction of the Earth; Z is the north pole. They are the
## rows of Rz(W) Rx(90 - dec) Rz(90 + ra).
func moon_axes(t: float) -> PackedFloat64Array:
	for i in CACHE:
		if _axes_t[i] == t:
			return _axes_v[i]
	var ang := _evaluate(_orient, _where(t), false)
	var ra := deg_to_rad(ang[0])
	var de := deg_to_rad(ang[1])
	var w := deg_to_rad(ang[2])
	var ca := cos(ra)
	var sa := sin(ra)
	var cd := cos(de)
	var sd := sin(de)
	var cw := cos(w)
	var sw := sin(w)
	var v := PackedFloat64Array([
		-cw * sa - sw * sd * ca, cw * ca - sw * sd * sa, sw * cd,
		sw * sa - cw * sd * ca, -sw * ca - cw * sd * sa, cw * cd,
		cd * ca, cd * sa, sd])
	_axes_i = (_axes_i + 1) % CACHE
	_axes_t[_axes_i] = t
	_axes_v[_axes_i] = v
	return v


## The Moon's angular velocity in the ICRF at GET [param t], rad/s: the
## prime meridian's rate about the pole, and the pole's own slow motion
## (some 0.004 degrees a day) as the rates of its right ascension about the
## ICRF pole and of its declination about the equator's node.
func moon_omega(t: float) -> Vector3:
	var ang := moon_angles(t)
	var a := moon_axes(t)
	var ra := deg_to_rad(ang[0])
	var node := Vector3(-sin(ra), cos(ra), 0.0)
	return (Vector3(0, 0, 1) * ang[3] - node * ang[4] + Vector3(a[6], a[7], a[8]) * ang[5]) * (PI / 180.0)

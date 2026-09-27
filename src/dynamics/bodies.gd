## Earth-Moon system constants and the lunar ephemeris. See README.md, "Fidelity".
##
## Two models of the Moon and the Sun, which the mission's moon block
## chooses (Mission.apply_ephemeris()):
## - JPL's (use_ephemeris()): the Moon's and the Sun's geocentric positions
##   from DE441 and the Moon's orientation from the IAU's rotation model,
##   fitted for the mission's dates (Ephemeris, data/ephemeris/). ECI is
##   then the ICRF, the J2000 equator and equinox.
## - A circular one (configure()): the Moon on a circular orbit in a plane
##   of fixed inclination to the ECI equator, turning with its pole on that
##   plane's normal, and a fixed Sun [simplified]. The propagator's analytic
##   checks fly on it.
## Spacecraft motion is three-body (Earth + Moon) in either. With JPL's, the
## Earth is oblate (zonal harmonics J2 to J4, about its mean pole of the
## ephemeris's date) and the Sun pulls too (perturbed); the circular model
## keeps the two points alone.
class_name Bodies
extends RefCounted

const MU_EARTH: float = 3.986004418e14   ## m³/s²
const R_EARTH: float = 6378137.0         ## m
const MU_MOON: float = 4.9028003063e12   ## m³/s², GRAIL's (GL1800F)
const R_MOON: float = 1737400.0          ## m
const MU_SUN: float = 1.32712440018e20   ## m³/s²
## The Earth's zonal harmonics J2, J3 and J4, unnormalised, about R_EARTH
## [published: EGM96].
const EARTH_J2: float = 1.08262668e-3
const EARTH_J3: float = -2.53265649e-6
const EARTH_J4: float = -1.61962159e-6
const MOON_DIST: float = 384400000.0     ## m, mean distance [simplified: circular]
## Laplace sphere of influence of the Moon, m.
const MOON_SOI: float = 66100000.0
## Height at which the atmosphere is treated as beginning (Entry Interface,
## 400,000 ft).
const ENTRY_INTERFACE_ALT: float = 121920.0

## The JPL ephemeris the Moon and the Sun follow, or null for the circular
## model below.
static var ephemeris: Ephemeris = null
## Gravity beyond the Earth's and the Moon's point masses: the Earth's
## zonal harmonics and the Sun. On with JPL's ephemeris.
static var perturbed: bool = false
## The Earth's pole, a unit vector in ECI: the mean pole of the
## ephemeris's date (IAU 1976 precession from J2000) [simplified: nutation,
## some 0.003 degrees, left out]; the circular model's ECI Z.
static var earth_pole: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
## The circular model's lunar orbit plane: inclination to the ECI equator
## and node longitude.
static var moon_inclination: float = deg_to_rad(28.5)
static var moon_raan: float = 0.0
## Moon argument of latitude at GET 0, rad.
static var moon_phase0: float = 0.0
## Sun direction angle in the lunar orbit plane, rad.
static var sun_phase: float = 0.0


## The circular model's mean motion, or with the ephemeris the Moon's mean
## rate of turning over the ephemeris's span (its sidereal month), rad/s.
static func moon_mean_motion() -> float:
	if ephemeris:
		var a := ephemeris.start_get_s
		var b := a + ephemeris.segments * ephemeris.segment_s
		return deg_to_rad(ephemeris.moon_angles(b)[2] - ephemeris.moon_angles(a)[2]) / (b - a)
	return sqrt((MU_EARTH + MU_MOON) / (MOON_DIST * MOON_DIST * MOON_DIST))


## Fly on the circular model.
static func configure(inclination_deg: float, raan_deg: float, phase0_deg: float, sun_phase_deg: float = -20.0) -> void:
	ephemeris = null
	perturbed = false
	MoonGravity.unload()
	earth_pole = PackedFloat64Array([0.0, 0.0, 1.0])
	sun_phase = deg_to_rad(sun_phase_deg)
	moon_inclination = deg_to_rad(inclination_deg)
	moon_raan = deg_to_rad(raan_deg)
	moon_phase0 = deg_to_rad(phase0_deg)


## Fly on JPL's ephemeris [param e], with the Earth oblate about its pole
## of the ephemeris's date and the Sun pulling.
static func use_ephemeris(e: Ephemeris) -> void:
	ephemeris = e
	perturbed = true
	earth_pole = pole_of_date(e.epoch_jd_utc)


## The Earth's mean pole at Julian Date [param jd] in the J2000 frame (the
## ICRF, to 0.01 arc seconds), by the IAU 1976 precession, as
## tools/ephemeris/parking_orbit.py takes the parking orbit's plane
## [simplified: TT as UTC, 40 s apart].
static func pole_of_date(jd: float) -> PackedFloat64Array:
	var t := (jd - 2451545.0) / 36525.0
	var arcsec := PI / 180.0 / 3600.0
	var zeta := (2306.2181 * t + 0.30188 * t * t + 0.017998 * t * t * t) * arcsec
	var theta := (2004.3109 * t - 0.42665 * t * t - 0.041833 * t * t * t) * arcsec
	return PackedFloat64Array([sin(theta) * cos(zeta), -sin(theta) * sin(zeta), cos(theta)])


## The Earth's zonal harmonics' part of the specific potential energy at
## (x, y, z) relative to it, J/kg: mu/r sum J_n (R/r)^n P_n(u), u the sine
## of the latitude; nil unless perturbed. Some -28 kJ/kg at 300 km over
## the tropics.
static func zonal_energy(x: float, y: float, z: float) -> float:
	if not perturbed:
		return 0.0
	var p := earth_pole
	var r := sqrt(x * x + y * y + z * z)
	var u := (x * p[0] + y * p[1] + z * p[2]) / r
	var q := R_EARTH / r
	return MU_EARTH / r * (EARTH_J2 * q * q * (3.0 * u * u - 1.0) / 2.0
		+ EARTH_J3 * q * q * q * (5.0 * u * u * u - 3.0 * u) / 2.0
		+ EARTH_J4 * q * q * q * q * (35.0 * u * u * u * u - 30.0 * u * u + 3.0) / 8.0)


## Unit vectors P (node direction) and Q (90° ahead in the orbit plane) of
## the lunar orbit, and its normal W. Returned as PackedFloat64Array(9).
## With the ephemeris, the osculating orbit's at GET 0.
static func moon_plane() -> PackedFloat64Array:
	if ephemeris:
		var w := moon_normal()
		var p := Vector3(0, 0, 1).cross(w).normalized()
		var q := w.cross(p)
		return PackedFloat64Array([p.x, p.y, p.z, q.x, q.y, q.z, w.x, w.y, w.z])
	var co := cos(moon_raan)
	var so := sin(moon_raan)
	var ci := cos(moon_inclination)
	var si := sin(moon_inclination)
	return PackedFloat64Array([co, so, 0.0, -so * ci, co * ci, si, so * si, -co * si, ci])


## Moon position and velocity relative to Earth at GET [param t], as
## PackedFloat64Array [x, y, z, vx, vy, vz] (m, m/s).
static func moon_state(t: float) -> PackedFloat64Array:
	if ephemeris:
		return ephemeris.moon_state(t)
	var n := moon_mean_motion()
	var th := moon_phase0 + n * t
	var c := cos(th)
	var s := sin(th)
	var pl := moon_plane()
	var d := MOON_DIST
	var vd := MOON_DIST * n
	return PackedFloat64Array([
		d * (c * pl[0] + s * pl[3]), d * (c * pl[1] + s * pl[4]), d * (c * pl[2] + s * pl[5]),
		vd * (-s * pl[0] + c * pl[3]), vd * (-s * pl[1] + c * pl[4]), vd * (-s * pl[2] + c * pl[5])])


## The Moon's position relative to the Earth at GET [param t], m: the
## first three entries (the circular model returns its whole state).
static func moon_position(t: float) -> PackedFloat64Array:
	if ephemeris:
		return ephemeris.moon_position(t)
	return moon_state(t)


## The normal of the Moon's orbit about the Earth in ECI: the sense of its
## motion, which tells a free return from a pass the other way. With the
## ephemeris, the osculating orbit's at GET 0 (its plane turns some 0.05
## degrees a day).
static func moon_normal() -> Vector3:
	if ephemeris:
		var m := ephemeris.moon_state(0.0)
		return Vector3(m[1] * m[5] - m[2] * m[4], m[2] * m[3] - m[0] * m[5], m[0] * m[4] - m[1] * m[3]).normalized()
	var pl := moon_plane()
	return Vector3(pl[6], pl[7], pl[8])


## The Moon's north pole in ECI at GET [param t]: the axis it turns about.
## The circular model puts it on the orbit normal; the real one is 6.7
## degrees from it.
static func moon_pole(t: float) -> Vector3:
	var a := moon_fixed_axes(t)
	return Vector3(a[6], a[7], a[8])


## The Moon-fixed (selenographic) frame at GET [param t]: the basis whose
## columns are its axes in ECI. X points at the Earth's mean direction
## (0° N, 0° E), Z is the north pole and Y is 90° E: with the ephemeris,
## the IAU's mean Earth/polar axis frame, which librates as the real Moon
## does. [simplified, circular model: the Moon turns synchronously, with
## its pole on the normal of its orbit.]
static func moon_fixed(t: float) -> Basis:
	if ephemeris:
		var a := ephemeris.moon_axes(t)
		return Basis(Vector3(a[0], a[1], a[2]), Vector3(a[3], a[4], a[5]), Vector3(a[6], a[7], a[8]))
	var th := moon_phase0 + moon_mean_motion() * t
	var pl := moon_plane()
	var w := Vector3(pl[6], pl[7], pl[8])
	var x := -(Vector3(pl[0], pl[1], pl[2]) * cos(th) + Vector3(pl[3], pl[4], pl[5]) * sin(th))
	return Basis(x, w.cross(x), w)


## The Moon-fixed frame's axes in ECI at GET [param t], as moon_fixed()
## has them but in doubles: PackedFloat64Array(9), X, then Y, then Z.
static func moon_fixed_axes(t: float) -> PackedFloat64Array:
	if ephemeris:
		return ephemeris.moon_axes(t)
	var th := moon_phase0 + moon_mean_motion() * t
	var pl := moon_plane()
	var c := cos(th)
	var s := sin(th)
	var x := [-(pl[0] * c + pl[3] * s), -(pl[1] * c + pl[4] * s), -(pl[2] * c + pl[5] * s)]
	return PackedFloat64Array([x[0], x[1], x[2],
		pl[7] * x[2] - pl[8] * x[1], pl[8] * x[0] - pl[6] * x[2], pl[6] * x[1] - pl[7] * x[0],
		pl[6], pl[7], pl[8]])


## [param r], a position relative to the Moon in ECI (m, three floats), in
## the Moon-fixed frame at GET [param t], in doubles: to the millimetre
## where moon_fixed()'s single-precision Basis gives a decimetre.
static func to_moon_fixed(r: Array, t: float) -> PackedFloat64Array:
	var a := moon_fixed_axes(t)
	return PackedFloat64Array([
		r[0] * a[0] + r[1] * a[1] + r[2] * a[2],
		r[0] * a[3] + r[1] * a[4] + r[2] * a[5],
		r[0] * a[6] + r[1] * a[7] + r[2] * a[8]])


## The Moon's angular velocity in ECI at GET [param t], rad/s.
static func moon_omega(t: float) -> Vector3:
	if ephemeris:
		return ephemeris.moon_omega(t)
	return moon_normal() * moon_mean_motion()


## A point at [param radius] m from the Moon's centre at latitude
## [param lat_deg] and east longitude [param lon_deg], in the Moon-fixed
## frame.
static func selenographic_to_fixed(lat_deg: float, lon_deg: float, radius: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * cos(lo), cos(la) * sin(lo), sin(la)) * radius


## Latitude and east longitude (degrees) and radius (m) of a Moon-fixed
## position, as Vector3(lat, lon, radius).
static func fixed_to_selenographic(p: Vector3) -> Vector3:
	var r := p.length()
	return Vector3(rad_to_deg(asin(clampf(p.z / maxf(r, 1e-9), -1.0, 1.0))), rad_to_deg(atan2(p.y, p.x)), r)


## The Sun's position relative to the Earth at GET [param t], m: the
## ephemeris's, or the circular model's direction at a mean distance.
static func sun_position(t: float) -> PackedFloat64Array:
	if ephemeris:
		return ephemeris.sun_position(t)
	var d := sun_direction(t) * 1.495978707e11
	return PackedFloat64Array([d.x, d.y, d.z])


## Unit vector from the Earth toward the Sun in ECI at GET [param t]. With
## the circular model [simplified: fixed for the mission and placed in the
## lunar orbit plane at sun_phase, chosen so the Moon shows the waxing
## crescent Apollo 11 met: ~65° east of the Sun at LOI].
static func sun_direction(t: float) -> Vector3:
	if ephemeris:
		var s := ephemeris.sun_position(t)
		return Vector3(s[0], s[1], s[2]).normalized()
	var pl := moon_plane()
	return (Vector3(pl[0], pl[1], pl[2]) * cos(sun_phase) + Vector3(pl[3], pl[4], pl[5]) * sin(sun_phase)).normalized()


static func mu_of(primary: String) -> float:
	return MU_MOON if primary == "moon" else MU_EARTH


static func radius_of(primary: String) -> float:
	return R_MOON if primary == "moon" else R_EARTH

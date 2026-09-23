## Earth-Moon system constants and the lunar ephemeris. See README.md, "Fidelity".
##
## The Moon moves on a circular orbit about the Earth in a plane of fixed
## inclination to the Earth-centred inertial (ECI) equator. That is a
## deliberate simplification [simplified]: real lunar eccentricity (0.055)
## and solar perturbation are omitted so that trajectory targeting stays
## cheap and deterministic. Spacecraft motion itself is fully three-body
## (Earth + Moon) at all times.
class_name Bodies
extends RefCounted

const MU_EARTH: float = 3.986004418e14   ## m³/s²
const R_EARTH: float = 6378137.0         ## m
const MU_MOON: float = 4.9048695e12      ## m³/s²
const R_MOON: float = 1737400.0          ## m
const MOON_DIST: float = 384400000.0     ## m, mean distance [simplified: circular]
## Laplace sphere of influence of the Moon, m.
const MOON_SOI: float = 66100000.0
## Height at which the atmosphere is treated as beginning (Entry Interface,
## 400,000 ft).
const ENTRY_INTERFACE_ALT: float = 121920.0

## Lunar orbit plane: inclination to the ECI equator and node longitude.
static var moon_inclination: float = deg_to_rad(28.5)
static var moon_raan: float = 0.0
## Moon argument of latitude at GET 0, rad.
static var moon_phase0: float = 0.0
## Sun direction angle in the lunar orbit plane, rad.
static var sun_phase: float = 0.0


static func moon_mean_motion() -> float:
	return sqrt((MU_EARTH + MU_MOON) / (MOON_DIST * MOON_DIST * MOON_DIST))


static func configure(inclination_deg: float, raan_deg: float, phase0_deg: float, sun_phase_deg: float = -20.0) -> void:
	sun_phase = deg_to_rad(sun_phase_deg)
	moon_inclination = deg_to_rad(inclination_deg)
	moon_raan = deg_to_rad(raan_deg)
	moon_phase0 = deg_to_rad(phase0_deg)


## Unit vectors P (node direction) and Q (90° ahead in the orbit plane) of
## the lunar orbit, and its normal W. Returned as PackedFloat64Array(9).
static func moon_plane() -> PackedFloat64Array:
	var co := cos(moon_raan)
	var so := sin(moon_raan)
	var ci := cos(moon_inclination)
	var si := sin(moon_inclination)
	return PackedFloat64Array([co, so, 0.0, -so * ci, co * ci, si, so * si, -co * si, ci])


## Moon position and velocity relative to Earth at GET [param t], as
## PackedFloat64Array [x, y, z, vx, vy, vz] (m, m/s).
static func moon_state(t: float) -> PackedFloat64Array:
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


## Moon orbit normal in ECI.
static func moon_normal() -> Vector3:
	var pl := moon_plane()
	return Vector3(pl[6], pl[7], pl[8])


## The Moon-fixed (selenographic) frame at GET [param t]: the basis whose
## columns are its axes in ECI. X points at the Earth (0° N, 0° E), Z is
## the north pole and Y is 90° E. [simplified: the Moon turns
## synchronously, with its pole on the normal of its orbit; the real Moon
## librates, and its pole is 1.5° from the ecliptic's (slice 4a).]
static func moon_fixed(t: float) -> Basis:
	var th := moon_phase0 + moon_mean_motion() * t
	var pl := moon_plane()
	var w := Vector3(pl[6], pl[7], pl[8])
	var x := -(Vector3(pl[0], pl[1], pl[2]) * cos(th) + Vector3(pl[3], pl[4], pl[5]) * sin(th))
	return Basis(x, w.cross(x), w)


## The Moon's rotation in ECI, rad/s.
static func moon_omega() -> Vector3:
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


## Unit vector toward the Sun in ECI [simplified: fixed for the mission and
## placed in the lunar orbit plane at sun_phase, chosen so the Moon shows
## the waxing crescent Apollo 11 met: ~65° east of the Sun at LOI].
static func sun_direction() -> Vector3:
	var pl := moon_plane()
	return (Vector3(pl[0], pl[1], pl[2]) * cos(sun_phase) + Vector3(pl[3], pl[4], pl[5]) * sin(sun_phase)).normalized()


static func mu_of(primary: String) -> float:
	return MU_MOON if primary == "moon" else MU_EARTH


static func radius_of(primary: String) -> float:
	return R_MOON if primary == "moon" else R_EARTH

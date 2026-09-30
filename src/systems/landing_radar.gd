## Landing radar: the Doppler radar under the LM's descent stage. Its
## altitude beam measures the slant range to the ground (Terrain), and its
## velocity beams the LM's velocity over the turning surface, in the LM's
## axes. The antenna has two positions, which the LGC selects
## (lm.guid.lr_antenna): 1 for the braking phase, tilted from the LM's -X
## axis toward -Z so the beams reach the ground while the LM flies windows
## up; 2 for the approach and landing, along -X. The data are good only
## within the radar's range and while the beam meets the ground no more
## than max_incidence_deg from straight on. [simplified: noise-free; the
## altitude beam is the antenna's boresight, the velocity beams one
## measurement of the whole velocity; the ranges are from the LM's centre
## of mass.]
##
## Its range scale (slice 12a) goes low below a slant range of 2,500 ft
## and high again above 2,800 ft, on the range it measures; in low scale
## its trackers acquire the range only within 3,500 ft and the velocity
## within about 4,600 ft of altitude [published: LMA790-3-LM, p. 2.2-18;
## MSC-04112, p. 8-5]. Apollo 14's switched to low scale 4 min 52 s before
## PDI (fail("scale")) and, measuring nothing, stayed there until its
## breaker, PGNS: LDG RDR on panel 11 (ctl.lm.cb_ldg_rdr), was cycled:
## powered up, it comes on in high scale, and its data are good once its
## trackers acquire, the velocity 20 s after and the range 22 s after
## [published: MSC-04112, section 14.2.4 and Table 8-V; LMA790-3-LM,
## p. 2.2-26; simplified: noise at the edge of its range set Apollo 14's
## low scale, here the failure; no acquisition time otherwise].
##
## It measures after Dynamics has stepped (stage DEPENDENT), so the LGC
## reads it next step against its state for the same instant.
##
## Reads:  lm.dyn.primary, lm.dyn.r_m, lm.dyn.v_mps, lm.dyn.att_q,
##         lm.dyn.landed, lm.sys.powered, dock.state, lm.guid.lr_antenna,
##         ctl.lm.cb_ldg_rdr (the breaker, closed true)
## Writes: lm.lr.range_m (altitude beam's slant range; 0 without data),
##         lm.lr.beam_body (its direction, LM axes), lm.lr.alt_good,
##         lm.lr.vel_body (m/s, LM axes), lm.lr.vel_good, lm.lr.antenna,
##         lm.lr.low_scale, lm.lr.powered
class_name LandingRadar
extends Node

var range_m: float = 0.0
var alt_good: bool = false
var vel_good: bool = false
var vel_body: Vector3 = Vector3.ZERO
var antenna: int = 1
## In low scale (slice 12a).
var low_scale: bool = false
## When the radar last came on, GET s: its trackers' search starts then.
var power_get: float = -1.0e9
var powered: bool = true


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.DEPENDENT)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The altitude beam's direction in the LM's axes, antenna position
## [param pos].
static func beam_body(pos: int) -> Vector3:
	if pos != 1:
		return Vector3(-1.0, 0.0, 0.0)
	var t := deg_to_rad(float(SpacecraftData.section("landing_radar")["position1_tilt_deg"]))
	return Vector3(-cos(t), 0.0, -sin(t))


func tick(_dt: float) -> void:
	antenna = int(Bus.get_value("lm.guid.lr_antenna", 1))
	var t := float(Bus.get_value("time.get_s", 0.0))
	var power := bool(Bus.get_value("lm.sys.powered", true)) and bool(Bus.get_value("ctl.lm.cb_ldg_rdr", true))
	if power and not powered:
		# Powered up: high scale, the trackers searching.
		low_scale = false
		power_get = t
	powered = power
	var on := powered and str(Bus.get_value("dock.state", "")) == "free" \
		and str(Bus.get_value("lm.dyn.primary", "")) == "moon" and not bool(Bus.get_value("lm.dyn.landed", false))
	var d := SpacecraftData.section("landing_radar")
	var r_a: Array = Bus.get_value("lm.dyn.r_m", [0.0, 0.0, 0.0])
	var r := Vector3(r_a[0], r_a[1], r_a[2])
	var mf := Bodies.moon_fixed(t)
	var height := r.length() - Terrain.radius_under(mf.transposed() * r)
	# The slant range can't be shorter than the height over the ground.
	if not on or height > float(d["alt_range_m"]):
		range_m = 0.0
		alt_good = false
		vel_good = false
		vel_body = Vector3.ZERO
		_publish()
		return
	var att := Basis(Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY))
	var dir := att * beam_body(antenna)
	var hit := slant_range(r, dir, mf)
	var ok := hit.x > 0.0 and hit.y <= deg_to_rad(float(d["max_incidence_deg"]))
	var since := t - power_get
	var alt_in := hit.x <= float(d["low_scale_alt_range_m"] if low_scale else d["alt_range_m"])
	var vel_in := height <= float(d["low_scale_vel_height_m"]) if low_scale else hit.x <= float(d["vel_range_m"])
	alt_good = ok and alt_in and since >= float(d["acquire_alt_s"]) - 1e-6
	vel_good = ok and vel_in and since >= float(d["acquire_vel_s"]) - 1e-6
	range_m = hit.x if alt_good else 0.0
	# The scale follows the range the radar measures.
	if alt_good and hit.x < float(d["low_scale_below_m"]):
		low_scale = true
	elif alt_good and hit.x > float(d["high_scale_above_m"]):
		low_scale = false
	var v_a: Array = Bus.get_value("lm.dyn.v_mps", [0.0, 0.0, 0.0])
	var rel := Vector3(v_a[0], v_a[1], v_a[2]) - Bodies.moon_omega(t).cross(r)
	vel_body = att.inverse() * rel if vel_good else Vector3.ZERO
	_publish()


## Where the ray from [param r] (Moon-centred, inertial) along the unit
## vector [param dir] meets the ground, the Moon-fixed frame being
## [param mf]: Vector2(slant range, incidence angle from the ground's
## vertical), or (-1, 0) when it misses.
static func slant_range(r: Vector3, dir: Vector3, mf: Basis) -> Vector2:
	var mft := mf.transposed()
	var ground := Terrain.radius_under(mft * r)
	var s := sphere_hit(r, dir, ground)
	if s < 0.0:
		return Vector2(-1.0, 0.0)
	# Newton on the height above the ground along the ray; the ground's
	# slope is left out of the derivative.
	for _i in 6:
		var p := r + dir * s
		var f := p.length() - Terrain.radius_under(mft * p)
		var df := dir.dot(p.normalized())
		if df > -1e-3:
			break
		var step := f / df
		s = maxf(s - step, 0.0)
		if absf(step) < 0.05:
			break
	var at := r + dir * s
	return Vector2(s, acos(clampf(-dir.dot(at.normalized()), -1.0, 1.0)))


## The nearer distance along [param dir] from [param r] to the sphere of
## radius [param radius], or -1.
static func sphere_hit(r: Vector3, dir: Vector3, radius: float) -> float:
	# In GDScript's doubles: Vector3's floats lose metres near the Moon.
	var rx := float(r.x)
	var ry := float(r.y)
	var rz := float(r.z)
	var b := rx * dir.x + ry * dir.y + rz * dir.z
	var c := (rx * rx + ry * ry + rz * rz) - radius * radius
	var disc := b * b - c
	if disc < 0.0:
		return -1.0
	var s := -b - sqrt(disc)
	return s if s >= 0.0 else -1.0


## Apollo 14's failure: the range scale switched to low with nothing
## measured (part "scale").
func fail(part: String) -> void:
	if part == "scale":
		low_scale = true


func _publish() -> void:
	Bus.set_value("lm.lr.range_m", range_m)
	Bus.set_value("lm.lr.beam_body", beam_body(antenna))
	Bus.set_value("lm.lr.alt_good", alt_good)
	Bus.set_value("lm.lr.vel_body", vel_body)
	Bus.set_value("lm.lr.vel_good", vel_good)
	Bus.set_value("lm.lr.antenna", antenna)
	Bus.set_value("lm.lr.low_scale", low_scale)
	Bus.set_value("lm.lr.powered", powered)


func snapshot() -> Dictionary:
	return {"antenna": antenna, "low_scale": low_scale, "power_get": power_get, "powered": powered}


func restore(d: Dictionary) -> void:
	antenna = int(d.get("antenna", 1))
	low_scale = bool(d.get("low_scale", false))
	power_get = float(d.get("power_get", -1.0e9))
	powered = bool(d.get("powered", true))
	_publish()

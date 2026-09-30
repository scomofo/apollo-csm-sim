## Rendezvous radar: the LM's radar that tracks the transponder on the CSM
## (slice 11d). Its antenna turns on two gimbals, the shaft and the
## trunnion, in orientation I, the rendezvous's: at both zero it looks
## along the LM's +Z, a shaft angle S tips it toward +X and a trunnion angle
## T toward -Y, its line of sight (sin S cos T, -sin T, cos S cos T) in the
## LM's axes [published: Luminary 099's RRNB, LEM_GEOMETRY], held within
## mode 1's coverage, S -70 to +59° and T within 55° [published:
## Luminary's RRLIMCHK; LM AOH LMA790-3-LM p. 2.2-8] [simplified: mode 2,
## for the surface and the ascent, and the mechanical coverage beyond left
## out].
##
## The RNDZ RADAR switch (ctl.lm.rr_mode) chooses who points it:
##   0 LGC         while the LGC designates (lm.guid.rr_designating), the
##                 antenna slews to its angles (lm.guid.rr_designate) at up
##                 to 7°/s, and inside 7° at the error's own rate each
##                 second [published: AOH p. 2.2-8]; the LGC's track enable
##                 (lm.guid.rr_track_enable) closes the tracking loop
##   1 AUTO TRACK  it tracks by itself
##   2 SLEW        the crew slews it on the SLEW switch, UP and DOWN the
##                 shaft (ctl.lm.rr_slew_shaft, +1 up toward the LM's +X)
##                 and LEFT and RIGHT the trunnion (ctl.lm.rr_slew_trunnion,
##                 +1 left toward -Y) [estimated: the senses], at the SLEW
##                 RATE's 7 or 1.33°/s (ctl.lm.rr_slew_rate: 1 HI, 0 LO)
##                 [published: AOH pp. 2.2-7, 3-61]
## Tracking, it locks on the transponder once the line of sight to the CSM
## lies within capture_deg of its boresight, and follows it; the range
## tracker then takes acquisition_s before the data are good [published:
## AOH Table 2.2-2]. Not tracking, its gyros hold the boresight's direction
## in inertial space [published: AOH p. 2.2-28]. It loses the CSM when the
## line of sight leaves its coverage, the Moon comes between them or the
## range passes 400 nmi; a turn of the switch starts the range search
## again [published: GSOP R-567 p. 5.2-47]. SIGNAL STRENGTH (lm.rr.signal)
## reads the transponder through the beam, for peaking by hand [estimated:
## a Gaussian main lobe beam_3db_deg wide at half power, the power falling
## with the range squared, the meter reading 60 dB of it from full scale
## at 1 nmi on the boresight] [simplified: no side lobes to lock on, and
## the transponder seen whatever the CSM's attitude].
##
## Its errors are the flight's, drawn from the mission's seed (disperse()):
## biases on the range, the range rate and the boresight's shaft and
## trunnion, and noise on each sample; the range in 9.38 or 75.04 ft
## counts, the rate in 0.6278 ft/s counts, the angles in the CDUs' 2^-15 of
## a turn (spacecraft.json "rendezvous_radar"). Until disperse(), it is
## ideal.
##
## It measures after Dynamics has stepped (stage DEPENDENT), so the LGC
## reads it next step against its state vectors for the same instant.
##
## Reads:  lm.dyn.primary, lm.dyn.r_m, lm.dyn.v_mps, lm.dyn.att_q,
##         dyn.primary, dyn.r_m, dyn.v_mps, lm.sys.powered, dock.state,
##         ctl.lm.rr_mode, ctl.lm.rr_slew_shaft, ctl.lm.rr_slew_trunnion,
##         ctl.lm.rr_slew_rate,
##         lm.guid.rr_designating, lm.guid.rr_designate,
##         lm.guid.rr_track_enable
## Writes: lm.rr.range_m (0 without data), lm.rr.range_rate_mps (positive
##         opening), lm.rr.shaft_rad and lm.rr.trunnion_rad (the antenna's
##         CDUs), lm.rr.los_body (their line of sight, LM axes),
##         lm.rr.data_good, lm.rr.locked (on the transponder),
##         lm.rr.no_track (the NO TRACK light), lm.rr.signal (0 to 1)
class_name RendezvousRadar
extends Node

## The CDUs' count, rad [derived: 2^-15 of a turn].
const CDU_RAD := TAU / 32768.0
const FT := 0.3048
const NMI := 1852.0

var shaft: float = 0.0
var trunnion: float = 0.0
## Locked on the transponder, and how long since (the range search).
var locked: bool = false
var track_s: float = 0.0
## The boresight's direction in inertial space, which the gyros hold.
var hold_dir: Vector3 = Vector3.ZERO
var data_good: bool = false
var range_m: float = 0.0
var range_rate: float = 0.0
var shaft_cdu: float = 0.0
var trunnion_cdu: float = 0.0
var los_body: Vector3 = Vector3(0, 0, 1)
var strength: float = 0.0
var no_track: bool = false
## No errors until disperse().
var ideal: bool = true
## This flight's biases: the range's in standard deviations of its limit
## (it scales with the range), the rate's (m/s) and the boresight's (rad).
var bias_range_k: float = 0.0
var bias_rate: float = 0.0
var bias_shaft: float = 0.0
var bias_trunnion: float = 0.0
var _rng := RandomNumberGenerator.new()
var _mode_was: int = -1
var _tracking_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.DEPENDENT)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## Draw this flight's biases from [param seed], and the noise to come.
func disperse(seed: int) -> void:
	var d := SpacecraftData.section("rendezvous_radar")
	_rng.seed = seed
	ideal = false
	bias_range_k = _rng.randfn(0.0, 1.0)
	bias_rate = _rng.randfn(0.0, float(d["rate_bias_fps"]) * FT / 3.0)
	var a := float(d["angle_bias_mrad"]) * 1e-3 / 3.0
	bias_shaft = _rng.randfn(0.0, a)
	bias_trunnion = _rng.randfn(0.0, a)


## The line of sight at shaft [param s] and trunnion [param t], LM axes.
static func los_of(s: float, t: float) -> Vector3:
	return Vector3(sin(s) * cos(t), -sin(t), cos(s) * cos(t))


## The shaft and trunnion (x, y) that look along [param los] (LM axes), in
## mode 1 [published: Luminary's RRANGLES].
static func angles_of(los: Vector3) -> Vector2:
	var u := los.normalized()
	return Vector2(atan2(u.x, u.z), asin(clampf(-u.y, -1.0, 1.0)))


## [param a] (shaft, trunnion) within mode 1's coverage.
static func in_coverage(a: Vector2) -> bool:
	var d := SpacecraftData.section("rendezvous_radar")
	return a.x >= deg_to_rad(float(d["shaft_min_deg"])) and a.x <= deg_to_rad(float(d["shaft_max_deg"])) \
		and absf(a.y) <= deg_to_rad(float(d["trunnion_max_deg"]))


static func _clamped(a: Vector2) -> Vector2:
	var d := SpacecraftData.section("rendezvous_radar")
	var tmax := deg_to_rad(float(d["trunnion_max_deg"]))
	return Vector2(clampf(a.x, deg_to_rad(float(d["shaft_min_deg"])), deg_to_rad(float(d["shaft_max_deg"]))),
		clampf(a.y, -tmax, tmax))


func tick(dt: float) -> void:
	var d := SpacecraftData.section("rendezvous_radar")
	var mode := int(Bus.get_value("ctl.lm.rr_mode", 1))
	var tracking := mode == 1 or (mode == 0 and bool(Bus.get_value("lm.guid.rr_track_enable", false)))
	if mode != _mode_was or tracking != _tracking_was:
		# The switch turned: the range search starts again.
		track_s = 0.0
		if not tracking:
			locked = false
	_mode_was = mode
	_tracking_was = tracking
	var att := Basis(Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY) as Quaternion)
	var on := str(Bus.get_value("dock.state", "")) == "free" and bool(Bus.get_value("lm.sys.powered", true)) \
		and str(Bus.get_value("lm.dyn.primary", "")) == "moon" and str(Bus.get_value("dyn.primary", "")) == "moon"
	if hold_dir == Vector3.ZERO:
		hold_dir = att * los_of(shaft, trunnion)
	var lm_r: Array = Bus.get_value("lm.dyn.r_m", [0.0, 0.0, 0.0])
	var cm_r: Array = Bus.get_value("dyn.r_m", [0.0, 0.0, 0.0])
	# The line of sight, in doubles before it is a Vector3.
	var dd := [float(cm_r[0]) - float(lm_r[0]), float(cm_r[1]) - float(lm_r[1]), float(cm_r[2]) - float(lm_r[2])]
	var rng := sqrt(dd[0] * dd[0] + dd[1] * dd[1] + dd[2] * dd[2])
	var visible := on and rng > 0.0 and rng <= float(d["range_max_m"]) and not blocked(lm_r, dd)
	var los := Vector3(dd[0], dd[1], dd[2]) / rng if rng > 0.0 else Vector3(0, 0, 1)
	var los_b := att.inverse() * los
	var target := angles_of(los_b)
	# Where the gyros hold it.
	var a := _clamped(angles_of(att.inverse() * hold_dir))
	if not on:
		locked = false
		track_s = 0.0
	elif mode == 2:
		var slew := Vector2(int(Bus.get_value("ctl.lm.rr_slew_shaft", 0)), int(Bus.get_value("ctl.lm.rr_slew_trunnion", 0)))
		var rate := float(d["slew_hi_dps"] if int(Bus.get_value("ctl.lm.rr_slew_rate", 1)) == 1 else d["slew_lo_dps"])
		a = _clamped(a + slew.clamp(-Vector2.ONE, Vector2.ONE) * deg_to_rad(rate) * dt)
	elif not tracking and bool(Bus.get_value("lm.guid.rr_designating", false)):
		# The LGC's designate: up to 7°/s, and inside 7° the error's rate.
		var want: Vector2 = Bus.get_value("lm.guid.rr_designate", a)
		var e := _clamped(want) - a
		var r := minf(e.length(), deg_to_rad(float(d["designate_rate_dps"]))) * dt
		if e.length() > 0.0:
			a += e.normalized() * minf(r, e.length())
	elif not tracking:
		pass
	elif locked:
		if visible and in_coverage(target):
			a = target
			track_s += dt
		else:
			locked = false
			track_s = 0.0
	elif visible and in_coverage(target) and los_of(a.x, a.y).angle_to(los_b) <= deg_to_rad(float(d["capture_deg"])):
		locked = true
		track_s = 0.0
		a = target
	shaft = a.x
	trunnion = a.y
	hold_dir = att * los_of(shaft, trunnion)
	data_good = locked and track_s >= float(d["acquisition_s"]) - 1e-6
	no_track = on and not data_good
	var off := los_of(shaft, trunnion).angle_to(los_b)
	var w := deg_to_rad(float(d["beam_3db_deg"])) / 2.0
	# The beam's loss and the range's, dB.
	var db := -10.0 * log(2.0) / log(10.0) * (off / w) * (off / w) - 20.0 * log(maxf(rng, NMI) / NMI) / log(10.0)
	strength = clampf(1.0 + db / 60.0, 0.0, 1.0) if visible else 0.0
	if data_good:
		var cm_v: Array = Bus.get_value("dyn.v_mps", [0.0, 0.0, 0.0])
		var lm_v: Array = Bus.get_value("lm.dyn.v_mps", [0.0, 0.0, 0.0])
		var rel_v := Vector3(float(cm_v[0]) - float(lm_v[0]), float(cm_v[1]) - float(lm_v[1]),
			float(cm_v[2]) - float(lm_v[2]))
		_measure(rng, rel_v.dot(los), d)
	else:
		range_m = 0.0
		range_rate = 0.0
		shaft_cdu = _cdu(shaft)
		trunnion_cdu = _cdu(trunnion)
		los_body = los_of(shaft_cdu, trunnion_cdu)
	_publish()


## A sample of range [param rng] and range rate [param rdot] (m, m/s),
## with the antenna on the line of sight, as the radar reads them: this
## flight's biases, the noise, the counts.
func _measure(rng: float, rdot: float, d: Dictionary) -> void:
	var near := rng < float(d["low_scale_nmi"]) * NMI
	var r := rng
	var rd := rdot
	var s := shaft
	var t := trunnion
	if not ideal:
		var limit := float(d["range_bias_near_ft"]) * FT if near \
			else maxf(float(d["range_bias_ft"]) * FT, float(d["range_bias_frac"]) * rng)
		r += bias_range_k * limit / 3.0 + _rng.randfn(0.0, float(d["range_noise_ft"]) * FT)
		rd += bias_rate + _rng.randfn(0.0, float(d["rate_noise_fps"]) * FT)
		var n := deg_to_rad(float(d["angle_noise_deg"]))
		s += bias_shaft + _rng.randfn(0.0, n)
		t += bias_trunnion + _rng.randfn(0.0, n)
	var rc := float(d["range_count_near_ft"] if near else d["range_count_far_ft"]) * FT
	var vc := float(d["rate_count_fps"]) * FT
	range_m = roundf(r / rc) * rc
	range_rate = roundf(rd / vc) * vc
	shaft_cdu = _cdu(s)
	trunnion_cdu = _cdu(t)
	los_body = los_of(shaft_cdu, trunnion_cdu)


static func _cdu(a: float) -> float:
	return roundf(a / CDU_RAD) * CDU_RAD


## The Moon stands between the LM at [param r] and the CSM [param d] from
## it (m, Moon-centred): the line between them passes inside its
## reference sphere.
static func blocked(r: Array, d: Array) -> bool:
	var dd := float(d[0]) * float(d[0]) + float(d[1]) * float(d[1]) + float(d[2]) * float(d[2])
	var rd := float(r[0]) * float(d[0]) + float(r[1]) * float(d[1]) + float(r[2]) * float(d[2])
	var k := clampf(-rd / maxf(dd, 1e-9), 0.0, 1.0)
	var p := [float(r[0]) + float(d[0]) * k, float(r[1]) + float(d[1]) * k, float(r[2]) + float(d[2]) * k]
	return p[0] * p[0] + p[1] * p[1] + p[2] * p[2] < Bodies.R_MOON * Bodies.R_MOON


func _publish() -> void:
	Bus.set_value("lm.rr.range_m", range_m)
	Bus.set_value("lm.rr.range_rate_mps", range_rate)
	Bus.set_value("lm.rr.shaft_rad", shaft_cdu)
	Bus.set_value("lm.rr.trunnion_rad", trunnion_cdu)
	Bus.set_value("lm.rr.los_body", los_body)
	Bus.set_value("lm.rr.data_good", data_good)
	Bus.set_value("lm.rr.locked", locked)
	Bus.set_value("lm.rr.no_track", no_track)
	Bus.set_value("lm.rr.signal", strength)


func snapshot() -> Dictionary:
	return {"shaft": shaft, "trunnion": trunnion, "locked": locked, "track_s": track_s,
		"hold": [hold_dir.x, hold_dir.y, hold_dir.z], "mode_was": _mode_was, "tracking_was": _tracking_was,
		"ideal": ideal, "bias": [bias_range_k, bias_rate, bias_shaft, bias_trunnion], "rng_state": str(_rng.state),
		"out": [data_good, range_m, range_rate, shaft_cdu, trunnion_cdu, strength, no_track]}


## Its antenna, its lock and its errors as they were, and what it measured
## at the end of the step the checkpoint was taken after, which the LGC's
## next mark reads.
func restore(d: Dictionary) -> void:
	if not d.has("shaft"):
		tick(0.0)
		return
	shaft = float(d["shaft"])
	trunnion = float(d["trunnion"])
	locked = bool(d["locked"])
	track_s = float(d["track_s"])
	var h: Array = d["hold"]
	hold_dir = Vector3(h[0], h[1], h[2])
	_mode_was = int(d["mode_was"])
	_tracking_was = bool(d["tracking_was"])
	ideal = bool(d["ideal"])
	var b: Array = d["bias"]
	bias_range_k = float(b[0])
	bias_rate = float(b[1])
	bias_shaft = float(b[2])
	bias_trunnion = float(b[3])
	_rng.state = str(d["rng_state"]).to_int()
	var o: Array = d["out"]
	data_good = bool(o[0])
	range_m = float(o[1])
	range_rate = float(o[2])
	shaft_cdu = float(o[3])
	trunnion_cdu = float(o[4])
	strength = float(o[5])
	no_track = bool(o[6])
	los_body = los_of(shaft_cdu, trunnion_cdu)
	_publish()

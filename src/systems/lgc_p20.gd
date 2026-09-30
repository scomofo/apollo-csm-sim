## Luminary's P20, rendezvous navigation, for the LGC (slice 11d): the
## rendezvous radar acquired and its marks weighted into the LM's state
## vector, or the CSM's, as Luminary 099's P20 did [published: Luminary
## 099, P20-P25 and MEASUREMENT_INCORPORATION; GSOP R-567 sections 4 and
## 5.2]. V37E20E starts it, and it runs on behind the rendezvous programs
## until V56:
##
##   V50N25 00201  the RNDZ RADAR switch isn't at LGC: PRO looks again;
##            ENTER is R23's acquisition by hand, V50N25 00205: the crew
##            slews the antenna onto the CSM and locks on in AUTO TRACK,
##            turns the switch to LGC, and PRO once the NO TRACK light is out
##   R61      the attitude with the LM's +Z on the line of sight to the CSM
##            from the state vectors (VECPOINT): past 15° V50N18 (PRO:
##            KALCMANU's turn; ENTER: none); within it, the DAP's attitude
##            straight away. R65 looks again every 8 s while the DAP is in
##            AUTO and no other program flies the LM, and turns it past 5°
##            (R65_DEG)
##   R21      the antenna designated every 0.5 s to the state vectors' line
##            of sight; within 0.5° the track enable, then the data good
##            awaited; 60 passes without it, alarm 00503, and again
##            [simplified: R24's hexagonal search left out]
##   V50N72   lock-on: the main lobe's check; PRO, and 2.5 s later R22
##   R22      a mark: the radar's range rate, the IMU's attitude, its shaft
##            and trunnion, its range; dropped past 3° from the state
##            vectors' line of sight (alarm 00525) [simplified: V06N05's
##            PRO to take it], or past 30° from +Z (R61 again). Weighted
##            in, range, range rate, shaft and trunnion in turn, each
##            checked against RMAX and VMAX: past them V06N49 shows the
##            change, dR (nmi), dV (ft/s) and the source (1 to 4); PRO takes
##            it, V32 drops the rest of the mark and marks again, V34 ends
##            P20. The next mark comes 64 s after one weighted in, 18 s
##            after one read only
##
## Which state vector moves: the LM's (V80), P20's choice at its start in
## flight, or the CSM's (V81); V95 neither, until V80 or V81. P32 to P35
## let the marks in when they start, and hold them off from their final
## computation to the next program's start (UPDATFLG). The filter
## (RendezvousFilter) starts at the first mark weighted in after W was
## given up, from the pad loads WRENDPOS, WRENDVEL and WSHAFT/WTRUN, which
## V67's V06N99 shows as root sum squares and the crew loads anew (PRO);
## an uplink of either state vector, P12's liftoff, V93 or a load give W
## up. The radar's boresight biases it learns (X789) stay through it.
class_name LgcRendezvousNav
extends RefCounted

## R21's designate cycle and its passes [published: DESLOOP 50 cs,
## MAXTRIES 60]; the track enable within TRACK_ENABLE_DEG [published:
## COS1/2DG].
const DESIGNATE_S := 0.5
const DESIGNATE_PASSES := 60
const TRACK_ENABLE_DEG := 0.5
## The wait for the angle servos after the main lobe's check [published:
## P20LEMWT 250 cs].
const SETTLE_S := 2.5
## The next mark after one weighted in and after one read only, s
## [published: GSOP R-567 p. 5.2-79, about 64 s; derived: R65CNTR 2, 18 s].
const MARK_S := 64.0
const READ_S := 18.0
## R65's pass, s, and R61's turn past this, deg [published: GSOP R-567 p.
## 5.2-80, 2 s and a 6 s wait; COS15DEG]; R65 turns the LM only past
## R65_DEG, leading the line of sight by as much along its motion
## [simplified: Luminary's R65 wrote the attitude to the DAP every pass,
## and its DAP held it within the deadband the crew had chosen, 0.3 or
## 5°; the simulator's DAP comes to rest on its attitude, which a turn
## every 8 s would never let it do].
const R65_S := 8.0
const R65_DEG := 5.0
const R61_DEG := 15.0
## A mark's line of sight within this of the state vectors', deg (alarm
## 00525), and of +Z [published: THREEDEG; LRS22.2's 30DEG].
const DTHETA_DEG := 3.0
const Z_AXIS_DEG := 30.0
## The IMU's angle variance per axis, rad², added to the angles' [published:
## IMUVAR].
const IMUVAR := 1e-6
## Each priority display's verb and noun.
const PRIORITY_VN := {"n25": [50, 25], "manual": [50, 25], "r61": [50, 18], "n72": [50, 72], "n49": [6, 49],
	"v67": [6, 99]}

var lgc: Lgc
## UPDATFLG, VEHUPFLG (true: the LM's), NOUPFLAG.
var updat: bool = true
var update_lm: bool = true
var no_update: bool = false
## Where P20 stands: "" not running; "n25" the switch; "manual" R23;
## "r61" R61's V50N18; "turning" its turn; "designate" and "lock" R21;
## "n72" the lock-on's check; "settle"; "track" R22. R61's turn comes back
## to [member resume]: "designate" at the start, "track" after.
var phase: String = ""
var resume: String = "designate"
var passes: int = 0
var next_get: float = -1.0
var r65_get: float = -1.0
## MARKCTR (N45's R1).
var marks: int = 0
## W's pad loads, per axis: position (m), velocity (m/s), bias (rad)
## (spacecraft.json "rendezvous_navigation").
var w_pos: float = 0.0
var w_vel: float = 0.0
var w_bias: float = 0.0
## RENDWFLG: W valid.
var rendw: bool = false
var filter := RendezvousFilter.new()
## X789: the shaft's and trunnion's bias estimates, rad.
var bias := Vector2.ZERO
## The last change N49 showed: dR (m), dV (m/s), the source.
var n49 := Vector3.ZERO
## A mark waiting on N49: {"t", "meas" [range, rate, shaft, trunnion],
## "att" (the IMU's), "lm", "cm" (the state vectors at the mark, arrays),
## "i" (the measurement shown), "dx" (the one shown), "e" (E with it)}.
var pending: Dictionary = {}
## V67's loads, until PRO; empty when none.
var v67_load: Array = []
## The priority display up ("" none) and the program's display it covers.
var priority: String = ""
var covered: Dictionary = {}
## The attitude R61 turns to.
var r61_target: Quaternion = Quaternion.IDENTITY
## The attitude R61 or R65 last gave the DAP, which P20 gives up when it
## ends.
var held_q: Quaternion = Quaternion.IDENTITY
## What P20 commands the radar: designating, its angles, the track enable.
var designating: bool = false
var designate := Vector2.ZERO
var track_enable: bool = false


func _init(computer: Lgc) -> void:
	lgc = computer
	var d := SpacecraftData.section("rendezvous_navigation")
	w_pos = float(d["wrendpos_m"])
	w_vel = float(d["wrendvel_mps"])
	w_bias = float(d["wbias_rad"])


func running() -> bool:
	return phase != ""


## V37E20E: in flight the LM's state vector is the one to update; the
## switch looked at, then R61.
func start() -> void:
	updat = true
	update_lm = true
	marks = 0
	passes = 0
	pending = {}
	_release()
	_look_at_switch()


## V56 (and the LGC's power-down): P20 ends, and the DAP holds the LM
## where it is, no longer turning it with the line of sight.
func stop() -> void:
	phase = ""
	pending = {}
	designating = false
	track_enable = false
	if priority != "":
		_release()
	if lgc.auto_active and lgc.auto_target.is_equal_approx(held_q):
		lgc.auto_active = false
		lgc.hold_q = lgc._att()
	_publish()


func _look_at_switch() -> void:
	if int(Bus.get_value("ctl.lm.rr_mode", 1)) != 0:
		phase = "n25"
		_show("n25", 50, 25)
		return
	_r61("designate")


## R61: the attitude with +Z on the line of sight, past R61_DEG by its
## V50N18, within it the DAP's straight away; then on to [param then]
## ("designate" at P20's start, "track" after).
func _r61(then: String) -> void:
	resume = then
	var los := _los()
	if los == Vector3.ZERO:
		_resume()
		return
	var att := lgc._att()
	r61_target = _tracking_attitude(att, los)
	if rad_to_deg((Basis(att) * Vector3.BACK).angle_to(los)) > R61_DEG:
		phase = "r61"
		_show("r61", 50, 18)
		return
	if lgc.mode() == 2:
		_hold(r61_target)
	if then == "designate":
		_designate_start()


## On after R61: R21's designate, or R22's marks again.
func _resume() -> void:
	if resume == "track":
		phase = "track"
		next_get = lgc._now()
	else:
		_designate_start()


## The attitude [param att] turned the least way to put +Z along
## [param los] (Luminary's VECPOINT).
static func _tracking_attitude(att: Quaternion, los: Vector3) -> Quaternion:
	var z := Basis(att) * Vector3.BACK
	return (Imu.arc(z, los.normalized()) * att).normalized()


## The DAP holds [param q] in AUTO.
func _hold(q: Quaternion) -> void:
	held_q = q
	lgc.auto_target = q
	lgc.desired_q = q
	lgc.auto_active = true


func _designate_start() -> void:
	phase = "designate"
	passes = 0
	track_enable = false
	next_get = lgc._now()


## The line of sight to the CSM from the LGC's two state vectors
## (inertial, unit), or zero without them.
func _los() -> Vector3:
	if lgc.nav == null or lgc._csm_now() == null:
		return Vector3.ZERO
	return Rendezvous.rel_pos(lgc.nav, lgc.csm_nav).normalized()


## The priority display [param kind], V[param v] N[param n], over the
## program's.
func _show(kind: String, v: int, n: int) -> void:
	if priority == "":
		covered = lgc.dsky.program_display().duplicate()
	priority = kind
	lgc.dsky.show(v, n, true)


## The priority display answered: the program's display back.
func _release() -> void:
	if priority == "":
		return
	priority = ""
	if not covered.is_empty():
		lgc.dsky.show(int(covered["v"]), int(covered["n"]), bool(covered["flash"]))
	elif lgc.program == 20:
		lgc.dsky.show(16, 54)
	else:
		lgc.dsky.blank()
	covered = {}


## The crew's answer to the priority display: "pro", "enter" (V50's
## ENTER), "v32" or "v34".
func answer(key: String) -> void:
	var kind := priority
	match kind:
		"n25":
			_release()
			if key == "pro":
				_look_at_switch()
			elif key == "enter":
				# R23: the tracker enabled for the crew's lock-on by hand.
				phase = "manual"
				track_enable = true
				designating = false
				_show("manual", 50, 25)
			else:
				stop()
		"manual":
			if key == "pro" and bool(Bus.get_value("lm.rr.data_good", false)):
				_release()
				phase = "settle"
				next_get = lgc._now() + SETTLE_S
			elif key == "v34":
				_release()
				stop()
		"r61":
			_release()
			if key == "pro":
				_hold(r61_target)
				lgc._plan_via()
				phase = "turning"
			elif key == "enter":
				_resume()
			else:
				stop()
		"n72":
			_release()
			if key == "pro":
				phase = "settle"
				next_get = lgc._now() + SETTLE_S
			else:
				_designate_start()
		"n49":
			_release()
			if key == "pro":
				_accept_pending()
			elif key == "v32":
				# Recycle: the rest of the mark dropped, and a mark at once.
				_finish_mark(false)
				next_get = lgc._now()
			else:
				_finish_mark(false)
				stop()
		"v67":
			_release()
			if key == "pro" and v67_load.size() == 3:
				w_pos = float(v67_load[0])
				w_vel = float(v67_load[1])
				w_bias = float(v67_load[2])
				rendw = false
			v67_load = []


## V80, V81, V95, V93, V67 [published: Luminary 099's EXTENDED_VERBS].
func verb(v: int) -> bool:
	match v:
		80:
			update_lm = true
			no_update = false
		81:
			update_lm = false
			no_update = false
		95:
			no_update = true
		93:
			rendw = false
		67:
			v67_load = []
			_show("v67", 6, 99)
		_:
			return false
	_publish()
	return true


## V25N99's load: the per-axis values the crew keys (R1 m, R2 m/s, R3 rad).
func noun_load(_n: int, idx: int, value: float) -> bool:
	if priority != "v67":
		return false
	if v67_load.size() != 3:
		v67_load = [w_pos, w_vel, w_bias]
	v67_load[idx] = value
	return true


## W given up (an uplink, P12's liftoff): the next mark starts it again.
func invalidate() -> void:
	rendw = false


## The rendezvous programs P32 to P35 start: marks may update (P20FLGON).
func targeting_started() -> void:
	updat = true


## Their final computation: no mark weighted in until the next starts.
func final_computation() -> void:
	updat = false


func noun_values(n: int) -> Variant:
	var v: Variant = null
	match n:
		25:
			v = [205.0 if phase == "manual" else 201.0, 0.0, 0.0]
		45:
			var tfi := lgc.maneuver_tig - lgc._now() if lgc.maneuver_valid else 0.0
			v = [marks, tfi, wrapf(lgc.icdu().z, 0.0, 360.0)]
		49:
			v = [n49.x, n49.y, n49.z]
		72:
			var s := float(Bus.get_value("lm.rr.shaft_rad", 0.0))
			var t := float(Bus.get_value("lm.rr.trunnion_rad", 0.0))
			v = [wrapf(360.0 - rad_to_deg(t), 0.0, 360.0), wrapf(rad_to_deg(s), 0.0, 360.0), 0.0]
		78:
			v = [float(Bus.get_value("lm.rr.range_m", 0.0)), float(Bus.get_value("lm.rr.range_rate_mps", 0.0)), 0.0]
		99:
			var r := filter.rss() if rendw else Vector3(w_pos, w_vel, w_bias) * Vector3(sqrt(3.0), sqrt(3.0), sqrt(2.0))
			v = v67_load if v67_load.size() == 3 else [r.x, r.y, r.z]
	return v


## Each step while P20 runs.
func step() -> void:
	if phase == "":
		return
	var now := lgc._now()
	match phase:
		"turning":
			# Done, or LGC MODE out of AUTO: the crew have the LM.
			if lgc.mode() != 2 or (not lgc.kal_turning() and lgc.maneuver_vias.is_empty()
					and lgc._att_error(r61_target) < deg_to_rad(1.0)):
				_resume()
		"designate", "lock":
			_designate(now)
		"settle":
			if now >= next_get:
				phase = "track"
				next_get = now
		"track":
			if not bool(Bus.get_value("lm.rr.data_good", false)):
				# Lost: designate again (R25, R21).
				_designate_start()
			else:
				_r65(now)
				if now >= next_get - 1e-6 and pending.is_empty() and priority == "" and not _burning():
					_mark(now)
	_publish()


func _burning() -> bool:
	return lgc.engine_on or lgc.rcs_burn


## R21: designate to the state vectors' line of sight every DESIGNATE_S;
## the track enable once the antenna's within TRACK_ENABLE_DEG, then the
## lock-on awaited; DESIGNATE_PASSES passes, and alarm 00503.
func _designate(now: float) -> void:
	if bool(Bus.get_value("lm.rr.data_good", false)) and track_enable:
		designating = false
		phase = "n72"
		_show("n72", 50, 72)
		return
	if now < next_get - 1e-6:
		return
	next_get = now + DESIGNATE_S
	passes += 1
	if passes > DESIGNATE_PASSES:
		lgc._alarm(503)
		_designate_start()
		return
	var los := _los()
	if los == Vector3.ZERO:
		return
	designate = RendezvousRadar.angles_of(Basis(lgc._att()).inverse() * los)
	var at := Vector2(float(Bus.get_value("lm.rr.shaft_rad", 0.0)), float(Bus.get_value("lm.rr.trunnion_rad", 0.0)))
	if phase == "designate" and RendezvousRadar.los_of(at.x, at.y).angle_to(RendezvousRadar.los_of(designate.x, designate.y)) \
			<= deg_to_rad(TRACK_ENABLE_DEG):
		phase = "lock"
		track_enable = true
		designating = false
	elif phase == "designate":
		designating = true
		track_enable = false


## R65: keep +Z on the line of sight while the DAP is in AUTO and no
## program flies the LM; past R61_DEG, R61's V50N18.
func _r65(now: float) -> void:
	if now < r65_get - 1e-6:
		return
	r65_get = now + R65_S
	if lgc.mode() != 2 or _flying() or lgc.kal_turning() or not lgc.maneuver_vias.is_empty():
		return
	var los := _los()
	if los == Vector3.ZERO:
		return
	var att := lgc._att()
	var off := rad_to_deg((Basis(att) * Vector3.BACK).angle_to(los))
	if off > R61_DEG:
		_r61("track")
	elif off > R65_DEG:
		# Ahead of the line of sight by R65_DEG, along its turning.
		var r := Rendezvous.rel_pos(lgc.nav, lgc.csm_nav)
		var w := r.cross(Rendezvous.rel_vel(lgc.nav, lgc.csm_nav))
		var lead := los.rotated(w.normalized(), deg_to_rad(R65_DEG)) if w.length() > 0.0 else los
		_hold(_tracking_attitude(att, lead))
		lgc._plan_via()


## Another program flies the LM: a burn's, the descent's, the ascent's, an
## abort's, or the alignment's turns.
func _flying() -> bool:
	var p := lgc.program
	return p in lgc.thrusting_programs() or p in Lgc.DESCENT or p == Lgc.ASCENT or p in Lgc.ABORTS or p in [52, 57]


# --- R22: the marks -----------------------------------------------------------------

## A mark: read the radar and, with the marks let in, weigh it in.
func _mark(now: float) -> void:
	var s := float(Bus.get_value("lm.rr.shaft_rad", 0.0))
	var t := float(Bus.get_value("lm.rr.trunnion_rad", 0.0))
	var att := lgc._att()
	var nb := Basis(att)
	var los := _los()
	var rr_los: Vector3 = nb * RendezvousRadar.los_of(s, t)
	if los == Vector3.ZERO or rr_los.angle_to(los) > deg_to_rad(DTHETA_DEG):
		# Alarm 00525: a side lobe, or a state vector far off.
		lgc._alarm(525)
		_designate_start()
		return
	if RendezvousRadar.los_of(s, t).angle_to(Vector3.BACK) > deg_to_rad(Z_AXIS_DEG):
		next_get = now + READ_S
		if not _flying():
			_r61("track")
		return
	if no_update or not updat:
		next_get = now + READ_S
		return
	var lm := lgc.nav.clone()
	var cm: Trajectory = lgc._csm_now().clone()
	var upd := lm if update_lm else cm
	if not rendw:
		filter.init(upd, w_pos, w_vel, w_bias)
		rendw = true
		marks = 0
	else:
		filter.carry(upd)
	pending = {"t": lm.t, "meas": [float(Bus.get_value("lm.rr.range_m", 0.0)),
		float(Bus.get_value("lm.rr.range_rate_mps", 0.0)), s, t], "att": att,
		"lm": Array(lm.s), "cm": Array(cm.s), "s0": Array(upd.s), "i": 0}
	_incorporate()


## Weigh in the mark's measurements from the pending one on, each checked
## against RMAX and VMAX; N49 past them.
func _incorporate() -> void:
	var d := SpacecraftData.section("rendezvous_navigation")
	while int(pending["i"]) < 4:
		var i := int(pending["i"])
		var m := _measurement(i)
		var u := RendezvousFilter.update(filter.e, m["b"], m["dq"], m["var"])
		var dx: PackedFloat64Array = u["dx"]
		var dr := Vector3(dx[0], dx[1], dx[2]).length()
		var dv := Vector3(dx[3], dx[4], dx[5]).length()
		pending["dx"] = dx
		pending["e"] = u["e"]
		if dr > float(d["rmax_m"]) or dv > float(d["vmax_mps"]):
			n49 = Vector3(dr, dv, i + 1)
			_show("n49", 6, 49)
			return
		_apply(dx, u["e"])
	_finish_mark(true)


## PRO at N49: the measurement shown weighed in, and on to the rest.
func _accept_pending() -> void:
	if pending.is_empty():
		return
	_apply(pending["dx"], pending["e"])
	_incorporate()


func _apply(dx: PackedFloat64Array, e: PackedFloat64Array) -> void:
	var key := "lm" if update_lm else "cm"
	var s: Array = pending[key]
	for j in 6:
		s[j] = float(s[j]) + dx[j]
	bias += Vector2(dx[6], dx[7])
	filter.e = e
	pending["i"] = int(pending["i"]) + 1


## The mark done ([param counted] all of it weighed in, or its rest
## dropped): the state vector at its time moved into the LGC's own now,
## carried on to first order, as the CMC's marks are; the next mark in
## MARK_S.
func _finish_mark(counted: bool) -> void:
	if pending.is_empty():
		return
	var tr: Trajectory = lgc.nav if update_lm else lgc.csm_nav
	var after: Array = pending["lm" if update_lm else "cm"]
	var s0: Array = pending["s0"]
	var dt := tr.t - float(pending["t"])
	for j in 3:
		var dp := float(after[j]) - float(s0[j])
		var dv := float(after[3 + j]) - float(s0[3 + j])
		tr.s[j] += dp + dv * dt
		tr.s[3 + j] += dv
	var anchor := filter.anchor
	if anchor != null:
		for j in 6:
			anchor.s[j] = float(after[j])
	if int(pending["i"]) > 0:
		marks += 1 if counted else 0
	pending = {}
	next_get = lgc._now() + MARK_S


## Measurement [param i] of the pending mark: its gradient b (8), residual
## dq and variance var, scaled as Luminary's LSR22.3 scales them, the signs
## the updated vehicle's [published: GSOP R-567 Eqs. 2.4.2 to 2.4.9].
func _measurement(i: int) -> Dictionary:
	var d := SpacecraftData.section("rendezvous_navigation")
	var lm: Array = pending["lm"]
	var cm: Array = pending["cm"]
	var meas: Array = pending["meas"]
	var nb := Basis(pending["att"] as Quaternion)
	var mx := nb.x
	var my := nb.y
	var mz := nb.z
	var r := Vector3(float(cm[0]) - float(lm[0]), float(cm[1]) - float(lm[1]), float(cm[2]) - float(lm[2]))
	var vlc := Vector3(float(cm[3]) - float(lm[3]), float(cm[4]) - float(lm[4]), float(cm[5]) - float(lm[5]))
	var rlc := r.length()
	var ulc := r / rlc
	var sgn := -1.0 if update_lm else 1.0
	var b := PackedFloat64Array()
	b.resize(RendezvousFilter.N)
	var dq := 0.0
	var v := 0.0
	var sin_t := -ulc.dot(my)
	var rxz := rlc * sqrt(maxf(1.0 - sin_t * sin_t, 1e-12))
	match i:
		0:
			dq = float(meas[0]) - rlc
			for j in 3:
				b[j] = sgn * ulc[j]
			v = maxf(rlc * rlc * float(d["rangevar"]), float(d["rvarmin_m2"]))
		1:
			var rdot := vlc.dot(ulc)
			dq = rlc * (float(meas[1]) - rdot)
			var b0 := ulc.cross(vlc).cross(ulc)
			for j in 3:
				b[j] = sgn * b0[j]
				b[3 + j] = sgn * rlc * ulc[j]
			v = rlc * rlc * maxf(float(meas[1]) * float(meas[1]) * float(d["ratevar"]), float(d["vvarmin_m2s2"]))
		2:
			var beta := atan2(ulc.dot(mx), ulc.dot(mz))
			dq = rxz * wrapf(float(meas[2]) - beta - bias.x, -PI, PI)
			var b0 := my.cross(ulc).normalized()
			for j in 3:
				b[j] = sgn * b0[j]
			b[6] = rxz
			v = rxz * rxz * (float(d["shaftvar_rad2"]) + IMUVAR)
		3:
			dq = rxz * (float(meas[3]) - asin(clampf(sin_t, -1.0, 1.0)) - bias.y)
			var b0 := my.cross(ulc).cross(ulc)
			for j in 3:
				b[j] = sgn * b0[j]
			b[7] = rxz
			v = rxz * rxz * (float(d["trunvar_rad2"]) + IMUVAR)
	return {"b": b, "dq": dq, "var": v}


func _publish() -> void:
	Bus.set_value("lm.guid.rr_designating", designating and phase in ["designate", "lock"])
	Bus.set_value("lm.guid.rr_designate", designate)
	Bus.set_value("lm.guid.rr_track_enable", track_enable and phase != "")
	Bus.set_value("lm.guid.rr_phase", phase)
	Bus.set_value("lm.guid.rr_update", "none" if no_update else ("lm" if update_lm else "csm"))
	Bus.set_value("lm.guid.rr_w_valid", rendw)
	Bus.set_value("lm.guid.rr_wpos_m", w_pos)
	Bus.set_value("lm.guid.rr_marks", marks)


func snapshot() -> Dictionary:
	return {"updat": updat, "update_lm": update_lm, "no_update": no_update, "phase": phase, "resume": resume,
		"passes": passes,
		"next_get": next_get, "r65_get": r65_get, "marks": marks, "w": [w_pos, w_vel, w_bias], "rendw": rendw,
		"filter": filter.snapshot(), "bias": [bias.x, bias.y], "n49": [n49.x, n49.y, n49.z],
		"pending": _pending_snapshot(), "v67_load": v67_load.duplicate(), "priority": priority,
		"covered": covered.duplicate(), "r61": [r61_target.x, r61_target.y, r61_target.z, r61_target.w],
		"held": [held_q.x, held_q.y, held_q.z, held_q.w],
		"designating": designating, "designate": [designate.x, designate.y], "track_enable": track_enable}


func _pending_snapshot() -> Dictionary:
	if pending.is_empty():
		return {}
	var p := pending.duplicate(true)
	var q: Quaternion = p["att"]
	p["att"] = [q.x, q.y, q.z, q.w]
	if p.has("dx"):
		p["dx"] = Array(p["dx"])
		p["e"] = Array(p["e"])
	return p


func restore(d: Dictionary) -> void:
	updat = bool(d.get("updat", true))
	update_lm = bool(d.get("update_lm", true))
	no_update = bool(d.get("no_update", false))
	phase = str(d.get("phase", ""))
	resume = str(d.get("resume", "designate"))
	passes = int(d.get("passes", 0))
	next_get = float(d.get("next_get", -1.0))
	r65_get = float(d.get("r65_get", -1.0))
	marks = int(d.get("marks", 0))
	var w: Array = d.get("w", [w_pos, w_vel, w_bias])
	w_pos = float(w[0])
	w_vel = float(w[1])
	w_bias = float(w[2])
	rendw = bool(d.get("rendw", false))
	filter = RendezvousFilter.new()
	filter.restore(d.get("filter", {}))
	var b: Array = d.get("bias", [0.0, 0.0])
	bias = Vector2(b[0], b[1])
	var n: Array = d.get("n49", [0.0, 0.0, 0.0])
	n49 = Vector3(n[0], n[1], n[2])
	pending = (d.get("pending", {}) as Dictionary).duplicate(true)
	if not pending.is_empty():
		var q: Array = pending["att"]
		pending["att"] = Quaternion(q[0], q[1], q[2], q[3])
		if pending.has("dx"):
			pending["dx"] = PackedFloat64Array(pending["dx"])
			pending["e"] = PackedFloat64Array(pending["e"])
	v67_load = (d.get("v67_load", []) as Array).duplicate()
	priority = str(d.get("priority", ""))
	covered = (d.get("covered", {}) as Dictionary).duplicate()
	var r: Array = d.get("r61", [0.0, 0.0, 0.0, 1.0])
	r61_target = Quaternion(r[0], r[1], r[2], r[3])
	var h: Array = d.get("held", [0.0, 0.0, 0.0, 1.0])
	held_q = Quaternion(h[0], h[1], h[2], h[3])
	designating = bool(d.get("designating", false))
	var g: Array = d.get("designate", [0.0, 0.0])
	designate = Vector2(g[0], g[1])
	track_enable = bool(d.get("track_enable", false))
	_publish()


## The priority display up again over the program's, once the LGC's
## restore has put that up.
func show_priority() -> void:
	if PRIORITY_VN.has(priority):
		lgc.dsky.show(PRIORITY_VN[priority][0], PRIORITY_VN[priority][1], true)

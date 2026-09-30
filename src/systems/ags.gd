## The LM's Abort Guidance Section (slice 7d's attitude hold and ΔV count;
## slice 11e its flight program): the Abort Sensor Assembly's gyros and
## accelerometers, the Abort Electronics Assembly running FP6, Apollo 11's
## and 12's flight program, and the DEDA on panel 6 [published: LM AGS
## Programmed Equations Document, Flight Program 6, 11176-6041-T0-00; LM/AGS
## Operating Manual, Flight Program 6, 11176-6033-T000 rev. 1].
##
## It runs while the LM's buses are powered and its breakers are in
## (ctl.lm.ags). Its attitude reference is strapped down to the LM
## [simplified: the ASA's gyros and accelerometers ideal]: the direction
## cosines of the body axes in its own inertial frame, which the crew set
## with the DEDA's address 400 (the submode, S00): +30000 aligns it to the
## PGNS's platform through the IMU's gimbal angles, as their CDUs read them
## (the frame is then the stable member, off by the platform's own
## misalignment), for two seconds, then back to +00000; +50000 lays it on
## the LM's body axes until +00000 [simplified: the lunar align (+40000)
## and the calibrations (+60000, +70000) left out]. Powering up, it lays
## its frame on the body axes. AGS ALIGN, slice 7d's proxy, is the body
## axis align and the ΔV count's zeroing in one.
##
## Its equations (AgsFp6) navigate the LM on the accelerometers and
## spherical gravity and the CSM by its ephemeris, every two seconds, and
## solve the guidance routine the DEDA's 410 selects: orbit insertion,
## CSI, CDH, TPI and external ΔV. 414+10000 takes the LGC's V47 downlink
## (lm.lgc.ags_downlink) for both state vectors. Every step it works FP6's
## 40-ms logic: the attitude errors of the submode (400: attitude hold,
## +10000 guidance steering, +20000 Z axis steering), limited to 15 deg,
## and the engine command. With the guidance control switch at AGS
## (ctl.lm.guid_cont 1) the errors fly the LM, or the docked stack, on the
## LM's jets; the ACA commands rate while out of detent, and in FREE
## (ctl.lm.mode 0) it fires the jets itself [simplified: one mode control
## for both guidance systems]. The AGS commands the engine only in AUTO with
## ABORT or ABORT STAGE latched in and guidance steering selected: ON once
## ullage has been sensed for 1K9 cycles, OFF when the velocity to be
## gained along X, counted down every step, falls under the ascent engine's
## tail-off (1.6875 ft/s) with the whole under 70 ft/s; otherwise it
## follows the engines as they are. On the surface ABORT STAGE holds the
## attitude until the ascent engine is 2.5 s alight. The DEDA's
## accumulated ΔV along X (470) is lm.ags.dv_x_mps, zeroed at AGS ALIGN.
##
## Reads:  ctl.lm.ags, ctl.lm.ags_align (momentary), ctl.lm.guid_cont,
##         ctl.lm.mode, ctl.lm.rhc, lm.sys.powered, lm.dyn.att_q,
##         lm.dyn.omega, lm.dyn.dv_step, lm.imu.icdu_deg, lm.dps.on,
##         lm.aps.on, lm.aps.abort_armed (ABORT STAGE), lm.dps.abort_armed
##         (ABORT), lm.lgc.ags_downlink, time.get_s (and what
##         Lgc.jet_authority() reads)
## Writes: lm.ags.on, lm.ags.rcs_rot_cmd, lm.ags.dap_busy,
##         lm.ags.att_error_deg, lm.ags.dv_x_mps, lm.ags.engine_on,
##         lm.ags.s00, lm.ags.s10, lm.ags.pgns_aligned (the frame last
##         laid on the platform), lm.ags.initialized (state vectors
##         taken), lm.deda.addr, lm.deda.data, lm.deda.opr_err
class_name Ags
extends Node

## The ACA's full-scale rate, rad/s (the LGC's own).
const RATE_HOLD := AgcCore.RATE_HOLD
const DEADBAND := AgcCore.ATT_DEADBAND
const REST_RATE := AgcCore.REST_RATE
## FP6's 40-ms constants (LM-5's): the attitude errors' limit (4K21, rad),
## the attitude held after the ascent engine lights (4K23, 62 counts of
## 40 ms, s), the ascent engine's cutoff impulse (4K25, ft/s) and the
## velocity to be gained the engine may cut off under (4K26, ft/s).
const ERROR_LIMIT := 0.2618103
const STAGE_HOLD := 62 * 0.04
const CUTOFF_IMPULSE := 1.6875
const CUTOFF_VG := 70.0
## The AGS to PGNS align's time, s; the DEDA's service, every half second
## (branches 12, 24, 36 and 48).
const ALIGN_S := 2.0
const DEDA_S := 0.5
## The DEDA's words (octal address): [what, quantization]. ft100: 100 ft;
## fps: 0.1 ft/s; min: 0.1 min; cmin: 0.01 min; nmi: 0.1 nmi; cdeg: 0.01
## deg; count: 1 (FP6's Table 9.1).
const WORDS := {
	"211": ["disp.y", "ft100"], "223": ["j25", "ft100"], "224": ["j7", "ft100"], "225": ["j8", "ft100"],
	"226": ["j9", "ft100"], "231": ["j5", "ft100"], "232": ["j16", "ft100"], "233": ["j21", "ft100"],
	"240": ["r_l.0", "ft100"], "241": ["r_l.1", "ft100"], "242": ["r_l.2", "ft100"],
	"244": ["r_e.0", "ft100"], "245": ["r_e.1", "ft100"], "246": ["r_e.2", "ft100"],
	"254": ["t_l", "min"], "272": ["t_e", "min"], "274": ["j29", "min"], "275": ["j1", "min"],
	"260": ["v_l.0", "fps"], "261": ["v_l.1", "fps"], "262": ["v_l.2", "fps"], "263": ["disp.v_py", "fps"],
	"264": ["v_e.0", "fps"], "265": ["v_e.1", "fps"], "266": ["v_e.2", "fps"], "267": ["disp.vg_mag", "fps"],
	"270": ["disp.v_y0", "fps"], "277": ["disp.xi", "cdeg"], "303": ["angle", "cdeg"],
	"306": ["j4", "cmin"], "307": ["j6", "cmin"], "310": ["t_delta", "cmin"], "311": ["disp.t_r", "cmin"],
	"312": ["j3", "cmin"], "313": ["disp.t_perg", "cmin"], "314": ["disp.dr", "nmi"], "315": ["disp.q_a", "nmi"],
	"316": ["j18", "nmi"], "317": ["disp.range", "nmi"], "337": ["disp.h", "nmi"],
	"340": ["r.0", "ft100"], "341": ["r.1", "ft100"], "342": ["r.2", "ft100"],
	"344": ["r_c.0", "ft100"], "345": ["r_c.1", "ft100"], "346": ["r_c.2", "ft100"], "347": ["disp.r_f", "ft100"],
	"360": ["v.0", "fps"], "361": ["v.1", "fps"], "362": ["v.2", "fps"],
	"364": ["v_c.0", "fps"], "365": ["v_c.1", "fps"], "366": ["v_c.2", "fps"], "367": ["disp.hdot", "fps"],
	"371": ["dv_second", "fps"], "372": ["disp.t_a0", "min"], "373": ["t_ig", "min"], "377": ["t", "min"],
	"402": ["dr_second", "nmi"], "403": ["disp.q_lt", "nmi"], "433": ["disp.v", "fps"],
	"440": ["disp.range_rate", "fps"], "450": ["j28_1", "fps"], "451": ["j28_2", "fps"], "452": ["j28_3", "fps"],
	"464": ["j22", "fps"], "465": ["j23", "fps"], "470": ["vd.0", "fps"], "471": ["vd.1", "fps"],
	"472": ["vd.2", "fps"], "477": ["disp.rdot_a", "fps"], "500": ["dvg.0", "fps"], "501": ["dvg.1", "fps"],
	"502": ["dvg.2", "fps"], "503": ["j17", "fps"], "616": ["k9", "count"],
}
const QUANTUM := {"ft100": 100.0, "fps": 0.1, "min": 6.0, "cmin": 0.6, "nmi": 607.6115, "cdeg": 0.01,
	"count": 1.0}
## The selectors (octal address): the digit keyed first after the sign.
const SELECTORS := ["400", "407", "410", "411", "412", "413", "414", "415", "416", "417", "507", "623"]

var fp6 := AgsFp6.new()
var deda := Deda.new()
## The AGS's inertial frame: its axes (columns) in ECI.
var frame: Basis = Basis.IDENTITY
## S00 (400): 0 attitude hold, 1 guidance steering, 2 Z axis steering;
## 3 the AGS to PGNS align, 5 the body axis align.
var s00: int = 0
## S14 (414): 1 the downlink's state vectors awaited, 2 the LM's and 3 the
## CSM's from the DEDA's cells.
var s14: int = 0
## The attitude hold's X and Z axes (AGS frame), and whether they are
## captured (δ5).
var hold_x := Vector3(1, 0, 0)
var hold_z := Vector3(0, 0, 1)
var hold_set: bool = false
## How long the attitude has been held since the ascent engine lit (μ6's
## count, s).
var mu6: float = 0.0
## The sensed velocity accumulated along each body axis (V_d, ft/s), its
## value at the last cycle (V_D), and the velocity to be gained along each
## body axis then plus V_D (V_g).
var v_d := PackedFloat64Array([0.0, 0.0, 0.0])
var v_dd := PackedFloat64Array([0.0, 0.0, 0.0])
var v_g := PackedFloat64Array([0.0, 0.0, 0.0])
## The AEA's engine command (E/ON) and attitude errors (rad, body axes).
var engine_on: bool = false
var errors := Vector3.ZERO
## The frame was last laid on the PGNS's platform (400+30000's two seconds
## done), not on the body axes.
var pgns_aligned: bool = false
## The time into the two-second cycle, the DEDA's half second and the
## AGS to PGNS align, s.
var cycle_t: float = 0.0
var deda_t: float = 0.0
var align_t: float = 0.0
## The sensed ΔV this cycle (ft/s, AGS frame).
var dv_cycle := PackedFloat64Array([0.0, 0.0, 0.0])
var _on: bool = false
var _align_was: bool = false
var _rhc_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.POWER_GUIDANCE)
	SimClock.add_ticker(sense, SimClock.Stage.DEPENDENT)
	_publish(Vector3.ZERO, false)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)
	SimClock.remove_ticker(sense)


func _att() -> Quaternion:
	return Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY)


func tick(dt: float) -> void:
	var on := bool(Bus.get_value("lm.sys.powered", false)) and bool(Bus.get_value("ctl.lm.ags", false))
	var q := _att()
	if on and not _on:
		_power_on(q)
	_on = on
	if not on:
		_publish(Vector3.ZERO, false)
		return
	var align := bool(Bus.get_value("ctl.lm.ags_align", false))
	if align and not _align_was:
		# AGS ALIGN: 400+50000, 400+00000 and the ΔV count zeroed.
		frame = Basis(q)
		pgns_aligned = false
		s00 = 0
		hold_set = false
		v_d = PackedFloat64Array([0.0, 0.0, 0.0])
	_align_was = align
	deda_t += dt
	if deda_t >= DEDA_S:
		deda_t = fmod(deda_t, DEDA_S)
		_serve_deda()
	_aligning(dt, q)
	var follow := _attitude_errors(q, dt)
	var cmd := _control(follow)
	_publish(cmd[0], cmd[1])


## Stage DEPENDENT, after Dynamics stepped: what the ASA sensed in the
## step, shared by time among the two-second cycles it spans (a coasting
## step spans many), and the cycles.
func sense(dt: float) -> void:
	if not _on:
		return
	var q := _att()
	var dv := _sense(dt)
	var rest := dt
	while cycle_t + rest >= AgsFp6.CYCLE - 1e-9:
		var part := maxf(AgsFp6.CYCLE - cycle_t, 0.0)
		_accumulate(q, dv * (part / dt))
		rest -= part
		cycle_t = 0.0
		_cycle(q)
	if dt > 0.0:
		_accumulate(q, dv * (rest / dt))
	cycle_t += rest
	Bus.set_value("lm.ags.dv_x_mps", v_d[0] * Units.FT)


## The power turn-on: the attitude hold, orbit insertion, the frame on the
## body axes [simplified: FP6 kept its direction cosines through a power
## loss, the gyros stopped; and set V_D to the descent stage's -8,000 ft/s].
func _power_on(q: Quaternion) -> void:
	frame = Basis(q)
	pgns_aligned = false
	s00 = 0
	fp6.s10 = 0
	hold_set = false
	v_d = PackedFloat64Array([0.0, 0.0, 0.0])
	v_dd = v_d.duplicate()
	fp6.v_dx_prev = 0.0
	engine_on = false


## The ASA's sensing this step: the ΔV (ECI, ft/s) its ideal
## accelerometers sensed. On the surface they sense the ground's push,
## gravity's opposite [simplified: a sphere's gravity].
func _sense(dt: float) -> Vector3:
	var step: Array = Bus.get_value("lm.dyn.dv_step", [0.0, 0.0, 0.0])
	var dv := Vector3(step[0], step[1], step[2]) / Units.FT
	if bool(Bus.get_value("lm.dyn.landed", false)):
		var p: Array = Bus.get_value("lm.dyn.r_m", [0.0, 0.0, 0.0])
		var r := Vector3(p[0], p[1], p[2])
		if r != Vector3.ZERO:
			dv = r.normalized() * (Bodies.mu_of("moon") / r.length_squared() * dt / Units.FT)
	return dv


## Sensed ΔV [param dv] (ECI, ft/s) into the counts: along the body axes
## and in the AGS's frame.
func _accumulate(q: Quaternion, dv: Vector3) -> void:
	if dv == Vector3.ZERO:
		return
	var b := Basis(q).transposed() * dv
	var a := frame.transposed() * dv
	for i in 3:
		v_d[i] += b[i]
		dv_cycle[i] += a[i]


## The alignments S00 selects: to the PGNS's platform through its gimbal
## angles, for two seconds, then back to the attitude hold; or onto the
## body axes, until the crew select another submode.
func _aligning(dt: float, q: Quaternion) -> void:
	if s00 == 3:
		var g: Vector3 = Bus.get_value("lm.imu.icdu_deg", Vector3.ZERO)
		frame = (Basis(q) * Imu.gimbal_basis(g).transposed()).orthonormalized()
		align_t += dt
		if align_t >= ALIGN_S:
			s00 = 0
			pgns_aligned = true
	elif s00 == 5:
		frame = Basis(q)
		pgns_aligned = false
	if s00 != 3:
		align_t = 0.0


## The body axes in the AGS's frame, for the equations: [X_b, Y_b, Z_b].
func _axes(q: Quaternion) -> Array:
	var m := frame.transposed() * Basis(q)
	var out := []
	for c in [m.x, m.y, m.z]:
		out.append(AgsFp6.vec(c.x, c.y, c.z))
	return out


## One two-second cycle: an initialization S14 asks for, or the equations.
func _cycle(q: Quaternion) -> void:
	if s14 == 1:
		var dl: Dictionary = Bus.get_value("lm.lgc.ags_downlink", {})
		if not dl.is_empty() and float(Bus.get_value("time.get_s", 0.0)) < float(dl["until"]):
			var t_dl: float = dl["t"]
			fp6.t += AgsFp6.CYCLE
			fp6.initialize(PackedFloat64Array(dl["lm_r"]), PackedFloat64Array(dl["lm_v"]), t_dl,
				[PackedFloat64Array(dl["csm_r"]), PackedFloat64Array(dl["csm_v"]), t_dl])
			s14 = 0
			dv_cycle = PackedFloat64Array([0.0, 0.0, 0.0])
			return
	elif s14 == 2:
		fp6.t += AgsFp6.CYCLE
		fp6.initialize(fp6.r_l, fp6.v_l, fp6.t_l)
		s14 = 0
		dv_cycle = PackedFloat64Array([0.0, 0.0, 0.0])
		return
	elif s14 == 3:
		fp6.set_csm(fp6.r_e, fp6.v_e, fp6.t_e)
		s14 = 0
	if fp6.d21:
		# On the surface the sensed velocities are zeroed every cycle.
		v_d = PackedFloat64Array([0.0, 0.0, 0.0])
	fp6.cycle(dv_cycle, v_d[0], _axes(q))
	dv_cycle = PackedFloat64Array([0.0, 0.0, 0.0])
	v_dd = v_d.duplicate()
	var vb: PackedFloat64Array = fp6.disp.get("vg_body", AgsFp6.vec(0.0, 0.0, 0.0))
	for i in 3:
		v_g[i] = vb[i] + v_dd[i]


# -- the 40-ms logic (figures 7.7 and 7.8) --------------------------------

## The attitude errors and the engine command. Returns whether the AGS
## follows (its errors kept from the jets).
func _attitude_errors(q: Quaternion, dt: float) -> bool:
	var ax := _axes(q)
	var xb := _v3(ax[0])
	var yb := _v3(ax[1])
	var zb := _v3(ax[2])
	var guided := int(Bus.get_value("ctl.lm.guid_cont", 0)) == 1
	var mode := int(Bus.get_value("ctl.lm.mode", 1))
	var aca := (Bus.get_value("ctl.lm.rhc", Vector3.ZERO) as Vector3).length() > 0.05
	var b1 := bool(Bus.get_value("lm.dps.on", false))
	var b2 := bool(Bus.get_value("lm.aps.on", false))
	var b3 := not guided or (mode == 1 and aca)
	var b4 := mode == 2
	var b5 := bool(Bus.get_value("lm.aps.abort_armed", false))
	var b6 := bool(Bus.get_value("lm.dps.abort_armed", false))
	# Staging recognized, and the surface left, when the ascent engine
	# lights.
	if not fp6.d2 and b2:
		fp6.d2 = true
		fp6.d21 = false
	if not b2:
		mu6 = 0.0
	errors = Vector3.ZERO
	var how := ""
	if s00 >= 3:
		hold_set = false
		engine_on = false
		return b3
	if b3:
		# Follow-up: the hold re-captured every step (δ5 = 0), the errors
		# for the needles only.
		how = "b3_steer" if b4 else "zero"
		hold_set = false
	elif not b4:
		how = "hold_follow"
	elif b5:
		if fp6.d21 or (b2 and mu6 < STAGE_HOLD):
			if b2:
				mu6 += dt
			how = "hold"
		else:
			how = "steer"
	elif fp6.d21:
		how = "zero"
	else:
		how = "steer" if b6 else "steer_follow"
	match how:
		"zero":
			hold_set = false
		"hold", "hold_follow":
			_hold(xb, yb, zb)
		_:
			_steer(xb, yb, zb)
	for i in 3:
		errors[i] = clampf(errors[i], -ERROR_LIMIT, ERROR_LIMIT)
	if how in ["zero", "b3_steer", "hold_follow", "steer_follow"]:
		engine_on = b1 or b2
	else:
		_engine()
	return b3


## AHE: the attitude hold's errors, the hold captured the first time.
func _hold(xb: Vector3, yb: Vector3, zb: Vector3) -> void:
	if not hold_set:
		hold_x = xb
		hold_z = zb
		hold_set = true
	errors = Vector3(-yb.dot(hold_z), -zb.dot(hold_x), yb.dot(hold_x))


## The steering S00 selects: the hold (0), guidance steering (1) or Z axis
## steering (2).
func _steer(xb: Vector3, yb: Vector3, zb: Vector3) -> void:
	if s00 == 0:
		_hold(xb, yb, zb)
		return
	hold_set = false
	var xd := _v3(fp6.x_bd)
	if s00 == 1:
		var w := _v3(fp6.w_b if fp6.s623 == 1 else fp6.w_c)
		errors.x = -w.dot(zb)
		if fp6.s11 == 1 or bool(Bus.get_value("lm.aps.on", false)):
			errors.y = fp6.k7 * xb.dot(xd)
			errors.z = -fp6.k8 * xb.dot(xd)
		errors.y -= zb.dot(xd)
		errors.z += yb.dot(xd)
	else:
		var zd := xd if fp6.s507 == 1 else _v3(fp6.disp.get("z_bd", AgsFp6.vec(0.0, 0.0, 1.0)))
		errors = Vector3(-yb.dot(zd), xb.dot(zd), _v3(fp6.w_c).dot(xb))


## The engine command under the AGS's full control (figure 7.8): ON while
## ullage holds and the velocity to be gained lasts, then OFF and the
## attitude hold.
func _engine() -> void:
	if s00 != 1 or fp6.mu8 < fp6.k9:
		engine_on = false
		return
	var dvg_x := v_g[0] - v_d[0]
	if dvg_x > CUTOFF_IMPULSE or fp6.vg_mag > CUTOFF_VG:
		engine_on = true
		return
	s00 = 0
	fp6.s11 = 0
	engine_on = false


## The jets' command: the ACA's rate while out of detent, the ACA itself
## in FREE, else the attitude errors flown down (none while following).
## Returns [command, busy].
func _control(follow: bool) -> Array:
	if int(Bus.get_value("ctl.lm.guid_cont", 0)) != 1:
		_rhc_was = false
		return [Vector3.ZERO, false]
	var hc: Vector3 = Bus.get_value("ctl.lm.rhc", Vector3.ZERO)
	var w: Vector3 = Bus.get_value("lm.dyn.omega", Vector3.ZERO)
	var alpha := Lgc.jet_authority()
	var active := hc.length() > 0.05
	var cmd := Vector3.ZERO
	if int(Bus.get_value("ctl.lm.mode", 1)) == 0:
		cmd = hc
		hold_set = false
	elif active:
		cmd = AgcCore._rate_cmd(hc * RATE_HOLD - w, alpha, 0.6)
		hold_set = false
	elif not follow:
		var e := errors
		var w_des := Vector3.ZERO
		for i in 3:
			var brake := sqrt(alpha[i] * absf(e[i]))
			w_des[i] = signf(e[i]) * minf(minf(absf(e[i]) * 0.4, brake), RATE_HOLD)
		if e.length() < DEADBAND * 0.1 and w.length() < 5e-5:
			w_des = Vector3.ZERO if w.length() > REST_RATE else w
		cmd = AgcCore._rate_cmd(w_des - w, alpha, 0.6)
	_rhc_was = active
	var busy := active or cmd.length() > 1e-4 or errors.length() > DEADBAND * 0.2
	return [cmd, busy]


static func _v3(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


# -- the DEDA ----------------------------------------------------------------

## A key on the DEDA: one of Deda.KEYS. The AEA takes a word entered, and
## shows one read out, at once [simplified: FP6 serviced the DEDA every
## half second, and the crew keyed AGS time (377) to the second].
func press(key: String) -> void:
	deda.press(key)
	if _on:
		_serve_deda()
	else:
		deda.take()
		_publish_deda()


## The half-second service: a word entered taken in, the one read out
## shown.
func _serve_deda() -> void:
	var e := deda.take()
	if not e.is_empty():
		store("%o" % int(e[0]), int(e[1]), str(e[2]))
	if deda.state == "readout":
		deda.show_word(word("%o" % deda.readout))
	_publish_deda()


## The DEDA's display of the word at octal [param addr]: a sign and five
## digits.
func word(addr: String) -> String:
	if addr in SELECTORS:
		return "+%d0000" % _selector(addr)
	var octal := {"574": [-1.0 if fp6.d2 else 1.0, -1], "604": [-1.0 if fp6.d21 else 1.0, -1],
		"605": [fp6.j2, 7], "514": [fp6.w_b[0], 1], "515": [fp6.w_b[1], 1], "516": [fp6.w_b[2], 1],
		"566": [fp6.k7, 0], "602": [fp6.k8, 0]}
	if octal.has(addr):
		var o: Array = octal[addr]
		if int(o[1]) < 0:
			# A flag: its sign.
			return "-00000" if float(o[0]) < 0.0 else "+00000"
		return _octal(float(o[0]), int(o[1]))
	if not WORDS.has(addr):
		return "+00000"
	var n := clampi(roundi(value(addr) / float(QUANTUM[WORDS[addr][1]])), -99999, 99999)
	return ("-" if n < 0 else "+") + "%05d" % absi(n)


## The value (FP6's units) of the decimal word at octal [param addr].
func value(addr: String) -> float:
	var what: String = WORDS[addr][0]
	var tpi := fp6.s10 >= 3
	var special := {
		"angle": rad_to_deg(fposmod(float(fp6.disp["theta_los"] if tpi else fp6.disp["theta_f"]), TAU)),
		"dv_second": float(fp6.disp["v_t"] if tpi else fp6.disp["v_p0"]),
		"dr_second": float(fp6.disp["q_ld"] if tpi else fp6.disp["Dr"]),
		"t": fp6.t + cycle_t, "k9": float(fp6.k9),
	}
	if special.has(what):
		return special[what]
	var parts := what.split(".")
	var x := 0.0
	match parts[0]:
		"disp":
			x = float(fp6.disp.get(parts[1], 0.0))
		"vd":
			x = v_d[int(parts[1])]
		"dvg":
			x = v_g[int(parts[1])] - v_d[int(parts[1])]
		_:
			var base: Variant = fp6.get(parts[0])
			x = float(base[int(parts[1])]) if parts.size() > 1 else float(base)
	return x


## A word entered at octal [param addr]: [param sign] and five
## [param digits].
func store(addr: String, sign: int, digits: String) -> void:
	if addr in SELECTORS:
		_set_selector(addr, int(digits.substr(0, 1)))
		return
	match addr:
		"574":
			fp6.d2 = sign < 0
		"604":
			fp6.d21 = sign < 0
		"605":
			fp6.j2 = _from_octal(sign, digits, 7)
		"514", "515", "516":
			fp6.w_b[int(addr) - 514] = _from_octal(sign, digits, 1)
		"566":
			fp6.k7 = _from_octal(sign, digits, 0)
		"602":
			fp6.k8 = _from_octal(sign, digits, 0)
	if not WORDS.has(addr):
		return
	var x := sign * int(digits) * float(QUANTUM[WORDS[addr][1]])
	var what: String = WORDS[addr][0]
	var parts := what.split(".")
	match parts[0]:
		"disp", "angle", "dv_second", "dr_second", "dvg", "r", "v", "r_c", "v_c":
			return
		"vd":
			v_d[int(parts[1])] = x
		"t":
			fp6.t = x
			cycle_t = 0.0
		"k9":
			fp6.k9 = int(x)
		_:
			if parts.size() > 1:
				var arr: PackedFloat64Array = fp6.get(parts[0])
				arr[int(parts[1])] = x
				fp6.set(parts[0], arr)
			else:
				fp6.set(what, x)


func _selector(addr: String) -> int:
	# 412, the self test, reads passed [simplified: FP6's inflight self
	# test left out].
	var m := {"400": s00, "407": fp6.s07, "410": fp6.s10, "411": fp6.s11, "412": 1, "414": s14,
		"416": fp6.s16, "417": fp6.s17, "507": fp6.s507, "623": fp6.s623}
	return int(m.get(addr, 0))


func _set_selector(addr: String, n: int) -> void:
	match addr:
		"400":
			s00 = n
			hold_set = false
		"407":
			fp6.s07 = n
		"410":
			if fp6.s10 != n and n in [1, 2, 3, 4]:
				fp6.s07 = 0
			fp6.s10 = n
		"411":
			fp6.s11 = n
		"413":
			# The landing azimuth stored and the lunar surface flag set.
			fp6.d21 = true
		"414":
			s14 = n
		"415":
			fp6.mark(_axes(_att())[2])
		"416":
			fp6.s16 = n
		"417":
			fp6.s17 = n
		"507":
			fp6.s507 = n
		"623":
			fp6.s623 = n


## [param x] at binary scaling B[param b] as the DEDA shows an octal word:
## its 18 bits' top 16, a sign and five octal digits.
static func _octal(x: float, b: int) -> String:
	var n := roundi(x * pow(2.0, 17 - b)) >> 2
	if n < 0:
		n += 1 << 15
		return "-%05o" % n
	return "+%05o" % n


static func _from_octal(sign: int, digits: String, b: int) -> float:
	var n := Deda._octal(digits)
	if sign < 0:
		n -= 1 << 15
	return float(n << 2) / pow(2.0, 17 - b)


func _publish_deda() -> void:
	Bus.set_value("lm.deda.addr", deda.addr_text if _on else "")
	Bus.set_value("lm.deda.data", deda.data_text if _on else "")
	Bus.set_value("lm.deda.opr_err", _on and deda.opr_err)


func _publish(cmd: Vector3, busy: bool) -> void:
	Bus.set_value("lm.ags.on", _on)
	Bus.set_value("lm.ags.rcs_rot_cmd", cmd)
	Bus.set_value("lm.ags.dap_busy", busy)
	Bus.set_value("lm.ags.att_error_deg", errors * (180.0 / PI) if _on else Vector3.ZERO)
	Bus.set_value("lm.ags.dv_x_mps", v_d[0] * Units.FT)
	Bus.set_value("lm.ags.engine_on", _on and engine_on)
	Bus.set_value("lm.ags.s00", s00)
	Bus.set_value("lm.ags.s10", fp6.s10)
	Bus.set_value("lm.ags.pgns_aligned", _on and pgns_aligned)
	Bus.set_value("lm.ags.initialized", _on and fp6.initialized)
	_publish_deda()


func snapshot() -> Dictionary:
	return {"fp6": fp6.snapshot(), "deda": deda.snapshot(), "frame": Imu.rows_of(frame), "s00": s00,
		"s14": s14, "hold_x": [hold_x.x, hold_x.y, hold_x.z], "hold_z": [hold_z.x, hold_z.y, hold_z.z],
		"hold_set": hold_set, "mu6": mu6, "v_d": Array(v_d), "v_dd": Array(v_dd), "v_g": Array(v_g),
		"engine_on": engine_on, "pgns_aligned": pgns_aligned, "cycle_t": cycle_t, "deda_t": deda_t, "align_t": align_t,
		"dv_cycle": Array(dv_cycle), "on": _on, "align_was": _align_was, "rhc_was": _rhc_was}


func restore(d: Dictionary) -> void:
	fp6 = AgsFp6.new()
	fp6.restore(d.get("fp6", {}))
	deda = Deda.new()
	deda.restore(d.get("deda", {}))
	frame = Imu.from_rows(d.get("frame", Imu.rows_of(Basis.IDENTITY)))
	s00 = int(d.get("s00", 0))
	s14 = int(d.get("s14", 0))
	var hx: Array = d.get("hold_x", [1.0, 0.0, 0.0])
	var hz: Array = d.get("hold_z", [0.0, 0.0, 1.0])
	hold_x = Vector3(hx[0], hx[1], hx[2])
	hold_z = Vector3(hz[0], hz[1], hz[2])
	hold_set = bool(d.get("hold_set", false))
	mu6 = float(d.get("mu6", 0.0))
	v_d = PackedFloat64Array(d.get("v_d", [0.0, 0.0, 0.0]))
	v_dd = PackedFloat64Array(d.get("v_dd", [0.0, 0.0, 0.0]))
	v_g = PackedFloat64Array(d.get("v_g", [0.0, 0.0, 0.0]))
	engine_on = bool(d.get("engine_on", false))
	pgns_aligned = bool(d.get("pgns_aligned", false))
	cycle_t = float(d.get("cycle_t", 0.0))
	deda_t = float(d.get("deda_t", 0.0))
	align_t = float(d.get("align_t", 0.0))
	dv_cycle = PackedFloat64Array(d.get("dv_cycle", [0.0, 0.0, 0.0]))
	_on = bool(d.get("on", false))
	_align_was = bool(d.get("align_was", false))
	_rhc_was = bool(d.get("rhc_was", false))
	_publish(Vector3.ZERO, false)

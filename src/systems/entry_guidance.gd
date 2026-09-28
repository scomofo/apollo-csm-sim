## Colossus's entry guidance: the roll command the CMC flies from P63 to
## 1,000 ft/s, ported from Comanche 055's REENTRY CONTROL (pages 844-882,
## the logic of the Colossus 2 GSOP, R-577, section 5.7) [published].
##
## Every pass (two seconds, as the SERVICER ran it) TARGETNG finds the range
## to the target on the turning Earth and the crossrange, then the phase's
## equations give the L/D to fly in the trajectory's plane and LIMITL/D
## turns it into a roll command, choosing its side by the lateral logic:
##   INITROLL  (P63, P64) the initial roll, lift up or down, held past
##             0.05 g until the drag reaches KAT; then constant drag, until
##             the altitude rate comes up to -700 ft/s
##   HUNTEST   (P64) predicts the range of an up-control, a skip and a
##             second entry, at the up-control's L/D (LEWD), and iterates
##             LEWD onto the target's range; while the prediction runs long
##             it flies constant drag (CONSTD). Below an exit velocity of
##             18,000 ft/s, the final phase
##   UPCONTRL  (P65) steers onto the up-control's reference trajectory, to
##             the exit velocity VL and the exit drag Q7; with the drag under
##             Q7, KEP2
##   KEP2      (P66) the ballistic phase: the roll held until the drag comes
##             back to Q7F + KDMIN
##   PREDICT3  (P67) the final phase: the range predicted by linear
##             perturbation of the stored reference trajectory, flown back
##             onto the target; steering stops below VQUIT
## The G limiter holds the load under 8 g in the final phase, and above
## 175 ft/s² of drag no negative lift is flown, and a roll reversal goes
## over the top (through lift up).
##
## The equations run in the listing's units: feet, ft/s, ft/s², nautical
## miles (21,600 to the revolution) and radians. Colossus's roll command
## ROLLC is positive to the left of the trajectory (S62.3: the lift along
## UZA cos + UYA... with UYA = unit(V x R) to the right); the simulator's
## bank angle is its negative.
class_name EntryGuidance
extends RefCounted

const FT := 0.3048
const G := 32.2                 ## ft/s², GS
const VSAT := 25766.1973        ## ft/s
const RE := 21202900.0          ## ft
const HS := 28500.0             ## ft, the atmosphere's scale height
const ATK := 3437.7468          ## nmi per radian
const C1 := 1.25
const C16 := 0.01               ## CONSTD's gain on drag, per ft/s²
const C17 := 0.001              ## CONSTD's gain on altitude rate, per ft/s
const C18 := 500.0              ## ft/s: the final phase's start past VL
const C20 := 175.0              ## ft/s²: no negative lift above it
const C21 := 140.0              ## ft/s²: no lateral switch above it (P65)
const CHOOK := 0.25
const CH1 := 1.0
const COS15 := 0.965
const DLEWD0 := -0.05
const GMAX := 257.6             ## ft/s², 8 g
const KA1 := 1.3                ## g
const KA2 := 0.2                ## g
const KALIM := 1.5              ## g
const KA3 := 90.0               ## ft/s²
const KA4 := 40.0               ## ft/s²
const KB1 := 3.4
const KB2 := 0.0034             ## per ft/s
const KDMIN := 0.5              ## ft/s²
const KTETA := 1000.0           ## s per radian of range, the time to go before P67
const K44 := 19749550.0         ## ft/s
const LATBIAS := 0.41252961     ## nmi
const LEWD1 := 0.15
const Q3 := 0.07                ## nmi per ft/s
const Q5 := 7050.0              ## nmi per radian
const Q6 := 0.0349              ## rad
const Q7F := 6.0                ## ft/s²
const Q7MIN := 40.0             ## ft/s²
const Q19 := 0.5
const Q21 := 500.0              ## nmi per unit of LAD
const Q22 := -1152.0            ## nmi
const VFINAL1 := 27000.0        ## ft/s
const VFINAL := 26600.0         ## ft/s
const VLMIN := 18000.0          ## ft/s
const VMIN := VSAT / 2.0        ## ft/s: relative velocity below it, in P67
const VRCONT := 700.0           ## ft/s
const VQUIT := 1000.0           ## ft/s
const TOL_NMI := 25.0
const PASS_S := 2.0
## 0.05 g, ft/s².
const G05 := 0.05 * G

## S61.2's altitudes (above the Earth's radius), m: entry interface, the
## one its G formula takes the flight path angle at, and the EMS's for a
## lunar return (297,431 ft); its time to go per radian of range from the
## EMS altitude, s (KTETA1); and its drag loss down to 0.05 g, ft²/s²
## (VEMSCON: a scale height of 16,369 ft times 0.05 g) [published].
const ALT_400K := 400000.0 * FT
const ALT_300K := 300000.0 * FT
const EMS_ALT := 297431.0 * FT
const KTETA1 := 1100.0
const VEMS_LOSS := 16369.0 * G05

## The final phase's stored reference trajectory: at each velocity (ft/s),
## the range to go (nmi), the drag (ft/s²) and the altitude rate (ft/s) along
## it, and the range's partials in drag (nmi per ft/s²), in altitude rate
## (nmi per ft/s) and in L/D (nmi), from the listing's table, unscaled (the
## altitude rate's partial is stored "B-3", on a scale of 21,600/2VSAT nmi
## per ft/s: GSOP 5.7's table of maxima).
const REF_V := [993.96, 2102.98, 3921.97, 6294.97, 8530.97, 10101.0, 14013.95, 15950.98, 18356.97,
	20828.99, 23089.95, 23499.94, 35000.0]
const REF_DRDA := [-0.034671, -0.055509, -0.090341, -0.140999, -0.1978, -0.2372, -0.330496, -0.360494,
	-0.495595, -0.648287, -2.020999, -3.354004, -3.354004]
const REF_DRDRDOT := [0.002508, 0.003582, 0.007039, 0.01446, 0.02479, 0.03391, 0.06139, 0.07683, 0.09982,
	0.1335, 0.2175, 0.3046, 0.3046]
const REF_RDOT := [-690.54, -718.72, -693.73, -608.75, -492.81, -415.84, -351.86, -415.84, -565.78,
	-780.7, -926.64, -819.68, -819.68]
const REF_RTOGO := [2.178, 8.9, 22.1, 46.3, 75.4, 99.9, 170.905, 210.3, 266.801, 344.301, 504.8, 643.0, 794.3]
const REF_DREF := [41.135, 60.0, 81.5, 93.9, 98.5, 102.3, 118.7, 125.2, 120.4, 95.4, 28.1, 6.4, 6.4]
const REF_F3 := [12.126, 21.819, 43.281, 96.701, 187.439, 282.201, 329.4, 465.499, 682.7, 980.5, 1385.0,
	1508.001, 1508.001]

## The CM's L/D, and the final phase's reference L/D (pad loaded).
var lad: float = 0.3
var lod: float = 0.15
## The target, a unit vector in the Earth-fixed frame.
var target_ef: Vector3 = Vector3.RIGHT
## +1 heads up (lift down), -1 heads down (lift up): N61's R3.
var headsup: int = -1

## The phase: "initroll", "huntest", "upcontrl", "kep2", "predict3", "done".
var mode: String = "initroll"
## The program the phase shows: 63 to 67.
var program: int = 63

# The listing's switches.
var gonepast: bool = true
var goneby: bool = false
var relvelsw: bool = false
var egsw: bool = false
var noswitch: bool = false
var hind: bool = false
var inrlsw: bool = false
var latsw: bool = true
var g05sw: bool = false

# Its variables (ft, ft/s, ft/s², rad).
var ld: float = 0.0          ## L/D
var ld1: float = 0.0         ## L/D1, as limited for lateral control
var ldcminr: float = 0.0
var klat: float = 0.0
var q2: float = 0.0
var q7: float = Q7F
var factor: float = 1.0
var k2roll: float = -1.0
var kat: float = 0.0
var d0: float = 0.0
var lewd: float = LEWD1
var dlewd: float = DLEWD0
var diffold: float = 0.0
var v1: float = 0.0
var a0: float = 0.0
var a1: float = 0.0
var alp: float = 0.0
var fact1: float = 0.0
var fact2: float = 0.0
var vl: float = 0.0
var gammal1: float = 0.0
var vbars: float = 0.0
var dvl: float = 0.0
var vs1: float = VSAT
var dhook: float = 0.0
var ahookdv: float = 0.0
var theta: float = 0.0       ## THETAH, rad
var latang: float = 0.0
var rollc: float = 0.0       ## rad, Colossus's sign
var dnrngerr: float = 0.0    ## nmi
var predang: float = 0.0     ## nmi
# The last pass's measurements, for the displays.
var v: float = 0.0
var rdot: float = 0.0
var d: float = 0.0
var leq: float = 0.0


## STARTENT (P63): the entry equations initialized at GET [param t] on the
## state [param r], [param vel] (ECI, m, m/s), heads [param p_headsup].
func start(r: Vector3, vel: Vector3, t: float, p_lad: float, p_lod: float, p_target_ef: Vector3,
		p_headsup: int = -1) -> void:
	lad = p_lad
	lod = p_lod
	target_ef = p_target_ef.normalized()
	headsup = p_headsup
	mode = "initroll"
	program = 63
	gonepast = true
	goneby = false
	relvelsw = false
	egsw = false
	noswitch = false
	hind = false
	inrlsw = false
	latsw = true
	g05sw = false
	ldcminr = lad * COS15
	klat = lad / 24.0
	q7 = Q7F
	factor = 1.0
	ld = -lad * signf(float(headsup))
	ld1 = ld
	q2 = Q22 + Q21 * lad
	diffold = 0.0
	dlewd = DLEWD0
	lewd = LEWD1
	# RT half a thousand seconds on, the nominal entry's (STARTEN1).
	var rt := target_at(t + 500.0)
	var uni := vel.cross(r).normalized()
	latang = rt.dot(uni)
	k2roll = -signf(latang) if latang != 0.0 else -1.0
	theta = angle(rt, r.normalized())
	rollc = 0.0 if ld >= 0.0 else PI


## The target at latitude [param lat_deg], east longitude [param lng_deg]:
## a unit vector in the Earth-fixed frame.
static func target_of(lat_deg: float, lng_deg: float) -> Vector3:
	var p := Bodies.geographic_to_fixed(lat_deg, lng_deg, 1.0)
	return Vector3(p[0], p[1], p[2])


## S61.2: P61's displays, from the state vector [param tr] (a copy is
## coasted on) and the target [param p_target_ef] (Earth-fixed, a unit
## vector). "gmax" (g): the load Colossus's formula expects lift up at an
## L/D of 0.3, from the speed and flight path angle at 300,000 ft;
## "vpred" (m/s) and "gammaei" (deg, negative down) at entry interface,
## 400,000 ft, and "ei_get" its GET; and for the EMS, "rtgo" (nmi), the
## range from the EMS altitude to the target where it will be at the
## landing, "vio" (m/s), the speed there less the drag's loss down to
## 0.05 g, and "tte_get", its GET [simplified: the simulator's integration
## for Colossus's conics, and heights above its spherical Earth for the
## Fischer ellipsoid's]. Empty when the state doesn't come down to entry
## interface within [param max_s].
static func predict(tr: Trajectory, p_target_ef: Vector3, max_s: float = 86400.0) -> Dictionary:
	var c := tr.clone()
	var t_max := c.t + max_s
	if not _coast_down_to(c, ALT_400K, t_max):
		return {}
	var out := {"ei_get": c.t, "vpred": c.speed(), "gammaei": _gamma_deg(c)}
	_coast_down_to(c, ALT_300K, t_max)
	var vbarsq := pow((c.speed() / FT - 36000.0) / 20000.0, 2.0)
	out["gmax"] = maxf(4.0 * (-_gamma_deg(c) - 6.05 - 2.4 * vbarsq) / (1.0 + 4.8 * vbarsq) + 10.0, 0.0)
	_coast_down_to(c, EMS_ALT, t_max)
	var vf := c.speed() / FT
	out["vio"] = (vf - VEMS_LOSS / (vf * maxf(deg_to_rad(-_gamma_deg(c)), 1e-3))) * FT
	out["tte_get"] = c.t
	# DISPTARG: the range to the target where it will be, twice over.
	var ur := c.pos().normalized()
	var th := 0.0
	for i in 3:
		var p := Bodies.earth_fixed_to_eci([p_target_ef.x, p_target_ef.y, p_target_ef.z], c.t + KTETA1 * th)
		th = angle(ur, Vector3(p[0], p[1], p[2]).normalized())
	out["rtgo"] = th * ATK
	return out


## The angle between unit vectors [param a] and [param b], rad, resolved
## down to the smallest (their dot product's arccosine isn't, in single
## precision: a nautical mile and more).
static func angle(a: Vector3, b: Vector3) -> float:
	return atan2(a.cross(b).length(), a.dot(b))


## The flight path angle of [param c], deg: negative down.
static func _gamma_deg(c: Trajectory) -> float:
	return rad_to_deg(asin(clampf(c.radial_rate() / maxf(c.speed(), 1e-6), -1.0, 1.0)))


## Coast [param c] down to altitude [param alt] (m), landing within a
## metre below it; false if it doesn't come down that far before GET
## [param t_max]. A state already below stays.
static func _coast_down_to(c: Trajectory, alt: float, t_max: float) -> bool:
	var near := alt + 200000.0
	if c.altitude() > near:
		var below := func(t2: Trajectory) -> bool:
			return t2.altitude() < near or t2.radial_rate() > 0.0 and t2.primary == "earth" and t2.altitude() < 5.0e7
		c.coast_until(below, t_max, 60.0)
	while c.altitude() > alt + 1.0:
		var rd := c.radial_rate()
		if rd >= 0.0 or c.t >= t_max:
			return false
		c.step(minf((c.altitude() - alt) / -rd, 10.0))
	return true


## The target's position at GET [param t], a unit vector in ECI.
func target_at(t: float) -> Vector3:
	var p := Bodies.earth_fixed_to_eci([target_ef.x, target_ef.y, target_ef.z], t)
	return Vector3(p[0], p[1], p[2]).normalized()


## One pass at GET [param t] on the CMC's state [param r], [param vel] (ECI,
## m, m/s) and its accelerometers' ΔV [param dv_sensed] (m/s) over the pass,
## [param pass_s] long. Returns the roll command (rad, Colossus's sign), or
## NAN once steering has stopped.
func step(r: Vector3, vel: Vector3, dv_sensed: Vector3, t: float, pass_s: float = PASS_S) -> float:
	if mode == "done":
		return NAN
	# The DAP set LATSW again when it last rolled.
	latsw = true
	_targeting(r, vel, dv_sensed, t, pass_s)
	match mode:
		"initroll":
			_initroll()
		"huntest":
			_huntest()
		"upcontrl":
			_upcontrl()
		"kep2":
			_kep2()
		"predict3":
			_predict3()
	return rollc if mode != "done" else NAN


## TARGETNG: the velocity (inertial, or relative to the air once RELVELSW),
## the drag the accelerometers measure, the range to the target predicted
## at the end of the time to go, and the crossrange.
func _targeting(r: Vector3, vel: Vector3, dv_sensed: Vector3, t: float, pass_s: float) -> void:
	var rf := r / FT
	var vf := vel / FT
	if relvelsw:
		vf -= Bodies.earth_omega().cross(rf)
	var unitr := rf.normalized()
	v = vf.length()
	leq = (v / VSAT) * (v / VSAT) - 1.0
	rdot = vf.dot(unitr)
	d = maxf(dv_sensed.length() / FT / maxf(pass_s, 1e-3), 1e-6)
	var uni := vf.cross(rf).normalized()
	var eta := 0.0
	if not relvelsw:
		# GETETA: the drag a half pass on.
		d += d * (-rdot / HS - 2.0 * d / v) * (PASS_S / 2.0)
		if egsw:
			if v < VMIN:
				relvelsw = true
			eta = theta * RE / v
		else:
			eta = theta * KTETA
	var rt := target_at(t + eta)
	latang = rt.dot(uni)
	goneby = rt.cross(unitr).dot(uni) < 0.0
	theta = angle(rt, unitr)
	g05sw = d >= G05


## INITROLL: hold the initial roll until the drag reaches KAT, then
## constant drag, until the altitude rate comes up to -VRCONT.
func _initroll() -> void:
	if not inrlsw:
		if not g05sw:
			_limit_ld()
			return
		# 0.05 g: P64.
		program = 64
		kat = minf(KA1 * leq * leq * leq + KA2, KALIM) * G
		gonepast = false
		if v < VFINAL1:
			mode = "kep2"
			inrlsw = true
			_limit_ld()
			return
		d0 = KA3 * leq + KA4
		ld = lad
		if v - VFINAL + K44 * pow(rdot / v, 3.0) >= 0.0:
			ld = -lad
		inrlsw = true
		_limit_ld()
		return
	if rdot + VRCONT < 0.0:
		if kat - d >= 0.0:
			_limit_ld()
		else:
			_constd()
		return
	# FOREHUNT
	diffold = 0.0
	dlewd = DLEWD0
	lewd = LEWD1
	hind = false
	mode = "huntest"
	_huntest()


## HUNTEST: the range of the rest of the entry predicted at the
## up-control's L/D, LEWD iterated onto the target's range.
func _huntest() -> void:
	for it in 30:
		a1 = d
		var tem1b := lad if rdot < 0.0 else lewd
		v1 = v + rdot / tem1b
		a0 = (v1 / v) * (v1 / v) * (d + rdot * rdot / (2.0 * C1 * HS * tem1b))
		if rdot < 0.0:
			a1 = a0
		if ld < 0.0:
			v1 -= VQUIT
		alp = 2.0 * C1 * HS * a0 / (lewd * v1 * v1)
		if absf(1.0 - alp) < 1e-9 or absf(alp) < 1e-12:
			_constd()
			return
		fact1 = v1 / (1.0 - alp)
		fact2 = alp * (alp - 1.0) / a0
		vl = fact1 * (1.0 - sqrt(maxf(q7 * fact2 + alp, 0.0)))
		gammal1 = lewd * (v1 - vl) / vl
		if vl < VLMIN:
			_prefinal()
			return
		vbars = (vl / VSAT) * (vl / VSAT)
		if vl > VSAT:
			_constd()
			return
		dvl = VSAT - vl
		vs1 = VSAT
		if v1 <= VSAT:
			dvl = v1 - vl
			vs1 = v1
		dhook = (pow(1.0 - vs1 / fact1, 2.0) - alp) / fact2
		if absf(dhook) < 1e-9:
			dhook = 1e-9
		ahookdv = CHOOK * (dhook / q7 - 1.0)
		var gammal := gammal1 - CH1 * G * dvl * dvl * (1.0 + ahookdv) / (dhook * vl * vl)
		if gammal < 0.0:
			# NEGAMA: the exit velocity lowered to fly out level.
			var dvl_v := (gammal * vl / 3.0) / (lewd / 3.0 - dvl * (2.0 / 3.0 + ahookdv) * CH1 * G / (dhook * vl))
			vl += dvl_v
			q7 = (pow(1.0 - vl / fact1, 2.0) - alp) / fact2
			vbars = (vl / VSAT) * (vl / VSAT)
			gammal = 0.0
		gammal1 += Q19 * (gammal - gammal1)
		# RANGER: the predicted range, rad.
		var cosg := 1.0 - gammal * gammal / 2.0
		var e := sqrt(maxf(1.0 + (vbars - 2.0) * vbars * cosg * cosg, 1e-12))
		var askep := 2.0 * asin(clampf(vbars * cosg * gammal / e, -1.0, 1.0))
		var asp1 := (q2 + Q3 * vl) / ATK
		var g1 := gammal1 if absf(gammal1) >= 1e-6 else 1e-6
		var aspup := -(HS / RE) * log(maxf(v1 * v1 * q7 / (vl * vl * a0), 1e-12)) / g1
		var aspdwn := -rdot * v / (a0 * RE)
		var asp3 := Q5 * (Q6 - gammal) / ATK
		var diff := askep + asp1 + aspup + asp3 + aspdwn - theta
		if absf(diff) * ATK < TOL_NMI:
			mode = "upcontrl"
			program = 65
			_upcontrl()
			return
		if not hind and diff >= 0.0:
			# Still long: constant drag bleeds it off, and the hunt goes on
			# next pass.
			diffold = diff
			q7 = Q7F
			_constd()
			return
		# GETLEWD: the secant on LEWD.
		if absf(diffold - diff) < 1e-12:
			break
		dlewd = dlewd * diff / (diffold - diff)
		if lewd + dlewd < 0.0:
			dlewd = -lewd / 2.0
		lewd += dlewd
		if lewd >= 1.0:
			lewd = 1.0
			diffold = diff
			q7 = Q7F
			_constd()
			return
		hind = true
		diffold = diff
		q7 = Q7F
	_constd()


## CONSTD: hold the drag at D0.
func _constd() -> void:
	var rdotref := -2.0 * HS * d0 / v
	ld = -G * leq / d0 + C16 * (d - d0) - C17 * (rdot - rdotref)
	_negtests()


## UPCONTRL: onto the up-control's reference trajectory.
func _upcontrl() -> void:
	if d > C21:
		noswitch = true
	if v > v1:
		# DOWNCNTL: down to the perigee on lift up's reference.
		var rdtr := lad * (v1 - v)
		var dref := (v / v1) * (v / v1) * a0 - (v1 - v) * (v1 - v) * lad / (2.0 * C1 * HS)
		ld = lad - C17 * (rdot - rdtr) + C16 * (d - dref)
		_negtests()
		return
	if d < q7:
		mode = "kep2"
		program = 66
		_kep2()
		return
	if rdot < 0.0 and v - vl - C18 < 0.0:
		_prefinal()
		return
	if d > a0:
		ld = lad
		_limit_ld()
		return
	var vref := fact1 * (1.0 - sqrt(maxf(fact2 * d + alp, 0.0)))
	var rdotref := lewd * (v1 - vref)
	if vs1 - vref >= 0.0:
		var dv := vs1 - vref
		rdotref -= CH1 * G * (1.0 + dv * ahookdv / dvl) * dv * dv / (dhook * vref)
	if d - Q7MIN >= 0.0:
		factor = (d - q7) / (a1 - q7)
	var dld := -KB2 * factor * (KB1 * factor * (rdot - rdotref) + v - vref)
	if absf(dld) > 0.1:
		dld = signf(dld) * (0.1 + 0.1 * (absf(dld) - 0.1))
	ld = lewd + dld
	_negtests()


## KEP2: the ballistic phase, the roll held; lift up out of the air.
func _kep2() -> void:
	if d > Q7F + KDMIN:
		_prefinal()
		return
	if not g05sw:
		rollc = 0.0


func _prefinal() -> void:
	egsw = true
	mode = "predict3"
	program = 67
	_predict3()


## PREDICT3: the final phase, on the stored reference trajectory.
func _predict3() -> void:
	if v < VQUIT:
		mode = "done"
		return
	var j := REF_V.size() - 2
	while j > 0 and float(REF_V[j]) > v:
		j -= 1
	var grad := (v - float(REF_V[j])) / (float(REF_V[j + 1]) - float(REF_V[j]))
	var f := func(tab: Array) -> float:
		return float(tab[j]) + grad * (float(tab[j + 1]) - float(tab[j]))
	predang = f.call(REF_RTOGO) + f.call(REF_DRDRDOT) * (rdot - f.call(REF_RDOT)) + f.call(REF_DRDA) * (d - f.call(REF_DREF))
	var thetnm := theta * ATK
	dnrngerr = predang - thetnm
	if gonepast:
		ld = -lad
	elif goneby:
		dnrngerr = 9999.9
		gonepast = true
		ld = -lad
	else:
		ld = lod + 4.0 * (thetnm - predang) / f.call(REF_F3)
		if absf(ld) >= 1.0:
			ld = lad * signf(ld)
	_glimiter()


## The G limiter: lift up when the load would pass GMAX.
func _glimiter() -> void:
	if d < GMAX / 2.0:
		_limit_ld()
		return
	if d > GMAX:
		ld = lad
		_limit_ld()
		return
	var xlim := sqrt(maxf(2.0 * HS * (GMAX - d) * (leq / 8.0 + lad) + pow(2.0 * HS * GMAX / v, 2.0), 0.0))
	if rdot + xlim < 0.0:
		ld = lad
	_limit_ld()


## NEGTESTS: no negative lift, and rolls over the top, in dense air; an
## L/D past 1 (the listing's overflow) is full lift, through the G limiter.
func _negtests() -> void:
	if absf(ld) >= 1.0:
		ld = lad * signf(ld)
		_glimiter()
		return
	if d >= C20:
		latsw = false
		if ld < 0.0:
			ld = 0.0
	_limit_ld()


## LIMITL/D: the lateral logic, then the roll command.
func _limit_ld() -> void:
	ld1 = ld
	if not gonepast:
		var y := (klat * (v / VSAT) * (v / VSAT) * ATK + LATBIAS) / ATK
		var side := latang * signf(k2roll)
		var switch_test := true
		if absf(ld) >= ldcminr:
			if side < 0.0:
				ld1 = ldcminr * signf(ld)
				switch_test = false
			else:
				y /= 2.0
		if switch_test and side - y >= 0.0:
			if noswitch:
				noswitch = false
			else:
				k2roll = -k2roll
	rollc = signf(k2roll) * acos(clampf(ld1 / lad, -1.0, 1.0))
	noswitch = false


## The roll command in the simulator's sense, deg: positive, lift to the
## right of the trajectory.
func bank_cmd_deg() -> float:
	return -rad_to_deg(rollc)


## ROLLC as the DSKY shows it, deg: 0 to 360.
func rollc_deg() -> float:
	return fposmod(rad_to_deg(rollc), 360.0)


func snapshot() -> Dictionary:
	var s := {}
	for k in ["lad", "lod", "headsup", "mode", "program", "gonepast", "goneby", "relvelsw", "egsw",
			"noswitch", "hind", "inrlsw", "latsw", "g05sw", "ld", "ld1", "ldcminr", "klat", "q2", "q7",
			"factor", "k2roll", "kat", "d0", "lewd", "dlewd", "diffold", "v1", "a0", "a1", "alp", "fact1",
			"fact2", "vl", "gammal1", "vbars", "dvl", "vs1", "dhook", "ahookdv", "theta", "latang", "rollc",
			"dnrngerr", "predang", "v", "rdot", "d", "leq"]:
		s[k] = get(k)
	s["target_ef"] = [target_ef.x, target_ef.y, target_ef.z]
	return s


func restore(s: Dictionary) -> void:
	for k in s:
		if k == "target_ef":
			var a: Array = s[k]
			target_ef = Vector3(a[0], a[1], a[2])
		elif k in ["mode"]:
			set(k, str(s[k]))
		elif k in ["headsup", "program"]:
			set(k, int(s[k]))
		elif typeof(get(k)) == TYPE_BOOL:
			set(k, bool(s[k]))
		else:
			set(k, float(s[k]))

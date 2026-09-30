## The Abort Guidance Section's flight program, FP6 (slice 11e): the
## Abort Electronics Assembly's two-second navigation and guidance
## equations as TRW's programmed equations document gives them [published:
## LM AGS Programmed Equations Document, Flight Program 6, 11176-6041-T0-00,
## April 1969, figures 7.11 to 7.35], with Apollo 11's LM-5 mission
## constants [published: LM/AGS FP6 LM 5 Mission Constants, 11176-6055-RO-00,
## June 1969]. FP6 flew on Apollo 11 and 12. Everything is in the AEA's
## units, feet, feet per second, seconds and radians, in its inertial frame:
## centred on the Moon, its axes where the AGS's last alignment left them.
## Vectors are PackedFloat64Array (3), as the AEA's double precision needed
## [simplified: in doubles throughout, where the AEA's 18-bit words kept
## most quantities to 17 bits].
##
## Each call to cycle() is one of the AEA's two-second cycles, its fifty
## branches in order [simplified: the branches run within one step where
## the AEA spread them over the cycle's 40-ms slots]:
## - Branch 1: the LM's navigation. Its velocity takes the accelerometers'
##   ΔV and gravity's, 3G(n) - G(n-1) of spherical gravity, and its position
##   the mean of the two velocities, over two seconds; a ΔV under 0.25 ft/s
##   in a cycle (1K35) is taken for the accelerometers' bias and dropped.
## - Branches 2 and 3: the CSM from its ephemeris (r_E, V_E, t_E) by the
##   ellipse predictor, a Kepler solution in two Newton steps, its epoch
##   stepped a period on (the bootstrap) once it is older than one.
## - Branches 5 to 7: the altitude update (223) and the radar filter.
## - Branches 8 to 10: the LM's orbit, its pericynthion and apocynthion, and
##   the unit vectors of the LM's position against the CSM's orbit plane.
## - Branches 11 on: the guidance routine S10 selects (address 410): orbit
##   insertion (0), CSI (1), CDH (2), TPI search (3) and execute (4), and
##   external ΔV (5), then the steering: the desired thrust direction
##   X_bD and the velocity to be gained.
## Initialization (S14, address 414) takes the place of a cycle.
class_name AgsFp6
extends RefCounted

# -- LM-5's constants (11176-6055-RO-00, Appendix C) ------------------------
## The Moon's gravitational constant (2K1), ft³/s², and its reciprocal
## (2K2).
const MU := 0.17318811e15
## A trial p's perturbation (2K14), ft; the p-iterator's trials less three
## (2K17); its partial's protector (2K18), s; Δp's limit (2K19), ft; its
## convergence (2K20), s; V_T's value on no solution (2K11), ft/s.
const P_PERTURB := 49984.0
const P_ITERATIONS := 5
const P_PARTIAL_MIN := 15.0
const P_STEP_MAX := 500032.0
const P_CONVERGED := 2.0
const NO_SOLUTION := 6000.0
## q when e overflows (2K3), ft; the sine of TPI's central angle limit
## (3K4).
const Q_OVERFLOW := 1048576.0
const SIN_CENTRAL_MIN := 0.173645
## Orbit insertion: ṙ_f = 4K4 (4K5 - r_b), limited to 4K6; the
## semimajor axis's slope with the phase angle (4K10, LM-5's).
const RDOT_SLOPE := 0.004
const RDOT_RADIUS := 5742400.0
const RDOT_MAX := 80.0
const ALPHA_SLOPE := -625384.0
## The burn time's coefficients (4K2, 4K3, LM-5's).
const TB_K2 := -0.5024e-4
const TB_K3 := 0.1683e-8
## The jerk limits: r⃛_d at most 0 (5K14) and at least -0.1 ft/s³ (5K18),
## or 0 once staged with the thrust under 5 ft/s² (5K20, 4K12); y⃛_d within
## 0.01 ft/s³ (5K16, 5K17, LM-5's).
const RDDD_MAX := 0.0
const RDDD_MIN := -0.1
const RDDD_MIN_LOW_THRUST := 0.0
const LOW_THRUST := 5.0
const YDDD_MAX := 0.01
const YDDD_MIN := -0.01
## The thrust acceleration's lower limit (4K34), ft/s², and the ullage
## threshold (4K35).
const A_T_MIN := 1.0
const ULLAGE_ACCEL := 0.099609
## Below this sensed ΔV a cycle, the accelerometers' bias (1K35), ft/s.
const NAV_DV_MIN := 0.25
## Below this velocity to be gained the thrust direction holds (5K26),
## ft/s.
const VG_FREEZE := 15.0
## The vertical rise's value of V_G, ft/s.
const VG_VERTICAL := 1024.0
## The radar filter: P's starting diagonal, position (6K2, ft²) and
## velocity (6K4, ft²/s²); the out-of-plane gains on position (6K5) and
## velocity (6K6); the variances of range rate (6K8, ft²/s²), gimbal angle
## (6K9, rad²) and range (6K10, ft²).
const P_POS := 0.99999744e8
const P_VEL := 100.0
const K_OUT_POS := -0.73000336
const K_OUT_VEL := -0.24023437
const VAR_RDOT := 0.21875
const VAR_ANGLE := 0.30290103e-4
const VAR_RANGE := 0.6250496e7
## The two-second cycle, s.
const CYCLE := 2.0

## The fields a checkpoint keeps: the whole of the AEA's memory the
## equations use.
const SAVED := ["j1", "j2", "j3", "j4", "j5", "j6", "j7", "j8", "j9", "j16", "j21", "j22", "j23", "j29",
	"j25", "j17", "j18", "j28_1", "j28_2", "j28_3", "t_ig", "t_delta", "s10", "s07", "s11", "s16", "s17",
	"s507", "s623", "d21", "d2", "mu8", "k9", "k7", "k8", "w_b", "t", "r", "v", "v_prev", "dig", "g_prev",
	"r_e", "v_e", "t_e", "r_l", "v_l", "t_l", "initialized", "dq_s", "v_dx_prev", "a_t", "r_b", "rddd",
	"yddd", "dv_ext", "vg", "vg_mag", "x_bd", "vg_tpi", "d10", "disp", "p_cov", "mu17", "t_1", "z_star",
	"r_star", "rdot_star", "dt_star", "r_c", "v_c", "w_c", "csm_orbit", "u1", "v1", "w1"]

# -- the targets and constants the DEDA reaches (LM-5's values) ----------
## 1J: TPI time for CSI (275), AGS time, s. 2J: the cotangent of the line
## of sight's angle at TPI (605; 1.997, 26.6 deg). 3J: rendezvous offset
## (312), s. 4J: the node's time before rendezvous (306), s. 5J: the landing
## site's radius (231), ft. 6J: TPI's transfer time (307), s. 7J, 8J, 9J:
## insertion's semimajor axis term and limits (224-226), ft. 16J: its
## altitude (232), ft. 21J, 22J: the vertical rise's thresholds (233, 464).
## 23J: insertion's radial rate (465), ft/s. 29J: the radar filter's time
## start (274), s.
var j1: float = 0.0
var j2: float = 1.997
var j3: float = 0.0
var j4: float = 0.0
var j5: float = 5693629.0
var j6: float = 42.83 * 60.0
var j7: float = 6026726.0
var j8: float = 5814800.0
var j9: float = 7031232.0
var j16: float = 60032.0
var j21: float = 25024.0
var j22: float = 50.0
var j23: float = 19.5
var j29: float = -300.0 * 60.0
## The altitude update (223), ft: 0 for none.
var j25: float = 0.0
## Radar range rate (503), ft/s, and range (316), ft, awaiting the filter:
## 0 for none.
var j17: float = 0.0
var j18: float = 0.0
## External ΔV (450-452): downrange, minus crossrange (against the CSM's
## angular momentum) and minus radial (down), ft/s. TPI's solution sets
## j28_1 to NO_SOLUTION as its flag.
var j28_1: float = 0.0
var j28_2: float = 0.0
var j28_3: float = 0.0
## The next maneuver's time (373), AGS time, s, and the time to it (310).
var t_ig: float = 0.0
var t_delta: float = 0.0

# -- the selectors ---------------------------------------------------------
## S10 (410): the guidance routine. S07 (407): the external ΔV frozen and
## the sensed ΔV counted. S11 (411): the APS's cant in the steering. S16
## (416): CDH at 1/2 (1) or 3/2 (3) of an orbit after CSI. S17 (417): the
## radar filter to start. S507 (507), S623 (623): the Z axis's steering
## submodes.
var s10: int = 0
var s07: int = 0
var s11: int = 0
var s16: int = 1
var s17: int = 0
var s507: int = 0
var s623: int = 0
## The lunar surface flag (604) and the staging flag (574).
var d21: bool = false
var d2: bool = false
## The ullage counter (μ8) and its limit (1K9, 616).
var mu8: int = 0
var k9: int = 4
## The APS's cant, pitch (4K7, 566) and roll (4K8, 602), rad
## [simplified: 0 here, where LM-5's was 0.0262 in pitch: the simulator's
## ascent engine thrusts along +X].
var k7: float = 0.0
var k8: float = 0.0
## The yaw steering plane's normal (514-516), for S623 = 1.
var w_b: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])

# -- the state ---------------------------------------------------------------
## The AGS clock (377), s.
var t: float = 0.0
## The LM's position and velocity, and its velocity a cycle ago.
var r: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var v: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var v_prev: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## Gravity over the next cycle (ΔIG), and over the last (G(n-1)Δt).
var dig: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var g_prev: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The CSM's ephemeris: its position, velocity and epoch (AGS time).
var r_e: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var v_e: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var t_e: float = 0.0
## The LM's ephemeris last loaded (the DEDA's 240-262 and 254).
var r_l: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var v_l: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var t_l: float = 0.0
## The navigation has been initialized.
var initialized: bool = false
## Sensed ΔV counted for an external ΔV burn (Δq_s), ft/s.
var dq_s: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The accumulated X-body sensed velocity a cycle ago (V_DX), and the
## thrust acceleration (a_T).
var v_dx_prev: float = 0.0
var a_t: float = A_T_MIN

# -- the guidance's own --------------------------------------------------
## The predicted final radius (r_b) and the jerks (r⃛_d, y⃛_d) insertion's
## law carries from cycle to cycle.
var r_b: float = 0.0
var rddd: float = 0.0
var yddd: float = 0.0
## The external ΔV frozen at the burn's start (ΔV), inertial.
var dv_ext: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The velocity to be gained (V_G) and its magnitude, and the desired thrust
## direction (X_bD).
var vg: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var vg_mag: float = 0.0
var x_bd: PackedFloat64Array = PackedFloat64Array([1.0, 0.0, 0.0])
## TPI's velocity to be gained (its V_G, inertial) for the external ΔV.
var vg_tpi: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The node flag (δ10) of TPI's retargeting.
var d10: bool = false

# -- the displays the DEDA reads -----------------------------------------
var disp := {
	"h": 0.0, "hdot": 0.0, "q_lt": 0.0, "q_a": 0.0, "t_perg": 0.0,
	"theta_f": 0.0, "theta_los": 0.0, "dr": 0.0, "Dr": 0.0, "v_p0": 0.0,
	"t_a0": 0.0, "rdot_a": 0.0, "v_py": 0.0, "q_ld": 0.0, "v_t": NO_SOLUTION,
	"t_r": 0.0, "range": 0.0, "range_rate": 0.0, "y": 0.0, "v_y0": 0.0, "xi": 0.0,
	"r_f": 0.0, "vg_mag": 0.0, "v": 0.0,
}

# -- the radar filter ----------------------------------------------------
## P, the in-plane covariance (4 x 4, row-major: x and z position, x and
## z velocity).
var p_cov: PackedFloat64Array = PackedFloat64Array()
## The cycles since P was last carried (μ17), and the last range update's
## time (t_1).
var mu17: int = 0
var t_1: float = 0.0
## A mark's (S15, 415) saved Z axis, range vector and range rate, and the
## time since the last range update then.
var z_star: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
var r_star: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var rdot_star: float = 0.0
var dt_star: float = 0.0
## The CSM's present state.
var r_c: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
var v_c: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0])
## The CSM's orbit: W_c, and α_E, n_E, C_E, S_E and its period.
var w_c: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.0])
var csm_orbit := {"a": 0.0, "n": 0.0, "c": 0.0, "s": 0.0, "r": 0.0, "period": 0.0}
## Branch 10's unit vectors: U1, V1 and W1, and the steering's.
var u1: PackedFloat64Array = PackedFloat64Array([1.0, 0.0, 0.0])
var v1: PackedFloat64Array = PackedFloat64Array([0.0, 1.0, 0.0])
var w1: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 1.0])
## The gravity gradients (a, c, j) branch 5 leaves for the radar filter.
var _grad := [0.0, 0.0, 0.0]


func _init() -> void:
	p_init()


# -- vectors in doubles -----------------------------------------------------

static func vec(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x, y, z])


static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] + b[0], a[1] + b[1], a[2] + b[2]])


static func sub(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] - b[0], a[1] - b[1], a[2] - b[2]])


static func mul(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return PackedFloat64Array([a[0] * s, a[1] * s, a[2] * s])


static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]])


static func length(a: PackedFloat64Array) -> float:
	return sqrt(dot(a, a))


static func unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var n := length(a)
	return mul(a, 1.0 / n) if n > 0.0 else PackedFloat64Array([0.0, 0.0, 0.0])


# -- the orbit subroutines (figure 7.33) ------------------------------

## ORBPM: [param r0] and [param v0]'s orbit: {r, a, n, c (e cos E),
## s (e sin E)}.
static func orbit_params(r0: PackedFloat64Array, v0: PackedFloat64Array) -> Dictionary:
	var ri := length(r0)
	var a := ri / (2.0 - ri * dot(v0, v0) / MU)
	var n := sqrt(MU / absf(a * a * a))
	return {"r": ri, "a": a, "n": n, "c": 1.0 - ri / a, "s": dot(r0, v0) / sqrt(MU * absf(a))}


## ELPRD: [param r0] and [param v0] carried [param ti] seconds on their
## ellipse (its parameters [param o], orbit_params()'s): [position,
## velocity]. Two Newton steps on Kepler's equation from ΔE = ΔM, as the
## AEA took.
static func ellipse(r0: PackedFloat64Array, v0: PackedFloat64Array, ti: float, o: Dictionary) -> Array:
	var a: float = o["a"]
	var n: float = o["n"]
	var c: float = o["c"]
	var s: float = o["s"]
	var dm := n * ti
	var de := dm
	var x12 := 1.0 - c * cos(de) + s * sin(de)
	for _i in 2:
		var x11 := -de - s + dm + c * sin(de) + s * cos(de)
		de += x11 / x12
		x12 = 1.0 - c * cos(de) + s * sin(de)
	var ri: float = o["r"]
	var f := (a / ri) * (cos(de) - c)
	var g := ti + (sin(de) - de) / n
	var fd := (-1.0 / ri) * sqrt(MU / a) * (sin(de) / x12)
	var gd := ((1.0 - c) * cos(de) + s * sin(de)) / x12
	return [add(mul(r0, f), mul(v0, g)), add(mul(r0, fd), mul(v0, gd))]


## GRAV: gravity over a cycle at [param rr] (G Δt), ft/s.
static func gravity_dt(rr: PackedFloat64Array) -> PackedFloat64Array:
	var rn := length(rr)
	return mul(rr, -MU * CYCLE / (rn * rn * rn))


# -- initialization (figures 7.11, 7.12) ----------------------------------

## The LM's state vector [param rl], [param vl] at AGS time [param tl]
## (the downlink's or the DEDA's 240-262 and 254), and, unless
## [param csm] is empty, the CSM's [r, v, t]: IC1 to IC3. The LM is carried
## to the present on its ellipse, or on the surface by its velocity alone.
func initialize(rl: PackedFloat64Array, vl: PackedFloat64Array, tl: float, csm: Array = []) -> void:
	r_l = rl.duplicate()
	v_l = vl.duplicate()
	t_l = tl
	if not csm.is_empty():
		set_csm(csm[0], csm[1], csm[2])
	var ti := t - t_l
	if d21:
		r = add(r_l, mul(v_l, ti))
		v = v_l.duplicate()
	else:
		var st := ellipse(r_l, v_l, ti, orbit_params(r_l, v_l))
		r = st[0]
		v = st[1]
	v_prev = v.duplicate()
	var g := gravity_dt(r)
	g_prev = g
	dig = g
	_grav_display()
	initialized = true
	p_init()


## The CSM's ephemeris [param re], [param ve] at AGS time [param te]
## (S14 = 3, or the downlink's).
func set_csm(re: PackedFloat64Array, ve: PackedFloat64Array, te: float) -> void:
	r_e = re.duplicate()
	v_e = ve.duplicate()
	t_e = te
	_csm_orbit()


func _csm_orbit() -> void:
	w_c = unit(cross(r_e, v_e))
	csm_orbit = orbit_params(r_e, v_e)
	csm_orbit["period"] = TAU / float(csm_orbit["n"])


## The CSM at AGS time [param at]: [position, velocity].
func csm_at(at: float) -> Array:
	return ellipse(r_e, v_e, at - t_e, csm_orbit)


# -- the cycle -----------------------------------------------------------

## One two-second cycle. [param dv_s] is the ΔV the accelerometers sensed
## over it, inertial (ft/s); [param v_dx] the X body axis's accumulated
## sensed velocity (V_dX, ft/s); [param axes] the body axes, inertial
## ([X_b, Y_b, Z_b]).
func cycle(dv_s: PackedFloat64Array, v_dx: float, axes: Array) -> void:
	if not initialized:
		t += CYCLE
		return
	_navigate(dv_s, v_dx)
	_csm_branches()
	_range_branch()
	_radar_filter()
	_lm_orbit()
	_guidance(axes)


## Branch 1 (figure 7.13).
func _navigate(dv_s: PackedFloat64Array, v_dx: float) -> void:
	var dv := dv_s
	if d21:
		mu8 = k9
		dig = vec(0.0, 0.0, 0.0)
		dv = vec(0.0, 0.0, 0.0)
	else:
		a_t = 0.5 * (v_dx - v_dx_prev)
		mu8 = mu8 + 1 if a_t >= ULLAGE_ACCEL else 0
		if absf(dv[0]) + absf(dv[1]) + absf(dv[2]) < NAV_DV_MIN:
			dv = vec(0.0, 0.0, 0.0)
	v_dx_prev = v_dx
	dq_s = add(dq_s, dv)
	var v_old := v
	v = add(add(v, dig), dv)
	if d21:
		v = v_old
	r = add(r, add(v, v_old))
	v_prev = v_old
	_grav_display()
	a_t = maxf(a_t, A_T_MIN)
	t += CYCLE


## GRAV's gravity integral for the next cycle, and the altitude and its
## rate.
func _grav_display() -> void:
	var g := gravity_dt(r)
	dig = add(g, mul(sub(g, g_prev), 0.5))
	g_prev = g
	var rn := length(r)
	u1 = mul(r, 1.0 / rn)
	disp["hdot"] = dot(u1, v)
	disp["h"] = rn - j5


## Branches 2 and 3 (figures 7.14, 7.15): the CSM's orbit, its epoch's
## bootstrap and its present state.
func _csm_branches() -> void:
	var period: float = csm_orbit["period"]
	if period > 0.0 and t - t_e >= period:
		t_e += period
	var st := csm_at(t)
	r_c = st[0]
	v_c = st[1]


## Branches 4 and 5 (figure 7.16): the altitude update, the range and
## range rate to the CSM, and gravity's gradients for the filter.
func _range_branch() -> void:
	disp["v"] = length(v)
	if j25 > 0.0:
		r = mul(unit(r), j5 + j25)
	j25 = 0.0
	var rel := sub(r_c, r)
	var rn := length(rel)
	disp["range"] = rn
	var zbd := mul(rel, 1.0 / rn) if rn > 0.0 else vec(0.0, 0.0, 1.0)
	disp["z_bd"] = zbd
	disp["rel_v"] = sub(v_c, v)
	disp["range_rate"] = dot(disp["rel_v"], zbd)
	var ur := unit(r)
	var k := MU / pow(length(r), 3)
	_grad = [k * (3.0 * ur[0] * ur[0] - 1.0), k * (3.0 * ur[0] * ur[2]), k * (3.0 * ur[2] * ur[2] - 1.0)]


## Branches 8 to 10 (figure 7.19): the LM's orbit and the unit vectors of
## its position against the CSM's plane.
func _lm_orbit() -> void:
	var rn := length(r)
	var hdot: float = disp["hdot"]
	var vh2 := dot(v, v) - hdot * hdot
	disp["vh2"] = vh2
	var p := rn * rn * vh2 / MU
	var e2 := pow(p / rn - 1.0, 2) + hdot * hdot * p / MU
	var q := Q_OVERFLOW if e2 >= 1.0 / 64.0 else p / (1.0 + sqrt(e2))
	disp["q_lt"] = q - j5
	var o := orbit_params(r, v)
	disp["t_perg"] = (TAU - atan2(float(o["s"]), float(o["c"])) + float(o["s"])) / float(o["n"])
	disp["q_a"] = 2.0 * (float(o["a"]) - j5) - float(disp["q_lt"])
	disp["y"] = dot(w_c, r)
	disp["v_y0"] = dot(w_c, v)
	u1 = mul(r, 1.0 / rn)
	v1 = unit(cross(w_c, u1))
	w1 = cross(u1, v1)


# -- the radar filter (figures 7.16 to 7.18) --------------------------------

## FINIT: P diagonal, the first range's Δt long.
func p_init() -> void:
	p_cov = PackedFloat64Array()
	p_cov.resize(16)
	p_cov[0] = P_POS
	p_cov[5] = P_POS
	p_cov[10] = P_VEL
	p_cov[15] = P_VEL
	t_1 = j29
	s17 = 0


func _p(i: int, j: int) -> float:
	return p_cov[(i - 1) * 4 + (j - 1)]


func _set_p(i: int, j: int, val: float) -> void:
	p_cov[(i - 1) * 4 + (j - 1)] = val
	p_cov[(j - 1) * 4 + (i - 1)] = val


## S15 (415): the Z body axis [param z_b] (inertial) and the computed range
## vector and range rate saved for the radar reading to come, with the time
## since the last range update.
func mark(z_b: PackedFloat64Array) -> void:
	z_star = unit(z_b)
	r_star = sub(r_c, r)
	rdot_star = float(disp["range_rate"])
	dt_star = t - t_1


## Branches 6 and 7: P carried every 16 s (eight cycles), and a radar range
## (J18) or range rate (J17) taken in then. The filter holds the in-plane
## state (the AGS frame's x and z, the CSM's plane within 10 deg of them)
## and moves the out-of-plane position and velocity by constant gains.
func _radar_filter() -> void:
	mu17 += 1
	if mu17 != 8:
		return
	mu17 = 0
	var a: float = _grad[0]
	var c: float = _grad[1]
	var jj: float = _grad[2]
	var p11 := _p(1, 1) + 32.0 * _p(1, 3) + 8192.0
	var p12 := _p(1, 2) + 16.0 * (_p(1, 4) + _p(2, 3))
	var p13 := _p(1, 3) + 16.0 * (_p(3, 3) + a * _p(1, 1) + c * _p(1, 2))
	var p14 := _p(1, 4) + 16.0 * (_p(3, 4) + c * _p(1, 1) + jj * _p(1, 2))
	var p44 := _p(4, 4) + 32.0 * (c * _p(1, 4) + jj * _p(2, 4)) + 1.0 / 128.0
	var p22 := _p(2, 2) + 32.0 * _p(2, 4) + 8192.0
	var p23 := _p(2, 3) + 16.0 * (_p(3, 4) + a * _p(1, 2) + c * _p(2, 2))
	var p24 := _p(2, 4) + 16.0 * (_p(4, 4) + c * _p(1, 2) + jj * _p(2, 2))
	var p33 := _p(3, 3) + 32.0 * (a * _p(1, 3) + c * _p(2, 3)) + 1.0 / 128.0
	var p34 := _p(3, 4) + 16.0 * (a * _p(1, 4) + c * _p(2, 4) + c * _p(1, 3) + jj * _p(2, 3))
	for e in [[1, 1, p11], [1, 2, p12], [1, 3, p13], [1, 4, p14], [2, 2, p22], [2, 3, p23], [2, 4, p24],
			[3, 3, p33], [3, 4, p34], [4, 4, p44]]:
		_set_p(e[0], e[1], e[2])
	if s17 != 0:
		p_init()
	if j17 != 0.0:
		_radar_rate()
	elif j18 > 0.0:
		_radar_range()
	j18 = 0.0


## RATE: a range rate's update.
func _radar_rate() -> void:
	var dr1 := j17 - rdot_star
	j17 = 0.0
	var rn: float = disp["range"]
	var u: PackedFloat64Array = disp["z_bd"]
	var rel_v: PackedFloat64Array = disp["rel_v"]
	var rdot: float = disp["range_rate"]
	var m := [(rdot * u[0] - rel_v[0]) / rn, (rdot * u[2] - rel_v[2]) / rn, -u[0], -u[2]]
	var l1 := []
	for i in range(1, 5):
		l1.append(_p(i, 1) * m[0] + _p(i, 2) * m[1] + _p(i, 3) * m[2] + _p(i, 4) * m[3])
	var q11: float = m[0] * l1[0] + m[1] * l1[1] + m[2] * l1[2] + m[3] * l1[3] + VAR_RDOT
	_filter_update(q11, 0.0, 1.0, l1, [0.0, 0.0, 0.0, 0.0], dr1, 0.0)


## RANGE: a range's update, the reading along the saved Z axis.
func _radar_range() -> void:
	var meas := mul(z_star, j18)
	var dr1: float = meas[0] - r_star[0]
	var dr2: float = meas[2] - r_star[2]
	var dr3: float = meas[1] - r_star[1]
	t_1 = t
	r[1] += K_OUT_POS * dr3
	if dt_star > 0.0:
		v[1] += K_OUT_VEL * dr3 / dt_star
	var u: PackedFloat64Array = disp["z_bd"]
	var rel: PackedFloat64Array = sub(r_c, r)
	var q11 := _p(1, 1) + VAR_RANGE * u[0] * u[0] + rel[2] * rel[2] * VAR_ANGLE
	var q22 := _p(2, 2) + VAR_RANGE * u[2] * u[2] + rel[0] * rel[0] * VAR_ANGLE
	var q12 := _p(1, 2) - rel[0] * rel[2] * VAR_ANGLE
	var l1 := [-_p(1, 1), -_p(1, 2), -_p(1, 3), -_p(1, 4)]
	var l2 := [_p(2, 1), _p(2, 2), _p(2, 3), _p(2, 4)]
	_filter_update(q11, q12, q22, l1, l2, dr1, dr2)


## FLTRJ and FLTRK: the gains B from L and Q, the in-plane state moved by
## them, and P after.
func _filter_update(q11: float, q12: float, q22: float, l1: Array, l2: Array, dr1: float, dr2: float) -> void:
	var det := q11 * q22 - q12 * q12
	if det == 0.0:
		return
	var b1 := []
	var b2 := []
	for i in 4:
		b1.append((q22 * float(l1[i]) + q12 * float(l2[i])) / det)
		b2.append(-(q11 * float(l2[i]) + q12 * float(l1[i])) / det)
	r[0] += b1[0] * dr1 + b2[0] * dr2
	r[2] += b1[1] * dr1 + b2[1] * dr2
	v[0] += b1[2] * dr1 + b2[2] * dr2
	v[2] += b1[3] * dr1 + b2[3] * dr2
	var np := p_cov.duplicate()
	for i in 4:
		for j in range(i, 4):
			np[i * 4 + j] = p_cov[i * 4 + j] - b1[i] * float(l1[j]) + b2[i] * float(l2[j])
			np[j * 4 + i] = np[i * 4 + j]
	p_cov = np


# -- guidance (figures 7.20 to 7.30) --------------------------------------

## Branch 11 on: the routine S10 selects, then the steering.
func _guidance(axes: Array) -> void:
	if s10 >= 5:
		_external_dv(axes)
		return
	if s10 <= 0:
		t_delta = 0.0
		_predict(r, v, axes)
		return
	if s10 != 3:
		t_delta = t_ig - t
	t_ig = t + t_delta
	disp["t_r"] = t_delta + j6
	if t_delta < 0.0:
		t_delta = 0.0
	s07 = 0
	var st := ellipse(r, v, t_delta, orbit_params(r, v)) if t_delta > 0.0 else [r, v]
	_predict(st[0], st[1], axes)


## DXFR10 to DXFR14: the LM's state at the maneuver ([param r5],
## [param v5]) against the CSM's, then the routine's own branches.
func _predict(r5: PackedFloat64Array, v5: PackedFloat64Array, axes: Array) -> void:
	var rf := length(r5)
	var u := mul(r5, 1.0 / rf)
	u1 = u
	var rdot_a := dot(v5, u)
	disp["rdot_a"] = rdot_a
	disp["v_py"] = dot(v5, w_c)
	var v_ha := length(v5)
	var period: float = csm_orbit["period"]
	var ti := (t - t_e - period) + t_delta
	if ti >= 0.0:
		ti -= period
	var cst := ellipse(r_e, v_e, ti, csm_orbit)
	var rel := sub(cst[0], r5)
	var v1p := unit(cross(w_c, u))
	var rx := dot(u, rel)
	var rz := dot(v1p, rel)
	var n_e: float = csm_orbit["n"]
	if s10 >= 3:
		disp["theta_los"] = fposmod(atan2(rx, rz), TAU)
		var tr: float = disp["t_r"]
		_tpi(v5, u, rf, (t - t_e - period) + tr - j3, tr - t_delta, axes)
		return
	var theta := fposmod(atan2(rz, rx + rf), TAU)
	ti -= (theta - TAU) / n_e
	if theta > PI:
		theta -= TAU
	disp["theta_f"] = theta
	if s10 <= 0:
		_insertion(rf, rdot_a, theta, axes)
		return
	var tst := ellipse(r_e, v_e, ti, csm_orbit)
	_csi_cdh(rf, rdot_a, v_ha, theta, tst[0], tst[1], axes)


## CSICDH (figure 7.28): CSI's horizontal burn for the line of sight's
## angle at TPI time after a CDH half or three halves of an orbit on, or
## CDH's coelliptic burn.
func _csi_cdh(rf: float, rdot_a: float, v_ha: float, theta: float, r_t: PackedFloat64Array,
		v_t: PackedFloat64Array, axes: Array) -> void:
	var rt := length(r_t)
	var u2 := mul(r_t, 1.0 / rt)
	var dr := rt - rf
	var big_dr := dr
	var rdot_f := dot(u2, v_t)
	var a_e: float = csm_orbit["a"]
	var n_e: float = csm_orbit["n"]
	disp["dr"] = dr
	if s10 == 2:
		t_ig += float(disp["t_a0"])
		disp["t_a0"] = 0.0
	else:
		var a := 0.75 * PI * s16
		var b := j2 + 1.5 * n_e * (j1 - t_ig) - a + 1.5 * a * dr / a_e
		var c := theta - a * dr / a_e + 4.0 * (rdot_a - rdot_f) / v_ha
		big_dr = c / b * a_e
		disp["v_p0"] = sqrt(pow(n_e / 4.0 * (dr - big_dr), 2) + pow(rdot_a - rdot_f, 2))
		disp["t_a0"] = (PI * s16 - a * dr / a_e - a * big_dr / a_e) / n_e
		rdot_f = rdot_a
	disp["Dr"] = big_dr
	var alpha_l := a_e - dr / 2.0 - big_dr / 2.0
	var v_hf := sqrt(MU * (2.0 * alpha_l - rf) / (alpha_l * rf))
	j28_1 = v_hf - v_ha
	j28_3 = rdot_a - rdot_f
	_external_dv(axes)


## OI1 and GDLAW (figures 7.28, 7.29): orbit insertion's targets, the
## semimajor axis from the phase angle to the CSM, and its guidance law,
## which holds the radial and out-of-plane jerks constant to reach the
## injection altitude and radial rate with the velocity.
func _insertion(rf: float, rdot_a: float, theta: float, axes: Array) -> void:
	var vh2: float = disp["vh2"]
	var vy0: float = disp["v_y0"]
	var v_ha := sqrt(maxf(vh2 - vy0 * vy0, 0.0))
	if r_b < j5:
		r_b = rf
	var rdot_f := clampf(RDOT_SLOPE * (RDOT_RADIUS - r_b), j23, RDOT_MAX)
	var alpha_l := clampf(j7 + ALPHA_SLOPE * theta, j8, j9)
	disp["alpha_l"] = alpha_l
	var r_f := r_b
	var v_hf := sqrt(maxf(MU * (2.0 * alpha_l - r_f) / (alpha_l * r_f), 0.0))
	j28_1 = v_hf - v_ha
	j28_3 = rdot_a - rdot_f
	# GDLAW.
	vg_mag = sqrt(j28_1 * j28_1 + j28_3 * j28_3 + vy0 * vy0)
	var tb := maxf(vg_mag / a_t * (1.0 + TB_K2 * vg_mag + TB_K3 * vg_mag * vg_mag), CYCLE)
	var rdd := (rdot_f - rdot_a - 0.5 * rddd * tb * tb) / tb
	var ydd := (-vy0 - 0.5 * yddd * tb * tb) / tb
	var y: float = disp["y"]
	var rn := length(r)
	var r_pred := rn + rdot_a * tb + 0.5 * rdd * tb * tb + rddd * tb * tb * tb / 6.0
	r_b = r_pred
	disp["r_f"] = r_pred
	var y_f := y + vy0 * tb + 0.5 * ydd * tb * tb + yddd * tb * tb * tb / 6.0
	var rddd_min := RDDD_MIN_LOW_THRUST if d2 and a_t <= LOW_THRUST else RDDD_MIN
	rddd = clampf(rddd + 12.0 / pow(tb, 3) * (r_pred - j16 - j5), rddd_min, RDDD_MAX)
	yddd = clampf(yddd + 12.0 / pow(tb, 3) * y_f, YDDD_MIN, YDDD_MAX)
	rdd += MU / (rn * rn) - vh2 / rn
	# STEER (figure 7.30).
	var psi_p := rdd / a_t
	var psi_y := ydd / a_t
	if float(disp["h"]) <= j21 and float(disp["hdot"]) <= j22:
		psi_p = 1.0
		vg_mag = VG_VERTICAL
	_steer(psi_p, psi_y, axes)


## The pitch and yaw steering's desired thrust direction, held once
## thrusting within VG_FREEZE of the cutoff.
func _steer(psi_p: float, psi_y: float, axes: Array) -> void:
	if not (mu8 != 0 and vg_mag < VG_FREEZE):
		psi_p = clampf(psi_p, -1.0, 1.0)
		var lim := sqrt(maxf(1.0 - psi_p * psi_p, 0.0))
		psi_y = clampf(psi_y, -lim, lim)
		var h := sqrt(maxf(1.0 - psi_p * psi_p - psi_y * psi_y, 0.0))
		var sgn := -1.0 if j28_1 < 0.0 else 1.0
		x_bd = add(add(mul(u1, psi_p), mul(v1, sgn * h)), mul(w1, psi_y))
		vg = mul(x_bd, vg_mag)
	_body_vg(axes)


## XDV (figure 7.20): the external ΔV, or TPI's, frozen when the burn
## starts, less the ΔV sensed since.
func _external_dv(axes: Array) -> void:
	if s07 == 0:
		if mu8 > 0:
			s07 = 1
		else:
			if j28_1 < NO_SOLUTION:
				dv_ext = add(add(mul(u1, -j28_3), mul(v1, j28_1)), mul(w1, -j28_2))
			else:
				dv_ext = vg_tpi.duplicate()
			dq_s = vec(0.0, 0.0, 0.0)
	vg = sub(dv_ext, dq_s)
	vg_mag = length(vg)
	if not (mu8 != 0 and vg_mag < VG_FREEZE) and vg_mag > 0.0:
		x_bd = mul(vg, 1.0 / vg_mag)
	_body_vg(axes)


## STEER5: the velocity to be gained along each body axis ([X_b, Y_b,
## Z_b] in [param axes]), which the 40-ms engine logic counts down.
func _body_vg(axes: Array) -> void:
	disp["vg_mag"] = vg_mag
	disp["vg_body"] = vec(vg_mag * dot(x_bd, axes[0]), vg_mag * dot(x_bd, axes[1]), vg_mag * dot(x_bd, axes[2]))


# -- TPI (figures 7.23 to 7.27) ---------------------------------------------

## The direct transfer from the LM at the maneuver (its velocity
## [param v5], position unit vector [param u] and radius [param rf]) to the
## CSM [param tr_i] from its epoch (less a period), taking
## [param tt] seconds, by the p-iterator; its velocity to be gained and the
## braking impulse at the CSM (V_T their sum), or NO_SOLUTION.
func _tpi(v5: PackedFloat64Array, u: PackedFloat64Array, rf: float, tr_i: float, tt: float,
		axes: Array) -> void:
	j28_1 = NO_SOLUTION
	var sol := _transfer(v5, u, rf, tr_i, tt)
	if sol.is_empty():
		disp["v_t"] = NO_SOLUTION
		disp["q_ld"] = -j5
	else:
		vg_tpi = sol["vg"]
		disp["v_t"] = length(sol["vg"]) + length(sol["vf"])
		disp["q_ld"] = float(sol["q"]) - j5
	_external_dv(axes)


## The transfer: {vg (inertial), vf, q (the transfer's pericynthion radius)},
## empty without a solution.
func _transfer(v5: PackedFloat64Array, u: PackedFloat64Array, rf: float, tr_i: float,
		tt: float) -> Dictionary:
	var target := ellipse(r_e, v_e, tr_i, csm_orbit)
	var geom := _transfer_vectors(u, target[0])
	if geom.is_empty():
		return {}
	var p := _p_iterate(rf, float(geom["rt"]), float(geom["c1"]), float(geom["c2"]), tt)
	if p.is_empty():
		return {}
	if j4 != 0.0:
		# The node: the same transfer aimed J4 before the rendezvous.
		var node := ellipse(r_e, v_e, tr_i - j4, csm_orbit)
		var g2 := _transfer_vectors(u, node[0])
		if not g2.is_empty():
			geom = g2
			target = node
	var pp: float = p["p"]
	var rt: float = geom["rt"]
	var sqp := sqrt(MU * pp)
	var rdot_i := add(mul(u, sqrt(MU / pp) * float(p["x3"])), mul(geom["v1"], sqp / rf))
	var rdot_fin := add(mul(geom["u2"], sqrt(MU / pp) * float(p["x4"])), mul(geom["v2"], sqp / rt))
	return {"vg": sub(rdot_i, v5), "vf": sub(rdot_fin, target[1]),
		"q": float(p["a"]) * (1.0 - sqrt(float(p["e2"])))}


## TRANSFER VECTORS: the central angle's cosine and sine (c1, c2) from
## the LM's [param u] to the target [param rt_v], and the transfer plane's
## unit vectors; empty inside SIN_CENTRAL_MIN of a multiple of π.
func _transfer_vectors(u: PackedFloat64Array, rt_v: PackedFloat64Array) -> Dictionary:
	var rt := length(rt_v)
	var u2 := mul(rt_v, 1.0 / rt)
	var c1 := dot(u, u2)
	var c2 := sqrt(maxf(1.0 - c1 * c1, 0.0))
	if c2 < SIN_CENTRAL_MIN:
		return {}
	# Its sign by W1's and W_c's components along the frame's y axis, which
	# FP6 takes for the orbits' normal (the frame's XZ plane within 80 deg
	# of the LM's orbit).
	var wv := cross(u, u2)
	if wv[1] * w_c[1] < 0.0:
		c2 = -c2
	return {"rt": rt, "u2": u2, "c1": c1, "c2": c2, "v1": mul(sub(u2, mul(u, c1)), 1.0 / c2),
		"v2": mul(sub(mul(u2, c1), u), 1.0 / c2)}


## The p-iterator (figure 7.25): the semi-latus rectum of the conic from
## radius [param r1] to [param r2] across the central angle (cosine
## [param c1], sine [param c2]) in [param tt] seconds, in eight trials from
## p = r1 + 2K14: {p, x3, x4, e2, a}, or empty.
func _p_iterate(r1: float, r2: float, c1: float, c2: float, tt: float) -> Dictionary:
	var p := r1 + P_PERTURB
	var p_old := 0.0
	var t_old := 0.0
	var dpdt := 0.0
	for mu3 in range(1, P_ITERATIONS + 4):
		var x1 := p / r1 - 1.0
		var x2 := p / r2 - 1.0
		var x3 := (c1 * x1 - x2) / c2
		var x4 := (x1 - c1 * x2) / c2
		var e2 := x1 * x1 + x3 * x3
		if e2 >= 0.25:
			return {}
		var se := sqrt(1.0 - e2)
		var x8 := (r1 / p) * se * x3
		var x9 := (r2 / p) * se * x4
		var s_de := se * (c2 + x4 - x3)
		var c_de := c1 + e2 + x1 + x2 - x3 * x4
		var a := p / (1.0 - e2)
		var de := fposmod(atan2(s_de, c_de), TAU)
		var tp := sqrt(a * a * a / MU) * (de + x8 - x9)
		if mu3 == P_ITERATIONS + 3:
			if absf(tt - tp) < P_CONVERGED:
				return {"p": p, "x3": x3, "x4": x4, "e2": e2, "a": a}
			return {}
		if mu3 == 1:
			p_old = p
			t_old = tp
			p -= P_PERTURB
			continue
		if mu3 == 2 or absf(tp - t_old) >= P_PARTIAL_MIN:
			dpdt = (p - p_old) / (tp - t_old)
		var dp := clampf((tt - tp) * dpdt, -P_STEP_MAX, P_STEP_MAX)
		p_old = p
		t_old = tp
		p += dp
	return {}


# -- checkpoints ----------------------------------------------------------

func snapshot() -> Dictionary:
	var d := {}
	for k in SAVED:
		d[k] = _plain(get(k))
	return d


func restore(d: Dictionary) -> void:
	for k in SAVED:
		if not d.has(k):
			continue
		var cur: Variant = get(k)
		var val: Variant = d[k]
		if cur is PackedFloat64Array:
			set(k, PackedFloat64Array(val))
		elif cur is Dictionary:
			var out := {}
			for key in val:
				var x: Variant = val[key]
				out[key] = PackedFloat64Array(x) if x is Array else float(x)
			set(k, out)
		elif cur is bool:
			set(k, bool(val))
		elif cur is int:
			set(k, int(val))
		else:
			set(k, float(val))


static func _plain(v: Variant) -> Variant:
	if v is PackedFloat64Array:
		return Array(v)
	if v is Dictionary:
		var out := {}
		for key in v:
			out[key] = _plain(v[key])
		return out
	return v

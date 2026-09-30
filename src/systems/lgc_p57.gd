## Luminary's P57, lunar surface alignment, for the LGC (slice 11b): the
## platform aligned on the Moon, where the LM can't turn to put a star on
## the AOT's lines, from the gravity vector the accelerometers measure, a
## stored attitude and stars sighted with the reticle's cursor and spiral
## (src/systems/aot.gd), on the displays of Luminary 099's P57, its
## gravity determination GVDETER, R59 and AOTMARK's surface marks
## [published: Luminary 099, log sections P51-P53 and AOTMARK]:
##
##   V04N06   the option: 3 REFSMMAT (offered), 4 landing site, 1
##            preferred; 2 is no option on the surface. PRO
##   V06N34   (4) the orientation's time, TALIGN: the ascent's TIG
##            offered, 0 for now; a later time is P12's TIG too. PRO: X
##            up through the LM at TALIGN, Z along the CSM's orbit's
##            normal crossed with it (LSORIENT)
##   V05N06   R1 00010, R2 the technique the crew loads (V22): 0 the stored
##            attitude, 1 REFSMMAT and gravity, 2 two stars, 3 gravity and
##            a star; R3 the flags, 00100 REFSMMAT known and 00010 an
##            attitude stored. PRO: with REFSMMAT known the LM's attitude
##            is stored first, Moon-fixed (REFMF); with neither flag, 0 and
##            1 are alarm 00701 (V05N09, PRO or V32 back to V05N06)
##   GVDETER  (1 and 3) the IMU coarse aligns to gimbal angles 42, -42
##            and 35 deg, the PIPAs read gravity for 20 x 2 s, it turns
##            180 deg about that and reads again, and the two average out
##            the PIPAs' biases [simplified: the specific force read as it
##            is, the plumb line through the Moon's field; the biases,
##            the counts' quantization and the Moon's spin left out]
##   V06N04   the angle between this gravity vector and the last (0 before
##            one: ACOS of nothing, 90 deg); PRO takes it, V32 stores it
##            and measures again
##   With an attitude stored, a first pass aligns to it (the platform's
##   orientation, lost in GVDETER's turns, found again): V06N22 the
##   gimbal angles and PRO for the coarse align, or the gyros torqued
##   under 5 deg; no N05 or N93. Then the technique's own pass:
##   0, 1      the stored attitude's Y and Z, or the landing site's
##            vertical and its Z, against the body's axes and gravity
##   2, 3      for each star R59: V01N70 the star (V21), PRO: the detent
##            whose field holds it (within 30 deg of its axis, 1 to 6 in
##            turn) and V06N79 the cursor and spiral angles that find it
##            there and the detent (alarm 00404 in none: V05N09, PRO marks
##            without, V32 another star); PRO. V01N71 the detent and star,
##            PRO; V54N71: MARK X or Y takes the CDU angles, V06N79 asks
##            for the counter's readings (V21 cursor, V22 spiral, ENTER),
##            V32 another mark (up to MAX_MARKS, alarm 00107), PRO ends
##            them; REJECT drops the latest (alarm 00115 but for one);
##            each mark's star is SURFSTAR's, and they average
##   V06N05   the star angle difference; PRO (V32 to the check)
##   V06N93   the gyro torquing angles; PRO: torqued, or past 5 deg coarse
##            aligned and trimmed; REFSMMAT is the new orientation and the
##            attitude is stored (V32: neither, on to the check)
##   V50N25 00014  PRO aligns again by the technique; ENTER ends P57, for
##            2 after V06N89: the landing site that gravity and the two
##            stars' platform give (PRO takes it into the LM's state
##            vector, V34 rejects it)
## P57 needs the IMU (alarm 00210) and the LM on the surface (alarm 01520:
## [adapted] Luminary took V37E57E anywhere, its gravity meaningless in
## flight).
class_name LgcSurfaceAlign
extends RefCounted

## GVDETER's first orientation's gimbal angles, outer, inner, middle, deg,
## its reads and their interval, s [published: GVDETER's THETAD, T/2SEC
## and 2SECS].
const GRAVITY_GIMBALS_DEG := Vector3(42.0, -42.0, 35.0)
const GRAVITY_READS := 20
const GRAVITY_READ_S := 2.0
## Gyro torquing past this about any axis coarse aligns instead, deg
## [published: 5DEGTEST].
const COARSE_PAST_DEG := 5.0
## R59: a star within this of a detent's axis is in its field; within
## ON_AXIS_DEG, at its centre (cursor and spiral zero), deg [published:
## R59's DEG30 and DEG.5].
const FIELD_HALF_DEG := 30.0
const ON_AXIS_DEG := 0.5
## The marks a star takes [published: AOTMARK's surface marks].
const MAX_MARKS := 5

var lgc: AgcCore
## The option (V04N06), the technique (V05N06), TALIGN (N34, GET s) and
## the orientation they give, XSMD (reference to stable member).
var option: int = 3
var technique: int = 0
var talign: float = 0.0
var orientation: Basis = Basis.IDENTITY
## INITALGN: the first pass, on the stored attitude.
var initial: bool = false
## GSAV: gravity (up, the PIPAs' reading) in body axes; the latest
## determination and N04's angle between them, deg.
var gsav: Vector3 = Vector3.ZERO
var gravity: Vector3 = Vector3.ZERO
var n04_deg: float = 0.0
## ATTFLG and the stored attitude, the body's Y and Z axes, Moon-fixed
## (YNBSAV, ZNBSAV).
var attitude_stored: bool = false
var ynb_mf: Vector3 = Vector3.ZERO
var znb_mf: Vector3 = Vector3.ZERO
## AOTCODE (detent * 100 + star, as N70 and N71 show it), the star being
## sighted (STARIND: 0 the first of two, 1 the second or only one), R59's
## detent and the cursor and spiral angles (N79, deg).
var aotcode: int = 0
var star_i: int = 0
var poscode: int = 0
var cursor: float = 0.0
var spiral: float = 0.0
## The surface marks on the star being sighted: each {"cdu", "cursor",
## "spiral"}, and the one waiting for its readings (or null).
var marks: Array = []
var pending: Variant = null
## The two pairs SURFLINE aligns with: each vector in the reference frame
## (VEC1, VEC2) and as the platform sees it (STARSAV1, STARSAV2), and the
## stars sighted (their codes).
var refs: Array = [Vector3.ZERO, Vector3.ZERO]
var observed: Array = [Vector3.ZERO, Vector3.ZERO]
var stars: Array = [0, 0]
## N05 (deg), the torque that takes the platform onto XSMD (rad, stable
## member axes, as Imu.torque() takes it), and a coarse align's gimbals.
var sad_deg: float = 0.0
var torque: Vector3 = Vector3.ZERO
var coarse_target: Basis = Basis.IDENTITY
## Technique 2's landing site from gravity (N89), Moon-fixed, m.
var site_mf: Vector3 = Vector3.ZERO
## GVDETER's progress: "" or the phase ("coarse1", "read1", "coarse2",
## "read2"), the read's end (GET s) and the first orientation's reading
## (body axes).
var _g_phase: String = ""
var _g_until: float = 0.0
var _g_first: Vector3 = Vector3.ZERO
var _x_was: bool = false
var _y_was: bool = false
var _reject_was: bool = false


func _init(computer: AgcCore) -> void:
	lgc = computer


## P57 from V37: V04N06 with option 3, if the IMU runs.
func start() -> void:
	_g_phase = ""
	marks = []
	pending = null
	if lgc.imu.failed:
		lgc._alarm(210)   # IMU not operating
		lgc.change_program(0)
		return
	option = 3
	_show("option")


func proceed() -> void:
	match lgc.step_name:
		"option":
			match option:
				4:
					talign = lgc.tig_load
					_show("n34")
				1:
					if not lgc.preferred_valid:
						lgc._alarm(215)   # no preferred orientation
						return
					orientation = lgc.preferred_refsmmat
					_technique_display()
				3:
					orientation = lgc.imu.refsmmat
					_technique_display()
				_:
					_show("option")   # 2: no option on the surface
		"n34":
			if not _landing_site_orientation():
				lgc.dsky.set_lamp("opr_err", true)
				return
			_technique_display()
		"technique":
			_technique_chosen()
		"no_attitude":
			_show("technique")
		"n04":
			gsav = gravity
			_attitude_check()
		"n22":
			_coarse()
		"n70":
			_acquire()
		"n79_acquire":
			aotcode = poscode * 100 + _star()
			_show("n71")
		"no_detent":
			_show("n71")
		"n71":
			var d := _detent()
			if d < 1 or d > 6 or not Stars.has(_star()):
				lgc.dsky.set_lamp("opr_err", true)   # not a detent (or a star) it can mark with
				return
			marks = []
			pending = null
			_show("marks")
		"marks":
			_marks_done()
		"n79":
			_complete_mark()
			_marks_done()
		"n05":
			_show("n93")
		"n93":
			_trim_or_coarse()
		"check":
			_realign()
		"n89":
			var l := lgc as Lgc
			l.nav_landed_mf = site_mf
			lgc.change_program(0)


## ENTER at a flashing display: V50N25 00014 ends P57 (technique 2 first
## shows its landing site); V01N70, V01N71, V06N79 and V06N89 show again,
## but R59's V06N79 goes back to V01N70; V54N71 goes back to V01N71, the
## marks dropped.
func enter(v: int, n: int) -> bool:
	var took := false
	match lgc.step_name:
		"check":
			took = v == 50 and n == 25
			if took:
				if technique == 2:
					_site_from_gravity()
					_show("n89")
				else:
					lgc.change_program(0)
		"n70", "n71":
			took = v == 1 and n in [70, 71]
			if took:
				_show(lgc.step_name)
		"n79", "n89":
			took = v == 6 and n in [79, 89]
			if took:
				_show(lgc.step_name)
		"n79_acquire":
			# 79DISP's third return, V32's too: R59 again.
			took = v == 6 and n == 79
			if took:
				_show("n70")
		"marks":
			took = v == 54 and n == 71
			if took:
				marks = []
				pending = null
				_show("n71")
	return took


## V32: back to V04N06 or V05N06 or N34 or N22 (shown again); at N04
## gravity measured again; at N79 in R59 or its alarm, another star; at
## N79 in the marks, another mark; at N05 and N93 on to the check.
func recycle() -> bool:
	match lgc.step_name:
		"option", "technique", "n34", "n22", "n70", "n89":
			_show(lgc.step_name)
		"no_attitude":
			_show("technique")
		"n04":
			gsav = gravity
			_gravity()
		"n79_acquire", "no_detent":
			_show("n70")
		"n79":
			if marks.size() + (0 if pending == null else 1) >= MAX_MARKS:
				lgc._alarm(107)   # five marks already
				return true
			_complete_mark()
			_show("marks")
		"n05", "n93":
			_check()
		_:
			return false
	return true


## Each step: GVDETER's turns and reads, a coarse align's end, and the
## marks.
func step() -> void:
	if lgc.program != 57:
		_read_marks()
		return
	match lgc.step_name:
		"gravity":
			_gravity_step()
		"coarse":
			if lgc.imu.operating():
				# GYROTRIM: the gyros take the gimbals onto the angles the
				# coarse align drove at.
				lgc.imu.torque(Imu.rotation_vector(coarse_target * Imu.gimbal_basis(lgc.icdu()).transposed()))
				_surface_display()
	_read_marks()


func noun_values(n: int) -> Variant:
	var v: Variant = null
	match n:
		4:
			v = [n04_deg, 0.0, 0.0]
		5:
			v = [sad_deg, 0.0, 0.0]
		6:
			if lgc.step_name in ["technique", "no_attitude"]:
				v = [10.0, float(technique), (100.0 if lgc.imu.aligned else 0.0) + (10.0 if attitude_stored else 0.0)]
			else:
				v = [1.0, float(option), 0.0]
		22:
			var g := Imu.gimbal_angles(coarse_target)
			v = [g.x, g.y, g.z]
		25:
			v = [14.0, 0.0, 0.0]
		34:
			v = [talign, talign, talign]
		70, 71:
			v = [float(aotcode), 0.0, 0.0]
		79:
			v = [cursor, spiral, float(poscode)]
		89:
			var s := Bodies.fixed_to_selenographic(site_mf)
			v = [s.x, s.y / 2.0, s.z - Bodies.R_MOON]
		93:
			# The platform's own turn, as N93 shows it (Imu.torque() takes
			# the reverse).
			var t := -torque * (180.0 / PI)
			v = [t.x, t.y, t.z]
	return v


func noun_load(n: int, idx: int, value: float) -> bool:
	var ok := false
	match n:
		6:
			ok = idx == 1 and ((lgc.step_name == "option" and int(value) in [1, 2, 3, 4])
				or (lgc.step_name == "technique" and int(value) in [0, 1, 2, 3]))
			if ok and lgc.step_name == "option":
				option = int(value)
			elif ok:
				technique = int(value)
		34:
			ok = lgc.step_name == "n34"
			if ok:
				var parts := [floorf(talign / 3600.0) * 3600.0, floorf(fmod(talign, 3600.0) / 60.0) * 60.0, fmod(talign, 60.0)]
				parts[idx] = value
				talign = parts[0] + parts[1] + parts[2]
		70, 71:
			ok = idx == 0 and lgc.step_name in ["n70", "n71"] and _code_ok(value)
			if ok:
				aotcode = int(value)
		79:
			ok = lgc.step_name in ["n79", "n79_acquire"] and value >= 0.0 and value < 360.0
			if ok:
				match idx:
					0:
						cursor = value
					1:
						spiral = value
					2:
						poscode = int(value)
	return ok


# --- the flow ---------------------------------------------------------------------

## Step [param s] and its display.
func _show(s: String) -> void:
	lgc.step_name = s
	match s:
		"option":
			lgc.dsky.show(4, 6, true)
		"n34":
			lgc.dsky.show(6, 34, true)
		"technique":
			lgc.dsky.show(5, 6, true)
		"no_attitude", "no_detent":
			lgc.dsky.show(5, 9, true)
		"gravity":
			lgc.dsky.show(5, 6)
		"n04":
			lgc.dsky.show(6, 4, true)
		"n22":
			lgc.dsky.show(6, 22, true)
		"coarse":
			lgc.dsky.show(16, 20)
		"n70":
			lgc.dsky.show(1, 70, true)
		"n79_acquire", "n79":
			lgc.dsky.show(6, 79, true)
		"n71":
			lgc.dsky.show(1, 71, true)
		"marks":
			lgc.dsky.show(54, 71, true)
		"n05":
			lgc.dsky.show(6, 5, true)
		"n93":
			lgc.dsky.show(6, 93, true)
		"check":
			lgc.dsky.show(50, 25, true)
		"n89":
			lgc.dsky.show(6, 89, true)


## PACKOPTN: V05N06, technique 0 offered.
func _technique_display() -> void:
	technique = 0
	_show("technique")


## PRO at V05N06: with REFSMMAT known, the attitude stored from it; with
## neither it nor one stored, gravity and a star or two stars only (alarm
## 00701). Then BYLMATT: the first pass to come, and gravity for 1 and 3.
func _technique_chosen() -> void:
	if lgc.imu.aligned:
		_store_attitude()
	elif not attitude_stored and technique < 2:
		lgc._alarm(701)   # the technique inconsistent with the flags
		_show("no_attitude")
		return
	initial = true
	if technique in [1, 3]:
		_gravity()
	else:
		_attitude_check()


## ATTCHK: with an attitude stored, the first pass on it; else the
## technique's.
func _attitude_check() -> void:
	if attitude_stored:
		_pass(0)
	else:
		_realign()


## P57JUMP: the technique's own pass.
func _realign() -> void:
	initial = false
	_pass(technique)


## The pass for technique [param t]: its two pairs, from the stored
## attitude (0), the landing site's vertical and the stored Z (1), or
## the stars sighted (2, 3; R59 and the marks first).
func _pass(t: int) -> void:
	var g := Imu.gimbal_basis(lgc.icdu())
	match t:
		0:
			refs = [_mf_to_ref(ynb_mf), _mf_to_ref(znb_mf)]
			observed = [g * Vector3(0, 1, 0), g * Vector3(0, 0, 1)]
			_surfline()
		1:
			refs = [_mf_to_ref(_rls_mf().normalized()), _mf_to_ref(znb_mf)]
			observed = [g * gsav, g * Vector3(0, 0, 1)]
			_surfline()
		2:
			star_i = 0
			_r59()
		3:
			refs[0] = _mf_to_ref(_rls_mf().normalized())
			observed[0] = g * gsav
			star_i = 1
			_r59()


## SURFLINE: AXISGEN's torque from the two pairs, the vectors as XSMD
## puts them against the platform's; N05 first but on the first pass.
func _surfline() -> void:
	var e1: Vector3 = orientation * (refs[0] as Vector3)
	var e2: Vector3 = orientation * (refs[1] as Vector3)
	torque = Imu.rotation_vector(Imu.triad(e1, e2) * Imu.triad(observed[0], observed[1]).transposed())
	if initial:
		_trim_or_coarse()
		return
	sad_deg = absf(rad_to_deg(e1.angle_to(e2)) - rad_to_deg((observed[0] as Vector3).angle_to(observed[1])))
	_show("n05")


## 5DEGTEST: the gyros torqued (GYROTRIM), or past COARSE_PAST_DEG a
## coarse align, V06N22 first on the first pass (COATRIM).
func _trim_or_coarse() -> void:
	var big := deg_to_rad(COARSE_PAST_DEG)
	if absf(torque.x) <= big and absf(torque.y) <= big and absf(torque.z) <= big:
		lgc.imu.torque(torque)
		_surface_display()
		return
	coarse_target = Imu.rotation(torque) * Imu.gimbal_basis(lgc.icdu())
	if initial:
		_show("n22")
	else:
		_coarse()


## CORSIT: the coarse align to the new orientation's gimbal angles.
func _coarse() -> void:
	lgc.imu.coarse_align(coarse_target, Basis(lgc._true_att()))
	_show("coarse")


## SURFDISP: REFSMMAT is XSMD, the platform's orientation known. After
## the first pass the technique's; after the technique's the attitude
## stored (technique 0 leaves it), and the check.
func _surface_display() -> void:
	lgc.imu.refsmmat = orientation
	lgc.imu.aligned = true
	lgc.reference_changed()
	if technique != 0 and initial:
		_realign()
		return
	if technique != 0:
		_store_attitude()
	_check()


func _check() -> void:
	_show("check")


## REFMF: the body's Y and Z axes, Moon-fixed, as the LGC reads them from
## REFSMMAT and the CDUs.
func _store_attitude() -> void:
	var sm_to_mf := Bodies.moon_fixed(lgc._now()).transposed() * lgc.imu.refsmmat.transposed()
	var g := Imu.gimbal_basis(lgc.icdu())
	ynb_mf = (sm_to_mf * (g * Vector3(0, 1, 0))).normalized()
	znb_mf = (sm_to_mf * (g * Vector3(0, 0, 1))).normalized()
	attitude_stored = true


## A Moon-fixed direction [param v] in the reference frame now (MFREF).
func _mf_to_ref(v: Vector3) -> Vector3:
	return (Bodies.moon_fixed(lgc._now()) * v).normalized()


## RLS: the LM's position, Moon-fixed, as the LGC holds it.
func _rls_mf() -> Vector3:
	var l := lgc as Lgc
	if l.nav_landed_mf != Vector3.ZERO:
		return l.nav_landed_mf
	return Bodies.moon_fixed(lgc._now()).transposed() * lgc.current_traj().pos()


## Option 4 (TDISP, P57C and P57D): XSMD with X up through the LM at
## TALIGN (0: now; a later time is P12's TIG too) and Z along the CSM's
## orbit's normal crossed with it, the CSM's state vector as the LGC holds
## it (LSORIENT). False without the CSM's state vector.
func _landing_site_orientation() -> bool:
	var l := lgc as Lgc
	if l.csm_nav == null:
		return false
	var now := lgc._now()
	if talign <= 0.0:
		talign = now
	elif talign > now:
		lgc.tig_load = talign
	var c := l.csm_nav
	orientation = Imu.landing_site(Bodies.moon_fixed(talign) * _rls_mf(), c.pos().cross(c.vel()))
	return true


# --- GVDETER --------------------------------------------------------------------

## GVDETER: REFSMMAT's flag cleared, the coarse align to the first
## orientation.
func _gravity() -> void:
	lgc.imu.aligned = false
	lgc.imu.coarse_align(Imu.gimbal_basis(GRAVITY_GIMBALS_DEG), Basis(lgc._true_att()))
	_g_phase = "coarse1"
	_show("gravity")


func _gravity_step() -> void:
	match _g_phase:
		"coarse1", "coarse2":
			if lgc.imu.operating():
				_g_phase = "read1" if _g_phase == "coarse1" else "read2"
				_g_until = lgc._now() + GRAVITY_READS * GRAVITY_READ_S
		"read1", "read2":
			if lgc._now() < _g_until - 1e-6:
				return
			var sm := _specific_force_sm()
			var nb := Imu.gimbal_basis(lgc.icdu()).transposed() * sm
			if _g_phase == "read1":
				_g_first = nb
				# The second orientation: the first turned 180 deg about
				# gravity.
				var turn := Basis(sm, PI)
				lgc.imu.coarse_align(turn * Imu.gimbal_basis(lgc.icdu()), Basis(lgc._true_att()))
				_g_phase = "coarse2"
				return
			gravity = (_g_first + nb).normalized()
			n04_deg = rad_to_deg(acos(clampf(gravity.dot(gsav), -1.0, 1.0)))
			_g_phase = ""
			_show("n04")


## What the PIPAs read on the surface, stable member axes: the ground's
## push against the Moon's pull, up the plumb line, through its field.
func _specific_force_sm() -> Vector3:
	return lgc.imu.platform * plumb_up(lgc.truth_traj())


## The plumb line's up at [param tr]'s position on the Moon (ECI): the
## central pull and GRAIL's field, reversed.
static func plumb_up(tr: Trajectory) -> Vector3:
	var r := tr.pos()
	var mf := Bodies.moon_fixed(tr.t)
	var p := mf.transposed() * r
	var a := MoonGravity.accel_fixed(p.x, p.y, p.z)
	var g := -r * (Bodies.MU_MOON / pow(r.length(), 3.0)) + mf * Vector3(a[0], a[1], a[2])
	return -g.normalized()


# --- R59 and the surface marks ----------------------------------------------------

func _detent() -> int:
	@warning_ignore("integer_division")
	return aotcode / 100


func _star() -> int:
	return aotcode % 100


func _code_ok(value: float) -> bool:
	var c := int(value)
	@warning_ignore("integer_division")
	return c / 100 <= 7 and (c % 100 == 0 or Stars.has(c % 100))


## R59: the star to sight, V01N70, if REFSMMAT is known to find it with;
## else straight to the marks (R59OUT).
func _r59() -> void:
	if not lgc.imu.aligned:
		_show("n71")
		return
	_show("n70")


## R59A: the detents in turn, 1 to 6, for the first whose field holds the
## star as the LGC knows the platform: V06N79 its cursor and spiral, or
## alarm 00404. A code that isn't a catalog star goes straight to the
## marks.
func _acquire() -> void:
	if not Stars.has(_star()):
		_show("n71")
		return
	var s := Imu.gimbal_basis(lgc.icdu()).transposed() * (lgc.imu.refsmmat * Stars.direction(_star()))
	for d in range(1, 7):
		var cs := r59_cursor_spiral(s, Aot.azimuth(d))
		if cs.x < 0.0:
			continue
		poscode = d
		cursor = cs.x
		spiral = cs.y
		_show("n79_acquire")
		return
	lgc._alarm(404)   # the star in no detent's field
	_show("no_detent")


## R59's cursor and spiral angles (deg) for a star at [param s] (body
## axes) through the detent at azimuth [param az_deg]: THET, the star's
## bearing about the optic axis from the LM's X axis, plus the azimuth,
## and that plus twelve times its angle off the axis; (0, 0) within
## ON_AXIS_DEG of it; (-1, -1) outside the field.
static func r59_cursor_spiral(s: Vector3, az_deg: float) -> Vector2:
	var oa := Aot.optic_axis(az_deg)
	# Its double precision ARCCOS as angle_to(), which keeps a small angle's
	# digits in single precision.
	var off := rad_to_deg(s.angle_to(oa))
	if off >= FIELD_HALF_DEG:
		return Vector2(-1.0, -1.0)
	if off < ON_AXIS_DEG:
		return Vector2.ZERO
	var a := oa.cross(Vector3(1, 0, 0)).normalized()
	var b := oa.cross(a).normalized()
	var c := oa.cross(s).normalized()
	var thet := rad_to_deg(c.angle_to(a))
	if c.dot(b) < 0.0:
		thet = 360.0 - thet
	var yrot := fposmod(az_deg + thet, 360.0)
	return Vector2(yrot, fposmod(yrot + off / Aot.SPIRAL_RATIO, 360.0))


## SURFSTAR: the star through detent [param d] at the counter's
## [param cursor_deg] and [param spiral_deg] readings, body axes: SEP =
## ((spiral - cursor) mod 360) / 12 off the optic axis, in the Y-line's
## plane turned by the cursor; both zero, on the axis.
static func surfstar(d: int, cursor_deg: float, spiral_deg: float) -> Vector3:
	var p := Aot.planes(Aot.azimuth(d))
	var oa: Vector3 = p[0]
	if cursor_deg == 0.0 and spiral_deg == 0.0:
		return oa
	var c := deg_to_rad(cursor_deg)
	var yp: Vector3 = (p[1] as Vector3) * cos(c) - (p[2] as Vector3) * sin(c)
	var toward := yp.cross(oa).normalized()
	var sep := deg_to_rad(fposmod(spiral_deg - cursor_deg, 360.0) * Aot.SPIRAL_RATIO)
	return (oa * cos(sep) + toward * sin(sep)).normalized()


## MARK X or MARK Y (either, on the surface) in the marks or at their
## N79: the CDU angles for a mark waiting for its readings. REJECT drops
## the latest mark but the only one (alarm 00115).
func _read_marks() -> void:
	var x := bool(Bus.get_value("ctl.lm.aot.mark_x", false))
	var y := bool(Bus.get_value("ctl.lm.aot.mark_y", false))
	var rej := bool(Bus.get_value("ctl.lm.aot.reject", false))
	var marking := lgc.program == 57 and lgc.step_name in ["marks", "n79"]
	if marking and ((x and not _x_was) or (y and not _y_was)):
		pending = {"cdu": lgc.icdu()}
		_show("n79")
	if marking and rej and not _reject_was:
		if marks.is_empty():
			lgc._alarm(115)   # no mark to reject
		elif lgc.step_name == "n79" and pending != null:
			pending = null
		else:
			marks.pop_back()
	_x_was = x
	_y_was = y
	_reject_was = rej


## SURFAGAN: the waiting mark takes N79's readings.
func _complete_mark() -> void:
	if pending == null:
		return
	var p: Dictionary = pending
	marks.append({"cdu": p["cdu"], "cursor": cursor, "spiral": spiral})
	pending = null


## PRO at the marks (MARKCHEX, AVESTAR): each mark's star through its own
## CDU angles, averaged (alarm 00111 without one); then R59RET: on to the
## second star, or SURFLINE.
func _marks_done() -> void:
	if marks.is_empty():
		lgc._alarm(111)   # no mark to process
		_show("marks")
		return
	var sum := Vector3.ZERO
	for m: Dictionary in marks:
		sum += Imu.gimbal_basis(m["cdu"]) * surfstar(_detent(), float(m["cursor"]), float(m["spiral"]))
	observed[star_i] = sum.normalized()
	refs[star_i] = Stars.direction(_star())
	stars[star_i] = _star()
	marks = []
	if technique == 2 and star_i == 0:
		star_i = 1
		_r59()
		return
	_surfline()


## Technique 2's landing site: along gravity as the aligned platform
## places it, at the RLS's radius.
func _site_from_gravity() -> void:
	var up := lgc.imu.refsmmat.transposed() * (Imu.gimbal_basis(lgc.icdu()) * gsav)
	site_mf = Bodies.moon_fixed(lgc._now()).transposed() * up.normalized() * _rls_mf().length()


# --- checkpoint -----------------------------------------------------------------

func snapshot() -> Dictionary:
	var ms := []
	for m: Dictionary in marks:
		var c: Vector3 = m["cdu"]
		ms.append({"cdu": [c.x, c.y, c.z], "cursor": m["cursor"], "spiral": m["spiral"]})
	var pd: Variant = null
	if pending != null:
		var pc: Vector3 = pending["cdu"]
		pd = [pc.x, pc.y, pc.z]
	return {
		"option": option, "technique": technique, "talign": talign, "orientation": Imu.rows_of(orientation),
		"initial": initial, "gsav": _a(gsav), "gravity": _a(gravity), "n04_deg": n04_deg,
		"attitude_stored": attitude_stored, "ynb_mf": _a(ynb_mf), "znb_mf": _a(znb_mf),
		"aotcode": aotcode, "star_i": star_i, "poscode": poscode, "cursor": cursor, "spiral": spiral,
		"marks": ms, "pending": pd, "refs": [_a(refs[0]), _a(refs[1])], "observed": [_a(observed[0]), _a(observed[1])],
		"stars": stars.duplicate(), "sad_deg": sad_deg, "torque": _a(torque), "coarse_target": Imu.rows_of(coarse_target),
		"site_mf": _a(site_mf), "g_phase": _g_phase, "g_until": _g_until, "g_first": _a(_g_first),
		"x_was": _x_was, "y_was": _y_was, "reject_was": _reject_was,
	}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	option = int(d["option"])
	technique = int(d["technique"])
	talign = float(d["talign"])
	orientation = Imu.from_rows(d["orientation"])
	initial = bool(d["initial"])
	gsav = _v(d["gsav"])
	gravity = _v(d["gravity"])
	n04_deg = float(d["n04_deg"])
	attitude_stored = bool(d["attitude_stored"])
	ynb_mf = _v(d["ynb_mf"])
	znb_mf = _v(d["znb_mf"])
	aotcode = int(d["aotcode"])
	star_i = int(d["star_i"])
	poscode = int(d["poscode"])
	cursor = float(d["cursor"])
	spiral = float(d["spiral"])
	marks = []
	for m: Dictionary in d["marks"]:
		marks.append({"cdu": _v(m["cdu"]), "cursor": float(m["cursor"]), "spiral": float(m["spiral"])})
	pending = null if d["pending"] == null else {"cdu": _v(d["pending"])}
	refs = [_v(d["refs"][0]), _v(d["refs"][1])]
	observed = [_v(d["observed"][0]), _v(d["observed"][1])]
	stars = [int(d["stars"][0]), int(d["stars"][1])]
	sad_deg = float(d["sad_deg"])
	torque = _v(d["torque"])
	coarse_target = Imu.from_rows(d["coarse_target"])
	site_mf = _v(d["site_mf"])
	_g_phase = str(d["g_phase"])
	_g_until = float(d["g_until"])
	_g_first = _v(d["g_first"])
	_x_was = bool(d["x_was"])
	_y_was = bool(d["y_was"])
	_reject_was = bool(d["reject_was"])


## P57's display at a restore.
func show_step() -> void:
	if lgc.step_name != "":
		_show(lgc.step_name)


static func _a(v: Vector3) -> Array:
	return [v.x, v.y, v.z]


static func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])

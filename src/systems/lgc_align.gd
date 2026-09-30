## Luminary's P52, IMU realign, for the LGC (slice 11a): the platform
## aligned to the stars through the alignment optical telescope
## (src/systems/aot.gd), on the displays of Luminary 099's P52, its fine
## align R51, R52 to R56, R60 and AOTMARK [published: Luminary 099, log
## sections P51-P53, AOTMARK and R60,R62]:
##
##   V04N06   the option: 1 preferred (P30's burn attitude), 2 nominal (X
##            up along the LM's radius, Y along V x R, Z forward), 3
##            REFSMMAT, 4 landing site (X up through the site, Z downrange
##            in the CSM's orbit); 1 offered after a P30, 2 otherwise. PRO
##   V06N34   (2 and 4) the orientation's time: 0 for now, the landing's
##            for 4. PRO; for 4 V06N89 the site (latitude, longitude/2,
##            altitude) and PRO
##   V06N22   (1, 2, 4) the gimbal angles the new orientation puts the LM
##            at, alarm 00401 with it if the middle gimbal's would be past
##            60 deg (CALCGA: a warning, the crew maneuvers or goes on);
##            PRO for V50N25 00013, and PRO again: the IMU coarse aligns
##            unless each angle is within 1 deg of its CDU's, and REFSMMAT
##            is the new orientation, the rest left to the fine align
##            [simplified: V32's coarse align by gyro torquing isn't
##            modelled]
##   V50N25 00015  PRO: the LGC picks two stars (R56: within 50 deg of the
##            front detent's line of sight as the LGC reads the attitude,
##            60 deg clear of the Sun and 5 deg of the Earth's and the
##            Moon's limbs, more than 50 deg apart, the widest such pair,
##            the one nearer the line of sight first), or alarm 00405 and
##            V05N09 (PRO to choose them by hand, V32 to look again);
##            ENTER to choose them by hand
##   For each star:
##   V01N70   R1 the detent and the star, 002SS (the front detent, the star
##            R56 chose; V21 loads others, ENTER shows them again); PRO:
##            the attitude that turns that detent's line of sight onto the
##            star, as the LGC knows the platform
##   V50N18   please perform auto maneuver: PRO, and the DAP turns the LM
##            there in AUTO (V06N18) and V50N18 comes back; ENTER to mark
##   V01N71   the detent and the star to mark (V21 changes them); PRO
##   V54N71   mark X or Y: the crew turns the LM on the ACA until the star
##            crosses the reticle's Y-line and presses MARK Y, and the
##            X-line and MARK X, in either order (V53 asks for the pair's
##            Y mark, V52 its X). Each mark takes the CDU angles. Up to
##            MAX_PAIRS pairs (alarm 00107 past them); a second mark on one
##            line in a pair is alarm 00114. REJECT drops the last mark,
##            and at once again the rest of its pair (alarm 00115 with
##            none). PRO: each pair's two planes, each turned to the stable
##            member through its own mark's angles, meet along the star,
##            and the pairs are averaged; a pair left unfinished is left
##            out (alarm 00111 without a whole one). ENTER goes back to
##            V01N71 and the marks are dropped
##   V06N05   the star angle difference; PRO (V32 skips the torquing)
##   V06N93   the gyro torquing angles; PRO torques the platform onto
##            REFSMMAT
##   V50N25 00014  PRO marks another pair as a check; ENTER ends P52
## P52 needs the IMU operating (alarm 00210) and its orientation known
## (alarm 00220), and a gimbal lock that cages the IMU ends it (00220).
## The AOT's detent in N70 and N71 must be the one its knob is at: the LGC
## can't see the knob. [simplified: the COAS's codes, 0 and 7, aren't
## taken; P52 goes back to P00 at its end, not to P20]
class_name LgcAlign
extends RefCounted

## R56's reach from the front detent's line of sight, deg, and the pair's
## least separation, deg [published: Luminary 099, PICAPAR]; the Sun's
## exclusion, and the margin past the Earth's and the Moon's limbs, deg
## [published: ibid., LOCSAM].
const R56_FIELD_DEG := 50.0
const R56_PAIR_MIN_DEG := 50.0
const SUN_CLEAR_DEG := 60.0
const LIMB_CLEAR_DEG := 5.0
## The mark pairs a star takes [published: AOTMARK].
const MAX_PAIRS := 5
## The coarse align only drives the gimbals when one is off its new angle
## by more than this, deg [published: CAL53A]; the new orientation's middle
## gimbal angle past this is alarm 00401, deg [published: CALCGA].
const FINE_ONLY_DEG := 1.0
const N22_LOCK_DEG := 60.0
## The detent R52 offers: the front.
const FRONT := 2
## The maneuver to a star is done inside this of the attitude, deg, with
## the rates under this, deg/s [estimated].
const ON_STAR_DEG := 0.3
const ON_STAR_RATE_DEG_S := 0.05

var lgc: AgcCore
## The option (N06), the orientation's time (N34, GET s; 0 for now) and
## the orientation it gives, XSMD (reference to stable member).
var option: int = 2
var talign: float = 0.0
var orientation: Basis = Basis.IDENTITY
## The two stars' N70/N71 codes, detent * 100 + star (their digits the
## octal ones), the star being marked (0 or 1), and R56's pick.
var codes: Array = [0, 0]
var star_i: int = 0
var picked: Array = [0, 0]
## The marks on the star being marked: pairs, each {"x": the X mark's CDU
## angles (deg) or null, "y": the Y mark's, "last": "x" or "y"}; and a
## REJECT since the last mark (a second drops the pair's rest).
var pairs: Array = []
var rejected: bool = false
## The stars as marked (stable member axes), the star angle difference
## (deg), the torque that takes the platform onto REFSMMAT (rad, stable
## member axes, as Imu.torque() takes it: N93 shows its reverse, the
## platform's turn) and N25's code.
var measured: Array = [Vector3.ZERO, Vector3.ZERO]
var sad_deg: float = 0.0
var torque: Vector3 = Vector3.ZERO
var checklist: int = 15
var _x_was: bool = false
var _y_was: bool = false
var _reject_was: bool = false


func _init(computer: AgcCore) -> void:
	lgc = computer


## P52 from V37: the option, if the IMU runs and its orientation is known.
func start() -> void:
	pairs = []
	rejected = false
	star_i = 0
	if not lgc.imu.operating():
		lgc._alarm(210)   # IMU not operating
		lgc.change_program(0)
		return
	if not lgc.imu.aligned:
		lgc._alarm(220)   # the orientation unknown
		lgc.change_program(0)
		return
	option = 1 if lgc.preferred_valid else 2
	_show("option")


func proceed() -> void:
	match lgc.step_name:
		"option":
			match option:
				1:
					if not lgc.preferred_valid:
						lgc._alarm(215)   # no preferred orientation
						return
					orientation = lgc.preferred_refsmmat
					_show("n22")
				2, 4:
					talign = _landing_time() if option == 4 else 0.0
					_show("n34")
				_:
					_acquire()
		"n34":
			if not _new_orientation():
				lgc.dsky.set_lamp("opr_err", true)
				return
			_show("n89" if option == 4 else "n22")
		"n89":
			_show("n22")
		"n22":
			checklist = 13
			_show("coarse_type")
		"coarse_type":
			_coarse_align()
		"check":
			_acquire()
		"acquire":
			if _pick_stars():
				codes = [FRONT * 100 + int(picked[0]), FRONT * 100 + int(picked[1])]
				star_i = 0
				_show("n70")
			else:
				lgc._alarm(405)   # two stars not available
				_show("no_stars")
		"no_stars":
			_to_star(0)
		"n70":
			if not _aim():
				lgc.dsky.set_lamp("opr_err", true)
				return
			_show("v50n18")
		"v50n18":
			lgc._plan_via()
			lgc.auto_active = true
			_show("maneuver")
		"n71":
			var d := detent()
			if d < 1 or d > 6 or not Stars.has(star()):
				_show("n71")   # not a detent (or a star) it can mark with
				return
			pairs = []
			rejected = false
			_show("marks")
		"marks":
			_marks_done()
		"n05":
			torque = _torquing_angles()
			_show("n93")
		"n93":
			lgc.imu.torque(torque)
			lgc.imu.aligned = true
			lgc.reference_changed()
			_check()


## ENTER at a flashing display (the DSKY's V50, V01 and V5x with their
## nouns): V50N25 00015 chooses the stars by hand, 00014 ends P52; V01N70
## and V01N71 show their codes again; V50N18 after the maneuver goes on to
## the marks; V5xN71 goes back to V01N71.
func enter(v: int, n: int) -> bool:
	var took := false
	match lgc.step_name:
		"acquire":
			took = v == 50 and n == 25
			if took:
				_to_star(0)
		"check":
			took = v == 50 and n == 25
			if took:
				lgc.change_program(0)
		"n70":
			took = v == 1 and n == 70
			if took:
				_show("n70")
		"v50n18":
			took = v == 50 and n == 18
			if took:
				if lgc.auto_active:
					# Stopped short: the DAP holds the LM where it is.
					lgc.auto_active = false
					lgc.hold_q = lgc._att()
				_show("n71")
		"n71":
			took = v == 1 and n == 71
			if took:
				_show("n71")
		"marks":
			took = n == 71 and v in [52, 53, 54]
			if took:
				pairs = []
				_show("n71")
	return took


## V32: at V05N09 (no stars) look again; at N05 leave the platform
## untorqued and go on to the check.
func recycle() -> bool:
	match lgc.step_name:
		"no_stars":
			_acquire()
			return true
		"n05":
			_check()
			return true
	return false


## Each step: in P52 the end of a coarse align or of a maneuver to a star,
## and the marks; a gimbal lock that cages the IMU ends P52.
func step() -> void:
	if lgc.program == 52 and lgc.imu.mode == "caged":
		lgc._alarm(220)
		lgc.change_program(0)
	var s := lgc.step_name if lgc.program == 52 else ""
	match s:
		"coarse":
			if lgc.imu.operating():
				lgc.imu.aligned = true
				lgc.reference_changed()
				_acquire()
		"maneuver":
			if lgc._att_error(lgc.auto_target) < deg_to_rad(ON_STAR_DEG) \
					and lgc._omega().length() < deg_to_rad(ON_STAR_RATE_DEG_S):
				# There: the DAP holds it, and the crew's ACA moves it on.
				lgc.hold_q = lgc.auto_target
				lgc.auto_active = false
				_show("v50n18")
	_read_marks()


func detent() -> int:
	@warning_ignore("integer_division")
	return int(codes[star_i]) / 100


func star() -> int:
	return int(codes[star_i]) % 100


## N70 or N71's code loaded (V21): the detent and star for the star being
## marked; false (OPR ERR) for one that isn't a code.
func load_code(value: float) -> bool:
	var c := int(value)
	@warning_ignore("integer_division")
	var d := c / 100
	if d > 7 or (c % 100 != 0 and not Stars.has(c % 100)):
		return false
	codes[star_i] = c
	return true


func noun_values(n: int) -> Variant:
	var v: Variant = null
	match n:
		5:
			v = [sad_deg, 0.0, 0.0]
		6:
			v = [1.0, float(option), 0.0]
		22:
			var g := Imu.gimbal_angles(orientation * Basis(lgc._att()))
			v = [g.x, g.y, g.z]
		25:
			v = [float(checklist), 0.0, 0.0]
		34:
			v = [talign, talign, talign]
		70, 71:
			v = [float(codes[star_i]), 0.0, 0.0]
		89:
			var s := Bodies.fixed_to_selenographic(lgc.landing_site)
			v = [s.x, s.y / 2.0, s.z - Bodies.R_MOON]
		93:
			# The gyros' torquing, the platform's own turn back onto
			# REFSMMAT, as Luminary shows it: Imu.torque() takes the
			# reverse, its reference's.
			var t := -torque * (180.0 / PI)
			v = [t.x, t.y, t.z]
	return v


func noun_load(n: int, idx: int, value: float) -> bool:
	var ok := false
	match n:
		6:
			ok = idx == 1 and lgc.step_name == "option" and int(value) in [1, 2, 3, 4]
			if ok:
				option = int(value)
		34:
			ok = lgc.step_name == "n34"
			if ok:
				var parts := [floorf(talign / 3600.0) * 3600.0, floorf(fmod(talign, 3600.0) / 60.0) * 60.0, fmod(talign, 60.0)]
				parts[idx] = value
				talign = parts[0] + parts[1] + parts[2]
		70, 71:
			ok = idx == 0 and lgc.step_name in ["n70", "n71"] and load_code(value)
	return ok


# --- the steps ---------------------------------------------------------------

## Step [param s] and its display; [param fresh] for a step just come to
## (a restore shows it again without its alarm).
func _show(s: String, fresh: bool = true) -> void:
	lgc.step_name = s
	match s:
		"option":
			lgc.dsky.show(4, 6, true)
		"n34":
			lgc.dsky.show(6, 34, true)
		"n89":
			lgc.dsky.show(6, 89, true)
		"n22":
			var g := orientation * Basis(lgc._att())
			if fresh and absf(wrapf(Imu.gimbal_angles(g).z, -180.0, 180.0)) > N22_LOCK_DEG:
				lgc._alarm(401)   # the new orientation near gimbal lock here
			lgc.dsky.show(6, 22, true)
		"coarse":
			lgc.dsky.show(16, 20)
		"coarse_type", "acquire", "check":
			lgc.dsky.show(50, 25, true)
		"no_stars":
			lgc.dsky.show(5, 9, true)
		"n70":
			lgc.dsky.show(1, 70, true)
		"v50n18":
			lgc.dsky.show(50, 18, true)
		"maneuver":
			lgc.dsky.show(6, 18)
		"n71":
			lgc.dsky.show(1, 71, true)
		"marks":
			lgc.dsky.show(_mark_verb(), 71, true)
		"n05":
			lgc.dsky.show(6, 5, true)
		"n93":
			lgc.dsky.show(6, 93, true)


func _acquire() -> void:
	checklist = 15
	_show("acquire")


func _check() -> void:
	checklist = 14
	_show("check")


func _to_star(i: int) -> void:
	star_i = i
	# R52 offers the front detent with R56's star.
	codes[i] = FRONT * 100 + int(picked[i])
	_show("n70")


## The landing's time for option 4: the one the LGC last aligned to, or
## PDI's with the descent's nominal length.
func _landing_time() -> float:
	var l := lgc as Lgc
	if l.tland > 0.0:
		return l.tland
	return l.pdi_tig + float(SpacecraftData.section("descent_guidance")["descent_s"]) if l.pdi_tig > 0.0 else 0.0


## Option 2's or 4's orientation at N34's time into orientation; false
## without what it needs (the landing site for 4).
func _new_orientation() -> bool:
	var l := lgc as Lgc
	var t := talign if talign > 0.0 else lgc._now()
	var tr := lgc.predict(t)
	if option == 2:
		orientation = Imu.lm_nominal(tr.pos(), tr.vel())
		return true
	if l.landing_site == Vector3.ZERO or tr.primary != "moon":
		return false
	# The CSM's orbit gives downrange, its state vector as the LGC holds it.
	var c := l.csm_nav.clone() if l.csm_nav != null else tr
	if c.t < t:
		c.coast_to(t, 60.0)
	orientation = Imu.landing_site(Bodies.moon_fixed(t) * l.landing_site, c.pos().cross(c.vel()))
	l.tland = t
	talign = t
	return true


## CAL53A: the coarse align to the new orientation, unless each gimbal is
## within FINE_ONLY_DEG of its angle there; REFSMMAT is the new
## orientation either way.
func _coarse_align() -> void:
	var g := orientation * Basis(lgc._att())
	var want := Imu.gimbal_angles(g)
	var now := lgc.icdu()
	var far := false
	for i in 3:
		far = far or absf(wrapf(want[i] - now[i], -180.0, 180.0)) > FINE_ONLY_DEG
	lgc.imu.refsmmat = orientation
	lgc.preferred_valid = false
	if far:
		lgc.imu.coarse_align(g, Basis(lgc._true_att()))
		_show("coarse")
		return
	lgc.imu.aligned = true
	lgc.reference_changed()
	_acquire()


## R56: two stars within R56_FIELD_DEG of the front detent's line of sight
## (as the LGC reads the attitude), clear of the Sun, the Earth and the
## Moon, more than R56_PAIR_MIN_DEG apart: the widest pair, the one nearer
## the line of sight first. False without one.
func _pick_stars() -> bool:
	var sax := Basis(lgc._att()) * Aot.optic_axis(Aot.azimuth(FRONT))
	var usable := []
	for c in clear_stars(lgc.current_traj()):
		if rad_to_deg(Stars.direction(c).angle_to(sax)) <= R56_FIELD_DEG:
			usable.append(c)
	var best := []
	var best_sep := 0.0
	for i in usable.size():
		for j in range(i + 1, usable.size()):
			var sep := rad_to_deg(Stars.direction(usable[i]).angle_to(Stars.direction(usable[j])))
			if sep > R56_PAIR_MIN_DEG and sep > best_sep:
				best_sep = sep
				best = [usable[i], usable[j]]
	if best.is_empty():
		return false
	if Stars.direction(best[1]).angle_to(sax) < Stars.direction(best[0]).angle_to(sax):
		best = [best[1], best[0]]
	picked = best
	return true


## The navigation stars clear of the Sun, the Earth and the Moon from the
## LM at [param tr], by R56's limits.
static func clear_stars(tr: Trajectory) -> Array:
	var hidden := _hiding_bodies(tr)
	var out := []
	for c in Stars.codes():
		var s := Stars.direction(c)
		var clear := true
		for b in hidden:
			if rad_to_deg(s.angle_to(b[0])) < float(b[1]):
				clear = false
		if clear:
			out.append(c)
	return out


## The Sun, the Earth and the Moon from the LM at [param tr]: each
## direction (ECI) and the angle (deg) within which it hides a star.
static func _hiding_bodies(tr: Trajectory) -> Array:
	var m := Bodies.moon_position(tr.t)
	var moon := Vector3(m[0], m[1], m[2])
	var geo := tr.pos() if tr.primary == "earth" else tr.pos() + moon
	var out := [[Bodies.sun_direction(tr.t), SUN_CLEAR_DEG]]
	for b in [[-geo, Bodies.R_EARTH], [moon - geo, Bodies.R_MOON]]:
		var d: Vector3 = b[0]
		out.append([d.normalized(), rad_to_deg(asin(clampf(float(b[1]) / d.length(), 0.0, 1.0))) + LIMB_CLEAR_DEG])
	return out


## R52: the attitude that turns N70's detent's line of sight onto its star
## as the LGC knows the platform, the least turn from where the LM is
## (VECPOINT). False for a detent or star it can't aim.
func _aim() -> bool:
	var d := detent()
	if d < 1 or d > 6 or not Stars.has(star()):
		return false
	var now := lgc._att()
	var axis := Basis(now) * Aot.optic_axis(Aot.azimuth(d))
	var target := (Imu.arc(axis, Stars.direction(star())) * now).normalized()
	lgc.auto_target = target
	lgc.desired_q = target
	return true


## The mark verb: V53 the pair wants its Y mark, V52 its X, V54 either.
func _mark_verb() -> int:
	if pairs.is_empty():
		return 54
	var p: Dictionary = pairs[-1]
	if p["x"] != null and p["y"] == null:
		return 53
	if p["y"] != null and p["x"] == null:
		return 52
	return 54


## MARK X, MARK Y and REJECT (the CCRD's, rising edges), in "marks".
func _read_marks() -> void:
	var x := bool(Bus.get_value("ctl.lm.aot.mark_x", false))
	var y := bool(Bus.get_value("ctl.lm.aot.mark_y", false))
	var rej := bool(Bus.get_value("ctl.lm.aot.reject", false))
	var marking := lgc.program == 52 and lgc.step_name == "marks"
	if marking and x and not _x_was:
		_mark("x")
	if marking and y and not _y_was:
		_mark("y")
	if marking and rej and not _reject_was:
		_reject()
	_x_was = x
	_y_was = y
	_reject_was = rej


## A mark on [param axis] ("x" or "y"): the CDU angles now, into the pair
## being made, or a new one once that is whole.
func _mark(axis: String) -> void:
	if pairs.is_empty() or (pairs[-1]["x"] != null and pairs[-1]["y"] != null):
		if pairs.size() >= MAX_PAIRS:
			lgc._alarm(107)   # five pairs already
			return
		pairs.append({"x": null, "y": null, "last": ""})
	var p: Dictionary = pairs[-1]
	if p[axis] != null:
		lgc._alarm(114)   # not the mark wanted
		return
	p[axis] = lgc.icdu()
	p["last"] = axis
	rejected = false
	_show("marks")


## REJECT: the pair being made loses its last mark, or at a second REJECT
## its other; an earlier, whole pair stays.
func _reject() -> void:
	var p: Dictionary = pairs[-1] if not pairs.is_empty() else {}
	if p.is_empty() or (p["x"] == null and p["y"] == null):
		lgc._alarm(115)   # no mark to reject
		return
	if rejected:
		p["x"] = null
		p["y"] = null
	else:
		p[p["last"]] = null
		p["last"] = "x" if p["x"] != null else "y"
		rejected = true
	_show("marks")


## PRO at the marks: the star from the whole pairs (MARKCHEX, AVESTAR), and
## on to the next star, or to N05.
func _marks_done() -> void:
	if not pairs.is_empty() and (pairs[-1]["x"] == null or pairs[-1]["y"] == null):
		pairs.pop_back()
	if pairs.is_empty():
		lgc._alarm(111)   # no pair to process
		rejected = false
		_show("marks")
		return
	var p := Aot.planes(Aot.azimuth(detent()))
	var sum := Vector3.ZERO
	for pr: Dictionary in pairs:
		var yp := Imu.gimbal_basis(pr["y"]) * (p[1] as Vector3)
		var xp := Imu.gimbal_basis(pr["x"]) * (p[2] as Vector3)
		sum += xp.cross(yp).normalized()
	measured[star_i] = sum.normalized()
	pairs = []
	if star_i == 0:
		_to_star(1)
		return
	_star_angle_difference()
	_show("n05")


func _star_angle_difference() -> void:
	var s1 := Stars.direction(int(codes[0]) % 100)
	var s2 := Stars.direction(int(codes[1]) % 100)
	var m1: Vector3 = measured[0]
	var m2: Vector3 = measured[1]
	sad_deg = absf(rad_to_deg(m1.angle_to(m2)) - rad_to_deg(s1.angle_to(s2)))


## AXISGEN: the rotation (rad, stable member axes) that takes the marked
## stars where REFSMMAT puts them.
func _torquing_angles() -> Vector3:
	var e1 := lgc.imu.refsmmat * Stars.direction(int(codes[0]) % 100)
	var e2 := lgc.imu.refsmmat * Stars.direction(int(codes[1]) % 100)
	return Imu.rotation_vector(Imu.triad(e1, e2) * Imu.triad(measured[0], measured[1]).transposed())


# --- checkpoint -----------------------------------------------------------------

func snapshot() -> Dictionary:
	var ps := []
	for pr: Dictionary in pairs:
		ps.append({"x": _arr(pr["x"]), "y": _arr(pr["y"]), "last": pr["last"]})
	var m0: Vector3 = measured[0]
	var m1: Vector3 = measured[1]
	return {
		"option": option, "talign": talign, "orientation": Imu.rows_of(orientation), "codes": codes.duplicate(),
		"star_i": star_i, "picked": picked.duplicate(), "pairs": ps, "rejected": rejected,
		"measured": [[m0.x, m0.y, m0.z], [m1.x, m1.y, m1.z]], "sad_deg": sad_deg,
		"torque": [torque.x, torque.y, torque.z], "checklist": checklist,
		"x_was": _x_was, "y_was": _y_was, "reject_was": _reject_was,
	}


func restore(d: Dictionary) -> void:
	if d.is_empty():
		return
	option = int(d["option"])
	talign = float(d["talign"])
	orientation = Imu.from_rows(d["orientation"])
	codes = [int(d["codes"][0]), int(d["codes"][1])]
	star_i = int(d["star_i"])
	picked = [int(d["picked"][0]), int(d["picked"][1])]
	pairs = []
	for pr: Dictionary in d["pairs"]:
		pairs.append({"x": _vec(pr["x"]), "y": _vec(pr["y"]), "last": str(pr["last"])})
	rejected = bool(d["rejected"])
	measured = [_vec(d["measured"][0]), _vec(d["measured"][1])]
	sad_deg = float(d["sad_deg"])
	var t: Array = d["torque"]
	torque = Vector3(t[0], t[1], t[2])
	checklist = int(d["checklist"])
	_x_was = bool(d["x_was"])
	_y_was = bool(d["y_was"])
	_reject_was = bool(d["reject_was"])


## P52's display at a restore.
func show_step() -> void:
	if lgc.step_name != "":
		_show(lgc.step_name, false)


static func _arr(v: Variant) -> Variant:
	if v == null:
		return null
	var w: Vector3 = v
	return [w.x, w.y, w.z]


static func _vec(a: Variant) -> Variant:
	if a == null:
		return null
	return Vector3(a[0], a[1], a[2])

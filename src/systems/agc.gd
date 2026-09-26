## Apollo Guidance Computer (Command Module Computer, CMC) with its DSKY:
## the Colossus programs a lunar CSM crew used most, driven through the
## real verb/noun dialogue. The DSKY, P30, the thrusting programs, P47 and
## the digital autopilot are the core's (src/systems/agc_core.gd); the CMC
## adds its engine, its entry programs and its controls.
##
##   P00  CMC idling
##   P30  External ΔV
##   P40  SPS thrusting [simplified: LVLH steering stands in for Colossus
##        cross-product steering, which a long LOI burn needs]
##   P41  RCS thrusting: as P40, but the burn is +X translation on the SM
##        RCS (small corrections the SPS cannot resolve)
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   P61  Entry preparation: V16N64 (g, velocity, altitude)
##   P64  Entry guidance (auto at 0.05 g): bank-angle drag control
##   P67  Entry final phase (lift up)
##   P27  Update: the ground's uplinks (V71), the state vector and a PAD's
##        P30 loads, taken in P00 with the UP TLM CM switch in ACCEPT
##        (ctl.cmc.up_tlm); the DSKY shows P27 while UPLINK ACTY is lit
##   P51  IMU orientation determination, for a platform whose orientation
##        is lost: V50N25 00015 (the crew finds a star in the optics), V51
##        (please mark), V01N71 (the crew loads the star's code), twice;
##        V06N05 star angle difference; PRO sets REFSMMAT to the platform's
##        orientation. A caged IMU is coarse aligned to zero gimbal angles
##        first
##   P52  IMU realign: V04N06 option (1 preferred, 2 nominal, 3 REFSMMAT,
##        4 landing site); for a new orientation V06N22 (its gimbal angles)
##        and a coarse align on PRO; V50N25 00015, PRO picks two stars
##        (alarm 00405 if none will do); for each V01N70 (its code), the
##        optics driven to it in CMC mode, V51 and a mark; V06N05; V06N93
##        gyro torquing angles, PRO torques; V50N25 00014, PRO for a check
##        pair. V32 at N05 or N93 marks again. It needs the platform's
##        orientation known (alarm 00220: P51 first)
##   V41N20  Coarse align: V25N22 flashes for the gimbal angles, and the
##        IMU is driven to them; REFSMMAT no longer holds
## P52 won't coarse align to a new orientation that puts the middle gimbal
## past LOCK_MANEUVER_DEG where the CSM is (alarm 00401): the crew
## maneuvers first, and N22 follows the attitude. A gimbal lock that cages
## the IMU ends P51 and P52 (alarm 00220).
##
## Marks: MARK (ctl.optics.mark) takes the optics' line of sight
## (optics.shaft_deg, optics.trunnion_deg) and the ICDU angles, each to a
## CDU count; MARK REJECT (ctl.optics.mark_reject) drops the last mark.
##
## Navigation: the CMC flies on its own state vector (the core's nav),
## which a start phase sets to the state the ground last tracked. Average-G
## adds the CSM's sensed ΔV in P40, P41, P47 and entry, and while the S-IVB
## burns TLI [simplified: the monitor, P15, isn't modelled]. In coast it
## doesn't: the small forces there (vents, unbalanced jets, a translation
## in P00) move the CSM off the state vector, and the ground's uplinks take
## that out.
##
## The IMU: the CMC's drifts (src/systems/imu.gd), at rates drawn from the
## mission's seed, and a start phase aligns it to that phase's REFSMMAT.
## The FDAI's total attitude is the CSM's attitude relative to the stable
## member, the ICDU angles. P30 works out the preferred orientation for the
## maneuver it stores (X along the thrust, heads up), which P52 aligns to.
##
## Digital autopilot (active when ctl.scs.att_source == 0, CMC):
##   ctl.cmc.mode 0 FREE  RHC commands acceleration, no hold
##                1 HOLD  RHC rate command, attitude hold on release
##                2 AUTO  as HOLD, plus program-commanded maneuvers
## It doesn't fly the S-IVB stack (the IU does) or in the atmosphere.
##
## Reads:  the core's, ctl.cmc.up_tlm, sivb.state, ctl.optics.mark,
##         ctl.optics.mark_reject, optics.shaft_deg, optics.trunnion_deg
## Writes: the core's channels (guid.*, dsky.*), guid.sps_on,
##         guid.bank_auto, guid.bank_cmd_deg, guid.optics.cmd (the CMC
##         drives the optics), guid.optics.cmd_deg (shaft, trunnion),
##         guid.align_marks (P51 and P52's marks taken) and guid.align_star
##         (the star to mark, or just marked, 0 for none yet)
class_name Agc
extends AgcCore

const ENTRY_G_REF := 4.0          ## g, constant-drag reference
const ENTRY_FINAL_V := 3000.0     ## m/s, P67 below this
## P52 takes stars no further than this from the optics' shaft axis, deg,
## clear of the Earth's and the Moon's limbs and of the Sun by these, deg,
## and pairs them this far apart, deg [estimated].
const STAR_TRUNNION_MAX_DEG := 50.0
const STAR_LIMB_CLEAR_DEG := 5.0
const STAR_SUN_CLEAR_DEG := 15.0
const PAIR_MIN_DEG := 30.0
const PAIR_MAX_DEG := 150.0
## P51 and P52's nouns.
const CMC_NOUNS := {
	5: {"name": "STAR ANGLE DIFF", "c": [["SAD", "d2", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	6: {"name": "OPTION CODE", "c": [["CODE", "o", 1.0], ["OPTION", "o", 1.0], ["", "blank", 1.0]]},
	22: {"name": "NEW ICDU ANGLES", "c": [["OG", "d2", 1.0], ["IG", "d2", 1.0], ["MG", "d2", 1.0]]},
	25: {"name": "CHECKLIST", "c": [["CODE", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	70: {"name": "STAR CODE", "c": [["STAR", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	71: {"name": "STAR CODE", "c": [["STAR", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	91: {"name": "OCDU ANGLES", "c": [["SHAFT", "d2", 1.0], ["TRUN", "d3", 1.0], ["", "blank", 1.0]]},
	93: {"name": "TORQUING ANGLES", "c": [["X", "d3", 1.0], ["Y", "d3", 1.0], ["Z", "d3", 1.0]]},
}

var entry_captured: bool = false
## P51 and P52: the option (P52's), the orientation a coarse align goes
## to, the two stars (codes), the marks taken (each star's direction as
## measured, stable member axes), the star angle difference (deg), the
## torquing angles (rad, stable member axes) and the checklist code N25
## shows.
var align_option: int = 3
var align_refsmmat: Basis = Basis.IDENTITY
var align_stars: Array = [0, 0]
var align_marks: Array = []
var align_sad_deg: float = 0.0
var align_torque: Vector3 = Vector3.ZERO
var align_checklist: int = 15
## V41N20: the gimbal angles loaded into N22, and whether the load is for
## it.
var coarse_load: Vector3 = Vector3.ZERO
var _v41: bool = false
## P52 option 4's landing site (Moon-fixed, m) and landing time (GET, s).
var landing_site_mf: Vector3 = Vector3.ZERO
var landing_get: float = 0.0
var _mark_was: bool = false
var _reject_was: bool = false
var _restoring: bool = false


## The programs whose Average-G puts the sensed ΔV into the state vector.
const AVERAGE_G := [40, 41, 47, 61, 64, 67]


func _init() -> void:
	super()
	dsky.nouns = Dsky.NOUNS.merged(CMC_NOUNS, true)


func programs() -> Array:
	return [0, 30, 40, 41, 47, 51, 52, 61, 64, 67]


func thrusting_programs() -> Array:
	return [40, 41]


func engine_thrust(_p: int) -> float:
	return float(SpacecraftData.section("sps")["thrust_n"])


func engine_tau_off(_p: int) -> float:
	return float(SpacecraftData.section("sps")["tau_off_s"])


func engine_running() -> bool:
	return bool(Bus.get_value("sps.on", false))


func publish_engine(on: bool) -> void:
	Bus.set_value("guid.sps_on", on)


func mode() -> int:
	return int(Bus.get_value("ctl.cmc.mode", 1))


func rhc() -> Vector3:
	return Bus.get_value("ctl.rhc", Vector3.ZERO)


func att_source() -> int:
	return int(Bus.get_value("ctl.scs.att_source", 0))


func dap_enabled() -> bool:
	return str(Bus.get_value("dyn.config", "stack")) != "stack" and not bool(Bus.get_value("dyn.in_atmosphere", false))


func authority() -> Vector3:
	var cfg := str(Bus.get_value("dyn.config", "csm"))
	if cfg == "stack":
		return Vector3.ONE
	var c := SpacecraftData.config(cfg)
	var mass := float(Bus.get_value("dyn.mass_kg", 30000.0))
	var inertia := SpacecraftData.inertia(cfg, mass)
	var f := float(SpacecraftData.section("cm_rcs" if cfg == "cm" else "sm_rcs")["jet_thrust_n"])
	var roll := f * float(c["rcs_roll_arm_m"]) * 4.0
	var pitch := f * float(c["rcs_pitch_arm_m"]) * 2.0
	return Vector3(roll / inertia.x, pitch / inertia.y, pitch / inertia.z)


func start_program(p: int) -> void:
	if p in [61, 64, 67]:
		dsky.show(16, 64)
	if _restoring or not p in [51, 52]:
		return
	align_marks = []
	align_stars = [0, 0]
	if p == 52:
		if not imu.aligned:
			_alarm(220)   # the orientation unknown: P51 finds it
			change_program(0)
			return
		align_option = 1 if preferred_valid else 3
		step_name = "option"
		dsky.show(4, 6, true)
		return
	if imu.operating():
		_acquire()
	else:
		# Caged: run the IMU up at zero gimbal angles first.
		imu.coarse_align(Basis.IDENTITY, Basis(_true_att()))
		step_name = "coarse"
		dsky.show(16, 20)


func real_imu() -> bool:
	return true


## The FDAI's total attitude: the CSM's relative to the stable member.
func indicator_attitude(_lvlh: Quaternion) -> Quaternion:
	return imu.gimbals(Basis(_true_att())).get_rotation_quaternion()


## P27 runs from P00, and only with the UP TLM CM switch in ACCEPT.
func accepts_uplink() -> bool:
	return super.accepts_uplink() and program == 0 and bool(Bus.get_value("ctl.cmc.up_tlm", true))


func avg_g() -> bool:
	return program in AVERAGE_G or str(Bus.get_value("sivb.state", "")) == "burning"


func extra_step() -> void:
	_entry_step()
	_align_step()


func proceed() -> void:
	if program == 52:
		_proceed_p52()
	elif program == 51:
		_proceed_p51()
	else:
		super.proceed()
		return
	# The step on the Bus at once, for the checklist, not at the next tick.
	_publish()
	_publish_align()
	_publish_imu()


func verb_noun(v: int, n: int) -> bool:
	if v == 32 and program in [51, 52] and step_name in ["n05", "n93"]:
		# Recycle: mark again.
		align_marks = []
		_acquire()
		_publish()
		_publish_align()
		return true
	if v == 41 and n == 20:
		_v41 = true
		coarse_load = icdu()
		dsky.request_load(25, 22)
		return true
	return super.verb_noun(v, n)


func noun_values(n: int) -> Variant:
	match n:
		5:
			return [align_sad_deg, 0.0, 0.0]
		6:
			return [1.0, float(align_option), 0.0]
		22:
			if _v41:
				return [coarse_load.x, coarse_load.y, coarse_load.z]
			var g := Imu.gimbal_angles(align_refsmmat * Basis(_att()))
			return [g.x, g.y, g.z]
		25:
			return [float(align_checklist), 0.0, 0.0]
		70, 71:
			return [float(align_stars[_star_index()]), 0.0, 0.0]
		91:
			return [float(Bus.get_value("optics.shaft_deg", 0.0)), float(Bus.get_value("optics.trunnion_deg", 0.0)), 0.0]
		93:
			return [rad_to_deg(align_torque.x), rad_to_deg(align_torque.y), rad_to_deg(align_torque.z)]
	return super.noun_values(n)


func noun_load(n: int, idx: int, value: float) -> bool:
	match n:
		6:
			if idx != 1 or program != 52 or step_name != "option" or not int(value) in [1, 2, 3, 4]:
				return false
			align_option = int(value)
			return true
		70, 71:
			if idx != 0 or not program in [51, 52] or not Stars.has(int(value)):
				return false
			align_stars[_star_index()] = int(value)
			_publish_align()
			return true
		22:
			if not _v41:
				return false
			coarse_load[idx] = value
			if idx == 2:
				_v41 = false
				imu.coarse_align(Imu.gimbal_basis(coarse_load), Basis(_true_att()))
				imu.aligned = false
			return true
	return super.noun_load(n, idx, value)


# --- IMU alignment: P51 and P52 ------------------------------------------------------

## The star N70 or N71 is for: the one to mark next, or in P51 the one
## just marked.
func _star_index() -> int:
	var i := align_marks.size() - 1 if step_name == "id" else align_marks.size()
	return clampi(i, 0, 1)


func _acquire() -> void:
	step_name = "acquire"
	align_checklist = 15
	dsky.show(50, 25, true)


func _proceed_p52() -> void:
	match step_name:
		"option":
			if align_option == 3:
				_acquire()
			elif _new_orientation(align_option):
				step_name = "n22"
				dsky.show(6, 22, true)
			else:
				dsky.set_lamp("opr_err", true)
		"n22":
			var g := align_refsmmat * Basis(_att())
			if absf(wrapf(Imu.gimbal_angles(g).z, -180.0, 180.0)) > LOCK_MANEUVER_DEG:
				# The new orientation would put the gimbals in lock here:
				# maneuver first (N22 follows the attitude).
				_alarm(401)
				return
			imu.coarse_align(g, Basis(_true_att()))
			imu.refsmmat = align_refsmmat
			step_name = "coarse"
			dsky.show(16, 20)
		"acquire":
			if _select_stars():
				step_name = "star"
				dsky.show(1, 70, true)
			else:
				_alarm(405)   # two stars not available
		"star":
			step_name = "mark"
			dsky.show(51, -1, true)
		"n05":
			align_torque = _torquing_angles()
			step_name = "n93"
			dsky.show(6, 93, true)
		"n93":
			imu.torque(align_torque)
			imu.aligned = true
			step_name = "check"
			align_checklist = 14
			dsky.show(50, 25, true)
		"check":
			# A check: another pair, whose torquing angles should be near zero.
			align_marks = []
			_acquire()


func _proceed_p51() -> void:
	match step_name:
		"acquire":
			step_name = "mark"
			dsky.show(51, -1, true)
		"id":
			if not Stars.has(int(align_stars[_star_index()])):
				dsky.set_lamp("opr_err", true)
				return
			if align_marks.size() < 2:
				_acquire()
			else:
				_star_angle_difference()
				step_name = "n05"
				dsky.show(6, 5, true)
		"n05":
			# REFSMMAT: the platform's orientation, from the two stars.
			var s1 := Stars.direction(align_stars[0])
			var s2 := Stars.direction(align_stars[1])
			imu.refsmmat = _triad(align_marks[0], align_marks[1]) * _triad(s1, s2).transposed()
			imu.aligned = true
			change_program(0)


## The REFSMMAT for P52's option [param opt] (1, 2 or 4) into
## align_refsmmat; false if there is none.
func _new_orientation(opt: int) -> bool:
	var tr := current_traj()
	match opt:
		1:
			if not preferred_valid:
				return false
			align_refsmmat = preferred_refsmmat
		2:
			align_refsmmat = Imu.nominal(tr.pos(), tr.vel())
		4:
			if tr.primary != "moon" or landing_site_mf == Vector3.ZERO:
				return false
			align_refsmmat = Imu.landing_site(Bodies.moon_fixed(landing_get) * landing_site_mf, tr.pos().cross(tr.vel()))
		_:
			return false
	return true


## Each step: the end of a coarse align, MARK and MARK REJECT, and the
## optics driven to the star in P52 (CMC mode). A gimbal lock that cages
## the IMU ends P51 and P52 (alarm 00220): their marks no longer hold.
func _align_step() -> void:
	if program in [51, 52] and imu.mode == "caged":
		_alarm(220)
		change_program(0)
		return
	if program in [51, 52] and step_name == "coarse" and imu.operating():
		_acquire()
	var mark := bool(Bus.get_value("ctl.optics.mark", false))
	if mark and not _mark_was:
		_on_mark()
	_mark_was = mark
	var rej := bool(Bus.get_value("ctl.optics.mark_reject", false))
	if rej and not _reject_was:
		_on_mark_reject()
	_reject_was = rej
	var drive := program == 52 and step_name in ["star", "mark"]
	Bus.set_value("guid.optics.cmd", drive)
	if drive:
		var a := Optics.angles_for(Basis(_att()).inverse() * Stars.direction(align_stars[_star_index()]))
		Bus.set_value("guid.optics.cmd_deg", Vector3(a.x, a.y, 0.0))
	_publish_align()


## P51 and P52's marks taken and the star they're on, on the Bus.
func _publish_align() -> void:
	var aligning := program in [51, 52]
	Bus.set_value("guid.align_marks", align_marks.size() if aligning else 0)
	Bus.set_value("guid.align_star", int(align_stars[_star_index()]) if aligning else 0)


## MARK: the star's direction in stable member axes, from the optics and
## the gimbals, each read to a CDU count.
func _on_mark() -> void:
	if not (program in [51, 52] and step_name == "mark"):
		return
	var g := Imu.gimbal_basis(icdu())
	var sh := snappedf(float(Bus.get_value("optics.shaft_deg", 0.0)), Imu.CDU_DEG)
	var tn := snappedf(float(Bus.get_value("optics.trunnion_deg", 0.0)), Imu.CDU_DEG)
	align_marks.append(g * Optics.los(sh, tn))
	if program == 51:
		align_stars[align_marks.size() - 1] = 0
		step_name = "id"
		dsky.show(1, 71, true)
	elif align_marks.size() < 2:
		step_name = "star"
		dsky.show(1, 70, true)
	else:
		_star_angle_difference()
		step_name = "n05"
		dsky.show(6, 5, true)


func _on_mark_reject() -> void:
	if not program in [51, 52] or align_marks.is_empty() or not step_name in ["star", "mark", "id", "n05"]:
		return
	align_marks.pop_back()
	step_name = "mark"
	dsky.show(51, -1, true)


## Two stars the optics can reach from the attitude as the CMC reads it,
## clear of the Earth, the Moon and the Sun, as near a right angle apart as
## there are; false without a pair.
func _select_stars() -> bool:
	var to_body := Basis(_att()).inverse()
	var tr := current_traj()
	var sun := Bodies.sun_direction(tr.t)
	var near := _near_bodies(tr)
	var usable := []
	for c in Stars.codes():
		var s := Stars.direction(c)
		if Optics.angles_for(to_body * s).y > STAR_TRUNNION_MAX_DEG:
			continue
		if rad_to_deg(s.angle_to(sun)) < STAR_SUN_CLEAR_DEG:
			continue
		var hidden := false
		for b in near:
			if rad_to_deg(s.angle_to(b[0])) < float(b[1]) + STAR_LIMB_CLEAR_DEG:
				hidden = true
		if not hidden:
			usable.append(c)
	var best := []
	var best_off := INF
	for i in usable.size():
		for j in range(i + 1, usable.size()):
			var sep := rad_to_deg(Stars.direction(usable[i]).angle_to(Stars.direction(usable[j])))
			if sep >= PAIR_MIN_DEG and sep <= PAIR_MAX_DEG and absf(sep - 90.0) < best_off:
				best_off = absf(sep - 90.0)
				best = [usable[i], usable[j]]
	if best.is_empty():
		return false
	align_stars = best
	return true


## The Earth and the Moon from the CSM at [param tr]: each direction (ECI)
## and angular radius (deg).
static func _near_bodies(tr: Trajectory) -> Array:
	var m := Bodies.moon_position(tr.t)
	var moon := Vector3(m[0], m[1], m[2])
	var geo := tr.pos() if tr.primary == "earth" else tr.pos() + moon
	var out := []
	for b in [[-geo, Bodies.R_EARTH], [moon - geo, Bodies.R_MOON]]:
		var d: Vector3 = b[0]
		out.append([d.normalized(), rad_to_deg(asin(clampf(float(b[1]) / d.length(), 0.0, 1.0)))])
	return out


func _star_angle_difference() -> void:
	var s1 := Stars.direction(align_stars[0])
	var s2 := Stars.direction(align_stars[1])
	var d1: Vector3 = align_marks[0]
	var d2: Vector3 = align_marks[1]
	align_sad_deg = absf(rad_to_deg(d1.angle_to(d2)) - rad_to_deg(s1.angle_to(s2)))


## The rotation (rad, stable member axes) that takes the marked stars where
## REFSMMAT puts them.
func _torquing_angles() -> Vector3:
	var e1 := imu.refsmmat * Stars.direction(align_stars[0])
	var e2 := imu.refsmmat * Stars.direction(align_stars[1])
	var r := _triad(e1, e2) * _triad(align_marks[0], align_marks[1]).transposed()
	return Imu.rotation_vector(r)


## Axes from two directions, as columns, sharing their errors: the
## bisector, the normal and the third.
static func _triad(a: Vector3, b: Vector3) -> Basis:
	var x := (a.normalized() + b.normalized()).normalized()
	var y := a.cross(b).normalized()
	return Basis(x, y, x.cross(y))


func _show_align_step() -> void:
	match step_name:
		"option":
			dsky.show(4, 6, true)
		"n22":
			dsky.show(6, 22, true)
		"coarse":
			dsky.show(16, 20)
		"acquire", "check":
			dsky.show(50, 25, true)
		"star":
			dsky.show(1, 70, true)
		"mark":
			dsky.show(51, -1, true)
		"id":
			dsky.show(1, 71, true)
		"n05":
			dsky.show(6, 5, true)
		"n93":
			dsky.show(6, 93, true)


func snapshot() -> Dictionary:
	var d := super.snapshot()
	var marks := []
	for m in align_marks:
		marks.append([m.x, m.y, m.z])
	d["align"] = {
		"option": align_option, "refsmmat": Imu.rows_of(align_refsmmat), "stars": align_stars.duplicate(),
		"marks": marks, "sad_deg": align_sad_deg, "torque": [align_torque.x, align_torque.y, align_torque.z],
		"checklist": align_checklist, "coarse_load": [coarse_load.x, coarse_load.y, coarse_load.z], "v41": _v41,
		"site_mf": [landing_site_mf.x, landing_site_mf.y, landing_site_mf.z], "landing_get": landing_get,
		"mark_was": _mark_was, "reject_was": _reject_was,
	}
	return d


func restore(d: Dictionary) -> void:
	_restoring = true
	super.restore(d)
	_restoring = false
	var a: Dictionary = d.get("align", {})
	if a.is_empty():
		return
	align_option = int(a["option"])
	align_refsmmat = Imu.from_rows(a["refsmmat"])
	align_stars = [int(a["stars"][0]), int(a["stars"][1])]
	align_marks = []
	for m in a["marks"]:
		align_marks.append(Vector3(m[0], m[1], m[2]))
	align_sad_deg = float(a["sad_deg"])
	var t: Array = a["torque"]
	align_torque = Vector3(t[0], t[1], t[2])
	align_checklist = int(a["checklist"])
	var c: Array = a["coarse_load"]
	coarse_load = Vector3(c[0], c[1], c[2])
	_v41 = bool(a["v41"])
	var sm: Array = a["site_mf"]
	landing_site_mf = Vector3(sm[0], sm[1], sm[2])
	landing_get = float(a["landing_get"])
	_mark_was = bool(a["mark_was"])
	_reject_was = bool(a["reject_was"])
	if program in [51, 52]:
		_show_align_step()


## Entry guidance flies on the sensed deceleration (g) and the state
## vector's speed and altitude rate.
func _entry_step() -> void:
	if not program in [61, 64, 67]:
		Bus.set_value("guid.bank_auto", false)
		return
	var g := float(Bus.get_value("dyn.g_load", 0.0))
	if program == 61 and g >= 0.05:
		change_program(64)
	var tr := current_traj()
	if program == 64 and tr.speed() < ENTRY_FINAL_V:
		change_program(67)
	var auto := (program == 64 or program == 67) and att_source() == 0
	Bus.set_value("guid.bank_auto", auto)
	if not auto:
		return
	var cmd := 0.0
	if program == 64:
		# Lift up until the drag builds to near the reference, then a
		# constant-drag controller on the vertical lift fraction u = cos(bank):
		# more lift when too deep (drag high, or sinking fast), less when
		# shallow or climbing, so the CM neither digs in nor skips out.
		if g >= ENTRY_G_REF * 0.75:
			entry_captured = true
		if entry_captured:
			var hdot := tr.radial_rate()
			var u := 0.2 + 1.5 * (g - ENTRY_G_REF) / ENTRY_G_REF - 0.01 * hdot
			cmd = rad_to_deg(acos(clampf(u, -1.0, 1.0)))
	Bus.set_value("guid.bank_cmd_deg", cmd)

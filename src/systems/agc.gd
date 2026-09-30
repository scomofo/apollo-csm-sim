## Apollo Guidance Computer (Command Module Computer, CMC) with its DSKY:
## the Colossus programs a lunar CSM crew used most, driven through the
## real verb/noun dialogue. The DSKY, P30, the thrusting programs, P47 and
## the digital autopilot are the core's (src/systems/agc_core.gd); the CMC
## adds its engine, its entry programs and its controls.
##
##   P00  CMC idling
##   P30  External ΔV
##   P40  SPS thrusting, on Colossus's cross-product steering (the core's
##        cross_product())
##   P41  RCS thrusting: as P40, but the burn is +X translation on the SM
##        RCS (small corrections the SPS cannot resolve)
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   P61  Entry preparation: V06N61 the target (latitude, longitude; the
##        ground's uplink, or the crew loads it with V25N61) and HEADSUP
##        (+1 heads up, lift down; -1 lift up, preloaded); PRO for V06N60
##        (the peak load expected, the speed and flight path angle at entry
##        interface) and V06N63 (the EMS's range, speed and time to go at
##        the EMS altitude); PRO for P62
##   P62  CM/SM separation and the pre-entry maneuver: V50N25 00041 asks for
##        CM/SM SEP; PRO for V06N61 again; PRO, and in CMC MODE AUTO the CM
##        turns to the entry attitude (V06N22, its gimbal angles: the heat
##        shield into the air, lift up or down by HEADSUP). Once within 45°
##        of it, and 21 s on (Colossus's time for the rest of the maneuver),
##        or at entry interface, P63
##   P63  Entry initialization (V06N64: g, velocity, range to the target);
##        at 0.05 g P64, and from there Colossus's entry guidance (the
##        EntryGuidance port) rolls the lift, a pass every two seconds on
##        the state vector and the accelerometers:
##   P64  V06N74 (roll command, velocity, drag): the initial roll, constant
##        drag, and the prediction of the up-control's range
##   P65  Up-control: V16N69 (roll command, the exit drag and velocity)
##        flashes once, PRO; then V06N74
##   P66  Ballistic, above the air (V06N22)
##   P67  The final phase (V06N66: roll command, crossrange and downrange
##        errors); at 1,000 ft/s steering stops and V16N67 flashes (range
##        to go, latitude, longitude); PRO for P00
##        P63 to P67 follow from the guidance, not V37
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
##   V41N20  Coarse align (the core's): V25N22 flashes for the gimbal
##        angles, and the IMU is driven to them; REFSMMAT no longer holds
##   P23  Cislunar navigation: V05N70 (the star; the landmark, 0; the
##        horizon, 1 the Earth's and 2 the Moon's) [simplified: star-horizon
##        marks only, on the solid limb]; PRO for V50N18, the attitude that
##        lays the sextant's landmark line on the horizon under the star
##        (alarm 00404 when the star is behind the body or past the
##        trunnion's reach); PRO for the auto maneuver (CMC MODE AUTO); V51
##        once there, with the optics on the star in CMC mode; the crew
##        lays the star on the horizon and marks; V06N49 the update (ΔR,
##        ΔV); PRO takes it in and goes back to N70, V32 marks again
##   P22  Lunar orbit navigation: V06N89 the landmark (the landing site,
##        or one the crew loads: latitude, longitude/2, altitude); PRO for
##        V50N18, the attitude that lays the landmark line on it at the
##        next pass; PRO for the maneuver; V51, the optics on the landmark
##        while they reach it; each mark V06N49, PRO or V32 as in P23
##   P37  Return to Earth: V06N33 TIG (half an hour on, or loaded); PRO
##        works out the midcourse correction from the state vector that
##        brings the vacuum perigee to the entry corridor's middle
##        (V06N81); PRO for V06N42; PRO stores it for P40 or P41, as P30
##        does [simplified: the RTCC's targeting, by integration, stands in
##        for P37's conics and its landing-site options]
##   V67  The navigation filter's RMS errors (V06N99: position, velocity);
##        loading either starts the filter again from them
##   V93  Start the filter again from its RMS errors at the next mark
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
## that out, or the crew's own marks (P22, P23) through the navigation
## filter (src/systems/nav_filter.gd). The filter starts again from its RMS
## errors after a burn of more than NavFilter.BIG_BURN_MPS, a start phase
## or an uplink [simplified: the crew's V93 after an uplink is made for
## them].
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
##         ctl.optics.mark_reject, optics.shaft_deg, optics.trunnion_deg,
##         dyn.mass_kg (P37)
## Writes: the core's channels (guid.*, dsky.*), guid.sps_on,
##         guid.bank_auto, guid.bank_cmd_deg, guid.optics.cmd (the CMC
##         drives the optics), guid.optics.cmd_deg (shaft, trunnion),
##         guid.align_marks (P51 and P52's marks taken), guid.align_star
##         (the star to mark, or just marked, 0 for none yet),
##         guid.nav_marks (the marks P22 or P23 has taken in) and
##         guid.landmark_mf (P22's landmark, Moon-fixed, m; zero otherwise)
class_name Agc
extends AgcCore

## The entry's pad loads: the CM's L/D (LADPAD) and the final phase's
## reference L/D (LODPAD) [published: the listing's nominal L/D, and half of
## it for the final phase, as the F mission's entry summary gives it,
## MSC-CF-P-69-7].
const ENTRY_LAD := 0.3
const ENTRY_LOD := 0.15
## P62 hands over to P63 this long after the heat shield comes within
## ENTRY_ALFA_DEG of the entry attitude, s: the rest of the maneuver at
## 3°/s (the listing's WAKEP62) [published].
const ENTRY_ALFA_DEG := 45.0
const ENTRY_WAKE_S := 21.0
## The entry's programs, and those of them its guidance moves on to itself.
const ENTRY_PROGRAMS := [61, 62, 63, 64, 65, 66, 67]
const ENTRY_GUIDANCE := [63, 64, 65, 66, 67]
## P52 takes stars no further than this from the optics' shaft axis, deg,
## clear of the Earth's and the Moon's limbs and of the Sun by these, deg,
## and pairs them this far apart, deg [estimated].
const STAR_TRUNNION_MAX_DEG := 50.0
const STAR_LIMB_CLEAR_DEG := 5.0
const STAR_SUN_CLEAR_DEG := 15.0
const PAIR_MIN_DEG := 30.0
const PAIR_MAX_DEG := 150.0
## A P23 mark's error, deg: its star-horizon angle's [estimated: the
## crew's laying the star on the horizon, some 10 arc seconds]. A P22
## mark's: the landmark's line of sight, each way across it [estimated:
## centring it in the sextant, and the platform's alignment].
const SIGHT_SIGMA_DEG := 0.003
const LANDMARK_SIGMA_DEG := 0.02
## P22 and P23 ask for a mark once the attitude is this near the sighting
## attitude, deg, and the rates this low, deg/s.
const SIGHT_ATT_DEG := 0.5
const SIGHT_RATE_DEG_S := 0.05
## P22 lands the clock this long before its pass, s.
const PASS_LEAD_S := 600.0
## P37's vacuum perigee altitude, m: the entry corridor's middle
## [simplified: Colossus's P37 aimed at an entry flight path angle]; its
## TIG unless the crew loads another, s from now; and how far on it looks
## for the Earth, s.
const P37_PERIGEE_ALT_M := 37000.0
const P37_LEAD_S := 1800.0
const P37_SEARCH_S := 5.0 * 86400.0
## P51, P52, P22, P23 and V67's nouns.
const CMC_NOUNS := {
	5: {"name": "STAR ANGLE DIFF", "c": [["SAD", "d2", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	6: {"name": "OPTION CODE", "c": [["CODE", "o", 1.0], ["OPTION", "o", 1.0], ["", "blank", 1.0]]},
	22: {"name": "NEW ICDU ANGLES", "c": [["OG", "d2", 1.0], ["IG", "d2", 1.0], ["MG", "d2", 1.0]]},
	25: {"name": "CHECKLIST", "c": [["CODE", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	49: {"name": "DELTA R/DELTA V", "c": [["DR", "d1", 1.0 / Dsky.NMI], ["DV", "d1", 1.0 / Dsky.FT], ["", "blank", 1.0]]},
	70: {"name": "STAR/LMK/HOR", "c": [["STAR", "o", 1.0], ["LMK", "o", 1.0], ["HOR", "o", 1.0]]},
	71: {"name": "STAR CODE", "c": [["STAR", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	89: {"name": "LANDMARK", "c": [["LAT", "d3", 1.0], ["LONG/2", "d3", 1.0], ["ALT", "d2", 1.0 / Dsky.NMI]]},
	91: {"name": "OCDU ANGLES", "c": [["SHAFT", "d2", 1.0], ["TRUN", "d3", 1.0], ["", "blank", 1.0]]},
	93: {"name": "TORQUING ANGLES", "c": [["X", "d3", 1.0], ["Y", "d3", 1.0], ["Z", "d3", 1.0]]},
	99: {"name": "RMS ERROR", "c": [["POS", "i", 1.0 / Dsky.FT], ["VEL", "d1", 1.0 / Dsky.FT], ["", "blank", 1.0]]},
	# The entry's: ranges in nautical miles, loads and drag in g.
	60: {"name": "GMAX/VPRED/GAMMAEI", "c": [["GMAX", "d2", 1.0], ["VPRED", "i", 1.0 / Dsky.FT], ["GAMMAEI", "d2", 1.0]]},
	61: {"name": "LAT/LONG/HEADSUP", "c": [["LAT", "d2", 1.0], ["LONG", "d2", 1.0], ["HEADSUP", "i", 1.0]]},
	63: {"name": "RTGO/VIO/TTE", "c": [["RTGO", "d1", 1.0], ["VIO", "i", 1.0 / Dsky.FT], ["TTE", "mmss", 1.0]]},
	64: {"name": "G/VI/RTOGO", "c": [["G", "d2", 1.0], ["VI", "i", 1.0 / Dsky.FT], ["RTOGO", "d1", 1.0]]},
	66: {"name": "ROLLC/XRNG/DNRNG", "c": [["ROLLC", "d2", 1.0], ["XRNGERR", "d1", 1.0], ["DNRNGERR", "d1", 1.0]]},
	67: {"name": "RTOGO/LAT/LONG", "c": [["RTOGO", "d1", 1.0], ["LAT", "d2", 1.0], ["LONG", "d2", 1.0]]},
	69: {"name": "ROLLC/DL/VL", "c": [["ROLLC", "d2", 1.0], ["DL", "d2", 1.0], ["VL", "i", 1.0 / Dsky.FT]]},
	74: {"name": "ROLLC/VI/D", "c": [["ROLLC", "d2", 1.0], ["VI", "i", 1.0 / Dsky.FT], ["D", "d2", 1.0]]},
}

## The entry: Colossus's guidance (P63 to P67); its target, N61's latitude
## and longitude (deg), from the ground's uplink or the crew's load, and
## HEADSUP (+1 lift down, -1 lift up); and P61's predictions
## (EntryGuidance.predict()).
var entry := EntryGuidance.new()
var entry_lat: float = 0.0
var entry_lng: float = 0.0
var entry_headsup: int = -1
var entry_pred: Dictionary = {}
## P40 and P41 steer as Colossus's did (cross_product()); false holds the
## ΔV's LVLH direction instead, as the simulator did before, to compare.
var cross_product_steering: bool = true
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
## P52 option 4's landing site (Moon-fixed, m) and landing time (GET, s).
var landing_site_mf: Vector3 = Vector3.ZERO
var landing_get: float = 0.0
var _mark_was: bool = false
var _reject_was: bool = false
var _restoring: bool = false
## P22 and P23: the star and the horizon (1 the Earth's, 2 the Moon's)
## N70 holds; P22's landmark (Moon-fixed, m) and its next pass (GET, s);
## the marks taken in this run; and a mark's update waiting at N49,
## {"t" (the mark's GET), "dx", "p"}, empty for none.
var sight_star: int = 0
var sight_horizon: int = 1
var sight_landmark_mf: Vector3 = Vector3.ZERO
var sight_pass: float = -1.0
var sight_marks: int = 0
var sight_pending: Dictionary = {}
## The navigation filter, and the RMS errors V67 shows (m, m/s).
var nav_filter := NavFilter.new()
var _rms_shown: Vector2 = Vector2.ZERO
## The ΔV Average-G has taken in since it started, m/s: at its end, the
## burn the filter carries its errors through.
var _burn_dv: float = 0.0
## The entry's accelerometer ΔV since its last pass, m/s, and that pass's
## GET; and the GET P62 wakes P63 at (-1 until the CM is near the entry
## attitude).
var _entry_dv: Vector3 = Vector3.ZERO
var _entry_pass: float = -1.0
var _entry_wake: float = -1.0


## The programs whose Average-G puts the sensed ΔV into the state vector.
const AVERAGE_G := [11, 40, 41, 47, 61, 62, 63, 64, 65, 66, 67]


func _init() -> void:
	super()
	dsky.nouns = Dsky.NOUNS.merged(CMC_NOUNS, true)


func programs() -> Array:
	return [0, 11, 22, 23, 30, 37, 40, 41, 47, 51, 52] + ENTRY_PROGRAMS


func thrusting_programs() -> Array:
	return [40, 41]


## The SPS's thrust, or in P41 the four +X jets'.
func engine_thrust(p: int) -> float:
	if p == 41:
		return 4.0 * float(SpacecraftData.section("sm_rcs")["jet_thrust_n"])
	return float(SpacecraftData.section("sps")["thrust_n"])


func cross_product() -> bool:
	return cross_product_steering


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
	var f := float(SpacecraftData.section("sm_rcs" if SpacecraftData.sm_attached(cfg) else "cm_rcs")["jet_thrust_n"])
	var roll := f * float(c["rcs_roll_arm_m"]) * 4.0
	var pitch := f * float(c["rcs_pitch_arm_m"]) * 2.0
	return Vector3(roll / inertia.x, pitch / inertia.y, pitch / inertia.z)


func start_program(p: int) -> void:
	if p in ENTRY_PROGRAMS:
		if not _restoring:
			_start_entry(p)
		return
	if p == 11:
		# Earth orbit insertion monitor: the speed, the altitude rate and the
		# altitude [simplified: on V16, which the DSKY refreshes, for P11's
		# own V06].
		dsky.show(16, 62)
	if p in [22, 23, 37]:
		if not _restoring:
			_start_nav_program(p)
		return
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


## The CM's buses dead (Apollo 13's power-down): the IMU loses its
## orientation, and comes back caged.
func powered_down() -> void:
	imu.cage(Basis(_true_att()))


## The FDAI's total attitude: the CSM's relative to the stable member.
func indicator_attitude(_lvlh: Quaternion) -> Quaternion:
	return imu.gimbals(Basis(_true_att())).get_rotation_quaternion()


## P27 runs from P00, and only with the UP TLM CM switch in ACCEPT.
func accepts_uplink() -> bool:
	return super.accepts_uplink() and program == 0 and bool(Bus.get_value("ctl.cmc.up_tlm", true))


func avg_g() -> bool:
	return program in AVERAGE_G or str(Bus.get_value("sivb.state", "")) == "burning"


## A start phase's state vector: the filter starts again at the next mark.
func init_nav(tr: Trajectory) -> void:
	super.init_nav(tr)
	nav_filter.stale = true


## The ground's state vector: the filter starts again at the next mark.
func uplink_state(tr: Trajectory) -> bool:
	if not super.uplink_state(tr):
		return false
	nav_filter.stale = true
	return true


## As the core's, and when Average-G stops, the filter carries its errors
## through the burn it took in. The entry's passes take the ΔV in.
func _navigate(dv: Vector3) -> void:
	super._navigate(dv)
	_entry_dv += dv
	if avg_g():
		_burn_dv += dv.length()
	elif _burn_dv > 0.0:
		if nav != null:
			nav_filter.after_burn(nav, _burn_dv)
		_burn_dv = 0.0


## P22 and P23 leave the DAP holding the attitude they flew to, and P40
## and P41 where they leave the CSM (not where it was before their
## maneuver, which a hold would turn it back to).
func change_program(p: int) -> bool:
	if p in ENTRY_GUIDANCE and not _restoring:
		return false
	var steering := auto_active
	var target := auto_target if program in [22, 23] else _att()
	var ok := super.change_program(p)
	if ok and steering:
		hold_q = target
	_publish_nav()
	return ok


func extra_step() -> void:
	_entry_step()
	_align_step()
	_nav_step()


func proceed() -> void:
	if program == 52:
		_proceed_p52()
	elif program == 51:
		_proceed_p51()
	elif program in [22, 23, 37]:
		_proceed_nav()
	elif program in ENTRY_PROGRAMS:
		_proceed_entry()
	else:
		super.proceed()
		return
	# The step on the Bus at once, for the checklist, not at the next tick.
	_publish()
	_publish_align()
	_publish_imu()
	_publish_nav()


func verb_noun(v: int, n: int) -> bool:
	if v == 32 and program in [51, 52] and step_name in ["n05", "n93"]:
		# Recycle: mark again.
		align_marks = []
		_acquire()
		_publish()
		_publish_align()
		return true
	if v == 32 and program in [22, 23] and step_name == "n49":
		_reject_sighting()
		return true
	if v == 67:
		_rms_shown = _nav_rms()
		dsky.show(6, 99, false, false)
		return true
	if v == 93:
		nav_filter.stale = true
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
				return super.noun_values(n)
			if program in [62, 66]:
				# The entry attitude's.
				var e := gimbal_angles_of(_entry_q())
				return [e.x, e.y, e.z]
			var g := Imu.gimbal_angles(align_refsmmat * Basis(_att()))
			return [g.x, g.y, g.z]
		25:
			return [float(align_checklist), 0.0, 0.0]
		49:
			var dx: PackedFloat64Array = sight_pending.get("dx", PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0]))
			return [Vector3(dx[0], dx[1], dx[2]).length(), Vector3(dx[3], dx[4], dx[5]).length(), 0.0]
		70:
			if program == 23:
				return [float(sight_star), 0.0, float(sight_horizon)]
			return [float(align_stars[_star_index()]), 0.0, 0.0]
		71:
			return [float(align_stars[_star_index()]), 0.0, 0.0]
		89:
			var s := Bodies.fixed_to_selenographic(sight_landmark_mf)
			return [s.x, s.y / 2.0, s.z - Bodies.R_MOON]
		91:
			return [float(Bus.get_value("optics.shaft_deg", 0.0)), float(Bus.get_value("optics.trunnion_deg", 0.0)), 0.0]
		93:
			# The gyros' torquing, the platform's own turn back onto
			# REFSMMAT: Imu.torque() takes the reverse, its reference's.
			return [-rad_to_deg(align_torque.x), -rad_to_deg(align_torque.y), -rad_to_deg(align_torque.z)]
		99:
			return [_rms_shown.x, _rms_shown.y, 0.0]
		60:
			return [float(entry_pred.get("gmax", 0.0)), float(entry_pred.get("vpred", 0.0)),
				float(entry_pred.get("gammaei", 0.0))]
		61:
			return [entry_lat, entry_lng, float(entry_headsup)]
		63:
			return [float(entry_pred.get("rtgo", 0.0)), float(entry_pred.get("vio", 0.0)),
				_now() - float(entry_pred.get("tte_get", _now()))]
		64:
			return [entry.d / EntryGuidance.G, entry.v * EntryGuidance.FT, entry.theta * EntryGuidance.ATK]
		66:
			return [entry.rollc_deg(), entry.latang * EntryGuidance.ATK, entry.dnrngerr]
		67:
			var tr := current_traj()
			var p := Bodies.eci_to_earth_fixed([tr.pos().x, tr.pos().y, tr.pos().z], tr.t)
			var ll := Bodies.fixed_to_geographic(Vector3(p[0], p[1], p[2]))
			return [entry.theta * EntryGuidance.ATK, ll.x, ll.y]
		69:
			return [entry.rollc_deg(), entry.q7 / EntryGuidance.G, entry.vl * EntryGuidance.FT]
		74:
			return [entry.rollc_deg(), entry.v * EntryGuidance.FT, entry.d / EntryGuidance.G]
	return super.noun_values(n)


func noun_load(n: int, idx: int, value: float) -> bool:
	match n:
		6:
			if idx != 1 or program != 52 or step_name != "option" or not int(value) in [1, 2, 3, 4]:
				return false
			align_option = int(value)
			return true
		70:
			if program == 23:
				return _load_sighting(idx, int(value))
			if idx != 0 or not program in [51, 52] or not Stars.has(int(value)):
				return false
			align_stars[_star_index()] = int(value)
			_publish_align()
			return true
		71:
			if idx != 0 or not program in [51, 52] or not Stars.has(int(value)):
				return false
			align_stars[_star_index()] = int(value)
			_publish_align()
			return true
		89:
			if program != 22 or step_name != "n89":
				return false
			var s := Bodies.fixed_to_selenographic(sight_landmark_mf)
			var lla := [s.x, s.y, s.z - Bodies.R_MOON]
			lla[idx] = value * 2.0 if idx == 1 else value
			sight_landmark_mf = Bodies.selenographic_to_fixed(lla[0], lla[1], Bodies.R_MOON + lla[2])
			return true
		61:
			if not program in [61, 62] or step_name != "n61":
				return false
			match idx:
				0:
					if absf(value) > 90.0:
						return false
					entry_lat = value
				1:
					if absf(value) > 180.0:
						return false
					entry_lng = value
				2:
					if absf(absf(value) - 1.0) > 1e-6:
						return false
					entry_headsup = int(value)
			return true
		99:
			if idx == 0 and value >= 1.0:
				nav_filter.pos_rms = value
			elif idx == 1 and value >= 0.001:
				nav_filter.vel_rms = value
			else:
				return false
			nav_filter.stale = true
			_rms_shown = Vector2(nav_filter.pos_rms, nav_filter.vel_rms)
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
			imu.refsmmat = Imu.triad(align_marks[0], align_marks[1]) * Imu.triad(s1, s2).transposed()
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
	var aim := _optics_aim()
	Bus.set_value("guid.optics.cmd", aim != Vector3.ZERO)
	if aim != Vector3.ZERO:
		var a := Optics.angles_for(aim)
		Bus.set_value("guid.optics.cmd_deg", Vector3(a.x, a.y, 0.0))
	_publish_align()


## Where the CMC drives the optics, body axes (zero for nowhere): P52's
## star, P23's star, and P22's landmark while the trunnion reaches it
## above its horizon, each where the state vector and the platform put it.
func _optics_aim() -> Vector3:
	if program == 52 and step_name in ["star", "mark"]:
		return Basis(_att()).inverse() * Stars.direction(align_stars[_star_index()])
	if not (program in [22, 23] and step_name in ["maneuver", "mark"]):
		return Vector3.ZERO
	if program == 23:
		return Basis(_att()).inverse() * Stars.direction(sight_star) if Stars.has(sight_star) else Vector3.ZERO
	if nav == null or not _landmark_visible(nav):
		return Vector3.ZERO
	var d := Basis(_att()).inverse() * (NavFilter.landmark_los(nav, sight_landmark_mf)["los"] as Vector3)
	return d if Optics.angles_for(d).y <= Optics.TRUNNION_MAX_DEG else Vector3.ZERO


## P51 and P52's marks taken and the star they're on, on the Bus.
func _publish_align() -> void:
	var aligning := program in [51, 52]
	Bus.set_value("guid.align_marks", align_marks.size() if aligning else 0)
	Bus.set_value("guid.align_star", int(align_stars[_star_index()]) if aligning else 0)


## MARK: the star's direction in stable member axes, from the optics and
## the gimbals, each read to a CDU count; in P22 and P23 a sighting.
func _on_mark() -> void:
	if program in [22, 23] and step_name == "mark":
		_mark_sighting()
		return
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
	if program in [22, 23] and step_name == "n49":
		_reject_sighting()
		return
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
	var r := Imu.triad(e1, e2) * Imu.triad(align_marks[0], align_marks[1]).transposed()
	return Imu.rotation_vector(r)


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
		"checklist": align_checklist,
		"site_mf": [landing_site_mf.x, landing_site_mf.y, landing_site_mf.z], "landing_get": landing_get,
		"mark_was": _mark_was, "reject_was": _reject_was,
	}
	var pending := {}
	if not sight_pending.is_empty():
		pending = {"t": sight_pending["t"], "dx": Array(sight_pending["dx"]), "p": Array(sight_pending["p"])}
	d["sight"] = {
		"star": sight_star, "horizon": sight_horizon,
		"landmark_mf": [sight_landmark_mf.x, sight_landmark_mf.y, sight_landmark_mf.z], "pass": sight_pass,
		"marks": sight_marks, "pending": pending, "rms_shown": [_rms_shown.x, _rms_shown.y], "burn_dv": _burn_dv,
	}
	d["nav_filter"] = nav_filter.snapshot()
	d["entry"] = {
		"guidance": entry.snapshot(), "lat": entry_lat, "lng": entry_lng, "headsup": entry_headsup,
		"pred": entry_pred.duplicate(), "dv": [_entry_dv.x, _entry_dv.y, _entry_dv.z], "pass": _entry_pass,
		"wake": _entry_wake,
	}
	return d


func restore(d: Dictionary) -> void:
	_restoring = true
	super.restore(d)
	_restoring = false
	_restore_nav(d)
	_restore_entry(d)
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
	var sm: Array = a["site_mf"]
	landing_site_mf = Vector3(sm[0], sm[1], sm[2])
	landing_get = float(a["landing_get"])
	_mark_was = bool(a["mark_was"])
	_reject_was = bool(a["reject_was"])
	if program in [51, 52]:
		_show_align_step()


# --- navigation: P22, P23 and P37 ---------------------------------------------------

func _start_nav_program(p: int) -> void:
	sight_pending = {}
	sight_marks = 0
	sight_pass = -1.0
	match p:
		23:
			step_name = "n70"
			dsky.show(5, 70, true)
		22:
			if sight_landmark_mf == Vector3.ZERO:
				sight_landmark_mf = landing_site_mf
			if current_traj().primary != "moon" or sight_landmark_mf == Vector3.ZERO:
				# Not in lunar orbit, or no landmark to track.
				dsky.set_lamp("opr_err", true)
				change_program(0)
				return
			step_name = "n89"
			dsky.show(6, 89, true)
		37:
			tig_load = ceilf((_now() + P37_LEAD_S) / 60.0) * 60.0
			step_name = "n33"
			dsky.show(6, 33, true)


func _proceed_nav() -> void:
	match step_name:
		"n70":
			_plan_sighting()
		"n89":
			_plan_pass()
		"v50n18":
			if _locks_gimbals(auto_target):
				_alarm(401)
				return
			_plan_via()
			auto_active = true
			step_name = "maneuver"
			dsky.show(6, 18)
		"n49":
			_take_sighting()
		"n33":
			_plan_return()
		"n81":
			step_name = "n42"
			dsky.show(6, 42, true)
		"n42":
			_store_maneuver()
			change_program(0)


## N70's loads in P23: the star (R1), the landmark (R2: none, 0) and the
## horizon (R3: 1 the Earth's, 2 the Moon's).
func _load_sighting(idx: int, value: int) -> bool:
	match idx:
		0:
			if not Stars.has(value):
				return false
			sight_star = value
		1:
			return value == 0
		2:
			if not value in [1, 2]:
				return false
			sight_horizon = value
	return true


func _horizon_body() -> String:
	return "earth" if sight_horizon == 1 else "moon"


## P23's PRO at N70: the attitude that lays the landmark line on the
## horizon under the star, where the state vector puts it (alarm 00404
## when the star is behind the body or past the trunnion's reach).
func _plan_sighting() -> void:
	if not Stars.has(sight_star):
		dsky.set_lamp("opr_err", true)
		return
	var m := NavFilter.star_horizon(current_traj(), Stars.direction(sight_star), _horizon_body())
	if m.is_empty() or rad_to_deg(float(m["q"])) > Optics.TRUNNION_MAX_DEG:
		_alarm(404)
		return
	_fly_to_sight(m["horizon"])


## P22's PRO at N89: the next pass over the landmark from the state
## vector, found again with the landmark where the Moon has turned it by
## then, and the attitude that lays the landmark line on it there.
func _plan_pass() -> void:
	var tr := current_traj()
	if tr.primary != "moon" or sight_landmark_mf == Vector3.ZERO:
		dsky.set_lamp("opr_err", true)
		return
	var t := tr.t
	for _i in 2:
		t = Rtcc.time_at_direction(current_traj(), Rtcc.site_at(sight_landmark_mf, t).normalized(), tr.t)
	sight_pass = t
	_fly_to_sight(Rtcc.site_at(sight_landmark_mf, t) - predict(t).pos())


## V50N18 for the attitude that lays the sextant's landmark line along
## [param dir] (ECI), turned about it to the one nearest the CSM's attitude
## that keeps the middle gimbal clear (alarm 00401 if none does). The DAP
## holds the attitude it was holding till PRO.
func _fly_to_sight(dir: Vector3) -> void:
	var now := _att()
	var d := dir.normalized()
	var base := (Quaternion(Basis(now) * Optics.landmark_line(), d) * now).normalized()
	var best := Quaternion.IDENTITY
	var best_angle := INF
	for k in 12:
		var q := (Quaternion(d, TAU * k / 12.0) * base).normalized()
		var a := _angle_between(now, q)
		if a < best_angle and not _locks_gimbals(q):
			best = q
			best_angle = a
	if best_angle == INF:
		_alarm(401)
		return
	if auto_active:
		hold_q = auto_target
		auto_active = false
	auto_target = best
	desired_q = best
	step_name = "v50n18"
	dsky.show(50, 18, true)


## The landmark is above its horizon from [param tr].
func _landmark_visible(tr: Trajectory) -> bool:
	var st := tr.moon_state_rel()
	var site := Rtcc.site_at(sight_landmark_mf, tr.t)
	return (Vector3(st[0], st[1], st[2]) - site).dot(site) > 0.0


## MARK in P22 or P23: the sighting weighted in by the filter, for N49;
## the state vector moves only on PRO. P22 needs the platform's
## orientation (alarm 00220).
func _mark_sighting() -> void:
	if nav == null:
		return
	if program == 22 and not (imu.aligned and imu.operating()):
		_alarm(220)
		return
	var pm := nav_filter.carried(nav)
	var u := _horizon_update(pm) if program == 23 else _landmark_update(pm)
	if u.is_empty():
		_alarm(404)
		return
	sight_pending = {"t": nav.t, "dx": u["dx"], "p": u["p"]}
	step_name = "n49"
	dsky.show(6, 49, true)


## P23's mark: the sextant's trunnion angle, read to SEXTANT_READ_DEG, is
## the star's angle from the horizon; against the state vector's. Empty
## when the state vector puts the star behind the body.
func _horizon_update(pm: PackedFloat64Array) -> Dictionary:
	var m := NavFilter.star_horizon(nav, Stars.direction(sight_star), _horizon_body())
	if m.is_empty():
		return {}
	var q := deg_to_rad(snappedf(float(Bus.get_value("optics.trunnion_deg", 0.0)), Optics.SEXTANT_READ_DEG))
	var s := deg_to_rad(SIGHT_SIGMA_DEG)
	return NavFilter.scalar_update(pm, m["b"], q - float(m["q"]), s * s)


## P22's mark: the landmark's line of sight, from the optics and the
## gimbals, each read to a CDU count, and REFSMMAT; against the state
## vector's, each way across it in turn.
func _landmark_update(pm: PackedFloat64Array) -> Dictionary:
	var sh := snappedf(float(Bus.get_value("optics.shaft_deg", 0.0)), Imu.CDU_DEG)
	var tn := snappedf(float(Bus.get_value("optics.trunnion_deg", 0.0)), Imu.CDU_DEG)
	var seen := imu.refsmmat.transposed() * (Imu.gimbal_basis(icdu()) * Optics.los(sh, tn))
	var m := NavFilter.landmark_los(nav, sight_landmark_mf)
	var rng := float(m["range"])
	var s := deg_to_rad(LANDMARK_SIGMA_DEG)
	var dx := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var p := pm
	for e: Vector3 in [m["e1"], m["e2"]]:
		var b := PackedFloat64Array([-e.x / rng, -e.y / rng, -e.z / rng, 0.0, 0.0, 0.0])
		# The residual, less what the first way's update already took out.
		var dq := float(seen.dot(e))
		for i in 3:
			dq -= b[i] * dx[i]
		var u := NavFilter.scalar_update(p, b, dq, s * s)
		var step: PackedFloat64Array = u["dx"]
		for i in 6:
			dx[i] += step[i]
		p = u["p"]
	return {"dx": dx, "p": p}


## PRO at N49: the mark's update into the state vector, carried on from
## the mark's time to first order, and its errors the filter's. P23 goes
## back to N70, P22 to the next mark.
func _take_sighting() -> void:
	if sight_pending.is_empty() or nav == null:
		return
	var dx := (sight_pending["dx"] as PackedFloat64Array).duplicate()
	var dt := nav.t - float(sight_pending["t"])
	for i in 3:
		dx[i] += dx[i + 3] * dt
	nav_filter.accept(nav, dx, sight_pending["p"])
	sight_pending = {}
	sight_marks += 1
	if program == 23:
		step_name = "n70"
		dsky.show(5, 70, true)
	else:
		step_name = "mark"
		dsky.show(51, -1, true)


## V32 or MARK REJECT at N49: the mark dropped, to mark again.
func _reject_sighting() -> void:
	sight_pending = {}
	step_name = "mark"
	dsky.show(51, -1, true)
	_publish_nav()


## P37's PRO at N33: the correction at TIG, from the state vector, that
## brings the vacuum perigee to P37_PERIGEE_ALT_M, none when it's within
## the RTCC's tolerance. OPR ERR for a TIG less than a minute off, or a
## state vector that doesn't come back to the Earth.
func _plan_return() -> void:
	if tig_load < _now() + 60.0:
		dsky.set_lamp("opr_err", true)
		return
	var t_max := tig_load + P37_SEARCH_S
	var er := Rtcc.earth_return(predict(tig_load), t_max)
	if not bool(er["reached"]):
		dsky.set_lamp("opr_err", true)
		return
	var target := signf(float(er["f"])) * (Bodies.R_EARTH + P37_PERIGEE_ALT_M)
	var pad := Rtcc.plan_mcc(current_traj(), float(Bus.get_value(_ch("dyn.mass_kg"), 30000.0)), tig_load, "earth", target, t_max)
	dv_lvlh_load = pad["dv_lvlh"]
	step_name = "n81"
	dsky.show(6, 81, true)


## Each step: P22 and P23 ask for a mark once at the sighting attitude, and
## P22 lands the clock ahead of its pass.
func _nav_step() -> void:
	if program in [22, 23] and step_name == "maneuver" and _att_error(auto_target) < deg_to_rad(SIGHT_ATT_DEG) \
			and _omega().length() < deg_to_rad(SIGHT_RATE_DEG_S):
		step_name = "mark"
		dsky.show(51, -1, true)
	if program == 22:
		var lead := sight_pass - PASS_LEAD_S
		Bus.set_value("guid.next_event_get_s", lead if sight_pass > 0.0 and _now() < lead else -1.0)
	_publish_nav()


func _publish_nav() -> void:
	Bus.set_value("guid.nav_marks", sight_marks if program in [22, 23] else 0)
	Bus.set_value("guid.landmark_mf", sight_landmark_mf if program == 22 else Vector3.ZERO)


## The filter's RMS errors now (m, m/s): its covariance carried to the
## state vector's time, or the RMS it starts again from.
func _nav_rms() -> Vector2:
	if nav == null or nav_filter.stale or nav_filter.anchor == null:
		return Vector2(nav_filter.pos_rms, nav_filter.vel_rms)
	return NavFilter.rms(nav_filter.carried(nav))


func _show_nav_step() -> void:
	match step_name:
		"n70":
			dsky.show(5, 70, true)
		"n89":
			dsky.show(6, 89, true)
		"v50n18":
			dsky.show(50, 18, true)
		"maneuver":
			dsky.show(6, 18)
		"mark":
			dsky.show(51, -1, true)
		"n49":
			dsky.show(6, 49, true)
		"n33":
			dsky.show(6, 33, true)
		"n81":
			dsky.show(6, 81, true)
		"n42":
			dsky.show(6, 42, true)


func _restore_nav(d: Dictionary) -> void:
	var s: Dictionary = d.get("sight", {})
	if not s.is_empty():
		sight_star = int(s["star"])
		sight_horizon = int(s["horizon"])
		var l: Array = s["landmark_mf"]
		sight_landmark_mf = Vector3(l[0], l[1], l[2])
		sight_pass = float(s["pass"])
		sight_marks = int(s["marks"])
		sight_pending = {}
		var pd: Dictionary = s["pending"]
		if not pd.is_empty():
			sight_pending = {"t": float(pd["t"]), "dx": PackedFloat64Array(pd["dx"]), "p": PackedFloat64Array(pd["p"])}
		var r: Array = s["rms_shown"]
		_rms_shown = Vector2(r[0], r[1])
		_burn_dv = float(s["burn_dv"])
	nav_filter.restore(d.get("nav_filter", {}))
	if program in [22, 23, 37]:
		_show_nav_step()


# --- the entry ----------------------------------------------------------------

## The ground's entry target (P27, with the entry PAD): N61's latitude and
## longitude, deg. Returns false, loading nothing, when the computer doesn't
## take uplinks now (accepts_uplink()).
func uplink_entry_target(lat_deg: float, lng_deg: float) -> bool:
	if not accepts_uplink():
		return false
	entry_lat = lat_deg
	entry_lng = lng_deg
	_uplink_shown()
	return true


## The target, a unit vector in the Earth-fixed frame.
func entry_target_ef() -> Vector3:
	return EntryGuidance.target_of(entry_lat, entry_lng)


## P61 preloads HEADSUP (lift up) and flashes the target, N61; P62 asks for
## CM/SM separation (V50N25 00041).
func _start_entry(p: int) -> void:
	_entry_pass = -1.0
	_entry_wake = -1.0
	if p == 61:
		entry_headsup = -1
		entry_pred = {}
		step_name = "n61"
		dsky.show(6, 61, true)
	elif p == 62:
		align_checklist = 41
		step_name = "sep"
		dsky.show(50, 25, true)


func _proceed_entry() -> void:
	match step_name:
		"n61":
			if program == 61:
				entry_pred = EntryGuidance.predict(current_traj(), entry_target_ef())
				step_name = "n60"
				dsky.show(6, 60, true)
			else:
				# The roll to fly into the air by, and the maneuver to the
				# entry attitude.
				entry.rollc = 0.0 if entry_headsup < 0 else PI
				auto_target = _entry_q()
				_plan_via()
				auto_active = true
				step_name = "n22"
				dsky.show(6, 22)
		"n60":
			step_name = "n63"
			dsky.show(6, 63, true)
		"n63":
			change_program(62)
		"sep":
			step_name = "n61"
			dsky.show(6, 61, true)
		"n69":
			step_name = ""
			dsky.show(6, 74)
		"n67":
			change_program(0)


func _restore_entry(d: Dictionary) -> void:
	var e: Dictionary = d.get("entry", {})
	if e.is_empty():
		return
	entry.restore(e["guidance"])
	entry_lat = float(e["lat"])
	entry_lng = float(e["lng"])
	entry_headsup = int(e["headsup"])
	entry_pred = {}
	var pr: Dictionary = e["pred"]
	for k in pr:
		entry_pred[k] = float(pr[k])
	var dv: Array = e["dv"]
	_entry_dv = Vector3(dv[0], dv[1], dv[2])
	_entry_pass = float(e["pass"])
	_entry_wake = float(e["wake"])
	if program in ENTRY_PROGRAMS:
		match step_name:
			"n61":
				dsky.show(6, 61, true)
			"n60":
				dsky.show(6, 60, true)
			"n63":
				dsky.show(6, 63, true)
			"sep":
				dsky.show(50, 25, true)
			"n22":
				dsky.show(6, 22)
			"n69":
				dsky.show(16, 69, true)
			"n67":
				dsky.show(16, 67, true)
			_:
				dsky.show(6, {63: 64, 64: 74, 65: 74, 66: 22, 67: 66}.get(program, 64))


## The entry attitude now: the heat shield into the air as the state vector
## has it, the lift rolled to the roll command.
func _entry_q() -> Quaternion:
	var tr := current_traj()
	var vhat := Atmosphere.air_velocity(tr.pos(), tr.vel()).normalized()
	return Dynamics.trim_basis(tr.pos(), vhat, deg_to_rad(entry.bank_cmd_deg())).get_rotation_quaternion()


## Each step: P62 and P63 keep the maneuver on the entry attitude as the
## air turns, and P62 wakes P63 near it; from P63 a guidance pass every
## two seconds, which moves the program on; the roll command to the entry
## DAP (guid.bank_cmd_deg; guid.bank_over_top, Colossus's LATSW, once the
## drag is heavy), which flies it while the SCS takes the CMC's attitude.
func _entry_step() -> void:
	var now := _now()
	var in_air := bool(Bus.get_value(_ch("dyn.in_atmosphere"), false))
	if program == 62 and step_name == "n22":
		auto_target = _entry_q()
		if in_air:
			_entry_phase(63)
		elif _entry_wake < 0.0:
			var x_now := Basis(_att()) * Vector3.RIGHT
			var x_to := Basis(auto_target) * Vector3.RIGHT
			if x_now.angle_to(x_to) < deg_to_rad(ENTRY_ALFA_DEG):
				_entry_wake = now + ENTRY_WAKE_S
		elif now >= _entry_wake:
			_entry_phase(63)
	if program == 63 and not in_air:
		auto_target = _entry_q()
	if program in ENTRY_GUIDANCE and entry.mode != "done" and now >= _entry_pass + EntryGuidance.PASS_S - 1e-6 \
			and nav != null:
		var dt := now - _entry_pass
		entry.step(nav.pos(), nav.vel(), _entry_dv, now, dt)
		_entry_dv = Vector3.ZERO
		_entry_pass = now
		if entry.program != program:
			_entry_phase(entry.program)
		if entry.mode == "done" and step_name != "n67":
			step_name = "n67"
			dsky.show(16, 67, true)
	var auto := program in ENTRY_PROGRAMS and program != 61 and step_name != "sep" and att_source() == 0
	Bus.set_value("guid.bank_auto", auto)
	Bus.set_value("guid.bank_cmd_deg", entry.bank_cmd_deg() if auto else 0.0)
	Bus.set_value("guid.bank_over_top", auto and not entry.latsw)


## The entry moves on to program [param p]: P63 starts the guidance on the
## state vector; P64 to P67 are the guidance's phases.
func _entry_phase(p: int) -> void:
	program = p
	step_name = ""
	dsky.set_prog(p)
	match p:
		63:
			var tr := current_traj()
			entry.start(tr.pos(), tr.vel(), _now(), ENTRY_LAD, ENTRY_LOD, entry_target_ef(), entry_headsup)
			_entry_dv = Vector3.ZERO
			_entry_pass = _now() - EntryGuidance.PASS_S
			dsky.show(6, 64)
		64:
			dsky.show(6, 74)
		65:
			step_name = "n69"
			dsky.show(16, 69, true)
		66:
			dsky.show(6, 22)
		67:
			dsky.show(6, 66)
	_publish()

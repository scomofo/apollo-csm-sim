## LM Guidance Computer (LGC) with its DSKY: the Luminary programs for the
## LM's burns in lunar orbit, on the AGC core the CMC shares
## (src/systems/agc_core.gd). It reads the LM's truth and writes its own
## channels: lm.dyn.* in, lm.guid.* and lm.dsky.* out.
##
##   P00  LGC idling
##   P30  External ΔV (the DOI PAD's TIG and ΔV)
##   P40  DPS thrusting: the engine starts at 10 % throttle and burns at
##        40 % after 15 s, as Apollo 11's DOI did [simplified: the crew
##        throttled up by hand]
##   P41  RCS thrusting: +X translation on the LM RCS
##   P42  APS thrusting (the ascent stage, after staging)
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   P63  Braking: the ignition algorithm finds TIG, 470 km (ground range)
##        before the landing site, then V50N18 auto maneuver, V99 at TIG-5 s,
##        26 s at 10 % throttle, and Klumpp's quadratic guidance at full
##        thrust until the throttle comes back into its range; V16N68
##   P64  Approach, from high gate: the same guidance to the approach
##        target, the throttle in its range; V16N64 [simplified: no
##        landing point redesignation]
##   P65  Automatic landing: nulls the horizontal velocity and slows the
##        descent to 0.8 m/s near the surface; V16N60
##   P66  Rate of descent, from P64 or P65 at the first ROD click: the crew
##        flies the attitude, and the throttle holds the descent rate each
##        click moves by 1 ft/s; V16N60
##   P68  Landing confirmation at touchdown: engine off, V06N43
##
## The descent's guidance runs in a frame fixed at the landing site (x up,
## y crossrange, z downrange along the ground track), turning with the
## Moon. Its targets are in data/spacecraft.json ("descent_guidance").
## Navigation is ideal [simplified: no landing radar].
##
## The LGC runs while the LM flies free [simplified: the LM powers up as it
## undocks; docked, and after LM JETT, the LGC is dark and the CSM flies
## the stack].
##
## Digital autopilot: ctl.lm.mode 0 FREE, 1 HOLD, 2 AUTO, as the CMC's,
## with the ACA (ctl.lm.rhc) about the LM's X, Y and Z axes: the LM crew's
## yaw, pitch and roll [simplified: the LM's PGNS MODE CONTROL is OFF,
## ATT HOLD and AUTO; no AGS]. Powering up, it holds the attitude the LM
## has.
##
## Reads:  the core's, lm.dyn.landed, ctl.lm.rod (the ROD switch: +1 up,
##         -1 down, momentary)
## Writes: the core's channels under lm. (lm.guid.*, lm.dsky.*),
##         lm.guid.dps_on, lm.guid.dps_throttle, lm.guid.aps_on
class_name Lgc
extends AgcCore

## Powered descent's programs, and those that fire the descent engine.
const DESCENT := [63, 64, 65, 66, 68]
const DESCENT_BURN := [63, 64, 65, 66]
## The nouns the LGC adds, or means otherwise than the CMC does.
const LGC_NOUNS := {
	43: {"name": "LAT/LONG/ALT", "c": [["LAT", "d2", 1.0], ["LONG", "d2", 1.0], ["ALT", "d1", 1.0 / Dsky.NMI]]},
	60: {"name": "VH/HDOT/H", "c": [["VH", "d1", 1.0 / Dsky.FT], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	64: {"name": "LPD/HDOT/H", "c": [["LPD", "i", 1.0], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	68: {"name": "RNG/TGO/V", "c": [["RNG", "d1", 1.0 / Dsky.NMI], ["TGO", "mmss", 1.0], ["V", "i", 1.0 / Dsky.FT]]},
}

## The landing site in the Moon-fixed frame (uplinked with the DOI PAD),
## m; zero until then.
var landing_site: Vector3 = Vector3.ZERO
## The guidance frame fixed at the site, its axes (x up, y crossrange,
## z downrange) in the Moon-fixed frame.
var guidance_frame: Basis = Basis.IDENTITY
## Powered descent's ignition, GET s.
var pdi_tig: float = 0.0
## Time to go to the phase's target, s.
var tgo: float = 0.0
## The DPS throttle the descent commands, a fraction of full thrust.
var descent_throttle: float = 0.1
## P66's altitude rate, m/s (negative down).
var rod_cmd: float = 0.0
var _rod_was: int = 0
var _guide_get: float = -1.0
var _restoring: bool = false
# What the descent displays show: ground range to the site (m), speed over
# the surface, horizontal and vertical (m/s), footpads' height (m) and the
# landing point's angle from the LM's +Z axis (°).
var _range := 0.0
var _speed := 0.0
var _vh := 0.0
var _hdot := 0.0
var _h := 0.0
var _lpd := 0.0


func _init() -> void:
	super()
	prefix = "lm."
	dsky.nouns = Dsky.NOUNS.merged(LGC_NOUNS, true)


func programs() -> Array:
	return [0, 30, 40, 41, 42, 47] + DESCENT


func thrusting_programs() -> Array:
	return [40, 41, 42]


func engine_thrust(p: int) -> float:
	if p == 42:
		return float(SpacecraftData.section("aps")["thrust_n"])
	return float(SpacecraftData.section("dps")["thrust_n"]) * Dps.throttle_target(throttle())


func engine_tau_off(p: int) -> float:
	return float(SpacecraftData.section("aps" if p == 42 else "dps")["tau_off_s"])


func engine_running() -> bool:
	return bool(Bus.get_value("lm.dps.on", false)) or bool(Bus.get_value("lm.aps.on", false))


func publish_engine(on: bool) -> void:
	Bus.set_value("lm.guid.dps_on", on and (program == 40 or program in DESCENT_BURN))
	Bus.set_value("lm.guid.dps_throttle", throttle())
	Bus.set_value("lm.guid.aps_on", on and program == 42)


## The DPS throttle the LGC commands, a fraction of full thrust: in
## powered descent the guidance's; in P40 the start throttle for
## p40_start_s after ignition, then the burn throttle.
func throttle() -> float:
	if program in DESCENT_BURN:
		return descent_throttle
	var d := SpacecraftData.section("dps")
	if ignition_get < 0.0 or _now() - ignition_get < float(d["p40_start_s"]):
		return float(d["p40_start_throttle"])
	return float(d["p40_throttle"])


func mode() -> int:
	return int(Bus.get_value("ctl.lm.mode", 1))


func rhc() -> Vector3:
	return Bus.get_value("ctl.lm.rhc", Vector3.ZERO)


func is_powered() -> bool:
	return _free() and bool(Bus.get_value("lm.sys.powered", true))


## On the surface the LM sits on its gear: its DAP fires no jets.
func dap_enabled() -> bool:
	return not bool(Bus.get_value("lm.dyn.landed", false))


func auto_rate() -> float:
	if program in DESCENT_BURN:
		return deg_to_rad(float(SpacecraftData.section("descent_guidance")["auto_rate_dps"]))
	return RATE_AUTO


## The DAP takes up the attitude the LM has as its hold.
func powered_up() -> void:
	_last_source = -1


func authority() -> Vector3:
	var cfg := str(Bus.get_value("lm.dyn.config", "lm"))
	var mass := float(Bus.get_value("lm.dyn.mass_kg", SpacecraftData.lm_mass()))
	var inertia := SpacecraftData.inertia(cfg if cfg in SpacecraftData.LM_CONFIGS else "lm", mass)
	var d := SpacecraftData.section("lm_rcs")
	# Both systems' jets about each axis.
	var t := float(d["jet_thrust_n"]) * float(d["arm_m"]) * float(d["rotation_jets"]) * 2.0
	return Vector3(t / inertia.x, t / inertia.y, t / inertia.z)


## The LM's accelerometers count only while it flies free.
func sense(dt: float) -> void:
	if _free():
		super.sense(dt)


func _free() -> bool:
	return str(Bus.get_value("dock.state", "")) == "free"


# --- powered descent ---------------------------------------------------------------

## Load the landing site from the ground (with the DOI PAD), Moon-fixed, m.
func uplink_landing_site(site_mf: Vector3) -> void:
	landing_site = site_mf
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


## P63 needs the landing site and the LM flying free; P64 to P68 come only
## from the descent itself.
func change_program(p: int) -> bool:
	if not _restoring:
		if p == 63 and (landing_site == Vector3.ZERO or not _free()):
			_alarm(1520)
			return false
		if p in DESCENT and p != 63:
			_alarm(1520)
			return false
	return super.change_program(p)


func start_program(p: int) -> void:
	if p == 63 and not _restoring:
		_start_p63()


func _start_p63() -> void:
	var tr := current_traj()
	var up := landing_site.normalized()
	# Downrange is along the ground track, as the LM will pass over the site.
	var h := (Bodies.moon_fixed(_now()).transposed() * tr.pos().cross(tr.vel())).normalized()
	var z := h.cross(up).normalized()
	guidance_frame = Basis(up, z.cross(up), z)
	pdi_tig = ignition_time(tr, float(SpacecraftData.section("descent_guidance")["pdi_range_m"]))
	step_name = "tig"
	dsky.show(6, 33, true)


## P63's ignition algorithm: the time [param tr] comes within
## [param pdi_range] (ground range) of the landing site on its next pass.
func ignition_time(tr: Trajectory, pdi_range: float) -> float:
	var t := tr.clone()
	var box := {"prev": _range_to_site(t)}
	var within := func(t2: Trajectory) -> bool:
		var rng := _range_to_site(t2)
		var hit: bool = box["prev"] > pdi_range and rng <= pdi_range
		box["prev"] = rng
		return hit
	t.coast_until(within, t.t + 1.5 * float(t.conic()["period"]), 20.0, 0.002)
	# Back up to the crossing at the ground speed.
	var ground := t.speed() * Bodies.R_MOON / t.radius()
	return t.t - (pdi_range - _range_to_site(t)) / ground


## Ground range from under [param tr] to the landing site, m.
func _range_to_site(tr: Trajectory) -> float:
	return tr.pos().angle_to(Bodies.moon_fixed(tr.t) * landing_site) * Bodies.R_MOON


func proceed() -> void:
	if program == 63:
		match step_name:
			"tig":
				# Maneuver to thrust against the velocity over the surface at TIG.
				var at := predict(pdi_tig)
				var rel := at.vel() - Bodies.moon_omega().cross(at.pos())
				auto_target = _descent_attitude(-rel, Bodies.moon_fixed(pdi_tig) * guidance_frame)
				desired_q = auto_target
				step_name = "v50n18"
				dsky.show(50, 18, true)
			"v50n18":
				step_name = "maneuver"
				auto_active = true
				dsky.show(6, 18)
			"v99":
				engine_enabled = true
				step_name = "ignition"
				dsky.show(16, 68)
		return
	if program == 68:
		change_program(0)
		return
	super.proceed()


func extra_step() -> void:
	var rod := int(Bus.get_value("ctl.lm.rod", 0))
	var click := rod if rod != 0 and _rod_was == 0 else 0
	_rod_was = rod
	if not program in DESCENT:
		return
	var st := _descent_state()
	var now := _now()
	var dt := now - _guide_get if _guide_get >= 0.0 else 0.0
	_guide_get = now
	if program in DESCENT_BURN and bool(Bus.get_value("lm.dyn.landed", false)) and step_name != "tig":
		_descent_phase(68)
		return
	if click != 0 and program in [64, 65, 66]:
		if program != 66:
			rod_cmd = float(st["vg"].x)
			_descent_phase(66)
		rod_cmd += click * float(SpacecraftData.section("descent_guidance")["rod_click_mps"])
	match program:
		63:
			_p63_step(st, now, dt)
		64:
			var d := SpacecraftData.section("descent_guidance")
			descent_throttle = _throttle_for(_steer_to(_klumpp(d["approach"], st, dt), st))
			if tgo <= float(d["approach"]["tend_s"]):
				_descent_phase(65)
		65:
			_p65_step(st)
		66:
			_p66_step(st)


func _p63_step(st: Dictionary, now: float, dt: float) -> void:
	var d := SpacecraftData.section("descent_guidance")
	match step_name:
		"maneuver":
			if _att_error(auto_target) < deg_to_rad(2.0) and _omega().length() < deg_to_rad(0.2):
				step_name = "wait"
				dsky.show(16, 68)
			if now >= pdi_tig - 5.0:
				step_name = "v99"
				dsky.show(99, 68, true)
		"wait":
			if now >= pdi_tig - 5.0:
				step_name = "v99"
				dsky.show(99, 68, true)
		"ignition":
			if now >= pdi_tig - 1e-6:
				step_name = "braking"
				engine_on = true
				ignition_get = now
				tgo = float(d["braking"]["tgo0_s"])
		"braking":
			var thr := _steer_to(_klumpp(d["braking"], st, dt), st)
			if now - ignition_get < float(d["trim_s"]):
				descent_throttle = float(d["trim_throttle"])
			else:
				descent_throttle = _throttle_for(thr)
			if tgo <= float(d["braking"]["tend_s"]):
				_descent_phase(64)
	# Coast landing points before ignition: TIG-60 s, then TIG-5 s.
	var next := -1.0
	if step_name in ["tig", "v50n18", "maneuver", "wait"]:
		next = pdi_tig - 60.0 if now < pdi_tig - 60.0 else pdi_tig - 5.0
	Bus.set_value(_ch("guid.next_event_get_s"), next)


## The throttle for a guidance command [param thr]: full thrust above the
## throttleable range, which the command otherwise keeps to.
static func _throttle_for(thr: float) -> float:
	var dps := SpacecraftData.section("dps")
	return 1.0 if thr > float(dps["throttle_max"]) else maxf(thr, float(dps["throttle_min"]))


## P65: null the horizontal velocity and descend at a rate that slows to
## p65_rate_final_mps near the surface. The thrust always points up, and
## the LM tilts no more than 20° to stop.
func _p65_step(st: Dictionary) -> void:
	var d := SpacecraftData.section("descent_guidance")
	var vg: Vector3 = st["vg"]
	var up_g := -(st["gg"] as Vector3).x
	var hdot := -maxf(float(d["p65_rate_final_mps"]), minf(float(d["p65_rate_max_mps"]), float(d["p65_rate_gain"]) * _h))
	var ax := clampf((hdot - vg.x) / float(d["vertical_tau_s"]), -0.6 * up_g, up_g)
	var ah := -Vector3(0.0, vg.y, vg.z) / float(d["horizontal_tau_s"])
	var ah_max := (ax + up_g) * tan(deg_to_rad(20.0))
	if ah.length() > ah_max:
		ah = ah.normalized() * ah_max
	var thr := _steer_to(Vector3(ax, ah.y, ah.z), st)
	var dps := SpacecraftData.section("dps")
	descent_throttle = clampf(thr, float(dps["throttle_min"]), float(dps["throttle_max"]))


## P66: the crew flies the attitude; the throttle holds the altitude rate
## the ROD clicks set.
func _p66_step(st: Dictionary) -> void:
	var d := SpacecraftData.section("descent_guidance")
	var vg: Vector3 = st["vg"]
	var gg: Vector3 = st["gg"]
	var ax := (rod_cmd - vg.x) / float(d["vertical_tau_s"])
	var g: Basis = st["g"]
	var cos_tilt := maxf((Basis(_att()) * Vector3.RIGHT).dot(g.x), 0.5)
	var dps := SpacecraftData.section("dps")
	var thr := (ax - gg.x) * _mass() / (float(dps["thrust_n"]) * cos_tilt)
	descent_throttle = clampf(thr, float(dps["throttle_min"]), float(dps["throttle_max"]))


## Enter a later descent program, the engine running on.
func _descent_phase(p: int) -> void:
	program = p
	step_name = ""
	dsky.set_prog(p)
	match p:
		64:
			tgo = float(SpacecraftData.section("descent_guidance")["approach"]["tgo0_s"])
			dsky.show(16, 64)
		65:
			dsky.show(16, 60)
		66:
			auto_active = false
			hold_q = _att()
			dsky.show(16, 60)
		68:
			engine_on = false
			engine_enabled = false
			auto_active = false
			hold_q = _att()
			dsky.show(6, 43, true)


## Where the LM is and how it moves in the guidance frame: "g" its axes in
## ECI, "rg" and "vg" the LM's position and velocity over the turning
## surface relative to the site, "gg" gravity.
func _descent_state() -> Dictionary:
	var mf := Bodies.moon_fixed(_now())
	var g := mf * guidance_frame
	var gi := g.transposed()
	var tr := current_traj()
	var r := tr.pos()
	var rel := tr.vel() - Bodies.moon_omega().cross(r)
	var rg := gi * (r - mf * landing_site)
	var vg := gi * rel
	var rl := r.length()
	_range = r.angle_to(mf * landing_site) * Bodies.R_MOON
	_speed = rel.length()
	_vh = vg.z
	_hdot = vg.x
	_h = rl - Bodies.R_MOON - Dynamics.lm_cm_height(str(Bus.get_value("lm.dyn.config", "lm")))
	var fwd := Basis(_att()) * Vector3.BACK
	_lpd = rad_to_deg(fwd.angle_to(mf * landing_site - r))
	return {"g": g, "rg": rg, "vg": vg, "gg": gi * (-r * (Bodies.MU_MOON / (rl * rl * rl)))}


## One cycle of Klumpp's quadratic guidance to [param target]: the
## acceleration command, in the guidance frame, for a quadratic
## acceleration that meets the target's position, velocity and
## acceleration, with the time to go that meets its downrange jerk.
func _klumpp(target: Dictionary, st: Dictionary, dt: float) -> Vector3:
	var rt := _v3(target["r"])
	var vt := _v3(target["v"])
	var at := _v3(target["a"])
	var rg: Vector3 = st["rg"]
	var vg: Vector3 = st["vg"]
	tgo = solve_tgo(tgo - dt, float(target["jz"]), at.z, vg.z, vt.z, rg.z, rt.z)
	var tau := maxf(tgo, 1.0)
	return at + (rt - rg) * (12.0 / (tau * tau)) - (vt + vg) * (6.0 / tau)


## The time to go that meets the target's downrange jerk [param jz]:
## Newton on jz t³ - 6 atz t² + (6 vz + 18 vtz) t + 24 (rz - rtz) = 0
## from [param guess].
static func solve_tgo(guess: float, jz: float, atz: float, vz: float, vtz: float, rz: float, rtz: float) -> float:
	var t := guess
	for _i in 20:
		var f := jz * t * t * t - 6.0 * atz * t * t + (6.0 * vz + 18.0 * vtz) * t + 24.0 * (rz - rtz)
		var df := 3.0 * jz * t * t - 12.0 * atz * t + (6.0 * vz + 18.0 * vtz)
		if absf(df) < 1e-9:
			break
		var step := f / df
		t -= step
		if absf(step) < 1e-6:
			break
	return t


## Steer the thrust to give the acceleration [param acmd] (guidance frame)
## against gravity. Returns the throttle it needs.
func _steer_to(acmd: Vector3, st: Dictionary) -> float:
	var ath := acmd - (st["gg"] as Vector3)
	var g: Basis = st["g"]
	auto_target = _descent_attitude(g * ath.normalized(), g)
	desired_q = auto_target
	auto_active = true
	return ath.length() * _mass() / float(SpacecraftData.section("dps")["thrust_n"])


## The LM's attitude to thrust along [param u] (ECI): +X along it, +Y along
## the guidance frame's crossrange: windows up while braking, and facing
## downrange, toward the site, once upright.
static func _descent_attitude(u: Vector3, g: Basis) -> Quaternion:
	var x := u.normalized()
	var y := g.y - x * g.y.dot(x)
	if y.length() < 1e-3:
		y = x.cross(g.z)
	y = y.normalized()
	return Basis(x, y, x.cross(y)).orthonormalized().get_rotation_quaternion()


func _mass() -> float:
	return float(Bus.get_value("lm.dyn.mass_kg", SpacecraftData.lm_mass()))


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func noun_values(n: int) -> Variant:
	match n:
		33:
			if program == 63:
				return [pdi_tig, pdi_tig, pdi_tig]
		43:
			var at := Bodies.fixed_to_selenographic(Bodies.moon_fixed(_now()).transposed() * current_traj().pos())
			return [at.x, at.y, maxf(_h, 0.0)]
		60:
			return [_vh, _hdot, _h]
		64:
			return [_lpd, _hdot, _h]
		68:
			return [_range, tgo, _speed]
	return super.noun_values(n)


func snapshot() -> Dictionary:
	var d := super.snapshot()
	var gf := guidance_frame
	d["descent"] = {
		"site": [landing_site.x, landing_site.y, landing_site.z],
		"frame": [gf.x.x, gf.x.y, gf.x.z, gf.y.x, gf.y.y, gf.y.z, gf.z.x, gf.z.y, gf.z.z],
		"pdi_tig": pdi_tig, "tgo": tgo, "throttle": descent_throttle, "rod_cmd": rod_cmd, "guide_get": _guide_get,
	}
	return d


func restore(d: Dictionary) -> void:
	var dd: Dictionary = d.get("descent", {})
	if not dd.is_empty():
		landing_site = _v3(dd["site"])
		var f: Array = dd["frame"]
		guidance_frame = Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8]))
	_restoring = true
	super.restore(d)
	_restoring = false
	if not dd.is_empty():
		pdi_tig = float(dd["pdi_tig"])
		tgo = float(dd["tgo"])
		descent_throttle = float(dd["throttle"])
		rod_cmd = float(dd["rod_cmd"])
		_guide_get = float(dd["guide_get"])
		# The display the restored step shows.
		if program == 63:
			var shows := {"tig": [6, 33, true], "v50n18": [50, 18, true], "maneuver": [6, 18, false], "v99": [99, 68, true]}
			var sh: Array = shows.get(step_name, [16, 68, false])
			dsky.show(sh[0], sh[1], sh[2])
		elif program in DESCENT:
			dsky.set_prog(program)
			dsky.show(6 if program == 68 else 16, {64: 64, 65: 60, 66: 60, 68: 43}[program], program == 68)

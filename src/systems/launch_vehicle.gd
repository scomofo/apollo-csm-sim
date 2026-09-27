## The Saturn V from the pad to parking orbit: the S-IC, the S-II and the
## S-IVB's first burn, flown by the Instrument Unit's boost program
## [published: Saturn V Launch Vehicle Guidance Equations, SA-504 (Boeing
## D5-15706-4, 1967); AS-506's flight evaluation report, MPR-SAT-FE-69-9].
##
## On the pad, held by the holddown arms, until they release (the mission's
## launch block); Dynamics keeps the vehicle turning with the Earth. The
## S-IC's start sequence and its engines' thrust OK come on the clock there
## [simplified: the thrust builds against the arms]. Then the program runs
## on the IU's time bases, as AS-506's did:
## - T1, from the umbilical's disconnect: the yaw away from the tower; at
##   137 m (or T1 13 s) the roll to the flight azimuth and the time-tilt
##   pitch program, in the pitch plane fixed at guidance reference release;
##   the S-IC's centre engine's cutoff on the clock.
## - T2, from that cutoff: the tilt arrest. The outboard engines burn until
##   the S-IC's propellant is gone.
## - T3, from their cutoff: staging, the S-II's start, its aft interstage's
##   and the launch escape tower's jettison; then the iterative guidance
##   mode (Sivb.igm_burns()) onto the parking orbit, the S-II's centre
##   engine's cutoff and the shift to the low mixture ratio on the clock,
##   and the S-II burning until its propellant is gone.
## - T4, from that cutoff: staging and the S-IVB's first burn, until the
##   IU's velocity cutoff on the parking orbit's circular speed (T5), and
##   insertion after it, when the sequencer takes the stack on into the
##   parking orbit.
## The attitude follows the commands at the IU's rate limit; each engine
## runs at its stage's thrust and flow [simplified: no start or shutdown
## transients but ramps at the S-II's and the S-IVB's starts, and no
## engine failures or aborts].
##
## The main display console's launch lights follow the vehicle (_lights()).
##
## Writes: lv.state, lv.stage, lv.held, lv.pad_fixed, lv.thrust_n,
##         lv.dir, lv.q, lv.mass_kg, lv.engines, lv.attached, lv.mach,
##         lv.q_pa, lv.max_q_pa, lv.event.<id> (GET), lv.eng_light_1 to 5,
##         lv.liftoff_light, lv.s2_sep_light
class_name LaunchVehicle
extends Node

signal event_fired(id: String)

## How often the IGM works out the steering, s, as Sivb's.
const CYCLE_S := 1.0
## The height of the vehicle's reference point over the pad, m: the
## ground is the simulator's round Earth.
const PAD_HEIGHT_M := 1.0

## "idle" | "pad" | "flight" | "done"
var state: String = "idle"
## "S-IC", "S-II", "S-IVB", or "" between them.
var stage: String = ""
var mass: float = 0.0
var sic_prop: float = 0.0
var s2_prop: float = 0.0
## The mission's launch block and the insertion the IGM flies to: {"rt",
## "vt", "gamma", "n"} (Sivb.igm_burns()).
var launch: Dictionary = {}
var target: Dictionary = {}
## Each time base's start, GET: "T1" to "T5".
var bases: Dictionary = {}
## Each event's GET.
var events: Dictionary = {}
## The thrust's direction (the vehicle's X axis), ECI, and the command it
## turns toward at the rate limit.
var dir: Vector3 = Vector3.ZERO
var cmd: Vector3 = Vector3.ZERO
## The pitch plane's azimuth, degrees: the roll program turns it from the
## pad's to the flight azimuth.
var roll_az: float = 90.0
## When the tilt began (GET), -1 before.
var tilt_at: float = -1.0
## The pad's local axes at guidance reference release, ECI: up, north,
## east.
var grr_axes: PackedFloat64Array = PackedFloat64Array()
## The pad in the Earth-fixed frame, m.
var pad_fixed: PackedFloat64Array = PackedFloat64Array()
## The S-IVB's burn time the IGM carries between passes, s, and when it
## last passed (GET).
var t_go: float = 150.0
var guided_at: float = -1.0
var thrust: float = 0.0
var engines: int = 0
## The highest dynamic pressure yet, Pa, and when (GET).
var max_q: float = 0.0
var max_q_at: float = -1.0


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## Put the vehicle on the pad for [param p_launch] (the mission's launch
## block), to fly to [param p_target] ({"rt", "vt", "gamma", "n"}).
func arm(p_launch: Dictionary, p_target: Dictionary) -> void:
	launch = p_launch.duplicate(true)
	target = p_target.duplicate(true)
	var d := SpacecraftData.section("saturn_v")
	state = "pad"
	stage = "S-IC"
	mass = float(d["liftoff_kg"])
	sic_prop = float(d["s_ic"]["propellant_kg"])
	s2_prop = float(d["s_ii"]["propellant_kg"])
	bases = {}
	events = {}
	tilt_at = -1.0
	roll_az = float(launch["pad_azimuth_deg"])
	t_go = 150.0
	guided_at = -1.0
	thrust = 0.0
	engines = 0
	max_q = 0.0
	max_q_at = -1.0
	pad_fixed = Bodies.geographic_to_fixed(float(launch["pad_lat_deg"]), float(launch["pad_lon_deg"]),
		Bodies.R_EARTH + PAD_HEIGHT_M)
	var t_grr := float(launch["grr_get_s"])
	var up := _v(Bodies.earth_fixed_to_eci(pad_fixed, t_grr)).normalized()
	var pole := Bodies.earth_omega().normalized()
	var east := pole.cross(up).normalized()
	var north := up.cross(east)
	grr_axes = PackedFloat64Array([up.x, up.y, up.z, north.x, north.y, north.z, east.x, east.y, east.z])
	dir = up
	cmd = up
	_publish()


## The pad's state in ECI at GET [param t], in doubles: [x, y, z, vx, vy,
## vz].
func pad_state(t: float) -> PackedFloat64Array:
	return pad_state_of(pad_fixed, t)


## The state of a point fixed on the Earth at [param fixed] (Earth-fixed,
## m) in ECI at GET [param t], in doubles: it moves with the Earth's
## turning.
static func pad_state_of(fixed: Array, t: float) -> PackedFloat64Array:
	var r := Bodies.earth_fixed_to_eci(fixed, t)
	var w := Bodies.earth_omega()
	return PackedFloat64Array([r[0], r[1], r[2], w.y * r[2] - w.z * r[1], w.z * r[0] - w.x * r[2], w.x * r[1] - w.y * r[0]])


func tick(dt: float) -> void:
	if state == "idle" or state == "done" or str(Bus.get_value("dyn.config", "")) != "saturn_v":
		thrust = 0.0
		engines = 0
		_publish()
		return
	var now := float(Bus.get_value("time.get_s", 0.0))
	if state == "pad":
		if not events.has("ignition") and now >= float(launch["ignition_get_s"]) - 1e-6:
			_fire("ignition", now)
		if not events.has("thrust_ok") and now >= float(launch["thrust_ok_get_s"]) - 1e-6:
			_fire("thrust_ok", now)
		if now < float(launch["release_get_s"]) - 1e-6:
			_publish()
			return
		state = "flight"
		_fire("liftoff", now)
	if not bases.has("T1") and now >= float(launch["t1_get_s"]) - 1e-6:
		bases["T1"] = now
	var st := _state()
	var r := Vector3(st[0], st[1], st[2])
	var v := Vector3(st[3], st[4], st[5])
	_sequence(now, r)
	_air(now, r, v)
	_steer(now, dt)
	var f := _propulsion(now, r, dt)
	# The IU's velocity cutoff: the part of this step that brings the speed
	# to the target's, as Sivb cuts off on the energy.
	if stage == "S-IVB" and f.x > 0.0:
		var dv := f.x / maxf(mass, 1.0) * dt
		var frac := Sivb._cutoff_fraction(st, v.length_squared() / 2.0, float(target["vt"]) * float(target["vt"]) / 2.0,
			dir * dv)
		if v.length() >= float(target["vt"]):
			frac = 0.0
		f *= frac
		if frac < 1.0:
			bases["T5"] = now
			stage = ""
			_fire("s4_cutoff", now)
	thrust = f.x
	mass -= f.y * dt
	var t5 := float(bases.get("T5", INF))
	if now >= t5 + float(launch["insertion_t5_s"]) - 1e-6:
		state = "done"
		_fire("insertion", now)
	_publish()


## The events on the time bases, and the stages' ends.
func _sequence(now: float, r: Vector3) -> void:
	var t1 := float(bases.get("T1", INF))
	if not bases.has("T2") and now >= t1 + float(launch["sic_ceco_t1_s"]) - 1e-6:
		bases["T2"] = now
		_fire("sic_ceco", now)
	if tilt_at < 0.0 and (r.length() - Bodies.R_EARTH - PAD_HEIGHT_M >= float(launch["tilt_altitude_m"])
			or now >= t1 + float(launch["tilt_t1_s"]) - 1e-6):
		tilt_at = now
		_fire("tilt", now)
	var t3_s: Dictionary = launch["t3_s"]
	var t4_s: Dictionary = launch["t4_s"]
	if bases.has("T3"):
		var t3 := float(bases["T3"])
		var d := SpacecraftData.section("saturn_v")
		if not events.has("staging") and now >= t3 + float(t3_s["separation"]) - 1e-6:
			mass = float(d["s_ii"]["start_kg"])
			_fire("staging", now)
		if not events.has("s2_ignition") and now >= t3 + float(t3_s["s2_start"]) - 1e-6:
			stage = "S-II"
			_fire("s2_ignition", now)
		if not events.has("interstage_jettison") and now >= t3 + float(t3_s["aft_interstage"]) - 1e-6:
			mass -= float(d["s_ii"]["aft_interstage_kg"])
			_fire("interstage_jettison", now)
		if not events.has("les_jettison") and now >= t3 + float(t3_s["les"]) - 1e-6:
			mass -= float(d["s_ii"]["les_kg"])
			_fire("les_jettison", now)
		if not events.has("igm") and now >= t3 + float(t3_s["igm"]) - 1e-6:
			_fire("igm", now)
		if not events.has("s2_ceco") and now >= t3 + float(t3_s["s2_ceco"]) - 1e-6:
			_fire("s2_ceco", now)
		if not events.has("emr_shift") and now >= t3 + float(t3_s["emr_shift"]) - 1e-6:
			_fire("emr_shift", now)
	if bases.has("T4"):
		var t4 := float(bases["T4"])
		if not events.has("s2_staging") and now >= t4 + float(t4_s["separation"]) - 1e-6:
			mass = float(SpacecraftData.section("saturn_v")["s_ivb"]["start_kg"])
			_fire("s2_staging", now)
		if not events.has("s4_ignition") and now >= t4 + float(t4_s["s4_ignition"]) - 1e-6:
			stage = "S-IVB"
			_fire("s4_ignition", now)


## The thrust and the flow this step, Vector2(N, kg/s); ends a stage when
## its propellant runs out within the step.
func _propulsion(now: float, r: Vector3, dt: float) -> Vector2:
	var d := SpacecraftData.section("saturn_v")
	match stage:
		"S-IC":
			var c: Dictionary = d["s_ic"]
			engines = int(c["engines"]) - (1 if bases.has("T2") else 0)
			var p := Atmosphere.pressure(r.length() - Bodies.R_EARTH)
			var f1 := float(c["thrust_vac_n"]) - p * float(c["exit_area_m2"])
			var isp := float(c["isp_vac_s"]) - (float(c["isp_vac_s"]) - float(c["isp_sl_s"])) * p / Atmosphere.P0
			var f := f1 * engines
			var md := f / (isp * Units.G0)
			if md * dt >= sic_prop:
				var frac := sic_prop / (md * dt)
				sic_prop = 0.0
				bases["T3"] = now
				stage = ""
				engines = 0
				_fire("sic_oeco", now)
				return Vector2(f, md) * frac
			sic_prop -= md * dt
			return Vector2(f, md)
		"S-II":
			var c: Dictionary = d["s_ii"]
			var t3 := float(bases["T3"])
			var t3_s: Dictionary = launch["t3_s"]
			var k := clampf((now - t3 - float(t3_s["s2_start"])) / (float(t3_s["s2_mainstage"]) - float(t3_s["s2_start"])), 0.0, 1.0)
			var f := float(c["thrust_n"])
			var md := float(c["flow_kg_s"])
			engines = 5
			if events.has("s2_ceco"):
				engines = 4
				f *= 0.8
				md *= 0.8
			if events.has("emr_shift"):
				f = float(c["low_mr_thrust_n"])
				md = float(c["low_mr_flow_kg_s"])
			f *= k
			md *= k
			if md * dt >= s2_prop:
				var frac := s2_prop / (md * dt)
				s2_prop = 0.0
				bases["T4"] = now
				stage = ""
				engines = 0
				_fire("s2_oeco", now)
				return Vector2(f, md) * frac
			s2_prop -= md * dt
			return Vector2(f, md)
		"S-IVB":
			var c: Dictionary = d["s_ivb"]
			var t4 := float(bases["T4"])
			var t4_s: Dictionary = launch["t4_s"]
			var k := clampf((now - t4 - float(t4_s["s4_ignition"])) / (float(t4_s["s4_mainstage"]) - float(t4_s["s4_ignition"])), 0.0, 1.0)
			engines = 1
			return Vector2(float(c["thrust_n"]), float(c["flow_kg_s"])) * k
	engines = 0
	return Vector2.ZERO


## Mach 1 and the maximum dynamic pressure, as the vehicle passes them.
func _air(now: float, r: Vector3, v: Vector3) -> void:
	var h := r.length() - Bodies.R_EARTH
	if h > 100000.0:
		return
	var va := Atmosphere.air_velocity(r, v).length()
	var mach := va / Atmosphere.sound_speed(h)
	var q := 0.5 * Atmosphere.density(h) * va * va
	Bus.set_value("lv.mach", mach)
	Bus.set_value("lv.q_pa", q)
	if not events.has("mach_1") and mach >= 1.0:
		_fire("mach_1", now)
	if not events.has("max_q"):
		if q >= max_q:
			max_q = q
			max_q_at = now
		elif q < 0.98 * max_q:
			events["max_q"] = max_q_at
			Bus.set_value("lv.event.max_q", max_q_at)
			Bus.set_value("lv.max_q_pa", max_q)
			event_fired.emit("max_q")


## The attitude command, and the thrust turned toward it at the rate limit.
func _steer(now: float, dt: float) -> void:
	var a := grr_axes
	var up := Vector3(a[0], a[1], a[2])
	var north := Vector3(a[3], a[4], a[5])
	var east := Vector3(a[6], a[7], a[8])
	var t1 := now - float(bases.get("T1", now))
	var rate := deg_to_rad(float(launch["attitude_rate_dps"]))
	if bases.has("T5"):
		# Cut off: the attitude holds.
		cmd = dir
	elif events.has("igm"):
		if guided_at < 0.0 or now >= guided_at + CYCLE_S - 1e-6:
			guided_at = now
			var burns := _burns(now)
			var last: Dictionary = burns[-1]
			if float(last["t0"]) + float(last["T"]) > Sivb.FREEZE_S or stage != "S-IVB":
				var g := Sivb.igm_burns(_state(), burns, target)
				cmd = g["dir"]
				t_go = float((g["burns"] as Array)[-1]["T"])
			elif stage == "S-IVB":
				t_go = maxf(t_go - CYCLE_S, 0.0)
	elif tilt_at >= 0.0:
		var az := deg_to_rad(float(launch["flight_azimuth_deg"]))
		var down_range := north * cos(az) + east * sin(az)
		var t_ar := float(bases.get("T2", INF)) + float(launch["tilt_arrest_t2_s"])
		var chi := deg_to_rad(_tilt(minf(now, t_ar) - float(bases.get("T1", now))))
		cmd = up * cos(chi) - down_range * sin(chi)
		roll_az = move_toward(roll_az, float(launch["flight_azimuth_deg"]), rad_to_deg(rate) * dt)
	else:
		var yaw: Array = launch["yaw_t1_s"]
		var y := deg_to_rad(float(launch["yaw_deg"])) if t1 >= float(yaw[0]) and t1 < float(yaw[1]) else 0.0
		# Away from the tower, to the south [estimated].
		cmd = up * cos(y) - north * sin(y)
	# The vehicle turns toward the command at the rate limit.
	var ang := dir.angle_to(cmd)
	var step := rate * dt
	if ang <= step or ang < 1e-9:
		dir = cmd
	else:
		var axis := dir.cross(cmd).normalized()
		dir = dir.rotated(axis, step).normalized()


## The time-tilt pitch program: degrees from the launch vertical at
## [param t] T1 seconds, by segment (negative downrange).
func _tilt(t: float) -> float:
	var seg: Array = launch["tilt_segments_s"]
	var polys: Array = launch["tilt_poly"]
	var k := 0
	while k < seg.size() and t >= float(seg[k]):
		k += 1
	var c: Array = polys[k]
	var x := 0.0
	for i in range(c.size() - 1, -1, -1):
		x = x * t + float(c[i])
	return x


## The burns still to come, for the IGM: the S-II's at the high mixture
## ratio on five engines, then four, then at the low ratio until its
## propellant is gone, the coast to the S-IVB's ignition, and the S-IVB's
## burn, whose time the IGM iterates.
func _burns(now: float) -> Array:
	var d := SpacecraftData.section("saturn_v")
	var s2: Dictionary = d["s_ii"]
	var s4: Dictionary = d["s_ivb"]
	var out: Array = []
	var t0 := 0.0
	var m := mass
	if stage == "S-II":
		var t3 := float(bases["T3"])
		var t3_s: Dictionary = launch["t3_s"]
		var left := s2_prop
		var phases := [[t3 + float(t3_s["s2_ceco"]), float(s2["thrust_n"]), float(s2["flow_kg_s"])],
			[t3 + float(t3_s["emr_shift"]), float(s2["thrust_n"]) * 0.8, float(s2["flow_kg_s"]) * 0.8]]
		for ph: Array in phases:
			var end := float(ph[0])
			if now < end and left > 0.0:
				var t := minf(end - now - t0, left / float(ph[2]))
				out.append({"t0": t0, "T": t, "F": float(ph[1]), "mdot": float(ph[2]), "m0": m})
				m -= float(ph[2]) * t
				left -= float(ph[2]) * t
				t0 += t
		if left > 0.0:
			var t := left / float(s2["low_mr_flow_kg_s"])
			out.append({"t0": t0, "T": t, "F": float(s2["low_mr_thrust_n"]), "mdot": float(s2["low_mr_flow_kg_s"]), "m0": m})
			t0 += t
		t0 += float((launch["t4_s"] as Dictionary)["s4_ignition"])
		out.append({"t0": t0, "T": t_go, "F": float(s4["thrust_n"]), "mdot": float(s4["flow_kg_s"]), "m0": float(s4["start_kg"])})
	elif stage == "S-IVB":
		out.append({"t0": 0.0, "T": t_go, "F": float(s4["thrust_n"]), "mdot": float(s4["flow_kg_s"]), "m0": m})
	else:
		var t4 := float(bases.get("T4", now))
		var ign := t4 + float((launch["t4_s"] as Dictionary)["s4_ignition"])
		out.append({"t0": maxf(ign - now, 0.0), "T": t_go, "F": float(s4["thrust_n"]), "mdot": float(s4["flow_kg_s"]),
			"m0": float(s4["start_kg"])})
	return out


func _fire(id: String, now: float) -> void:
	events[id] = now
	Bus.set_value("lv.event." + id, now)
	event_fired.emit(id)


## The vehicle's attitude, ECI from body: X along the thrust, Z down across
## it (the crew heads down, as the stack in orbit), in the pitch plane of
## the roll program's azimuth until the iterative guidance, then in the
## local vertical's plane.
func attitude(r: Vector3) -> Quaternion:
	var x := dir
	var toward := -r.normalized()
	if not events.has("igm"):
		var a := grr_axes
		var az := deg_to_rad(roll_az)
		toward = Vector3(a[3], a[4], a[5]) * cos(az) + Vector3(a[6], a[7], a[8]) * sin(az)
	var z := toward - x * toward.dot(x)
	if z.length() < 1e-6:
		z = x.cross(Vector3(0, 0, 1)).cross(x)
	z = z.normalized()
	return Basis(x, z.cross(x), z).orthonormalized().get_rotation_quaternion()


func _state() -> PackedFloat64Array:
	var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH, 0.0, 0.0])
	var v: Array = Bus.get_value("dyn.v_mps", [0.0, 0.0, 0.0])
	return PackedFloat64Array([r[0], r[1], r[2], v[0], v[1], v[2]])


static func _v(a: PackedFloat64Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func _publish() -> void:
	Bus.set_value("lv.state", state)
	Bus.set_value("lv.stage", stage)
	Bus.set_value("lv.held", state == "pad")
	Bus.set_value("lv.pad_fixed", Array(pad_fixed))
	Bus.set_value("lv.thrust_n", thrust)
	Bus.set_value("lv.dir", [dir.x, dir.y, dir.z])
	Bus.set_value("lv.mass_kg", mass)
	Bus.set_value("lv.engines", engines)
	# Still on the vehicle: the S-IC, the S-II, the launch escape tower.
	var on := state == "pad" or state == "flight"
	Bus.set_value("lv.attached", [on and not events.has("staging"), on and not events.has("s2_staging"),
		on and not events.has("les_jettison")])
	if state != "idle":
		var r: Array = Bus.get_value("dyn.r_m", [Bodies.R_EARTH, 0.0, 0.0])
		var q := attitude(Vector3(r[0], r[1], r[2]))
		Bus.set_value("lv.q", [q.x, q.y, q.z, q.w])
	var lights := _lights()
	for i in 5:
		Bus.set_value("lv.eng_light_%d" % (i + 1), lights[i])
	Bus.set_value("lv.liftoff_light", lights[5])
	Bus.set_value("lv.s2_sep_light", lights[6])


## The main display console's launch lights now [estimated: the Apollo
## Operations Handbook's account of them, not their circuits]: the LV
## ENGINE lights 1 to 5, the LIFTOFF light and the S-II SEP light. An
## engine's light is lit while that engine, on the stage burning or next to
## burn, is below thrust: on the pad until the S-IC's thrust OK, the centre
## engine's after its cutoff, all five from a stage's cutoff until its
## separation, and again from the next stage's start until its mainstage
## (the S-IVB's one engine on light 1). LIFTOFF is lit from the liftoff to
## the S-IC's separation, S-II SEP from then until the S-II's aft
## interstage falls away. All go out at insertion, when the stack flies on
## [simplified].
func _lights() -> Array:
	var on := state == "pad" or state == "flight"
	var eng := [false, false, false, false, false]
	if on:
		var now := float(Bus.get_value("time.get_s", 0.0))
		var t3_s: Dictionary = launch["t3_s"]
		var t4_s: Dictionary = launch["t4_s"]
		var all := false
		match stage:
			"S-IC":
				all = not events.has("thrust_ok")
				eng[4] = bases.has("T2")
			"S-II":
				all = now < float(bases["T3"]) + float(t3_s["s2_mainstage"]) - 1e-6
				eng[4] = events.has("s2_ceco")
			"S-IVB":
				eng[0] = now < float(bases["T4"]) + float(t4_s["s4_mainstage"]) - 1e-6
			_:
				# Between a cutoff and the next stage's start.
				if bases.has("T5"):
					eng[0] = true
				elif bases.has("T4"):
					all = not events.has("s2_staging")
				elif bases.has("T3"):
					all = not events.has("staging")
		if all:
			eng = [true, true, true, true, true]
	var liftoff := on and events.has("liftoff") and not events.has("staging")
	var s2_sep := on and events.has("staging") and not events.has("interstage_jettison")
	return eng + [liftoff, s2_sep]


func snapshot() -> Dictionary:
	return {"state": state, "stage": stage, "mass": mass, "sic_prop": sic_prop, "s2_prop": s2_prop,
		"launch": launch, "target": target, "bases": bases.duplicate(), "events": events.duplicate(),
		"dir": [dir.x, dir.y, dir.z], "cmd": [cmd.x, cmd.y, cmd.z], "roll_az": roll_az, "tilt_at": tilt_at,
		"grr_axes": Array(grr_axes), "pad_fixed": Array(pad_fixed), "t_go": t_go, "guided_at": guided_at,
		"thrust": thrust, "engines": engines, "max_q": max_q, "max_q_at": max_q_at}


func restore(d: Dictionary) -> void:
	state = str(d.get("state", "idle"))
	stage = str(d.get("stage", ""))
	mass = float(d.get("mass", 0.0))
	sic_prop = float(d.get("sic_prop", 0.0))
	s2_prop = float(d.get("s2_prop", 0.0))
	launch = (d.get("launch", {}) as Dictionary).duplicate(true)
	target = (d.get("target", {}) as Dictionary).duplicate(true)
	bases = (d.get("bases", {}) as Dictionary).duplicate()
	events = (d.get("events", {}) as Dictionary).duplicate()
	var a: Array = d.get("dir", [0.0, 0.0, 0.0])
	dir = Vector3(a[0], a[1], a[2])
	a = d.get("cmd", [0.0, 0.0, 0.0])
	cmd = Vector3(a[0], a[1], a[2])
	roll_az = float(d.get("roll_az", 90.0))
	tilt_at = float(d.get("tilt_at", -1.0))
	grr_axes = PackedFloat64Array(d.get("grr_axes", []))
	pad_fixed = PackedFloat64Array(d.get("pad_fixed", []))
	t_go = float(d.get("t_go", 150.0))
	guided_at = float(d.get("guided_at", -1.0))
	thrust = float(d.get("thrust", 0.0))
	engines = int(d.get("engines", 0))
	max_q = float(d.get("max_q", 0.0))
	max_q_at = float(d.get("max_q_at", -1.0))
	_publish()

## The CSM's probe and the LM's drogue as geometry: where the two docking
## ports are relative to each other, and whether a contact between them is
## within the capture limits in data/spacecraft.json ("docking"). Dynamics
## owns both vehicles and acts on the answers: it splits the stack at
## undocking, joins it at capture, and makes the vehicles rebound from a
## contact without capture (docs/ROADMAP.md, slice 3a).
##
## The probe is on the CSM's +X axis, csm_port_m from its centre of mass,
## and the drogue on the LM's +X (up) axis, lm_port_m from its centre of
## mass (lm_ascent_port_m from the ascent stage's, after staging). Docked,
## the LM's +X points back along the CSM's -X [estimated].
## Capture latches the vehicles hard docked at once [simplified: no soft
## dock], and only the probe can meet the LM [simplified: no collisions
## between the vehicles' bodies]. At transposition and docking the LM is
## still in the S-IVB's adapter (configuration lm_sivb, its drogue
## tde_port_m from their centre of mass). With the capture latches failed
## (Apollo 14's, slice 12a) no contact captures: the probe held in the
## drogue under +X and retracted pulls the rings together to hard dock.
class_name Docking
extends RefCounted

## The docked LM's attitude relative to the CSM's (LM body axes to CSM
## body axes): half a turn about +Z [estimated].
const LM_IN_CSM := Quaternion(0.0, 0.0, 1.0, 0.0)


static func params() -> Dictionary:
	return SpacecraftData.section("docking")


## The docked LM's gimbal angles (outer, inner, middle; deg) for a platform
## lying where the CSM's does, from the CSM's ICDU angles [param cm_deg]:
## the docked alignment's coarse align (V41N20 in the LGC), through the
## docking geometry (LM_IN_CSM). Apollo 13's crew worked them out by hand
## from Odyssey's N20 with the docking ring's roll calibration: 300 deg less
## the CM's outer, plus the calibration; its inner plus 180; its middle's
## negative (the Apollo Flight Journal, 058:03-058:04) [published]; the LM
## here docks at its nominal index, 180 deg about Z [estimated].
static func lm_gimbals(cm_deg: Vector3) -> Vector3:
	return Imu.gimbal_angles(Imu.gimbal_basis(cm_deg) * Basis(LM_IN_CSM))


## The LM's docking port's distance from its centre of mass along +X, m,
## for its configuration [param cfg] ("lm", "lm_ascent", or "lm_sivb" in
## the S-IVB's adapter, from theirs).
static func lm_port_m(cfg: String) -> float:
	match cfg:
		"lm_ascent":
			return float(params()["lm_ascent_port_m"])
		"lm_sivb":
			return float(params()["tde_port_m"])
	return float(params()["lm_port_m"])


## [param b]'s state relative to [param a]'s, [x, y, z, vx, vy, vz] in
## inertial axes (m, m/s), whichever bodies they are relative to.
static func relative_state(a: Trajectory, b: Trajectory) -> PackedFloat64Array:
	var sa := a.s if a.primary == b.primary else a.earth_state()
	var sb := b.s if a.primary == b.primary else b.earth_state()
	var out := PackedFloat64Array()
	out.resize(6)
	for i in 6:
		out[i] = sb[i] - sa[i]
	return out


## Where the LM's port is relative to the CSM's, inertial axes:
##   d, u           the LM port's position (m) and velocity (m/s) relative
##                  to the CSM port, each port moving with its vehicle
##   n              the LM's docking axis, out of its port
##   range          |d|, m
##   axial          the probe tip's height above the drogue's face, along
##                  n, m: positive in front of the LM
##   lateral        the probe tip's offset in the drogue's face, m (Vector3)
##   closing        the probe's speed into the drogue, m/s
##   lateral_speed  its speed across the drogue's face, m/s
##   misalign_deg   angle between the CSM's +X and the LM's -X
##   rate_dps       the vehicles' relative angular rate, °/s
static func relative(csm_traj: Trajectory, csm_att: Attitude, lm: Vehicle) -> Dictionary:
	var p := params()
	var rel := relative_state(csm_traj, lm.traj)
	var rc := csm_att.eci_from_body()
	var rl := lm.attitude.eci_from_body()
	var arm_c := rc * Vector3(float(p["csm_port_m"]), 0.0, 0.0)
	var arm_l := rl * Vector3(lm_port_m(lm.config), 0.0, 0.0)
	var wc := rc * csm_att.omega
	var wl := rl * lm.attitude.omega
	var d := Vector3(rel[0], rel[1], rel[2]) + arm_l - arm_c
	var u := Vector3(rel[3], rel[4], rel[5]) + wl.cross(arm_l) - wc.cross(arm_c)
	var n := rl * Vector3.RIGHT
	var axial := -d.dot(n)
	var across := -u - n * (-u.dot(n))
	return {
		"d": d, "u": u, "n": n, "range": d.length(),
		"axial": axial, "lateral": -d - n * axial,
		"closing": u.dot(n), "lateral_speed": across.length(),
		"misalign_deg": rad_to_deg((rc * Vector3.RIGHT).angle_to(-n)),
		"rate_dps": rad_to_deg((wc - wl).length()),
	}


## A contact of the probe with the drogue, from geometry [param g] and
## the probe's [param miss_m] from the drogue's centre, SI:
##   captured, fault   whether it captures; if not, the first limit it broke:
##                     closing, across, miss, misaligned or turning, or
##                     latches, within them with [param latches_failed]
##   closing_mps, lateral_speed_mps, miss_m, misalign_deg, rate_dps
## Dynamics adds get_s (its GET) and tde (the target the LM on the S-IVB),
## and reports the probe's retraction to hard dock as a capture with
## retract.
static func contact(g: Dictionary, miss_m: float, latches_failed: bool = false) -> Dictionary:
	var p := params()
	var fault := ""
	if float(g["closing"]) > float(p["closing_max_mps"]):
		fault = "closing"
	elif float(g["lateral_speed"]) > float(p["lateral_speed_max_mps"]):
		fault = "across"
	elif miss_m > float(p["lateral_miss_max_m"]):
		fault = "miss"
	elif float(g["misalign_deg"]) > float(p["misalign_max_deg"]):
		fault = "misaligned"
	elif float(g["rate_dps"]) > float(p["rate_max_dps"]):
		fault = "turning"
	elif latches_failed:
		fault = "latches"
	return {
		"captured": fault == "", "fault": fault,
		"closing_mps": g["closing"], "lateral_speed_mps": g["lateral_speed"], "miss_m": miss_m,
		"misalign_deg": g["misalign_deg"], "rate_dps": g["rate_dps"],
	}


## [param c] (see contact()) in words, feet and ft/s as the crew had them.
static func describe(c: Dictionary) -> String:
	if c.is_empty():
		return ""
	if bool(c.get("retract", false)):
		return "hard dock: the probe retracted, the ring latches fired"
	var closing := float(c["closing_mps"]) / Units.FT
	if bool(c["captured"]):
		return "capture at %.2f ft/s, %.1f ft off centre" % [closing, float(c["miss_m"]) / Units.FT]
	match str(c["fault"]):
		"closing":
			return "no capture: closing at %.2f ft/s" % closing
		"across":
			return "no capture: moving across at %.2f ft/s" % (float(c["lateral_speed_mps"]) / Units.FT)
		"miss":
			return "no capture: %.1f ft off centre" % (float(c["miss_m"]) / Units.FT)
		"misaligned":
			return "no capture: %.0f° out of line" % float(c["misalign_deg"])
		"latches":
			return "no capture: the capture latches didn't engage, at %.2f ft/s" % closing
		_:
			return "no capture: turning at %.1f°/s" % float(c["rate_dps"])

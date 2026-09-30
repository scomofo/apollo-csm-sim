## The LGC's AGS initialization, R47 (slice 11e), as Luminary 099's
## [published: AGS_INITIALIZATION.agc, pages 206 to 210]: V47 sends the
## AGS's Abort Electronics Assembly the LM's and the CSM's state vectors
## over the downlink. It checks REFSMFLG (alarm 00220 without it), then
## flashes V06N16, the GET of the AEA clock's zero (AGSK): PRO keeps it, V32
## makes the V32's ENTER the new zero (as the crew keyed it with the DEDA's
## 377 entry), V34 ends. Sending, it extrapolates both state vectors to the
## present, turns them into stable member coordinates by REFSMMAT, in feet
## and feet per second, and times them from AGSK, and holds them on the
## AGS downlist for 20 s (V06N16), in which the crew's 414+10000 on the DEDA
## takes them; then V50N16 until PRO [simplified: the ICDU and AEA gimbal
## angle counters' zeroing after the downlist is left out, and a new AGSK
## is set by V32 only, not V25].
class_name LgcR47
extends RefCounted

## The downlist's time on the AGS's list, s.
const SEND_S := 20.0

var lgc: Object
## The GET of the AEA clock's zero, s.
var agsk: float = 0.0
## "" off, "k" (V06N16 flashing, the zero), "send" (the downlist, V06N16),
## "done" (V50N16); on the Bus as lm.guid.r47.
var phase: String = "":
	set(p):
		phase = p
		Bus.set_value("lm.guid.r47", p)
var send_until: float = 0.0
## The program's display R47 covers.
var covered: Dictionary = {}


## V47E: R47 starts, or alarm 00220 without REFSMFLG. Returns true.
func start() -> bool:
	if not lgc.imu.aligned:
		lgc._alarm(220)
		return true
	if phase == "":
		covered = lgc.dsky.program_display().duplicate()
	phase = "k"
	lgc.dsky.show(6, 16, true)
	return true


## The crew's answer: "pro", "v32" or "v34". Returns whether R47 took it.
func answer(key: String) -> bool:
	if phase == "":
		return false
	match key:
		"v34":
			stop()
		"v32":
			if phase == "k":
				agsk = lgc._now()
				lgc.dsky.show(6, 16, true)
		"pro":
			if phase == "k":
				_send()
			elif phase == "done":
				stop()
	return true


## The state vectors onto the AGS downlist.
func _send() -> void:
	var now: float = lgc._now()
	var lm: Trajectory = lgc.current_traj()
	var csm: Trajectory = lgc._csm_now()
	if lm == null or csm == null:
		stop()
		return
	lm = lm.clone()
	lm.coast_to(now)
	csm = csm.clone()
	csm.coast_to(now)
	var m: Basis = lgc.imu.refsmmat
	Bus.set_value("lm.lgc.ags_downlink", {"until": now + SEND_S, "t": now - agsk,
		"lm_r": _sm(m, lm.s, 0, 1.0 / Units.FT), "lm_v": _sm(m, lm.s, 3, 1.0 / Units.FT),
		"csm_r": _sm(m, csm.s, 0, 1.0 / Units.FT), "csm_v": _sm(m, csm.s, 3, 1.0 / Units.FT)})
	phase = "send"
	send_until = now + SEND_S
	lgc.dsky.show(6, 16, false)


## State [param s]'s vector from [param i], in stable member axes (the
## rows of [param m]) and scaled by [param k], in doubles.
static func _sm(m: Basis, s: PackedFloat64Array, i: int, k: float) -> Array:
	var out := []
	var t := m.transposed()
	for row in [t.x, t.y, t.z]:
		out.append((float(row.x) * s[i] + float(row.y) * s[i + 1] + float(row.z) * s[i + 2]) * k)
	return out


## The downlist's 20 s over: V50N16 until PRO.
func tick(now: float) -> void:
	if phase == "send" and now >= send_until:
		phase = "done"
		lgc.dsky.show(50, 16, true)


func stop() -> void:
	if phase == "":
		return
	phase = ""
	if not covered.is_empty():
		lgc.dsky.show(int(covered["v"]), int(covered["n"]), bool(covered["flash"]))
	else:
		lgc.dsky.blank()
	covered = {}


func snapshot() -> Dictionary:
	return {"agsk": agsk, "phase": phase, "send_until": send_until, "covered": covered}


func restore(d: Dictionary) -> void:
	agsk = float(d.get("agsk", 0.0))
	phase = str(d.get("phase", ""))
	send_until = float(d.get("send_until", 0.0))
	covered = d.get("covered", {})


## The display back up over the program's after the LGC's restore.
func show_display() -> void:
	match phase:
		"k":
			lgc.dsky.show(6, 16, true)
		"send":
			lgc.dsky.show(6, 16, false)
		"done":
			lgc.dsky.show(50, 16, true)

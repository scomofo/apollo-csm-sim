## Evidence recorder for the headset run (docs/VR_ACCEPTANCE.md, slice 2e).
## It watches the Bus while the tester works through docs/HEADSET_RUN.md.
## When the XR session stops or the window closes, it writes a JSON record
## to user://vr_acceptance/, plus a copy of the acceptance tables with the
## objective rows' evidence filled in. A later stop or the close rewrites
## the same files, so a session the runtime stops and restarts (a headset
## taken off) still leaves one record of the whole run. Evidence is not a
## verdict: the tester fills the Pass column.
## Adapted from gemini-capsule's src/presentation/vr_acceptance_recorder.gd
## at 40e449c (README.md lists the port). Apollo's objective rows are a
## panel switch, a DSKY verb and noun and a wrist-menu button worked by
## fingertip; the rotation controller on the thumbsticks; the vignette,
## the horizon aid's default and the time-rate lock. They replace Gemini's
## ACE POWER and RATE CMD rows. Eagle's rows, from a second run aboard the
## LM, take the recentres made there, a verb and noun typed on the LGC's
## DSKY and the touches on its switches. R5's, at the lower equipment bay,
## take the seat, how far the right stick turned the optics and the
## touches on MARK. The seated reference space is 0 (Local) here.
## Presentation only: it writes nothing to the Bus.
##
## Reads:  player.*, ctl.rhc, dyn.omega, dsky.verb, dsky.noun,
##         lm.dsky.verb, lm.dsky.noun, optics.mode, optics.shaft_deg,
##         optics.trunnion_deg, present.comfort.vignette,
##         present.comfort.horizon, present.menu.visible, perf.*
class_name VrAcceptanceRecorder
extends Node

const OUT_DIR := "user://vr_acceptance"
## Frames slower than this multiple of the headset frame budget count as dropped.
const DROP_FACTOR := 1.5
## Godot 4.4.1's seated reference space, Local.
const LOCAL_SPACE := 0
## How the record spells DSKY keys; digits stand for themselves.
const DSKY_LETTERS := {"VERB": "V", "NOUN": "N", "ENTR": "E", "PRO": "P", "CLR": "C",
	"KEY REL": "K", "RSET": "R", "+": "+", "-": "-"}
const TOUCH_LOG := 80

var rig: Node3D
var xr_interface: XRInterface
var out_dir: String = OUT_DIR
## Write the record when the window closes: main turns it on in a headset.
var write_on_exit: bool = false

var record := {
	"format_version": 1,
	"started_utc": "",
	"godot": Engine.get_version_info().get("string", ""),
	"rig": "",
	"reference_space": -1,
	"session_begun_after_s": -1.0,
	"focus_seen": false,
	"refresh_hz": 0.0,
	"recenters": [],
	"origin_moves_outside_recenter": 0,
	"seats": [],
	"touch": {"count": 0, "channels": {}, "labels": []},
	"switch_by_touch": {"channel": "", "label": "", "at_s": -1.0},
	"dsky_by_touch": {"typed": "", "verb": "", "noun": "", "at_s": -1.0, "shown": false},
	"lgc_dsky_by_touch": {"typed": "", "verb": "", "noun": "", "at_s": -1.0, "shown": false},
	"menu_by_touch": {"label": "", "at_s": -1.0},
	"sticks": {"max_pitch": 0.0, "max_pitch_rate_deg_s": 0.0, "max_roll": 0.0, "max_roll_rate_deg_s": 0.0,
		"locked_seen": false, "max_while_locked": 0.0},
	"optics": {"manual_travel_deg": 0.0},
	"comfort": {"horizon_at_start": null, "max_vignette": 0.0},
	"frames": {"count": 0, "dropped": 0, "worst_ms": 0.0, "budget_ms": 0.0},
	"clean_stop": false,
	"session_stops": 0,
	"close_requested": false,
	"menu_opened": false,
	"written_utc": "",
}

var _t0_ms := 0
var _last_origin := Vector3.INF
var _ignore_origin_until_ms := 0
var _typed := ""
var _menu_labels := {}
var _optics_was := Vector2.INF
## The written files' path without the extension, set by the first write.
var _base := ""


func _ready() -> void:
	_t0_ms = Time.get_ticks_msec()
	record["started_utc"] = Time.get_datetime_string_from_system(true)
	record["reference_space"] = int(ProjectSettings.get_setting("xr/openxr/reference_space", -1))
	for b in WristMenu.BUTTONS:
		_menu_labels[b[1]] = true
	for pad in WristMenu.PADS["lm"]:
		_menu_labels[pad[1]] = true
	Bus.subscribe("player.rig", func(v: Variant) -> void: record["rig"] = str(v))
	Bus.subscribe("player.xr_session", _on_session)
	Bus.subscribe("player.xr_focus", func(v: Variant) -> void:
		if bool(v):
			record["focus_seen"] = true)
	Bus.subscribe("player.xr_refresh_hz", func(v: Variant) -> void: record["refresh_hz"] = float(v))
	Bus.subscribe("player.recenter_count", _on_recenter)
	Bus.subscribe("player.seat", _on_seat)
	Bus.subscribe("player.touch_actuations", _on_touch)
	Bus.subscribe("present.menu.visible", func(v: Variant) -> void:
		if bool(v):
			record["menu_opened"] = true)
	Bus.subscribe("present.comfort.horizon", func(v: Variant) -> void:
		if record["comfort"]["horizon_at_start"] == null:
			record["comfort"]["horizon_at_start"] = bool(v))
	if xr_interface:
		# The recorder lives for the whole app run (created once in main.gd),
		# so this relies on Godot 4's automatic signal disconnect when the
		# node is freed at exit; no _exit_tree disconnect needed.
		xr_interface.session_stopping.connect(_on_session_stopping)


func _elapsed_s() -> float:
	return float(Time.get_ticks_msec() - _t0_ms) / 1000.0


func _on_session(up: Variant) -> void:
	if bool(up) and float(record["session_begun_after_s"]) < 0.0:
		record["session_begun_after_s"] = _elapsed_s()


func _on_seat(seat: Variant) -> void:
	if not str(seat) in record["seats"]:
		record["seats"].append(str(seat))


## S3: right after a recenter the tracked head must sit on the seat's eye,
## raised by the calibrated eye height. The raw offset is kept apart from
## the calibration error.
func _on_recenter(count: Variant) -> void:
	var residual := -1.0
	var head_offset := -1.0
	var target_height := 0.0
	if rig:
		target_height = float(rig.get("height_offset"))
		var cam: Node3D = rig.get_node_or_null("XRCamera3D")
		if cam == null:
			cam = rig.get_node_or_null("Camera3D")
		if cam:
			var actual: Vector3 = rig.transform * cam.position
			head_offset = actual.length()
			residual = actual.distance_to(Vector3(0.0, target_height, 0.0))
		_last_origin = rig.position
	_ignore_origin_until_ms = Time.get_ticks_msec() + 500
	record["recenters"].append({"n": int(count), "at_s": _elapsed_s(), "head_offset_m": head_offset,
		"target_height_m": target_height, "residual_m": residual,
		"vehicle": str(Bus.get_value("player.vehicle", "csm"))})


## A1, A2, A7, E2 to E4: what a fingertip crossing actuated. ControlBase
## names the control and its channel before it counts the crossing.
func _on_touch(_count: Variant) -> void:
	var label := str(Bus.get_value("player.last_touch_label", ""))
	var channel := str(Bus.get_value("player.last_touch_channel", ""))
	var t: Dictionary = record["touch"]
	t["count"] = int(t["count"]) + 1
	if channel != "":
		t["channels"][channel] = int(t["channels"].get(channel, 0)) + 1
	t["labels"].append(label)
	while t["labels"].size() > TOUCH_LOG:
		t["labels"].remove_at(0)
	if channel.begins_with("ctl.") and float(record["switch_by_touch"]["at_s"]) < 0.0:
		record["switch_by_touch"] = {"channel": channel, "label": label, "at_s": _elapsed_s()}
	if _menu_labels.has(label) and float(record["menu_by_touch"]["at_s"]) < 0.0:
		record["menu_by_touch"] = {"label": label, "at_s": _elapsed_s()}
	if channel == "" and (DSKY_LETTERS.has(label) or (label.length() == 1 and label.is_valid_int())):
		_typed = (_typed + str(DSKY_LETTERS.get(label, label))).right(24)
		var re := RegEx.create_from_string("V(\\d\\d)N(\\d\\d)E$")
		var m := re.search(_typed)
		# The CMC's DSKY, or aboard Eagle the LGC's.
		var key := "lgc_dsky_by_touch" if str(Bus.get_value("player.vehicle", "csm")) == "lm" else "dsky_by_touch"
		if m and float(record[key]["at_s"]) < 0.0:
			record[key] = {"typed": m.get_string(0), "verb": m.get_string(1), "noun": m.get_string(2),
				"at_s": _elapsed_s(), "shown": false}


func _process(delta: float) -> void:
	# A2, E3: the CMC, and the LGC, took the verb and noun typed by
	# fingertip.
	_check_shown(record["dsky_by_touch"], "dsky")
	_check_shown(record["lgc_dsky_by_touch"], "lm.dsky")
	# A3, A4, C4: the thumbsticks on the rotation controller, and the lock.
	var rhc: Vector3 = Bus.get_value("ctl.rhc", Vector3.ZERO)
	var omega: Vector3 = Bus.get_value("dyn.omega", Vector3.ZERO)
	var s: Dictionary = record["sticks"]
	if SimClock.controls_locked():
		s["locked_seen"] = true
		s["max_while_locked"] = maxf(s["max_while_locked"], rhc.length())
	else:
		s["max_pitch"] = maxf(s["max_pitch"], absf(rhc.y))
		s["max_roll"] = maxf(s["max_roll"], absf(rhc.x))
		s["max_pitch_rate_deg_s"] = maxf(s["max_pitch_rate_deg_s"], absf(rad_to_deg(omega.y)))
		s["max_roll_rate_deg_s"] = maxf(s["max_roll_rate_deg_s"], absf(rad_to_deg(omega.x)))
	record["comfort"]["max_vignette"] = maxf(record["comfort"]["max_vignette"], float(Bus.get_value("present.comfort.vignette", 0.0)))
	# R5: the optics turned by hand (OPTICS MODE at MAN, the right stick).
	var optics := Vector2(float(Bus.get_value("optics.shaft_deg", 0.0)), float(Bus.get_value("optics.trunnion_deg", 0.0)))
	if str(Bus.get_value("optics.mode", "")) == "manual" and _optics_was != Vector2.INF:
		var turned := Vector2(absf(wrapf(optics.x - _optics_was.x, -180.0, 180.0)), absf(optics.y - _optics_was.y))
		record["optics"]["manual_travel_deg"] = float(record["optics"]["manual_travel_deg"]) + turned.x + turned.y
	_optics_was = optics
	# A4, S4: the origin moves only on a recenter.
	if rig and Time.get_ticks_msec() > _ignore_origin_until_ms:
		if _last_origin != Vector3.INF and rig.position.distance_to(_last_origin) > 0.01:
			record["origin_moves_outside_recenter"] = int(record["origin_moves_outside_recenter"]) + 1
		_last_origin = rig.position
	# Frame pacing against the headset refresh.
	var hz := float(record["refresh_hz"])
	var budget_ms := 1000.0 / hz if hz > 0.0 else 11.1
	var fr: Dictionary = record["frames"]
	fr["budget_ms"] = budget_ms
	fr["count"] = int(fr["count"]) + 1
	var ms := delta * 1000.0
	fr["worst_ms"] = maxf(fr["worst_ms"], ms)
	if ms > budget_ms * DROP_FACTOR:
		fr["dropped"] = int(fr["dropped"]) + 1


## Whether the DSKY publishing on [param prefix] shows the verb and noun
## typed in [param d].
func _check_shown(d: Dictionary, prefix: String) -> void:
	if float(d["at_s"]) >= 0.0 and not bool(d["shown"]):
		d["shown"] = str(Bus.get_value(prefix + ".verb", "")) == d["verb"] and str(Bus.get_value(prefix + ".noun", "")) == d["noun"]


func _on_session_stopping() -> void:
	record["clean_stop"] = true
	record["session_stops"] = int(record["session_stops"]) + 1
	write()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and write_on_exit:
		record["clean_stop"] = true
		record["close_requested"] = true
		write()


## Write the JSON record and the pre-filled tables; returns the path they
## share without the extension. The first write names the files, and later
## ones rewrite them with the record so far.
func write() -> String:
	record["written_utc"] = Time.get_datetime_string_from_system(true)
	if _base == "":
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
		var stamp: String = str(record["written_utc"]).replace(":", "-").replace("T", "_")
		_base = "%s/%s" % [out_dir, stamp]
	var f := FileAccess.open(_base + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(record, "  "))
		f.close()
	var m := FileAccess.open(_base + ".md", FileAccess.WRITE)
	if m:
		m.store_string(markdown())
		m.close()
	print("VrAcceptanceRecorder: wrote %s.{json,md}" % ProjectSettings.globalize_path(_base))
	return _base


static func _yn(ok: bool) -> String:
	return "evidence: pass" if ok else "evidence: FAIL"


## The docs/VR_ACCEPTANCE.md tables with the evidence column filled in.
func markdown() -> String:
	var r := record
	var rec: Array = r["recenters"]
	var last_res := -1.0
	if rec.size() > 0:
		last_res = float(rec[rec.size() - 1]["residual_m"])
	var fr: Dictionary = r["frames"]
	var drop_pct := 100.0 * float(fr["dropped"]) / maxf(1.0, float(fr["count"]))
	var s: Dictionary = r["sticks"]
	var sw: Dictionary = r["switch_by_touch"]
	var dk: Dictionary = r["dsky_by_touch"]
	var mn: Dictionary = r["menu_by_touch"]
	var touch: Dictionary = r["touch"]
	var ch: Dictionary = touch["channels"]
	var horizon_start = r["comfort"]["horizon_at_start"]
	var lines := PackedStringArray()
	lines.append("Headset run %s, Godot %s, rig `%s`, refresh %.0f Hz" % [r["started_utc"], r["godot"], r["rig"], r["refresh_hz"]])
	lines.append("")
	lines.append("Commit/build: ______; headset/controllers: ______; OpenXR runtime: ______")
	lines.append("")
	lines.append("## Session")
	lines.append("| # | Check | Pass? | Notes |")
	lines.append("|---|---|---|---|")
	lines.append("| S1 | OpenXR runtime detected; `--xr-mode on` starts the XR rig in the cabin | | %s (`player.rig` = %s) |" % [_yn(r["rig"] == "xr"), r["rig"]])
	lines.append("| S2 | Session start, no black eye or stuck overlay | | %s: session up after %.1f s, focus %s; the black-eye check is the tester's |" % [
		_yn(float(r["session_begun_after_s"]) >= 0.0 and bool(r["focus_seen"])), r["session_begun_after_s"], "seen" if r["focus_seen"] else "never seen"])
	lines.append("| S3 | Recentre puts the head on the seat's eye, at the calibrated height, without moving the cabin | | %s: %d recentres, calibration residual %.3f m |" % [
		_yn(rec.size() > 0 and last_res >= 0.0 and last_res < 0.02), rec.size(), last_res])
	lines.append("| S4 | Tracking origin stays seated (Local) | | %s: reference_space %d (0 = Local), origin moved outside a recentre %d times |" % [
		_yn(int(r["reference_space"]) == LOCAL_SPACE and int(r["origin_moves_outside_recenter"]) == 0), r["reference_space"], r["origin_moves_outside_recenter"]])
	lines.append("| S5 | Clean session end and headset removal | | %s: %d session stops, window %s |" % [_yn(bool(r["clean_stop"])),
		int(r["session_stops"]), "closed" if r["close_requested"] else "not closed"])
	lines.append("| S6 | Wrist menu opens on the left Menu button or the palm; HIDE holds while the palm faces you | | %s: menu %s during the session; which input opened it is the tester's note |" % [
		_yn(bool(r["menu_opened"])), "opened" if r["menu_opened"] else "never opened"])
	lines.append("")
	lines.append("## Reach and cabin")
	lines.append("| # | Check | Pass? | Notes |")
	lines.append("|---|---|---|---|")
	lines.append("| R1 | From the commander's couch, every MDC1 control is in fingertip reach | | tester |")
	lines.append("| R2 | From the centre couch (SEAT), the DSKY is in fingertip reach | | tester; seats used: %s |" % ", ".join(PackedStringArray(r["seats"])))
	lines.append("| R3 | Windows sit where the eyes expect them; nothing clips the headset | | tester |")
	lines.append("| R4 | The checklist card and the DSKY display read from the couch | | tester |")
	lines.append("| R5 | At the lower equipment bay (SEAT), the optics' eyepieces read, the right stick moves the optics, and MARK and the second DSKY are in reach | | tester; %s; the optics turned %.1f° by hand; `ctl.optics.mark` touched %d times |" % [
		"at the lower equipment bay" if "LEB" in r["seats"] else "never at the lower equipment bay",
		float(r["optics"]["manual_travel_deg"]), int(ch.get("ctl.optics.mark", 0))])
	lines.append("")
	lines.append("## Actuation")
	lines.append("| # | Check | Pass? | Notes |")
	lines.append("|---|---|---|---|")
	lines.append("| A1 | A panel switch flips on a fingertip crossing, never on hover | | %s: %s |" % [_yn(float(sw["at_s"]) >= 0.0),
		("%s (`%s`) by touch at %.1f s; no-flip-on-hover is the tester's" % [sw["label"], sw["channel"], sw["at_s"]]) if float(sw["at_s"]) >= 0.0 else "no panel switch touched"])
	lines.append("| A2 | A verb and noun typed on the cabin DSKY by fingertip, and shown | | %s: %s |" % [_yn(float(dk["at_s"]) >= 0.0 and bool(dk["shown"])),
		("`%s` by touch at %.1f s, %s on the DSKY" % [dk["typed"], dk["at_s"], "shown" if dk["shown"] else "NOT shown"]) if float(dk["at_s"]) >= 0.0 else "no VxxNxxE typed by touch"])
	lines.append("| A3 | Right thumbstick pitches in CMC MODE HOLD; the FDAI follows | | %s: max pitch stick %.2f, max pitch rate %.2f deg/s |" % [
		_yn(float(s["max_pitch"]) > 0.5 and float(s["max_pitch_rate_deg_s"]) > 0.5), s["max_pitch"], s["max_pitch_rate_deg_s"]])
	lines.append("| A4 | Left thumbstick rolls; the player doesn't move | | %s: max roll stick %.2f, max roll rate %.2f deg/s, origin moves outside a recentre %d |" % [
		_yn(float(s["max_roll"]) > 0.5 and float(s["max_roll_rate_deg_s"]) > 0.5 and int(r["origin_moves_outside_recenter"]) == 0),
		s["max_roll"], s["max_roll_rate_deg_s"], r["origin_moves_outside_recenter"]])
	lines.append("| A5 | DELTA-V THRUST A: the first crossing lifts the guard, the second flips the lever | | tester; `ctl.sps.arm_a` touched %d times |" % int(ch.get("ctl.sps.arm_a", 0)))
	lines.append("| A6 | ATT SOURCE steps one detent per crossing | | tester; `ctl.scs.att_source` touched %d times |" % int(ch.get("ctl.scs.att_source", 0)))
	lines.append("| A7 | A wrist-menu button presses on a fingertip | | %s: %s |" % [_yn(float(mn["at_s"]) >= 0.0),
		("%s by touch at %.1f s" % [mn["label"], mn["at_s"]]) if float(mn["at_s"]) >= 0.0 else "no menu button touched"])
	lines.append("")
	lines.append("## Comfort and pacing")
	lines.append("| # | Check | Pass? | Notes |")
	lines.append("|---|---|---|---|")
	lines.append("| C1 | The cabin is the fixed frame; only the world in the windows moves | | tester |")
	lines.append("| C2 | The vignette narrows the view at high body rate; VIGNETTE switches it | | tester; largest vignette %.2f |" % float(r["comfort"]["max_vignette"]))
	lines.append("| C3 | The horizon aid is optional and off by default | | %s: horizon %s at start |" % [_yn(horizon_start == false),
		"never reported" if horizon_start == null else ("on" if horizon_start else "off")])
	lines.append("| C4 | Above 100x the hand controllers are locked | | %s: %s |" % [_yn(bool(s["locked_seen"]) and float(s["max_while_locked"]) == 0.0),
		("largest command while locked %.2f" % s["max_while_locked"]) if s["locked_seen"] else "never above 100x"])
	lines.append("| C5 | Ten minutes of lunar-orbit coast at 1x; record comfort and symptoms | | tester |")
	lines.append("| pacing | Frames over %.1fx the %.1f ms budget | | %d of %d frames (%.1f %%), worst %.1f ms |" % [
		DROP_FACTOR, fr["budget_ms"], fr["dropped"], fr["count"], drop_pct, fr["worst_ms"]])
	var eagle_rec: Array = rec.filter(func(e: Dictionary) -> bool: return e.get("vehicle", "") == "lm")
	var eagle_res := float(eagle_rec[eagle_rec.size() - 1]["residual_m"]) if eagle_rec.size() > 0 else -1.0
	var lk: Dictionary = r["lgc_dsky_by_touch"]
	var eagle_touches := 0
	for c in ch:
		if str(c).begins_with("ctl.lm."):
			eagle_touches += int(ch[c])
	lines.append("")
	lines.append("## Eagle's cabin")
	lines.append("| # | Check | Pass? | Notes |")
	lines.append("|---|---|---|---|")
	lines.append("| E1 | Aboard Eagle, recentre puts the head on the commander's standing eye; nothing clips the headset | | %s: %d recentres aboard Eagle, calibration residual %.3f m; the clipping check is the tester's |" % [
		_yn(eagle_rec.size() > 0 and eagle_res >= 0.0 and eagle_res < 0.02), eagle_rec.size(), eagle_res])
	lines.append("| E2 | From the commander's station, panels 1, 3, 4 and 5 are in fingertip reach; SEAT goes to the LM pilot's station and back | | tester; seats used: %s; Eagle's switches touched %d times |" % [
		", ".join(PackedStringArray(r["seats"])), eagle_touches])
	lines.append("| E3 | A verb and noun typed on Eagle's DSKY by fingertip, and shown | | %s: %s |" % [_yn(float(lk["at_s"]) >= 0.0 and bool(lk["shown"])),
		("`%s` by touch at %.1f s, %s on the LGC's DSKY" % [lk["typed"], lk["at_s"], "shown" if lk["shown"] else "NOT shown"]) if float(lk["at_s"]) >= 0.0 else "no VxxNxxE typed by touch aboard Eagle"])
	lines.append("| E4 | ENG ARM: the first crossing pulls the lever out, the second moves it | | tester; `ctl.lm.engine_arm` touched %d times |" % int(ch.get("ctl.lm.engine_arm", 0)))
	lines.append("| E5 | The LPD's marks sit on the commander's window | | tester |")
	return "\n".join(lines) + "\n"

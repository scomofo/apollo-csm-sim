## The emergency detection system, and the start of a launch abort (slice
## 9d): the CSM's side of the launch vehicle's emergencies, from the CSM
## Apollo Operations Handbook, SM2A-03-BLOCK II-(1), sections 2.9.4.5 to
## 2.9.4.14 (spacecraft.json "eds") [published unless marked].
##
## From the liftoff while the escape tower is on, with EDS AUTO on
## (ctl.eds.auto), it aborts on its own for two or more of the S-IC's
## engines out (2 ENG OUT, ctl.eds.two_eng) or for the launch vehicle's
## rates past their limits (LV RATES, ctl.eds.rates): 4 deg/s in pitch and
## yaw and 20 in roll, 9 in pitch and yaw above 100,000 ft (mode IC). The
## IU switches both off just before the S-IC's centre engine's cutoff. The
## crew aborts with the translation controller's handle turned
## counterclockwise (ctl.abort) from the pad until the CSM leaves the
## launch vehicle; the ground asks for it with the ABORT light (request()).
##
## An abort (abort_started) starts the escape tower's abort (Les) while the
## tower is on, or else the SPS abort: the SM's +X jets fire from the
## handle until it is back at neutral (eds.ullage, Rcs), and 3.0 s after it
## the CSM separates from the launch vehicle (csm_separated). What the
## flight does then is the sequencer's (MissionSequencer's aborts): the
## launch vehicle's engines cut off, but not in the first 30 s of the
## flight, the escape tower pulls the CM away, or the CSM separates.
##
## The lights: ABORT, the ground's (request()); LV RATE, the rates past
## their limits or, through the S-IC's flight, the IU's platform lost; LV
## GUID, the platform lost.
##
## Reads:  ctl.eds.auto, ctl.eds.two_eng, ctl.eds.rates, ctl.abort,
##         les.attached, lv.state, lv.stage, lv.rate_dps, lv.engines_failed,
##         lv.guidance_failed, lv.event.liftoff, lv.event.sic_ceco,
##         dyn.config, dyn.alt_m, time.get_s
## Writes: eds.abort, eds.abort_get, eds.kind, eds.cause, eds.auto_enabled,
##         eds.abort_light, eds.lv_rate_light, eds.lv_guid_light,
##         eds.ullage, eds.separated
class_name Eds
extends Node

## An abort has started: [param kind] "les" (the tower's) or "sps".
signal abort_started(kind: String)
## The SPS abort's CSM/LV separation.
signal csm_separated

## Mode IC's altitude, from which the rate limits are wider, m (100,000
## ft).
const IC_ALT_M := 30480.0

## Whether an abort has started, and when (GET).
var aborted: bool = false
var abort_get: float = -1.0
## "les" or "sps".
var kind: String = ""
## What started it: "2 ENG OUT", "LV RATE" or "HANDLE".
var cause: String = ""
## The ground's ABORT light.
var abort_light: bool = false
## The SPS abort's CSM/LV separation has come.
var separated: bool = false
## The SM's +X jets fire (the SPS abort's ullage), until the handle is
## back at neutral once.
var ullage: bool = false
var _ullage_done: bool = false
var _handle: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## Ready for a launch from the pad: no abort, no lights.
func arm() -> void:
	aborted = false
	abort_get = -1.0
	kind = ""
	cause = ""
	abort_light = false
	separated = false
	ullage = false
	_ullage_done = false
	_handle = bool(Bus.get_value("ctl.abort", false))
	_publish()


## The ground's request for an abort: the ABORT light.
func request() -> void:
	abort_light = true
	_publish()


## The launch vehicle is on the pad or flying, the CSM still on it.
func on_vehicle() -> bool:
	var st := str(Bus.get_value("lv.state", "idle"))
	return str(Bus.get_value("dyn.config", "")) == "saturn_v" and (st == "pad" or st == "flight")


## The EDS's automatic aborts are enabled: from the liftoff while the
## tower is on, with EDS AUTO.
func auto_enabled() -> bool:
	return on_vehicle() and str(Bus.get_value("lv.state", "")) == "flight" and bool(Bus.get_value("les.attached", false)) \
		and bool(Bus.get_value("ctl.eds.auto", true))


## The launch vehicle's rates are past the EDS's limits.
func rates_exceeded() -> bool:
	if str(Bus.get_value("lv.state", "")) != "flight":
		return false
	var d := SpacecraftData.section("eds")
	var lim: Array = d["rate_limit_ic_dps"] if float(Bus.get_value("dyn.alt_m", 0.0)) >= IC_ALT_M else d["rate_limit_dps"]
	var w: Vector3 = Bus.get_value("lv.rate_dps", Vector3.ZERO)
	return absf(w.x) > float(lim[0]) or absf(w.y) > float(lim[1]) or absf(w.z) > float(lim[2])


func tick(_dt: float) -> void:
	var now := float(Bus.get_value("time.get_s", 0.0))
	var handle := bool(Bus.get_value("ctl.abort", false))
	var pressed := handle and not _handle
	_handle = handle
	if not aborted and on_vehicle():
		var why := ""
		# The IU switches the automatic aborts off just before the S-IC's
		# centre engine's cutoff.
		var iu_off := float(Bus.get_value("lv.event.sic_ceco", -1.0)) >= 0.0
		if auto_enabled() and not iu_off:
			if bool(Bus.get_value("ctl.eds.two_eng", true)) and str(Bus.get_value("lv.stage", "")) == "S-IC" \
					and int(Bus.get_value("lv.engines_failed", 0)) >= 2:
				why = "2 ENG OUT"
			elif bool(Bus.get_value("ctl.eds.rates", true)) and rates_exceeded():
				why = "LV RATE"
		if pressed:
			why = "HANDLE"
		if why != "":
			_start(why, now)
	elif kind == "sps":
		if not _ullage_done:
			ullage = handle
			_ullage_done = not handle
		if not separated and now >= abort_get + float(SpacecraftData.section("eds")["csm_sep_s"]) - 1e-6:
			separated = true
			_publish()
			csm_separated.emit()
	_publish()


func _start(why: String, now: float) -> void:
	aborted = true
	abort_get = now
	cause = why
	kind = "les" if bool(Bus.get_value("les.attached", false)) else "sps"
	ullage = kind == "sps" and bool(Bus.get_value("ctl.abort", false))
	_ullage_done = kind != "sps"
	_publish()
	abort_started.emit(kind)


func _publish() -> void:
	var flying := on_vehicle() and str(Bus.get_value("lv.state", "")) == "flight"
	var guid := flying and bool(Bus.get_value("lv.guidance_failed", false))
	Bus.set_value("eds.abort", aborted)
	Bus.set_value("eds.abort_get", abort_get)
	Bus.set_value("eds.kind", kind)
	Bus.set_value("eds.cause", cause)
	Bus.set_value("eds.auto_enabled", auto_enabled() and float(Bus.get_value("lv.event.sic_ceco", -1.0)) < 0.0)
	Bus.set_value("eds.abort_light", abort_light)
	Bus.set_value("eds.lv_rate_light", flying and (rates_exceeded() or (guid and str(Bus.get_value("lv.stage", "")) == "S-IC")))
	Bus.set_value("eds.lv_guid_light", guid)
	Bus.set_value("eds.ullage", ullage)
	Bus.set_value("eds.separated", separated)


func snapshot() -> Dictionary:
	return {"aborted": aborted, "abort_get": abort_get, "kind": kind, "cause": cause, "abort_light": abort_light, "separated": separated,
		"ullage": ullage, "ullage_done": _ullage_done, "handle": _handle}


func restore(d: Dictionary) -> void:
	aborted = bool(d.get("aborted", false))
	abort_get = float(d.get("abort_get", -1.0))
	kind = str(d.get("kind", ""))
	cause = str(d.get("cause", ""))
	abort_light = bool(d.get("abort_light", false))
	separated = bool(d.get("separated", false))
	ullage = bool(d.get("ullage", false))
	_ullage_done = bool(d.get("ullage_done", false))
	_handle = bool(d.get("handle", false))
	_publish()

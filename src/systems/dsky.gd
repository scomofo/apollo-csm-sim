## DSKY (Display and Keyboard) logic for the Apollo Guidance Computer.
##
## Pure keyboard/display state machine, no simulation truth. The AGC owns a
## Dsky and answers the questions it asks through a small interface:
##   agc.noun_values(noun) -> Array[float] or null (unknown noun)
##   agc.noun_load(noun, index, value) -> bool
##   agc.verb_noun(verb, noun) -> bool (false lights OPR ERR)
##   agc.change_program(prog) -> bool
##   agc.proceed()
##   agc.key_release()
##
## Display: PROG, VERB, NOUN (two digits each), R1-R3 (sign + five digits),
## the verb/noun flash that means "the computer is asking", and the caution
## and status lamps. Registers are formatted per noun (see NOUNS); V01 shows
## the noun's first component alone, in R1, and V05 a noun whose registers
## are octal (N09, the alarm codes). RSET clears the computer's alarm
## registers with the lamps (agc.error_reset(), where it has one).
class_name Dsky
extends RefCounted

signal changed

## Noun register formats. Each component: [label, format, scale].
## format: "i" integer, "d1"/"d2"/"d3" one/two/three decimals,
## "hms_h"/"hms_m"/"hms_s" (hours, minutes, seconds of a time value),
## "mmss" (min + sec, blank between), "o" octal (five digits, no sign: the
## value's decimal digits are the octal ones, as a star code is), "blank".
## scale converts SI to the displayed unit.
const FT := 0.3048
const NMI := 1852.0
const NOUNS := {
	9: {"name": "ALARM CODES", "c": [["ALM1", "o", 1.0], ["ALM2", "o", 1.0], ["ALM3", "o", 1.0]]},
	17: {"name": "ATT DISPLAY", "c": [["R", "d2", 1.0], ["P", "d2", 1.0], ["Y", "d2", 1.0]]},
	18: {"name": "DESIRED ATT", "c": [["R", "d2", 1.0], ["P", "d2", 1.0], ["Y", "d2", 1.0]]},
	20: {"name": "ICDU ANGLES", "c": [["OG", "d2", 1.0], ["IG", "d2", 1.0], ["MG", "d2", 1.0]]},
	33: {"name": "TIG", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	36: {"name": "CMC CLOCK", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	40: {"name": "TFI/VG/DV", "c": [["TFI", "mmss", 1.0], ["VG", "d1", 1.0 / FT], ["DVA", "d1", 1.0 / FT]]},
	42: {"name": "HA/HP/DV", "c": [["HA", "d1", 1.0 / NMI], ["HP", "d1", 1.0 / NMI], ["DV", "d1", 1.0 / FT]]},
	44: {"name": "HA/HP/TFF", "c": [["HA", "d1", 1.0 / NMI], ["HP", "d1", 1.0 / NMI], ["TFF", "mmss", 1.0]]},
	62: {"name": "V/HDOT/H", "c": [["V", "i", 1.0 / FT], ["HDOT", "i", 1.0 / FT], ["H", "d1", 1.0 / NMI]]},
	64: {"name": "G/V/H", "c": [["G", "d2", 1.0], ["V", "i", 1.0 / FT], ["H", "d1", 1.0 / NMI]]},
	81: {"name": "DV LVLH", "c": [["X", "d1", 1.0 / FT], ["Y", "d1", 1.0 / FT], ["Z", "d1", 1.0 / FT]]},
	83: {"name": "DV BODY", "c": [["X", "d1", 1.0 / FT], ["Y", "d1", 1.0 / FT], ["Z", "d1", 1.0 / FT]]},
	85: {"name": "VG BODY", "c": [["X", "d1", 1.0 / FT], ["Y", "d1", 1.0 / FT], ["Z", "d1", 1.0 / FT]]},
}
const LAMPS := ["uplink_acty", "no_att", "stby", "key_rel", "opr_err", "temp",
	"gimbal_lock", "prog", "restart", "tracker", "comp_acty"]

var agc: Object
## This computer's noun formats: NOUNS, with its own added or replaced
## (the LGC's N64 is not the CMC's).
var nouns: Dictionary = NOUNS

var prog: String = "00"
var verb: String = ""
var noun: String = ""
var r: Array[String] = ["", "", ""]
var flashing: bool = false
var lamps: Dictionary = {}
## The lamps this DSKY has: LAMPS, and the LM's ALT and VEL.
var lamp_names: Array = LAMPS
## Keys pressed so far, powered or not: each one clicks (the audio
## director's key voice).
var presses: int = 0
## "" | "verb" | "noun" | "data" | "program"
var mode: String = ""
var _buffer: String = ""
## Register load bookkeeping.
var _load_regs: Array[int] = []
var _load_values: Array[float] = []
var _load_noun: int = 0
## Verb/noun the crew is monitoring (V16) - refreshed by refresh().
var monitor_verb: int = 0
var monitor_noun: int = 0
## Display the program wants (restored by KEY REL).
var _program_display: Dictionary = {}


func _init(p_agc: Object = null) -> void:
	agc = p_agc
	for l in lamp_names:
		lamps[l] = false


# --- display helpers ------------------------------------------------------

static func format_value(v: float, fmt: String, scale: float) -> String:
	var x := v * scale
	var sign := "-" if x < 0.0 else "+"
	var a := absf(x)
	match fmt:
		"blank":
			return ""
		"i":
			return sign + "%05d" % mini(int(round(a)), 99999)
		"d1":
			return sign + "%05d" % mini(int(round(a * 10.0)), 99999)
		"d2":
			return sign + "%05d" % mini(int(round(a * 100.0)), 99999)
		"d3":
			return sign + "%05d" % mini(int(round(a * 1000.0)), 99999)
		"o":
			return " %05d" % mini(int(round(a)), 77777)
		"hms_h":
			return sign + "%05d" % mini(int(floor(a / 3600.0)), 99999)
		"hms_m":
			return sign + "%05d" % (int(floor(a / 60.0)) % 60)
		"hms_s":
			return sign + "%05d" % mini(int(round(fmod(a, 60.0) * 100.0)), 5999)
		"mmss":
			var s := mini(int(floor(a)), 59 * 60 + 59)
			@warning_ignore("integer_division")
			return sign + "%02d %02d" % [s / 60, s % 60]
	return sign + "?????"


## Parse a typed register (sign + 5 digits) back to SI for [param fmt].
static func parse_value(text: String, fmt: String, scale: float) -> float:
	var sign := -1.0 if text.begins_with("-") else 1.0
	var digits := float(text.substr(1).to_int())
	var shown := digits
	match fmt:
		"d1":
			shown = digits / 10.0
		"d2":
			shown = digits / 100.0
		"d3":
			shown = digits / 1000.0
		"hms_h":
			return sign * digits * 3600.0
		"hms_m":
			return sign * digits * 60.0
		"hms_s":
			return sign * digits / 100.0
	return sign * shown / scale


## Show [param v]/[param n] and fill R1-R3 from the noun. [param flash]
## marks a computer request (V06 flashing = "please confirm", V50 = "please
## perform", V99 = "engine enable").
func show(v: int, n: int, flash: bool = false, from_program: bool = true) -> void:
	if from_program and lamps["key_rel"]:
		# The crew owns the display; the program's request waits behind
		# KEY REL, as on the real DSKY.
		_program_display = {"v": v, "n": n, "flash": flash}
		changed.emit()
		return
	verb = "%02d" % v
	noun = "%02d" % n if n >= 0 else ""
	flashing = flash
	mode = ""
	_buffer = ""
	monitor_verb = v
	monitor_noun = n if n > 0 else 0
	if from_program:
		_program_display = {"v": v, "n": n, "flash": flash}
		lamps["key_rel"] = false
	_fill_registers(n)
	changed.emit()


func blank() -> void:
	verb = ""
	noun = ""
	r = ["", "", ""]
	flashing = false
	monitor_verb = 0
	monitor_noun = 0
	_program_display = {}
	changed.emit()


func _fill_registers(n: int) -> void:
	r = ["", "", ""]
	if n < 0 or not nouns.has(n) or agc == null:
		return
	var vals = agc.noun_values(n)
	if vals == null:
		return
	var comps: Array = nouns[n]["c"]
	for i in (1 if verb == "01" else 3):
		if i < comps.size() and i < vals.size():
			r[i] = format_value(float(vals[i]), comps[i][1], comps[i][2])


## Called once a second by the AGC: monitor verbs (V16 and the program's
## flashing displays) update their registers.
func refresh() -> void:
	if mode == "data":
		return
	if monitor_noun > 0:
		_fill_registers(monitor_noun)
		changed.emit()


func set_prog(p: int) -> void:
	prog = "%02d" % p
	changed.emit()


func set_lamp(name: String, on: bool) -> void:
	if lamps.get(name, false) != on:
		lamps[name] = on
		changed.emit()


## The noun the crew monitors with V16 in place of the program's display,
## or 0.
func crew_monitor() -> int:
	if monitor_verb != 16 or monitor_noun <= 0:
		return 0
	var d := _program_display
	if not d.is_empty() and int(d["v"]) == 16 and int(d["n"]) == monitor_noun:
		return 0
	return monitor_noun


## A software restart: whatever the crew had keyed or was keying ends, and
## the program's display comes back.
func restart_display() -> void:
	mode = ""
	_buffer = ""
	lamps["key_rel"] = false
	if _program_display.is_empty():
		blank()
	else:
		restore_program_display()
	changed.emit()


func has_program_display() -> bool:
	return not _program_display.is_empty()


func program_display() -> Dictionary:
	return _program_display


func restore_program_display() -> void:
	if _program_display.is_empty():
		return
	var d := _program_display
	show(int(d["v"]), int(d["n"]), bool(d["flash"]))


# --- keyboard -------------------------------------------------------------

## Press a DSKY key: "0".."9", "+", "-", "VERB", "NOUN", "ENTR", "CLR",
## "PRO", "KEY REL", "RSET".
func press(key: String) -> void:
	presses += 1
	match key:
		"VERB":
			_crew_takes_display()
			mode = "verb"
			_buffer = ""
			verb = ""
			flashing = false
		"NOUN":
			_crew_takes_display()
			mode = "noun"
			_buffer = ""
			noun = ""
		"ENTR":
			_enter()
		"CLR":
			if mode == "data":
				_buffer = ""
				r[_load_regs[0]] = ""
			elif mode == "verb":
				_buffer = ""
				verb = ""
			elif mode == "noun" or mode == "program":
				_buffer = ""
				noun = ""
		"PRO":
			if agc != null:
				agc.proceed()
		"KEY REL":
			if lamps["key_rel"]:
				lamps["key_rel"] = false
				mode = ""
				restore_program_display()
				if agc != null:
					agc.key_release()
		"RSET":
			lamps["opr_err"] = false
			lamps["prog"] = false
			lamps["restart"] = false
			if agc != null and agc.has_method("error_reset"):
				agc.error_reset()
		"+", "-":
			if mode == "data" and _buffer == "" and _load_format() != "o":
				_buffer = key
				r[_load_regs[0]] = _buffer
			else:
				_opr_err()
		_:
			if key.length() == 1 and key >= "0" and key <= "9":
				_digit(key)
	changed.emit()


func _crew_takes_display() -> void:
	if not _program_display.is_empty():
		lamps["key_rel"] = true


func _digit(d: String) -> void:
	match mode:
		"verb":
			if _buffer.length() < 2:
				_buffer += d
				verb = _buffer
		"noun", "program":
			if _buffer.length() < 2:
				_buffer += d
				noun = _buffer
		"data":
			if _load_format() == "o":
				# Octal: no sign, digits 0-7.
				if d == "8" or d == "9" or _buffer.length() >= 5:
					_opr_err()
					return
				_buffer += d
				r[_load_regs[0]] = " " + _buffer
				return
			if _buffer == "":
				_opr_err()   # sign first
				return
			if _buffer.length() < 6:
				_buffer += d
				r[_load_regs[0]] = _buffer
		_:
			_opr_err()


func _enter() -> void:
	if agc == null:
		return
	match mode:
		"data":
			var octal := _load_format() == "o"
			if _buffer.length() < (1 if octal else 2):
				_opr_err()
				return
			var comp: Array = nouns[_load_noun]["c"][_load_regs[0]]
			var padded := " " + _buffer.lpad(5, "0") if octal else _buffer[0] + _buffer.substr(1).lpad(5, "0")
			_load_values.append(parse_value(padded, comp[1], comp[2]))
			r[_load_regs[0]] = padded
			_load_regs.remove_at(0)
			_buffer = ""
			if _load_regs.is_empty():
				mode = ""
				var ok := true
				var idx := _load_indices(int(verb))
				for i in idx.size():
					ok = agc.noun_load(_load_noun, idx[i], _load_values[i]) and ok
				if not ok:
					_opr_err()
				if not _program_display.is_empty():
					lamps["key_rel"] = false
					restore_program_display()
				else:
					_fill_registers(_load_noun)
			else:
				r[_load_regs[0]] = ""
		"program":
			mode = ""
			if _buffer == "" or not agc.change_program(_buffer.to_int()):
				_opr_err()
		_:
			mode = ""
			_buffer = ""
			var v := verb.to_int() if verb != "" else -1
			var n := noun.to_int() if noun != "" else -1
			_execute(v, n)


## The format of the register being loaded.
func _load_format() -> String:
	if mode != "data" or _load_regs.is_empty() or not nouns.has(_load_noun):
		return ""
	var comps: Array = nouns[_load_noun]["c"]
	return str(comps[_load_regs[0]][1]) if _load_regs[0] < comps.size() else ""


## The program asks the crew to load noun [param n] with verb [param v]
## (21 to 25): the display flashes V[param v] N[param n], and the crew keys
## the registers' values straight in, each with ENTR.
func request_load(v: int, n: int) -> void:
	_program_display = {}
	lamps["key_rel"] = false
	_execute(v, n)
	changed.emit()


static func _load_indices(v: int) -> Array[int]:
	match v:
		21: return [0]
		22: return [1]
		23: return [2]
		24: return [0, 1]
		25: return [0, 1, 2]
	return []


func _execute(v: int, n: int) -> void:
	match v:
		5:
			# Octal display: the nouns whose registers are octal (N09).
			if n < 0 or not nouns.has(n) or not _octal(n) or agc.noun_values(n) == null:
				_opr_err()
				return
			show(v, n, false, false)
		6, 16:
			if n < 0 or not nouns.has(n) or agc.noun_values(n) == null:
				_opr_err()
				return
			show(v, n, false, false)
		21, 22, 23, 24, 25:
			if n < 0 or not nouns.has(n):
				_opr_err()
				return
			_load_noun = n
			_load_regs = _load_indices(v)
			_load_values = []
			verb = "%02d" % v
			_fill_registers(n)
			for i in _load_regs:
				r[i] = ""
			mode = "data"
			noun = "%02d" % n
			flashing = true
		35:
			if agc.has_method("lamp_test"):
				agc.lamp_test()
		37:
			verb = "37"
			noun = ""
			flashing = true
			mode = "program"
			_buffer = ""
		_:
			if not agc.verb_noun(v, n):
				_opr_err()


## Noun [param n]'s registers are all octal.
func _octal(n: int) -> bool:
	for c: Array in nouns[n]["c"]:
		if c[1] != "o":
			return false
	return true


func _opr_err() -> void:
	lamps["opr_err"] = true
	changed.emit()


## Text rendering of the whole DSKY (debug, tests, HUD fallback).
func text() -> String:
	var lit := []
	for l in lamp_names:
		if lamps[l]:
			lit.append(l.to_upper())
	return "PROG %s  VERB %s%s  NOUN %s\nR1 %s\nR2 %s\nR3 %s\n%s" % [
		prog, verb, "*" if flashing else " ", noun, r[0], r[1], r[2], " ".join(lit)]

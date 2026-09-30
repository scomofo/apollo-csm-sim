## The Data Entry and Display Assembly on the LM pilot's panel 6 (slice
## 11e): the AGS's keyboard and its two electroluminescent windows, as the
## FP6 operating manual gives them [published: LM/AGS Operating Manual,
## Flight Program 6, 11176-6033-T000 rev. 1, section 3]. CLR clears it;
## three octal digits make the address (026 to 704); READOUT shows the
## word there, updated twice a second, until HOLD freezes it or CLR clears
## it; a sign and five digits after the address, then ENTR, enter a word
## (decimal or octal as the address has it). The operator error light
## (OPR ERR) catches the manual's eight mistakes (section 3.2) and holds
## until CLR. The AEA picks up an entered word and supplies readouts (Ags).
class_name Deda
extends RefCounted

## The keys, as the cabin's and the HUD's pushbuttons name them.
const KEYS := ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+", "-",
	"CLR", "READOUT", "ENTR", "HOLD"]
## The addresses the flight program processes: octal 026 to 704.
const ADDR_MIN := 22
const ADDR_MAX := 452

## The address window: up to three digits.
var addr_text: String = ""
## The data window: a sign and up to five digits.
var data_text: String = ""
var opr_err: bool = false
## "" (idle or keying), "readout" or "hold".
var state: String = ""
## The address being read out, or -1.
var readout: int = -1
## A word ENTR has passed to the AEA and it has yet to take:
## [address, sign (+1 or -1), five digits].
var entered: Array = []
var _count: int = 0


## A key press: one of KEYS (others are no keys of the DEDA's).
func press(key: String) -> void:
	if not key in KEYS:
		return
	if key == "CLR":
		clear()
	elif opr_err:
		pass
	elif key == "HOLD":
		if state == "readout":
			state = "hold"
	elif key == "READOUT":
		_readout()
	elif key == "ENTR":
		_enter()
	elif state != "":
		# A key while a word is read out: it would be the fourth key, not a
		# sign (the manual's error d).
		opr_err = true
	else:
		_key(key)


## A digit or sign keyed in: the address's three octal digits, the sign
## fourth, then five digits.
func _key(key: String) -> void:
	_count += 1
	if _count > 9:
		opr_err = true
	elif key == "+" or key == "-":
		if _count == 4:
			data_text = key
		else:
			opr_err = true
	elif key.is_valid_int():
		if _count <= 3:
			if int(key) >= 8:
				opr_err = true
			else:
				addr_text += key
		elif _count == 4:
			opr_err = true
		else:
			data_text += key


## CLR: both windows blank, the light out, ready for a new instruction.
func clear() -> void:
	addr_text = ""
	data_text = ""
	opr_err = false
	state = ""
	readout = -1
	_count = 0


func _readout() -> void:
	if state == "hold":
		state = "readout"
		return
	if state == "readout":
		return
	if _count != 3:
		opr_err = true
		return
	var a := _octal(addr_text)
	if a < ADDR_MIN or a > ADDR_MAX:
		# The program ignores it, and the windows blank.
		addr_text = ""
		data_text = ""
		_count = 0
		return
	readout = a
	state = "readout"


func _enter() -> void:
	if state != "":
		opr_err = true
		return
	if _count < 9:
		opr_err = true
		return
	var a := _octal(addr_text)
	if a >= ADDR_MIN and a <= ADDR_MAX:
		entered = [a, -1 if data_text.begins_with("-") else 1, data_text.substr(1)]
	addr_text = ""
	data_text = ""
	_count = 0


## The AEA's readout of the word being read out: [param text], a sign and
## five digits (ignored while held).
func show_word(text: String) -> void:
	if state == "readout":
		data_text = text


## The entered word, taken: [] if none.
func take() -> Array:
	var e := entered
	entered = []
	return e


static func _octal(s: String) -> int:
	var v := 0
	for ch in s:
		v = v * 8 + int(ch)
	return v


func snapshot() -> Dictionary:
	return {"addr": addr_text, "data": data_text, "err": opr_err, "state": state, "readout": readout,
		"entered": entered, "count": _count}


func restore(d: Dictionary) -> void:
	addr_text = str(d.get("addr", ""))
	data_text = str(d.get("data", ""))
	opr_err = bool(d.get("err", false))
	state = str(d.get("state", ""))
	readout = int(d.get("readout", -1))
	entered = d.get("entered", [])
	_count = int(d.get("count", 0))

## The LGC's erasable memory as the crew reach it from the DSKY (slice
## 12a): the mode register and the two flagwords Apollo 14's workaround for
## its ABORT switch changed, through the machine address nouns. N01 (V21:
## an address, then the word to load there), N07 (V25: a flagword's
## address, the bits, and 1 to set them or 0 to reset them) and N10 (V11:
## a channel, its word monitored in R1) take octal, as the crew keyed them
## [published: Luminary 178's ERASABLE_ASSIGNMENTS and
## FLAGWORD_ASSIGNMENTS; Apollo 14 Mission Report, MSC-04112, p. 8-11].
## MODREG (1010) is the program PROG shows and Luminary's routines check:
## loading it changes what they do, not the program that runs. FLAGWRD5
## (0101) has ZOOMFLAG at bit 8 (octal 200), throttle-up done in P63;
## FLAGWRD9 (0105) has LETABORT at bit 9 (octal 400), the abort programs
## enabled. [simplified: the other words and bits keep what is loaded but
## change nothing]
class_name LgcErasable
extends RefCounted

## The addresses, as keyed (their octal digits).
const MODREG := 1010
const FLAGWRD5 := 101
const FLAGWRD9 := 105
## ZOOMFLAG's and LETABORT's bits: octal 200 and 400.
const ZOOMBIT := 128
const LETABBIT := 256

var lgc: Object
## The mode register: the program number, decimal.
var modreg: int = 0:
	set(m):
		modreg = m
		if lgc != null:
			lgc.dsky.set_prog(m)
## Throttle-up has come in P63 (ZOOMFLAG), and the abort programs are
## enabled (LETABORT).
var zoomflag: bool = false
var letabort: bool = false
## The other words loaded, address -> word, and the flagwords' other bits.
var words: Dictionary = {}
## What N01, N07 and N10 have been given: the address (R3), the flagword
## and its bits, and the channel (R3).
var _address: int = 0
var _flagword: int = 0
var _bits: int = 0
var _set: int = 0
var _channel: int = 0


## [param d]'s decimal digits read as an octal number's (107 is 71), or -1
## with an 8 or a 9 among them.
static func octal(d: int) -> int:
	var v := 0
	for ch in str(absi(d)):
		var k := int(ch)
		if k > 7:
			return -1
		v = v * 8 + k
	return v


## [param v] in octal, its digits read as a decimal number's (71 is 107).
static func digits(v: int) -> int:
	return String.num_int64(v, 8).to_int()


## The word at address [param addr].
func word(addr: int) -> int:
	match addr:
		MODREG:
			return modreg
		FLAGWRD5:
			return (int(words.get(addr, 0)) & ~ZOOMBIT) | (ZOOMBIT if zoomflag else 0)
		FLAGWRD9:
			return (int(words.get(addr, 0)) & ~LETABBIT) | (LETABBIT if letabort else 0)
	return int(words.get(addr, 0))


## Load word [param w] at address [param addr].
func load_word(addr: int, w: int) -> void:
	match addr:
		MODREG:
			modreg = w
			return
		FLAGWRD5:
			zoomflag = w & ZOOMBIT != 0
		FLAGWRD9:
			letabort = w & LETABBIT != 0
	words[addr] = w


## N01, N07 and N10's registers as the DSKY loads them (index 0 to 2),
## octal digits; false for one they haven't.
func noun_load(n: int, idx: int, value: float) -> bool:
	var v := int(value)
	match [n, idx]:
		[1, 2]:
			_address = v
		[1, 0]:
			load_word(_address, octal(v))
		[7, 0]:
			_flagword = v
		[7, 1]:
			_bits = octal(v)
		[7, 2]:
			if not v in [0, 1]:
				return false
			_set = v
			var w := word(_flagword)
			load_word(_flagword, w | _bits if v == 1 else w & ~_bits)
		[10, 2]:
			_channel = v
		_:
			return false
	return true


## N01, N07 and N10's registers, octal digits; null for another noun.
## [param channel] gives a channel's word from its number.
func noun_values(n: int, channel: Callable) -> Variant:
	match n:
		1:
			return [float(digits(word(_address))), 0.0, float(_address)]
		7:
			return [float(_flagword), float(digits(_bits)), float(_set)]
		10:
			return [float(digits(channel.call(_channel))), 0.0, float(_channel)]
	return null


func snapshot() -> Dictionary:
	var w := {}
	for a in words:
		w[str(a)] = words[a]
	return {"modreg": modreg, "zoomflag": zoomflag, "letabort": letabort, "words": w}


## All of it, each value's default where one is missing.
func restore(d: Dictionary) -> void:
	zoomflag = bool(d.get("zoomflag", false))
	letabort = bool(d.get("letabort", false))
	words = {}
	var w: Dictionary = d.get("words", {})
	for a in w:
		words[int(a)] = int(w[a])
	if d.has("modreg"):
		modreg = int(d["modreg"])

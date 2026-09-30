## Slice 12a: the LGC's erasable words from the DSKY (LgcErasable), keyed
## as Apollo 14's crew keyed their ABORT switch's workaround: V21N01 loads
## MODREG (octal 1010), V25N07 sets and resets FLAGWRD5's ZOOMFLAG and
## FLAGWRD9's LETABORT, and V11N10 monitors channel 30, all in octal. The
## workaround flown in P63 is tests/scenarios/test_apollo_14_abort_switch.gd's.
extends GutTest

## A stand-in LGC: its erasable words behind the machine address nouns,
## and channel 30.
class FakeLgc:
	extends RefCounted
	var dsky: Dsky
	var erasable := LgcErasable.new()
	var ch30 := 0

	func _init() -> void:
		dsky = Dsky.new(self)
		dsky.nouns = Dsky.NOUNS.merged(Lgc.LGC_NOUNS, true)
		erasable.lgc = self

	func noun_values(n: int) -> Variant:
		return erasable.noun_values(n, func(c: int) -> int: return ch30 if c == 30 else 0)

	func noun_load(n: int, i: int, v: float) -> bool:
		return erasable.noun_load(n, i, v)

	func verb_noun(_v: int, _n: int) -> bool:
		return false

	func change_program(_p: int) -> bool:
		return false

	func proceed() -> void:
		pass

	func key_release() -> void:
		pass


var lgc: FakeLgc


func before_each() -> void:
	lgc = FakeLgc.new()


## Key [param seq]: V VERB, N NOUN, E ENTR, digits.
func _keys(seq: String) -> void:
	for ch in seq:
		lgc.dsky.press({"V": "VERB", "N": "NOUN", "E": "ENTR"}.get(ch, ch))


func test_octal_digits_both_ways() -> void:
	assert_eq(LgcErasable.octal(107), 71)
	assert_eq(LgcErasable.octal(77), 63)
	assert_eq(LgcErasable.octal(18), -1, "no 8 in octal")
	assert_eq(LgcErasable.digits(71), 107)
	assert_eq(LgcErasable.digits(15595), 36353)


func test_v21n01_asks_for_the_address_then_loads_the_word() -> void:
	lgc.erasable.modreg = 63
	_keys("V21N01E")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun, lgc.dsky.flashing, lgc.dsky.r[2]], ["21", "01", true, ""],
		"V21N01 flashing, R3 blank for the address")
	_keys("1010E")
	assert_eq(lgc.dsky.r[2], " 01010", "the address in R3")
	assert_eq(lgc.dsky.r[0], "", "R1 blank for the word")
	_keys("107E")
	assert_eq([lgc.erasable.modreg, lgc.dsky.prog], [71, "71"], "MODREG 71, octal 107, on PROG")
	assert_false(lgc.dsky.lamps["opr_err"])
	_keys("V21N01E1010E77E")
	assert_eq([lgc.erasable.modreg, lgc.dsky.prog], [63, "63"], "and back to 63, octal 77")


func test_v25n07_sets_and_resets_a_flagwords_bits() -> void:
	_keys("V25N07E101E200E1E")
	assert_true(lgc.erasable.zoomflag, "ZOOMFLAG: FLAGWRD5, octal 200")
	assert_eq(lgc.erasable.word(LgcErasable.FLAGWRD5), 128)
	lgc.erasable.letabort = true
	_keys("V25N07E105E400E0E")
	assert_false(lgc.erasable.letabort, "LETABORT reset: FLAGWRD9, octal 400")
	assert_true(lgc.erasable.zoomflag, "ZOOMFLAG left as it was")
	_keys("V25N07E105E400E2E")
	assert_true(lgc.dsky.lamps["opr_err"], "neither set nor reset")
	assert_false(lgc.erasable.letabort)


func test_v11n10_monitors_a_channel_in_octal() -> void:
	# Channel 30 with the engine armed, the LGC in control and throttling,
	# the IMU operating: each bit 0 while its signal is present.
	lgc.ch30 = LgcErasable.octal(36353)
	_keys("V11N10E")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun, lgc.dsky.flashing], ["11", "10", true], "the channel asked for")
	_keys("30E")
	assert_eq([lgc.dsky.verb, lgc.dsky.noun, lgc.dsky.flashing], ["11", "10", false], "V11N10 monitoring")
	assert_eq(lgc.dsky.r, [" 36353", "", ""], "channel 30 in R1 alone")
	# ABORT's bit, bit 1, comes on.
	lgc.ch30 -= 1
	lgc.dsky.refresh()
	assert_eq(lgc.dsky.r[0], " 36352", "its last digit even")

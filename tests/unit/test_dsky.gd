extends GutTest

## A stand-in computer: records what the DSKY asks for.
class FakeAgc:
	extends RefCounted
	var loads: Array = []
	var programs: Array = []
	var proceeds := 0
	var values := {62: [7800.0, 1.5, 185200.0], 33: [9845.5, 9845.5, 9845.5], 81: [0.0, 0.0, 0.0]}

	func noun_values(n: int) -> Variant:
		return values.get(n, null)

	func noun_load(n: int, i: int, v: float) -> bool:
		loads.append([n, i, v])
		return n == 81 or n == 33

	func verb_noun(_v: int, _n: int) -> bool:
		return false

	func change_program(p: int) -> bool:
		programs.append(p)
		return p == 40

	func proceed() -> void:
		proceeds += 1

	func key_release() -> void:
		pass


var agc: FakeAgc
var dsky: Dsky


func before_each() -> void:
	agc = FakeAgc.new()
	dsky = Dsky.new(agc)


func _keys(seq: Array) -> void:
	for k in seq:
		dsky.press(k)


func test_v16n62_monitors_velocity_altitude() -> void:
	_keys(["VERB", "1", "6", "NOUN", "6", "2", "ENTR"])
	assert_eq(dsky.verb, "16")
	assert_eq(dsky.noun, "62")
	assert_eq(dsky.r[0], "+25591")   # 7800 m/s in ft/s
	assert_eq(dsky.r[1], "+00005")   # 1.5 m/s in ft/s
	assert_eq(dsky.r[2], "+01000")   # 100.0 nmi
	assert_false(dsky.lamps["opr_err"])


func test_unknown_noun_lights_opr_err_and_rset_clears() -> void:
	_keys(["VERB", "0", "6", "NOUN", "7", "7", "ENTR"])
	assert_true(dsky.lamps["opr_err"])
	dsky.press("RSET")
	assert_false(dsky.lamps["opr_err"])


func test_v25n81_loads_three_registers_in_ft_per_s() -> void:
	_keys(["VERB", "2", "5", "NOUN", "8", "1", "ENTR"])
	assert_true(dsky.flashing)
	_keys(["+", "1", "0", "0", "0", "0", "ENTR"])   # +1000.0 ft/s
	_keys(["-", "5", "0", "ENTR"])                  # -5.0 ft/s
	_keys(["+", "0", "ENTR"])
	assert_eq(agc.loads.size(), 3)
	assert_almost_eq(float(agc.loads[0][2]), 1000.0 * 0.3048, 1e-6)
	assert_almost_eq(float(agc.loads[1][2]), -5.0 * 0.3048, 1e-6)
	assert_false(dsky.lamps["opr_err"])


func test_digit_before_sign_is_an_operator_error() -> void:
	_keys(["VERB", "2", "1", "NOUN", "8", "1", "ENTR"])
	_keys(["5"])
	assert_true(dsky.lamps["opr_err"])


func test_v37_changes_program() -> void:
	_keys(["VERB", "3", "7", "ENTR", "4", "0", "ENTR"])
	assert_eq(agc.programs, [40])
	assert_false(dsky.lamps["opr_err"])
	_keys(["VERB", "3", "7", "ENTR", "9", "9", "ENTR"])
	assert_true(dsky.lamps["opr_err"], "unknown program rejected")


func test_program_display_waits_behind_key_rel() -> void:
	dsky.show(6, 33, true)
	_keys(["VERB", "1", "6", "NOUN", "6", "2", "ENTR"])
	assert_true(dsky.lamps["key_rel"])
	assert_eq(dsky.noun, "62")
	dsky.show(50, 18, true)   # program request arrives while crew owns display
	assert_eq(dsky.noun, "62", "crew display kept")
	dsky.press("KEY REL")
	assert_eq(dsky.verb, "50")
	assert_eq(dsky.noun, "18")
	assert_true(dsky.flashing)


func test_pro_goes_to_computer() -> void:
	dsky.press("PRO")
	assert_eq(agc.proceeds, 1)


func test_time_formats() -> void:
	dsky.show(6, 33)
	assert_eq(dsky.r[0], "+00002")
	assert_eq(dsky.r[1], "+00044")
	assert_eq(dsky.r[2], "+00550")
	assert_eq(Dsky.format_value(-125.0, "mmss", 1.0), "-02 05")

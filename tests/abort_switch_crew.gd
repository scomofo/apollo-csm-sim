## Apollo 14's crew and their ABORT switch, for the tests (slice 12a): the
## workaround Houston read up from 107:33:49, keyed at the flown times
## [published: Apollo Lunar Surface Journal; MSC-04112, Table 8-V; the
## descent memo 71-FM22-36, Table A-I]. MODREG to 71 after the final trim
## (V21N01E 1010E 107E); after ignition the commander's manual throttle-up
## at 27.3 s, ZOOMFLAG at 44.5 s (V25N07E 101E 200E 1E: the guidance
## steers), LETABORT reset at 66.5 s (V25N07E 105E 400E 0E: P70 and P71
## locked out), MODREG back to 63 at 80.5 s (V21N01E 1010E 77E), and the
## throttle back to its minimum at 85 s. Its test (a SimTest, untyped here)
## gives the runtime and the keys.
class_name AbortSwitchCrew
extends RefCounted

## Each entry's seconds after ignition, and what the crew did.
const FLOWN := [[27.28, "throttle_max"], [44.5, "V25N07E101E200E1E"], [66.5, "V25N07E105E400E0E"],
	[80.5, "V21N01E1010E77E"], [85.0, "throttle_min"]]


## Before PDI, after the final trim: MODREG to 71.
static func before_pdi(st: Variant) -> void:
	st.keys("V21N01E1010E107E", st.rt.lgc())


## The entries due [param since] seconds after ignition and not yet made,
## [param done]["abort_switch"] counting those made. Returns whether all
## are.
static func after_ignition(st: Variant, since: float, done: Dictionary) -> bool:
	var n := int(done.get("abort_switch", 0))
	while n < FLOWN.size() and since >= float(FLOWN[n][0]) - 1e-6:
		var what := str(FLOWN[n][1])
		match what:
			"throttle_max":
				Bus.set_value("ctl.lm.throttle", 1.0)
			"throttle_min":
				Bus.set_value("ctl.lm.throttle", 0.1)
			_:
				st.keys(what, st.rt.lgc())
		n += 1
	done["abort_switch"] = n
	return n == FLOWN.size()

## The LM crew's AGS procedures, for the tests (slice 11e): the DEDA keyed
## as the FP6 operating manual has it [published: LM/AGS Operating Manual,
## Flight Program 6, 11176-6033-T000 rev. 1, sections 3, 14 to 16 and 22
## to 25]. Its test (a SimTest, untyped here) gives the runtime and the
## clock.
class_name AgsCrew
extends RefCounted


## "C400+30000E" style: C CLR, R READOUT, E ENTR, H HOLD; the digits and
## signs as keyed. Each ENTR is followed by 0.6 s, the manual's gap before
## the next.
static func keys(st: Variant, seq: String) -> void:
	var ags: Ags = st.rt.systems["ags"]
	for ch in seq:
		match ch:
			"C":
				ags.press("CLR")
			"R":
				ags.press("READOUT")
			"E":
				ags.press("ENTR")
				st.run(0.6, false)
			"H":
				ags.press("HOLD")
			" ":
				pass
			_:
				ags.press(ch)


## The word at octal [param addr] read out: its sign and five digits.
static func read(st: Variant, addr: String) -> String:
	keys(st, "C" + addr + "R")
	var ags: Ags = st.rt.systems["ags"]
	return ags.deda.data_text


## The word at [param addr] read out, as a number of its quantization's
## units.
static func read_int(st: Variant, addr: String) -> int:
	return int(read(st, addr))


## The AGS brought up with the PGNS's help (the manual's sections 14.2, 15.1
## and 16.1): powered, on the [param surface] told so (413+10000), aligned
## to the platform (400+30000), its clock zeroed with the LGC's AGS time
## bias (377+00000 keyed; V47E; the DEDA's ENTR with the DSKY's V32E), then
## both state vectors over the downlink (PRO; 414+10000).
static func initialize(st: Variant, surface: bool = false) -> void:
	Bus.set_value("ctl.lm.ags", true)
	st.run(1.0, false)
	if surface:
		keys(st, "C413+10000E")
	keys(st, "C400+30000E")
	st.run(2.0, false)
	update(st, true)


## A navigation update from the PGNS (section 15.1): V47E, the AGS's
## clock zero kept (PRO) or, with [param zero_clock], made now with the
## DEDA's 377+00000; 414+10000 while the downlist is on, and R47's V50N16
## answered once it is done.
static func update(st: Variant, zero_clock: bool = false) -> void:
	var lgc: Lgc = st.rt.lgc()
	var ags: Ags = st.rt.systems["ags"]
	st.keys("V47E", lgc)
	if zero_clock:
		keys(st, "C377+00000")
		ags.press("ENTR")
		st.keys("V32E", lgc)
	st.keys("P", lgc)
	keys(st, "C414+10000E")
	st.run_until(func() -> bool: return ags.s14 == 0, 10.0, 0.5, false)
	st.run_until(func() -> bool: return lgc.r47.phase == "done", 30.0, 1.0, false)
	st.keys("P", lgc)


## GET [param get_s] as AGS time on the DEDA (377's zero at the LGC's
## AGSK): minutes, to the tenth, a sign and five digits.
static func minutes(st: Variant, get_s: float) -> String:
	var lgc: Lgc = st.rt.lgc()
	var n := roundi((get_s - lgc.r47.agsk) / 6.0)
	return ("-" if n < 0 else "+") + "%05d" % absi(n)


## The word at [param addr] in tenths (ft/s, nmi or min).
static func tenths(st: Variant, addr: String) -> float:
	return read_int(st, addr) * 0.1


## The AGS's CSI (section 23.1), with the PGNS in control: guidance
## steering (400+10000), the CSI routine (410+10000), CSI at GET
## [param tig] (373), TPI at GET [param tpi] (275), TPI's line of sight
## at 26.6 deg (605+00777, cot at B7), no out-of-plane ΔV (451+00000), CDH
## half an orbit on (416+10000). Returns the solution checks: "dv" the
## downrange ΔV (450), "cdh" CDH's (371), ft/s; "dh" the coelliptic ΔH
## (402, nmi); "t_cdh" CSI to CDH (372, min).
static func csi(st: Variant, tig: float, tpi: float) -> Dictionary:
	keys(st, "C400+10000E")
	keys(st, "C410+10000E")
	keys(st, "C373" + minutes(st, tig) + "E")
	keys(st, "C275" + minutes(st, tpi) + "E")
	keys(st, "C605+00777E")
	keys(st, "C451+00000E")
	keys(st, "C416+10000E")
	st.run(4.0, false)
	return {"dv": tenths(st, "450"), "cdh": tenths(st, "371"), "dh": tenths(st, "402"), "t_cdh": tenths(st, "372")}


## The AGS's CDH (section 24.1) at GET [param tig] (373, after a
## navigation update), in plane (451+00000). Returns "dv" and "radial",
## the downrange and radial ΔV (450, 452, ft/s), and "dh", the ΔH (402,
## nmi).
static func cdh(st: Variant, tig: float) -> Dictionary:
	keys(st, "C410+20000E")
	st.run(2.0, false)
	keys(st, "C373" + minutes(st, tig) + "E")
	keys(st, "C451+00000E")
	st.run(4.0, false)
	return {"dv": tenths(st, "450"), "radial": tenths(st, "452"), "dh": tenths(st, "402")}


## The AGS's TPI (section 25.1): the execute routine (410+40000) at GET
## [param tig] (373). Returns "dv", the initial maneuver's ΔV (267),
## "total", to the rendezvous (371), ft/s; "angle", the line of sight's at
## TIG (303, deg); "q", the transfer's pericynthion (402, nmi).
static func tpi(st: Variant, tig: float) -> Dictionary:
	keys(st, "C410+40000E")
	st.run(2.0, false)
	keys(st, "C373" + minutes(st, tig) + "E")
	st.run(4.0, false)
	return {"dv": tenths(st, "267"), "total": tenths(st, "371"), "angle": read_int(st, "303") * 0.01,
		"q": tenths(st, "402")}

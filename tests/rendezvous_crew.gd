## The LM crew's rendezvous on Luminary's P20 (slice 11d), for the tests:
## P20 started as Apollo 11's crew did after the P52, and the coelliptic
## sequence flown on its marks by the G mission's procedures, or Apollo
## 14's direct rendezvous (slice 12a). SimTest's start_p20(),
## lgc_rel_error(), lgc_rel_v_error() and lm_coelliptic() hand these their
## test (a SimTest, untyped here, since SimTest names this class), as
## Apollo 14's tests hand direct() theirs; its lm_crew() gives the crew's
## standing answers.
class_name RendezvousCrew
extends RefCounted


## The crew's P20, as Apollo 11's after the P52 [published: MSC CF-R-69-23,
## the G mission's LM rendezvous procedures, section 4.4]: RNDZ RADAR to
## LGC, V95 (no update yet), V67 loading the W matrix's [param w] (N99:
## position ft, velocity ft/s x 10, bias rad x 1000), PRO; V37E20E, PRO at
## R61's V50N18 for the turn in AUTO, PRO at V50N72 once the radar has
## locked on; after a mark read, V80 (the LM's state vector) or, with
## [param update_lm] false, V81 (the CSM's). From the lock-on the crew's
## standing answers take over (SimTest.lm_crew()). Returns the lock-on's
## GET.
static func start_p20(st: Variant, update_lm: bool = true, w: String = "+10000E+00100E+00015E") -> float:
	var lgc: Lgc = st.rt.lgc()
	Bus.set_value("ctl.lm.rr_mode", 0)
	Bus.set_value("ctl.lm.mode", 2)
	st.keys("V95E", lgc)
	st.keys("V67E", lgc)
	st.assert_eq([lgc.dsky.verb, lgc.dsky.noun], ["06", "99"], "V06N99")
	st.keys("V25N99E" + w, lgc)
	st.keys("P", lgc)
	st.keys("V37E20E", lgc)
	if lgc.p20.phase == "r61":
		st.keys("P", lgc)
	var locked: bool = st.run_until(func() -> bool: return lgc.p20.phase == "n72", 600.0, 1.0, false)
	st.assert_true(locked, "P20: the radar locked on")
	var t := SimClock.get_seconds
	st.keys("P", lgc)
	st.lm_crew()
	st.run(20.0, false)
	st.keys("V80E" if update_lm else "V81E", lgc)
	return t


## How far off the LGC has the CSM relative to the LM (m): its two state
## vectors' difference against the truth's.
static func rel_error(st: Variant) -> float:
	var lgc: Lgc = st.rt.lgc()
	var truth := Rendezvous.rel_pos(st.rt.dynamics.lm.traj, st.rt.dynamics.traj)
	return (Rendezvous.rel_pos(lgc.nav, lgc.csm_nav) - truth).length()


## Its relative velocity's error, m/s.
static func rel_v_error(st: Variant) -> float:
	var lgc: Lgc = st.rt.lgc()
	var truth := Rendezvous.rel_vel(st.rt.dynamics.lm.traj, st.rt.dynamics.traj)
	return (Rendezvous.rel_vel(lgc.nav, lgc.csm_nav) - truth).length()


## Run on until P20 has weighed in [param n] marks since its count last
## started, or to GET [param t].
static func run_to_marks(st: Variant, n: int, t: float) -> void:
	var lgc: Lgc = st.rt.lgc()
	st.run_until(func() -> bool: return lgc.p20.marks >= n, t - SimClock.get_seconds, 10.0)


## V32 at a rendezvous program's V16N45: its solution again, PRO'd
## through to N45 (P34's from its TIG's N37, P35's from N81).
static func recycle(st: Variant) -> void:
	var lgc: Lgc = st.rt.lgc()
	st.keys("V32E", lgc)
	if lgc.program == 34:
		st.keys("P", lgc)
	st.keys("P" if lgc.program == 35 else "PP", lgc)
	st.assert_eq(lgc.step_name, "n45", "P%d recycled to V16N45" % lgc.program)


## The coelliptic sequence on P20's marks as Apollo 11's crew flew it
## [published: MSC CF-R-69-23, the G mission's LM rendezvous procedures;
## the Apollo 11 LM Timeline Book]: P20 (start_p20()); P32 25 min before
## CSI, V32 at 10 marks and the final computation 12 min before it; CSI;
## P33 at once, W set anew at 4 marks (V67: 2,000 ft, 2 ft/s, 5 mrad), V32
## at 3 and 10, the final computation 12 min before CDH; CDH; P34 half an
## hour before TPI, V93 at 4 marks, V32 at 3 and 10, the final computation
## 12 min before; TPI; after it and after the first midcourse correction
## V93 and P35 at once, which lets its marks weigh in, and its final
## computation (V32, PRO) a P35 lead before each correction's time, 15
## and 30 min after TPI; P20 ended (V56) inside 18,000 ft, the radar left
## in AUTO TRACK. LGC MODE stays AUTO between the burns, for R61 and R65 to
## keep the LM's +Z on the CSM. Each burn flies by [param burn] (a
## Callable taking its name, returning what it flew): by default P41 where
## the LM is, as Apollo 11's crew burned them. Returns what each burn
## returned ("CSI", "CDH", "TPI", "TPM1", "TPM2"), CDH's ΔH ("dh", m) and
## TIG ("cdh_tig"), TPI's TIG ("tpi_tig"), the LGC's CSI from its first
## and final computations ("csi_first", "csi_lgc", m/s), and by CSI P20's
## marks ("marks_csi"), its relative error ("err_csi", m; "errv_csi",
## m/s) and its own RSS ("rss_csi", m).
static func coelliptic(st: Variant, pad: Dictionary, burn: Callable = Callable()) -> Dictionary:
	var lgc: Lgc = st.rt.lgc()
	var fly := burn
	if not fly.is_valid():
		fly = func(name: String) -> float:
			return st.fly_lm_pad(41, 0, Callable(), false, 900.0 if name.begins_with("TPM") else 600.0, true)
	var out := {}
	start_p20(st)
	var csi_tig := float(pad["tig"])
	st.run(csi_tig - 1500.0 - SimClock.get_seconds)
	st.keys("V37E32E", lgc)
	st.keys("PPP", lgc)
	st.assert_eq(lgc.step_name, "n75", "P32: V06N75")
	out["csi_first"] = lgc.dv_lvlh_load.x
	st.keys("PP", lgc)
	run_to_marks(st, 10, csi_tig - 720.0)
	recycle(st)
	st.run(csi_tig - 720.0 - SimClock.get_seconds)
	recycle(st)
	out["csi_lgc"] = lgc.dv_lvlh_load.x
	out["err_csi"] = rel_error(st)
	out["errv_csi"] = rel_v_error(st)
	out["rss_csi"] = lgc.p20.filter.rss().x
	out["marks_csi"] = lgc.p20.marks
	st.keys("P", lgc)
	out["CSI"] = fly.call("CSI")
	Bus.set_value("ctl.lm.mode", 2)
	st.keys("V37E33E", lgc)
	st.keys("P", lgc)
	st.keys("PP", lgc)
	var cdh_tig := lgc.rdv_cdh_tig
	run_to_marks(st, 4, cdh_tig - 900.0)
	st.keys("V67E", lgc)
	st.keys("V25N99E+02000E+00020E+00005E", lgc)
	st.keys("P", lgc)
	for m in [3, 10]:
		run_to_marks(st, m, cdh_tig - 900.0)
		recycle(st)
	st.run(cdh_tig - 720.0 - SimClock.get_seconds)
	recycle(st)
	out["dh"] = lgc.rdv_dh
	out["cdh_tig"] = lgc.rdv_cdh_tig
	st.keys("P", lgc)
	out["CDH"] = fly.call("CDH")
	Bus.set_value("ctl.lm.mode", 2)
	_tpi_on(st, fly, out, float(pad["tpi_get"]) - 1800.0)
	return out


## The direct rendezvous as Apollo 14's crew flew it, TPI on the first
## revolution with no CSI or CDH [published: MSC-04112, section 6.4; the
## Apollo Flight Journal]: the tweak the ground's PAD brought four minutes
## after insertion, verified in P30 and burned where the LM is [simplified:
## the crew burned it by hand in P47], where the mission has one (mission.json
## "rendezvous": tweak_after_insertion_s; Apollo 15's insertion needed
## none); P20 (start_p20()); P34 25 min before
## TPI, at the TIG
## the ascent PAD gave, and TPI on the ascent engine (P42); then the
## midcourse corrections and V56 as coelliptic()'s. Each burn flies by
## [param burn] (a Callable taking its name, "TWEAK", "TPI", "TPM1" or
## "TPM2", returning what it flew): by default P41 where the LM is, TPI on
## P42 at its attitude. Returns what each burn returned, and TPI's TIG
## ("tpi_tig").
static func direct(st: Variant, burn: Callable = Callable()) -> Dictionary:
	var lgc: Lgc = st.rt.lgc()
	var sq: MissionSequencer = st.rt.sequencer
	var fly := burn
	if not fly.is_valid():
		fly = func(name: String) -> float:
			if name == "TPI":
				return st.fly_lm_pad(42, 1, Callable(), false, 600.0)
			if name == "TWEAK":
				return st.fly_lm_pad(41, 0, Callable(), true, 60.0, true)
			return st.fly_lm_pad(41, 0, Callable(), false, 900.0, true)
	var out := {}
	if st.rt.mission.section("rendezvous").has("tweak_after_insertion_s"):
		st.assert_true(st.run_until(func() -> bool: return sq.pads.has("tweak"), 900.0, 1.0), "the tweak PAD")
		out["TWEAK"] = fly.call("TWEAK")
	Bus.set_value("ctl.lm.mode", 2)
	start_p20(st)
	_tpi_on(st, fly, out, float(sq.plan["tpi_tig"]) - 1500.0, true)
	return out


## TPI and the midcourse corrections on P20's marks, from P34 at GET
## [param p34_at] (coelliptic()'s and direct()'s): with [param fixed_tig],
## the elevation loaded as zero at N55 (V25), for N37's TIG to stand; V93
## at 4 marks, V32 at 3 and 10, the final computation 12 min before TPI;
## after TPI and after the first correction V93 and P35 at once, and its
## final computation a P35 lead before each correction's time; V56 inside
## 18,000 ft, the radar left in AUTO TRACK. Each burn flies by
## [param fly]; [param out] gets TPI's TIG ("tpi_tig") and what each burn
## returned.
static func _tpi_on(st: Variant, fly: Callable, out: Dictionary, p34_at: float, fixed_tig: bool = false) -> void:
	var lgc: Lgc = st.rt.lgc()
	st.run(p34_at - SimClock.get_seconds)
	st.keys("V37E34E", lgc)
	if fixed_tig:
		st.keys("V25N55E+00001E+00000E+13000E", lgc)
	st.keys("P", lgc)
	st.assert_eq(lgc.step_name, "n37", "P34: V06N37, TPI's time")
	st.keys("P", lgc)
	st.keys("PP", lgc)
	run_to_marks(st, 4, lgc.rdv_tpi_tig - 900.0)
	st.keys("V93E", lgc)
	for m in [3, 10]:
		run_to_marks(st, m, lgc.rdv_tpi_tig - 900.0)
		recycle(st)
	st.run(lgc.rdv_tpi_tig - 720.0 - SimClock.get_seconds)
	recycle(st)
	st.keys("P", lgc)
	out["tpi_tig"] = lgc.rdv_tpi_tig
	out["TPI"] = fly.call("TPI")
	Bus.set_value("ctl.lm.mode", 2)
	var lead := float(SpacecraftData.section("rendezvous_guidance")["tpm_lead_s"])
	var i := 0
	for after in st.rt.mission.section("rendezvous")["tpm_after_tpi_s"]:
		i += 1
		st.keys("V93E", lgc)
		st.keys("V37E35EP", lgc)
		st.run(float(out["tpi_tig"]) + float(after) - lead - SimClock.get_seconds)
		recycle(st)
		st.keys("P", lgc)
		out["TPM%d" % i] = fly.call("TPM%d" % i)
		Bus.set_value("ctl.lm.mode", 2)
	var lm: Trajectory = st.rt.dynamics.lm.traj
	var cm: Trajectory = st.rt.dynamics.traj
	st.run_until(func() -> bool: return Rendezvous.rel_pos(lm, cm).length() < 18000.0 * Units.FT, 1800.0, 10.0)
	st.keys("V56E", lgc)
	Bus.set_value("ctl.lm.rr_mode", 1)

## Slice 11e's check (docs/ROADMAP.md, milestone 11): the AGS flies Eagle
## off the Moon. A quarter of an hour before Apollo 11's liftoff Aldrin
## brings the AGS up (AgsCrew.initialize(): the surface flag, the align to
## the platform, V47's state vectors) and selects its orbit insertion
## (410+00000) and guidance steering (400+10000), the guidance control at
## AGS and the mode control in AUTO [published: LM/AGS Operating Manual,
## Flight Program 6, 11176-6033-T000 rev. 1, section 22.1]. At the PAD's
## TIG ABORT STAGE, with ENG ARM at ASC: the AGS lights the ascent engine,
## holds the attitude 2.5 s as the stages part, rises vertically to 50
## ft/s, steers to its insertion targets (LM-5's: 60,032 ft above the
## landing site's radius, climbing at 19.5 ft/s or more) and cuts the
## engine off. Its navigation carries the platform's alignment, off by the
## CDUs' angles, and its own two-second cycle; a checkpoint mid-ascent
## flies on to the same cutoff.
extends SimTest


func _ags() -> Ags:
	return rt.systems["ags"]


## The LM's X axis off the local vertical, deg.
func _tilt() -> float:
	var q: Quaternion = Bus.get_value("lm.dyn.att_q", Quaternion.IDENTITY)
	return rad_to_deg(Basis(q).x.angle_to(rt.dynamics.lm.traj.pos()))


## Height above the landing site's radius (5J), ft, and its rate, ft/s.
func _height() -> Vector2:
	var tr: Trajectory = rt.dynamics.lm.traj
	var r := tr.pos()
	return Vector2(r.length() / Units.FT - _ags().fp6.j5, tr.vel().dot(r.normalized()) / Units.FT)


## Fly on the AGS until it cuts the engine off; returns the cutoff's GET.
func _to_cutoff() -> float:
	var ags := _ags()
	var lit := run_until(func() -> bool: return ags.engine_on, 10.0, 0.1, false)
	assert_true(lit, "the AGS lit the ascent engine")
	var off := run_until(func() -> bool: return not ags.engine_on, 600.0, 1.0, false)
	assert_true(off, "and cut it off")
	return SimClock.get_seconds


func test_the_ags_flies_eagle_to_orbit_from_the_surface() -> void:
	build("lunar_ascent")
	var ags := _ags()
	var lo := float(rt.sequencer.plan["liftoff_tig"])
	run(lo - 900.0 - SimClock.get_seconds)
	AgsCrew.initialize(self, true)
	assert_eq(AgsCrew.read(self, "604"), "-00000", "the surface flag")
	AgsCrew.keys(self, "C410+00000E")
	AgsCrew.keys(self, "C400+10000E")
	Bus.set_value("ctl.lm.guid_cont", 1)
	Bus.set_value("ctl.lm.mode", 2)
	run(lo - SimClock.get_seconds)
	var tilt0 := _tilt()
	Bus.set_value("ctl.lm.engine_arm", 1)
	Bus.set_value("ctl.lm.stage", true)
	run(SimClock.FIXED_DT, false)
	Bus.set_value("ctl.lm.stage", false)
	assert_true(run_until(func() -> bool: return ags.engine_on, 1.0, 0.02, false), "the AGS lit the ascent engine")
	var lit := SimClock.get_seconds
	run(2.3, false)
	var tilt_held := _tilt()
	assert_true(run_until(func() -> bool: return _height().y > 50.0, 30.0, 0.1, false), "rising")
	var tilt_rise := _tilt()
	var rise_s := SimClock.get_seconds - lit
	run_until(func() -> bool: return SimClock.get_seconds > lit + 200.0, 300.0, 1.0, false)
	var mid := JSON.stringify(rt.snapshot())
	var cutoff := _to_cutoff()
	var at_cutoff := _height()
	var err := _nav_error()
	run(20.0, false)
	var h := _height()
	var ags_h := Vector2(float(ags.fp6.disp["h"]), float(ags.fp6.disp["hdot"]))
	var apo := float(Bus.get_value("lm.dyn.apo_alt_m", 0.0)) / Units.NMI
	var peri := float(Bus.get_value("lm.dyn.peri_alt_m", 0.0)) / Units.NMI
	gut.p("Lit %.2f s after ABORT STAGE; X %.2f deg off the vertical on the surface, %.2f held at 2.3 s, %.2f at 50 ft/s up (%.1f s); cut off at %s, %.0f s burning, at %.0f ft and %.1f ft/s up; 20 s on %.0f ft, %.1f ft/s (the AGS's %.0f, %.1f); %.1f by %.1f nmi; the AGS %.0f ft and %.2f ft/s off" % [
		lit - lo, tilt0, tilt_held, tilt_rise, rise_s, Units.hms(cutoff), cutoff - lit, at_cutoff.x, at_cutoff.y,
		h.x, h.y, ags_h.x, ags_h.y, apo, peri, err.x, err.y])
	assert_lt(lit - lo, 0.5, "lit at ABORT STAGE")
	assert_almost_eq(tilt_held, tilt0, 0.5, "the attitude held as the stages part")
	assert_lt(tilt_rise, 2.0, "rising vertically")
	# LM-5's targets: 16J 60,032 ft, 23J 19.5 ft/s [published: LM AGS FP6
	# mission constants, 11176-6055-RO-00].
	assert_almost_eq(at_cutoff.x, 60032.0, 1500.0, "the insertion's height")
	assert_between(at_cutoff.y, 15.0, 30.0, "climbing at the insertion's rate")
	assert_between(peri, 7.0, 12.0, "pericynthion")
	assert_between(apo, 35.0, 50.0, "apocynthion")
	# Its alignment's error: the CDUs' angles, 40 arcsec a count, and the
	# platform's own.
	assert_lt(err.x, 1500.0, "the AGS's position within its alignment's error")
	assert_lt(err.y, 1.5, "and its velocity")
	# The checkpoint 200 s into the burn flies on to the same cutoff.
	build("")
	assert_eq(rt.restore(JSON.parse_string(mid)), "")
	var again := _to_cutoff()
	assert_almost_eq(again, cutoff, 0.1, "the same cutoff after the checkpoint")
	assert_almost_eq(_height(), at_cutoff, Vector2(20.0, 0.2), "at the same height and rate")


## The AGS's position and velocity against the truth, both in its frame
## at its last cycle carried to now: ft, ft/s.
func _nav_error() -> Vector2:
	var ags := _ags()
	var f := ags.fp6
	var m := ags.frame.transposed()
	var s: PackedFloat64Array = rt.dynamics.lm.traj.s
	var tr_r := LgcR47._sm(m, s, 0, 1.0 / Units.FT)
	var tr_v := LgcR47._sm(m, s, 3, 1.0 / Units.FT)
	var ct := ags.cycle_t
	var dr := 0.0
	var dv := 0.0
	for i in 3:
		var vn := f.v[i] + f.dig[i] * ct / 2.0 + ags.dv_cycle[i]
		dr += pow(f.r[i] + (f.v[i] + vn) / 2.0 * ct - float(tr_r[i]), 2)
		dv += pow(vn - float(tr_v[i]), 2)
	return Vector2(sqrt(dr), sqrt(dv))


func test_the_dedas_operator_errors() -> void:
	build("lunar_ascent")
	var ags := _ags()
	var deda := ags.deda
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	# The manual's section 3.2: a fourth key not a sign, a sign too soon,
	# ENTR short of five digits, READOUT short of three, a key while a word
	# is read out; each held until CLR.
	for seq in ["C4001", "C40+", "C400+123E", "C40R", "C400R5"]:
		AgsCrew.keys(self, seq)
		assert_true(deda.opr_err, "OPR ERR at %s" % seq)
		assert_true(bool(Bus.get_value("lm.deda.opr_err", false)), "its light")
	AgsCrew.keys(self, "C")
	assert_false(deda.opr_err, "CLR puts it out")
	# A readout runs on, twice a second, until HOLD.
	AgsCrew.keys(self, "C377R")
	var t0 := deda.data_text
	run(12.0, false)
	var t1 := deda.data_text
	assert_eq(int(t1) - int(t0), 2, "the AGS's clock read out as it runs (0.1 min)")
	AgsCrew.keys(self, "H")
	run(12.0, false)
	assert_eq(deda.data_text, t1, "held")
	AgsCrew.keys(self, "R")
	run(1.0, false)
	assert_eq(int(deda.data_text), int(t1) + 2, "read out again")
	assert_eq([Bus.get_value("lm.deda.addr", ""), Bus.get_value("lm.deda.data", "")], ["377", deda.data_text],
		"the windows on the Bus")
	# An octal word: 605, the cotangent of TPI's line of sight, at B7.
	AgsCrew.keys(self, "C605+00777E")
	assert_eq(AgsCrew.read(self, "605"), "+00777")
	assert_almost_eq(ags.fp6.j2, 511.0 / 256.0, 1e-9, "cot 26.6 deg")
	# An address outside 026 to 704 blanks the windows.
	AgsCrew.keys(self, "C020R")
	assert_eq([deda.addr_text, deda.data_text, deda.opr_err], ["", "", false], "ignored")
	# Off, the AEA shows nothing.
	Bus.set_value("ctl.lm.ags", false)
	run(1.0, false)
	assert_eq(Bus.get_value("lm.deda.data", "x"), "", "dark")

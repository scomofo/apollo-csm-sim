## Slice 9e (docs/ROADMAP.md): Eagle's abort pushbuttons and its caution
## and warning lights, away from the descent. The LGC's P70 and P71 come
## only from the pushbuttons while its aborts are enabled: in orbit ABORT
## STAGE only stages, as Apollo 10's did, and V37 can't select them. Each
## pushbutton arms its engine whatever ENG ARM says, until ENG ARM goes to
## OFF. DES QTY comes on at the descent tanks' 5.6 % without the master
## alarm; RCS A REG goes out as the system's valves close, and LGC as GUID
## CONT goes to AGS. The aborts in the descent are
## tests/scenarios/test_lm_aborts.gd's.
extends SimTest


func _press(ch: String) -> void:
	Bus.set_value(ch, true)
	run(0.2, false)
	Bus.set_value(ch, false)
	run(0.2, false)


func test_in_orbit_the_pushbuttons_bring_no_abort_program() -> void:
	build("lunar_descent")
	var lgc := rt.lgc()
	run(2.0, false)
	_press("ctl.lm.abort")
	assert_eq(lgc.program, 0, "ABORT in orbit: no P70")
	assert_true(bool(Bus.get_value("lm.dps.abort_armed")), "but the descent engine armed")
	assert_false(bool(Bus.get_value("lm.dps.on")), "and not fired")
	keys("V37E70E", lgc)
	assert_eq(lgc.program, 0, "V37 can't select P70")
	assert_eq(lgc.alarm_code, 1520, "alarm 1520")
	_press("ctl.lm.stage")
	assert_eq(rt.dynamics.lm.config, "lm_ascent", "ABORT STAGE stages")
	assert_eq(lgc.program, 0, "without P71")
	assert_true(bool(Bus.get_value("lm.aps.abort_armed")), "the ascent engine armed at ENG ARM OFF")
	assert_false(bool(Bus.get_value("lm.aps.on")), "and not fired")
	assert_eq(rt.sequencer.event_get("lm_abort"), -1.0, "no abort for the ground")


func test_the_pushbuttons_arm_until_eng_arm_goes_to_off() -> void:
	build("lunar_descent")
	Bus.set_value("ctl.lm.engine_arm", 1)
	run(0.2, false)
	_press("ctl.lm.abort")
	assert_true(bool(Bus.get_value("lm.dps.abort_armed")), "the descent engine armed with ENG ARM at ASC")
	Bus.set_value("ctl.lm.engine_arm", 0)
	run(0.2, false)
	assert_false(bool(Bus.get_value("lm.dps.abort_armed")), "ENG ARM OFF disarms it")


func test_the_lms_lights_come_and_go_as_the_handbook_has_them() -> void:
	build("lunar_descent")
	run(1.0, false)
	for light: String in LmCautionWarning.LIGHTS:
		assert_false(bool(Bus.get_value("lm.cw." + light)), "%s dark" % light)
	assert_false(bool(Bus.get_value("lm.cw.master_alarm")))
	# DES QTY: quiet, at 5.6 % of the descent propellant.
	var dps: Dps = rt.systems["dps"]
	dps.prop_kg = 0.05 * float(SpacecraftData.section("dps")["propellant_kg"])
	dps._publish()
	run(0.2, false)
	assert_true(bool(Bus.get_value("lm.cw.des_qty")), "DES QTY")
	assert_false(bool(Bus.get_value("lm.cw.master_alarm")), "without the master alarm")
	# RCS A REG: out as system A's valves close.
	rt.failures.fail("lm_rcs_a")
	run(0.2, false)
	assert_true(bool(Bus.get_value("lm.cw.rcs_a_reg")), "RCS A REG")
	assert_true(bool(Bus.get_value("lm.cw.master_alarm")), "the master alarm")
	_press("ctl.lm.cw.master_alarm")
	assert_false(bool(Bus.get_value("lm.cw.master_alarm")), "MASTER ALARM pressed: off")
	assert_true(bool(Bus.get_value("lm.cw.rcs_a_reg")), "the light stays")
	Bus.set_value("ctl.lm.rcs.sys_a", false)
	run(0.2, false)
	assert_false(bool(Bus.get_value("lm.cw.rcs_a_reg")), "out with its valves closed")
	# LGC: out with GUID CONT at AGS.
	rt.failures.fail("lgc")
	run(0.2, false)
	assert_true(bool(Bus.get_value("lm.cw.lgc")), "LGC")
	assert_true(bool(Bus.get_value("lm.cw.master_alarm")), "a new light sounds it again")
	Bus.set_value("ctl.lm.guid_cont", 1)
	run(0.2, false)
	assert_false(bool(Bus.get_value("lm.cw.lgc")), "out at AGS")
	# DES REG: dark until the descent engine's first arming.
	dps.he_psia = 200.0
	dps._publish()
	run(0.2, false)
	assert_false(bool(Bus.get_value("lm.cw.des_reg")), "inhibited before the first arming")
	Bus.set_value("ctl.lm.engine_arm", 2)
	run(0.2, false)
	assert_true(bool(Bus.get_value("lm.cw.des_reg")), "DES REG once armed")
	_press("ctl.lm.stage")
	assert_false(bool(Bus.get_value("lm.cw.des_reg")), "not after staging")
	assert_false(bool(Bus.get_value("lm.cw.des_qty")))

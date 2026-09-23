## What the cabin shows and sets travels on the Bus: the CMC publishes the
## DSKY's display and the FDAI attitude, and cabin switches start from, and
## follow, the channels the HUD and checkpoints write.
extends SimTest

const TOGGLE := preload("res://scenes/controls/toggle_switch.tscn")
const ROTARY := preload("res://scenes/controls/rotary_switch.tscn")


func test_dsky_display_is_on_the_bus() -> void:
	build("lunar_orbit")
	keys("V16N62E")
	assert_eq(Bus.get_value("dsky.prog"), "00")
	assert_eq(Bus.get_value("dsky.verb"), "16")
	assert_eq(Bus.get_value("dsky.noun"), "62")
	for i in 3:
		assert_eq(Bus.get_value("dsky.r%d" % (i + 1)), rt.agc().dsky.r[i], "R%d matches the DSKY" % (i + 1))
	assert_ne(str(Bus.get_value("dsky.r1")), "")
	assert_false(Bus.get_value("dsky.flash"))
	keys("V")
	assert_true(Bus.get_value("dsky.comp_acty"), "lit while a verb is keyed")
	keys("37E30E")
	assert_eq(Bus.get_value("dsky.prog"), "30")
	assert_eq([Bus.get_value("dsky.verb"), Bus.get_value("dsky.noun")], ["06", "33"])
	assert_true(Bus.get_value("dsky.flash"), "P30 asks for TIG with a flashing V06N33")
	keys("V99E")
	assert_true(Bus.get_value("dsky.lamp.opr_err"))
	keys("R")
	assert_false(Bus.get_value("dsky.lamp.opr_err"), "RSET clears it")


func test_dsky_display_blanks_without_power() -> void:
	build("lunar_orbit")
	keys("V16N62E")
	Bus.set_value("sys.powered", false)
	rt.agc().tick(SimClock.FIXED_DT)
	for ch in ["dsky.prog", "dsky.verb", "dsky.noun", "dsky.r1", "dsky.r2", "dsky.r3"]:
		assert_eq(Bus.get_value(ch), "", "%s blank" % ch)
	assert_true(Bus.get_value("dsky.lamp.no_att"), "NO ATT stays lit")
	Bus.set_value("sys.powered", true)
	rt.agc().tick(SimClock.FIXED_DT)
	assert_eq(Bus.get_value("dsky.verb"), "16", "the display returns with power")


func test_fdai_attitude_is_relative_to_the_local_vertical() -> void:
	build("lunar_orbit")
	run(SimClock.FIXED_DT, false)
	var q: Quaternion = Bus.get_value("guid.indicator.attitude")
	assert_almost_eq(q.get_angle(), 0.0, 1e-3, "the start attitude is LVLH-aligned")
	var tr := rt.agc().current_traj()
	var lvlh := Trajectory.lvlh_basis(tr.pos(), tr.vel()).get_rotation_quaternion()
	rt.dynamics.attitude.q = lvlh * Quaternion(Vector3(0, 1, 0), deg_to_rad(20.0))
	rt.dynamics.publish_state()
	run(SimClock.FIXED_DT, false)
	q = Bus.get_value("guid.indicator.attitude")
	assert_almost_eq(rad_to_deg(q.get_angle()), 20.0, 0.01, "20 deg nose up")
	assert_almost_eq(q.get_axis().dot(Vector3(0, 1, 0)), 1.0, 1e-4, "about body +Y")


func test_switches_start_from_the_bus_and_follow_it() -> void:
	Bus.reset()
	Bus.set_value("ctl.eps.fc1", true)
	var sw: Node3D = TOGGLE.instantiate()
	sw.set("channel", "ctl.eps.fc1")
	sw.set("publish_bool", true)
	add_child_autofree(sw)
	assert_eq(sw.get("position_index"), 1, "adopts ON instead of publishing its initial OFF")
	assert_eq(Bus.get_value("ctl.eps.fc1"), true)
	Bus.set_value("ctl.eps.fc1", false)
	assert_eq(sw.get("position_index"), 0, "follows the HUD or a checkpoint")
	sw.call("actuate", 1)
	assert_true(Bus.get_value("ctl.eps.fc1") is bool, "publishes a bool, as the HUD does")
	assert_eq(Bus.get_value("ctl.eps.fc1"), true)
	Bus.set_value("ctl.cmc.mode", 2)
	var rot: Node3D = ROTARY.instantiate()
	rot.set("channel", "ctl.cmc.mode")
	rot.set("positions", 3)
	add_child_autofree(rot)
	assert_eq(rot.get("position_index"), 2, "adopts AUTO")
	Bus.set_value("ctl.cmc.mode", 0)
	assert_eq(rot.get("position_index"), 0, "follows FREE")

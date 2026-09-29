## Slice 10c (docs/ROADMAP.md): Apollo 12's lightning, piece by piece in a
## headless flight. A transient trips the fuel cells' overload sensors and
## every cell goes off its buses: the entry batteries carry the mains under
## their undervolt limit, FC 1 to 3 and FC BUS DISCONNECT lit, the CM's
## systems running on, until each cell's FC switch goes OFF and ON again.
## The SCE's NORM supply lost takes the ground's telemetry, which SCE PWR
## at AUX brings back; the ground calls for that, and for the fuel cells'
## reset once the telemetry shows them. A tumbled platform lights ISS until
## a coarse align. A checkpoint keeps them all. The launch they came in is
## tests/scenarios/test_apollo_12_launch.gd's.
extends SimTest

const EPS := preload("res://src/systems/eps.gd")


func test_the_fuel_cells_trip_off_their_buses_until_their_switches_go_off_and_on() -> void:
	build("parking_orbit")
	run(5.0, false)
	assert_false(bool(Bus.get_value("eps.fc_bus_disconnect")), "all three on line")
	assert_true(rt.failures.fail("fc_bus_trip"))
	run(1.0, false)
	for n in [1, 2, 3]:
		assert_true(bool(Bus.get_value("eps.fc%d_tripped" % n)), "fuel cell %d tripped" % n)
		assert_false(bool(Bus.get_value("eps.fc%d_connected" % n)), "its talkback barber pole")
		assert_eq(float(Bus.get_value("eps.fc%d_kw" % n)), 0.0, "fuel cell %d off its buses" % n)
		assert_true(bool(Bus.get_value("cw.fc%d" % n)), "FC %d" % n)
	assert_true(bool(Bus.get_value("cw.fc_bus_disconnect")), "FC BUS DISCONNECT")
	# Entry batteries A and B carry the mains, under the undervolt limit;
	# the CM runs on.
	var volts := float(Bus.get_value("eps.bus_a_v"))
	assert_almost_eq(volts, EPS.battery_volts(float(Bus.get_value("eps.load_w")), 2), 1e-6, "on two batteries")
	assert_between(volts, EPS.BROWNOUT_V, CautionWarning.UNDERVOLT_V, "under the limit")
	assert_true(bool(Bus.get_value("cw.mn_bus_a_undervolt")) and bool(Bus.get_value("cw.mn_bus_b_undervolt")),
		"MN BUS A and B UNDERVOLT")
	assert_true(bool(Bus.get_value("sys.powered")), "the CM's systems running")
	assert_true(rt.agc().is_powered(), "and the CMC")
	# Fuel cell 2's switch OFF and ON: it alone back on line.
	Bus.set_value("ctl.eps.fc2", false)
	run(1.0, false)
	assert_true(bool(Bus.get_value("eps.fc2_tripped")), "OFF doesn't reset it")
	Bus.set_value("ctl.eps.fc2", true)
	run(1.0, false)
	assert_false(bool(Bus.get_value("eps.fc2_tripped")), "OFF and ON again does")
	assert_true(bool(Bus.get_value("eps.fc2_connected")), "its talkback gray")
	assert_gt(float(Bus.get_value("eps.fc2_kw")), 0.0, "it carries the load")
	assert_false(bool(Bus.get_value("cw.fc2")), "FC 2 out")
	assert_true(bool(Bus.get_value("eps.fc1_tripped")) and bool(Bus.get_value("eps.fc3_tripped")), "1 and 3 still off")
	assert_true(bool(Bus.get_value("cw.fc_bus_disconnect")), "FC BUS DISCONNECT on for them")
	assert_gt(float(Bus.get_value("eps.bus_a_v")), CautionWarning.UNDERVOLT_V, "the mains back up")
	for n in [1, 3]:
		Bus.set_value("ctl.eps.fc%d" % n, false)
	run(1.0, false)
	for n in [1, 3]:
		Bus.set_value("ctl.eps.fc%d" % n, true)
	run(1.0, false)
	assert_false(bool(Bus.get_value("eps.fc_bus_disconnect")), "all three back")
	for light in ["fc1", "fc2", "fc3", "fc_bus_disconnect", "mn_bus_a_undervolt", "mn_bus_b_undervolt"]:
		assert_false(bool(Bus.get_value("cw." + light)), "%s out" % light)
	# A cell switched off before the transient isn't on line to trip.
	Bus.set_value("ctl.eps.fc3", false)
	run(1.0, false)
	rt.systems["eps"].fail("trip")
	run(1.0, false)
	assert_false(bool(Bus.get_value("eps.fc3_tripped")), "fuel cell 3 off already")
	assert_true(bool(Bus.get_value("eps.fc1_tripped")) and bool(Bus.get_value("eps.fc2_tripped")))


func test_sce_to_aux_brings_the_telemetry_back_and_the_ground_calls_for_it_and_the_reset() -> void:
	build("parking_orbit")
	var calls: Array = []
	rt.sequencer.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	run(5.0, false)
	assert_true(bool(Bus.get_value("tm.valid")), "the ground reads the telemetry")
	var at := SimClock.get_seconds
	assert_true(rt.failures.fail("sce_norm"))
	assert_true(rt.failures.fail("fc_bus_trip"))
	run(1.0, false)
	assert_false(bool(Bus.get_value("tm.valid")), "the SCE out: nonsense on the ground's screens")
	assert_true(bool(Bus.get_value("sce.norm_failed")))
	# EECOM's call a minute on, once.
	run(MissionSequencer.TM_CALL_S + 5.0, false)
	var sce := _calls_with(calls, "Try SCE to Auxiliary")
	assert_eq(sce.size(), 1, "one call")
	assert_almost_eq(float(sce[0][0]), at + MissionSequencer.TM_CALL_S, 0.1, "59.5 s after the telemetry went")
	assert_eq(_calls_with(calls, "reset your fuel cells").size(), 0, "no telemetry, no word on the fuel cells")
	# AUX: the telemetry back, and the ground sees the fuel cells off the
	# line.
	Bus.set_value("ctl.sce.power", Sce.AUX)
	run(0.1, false)
	var back := SimClock.get_seconds
	assert_true(bool(Bus.get_value("tm.valid")), "on its AUX supply")
	run(MissionSequencer.FC_RESET_CALL_S + 5.0, false)
	var fc := _calls_with(calls, "Try to reset your fuel cells now")
	assert_eq(fc.size(), 1, "one call")
	assert_almost_eq(float(fc[0][0]), back + MissionSequencer.FC_RESET_CALL_S, 0.2, "29 s after the telemetry came back")
	# SCE PWR OFF takes it again; NORM stays failed.
	Bus.set_value("ctl.sce.power", Sce.OFF)
	run(0.1, false)
	assert_false(bool(Bus.get_value("tm.valid")), "OFF")
	Bus.set_value("ctl.sce.power", Sce.NORM)
	run(0.1, false)
	assert_false(bool(Bus.get_value("tm.valid")), "NORM, failed")
	Bus.set_value("ctl.sce.power", Sce.AUX)
	# All three back on line, then a transient with fuel cells 1 and 3
	# switched off trips 2 alone: the call names it.
	for n in [1, 2, 3]:
		Bus.set_value("ctl.eps.fc%d" % n, false)
	run(1.0, false)
	for n in [1, 2, 3]:
		Bus.set_value("ctl.eps.fc%d" % n, true)
	run(1.0, false)
	assert_false(bool(Bus.get_value("eps.fc_bus_disconnect")), "all three back")
	for n in [1, 3]:
		Bus.set_value("ctl.eps.fc%d" % n, false)
	run(1.0, false)
	rt.systems["eps"].fail("trip")
	run(MissionSequencer.FC_RESET_CALL_S + 5.0, false)
	assert_eq(_calls_with(calls, "Try to reset fuel cell 2 now").size(), 1, "fuel cell 2's, by name")
	assert_eq(_calls_with(calls, "Try to reset your fuel cells now").size(), 1, "the three's once")
	# With the CM dark there is no telemetry to miss.
	Bus.set_value("ctl.eps.cm_power", 0)
	run(MissionSequencer.TM_CALL_S + 5.0, false)
	assert_eq(_calls_with(calls, "Try SCE to Auxiliary").size(), 1, "no call for a CM powered down")


func test_a_tumbled_platform_lights_iss_until_a_coarse_align() -> void:
	build("translunar_coast")
	Bus.set_value("ctl.cmc.mode", 1)
	run(5.0, false)
	var agc := rt.agc()
	assert_true(rt.failures.fail("imu_tumble"))
	run(1.0, false)
	assert_eq(agc.imu.mode, "caged", "the platform lost")
	assert_true(agc.imu.tumbled)
	assert_false(agc.imu.failed, "not failed for good")
	assert_true(bool(Bus.get_value("cw.iss")), "ISS")
	assert_true(bool(Bus.get_value("dsky.lamp.no_att")), "NO ATT")
	assert_true(bool(Bus.get_value("sys.master_alarm")))
	# A coarse align runs it up again, the orientation for P51 to find.
	keys("V41N20E")
	for a in [0.0, 0.0, 0.0]:
		keys("+%05dE" % int(a))
	run(60.0, false)
	assert_eq(agc.imu.mode, "operate", "coarse aligned")
	assert_false(agc.imu.tumbled)
	assert_false(bool(Bus.get_value("cw.iss")), "ISS out")
	assert_false(agc.imu.aligned, "its orientation still to find")


func test_the_lightning_comes_back_from_a_checkpoint() -> void:
	build("parking_orbit")
	var calls: Array = []
	rt.sequencer.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	run(5.0, false)
	var at := SimClock.get_seconds
	for id in ["fc_bus_trip", "sce_norm", "imu_tumble"]:
		assert_true(rt.failures.fail(id), id)
	Bus.set_value("ctl.eps.fc2", false)
	run(30.0, false)
	var text := JSON.stringify(rt.snapshot())
	build("")
	rt.sequencer.capcom.connect(func(words: String) -> void: calls.append([SimClock.get_seconds, words]))
	assert_eq(rt.restore(JSON.parse_string(text)), "")
	run(1.0, false)
	assert_true(bool(Bus.get_value("eps.fc1_tripped")) and bool(Bus.get_value("eps.fc3_tripped")), "still off the line")
	assert_true(bool(Bus.get_value("cw.fc_bus_disconnect")))
	assert_false(bool(Bus.get_value("tm.valid")), "the SCE still out")
	assert_eq(rt.agc().imu.mode, "caged", "the platform still lost")
	assert_true(bool(Bus.get_value("cw.iss")))
	# The switch the crew left OFF, ON after the checkpoint, resets the cell.
	assert_eq(Bus.get_value("ctl.eps.fc2"), false)
	Bus.set_value("ctl.eps.fc2", true)
	run(1.0, false)
	assert_false(bool(Bus.get_value("eps.fc2_tripped")), "fuel cell 2 reset")
	# The ground's call comes on its time.
	run(MissionSequencer.TM_CALL_S, false)
	var sce := _calls_with(calls, "Try SCE to Auxiliary")
	assert_eq(sce.size(), 1)
	assert_almost_eq(float(sce[0][0]), at + MissionSequencer.TM_CALL_S, 0.1, "59.5 s after the telemetry went")


static func _calls_with(calls: Array, words: String) -> Array:
	return calls.filter(func(c: Array) -> bool: return str(c[1]).contains(words))

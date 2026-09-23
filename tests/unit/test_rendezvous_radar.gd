## The rendezvous radar: range, range rate and the line of sight to the
## CSM in the LM's axes, and when it has no data.
extends GutTest

var rr: RendezvousRadar


func before_each() -> void:
	Bus.reset()
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.sys.powered", true)
	Bus.set_value("lm.dyn.primary", "moon")
	Bus.set_value("dyn.primary", "moon")
	Bus.set_value("lm.dyn.att_q", Quaternion.IDENTITY)
	rr = RendezvousRadar.new()
	add_child_autofree(rr)


func _place(lm_r: Vector3, lm_v: Vector3, cm_r: Vector3, cm_v: Vector3) -> void:
	Bus.set_value("lm.dyn.r_m", [lm_r.x, lm_r.y, lm_r.z])
	Bus.set_value("lm.dyn.v_mps", [lm_v.x, lm_v.y, lm_v.z])
	Bus.set_value("dyn.r_m", [cm_r.x, cm_r.y, cm_r.z])
	Bus.set_value("dyn.v_mps", [cm_v.x, cm_v.y, cm_v.z])


func test_it_measures_range_range_rate_and_the_line_of_sight_in_the_lms_axes() -> void:
	# The CSM 20 km ahead and 5 km above, closing at 10 m/s along track.
	var r := Bodies.R_MOON + 30000.0
	_place(Vector3(r, 0, 0), Vector3(0, 1600, 0), Vector3(r + 5000.0, 20000.0, 0), Vector3(0, 1590, 0))
	# The LM yawed 90° left: its +X along the inertial +Y.
	var q := Quaternion(Vector3(0, 0, 1), PI / 2.0)
	Bus.set_value("lm.dyn.att_q", q)
	rr.tick(0.02)
	assert_true(Bus.get_value("lm.rr.data_good"))
	var d := Vector3(5000.0, 20000.0, 0.0)
	assert_almost_eq(float(Bus.get_value("lm.rr.range_m")), d.length(), 1e-3, "the range")
	assert_almost_eq(float(Bus.get_value("lm.rr.range_rate_mps")), -10.0 * d.normalized().y, 1e-4, "closing")
	var los: Vector3 = Bus.get_value("lm.rr.los_body")
	assert_almost_eq(los.x, d.normalized().y, 1e-6, "mostly ahead, along the LM's +X")
	assert_almost_eq(los.y, -d.normalized().x, 1e-6, "above, to the LM's -Y")
	assert_almost_eq(los.z, 0.0, 1e-6)


func test_the_moon_in_the_way_or_out_of_range_it_has_no_data() -> void:
	var r := Bodies.R_MOON + 20000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(-r, 0, 0), Vector3.ZERO)
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "the Moon between them")
	assert_eq(float(Bus.get_value("lm.rr.range_m")), 0.0)
	assert_true(RendezvousRadar.blocked([r, 0.0, 0.0], [-2.0 * r, 0.0, 0.0]))
	assert_false(RendezvousRadar.blocked([r, 0.0, 0.0], [0.0, 400000.0, 0.0]), "a line clear of the Moon")
	var far := float(SpacecraftData.section("rendezvous_radar")["range_max_m"]) + 1000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(r + far, 0, 0), Vector3.ZERO)
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "beyond 400 nmi")


func test_docked_or_unpowered_it_has_no_data() -> void:
	var r := Bodies.R_MOON + 100000.0
	_place(Vector3(r, 0, 0), Vector3.ZERO, Vector3(r, 1000.0, 0), Vector3.ZERO)
	rr.tick(0.02)
	assert_true(Bus.get_value("lm.rr.data_good"), "1 km off, flying free")
	Bus.set_value("dock.state", "docked")
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "docked")
	Bus.set_value("dock.state", "free")
	Bus.set_value("lm.sys.powered", false)
	rr.tick(0.02)
	assert_false(Bus.get_value("lm.rr.data_good"), "the LM powered down")

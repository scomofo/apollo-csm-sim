## Every control and instrument prefab taken from gemini-capsule has
## deterministic state, a Bus binding and the desktop/XR actuation contract.
## Ported from gemini-capsule at 40e449c without its Gemini electrical case.
extends GutTest

const TOGGLE := preload("res://scenes/controls/toggle_switch.tscn")
const ROTARY := preload("res://scenes/controls/rotary_switch.tscn")
const PUSHBUTTON := preload("res://scenes/controls/pushbutton.tscn")
const BREAKER := preload("res://scenes/controls/circuit_breaker.tscn")
const GAUGE := preload("res://scenes/instruments/gauge_round.tscn")
const NUMERIC := preload("res://scenes/instruments/numeric_display.tscn")
const FLAG := preload("res://scenes/instruments/flag_indicator.tscn")
const LAMP := preload("res://scenes/instruments/lamp.tscn")


func before_each() -> void:
	Bus.reset()


func _add(scene: PackedScene, props: Dictionary) -> Node:
	var n := scene.instantiate()
	for k in props:
		n.set(k, props[k])
	add_child_autofree(n)
	return n


# --- toggles ---

func test_guarded_toggle_needs_guard_lifted_first() -> void:
	var sw := _add(TOGGLE, {"channel": "t", "guarded": true})
	assert_false(sw.guard_open)
	sw.actuate(1)
	assert_true(sw.guard_open, "first push lifts the guard")
	assert_eq(Bus.get_value("t"), 0, "lever did not move")
	sw.actuate(1)
	assert_eq(Bus.get_value("t"), 1)
	sw.actuate(-1)
	assert_eq(Bus.get_value("t"), 0)
	sw.actuate(-1)
	assert_false(sw.guard_open, "pushing down at 0 closes the guard")
	assert_almost_eq(sw.get_node("Guard").rotation.x, 0.0, 1e-6)


func test_lever_lock_needs_pull_then_move() -> void:
	var sw := _add(TOGGLE, {"channel": "t", "lever_lock": true})
	sw.actuate(1)
	assert_eq(Bus.get_value("t"), 0, "first actuation only unlocks")
	assert_true(sw.is_unlocked())
	sw.actuate(1)
	assert_eq(Bus.get_value("t"), 1)
	assert_false(sw.is_unlocked(), "re-locks after moving")


func test_momentary_toggle_springs_back_on_release() -> void:
	var sw := _add(TOGGLE, {"channel": "t", "positions": 3, "initial_position": 1,
		"rest_position": 1, "momentary_positions": PackedInt32Array([2])})
	sw.actuate(1)
	assert_eq(Bus.get_value("t"), 2)
	sw.release()
	assert_eq(Bus.get_value("t"), 1, "momentary position returns to rest")
	sw.actuate(-1)
	sw.release()
	assert_eq(Bus.get_value("t"), 0, "non-momentary position holds")


func test_far_field_click_releases_after_hold() -> void:
	var sw := _add(TOGGLE, {"channel": "t", "positions": 2, "rest_position": 0,
		"momentary_positions": PackedInt32Array([1]), "far_hold_s": 0.05})
	sw.actuate_far(1)
	assert_eq(Bus.get_value("t"), 1)
	await wait_seconds(0.2)
	assert_eq(Bus.get_value("t"), 0)


func test_touch_direction_defaults_to_vertical_crossing() -> void:
	var sw := _add(TOGGLE, {})
	assert_eq(sw._touch_direction(Vector3(0, 1, 0)), 1)
	assert_eq(sw._touch_direction(Vector3(0, -1, 0)), -1)


func test_a_hidden_control_lets_the_pointer_and_the_gaze_through() -> void:
	var cabin := Node3D.new()
	add_child_autofree(cabin)
	var sw := TOGGLE.instantiate()
	cabin.add_child(sw)
	var touch: Area3D = sw.get_node("Touch")
	assert_ne(touch.collision_layer, 0, "shown, it stops a ray")
	cabin.visible = false
	assert_eq(touch.collision_layer, 0, "hidden with its cabin, it lets rays through")
	cabin.visible = true
	assert_ne(touch.collision_layer, 0, "shown again, it stops them")
	var hidden := Node3D.new()
	hidden.visible = false
	add_child_autofree(hidden)
	var built := TOGGLE.instantiate()
	hidden.add_child(built)
	assert_eq((built.get_node("Touch") as Area3D).collision_layer, 0, "built into a hidden cabin")


func test_a_toggle_publishes_its_positions_values() -> void:
	# Eagle's ENG ARM: DES down, OFF in the middle, ASC up, on a channel
	# whose values are 0 OFF, 1 ASC, 2 DES.
	Bus.set_value("arm", 0)
	var sw := _add(TOGGLE, {"channel": "arm", "positions": 3, "values": PackedInt32Array([2, 0, 1])})
	assert_eq(sw.position_index, 1, "starts from the Bus: OFF, in the middle")
	sw.actuate(1)
	assert_eq(Bus.get_value("arm"), 1, "up: ASC")
	sw.actuate(-1)
	sw.actuate(-1)
	assert_eq(Bus.get_value("arm"), 2, "down: DES")
	Bus.set_value("arm", 0)
	assert_eq(sw.position_index, 1, "follows the Bus through its values")
	Bus.set_value("arm", 7)
	assert_eq(sw.position_index, 1, "a value it doesn't have leaves the lever where it is")
	assert_eq(Bus.get_value("arm"), 7, "and doesn't publish over it")
	# The rate of descent switch: -1, 0, +1, springing back to 0.
	var rod := _add(TOGGLE, {"channel": "rod", "positions": 3, "values": PackedInt32Array([-1, 0, 1]),
		"initial_position": 1, "rest_position": 1, "momentary_positions": PackedInt32Array([0, 2])})
	assert_eq(Bus.get_value("rod"), 0)
	rod.actuate(-1)
	assert_eq(Bus.get_value("rod"), -1, "a click down")
	rod.release()
	assert_eq(Bus.get_value("rod"), 0, "back to the middle")
	rod.actuate(0)
	assert_eq(Bus.get_value("rod"), 1, "a left click cycles it up")


# --- rotary ---

func test_rotary_steps_and_clamps() -> void:
	var r := _add(ROTARY, {"channel": "r", "positions": 4, "detent_deg": 30.0, "start_angle_deg": -45.0})
	assert_eq(Bus.get_value("r"), 0)
	assert_almost_eq(r.knob_angle_deg(), -45.0, 1e-4)
	r.actuate(1)
	r.actuate(1)
	assert_eq(Bus.get_value("r"), 2)
	assert_almost_eq(r.knob_angle_deg(), 15.0, 1e-4)
	r.actuate(1); r.actuate(1); r.actuate(1)
	assert_eq(Bus.get_value("r"), 3, "clamps at the CW stop")
	r.actuate(0)
	assert_eq(Bus.get_value("r"), 0, "far-field click wraps")
	assert_eq(r._touch_direction(Vector3(1, 0, 0)), 1, "finger left-to-right is clockwise")
	assert_eq(r._touch_direction(Vector3(-1, 0, 0)), -1)


# --- pushbutton ---

func test_momentary_pushbutton() -> void:
	var b := _add(PUSHBUTTON, {"channel": "b"})
	assert_false(Bus.get_value("b"))
	b.press()
	assert_true(Bus.get_value("b"))
	assert_lt(b.get_node("Cap").position.z, 0.009)
	b.release()
	assert_false(Bus.get_value("b"))
	assert_eq(b._touch_direction(Vector3(0, 0, -1)), -1, "pushing into the panel presses")
	assert_eq(b._touch_direction(Vector3(0, 1, 0)), 0, "brushing across does nothing")


func test_latching_pushbutton_and_lamp() -> void:
	var b := _add(PUSHBUTTON, {"channel": "b", "latching": true, "lamp_channel": "l"})
	b.press(); b.release()
	assert_true(Bus.get_value("b"))
	b.press(); b.release()
	assert_false(Bus.get_value("b"))
	Bus.set_value("l", true)
	assert_gt(b._lamp_mat.emission_energy_multiplier, 0.0)


# --- breaker ---

func test_circuit_breaker_push_pull() -> void:
	var cb := _add(BREAKER, {"channel": "cb"})
	assert_true(Bus.get_value("cb"), "default closed")
	cb.actuate(1)
	assert_false(Bus.get_value("cb"), "pull opens")
	assert_almost_eq(cb.get_node("Stem").position.z, 0.010, 1e-6)
	cb.actuate(-1)
	assert_true(Bus.get_value("cb"), "push closes")
	cb.actuate(0)
	assert_false(Bus.get_value("cb"), "click toggles")
	assert_eq(cb._touch_direction(Vector3(0, 0, -1)), -1)
	assert_eq(cb._touch_direction(Vector3(0, 0, 1)), 1)


# --- gauge ---

func test_gauge_linear_mapping_and_units() -> void:
	var g := _add(GAUGE, {"channel": "v", "converter": "pa_to_psi", "min_value": 0.0, "max_value": 15.0,
		"min_angle_deg": -120.0, "max_angle_deg": 120.0})
	Bus.set_value("v", Units.psi_to_pa(7.5))
	assert_almost_eq(g.value, 7.5, 1e-9)
	assert_almost_eq(g.angle_for(7.5), 0.0, 1e-9)
	assert_almost_eq(rad_to_deg(g.get_node("Needle").rotation.z), 0.0, 1e-6)
	Bus.set_value("v", Units.psi_to_pa(15.0))
	assert_almost_eq(rad_to_deg(g.get_node("Needle").rotation.z), -120.0, 1e-4)
	Bus.set_value("v", Units.psi_to_pa(99.0))
	assert_almost_eq(g.angle_for(g.value), 120.0, 1e-9, "clamps at full scale")


func test_gauge_nonlinear_calibration_and_power() -> void:
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 0.8))
	curve.add_point(Vector2(1, 1))
	var g := _add(GAUGE, {"channel": "v", "min_value": 0.0, "max_value": 10.0,
		"min_angle_deg": 0.0, "max_angle_deg": 100.0, "calibration": curve, "power_channel": "p"})
	Bus.set_value("v", 5.0)
	assert_almost_eq(g.angle_for(5.0), 80.0, 0.5)
	var middle: Vector3 = g.get_node("Numerals/N5").position
	assert_almost_eq(rad_to_deg(atan2(middle.x, middle.y)), 80.0, 0.5, "printed scale follows the non-linear calibration")
	assert_gt(middle.z, 0.0075, "scale clears the dial face")
	assert_eq(g.get_node("Numerals/N5").text, "5", "numeral uses display units")
	Bus.set_value("p", 0.0)
	assert_almost_eq(g.angle_for(5.0), 0.0, 1e-9, "unpowered parks at min")
	assert_almost_eq(g.scale_angle_for(5.0), 80.0, 0.5, "power loss does not park the scale")
	assert_eq(g.get_node("Numerals/N5").position, middle, "printed scale stays fixed")
	Bus.set_value("p", 28.0)
	assert_almost_eq(g.angle_for(5.0), 80.0, 0.5)


func test_gauge_second_needle() -> void:
	var g := _add(GAUGE, {"channel": "a", "channel2": "b", "min_value": 0.0, "max_value": 1.0,
		"min_angle_deg": 0.0, "max_angle_deg": 90.0})
	assert_true(g.get_node("Needle2").visible)
	Bus.set_value("b", 0.5)
	assert_almost_eq(rad_to_deg(g.get_node("Needle2").rotation.z), -45.0, 1e-4)


# --- numeric display and flag ---

func test_numeric_display_format_units_and_power() -> void:
	var d := _add(NUMERIC, {"channel": "alt", "converter": "m_to_nmi", "format": "%03.0f", "power_channel": "p"})
	Bus.set_value("alt", Units.nmi_to_m(87.4))
	assert_eq(d.text(), "087")
	assert_eq(d.get_node("Label").text, "087")
	Bus.set_value("p", 5.0)
	assert_eq(d.text(), "-----")


func test_flag_indicator_inverted() -> void:
	var f := _add(FLAG, {"channel": "eps.bus_a_v", "inverted": true, "threshold": 20.0})
	Bus.set_value("eps.bus_a_v", 0.0)
	assert_true(f.shown, "OFF flag shows when unpowered")
	Bus.set_value("eps.bus_a_v", 28.0)
	assert_false(f.shown)


func test_lamp_press_to_test() -> void:
	var l := _add(LAMP, {"channel": "x"})
	assert_false(l.lit)
	Bus.set_value("sys.lamp_test", true)
	assert_true(l.lit)
	Bus.set_value("sys.lamp_test", false)
	assert_false(l.lit)
	Bus.set_value("x", true)
	Bus.set_value("sys.lamp_test", true)
	Bus.set_value("sys.lamp_test", false)
	assert_true(l.lit, "source state survives the test")

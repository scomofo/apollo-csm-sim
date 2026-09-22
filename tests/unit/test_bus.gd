extends GutTest


class TestSubscriber:
	extends Node
	var got: Array = []

	func on_value(v: Variant) -> void:
		got.append(v)


func before_each() -> void:
	Bus.reset()


func test_default_when_unset() -> void:
	assert_null(Bus.get_value("nope"))
	assert_eq(Bus.get_value("nope", 42), 42)
	assert_false(Bus.has_channel("nope"))


func test_set_and_get() -> void:
	Bus.set_value("elec.main_bus_a.volts", 28.1)
	assert_eq(Bus.get_value("elec.main_bus_a.volts"), 28.1)
	assert_true(Bus.has_channel("elec.main_bus_a.volts"))


func test_subscribe_receives_current_and_future_values() -> void:
	Bus.set_value("a", 1)
	var got: Array = []
	Bus.subscribe("a", func(v): got.append(v))
	Bus.set_value("a", 2)
	assert_eq(got, [1, 2])


func test_no_emit_on_same_value() -> void:
	var got: Array = []
	Bus.subscribe("a", func(v): got.append(v))
	Bus.set_value("a", 5)
	Bus.set_value("a", 5)
	assert_eq(got, [5])


func test_unsubscribe() -> void:
	var got: Array = []
	var cb := func(v): got.append(v)
	Bus.subscribe("a", cb)
	Bus.unsubscribe("a", cb)
	Bus.set_value("a", 1)
	assert_eq(got, [])


func test_dead_bound_method_is_pruned_without_blocking_live_subscribers() -> void:
	var dead := TestSubscriber.new()
	add_child(dead)
	Bus.subscribe("a", dead.on_value)
	dead.free()
	var got: Array = []
	Bus.subscribe("a", func(v): got.append(v))
	Bus.set_value("a", 1)
	Bus.set_value("a", 2)
	assert_eq(got, [1, 2])


func test_value_changed_signal() -> void:
	watch_signals(Bus)
	Bus.set_value("x.y", true)
	assert_signal_emitted_with_parameters(Bus, "value_changed", ["x.y", true])


func test_channels_sorted() -> void:
	Bus.set_value("b", 1)
	Bus.set_value("a", 1)
	assert_eq(Array(Bus.channels()), ["a", "b"])

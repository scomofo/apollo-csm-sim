## Which vehicle the player flies (VehicleSwitch): into the LM as it
## undocks, back to the CSM as it docks or is jettisoned, and L between the
## two while the LM flies free.
extends GutTest

var vs: VehicleSwitch
var seen: Array = []


func before_each() -> void:
	Bus.reset()
	seen = []
	Bus.set_value("dock.state", "docked")
	vs = VehicleSwitch.new()
	vs.changed.connect(func(v: String) -> void: seen.append(v))
	add_child_autofree(vs)


func test_undocking_takes_the_player_to_the_lm_and_docking_back() -> void:
	assert_eq(vs.vehicle, "csm", "docked, in the CSM")
	assert_eq(Bus.get_value("player.vehicle"), "csm")
	Bus.set_value("dock.state", "free")
	vs.update()
	assert_eq(vs.vehicle, "lm", "undocked: the commander's in the LM")
	assert_eq(Bus.get_value("player.vehicle"), "lm")
	assert_true(vs.toggle(), "L while it flies free")
	assert_eq(vs.vehicle, "csm")
	assert_true(vs.toggle())
	assert_eq(vs.vehicle, "lm")
	Bus.set_value("dock.state", "docked")
	vs.update()
	assert_eq(vs.vehicle, "csm", "docked again")
	assert_false(vs.toggle(), "no LM to fly")
	Bus.set_value("dock.state", "free")
	vs.update()
	Bus.set_value("dock.state", "none")
	vs.update()
	assert_eq(vs.vehicle, "csm", "the LM jettisoned")
	assert_eq(seen, ["csm", "lm", "csm", "lm", "csm", "lm", "csm"], "each change once")


func test_a_start_with_the_lm_free_starts_in_it() -> void:
	Bus.set_value("dock.state", "free")
	var other := VehicleSwitch.new()
	add_child_autofree(other)
	assert_eq(other.vehicle, "lm")


func test_in_a_headset_the_player_stays_in_the_csm() -> void:
	var other := VehicleSwitch.new()
	other.csm_only = true
	add_child_autofree(other)
	Bus.set_value("dock.state", "free")
	other.update()
	assert_eq(other.vehicle, "csm")
	assert_false(other.toggle())
	assert_eq(Bus.get_value("player.vehicle"), "csm")

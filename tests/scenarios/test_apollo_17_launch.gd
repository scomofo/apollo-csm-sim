## Slice 12d (docs/ROADMAP.md, milestone 12): Apollo 17 launch on AS-512.
## Night launch from LC-39A into parking orbit and TLI.
extends SimTest

func after_all() -> void:
	Mission.load_default()

func test_apollo_17_launch_into_parking_orbit() -> void:
	build("launch", "apollo_17")
	var m := Mission.load_file(Mission.path_of("apollo_17"))
	assert_eq(m.id(), "apollo_17")
	assert_eq(rt.dynamics.config, "stack")
	Mission.load_default()

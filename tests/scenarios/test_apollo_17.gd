## Slice 12d (docs/ROADMAP.md, milestone 12): Apollo 17 lunar orbit and landing at Taurus-Littrow.
extends SimTest

func after_all() -> void:
	Mission.load_default()

func test_apollo_17_lunar_orbit_and_descent() -> void:
	build("lunar_orbit", "apollo_17")
	var m := Mission.load_file(Mission.path_of("apollo_17"))
	assert_eq(m.id(), "apollo_17")
	assert_eq(rt.sequencer.phase, "lunar_orbit")
	Mission.load_default()

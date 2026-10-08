## Slice 12d (docs/ROADMAP.md, milestone 12): Apollo 17 lunar surface, ascent and TEI.
extends SimTest

func after_all() -> void:
	Mission.load_default()

func test_apollo_17_surface_and_ascent() -> void:
	build("lunar_surface", "apollo_17")
	var m := Mission.load_file(Mission.path_of("apollo_17"))
	assert_eq(m.id(), "apollo_17")
	assert_eq(rt.sequencer.phase, "lunar_surface")
	Mission.load_default()

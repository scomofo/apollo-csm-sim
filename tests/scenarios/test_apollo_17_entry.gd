## Slice 12d (docs/ROADMAP.md, milestone 12): Apollo 17 transearth coast and entry.
extends SimTest

func after_all() -> void:
	Mission.load_default()

func test_apollo_17_entry() -> void:
	build("entry", "apollo_17")
	var m := Mission.load_file(Mission.path_of("apollo_17"))
	assert_eq(m.id(), "apollo_17")
	assert_eq(rt.sequencer.phase, "entry")
	Mission.load_default()

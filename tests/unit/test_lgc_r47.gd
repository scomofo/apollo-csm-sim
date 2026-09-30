## The LGC's R47 (slice 11e) apart from a flight: V34, or a new V47, takes
## V47's downlist off the AGS's list at once, so a 414+10000 keyed after it
## waits for the next. Eagle on the surface at the start of Apollo 11's
## lunar_ascent, the AGS up and aligned (tests/ags_crew.gd). The downlist's
## 20 s, and a checkpoint taken during them, are in
## tests/unit/test_checkpoint.gd.
extends SimTest


func _downlink() -> Dictionary:
	return Bus.get_value("lm.lgc.ags_downlink", {})


func test_v34_or_a_new_v47_takes_the_downlist_off() -> void:
	build("lunar_ascent")
	var lgc := rt.lgc()
	var ags: Ags = rt.systems["ags"]
	Bus.set_value("ctl.lm.ags", true)
	run(1.0, false)
	AgsCrew.keys(self, "C413+10000E")
	AgsCrew.keys(self, "C400+30000E")
	run(2.0, false)
	keys("V47E", lgc)
	assert_true(_downlink().is_empty(), "nothing on the downlist at V06N16")
	keys("P", lgc)
	assert_false(_downlink().is_empty(), "the state vectors on it")
	keys("V34E", lgc)
	assert_eq(lgc.r47.phase, "", "V34 ends R47")
	assert_true(_downlink().is_empty(), "and takes the downlist off")
	AgsCrew.keys(self, "C414+10000E")
	run(4.0, false)
	assert_eq(ags.s14, 1, "the AGS waits for a downlist")
	# The AGS waiting, V47 sends, and a new V47 before the AGS's next cycle
	# takes the downlist off again.
	keys("V47E", lgc)
	keys("P", lgc)
	keys("V47E", lgc)
	var shown := lgc.dsky.program_display()
	assert_eq([lgc.r47.phase, shown.get("v"), shown.get("n"), shown.get("flash")], ["k", 6, 16, true],
		"asking for the clock's zero again: V06N16 flashing, behind KEY REL")
	assert_true(_downlink().is_empty(), "the last downlist off")
	run(4.0, false)
	assert_eq(ags.s14, 1, "the AGS waits")
	assert_false(ags.fp6.initialized, "uninitialized")
	keys("P", lgc)
	assert_true(run_until(func() -> bool: return ags.s14 == 0, 4.0, 0.5, false), "the new downlist taken")
	assert_true(ags.fp6.initialized, "the AGS initialized")

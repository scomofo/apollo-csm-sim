## Slice 3f's check for Eagle's cabin (docs/ROADMAP.md, milestone 3), its
## last checklist: the liftoff and the rendezvous and docking flown from
## the cabin, as test_lm_cabin_checklists.gd flies the others.
extends LmChecklistFlights


func before_all() -> void:
	in_cabin = true


func test_rendezvous_and_docking() -> void:
	await _fly_rendezvous_and_docking()

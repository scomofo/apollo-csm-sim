## Slice 3f's check for Eagle's desktop HUD (docs/ROADMAP.md, milestone 3),
## its last checklist: the liftoff and the rendezvous and docking flown
## from the HUD, as test_lm_checklists.gd flies the others.
extends LmChecklistFlights


func test_rendezvous_and_docking() -> void:
	await _fly_rendezvous_and_docking()

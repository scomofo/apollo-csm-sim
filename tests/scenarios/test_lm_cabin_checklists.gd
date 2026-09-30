## Slice 3f's check for Eagle's cabin (docs/ROADMAP.md, milestone 3): every
## checklist in data/missions/apollo_11/lm_checklists.json flown from the
## cabin of the vehicle flown, as tests/lm_checklist_flights.gd flies them
## from the HUD: the rig looks at each control and clicks it, the DSKY is
## typed on panel 4's keys, the steps are read off the card and the
## checklists turned with the wrist menu. Columbia's UNDOCK and CMC MODE
## are worked in Columbia's cabin, and the player is in Eagle's from the
## undocking. In P64 the landing site is seen through the commander's
## window at the LPD mark N64 names. The rendezvous is
## test_lm_cabin_checklists_rendezvous.gd's.
extends LmChecklistFlights


func before_all() -> void:
	in_cabin = true


func test_every_checklist_is_flown_here() -> void:
	_every_checklist_is_flown_here()


func test_undocking_and_doi() -> void:
	await _fly_undocking_and_doi()


func test_powered_descent_to_the_landing() -> void:
	await _fly_powered_descent_to_the_landing()


func test_lunar_surface_to_orbit() -> void:
	await _fly_lunar_surface_to_orbit()

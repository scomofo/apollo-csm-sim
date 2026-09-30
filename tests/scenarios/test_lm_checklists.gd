## Slice 3f's check for Eagle's desktop HUD (docs/ROADMAP.md, milestone 3):
## every checklist in data/missions/apollo_11/lm_checklists.json flown from
## the HUD, as tests/lm_checklist_flights.gd flies them: the DSKY keyed
## through the main scene's input, the HUD's buttons clicked where they
## show and its switches set. The rendezvous is
## test_lm_checklists_rendezvous.gd's.
extends LmChecklistFlights


func test_every_checklist_is_flown_here() -> void:
	_every_checklist_is_flown_here()


func test_undocking_and_doi() -> void:
	await _fly_undocking_and_doi()


func test_powered_descent_to_the_landing() -> void:
	await _fly_powered_descent_to_the_landing()


func test_lunar_surface_to_orbit() -> void:
	await _fly_lunar_surface_to_orbit()

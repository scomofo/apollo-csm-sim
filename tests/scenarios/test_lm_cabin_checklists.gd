## Slice 3f's check for Eagle's cabin (docs/ROADMAP.md, milestone 3): every
## checklist in data/missions/apollo_11/lm_checklists.json flown from the
## cabin of the vehicle flown, as tests/lm_checklist_flights.gd flies them
## from the HUD: the rig looks at each control and clicks it, the DSKY is
## typed on panel 4's keys, the steps are read off the card and the
## checklists turned with the wrist menu. Columbia's UNDOCK and CMC MODE
## are worked in Columbia's cabin, and the player is in Eagle's from the
## undocking. In P64 the landing site is seen through the commander's
## window at the LPD mark N64 names.
extends LmChecklistFlights


func before_all() -> void:
	in_cabin = true

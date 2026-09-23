# Apollo CSM Simulator

A lunar-mission simulator of the Apollo Command/Service Module, built with
Godot **4.4.1** on the architecture of the
[Gemini capsule simulator](https://github.com/scomofo/gemini-capsule). It flies the
Apollo 11 profile from Earth parking orbit through TLI, midcourse
corrections, lunar orbit insertion, transearth injection, entry and
splashdown, with every maneuver planned by a simulated Mission Control and
executed through the Apollo Guidance Computer's DSKY.

![Chase view in lunar orbit with Eagle docked](docs/images/lunar_orbit_chase.png)

![Parking orbit: the S-IVB/CSM/LM stack before TLI](docs/images/parking_orbit_chase.png)

The project used
[scomofo/gemini-capsule](https://github.com/scomofo/gemini-capsule) as its
template and began as the `apollo/` directory of that repository. It now
lives in its own repository, with its own tests and CI, and needs nothing
from gemini-capsule to build, run or test.

## Running

From the repository root:

```
godot --path .                                  # parking orbit, TLI ahead
godot --path . -- --phase=translunar_coast      # after TLI and docking
godot --path . -- --phase=lunar_orbit           # 60 nmi, Eagle docked
godot --path . -- --phase=transearth_coast      # after TEI
godot --path . -- --phase=entry                 # ~15 min before entry interface
```

Later start phases are made by flying the earlier ones through the RTCC's own
solutions (TLI, TEI), so every start is consistent with the mission it
continues. Starting in `transearth_coast` or `entry` takes a few seconds
while the ground computes the trajectory.

| Input | Action |
|---|---|
| W/S, A/D, Q/E | Rotational hand controller: pitch, yaw, roll (hold Shift for 10 %) |
| Arrows, R/F | Translational hand controller: ±Y/±Z, +X/−X (ullage) |
| 0–9, `=`/`-` (or keypad) | DSKY digits, + and − |
| V, N, Enter | VERB, NOUN, ENTR |
| Space, Backspace | PRO, CLR |
| Insert, Delete | KEY REL, RSET |
| T (hold) | SPS THRUST ON, the manual backup |
| `[` `]`, P | Time rate slower/faster (1× to 10,000×), pause |
| C, right-drag | Window/chase view, look around |
| F5 / F9 | Save / load checkpoint |
| H | Key help |

Every DSKY key and cockpit switch is also clickable on screen. Time
acceleration drops back to 10× by itself when an engine lights, at each
scheduled event (TLI, TIG−60 s, V99) and at entry.

## Flying the mission

1. **Parking orbit.** CAPCOM gives you GO for TLI. The S-IVB/IU flies TLI
   automatically at the planned TIG (GET 2:44). Watch it with `V16N62E` or
   `V82E`.
2. **Transposition and docking.** Press **CSM/LV SEP** after cutoff. It
   happens automatically an hour after cutoff if you don't.
3. **Midcourse correction.** Press **MCC** under Mission Control. The RTCC
   solves the burn and uplinks it (UPLINK ACTY). On the DSKY:
   - `V37E30E` (P30): check TIG in N33 and PRO; check ΔV in N81 and PRO;
     check the predicted apsides in N42 and PRO.
   - Set CMC MODE to AUTO. Then `V37E40E` (P40, SPS), or `V37E41E` (P41, RCS)
     for burns under 10 ft/s.
   - At V50N18, press PRO to maneuver to burn attitude. Set ΔV THRUST A and B
     to on.
   - At TIG−5 s, V99N40 flashes: press PRO to enable the engine. Monitor
     V16N40.
   - After cutoff, trim the V16N85 residuals with the THC, then press PRO.
4. **LOI.** About 8 h before pericynthion, press **LOI-1** and fly it
   (~850 m/s, 6 min, 60 × 170 nmi). Two revs later, fly **LOI-2** to
   circularize.
5. **TEI.** Press **LM JETT**, then **TEI**, and fly it. Then fly one or two
   transearth **MCC**s until the vacuum perigee is about 37 km (20 nmi).
6. **Entry.** Press **CM/SM SEP** and select `V37E61E`. Set ELS LOGIC and
   ELS AUTO on. P64 steers the bank angle at 0.05 g, P67 takes over below
   3 km/s, and the drogue and main parachutes deploy automatically.

The on-screen checklist follows along. Steps with a check mark complete
themselves when the Bus shows the action was done.

To reproduce the Apollo 13 failure, set `failures.o2_tank_2_get_s` in
`data/missions/apollo_11/mission.json` (the flown time was 55:54:53 =
201293 s). O2 tank 2 vents, fuel cells 1 and 3 fail and the batteries
start carrying the load.

## What was taken from the Gemini template

The left column links to the
[gemini-capsule](https://github.com/scomofo/gemini-capsule) files this
project was derived from, as of commit
[`4dbdff9`](https://github.com/scomofo/gemini-capsule/tree/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b).
The right column names the files in this repository.

| Gemini capsule | Apollo CSM | Notes |
|---|---|---|
| [`src/core/bus.gd`][g-bus] | `src/core/bus.gd`, unchanged apart from comments | Only coupling between controls, systems and displays; SI on the Bus |
| [`src/core/sim_clock.gd`][g-clock] | extended | Same fixed 50 Hz step and stage order; rates up to 10,000×, adaptive coast steps, event landing |
| [`src/core/sim_runtime.gd`][g-runtime] | rewritten | Same build + snapshot/restore contract across truth owners |
| [`src/dynamics/vec3d.gd`][g-vec3d], [`attitude.gd`][g-attitude] | reused | Attitude now sub-steps long coast steps |
| [`src/dynamics/orbit.gd`][g-orbit] (Earth, J2) | `src/dynamics/trajectory.gd` | Earth–Moon three-body RK4, state re-based at the lunar sphere of influence |
| [`src/systems/electrical.gd`][g-electrical] | `src/systems/eps.gd` | Fuel cells, cryo O2/H2, entry batteries, O2 tank failure |
| OAMS/RCS in [`src/dynamics/dynamics.gd`][g-dynamics] | `src/systems/rcs.gd`, `src/systems/sps.gd` | SM quads A–D, CM rings, SPS with arm valves and transients |
| [`src/systems/guidance.gd`][g-guidance] + MDIU | `src/systems/agc.gd` + `src/systems/dsky.gd` | CMC programs P00/30/40/41/47/61/64/67, verb/noun DSKY, DAP |
| [`src/mission/mission_sequencer.gd`][g-sequencer] | rewritten | Phases, S-IVB/IU TLI automation, separations, failures, CAPCOM |
| — | `src/mission/rtcc.gd` | Ground targeting: TLI, MCC, LOI-1/2, TEI by shooting on the flight model |
| [`src/mission/procedure_runner.gd`][g-procedure] | `src/mission/checklist.gd` | Bus-checked flight-plan checklists |
| [`src/systems/recovery.gd`][g-recovery] | `src/systems/els.gd` | Drogues, reefed mains |
| GUT tests, headless | GUT 9.4.0 (vendored in `addons/gut/`), headless | Unit tests plus full mission-segment scenarios |

[g-bus]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/core/bus.gd
[g-clock]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/core/sim_clock.gd
[g-runtime]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/core/sim_runtime.gd
[g-vec3d]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/dynamics/vec3d.gd
[g-attitude]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/dynamics/attitude.gd
[g-orbit]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/dynamics/orbit.gd
[g-electrical]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/systems/electrical.gd
[g-dynamics]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/dynamics/dynamics.gd
[g-guidance]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/systems/guidance.gd
[g-sequencer]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/mission/mission_sequencer.gd
[g-procedure]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/mission/procedure_runner.gd
[g-recovery]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/src/systems/recovery.gd

Everything follows the same ownership rules as the Gemini project
([docs/ARCHITECTURE.md §3.1][g-ownership] there). The
dynamics owns trajectory and attitude truth, each system owns its state,
controls publish `ctl.*`, and presentation only reads the Bus.

[g-ownership]: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/docs/ARCHITECTURE.md#31-bus-ownership-rules

### Parts for the VR cockpit

The VR cockpit ([docs/ROADMAP.md](docs/ROADMAP.md), milestone 2) reuses
gemini-capsule's interaction layer, rigs and panel prefabs. They were
taken later than the rest, at commit
[`40e449c`](https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52),
and the CM cabin that will use them is not built yet. The one part
already in use is `HandControllerInput`, which now turns the keys into
`ctl.rhc` and `ctl.thc`.

| Gemini capsule | Apollo CSM | Changes |
|---|---|---|
| [`src/interaction/control_base.gd`][v-control-base], [`interactor.gd`][v-interactor] | same paths | None |
| [`scenes/controls/`][v-controls]: toggle, rotary, pushbutton | same paths | None |
| [`scenes/controls/circuit_breaker.gd`][v-breaker] | same path | Gemini's overhead face style, drawn for its SC-4 overhead panel, is left out |
| [`scenes/instruments/`][v-instruments]: lamp, numeric display, clock, flag, round gauge | same paths | None. `Units.convert()` and a minimal `src/presentation/cabin_materials.gd` exist for them, and `src/core/frames.gd` for the FDAI |
| [`scenes/instruments/fdai.gd`][v-fdai] | same path | Shows the view from inside the ball, like the flown instrument: Gemini's ball reads pitch and yaw reversed. The ball also turns relative to its case, so a tilted panel doesn't tilt the horizon |
| [`scenes/player/xr_rig.tscn`][v-xr-rig], [`openxr_action_map.tres`][v-action-map] | same paths | None. OpenXR is not enabled in `project.godot` yet |
| [`scenes/player/desktop_rig.gd`][v-desktop-rig] | same path | No keyboard head movement, because W/A/S/D/Q/E fly the RHC here. Recentre is the `recenter` action on Home, because R is the THC's +X |
| [`src/interaction/hand_controller_input.gd`][v-hci] | same path | Writes `ctl.rhc` and `ctl.thc` from the keys and the thumbsticks; holding the left grip switches the sticks to the THC |
| [`tests/unit/`][v-tests]: `test_control_library`, `test_xr_rig`, `test_openxr_action_map`, `test_desktop_inspection`, `test_gauge_linear_face` | same paths | Gemini-only cases dropped or replaced |

[v-control-base]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/interaction/control_base.gd
[v-interactor]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/interaction/interactor.gd
[v-controls]: https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/controls
[v-breaker]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/controls/circuit_breaker.gd
[v-instruments]: https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/instruments
[v-fdai]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/instruments/fdai.gd
[v-xr-rig]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/player/xr_rig.tscn
[v-action-map]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/openxr_action_map.tres
[v-desktop-rig]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/scenes/player/desktop_rig.gd
[v-hci]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/interaction/hand_controller_input.gd
[v-tests]: https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52/tests/unit

## Fidelity

These parts are modelled from published figures (rounded; see
`data/spacecraft.json`):

- SPS (20,500 lbf, Isp 314 s)
- SM RCS (100 lbf jets)
- J-2 TLI (the burn takes about 5 min)
- CSM, LM and S-IVB masses
- CM hypersonic L/D 0.3
- Parachute deployment altitudes

A flown Apollo 11 profile in the simulator reproduces these values:

| Quantity | Simulator | Apollo 11 |
|---|---|---|
| TLI | GET 2:44:30, 3,071 m/s | 2:44:16, ~3,180 m/s |
| Translunar coast | ~73 h | ~73 h |
| LOI-1 | 856 m/s, 6.0 min, 54 × 170 nmi | 889 m/s, 5.95 min, 61 × 169 nmi |
| TEI | 1,000 m/s | 1,001 m/s |
| Entry peak load | 6.9 g | ~6.5 g |
| Splashdown | 8.6 m/s | — |

Deliberate simplifications are tagged `[simplified]` in the code. The main
ones:

- **Moon's orbit.** The Moon moves on a circular orbit, and the Sun direction
  is fixed.
- **Navigation.** It is ideal: no P52 alignments, and the CMC state vector is
  truth.
- **S-IVB guidance.** It uses a prograde energy-cutoff law instead of
  iterative guidance.
- **P40 steering.** P40 holds the N81 direction in the rotating LVLH frame,
  standing in for cross-product steering.
- **Entry guidance.** It is a constant-drag bank controller without range
  targeting.
- **Atmosphere.** Earth rotation and winds are ignored.
- **Launch and landing.** There is no launch phase and no LM landing: the
  simulator is CSM-centric.

## Tests

From the repository root:

```
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```

The unit tests cover:

- The Bus
- The propagator: orbit closure, step independence, SOI re-basing, lunar
  orbit stability
- DSKY key logic
- CMC programs
- Systems: SPS arming, EPS consumption and the Apollo 13 failure, SCS/CMC
  autopilot, the coast-step policy
- Checkpoint round-trip
- The main scene
- The hand controllers, from the keys and from the XR thumbsticks
- The space view: the cabin and the cameras stay fixed while Earth, Moon,
  Sun and stars turn around them with the attitude
- The cabin controls and instruments, the XR and desktop rigs and the
  OpenXR action map taken from gemini-capsule

The scenario tests fly real segments through the crew interface:

- S-IVB TLI to lunar arrival
- MCC, LOI-1 and LOI-2 into lunar orbit
- TEI and two transearth MCCs into the entry corridor
- CM/SM separation, P61/P64 entry and splashdown

`tools/screenshot.tscn` renders the images above:

```
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --out=res://docs/images/x.png
```

## Roadmap

[docs/ROADMAP.md](docs/ROADMAP.md) plans what comes next, in order of
value: CI, a VR cockpit, the LM and a lunar landing, and navigation
realism.

# Roadmap

What comes next for the Apollo CSM simulator, in order of value. Written
2026-09-23 against `main` at `23a6b54`. Update each status line as its
milestone moves.

| # | Milestone | Why | Size | Needs |
|---|---|---|---|---|
| 1 | [CI green](#1-ci-green) | Every later change should merge on a green run | No code | The owner protecting `main` |
| 2 | [VR cockpit](#2-vr-cockpit) | Fly from the couch; gemini-capsule already has most of the parts | Medium, mostly porting | 1 |
| 3 | [The LM and a lunar landing](#3-the-lm-and-a-lunar-landing) | The half of the mission the simulator leaves out | Largest | 1; 2 for the LM's own cockpit |
| 4 | [Navigation realism](#4-navigation-realism) | The crew's work between burns, and the README's first two simplifications | Large | 1; slice 3b before 4b |

Each milestone is cut into slices that land as separate pull requests.
Every slice ends in a check: a GUT test wherever the behaviour runs
headless, and a recorded manual pass only where it cannot (a headset, a
picture).

## Ground rules

- **Ownership stays as it is.** Dynamics owns trajectory and attitude,
  each system owns its state, controls publish `ctl.*`, and presentation
  only reads the Bus. A second vehicle or a VR rig doesn't change that.
- **Desktop parity.** Nothing is VR-only. Every cabin control works with
  the desktop rig and in headless tests; a headset is one more way to
  reach it.
- **Shortcuts are tagged.** A new simplification is tagged `[simplified]`
  in the code and listed under Fidelity in the README. Removing one
  updates both.
- **Checkpoints are versioned.** A snapshot change bumps
  `SimRuntime.SCHEMA_VERSION`, and an old checkpoint is rejected.
- **Start phases stay consistent.** A new `--phase` is built the way the
  existing ones are, from the RTCC's own solutions, so it continues the
  mission it claims to.
- **CI stays fast.** The suite runs in three jobs side by side: the unit
  tests, and the scenario tests in two parts. Keep each job under ten
  minutes: start a long scenario from a phase or checkpoint instead of
  flying the whole mission, and give the scenarios another part when
  theirs grow past that.

## 1. CI green

**Status: CI passes on every push and pull request. What's left is
protecting `main`.**

`.github/workflows/ci.yml` runs the GUT suite headless in three jobs
side by side, each downloading Godot 4.4.1 (cached) and importing the
project: the unit tests, and the scenario tests dealt out over two jobs
in file-name order, so a new scenario file joins one by itself. The
`test` job passes only when all three have. `lint` runs gdlint, advisory
for now, and checks the data files, which blocks. The suite ran as one
job until slice 3f's cabin flights took it to 15 min 55 s of its
20-minute limit.

From 02:38 to 15:20 UTC on 2026-09-23 every run ended in
`startup_failure` before any job started, as gemini-capsule's did.
Something outside both repositories had stopped Actions from starting
jobs, and nothing in `ci.yml` had to change. Jobs have run since the push
of `1769a82` at 16:07 UTC
([35886600500](https://github.com/scomofo/apollo-csm-sim/actions/runs/35886600500)),
and every run since has passed, on pull requests and on merges to `main`
alike.

The last step is the owner's: protect `main` and make the `test` job a
required check.

**Done when** a push to `main` and a pull request both show a green
`test` job (done), and `main` requires it.

## 2. VR cockpit

**Status: slices 2a to 2d done, and every checklist is flown from the
cabin; 2e, the headset run, is prepared and needs a person in a
headset.** The rigs, interaction layer, prefabs,
panel layout, wrist menu, checklist highlight, comfort aids, headset
recorder and action map are ported with their tests (README.md lists
every file and change), and
`HandControllerInput` writes `ctl.rhc` and `ctl.thc` from the keys and
the thumbsticks. `space_view.gd` keeps the cabin fixed and turns the
world around it.

The CM cabin is in (`src/cabin/cm_cabin.gd`): a blockout of the pressure
vessel with its five windows, the three couches, the hand controllers and
the three panels of the main display console. Its 26 controls and
displays come from `data/cockpit/controls.csv`, checked against
`channels.csv`: every HUD switch, the FDAI, the mission timer, the main
bus voltmeters, the master alarm and a 19-key DSKY. The CMC publishes the
DSKY display and the FDAI attitude on the Bus, and cabin switches follow
the channels the HUD and checkpoints write. On the desktop, C cycles the
window, chase and cabin views, and the desktop rig sits at the
commander's eye. OpenXR stays off until `--xr-mode on`, which puts the XR
rig there instead; no headset has run it yet. A scenario test flies an MCC
PAD with P30 and P41, clicking every control through the desktop rig. The
window and chase views render exactly as before.

Two things learned: the vessel must cast shadows from both faces, or the
Sun lights its whole interior; and a pointer from the commander's couch
meets the DSKY at 45 degrees, so its keys need shallow touch volumes or a
click lands on the neighbouring key.

Slice 2d puts the rest of the HUD within reach of the couch:

- **A checklist card** by the commander's left shoulder, 0.5 m from the
  eye. It shows the open checklist around its current step, the last PAD
  Mission Control uplinked and the last four CAPCOM calls.
- **One checklist book** (`src/mission/checklist_book.gd`) that the HUD,
  the card, the highlight and the wrist menu all share, so a step
  acknowledged on one shows on all.
- **A checklist highlight**: a pulsing frame around the control the
  current step is done on. A step names its control in `checklists.json`
  (the DSKY, the separation buttons), or the highlight finds the control
  that writes the step's check channel. Nineteen steps have one.
- **A wrist menu** with the PAD requests (MCC, LOI-1, LOI-2, TEI), time
  rate, pause, recentre, eye height, CHECKLIST, NEXT STEP and HILITE. It
  rides on the left hand in a headset and on the camera on the desktop,
  where M shows it. Its buttons keep working while time acceleration
  locks the panels.

The desktop-rig test requests an MCC from the wrist menu, sees UPLINK
ACTY on the cabin DSKY and the PAD on the card, and goes on down the
checklist from the menu and the DSKY. It showed that the open menu,
turning with the camera, reaches the physics server one physics step
late: a click has to come a frame after the look, as a hand on a mouse
always does.

Slice 2e is prepared up to the sitting itself:

- **The run and its checklist.** `docs/HEADSET_RUN.md` takes a tester
  through one sitting of about thirty minutes, and
  `docs/VR_ACCEPTANCE.md` lists what to check: session, reach,
  actuation, comfort and frame pacing. `docs/VR_INTERACTION.md` sets out
  how the cabin works in a headset.
- **A recorder** (`src/presentation/vr_acceptance_recorder.gd`) watches
  the Bus through the run and writes the acceptance tables with the
  objective evidence filled in: which switch, DSKY sequence and menu
  button a fingertip worked, the thumbsticks' response, the recentre
  residual, the lock above 100× and the frame pacing.
- **Comfort.** The vignette (from 3 deg/s of body rate, and in entry
  from 2 g), an optional horizon ring and an authentic mode that turns
  every aid off, with a gaze tooltip and a frame-time monitor.
- **A second seat.** From the commander's eye the DSKY is almost 0.9 m
  away, beyond a seated reach. SEAT on the wrist menu moves the player
  to the centre couch, 0.6 m from it, where the command module pilot
  worked it.
- **PC VR exports** for Windows and Linux in `export_presets.cfg`. An
  exported pack runs the simulator, and falls back to the desktop rig
  when no OpenXR runtime is active.

Preparing it found five faults the desktop couldn't show. The XR
thumbsticks weren't wired to the hands. The fingertips were invisible.
V-Sync stayed on in a headset, which would have held it to the desktop
monitor's refresh. A thumbstick resting off centre would have turned the
spacecraft in CMC MODE FREE. And a runtime that stops the session when
the headset comes off would have cut the record short. All five are
fixed, and a test now runs the main scene's headset branch against a
stand-in for the OpenXR interface.

What needs a person: the sitting itself, and the rows only a tester can
judge (reach from each couch, legibility, comfort over ten minutes, no
flip on hover).

Every checklist is now worked from the cabin.
`tests/scenarios/test_cabin_checklists.gd` flies each one from the
commander's couch through the desktop rig, until the card shows it
complete:

- **Parking orbit and TLI**: V82 on the DSKY after cutoff, then CSM/LV
  SEP.
- **LOI-1, LOI-2 and TEI**, each flown down the SPS burn checklist on P40,
  with LM JETT between them.
- **Entry**: an MCC request (none is needed), CM/SM SEP, P61, ELS LOGIC
  and AUTO, and on to splashdown.

Mission Control's PADs, NEXT STEP and CHECKLIST come from the wrist menu.
The simulator's SPS cutoffs leave under 0.2 ft/s to trim, so LOI-1 is
cut off 0.5 ft/s short, and the crew trims it with the translation
controller on the keys.

Writing the test found two things:

- **The checklist book lost its place.** It did when the crew turned to
  the SPS burn checklist and back. Now CHECKLIST turns to each checklist
  where it was left, and a finished one starts again, as the SPS burn
  checklist does for each burn.
- **P40 belongs near TIG.** Selected when the PAD arrives, its steering
  holds the burn attitude for hours, and the clock can only take fine
  steps meanwhile. The crew selects it about a quarter of an hour before
  TIG, time enough for the maneuver to the burn attitude. Between burns
  it drifts in CMC MODE FREE, because an attitude hold in lunar orbit
  limit-cycles and slows the clock the same way. `SimTest.fly_pad()`,
  which the other mission scenarios use, now flies a PAD the same way.
  It also steps into V99 a second at a time, so PRO comes at TIG−5 s and
  the engine lights on time, where it had lit up to 10 s late.
  `test_lunar_mission.gd` went from 130 s to 23 s. TEI now leaves a
  vacuum perigee of 79 km, not −174 km, and one transearth MCC puts it in
  the corridor.

What remains for the milestone is the recorded headset pass.

Today the cockpit is a 2D overlay. `src/presentation/hud.gd` draws the
DSKY, a grid of switches, the FDAI, Mission Control, CAPCOM and the
checklist over the window or chase view of
`src/presentation/space_view.gd`. gemini-capsule is a VR simulator built
on the same Bus and SimClock, and it already has most of the parts a VR
cockpit needs.

### What ports from gemini-capsule

Copy the files rather than share them. A pinned copy keeps this
repository buildable without gemini-capsule, which the README promises.
Pin the copy to one gemini-capsule commit (`40e449c` is its `main`
today) and add the files to the README's "What was taken from the Gemini
template" table. Consider a shared addon only if the same fixes start
landing in both repositories.

| gemini-capsule | What it is | Porting |
|---|---|---|
| `scenes/player/xr_rig.tscn`, `xr_rig.gd` | Seated `XROrigin3D` with two controllers and fingertip interactors. Recentres on session start, on the runtime's recentre and on B/Y | As is |
| `scenes/player/desktop_rig.tscn`, `desktop_rig.gd` | The same interface on the desktop: centre-ray click, scroll and inspection zoom | Without its keyboard head movement: W/A/S/D/Q/E fly the RHC here, and its recentre key R is the THC's +X, so recentre moved to Home. The tests drive this rig |
| `src/interaction/control_base.gd`, `interactor.gd` | Touch volume, crossing direction and far-field click. Nothing changes on hover. Controls lock while `SimClock.controls_locked()` | As is. Apollo's SimClock has the same method; it locks above 100×, Gemini's above 10× |
| `scenes/controls/` | Toggle (two- or three-position, guarded, lever-lock, momentary), rotary, pushbutton (momentary or latching, with a lamp), circuit breaker, pull handle, telelight switch | Toggle, rotary and pushbutton as is. The breaker without the overhead face drawn for Gemini's SC-4 panel. The pull handle (Gemini's O2 recock grip) and the telelight switch (Gemini's sequence lights) stay behind |
| `scenes/instruments/` | Lamp, numeric display, clock, flag, round gauge, telelight, FDAI | The telelight stays behind with the telelight switch. Three need adapting. `lamp.gd` uses Gemini's `CabinMaterials`. `numeric_display.gd` calls `Units.convert()`, which Apollo's `Units` lacks. `fdai.gd` uses `Frames.BODY_TO_GODOT` and reads `guid.indicator.attitude`, which Apollo doesn't publish. Its ball also shows the outside view, so pitch and yaw read reversed, and it ignores how its case is mounted; Apollo's copy fixes both |
| `src/cabin/cockpit_layout.gd`, `assets/data/cockpit/controls.csv`, `channels.csv` | Data-driven panels: one validated CSV row per control, with its source and confidence | Done in 2c. Rows are checked against `CmCabin`'s panels and the channel types instead of a cabin datum and a cockpit spec; `spec_id` waits for a CM cockpit spec |
| `src/interaction/hand_controller_input.gd` | Thumbsticks to the hand-controller channels | Gemini writes `ctl.hand_controller.pitch`, `.yaw` and `.roll`. Apollo reads `ctl.rhc` (roll, pitch, yaw) and `ctl.thc` (X, Y, Z) as `Vector3`s |
| `openxr_action_map.tres`, the `[xr]` block of `project.godot`, `export_presets.cfg` | Action map with the Touch, Index, Vive, Vive Focus 3, WMR and Pico profiles among others; OpenXR settings; PC VR and Quest 3 presets | All in. gemini-capsule's docs describe a seated `LOCAL` space, but its `project.godot` sets `xr/openxr/reference_space=1`, which Godot 4.4.1 reads as Stage (the options are Local, Stage, Local Floor). Apollo uses 0, Local, and leaves OpenXR off until `--xr-mode on`. The PC VR presets came with the 2e preparation; the Quest preset stays behind |
| `src/presentation/wrist_menu.gd`, `comfort.gd`, `gaze_tooltip.gd`, `checklist_highlight.gd`, `vr_acceptance_recorder.gd`, `perf_monitor.gd` | Wrist menu, vignette, tooltips, next-control highlight, headset acceptance recorder, frame-time budget | All in: the wrist menu and the highlight in 2d, the rest with the 2e preparation. The highlight takes a step's `control` or looks up the control for its check channel in `controls.csv`. `comfort.gd` reads `dyn.omega`, `dyn.g_load` and `guid.indicator.attitude` in place of Gemini's `guid.rate.*`, `aero.q_dyn_pa` and `guid.att.lvlh`, and the recorder checks Apollo's controls in place of Gemini's `ctl.ace.power` |
| `docs/VR_INTERACTION.md`, `HEADSET_RUN.md`, `VR_ACCEPTANCE.md` | Interaction rules and the headset acceptance run | Rewritten for the CM |

None of this has a recorded headset pass yet. gemini-capsule's
`docs/CURRENT_GATES.md` (2026-09-22) still lists headset acceptance as
its first open gate. One sitting can serve both projects: run
gemini-capsule's `HEADSET_RUN.md`, then Apollo's.

### What's new for Apollo

- **A fixed cabin.** `space_view.gd` moves its camera with the
  spacecraft's attitude through render space, whose axes are ECI. A VR
  camera belongs to the headset, and gemini-capsule never moves it from
  code (`VR_INTERACTION.md` §4). So the cabin sits at the render origin,
  and the Earth, Moon, Sun and sky turn around it by the inverse of
  `dyn.att_q`. gemini-capsule's `scenes/world/world.gd` does this. The
  chase view stays on the desktop.
- **The CM cabin.** Three couches, the main display console and the
  five windows. The player sits in the left (commander's)
  couch, with the rotation controller on the right armrest and the
  translation controller on the left. Take panel identity from the CSM
  Apollo Operations Handbook. Mark dimensions `[estimated]` until
  drawings are transcribed, as gemini-capsule's `controls.csv` does.
  Built in 2c as a blockout; the panel assignment follows the CM in
  outline only, and the handbook pass is still to do.
- **Every HUD control in the cabin.** Give every control `hud.gd` offers
  a `controls.csv` row: ΔV THRUST A and B, THRUST ON, ATT SOURCE, CMC
  MODE, RCS QUAD A to D, FC 1 to 3, BATT TO BUS, ELS LOGIC, ELS AUTO,
  DROGUE, MAIN CHUTES, CSM/LV SEP, LM JETT and CM/SM SEP. ATT SOURCE and
  BATT TO BUS each stand in for several real switches, so mark them
  `proxy`, as gemini-capsule does for such rows.
- **A cabin DSKY.** Build the 19 keys from the pushbutton prefab. Each
  key calls `Dsky.press()` from the prefab's `activated` signal, the
  same call the 2D panel and the tests make. For the displays, publish
  the DSKY's state on the Bus: PROG, VERB, NOUN, R1 to R3, the flash and
  the lamps. Done in 2c: the lamps are the lamp prefab, and the
  electroluminescent fields are labels bound to the `dsky.*` strings, so
  the numeric display needed no text mode. `DskyPanel` still reads the
  `Dsky` object directly.
- **The FDAI.** Publish the attitude the ball shows, so the 3D FDAI
  prefab can read it. That's LVLH-relative today, as Apollo's
  `src/presentation/fdai.gd` computes it, and relative to REFSMMAT after
  slice 4c. The CMC publishes it as `guid.indicator.attitude` since 2c.
- **Hand controllers.** Thumbsticks write `ctl.rhc` and `ctl.thc` first,
  as in gemini-capsule. A grabbed RHC and THC come later; gemini-capsule
  hasn't built grab interaction either.
- **Mission Control, CAPCOM and the checklist.** Put the checklist and
  the CAPCOM log on a readable card. The PAD requests (MCC, LOI-1, LOI-2,
  TEI), time rate, pause, recentre and eye height go on the wrist menu.
  Done in 2d; the eye height isn't saved between sessions yet.
- **Comfort.** The cabin is the fixed frame and only the windows move.
  The vignette follows body rate and entry g. Done with the 2e
  preparation, with the horizon ring and authentic mode.

### Slices

| Slice | Work | Check |
|---|---|---|
| 2a (done) | Port the rigs, the interaction layer, the prefabs and the action map, with adapters for `ctl.rhc`, `ctl.thc`, `Units`, materials and frames | The ported `test_xr_rig.gd`, `test_openxr_action_map.gd` and `test_control_library.gd` (minus its Gemini electrical cases) pass headless |
| 2b (done) | Fixed cabin in `space_view.gd` | New test: turning `dyn.att_q` moves the Earth, Moon, Sun and sky but not the camera or the cabin (gemini-capsule's `tests/unit/test_world_presenter.gd` is the model). `tools/screenshot.tscn` still renders the same window view |
| 2c (done) | CM cabin, `controls.csv`, cabin DSKY and FDAI | Every row round-trips from CSV to node to Bus. A scenario test flies an MCC PAD with P30 and P41 using only cabin controls, through the desktop rig |
| 2d (done) | Checklist and CAPCOM card, wrist menu | Desktop-rig test: request a PAD from the wrist menu, then see UPLINK ACTY on the cabin DSKY and the PAD on the card |
| 2e (prepared) | Headset run | One recorded pass of an Apollo `VR_ACCEPTANCE.md` in a headset, including a verb/noun typed on the cabin DSKY with a fingertip |

**Done when** a crew member can do every action in
`data/missions/apollo_11/checklists.json` from the couch, a scenario
test does them through cabin controls, and one headset pass is recorded.
The 2D HUD stays as the desktop fallback.

### Risks

- **The DSKY.** Its keypad is small and dense, and the crew types on it
  constantly. Fingertip typing is the first thing to try in the headset,
  from the centre couch: it is out of reach from the commander's.
- **Frame time.** The procedural Earth, Moon and star shaders have never
  been measured at 90 Hz in stereo. `perf_monitor.gd` is ported: the
  wrist menu shows the worst frame of the last 90, and the recorder
  counts the frames over 1.5 times the headset's budget.

## 3. The LM and a lunar landing

**Status: done. The LM undocks, flies free and docks again, flies DOI on
its own computer, lands at Tranquility Base, lifts off to orbit at the
time the RTCC gives, and flies the rendezvous back to Columbia, which
docks with it (slices 3a to 3e). Slice 3f has given Mission Control its
timeline from undocking to TEI, the LM its start phases `lunar_descent`,
`lunar_surface` and `lunar_ascent`, and the player Eagle's cockpit on the
desktop, Eagle's checklists and Eagle's cabin, each checklist flown from
the HUD and from the cabin. Flying Eagle in a headset waits on the
headset run, with milestone 2's (slice 2e).**
Before 3a the LM was only mass: 15,103 kg added in the `csm_lm`
configuration (`data/spacecraft.json`) and dropped at LM JETT before TEI.

Slice 3a makes it a second vehicle:

- **Two vehicles.** Dynamics owns both. The CSM keeps its channels
  (`dyn.*`), and the free LM (`src/dynamics/vehicle.gd`) publishes the same
  ones as `lm.dyn.*`. It has no systems yet: it coasts, holding the
  attitude it undocked in.
- **Undocking.** UNDOCK, on the HUD and on the main display console,
  splits the stack with its momentum conserved, and the probe pushes the
  vehicles apart at 0.03 m/s.
- **Docking.** `src/dynamics/docking.gd` places each docking port on its
  vehicle and publishes where the LM's port is from the CSM's (`dock.*`),
  which the flight panel reads out. A contact within the capture limits
  (closing under 0.3 m/s and across under 0.15 m/s, within 0.3 m of the
  drogue's centre, 10° of alignment and 1°/s of relative rate) docks the
  vehicles again. Any other contact rebounds, and CAPCOM says why. The
  geometry and the limits are estimates.
- **The coast-step policy holds for both vehicles.** A coast step is taken
  only while both coast, and it is no longer than either trajectory
  allows, or than a second while they are within 200 m of each other.
- **Checkpoints are schema 2**: a map of vehicles, each with its dynamics
  and systems. Schema 1 checkpoints are rejected.
- **The space view** draws the free LM where it flies and turned as it
  is.

The scenario test (`tests/scenarios/test_docking.gd`) undocks in lunar
orbit, flies an equiperiod separation (0.6 m/s radially down) and coasts
a revolution. Half a revolution on, the CSM is 2,721 m farther ahead of
the LM, where the linear (Clohessy-Wiltshire) solution puts it
(2,723 m), and a revolution on it is back within 5 m. A checkpoint taken
mid-revolution flies on as the uninterrupted run did, and the CSM docks
again on the translation controller.

Writing it showed how to hold station in orbit. Held still inertially 21 m
behind the LM, the CSM is not on the LM's orbit. In the LM's turning
local frame it moves at 0.02 m/s, which added 3 % to the separation, and
the two orbits' periods differed by about 10 ms, which is 16 m of drift
a revolution. The test's pilot holds station in the local frame, as a crew
would, flying against the horizon.

Slice 3b gives the LM its own systems:

- **One AGC core, two computers.** `src/systems/agc_core.gd` holds the
  verb/noun dialogue, the program table and alarms, P30, the thrusting
  programs, P47 and the DAP. The CMC (`agc.gd`, Colossus) and the LGC
  (`lgc.gd`, Luminary) each add their own programs, engines and
  controls. The CMC flies as it did: the scenario suite prints the same
  numbers, digit for digit.
- **The LGC** reads the LM's truth (`lm.dyn.*`) and writes `lm.guid.*`
  and `lm.dsky.*`, on its own DSKY. It has P00, P30, P40 on the descent
  engine, P41 on the LM RCS, P42 on the ascent engine and P47. It powers
  up as the LM undocks and holds the attitude it undocked in.
- **The LM's systems**: the descent engine, throttleable from 10 % to
  60 % (`dps.gd`), the ascent engine (`aps.gd`), and the RCS, two
  systems of 100 lbf jets (`lm_rcs.gd`). They fire only while the LM
  flies free. The LM's mass, docked or free, follows its own tanks.
  STAGE leaves the descent stage behind, and the docking port stays
  where it was.
- **DOI.** `Rtcc.plan_doi()` sizes a retrograde burn on the descent
  engine to put the next pericynthion at 50,000 ft, flying the throttle
  schedule the LGC flies: 10 % for 15 s, then 40 %, as Apollo 11 did.
  Mission Control uplinks the PAD to the LGC.
- **Checkpoints stay schema 2.** Each vehicle's entry carries its own
  systems: the LM's while it flies free, the CSM's with the docked LM's
  among them, as its mass is part of the CSM's configuration. A 3a
  checkpoint restores as it was saved (its LM had no systems, so full
  tanks).

The scenario test (`tests/scenarios/test_doi.gd`) undocks Eagle, uplinks a
DOI PAD (71.6 ft/s, 29 s) and flies it on the LGC. Half a revolution
later Eagle passes its pericynthion at 15,197 m, 43 m under the PAD's
15,240 m, a second after the PAD's time. Columbia's orbit is untouched.
`tests/scenarios/test_lm_burns.gd` flies P41, P47, staging and P42, and
the LM's autopilot.

Slice 3c lands it:

- **A Moon-fixed frame.** `Bodies.moon_fixed()` turns the Moon
  synchronously, its pole on the normal of its orbit, and the space view
  draws the Moon with it.
- **The orbit over the site.** LOI adds an out-of-plane component that
  turns the orbit about the burn point to pass over Tranquility Base at
  Apollo 11's landing time, 102:45:40. The `lunar_orbit` phase starts in
  such an orbit, with the site at the ground track's northernmost point,
  so it stays over the site for revolutions either side. The DOI PAD
  flies the landing pass nearest that time. It centres the burn half a
  revolution before a pericynthion 470 km (ground range) short of the
  site, and uplinks the site to the LGC.
- **Powered descent.** P63's ignition algorithm finds TIG 470 km out.
  After 26 s at 10 % throttle, Klumpp's quadratic guidance brakes at full
  thrust until the throttle comes back into its range, about 2 min before
  high gate. P64 flies the approach from high gate, 2 km up and 8 km out.
  P65 (not in Apollo's flown sequence, which went to P66 by hand) lands
  automatically, stopping the drift and slowing the descent to 0.8 m/s.
  The first ROD click hands over to P66: the crew flies the attitude,
  and the throttle holds the descent rate, 1 ft/s per click. At
  touchdown, P68 shuts the engine down. The guidance's targets are this
  simulator's own, designed with a Python model of the descent before
  they went into the LGC. The model landed within 3 m across 455 to 520 km
  of PDI range, 5 km of crossrange, 14.5 to 16 km of PDI altitude and a
  slower autopilot.
- **The surface.** The real one, from NASA's elevation maps
  (`src/dynamics/terrain.gd`, `data/terrain/`, built by
  `tools/terrain/build_terrain.py`). Around the site it is LROC's 2 m
  terrain model of the Apollo 11 site, resampled to 4 m, with West crater
  30 m deep 550 m east of the LM. Along the approach it is SLDEM2015 at
  59 and 118 m, elsewhere LOLA at 1°. Tranquility Base lies 1,927 m
  below the 1737.4 km reference sphere, and the DOI now targets 50,000 ft
  above the site, as Apollo's did. CONTACT LIGHT comes on when a probe
  touches, and touchdown is when the footpads do. The landed LM sits on
  its gear and turns with the Moon, and when its engine's thrust exceeds
  its weight for half a second it lifts off. ENGINE START and ENGINE STOP
  start and stop an armed engine by hand.
- **The LGC's own navigation** (part of slice 4b, for the LGC). It flies
  on its own state vector, never truth: the CSM's at undocking, then the
  ground's. The PDI PAD uplinks it with MSFN's tracking error, set in
  `mission.json` where it meets PDI (250 m along track, 150 m across and
  900 m high). The LGC coasts it with its own integration and adds the
  sensed ΔV.
- **The landing radar** (part of 4d). Its beams measure the slant range
  to the real ground and the velocity over it; its antenna tilts for
  braking and turns straight down from P64. The DSKY's ALT and VEL lamps
  go out as its data come good, and N63 shows ΔH. With V57 the LGC
  weights the radar's altitude and velocity into its state vector every
  2 s. It has no terrain model, as Apollo 11's LGC had none, so the
  ground's dips and rises along the approach reach its altitude.
- **Landing point redesignation.** In P64, with the mode switch in AUTO,
  each click of the ACA moves the landing point 0.5° along the LPD scale
  on the commander's window, or 2° in azimuth. N64 shows the time left and
  the LPD angle.

`tests/scenarios/test_landing.gd` is the check. From a checkpoint before
PDI:
- The automatic run keys V57 when the radar's altitude comes good, 11 km
  over the ground, with ΔH at −954 m. ΔH is −22 m by high gate.
- It lands 140 m from the site at 0.80 m/s down and no drift, 12 min 6 s
  after PDI, with 687 kg of descent propellant left. The miss is the
  crossrange error, which the radar can't see.
- Without V57, Eagle hits the ground 4 km short at 24 m/s.
- With a 900 m error along the track, the commander redesignates 19 times
  in P64, moving the landing point 804 m, and Eagle lands 2 m from the
  site.
- The P66 run takes over at 150 m with scripted hand-controller and ROD
  inputs and lands at 0.77 m/s down.

Slice 3d lifts it off:

- **The liftoff time.** `Rtcc.plan_liftoff()` flies the LGC's own ascent
  from where Eagle sits, and finds the liftoff, in the first window ten
  minutes out or later, that has Columbia 16.4° ahead at insertion
  (`mission.json` "ascent"). That lead is estimated: flying Apollo 11's
  coelliptic sequence (CSI circularizing at the first apolune, TPI at
  26.6° elevation), it puts TPI 2 h 35 min after insertion, where Apollo
  11 flew it. The ascent PAD uplinks the liftoff time with Eagle's and
  Columbia's state vectors, as the truth.
- **P12.** V06N33 shows the liftoff time and V06N76 the targets
  (5,535 ft/s, 32 ft/s up, and the LM's distance from Columbia's plane).
  V16N74 counts down, and V99N74 comes five seconds out, when the crew
  stage with ABORT STAGE, arm the ascent engine and PRO: "Abort Stage,
  Engine Arm, Ascent, Proceed", as Aldrin called it. The LM rises
  vertically to 40 ft/s up while it yaws to face along Columbia's track,
  then pitches over.
- **E guidance** (`src/systems/ascent_guidance.gd`, after Cherry's,
  which Luminary's P12 flew). The thrust's radial and out-of-plane parts
  follow acceleration profiles linear in time, which reach 60,000 ft and
  32 ft/s up in Columbia's plane as the time to go runs out. The rest of
  the thrust is horizontal, and the time to go comes from the rocket
  equation. The steering is held for the last 2 s, and the engine is cut
  off with its tail-off's lead. The LM's +Y axis stays along Columbia's
  orbit normal, so it pitches over without rolling and reaches orbit
  windows down.
- **The CSM's state vector in the LGC** (`Lgc.csm_nav`), which the
  rendezvous programs of slice 3e will use.

As with the descent, the guidance flew in a Python model first. It
inserted within 15 m and 0.15 m/s of its targets, 425 s after ignition,
with 183 kg of propellant left.

`tests/scenarios/test_ascent.gd` is the check. Eagle is set down at the
site (the landing is 3c's check):
- The RTCC's PAD: liftoff in the first window, Columbia 16.4° ahead at
  insertion, and a 9.0 × 44.8 nmi orbit predicted.
- P12 lifts off 0.7 s after TIG, rises for 8 s to 59 m, and cuts off
  7 min 8 s after liftoff (Apollo 11: 7 min 17 s). It inserts at
  60,054 ft and 32.1 ft/s up into a 9.0 × 45.1 nmi orbit above the site,
  0.001° from Columbia's plane, with Columbia 16.42° ahead and 167 kg of
  the ascent engine's propellant left. After the pitchover the LM turns
  at under 1°/s.
- A checkpoint taken 200 s into the ascent flies on to the same
  insertion.

Writing it showed that the LM's roll must come from the plane, not from
the direction of flight. Taken from downrange, the +Z axis swung 180° as
the thrust passed the horizontal near insertion, and the LM reached orbit
rolling at 4.5°/s.

Slice 3e flies the rendezvous:

- **Targeting** (`src/systems/rendezvous.gd`), which the RTCC and the
  LGC share, flown on the flight model:
  - CSI is a horizontal burn at the LM's first apolune. It is sized so
    that, with CDH half a revolution on, the CSM stands 26.6° above the
    LM's horizon at TPI's time.
  - CDH puts the LM on an orbit a constant height below the CSM's. Its
    semi-major axis is the CSM's less that height, and its radial
    velocity is the CSM's there, scaled by (a_CSM / a_LM)^1.5.
  - TPI comes when the CSM rises to 26.6°, with the transfer that meets
    it after it has flown 130°, found by Newton's method on the miss.
  - The midcourse corrections aim at the same meeting.
- **The CSI PAD.** `Rtcc.plan_rendezvous()` flies the sequence from both
  vehicles' state vectors, with TPI 2 h 35 min after insertion, as Apollo
  11 had it. The ground uplinks CSI's and TPI's times, and Columbia's
  state vector as MSFN tracked it, 914 m off, most of it along the track
  (`mission.json` "rendezvous").
- **The rendezvous radar** (`src/systems/rendezvous_radar.gd`) measures
  the range, the range rate and the line of sight to Columbia, out to
  400 nmi, unless the Moon is in the way.
- **P20** marks once a minute. The first mark after an uplink takes the
  radar's relative position outright. Later marks weight it by half, and
  move the velocity by the position's residual and the range rate's.
  V16N54 shows the range, the range rate and Columbia's elevation, and
  V06N49 the last mark.
- **P32 to P35** target each burn with Luminary's displays (N11, N13,
  N37, N55, N58, N75 and N81), and P41 flies it on the RCS.
- **Checkpoints are schema 3.** They carry the LGC's rendezvous state,
  and schema 2 checkpoints are rejected. Restored, the rendezvous radar
  measures again from the restored vehicles.
- **Braking and docking.** From a mile out, the test's commander brakes
  on the TTCA by the gates (30 ft/s from a mile, 20 from 3,000 ft, 10
  from 1,500 ft, 5 from 500 ft), nulling the line of sight's drift, and
  stops 40 m out. Eagle turns its docking port to Columbia, and Collins
  flies the probe into the drogue.

As with the descent and the ascent, the sequence flew in a Python model
first.

`tests/scenarios/test_rendezvous.gd` is the check. From Eagle's insertion
(the ascent is 3d's check):
- The CSI PAD: CSI 52.3 ft/s, 50 min 50 s after insertion (Apollo 11:
  51.5 ft/s, 50 min 18 s), 15 nmi below Columbia, then TPI 24.0 ft/s and
  30.9 ft/s to brake (Apollo 11: TPI about 25 ft/s, and closing at 31 ft/s
  0.7 mile out).
- In 12 marks, P20 takes Columbia's 914 m error down to 0.2 m relative
  to Eagle. What is left against the truth, 4 m, is Eagle's own
  navigation error, which the rendezvous doesn't feel.
- The LGC flies the sequence: CSI 52.3 ft/s, then CDH 2.1 ft/s onto an
  orbit 14.6 nmi below Columbia's. TPI is 24.0 ft/s, 18 s before the
  plan's time, and the midcourse corrections are 0.2 and 0.1 ft/s.
  Braking takes 15 min, and station-keeping begins 45 min after TPI
  (Apollo 11: 15 min and 48 min). Collins docks at 0.33 ft/s, dead
  centre.
- Eagle's ΔV from insertion to station-keeping is 116.0 ft/s, 6 % over
  the RTCC's plan of 109.1 ft/s. The check allows 20 %.

Writing it showed that the targeting needs doubles. CDH's ΔV, taken as
the difference of two single-precision velocities of 1.6 km/s, was off
by up to a tenth of a millimetre per second. That moved Columbia's
elevation at TPI by 10⁻⁵ radians from one trial to the next, noise the
secant method could not solve through, so the LGC found no CSI solution
from its own state vectors. With the ΔV in doubles, CSI converges to
10⁻⁷ radians.

Slice 3f's first part gives Mission Control its timeline and the LM its
start phases:

- **The timeline** (`mission.json` "lunar_timeline") runs from undocking
  to TEI. Each entry comes at an Apollo 11 GET, after a mission event, or
  before a time the ground has planned, and only if its condition holds
  then. CAPCOM makes the call, and the ground uplinks the PAD.
  - The GO calls come as long before each burn as Apollo 11's did: 18 min
    21 s before DOI, 4 min 57 s before PDI and 12 min 48 s before CSI.
  - The STAY calls come as long after touchdown as Apollo 11's did.
  - The ascent and TEI PADs take the opportunity nearest Apollo 11's
    times.
  - No PAD comes while the ground's last of its kind is still to be
    flown, so a test that asks for its own PAD doesn't get a second one.
    Nor does an undocking a day early bring a DOI PAD.
- **The flight phase follows Eagle** in lunar orbit: `lunar_descent`
  from DOI (its perilune under 50 km) to touchdown, `lunar_surface`
  while it is landed, and `lunar_ascent` from liftoff to docking.
- **The start phases** are flown on from the `lunar_orbit` start, docked
  until Apollo 11's undocking at 100:12:00, then through the timeline and
  the RTCC's own solutions.
  - `lunar_descent` starts 20 min before PDI, after the DOI PAD flown as
    the RTCC models the burn.
  - `lunar_surface` starts 10 min after Eagle is set down on the site, at
    the time DOI planned for.
  - `lunar_ascent` starts 20 min before the liftoff the ascent PAD gives.
- **Checkpoints are schema 4.** They carry Mission Control's planned
  times and the timeline's progress.

The start phases run half an hour ahead of Apollo 11. The landing pass
nearest 102:45:40 lands at 102:11:34, and the ascent window nearest
124:22:00 opens at 123:51:27.

The checks:
- `tests/scenarios/test_landing.gd` now starts from `lunar_descent`, and
  lands as it did: 140 m from the site at 0.80 m/s down.
- `tests/scenarios/test_rendezvous.gd` starts from `lunar_ascent`. It
  flies P12 and the rendezvous to docking as 3e's check did: CSI
  52.3 ft/s, TPI 24.0 ft/s, capture at 0.33 ft/s, and Eagle's ΔV 4 %
  over the plan. Then comes GO for jettison, and after LM JETT the TEI
  PAD, for 134:41:44.
- `tests/scenarios/test_lunar_timeline.gd` follows the timeline from
  `lunar_orbit`, checks each LM start phase, and restores a checkpoint
  mid-timeline.

Slice 3f's second part puts the player in Eagle:

- **Who flies what.** The player moves to the LM as it undocks, as its
  commander, and back to the CSM when the two dock or the LM is
  jettisoned (`src/presentation/vehicle_switch.gd`). While the LM flies
  free, L changes vehicles on the desktop. The vehicle left behind flies
  on as its computer and switches have it. In a headset the player stayed
  in the CM until the fourth part, below, gave the LM its cabin.
- **The LM's cockpit** came first as a desktop overlay (the fourth part,
  below, added its cabin). In Eagle the HUD shows the LGC's DSKY, which
  the keys type into, and the LM's switches: the LGC's mode, ENGINE ARM,
  ABORT STAGE, ENGINE START and STOP, the RCS systems and the ROD
  switch. It also shows the LM's flight data and systems, and Mission
  Control's LM PADs. The FDAI shows Eagle's attitude and rates and its
  LGC's errors. The hand controllers fly its ACA and TTCA, about and
  along its axes.
- **The view from Eagle** is out of its forward windows, or a chase view
  above 40 km. Near the Moon the ground below the LM, drawn from the
  height maps (`src/presentation/lunar_ground.gd`), takes the place of
  the Moon's sphere. The sphere's flat facets lie up to 2 km under the
  surface they stand for, and within 1,927 m of the site the LM is inside
  the sphere, so the Moon wasn't drawn at all. The ground is a grid of
  rings around the point below the LM, fine near it and coarse out past
  the horizon. It is built on a worker thread, with the heights the gear
  lands on. On the surface the view takes Eagle's position in the
  Moon-fixed frame. Its ECI position, turned through a single-precision
  Basis, moves by centimetres from step to step, and the ground would
  shake with it.

The checks: `tests/unit/test_vehicle_switch.gd` and
`tests/unit/test_lunar_ground.gd`; the space view from Eagle on the
surface and in orbit (`tests/unit/test_space_view.gd`); and the main
scene started in `lunar_descent`, with Eagle's HUD, the keys on the LGC,
its two views and L between the vehicles (`tests/unit/test_main_scene.gd`).

Slice 3f's third part gives Eagle its checklists, and checks that you
can fly them yourself:

- **Eagle's checklists** (`data/missions/apollo_11/lm_checklists.json`):
  the undocking and DOI, the powered descent from P63 to P68, the surface
  stay and P12 to orbit, and the rendezvous from P20 through CSI, CDH,
  TPI and the two midcourse corrections to braking and docking. Every
  step checks itself off on the Bus: the LGC's program and step and its
  stored maneuver, the switches, the engines, the landing, liftoff and
  insertion, Mission Control's PADs and calls, and the docking. The LGC
  now publishes V57's radar updates and P20's marks being taken
  (`lm.guid.lr_update`, `lm.guid.rr_nav`) for them. Between burns they
  put the LGC in free drift [simplified: each firing of an attitude
  hold's jets drops time acceleration back to 10×; in free drift it
  stays].
- **Each vehicle its own checklists.** A checklist names the flight
  phases it is for, in place of the book's table of them. The HUD shows
  the checklists of the vehicle you fly. At the start both vehicles'
  open the one for the phase, and so do the ones of the vehicle you
  board as Eagle undocks or docks (`VehicleSwitch.boarded`). L goes back
  to the other's where they stood, and both keep up with the Bus
  whichever shows.
- **The check** (`tests/scenarios/test_lm_checklists.gd`). The main
  scene runs in a viewport of its own, worked as a player at the desktop
  works it (`tests/desktop_test.gd`): the DSKY on the keys through the
  scene's input, the HUD's buttons clicked where they show and its
  switches set, and the braking and the docking on the hand controllers'
  keys. Each of Eagle's checklists is flown from its phase's start until
  the HUD shows it complete.
  - From `lunar_orbit`: CMC MODE FREE and UNDOCK in Columbia at GO for
    undocking, and DOI down the first checklist, to a pericynthion
    15,286 m above the site.
  - From `lunar_descent`: P63 to P68, V57 when the radar has the ground,
    and a landing 140 m from the site.
  - From `lunar_surface`: STAY for T3, the ascent PAD, and P12 to a
    9.0 × 45.0 nmi orbit.
  - From `lunar_ascent`: the liftoff again, then the rendezvous as the
    LGC flew it in 3e (CSI 52.3 ft/s, TPI 24.0 ft/s), braked by the
    gates on the keys in 15 min 23 s. After L, Columbia docks at
    0.33 ft/s.

  Writing it showed that most of what the DSKY's keys do reaches the Bus
  at the computer's next step, 20 ms on; only a program change goes at
  once. The test gives each typed sequence that step.

Slice 3f's fourth part puts the player in Eagle's cabin, from milestone
2's prefabs, so the LM can be flown in a headset:

- **The cabin** (`src/cabin/lm_cabin.gd`). A blockout of the ascent
  stage's crew compartment, a cylinder 92 in across and 42 in deep lying
  fore and aft, and the midsection behind it under the docking tunnel. It
  has the two triangular forward windows, the overhead docking window and
  the forward hatch. The commander stands on the left and the LM pilot on
  the right, 1.6 m above the floor, each with an ACA at the right hand
  and a TTCA at the left. Panels 1 to 5 are where the LM's panel
  descriptions put them, at estimated positions. The cabin is built from
  the docking port, in the LM's body axes, and stays about the centre of
  mass as the LM stages. CmCabin and LmCabin now share `src/cabin/cabin.gd`
  (the anchor, the seats, the card's mount and the panels).
- **Its controls** (`data/cockpit/lm_controls.csv`, checked by the same
  CockpitLayout against `channels.csv`):
  - Panel 1: the mission timer, the rendezvous radar's range and range
    rate, the descent engine's thrust, the FDAI on the LGC's attitude,
    LUNAR CONTACT, ENG ARM (lever-locked) and ABORT STAGE.
  - Panel 2: the LM pilot's FDAI and LUNAR CONTACT, and RCS SYS A and B.
  - Panel 3: LGC MODE.
  - Panel 4: the LGC's DSKY, with its ALT and VEL lamps below TRACKER.
  - Panel 5: ENGINE STOP and START and the DES RATE switch.
  
  Every switch on Eagle's HUD has a cabin control. A toggle can now
  publish a value for each position, which ENG ARM (DES, OFF, ASC) and
  DES RATE (−1, 0, +1) need. Eagle's checklist steps name the control
  they're done on, 57 of them in all.
- **The landing point designator.** Its marks on the commander's window
  are every 5° from 0 to 65° below the LM's +Z, as seen from the
  commander's eye, the angle the LGC's N64 gives. The window is square to
  +Z, so a mark's height holds whatever the landing point's azimuth.
- **The view from inside.** The rig moves to the cabin of the vehicle
  flown, with the checklist card, the highlight and the wrist menu, whose
  PAD buttons ask for Eagle's PADs (DOI, PDI, ASCENT and CSI). SEAT goes
  to the LM pilot's station. C cycles Eagle's window, chase and cabin
  views, and a headset boards Eagle as the desktop does. In the cabin the
  eye is 1 to 2 m from the centre of mass, and the space view draws the
  ground about it. Near the surface the ground's scale keeps it 2.2 m
  below the eye, under the floor, and Columbia is drawn no nearer than
  2.8 m, outside the cabin. The comfort aids read Eagle's rates and
  attitude. Both cabins sit at the render origin, so a hidden control
  now takes no pointer or gaze ray, and the cabin of the vehicle not
  flown can't stop one meant for the other.
- **The headset run.** `HEADSET_RUN.md` gains a short second run in
  Eagle, from `lunar_descent`, and `VR_ACCEPTANCE.md` rows E1 to E5. The
  recorder fills in their evidence: the recentres made aboard Eagle, a
  verb and noun typed on the LGC's DSKY, and the touches on Eagle's
  switches.

The checks:
- `tests/unit/test_lm_cabin.gd`:
  - The commander's eye and panels, and the shell's areas less its
    openings.
  - The LPD marks, the two stations and their reach.
  - The cabin kept about the centre of mass as the LM stages.
- `tests/unit/test_cockpit_layout.gd`: Eagle's layout validates and
  round-trips, and the desktop rig reaches each of its controls.
- `tests/unit/test_space_view.gd`: the ground and Columbia drawn outside
  the cabin on the surface.
- `tests/unit/test_main_scene_xr.gd`: a headset boarding Eagle.
- `tests/scenarios/test_vr_acceptance_recorder.gd`: aboard Eagle, a
  recentre, V16N43 on its DSKY and ENG ARM count as Eagle's rows.
- `tests/scenarios/test_lm_cabin_checklists.gd` flies Eagle's four
  checklists from the cabin, through the desktop rig. The flights are the
  HUD's own (`tests/lm_checklist_flights.gd`), and they come out as they
  do from the HUD, number for number. At high gate the landing site is
  32.7° down the commander's window, and N64 shows 33.

Writing it showed three things:
- **The ground in the cabin.** At the Moon sphere's scale the ground under
  a landed Eagle would be drawn 4 mm below its centre of mass, inside the
  cabin, 1.9 m below the eye.
- **Shadows.** The cabin's shell, at true scale, cast a shadow that
  wasn't Eagle's on that scaled ground. So in the cabin the Sun shadows
  only the cabin, within 3 m of the eye.
- **Cracks.** The bulkheads' chords sat inside the wall's, and the Sun
  showed through the cracks. The bulkheads now reach into the wall.

### What changes underneath

- **Two vehicles at once.** Done in 3a. Today's channels stay the CSM's,
  and the LM's carry an `lm.` prefix (`lm.dyn.r_m`, and `lm.guid.program`
  once it has a computer), which left the existing tests and checklists
  untouched. The coast-step policy (`sys.coast_ok`, `dyn.coast_dt_s`)
  holds for both vehicles, and the snapshot has a map of vehicles
  (schema 2). The LM's systems went into it in 3b, and the LGC's
  rendezvous state in 3e (schema 3).
- **An AGC core with two program sets.** Done in 3b:
  `src/systems/agc_core.gd` under the CMC's Colossus programs (`agc.gd`)
  and the LGC's Luminary programs (`lgc.gd`). Milestone 4 changes the
  core once for both computers.
- **A Moon-fixed frame.** Done in 3c: `Bodies.moon_fixed()`, synchronous
  rotation with the pole on the lunar orbit normal, tagged
  `[simplified]`. Slice 4a swaps in a real rotation model.
- **Lunar orbit over the site.** Done in 3c: LOI turns the orbit over the
  site at the landing time.
- **The surface.** Done in 3c at Tranquility Base (0.674° N, 23.473° E),
  on NASA's elevation maps, with touchdown, CONTACT LIGHT, and a landed LM
  that can lift off. P12 flies it back to orbit since 3d.

### Guidance

| Phase | LGC programs | Basis |
|---|---|---|
| Descent orbit insertion to about 15 km (50,000 ft) | P30, P40 on the DPS | The CMC's P30 and P40 dialogue, with an RTCC DOI PAD |
| Powered descent | P63 braking, P64 approach with landing-point redesignation, P65 automatic landing, P66 rate of descent, P68 landing confirmation, with landing radar updates | Klumpp's Apollo lunar descent guidance (MIT Draper Laboratory, 1971). Done in 3c |
| Ascent to about 9 × 45 nmi | P12, at the RTCC's liftoff time | After E guidance (Cherry, 1964), which Luminary's P12 flew. Done in 3d |
| Rendezvous: CSI, CDH, TPI, two midcourse corrections, braking | P20, P32 to P35, burns flown with P41 on the LM RCS | Luminary GSOP, section 5; the Apollo 11 flight plan. Done in 3e |
| Docking | Manual, with the THC | Done in 3a, and flown after the rendezvous in 3e |

### Who flies what

One person can't fly both vehicles. At undocking the player moves to
the LM, as its commander, and the CSM flies on as its computer and
switches have it. At docking, or when the LM is jettisoned, the player
returns to the CSM. L changes vehicles while the LM flies free, and the
player goes with it to the other vehicle's cabin (slice 3f).

### Slices

| Slice | Work | Check |
|---|---|---|
| 3a (done) | Two vehicles: undocking, independent flight, docking capture, snapshot schema 2 | Test: undock in lunar orbit, separate and coast one revolution; a checkpoint restored mid-revolution matches the uninterrupted run; re-dock within the capture limits |
| 3b (done) | AGC core split. LM data, DPS, APS, LM RCS and LM DAP. LGC P00, P30, P40, P41, P42, P47 | The existing tests pass unchanged. New test: fly a DOI PAD on the LGC to its pericynthion target |
| 3c (done) | Moon-fixed frame, landing site, LOI over the site, P63, P64, P66, P68, touchdown | Test: automatic guidance from PDI to touchdown lands within 500 m of the site at under 1 m/s vertical and 0.5 m/s horizontal speed. A second run flies P66 with scripted hand-controller inputs |
| 3d (done) | Lunar liftoff time from the RTCC, P12 | Test: liftoff to insertion, within set limits of the target orbit |
| 3e (done) | P20, P32 to P35, braking, docking | Test: insertion to docking capture, with total ΔV within a set margin of the RTCC plan |
| 3f (done) | Undocking-to-TEI timeline in `mission.json`; start phases `lunar_descent`, `lunar_surface` and `lunar_ascent`; checklists; CAPCOM; an LM cockpit (desktop overlay first, then cabin prefabs from milestone 2) | The new start phases are built from the earlier ones; every LM checklist is flown from the desktop HUD and from Eagle's cabin; and the full suite passes |

**Done when** `--phase=lunar_descent` lands at Tranquility Base and
`--phase=lunar_ascent` docks with Columbia. The README's Fidelity table
gains DOI, touchdown, insertion and docking rows against the Apollo 11
Mission Report, and "no LM landing" leaves its list of simplifications.

### Risks

- **Size.** This milestone is likely bigger than everything built so far. Land
  3a and 3b before any guidance work.
- **Rendering near the surface.** `space_view.gd` draws the Moon as a
  sphere 2,000 render units from the vehicle, scaled to its true
  apparent size. That works from orbit. At 1 km altitude, though, it
  puts the surface 1.2 units from the vehicle. That's closer than the
  window camera, which sits 3.6 units out along the nose, and at arm's
  length in stereo. The terrain near the site must be drawn at true
  scale around the vehicle; the scaled sphere stays for the far view.
- **The landing radar.** Done in 3c, with the LGC's own state vector for
  it to correct.

## 4. Navigation realism

**Status: begun for the LGC in slice 3c.** The LGC keeps its own state
vector, uplinked with the ground's tracking error before PDI, and the
landing radar updates it (parts of 4b and 4d). The rest is not started.
These are the README's first two simplifications:

- The Moon moves on a circular orbit, and the Sun's direction is fixed
  (`src/dynamics/bodies.gd`).
- Navigation is ideal. The CMC reads truth: `Agc.current_traj()` and
  `_att()` read `dyn.r_m`, `dyn.v_mps` and `dyn.att_q`. REFSMMAT is the
  ECI frame. There are no alignments and no uplinks, and the RTCC plans
  from the true state (`MissionSequencer.request_pad()`).

Much of the crew's flown work between burns was navigation: platform
alignments, sightings and accepting uplinks. Without it, the DSKY is
quiet between burns.

### Slices

| Slice | Work | Check |
|---|---|---|
| 4a Ephemeris | Real Moon and Sun positions for the mission dates, in a dated inertial frame. The Moon-fixed frame from 3c gets a real rotation model. Recommended: Chebyshev coefficients fitted to JPL ephemeris vectors, generated by a script in `tools/`, stored under `data/`, with their provenance in NOTICE | Error against held-out reference vectors stays under 1 km for the Moon's position and 0.01° for the Sun's direction. The scenario suite passes, re-tuned only where the flight really changed. Re-measure the Fidelity table |
| 4b Onboard state | The AGC keeps its own state vectors (the CSM's; the LGC's has done so since 3c, `Lgc.nav`, and it has held the CSM's as the ground uplinks it since 3d, `Lgc.csm_nav`, which it coasts and P20's radar marks update since 3e): it coasts them with its own integration and updates them from sensed ΔV while thrusting (`AgcCore.sense()` already integrates `dyn.dv_step`, and the LGC's `lm.dyn.dv_step`). Every program and noun uses them, never truth. Truth gains small forces the AGC doesn't model (vents, unbalanced attitude jets), with seeded dispersions whose seed is in the checkpoint. The RTCC plans from a tracked state with tracking error. The crew accepts state-vector uplinks through P27 (V71) | Test: after a long coast, the onboard state has drifted from truth by a bounded amount, and an uplink replaces it with the tracked state. The MCC and LOI scenarios pass with an uplink step |
| 4c IMU and P52 | REFSMMATs (launch pad, preferred for each burn, landing site), gyro drift, and ICDU angles and the FDAI relative to REFSMMAT. Gimbal lock costs the alignment instead of only lighting the lamp. An optics view (sextant and scanning telescope) with the 37 Apollo navigation stars; P51, P52, V41 N20 coarse align, N05 star angle difference, N93 torquing angles. Desktop first; in the cabin the optics sit at the lower equipment bay, away from the couch | Test: drift for 12 h, realign with P52 and two star marks, and the residual misalignment is under a set limit. A burn flown on a misaligned platform misses by the amount the misalignment predicts |
| 4d Onboard navigation (stretch) | P23 cislunar sightings and P22 landmark tracking. (In the LM, the landing radar has updated the LGC's altitude and velocity since 3c) | Test: P23 marks alone keep the entry corridor within limits without an uplink |

### What 4a changes elsewhere

- **The parking orbit.** It lies in the Moon's orbital plane today
  (`MissionSequencer._parking_orbit_traj()`), so TLI and MCC planning
  are planar: `Rtcc.plan_mcc()` solves for LVLH X and Z only. Apollo
  11's parking orbit was inclined about 32.5°. With the real geometry,
  TLI needs an out-of-plane solution and the MCC a Y component.
- **The `moon` block in `mission.json`.** Its Moon phase was chosen so
  that TLI falls near 2:44 GET. The real geometry and launch time
  replace it.
- **The Sun angle at the landing site** now follows from the date. The
  landings were timed for a low Sun behind the LM.
- **The analytic references in the propagator's unit tests.** Keep the
  circular model selectable from mission data for the tests that need
  it.

### Order

4a is self-contained. If it lands before 3c, the landing is built once,
on the real Moon. 4b and 4c change every AGC program's inputs, so do
them after the core split in 3b.

## Later, not scheduled

These simplifications stay after all four milestones:

- There's no launch; missions start in parking orbit.
- The S-IVB cuts off TLI on energy instead of flying iterative guidance.
- P40 holds the ΔV direction in LVLH instead of cross-product steering.
- Entry guidance controls drag with bank angle and has no range
  targeting. The atmosphere ignores Earth's rotation and winds.

Also later:

- **Sound.** gemini-capsule synthesises its cabin sounds from Bus
  events in `src/presentation/audio_director.gd`.
- **Other missions.** Apollo 8 flew without an LM, so it could come
  first; Apollo 10 and 12 to 17 need milestone 3. Add them as data under
  `data/missions/`, not as code branches.

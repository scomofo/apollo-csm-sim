# Roadmap

What comes next for the Apollo CSM simulator, in order of value. Written
2026-09-23 against `main` at `23a6b54`; milestones 5 to 7 added
2026-09-26 against `d31d580`. Update each status line as its milestone
moves.

| # | Milestone | Why | Size | Needs |
|---|---|---|---|---|
| 1 | [CI green](#1-ci-green) | Every later change should merge on a green run | No code | The owner protecting `main` |
| 2 | [VR cockpit](#2-vr-cockpit) | Fly from the couch; gemini-capsule already has most of the parts | Medium, mostly porting | 1 |
| 3 | [The LM and a lunar landing](#3-the-lm-and-a-lunar-landing) | The half of the mission the simulator leaves out | Largest | 1; 2 for the LM's own cockpit |
| 4 | [Navigation realism](#4-navigation-realism) | The crew's work between burns, and the README's first two simplifications | Large | 1; slice 3b before 4b |
| 5 | [The whole flight](#5-the-whole-flight) | The flight's remaining simplifications: no launch, the S-IVB's fixed yaw, gravity from two points, P40's LVLH steering, entry without an aim | Largest | 4 |
| 6 | [Sound](#6-sound) | The cabin is silent; gemini-capsule synthesises its sounds already | Small, mostly porting | 1 |
| 7 | [Other missions](#7-other-missions) | Only Apollo 11 flies; the others are data | Large, one mission a slice | 3; 5d for launches |

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
- **CI stays fast.** The suite runs in four jobs side by side: the unit
  tests, and the scenario tests in three parts, dealt out by each file's
  time on the runners (`.github/scenario_seconds.txt`). Keep each job
  under ten minutes: start a long scenario from a phase or checkpoint
  instead of flying the whole mission, record a new scenario file's
  time, and give the scenarios another part when theirs grow past that.

## 1. CI green

**Status: CI passes on every push and pull request. What's left is
protecting `main`.**

`.github/workflows/ci.yml` runs the GUT suite headless in four jobs
side by side, each downloading Godot 4.4.1 (cached) and importing the
project: the unit tests, and the scenario tests dealt out over three
jobs in file-name order, so a new scenario file joins one by itself. The
`test` job passes only when all four have. `lint` runs gdlint, advisory
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
  Built in 2c as a blockout; the AOH Vol 1 §3 handbook pass is done for
  panel assignments (MDC1/2/3 = Panels 1/2/3), while x/y placements stay
  confidence D — Figure 3-1 carries no dimensions.
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
  prefab can read it. It was LVLH-relative until slice 4c, and since then
  it is the CMC's total attitude, relative to the stable member (the
  ICDU angles). The CMC publishes it as `guid.indicator.attitude` since
  2c; the horizon aid reads the LVLH-relative attitude,
  `guid.indicator.lvlh`, since 4c.
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
  draws the Moon with it. Slice 4a gave it the IAU's rotation model.
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
- **A Moon-fixed frame.** Done in 3c: `Bodies.moon_fixed()`, then
  synchronous rotation with the pole on the lunar orbit normal. Since 4a
  it turns by the IAU's rotation model.
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

**Status: done. Apollo 11 flies on JPL's ephemeris, and the CMC flies
on its own state vector, which the ground's uplinks correct, on its own
IMU, which drifts and which P52 realigns on the stars, and on its own
sightings: P23's marks keep the entry corridor without an uplink, and
P22 marks landmarks in lunar orbit. The LGC has flown on its own state
vector since 3c, and its landing radar updates it (part of 4d).** The
milestone began as the README's first two simplifications. 4a took the
first, a Moon on a circular orbit and a Sun whose direction was fixed,
4b the state vector's half of the second, and 4c the IMU's half, for the
CMC: its attitude, its sensed ΔV and its alignments. The LGC's IMU stays
ideal, its alignments with the AOT (P52, P57) left for later.

Much of the crew's flown work between burns was navigation: platform
alignments, sightings and accepting uplinks. 4b gave them the uplinks,
4c the alignments, and 4d the sightings.

Slice 4a puts the flight under the real sky:

- **The ephemeris.** `tools/ephemeris/fit_ephemeris.py` fits Chebyshev
  series, in 4-day segments from GET −2 to +30 days, to JPL Horizons'
  DE441 positions of the Moon and the Sun, and to the IAU's rotation
  model of the Moon from NAIF's `pck00010.tpc`
  (`data/ephemeris/apollo_11.json`, 20 KB). Against values held out of
  the fit the Moon is within 0.09 m and the Sun's direction within
  6 × 10⁻¹⁰°. The Moon-fixed frame puts the sub-Earth point where
  Horizons does, within 0.006°. ECI is the ICRF. `Bodies` flies on the
  series when the mission's `moon` block names them, and on the circular
  model otherwise; the propagator costs 1.1 to 1.4 times what it did.
- **The parking orbit** is Apollo 11's, from the Saturn V flight
  evaluation report (`tools/ephemeris/parking_orbit.py`): 32.5° to the
  equator, entered 709.3 s after liftoff.
- **TLI** solves its ignition time and a yaw out of the plane
  (`Rtcc.plan_tli()`) for an aim in the B-plane: 111 km over the Moon,
  retrograde, in the plane that holds Tranquility Base at the landing
  time. It takes a yaw of 14.5°, and turns the plane 5.0° where Apollo
  11's IU turned it 1.3°. Two things make the difference. The Earth's
  oblateness, which this simulator leaves out, turned the real parking
  orbit's plane 0.8° west before TLI, which brought the Moon about half
  the way to it. And a yaw held through the burn does less for the aim
  than the IU's steering. The translunar MCC keeps the aim in all three
  axes (`Rtcc.plan_mcc()`), and LOI puts the orbit over the site.
- **The `lunar_orbit` phase** starts in that orbit, phased for the
  timeline: Eagle's DOI at 101:36:14 and PDI at 102:33:33 set it down at
  102:45:39. Apollo 11's were 101:36:14, 102:33:05 and 102:45:40.
- **The Sun** stands 10.7° over Tranquility Base at touchdown, where the
  mission report has 10.8°.

The Fidelity table in the README has the rest of the flight measured
again.

Slice 4b gives the CMC its own navigation:

- **The state vector.** The AGC core's (`AgcCore.nav`), which the LGC
  has used since 3c: coasted with the computer's own integration, with
  the vehicle's sensed ΔV added while Average-G runs. The CMC's runs in
  P40, P41, P47 and entry, and while the S-IVB burns TLI; the LGC's all
  the time Eagle flies free. Every CMC program and noun reads it: P30,
  P40's steering, V82 and entry guidance's speed and altitude rate.
- **Unmodelled forces.** The CSM's truth gains the SM's vents, a steady
  force in body axes, and its attitude jets' net force from their
  imbalance while they fire, both drawn once for the flight from the
  mission's seed (mission.json "dispersions", spacecraft.json
  "unmodelled"). They act through coast steps. In coast the CMC's
  Average-G is off, so they move the CSM off its state vector: from a
  perfect state, 541 m in a day's translunar coast.
- **MSFN.** The RTCC plans the CSM's PADs from its tracked state, truth
  off by a tracking error drawn for each request (mission.json "msfn",
  by the body the orbit is about), and uplinks that state with them.
  **SV** under Mission Control asks for it alone.
- **P27.** The CMC takes uplinks in P00 with a new UP TLM CM switch in
  ACCEPT. The switch sits on panel 2, right of the DSKY, where the
  Operations Handbook's drawing has it, and is on the HUD too. The DSKY
  shows P27 and V71 while UPLINK ACTY is lit. In BLOCK, CAPCOM reads the
  PAD up by voice. The SPS burn checklist sets ACCEPT before the request
  and BLOCK after it.
- **Checkpoints** are schema 6: the CMC's state vector, the unmodelled
  forces, and where MSFN's draws have got to.
- **What it changes in flight.** By LOI the CMC's state vector is 93 km
  off, mostly the start's tracking error grown over three days, and the
  LOI PAD's uplink brings it to 0.4 km. The RTCC now plans LOI-1 from the
  tracked state, so its PAD carries a few ft/s out of plane (DVY +13.9),
  and the orbit it leaves passes 660 m from the site where the plan has
  it over it. The rest of the flight moves by seconds and tenths of a
  ft/s (the README's Fidelity table).

Slice 4c gives the CMC its IMU:

- **The platform** (`src/systems/imu.gd`). The CMC reads its attitude
  and its accelerometers through the stable member, which it takes to lie
  at REFSMMAT, so a misaligned platform turns both. The gyros drift at
  rates drawn from the mission's seed (spacecraft.json "imu", 0.015°/h
  per axis): 0.215° in 12 h of translunar coast for this flight. The ICDU
  angles are the CSM's attitude relative to the stable member, in the
  gimbals' order (outer on the body's X, inner on the stable member's
  Y), to a CDU count; the FDAI's total attitude and N20 show them.
- **REFSMMATs.** The launch pad's (mission.json "launch_refsmmat": X
  along the flight azimuth, Z down at liftoff, from
  `tools/ephemeris/parking_orbit.py`), the preferred orientation P30 works
  out for each maneuver (X along the thrust, heads up: the burn attitude
  at zero gimbal angles), the landing site's (X up through the site at
  the landing time, Z downrange) and the nominal (the local vertical).
  Each start phase starts freshly aligned: the launch pad's until the
  lunar orbit, the landing site's there, the nominal on the way home.
- **Gimbal lock.** GIMBAL LOCK lights past 70° of middle gimbal, and past
  85° the CMC cages the IMU, as Colossus's gimbal lock monitor did: the
  platform turns with the CSM, NO ATT lights, the DAP only damps the
  rates, and the alignment is lost (alarm 00220 for P40, P41 and P52;
  a cage ends P51 and P52). P40 won't maneuver to a burn attitude past 60°
  of middle gimbal (alarm 00401), and the CMC plans each maneuver clear
  of lock: the thrust axis the short way onto the burn's, then a roll
  about it (the outer gimbal alone), or, where that first leg would pass
  60°, one gimbal at a time, so the middle gimbal runs only between its
  two ends' angles. P52 won't coarse align to a new orientation past 60°
  where the CSM points (alarm 00401): the crew turns first.
- **The optics** (`src/systems/optics.gd`, `src/presentation/optics_view.gd`).
  The sextant (1.8°) and the scanning telescope (60°) on one line of
  sight, from a shaft axis 32.5° from +Z toward the nose; OPTICS ZERO,
  OPTICS MODE (MANUAL, the optics hand controller; CMC, the computer
  drives them), OPTICS SPEED, MARK and MARK REJECT. Their view shows the
  37 navigation stars, from the Hipparcos catalogue carried to the
  launch day (`tools/stars/navigation_stars.py`), and the Earth, the Moon
  and the Sun. On the desktop, O opens them; in the cabin they are on
  the lower equipment bay's panel with a second DSKY, a station SEAT
  moves to, away from the couch.
- **P52, P51 and V41 N20.** P52 realigns: the option (1 preferred,
  2 nominal, 3 REFSMMAT, 4 landing site), N22 and a coarse align for a new
  orientation, the CMC's two stars (alarm 00405 when the Moon or the
  Earth fills the optics: roll heads down), N70 and a mark on each, N05,
  and N93's torquing angles, torqued. P51 finds a caged platform's
  orientation from two stars the crew marks and names (N71). V41 N20
  coarse aligns to loaded gimbal angles. The IMU realign checklist flies
  P52 at the lower equipment bay, and the SPS burn checklist calls for it
  after P30.
- **Checkpoints** are schema 7: the IMU, P51 and P52's marks, and the
  optics.
- **What it changes in flight.** Every burn the suite flies realigns to
  its preferred orientation first, as the crew did. After 12 h of drift
  P52 leaves 0.003° (N05 0.004°), and a TEI flown on a platform 0.5° off
  goes 8.59 m/s off the aligned flight, where the misalignment predicts
  8.56 m/s, 0.28° apart; that moves the Earth return's perigee 71 km.

Slice 4d lets the CMC navigate on its own sightings:

- **The filter** (`src/systems/nav_filter.gd`). The state vector's error
  covariance, 6 × 6 in ECI axes, where Colossus kept its square root, the
  W matrix. It is carried from one mark to the next by the trajectory's
  own transition matrix, found by coasting the state with each
  component nudged, so the Earth's and the Moon's pulls both shape it,
  and it grows with the vents' unmodelled push. Each mark is weighted in
  a scalar at a time (Joseph form). It starts from RMS errors (30 km,
  10 m/s) at the first mark after a start phase, an uplink, V93 or a
  burn of more than 50 m/s; a smaller burn's execution error is added.
- **The sextant's landmark line.** It looks along the shaft axis, and its
  image lies over the star line's: the star line's image is the landmark
  line's turned about the trunnion axis by the trunnion angle. With a
  star laid on a horizon, the trunnion angle is the angle between them,
  however the CSM points, and P23 reads it to 0.002°. The optics view
  shows the landmark line's Earth and Moon, fainter, in the sextant.
- **P23.** V05N70 (the star, the landmark 0, the horizon: 1 the
  Earth's, 2 the Moon's); the attitude that lays the landmark line on
  the horizon under the star, turned about it to keep the middle gimbal
  clear (V50N18, alarm 00404 when the star can't be laid on the
  horizon); the auto maneuver; V51 with the optics on the star; the mark
  against the star-horizon angle from the state vector (the solid limb);
  V06N49's ΔR and ΔV; PRO takes it in, V32 marks again.
- **P37.** The correction at TIG (N33, half an hour on) that brings the
  vacuum perigee to 37 km, worked out from the CMC's own state vector by
  the RTCC's targeting (N81, N42), and stored for P40 or P41 as P30
  stores a PAD.
- **P22.** A landmark, the landing site unless the crew loads another
  (N89); the next pass over it from the state vector; the attitude that
  points the landmark line at it there; the optics driven to it while
  the trunnion reaches it; each mark's line of sight, from the optics,
  the gimbals and REFSMMAT, against the state vector's, each way across
  it. The optics view rings the landmark, and the clock stops ten
  minutes before the pass.
- **V67 and V93.** V67 shows the filter's RMS errors (N99) and takes new
  ones; V93 starts it again at the next mark.
- **The DSKY.** V01 shows a noun's first register alone, as P52's V01N70
  always did, now that N70 has three.
- **Checkpoints** are schema 8: the filter, P22's and P23's step and a
  mark waiting at N49. 4d first kept schema 7, letting a 4c checkpoint
  restore with the filter starting again; the ground rules ask for the
  bump, which came with 5a's pull request.
- **What it does in flight.** A TEI flown on a platform 0.5° off leaves
  a vacuum perigee of −115 km and the CMC's state vector 1.1 km and
  8.9 m/s off. With no uplink, ten P23 sessions of six marks and two
  P37s (4.0 and 0.3 m/s) leave 37.9 km; P37 from the unmarked state would
  have left −41 km. In lunar orbit, five P22 marks through one pass bring
  the state vector from 2.2 km off to 53 m (`test_onboard_navigation.gd`).

### Slices

| Slice | Work | Check |
|---|---|---|
| 4a (done) Ephemeris | Real Moon and Sun positions for the mission dates, in a dated inertial frame. The Moon-fixed frame from 3c gets a real rotation model. Recommended: Chebyshev coefficients fitted to JPL ephemeris vectors, generated by a script in `tools/`, stored under `data/`, with their provenance in NOTICE | Error against held-out reference vectors stays under 1 km for the Moon's position and 0.01° for the Sun's direction. The scenario suite passes, re-tuned only where the flight really changed. Re-measure the Fidelity table |
| 4b (done) Onboard state | The AGC keeps its own state vectors (the CSM's; the LGC's has done so since 3c, `Lgc.nav`, and it has held the CSM's as the ground uplinks it since 3d, `Lgc.csm_nav`, which it coasts and P20's radar marks update since 3e): it coasts them with its own integration and updates them from sensed ΔV while thrusting (`AgcCore.sense()` already integrates `dyn.dv_step`, and the LGC's `lm.dyn.dv_step`). Every program and noun uses them, never truth. Truth gains small forces the AGC doesn't model (vents, unbalanced attitude jets), with seeded dispersions whose seed is in the checkpoint. The RTCC plans from a tracked state with tracking error. The crew accepts state-vector uplinks through P27 (V71) | Test: after a long coast, the onboard state has drifted from truth by a bounded amount, and an uplink replaces it with the tracked state. The MCC and LOI scenarios pass with an uplink step |
| 4c (done) IMU and P52 | REFSMMATs (launch pad, preferred for each burn, landing site), gyro drift, and ICDU angles and the FDAI relative to REFSMMAT. Gimbal lock costs the alignment instead of only lighting the lamp. An optics view (sextant and scanning telescope) with the 37 Apollo navigation stars; P51, P52, V41 N20 coarse align, N05 star angle difference, N93 torquing angles. Desktop first; in the cabin the optics sit at the lower equipment bay, away from the couch | Test: drift for 12 h, realign with P52 and two star marks, and the residual misalignment is under a set limit. A burn flown on a misaligned platform misses by the amount the misalignment predicts |
| 4d (done) Onboard navigation (stretch) | P23 cislunar sightings and P22 landmark tracking. (In the LM, the landing radar has updated the LGC's altitude and velocity since 3c) | Test: P23 marks alone keep the entry corridor within limits without an uplink |

### What 4a changed elsewhere

- **The parking orbit.** It lay in the Moon's orbital plane
  (`MissionSequencer._parking_orbit_traj()`), so TLI and MCC planning
  were planar. It is Apollo 11's now, inclined 32.5°: TLI solves a yaw
  out of the plane, and `Rtcc.plan_mcc()` solves in all three axes (the
  translunar MCC PAD is +1.8, −0.1 and −2.2 ft/s).
- **The `moon` block in `mission.json`** names the ephemeris. Its
  circular Moon's phase, chosen so that TLI fell near 2:44 GET, is gone,
  and TLI's energy is Apollo 11's.
- **The Sun angle at the landing site** follows from the date: 10.7° at
  touchdown. The landings were timed for a low Sun behind the LM.
- **The analytic references in the propagator's unit tests** keep the
  circular model (`Bodies.configure()`), and those tests hand the
  mission's model back when they finish.
- **Checkpoints** are schema 5: ECI is the ICRF, and the S-IVB saves its
  yaw.

### What 4c changed elsewhere

- **The attitude displays.** N20, N22 and N18 and the HUD's ATT line are
  ICDU angles in the gimbals' order (outer on the body's X, inner on the
  stable member's Y), where they were Euler angles against ECI in
  another order. The FDAI shows total attitude against REFSMMAT; the
  horizon aid moved to its own channel, `guid.indicator.lvlh`, since it
  wants the local vertical. Eagle's FDAI stays LVLH-relative, and the
  LGC's GIMBAL LOCK lamp stays a lamp.
- **The burns.** The suite's burns realign first: `fly_pad()` flies P52
  option 1 25 minutes before TIG, rolling heads down when the Moon or the
  Earth fills the optics, and the cabin's SPS burns fly the IMU realign
  checklist at the lower equipment bay. Eagle's flights are unchanged.
- **The cabin.** Columbia has a third station, the lower equipment bay,
  with its own panel (the optics' eyepieces, OPTICS ZERO, MODE and SPEED,
  MARK, MARK REJECT and the second DSKY), and SEAT goes round three
  stations. There the hand controller input drives the optics, as it
  does on the desktop while the optics are open.
- **The DSKY** shows and loads octal registers (star codes, option and
  checklist codes) and three decimals (N93, the trunnion).
- **Attitude hold.** The drifting platform moves the attitude the CMC
  holds. The hold stopped firing inside its 0.1° deadband with whatever
  rate was left, so once the drift had carried it out, it limit-cycled:
  each coast step carried the attitude out again, and the jets fired
  again, about once a minute. Through the coast to LOI in HOLD, that
  emptied SM RCS quads B and D, and LOI-1 flew 56 % long. The hold now
  comes to rest inside 0.05° and nulls the rate before it leaves the jets
  off: 16 h in HOLD costs 0.15 kg, a correction every three hours or so
  (`test_imu_alignment.gd`).

### What 4d changed elsewhere

- **The test helpers.** `fly_pad()` accepts a PAD with P30 and then
  flies it with `fly_stored()`, which flies P37's too. New helpers make
  P23's marks (`p23_mark()`, `superimpose()`), P22's (`centre_landmark()`)
  and run P37 (`p37()`).
- **The DAP after P22 and P23.** It holds the sighting attitude when they
  end, where it would have gone back to the attitude it held before
  their maneuvers.
- **`tools/screenshot.tscn`** takes `--p23=<code>`, which renders P23's
  mark (the README's image).

### Order

4a is self-contained. If it lands before 3c, the landing is built once,
on the real Moon. 4b and 4c change every AGC program's inputs, so do
them after the core split in 3b.

## 5. The whole flight

**Status: slices 5a and 5b are done: the Earth is oblate, the Sun
pulls, and the Moon has its mascons.** What the README still lists as
simplifications of the flight itself: the missions start in parking
orbit, the S-IVB flies TLI at a fixed yaw, P40 holds its ΔV direction in
LVLH, and entry guidance has no aim.

- **Gravity** first, since it moves every number the suite checks. The
  Earth's oblateness turned Apollo 11's parking orbit 0.8° west before
  TLI, about half the yaw the S-IVB takes here to reach the Moon's
  plane. The Sun's tide, some 3 × 10⁻⁵ m/s² at the Moon's distance,
  pulls a translunar coast hundreds of kilometres off in three days. The
  Moon's mascons move a 60 nmi orbit's apsides by kilometres a day, and
  they were why the ground's lunar orbit predictions went wrong on the
  early flights.
- **The S-IVB's iterative guidance** then flies TLI to its target as the
  IU did, and **the launch** reuses it for the S-II and the S-IVB's
  first burn. The launch brings the atmosphere turning with the Earth.
- **P40's cross-product steering** is Colossus's, which a long burn like
  LOI-1 needs.
- **Entry range targeting** comes last, on the rotating Earth the launch
  brings: Colossus's entry guidance, aimed at a splashdown point.

The onboard computers keep models of their own, as the flown ones did:
the CMC and the LGC integrate the Earth's oblateness but only the R-2
model of the Moon's field, so in lunar orbit their state vectors drift
from truth as the flown ones did, and the ground's tracking and P22
matter more.

Slice 5a gives the Earth its shape and the Sun its pull:

- **The Earth's oblateness.** Its zonal harmonics, J2 to J4 (EGM96),
  about its mean pole of the ephemeris's date: the IAU 1976 precession
  from J2000, 0.17° from the ICRF's pole in 1969. Truth, the RTCC and
  the onboard computers integrate it alike. The parking orbit's node
  regresses 0.317°/h, J2's analytic rate within 1 %, and 0.8° by Apollo
  11's TLI (`test_tli.gd`). Round an orbit the energy counting the
  oblate potential holds to 7 J/kg, where the two-body energy swings
  27 kJ/kg.
- **The Sun's pull**, as a third body, where the ephemeris has it at
  each step's middle. On the way out it moves the Moon's arrival by
  seconds.
- **TLI.** With the parking orbit turning toward the Moon's plane, the
  fixed yaw drops from 14.5° to 5.6°: the plane turns 1.9°, where it
  turned 5.0° (the IU turned it 1.3°), and the J-2 gives 3,182 m/s,
  where it gave 3,278 (Apollo 11: ~3,180). The S-IVB cuts off on the
  energy counting the oblate potential [estimated]. Read as a two-body
  energy at the cutoff, 285 km up over 9° N where J2's potential is
  −28 kJ/kg, the flown C3 leaves the stack 3.7 % more bound once away
  from the Earth, and the Moon comes 1.6 h late.
- **The vacuum perigee.** The RTCC took a return's vacuum perigee from
  the conic at 100,000 km. It now integrates on to the perigee
  (`Rtcc.vacuum_perigee()`), so TEI, the MCCs and P37 aim at the
  perigee the CM reaches. Under the surface it integrates on through
  the same field, so a steep return's perigee runs on smoothly past
  it; only a return whose perigee lies deeper than half the Earth's
  radius keeps the conic's. On the entry start phase's return that
  perigee is 4.7 km below the conic's: J2 pulls it 3.2 km lower on the
  way in and the Moon 2.1 km, and the Sun lifts it 0.7 km. Aimed by the
  conic, the entry peaked at 7.1 g before 5a, from the Moon's 2.1 km
  alone, and at 7.6 g with the oblateness and the Sun. Aimed at the
  true 37 km, it meets the atmosphere at −6.52° (−6.60° before 5a) and
  peaks at 6.7 g (Apollo 11: about 6.5 g).
- **What else it moves.** The rest of the flight moves by seconds and
  tenths of a ft/s (the README's Fidelity table): about the Moon only
  the Sun's tide is new, some 10⁻⁷ m/s². 4d's check holds: after
  the misaligned TEI's −117 km (−115 before), P23's marks and two P37s
  bring the vacuum perigee to 38.1 km (37.9).
- **CI** deals the scenario files over its three parts by their time on
  the runners, recorded in `.github/scenario_seconds.txt`, where it
  dealt them in turn by name. By name, one run on this slice's gravity
  took 8:15, 10:06 and 2:04; dealt by time, the parts took 6:50, 7:02
  and 6:47.
- **Checkpoints** are schema 8, bumped here for 4d's navigation state.

Slice 5b gives the Moon its mascons:

- **The field.** GRAIL's GL1800F, in the mean Earth/polar axis frame the
  simulator's Moon-fixed frame is, cut at degree 30 by
  `tools/gravity/moon_gravity.py` (standard library only; it fetches the
  coefficients from the PDS by range requests). The tool's study: 60 nmi
  up, the degrees past 30 pull 67 µm/s² RMS, and a day of a 60 nmi
  orbit on degree 30 comes within 1.3 km along the track and 0.16 km in
  its apsides of degree 100's. `MoonGravity` evaluates it by
  Cunningham's recursion on unnormalised coefficients (Montenbruck and
  Gill), within 1e-6 of the direct sum's gradient; the tool's own
  integration, by spherical Legendre functions, flies a 12 h reference
  orbit that the propagator matches to a tenth of a millimetre. The
  lunar GM becomes GRAIL's, 4,902.800 km³/s². Inside the Moon, where
  only a trajectory diving through the surface goes (a trial burn of
  the RTCC's DOI bisection, say), the series diverges: 20 km/s² where
  one such trial got to 960 km from the centre, the integration
  crawling on the steps it shrank to. Below 0.99 of the reference
  radius, under the lowest ground, the field is taken straight above,
  bounded and continuous.
- **The cost.** Degree 30 costs 246 µs an evaluation, too much for
  every stage of every step. So the field is sampled once every 30 s of
  GET, at each interval's middle,
  where the trajectory will be then (a third-order series along the
  step), and a cubic through four samples gives it at each stage; the
  degree fades with distance, to the terms whose (R/r)ⁿ still exceed
  e⁻⁸, 3 at ten lunar radii. A day of a 60 nmi orbit comes 10 m from
  one evaluated at every stage, its apsides under a metre. On CI the
  scenario parts' tests took 6:09, 8:11 and 8:50 (5a's: 6:13, 6:24 and
  6:46), still dealt by 5a's times, the slowest job 9:11; with 5b's in
  `.github/scenario_seconds.txt` they deal 461, 463 and 459 s.
- **The onboard model.** The CMC and the LGC fly R-2, the model their
  programs carried: the Moon's J2, J3, C22 and C31 at 1,738.09 km,
  applied within 16,093 km (Risdal's Boeing report; the Comanche 055 and
  Luminary 099 listings and padloads). The CMC leaves out the Earth's
  and the Sun's pull below 800 km, and the LGC everywhere. 60 nmi up,
  R-2's pull beyond the point is 388 µm/s² where GRAIL's is 655, 383
  apart, and from one state the CMC's model comes 3.5 km from the truth
  in two revolutions. The RTCC integrates truth's field [simplified: the
  ground flew R-2 too].
- **The flown orbit.** The `lunar_orbit` start phase now starts where
  Apollo 11's LOI-2 cut off, at 80:11:54, in its 65.7 × 53.8 nmi orbit
  above the landing site with the pericynthion at 80° W, phased to pass
  over the site at the landing; LOI-2's PAD targets the flown 65.7 ×
  53.7 nmi. Flown on through GRAIL's field it follows the ground's
  tracking figures (the PAO's and the report's Table 7-V) within
  1.5 nmi, to 61.8 × 56.9 nmi at 126 h, where the mission report has
  62.4 × 56.6; through R-2 it rounds out to 59.5 × 59.0, where R-2
  predicted 59.9 × 59.3. A round 60 nmi orbit, Apollo 10's approach,
  goes 13.5 nmi out of round by then, where the report estimated 11.6.
  (`test_mascons.gd`.)
- **DOI and PDI.** In the half revolution from DOI the field turns the
  descent orbit's apsides by some 4°, so the RTCC now moves DOI until
  the pericynthion falls where PDI begins: DOI comes at 101:34:52
  (Apollo 11: 101:36:14). The PDI PAD's state vector is coasted back
  along the LGC's model, so the LGC comes to PDI off by the mission
  data's error.
- **The rendezvous** on the flown orbit behaves as Apollo 11's did:
  with Columbia's orbit out of round, CDH takes 7.5 ft/s (Apollo 11's
  took 19.9), and TPI comes 2 min 37 s before the plan's time (Apollo
  11's came 6 min 39 s after). With the LGC's model drifting, a TPI
  worked out half an hour ahead left 6.4 ft/s for the first midcourse
  correction; recomputed 12 minutes before, as the crew did, the
  corrections are 2.7 and 0.5 ft/s (Apollo 11's crew reported under 1
  and about 1.5).
- **The re-tune.** Measured where the field moves the truth: the DOI's
  pericynthion by flying to it, not by the conic of the moment, which
  the field swings by kilometres round the orbit; Columbia's orbit
  after DOI by a copy flown beside it; an ascent-engine burn by its
  apsides just before and after. The equiperiod separation burns across
  the velocity, which on the flown orbit is off the local vertical. The
  CMC's state vector is judged against a copy drifting on its model
  alike (P47, the misaligned TEI). P22's error is set at the pass, where
  the model's drift had cancelled part of it. The misaligned TEI now
  leaves the CSM far shallow of the corridor, not steep. Three tests
  held only by the timing of the old orbit: P52 before TEI finds no
  stars in any roll with the nose on the Moon, so the crew turns the
  nose away; P68 comes a step after touchdown, which the test now waits
  for; and P12's tail-off, under a second, fell between the test's
  one-second looks, so the test now looks finely from the steering's
  hold on. And the tests' `fly_until()` and `run_until()` step at
  least one clock step at a time: a remainder of a microsecond, which a
  shifted timeline left one flight, had piled up in the clock's
  accumulator a frame at a time, 17,500 frames and two minutes before it
  made a step.
- **Checkpoints** are schema 9: each trajectory's field samples, since
  a restored flight must interpolate from the same ones. A restored
  run's first step is a fine one, so its coast steps fall 0.02 s off the
  uninterrupted run's; the field parts the two flights by millimetres
  in a quarter of an hour, where they stayed within a fifth of one, and
  the round trip's check on their times allows 0.1 ms.

### Slices

| Slice | Work | Check |
|---|---|---|
| 5a (done) The Earth's oblateness and the Sun | The Earth's zonal harmonics (J2 to J4) about its pole of date, precessed from the ICRF, and the Sun's pull from the ephemeris, in the propagator: truth, the RTCC and the onboard computers alike. The suite gets a third scenario part if the step's cost takes a part past ten minutes | Test: the parking orbit's node moves west as flown before TLI (0.8°), and each new acceleration matches an independent evaluation. The suite passes, re-tuned only where the flight really changed; re-measure the Fidelity table |
| 5b (done) The Moon's mascons | The Moon's gravity field from GRAIL, truncated by a script in `tools/` to the degree a 60 nmi orbit feels, for truth and the RTCC; the CMC and the LGC keep the simpler lunar model their programs flew with, sourced in the slice. The step's cost is measured and budgeted | Test: a low lunar orbit's apsides move as an independent integration of the same field predicts, and the flown LOI-2 orbit's change by the landing is compared with the mission report's. The landing and the rendezvous pass, the onboard state vectors now drifting from truth |
| 5c S-IVB iterative guidance | The IU's iterative guidance mode for TLI: steering to the target conic the RTCC plans (its energy, eccentricity and plane), the time to go iterated as it burns, cutoff on the target. The fixed yaw goes | Test: TLI hits the target within a set limit, with its ΔV and plane change near Apollo 11's (about 3,180 m/s and 1.3°) |
| 5d The launch | Liftoff from Launch Complex 39A at 13:32:00 UTC: the S-IC's roll and tilt programs and its cutoffs, staging, the S-II and the S-IVB on iterative guidance, the launch escape tower's jettison, insertion. The atmosphere turns with the Earth. A start phase on the pad, and the cabin and the HUD through the ascent. Aborts are left for later | Test: insertion into Apollo 11's parking orbit (32.5°, about 100 nmi) at about 11:49 GET within set limits, each stage's burn near the flown times (the Saturn V flight evaluation report) |
| 5e P40 cross-product steering | Colossus's cross-product steering in P40 and P41, in place of holding the ΔV's LVLH direction | Test: LOI-1 on cross-product steering leaves an orbit nearer the RTCC's plan than LVLH steering does, and short burns come out as they did |
| 5f Entry range targeting | Colossus's entry guidance (P62 to P67): the range to a splashdown target on the rotating Earth, up-control for long ranges, the final phase along a reference trajectory, and lateral roll reversals. The target comes with the entry PAD | Test: from entry interface the CM splashes down within a set limit of the target, from a short and a long range alike |

### Order

5a first: its re-tune is the suite's, and every later check is measured
on it. 5b followed at once; nothing else needs the mascons.
5c before 5d, whose guidance it is; 5d before 5f, whose rotating Earth
it brings. 5e stands alone.

## 6. Sound

**Status: not started.** The cabin is silent. gemini-capsule
synthesises its cabin sounds from Bus events in
`src/presentation/audio_director.gd`, with nothing recorded to license.

| Slice | Work | Check |
|---|---|---|
| 6a The audio director | Port it: the SPS, the S-IVB and the attitude jets, the DSKY's keys, the master alarm, pyros, the parachutes and the cabin fans; in Eagle, its descent and ascent engines. On the desktop and in the headset alike | Test: Bus events start and stop the director's voices. A recorded listening pass |

## 7. Other missions

**Status: not started.** Only Apollo 11 flies. Each other mission is
data under `data/missions/`, not a code branch: its ephemeris fit for
its dates, its parking orbit and REFSMMATs, its landing site, Mission
Control's timeline and its vehicles. What a mission needs that the
simulator can't do yet comes in its slice, for every mission after it.

| Slice | Work | Check |
|---|---|---|
| 7a Apollo 8 | No LM: the S-IVB carries a test article, and the CSM flies ten lunar orbits alone | Test: Apollo 8 flies from its data alone, parking orbit to splashdown, its Fidelity table within set limits of the flight |
| 7b Apollo 10 | The LM's descent to 8 nmi over the landing site, staging and the rendezvous, without a landing | Test: as 7a, for Apollo 10 |
| 7c Apollo 12 | A pinpoint landing beside Surveyor III, the landing site updated in P63 as the flown LGC's noun 69 did | Test: as 7a, and Intrepid lands within a set limit of the Surveyor |
| 7d Apollo 13 | The service module's oxygen tank, the LM as a lifeboat and the free return | Test: as 7a, from the tank's failure to splashdown |

Apollo 14 flies as 12 did; the J missions (15 to 17), with the rover and
the SIM bay, are left for later.

## Later, not scheduled

These simplifications stay after all seven milestones:

- The winds, at launch and at entry.
- Aborts during the launch.
- The LGC's IMU stays ideal: its alignments with the AOT (P52, P57) are
  left out.
- P23 marks the solid limb, on stars and horizons only, and P22 takes
  its landmark's position as known.
- The J missions (Apollo 15 to 17).

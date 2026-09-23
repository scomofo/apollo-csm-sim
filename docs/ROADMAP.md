# Roadmap

What comes next for the Apollo CSM simulator, in order of value. Written
2026-09-23 against `main` at `23a6b54`. Update each status line as its
milestone moves.

| # | Milestone | Why | Size | Needs |
|---|---|---|---|---|
| 1 | [CI green](#1-ci-green) | Every later change should merge on a green run | No code | GitHub Actions starting jobs again |
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
- **CI stays fast.** The suite takes about two and a half minutes. Keep
  it under ten: start a long scenario from a phase or checkpoint instead
  of flying the whole mission.

## 1. CI green

**Status: blocked on GitHub Actions. The suite passes.**

`.github/workflows/ci.yml` has one job, `test`: download Godot 4.4.1
(cached), import the project, and run GUT headless. It hasn't run a job
yet. Its only run,
[35795789969](https://github.com/scomofo/apollo-csm-sim/actions/runs/35795789969)
(the push of `23a6b54` to `main`), ended in `startup_failure` before any
job was created.

The workflow isn't the cause. gemini-capsule fails the same way. Its CI
last started jobs at 21:07 UTC on 2026-09-22. Every run since 21:42 UTC
has ended in `startup_failure` with no jobs, although its `ci.yml` hasn't
changed since 16:24 UTC that day. Something outside both repositories
stopped Actions from starting jobs. Nothing in `ci.yml` needs to change.

Run locally at `23a6b54` with the commands in `ci.yml`:

| Step | Result |
|---|---|
| `godot --headless --path . --import` | Exit 0 in 11 s |
| `godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit` | Exit 0: 45 of 45 tests and 194 asserts passed in 139 s |

GUT also prints one warning and counts 10 orphans. The warning is about
the inner class `TestSubscriber` in `tests/unit/test_bus.gd`, which
doesn't extend `GutTest`, so GUT skips it. Neither fails the run.

When Actions starts jobs again:

1. Push to `main`, for example by merging a pull request. A run that
   ended in `startup_failure` can't be re-run: the API answers 403,
   "This workflow run cannot be retried". Expect about three minutes
   (the job's limit is 20).
2. If the runner fails where the local run passed, fix that before
   anything else merges.
3. Protect `main` and make the `test` job a required check.

**Done when** a push to `main` and a pull request both show a green
`test` job, and `main` requires it.

## 2. VR cockpit

**Status: slices 2a and 2b done.** The rigs, interaction layer, prefabs
and action map are ported with their tests (README.md lists every file
and change), and `HandControllerInput` now writes `ctl.rhc` and `ctl.thc`
from the keys and the thumbsticks. `space_view.gd` keeps the cabin fixed
and turns the world around it; the window and chase views render as
before (four screenshots within 7 pixels of the old ones, all star-lookup
rounding). Nothing draws a cabin yet; 2c is next.

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
| `src/cabin/cockpit_layout.gd`, `assets/data/cockpit/controls.csv`, `channels.csv` | Data-driven panels: one validated CSV row per control, with its source and confidence | Needs an Apollo cabin datum and a cockpit spec to check each `spec_id` against |
| `src/interaction/hand_controller_input.gd` | Thumbsticks to the hand-controller channels | Gemini writes `ctl.hand_controller.pitch`, `.yaw` and `.roll`. Apollo reads `ctl.rhc` (roll, pitch, yaw) and `ctl.thc` (X, Y, Z) as `Vector3`s |
| `openxr_action_map.tres`, the `[xr]` block of `project.godot`, `export_presets.cfg` | Action map with the Touch, Index, Vive, Vive Focus 3, WMR and Pico profiles among others; OpenXR settings; PC VR and Quest 3 presets | Settle the reference space first. gemini-capsule's docs describe a seated `LOCAL` space, but its `project.godot` sets `xr/openxr/reference_space=1`, which Godot 4.4.1 reads as Stage (the options are Local, Stage, Local Floor) |
| `src/presentation/wrist_menu.gd`, `comfort.gd`, `gaze_tooltip.gd`, `checklist_highlight.gd`, `vr_acceptance_recorder.gd`, `perf_monitor.gd` | Wrist menu, vignette, tooltips, next-control highlight, headset acceptance recorder, frame-time budget | `comfort.gd` reads Gemini channels (`guid.rate.*`, `aero.q_dyn_pa`, `guid.att.lvlh`); Apollo has `dyn.omega`, `dyn.g_load` and `dyn.att_q`. The recorder checks Gemini controls such as `ctl.ace.power`. Apollo's checklist steps name Bus channels, not controls, so the highlight looks up the control for a channel in `controls.csv` |
| `docs/VR_INTERACTION.md`, `HEADSET_RUN.md`, `VR_ACCEPTANCE.md` | Interaction rules and the headset acceptance run | Rewrite for the CM |

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
  the lamps. The numeric-display and lamp prefabs can then show it
  (registers need a text mode in the numeric display). Today `DskyPanel`
  reads the `Dsky` object directly.
- **The FDAI.** Publish the attitude the ball shows, so the 3D FDAI
  prefab can read it. That's LVLH-relative today, as Apollo's
  `src/presentation/fdai.gd` computes it, and relative to REFSMMAT after
  slice 4c.
- **Hand controllers.** Thumbsticks write `ctl.rhc` and `ctl.thc` first,
  as in gemini-capsule. A grabbed RHC and THC come later; gemini-capsule
  hasn't built grab interaction either.
- **Mission Control, CAPCOM and the checklist.** Put the checklist and
  the CAPCOM log on a readable card. The PAD requests (MCC, LOI-1, LOI-2,
  TEI), time rate, pause, recentre and eye height go on the wrist menu.
- **Comfort.** The cabin is the fixed frame and only the windows move.
  The vignette follows body rate and entry g.

### Slices

| Slice | Work | Check |
|---|---|---|
| 2a (done) | Port the rigs, the interaction layer, the prefabs and the action map, with adapters for `ctl.rhc`, `ctl.thc`, `Units`, materials and frames | The ported `test_xr_rig.gd`, `test_openxr_action_map.gd` and `test_control_library.gd` (minus its Gemini electrical cases) pass headless |
| 2b (done) | Fixed cabin in `space_view.gd` | New test: turning `dyn.att_q` moves the Earth, Moon, Sun and sky but not the camera or the cabin (gemini-capsule's `tests/unit/test_world_presenter.gd` is the model). `tools/screenshot.tscn` still renders the same window view |
| 2c | CM cabin, `controls.csv`, cabin DSKY and FDAI | Every row round-trips from CSV to node to Bus. A scenario test flies an MCC PAD with P30 and P41 using only cabin controls, through the desktop rig |
| 2d | Checklist and CAPCOM card, wrist menu | Desktop-rig test: request a PAD from the wrist menu, then see UPLINK ACTY on the cabin DSKY and the PAD on the card |
| 2e | Headset run | One recorded pass of an Apollo `VR_ACCEPTANCE.md` in a headset, including a verb/noun typed on the cabin DSKY with a fingertip |

**Done when** a crew member can do every action in
`data/missions/apollo_11/checklists.json` from the couch, a scenario
test does them through cabin controls, and one headset pass is recorded.
The 2D HUD stays as the desktop fallback.

### Risks

- **The DSKY.** Its keypad is small and dense, and the crew types on it
  constantly. Fingertip typing is the first thing to try in the headset.
- **Frame time.** The procedural Earth, Moon and star shaders have never
  been measured at 90 Hz in stereo. Port `perf_monitor.gd` with the rest.

## 3. The LM and a lunar landing

**Status: not started.** The simulator is CSM-centric. The LM is only
mass: 15,103 kg added in the `csm_lm` configuration
(`data/spacecraft.json`) and dropped at LM JETT before TEI.

### What changes underneath

- **Two vehicles at once.** `Dynamics` owns one trajectory, one attitude
  and one configuration. The systems read and write unscoped channels
  (`dyn.*`, `guid.*`, `sps.*`, `rcs.*`), and `SimRuntime` has one AGC.
  After undocking, the CSM and the LM fly at the same time. Decide the
  channel scheme first. Recommendation: today's channels stay the
  CSM's, and the LM gets an `lm.` prefix (`lm.dyn.r_m`,
  `lm.guid.program`). That leaves the existing tests and checklists
  untouched. The coast-step policy (`sys.coast_ok`, `dyn.coast_dt_s`)
  must hold for both vehicles, and the snapshot gains a map of vehicles
  (schema 2).
- **An AGC core with two program sets.** `src/systems/agc.gd` mixes the
  verb/noun dialogue and the DAP with Colossus programs. Split it into a
  core (dialogue, program table, alarms, DAP) and two program sets: the
  CMC's (Colossus) and the LGC's (Luminary). Milestone 4 then changes
  the core once for both computers.
- **A Moon-fixed frame.** The Moon doesn't rotate in the simulation's
  truth; only `space_view.gd` turns it to face the Earth. A landing site
  needs a Moon-fixed frame. Put it behind one function in
  `src/dynamics/bodies.gd`. For now, use synchronous rotation with the
  pole on the lunar orbit normal, tagged `[simplified]`. Slice 4a swaps
  in a real rotation model.
- **Lunar orbit over the site.** LOI, or a plane change, must put the
  orbit over the landing site at the planned landing time. Today
  `Rtcc.plan_loi()` burns straight retrograde.
- **The surface.** Land at Tranquility Base (0.674° N, 23.473° E).
  Model the terrain height there (a sphere first, a DEM patch later) and
  touchdown, lighting CONTACT LIGHT when a probe touches. A landed LM
  must be able to lift off.

### Guidance

| Phase | LGC programs | Basis |
|---|---|---|
| Descent orbit insertion to about 15 km (50,000 ft) | P30, P40 on the DPS | The CMC's P30 and P40 dialogue, with an RTCC DOI PAD |
| Powered descent | P63 braking, P64 approach with landing-point redesignation, P66 rate of descent, P68 landing confirmation | Klumpp's Apollo lunar descent guidance (MIT Draper Laboratory, 1971) |
| Ascent to about 9 × 45 nmi | P12 | Luminary GSOP, section 5 |
| Rendezvous: CSI, CDH, TPI, two midcourse corrections, braking | P20, P32 to P35, burns flown with P41 on the LM RCS | Luminary GSOP, section 5; the Apollo 11 flight plan |
| Docking | Manual, with the THC | — |

### Who flies what

One person can't fly both vehicles. Proposal: at undocking, the
player moves to the LM as commander. The CSM coasts under automation,
holding attitude and tracking the LM. At docking, the player returns to
the CSM. Switching vehicles at will is a later choice.

### Slices

| Slice | Work | Check |
|---|---|---|
| 3a | Two vehicles: undocking, independent flight, docking capture, snapshot schema 2 | Test: undock in lunar orbit, separate and coast one revolution; a checkpoint restored mid-revolution matches the uninterrupted run; re-dock within the capture limits |
| 3b | AGC core split. LM data, DPS, APS, LM RCS and LM DAP. LGC P00, P30, P40, P41, P42, P47 | The existing tests pass unchanged. New test: fly a DOI PAD on the LGC to its pericynthion target |
| 3c | Moon-fixed frame, landing site, LOI over the site, P63, P64, P66, P68, touchdown | Test: automatic guidance from PDI to touchdown lands within 500 m of the site at under 1 m/s vertical and 0.5 m/s horizontal speed. A second run flies P66 with scripted hand-controller inputs |
| 3d | Lunar liftoff time from the RTCC, P12 | Test: liftoff to insertion, within set limits of the target orbit |
| 3e | P20, P32 to P35, braking, docking | Test: insertion to docking capture, with total ΔV within a set margin of the RTCC plan |
| 3f | Undocking-to-TEI timeline in `mission.json`; start phases `lunar_descent`, `lunar_surface` and `lunar_ascent`; checklists; CAPCOM; an LM cockpit (desktop overlay first, then cabin prefabs from milestone 2) | The new start phases are built from the earlier ones, and the full suite passes |

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
- **The landing radar.** It has nothing to correct while navigation is
  ideal. Model it, but it only matters after slice 4b.

## 4. Navigation realism

**Status: not started.** These are the README's first two
simplifications:

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
| 4b Onboard state | The AGC keeps its own state vectors (the CSM's, and the LM's from 3b): it coasts them with its own integration and updates them from sensed ΔV while thrusting (`Agc.sense()` already integrates `dyn.dv_step`). Every program and noun uses them, never truth. Truth gains small forces the AGC doesn't model (vents, unbalanced attitude jets), with seeded dispersions whose seed is in the checkpoint. The RTCC plans from a tracked state with tracking error. The crew accepts state-vector uplinks through P27 (V71) | Test: after a long coast, the onboard state has drifted from truth by a bounded amount, and an uplink replaces it with the tracked state. The MCC and LOI scenarios pass with an uplink step |
| 4c IMU and P52 | REFSMMATs (launch pad, preferred for each burn, landing site), gyro drift, and ICDU angles and the FDAI relative to REFSMMAT. Gimbal lock costs the alignment instead of only lighting the lamp. An optics view (sextant and scanning telescope) with the 37 Apollo navigation stars; P51, P52, V41 N20 coarse align, N05 star angle difference, N93 torquing angles. Desktop first; in the cabin the optics sit at the lower equipment bay, away from the couch | Test: drift for 12 h, realign with P52 and two star marks, and the residual misalignment is under a set limit. A burn flown on a misaligned platform misses by the amount the misalignment predicts |
| 4d Onboard navigation (stretch) | P23 cislunar sightings and P22 landmark tracking. In the LM, the landing radar updates the LGC's altitude and velocity during P63 and P64 | Test: P23 marks alone keep the entry corridor within limits without an uplink |

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

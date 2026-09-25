# VR hardware acceptance

Desktop tests can't tick this list. A pass on a real headset closes slice
2e of `ROADMAP.md`; until then the XR path is unverified. Run it with
`HEADSET_RUN.md`. The simulator writes these tables with the objective
rows' evidence filled in (`src/presentation/vr_acceptance_recorder.gd`);
fill in the Pass column and paste the result into the pull request or
issue. Adapted from gemini-capsule's `docs/VR_ACCEPTANCE.md`.

Target: PC VR, seated, OpenXR, Godot **4.4.1** standard. Any headset whose
controllers the action map binds counts (`openxr_action_map.tres`: Touch,
Index, Vive, Vive Focus 3, WMR, Pico and others).

## Session

| # | Check | Pass? | Notes |
|---|---|---|---|
| S1 | OpenXR runtime detected; `--xr-mode on` starts the XR rig in the cabin | | |
| S2 | Session start, no black eye or stuck overlay | | |
| S3 | Recentre puts the head on the seat's eye, at the calibrated height, without moving the cabin | | |
| S4 | Tracking origin stays seated (Local) | | |
| S5 | Clean session end and headset removal | | |
| S6 | Wrist menu opens on the left Menu button or the palm; HIDE holds while the palm faces you | | |

## Reach and cabin

| # | Check | Pass? | Notes |
|---|---|---|---|
| R1 | From the commander's couch, every MDC1 control is in fingertip reach | | |
| R2 | From the centre couch (SEAT), the DSKY is in fingertip reach | | |
| R3 | Windows sit where the eyes expect them; nothing clips the headset | | |
| R4 | The checklist card and the DSKY display read from the couch | | |

## Actuation

| # | Check | Pass? | Notes |
|---|---|---|---|
| A1 | A panel switch flips on a fingertip crossing, never on hover | | |
| A2 | A verb and noun typed on the cabin DSKY by fingertip, and shown | | |
| A3 | Right thumbstick pitches in CMC MODE HOLD; the FDAI follows | | |
| A4 | Left thumbstick rolls; the player doesn't move | | |
| A5 | DELTA-V THRUST A: the first crossing lifts the guard, the second flips the lever | | |
| A6 | ATT SOURCE steps one detent per crossing | | |
| A7 | A wrist-menu button presses on a fingertip | | |

## Comfort and pacing

| # | Check | Pass? | Notes |
|---|---|---|---|
| C1 | The cabin is the fixed frame; only the world in the windows moves | | |
| C2 | The vignette narrows the view at high body rate; VIGNETTE switches it | | |
| C3 | The horizon aid is optional and off by default | | |
| C4 | Above 100x the hand controllers are locked | | |
| C5 | Ten minutes of lunar-orbit coast at 1x; record comfort and symptoms | | |
| pacing | Frames over 1.5x the headset's frame budget | | |

## Eagle's cabin

A second run, from `--phase=lunar_descent` (`HEADSET_RUN.md`).

| # | Check | Pass? | Notes |
|---|---|---|---|
| E1 | Aboard Eagle, recentre puts the head on the commander's standing eye; nothing clips the headset | | |
| E2 | From the commander's station, panels 1, 3, 4 and 5 are in fingertip reach; SEAT goes to the LM pilot's station and back | | |
| E3 | A verb and noun typed on Eagle's DSKY by fingertip, and shown | | |
| E4 | ENG ARM: the first crossing pulls the lever out, the second moves it | | |
| E5 | The LPD's marks sit on the commander's window | | |

Also record the commit, headset, controllers, OpenXR runtime, refresh rate
and date, and one photo or capture from the couch. Any Fail row becomes
its own issue.

## What the rows mean

- **Recentre and reference space.** The seated `Local` space
  (`xr/openxr/reference_space=0`). Recentring moves the rig's origin so the
  tracked head sits on the seat's design eye, raised by the wrist menu's
  eye-height offset. The cabin never moves. The recorder measures the
  residual from that target after each recentre (S3), and counts origin
  moves outside a recentre (S4, A4).
- **Deliberate actuation.** A state changes only on a crossing, never on
  hover. A toggle moves one position per crossing along its lever. A rotary
  steps one detent per left-to-right (clockwise) or right-to-left crossing.
  A key or button presses when a fingertip pushes into it. The recorder
  counts fingertip crossings (`player.touch_actuations`). It notes which
  control each one was (`player.last_touch_label`) and its channel. So a
  pointer click or a script can't pass A1, A2 or A7.
- **Reach.** The player is one crew member in a three-seat cabin.
  - From the commander's couch, MDC1 should be in reach, and the DSKY
    probably isn't. SEAT moves to the centre couch, where the command
    module pilot worked the DSKY.
  - Nothing on MDC3 (the EPS switches) is expected in reach from the left
    couch. The headset has no far-field pointer yet, so record which
    controls you couldn't reach rather than leaning across.
  - The panel layout is estimated (confidence D in
    `data/cockpit/controls.csv`). A reach failure is a layout finding to
    fix in the data, not by scaling the cabin.
- **Eagle's cabin.** The LM's crew stood. The commander's station is on
  the left and the LM pilot's on the right, and SEAT moves between them.
  From the commander's station, panels 1, 3, 4 (the DSKY) and 5 should be
  in reach; panel 2 is the LM pilot's. Every position in
  `data/cockpit/lm_controls.csv` is estimated too. The recorder notes
  which vehicle each recentre was in (E1), what was typed on Eagle's DSKY
  (E3), and how often Eagle's switches were touched (E2, E4). The LPD's
  marks are drawn for the commander's design eye, so they read true with
  the head there.
- **Comfort.** Nothing moves the camera but the headset. The vignette
  starts at 3 deg/s of body rate (full at 12 deg/s), above the CMC's
  2 deg/s hold rate, and in entry deceleration from 2 g. The horizon ring
  is an inauthentic aid, off by default. AUTHENTIC turns every aid off,
  the checklist highlight and the gaze tooltip too.
- **Time acceleration.** Above 100x the panel switches and the hand
  controllers lock. The wrist menu and the DSKY keys don't, so the crew can
  always slow the clock down.
- **Pacing.** A frame counts as dropped at 1.5 times the budget of the
  refresh the runtime reports (11.1 ms at 90 Hz). The procedural Earth,
  Moon and star shaders haven't been measured in stereo before this run.
  The wrist menu's top line shows the worst frame time of the last 90
  frames.

## Known gaps, not failures

- No far-field pointer in the headset; no grabbed rotation or translation
  controller (the thumbsticks fly them); no haptics or switch sounds.
- The eye height isn't saved between sessions.
- Hand tracking isn't implemented; use the controllers.

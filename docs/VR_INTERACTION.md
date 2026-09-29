# VR interaction

How the player works the CM's and the LM's cabins in a headset and on
the desktop. This describes what is built; milestone 2 of `ROADMAP.md`
plans the rest. `HEADSET_RUN.md` runs a headset session and
`VR_ACCEPTANCE.md` checks it. Adapted from gemini-capsule's
`docs/VR_INTERACTION.md`; README.md lists the files taken from it.

## 1. Platform

- **OpenXR** through Godot 4.4.1's own plugin: no vendor SDK and no
  godot-xr-tools.
- **PC VR only.** Any OpenXR runtime on Windows or Linux: SteamVR, Meta
  Quest Link or another. The action map (`openxr_action_map.tres`, from
  gemini-capsule) binds Touch, Index, Vive, Vive Focus 3, WMR, Pico and
  others; `tests/unit/test_openxr_action_map.gd` checks it. There is no
  standalone (Android) build and no hand tracking.
- **Off by default.** `project.godot` leaves OpenXR off, so a desktop run
  never starts a runtime. `--xr-mode on` turns it on for one run: on the
  command line, in the editor's Main Run Args, or after an export from
  `export_presets.cfg` (PC VR, Windows and Linux). Without a runtime,
  Godot reports that OpenXR failed to start and the simulator runs on the
  desktop rig.
- **Seated.** The tracking origin is the `Local` reference space
  (`xr/openxr/reference_space=0`). Recentring moves the rig's origin so
  that the head sits on the design eye point of the couch the player is
  in, facing the console, or in Eagle of the station the player stands
  at, facing the window. Eagle's crew stood, so a seated player's head
  goes to a standing eye. It happens on session start, on the runtime's
  own recentre, on B or Y of either controller and on the wrist menu's
  RECENTRE. EYE +1cm and EYE -1cm move that point up or down, by up to
  15 cm, for the player's seated height. The cabin never moves: its
  geometry is the reference.
- **Session.** The simulation keeps running when the headset comes off or
  loses focus: it is a mission clock. `player.xr_session` and
  `player.xr_focus` say where the session is. The runtime paces the
  frames, so V-Sync is off. At session start the frame cap and the
  frame-time budget follow the refresh the runtime reports.

## 2. Input

| Input | Action |
|---|---|
| Fingertip: the green dot just past each controller's tip | Works the panel controls, the DSKY and the wrist menu (§3) |
| B or Y (`by_button`) | Recentre |
| Left Menu button (`menu_button`), or the left palm turned toward the face | Wrist menu |
| Right thumbstick (`primary`) | Rotation controller: pitch (forward = nose down) and yaw |
| Left thumbstick, left and right | Roll |
| Left grip (`grip`) held, with the thumbsticks | Translation controller: left stick ±Y and up/down, right stick forward/back (±X) |
| Right thumbstick, at the lower equipment bay | The optics hand controller: right and left turn the shaft, forward and back raise and lower the trunnion |

Each thumbstick axis reads zero within 15 % of centre
(`HandControllerInput.STICK_DEADZONE`), as each RHC axis has a breakout
detent. A stick that rests off centre or drifts commands nothing, which
matters in CMC MODE FREE and in a manual entry, where the command goes
straight to the jets. Beyond the deadzone the command runs from 0 to 1.
Above 100× the sticks read zero, like the keys.

The thumbsticks stand in for the hand controllers until a grabbed
rotation controller (on the right armrest of the commander's couch) and
translation controller (on the left) are built. gemini-capsule hasn't
built grab interaction either.

## 3. Panel controls

Every control has a touch volume (`src/interaction/control_base.gd`). A
fingertip works it by crossing the volume, and the direction of travel in
the control's own axes decides what happens.

| Control | In the cabin | Fingertip | Desktop pointer |
|---|---|---|---|
| Toggle switch, two to five positions | CMC MODE, UP TLM CM, the SCS's RATE, ATT DEADBAND and SCS TVC, the EMS's ΔV/EMS SET rocker (five positions, springing back to the middle), ELS LOGIC, ELS AUTO, the EDS's EDS AUTO, 2 ENG OUT and LV RATES, RCS QUAD A to D, FC 1 to 3, BATT TO BUS, OPTICS ZERO and OPTICS MODE at the lower equipment bay; in Eagle, LGC MODE, RNDZ RADAR, RCS SYS A and B, and DES RATE, which springs back to the middle | One position per crossing: up through the lever moves it up, down moves it down | A click cycles the positions; the scroll wheel moves it up or down |
| Lever-locked toggle switch | ENG ARM, in Eagle | The first crossing pulls the lever out for 1.5 s, and a crossing within that time moves it | A click or a scroll pulls it out, and the next within 1.5 s moves it |
| Guarded toggle switch | DELTA-V THRUST A and B | The first upward crossing lifts the guard and the next flips the lever. A downward crossing at OFF closes the guard | A click lifts the guard, then cycles the lever; scrolling down at OFF closes the guard |
| Rotary switch | ATT SOURCE, EMS FUNCTION, OPTICS SPEED | One detent per crossing: left to right steps clockwise, right to left anticlockwise | A click steps clockwise and wraps round; the scroll wheel steps either way |
| Pushbutton | UNDOCK, GDC ALIGN, CSM/LV SEP, LM JETT, CM/SM SEP, DROGUE DEPLOY, MAIN DEPLOY, TWR JETT, ABORT (the translation controller's abort handle, turned counterclockwise while it is held), and MARK and MARK REJECT at the lower equipment bay; in Eagle, ABORT STAGE, ENGINE STOP and ENGINE START | Pressed by a fingertip pushed into its face; pulling back out doesn't press it | A click |
| DSKY key | The 19 keys of each DSKY: Columbia's two, on the main display console and at the lower equipment bay, and Eagle's | Like a pushbutton. The touch volumes are shallow, so a finger coming in at an angle presses the key it is on, not the next one | A click |
| Wrist-menu button | §5 | Like a pushbutton | A click |

The FDAI, the mission timer, the main bus voltmeters, the master alarm,
the SPS THRUST ON lamp, the launch's lamps (the LV ENG lights, LIFTOFF,
S-II SEP, and the EDS's ABORT, LV RATE and LV GUID), the DSKY's display and the optics' eyepieces show
their Bus channels and take no input, and so do Eagle's range, range
rate and thrust readouts and LUNAR CONTACT lamps. The eyepieces are one
screen on the lower equipment bay, the telescope's view beside the
sextant's [simplified: the crew looked into two eyepieces].

Rules:

- **Deliberate actuation.** A state changes only on a crossing, never on
  hover, so a hand passing over a dense panel changes nothing it didn't
  cross. A second touch within 0.25 s is ignored (`retrigger_s`).
- **Time acceleration.** Above 100× the panel's switches lock
  (`SimClock.controls_locked()`). The DSKY keys and the wrist menu don't,
  so the crew can always slow the clock.
- **Reach.** The headset has no far-field pointer yet, so a control out
  of fingertip reach can't be worked from that couch. The cabin geometry
  is the reference: seated height is fixed by recentring and the eye
  height, never by moving or scaling the cabin. A control out of reach is
  a layout finding for `data/cockpit/controls.csv` or
  `data/cockpit/lm_controls.csv`, where every position is estimated
  (confidence D).
- **Legibility.** Every control is captioned, and switch positions are
  lettered beside each lever and around each knob.
- **Not built:** switch sounds, haptic pulses, a hand mesh that turns
  translucent inside a panel. The prefabs have circuit breakers, but no
  Apollo panel row uses them yet.

## 4. Comfort

The CM can turn at several degrees per second while the player sits
still, and so can Eagle. The aids are in `src/presentation/comfort.gd`,
on the camera, and read the rates and attitude of the vehicle flown.

- **The cabin is the fixed frame.** The cabin sits at the render origin,
  and the Earth, Moon, Sun and stars turn around it by the inverse of the
  attitude (`src/presentation/space_view.gd`). Nothing but the headset
  moves the camera. In Eagle the render origin is its centre of mass,
  and near the surface the ground is drawn about the eye, below the
  floor.
- **Vignette**, on by default. It narrows the view from 3 deg/s of body
  rate, and is full at 12 deg/s. The CMC holds attitude at 2 deg/s, so
  ordinary maneuvers leave the view alone. In entry it narrows from 2 g,
  to 60 % at 6 g. VIGNETTE on the wrist menu switches it.
- **Horizon ring**, off by default because it is inauthentic: a ring
  round the head, level with the local horizontal. HORIZON switches it.
- **Authentic mode** (AUTHENTIC) turns every aid off: the vignette, the
  horizon ring, the checklist highlight and the gaze tooltip.
- **Frame rate.** The frame budget follows the headset's refresh
  (11.1 ms at 90 Hz). `src/presentation/perf_monitor.gd` publishes the
  frame time, and the wrist menu's top line shows the worst of the last
  90 frames. The Earth, Moon and star shaders haven't been measured in
  stereo yet.
- **Not built:** vibration of the cabin in entry, g-load cues other than
  the vignette, saving the comfort settings.

## 5. Menus and helpers

- **Wrist menu** (`src/presentation/wrist_menu.gd`), on the left hand in
  a headset. It shows when the left palm turns toward the face, and the
  left Menu button shows or hides it whatever the palm does. After HIDE
  it stays closed until the palm turns away and back. The other hand's
  fingertip presses its buttons:
  - MCC, LOI-1, LOI-2 and TEI ask Mission Control for a PAD
    (`ctl.ground.pad_request`, as the HUD does). In Eagle they're DOI,
    PDI, ASCENT and CSI.
  - RATE -, RATE + and PAUSE set the clock.
  - RECENTRE, EYE +1cm and EYE -1cm set the eye point (§1).
  - SEAT moves between the commander's couch, the centre couch and the
    lower equipment bay, and in Eagle between the commander's station and
    the LM pilot's.
  - HIDE closes the menu.
  - CHECKLIST turns to the next checklist where it was left (a finished
    one starts again), NEXT STEP goes past a step without its check, and
    HILITE switches the highlight.
  - VIGNETTE, HORIZON and AUTHENTIC switch the comfort aids (§4), and
    SOUND - and SOUND + set the sound's level, 3 dB a press.
  - FLIGHT turns to its flight page, the flight menu: the mission and the
    start phase chosen with < MISSION, MISSION >, < PHASE and PHASE >,
    a line on each above the buttons, START to fly it in place of the
    flight flown, SAVES, FAILURES and BACK. At launch the menu opens on
    this page, held open until the Menu button closes it.
  - SAVES turns to the saved flights, < SAVED and SAVED > stepping
    through them: SAVE keeps the flight flown now, RESUME flies the one
    shown in place of it, and DELETE, pressed twice, deletes it.
  - FAILURES turns to the instructor's page: the failure catalog, stepped
    through with < FAILURE and FAILURE >, and FAIL, which fails the one
    shown at once. Its caution light comes on, on MDC-2, and its
    malfunction procedure opens on the checklist card.

  The settings (the eye height, the comfort aids, the highlight, the
  sound's level) are kept between sessions as they change.

  Its top line shows GET, the time rate, the worst recent frame time and
  the seat.
- **Checklist card** (`src/presentation/checklist_card.gd`), by the
  commander's left shoulder, 0.5 m from the eye; it moves with the seat.
  It shows the open checklist around its current step, the last PAD
  Mission Control uplinked and CAPCOM's last four calls. The HUD, the
  card, the highlight and the wrist menu share one checklist book.
- **Checklist highlight** (`src/presentation/checklist_highlight.gd`): a
  pulsing frame round the control the current step is done on. A step
  names it (`control` in `checklists.json`), or the highlight finds the
  control that writes the step's check channel.
- **Gaze tooltip** (`src/presentation/gaze_tooltip.gd`): look at a
  control for 0.4 s and a label above it gives its name and position. In
  a headset the gaze is the head's forward axis; on the desktop it is the
  pointer's ray.
- **Seats.** The commander's (left) couch, and the centre couch, where
  the command module pilot worked the DSKY and it is within reach. The
  lower equipment bay, beyond the couches' feet, where the command module
  pilot aligned the platform: facing its navigation panel, head toward the
  apex, with the optics' eyepieces, their switches, MARK and the second
  DSKY within reach, and the right stick on the optics. SEAT moves the
  player and the card, never the cabin. The right couch isn't a seat yet.
  In Eagle the crew stood: the commander on the left and the LM pilot on
  the right, each 1.6 m above the floor.
- **Changing vehicles.** As the LM undocks the rig goes to Eagle's
  commander's station, with the card, the highlight and the wrist menu,
  and back to the CM's couch it left as the two dock. The tracking
  origin goes with it, so no recentre is needed. On the desktop, L
  changes vehicles while the LM flies free.
- **Acceptance recorder** (`src/presentation/vr_acceptance_recorder.gd`).
  In a headset it writes the evidence for `VR_ACCEPTANCE.md` to
  `user://vr_acceptance/` when the session stops or the window closes.
- **Not built:** buttons to jump to a mission phase, start a new flight
  or quit; a guided first run.

## 6. Desktop fallback

The desktop rig (`scenes/player/desktop_rig.gd`) sits at the same eye
point and works the same controls through the same contract, which is
how the tests drive the cabin. C cycles the window, chase and cabin
views. In the cabin:

- A left click works the control under the cursor, and the scroll wheel
  moves a switch or steps a knob. Shift-scroll magnifies.
- Right-click turns mouse look on and off. Z inspects the control under
  the cursor, and Z or Esc returns. Home recentres.
- M shows the wrist menu, which rides on the camera.
- The keys fly the hand controllers: W/S, A/D and Q/E rotate; the arrows
  and R/F translate.

The pointer reaches 2 m from the couch (`CmCabin.CLICK_RANGE`), so the
whole console is in reach, which a fingertip isn't. The 2D HUD stays for
the window and chase views; in the cabin view it hides the DSKY and the
panels the cabin has.

Desktop tests can't wear a headset. The rig, the controls, the menu, the
card, the comfort aids and the recorder are tested on the desktop rig,
and `tests/unit/test_main_scene_xr.gd` runs the main scene's headset
branch against a stand-in for the OpenXR interface. The rest is
`VR_ACCEPTANCE.md`.

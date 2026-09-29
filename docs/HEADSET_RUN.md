# Headset run guide

How to run the headset pass in `VR_ACCEPTANCE.md` (slice 2e in
`ROADMAP.md`) and get a record to paste into the pull request or issue.
One sitting, about thirty minutes in Columbia's cabin and ten in Eagle's.
Adapted from gemini-capsule's `docs/HEADSET_RUN.md`.

## Before you sit down

- Godot **4.4.1** standard build, the same zip CI downloads.
- An OpenXR runtime set as the system default:
  - **SteamVR** (Index, Vive, WMR through SteamVR, or a streamed headset
    such as the HTC Vive XR Elite through VIVE Hub): *SteamVR → Settings →
    OpenXR → Set SteamVR as OpenXR runtime*.
  - **Quest 2/3/Pro through Link or Air Link**: in the Meta Quest Link app,
    *Settings → General → OpenXR Runtime → Set Meta Quest Link as active*.
- A chair you can sit back in. The rig is seated (the `Local` reference
  space). Recentring puts your head on the eye point of the couch you're
  in, so the cabin fits your seated height.

## Run it

OpenXR is off unless you ask for it, so desktop runs never start a
headset runtime. From the repository root:

```
godot --path . --xr-mode on -- --phase=lunar_orbit
```

Without `-- --phase=`, the simulator opens on the flight menu, on your
left wrist: press MISSION > and PHASE > with a fingertip until it reads
Apollo 11 and LUNAR ORBIT, then START.

From the editor, put `--xr-mode on` in *Project Settings → Editor → Run →
Main Run Args* (with *Advanced Settings* on), then press Play.

The console prints `Main: OpenXR initialised, XR rig`, then `Main: OpenXR
session begun (90 Hz)` or your headset's refresh rate. If Godot prints
`OpenXR was requested but failed to start` instead, the runtime isn't
active (see above) and the simulator has started on the desktop rig.

### From an export

CI exports the *PC VR* presets in `export_presets.cfg` (Windows and
Linux) on every merge to `main`: the run's `ApolloVR-pc-vr` artifact on
the repository's *Actions* page holds a zip for each, and a tag's release
has them attached. Unzip one and run it with the same argument as above:
`ApolloVR.exe --xr-mode on -- --phase=lunar_orbit`, or without
`-- --phase=` for the flight menu. To export them yourself you need Godot
4.4.1's export templates (*Editor → Manage Export Templates*):

```
mkdir -p build/windows
godot --headless --path . --export-release "PC VR (Windows)" build/windows/ApolloVR.exe
```

Without the templates, export the game's pack alone and run it with the
same Godot binary:

```
mkdir -p build
godot --headless --path . --export-pack "PC VR (Windows)" build/ApolloVR.pck
godot --main-pack build/ApolloVR.pck --xr-mode on -- --phase=lunar_orbit
```

The presets leave out `tests/`, `tools/` and the GUT addon, and bring
`data/`'s CSV and JSON files.

The `lunar_orbit` start puts you in a 60-mile orbit with Eagle docked, the
lunar surface below and the Earth in view. The checklist card by your left
shoulder opens at *Lunar orbit and TEI*.

## Controls in the headset

| Input | Action |
|---|---|
| B or Y on either controller | Recentre on the couch's eye point |
| Left Menu button, or the left palm turned toward your face | Wrist menu |
| Fingertip (the green dot just past each controller's tip) crossing a lever | Flip the switch one position. Hovering does nothing |
| Fingertip pushed into a key or button | Press it. Tap deliberately: a key ignores a second touch within 0.25 s |
| Right thumbstick | Rotation controller: pitch (forward = nose down) and yaw |
| Left thumbstick, left and right | Roll |
| Left grip held + thumbsticks | Translation controller: left stick ±Y and up/down, right stick forward/back |

A thumbstick axis does nothing within 15 % of centre, so a stick that
rests off centre doesn't turn the spacecraft.

The wrist menu has the PAD requests (MCC, LOI-1, LOI-2, TEI; in Eagle,
DOI, PDI, ASCENT and CSI), time rate,
pause, recentre, eye height ±1 cm, SEAT, CHECKLIST, NEXT STEP, HILITE,
VIGNETTE, HORIZON, AUTHENTIC, SOUND - and SOUND +, and FLIGHT, the
flight menu, with its saved flights. Its top line shows GET, the time
rate, the worst recent frame time and your seat. The eye height you set
is kept for the next session.

There's no far-field pointer in the headset yet. You can only work what
you can reach. SEAT moves you between the commander's couch (left), the
centre couch, where the DSKY is straight ahead, and the lower equipment
bay beyond the couches' feet, where the optics are.

## Work the checklist

Work through these in order. The recorder notes the objective rows itself.

1. **S1, S2.** Put the headset on and check that both eyes show the
   cabin. Note the commit, headset, controllers, runtime and refresh rate.
2. **S3.** Press B or Y to recentre. Try the wrist menu's EYE +1cm and
   EYE -1cm, and recentre again: your eye moves, and the cabin doesn't.
3. **S6.** Open and close the wrist menu with the left Menu button. If the
   palm gesture works, press HIDE while the palm still faces you: the menu
   must stay closed until you turn the palm away and back.
4. **S4, R1, R3, R4.** Sit up, lean and look around: the cabin must not
   follow your head.
   - From the commander's couch, reach every control on the left panel
     (MDC1).
   - Check the windows: the two rendezvous windows are above the console,
     there's a side window on each side, and the hatch window is overhead.
   - Read the checklist card and the DSKY display.
5. **A1.** CMC MODE is the three-position switch on MDC1, right of the
   ATT SOURCE knob. Hover a fingertip over the lever without crossing it:
   nothing happens. Push up through it to AUTO, then down to HOLD. Finish
   at HOLD.
6. **A5.** DELTA-V THRUST A is the red-guarded switch on MDC1:
   - The first upward crossing lifts the guard, and the second flips the
     lever to NORMAL.
   - Push down to OFF, then down again to close the guard.
7. **A6.** ATT SOURCE is the knob left of CMC MODE. A left-to-right
   crossing steps it clockwise one detent: CMC to SCS. Go back to CMC.
8. **R2, A2.** Press SEAT on the wrist menu: you're in the centre couch.
   - Type **V16N62E** on the DSKY with a fingertip: VERB 1 6, NOUN 6 2,
     ENTR.
   - The display shows verb 16, noun 62 and the velocity, altitude rate
     and altitude.
   - **R5.** Press SEAT again: you're at the lower equipment bay, facing
     its panel. Read the optics' eyepieces (the telescope left, the
     sextant right). Set OPTICS MODE to MAN and move the optics with the
     right stick: the stars move across both views. Press MARK and MARK
     REJECT, and reach the second DSKY. Set OPTICS MODE back to CMC.
   - Press SEAT once more to go back to the commander's couch.
9. **A7.** Press NEXT STEP on the wrist menu with a fingertip. The
   checklist card moves on a step.
10. **A3, A4.** With CMC MODE at HOLD, push the right stick forward for a
    few seconds: the FDAI pitches and the Moon moves in the windows. Then
    roll with the left stick. You don't move; the world does.
11. **C1, C2, C3.**
    - Set CMC MODE to FREE and hold the right stick until the view narrows
      (above 3 deg/s). Then set HOLD to stop the rotation.
    - Try VIGNETTE (off and on) and HORIZON (a ring level with the lunar
      horizon; off at start).
    - AUTHENTIC turns every aid off, the checklist highlight too.
12. **C4.** RATE + to 1000x: the thumbsticks do nothing and the switches
    lock, while the wrist menu and the DSKY keys still work. RATE - back
    to 1x.
13. **C5.** Coast for ten minutes at 1x. Note comfort, hitches and frame
    pacing.
14. **S5.** Take the headset off and put it back on, then quit normally.

## Eagle's cabin

A second run checks the LM's cabin (the E rows). It starts in Eagle on
the descent orbit, 20 minutes before PDI:

```
godot --path . --xr-mode on -- --phase=lunar_descent
```

Eagle's crew flew standing, so you stand at the commander's station, on
the left, at its triangular window. Press B or Y to recentre: your head
goes to the commander's eye, 1.6 m above the floor, whatever your seated
height. EYE +1cm and EYE -1cm still adjust it. The wrist menu's PAD
buttons are Eagle's: DOI, PDI, ASCENT and CSI.

1. **E1.** Recentre and look around. Nothing should clip the headset.
   - The window is at your face, and the docking window is overhead.
   - Panel 1 is to your right, with the FDAI, ENG ARM and ABORT STAGE.
   - Panels 3 and 4 (LGC MODE and the DSKY) are below it, between the
     stations.
   - Panel 5 is by your left hand, with ENGINE STOP, ENGINE START and
     DES RATE.
2. **E2.** From the commander's station, reach each of those controls.
   Note any you can't reach.
   - Press SEAT on the wrist menu: you're at the LM pilot's station, with
     panel 2 to your left.
   - Press SEAT again to go back.
3. **E3.** Type **V16N43E** on Eagle's DSKY: VERB 1 6, NOUN 4 3, ENTR.
   The display shows verb 16, noun 43 and Eagle's latitude, longitude
   and altitude.
4. **E4.** ENG ARM is lever-locked, and starts at OFF.
   - Push down through the lever. Nothing moves, but the lever is pulled
     out for 1.5 s.
   - Push down again within that time: DES.
   - Push up twice the same way to finish at OFF.
5. **E5.** The landing point designator's scale is on your window: a
   mark every 5°, from 0 at the top to 65°, with figures every 10°. It
   should sit on the glass, not in front of it or behind it.
6. Quit normally.

If you have time before quitting, fly PDI from the checklist card, which
takes about 25 minutes. RATE + to 10x shortens the coast; go back to 1x
at TIG-10 min, when the card asks for P63. The highlight frames each
step's control. At high gate the landing site sits on the mark N64
gives.

## Get the record

When the session stops or the window closes, the simulator writes:

```
user://vr_acceptance/<utc-timestamp>.json
user://vr_acceptance/<utc-timestamp>.md
```

If the runtime stops the session when the headset comes off and starts
it again when it goes back on, the later stop and the close rewrite the
same two files, so one record covers the whole run. Eagle's run writes a
record of its own, whose E rows are the ones to fill in.

`user://` is:
- Windows: `%APPDATA%\Godot\app_userdata\Apollo CSM Simulator\`
- Linux: `~/.local/share/godot/app_userdata/Apollo CSM Simulator/`
- macOS: `~/Library/Application Support/Godot/app_userdata/Apollo CSM Simulator/`

The `.md` file is the `VR_ACCEPTANCE.md` tables. The objective rows'
evidence is filled in from the Bus:
- the rig, time to session, focus, recentre residual, reference space and
  origin drift, and a clean stop
- which switch, DSKY sequence and menu button a fingertip worked
- the stick deflection and body-rate response
- the vignette and horizon states, the lock above 100x
- frame pacing against the headset refresh
- in Eagle, the recentres at its station, the sequence typed on its DSKY
  and the switches a fingertip worked

Rows marked `tester` are yours. Fill in the Pass column, add the headset,
runtime and date at the top, and paste it into the pull request or issue.
Any Fail row becomes its own issue.

Evidence is evidence, not a verdict. `evidence: pass` on A1 means a switch
changed after a fingertip crossing; that it didn't change on hover is your
observation.

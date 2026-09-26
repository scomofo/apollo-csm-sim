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

![Eagle flying free of Columbia in lunar orbit, with the range to its docking port on the HUD](docs/images/lm_undocked_chase.png)

![Eagle on the descent orbit, 21 nmi up: the view out of its windows, the LGC's DSKY and Eagle's panels](docs/images/eagle_descent_orbit.png)

![The CM cabin in lunar orbit: FDAI, DSKY and the main display console](docs/images/cabin_lunar_orbit.png)

![The checklist card with the TEI PAD and CAPCOM, and the wrist menu](docs/images/cabin_checklist.png)

![Eagle's cabin on the descent orbit: the landing point designator on the commander's window, panel 1 with the FDAI, and the LGC's DSKY on panel 4](docs/images/eagle_cabin.png)

![P52 after 12 hours of translunar coast: the CMC has driven the optics to Menkent from its drifted platform, and the star sits 0.15° off the sextant's reticle for the crew to centre and mark](docs/images/optics_p52.png)

![P23 on the way home: the sextant's landmark line lays the Earth's disc over the star line's view, and Alpheratz sits on its horizon for the mark](docs/images/optics_p23.png)

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
godot --path . -- --phase=lunar_descent         # Eagle after DOI, 20 min before PDI
godot --path . -- --phase=lunar_surface         # Eagle at Tranquility Base, 10 min after landing
godot --path . -- --phase=lunar_ascent          # 20 min before liftoff, the ascent PAD in
godot --path . -- --phase=transearth_coast      # after TEI
godot --path . -- --phase=entry                 # ~15 min before entry interface
```

Later start phases are made by flying the earlier ones through the RTCC's own
solutions (TLI, DOI, the landing time, the liftoff time, TEI), so every
start is consistent with the mission it continues. The LM's start phases
undock Eagle at Apollo 11's time and follow Mission Control's timeline
from there (below), with you in Eagle. Starting in any phase after
`lunar_orbit` takes a few seconds while the ground computes the
trajectory.

`godot --path . --xr-mode on` starts OpenXR, which is off by default, and
puts you in the commander's couch in a headset, or, once Eagle undocks
and in its start phases, at Eagle's commander's station. No headset run
has been recorded yet ([docs/ROADMAP.md](docs/ROADMAP.md), slice 2e).
[docs/HEADSET_RUN.md](docs/HEADSET_RUN.md) walks through one, including
the PC VR exports in `export_presets.cfg`;
[docs/VR_ACCEPTANCE.md](docs/VR_ACCEPTANCE.md) is its checklist, and
[docs/VR_INTERACTION.md](docs/VR_INTERACTION.md) describes how the cabins
work in a headset.

| Input | Action |
|---|---|
| W/S, A/D, Q/E | Rotational hand controller: pitch, yaw, roll (hold Shift for 10 %); in Eagle, its ACA |
| Arrows, R/F | Translational hand controller: ±Y/±Z, +X/−X (ullage); in Eagle, its TTCA: R/F up and down, Up/Down forward and aft |
| 0–9, `=`/`-` (or keypad) | DSKY digits, + and − |
| V, N, Enter | VERB, NOUN, ENTR |
| Space, Backspace | PRO, CLR |
| Insert, Delete | KEY REL, RSET |
| T (hold) | SPS THRUST ON, the manual backup (in Columbia) |
| L | Fly Eagle or Columbia, while Eagle flies free |
| `[` `]`, P | Time rate slower/faster (1× to 10,000×), pause |
| C | Window, chase or cabin view (Columbia's or Eagle's) |
| Right-drag | Look around (window and chase views) |
| In the cabin view: click, scroll | Work the control under the cursor: a click cycles a switch or presses a key, scrolling moves a switch up or down |
| In the cabin view: right-click, Z, Home | Mouse look on and off; inspect the control under the cursor; recentre |
| In the cabin view: M | Wrist menu: PAD requests, time rate, pause, recentre, eye height, seat (the couches, and the lower equipment bay with the optics), checklist, comfort aids |
| O | The optics, the sextant and the scanning telescope: while they're open, W/S and A/D move them instead of the hand controller, X is MARK and Y MARK REJECT. In the cabin they are at the lower equipment bay, where the same keys and the right stick move them |
| F5 / F9 | Save / load checkpoint |
| H | Key help |

Every DSKY key and cockpit switch is also clickable on screen, in the HUD
or, in the cabin view, on Columbia's main display console and lower
equipment bay, or on Eagle's panels. Above 100× the
cabin's switches lock, and its DSKY keys still work. Time acceleration
drops back to 10× by itself when an engine lights, at each scheduled
event (TLI, TIG−60 s, V99, and Mission Control's calls and PADs from
undocking to TEI) and at entry.

## Flying the mission

1. **Parking orbit.** CAPCOM gives you GO for TLI. The S-IVB/IU flies TLI
   automatically at the planned TIG (GET 2:44). Watch it with `V16N62E` or
   `V82E`.
2. **Transposition and docking.** Press **CSM/LV SEP** after cutoff. It
   happens automatically an hour after cutoff if you don't.
3. **Midcourse correction.** With the CMC in P00 and UP TLM CM in ACCEPT,
   press **MCC** under Mission Control. The RTCC solves the burn from the
   state MSFN tracked, and uplinks that state vector and the PAD: P27 and
   V71 on the DSKY while UPLINK ACTY is lit. Then set UP TLM CM to BLOCK.
   On the DSKY:
   - `V37E30E` (P30): check TIG in N33 and PRO; check ΔV in N81 and PRO;
     check the predicted apsides in N42 and PRO.
   - Realign the IMU with P52 option 1, to the preferred orientation P30
     worked out for the burn (below).
   - Set CMC MODE to AUTO. Then `V37E40E` (P40, SPS), or `V37E41E` (P41, RCS)
     for burns under 10 ft/s.
   - At V50N18, press PRO to maneuver to burn attitude. Set ΔV THRUST A and B
     to on.
   - At TIG−5 s, V99N40 flashes: press PRO to enable the engine. Monitor
     V16N40.
   - After cutoff, trim the V16N85 residuals with the THC, then press PRO.
4. **LOI.** About 8 h before pericynthion, press **LOI-1** and fly it
   (~875 m/s, 6 min, 53 × 170 nmi). Two revs later, fly **LOI-2** to
   circularize.
5. **TEI.** Press **LM JETT**, then **TEI**, and fly it. Then fly one or two
   transearth **MCC**s until the vacuum perigee is about 37 km (20 nmi),
   or navigate on board with P23 and plan them with P37 (below).
   Before LM JETT you can undock and dock again (below).
6. **Entry.** Press **CM/SM SEP** and select `V37E61E`. Set ELS LOGIC and
   ELS AUTO on. P64 steers the bank angle at 0.05 g, P67 takes over below
   3 km/s, and the drogue and main parachutes deploy automatically.

**State vectors.** The CMC flies on its own state vector. Its
accelerometers feed it only in P40, P41, P47 and entry, and during TLI. In
coast the SM's vents and the attitude jets' imbalance slowly move the CSM
off it, and so does a translation in P00. Mission Control uplinks the
state vector MSFN tracked with each of Columbia's PADs, and **SV** under
Mission Control asks for one alone. The CMC takes them in P00, with UP TLM
CM (panel 2, right of the DSKY) in ACCEPT. In BLOCK, CAPCOM reads the
PAD up by voice instead.

**The IMU.** The CMC reads its attitude and its accelerometers through
the IMU's stable member, which it takes to lie at REFSMMAT. The gyros
drift the platform off it, about 0.02° an hour, and a burn flown on a
drifted platform goes that far off in direction. Each start phase starts
freshly aligned: to the launch pad REFSMMAT until the lunar orbit, to the
landing site's there, and to the local vertical on the way home. The
FDAI's total attitude and N20 are the ICDU angles, the CSM's attitude
relative to the stable member. GIMBAL LOCK lights past 70° of middle
gimbal, and past 85° the CMC cages the IMU: NO ATT, and the alignment is
lost (P51 and P52 stop with 00220). P40 won't maneuver to a burn attitude
past 60° of middle gimbal (PROG, 00401), and it plans each maneuver
clear of lock: the thrust axis the short way onto the burn's and then a
roll about it, or, where that would pass near lock, one gimbal at a time.

Realign before a burn with P52 (the IMU realign checklist): `V37E52E`,
then `V22E`, the option and `E` (1 the preferred orientation P30 worked
out for the burn, 2 the local vertical, 3 REFSMMAT again, 4 the landing
site's), and PRO. For a new orientation, PRO at N22 drives the gimbals to
it (NO ATT meanwhile). If its middle gimbal is past 60° where the CSM
points, PROG and 00401 say so instead: turn the CSM until N22's middle
gimbal is small, clear of GIMBAL LOCK on the way, RSET, and PRO again.
PRO at V50N25 00015, and the CMC picks two stars.
For each, PRO at N70: the CMC drives the optics to where it expects the
star, in OPTICS MODE CMC. Switch to MANUAL, centre the star in the sextant
and MARK. N05 is the star angle difference, and N93 the gyro torquing
angles; PRO torques the gyros through them. On the desktop, O opens the
optics. In the cabin they're at the lower equipment bay, away from the
couch (SEAT on the wrist menu), with a second DSKY. The optics look out of
the CM's side toward the crew's feet, so in low orbit, heads up, they see
the Moon or the Earth: PROG and 00405 say there are no stars, and you
roll heads down first. A caged platform needs P51 (`V37E51E`). It runs
the IMU up at zero gimbal angles; find two stars yourself, MARK each and
load its octal code (`V21E`, the code, `E`, PRO), and P51 works out the
platform's orientation. The 37 navigation stars and their codes are in
[data/stars/navigation_stars.json](data/stars/navigation_stars.json).

**Navigating on board.** The CMC can keep its own state vector with the
sextant, as the crew did in case the ground went quiet. P23
(`V37E23E`) marks a star on the Earth's or the Moon's horizon. At
V05N70 load the star's code (`V21E`, the code, `E`) and the horizon
(`V23E`, 1 for the Earth's or 2 for the Moon's, `E`), then PRO. A star
behind the body, or more than 57.5° from its horizon, brings PROG and
00404. V50N18 is the attitude that lays the sextant's landmark line,
which looks along the optics' shaft axis, on the horizon under the
star: in CMC MODE AUTO, PRO flies there, and at V51 the CMC has driven
the optics to the star. The sextant lays the landmark line's fainter
view of the Earth or the Moon over the star line's. In OPTICS MODE
MANUAL, move the star onto the horizon and MARK: the trunnion angle is
then the angle between them. V06N49 shows how far the mark would move
the state vector (ΔR in nmi, ΔV in ft/s). PRO takes it in and goes back
to N70 for the next; V32 or MARK REJECT marks again. P37 (`V37E37E`)
works out a midcourse correction from the CMC's own state vector to the
entry corridor's middle, a vacuum perigee of 37 km (20 nmi). N33 has TIG
half an hour on (load another with `V25E`); PRO for the ΔV in N81, PRO
for the apsides in N42, and PRO stores it. Fly it as a PAD's, after P52
option 1. In lunar orbit P22 (`V37E22E`) marks a landmark: the landing
site, unless you load another into N89 (latitude, longitude halved,
altitude). PRO for V50N18, the attitude that points the landmark line at
it on the next pass, and PRO to fly there; the clock stops ten minutes
before the pass. As the CSM comes up on it, the CMC drives the optics to
the landmark, ringed in the optics view: centre it, MARK, and PRO at N49,
a few times through the pass. Each mark is weighted by the navigation
filter's estimate of the state vector's errors. V67 shows their RMS
(N99: position in ft, velocity in ft/s), and loading either starts the
filter again from it. V93 starts it again at the next mark, as a burn of
more than 50 m/s, a start phase or an uplink does.

**Undocking and docking.** In lunar orbit, **UNDOCK** releases Eagle. The
probe pushes the two apart at 0.1 ft/s, and the LM flies free on its own
orbit, with you in it (below). Its computer, the LGC, powers up as it
undocks and holds the attitude it undocked in. Press **L** to go back to
Columbia. While Eagle flies free, Columbia's flight panel shows the
range to its docking port, the range rate, where the port is along the
CSM's axes (X along the probe) and how it moves, and how far the two
docking axes are out of line. Fly the CSM back to it on the translation
controller. The
probe captures, and the vehicles are docked again, when it meets the
drogue at under 1 ft/s, moving across at under 0.5 ft/s, within 1 ft of
its centre, within 10° of alignment and under 1°/s of relative rate. Any
other contact rebounds, and CAPCOM says why.

**Eagle's own burns and the landing.** The LM has its own computer, the
LGC, with its own DSKY. Its descent and ascent engines, its RCS and its
autopilot fly the same way as Columbia's. LOI puts the lunar orbit over
Tranquility Base (0.674° N, 23.473° E) at Apollo 11's landing time.
Mission Control uplinks the DOI PAD and the landing site to the LGC, and
the crew flies DOI with P30 and P40 on the descent engine: 10 % throttle
for 15 s, then 40 %, as Apollo 11 did. Before PDI the ground uplinks the
LM's state vector with the PDI PAD, and it carries the tracking error
(mission.json "pdi"). The LGC flies on its own state vector from then on,
not on truth. Half a revolution after DOI, P63 ignites powered descent
470 km before the site. It brakes at full thrust until the throttle comes
back into its range.

The landing radar under the descent stage finds the ground, the real
ground of NASA's elevation maps. As its data come good, the ALT and VEL
lamps on the LGC's DSKY go out, and N63 shows ΔH, the radar's altitude
less the LGC's: about −3,100 ft here. The crew keys V57, and the radar
pulls the LGC's altitude and velocity in. Without V57 the LGC flies
Eagle into the ground a kilometre short of where it thinks it is. P64
flies the approach from high gate, about 2 km up and 8 km out. The LPD
angle in N64 tells the commander where on the window's scale to look for
the landing point, and each click of the hand controller moves it: 0.5°
fore or aft, 2° left or right. P65 lands automatically. At the first
click of the ROD switch, P66 hands the attitude to the crew while the
throttle holds the descent rate, 1 ft/s per click. CONTACT LIGHT comes
on when a probe touches, and at touchdown P68 shuts the engine down.

**The ascent.** On the surface, Mission Control's ascent PAD gives the
liftoff time. The RTCC flies the LGC's own ascent from where Eagle sits,
and times the liftoff for Columbia to lead by 16.4° at insertion, an
estimate of the lead Apollo 11's rendezvous needed (mission.json
"ascent"). Eagle's and
Columbia's state vectors come up with it. P12 shows the liftoff time
(N33), the insertion targets (N76: 5,535 ft/s, 32 ft/s up, and how far
Eagle sits from Columbia's plane) and the countdown (N74). At V99, five
seconds out, the crew stage with ABORT STAGE, arm the ascent engine and
key PRO: "Abort Stage, Engine Arm, Ascent, Proceed", as Aldrin called
it. The ascent engine lifts Eagle straight up to 40 ft/s while it yaws to
face along Columbia's track, and it pitches over. The LGC's ascent
guidance, after the E guidance Luminary flew, puts it into a 9 × 45 nmi
orbit in Columbia's plane, 60,000 ft up and climbing at 32 ft/s, and the
engine stops about seven minutes after liftoff.

**The rendezvous.** After insertion, Mission Control's CSI PAD carries
the RTCC's plan: Apollo 11's coelliptic sequence, flown from both
vehicles' state vectors, with TPI 2 h 35 min after insertion, as Apollo
11 had it. The ground uplinks CSI's and TPI's times, and Columbia's state
vector as MSFN tracked it, about 900 m off (mission.json "rendezvous").
In P20 the rendezvous radar marks Columbia once a minute, and the marks
take the error out of where the LGC has Columbia relative to Eagle.
V16N54 shows the range, the range rate and Columbia's elevation. P32
targets CSI at the first apolune: the horizontal burn that, with CDH half
a revolution on, has Columbia 26.6° above Eagle's horizon at TPI's time.
P33 targets CDH, onto an orbit a constant 15 nmi below Columbia's. P34
finds when Columbia comes up to 26.6°, and the transfer that meets it
after it has flown 130° of its orbit. P35 corrects the course 15 and 30
minutes after TPI, and P41 flies each burn on the RCS. From a mile out
the commander brakes on the TTCA, holding the closing rate to the range
gates, and stops about 40 m from Columbia. Collins then flies the probe
into the drogue, as he did.

**Mission Control's timeline.** From undocking to TEI, Mission Control
keeps Apollo 11's timeline (mission.json "lunar_timeline"):
- **Undocking and DOI.** CAPCOM gives GO for undocking at 100:00. The DOI
  PAD comes 8½ minutes after Eagle undocks, and GO for DOI 18 minutes
  before the burn.
- **Powered descent.** The PDI PAD's state vector comes 15 minutes before
  PDI, and GO for powered descent 5 minutes before it.
- **On the surface.** CAPCOM gives STAY for T2 and T3. The ascent PAD comes
  at 122:22, for the liftoff window nearest Apollo 11's 124:22 (here
  124:25:40), and "cleared for takeoff" 5 minutes before liftoff.
- **Rendezvous.** The CSI PAD comes 5 minutes after insertion, and GO for
  CSI 13 minutes before the burn.
- **Jettison and TEI.** GO for jettison comes two hours after docking.
  After LM JETT, the TEI PAD comes at 134:01, for the opportunity nearest
  Apollo 11's 135:23:42 (here 135:20:38).

Each PAD comes only when the vehicles can use it, and not while the
ground's last PAD of its kind is still to be flown. An undocking a day
early, for docking practice, brings no DOI PAD. In lunar orbit the flight
phase follows Eagle: LUNAR DESCENT from DOI, LUNAR SURFACE while it is
landed, and LUNAR ASCENT from liftoff until it docks.

The LGC also has P41 (LM RCS), P42 (the ascent engine, after staging)
and P47, and ENGINE START lifts a landed ascent stage off by hand.

**Flying Eagle.** You move to Eagle as it undocks, as its commander, and
back to Columbia when the two dock or Eagle is jettisoned. While Eagle
flies free, **L** changes vehicles. The HUD becomes Eagle's:
- The LGC's DSKY, which the keys type into.
- Eagle's switches: LGC MODE, ENG ARM (ASC or DES), ABORT STAGE, ENG
  START and STOP, RCS SYS A and B, and ROD UP and DOWN for P66.
- Its flight data: its height over the ground below it, its vertical
  speed and its speed over the turning surface, its orbit, its mass and
  rates, the landing radar's ΔH, the rendezvous radar's range and range
  rate, and the ALT and VEL lamps and CONTACT LIGHT.
- Its engines, RCS and LGC, and Mission Control's LM PADs: DOI, PDI,
  ASCENT and CSI.
- The FDAI, on Eagle's attitude and rates and its LGC's errors.

The hand controllers fly its ACA and TTCA. The view is out of its
forward windows, or a chase view above 40 km, and near the Moon the
ground below Eagle is drawn from the same height maps its gear lands on.

**Eagle's cabin.** C's third view, and the only view in a headset, puts
you standing at the commander's station in Eagle's cabin
(`src/cabin/lm_cabin.gd`), at its window. Panels 1 to 5 carry every
switch of Eagle's HUD and its displays (`data/cockpit/lm_controls.csv`):
- Panel 1, to your right: the mission timer, the rendezvous radar's range
  and range rate, the descent engine's thrust, the FDAI, LUNAR CONTACT,
  ENG ARM and ABORT STAGE. ENG ARM is lever-locked: the first push pulls
  the lever out, the second moves it.
- Panel 2, the LM pilot's: its own FDAI and LUNAR CONTACT, and RCS SYS A
  and B.
- Panel 3, between you: LGC MODE.
- Panel 4, below it: the LGC's DSKY, with its ALT and VEL lamps.
- Panel 5, by your left hand: ENGINE STOP and START and DES RATE, the
  rate of descent switch. Scroll it up for +1 FPS and down for −1 FPS.

The landing point designator's scale is on your window: a mark every 5°
down to 65°. In P64 the landing point sits on the mark N64 gives. The
checklist card is by your left shoulder, and the wrist menu's PAD buttons
ask for Eagle's PADs. L takes you to the other vehicle's cabin while
Eagle flies free, and you go aboard with the docking state as on the
HUD.

The on-screen checklist follows along. Steps with a check mark complete
themselves when the Bus shows the action was done. Columbia and Eagle
each have their own checklists, and the HUD shows those of the vehicle
you fly. At the start each opens the one for the flight phase, and so
does the vehicle you board as Eagle undocks or docks; L goes back to the
other's where they stood. Eagle's four take it from the undocking
through DOI, the powered descent and landing, the surface stay and
liftoff, and the rendezvous to docking
(`data/missions/apollo_11/lm_checklists.json`). In the cabin, the same
checklist is on the card by the commander's left shoulder, with the last
PAD and CAPCOM's calls, and a green frame marks the control for the
current step. The wrist menu's NEXT STEP goes past a step without a
check. CHECKLIST turns to the next checklist where it was left, so you
can fly a burn down the SPS burn checklist and come back to the phase's;
a finished checklist starts again. SEAT moves you to the
centre couch, where the DSKY is straight ahead and, in a headset, within
reach, or in Eagle to the LM pilot's station.

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
| [`src/systems/guidance.gd`][g-guidance] + MDIU | `src/systems/agc_core.gd`, `agc.gd`, `lgc.gd`, `ascent_guidance.gd`, `rendezvous.gd` + `src/systems/dsky.gd` | One AGC core (verb/noun DSKY, its own state vector and the ground's uplinks, P30, thrusting programs, P47, DAP) under two program sets: the CMC's P00/27/30/40/41/47/61/64/67 and the LGC's P00/12/20/30/32/33/34/35/40/41/42/47/63/64/65/66/68 |
| — | `src/systems/dps.gd`, `aps.gd`, `lm_rcs.gd`, `landing_radar.gd`, `rendezvous_radar.gd` | The LM's descent and ascent engines, its RCS, and its landing and rendezvous radars |
| — | `src/dynamics/terrain.gd`, `data/terrain/`, `tools/terrain/build_terrain.py` | The surface from NASA's elevation maps: LROC's Apollo 11 site model at 4 m, SLDEM2015 along the approach, LOLA elsewhere (sources in NOTICE) |
| [`src/mission/mission_sequencer.gd`][g-sequencer] | rewritten | Phases, S-IVB/IU TLI automation, separations, failures, CAPCOM |
| — | `src/mission/rtcc.gd` | Ground targeting: TLI, MCC, LOI-1/2 over the landing site, TEI, the LM's DOI for the landing pass, its liftoff time and its rendezvous (the CSI PAD), by shooting on the flight model. The sequencer's PDI PAD uplinks the LM's state vector with its tracking error, and the CSI PAD the CSM's with its own |
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
gemini-capsule's interaction layer, rigs, panel prefabs and data-driven
panel layout. They were taken later than the rest, at commit
[`40e449c`](https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52).
The CM cabin (`src/cabin/cm_cabin.gd`), Eagle's (`src/cabin/lm_cabin.gd`,
milestone 3), what they share (`src/cabin/cabin.gd`) and the cabin DSKY
(`scenes/instruments/cabin_dsky.gd`) are new. Every row of
`data/cockpit/controls.csv` places one control or display on the main
display console, and every row of `lm_controls.csv` one on Eagle's
panels, at estimated positions (confidence D) until the panel drawings
are transcribed.

| Gemini capsule | Apollo CSM | Changes |
|---|---|---|
| [`src/interaction/control_base.gd`][v-control-base], [`interactor.gd`][v-interactor] | same paths | Two additions to `control_base.gd`: a fingertip crossing names the control on `player.last_touch_label` before it counts, so the headset recorder can tell DSKY keys and menu buttons apart; and a hidden control takes no pointer or gaze ray, since Eagle's cabin and Columbia's share the render origin |
| [`scenes/controls/`][v-controls]: toggle, rotary, pushbutton | same paths | They start from the value the Bus already holds (the simulation's state, a checkpoint, the HUD) instead of publishing their initial position over it, and the toggle and rotary follow later changes. A two-position toggle can publish a bool, as the HUD does, and a toggle a value for each position (Eagle's ENG ARM and DES RATE) |
| [`scenes/controls/circuit_breaker.gd`][v-breaker] | same path | Gemini's overhead face style, drawn for its SC-4 overhead panel, is left out |
| [`scenes/instruments/`][v-instruments]: lamp, numeric display, clock, flag, round gauge | same paths | None. `Units.convert()` and a minimal `src/presentation/cabin_materials.gd` exist for them, and `src/core/frames.gd` for the FDAI |
| [`scenes/instruments/fdai.gd`][v-fdai] | same path | Shows the view from inside the ball, like the flown instrument: Gemini's ball reads pitch and yaw reversed. The ball also turns relative to its case, so a tilted panel doesn't tilt the horizon. On Eagle's panels it reads the LGC's attitude, level with the windows forward and the LM's +X up |
| [`scenes/player/xr_rig.tscn`][v-xr-rig], [`openxr_action_map.tres`][v-action-map] | same paths | Each fingertip has its own collision shape and a small green marker, so the player can see it. OpenXR is off in `project.godot` until `--xr-mode on`, with the seated Local reference space (Gemini's `project.godot` sets Stage) |
| [`scenes/player/desktop_rig.gd`][v-desktop-rig] | same path | No keyboard head movement, because W/A/S/D/Q/E fly the RHC here. Recentre is the `recenter` action on Home, because R is the THC's +X |
| [`src/interaction/hand_controller_input.gd`][v-hci] | same path | Writes `ctl.rhc` and `ctl.thc` from the keys and the thumbsticks; holding the left grip switches the sticks to the THC. `for_xr_rig()` reads a headset's hands, and each stick axis has a 15 % deadzone, for the RHC's breakout detents |
| [`src/presentation/wrist_menu.gd`][v-wrist-menu] | same path | Apollo's buttons: the PAD requests (writing `ctl.ground.pad_request`, as the HUD does), time rate, pause, recentre, eye height, SEAT, CHECKLIST, NEXT STEP, HILITE, VIGNETTE, HORIZON and AUTHENTIC. In Eagle the PAD buttons ask for DOI, PDI, ASCENT and CSI, and SEAT goes to the LM pilot's station. Gemini's guide and new-flight buttons stay behind, and settings aren't saved yet |
| [`src/presentation/comfort.gd`][v-comfort] | same path | Reads `dyn.omega`, `dyn.g_load` and `guid.indicator.attitude` in place of Gemini's `guid.rate.*`, dynamic pressure and `guid.att.lvlh`: the vignette starts at 3 deg/s of body rate and 2 g in entry. In Eagle it reads Eagle's rates and the LGC's attitude |
| [`src/presentation/gaze_tooltip.gd`][v-tooltip], [`perf_monitor.gd`][v-perf] | same paths | None. The frame budget follows the headset's refresh at session start |
| [`src/presentation/vr_acceptance_recorder.gd`][v-recorder] | same path | Apollo's rows: a panel switch, a DSKY verb and noun and a wrist-menu button worked by fingertip, the thumbsticks on the rotation controller, the vignette, the horizon aid's default and the lock above 100×, in place of Gemini's ACE POWER and RATE CMD. Eagle's rows: recentres at its station, a verb and noun on its DSKY and its switches touched. A later session stop rewrites the record, so a headset taken off mid-run doesn't cut it short |
| [`docs/VR_INTERACTION.md`, `HEADSET_RUN.md`, `VR_ACCEPTANCE.md`][v-vr-docs], [`export_presets.cfg`][v-export] | same paths | Rewritten for the CM, with Eagle's cabin added. The PC VR presets (Windows, Linux) leave out `tests/`, `tools/` and GUT; Gemini's Quest preset stays behind |
| [`src/presentation/checklist_highlight.gd`][v-highlight] | same path | Finds the control from the step's `control` or its check channel, and the frame fits the control's footprint, DSKY included. Off with HILITE or in authentic mode |
| [`src/cabin/cockpit_layout.gd`][v-layout], [`controls.csv`, `channels.csv`][v-cockpit-data] | `src/cabin/cockpit_layout.gd`, `data/cockpit/` | Rows are checked against their cabin's panels (`CmCabin`'s, or `LmCabin`'s for `lm_controls.csv`) and the channel types in `channels.csv`, and for overlaps. No `spec_id` column until a CM or LM cockpit spec exists. A switch on a bool channel publishes a bool; switch positions are lettered beside the lever and around the knob |
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
[v-layout]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/cabin/cockpit_layout.gd
[v-wrist-menu]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/wrist_menu.gd
[v-highlight]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/checklist_highlight.gd
[v-cockpit-data]: https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52/assets/data/cockpit
[v-comfort]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/comfort.gd
[v-tooltip]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/gaze_tooltip.gd
[v-perf]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/perf_monitor.gd
[v-recorder]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/src/presentation/vr_acceptance_recorder.gd
[v-vr-docs]: https://github.com/scomofo/gemini-capsule/tree/40e449cfb8c35111de47a33bd351b2d945e6fa52/docs
[v-export]: https://github.com/scomofo/gemini-capsule/blob/40e449cfb8c35111de47a33bd351b2d945e6fa52/export_presets.cfg

## Fidelity

These parts are modelled from published figures (rounded; see
`data/spacecraft.json`):

- SPS (20,500 lbf, Isp 314 s)
- SM RCS (100 lbf jets)
- LM descent engine (10,125 lbf, throttleable from 10 % to 60 %, Isp
  311 s), ascent engine (3,500 lbf) and RCS (100 lbf jets in two systems)
- The rendezvous radar's range (400 nmi), and the TPI elevation and
  transfer angle (26.6° and 130°)
- J-2 TLI (the burn takes about 5 min)
- CSM, LM and S-IVB masses (the LM's split between its stages is
  estimated)
- CM hypersonic L/D 0.3
- Parachute deployment altitudes

A flown Apollo 11 profile in the simulator reproduces these values:

| Quantity | Simulator | Apollo 11 |
|---|---|---|
| TLI | GET 2:44:48, 3,273 m/s, the plane turned 5.0° | 2:44:16, ~3,180 m/s, 1.3° |
| Translunar coast | 73.0 h | 73.0 h |
| LOI-1 | GET 75:49:46, 875 m/s, 6.1 min, 53 × 170 nmi | 75:49:50, 889 m/s, 5.95 min, 61 × 169 nmi |
| TEI | GET 135:20:38, 1,000 m/s | 135:23:42, 1,001 m/s |
| DOI | GET 101:36:14, 73.1 ft/s, 30 s | 101:36:14, ~76 ft/s, ~30 s |
| Powered descent | 12 min 6 s, touchdown at 102:45:39, 140 m from the target (the LGC's crossrange error, which the radar can't see) | 12 min 35 s, touchdown at 102:45:40, about 6 km past the target |
| The Sun at touchdown | 10.7° up | 10.8° up |
| Ascent, liftoff to cutoff | GET 124:25:40, 7 min 8 s, then 60,054 ft and 32.0 ft/s up, 9.0 × 45.1 nmi | 124:22:00, 7 min 17 s, then 60,666 ft and 32.8 ft/s up, 9.5 × 47.3 nmi |
| CSI | 52.4 ft/s, 50 min 50 s after insertion | 51.5 ft/s, 50 min 18 s after insertion |
| TPI | 24.0 ft/s, 2 h 34 min 20 s after insertion | ~25 ft/s, 2 h 34 min 35 s after insertion |
| Midcourse corrections | 0.2 and under 0.1 ft/s | ~1 ft/s each |
| Braking, then station-keeping | 15 min 27 s, station-keeping 45 min after TPI | 15 min 8 s, station-keeping 48 min after TPI |
| Docking | GET 127:57:20, 50 min after TPI | 128:03:00, 59 min after TPI |
| Entry peak load | 7.1 g | ~6.5 g |
| Splashdown | 8.6 m/s | — |

Deliberate simplifications are tagged `[simplified]` in the code. The main
ones:

- **Gravity.** The Earth, the Moon and the Sun pull where JPL's
  ephemeris (DE441) has them on Apollo 11's dates, and the Moon turns by
  the IAU's rotation model. The Earth is oblate to its zonal harmonics,
  J2 to J4, about its mean pole of date: its tesseral harmonics and
  nutation are left out. The Moon pulls as a point, without its mascons.
  The onboard computers and the RTCC integrate the same gravity.
- **Navigation.** Both computers fly on their own state vectors, which the
  ground's uplinks correct, and the CMC's own marks too. MSFN's tracking error is drawn fresh for each
  uplink, not from tracking arcs. The CSM's unmodelled forces are a
  steady vent force and its jets' imbalance, drawn once for the flight,
  and the LM and the S-IVB have none. The LGC's Average-G runs all the
  time Eagle flies free.
- **The IMU.** The CMC's gyros drift at a steady rate, drawn once for the
  flight, with no drift that follows the acceleration, and its
  accelerometers have no bias or scale error. A coarse align lands within
  0.2° of its angles; the marks and the gimbals read to a CDU count
  (0.011°). The LGC's IMU is ideal, its REFSMMAT the ECI frame and its
  attitude true: its P52 with the AOT, and P57 on the surface, are left
  for later.
- **The optics.** The telescope shares the sextant's star line, without a
  trunnion of its own. Their view shows the 37 navigation stars and the
  Earth, the Moon and the Sun, without the fainter stars, aberration or
  the docked LM in the way; the sextant's landmark line shows only the
  Earth and the Moon. The telescope names its stars, which the flown one
  didn't; NAMES turns that off. P22's landmark is ringed, since the
  view's Moon is a plain disc. In the cabin the eyepieces are one
  screen on the lower equipment bay.
- **Onboard navigation.** The CMC's filter keeps the state vector's error
  covariance itself, where Colossus kept its square root (the W matrix),
  and starts it from RMS errors the crew can load with V67; an uplink
  starts it again, as the crew's V93 would. P23 marks the solid limb,
  not the atmosphere's horizon some 30 km up, so there is no horizon
  altitude to calibrate, and it marks stars on horizons only, not on
  landmarks. The tests' crew lays the star on the horizon by setting the
  trunnion, without trimming the attitude or the shaft. P37 aims at the
  corridor's middle with the RTCC's integrated targeting, where
  Colossus's P37 worked in conics to an entry flight path angle, and has
  no landing-site options. P22's landmark is known exactly, and its marks
  update the CSM's state vector only.
- **S-IVB guidance.** It thrusts along the velocity, turned out of the
  plane by a fixed yaw, and cuts off on energy, instead of flying
  iterative guidance. Apollo 11's TLI takes a yaw of 14.5° and turns the
  plane 5.0°, where the IU turned it 1.3°: a fixed yaw does less for the
  aim than the IU's steering, and the parking orbit hasn't turned with
  the oblateness. So TLI costs 3,273 m/s, against Apollo 11's ~3,180.
- **P40 steering.** P40 holds the N81 direction in the rotating LVLH frame,
  standing in for cross-product steering.
- **Entry guidance.** It is a constant-drag bank controller without range
  targeting.
- **Atmosphere.** Earth rotation and winds are ignored.
- **Launch.** There is no launch phase.
- **The landing.** The surface is NASA's elevation maps, smooth between their
  posts: 4 m at the site, so no smaller rocks, and the gear meets the
  ground level, straight below the centre of mass. The descent's guidance
  targets are this simulator's own, designed after Klumpp's Apollo
  guidance. The tracking error is set in the mission data, where it meets
  PDI, and the landing radar is noise-free. The LGC has no terrain model,
  as Apollo 11's had none, so the radar's altitude over lower ground reads
  high. The crew's ENGINE STOP after contact light is the LGC's at
  touchdown. The LM can't tip over or break its gear: a hard landing only
  draws a call from CAPCOM. From Columbia the Moon is a sphere. From
  Eagle the ground below it is drawn from the maps, on a grid of rings
  that thins out away from the LM, so relief far from it is smoothed. It
  is lit as a plain matte surface, without the Moon's own photometry.
- **The LM.** Its systems power up as it undocks. Docked, it is dark,
  and the CSM flies the stack. The crew's throttle-up in DOI is the
  LGC's. The descent engine has no gimbal trim, and staging leaves the
  descent stage behind, no longer simulated. The ascent engine fires only
  after staging (no fire-in-the-hole abort).
- **The ascent.** The ground times the liftoff from both vehicles' true
  state vectors, and uplinks them as the truth. The lead Columbia has at
  insertion is estimated from Apollo 11's rendezvous. P12's steering
  takes the engine's nominal thrust for its acceleration, not the
  measured one.
- **Eagle's cockpit.** On the HUD it is a desktop overlay, not Eagle's
  panels: the LGC's DSKY and the switches the LM's burns and landing
  need, with no abort guidance section. The window view from Eagle is
  from its centre of mass, and its chase view gives way to the window
  view below 40 km, where a camera beside it would see the scaled Moon
  from the wrong place.
- **Eagle's cabin.** It is a blockout, like the CM's: the shell and the
  stations follow the LM in outline, and every panel position is
  estimated. The panels carry only the controls and displays the
  simulator models. LGC MODE stands in for the PGNS mode control, ABORT
  STAGE and ENGINE STOP are momentary, and a number stands in for each
  tape meter. The LPD's scale is for the commander's design eye. Seen
  from the cabin, the ground is drawn about the eye, at a scale that
  keeps it below the floor, and Columbia no nearer than 2.8 m. Eagle
  casts no shadow on the ground, and the descent stage can't be seen
  from inside.
- **The LM's start phases.** Columbia drifts in CMC MODE FREE while
  Eagle flies. The start phases fly DOI as the RTCC models P40's burn,
  and set Eagle down on the site at the time DOI planned for. They leave
  the descent stage the propellant the automatic landing leaves.
- **The rendezvous.** The rendezvous radar is noise-free and finds
  Columbia wherever it is, without gimbal limits or a manual lock-on.
  P20 weights each mark by fixed gains, not Luminary's filter, and
  updates only Columbia's state vector. The RTCC and P32 to P35 target
  impulsive burns on the flight model, which P41 flies as finite ones,
  and CDH comes half a revolution after CSI. MSFN's error in Columbia's
  state vector and the braking gates are estimates.
- **Docking.** Capture docks the vehicles hard at once, without a soft
  dock and probe retraction. Only the probe can touch the LM: the
  vehicles' bodies pass through each other. The docking geometry, the
  push apart at undocking and the capture limits are estimates.
- **The cabin.** It is a blockout: the vessel, couches and console follow
  the CM in outline, and every panel position is estimated. The Block II
  main display console layout is on file in
  `reference/nasa-history-diagrams/` (the Operations Handbook's
  Figure 3-1, sheets 1-6, with its position grid). It gives control
  identity and placement, not physical dimensions.

## Tests

From the repository root:

```
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```

That runs the whole suite, which takes a quarter of an hour, nearly all
of it in the scenario tests. Add `-gdir=res://tests/unit/` to run only
the unit tests, in about a minute, or `-gselect=<name>` to run only the
scripts whose file names contain `<name>`. CI runs the suite in four
parts side by side (`.github/workflows/ci.yml`): the unit tests, and the
scenario tests dealt out over three jobs.

The unit tests cover:

- The Bus
- The propagator: orbit closure, step independence, SOI re-basing, lunar
  orbit stability
- The Moon-fixed frame on the circular model: the Moon keeps a face to
  the Earth and turns once a sidereal month, and selenographic
  coordinates round-trip
- The ephemeris (`tests/unit/test_ephemeris.gd`): the fitted series
  against JPL's values held out of the fit, the Moon-fixed frame against
  Horizons' sub-Earth point and the libration's limits, smooth joins
  between segments, the Moon's spin as its frame turns, the Sun 10.7°
  over Tranquility Base at touchdown (the mission report has 10.8°), the
  Moon's pole 6.6° from its orbit's normal, a sidereal month of 27.32
  days, and the mission choosing the model
- The terrain: Tranquility Base 1,927 m below the reference sphere, West
  crater 30 m deep east of the LM, and the maps blending without steps
- The landing radar: its slant range to the ground in both antenna
  positions, over West crater too, its data-good ranges and its velocity
  over the turning surface
- The ascent guidance: its targets are a 9 × 45 nmi orbit, it pitches
  over along the track, steers back into the CSM's plane, and its time to
  go is the rocket equation's
- The rendezvous targeting: the CSM's elevation, the next apsis, CDH
  leaving the LM the same height below the CSM's orbit all the way round,
  CSI sized for the TPI elevation at TPI's time, and TPI's time and its
  transfer meeting the CSM (24.6 ft/s, and 31.6 ft/s to brake)
- The rendezvous radar: range, range rate and the line of sight in the
  LM's axes, and no data with the Moon in the way, beyond 400 nmi,
  docked or powered down
- DSKY key logic, with V01 showing R1 alone
- CMC programs
- The navigation filter (`tests/unit/test_nav_filter.gd`): the
  star-horizon angle and its gradient against finite differences, a star
  behind the Earth, the landmark's line of sight, a scalar update, the
  transition matrix, the covariance carried between marks, and a
  checkpoint
- The IMU, the stars and the optics (`tests/unit/test_imu.gd`): the
  gimbal angles in the gimbals' order and to a CDU count, the preferred
  and landing site REFSMMATs, a drift that adds up over 1.8 million
  fixed steps, the attitude and the sensed ΔV turned by a misalignment
  and torqued back, a coarse align's time and accuracy, GIMBAL LOCK at
  70° and the cage at 85°, V41 N20, the 37 stars' codes and positions,
  the optics' line of sight, modes and limits, the optics view's
  projection, and the DSKY's octal and three-decimal registers
- Systems: SPS arming, EPS consumption and the Apollo 13 failure, SCS/CMC
  autopilot, the coast-step policy
- Checkpoint round-trip, with a map of vehicles, each with its own
  systems, the LGC's rendezvous state, Mission Control's planned times
  and timeline, the CMC's state vector, the CSM's unmodelled forces and
  where MSFN's draws have got to, the CMC's IMU and a P52 between its
  marks, and its navigation filter and a P23 mark waiting at N49
  (schema 8). Older checkpoints are rejected
- The main scene, and in Eagle from `lunar_descent`: its HUD, the keys on
  its LGC, its two views, its checklist for the phase, and L between the
  vehicles
- The hand controllers, from the keys and from the XR thumbsticks, with
  the thumbstick deadzone, and in Eagle its ACA and TTCA about its own
  axes, as its FDAI reads them
- Which vehicle you fly: Eagle from undocking, Columbia again at docking
  or jettison, and L between them while Eagle flies free. Boarding, not
  L, opens the vehicle's checklist for the phase
- Columbia's and Eagle's checklists: each opens the one its phases name,
  and the HUD shows the checklists of the vehicle flown, both keeping up
  with the Bus whichever shows
- The space view: the cabin and the cameras stay fixed while Earth, Moon,
  Sun and stars turn around them with the attitude, and the LM, once it
  undocks, is drawn where it flies and turned as it is. From Eagle, the
  two vehicles are drawn as they are to each other, and on the surface
  the ground takes the sphere's place, 3.6 m below its centre of mass,
  with Columbia drawn nearer than the ground. From Eagle's cabin the
  ground is drawn about the commander's eye, 2.2 m below it, beneath the
  cabin's floor, and Columbia outside the cabin, 2.8 m out
- The ground below Eagle: the maps' heights on its grid, placed at the
  Moon's scale with the eye at the origin, a new grid as Eagle moves on
  or comes down, and the last one drawn while a worker builds the next
- Eagle's cabin (`tests/unit/test_lm_cabin.gd`):
  - The commander stands at the window, 1.6 m above the floor.
  - Each panel faces the crew member who works it, inside the shell.
  - The bulkheads are whole but for the windows and the way aft.
  - The LPD marks are where the commander looks at their angles.
  - The DSKY is within reach of both stations, and SEAT goes between
    them.
  - The cabin stays about the centre of mass as Eagle stages
- The cabin controls and instruments, the XR and desktop rigs and the
  OpenXR action map taken from gemini-capsule
- The cockpit layouts: `controls.csv` and `lm_controls.csv` validate,
  malformed rows are reported, and every row round-trips between its node
  and the Bus, a toggle's through its values. Every switch on Columbia's
  and Eagle's HUDs has a cabin control, each cabin DSKY types into its
  computer (Eagle's with its ALT and VEL lamps), and the desktop rig can
  click every control from the commander's couch or station
- What the cabin shows and sets on the Bus: the DSKY display, the FDAI
  attitude, and switches that follow the HUD and checkpoints
- The checklists in the cabin: one book shared by the HUD and the card,
  the card's checklist, PAD and CAPCOM, and the highlight on the control
  each step names or whose channel it checks, in Columbia's cabin or,
  following the player, Eagle's
- The wrist menu: its PAD buttons, Columbia's or Eagle's, its clock,
  recentre, eye-height and checklist buttons, M and the controller
  button, the palm gesture, and buttons that work while the panels are
  locked
- The headset aids: the vignette and horizon ring, Columbia's or
  Eagle's, authentic mode, the gaze tooltip, the frame-time monitor, and
  the seat switch that brings the DSKY within reach
- The main scene's headset branch, run against a stand-in for the OpenXR
  interface: the XR rig and its camera, hands and menu, frame pacing to
  the headset's refresh, one record across a restarted session, and the
  player boarding Eagle's cabin as it undocks

The scenario tests fly real segments through the crew interface:

- S-IVB TLI to lunar arrival
- MCC, LOI-1 and LOI-2 into lunar orbit, each PAD uplinked with the
  state vector MSFN tracked (P27) and flown after a P52 to its preferred
  orientation, as every burn in the suite is. By the LOI PAD the CMC's
  state vector is 93 km off, and the uplink brings it to 0.4 km
- The IMU (`tests/scenarios/test_imu_alignment.gd`), slice 4c's check.
  Twelve hours of translunar coast drift the platform 0.215°, and P52 on
  two stars (Menkent and Altair) leaves 0.003°, under the 0.02° limit,
  with N05 0.004°. A TEI flown on a platform 0.5° off goes 8.59 m/s off
  the aligned flight, where the misalignment predicts 8.56 m/s, and the
  CMC doesn't see it. A yaw in FREE lights GIMBAL LOCK at 70°, cages the
  IMU at 85° and loses the alignment; P52 and P40 refuse (00220), and P51
  finds the platform's orientation on two stars the crew names. P52
  won't coarse align to a new orientation in gimbal lock from where the
  CSM points (00401) until the CSM turns, and P40's maneuver to the burn
  attitude keeps the middle gimbal under 12°. P52 option 1 puts
  the burn attitude at zero gimbal angles, and with the optics on the
  Moon it finds no stars (00405). Sixteen hours of attitude hold on the
  drifting platform cost 0.15 kg of RCS propellant
- The CMC's own state vector (`tests/scenarios/test_onboard_state.gd`),
  slice 4b's check. From a perfect state, a day's translunar coast leaves
  it 541 m off, as far as the SM's vents move a copy of the CSM, and the
  ground's uplink puts it back to MSFN's tracking error, with P27 and V71
  on the DSKY. The CMC takes uplinks only in P00 with UP TLM CM in
  ACCEPT; in BLOCK a PAD comes by voice. A translation in P00 isn't in its
  state vector, and one in P47 is
- Onboard navigation (`tests/scenarios/test_onboard_navigation.gd`),
  slice 4d's check. A TEI flown on a platform 0.5° off leaves a vacuum
  perigee of −115 km, steep of the 25 to 50 km corridor, and the CMC's
  state vector 1.1 km and 8.9 m/s off. With UP TLM CM in BLOCK from then
  on, the crew marks six stars with P23 every four hours from 10 h after
  TEI, three on the Moon's horizon and three on the Earth's. At 38.6 h
  P37 works out 4.0 m/s from the CMC's state, which, flown after P52,
  leaves 29.1 km, where P37 from the unmarked state would have left
  −41.3 km. After two more sessions a second P37 of 0.3 m/s leaves
  37.9 km. P23's dialogue: the codes it won't take, 00404 for a star it
  can't lay on the horizon, the landmark line on the horizon under the
  star, V32 dropping a bad mark, a good one bringing a state vector 50 km
  off to 18 km, V67's RMS, and a load starting the filter again. In lunar
  orbit, five P22 marks on the landing site through one pass bring the
  state vector from 2.2 km off to 53 m
- TEI and the transearth MCCs into the entry corridor
- CM/SM separation, P61/P64 entry and splashdown
- An MCC PAD flown with P30 and P41 using only the cabin's controls,
  each one clicked through the desktop rig
- A PAD requested from the wrist menu through the desktop rig: UPLINK
  ACTY on the cabin DSKY, the PAD on the checklist card, and the
  checklist worked on from the menu and the DSKY
- The headset acceptance recorder on the desktop rig: fingertip crossings
  on a switch, the DSKY and the menu (a click doesn't count), the
  thumbsticks' pitch and roll response, the lock above 100×, aboard
  Eagle a recentre, its DSKY and ENG ARM, at the lower equipment bay the
  optics turned by hand and MARK, and the record it writes
- Every checklist worked through the desktop rig until the card shows it
  complete: parking orbit and TLI, LOI-1, LOI-2 and TEI each down the SPS
  burn checklist on P40 with a residual trimmed on the translation
  controller, each after the IMU realign checklist at the lower
  equipment bay (SEAT, its DSKY, the optics and MARK), LM JETT, and entry
  to splashdown. The cabin scenarios share `tests/cabin_test.gd`
- Undocking and docking in lunar orbit (`tests/scenarios/test_docking.gd`).
  The stack splits with its momentum conserved. An equiperiod separation
  (0.6 m/s radially down) carries the CSM 4ΔV/n ahead of the LM half a
  revolution later, as the linear (Clohessy-Wiltshire) solution has it,
  and brings it back within 5 m a revolution later. A checkpoint taken
  mid-revolution flies on as the uninterrupted run does. The CSM docks
  again on the translation controller, and contacts that close too fast
  or misaligned rebound
- DOI on the LGC (`tests/scenarios/test_doi.gd`), slice 3b's check. Eagle
  undocks, Mission Control uplinks a DOI PAD to the LGC, and P40 flies it
  on the descent engine, at 10 % and then 40 % throttle. Half a
  revolution later Eagle passes its pericynthion within 250 m of the
  PAD's 50,000 ft above the site (15,217 m against 15,239 m), while
  Columbia's orbit stays as it was
- The landing at Tranquility Base (`tests/scenarios/test_landing.gd`),
  slice 3c's check, and slice 3f's for the `lunar_descent` start phase.
  LOI turns the orbit over the site, and the `lunar_orbit` phase starts
  over it. From `lunar_descent`, the timeline's PDI PAD puts the LGC's
  state vector off by the tracking error at PDI. From a checkpoint before
  PDI:
  - The automatic landing. The crew keys V57 when the radar's altitude
    comes good, with ΔH at −948 m, and ΔH is −22 m by high gate. P63,
    P64 and P65 land Eagle 140 m from the site at 0.8 m/s down and none
    across.
  - Without V57, Eagle hits the ground 4 km short at 24 m/s.
  - With a 900 m error along the track, the commander redesignates in
    P64 and lands 2 m from the site.
  - A run takes over in P66 at 150 m, with the hand controller and the
    ROD switch.
  
  A landed LM turns with the Moon, and lifts off on its ascent engine.
- The ascent (`tests/scenarios/test_ascent.gd`), slice 3d's check. Eagle
  is set down at the site. The RTCC times the liftoff for Columbia to
  lead by 16.4° at insertion. P12 lifts off at that time, rises for 8 s,
  and cuts off 7 min 8 s after liftoff. It inserts at 60,054 ft and
  32.0 ft/s up into a 9.0 × 45.1 nmi orbit, within 0.001° of Columbia's
  plane, with Columbia 16.42° ahead and 167 kg of propellant left. A
  checkpoint taken mid-ascent flies on to the same insertion
- The rendezvous (`tests/scenarios/test_rendezvous.gd`), slice 3e's
  check, and slice 3f's for the `lunar_ascent` start phase. From that
  phase, P12 lifts Eagle off at the ascent PAD's time, 124:25:40
  (Apollo 11: 124:22:00).
  - Five minutes after insertion the timeline's CSI PAD plans CSI at
    52.3 ft/s (Apollo 11: 51.5), 15 nmi below Columbia, and TPI at
    24.1 ft/s.
  - Columbia's uplinked state vector is 914 m off, and after 12 marks
    P20 has it within 0.2 m relative to Eagle.
  - The LGC flies the sequence: CDH 2.1 ft/s onto 14.7 nmi below, TPI
    15 s before the plan's time, and midcourse corrections of 0.2 ft/s
    and under 0.1 ft/s.
  - The commander brakes by the gates and stops 40 m out, and Collins
    docks at 0.33 ft/s. Eagle's ΔV, 114.2 ft/s, is 5 % over the RTCC's
    plan (the check allows 20 %).
  - GO for jettison comes 2 h 5 min after docking. After LM JETT, the TEI
    PAD plans TEI at 135:20:38, the opportunity nearest Apollo 11's
    135:23:42
- Mission Control's timeline (`tests/scenarios/test_lunar_timeline.gd`),
  slice 3f. From `lunar_orbit`: GO for undocking at 100:00, the DOI PAD
  8 min 29 s after Eagle undocks, and GO for DOI 18 min 21 s before the
  burn. An undocking a day early brings no DOI PAD. Each LM start phase
  continues the mission: `lunar_descent` on the descent orbit 20 min
  before PDI, `lunar_surface` on the site after the landing, with STAY
  for T3 and the ascent PAD to come, and `lunar_ascent` with the ascent
  PAD in. A checkpoint taken mid-timeline carries on as the uninterrupted
  run does
- Eagle's checklists from its desktop HUD
  (`tests/scenarios/test_lm_checklists.gd`) and from its cabin
  (`test_lm_cabin_checklists.gd`), slice 3f's checks. The two fly the
  same flights (`tests/lm_checklist_flights.gd`). The main
  scene runs in a viewport of its own, worked as a player at the desktop
  works it: the DSKY on the keys through the scene's input, the HUD's
  buttons clicked where they show and its switches set, and the braking
  and the docking on the hand controllers' keys. In the cabin the rig
  clicks each control, the DSKY is typed on panel 4's keys, the steps are
  read off the card and the checklists turned with the wrist menu. Each
  of Eagle's four checklists is flown from its phase's start until the
  HUD, or the card, shows it complete, with the same numbers from both:
  - From `lunar_orbit`: UNDOCK in Columbia at GO for undocking, and DOI
    to a pericynthion 15,265 m above the site.
  - From `lunar_descent`: P63 to P68, and a landing 140 m from the site.
    At high gate the site is 33.9° down the commander's window, and N64
    shows 34.
  - From `lunar_surface`: STAY for T3, the ascent PAD, and P12 to a
    9.0 × 45.0 nmi orbit.
  - From `lunar_ascent`: the liftoff, then P20, CSI (52.4 ft/s), CDH,
    TPI (24.0 ft/s) and the two midcourse corrections on P41, braking by
    the gates on the TTCA's keys in 15 min 23 s, and, after L, Columbia
    flown into the drogue on the THC's keys, capturing at 0.33 ft/s.

  The desktop scenarios share `tests/desktop_test.gd`
- The LM's other systems (`tests/scenarios/test_lm_burns.gd`): P41 on its
  RCS, P47 on a translation, staging and P42 on the ascent engine, its
  autopilot turning and holding it, the LGC dark while the LM is docked,
  and the two computers each keeping its own DSKY

`tools/screenshot.tscn` renders the images above (`--view=0` window,
`1` chase, `2` cabin; `--hud=0` leaves the HUD out, `--menu=1` shows the
wrist menu, `--pad=<kind>` asks Mission Control for a PAD first, and
`--undock=<s>` undocks the LM and lets it drift for that many seconds,
`--vehicle=csm` or `lm` chooses whose view it is while Eagle flies free,
`--optics=<code>` opens the optics on a navigation star, `--seat=LEB`
puts the cabin view at the lower equipment bay, `--p52=<hours>`
drifts that long and starts P52 with the optics open, and `--p23=<code>`
flies P23 to a star, 0 for the first near the Earth's horizon, and lays
it on the horizon).
They were rendered in software, so the frame time on the wrist menu's top
line is the software renderer's:

```
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --out=res://docs/images/x.png
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --undock=400 --yaw=3.6 --vehicle=csm --out=res://docs/images/lm_undocked_chase.png
godot --path . tools/screenshot.tscn -- --phase=lunar_descent --view=0 --out=res://docs/images/eagle_descent_orbit.png
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=2 --yaw=-0.3 --pitch=-0.12 --hud=0 --out=res://docs/images/cabin_lunar_orbit.png
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=2 --yaw=0.55 --pitch=-0.08 --hud=0 --menu=1 --pad=tei --out=res://docs/images/cabin_checklist.png
godot --path . tools/screenshot.tscn -- --phase=lunar_descent --view=2 --yaw=-0.75 --pitch=-0.75 --hud=0 --out=res://docs/images/eagle_cabin.png
godot --path . tools/screenshot.tscn -- --phase=translunar_coast --p52=12 --out=res://docs/images/optics_p52.png
godot --path . tools/screenshot.tscn -- --phase=transearth_coast --p23=0 --out=res://docs/images/optics_p23.png
```

## Roadmap

[docs/ROADMAP.md](docs/ROADMAP.md) plans what comes next, in order of
value: CI, a VR cockpit, the LM and a lunar landing, and navigation
realism. The VR cockpit waits on a headset run. The LM undocks, flies
free and docks again (slice 3a), flies DOI on its own computer (slice
3b), lands at Tranquility Base (slice 3c), lifts off to orbit at the
RTCC's time (slice 3d), and flies the rendezvous back to Columbia, which
docks with it (slice 3e). Slice 3f has given Mission Control its
timeline from undocking to TEI, the LM its start phases, and you Eagle's
cockpit, as a desktop overlay, the view out of its windows, its
checklists, and its cabin, each checklist flown from the HUD and from the
cabin. That finishes the LM milestone; flying Eagle in a headset waits on
the headset run, with the VR cockpit's. In navigation realism, Apollo 11
now flies on JPL's ephemeris (slice 4a), the CMC on its own state
vector, which the ground's uplinks correct (slice 4b), and on its own
IMU, which drifts and which P52 realigns on the stars through the optics
at the lower equipment bay (slice 4c), and on its own sightings: P23's
stars on the horizons keep the entry corridor without an uplink, and
P22 marks landmarks in lunar orbit (slice 4d). That finishes navigation
realism. Next come the flight's remaining simplifications (milestone
5: gravity beyond two points, the S-IVB's iterative guidance, the
launch, P40's cross-product steering and entry range targeting), sound
(6) and the other missions (7).

# Apollo CSM Simulator

A lunar-mission simulator of the Apollo Command/Service Module, built with
Godot **4.4.1** on the architecture of the
[Gemini capsule simulator](https://github.com/scomofo/gemini-capsule). It flies the
Apollo 11 profile from the launch pad, on the Saturn V into Earth parking
orbit, through TLI, midcourse corrections, lunar orbit insertion,
transearth injection, entry and splashdown, with every maneuver planned by
a simulated Mission Control and executed through the Apollo Guidance
Computer's DSKY.

![Chase view in lunar orbit with Eagle docked](docs/images/lunar_orbit_chase.png)

![Apollo 11 16 s after liftoff: the Saturn V climbing from the pad on its S-IC, P11 on the DSKY and the launch checklist](docs/images/launch_chase.png)

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

From the repository root, `godot --path .` opens on the flight menu, in
the cabin: every mission under `data/missions/`, in the order they flew,
each start phase and a line on where it starts. `< MISSION`, `MISSION >`,
`< PHASE` and `PHASE >` choose, and START flies it. Closing the menu (M
on the desktop, the left controller's menu button in a headset) flies the
flight behind it instead, Apollo 11's parking orbit. The menu is the
wrist menu's FLIGHT page, clicked on the desktop and pressed with a
fingertip in a headset; BACK turns to the wrist menu's other buttons. F1, or FLIGHT on the wrist menu, brings it back in a flight, and
the flight chosen starts in place of the one flown, with the eye height,
the comfort aids, the checklist highlight and the sound's level kept.
SAVES on the flight page lists the saved flights, newest first, each
named for its mission, phase and GET: SAVE keeps the flight flown now,
RESUME starts the one shown in place of it, and DELETE, pressed twice,
deletes it. A save made by a version whose checkpoints differ is listed
but can't be resumed. F5 and F9 keep a quick save among them. The saves
are in `user://saves/` and the settings, kept as they change, in
`user://settings.json` (Godot's user data folder for the project). A
flight given on the command line starts without the menu:

```
godot --path . -- --mission=apollo_11           # parking orbit, TLI ahead
godot --path . -- --phase=launch                # on the pad, 20 s before liftoff
godot --path . -- --phase=translunar_coast      # after TLI and docking
godot --path . -- --phase=lunar_orbit           # after LOI-2, 54 × 66 nmi, Eagle docked
godot --path . -- --phase=lunar_descent         # Eagle after DOI, 20 min before PDI
godot --path . -- --phase=lunar_surface         # Eagle at Tranquility Base, 10 min after landing
godot --path . -- --phase=lunar_ascent          # 20 min before liftoff, the ascent PAD in
godot --path . -- --phase=tei                   # Columbia alone, a minute before the TEI PAD
godot --path . -- --phase=transearth_coast      # after TEI
godot --path . -- --phase=entry                 # ~20 min before entry interface, the target in
```

Later start phases are made by flying the earlier ones through the RTCC's own
solutions (TLI, DOI, the landing time, the liftoff time, TEI), so every
start is consistent with the mission it continues. The LM's start phases
undock Eagle at Apollo 11's time and follow Mission Control's timeline
from there (below), with you in Eagle. Starting in any phase after
`lunar_orbit` takes a few seconds while the ground computes the
trajectory.

`-- --mission=apollo_8` flies Apollo 8 instead: the CSM alone, the S-IVB
carrying a test article where Apollo 11's carried Eagle, ten lunar
orbits, and Mission Control's timeline from TLI to the entry. Its start
phases are `launch` (on the pad, AS-503 its Saturn V), `parking_orbit`
(the default), `translunar_coast` (after CSM/LV SEP), `lunar_orbit` (after LOI-2, 60 × 61 nmi), `tei`,
`transearth_coast` and `entry`. `-- --mission=apollo_10` flies Apollo
10: Snoopy flies the landing mission down to 8 nmi over the first
landing's site without landing, stages in orbit and flies the rendezvous
back to Charlie Brown. Its start phases are `launch` (on LC-39B, AS-505
its Saturn V), `parking_orbit` (the default), `translunar_coast`,
`lunar_orbit` (after LOI-2, 61 × 59 nmi),
`lunar_descent` (Snoopy on its descent orbit, 20 min before the low
pass), `tei`, `transearth_coast` and `entry`. `-- --mission=apollo_12`
flies Apollo 12: Intrepid lands beside Surveyor III in the Ocean of
Storms, the landing site moved in powered descent by the ground's noun
69. Its start phases are `launch` (on LC-39A, AS-507 its Saturn V, into
the overcast and its lightning), `parking_orbit` (the default),
`translunar_coast`, `lunar_orbit` (after LOI-2, 66 × 54 nmi),
`lunar_descent` (Intrepid on its descent orbit, 20 min before PDI),
`lunar_surface` (10 min after the landing), `lunar_ascent` (20 min before
the liftoff, Yankee Clipper's first plane change flown), `tei`,
`transearth_coast` and `entry`. `-- --mission=apollo_13` flies Apollo
13: the SM's oxygen tank fails at 55:54:53, and Aquarius, the LM, is the
lifeboat that brings the crew home around the Moon. Its start phases are
`launch` (on LC-39A, AS-508 its Saturn V, whose S-II's centre engine pogo
shuts down), `parking_orbit` (the default), `translunar_coast` and
`tank_failure` (five minutes before the failure). `-- --mission=apollo_14`
flies Apollo 14: Kitty Hawk's DOI with Antares docked, the landing at Fra
Mauro and the direct rendezvous; `-- --mission=apollo_15` flies Apollo
15, the first J mission: Falcon three days at Hadley, past the Apennine
front. Their start phases are Apollo 12's, `lunar_orbit` on the descent
orbit with the LM docked. Each mission is data under
`data/missions/<id>/`: its dates and the JPL ephemeris for them, its
vehicles, its orbits, Mission Control's timeline, the call signs, the
checklists, and its start phases with the flight menu's line on each.

Builds of the PC VR presets (Windows and Linux) come from CI on every
merge to `main`, as the run's `ApolloVR-pc-vr` artifact, and are attached
to a tag's release; each has the executable and its `.pck` side by side.
CI flies a minute of the launch on the Linux build, headless, before it
keeps them (`-- --quit-after=<s>` quits after that many seconds of GET).
It builds a Quest 3 APK the same way, for a Quest by itself, with no PC
([docs/QUEST_STANDALONE.md](docs/QUEST_STANDALONE.md)); no pass on a
Quest has been recorded yet.

`godot --path . --xr-mode on` starts OpenXR, which is off by default, and
puts you in the commander's couch in a headset, or, once Eagle undocks
and in its start phases, at Eagle's commander's station. No headset run
has been recorded yet ([docs/ROADMAP.md](docs/ROADMAP.md), slice 2e).
[docs/HEADSET_RUN.md](docs/HEADSET_RUN.md) walks through one, including
the PC VR exports in `export_presets.cfg`;
[docs/VR_ACCEPTANCE.md](docs/VR_ACCEPTANCE.md) is its checklist, and
[docs/VR_INTERACTION.md](docs/VR_INTERACTION.md) describes how the cabins
work in a headset.

The cabin has sound, on the desktop and in a headset alike:
- the Saturn V's stages, the S-IVB, the SPS, and in Eagle its descent and
  ascent engines;
- the attitude jets, and the air in the launch and the entry;
- the pyros, the docking latches and the parachutes' mortars;
- the switches and the DSKY keys, and the cabin fans;
- the master alarm's tone, which a MASTER ALARM switch-light (on MDC-1,
  MDC-3 or the HUD) silences until the next caution light comes on.

Every voice is synthesised. `-- --o2-failure-in=<s>` fails the SM's oxygen
tank 2 that many seconds into the start phase, as Apollo 13's did, which
sounds the master alarm. No listening pass has been recorded yet
([docs/LISTENING_PASS.md](docs/LISTENING_PASS.md) is its checklist, with a
tool that renders each voice to a file).

Failures are data (`data/failures.json`): an O2 tank, a fuel cell, an SM
RCS quad, the CMC or the IMU fails as the catalog says, lights its caution
and warning light (CRYO PRESS, FC 1 to 3, SM RCS A to D, CMC or ISS, on
MDC-2 and the HUD's C&W line) and sounds the master alarm, and its
malfunction procedure opens on the checklist card. Apollo 12's lightning
is three of them: the fuel cells tripped off their buses (FC BUS
DISCONNECT), the SCE's NORM supply, which no light shows (the ground's
telemetry goes, and Houston calls for SCE to AUX), and the platform
tumbled (ISS, until a coarse align). Apollo 13's S-II centre engine is
another: pogo shuts it down, LV ENG 5 lights, and the IU burns the other
four and the S-IVB longer. A mission arms its own at their times, as
Apollo 13's tank. FAILURES on the flight menu is the
instructor's page: `< FAILURE` and `FAILURE >` step through the catalog,
and FAIL fails the one shown at once.

**The backups.** With the CMC gone, the SCS and the EMS fly the CSM
(`src/systems/scs.gd`, `src/systems/ems.gd`; their switches are on MDC-1
and the HUD):
- **The SCS.** Its body-mounted gyros feed the GDC, which keeps its own
  attitude; GDC ALIGN brings it to the IMU's while the CMC reads it, and
  it drifts a few tenths of a degree an hour from there. With ATT SOURCE
  at SCS the FDAIs show the GDC's attitude. The hand controller commands
  rates: 0.7°/s at full deflection with RATE LOW, 7°/s (20°/s in roll)
  with HIGH. Released, the SCS holds the attitude within its deadband:
  0.2° at RATE LOW and ATT DEADBAND MIN, up to 8° at HIGH and MAX.
- **The SPS under the SCS.** While the SPS fires, its gimbal (±4.5°)
  holds the attitude (SCS TVC AUTO), or turns the CSM on the hand
  controller (RATE CMD, MTVC).
- **The EMS.** Its ΔV counter, set on the ΔV/EMS SET rocker, counts down
  the ΔV its own accelerometer senses along X. With the EMS in ΔV,
  THRUST ON starts the SPS and the EMS ends the burn at −0.1 ft/s.
  Houston's maneuver PADs now give the burn attitude as the FDAI's R, P
  and Y and the counter's setting, ΔVC: the ΔV less the SPS's tail-off.
- **The EMS in the entry.** Set its scroll to the entry PAD's VIO (VO
  SET) and its range to RTGO (RNG SET), and turn it to ENTRY. At 0.05 g
  its light comes on, and the scroll traces g against velocity while the
  range counts down. Ten seconds on, a corridor light says which way the
  lift must point.

**The launch's aborts.** Apollo 11's launch can end in any of its four
abort modes, from the CSM Apollo Operations Handbook's section 2.9 and
the flight's Mission Operation Report (`src/systems/eds.gd`,
`src/systems/les.gd`; the switches and lights are on MDC-1 and the HUD):
- **The EDS.** With EDS AUTO, 2 ENG OUT and LV RATES on, it aborts by
  itself from the liftoff for two S-IC engines out or the launch
  vehicle's rates past their limits, until the IU switches it off at the
  S-IC's centre engine's cutoff. Otherwise the ABORT light is Houston's
  call, and the abort handle (the translation controller turned
  counterclockwise: the HUD's ABORT) is the crew's. LV RATE and LV GUID
  light for the rates and the IU's guidance platform.
- **Mode I**, while the tower is on: the escape motor pulls the CM away.
  In the first 42 s (IA) the pitch control motor tilts it out to sea;
  11 s on the canards turn it blunt end forward. The tower goes when the
  ELS comes on below 24,000 ft, and the chutes follow on the ELS's
  timers. In mode IC the crew may send the tower with TWR JETT.
- **Modes II to IV**, after the tower: the handle cuts the booster off,
  fires the SM's +X jets while it is held, and separates the CSM 3 s
  later. In mode II the CM separates and falls to a full-lift entry. In
  mode III (the crew brought home at once, from 9:00) Houston's PAD
  burns the SPS retrograde. The crew turns the CSM on the SCS at RATE
  HIGH, flies P40, then enters on half lift, rolled 60° to the south. In
  mode IV (from 9:00) Houston's PAD takes the CSM into orbit on the SPS.
- The modes are called as Apollo 11's were: Armstrong's One Bravo at
  0:44, then Houston's Mode One Charlie at 1:58, S-IVB to COI capability
  at 5:27 and Mode IV capability at 9:00.

**Eagle's aborts.** From the descent's ignition to the touchdown, the
LGC answers Eagle's two abort pushbuttons (Luminary 099's P70 and P71;
the switches are on panel 1 and the HUD). Its abort monitor reads them
on channel 30 while its aborts are enabled (LETABORT, set 0.2 s after
the ignition), skipping both while its mode register reads 71 and
ABORT while it reads 70, as Luminary's did:
- **ABORT** (P70): the descent engine throttles up to full thrust and
  P12's guidance flies it to insertion, 60,000 ft up.
- **ABORT STAGE** (P71): the descent engine stops, the LM stages, and the
  ascent engine flies the same guidance, from P63 to P66 or from P70 when
  the descent engine runs low. Each button arms its engine whatever ENG
  ARM says. Below 25,000 ft the LM first rises vertically to 40 ft/s up.
- **The orbit** depends on where Columbia is. Early in the descent Eagle
  is ahead of it, and climbs into an orbit with a high apolune to fall
  behind; later Columbia is ahead, and Eagle goes into a lower one. The
  apolune is the one that brings TPI at the time the PDI PAD gives for
  the abort: 105:12:30 in the first ten minutes, 107:11:30 after, as
  Apollo 11's did. Houston uplinks Columbia's state vector with Eagle's
  before PDI for it, and five minutes after insertion the CSI PAD, from
  which the rendezvous goes as after a liftoff.
- **Eagle's caution and warning lights** (panels 1 and 2, and the HUD's
  C&W line) light its master alarm: DES REG for the descent tanks'
  helium, RCS A or B REG for an RCS system's regulator, LGC and ISS for
  the PGNS. DES QTY comes on quietly with 5.6 % of the descent
  propellant left, about two minutes of hovering. Each failure opens its
  procedure in Eagle's checklist book.
- **Apollo 14's ABORT switch** (the failure catalog's lm_abort_switch):
  a particle in the switch shorts its contacts to the LGC, which sees
  ABORT with the pushbutton out. No light shows it; Houston calls it.
  `V11N10E 30E` monitors channel 30 in R1, each bit 0 while its signal
  is present: its last digit even while ABORT is set. TAP (panel 1, and
  the HUD's TAP PANEL), a tap on the panel by the switch, clears it, as
  the pushbutton's press does, and it comes back. Flying Apollo 14, it
  shorts at the flown times and Houston calls each. After the ignition
  it would start P70; Houston's workaround, in the descent checklist,
  keeps P63 flying: `V21N01E 1010E 107E` before PDI puts 71 in the mode
  register, and the abort monitor takes P71 for running. That also
  passes ZOOM by at 26 s, so THROTTLE (panel 1's lever or the HUD) goes
  to MAX by hand, over AUTO; `V25N07E 101E 200E 1E` sets ZOOMFLAG, and
  the guidance steers; `V25N07E 105E 400E 0E` resets LETABORT, locking
  P70 and P71 out, so an abort now is the AGS's; `V21N01E 1010E 77E`
  puts 63 back, and THROTTLE goes back to MIN.
- **Apollo 14's landing radar** (lm_lr_scale): its range scale goes to
  low with nothing measured, where it takes the range only within 3,500
  ft and the velocity within about 4,600 ft of altitude. Measuring
  nothing, it can't switch back, and ALT and VEL stay on through the
  braking phase; by the mission rules, without the radar by 10,000 ft
  the landing was aborted. LDG RDR (panel 3, standing in for panel 11's
  breaker, and the HUD's LDG RDR CB) pulled and pushed back in brings it
  back in high scale: VEL goes out 20 s later and ALT 22 s later, and
  V57 lets the radar in. Flying Apollo 14, the scale goes low 4 min
  52 s before PDI, and Houston calls for the breaker's cycle 6 min 16 s
  after ignition.
- **Kitty Hawk's capture latches** (csm_capture_latches): the docking
  probe's three capture latches don't engage the drogue, and each
  contact rebounds. With the probe held in the drogue under +X, **PROBE
  RETRACT** (panel 2, and the HUD) pulls the docking rings together, and
  the twelve ring latches fire 4.9 s on: hard dock, which clears it.
  Flying Apollo 14, it fails at CSM/LV SEP, and Houston's calls through
  the attempts come at the flown times after the separation.

The launch vehicle's engines and its guidance platform are on the
failure catalog. A failure can also be armed a time after a mission
event, rather than at a GET.

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
| In the cabin view: M | Wrist menu: PAD requests, time rate, pause, recentre, eye height, seat (the couches, and the lower equipment bay with the optics), checklist, comfort aids, the sound's level, and FLIGHT, the flight menu |
| F1 | The flight menu, in the cabin view: another mission or start phase, started in place of the one flown, and the saved flights |
| O | The optics, the sextant and the scanning telescope: while they're open, W/S and A/D move them instead of the hand controller, X is MARK and Y MARK REJECT. In the cabin they are at the lower equipment bay, where the same keys and the right stick move them. In Eagle, the alignment optical telescope: its DETENT knob turns it, X is MARK X, Y MARK Y and Z REJECT, and `,` and `.` turn its reticle (Shift: slowly); in the cabin it is overhead, between the crew, with the RETICLE rocker |
| F5 / F9 | Quick save, and back to it: in place, or as its flight in place of another mission's. The flight menu's SAVES lists it with the other saved flights |
| H | Key help |

Every DSKY key and cockpit switch is also clickable on screen, in the HUD
or, in the cabin view, on Columbia's main display console and lower
equipment bay, or on Eagle's panels. Above 100× the
cabin's switches lock, and its DSKY keys still work. Time acceleration
drops back to 10× by itself when an engine lights, at each scheduled
event (TLI, TIG−60 s, V99, and Mission Control's calls and PADs from
undocking to TEI) and at entry.

## Flying the mission

1. **Launch.** The launch phase starts on Launch Complex 39A 20 s before
   liftoff, at 13:32:00 UTC. The Saturn V flies itself on the Instrument
   Unit's program, as AS-506 did:
   - the roll and pitch program;
   - the S-IC's cutoffs and staging;
   - the S-II and the S-IVB on the IU's iterative guidance, and the
     tower's jettison;
   - insertion into the 100 nmi parking orbit at 11:51.

   At liftoff the CMC comes up in P11 (V16N62: inertial speed, altitude
   rate, altitude). Panel 1's LV ENG, LIFTOFF and S-II SEP lights show the
   stages, and the launch checklist checks itself off as they come. After
   insertion, `V82E` shows the orbit. A failure in the launch ends it in
   its abort mode (**The launch's aborts**, above).
2. **Parking orbit.** CAPCOM gives you GO for TLI. The S-IVB/IU flies TLI
   automatically at the planned TIG (GET 2:44), on its iterative guidance,
   onto the free return the RTCC planned. Watch it with `V16N62E` or
   `V82E`.
3. **Transposition and docking.** Press **CSM/LV SEP** after cutoff. It
   happens automatically an hour after cutoff if you don't. Flying Apollo
   14, CSM/LV SEP leaves Kitty Hawk free of Antares, still on the S-IVB:
   +X away, pitch through 180° to face its drogue, and dock on the
   translation controller, the flight panel showing the range and
   alignment as for any docking (**Undocking and docking**, below). The
   capture latches fail, as Kitty Hawk's did: hold +X at the contact and
   press **PROBE RETRACT**. If you haven't docked by the flight's
   extraction (5:47), the ground takes it as done.
4. **Midcourse correction.** With the CMC in P00 and UP TLM CM in ACCEPT,
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
5. **LOI.** About 8 h before pericynthion, press **LOI-1** and fly it
   (~875 m/s, 6 min, 53 × 170 nmi). Two revs later, fly **LOI-2** into
   Apollo 11's 54 × 66 nmi orbit, out of round for the Moon's mascons to
   round it toward 60 nmi by the rendezvous.
6. **TEI.** Press **LM JETT**, then **TEI**, and fly it. Then fly one or two
   transearth **MCC**s until the vacuum perigee is about 37 km (20 nmi),
   or navigate on board with P23 and plan them with P37 (below).
   Before LM JETT you can undock and dock again (below).
7. **Entry.** Select `V37E61E`. P61 flashes N61, the target the entry
   PAD's uplink brought, and HEADSUP (-1, lift up); PRO, and PRO again at
   N60 (the peak load expected, and the speed and flight path angle at
   entry interface) and N63 (the EMS's range, speed and time to go). P62
   asks for CM/SM SEP (V50N25 00041): press **CM/SM SEP**, then PRO. At
   N61, set CMC MODE AUTO and PRO: the CM turns to the entry attitude,
   and P63 takes over once it is near. Set ELS LOGIC and ELS AUTO on. At
   0.05 g P64 starts Colossus's entry guidance, which rolls the lift to
   bring the CM down on the target: P65's up-control (PRO at its flashing
   N69), P66's skip on a long range, and P67's final phase, which ends at
   1,000 ft/s with N67 flashing the range to go and where the CM is (PRO
   for P00). The drogue and main parachutes deploy automatically.

**Apollo 8.** With `-- --mission=apollo_8` the flight is Apollo 8's, from
the pad or its parking orbit. From the pad it's the launch above on the
first crewed Saturn V, AS-503, at 12:51:00 UTC on 21 December 1968: its
own stages, clock and flight azimuth, its S-II burning on all five
engines to its cutoff, and insertion at 11:42. The S-IVB flies TLI at the
RTCC's TIG (GET 2:50), and CSM/LV SEP leaves the S-IVB and its test
article behind, with nothing to dock with (it happens by itself 25 min
after cutoff). Mission Control's timeline then brings each PAD at the
flown time, and CAPCOM's calls at theirs:
- the two separation maneuvers from the S-IVB, radially up (3:40 and
  4:45, the second the unplanned one);
- MCC-1 (11:00) and MCC-2 (61:00);
- LOI-1 (69:08) and LOI-2 two revolutions on (73:35);
- TEI on the tenth revolution (89:19);
- the transearth MCCs (104:00, and 122:00 and 144:46 only if the corridor
  needs them);
- the entry PAD (145:12).

Fly each as above: the separation maneuvers and the small corrections on
P41 (the RCS burn checklist), the rest on P40. Realign the platform
before the entry, with P52 option 3.

**Apollo 10.** With `-- --mission=apollo_10` the flight is Apollo 10's,
from the pad or its parking orbit. From the pad it's the launch above on
AS-505, from Launch Complex 39B, the only Saturn V launched from it, at
16:49:00 UTC on 18 May 1969, with insertion at 11:58. The S-IVB flies
TLI at the RTCC's TIG (GET 2:33),
and transposition, docking and extraction follow by themselves 24 min
after cutoff. The timeline's PADs come at the flown times:
- the evasive maneuver on the SPS (4:39);
- MCC-1 (26:33), and MCC-4 (70:56) if the tracking has the approach off;
- LOI-1 at its PAD's TIG (75:56), which turns the orbit into the first
  landing's plane over site 2, and LOI-2 (80:25);
- Charlie Brown's separation PAD before the undocking at 98:12, for 2.5
  ft/s radially down at 98:47;
- Snoopy's DOI PAD after the undocking, for DOI at 99:46, down to 8 nmi
  over the site at 100:44;
- the phasing PAD (100:58), on the DPS at 10 % for 26 s, then full;
- the insertion PAD (102:55) and a state vector for Snoopy, and GO for
  staging: stage (ABORT STAGE) ten minutes before the insertion, then
  fly it on the ascent engine (P42);
- the CSI PAD after the insertion: CSI (103:46), CDH, TPI and the
  midcourse corrections on P32 to P35, as from Apollo 11's
  `lunar_ascent`, braking, and Charlie Brown docks;
- GO for jettison two hours after docking, and TEI (137:36);
- the transearth MCCs (176:50 and 188:50, if the corridor needs them)
  and the entry PAD (190:49).

Snoopy's checklists follow its flight: the undocking and DOI; the low
pass, phasing and staging; the insertion and the rendezvous.

**Apollo 12.** With `-- --mission=apollo_12` the flight is Apollo 12's,
from the pad or its parking orbit. From the pad it's the launch above on
AS-507 at 16:22:00 UTC on 14 November 1969, into the overcast, and
lightning strikes it twice:
- at 0:36.5 the fuel cells trip off their buses: FC 1 to 3, FC BUS
  DISCONNECT and both MN BUS UNDERVOLTs light, and the entry batteries
  carry the mains at 25.5 V. The strike drops the SCE out too, and
  Houston's telemetry with it (the HUD's EPS line reads TM LOST);
- at 0:52 the second tumbles the platform: ISS and NO ATT.

The IU flies on to orbit regardless. At 1:36 Houston calls "Try SCE to
Auxiliary": set SCE PWR (MDC-3, and the HUD) to AUX. Once the telemetry
is back Houston calls for the fuel cells' reset: set each FC switch
(MDC-3) OFF and back ON, as Apollo 12's crew did for 1 and 2 at 2:22 and
3 at 2:50. Insertion is at 11:53. In the parking orbit, P51 (`V37E51E`)
finds the platform again on two stars before TLI; the IU holds the stack
heads down, the optics on the sky.

The S-IVB flies TLI onto the free return at the
RTCC's TIG (GET 2:47), and transposition, docking and extraction follow
25 min after cutoff. The timeline's PADs come at the flown times:
- MCC-2 (30:53), which takes the stack off the free return onto the
  hybrid, and MCC-4 (78:25) if the tracking has the approach off;
- LOI-1 at its PAD's TIG (83:25), which turns the orbit into the plane
  over the landing site, some 14° to the lunar equator, and LOI-2 at its
  own (87:49);
- Yankee Clipper's separation PAD before the undocking at 107:54, for 2.5
  ft/s radially down at 108:25;
- Intrepid's DOI PAD after the undocking, for DOI at 109:20; the PDI PAD
  and its state vector half an hour before PDI (110:20), and GO for PDI;
- after throttle-up, the ground's noun 69: key V21N69E and R1 as CAPCOM
  reads it (+ or −, ft), and the LGC moves its landing site that far
  downrange;
- STAY for T1 and T3; Yankee Clipper's first plane change (119:45), which
  puts its orbit over Intrepid for the liftoff; the ascent PAD (140:19)
  and the liftoff (142:01);
- the CSI PAD after the insertion, and the rendezvous as from Apollo 11's
  `lunar_ascent`; GO for Pyro Arm two hours after docking;
- the second plane change (159:05), for the photographs, a fixed
  maneuver on the SPS;
- TEI (172:24), the transearth MCCs (188:27 and 241:22, if the corridor
  needs them) and the entry PAD (239:32).

The landing site is the Surveyor's, on the inner slope of its crater,
1,432 m below the reference sphere on LROC's model of the site; Intrepid
came down 535 ft from it, on the rim to its northwest. The orbit has
drifted north of the site by PDI, and P63 steers across to it. In P64
the LPD on the window shows where the LGC is taking you: redesignate
with the ACA onto the crater, then take over with the ROD switch (P66)
at a few hundred feet and fly to your spot. Intrepid's checklists follow
its flight, with noun 69 in the powered descent's; Yankee Clipper's has
the plane changes.

**Apollo 13.** With `-- --mission=apollo_13` the flight is Apollo 13's,
from the pad, its parking orbit, or with `-- --phase=tank_failure` from
five minutes before the failure. From the pad it's the launch above on
AS-508 at 19:13:00 UTC on 11 April 1970. At 5:30.6 pogo shuts the S-II's
centre engine down, 132 s before the IU would have, and LV ENG 5 lights:
Lovell's "Inboard." The IU's guidance steers on the four outboard
engines, pitching the stack up 7.6° as it re-plans, and its shift to
the low mixture ratio waits on the velocity it senses, 33 s later than
without the pogo. The four burn 33 s longer, the S-IVB 11 s longer, and
insertion comes at 12:39, 44 s late. TLI puts the stack on the free return, and
MCC-2 (30:41, on the SPS) takes it onto the hybrid, 60 nmi over the Moon.
At 55:54:53 the SM's oxygen tank 2 fails: the master alarm, MAIN B
UNDERVOLT, fuel cells 1 and 3 lost, and tank 1 leaks its oxygen away
while fuel cell 2 carries the CSM, until about 58:15. The timeline's
calls and PADs come at the flown times:
- the emergency power-down (56:16): CM POWER to EMER;
- into the LM (57:41): LM PWR on, its LGC MODE in FREE while the CMC's
  DAP still holds the stack, and the CMC's gimbal angles (57:48) for the
  LGC's coarse align through the docking (V41N20): the CM's inner plus
  180°, and its middle's negative;
- the CSM powered down (58:37): CM POWER OFF, LGC MODE HOLD, and the
  LGC's REFSMMAT, the CMC's carried across (58:44);
- the free return (61:30) and PC+2 (79:28) on the descent engine, P40
  flying the docked stack, PC+2 5 s at the minimum, 21 s at 40 % and then
  full;
- the PGNS off to save the LM's power (82:03); MCC-5 read up by voice
  (104:34) and flown by hand on the AGS at 105:18:28: point +X along the
  burn on the ACA, AGS ALIGN, ullage on the jets, ENGINE START at the
  TTCA's minimum throttle and ENGINE STOP on the DEDA's count;
- the LM charging the CM's entry batteries from 112 hours: LM PWR on the
  CM's panel;
- the PGNS up again for the ground's coarse align angles and REFSMMAT
  (134:40, 135:04), and MCC-7 on the LM's jets in P41 (137:40);
- SM SEP (138:02) with the AGS holding: 0.5 ft/s +X on the jets, CM/SM
  SEP, 0.5 ft/s back;
- the CM's coarse align angles (139:52), its power-up (140:10), state
  vector (140:24) and REFSMMAT (140:45), and a P52; LM JETT (141:30), the
  docking tunnel's pressure pushing Aquarius off; the entry PAD (141:48)
  and the final state vector (142:01).

Aquarius's checklists follow the lifeboat's flight: its activation and
the docked alignment, the descent engine's burns docked, MCC-5 on the
AGS, and the PGNS again for MCC-7 and SM SEP. Odyssey's open on the
failure at `tank_failure`, and on the power-up and entry after the Moon.

**Apollo 14.** With `-- --mission=apollo_14` the flight is Apollo 14's,
from the pad, its parking orbit or any start phase after them. From the
pad it's the launch above on AS-509 at 21:03:02 UTC on 31 January 1971,
40 min late for the overcast, on the 75.6° azimuth the later hour gave.
The timeline's calls and PADs come at the flown times, taken back to
range zero where the flight moved its clocks 40 min 3 s at 54:54:
- GO for TLI (2:27); MCC-2 (30:36), which takes the stack off the free
  return onto the hybrid, and MCC-4 (76:58) if the tracking has the
  approach off;
- after the crew's CSM/LV SEP, Kitty Hawk's capture latches failed, and
  Houston's calls through the attempts to dock at the flown times after
  the separation (3:02:29): the probe's breakers (3:18), +X held at the
  contact (3:23), the normal procedures again (4:15) and the probe's
  retraction (4:39);
- LOI (81:57), centred on the pericynthion the corrections put in the
  plane over Fra Mauro;
- DOI (86:13), Kitty Hawk's with Antares docked, down to 9 nmi at the
  low point: the RTCC sizes it for the landing pass a day later, its PAD
  at 84:52 and GO at 85:39;
- the separation PAD, docked (101:52), for 0.8 ft/s radially down after
  the undocking at 103:47, and Kitty Hawk's CIRC PAD (104:35), back up to
  60 nmi at 105:12;
- the ABORT switch's shorts from 104:16, each called and tapped clear,
  and at 107:34 Houston's workaround, keyed before PDI and after it;
- the landing radar's scale low from 4 min 52 s before PDI, and Houston's
  call to cycle its breaker 6 min 16 s after ignition;
- the PDI PAD and its state vector (105:53), two hours before PDI
  (108:02); GO for Fra Mauro, and noun 69 after throttle-up, keyed as
  Apollo 12's;
- STAY for T1, T2 and T3; Kitty Hawk's plane change (117:30), which puts
  its orbit over Antares for the liftoff;
- the ascent PAD (139:57) for the direct rendezvous, with TPI's TIG for
  N37, GO for liftoff (141:29) and the liftoff (141:44);
- the tweak's PAD after the insertion: a few ft/s on the jets, P30 and
  P41 where Antares is; GO for the APS TPI, and TPI on the ascent engine
  in P42 at N37's time, with N55's elevation loaded as zero (V25N55E,
  +00001E, +00000E, +13000E); P35's midcourse corrections; GO for Pyro
  Arm two hours after docking;
- TEI (148:36), MCC-5 (165:35) and the entry PAD (211:06).

The automatic guidance takes Antares some 1,350 ft short of where it came
down, as it took the flight's: take over with the ROD switch at a few
hundred feet and fly the rest, as Shepard flew 2,000 ft of it in P66.
Antares's checklists follow its flight: the P52 after the undocking, the
descent with noun 69, the surface and the liftoff, and the direct
rendezvous; Kitty Hawk's have DOI and CIRC.

**Apollo 15.** With `-- --mission=apollo_15` the flight is Apollo 15's,
the first J mission, from the pad, its parking orbit or any start phase
after them. From the pad it's the launch above on AS-510 at 13:34:00 UTC
on 26 July 1971, on time, on the 80.1° azimuth. Falcon, the J mission's
LM, carries 1,150 lb more descent propellant in longer tanks and five
descent batteries, for three days at Hadley. The timeline's calls and
PADs come at the flown times, the flight's clocks never moved:
- GO for TLI (2:30), onto a trajectory past the Moon 139 nmi up; the
  SPS's test, flown as MCC-2 (28:40), and MCC-4 (73:31), which bring the
  pericynthion down to 68 nmi in the plane over Hadley;
- LOI (78:32), into the orbit 26° to the lunar equator;
- DOI (82:40), Endeavour's with Falcon docked, down to 10 nmi at the low
  point: the RTCC sizes it for the landing pass a day later, its PAD at
  81:31 and GO at 82:08;
- the separation PAD, docked (98:42), Houston's word on the probe's loose
  umbilical (100:20), the undocking 25 min late at 100:39 and the
  separation after it; Endeavour's CIRC PAD (101:06), back up to 60 nmi at
  101:39;
- the PDI PAD and its state vector (102:28), two hours before PDI
  (104:30); GO for PDI, noun 69 after throttle-up, keyed as Apollo 12's,
  Houston's word to accept the radar's ΔH, and GO for landing;
- STAY for T1, T2 and the three days; Endeavour's plane change (165:12),
  which puts its orbit over Falcon for the liftoff;
- the ascent PAD (170:41) for the direct rendezvous, with TPI's TIG for
  N37, GO for the direct rendezvous (171:29) and for liftoff (171:35);
- "No tweak" after the insertion, and GO for the APS TPI; GO for Pyro
  Arm a revolution late, nearly six hours after docking;
- the shaping PAD for the subsatellite's orbit (220:35), the RTCC's burn
  at its TIG onto its 76 by 54 nmi; TEI (223:49), MCC-7 (291:57) and the
  entry PAD (293:55).

Falcon's descent is Luminary 210's, on its e-load's own targets: the
approach 25° steep past the Apennine front against the H missions' 14°,
P64 at 9 min 23 s. Its terrain model, the e-load's five slopes of the
ground uprange of the site, goes into the landing radar's ΔH: over the
mare it takes the LGC's altitude up thousands of feet, the model's
slope where the mare had none, until the radar sees the foothills. The
automatic guidance takes Falcon to the target, some 2,000 ft south of
where it came down: redesignate the landing point north and on with the
hand controller in P64, as Scott did, and take over at 400 ft. Falcon's
checklists follow its flight: the P52 after the undocking, the descent
with noun 69, the surface and the liftoff, and the direct rendezvous
with no tweak; Endeavour's have DOI, CIRC and the shaping burn.

**State vectors.** The CMC flies on its own state vector. Its
accelerometers feed it only in P40, P41, P47 and entry, and during TLI. In
coast the SM's vents and the attitude jets' imbalance slowly move the CSM
off it, and so does a translation in P00. In lunar orbit the Moon's
mascons move it kilometres off in a few revolutions, since the CMC
integrates the simpler R-2 model its program flew with, as Eagle's LGC
does too. Mission Control uplinks the
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
other contact rebounds, and CAPCOM says why. With the capture latches
failed (Apollo 14's), hold +X at the contact and press **PROBE
RETRACT**: the ring latches fire 4.9 s on.

**Eagle's platform and P52.** The LGC's IMU is a real one, as the CMC's
is. At undocking it stands on the landing site REFSMMAT where the crew's
docked alignment left it, off by what the flight's first P52 found less
its drift since, and its gyros drift at the rates the mission report
measured: Eagle's +4.5, −5.0 and −0.4 mERU in flight, and on the Moon
+2.6, −2.6 and +2.3. Realign it with P52 on the alignment optical
telescope (AOT), as Armstrong did at 101:15:

- `V37E52E`. V04N06 shows the option: `V22E3EP` for option 3, the
  REFSMMAT (1 is the preferred orientation, 2 the nominal, 4 the landing
  site, which asks for the time in N34 and the site in N89). V06N22 shows
  the gimbal angles; PRO.
- At V50N25 00015, PRO for the LGC's pair of stars (R56), or ENTER to load
  your own: at V01N70, `V21E`, the detent and the star (`00225`: the front
  detent, Acrux), `E`.
- For each star: PRO at V01N70; with LGC MODE in AUTO, PRO at V50N18, and
  the LGC turns Eagle to put the star in the detent's field, about a
  single axis at the 2°/s Apollo 11's crew loaded (Luminary's KALCMANU);
  ENTER at V50N18 when it's there.
- At V01N71, PRO, and mark: turn Eagle until the star crosses the reticle's
  Y-line and press MARK Y, then its X-line and press MARK X; up to five
  pairs. REJECT takes back the last mark. PRO when done.
- V06N05 shows the star angle difference and V06N93 the torquing angles;
  PRO torques the platform. At V50N25 00014, ENTER for P00 (PRO checks the
  alignment on the stars again).

**O** opens the AOT's view, turned by its DETENT knob through the six
detents (the rear one, CL, is stowed). Its reticle shows the Y-line, the
X-line and the spirals; `,` and `.` turn it (Shift: slowly), and its
counter reads the turn under the view.

**On the surface: P57.** On the Moon Eagle can't turn to put a star on the
reticle's lines. P57 aligns the platform from gravity and from stars found
with the reticle, as Apollo 11's crew did five times at Tranquility Base:

- `V37E57E`. V04N06 offers option 3, the REFSMMAT: PRO. Or `V22E4EP` for
  option 4, the landing site's orientation at a time: V06N34 offers the
  ascent's TIG (0 for now); PRO.
- V05N06 shows the technique in R2 and the flags in R3 (00100: REFSMMAT
  known; 00010: an attitude stored). `V22E` and 1 for REFSMMAT and
  gravity, 2 for two stars, 3 for gravity and a star, or 0 for the stored
  attitude; PRO.
- For 1 and 3 the platform turns to two orientations and reads gravity at
  each, some two minutes. V06N04 shows the angle to the last gravity
  vector: PRO, or V32 to measure again. Gravity's turns lose the platform's
  orientation; with an attitude stored, V06N22 shows the gimbal angles
  that turn it back: PRO.
- For 2 and 3, at V01N70 key the star (`V21E`, the code, `E`) and PRO.
  V06N79 shows the detent R59 finds it in (R3) and where the cursor and
  spiral will find it; PRO, and PRO at V01N71.
- At the AOT, turn the DETENT knob to that detent and press MARK Y (or X).
  Turn the reticle until the Y-line crosses the star and load the
  counter's reading, the cursor (`V21E`, the reading, `E`). Turn on until
  the spiral crosses it and load that reading, the spiral (`V22E`). V32
  takes another mark, up to five; REJECT drops the last; PRO when done.
- V06N05 shows the star angle difference, PRO; V06N93 the torquing angles,
  PRO. At V50N25 00014, ENTER for P00. For technique 2, V06N89 first shows
  the landing site that gravity and the stars place Eagle at: PRO takes
  it, V34 rejects it, as Houston asked Apollo 11's crew to do.

**Eagle's own burns and the landing.** The LM has its own computer, the
LGC, with its own DSKY. Its descent and ascent engines, its RCS and its
autopilot fly the same way as Columbia's. LOI puts the lunar orbit over
Tranquility Base (0.674° N, 23.473° E) at Apollo 11's landing time.
Mission Control uplinks the DOI PAD and the landing site to the LGC, and
the crew flies DOI with P30 and P40 on the descent engine: 10 % throttle
for 15 s, then 40 %, as Apollo 11 did. P40 to P42 steer as Luminary's
did: the velocity to be gained at ignition, the ΔV turned through half
the burn's arc, is drawn down by the ΔV the LM senses, and the thrust is
held on it, the LM's roll left alone. Before PDI the ground uplinks the
LM's state vector with the PDI PAD, and it carries the tracking error
(mission.json "pdi"). The LGC flies on its own state vector from then on,
not on truth. Half a revolution after DOI, P63 ignites powered descent
470 km before the site. For 26 s it holds the attitude at 10 %; then, at
ZOOM, it throttles up and its guidance steers, braking at full thrust
until the throttle comes back into its range.

The landing radar under the descent stage finds the ground, the real
ground of NASA's elevation maps. From ignition P63 shows N63, the speed,
altitude rate and altitude, as Luminary 099 did. As the radar's data
come good, the ALT and VEL lamps on the LGC's DSKY go out, and V16N68
shows ΔH, the radar's altitude less the LGC's: about −3,100 ft here,
with the range to the site and the time to go in braking. The crew keys
V57, and the radar
pulls the LGC's altitude and velocity in. Without V57 the LGC flies
Eagle into the ground a kilometre short of where it thinks it is. P64
flies the approach from high gate, about 2 km up and 8 km out. The LPD
angle in N64 tells the commander where on the window's scale to look for
the landing point, and each click of the hand controller moves it: 0.5°
fore or aft, 2° left or right. P65 lands automatically. At the first
click of the ROD switch, P66 hands the attitude to the crew while the
throttle holds the descent rate, 1 ft/s per click. CONTACT LIGHT comes
on when a probe touches, and at touchdown P68 shuts the engine down.

**Apollo 11's program alarms.** The LGC's Executive runs the descent's
jobs on the time its interrupts leave (`src/systems/lgc_executive.gd`).
A job holds one of eight core sets while it waits or runs, and one of
five VAC areas if it uses the interpreter. At the descent's peak the
jobs take about 90 % of the computer, as the mission report has it.
Eagle's crew left the rendezvous radar's mode switch (RNDZ RADAR, on
panel 3 and the HUD) at AUTO TRACK and then SLEW, not LGC. That ran the
radar's resolvers on an 800 Hz supply out of phase with the LGC's, and
their CDUs slewed, sending the LGC counter pulses that took about 13 %
of its time. On top of that, the crew's V16N68 in P63, once the radar's
data come good, or P64's landing point designator in AUTO, is more than
the LGC has. Jobs pile up. When no core set is left for one, the
Executive alarms 1202; when no VAC area is left, 1201. Either way it
restarts:
- PROG lights, V05N09 shows the codes (the first, the second and the
  last), and RSET clears them;
- whatever the crew had keyed is gone, and the program's display is
  back;
- the guidance carries on at the Servicer's next cycle.

Houston calls GO half a minute after the first alarm and within seconds
after the rest. With the switch at LGC no alarm comes. Apollo 12's
Luminary 1B and later zeroed the CDUs, so their switch doesn't matter.

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
P32 targets CSI at the first apolune: the horizontal burn that, with CDH
half a revolution on, has Columbia 26.6° above Eagle's horizon at TPI's
time. P33 targets CDH, onto an orbit a constant 15 nmi below Columbia's.
P34 finds when Columbia comes up to 26.6°, and the transfer that meets
it after it has flown 130° of its orbit. P35 corrects the course 15 and
30 minutes after TPI, and P41 flies each burn on the RCS: after its
maneuver to the burn attitude (PRO at V50N18), or where Eagle is (ENTER
at V50N18), the residuals of V16N85 nulled along each body axis, as
Apollo 11's crew burned theirs. From a mile out the commander brakes on
the TTCA, holding the closing rate to the range gates, and stops about
40 m from Columbia. Collins then flies the probe into the drogue, as he
did.

**P20 and the rendezvous radar.** The radar has the flight's errors, and
P20 is Luminary 099's: its marks take the error out of where the LGC has
Columbia relative to Eagle. After the P52, start it as Apollo 11's crew
did (the G mission's procedures):
- RNDZ RADAR to LGC and LGC MODE to AUTO. `V95E`: no state vector update
  yet. `V67E`, and at V06N99 load the filter's starting errors, per axis,
  `V25N99E+10000E+00100E+00015E` (10,000 ft, 10 ft/s and 15 mrad), PRO.
- `V37E20E`. P20 turns Eagle's +Z axis, which the radar looks along, onto
  Columbia (PRO at V50N18), and points the radar where the state vectors
  put Columbia. Once it has locked on and its range search is done, about
  15 s, V50N72 shows its angles: PRO.
- `V80E`: the marks update Eagle's state vector (`V81E`: Columbia's).

About once a minute P20 marks: the radar's range, range rate, shaft and
trunnion angles, weighed in by Luminary's filter, which also learns the
radar's boresight biases. A mark that would move the state vector more
than 2,000 ft or 2 ft/s shows V06N49, the change (nmi, ft/s) and which
measurement: PRO takes it, V32 drops it and marks again, V34 ends P20.
Between burns P20 keeps +Z on Columbia while LGC MODE is in AUTO,
rolled about the line of sight, where the least turn would light GIMBAL
LOCK, to keep the middle gimbal within 60°.
- `V67E` shows the filter's own error (N99) and loads it anew; `V93E`
  starts it again from those loads at the next mark.
- P32 to P35 let the marks in from their start to their final
  computation; V16N45 counts them. `V32E` at N45 computes the burn again,
  and PRO there is the final computation: 12 minutes before CSI, CDH and
  TPI, as Apollo 11's crew had it, and 5 minutes before each midcourse
  correction, P35 being selected right after the burn before it.
- `V56E` ends P20. Inside 18,000 ft the crew leave the radar in AUTO
  TRACK for its range and range rate.

To lock on by hand (R23), with RNDZ RADAR at SLEW, `V37E20E` shows
V50N25 00201: ENTER, for 00205. Slew the antenna onto Columbia on the
SLEW switch (HI 7°/s, LO 1.33°/s) until SIGNAL STRENGTH peaks, go to AUTO
TRACK, and once NO TRACK is out, to LGC; PRO when NO TRACK is out again.

**The AGS.** Eagle's abort guidance section runs FP6, Apollo 11's and
12's flight program: it navigates on its own accelerometers every two
seconds and works out its own guidance, and the crew talk to it through
the DEDA. AGS STATUS on panel 6 (AGS on the HUD) powers it, and **G**
opens the HUD's DEDA; while it's open, the digits, + and −, Enter (ENTR)
and Backspace (CLR) key into it. On the DEDA, CLR and an address's three
octal digits, then READOUT, show the word there, twice a second, until
HOLD or CLR; the address, a sign, five digits and ENTR enter one. A key
out of order lights OPR ERR until CLR. The FP6 operating manual lists
the words (11176-6033-T000). After the P57 on the surface the surface
checklist brings it up:
- 413+10000 (the surface flag), and 400+30000: the AGS aligns to the
  platform through its gimbal angles, for two seconds.
- `V47E`, R47, the AGS initialization. At V06N16 key 377+00000 on the
  DEDA and its ENTR with `V32E`, zeroing the AGS's clock with the LGC's.
  PRO puts Eagle's and Columbia's state vectors on the AGS's downlist for
  20 s, where 414+10000 takes them; PRO at V50N16. V34 ends R47 and takes
  them off the downlist, as a new V47 does.

Before each rendezvous burn V47 and 414+10000 update it again (PRO at
V06N16 keeps its clock), and its guidance routine (410) gives its own
solution:
- CSI (+10000): CSI's time in 373 and TPI's in 275, in AGS minutes to
  the tenth; 605 the cotangent of TPI's line of sight (+00777, 26.6°);
  416+10000 for CDH half an orbit on. 450 is the ΔV, 402 the ΔH.
- CDH (+20000): its time in 373. 450 and 452 are the ΔV along and up.
- TPI: search (+30000), 310 the time to go and 303 the line of sight;
  execute (+40000), its time in 373, and 267 the ΔV.
- External ΔV (+50000), to fly one of these.

With GUID CONT at AGS the AGS flies Eagle: 400+10000 steers to its
guidance, 400+00000 holds the attitude. For an abort from the surface on
it, select orbit insertion (410+00000) and guidance steering, GUID CONT to
AGS and LGC MODE to AUTO, and at the liftoff ENG ARM to ASC and ABORT
STAGE: the AGS lights the ascent engine, holds the attitude 2.5 s as the
stages part, rises vertically to 50 ft/s, steers for 60,000 ft and 19.5
ft/s up above the site's radius, and cuts the engine off.

**Mission Control's timeline.** From undocking to the entry, Mission
Control keeps Apollo 11's timeline (mission.json "lunar_timeline"):
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
  After LM JETT, the TEI PAD comes at 134:01, for Apollo 11's TEI at
  135:23:41, solved for its return: entry interface at 195:03:06, the
  return's inclination and the corridor's middle.
- **The entry PAD.** At 191:43:57 the entry PAD comes up with the state
  vector and Apollo 11's final target, 13.32° N 169.17° W, some 1,500
  nmi from entry interface.

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
- The LGC's DSKY, which the keys type into, and on G the AGS's DEDA.
- Eagle's switches: LGC MODE, ENG ARM (ASC or DES), ABORT and ABORT
  STAGE, ENG START and STOP, RCS SYS A and B, MASTER ALARM, ROD UP and
  DOWN for P66, and the rendezvous radar's mode, RNDZ RADAR (LGC, AUTO
  TRACK or SLEW), its SLEW RATE and the SLEW buttons.
- Its flight data: its height over the ground below it, its vertical
  speed and its speed over the turning surface, its orbit, its mass and
  rates, the landing radar's ΔH, the rendezvous radar's range and range
  rate (or NO TRACK) and SIGNAL STRENGTH, and the ALT and VEL lamps and
  CONTACT LIGHT.
- Its engines, RCS and LGC, its caution and warning lights, and Mission
  Control's LM PADs: DOI, PDI, ASCENT and CSI.
- The FDAI, on Eagle's attitude and rates and its LGC's errors.

The hand controllers fly its ACA and TTCA. The view is out of its
forward windows, or a chase view above 40 km, and near the Moon the
ground below Eagle is drawn from the same height maps its gear lands on.

**Eagle's cabin.** C's third view, and the only view in a headset, puts
you standing at the commander's station in Eagle's cabin
(`src/cabin/lm_cabin.gd`), at its window. Panels 1 to 6 carry every
switch of Eagle's HUD and its displays (`data/cockpit/lm_controls.csv`):
- Panel 1, to your right: the mission timer, the rendezvous radar's range
  and range rate, the descent engine's thrust, the FDAI, LUNAR CONTACT,
  ENG ARM, ABORT and ABORT STAGE, a MASTER ALARM, and the LGC, ISS, DES
  QTY and DES REG lights. ENG ARM is lever-locked: the first push pulls
  the lever out, the second moves it.
- Panel 2, the LM pilot's: its own FDAI, LUNAR CONTACT and MASTER ALARM,
  RCS SYS A and B, and the RCS A and B REG lights.
- Panel 3, between you: LGC MODE and RNDZ RADAR, the rendezvous radar's
  mode, with its SLEW RATE, its SLEW switch (UP and DOWN, LEFT and RIGHT,
  spring-loaded), the NO TRACK light and SIGNAL STRENGTH.
- Panel 4, below it: the LGC's DSKY, with its ALT and VEL lamps.
- Panel 5, by your left hand: ENGINE STOP and START and DES RATE, the
  rate of descent switch. Scroll it up for +1 FPS and down for −1 FPS.
- Panel 6, by the LM pilot's right hand: the AGS's DEDA and AGS STATUS.
  SEAT on the wrist menu takes you to the LM pilot's station.

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

### The audio director

The cabin's sound ([docs/ROADMAP.md](docs/ROADMAP.md), slice 6a) is
gemini-capsule's audio director, taken at commit
[`e0a5bd5`](https://github.com/scomofo/gemini-capsule/tree/e0a5bd58f2d84512de1315f29c7534d438da26bb).
The caution and warning system that sounds the master alarm
(`src/systems/caution_warning.gd`) and the render tool
(`tools/render_voices.gd`) are new.

| Gemini capsule | Apollo CSM | Changes |
|---|---|---|
| [`src/presentation/audio_director.gd`][a-director] | same path | Apollo's voices, from Apollo's channels. The one-shots are the switches (each control's type from the cockpit layouts, where Gemini guessed from the channel's name), DSKY keys, jets starting, the flight's pyros and latches, the parachutes' mortars, touchdown and splashdown. The continuous voices are the Saturn V's stages, the S-IVB, the SPS, Eagle's engines, the jets firing, the air, the fans, breathing and the master alarm's tone. Each is heard in its own vehicle's cabin, or in both while they're docked. Each voice is rendered once, on a worker thread, and the continuous ones loop, where Gemini synthesised its layers every frame and its one-shots at each play. They play through a limited bus, and a checkpoint's load makes no sound. Gemini's registry of recorded samples, its archive recordings, CAPCOM's quindar tones and its retro-rockets stay behind |
| [`tests/unit/test_presentation.gd`][a-tests] (its audio cases) | `tests/unit/test_audio_director.gd` | Rewritten for Apollo's voices, with the renders checked against their recipes |

[a-director]: https://github.com/scomofo/gemini-capsule/blob/e0a5bd58f2d84512de1315f29c7534d438da26bb/src/presentation/audio_director.gd
[a-tests]: https://github.com/scomofo/gemini-capsule/blob/e0a5bd58f2d84512de1315f29c7534d438da26bb/tests/unit/test_presentation.gd

## Fidelity

These parts are modelled from published figures (rounded; see
`data/spacecraft.json`):

- SPS (20,500 lbf, Isp 314 s)
- SM RCS (100 lbf jets)
- LM descent engine (10,125 lbf, throttleable from 10 % to 60 %, Isp
  311 s), ascent engine (3,500 lbf) and RCS (100 lbf jets in two systems)
- The rendezvous radar's range (400 nmi), and the TPI elevation and
  transfer angle (26.6° and 130°)
- The Saturn V as AS-506 flew it, from its flight evaluation report:
  - its masses at liftoff and at each stage's start;
  - the S-IC's five F-1s, 6,719 kN each at sea level and 7,986 kN in
    vacuum, with Isp from 264.5 s to 302 s;
  - the S-II's five J-2s, 5,142 kN, and 3,059 kN on four at the low
    mixture ratio;
  - the S-IVB's J-2 in its first burn, 901 kN;
  - the IU's event times, its pitch program (SA-504's) and its flight
    azimuth, 72.058°;
  - the drag from the flight manual's axial force coefficient.
- The J-2 in TLI, the S-IVB's second burn (894 kN, Isp 428.7 s, 74,452 kg
  of propellant), and the vehicle's 134,051 kg at its ignition
- CSM, LM and S-IVB masses (the LM's split between its stages is
  estimated)
- CM hypersonic L/D 0.3
- Parachute deployment altitudes

A flown Apollo 11 profile in the simulator reproduces these values:

| Quantity | Simulator | Apollo 11 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:06.8; 32.7 kPa at 1:18.2 | 1:06.3; 35.2 kPa at 1:23.0 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.2, 2:41.7, at 66.0 km and 2,738 m/s | 2:15.2, 2:41.6, at 66.1 km and 2,764 m/s |
| Launch: the S-II's cutoff | 9:08.2, at 6,916 m/s | 9:08.2, at 6,910 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:41.3; 11:51.1 at 7,793.1 m/s | 11:39.3; 11:49.3 at 7,793.1 m/s |
| Parking orbit | 99.9 × 99.8 nmi, 32.521° | 100.4 × 98.9 nmi, 32.521° |
| TLI | GET 2:43:58, 3,186 m/s in 334.8 s, the plane turned 1.20°, C3 −1,376,351 m²/s² | 2:44:16, 3,182 m/s in 346.9 s, 1.20°, C3 −1,391,607 m²/s² |
| The free return after TLI | 896.5 nmi past the Moon at 75:05:23, 1.9° N 174.4° W; an Earth capture | 896.3 nmi at 75:05:21, 0.1° S 174.1° W; an Earth capture |
| Translunar midcourse correction | 30.5 ft/s at 4:04 | 19.7 ft/s at 4:40 (the evasive maneuver) and 20.9 ft/s at 26:45 |
| Translunar coast | 73.0 h | 73.0 h |
| LOI-1 | GET 75:50:32, 880 m/s, 6.1 min, 58 × 170 nmi | 75:49:50, 889 m/s, 5.96 min, 60 × 170 nmi |
| The orbit after LOI-2, above the landing site, flown through the Moon's field | 65.4 × 53.5 nmi at 80:11:54, 61.8 × 56.9 nmi at 126 h | 65.7 × 53.8 nmi, 62.4 × 56.6 nmi |
| TEI | GET 135:23:41, 3,309 ft/s | 135:23:42, 3,284 ft/s |
| Eagle's P52 after undocking | on Acrux and Antares, torqued at 101:13:25: N05 0.011°, N93 −0.287, +0.290, −0.089° | torqued at 101:20:18: N05 0.03°, N93 −0.292, +0.289, −0.094° |
| DOI | GET 101:34:56, 74.3 ft/s, 30 s | 101:36:14, ~76 ft/s, ~30 s |
| Powered descent | 12 min 7 s, touchdown at 102:45:22, 86 m from the target (the LGC's error across the ground, which the radar can't see) | 12 min 35 s, touchdown at 102:45:40, about 6 km past the target |
| The Sun at touchdown | 10.7° up | 10.8° up |
| Eagle's P57s on the surface | 103:47 on Rigel and Navi, which R59 finds in the left-rear and right-rear detents: N05 0.001°; 122:17 on gravity and Capella, in the right rear: N93 −0.692, +0.704, −0.620° | 103:47 on the same stars through the same detents: N05 0.09°; 122:17 on Capella through the right rear: N93 −0.699, +0.695, −0.628° |
| Ascent, liftoff to cutoff | GET 124:22:23, 7 min 8 s, then 59,641 ft and 29.8 ft/s up (the LGC's 60,034 ft and 32.0 ft/s, its platform 0.050° off after the P57 at 123:49), 9.1 × 45.3 nmi | 124:22:00, 7 min 17 s, then 60,666 ft and 32.8 ft/s up, 9.5 × 47.3 nmi |
| The AGS's orbit after the ascent (its DEDA's 315 and 403) | 44.6 × 9.1 nmi, the truth's 45.2 × 9.1 | 46.6 × 9.5 nmi, the PGNS's 47.3 × 9.5 |
| CSI | 50.9 ft/s, 50 min 59 s after insertion (the LGC's solution 50.1, the PAD's 50.0) | 51.5 ft/s, 50 min 18 s after insertion |
| The AGS's CSI, from the LGC's state vectors | 50.0 ft/s, ΔH 16.4 nmi (the LGC's 50.1) | 51.3 ft/s, ΔH 15.5 nmi at 124:39 (the PGNS's 51.5) |
| CDH, with Columbia's orbit out of round | 8.6 ft/s | 19.9 ft/s |
| TPI | 28.3 ft/s, 2 h 33 min 24 s after insertion, 71 s before the plan's time | ~25 ft/s, 2 h 34 min 35 s after insertion, 6 min 39 s after the plan's |
| Midcourse corrections | 3.0 and 0.9 ft/s | 0.98 and 1.30 ft/s |
| Braking, then station-keeping | 11 min 2 s, station-keeping 46 min after TPI | 15 min 8 s, station-keeping 48 min after TPI |
| Docking | GET 127:53:32, 51 min after TPI | 128:03:00, 59 min after TPI |
| Entry interface | 195:03:05, 36,194 ft/s, 6.53° down, 3.23° S 171.88° E | 195:03:05.7, 36,194 ft/s, 6.48° down, 3.19° S 171.96° E |
| Entry: 0.05 g, and the two peak loads | 195:03:34; 6.5 and 6.1 g | about 195:03:34; 6.5 and 6.0 g |
| Drogues | 195:12:39 | 195:12:07 |
| Splashdown | 195:18:20, 13.33° N 169.18° W, 0.9 nmi from the target, at 9.8 m/s | 195:18:35, 13.30° N 169.15° W, 1.7 nmi from it by the CMC's reckoning |

Apollo 8 flown from its data alone, from the pad into its parking orbit
(`tests/scenarios/test_apollo_8_launch.gd`) and from its parking orbit
to the splashdown (`tests/scenarios/test_apollo_8.gd`), each holding its
rows within set limits of the flight's figures, against the Apollo 8
Mission Report (MSC-PA-R-69-1), the AS-503 flight evaluation report
(MPR-SAT-FE-69-1) and the Apollo Flight Journal:

| Quantity | Simulator | Apollo 8 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:01.3; 33.8 kPa at 1:11.9 | 1:01.5; 37.2 kPa at 1:18.9 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:05.96 at 1,878 m/s and 24.47° up, 2:33.78 at 2,693 m/s and 20.13° | 2:05.93 at 1,894 m/s and 24.53°, 2:33.82 at 2,713 m/s and 20.70° |
| Launch: the S-II's cutoff, on all five engines | 8:43.98, at 6,781 m/s | 8:44.04, at 6,821 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:32.1; 11:41.9 at 7,793.0 m/s | 11:25.0; 11:35.0 at 7,792.8 m/s |
| Parking orbit, and the S-IVB's propellant for TLI | 100.0 × 100.0 nmi, 32.508°; 71,271 kg | 100.0 × 99.6 nmi, 32.509°; 72,727 kg |
| TLI, from the pad | GET 2:50:15, 3,048 m/s in 313.6 s, C3 −1,422,250 m²/s² | 2:50:37, 3,040 m/s in 318.4 s, C3 −1,478,917 m²/s² |
| TLI | GET 2:50:11, 3,046 m/s in 317.2 s, C3 −1,420,280 m²/s² | 2:50:37, 3,040 m/s in 318.4 s, C3 −1,478,917 m²/s² |
| The separation maneuvers, and the pericynthion after them | 1.1 and 7.7 ft/s radially up; 464.2 nmi at 69:01:20 | 1.1 and 7.7 ft/s; 458.1 nmi at 68:57:40 |
| MCC-1, and the pericynthion after it | 25.1 ft/s at 10:59:58, N81 +16.5, +1.6, +18.9; 68.1 nmi at 69:10:30 | 24.8 ft/s at 10:59:58, N81 +13.6, −4.5, +20.2 (flown 20.4); 66.3 nmi at 69:10:40 |
| MCC-2, and the pericynthion after it | 2.5 ft/s; 66.0 nmi at 69:10:38 | 2.0 ft/s (flown 1.4); 65.8 nmi at 69:10:39 |
| LOI-1 | 69:08:19, N81 −2,988.9, +247.7, +118.7; 3,001 ft/s in 250.9 s, 1.1° down at cutoff; 169.4 × 59.9 nmi, 12.28° to the lunar equator | 69:08:20, N81 −2,984.0, +239.0, +105.3; 2,997 ft/s in 246.9 s, 0.79° down; 168.5 × 60.0 nmi, 12.29° |
| LOI-2, two revolutions on | 73:37:13, 134.0 ft/s; 62.6 × 59.6 nmi | 73:35:07, 134.8 ft/s; 60.7 × 59.7 nmi |
| The lunar orbit before TEI, flown through the Moon's field | 64.1 × 57.6 nmi after 10.2 revolutions | 63.6 × 58.6 nmi after 10 |
| TEI | 89:19:15, N81 +3,521.9, −190.1, +98.2; 3,528 ft/s in 211.4 s | 89:19:16, N81 +3,518.6, −151.2, −52.0; 3,519 ft/s in 203.7 s |
| Transearth midcourse corrections | MCC-5 2.2 ft/s, MCC-6 none, MCC-7 2.7 ft/s | MCC-5 4.8 ft/s, MCC-6 and MCC-7 scrubbed |
| Entry interface | 146:46:58, 36,216 ft/s, 6.57° down, 20.80° N 176.54° E | 146:46:13, 36,221 ft/s, 6.50° down, 20.72° N 176.89° E |
| The entry | P61 to P65, then P67; 6.89 g at the peak | P61 to P64, P67, no P65; 6.84 g |
| Splashdown | 147:01:36, 8.16° N 165.02° W, 2.1 nmi from the target | 147:00:42, 8.10° N 165.01° W, 2.3 nmi from it |

The report's own figures don't all agree, and the table takes these:
- Its entry interface's longitude, 179.89° W (Table 5-V), is 3° from the
  CMC's own state then (Table 6.9-III), 176.89° E, which the simulator's
  return meets; its time, speed and angle agree.
- Its pericynthions after TLI and the first separation (Table 5-III) can't
  both come from TLI and a 1.1 ft/s burn: the S-IVB's venting moved the
  spacecraft before it separated. The RTCC aims TLI at the flight's
  pericynthion after the separations instead (below).

Apollo 10 flown from its data alone, from the pad into its parking orbit
(`tests/scenarios/test_apollo_10_launch.gd`) and from its parking orbit
to the splashdown (`tests/scenarios/test_apollo_10.gd`), each holding its
rows within set limits of the flight's figures, against the Apollo 10
Mission Report (MSC-00126), the AS-505 flight evaluation report
(MPR-SAT-FE-69-7), its postflight trajectory (Boeing D5-15560-5) and the
Apollo Flight Journal:

| Quantity | Simulator | Apollo 10 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:07.0; 32.9 kPa at 1:18.6 | 1:06.8; 33.2 kPa at 1:22.6 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.16 at 1,973 m/s and 23.36° up, 2:41.58 at 2,727 m/s and 19.71° | 2:15.16 at 1,973 m/s and 22.81°, 2:41.63 at 2,752 m/s and 18.95° |
| Launch: the S-II's centre engine's cutoff, and its own | 7:40.56 at 5,661 m/s; 9:12.60 at 6,883 m/s | 7:40.61 at 5,678 m/s; 9:12.64 at 6,898 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:48.2; 11:58.0 at 7,793.0 m/s | 11:43.8; 11:53.8 at 7,793.1 m/s |
| Parking orbit, and the S-IVB's propellant for TLI | 100.0 × 100.0 nmi, 32.546°; 72,850 kg | 100.3 × 99.7 nmi, 32.546°; 73,462 kg |
| TLI from the pad, and the pericynthion after it | GET 2:33:16, 3,050 m/s in 339.8 s, C3 −1,299,414 m²/s²; 908.2 nmi at 76:10:18 | 2:33:28, 3,056 m/s in 342.9 s, C3 −1,308,471 m²/s²; 907.7 nmi at 76:10:18 |
| TLI, and the pericynthion after it | GET 2:33:13, 3,050 m/s in 341.4 s, C3 −1,298,719 m²/s²; 907.9 nmi at 76:10:17 | 2:33:28, 3,056 m/s in 342.9 s, C3 −1,308,471 m²/s²; 907.7 nmi at 76:10:18 |
| The evasive maneuver, and the pericynthion after it | 19.7 ft/s on the SPS; 259.3 nmi at 76:41:52 | 18.8 ft/s (the PAD's 19.7); 286.1 nmi at 76:40:01 |
| MCC-1, and the pericynthion after it | 52.1 ft/s at 26:32:56, N81 −40.8, +16.0, −28.2; 55.5 nmi at 76:00:17 | 48.7 ft/s at 26:32:56, N81 −39.8, +10.9, −25.8 (flown 49.2); 60.9 nmi at 76:00:15 |
| MCC-4, and the pericynthion after it | 3.1 ft/s; 60.0 nmi at 76:00:15 | 2.8 ft/s, not flown; 60.7 nmi |
| LOI-1 | 75:55:53, N81 −2,947.4, −837.8, −292.9; 3,078 ft/s in 379.9 s; 170.2 × 60.6 nmi, 1.44° to the lunar equator | 75:55:53, N81 −2,913.8, −561.2, −299.7; 2,982 ft/s in 356.1 s; 170.0 × 60.2 nmi, 1.2° planned |
| LOI-2 | 80:22:30, 138.4 ft/s; 60.4 × 60.0 nmi | 80:25:08, 139.0 ft/s; 61.0 × 59.2 nmi |
| The CSM's separation maneuver | 2.5 ft/s radially down; Charlie Brown in 62.3 × 57.7 nmi | 2.5 ft/s; 62.9 × 57.7 nmi |
| Snoopy's first P52 | 99:18:21 on Antares and Acrux: N05 0.006°, N93 −0.666, −0.196, −0.061° | 99:20: N05 0.09°, N93 −0.668, −0.195, −0.055° |
| DOI | 99:47:09, 68.7 ft/s in 28 s; 61.6 × 9.4 nmi | 99:46:01, 71.3 ft/s in 27.4 s; 60.9 × 8.5 nmi |
| The low pass | 46,925 ft over the terrain at the lowest; 55,744 ft up over the site, 2.5 nmi south of it | 47,400 ft by the landing radar; 56,783 ft, about 5 miles south |
| The phasing burn | 100:57:46, 176.8 ft/s in 41 s, 10 % at 10 s and full at 35 s; 191.7 × 11.5 nmi | 100:58:26, 176.0 ft/s in 40.0 s, 13.1 % and full; 190.1 × 12.1 nmi |
| Staging and the insertion | the ascent stage 8,383 lb; 102:54:22, 220.9 ft/s in 18 s; 46.9 × 11.1 nmi | 8,273 lb; 102:55:02, 220.9 ft/s in 15.5 s; 46.5 × 11.0 nmi |
| CSI | 103:43:24, 42.7 ft/s; 46.3 × 42.1 nmi | 103:45:55, 45.3 ft/s; 48.7 × 40.7 nmi |
| CDH | 104:41:18, 5.8 ft/s, 16.2 nmi below Charlie Brown | 104:43:53, 3.0 ft/s, 15.0 nmi |
| TPI, and the midcourse corrections | 105:22:11, 26.3 ft/s; 2.5 ft/s | 105:22:56, 24.1 ft/s; two small ones |
| Docking | 106:13:36, the LM's RCS having given 120 ft/s from CSI | 106:22:02 |
| TEI | 137:36:28, N81 +3,617.0, +137.2, −450.3; 3,648 ft/s in 174.0 s | 137:36:29, N81 +3,625.2, +40.0, +188.0; 3,630 ft/s in 164.8 s |
| Transearth midcourse corrections | MCC-6 12.9 ft/s, MCC-7 4.4 ft/s | MCC-6 not flown, MCC-7 2.2 ft/s |
| Entry interface | 191:48:55, 36,307 ft/s, 6.64° down, 23.56° S 174.09° E | 191:48:55, 36,314 ft/s, 6.54° down, 23.60° S 174.39° E |
| The entry | P61 to P65, then P67; 7.13 g at the peak | P61 to P67; 6.78 g |
| Splashdown | 192:03:35, 15.07° S 164.70° W, 1.8 nmi from the target | 192:03:23, 15.06° S 164.65° W, 1.3 nmi from it |

Here too the report's figures don't all agree, and the table takes these:
- Its TEI gave 3,680.3 ft/s by Table 6-V and 3,630.2 ft/s by the SPS's
  own velocity gained (Table 7.6-V), which the TEI PAD's N81 matches: the
  table takes Table 7.6-V's.
- Its masses and the APS's thrust give the insertion's 220.9 ft/s in
  17.6 s, where it burned 15.5 s (Table 6-IV); the simulator, flying
  them, takes 18 s.
- The phasing burn flew 176.0 ft/s against its PAD's 176.9: the test
  holds the simulator to the PAD, which P40 flies.

Apollo 12 flown from its data alone, from the pad through its lightning
into its parking orbit (`tests/scenarios/test_apollo_12_launch.gd`) and
from its parking orbit to the splashdown
(`tests/scenarios/test_apollo_12.gd`), each holding its rows within set
limits of the flight's figures, against the Apollo 12 Mission Report
(MSC-01855), the AS-507 flight evaluation report (MPR-SAT-FE-70-1), the
Mission Director's summary report (M-932-69-12), the Apollo Flight
Journal and the Apollo Lunar Surface Journal:

| Quantity | Simulator | Apollo 12 |
|---|---|---|
| Launch: the first strike, 0:36.5 | FC 1 to 3, FC BUS DISCONNECT, MN BUS A and B UNDERVOLT; the mains at 25.5 V on the batteries; the telemetry gone | the same lights, with the AC buses'; 24 V; the SCE dropped out |
| Launch: the second strike, 0:52 | ISS and NO ATT, the platform caged | ISS at about 50 s, the platform tumbling |
| Launch: SCE to AUX, and the fuel cells' reset | Houston's calls at 1:36.0 and 2:19.0; the telemetry back on AUX at 1:50; fuel cells 1 and 2 on line at 2:22 and 3 at 2:50 | the calls at 1:36 and 2:19; SCE to AUX at 1:50 on the onboard tape (working again at 97.5 s, the Mission Director's report); 1 and 2 by 142.5 s, 3 at 170.5 s |
| Launch: Mach 1, maximum dynamic pressure | 1:06.5; 32.4 kPa at 1:17.4 | 1:06.1; 32.7 kPa at 1:21.1 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.24 at 1,972 m/s and 23.52° up, 2:41.76 at 2,728 m/s and 19.83° | 2:15.24 at 1,980 m/s and 23.94°, 2:41.74 at 2,751 m/s and 20.51° |
| Launch: the S-II's centre engine's cutoff, and its own | 7:40.78 at 5,681 m/s; 9:12.34 at 6,912 m/s | 7:40.75 at 5,723 m/s; 9:12.34 at 6,959 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:42.9; 11:52.7 at 7,793.3 m/s | 11:33.9; 11:43.9 at 7,792.5 m/s |
| Parking orbit, and the S-IVB's propellant for TLI | 99.7 × 99.7 nmi, 32.540°; 72,127 kg | 100.1 × 97.8 nmi, 32.540°; 73,775 kg to depletion |
| P51 in the parking orbit | 0:45:09, Diphda and Sirius, 0.001° from the catalog's angle | the first night, Rigel and Sirius, 0.01° |
| TLI from the pad, and the pericynthion after it | GET 2:47:50 for 339.4 s, C3 −1,820,312 m²/s²; 279.5 nmi at 83:44:04 | 2:47:23 for 341.3 s, C3 −1,834,425 m²/s²; 280.2 nmi at 83:44:04 |
| TLI, and the pericynthion after it | GET 2:47:45, 10,559 ft/s from the J-2 in 343.6 s, C3 −1,821,128 m²/s²; 279.5 nmi at 83:44:04 | 2:47:23, 10,515 ft/s in 341.3 s, C3 −1,834,425 m²/s²; 280.2 nmi at 83:44:04 |
| MCC-2, off the free return | 57.8 ft/s at 30:52:43, N81 −56.0, −8.8, −11.0; 69.2 nmi at 83:28:37 | 61.7 ft/s at 30:52:44, N81 −60.1, −12.6, +5.6 (flown 61.8); 65.1 nmi at 83:28:39 |
| MCC-4 | 2.4 ft/s; 67.0 nmi at 83:28:42 | not needed |
| LOI-1 | 83:25:18, N81 −2,856.7, +796.6, +165.0; 2,970 ft/s in 379.6 s; 169.7 × 59.9 nmi, 13.5° to the lunar equator | 83:25:19, N81 −2,821.3, +603.6, +112.4; 2,889.5 ft/s in 352.3 s; 168.8 × 62.6 nmi, 14.6° |
| LOI-2 | 87:48:43, N81 −136.8, 0.0, −135.9, 192.9 ft/s; 66.2 × 53.8 nmi | 87:48:48, N81 −139.2, +0.1, −89.5, 165.2 ft/s; 66.1 × 54.3 nmi |
| The CSM's separation maneuver | 2.5 ft/s radially down; Yankee Clipper in 64.0 × 55.8 nmi | 2.4 ft/s (the PAD's 2.5); 63.5 × 56.3 nmi |
| Intrepid's first P52 | 108:46:07 on Capella and Rigel: N05 0.005°, N93 +0.013, −0.001, −0.066° | 108:48 on the same stars: N05 0.02°, N93 +0.018, −0.002, −0.069° |
| DOI | 109:20:11, 69.6 ft/s in 30 s; 60.7 × 9.0 nmi | 109:23:40, 72.4 ft/s in 29.0 s; 60.6 × 8.1 nmi |
| PDI, and the crossrange | 110:19:46; the site 4.3 nmi south of the orbit's plane, the lateral velocity up to 86 ft/s 228 s on | 110:20:38; about 5 miles south, up to 78 ft/s about 5 min on |
| Noun 69, and the landing radar | +4,300 ft 80 s after PDI; ΔH −1,033 ft at 35,563 ft | +4,200 ft 79 s after PDI; ΔH −918, −1,000 ft, the radar's altitude from 41,438 ft |
| P64 | 110:28:25 at 8,075 ft, aiming 455 ft from the Surveyor; 15 LPD clicks | 110:29:11 near 7,000 ft, aiming 416 ft from it |
| The landing | P66 at 110:30:35 at 390 ft; touchdown 110:31:53, 514 ft from Surveyor III, where Intrepid came down; 1,346 lb of the DPS's propellant left | P66 at 110:30:50 at 400 ft; 110:32:36, 535 ft from it; 1,175 lb |
| The first plane change | 119:45:06, N81 −9.2, +312.8, 0; 313.1 ft/s in 19.0 s; 62.4 × 57.1 nmi | 119:47:13, N81 −11.5, +349.6, 0; 349.9 ft/s in 18.2 s; 62.5 × 57.6 nmi |
| The P57 before the liftoff | 141:26:58, option 4, on gravity and Arcturus, which R59 finds in the right-rear detent: N05 0.02°, N93 +0.010, +0.106, −0.033° | 141:29 on Procyon through the left-front detent: N05 0.04°, N93 −0.023, +0.004, +0.015° |
| The ascent | liftoff 142:01:21, N76 5,532.7 and 37.0 ft/s, −0.28 nmi crossrange; 441 s on the APS; 45.3 × 8.7 nmi, 0.02° from Yankee Clipper's plane | 142:03:48 (planned 142:01:18), N76 5,535.0 and 37.0 ft/s, +0.2 nmi; 423.2 s; 46.3 × 8.8 nmi |
| The P52 after the insertion | 142:20:55 on Rigel and Capella: N05 0.002°, N93 −0.006, +0.023, +0.015° | 142:23 on the same stars: N05 0.01° |
| CSI | 142:58:34, 47.0 ft/s; 44.7 × 42.1 nmi | 143:01:51, 45.0 ft/s; 51.0 × 41.5 nmi |
| CDH | 143:56:29, 3.9 ft/s, 17.0 nmi below Yankee Clipper | 144:00:03, 13.8 ft/s |
| TPI, and the midcourse corrections | 144:33:56, 30.0 ft/s; 5.7 ft/s | 144:36:26, 29.0 ft/s |
| Docking | 145:24:39, the LM's RCS having given 129 ft/s from CSI | 145:36:20 |
| The second plane change | 159:04:44, 381.4 ft/s in 22.0 s; 63.0 × 56.8 nmi | 159:04:46, 381.8 ft/s in 19.2 s; 64.7 × 56.8 nmi |
| TEI | 172:22:44, N81 +3,029.6, +64.6, −0.1; 3,030 ft/s in 138.2 s; entry interface after it at 244:21:08 | 172:27:17, N81 +3,027.2, +302.1, −25.3; 3,042 ft/s in 130.3 s; 244:22:19 |
| Transearth midcourse corrections | MCC-5 3.9 ft/s, MCC-7 none | MCC-5 2.0 ft/s, MCC-7 2.4 ft/s |
| Entry interface | 244:18:36, 36,117 ft/s, 6.51° down, 13.57° S 174.39° E | 244:22:19, 36,116 ft/s, 6.48° down, 13.80° S 173.52° E |
| The entry | P61 to P64, then P67; 6.80 g at the peak | P61 to P67; 6.1 g on the PAD |
| Splashdown | 244:32:45, 15.84° S 165.17° W, 1.7 nmi from the target | 244:36:25, 15.78° S 165.15° W, within 2 miles of it |

The table takes these from the flight's figures:
- TLI's 10,515 ft/s is the J-2's (MSC-01855, Table 5-IV), which the
  simulator's row takes by the rocket equation on the propellant it
  burned, as Apollo 11's does.
- Noun 69 read 4,200 ft where the Doppler residuals after DOI showed
  4,400 (MSC-01855, section 4.2): the simulator's LGC is off by the 4,400,
  and the ground reads it with MSFN's spread.
- Where Intrepid came down is LROC's (Wagner et al., 2017), 157 m (515
  ft) northwest of the Surveyor where LROC has it; the mission report's
  535 ft is the 1969 survey's.
- The P57 before the liftoff was on Procyon through the left-front
  detent (Table 8.6-I). Procyon isn't in a detent's field from where the
  simulator's Intrepid sits, and the test takes the first star R59 finds.
  Intrepid's heading at rest isn't in the report, as Eagle's 13° yaw is
  in Apollo 11's debriefing: the simulator's keeps the heading it landed
  on.

Apollo 13 flown from its data alone, from the pad on four S-II engines
into its parking orbit and on through TLI
(`tests/scenarios/test_apollo_13_launch.gd`) and from five minutes before
the oxygen tank failed to the splashdown
(`tests/scenarios/test_apollo_13.gd`), each holding its rows within set
limits of the flight's figures, against the Apollo 13 Mission Report
(MSC-02680) and its guidance supplement, the AS-508 flight evaluation
report (MPR-SAT-FE-70-2), the Mission Operations Report and the Apollo
Flight Journal. The launch's pogo rows set the flight beside the same
launch flown without the pogo, as the report sets it beside its
prediction:

| Quantity | Simulator | Apollo 13 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:07.2; 32.7 kPa at 1:18.7 | 1:08.4; 31.2 kPa at 1:21.3 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.20 at 1,952 m/s and 23.16° up, 2:43.62 at 2,757 m/s and 19.24° | 2:15.18 at 1,929 m/s and 23.61°, 2:43.60 at 2,744 m/s and 19.48° |
| Launch: pogo shuts the S-II's centre engine down | 5:30.66 at 3,913 m/s and 4.84° up, LV ENG 5 on; the IU's guidance pitches up 7.6° | 5:30.65 at 3,920 m/s and 4.16°; about 7° |
| Launch: the IU's command to shift the mixture ratio, and the shift | 8:54.76 and 8:57.56; 33.0 s later than without the pogo | 8:54.7 and 8:57.5; 32.2 s later than predicted |
| Launch: the S-II's cutoff, and its burn | 9:52.64 at 6,913 m/s; 427.6 s, 33.0 s longer than without the pogo | 9:52.64 at 6,892 m/s; 427.64 s, 34.93 s longer than predicted |
| Launch: the S-IVB's cutoff and burn, and insertion | 12:28.80 after 151.9 s, 10.8 s longer than without the pogo; 12:38.80 at 7,792.9 m/s, 43.8 s later | 12:29.83 after 152.9 s, 9.3 s longer than predicted; 12:39.83 at 7,792.5 m/s, 44.07 s later |
| Parking orbit, and the S-IVB's propellant for TLI | 100.1 × 100.1 nmi, 32.525°; 73,331 kg | 100.3 × 99.3 nmi, 32.525°; 73,447 kg at its second ignition |
| TLI from the pad, and the pericynthion after it | GET 2:35:45 for 353.8 s, C3 −1,366,030 m²/s²; 250.8 nmi at 77:46:47 | 2:35:46.4 for 350.8 s, C3 −1,376,274 m²/s²; the parking-orbit start's aim, 250.2 nmi at 77:46:46 |
| The hybrid at the incident | pericynthion 60.0 nmi at 77:28:39 | 63 nmi at 77:28:39 (the PAD's 60) |
| The oxygen tank | tank 2 fails at 55:54:53; fuel cell 2 carries the CSM until 58:14:25 | 55:54:53; 58:15:11 |
| The docked coarse align | the CM's N20 355.58, 167.77, 351.88; the LM's V41N20 184.42, 347.77, 8.12 | 355.57, 167.78, 351.87; 302.43, 347.78, 8.13 |
| The CSM powered down | 58:40:11, 95 A-h in the entry batteries | 58:40, 99 A-h |
| MCC-2, back to a free return | 61:29:42, N81 −20.1, +3.5, −30.6; 36.8 ft/s in 31.0 s on the DPS; then 137.8 nmi at 77:21:55 | 61:29:43, N81 −21.3, +4.1, −31.2; 37.8 ft/s in 34.2 s; then 136 nmi at 77:20:57 |
| PC+2 | 79:27:38, N81 +815.1, −41.9, −221.3; 845.7 ft/s in 255.0 s on the DPS; 95,626 to 87,818 lb; the LM's middle and inner gimbals 329.7, 353.5 | 79:27:39, N81 +833.0, −50.9, −213.9; 860.5 ft/s in 263.8 s; 95,424 to 87,456 lb; 330.0, 355.0 |
| The return after PC+2 | no entry: vacuum perigee 84.9 nmi | no entry: 80.6 nmi |
| MCC-5, by hand on the AGS | the PAD's 7.4 ft/s; the engine on at 105:18:28 for 15.2 s at 10 %; the DEDA 7.1, trimmed to 7.4; the entry 6.44° down | 7.8 ft/s; 105:18:28, 14 s; 7.4, trimmed to 7.6; 6.52° |
| MCC-7, on the LM's jets | 137:39:48, 1.0 ft/s in 7.0 s; the entry 6.46° down | 137:39:52, 3.0 ft/s in 21.5 s; 6.26° |
| SM SEP | 138:01:44; the CM and LM 37,464 lb | 138:01:48; 37,110 lb |
| The CM's power-up | 120 A-h in the entry batteries; P52 on stars 7 and 44, 0.004° of star angle difference | 118 A-h; stars 36 and 40, 0.00 |
| Aquarius at LM JETT | 456 A-h left; 10,288 lb in the descent stage, 8,147 lb of it used; 258 lb of the jets' propellant used | 410 A-h; 10,091.6 lb, 8,342.9 used; 467 lb |
| LM JETT | 141:29:56; the CM pushed back 1.91 ft/s, 12,367.7 lb | 141:30:00; 1.88 ft/s, 12,367.6 lb |
| Entry interface | 142:41:45, 36,199 ft/s, 6.33° down | 142:40:46, 36,210.6 ft/s, 6.27° down |
| The entry | P61 to P64, then P67; 5.68 g at the peak | P61 to P67; 5.2 g on the PAD |
| Splashdown | 142:55:58, 21.67° S 165.37° W, 0.4 nmi from the target; 41 A-h left in the entry batteries | 142:54:41, 21.64° S 165.36° W, about a mile from it; 29 A-h |

The table takes these from the flight's figures:
- The launch: AS-508's F-1s give 8,000 kN each in vacuum, the stage's
  40.0 MN on five before the centre engine's cutoff in the report's
  Figure 5-3 [a plot reading]; its peak acceleration at the outboard
  cutoff, the other missions' measure, gives 7,836 kN, which left the
  S-IC 40 m/s short and the S-IVB burning 12 s long. The S-IC's vacuum
  Isp (306.6 s) and the S-II's flow at the high ratio (1,230.0 kg/s, 1 %
  under the report's with the pressurization's) are tuned for the flown
  cutoffs, and the IU's velocity criterion for the flown command
  [estimated]. The pitch-up is a plot reading of the report's Figure 9-4.
- The docked coarse align's outer gimbal: Aquarius's crew added their
  docking ring's roll calibration (the Apollo Flight Journal, 058:03);
  the simulator's LM docks at its nominal index, 118° round from
  Aquarius's. The inner and middle gimbals, which the index leaves alone,
  are the flight's.
- PC+2's platform error is the guidance supplement's: the docked
  alignment 0.351° off, which it found from the burn's 5.27 ft/s error,
  taken whole at the alignment. It leaves the return missing the
  atmosphere, as the flight's did.
- PC+2's PAD is the simulator's RTCC's, solved for the flown return's
  entry interface time and inclination from the simulator's trajectory:
  17 ft/s less than the flight's PAD.
- The simulator's MCC-5 leaves the entry 0.08° shallower than the
  flight's, and MCC-7 has less to do.

Apollo 14 flown from its data alone, from the pad into its parking orbit
and on through TLI (`tests/scenarios/test_apollo_14_launch.gd`), through
its transposition and docking (`tests/scenarios/test_apollo_14_docking.gd`),
from its parking orbit to the landing at Fra Mauro
(`tests/scenarios/test_apollo_14.gd`) and from the surface to the
splashdown (`tests/scenarios/test_apollo_14_return.gd`), each holding its
rows within set limits of the flight's figures, against the Apollo 14
Mission Report (MSC-04112), its trajectory reconstruction (MSC-04330),
the AS-509 flight evaluation report (MPR-SAT-FE-71-1), the Apollo Flight
Journal and the Apollo Lunar Surface Journal:

| Quantity | Simulator | Apollo 14 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:08.1; 33.0 kPa at 1:20.4 | 1:08.0; 31.4 kPa at 1:21.0 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.16 at 1,931 m/s and 22.65° up, 2:44.10 at 2,739 m/s and 18.65° | 2:15.14 at 1,915 m/s and 23.55°, 2:44.10 at 2,735 m/s and 19.58° |
| Launch: the S-II's centre and outboard engines' cutoffs | 7:43.08 at 5,651 m/s, 9:19.04 at 6,966 m/s | 7:43.09 at 5,655 m/s, 9:19.05 at 6,982 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:45.10, 11:54.90 at 7,793.0 m/s | 11:40.56, 11:50.56 at 7,790.6 m/s |
| Parking orbit, and the S-IVB's propellant for TLI | 100.1 × 99.9 nmi, 31.120°; 73,766 kg | 100.1 × 98.9 nmi, 31.120°; 74,453 kg at its second ignition |
| TLI, and the pericynthion after it | GET 2:28:32, 10,391 ft/s in 353.2 s, C3 −1,668,228 m²/s²; 1,979.3 nmi at 82:15:18 | 2:28:32, 10,366.5 ft/s in 350.8 s, C3 −1,678,092 m²/s²; 1,979 nmi at 82:15:19 |
| CSM/LV SEP and the transposition | the crew's at 3:02:29; turned about, the drogue 32.7 ft ahead, 0.5° out of line, at 3:06:28 | 03:02:29.4 |
| The attempts without capture | 3:13:53 at 0.10 ft/s; 3:23:42 at 0.45 ft/s, +X 6.2 s; 4:32:29 at 0.25 ft/s: the capture latches didn't engage | 3:13:53.7 at 0.1 ft/s, and seven more contacts to 4:32:29.3: 3:23:41.7 at 0.4 to 0.5 ft/s, +X 6.2 s; 4:32:29.3 at 0.25 ft/s |
| The sixth attempt | contact 4:56:45 at 0.20 ft/s, +X held; PROBE RETRACT 6.9 s on; the ring latches 11.8 s after the contact, hard dock 4:56:57 | 4:56:44.9 at 0.2 ft/s, +X 14.3 s; the retraction 6.9 s on; the first ring latch 11.8 s after the contact; hard dock 04:56:56 |
| MCC-2, off the free return | 67.4 ft/s at 30:36:07, N81 −23.6, +7.7, +62.7 | 71.4 ft/s at 30:36:07, N81 −25.9, +4.4, +66.4 |
| MCC-4, and the pericynthion after it | 2.2 ft/s; 59.1 nmi at 82:00:30 | 3.8 ft/s; 60.7 nmi at 82:00:33 |
| LOI | 81:57:20, N81 −2,816.1, −1,190.2, +87.9; 3,059 ft/s in 393.0 s; 169.7 × 58.4 nmi, 13.8° to the lunar equator | 81:56:40, N81 −2,804.9, −1,103.5, −227.0; 3,022.4 ft/s in 370.8 s; 169.0 × 58.1 nmi |
| DOI, Kitty Hawk with Antares docked | 86:13:30, 208.0 ft/s in 24.0 s; 58.5 × 9.1 nmi; PDI planned for 108:01:06 | 86:10:52, N81 −206.4, 0, −3.6; 20.6 s; 58.8 × 10.4 nmi as the crew read it |
| The separation, and CIRC | 0.8 ft/s radially down; CIRC 105:11:45, 73.4 ft/s into 63.2 × 55.4 nmi | 0.8 ft/s; 105:11:45, 76.2 ft/s on the PAD, into 63.9 × 56.0 nmi |
| Antares's first P52, on stars 22 and 16 | 104:45:38: N05 0.005°, N93 +0.098, +0.056, −0.017° | 104:46:37: 0.04°; +0.097, +0.062, −0.013° |
| PDI | the PAD at 105:52:04; 108:00:49, 46,257 ft over the site | the PAD at 105:53:23; 108:02:25, 47,355 ft (the PGNCS's) |
| The ABORT switch's workaround | MODREG 71 before PDI; the throttle-up by hand at +27.3 s; ZOOMFLAG at +44.5 s, 45,495 ft; LETABORT reset at +66.5 s, 45,197 ft; MODREG 63 at +80.5 s, 45,189 ft | the same keys at the same times; 47,503, 46,996 and 46,459 ft |
| Noun 69 | +2,600 ft 113 s after PDI | +2,800 ft, 112 s after PDI |
| The landing radar | low scale from 4 min 52 s before PDI; its breaker cycled 386 s after PDI, 25,033 ft up; VEL out 21 s later and ALT 23 s later, 20,016 ft up; ΔH 949 ft | low scale from 107:57:34.66; the breaker cycled 384 s after PDI; velocity good 20 s later and range 22 s later, 22,486 ft up; ΔH about 1,000 ft |
| P64 | 108:08:39 at 8,098 ft, aiming 1,419 ft short of where Antares came down | 108:11:09 at 8,190 ft, aiming 1,350 ft short of the target |
| The landing | P66 at 108:10:54 at 359 ft, 1,687 ft short; touchdown 108:13:16 on the spot; 1,027 lb of the DPS's propellant left | P66 at 108:13:09 at 360 ft, about 2,200 ft short; 108:15:09; 794 lb |
| The plane change (LOPC-1) | 117:32:40, N81 −12.1, +359.5, 0; 359.7 ft/s; 62.0 × 56.3 nmi | 117:29:32, N81 −12.9, +370.7, −5.5; 370.8 ft/s; 62.1 × 57.2 nmi on the PAD |
| The ascent | liftoff 141:43:53, N76 5,542.9 and 31.3 ft/s, −0.12 nmi crossrange, TPI's TIG 142:29:15; 442 s on the APS into 52.6 × 9.2 nmi | 141:45:40, N76 5,542.9 and 31.3 ft/s, −0.3 nmi, TPI 142:30:51; 432.1 s into 51.7 × 8.5 nmi |
| The tweak | 141:55:13, 9.3 ft/s on the RCS | 141:56:49, 10.3 ft/s |
| TPI on the APS | 142:29:15, 99.1 ft/s; Kitty Hawk 26.6° up, Antares 15.0 nmi below | 142:30:51, 88.5 ft/s; 26.6°, 15 nmi below |
| Midcourse corrections, and docking | 0.3 ft/s together; 143:24:27 | 1.1 and 1.6 ft/s; 143:32:51 |
| TEI | 148:36:01, N81 +2,955.0, +1,712.0, −958.4; 3,547 ft/s in 162.3 s | 148:36:01, N81 +3,013.3, +1,667.4, −340.3; 3,460.6 ft/s in 149.2 s |
| MCC-5 | 0.2 ft/s | 0.5 ft/s (the PAD's 0.7) |
| Entry interface | 215:48:03, 36,149 ft/s, 6.71° down, 36.36° S 164.92° E | 215:47:45, 36,170.2 ft/s, 6.37° down, 36.36° S 165.80° E |
| The entry, and splashdown | P61 to P64, then P67; 7.32 g at the peak; 216:02:22, 27.01° S 172.65° W, 0.7 nmi from the target | P61 to P67; 6.2 g on the PAD; 216:01:58, 27.01° S 172.65° W, 0.62 nmi from it |

The table takes these from the flight's figures:
- The launch: AS-509's F-1s give 7,940 kN each in vacuum, the stage's
  39.7 MN on five before the centre engine's cutoff in the report's
  Figure 5-3 [a plot reading], as Apollo 13's did; the peak acceleration
  at the outboard cutoff gives 7,838 kN, which flew the S-IC a second
  long and 1.3° flat. The S-IC's vacuum Isp (305.15 s) and the S-II's
  flow at the high ratio (1,237.5 kg/s) are tuned for the flown cutoffs
  [estimated]. The S-IC still leaves the stack 0.9° flatter than AS-509,
  on SA-504's pitch polynomial [estimated for AS-509], and the S-IVB's
  burn runs 4.5 s long.
- The transposition and docking: the test's crew fly four of the six
  attempts at the flown times and closing speeds, the second and third
  left out. The ring latches 4.9 s after the retraction began are the
  flight's; the LM comes out of the adapter at the hard dock, where
  Antares's ejection came 50 min later. test_apollo_14.gd leaves the
  docking to the ground, at the flight's extraction.
- LOI is centred on the pericynthion, where the midcourse corrections
  put the plane over the site: at the flight's TIG the simulator's burn,
  longer on the larger plane change, ran 3 min past that node, and the
  plane through its end and the site came out 2.5° steeper.
- DOI's TIG is the pericynthion the simulator's LOI left, 2 min 38 s
  after the flight's, and the landing pass comes round 1 min 18 s early.
- The landing radar: Houston's call comes at the flight's time after
  ignition; the simulator's braking runs short of Antares's, so it
  finds the LM lower, and the radar comes good 2,500 ft lower than
  Antares's. The ΔH is the radar's first, at the V57, where the flight's
  first readings ran 13,000 ft long on a side lobe before they settled
  (MSC-04112, section 14.2.4).
- The TPI geometry is the tweak's target: 26.6° and 15 nmi below at
  N37's time (MSC-04330, Appendix B).
- TEI is solved at the flight's TIG for the flown return's inclination,
  entry interface time and corridor; the simulator's Kitty Hawk needs
  more of it up there.

Apollo 15 flown from its data alone, from the pad into its parking orbit
and on through TLI (`tests/scenarios/test_apollo_15_launch.gd`), from its
parking orbit to the landing at Hadley (`tests/scenarios/test_apollo_15.gd`),
from the surface to TEI (`tests/scenarios/test_apollo_15_return.gd`) and
from the transearth coast to the splashdown
(`tests/scenarios/test_apollo_15_entry.gd`), each holding its rows within
set limits of the flight's figures, against the Apollo 15 Mission Report
(MSC-05161) and its GN&C supplement, the AS-510 flight evaluation report
(MPR-SAT-FE-71-2), the main parachute's anomaly report (MSC-05805), the
Earth landing system's experience report (NASA TN D-7437), the flight
controllers' postflight memos, the Apollo Flight Journal and the Apollo
Lunar Surface Journal:

| Quantity | Simulator | Apollo 15 |
|---|---|---|
| Launch: Mach 1, maximum dynamic pressure | 1:06.3; 33.3 kPa at 1:17.8 | 1:05.0; 36.8 kPa at 1:22.0 |
| Launch: the S-IC's centre and outboard engines' cutoffs | 2:15.96 at 2,035 m/s and 23.79° up, 2:39.74 at 2,755 m/s and 20.44° | 2:15.96 at 2,045 m/s and 24.22°, 2:39.56 at 2,756 m/s and 21.27° |
| Launch: the S-II's centre and outboard engines' cutoffs | 7:39.72 at 5,708 m/s, 9:08.52 at 6,984 m/s | 7:39.56 at 5,713 m/s, 9:09.06 at 6,995 m/s |
| Launch: the S-IVB's cutoff, and insertion | 11:37.40, 11:47.20 at 7,803.4 m/s | 11:34.68, 11:44.67 at 7,801.9 m/s |
| Parking orbit, and the S-IVB's propellant for TLI | 90.7 × 90.6 nmi, 29.679°; 75,445 kg | 91.5 × 89.6 nmi, 29.679°; 75,960 kg at its second ignition |
| TLI, and the pericynthion after it | 2:50:00, 10,449 ft/s in 352.1 s, C3 −1,436,465 m²/s²; 138.7 nmi at 78:31:21 | 2:50:03, 10,414.7 ft/s in 350.8 s, C3 −1,438,810 m²/s²; 139 nmi at 78:31:21 |
| MCC-2, the SPS's test | 7.9 ft/s at 28:40:00, N81 +1.1, +3.5, +7.0; then 62.8 nmi at 78:35:01 | 5.3 ft/s at 28:40:22 on the SCS; then 63 nmi at 78:35:15 |
| MCC-4, and the pericynthion after it | 1.9 ft/s; 67.1 nmi at 78:35:06 | 5.4 ft/s at 73:31:14; 68.3 nmi at 78:35:06 |
| LOI | 78:31:54, N81 −2,883.5, −745.6, +33.4; 2,979 ft/s in 406.3 s; 170.8 × 59.3 nmi, 26.12° to the lunar equator | 78:31:46, N81 −2,897.5, −776.4, −44.1; 3,000.1 ft/s in 398.4 s; 170.1 × 57.7 nmi |
| DOI, Endeavour with Falcon docked | 82:40:55, N81 −205.3, 0, 0; 205.2 ft/s in 25.0 s; 59.5 × 11.5 nmi; PDI planned for 104:32:51 | 82:39:48, N81 −208.4, −48.0, +2.0; 213.9 ft/s in 24.5 s; 58.5 × 9.6 nmi; PDI 104:30:09 |
| The separation, and CIRC | 1.4 ft/s on P41 at 100:39:37; CIRC 101:38:58, N81 +66.4, 0, +29.4, 72.6 ft/s into 65.2 × 54.4 nmi | 1.1 ft/s on P47 after the undocking at 100:39:16; 101:38:58, N81 +68.3, −0.1, −0.7, 68.3 ft/s into 65.2 × 54.8 nmi |
| Falcon's first P52, on stars 41 and 01 | 101:16:05: N05 0.004°, N93 −0.002, +0.079, −0.048° | 101:16: 0.01°; −0.002, +0.076, −0.046° |
| PDI | the PAD at 102:30:40; 104:33:28, 51,441 ft over the site | the PAD at 102:27:58; 104:30:09, about 50,000 ft (the nominal 50,087) |
| Noun 69 | +3,000 ft 77 s after PDI | 2,800 ft downrange, 76.5 s after PDI (voiced −02800) |
| The landing radar and the terrain model | the altitude good 299 s after PDI, ΔH +3,508 ft; the LGC's altitude taken 3,550 ft above the truth, 16 ft above it at P64 | 3:29 after PDI, ΔH +3,400 ft; taken up 4,800 ft, converged over the Apennine foothills |
| Throttle-down | 426 s after PDI | 7:21.7 |
| P64, the 25° approach | 104:42:56, 568 s after PDI, at 7,106 ft, aiming 1,987 ft from where Falcon came down; 27 LPD clicks | 104:39:32, 9:22.8 after PDI, at 7,000 ft; 18 redesignations |
| The landing | P66 at 104:44:33 at 391 ft, 651 ft off; touchdown 104:45:53, 745 s after PDI, on the spot; 1,460 lb of the DPS's propellant left | P66 at 104:41:08 at 400 ft; 104:42:29, 740 s after PDI; 1,188 lb |
| The plane change (LOPC-1) | 165:15:49, N81 −9.5, +317.6, 0; 317.6 ft/s in 20.0 s; 66.1 × 52.5 nmi | 165:11:32, N81 −9.2, +330.3, +18.4; 330.6 ft/s in 18.3 s; 64.5 × 53.6 nmi |
| The ascent | liftoff 171:39:54, N76 5,530.4 and 32.0 ft/s, +0.70 nmi crossrange, TPI's TIG 172:32:23; 444 s on the APS into 42.7 × 9.0 nmi | 171:37:23, N76 5,530.4 and 32.0 ft/s, −0.4 nmi, TPI 172:29:39; 431 s into 42.5 × 9.0 nmi |
| TPI on the APS, no tweak | 172:32:23, 78.7 ft/s; Endeavour 25.5° up, Falcon 11.9 nmi below | 172:29:40, 72.7 ft/s |
| Midcourse corrections, and docking | 0.3 ft/s together; 173:23:41 | 1.6 and 2.8 ft/s; 173:36:25 |
| The shaping burn | 221:20:47, N81 +16.8, 0, −102.1; 103.3 ft/s into 76.7 × 54.5 nmi | 221:20:48, N81 +17.0, −0, −64.2; 66.4 ft/s into 76.0 × 54.3 nmi |
| TEI | 223:48:45, N81 +2,922.6, −861.1, +701.0; 3,126 ft/s in 151.7 s | 223:48:45, N81 +2,945.2, −761.3, −171.4; 3,046.8 ft/s in 140.9 s |
| Worden's EVA | the cabin vented from 241:57:12 to 242:36:19 | 241:57:12 to 242:36:19 |
| MCC-7 | 1.2 ft/s | 5.6 ft/s on the SM RCS |
| Entry interface | 294:59:11, 36,095 ft/s, 6.51° down, 14.09° N 175.08° W | 294:58:55, 36,096.4 ft/s, 6.51° down, 14.23° N 175.02° W |
| The parachutes | the mains out at 295:08:34; one deflated 99 s on, at 5,844 ft; two at 39.1 ft/s on average from there, 37.3 ft/s at the water | 295:07:34; one deflated about 99 s on, at about 6,000 ft; two at 37.5 ft/s on average, 36 ft/s at the water by design, 32 on three |
| The entry, and splashdown | P61 to P64, then P67; 6.49 g at the peak; 295:12:43, 811 s after entry interface, 26.14° N 158.15° W, 1.4 nmi from the target | P61 to P67; 6.2 g on the PAD; 295:11:53, 778 s after it (the PAD's 809 on three mains), 26.13° N 158.14° W, about 1 nmi from it |

The table takes these from the flight's figures:
- The launch: the S-IC's vacuum Isp (305.1 s) and the S-II's flow at the
  high ratio (1,240 kg/s) are tuned for the flown cutoffs [estimated];
  the S-IVB's burn runs 2.7 s long, and on the standard atmosphere the
  maximum dynamic pressure comes 4 s early and 3.5 kPa low.
- MCC-2, the SPS's test after its THRUST light stayed on from TLI, is
  flown on P40, where the crew flew it on the SCS.
- DOI: the RTCC sizes it through the field the stack flies, needing no
  trim, where the flight's perilune decayed faster than the ground
  predicted until the DOI trim (95:56:44.7, 3.2 ft/s on the SM RCS):
  its perilune comes out 2 nmi higher than the flight's, its revolutions
  15 s longer, and PDI and the landing come 3 min late.
- The separation is flown on P41 at the timeline's TIG, 21 s after the
  undocking: Endeavour turns off Falcon as it burns, and senses more than
  the PAD's 1.0 ft/s.
- PDI comes where the flight's did, 17.04° of arc before the site; the
  e-load's ignition point, 15.63°, is its ignition algorithm's, not
  flown here. The simulator's braking holds Falcon higher than the
  flight's at first, and its radar's altitude comes good 90 s later than
  Falcon's; the terrain model then takes the LGC's altitude up 3,550 ft
  against the flight's 4,800, and over the foothills the radar brings
  it back.
- The redesignations: the test's commander clicks the LPD once a second
  while a click brings it nearer the spot, where Falcon came down, 590 m
  north and 151 m west of the target; Scott moved it 338 m uprange and
  409 m north of where the guidance was taking him, the ground's
  state vector having Falcon south.
- The rendezvous: Endeavour docks with no station-keeping, where the
  flight's docking followed 20 min of it.
- The shaping burn is the RTCC's at the PAD's TIG onto the PAD's orbit,
  from the orbit the simulator's Endeavour has come to by then: its ΔV
  differs, and so does TEI's.
- Worden's EVA passes as time, the cabin vented from its start to its
  end [simplified].
- One of the mains fails 99 s after they come out, where the flight's
  deflated, about 3 s after the CM RCS's depletion firing ran out of
  oxidizer (MSC-05161, section 14.1.9); the flight's rate on two from
  there, 37.5 ft/s, is derived from the time it took to come down from
  about 6,000 ft. The simulator's CM comes down at the weight it entered
  with, where the flight's weighed 1,200 lb less at the water
  (MSC-05161, Table A-III): it lands 1.3 ft/s faster than the design's
  rate on two [simplified].
- The mains come out 60 s after the flight's: entry interface 16 s late,
  and the CM 44 s longer from there to 10,000 ft, 32 s of it below
  90,000 ft, where its drag is held at the hypersonic trim's
  [simplified].

Deliberate simplifications are tagged `[simplified]` in the code. The main
ones:

- **Gravity.** The Earth, the Moon and the Sun pull where JPL's
  ephemeris (DE441) has them on each mission's dates, and the Moon turns
  by the IAU's rotation model. The Earth is oblate to its zonal harmonics,
  J2 to J4, about its mean pole of date: its tesseral harmonics and
  nutation are left out. The Moon's field is GRAIL's, cut at degree 30,
  which flies a 60 nmi orbit within 1.3 km of degree 100's in a day, and
  fewer degrees farther out; it is sampled every 30 s along each
  trajectory and interpolated between, 10 m off in a day. The onboard
  computers carry the R-2 model they flew with: the Moon's J2, J3, C22
  and C31, within 16,093 km of it. The CMC leaves out the Earth's and
  the Sun's pull below 800 km, and the LGC leaves them out everywhere.
  Their Earth is truth's, and their lunar GM GRAIL's (Colossus's differs
  by 5 parts in a million). The RTCC integrates truth's field, where
  the ground flew R-2 too, so its lunar orbit predictions don't go
  wrong as the flight's did.
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
  (0.011°). The LGC's IMU is a real one too (slice 11a). Its gyros drift
  at the steady rates each mission report measured between its LM's
  first two alignments (Apollo 13's none), where the flights' rates moved
  from one alignment to the next, and on the surface at the rates it
  measured there (slice 11b). The docked alignment isn't flown: at
  undocking the platform stands where the flight's first P52 found it,
  less the drift. The LM start phases begin with it aligned, by the P52
  or P57 before them. P57's gravity is the plumb line as it is: the
  PIPAs' biases, which its two orientations cancel, and their counts'
  quantization aren't modelled, so N04 shows next to nothing. The CMC's
  automatic maneuvers turn the thrust axis onto the target's first, then
  about it. The LGC's turn about a single axis, as Luminary's KALCMANU
  did (slice 11c). Where that axis would take the middle gimbal past
  60°, the LGC routes the turn as the CMC does, in place of the hand
  maneuvers its crews made clear of the lock zone, since Luminary 099
  had no re-planning. Powered up docked, as Apollo 13's lifeboat, the
  LGC's IMU is caged until the crew coarse aligns it through the
  docking.
- **The optics.** The telescope shares the sextant's star line, without a
  trunnion of its own. Their view shows the 37 navigation stars and the
  Earth, the Moon and the Sun, without the fainter stars, aberration or
  the docked LM in the way; the sextant's landmark line shows only the
  Earth and the Moon. The telescope names its stars, which the flown one
  didn't; NAMES turns that off. P22's landmark is ringed, since the
  view's Moon is a plain disc. In the cabin the eyepieces are one
  screen on the lower equipment bay. The LM's AOT shows the same sky,
  without the LM's own structure or the docked CSM in its fields, or the
  sunlight that washed out its rear detents on the surface. Its pair of
  spirals is drawn as a double line, its reticle knob is a rocker that
  turns the reticle at two rates, and a star is sharp across the whole
  field, where Apollo 12's crew couldn't see one more than 20° out. The
  tests' marks in flight are taken as the star lies on a line, the crew's
  turning of Eagle on the hand controller left out, and their counter
  readings on the surface are the geometry's, to the counter's hundredths.
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
- **S-IVB guidance.** The IU flies TLI on its iterative guidance mode
  for one stage, a pass a second, the J-2 at a constant thrust and
  specific impulse and cut off at once, on the C3 its thrust decay left
  the flown one on. TLI's plane is the flown one, which the IU's
  preflight targeting gave; the RTCC solves the ignition time and the
  energy for the flown free return, and puts the conic's perigee
  mid-burn.
- **P40 steering.** The CMC's P40 and P41 steer as Colossus's did: the
  N81 ΔV set inertially at TIG and turned through half the burn's arc,
  drawn down by the sensed ΔV, the thrust steered onto it until the last
  4 s. The DAP turns the thrust onto it at its own rates, not on the cross
  product's gain, and the burn's mass is the true one, where the crew
  loaded it into the DAP. The LGC's P40 to P42 steer as Luminary's did
  (slice 11c), on its own thrust constants, with the thrust taken along
  +X, where FINDCDUW steered its filtered measure of the thrust's
  direction and the descent engine's trim gimbal trimmed it.
- **Entry guidance.** The CMC flies Colossus's entry guidance, ported
  from its listing, on its own state vector and accelerometers. P61
  predicts the entry by integrating the state vector, where Colossus
  worked in conics, and the entry PAD's predictions are the CMC's, not
  the RTCC's own entry simulation. The target sits on the simulator's
  round Earth, its geodetic latitude taken for geocentric. The CM trims
  with the heat shield square to the air. The entry DAP rolls at up to
  20°/s, speeding up and braking at the rates its roll control assumed,
  not on the jets' phase plane, and P62 hands over to P63 21 s after the
  CM comes within 45° of the entry attitude, the rest of the maneuver
  taken as done.
- **Atmosphere.** The 1976 U.S. Standard Atmosphere turns with the
  Earth, without winds. Its density is a log-linear table of the
  standard's values; its pressure and speed of sound come from the
  standard's layers.
- **Launch.** The pad sits on the simulator's round Earth, its geodetic
  latitude taken for geocentric. The vehicle is a point 1 m over the pad
  whose thrust turns at the IU's rate limit, 1°/s. Its engines run at
  their stages' thrust, with no start or shutdown transients but the
  S-II's and S-IVB's starts, and no engine failures. The S-IC's thrust
  follows the air's pressure, and its propellant ends its burn at the
  flown time. The IU's pitch program is SA-504's; AS-506's own isn't at
  hand. The S-IVB vents and burns 1,051 kg in the parking orbit, taken
  off at insertion. Apollo 8's launch (AS-503) flies SA-504's pitch
  program too, sped up by 7 % for its lighter vehicle, which puts its
  flight path angle at the centre engine's cutoff on the flown one.
- **The launch's view.** Panel 1's launch lights are the Operations
  Handbook's account of them, not their circuits, and their places are
  estimated. The sky is a blend toward blue with the air's pressure and
  the Sun's height, not scattering. Below 8 km the ground is a plain in
  haze, at true scale under the S-IC's base, since the scaled Earth
  would pass through a vehicle 113 m tall.
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
  and the CSM flies the stack, until its crew powers it up (LM PWR), as
  Apollo 13's did. The crew's throttle-up in DOI is the
  LGC's. The descent engine has no gimbal trim, and staging leaves the
  descent stage behind, no longer simulated. The ascent engine fires only
  after staging (no fire-in-the-hole abort).
- **Eagle's aborts.** Luminary's cubic in the descent's time to go for
  the insertion velocity (ABTCOF) is erasable and not at hand: the LGC
  solves instead for the apolune the cubic was fitted to give, on a
  simple model of the coelliptic sequence, and P12's orbit is its floor.
  The aborts' radial rate at insertion is P12's. Apollo 11's later
  aborts also had a phasing burn at 103:40:00; here CSI at the first
  apolune sets the coelliptic height instead. ABORT and ABORT STAGE are
  momentary, and the arming they give their engines holds until ENG ARM
  goes to OFF. ABORT STAGE stages the LM as it is pressed, not after the
  hardware's delay for the descent engine's thrust to die away. The
  LGC's P70 and P71 come only from the pushbuttons. The AGS has no
  abort guidance.
- **Eagle's failures.** A failed regulator's pressure falls, and the
  descent engine's thrust with it, at an estimated rate. An RCS system's
  jets stop at once when its regulator fails. Only the lights the
  catalog's failures need are modelled.
- **The ascent.** The ground times the liftoff from both vehicles' true
  state vectors, and uplinks them as the truth. The lead Columbia has at
  insertion is estimated from Apollo 11's rendezvous. P12's steering
  takes the engine's nominal thrust for its acceleration, not the
  measured one.
- **Eagle's cockpit.** On the HUD it is a desktop overlay, not Eagle's
  panels: the LGC's DSKY and the switches the LM's burns and landing
  need, with the abort guidance section's attitude hold and ΔV counter
  (Apollo 13's) but none of its guidance. The window view from Eagle is
  from its centre of mass, and its chase view gives way to the window
  view below 40 km, where a camera beside it would see the scaled Moon
  from the wrong place.
- **Eagle's cabin.** It is a blockout, like the CM's: the shell and the
  stations follow the LM in outline, and every panel position is
  estimated. The panels carry only the controls and displays the
  simulator models. LGC MODE stands in for the PGNS mode control, ABORT,
  ABORT STAGE and ENGINE STOP are momentary, and a number stands in for each
  tape meter. The LPD's scale is for the commander's design eye. Seen
  from the cabin, the ground is drawn about the eye, at a scale that
  keeps it below the floor, and Columbia no nearer than 2.8 m. Eagle
  casts no shadow on the ground, and the descent stage can't be seen
  from inside.
- **The LM's start phases.** Columbia drifts in CMC MODE FREE while
  Eagle flies. The start phases fly DOI as the RTCC models P40's burn,
  and set Eagle down on the site at the time DOI planned for. They leave
  the descent stage the propellant the automatic landing leaves.
- **The rendezvous.** The RTCC targets impulsive burns on the truth's
  gravity and P32 to P35 on the LGC's own model, and P41 flies them as
  finite ones. CDH comes half a revolution after CSI. MSFN's error in
  Columbia's state vector and the braking gates are estimates.
- **The rendezvous radar and P20.** Each flight's radar biases are drawn
  within the Operations Handbook's limits, taken as 3σ; the noise is
  what Apollo 11's radar showed. The radar keeps to mode 1's coverage,
  and there is no mode 2 for the surface. It locks on anywhere within 2°
  of Columbia, with no side lobes to lock onto and no range search to
  sweep. P20 leaves out R24's search pattern, and a mark whose line of
  sight is off by more than 3° is dropped without its V06N05. R65 turns
  Eagle only once the line of sight is 5° off its +Z axis, leading it by
  as much, where Luminary's DAP held it within the deadband the crew had
  chosen. SIGNAL STRENGTH is a number from 0 to 1, from the beam's loss
  and the range's.
- **The AGS.** Its sensor assembly is ideal, its gyros and accelerometers
  exact, and its clock keeps time. Its frame is the platform's through
  the CDUs' angles, 40 arcsec a count, so it starts some 500 ft and 0.5
  ft/s off, as the real one was off by its alignment. The ascent engine
  thrusts along +X, so the AGS's cant terms (4K7 and 4K8) are 0. One LGC
  MODE switch serves both guidance systems. The lunar align, the
  calibrations, the self test and the telemetry are left out (412 reads
  passed), the DEDA's words go in and read out at once rather than on
  the half second, and only V32 sets R47's clock zero.
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
- **Sound.** Every voice is synthesised from an estimated recipe, with
  nothing recorded, and its level against the others is estimated too.
  Only the master alarm's tone is the Operations Handbook's. No voice is
  placed in the cabin: each plays in both ears, in its own vehicle's
  cabin, and at full level through the tunnel while the two are docked.
  The fans run while the CM's buses are powered, and Eagle's while it
  flies, since the ECS isn't modelled.
- **Caution and warning.** Only the status lights the modelled systems
  and the failure catalog need: FC 1 to 3 (for a failed fuel cell rather
  than the handbook's flow, temperature and pH limits, or one tripped off
  its buses), FC BUS DISCONNECT, MN BUS A and B UNDERVOLT, CRYO PRESS, SM
  RCS A to D, CMC and ISS, on MDC-2's lamp matrix and the HUD's C&W line.
  There are no CSM/CM, NORMAL/BOOST/ACK or lamp test switches, and no AC
  bus lights. MDC-1's and MDC-3's MASTER ALARM switch-lights are in the
  cabin, but not the lower equipment bay's.
- **Apollo 8.**
  - The S-IVB's venting after TLI isn't modelled. So the RTCC aims TLI at
    the flight's pericynthion after the separation maneuvers, flying them
    in its trials as impulses: 464.0 nmi at 69:01:20, where the report's
    state at MCC-1's ignition passes the Moon here. TLI's C3 comes out 4 %
    over the flight's.
  - The separation maneuvers are PADs flown on P41, where the crew flew
    them on the THC by the EMS.
  - LOI-1 burns at its PAD's TIG, which set where its perilune lay for
    LOI-2.
  - The SPS gives a short burn's ΔV in full, where MCC-1's 2.4 s gave
    20.4 ft/s of the 24.8 on its low thrust.
  - A site on the ground track (its farthest south, at LOI-2's cutoff)
    sets the lunar orbit's plane where a landing site would. Its REFSMMAT
    is the site's rather than LOI-2's burn attitude, and its altitudes
    count from the Moon's mean radius.
  - AS-503's S-IC and S-II leave its S-IVB about 40 m/s more to give at
    the S-II's cutoff than they left the flight's, where each stage's
    cutoff comes within 0.06 s of the flown. The S-IC is 19 m/s short at
    its cutoff, as Apollo 11's is 26 m/s short, and the S-II's figures (its
    thrust 61 s into its burn, its low mixture ratio's thrust, and its
    propellant from the vehicle's masses) burn out on time at an Isp of
    435 s after the shift. So the S-IVB's first burn runs 7 s long, and
    TLI has 1.5 t less propellant and burns 3.6 s shorter than from the
    parking-orbit start.
  - The maximum dynamic pressure comes 7 s early and 3.4 kPa low on the
    standard atmosphere, as Apollo 11's comes 5 s early and 2.5 kPa low.
- **Apollo 10.**
  - AS-505's S-IC is 25 m/s short at its cutoff, as AS-506's is, and its
    S-II 15 m/s short at its own, so the S-IVB's first burn runs 4.4 s
    long. Each stage's cutoff comes within 0.05 s of the flown. The S-II
    burns out on time on the report's thrusts, its flow at the low
    mixture ratio from the Isp it gives a second before the cutoff, and
    its flow at the high ratio 0.45 % under the report's 61 s into its
    burn, to fit the propellant the vehicle's masses give.
  - The phasing and insertion burns are the flown PADs, fixed maneuvers
    timed from the low point the DOI PAD plans, where the ground's
    two-impulse processor solved them for the rendezvous. The crew
    throttled the DPS up by hand at the PAD's time; P40 flies the PAD's
    throttle schedule instead.
  - The LM carries its crew from TLI, 431 lb over its launch weight, for
    its masses at separation, staging and insertion. The report's masses
    and APS thrust give the insertion's 220.9 ft/s in 17.6 s, where it
    burned 15.5 s.
  - The descent stage is gone at staging, and the staging's gyrations
    (the AGS's mode switch left in AUTO) aren't flown. Nor are the
    unmanned ascent stage's separation and its APS burn to depletion after
    LM JETT.
  - MSFN's tracking error is drawn axis by axis. In lunar orbit its
    radial part changes the orbit's period, which the ground's Doppler
    tracking pinned closely, and at TEI it moves the return's perigee by
    hundreds of kilometres: the flight's TEI came within 0.5° of the
    corridor, the simulator's needs the transearth corrections.
  - The ground deleted MCC-4, its 2.8 ft/s not needed; the RTCC here flies
    it when the tracking has left the approach off.
- **Apollo 12.**
  - The free return the RTCC's TLI leaves passes the Moon 4° north of the
    flight's (25.6° S against 29.7° S), and the approach the midcourse
    corrections leave, on the node of the orbit over the site, comes in
    1.4° steeper than the flight's. LOI-1 turns it farther, and its cutoff
    ends farther north, which leaves the orbit a degree less inclined
    than the flight's 14.6°: the first plane change is 35 ft/s smaller.
  - The RTCC aims LOI-1's plane at the landing site without the Moon's
    field turning it in the day to the landing, and the site is 4 nmi
    south of the orbit at PDI. The flight's RTCC predicted the turning,
    with a model of the field that left the site about 5 miles south
    [published].
  - Noun 69 carries only the correction downrange, as Apollo 12's did.
    MSFN's processor reads the LGC's error along the track with a 60 m
    spread [estimated].
  - The first plane change: the RTCC flies the orbit on to the liftoff to
    find how the Moon's field turns its plane, as a day of tracking let
    the ground predict it.
  - The liftoff: the real Yankee Clipper came round later than the flight
    plan had it, and Intrepid lifted off 2.5 min after the planned
    142:01:18. The simulator's CSM comes round as planned, and Intrepid
    lifts off near the planned time.
  - TEI: the simulator's CSM reaches the flown TEI's place minutes before
    its time, so the RTCC moves the ignition to where the burn needs no
    part up or down [simplified: the RTCC chose the TIG for the least
    ΔV].
  - The LM carries its crew from TLI, and its RCS's load at liftoff is
    estimated. The test's commander flies the LPD and P66 to the spot
    Intrepid came down on; Conrad flew over the crater and back.
  - AS-507's S-IC is 23 m/s short at its cutoff, as AS-506's is, and its
    S-II another 25 m/s at its own, so the S-IVB's first burn runs 9 s
    long, and TLI has 1.6 t less propellant than from the parking-orbit
    start. Each stage's cutoff comes within 0.03 s of the flown. The S-II
    burns out on time at its flow at the high mixture ratio 0.8 % under
    the report's 61 s in (which counts the pressurization's flow), its
    shift at the engines' 490.0 s rather than the IU's command at 487.3
    s, and its flow at the low ratio at the 427 s Isp of the report's
    Figure 6-3 [estimated].
  - The lightning is what the crew and the ground saw of it. The mains
    read 25.5 V on the batteries, where the flight's read 24 V, and the
    CM's systems run down to 20 V [estimated: the flight's CMC ran on at
    24 V, restarting in the dip to 18 or 19 V]. The CMC's five restarts,
    the AC buses' lights, the event timer, the nine measurements lost for
    good and the SM RCS quantity gauges aren't modelled. The tumbled
    platform is caged at once, where the flight's gimbals drove round at
    35°/s until the crew pulled the IMU's breakers in orbit; the CMC
    integrates the ascent on it, and the ground's state vector uplinks put
    its navigation right, as the flight's did.
  - The IU holds the stack heads down in the parking orbit, the optics on
    the sky, as Apollo 12's P51 and P52s on it need. It rolls to it from
    the launch's attitude at once at insertion, and back heads up at once
    when it turns for TLI, 60 s before the ignition, as the CSM's burns
    fly.
  - The crew's reset of the fuel cells is each cell's FC switch, standing
    for its MN BUS A and B switches; the ground calls for it 29 s after
    the telemetry shows the cells off the line, as 2:19 came after the
    switch to AUX at 1:50 on the onboard tape [derived]. The Mission
    Director's report has the SCE working again at 97.5 s.
- **Apollo 13.**
  - The LM docks at its nominal roll index. Aquarius's docking ring's
    calibration is not modelled, and the LGC's outer gimbal angle at the
    docked alignment is 118° from Aquarius's.
  - The oxygen tank's failure is its effect on the power: the vent's
    push on the stack, which the ground's tracking saw, is left out, and
    so are the cabin's carbon dioxide (the crew's adapted scrubbers), its
    cold and its water.
  - The stack holds its attitude through the coasts, without passive
    thermal control, and the LM's jets use a third of the flight's
    propellant.
  - The stack weighs from the incident on what the mission report has it
    weigh: the SM's dry mass takes the SPS's load then, and leaves out
    the oxygen the incident lost.
  - The LM's batteries are one store of ampere-hours with a load for each
    state the crew put it in; the CM's entry batteries charge at a fixed
    current from the LM.
  - The crew use the AGS as Aquarius's did, to hold an attitude and count
    the ΔV along the LM's X axis; its guidance (slice 11e) isn't flown. The ground's docked alignment, its fine align
    torquing and its REFSMMAT, comes up at once, and the PGNS comes back
    at 133:30 on the ground's angles, without the crew's Sun and Moon
    P52.
  - There is no launch for Apollo 13 yet: its start phases begin in the
    parking orbit.

## Tests

From the repository root:

```
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gexit
```

That runs the whole suite, which takes over an hour and a half, nearly
all of it in the scenario tests. Add `-gdir=res://tests/unit/` to run
only the unit tests, in about ten minutes, or `-gselect=<name>` to run only the
scripts whose file names contain `<name>`. CI runs the suite in eighteen
parts side by side (`.github/workflows/ci.yml`): the unit tests dealt
out over three jobs and the scenario tests over fifteen, by each file's time
on the runners (`.github/unit_seconds.txt`,
`.github/scenario_seconds.txt`). Beside them, its build job
exports the PC VR presets with Godot 4.4.1's templates and flies a
minute of the launch on the exported Linux build.

The unit tests cover:

- The Bus
- The propagator: orbit closure, step independence, SOI re-basing, lunar
  orbit stability
- Gravity (`tests/unit/test_gravity.gd`): the Earth's zonal harmonics
  against their potential's gradient, the energy counting them held round
  an orbit, a parking orbit's node regressing at J2's rate, the Sun's pull
  against its tide, the RTCC's vacuum perigee flown through the
  oblateness, above the surface and under it, and the Earth's pole of
  1969
- The Moon's field (`tests/unit/test_moon_gravity.gd`): the mission
  flies GRAIL's field to degree 30 with its GM; the recursion against
  the direct sum's gradient, the mascons pulling up to 884 µm/s² round
  the equator 60 nmi up; R-2 against its potential's gradient, and
  nothing from it past 16,093 km; both bounded inside the Moon, where a
  trial diving through the surface goes; the degree fading with
  distance; 12 h of a 60 nmi orbit flown as
  `tools/gravity/moon_gravity.py` integrates it independently, to a
  tenth of a millimetre; the propagator sampling the field where the
  trajectory is, and under thrust where the thrust carries it, the
  samples ahead taken again when a burn begins or ends within an
  interval (0.01 µm/s² off where the held ones are 10 to 13); and each
  computer on its own model: the CMC without the Earth and the Sun below
  800 km, the LGC without them anywhere, R-2 383 µm/s² off GRAIL's pull
  60 nmi up
- The Moon-fixed frame on the circular model: the Moon keeps a face to
  the Earth and turns once a sidereal month, and selenographic
  coordinates round-trip
- The ephemeris (`tests/unit/test_ephemeris.gd`): the fitted series
  against JPL's values held out of the fit, the Moon-fixed frame against
  Horizons' sub-Earth point and the libration's limits, smooth joins
  between segments, the Moon's spin as its frame turns, the Sun 10.7°
  over Tranquility Base at touchdown (the mission report has 10.8°), the
  Moon's pole 6.6° from its orbit's normal, a sidereal month of 27.32
  days, and the mission choosing the model; Apollo 8's (slice 7a),
  Apollo 10's (slice 7b), Apollo 12's (slice 7c) and Apollo 13's (slice
  7d) against their own
  held-out values, as close
- The missions (`tests/unit/test_missions.gd`), slice 7a: each under
  `data/missions/` flies its own world and vehicles, Apollo 8's stack
  126,867 kg at TLI's ignition, its CSM 63,524 lb at the separation and
  its CM 12,179 lb for the entry, and Apollo 11's again after it. CAPCOM
  calls each vehicle by its call sign, every timeline entry is one
  Mission Control can make, and Apollo 8 has its own checklists and no
  LM's. CSM/LV SEP without an LM leaves the CSM alone, the test article
  and the S-IVB behind, and an Apollo 8 checkpoint keeps its mission and
  no LM. Slice 7b: Apollo 10's stack 292,191 lb at TLI's ignition, its
  CSM 63,560 lb, its CM 12,138 lb and Snoopy 31,166 lb at its separation,
  with half an APS load; its checklists, Snoopy's for a flight without a
  landing; and from `lunar_descent` the phasing and insertion PADs timed
  from the low point, the phasing's throttle schedule in the LGC, and
  staging in orbit into `lunar_ascent`, the ascent engine's burn there
  its insertion. Slice 7c: Apollo 12's stack 134,986 kg at TLI's
  ignition, its CSM 63,535.6 lb at docking, its CM 12,283.5 lb, and
  Intrepid 33,985.5 lb at its separation, 16,564.2 lb on the surface and
  10,749.6 lb at lift-off; its checklists, with noun 69 in the powered
  descent's; from `lunar_descent` the LGC's state vector 4,400 ft off
  along the track at PDI, as the PDI PAD brought it before the start; and
  from `lunar_ascent` Yankee Clipper's orbit over Intrepid at the liftoff.
  Slice 7d: Apollo 13's stack 96,038.7 lb from the incident, Aquarius
  33,499.1 lb and the CM 12,367.6 lb for the entry; its checklists,
  opening on the failure at `tank_failure`, every one of Aquarius's steps
  checking itself off
- The lifeboat (`tests/unit/test_lifeboat.gd`), slice 7d: docked, the LM
  dark until its crew powers it up, then 30 A on its batteries with the
  PGNS up and 12 A powered down; the docked LGC's platform caged until a
  coarse align onto the CM's through the docking, as Apollo 13's crew
  worked the angles out; the LM's descent engine, started by hand, and
  its jets flying the stack; the AGS holding it and counting its ΔV; the
  CM powered down to its emergency load and dark, and charging its entry
  batteries from the LM; tank 1 leaking away 2 h 20 min after tank 2
  fails; LM JETT from the CM pushing it back; a misaligned platform, the
  DAP's hold after a burn's program, the PC+2 throttle schedule, and a
  checkpoint that keeps it all
- The failure catalog (`tests/unit/test_failures.gd`), slice 9a: each
  failure in `data/failures.json`, set in a headless flight, lights its
  caution and warning light, sounds the master alarm and changes its
  system as the catalog says (the O2 tank vented, the fuel cell's output
  gone, the quad dead, the CMC's DSKY dark, the IMU caged for good); a
  checkpoint keeps the armed and the failed, and the clock comes to an
  armed one on its second; a mission arms its own; the instructor's page
  fails the one it shows; and a failure opens its malfunction procedure.
  Apollo 14's ABORT switch, which no light shows, sets the LGC's abort
  bit, and its landing radar's scale goes low
- Apollo 11's program alarms (`tests/scenarios/test_program_alarms.gd`),
  slice 9b: the landing flown as its crew flew it, the rendezvous radar's
  switch turned to SLEW, Aldrin's V16N68 for ΔH, and Armstrong's ATT HOLD
  at 102:43:08 and P66 at 430 ft. It brings 1202s 358 and 412 s after
  PDI in P63, and 1201s at 562 and 592 s in P64, each on V05N09, with
  Houston's GO; the flight had them 5 min 17 s to 9 min 53 s after PDI.
  Eagle lands 80 m from the site, 0.5 m/s down, 12 min 15 s after PDI.
  With the switch at LGC no alarm comes, and the LGC's load peaks at 92 %.
  `tests/unit/test_lgc_executive.gd`: the eight core sets and five VAC
  areas and their alarms, the jobs by priority, a load within the LGC
  never alarming, the radar's CDUs counting only on Apollo 11's LGC away
  from LGC, the crew's monitor, and a checkpoint of the jobs and restarts
- The backups (`tests/scenarios/test_backups.gd`), slice 9c: Apollo 11's
  TEI flown on the SCS with the CMC failed. The GDC is aligned 20 minutes
  before TIG, the burn attitude found on the FDAI's GDC angles, and the
  burn ended by the EMS at the PAD's ΔVC. It comes 3,309.0 ft/s against
  the PAD's 3,309.3, 0.26° off its direction. Apollo 11's entry, the CMC
  flying it, with the EMS set to the entry PAD: its 0.05 G light 1.2 s
  after the CM reached 0.05 g, LIFT UP ten seconds on, the scroll's g
  within 4.5 % of the CM's load and its velocity within 3.5 % of the
  CM's, and its range 2.9 nmi from zero at the splashdown.
  `tests/unit/test_scs_ems.gd`: the SCS's hold and rate command at RATE
  LOW and HIGH and ATT DEADBAND MIN and MAX; the GDC's drift, GDC ALIGN
  and the FDAIs on it at SCS; the EMS's rocker; the EMS ending an SCS burn
  (106 ft/s for 100 set, the tail-off after it) and keeping THRUST ON
  from starting below zero; MTVC pitching the CSM on the gimbal; and a
  checkpoint
- The launch's aborts (`tests/scenarios/test_launch_aborts.gd`), slice
  9d: from a point in each mode's window of Apollo 11's launch, set off
  by a failure from the catalog. Downrange is measured along the nominal
  flight's ground track, and crossrange off it:

  | Mode | Set off by | Where it came down | Area (Mission Operation Report) |
  |---|---|---|---|
  | IB | S-IC engines 1 and 2 out at 1:00; the EDS aborts on its own | 2.9 nmi downrange, 0.1 nmi off the track; 5.7 g, 9.8 m/s | launch site to 520 nmi |
  | II | the S-II's engines out at 4:00; Houston's ABORT and the handle; full lift | 530.6 nmi, 0.2 nmi off; 10.5 g | 440 to 3,200 nmi on the track |
  | III | Apollo 13's O2 tank at 11:00; the ground's 378 m/s retrograde burn; half lift | 3,304.9 nmi, 52.5 nmi south; 7.9 g | 3,000 to 3,350 nmi, about 70 nmi south |
  | IV | the S-IVB's engine out at 10:30; the SPS's 493 m/s into orbit | 85.6 by 84.9 nmi, still up an hour on | a safe orbit (perigee at least 75 nmi) |

  `tests/unit/test_launch_escape.gd`:
  - a pad abort on the handle climbs 1,046 m and comes down 1.7 km out
    to sea; the tower goes at 14.1 s, the drogues at 16.1 s and the mains
    at 28.1 s, as the handbook's low abort has them;
  - the EDS aborts on the rates 1.6 s after the IU's platform fails.
    With LV RATES off it doesn't, and Houston's ABORT asks for the
    handle;
  - two S-IC engines out abort, but not after the IU switches the EDS
    off;
  - after the tower the handle separates the CSM 3 s on, with the SM's
    +X jets while held;
  - the modes are called as Apollo 11's were;
  - a checkpoint under the tower comes down on the same spot.

  `tests/unit/test_failures.gd`: each launch vehicle failure lights its
  lamp in its stage, and a failure armed on an event comes that long
  after it
- The LM's aborts (`tests/scenarios/test_lm_aborts.gd`), slice 9e: from
  the checkpoint before Apollo 11's PDI, each abort reaches an orbit and,
  after a P52 there on two stars the crew can see, the rendezvous from it
  docks:

  | Abort | Set off by | Insertion | Rendezvous |
  |---|---|---|---|
  | P70, 3 min into P63, 17 km up, Eagle 7.2° ahead of Columbia | the crew's ABORT | on the descent engine in 156 s: 9.1 by 130.1 nmi (the phasing's apolune 131.4), 3,520 kg left | CSI 49.9 ft/s, CDH 115.5, ΔH 16.1 nmi; TPI 2 min 44 s after the PDI PAD's 105:12:41, midcourses 7.3 ft/s; docked at 106:05:17 |
  | P71, in P66 at 500 ft, Columbia 10.4° ahead | DES REG at 523 ft, the descent helium's regulator failed | on the ascent engine in 428 s, no lower than 488 ft: 9.3 by 64.3 nmi (63.6), 170 kg left | CSI 47.2 ft/s, CDH 36.5, ΔH 18.7 nmi; TPI 1 min 28 s after the PAD's 107:11:41, midcourses 3.7 ft/s; docked at 108:04:01 |

  A checkpoint in P70 flies on to the same orbit.
  `tests/unit/test_lm_abort_buttons.gd`: in orbit ABORT STAGE only
  stages, and V37 can't select P70; each pushbutton arms its engine until
  ENG ARM goes to OFF; DES QTY lights at 5.6 % without the master alarm,
  RCS A REG goes out as its valves close, LGC as GUID CONT goes to AGS,
  and DES REG is dark before the first arming and after staging.
  `tests/unit/test_failures.gd`: each of the LM's failures lights its
  light and the LM's master alarm (the ABORT switch's short, which no
  light shows, sets the LGC's abort bit) and opens its procedure in
  Eagle's book. `tests/unit/test_ascent_guidance.gd`: the aborts' apolune is
  above Columbia's with Eagle ahead, lower the more Columbia leads, and
  P12's with no TPI time.
- The lightning's pieces (`tests/unit/test_lightning.gd`), slice 10c: the
  fuel cells tripped off their buses until each FC switch goes OFF and
  ON, a cell switched off before it not tripped; the mains on two
  batteries under the undervolt limit, the CM running on; the SCE on
  AUX, OFF or NORM; the ground's calls for SCE to AUX 59.5 s after the
  telemetry goes and for the reset 29 s after it shows the cells, by
  name for one, and none for a CM powered down; a tumbled platform's ISS
  out at a coarse align; and a checkpoint of them all. The catalog's
  test runs the three as the others, the SCE's without a light, and
  Apollo 12's launch start alone arms them on its liftoff; as it does
  Apollo 13's S-II centre engine (slice 10d), which it runs with the
  launch vehicle's others
- The terrain: Tranquility Base 1,927 m below the reference sphere, West
  crater 30 m deep east of the LM, and the maps blending without steps;
  Surveyor III 1,432 m below it on its crater's slope, and Intrepid's
  spot 10 m higher
- The landing radar: its slant range to the ground in both antenna
  positions, over West crater too, its data-good ranges and its velocity
  over the turning surface; in low scale the range within 3,500 ft and
  the velocity within 4,600 ft of altitude, the scale low below 2,500 ft
  and high above 2,800 ft, and a breaker's cycle bringing it back in high
  scale, its velocity good 20 s later and its range 22 s later (slice
  12a)
- The ascent guidance: its targets are a 9 × 45 nmi orbit, it pitches
  over along the track, steers back into the CSM's plane, and its time to
  go is the rocket equation's
- The launch's models (`tests/unit/test_launch_models.gd`):
  - the atmosphere against the 1976 standard's table;
  - the Earth-fixed frame turning once a sidereal day, the pad moving at
    408 m/s and the air there still;
  - the pad under the launch REFSMMAT's vertical;
  - the IGM's integrals over burns in sequence, with coasts between,
    against the acceleration integrated step by step.
- The S-IVB's iterative guidance (`tests/unit/test_igm.gd`): from the
  flown TIG onto the flown TLI's conic, in planes turned 0, 1.3 and −2°
  about the burn, it cuts off on the conic's energy within 1 J/kg and in
  its plane within 0.005°, at its radius and flight path angle, 13° past
  its perigee; its time to go, worked out every second, puts the cutoff
  within 0.34 s from the burn's fifth second on
- The rendezvous targeting: the CSM's elevation, the next apsis, CDH
  leaving the LM the same height below the CSM's orbit all the way round,
  CSI sized for the TPI elevation at TPI's time, and TPI's time and its
  transfer meeting the CSM (24.6 ft/s, and 31.6 ft/s to brake)
- The rendezvous radar (`tests/unit/test_rendezvous_radar.gd`, slice
  11d): its angles and mode 1's coverage; in AUTO TRACK the lock-on
  within its beam, good data 15 s on, NO TRACK out, and the range and
  range rate to a count; the LGC's designate closing the loop with the
  track enable; slewed by hand, SIGNAL STRENGTH peaking on Columbia and
  no lock in SLEW; its errors within the flight's; and no data with the
  Moon in the way, beyond 400 nmi, docked or powered down
- Luminary's P20 (`tests/unit/test_lgc_p20.gd`, slice 11d), Eagle 8 km
  behind Columbia: the filter's update a Kalman filter's and its
  covariance coasting on the state vector; V67's N99 and its load, V93,
  V80, V81 and V95; the lock-on after R61's turn, V06N49 on the first
  mark (V32 marks again, PRO takes it, V34 ends P20), and six marks taking
  a 1.5 km error in the ground's state vector for Columbia down to 23 m;
  R23's lock-on by hand; and alarm 00503 when Columbia isn't where the
  state vectors put it
- The AGS's equations (`tests/unit/test_ags_fp6.gd`, slice 11e): FP6's
  ellipse predictor against a two-body integration 10 and 30 min on and
  15 min back; a transfer along the LM's own orbit needing nothing; CDH
  between coelliptic circular orbits nothing; CSI at an 8° phase, 54.7
  ft/s, with CDH then 4.2 ft/s at 11.9 nmi and the line of sight 27.0°
  at TPI (26.6° targeted); orbit insertion from the surface on a point
  mass to 60,049 ft and 19.8 ft/s up, cut off as the 40-ms logic does;
  and the radar filter taking 3,000 ft of error to 16 ft
- The LGC's R47 (`tests/unit/test_lgc_r47.gd`, slice 11e): V34, or a new
  V47, taking the downlist off at once, so that the AGS waits for the
  next
- The LGC's erasable words from the DSKY (`tests/unit/test_lgc_erasable.gd`,
  slice 12a): V21N01 asking for its address, then loading MODREG in
  octal (107 is 71, on PROG); V25N07 setting ZOOMFLAG and resetting
  LETABORT, and refusing a third register neither 0 nor 1; V11N10
  monitoring channel 30 in R1 alone
- DSKY key logic, with V01 showing R1 alone
- CMC programs, and Colossus's velocity to be gained for an External ΔV
  (`tests/unit/test_agc.gd`): the ΔV's size and its part out of the
  orbit's plane as loaded, the rest turned the way the vehicle moves
  through half the burn's arc, which on a 300 m/s burn in a 60 nmi lunar
  orbit points 0.12° from the retrograde at the burn's middle, where the
  ΔV as loaded points 2.4° off
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
- The LM's P52 and the AOT (`tests/unit/test_lm_p52.gd`), slice 11a: the
  six detents 60° apart and 45° off +X, the front one in the X-Z plane,
  each with its two mark planes about its line of sight; the shortest
  turn exact down to hundredths of a degree (Godot's own takes a turn
  under about 0.2° for none); AOTMARK's marks: V52 and V53 asking for
  the pair's other, a second mark on one line 00114, REJECT dropping the
  last mark and then its pair, 00115 with none, 00111 at PRO without a
  whole pair, 00107 at a sixth, and the star as marked where the platform
  has it; N05 and N93 next to nothing on an aligned platform; and option
  4 orienting REFSMMAT to the landing site at TLAND
- The AOT's reticle and P57 on the surface (`tests/unit/test_lm_p57.gd`),
  slice 11b. The counter's cursor and spiral readings of a star find it
  again (Luminary's SURFSTAR), R59's readings off the LGC's own view of
  it agree with the reticle's, and the knob turns the counter at its two
  rates. P57 refuses in flight (01520). On a platform knocked off on
  purpose:
  - gravity and the stored attitude (technique 1) level the platform and
    keep its azimuth, N04 showing 90° to a gravity never measured and
    then next to nothing;
  - two stars (technique 2) align all of it, and V06N89 places the site
    within a kilometre;
  - gravity and a star (technique 3) after the stored attitude's pass;
  - the surface marks come as AOTMARK takes them (00115, 00111, 00107
    and REJECT), a technique without its flags brings 00701 and a star
    below the horizon 00404;
  - option 4 turns REFSMMAT to the site at TALIGN, the ascent's TIG
- Systems: SPS arming, EPS consumption and the Apollo 13 failure, SCS/CMC
  autopilot, the coast-step policy, and the caution and warning lights:
  each new one sounds the master alarm until a MASTER ALARM switch-light
  resets it, a main bus undervolts under 26.25 V, and the unit is dark
  with the buses dead
- The audio director (`tests/unit/test_audio_director.gd`), slice 6a's
  check: the Bus's events start and stop its voices. Each kind of switch
  clicks as it should (a pushbutton's release silent, the hand
  controllers never), and so does every DSKY key. The jets thump as they
  start and hiss while they fire. The engines' voices follow their thrust
  and the air's its dynamic pressure, and the fans, the breathing and the
  master alarm's tone come and go with their channels. Every event the
  flight fires has a sound or is listed as silent. Each vehicle's voices
  are heard in its own cabin, both while docked, and nothing plays while
  paused or as a checkpoint loads. Each voice renders as its recipe says:
  the one-shots die away, the loops repeat without a seam or clipping,
  and the master alarm's tone is 750 Hz and then 2,000 Hz
- Checkpoint round-trip, with a map of vehicles, each with its own
  systems, the LGC's rendezvous state, Mission Control's planned times
  and timeline, the CMC's state vector, the CSM's unmodelled forces and
  where MSFN's draws have got to, the CMC's IMU and a P52 between its
  marks, its navigation filter and a P23 mark waiting at N49, and the
  Moon's field's samples each trajectory holds and the thrust they were
  taken with, the IU's target conic and its guidance's state, and the
  launch vehicle's stages, time bases, guidance and events, the thrust
  direction P40 holds in a burn's last seconds, the CMC's entry guidance
  and the CM's roll rate, the master alarm circuit, the LGC's throttle
  schedule for P40, and whether N69 has moved its landing site (schema
  17). Older checkpoints are rejected. The AGS comes back from one taken
  mid-initialization, R47 at V06N16 and the DEDA mid-entry (schema 30),
  and R47's downlist from one taken while it is on (schema 31), and the
  LGC's mode register, its LETABORT and the ABORT switch's short from
  one taken with MODREG loaded at 71 (schema 32), the landing radar's
  low scale and its breaker's cycle (schema 33), the transposition and
  docking from one taken mid-retraction, the LM on the S-IVB and the
  capture latches failed (schema 34), and a failed main parachute and
  the cabin vented for an EVA (schema 35)
- The main scene, and in Eagle from `lunar_descent`: its HUD, the keys on
  its LGC or, with G, its DEDA, its two views, its checklist for the
  phase, and L between the vehicles; and the mission it's given, Apollo
  8's with its own checklists
- The hand controllers, from the keys and from the XR thumbsticks, with
  the thumbstick deadzone, and in Eagle its ACA and TTCA about its own
  axes, as its FDAI reads them
- Which vehicle you fly: Eagle from undocking, Columbia again at docking
  or jettison, and L between them while Eagle flies free. Boarding, not
  L, opens the vehicle's checklist for the phase
- Columbia's and Eagle's checklists, the launch's among them: each opens the one its phases name,
  and the HUD shows the checklists of the vehicle flown, both keeping up
  with the Bus whichever shows
- The space view: the cabin and the cameras stay fixed while Earth, Moon,
  Sun and stars turn around them with the attitude, and the LM, once it
  undocks, is drawn where it flies and turned as it is. From Eagle, the
  two vehicles are drawn as they are to each other, and on the surface
  the ground takes the sphere's place, 3.6 m below its centre of mass,
  with Columbia drawn nearer than the ground. From Eagle's cabin the
  ground is drawn about the commander's eye, 2.2 m below it, beneath the
  cabin's floor, and Columbia outside the cabin, 2.8 m out. On the pad
  the sky is blue, the ground is drawn 113 m down under the S-IC's base in
  place of the scaled Earth, and the chase camera stands the Saturn V up;
  in orbit none of it shows
- The ground below Eagle: the maps' heights on its grid, placed at the
  Moon's scale with the eye at the origin, a new grid as Eagle moves on
  or comes down, and the last one drawn while a worker builds the next
- Eagle's cabin (`tests/unit/test_lm_cabin.gd`):
  - The commander stands at the window, 1.6 m above the floor.
  - Each panel faces the crew member who works it, inside the shell.
  - The bulkheads are whole but for the windows and the way aft.
  - The LPD marks are where the commander looks at their angles.
  - The DSKY is within reach of both stations, panel 6 of the LM
    pilot's, and SEAT goes between them.
  - The cabin stays about the centre of mass as Eagle stages
- The cabin controls and instruments, the XR and desktop rigs and the
  OpenXR action map taken from gemini-capsule
- The cockpit layouts: `controls.csv` and `lm_controls.csv` validate,
  malformed rows are reported, and every row round-trips between its node
  and the Bus, a toggle's through its values. Every switch on Columbia's
  and Eagle's HUDs has a cabin control but SPS THRUST ON, the HUD's
  manual backup, which in the cabin is a lamp; each cabin DSKY types into
  its computer (Eagle's with its ALT and VEL lamps), panel 6's DEDA and
  the HUD's key into the AGS, and the desktop rig can click every control
  from the commander's couch or station, panel 6's from the LM pilot's
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

- The launch (`tests/scenarios/test_launch.gd`), slice 5d's check. From
  the pad, the Saturn V flies Apollo 11 into its parking orbit:
  - insertion at 11:51.1, 7,793.1 m/s (11:49.3 and 7,793.1 m/s flown);
  - the orbit 99.9 × 99.8 nmi at 32.521°, 0.003° from the flown plane;
  - each stage's cutoff near the flight evaluation report's: the S-IC's
    within 0.1 s, the S-II's within 0.02 s, the S-IVB's 2.0 s late;
  - Mach 1 and the maximum dynamic pressure near the report's;
  - the CMC in P11, the countdown's start sequence and thrust OK, and
    panel 1's lights through each stage;
  - the S-IVB left with 74,299 kg for TLI (74,452 flown), and TLI planned
    for 2:44:00.

  A checkpoint mid-S-II flies on to the same cutoff
- S-IVB TLI to lunar arrival (`tests/scenarios/test_tli.gd`), slice 5c's
  check: the IU's iterative guidance flies TLI at 2:43:58 into the flown
  TLI's plane, turning it 1.20° as flown, with 3,186 m/s from the J-2 in
  334.8 s (Apollo 11: 3,182 m/s in 346.9 s), onto the RTCC's C3 of
  −1,376,351 m²/s², 0.7 m/s over the flight evaluation report's. The
  stack passes the Moon 896.5 nmi up at 75:05:23, 1.9° N 174.4° W, and
  comes back to an Earth capture, as Apollo 11's free return did (896.3
  nmi at 75:05:21, 0.1° S 174.1° W). A checkpoint mid-burn flies on to
  the same cutoff. And slice 5a's check: the parking orbit's node
  regresses at J2's rate, 0.8° by the flown TLI
- MCC, LOI-1 and LOI-2 into lunar orbit, each PAD uplinked with the
  state vector MSFN tracked (P27) and flown after a P52 to its preferred
  orientation, as every burn in the suite is. The MCC takes the free
  return to 60 nmi over the landing site at 75:53:35, where Apollo 11's
  first left it, with 30.5 ft/s (Apollo 11 took 19.7 and 20.9 ft/s in
  two burns), and LOI-1 comes at 75:50:32 (75:49:50) with 2,885.6 ft/s
  (2,917.5). By the LOI PAD the
  CMC's state vector is 18 km off, and the uplink brings it to 0.4 km.
  LOI-2's PAD targets Apollo 11's 65.7 × 53.7 nmi
- P40's cross-product steering (`tests/scenarios/test_p40_steering.gd`),
  slice 5e's check. From the same state 8 h before the Moon, LOI-1 on
  cross-product steering leaves 57.6 × 169.7 nmi against the RTCC's plan
  of 60.0 × 170.1 nmi; flown on the same PAD holding the ΔV's LVLH
  direction instead, it leaves 57.8 × 162.3, 7.8 nmi short in apolune.
  The perilune's 2.4 nmi either way is the CMC's navigation. LOI-2, a
  quarter of a minute, comes out within 0.08 nmi either way. A checkpoint taken
  in a burn's last seconds, the steering stopped, flies on to the same
  cutoff
- The Moon's mascons (`tests/scenarios/test_mascons.gd`), slice 5b's
  check. From LOI-2, GRAIL's field takes the orbit through the ground's
  tracking figures to 61.8 × 56.9 nmi at 126 h, where Apollo 11's was
  62.4 × 56.6 (the mission report); through R-2 it rounds out to
  59.5 × 59.0, where the ground's R-2 predicted 59.9 × 59.3. A round
  60 nmi orbit, Apollo 10's approach, goes 13.5 nmi out of round by
  then, where the report estimated 11.6. From the same state, the CMC's
  model comes 3.5 km from the truth in two revolutions
- The IMU (`tests/scenarios/test_imu_alignment.gd`), slice 4c's check.
  Twelve hours of translunar coast drift the platform 0.215°, and P52 on
  two stars (Menkent and Altair) leaves 0.006°, under the 0.02° limit,
  with N05 0.001°. A TEI flown on a platform 0.5° off goes 7.84 m/s off
  the aligned flight, where the misalignment predicts 7.82 m/s, and the
  CMC doesn't see it. A yaw in FREE lights GIMBAL LOCK at 70°, cages the
  IMU at 85° and loses the alignment; P52 and P40 refuse (00220), and P51
  finds the platform's orientation on two stars the crew names. P52
  won't coarse align to a new orientation in gimbal lock from where the
  CSM points (00401) until the CSM turns, and P40's maneuver to the burn
  attitude keeps the middle gimbal to 1.3° at most. P52 option 1 puts
  the burn attitude at zero gimbal angles, and with the optics on the
  Moon it finds no stars (00405). Sixteen hours of attitude hold on the
  drifting platform cost 0.16 kg of RCS propellant
- The CMC's own state vector (`tests/scenarios/test_onboard_state.gd`),
  slice 4b's check. From a perfect state, a day's translunar coast leaves
  it 542 m off, as far as the SM's vents move a copy of the CSM, and the
  ground's uplink puts it back to MSFN's tracking error, with P27 and V71
  on the DSKY. The CMC takes uplinks only in P00 with UP TLM CM in
  ACCEPT; in BLOCK a PAD comes by voice. A translation in P00 isn't in its
  state vector, and one in P47 is, all but the 3 mm/s its model of the
  Moon's field drifts from the truth meanwhile
- Onboard navigation (`tests/scenarios/test_onboard_navigation.gd`),
  slice 4d's check. A TEI flown on a platform 0.5° off leaves a vacuum
  perigee of 269 km, far shallow of the 25 to 50 km corridor, and the
  CMC's state vector 3.8 km and 11.2 m/s off. With UP TLM CM in BLOCK
  from then on, the crew marks six stars with P23 every four hours from
  10 h after TEI, three on the Moon's horizon and three on the Earth's.
  At 38.6 h P37 works out 4.7 m/s from the CMC's state, which, flown
  after P52, leaves 43.5 km, where P37 from the unmarked state would
  have left 355 km. After two more sessions a second P37 of 0.19 m/s
  leaves 37.1 km. P23's dialogue: the codes it won't take, 00404 for a
  star it can't lay on the horizon, the landmark line on the horizon
  under the star, V32 dropping a bad mark, a good one bringing a state
  vector 50 km off to 15 km, V67's RMS, and a load starting the filter
  again. In lunar orbit, five P22 marks on the landing site through one
  pass bring the state vector from 2.0 km off to 18 m
- TEI and the transearth MCCs into the entry corridor
- The entry on P61 to P67 (`tests/scenarios/test_entry.gd`), slice 5f's
  check. P61's N60 and N63 read Apollo 11's entry PAD, and from entry
  interface the CM comes down within 3 nmi of its target: Apollo 11's,
  1,500 nmi out, through P65 and P67 with no P66 and loads peaking at 6.5
  and 6.1 g, 0.9 nmi from it (`test_lunar_mission.gd`); the shorter range
  Apollo 11 had planned, 1,266 nmi, through P67 without an up-control,
  1.0 nmi; and 2,000 nmi, skipping out through P66, 1.2 nmi. A checkpoint
  taken mid-roll flies on as it did
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
  complete: the launch, checked off on the vehicle's events with panel 1's
  lights lit and V82 on the orbit, parking orbit and TLI, the MCC, LOI-1,
  LOI-2 and TEI each
  down the SPS burn checklist on P40 with a residual trimmed on the translation
  controller, each after the IMU realign checklist at the lower
  equipment bay (SEAT, its DSKY, the optics and MARK), LM JETT, TEI from
  its start phase, and entry to splashdown on P61 to P67. The cabin
  scenarios share `tests/cabin_test.gd`
- Undocking and docking in lunar orbit (`tests/scenarios/test_docking.gd`).
  The stack splits with its momentum conserved. An equiperiod separation
  (0.6 m/s down across the CSM's velocity, which on Apollo 11's
  out-of-round orbit is off the local vertical) carries the CSM 4ΔV/n
  ahead of the LM half a revolution later, as the linear
  (Clohessy-Wiltshire) solution has it for a round orbit, and brings it
  back within 5 m a revolution later. A checkpoint taken mid-revolution
  flies on as the uninterrupted run does. The CSM docks again on the
  translation controller, and contacts that close too fast or
  misaligned rebound. With the capture latches failed, a contact within
  the limits rebounds too; the probe held in the drogue under +X and
  retracted docks the vehicles 4.9 s on, and let out of the drogue first
  it doesn't. Apollo 14's CSM/LV SEP leaves the LM on the S-IVB, the
  stack's centre of mass and momentum kept, and at the flight's
  extraction the ground takes the docking as done
- DOI on the LGC (`tests/scenarios/test_doi.gd`), slice 3b's check. Eagle
  undocks, Mission Control uplinks a DOI PAD to the LGC, and P40 flies it
  on the descent engine, at 10 % and then 40 % throttle. Half a
  revolution later Eagle passes its pericynthion within 250 m of the
  PAD's 50,000 ft above the site (15,240 m against 15,241 m), while
  Columbia flies on in its own orbit
- The landing at Tranquility Base (`tests/scenarios/test_landing.gd`),
  slice 3c's check, and slice 3f's for the `lunar_descent` start phase.
  LOI turns the orbit over the site, and the `lunar_orbit` phase starts
  over it, in Apollo 11's orbit after LOI-2. The RTCC places DOI for the
  pericynthion to fall where PDI begins, though the Moon's field turns
  the descent orbit's apsides by degrees in the half revolution. From
  `lunar_descent`, the timeline's PDI PAD puts the LGC's state vector
  off by the tracking error at PDI. From a checkpoint before PDI:
  - The automatic landing. The crew keys V57 when the radar's altitude
    comes good, with ΔH at −813 m, and ΔH is −3 m by high gate. P63,
    P64 and P65 land Eagle 86 m from the site at 0.8 m/s down and none
    across.
  - Without V57, Eagle hits the ground 2.8 km from the site at 18.6 m/s.
  - With a 900 m error along the track, the commander redesignates in
    P64 and lands 2 m from the site.
  - A run takes over in P66 at 150 m, with the hand controller and the
    ROD switch.
  - Slice 7c: after throttle-up the ground reads the LGC's error along the
    track to the nearest 100 ft, and V21N69 moves the landing site that
    far downrange while P63 flies on. Before P63 the LGC won't take it.
  
  A landed LM turns with the Moon, and lifts off on its ascent engine.
- Eagle's platform and P52 (`tests/scenarios/test_lm_alignment.gd`),
  slice 11a's check. From `lunar_orbit`, Eagle undocks at 100:12, its
  platform 0.32° off the landing site REFSMMAT, where the crew's docked
  alignment left it, and drifting at the mission report's rates. At 101:12
  the crew's P52 (option 3, stars 25 and 33 in the front detent, each
  marked as Eagle turns it onto the reticle's Y-line and then its X-line)
  shows N05 0.011° (flown 0.03°) and N93 −0.287, +0.290 and −0.089° (flown
  −0.292, +0.289 and −0.094°). It torques the platform to within 0.007° of
  REFSMMAT. DOI and the automatic landing fly on it, 0.13° off at PDI and
  0.15° at touchdown, and Eagle lands 178 m from the site
- Eagle's P57s (`tests/scenarios/test_lm_surface_alignment.gd`), slice
  11b's check. From `lunar_surface`, Eagle sits at Tranquility Base
  yawed 13° left, as Aldrin reported it, its platform aligned 10 min
  after the landing and drifting at the report's surface rates. Its
  crew's five P57s come as Apollo 11's did (MSC-00171, Table 9.6-I):
  - 103:01: gravity, twice as Houston asked (technique 1); N04 90°, then
    0.00°; N93 left untorqued with V34.
  - 103:47: Rigel and Navi (technique 2), which R59 finds in the
    left-rear and right-rear detents, as the crew found them; N05 0.001°
    (flown 0.09°). V06N89 places the site 198 m from Eagle, and V34
    rejects it, as Houston asked.
  - 104:16: option 4 to the site at T3, on gravity and Rigel.
  - 122:17: gravity and Capella, in the right-rear detent. N93 shows the
    night's drift, −0.692, +0.704 and −0.620° (flown −0.699, +0.695 and
    −0.628°).
  - 123:49: option 4 to the site at the ascent PAD's liftoff, on gravity
    and Capella.

  The start's platform leaves the first three N93s at hundredths, where
  the flown ones carried the descent's drift. P12 flies Eagle to its
  insertion on the last: the LGC has it at 60,034 ft and 32.0 ft/s up,
  truly 59,641 ft and 29.8 ft/s, in a 9.1 × 45.3 nmi orbit, the platform
  0.050° off
- The ascent (`tests/scenarios/test_ascent.gd`), slice 3d's check. Eagle
  is set down at the site. The RTCC times the liftoff for Columbia to
  lead by 16.4° at insertion. 33 min before it the crew align the
  platform with P57, as Apollo 11's last one was: option 4 to the site at
  the liftoff, on gravity and a star. P12 lifts off at that time, rises
  for 9 s, and cuts off 7 min 8 s after liftoff. The LGC has Eagle
  inserted at 60,018 ft and 31.97 ft/s up. Its platform, 0.065° off by
  then, turned the thrust and the LGC's measure of it alike, so Eagle is
  truly at 59,199 ft and 27.6 ft/s up, in a 9.1 × 45.5 nmi orbit, within
  0.04° of Columbia's plane, with Columbia 16.42° ahead and 167 kg of
  propellant left. A checkpoint taken mid-ascent flies on to the same
  insertion
- The rendezvous (`tests/scenarios/test_rendezvous.gd`), slice 3e's
  check, and slice 3f's for the `lunar_ascent` start phase. From that
  phase, P12 lifts Eagle off at the ascent PAD's time, 124:22:23
  (Apollo 11: 124:22:00).
  - Five minutes after insertion the timeline's CSI PAD plans CSI at
    50.0 ft/s (Apollo 11: 51.5), 16.3 nmi below Columbia's out-of-round
    orbit, and TPI at 26.8 ft/s.
  - The crew realign the platform with P52 on Rigel and Acrux, as
    Armstrong and Aldrin did after insertion: N05 0.003° (theirs 0.00)
    and N93 −0.032, +0.031 and −0.007° (theirs −0.006, +0.064 and
    +0.137).
  - P20 starts as the G mission's procedures had it (slice 11d). The
    radar locks on 40 s after the P52, 246 nmi from Columbia, and in 12
    minutes its 11 marks take the relative error from the ground's 1,112
    m (Columbia's state vector as MSFN tracked it, and Eagle's own from
    the ascent) to 282 m and 0.28 m/s. N99 shows 8,234 ft, 6.80 ft/s and
    0.0065 rad; the radar's boresight biases, drawn for this flight at
    −0.022 and −0.094°, are estimated at −0.070 and −0.111°. N78 shows
    the radar's range, which less this flight's range bias is within its
    noise and count of the truth.
  - The LGC flies the sequence. By CSI its 28 marks have Columbia 264 m
    and 0.44 m/s off, within the filter's own RSS of 506 m, and its CSI
    is 50.1 ft/s against the PAD's 50.0 (Apollo 11's four solutions
    agreed within 0.2 ft/s). CSI 50.9 ft/s; CDH 8.6 ft/s onto 16.3 nmi
    below (Apollo 11's took 19.9 ft/s for Columbia's orbit); TPI 28.3
    ft/s 71 s before the plan's time (Apollo 11's came 6 min 39 s
    after); and midcourse corrections of 3.0 and 0.9 ft/s (Apollo 11's
    LGC: 0.98 and 1.30), each burned where Eagle is with its +Z on
    Columbia, as Apollo 11's crew burned them.
  - The AGS, brought up on the surface a quarter of an hour before the
    liftoff (slice 11e), navigates the ascent on its accelerometers: 44.6
    × 9.1 nmi after it by its DEDA, against the truth's 45.2 × 9.1
    (Apollo 11's AGS had 46.6 × 9.5 to the PGNS's 47.3 × 9.5). Updated
    from the LGC before each burn (V47), its own solutions match the
    LGC's within the checks' 1 ft/s (2 for TPI): CSI 50.0 ft/s and ΔH
    16.4 nmi (the LGC's 50.1; Apollo 11's AGS had 51.3 and 15.5 nmi to
    the PGNS's 51.5); CDH 4.1 ft/s back and 7.3 up (the LGC's 4.0 and
    7.3); TPI 27.8 ft/s (27.9), the line of sight 26.61° at the LGC's
    TIG.
  - The platform drifts some 0.1°/h, as Eagle's did, and by the midcourse
    corrections has turned the radar's line of sight 0.25° across the
    range, some 200 m at 40 km, which the filter's bias states take in
    only in part; the radar's own errors add to it. On an ideal radar the
    midcourse corrections come to 0.6 and 0.2 ft/s, and the three other
    draws of its errors tried gave 1.1, 3.1 and 1.1 ft/s together. The
    checks hold TPI within 1 m/s of the PAD's and the two within 2.5 m/s.
  - The commander brakes by the gates in 11 min 2 s and stops 40 m out,
    and Collins docks at 0.33 ft/s at 127:53:32. Eagle's ΔV, 128.9 ft/s,
    is 7 % over the RTCC's plan (the check allows 20 %), the braking
    about 37 ft/s of it against the plan's 33.8: P20 kept +Z and the
    radar on Columbia, where after 11c's burns Eagle was left 44° off
    the line of sight and the braking took 42.3 ft/s.
  - GO for jettison comes 2 h 5 min after docking. After LM JETT, the TEI
    PAD plans TEI at 135:23:41, Apollo 11's
- The AGS's abort insertion (`tests/scenarios/test_ags.gd`), slice 11e's
  check. From `lunar_ascent` the AGS is brought up on the surface, its
  orbit insertion (410+00000) and guidance steering (400+10000) keyed on
  the DEDA, GUID CONT at AGS and LGC MODE in AUTO. At the PAD's TIG,
  ABORT STAGE with ENG ARM at ASC: the AGS lights the ascent engine 0.04
  s on, holds the attitude as the stages part, rises vertically to 50
  ft/s in 10.2 s, steers to 60,515 ft above the site's radius and 20.1
  ft/s up (LM-5's targets: 60,032 ft and 19.5 ft/s or more), and cuts
  the engine off after 432 s, into 41.9 × 8.5 nmi. Its own navigation is
  then 456 ft and 0.20 ft/s off, the CDUs' angles it aligned through.
  A checkpoint taken 200 s into the burn flies on to the same cutoff. On
  the DEDA, each of the manual's operator errors lights OPR ERR until
  CLR, a readout runs on (the AGS's clock) until HOLD, an address outside
  026 to 704 blanks the windows, and an octal word reads back as keyed
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
  (`tests/scenarios/test_lm_checklists.gd`, and
  `test_lm_checklists_rendezvous.gd` for the rendezvous) and from its
  cabin (`test_lm_cabin_checklists.gd` and
  `test_lm_cabin_checklists_rendezvous.gd`), slice 3f's checks. The four
  fly the same flights (`tests/lm_checklist_flights.gd`), the rendezvous
  in files of its own for CI's parts. The main
  scene runs in a viewport of its own, worked as a player at the desktop
  works it: the DSKY on the keys through the scene's input, the HUD's
  buttons clicked where they show and its switches set, and the braking
  and the docking on the hand controllers' keys. In the cabin the rig
  clicks each control, the DSKY is typed on panel 4's keys and the DEDA on
  panel 6's, from the LM pilot's station; on the HUD G opens the DEDA and
  the keys type into it. The steps are read off the card and the
  checklists turned with the wrist menu. At the AOT the P52s' marks are
  taken on the reticle's lines and the P57's with its counter (slice
  11b). Each of Eagle's four checklists is flown
  from its phase's start until the HUD, or the card, shows it complete,
  with the same numbers from both:
  - From `lunar_orbit`: UNDOCK in Columbia at GO for undocking, the P52
    after undocking on Acrux and Antares (N05 0.005°, N93 −0.233,
    +0.222 and −0.098°), and DOI to a pericynthion 15,218 m above the
    site.
  - From `lunar_descent`: P63 to P68, and a landing 85 m from the site.
    At high gate the site is 33.7° down the commander's window, and N64
    shows 34.
  - From `lunar_surface`: STAY for T3, the ascent PAD, the P57 33 min
    before the liftoff (option 4, gravity and a star; N93 −0.642,
    +0.803 and −0.866° after the day's drift since the start), the AGS
    brought up after it (slice 11e: AGS STATUS, the DEDA's surface flag
    and its align to the platform, V47 with the AGS's clock zeroed, and
    414+10000; the AGS then 864 ft from where Eagle is), and P12 to a
    9.1 × 45.3 nmi orbit.
  - From `lunar_ascent`: the P57, the AGS (57 ft off) and the liftoff,
    the P52 after insertion on Rigel and Acrux (N05 0.001°), then P20 as the G
    mission's procedures had it (RNDZ RADAR to LGC, V95, V67's loads, the
    lock-on, V80), P32 and its recycles, CSI (50.6 ft/s), P33 and CDH
    (8.3 ft/s), P34 and TPI (27.3 ft/s against the PAD's 26.8), P35 from
    each burn on and the two midcourse corrections on P41 (1.3 and 0.4
    ft/s), V56 inside 18,000 ft, braking by the gates on the TTCA's keys
    in 11 min 8 s, and, after L, Columbia flown into the drogue on the
    THC's keys, capturing at 0.33 ft/s.

  The desktop scenarios share `tests/desktop_test.gd`
- The LM's other systems (`tests/scenarios/test_lm_burns.gd`): P41 on its
  RCS, P47 on a translation, staging and P42 on the ascent engine, P40 on
  the throttle schedule a PAD brings (Apollo 10's phasing burn), its
  autopilot turning and holding it, the LGC dark while the LM is docked,
  and the two computers each keeping its own DSKY
- Luminary's steering (`tests/scenarios/test_lm_steering.gd`), slice
  11c's check. From `lunar_orbit`, Eagle undocks and flies the DOI PAD
  twice from one checkpoint. On Luminary's steering it passes its
  pericynthion 15,240 m above the site, 1 m from the PAD's, which the
  RTCC planned on the same law; holding the ΔV's direction in the
  rotating LVLH frame, as the LGC did before, it misses by 18 m. Staged,
  a P42 of Apollo 10's insertion's size (220.9 ft/s) on the ascent engine
  comes out at 112.0 × 387.5 km above the site, 0.7 km from the RTCC's
  plan and 0.3 km from the LVLH hold's. KALCMANU turns Eagle 120° about
  its Y axis in 60 s, at the 2°/s Apollo 11's crew loaded, within 0.84°
  of its reference, the middle gimbal still; a 150° yaw, whose single
  axis would swing the middle gimbal through 90°, is routed and keeps it
  under 31°, the IMU never caged
- Apollo 8 (`tests/scenarios/test_apollo_8.gd`), slice 7a's check. It
  flies from its data alone, from the parking orbit to the splashdown:
  TLI, CSM/LV SEP with nothing to dock with, and every PAD the timeline
  brings, flown as the crew flew it (the separation maneuvers, MCC-1 and
  MCC-2, LOI-1 and LOI-2, TEI after ten lunar orbits, the transearth
  corrections), then a P52 and the entry on P61 to P67. Each row of Apollo
  8's Fidelity table (above) is held within limits of the flight's
  figures, and CAPCOM's calls come at their times
- Apollo 10's launch (`tests/scenarios/test_apollo_10_launch.gd`), slice
  10b's check. From LC-39B, AS-505 flies Apollo 10 into its parking
  orbit, and the flight goes on through TLI as the parking-orbit start
  flies it:
  - each stage's cutoff within 0.05 s of the flight evaluation report's,
    and the S-IVB's 4.4 s late;
  - the orbit 100.0 × 100.0 nmi at 32.546°, 0.003° from the flown plane;
  - Mach 1, the maximum dynamic pressure and the tilt's start near the
    report's;
  - the CMC in P11, and panel 1's lights through each stage;
  - the S-IVB left with 72,850 kg for TLI (73,462 flown), and TLI at
    2:33:16, 3,050 m/s in 339.8 s, onto the free return past the Moon
    908.2 nmi up at 76:10:18 (907.7 nmi at 76:10:18 flown)
- Apollo 12's launch and its lightning
  (`tests/scenarios/test_apollo_12_launch.gd`), slice 10c's check. From
  LC-39A, AS-507 flies Apollo 12 through its two strikes into its parking
  orbit, and the flight goes on through TLI as the parking-orbit start
  flies it:
  - the first strike at 36.5 s lights FC 1 to 3, FC BUS DISCONNECT and
    both UNDERVOLTs, the talkbacks barber pole, the mains on the
    batteries under 26.25 V and the telemetry gone; the second at 52 s
    ISS and NO ATT, the platform caged;
  - Houston's "SCE to AUX" at 1:36 and its call to reset the fuel cells at
    2:19, each within a second of the flight's; SCE PWR at AUX brings the
    telemetry back, and each FC switch OFF and ON its cell, until only ISS
    is lit;
  - each stage's cutoff within 0.03 s of the flight evaluation report's,
    and the S-IVB's 9 s late; the velocities within 50 m/s and the flight
    path angles within 1°;
  - the orbit at 32.540°, 0.003° from the flown plane, and the S-IVB's
    propellant within 2 t of the parking-orbit start's;
  - P51 in the parking orbit on two stars, N05 0.001°, the ISS light out;
  - TLI at 2:47:50 for 339.4 s, onto the free return past the Moon 279.5
    nmi up at 83:44:04 (280.2 nmi at 83:44:04 flown)
- Apollo 13's launch and its centre engine
  (`tests/scenarios/test_apollo_13_launch.gd`), slice 10d's check. From
  LC-39A, AS-508 flies Apollo 13 into its parking orbit on four S-II
  engines after pogo shuts the fifth down, and the flight goes on through
  TLI as the parking-orbit start flies it:
  - the centre engine out at 330.66 s, LV ENG 5 lit until the S-II's
    separation, Lovell's "Inboard." and Houston's word at 5:36; the IU's
    guidance pitching up 7.6° on the four (about 7° flown);
  - each stage's cutoff, the IU's command to shift the mixture ratio on
    its velocity criterion and the shift within 0.06 s of the flight
    evaluation report's; the S-II's burn 427.6 s (427.64 flown), the
    S-IVB's 151.9 s (152.9) and insertion 1.0 s early; the velocities
    within 40 m/s and the flight path angles within 1°;
  - the orbit at 32.525°, 0.003° from the flown plane, and the S-IVB's
    propellant, 73,331 kg, within 2 t of the parking-orbit start's;
  - TLI at 2:35:45 for 353.8 s, onto the free return past the Moon 250.8
    nmi up at 77:46:47, as the parking-orbit start aims;
  - flown again without the pogo, the shift's command, the S-II's cutoff
    and the S-IVB's within 1.6 s of their predictions, and the pogo's toll
    beside it as the report has it against the prediction: the shift 33.0
    s later (32.2), the S-II's burn 33.0 s longer (34.93), the S-IVB's
    10.8 s (9.3), insertion 43.8 s later (44.07)
- Apollo 14's launch (`tests/scenarios/test_apollo_14_launch.gd`), slice
  12a's check. From LC-39A, AS-509 flies Apollo 14 into its parking orbit
  on the 75.558° azimuth, and the flight goes on through TLI as the
  parking-orbit start flies it:
  - each of the S-IC's and S-II's cutoffs within 0.02 s of the flight
    evaluation report's, and the S-IVB's 4.5 s late; the velocities
    within 20 m/s and the flight path angles within 1°;
  - Houston's marks of the abort modes at the flown times, One Bravo at
    0:42 to mode IV at 9:12;
  - the orbit 100.1 × 99.9 nmi at 31.120°, 0.003° from the flown plane,
    and the S-IVB's propellant, 73,766 kg, within 2 t of the
    parking-orbit start's;
  - TLI at 2:28:34 for 351.4 s, onto the free return past the Moon 1,979.4
    nmi up at 82:15:18 (1,979 nmi at 82:15:19 flown)
- Apollo 8's launch (`tests/scenarios/test_apollo_8_launch.gd`), slice
  10a's check. From the pad, AS-503 flies Apollo 8 into its parking
  orbit, and the flight goes on through TLI as the parking-orbit start
  flies it:
  - each stage's cutoff within 0.06 s of the flight evaluation report's,
    the S-II's on all five engines, and the S-IVB's 7.1 s late;
  - the orbit 100.0 × 100.0 nmi at 32.508°, 0.003° from the flown plane;
  - Mach 1 and the maximum dynamic pressure near the report's, and the
    tilt at its flown 12.11 s;
  - the CMC in P11, the countdown's start sequence and thrust OK, and
    panel 1's lights through each stage;
  - the S-IVB left with 71,271 kg for TLI (72,727 flown), and TLI at
    2:50:15, 3,048 m/s in 313.6 s (2:50:37, 3,040 m/s in 318.4 s flown)
- Apollo 10 (`tests/scenarios/test_apollo_10.gd`), slice 7b's check. It
  flies from its data alone, from the parking orbit to the splashdown:
  TLI, the evasive maneuver, MCC-1 and MCC-4, LOI-1 and LOI-2; then
  Snoopy's undocking, Charlie Brown's separation, Snoopy's first P52 on
  the AOT (slice 11a), DOI, the low pass over site 2, the phasing burn on
  the PAD's throttle schedule, staging in orbit and the insertion on the
  ascent engine; a P52, P20, CSI, CDH, TPI and the midcourse corrections,
  braking and docking; then LM JETT, TEI, the transearth corrections, a
  P52 and the entry on P61 to P67. Each row of Apollo 10's Fidelity
  table (above) is held within limits of the flight's figures, and
  CAPCOM's calls come at their times
- Apollo 12 (`tests/scenarios/test_apollo_12.gd`), slice 7c's check. It
  flies from its data alone, from the parking orbit to the splashdown:
  TLI onto the free return, MCC-2 onto the hybrid, MCC-4, LOI-1 and
  LOI-2; Intrepid's undocking, Yankee Clipper's separation, the crew's
  P52 on Capella and Rigel, DOI and powered descent, with the ground's
  noun 69 keyed in, V57, the redesignation in P64 and P66 from 400 ft to
  where Intrepid came down, within 250 m of Surveyor III; the first plane
  change, the P57 before the liftoff, P12's liftoff, the P52 after the
  insertion and the rendezvous; LM JETT, the second plane change, TEI,
  the transearth corrections, a P52 and the entry on P61 to P67. Each
  row of Apollo 12's Fidelity table (above) is held within limits of the
  flight's figures
- Apollo 13 (`tests/scenarios/test_apollo_13.gd`), slice 7d's check. It
  flies from its data alone, from five minutes before the oxygen tank
  failed to the splashdown: the failure and the power-down, Aquarius
  powered up and coarse aligned to the CM's platform, the CSM dark; the
  free return and PC+2 on the descent engine, P40 flying the docked
  stack, PC+2 missing the atmosphere with the flight's platform error;
  MCC-5 by hand on the AGS; the LM charging the entry batteries; the
  PGNS again for MCC-7 on the LM's jets; SM SEP, the CM's power-up and
  alignment, LM JETT and the entry on P61 to P67. Each row of Apollo 13's
  Fidelity table (above) is held within limits of the flight's figures
- Apollo 14 (`tests/scenarios/test_apollo_14.gd` and
  `test_apollo_14_return.gd`), slice 12a's check. It flies from its data
  alone, from the parking orbit to the landing at Fra Mauro: TLI, MCC-2
  onto the hybrid, LOI into the plane over the site, DOI by Kitty Hawk
  with Antares docked, the undocking and CIRC, Antares's P52 after it,
  and powered descent with noun 69, Houston's workaround for the ABORT
  switch keyed at the flown times and the landing radar's breaker cycled
  at Houston's call, P66 flown from 360 ft to the spot
  Antares came down on; then from the surface to the splashdown: Kitty
  Hawk's plane change, the P57 before the liftoff, the direct
  rendezvous's liftoff, tweak and TPI on the ascent engine, docking, LM
  JETT, TEI, MCC-5 and the entry on P61 to P67. Each row of Apollo 14's
  Fidelity table (above) is held within limits of the flight's figures
- Apollo 14's ABORT switch (`tests/scenarios/test_apollo_14_abort_switch.gd`),
  slice 12a: from the lunar_descent start, the switch shorted at the
  flown times on the way and taken up tapped clear. Channel 30 on
  V11N10 shows the short, its last digit even, and a tap on the panel,
  or the pushbutton's press, clears it. After the throttle-up the short
  starts P70, the descent engine at full thrust. With the workaround
  keyed as flown, ZOOM passes by at 26 s (10 %, the attitude held), the
  commander's throttle-up goes over AUTO, and after it neither the short
  nor ABORT itself stops P63
- Apollo 14's landing radar (`tests/scenarios/test_apollo_14_landing_radar.gd`),
  slice 12a: from the lunar_descent start, the range scale low 4 min
  52 s before PDI; with the breaker left in at Houston's call, ALT and
  VEL are still on at 10,000 ft, where the mission rules called an abort
- Apollo 14's transposition and docking
  (`tests/scenarios/test_apollo_14_docking.gd`), slice 12a: from the
  parking orbit, TLI and the crew's CSM/LV SEP at the flown time, Antares
  left on the S-IVB. The crew (`tests/tde_crew.gd`) turn about and fly
  four of the six attempts at the flown times and closing speeds, the
  capture latches failed; on the last they hold +X with the probe in the
  drogue and retract it 6.9 s after the contact, and the ring latches
  fire 11.8 s after it, as the flight's did. Houston's calls come at the
  flown times after the separation
- Apollo 15's launch (`tests/scenarios/test_apollo_15_launch.gd`), slice
  12b's check. From LC-39A, AS-510 flies Apollo 15 on time into its
  90 nmi parking orbit on the 80.088° azimuth, and the flight goes on
  through TLI as the parking-orbit start flies it:
  - each of the S-IC's and S-II's cutoffs within 0.6 s of the flight
    evaluation report's, and the S-IVB's 2.7 s late; the velocities
    within 11 m/s and the flight path angles within 1°;
  - Houston's marks of the abort modes at the flown times, One Bravo at
    0:42 to mode IV at 9:15;
  - the orbit 90.7 × 90.6 nmi at 29.679°, 0.003° from the flown plane,
    and the S-IVB's propellant, 75,445 kg, within 2 t of the
    parking-orbit start's;
  - TLI at 2:50:02 for 350.8 s, onto a trajectory past the Moon 139.2 nmi
    up at 78:31:23, not a free return.
- Apollo 15 (`tests/scenarios/test_apollo_15.gd`,
  `test_apollo_15_return.gd` and `test_apollo_15_entry.gd`), slice 12b's
  check. It flies from its data alone, from the parking orbit to the
  landing at Hadley: TLI, the SPS's test as MCC-2, MCC-4, LOI into the
  plane over the site, DOI by Endeavour with Falcon docked, the undocking
  25 min late and CIRC, Falcon's P52 after it, and powered descent on
  Luminary 210's targets, 25° steep past the Apennine front, with noun 69,
  the landing radar's ΔH through the LGC's terrain model, the
  commander's redesignations in P64 and P66 from 400 ft to the spot
  Falcon came down on; from the surface to TEI: Endeavour's plane change,
  the P57 before the liftoff, the direct rendezvous with no tweak, TPI on
  the ascent engine, docking, LM JETT, the shaping burn and TEI; and from
  the transearth coast home: Worden's EVA, the cabin vented at the flown
  times, MCC-7, the entry PAD and the entry on P61 to P67, one of the
  mains failed 99 s after they came out and the CM down on two at their
  rate. Each row of Apollo 15's Fidelity table (above) is held within
  limits of the flight's figures

`tools/screenshot.tscn` renders the images above (`--view=0` window,
`1` chase, `2` cabin; `--hud=0` leaves the HUD out, `--menu=1` shows the
wrist menu, `--pad=<kind>` asks Mission Control for a PAD first, and
`--undock=<s>` undocks the LM and lets it drift for that many seconds,
`--vehicle=csm` or `lm` chooses whose view it is while Eagle flies free,
`--optics=<code>` opens the optics on a navigation star, `--seat=LEB`
puts the cabin view at the lower equipment bay, `--p52=<hours>`
drifts that long and starts P52 with the optics open, and `--p23=<code>`
flies P23 to a star, 0 for the first near the Earth's horizon, and lays
it on the horizon, and `--coast=<s>` flies on that long first, as from
the pad into the ascent).
They were rendered in software, so the frame time on the wrist menu's top
line is the software renderer's:

```
godot --path . tools/screenshot.tscn -- --phase=lunar_orbit --view=1 --out=res://docs/images/x.png
godot --path . tools/screenshot.tscn -- --phase=launch --view=1 --coast=36 --yaw=2.4 --pitch=0.18 --out=res://docs/images/launch_chase.png
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
realism. In the flight's remaining simplifications (milestone 5), the
Earth is oblate and the Sun pulls (slice 5a), and the Moon has its
mascons, which the onboard computers model as their flown R-2 did, so
their state vectors drift from truth in lunar orbit (slice 5b), and the
S-IVB flies TLI on the IU's iterative guidance (slice 5c), the Saturn V
flies Apollo 11 from the pad into its parking orbit (slice 5d), the
CMC's P40 and P41 steer as Colossus's did (slice 5e), and the CMC flies
the entry down on Apollo 11's target on Colossus's P61 to P67 (slice
5f). That finishes the whole flight. The cabin has its sound (slice 6a),
which waits on a listening pass. Of the other missions (milestone 7),
Apollo 8 flies from its data alone (slice 7a): the CSM without an LM,
from its parking orbit through ten lunar orbits to its splashdown. So
does Apollo 10 (slice 7b): Snoopy down to 8 nmi over the first
landing's site, staged in orbit, and back to Charlie Brown by the
landing mission's rendezvous. So does Apollo 12 (slice 7c): Intrepid
lands beside Surveyor III, its landing site moved in powered descent by
the ground's noun 69, and its commander redesignating onto the crater.
And Apollo 13 (slice 7d) comes home after its oxygen tank failed, from
five minutes before the failure to its splashdown, Aquarius its lifeboat.
That finishes the other missions. A way in (milestone 8): the flight
menu picks any mission and start phase, on the desktop and on the wrist,
and starts it in place of the flight flown (slice 8a), and saves flights
and resumes them, the settings kept between sessions (slice 8b); CI
builds the PC VR presets and flies the Linux build before it keeps them
(slice 8c), and builds a Quest 3 APK, whose pass on the headset is still
to be run (slice 8d). Of failures, backups and aborts (milestone 9), the
failures are a catalog, armed by a mission or failed by an instructor,
each lighting its caution and opening its malfunction procedure (slice
9a), and Apollo 11's landing brings its 1202 and 1201 alarms, from the
LGC's Executive and the rendezvous radar's switch as its crew had it
(slice 9b). With the CMC failed, the SCS and the EMS fly a burn to the
PAD, and the EMS monitors the entry (slice 9c). The launch aborts in
each of its four modes, on the EDS, the escape tower and the SPS, set
off by the catalog's failures (slice 9d). Eagle aborts from P63 on the
descent engine and from P66 at 500 ft on the ascent engine, into orbits
phased for the rendezvous, which docks, and has its own failures and
caution and warning lights (slice 9e). Of every mission from the pad
(milestone 10), Apollo 8 flies from the pad on AS-503, the first crewed
Saturn V, into its parking orbit and on through TLI (slice 10a),
Apollo 10 from LC-39B on AS-505 (slice 10b), and Apollo 12 on AS-507
through its lightning: the fuel cells off their buses, SCE to AUX, the
platform tumbled and aligned again with P51 in the parking orbit (slice
10c), and Apollo 13 on AS-508 on four S-II engines after pogo shut the
fifth down, the IU's guidance burning them and the S-IVB longer into its
parking orbit (slice 10d). That finishes every mission from the pad. Of
the LM's navigation (milestone 11), the LGC's platform is a real one,
drifting at Eagle's measured rates, and P52 realigns it on the stars
through the alignment optical telescope, as Armstrong's after undocking
did (slice 11a). P57 aligns it on the Moon, from gravity and the AOT's
stars, as Apollo 11's crew did before the liftoff (slice 11b), and the
LGC steers its burns and turns the LM as Luminary did (slice 11c). The
rendezvous radar has the flight's noise and biases, its gimbals'
coverage and a lock-on by hand, and P20 is Luminary's, its filter
weighing each mark in and learning the radar's boresight biases, flown
by the G mission's procedures (slice 11d). The AGS flies FP6, its own
navigation from the LGC's V47 downlist, its abort insertion and its
CSI, CDH and TPI solutions, keyed on the DEDA (slice 11e). That finishes
the LM's navigation. Of Apollo 14 to 17 (milestone 12), Apollo 14 flies
from its data alone (slice 12a): AS-509 from the pad, DOI by Kitty Hawk
with Antares docked, the landing at Fra Mauro, and the first direct
rendezvous, TPI on the ascent engine in the first revolution. Its
troubles come with it: the ABORT switch's short and Houston's workaround
keyed on the DSKY, the landing radar's low scale and its breaker's
cycle, and the transposition and docking's six attempts, the capture
latches failed, the probe retracted into the ring latches at the last.
Apollo 15 flies from its data too (slice 12b): AS-510 into its 90 nmi
parking orbit, the J mission's LM three days at Hadley, its descent 25°
steep past the Apennine front on Luminary 210's targets and the LGC's
terrain model, Endeavour's plane change and its orbit shaped for the
subsatellite, and the way home: Worden's EVA, the cabin vented, and the
splashdown on two main parachutes, the third failed.

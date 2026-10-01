# Listening pass

Slice 6a's check that a test can't make ([ROADMAP.md](ROADMAP.md),
milestone 6): someone listens to the audio director's voices
(`src/presentation/audio_director.gd`), on the desktop and in a headset.
`tests/unit/test_audio_director.gd` checks the rest:
- that the Bus's events start and stop each voice;
- that each voice is heard in its own cabin;
- that each renders as its recipe says (the master alarm's tone included).

Fill in the tables below, on the desktop and then in a headset, and paste
them into the pull request or issue. About forty minutes for both.

Every voice is synthesised and nothing is recorded, so all but the master
alarm's tone are estimates. The pass is where they get judged. Note
anything that sounds wrong, too loud or too quiet against the rest. The
recipes and levels are in `ONE_SHOTS`, `LAYERS` and `gains()` at the top
of the director.

## Before you start

- Godot **4.4.1**, as for the tests.
- Headphones, or speakers that play bass. The engines sit between 30 and
  300 Hz, below what most laptop speakers play.
- For the headset, set up as in [HEADSET_RUN.md](HEADSET_RUN.md). Make
  the headset's audio the system's default output. SteamVR and the Meta
  Quest Link app can do this for you.
- Set the system volume, then use SOUND - and SOUND + on the wrist
  menu to adjust the simulator. Each press changes it by
  3 dB, from -30 dB to the designed level (0 dB); the setting is saved.

## 1. The voices on their own

Render every voice to a WAV file, then play each one:

```
godot --headless --path . -s tools/render_voices.gd
```

The tool prints where it put them: a `voices` folder in Godot's user data
for the project, unless `-- --out=<folder>` names another outside the
project. `all.wav` has them all in turn, a second apart, in this order.
Each continuous voice's file is its loop played three times: listen for a
click or a jump where it repeats (every 3 s, 2 s for the fans and jets,
5 s for the breathing, 0.8 s for the alarm).

| # | File | What it is | Listen for | Pass? | Notes |
|---|---|---|---|---|---|
| V1 | `click.wav` | A toggle switch's lever | A crisp, short click | | |
| V2 | `rotary.wav` | A rotary switch's detent | A duller click | | |
| V3 | `button.wav` | A pushbutton going in | A soft press | | |
| V4 | `key.wav` | A DSKY key | The lightest click | | |
| V5 | `thump.wav` | An attitude jet starting | A dull thump | | |
| V6 | `pyro.wav` | A separation or jettison | A sharp bang | | |
| V7 | `latch.wav` | Docking latches | A metallic clack | | |
| V8 | `mortar.wav` | A parachute's mortar | A deep boom | | |
| V9 | `shock.wav` | Eagle's touchdown, the Saturn V's release | A heavy thud | | |
| V10 | `splash.wav` | The splashdown | A long, rushing crash | | |
| V11 | `saturn.wav` | The S-IC and S-II | A deep, rough roar | | |
| V12 | `sivb.wav` | The S-IVB's J-2 | A smoother, steadier roar | | |
| V13 | `sps.wav` | The SPS | A deep, smooth rumble | | |
| V14 | `dps.wav` | Eagle's descent engine | A low roar | | |
| V15 | `aps.wav` | Eagle's ascent engine | Brighter and rougher than the descent engine | | |
| V16 | `jets.wav` | Attitude jets firing on | A hiss | | |
| V17 | `rumble.wav` | The air, in the launch and the entry | A wind's roar | | |
| V18 | `fan.wav` | The cabin fans | A steady hum | | |
| V19 | `breath.wav` | Breathing hard, above 3.5 g | Slow breaths | | |
| V20 | `alarm.wav` | The master alarm | 750 Hz and 2,000 Hz in turn, changing 2.5 times a second (the Operations Handbook's tone) | | |

## 2. In flight

Start each check with `godot --path . -- --phase=<phase>`. In a headset,
put `--xr-mode on` before the `--`. The voices are the same in every view
and on both rigs. A voice plays only in its own vehicle's cabin, except
while the two are docked, when both vehicles' voices are heard. `]` and
`[` change the time rate between events, and the voices go on at any rate.

| # | Start | Do | Listen for | Desktop | Headset | Notes |
|---|---|---|---|---|---|---|
| F1 | `lunar_orbit` | Nothing | The fans' hum under everything | | | |
| F2 | `lunar_orbit` | Throw CMC MODE, turn ATT SOURCE, press MASTER ALARM (MDC-1) | A click at each throw, a duller one at each detent, a press as the button goes in and nothing as it comes out | | | |
| F3 | `lunar_orbit` | Type `V16N62E` on the DSKY | Seven key clicks | | | |
| F4 | `lunar_orbit` | CMC MODE to FREE, hold a pitch (W or S, or the right stick), let go, back to HOLD | A thump as the jets start and a hiss while they fire. The DAP's pulses in HOLD thump now and then | | | |
| F5 | `lunar_orbit` | Arm DELTA-V THRUST A (MDC-1) and hold T, the keyboard's SPS THRUST ON, for a few seconds | The SPS's roar coming up at ignition and falling away as you let go | | | |
| F6 | `launch` | Watch it fly, speeding up between the events | From T−9 s the S-IC's roar builds; a thud at liftoff; the air's rumble rising to max-Q at 1:18 and fading. A bang at staging (2:42), the S-II's smoother sound, and bangs at the interstage's (3:12) and the tower's (3:18) jettisons. A bang at the S-II's separation (9:09) and the S-IVB's quieter J-2; at insertion (11:51) only the fans | | | |
| F7 | `parking_orbit` | Let TLI fly at its TIG (2:44), then press CSM/LV SEP | The J-2 for six minutes, then a bang | | | |
| F8 | `lunar_orbit` | Press UNDOCK | The latches, and then the player is in Eagle, with its fans' hum | | | |
| F9 | `lunar_descent` | Fly the descent (its checklist) to touchdown | The descent engine low at 10 % and fuller at the throttle-up; Eagle's jets; a thud at touchdown | | | |
| F10 | `lunar_descent` | With Eagle flying, press L to go to Columbia and back | Eagle's engine and jets heard only in Eagle | | | |
| F11 | `lunar_ascent` | Fly the ascent (its checklist): ABORT STAGE, then the ascent engine | A bang at staging, then the ascent engine, rougher than the descent engine | | | |
| F12 | `entry` | Fly the entry (its checklist) to splashdown | A bang at CM/SM SEP; the air's rumble from entry interface, loudest at the peak loads, with breathing above 3.5 g; a mortar at the drogues and again at the mains; the splash | | | |
| F13 | `translunar_coast`, as `-- --phase=translunar_coast --o2-failure-in=30` | Wait two minutes; press MASTER ALARM; wait another minute | The master alarm's tone as FC 1's light comes on (the MASTER ALARM lights on MDC-1 and MDC-3 with it). The press stops it, and FC 3's light sounds it again | | | |
| F14 | Any | P to pause, P again; F5, then F9 | The voices hush while paused and come back. The checkpoint's load makes no sound | | | |

## Record

| Field | Value |
|---|---|
| Commit | |
| Desktop: OS, audio device | |
| Headset, runtime, audio device | |
| Date, listener | |

# Quest 3 standalone

Slice 8d of `ROADMAP.md`: the simulator on a Meta Quest 3 by itself, with
no PC. Adapted from gemini-capsule's `docs/QUEST_STANDALONE_EXPORT.md`.
CI builds the APK. The headset pass at the end of this page is still to
be run: until it has been, the standalone headset is prepared but not
verified.

## The export preset

`Quest 3 Standalone` in `export_presets.cfg` is deliberately narrow:

- Android, Gradle build, APK, ARM64 only;
- OpenXR, with the Meta OpenXR Vendors plugin as the only loader;
- Quest 3 only (Quest 1, 2 and Pro are off for this target);
- no hand tracking and no passthrough: the cabins are worked with the
  controllers, as on a PC;
- `--xr-mode on` among its command-line arguments, so OpenXR starts on
  the headset as it does on a PC run with that flag, while the project
  keeps OpenXR off for desktop runs;
- the Compatibility renderer (`gl_compatibility`), which
  `project.godot` sets for mobile, where a PC uses Forward+;
- the Meta plugin's starting color space at REC709
  (`xr/openxr/extensions/meta/color_space/starting_color_space` in
  `project.godot`), which its export requires. Without the plugin, a
  desktop run ignores the setting.

## Getting the APK

CI's `quest` job builds a debug APK on every push. A push to `main`
keeps it as the run's `ApolloVR-quest3` artifact, and a tag's release
has it attached. With the Quest in developer mode and plugged in:

```
adb install -r ApolloVR-quest3-debug.apk
```

It appears as *Apollo VR* under *Unknown sources* in the app library.
It opens on the flight menu, on your left wrist (`README.md`, Running).

## Building it yourself

Install JDK 17 and the Android SDK packages Godot 4.4 builds with:

```text
platform-tools
build-tools;34.0.0
platforms;android-34
cmdline-tools;latest
cmake;3.10.2.4988404
ndk;23.2.8568313
```

Then:

- Install Godot 4.4.1's export templates (*Editor → Manage Export
  Templates*).
- Install **Godot OpenXR Vendors 4.3.1-stable** under
  `addons/godotopenxrvendors`, copied from `asset/addons/godotopenxrvendors`
  in the release's `godotopenxrvendorsaddon.zip`. The v4 plugin line
  supports Godot 4.4; v5 needs Godot 4.6 or newer.

The addon and the `android/` directory the export makes are build-time
dependencies, not committed (`.gitignore`). Then:

```bash
godot --headless --path . --import
godot --headless --path . \
  --install-android-build-template \
  --export-debug "Quest 3 Standalone" build/android-quest/ApolloVR.apk
```

A release APK takes the editor's signing workflow; CI builds only a debug
one.

## What CI checks, and what it can't

The `quest` job:

- draws Columbia's cabin, the chase view in lunar orbit and the Moon from
  Eagle's descent orbit with the Compatibility renderer on software GL. A
  shader that doesn't compile for the headset's renderer fails the job,
  and the pictures are kept as the run's `compatibility-renders`
  artifact;
- builds the APK: the preset's options, the Gradle template, the OpenXR
  Vendors plugin and Android's compile, link and package steps.

It can't tell whether the frames keep up on the headset. The procedural
Earth, Moon and sky and the lunar terrain have never been timed on a
mobile GPU. They are cut to the headset's budget only where the pass
below finds them over it.

## The headset pass

Rows Q1 to Q4 in `VR_ACCEPTANCE.md`. The headset recorder writes them
with the others (`HEADSET_RUN.md`), timing the frames by where they were
drawn.

1. **Q1.** Install CI's APK and start it with no PC connected. The
   flight menu is on your left wrist.
2. **Q2.** Choose Apollo 11 and LUNAR ORBIT and START. Stay in
   Columbia's cabin for five minutes at 1x, looking out of the windows at
   the Moon and the Earth as well as at the panels.
3. **Q3.** From the flight menu, choose LUNAR DESCENT and START. Fly
   Eagle's descent orbit for five minutes, looking at the terrain out of
   the commander's window.
4. **Q4.** Compare the Earth, the Moon, the sky and the terrain with a
   PC run (or `docs/images/`).
5. Quit from the headset's menu, which ends the session: the recorder
   writes its files then. They are in the app's own storage, which a
   debug APK lets `adb` read:

   ```
   adb shell run-as com.scomofo.apollocsmsim ls files/vr_acceptance
   adb exec-out run-as com.scomofo.apollocsmsim cat files/vr_acceptance/<name>.md > quest_run.md
   ```

   Paste the table into the pull request or issue, and fill in the Pass
   column.

Q2 and Q3 count as within the budget when no more than 1 % of the frames
drawn there took over 1.5 times the headset's frame time (13.9 ms at
72 Hz, 11.1 ms at 90 Hz). Where one misses it, the pass's numbers say
which view to cut first.

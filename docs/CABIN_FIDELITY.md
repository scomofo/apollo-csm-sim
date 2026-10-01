# Cabin interior fidelity

## Window surrounds, October 2026

The CM's previous window retainers used straight bars at the radius of
each opening's centre. Over the length of a rendezvous opening the
estimated shell radius changes by 18.4 cm, so the bars floated away from
one end and disappeared into the wall at the other.

The surrounds now use the same axial and angular coordinates as the
shell openings. Continuous bands form a dark gasket, a bevelled metal
retainer and a recessed black liner. Twelve small slotted fasteners per
window follow the local shell normal. Their heads and slots are batched;
each window still has eight rendered surfaces, as the old eight bars did.
These are static presentation meshes without control collision shapes.

![CM window surrounds and retained cockpit controls](images/cabin_window_detail.png)

### Reference and estimates

[NASA TN D-6721, Apollo Experience Report: Window Contamination](https://ntrs.nasa.gov/citations/19720012257)
(March 1972), printed pages 3-4, figures 1-6, describes the five CM
window assemblies, their inner pressure-vessel panes and outer heat-shield
panes. Its sections show separate frames and a recessed viewing path.
Page 4 describes aluminium frames and black silicone covering visible
insulation to reduce glare. Those construction features guide this pass.

The 55 mm radial recess, 34 mm surround, 7 mm screw heads, screw count,
spacing, colours and roughness are **estimates**. The existing aperture
locations and sizes have not changed. The surrounds follow the simulator's
cone; real pressure panes are planar. Rectangular openings remain a
**[simplified]** approximation, including the rendezvous windows. No glass
surface, refraction, optical coating, dirt or mission-specific window
contamination has been added. This is a correction to the existing
blockout, not a dimensioned reconstruction of a particular flown cabin.

### Verification and capture

`test_cockpit_layout.gd` checks the actual mesh's distance from the shell
and ray intersections through and around every
opening, including the left-side window across the angular seam. Existing
tests check the five shell apertures, all control click targets, Bus
bindings, DSKYs and seat anchors. The main-scene tests cover cabin setup.
With a real renderer the window test also checks all 60 fastener
orientations. Godot 4.4's dummy renderer returns identity for MultiMesh
transform reads, so those assertions are skipped headless; run the window
tests with `--rendering-method gl_compatibility` and without `--headless`
to exercise them.

The screenshot is a Godot 4.4.1 Compatibility render at 1600 x 900, from
the commander's station in lunar orbit:

```sh
godot --path . --rendering-method gl_compatibility --resolution 1600x900 tools/screenshot.tscn -- --phase=lunar_orbit --view=2 --hud=0 --pitch=0.55 --yaw=-0.16 --zoom=1.65 --out=res://docs/images/cabin_window_detail.png
```

The screenshot tool's optional `--zoom` uses the existing desktop
inspection magnification. It does not change the gameplay camera's
default FOV or headset settings. Desktop render checks are separate from
the pending human headset and Quest performance acceptance passes.

## Lower equipment bay

Selecting LEB previously turned the navigator toward body +Z while its
panel still faced the couches along -X, leaving it above the initial
view. Panel LEB122 now uses the station's existing LEB basis and sits
48 cm ahead of its unchanged eye point. Its optics, second DSKY, switches
and labels face the navigator upright. A short-range task light illuminates
the panel. The panel centre and lighting remain **estimated**, not a
transcription of flown dimensions.

![Navigation panel from the lower equipment bay station](images/cabin_navigation_station.png)

The station test checks the panel's direction, upright orientation and
reach; the existing desktop test clicks every LEB control from that
station. Capture with the same screenshot command, replacing the pitch,
yaw and zoom arguments with `--seat=LEB`.

## Next interior passes

1. Transcribe the window planes and outlines from dimensioned drawings,
   distinguishing inner pressure frames from outer rendezvous recesses.
2. Replace the couch slabs with sourced tubular frames and restraint
   details while keeping crew eyes and control reach fixed.
3. Develop the console's stepped structure and equipment-bay enclosures
   around the existing functional controls, checking labels and reach.

Each pass should retain its references, state estimated dimensions, and
include a fresh visual check alongside the relevant interaction tests.

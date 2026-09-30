## LM Guidance Computer (LGC) with its DSKY: the Luminary programs for the
## LM's burns in lunar orbit and its landing, on the AGC core the CMC
## shares (src/systems/agc_core.gd). It navigates on its own state vector
## (below) and writes its own channels: lm.guid.* and lm.dsky.*.
##
##   P00  LGC idling
##   P12  Powered ascent, from the surface: V06N33 the liftoff time (the
##        ground's ascent PAD), V06N76 the insertion targets and the LM's
##        distance from the CSM's plane, V16N74 the countdown, and V99N74
##        at TIG-5 s: the crew stage (ABORT STAGE), arm the ascent engine
##        and PRO. At TIG the APS lifts the LM in a vertical rise to
##        40 ft/s up while it yaws to face along the CSM's plane, pitches
##        over, and flies ascent guidance (AscentGuidance) to insertion
##        into a 9 x 45 nmi orbit in the CSM's plane; V16N94, then V16N85
##        at cutoff
##   P20  Rendezvous navigation (slice 11d, LgcRendezvousNav): the
##        rendezvous radar acquired and locked on, the LM kept with its +Z
##        on the CSM, and the radar's marks weighted into the LM's state
##        vector (V80) or the CSM's (V81) by Luminary's filter; V16N54
##        range, range rate and the CSM's elevation from the state vectors.
##        It goes on behind P32 to P35 until V56
##   P30  External ΔV (the DOI PAD's TIG and ΔV)
##   P32  CSI: V06N11 its TIG, V06N55 the TPI elevation, V06N37 the TPI
##        time, then the horizontal ΔV that, with CDH half a revolution
##        on, has the CSM at that elevation at that time (Rendezvous); V06N75
##        (ΔH, and the times to CDH and on to TPI) and V06N81, stored for
##        P41
##   P33  CDH: V06N13 its TIG (from P32), the coelliptic ΔV; V06N75, V06N81
##   P34  TPI: V06N55, V06N37 the time the CSM reaches the TPI elevation,
##        and the transfer that meets it after it has flown 130°; V06N58
##        (perilune, ΔV TPI and braking), V06N81
##   P35  Midcourse correction, 5 min ahead, to the same meeting: V06N81
##        Each of P32 to P35 then shows V16N45 (marks, time to ignition,
##        middle gimbal): V32 computes again, PRO is the final computation
##   P40  DPS thrusting, on the burn's throttle schedule, which the ground
##        uplinks with its PAD (Dps.p40_schedule()): Apollo 11's DOI started
##        at 10 % and burned at 40 % after 15 s, Apollo 10's phasing burn
##        at full thrust after 26 s, Apollo 13's PC+2 at 12.6 % for 5 s,
##        40 % for 21 s and then full [simplified: the crew throttled up by
##        hand, as the PAD said]
##   P41  RCS thrusting: +X translation on the LM RCS
##   P42  APS thrusting (the ascent stage, after staging). P40 to P42 steer
##        as Luminary 099's did (slice 11c): the velocity to be gained at
##        TIG, turned through half the burn's arc on Luminary's thrusts
##        (vg_thrust()), drawn down by the sensed ΔV, the thrust steered
##        onto it with the LM's roll left alone, as FINDCDUW steered it
##        (steer_attitude())
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   P52  IMU realign on the alignment optical telescope's marks (slice
##        11a): options 1 to 4 on V04N06, the stars on V01N70 and V01N71,
##        the LGC turning the LM to each, the crew's X and Y marks
##        (V54N71), V06N05 and V06N93, as Luminary 099's (src/systems/
##        lgc_align.gd)
##   P57  Lunar surface alignment (slice 11b): options 3 and 4 on
##        V04N06, the technique on V05N06 (the stored attitude, REFSMMAT
##        and gravity, two stars, gravity and a star), gravity measured
##        in two turns of the platform (V06N04), the stars sighted with
##        the AOT's reticle (R59's detent and V06N79 cursor and spiral),
##        V06N05 and V06N93, as Luminary 099's (src/systems/lgc_p57.gd).
##        Only on the surface
##   P63  Braking: the ignition algorithm finds TIG, 470 km (ground range)
##        before the landing site, then V50N18 auto maneuver, V99 at TIG-5 s,
##        26 s at 10 % throttle holding the attitude, and at ZOOM, with
##        MODREG at 63, Klumpp's quadratic guidance steering at full
##        thrust until the throttle comes back into its range (ZOOMFLAG:
##        without it the guidance neither steers nor throttles; slice
##        12a) [published: Luminary 178's P63ZOOM; Eyles, "Tales from the
##        Lunar Module Guidance Computer", 2004]; V06N63 (the
##        speed, altitude rate and altitude) from ignition, as Luminary
##        099's, and V16N68 (the slant range to the site, the time to go in
##        braking and ΔH) when the crew asks for it. The
##        crew may move the landing site by the ground's correction: V21N69
##        loads its downrange part (R1; V22 R2 crossrange, V23 R3 altitude,
##        V25 all three, ft), which Luminary 1B added to the site at its
##        next guidance cycle and zeroed, as Apollo 12's did 4,200 ft
##        downrange; here the site moves as the load is entered, in P63 or
##        P64
##   P64  Approach, from high gate: the same guidance to the approach
##        target, the throttle in its range; V16N64. With the mode switch
##        in AUTO the ACA redesignates the landing point: each click fore
##        or aft moves it 0.5° along the LPD scale on the commander's
##        window, each click left or right 2° in azimuth. N64 R1 shows the
##        time left to redesignate (first two digits) and the LPD angle,
##        the landing point's angle below the LM's +Z axis (last three)
##   P65  Automatic landing: nulls the horizontal velocity and slows the
##        descent to 0.8 m/s near the surface; V16N60
##   P66  Rate of descent, from P64 or P65 at the first ROD click: the crew
##        flies the attitude, and the throttle holds the descent rate each
##        click moves by 1 ft/s; V16N60
##   P68  Landing confirmation at touchdown: engine off, V06N43
##   P70  DPS abort (slice 9e), from P63 to P66 once the descent engine
##        has lit, at the ABORT pushbutton: the descent engine throttles
##        up to full thrust and P12's guidance flies the LM to insertion
##        (AscentGuidance), its vertical rise ended above 25,000 ft, into
##        an orbit whose apolune phases it for the rendezvous
##        (AscentGuidance.abort_targets(): the TPI the PDI PAD gave,
##        uplinked with it); V16N94, then V16N85 at cutoff [published:
##        Luminary 099's P70-P71, and Bennett, NASA TM X-58040]
##   P71  APS abort, at ABORT STAGE, from P63 to P66 or from P70: staged,
##        the ascent engine flies the same guidance, its targets worked out
##        afresh. Luminary's abort monitor reads the pushbuttons on channel
##        30 while its aborts are enabled (LETABORT, from 0.2 s after P63's
##        ignition to the touchdown or P71), skipping them all with MODREG
##        at 71 and ABORT with it at 70 (slice 12a) [published: Luminary
##        178's P70-P71, routine 10,11; simplified: every step, not every
##        0.25 s, and selected only by the pushbuttons]
##
## The descent's guidance runs in a frame fixed at the landing site (x up,
## y crossrange, z downrange along the ground track), turning with the
## Moon. Its targets are in data/spacecraft.json ("descent_guidance").
##
## Navigation: the LGC flies on its own state vector (nav), never truth.
## Powering up at undocking it takes the CSM's; the ground's uplinks
## replace it (P27, with the PDI PAD: MSFN's tracking error in it). It
## coasts it with its own integration and adds the LM's sensed ΔV
## (lm.dyn.dv_step). Its altitude is above the landing site's radius [it
## has no terrain model, as Apollo 11's LGC had none]. In P63 to P66 it
## reads the landing radar every 2 s: N68 shows ΔH, the radar's altitude
## less its own, and once the crew permits updates (V57) it weights the
## radar's altitude and velocity into its state. The DSKY's ALT and VEL
## lamps light while the radar has no good data. On the surface it holds
## the spot it landed at, turning with the Moon. The ground uplinks the
## CSM's state vector too (csm_nav): P12 flies into its plane, and the
## LGC coasts it for the rendezvous. P20's marks move one or the other
## toward what the rendezvous radar measures (LgcRendezvousNav).
##
## The IMU (slice 11a): a real one, as the CMC's, its gyros drifting at
## rates drawn from the mission's seed (spacecraft.json "lm_imu"). The LGC
## reads its attitude and its sensed ΔV through the platform, and its
## gimbal angles are the platform's against the LM. Undocking, the
## platform is at the landing site REFSMMAT the crew aligned it to docked,
## off by what the flight's first P52 found (the sequencer's); P52 on the
## AOT's stars brings it back.
##
## The LGC runs while the LM's buses are powered (lm.sys.powered, the LM's
## EPS's) and its PGNS breakers are in (ctl.lm.pgns): while the LM flies
## free [simplified: the LM powers up as it undocks], or docked once its
## crew has powered it up, as Apollo 13's did. Docked, it flies the stack:
## its DAP on the stack's inertia, and P30, P40 and P41 on the LM's engine
## and jets. Powered up docked, its IMU is caged until the
## crew coarse aligns it to the CMC's platform (V41N20, the angles the
## CMC's N20 gives turned through the docking geometry, Docking.
## lm_gimbals()) and the ground's REFSMMAT comes up with it; losing its
## power again loses the platform's orientation and the state vector.
## Docked and dark, as after LM JETT, the CSM flies the stack.
##
## The Executive (slice 9b, LgcExecutive): from ignition to touchdown the
## descent's jobs share the LGC's time the interrupts leave: the Servicer
## every 2 s, the landing radar's reading once its altitude is good, P64's
## landing point designator in AUTO, and a noun the crew monitors with
## V16. At the
## descent's peak they take about 90 % of it [published: Apollo 11 Mission
## Report, section 16.2]. With the rendezvous radar's mode switch
## (ctl.lm.rr_mode) at AUTO TRACK or SLEW, Luminary 1A (Apollo 11's,
## rr_cdu_zeroed false) also counts the pulses of the radar's slewing CDUs,
## about 13 % more (interrupt_duty()). Jobs then wait, each holding a core
## set, and a VAC area if it has one, and when the Executive has none to
## give a job it alarms, 1202 (no core sets) or 1201 (no VAC areas), and
## restarts the software: the PROG lamp, the alarm codes in N09 (V05N09),
## the crew's display gone and the program's back, the guidance's commands
## held until the Servicer's next cycle. As on Apollo 11, the crew's
## V16N68 on top of P63 with the radar's data brings 1202s, and P64 1201s.
##
## Digital autopilot: ctl.lm.mode 0 FREE, 1 HOLD, 2 AUTO, as the CMC's,
## with the ACA (ctl.lm.rhc) about the LM's X, Y and Z axes: the LM crew's
## yaw, pitch and roll [simplified: the LM's PGNS MODE CONTROL is OFF,
## ATT HOLD and AUTO]. Powering up, it holds the attitude the LM has. With
## the guidance control switch at AGS (ctl.lm.guid_cont) the AGS flies
## the LM (src/systems/ags.gd) and the DAP follows the attitude.
##
## V47 (slice 11e, LgcR47) is Luminary's AGS initialization, R47: the
## state vectors to the AGS over the downlink (lm.lgc.ags_downlink), and
## the GET of the AEA clock's zero in N16.
##
## The crew reach its erasable memory (slice 12a, LgcErasable): V21N01
## loads a word at an address, V25N07 sets or resets a flagword's bits,
## and V11N10 monitors a channel, all in octal, as Apollo 14's crew keyed
## the workaround for their ABORT switch's short (fail("abort_switch"):
## its contacts to the LGC closed until a tap on the panel beside it or
## the pushbutton's press opens them).
##
## Reads:  the core's, lm.dyn.landed, ctl.lm.panel_tap (a tap on the panel
##         beside ABORT, momentary), ctl.lm.rod (the ROD switch: +1 up,
##         -1 down, momentary), ctl.lm.rr_mode (the rendezvous radar's
##         mode switch: 0 LGC, 1 AUTO TRACK, 2 SLEW), the landing radar's
##         lm.lr.*, the rendezvous radar's lm.rr.*
## Writes: the core's channels under lm. (lm.guid.*, lm.dsky.*),
##         lm.guid.dps_on, lm.guid.dps_throttle, lm.guid.aps_on (P12, P42),
##         lm.guid.lr_antenna (1 in P63, 2 from P64), lm.guid.delta_h_m,
##         lm.lgc.ags_downlink (V47's AGS downlist: the LM's and CSM's
##         state vectors in stable member axes, ft and ft/s; {} when R47
##         isn't sending), lm.guid.r47
##         (R47's phase: "", "k", "send", "done"),
##         lm.guid.lr_update (V57 given), lm.guid.ls_corrected (N69 loaded
##         since the site's uplink), lm.guid.rr_nav (P20 running), P20's
##         lm.guid.rr_designating, lm.guid.rr_designate (the radar's shaft
##         and trunnion) and lm.guid.rr_track_enable,
##         lm.guid.exec_load (the Executive's load, a share of the LGC's
##         time), lm.guid.rr_counting (the radar's CDUs counting),
##         lm.guid.restarts (software restarts this flight),
##         lm.guid.restart_get and lm.guid.restart_alarm (the last's GET
##         and alarm), lm.dsky.lamp.alt, lm.dsky.lamp.vel, lm.lgc.abort_bit
##         (channel 30's ABORT bit present, the switch's short's too),
##         lm.lgc.modreg, lm.lgc.letabort and lm.lgc.zoomflag
class_name Lgc
extends AgcCore

## Powered descent's programs, and those that fire the descent engine.
const DESCENT := [63, 64, 65, 66, 68]
const DESCENT_BURN := [63, 64, 65, 66]
## Powered ascent.
const ASCENT := 12
## The aborts from the powered descent: on the descent engine, and on the
## ascent engine after staging.
const ABORTS := [70, 71]
## The rendezvous targeting programs: CSI, CDH, TPI, TPM.
const RENDEZVOUS := [32, 33, 34, 35]
## The DSKY's time registers the rendezvous programs show and load.
const TIME_NOUNS := [11, 13, 37]
## The thrusts (N) Luminary 099's S40.1 turns an External ΔV through half
## the burn's arc on: FDPS, the DPS's 9,817.5 lbf, for the whole burn (its
## start at 10 % left out), and FRCS4, the four +X jets' 400 lbf, for P41
## [published: Luminary 099, CONTROLLED_CONSTANTS; R-567, section 5.3,
## p. 5.3-23]. P42 takes the ascent engine's own.
const FDPS_N := 43670.0
const FRCS4_N := 1779.3
## KALCMANU's rate, rad/s: the crew loads it with V48 (N46 R1's last digit:
## 0.2, 0.5, 2 or 10 °/s), and each of Apollo 11's LM loads had 2 °/s,
## docked, undocked, on the surface and after insertion (the LM Systems
## Activation Checklist, ACT-47 and ACT-66; the Lunar Surface Checklist,
## SUR-58; the Flight Plan, p. 3-90), docked too, where the program notes
## advised no more than 0.5 °/s (Luminary 1A program notes, 1.7.5)
## [published].
const KALCMANU_RATE := 0.0349066
## The nouns the LGC adds, or means otherwise than the CMC does.
const LGC_NOUNS := {
	16: {"name": "AGS CLOCK ZERO", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	22: {"name": "NEW ICDU ANGLES", "c": [["OG", "d2", 1.0], ["IG", "d2", 1.0], ["MG", "d2", 1.0]]},
	43: {"name": "LAT/LONG/ALT", "c": [["LAT", "d2", 1.0], ["LONG", "d2", 1.0], ["ALT", "d1", 1.0 / Dsky.NMI]]},
	60: {"name": "VH/HDOT/H", "c": [["VH", "d1", 1.0 / Dsky.FT], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	63: {"name": "VI/HDOT/H", "c": [["VI", "d1", 1.0 / Dsky.FT], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	64: {"name": "TR LPD/HDOT/H", "c": [["TR LPD", "i", 1.0], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	68: {"name": "RNG/TGO/DH", "c": [["RNG", "d1", 1.0 / Dsky.NMI], ["TGO", "mmss", 1.0], ["DH", "i", 1.0 / Dsky.FT]]},
	69: {"name": "LS CORR", "c": [["DZ", "i", 1.0 / Dsky.FT], ["DY", "i", 1.0 / Dsky.FT], ["DX", "i", 1.0 / Dsky.FT]]},
	74: {"name": "TFI/YAW/PITCH", "c": [["TFI", "mmss", 1.0], ["YAW", "d2", 1.0], ["PITCH", "d2", 1.0]]},
	76: {"name": "VH/HDOT/XRNG", "c": [["VH", "d1", 1.0 / Dsky.FT], ["HDOT", "d1", 1.0 / Dsky.FT], ["XRNG", "d2", 1.0 / Dsky.NMI]]},
	94: {"name": "VG/HDOT/H", "c": [["VG", "d1", 1.0 / Dsky.FT], ["HDOT", "d1", 1.0 / Dsky.FT], ["H", "i", 1.0 / Dsky.FT]]},
	11: {"name": "TIG CSI", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	13: {"name": "TIG CDH", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	37: {"name": "TIG TPI", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	# P20's (LgcRendezvousNav) [published: Luminary 099's noun tables].
	45: {"name": "MARKS/TFI/MGA", "c": [["MARKS", "i", 1.0], ["TFI", "mmss", 1.0], ["MGA", "d2", 1.0]]},
	49: {"name": "DR/DV/SOURCE", "c": [["DR", "d1", 1.0 / Dsky.NMI], ["DV", "d1", 1.0 / Dsky.FT], ["SOURCE", "i", 1.0]]},
	72: {"name": "RR 360-TRUN/SHAFT", "c": [["TRUN", "d2", 1.0], ["SHAFT", "d2", 1.0], ["", "blank", 1.0]]},
	78: {"name": "RR RANGE/RATE", "c": [["R", "d2", 1.0 / Dsky.NMI], ["RDOT", "i", 1.0 / Dsky.FT], ["", "blank", 1.0]]},
	99: {"name": "RMS POS/VEL/BIAS", "c": [["POS", "i", 1.0 / Dsky.FT], ["VEL", "d1", 1.0 / Dsky.FT], ["BIAS", "d3", 1.0]]},
	54: {"name": "R/RDOT/E", "c": [["R", "d2", 1.0 / Dsky.NMI], ["RDOT", "d1", 1.0 / Dsky.FT], ["E", "d2", 1.0]]},
	55: {"name": "N/E/WT", "c": [["N", "i", 1.0], ["E", "d2", 1.0], ["WT", "d2", 1.0]]},
	58: {"name": "HP/DVTPI/DVTPF", "c": [["HP", "d1", 1.0 / Dsky.NMI], ["DVTPI", "d1", 1.0 / Dsky.FT], ["DVTPF", "d1", 1.0 / Dsky.FT]]},
	75: {"name": "DH/DTCDH/DTTPI", "c": [["DH", "d1", 1.0 / Dsky.NMI], ["DTCDH", "mmss", 1.0], ["DTTPI", "mmss", 1.0]]},
	# P52's (LgcAlign) and P57's (LgcSurfaceAlign).
	4: {"name": "ANGLE DIFF", "c": [["ANGLE", "d2", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	5: {"name": "STAR ANGLE DIFF", "c": [["SAD", "d2", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	6: {"name": "OPTION CODE", "c": [["CODE", "o", 1.0], ["OPTION", "o", 1.0], ["FLAGS", "o", 1.0]]},
	25: {"name": "CHECKLIST", "c": [["CODE", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	34: {"name": "TIME OF EVENT", "c": [["HRS", "hms_h", 1.0], ["MIN", "hms_m", 1.0], ["SEC", "hms_s", 1.0]]},
	70: {"name": "AOT DETENT/STAR", "c": [["CODE", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	71: {"name": "AOT DETENT/STAR", "c": [["CODE", "o", 1.0], ["", "blank", 1.0], ["", "blank", 1.0]]},
	79: {"name": "CURSOR/SPIRAL/POS", "c": [["CURSOR", "d2", 1.0], ["SPIRAL", "d2", 1.0], ["POS", "i", 1.0]]},
	89: {"name": "LANDING SITE", "c": [["LAT", "d3", 1.0], ["LONG/2", "d3", 1.0], ["ALT", "d2", 1.0 / Dsky.NMI]]},
	93: {"name": "TORQUING ANGLES", "c": [["X", "d3", 1.0], ["Y", "d3", 1.0], ["Z", "d3", 1.0]]},
	# The machine address nouns (LgcErasable), octal.
	1: {"name": "SPECIFY ADDRESS", "c": [["WORD", "o", 1.0], ["", "blank", 1.0], ["ADDRESS", "o", 1.0]]},
	7: {"name": "FLAG BITS", "c": [["ECADR", "o", 1.0], ["BITS", "o", 1.0], ["SET", "o", 1.0]]},
	10: {"name": "CHANNEL", "c": [["WORD", "o", 1.0], ["", "blank", 1.0], ["CHANNEL", "o", 1.0]]},
}

## The landing site in the Moon-fixed frame (uplinked with the DOI PAD),
## m; zero until then.
var landing_site: Vector3 = Vector3.ZERO
## The guidance frame fixed at the site, its axes (x up, y crossrange,
## z downrange) in the Moon-fixed frame.
var guidance_frame: Basis = Basis.IDENTITY
## Powered descent's ignition, GET s.
var pdi_tig: float = 0.0
## TLAND: the landing's time, GET s, uplinked with the DOI PAD (P52 option
## 4's orientation is the site's at it); 0 until then.
var tland: float = 0.0
## P52 (slice 11a) and P57 (slice 11b).
var align: LgcAlign
var surface: LgcSurfaceAlign
## Time to go to the phase's target, s.
var tgo: float = 0.0
## The DPS throttle the descent commands, a fraction of full thrust.
var descent_throttle: float = 0.1
## P40's throttle schedule for the stored burn (Dps.p40_schedule()),
## uplinked with its PAD.
var p40_schedule: Array = Dps.p40_schedule()
## P66's altitude rate, m/s (negative down).
var rod_cmd: float = 0.0
## Where the LGC has the LM on the surface (Moon-fixed), once landed. (Its
## state vector is the core's nav, null until it powers up.)
var nav_landed_mf: Vector3 = Vector3.ZERO
## V57: the landing radar may update the state vector.
var lr_update: bool = false
## N69 has moved the landing site since the ground uplinked it.
var ls_corrected: bool = false
## The landing radar's altitude less the LGC's, m, at its last reading.
var delta_h: float = 0.0
## The CSM's state vector from the ground, at its own time; null until
## uplinked.
var csm_nav: Trajectory = null
## P12's insertion targets (AscentGuidance.targets(): radius, radial rate,
## horizontal velocity), the radius its altitudes are above (the landing
## site's) and the plane it flies into (the CSM's orbit normal, inertial).
var ascent_targets: Dictionary = {}
var ascent_base: float = 0.0
var ascent_plane: Vector3 = Vector3.ZERO
## The aborts' TPI times from the PDI PAD (GET s): for an abort before
## abort_split_get, and after it; and the one the abort in flight aims at.
## -1 without them.
var abort_tpi_early: float = -1.0
var abort_tpi_late: float = -1.0
var abort_split_get: float = -1.0
var abort_tpi: float = -1.0
## P20 running (slice 11d: p20).
var rr_nav: bool = false
var p20: LgcRendezvousNav
## The AGS's initialization, V47 (slice 11e: LgcR47).
var r47 := LgcR47.new()
## The mode register and the flagwords the crew can load (slice 12a:
## LgcErasable).
var erasable := LgcErasable.new()
## The ABORT pushbutton's contacts to the LGC shorted: Apollo 14's switch,
## metallic contamination in it (fail("abort_switch")) [published: Apollo
## 14 Mission Report, MSC-04112, section 14.2.2].
var abort_short: bool = false
## The rendezvous: CSI, CDH and TPI's TIGs (GET s, N11, N13, N37), the TPI
## elevation and the transfer angle (radians, N55), the meeting TPI aims at
## (GET), and what P32 to P35 last worked out: ΔH (m), the ΔV of TPI and
## of braking (m/s) and the perilune after TPI (m).
var rdv_csi_tig: float = 0.0
var rdv_cdh_tig: float = 0.0
var rdv_tpi_tig: float = 0.0
var rdv_elev: float = 0.0
var rdv_wt: float = 0.0
var rdv_intercept_get: float = 0.0
var rdv_dh: float = 0.0
var rdv_tpi_dv: float = 0.0
var rdv_tpf_dv: float = 0.0
var rdv_hp: float = 0.0
## The Executive, running the powered descent's jobs (LgcExecutive).
var executive := LgcExecutive.new()
## KALCMANU's turn (_plan_via()): from attitude kal_from about the inertial
## axis kal_axis through kal_angle (rad) at kal_rate (rad/s), begun at GET
## kal_t0; none while kal_t0 is negative.
var kal_from: Quaternion = Quaternion.IDENTITY
var kal_axis: Vector3 = Vector3.RIGHT
var kal_angle: float = 0.0
var kal_rate: float = KALCMANU_RATE
var kal_t0: float = -1.0
## Luminary zeroes the rendezvous radar's CDUs while the radar's mode
## switch is away from LGC, as Luminary 1B did from Apollo 12; Apollo 11's
## Luminary 1A counted their pulses (mission.json "lgc").
var rr_cdu_zeroed: bool = true
## Software restarts this flight, the GET of the last and its alarm.
var restarts: int = 0
var restart_get: float = -1.0
var restart_alarm: int = 0
var _lr_timer: float = 0.0
## The ACA's last detent state about Y and Z (-1, 0, +1), for LPD clicks.
var _aca_was: Vector2i = Vector2i.ZERO
var _rod_was: int = 0
var _guide_get: float = -1.0
## The GET of the last step, and until when a restart holds the guidance's
## commands (the Servicer's next cycle).
var _step_get: float = -1.0
var _restart_hold: float = -1.0
var _restoring: bool = false
## The ABORT pushbutton at the last step, and an abort program being
## selected by the pushbuttons (change_program() takes only those).
var _abort_was: bool = false
var _abort_request: bool = false
var _tap_was: bool = false
## When P63's ignition routine sets LETABORT (0.2 s after it) and ZOOM
## comes (the trim's end), GET s; -1 once done.
var _letabort_get: float = -1.0
var _zoom_get: float = -1.0
# What the descent displays show: slant range to the site (m), speed over
# the surface, horizontal and vertical (m/s), footpads' height (m) and the
# landing point's angle from the LM's +Z axis (°).
var _slant := 0.0
var _vh := 0.0
var _hdot := 0.0
var _h := 0.0
var _lpd := 0.0


func _init() -> void:
	super()
	prefix = "lm."
	align = LgcAlign.new(self)
	surface = LgcSurfaceAlign.new(self)
	p20 = LgcRendezvousNav.new(self)
	r47.lgc = self
	erasable.lgc = self
	dsky.nouns = Dsky.NOUNS.merged(LGC_NOUNS, true)
	var r := SpacecraftData.section("rendezvous_guidance")
	rdv_elev = deg_to_rad(float(r["tpi_elevation_deg"]))
	rdv_wt = deg_to_rad(float(r["tpi_transfer_deg"]))
	dsky.lamp_names = Dsky.LAMPS + ["alt", "vel"]
	for l in ["alt", "vel"]:
		dsky.lamps[l] = false


func _ready() -> void:
	super()
	_publish_executive()


func programs() -> Array:
	return [0, ASCENT, 20, 30] + RENDEZVOUS + [40, 41, 42, 47, 52, 57] + DESCENT + ABORTS


## Its IMU is a real one (slice 11a).
func real_imu() -> bool:
	return true


## The auto maneuver refuses a final attitude past 70 deg of middle gimbal
## (alarm 00401) [published: Luminary 099, KALCMANU's LOCKANGL].
func lock_alarm_deg() -> float:
	return 70.0


func thrusting_programs() -> Array:
	return [40, 41, 42]


func engine_thrust(p: int) -> float:
	if p == 41:
		return Rtcc.lm_rcs_x_thrust()
	if _on_aps(p):
		return float(SpacecraftData.section("aps")["thrust_n"])
	return float(SpacecraftData.section("dps")["thrust_n"]) * Dps.throttle_target(throttle())


## The thrust S40.1 takes for program [param p]'s burn: FDPS in P40, FRCS4
## in P41, the ascent engine's in P42.
func vg_thrust(p: int) -> float:
	if p == 41:
		return FRCS4_N
	if _on_aps(p):
		return float(SpacecraftData.section("aps")["thrust_n"])
	return FDPS_N


## FINDCDUW's steering: the thrust axis turned the shortest way onto
## [param dir] from the attitude the steering held last, the LM's roll about
## it left alone, as in P40 and P42 it commanded no change of it [published:
## Luminary 099, FINDCDUW--GUIDAP_INTERFACE; Luminary Memo 27]
## [simplified: the thrust taken along +X, where FINDCDUW put its filtered
## measure of the thrust's direction on the velocity to be gained].
func steer_attitude(dir: Vector3) -> Quaternion:
	var x := Basis(auto_target) * Vector3.RIGHT
	return (Imu.arc(x, dir.normalized()) * auto_target).normalized()


func engine_tau_off(p: int) -> float:
	return float(SpacecraftData.section("aps" if _on_aps(p) else "dps")["tau_off_s"])


## Program [param p] fires the ascent engine.
static func _on_aps(p: int) -> bool:
	return p in [42, ASCENT, 71]


func engine_running() -> bool:
	return bool(Bus.get_value("lm.dps.on", false)) or bool(Bus.get_value("lm.aps.on", false))


func publish_engine(on: bool) -> void:
	Bus.set_value("lm.guid.dps_on", on and (program in [40, 70] or program in DESCENT_BURN))
	Bus.set_value("lm.guid.dps_throttle", throttle())
	Bus.set_value("lm.guid.aps_on", on and _on_aps(program))


## The DPS throttle the LGC commands, a fraction of full thrust: in
## powered descent the guidance's; in P70 full thrust; in P40 the
## schedule's, its start throttle for its first seconds after ignition,
## then its burn throttle.
func throttle() -> float:
	if program in DESCENT_BURN:
		return descent_throttle
	if program == 70:
		return 1.0
	return Dps.schedule_throttle(p40_schedule, _now() - ignition_get if ignition_get >= 0.0 else 0.0)


func mode() -> int:
	return int(Bus.get_value("ctl.lm.mode", 1))


## The guidance control switch: 0 PGNS flies the LM, 1 the AGS does, and
## the DAP follows the attitude.
func att_source() -> int:
	return int(Bus.get_value("ctl.lm.guid_cont", 0))


## The ACA, to the DAP; in P64 with the mode switch in AUTO it
## redesignates the landing point instead.
func rhc() -> Vector3:
	if program == 64 and mode() == 2:
		return Vector3.ZERO
	return Bus.get_value("ctl.lm.rhc", Vector3.ZERO)


func is_powered() -> bool:
	return bool(Bus.get_value("lm.sys.powered", false)) and bool(Bus.get_value("ctl.lm.pgns", true))


## On the surface the LM sits on its gear: its DAP fires no jets.
func dap_enabled() -> bool:
	return not bool(Bus.get_value("lm.dyn.landed", false))


func auto_rate() -> float:
	if program in DESCENT_BURN:
		return deg_to_rad(float(SpacecraftData.section("descent_guidance")["auto_rate_dps"]))
	if program == ASCENT or program in ABORTS:
		return deg_to_rad(float(SpacecraftData.section("ascent_guidance")["auto_rate_dps"]))
	return kalcmanu_rate()


## KALCMANU's rate: the crew's V48 load's (KALCMANU_RATE).
func kalcmanu_rate() -> float:
	return KALCMANU_RATE


## The auto maneuver to auto_target as Luminary 099's KALCMANU flew it (R60,
## ATTITUDE MANEUVER ROUTINE): one turn about a single axis at the rate the
## crew loaded (kalcmanu_rate()), its reference attitude stepped along the
## turn for the DAP to follow at that rate (_maneuver_target(),
## _maneuver_rate()), and at the turn's end the attitude held; a turn under
## 0.25° none. A thrusting program refuses a final attitude past 70° of
## middle gimbal (00401) [published: Luminary 099,
## ATTITUDE_MANEUVER_ROUTINE and KALCMANU_STEERING; R-567, section 3.7.4].
## 099 had no re-planning round gimbal lock (its skirting of the lock zone
## is in the listing but left out: LOCSKIRT EQUALS NOGIMLOC): its crews
## watched the FDAI and turned clear by hand, as Apollo 11's yawed round
## before P63. Where the single axis would take the middle gimbal past
## LOCK_MANEUVER_DEG, the LGC routes the turn as the CMC does instead
## (AgcCore._plan_via()) [adapted: the crew's hand maneuvers, left to it].
func _plan_via() -> void:
	_drop_maneuver()
	var now := _att()
	var d := (auto_target * now.inverse()).normalized()
	if d.w < 0.0:
		d = -d
	var angle := 2.0 * acos(clampf(d.w, 0.0, 1.0))
	if angle < deg_to_rad(0.25):
		return
	var axis := Vector3(d.x, d.y, d.z).normalized()
	var peak := 0.0
	for i in 33:
		var q := (Quaternion(axis, angle * i / 32.0) * now).normalized()
		peak = maxf(peak, absf(wrapf(gimbal_angles_of(q).z, -180.0, 180.0)))
	if peak > LOCK_MANEUVER_DEG:
		super()
		return
	kal_axis = axis
	kal_angle = angle
	kal_from = now
	kal_rate = kalcmanu_rate()
	kal_t0 = _now()


func _drop_maneuver() -> void:
	super()
	kal_t0 = -1.0


## KALCMANU is still turning its reference.
func kal_turning() -> bool:
	return kal_t0 >= 0.0 and _now() < kal_t0 + kal_angle / kal_rate


## KALCMANU's reference attitude now, on its way from kal_from.
func _kal_ref() -> Quaternion:
	return (Quaternion(kal_axis, minf(kal_rate * (_now() - kal_t0), kal_angle)) * kal_from).normalized()


func _maneuver_target() -> Quaternion:
	return _kal_ref() if kal_turning() else super()


## KALCMANU's rate about its axis, in body axes, while it turns.
func _maneuver_rate() -> Vector3:
	if not kal_turning():
		return Vector3.ZERO
	return Basis(_att()).inverse() * (kal_axis * kal_rate)


## The DAP takes up the attitude the LM has as its hold, and the LGC the
## CSM's state vector (sense() takes it once Dynamics has stepped). Docked,
## its IMU is a real one, and caged.
func powered_up() -> void:
	_last_source = -1
	nav = null
	rr_nav = false
	p20.stop()
	if not _free():
		imu.cage(Basis(_true_att()))


## The LM dark at the start, flying with the CSM: its power, whenever it
## comes, is a power-up.
func start_dark() -> void:
	_powered = false


## The platform's orientation and the state vector are lost.
func powered_down() -> void:
	imu.cage(Basis(_true_att()))
	nav = null


func authority() -> Vector3:
	return jet_authority()


## Docked, the LM flies a stack twenty times stiffer in pitch and yaw than
## in roll: about the error's axis.
func slew_about_axis() -> bool:
	return not _free()


## The angular acceleration the LM's jets give about its axes, both
## systems' (rad/s^2); docked, on the stack's inertia (its diagonal the same
## about the LM's axes as about the CSM's) [simplified: the jets' torques
## the LM's own]. The LGC's DAP and the AGS's hold fly on it.
static func jet_authority() -> Vector3:
	var cfg := str(Bus.get_value("lm.dyn.config", "lm"))
	var mass := float(Bus.get_value("lm.dyn.mass_kg", SpacecraftData.lm_mass()))
	if str(Bus.get_value("dock.state", "")) == "docked":
		cfg = str(Bus.get_value("dyn.config", "csm_lm"))
	elif not cfg in SpacecraftData.LM_CONFIGS:
		cfg = "lm"
	var inertia := SpacecraftData.inertia(cfg, mass)
	var d := SpacecraftData.section("lm_rcs")
	# Both systems' jets about each axis.
	var t := float(d["jet_thrust_n"]) * float(d["arm_m"]) * float(d["rotation_jets"]) * 2.0
	return Vector3(t / inertia.x, t / inertia.y, t / inertia.z)


# --- navigation ----------------------------------------------------------------------

## Replace the state vector with the ground's [param tr] (P27, V71): the
## LGC coasts it on from its time.
func uplink_state(tr: Trajectory) -> bool:
	if not super.uplink_state(tr):
		return false
	nav_landed_mf = Vector3.ZERO
	p20.invalidate()
	return true


## Luminary's gravity model: R-2 like Colossus's, with no third bodies.
func nav_model() -> Trajectory.Model:
	return Trajectory.Model.LGC


## Replace the CSM's state vector with the ground's [param tr] (P27). The
## LGC coasts it on from its time, and P20's filter starts again at its
## next mark.
func uplink_csm_state(tr: Trajectory) -> void:
	csm_nav = tr.clone().as_onboard(Trajectory.Model.LGC)
	p20.invalidate()
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


## Load the rendezvous's times from the ground's CSI PAD: CSI's TIG (N11)
## and TPI's (N37).
func uplink_rendezvous(csi_tig: float, tpi_tig: float) -> void:
	rdv_csi_tig = csi_tig
	rdv_tpi_tig = tpi_tig
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


## Load P40's throttle schedule from the ground's PAD for a DPS burn
## ([start_s, start_throttle, throttle]; spacecraft.json's when empty).
func uplink_throttle(schedule: Array) -> void:
	p40_schedule = Dps.p40_schedule(schedule)


## Load the liftoff time from the ground's ascent PAD: P12's TIG (N33).
func uplink_liftoff(tig: float) -> void:
	tig_load = tig
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


## Load the aborts' TPI times from the ground's PDI PAD (GET s): [param early]
## for an abort before [param split], [param late] after it. P70 and P71
## phase the LM's orbit for them (AscentGuidance.abort_targets()) [stands
## in for Luminary's ABTCOF coefficients, erasable loads fitted to them].
func uplink_abort_tpi(early: float, late: float, split: float) -> void:
	abort_tpi_early = early
	abort_tpi_late = late
	abort_split_get = split
	abort_tpi = -1.0


## Stage DEPENDENT: coast the state vector to now with this step's sensed
## ΔV [param dv] (all of it: Average-G always runs while the LM flies free
## [simplified]); on the surface, hold it at the spot it landed at. The
## CSM's state vector coasts along, but in the powered descent and on the
## surface, where it waits for an abort or P12 (_csm_now()).
func _navigate(dv: Vector3) -> void:
	var now := _now()
	var landed := bool(Bus.get_value("lm.dyn.landed", false))
	if csm_nav != null and csm_nav.t < now and not landed and not program in DESCENT:
		csm_nav.coast_to(now)
	if nav == null:
		super._navigate(dv)   # the LM's truth: the CSM's, handed over at undocking
		return
	if bool(Bus.get_value("lm.dyn.landed", false)):
		if nav_landed_mf == Vector3.ZERO:
			nav_landed_mf = Bodies.moon_fixed(nav.t).transposed() * nav.pos()
		var r := Bodies.moon_fixed(now) * nav_landed_mf
		nav.set_state("moon", now, r, Bodies.moon_omega(now).cross(r))
		return
	nav_landed_mf = Vector3.ZERO
	super._navigate(dv)


## Every 2 s in P63 to P66: read the landing radar. ΔH is its altitude
## less the LGC's (above the landing site's radius); with updates
## permitted (V57), the radar's altitude and velocity are weighted into the
## state vector.
func _landing_radar(dt: float) -> void:
	var on := program in DESCENT_BURN and nav != null
	var alt_good := bool(Bus.get_value("lm.lr.alt_good", false))
	var vel_good := bool(Bus.get_value("lm.lr.vel_good", false))
	dsky.set_lamp("alt", on and not alt_good)
	dsky.set_lamp("vel", on and not vel_good)
	if not on:
		_lr_timer = 0.0
		return
	var d := SpacecraftData.section("landing_radar")
	_lr_timer += dt
	if _lr_timer < float(d["update_s"]) - 1e-6:
		return
	_lr_timer = 0.0
	var att := Basis(_att())
	var r := nav.pos()
	var up := r.normalized()
	if alt_good:
		var beam := att * (Bus.get_value("lm.lr.beam_body", Vector3(-1, 0, 0)) as Vector3)
		var h_lr := float(Bus.get_value("lm.lr.range_m", 0.0)) * -beam.dot(up)
		delta_h = h_lr - (nav.radius() - landing_site.length())
		Bus.set_value("lm.guid.delta_h_m", delta_h)
		if lr_update:
			var k := delta_h * float(d["alt_weight"])
			for i in 3:
				nav.s[i] += up[i] * k
	if vel_good and lr_update:
		var v_meas := att * (Bus.get_value("lm.lr.vel_body", Vector3.ZERO) as Vector3) + Bodies.moon_omega(nav.t).cross(r)
		var dv := (v_meas - nav.vel()) * float(d["vel_weight"])
		for i in 3:
			nav.s[3 + i] += dv[i]


## From ignition to touchdown, the powered descent's jobs on the
## Executive: a job it finds no room for alarms, and restarts the
## software (_software_restart()).
func _executive(dt: float, now: float) -> void:
	if program in DESCENT_BURN and engine_on:
		var code := executive.step(dt, now, _descent_jobs(), interrupt_duty())
		if code != 0:
			_software_restart(code, now)
	else:
		executive.stop()
	_publish_executive()


func _publish_executive() -> void:
	Bus.set_value("lm.guid.exec_load", executive.load)
	Bus.set_value("lm.guid.rr_counting", rr_counting())
	Bus.set_value("lm.guid.restarts", restarts)
	Bus.set_value("lm.guid.restart_get", restart_get)
	Bus.set_value("lm.guid.restart_alarm", restart_alarm)


## The jobs the descent's programs schedule now (data/spacecraft.json
## "lgc_executive"): the Servicer, at its program's share; the landing
## radar's reading once its altitude is good; P64's landing point
## designator while the commander can redesignate, the mode control in
## AUTO; and a noun the crew monitors with V16.
func _descent_jobs() -> Dictionary:
	var jobs: Dictionary = SpacecraftData.section("lgc_executive")["jobs"]
	var s: Dictionary = jobs["servicer"]
	var out := {"servicer": s.merged({"duty": float(s["duty_by_program"][str(program)])}, true)}
	if bool(Bus.get_value("lm.lr.alt_good", false)):
		out["landing_radar"] = jobs["landing_radar"]
	if program == 64 and mode() == 2:
		out["lpd"] = jobs["lpd"]
	var n := dsky.crew_monitor()
	if n > 0:
		var m: Dictionary = jobs["monitor"]
		out["monitor"] = m.merged({"duty": float(m["duty_by_noun"].get(str(n), m["duty"]))}, true)
	return out


## The share of the LGC's time its interrupts take: its counters' and timed
## routines', and the rendezvous radar's CDUs' pulses while they count.
func interrupt_duty() -> float:
	var e := SpacecraftData.section("lgc_executive")
	var d := float(e["interrupt_duty"])
	if rr_counting():
		d += float(e["rr_cdu_pps"]) * float(e["counter_pulse_s"])
	return d


## The rendezvous radar's CDUs count into the LGC: with its mode switch
## (ctl.lm.rr_mode) at AUTO TRACK or SLEW, the ATCA's 800 Hz, not in phase
## with the PGNS's, excites its resolvers and the CDUs slew; unless this
## Luminary zeroes them.
func rr_counting() -> bool:
	return not rr_cdu_zeroed and int(Bus.get_value("ctl.lm.rr_mode", 0)) != 0


## The Executive found no room for a job: its alarm (1201 or 1202) and a
## software restart. Whatever the crew had on the DSKY ends and the
## program's display comes back; the guidance carries on from its restart
## point at the Servicer's next cycle.
func _software_restart(code: int, now: float) -> void:
	_alarm(code)
	restarts += 1
	restart_get = now
	restart_alarm = code
	dsky.restart_display()
	_restart_hold = float(executive.next_get.get("servicer", now))


func verb_noun(v: int, n: int) -> bool:
	if program == 52 and ((v == 32 and align.recycle()) or align.enter(v, n)):
		return true
	if program == 57 and ((v == 32 and surface.recycle()) or surface.enter(v, n)):
		return true
	if v == 57:
		# Permit landing radar updates.
		lr_update = true
		return true
	if _r47_verb(v) or _p20_verb(v):
		return true
	if v == 32 and program in RENDEZVOUS and step_name == "n45":
		_recycle_rendezvous()
		return true
	return super.verb_noun(v, n)


## R47's verbs: V47 starts it, and V32 and V34 answer its display.
## Returns whether [param v] was one of them.
func _r47_verb(v: int) -> bool:
	if v == 47:
		return r47.start()
	return v in [32, 34] and r47.answer({32: "v32", 34: "v34"}[v])


## P20's verbs: V67, V80, V81, V93 and V95 (LgcRendezvousNav.verb()); at
## its priority display V32 recycle, V34 terminate and ENTER at a V50; V56
## terminates tracking. Ended, P20 leaves P00. Returns whether [param v]
## was one of them.
func _p20_verb(v: int) -> bool:
	if v in [67, 80, 81, 93, 95] and p20.verb(v):
		return true
	if p20.priority != "" and v in [32, 34, 50]:
		p20.answer({32: "v32", 34: "v34", 50: "enter"}[v])
	elif v == 56:
		p20.stop()
		rr_nav = false
	else:
		return false
	if not p20.running() and program == 20:
		change_program(0)
	return true


func _free() -> bool:
	return str(Bus.get_value("dock.state", "")) == "free"


# --- powered descent ---------------------------------------------------------------

## Load the landing site from the ground (with the DOI PAD), Moon-fixed, m.
func uplink_landing_site(site_mf: Vector3) -> void:
	landing_site = site_mf
	ls_corrected = false
	_uplink_timer = 2.0
	dsky.set_lamp("uplink_acty", true)


## P63 needs the landing site and the LM flying free; P64 to P68 come only
## from the descent itself. P12 needs the LM on the surface and the CSM's
## state vector, P57 the surface; P70 and P71 come only from the abort
## pushbuttons.
func change_program(p: int) -> bool:
	if not _restoring and _refused(p):
		_alarm(1520)
		return false
	if program in thrusting_programs() and p != program and not _restoring:
		# A new program after an Average-G one: P20's marks count again
		# [published: GSOP R-567 section 4, P20's assumption 6].
		p20.marks = 0
	var ok := super.change_program(p)
	if ok:
		erasable.modreg = program
	return ok


## Whether the LGC refuses program [param p] (alarm 1520): P63 without the
## landing site or flying docked; P64 to P68 but from the descent; P12 off
## the surface or without the state vectors; P57 off the surface; P20 and
## P32 to P35 on the surface or without them, and P35 too late for its
## lead; P70 and P71 but from the pushbuttons.
func _refused(p: int) -> bool:
	var landed := bool(Bus.get_value("lm.dyn.landed", false))
	var navs := csm_nav != null and nav != null and _free()
	var lead := float(SpacecraftData.section("rendezvous_guidance")["tpm_lead_s"])
	return (p == 63 and (landing_site == Vector3.ZERO or not _free())) or (p in DESCENT and p != 63) \
		or (p == ASCENT and not (navs and landed)) or (p == 57 and not landed) \
		or ((p == 20 or p in RENDEZVOUS) and not (navs and not landed)) \
		or (p == 35 and rdv_intercept_get <= _now() + lead) or (p in ABORTS and not _abort_request)


func start_program(p: int) -> void:
	if p == 52 and not _restoring:
		align.start()
	if p == 57 and not _restoring:
		surface.start()
	if p == 63 and not _restoring:
		_start_p63()
	if p == ASCENT and not _restoring:
		_start_p12()
	if p in ABORTS and not _restoring:
		_start_abort(p)
	if p == 20:
		rr_nav = true
		dsky.show(16, 54)
		if not _restoring:
			p20.start()
	if p in RENDEZVOUS and not _restoring:
		p20.targeting_started()
		_start_rendezvous(p)


func _start_p63() -> void:
	var tr := current_traj()
	var up := landing_site.normalized()
	# Downrange is along the ground track, as the LM will pass over the site.
	var h := (Bodies.moon_fixed(_now()).transposed() * tr.pos().cross(tr.vel())).normalized()
	var z := h.cross(up).normalized()
	guidance_frame = Basis(up, z.cross(up), z)
	pdi_tig = pdi_time(tr, landing_site, float(SpacecraftData.section("descent_guidance")["pdi_range_m"]))
	step_name = "tig"
	dsky.show(6, 33, true)


## P63's ignition algorithm: the time [param tr] comes within
## [param pdi_range] (ground range) of [param site_mf] (Moon-fixed) on its
## next pass. The ground predicts PDI with it too.
static func pdi_time(tr: Trajectory, site_mf: Vector3, pdi_range: float) -> float:
	var t := tr.clone()
	var rng := func(t2: Trajectory) -> float:
		return t2.pos().angle_to(Bodies.moon_fixed(t2.t) * site_mf) * Bodies.R_MOON
	var box := {"prev": rng.call(t)}
	var within := func(t2: Trajectory) -> bool:
		var r2: float = rng.call(t2)
		var hit: bool = box["prev"] > pdi_range and r2 <= pdi_range
		box["prev"] = r2
		return hit
	t.coast_until(within, t.t + 1.5 * float(t.conic()["period"]), 20.0, 0.002)
	# Back up to the crossing at the ground speed.
	var ground := t.speed() * Bodies.R_MOON / t.radius()
	return t.t - (pdi_range - float(rng.call(t))) / ground


func proceed() -> void:
	if r47.phase != "" or p20.priority != "" or program in RENDEZVOUS:
		# PRO answers R47's display, then P20's priority display.
		if r47.phase != "":
			r47.answer("pro")
		elif p20.priority != "":
			p20.answer("pro")
		else:
			_proceed_rendezvous()
		return
	if program in [52, 57]:
		if program == 52:
			align.proceed()
		else:
			surface.proceed()
		_publish_imu()
		return
	if program in ABORTS:
		if step_name == "post":
			change_program(0)
		return
	if program == ASCENT:
		match step_name:
			"tig":
				step_name = "targets"
				dsky.show(6, 76, true)
			"targets":
				step_name = "wait"
				dsky.show(16, 74)
			"v99":
				engine_enabled = true
				step_name = "ignition"
				dsky.show(16, 94)
			"post":
				change_program(0)
		return
	if program == 63:
		match step_name:
			"tig":
				# Maneuver to thrust against the velocity over the surface at TIG.
				var at := predict(pdi_tig)
				var rel := at.vel() - Bodies.moon_omega(at.t).cross(at.pos())
				auto_target = _descent_attitude(-rel, Bodies.moon_fixed(pdi_tig) * guidance_frame)
				desired_q = auto_target
				step_name = "v50n18"
				dsky.show(50, 18, true)
			"v50n18":
				# KALCMANU's turn from the attitude DOI left [simplified: to
				# the whole ignition attitude, where Luminary's R60 pointed
				# the thrust axis alone (VECPOINT) and Apollo 11's crew had
				# yawed round to windows down by hand first].
				_plan_via()
				step_name = "maneuver"
				auto_active = true
				dsky.show(6, 18)
			"v99":
				engine_enabled = true
				step_name = "ignition"
				dsky.show(6, 63)
		return
	if program == 68:
		change_program(0)
		return
	super.proceed()


func extra_step() -> void:
	# KALCMANU gives up its turn once the mode switch leaves AUTO, or the
	# auto maneuver is off.
	if kal_t0 >= 0.0 and (mode() != 2 or not auto_active):
		kal_t0 = -1.0
	var rod := int(Bus.get_value("ctl.lm.rod", 0))
	var click := rod if rod != 0 and _rod_was == 0 else 0
	_rod_was = rod
	var aca: Vector3 = Bus.get_value("ctl.lm.rhc", Vector3.ZERO)
	var detent := Vector2i(_out_of_detent(aca.y), _out_of_detent(aca.z))
	var lpd_clicks := Vector2i(detent.x if detent.x != _aca_was.x else 0, detent.y if detent.y != _aca_was.y else 0)
	_aca_was = detent
	Bus.set_value("lm.guid.lr_antenna", 2 if program in [64, 65, 66, 68] else 1)
	Bus.set_value("lm.guid.lr_update", lr_update)
	Bus.set_value("lm.guid.ls_corrected", ls_corrected)
	Bus.set_value("lm.guid.rr_nav", rr_nav)
	var now := _now()
	var step_dt := now - _step_get if _step_get >= 0.0 else 0.0
	_step_get = now
	_landing_radar(step_dt if program in DESCENT else 0.0)
	align.step()
	surface.step()
	p20.step()
	r47.tick(_now())
	rr_nav = p20.running()
	_executive(step_dt, now)
	_abort_discretes()
	if program == ASCENT or program in ABORTS:
		_p12_step(now)
		return
	if not program in DESCENT or now < _restart_hold - 1e-6:
		# Restarted: the guidance carries on from its restart point at the
		# Servicer's next cycle, its commands held till then.
		return
	var dt := now - _guide_get if _guide_get >= 0.0 else 0.0
	_guide_get = now
	if program in DESCENT_BURN and bool(Bus.get_value("lm.dyn.landed", false)) and step_name != "tig":
		_descent_phase(68)
		return
	if program == 64 and mode() == 2 and lpd_clicks != Vector2i.ZERO:
		_redesignate(lpd_clicks)
	var st := _descent_state()
	if click != 0 and program in [64, 65, 66]:
		if program != 66:
			rod_cmd = float(st["vg"].x)
			_descent_phase(66)
		rod_cmd += click * float(SpacecraftData.section("descent_guidance")["rod_click_mps"])
	match program:
		63:
			_p63_step(st, now, dt)
		64:
			var d := SpacecraftData.section("descent_guidance")
			descent_throttle = _throttle_for(_steer_to(_klumpp(d["approach"], st, dt), st))
			if tgo <= float(d["approach"]["tend_s"]):
				_descent_phase(65)
		65:
			_p65_step(st)
		66:
			_p66_step(st)


func _p63_step(st: Dictionary, now: float, dt: float) -> void:
	var d := SpacecraftData.section("descent_guidance")
	match step_name:
		"maneuver":
			if _att_error(auto_target) < deg_to_rad(2.0) and _omega().length() < deg_to_rad(0.2):
				step_name = "wait"
				dsky.show(16, 68)
			if now >= pdi_tig - 5.0:
				_tig_minus_5()
		"wait":
			if now >= pdi_tig - 5.0:
				_tig_minus_5()
		"ignition":
			if now >= pdi_tig - 1e-6:
				_drop_maneuver()
				step_name = "braking"
				engine_on = true
				ignition_get = now
				_letabort_get = now + 0.2
				_zoom_get = now + float(d["trim_s"])
				tgo = float(d["braking"]["tgo0_s"])
		"braking":
			if _letabort_get >= 0.0 and now >= _letabort_get - 1e-6:
				# P63IGN: "SET FLAG FOR P70-P71".
				_letabort_get = -1.0
				erasable.letabort = true
			if _zoom_get >= 0.0 and now >= _zoom_get - 1e-6:
				# ZOOM: P63ZOOM's throttle-up and guidance only with MODREG
				# at 63.
				_zoom_get = -1.0
				if erasable.modreg == 63:
					erasable.zoomflag = true
			var acmd := _klumpp(d["braking"], st, dt)
			# Before ZOOMFLAG the attitude holds and the throttle stays at
			# the trim's.
			descent_throttle = _throttle_for(_steer_to(acmd, st)) if erasable.zoomflag else float(d["trim_throttle"])
			if tgo <= float(d["braking"]["tend_s"]):
				_descent_phase(64)
	# Coast landing points before ignition: TIG-60 s, then TIG-5 s.
	var next := -1.0
	if step_name in ["tig", "v50n18", "maneuver", "wait"]:
		next = pdi_tig - 60.0 if now < pdi_tig - 60.0 else pdi_tig - 5.0
	Bus.set_value(_ch("guid.next_event_get_s"), next)


## TIG-5: V99 asks for the go to light the engine, and ZOOMFLAG is reset.
func _tig_minus_5() -> void:
	step_name = "v99"
	erasable.zoomflag = false
	dsky.show(99, 68, true)


## The throttle for a guidance command [param thr]: full thrust above the
## throttleable range, which the command otherwise keeps to.
static func _throttle_for(thr: float) -> float:
	var dps := SpacecraftData.section("dps")
	return 1.0 if thr > float(dps["throttle_max"]) else maxf(thr, float(dps["throttle_min"]))


## P65: null the horizontal velocity and descend at a rate that slows to
## p65_rate_final_mps near the surface. The thrust always points up, and
## the LM tilts no more than 20° to stop.
func _p65_step(st: Dictionary) -> void:
	var d := SpacecraftData.section("descent_guidance")
	var vg: Vector3 = st["vg"]
	var up_g := -(st["gg"] as Vector3).x
	var hdot := -maxf(float(d["p65_rate_final_mps"]), minf(float(d["p65_rate_max_mps"]), float(d["p65_rate_gain"]) * _h))
	var ax := clampf((hdot - vg.x) / float(d["vertical_tau_s"]), -0.6 * up_g, up_g)
	var ah := -Vector3(0.0, vg.y, vg.z) / float(d["horizontal_tau_s"])
	var ah_max := (ax + up_g) * tan(deg_to_rad(20.0))
	if ah.length() > ah_max:
		ah = ah.normalized() * ah_max
	var thr := _steer_to(Vector3(ax, ah.y, ah.z), st)
	var dps := SpacecraftData.section("dps")
	descent_throttle = clampf(thr, float(dps["throttle_min"]), float(dps["throttle_max"]))


## P66: the crew flies the attitude; the throttle holds the altitude rate
## the ROD clicks set.
func _p66_step(st: Dictionary) -> void:
	var d := SpacecraftData.section("descent_guidance")
	var vg: Vector3 = st["vg"]
	var gg: Vector3 = st["gg"]
	var ax := (rod_cmd - vg.x) / float(d["vertical_tau_s"])
	var g: Basis = st["g"]
	var cos_tilt := maxf((Basis(_att()) * Vector3.RIGHT).dot(g.x), 0.5)
	var dps := SpacecraftData.section("dps")
	var thr := (ax - gg.x) * _mass() / (float(dps["thrust_n"]) * cos_tilt)
	descent_throttle = clampf(thr, float(dps["throttle_min"]), float(dps["throttle_max"]))


## Enter a later descent program, the engine running on.
func _descent_phase(p: int) -> void:
	program = p
	step_name = ""
	erasable.modreg = p
	if p == 68:
		# LANDJUNK: the aborts end at the touchdown.
		erasable.letabort = false
	match p:
		64:
			tgo = float(SpacecraftData.section("descent_guidance")["approach"]["tgo0_s"])
			dsky.show(16, 64)
		65:
			dsky.show(16, 60)
		66:
			auto_active = false
			hold_q = _att()
			dsky.show(16, 60)
		68:
			engine_on = false
			engine_enabled = false
			auto_active = false
			hold_q = _att()
			dsky.show(6, 43, true)


## Where the LM is and how it moves in the guidance frame: "g" its axes in
## ECI, "rg" and "vg" the LM's position and velocity over the turning
## surface relative to the site, "gg" gravity.
func _descent_state() -> Dictionary:
	var mf := Bodies.moon_fixed(_now())
	var g := mf * guidance_frame
	var gi := g.transposed()
	var tr := current_traj()
	var r := tr.pos()
	var rel := tr.vel() - Bodies.moon_omega(tr.t).cross(r)
	var rg := gi * (r - mf * landing_site)
	var vg := gi * rel
	var rl := r.length()
	_slant = (r - mf * landing_site).length()
	_vh = vg.z
	_hdot = vg.x
	_h = rl - landing_site.length() - Dynamics.lm_cm_height(str(Bus.get_value("lm.dyn.config", "lm")))
	var los := Basis(_att()).inverse() * (mf * landing_site - r)
	_lpd = rad_to_deg(atan2(-los.x, los.z))
	return {"g": g, "rg": rg, "vg": vg, "gg": gi * (-r * (Bodies.MU_MOON / (rl * rl * rl)))}


## -1, 0 or +1: the ACA out of its detent one way or the other on an axis.
static func _out_of_detent(v: float) -> int:
	return 1 if v > 0.5 else (-1 if v < -0.5 else 0)


## The time left in P64 to redesignate the landing point, s.
func lpd_time() -> float:
	if program != 64:
		return 0.0
	return maxf(tgo - float(SpacecraftData.section("descent_guidance")["approach"]["tend_s"]), 0.0)


## P64: move the landing point by ACA clicks along the LPD. [param clicks].x
## is fore (-1, farther) or aft (+1, nearer), lpd_elevation_deg each, about
## the LM's Y axis; .y is left (-1) or right (+1), lpd_azimuth_deg each,
## about the local vertical. The new point is where the turned line of
## sight meets the landing site's sphere [simplified: the guidance frame
## moves with the point, its axes kept].
func _redesignate(clicks: Vector2i) -> void:
	if lpd_time() <= 0.0 or nav == null:
		return
	var d := SpacecraftData.section("descent_guidance")
	var mf := Bodies.moon_fixed(_now())
	var r := nav.pos()
	var up := r.normalized()
	var los := mf * landing_site - r
	if clicks.x != 0:
		los = los.rotated((Basis(_att()) * Vector3.UP).normalized(), deg_to_rad(-clicks.x * float(d["lpd_elevation_deg"])))
	if clicks.y != 0:
		los = los.rotated(up, deg_to_rad(-clicks.y * float(d["lpd_azimuth_deg"])))
	var s := LandingRadar.sphere_hit(r, los.normalized(), landing_site.length())
	if s < 0.0:
		return   # a line of sight above the horizon: the LGC ignores the click
	landing_site = mf.transposed() * (r + los.normalized() * s)


## N69's correction: move the landing site by [param d] in the guidance
## frame (x up, y crossrange, z downrange), m. The horizontal part moves
## it over its sphere, the vertical part raises it [simplified: Luminary
## added the vector as it was, which lifts a site moved 4,200 ft by half
## a metre].
func correct_landing_site(d: Vector3) -> void:
	var r := landing_site.length() + d.x
	landing_site = (landing_site + guidance_frame * Vector3(0.0, d.y, d.z)).normalized() * r
	ls_corrected = true


## One cycle of Klumpp's quadratic guidance to [param target]: the
## acceleration command, in the guidance frame, for a quadratic
## acceleration that meets the target's position, velocity and
## acceleration, with the time to go that meets its downrange jerk.
func _klumpp(target: Dictionary, st: Dictionary, dt: float) -> Vector3:
	var rt := _v3(target["r"])
	var vt := _v3(target["v"])
	var at := _v3(target["a"])
	var rg: Vector3 = st["rg"]
	var vg: Vector3 = st["vg"]
	tgo = solve_tgo(tgo - dt, float(target["jz"]), at.z, vg.z, vt.z, rg.z, rt.z)
	var tau := maxf(tgo, 1.0)
	return at + (rt - rg) * (12.0 / (tau * tau)) - (vt + vg) * (6.0 / tau)


## The time to go that meets the target's downrange jerk [param jz]:
## Newton on jz t³ - 6 atz t² + (6 vz + 18 vtz) t + 24 (rz - rtz) = 0
## from [param guess].
static func solve_tgo(guess: float, jz: float, atz: float, vz: float, vtz: float, rz: float, rtz: float) -> float:
	var t := guess
	for _i in 20:
		var f := jz * t * t * t - 6.0 * atz * t * t + (6.0 * vz + 18.0 * vtz) * t + 24.0 * (rz - rtz)
		var df := 3.0 * jz * t * t - 12.0 * atz * t + (6.0 * vz + 18.0 * vtz)
		if absf(df) < 1e-9:
			break
		var step := f / df
		t -= step
		if absf(step) < 1e-6:
			break
	return t


## Steer the thrust to give the acceleration [param acmd] (guidance frame)
## against gravity. Returns the throttle it needs.
func _steer_to(acmd: Vector3, st: Dictionary) -> float:
	var ath := acmd - (st["gg"] as Vector3)
	var g: Basis = st["g"]
	auto_target = _descent_attitude(g * ath.normalized(), g)
	desired_q = auto_target
	auto_active = true
	return ath.length() * _mass() / float(SpacecraftData.section("dps")["thrust_n"])


## The LM's attitude to thrust along [param u] (ECI): +X along it, +Y along
## the guidance frame's crossrange: windows up while braking, and facing
## downrange, toward the site, once upright.
static func _descent_attitude(u: Vector3, g: Basis) -> Quaternion:
	var x := u.normalized()
	var y := g.y - x * g.y.dot(x)
	if y.length() < 1e-3:
		y = x.cross(g.z)
	y = y.normalized()
	return Basis(x, y, x.cross(y)).orthonormalized().get_rotation_quaternion()


## The CSM's state vector coasted to the LM's own (the time the LGC's
## navigation has reached, a step behind the clock until this step's
## sensing), or null.
func _csm_now() -> Trajectory:
	var t := nav.t if nav != null else _now()
	if csm_nav != null and csm_nav.t < t:
		csm_nav.coast_to(t)
	return csm_nav


# --- powered ascent ----------------------------------------------------------------

## P12: the insertion targets above the landing site the LGC has (or, with
## none, the ground below the LM), and the CSM's plane; then V06N33, the
## liftoff time.
func _start_p12() -> void:
	# The powered ascent gives P20's W up [published: Luminary 099's ATMAG].
	p20.invalidate()
	var tr := current_traj()
	ascent_base = landing_site.length() if landing_site != Vector3.ZERO \
		else tr.radius() - Dynamics.lm_cm_height(str(Bus.get_value("lm.dyn.config", "lm")))
	ascent_targets = AscentGuidance.targets(ascent_base)
	var c := _csm_now()
	ascent_plane = c.pos().cross(c.vel()).normalized()
	tgo = 0.0
	step_name = "tig"
	dsky.show(6, 33, true)


# --- the aborts (slice 9e) ----------------------------------------------------------

## Luminary's abort monitor on channel 30, while its landing displays run
## (P63 to P66, P70 and P71): with the aborts enabled (LETABORT) and MODREG
## not 71, ABORT STAGE, which has staged the LM (Dynamics.stage_lm()),
## starts P71; with MODREG not 70 either, ABORT starts P70. ABORT's bit is
## the pushbutton's contacts to the LGC, which the switch's short closes;
## a tap on the panel beside it, or the pushbutton's press, opens them
## again [published: MSC-04112, section 14.2.2, "removed by tapping on the
## panel near the abort switch"; MSC-04330, Appendix A, reset "by pressing
## the switch twice"].
func _abort_discretes() -> void:
	var abort := bool(Bus.get_value("ctl.lm.abort", false))
	var tap := bool(Bus.get_value("ctl.lm.panel_tap", false))
	if abort_short and (tap and not _tap_was or abort and not _abort_was):
		abort_short = false
	_tap_was = tap
	_abort_was = abort
	Bus.set_value("lm.lgc.abort_bit", abort or abort_short)
	Bus.set_value("lm.lgc.modreg", erasable.modreg)
	Bus.set_value("lm.lgc.letabort", erasable.letabort)
	Bus.set_value("lm.lgc.zoomflag", erasable.zoomflag)
	if not erasable.letabort or erasable.modreg == 71 or not (program in DESCENT_BURN or program in ABORTS):
		return
	if str(Bus.get_value("lm.dyn.config", "lm")) == "lm_ascent":
		_abort(71)
	elif erasable.modreg != 70 and (abort or abort_short):
		_abort(70)


## Channel [param n]'s word as the LGC reads it: channel 30's input
## discretes, each bit 0 while its signal is present, as Luminary's abort
## monitor complements it [published: Luminary 178's
## INPUT_OUTPUT_CHANNEL_BIT_DESCRIPTIONS and P70-P71]: bit 1 ABORT, 3 the
## engine armed, 4 ABORT STAGE, 5 the LGC throttling the descent engine,
## 9 the IMU operating, 10 the LGC in control, 15 the stable member's
## temperature in limits [simplified: the other bits read absent, bits 5
## and 10 follow GUID CONT, with no THR CONT switch, and the other
## channels read 0].
func channel(n: int) -> int:
	if n != 30:
		return 0
	var pgns := int(Bus.get_value("ctl.lm.guid_cont", 0)) == 0
	var present := {
		1: bool(Bus.get_value("ctl.lm.abort", false)) or abort_short,
		3: int(Bus.get_value("ctl.lm.engine_arm", 0)) != 0 or bool(Bus.get_value("lm.dps.abort_armed", false)),
		4: str(Bus.get_value("lm.dyn.config", "lm")) == "lm_ascent",
		5: pgns, 9: imu.operating(), 10: pgns, 15: is_powered(),
	}
	var w := 32767
	for b: int in present:
		if present[b]:
			w &= ~(1 << (b - 1))
	return w


## The ABORT switch's short (Apollo 14's), or the core's failures.
func fail(part: String) -> void:
	if part == "abort_switch":
		abort_short = true
		return
	super.fail(part)


func _abort(p: int) -> void:
	_abort_request = true
	change_program(p)
	_abort_request = false


## P70 or P71 [param p]: the insertion targets for the TPI the abort aims
## at (the PDI PAD's for an abort before the split, or after it), in the
## CSM's plane; the engine on, from the vertical rise below 25,000 ft or
## straight into ascent guidance above it.
func _start_abort(p: int) -> void:
	var tr := current_traj()
	var now := _now()
	ascent_base = landing_site.length() if landing_site != Vector3.ZERO else Bodies.R_MOON
	var c := _csm_now()
	ascent_plane = (c.pos().cross(c.vel()) if c != null else tr.pos().cross(tr.vel())).normalized()
	if abort_tpi < 0.0 and abort_split_get >= 0.0:
		# The first abort's: P71 after P70 aims at the same.
		abort_tpi = abort_tpi_early if now < abort_split_get else abort_tpi_late
	var eng := SpacecraftData.section("aps" if _on_aps(p) else "dps")
	if c != null:
		ascent_targets = AscentGuidance.abort_targets(tr.pos(), tr.vel(), c.pos(), c.vel(), ascent_base, now, abort_tpi,
			_mass(), engine_thrust(p), float(eng["isp_s"]))
	else:
		ascent_targets = AscentGuidance.targets(ascent_base)
	var d := SpacecraftData.section("ascent_guidance")
	var rise := tr.radial_rate() < float(d["vertical_rise_hdot_mps"]) \
		and tr.radius() - ascent_base < float(d["abort_vertical_alt_m"])
	step_name = "vertical" if rise else "ascent"
	if p == 71:
		erasable.letabort = false
	tgo = 0.0
	engine_enabled = true
	engine_on = true
	ignition_get = now
	_drop_maneuver()
	auto_active = true
	dsky.show(16, 94)


## P12's step: the countdown to TIG; from ignition the vertical rise, the
## pitchover and ascent guidance to insertion, the steering held for the
## last seconds, and cutoff when the time to go is down to the engine's
## tail-off. P70 and P71 fly the same from the vertical rise, on their
## engine, the rise ended above 25,000 ft too.
func _p12_step(now: float) -> void:
	var d := SpacecraftData.section("ascent_guidance")
	var tr := current_traj()
	var up := tr.pos().normalized()
	var eng := SpacecraftData.section("aps" if _on_aps(program) else "dps")
	var g := AscentGuidance.steer(tr.pos(), tr.vel(), tr.radius(), tr.radial_rate(), ascent_plane, _mass(),
		ascent_targets, tgo, engine_thrust(program), float(eng["isp_s"]))
	var need: Vector3 = g["vg"]
	vg = PackedFloat64Array([need.x, need.y, need.z])
	var next := -1.0
	match step_name:
		"tig", "targets", "wait":
			if step_name == "wait" and now >= tig_load - 5.0:
				step_name = "v99"
				dsky.show(99, 74, true)
				next = tig_load
			else:
				# Coast landing points: TIG-60 s, then TIG-5 s.
				next = tig_load - 60.0 if now < tig_load - 60.0 else tig_load - 5.0
		"v99":
			# On the surface nothing else keeps the steps fine: land on TIG.
			next = tig_load if now < tig_load else -1.0
		"ignition":
			if now >= tig_load - 1e-6:
				step_name = "vertical"
				engine_on = true
				ignition_get = now
			else:
				next = tig_load
		"vertical":
			if tr.radial_rate() >= float(d["vertical_rise_hdot_mps"]) \
					or (program in ABORTS and tr.radius() - ascent_base >= float(d["abort_vertical_alt_m"])):
				step_name = "ascent"
		"ascent":
			if float(g["tgo"]) < float(d["hold_s"]):
				step_name = "hold"
		"tailoff":
			if not engine_running():
				step_name = "post"
				# In orbit the DAP holds the attitude the LM inserted in.
				hold_q = _att()
				dsky.show(16, 85, true)
	if step_name in ["vertical", "ascent"]:
		# Straight up, facing along the CSM's track; then along the guidance.
		auto_target = _ascent_attitude(up if step_name == "vertical" else g["u"], -ascent_plane)
		desired_q = auto_target
		auto_active = true
	if step_name in ["vertical", "ascent", "hold"]:
		tgo = g["tgo"]
		if step_name != "vertical" and tgo <= engine_tau_off(program):
			engine_on = false
			step_name = "tailoff"
	Bus.set_value(_ch("guid.next_event_get_s"), next)


## The LM's attitude in P12 to thrust along [param u]: +X along it, +Y to
## the right of the CSM's track, [param right] (its orbit normal
## reversed). The LM pitches over about +Y: the crew face along the track
## in the vertical rise, and look down at the surface once the thrust
## lies along it.
static func _ascent_attitude(u: Vector3, right: Vector3) -> Quaternion:
	var x := u.normalized()
	var y := right - x * right.dot(x)
	if y.length() < 1e-3:
		y = x.cross(Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT)
	y = y.normalized()
	return Basis(x, y, x.cross(y)).orthonormalized().get_rotation_quaternion()


## N74: the time from ignition, and the yaw and pitch after the vertical
## rise: the turn about the vertical that faces the LM along the CSM's
## plane, and the angle from the vertical that guidance first commands,
## where the rise ends (40 ft/s up, some 50 m over the surface, on the
## ascent stage).
func _n74() -> Array:
	var tfi := _now() - tig_load
	if ascent_targets.is_empty():
		return [tfi, 0.0, 0.0]
	var tr := current_traj()
	var up := tr.pos().normalized()
	var fwd := ascent_plane.cross(up).normalized()
	var z := Basis(_att()) * Vector3(0.0, 0.0, 1.0)
	var zh := z - up * z.dot(up)
	var yaw := rad_to_deg(atan2(zh.cross(fwd).dot(up), zh.dot(fwd)))
	var rise := float(SpacecraftData.section("ascent_guidance")["vertical_rise_hdot_mps"])
	var f := SpacecraftData.lm_full_loads()
	var m := SpacecraftData.lm_total_mass("lm_ascent", 0.0, float(Bus.get_value("lm.aps.prop_kg", f[1])),
		float(Bus.get_value("lm.rcs.prop_kg", f[2])))
	var g := AscentGuidance.steer(up * (tr.radius() + 50.0), tr.vel() + up * rise, tr.radius() + 50.0, rise,
		ascent_plane, m, ascent_targets, 0.0)
	return [tfi, yaw, rad_to_deg((g["u"] as Vector3).angle_to(up))]


# --- rendezvous ---------------------------------------------------------------------

## The LGC's two state vectors coasted to GET [param t] (copies): [LM, CSM].
func _rdv_states(t: float) -> Array:
	var l := nav.clone()
	l.coast_to(t)
	var c := csm_nav.clone()
	c.coast_to(t)
	return [l, c]


## [param dv] (inertial) in [param tr]'s LVLH axes, as N81 shows it.
static func _to_lvlh(tr: Trajectory, dv: Vector3) -> Vector3:
	return Trajectory.lvlh_basis(tr.pos(), tr.vel()).inverse() * dv


func _start_rendezvous(p: int) -> void:
	match p:
		32:
			step_name = "n11"
			dsky.show(6, 11, true)
		33:
			step_name = "n13"
			dsky.show(6, 13, true)
		34:
			step_name = "n55"
			dsky.show(6, 55, true)
		35:
			if _target_tpm():
				step_name = "n81"
				dsky.show(6, 81, true)


## PRO through P32 to P35's displays. N81's stores the maneuver, for P41
## to fly, and V16N45 follows (marks, time from ignition, middle gimbal):
## V32 there computes it again on the marks since, PRO is the final
## computation, after which P20's marks wait for the next program's start
## [published: Luminary 099, P32-P35 and P20FLGON; the G mission's
## rendezvous procedures, CF-R-69-23]. V37 may leave it at N45 for P41.
func _proceed_rendezvous() -> void:
	match step_name:
		"n11":
			step_name = "n55"
			dsky.show(6, 55, true)
		"n55":
			if program == 34 and not _find_tpi_tig():
				return
			step_name = "n37"
			dsky.show(6, 37, true)
		"n37":
			if program == 32 and _target_csi():
				step_name = "n75"
				dsky.show(6, 75, true)
			elif program == 34 and _target_tpi():
				step_name = "n58"
				dsky.show(6, 58, true)
		"n13":
			if _target_cdh():
				step_name = "n75"
				dsky.show(6, 75, true)
		"n75", "n58":
			step_name = "n81"
			dsky.show(6, 81, true)
		"n81":
			_store_maneuver()
			step_name = "n45"
			dsky.show(16, 45, true)
		"n45":
			p20.final_computation()
			change_program(0)


## V32 at V16N45: the solution again on the state vectors the marks have
## moved since.
func _recycle_rendezvous() -> void:
	match program:
		32:
			if _target_csi():
				step_name = "n75"
				dsky.show(6, 75, true)
		33:
			if _target_cdh():
				step_name = "n75"
				dsky.show(6, 75, true)
		34:
			# The TPI time found again for the elevation.
			if _find_tpi_tig():
				step_name = "n37"
				dsky.show(6, 37, true)
		35:
			if _target_tpm():
				step_name = "n81"
				dsky.show(6, 81, true)


## P32: CSI's horizontal ΔV, for its TIG and TPI's (Rendezvous.plan_csi()).
## Alarm 611 without a solution, or with the TIG past.
func _target_csi() -> bool:
	if rdv_csi_tig <= _now() or rdv_tpi_tig <= rdv_csi_tig:
		_alarm(611)
		return false
	var sol := Rendezvous.plan_csi(nav, csm_nav, rdv_csi_tig, rdv_tpi_tig, rdv_elev)
	if not sol["ok"]:
		_alarm(611)
		return false
	rdv_cdh_tig = sol["cdh_get"]
	rdv_dh = sol["dh"]
	tig_load = rdv_csi_tig
	dv_lvlh_load = Vector3(sol["dv"], 0.0, 0.0)
	return true


## P33: the coelliptic ΔV at CDH's TIG.
func _target_cdh() -> bool:
	if rdv_cdh_tig <= _now():
		_alarm(611)
		return false
	var st := _rdv_states(rdv_cdh_tig)
	var d := Rendezvous.cdh(st[0], st[1])
	rdv_dh = d["dh"]
	tig_load = rdv_cdh_tig
	dv_lvlh_load = _to_lvlh(st[0], d["dv"])
	return true


## P34: TPI's TIG, when the CSM comes up to the TPI elevation within the
## next three hours; with the elevation loaded as zero (N55), N37's TIG as
## it stands [published: P34 computes "TIG(TPI) given E, or E given
## TIG(TPI)" (GSOP R-567, section 4, P34); Apollo 14's direct rendezvous
## had TPI a set 38 min after the insertion (MSC-04330), the ascent PAD's
## N37].
func _find_tpi_tig() -> bool:
	var now := maxf(_now(), nav.t)
	if is_zero_approx(rdv_elev):
		if rdv_tpi_tig <= now:
			_alarm(611)
			return false
		return true
	var t := Rendezvous.tpi_time(nav, csm_nav, rdv_elev, now + 60.0, now + 3.0 * 3600.0)
	if t < 0.0:
		_alarm(611)
		return false
	rdv_tpi_tig = t
	return true


## P34: the transfer from TPI's TIG that meets the CSM after it has flown
## the transfer angle.
func _target_tpi() -> bool:
	if rdv_tpi_tig <= _now():
		_alarm(611)
		return false
	var st := _rdv_states(rdv_tpi_tig)
	var l: Trajectory = st[0]
	rdv_intercept_get = Rendezvous.arrival(st[1], rdv_wt)
	var tr := Rendezvous.transfer(l, st[1], rdv_intercept_get)
	var dv: Vector3 = tr["dv"]
	rdv_tpi_dv = dv.length()
	rdv_tpf_dv = tr["rel_v"]
	var after := l.s.duplicate()
	for i in 3:
		after[3 + i] += dv[i]
	rdv_hp = float(Trajectory.conic_of(after, Bodies.mu_of(l.primary))["rp"]) - Bodies.radius_of(l.primary)
	tig_load = rdv_tpi_tig
	dv_lvlh_load = _to_lvlh(l, dv)
	return true


## P35: the correction tpm_lead_s ahead that aims at TPI's meeting again.
func _target_tpm() -> bool:
	var tig := maxf(_now(), nav.t) + float(SpacecraftData.section("rendezvous_guidance")["tpm_lead_s"])
	var st := _rdv_states(tig)
	var tr := Rendezvous.transfer(st[0], st[1], rdv_intercept_get)
	rdv_tpf_dv = tr["rel_v"]
	tig_load = tig
	dv_lvlh_load = _to_lvlh(st[0], tr["dv"])
	return true


func _mass() -> float:
	return float(Bus.get_value("lm.dyn.mass_kg", SpacecraftData.lm_mass()))


static func _v3(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func noun_values(n: int) -> Variant:
	var v: Variant = null
	if n in [1, 7, 10]:
		return erasable.noun_values(n, channel)
	if program == 57 and n in [4, 5, 6, 22, 25, 34, 70, 71, 79, 89, 93]:
		return surface.noun_values(n)
	if n == 25 and p20.priority in ["n25", "manual"]:
		return p20.noun_values(n)
	if n in [5, 6, 25, 34, 70, 71, 89, 93] or (n == 22 and not _v41):
		return align.noun_values(n)
	match n:
		33:
			if program == 63:
				v = [pdi_tig, pdi_tig, pdi_tig]
		43:
			var at := Bodies.fixed_to_selenographic(Bodies.moon_fixed(_now()).transposed() * current_traj().pos())
			v = [at.x, at.y, maxf(_h, 0.0)]
		60:
			v = [_vh, _hdot, _h]
		63:
			v = [current_traj().speed(), _hdot, _h]
		64:
			v = [floorf(minf(lpd_time(), 99.0)) * 1000.0 + clampf(roundf(_lpd), 0.0, 999.0), _hdot, _h]
		68:
			v = [_slant, tgo, delta_h]
		69:
			# The correction still to add: none, once the site has moved.
			v = [0.0, 0.0, 0.0]
		74:
			if program == ASCENT:
				v = _n74()
		76:
			# The targets, and the LM's distance from the CSM's plane.
			if not ascent_targets.is_empty():
				v = [ascent_targets["vh"], ascent_targets["rdot"], current_traj().pos().dot(ascent_plane)]
		94:
			if not ascent_targets.is_empty():
				var tr := current_traj()
				v = [Vector3(vg[0], vg[1], vg[2]).length(), tr.radial_rate(), tr.radius() - ascent_base]
		11, 13, 37:
			var t: float = {11: rdv_csi_tig, 13: rdv_cdh_tig, 37: rdv_tpi_tig}[n]
			v = [t, t, t]
		16:
			v = [r47.agsk, r47.agsk, r47.agsk]
		45, 49, 72, 78, 99:
			v = p20.noun_values(n)
		54:
			if nav != null and _csm_now() != null:
				var los := Rendezvous.rel_pos(nav, csm_nav)
				v = [los.length(), Rendezvous.rel_vel(nav, csm_nav).dot(los.normalized()),
					rad_to_deg(Rendezvous.elevation(nav, csm_nav))]
		55:
			v = [1, rad_to_deg(rdv_elev), rad_to_deg(rdv_wt)]
		58:
			v = [rdv_hp, rdv_tpi_dv, rdv_tpf_dv]
		75:
			v = [rdv_dh, rdv_cdh_tig - rdv_csi_tig, rdv_tpi_tig - rdv_cdh_tig]
	return v if v != null else super.noun_values(n)


## V24N76: the crew load P12's horizontal velocity and climb targets.
## V21N69 (or V22 to V25) in P63 or P64: the landing site correction, m.
func noun_load(n: int, idx: int, value: float) -> bool:
	if n in [1, 7, 10, 99] or (program == 52 and n in [6, 34, 70, 71]) or (program == 57 and n in [6, 34, 70, 71, 79]):
		# The machine address nouns, V67's W (P20), or P52's and P57's.
		var by: Object = erasable if n in [1, 7, 10] else (p20 if n == 99 else (align if program == 52 else surface))
		return by.noun_load(n, idx, value)
	if n == 69:
		var ok := program in [63, 64] and landing_site != Vector3.ZERO
		if ok:
			correct_landing_site([Vector3(0.0, 0.0, value), Vector3(0.0, value, 0.0), Vector3(value, 0.0, 0.0)][idx])
		return ok
	if n == 76:
		var took := not ascent_targets.is_empty() and idx <= 1
		if took:
			ascent_targets["vh" if idx == 0 else "rdot"] = value
		return took
	if n in TIME_NOUNS:
		match n:
			11:
				rdv_csi_tig = _load_hms(rdv_csi_tig, idx, value)
			13:
				rdv_cdh_tig = _load_hms(rdv_cdh_tig, idx, value)
			37:
				rdv_tpi_tig = _load_hms(rdv_tpi_tig, idx, value)
		return true
	if n == 55:
		# The number of apsides to CDH is always 1 here.
		if idx == 1:
			rdv_elev = deg_to_rad(value)
		elif idx == 2:
			rdv_wt = deg_to_rad(value)
		return idx != 0 or is_equal_approx(value, 1.0)
	return super.noun_load(n, idx, value)


## Time [param t] with its hours (idx 0), minutes (1) or seconds (2)
## replaced by [param value], which the DSKY gives in seconds.
static func _load_hms(t: float, idx: int, value: float) -> float:
	var parts := [floorf(t / 3600.0) * 3600.0, floorf(fmod(t, 3600.0) / 60.0) * 60.0, fmod(t, 60.0)]
	parts[idx] = value
	return parts[0] + parts[1] + parts[2]


func snapshot() -> Dictionary:
	var d := super.snapshot()
	var gf := guidance_frame
	d["descent"] = {
		"site": [landing_site.x, landing_site.y, landing_site.z],
		"frame": [gf.x.x, gf.x.y, gf.x.z, gf.y.x, gf.y.y, gf.y.z, gf.z.x, gf.z.y, gf.z.z],
		"pdi_tig": pdi_tig, "tgo": tgo, "throttle": descent_throttle, "rod_cmd": rod_cmd, "guide_get": _guide_get,
		"lr_update": lr_update, "delta_h": delta_h, "lr_timer": _lr_timer, "ls_corrected": ls_corrected,
		"step_get": _step_get, "restart_hold": _restart_hold, "letabort_get": _letabort_get, "zoom_get": _zoom_get,
	}
	d["executive"] = executive.snapshot()
	d["align"] = align.snapshot()
	d["surface"] = surface.snapshot()
	d["tland"] = tland
	d["restarts"] = {"count": restarts, "get": restart_get, "alarm": restart_alarm}
	d["nav_landed_mf"] = [nav_landed_mf.x, nav_landed_mf.y, nav_landed_mf.z]
	d["p40_schedule"] = p40_schedule.duplicate()
	d["kalcmanu"] = {"from": [kal_from.x, kal_from.y, kal_from.z, kal_from.w],
		"axis": [kal_axis.x, kal_axis.y, kal_axis.z], "angle": kal_angle, "rate": kal_rate, "t0": kal_t0}
	d["ascent"] = {"targets": ascent_targets.duplicate(), "base": ascent_base,
		"plane": [ascent_plane.x, ascent_plane.y, ascent_plane.z]}
	d["abort"] = {"tpi_early": abort_tpi_early, "tpi_late": abort_tpi_late, "split": abort_split_get, "tpi": abort_tpi,
		"abort_was": _abort_was, "short": abort_short, "tap_was": _tap_was}
	d["erasable"] = erasable.snapshot()
	if csm_nav != null:
		d["csm_nav"] = {"primary": csm_nav.primary, "t": csm_nav.t, "s": Array(csm_nav.s), "field": csm_nav.field_snapshot()}
	d["rendezvous"] = {
		"rr_nav": rr_nav, "p20": p20.snapshot(), "r47": r47.snapshot(),
		"csi_tig": rdv_csi_tig, "cdh_tig": rdv_cdh_tig, "tpi_tig": rdv_tpi_tig, "elev": rdv_elev, "wt": rdv_wt,
		"intercept_get": rdv_intercept_get, "dh": rdv_dh, "tpi_dv": rdv_tpi_dv, "tpf_dv": rdv_tpf_dv, "hp": rdv_hp,
	}
	return d


func restore(d: Dictionary) -> void:
	var dd: Dictionary = d.get("descent", {})
	if not dd.is_empty():
		landing_site = _v3(dd["site"])
		var f: Array = dd["frame"]
		guidance_frame = Basis(Vector3(f[0], f[1], f[2]), Vector3(f[3], f[4], f[5]), Vector3(f[6], f[7], f[8]))
	_restoring = true
	super.restore(d)
	_restoring = false
	nav_landed_mf = _v3(d.get("nav_landed_mf", [0.0, 0.0, 0.0]))
	executive.restore(d.get("executive", {}))
	align.restore(d.get("align", {}))
	surface.restore(d.get("surface", {}))
	tland = float(d.get("tland", 0.0))
	if program == 52:
		align.show_step()
	if program == 57:
		surface.show_step()
	var rs: Dictionary = d.get("restarts", {})
	restarts = int(rs.get("count", 0))
	restart_get = float(rs.get("get", -1.0))
	restart_alarm = int(rs.get("alarm", 0))
	_publish_executive()
	p40_schedule = Dps.p40_schedule(d.get("p40_schedule", []))
	var kd: Dictionary = d.get("kalcmanu", {})
	if kd.has("t0"):
		var kf: Array = kd["from"]
		kal_from = Quaternion(kf[0], kf[1], kf[2], kf[3])
		kal_axis = _v3(kd["axis"])
		kal_angle = float(kd["angle"])
		kal_rate = float(kd["rate"])
		kal_t0 = float(kd["t0"])
	csm_nav = null
	var cd: Dictionary = d.get("csm_nav", {})
	if not cd.is_empty():
		csm_nav = Trajectory.new().as_onboard(Trajectory.Model.LGC)
		csm_nav.set_state_d(str(cd["primary"]), float(cd["t"]), PackedFloat64Array(cd["s"]))
		csm_nav.restore_field(cd.get("field", {}))
	var ad: Dictionary = d.get("ascent", {})
	ascent_targets = (ad.get("targets", {}) as Dictionary).duplicate()
	ascent_base = float(ad.get("base", 0.0))
	ascent_plane = _v3(ad.get("plane", [0.0, 0.0, 0.0]))
	var ab: Dictionary = d.get("abort", {})
	abort_tpi_early = float(ab.get("tpi_early", -1.0))
	abort_tpi_late = float(ab.get("tpi_late", -1.0))
	abort_split_get = float(ab.get("split", -1.0))
	abort_tpi = float(ab.get("tpi", -1.0))
	_abort_was = bool(ab.get("abort_was", false))
	abort_short = bool(ab.get("short", false))
	_tap_was = bool(ab.get("tap_was", false))
	if program in ABORTS:
		dsky.show(16, 85 if step_name == "post" else 94, step_name == "post")
	elif program == ASCENT:
		# The display the restored step shows.
		var shows := {"tig": [6, 33, true], "targets": [6, 76, true], "wait": [16, 74, false], "v99": [99, 74, true],
			"post": [16, 85, true]}
		var sh: Array = shows.get(step_name, [16, 94, false])
		dsky.show(sh[0], sh[1], sh[2])
	# All of it, each value's default where one is missing: nothing from
	# before the restore stays.
	var rd: Dictionary = d.get("rendezvous", {})
	var r := SpacecraftData.section("rendezvous_guidance")
	rr_nav = bool(rd.get("rr_nav", false))
	p20.restore(rd.get("p20", {}))
	r47.restore(rd.get("r47", {}))
	rdv_csi_tig = float(rd.get("csi_tig", 0.0))
	rdv_cdh_tig = float(rd.get("cdh_tig", 0.0))
	rdv_tpi_tig = float(rd.get("tpi_tig", 0.0))
	rdv_elev = float(rd.get("elev", deg_to_rad(float(r["tpi_elevation_deg"]))))
	rdv_wt = float(rd.get("wt", deg_to_rad(float(r["tpi_transfer_deg"]))))
	rdv_intercept_get = float(rd.get("intercept_get", 0.0))
	rdv_dh = float(rd.get("dh", 0.0))
	rdv_tpi_dv = float(rd.get("tpi_dv", 0.0))
	rdv_tpf_dv = float(rd.get("tpf_dv", 0.0))
	rdv_hp = float(rd.get("hp", 0.0))
	if program == 20:
		dsky.show(16, 54)
	elif program in RENDEZVOUS and step_name != "":
		dsky.show(6, int(step_name.substr(1)), true)
	p20.show_priority()
	r47.show_display()
	if not dd.is_empty():
		lr_update = bool(dd.get("lr_update", false))
		ls_corrected = bool(dd.get("ls_corrected", false))
		delta_h = float(dd.get("delta_h", 0.0))
		_lr_timer = float(dd.get("lr_timer", 0.0))
		pdi_tig = float(dd["pdi_tig"])
		tgo = float(dd["tgo"])
		descent_throttle = float(dd["throttle"])
		rod_cmd = float(dd["rod_cmd"])
		_guide_get = float(dd["guide_get"])
		_step_get = float(dd.get("step_get", _guide_get))
		_restart_hold = float(dd.get("restart_hold", -1.0))
		_letabort_get = float(dd.get("letabort_get", -1.0))
		_zoom_get = float(dd.get("zoom_get", -1.0))
		# The display the restored step shows.
		if program == 63:
			var shows := {"tig": [6, 33, true], "v50n18": [50, 18, true], "maneuver": [6, 18, false], "wait": [16, 68, false],
				"v99": [99, 68, true]}
			var sh: Array = shows.get(step_name, [6, 63, false])
			dsky.show(sh[0], sh[1], sh[2])
		elif program in DESCENT:
			dsky.set_prog(program)
			dsky.show(6 if program == 68 else 16, {64: 64, 65: 60, 66: 60, 68: 43}[program], program == 68)
	# MODREG last: PROG shows what the crew may have loaded.
	erasable.restore(d.get("erasable", {"modreg": program}))

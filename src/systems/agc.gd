## Apollo Guidance Computer (Command Module Computer, CMC) with its DSKY:
## the Colossus programs a lunar CSM crew used most, driven through the
## real verb/noun dialogue. The DSKY, P30, the thrusting programs, P47 and
## the digital autopilot are the core's (src/systems/agc_core.gd); the CMC
## adds its engine, its entry programs and its controls.
##
##   P00  CMC idling
##   P30  External ΔV
##   P40  SPS thrusting [simplified: LVLH steering stands in for Colossus
##        cross-product steering, which a long LOI burn needs]
##   P41  RCS thrusting: as P40, but the burn is +X translation on the SM
##        RCS (small corrections the SPS cannot resolve)
##   P47  Thrust monitor (manual burns): V16N83 body ΔV
##   P61  Entry preparation: V16N64 (g, velocity, altitude)
##   P64  Entry guidance (auto at 0.05 g): bank-angle drag control
##   P67  Entry final phase (lift up)
##   P27  Update: the ground's uplinks (V71), the state vector and a PAD's
##        P30 loads, taken in P00 with the UP TLM CM switch in ACCEPT
##        (ctl.cmc.up_tlm); the DSKY shows P27 while UPLINK ACTY is lit
##
## Navigation: the CMC flies on its own state vector (the core's nav),
## which a start phase sets to the state the ground last tracked. Average-G
## adds the CSM's sensed ΔV in P40, P41, P47 and entry, and while the S-IVB
## burns TLI [simplified: the monitor, P15, isn't modelled]. In coast it
## doesn't: the small forces there (vents, unbalanced jets, a translation
## in P00) move the CSM off the state vector, and the ground's uplinks take
## that out.
##
## Digital autopilot (active when ctl.scs.att_source == 0, CMC):
##   ctl.cmc.mode 0 FREE  RHC commands acceleration, no hold
##                1 HOLD  RHC rate command, attitude hold on release
##                2 AUTO  as HOLD, plus program-commanded maneuvers
## It doesn't fly the S-IVB stack (the IU does) or in the atmosphere.
##
## Reads:  the core's, ctl.cmc.up_tlm, sivb.state
## Writes: the core's channels (guid.*, dsky.*), guid.sps_on,
##         guid.bank_auto and guid.bank_cmd_deg
class_name Agc
extends AgcCore

const ENTRY_G_REF := 4.0          ## g, constant-drag reference
const ENTRY_FINAL_V := 3000.0     ## m/s, P67 below this

var entry_captured: bool = false


## The programs whose Average-G puts the sensed ΔV into the state vector.
const AVERAGE_G := [40, 41, 47, 61, 64, 67]


func programs() -> Array:
	return [0, 30, 40, 41, 47, 61, 64, 67]


func thrusting_programs() -> Array:
	return [40, 41]


func engine_thrust(_p: int) -> float:
	return float(SpacecraftData.section("sps")["thrust_n"])


func engine_tau_off(_p: int) -> float:
	return float(SpacecraftData.section("sps")["tau_off_s"])


func engine_running() -> bool:
	return bool(Bus.get_value("sps.on", false))


func publish_engine(on: bool) -> void:
	Bus.set_value("guid.sps_on", on)


func mode() -> int:
	return int(Bus.get_value("ctl.cmc.mode", 1))


func rhc() -> Vector3:
	return Bus.get_value("ctl.rhc", Vector3.ZERO)


func att_source() -> int:
	return int(Bus.get_value("ctl.scs.att_source", 0))


func dap_enabled() -> bool:
	return str(Bus.get_value("dyn.config", "stack")) != "stack" and not bool(Bus.get_value("dyn.in_atmosphere", false))


func authority() -> Vector3:
	var cfg := str(Bus.get_value("dyn.config", "csm"))
	if cfg == "stack":
		return Vector3.ONE
	var c := SpacecraftData.config(cfg)
	var mass := float(Bus.get_value("dyn.mass_kg", 30000.0))
	var inertia := SpacecraftData.inertia(cfg, mass)
	var f := float(SpacecraftData.section("cm_rcs" if cfg == "cm" else "sm_rcs")["jet_thrust_n"])
	var roll := f * float(c["rcs_roll_arm_m"]) * 4.0
	var pitch := f * float(c["rcs_pitch_arm_m"]) * 2.0
	return Vector3(roll / inertia.x, pitch / inertia.y, pitch / inertia.z)


func start_program(p: int) -> void:
	if p in [61, 64, 67]:
		dsky.show(16, 64)


## P27 runs from P00, and only with the UP TLM CM switch in ACCEPT.
func accepts_uplink() -> bool:
	return super.accepts_uplink() and program == 0 and bool(Bus.get_value("ctl.cmc.up_tlm", true))


func avg_g() -> bool:
	return program in AVERAGE_G or str(Bus.get_value("sivb.state", "")) == "burning"


func extra_step() -> void:
	_entry_step()


## Entry guidance flies on the sensed deceleration (g) and the state
## vector's speed and altitude rate.
func _entry_step() -> void:
	if not program in [61, 64, 67]:
		Bus.set_value("guid.bank_auto", false)
		return
	var g := float(Bus.get_value("dyn.g_load", 0.0))
	if program == 61 and g >= 0.05:
		change_program(64)
	var tr := current_traj()
	if program == 64 and tr.speed() < ENTRY_FINAL_V:
		change_program(67)
	var auto := (program == 64 or program == 67) and att_source() == 0
	Bus.set_value("guid.bank_auto", auto)
	if not auto:
		return
	var cmd := 0.0
	if program == 64:
		# Lift up until the drag builds to near the reference, then a
		# constant-drag controller on the vertical lift fraction u = cos(bank):
		# more lift when too deep (drag high, or sinking fast), less when
		# shallow or climbing, so the CM neither digs in nor skips out.
		if g >= ENTRY_G_REF * 0.75:
			entry_captured = true
		if entry_captured:
			var hdot := tr.radial_rate()
			var u := 0.2 + 1.5 * (g - ENTRY_G_REF) / ENTRY_G_REF - 0.01 * hdot
			cmd = rad_to_deg(acos(clampf(u, -1.0, 1.0)))
	Bus.set_value("guid.bank_cmd_deg", cmd)

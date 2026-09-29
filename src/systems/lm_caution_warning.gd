## The LM's caution and warning (slice 9e): its status lights and its
## master alarm [published: LM Apollo Operations Handbook, LMA790-3-LM,
## section 2.9.4]. As the CSM's (CautionWarning): a light comes on with its
## condition and stays on while it holds, and each one coming on lights
## the MASTER ALARM pushbutton-lights and sounds the tone, until a MASTER
## ALARM is pressed. The unit runs on the LM's buses.
##
## The lights are those the modelled systems and the failure catalog's LM
## failures need, with the handbook's triggers (ibid., 2.9.4.4):
##   DES QTY     before staging, a descent tank down to 5.6 % of its
##               propellant (Dps' lm.dps.low_level); it bypasses the
##               master alarm, "to prevent distraction of the astronauts
##               during the most critical phase of the lunar landing"
##   DES REG     before staging, the descent helium out of 219.2 to 259.1
##               psia; dark until the descent engine's first arming
##   RCS A REG, RCS B REG  a system's regulator failed (LmRcs); out when
##               its main shutoff valves close (the system's switch)
##   LGC         the LGC failed; out with GUID CONT at AGS
##   ISS         the LGC's IMU failed; out with GUID CONT at AGS
##
## Reads:  lm.dps.low_level, lm.dps.he_psia, lm.dps.abort_armed,
##         ctl.lm.engine_arm, lm.rcs.sys_a_failed, lm.rcs.sys_b_failed,
##         ctl.lm.rcs.sys_a, ctl.lm.rcs.sys_b, lm.guid.fail, lm.imu.fail,
##         ctl.lm.guid_cont, lm.dyn.config, lm.sys.powered,
##         ctl.lm.cw.master_alarm (a MASTER ALARM pushbutton, pressed)
## Writes: lm.cw.<light> (each status light's), lm.cw.master_alarm
class_name LmCautionWarning
extends Node

const LIGHTS := ["des_qty", "des_reg", "rcs_a_reg", "rcs_b_reg", "lgc", "iss"]
## Each light's legend.
const LEGENDS := {"des_qty": "DES QTY", "des_reg": "DES REG", "rcs_a_reg": "RCS A REG", "rcs_b_reg": "RCS B REG",
	"lgc": "LGC", "iss": "ISS"}
## The lights that leave the master alarm alone.
const QUIET := ["des_qty"]
## DES REG's limits, psia [published: ibid., 2.9.4.4.20].
const DES_REG_PSIA := Vector2(219.2, 259.1)

## The master alarm: its lights and tone.
var on: bool = false
## Each status light's condition at the last step.
var lights: Dictionary = {}
## The descent engine has been armed (DES REG's inhibit lifted).
var des_armed: bool = false
var _reset_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(_dt: float) -> void:
	var reset := bool(Bus.get_value("ctl.lm.cw.master_alarm", false))
	if reset and not _reset_was:
		on = false
	_reset_was = reset
	if int(Bus.get_value("ctl.lm.engine_arm", 0)) == Dps.ARM_DES or bool(Bus.get_value("lm.dps.abort_armed", false)):
		des_armed = true
	for light: String in LIGHTS:
		var lit := _condition(light)
		if lit and not bool(lights.get(light, false)) and not light in QUIET:
			on = true
		lights[light] = lit
	_publish()


func _condition(light: String) -> bool:
	var descent := str(Bus.get_value("lm.dyn.config", "")) == "lm"
	var pgns := int(Bus.get_value("ctl.lm.guid_cont", 0)) == 0
	match light:
		"des_qty":
			return descent and bool(Bus.get_value("lm.dps.low_level", false))
		"des_reg":
			var p := float(Bus.get_value("lm.dps.he_psia", 245.0))
			return descent and des_armed and (p < DES_REG_PSIA.x or p > DES_REG_PSIA.y)
		"rcs_a_reg", "rcs_b_reg":
			var s := light[4]
			return bool(Bus.get_value("lm.rcs.sys_%s_failed" % s, false)) and bool(Bus.get_value("ctl.lm.rcs.sys_" + s, true))
		"lgc":
			return pgns and bool(Bus.get_value("lm.guid.fail", false))
		"iss":
			return pgns and bool(Bus.get_value("lm.imu.fail", false))
	return false


func _publish() -> void:
	var powered := bool(Bus.get_value("lm.sys.powered", false))
	for light: String in LIGHTS:
		Bus.set_value("lm.cw." + light, powered and bool(lights.get(light, false)))
	Bus.set_value("lm.cw.master_alarm", powered and on)


func snapshot() -> Dictionary:
	return {"on": on, "lights": lights.duplicate(), "des_armed": des_armed}


func restore(d: Dictionary) -> void:
	on = bool(d.get("on", false))
	lights = (d.get("lights", {}) as Dictionary).duplicate()
	des_armed = bool(d.get("des_armed", false))
	_reset_was = bool(Bus.get_value("ctl.lm.cw.master_alarm", false))
	_publish()

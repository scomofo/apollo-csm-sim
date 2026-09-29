## Caution and warning: the systems' status lights and the master alarm
## [published: CSM Apollo Operations Handbook, SM2A-03-BLOCK II-(1), 2.10.2
## and 2.10.3].
## A status light comes on with its condition and stays on while it holds.
## Each one coming on turns the master alarm on: the MASTER ALARM
## switch-lights and the tone in the crew's headsets (the audio director's).
## Pressing a MASTER ALARM switch-light turns both off and re-arms the
## circuit for the next light, which sounds it again. The unit runs on the
## main buses: with them dead, it is dark.
##
## The lights are those the modelled systems' limits and the failure
## catalog's failures (data/failures.json, slice 9a) need, with the
## handbook's triggers (ibid., pp. 2.10-5 to 2.10-8):
##   FC 1 to FC 3       a fuel cell failed [simplified: for the flow,
##                      temperature and pH limits the handbook lists]
##   MN BUS A, B UNDERVOLT  a main bus below 26.25 V
##   CRYO PRESS         an O2 tank below 800 or above 950 psia, or a
##                      hydrogen tank below 220 or above 270 psia
##   SM RCS A to D      a quad's secondary fuel pressure below 145 or above
##                      215 psia [simplified: its package temperature
##                      limits left out]
##   CMC                the CMC failed (its prime power lost, among the
##                      handbook's causes)
##   ISS                the IMU failed
## The SM's lights go out with the SM.
##
## Reads:  eps.fc1_ok to eps.fc3_ok, eps.bus_a_v, eps.bus_b_v,
##         eps.o2_tank<n>_psia, eps.h2_tank<n>_psia, rcs.quad_<x>_psia,
##         guid.fail, imu.fail, dyn.config, sys.powered,
##         ctl.cw.master_alarm (a MASTER ALARM switch-light, pressed)
## Writes: cw.<light> (each status light's), sys.master_alarm
class_name CautionWarning
extends Node

## A main bus's undervolt limit, V [published: ibid., p. 2.10-8, 26.25 ±
## 0.1 V dc].
const UNDERVOLT_V := 26.25
const LIGHTS := ["fc1", "fc2", "fc3", "mn_bus_a_undervolt", "mn_bus_b_undervolt", "cryo_press",
	"sm_rcs_a", "sm_rcs_b", "sm_rcs_c", "sm_rcs_d", "cmc", "iss"]
## Each light's legend on the C&W panel.
const LEGENDS := {"fc1": "FC 1", "fc2": "FC 2", "fc3": "FC 3", "mn_bus_a_undervolt": "MN BUS A UNDERVOLT",
	"mn_bus_b_undervolt": "MN BUS B UNDERVOLT", "cryo_press": "CRYO PRESS", "sm_rcs_a": "SM RCS A",
	"sm_rcs_b": "SM RCS B", "sm_rcs_c": "SM RCS C", "sm_rcs_d": "SM RCS D", "cmc": "CMC", "iss": "ISS"}
## CRYO PRESS's limits, psia [published: ibid., p. 2.10-5].
const O2_PSIA_LIMITS := Vector2(800.0, 950.0)
const H2_PSIA_LIMITS := Vector2(220.0, 270.0)
## SM RCS's secondary fuel pressure limits, psia [published: ibid.].
const RCS_PSIA_LIMITS := Vector2(145.0, 215.0)

## The master alarm: its lights and tone.
var on: bool = false
## Each status light's condition at the last step.
var lights: Dictionary = {}
var _reset_was: bool = false


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.SYSTEMS)
	_publish()


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func tick(_dt: float) -> void:
	var reset := bool(Bus.get_value("ctl.cw.master_alarm", false))
	if reset and not _reset_was:
		on = false
	_reset_was = reset
	for light: String in LIGHTS:
		var lit := _condition(light)
		if lit and not bool(lights.get(light, false)):
			on = true
		lights[light] = lit
	_publish()


func _condition(light: String) -> bool:
	var lit := false
	match light:
		"mn_bus_a_undervolt", "mn_bus_b_undervolt":
			lit = float(Bus.get_value("eps.bus_%s_v" % light[7], 28.0)) < UNDERVOLT_V
		"cryo_press":
			lit = _sm() and _cryo_out()
		"sm_rcs_a", "sm_rcs_b", "sm_rcs_c", "sm_rcs_d":
			var q := light.trim_prefix("sm_rcs_")
			lit = _sm() and not _within(float(Bus.get_value("rcs.quad_%s_psia" % q, 180.0)), RCS_PSIA_LIMITS)
		"cmc":
			lit = bool(Bus.get_value("guid.fail", false))
		"iss":
			lit = bool(Bus.get_value("imu.fail", false))
		_:
			lit = not bool(Bus.get_value("eps.%s_ok" % light, true))
	return lit


## A cryogenic tank's pressure out of its limits.
static func _cryo_out() -> bool:
	for n in [1, 2]:
		if not _within(float(Bus.get_value("eps.o2_tank%d_psia" % n, 900.0)), O2_PSIA_LIMITS) \
				or not _within(float(Bus.get_value("eps.h2_tank%d_psia" % n, 245.0)), H2_PSIA_LIMITS):
			return true
	return false


## The SM is attached, with its tanks and quads.
static func _sm() -> bool:
	return SpacecraftData.sm_attached(str(Bus.get_value("dyn.config", "csm")))


static func _within(v: float, limits: Vector2) -> bool:
	return v >= limits.x and v <= limits.y


func _publish() -> void:
	var powered := bool(Bus.get_value("sys.powered", true))
	for light: String in LIGHTS:
		Bus.set_value("cw." + light, powered and bool(lights.get(light, false)))
	Bus.set_value("sys.master_alarm", powered and on)


func snapshot() -> Dictionary:
	return {"on": on, "lights": lights.duplicate()}


func restore(d: Dictionary) -> void:
	on = bool(d["on"])
	lights = d["lights"].duplicate()
	_reset_was = bool(Bus.get_value("ctl.cw.master_alarm", false))
	_publish()

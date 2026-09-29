## LM Electrical Power System (lumped model): the descent stage's four
## batteries and the ascent stage's two, as one store of ampere-hours, and
## the LM's load on them.
##
## The LM's buses are powered (lm.sys.powered) while its batteries hold
## charge and either it flies free [simplified: it powers up as it undocks,
## as the other missions' LMs did hours before] or, docked, its crew has
## powered it up (ctl.lm.power: the LM activation that made it Apollo 13's
## lifeboat). The load is the LM powered down (its communications, caution
## and warning, and the environmental control's pumps and fans), plus the
## PGNS while its breakers are in (ctl.lm.pgns: the LGC and its IMU), the
## AGS while it is on (ctl.lm.ags), and the command module's while the CM
## takes the LM's power through the umbilical (eps.lm_draw_a, the CSM's
## EPS's), at the batteries' voltage (spacecraft.json "lm_eps") [derived
## from Apollo 13's: 30 A with the PGNS up, 12 A powered down].
##
## Reads:  ctl.lm.power, ctl.lm.pgns, ctl.lm.ags, eps.lm_draw_a, dock.state
## Writes: lm.sys.powered, lm.eps.batt_ah, lm.eps.load_a, lm.eps.bus_v
extends Node

var batt_ah: float = -1.0


func _ready() -> void:
	if batt_ah < 0.0:
		batt_ah = float(SpacecraftData.section("lm_eps")["battery_ah"])
	SimClock.add_ticker(tick, SimClock.Stage.POWER_GUIDANCE)
	_publish(false, 0.0)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


## The LM's buses are powered now.
func powered() -> bool:
	var dock := str(Bus.get_value("dock.state", ""))
	var on := dock == "free" or (dock == "docked" and bool(Bus.get_value("ctl.lm.power", false)))
	return on and batt_ah > 0.0


## The LM's load now, A.
func load_a() -> float:
	var d := SpacecraftData.section("lm_eps")
	var a := float(d["base_a"])
	if bool(Bus.get_value("ctl.lm.pgns", true)):
		a += float(d["pgns_a"])
	if bool(Bus.get_value("ctl.lm.ags", false)):
		a += float(d["ags_a"])
	return a + float(Bus.get_value("eps.lm_draw_a", 0.0))


func tick(dt: float) -> void:
	var on := powered()
	var a := load_a() if on else 0.0
	batt_ah = maxf(0.0, batt_ah - a * dt / 3600.0)
	_publish(on and batt_ah > 0.0, a)


func _publish(on: bool, a: float) -> void:
	Bus.set_value("lm.sys.powered", on)
	Bus.set_value("lm.eps.batt_ah", batt_ah)
	Bus.set_value("lm.eps.load_a", a)
	Bus.set_value("lm.eps.bus_v", float(SpacecraftData.section("lm_eps")["bus_v"]) if on else 0.0)


func snapshot() -> Dictionary:
	return {"batt_ah": batt_ah}


func restore(d: Dictionary) -> void:
	batt_ah = float(d.get("batt_ah", SpacecraftData.section("lm_eps")["battery_ah"]))
	_publish(powered(), 0.0)

## Electrical Power System (lumped model).
##
## Three hydrogen-oxygen fuel cells feed Main Buses A and B through their
## crew-selectable connect switches while the Service Module is attached.
## Two cryogenic oxygen and two hydrogen tanks supply the reactants (and the
## cabin oxygen). Entry batteries A, B and C carry the buses after CM/SM
## separation, or when every fuel cell is off-line.
##
## Loads are a lumped baseline plus the active systems; reactant use is the
## fuel-cell electrochemistry figure (~0.36 kg O2 and ~0.045 kg H2 per kWh
## [estimated]). A cryogenic O2 tank failure can be injected
## (fail_o2_tank(2), the Apollo 13 case): tank 2 vents, and the shared
## plumbing starves fuel cells 1 and 3 over the following minutes.
##
## Reads:  ctl.eps.fc1..3 (bool, connected), ctl.eps.batt_bus (bool: tie
##         entry batteries to the mains), dyn.config
## Writes: eps.bus_a_v, eps.bus_b_v, eps.fc<n>_kw, eps.fc<n>_ok,
##         eps.o2_tank<n>_kg, eps.h2_tank<n>_kg, eps.batt_<x>_ah,
##         eps.load_w, sys.powered (CautionWarning lights the buses'
##         undervolts and the fuel cells' failures)
extends Node

const NOMINAL_V := 28.0
const FC_MAX_KW := 1.42
const O2_KG_PER_KWH := 0.36
const H2_KG_PER_KWH := 0.045
## Crew metabolic + cabin leak oxygen draw (three crew) [estimated].
const O2_CABIN_KG_S := 0.10 / 3600.0
const BATT_AH := 40.0
const BASE_LOAD_W := 1900.0
const CM_ONLY_LOAD_W := 1300.0

var o2_kg: Array[float] = [145.0, 145.0]
var h2_kg: Array[float] = [12.7, 12.7]
var batt_ah: Array[float] = [BATT_AH, BATT_AH, BATT_AH]
var fc_ok: Array[bool] = [true, true, true]
## Seconds since an O2 tank failure; negative when none.
var o2_fault_age: float = -1.0
var o2_fault_tank: int = -1


func _ready() -> void:
	SimClock.add_ticker(tick, SimClock.Stage.POWER_GUIDANCE)
	for n in 3:
		if not Bus.has_channel("ctl.eps.fc%d" % (n + 1)):
			Bus.set_value("ctl.eps.fc%d" % (n + 1), true)
	publish_state(0.0, 0.0, 0.0)


func _exit_tree() -> void:
	SimClock.remove_ticker(tick)


func fail_o2_tank(tank: int) -> void:
	o2_fault_tank = clampi(tank, 1, 2) - 1
	o2_fault_age = 0.0


func tick(dt: float) -> void:
	var sm_attached := str(Bus.get_value("dyn.config", "stack")) != "cm"
	if o2_fault_age >= 0.0:
		o2_fault_age += dt
		# The failed tank vents over ~3 minutes; the shared valve module takes
		# fuel cells 1 and 3 with it.
		o2_kg[o2_fault_tank] = maxf(0.0, o2_kg[o2_fault_tank] - 145.0 / 180.0 * dt)
		if o2_fault_age > 90.0:
			fc_ok[0] = false
		if o2_fault_age > 150.0:
			fc_ok[2] = false
	var load := BASE_LOAD_W if sm_attached else CM_ONLY_LOAD_W
	load += 150.0 * float(Bus.get_value("rcs.active_jets", 0))
	if float(Bus.get_value("sps.thrust_n", 0.0)) > 0.0:
		load += 600.0
	var o2_total := o2_kg[0] + o2_kg[1]
	var h2_total := h2_kg[0] + h2_kg[1]
	var cells: Array[int] = []
	if sm_attached:
		for n in 3:
			if fc_ok[n] and bool(Bus.get_value("ctl.eps.fc%d" % (n + 1), true)) and o2_total > 0.0 and h2_total > 0.0:
				cells.append(n)
	var fc_capacity := cells.size() * FC_MAX_KW * 1000.0
	var fc_w := minf(load, fc_capacity)
	var batt_w := load - fc_w
	var use_batt := not sm_attached or bool(Bus.get_value("ctl.eps.batt_bus", false)) or batt_w > 0.0
	var batt_available := 0.0
	for a in batt_ah:
		batt_available += a
	if not use_batt:
		batt_w = 0.0
	var volts := 0.0
	if fc_w > 0.0 or (batt_w > 0.0 and batt_available > 0.0):
		volts = NOMINAL_V + 1.2 - 0.9 * (load / 2000.0)
		if batt_w > 0.0 and batt_available <= 0.0:
			volts *= fc_w / load
	# Reactants.
	var kwh := fc_w / 1000.0 * dt / 3600.0
	_draw(o2_kg, kwh * O2_KG_PER_KWH + (O2_CABIN_KG_S * dt if sm_attached else 0.0))
	_draw(h2_kg, kwh * H2_KG_PER_KWH)
	if batt_w > 0.0 and volts > 0.0:
		var ah := batt_w / volts * dt / 3600.0 / 3.0
		for i in 3:
			batt_ah[i] = maxf(0.0, batt_ah[i] - ah)
	publish_state(volts, load, fc_w / maxf(cells.size(), 1) / 1000.0, cells)


func _draw(tanks: Array[float], kg: float) -> void:
	# Tanks feed in parallel; draw from whichever still holds reactant.
	var live := 0
	for v in tanks:
		if v > 0.0:
			live += 1
	if live == 0:
		return
	for i in tanks.size():
		if tanks[i] > 0.0:
			tanks[i] = maxf(0.0, tanks[i] - kg / live)


func publish_state(volts: float, load: float, kw_per_cell: float, cells: Array[int] = []) -> void:
	Bus.set_value("eps.bus_a_v", volts)
	Bus.set_value("eps.bus_b_v", volts)
	Bus.set_value("eps.load_w", load)
	Bus.set_value("sys.powered", volts > 25.0)
	for n in 3:
		Bus.set_value("eps.fc%d_kw" % (n + 1), kw_per_cell if cells.has(n) else 0.0)
		Bus.set_value("eps.fc%d_ok" % (n + 1), fc_ok[n])
	for n in 2:
		Bus.set_value("eps.o2_tank%d_kg" % (n + 1), o2_kg[n])
		Bus.set_value("eps.h2_tank%d_kg" % (n + 1), h2_kg[n])
	for n in 3:
		Bus.set_value("eps.batt_%s_ah" % ["a", "b", "c"][n], batt_ah[n])


func snapshot() -> Dictionary:
	return {"o2": o2_kg.duplicate(), "h2": h2_kg.duplicate(), "batt": batt_ah.duplicate(),
		"fc_ok": fc_ok.duplicate(), "fault_age": o2_fault_age, "fault_tank": o2_fault_tank}


func restore(d: Dictionary) -> void:
	for i in 2:
		o2_kg[i] = float(d["o2"][i])
		h2_kg[i] = float(d["h2"][i])
	for i in 3:
		batt_ah[i] = float(d["batt"][i])
		fc_ok[i] = bool(d["fc_ok"][i])
	o2_fault_age = float(d.get("fault_age", -1.0))
	o2_fault_tank = int(d.get("fault_tank", -1))
	tick(0.0)

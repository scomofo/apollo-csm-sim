## The LGC's Executive in the powered descent (slice 9b): the jobs the
## descent's programs schedule, sharing the computer's time the interrupts
## leave, and the pool of registers each holds while it waits or runs.
## [simplified: a functional model of the jobs, not their instructions;
## only the powered descent's are modelled, the LGC's other programs light
## enough never to fill the pool]
##
## Luminary's Executive runs the job of highest priority; a job holds a
## core set from its scheduling to its end, and a job that uses the
## interpreter a VAC area too. There are eight core sets and five VAC
## areas [published: Luminary 099's EXECUTIVE, which counts NO.CORES from
## 7 down to 0, and VAC1USE to VAC5USE; Eyles, "Tales from the Lunar Module
## Guidance Computer", 2004]. Scheduling a job with no VAC area free is
## alarm 1201, with no core set free 1202 [published: Luminary 099's alarm
## list, EXECUTIVE OVERFLOW - NO VAC AREAS and NO CORE SETS]; either way
## the Executive restarts the software (BAILOUT): every job is dropped,
## and the programs carry on from their restart points. The Servicer, the
## navigation and guidance job, is scheduled every 2 s whether or not the
## last one has finished [published: Apollo 11 Mission Report, MSC-00171,
## section 16.2].
##
## The interrupts come before any job: the counters and the timed routines
## take a share of the computer's time (Lgc.interrupt_duty()), and the jobs
## share the rest.
class_name LgcExecutive
extends RefCounted

const CORE_SETS := 8
const VAC_AREAS := 5
const NO_VAC_AREAS := 1201
const NO_CORE_SETS := 1202

## The jobs scheduled and not yet ended, highest priority first, in the
## order they came among equals: each {"name", "priority", "vac", "left",
## the computer's time it still needs, s}.
var jobs: Array = []
## Each periodic job's next scheduling, GET s.
var next_get: Dictionary = {}
## The share of the computer's time the interrupts and the jobs asked for
## at the last step (over 1: more than it has).
var load: float = 0.0


## Step to [param now], [param dt] s on: schedule the jobs of [param wanted]
## (name -> {period_s, phase_s, priority, vac, duty}: every period_s, first
## phase_s after it is wanted, each needing duty of the computer's time)
## that are due, then run the jobs, highest priority first, on the time the
## interrupts' share [param interrupt_duty] leaves. Returns the alarm the
## Executive raised scheduling a job, 0 if none; with one, every job has
## been dropped (restart()).
func step(dt: float, now: float, wanted: Dictionary, interrupt_duty: float) -> int:
	load = interrupt_duty
	for name: String in next_get.keys():
		if not wanted.has(name):
			next_get.erase(name)
	for name: String in wanted:
		var w: Dictionary = wanted[name]
		load += float(w["duty"])
		if not next_get.has(name):
			next_get[name] = now + float(w.get("phase_s", 0.0))
		while now >= float(next_get[name]) - 1e-6:
			next_get[name] = float(next_get[name]) + float(w["period_s"])
			var code := _schedule(name, w)
			if code != 0:
				restart()
				return code
	var cpu := dt * maxf(1.0 - interrupt_duty, 0.0)
	while cpu > 1e-12 and not jobs.is_empty():
		var j: Dictionary = jobs[0]
		var used := minf(cpu, float(j["left"]))
		j["left"] = float(j["left"]) - used
		cpu -= used
		if float(j["left"]) <= 1e-9:
			jobs.remove_at(0)
	return 0


## A software restart: every job dropped. The periodic ones come again on
## their schedules.
func restart() -> void:
	jobs.clear()


## No descent: no jobs, and none to come.
func stop() -> void:
	jobs.clear()
	next_get.clear()
	load = 0.0


## The VAC areas the jobs hold.
func vac_in_use() -> int:
	var n := 0
	for j: Dictionary in jobs:
		if bool(j["vac"]):
			n += 1
	return n


## Schedule job [param name]: a VAC area first if it needs one, then a
## core set, as FINDVAC does. Returns the alarm if there is none.
func _schedule(name: String, w: Dictionary) -> int:
	var vac := bool(w["vac"])
	if vac and vac_in_use() >= VAC_AREAS:
		return NO_VAC_AREAS
	if jobs.size() >= CORE_SETS:
		return NO_CORE_SETS
	var j := {"name": name, "priority": int(w["priority"]), "vac": vac,
		"left": float(w["duty"]) * float(w["period_s"])}
	var i := jobs.size()
	while i > 0 and int(jobs[i - 1]["priority"]) < int(j["priority"]):
		i -= 1
	jobs.insert(i, j)
	return 0


func snapshot() -> Dictionary:
	return {"jobs": jobs.duplicate(true), "next_get": next_get.duplicate(), "load": load}


func restore(d: Dictionary) -> void:
	jobs = (d.get("jobs", []) as Array).duplicate(true)
	next_get = (d.get("next_get", {}) as Dictionary).duplicate()
	load = float(d.get("load", 0.0))

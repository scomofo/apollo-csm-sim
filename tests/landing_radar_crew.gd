## Apollo 14's crew and their landing radar, for the tests (slice 12a): at
## Houston's call, 108:08:42, the commander pulls the PGNS: LDG RDR breaker
## and pushes it back in, "Been cycled" at 108:08:52 (Apollo Lunar Surface
## Journal), the radar back in high scale at 108:08:50.66 (MSC-04112,
## Table 8-V) [published].
class_name LandingRadarCrew
extends RefCounted

## Houston's call.
const CALL := "cycle the Landing Radar breaker"
## Seconds from the call to the breaker's pull, and to its push back in.
const PULL_S := 6.0
const PUSH_S := 8.66


## The breaker's cycle, a step at a time: [param done] keeps the call's
## GET ("lr_call") and the pull's and the push's ("lr_pulled",
## "lr_pushed"). Returns whether the breaker is back in.
static func cycle_breaker(done: Dictionary) -> bool:
	var now := SimClock.get_seconds
	if not done.has("lr_call"):
		if str(Bus.get_value("mission.capcom", "")).contains(CALL):
			done["lr_call"] = now
		return false
	var since := now - float(done["lr_call"])
	if since >= PULL_S - 1e-6 and not done.has("lr_pulled"):
		Bus.set_value("ctl.lm.cb_ldg_rdr", false)
		done["lr_pulled"] = now
	if since >= PUSH_S - 1e-6 and done.has("lr_pulled") and not done.has("lr_pushed"):
		Bus.set_value("ctl.lm.cb_ldg_rdr", true)
		done["lr_pushed"] = now
	return done.has("lr_pushed")

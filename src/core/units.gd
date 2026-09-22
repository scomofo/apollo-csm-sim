## SI <-> Apollo display units. Everything on the Bus is SI; the DSKY and
## the HUD convert here, never in the systems (Gemini docs/ARCHITECTURE.md §3).
class_name Units
extends RefCounted

const FT: float = 0.3048            ## m per ft
const NMI: float = 1852.0           ## m per nautical mile
const LBF: float = 4.4482216152605  ## N per lbf
const LBM: float = 0.45359237       ## kg per lbm
const G0: float = 9.80665           ## m/s², standard gravity


static func m_to_nmi(m: float) -> float:
	return m / NMI


static func mps_to_fps(v: float) -> float:
	return v / FT


static func fps_to_mps(v: float) -> float:
	return v * FT


static func kg_to_lb(kg: float) -> float:
	return kg / LBM


## HHH:MM:SS for a signed number of seconds.
static func hms(seconds: float) -> String:
	var s := absi(int(floor(absf(seconds))))
	var sign := "-" if seconds < 0.0 else ""
	@warning_ignore("integer_division")
	return "%s%03d:%02d:%02d" % [sign, s / 3600, (s % 3600) / 60, s % 60]

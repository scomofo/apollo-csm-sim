## SI <-> Apollo display units. Everything on the Bus is SI; the DSKY and
## the HUD convert here, never in the systems (gemini-capsule's
## docs/ARCHITECTURE.md §3: https://github.com/scomofo/gemini-capsule/blob/4dbdff93b60e1d1e41c74ef8c3ca446b9752649b/docs/ARCHITECTURE.md#3-core-signal-bus-and-data-model).
class_name Units
extends RefCounted

const FT: float = 0.3048            ## m per ft
const NMI: float = 1852.0           ## m per nautical mile
const LBF: float = 4.4482216152605  ## N per lbf
const PSF: float = 47.880258889     ## Pa per lbf/ft²
const LBM: float = 0.45359237       ## kg per lbm
const PSI: float = 6894.757293168   ## Pa per psi
const G0: float = 9.80665           ## m/s², standard gravity


static func m_to_ft(m: float) -> float:
	return m / FT


static func m_to_nmi(m: float) -> float:
	return m / NMI


static func nmi_to_m(nmi: float) -> float:
	return nmi * NMI


static func mps_to_fps(v: float) -> float:
	return v / FT


static func fps_to_mps(v: float) -> float:
	return v * FT


static func kg_to_lb(kg: float) -> float:
	return kg / LBM


static func n_to_lbf(n: float) -> float:
	return n / LBF


static func pa_to_psi(pa: float) -> float:
	return pa / PSI


static func psi_to_pa(psi: float) -> float:
	return psi * PSI


static func k_to_f(k: float) -> float:
	return (k - 273.15) * 1.8 + 32.0


## Convert an SI value by name, for the data-driven cabin instruments
## (numeric displays and gauges). The names are gemini-capsule's, so its
## instrument rows keep working: "none", "m_to_ft", "m_to_nmi",
## "mps_to_fps", "pa_to_psi", "k_to_f", "n_to_lbf", "kg_to_lbm",
## "mps2_to_g", "rad_to_deg". An unknown name returns the value unchanged.
static func convert(value: float, kind: String) -> float:
	match kind:
		"m_to_ft": return m_to_ft(value)
		"m_to_nmi": return m_to_nmi(value)
		"mps_to_fps": return mps_to_fps(value)
		"pa_to_psi": return pa_to_psi(value)
		"k_to_f": return k_to_f(value)
		"n_to_lbf": return n_to_lbf(value)
		"kg_to_lbm": return kg_to_lb(value)
		"mps2_to_g": return value / G0
		"rad_to_deg": return rad_to_deg(value)
	return value


## HHH:MM:SS for a signed number of seconds.
static func hms(seconds: float) -> String:
	var s := absi(int(floor(absf(seconds))))
	var sign := "-" if seconds < 0.0 else ""
	@warning_ignore("integer_division")
	return "%s%03d:%02d:%02d" % [sign, s / 3600, (s % 3600) / 60, s % 60]

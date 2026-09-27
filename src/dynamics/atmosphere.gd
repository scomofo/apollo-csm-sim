## Earth atmosphere: the density from a log-linear table of the 1976 U.S.
## Standard Atmosphere, and its pressure and speed of sound from the same
## standard's layers (README.md, "Fidelity"). The air turns with the Earth
## (air_velocity()) [simplified: no winds].
class_name Atmosphere
extends RefCounted

const TABLE_KM: Array[float] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 150, 200, 300]
const TABLE_RHO: Array[float] = [1.225, 0.4135, 0.08891, 0.01841, 0.003996, 0.001027, 3.097e-4,
	8.283e-5, 1.846e-5, 3.416e-6, 5.604e-7, 9.708e-8, 2.222e-8, 2.076e-9, 2.541e-10, 1.916e-11]
## The 1976 standard's layers to 86 km: base geopotential height (m), base
## temperature (K) and lapse rate (K/m) [published].
const LAYERS: Array = [[0.0, 288.15, -0.0065], [11000.0, 216.65, 0.0], [20000.0, 216.65, 0.001],
	[32000.0, 228.65, 0.0028], [47000.0, 270.65, 0.0], [51000.0, 270.65, -0.0028], [71000.0, 214.65, -0.002],
	[84852.0, 186.946, 0.0]]
const P0 := 101325.0
const R_AIR := 287.053
const GAMMA := 1.4
const G0 := 9.80665


## Density in kg/m³ at geometric altitude [param alt_m].
static func density(alt_m: float) -> float:
	var km := alt_m / 1000.0
	if km <= 0.0:
		return TABLE_RHO[0]
	if km >= 1000.0:
		return 0.0
	var n := TABLE_KM.size()
	if km >= TABLE_KM[n - 1]:
		var h := (TABLE_KM[n - 1] - TABLE_KM[n - 2]) / log(TABLE_RHO[n - 2] / TABLE_RHO[n - 1])
		return TABLE_RHO[n - 1] * exp(-(km - TABLE_KM[n - 1]) / h)
	for i in range(n - 1):
		if km < TABLE_KM[i + 1]:
			var f := (km - TABLE_KM[i]) / (TABLE_KM[i + 1] - TABLE_KM[i])
			return exp(lerpf(log(TABLE_RHO[i]), log(TABLE_RHO[i + 1]), f))
	return 0.0


## Pressure (Pa) and temperature (K) at geometric altitude [param alt_m],
## as Vector2; above the layers (86 km) the pressure falls on with the
## last layer's scale height.
static func pressure_temperature(alt_m: float) -> Vector2:
	var h := maxf(alt_m, 0.0)
	var hg := Bodies.R_EARTH * h / (Bodies.R_EARTH + h)
	var p := P0
	for i in LAYERS.size():
		var hb: float = LAYERS[i][0]
		var tb: float = LAYERS[i][1]
		var lr: float = LAYERS[i][2]
		var top: float = LAYERS[i + 1][0] if i + 1 < LAYERS.size() else INF
		var dh := minf(hg, top) - hb
		var t := tb + lr * dh
		if lr == 0.0:
			p *= exp(-G0 * dh / (R_AIR * tb))
		else:
			p *= pow(t / tb, -G0 / (R_AIR * lr))
		if hg <= top:
			return Vector2(p, t)
	return Vector2(p, LAYERS[-1][1])


static func pressure(alt_m: float) -> float:
	return pressure_temperature(alt_m).x


## The speed of sound at geometric altitude [param alt_m], m/s.
static func sound_speed(alt_m: float) -> float:
	return sqrt(GAMMA * R_AIR * pressure_temperature(alt_m).y)


## The velocity through the air of a body at [param r] with velocity
## [param v] (both ECI, Earth-relative): the air turns with the Earth.
static func air_velocity(r: Vector3, v: Vector3) -> Vector3:
	return v - Bodies.earth_omega().cross(r)

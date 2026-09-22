## Earth atmosphere density from a log-linear table of the 1976 U.S.
## Standard Atmosphere (README.md, "Fidelity"). Earth rotation and winds are not
## modelled [simplified]: the air-relative velocity is the inertial one.
class_name Atmosphere
extends RefCounted

const TABLE_KM: Array[float] = [0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 120, 150, 200, 300]
const TABLE_RHO: Array[float] = [1.225, 0.4135, 0.08891, 0.01841, 0.003996, 0.001027, 3.097e-4,
	8.283e-5, 1.846e-5, 3.416e-6, 5.604e-7, 9.708e-8, 2.222e-8, 2.076e-9, 2.541e-10, 1.916e-11]


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

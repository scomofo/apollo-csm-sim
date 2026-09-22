// Procedural Moon: highlands, darker maria and crater speckle.
shader_type spatial;
#include "res://src/presentation/shaders/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 p = normalize(obj);
	float maria = smoothstep(0.5, 0.62, fbm(p * 1.6 + vec3(2.0), 5));
	float crater = fbm(p * 24.0, 4);
	float fine = fbm(p * 400.0, 4);
	float pits = smoothstep(0.62, 0.7, fbm(p * 1500.0, 2));
	vec3 col = base_color.rgb * mix(1.0, 0.5, maria) * (0.7 + 0.4 * crater) * (0.75 + 0.4 * fine) * (1.0 - 0.35 * pits);
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}

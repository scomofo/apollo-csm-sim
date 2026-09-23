// Procedural Moon: highlands, darker maria and crater speckle.
shader_type spatial;
#include "res://src/presentation/shaders/noise.gdshaderinc"
#include "res://src/presentation/shaders/moon_color.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.6, 0.6, 0.6, 1.0);
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	ALBEDO = moon_color(normalize(obj), base_color.rgb);
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}

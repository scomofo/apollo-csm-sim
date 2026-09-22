// Procedural Earth: oceans, continents, ice caps and clouds. Object-space
// noise, so the pattern turns with the planet (the mesh carries GMST).
shader_type spatial;
render_mode cull_back;
#include "res://src/presentation/shaders/noise.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.05, 0.18, 0.45, 1.0);
varying vec3 obj;

void vertex() {
	obj = VERTEX;
}

void fragment() {
	vec3 p = normalize(obj);
	float land = fbm(p * 2.2, 6);
	float lat = abs(p.z);
	vec3 ocean = base_color.rgb * (0.7 + 0.3 * fbm(p * 12.0, 3));
	land += 0.08 * (fbm(p * 60.0, 3) - 0.5);
	vec3 green = mix(vec3(0.16, 0.30, 0.10), vec3(0.45, 0.38, 0.22), smoothstep(0.45, 0.7, fbm(p * 5.0 + 3.0, 4)));
	float is_land = smoothstep(0.52, 0.55, land);
	vec3 col = mix(ocean, green, is_land);
	col = mix(col, vec3(0.92), smoothstep(0.82, 0.9, lat + 0.05 * fbm(p * 8.0, 3)));
	float cloud = smoothstep(0.55, 0.8, fbm(p * 4.0 + vec3(5.0), 6) + 0.12 * (fbm(p * 90.0, 3) - 0.5));
	col = mix(col, vec3(1.0), cloud * 0.85);
	ALBEDO = col;
	ROUGHNESS = mix(0.35, 0.9, max(is_land, cloud));
	SPECULAR = mix(0.6, 0.2, max(is_land, cloud));
}

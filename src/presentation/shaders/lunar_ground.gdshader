// The ground below Eagle (src/presentation/lunar_ground.gd), coloured as
// the Moon's sphere is, at each point's Moon-fixed direction. The grid
// carries it in UV as latitude and east longitude (rad); its relief is in
// the mesh.
shader_type spatial;
#include "res://src/presentation/shaders/noise.gdshaderinc"
#include "res://src/presentation/shaders/moon_color.gdshaderinc"

uniform vec4 base_color : source_color = vec4(0.42, 0.41, 0.4, 1.0);
varying vec3 dir;

void vertex() {
	float cl = cos(UV.x);
	dir = vec3(cl * sin(UV.y), sin(UV.x), cl * cos(UV.y));
}

void fragment() {
	ALBEDO = moon_color(normalize(dir), base_color.rgb);
	ROUGHNESS = 0.95;
	SPECULAR = 0.05;
}

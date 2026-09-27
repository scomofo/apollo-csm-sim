// Star field fixed in the inertial frame, plus the Sun's disc in the
// direction of the scene's directional light. The render axes are the
// cabin's (space_view.gd), so cabin_to_eci turns a view direction into ECI
// for the star lookup; the Sun disc stays in render axes, like the light.
// In the Earth's air by day the sky is blue over the stars, paler toward
// the horizon: air is how blue (space_view.gd sets it from the air's
// pressure and the Sun's height), zenith the local vertical in render axes.
shader_type sky;

uniform mat3 cabin_to_eci = mat3(1.0);
uniform float air = 0.0;
uniform vec3 zenith = vec3(0.0, 1.0, 0.0);

float h(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

void sky() {
	vec3 w = normalize(EYEDIR);
	vec3 d = normalize(cabin_to_eci * w);
	vec3 col = vec3(0.0);
	for (int layer = 0; layer < 2; layer++) {
		float scale = layer == 0 ? 180.0 : 420.0;
		vec3 c = floor(d * scale);
		float r = h(c + float(layer) * 17.0);
		if (r > (layer == 0 ? 0.992 : 0.985)) {
			vec3 center = (c + 0.5 + 0.35 * (vec3(h(c + 1.0), h(c + 2.0), h(c + 3.0)) - 0.5)) / scale;
			float dist = length(d - normalize(center)) * scale;
			float b = smoothstep(0.35, 0.0, dist) * (0.4 + 1.6 * h(c + 5.0));
			vec3 tint = mix(vec3(0.75, 0.82, 1.0), vec3(1.0, 0.85, 0.7), h(c + 9.0));
			col += tint * b * (layer == 0 ? 1.2 : 0.6);
		}
	}
	float up = clamp(dot(w, zenith), 0.0, 1.0);
	col = mix(col, mix(vec3(0.62, 0.74, 0.88), vec3(0.22, 0.42, 0.78), sqrt(up)), air);
	if (LIGHT0_ENABLED) {
		float s = dot(w, LIGHT0_DIRECTION);
		col += vec3(1.0, 0.97, 0.9) * (smoothstep(0.99996, 0.99999, s) * 40.0 + pow(max(s, 0.0), 800.0) * 0.6);
	}
	COLOR = col;
}

// Thin additive limb glow around the Earth, brighter on the day side.
shader_type spatial;
render_mode blend_add, unshaded, cull_front, depth_draw_never;

// Toward the Sun, in render (cabin) axes; space_view.gd sets it every frame.
uniform vec3 sun_dir = vec3(1.0, 0.0, 0.0);

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);
	float day = clamp(dot(-n, sun_dir) * 0.8 + 0.4, 0.05, 1.0);
	ALBEDO = vec3(0.3, 0.55, 1.0) * rim * day * 1.4;
}

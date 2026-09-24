// The Moon's colouring: highlands, darker maria and crater speckle, at the
// Moon-fixed direction p in the Moon sphere's mesh axes (X 90° E, Y the
// north pole, Z 0° N 0° E). moon.gdshader and lunar_ground.gdshader share
// it; include noise.gdshaderinc first.
vec3 moon_color(vec3 p, vec3 base) {
	float maria = smoothstep(0.5, 0.62, fbm(p * 1.6 + vec3(2.0), 5));
	float crater = fbm(p * 24.0, 4);
	float fine = fbm(p * 400.0, 4);
	float pits = smoothstep(0.62, 0.7, fbm(p * 1500.0, 2));
	return base * mix(1.0, 0.5, maria) * (0.7 + 0.4 * crater) * (0.75 + 0.4 * fine) * (1.0 - 0.35 * pits);
}

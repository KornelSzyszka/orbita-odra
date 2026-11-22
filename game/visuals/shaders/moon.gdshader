// Procedural grey cratered moon "Ślęża".
shader_type spatial;

#include "res://game/visuals/shaders/noise.gdshaderinc"

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = VERTEX;
}

void fragment() {
	vec3 p = normalize(sphere_dir);
	float base = fbm(p * 3.0, 6);
	float maria = smoothstep(0.52, 0.56, fbm(p * 1.5 + vec3(4.0), 4));
	// crater-like rings from cellular-ish noise
	float c = vnoise(p * 40.0);
	float rings = smoothstep(0.80, 0.86, c) - smoothstep(0.88, 0.95, c);
	vec3 col = mix(vec3(0.55, 0.54, 0.52), vec3(0.30, 0.30, 0.31), maria);
	col *= 0.8 + 0.4 * base;
	col += rings * 0.12;
	col *= 0.9 + 0.2 * vnoise(p * 600.0);
	ALBEDO = col;
	ROUGHNESS = 0.97;
	SPECULAR = 0.1;
}

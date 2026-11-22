// Cloud layer on a thin shell a few kilometres above the surface. Coverage is
// domain-warped fbm that drifts slowly; lighting is computed from the sun
// direction (soft terminator, warm rim at dusk) so the night side stays dark.
// Seen from below near the launch site it forms scattered clouds over the horizon.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://game/visuals/shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 launch_dir = vec3(0.0, 1.0, 0.0);
uniform float coverage = 0.5;
uniform float opacity = 0.85;
uniform float drift = 0.0008;   // [rad/s] slow rotation of the pattern

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = VERTEX;
}

void fragment() {
	vec3 p0 = normalize(sphere_dir);
	float a = TIME * drift;
	vec3 p = vec3(p0.x * cos(a) - p0.y * sin(a), p0.x * sin(a) + p0.y * cos(a), p0.z);
	float fw = length(fwidth(p)) + 1e-7;
	float f60 = 1.0 - smoothstep(0.25, 0.9, fw * 60.0);
	float f400 = 1.0 - smoothstep(0.25, 0.9, fw * 400.0);
	vec3 w = vec3(fbm(p * 2.5 + vec3(1.0), 3), fbm(p * 2.5 + vec3(5.0), 3), fbm(p * 2.5 + vec3(9.0), 3));
	float c = fbm(p * 6.0 + (w - 0.5) * 2.2, 5);
	c = c * 0.75 + fbm(p * 18.0 + w * 3.0, 3) * 0.25;
	// storm bands at mid latitudes, clearer subtropics
	float lat = abs(p.z);
	c += 0.07 * sin(lat * 14.0) + mix(0.0, (fbm(p * 60.0, 3) - 0.5) * 0.22, f60);
	c += mix(0.0, (vnoise(p * 400.0) - 0.5) * 0.08, f400);
	float thr = mix(0.66, 0.44, coverage);
	float cov = smoothstep(thr, thr + 0.07, c);
	// keep the immediate launch site mostly clear
	cov *= mix(1.0, 0.35, (1.0 - smoothstep(0.0, 0.03, distance(p0, launch_dir))));
	float mu = dot(p0, normalize(sun_dir));
	float lit = smoothstep(-0.10, 0.25, mu);
	float dusk = smoothstep(-0.10, 0.02, mu) * (1.0 - smoothstep(0.02, 0.25, mu));
	float shade = 0.72 + 0.28 * smoothstep(thr, thr + 0.25, c);
	vec3 col = mix(vec3(1.0), vec3(1.0, 0.55, 0.30), dusk * 0.8) * shade;
	ALBEDO = col * (0.03 + 0.97 * lit);
	ALPHA = cov * opacity;
}

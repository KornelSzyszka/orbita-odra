// Additive atmospheric scattering on a shell sphere (unit sphere in object
// space, scaled to planet_radius + atmosphere top). Each pixel intersects the
// view ray with the shell and the planet analytically and integrates a few
// samples of exponential density lit by the sun, so the limb glows, the haze
// thickens towards the horizon, the terminator turns orange and the night side
// stays dark. Rendered on the inner side (cull_front) so it works both from
// orbit and from inside the atmosphere.
shader_type spatial;
render_mode unshaded, blend_add, cull_front, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 glow_color : source_color = vec4(0.28, 0.55, 1.0, 1.0);
uniform vec4 sunset_color : source_color = vec4(1.0, 0.42, 0.16, 1.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float intensity = 1.0;
uniform float inner_ratio = 0.89;        // planet radius / shell radius
uniform float scale_ratio = 0.18;        // density scale height / shell thickness

varying vec3 obj_pos;
varying vec3 cam_obj;

void vertex() {
	obj_pos = VERTEX;
	float s = length(MODEL_MATRIX[0].xyz);
	cam_obj = (CAMERA_POSITION_WORLD - NODE_POSITION_WORLD) / s;
}

// returns (t_near, t_far) of a ray against a sphere at the origin; t_far < t_near = miss
vec2 sphere_hit(vec3 ro, vec3 rd, float r) {
	float b = dot(ro, rd);
	float c = dot(ro, ro) - r * r;
	float h = b * b - c;
	if (h < 0.0) {
		return vec2(1.0, -1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

void fragment() {
	vec3 ro = cam_obj;
	vec3 rd = normalize(obj_pos - cam_obj);
	vec2 outer = sphere_hit(ro, rd, 1.0);
	float t0 = max(outer.x, 0.0);
	float t1 = outer.y;
	vec2 inner = sphere_hit(ro, rd, inner_ratio);
	bool ground = inner.y > inner.x && inner.x > 0.0;
	if (ground) {
		t1 = min(t1, inner.x);
	}
	vec3 sd = normalize(sun_dir);
	float thick = 1.0 - inner_ratio;
	float hs = thick * scale_ratio;
	vec3 sum = vec3(0.0);
	float depth = 0.0;
	const int N = 8;
	float seg = max(t1 - t0, 0.0) / float(N);
	for (int i = 0; i < N; i++) {
		vec3 x = ro + rd * (t0 + seg * (float(i) + 0.5));
		float r = length(x);
		float dens = exp(-max(r - inner_ratio, 0.0) / hs);
		float mu = dot(x / r, sd);
		float lit = smoothstep(-0.12, 0.18, mu);
		float dusk = smoothstep(-0.12, 0.02, mu) * (1.0 - smoothstep(0.02, 0.30, mu));
		depth += dens * seg;
		vec3 c = mix(glow_color.rgb, sunset_color.rgb, dusk * 0.85);
		sum += c * dens * lit * seg * exp(-depth / (hs * 7.0));
	}
	// normalise: a grazing ray through the lowest layer ~= 1
	float norm = 1.0 / (hs * 9.0);
	vec3 col = sum * norm;
	// forward scattering around the sun
	float fwd = pow(max(dot(rd, sd), 0.0), 8.0);
	col *= 1.0 + fwd * 1.5;
	col = col / (1.0 + col * 0.35);
	ALBEDO = col * intensity * 1.35;
}

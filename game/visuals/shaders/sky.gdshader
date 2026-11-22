// Procedural space sky: three star layers with colour temperature, a galactic
// band with dust lanes and faint nebulae, the sun with a corona, and a daytime
// scattering sky (zenith/horizon gradient, sun halo, low-sun warm tint) that
// fades with the density of the air around the rocket.
shader_type sky;

#include "res://game/visuals/shaders/noise.gdshaderinc"

uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 up_dir = vec3(0.0, 1.0, 0.0);
uniform float air = 0.0;          // 0 = vacuum, 1 = sea level
uniform float star_gain = 1.0;

// One star per 3D cell of a direction lattice. `density` = cells per unit,
// `p` = probability of a star in a cell. Returns rgb.
vec3 star_layer(vec3 d, float density, float p, float seed, float size) {
	vec3 q = d * density;
	vec3 cell = floor(q);
	float h = hash13(cell + seed);
	if (h < 1.0 - p) {
		return vec3(0.0);
	}
	vec3 c = vec3(hash13(cell + seed + 1.7), hash13(cell + seed + 4.3), hash13(cell + seed + 8.1));
	vec3 off = fract(q) - (0.25 + 0.5 * c);
	float b = pow(hash13(cell + seed + 2.9), 3.0);           // most stars faint, a few bright
	float r = size * (0.55 + 0.9 * b);
	float core = 1.0 - smoothstep(0.0, r, length(off));
	float t = hash13(cell + seed + 6.6);
	vec3 col = t < 0.15 ? vec3(1.0, 0.72, 0.52) : (t < 0.45 ? vec3(1.0, 0.93, 0.82) : vec3(0.78, 0.86, 1.0));
	return col * core * (0.35 + 2.6 * b);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	vec3 sd_n = normalize(sun_dir);
	vec3 up = normalize(up_dir);

	// --- galaxy: tilted great circle with dust lanes and colour patches
	vec3 band_n = normalize(vec3(0.3, 0.2, 1.0));
	float bd = dot(d, band_n);
	float band = exp(-bd * bd * 14.0);
	float core = exp(-bd * bd * 60.0);
	float cloud = fbm(d * 5.0 + vec3(2.0), 5);
	float dust = smoothstep(0.50, 0.72, fbm(d * 9.0 + vec3(7.3, 1.1, 4.0), 5)) * core;
	float glow = band * (0.30 + 0.8 * cloud) * (1.0 - 0.45 * dust);
	vec3 gal = mix(vec3(0.16, 0.19, 0.34), vec3(0.42, 0.38, 0.40), core) * glow * 0.26;
	float neb1 = smoothstep(0.55, 0.85, fbm(d * 3.0 + vec3(11.0, 5.0, 2.0), 4)) * band;
	float neb2 = smoothstep(0.58, 0.85, fbm(d * 3.4 + vec3(3.0, 17.0, 9.0), 4)) * (0.3 + band);
	gal += vec3(0.55, 0.16, 0.30) * neb1 * 0.22 + vec3(0.10, 0.30, 0.42) * neb2 * 0.12;

	// --- stars: dense faint field (more of them inside the band) + sparse bright ones
	vec3 stars = star_layer(d, 620.0, 0.030 + 0.05 * band, 0.0, 0.32);
	stars += star_layer(d, 260.0, 0.020, 31.0, 0.26) * 1.2;
	stars += star_layer(d, 90.0, 0.012, 73.0, 0.16) * 2.4;
	vec3 space = gal + stars * star_gain;

	// --- sun disc + corona (visible from space and through air)
	float sd = dot(d, sd_n);
	float disc = smoothstep(0.99945, 0.99975, sd);
	vec3 sun = vec3(1.0, 0.96, 0.88) * (disc * 40.0 + pow(max(sd, 0.0), 900.0) * 3.0 + pow(max(sd, 0.0), 60.0) * 0.20);

	// --- scattering sky
	float sun_elev = dot(up, sd_n);
	float day = smoothstep(-0.18, 0.25, sun_elev);
	float elev = dot(d, up);
	float h = clamp(elev, 0.0, 1.0);
	vec3 zenith = vec3(0.10, 0.30, 0.78);
	vec3 horizon = vec3(0.62, 0.78, 0.98);
	vec3 blue = mix(horizon, zenith, pow(h, 0.45));
	// warm horizon on the sun side when the sun is low
	float low = 1.0 - smoothstep(0.0, 0.45, sun_elev);
	float toward = pow(max(dot(normalize(d - up * elev), normalize(sd_n - up * sun_elev + vec3(1e-4))), 0.0), 3.0);
	blue = mix(blue, vec3(1.0, 0.55, 0.28), low * toward * exp(-h * 9.0) * 0.8);
	// mie halo around the sun
	blue += vec3(1.0, 0.92, 0.78) * pow(max(sd, 0.0), 24.0) * 0.55;
	// below the horizon (behind terrain, seen at altitude): hazy ground colour
	blue = mix(blue, vec3(0.30, 0.38, 0.46), (1.0 - smoothstep(-0.08, 0.0, elev)));
	blue *= day;

	float a = clamp(air, 0.0, 1.0);
	// thin air: sky darkens towards the zenith first, haze stays at the horizon
	float thick = clamp(a * (1.0 + 2.5 * exp(-abs(elev) * 6.0) * (1.0 - a)), 0.0, 1.0) * day;
	vec3 col = mix(space, blue, thick);
	COLOR = col + sun * (1.0 - 0.6 * thick);
}

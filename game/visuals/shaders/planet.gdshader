// Procedural terrestrial planet "Odra": domain-warped continents, biomes by
// humidity/elevation/latitude, coastal shelves, mountains with snow, ice caps,
// glossy oceans and warm city lights on the night side. Clouds are a separate
// shell (clouds.gdshader). Climate axis = Z (orbit plane XY is the equator);
// the launch site at +Y is forced to land and gets a concrete launch complex.
// Detail octaves fade out with screen-space footprint, so the planet does not
// shimmer in the map view.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

#include "res://game/visuals/shaders/noise.gdshaderinc"

uniform vec3 local_offset = vec3(0.0);   // added to VERTEX (used by the launch-site patch)
uniform vec3 launch_dir = vec3(0.0, 1.0, 0.0);
uniform vec3 sun_dir = vec3(0.0, 1.0, 0.0);
uniform float planet_radius = 480000.0;  // [m] for metre-scale launch-site markings
uniform float city_lights = 1.0;

varying vec3 sphere_dir;

void vertex() {
	sphere_dir = VERTEX + local_offset;
}

float continent_field(vec3 p) {
	vec3 w = vec3(fbm(p * 1.7 + vec3(3.1, 0.0, 0.0), 3),
			fbm(p * 1.7 + vec3(0.0, 7.7, 0.0), 3),
			fbm(p * 1.7 + vec3(1.3, 9.2, 4.4), 3));
	return fbm(p * 2.1 + (w - 0.5) * 1.3, 6);
}

void fragment() {
	vec3 p = normalize(sphere_dir);
	// screen-space footprint of one unit of p -> octave fade factors
	float fw = length(fwidth(p)) + 1e-7;
	float f900 = 1.0 - smoothstep(0.25, 0.9, fw * 900.0);
	float f7000 = 1.0 - smoothstep(0.25, 0.9, fw * 7000.0);
	float f90 = 1.0 - smoothstep(0.25, 0.9, fw * 90.0);

	float cont = continent_field(p);
	float pad_d = distance(p, launch_dir);
	cont += (1.0 - smoothstep(0.0, 0.22, pad_d)) * 0.30;
	float land = smoothstep(0.500, 0.506, cont);
	float elev = smoothstep(0.505, 0.74, cont);

	float mid = mix(0.5, fbm(p * 90.0, 3), f90);
	float detail = mix(0.5, fbm(p * 900.0, 3), f900) * 0.65 + mix(0.5, vnoise(p * 7000.0), f7000) * 0.35;
	float hum = fbm(p * 5.0 + vec3(5.0), 4) + (mid - 0.5) * 0.25;
	float lat = abs(p.z);
	float temp = 1.0 - lat * 1.15 - elev * 0.5;

	// ocean: deep -> shelf -> turquoise shallows
	vec3 deep = vec3(0.008, 0.035, 0.11);
	vec3 shelf = vec3(0.02, 0.12, 0.26);
	vec3 shallow = vec3(0.05, 0.30, 0.38);
	vec3 ocean = mix(deep, shelf, smoothstep(0.38, 0.48, cont));
	ocean = mix(ocean, shallow, smoothstep(0.485, 0.50, cont) * 0.8);

	// land biomes
	vec3 forest = vec3(0.05, 0.15, 0.05);
	vec3 grass = vec3(0.16, 0.30, 0.09);
	vec3 steppe = vec3(0.42, 0.40, 0.20);
	vec3 desert = vec3(0.70, 0.55, 0.33);
	vec3 tundra = vec3(0.36, 0.36, 0.30);
	vec3 rock = vec3(0.34, 0.30, 0.27);
	vec3 sand = vec3(0.72, 0.65, 0.46);
	vec3 ground = mix(desert, steppe, smoothstep(0.36, 0.48, hum));
	ground = mix(ground, grass, smoothstep(0.47, 0.56, hum));
	ground = mix(ground, forest, smoothstep(0.58, 0.68, hum) * (0.6 + 0.4 * detail));
	ground = mix(ground, tundra, (1.0 - smoothstep(0.22, 0.38, temp)));
	ground *= 0.82 + 0.36 * detail;
	ground = mix(ground, rock * (0.8 + 0.4 * detail), smoothstep(0.55, 0.80, elev));
	float snowline = smoothstep(0.86, 0.95, elev + (detail - 0.5) * 0.08 + lat * 0.25);
	ground = mix(ground, vec3(0.90, 0.92, 0.95), snowline);
	ground = mix(sand, ground, smoothstep(0.500, 0.512, cont));   // beaches

	vec3 col = mix(ocean, ground, land);
	float ice = smoothstep(0.86, 0.90, lat + (fbm(p * 12.0, 3) - 0.5) * 0.10);
	col = mix(col, vec3(0.86, 0.90, 0.95), ice);

	// --- launch complex (metre-scale markings, only resolvable on the patch)
	float m = pad_d * planet_radius;           // [m] from the pad centre
	vec3 east = vec3(-1.0, 0.0, 0.0);
	vec3 north = vec3(0.0, 0.0, 1.0);
	float ex = dot(p - launch_dir, east) * planet_radius;
	float nz = dot(p - launch_dir, north) * planet_radius;
	float site = step(m, 2500.0);
	if (site > 0.0) {
		vec3 grass_site = mix(vec3(0.20, 0.30, 0.11), vec3(0.30, 0.34, 0.15), detail);
		col = mix(col, grass_site, (1.0 - smoothstep(600.0, 1400.0, m)) * 0.7);
		float apron = (1.0 - smoothstep(44.0, 46.0, m));
		float scorch = (1.0 - smoothstep(18.0, 40.0, m)) * 0.55;
		float road = (1.0 - smoothstep(3.5, 4.5, abs(nz))) * step(30.0, ex) * step(ex, 1900.0);
		float road2 = (1.0 - smoothstep(2.5, 3.5, abs(ex - 420.0))) * step(-600.0, nz) * step(nz, 0.0);
		float yard = step(abs(ex - 420.0), 60.0) * step(abs(nz + 640.0), 45.0);
		vec3 concrete = vec3(0.55, 0.55, 0.53) * (0.88 + 0.24 * detail);
		col = mix(col, concrete, max(max(apron, yard), max(road, road2)));
		col = mix(col, vec3(0.10, 0.09, 0.08), scorch * apron);
		// painted ring and centre lines
		float ring = (1.0 - smoothstep(0.15, 0.45, abs(m - 30.0))) * apron * step(0.5, fract(atan(nz, ex) * 9.549));
		col = mix(col, vec3(0.85, 0.62, 0.12), ring * 0.85);
		float stripe = (1.0 - smoothstep(0.1, 0.35, abs(nz))) * step(fract(ex / 12.0), 0.5) * road;
		col = mix(col, vec3(0.92, 0.92, 0.85), stripe);
	}

	ALBEDO = col;
	float wet = (1.0 - land) * (1.0 - ice);
	ROUGHNESS = mix(0.92, 0.22, wet);
	SPECULAR = mix(0.3, 0.7, wet);

	// --- night side: warm city lights on habitable, temperate land
	float ndl = dot(p, normalize(sun_dir));
	float night = (1.0 - smoothstep(-0.14, 0.06, ndl));
	if (night > 0.0 && city_lights > 0.0) {
		float habitable = land * (1.0 - ice) * (1.0 - snowline) * smoothstep(0.30, 0.50, temp)
				* (1.0 - smoothstep(0.45, 0.62, elev)) * smoothstep(0.34, 0.48, hum);
		float f400 = 1.0 - smoothstep(0.25, 0.9, fw * 400.0);
		float region = smoothstep(0.42, 0.62, fbm(p * 14.0 + vec3(2.0, 5.0, 1.0), 3));
		float towns = smoothstep(0.52, 0.85, vnoise(p * 70.0)) * (0.55 + 0.45 * mix(0.5, vnoise(p * 400.0), f400));
		float coast = (1.0 - smoothstep(0.502, 0.53, cont)) * land;   // coasts are denser
		float lights = habitable * clamp(region * 0.8 + coast * 0.9, 0.0, 1.0) * towns;
		EMISSION = vec3(1.0, 0.66, 0.30) * lights * night * 3.2 * city_lights;
	}
}

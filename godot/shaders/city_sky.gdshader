shader_type sky;
// Blue-hour atmosphere: one quiet crescent, with no competing solar disc.
uniform vec3 zenith_color : source_color = vec3(0.025, 0.09, 0.23);
uniform vec3 horizon_color : source_color = vec3(0.23, 0.43, 0.57);
uniform vec3 horizon_afterglow : source_color = vec3(0.43, 0.40, 0.43);
uniform vec3 moon_color : source_color = vec3(0.76, 0.86, 0.92);
uniform vec3 moon_direction = vec3(0.186, 0.225, -0.956);
uniform float moon_radius = 0.016;
// Defaults preserve the established blue-hour scene. Review cycle opts in.
uniform float moon_visibility = 1.0;
uniform float star_visibility = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}
float noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(cell), hash(cell + vec3(1,0,0)), f.x),
		mix(hash(cell + vec3(0,1,0)), hash(cell + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash(cell + vec3(0,0,1)), hash(cell + vec3(1,0,1)), f.x),
		mix(hash(cell + vec3(0,1,1)), hash(cell + vec3(1,1,1)), f.x), f.y), f.z);
}
void sky() {
	vec3 ray = normalize(EYEDIR);
	float elevation = max(ray.y, 0.0);
	float gradient = pow(clamp(elevation * 2.1, 0.0, 1.0), 0.6);
	vec3 atmosphere = mix(horizon_color, zenith_color, gradient);
	// Last light stays at the horizon, leaving the satellite's sky uncluttered.
	float afterglow = exp(-elevation * 24.0) * 0.34;
	atmosphere = mix(atmosphere, horizon_afterglow, afterglow);
	if (ray.y < 0.0) {
		atmosphere = mix(horizon_color, vec3(0.015, 0.025, 0.045), smoothstep(0.0, 0.3, -ray.y));
	}
	// Sparse, broad cirrus wisps add depth without a painted cloud backdrop.
	vec3 cloud_p = ray * vec3(9.0, 32.0, 9.0);
	float cloud = noise(cloud_p) * 0.68 + noise(cloud_p * 2.1) * 0.32;
	float cloud_band = smoothstep(0.03, 0.10, elevation) * (1.0 - smoothstep(0.28, 0.48, elevation));
	float wisps = smoothstep(0.66, 0.86, cloud) * cloud_band * 0.035;
	atmosphere += vec3(0.35, 0.45, 0.58) * wisps;

	vec3 direction = normalize(moon_direction);
	vec3 right = normalize(cross(vec3(0,1,0), direction));
	vec3 up = cross(direction, right);
	vec2 uv = vec2(dot(ray, right), dot(ray, up)) / sin(moon_radius);
	float radius2 = dot(uv, uv);
	float disc = (1.0 - smoothstep(0.97, 1.03, radius2)) * step(0.99, dot(ray, direction));
	vec3 normal = vec3(uv, sqrt(max(0.0, 1.0 - radius2)));
	// Light arrives from the low horizon: a softly shaded lower-right crescent.
	float illumination = max(dot(normal, normalize(vec3(0.55,-0.65,-0.52))), 0.0);
	float terrain = 0.90 + 0.10 * noise(normal * 21.0);
	vec3 lunar_surface = mix(atmosphere * 0.93, moon_color * terrain, smoothstep(0.0, 0.22, illumination));
	float stars = 0.0;
	if (star_visibility > 0.0) {
		stars = pow(hash(floor(ray * 1800.0)), 1100.0) * smoothstep(0.04, 0.18, ray.y);
	}
	COLOR = mix(atmosphere, lunar_surface, disc * moon_visibility) + vec3(0.65,0.78,0.95) * stars * star_visibility * 0.45;
}

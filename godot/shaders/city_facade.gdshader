shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 body_color : source_color = vec4(0.08, 0.15, 0.21, 1.0);
uniform vec4 light_color : source_color = vec4(0.25, 0.65, 0.8, 1.0);
uniform float occupancy = 0.65;
uniform float seed = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7)) + seed) * 43758.5453); }
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
	vec2 facade = vec2(abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x, world_pos.y);
	vec2 cell = facade / vec2(2.2, 3.6);
	vec2 f = fract(cell);
	vec2 aa = max(fwidth(cell), vec2(0.001));
	float window = smoothstep(0.14, 0.14 + aa.x, f.x) * (1.0 - smoothstep(0.83 - aa.x, 0.83, f.x));
	window *= smoothstep(0.25, 0.25 + aa.y, f.y) * (1.0 - smoothstep(0.78 - aa.y, 0.78, f.y));
	float wall = 1.0 - smoothstep(0.4, 0.7, abs(world_normal.y));
	window *= wall;
	float random = hash(floor(cell));
	float lit = step(1.0 - occupancy, random) * window;
	float floor_band = (1.0 - smoothstep(0.04, 0.07 + aa.y, f.y)) * wall;
	ALBEDO = mix(body_color.rgb, vec3(0.025, 0.065, 0.085), window * 0.8);
	ALBEDO += floor_band * vec3(0.035, 0.05, 0.06);
	METALLIC = mix(0.55, 0.35, window);
	ROUGHNESS = mix(0.4, 0.23, window);
	vec3 room = mix(light_color.rgb, vec3(0.7, 0.48, 0.24), step(0.94, random));
	EMISSION = room * lit * (0.3 + random * 0.65);
}

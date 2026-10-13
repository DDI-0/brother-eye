shader_type spatial;

uniform vec4 tint : source_color = vec4(0.08, 0.14, 0.22, 1.0);
uniform float metal : hint_range(0.0, 1.0) = 0.85;
uniform float rough : hint_range(0.0, 1.0) = 0.35;
uniform float uv_scale = 0.1;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D metallic_roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool pavement = false;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	// Triplanar blend weights
	vec3 blend = pow(abs(world_normal), vec3(4.0));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	float scale = pavement ? 0.06 : uv_scale;
	vec2 uv_x = world_pos.zy * scale;
	vec2 uv_y = world_pos.xz * scale;
	vec2 uv_z = world_pos.xy * scale;

	vec4 col_x = texture(albedo_texture, uv_x);
	vec4 col_y = texture(albedo_texture, uv_y);
	vec4 col_z = texture(albedo_texture, uv_z);
	vec4 tex_albedo = col_x * blend.x + col_y * blend.y + col_z * blend.z;

	vec4 mr_x = texture(metallic_roughness_texture, uv_x);
	vec4 mr_y = texture(metallic_roughness_texture, uv_y);
	vec4 mr_z = texture(metallic_roughness_texture, uv_z);
	vec4 tex_mr = mr_x * blend.x + mr_y * blend.y + mr_z * blend.z;

	// In glTF PBR standard: G channel = Roughness, B channel = Metallic
	float tex_roughness = tex_mr.g;
	float tex_metallic = tex_mr.b;

	// Subtle panel line micro-grid for futuristic plating definition
	vec2 tile = (world_normal.y > 0.6 ? world_pos.xz : (abs(world_normal.x) > abs(world_normal.z) ? world_pos.zy : world_pos.xy)) / (pavement ? vec2(2.5) : vec2(3.5, 4.5));
	vec2 edge = min(fract(tile), 1.0 - fract(tile));
	vec2 aa = max(fwidth(tile), vec2(0.001));
	float seam = min(smoothstep(0.003, 0.003 + aa.x, edge.x), smoothstep(0.004, 0.004 + aa.y, edge.y));

	// Preserve the material tint so roads and foundations remain distinct from metal facades.
	vec3 base_color = tex_albedo.rgb * (tint.rgb * 0.85 + vec3(0.10)) * 1.2;
	ALBEDO = base_color * mix(0.8, 1.18, seam);
	METALLIC = clamp(tex_metallic * metal, 0.4, 0.88);
	ROUGHNESS = clamp(tex_roughness * rough * 1.1, 0.18, 0.65);
}

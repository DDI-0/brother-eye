shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform sampler2D mr_tex : hint_default_white, filter_linear_mipmap;

uniform vec4 chrome_color : source_color = vec4(0.38, 0.46, 0.55, 1.0);
uniform vec4 glass_color : source_color = vec4(0.03, 0.06, 0.10, 1.0);
uniform vec4 neon_color : source_color = vec4(0.05, 0.90, 1.0, 1.0);
uniform float metallic_val : hint_range(0.0, 1.0) = 0.96;
uniform float roughness_val : hint_range(0.0, 1.0) = 0.18;
uniform float normal_depth : hint_range(0.0, 5.0) = 2.2;
uniform float neon_intensity : hint_range(0.0, 10.0) = 2.2;

varying vec3 v_world_pos;
varying vec3 v_world_norm;
varying float v_local_y;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_norm = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	v_local_y = VERTEX.y;
}

void fragment() {
	vec4 raw_albedo = texture(albedo_tex, UV);
	vec3 norm_sample = texture(normal_tex, UV).rgb;
	
	// Unpack normal map & apply enhanced depth
	NORMAL_MAP = norm_sample;
	NORMAL_MAP_DEPTH = normal_depth;

	// Distinguish chrome ribs from recessed window cavities
	float cavity = clamp(raw_albedo.b * 1.5 - raw_albedo.r * 0.35, 0.0, 1.0);
	float edge_factor = length(norm_sample.xy - vec2(0.5)) * 2.4;

	// High-contrast gleaming titanium-chrome hull with dark tinted glass recesses
	vec3 base_col = mix(glass_color.rgb, chrome_color.rgb, smoothstep(0.18, 0.62, cavity));
	
	ALBEDO = base_col;
	METALLIC = mix(0.5, metallic_val, smoothstep(0.2, 0.65, cavity));
	ROUGHNESS = mix(0.16, roughness_val, smoothstep(0.25, 0.75, cavity));

	// Cyberpunk neon edge conduits along the spiral ribbons & fresnel rim
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.8);
	float ribbon_neon = smoothstep(0.6, 0.96, edge_factor) * 0.55;

	vec3 emission_glow = neon_color.rgb * (fresnel * 0.35 + ribbon_neon) * neon_intensity;
	EMISSION = emission_glow;
	
	RIM = 0.7;
	RIM_TINT = 0.5;
}

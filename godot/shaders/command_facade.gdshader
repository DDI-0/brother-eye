shader_type spatial;
// World-space panel coordinates remain consistent across structural pieces.
uniform vec4 tint : source_color = vec4(0.12,0.15,0.18,1.0);
uniform float metal = 0.65;
uniform float roughness = 0.48;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX*NORMAL);
}
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
	vec2 p = abs(world_normal.x)>0.6 ? world_pos.zy : world_pos.xy;
	if (abs(world_normal.y)>0.6) { p = world_pos.xz; }
	vec2 panel = p / vec2(2.5,4.0);
	vec2 edge = min(fract(panel),1.0-fract(panel));
	vec2 aa = max(fwidth(panel),vec2(0.0001));
	float joint = 1.0-min(smoothstep(0.002,0.002+aa.x,edge.x),smoothstep(0.002,0.002+aa.y,edge.y));
	float variation = hash(floor(panel));
	float runoff = (1.0-smoothstep(0.0,0.09,fract(panel.y)))*0.08;
	ALBEDO = tint.rgb*(0.88+variation*0.24)*(1.0-joint*0.42-runoff);
	METALLIC = metal;
	ROUGHNESS = clamp(roughness+variation*0.12+joint*0.16,0.0,1.0);
}

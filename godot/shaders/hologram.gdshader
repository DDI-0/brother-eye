shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float clock = 0.0;
varying vec3 local_pos;
varying vec3 radial_view;
void vertex() {
	local_pos = VERTEX;
	radial_view = (MODELVIEW_MATRIX * vec4(normalize(VERTEX),0.0)).xyz;
}
void fragment() {
	float longitude = atan(local_pos.x,local_pos.z);
	float age = mod(clock * 1.05 - longitude + 6.283185,6.283185);
	float trail = exp(-age*3.2);
	float beam = exp(-age*age*180.0);
	float front = smoothstep(-0.15,0.55,dot(normalize(radial_view),normalize(VIEW)));
	float depth = mix(0.12,1.0,front);
	float twinkle = 0.82 + 0.18*sin(clock*3.8+COLOR.g*100.0);
	float brightness = COLOR.r*twinkle + COLOR.b*(trail*1.2+beam*1.6);
	float equator = (1.0-smoothstep(0.0,0.035,abs(local_pos.y)))*0.16*(0.7+0.3*sin(clock*3.0));
	vec3 cyan = mix(vec3(0.015,0.55,0.82),vec3(0.22,0.94,1.0),beam);
	ALBEDO = cyan*(brightness+equator)*2.0;
	EMISSION = cyan*(brightness+equator)*2.0;
	ALPHA = depth;
}

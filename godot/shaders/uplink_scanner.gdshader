shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
uniform float clock = 0.0;
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float age = mod(clock*1.05-atan(local_pos.x,local_pos.z)+6.283185,6.283185);
	float leading_edge = exp(-age*age*1600.0);
	float sector = exp(-age*9.0);
	float facing = mix(0.15,1.0,smoothstep(0.0,0.6,dot(normalize(NORMAL),normalize(VIEW))));
	ALBEDO = vec3(0.0,0.7,1.0);
	ALPHA = (leading_edge*.22+sector*.045)*facing;
}

shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float scan = pow(max(0.0,sin(UV.y*65.0+TIME*8.0)),12.0);
	ALBEDO = vec3(0.0,0.6,0.95);
	EMISSION = vec3(0.0,0.6,0.95);
	ALPHA = (rim*.07+scan*.025)*sin(UV.y*3.14159);
}

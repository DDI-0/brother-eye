shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 tint : source_color = vec4(0.0,0.65,1.0,0.3);
varying vec3 local_pos;
void vertex() { local_pos = VERTEX; }
void fragment() {
	float scan = 0.55 + 0.45*sin(local_pos.y*75.0-TIME*2.0);
	float edge = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
	ALBEDO = tint.rgb;
	EMISSION = tint.rgb*1.2;
	ALPHA = tint.a*(0.25+scan*0.45+edge*0.7);
}

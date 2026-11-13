shader_type spatial;
// Additive version of particle.gdshader (glow, sparks, muzzle flashes).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D uMap : source_color, filter_linear_mipmap;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	vec4 t = texture(uMap, UV);
	float a = t.a * COLOR.a;
	if (a < 0.01) discard;
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * t.rgb * a;
	ALPHA = a;
}

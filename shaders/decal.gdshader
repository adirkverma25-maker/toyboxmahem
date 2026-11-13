shader_type spatial;
// Bullet holes and paint splats (port of Effects.ts DECAL_VS/FS): texture alpha x per-instance alpha,
// tinted with the instance color.
render_mode unshaded, depth_draw_never, cull_back, shadows_disabled;

uniform sampler2D uMap : source_color, filter_linear_mipmap;
varying float v_alpha;

void vertex() {
	v_alpha = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec4 t = texture(uMap, UV);
	float a = t.a * v_alpha;
	if (a < 0.01) discard;
	ALBEDO = pow(COLOR.rgb, vec3(2.2));
	ALPHA = a;
}

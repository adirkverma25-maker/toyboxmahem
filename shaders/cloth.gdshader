// Cloth panel with gentle sway (blankets, curtains, drapes). Port of swayCloth() in Arena.ts:
// the plane hangs from its top edge (y = 0 at the top, -height at the bottom) and waves in z.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_tex = false;
uniform vec4 albedo : source_color = vec4(1.0);
uniform float roughness = 0.95;
uniform float width = 4.0;
uniform float height = 18.0;
uniform float amp = 0.35;
uniform float speed = 0.9;
uniform float sag = 0.0;
uniform float phase = 0.0;

float disp(vec2 p) {
	float k = min(1.0, -p.y / height);
	float wave = sin(TIME * speed + p.x * 0.6 + phase) * 0.6 + sin(TIME * speed * 1.7 + p.x * 1.3 + phase * 2.0) * 0.4;
	return wave * amp * k * k + sag * sin((p.x / width + 0.5) * PI) * (1.0 - k * 0.3);
}

void vertex() {
	vec2 p = VERTEX.xy;
	float z = disp(p);
	float e = 0.05;
	float dx = (disp(p + vec2(e, 0.0)) - z) / e;
	float dy = (disp(p + vec2(0.0, e)) - z) / e;
	VERTEX.z += z;
	NORMAL = normalize(vec3(-dx, -dy, 1.0));
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) c *= texture(albedo_tex, UV);
	ALBEDO = c.rgb;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
}

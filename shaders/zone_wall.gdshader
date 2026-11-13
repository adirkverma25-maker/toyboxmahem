shader_type spatial;
// Soft striped cylinder wall for capture zones (port of HillZone.ts WALL_FS).
render_mode unshaded, depth_draw_never, cull_disabled, shadows_disabled;

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uTime = 0.0;
uniform float uAlpha = 1.0;

void fragment() {
	vec2 vUv = vec2(UV.x, 1.0 - UV.y);
	float fade = pow(1.0 - vUv.y, 1.6);
	float stripes = 0.65 + 0.35 * sin(vUv.x * 120.0 + uTime * 3.0);
	float rise = 0.5 + 0.5 * sin(vUv.y * 18.0 - uTime * 4.0);
	float a = (fade * 0.42 + fade * rise * 0.18 + 0.04) * stripes * uAlpha;
	ALBEDO = uColor;
	ALPHA = clamp(a, 0.0, 1.0);
}

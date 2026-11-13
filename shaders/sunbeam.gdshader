shader_type spatial;
// Sunbeam volume from the window (port of Ambient.ts BEAM_FS): fades in from the floor and out near the ceiling.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

uniform float uTime = 0.0;
uniform float uStrength = 1.0;
varying vec3 vWorld;

void vertex() {
	vWorld = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float h = smoothstep(0.0, 9.0, vWorld.y) * (1.0 - smoothstep(22.0, 27.0, vWorld.y));
	float streak = 0.75 + 0.25 * sin(vWorld.x * 0.9 + vWorld.z * 0.4 + uTime * 0.3);
	float a = 0.045 * h * streak * uStrength;
	ALBEDO = vec3(1.0, 0.86, 0.62) * a;
	ALPHA = a;
}

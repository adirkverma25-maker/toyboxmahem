shader_type spatial;
// Mesh Shield: hexagon wire mesh with a bright rim, ripple on hits and a fade in/out (port of Barriers.ts FS).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uTime = 0.0;
uniform float uAlpha = 0.0;
uniform float uFlash = 0.0;
uniform float uHealth = 1.0;
uniform vec2 uSize = vec2(2.8, 2.2);

float hexDist(vec2 p) {
	p = abs(p);
	return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}

void fragment() {
	vec2 vUv = vec2(UV.x, 1.0 - UV.y);
	vec2 p = (vUv - 0.5) * uSize * 3.2;
	vec2 r = vec2(1.0, 1.7320508);
	vec2 h = r * 0.5;
	vec2 a = mod(p, r) - h;
	vec2 b = mod(p - h, r) - h;
	vec2 g = dot(a, a) < dot(b, b) ? a : b;
	float d = hexDist(g);
	float wire = smoothstep(0.42, 0.5, d);
	vec2 e = min(vUv, 1.0 - vUv) * uSize;
	float rim = 1.0 - smoothstep(0.0, 0.09, min(e.x, e.y));
	float scan = 0.5 + 0.5 * sin(vUv.y * 40.0 - uTime * 6.0);
	float crack = (1.0 - uHealth) * step(0.75, fract(sin(dot(floor(p * 1.3), vec2(12.9898, 78.233))) * 43758.5453));
	float a2 = wire * (0.55 + 0.2 * scan) + rim * 0.9 + 0.06 + uFlash * 0.5 - crack * 0.2;
	vec3 col = mix(uColor, vec3(1.0), rim * 0.4 + uFlash * 0.6);
	float alpha = clamp(a2, 0.0, 1.0) * uAlpha;
	ALBEDO = col * alpha;
	ALPHA = alpha;
}

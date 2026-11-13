shader_type canvas_item;
// HUD screen effects (styles.css .vignette, .hurtflash, .shieldflash, .cloak-fx).
uniform float vignette = 0.0;
uniform float hurt = 0.0;
uniform float shield = 0.0;
uniform float cloak = 0.0;
uniform vec2 aspect = vec2(1.0, 1.0);

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = length(p);
	// red vignette: transparent to 55% of the radius, crimson at the corners
	float v = smoothstep(0.55, 1.0, r / 1.4142 * 1.414) * 0.55 * vignette;
	// inset glows from the screen edges
	vec2 e = min(UV, 1.0 - UV) * aspect;
	float edge = min(e.x, e.y);
	float hurtg = (1.0 - smoothstep(0.0, 0.12, edge)) * 0.6 * hurt;
	float shg = (1.0 - smoothstep(0.0, 0.14, edge)) * 0.55 * shield;
	float clk = ((1.0 - smoothstep(0.0, 0.22, edge)) * 0.42 + smoothstep(0.55, 1.0, r) * 0.12) * cloak;
	vec4 c = vec4(0.0);
	c = mix(c, vec4(220.0 / 255.0, 20.0 / 255.0, 60.0 / 255.0, 1.0), clamp(v, 0.0, 1.0));
	c = mix(c, vec4(1.0, 60.0 / 255.0, 80.0 / 255.0, 1.0), clamp(hurtg, 0.0, 1.0));
	c = mix(c, vec4(90.0 / 255.0, 200.0 / 255.0, 250.0 / 255.0, 1.0), clamp(shg, 0.0, 1.0));
	c = mix(c, vec4(110.0 / 255.0, 190.0 / 255.0, 1.0, 1.0), clamp(clk, 0.0, 1.0));
	c.a = clamp(v + hurtg + shg + clk, 0.0, 1.0);
	COLOR = c;
}

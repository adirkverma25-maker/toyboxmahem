shader_type spatial;
// Conquest flag: waves along its length (port of the per-vertex wave in SectorZones.ts).
render_mode cull_disabled;

uniform vec3 uColor : source_color = vec3(1.0);
uniform float uTime = 0.0;
uniform float uPhase = 0.0;

void vertex() {
	float x = VERTEX.x;
	VERTEX.z = sin(x * 3.0 - uTime * 6.0 + uPhase) * 0.08 * x;
}

void fragment() {
	ALBEDO = uColor;
	ROUGHNESS = 0.7;
	EMISSION = uColor * 0.25;
}

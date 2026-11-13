class_name Lighting
## Light helpers. three.js (physically based units) and Godot use different light scales; these factors
## convert the original numbers so maps can keep the values from the TypeScript code.

const POINT_SCALE := 0.11
const SUN_SCALE := 0.36


static func sun(root: Node3D, color: String, intensity: float, dir: Vector3, extent: float) -> DirectionalLight3D:
	var l := DirectionalLight3D.new()
	l.light_color = U.col(color)
	l.light_energy = intensity * SUN_SCALE
	l.shadow_enabled = true
	l.shadow_bias = 0.04
	l.shadow_normal_bias = 1.2
	l.shadow_blur = 1.5
	# one shadow map over the room, like the original's single orthographic sun shadow
	l.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	l.directional_shadow_max_distance = extent * 1.6
	root.add_child(l)
	var target := Vector3(2, 0, -4)
	l.look_at_from_position(target - dir * 90.0, target, Vector3.UP)
	return l


## World environment shared by every map: tonemapping, fog, glow (bloom), ambient light.
static func environment(sky: Dictionary) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = U.col(sky.background)
	if sky.has("hemi"):
		# three.js HemisphereLight: sky color from above, ground color from below
		var h: Array = sky.hemi
		var top := U.col(h[0])
		var ground := U.col(h[1])
		var psm := ProceduralSkyMaterial.new()
		psm.sky_top_color = top
		psm.sky_horizon_color = top.lerp(ground, 0.5)
		psm.ground_bottom_color = ground
		psm.ground_horizon_color = top.lerp(ground, 0.5)
		psm.sun_angle_max = 0.0
		psm.sky_energy_multiplier = 1.0
		var sk := Sky.new()
		sk.sky_material = psm
		e.sky = sk
		e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
		e.ambient_light_energy = h[2] * 0.9
		e.ambient_light_sky_contribution = 1.0
		e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	else:
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = U.col(sky.get("ambient", "#fff1dc"))
		e.ambient_light_energy = sky.get("ambient_energy", 0.55)
		e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = sky.get("exposure", 1.0)
	e.tonemap_white = 6.0
	var fog: Array = sky.fog
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = U.col(fog[0])
	e.fog_depth_begin = fog[1]
	e.fog_depth_end = fog[2]
	e.fog_depth_curve = 1.0
	e.fog_density = 1.0
	e.fog_sky_affect = 0.0
	e.glow_enabled = true
	e.glow_intensity = 0.5
	e.glow_strength = 0.9
	e.glow_bloom = 0.04
	e.glow_hdr_threshold = 1.1
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	return e

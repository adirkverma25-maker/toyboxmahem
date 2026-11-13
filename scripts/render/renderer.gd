class_name Renderer
extends Node
## World + viewmodel rendering and quality tiers (port of src/render/Renderer.ts).
##  low    - no shadows, no post FX, reduced resolution
##  medium - soft shadows, bloom, 2x MSAA
##  high   - sharper shadows, bloom, ambient occlusion, 4x MSAA
## The viewmodel renders in its own World3D (SubViewport layered over the game view) so it never clips.

var world := Node3D.new()
var camera := Camera3D.new()
var env := WorldEnvironment.new()
var cam_attr := CameraAttributesPractical.new()
var vm_layer := CanvasLayer.new()
var vm_container := SubViewportContainer.new()
var vm_viewport := SubViewport.new()
var vm_camera := Camera3D.new()
var vm_root := Node3D.new()
var quality := "high"
var menu_blur := false
var motion_blur := false
var sun: DirectionalLight3D = null
var point_lights: Array = []


func _init() -> void:
	name = "Renderer"
	world.name = "World"
	camera.fov = 90
	camera.near = 0.05
	camera.far = 400
	camera.attributes = cam_attr
	world.add_child(camera)
	world.add_child(env)
	# viewmodel world: its own scene, lights and camera (fov 62, near 0.01)
	vm_layer.layer = 1
	vm_container.stretch = true
	vm_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vm_viewport.own_world_3d = true
	vm_viewport.transparent_bg = true
	vm_viewport.handle_input_locally = false
	vm_container.add_child(vm_viewport)
	vm_layer.add_child(vm_container)
	vm_camera.fov = 62
	vm_camera.near = 0.01
	vm_camera.far = 10
	vm_viewport.add_child(vm_camera)
	vm_viewport.add_child(vm_root)
	var vm_env := WorldEnvironment.new()
	vm_env.environment = Lighting.environment({"background": "#000000", "fog": ["#000000", 1000.0, 2000.0], "exposure": 0.98, "hemi": ["#fff1dc", "#7a5a40", 1.6]})
	vm_env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vm_env.environment.fog_enabled = false
	vm_env.environment.glow_enabled = false
	vm_viewport.add_child(vm_env)
	var key := DirectionalLight3D.new()
	key.light_color = U.col("#ffe2b8")
	key.light_energy = 2.4 * Lighting.SUN_SCALE
	vm_viewport.add_child(key)
	key.look_at_from_position(Vector3(-1, 2, 1.5), Vector3.ZERO, Vector3.UP)
	var rim := DirectionalLight3D.new()
	rim.light_color = U.col("#b8d8ff")
	rim.light_energy = 1.2 * Lighting.SUN_SCALE
	vm_viewport.add_child(rim)
	rim.look_at_from_position(Vector3(1.5, 0.5, -1), Vector3.ZERO, Vector3.UP)


func attach(parent: Node) -> void:
	parent.add_child(self)
	parent.add_child(world)
	parent.add_child(vm_layer)
	camera.make_current()


func set_sky(sky: Dictionary) -> void:
	env.environment = Lighting.environment(sky)
	env.environment.tonemap_exposure = sky.exposure
	set_quality(quality)


func set_quality(q: String) -> void:
	quality = q
	var vp := get_viewport()
	var e := env.environment
	vp.msaa_3d = Viewport.MSAA_4X if q == "high" else (Viewport.MSAA_2X if q == "medium" else Viewport.MSAA_DISABLED)
	vm_viewport.msaa_3d = vp.msaa_3d
	vp.scaling_3d_scale = 0.8 if q == "low" else 1.0
	RenderingServer.directional_shadow_atlas_set_size(4096 if q == "high" else 2048, q == "high")
	if sun:
		sun.shadow_enabled = q != "low"
		sun.shadow_blur = 1.0 if q == "high" else 1.6
	# dim side lights on low to save fragment cost
	for l in point_lights:
		if is_instance_valid(l):
			(l as Light3D).visible = q != "low" or (l as Light3D).light_energy > 15 * Lighting.POINT_SCALE
	if e:
		e.glow_enabled = q != "low"
		e.ssao_enabled = q == "high"
		e.ssao_radius = 1.2
		e.ssao_intensity = 1.6
	_apply_blur()


func set_menu_blur(on: bool) -> void:
	menu_blur = on
	_apply_blur()


func _apply_blur() -> void:
	var on := menu_blur and quality != "low"
	cam_attr.dof_blur_far_enabled = on
	cam_attr.dof_blur_far_distance = 26
	cam_attr.dof_blur_far_transition = 18
	cam_attr.dof_blur_near_enabled = on
	cam_attr.dof_blur_near_distance = 8
	cam_attr.dof_blur_near_transition = 5
	cam_attr.dof_blur_amount = 0.06


func set_motion_blur(on: bool) -> void:
	motion_blur = on


func set_viewmodel_visible(v: bool) -> void:
	vm_layer.visible = v


func _process(_dt: float) -> void:
	# the viewmodel camera has the same aspect as the world camera (SubViewportContainer stretches)
	pass

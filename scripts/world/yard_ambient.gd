class_name YardAmbient
extends Node3D
## Backyard background life (port of src/world/YardAmbient.ts): drifting clouds and butterflies. No hazards.
## Shares the bedroom ambient's interface: update / block_drop / clear_blocks / start_sounds / stop_sounds.

var ambience_on := false
var clouds: Array = []
var flies: Array = []
var t := 0.0
var reduced := false


func _init() -> void:
	name = "Ambient"
	var dot := Tex.soft_dot()
	for i in 14:
		var s := Sprite3D.new()
		s.texture = dot
		s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		var big := 26.0 + (i % 4) * 9
		s.pixel_size = big / 64.0
		s.scale = Vector3(2.1, 1, 1)
		s.modulate = Color(1, 1, 1, 0.85)
		s.shaded = false
		s.transparent = true
		s.fixed_size = false
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.billboard_keep_scale = true
		m.albedo_texture = dot
		m.albedo_color = Color(1, 1, 1, 0.85)
		m.disable_fog = true
		m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		s.material_override = m
		s.position = Vector3(-150 + ((i * 53) % 300), 62 + (i % 5) * 9, -150 + ((i * 97) % 300))
		add_child(s)
		clouds.append(s)
	var cols := ["#ff9f1c", "#ffd23f", "#9b5de5", "#48cae4", "#ff5d8f", "#ffffff"]
	for i in 9:
		var g := Node3D.new()
		var mat := Mats.basic(cols[i % cols.size()], null, false, true)
		var wings := []
		for s in [-1, 1]:
			var w := Geo.circle(0.28, 8).translate(0.26, 0, 0).mesh_instance(mat, Vector3.ZERO, Basis(), false)
			w.set_meta("side", s)
			g.add_child(w)
			wings.append(w)
		add_child(g)
		flies.append({"g": g, "wings": wings, "c": Vector3(-26 + ((i * 17) % 52), 0, -26 + ((i * 29) % 52)), "r": 3 + (i % 4) * 1.6, "sp": 0.5 + (i % 3) * 0.22, "ph": i * 1.7, "h": 3 + (i % 5) * 1.5})


func update(dt: float, _actors := [], _hurt := Callable(), _listener := Vector3.ZERO) -> void:
	t += dt
	for c in clouds:
		c.position.x += dt * 1.6
		if c.position.x > 160:
			c.position.x = -160
	var k := 0.4 if reduced else 1.0
	for f in flies:
		var a: float = t * f.sp * k + f.ph
		var g: Node3D = f.g
		g.position = Vector3(f.c.x + cos(a) * f.r, f.h + sin(a * 2.3) * 0.8, f.c.z + sin(a * 1.3) * f.r)
		g.rotation.y = -a
		var flap: float = sin(t * 22 * k + f.ph) * 0.9
		for i in 2:
			var w: Node3D = f.wings[i]
			var s: float = w.get_meta("side")
			w.basis = U.euler(-PI / 2, flap if i == 0 else -flap, 0).scaled_local(Vector3(s, 1, 1))


func block_drop(_nav = null, _count := 8, _spots = null) -> Array:
	return []


func clear_blocks() -> void:
	pass


func start_sounds() -> void:
	pass


func stop_sounds() -> void:
	pass


func set_reduced_motion(r: bool) -> void:
	reduced = r

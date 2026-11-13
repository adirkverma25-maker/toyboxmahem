class_name AmbientBedroom
extends Node3D
## Living room details (port of src/world/Ambient.ts): toy train on the high shelf, wind-up robots, rc cars,
## ceiling fan shadow, sunbeam dust, volcano smoke, the wall clock, falling building blocks and ambient sounds.

const BEAM_SHADER := preload("res://shaders/sunbeam.gdshader")

var arena: Dictionary
var phys: Phys
var fx: Effects
var audio
var train_curve: CRSpline
var train_cars: Array = []
var train_u := 0.0
var train_speed := 6.0
var train_stop_t := 0.0
var train_wheels: Array = []
var fan_blades := Node3D.new()
var fan_shadow: MeshInstance3D
var beam_mat: ShaderMaterial
var dust: Effects.ParticlePool
var dust_vel := PackedVector3Array()
var rc: Array = []
var robots: Array = []
var clock_hands := {}
var clock_pos: Vector3
var timers := {"tick": 0.0, "creak": U.rand(8, 20), "wind": U.rand(4, 10), "whistle": U.rand(20, 40), "chug": 0.0, "bird": U.rand(3, 8), "smoke": U.rand(4, 9), "clatter": U.rand(8, 16), "smokeOn": 0.0}
var tock := false
var blocks: Array = []
var warnings: Array = []
var block_mats: Array = []
var block_mesh: ArrayMesh
var time := 0.0
var ambience_on := false
var sounds_on := false
var reduced := false


func _init(a: Dictionary, ph: Phys, effects: Effects, aud) -> void:
	name = "Ambient"
	arena = a
	phys = ph
	fx = effects
	audio = aud
	var R: Dictionary = ArenaBedroom.ROOM
	var S: Dictionary = ArenaBedroom.SHELF
	clock_pos = Vector3(-24, 15, R.z1 - 0.3)
	# ------------------------------------------------ train track on the shelf
	var y: float = S.y + 0.02
	var ix: float = R.x1 - S.track_inset
	var iz: float = R.z1 - S.track_inset
	var r := 1.0
	var pts := []
	for c in [[ix - r, iz - r, 0.0], [-ix + r, iz - r, PI / 2], [-ix + r, -iz + r, PI], [ix - r, -iz + r, PI * 1.5]]:
		for i in 5:
			var ang: float = c[2] + float(i) / 4 * (PI / 2)
			pts.append(Vector3(c[0] + cos(ang) * r, y, c[1] + sin(ang) * r))
	train_curve = CRSpline.new(pts, true, "centripetal")
	_build_track()
	_build_train()
	# ------------------------------------------------ ceiling fan + fake rotating shadow over the sun patch
	var fan := Node3D.new()
	fan.position = Vector3(2, R.h, 1)
	fan.add_child(Geo.cylinder(0.15, 0.15, 2.4, 10).mesh_instance(Mats.metal("#d9d9d9"), Vector3(0, -1.2, 0)))
	fan.add_child(Geo.cylinder(0.9, 0.7, 0.8, 24).mesh_instance(Mats.plastic("#ffffff", {"rough": 0.4}), Vector3(0, -2.6, 0)))
	fan_blades.position.y = -2.8
	var blade_mat := Mats.plastic("#e9d8bf", {"rough": 0.6, "clearcoat": 0.0})
	for i in 4:
		fan_blades.add_child(Geo.rounded_box(5.5, 0.12, 1.3, 2, 0.05).mesh_instance(blade_mat, Vector3(cos(i * PI / 2) * 3.4, 0, sin(i * PI / 2) * 3.4), U.euler(0.12, -i * PI / 2, 0, "XYZ")))
	fan.add_child(fan_blades)
	add_child(fan)
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_texture = Tex.fan_shadow()
	sm.albedo_color = Color(0, 0, 0, 0.35)
	sm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	sm.render_priority = 1
	fan_shadow = Geo.plane(18, 18).mesh_instance(sm, Vector3(10, 0.1, -2), Basis(Vector3.RIGHT, -PI / 2), false)
	add_child(fan_shadow)
	# ------------------------------------------------ sunbeam volume + dust motes
	var W: Dictionary = arena.window
	var d: Vector3 = arena.sun_dir
	var proj := func(p: Vector3) -> Vector3: return p + d * (p.y / -d.y)
	var corners := [Vector3(W.x0, W.y0, W.z + 0.2), Vector3(W.x1, W.y0, W.z + 0.2), Vector3(W.x1, W.y1, W.z + 0.2), Vector3(W.x0, W.y1, W.z + 0.2)]
	var verts := corners.duplicate()
	for c in corners:
		verts.append(proj.call(c))
	var idx := [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7]
	var g := Geo.new()
	var k := 0
	while k < idx.size():
		g._tri(verts[idx[k]], verts[idx[k + 1]], verts[idx[k + 2]], Vector3.UP, Vector3.UP, Vector3.UP, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO)
		k += 3
	beam_mat = ShaderMaterial.new()
	beam_mat.shader = BEAM_SHADER
	beam_mat.render_priority = 4
	var beam := g.mesh_instance(beam_mat, Vector3.ZERO, Basis(), false)
	beam.extra_cull_margin = 100
	add_child(beam)
	dust = Effects.ParticlePool.new(420, true)
	add_child(dust.node)
	dust_vel.resize(420)
	for i in 420:
		var p := _random_beam_point()
		dust.emit(p, Vector3.ZERO, U.col("#fff1d0"), 0.09, 1e9, {"alpha": 0.85})
		dust_vel[i] = Vector3(U.rand(-0.05, 0.05), U.rand(-0.03, 0.03), U.rand(-0.05, 0.05))
	# ------------------------------------------------ rc cars on the garage track
	for i in 2:
		var car := _build_rc_car("#ff006e" if i == 0 else "#3a86ff")
		add_child(car)
		var body := phys.kinematic_box(Vector3(0, -20, 0), Vector3(0.55, 0.4, 0.95), "plastic")
		rc.append({"group": car, "body": body, "angle": i * PI, "speed": 0.95 if i == 0 else 0.8, "pos": Vector3.ZERO, "yaw": 0.0, "hum": null})
	# ------------------------------------------------ wind-up robots
	var sill: float = R.z0 + 1.2
	robots.append(_build_robot("#e63946", Vector3(-5, 12, sill), Vector3(9, 12, sill)))
	# two more patrol the shelf walkway (they shove toys out of the way)
	var walk: float = S.depth - 1.0
	robots.append(_build_robot("#3a86ff", Vector3(-26, S.y, R.z1 - walk), Vector3(-8, S.y, R.z1 - walk)))
	robots.append(_build_robot("#06d6a0", Vector3(R.x0 + walk, S.y, -22), Vector3(R.x0 + walk, S.y, 8)))
	# ------------------------------------------------ wall clock
	_build_clock()
	# block materials
	for cl in [["#e63946", "A"], ["#2a9d8f", "B"], ["#f4a261", "C"], ["#457b9d", "D"], ["#8ab17d", "E"]]:
		var col: String = cl[0]
		var letter: String = cl[1]
		var t := Tex.make("dropblock" + letter, 128, 128, func(ci: CanvasItem):
			ci.draw_rect(Rect2(0, 0, 128, 128), Color("#e8cfa5"))
			ci.draw_rect(Rect2(10, 10, 108, 108), Color(col))
			Tex.text(ci, Tex.FONT_TITLE, letter, 64, 70, 80, Color.WHITE)
		, {"placeholder": Color(col)})
		block_mats.append(Mats.textured(t, 0.55))
	block_mesh = Geo.rounded_box(1.6, 1.6, 1.6, 2, 0.12).to_mesh()


func _random_beam_point() -> Vector3:
	var W: Dictionary = arena.window
	var d: Vector3 = arena.sun_dir
	var p := Vector3(U.rand(W.x0, W.x1), U.rand(W.y0, W.y1), W.z + 0.3)
	return p + d * U.rand(0.5, p.y / -d.y)


func _build_track() -> void:
	var N := 600
	var rails := [[], []]
	for i in N:
		var u := float(i) / N
		var p := train_curve.get_point_at(u)
		var t := train_curve.get_tangent_at(u)
		var side := t.cross(Vector3.UP).normalized()
		var a := p + side * 0.28
		a.y = p.y + 0.12
		var b := p - side * 0.28
		b.y = p.y + 0.12
		rails[0].append(a)
		rails[1].append(b)
	var rail_mat := Mats.metal("#b8bcc4", 0.3)
	for r in rails:
		var closed: Array = r.duplicate()
		closed.append(r[0])
		add_child(Geo.tube(closed, N, 0.04, 5).mesh_instance(rail_mat, Vector3.ZERO, Basis(), false))
	var count := floori(train_curve.get_length() / 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = Geo.box(0.85, 0.08, 0.18).to_mesh(Mats.std("#7b4a2a", 0.8))
	mm.instance_count = count
	for i in count:
		var u := float(i) / count
		var p := train_curve.get_point_at(u)
		var t := train_curve.get_tangent_at(u)
		mm.set_instance_transform(i, Transform3D(Effects.DecalPool._face(t), p + Vector3(0, 0.04, 0)))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	add_child(mi)


func _build_train() -> void:
	var colors := ["#d62828", "#f77f00", "#2a9d8f", "#3a86ff"]
	for i in 4:
		var g := Node3D.new()
		var c := Mats.plastic(colors[i], {"rough": 0.25})
		var body_len := 2.2 if i == 0 else 1.8
		g.add_child(Geo.rounded_box(1.1, 0.9, body_len, 2, 0.15).mesh_instance(c, Vector3(0, 0.75, 0)))
		if i == 0:
			g.add_child(Geo.cylinder(0.45, 0.45, 1.3, 18).mesh_instance(Mats.plastic("#1d3557"), Vector3(0, 1.0, 0.45), Basis(Vector3.RIGHT, PI / 2)))
			g.add_child(Geo.cylinder(0.18, 0.12, 0.6, 12).mesh_instance(Mats.plastic("#222222"), Vector3(0, 1.6, 0.8)))
			g.add_child(Geo.rounded_box(1.1, 0.8, 0.8, 2, 0.12).mesh_instance(c, Vector3(0, 1.55, -0.6)))
			g.add_child(Geo.sphere(0.14, 10, 8).mesh_instance(Mats.glow("#fff3b0", 3), Vector3(0, 1.0, 1.15)))
		else:
			# cargo: blocks / balls
			var cg := Geo.sphere(0.4, 14, 10) if i == 2 else Geo.rounded_box(0.7, 0.6, 0.9, 2, 0.1)
			g.add_child(cg.mesh_instance(Mats.plastic(U.pick(["#ffbe0b", "#8338ec", "#06d6a0"])), Vector3(0, 1.5, 0)))
		for z in [-body_len * 0.3, body_len * 0.3]:
			for x in [-0.5, 0.5]:
				var w := Geo.cylinder(0.22, 0.22, 0.12, 14).mesh_instance(Mats.rubber("#111111"), Vector3(x, 0.3, z), Basis(Vector3.BACK, PI / 2))
				g.add_child(w)
				train_wheels.append(w)
		add_child(g)
		train_cars.append(g)


func _build_rc_car(color: String) -> Node3D:
	var g := Node3D.new()
	g.add_child(Geo.rounded_box(1.1, 0.45, 1.9, 2, 0.15).mesh_instance(Mats.plastic(color, {"rough": 0.2, "clearcoat": 1.0}), Vector3(0, 0.45, 0)))
	g.add_child(Geo.rounded_box(0.9, 0.35, 0.8, 2, 0.12).mesh_instance(Mats.plastic("#111827", {"rough": 0.1}), Vector3(0, 0.8, -0.1)))
	g.add_child(Geo.box(1.1, 0.06, 0.3).mesh_instance(Mats.plastic("#ffbe0b"), Vector3(0, 0.95, -0.85)))
	g.add_child(Geo.cylinder(0.015, 0.015, 0.8, 6).mesh_instance(Mats.metal("#cccccc"), Vector3(0.35, 1.1, -0.6)))
	for z in [-0.6, 0.6]:
		for x in [-0.55, 0.55]:
			g.add_child(Geo.cylinder(0.28, 0.28, 0.25, 16).mesh_instance(Mats.rubber("#1d1d1d"), Vector3(x, 0.28, z), Basis(Vector3.BACK, PI / 2)))
	return g


func _build_robot(color: String, a: Vector3, b: Vector3) -> Dictionary:
	var g := Node3D.new()
	var c := Mats.plastic(color, {"rough": 0.3, "metal": 0.2})
	g.add_child(Geo.rounded_box(0.7, 0.8, 0.5, 2, 0.08).mesh_instance(c, Vector3(0, 0.9, 0)))
	g.add_child(Geo.rounded_box(0.55, 0.45, 0.45, 2, 0.08).mesh_instance(Mats.metal("#c0c6d0", 0.3), Vector3(0, 1.55, 0)))
	for x in [-0.12, 0.12]:
		g.add_child(Geo.sphere(0.06, 8, 6).mesh_instance(Mats.glow("#fff07a", 2.5), Vector3(x, 1.6, 0.23)))
	var legs := []
	for x in [-0.18, 0.18]:
		var leg := Node3D.new()
		leg.position = Vector3(x, 0.5, 0)
		leg.add_child(Geo.rounded_box(0.18, 0.5, 0.22, 2, 0.05).mesh_instance(Mats.metal("#8d99ae", 0.4), Vector3(0, -0.25, 0)))
		g.add_child(leg)
		legs.append(leg)
	var key := Node3D.new()
	key.position = Vector3(0, 1.0, -0.3)
	var gold := Mats.metal("#d4af37")
	key.add_child(Geo.cylinder(0.04, 0.04, 0.25, 8).mesh_instance(gold, Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2)))
	key.add_child(Geo.torus(0.15, 0.04, 6, 16).mesh_instance(gold, Vector3(0, 0, -0.18)))
	g.add_child(key)
	g.position = a
	add_child(g)
	return {"group": g, "legs": legs, "key": key, "a": a, "b": b, "t": randf(), "dir": 1.0, "speed": U.rand(0.6, 0.9), "pause": 0.0}


func _build_clock() -> void:
	var g := Node3D.new()
	g.add_child(Geo.cylinder(2.2, 2.2, 0.3, 40).mesh_instance(Mats.plastic("#ffffff", {"rough": 0.4}), Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2)))
	g.add_child(Geo.torus(2.2, 0.22, 10, 40).mesh_instance(Mats.plastic("#ef476f")))
	for i in 12:
		var ang := float(i) / 12 * TAU
		g.add_child(Geo.box(0.12, 0.45 if i % 3 == 0 else 0.25, 0.05).mesh_instance(Mats.plastic("#1d3557"), Vector3(sin(ang) * 1.8, cos(ang) * 1.8, -0.18), Basis(Vector3.BACK, -ang)))
	var hand := func(length: float, w: float, col: String) -> Node3D:
		var h := Node3D.new()
		h.add_child(Geo.box(w, length, 0.05).mesh_instance(Mats.plastic(col), Vector3(0, length / 2 - 0.15, 0)))
		h.position.z = -0.22
		g.add_child(h)
		return h
	clock_hands = {"h": hand.call(1.1, 0.14, "#1d3557"), "m": hand.call(1.6, 0.09, "#1d3557"), "s": hand.call(1.7, 0.04, "#e63946")}
	g.transform = Transform3D(Basis(Vector3.UP, PI), clock_pos)
	add_child(g)


## Falling block event: marks landing spots, then drops wooden blocks from the ceiling.
func block_drop(nav: NavGraph, count := 8, spots = null) -> Array:
	var used := []
	for i in count:
		var p = null
		if spots != null:
			p = spots[i] if i < spots.size() else null
		else:
			var id := nav.random(func(n): return n.pos.y < 0.5 and n.open >= 7)
			if id >= 0 and id < nav.nodes.size():
				p = nav.nodes[id].pos
		if p == null:
			continue
		used.append(p)
		var m := Zones.ring_material("#ff4d4d", 0.0)
		var ring := Geo.ring(0.2, 1.1, 32).mesh_instance(m, Vector3(p.x, p.y + 0.06, p.z), Basis(Vector3.RIGHT, -PI / 2), false)
		add_child(ring)
		warnings.append({"ring": ring, "mat": m, "pos": p, "t": -i * 0.35, "dropped": false})
	return used


func _spawn_block(p: Vector3) -> void:
	var body := phys.dynamic_box(Vector3(p.x, 26, p.z), Vector3(0.8, 0.8, 0.8), "wood", 0.8, U.euler(U.rand(0, 1), U.rand(0, 3), U.rand(0, 1)))
	body.linear_velocity = Vector3(0, -6, 0)
	body.angular_velocity = Vector3(U.rand(-2, 2), U.rand(-2, 2), U.rand(-2, 2))
	var mesh := MeshInstance3D.new()
	mesh.mesh = block_mesh
	mesh.material_override = U.pick(block_mats)
	body.add_child(mesh)
	blocks.append({"mesh": mesh, "body": body, "life": 40.0, "hit": {}, "landed": false})


func clear_blocks() -> void:
	for b in blocks:
		(b.body as Node).queue_free()
	blocks = []
	for w in warnings:
		(w.ring as Node).queue_free()
	warnings = []


func start_sounds() -> void:
	if sounds_on:
		return
	sounds_on = true
	for c in rc:
		c.hum = audio.motor_loop(c.pos)


func stop_sounds() -> void:
	sounds_on = false
	for c in rc:
		if c.hum:
			c.hum.stop()
		c.hum = null


func set_reduced_motion(r: bool) -> void:
	reduced = r


func update(dt: float, actors: Array, hurt: Callable, listener: Vector3) -> void:
	time += dt
	var t := time
	var shelf_y: float = ArenaBedroom.SHELF.y
	# train: runs, pauses at the "station" now and then
	var length := train_curve.get_length()
	if train_stop_t > 0:
		train_stop_t -= dt
	else:
		train_u = fmod(train_u + train_speed * dt / length, 1.0)
		if randf() < dt * 0.01:
			train_stop_t = U.rand(4, 9)
	for i in train_cars.size():
		var car: Node3D = train_cars[i]
		var u := fmod(train_u - i * 2.4 / length + 1, 1.0)
		var p := train_curve.get_point_at(u)
		var tan := train_curve.get_tangent_at(u)
		car.position = p
		car.rotation = Vector3(0, atan2(tan.x, tan.z), 0)
	if train_stop_t <= 0:
		for w in train_wheels:
			(w as Node3D).rotate(Vector3.RIGHT, dt * train_speed * 4)
		# the train shoves toys off its track (toward the room side)
		for i in train_cars.size():
			var car: Node3D = train_cars[i]
			var yaw := car.rotation.y
			var fxv := sin(yaw)
			var fzv := cos(yaw)
			var sx := fzv
			var sz := -fxv
			var hl := (1.1 if i == 0 else 0.9) + 0.42
			var hw := 0.55 + 0.42
			var inward := signf((2 - car.position.x) * sx + (1 - car.position.z) * sz)
			if inward == 0:
				inward = 1
			for a in actors:
				if not a.alive or absf(a.pos.y - shelf_y) > 1.3:
					continue
				var dx: float = a.pos.x - car.position.x
				var dz: float = a.pos.z - car.position.z
				var lf := dx * fxv + dz * fzv
				var ls := dx * sx + dz * sz
				if absf(lf) > hl or absf(ls) > hw:
					continue
				var push := inward * hw - ls
				a.pos.x += sx * push + fxv * 0.05
				a.pos.z += sz * push + fzv * 0.05
				a.vel.x += sx * inward * 2.5 + fxv * train_speed * 0.4
				a.vel.z += sz * inward * 2.5 + fzv * train_speed * 0.4
				a.sync()
	# fan
	fan_blades.rotation.y += dt * (1.2 if reduced else 2.6)
	fan_shadow.basis = Basis(Vector3.RIGHT, -PI / 2) * Basis(Vector3.BACK, fan_blades.rotation.y)
	beam_mat.set_shader_parameter("uTime", t)
	# dust
	for i in 420:
		var p := dust.pos[i]
		var v := dust_vel[i]
		p.x += (v.x + sin(t * 0.3 + i * 3) * 0.02) * dt
		p.y += (v.y + sin(t * 0.21 + i * 3 * 0.7) * 0.015) * dt
		p.z += v.z * dt
		if p.y < 0.3 or p.y > 27 or randf() < dt * 0.01:
			p = _random_beam_point()
		dust.pos[i] = p
		dust.vel[i] = Vector3.ZERO
	dust.dirty = true
	dust.update(0)
	# rc cars
	for c in rc:
		c.angle += dt * c.speed
		var x: float = 17 + cos(c.angle) * 8.4
		var z: float = 18.5 + sin(c.angle) * 4.2
		var tx: float = -sin(c.angle) * 8.4
		var tz: float = cos(c.angle) * 4.2
		c.yaw = atan2(tx, tz)
		c.pos = Vector3(x, 0, z)
		var cg: Node3D = c.group
		cg.position = c.pos
		cg.rotation = Vector3(0, c.yaw, sin(t * 20) * 0.01)
		(c.body as AnimatableBody3D).global_transform = Transform3D(Basis(Vector3.UP, c.yaw), Vector3(x, 0.45, z))
		if c.hum:
			c.hum.move(c.pos + Vector3(0, 0.5, 0), Vector2(tx, tz).length() * c.speed)
		# bump toys out of the way
		var cs := cos(-c.yaw)
		var sn := sin(-c.yaw)
		for a in actors:
			if not a.alive or a.pos.y > 1.2:
				continue
			var dx: float = a.pos.x - x
			var dz: float = a.pos.z - z
			var lx := dx * cs + dz * sn
			var lz := -dx * sn + dz * cs
			var hx := 0.55 + 0.42
			var hz := 0.95 + 0.42
			if absf(lx) < hx and absf(lz) < hz:
				var px := hx - absf(lx)
				var pz := hz - absf(lz)
				var ox := 0.0
				var oz := 0.0
				if px < pz:
					ox = signf(lx) * px
				else:
					oz = signf(lz) * pz
				var wx: float = ox * cos(c.yaw) + oz * sin(c.yaw)
				var wz: float = -ox * sin(c.yaw) + oz * cos(c.yaw)
				a.pos.x += wx
				a.pos.z += wz
				a.vel.x += wx * 8 + sin(c.yaw) * 2
				a.vel.z += wz * 8 + cos(c.yaw) * 2
				a.sync()
	# robots
	for r in robots:
		var rg: Node3D = r.group
		if r.pause > 0:
			r.pause -= dt
			(r.key as Node3D).rotation.z += dt * 1
			continue
		var L: float = (r.a as Vector3).distance_to(r.b)
		r.t += r.dir * r.speed * dt / L
		if r.t > 1 or r.t < 0:
			r.dir *= -1
			r.t = clampf(r.t, 0, 1)
			r.pause = U.rand(1, 3)
		rg.position = (r.a as Vector3).lerp(r.b, r.t)
		for a in actors:
			if not a.alive or absf(a.pos.y - rg.position.y) > 1.2:
				continue
			var dx: float = a.pos.x - rg.position.x
			var dz: float = a.pos.z - rg.position.z
			var d := Vector2(dx, dz).length()
			var mn := 0.42 + 0.4
			if d >= mn:
				continue
			var nx := dx / d if d > 1e-3 else 1.0
			var nz := dz / d if d > 1e-3 else 0.0
			a.pos.x += nx * (mn - d)
			a.pos.z += nz * (mn - d)
			a.sync()
		var dir: Vector3 = ((r.b as Vector3) - (r.a as Vector3)) * r.dir
		rg.rotation.y = atan2(dir.x, dir.z)
		(r.legs[0] as Node3D).rotation.x = sin(t * 9) * 0.5
		(r.legs[1] as Node3D).rotation.x = -sin(t * 9) * 0.5
		rg.position.y += absf(sin(t * 9)) * 0.05
		(r.key as Node3D).rotation.z += dt * 6
	# clock (game time)
	if not clock_hands.is_empty():
		var sec := floorf(t)
		(clock_hands.s as Node3D).rotation.z = -(sec / 60) * TAU
		(clock_hands.m as Node3D).rotation.z = -((t / 3600) * TAU + 1.1)
		(clock_hands.h as Node3D).rotation.z = -((t / 43200) * TAU + 4.3)
	# block-drop warnings and falling blocks
	for i in range(warnings.size() - 1, -1, -1):
		var w: Dictionary = warnings[i]
		w.t += dt
		if w.t > 0:
			(w.mat as StandardMaterial3D).albedo_color.a = minf(0.75, w.t) * (0.7 + sin(w.t * 14) * 0.3)
			(w.ring as Node3D).scale = Vector3.ONE * (0.6 + minf(1, w.t / 1.5) * 0.6)
		if w.t > 1.6 and not w.dropped:
			w.dropped = true
			_spawn_block(w.pos)
		if w.t > 3:
			(w.ring as Node).queue_free()
			warnings.remove_at(i)
	for i in range(blocks.size() - 1, -1, -1):
		var b: Dictionary = blocks[i]
		var body: RigidBody3D = b.body
		var p := body.global_position
		var v := body.linear_velocity
		if v.y < -7:
			for a in actors:
				if not a.alive or b.hit.has(a.id):
					continue
				var dx: float = a.pos.x - p.x
				var dz: float = a.pos.z - p.z
				if dx * dx + dz * dz < 1.5 and p.y - 0.8 < a.pos.y + 1.8 and p.y + 0.8 > a.pos.y:
					b.hit[a.id] = true
					hurt.call(a, 40.0, p)
		elif not b.landed and p.y < 3 and absf(v.y) < 3:
			b.landed = true
			audio.block_land(p)
			fx.impact(p - Vector3(0, 0.8, 0), Vector3.UP, "wood", {"big": true, "decal": false})
		b.life -= dt
		if b.life < 1:
			(b.mesh as Node3D).scale = Vector3.ONE * maxf(0.01, b.life)
		if b.life <= 0 or p.y < -5:
			body.queue_free()
			blocks.remove_at(i)
	# volcano smoke + embers
	timers.smoke -= dt
	if timers.smoke <= 0:
		timers.smoke = U.rand(7, 14)
		timers.smokeOn = 2.5
		if ambience_on:
			audio.rumble(Vector3(-23, 8, 29))
	if timers.smokeOn > 0:
		timers.smokeOn -= dt
		if randf() < dt * 30:
			fx.soft.emit(Vector3(-23 + U.rand(-0.6, 0.6), 7.6, 29 + U.rand(-0.6, 0.6)), Vector3(U.rand(-0.3, 0.3), U.rand(1.5, 2.5), U.rand(-0.3, 0.3)), U.col(U.pick(["#e9e3dc", "#cfc7be", "#f7f2ec"])), U.rand(1.2, 2), U.rand(2.5, 4), {"grow": 1.4, "drag": 0.4, "alpha": 0.55})
		if randf() < dt * 25:
			fx.glow.emit(Vector3(-23, 7.4, 29), Vector3(U.rand(-1.5, 1.5), U.rand(3, 6), U.rand(-1.5, 1.5)), U.col(U.pick(["#ff7b00", "#ffb703", "#ff4d00"])), U.rand(0.1, 0.2), U.rand(0.8, 1.4), {"gravity": 4})
	# ambient sound beats
	if ambience_on:
		_ambient_sounds(dt, listener)


func _ambient_sounds(dt: float, listener: Vector3) -> void:
	var tm := timers
	tm.tick -= dt
	if tm.tick <= 0:
		tm.tick += 1
		tock = not tock
		audio.clock_tick(clock_pos, tock)
	tm.creak -= dt
	if tm.creak <= 0:
		tm.creak = U.rand(14, 32)
		audio.creak(audio.random_creak_spot())
	tm.wind -= dt
	if tm.wind <= 0:
		tm.wind = U.rand(6, 14)
		audio.wind_up((U.pick(robots).group as Node3D).position)
	var engine: Vector3 = (train_cars[0] as Node3D).position
	tm.whistle -= dt
	if tm.whistle <= 0:
		tm.whistle = U.rand(30, 60)
		audio.train_whistle(engine)
	if train_stop_t <= 0 and engine.distance_to(listener) < 40:
		tm.chug -= dt
		if tm.chug <= 0:
			tm.chug = 0.36
			audio.train_chug(engine)
	tm.bird -= dt
	if tm.bird <= 0:
		tm.bird = U.rand(4, 9)
		audio.bird(Vector3(U.rand(-31, -8), U.rand(4, 9), U.rand(13, 35)))
	tm.clatter -= dt
	if tm.clatter <= 0:
		tm.clatter = U.rand(10, 22)
		audio.clatter(Vector3(U.rand(-30, -14), 1, U.rand(-6, 9)))

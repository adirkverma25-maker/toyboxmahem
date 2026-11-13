class_name Zones
## Objective visuals: HillZone (the giant toy box for Toy Box Takeover) and SectorZones (the Conquest sectors)
## (ports of HillZone.ts and SectorZones.ts).

const WALL_SHADER := preload("res://shaders/zone_wall.gdshader")
const FLAG_SHADER := preload("res://shaders/flag.gdshader")
const NEUTRAL := "#fff6d8"
const CONTESTED := "#ff4d8d"


static func wall_material(color: String, alpha: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WALL_SHADER
	m.set_shader_parameter("uColor", U.col(color))
	m.set_shader_parameter("uAlpha", alpha)
	m.render_priority = 5
	return m


static func ring_material(color: String, opacity: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var c := U.col(color)
	c.a = opacity
	m.albedo_color = c
	m.render_priority = 5
	return m


## The giant toy box capture zone for Toy Box Takeover.
class HillZone extends Node3D:
	var wall: MeshInstance3D
	var ring: MeshInstance3D
	var box := Node3D.new()
	var key := Node3D.new()
	var wall_mat: ShaderMaterial
	var ring_mat: StandardMaterial3D
	var drop_t := 1.0
	var site_pos := Vector3.ZERO
	var radius := 4.0
	var height := 4.0
	var color := Color.WHITE
	var cur := Color.WHITE
	var time := 0.0

	func _init() -> void:
		name = "HillZone"
		wall_mat = Zones.wall_material("#ffffff", 1)
		wall = Geo.cylinder(1, 1, 1, 64, 1, true).mesh_instance(wall_mat, Vector3.ZERO, Basis(), false)
		wall.extra_cull_margin = 50
		ring_mat = Zones.ring_material("#ffffff", 0.85)
		ring = Geo.ring(0.93, 1, 72).mesh_instance(ring_mat, Vector3.ZERO, Basis(), false)
		# floating open toy box with a wind-up key on top
		var card := Mats.textured(Tex.cardboard("TOYS"), 0.85)
		var s := 1.5
		var wall_geo := Geo.rounded_box(s, s * 0.8, 0.08, 1, 0.02)
		for i in 4:
			var a := i * PI / 2
			box.add_child(wall_geo.mesh_instance(card, Vector3(sin(a) * s * 0.5, 0, cos(a) * s * 0.5), Basis(Vector3.UP, a)))
			box.add_child(Geo.rounded_box(s, 0.06, s * 0.45, 1, 0.02).mesh_instance(card, Vector3(sin(a) * s * 0.68, s * 0.42, cos(a) * s * 0.68), Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -0.7)))
		box.add_child(Geo.rounded_box(s, 0.08, s, 1, 0.02).mesh_instance(card, Vector3(0, -s * 0.4, 0)))
		# toys peeking out
		var toy_cols := ["#ef476f", "#ffd166", "#06d6a0", "#118ab2"]
		for i in 4:
			var g := Geo.sphere(0.25, 14, 10) if i % 2 else Geo.rounded_box(0.4, 0.4, 0.4, 2, 0.08)
			box.add_child(g.mesh_instance(Mats.plastic(toy_cols[i]), Vector3((0.3 if i % 2 else -0.3) * (-1 if i > 1 else 1), 0.25, 0.3 if i > 1 else -0.3)))
		var gold := Mats.metal("#d4af37", 0.25)
		key.add_child(Geo.cylinder(0.08, 0.08, 0.9, 10).mesh_instance(gold, Vector3(0, 0.45, 0)))
		for x in [-0.4, 0.4]:
			key.add_child(Geo.torus(0.3, 0.08, 10, 24).mesh_instance(gold, Vector3(x, 1.05, 0)))
		key.position.y = s * 0.3
		box.add_child(key)
		add_child(wall)
		add_child(ring)
		add_child(box)
		visible = false

	func hide_zone() -> void:
		visible = false

	## Move to a new site with a little drop-in animation.
	func place(pos: Vector3, r: float, h: float, animate := true) -> void:
		site_pos = pos
		radius = r
		height = h
		visible = true
		wall.transform = Transform3D(Basis.from_scale(Vector3(r, h, r)), Vector3(pos.x, pos.y + h / 2, pos.z))
		ring.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2).scaled(Vector3(r, r, r)), Vector3(pos.x, pos.y + 0.07, pos.z))
		drop_t = 0.0 if animate else 1.0

	func update(dt: float, h, reduced: bool) -> void:
		if h == null:
			visible = false
			return
		time += dt
		drop_t = minf(1, drop_t + dt / 0.9)
		var e := 1 - pow(1 - drop_t, 3)
		var hover := site_pos.y + height + 1.2
		box.position = Vector3(site_pos.x, hover + (1 - e) * 14 + (0.0 if reduced else sin(time * 1.5) * 0.15), site_pos.z)
		box.rotation.y += dt * 0.35
		var scoring: bool = h.owner >= 0
		key.rotation.y += dt * (6.0 if scoring else 0.8)
		# color: team when held, flashing pink when contested, white when empty
		if h.contested:
			color = U.col("#ff4d8d" if sin(time * 12) > 0 else "#ffffff")
		elif h.owner >= 0:
			color = U.col(Modes.TEAMS[h.owner].color)
		else:
			color = U.col("#fff6d8")
		cur = cur.lerp(color, minf(1, dt * 10))
		wall_mat.set_shader_parameter("uColor", cur)
		wall_mat.set_shader_parameter("uTime", time)
		wall_mat.set_shader_parameter("uAlpha", (0.75 + (0.35 if scoring else 0.0)) * e)
		# pulse in the last 10 seconds before it moves
		var warn: float = 0.5 + 0.5 * sin(time * 10) if h.timeLeft < 10 else 1.0
		var rc := cur
		rc.a = 0.85 * warn
		ring_mat.albedo_color = rc


## Letter badge drawn on a canvas (the original drew it on an HTML canvas).
class Badge extends Node2D:
	var letter := ""
	var fill := Color.WHITE
	var ring := Color.WHITE
	var progress := 0.0

	func _draw() -> void:
		draw_circle(Vector2(64, 64), 52, fill)
		draw_arc(Vector2(64, 64), 52, 0, TAU, 64, Color(0, 0, 0, 0.35), 10, true)
		if progress > 0 and progress < 1:
			draw_arc(Vector2(64, 64), 58, -PI / 2, -PI / 2 + TAU * progress, 48, ring, 10, true)
		var f: Font = Tex.FONT_TITLE
		var w := f.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 66).x
		draw_string(f, Vector2(64 - w / 2, 70 + 24), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 66, Color("#1d1d1f"))


## The six Conquest sectors: soft cylinder wall, floor ring, a flag that climbs as a team captures, and a letter badge.
class SectorZones extends Node3D:
	var vis: Array = []
	var time := 0.0

	func _init() -> void:
		name = "SectorZones"
		visible = false

	func build(sectors: Array) -> void:
		clear()
		for s in sectors:
			var g := Node3D.new()
			g.position = s.pos
			var r: float = s.def.radius
			var h: float = s.def.height
			var wall_mat := Zones.wall_material(Zones.NEUTRAL, 0.55)
			g.add_child(Geo.cylinder(r, r, h, 56, 1, true).mesh_instance(wall_mat, Vector3(0, h / 2, 0), Basis(), false))
			var ring_mat := Zones.ring_material(Zones.NEUTRAL, 0.85)
			g.add_child(Geo.ring(r - 0.3, r, 64).mesh_instance(ring_mat, Vector3(0, 0.07, 0), Basis(Vector3.RIGHT, -PI / 2), false))
			# flag pole in the middle
			var pole_h := h + 2.2
			g.add_child(Geo.cylinder(0.07, 0.09, pole_h, 10).mesh_instance(Mats.metal("#e0e0e0", 0.3), Vector3(0, pole_h / 2, 0)))
			g.add_child(Geo.sphere(0.16, 12, 10).mesh_instance(Mats.plastic("#ffd23f"), Vector3(0, pole_h + 0.1, 0)))
			var flag_mat := ShaderMaterial.new()
			flag_mat.shader = Zones.FLAG_SHADER
			flag_mat.set_shader_parameter("uColor", U.col(Zones.NEUTRAL))
			flag_mat.set_shader_parameter("uPhase", float(vis.size()))
			var flag := Geo.plane(1.5, 0.95, 6, 1).translate(0.75, 0, 0).mesh_instance(flag_mat)
			g.add_child(flag)
			g.add_child(Geo.cylinder(0.5, 0.6, 0.25, 16).mesh_instance(Mats.plastic("#555b6e"), Vector3(0, 0.12, 0)))
			# floating letter badge
			var vp := SubViewport.new()
			vp.size = Vector2i(128, 128)
			vp.transparent_bg = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			var badge := Badge.new()
			vp.add_child(badge)
			g.add_child(vp)
			var spr := Sprite3D.new()
			spr.texture = vp.get_texture()
			spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			spr.pixel_size = 1.5 / 128.0
			spr.shaded = false
			spr.no_depth_test = false
			spr.position.y = pole_h + 1.3
			g.add_child(spr)
			add_child(g)
			vis.append({"group": g, "wall_mat": wall_mat, "ring_mat": ring_mat, "flag": flag, "flag_mat": flag_mat, "vp": vp, "badge": badge,
				"last_badge": "", "height": pole_h, "color": U.col(Zones.NEUTRAL)})
		visible = sectors.size() > 0

	func _draw_badge(v: Dictionary, letter: String, color: String, ring: String, progress: float) -> void:
		var k := "%s|%s|%s|%d" % [letter, color, ring, roundi(progress * 20)]
		if k == v.last_badge:
			return
		v.last_badge = k
		var b: Badge = v.badge
		b.letter = letter
		b.fill = U.col(color)
		b.ring = U.col(ring)
		b.progress = progress
		b.queue_redraw()
		(v.vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE

	func update(dt: float, sectors: Array) -> void:
		if sectors.is_empty() or vis.is_empty():
			visible = false
			return
		visible = true
		time += dt
		for i in sectors.size():
			if i >= vis.size():
				break
			var s: Dictionary = sectors[i]
			var v: Dictionary = vis[i]
			var owner_col: String = Modes.TEAMS[s.owner].color if s.owner >= 0 else Zones.NEUTRAL
			var act_col: String = Modes.TEAMS[s.active].color if s.active >= 0 else owner_col
			var target: String
			if s.contested:
				target = Zones.CONTESTED if sin(time * 12) > 0 else "#ffffff"
			elif s.active >= 0 and s.active != s.owner:
				target = act_col if sin(time * 8) > 0 else owner_col
			else:
				target = owner_col
			v.color = (v.color as Color).lerp(U.col(target), minf(1, dt * 10))
			var wm: ShaderMaterial = v.wall_mat
			wm.set_shader_parameter("uColor", v.color)
			wm.set_shader_parameter("uTime", time)
			wm.set_shader_parameter("uAlpha", 0.7 if s.owner >= 0 else 0.5)
			var rc: Color = v.color
			rc.a = 0.85
			(v.ring_mat as StandardMaterial3D).albedo_color = rc
			# flag: owned = flag at the top in the owner's color, shrinking as it's drained;
			# neutral = the capturing team's flag climbing with progress
			var flag_team: int = s.owner if s.owner >= 0 else s.progressTeam
			var hgt: float = s.progress if s.owner >= 0 else (s.progress if s.progressTeam >= 0 else 0.0)
			var fm: ShaderMaterial = v.flag_mat
			fm.set_shader_parameter("uColor", U.col(Modes.TEAMS[flag_team].color if flag_team >= 0 else Zones.NEUTRAL))
			fm.set_shader_parameter("uTime", time)
			var flag: Node3D = v.flag
			flag.position.y = 0.6 + (v.height - 1.2) * hgt
			flag.rotation.y = sin(time * 2 + i) * 0.25
			_draw_badge(v, s.def.letter, Modes.TEAMS[s.owner].light if s.owner >= 0 else "#fff6d8", Modes.TEAMS[s.active].color if s.active >= 0 else "#ffffff",
				(s.progress if s.progress < 1 else 0.0) if s.owner >= 0 else s.progress)

	func clear() -> void:
		for v in vis:
			(v.group as Node).queue_free()
		vis = []
		visible = false

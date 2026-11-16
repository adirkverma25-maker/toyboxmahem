class_name Pickups
extends Node3D
## Health batteries, shields and power-ups (port of src/match/Pickups.ts). The original's weapon pedestals
## were switched off (weapons come from the loadout), so they are not ported.

const INFO := {
	"health": {"label": "Health Battery +35", "color": "#4ade80", "icon": "🔋"},
	"shield": {"label": "Bubble Shield +50", "color": "#5ac8fa", "icon": "🫧"},
	"turbo": {"label": "Turbo Wheels", "color": "#ff9f1c", "icon": "🛞"},
	"infinite": {"label": "Infinite Springs", "color": "#f2c94c", "icon": "♾️"},
	"power": {"label": "Power Star", "color": "#ffe14d", "icon": "⭐"},
}

var items: Array = []
var fx: Effects
var audio
var events: Emitter


static func _mesh(g: Geo, mat: Material, pos := Vector3.ZERO, rot := Basis()) -> MeshInstance3D:
	return g.mesh_instance(mat, pos, rot)


static func additive(color, opacity: float, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var c := U.col(color)
	c.a = opacity
	m.albedo_color = c
	if tex:
		m.albedo_texture = tex
	return m


static func star_points(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := float(i) / 10 * TAU + PI / 2
		var r := inner if i % 2 else outer
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts


static func build_model(kind: String) -> Node3D:
	var g := Node3D.new()
	match kind:
		"health":
			g.add_child(_mesh(Geo.cylinder(0.26, 0.26, 0.8, 24), Mats.plastic("#22c55e", {"rough": 0.25, "clearcoat": 1.0})))
			g.add_child(_mesh(Geo.cylinder(0.265, 0.265, 0.25, 24), Mats.plastic("#111827", {"rough": 0.3}), Vector3(0, -0.2, 0)))
			g.add_child(_mesh(Geo.cylinder(0.1, 0.1, 0.1, 16), Mats.metal("#d4d4d8", 0.2), Vector3(0, 0.45, 0)))
			g.add_child(_mesh(Geo.box(0.2, 0.05, 0.05), Mats.glow("#ffffff", 1.5), Vector3(0, 0.12, 0.27)))
			g.add_child(_mesh(Geo.box(0.05, 0.2, 0.05), Mats.glow("#ffffff", 1.5), Vector3(0, 0.12, 0.27)))
		"shield":
			var m := Mats.translucent("#bde7ff", 0.45, "#3aa0ff", 0.4)
			m.roughness = 0.02
			m.rim_enabled = true
			m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
			g.add_child(_mesh(Geo.sphere(0.42, 28, 20), m))
			g.add_child(_mesh(Geo.cylinder(0.2, 0.2, 0.06, 6), Mats.glow("#5ac8fa", 2), Vector3.ZERO, Basis(Vector3.RIGHT, PI / 2)))
		"turbo":
			for x in [-0.25, 0.25]:
				g.add_child(_mesh(Geo.torus(0.2, 0.09, 12, 24), Mats.plastic("#1f2937", {"rough": 0.7, "clearcoat": 0.0}), Vector3(x, 0, 0), Basis(Vector3.UP, PI / 2)))
				g.add_child(_mesh(Geo.cylinder(0.1, 0.1, 0.12, 16), Mats.plastic("#ff9f1c"), Vector3(x, 0, 0), Basis(Vector3.BACK, PI / 2)))
			g.add_child(_mesh(Geo.cylinder(0.03, 0.03, 0.5, 8), Mats.metal("#cbd5e1"), Vector3.ZERO, Basis(Vector3.BACK, PI / 2)))
			g.add_child(_mesh(Geo.cone(0.12, 0.35, 12), Mats.glow("#ff6b00", 2.5), Vector3(0, 0, -0.25), Basis(Vector3.RIGHT, PI / 2)))
		"infinite":
			var pts := []
			for i in 201:
				var t := float(i) / 200 * TAU
				var s := sin(t)
				var c := cos(t)
				var d := 1 + s * s
				var lx := 0.42 * c / d
				var ly := 0.42 * s * c / d
				var coil := 0.05
				pts.append(Vector3(lx + cos(t * 24) * coil * 0.3, ly + sin(t * 24) * coil, cos(t * 24) * coil))
			g.add_child(_mesh(Geo.tube(pts, 300, 0.025, 6), Mats.metal("#f2c94c", 0.2)))
		"power":
			var geo := Geo.extrude(star_points(0.42, 0.19), 0.14).translate(0, 0, -0.07)
			var m := StandardMaterial3D.new()
			m.albedo_color = U.col("#ffe14d")
			m.emission_enabled = true
			m.emission = U.col("#ffb703")
			m.emission_energy_multiplier = 0.9
			m.roughness = 0.2
			m.clearcoat_enabled = true
			m.clearcoat = 1
			g.add_child(_mesh(geo, m))
			for x in [-0.08, 0.08]:
				g.add_child(_mesh(Geo.sphere(0.035, 8, 6), Mats.plastic("#222222"), Vector3(x, 0.04, 0.12)))
	return g


func _init(spots: Array, effects: Effects, aud, ev: Emitter) -> void:
	name = "Pickups"
	fx = effects
	audio = aud
	events = ev
	for s in spots:
		items.append(_make_item(s.kind, s.pos, INFO[s.kind].color, build_model(s.kind)))


func _make_item(kind: String, pos: Vector3, color: String, model: Node3D) -> Dictionary:
	var group := Node3D.new()
	group.position = pos
	var spinner := Node3D.new()
	spinner.position.y = 1.0
	spinner.add_child(model)
	group.add_child(spinner)
	var halo := Sprite3D.new()
	halo.texture = Tex.soft_dot()
	halo.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	halo.pixel_size = 1.6 / 64.0
	halo.modulate = U.col(color)
	halo.modulate.a = 0.55
	halo.shaded = false
	halo.transparent = true
	halo.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	halo.position.y = 1.0
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var hm := additive(color, 0.55, Tex.soft_dot())
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo.material_override = hm
	group.add_child(halo)
	var ring := Geo.ring(0.55, 0.75, 32).mesh_instance(additive(color, 0.6), Vector3(0, 0.04, 0), Basis(Vector3.RIGHT, -PI / 2), false)
	group.add_child(ring)
	add_child(group)
	return {"kind": kind, "pos": pos, "group": group, "spinner": spinner, "halo": halo, "halo_mat": hm, "ring": ring,
		"available": true, "respawnAt": 0.0, "phase": randf() * 6, "color": color, "s": 1.0}


func reset() -> void:
	for it in items:
		it.available = true
		it.group.visible = true
		it.s = 1.0
		(it.spinner as Node3D).scale = Vector3.ONE


## For bots: what's on the map. [{pos, kind, available}]
func list() -> Array:
	return items.map(func(i): return {"pos": i.pos, "kind": i.kind, "available": i.available})


func _can_use(it: Dictionary, a: Actor) -> bool:
	match it.kind:
		"health":
			if a.health < a.max_health:
				return true
			for w in a.weapons:
				if w and not w.is_energy() and w.reserve < w.cfg.reserve * 0.5:
					return true
			return false
		"shield":
			return a.shield < Cfg.COMBAT.maxShield
	return true


func _take(it: Dictionary, a: Actor, now: float) -> void:
	var P: Dictionary = Cfg.PICKUPS
	it.available = false
	it.respawnAt = now + P.respawn.get(it.kind, 20)
	fx.pickup_sparkle(it.pos, it.color)
	var label := ""
	match it.kind:
		"health":
			a.health = minf(a.max_health, a.health + P.healthAmount)
		"shield":
			a.shield = minf(Cfg.COMBAT.maxShield, a.shield + P.shieldAmount)
		"turbo":
			a.buffs.turbo = now + P.turboTime
		"infinite":
			a.buffs.infinite = now + P.infiniteTime
		"power":
			a.buffs.power = now + P.powerTime
	label = INFO[it.kind].label
	# no weapon pedestals any more: every pick-up also tops up the ammo of both your weapons
	if refill_ammo(a):
		label += " + ammo"
	audio.pickup(it.kind, it.pos, a.is_player)
	events.emit("pickup", {"actor": a, "kind": it.kind, "label": label})


func update(dt: float, now: float, actors: Array) -> void:
	for it in items:
		it.phase += dt
		var group: Node3D = it.group
		if not it.available:
			if now >= it.respawnAt:
				it.available = true
				it.s = 0.01
				fx.pickup_sparkle(it.pos, it.color)
				audio.spawn_pop(it.pos + Vector3(0, 1, 0))
			group.visible = it.available
			continue
		group.visible = true
		# grow back in, spin, bob, pulse
		it.s = minf(1, it.s + dt * 3)
		var spinner: Node3D = it.spinner
		spinner.scale = Vector3.ONE * it.s
		spinner.rotation.y += dt * 1.8
		spinner.position.y = 1.0 + sin(it.phase * 2.2) * 0.12
		(it.halo_mat as StandardMaterial3D).albedo_color.a = 0.4 + sin(it.phase * 4) * 0.15
		var rs := 1 + sin(it.phase * 3) * 0.08
		(it.ring as Node3D).scale = Vector3(rs, rs, rs)
		# auto-collect
		for a in actors:
			if not a.alive:
				continue
			var dx: float = a.pos.x - it.pos.x
			var dz: float = a.pos.z - it.pos.z
			var dy: float = a.pos.y - it.pos.y
			if dx * dx + dz * dz > 1.5 or absf(dy) > 1.6:
				continue
			if _can_use(it, a):
				_take(it, a, now)
				break


## Online guest: show exactly the pick-ups the host says are there (bit i = item i). Only the host
## brings them back, so a taken one waits here until the host's snapshot says it's back.
func apply_available(mask: int) -> void:
	for i in items.size():
		var it: Dictionary = items[i]
		var on := (mask & (1 << i)) != 0
		if on == it.available:
			continue
		it.available = on
		fx.pickup_sparkle(it.pos, it.color)
		if on:
			it.s = 0.01
		else:
			it.respawnAt = INF


## Every pick-up tops up half the reserve of both weapons. Returns true if anything was added.
static func refill_ammo(a: Actor) -> bool:
	var ammo := false
	for w in a.weapons:
		if not w or w.is_energy() or w.reserve >= w.cfg.reserve:
			continue
		w.reserve = int(minf(w.cfg.reserve, w.reserve + ceilf(w.cfg.reserve * 0.5)))
		ammo = true
	return ammo

class_name Combat
extends Node3D
## Hitscan, projectiles, explosions, punches and the single authority for damage + eliminations
## (port of src/combat/Combat.ts, solo/host path).
## Events: damage, kill, shot, explosion, hit (see Game for the payload keys).

const PROJ_POOL := {"dart": 140, "bubble": 160, "crayon": 20, "bolt": 120, "arrow": 40, "slug": 40}
const STUCK := 40
const PAINT := ["#ef476f", "#ffd166", "#06d6a0", "#118ab2", "#8338ec", "#ff8c42"]

var phys: Phys
var fx: Effects
var audio
var events: Emitter
var actors: Callable
var bricks
var now := 0.0
var reduced_motion := false
var barriers: Barriers
var _projectiles: Array = []
var _mm := {}  # visual -> MultiMesh
var _buf := {}  # visual -> PackedFloat32Array
var _dirty := {}
var _stuck: MultiMesh
var _stuck_buf := PackedFloat32Array()
var _stuck_life := PackedFloat32Array()
var _stuck_next := 0
## Who decides what a shot does (online play):
##  "full"   - this game applies damage (solo, and the host)
##  "claims" - a guest's own attacks: hits go to the host through `on_claim`, the host applies them
##  "visual" - someone else's shot replayed for the looks: no damage at all
var local_auth := "full"
## guest: the toy whose movement this game runs (gets its own knockback directly)
var local_mover: Actor = null
## guest: (claim: {target, dmg, head, weapon, point, dir, kv}) for every hit its own attacks land
var on_claim := Callable()
## host: (a, v: Vector3, min_vy) -> bool, knockback for a toy moved by a guest's game
var on_remote_kick := Callable()
## online: (shooter, ws, origin, dir, muzzle, spread) for every real (not replayed) trigger pull
var on_fire := Callable()
## online: (a, yaw) when a Mesh Shield goes up (see Abilities.try_shield)
var on_shield := Callable()
## authority of whatever is being resolved right now
var _auth := "full"
var _pending := {}


## Suction-cup arrow, pointing down +Z (cup at the front).
static func arrow_geometry() -> Geo:
	var g := Geo.cylinder(0.028, 0.028, 0.9, 8).rotate_basis(Basis(Vector3.RIGHT, PI / 2))
	g.merge(Geo.cylinder(0.1, 0.035, 0.1, 14).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).translate(0, 0, 0.5))
	for r in [0.0, PI / 2]:
		g.merge(Geo.box(0.16, 0.012, 0.18).rotate_basis(Basis(Vector3.BACK, r)).translate(0, 0, -0.36))
	return g


func _init(p: Phys, effects: Effects, aud, ev: Emitter, actor_list: Callable, loose_bricks) -> void:
	name = "Combat"
	phys = p
	fx = effects
	audio = aud
	events = ev
	actors = actor_list
	bricks = loose_bricks
	barriers = Barriers.new()
	add_child(barriers)
	barriers.on_break = func(b: Dictionary) -> void:
		audio.shield_break(b.center)
		var c := U.col(b.color)
		for i in 24:
			var p0: Vector3 = (b.center as Vector3) + (b.right as Vector3) * U.rand(-b.halfW, b.halfW)
			p0.y = b.center.y + U.rand(-b.halfH, b.halfH)
			fx.glow.emit(p0, Vector3(U.rand(-3, 3), U.rand(-1, 3), U.rand(-3, 3)), c, U.rand(0.1, 0.2), U.rand(0.3, 0.6), {"gravity": 6, "drag": 2})
	var arrow_geo := arrow_geometry()
	var white_std := func(rough: float, emissive := "", ei := 0.0) -> StandardMaterial3D:
		var m := StandardMaterial3D.new()
		m.roughness = rough
		m.vertex_color_use_as_albedo = true
		if emissive != "":
			m.emission_enabled = true
			m.emission = U.col(emissive)
			m.emission_energy_multiplier = ei
		return m
	_stuck = _make_mm(arrow_geo.to_mesh(white_std.call(0.5)), STUCK, true)
	_stuck_buf.resize(STUCK * 16)
	_stuck.visible_instance_count = 0
	_stuck_life.resize(STUCK)
	var bubble_mat := StandardMaterial3D.new()
	bubble_mat.vertex_color_use_as_albedo = true
	bubble_mat.roughness = 0.02
	bubble_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bubble_mat.albedo_color = Color(1, 1, 1, 0.5)
	bubble_mat.clearcoat_enabled = true
	bubble_mat.clearcoat = 1
	bubble_mat.rim_enabled = true
	bubble_mat.rim = 1
	bubble_mat.emission_enabled = true
	bubble_mat.emission = U.col("#b388ff")
	bubble_mat.emission_energy_multiplier = 0.4
	bubble_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var bolt_mat := StandardMaterial3D.new()
	bolt_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bolt_mat.vertex_color_use_as_albedo = true
	var meshes := {
		"dart": Geo.capsule(0.045, 0.22, 4, 8).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).to_mesh(white_std.call(0.7, "#ff8a3d", 0.25)),
		"bubble": Geo.sphere(0.15, 14, 10).to_mesh(bubble_mat),
		"crayon": Geo.cylinder(0.12, 0.12, 0.7, 12).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).to_mesh(white_std.call(0.6)),
		"bolt": Geo.capsule(0.05, 0.5, 4, 8).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).to_mesh(bolt_mat),
		"arrow": arrow_geo.to_mesh(white_std.call(0.5, "#ff4d6d", 0.15)),
		# sniper round: a thin bright streak (stretched along its flight)
		"slug": Geo.capsule(0.025, 0.3, 3, 6).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).to_mesh(bolt_mat),
	}
	for k in PROJ_POOL:
		_mm[k] = _make_mm(meshes[k], PROJ_POOL[k], k != "bolt" and k != "bubble" and k != "slug")
		var b := PackedFloat32Array()
		b.resize(PROJ_POOL[k] * 16)
		_buf[k] = b
		_dirty[k] = false
		for i in PROJ_POOL[k]:
			_projectiles.append({"active": false, "visual": k, "idx": i, "pos": Vector3.ZERO, "prev": Vector3.ZERO, "vel": Vector3.ZERO,
				"offset": Vector3.ZERO, "gravity": 0.0, "drag": 0.0, "radius": 0.1, "life": 0.0, "shooter": null, "cfg": {},
				"traveled": 0.0, "hits": {}, "color": "#fff", "whistle": null, "power": 1.0, "charge": 1.0, "auth": "full"})


func _make_mm(mesh: Mesh, count: int, shadow: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mm


static func _write(buf: PackedFloat32Array, i: int, xf: Transform3D) -> void:
	var o := i * 16
	var b := xf.basis
	buf[o] = b.x.x
	buf[o + 1] = b.y.x
	buf[o + 2] = b.z.x
	buf[o + 3] = xf.origin.x
	buf[o + 4] = b.x.y
	buf[o + 5] = b.y.y
	buf[o + 6] = b.z.y
	buf[o + 7] = xf.origin.y
	buf[o + 8] = b.x.z
	buf[o + 9] = b.y.z
	buf[o + 10] = b.z.z
	buf[o + 11] = xf.origin.z


static func _hide(buf: PackedFloat32Array, i: int) -> void:
	for k in 12:
		buf[i * 16 + k] = 0


static func _color(buf: PackedFloat32Array, i: int, c: Color) -> void:
	var l := c.srgb_to_linear()
	buf[i * 16 + 12] = l.r
	buf[i * 16 + 13] = l.g
	buf[i * 16 + 14] = l.b
	buf[i * 16 + 15] = 1


## Basis turning +Z toward unit `d`.
static func _face(d: Vector3) -> Basis:
	return Effects.DecalPool._face(d)


## Fire one trigger pull of `ws` from `origin` (eye) toward `dir`. `muzzle` is where visuals start.
## `auth` defaults to `local_auth` (see above).
func fire(shooter: Actor, ws: WeaponState, origin: Vector3, dir: Vector3, muzzle: Vector3, spread_deg: float, auth := "") -> void:
	if auth == "":
		auth = local_auth
	var cfg := ws.cfg
	var power: float = Cfg.PICKUPS.powerMult if shooter.has_buff("power", now) else 1.0
	# bows: damage and arrow speed scale with how long the string was held
	var charge := ws.last_charge if cfg.has("charge") else 1.0
	shooter.shots_fired += int(cfg.pellets)
	shooter.reveal_at = now  # attacking drops cloak
	if auth != "visual" and on_fire.is_valid():
		on_fire.call(shooter, ws, origin, dir, muzzle, spread_deg)
	_auth = auth
	for p in int(cfg.pellets):
		var d := U.cone_direction(dir, deg_to_rad(spread_deg))
		if cfg.projectile.kind == "hitscan":
			_hitscan(shooter, cfg, origin, d, muzzle, power)
		else:
			_spawn_projectile(shooter, cfg, origin, d, muzzle, power, charge, auth)
	_auth = "full"
	_flush_claims()
	events.emit("shot", {"shooter": shooter, "weapon": cfg.id, "pos": origin})


## Someone else's shot, replayed so it looks right (online play). Never hurts anyone.
func replay_shot(shooter: Actor, ws: WeaponState, origin: Vector3, dir: Vector3, muzzle: Vector3, spread_deg: float) -> void:
	fire(shooter, ws, origin, dir, muzzle, spread_deg, "visual")


## Host: apply a hit a guest's own attack landed, as if the host's copy of that shot had hit.
func apply_claim(c: Dictionary, attacker: Actor) -> void:
	_auth = "full"
	var target: Actor = c.target
	apply_damage(target, attacker, c.dmg, c.head, c.point, c.weapon, c.dir)
	var kv: Vector3 = c.kv
	if kv.length_squared() > 0 and target.alive:
		_kick(target, kv.x, kv.y, kv.z, kv.y if kv.y > 0 else 0.0)


## Guest: the host says this toy was popped (the score and respawn come in the snapshot).
func pop_remote(victim: Actor, killer, weapon: String, head: bool) -> void:
	if victim.alive:
		victim.alive = false
		victim.health = 0
		victim.despawn()
		fx.break_apart(victim.pos, victim.def.colors, reduced_motion)
		audio.eliminated(victim.pos + Vector3(0, 1, 0))
	events.emit("kill", {"killer": killer, "victim": victim, "weapon": weapon, "head": head, "time": now})


func _flush_claims() -> void:
	if _pending.is_empty():
		return
	for c in _pending.values():
		if on_claim.is_valid():
			on_claim.call(c)
	_pending.clear()


## Add knockback to a toy. `min_vy` pops the toy up to at least that vertical speed. Whoever runs that
## toy's movement gets it: this game (bots, solo, a guest's own toy), the host's `on_remote_kick` for a
## guest's toy, or the claim sent to the host.
func _kick(a: Actor, vx: float, vy: float, vz: float, min_vy := 0.0) -> void:
	if _auth == "visual":
		return
	if _auth == "claims" and a != local_mover:
		var c = _pending.get(a)
		if c != null:
			var kv: Vector3 = c.kv
			kv.x += vx
			kv.z += vz
			kv.y = maxf(kv.y + vy, min_vy)
			c.kv = kv
		return
	if _auth == "full" and on_remote_kick.is_valid() and on_remote_kick.call(a, Vector3(vx, vy, vz), min_vy):
		return
	a.vel.x += vx
	a.vel.z += vz
	a.vel.y = maxf(a.vel.y + vy, min_vy) if min_vy > 0 else a.vel.y + vy


func _falloff(cfg: Dictionary, dist: float) -> float:
	if dist <= cfg.effectiveRange:
		return 1.0
	if dist >= cfg.falloffEnd:
		return cfg.minDamageMult
	var t: float = (dist - cfg.effectiveRange) / (cfg.falloffEnd - cfg.effectiveRange)
	return 1 + (cfg.minDamageMult - 1) * t


## Nearest character hit along a segment (excluding shooter + already-hit). Returns {actor, t, head} or {}.
func _trace_actors(o: Vector3, d: Vector3, max_t: float, shooter, inflate: float, skip := {}) -> Dictionary:
	var best := {}
	for a in actors.call():
		if not a.alive or a == shooter or skip.has(a.id):
			continue
		if shooter and shooter.team >= 0 and a.team == shooter.team:
			continue  # no friendly fire: shots pass through teammates
		var proj: float = (a.chest_pos() - o).dot(d)
		if proj < -1.5 or proj > max_t + 1.5:
			continue
		var hb: Dictionary = a.def.hitbox
		var th := U.ray_sphere(o, d, a.head_pos(), hb.headR + inflate, max_t)
		var seg: Array = a.body_segment()
		var tb := U.ray_capsule(o, d, seg[0], seg[1], hb.bodyR + inflate, max_t)
		var t := -1.0
		var head := false
		if th >= 0 and (tb < 0 or th <= tb + 0.05):
			t = th
			head = true
		elif tb >= 0:
			t = tb
		if t >= 0 and (best.is_empty() or t < best.t):
			best = {"actor": a, "t": t, "head": head}
	return best


func _hitscan(shooter: Actor, cfg: Dictionary, origin: Vector3, d: Vector3, muzzle: Vector3, power: float) -> void:
	var max_range := 220.0
	var world := phys.raycast(origin, d, max_range)
	var wt: float = world.dist if not world.is_empty() else max_range
	var hit := _trace_actors(origin, d, wt, shooter, 0)
	var shield := barriers.trace(origin, d, hit.t if not hit.is_empty() else wt, shooter)
	if not shield.is_empty():
		hit = {}
	var ht: float = hit.t if not hit.is_empty() else wt
	var end: Vector3 = origin + d * (shield.t if not shield.is_empty() else ht)
	var tr: String = cfg.projectile.get("tracer", "pellet")
	var tc: String = cfg.colors.tracer
	if tr == "precision":
		fx.tracer(muzzle, end, tc, 0.06, 0.45)
		fx.tracer(muzzle, end, "#ffffff", 0.02, 0.3)
	elif tr == "heavy":
		fx.tracer(muzzle, end, tc, 0.05, 0.05, minf(0.08, ht / 260))
	elif tr == "buzz":
		fx.tracer(muzzle, end, tc, 0.03, 0.03, minf(0.06, ht / 300))
	else:
		fx.tracer(muzzle, end, tc, 0.045, 0.04, minf(0.09, ht / 240))
	if not shield.is_empty():
		_hit_barrier(shield.b, end, cfg.damage * _falloff(cfg, shield.t) * power)
	elif not hit.is_empty():
		shooter.shots_hit += 1
		var dmg: float = cfg.damage * (cfg.headMult if hit.head else 1.0) * _falloff(cfg, hit.t) * power
		var target: Actor = hit.actor
		apply_damage(target, shooter, dmg, hit.head, end, cfg.id, d)
		if cfg.has("knockback") and target.alive:
			# heavy rounds shove the target back along the shot and pop them off the ground a little
			var k: float = cfg.knockback * _falloff(cfg, hit.t)
			var flat := Vector3(d.x, 0, d.z).normalized()
			_kick(target, flat.x * k, 0, flat.z * k, 3)
	elif not world.is_empty():
		_world_impact(world, cfg, d)


func _hit_barrier(b: Dictionary, point: Vector3, dmg: float) -> void:
	barriers.damage(b, dmg)
	fx.hit_spark(point, "#bdeeff", true, false)
	if randf() < 0.5:
		audio.zap(point)


func _world_impact(hit: Dictionary, cfg: Dictionary, d: Vector3) -> void:
	if hit.dynamic_body:
		(hit.dynamic_body as RigidBody3D).apply_impulse(Vector3(d.x * 0.6, d.y * 0.6 + 0.2, d.z * 0.6), hit.point - (hit.dynamic_body as RigidBody3D).global_position)
	var big: bool = cfg.id in ["thunderspring", "walloper"]
	fx.impact(hit.point, hit.normal, hit.mat, {"big": big})
	if randf() < 0.7 or big:
		audio.impact(hit.mat, hit.point, 1.5 if big else 0.8)


func _spawn_projectile(shooter: Actor, cfg: Dictionary, origin: Vector3, d: Vector3, muzzle: Vector3, power: float, charge := 1.0, auth := "full") -> void:
	var spec: Dictionary = cfg.projectile
	var p = null
	for x in _projectiles:
		if not x.active and x.visual == spec.visual:
			p = x
			break
	if p == null:
		return
	p.active = true
	p.auth = auth
	p.pos = origin
	p.prev = origin
	var speed: float = cfg.charge.minSpeed + (cfg.charge.maxSpeed - cfg.charge.minSpeed) * charge if cfg.has("charge") else spec.speed
	p.vel = d * (speed * (U.rand(0.85, 1.1) if spec.visual == "bubble" else 1.0))
	p.charge = charge
	p.offset = muzzle - origin
	p.gravity = spec.gravity
	p.drag = spec.get("drag", 0.0)
	p.radius = spec.radius
	p.life = spec.life
	p.shooter = shooter
	p.cfg = cfg
	p.traveled = 0.0
	p.hits = {}
	p.power = power * (pow(charge, cfg.charge.curve) if cfg.has("charge") else 1.0)
	match spec.visual:
		"arrow": p.color = cfg.colors.accent
		"crayon": p.color = U.pick(PAINT)
		"bubble": p.color = U.pick(["#e0aaff", "#9be7ff", "#ffc6ff", "#caffbf"])
		_: p.color = cfg.colors.tracer
	if spec.visual == "slug":
		# the sniper streak: a bright line from the barrel down the line of fire (the round itself drops a touch)
		var reach := phys.ray_dist(origin, d, 220.0)
		var end := origin + d * (reach if reach != INF else 220.0)
		fx.tracer(muzzle, end, cfg.colors.tracer, 0.05, 0.35)
		fx.tracer(muzzle, end, "#ffffff", 0.018, 0.25)
	var col: String = ("#ff7a1a" if randf() < 0.5 else "#2f6fe0") if spec.visual == "dart" else p.color
	_color(_buf[spec.visual], p.idx, U.col(col))
	var vmm: MultiMesh = _mm[spec.visual]
	vmm.visible_instance_count = maxi(vmm.visible_instance_count, p.idx + 1)
	p.whistle = audio.whistle(origin) if spec.visual == "crayon" else null


func update(dt: float) -> void:
	barriers.update(dt, now)
	# arrows stuck in walls fade away
	var stuck_dirty := false
	var stuck_top := 0
	for i in STUCK:
		if _stuck_life[i] <= 0:
			continue
		_stuck_life[i] -= dt
		if _stuck_life[i] <= 0:
			_hide(_stuck_buf, i)
			stuck_dirty = true
		else:
			stuck_top = i + 1
	if stuck_dirty:
		_stuck.buffer = _stuck_buf
		_stuck.visible_instance_count = stuck_top
	var top := {}
	for p in _projectiles:
		if not p.active:
			continue
		var buf: PackedFloat32Array = _buf[p.visual]
		_dirty[p.visual] = true
		_auth = p.auth
		p.prev = p.pos
		var vel: Vector3 = p.vel
		vel.y -= p.gravity * dt
		if p.drag:
			vel *= maxf(0, 1 - p.drag * dt)
		p.vel = vel
		var step := vel * dt
		var seg_len := step.length()
		p.life -= dt
		var done := false
		var cfg: Dictionary = p.cfg
		if seg_len > 1e-5:
			var d := step / seg_len
			var prev: Vector3 = p.prev
			var world := phys.raycast(prev, d, seg_len + p.radius)
			var wt: float = world.dist if not world.is_empty() else INF
			var hit := _trace_actors(prev, d, minf(seg_len, wt), p.shooter, p.radius, p.hits)
			var shield := barriers.trace(prev, d, minf(minf(seg_len + p.radius, wt), hit.t if not hit.is_empty() else INF), p.shooter)
			if not shield.is_empty():
				var point: Vector3 = prev + d * shield.t
				p.pos = point
				if cfg.has("explosion"):
					var bn: Vector3 = shield.b.normal
					var sg := signf(-d.dot(bn))
					explode(point, bn * (sg if sg != 0 else 1.0), p, null)
				else:
					_hit_barrier(shield.b, point, cfg.damage * p.power)
				done = true
			elif not hit.is_empty() and hit.t <= wt:
				var target: Actor = hit.actor
				p.hits[target.id] = true
				p.shooter.shots_hit += 1
				var point: Vector3 = prev + d * hit.t
				var dist: float = p.traveled + hit.t
				if cfg.has("explosion"):
					apply_damage(target, p.shooter, cfg.damage * p.power, false, point, cfg.id, d)
					explode(point, -d, p, target)
				else:
					var dmg: float = cfg.damage * (cfg.headMult if hit.head else 1.0) * _falloff(cfg, dist) * p.power
					apply_damage(target, p.shooter, dmg, hit.head, point, cfg.id, d)
					if p.visual == "bubble":
						fx.bubble_burst(point, p.color)
					if p.visual == "bolt":
						fx.energy_hit(point, cfg.colors.glow)
					if p.visual == "arrow" and p.charge > 0.85:
						_kick(target, d.x * 2.5, d.y * 2.5, d.z * 2.5)
				done = true
			elif not world.is_empty():
				p.pos = world.point
				if cfg.has("explosion"):
					explode(world.point, world.normal, p, null)
				elif p.visual == "bubble":
					fx.bubble_burst(world.point, p.color)
					if randf() < 0.4:
						audio.bubble_pop(world.point)
				elif p.visual == "bolt":
					fx.energy_hit(world.point, cfg.colors.glow)
					fx.impacts.add(world.point, world.normal, 0.3, "#3a1b5c", 6, 0.5)
					if randf() < 0.5:
						audio.zap(world.point)
				elif p.visual == "arrow":
					_stick_arrow(world.point, d, p.color)
					audio.impact(world.mat, world.point, 0.7)
					fx.impact(world.point, world.normal, world.mat, {"decal": false})
				else:
					_world_impact(world, cfg, d)
				if world.dynamic_body and not cfg.has("explosion"):
					var rb: RigidBody3D = world.dynamic_body
					rb.apply_impulse(Vector3(d.x * 0.4, 0.2, d.z * 0.4), world.point - rb.global_position)
				done = true
			else:
				p.pos += step
				p.traveled += seg_len
		if not done and p.life <= 0:
			if p.visual == "bubble":
				fx.bubble_burst(p.pos, p.color)
			if cfg.has("explosion"):
				explode(p.pos, Vector3.UP, p, null)
			done = true
		if p.whistle:
			p.whistle.move(p.pos)
		if done:
			p.active = false
			if p.whistle:
				p.whistle.stop()
			p.whistle = null
			_hide(buf, p.idx)
			continue
		# visual: converge from muzzle to the true path, stretch along velocity for a motion trail
		p.offset *= maxf(0, 1 - dt * 14)
		var sp := vel.length()
		var stretch := 1.0
		match p.visual:
			"arrow": stretch = 1.0
			"bubble": stretch = 1 + minf(0.4, sp * 0.004)
			"bolt": stretch = 1 + minf(3, sp * 0.02)
			"slug": stretch = 1 + minf(6, sp * 0.02)
			_: stretch = 1 + minf(1.2, sp * 0.008)
		var sz := U.rand(0.9, 1.1) if p.visual == "bubble" else 1.0
		var b := _face(vel / maxf(1e-4, sp)).scaled_local(Vector3(sz, sz, stretch * sz))
		_write(buf, p.idx, Transform3D(b, (p.pos as Vector3) + (p.offset as Vector3)))
		top[p.visual] = maxi(top.get(p.visual, 0), p.idx + 1)
	for k in _dirty:
		if _dirty[k]:
			(_mm[k] as MultiMesh).buffer = _buf[k]
			_dirty[k] = false
		# only draw the slots in use (idle pool slots would still cost vertex work)
		(_mm[k] as MultiMesh).visible_instance_count = top.get(k, 0)
	_auth = "full"
	_flush_claims()


func explode(point: Vector3, normal: Vector3, p: Dictionary, direct) -> void:
	var ex: Dictionary = p.cfg.explosion
	var center := point + normal * 0.25
	var colors := [p.color, U.pick(PAINT), U.pick(PAINT), "#ffffff"]
	fx.explosion(center, normal, colors, reduced_motion)
	fx.paint_splat(point, normal, p.color, 2.6)
	# extra paint splats on nearby surfaces
	for i in 5:
		var d := Vector3(U.rand(-1, 1), U.rand(-1, 0.4), U.rand(-1, 1)).normalized()
		var h := phys.raycast(center, d, ex.radius)
		if not h.is_empty():
			fx.paint_splat(h.point, h.normal, U.pick([p.color] + PAINT), U.rand(0.8, 1.6))
	audio.explosion(center)
	if bricks:
		bricks.blast(center, ex.radius, 3.2)
	var shooter: Actor = p.shooter
	for a in actors.call():
		if not a.alive or a == direct:
			continue
		if a != shooter and shooter.team >= 0 and a.team == shooter.team:
			continue
		var h: Vector3 = a.chest_pos()
		var dist := h.distance_to(center)
		if dist > ex.radius + 0.4:
			continue
		if not phys.los(center, h, true):
			continue
		var f := maxf(0, 1 - maxf(0, dist - 0.4) / ex.radius)
		var wall := barriers.between(center, h, shooter)
		if not wall.is_empty():
			barriers.damage(wall.b, ex.maxDamage * f * p.power * 0.5)
			continue
		var dmg: float = ex.maxDamage * f * p.power
		if a == shooter:
			dmg *= ex.selfDamageMult
		if dmg < 1:
			continue
		apply_damage(a, shooter, dmg, false, h, p.cfg.id, (h - center).normalized())
		# knockback
		var push := Vector3(h.x - center.x, 0.6, h.z - center.z).normalized() * (6 * f)
		_kick(a, push.x, push.y, push.z)
	events.emit("explosion", {"pos": center, "radius": ex.radius})


func _stick_arrow(point: Vector3, d: Vector3, color: String) -> void:
	var i := _stuck_next
	_stuck_next = (_stuck_next + 1) % STUCK
	_write(_stuck_buf, i, Transform3D(_face(d), point - d * 0.5))
	_color(_stuck_buf, i, U.col(color))
	_stuck.buffer = _stuck_buf
	_stuck_life[i] = 8
	_stuck.visible_instance_count = maxi(_stuck.visible_instance_count, i + 1)


## Spring Punch: a spring-loaded boxing glove pops out and hits the closest enemy in front.
## Returns the toy that got punched (or null on a whiff).
func jab(attacker: Actor) -> Actor:
	var J: Dictionary = Cfg.ABILITIES.jab
	var eye := attacker.eye_pos()
	var fwd := attacker.forward()
	attacker.reveal_at = now
	attacker.spawn_protect_until = minf(attacker.spawn_protect_until, now)
	var cos_max := cos(deg_to_rad(J.coneDeg))
	var best: Actor = null
	var best_d := INF
	for a in actors.call():
		if not a.alive or not attacker.is_enemy(a):
			continue
		var c: Vector3 = a.chest_pos()
		var to := c - eye
		var dist := to.length()
		if dist > J.range + a.def.hitbox.bodyR + 0.4:
			continue
		# be generous vertically: compare against the flattened aim when they're right next to us
		var dir := to / maxf(1e-4, dist)
		var flat_f := Vector3(fwd.x, 0, fwd.z).normalized()
		var flat_d := Vector3(dir.x, 0, dir.z).normalized()
		if dir.dot(fwd) < cos_max and (dist > 1.6 or flat_d.dot(flat_f) < cos_max):
			continue
		if not phys.los(eye, c, true):
			continue
		if not barriers.between(eye, c, attacker).is_empty():
			continue
		if dist < best_d:
			best_d = dist
			best = a
	if best == null:
		# maybe we punched an enemy shield
		var wall := barriers.trace(eye, fwd, J.range, attacker)
		if not wall.is_empty():
			_hit_barrier(wall.b, eye + fwd * wall.t, J.damage)
		return null
	var point := best.chest_pos()
	var push := Vector3(point.x - attacker.pos.x, 0, point.z - attacker.pos.z).normalized()
	var power: float = Cfg.PICKUPS.powerMult if attacker.has_buff("power", now) else 1.0
	attacker.shots_fired += 1
	attacker.shots_hit += 1
	_auth = local_auth
	apply_damage(best, attacker, J.damage * power, false, point, "jab", push)
	_kick(best, push.x * J.knockback, 0, push.z * J.knockback, 3.5)
	_auth = "full"
	_flush_claims()
	fx.hit_spark(point, "#ff4d6d", false, true)
	for i in 10:
		fx.glow.emit(point, Vector3(U.rand(-3, 3), U.rand(0, 4), U.rand(-3, 3)), U.col(U.pick(["#ffd166", "#ffffff", "#ff4d6d"])), U.rand(0.1, 0.2), U.rand(0.2, 0.4), {"gravity": 6, "drag": 3})
	return best


## Single authority for damage + eliminations.
func apply_damage(target: Actor, attacker, amount: float, head: bool, point: Vector3, weapon: String, dir: Vector3) -> void:
	if not target.alive or amount <= 0:
		return
	if attacker and attacker != target and attacker.team >= 0 and attacker.team == target.team:
		return
	if _auth == "visual":
		fx.hit_spark(point, target.def.colors[0], false, head)
		return
	if _auth == "claims":
		_claim_damage(target, attacker, amount, head, point, weapon, dir)
		return
	if target.is_protected(now):
		fx.hit_spark(point, "#bdeeff", true, false)
		return
	var shield_dmg := minf(target.shield, amount)
	target.shield -= shield_dmg
	var health_dmg := minf(target.health, amount - shield_dmg)
	target.health -= amount - shield_dmg
	target.last_damage_at = now
	target.recent_damage.append([now, amount])
	target.hit_flinch = minf(1, target.hit_flinch + 0.6)
	if attacker and attacker != target:
		target.last_attacker = attacker
		target.last_attacker_at = now
		attacker.damage_dealt += shield_dmg + health_dmg
	var shield_broke := shield_dmg > 0 and target.shield <= 0
	fx.hit_spark(point, target.def.colors[0], shield_dmg > 0 and health_dmg <= 0, head)
	var from_dir: Vector3 = (attacker.eye_pos() - target.eye_pos()).normalized() if attacker else -dir
	events.emit("damage", {"attacker": attacker, "target": target, "amount": shield_dmg + health_dmg, "shieldDmg": shield_dmg,
		"healthDmg": health_dmg, "head": head, "point": point, "weapon": weapon, "fromDir": from_dir, "shieldBroke": shield_broke})
	if attacker and attacker != target:
		events.emit("hit", {"attacker": attacker, "target": target, "head": head, "shield": shield_dmg > 0 and health_dmg <= 0})
	if target.health <= 0:
		_eliminate(target, attacker, weapon, head)


## Guest: one of our own attacks hit someone. Show it right away (spark, hitmarker via the damage event)
## but leave their health alone; the claim goes to the host, which applies it.
func _claim_damage(target: Actor, attacker, amount: float, head: bool, point: Vector3, weapon: String, dir: Vector3) -> void:
	var c = _pending.get(target)
	if c != null:
		c.dmg += amount
		c.head = c.head or head
	else:
		_pending[target] = {"target": target, "dmg": amount, "head": head, "weapon": weapon, "point": point, "dir": dir, "kv": Vector3.ZERO}
	if target == local_mover:
		return  # our own splash: the host's damage event will tell us
	if target.is_protected(now):
		fx.hit_spark(point, "#bdeeff", true, false)
		return
	var shield_dmg := minf(target.shield, amount)
	var health_dmg := minf(target.health, amount - shield_dmg)
	fx.hit_spark(point, target.def.colors[0], shield_dmg > 0 and health_dmg <= 0, head)
	var from_dir: Vector3 = (attacker.eye_pos() - target.eye_pos()).normalized() if attacker else -dir
	events.emit("damage", {"attacker": attacker, "target": target, "amount": shield_dmg + health_dmg, "shieldDmg": shield_dmg,
		"healthDmg": health_dmg, "head": head, "point": point, "weapon": weapon, "fromDir": from_dir, "shieldBroke": false})


func _eliminate(victim: Actor, killer, weapon: String, head: bool) -> void:
	if not victim.alive:
		return  # never double-count
	victim.alive = false
	victim.health = 0
	victim.deaths += 1
	victim.streak = 0
	victim.respawn_at = now + Cfg.COMBAT.respawnTime
	victim.despawn()
	# credit: direct killer, or whoever hurt them last (falling blocks / self splash)
	var credit: Actor = killer if killer and killer != victim else null
	if credit == null and victim.last_attacker and victim.last_attacker != victim and now - victim.last_attacker_at < 5:
		credit = victim.last_attacker
	if credit:
		credit.kills += 1
		credit.streak += 1
		credit.best_streak = maxi(credit.best_streak, credit.streak)
		credit.score_at = now
		if head:
			credit.headshots += 1
	var pos := victim.pos
	fx.break_apart(pos, victim.def.colors, reduced_motion)
	audio.eliminated(pos + Vector3(0, 1, 0))
	events.emit("kill", {"killer": credit, "victim": victim, "weapon": weapon, "head": head, "time": now})


func clear() -> void:
	barriers.clear()
	_stuck_life.fill(0)
	for i in STUCK:
		_hide(_stuck_buf, i)
	_stuck.buffer = _stuck_buf
	_stuck.visible_instance_count = 0
	for p in _projectiles:
		p.active = false
		if p.whistle:
			p.whistle.stop()
		p.whistle = null
	for k in _buf:
		var b: PackedFloat32Array = _buf[k]
		for i in PROJ_POOL[k]:
			_hide(b, i)
		(_mm[k] as MultiMesh).buffer = b
		(_mm[k] as MultiMesh).visible_instance_count = 0

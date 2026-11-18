class_name Combat
extends Node3D
## Hitscan, projectiles, explosions, punches and the single authority for damage + eliminations
## (port of src/combat/Combat.ts, solo/host path).
## Events: damage, kill, shot, explosion, hit (see Game for the payload keys).

const PROJ_POOL := {"dart": 140, "bubble": 160, "crayon": 20, "bolt": 120, "arrow": 40, "slug": 40, "grenade": 24, "mine": 32, "drill": 8}
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
## breakable walls and cover (null on maps built without it)
var destruction: Destruction
## explosions hit walls and props this much harder than toys (a Crayon Cannon mag takes down a wall)
const BLAST_STRUCT := 6.0
## guest: (id: int, dmg: float, kind: String) its own attack hit a breakable piece (the host applies it)
var on_piece_claim := Callable()
## online: (shooter, gadget id, origin, dir) for every real (not replayed) gadget throw
var on_gadget := Callable()
## burning patches left by pyro gadgets: {pos, r, dps, until, shooter, auth, tick, wid}
var _fires: Array = []
## placed gadgets: {kind, owner, auth, until, node, body, pos, yaw, next_shot, head}
var _deployed: Array = []
## guest: (target: Actor, amount: float) its own Health Infuser healed someone (the host applies it)
var on_heal_claim := Callable()
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
		# gadgets: a round toy grenade and a flat disc mine (its axis follows the surface it sticks to)
		"grenade": Geo.sphere(0.13, 12, 9).to_mesh(white_std.call(0.45)),
		"mine": Geo.cylinder(0.2, 0.22, 0.09, 16).rotate_basis(Basis(Vector3.RIGHT, PI / 2)).to_mesh(white_std.call(0.4)),
		"drill": Geo.cone(0.09, 0.5, 8).rotate_basis(Basis(Vector3.RIGHT, -PI / 2)).to_mesh(white_std.call(0.35)),
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
				"traveled": 0.0, "hits": {}, "color": "#fff", "whistle": null, "power": 1.0, "charge": 1.0, "auth": "full",
				"stuck": false, "arm": 0.0, "normal": Vector3.UP, "born": 0.0})


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
		_hit_piece(world, cfg.damage * _falloff(cfg, world.dist) * power)


## A shot, dart or punch hit a breakable piece.
func _hit_piece(world: Dictionary, dmg: float) -> void:
	if destruction == null or world.is_empty():
		return
	var id := destruction.piece_of(world.collider)
	if id >= 0:
		_piece_hit(id, dmg, "bullet", world.point, world.normal)


## Damage a piece the way the current shot's authority allows: replays only show chips, a guest's own hits are
## claimed (the host decides), everything else is applied here.
func _piece_hit(id: int, dmg: float, kind: String, point: Vector3, normal: Vector3) -> void:
	match _auth:
		"visual":
			destruction.hit_fx(id, point, normal)
		"claims":
			destruction.hit_fx(id, point, normal)
			if on_piece_claim.is_valid():
				on_piece_claim.call(id, dmg, kind)
		_:
			destruction.damage(id, dmg, kind, point, normal)


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
	p.stuck = false
	p.born = now
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
	_update_fires(dt)
	_update_deployed(dt)
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
		if p.stuck:
			# a mine on the ground / a wall: arm, then go off when an enemy comes close (or when it times out)
			p.life -= dt
			p.arm -= dt
			var boom: bool = p.life <= 0
			if p.cfg.has("drill"):
				# drilling: sparks, then the blast
				boom = boom or p.arm <= 0
				if randf() < 0.6:
					fx.glow.emit(p.pos + p.normal * 0.1, p.normal * U.rand(1, 3) + Vector3(U.rand(-1.5, 1.5), U.rand(0, 2), U.rand(-1.5, 1.5)), U.col(U.pick(["#ffd23f", "#ffb347", "#ffffff"])), U.rand(0.06, 0.12), U.rand(0.15, 0.3), {"gravity": 8})
			elif p.arm <= 0 and not boom and p.shooter:
				for o in actors.call():
					if o.alive and o != p.shooter and p.shooter.is_enemy(o) and (o.pos + Vector3(0, 0.6, 0)).distance_to(p.pos) < p.cfg.mine.trigger:
						boom = true
						break
			if boom:
				p.stuck = false
				p.active = false
				explode(p.pos, p.normal, p, null)
				_hide(buf, p.idx)
				continue
			var blink := 1.0 if p.arm <= 0 and fmod(now, 1.0) < 0.12 else 0.0
			_color(buf, p.idx, U.col(p.color).lerp(Color("#ff4d6d"), blink))
			var spin := Basis(Vector3.FORWARD, now * 25.0) if p.cfg.has("drill") else Basis()
			_write(buf, p.idx, Transform3D(_face(-p.normal if p.cfg.has("drill") else p.normal) * spin, p.pos))
			top[p.visual] = maxi(top.get(p.visual, 0), p.idx + 1)
			continue
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
			var hit := {} if cfg.has("mine") or cfg.has("drill") else _trace_actors(prev, d, minf(seg_len, wt), p.shooter, p.radius, p.hits)
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
					explode(point, -d, p, null if cfg.get("gadget", false) else target)  # a grenade's blast also hits the toy it struck
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
			elif not world.is_empty() and (cfg.has("mine") or cfg.has("drill")):
				# a mine sticks where it lands; a drill bites into what it hits
				p.pos = world.point + world.normal * (0.05 if cfg.has("mine") else -0.1)
				p.normal = world.normal
				p.vel = Vector3.ZERO
				p.stuck = true
				p.arm = cfg.drill.delay if cfg.has("drill") else cfg.mine.arm
				p.life = cfg.drill.delay + 0.5 if cfg.has("drill") else cfg.mine.life
				if cfg.has("drill"):
					audio.impact("metal", p.pos, 1.5)
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
				if not cfg.has("explosion"):
					_hit_piece(world, cfg.damage * p.power)
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
			if cfg.has("explosion") and not cfg.has("mine") and not cfg.has("drill"):
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
	var gadget: bool = p.cfg.get("gadget", false)
	var colors := ["#ffb347", "#ff6b2b", "#fff1c1", "#4a4a4a"] if gadget else [p.color, U.pick(PAINT), U.pick(PAINT), "#ffffff"]
	if ex.has("glitch"):
		colors = ["#b388ff", "#4cc9f0", "#ffffff", "#7b2cbf"]
	elif ex.has("flash"):
		colors = ["#ffffff", "#fff8d6", "#ffffff", "#d0d0d0"]
	fx.explosion(center, normal, colors, reduced_motion)
	if gadget and not ex.has("glitch") and not ex.has("flash"):
		fx.impacts.add(point, normal, ex.radius * 0.45, "#1b1b1b", 20, 0.8)  # scorch mark
	else:
		fx.paint_splat(point, normal, p.color, 2.6)
	# extra paint splats on nearby surfaces
	for i in (0 if gadget else 5):
		var d := Vector3(U.rand(-1, 1), U.rand(-1, 0.4), U.rand(-1, 1)).normalized()
		var h := phys.raycast(center, d, ex.radius)
		if not h.is_empty():
			fx.paint_splat(h.point, h.normal, U.pick([p.color] + PAINT), U.rand(0.8, 1.6))
	audio.explosion(center)
	if bricks:
		bricks.blast(center, ex.radius, 3.2)
	if destruction:
		for e in destruction.blast_hits(center, ex.radius, ex.get("pieceDamage", ex.maxDamage * BLAST_STRUCT) * p.power):
			_piece_hit(e.id, e.dmg, "blast", e.point, e.normal)
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
	if ex.has("flash"):
		_flash_from(center, ex.flash.radius, shooter, "flashbang", true)
	if ex.has("flashThrough"):
		# the breach drill: the blast goes through the wall and flashes whoever is on the other side
		_flash_from(point - normal * 1.2, ex.flashThrough.radius, shooter, "drillFlash", false)
	if ex.has("fire"):
		var f: Dictionary = ex.fire
		var ground := phys.raycast(center, Vector3.DOWN, 3.0, true)
		var at: Vector3 = ground.point if not ground.is_empty() else point
		_fires.append({"pos": at, "r": f.radius, "dps": f.dps, "until": now + f.time, "shooter": shooter, "auth": _auth, "tick": 0.0, "wid": p.cfg.id})
		audio.explosion(at)


## Throw / place a gadget (auth as for fire(): "" = this game's own, "visual" = someone else's, replayed).
func throw_gadget(shooter: Actor, gid: String, origin: Vector3, dir: Vector3, auth := "") -> void:
	if not Cfg.GADGETS.has(gid):
		return
	if auth == "":
		auth = local_auth
	var cfg: Dictionary = Cfg.GADGETS[gid]
	if auth != "visual" and on_gadget.is_valid():
		on_gadget.call(shooter, gid, origin, dir)
	shooter.reveal_at = now
	if cfg.has("deploy"):
		_deploy(shooter, gid, origin, dir, auth)
		return
	if cfg.has("heal"):
		heal_burst(shooter, auth)
		return
	if cfg.has("mine"):
		# only so many mines out at once: the oldest one goes
		var mine := []
		for x in _projectiles:
			if x.active and x.shooter == shooter and x.cfg.get("id", "") == gid:
				mine.append(x)
		if mine.size() >= int(cfg.mine.max):
			mine.sort_custom(func(a, b): return a.born < b.born)
			var old: Dictionary = mine[0]
			old.active = false
			old.stuck = false
			_hide(_buf[old.visual], old.idx)
			_dirty[old.visual] = true
	_auth = auth
	_spawn_projectile(shooter, cfg, origin, dir, origin, 1.0, 1.0, auth)
	_auth = "full"


## A blinding pop at `at`: enemies within r who can see it are flashed (a 2-point hit carries it, so it goes
## through claims online like any hit). `need_look`: only if they're facing it.
func _flash_from(at: Vector3, r: float, shooter: Actor, wid: String, need_look: bool) -> void:
	fx.glow.emit(at, Vector3.ZERO, Color.WHITE, 9.0, 0.18)
	fx.flash_light(at, "#ffffff", 140, 0.25, r * 1.5)
	audio.zap(at)
	for a in actors.call():
		if not a.alive or a == shooter or not shooter.is_enemy(a):
			continue
		var eye: Vector3 = a.eye_pos()
		if eye.distance_to(at) > r or not phys.los(at, eye, true):
			continue
		if need_look and a.forward().dot((at - eye).normalized()) < -0.2:
			continue  # looking away
		apply_damage(a, shooter, 2.0, false, eye, wid, (eye - at).normalized())


## Health Infuser: heal the user and teammates close by (guests' heals go to the host as claims).
func heal_burst(healer: Actor, auth := "full") -> void:
	var cfg: Dictionary = Cfg.GADGETS.healthInfuser
	var c := healer.chest_pos()
	for i in 24:
		var a := randf() * TAU
		fx.glow.emit(c + Vector3(cos(a), U.rand(-0.6, 0.6), sin(a)) * U.rand(0.3, 1.2), Vector3(0, U.rand(1, 3), 0), U.col(U.pick(["#7dff6b", "#ffffff", "#2dc653"])), U.rand(0.12, 0.25), U.rand(0.4, 0.8), {"gravity": -1, "drag": 2})
	audio.pickup("health", c, healer.is_player)
	if auth == "visual":
		return
	for a in actors.call():
		if not a.alive:
			continue
		if a != healer and (healer.team < 0 or a.team != healer.team or a.pos.distance_to(healer.pos) > cfg.radius):
			continue
		if auth == "claims":
			if on_heal_claim.is_valid():
				on_heal_claim.call(a, cfg.heal)
		else:
			a.health = minf(a.max_health, a.health + cfg.heal)


## Place a stairs / turret gadget a step in front of where it was thrown from.
func _deploy(owner: Actor, gid: String, origin: Vector3, dir: Vector3, auth: String) -> void:
	var cfg: Dictionary = Cfg.GADGETS[gid]
	# one of each per toy: the old one folds away
	for d in _deployed.duplicate():
		if d.owner == owner and d.kind == cfg.deploy:
			_undeploy(d)
	var flat := Vector3(dir.x, 0, dir.z)
	flat = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	var at := origin + flat * (1.0 if cfg.deploy == "stairs" else 1.6)
	var ground := phys.raycast(at + Vector3(0, 0.5, 0), Vector3.DOWN, 6.0, true)
	if not ground.is_empty():
		at = ground.point
	var yaw := atan2(-flat.x, -flat.z)
	var node := Node3D.new()
	node.transform = Transform3D(Basis(Vector3.UP, yaw), at)
	add_child(node)
	var body := StaticBody3D.new()
	body.collision_layer = Phys.WORLD
	body.collision_mask = 0
	body.set_meta("mat", "plastic")
	node.add_child(body)
	var d := {"kind": cfg.deploy, "owner": owner, "auth": auth, "until": now + cfg.life, "node": node, "body": body, "pos": at, "yaw": yaw, "next_shot": now + 0.8, "head": null}
	if cfg.deploy == "stairs":
		var a := Mats.plastic(cfg.colors.main, {"rough": 0.4})
		var b := Mats.plastic(cfg.colors.accent, {"rough": 0.4})
		for i in int(cfg.steps):
			var h: float = cfg.rise * (i + 1)
			var z: float = -cfg.run * (i + 0.5)
			var size := Vector3(cfg.width, h, cfg.run)
			node.add_child(Geo.rounded_box(size.x, size.y, size.z, 2, 0.04).mesh_instance(a if i % 2 == 0 else b, Vector3(0, h / 2, z), Basis(), true))
			var cs := CollisionShape3D.new()
			var sh := BoxShape3D.new()
			sh.size = size
			cs.shape = sh
			cs.position = Vector3(0, h / 2, z)
			body.add_child(cs)
	else:
		var dark := Mats.plastic(cfg.colors.main, {"rough": 0.4})
		var gold := Mats.plastic(cfg.colors.accent, {"rough": 0.3})
		node.add_child(Geo.cylinder(0.32, 0.4, 0.5, 14).mesh_instance(dark, Vector3(0, 0.25, 0), Basis(), true))
		var head := Node3D.new()
		head.position = Vector3(0, 0.75, 0)
		head.add_child(Geo.rounded_box(0.45, 0.32, 0.5, 2, 0.08).mesh_instance(gold, Vector3.ZERO, Basis(), true))
		head.add_child(Geo.cylinder(0.05, 0.05, 0.5, 8).mesh_instance(dark, Vector3(0, 0, -0.42), Basis(Vector3.RIGHT, PI / 2), true))
		node.add_child(head)
		d.head = head
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = Vector3(0.7, 1.0, 0.7)
		cs.shape = sh
		cs.position = Vector3(0, 0.5, 0)
		body.add_child(cs)
	_deployed.append(d)
	audio.punch(true, at)


func _undeploy(d: Dictionary) -> void:
	_deployed.erase(d)
	fx.reassemble(d.pos + Vector3(0, -0.5, 0), ["#ffd23f", "#3a86ff"])
	(d.node as Node).queue_free()


## Turrets look for the nearest enemy they can see and shoot it; everything folds away when its time is up.
func _update_deployed(_dt: float) -> void:
	for d in _deployed.duplicate():
		if now >= d.until or d.owner == null:
			_undeploy(d)
			continue
		if d.kind != "turret" or now < d.next_shot:
			continue
		var cfg: Dictionary = Cfg.GADGETS.turret
		var muzzle: Vector3 = (d.pos as Vector3) + Vector3(0, 0.8, 0)
		var best: Actor = null
		var bd: float = cfg.range
		for a in actors.call():
			if not a.alive or a.cloaked or not d.owner.is_enemy(a):
				continue
			var dist := muzzle.distance_to(a.chest_pos())
			if dist < bd and phys.los(muzzle, a.chest_pos(), true):
				bd = dist
				best = a
		if best == null:
			d.next_shot = now + 0.25
			continue
		var to := best.chest_pos() - muzzle
		(d.head as Node3D).rotation = Vector3(atan2(to.y, Vector2(to.x, to.z).length()), atan2(-to.x, -to.z) - float(d.yaw), 0)
		d.next_shot = now + float(cfg.interval)
		var dir := U.cone_direction(to.normalized(), deg_to_rad(cfg.spreadDeg))
		_auth = d.auth
		_hitscan(d.owner, cfg.gun, muzzle + to.normalized() * 0.5, dir, muzzle + to.normalized() * 0.6, 1.0)
		_auth = "full"
		_flush_claims()
		fx.muzzle(muzzle + to.normalized() * 0.6, to.normalized(), "#ffd23f", 0.6)
		if randf() < 0.5:
			audio.gunshot("rapidRascal", muzzle, false)


## Burning patches: flames, and damage four times a second to enemies standing in them.
func _update_fires(dt: float) -> void:
	if _fires.is_empty():
		return
	var keep := []
	for z in _fires:
		if now >= z.until or z.shooter == null:
			continue
		keep.append(z)
		var zp: Vector3 = z.pos
		for i in 3:
			var a := randf() * TAU
			var rr := sqrt(randf()) * float(z.r)
			fx.glow.emit(zp + Vector3(cos(a) * rr, 0.15, sin(a) * rr), Vector3(U.rand(-0.3, 0.3), U.rand(1.5, 3.2), U.rand(-0.3, 0.3)), U.col(U.pick(["#ff6b2b", "#ffb347", "#ffd23f", "#d62828"])), U.rand(0.25, 0.5), U.rand(0.3, 0.6), {"gravity": -2, "drag": 1})
		if randf() < 0.3:
			fx.soft.emit(zp + Vector3(U.rand(-1, 1), 0.6, U.rand(-1, 1)), Vector3(0, U.rand(0.8, 1.6), 0), Color(0.25, 0.22, 0.2), U.rand(0.8, 1.4), U.rand(0.8, 1.4), {"grow": 1.5, "drag": 1, "alpha": 0.35})
		z.tick -= dt
		if z.tick > 0:
			continue
		z.tick = 0.25
		var sh: Actor = z.shooter
		_auth = z.auth
		for a in actors.call():
			if not a.alive or a == sh:
				continue
			if sh.team >= 0 and a.team == sh.team:
				continue
			var d := Vector2(a.pos.x - zp.x, a.pos.z - zp.z).length()
			if d > float(z.r) or absf(a.pos.y - zp.y) > 1.8:
				continue
			apply_damage(a, sh, float(z.dps) * 0.25, false, a.chest_pos(), z.wid, Vector3.UP)
		_auth = "full"
		_flush_claims()
	_fires = keep


## Arrows stuck inside `box` (their middle point).
func stuck_in(box: AABB) -> int:
	var c := 0
	for i in STUCK:
		if _stuck_life[i] > 0 and box.has_point(Vector3(_stuck_buf[i * 16 + 3], _stuck_buf[i * 16 + 7], _stuck_buf[i * 16 + 11])):
			c += 1
	return c


## The wall these arrows were stuck in is gone: drop them.
func clear_stuck_in(box: AABB) -> void:
	var any := false
	for i in STUCK:
		if _stuck_life[i] > 0 and box.has_point(Vector3(_stuck_buf[i * 16 + 3], _stuck_buf[i * 16 + 7], _stuck_buf[i * 16 + 11])):
			_stuck_life[i] = 0
			_hide(_stuck_buf, i)
			any = true
	if any:
		_stuck.buffer = _stuck_buf


func _stick_arrow(point: Vector3, d: Vector3, color: String) -> void:
	var i := _stuck_next
	_stuck_next = (_stuck_next + 1) % STUCK
	_write(_stuck_buf, i, Transform3D(_face(d), point - d * 0.5))
	_color(_stuck_buf, i, U.col(color))
	_stuck.buffer = _stuck_buf
	_stuck_life[i] = 8
	_stuck.visible_instance_count = maxi(_stuck.visible_instance_count, i + 1)


## Melee: swing the class's toy weapon. Everyone whose body is inside the zone in front gets hit (a big,
## forgiving zone: within reach plus their body radius, inside the arc, a wide band up and down).
## Walls and props in the way take a chip too. Returns the toys that got hit.
func melee(attacker: Actor) -> Array:
	var md := attacker.melee_def()
	var eye := attacker.eye_pos()
	var fwd := attacker.forward()
	var flat_f := Vector3(fwd.x, 0, fwd.z).normalized()
	attacker.reveal_at = now
	attacker.spawn_protect_until = minf(attacker.spawn_protect_until, now)
	var half := deg_to_rad(md.arcDeg) / 2.0
	var power: float = Cfg.PICKUPS.powerMult if attacker.has_buff("power", now) else 1.0
	var hits := []
	_auth = local_auth
	for a in actors.call():
		if not a.alive or not attacker.is_enemy(a):
			continue
		var r: float = a.def.hitbox.bodyR
		# test the feet, chest and head: any of them in the zone counts
		var hit_at = null
		for pt in [a.pos + Vector3(0, 0.35, 0), a.chest_pos(), a.head_pos()]:
			var to: Vector3 = pt - eye
			var flat := Vector3(to.x, 0, to.z)
			var dist := flat.length()
			if dist > md.range + r or absf(to.y) > 2.2:
				continue
			# the body's width widens the arc up close
			var allow := half + (atan2(r, maxf(dist, 0.1)) if dist > 0.01 else PI)
			if dist > 0.3 and flat_f.angle_to(flat / dist) > allow:
				continue
			if not phys.los(eye, pt, true):
				continue
			hit_at = pt
			break
		if hit_at == null:
			continue
		var wall := barriers.between(eye, hit_at, attacker)
		if not wall.is_empty():
			_hit_barrier(wall.b, hit_at, md.damage)
			continue
		var push := Vector3(a.pos.x - attacker.pos.x, 0, a.pos.z - attacker.pos.z).normalized()
		apply_damage(a, attacker, md.damage * power, false, hit_at, md.id, push)
		_kick(a, push.x * md.knockback, 0, push.z * md.knockback, 3.0)
		fx.hit_spark(hit_at, md.color, false, true)
		hits.append(a)
	attacker.shots_fired += 1
	if hits.size():
		attacker.shots_hit += 1
	else:
		var shield := barriers.trace(eye, fwd, md.range, attacker)
		if not shield.is_empty():
			_hit_barrier(shield.b, eye + fwd * shield.t, md.damage)
		else:
			_hit_piece(phys.raycast(eye, fwd, md.range), md.damage * power)
	_auth = "full"
	_flush_claims()
	# a quick swoosh of light along the swing
	for i in 8:
		var a2 := lerpf(-half, half, float(i) / 7.0)
		var d := flat_f.rotated(Vector3.UP, a2)
		fx.glow.emit(eye + d * md.range * 0.75 + Vector3(0, -0.25, 0), d * 2.0, U.col(md.color), 0.18, 0.18, {"drag": 4})
	return hits


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
	target.last_damage_weapon = weapon
	if weapon == "glitchJug":
		target.glitched_until = now + float(Cfg.GADGETS.glitchJug.explosion.glitch)
	if weapon == "flashbang" or weapon == "drillFlash":
		var fl: Dictionary = Cfg.GADGETS.flashbang.explosion.flash if weapon == "flashbang" else Cfg.GADGETS.breachDrill.explosion.flashThrough
		target.flash_len = float(fl.time)
		target.flashed_until = maxf(target.flashed_until, now + float(fl.time))
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
	_fires.clear()
	for d in _deployed.duplicate():
		(d.node as Node).queue_free()
	_deployed.clear()
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

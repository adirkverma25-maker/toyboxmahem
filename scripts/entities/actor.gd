class_name Actor
extends RefCounted
## Anything that walks, shoots and can be eliminated: the player and every bot (port of src/entities/Actor.ts).
## The TypeScript game moved a Rapier kinematic capsule with a character controller (slide, 0.56 m autostep,
## 0.35 m ground snap, 50 degree max climb). Here a CharacterBody3D does the same job (see cc_move).

class Intent:
	var wish := Vector3.ZERO  # world-space XZ, length 0..1
	var sprint := false
	var jump := false  # pressed this frame
	var crouch := false  # held
	var crouch_pressed := false
	var dash := false  # pressed
	var ads := false

	func clear() -> void:
		wish = Vector3.ZERO
		jump = false
		dash = false
		crouch_pressed = false
		sprint = false
		crouch = false
		ads = false

static var next_id := 1

const AUTOSTEP_HEIGHT := 0.56
const SNAP := 0.35
const MAX_CLIMB := 50.0

var id: int
var name: String
var def: Dictionary
var is_player: bool
var phys: Phys
var body: CharacterBody3D
var _shape: CapsuleShape3D
var _shape_node: CollisionShape3D
var pos := Vector3.ZERO
var vel := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var grounded := false
var ground_mat := "wood"
var last_grounded := -10.0
var jump_buffer_at := -10.0
var jumped := false
var crouching := false
var crouch_t := 0.0
var sliding := false
var slide_t := 0.0
var slide_ready_at := 0.0
var _slide_buffer_at := -10.0
var _slide_dir := Vector3.ZERO
var dashing := false
var dash_t := 0.0
var dash_ready_at := 0.0
var _dash_dir := Vector3.ZERO
var _dash_from := Vector3.ZERO
var _half_height: float = Cfg.MOVE.standHalfHeight
var health: float = Cfg.COMBAT.maxHealth
var shield := 0.0
var alive := true
var respawn_at := 0.0
var last_damage_at := -99.0
var spawn_protect_until := 0.0
var weapons: Array = [null, null]
var slot := 0
var buffs := {"turbo": 0.0, "infinite": 0.0, "power": 0.0}
var kills := 0
var deaths := 0
var streak := 0
var best_streak := 0
var damage_dealt := 0.0
var shots_fired := 0
var shots_hit := 0
var headshots := 0
## -1 = no team (free-for-all), 0 = Sunrise, 1 = Moonbeam, 2 = Clover
var team := -1
var last_attacker: Actor = null
var last_attacker_at := -99.0
var ads := 0.0
var fire_kick := 0.0
var hit_flinch := 0.0
## ToyRig (null for the player)
var model = null
var _step_acc := 0.0
var _ground_probe_t := 0.0
var last_footstep_side := 0
## horizontal speed last frame
var speed := 0.0
var score_at := 0.0
# ---- abilities
var abilities: Array = ["dash", "grapple"]
## last time this toy attacked (firing or punching breaks cloak)
var reveal_at := -99.0
var jab_ready_at := 0.0
var grapple_ready_at := 0.0
var cloak_ready_at := 0.0
var shield_ready_at := 0.0
var cloaked := false
var cloak_start := 0.0
## seconds left on the punch animation
var jab_t := 0.0
## {anchor, start, check_at, check_dist, climbing} or null
var grapple = null
# ---- revive (team modes)
var revive_t := 0.0
var reviver: Actor = null
var revives := 0
## recent damage taken: [[t, amount]...] (bots use it to decide when to run)
var recent_damage: Array = []
var _mantle = null
## flying off a jump pad (cleared on landing)
var launched := false
## riding a zipline: {line, a, b, d, len, t, t0, t1, dir, speed, start} (null when not)
var zip = null
const ZIP_SPEED := 15.0
const ZIP_HANG := 2.15  # feet below the cable
var _grapple_end_time := 0.0
var disposed := false


func _init(d: Dictionary, player: bool, p: Phys) -> void:
	id = next_id
	next_id += 1
	def = d
	is_player = player
	phys = p
	name = d.name
	body = CharacterBody3D.new()
	body.collision_layer = Phys.CHAR
	body.collision_mask = Phys.WORLD | Phys.DEBRIS
	body.floor_max_angle = deg_to_rad(MAX_CLIMB)
	body.floor_snap_length = SNAP
	body.floor_stop_on_slope = true
	body.floor_block_on_wall = true
	body.safe_margin = 0.02
	body.max_slides = 6
	body.up_direction = Vector3.UP
	_shape = CapsuleShape3D.new()
	_shape.radius = Cfg.MOVE.radius
	_shape.height = (_half_height + Cfg.MOVE.radius) * 2.0
	_shape_node = CollisionShape3D.new()
	_shape_node.shape = _shape
	_shape_node.position.y = _half_height + Cfg.MOVE.radius
	body.add_child(_shape_node)
	phys.add_child(body)
	body.global_position = Vector3(0, -50, 0)


func weapon() -> WeaponState:
	return weapons[slot]


func has(ability: String) -> bool:
	return abilities.has(ability)


func eye_height() -> float:
	return Cfg.MOVE.standEye + (Cfg.MOVE.crouchEye - Cfg.MOVE.standEye) * crouch_t


func eye_pos() -> Vector3:
	return Vector3(pos.x, pos.y + eye_height(), pos.z)


func chest_pos() -> Vector3:
	return Vector3(pos.x, pos.y + 1.05 - crouch_t * 0.38, pos.z)


func head_pos() -> Vector3:
	return Vector3(pos.x, pos.y + def.hitbox.headY - crouch_t * 0.42, pos.z)


## [a, b] ends of the body capsule
func body_segment() -> Array:
	var hb: Dictionary = def.hitbox
	return [Vector3(pos.x, pos.y + hb.bodyBottom + hb.bodyR, pos.z),
		Vector3(pos.x, pos.y + maxf(hb.bodyBottom + hb.bodyR + 0.05, hb.bodyTop - hb.bodyR - crouch_t * 0.4), pos.z)]


func forward() -> Vector3:
	return Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


func is_enemy(o: Actor) -> bool:
	return o != self and (team < 0 or o.team != team)


func is_protected(now: float) -> bool:
	return now < spawn_protect_until


func has_buff(k: String, now: float) -> bool:
	return buffs[k] > now


func speed_mult(now: float) -> float:
	return Cfg.PICKUPS.turboMult if has_buff("turbo", now) else 1.0


## Popped but still revivable: team modes only, until the respawn timer runs out.
func is_downed(now: float) -> bool:
	return not alive and team >= 0 and respawn_at > now


func give_weapon(wid: String, s: int, scope := "") -> void:
	weapons[s] = WeaponState.new(wid, scope)


func teleport(feet: Vector3) -> void:
	pos = feet
	vel = Vector3.ZERO
	_sync_collider()


## Push the collider to the current position without touching velocity.
func sync() -> void:
	_sync_collider()


func _sync_collider() -> void:
	if disposed:
		return
	body.global_position = pos


func _set_half_height(h: float) -> void:
	if disposed or absf(_half_height - h) < 1e-3:
		return
	_half_height = h
	_shape.height = (h + Cfg.MOVE.radius) * 2.0
	_shape_node.position.y = h + Cfg.MOVE.radius


## Cloak toggles: on if ready, off if already active. Cooldown = time spent cloaked + base.
func toggle_cloak(now: float) -> bool:
	if cloaked:
		end_cloak(now)
		return true
	if now < cloak_ready_at:
		return false
	cloaked = true
	cloak_start = now
	return true


func end_cloak(now: float) -> void:
	if not cloaked:
		return
	var active := minf(Cfg.ABILITIES.cloak.maxActive, now - cloak_start)
	cloaked = false
	cloak_ready_at = now + active + Cfg.ABILITIES.cloak.baseCooldown


## Jump pad: fly on this velocity (gravity does the rest).
func launch(v: Vector3) -> void:
	end_zip()
	grapple = null
	_mantle = null
	dashing = false
	sliding = false
	vel = v
	grounded = false
	jumped = true
	launched = true
	last_grounded = -10
	jump_buffer_at = -10


## Grab a zipline (cable from ca to cb) at t, riding toward cb (dir 1) or ca (dir -1).
func start_zip(line: int, ca: Vector3, cb: Vector3, t: float, dir: int, margin: float, now: float) -> void:
	var len := maxf(0.01, ca.distance_to(cb))
	grapple = null
	_mantle = null
	dashing = false
	sliding = false
	launched = false
	zip = {"line": line, "a": ca, "b": cb, "d": (cb - ca) / len, "len": len, "t": t, "t0": margin / len, "t1": 1 - margin / len,
		"dir": dir, "speed": maxf(4.0, Vector2(vel.x, vel.z).length() * 0.6), "start": now}


func end_zip() -> void:
	zip = null


func _zip_step(intent: Intent, dt: float, now: float, ev: Dictionary) -> void:
	var z: Dictionary = zip
	var along: Vector3 = z.d * float(z.dir)
	if intent.jump and now - z.start > 0.15:
		# let go with a hop, keeping the ride's speed
		vel = along * z.speed * 0.8 + Vector3(0, 6.5, 0)
		end_zip()
		jumped = true
		jump_buffer_at = -10
		intent.jump = false
		_emit(ev, "on_jump", [self])
		return
	z.speed = minf(ZIP_SPEED, z.speed + 26 * dt)
	z.t += z.dir * z.speed * dt / z.len
	var done := false
	if z.t <= z.t0 or z.t >= z.t1:
		z.t = clampf(z.t, z.t0, z.t1)
		done = now - z.start > 0.2
	var cable: Vector3 = (z.a as Vector3).lerp(z.b, z.t)
	var desired := cable - Vector3(0, ZIP_HANG, 0) - pos
	var mv := cc_move(desired, false)
	pos += mv
	grounded = false
	vel = along * z.speed
	speed = z.speed
	# something in the way: drop off
	if desired.length() > 0.08 and mv.length() < desired.length() * 0.25 and now - z.start > 0.35:
		done = true
	if done:
		# gentle dismount at the end of the line
		vel = along * z.speed * 0.25 + Vector3(0, 3.0, 0)
		end_zip()
		jumped = true


func start_grapple(anchor: Vector3, now: float) -> void:
	end_zip()
	launched = false
	grapple = {"anchor": anchor, "start": now, "check_at": now + 0.3, "check_dist": INF, "climbing": false}
	grapple_ready_at = now + Cfg.ABILITIES.grapple.cooldown
	dashing = false
	sliding = false
	grounded = false


func _release_grapple(did_jump: bool, ev: Dictionary) -> void:
	var g = grapple
	if g == null:
		return
	grapple = null
	vel *= 0.7
	# pop up over the ledge we were pulled to, and keep moving onto it
	vel.y = minf(vel.y, 7)
	var anchor: Vector3 = g.anchor
	if anchor.y > pos.y + 0.3:
		vel.y = maxf(vel.y, 6)
	var hx := anchor.x - pos.x
	var hz := anchor.z - pos.z
	var hl := Vector2(hx, hz).length()
	if hl > 0.3 and hl < 3 and absf(anchor.y - pos.y) < 2.5:
		var s := maxf(4.5, Vector2(vel.x, vel.z).length())
		vel.x = hx / hl * s
		vel.z = hz / hl * s
		if anchor.y > pos.y - 0.2:
			vel.y = maxf(vel.y, 7.5)
			_mantle = {"until": _grapple_end_time + 0.45, "dir": Vector3(hx / hl, 0, hz / hl)}
	if did_jump:
		vel.y = maxf(vel.y, 7.5)
	jumped = true
	_emit(ev, "on_grapple_end", [self])


func damage_in_last(seconds: float, now: float) -> float:
	var s := 0.0
	for d in recent_damage:
		if now - d[0] <= seconds:
			s += d[1]
	return s


func spawn(at: Vector3, y: float, now: float) -> void:
	alive = true
	revive_t = 0
	reviver = null
	cloaked = false
	grapple = null
	_mantle = null
	zip = null
	launched = false
	jab_t = 0
	recent_damage = []
	health = Cfg.COMBAT.maxHealth
	shield = 0
	buffs = {"turbo": 0.0, "infinite": 0.0, "power": 0.0}
	last_damage_at = -99
	spawn_protect_until = now + Cfg.COMBAT.spawnProtection
	yaw = y
	pitch = 0
	sliding = false
	dashing = false
	crouching = false
	crouch_t = 0
	_set_half_height(Cfg.MOVE.standHalfHeight)
	last_attacker = null
	if not disposed:
		body.process_mode = Node.PROCESS_MODE_INHERIT
		_shape_node.disabled = false
	teleport(at)
	grounded = false
	hit_flinch = 0


func despawn() -> void:
	cloaked = false
	grapple = null
	zip = null
	launched = false
	if disposed:
		return
	_shape_node.disabled = true


static func _emit(ev: Dictionary, k: String, args: Array) -> void:
	var c = ev.get(k)
	if c is Callable and c.is_valid():
		c.callv(args)


## Character controller step: move the capsule by `desired` (slide along walls, step up small ledges,
## stick to the ground). Returns the movement actually made; sets `grounded`.
func cc_move(desired: Vector3, snap := true) -> Vector3:
	if disposed:
		return Vector3.ZERO
	var pd := body.get_process_delta_time()
	if pd <= 0:
		pd = 1.0 / 60.0
	var start := body.global_transform
	var was_on_floor := body.is_on_floor()
	body.floor_snap_length = SNAP if snap else 0.0
	body.velocity = desired / pd
	body.move_and_slide()
	var mv := body.global_position - start.origin
	var on_floor := body.is_on_floor()
	# autostep: blocked sideways while on the ground -> try going up, across, then back down
	var dh := Vector2(desired.x, desired.z).length()
	var mh := Vector2(mv.x, mv.z).length()
	if dh > 1e-4 and mh < dh * 0.7 and (was_on_floor or grounded) and desired.y <= 0.05:
		var stepped = _try_step(start, Vector3(desired.x, 0, desired.z), mh)
		if stepped != null:
			body.global_transform = stepped
			mv = stepped.origin - start.origin
			on_floor = true
	# nudge dynamic debris we walk into
	for i in body.get_slide_collision_count():
		var c := body.get_slide_collision(i)
		var o := c.get_collider()
		if o is RigidBody3D:
			(o as RigidBody3D).apply_central_impulse(-c.get_normal() * minf(4.0, desired.length() / pd * 0.25))
	grounded = on_floor
	return mv


func _try_step(start: Transform3D, horiz: Vector3, moved: float):
	var col := KinematicCollision3D.new()
	var t := start
	var up := Vector3(0, AUTOSTEP_HEIGHT, 0)
	if body.test_move(t, up, col):
		up = col.get_travel()
	if up.y < 0.05:
		return null
	t.origin += up
	var h := horiz
	if body.test_move(t, h, col):
		h = col.get_travel()
	if Vector2(h.x, h.z).length() <= moved + 1e-3:
		return null
	t.origin += h
	if not body.test_move(t, Vector3(0, -(up.y + 0.05), 0), col):
		return null
	if col.get_normal().y < cos(deg_to_rad(MAX_CLIMB)):
		return null
	t.origin += col.get_travel()
	if t.origin.y - start.origin.y < 0.01:
		return null
	return t


## Shared locomotion for player and bots. `ev` holds optional callbacks: on_jump(a), on_land(a, impact),
## on_slide(a), on_dash(a, from), on_footstep(a), on_grapple_end(a).
func move(intent: Intent, dt: float, now: float, ev: Dictionary = {}) -> void:
	if not alive or disposed:
		return
	var hspeed := Vector2(vel.x, vel.z).length()
	var sm := speed_mult(now)
	var M: Dictionary = Cfg.MOVE
	# --- slide start
	if intent.crouch_pressed:
		_slide_buffer_at = now
	var slide_wanted := now - _slide_buffer_at < 0.15 and intent.crouch
	if slide_wanted and (grounded or now - last_grounded < 0.08) and not sliding and hspeed > M.walkSpeed * 1.15 and now >= slide_ready_at:
		_slide_buffer_at = -10
		sliding = true
		slide_t = M.slideDuration
		_slide_dir = Vector3(vel.x, 0, vel.z).normalized()
		var boost := maxf(hspeed, M.slideBoost * sm)
		vel.x = _slide_dir.x * boost
		vel.z = _slide_dir.z * boost
		_emit(ev, "on_slide", [self])
	# --- crouch (stay crouched if there's no head room)
	var want_crouch := intent.crouch or sliding
	if not want_crouch and crouching:
		if not phys.capsule_fits(pos, M.radius - 0.02, M.standHalfHeight):
			want_crouch = true
	crouching = want_crouch
	_set_half_height(M.crouchHalfHeight if crouching else M.standHalfHeight)
	crouch_t = U.damp(crouch_t, 1.0 if crouching else 0.0, 14, dt)
	# --- zipline ride (overrides everything else)
	if zip != null:
		_zip_step(intent, dt, now, ev)
		return
	# --- grapple pull (overrides everything else)
	if grapple != null:
		var g: Dictionary = grapple
		var anchor: Vector3 = g.anchor
		var to := Vector3(anchor.x - pos.x, anchor.y - (pos.y + 1.0), anchor.z - pos.z)
		var dist := to.length()
		var t: float = now - g.start
		var stalled := false
		# pressed against a wall below the ledge: climb straight up it until we're level with the top
		if g.climbing and pos.y >= anchor.y - 0.3:
			g.climbing = false
		if now >= g.check_at and g.climbing:
			g.check_dist = dist
			g.check_at = now + 0.25
		if now >= g.check_at:
			# barely got closer in the last quarter second = something is in the way
			stalled = g.check_dist - dist < 1.2
			g.check_dist = dist
			g.check_at = now + 0.25
		if dist < 1.3 or t > Cfg.ABILITIES.grapple.maxTime or stalled or (intent.jump and t > 0.12):
			_grapple_end_time = now
			_release_grapple(intent.jump and t > 0.12, ev)
			intent.jump = false
			jump_buffer_at = -10
		else:
			var sp: float = Cfg.ABILITIES.grapple.speed * minf(1, 0.45 + t * 3)
			if g.climbing:
				vel = Vector3(0, sp * 0.8, 0)
			else:
				vel = to * (sp / maxf(1e-3, dist))
	# --- mantle over the ledge we hooked
	if _mantle != null:
		if now > _mantle.until or grounded:
			_mantle = null
		else:
			var md: Vector3 = _mantle.dir
			var along := vel.x * md.x + vel.z * md.z
			if along < 4.5:
				vel.x += md.x * (4.5 - along)
				vel.z += md.z * (4.5 - along)
			if vel.y < 2:
				vel.y = 2
	# --- dash
	if intent.dash and has("dash") and now >= dash_ready_at and not dashing and grapple == null:
		dashing = true
		dash_t = M.dashDuration
		dash_ready_at = now + M.dashCooldown
		if intent.wish.length_squared() > 0.01:
			_dash_dir = Vector3(intent.wish.x, 0, intent.wish.z).normalized()
		else:
			_dash_dir = Vector3(-sin(yaw), 0, -cos(yaw))
		_dash_from = pos
		sliding = false
		_emit(ev, "on_dash", [self, _dash_from])
	# --- target speed
	var target: float = M.walkSpeed
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var forwardish := intent.wish.length_squared() > 0.01 and intent.wish.dot(fwd) > 0.5
	if crouching:
		target = M.crouchSpeed
	elif intent.sprint and forwardish and ads < 0.3:
		target = M.walkSpeed * M.sprintMult
	var w := weapon()
	if w and ads > 0:
		target *= 1 + (w.cfg.adsMoveMult - 1) * ads
	if w and w.drawing() and w.cfg.has("charge"):
		target = minf(target, M.walkSpeed) * w.cfg.charge.moveMult
	target *= sm

	if grapple != null:
		pass  # velocity already set by the hook
	elif dashing:
		dash_t -= dt
		var sp: float = M.dashSpeed * sm
		vel.x = _dash_dir.x * sp
		vel.z = _dash_dir.z * sp
		if vel.y < 0:
			vel.y = 0
		if dash_t <= 0:
			dashing = false
			# keep some momentum
			vel.x *= 0.45
			vel.z *= 0.45
	elif sliding:
		slide_t -= dt
		var cur := Vector2(vel.x, vel.z).length()
		var ns := maxf(M.crouchSpeed, cur - 9 * dt)
		# slight steering
		if intent.wish.length_squared() > 0.01:
			_slide_dir = _slide_dir.lerp(intent.wish, 1.5 * dt).normalized()
		vel.x = _slide_dir.x * ns
		vel.z = _slide_dir.z * ns
		if slide_t <= 0 or (not grounded and now - last_grounded > 0.25):
			sliding = false
			slide_ready_at = now + M.slideCooldown
	elif grounded:
		var tx := intent.wish.x * target
		var tz := intent.wish.z * target
		var dx := tx - vel.x
		var dz := tz - vel.z
		var dl := Vector2(dx, dz).length()
		var accel: float = M.groundAccel if intent.wish.length_squared() > 0.01 else M.groundDecel
		var step := minf(dl, accel * dt)
		if dl > 1e-5:
			vel.x += dx / dl * step
			vel.z += dz / dl * step
	else:
		# small air control: steer without exceeding current / target speed
		var cur := Vector2(vel.x, vel.z).length()
		vel.x += intent.wish.x * M.airAccel * dt
		vel.z += intent.wish.z * M.airAccel * dt
		var ns := Vector2(vel.x, vel.z).length()
		var cap := maxf(maxf(cur, target * M.airControl + cur * (1 - M.airControl)), target * 0.6)
		if ns > cap:
			vel.x *= cap / ns
			vel.z *= cap / ns
	# --- jump with coyote time + input buffer
	if intent.jump:
		jump_buffer_at = now
	var can_jump: bool = (grounded or now - last_grounded < M.coyoteTime) and not jumped
	if now - jump_buffer_at <= M.jumpBuffer and can_jump and not dashing and grapple == null:
		vel.y = M.jumpVelocity
		grounded = false
		jumped = true
		jump_buffer_at = -10
		if sliding:
			sliding = false
			slide_ready_at = now + M.slideCooldown
		_emit(ev, "on_jump", [self])
	# --- gravity
	if not dashing and grapple == null:
		vel.y -= M.gravity * dt
	if vel.y < -40:
		vel.y = -40

	# --- collide & slide
	var desired := vel * dt
	var was_grounded := grounded
	var mv := cc_move(desired, vel.y <= 0 and grapple == null)
	pos += mv
	if grounded:
		last_grounded = now
		if vel.y <= 0:
			launched = false
			if not was_grounded and vel.y < -3:
				_emit(ev, "on_land", [self, clampf(-vel.y / 14, 0, 1)])
			vel.y = 0
			jumped = false
	# stop velocity building up against walls / ceilings
	if dt > 0:
		var dh := Vector2(desired.x, desired.z).length()
		var mh := Vector2(mv.x, mv.z).length()
		if dh > 1e-4 and mh < dh * 0.7 and not dashing and grapple == null and _mantle == null:
			vel.x = mv.x / dt * 0.9 + vel.x * 0.1
			vel.z = mv.z / dt * 0.9 + vel.z * 0.1
		if desired.y > 0 and mv.y < desired.y * 0.4 and grapple == null:
			vel.y = minf(vel.y, 0)
		var gr = grapple
		if gr != null and not gr.climbing and dh > 1e-3 and mh < dh * 0.4 and gr.anchor.y > pos.y + 0.2:
			gr.climbing = true
	# fell out of the world: put back on the rug
	if pos.y < -5:
		teleport(Vector3(2, 6, 1))
	speed = Vector2(vel.x, vel.z).length()
	# ground material probe (for footsteps)
	_ground_probe_t -= dt
	if grounded and _ground_probe_t <= 0:
		_ground_probe_t = 0.15
		var hit := phys.raycast(Vector3(pos.x, pos.y + 0.3, pos.z), Vector3.DOWN, 0.8)
		if not hit.is_empty():
			ground_mat = hit.mat
	# footsteps by distance travelled
	if grounded and not sliding and speed > 1:
		_step_acc += speed * dt
		var stride := 2.3 if speed > 7 else (1.4 if crouching else 1.9)
		if _step_acc > stride:
			_step_acc = 0
			last_footstep_side ^= 1
			_emit(ev, "on_footstep", [self])


## Called every frame for regen, buffs, timers.
func tick(dt: float, now: float) -> void:
	if not alive:
		return
	if now - last_damage_at > Cfg.COMBAT.regenDelay and health < Cfg.COMBAT.maxHealth:
		health = minf(Cfg.COMBAT.maxHealth, health + Cfg.COMBAT.regenRate * dt)
	fire_kick = maxf(0, fire_kick - dt * 6)
	jab_t = maxf(0, jab_t - dt)
	if cloaked and (now - cloak_start >= Cfg.ABILITIES.cloak.maxActive or reveal_at > cloak_start):
		end_cloak(now)
	if recent_damage.size() and now - recent_damage[0][0] > 5:
		recent_damage.pop_front()
	hit_flinch = maxf(0, hit_flinch - dt * 4)
	for w in weapons:
		if w:
			w.update(dt, now)


func dispose() -> void:
	if disposed:
		return
	disposed = true
	body.queue_free()

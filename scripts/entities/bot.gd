class_name Bot
extends RefCounted
## AI toy (port of src/entities/Bot.ts): state machine (patrol, search, engage, retreat, reload, seekPickup,
## objective, revive), A* on the nav graph, line-of-sight perception, hearing, cover, weapon choice by range,
## abilities, jump pads and ziplines, unstuck logic, 3 difficulties.
## world: {nav, phys, combat, audio, fx, actors(), player(), pickups(), spawn_points, zones, difficulty,
##         listener() -> Vector3, objective(a) -> {pos, radius, height} or null, team_mode, mode, traversal() -> Traversal}

const PERSONALITIES := {
	"captainClick": {"aggression": 0.5, "caution": 0.5, "jumpiness": 0.3, "speed": 1.0, "favorite": ["foamFury", "brickbreaker", "popcornPopper"], "dashUse": 0.3, "headshotBias": 0.25},
	"rexRampage": {"aggression": 0.95, "caution": 0.15, "jumpiness": 0.5, "speed": 1.02, "favorite": ["bubbleBlaster", "rapidRascal", "sizzler", "tumbleweed"], "dashUse": 0.7, "headshotBias": 0.1},
	"boltBuddy": {"aggression": 0.6, "caution": 0.4, "jumpiness": 0.6, "speed": 1.1, "favorite": ["starlightZapper", "foamFury"], "dashUse": 0.5, "headshotBias": 0.2},
	"princessPanic": {"aggression": 0.7, "caution": 0.3, "jumpiness": 0.95, "speed": 1.04, "favorite": ["foamFury", "rapidRascal"], "dashUse": 0.5, "headshotBias": 0.15},
	"turboTim": {"aggression": 0.75, "caution": 0.3, "jumpiness": 0.6, "speed": 1.12, "favorite": ["rapidRascal", "bubbleBlaster", "jackBlaster"], "dashUse": 0.9, "headshotBias": 0.15},
	"mechaMax": {"aggression": 0.25, "caution": 0.85, "jumpiness": 0.1, "speed": 0.95, "favorite": ["thunderspring", "brickbreaker", "plungerBow"], "dashUse": 0.2, "headshotBias": 0.45},
	"blockhead": {"aggression": 0.55, "caution": 0.45, "jumpiness": 0.35, "speed": 1.0, "favorite": ["crayonCannon", "brickbreaker"], "dashUse": 0.3, "headshotBias": 0.1},
	"sergeantSnap": {"aggression": 0.45, "caution": 0.6, "jumpiness": 0.25, "speed": 1.0, "favorite": ["popcornPopper", "jackBlaster"], "dashUse": 0.3, "headshotBias": 0.35},
	"dinaMite": {"aggression": 0.9, "caution": 0.2, "jumpiness": 0.55, "speed": 1.04, "favorite": ["crayonCannon", "bubbleBlaster", "sizzler"], "dashUse": 0.7, "headshotBias": 0.1},
	"sparky": {"aggression": 0.6, "caution": 0.35, "jumpiness": 0.7, "speed": 1.1, "favorite": ["starlightZapper", "rapidRascal"], "dashUse": 0.6, "headshotBias": 0.2},
	"duchessDazzle": {"aggression": 0.35, "caution": 0.7, "jumpiness": 0.4, "speed": 1.0, "favorite": ["thunderspring", "plungerBow", "walloper"], "dashUse": 0.3, "headshotBias": 0.5},
	"nitroNina": {"aggression": 0.8, "caution": 0.25, "jumpiness": 0.6, "speed": 1.12, "favorite": ["rapidRascal", "jackBlaster"], "dashUse": 0.9, "headshotBias": 0.15},
	"gearboxGus": {"aggression": 0.3, "caution": 0.8, "jumpiness": 0.1, "speed": 0.95, "favorite": ["brickbreaker", "plungerBow", "walloper"], "dashUse": 0.2, "headshotBias": 0.45},
	"brickette": {"aggression": 0.6, "caution": 0.4, "jumpiness": 0.45, "speed": 1.02, "favorite": ["brickbreaker", "jackBlaster"], "dashUse": 0.4, "headshotBias": 0.2},
}

const DIFFICULTY := {
	"easy": {"reaction": 0.9, "aimError": 9.5, "turn": 170.0, "view": 42.0, "fov": 100.0, "recoilComp": 0.15, "fireAngle": 8.0, "burst": 0.4, "headshot": 0.0, "hearing": 22.0},
	"normal": {"reaction": 0.55, "aimError": 5.4, "turn": 280.0, "view": 62.0, "fov": 115.0, "recoilComp": 0.4, "fireAngle": 6.0, "burst": 0.65, "headshot": 0.04, "hearing": 32.0},
	"hard": {"reaction": 0.34, "aimError": 3.2, "turn": 440.0, "view": 85.0, "fov": 125.0, "recoilComp": 0.65, "fireAngle": 4.5, "burst": 0.9, "headshot": 0.1, "hearing": 42.0},
}


## Each bot brings two of the five abilities, leaning on its personality.
static func pick_bot_abilities(p: Dictionary, cls := "light") -> Array:
	var w := {
		"dash": 0.4 + p.dashUse,
		"grapple": 0.5 + p.jumpiness * 0.5,
		"cloak": 0.3 + p.caution * 0.5 + p.aggression * 0.3,
		"shield": 0.2 + p.caution * 1.0,
	}
	var out := []
	for n in 1:
		var left := (Cfg.CLASSES[cls].abilities as Array).filter(func(id): return not out.has(id))
		var total := 0.0
		for id in left:
			total += w[id]
		var r := randf() * total
		var choice: String = left[left.size() - 1]
		for id in left:
			r -= w[id]
			if r <= 0:
				choice = id
				break
		out.append(choice)
	return out


## Bots bring one of their favorite weapons plus the pistol.
## The bot's blaster: a favourite its class can carry, else any blaster of its class.
static func pick_bot_loadout(p: Dictionary, cls: String) -> String:
	var guns: Array = Cfg.CLASSES[cls].guns
	var fav: Array = p.favorite.filter(func(g): return guns.has(g))
	return U.pick(fav) if fav.size() else U.pick(guns)


var actor: Actor
var personality: Dictionary
## light | medium (game.gd assigns it before the first spawn)
var cls := "light"
var w: Dictionary
var intent := Actor.Intent.new()
var state := "patrol"
var _state_t := 0.0
var target: Actor = null
var _target_visible := false
var _target_seen_at := -99.0
var _last_known := Vector3.ZERO
var _reaction_until := 0.0
var _heard = null
var _path: Array = []
var _path_idx := 0
## the nav revision this bot last planned against (a wall broke since -> plan again)
var _nav_rev := 0
var _goal := Vector3.ZERO
var _has_goal := false
var _think_at := randf() * 0.2
var _progress_at := 0.0
var _progress_pos := Vector3.ZERO
var _stuck_count := 0
var _unstick_until := 0.0
var _unstick_dir := Vector3.ZERO
var _strafe_dir := 1.0
var _strafe_change_at := 0.0
var _jump_at := 0.0
var _aim_noise := Vector2.ZERO
var _aim_noise_target := Vector2.ZERO
var _aim_noise_at := 0.0
var _trigger_held := false
var _burst_until := 0.0
var _pause_until := 0.0
var _next_semi_at := 0.0
var _aim_head := false
## after being hit: aim shakes until then (much longer after a melee hit)
var _shaky_until := 0.0
var _hurt_seen := -99.0
var _cover_until := 0.0
var _pickup_target = null
var _look_around := 0.0
var _weapon_models := {}
var _crouch_until := 0.0
var _want_dash := false
var _no_los_since := 0.0
## objective modes: holders sit in the toy box, hunters roam around it
var role := "holder"
var _hold_at := 0.0
var _riding := false  # on a jump pad / zipline link (don't count as stuck)
var _ride_started := false
var _ride_since := 0.0
var _was_grappling := false
var _ability_check_at := 0.0
var _sneaking := false
var _fleeing := false
var _revive_target: Actor = null
var passive := false  # training dummy: moves like normal but never shoots


func _init(a: Actor, p: Dictionary, world: Dictionary) -> void:
	actor = a
	personality = p
	w = world


## the downed teammate this bot is currently trying to revive
func reviving() -> Actor:
	return _revive_target if state == "revive" else null


func diff() -> Dictionary:
	return DIFFICULTY[w.difficulty]


func _listener() -> Vector3:
	return w.listener.call()


## Closest downed teammate worth running to (nobody else on it, enough time left on their timer).
func _find_downed(now: float, max_d := 26.0) -> Actor:
	var a := actor
	var best: Actor = null
	var best_d := max_d
	for o in w.actors.call():
		if o == a or o.team != a.team or not o.is_downed(now):
			continue
		if o.reviver and o.reviver != a and o.reviver.alive:
			continue
		var d: float = o.pos.distance_to(a.pos)
		# need time to get there (sprinting ~8 m/s) plus the 3 s hold
		if o.respawn_at - now < d / 7 + Cfg.COMBAT.reviveTime + 0.4 - o.revive_t:
			continue
		if d < best_d:
			best_d = d
			best = o
	return best


func set_model_weapon() -> void:
	var ws := actor.weapon()
	if actor.model == null or ws == null:
		return
	if not _weapon_models.has(ws.id):
		var wm := WeaponModel.build(ws.id)
		Merge.flatten_by_material(wm)
		_weapon_models[ws.id] = wm
	var m: WeaponModel = _weapon_models[ws.id]
	if m.get_parent():
		m.get_parent().remove_child(m)
	for c in actor.model.weapon_socket.get_children():
		actor.model.weapon_socket.remove_child(c)
	actor.model.set_weapon(m)
	var audio = w.audio
	var me := actor
	var wid := ws.id
	ws.on_reload_beat = func(part: String) -> void:
		if me.pos.distance_to(_listener()) < 18:
			audio.reload_part(wid, part, false, me.pos + Vector3(0, 1.2, 0))


func muzzle_world() -> Vector3:
	var ws := actor.weapon()
	if ws and _weapon_models.has(ws.id) and actor.model:
		var m: WeaponModel = _weapon_models[ws.id]
		if m.is_inside_tree():
			return m.muzzle.global_position
	return actor.eye_pos()


func _ability_deps() -> Dictionary:
	return {"combat": w.combat, "phys": w.phys, "audio": w.audio}


func on_spawn(now: float) -> void:
	role = "holder" if w.mode == "conquest" or randf() < 0.75 else "hunter"
	_sneaking = false
	_fleeing = false
	_revive_target = null
	_riding = false
	_ride_started = false
	state = "patrol"
	target = null
	_path = []
	_has_goal = false
	_heard = null
	_stuck_count = 0
	_progress_at = now + 1
	_progress_pos = actor.pos
	set_model_weapon()


## Called by the game when this bot takes damage.
func on_damaged(attacker, now: float) -> void:
	if attacker == null or attacker == actor:
		return
	# we know roughly where it came from
	if target == null or not _target_visible:
		_last_known = attacker.pos + Vector3(U.rand(-2, 2), 0, U.rand(-2, 2))
		_target_seen_at = now - 1
		if state == "patrol" or state == "seekPickup":
			_set_state("search", now)
		target = attacker
		_reaction_until = maxf(_reaction_until, now + diff().reaction * 0.6)
	if personality.caution > 0.6 and randf() < 0.4:
		_cover_until = now + U.rand(1, 2)


## Gunshot heard somewhere.
func on_sound(pos: Vector3, shooter: Actor, now: float, loud: float) -> void:
	if shooter == actor:
		return
	if pos.distance_to(actor.pos) > diff().hearing * loud:
		return
	if _target_visible:
		return
	_heard = {"pos": pos, "t": now}


func _set_state(s: String, now: float) -> void:
	if state == s:
		return
	state = s
	_state_t = now
	_path = []
	_has_goal = false


# ------------------------------------------------------------------ perception
func _perceive(now: float) -> void:
	var a := actor
	if a.flashed_until > now:
		# blinded: can't pick anyone out
		_target_visible = false
		return
	var d := diff()
	var eye := a.eye_pos()
	var fwd := Vector3(-sin(a.yaw), 0, -cos(a.yaw))
	var best: Actor = null
	var best_score := INF
	var phys: Phys = w.phys
	for o in w.actors.call():
		if o == a or not o.alive or not a.is_enemy(o):
			continue
		var to: Vector3 = o.pos - a.pos
		var dist := to.length()
		if dist > d.view:
			continue
		if o.cloaked and dist > Cfg.ABILITIES.cloak.revealDistance:
			continue
		var recently_hurt_me: bool = a.last_attacker == o and now - a.last_attacker_at < 2.5
		var flat := Vector3(to.x, 0, to.z).normalized()
		var ang := rad_to_deg(acos(clampf(flat.dot(fwd), -1, 1)))
		if ang > d.fov / 2 and dist > 5 and not recently_hurt_me and o != target:
			continue
		# line of sight to head or chest
		if not (phys.los(eye, o.head_pos()) or phys.los(eye, o.chest_pos())):
			continue
		var score := dist
		if recently_hurt_me:
			score -= 12
		if o == target:
			score -= 8
		if o.health + o.shield < 50:
			score -= 4
		if o.is_player:
			score -= 2
		if o.is_protected(now):
			score += 30
		if score < best_score:
			best_score = score
			best = o
	if best:
		if best != target:
			_reaction_until = now + d.reaction * U.rand(0.8, 1.3)
			_aim_head = randf() < d.headshot + personality.headshotBias * 0.3 and not best.melee_held
		target = best
		_target_visible = true
		_target_seen_at = now
		_last_known = best.pos
		_no_los_since = now
	else:
		_target_visible = false
		# Lights hunt: a hurt target is chased much longer before it's forgotten
		var keep_s := 12.0 if cls == "light" and target and target.health < target.max_health * 0.5 else 5.0
		if target and (not target.alive or now - _target_seen_at > keep_s):
			target = null


func _pickup_still(max_age: float, now: float) -> bool:
	if _pickup_target == null or now - _state_t > max_age:
		return false
	for x in w.pickups.call():
		if x.available and (x.pos as Vector3).distance_squared_to(_pickup_target) < 0.5:
			return true
	return false


# ------------------------------------------------------------------ decisions
func _think(now: float) -> void:
	var a := actor
	var p := personality
	_perceive(now)
	# getting hit rattles a toy: slower to answer, shaky aim, body shots; a melee hit is scary
	if a.last_damage_at > _hurt_seen:
		_hurt_seen = a.last_damage_at
		var melee_hit := Cfg.MELEE.has(a.last_damage_weapon)
		_reaction_until = maxf(_reaction_until, now + (U.rand(0.7, 1.1) if melee_hit else U.rand(0.25, 0.5)))
		_shaky_until = now + (2.2 if melee_hit else 1.0)
		_aim_head = false
		if melee_hit and state != "retreat" and randf() < 0.55 + p.caution * 0.35:
			_start_retreat(now)
			return
	# a toy charging in with a sword or spear makes careful toys back off
	if target and _target_visible and target.melee_held and state != "retreat" and target.pos.distance_to(a.pos) < 5.5 and randf() < 0.08 + p.caution * 0.15:
		_start_retreat(now)
		return
	var ws := a.weapon()
	var hp_frac := (a.health + a.shield) / a.max_health
	# wary: run once health starts dropping (earlier for careful toys), or after a sudden burst of damage
	var retreat_at: float = 0.35 + p.caution * 0.3
	var burst := a.damage_in_last(3, now)
	var scared := hp_frac < retreat_at or (burst > 35 and a.health < a.max_health * 0.75)
	# Mediums play it safe: back to cover below 40% health
	if cls == "medium" and a.health < a.max_health * 0.4:
		scared = true
	# weapon choice by distance
	if target and _target_visible:
		_choose_weapon(target.pos.distance_to(a.pos), now)
	if ws and ws.mag <= 0 and not ws.is_energy():
		var other = a.weapons[1 if a.slot == 0 else 0]
		if _target_visible and other and other.mag > 0 and p.aggression > 0.4:
			_switch_slot(1 if a.slot == 0 else 0, now)
		elif ws.reserve > 0 and not ws.reloading:
			ws.start_reload()
	ws = a.weapon()
	if ws and not _target_visible and not ws.reloading and not ws.is_energy() and ws.mag < ws.cfg.magSize * 0.4 and ws.reserve > 0:
		ws.start_reload()
	if scared and (_target_visible or burst > 0) and state != "retreat" and not (state == "seekPickup" and _fleeing) and now - _state_t > 0.8:
		_start_retreat(now)
		return
	if state == "retreat":
		if (hp_frac > 0.8 or now - _state_t > 9) and now - a.last_damage_at > 2.5:
			_set_state("search" if target else "patrol", now)
		return
	if state == "seekPickup" and _fleeing:
		# keep running for the battery; fall back to plain retreat if it's gone
		if not _pickup_still(10, now):
			_fleeing = false
			_set_state("patrol" if hp_frac > 0.8 else "retreat", now)
		return
	_fleeing = false
	if ws and ws.reloading and _target_visible and p.caution > 0.4:
		_set_state("reload", now)
		return
	var obj = w.objective.call(a)
	var in_obj: bool = _in_zone(obj) if obj != null else false
	if target and _target_visible:
		var far := target.pos.distance_to(a.pos) > 20
		# holders don't get dragged into long-range fights away from the toy box (they still shoot while moving)
		if obj != null and role == "holder" and not in_obj and far:
			_set_state("objective", now)
			return
		_set_state("engage", now)
		return
	# nobody shooting at us right now: pick up a downed teammate
	if w.team_mode:
		var keep: Actor = _revive_target if state == "revive" and _revive_target and _revive_target.is_downed(now) else null
		var d: Actor = keep
		if d == null and hp_frac > 0.4 and now - a.last_damage_at > 1.5:
			d = _find_downed(now, 11.0 if obj != null and role == "holder" else 26.0)
		if d:
			if _revive_target != d or state != "revive":
				_revive_target = d
				d.reviver = a
				_set_state("revive", now)
			return
		_revive_target = null
		if state == "revive":
			_set_state("patrol", now)
	if obj != null and role == "holder" and hp_frac > 0.35:
		_set_state("objective", now)
		return
	if state == "engage" and target and now - _target_seen_at < 3.5:
		# lost sight: push to last known position
		_set_state("search", now)
		return
	if _heard != null and now - _heard.t < 6 and state != "seekPickup":
		_last_known = _heard.pos
		_heard = null
		_set_state("search", now)
		return
	if state == "search" and now - _state_t > 9:
		_set_state("patrol", now)
	if state == "reload" and not (ws and ws.reloading):
		_set_state("patrol", now)
	# pickups: health when hurt, otherwise occasionally power-ups
	# objective holders only detour for pickups when they are actually hurt
	var stay_on_obj: bool = obj != null and role == "holder" and hp_frac >= 0.6 and ws != null and (ws.is_energy() or ws.reserve > 0)
	if not stay_on_obj and (state == "patrol" or (state == "search" and hp_frac < 0.5)):
		var pk = _pick_pickup(hp_frac)
		if pk != null:
			_pickup_target = pk
			_set_state("seekPickup", now)
	if state == "seekPickup":
		if not _pickup_still(14, now):
			_set_state("patrol", now)


## Get out of the fight: grab a nearby health battery if it isn't toward the enemy, else run for cover.
func _start_retreat(now: float) -> void:
	var a := actor
	var p := personality
	var from = target.pos if target else (a.last_attacker.pos if a.last_attacker else null)
	var best = null
	var best_d := 28.0
	for pk in w.pickups.call():
		if not pk.available or pk.kind != "health":
			continue
		var d: float = (pk.pos as Vector3).distance_to(a.pos)
		if d > best_d:
			continue
		if from != null:
			var to_pk := Vector3(pk.pos.x - a.pos.x, 0, pk.pos.z - a.pos.z).normalized()
			var to_enemy := Vector3(from.x - a.pos.x, 0, from.z - a.pos.z).normalized()
			if to_pk.dot(to_enemy) > 0.5 and (from as Vector3).distance_to(pk.pos) < d:
				continue
		best = pk.pos
		best_d = d
	if best != null:
		_pickup_target = best
		_set_state("seekPickup", now)
		_fleeing = true
	else:
		_set_state("retreat", now)
	_want_dash = randf() < p.dashUse + 0.2
	# escape tools
	var deps := _ability_deps()
	if a.has("cloak") and now >= a.cloak_ready_at and not a.cloaked and randf() < 0.45 + p.caution * 0.4:
		if Abilities.try_cloak(a, now, deps):
			_sneaking = true
	elif a.has("shield") and target and _target_visible and now >= a.shield_ready_at and randf() < 0.6:
		var t := target.pos
		Abilities.try_shield(a, now, deps, atan2(-(t.x - a.pos.x), -(t.z - a.pos.z)))
	if from != null and a.has("grapple") and now >= a.grapple_ready_at and randf() < 0.35:
		_grapple_away(from, now)


## Spring Hook to a higher spot pointing away from the threat.
func _grapple_away(from: Vector3, now: float) -> bool:
	var a := actor
	var nav: NavGraph = w.nav
	var eye := a.eye_pos()
	for i in 6:
		var id := nav.random(func(n):
			var d: float = (n.pos as Vector3).distance_to(a.pos)
			return d > 10 and d < Cfg.ABILITIES.grapple.range - 4 and n.pos.y > a.pos.y + 2.5 and (n.pos as Vector3).distance_to(from) > a.pos.distance_to(from) + 4)
		if id < 0 or id >= nav.nodes.size():
			continue
		var np: Vector3 = nav.nodes[id].pos
		if np.y <= a.pos.y + 2.5:
			continue
		var tgt := np + Vector3(0, 0.3, 0)
		if not w.phys.los(eye, tgt, true):
			continue
		var dir := (tgt - eye).normalized()
		var pt = Abilities.grapple_point(a, dir, w.phys)
		if pt == null or (pt as Vector3).distance_to(np) > 3:
			continue
		a.yaw = atan2(-dir.x, -dir.z)
		var r = Abilities.try_grapple(a, dir, now, _ability_deps())
		if not (r is bool and r == false):
			return true
	return false


## Spring Hook straight toward a point (used to climb toward a goal or a target that's high above).
func _grapple_toward(p: Vector3, now: float) -> bool:
	var a := actor
	var eye := a.eye_pos()
	var tgt := p + Vector3(0, 0.3, 0)
	if eye.distance_to(tgt) > Cfg.ABILITIES.grapple.range - 2 or not w.phys.los(eye, tgt, true):
		return false
	var dir := (tgt - eye).normalized()
	var pt = Abilities.grapple_point(a, dir, w.phys)
	if pt == null or (pt as Vector3).distance_to(p) > 3.5:
		return false
	var r = Abilities.try_grapple(a, dir, now, _ability_deps())
	return not (r is bool and r == false)


## Abilities that depend on the fight: punch up close, shield when pinned, hook up to high targets/goals.
func _use_abilities(now: float) -> void:
	var a := actor
	var p := personality
	var t := target
	var deps := _ability_deps()
	var ws := a.weapon()
	if t and _target_visible and t.alive:
		var dist := t.pos.distance_to(a.pos)
		var to := Vector3(t.pos.x - a.pos.x, 0, t.pos.z - a.pos.z).normalized()
		var facing := to.dot(Vector3(-sin(a.yaw), 0, -cos(a.yaw)))
		# gadgets: grenades at a target in throwing range, mines when holding ground or backing off
		if a.gadget != "" and now >= a.gadget_ready_at and now >= _reaction_until and randf() < 0.04:
			var gc: Dictionary = Cfg.GADGETS[a.gadget]
			if gc.has("mine"):
				if state == "retreat" or role == "holder" or dist < 9:
					Abilities.try_gadget(a, now, deps)
			elif gc.has("heal"):
				if a.health < a.max_health * 0.6:
					Abilities.try_gadget(a, now, deps)
			elif gc.get("deploy", "") == "turret":
				if dist > 8 and dist < 26:
					Abilities.try_gadget(a, now, deps)
			elif gc.has("deploy"):
				pass  # stairs: bots don't plan climbs
			elif dist > 7 and dist < 24 and facing > 0.9:
				Abilities.try_gadget(a, now, deps)
		if now >= _ability_check_at:
			_ability_check_at = now + 0.5
			var pinned := a.damage_in_last(2, now) > 22 or (ws != null and ws.reloading)
			if pinned and a.has("shield") and dist > 6 and now >= a.shield_ready_at and randf() < 0.35 + p.caution * 0.4:
				Abilities.try_shield(a, now, deps, atan2(-(t.pos.x - a.pos.x), -(t.pos.z - a.pos.z)))
			# they're up on a ledge / shelf: hook up after them
			if a.has("grapple") and t.pos.y - a.pos.y > 4 and dist < 34 and now >= a.grapple_ready_at and randf() < 0.25 + p.aggression * 0.3:
				_grapple_toward(t.pos, now)
			# sneak in invisible to get close (aggressive toys)
			if a.has("cloak") and not a.cloaked and now >= a.cloak_ready_at and dist > 14 and dist < 30 and randf() < p.aggression * 0.08:
				if Abilities.try_cloak(a, now, deps):
					_sneaking = true
		return
	if now < _ability_check_at:
		return
	_ability_check_at = now + 0.6
	# long climb ahead (shelves, desk, bed): hook to the goal when it's in sight
	if a.has("grapple") and _has_goal and _goal.y - a.pos.y > 5 and now >= a.grapple_ready_at and randf() < 0.3:
		if _grapple_toward(_goal, now):
			return
		# or to a node on the way up
		if _path.size():
			var i := _path.size() - 1
			while i > _path_idx:
				var np: Vector3 = w.nav.nodes[_path[i]].pos
				if np.y - a.pos.y > 4 and _grapple_toward(np, now):
					return
				i -= 2
	# conquest: sometimes slip into a contested sector unseen
	var obj = w.objective.call(a)
	if obj != null and a.has("cloak") and not a.cloaked and now >= a.cloak_ready_at and state == "objective":
		var d := a.pos.distance_to(obj.pos)
		if d > 12 and d < 30 and randf() < 0.12:
			if Abilities.try_cloak(a, now, deps):
				_sneaking = true


func _pick_pickup(hp_frac: float):
	var a := actor
	var best = null
	var best_d := INF
	for pk in w.pickups.call():
		if not pk.available:
			continue
		var d: float = (pk.pos as Vector3).distance_to(a.pos)
		var want := 0.0
		if pk.kind == "health" and hp_frac < 0.8:
			want = 1
		elif pk.kind == "shield" and a.shield < 25:
			want = 0.35
		elif pk.kind in ["power", "turbo", "infinite"]:
			want = 0.25
		if want <= 0 or d > 34:
			continue
		if randf() > want:
			continue
		if d < best_d:
			best_d = d
			best = pk.pos
	return best


func _choose_weapon(dist: float, now: float) -> void:
	var a := actor
	var cur := a.weapon()
	if cur == null or (cur.reloading and cur.reload_progress() > 0.5):
		return
	var other = a.weapons[1 if a.slot == 0 else 0]
	if other == null or (other.mag <= 0 and other.reserve <= 0 and not other.is_energy()):
		return
	var fit := func(id: String) -> float:
		var br: Array = Cfg.WEAPONS[id].botRange
		return br[0] - dist if dist < br[0] else (dist - br[1] if dist > br[1] else 0.0)
	if fit.call(other.id) + 4 < fit.call(cur.id) and now - cur.last_shot > 0.4:
		_switch_slot(1 if a.slot == 0 else 0, now)


func _switch_slot(s: int, now: float) -> void:
	var a := actor
	if a.weapons[s] == null or s == a.slot:
		return
	if a.weapon():
		a.weapon().cancel_reload()
	a.slot = s
	a.weapon().equip(now, 0.4)
	set_model_weapon()


## Take a class: Lights get bolder, Mediums more careful (on a copy of this bot's personality).
func set_class(c: String) -> void:
	cls = c if Cfg.CLASSES.has(c) else "light"
	var p := personality.duplicate()
	if cls == "light":
		p.aggression = clampf(p.aggression + 0.25, 0, 1)
		p.caution = clampf(p.caution - 0.25, 0, 1)
	else:
		p.caution = clampf(p.caution + 0.25, 0, 1)
		p.aggression = clampf(p.aggression - 0.2, 0, 1)
	personality = p


# ------------------------------------------------------------------ navigation
## A wall just broke somewhere: plan the current route again (it may now go through the hole).
func repath_soon() -> void:
	if _has_goal:
		_path = []
		_set_goal(_goal)


func _set_goal(p: Vector3) -> void:
	if _has_goal and _goal.distance_squared_to(p) < 4 and _path.size():
		return
	_goal = p
	_has_goal = true
	var nav: NavGraph = w.nav
	var s := nav.nearest(actor.pos, true, 6)
	var g := nav.nearest(p, false, 6)
	_path = nav.path(s, g)
	_path_idx = 0
	if _path.is_empty():
		_has_goal = false


func _in_zone(o: Dictionary) -> bool:
	var a := actor
	var dx: float = a.pos.x - o.pos.x
	var dz: float = a.pos.z - o.pos.z
	return dx * dx + dz * dz < pow(o.radius - 0.4, 2) and a.pos.y > o.pos.y - 1.2 and a.pos.y < o.pos.y + o.height


## A walkable spot inside the capture zone.
func _zone_spot(o: Dictionary) -> Vector3:
	var nav: NavGraph = w.nav
	var ids := nav.near(o.pos, o.radius - 0.6).filter(func(id):
		var y: float = nav.nodes[id].pos.y
		return y > o.pos.y - 1 and y < o.pos.y + o.height)
	return nav.nodes[U.pick(ids)].pos if ids.size() else o.pos


func _random_patrol_goal() -> Vector3:
	var nav: NavGraph = w.nav
	var spawns: Array = w.spawn_points
	var a := actor
	# objective modes: hunters prowl the approaches to the toy box
	var obj = w.objective.call(a)
	if obj != null and role == "hunter":
		var id := nav.random(func(n):
			var d: float = (n.pos as Vector3).distance_to(obj.pos)
			return d > obj.radius + 2 and d < 16)
		if id >= 0 and id < nav.nodes.size():
			return nav.nodes[id].pos
	# team modes: sometimes regroup with a teammate
	if w.team_mode and randf() < 0.4:
		var mates: Array = w.actors.call().filter(func(o): return o != a and o.alive and o.team == a.team)
		if mates.size():
			var m: Actor = U.pick(mates)
			var id := nav.random(func(n): return (n.pos as Vector3).distance_to(m.pos) < 7 and (n.pos as Vector3).distance_to(a.pos) > 4)
			if id >= 0 and (nav.nodes[id].pos as Vector3).distance_to(m.pos) < 7:
				return nav.nodes[id].pos
	# pick a zone first so toys spread around the whole room instead of clumping in the middle
	var zones: Array = w.zones.filter(func(z): return z.name != "Play Rug")
	var z = U.pick(zones) if randf() < 0.8 else null
	var id := nav.random(func(n):
		if n.open < 4:
			return false
		var np: Vector3 = n.pos
		for s in spawns:
			if (s as Vector3).distance_squared_to(np) < 30:
				return false
		if np.distance_to(a.pos) <= 10:
			return false
		return z == null or (np.x >= z.min[0] and np.x <= z.max[0] and np.z >= z.min[1] and np.z <= z.max[1]))
	if id >= 0 and id < nav.nodes.size():
		return nav.nodes[id].pos
	return a.pos


func _find_cover(from: Vector3):
	var nav: NavGraph = w.nav
	var a := actor
	var ids := nav.near(a.pos, 14)
	ids.shuffle()
	var best = null
	var best_score := INF
	var eye := from + Vector3(0, 1.5, 0)
	var checks := 0
	for id in ids:
		var np: Vector3 = nav.nodes[id].pos
		if absf(np.y - a.pos.y) > 3:
			continue
		checks += 1
		if checks > 24:
			break
		if w.phys.los(eye, np + Vector3(0, 1.1, 0)):
			continue
		var score := np.distance_to(a.pos) - np.distance_to(from) * 0.5
		if score < best_score:
			best_score = score
			best = np
	return best


## Steering toward the current path node. Returns [moving, world wish direction (unnormalized)].
func _follow_path() -> Array:
	var a := actor
	var nav: NavGraph = w.nav
	if _path.is_empty() or _path_idx >= _path.size():
		if _has_goal:
			var out := Vector3(_goal.x - a.pos.x, 0, _goal.z - a.pos.z)
			if out.length() < 0.8:
				_has_goal = false
				return [false, Vector3.ZERO]
			return [true, out]
		return [false, Vector3.ZERO]
	# jump pads and ziplines
	if _path_idx > 0:
		var l = nav.link_between(_path[_path_idx - 1], _path[_path_idx])
		if l != null and (l.pad >= 0 or l.zip >= 0):
			return _ride_link(l, nav.nodes[_path[_path_idx - 1]].pos, nav.nodes[_path[_path_idx]].pos)
	_riding = false
	_ride_started = false
	var node: Vector3 = nav.nodes[_path[_path_idx]].pos
	var dx := node.x - a.pos.x
	var dz := node.z - a.pos.z
	if dx * dx + dz * dz < 0.9 and absf(node.y - a.pos.y) < 1.4:
		_path_idx += 1
		if _path_idx >= _path.size():
			var out := Vector3(_goal.x - a.pos.x, 0, _goal.z - a.pos.z)
			return [out.length_squared() > 0.6, out]
		node = nav.nodes[_path[_path_idx]].pos
	# look one node ahead to smooth corners
	if _path_idx + 1 < _path.size():
		var nxt: Vector3 = nav.nodes[_path[_path_idx + 1]].pos
		if absf(nxt.y - a.pos.y) < 0.4 and absf(node.y - a.pos.y) < 0.4 and a.pos.distance_to(node) < 2.2:
			if w.phys.los(Vector3(a.pos.x, a.pos.y + 0.6, a.pos.z), Vector3(nxt.x, nxt.y + 0.6, nxt.z), true):
				node = nxt
	var out := Vector3(node.x - a.pos.x, 0, node.z - a.pos.z)
	# ledges that need a hop
	if _path_idx > 0:
		var l = nav.link_between(_path[_path_idx - 1], _path[_path_idx])
		if l != null and l.jump and a.grounded and out.length() < 1.7 and node.y > a.pos.y + 0.4:
			intent.jump = true
	return [true, out]


## Take a jump pad (walk onto it, fly) or a zipline (walk under the end, grab, ride) to the next node.
func _ride_link(l: Dictionary, from: Vector3, to: Vector3) -> Array:
	var a := actor
	var tv: Traversal = w.traversal.call()
	var now: float = w.combat.now
	if not _riding:
		_riding = true
		_ride_started = false
		_ride_since = now
	var busy: bool = a.zip != null or a.launched
	if busy:
		_ride_started = true
		return [false, Vector3.ZERO]
	if _ride_started:
		# landed / got off: carry on if we're where the link leads, otherwise plan again
		_riding = false
		_ride_started = false
		if Vector2(a.pos.x - to.x, a.pos.z - to.z).length() < 4.5 and absf(a.pos.y - to.y) < 2:
			_path_idx += 1
		else:
			_path = []
			_has_goal = false
		return [true, Vector3.ZERO]
	if now - _ride_since > 8:
		# couldn't get on: give up on this route
		_riding = false
		_path = []
		_has_goal = false
		return [false, Vector3.ZERO]
	if l.pad >= 0:
		# walk onto the middle of the pad; it launches us by itself
		var c: Vector3 = tv.pads[l.pad].pos
		return [true, Vector3(c.x - a.pos.x, 0, c.z - a.pos.z)]
	# zipline: get under the near end, then grab
	var z: Dictionary = tv.zips[l.zip]
	var end: Vector3 = z.a if from.distance_to(z.a) <= from.distance_to(z.b) else z.b
	var out := Vector3(end.x - a.pos.x, 0, end.z - a.pos.z)
	if out.length() < 1.6 and absf(a.pos.y - end.y) < 2.0:
		tv.attach_from(a, l.zip, end, now)
		_ride_started = true
		return [false, Vector3.ZERO]
	return [true, out]


# ------------------------------------------------------------------ main update
func update(dt: float, now: float) -> void:
	var a := actor
	var it := intent
	it.jump = false
	it.dash = false
	it.crouch_pressed = false
	it.sprint = false
	it.crouch = false
	it.wish = Vector3.ZERO
	if not a.alive:
		return
	_think_at -= dt
	if _think_at <= 0:
		_think_at = U.rand(0.12, 0.2)
		var nr: int = w.nav.revision
		if nr != _nav_rev:
			_nav_rev = nr
			repath_soon()
		_think(now)
	# after a Spring Hook the old path is useless
	if _was_grappling and a.grapple == null:
		_path = []
		_has_goal = false
		_progress_at = now + 1
		_progress_pos = a.pos
	_was_grappling = a.grapple != null
	if not a.cloaked:
		_sneaking = false
	if a.grapple == null:
		_use_abilities(now)
	var p := personality
	var tgt := target
	var dir := Vector3.ZERO
	var moving := false
	match state:
		"patrol":
			if not _has_goal:
				_set_goal(_random_patrol_goal())
			var r := _follow_path()
			moving = r[0]
			dir = r[1]
			if not moving:
				_has_goal = false
			it.sprint = (not it.sprint) if randf() < 0.02 else p.aggression > 0.6
		"search":
			if not _has_goal:
				_set_goal(_last_known)
			var r := _follow_path()
			moving = r[0]
			dir = r[1]
			it.sprint = p.aggression > 0.5
			if not moving:
				_look_around += dt
				a.yaw += dt * 1.6
				if _look_around > 2.2:
					_look_around = 0
					_set_state("patrol", now)
		"objective":
			var obj = w.objective.call(a)
			if obj == null:
				_set_state("patrol", now)
			elif not _in_zone(obj):
				if not _has_goal or _goal.distance_to(obj.pos) > obj.radius + 0.5:
					_set_goal(_zone_spot(obj))
				var r := _follow_path()
				moving = r[0]
				dir = r[1]
				it.sprint = true
				if not moving:
					_has_goal = false
				if a.pos.distance_to(obj.pos) > 25 and randf() < p.dashUse * 0.01:
					it.dash = true
			else:
				# hold the box: shuffle around inside it and watch the approaches
				if now > _hold_at or not _has_goal:
					_hold_at = now + U.rand(1.5, 3.5)
					_set_goal(_zone_spot(obj))
				var r := _follow_path()
				moving = r[0]
				dir = r[1]
				if not moving:
					a.yaw += dt * 0.9 * (1.0 if sin(now * 0.7 + a.id) > 0 else -1.0)
					a.pitch *= 1 - minf(1, dt * 3)
				it.crouch = p.caution > 0.6 and sin(now * 0.9 + a.id) > 0.3
		"revive":
			var t := _revive_target
			if t:
				var d := Vector2(t.pos.x - a.pos.x, t.pos.z - a.pos.z).length()
				if d < 1.5 and absf(t.pos.y - a.pos.y) < 2:
					# kneel next to them and hold on
					it.crouch = true
					moving = false
				else:
					if not _has_goal:
						_set_goal(t.pos)
					var r := _follow_path()
					moving = r[0]
					dir = r[1]
					it.sprint = true
					if not moving and d >= 2.3:
						_has_goal = false
		"seekPickup":
			if _pickup_target != null and not _has_goal:
				_set_goal(_pickup_target)
			var r := _follow_path()
			moving = r[0]
			dir = r[1]
			it.sprint = true
			if not moving:
				_set_state("patrol", now)
		"retreat", "reload":
			if not _has_goal and tgt:
				var c = _find_cover(tgt.pos)
				if c != null:
					_set_goal(c)
				else:
					# run directly away
					_set_goal(Vector3(a.pos.x - tgt.pos.x, 0, a.pos.z - tgt.pos.z).normalized() * 8 + a.pos)
			var r := _follow_path()
			moving = r[0]
			dir = r[1]
			it.sprint = not _target_visible or state == "retreat"
			if _want_dash and moving:
				it.dash = true
				_want_dash = false
		"engage":
			if tgt:
				var dist := tgt.pos.distance_to(a.pos)
				var ws := a.weapon()
				var br: Array = ws.cfg.botRange if ws else [5, 30]
				var lo: float = br[0]
				var hi: float = br[1]
				var ideal: float = lo + (hi - lo) * (0.55 - p.aggression * 0.4)
				if cls == "medium":
					ideal = clampf(ideal, minf(10.0, hi), 22.0)  # fight from mid range
				else:
					ideal *= 0.8  # Lights crowd their target
				var to_t := Vector3(tgt.pos.x - a.pos.x, 0, tgt.pos.z - a.pos.z).normalized()
				var side := Vector3(-to_t.z, 0, to_t.x) * _strafe_dir
				if now > _strafe_change_at:
					_strafe_dir = -1.0 if randf() < 0.5 else 1.0
					_strafe_change_at = now + U.rand(0.5, 1.8) * (1.3 - p.jumpiness * 0.6)
				if now < _cover_until:
					if not _has_goal:
						var c = _find_cover(tgt.pos)
						if c != null:
							_set_goal(c)
					var r := _follow_path()
					moving = r[0]
					dir = r[1]
				elif dist > hi * 1.05 or (not _target_visible and now - _no_los_since > 0.6):
					if not _has_goal or _goal.distance_squared_to(tgt.pos) > 16:
						_set_goal(tgt.pos)
					var r := _follow_path()
					moving = r[0]
					dir = r[1]
					it.sprint = dist > 14
					if dist > 22 and randf() < p.dashUse * 0.01:
						it.dash = true
				else:
					_has_goal = false
					dir = side
					if dist > ideal + 3:
						dir += to_t * 0.8
					elif dist < ideal - 3:
						dir += to_t * -0.8
					moving = true
					# don't walk off high ledges while strafing
					var probe := a.pos + dir.normalized() * 1.2
					probe.y = a.pos.y + 0.5
					var drop: float = w.phys.ray_dist(probe, Vector3.DOWN, 3, true)
					if drop > 1.6:
						_strafe_dir *= -1
						dir = -side
					if now > _jump_at:
						_jump_at = now + U.rand(1.2, 4) / (0.3 + p.jumpiness)
						if randf() < p.jumpiness * 0.6:
							it.jump = true
						if p.caution > 0.6 and randf() < 0.4:
							_crouch_until = now + U.rand(0.6, 1.5)
					if dist < 8 and p.dashUse > 0.6 and randf() < 0.004:
						it.dash = true
				it.crouch = now < _crouch_until
	if moving and dir.length_squared() > 1e-4:
		it.wish = Vector3(dir.x, 0, dir.z).normalized() * (1.0 if p.speed > 1 else p.speed)
	# ---------------- unstuck
	if now > _progress_at:
		var moved := a.pos.distance_to(_progress_pos)
		if moving and moved < 0.7 and state != "engage" and not _riding and a.grapple == null and a.zip == null and not a.launched:
			_stuck_count += 1
			_unstick_until = now + 0.6
			_unstick_dir = Vector3(U.rand(-1, 1), 0, U.rand(-1, 1)).normalized()
			it.jump = true
			if _stuck_count >= 2:
				_has_goal = false
				_path = []
			if _stuck_count >= 5:
				# last resort: hop to the nearest nav node
				var n: int = w.nav.nearest(a.pos, false, 10)
				if n >= 0:
					a.teleport(w.nav.nodes[n].pos + Vector3(0, 0.05, 0))
				_stuck_count = 0
		elif moved > 1.5:
			_stuck_count = 0
		_progress_at = now + 1
		_progress_pos = a.pos
	if now < _unstick_until:
		it.wish = _unstick_dir
	# on a zipline or flying off a pad: hands off (a stray jump would let go)
	if a.zip != null or a.launched:
		it.jump = false
		it.dash = false
		if a.launched:
			it.wish = Vector3.ZERO
	# ---------------- aim + fire
	_aim(dt, now, moving)
	# face movement when nothing to look at
	if tgt == null or (not _target_visible and state != "search"):
		if it.wish.length_squared() > 0.01:
			var want := atan2(-it.wish.x, -it.wish.z)
			a.yaw += clampf(U.angle_wrap(want - a.yaw), -dt * 5, dt * 5)
			a.pitch *= 1 - minf(1, dt * 4)


func _aim(dt: float, now: float, moving: bool) -> void:
	var a := actor
	var t := target
	var d := diff()
	var ws := a.weapon()
	_trigger_held = false
	if t == null or ws == null:
		return
	# aim point: chest or head, with lead for projectile weapons
	var aim_pt := t.head_pos() if _aim_head else t.chest_pos() - Vector3(0, 0.18, 0)
	if not _target_visible:
		aim_pt = _last_known + Vector3(0, 1.1, 0)
	var eye := a.eye_pos()
	var dist := eye.distance_to(aim_pt)
	var want_charge := clampf(0.5 + dist / 28, 0.6, 1) if ws.cfg.has("charge") else 1.0
	if ws.cfg.projectile.kind == "projectile" and _target_visible:
		var spd: float = ws.cfg.charge.minSpeed + (ws.cfg.charge.maxSpeed - ws.cfg.charge.minSpeed) * want_charge if ws.cfg.has("charge") else ws.cfg.projectile.speed
		var tt := dist / spd
		aim_pt += t.vel * (tt * (0.6 + 0.4 * (1 - d.aimError / 6)))
		if ws.cfg.projectile.gravity > 0:
			aim_pt.y += 0.5 * ws.cfg.projectile.gravity * tt * tt
	# smoothly wandering aim error, worse when moving or the target is moving fast
	if now > _aim_noise_at:
		_aim_noise_at = now + U.rand(0.18, 0.4)
		var err: float = d.aimError * (1 + (0.5 if moving else 0.0) + clampf(t.speed / 8, 0, 1) * 0.6) * (1.6 if now < _reaction_until + 0.4 else 1.0)
		err *= (2.4 if now < _shaky_until else 1.0) * (1.7 if t.melee_held else 1.0) * (4.0 if actor.flashed_until > now else 1.0)
		_aim_noise_target = Vector2(U.rand(-err, err), U.rand(-err, err * 0.35))
	_aim_noise = _aim_noise.lerp(_aim_noise_target, 1 - exp(-6 * dt))
	var to := aim_pt - eye
	var want_yaw := atan2(-to.x, -to.z) + deg_to_rad(_aim_noise.x)
	var want_pitch: float = atan2(to.y, Vector2(to.x, to.z).length()) + deg_to_rad(_aim_noise.y) + deg_to_rad(ws.recoil_pitch) * (1 - d.recoilComp)
	var max_turn := deg_to_rad(d.turn) * dt
	a.yaw += clampf(U.angle_wrap(want_yaw - a.yaw), -max_turn, max_turn)
	a.pitch += clampf(want_pitch - a.pitch, -max_turn, max_turn)
	a.pitch = clampf(a.pitch, -1.4, 1.4)
	# bow: keep the string drawn while we have a target, loose it once it's drawn far enough and on target
	if ws.cfg.has("charge"):
		var seen := _target_visible or now - _target_seen_at < 1.2
		if not seen or not t.alive or t.is_protected(now) or (a.cloaked and _sneaking and dist > 8):
			ws.cancel_draw()
			return
		if now < _reaction_until:
			_trigger_held = ws.drawing()
			return
		var off := rad_to_deg(absf(U.angle_wrap(want_yaw - a.yaw))) + rad_to_deg(absf(want_pitch - a.pitch))
		if not ws.drawing():
			_trigger_held = off < 25 and dist < ws.cfg.botRange[1] * 1.6
			return
		var ready := ws.charge_at(now) >= want_charge - 0.02
		_trigger_held = not (ready and _target_visible and off < d.fireAngle + 0.6)
		return
	if not _target_visible or now < _reaction_until or t.is_protected(now) or not t.alive:
		return
	# sneaking under cloak: don't give ourselves away until it's worth it
	if a.cloaked and _sneaking and dist > 9 and state != "engage":
		return
	if a.cloaked and _sneaking and dist > 6 and state == "retreat":
		return
	var off := rad_to_deg(absf(U.angle_wrap(want_yaw - a.yaw))) + rad_to_deg(absf(want_pitch - a.pitch))
	var rng: float = ws.cfg.botRange[1] * 1.6
	if off > d.fireAngle + ws.cfg.spread.hip * 0.5 or dist > rng:
		return
	# trigger discipline: bursts for automatics, human cadence for semi-autos
	if ws.cfg.auto:
		if now > _burst_until and now > _pause_until:
			_burst_until = now + U.rand(0.25, 0.8) * (0.5 + d.burst) * (1.6 if dist < 12 else 1.0)
			_pause_until = _burst_until + U.rand(0.15, 0.45) * (1.4 - d.burst)
		_trigger_held = now < _burst_until
	else:
		_trigger_held = now >= _next_semi_at


## Fire step (after aim) – returns shots fired this frame.
func fire(now: float) -> int:
	var a := actor
	var ws := a.weapon()
	if ws == null or not a.alive or passive:
		return 0
	var infinite := a.has_buff("infinite", now)
	var was_drawing := ws.drawing()
	var res := ws.pull_trigger(now, _trigger_held, _trigger_held, infinite)
	if ws.drawing() and not was_drawing and a.pos.distance_to(_listener()) < 18:
		w.audio.bow_draw(false, a.chest_pos())
	if res <= 0:
		return 0
	if not ws.cfg.auto:
		_next_semi_at = now + ws.interval() + U.rand(0.05, 0.3) * (2.0 if ws.cfg.id == "thunderspring" else 1.0)
	a.spawn_protect_until = minf(a.spawn_protect_until, now)
	var eye := a.eye_pos()
	var muzzle := muzzle_world()
	for i in res:
		var dir := a.forward()
		var spread := ws.spread(0.85 if ws.overlay() else 0.3, clampf(a.speed / 5.5, 0, 1.3), not a.grounded) * 1.4 + 0.6
		w.combat.fire(a, ws, eye, dir, muzzle, spread)
		ws.kick(false)
		a.fire_kick = 1
		w.fx.muzzle(muzzle, dir, ws.cfg.colors.glow, 1.4 if ws.cfg.pellets > 1 or ws.id == "crayonCannon" else 0.8)
		if ws.id == "starlightZapper":
			w.fx.flash_light(muzzle, ws.cfg.colors.glow, 6, 0.05, 6)
		if muzzle.distance_to(_listener()) < 80:
			w.audio.gunshot(ws.id, muzzle, false)
	return res


func anim_state(now: float) -> Dictionary:
	var a := actor
	var ws := a.weapon()
	return {
		"speed": a.speed, "grounded": a.grounded, "vy": a.vel.y, "crouch": a.crouch_t, "aimPitch": a.pitch,
		"reload": maxf(0.01, ws.reload_progress()) if ws and ws.reloading else 0.0,
		"fireKick": a.fire_kick, "hit": a.hit_flinch, "dashing": a.dashing, "sliding": a.sliding,
		"protectedShimmer": a.is_protected(now),
	}


func dispose() -> void:
	for m in _weapon_models.values():
		if is_instance_valid(m):
			(m as Node).queue_free()
	_weapon_models.clear()

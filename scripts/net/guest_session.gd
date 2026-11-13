class_name GuestSession
extends RefCounted
## A guest's side of an online match (port of src/net/GuestSession.ts). Your own toy moves and shoots
## here, instantly; everything else (other players, the host's bots, health, scores, pick-ups, falling
## blocks) comes from the host and is drawn a little in the past so it moves smoothly.

var g  # Game
var net  # the Net autoload
var lobby := {}
var local_seat := -1
## spawn counter, echoed in every state so the host can ignore stale ones
var life := 0
var buffer := Snapshot.Buffer.new()
## how far in the past other toys are drawn (ms)
var interp_delay := 100.0
## counters (dev test / debugging)
var stats := {"snaps": 0, "events": 0, "claims": 0, "shots": 0}
var _send_at := 0.0
var _hill_site := -1
var _disposed := false


func _init(game) -> void:
	g = game
	net = game.net
	net.on_game = _on_host_msg
	g.combat.local_auth = "claims"
	g.combat.on_claim = _on_claim
	g.combat.on_fire = _on_fire
	g.combat.on_shield = _on_shield


func started() -> bool:
	return not _disposed and local_seat >= 0 and g.state != "menu"


## Tell the host we're here, with the map we have loaded.
func say_ready() -> void:
	net.send_game({"g": "ready", "map": Maps.selected().id})


func _actor(seat: int):
	return g.actors[seat] if seat >= 0 and seat < g.actors.size() else null


func _on_claim(c: Dictionary) -> void:
	var target: int = g.actors.find(c.target)
	if target < 0:
		return
	stats.claims += 1
	net.send_game({"g": "ghit", "c": {"target": target, "dmg": Snapshot.r2(c.dmg), "head": c.head, "weapon": c.weapon,
		"point": Snapshot.v3(c.point), "dir": Snapshot.v3(c.dir), "kv": Snapshot.v3(c.kv)}})


func _on_fire(shooter: Actor, ws: WeaponState, origin: Vector3, dir: Vector3, muzzle: Vector3, spread: float) -> void:
	if g.player == null or shooter != g.player.actor:
		return
	stats.shots += 1
	net.send_game({"g": "gshot", "s": {"seat": local_seat, "weapon": ws.id, "origin": Snapshot.v3(origin),
		"dir": [Snapshot.r3(dir.x), Snapshot.r3(dir.y), Snapshot.r3(dir.z)], "muzzle": Snapshot.v3(muzzle), "spread": Snapshot.r2(spread)}})


func _on_shield(a: Actor, yaw: float) -> void:
	if g.player and a == g.player.actor:
		net.send_game({"g": "gability", "a": {"seat": local_seat, "id": "shield", "yaw": Snapshot.r3(yaw)}})


func _on_host_msg(m: Dictionary, _from: String) -> void:
	if _disposed:
		return
	match m.get("g", ""):
		"lobby":
			lobby = m.info
			# get onto the host's map while still in the lobby (the scene reloads; the connection stays up)
			if not lobby.started and g.state == "menu" and str(lobby.map) != Maps.selected().id:
				g.load_map_online(str(lobby.map))
				return
			g.lobby_changed(lobby)
		"start":
			var info: Dictionary = m.info
			var seats: Array = info.seats
			var seat := -1
			for i in seats.size():
				if seats[i].key == "h:" + net.id:
					seat = i
			if seat < 0:
				return  # joined after seating: wait for the next match
			if str(info.map) != Maps.selected().id:
				# not on the host's map yet: load it, then take this message again
				net.inbox.push_front([m, _from])
				g.load_map_online(str(info.map))
				return
			local_seat = seat
			life = 0
			buffer.clear()
			_hill_site = -1
			g.start_online_match(str(info.mode), seats, seat)
			g.combat.local_mover = g.player.actor if g.player else null
		"snap":
			if not started():
				return
			stats.snaps += 1
			buffer.push(float(m.at), m.actors)
			_apply_host_state(m)
		"ev":
			var ev: Dictionary = m.ev
			if started():
				stats.events += 1
				_on_event(ev)


## Health, score, match and pick-ups: the host's word, applied as soon as it arrives.
func _apply_host_state(m: Dictionary) -> void:
	var pa: Actor = g.player.actor if g.player else null
	var own = m.actors[local_seat] if local_seat < m.actors.size() else null
	if pa and own != null:
		var alive := pa.alive
		Snapshot.unpack_status_into(own, pa, g.time)
		pa.alive = alive  # life and death come from pop / spawn events
		if not alive:
			pa.health = 0
	Snapshot.unpack_match_into(m.match, g.match_, g.actors, Modes.HILL_SITES)
	g.pickups.apply_available(int(m.pickups))
	var site := int(m.match.h[0]) if m.match.h != null else -1
	if site != _hill_site:
		_hill_site = site
		g.place_hill()


func _on_event(ev: Dictionary) -> void:
	var me := local_seat
	match ev.get("e", ""):
		"kill":
			var victim = _actor(int(ev.victim))
			if victim:
				g.combat.pop_remote(victim, _actor(int(ev.killer)), str(ev.weapon), bool(ev.head))
		"damage":
			var target = _actor(int(ev.target))
			if target == null:
				return
			var att := int(ev.attacker)
			var tgt := int(ev.target)
			if att == me and tgt != me:
				return  # already shown when we fired
			if tgt == me:
				target.health = maxf(0, target.health - float(ev.healthDmg))
				target.shield = maxf(0, target.shield - float(ev.shieldDmg))
				target.last_damage_at = g.time
			target.hit_flinch = minf(1, target.hit_flinch + 0.6)
			g.events.emit("damage", {"attacker": _actor(att), "target": target, "amount": float(ev.amount), "shieldDmg": float(ev.shieldDmg),
				"healthDmg": float(ev.healthDmg), "head": bool(ev.head), "point": Snapshot.vec(ev.point), "weapon": "plasti9",
				"fromDir": Snapshot.vec(ev.fromDir), "shieldBroke": bool(ev.shieldBroke)})
		"spawn":
			var a = _actor(int(ev.seat))
			if a == null:
				return
			if int(ev.seat) == me:
				life += 1
			g.spawn_at(a, Vector3(ev.x, ev.y, ev.z), float(ev.yaw), bool(ev.revived), _actor(int(ev.get("by", -1))))
		"shot":
			var a = _actor(int(ev.seat))
			if a and int(ev.seat) != me:
				g.replay_shot(a, ev)
		"ability":
			var a = _actor(int(ev.seat))
			if a and int(ev.seat) != me:
				g.remote_ability(a, ev)
		"pickup":
			var a = _actor(int(ev.seat))
			if a == null:
				return
			var label: String = ev.label
			if int(ev.seat) == me and Pickups.refill_ammo(a) and not label.contains("ammo"):
				label += " + ammo"
			g.events.emit("pickup", {"actor": a, "kind": ev.kind, "label": label})
		"impulse":
			var pa: Actor = g.player.actor if g.player else null
			if pa == null or int(ev.seat) != me:
				return
			pa.vel.x += float(ev.vx)
			pa.vel.z += float(ev.vz)
			pa.vel.y = maxf(pa.vel.y, float(ev.vy))
		"match":
			var e = ev.ev
			if e is float:
				e = int(e)
			elif e is Dictionary:
				e = {"kind": e.kind, "sector": int(e.sector), "team": int(e.team)}
			g.on_match_event(e)
		"blockdrop":
			g.block_drop_at((ev.spots as Array).map(func(p): return Snapshot.vec(p)))


## Every guest frame: place everyone else, send our own state.
func update(real_now: float) -> void:
	if not started():
		return
	var target: float = net.server_now() - interp_delay
	for i in g.actors.size():
		if i == local_seat:
			continue
		var a: Actor = g.actors[i]
		var p = buffer.sample(target, i)
		if p == null:
			continue
		var was_alive := a.alive
		Snapshot.unpack_actor_into(p, a, g.time)
		if not was_alive and a.alive and a.model:
			a.model.scale_in = minf(a.model.scale_in, 0.3)
		g.gear.sync(a, Snapshot.actor_weapon_id(p), int(p[Snapshot.SLOT]))
		var r = g.remotes.get(a)
		if r != null:
			r.reload = float(p[Snapshot.RELOAD])
	if real_now >= _send_at:
		_send_at = real_now + 1000.0 / net.GUEST_RATE
		var s = _own_state()
		if s != null:
			net.send_game({"g": "gstate", "s": s})


func _own_state():
	var pl = g.player
	var a: Actor = pl.actor if pl else null
	if a == null or not a.alive:
		return null
	var ws: WeaponState = a.weapon()
	return {
		"life": life, "x": Snapshot.r2(a.pos.x), "y": Snapshot.r2(a.pos.y), "z": Snapshot.r2(a.pos.z), "yaw": Snapshot.r3(a.yaw), "pitch": Snapshot.r3(a.pitch),
		"vy": Snapshot.r2(a.vel.y), "speed": Snapshot.r2(a.speed), "grounded": a.grounded, "alive": a.alive, "slot": a.slot,
		"weapon": ws.id if ws else "", "reload": Snapshot.r2(maxf(0.01, ws.reload_progress())) if ws and ws.reloading else 0,
		"ads": Snapshot.r2(a.ads), "crouch": Snapshot.r2(a.crouch_t), "sliding": a.sliding, "dashing": a.dashing, "cloaked": a.cloaked,
		"fireKick": Snapshot.r2(a.fire_kick), "revive": pl.revive_held, "grapple": Snapshot.v3(a.grapple.anchor) if a.grapple != null else null,
		"jabT": Snapshot.r2(a.jab_t),
	}


func dispose() -> void:
	_disposed = true
	var c: Combat = g.combat
	c.local_auth = "full"
	c.local_mover = null
	c.on_claim = Callable()
	c.on_fire = Callable()
	c.on_shield = Callable()
	if net.on_game == Callable(self, "_on_host_msg"):
		net.on_game = Callable()

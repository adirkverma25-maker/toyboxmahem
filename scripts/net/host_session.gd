class_name HostSession
extends RefCounted
## The host's side of an online match (port of src/net/HostSession.ts). The host's game runs the real
## match; this
##  - keeps the lobby (mode, map, bot count, who's here) and starts the match
##  - drives each guest's toy from the states the guest sends
##  - applies the hits guests claim, replays their shots and shields so they show up here
##  - sends everyone snapshots (TICK_RATE a second) and events (pops, damage, spawns, pick-ups, match events)

## the lobby survives the scene reload when the host switches map
static var saved_lobby := {}

var g  # Game
var net  # the Net autoload
var lobby := {}
## peer id -> map id that guest has loaded (they send "ready" after every load)
var ready_maps := {}
## counters (dev test / debugging)
var stats := {"states": 0, "claims": 0, "shots": 0}
var _snap_at := 0.0
var _tick := 0
## pieces broken / newly cracked since the last snapshot (sent as one "break" event)
var _broken_queue: Array = []
var _cracked_queue: Array = []
var _disposed := false


func _init(game, mode: String, bots: int) -> void:
	g = game
	net = game.net
	if saved_lobby.is_empty():
		lobby = {"mode": mode, "map": Maps.selected().id, "bots": bots, "players": [], "started": false}
	else:
		lobby = saved_lobby.duplicate(true)
		lobby.started = false
		saved_lobby = {}
	net.on_game = _on_guest_msg
	net.on_peers = _peers_changed
	g.events.on("damage", _ev_damage)
	g.events.on("kill", _ev_kill)
	g.events.on("pickup", _ev_pickup)
	g.combat.on_remote_kick = _remote_kick
	g.combat.on_fire = _on_fire
	g.combat.on_shield = _on_shield


## a match is running (as opposed to the lobby)
func live() -> bool:
	return not _disposed and lobby.started and g.state != "menu"


func players() -> Array:
	var out := [{"id": net.id, "name": net.player_name}]
	for id in net.peers:
		out.append({"id": id, "name": net.peers[id]})
	return out


func set_lobby(p: Dictionary) -> void:
	lobby.merge(p, true)
	broadcast_lobby()


func broadcast_lobby() -> void:
	if _disposed:
		return
	lobby.players = players()
	lobby.map = Maps.selected().id
	lobby.bots = clampi(int(lobby.bots), 0, Roster.max_bots(lobby.mode, lobby.players.size()))
	lobby.ready = ready_maps.duplicate()
	net.send_game({"g": "lobby", "info": lobby})
	g.lobby_changed(lobby)


## Remember the lobby across a map switch (the scene reloads; the connection stays up).
func keep_for_reload() -> void:
	saved_lobby = lobby.duplicate(true)


## How many guests haven't finished loading the lobby's map yet.
func loading_count() -> int:
	var n := 0
	for id in net.peers:
		if ready_maps.get(id, "") != Maps.selected().id:
			n += 1
	return n


## Seat everyone, tell the guests, start the match here.
func start() -> void:
	var seats := Roster.build_seats(lobby.mode, players(), int(lobby.bots))
	lobby.started = true
	broadcast_lobby()
	net.send_game({"g": "start", "info": {"mode": lobby.mode, "map": lobby.map, "seats": seats}})
	g.start_online_match(lobby.mode, seats, 0)


## Back to the lobby after a match (results screen closed).
func back_to_lobby() -> void:
	lobby.started = false
	broadcast_lobby()


func _peers_changed() -> void:
	for id in ready_maps.keys():
		if not net.peers.has(id):
			ready_maps.erase(id)
	if not lobby.started:
		broadcast_lobby()
		return
	# mid-match: anyone who left loses their toy
	for a in g.remotes.keys():
		var r: Dictionary = g.remotes[a]
		if r.net_id != "" and not net.peers.has(r.net_id):
			g.drop_remote(a)
	lobby.players = players()
	g.lobby_changed(lobby)


func _actor_of(net_id: String):
	for a in g.remotes:
		if g.remotes[a].net_id == net_id:
			return a
	return null


func seat(a) -> int:
	return g.actors.find(a) if a != null else -1


func send_ev(ev: Dictionary, to := "") -> void:
	net.send_game({"g": "ev", "ev": ev}, to)


# ------------------------------------------------------------------ hooks into the local match
func _ev_damage(d: Dictionary) -> void:
	if not live():
		return
	send_ev({"e": "damage", "attacker": seat(d.attacker), "target": seat(d.target), "amount": Snapshot.r2(d.amount),
		"shieldDmg": Snapshot.r2(d.shieldDmg), "healthDmg": Snapshot.r2(d.healthDmg), "head": d.head,
		"point": Snapshot.v3(d.point), "fromDir": Snapshot.v3(d.fromDir), "shieldBroke": d.shieldBroke})


func _ev_kill(k: Dictionary) -> void:
	if live():
		send_ev({"e": "kill", "killer": seat(k.killer), "victim": seat(k.victim), "weapon": k.weapon, "head": k.head})


func _ev_pickup(p: Dictionary) -> void:
	if live():
		send_ev({"e": "pickup", "seat": seat(p.actor), "kind": p.kind, "label": p.label})


## Knockback for a toy moved by a guest's game: send it to them.
func _remote_kick(a: Actor, v: Vector3, min_vy: float) -> bool:
	var r = g.remotes.get(a)
	if r == null or r.net_id == "":
		return false
	send_ev({"e": "impulse", "seat": r.seat, "vx": Snapshot.r2(v.x), "vy": Snapshot.r2(maxf(v.y, min_vy)), "vz": Snapshot.r2(v.z)}, r.net_id)
	return true


func _on_fire(shooter: Actor, ws: WeaponState, origin: Vector3, dir: Vector3, muzzle: Vector3, spread: float) -> void:
	if not live() or g.remotes.has(shooter):
		return  # guests' shots are relayed when they arrive
	send_ev({"e": "shot", "seat": seat(shooter), "weapon": ws.id, "origin": Snapshot.v3(origin),
		"dir": [snappedf(dir.x, 0.0001), snappedf(dir.y, 0.0001), snappedf(dir.z, 0.0001)], "muzzle": Snapshot.v3(muzzle), "spread": Snapshot.r2(spread)})


func _on_shield(a: Actor, yaw: float) -> void:
	if live() and not g.remotes.has(a):
		send_ev({"e": "ability", "seat": seat(a), "id": "shield", "yaw": Snapshot.r3(yaw)})


func _on_guest_msg(m: Dictionary, from: String) -> void:
	if _disposed:
		return
	var kind: String = m.get("g", "")
	if kind == "ready":
		ready_maps[from] = str(m.get("map", ""))
		if not lobby.started:
			broadcast_lobby()
		else:
			# joined (or reloaded) during a match: they wait in the lobby for the next one
			net.send_game({"g": "lobby", "info": lobby}, from)
		return
	var a = _actor_of(from)
	if a == null or not live():
		return
	if kind == "gpiece":
		_on_piece_claim(m)
		return
	var r: Dictionary = g.remotes[a]
	match kind:
		"gstate":
			var s: Dictionary = m.s
			if int(s.life) >= int(r.life):
				stats.states += 1
				r.state = s
				r.revive_held = bool(s.get("revive", false))
				# the guest's class: kept for its next spawns, and applied to this life on its first state
				var c := str(s.get("cls", "light"))
				r.cls = c if Cfg.CLASSES.has(c) else "light"
				if int(r.cls_life) != int(r.life) and a.alive:
					r.cls_life = r.life
					if a.cls != r.cls:
						a.set_class(r.cls)
		"ghit":
			var c: Dictionary = m.c
			var ti := int(c.target)
			if ti < 0 or ti >= g.actors.size():
				return
			var target: Actor = g.actors[ti]
			if not accept_claim(target, a):
				return
			stats.claims += 1
			g.combat.apply_claim({"target": target, "dmg": minf(float(c.dmg), 400.0), "head": bool(c.head), "weapon": str(c.weapon),
				"point": Snapshot.vec(c.point), "dir": Snapshot.vec(c.dir), "kv": Snapshot.vec(c.kv)}, a)
		"gshot":
			var s: Dictionary = m.s
			if int(s.seat) != r.seat:
				return
			stats.shots += 1
			g.replay_shot(a, s)
			var ev := s.duplicate()
			ev.e = "shot"
			send_ev(ev)
		"gability":
			var ab: Dictionary = m.a
			if int(ab.seat) != r.seat:
				return
			g.remote_ability(a, ab)
			var ev := ab.duplicate()
			ev.e = "ability"
			send_ev(ev)


## Host-side check of a guest's "my shot hit that toy". Friends are trusted, so this only stops claims
## that can't be right any more (target or shooter already popped, teammates). Your own splash is fine.
static func accept_claim(target: Actor, attacker: Actor) -> bool:
	if not target.alive or not attacker.alive:
		return false
	if target == attacker:
		return true
	if attacker.team >= 0 and attacker.team == target.team:
		return false
	return true


## Put a guest's toy where their game says it is. Called every frame instead of Actor.move.
func drive(a: Actor, r: Dictionary) -> void:
	var s = r.state
	if s == null or not a.alive or int(s.life) < int(r.life):
		return
	a.pos = Vector3(s.x, s.y, s.z)
	a.yaw = s.yaw
	a.pitch = s.pitch
	a.vel.y = s.vy
	a.speed = s.speed
	a.grounded = s.grounded
	a.ads = s.ads
	a.crouch_t = s.crouch
	a.crouching = float(s.crouch) > 0.5
	a.sliding = s.sliding
	a.dashing = s.dashing
	a.cloaked = s.cloaked
	a.fire_kick = maxf(a.fire_kick, s.fireKick)
	a.melee_t = s.meleeT
	if s.grapple != null:
		var anchor := Snapshot.vec(s.grapple)
		if a.grapple != null:
			a.grapple.anchor = anchor
		else:
			a.grapple = {"anchor": anchor, "start": g.time, "check_at": INF, "check_dist": INF, "climbing": false}
	else:
		a.grapple = null
	r.reload = float(s.reload)
	g.gear.sync(a, str(s.weapon), int(s.slot))


## A toy (re)spawned or was revived here: tell everyone where.
func on_spawn(a: Actor, pos: Vector3, yaw: float, revived: bool, by = null) -> void:
	if not lobby.started or _disposed:
		return
	var ev := {"e": "spawn", "seat": seat(a), "x": Snapshot.r2(pos.x), "y": Snapshot.r2(pos.y), "z": Snapshot.r2(pos.z), "yaw": Snapshot.r2(yaw), "revived": revived}
	if by != null:
		ev.by = seat(by)
	send_ev(ev)


func match_event(e) -> void:
	if live():
		send_ev({"e": "match", "ev": e})


func block_drop(spots: Array) -> void:
	if live():
		send_ev({"e": "blockdrop", "spots": spots.map(func(p): return Snapshot.v3(p))})


## A wall or prop broke here: tell the guests with the next snapshot.
func piece_broken(id: int) -> void:
	if live():
		_broken_queue.append(id)


## A piece started showing cracks here: guests show them too.
func piece_cracked(id: int) -> void:
	if live():
		_cracked_queue.append(id)


## A guest's own attack hit a breakable piece. Unknown or already-broken pieces are ignored.
func _on_piece_claim(m: Dictionary) -> void:
	var D: Destruction = g.destruction
	var id := int(m.get("id", -1))
	var kind := str(m.get("kind", ""))
	if id < 0 or id >= D.pieces.size() or D.is_broken(id) or not kind in ["bullet", "blast"]:
		stats.stale_pieces = stats.get("stale_pieces", 0) + 1
		return
	stats.pieces = stats.get("pieces", 0) + 1
	var p: Dictionary = D.pieces[id]
	D.damage(id, clampf(float(m.get("dmg", 0.0)), 0.0, 400.0), kind, (p.mn + p.mx) / 2, Vector3.UP)


## Called every host frame: sends a snapshot TICK_RATE times a second.
func update(real_now: float) -> void:
	if not live() or real_now < _snap_at:
		return
	_snap_at = real_now + 1000.0 / net.TICK_RATE
	_tick += 1
	if _broken_queue.size() or _cracked_queue.size():
		send_ev({"e": "break", "ids": _broken_queue, "cracked": _cracked_queue})
		_broken_queue = []
		_cracked_queue = []
	var packed := []
	for a in g.actors:
		packed.append(Snapshot.pack_actor(a, g.time))
	var snap := {"g": "snap", "tick": _tick, "at": roundf(net.server_now()), "actors": packed,
		"match": Snapshot.pack_match(g.match_, g.actors, Modes.HILL_SITES), "pickups": Snapshot.pack_pickups(g.pickups.list())}
	# every 2 s the whole list of broken pieces, so a missed event can't leave a guest with a wall the host lost
	if _tick % (net.TICK_RATE * 2) == 0:
		snap.bk = Array(g.destruction.broken_ids())
		snap.ck = Array(g.destruction.cracked_ids())
	net.send_game(snap)


func dispose() -> void:
	_disposed = true
	g.events.off("damage", _ev_damage)
	g.events.off("kill", _ev_kill)
	g.events.off("pickup", _ev_pickup)
	g.combat.on_remote_kick = Callable()
	g.combat.on_fire = Callable()
	g.combat.on_shield = Callable()
	if net.on_game == Callable(self, "_on_guest_msg"):
		net.on_game = Callable()
	if net.on_peers == Callable(self, "_peers_changed"):
		net.on_peers = Callable()

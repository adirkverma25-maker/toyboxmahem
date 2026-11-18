class_name Snapshot
extends RefCounted
## Packing the host's match into small JSON for snapshots, and unpacking it on guests
## (port of src/net/snapshot.ts). A packed actor is a flat Array of numbers, indexed by the constants below.

const X := 0
const Y := 1
const Z := 2
const YAW := 3
const PITCH := 4
const HEALTH := 5
const SHIELD := 6
const ALIVE := 7
const TEAM := 8
const KILLS := 9
const DEATHS := 10
const HEADSHOTS := 11
const REVIVES := 12
const STREAK := 13
const SLOT := 14
const WEAPON := 15
const RELOAD := 16
const ADS := 17
const CROUCH := 18
const SPEED := 19
const GROUNDED := 20
const VY := 21
const FIRE_KICK := 22
const HIT_FLINCH := 23
const DASHING := 24
const SLIDING := 25
const CLOAKED := 26
## melee swing timer (seconds left)
const MELEE_T := 27
const RESPAWN := 28
const REVIVE_T := 29
const TURBO := 30
const INFINITE := 31
const POWER := 32
const GRAPPLE := 33
const GX := 34
const GY := 35
const GZ := 36
const BEST_STREAK := 37
## class: 0 light, 1 medium (which melee weapon the toy swings)
const CLS := 38
## fighting with the melee weapon instead of a blaster
const MELEE_HELD := 39
## seconds of Glitch Jug left
const GLITCH := 40
## seconds of flash left
const FLASH := 41
const LENGTH := 42

## fields that blend smoothly between snapshots; everything else steps to the newer value
const LERP := [X, Y, Z, PITCH, CROUCH, ADS, SPEED]
## "no respawn pending" on the wire (a real relative time can be slightly negative)
const NO_RESPAWN := -999.0
const PHASES := ["countdown", "playing", "ended"]

static var _weapon_ids: Array = []


static func weapon_ids() -> Array:
	if _weapon_ids.is_empty():
		_weapon_ids = Cfg.WEAPONS.keys()
	return _weapon_ids


static func r2(v: float) -> float:
	return roundf(v * 100) / 100


static func r3(v: float) -> float:
	return roundf(v * 1000) / 1000


static func v3(v: Vector3) -> Array:
	return [r2(v.x), r2(v.y), r2(v.z)]


static func vec(a) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


static func _b(v: bool) -> int:
	return 1 if v else 0


## absolute clock time -> seconds left (0 = none)
static func _left(t: float, now: float) -> float:
	return r2(t - now) if t > now else 0.0


## Pack one toy. `now` is the sender's game clock: timers go out as time left (every game's clock differs).
static func pack_actor(a: Actor, now: float) -> Array:
	var ws: WeaponState = a.weapon()
	var g = a.grapple
	var p := []
	p.resize(LENGTH)
	p[X] = r2(a.pos.x)
	p[Y] = r2(a.pos.y)
	p[Z] = r2(a.pos.z)
	p[YAW] = r3(a.yaw)
	p[PITCH] = r3(a.pitch)
	p[HEALTH] = roundf(a.health * 10) / 10
	p[SHIELD] = roundf(a.shield * 10) / 10
	p[ALIVE] = _b(a.alive)
	p[TEAM] = a.team
	p[KILLS] = a.kills
	p[DEATHS] = a.deaths
	p[HEADSHOTS] = a.headshots
	p[REVIVES] = a.revives
	p[STREAK] = a.streak
	p[BEST_STREAK] = a.best_streak
	p[SLOT] = a.slot
	p[WEAPON] = weapon_ids().find(ws.id) if ws else -1
	p[RELOAD] = r2(maxf(0.01, ws.reload_progress())) if ws and ws.reloading else 0
	p[ADS] = r2(a.ads)
	p[CROUCH] = r2(a.crouch_t)
	p[SPEED] = r2(a.speed)
	p[GROUNDED] = _b(a.grounded)
	p[VY] = r2(a.vel.y)
	p[FIRE_KICK] = r2(a.fire_kick)
	p[HIT_FLINCH] = r2(a.hit_flinch)
	p[DASHING] = _b(a.dashing)
	p[SLIDING] = _b(a.sliding)
	p[CLOAKED] = _b(a.cloaked)
	p[MELEE_T] = r2(a.melee_t)
	p[CLS] = 1 if a.cls == "medium" else 0
	p[MELEE_HELD] = _b(a.melee_held)
	p[GLITCH] = _left(a.glitched_until, now)
	p[FLASH] = _left(a.flashed_until, now)
	p[RESPAWN] = NO_RESPAWN if a.respawn_at < 0 else r2(a.respawn_at - now)
	p[REVIVE_T] = r2(a.revive_t)
	p[TURBO] = _left(a.buffs.turbo, now)
	p[INFINITE] = _left(a.buffs.infinite, now)
	p[POWER] = _left(a.buffs.power, now)
	p[GRAPPLE] = _b(g != null)
	p[GX] = r2(g.anchor.x) if g != null else 0
	p[GY] = r2(g.anchor.y) if g != null else 0
	p[GZ] = r2(g.anchor.z) if g != null else 0
	return p


static func actor_weapon_id(p: Array) -> String:
	var i := int(p[WEAPON])
	var ids := weapon_ids()
	return ids[i] if i >= 0 and i < ids.size() else ""


## Copy everything in a packed actor onto an actor (a puppet on a guest). `now` = receiver's game clock.
static func unpack_actor_into(p: Array, a: Actor, now: float) -> void:
	a.pos = Vector3(p[X], p[Y], p[Z])
	a.yaw = p[YAW]
	a.pitch = p[PITCH]
	unpack_status_into(p, a, now)
	a.slot = int(p[SLOT])
	a.ads = p[ADS]
	a.crouch_t = p[CROUCH]
	a.crouching = a.crouch_t > 0.5
	a.speed = p[SPEED]
	a.grounded = p[GROUNDED] > 0
	a.vel.y = p[VY]
	a.fire_kick = p[FIRE_KICK]
	a.hit_flinch = p[HIT_FLINCH]
	a.dashing = p[DASHING] > 0
	a.sliding = p[SLIDING] > 0
	a.cloaked = p[CLOAKED] > 0
	a.melee_t = p[MELEE_T]
	if p.size() > CLS:
		a.cls = "medium" if p[CLS] > 0 else "light"
	if p.size() > MELEE_HELD:
		a.melee_held = p[MELEE_HELD] > 0
	if p[GRAPPLE] > 0:
		var anchor := Vector3(p[GX], p[GY], p[GZ])
		if a.grapple != null:
			a.grapple.anchor = anchor
		else:
			a.grapple = {"anchor": anchor, "start": now, "check_at": INF, "check_dist": INF, "climbing": false}
	else:
		a.grapple = null


## What the host decides even for a guest's own toy: health, shield, life, team, score, power-up timers.
static func unpack_status_into(p: Array, a: Actor, now: float) -> void:
	a.health = p[HEALTH]
	a.shield = p[SHIELD]
	a.alive = p[ALIVE] > 0
	a.team = int(p[TEAM])
	a.kills = int(p[KILLS])
	a.deaths = int(p[DEATHS])
	a.headshots = int(p[HEADSHOTS])
	a.revives = int(p[REVIVES])
	a.streak = int(p[STREAK])
	a.best_streak = int(p[BEST_STREAK])
	a.respawn_at = -1.0 if p[RESPAWN] == NO_RESPAWN else now + float(p[RESPAWN])
	a.revive_t = p[REVIVE_T]
	a.buffs.turbo = now + float(p[TURBO]) if p[TURBO] > 0 else 0.0
	a.buffs.infinite = now + float(p[INFINITE]) if p[INFINITE] > 0 else 0.0
	if p.size() > GLITCH:
		a.glitched_until = now + float(p[GLITCH]) if p[GLITCH] > 0 else 0.0
	if p.size() > FLASH:
		var fl := float(p[FLASH])
		if fl > 0 and a.flashed_until <= now:
			a.flash_len = fl
		a.flashed_until = now + fl if fl > 0 else 0.0
	a.buffs.power = now + float(p[POWER]) if p[POWER] > 0 else 0.0


static func pack_match(m: Match, actors: Array, sites: Array) -> Dictionary:
	var h = m.hill
	var hp = null
	if h != null:
		hp = [sites.find(h.site), sites.find(h.next), r2(h.pos.x), r2(h.pos.y), r2(h.pos.z), r2(h.timeLeft), h.owner, _b(h.contested)] + h.counts
	var s := []
	for sec in m.sectors:
		s.append([sec.owner, r3(sec.progress), sec.progressTeam, _b(sec.contested), sec.active] + sec.counts)
	return {
		"ph": PHASES.find(m.phase), "cd": r2(m.countdown), "tl": r2(m.time_left),
		"ts": m.team_scores.map(func(x): return r2(x)), "wt": m.winner_team,
		"w": actors.find(m.winner) if m.winner else -1, "er": 1 if m.end_reason == "time" else 0,
		"h": hp, "s": s,
	}


static func unpack_match_into(p: Dictionary, m: Match, actors: Array, sites: Array) -> void:
	var ph := int(p.ph)
	m.phase = PHASES[ph] if ph >= 0 and ph < PHASES.size() else "playing"
	m.countdown = p.cd
	m.time_left = p.tl
	m.team_scores = (p.ts as Array).map(func(x): return float(x))
	m.winner_team = int(p.wt)
	var w := int(p.w)
	m.winner = actors[w] if w >= 0 and w < actors.size() else null
	m.end_reason = "time" if p.er else "score"
	if p.h != null and sites.size():
		var hh: Array = p.h
		var si := int(hh[0])
		var ni := int(hh[1])
		var site: Dictionary = sites[si] if si >= 0 and si < sites.size() else sites[0]
		var nxt: Dictionary = sites[ni] if ni >= 0 and ni < sites.size() else site
		var counts := hh.slice(8).map(func(x): return int(x))
		if m.hill != null:
			m.hill.site = site
			m.hill.next = nxt
			m.hill.pos = Vector3(hh[2], hh[3], hh[4])
			m.hill.timeLeft = hh[5]
			m.hill.owner = int(hh[6])
			m.hill.contested = hh[7] > 0
			m.hill.counts = counts
		else:
			m.hill = {"site": site, "next": nxt, "pos": Vector3(hh[2], hh[3], hh[4]), "timeLeft": hh[5], "owner": int(hh[6]), "contested": hh[7] > 0, "counts": counts}
	else:
		m.hill = null
	var rows: Array = p.s
	for i in mini(rows.size(), m.sectors.size()):
		var row: Array = rows[i]
		var s: Dictionary = m.sectors[i]
		s.owner = int(row[0])
		s.progress = row[1]
		s.progressTeam = int(row[2])
		s.contested = row[3] > 0
		s.active = int(row[4])
		s.counts = row.slice(5).map(func(x): return int(x))


static func pack_pickups(list: Array) -> int:
	var mask := 0
	for i in list.size():
		if list[i].available:
			mask |= 1 << i
	return mask


## A short history of snapshots so other toys can be drawn a little in the past, smoothly between
## 20 Hz updates (snapshot interpolation; port of src/net/interp.ts).
class Buffer:
	const KEEP_MS := 1000.0
	var entries: Array = []  # [{at, actors}]

	func push(at: float, actors: Array) -> void:
		if entries.size() and at <= entries[-1].at:
			return
		entries.append({"at": at, "actors": actors})
		while entries.size() > 1 and entries[0].at < at - KEEP_MS:
			entries.pop_front()

	func clear() -> void:
		entries = []

	## The seat's packed actor at time `target` (same clock as `at`), or null.
	func sample(target: float, seat: int):
		var h := entries
		if h.is_empty():
			return null
		if target <= h[0].at:
			return _at(h[0].actors, seat)
		var last: Dictionary = h[-1]
		if target >= last.at:
			return _at(last.actors, seat)
		for i in range(h.size() - 1, 0, -1):
			var a: Dictionary = h[i - 1]
			var b: Dictionary = h[i]
			if target < a.at:
				continue
			var pa = _at(a.actors, seat)
			var pb = _at(b.actors, seat)
			if pa == null or pb == null:
				return pb if pb != null else pa
			var k: float = (target - a.at) / maxf(1.0, b.at - a.at)
			var out: Array = (pb as Array).duplicate()
			for f in LERP:
				out[f] = pa[f] + (pb[f] - pa[f]) * k
			var dyaw := atan2(sin(pb[YAW] - pa[YAW]), cos(pb[YAW] - pa[YAW]))
			out[YAW] = pa[YAW] + dyaw * k
			return out
		return _at(last.actors, seat)

	static func _at(arr: Array, seat: int):
		return arr[seat] if seat >= 0 and seat < arr.size() else null

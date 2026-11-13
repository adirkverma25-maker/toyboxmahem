class_name Match
extends RefCounted
## Match rules for every mode (port of src/match/Match.ts).
##  ffa      - first actor to the target, or most pops at time
##  tdm      - team pops, first team to the target
##  takeover - teams score by holding the moving toy box
##  conquest - three teams capture sectors, first to hold 4 of 6
## update() returns events: an int (countdown), "go", "end", "blockdrop", "hillwarn", "hillmove", "hilltaken",
## "hillcontested", or a Dictionary {kind: captured|neutralized|attacked, sector, team}.

var phys: Phys
var spawn_points: Array
var mode: Dictionary = Modes.MODES.ffa
var phase := "countdown"
var countdown := 3.0
var time_left := 600.0
var winner: Actor = null
## -1 = no team result (ffa), team index for a team win, DRAW (-2) for a tie
var winner_team := -1
var end_reason := "score"
var team_scores: Array = [0.0, 0.0]
## {site, pos, next, timeLeft, counts, owner, contested} or null
var hill = null
## [{def, pos, owner, progress, progressTeam, counts, contested, active, lastAttackNote}]
var sectors: Array = []
var started_at := 0.0
var block_drops_enabled := randf() < 0.65
var next_block_drop := U.rand(70, 130)
var ended_at := 0.0
var _last_count := 4
var _site_bag: Array = []
## extra spawn pool for actors that should start on the high shelves (FFA newcomers)
var shelf_spawns: Array = []


func _init(p: Phys, spawns: Array) -> void:
	phys = p
	spawn_points = spawns


func kill_target() -> int:
	return mode.scoreTarget


func teams() -> bool:
	return mode.teams


func team_count() -> int:
	return mode.teamCount


func set_mode(id: String) -> void:
	mode = Modes.MODES[id]


func reset(now: float) -> void:
	phase = "countdown"
	countdown = 3
	time_left = mode.timeLimit
	winner = null
	winner_team = -1
	team_scores = []
	for i in maxi(2, mode.teamCount):
		team_scores.append(0.0)
	started_at = now
	block_drops_enabled = randf() < 0.65
	next_block_drop = U.rand(70, 130)
	_last_count = 4
	_site_bag = []
	hill = null
	sectors = []
	if mode.id == "takeover":
		var first := _draw_site()
		hill = {"site": first, "pos": _snap(first), "next": _draw_site(first), "timeLeft": Modes.TAKEOVER.hillDuration, "counts": [0, 0], "owner": -1, "contested": false}
	if mode.id == "conquest":
		for i in Modes.SECTORS.size():
			var def: Dictionary = Modes.SECTORS[i]
			var home := Modes.CONQUEST_HOMES.find(i)
			sectors.append({"def": def, "pos": _snap(def), "owner": home, "progress": 1.0 if home >= 0 else 0.0, "progressTeam": home,
				"counts": [0, 0, 0], "contested": false, "active": -1, "lastAttackNote": -99.0})
		_refresh_sector_scores()


func _draw_site(avoid = null) -> Dictionary:
	if _site_bag.is_empty():
		_site_bag = Modes.HILL_SITES.duplicate()
		_site_bag.shuffle()
	var s: Dictionary = _site_bag.pop_back()
	if avoid != null and s == avoid:
		if _site_bag.is_empty():
			_site_bag = Modes.HILL_SITES.filter(func(x): return x != avoid)
			_site_bag.shuffle()
		var other: Dictionary = _site_bag.pop_back()
		_site_bag.push_front(s)
		s = other
	return s


## Put the zone exactly on whatever surface is there.
func _snap(site: Dictionary) -> Vector3:
	var p: Vector3 = site.pos
	var d := phys.ray_dist(Vector3(p.x, p.y + 2.5, p.z), Vector3.DOWN, 6, true)
	if d != INF:
		p.y = p.y + 2.5 - d
	return p


## Called for every elimination. Returns true if it scored.
func on_kill(killer, victim: Actor) -> bool:
	if phase != "playing":
		return false
	if mode.id == "tdm" and killer and killer != victim and killer.team >= 0 and killer.team != victim.team:
		team_scores[killer.team] += 1
		return true
	return false


## Ranked standings of individual toys.
func standings(actors: Array) -> Array:
	var s := actors.duplicate()
	s.sort_custom(func(a, b):
		if a.kills != b.kills:
			return a.kills > b.kills
		if a.deaths != b.deaths:
			return a.deaths < b.deaths
		return a.score_at < b.score_at)
	return s


func leader(actors: Array) -> Actor:
	var s := standings(actors)
	return s[0] if s.size() else null


func top_score(actors: Array) -> float:
	if teams():
		return team_scores.max()
	var l := leader(actors)
	return l.kills if l else 0


## Teams ordered best first.
func team_order() -> Array:
	var idx := range(team_scores.size())
	idx.sort_custom(func(a, b): return team_scores[a] > team_scores[b])
	return idx


func _in_cylinder(a: Actor, pos: Vector3, radius: float, height: float) -> bool:
	if not a.alive:
		return false
	var dx := a.pos.x - pos.x
	var dz := a.pos.z - pos.z
	return dx * dx + dz * dz <= radius * radius and a.pos.y > pos.y - 1.2 and a.pos.y < pos.y + height


func in_hill(a: Actor) -> bool:
	return hill != null and _in_cylinder(a, hill.pos, hill.site.radius, hill.site.height)


## Index of the conquest sector this actor is standing in, or -1.
func sector_of(a: Actor) -> int:
	for i in sectors.size():
		var s: Dictionary = sectors[i]
		if _in_cylinder(a, s.pos, s.def.radius, s.def.height):
			return i
	return -1


func sectors_owned(team: int) -> int:
	var n := 0
	for s in sectors:
		if s.owner == team:
			n += 1
	return n


func _refresh_sector_scores() -> void:
	for t in team_scores.size():
		team_scores[t] = float(sectors_owned(t))


func _update_sectors(dt: float, actors: Array, now: float, out: Array) -> void:
	var C: Dictionary = Modes.CONQUEST
	for i in sectors.size():
		var s: Dictionary = sectors[i]
		var counts := [0, 0, 0]
		for a in actors:
			if a.team >= 0 and _in_cylinder(a, s.pos, s.def.radius, s.def.height):
				counts[a.team] += 1
		s.counts = counts
		var present := []
		for t in 3:
			if counts[t] > 0:
				present.append(t)
		s.contested = present.size() > 1
		s.active = -1
		if s.contested:
			continue  # frozen while two or more teams are inside
		if present.is_empty():
			# abandoned half-captures drain away
			if s.owner < 0 and s.progress > 0:
				s.progress = maxf(0, s.progress - C.decayRate * dt)
				if s.progress <= 0:
					s.progressTeam = -1
			continue
		var t: int = present[0]
		var speed: float = 1 + mini(2, counts[t] - 1) * C.bonusPerExtraToy
		if s.owner == t:
			if s.progress < 1:
				s.progress = minf(1, s.progress + dt * speed / C.neutralizeTime)
				s.active = t
		elif s.owner >= 0:
			# enemy sector: drain it to neutral
			s.active = t
			s.progress -= dt * speed / C.neutralizeTime
			if now - s.lastAttackNote > 6:
				s.lastAttackNote = now
				out.append({"kind": "attacked", "sector": i, "team": s.owner})
			if s.progress <= 0:
				var lost: int = s.owner
				s.owner = -1
				s.progress = 0.0
				s.progressTeam = -1
				out.append({"kind": "neutralized", "sector": i, "team": lost})
		else:
			# neutral: someone else's half-capture has to be undone first
			s.active = t
			if s.progressTeam >= 0 and s.progressTeam != t:
				s.progress -= dt * speed / C.captureTime
				if s.progress <= 0:
					s.progress = 0.0
					s.progressTeam = t
			else:
				s.progressTeam = t
				s.progress += dt * speed / C.captureTime
				if s.progress >= 1:
					s.progress = 1.0
					s.owner = t
					out.append({"kind": "captured", "sector": i, "team": t})
	_refresh_sector_scores()


func update(dt: float, actors: Array, now: float) -> Array:
	var out := []
	if phase == "countdown":
		countdown -= dt
		var c := int(ceil(countdown))
		if c < _last_count and c > 0:
			out.append(c)
			_last_count = c
		if countdown <= 0:
			phase = "playing"
			out.append("go")
		return out
	if phase != "playing":
		return out
	if mode.get("training", false):
		# training never ends: the clock counts the session up instead
		time_left += dt
		return out
	time_left -= dt
	if block_drops_enabled:
		next_block_drop -= dt
		if next_block_drop <= 0:
			next_block_drop = U.rand(80, 150)
			if time_left > 20:
				out.append("blockdrop")
	# toy box takeover scoring + movement
	var h = hill
	if h != null:
		var counts := [0, 0]
		for a in actors:
			if a.team >= 0 and in_hill(a):
				counts[a.team] += 1
		var prev_owner: int = h.owner
		var prev_contested: bool = h.contested
		h.counts = counts
		h.contested = counts[0] > 0 and counts[1] > 0
		h.owner = -1 if h.contested else (0 if counts[0] > 0 else (1 if counts[1] > 0 else -1))
		if h.owner >= 0:
			var extra := mini(2, counts[h.owner] - 1)
			team_scores[h.owner] = minf(mode.scoreTarget, team_scores[h.owner] + dt * (Modes.TAKEOVER.pointsPerSecond + extra * Modes.TAKEOVER.bonusPerExtraToy))
		if h.owner >= 0 and h.owner != prev_owner:
			out.append("hilltaken")
		if h.contested and not prev_contested:
			out.append("hillcontested")
		var before: float = h.timeLeft
		h.timeLeft -= dt
		if before > Modes.TAKEOVER.warnBefore and h.timeLeft <= Modes.TAKEOVER.warnBefore:
			out.append("hillwarn")
		if h.timeLeft <= 0:
			h.site = h.next
			h.pos = _snap(h.site)
			h.next = _draw_site(h.site)
			h.timeLeft = Modes.TAKEOVER.hillDuration
			h.owner = -1
			h.contested = false
			out.append("hillmove")
	if sectors.size():
		_update_sectors(dt, actors, now, out)
	# end conditions
	if teams():
		var target: float = mode.scoreTarget
		var reached := -1
		for t in team_scores.size():
			if team_scores[t] >= target:
				reached = t
				break
		if reached >= 0:
			_end_team(reached, "score", actors, now)
			out.append("end")
		elif time_left <= 0:
			time_left = 0
			var fl := team_scores.map(func(s): return floori(s))
			var best: int = fl.max()
			var leaders := []
			for t in fl.size():
				if fl[t] == best:
					leaders.append(t)
			_end_team(leaders[0] if leaders.size() == 1 else Modes.DRAW, "time", actors, now)
			out.append("end")
	else:
		var top := leader(actors)
		if top and top.kills >= kill_target():
			_end(top, "score", now)
			out.append("end")
		elif time_left <= 0:
			time_left = 0
			_end(top, "time", now)
			out.append("end")
	return out


func _end(w: Actor, reason: String, now: float) -> void:
	if phase == "ended":
		return
	phase = "ended"
	winner = w
	end_reason = reason
	ended_at = now


func _end_team(team: int, reason: String, actors: Array, now: float) -> void:
	winner_team = team
	# MVP of the winning side (or overall on a draw) for the stats screen
	var pool := actors.filter(func(a): return a.team == team) if team >= 0 else actors
	_end(leader(pool), reason, now)


## Did this actor win? (team win counts for every member)
func is_winner(a: Actor) -> bool:
	if teams():
		return winner_team >= 0 and winner_team == a.team
	return winner == a


## 0 calm .. 3 final moments
func intensity(actors: Array) -> int:
	if phase != "playing":
		return 1
	var top := top_score(actors)
	var t: float = mode.scoreTarget
	if mode.id == "conquest":
		if time_left < 30 or top >= t - 1:
			return 3
		if time_left < 120 or top >= t - 2:
			return 2
		return 1
	if time_left < 30 or top >= t * 0.93:
		return 3
	if time_left < 120 or top >= t * 0.8:
		return 2
	return 1


## Pick a safe spawn: far from living enemies and out of their sight, near your team's side in team modes
## (near your sectors in Conquest). Picks randomly among the best few. Returns {pos, yaw}.
func pick_spawn(actor: Actor, actors: Array, pool = null) -> Dictionary:
	if pool == null or (pool as Array).is_empty():
		pool = spawn_points
	var enemies := actors.filter(func(a): return a != actor and a.alive and (actor.team < 0 or a.team != actor.team))
	var friends := actors.filter(func(a): return a != actor and a.alive and a.team == actor.team) if actor.team >= 0 else []
	var owned := sectors.filter(func(s): return s.owner == actor.team and actor.team >= 0)
	var scored := []
	for p: Vector3 in pool:
		var min_d := 999.0
		var seen := 0
		var eye := Vector3(p.x, p.y + 1.5, p.z)
		for e in enemies:
			var d: float = e.pos.distance_to(p)
			min_d = minf(min_d, d)
			if d < 40 and phys.los(e.eye_pos(), eye, true):
				seen += 1
		var score := minf(min_d, 40) - seen * 14 + U.rand(0, 6)
		if actor.team >= 0 and sectors.size():
			# conquest: spawn behind your own sectors, never on top of someone else's
			if owned.size():
				var d := 999.0
				for s in owned:
					d = minf(d, Vector2(p.x - s.pos.x, p.z - s.pos.z).length())
				score += 16 - d * 0.3 if d < 20 else -d * 0.25
			for s in sectors:
				if s.owner == actor.team:
					continue
				if Vector2(p.x - s.pos.x, p.z - s.pos.z).length() < s.def.radius + 6:
					score -= 30
		elif actor.team >= 0:
			# Sunrise starts on the bed/desk (north) half, Moonbeam on the dino/garage (south) half
			var own := p.z < 2 if actor.team == 0 else p.z > -2
			score += 14 if own else -10
		if friends.size():
			var fd := 999.0
			for f in friends:
				fd = minf(fd, f.pos.distance_to(p))
			if fd < 18:
				score += 4
		if hill != null:
			var d := Vector2(p.x - hill.pos.x, p.z - hill.pos.z).length()
			if d < hill.site.radius + 7:
				score -= 30
		scored.append({"p": p, "score": score})
	scored.sort_custom(func(a, b): return a.score > b.score)
	var pick: Dictionary = scored[randi() % mini(3, scored.size())]
	var pp: Vector3 = pick.p
	# face the middle of the room (forward = (-sin yaw, 0, -cos yaw))
	var yaw := atan2(pp.x - 2, pp.z - 1)
	return {"pos": Vector3(pp.x, pp.y + 0.05, pp.z), "yaw": yaw}

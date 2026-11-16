class_name Abilities
## The four extra abilities, shared by the player and the bots so both follow the same rules
## (port of src/entities/abilities.ts). Dash lives in Actor.move. deps = {combat, phys, audio}.


static func ability_color(a: Actor) -> String:
	if a.team >= 0:
		return Modes.TEAMS[a.team].color
	return "#ffd23f" if a.is_player else a.def.accent


## Where sounds for this toy come from (null = the listener's own toy).
static func _src(a: Actor):
	return null if a.is_player else a.chest_pos()


## Throw / place the gadget along your aim. Returns false while it's recharging.
static func try_gadget(a: Actor, now: float, deps: Dictionary) -> bool:
	if not a.alive or a.gadget == "" or not Cfg.GADGETS.has(a.gadget) or now < a.gadget_ready_at:
		return false
	var g: Dictionary = Cfg.GADGETS[a.gadget]
	a.gadget_ready_at = now + g.cooldown
	var fwd := a.forward()
	# a little loft for throws; mines are lobbed short and low
	var dir := (fwd + Vector3(0, 0.18 if g.has("mine") else 0.12, 0)).normalized()
	var origin := a.eye_pos() + Vector3(fwd.x, 0, fwd.z).normalized() * 0.35 + Vector3(0, -0.15, 0)
	deps.combat.throw_gadget(a, a.gadget, origin, dir)
	deps.audio.punch(false, _src(a))
	return true


## Melee swing (sword / spear). Returns false while the last swing is still going.
static func try_melee(a: Actor, now: float, deps: Dictionary) -> bool:
	if not a.alive or now < a.melee_ready_at or a.grapple != null or a.zip != null:
		return false
	var md := a.melee_def()
	a.melee_ready_at = now + md.swing
	a.melee_t = md.swing
	var hits: Array = deps.combat.melee(a)
	deps.audio.punch(hits.size() > 0, _src(a))
	return true


## Where a Spring Hook fired along `dir` would latch, or null on a miss.
## Hooking the front of a ledge latches onto its top edge so the pull carries you up and over.
static func grapple_point(a: Actor, dir: Vector3, phys: Phys):
	var eye := a.eye_pos()
	var hit := phys.raycast(eye, dir, Cfg.ABILITIES.grapple.range, true)
	if hit.is_empty() or hit.dist < 2.5:
		return null
	var p: Vector3 = hit.point
	var n: Vector3 = hit.normal
	if n.y < -0.5:
		return p + n * 0.6  # underside of something: hang below it
	if n.y < 0.5:
		# wall or ledge face: look for a floor just above and behind the hit
		var into := -Vector3(n.x, 0, n.z).normalized()
		var probe := p + into * 0.7
		probe.y = p.y + 2.4
		var down := phys.raycast(probe, Vector3.DOWN, 2.6, true)
		if not down.is_empty() and down.normal.y > 0.7 and down.point.y > p.y - 0.2:
			return down.point + Vector3(0, 0.4, 0)
		return p + n * 0.5
	return p + Vector3(0, 0.4, 0)


## Spring Hook. Returns the anchor (Vector3), "miss" or false (cooldown).
static func try_grapple(a: Actor, dir: Vector3, now: float, deps: Dictionary):
	if not a.alive or not a.has("grapple") or now < a.grapple_ready_at or a.grapple != null:
		return false
	var anchor = grapple_point(a, dir, deps.phys)
	if anchor == null:
		a.grapple_ready_at = now + Cfg.ABILITIES.grapple.missCooldown
		deps.audio.grapple(_src(a), false)
		return "miss"
	a.start_grapple(anchor, now)
	deps.audio.grapple(_src(a), true)
	return anchor


## Cloak toggle.
static func try_cloak(a: Actor, now: float, deps: Dictionary) -> bool:
	if not a.alive or (not a.has("cloak") and not a.cloaked):
		return false
	var was := a.cloaked
	if not a.toggle_cloak(now):
		return false
	deps.audio.cloak(not was, _src(a))
	return true


## Mesh Shield: plants a hex-wire wall a step in front of you, facing where you look.
static func try_shield(a: Actor, now: float, deps: Dictionary, yaw = null) -> bool:
	if yaw == null:
		yaw = a.yaw
	if not a.alive or not a.has("shield") or now < a.shield_ready_at:
		return false
	a.shield_ready_at = now + Cfg.ABILITIES.shield.cooldown
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var p := a.pos + fwd * 1.5
	# sit it on whatever floor is there (but never above our own feet + a step)
	var g: float = deps.phys.ray_dist(Vector3(p.x, a.pos.y + 1.2, p.z), Vector3.DOWN, 4, true)
	p.y = a.pos.y if g == INF else minf(a.pos.y + 0.6, a.pos.y + 1.2 - g)
	deps.combat.barriers.deploy(a, p, yaw, ability_color(a), now)
	if deps.combat.on_shield.is_valid():
		deps.combat.on_shield.call(a, yaw)
	deps.audio.shield_up(null if a.is_player else p)
	return true

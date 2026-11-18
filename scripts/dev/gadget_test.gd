class_name GadgetTest
extends RefCounted
## Dev check (--screen=gadgettest --map=toycity): throw each gadget at a dummy in Training and report the
## damage; mines get a dummy walked onto them; one frag at a hard wall panel must break it.

static func run(g) -> void:
	var tree: SceneTree = g.get_tree()
	await tree.create_timer(1.0).timeout
	g.start_match("normal", "training")
	while g.match_.phase != "playing":
		await tree.process_frame
	var pa: Actor = g.player.actor
	var dummy: Actor = null
	for o in g.actors:
		if o != pa:
			dummy = o
			break
	var bad := 0
	var shots := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			shots = arg.trim_prefix("--shots=")
	if shots != "":
		# hold the gadget key: the throw arc and landing ring show
		pa.gadget = "fragGrenade"
		pa.gadget_ready_at = 0
		pa.teleport(Vector3(0, 0.3, 14))
		pa.yaw = 0
		pa.pitch = 0.1
		var key: String = Binds.kb["gadget"][0]
		g.input._down[key] = true
		g.input._pressed[key] = true
		for i in 20:
			g.input._down[key] = true
			await tree.process_frame
		g._shot(shots.path_join("grenade_aim.png"))
		g.input._down.erase(key)
		for i in 5:
			await tree.process_frame
		print("[gadget] aimed throw: arc shown, then thrown on release: %s" % (pa.gadget_ready_at > g.time))
	for gid in Cfg.GADGETS:
		if not Cfg.GADGETS[gid].has("projectile") or gid == "breachDrill":
			continue  # placed gadgets, the infuser and the drill are checked below
		pa.teleport(Vector3(0, 0.3, 10))
		pa.yaw = 0
		pa.pitch = -0.15
		dummy.teleport(Vector3(0, 0.3, 4))
		dummy.yaw = PI  # facing the thrower
		dummy.health = dummy.max_health
		dummy.shield = 0
		dummy.spawn_protect_until = 0
		dummy.flashed_until = 0
		await tree.process_frame
		var hp0: float = dummy.health
		g.combat.throw_gadget(pa, gid, pa.eye_pos(), (Vector3(0, -0.12, -1)).normalized())
		for i in 90:
			if Cfg.GADGETS[gid].has("mine") and i > 60:
				dummy.teleport(Vector3(0, 0.3, 6.5))
			else:
				dummy.teleport(Vector3(0, 0.3, 4))
			await tree.process_frame
		var lost: float = hp0 - dummy.health
		print("[gadget] %s: dummy lost %.0f%s%s" % [gid, lost, " (glitched)" if dummy.glitched_until > g.time else "", " (flashed %.1f s)" % (dummy.flashed_until - g.time) if dummy.flashed_until > g.time else ""])
		if lost <= 0 or (gid == "glitchJug" and dummy.glitched_until <= g.time) or (gid == "flashbang" and dummy.flashed_until <= g.time):
			bad += 1
		dummy.flashed_until = 0
		dummy.alive = true
	# two frags on a hard wall panel
	var D: Destruction = g.destruction
	var panel := -1
	for p in D.pieces:
		if p.cls == "hard" and not p.broken and p.mn.y < 0.5:
			panel = p.id
			break
	if panel >= 0:
		var pc: Dictionary = D.pieces[panel]
		var c: Vector3 = (pc.mn + pc.mx) / 2
		var shell := {"cfg": Cfg.GADGETS.fragGrenade, "color": "#556b2f", "shooter": pa, "power": 1.0}
		g.combat.explode(c + Vector3(0, 0, 0), Vector3.UP, shell, null)
		var after_one: bool = D.is_broken(panel)
		g.combat.explode(c, Vector3.UP, shell, null)
		print("[gadget] frag vs wall: broken after one %s, after two %s" % [after_one, D.is_broken(panel)])
		if not after_one:  # one frag blows a hole in the wall it hits
			bad += 1
	# turret: set it down facing a dummy, it should shoot it
	pa.teleport(Vector3(0, 0.3, 12))
	pa.yaw = 0
	pa.pitch = 0
	dummy.health = dummy.max_health
	dummy.shield = 0
	await tree.process_frame
	g.combat.throw_gadget(pa, "turret", pa.eye_pos(), Vector3(0, 0, -1))
	var thp: float = dummy.health
	for i in 150:
		dummy.teleport(Vector3(0, 0.3, 2))
		await tree.process_frame
	print("[gadget] turret: dummy lost %.0f" % (thp - dummy.health))
	if thp - dummy.health <= 0:
		bad += 1
	# stairs: there's a step to stand on in front of you
	pa.teleport(Vector3(-8, 0.3, 12))
	pa.yaw = 0
	await tree.process_frame
	g.combat.throw_gadget(pa, "stairs", pa.eye_pos(), Vector3(0, 0, -1))
	await tree.process_frame
	await tree.process_frame
	var top: Dictionary = g.phys.raycast(Vector3(-8, 6, 12 - 1.0 - 0.55 * 5.5), Vector3.DOWN, 6, true)
	print("[gadget] stairs: top step at %.2f m" % (top.point.y if not top.is_empty() else -1.0))
	if top.is_empty() or top.point.y < 2.5:
		bad += 1
	# health infuser heals you
	pa.health = 40
	g.combat.throw_gadget(pa, "healthInfuser", pa.eye_pos(), Vector3(0, 0, -1))
	print("[gadget] health infuser: 40 -> %.0f" % pa.health)
	if pa.health <= 40:
		bad += 1
	# breach drill into a full-height hard wall panel: it blows it out and flashes a toy on the far side
	var Dd: Destruction = g.destruction
	var fired := false
	for p in Dd.pieces:
		if fired:
			break
		if p.cls != "hard" or p.broken or p.mn.y > 0.5 or (p.mx - p.mn).y < 1.5 or (p.mx - p.mn).x < 0.8 or (p.mx - p.mn).z > 0.6:
			continue
		var wc: Vector3 = (p.mn + p.mx) / 2
		for side in [1.0, -1.0]:
			var from := wc + Vector3(0, 0, 3.0 * side)
			var h: Dictionary = g.phys.raycast(from, Vector3(0, 0, -side), 3.5)
			if h.is_empty() or Dd.piece_of(h.collider) != p.id:
				continue
			# a toy standing 2.5 m behind the wall, with clear floor under it
			var behind := Vector3(wc.x, p.mn.y + 0.05, wc.z - 2.5 * side)
			var fl: Dictionary = g.phys.raycast(behind + Vector3(0, 1.0, 0), Vector3.DOWN, 1.3, true)
			if fl.is_empty():
				continue
			fired = true
			dummy.health = dummy.max_health
			dummy.flashed_until = 0
			dummy.yaw = 0
			g.combat.throw_gadget(pa, "breachDrill", from, Vector3(0, 0, -side))
			var t0: float = g.time
			while g.time - t0 < 2.6:
				dummy.teleport(Vector3(behind.x, fl.point.y + 0.05, behind.z))
				await tree.process_frame
			var flashed: bool = dummy.flashed_until > g.time
			print("[gadget] breach drill: wall broken %s, toy behind it flashed %s" % [Dd.is_broken(p.id), flashed])
			if not Dd.is_broken(p.id) or not flashed:
				bad += 1
			break
	if not fired:
		print("[gadget] breach drill: no clear shot at a wall panel")
		bad += 1
	print("[gadget] %d failures" % bad)
	tree.quit(bad)

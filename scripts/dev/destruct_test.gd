class_name DestructTest
extends RefCounted
## Dev test (--screen=destruct --map=<id>, works headless): on the current map,
##  - there are hard and soft pieces;
##  - a hard wall that blocks a route breaks under explosions, the route then goes through the hole, and a bot
##    walks through it;
##  - bullets don't hurt hard walls; one pistol shot breaks glass (when the map has glass).
## Prints "[destruct] N failures" and quits.

static func run(g) -> void:
	var tree: SceneTree = g.get_tree()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	await tree.create_timer(1.0).timeout
	g.start_match("normal", "training")
	while g.match_.phase != "playing":
		await tree.process_frame
	var D: Destruction = g.destruction
	var nav: NavGraph = g.nav
	var bad := 0
	var count := {"glass": 0, "soft": 0, "hard": 0}
	for p in D.pieces:
		count[p.cls] += 1
	print("[destruct] pieces: %s" % str(count))
	if count.hard == 0 or count.soft == 0:
		print("[destruct] FAIL: map needs hard and soft pieces")
		bad += 1
	# nothing the game depends on may stand on a breakable piece: objectives, jump pads, zip ends
	var spots := []
	for s in Modes.HILL_SITES:
		spots.append([s.name, s.pos])
	for pd in g.map.pads:
		spots.append(["pad", pd.pos])
		spots.append(["pad landing", pd.to])
	for z in g.map.zips:
		spots.append(["zip end", z.a])
		spots.append(["zip end", z.b])
	for sp in spots:
		var h: Dictionary = g.phys.raycast(sp[1] + Vector3(0, 2.5, 0), Vector3.DOWN, 5.0)
		if not h.is_empty() and D.piece_of(h.collider) >= 0:
			print("[destruct] FAIL: %s at %s stands on breakable piece %d" % [sp[0], sp[1], D.piece_of(h.collider)])
			bad += 1

	# a link blocked only by one hard piece, between two open nodes that can reach each other the long way
	# round: take the one with the longest detour (at least 5 m)
	var pick := {}
	var tried := 0
	for n in nav.nodes:
		if tried > 400:
			break
		for l in n.links:
			var bl = l.get("blockers")
			if bl == null or bl.is_empty() or bl.size() > 2:
				continue
			var all_hard := true
			for b in bl:
				all_hard = all_hard and D.pieces[b].cls == "hard"
			if not all_hard:
				continue
			if not nav.node_open(n.id) or not nav.node_open(l.to) or l.pad >= 0 or l.zip >= 0:
				continue
			# walking through a wall on one level (not a drop out of a window)
			if absf((n.pos as Vector3).y - (nav.nodes[l.to].pos as Vector3).y) > 0.6:
				continue
			tried += 1
			var before := _length(nav, nav.path(n.id, l.to))
			if before > 5.0 and before < INF and before > pick.get("before", 0.0):
				pick = {"a": n.id, "b": l.to, "piece": bl[0], "all": Array(bl), "before": before}
	if pick.is_empty():
		print("[destruct] FAIL: no hard wall blocks a route")
		bad += 1
	else:
		var pc: Dictionary = D.pieces[pick.piece]
		var center: Vector3 = (pc.mn + pc.mx) / 2
		var a_pos: Vector3 = nav.nodes[pick.a].pos
		var normal := Vector3(a_pos.x - center.x, 0, a_pos.z - center.z).normalized()
		var shooter: Actor = g.player.actor
		var shell := {"cfg": Cfg.WEAPONS.crayonCannon, "color": "#e63946", "shooter": shooter, "power": 1.0}
		if shots != "":
			# stand back on the open side, crack the panel next to it, look at both
			var pa0: Actor = g.player.actor
			# back off as far as the open space on the near side allows (up to 7 m)
			var from := Vector3(center.x, a_pos.y + 1.4, center.z) + normal * 0.3
			var room: float = g.phys.ray_dist(from, normal, 7.5)
			var back := 7.0 if room == INF else maxf(1.5, room - 0.8)
			var eye_at := Vector3(center.x, a_pos.y, center.z) + normal * back
			pa0.teleport(eye_at)
			var look := (center - pa0.eye_pos()).normalized()
			pa0.yaw = atan2(-look.x, -look.z)
			pa0.pitch = asin(look.y)
			for p2 in D.pieces:
				if p2.id != pick.piece and p2.group == pc.group and not p2.broken and (p2.mn as Vector3).distance_to(pc.mn) < 2.5:
					D.damage(p2.id, 450, "blast", (p2.mn + p2.mx) / 2 + normal * 0.2, normal)
					break
			for i in 20:
				await tree.process_frame
			g._shot(shots.path_join("destruct_cracked.png"))
		# an arrow stuck in the wall has to go when the wall does
		var wall_box := AABB(pc.mn, pc.mx - pc.mn).grow(0.6)
		g.combat._stick_arrow(Vector3(center.x, a_pos.y + 1.2, center.z) + normal * 0.3, -normal, "#ffffff")
		var blasts := 0
		for pid in pick.all:
			var pcc: Dictionary = D.pieces[pid]
			var cc: Vector3 = (pcc.mn + pcc.mx) / 2
			var k := 0
			while not D.is_broken(pid) and k < 6:
				k += 1
				g.combat.explode(Vector3(cc.x, a_pos.y + 1.0, cc.z) + normal * 0.25, normal, shell, null)
				await tree.process_frame
			blasts = maxi(blasts, k)
		print("[destruct] hard wall broke after %d crayon blasts" % blasts)
		if shots != "":
			for i in 8:
				await tree.process_frame
			g._shot(shots.path_join("destruct_hole.png"))
			for i in 90:
				await tree.process_frame
			g._shot(shots.path_join("destruct_hole_settled.png"))
		for pid in pick.all:
			if not D.is_broken(pid):
				print("[destruct] FAIL: wall still standing after 6 blasts")
				bad += 1
		if g.combat.stuck_in(wall_box) > 0:
			print("[destruct] FAIL: an arrow is left hanging where the wall was")
			bad += 1
		var after := _length(nav, nav.path(pick.a, pick.b))
		print("[destruct] route %.1f m -> %.1f m" % [pick.before, after])
		if after <= 0.0 or after > 4.0:
			print("[destruct] FAIL: route didn't open through the hole")
			bad += 1
		# a bot walks through
		var bot = null
		for b in g.bots:
			if b.actor.alive:
				bot = b
				break
		if bot:
			# aim 3 m past the wall so "arrived" can't trigger before the bot is through
			var deep := nav.nearest(Vector3(center.x, a_pos.y, center.z) - normal * 3.0, false, 2.5)
			var goal: Vector3 = nav.nodes[deep if deep >= 0 else pick.b].pos
			bot.actor.teleport(a_pos)
			# a plain walk: no target to chase, no re-thinking
			bot.state = "patrol"
			bot.target = null
			bot._think_at = 99.0
			bot._has_goal = false
			bot._set_goal(goal)
			var t0: float = g.time
			var crossed := false
			while g.time - t0 < 6.0:
				bot._think_at = 99.0
				bot.state = "patrol"
				bot.target = null
				# through the hole = on the far side of the wall's plane
				if (bot.actor.pos - center).dot(normal) < -0.3:
					crossed = true
					break
				await tree.process_frame
			print("[destruct] bot crossed the hole: %s" % crossed)
			if not crossed:
				bad += 1

	# bullets vs hard walls, pistol vs glass
	var pa: Actor = g.player.actor
	var hard_id := -1
	var glass_id := -1
	for p in D.pieces:
		if p.broken:
			continue
		if p.cls == "hard" and hard_id < 0 and p.mn.y < 1.0:
			hard_id = p.id
		if p.cls == "glass" and glass_id < 0:
			glass_id = p.id
	if hard_id >= 0:
		var hp_before: float = D.pieces[hard_id].hp
		await _shoot_at(g, pa, hard_id, "brickbreaker")
		if D.pieces[hard_id].hp != hp_before or D.is_broken(hard_id):
			print("[destruct] FAIL: a bullet damaged a hard wall")
			bad += 1
	if glass_id >= 0:
		# the first pane with a clear line of fire
		var shot_id := -1
		for p in D.pieces:
			if p.cls == "glass" and not p.broken and await _shoot_at(g, pa, p.id, "plasti9"):
				shot_id = p.id
				break
		print("[destruct] glass broke on one pistol shot: %s" % (shot_id >= 0 and D.is_broken(shot_id)))
		if shot_id < 0 or not D.is_broken(shot_id):
			bad += 1
	print("[destruct] %d failures" % bad)
	tree.quit(bad)


static func _length(nav: NavGraph, route: Array) -> float:
	if route.is_empty():
		return INF
	var d := 0.0
	for i in range(1, route.size()):
		d += (nav.nodes[route[i - 1]].pos as Vector3).distance_to(nav.nodes[route[i]].pos)
	return d


## Stand 3 m in front of the piece (on the side with open air) and fire one shot at its middle.
static func _shoot_at(g, pa: Actor, id: int, wid: String) -> bool:
	var D: Destruction = g.destruction
	var p: Dictionary = D.pieces[id]
	var c: Vector3 = (p.mn + p.mx) / 2
	var ext: Vector3 = p.mx - p.mn
	var thin := Vector3.RIGHT if ext.x < ext.z else Vector3.BACK
	for side in [thin, -thin]:
		var eye: Vector3 = c + side * 3.0
		var h: Dictionary = g.phys.raycast(eye, -side, 3.5)
		if h.is_empty() or D.piece_of(h.collider) != id:
			continue
		pa.give_weapon(wid, 0)
		pa.slot = 0
		await g.get_tree().process_frame
		g.combat.fire(pa, pa.weapon(), eye, -side, eye, 0.0)
		await g.get_tree().process_frame
		return true
	return false

class_name GunTest
extends RefCounted
## Dev check (--screen=guntest[:<weaponId>] [--shots=dir]): take a blaster in Training, fire a few shots and
## reload from empty, saving pictures at each reload stage (casings flying, mag out, fresh mag going in, rack).
## The Sizzler is also fired at a dummy up close to check the 50 + 6 x 3 burn.

static func run(g, only := "") -> void:
	var tree: SceneTree = g.get_tree()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	await tree.create_timer(1.0).timeout
	var bad := 0
	var ids: Array = [only] if only != "" else ["plasti9", "foamFury", "brickbreaker", "rapidRascal", "jackBlaster", "sizzler", "tumbleweed", "popcornPopper", "walloper", "bubbleBlaster", "thunderspring", "crayonCannon"]
	for wid in ids:
		g.start_match("normal", "training")
		g.training_gun = wid
		while g.match_.phase != "playing":
			await tree.process_frame
		var pa: Actor = g.player.actor
		pa.health = 0
		g._respawn(pa)
		pa.teleport(Vector3(0, 0.3, 14))
		pa.yaw = 0
		pa.pitch = 0
		for o in g.actors:
			if o != pa:
				o.teleport(Vector3(30, 0.3, 30))
		for i in 30:
			await tree.process_frame
		var ws: WeaponState = pa.weapon()
		if shots != "":
			g._shot(shots.path_join("gun_%s_idle.png" % wid))
		# fire until empty (casings), photographing one just after a shot
		var fire_key: String = Binds.kb["fire"][0]
		var n := 0
		while ws.mag > 0 and n < 400:
			g.input._pressed[fire_key] = true
			g.input._down[fire_key] = true
			await tree.process_frame
			g.input._down.erase(fire_key)
			n += 1
			if n == 3 and shots != "":
				g._shot(shots.path_join("gun_%s_fire.png" % wid))
		for i in 10:
			await tree.process_frame
		print("[gun] %s: emptied in %d frames, mag %d, reserve %d" % [wid, n, ws.mag, ws.reserve])
		# reload from empty and photograph the stages
		g.input._pressed[Binds.kb["reload"][0]] = true
		await tree.process_frame
		var stages := [0.08, 0.25, 0.45, 0.6, 0.78, 0.95] if not ws.cfg.has("reloadPerShell") else [0.2, 0.5, 0.8]
		var si := 0
		var t0: float = g.time
		var frames := 0
		while ws.reloading and frames < 1500:
			await tree.process_frame
			frames += 1
			var f: float = ws.reload_progress() if not ws.cfg.has("reloadPerShell") else (g.time - t0) / (0.25 + float(ws.cfg.reloadPerShell) * ceilf(float(ws.cfg.magSize) / int(ws.cfg.get("shellRounds", 1))) + 0.3)
			if si < stages.size() and f >= stages[si]:
				if shots != "":
					g._shot(shots.path_join("gun_%s_reload_%d.png" % [wid, si]))
				si += 1
		print("[gun] %s: reloaded to %d in %.2f s" % [wid, ws.mag, g.time - t0])
		if ws.mag != ws.cfg.magSize:
			bad += 1
	# Tumbleweed: one pull is a 3-bullet burst for 90, and a reload goes 3 / 6 / 9
	if only == "" or only == "tumbleweed":
		g.start_match("normal", "training")
		g.training_gun = "tumbleweed"
		while g.match_.phase != "playing":
			await tree.process_frame
		var tp: Actor = g.player.actor
		tp.health = 0
		g._respawn(tp)
		var td: Actor = null
		for o in g.actors:
			if o != tp:
				td = o
				break
		tp.teleport(Vector3(0, 0.3, 10))
		tp.yaw = 0
		tp.pitch = 0
		for i in 80:
			td.teleport(Vector3(0, 0.3, 6))
			td.spawn_protect_until = 0
			await tree.process_frame
		td.shield = 0
		td.health = td.max_health
		var tws: WeaponState = tp.weapon()
		tp.pitch = atan2(td.chest_pos().y - tp.eye_pos().y, 4.0)
		await tree.process_frame
		var hp1: float = td.health
		# a quick tap (about 0.1 s): the burst must finish on its own
		g.input._pressed[Binds.kb["fire"][0]] = true
		for i in 6:
			g.input._down[Binds.kb["fire"][0]] = true
			await tree.process_frame
		g.input._down.erase(Binds.kb["fire"][0])
		for i in 30:
			td.teleport(Vector3(0, 0.3, 6))
			await tree.process_frame
		print("[gun] tumbleweed burst: mag %d/9, dummy lost %.0f" % [tws.mag, hp1 - td.health])
		if tws.mag != 6 or hp1 - td.health < 80:
			bad += 1
		tws.mag = 0
		g.input._pressed[Binds.kb["reload"][0]] = true
		var seen: Array = []
		var fr := 0
		while (tws.reloading or fr < 3) and fr < 900:
			await tree.process_frame
			fr += 1
			if seen.is_empty() or seen[seen.size() - 1] != int(tws.mag):
				seen.append(int(tws.mag))
		print("[gun] tumbleweed reload counts: %s" % str(seen))
		if seen != [0, 3, 6, 9]:
			bad += 1
	# Sizzler: 50 up close, then burns 6 x 3
	if only == "" or only == "sizzler":
		g.start_match("normal", "training")
		g.training_gun = "sizzler"
		while g.match_.phase != "playing":
			await tree.process_frame
		var pa: Actor = g.player.actor
		pa.health = 0
		g._respawn(pa)
		var dummy: Actor = null
		for o in g.actors:
			if o != pa:
				dummy = o
				break
		pa.teleport(Vector3(0, 0.3, 10))
		pa.yaw = 0
		pa.pitch = 0
		for i in 20:
			dummy.teleport(Vector3(0, 0.3, 8.6))
			dummy.spawn_protect_until = 0
			await tree.process_frame
		dummy.shield = 0
		dummy.health = dummy.max_health
		var hp0: float = dummy.health
		var ws: WeaponState = pa.weapon()
		g.combat.fire(pa, ws, pa.eye_pos(), (dummy.chest_pos() - pa.eye_pos()).normalized(), pa.eye_pos(), 0.0)
		await tree.process_frame
		var hit := hp0 - dummy.health
		var t0: float = g.time
		while g.time - t0 < 3.4:
			dummy.teleport(Vector3(0, 0.3, 8.6))
			await tree.process_frame
		var total := hp0 - dummy.health
		print("[gun] sizzler at 1.4 m: shot %.0f, after the burn %.0f (burning flag cleared %s)" % [hit, total, dummy.burning_until <= g.time])
		if absf(hit - 50) > 0.5 or absf(total - 68) > 0.5:
			bad += 1
		# far away: no burn
		dummy.health = dummy.max_health
		for i in 5:
			dummy.teleport(Vector3(0, 0.3, 0))
			await tree.process_frame
		hp0 = dummy.health
		g.combat.fire(pa, ws, pa.eye_pos(), (dummy.chest_pos() - pa.eye_pos()).normalized(), pa.eye_pos(), 0.0)
		t0 = g.time
		var first := -1.0
		while g.time - t0 < 3.4:
			dummy.teleport(Vector3(0, 0.3, 0))
			await tree.process_frame
			if first < 0:
				first = hp0 - dummy.health
		print("[gun] sizzler at 10 m: shot %.0f, total %.0f (no burn)" % [first, hp0 - dummy.health])
		if absf((hp0 - dummy.health) - first) > 0.5:
			bad += 1
	print("[gun] %d failures" % bad)
	tree.quit(bad)

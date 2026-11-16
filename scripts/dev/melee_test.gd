class_name MeleeTest
extends RefCounted
## Dev check (--screen=meleetest [--shots=dir]): take the sword (then the spear) as your weapon in Training,
## swing at a dummy, report the swing and the damage, and (with --shots) save pictures held and mid-swing.

static func run(g) -> void:
	var tree: SceneTree = g.get_tree()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	await tree.create_timer(1.0).timeout
	for kind in ["sword", "spear"]:
		g.start_match("normal", "training")
		g.training_gun = kind
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
		pa.teleport(Vector3(0, 0.3, 8))
		pa.yaw = 0
		pa.pitch = 0
		for i in 15:
			dummy.teleport(Vector3(0, 0.3, 6))
			dummy.spawn_protect_until = 0
			await tree.process_frame
		if shots != "":
			g._shot(shots.path_join("melee_held_%s.png" % kind))
		var hp0: float = dummy.health + dummy.shield
		g.input._pressed[Binds.kb["fire"][0]] = true
		var swung := false
		var frames := 0
		while frames < 40:
			await tree.process_frame
			frames += 1
			swung = swung or pa.melee_t > 0
			if frames == 3 and shots != "":
				g._shot(shots.path_join("melee_swing_%s.png" % kind))
		print("[melee] %s: class %s, melee weapon %s, blaster %s, swung %s, dummy lost %.0f" % [kind, pa.cls, pa.melee_held, pa.weapon() != null, swung, hp0 - (dummy.health + dummy.shield)])
	tree.quit()

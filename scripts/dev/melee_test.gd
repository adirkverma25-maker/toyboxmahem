class_name MeleeTest
extends RefCounted
## Dev check (--screen=meleetest [--shots=dir]): as a Light then a Medium, stand next to a dummy, press melee,
## and report the swing timer, the dummy's damage and (with --shots) a picture mid-swing.

static func run(g) -> void:
	var tree: SceneTree = g.get_tree()
	var shots := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
	await tree.create_timer(1.0).timeout
	for c in ["light", "medium"]:
		g.training_gun = "foamFury" if c == "light" else "jackBlaster"
		g.start_match("normal", "training")
		while g.match_.phase != "playing":
			await tree.process_frame
		var pa: Actor = g.player.actor
		var dummy: Actor = null
		for o in g.actors:
			if o != pa:
				dummy = o
				break
		pa.teleport(Vector3(0, 0.3, 8))
		pa.yaw = 0
		pa.pitch = 0
		dummy.teleport(Vector3(0, 0.3, 6))
		dummy.spawn_protect_until = 0
		pa.melee_ready_at = 0
		for i in 10:
			dummy.teleport(Vector3(0, 0.3, 6))
			await tree.process_frame
		var hp0: float = dummy.health + dummy.shield
		g.input._pressed[Binds.kb["melee"][0]] = true
		var swung := false
		for i in 8:
			await tree.process_frame
			swung = swung or pa.melee_t > 0
			if i == 4 and shots != "":
				g._shot(shots.path_join("melee_%s.png" % c))
		# take it out with weapon2 and look at it held
		g.input._pressed[Binds.kb["weapon2"][0]] = true
		for i in 30:
			await tree.process_frame
		if shots != "":
			g._shot(shots.path_join("melee_held_%s.png" % c))
		print("[melee] %s: held %s" % [c, pa.melee_held])
		print("[melee] %s: class %s, key %s, swung %s, vm visible %s, dummy lost %.0f" % [c, pa.cls, Binds.kb["melee"][0], swung, g.vm.melee_node.visible if g.vm else false, hp0 - (dummy.health + dummy.shield)])
	tree.quit()

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
		pa.teleport(Vector3(0, 0.3, 10))
		pa.yaw = 0
		pa.pitch = -0.15
		dummy.teleport(Vector3(0, 0.3, 4))
		dummy.health = dummy.max_health
		dummy.shield = 0
		dummy.spawn_protect_until = 0
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
		print("[gadget] %s: dummy lost %.0f" % [gid, lost])
		if lost <= 0:
			bad += 1
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
	print("[gadget] %d failures" % bad)
	tree.quit(bad)

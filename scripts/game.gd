class_name Game
extends Node
## Owns every system and runs the main loop (port of src/core/Game.ts). Online play: see scripts/net/.

const LoadingScreen := preload("res://scripts/ui/loading.gd")

static var _switch_done := false  # dev test: survives the scene reload
var state := "menu"
var training_gun := ""  # Training: blaster picked from the pause menu (this session only; its class comes with it)  # menu | playing | paused | results
var r := Renderer.new()
var phys: Phys
var arena: Dictionary
var ambient
var map: Dictionary
var nav: NavGraph
var fx: Effects
var events := Emitter.new()
var combat: Combat
## breakable walls / cover and the chunks they leave
var destruction: Destruction
var debris: Debris
var pickups: Pickups
var match_: Match
var hud: HUD
var menus: Menus
var input := GInput.new()
var vm: Viewmodel
var audio := AudioEngine.new()
var player: Player = null
var actors: Array = []
var bots: Array = []
var bot_by_actor := {}
var spawn_points: Array = []
var shelf_spawns: Array = []
var shelf_starters := {}
var time := 0.0
var time_scale := 1.0
var slowmo_t := 0.0
var menu_t := 0.0
var dash_from := {}
var last_zone := ""
var match_seconds := 0.0
var difficulty := "normal"
var mode := "ffa"
var hill_zone: Zones.HillZone
var sector_zones: Zones.SectorZones
var traversal: Traversal
var ropes: Ropes
var assignment := {}
var director_at := 0.0
var last_hill_note := -10.0
var move_events := {}
var pad_nav: PadNav
var beacons := {}
var ui_layer := CanvasLayer.new()
var loading
var ready_ok := false
var results_at := -1.0
## online: the connection (the Net autoload, outside the scene so it survives map reloads)
var net = Net
## online: set while hosting (this game runs the match for everyone)
var host: HostSession = null
## online: set while playing in someone else's match
var guest: GuestSession = null
## online: toys driven from the network (host: guests' toys; guest: everyone but you) -> Roster.new_remote
var remotes := {}
## online: weapons in remote toys' hands
var gear := Roster.Gear.new()


func _ready() -> void:
	name = "Game"
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(input)
	r.attach(self)
	r.world.add_child(audio)
	ui_layer.layer = 2
	add_child(ui_layer)
	loading = LoadingScreen.new()
	ui_layer.add_child(loading)
	_init_game()


func _step(text: String, frac: float) -> void:
	loading.set_step(text, frac)
	await get_tree().process_frame
	await get_tree().process_frame


func _init_game() -> void:
	await _step("Unboxing the renderer", 0.05)
	phys = Phys.new()
	phys.name = "Physics"
	r.world.add_child(phys)
	await _step("Loading physics", 0.12)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map=") and Net.status == "offline":
			Settings.data.map = a.trim_prefix("--map=")
		if a.begins_with("--quality="):
			Settings.data.quality = a.trim_prefix("--quality=")
	map = Maps.selected()
	Modes.use_map_sites(map.hillSites, map.sectors, map.homes)
	await _step(map.loading, 0.25)
	var arena_root := Node3D.new()
	arena_root.name = "Arena"
	r.world.add_child(arena_root)
	destruction = Destruction.new(phys)
	r.world.add_child(destruction)
	phys.set_meta("destruction", destruction)
	arena = map.build.call(arena_root, phys)
	phys.remove_meta("destruction")
	destruction.build()
	r.set_sky(map.sky)
	r.sun = arena.sun
	r.point_lights = arena.point_lights
	await phys.refresh()
	# pick-ups are dropped onto whatever surface is under them
	var spots := []
	for pr in arena.pickup_probes:
		var d := phys.ray_dist(Vector3(pr[1], pr[3], pr[2]), Vector3.DOWN, pr[3] + 2, true)
		spots.append({"kind": pr[0], "pos": Vector3(pr[1], 0.0 if d == INF else pr[3] - d, pr[2])})
	await _step("Teaching toys to walk", 0.5)
	nav = NavGraph.new(phys)
	nav.destruction = destruction
	var connectors := []
	for pd in map.pads:
		connectors.append([pd.pos, pd.to, false])
	for z in map.zips:
		connectors.append([z.a, z.b, true])
	await nav.build_async(arena.bounds, "%s-%d" % [map.id, hash("%s|%d|%d" % [str(connectors), phys.static_fingerprint(), destruction.fingerprint()])], 1.6, connectors)
	var hy: float = map.highY
	spawn_points = nav.spawn_points(22, func(n): return n.open >= 6 and n.pos.y < hy - 1)
	shelf_spawns = nav.spawn_points(10, func(n): return n.pos.y > hy and n.open >= 3)
	await _step("Filling the toy box", 0.65)
	fx = Effects.new()
	r.world.add_child(fx)
	fx.set_floor_probe(func(p: Vector3) -> float:
		var d := phys.ray_dist(p, Vector3.DOWN, 40, true)
		return 0.0 if d == INF else p.y - d)
	ambient = map.ambient.call(arena, phys, fx, audio)
	r.world.add_child(ambient)
	traversal = Traversal.new(phys, audio, fx, map.pads, map.zips)
	r.world.add_child(traversal)
	await phys.refresh()
	var links := traversal.link_nav(nav)
	if links < map.pads.size() + map.zips.size():
		push_warning("[nav] only %d/%d jump pads + ziplines linked" % [links, map.pads.size() + map.zips.size()])
	combat = Combat.new(phys, fx, audio, events, func(): return actors, arena.loose_bricks)
	r.world.add_child(combat)
	combat.destruction = destruction
	debris = Debris.new()
	r.world.add_child(debris)
	destruction.fx_hooks(debris, fx, audio)
	destruction.on_break = _on_piece_broken
	destruction.on_crack = func(id: int) -> void:
		if host:
			host.piece_cracked(id)
	pickups = Pickups.new(spots, fx, audio, events)
	r.world.add_child(pickups)
	match_ = Match.new(phys, spawn_points)
	hill_zone = Zones.HillZone.new()
	r.world.add_child(hill_zone)
	sector_zones = Zones.SectorZones.new()
	r.world.add_child(sector_zones)
	ropes = Ropes.new()
	r.world.add_child(ropes)
	vm = Viewmodel.new()
	r.vm_root.add_child(vm)
	audio.init()
	audio.occlusion = func(p: Vector3) -> bool: return not phys.los(r.camera.global_position, p, true)
	hud = HUD.new()
	hud.show_hud(false)
	ui_layer.add_child(hud)
	menus = Menus.new({
		"start": func(d: String, m: String): start_match(d, m),
		"resume": resume,
		"quit": quit_to_menu,
		"play_again": func(): start_match(difficulty, mode),
		"settings_changed": func(k: String): apply_settings(k),
		"load_map": func(_id: String, _m: String): _reload_map(),
		"training_try": func(wid: String): training_try(wid),
		"current_weapon": func() -> String: return player.actor.weapon().id if player and player.actor.weapon() else "",
		"host_room": func(m: String, bots: int): host_room(Net.new_code(), m, bots),
		"join_room": func(code: String): join_room(code),
		"leave_online": func(): leave_online(),
		"lobby_set": func(p: Dictionary): if host: host.set_lobby(p),
		"lobby_map": func(id: String): if host: load_map_online(id),
		"lobby_start": func(): if host: host.start(),
		"back_to_lobby": func(): back_to_lobby(),
		"online_role": func() -> String: return online_role(),
		"lobby_info": func() -> Dictionary: return host.lobby if host else (guest.lobby if guest else {}),
		"lobby_loading": func() -> int: return host.loading_count() if host else 0,
	}, audio, input)
	ui_layer.add_child(menus)
	ui_layer.move_child(loading, -1)
	_register_events()
	for k in Settings.data:
		apply_settings(k)
	pad_nav = PadNav.new(input, menus, {"back": func(): return menus.pad_back(), "start": func(): return menus.pad_start()})
	input.on_device_change = func(pad: bool) -> void:
		if not pad and state == "playing" and not input.locked:
			input.request_lock()
	Accounts.switched.connect(func(_a):
		for k in Settings.data:
			apply_settings(k))
	input.on_lock_change = func(locked: bool) -> void:
		if not locked and state == "playing" and match_.phase != "ended":
			pause()
	await _step("Warming up shaders", 0.82)
	_menu_camera(0)
	r.set_menu_blur(true)
	r.set_viewmodel_visible(false)
	await _step("Ready", 1.0)
	loading.finish()
	menus.open_after_load()
	_resume_online()
	if audio.music:
		audio.music.start()
	ready_ok = true
	_autotest()


func _shot(path: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("[autotest] saved ", path)


## Test hook: `Godot -- --autotest=<mode> [--seconds=N]` starts a match on its own, lets the bots play,
## prints a report and quits.
func _autotest() -> void:
	var m := ""
	var secs := 40.0
	var shots := ""
	var screen := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autotest="):
			m = a.trim_prefix("--autotest=")
		elif a.begins_with("--seconds="):
			secs = float(a.trim_prefix("--seconds="))
		elif a.begins_with("--shots="):
			shots = a.trim_prefix("--shots=")
		elif a.begins_with("--screen="):
			screen = a.trim_prefix("--screen=")
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--online="):
			_online_test(a.trim_prefix("--online="), m if m != "" else "ffa", secs, shots)
			return
	if screen == "meleetest":
		await MeleeTest.run(self)
		return
	if screen == "destruct":
		await DestructTest.run(self)
		return
	if screen == "snipertest":
		# fire each sniper at a full-health, full-shield dummy 40 m away: body and head
		await get_tree().create_timer(1.0).timeout
		start_match("normal", "training")
		while match_.phase != "playing":
			await get_tree().process_frame
		var pa := player.actor
		var target: Actor = null
		for o in actors:
			if o != pa:
				target = o
				break
		for wid in ["thunderspring"]:
			for part in ["body", "head"]:
				pa.teleport(Vector3(-20, 0, -26.4))
				pa.give_weapon(wid, 0)
				pa.slot = 0
				target.spawn(Vector3(20, 0, -26.4), 0, time)
				target.spawn_protect_until = 0
				target.health = target.max_health
				target.shield = Cfg.COMBAT.maxShield
				await get_tree().process_frame
				var eye := pa.eye_pos()
				var aim: Vector3 = target.head_pos() if part == "head" else target.chest_pos()
				var d := (aim - eye).normalized()
				combat.fire(pa, pa.weapon(), eye, d, eye, 0.0)
				var t0 := time
				while time - t0 < 0.6:
					target.teleport(Vector3(20, 0, -26.4))
					await get_tree().process_frame
				print("[sniper] %s %s shot at 40 m: %s (health %.0f, shield %.0f)" % [wid, part, "POPPED" if not target.alive else "survived", target.health, target.shield])
		get_tree().quit()
		return
	if screen == "interiors":
		# every Toy City building: walkable floor on each storey, and a walking route street -> door -> stairs -> roof
		await get_tree().create_timer(1.0).timeout
		start_match("normal", "training")
		while match_.phase != "playing":
			await get_tree().process_frame
		var bad := 0
		var shot_i := 0
		for key in ArenaToyCity.BUILDINGS:
			var d: Dictionary = ArenaToyCity.BUILDINGS[key]
			var levels := [0.0, 3.6]
			var n_up := maxi(1, floori((d.roof - 3.6) / 3.0))
			for k in range(1, n_up):
				levels.append(3.6 + k * (d.roof - 3.6) / n_up)
			levels.append(d.roof)
			var counts := []
			for y in levels:
				var c := 0
				for n in nav.nodes:
					var np: Vector3 = n.pos
					if np.x > d.x0 + 0.3 and np.x < d.x1 - 0.3 and np.z > d.z0 + 0.3 and np.z < d.z1 - 0.3 and absf(np.y - y) < 0.3:
						c += 1
				counts.append(c)
			# route: outside the first door -> roof, walking only
			var dr: Array = d.doors[0]
			var gx0: float = d.x0 + (d.depth if d.arcade == "w" else 0.0)
			var gx1: float = d.x1 - (d.depth if d.arcade == "e" else 0.0)
			var gz0: float = d.z0 + (d.depth if d.arcade == "n" else 0.0)
			var gz1: float = d.z1 - (d.depth if d.arcade == "s" else 0.0)
			var outside: Vector3
			match dr[0]:
				"n": outside = Vector3(dr[1], 0, gz0 - 2.0)
				"s": outside = Vector3(dr[1], 0, gz1 + 2.0)
				"w": outside = Vector3(gx0 - 2.0, 0, dr[1])
				"e": outside = Vector3(gx1 + 2.0, 0, dr[1])
			var start := nav.nearest(outside, false, 3)
			var roof_id := -1
			for n in nav.nodes:
				var np2: Vector3 = n.pos
				if absf(np2.y - d.roof) < 0.3 and np2.x > d.x0 + 1 and np2.x < d.x1 - 1 and np2.z > d.z0 + 1 and np2.z < d.z1 - 1:
					roof_id = n.id
					break
			# walking only: hide the special links while searching
			var saved := {}
			for n in nav.nodes:
				var keep := []
				for l in n.links:
					if l.pad >= 0 or l.zip >= 0:
						saved[n.id] = saved.get(n.id, []) + [l]
					else:
						keep.append(l)
				n.links = keep
			var route := nav.path(start, roof_id) if start >= 0 and roof_id >= 0 else []
			# which storeys can be reached on foot from the street (diagnostics)
			var seen := {start: true}
			var q := [start]
			while q.size():
				var cur: int = q.pop_back()
				for l in nav.nodes[cur].links:
					if not seen.has(l.to):
						seen[l.to] = true
						q.append(l.to)
			var reach := []
			for y in levels:
				var c2 := 0
				for id in seen:
					var np3: Vector3 = nav.nodes[id].pos
					if np3.x > d.x0 + 0.3 and np3.x < d.x1 - 0.3 and np3.z > d.z0 + 0.3 and np3.z < d.z1 - 0.3 and absf(np3.y - y) < 0.3:
						c2 += 1
				reach.append(c2)
			print("[interiors] %s reachable per level %s" % [key, reach])
			for id in saved:
				nav.nodes[id].links += saved[id]
			var ok: bool = route.size() > 0 and not counts.has(0)
			if not ok:
				bad += 1
			print("[interiors] %s %s: nodes per level %s, walking route street->roof %s" % [key, "ok" if ok else "FAIL", counts, ("%d steps" % route.size()) if route.size() else "NONE"])
			if shots != "":
				# stand inside on the ground floor and on the top storey, looking along the building
				for li in [0, levels.size() - 2]:
					var y: float = levels[li]
					var cx: float = (gx0 + gx1) / 2 if li == 0 else (d.x0 + d.x1) / 2
					var cz: float = (gz0 + gz1) / 2 if li == 0 else (d.z0 + d.z1) / 2
					var n_id := nav.nearest(Vector3(cx, y, cz), false, 6)
					if n_id >= 0:
						player.actor.teleport(nav.nodes[n_id].pos + Vector3(0, 0.05, 0))
						player.actor.yaw = PI * 0.25 + shot_i
						player.actor.pitch = -0.05
						for i in 10:
							await get_tree().process_frame
						_shot(shots + "/inside_%s_%d.png" % [key, li])
					shot_i += 1
		print("[interiors] %d failures" % bad)
		get_tree().quit()
		return
	if screen == "traversal":
		# ride every jump pad and zipline with the player and report where they ended up
		await get_tree().create_timer(1.0).timeout
		start_match("normal", "training")
		while match_.phase != "playing":
			await get_tree().process_frame
		var pa := player.actor
		var bad := 0
		for i in traversal.pads.size():
			var pd: Dictionary = traversal.pads[i]
			pa.teleport(pd.pos + Vector3(0, 0.05, 0))
			pa.vel = Vector3.ZERO
			var t0 := time
			var took_off := false
			while time - t0 < 6:
				await get_tree().process_frame
				if pa.launched:
					took_off = true
				elif took_off and pa.grounded:
					break
			var miss: float = Vector2(pa.pos.x - pd.to.x, pa.pos.z - pd.to.z).length()
			var dy: float = pa.pos.y - pd.to.y
			var ok := took_off and miss < 2.0 and absf(dy) < 0.8
			if not ok:
				bad += 1
			print("[traversal] pad %d %s: landed %s target %s (off %.2f m, dy %.2f)%s" % [i, "ok" if ok else "FAIL", pa.pos, pd.to, miss, dy, "" if took_off else " NO LAUNCH"])
			if shots != "" and i == 0:
				_shot(shots + "/pad0.png")
		for i in traversal.zips.size():
			for dir in [1, -1]:
				var z: Dictionary = traversal.zips[i]
				var from: Vector3 = z.a if dir == 1 else z.b
				var to: Vector3 = z.b if dir == 1 else z.a
				pa.teleport(from + Vector3(0, -1.0, 0))
				pa.vel = Vector3.ZERO
				traversal.attach_from(pa, i, from, time)
				var t0 := time
				var mid_shot := false
				while pa.zip != null and time - t0 < 12:
					await get_tree().process_frame
					if shots != "" and not mid_shot and i == 0 and dir == 1 and time - t0 > 1.0:
						mid_shot = true
						_shot(shots + "/zip0.png")
				# let them land
				var t1 := time
				while not pa.grounded and time - t1 < 3:
					await get_tree().process_frame
				var miss: float = Vector2(pa.pos.x - to.x, pa.pos.z - to.z).length()
				var ok: bool = miss < 4.0 and absf(pa.pos.y - (to.y - 1.0)) < 1.0
				if not ok:
					bad += 1
				print("[traversal] zip %d %s %s: ended %s, far end %s (off %.2f m)" % [i, "a->b" if dir == 1 else "b->a", "ok" if ok else "FAIL", pa.pos, to, miss])
		print("[traversal] %d failures" % bad)
		get_tree().quit()
		return
	if screen == "padtest":
		# controller A on a highlighted menu button must press it
		await get_tree().create_timer(1.0).timeout
		menus.main()
		await get_tree().process_frame
		var pb: Button = null
		for b in menus.find_children("*", "Button", true, false):
			if (b as Button).text.to_lower() == "play":
				pb = b
		pb.grab_focus()
		pad_nav._accept()
		await get_tree().process_frame
		await get_tree().process_frame
		print("[padtest] after A on Play: screen=", menus.current)
		get_tree().quit()
		return
	if screen == "switch":
		# press Start match with another map picked; after the reload, check the match is running
		if not _switch_done:
			_switch_done = true
			await get_tree().create_timer(1.0).timeout
			menus.play()
			menus.map_id = "toycity" if map.id != "toycity" else "bedroom"
			menus.play()
			for b in menus.find_children("*", "Button", true, false):
				if (b as Button).text.to_lower() == "start match":
					(b as Button).pressed.emit()
			return
		await get_tree().create_timer(3.0).timeout
		print("[switch] map=%s state=%s phase=%s actors=%d" % [map.id, state, match_.phase, actors.size()])
		if shots != "":
			_shot(shots + "/switch.png")
		await get_tree().process_frame
		get_tree().quit()
		return
	if screen.begins_with("loadout:"):
		menus.selected_weapon = screen.split(":")[1]
		screen = "loadout"
	if shots != "" and screen != "":
		# screenshot a menu screen and quit
		await get_tree().create_timer(1.5).timeout
		match screen:
			"play": menus.play()
			"loadout": menus.collection("main")
			"settings": menus.settings_screen("main")
			"controls": menus.controls("main")
			"login": menus.login("register")
			"main": menus.login("register"); await get_tree().process_frame; menus.main()
			"resume": menus.hide_menus(); menus.resume_hint(true, Callable())
			"online": menus.online_screen()
			"lobby":
				host_room("SHOT1", "ffa", 4)
				menus.connecting("Opening a room")
				while Net.status == "connecting":
					await get_tree().process_frame
		await get_tree().create_timer(1.0).timeout
		_shot(shots + "/menu_" + screen + ".png")
		await get_tree().process_frame
		get_tree().quit()
		return
	if m == "":
		return
	if shots != "":
		await get_tree().create_timer(1.0).timeout
		_shot(shots + "/menu.png")
	print("[autotest] map=%s mode=%s" % [map.id, m])
	add_child(ProfBracket.new(true))
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--exp="):
			_experiment(a.trim_prefix("--exp=").split(","))
	var vrid := get_viewport().get_viewport_rid()
	var vmrid: RID = r.vm_viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	RenderingServer.viewport_set_measure_render_time(vmrid, true)
	if "--tris" in OS.get_cmdline_user_args():
		await get_tree().create_timer(2.0).timeout
		TriDump.dump(get_tree().root)
	add_child(ProfBracket.new(false))
	start_match("normal", m)
	var t0 := Time.get_ticks_msec()
	var frames := 0
	while (Time.get_ticks_msec() - t0) / 1000.0 < secs and state == "playing":
		await get_tree().process_frame
		frames += 1
		if frames % 20 == 0:
			print("[perf] ", Prof.report(20))
			print("[gpu] main cpu %.1f gpu %.1f | vm cpu %.1f gpu %.1f | setup %.1f" % [RenderingServer.viewport_get_measured_render_time_cpu(vrid), RenderingServer.viewport_get_measured_render_time_gpu(vrid), RenderingServer.viewport_get_measured_render_time_cpu(vmrid), RenderingServer.viewport_get_measured_render_time_gpu(vmrid), RenderingServer.get_frame_setup_time_cpu()])
			print("[perf] frame %d: process %.1f ms, physics %.1f ms, fps %d, draw calls %d, objects %d, prims %d" % [frames, Performance.get_monitor(Performance.TIME_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000, Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)])
		# keep the player busy: walk forward, fire, jump now and then
		input._down["KeyW"] = true
		input._down["Mouse0"] = frames % 40 < 20
		if frames % 90 == 0:
			input._pressed["Space"] = true
		if frames % 300 == 0:
			input._pressed["KeyQ"] = true
		if m == "training" and frames % 30 == 0 and match_.phase == "playing":
			# put a live dummy right in front of the player so the test actually hits things
			var pa := player.actor
			for o in actors:
				if o != pa and o.alive:
					var fwd := -r.camera.global_transform.basis.z
					var spot: Vector3 = pa.pos + Vector3(fwd.x, 0, fwd.z).normalized() * 5
					o.teleport(spot)
					o.spawn_protect_until = 0
					break
			if frames == 300 and shots != "":
				_shot(shots + "/training_hud.png")
				pause()
				menus.try_blaster()
				await get_tree().create_timer(0.6).timeout
				_shot(shots + "/training_try.png")
				training_try("bubbleBlaster")
				resume()
				print("[training] slot weapon now ", player.actor.weapon().id)
		if shots != "":
			var el := (Time.get_ticks_msec() - t0) / 1000.0
			for st in [4.0, 9.0, 15.0, 22.0]:
				if el >= st and not has_meta("shot%d" % st):
					set_meta("shot%d" % st, true)
					if st == 9.0:
						input._down["Mouse2"] = true
					_shot(shots + "/%s_%s_%02d.png" % [map.id, m, int(st)])
					input._down["Mouse2"] = false
	print("[traversal] pads used %d, ziplines used %d" % [traversal.uses.pad, traversal.uses.zip])
	if m == "training":
		var pa := player.actor
		print("[training] pops %d headshots %d hits %d/%d reserve %d/%d" % [pa.kills, pa.headshots, pa.shots_hit, pa.shots_fired, pa.weapon().reserve, pa.weapon().cfg.reserve])
	var kills := 0
	var alive := 0
	for a in actors:
		kills += a.kills
		alive += int(a.alive)
	print("[autotest] %d frames in %.1f s (%.0f fps), match time %.1f, phase %s, actors %d, alive %d, total pops %d" % [frames, secs, frames / secs, time, match_.phase, actors.size(), alive, kills])
	print("[autotest] team scores %s, player pops %d deaths %d hp %.0f pos %s" % [str(match_.team_scores), player.actor.kills, player.actor.deaths, player.actor.health, str(player.actor.pos)])
	var stuck := 0
	for b in bots:
		if b.actor.alive and b.actor.pos.y < -1:
			stuck += 1
	print("[autotest] bots below the floor: %d" % stuck)
	quit_to_menu()
	await get_tree().process_frame
	get_tree().quit()


## Maps are built once per load: switching rebuilds the whole scene and returns to the Play screen.
func _reload_map() -> void:
	await get_tree().create_timer(0.06).timeout
	get_tree().reload_current_scene()


# ------------------------------------------------------------------ settings
func apply_settings(k: String) -> void:
	if k == "quality":
		r.set_quality(Settings.get_v("quality"))
		audio.hrtf = Settings.get_v("quality") != "low"
	if k.ends_with("Volume"):
		audio.set_volumes(Settings.get_v("masterVolume"), Settings.get_v("musicVolume"), Settings.get_v("sfxVolume"), Settings.get_v("ambienceVolume"))
	if k == "motionBlur":
		r.set_motion_blur(Settings.get_v("motionBlur"))
	if k == "enemyOutlines":
		_refresh_outlines()
	if k == "reducedMotion":
		combat.reduced_motion = Settings.get_v("reducedMotion")
		ambient.set_reduced_motion(Settings.get_v("reducedMotion"))
	if k == "playerName" and player:
		player.actor.name = Settings.get_v("playerName")
	if k == "fullscreen":
		if Settings.get_v("fullscreen"):
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif DisplayServer.get_name() != "headless":
			# 1920x1080 window; when the screen is too small for that (plus the title bar), fill it instead
			var usable := DisplayServer.screen_get_usable_rect()
			if usable.size.x < 1920 or usable.size.y < 1080 + 40:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	hud.apply_settings()


# ------------------------------------------------------------------ events
func _register_events() -> void:
	events.on("damage", func(d: Dictionary) -> void:
		var pl: Actor = player.actor if player else null
		var tgt: Actor = d.target
		if tgt == pl and player:
			hud.damage_from(d.attacker.pos if d.attacker else d.point - d.fromDir)
			player.on_damaged(d.amount)
			audio.player_hurt(d.healthDmg <= 0)
		if d.attacker == pl and tgt != pl:
			var kind: String = "head" if d.head else ("shield" if d.shieldDmg > 0 and d.healthDmg <= 0 else "body")
			if d.shieldDmg > 0 and d.healthDmg > 0:
				hud.damage_number(d.point + Vector3(0.25, 0.15, 0), d.shieldDmg, "shield")
				hud.damage_number(d.point, d.healthDmg, "head" if d.head else "body")
			else:
				hud.damage_number(d.point, d.amount, kind)
			if tgt.alive:
				hud.hit(kind)
			audio.hitmarker(d.head, kind == "shield")
		if bot_by_actor.has(tgt):
			bot_by_actor[tgt].on_damaged(d.attacker, time)
			if randf() < 0.5 and tgt.alive:
				audio.hurt(tgt.def.voicePitch, tgt.head_pos())
		if d.shieldBroke:
			audio.shield_break(tgt.chest_pos()))
	events.on("kill", func(k: Dictionary) -> void:
		var pl: Actor = player.actor if player else null
		var victim: Actor = k.victim
		var killer = k.killer
		match_.on_kill(killer, victim)
		var wname: String = "FALLING BLOCK" if k.weapon == "block" else (Cfg.MELEE[k.weapon].name.to_upper() if Cfg.MELEE.has(k.weapon) else Cfg.WEAPONS.get(k.weapon, {}).get("name", ""))
		hud.kill_feed(killer, victim, wname, k.head, killer == pl or victim == pl)
		if victim == pl and player:
			player.on_death(killer)
			hud.set_death(killer.name if killer else "", wname if killer else ("a falling block" if k.weapon == "block" else "your own crayon"))
		if killer == pl and victim != pl and pl:
			hud.hit("kill")
			hud.eliminated(victim.name, pl.streak, k.head)
			audio.kill_confirm(pl.streak)
			if not Settings.get_v("reducedMotion") and not online():
				slowmo_t = 0.22
				time_scale = 0.35
		# the body drops to the floor where it was popped (teammates can revive it there in team modes)
		var g := phys.ray_dist(victim.pos + Vector3(0, 0.6, 0), Vector3.DOWN, 60, true)
		if g != INF:
			victim.pos.y = victim.pos.y + 0.6 - g
		victim.revive_t = 0
		victim.reviver = null
		if match_.teams() and pl and victim.team == pl.team and victim != pl:
			hud.pickup("%s is down. Hold %s on them to revive" % [victim.name, GInput.action_name("revive")], Modes.TEAMS[victim.team].light))
	events.on("shot", func(s: Dictionary) -> void:
		var loud := 1.4 if s.weapon in ["crayonCannon", "thunderspring", "brickbreaker"] else (0.8 if s.weapon == "starlightZapper" else 1.0)
		for b in bots:
			b.on_sound(s.pos, s.shooter, time, loud))
	events.on("explosion", func(e: Dictionary) -> void:
		if player == null:
			return
		var d: float = player.actor.pos.distance_to(e.pos)
		if d < 14:
			player.add_trauma(clampf(1 - d / 14, 0, 1) * 0.55))
	events.on("pickup", func(p: Dictionary) -> void:
		if player == null or p.actor != player.actor:
			return
		var color: String = Pickups.INFO[p.kind].color if Pickups.INFO.has(p.kind) else "#ffd23f"
		hud.pickup(p.label, color))


# ------------------------------------------------------------------ match lifecycle
## A wall or prop broke: routes through it open (bots re-plan on their next think), arrows in it fall out.
func _on_piece_broken(id: int) -> void:
	nav.open_piece(id)
	var p: Dictionary = destruction.pieces[id]
	combat.clear_stuck_in(AABB(p.mn, p.mx - p.mn).grow(0.6))
	if host:
		host.piece_broken(id)


func _clear_match() -> void:
	for a in actors:
		if a.model:
			(a.model as Node).queue_free()
		a.dispose()
	for b in bots:
		b.dispose()
	actors = []
	bots = []
	bot_by_actor.clear()
	remotes.clear()
	gear.clear()
	player = null
	dash_from.clear()
	combat.clear()
	fx.clear()
	destruction.reset()
	debris.clear()
	ambient.clear_blocks()
	pickups.reset()
	hud.reset()
	hill_zone.hide_zone()
	sector_zones.clear()
	ropes.clear()
	shelf_starters.clear()
	assignment.clear()
	for b in beacons.values():
		(b.node as Node).queue_free()
	beacons.clear()


func _world_dict() -> Dictionary:
	return {
		"nav": nav, "phys": phys, "combat": combat, "audio": audio, "fx": fx,
		"actors": func(): return actors,
		"player": func(): return player.actor if player else null,
		"pickups": func(): return pickups.list(),
		"spawn_points": spawn_points, "zones": arena.zones, "difficulty": difficulty,
		"listener": func(): return r.camera.global_position,
		"objective": func(a: Actor):
			if match_.phase != "playing":
				return null
			var h = match_.hill
			if h != null:
				return {"pos": h.pos, "radius": h.site.radius, "height": h.site.height}
			if not assignment.has(a):
				return null
			var si: int = assignment[a]
			if si >= match_.sectors.size():
				return null
			var s: Dictionary = match_.sectors[si]
			return {"pos": s.pos, "radius": s.def.radius, "height": s.def.height},
		"team_mode": Modes.MODES[mode].teams, "mode": mode,
		"traversal": func(): return traversal,
	}


## Start a match. Solo: `seats` is left out and the cast is you plus the mode's bots, as always.
## Online: `seats` lists every toy in order (same order on every machine) and `local_seat` is yours.
func start_match(d: String, m := mode, seats = null, local_seat := 0) -> void:
	audio.init()
	difficulty = d
	mode = m
	match_.set_mode(m)
	var def: Dictionary = Modes.MODES[m]
	var team_mode: bool = def.teams
	_clear_match()
	time = 0
	match_seconds = 0
	var world := _world_dict()
	var training: bool = def.get("training", false)
	training_gun = ""
	menus.training_mode = training
	if seats == null:
		var me := _make_player()
		# roster: FFA = all fourteen; team modes = a random pick
		var roster := Chars.ALL_BOTS.duplicate()
		if m != "ffa":
			roster.shuffle()
			roster = roster.slice(0, def.botCount)
		for id in roster:
			_make_bot(id, m == "ffa" and Chars.SHELF_ROSTER.has(id), world, training)
		# teams: you are always on Sunrise; everyone else is dealt round the teams so sizes match
		if team_mode:
			me.team = 0
			var n: int = def.teamCount
			var order := bots.duplicate()
			order.shuffle()
			for i in order.size():
				order[i].actor.team = (i + 1) % n
			for b in bots:
				b.actor.model.set_team(Modes.TEAMS[b.actor.team].color)
	else:
		for i in seats.size():
			var st: Dictionary = seats[i]
			var bot_id := Roster.seat_bot(st)
			var a: Actor
			if i == local_seat:
				a = _make_player()
				a.name = str(st.name)
			elif bot_id != "" and guest == null:
				a = _make_bot(bot_id, bool(st.shelf), world, false)
			else:
				var cdef: Dictionary = Chars.CHARACTERS[bot_id] if bot_id != "" else Roster.human_def(str(st.name))
				a = _make_remote(cdef, str(st.name), i, Roster.seat_human(st), bool(st.shelf) and guest == null)
			a.team = int(st.team) if team_mode else -1
			if team_mode and a.model:
				a.model.set_team(Modes.TEAMS[a.team].color)
	var pa: Actor = player.actor
	_refresh_outlines()
	_assign_bot_classes(training)
	# spawn everyone
	match_.reset(time)
	match_.shelf_spawns = shelf_spawns
	if match_.hill != null:
		hill_zone.place(match_.hill.pos, match_.hill.site.radius, match_.hill.site.height)
	sector_zones.build(match_.sectors)
	director_at = 0
	if m == "conquest" and guest == null:
		_run_director(true)
	for a in actors:
		a.alive = false
		a.respawn_at = -1
		a.kills = 0
		a.deaths = 0
		a.streak = 0
		a.best_streak = 0
		a.headshots = 0
		a.shots_fired = 0
		a.shots_hit = 0
		a.damage_dealt = 0
		if guest != null and remotes.has(a):
			# guests: other toys appear when the host's snapshots and spawn events arrive
			a.despawn()
			a.model.visible = false
			continue
		_respawn(a, true)
	move_events = {
		"on_jump": func(a: Actor): if a.is_player: audio.jump(),
		"on_land": func(a: Actor, s: float):
			if a.is_player:
				audio.land(a.ground_mat, s)
				player.on_land(s)
			elif a.pos.distance_to(r.camera.global_position) < 20:
				audio.land(a.ground_mat, s * 0.6, a.pos),
		"on_slide": func(a: Actor): if a.is_player: audio.slide(),
		"on_dash": func(a: Actor, from: Vector3):
			dash_from[a] = from
			audio.dash(null if a.is_player else a.pos),
		"on_footstep": func(a: Actor):
			if a.is_player:
				audio.footstep(a.ground_mat, null, 0.5 if a.crouching else 1.0)
			elif a.pos.distance_to(r.camera.global_position) < 22:
				audio.footstep(a.ground_mat, a.pos, 0.8),
	}
	state = "playing"
	menus.hide_menus()
	hud.show_hud(true)
	r.set_menu_blur(false)
	r.set_viewmodel_visible(true)
	input.request_lock()
	if audio.music:
		audio.music.new_song()
		audio.music.start()
		audio.music.set_intensity(1)
	audio.start_ambience()
	ambient.ambience_on = true
	ambient.start_sounds()
	hud.countdown(3)
	audio.countdown(false)
	hud.set_mode(match_)
	if team_mode:
		var my_team := maxi(0, pa.team)
		var sub: String
		if m == "takeover":
			sub = "Hold the toy box. First to %d wins." % def.scoreTarget
		elif m == "conquest":
			sub = "You start with %s. Control 4 of the 6 sectors to win." % match_.sectors[Modes.CONQUEST_HOMES[my_team]].def.name
		else:
			sub = "First team to %d pops wins." % def.scoreTarget
		hud.announce("You're on Team " + Modes.TEAMS[my_team].name, sub, 3.4)
	elif training:
		hud.announce("Training Range", "These toys never shoot back. Ammo is endless. Pause to try any blaster or to leave.", 3.6)
	else:
		hud.announce("Free-for-All", map.ffaIntro, 3.2)


## You: the first-person toy this game moves.
func _make_player() -> Actor:
	var pdef: Dictionary = Chars.CHARACTERS.player.duplicate()
	pdef.name = Settings.get_v("playerName") if Settings.get_v("playerName") != "" else "You"
	var pa := Actor.new(pdef, true, phys)
	pa.name = pdef.name
	actors.append(pa)
	player = Player.new(pa, r.camera, vm, {
		"input": input, "combat": combat, "audio": audio, "fx": fx, "phys": phys,
		"nearby_prompt": func(a: Actor) -> String:
			var dn := _downed_near(a)
			if dn == null:
				if a.zip != null:
					return "%s to let go" % GInput.action_name("jump")
				if traversal.nearest_zip(a.eye_pos(), player.aim_dir())[0] >= 0:
					return "Press %s to grab the zipline" % GInput.action_name("revive")
				return ""
			if dn.reviver == a and dn.revive_t > 0:
				return "Reviving %s  %d%%" % [dn.name, roundi(dn.revive_t / Cfg.COMBAT.reviveTime * 100)]
			return "Hold %s to revive %s" % [GInput.action_name("revive"), dn.name],
		"try_zip": func(a: Actor) -> bool:
			if a.zip != null or _downed_near(a) != null:
				return false
			var hit := traversal.nearest_zip(a.eye_pos(), player.aim_dir())
			if hit[0] < 0:
				return false
			traversal.attach(a, hit[0], hit[1], player.aim_dir(), time)
			return true,
		"teammates": func(): return actors.filter(func(o): return o != pa and o.alive and o.team == pa.team) if pa.team >= 0 else [],
		"aim_targets": func(): return actors.filter(func(o): return o != pa and o.alive and (pa.team < 0 or o.team != pa.team)),
	})
	return pa


func _make_bot(id: String, shelf: bool, world: Dictionary, training: bool) -> Actor:
	var cdef: Dictionary = Chars.CHARACTERS[id]
	var a := Actor.new(cdef, false, phys)
	var rig := ToyRig.new(cdef)
	a.model = rig
	r.world.add_child(rig)
	var bot := Bot.new(a, Bot.PERSONALITIES[id], world)
	a.abilities = []  # set with the class (see _assign_bot_classes)
	bot.passive = training
	actors.append(a)
	bots.append(bot)
	bot_by_actor[a] = bot
	if shelf:
		shelf_starters[a] = true
	return a


## A toy moved by another game: a guest's toy on the host, anything but yours on a guest.
func _make_remote(cdef: Dictionary, nm: String, seat: int, net_id: String, shelf: bool) -> Actor:
	var a := Actor.new(cdef, false, phys)
	a.name = nm
	var rig := ToyRig.new(cdef)
	a.model = rig
	r.world.add_child(rig)
	actors.append(a)
	remotes[a] = Roster.new_remote(seat, net_id)
	if shelf:
		shelf_starters[a] = true
	return a


## Conquest brain for the bots: every couple of seconds each team decides which sectors to defend and
## which to attack, and sends its toys there (nearest first, spread out, sticky so they don't dither).
func _run_director(force := false) -> void:
	var m := match_
	if m.sectors.is_empty():
		return
	var now := time
	if not force and now < director_at:
		return
	director_at = now + 2
	for t in m.team_count():
		var tb := bots.filter(func(b): return b.actor.team == t and b.actor.alive)
		if tb.is_empty():
			continue
		var owned := m.sectors_owned(t)
		var leader := -INF
		for i in m.team_scores.size():
			if i != t:
				leader = maxf(leader, m.team_scores[i])
		var value := []
		for s in m.sectors:
			var enemies := 0
			for i in s.counts.size():
				if i != t:
					enemies += s.counts[i]
			var v: float
			if s.owner == t:
				v = 3.2 if (enemies > 0 or s.progress < 1) else (0.9 if owned >= 3 else 0.35)
			elif s.owner < 0:
				v = 2.8 if (s.progressTeam == t and s.progress > 0) else 2.3
			else:
				var threat := 1.6 if m.sectors_owned(s.owner) >= 3 else 0.0
				v = 1.5 + threat + (0.3 if m.team_scores[s.owner] == leader else 0.0)
			value.append(v)
		var crowd_n := {}
		# keep sticky assignments first
		var order := tb.duplicate()
		order.sort_custom(func(x, y): return int(assignment.has(x.actor)) > int(assignment.has(y.actor)))
		for b in order:
			var a: Actor = b.actor
			var cur: int = assignment.get(a, -1)
			var best := -1
			var best_score := -INF
			for i in m.sectors.size():
				var s: Dictionary = m.sectors[i]
				var d := Vector2(a.pos.x - s.pos.x, a.pos.z - s.pos.z).length() + absf(a.pos.y - s.pos.y) * 1.5
				var crowd: float = crowd_n.get(i, 0) * (0.5 if value[i] >= 3 else 1.1)
				var score: float = value[i] - d / 38 - crowd + (0.6 if i == cur else 0.0)
				if score > best_score:
					best_score = score
					best = i
			if best >= 0:
				assignment[a] = best
				crowd_n[best] = crowd_n.get(best, 0) + 1


## Allies always get a team-colored outline in team modes; enemy outlines follow the setting.
func _refresh_outlines() -> void:
	var me: Actor = player.actor if player else null
	for a in actors:
		if a.model == null:
			continue
		var ally: bool = me != null and me.team >= 0 and a.team == me.team
		if ally:
			a.model.set_outline(true, Modes.TEAMS[a.team].light)
		else:
			a.model.set_outline(Settings.get_v("enemyOutlines"), "#ff2d55")


## Which class a toy (re)spawns as: yours from the loadout (or the Training blaster's class), a bot's own,
## a remote toy's from its game.
func _class_for(a: Actor) -> String:
	var remote = remotes.get(a)
	if remote != null:
		return str(remote.get("cls", "light"))
	if a.is_player:
		return Cfg.class_of_gun(training_gun) if training_gun != "" else Loadout.cls()
	var bot = bot_by_actor.get(a)
	return bot.cls if bot else "light"


## Give every bot a class: an even mix on each team (FFA: across everyone); Training dummies are Mediums.
## Each bot's personality is nudged toward its class.
func _assign_bot_classes(training: bool) -> void:
	var teams := []
	for b in bots:
		teams.append(b.actor.team)
	var classes := assign_bot_classes(teams)
	for i in bots.size():
		var b: Bot = bots[i]
		b.set_class("medium" if training else classes[i])


## One class per bot (given each bot's team, -1 = no teams), alternating within each team from a random start.
static func assign_bot_classes(teams: Array) -> Array:
	var out := []
	var next := {}
	for t in teams:
		if not next.has(t):
			next[t] = randi() % 2
		out.append(Cfg.CLASS_ORDER[next[t] % 2])
		next[t] += 1
	return out


## (Re)spawn a toy. `at` = {pos, yaw} where the host said (guests); otherwise the match rules pick a spot.
func _respawn(a: Actor, initial := false, at = null) -> void:
	var pos: Vector3
	var yaw: float
	if at != null:
		pos = at.pos
		yaw = at.yaw
	else:
		var pool = shelf_spawns if shelf_starters.has(a) and shelf_spawns.size() else null
		var sp := match_.pick_spawn(a, actors, pool)
		pos = sp.pos
		yaw = sp.yaw
	a.set_class(_class_for(a))
	a.spawn(pos, yaw, time)
	a.slot = 0
	a.weapons[1] = null  # one blaster per loadout
	var remote = remotes.get(a)
	if remote != null:
		# moved by another game: no collider here, weapons come with its state
		remote.life += 1
		remote.state = null
		a.despawn()
		a.alive = true
		a.model.visible = true
		a.model.scale_in = 0.01
	elif a.is_player:
		# your loadout from the menu (changes made mid-match apply here, on the next respawn)
		var wid: String = training_gun if training_gun != "" else Loadout.gun()
		a.give_weapon(wid, 0, Loadout.scope(wid))
		a.abilities = Loadout.abilities(a.cls)
		player.on_spawn()
		a.weapon().equip(time, 0.3)
	else:
		var bot: Bot = bot_by_actor[a]
		a.give_weapon(Bot.pick_bot_loadout(bot.personality, bot.cls), 0)
		a.abilities = [] if bot.passive else Bot.pick_bot_abilities(bot.personality, bot.cls)
		bot.on_spawn(time)
		a.model.visible = true
		a.model.scale_in = 0.01
	fx.reassemble(pos, a.def.colors)
	if not initial:
		audio.spawn_pop(pos + Vector3(0, 1, 0))
	if host:
		host.on_spawn(a, pos, yaw, false)


# ------------------------------------------------------------------ revives (team modes)
## The downed teammate this toy is standing next to (closest one), or null.
func _downed_near(a: Actor) -> Actor:
	if not match_.teams() or not a.alive:
		return null
	var best: Actor = null
	var best_d: float = Cfg.COMBAT.reviveRange
	for o in actors:
		if o == a or o.team != a.team or not o.is_downed(time):
			continue
		if absf(o.pos.y - a.pos.y) > 2.2:
			continue
		var d := Vector2(o.pos.x - a.pos.x, o.pos.z - a.pos.z).length()
		if d < best_d:
			best_d = d
			best = o
	return best


## Holding on to a downed teammate for 3 s puts them back together on the spot.
func _update_revives(dt: float, now: float) -> void:
	if not match_.teams() or match_.phase != "playing":
		return
	var pl := player
	# people holding revive: you, and (when hosting) your guests
	var humans := [[pl.actor, _downed_near(pl.actor) if pl.revive_held else null]]
	for ra in remotes:
		if remotes[ra].net_id != "" and remotes[ra].revive_held:
			humans.append([ra, _downed_near(ra)])
	for d in actors:
		if not d.is_downed(now):
			d.revive_t = 0
			d.reviver = null
			continue
		var helper: Actor = null
		for hh in humans:
			if hh[1] == d:
				helper = hh[0]
				break
		if helper == null:
			for b in bots:
				if b.reviving() != d or not b.actor.alive:
					continue
				if absf(b.actor.pos.y - d.pos.y) < 2.2 and Vector2(b.actor.pos.x - d.pos.x, b.actor.pos.z - d.pos.z).length() < Cfg.COMBAT.reviveRange:
					helper = b.actor
					break
		if helper:
			d.reviver = helper
			d.revive_t += dt
			if d.revive_t >= Cfg.COMBAT.reviveTime:
				_revive(d, helper)
		else:
			d.revive_t = maxf(0, d.revive_t - dt * 2)
			# a bot that is still running over keeps its claim; anyone else lets go
			var rv: Actor = d.reviver
			if rv and (not rv.alive or rv.is_player or not bot_by_actor.has(rv) or bot_by_actor[rv].reviving() != d):
				d.reviver = null


func _revive(d: Actor, by: Actor) -> void:
	var pos := d.pos + Vector3(0, 0.05, 0)
	d.spawn(pos, d.yaw, time)
	d.health = d.revive_health()
	d.last_damage_at = time  # no instant regen: the usual 6 s wait applies
	d.respawn_at = -1
	by.revives += 1
	for w in d.weapons:
		if w:
			w.equip(time, 0.3)
	var remote = remotes.get(d)
	if remote != null:
		remote.life += 1
		remote.state = null
		d.despawn()
		d.alive = true
		d.model.visible = true
		d.model.scale_in = 0.6
	elif d.is_player:
		player.on_spawn()
		hud.announce("Back in the fight!", "%s revived you" % by.name, 2)
	else:
		bot_by_actor[d].on_spawn(time)
		d.model.visible = true
		d.model.scale_in = 0.6
	fx.reassemble(pos, d.def.colors)
	audio.spawn_pop(pos + Vector3(0, 1, 0))
	var me := player.actor
	if by == me:
		hud.pickup("You revived " + d.name, "#7dff6b")
	elif d != me and d.team == me.team:
		hud.pickup("%s revived %s" % [by.name, d.name], Modes.TEAMS[d.team].light)
	if host:
		host.on_spawn(d, pos, d.yaw, true, by)


func pause() -> void:
	if state != "playing":
		return
	state = "paused"
	input.exit_lock()
	menus.pause()
	r.set_menu_blur(true)
	hud.set_scoreboard(false)
	if online():
		return  # online the match keeps going for everyone: the pause menu just takes your hands off the controls
	audio.set_paused(true)
	PhysicsServer3D.set_active(false)


func resume() -> void:
	if state != "paused":
		return
	state = "playing"
	menus.hide_menus()
	r.set_menu_blur(false)
	audio.set_paused(false)
	PhysicsServer3D.set_active(true)
	input.request_lock()
	input.consume_pressed()


## Training: swap the blaster in your current slot for any blaster (locked ones too, for this session).
func training_try(wid: String) -> void:
	var pa := player.actor
	training_gun = wid
	if pa.alive:
		# the blaster now; its class (health, speed, abilities) from the next respawn
		pa.give_weapon(wid, 0, Loadout.scope(wid))
		pa.slot = 0
		player.equip_current(true)
		pa.weapon().equip(time, 0.3)


func quit_to_menu() -> void:
	leave_online()
	_back_to_menu()
	menus.main()


## Leave the match screen for the menus (the online connection, if any, stays up).
func _back_to_menu() -> void:
	state = "menu"
	PhysicsServer3D.set_active(true)
	Engine.time_scale = 1
	input.exit_lock()
	_clear_match()
	hud.show_hud(false)
	menus.resume_hint(false, Callable())
	r.set_menu_blur(true)
	r.set_viewmodel_visible(false)
	audio.set_paused(false)
	if audio.music:
		audio.music.set_intensity(0)
	ambient.stop_sounds()
	results_at = -1


func _end_match() -> void:
	var pl := player.actor
	state = "results"
	input.exit_lock()
	hud.set_scoreboard(false)
	var st: Dictionary = Settings.stats
	st.matches += 1
	var won := match_.is_winner(pl)
	var reward: Dictionary = Progress.award({
		"kills": pl.kills, "headshots": pl.headshots, "revives": pl.revives, "bestStreak": pl.best_streak, "won": won,
		"place": 0 if match_.teams() else match_.standings(actors).find(pl) + 1, "difficulty": difficulty,
	})
	if won:
		st.wins += 1
	st.kills += pl.kills
	st.deaths += pl.deaths
	st.headshots += pl.headshots
	st.shotsFired += pl.shots_fired
	st.shotsHit += pl.shots_hit
	st.bestStreak = maxi(st.bestStreak, pl.best_streak)
	st.bestMatchKills = maxi(st.bestMatchKills, pl.kills)
	st.playTimeSec += match_seconds
	Settings.save_stats()
	audio.fanfare(won)
	if audio.music:
		audio.music.set_intensity(0)
	var m := match_
	var title: String
	if m.teams():
		title = "Draw!" if m.winner_team == Modes.DRAW else ("Your team wins!" if won else "Team %s wins!" % Modes.TEAMS[m.winner_team].name)
	else:
		title = "Victory!" if won else "%s wins!" % (m.winner.name if m.winner else "Nobody")
	var sub := "Team %s controls 4 of 6 sectors" % Modes.TEAMS[m.winner_team].name if m.mode.id == "conquest" and m.winner_team >= 0 and m.end_reason == "score" else ""
	hud.announce(title, sub, 2)
	await get_tree().create_timer(1.8, true, false, true).timeout
	if state != "results":
		return
	menus.results(match_, actors, pl, reward)
	hud.show_hud(false)
	r.set_menu_blur(true)


## Dev: switch rendering features off to find GPU costs (--exp=shadow,glow,msaa,lights,vm,transp,fog,cc,sky)
func _experiment(what: PackedStringArray) -> void:
	var e := r.env.environment
	for w in what:
		match w:
			"shadow":
				for l in get_tree().root.find_children("*", "Light3D", true, false):
					(l as Light3D).shadow_enabled = false
			"glow": e.glow_enabled = false
			"msaa": get_viewport().msaa_3d = Viewport.MSAA_DISABLED; r.vm_viewport.msaa_3d = Viewport.MSAA_DISABLED
			"lights":
				for l in get_tree().root.find_children("*", "OmniLight3D", true, false):
					(l as Light3D).visible = false
				for l in get_tree().root.find_children("*", "SpotLight3D", true, false):
					(l as Light3D).visible = false
			"vm": r.vm_layer.visible = false; r.vm_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			"fog": e.fog_enabled = false
			"sky": e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			"half": get_viewport().scaling_3d_scale = 0.5
			"transp":
				for n in get_tree().root.find_children("*", "GeometryInstance3D", true, false):
					var gi := n as GeometryInstance3D
					var m: Material = gi.material_override
					if m == null and gi is MeshInstance3D and (gi as MeshInstance3D).mesh and (gi as MeshInstance3D).mesh.get_surface_count() > 0:
						m = (gi as MeshInstance3D).mesh.surface_get_material(0)
					if m == null and gi is MultiMeshInstance3D and (gi as MultiMeshInstance3D).multimesh.mesh:
						m = (gi as MultiMeshInstance3D).multimesh.mesh.surface_get_material(0)
					if m is ShaderMaterial or (m is BaseMaterial3D and (m as BaseMaterial3D).transparency != BaseMaterial3D.TRANSPARENCY_DISABLED):
						gi.visible = false
			"cc":
				for k in Mats._plastic:
					(Mats._plastic[k] as StandardMaterial3D).clearcoat_enabled = false
				for k in Mats._vc_twins:
					(Mats._vc_twins[k] as StandardMaterial3D).clearcoat_enabled = false
	print("[exp] ", what)


# ------------------------------------------------------------------ main loop
func _process(delta: float) -> void:
	if not ready_ok:
		return
	var real_dt := minf(delta / maxf(0.01, Engine.time_scale), 0.05)
	input.poll_pad()
	if state != "playing" and not input.capturing():
		pad_nav.update(Time.get_ticks_msec() / 1000.0)
	Prof.begin("frame")
	_frame(real_dt)
	Prof.end("frame")
	input.end_frame()


func _frame(real_dt: float) -> void:
	# slow-mo after the player's eliminations
	if slowmo_t > 0:
		slowmo_t -= real_dt
		if slowmo_t <= 0:
			time_scale = 1
	else:
		time_scale += (1 - time_scale) * minf(1, real_dt * 10)
	Engine.time_scale = time_scale if state == "playing" else 1.0
	var dt := real_dt * time_scale
	if state == "menu":
		menu_t += real_dt
		_menu_camera(menu_t)
		_world_tick(real_dt, false)
	elif state == "playing" or (state == "paused" and online()):
		# online the match never stops: the pause menu just takes your hands off the controls
		var blocked := state == "paused"
		if guest:
			_guest_tick(dt, real_dt, blocked)
		else:
			_game_tick(dt, real_dt, blocked)
	elif state == "results":
		menu_t += real_dt
		_world_tick(real_dt, true)
		_update_rigs(real_dt)
	audio.update_listener(r.camera)


## Things that animate regardless of the match: train, fan, dust, debris, effects.
func _world_tick(dt: float, with_actors: bool) -> void:
	time += dt
	for f in arena.animated:
		f.call(dt, time)
	ambient.update(dt, actors if with_actors else [], func(_a, _d, _p): pass, r.camera.global_position)
	traversal.update(dt, time, actors if with_actors else [], r.camera.global_position)
	combat.now = time
	combat.update(dt)
	fx.update(dt, r.camera.global_position)


## Your input for this frame (or none, while an online pause menu is open).
func _player_input(dt: float, now: float, frozen: bool, blocked := false) -> void:
	var pl := player
	if blocked:
		pl.intent.clear()
		pl.revive_held = false
		return
	hud.set_scoreboard(input.act("scoreboard"))
	if input.pressed("Escape") or input.pad_pressed(GInput.PAD.MENU):
		pause()
		return
	if not frozen:
		pl.update(dt, now)
	else:
		# allow looking around during the countdown (mouse or right stick)
		pl.look(dt, false)


func _game_tick(dt: float, real_dt: float, blocked := false) -> void:
	time += dt
	var now := time
	var pl := player
	var pa := pl.actor
	var m := match_
	match_seconds += dt
	combat.now = now
	var frozen := m.phase == "countdown"
	if m.mode.get("training", false):
		# training: the reserve never runs out (you still reload)
		for w in pa.weapons:
			if w:
				w.reserve = w.cfg.reserve
	_player_input(dt, now, frozen, blocked)
	if state != "playing" and not (state == "paused" and online()):
		return
	# bots think + move
	Prof.begin("bots")
	for b in bots:
		if frozen:
			b.intent.wish = Vector3.ZERO
		else:
			b.update(dt, now)
	Prof.end("bots")
	Prof.begin("move")
	for a in actors:
		if not a.alive:
			continue
		var remote = remotes.get(a)
		if remote != null:
			# a guest's toy: it moves in the guest's game, we put it where they say
			if host:
				host.drive(a, remote)
			a.tick(dt, now)
			continue
		var intent: Actor.Intent = pl.intent if a.is_player else bot_by_actor[a].intent
		if frozen:
			intent.wish = Vector3.ZERO
			intent.jump = false
			intent.dash = false
			intent.crouch_pressed = false
		var was_dashing: bool = a.dashing
		a.move(intent, dt, now, move_events)
		if was_dashing and not a.dashing and dash_from.has(a):
			fx.spring_trail(dash_from[a], a.pos, "#ffd23f" if a.is_player else a.def.accent)
		a.tick(dt, now)
		if not a.is_player:
			a.ads = 0
	_separate()
	Prof.end("move")
	if not frozen:
		for b in bots:
			b.fire(now)
	Prof.begin("combat")
	combat.update(dt)
	Prof.end("combat")
	Prof.begin("anim")
	for f in arena.animated:
		f.call(dt, now)
	pickups.update(dt, now, actors)
	Prof.end("anim")
	Prof.begin("ambient")
	ambient.update(dt, actors, func(a: Actor, dmg: float, p: Vector3): combat.apply_damage(a, null, dmg, false, p, "block", Vector3.DOWN), r.camera.global_position)
	# jump pads launch the toys this game moves (a guest's own game launches their toy)
	traversal.update(dt, now, actors.filter(func(x): return not remotes.has(x)) if remotes.size() else actors, r.camera.global_position)
	Prof.end("ambient")
	if m.mode.id == "conquest" and m.phase == "playing":
		_run_director()
	# match rules
	for e in m.update(dt, actors, now):
		if host:
			host.match_event(e)
		on_match_event(e)
	hill_zone.update(dt, m.hill, Settings.get_v("reducedMotion"))
	sector_zones.update(dt, m.sectors)
	_update_revives(dt, now)
	# respawns
	if m.phase != "ended":
		for a in actors:
			if not a.alive and a.respawn_at >= 0 and now >= a.respawn_at:
				_respawn(a)
	Prof.begin("rigs")
	_update_rigs(dt)
	Prof.end("rigs")
	# camera + viewmodel
	pl.update_camera(real_dt, now)
	pl.update_viewmodel(real_dt, now)
	r.set_viewmodel_visible(pa.alive)
	Prof.begin("fx")
	fx.update(dt, r.camera.global_position)
	Prof.end("fx")
	# zone ambience + music intensity
	var zone = _zone_at(pa.pos)
	if zone != null and zone.name != last_zone:
		last_zone = zone.name
		audio.set_zone(zone.ambience)
	var inten := m.intensity(actors)
	if audio.music and audio.music.intensity != inten:
		audio.music.set_intensity(inten)
	if m.phase == "playing" and m.time_left < 60.05 and m.time_left > 59.95 - dt:
		hud.announce("One minute left!", "", 2)
	Prof.begin("hud")
	hud.update(real_dt, now, pl, actors, m, r.camera, zone.name if zone != null else "")
	Prof.end("hud")
	if host:
		host.update(Net.now_ms())


## A guest's frame: your own toy moves and shoots here; everything else is placed from the host's
## snapshots (GuestSession.update). No bots, match rules, pick-up rules or respawn timers.
func _guest_tick(dt: float, real_dt: float, blocked: bool) -> void:
	time += dt
	var now := time
	var pl := player
	var pa := pl.actor
	var m := match_
	match_seconds += dt
	combat.now = now
	var frozen := m.phase == "countdown"
	_player_input(dt, now, frozen, blocked)
	if state == "menu" or player == null:
		return
	if pa.alive:
		var intent := pl.intent
		if frozen:
			intent.wish = Vector3.ZERO
			intent.jump = false
			intent.dash = false
			intent.crouch_pressed = false
		var was_dashing := pa.dashing
		pa.move(intent, dt, now, move_events)
		if was_dashing and not pa.dashing and dash_from.has(pa):
			fx.spring_trail(dash_from[pa], pa.pos, "#ffd23f")
		pa.tick(dt, now)
	guest.update(Net.now_ms())
	combat.update(dt)
	for f in arena.animated:
		f.call(dt, now)
	pickups.update(dt, now, [])
	ambient.update(dt, actors, func(_a, _d, _p): pass, r.camera.global_position)
	traversal.update(dt, now, [pa], r.camera.global_position)
	hill_zone.update(dt, m.hill, Settings.get_v("reducedMotion"))
	sector_zones.update(dt, m.sectors)
	_update_rigs(dt)
	pl.update_camera(real_dt, now)
	pl.update_viewmodel(real_dt, now)
	r.set_viewmodel_visible(pa.alive)
	fx.update(dt, r.camera.global_position)
	var zone = _zone_at(pa.pos)
	if zone != null and zone.name != last_zone:
		last_zone = zone.name
		audio.set_zone(zone.ambience)
	var inten := m.intensity(actors)
	if audio.music and audio.music.intensity != inten:
		audio.music.set_intensity(inten)
	if m.phase == "playing" and m.time_left < 60.05 and m.time_left > 59.95 - dt:
		hud.announce("One minute left!", "", 2)
	hud.update(real_dt, now, pl, actors, m, r.camera, zone.name if zone != null else "")


## What the HUD and sound do for a match event.
func on_match_event(e) -> void:
	var m := match_
	var now := time
	var pa := player.actor
	if e is int:
		hud.countdown(e)
		audio.countdown(false)
	elif e is Dictionary:
		_on_sector_event(e)
	elif e == "go":
		hud.countdown("GO")
		audio.countdown(true)
	elif e == "blockdrop":
		if not map.blockDrops:
			return
		# guests get the spots in a "blockdrop" event from the host
		if guest == null:
			var spots: Array = ambient.block_drop(nav, 8)
			if host:
				host.block_drop(spots)
		hud.announce("Block drop!", "Wooden blocks are falling. Watch for red rings.")
		audio.announce()
	elif e == "end":
		if state == "playing" or state == "paused":
			_end_match()
	elif e == "hillwarn" and m.hill != null:
		hud.announce("Toy box moving soon", "Next stop: " + m.hill.next.name, 2.5)
		audio.announce()
	elif e == "hillmove" and m.hill != null:
		hill_zone.place(m.hill.pos, m.hill.site.radius, m.hill.site.height)
		hud.announce("The toy box moved!", "Now at " + m.hill.site.name, 2.8)
		audio.announce()
		audio.block_land(m.hill.pos + Vector3(0, 2, 0))
	elif (e == "hilltaken" or e == "hillcontested") and m.hill != null and now - last_hill_note > 4:
		last_hill_note = now
		var mine: bool = m.hill.owner == pa.team
		var text := "Toy box contested!" if e == "hillcontested" else ("Your team has the toy box" if mine else "The enemy took the toy box!")
		hud.pickup(text, "#ff4d8d" if e == "hillcontested" else Modes.TEAMS[maxi(0, m.hill.owner)].color)


func _on_sector_event(e: Dictionary) -> void:
	var pa := player.actor
	var s: Dictionary = match_.sectors[e.sector]
	var nm: String = s.def.name.trim_prefix("the ")
	var mine: bool = e.team == pa.team
	if e.kind == "captured":
		hud.pickup("Your team captured " + nm if mine else "Team %s captured %s" % [Modes.TEAMS[e.team].name, nm], Modes.TEAMS[e.team].color)
		audio.sector_captured(mine)
		if match_.sectors_owned(e.team) == 3:
			hud.announce("Your team holds 3 sectors" if mine else "Team %s holds 3 sectors" % Modes.TEAMS[e.team].name, "One more wins it!" if mine else "Take one back before they get a fourth!", 2.6)
	elif e.kind == "neutralized":
		hud.pickup("You lost " + nm if mine else nm + " is neutral again", "#ff4d6d" if mine else "#fff6d8")
		if mine:
			audio.sector_captured(false)
	elif e.kind == "attacked" and mine:
		hud.pickup(nm + " is under attack!", "#ff4d8d")


func _zone_at(p: Vector3):
	for z in arena.zones:
		if p.x >= z.min[0] and p.x <= z.max[0] and p.z >= z.min[1] and p.z <= z.max[1]:
			return z
	return null


## Toys don't physically collide with each other; gently push overlapping ones apart.
func _separate() -> void:
	for i in actors.size():
		var a: Actor = actors[i]
		if not a.alive:
			continue
		for j in range(i + 1, actors.size()):
			var b: Actor = actors[j]
			if not b.alive or absf(a.pos.y - b.pos.y) > 1.6:
				continue
			var dx := b.pos.x - a.pos.x
			var dz := b.pos.z - a.pos.z
			var d2 := dx * dx + dz * dz
			var mn := 0.78
			if d2 >= mn * mn:
				continue
			var d := sqrt(d2) if d2 > 0 else 0.01
			var push := (mn - d) * 0.5
			var nx := dx / d if d2 > 1e-6 else randf() - 0.5
			var nz := dz / d if d2 > 1e-6 else randf() - 0.5
			_nudge(a, -nx * push, -nz * push)
			_nudge(b, nx * push, nz * push)


func _nudge(a: Actor, dx: float, dz: float) -> void:
	var motion := Vector3(dx, 0, dz)
	var col := KinematicCollision3D.new()
	if a.body.test_move(a.body.global_transform, motion, col):
		motion = col.get_travel()
	a.pos.x += motion.x
	a.pos.z += motion.z
	a.sync()


func _update_rigs(dt: float) -> void:
	for a in actors:
		var rig: ToyRig = a.model
		if rig == null:
			continue
		var b: Bot = bot_by_actor.get(a)
		if not a.alive:
			# team modes: the toy lies where it fell until it is revived or the respawn timer runs out
			var down: bool = a.is_downed(time) and match_.phase != "ended"
			rig.visible = down
			if down:
				rig.set_cloak(0, time)
				rig.set_melee(0)
				rig.scale_in = 1
				rig.scale = Vector3.ONE
				rig.position = Vector3(a.pos.x, a.pos.y + 0.32, a.pos.z)
				rig.rotation = Vector3(-PI / 2 + 0.06, a.yaw + PI, 0)
			continue
		rig.visible = true
		rig.scale_in = minf(1, rig.scale_in + dt * 3.5)
		rig.position = a.pos
		rig.rotation = Vector3(0, a.yaw + PI, 0)
		rig.update(dt, b.anim_state(time) if b else Roster.actor_anim(a, time, remotes[a].reload if remotes.has(a) else 0.0), time)
		rig.set_shimmer(a.is_protected(time), time)
		rig.set_melee(a.melee_t, Cfg.CLASSES[a.cls].melee, a.melee_def().swing)
		# cloaked toys: teammates see a ghost, enemies barely a shimmer (a bit more up close)
		var me: Actor = player.actor if player else null
		var op := 0.0
		if a.cloaked:
			var ally: bool = me != null and me.team >= 0 and a.team == me.team
			var d: float = me.pos.distance_to(a.pos) if me else 99.0
			op = 0.3 if ally else (0.12 if d < 3 else 0.045)
		rig.set_cloak(op, time)
	_update_beacons()
	# Spring Hook cords
	ropes.begin()
	for a in actors:
		if not a.alive or a.grapple == null:
			continue
		var from: Vector3
		if a.is_player:
			from = r.camera.global_transform * Vector3(-0.22, -0.22, -0.5)
		else:
			from = a.chest_pos() + Vector3(-sin(a.yaw), 0.15, -cos(a.yaw)) * 0.4
		ropes.draw(from, a.grapple.anchor, time - a.grapple.start)
	ropes.end()


## A pulsing team-colored ring with a plus over every downed toy, so bodies are easy to find.
func _update_beacons() -> void:
	var now := time
	for a in actors:
		var down: bool = a.is_downed(now) and match_.phase != "ended"
		var bc = beacons.get(a)
		if not down:
			if bc != null:
				bc.node.visible = false
			continue
		if bc == null:
			var g := Node3D.new()
			var mat := Zones.ring_material(Modes.TEAMS[a.team].color, 0.9)
			mat.render_priority = 0
			var ring := Geo.ring(0.95, 1.15, 40).mesh_instance(mat, Vector3(0, 0.06, 0), Basis(Vector3.RIGHT, -PI / 2), false)
			var fmat: StandardMaterial3D = mat.duplicate()
			fmat.albedo_color.a = 0.45
			var fill := MeshInstance3D.new()
			fill.material_override = fmat
			fill.transform = Transform3D(Basis(Vector3.RIGHT, -PI / 2), Vector3(0, 0.05, 0))
			var plus := Node3D.new()
			plus.add_child(Geo.box(0.7, 0.2, 0.2).mesh_instance(mat, Vector3.ZERO, Basis(), false))
			plus.add_child(Geo.box(0.2, 0.7, 0.2).mesh_instance(mat, Vector3.ZERO, Basis(), false))
			plus.position.y = 2.1
			g.add_child(ring)
			g.add_child(fill)
			g.add_child(plus)
			r.world.add_child(g)
			bc = {"node": g, "fill": fill, "plus": plus, "ring": ring, "frac": -1.0}
			beacons[a] = bc
		bc.node.visible = true
		(bc.node as Node3D).position = a.pos
		(bc.plus as Node3D).rotation.y = now * 2
		(bc.plus as Node3D).position.y = 2.1 + sin(now * 3) * 0.12
		(bc.ring as Node3D).scale = Vector3.ONE * (1 + sin(now * 5) * 0.06)
		# the pie fills up while someone is reviving
		var frac := roundf(minf(1, a.revive_t / Cfg.COMBAT.reviveTime) * 36) / 36
		if bc.frac != frac:
			bc.frac = frac
			(bc.fill as MeshInstance3D).mesh = Geo.ring(0.01, 0.95, 40, 1, PI / 2, maxf(0.001, frac * TAU)).to_mesh()


# ------------------------------------------------------------------ online
func online() -> bool:
	return host != null or guest != null


## "host", "guest" or "" (offline)
func online_role() -> String:
	return "host" if host != null else ("guest" if guest != null else "")


## Open a room on the relay and wait in the lobby.
func host_room(code: String, m: String, bots: int) -> void:
	leave_online()
	host = HostSession.new(self, m, bots)
	_watch_net()
	Net.connect_room(Net.default_server(), _net_name(), code, "host")
	Settings.set_v("lastRoom", Net.clean_code(code))


## Join a friend's room.
func join_room(code: String) -> void:
	leave_online()
	guest = GuestSession.new(self)
	_watch_net()
	Net.connect_room(Net.default_server(), _net_name(), code, "guest")
	Settings.set_v("lastRoom", Net.clean_code(code))


func _net_name() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--name="):
			return a.trim_prefix("--name=")
	var n: String = str(Settings.get_v("playerName")).strip_edges()
	return n if n != "" and n != "You" else "Toy%d" % (randi() % 900 + 100)


func _watch_net() -> void:
	Net.on_status = _on_net_status
	Net.on_host_left = _on_host_left


func _on_net_status(s: String, why: String) -> void:
	if s == "online":
		if host:
			host.broadcast_lobby()
		elif guest:
			guest.say_ready()
	elif s == "error":
		_net_ended(why if why != "" else "Connection problem.")


func _on_host_left() -> void:
	_net_ended("The host left the game.")


## Stop online play (keeps whatever screen is showing).
func leave_online() -> void:
	if host:
		host.dispose()
	if guest:
		guest.dispose()
	host = null
	guest = null
	Net.on_status = Callable()
	Net.on_host_left = Callable()
	Net.on_game = Callable()
	Net.on_peers = Callable()
	Net.disconnect_room()
	HostSession.saved_lobby = {}


func _net_ended(why: String) -> void:
	var in_match := state != "menu"
	leave_online()
	if in_match:
		quit_to_menu()
	menus.online_screen(why)


## After a map reload during online play: pick the session up again (the connection stayed up).
func _resume_online() -> void:
	if Net.status != "online" or Net.role == "solo":
		return
	if Net.role == "host":
		host = HostSession.new(self, "ffa", 0)
	else:
		guest = GuestSession.new(self)
	_watch_net()
	Net.hold = false
	menus.lobby({})
	if host:
		host.broadcast_lobby()
	else:
		guest.say_ready()


## Lobby news from the session: refresh the lobby screen if it's showing.
func lobby_changed(info: Dictionary) -> void:
	if state == "menu" and menus.current in ["lobby", "connecting"]:
		menus.lobby(info)


## Start an online match (host: after seating everyone; guest: when the host says so).
func start_online_match(m: String, seats: Array, local_seat: int) -> void:
	start_match(difficulty, m, seats, local_seat)


## Online map switch: maps are built when the scene loads, so this reloads the scene. The connection
## (the Net autoload) stays up and messages wait until the session picks up again after the reload.
func load_map_online(id: String) -> void:
	if host:
		host.keep_for_reload()
	Net.hold = true
	Settings.set_v("map", id)
	menus.loading_map(Maps.get_map(id).name)
	_reload_map()


## Results screen -> lobby (online).
func back_to_lobby() -> void:
	_back_to_menu()
	if host:
		host.back_to_lobby()
	menus.lobby(host.lobby if host else (guest.lobby if guest else {}))


## Host: a guest left mid-match. Their toy stays in its seat (seats are fixed) but is gone for good.
func drop_remote(a: Actor) -> void:
	var rr = remotes.get(a)
	if rr == null:
		return
	rr.net_id = ""
	rr.state = null
	a.alive = false
	a.respawn_at = -1
	a.health = 0
	a.despawn()
	if a.model:
		a.model.visible = false
	hud.pickup("%s left the game" % a.name, "#fff6d8")


## Show a shot fired in another game (no damage).
func replay_shot(a: Actor, s: Dictionary) -> void:
	var wid := str(s.get("weapon", ""))
	if not Cfg.WEAPONS.has(wid):
		return
	if a.weapon() == null or a.weapon().id != wid:
		gear.sync(a, wid, a.slot)
	var ws := a.weapon()
	if ws == null or not a.alive:
		return
	var muzzle := Snapshot.vec(s.muzzle)
	var dir := Snapshot.vec(s.dir).normalized()
	combat.replay_shot(a, ws, Snapshot.vec(s.origin), dir, muzzle, float(s.spread))
	a.fire_kick = 1
	fx.muzzle(muzzle, dir, ws.cfg.colors.glow, 1.4 if int(ws.cfg.pellets) > 1 or ws.id == "crayonCannon" else 0.8)
	if muzzle.distance_to(r.camera.global_position) < 80:
		audio.gunshot(ws.id, muzzle, false)


## Show an ability used in another game. Only the Mesh Shield needs it; the rest is in the snapshots.
func remote_ability(a: Actor, ab: Dictionary) -> void:
	if str(ab.get("id", "")) != "shield":
		return
	if not a.has("shield"):
		a.abilities = Cfg.CLASSES.medium.abilities.duplicate()  # only Mediums carry the Mesh Shield
	a.shield_ready_at = 0
	Abilities.try_shield(a, time, {"combat": combat, "phys": phys, "audio": audio}, float(ab.get("yaw", a.yaw)))


## Guest: the host (re)spawned or revived a toy here.
func spawn_at(a: Actor, pos: Vector3, yaw: float, revived: bool, by) -> void:
	_respawn(a, false, {"pos": pos, "yaw": yaw})
	if not revived:
		return
	a.health = a.revive_health()
	if player and a == player.actor:
		hud.announce("Back in the fight!", ("%s revived you" % by.name) if by else "", 2)


## Put the toy box marker where the match says it is.
func place_hill() -> void:
	var h = match_.hill
	if h != null:
		hill_zone.place(h.pos, h.site.radius, h.site.height)


## Guest: wooden blocks fall where the host's do.
func block_drop_at(spots: Array) -> void:
	if map.blockDrops:
		ambient.block_drop(nav, spots.size(), spots)


## Dev test of online play (two copies of the game, see CLAUDE.md):
##   --online=host[:guests] [--room=CODE] [--server=URL] [--autotest=<mode>] [--seconds=N]
##   --online=guest --room=CODE [--server=URL] [--seconds=N]
## The host waits for the guests, starts the match and both sides play by themselves (walk, aim at the
## nearest enemy, fire), then each prints what it saw.
## Online test helper: blast the hard wall panel nearest `pa` three times, with this game's own authority
## (the host applies it, a guest claims it).
func _test_blow_wall(pa: Actor, role: String) -> void:
	var best := -1
	var bd := INF
	for p in destruction.pieces:
		if p.cls != "hard" or p.broken:
			continue
		var d: float = ((p.mn + p.mx) / 2 as Vector3).distance_to(pa.pos)
		if d < bd and (role == "host" or d > 0.0):
			bd = d
			best = p.id
	if best < 0:
		return
	var pc: Dictionary = destruction.pieces[best]
	var c: Vector3 = (pc.mn + pc.mx) / 2
	var shell := {"cfg": Cfg.WEAPONS.crayonCannon, "color": "#e63946", "shooter": pa, "power": 1.0}
	for i in 4:
		combat._auth = combat.local_auth
		combat.explode(c + Vector3(0, 0, 0.4), Vector3.BACK, shell, null)
		combat._auth = "full"
		combat._flush_claims()
	print("[online] %s: blew wall piece %d" % [role, best])


func _online_test(role_arg: String, m: String, secs: float, shots: String) -> void:
	var parts := role_arg.split(":")
	var role := parts[0]
	var want := int(parts[1]) if parts.size() > 1 else 1
	var code := "TEST"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--room="):
			code = a.trim_prefix("--room=")
		elif a.begins_with("--class="):
			Loadout.set_cls(a.trim_prefix("--class="))
	if m == "training":
		m = "ffa"
	await get_tree().create_timer(0.5).timeout
	var t0 := Time.get_ticks_msec()
	if role == "host":
		if host == null:
			host_room(code, m, 3)
		while Net.status != "online" and Time.get_ticks_msec() - t0 < 15000:
			await get_tree().process_frame
			if not is_inside_tree():
				return
		print("[online] host status %s room %s via %s" % [Net.status, Net.room, Net.url.split("?")[0]])
		while (Net.peers.size() < want or host.loading_count() > 0) and Time.get_ticks_msec() - t0 < 120000:
			await get_tree().process_frame
			if not is_inside_tree():
				return
		print("[online] host: %d guest(s) in the lobby, %d still loading" % [Net.peers.size(), host.loading_count()])
		for a in OS.get_cmdline_user_args():
			# --lobbymap=<id>: switch the room to another map from the lobby first (reloads this scene; the
			# connection stays up and the new scene's test carries on from here)
			if a.begins_with("--lobbymap=") and a.trim_prefix("--lobbymap=") != map.id:
				print("[online] host: switching the room to ", a.trim_prefix("--lobbymap="))
				load_map_online(a.trim_prefix("--lobbymap="))
				return
		host.start()
	else:
		if guest == null:
			join_room(code)
		while not (guest and guest.started()) and Time.get_ticks_msec() - t0 < 120000:
			if Net.status == "error":
				print("[online] guest failed: ", Net.last_error)
				get_tree().quit(1)
				return
			await get_tree().process_frame
			if not is_inside_tree():
				return  # the scene reloaded onto the host's map: the new scene's test carries on
		print("[online] guest: in the match, seat %d of %d, map %s, rtt %.0f ms" % [guest.local_seat if guest else -1, actors.size(), map.id, Net.rtt])
	var hits := {"dealt": 0, "taken": 0}
	var moved := {}
	var last := {}
	events.on("damage", func(d: Dictionary) -> void:
		if player and d.attacker == player.actor and d.target != player.actor:
			hits.dealt += 1
		if player and d.target == player.actor:
			hits.taken += 1)
	var start := Time.get_ticks_msec()
	var frames := 0
	var recv0: int = Net.received
	while (Time.get_ticks_msec() - start) / 1000.0 < secs and state in ["playing", "paused", "results"]:
		await get_tree().process_frame
		if not is_inside_tree():
			return
		frames += 1
		if state != "playing" or player == null:
			continue
		var pa := player.actor
		# aim at the nearest live enemy that can be seen
		var best: Actor = null
		var bd := INF
		for o in actors:
			if o == pa or not o.alive or not pa.is_enemy(o):
				continue
			var dd := pa.pos.distance_to(o.pos)
			if dd < bd:
				bd = dd
				best = o
		# every 3 s, step up to 6 m from that enemy so there's something to shoot (moves are trusted online)
		if best and frames % 180 == 0 and match_.phase == "playing" and (bd > 10 or not phys.los(pa.eye_pos(), best.chest_pos(), true)):
			var away := Vector3(pa.pos.x - best.pos.x, 0, pa.pos.z - best.pos.z)
			away = away.normalized() if away.length() > 0.1 else Vector3.FORWARD
			pa.teleport(best.pos + away * 6 + Vector3(0, 0.2, 0))
		input._down["KeyW"] = frames % 240 < 150
		input._down["Mouse0"] = best != null and frames % 30 < 22
		if best != null and frames % 30 == 0:
			input._pressed["Mouse0"] = true  # semi-auto blasters fire on a fresh press
		if frames % 120 == 0:
			input._pressed["Space"] = true
		if best:
			var dv := best.chest_pos() - pa.eye_pos()
			pa.yaw = atan2(-dv.x, -dv.z)
			pa.pitch = atan2(dv.y, Vector2(dv.x, dv.z).length())
		for o in actors:
			if o != pa and o.alive:
				if last.has(o):
					moved[o] = moved.get(o, 0.0) + (o.pos as Vector3).distance_to(last[o])
				last[o] = o.pos
		if shots != "" and frames == 200:
			_shot(shots + "/online_%s.png" % role)
		# destruction sync: the host blows a wall panel near it at ~5 s, the guest one near it at ~7 s
		if frames == (300 if role == "host" else 420):
			_test_blow_wall(pa, role)
		# a guest claim for a piece that doesn't exist and one that's already gone: the host must ignore both
		if role == "guest" and frames == 600 and destruction.broken_ids().size():
			Net.send_game({"g": "gpiece", "id": 99999, "dmg": 50, "kind": "blast"})
			Net.send_game({"g": "gpiece", "id": destruction.broken_ids()[0], "dmg": 50, "kind": "blast"})
		if frames % 300 == 0:
			var ws := pa.weapon()
			print("[online] %s dbg: state %s phase %s alive %s best %s %.1f m los %s weapon %s mag %d fire %s" % [role, state, match_.phase, pa.alive, best.name if best else "-", bd, phys.los(pa.eye_pos(), best.chest_pos(), true) if best else false, ws.id if ws else "-", ws.mag if ws else -1, input.act("fire")])
	var pa2: Actor = player.actor if player else null
	var mv := 0.0
	for o in moved:
		mv += moved[o]
	print("[online] %s: %d frames, %d messages in, %d remotes, others moved %.0f m in total" % [role, frames, Net.received - recv0, remotes.size(), mv])
	if pa2:
		print("[online] %s: me pops %d deaths %d hp %.0f | my hits shown %d, damage taken events %d | rtt %.0f ms" % [role, pa2.kills, pa2.deaths, pa2.health, hits.dealt, hits.taken, Net.rtt])
	var score := []
	for o in actors:
		score.append("%s %d/%d%s" % [o.name, o.kills, o.deaths, " (remote)" if remotes.has(o) else ""])
	print("[online] %s: scoreboard %s | phase %s, time left %.0f" % [role, ", ".join(score), match_.phase, match_.time_left])
	var obj := ""
	if match_.hill != null:
		obj = "toy box at %s owner %d" % [match_.hill.site.name, match_.hill.owner]
	for sec in match_.sectors:
		obj += "%s:%d " % [sec.def.name.substr(0, 6), sec.owner]
	print("[online] %s: team scores %s %s" % [role, str(match_.team_scores.map(func(x): return snappedf(x, 0.1))), obj])
	print("[online] %s: broken %s" % [role, str(Array(destruction.broken_ids()))])
	for o in actors:
		if o.is_player or remotes.has(o):
			print("[online] %s: %s class %s max %.0f" % [role, o.name, o.cls, o.max_health])
	print("[online] %s: cracked %s" % [role, str(Array(destruction.cracked_ids()))])
	if host:
		print("[online] host: applied %d guest states, %d hit claims, %d replayed shots" % [host.stats.states, host.stats.claims, host.stats.shots])
		print("[online] host: applied %d piece claims, ignored %d stale ones" % [host.stats.get("pieces", 0), host.stats.get("stale_pieces", 0)])
	if guest:
		print("[online] guest: %d snapshots, %d events, sent %d hit claims, %d shots" % [guest.stats.snaps, guest.stats.events, guest.stats.claims, guest.stats.shots])
	if role == "host":
		# let the guests finish and leave first (closing the room would end their match)
		var tw := Time.get_ticks_msec()
		while Net.peers.size() > 0 and Time.get_ticks_msec() - tw < 20000:
			await get_tree().process_frame
	printerr("[online] %s: quit_to_menu" % role)
	quit_to_menu()
	printerr("[online] %s: back in the menu" % role)
	await get_tree().create_timer(0.5).timeout
	printerr("[online] %s: quitting" % role)
	get_tree().quit()


## Slow flyover of the map behind the menus.
func _menu_camera(t: float) -> void:
	var cam := r.camera
	var a := t * 0.045
	var mc: Dictionary = map.menuCam
	var pos := Vector3(2 + cos(a) * (mc.r - 1), mc.h + sin(a * 1.7) * 2.5, 1 + sin(a) * (mc.r + 1))
	var look := Vector3(2 + cos(a + 2.2) * 6, 3, 1 + sin(a + 2.2) * 6)
	cam.look_at_from_position(pos, look, Vector3.UP)
	var vs := cam.get_viewport().get_visible_rect().size
	cam.fov = Player.h_fov_to_v(75, vs.x / maxf(1, vs.y))

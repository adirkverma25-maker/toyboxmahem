extends Node
## Dev tests for destructible pieces (Destruction, Debris, nav blockers, blast rules).
## Run: Godot --headless --path . res://tools/test_destruction.tscn   -> prints "[test] N failures"

var failures := 0
var phys: Phys


func _ready() -> void:
	await _run()
	print("[test] %d failures" % failures)
	get_tree().quit(failures)


func check(cond: bool, name: String) -> void:
	if cond:
		print("ok   ", name)
	else:
		failures += 1
		print("FAIL ", name)


func _fresh() -> Destruction:
	if phys:
		phys.queue_free()
		await get_tree().process_frame
	phys = Phys.new()
	add_child(phys)
	var d := Destruction.new(phys)
	phys.add_child(d)
	return d


func _ray_hits(from: Vector3, to: Vector3) -> bool:
	return not phys.raycast(from, (to - from).normalized(), from.distance_to(to)).is_empty()


func _run() -> void:
	var mat := StandardMaterial3D.new()
	var d := await _fresh()
	var glass := d.add_piece(Vector3(0, 0, 0), Vector3(1, 2, 0.1), mat, "glass", "g", "glass")
	var soft := d.add_piece(Vector3(3, 0, 0), Vector3(4, 2, 0.4), mat, "soft", "g", "wood")
	var hard := d.add_piece(Vector3(6, 0, 0), Vector3(8, 3, 0.4), mat, "hard", "w", "wood")
	d.build()
	await phys.refresh()

	check(d.damage(glass, 25, "bullet", Vector3(0.5, 1, 0), Vector3.BACK) and d.is_broken(glass), "glass_breaks_on_one_bullet")

	var before: float = d.pieces[hard].hp
	check(not d.damage(hard, 9999, "bullet", Vector3(7, 1, 0), Vector3.BACK) and d.pieces[hard].hp == before and before == 700.0, "hard_ignores_bullets")

	check(d.damage(soft, 80, "blast", Vector3(3.5, 1, 0), Vector3.BACK), "soft_blast_triples")

	d.reset()
	await phys.refresh()
	d.damage(soft, 90, "bullet", Vector3(3.5, 1, 0), Vector3.BACK)
	check(d.is_cracked(soft) and not d.is_broken(soft), "cracked_stage")

	check(_ray_hits(Vector3(7, 1, -2), Vector3(7, 1, 2)), "hard_piece_blocks_rays")
	d.break_piece(hard, Vector3.FORWARD)
	await phys.refresh()
	check(not _ray_hits(Vector3(7, 1, -2), Vector3(7, 1, 2)), "collider_removed_on_break")

	d.reset()
	await phys.refresh()
	var all_full := true
	for p in d.pieces:
		all_full = all_full and p.hp == p.max_hp and not p.broken
	check(d.broken_ids().is_empty() and all_full and _ray_hits(Vector3(7, 1, -2), Vector3(7, 1, 2)), "reset_restores_everything")

	d.apply_broken([hard, hard, 999])
	check(d.broken_ids() == PackedInt32Array([hard]), "apply_broken_idempotent")

	var hit := phys.raycast(Vector3(0.5, 1, -2), Vector3.BACK, 4)
	check(not hit.is_empty() and d.piece_of(hit.collider) == glass, "piece_of_maps_collider")

	# Builder: breakable boxes go to Destruction, or stay plain static boxes when there is none
	var d2 := await _fresh()
	var B := Builder.new(Batcher.new(), phys)
	var plain := B.breakable_box([0, 0, 0], [1, 1, 1], mat, "soft", "x")
	B.destruction = d2
	var real := B.breakable_box([3, 0, 0], [4, 1, 1], mat, "soft", "x")
	await phys.refresh()
	check(plain == -1 and real == 0 and d2.pieces.size() == 1, "builder_breakable_box_routes")
	check(_ray_hits(Vector3(0.5, 0.5, -2), Vector3(0.5, 0.5, 2)), "builder_fallback_is_solid")

	# Debris: pooled chunks, never more than MAX alive, oldest recycled
	var deb := Debris.new()
	add_child(deb)
	for i in 20:
		deb.burst(Vector3(i, 0, 0), Vector3(i + 1, 2, 0.4), Color.WHITE, "soft", Vector3.FORWARD)
	check(deb.live_count() == Debris.MAX and Debris.MAX == 80, "debris_caps_at_80")
	check(deb.mm.visible_instance_count == Debris.MAX, "debris_visible_count_tracks_live")
	deb.clear()
	check(deb.live_count() == 0 and deb.mm.visible_instance_count == 0, "debris_clear")

	# breaking a piece throws debris once the effects are hooked up
	var d3 := await _fresh()
	var wall := d3.add_piece(Vector3(0, 0, 0), Vector3(2, 3, 0.4), mat, "hard", "w", "wood")
	d3.build()
	d3.fx_hooks(deb, null, null)
	d3.break_piece(wall, Vector3.BACK)
	check(deb.live_count() >= 4, "break_throws_debris")
	deb.clear()

	# blasts: falloff with distance, and a standing piece shields the ones behind it
	var d4 := await _fresh()
	var near_p := d4.add_piece(Vector3(1, 0, -1), Vector3(1.4, 2, 1), mat, "soft", "a", "wood")
	var far_p := d4.add_piece(Vector3(2.5, 0, -1), Vector3(2.9, 2, 1), mat, "soft", "a", "wood")
	var side_p := d4.add_piece(Vector3(-1, 0, 2.6), Vector3(1, 2, 3.0), mat, "soft", "a", "wood")
	var edge_p := d4.add_piece(Vector3(-4.2, 0, -1), Vector3(-3.8, 2, 1), mat, "soft", "a", "wood")
	d4.build()
	await phys.refresh()
	d4.blast(Vector3(0, 1, 0), 4.5, 40.0)
	check(d4.pieces[near_p].hp < 220.0 and d4.pieces[far_p].hp == 220.0, "blast_is_blocked_by_nearer_piece")
	var lost_side: float = 220.0 - d4.pieces[side_p].hp
	var lost_edge: float = 220.0 - d4.pieces[edge_p].hp
	check(lost_side > lost_edge and lost_edge > 0, "blast_falloff")

	# nav: a wall whose only gap is a breakable panel; routes through it open when it breaks
	var d5 := await _fresh()
	phys.box(Vector3(0, -0.5, 0), Vector3(10, 0.5, 10), "wood")
	phys.box(Vector3(3.2, 1.5, -5.5), Vector3(0.2, 1.5, 4.5), "wood")
	phys.box(Vector3(3.2, 1.5, 5.5), Vector3(0.2, 1.5, 4.5), "wood")
	var gap := d5.add_piece(Vector3(3.0, 0, -1.0), Vector3(3.4, 3, 1.0), mat, "soft", "gap", "wood")
	d5.build()
	await phys.refresh()
	var nav := NavGraph.new(phys)
	nav.destruction = d5
	await nav.build_async(AABB(Vector3(-9, -1, -9), Vector3(18, 6, 18)))
	var a_id := nav.nearest(Vector3(-5, 0, 0), false)
	var b_id := nav.nearest(Vector3(8, 0, 0), false)
	check(a_id >= 0 and b_id >= 0 and nav.path(a_id, b_id).is_empty(), "path_blocked_until_broken")
	var inside_ok := true
	var saw_blocked := false
	for n in nav.nodes:
		if not nav.node_open(n.id):
			saw_blocked = true
			inside_ok = inside_ok and not nav.near(n.pos, 0.1).has(n.id)
	check(saw_blocked and inside_ok, "near_skips_nodes_inside_pieces")
	d5.break_piece(gap, Vector3.RIGHT)
	nav.open_piece(gap)
	var route := nav.path(a_id, b_id)
	var through := false
	for id in route:
		var np: Vector3 = nav.nodes[id].pos
		through = through or (np.x > 1.5 and np.x < 4.5 and absf(np.z) < 1.6)
	check(route.size() > 0 and through, "path_opens_through_the_hole")
	nav._save_cache("dtest")
	var nav2 := NavGraph.new(phys)
	nav2.destruction = d5
	var same := nav2._load_cache("dtest") and nav2.nodes.size() == nav.nodes.size()
	if same:
		for i in nav.nodes.size():
			same = same and nav2.nodes[i].blockers == nav.nodes[i].blockers
			for j in nav.nodes[i].links.size():
				same = same and nav2.nodes[i].links[j].blockers == nav.nodes[i].links[j].blockers
	check(same, "cache_roundtrip_keeps_blockers")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(nav._cache_path("dtest")))

	# pieces marked "rests" fall with whatever holds them up; plain stacked pieces don't
	var d6 := await _fresh()
	var base_p := d6.add_piece(Vector3(0, 0, 0), Vector3(2, 1, 1), mat, "soft", "s", "wood")
	var top_p := d6.add_piece(Vector3(0.5, 1, 0), Vector3(1.5, 1.6, 1), mat, "soft", "s", "wood", {"rests": true})
	var cap_p := d6.add_piece(Vector3(0.6, 1.6, 0.2), Vector3(1.4, 2.0, 0.8), mat, "soft", "s", "wood", {"rests": true})
	var low_p := d6.add_piece(Vector3(4, 0, 0), Vector3(6, 1, 1), mat, "hard", "t", "wood")
	var band_p := d6.add_piece(Vector3(4, 1, 0), Vector3(6, 2, 1), mat, "hard", "t", "wood")
	d6.build()
	d6.break_piece(base_p, Vector3.UP)
	check(d6.is_broken(top_p) and d6.is_broken(cap_p), "resting_pieces_fall_with_support")
	d6.break_piece(low_p, Vector3.UP)
	check(not d6.is_broken(band_p), "stacked_wall_bands_do_not_cascade")

	# review fixes ---------------------------------------------------------------
	# a lintel over a doorway rests on the panels beside it (nothing below): it falls when one goes
	var d7 := await _fresh()
	var left_p := d7.add_piece(Vector3(0, 0, 0), Vector3(1, 3, 0.4), mat, "hard", "w", "wood")
	var right_p := d7.add_piece(Vector3(2.5, 0, 0), Vector3(3.5, 3, 0.4), mat, "hard", "w", "wood")
	var lintel_p := d7.add_piece(Vector3(1, 2.2, 0), Vector3(2.5, 3, 0.4), mat, "hard", "w", "wood", {"rests": true})
	d7.build()
	d7.break_piece(left_p, Vector3.BACK)
	check(d7.is_broken(lintel_p) and not d7.is_broken(right_p), "lintel_falls_with_side_support")

	# several breaks in one frame rebuild the group's mesh once, on the next frame
	var d8 := await _fresh()
	var ids := []
	for i in 4:
		ids.append(d8.add_piece(Vector3(i, 0, 0), Vector3(i + 1, 2, 0.4), mat, "soft", "row", "wood"))
	d8.build()
	await get_tree().process_frame
	var r0: int = d8.rebuilds
	for id in ids.slice(0, 3):
		d8.break_piece(id, Vector3.BACK)
	var immediate: int = d8.rebuilds - r0
	await get_tree().process_frame
	check(immediate == 0 and d8.rebuilds - r0 == 1, "group_rebuilt_once_per_frame")

	# guests learn about cracks from the host
	d8.apply_cracked([ids[3]])
	check(d8.is_cracked(ids[3]) and not d8.is_broken(ids[3]), "apply_cracked")
	var cracked_list: Array = []
	d8.on_crack = func(id: int) -> void: cracked_list.append(id)
	d8.reset()
	d8.damage(ids[0], 120, "bullet", Vector3(0.5, 1, 0), Vector3.BACK)
	check(cracked_list == [ids[0]] and d8.cracked_ids() == PackedInt32Array([ids[0]]), "on_crack_reports_new_cracks")

	# marks on a piece go with it when it breaks (decals are flat quads, they'd hang in the hole)
	var d9 := await _fresh()
	var marked := d9.add_piece(Vector3(0, 0, 0), Vector3(2, 3, 0.4), mat, "hard", "m", "wood")
	d9.build()
	var fxe := Effects.new()
	add_child(fxe)
	d9.fx_hooks(deb, fxe, null)
	fxe.impacts.add(Vector3(1, 1, 0.4), Vector3.BACK, 0.3, "#000000", 30)
	fxe.splats.add(Vector3(1, 2, 0.4), Vector3.BACK, 1.0, "#ff0000", 30)
	fxe.impacts.add(Vector3(6, 1, 0.4), Vector3.BACK, 0.3, "#000000", 30)
	var box := AABB(Vector3(-0.2, -0.2, -0.2), Vector3(2.4, 3.4, 0.8))
	d9.break_piece(marked, Vector3.BACK)
	check(fxe.impacts.count_in(box) == 0 and fxe.splats.count_in(box) == 0 and fxe.impacts.count_in(AABB(Vector3(5, 0, 0), Vector3(2, 2, 1))) == 1, "marks_cleared_on_break")
	deb.clear()

	# break sounds exist for every class
	var ok := true
	for c in Destruction.CLASSES:
		ok = ok and not AudioEngine._r_break(c).is_empty()
	check(ok, "break_sound_recipes")

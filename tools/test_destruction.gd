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

	# break sounds exist for every class
	var ok := true
	for c in Destruction.CLASSES:
		ok = ok and not AudioEngine._r_break(c).is_empty()
	check(ok, "break_sound_recipes")

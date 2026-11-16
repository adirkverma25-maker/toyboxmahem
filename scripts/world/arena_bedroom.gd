class_name ArenaBedroom
## Bedroom Brawl (port of src/world/Arena.ts): one big bedroom at toy scale.

const ROOM := {"x0": -32.0, "x1": 32.0, "z0": -36.0, "z1": 36.0, "h": 30.0}
## The high wall shelf that runs around the whole room. The toy train runs along the wall side.
const SHELF := {"y": 21.0, "depth": 4.2, "track_inset": 0.95}
## Jump pads up to the shelf (landing about 2.6 m out from the wall) and ziplines (feet positions at each end).
const PADS := [
	{"pos": Vector3(3.2, 0, 26), "to": Vector3(3.2, 21, 33.4)},  # south
	{"pos": Vector3(22, 0, 10.2), "to": Vector3(29.4, 21, 10.2)},  # east
	{"pos": Vector3(-21, 0, -9.6), "to": Vector3(-29.4, 21, -9.6)},  # west
	{"pos": Vector3(-22.5, 6, -15.5), "to": Vector3(-22.5, 21, -33.4)},  # bed -> north shelf
	{"pos": Vector3(12.4, 0, -6), "to": Vector3(12.4, 21, -33.4)},  # desk side -> north shelf
]
const ZIPS := [
	{"a": Vector3(-10, 22.0, -32.3), "b": Vector3(-15, 6.6, -15)},  # north shelf <-> blanket bridge
	{"a": Vector3(28.3, 22.0, -23), "b": Vector3(16.5, 9.5, -29)},  # east shelf (north of the closet) <-> desk outpost
	{"a": Vector3(0, 22.0, 32.3), "b": Vector3(2, 0.7, 11)},  # south shelf <-> play rug
	{"a": Vector3(-28.3, 22.0, 20), "b": Vector3(-9.5, 0.7, -1)},  # west shelf <-> rug edge
	{"a": Vector3(17, 9.5, -29), "b": Vector3(-22, 6.6, -22)},  # desk outpost <-> bed fortress
]
const BRICK_COLORS := ["#d6342c", "#f2c12e", "#1f6fd1", "#2f9e44", "#f4f4f4", "#f08c1f", "#7b3fb5"]


static func E(x: float, y: float, z: float) -> Basis:
	return U.euler(x, y, z)


## Cloth panel with gentle sway (blankets, curtains, drapes); pivot at the top edge.
static func sway_cloth(width: float, height: float, mat: StandardMaterial3D, seg_w: int, seg_h: int, amp: float, speed: float, sag := 0.0) -> MeshInstance3D:
	var g := Geo.plane(width, height, seg_w, seg_h).translate(0, -height / 2.0, 0)
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/cloth.gdshader")
	sm.set_shader_parameter("albedo", mat.albedo_color)
	if mat.albedo_texture:
		sm.set_shader_parameter("albedo_tex", mat.albedo_texture)
		sm.set_shader_parameter("use_tex", true)
	sm.set_shader_parameter("roughness", mat.roughness)
	sm.set_shader_parameter("width", width)
	sm.set_shader_parameter("height", height)
	sm.set_shader_parameter("amp", amp)
	sm.set_shader_parameter("speed", speed)
	sm.set_shader_parameter("sag", sag)
	sm.set_shader_parameter("phase", randf() * 10.0)
	var mi := MeshInstance3D.new()
	mi.mesh = g.to_mesh(sm)
	mi.extra_cull_margin = 2.0
	return mi


static func omni(root: Node3D, color: String, intensity: float, distance: float, decay: float, pos: Vector3) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = U.col(color)
	l.light_energy = intensity * Lighting.POINT_SCALE
	l.omni_range = distance
	l.omni_attenuation = decay * 0.5
	l.position = pos
	l.shadow_enabled = false
	root.add_child(l)
	return l


static func build(root: Node3D, phys: Phys) -> Dictionary:
	var M := Mats.env()
	var batch := Batcher.new()
	var B := Builder.new(batch, phys)
	var animated: Array[Callable] = []
	var point_lights: Array = []
	var rnd := U.seeded(2024)
	var X0: float = ROOM.x0
	var X1: float = ROOM.x1
	var Z0: float = ROOM.z0
	var Z1: float = ROOM.z1
	var RH: float = ROOM.h

	# ---------------------------------------------------------------- ROOM SHELL
	B.box([X0 - 1, -1, Z0 - 1], [X1 + 1, 0, Z1 + 1], M.floor, "wood", {"tile": 1.0 / 16})
	B.box([X0 - 1, RH, Z0 - 1], [X1 + 1, RH + 1, Z1 + 1], M.ceiling, "wood", {"cast": false})
	var WIN := {"x0": -6.0, "x1": 10.0, "y0": 12.0, "y1": 26.0, "z": Z0}
	var wx0: float = WIN.x0
	var wx1: float = WIN.x1
	var wy0: float = WIN.y0
	var wy1: float = WIN.y1
	B.box([X0 - 1, 0, Z0 - 1], [wx0, RH, Z0], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([wx1, 0, Z0 - 1], [X1 + 1, RH, Z0], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([wx0, 0, Z0 - 1], [wx1, wy0, Z0], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([wx0, wy1, Z0 - 1], [wx1, RH, Z0], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([X0 - 1, 0, Z1], [X1 + 1, RH, Z1 + 1], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([X0 - 1, 0, Z0], [X0, RH, Z1], M.wallpaper, "wood", {"tile": 1.0 / 12})
	B.box([X1, 0, Z0], [X1 + 1, RH, Z1], M.wallpaper, "wood", {"tile": 1.0 / 12})
	# baseboards
	B.box([X0, 0, Z0], [X1, 1.1, Z0 + 0.35], M.trim, "")
	B.box([X0, 0, Z1 - 0.35], [X1, 1.1, Z1], M.trim, "")
	B.box([X0, 0, Z0], [X0 + 0.35, 1.1, Z1], M.trim, "")
	B.box([X1 - 0.35, 0, Z0], [X1, 1.1, Z1], M.trim, "")
	# window frame, mullions, sill
	B.box([wx0 - 0.6, wy0 - 0.6, Z0 - 0.2], [wx0, wy1 + 0.6, Z0 + 0.5], M.trim, "wood")
	B.box([wx1, wy0 - 0.6, Z0 - 0.2], [wx1 + 0.6, wy1 + 0.6, Z0 + 0.5], M.trim, "wood")
	B.box([wx0, wy1, Z0 - 0.2], [wx1, wy1 + 0.6, Z0 + 0.5], M.trim, "wood")
	B.box([(wx0 + wx1) / 2 - 0.25, wy0, Z0 - 0.6], [(wx0 + wx1) / 2 + 0.25, wy1, Z0 - 0.2], M.trim, "wood")
	B.box([wx0, (wy0 + wy1) / 2 - 0.25, Z0 - 0.6], [wx1, (wy0 + wy1) / 2 + 0.25, Z0 - 0.2], M.trim, "wood")
	B.box([wx0 - 1.2, wy0 - 0.5, Z0 - 0.6], [wx1 + 1.2, wy0, Z0 + 2.4], M.trim, "wood")
	# sky outside
	var sky_m := Mats.basic("#ffffff", Tex.sky())
	sky_m.disable_fog = true
	var sky := Geo.plane(90, 45).mesh_instance(sky_m, Vector3(2, 18, Z0 - 14), Basis(), false)
	root.add_child(sky)
	# curtains
	for x in [wx0 - 2.2, wx1 + 2.2]:
		var cl := sway_cloth(4, 18, M.fabric_a, 8, 16, 0.35, 0.9)
		cl.position = Vector3(x, 28.5, Z0 + 0.9)
		root.add_child(cl)
	B.cyl([wx0 - 5, 28.6, Z0 + 0.9], 0.18, 0.1, M.metal_steel, "")
	B.obox([(wx0 + wx1) / 2, 28.6, Z0 + 0.9], [wx1 - wx0 + 9, 0.3, 0.3], Basis(), M.metal_steel, "")

	# high wall shelf
	var SH: float = SHELF.y
	var SD: float = SHELF.depth
	var shelf_mat := M.desk
	B.box([X0, SH - 0.5, Z0], [X1, SH, Z0 + SD], shelf_mat, "wood")
	B.box([X0, SH - 0.5, Z1 - SD], [X1, SH, Z1], shelf_mat, "wood")
	B.box([X0, SH - 0.5, Z0 + SD], [X0 + SD, SH, Z1 - SD], shelf_mat, "wood")
	B.box([X1 - SD, SH - 0.5, Z0 + SD], [X1, SH, Z1 - SD], shelf_mat, "wood")
	var stripe := Mats.plastic("#ffd23f", {"rough": 0.4})
	for ab in [
		[[X0 + SD, SH - 0.52, Z0 + SD - 0.12], [X1 - SD, SH + 0.02, Z0 + SD]],
		[[X0 + SD, SH - 0.52, Z1 - SD], [X1 - SD, SH + 0.02, Z1 - SD + 0.12]],
		[[X0 + SD - 0.12, SH - 0.52, Z0 + SD], [X0 + SD, SH + 0.02, Z1 - SD]],
		[[X1 - SD, SH - 0.52, Z0 + SD], [X1 - SD + 0.12, SH + 0.02, Z1 - SD]],
	]:
		B.box(ab[0], ab[1], stripe, "")
	# shelf brackets
	var x := -28
	while x <= 28:
		if not (x > wx0 - 1 and x < wx1 + 1):
			B.box([x - 0.2, SH - 2.6, Z0], [x + 0.2, SH - 0.5, Z0 + SD - 0.6], M.trim, "")
			B.box([x - 0.2, SH - 2.6, Z1 - SD + 0.6], [x + 0.2, SH - 0.5, Z1], M.trim, "")
		x += 8
	var z := -24
	while z <= 24:
		B.box([X0, SH - 2.6, z - 0.2], [X0 + SD - 0.6, SH - 0.5, z + 0.2], M.trim, "")
		B.box([X1 - SD + 0.6, SH - 2.6, z - 0.2], [X1, SH - 0.5, z + 0.2], M.trim, "")
		z += 8
	# (the long ramps up to the shelf are gone: jump pads and ziplines lead up there now)

	# south wall door + crayon drawings
	B.box([-5, 0, Z1 - 0.3], [5, 19.4, Z1], Mats.plastic("#f7f1e3", {"rough": 0.6, "clearcoat": 0.1}), "")
	B.box([-5.6, 0, Z1 - 0.45], [-5, 20, Z1], M.trim, "")
	B.box([5, 0, Z1 - 0.45], [5.6, 20, Z1], M.trim, "")
	B.box([-5, 19.4, Z1 - 0.45], [5, 20, Z1], M.trim, "")
	B.geo(Geo.sphere(0.45, 16, 12), Mats.metal("#d4af37", 0.25), [3.8, 10, Z1 - 0.7])
	_add_drawings(root)

	# ---------------------------------------------------------------- PLAY RUG (center)
	if true:
		var rug := Geo.cylinder(12, 12, 0.08, 64).mesh_instance(M.carpet, Vector3(2, 0.04, 1))
		root.add_child(rug)
		phys.cylinder(Vector3(2, 0.04, 1), 0.04, 12, "carpet")
		var block_cols := ["#e63946", "#2a9d8f", "#f4a261", "#457b9d", "#e9c46a", "#8ab17d"]
		var S := 1.2
		var letters := "TOYBOXMAYHEM"
		var li := 0
		for tier_def in [[3, 0], [2, 1], [1, 2]]:
			var n: int = tier_def[0]
			var tier: int = tier_def[1]
			var off := (3 - n) * S * 0.5
			for i in n:
				for j in n:
					var bx := 2 - 1.5 * S + off + i * S + S / 2
					var bz := 1 - 1.5 * S + off + j * S + S / 2
					var by := tier * S
					var bc: String = block_cols[(i + j * 2 + tier) % block_cols.size()]
					_letter_block(B, [bx, by + S / 2, bz], S * 0.98, bc, letters[li % letters.length()], rnd.next() * 0.15 - 0.075)
					li += 1
			phys.box(Vector3(2, tier * S + S / 2, 1), Vector3(n * S / 2, S / 2, n * S / 2), "wood")
		# giant striped ball
		B.geo(Geo.sphere(2, 32, 20), _stripe_ball_mat(), [-5, 2, 6.5], E(0.4, 0.3, 0.2))
		phys.ball(Vector3(-5, 2, 6.5), 2, "plastic")
		# toy drum
		B.cyl([9, 0, -4], 1.9, 2.2, Mats.plastic("#d62828"), "plastic", 32)
		B.cyl([9, 2.2, -4], 1.95, 0.08, Mats.rubber("#f8f4e3"), "", 32)
		for i in 12:
			var a := float(i) / 12 * TAU
			B.obox([9 + cos(a) * 1.92, 1.1, -4 + sin(a) * 1.92], [0.12, 2.4, 0.12], E(0.4 * sin(i), 0, 0.4 * cos(i)), Mats.metal("#f2d16b", 0.3), "")
		B.obox([9.8, 2.6, -3.5], [0.18, 0.18, 3], E(0.6, 0.4, 0), Mats.plastic("#f1c40f"), "")
		# stacking rings
		B.cyl([10.5, 0, 6.5], 1.9, 0.5, Mats.plastic("#3d405b"), "", 32)
		var ring_cols := ["#e63946", "#f4a261", "#e9c46a", "#2a9d8f", "#457b9d"]
		for i in 5:
			var r := 1.7 - i * 0.28
			B.geo(Geo.torus(r - 0.35, 0.36, 12, 32), Mats.plastic(ring_cols[i]), [10.5, 0.85 + i * 0.68, 6.5], E(PI / 2, 0, 0))
		B.cyl([10.5, 0.5, 6.5], 0.35, 3.6, Mats.plastic("#3d405b"), "")
		B.geo(Geo.sphere(0.6, 16, 12), Mats.plastic("#e63946"), [10.5, 4.3, 6.5])
		phys.cylinder(Vector3(10.5, 2, 6.5), 2, 1.8, "plastic")
		# spinning top lying on its side
		B.geo(Geo.cone(1.1, 1.6, 24), Mats.plastic("#9b5de5"), [-6, 1.1, -4], E(0, 0, PI / 2 + 0.4))
		phys.cylinder(Vector3(-6, 0.9, -4), 0.8, 1.0, "plastic", E(0, 0, PI / 2))
		# scattered crayons
		var crayon_cols := ["#e63946", "#2a9d8f", "#ffbe0b", "#3a86ff", "#8338ec", "#fb5607"]
		for i in 9:
			var a := rnd.next() * TAU
			var r := 4 + rnd.next() * 6
			var cx := 2 + cos(a) * r
			var cz := 1 + sin(a) * r
			if Vector2(cx - 2, cz - 1).length() < 3.2 or Vector2(cx + 5, cz - 6.5).length() < 2.8 or Vector2(cx - 9, cz + 4).length() < 2.6 or Vector2(cx - 10.5, cz - 6.5).length() < 2.6:
				continue
			B.geo(Geo.cylinder(0.2, 0.2, 2.2, 8), Mats.plastic(crayon_cols[i % crayon_cols.size()], {"rough": 0.6, "clearcoat": 0}), [cx, 0.28, cz], E(PI / 2, 0, rnd.next() * PI))

	# ---------------------------------------------------------------- BED FORTRESS (NW)
	if true:
		var bx0 := -32.0
		var bx1 := -19.0
		var bz0 := -35.0
		var bz1 := -12.0
		B.box([bx0, 0, -36], [bx1, 12, -35], M.bed_wood, "wood", {"round": 0.4})
		B.box([bx0 + 0.6, 11.4, -36.2], [bx1 - 0.6, 12.6, -34.8], M.bed_wood, "", {"round": 0.5})
		for p in [[bx0 + 0.7, bz0 + 0.7], [bx1 - 0.7, bz0 + 0.7], [bx0 + 0.7, bz1 - 0.7], [bx1 - 0.7, bz1 - 0.7], [-25.5, -24]]:
			B.box([p[0] - 0.6, 0, p[1] - 0.6], [p[0] + 0.6, 2.7, p[1] + 0.6], M.bed_wood, "wood", {"round": 0.15})
		B.box([bx0, 2.6, bz0], [bx1, 3.6, bz1], M.bed_wood, "", {"round": 0.2})
		B.box([bx0 + 0.2, 3.6, bz0 + 0.2], [bx1 - 0.2, 5.6, bz1 - 0.2], M.sheet, "", {"round": 0.6})
		phys.box(Vector3((bx0 + bx1) / 2, 4.3, (bz0 + bz1) / 2), Vector3((bx1 - bx0) / 2, 1.7, (bz1 - bz0) / 2), "fabric")
		# quilt over the lower 2/3
		B.box([bx0 - 0.2, 5.55, -29], [bx1 + 0.2, 6.05, bz1 + 0.2], M.blanket, "", {"round": 0.25})
		var drape_e := sway_cloth(17.2, 3.3, M.blanket, 18, 5, 0.12, 0.7)
		drape_e.position = Vector3(bx1 + 0.25, 5.95, (-29 + bz1) / 2)
		drape_e.rotation.y = PI / 2
		root.add_child(drape_e)
		var drape_s := sway_cloth(13.4, 3.3, M.blanket, 14, 5, 0.12, 0.8)
		drape_s.position = Vector3((bx0 + bx1) / 2, 5.95, bz1 + 0.25)
		root.add_child(drape_s)
		# pillows (cover)
		B.box([-31.3, 6, -34.6], [-26, 7.9, -30.4], M.pillow, "fabric", {"round": 0.8})
		B.box([-25, 6, -34.6], [-19.7, 7.9, -30.4], M.pillow2, "fabric", {"round": 0.8})
		# blanket slope: solid wedge from the floor up to the mattress
		B.wedge([-9.6, 0, -27], -PI / 2, 9.6, 6, 6, M.blanket, "fabric")
		B.geo(Geo.capsule(0.45, 5, 6, 16), M.blanket, [-9.4, 0.4, -27], E(PI / 2, 0, 0))
		# under-bed clutter
		B.breakable_box([-29, 0, -22], [-26, 1.7, -17.5], M.cardboard_shoes, "soft", "bed-clutter", "cardboard", {"round": 0.05})
		B.box([-23.5, 0, -31], [-21.5, 0.8, -27], M.fabric_b, "fabric", {"round": 0.35})
		B.geo(Geo.sphere(1.1, 24, 16), _stripe_ball_mat("#ff006e", "#ffbe0b"), [-22.5, 1.1, -16.5])
		phys.ball(Vector3(-22.5, 1.1, -16.5), 1.1, "plastic")
		# toy chest + lid
		var chest_mat := Mats.textured(Tex.wood("block"), 0.5, "#e98a7a")
		B.box([-10, 0, -19], [-3, 5.5, -11], chest_mat, "wood", {"round": 0.2})
		B.box([-10.3, 5.5, -19.3], [-2.7, 6, -10.7], Mats.plastic("#f2c14e", {"rough": 0.45}), "wood", {"round": 0.15})
		B.box([-7, 4, -10.95], [-6, 5.2, -10.7], Mats.metal("#d4af37"), "")
		B.geo(Geo.torus(0.9, 0.15, 8, 20), Mats.plastic("#ffffff"), [-6.5, 2.6, -10.92])
		# cardboard ramp up to the chest
		B.slab([6, 0, -15], [-3, 6, -15], 4, 0.35, M.cardboard, "cardboard")
		B.box([5.5, 0, -17], [6.5, 0.35, -13], M.cardboard, "")
		# blanket bridge (bed -> chest)
		var bridge := sway_cloth(9.4, 4.2, M.blanket, 14, 6, 0.03, 0.6, -0.25)
		bridge.rotation = Vector3(-PI / 2, 0, 0)
		bridge.position = Vector3(-14.5, 5.92, -17.1)
		root.add_child(bridge)
		phys.box(Vector3(-14.5, 5.75, -15), Vector3(4.7, 0.2, 2.1), "fabric")
		for p in [[-19.2, -17.1], [-19.2, -12.9], [-9.8, -17.1], [-9.8, -12.9]]:
			B.geo(Geo.torus_knot(0.25, 0.08, 32, 6), Mats.plastic("#ffffff", {"rough": 0.8}), [p[0], 6.05, p[1]])

	# ---------------------------------------------------------------- DESK OUTPOST (NE)
	var screen_tex: Dictionary = {}
	if true:
		B.box([14, 7.4, -36], [32, 8, -24], M.desk, "wood", {"round": 0.12})
		for dz in [-24.6, -35.4]:
			B.box([14, 0, dz - 0.6], [15.2, 7.4, dz + 0.6], M.desk, "wood", {"round": 0.1})
		B.box([26, 0, -36], [32, 7.4, -24.3], M.desk, "wood", {"round": 0.1})
		for y in [1.2, 3.8]:
			B.box([26.4, y, -24.4], [31.6, y + 2.2, -24.2], Mats.plastic("#e9d8bf", {"rough": 0.6, "clearcoat": 0}), "")
			B.box([28.4, y + 1, -24.25], [29.6, y + 1.3, -23.9], Mats.metal("#c0c0c0"), "")
		# ruler ramp from the floor
		var ruler_mat := Mats.plastic("#f6d743", {"rough": 0.25, "clearcoat": 1})
		B.slab([2, 0, -25.6], [14, 8, -25.6], 2.6, 0.3, ruler_mat, "plastic")
		var rdir := Vector3(12, 8, 0).normalized()
		for i in range(1, 28):
			var p := Vector3(2, 0, -25.6) + rdir * (i * 0.5)
			var long := i % 4 == 0
			B.obox([p.x, p.y + 0.02, p.z - 1.3 + (0.45 if long else 0.25)], [0.06, 0.04, 0.9 if long else 0.5], E(0, 0, atan2(8, 12)), Mats.plastic("#222"), "")
		# book staircase (real steps, 0.5 tall)
		var book_cols := ["#c0392b", "#2471a3", "#229954", "#d68910", "#7d3c98", "#117a65", "#ba4a00", "#2e4053"]
		var titles := ["ATLAS", "DINOS", "SPACE", "PUZZLES", "POEMS", "BUGS", "MAPS", "ROBOTS"]
		for i in 16:
			var y0 := i * 0.5
			var z_front := -8 - i * 1.0
			var jitter := (rnd.next() - 0.5) * 0.4
			var bm := Mats.textured(Tex.book(book_cols[i % 8], titles[i % 8]), 0.6)
			B.box([14.4 + jitter, y0, -24], [19.4 + jitter * 0.5, y0 + 0.5, z_front], bm, "cardboard", {"round": 0.04})
			B.box([14.5 + jitter, y0 + 0.04, -23.95], [19.3 + jitter * 0.5, y0 + 0.46, z_front - 0.04], M.paper, "")
		# keyboard (high ground)
		B.box([16, 8, -31], [28, 8.45, -27], Mats.plastic("#3a3f4b", {"rough": 0.4}), "", {"round": 0.2})
		phys.box(Vector3(22, 8.45, -29), Vector3(6, 0.45, 2), "plastic")
		var rows := [
			["ESC", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "=", "⌫"],
			["TAB", "Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "[", "]", "\\"],
			["CAPS", "A", "S", "D", "F", "G", "H", "J", "K", "L", ";", "'", "⏎", "⏎"],
			["⇧", "Z", "X", "C", "V", "B", "N", "M", ",", ".", "/", "⇧", "▲", "FN"],
		]
		var key_geo := Geo.rounded_box(0.72, 0.42, 0.78, 2, 0.1)
		var key_mat := Mats.plastic("#f1f1ee", {"rough": 0.35})
		for r in 4:
			for c in 14:
				B.geo(key_geo, key_mat, [16.43 + c * 0.855, 8.66, -30.5 + r * 0.98])
		var lab_m := Mats.basic("#ffffff", Tex.keyboard_labels(rows), true)
		var labels := Geo.plane(14 * 0.855, 4 * 0.98).mesh_instance(lab_m, Vector3(16.43 - 0.4275 + (14 * 0.855) / 2, 8.875, -30.5 - 0.49 + (4 * 0.98) / 2), E(-PI / 2, 0, 0), false)
		root.add_child(labels)
		# monitor
		B.box([20.5, 8, -35.2], [23.5, 8.3, -32], Mats.plastic("#2b2d33"), "plastic", {"round": 0.12})
		B.box([21.6, 8.3, -34.4], [22.4, 11, -33.6], Mats.plastic("#2b2d33"), "plastic", {"round": 0.1})
		B.box([15.6, 10.4, -35.4], [28.4, 17.6, -34.2], Mats.plastic("#1d1f24", {"rough": 0.3}), "plastic", {"round": 0.25})
		screen_tex = Tex.monitor_screen()
		var scr_m := Mats.basic("#ffffff", screen_tex.texture)
		var screen := Geo.plane(12.2, 6.6).mesh_instance(scr_m, Vector3(22, 14, -34.17), Basis(), false)
		root.add_child(screen)
		point_lights.append(omni(root, "#8a7dff", 6, 14, 2, Vector3(22, 13, -31)))
		# pencil cup with pencils
		B.cyl([15.9, 8, -33.5], 1.1, 3.6, Mats.plastic("#3a86ff"), "plastic", 24)
		var pencil_cols := ["#ffbe0b", "#fb5607", "#8338ec", "#06d6a0"]
		for i in 4:
			var a := float(i) / 4 * TAU
			B.geo(Geo.cylinder(0.22, 0.22, 7, 6), Mats.plastic(pencil_cols[i], {"rough": 0.5}), [15.9 + cos(a) * 0.45, 12, -33.5 + sin(a) * 0.45], E(cos(a) * 0.15, 0, sin(a) * 0.15))
		# book pile on desk (cover)
		var yy := 8.0
		var pile_titles := ["FAIRY", "COMICS", "TRAINS", "SPORTS"]
		for i in 4:
			var h := 0.55 + rnd.next() * 0.2
			var bm := Mats.textured(Tex.book(book_cols[(i + 3) % 8], pile_titles[i]), 0.6)
			B.breakable_box([28.4 + rnd.next() * 0.3, yy, -31.2 + rnd.next() * 0.3], [31.4 + rnd.next() * 0.3, yy + h, -25.2 - rnd.next() * 0.3], bm, "soft", "desk-books", "cardboard", {"round": 0.05, "rests": i > 0})
			yy += h
		# giant pencil lying flat (low cover)
		B.geo(Geo.cylinder(0.42, 0.42, 8, 6), Mats.plastic("#ffbe0b", {"rough": 0.5}), [21.5, 8.42, -25.4], E(0, 0, PI / 2))
		B.geo(Geo.cone(0.42, 1.2, 6), M.desk, [26.1, 8.42, -25.4], E(0, 0, -PI / 2))
		B.geo(Geo.cylinder(0.44, 0.44, 0.9, 12), Mats.plastic("#ff8fab"), [17.05, 8.42, -25.4], E(0, 0, PI / 2))
		phys.box(Vector3(21.6, 8.42, -25.4), Vector3(4.9, 0.42, 0.42), "wood")
		# desk lamp
		var lamp_m := Mats.metal("#2d6a4f", 0.35)
		B.cyl([30.5, 8, -33.8], 1.5, 0.4, lamp_m, "metal", 24)
		B.obox([30.5, 11, -33.4], [0.35, 6.2, 0.35], E(0.15, 0, 0), lamp_m, "metal")
		B.obox([29.4, 14.3, -32.4], [0.35, 4, 0.35], E(0.4, 0, 0.9), lamp_m, "")
		var shade := Mats.metal("#2d6a4f", 0.35)
		shade.cull_mode = BaseMaterial3D.CULL_DISABLED
		B.geo(Geo.cone(1.4, 2, 24, 1, true), shade, [27.8, 15.2, -31.6], E(0.3, 0, 0.6))
		B.geo(Geo.sphere(0.6, 16, 12), Mats.glow("#fff2c6", 4), [27.6, 14.6, -31.4])
		point_lights.append(omni(root, "#ffd7a0", 16, 26, 2, Vector3(27.2, 13.6, -30.8)))
		# sticky notes
		B.box([29, 8, -26], [31, 8.12, -24.4], Mats.plastic("#fff275", {"rough": 0.8, "clearcoat": 0}), "")

	# ---------------------------------------------------------------- CLOSET MAZE (E)
	if true:
		var cw := M.closet_wall
		var top := 18.0
		B.box([19.5, 0, -18.5], [20, top, -14], cw, "wood")
		B.box([19.5, 0, -9], [20, top, -3], cw, "wood")
		B.box([19.5, 0, 2], [20, top, 6.5], cw, "wood")
		B.box([19.5, 9, -14], [20, top, -9], cw, "wood")
		B.box([19.5, 9, -3], [20, top, 2], cw, "wood")
		B.box([20, 0, -18.5], [32, top, -18], cw, "wood")
		B.box([20, 0, 6], [32, top, 6.5], cw, "wood")
		B.box([19.5, top, -18.5], [32, top + 0.5, 6.5], cw, "wood")
		for zz in [[-18.5, -14], [-9, -3], [2, 6.5]]:
			B.box([19.3, 0, zz[0]], [19.5, top, zz[1]], M.wallpaper, "", {"tile": 1.0 / 12})
		B.box([19.3, 9, -14], [19.5, top, -9], M.wallpaper, "", {"tile": 1.0 / 12})
		B.box([19.3, 9, -3], [19.5, top, 2], M.wallpaper, "", {"tile": 1.0 / 12})
		for zz in [[-14, -9], [-3, 2]]:
			B.box([19.1, 0, zz[0] - 0.4], [19.6, 9.4, zz[0]], M.trim, "")
			B.box([19.1, 0, zz[1]], [19.6, 9.4, zz[1] + 0.4], M.trim, "")
			B.box([19.1, 9, zz[0] - 0.4], [19.6, 9.4, zz[1] + 0.4], M.trim, "")
		B.box([20, 0, -18], [32, 0.06, 6], M.fabric_b, "fabric", {"cast": false})
		var shoe := func(x0: float, z0: float, x1: float, z1: float, h: float) -> void:
			var layers := int(round(h / 1.4))
			var lh := h / layers
			for l in layers:
				var inset := (l % 2) * 0.1
				var mat := M.cardboard_shoes if l % 2 else M.cardboard
				# each box in the stack breaks on its own; the ones above come down with it
				B.breakable_box([x0 + inset, l * lh, z0 + inset], [x1 - inset, (l + 1) * lh - 0.02, z1 - inset], mat, "soft", "closet-shoes", "cardboard", {"round": 0.05, "rests": l > 0})
		shoe.call(23, -18, 24.5, -11, 3.2)
		shoe.call(24.5, -12.5, 30, -11, 3.2)
		shoe.call(27, -7.5, 32, -6, 3.2)
		shoe.call(22.5, -7.5, 24, -1.5, 3.2)
		shoe.call(24, -1.5, 28.5, 0, 2.6)
		shoe.call(26, 2.5, 32, 4, 1.25)
		for bin in [[29.6, -17.6, 32, -13.6, "#7fc8f8"], [20.4, 3, 22.6, 5.8, "#ffafcc"]]:
			B.breakable_box([bin[0], 0, bin[1]], [bin[2], 2.6, bin[3]], Mats.plastic(bin[4], {"rough": 0.15, "clearcoat": 1}), "soft", "closet-bins", "plastic", {"round": 0.2})
			B.breakable_box([bin[0] - 0.1, 2.6, bin[1] - 0.1], [bin[2] + 0.1, 2.9, bin[3] + 0.1], Mats.plastic("#ffffff", {"rough": 0.3}), "soft", "closet-bins", "plastic", {"round": 0.1, "rests": true})
		B.obox([31, 15.6, -6], [0.25, 0.25, 24], Basis(), Mats.metal("#d0d0d0", 0.2), "")
		var clothes := [M.fabric_a, M.fabric_b, M.fabric_c, M.fabric_d]
		for i in 9:
			var cz := -16.5 + i * 2.6
			var long := i == 2 or i == 5 or i == 7
			var bottom := 1.6 if long else 7 + rnd.next() * 2
			B.geo(Geo.torus(0.5, 0.06, 6, 12, PI), Mats.metal("#bbbbbb"), [31, 15.4, cz], E(0, PI / 2, 0))
			B.box([29.4, bottom, cz - 0.35], [32, 15.2, cz + 0.35], clothes[i % 4], "fabric" if long else "", {"round": 0.3})
		B.geo(Geo.octahedron(0.6), Mats.glow("#b8a6ff", 3), [31.6, 4, -9])
		point_lights.append(omni(root, "#8f7bff", 10, 22, 1.6, Vector3(27, 5, -6)))
		point_lights.append(omni(root, "#4f9dff", 6, 18, 1.6, Vector3(25, 4, -15)))

	# ---------------------------------------------------------------- TOY GARAGE (SE)
	if true:
		var track_m := Mats.plastic("#4a4e69", {"rough": 0.6, "clearcoat": 0.2})
		var track := Geo.ring(3.2, 5.2, 64, 1).mesh_instance(track_m, Vector3(17, 0.03, 18.5), E(-PI / 2, 0, 0))
		track.scale = Vector3(2.0, 1, 1)
		track.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(track)
		var dash := Geo.ring(4.12, 4.28, 64, 1).mesh_instance(Mats.plastic("#ffffff", {"rough": 0.6}), Vector3(17, 0.04, 18.5), E(-PI / 2, 0, 0), false)
		dash.scale = Vector3(2.0, 1, 1)
		root.add_child(dash)
		var deck_mat := Mats.plastic("#9aa5b1", {"rough": 0.5})
		B.box([22, 3.6, 24], [32, 4, 36], deck_mat, "plastic", {"round": 0.08})
		for p in [[22.5, 24.5], [22.5, 35.5], [27, 24.5], [31.5, 24.5], [27, 35.5], [22.5, 27.6], [22.5, 32.4]]:
			B.box([p[0] - 0.4, 0, p[1] - 0.4], [p[0] + 0.4, 3.6, p[1] + 0.4], Mats.plastic("#f4a261"), "plastic", {"round": 0.1})
		B.box([22.4, 4, 24], [32, 5, 24.4], Mats.plastic("#e76f51"), "plastic")
		B.box([22, 4, 24], [22.4, 5, 28], Mats.plastic("#e76f51"), "plastic")
		B.box([22, 4, 32], [22.4, 5, 36], Mats.plastic("#e76f51"), "plastic")
		var hp := Geo.circle(2.6, 32).mesh_instance(Mats.plastic("#ffd166", {"rough": 0.5}), Vector3(28, 4.02, 31), E(-PI / 2, 0, 0), false)
		root.add_child(hp)
		B.slab([14, 0, 30], [22, 4, 30], 4, 0.3, Mats.plastic("#6c757d", {"rough": 0.6}), "plastic")
		for i in 6:
			var t := (i + 0.5) / 6
			B.obox([14 + 8 * t, 4 * t + 0.03, 30], [0.4, 0.04, 3.6], E(0, 0, atan2(4, 8)), Mats.plastic("#ffd166"), "")
		B.wedge([24, 0, 16], PI / 2, 4, 1.6, 3.5, Mats.plastic("#fb8500"), "plastic")
		_add_car(B, [9.5, 0, 33], 0, "#e63946")
		_add_car(B, [16.5, 0, 34.5], 0.1, "#3a86ff")
		_add_car(B, [26.5, 0, 30], PI / 2, "#06d6a0")
		_add_car(B, [29.5, 4, 33.5], PI / 2 + 0.2, "#ffbe0b")
		_add_car(B, [8, 0, 13.5], -0.2, "#8338ec")
		for p in [[12, 24], [13.4, 25.6], [20.5, 13]]:
			B.cyl([p[0], 0, p[1]], 0.6, 1.3, Mats.plastic("#fb5607"), "plastic", 16, 0.12)
			B.box([p[0] - 0.75, 0, p[1] - 0.75], [p[0] + 0.75, 0.15, p[1] + 0.75], Mats.plastic("#fb5607"), "")
		for i in 3:
			B.geo(Geo.torus(1.0, 0.42, 12, 24), Mats.rubber("#222222"), [7.6, 0.42 + i * 0.8, 18], E(PI / 2, 0, 0))
		phys.cylinder(Vector3(7.6, 1.2, 18), 1.2, 1.4, "plastic")
		B.box([6.5, 0, 22], [8.3, 2.8, 24], Mats.plastic("#ef233c"), "plastic", {"round": 0.2})
		B.box([6.7, 1.6, 21.9], [8.1, 2.4, 22], Mats.glow("#fff3b0", 1.2), "")
		_add_sign(root, "TOY GARAGE", [27, 7.2, 24.3], "#e76f51")

	# ---------------------------------------------------------------- DINOSAUR KINGDOM (SW)
	if true:
		B.box([-32, 0, 12], [-6, 0.12, 36], M.fabric_d, "fabric", {"cast": false})
		var pts := []
		for i in 13:
			var t := i / 12.0
			pts.append(Vector2(6.6 - t * 4.6 + sin(t * 9) * 0.25, t * 8))
		pts.append(Vector2(1.6, 7.6))
		pts.append(Vector2(1.2, 6.6))
		var vmat := Mats.std("#7a4b35", 0.85)
		vmat.set_meta("flat", true)
		B.geo(Geo.lathe(pts, 40), vmat, [-23, 0, 29])
		var lava_m := Mats.glow("#ff6b1a", 3.5)
		var lava := Geo.circle(1.6, 24).mesh_instance(lava_m, Vector3(-23, 7.0, 29), E(-PI / 2, 0, 0), false)
		root.add_child(lava)
		for i in 5:
			var a := float(i) / 5 * TAU + 0.3
			var r0 := 2.2 + i * 0.25
			B.geo(Geo.capsule(0.28, 3 + (i % 2), 4, 8), Mats.glow("#ff7b00", 1.6), [-23 + cos(a) * r0 * 1.1, 6.1 - i * 0.2, 29 + sin(a) * r0 * 1.1], E(sin(a) * 0.6, 0, -cos(a) * 0.6))
		phys.cone(Vector3(-23, 4, 29), 4, 6.6, "plastic")
		var vl := omni(root, "#ff7a1a", 14, 20, 1.8, Vector3(-23, 9.5, 29))
		point_lights.append(vl)
		animated.append(func(_dt: float, t: float) -> void:
			vl.light_energy = (12 + sin(t * 2.3) * 3 + sin(t * 7.1) * 1.5) * Lighting.POINT_SCALE
			lava_m.emission_energy_multiplier = 3 + sin(t * 3) * 0.6)
		_add_trex(B, phys, [-15, 0, 18])
		_add_triceratops(B, phys, [-27, 0, 15])
		_add_brachio(B, phys)
		_add_stego(B, phys, [-10, 0, 23.5])
		for rk in [[-19, 23.5, 1.5], [-8.6, 14.2, 1.3], [-31, 21, 1.5], [-21, 13.6, 1.2], [-30.6, 33.6, 1.8]]:
			B.geo(Geo.dodecahedron(rk[2], 1), M.rock, [rk[0], rk[2] * 0.55, rk[1]], E(rnd.next(), rnd.next(), rnd.next()), [1, 0.8, 1.1])
			phys.ball(Vector3(rk[0], rk[2] * 0.45, rk[1]), rk[2] * 0.92, "plastic")
		for pm in [[-30.4, 13.2, 1], [-11.5, 34.6, 1.2], [-17.5, 35, 0.9], [-7.5, 19.5, 0.9], [-31, 26.5, 1.1]]:
			_add_palm(B, phys, [pm[0], 0, pm[1]], pm[2], rnd)

	# ---------------------------------------------------------------- BRICK DISTRICT (W-center)
	if true:
		var base := "#3a9d47"
		B.box([-31.5, 0, -7.5], [-13.5, 0.3, 9.5], Mats.plastic(base, {"rough": 0.4}), "plastic")
		B.add_studs(-31.5, -13.5, -7.5, 9.5, 0.3, base, 1.6)
		var C := BRICK_COLORS
		for i in 7:
			B.brick([-31.5, 0.3 + i, -7.5], [-27.5, 1.3 + i, -3.5], C[i % C.size()], "", i == 6)
		phys.box(Vector3(-29.5, 3.8, -5.5), Vector3(2, 3.5, 2), "plastic")
		B.wedge([-30, 0.3, 6], PI, 9.5, 7, 3, Mats.plastic("#f2c12e", {"rough": 0.35}), "plastic")
		# brick walls: hard panels about 1.6 m wide (studs on top); the pieces over doorways and the battlements
		# rest on them and come down when a panel under them goes
		var wall := func(mn: Array, mx: Array, col: String) -> void:
			var along_x: bool = mx[0] - mn[0] >= mx[2] - mn[2]
			var a0: float = mn[0] if along_x else mn[2]
			var a1: float = mx[0] if along_x else mx[2]
			var n := maxi(1, roundi((a1 - a0) / 1.6))
			var st := (a1 - a0) / n
			for k in n:
				var q0 := a0 + k * st
				var q1 := q0 + st
				var pmn: Array = [q0, mn[1], mn[2]] if along_x else [mn[0], mn[1], q0]
				var pmx: Array = [q1, mx[1], mx[2]] if along_x else [mx[0], mx[1], q1]
				B.breakable_brick(pmn, pmx, col, "hard", "bricks", true, {"rests": mn[1] > 1.0})
		wall.call([-27.5, 0.3, -5], [-23, 4.3, -3.8], "#bfc5cc")
		wall.call([-20.5, 0.3, -5], [-16, 4.3, -3.8], "#bfc5cc")
		wall.call([-23, 2.8, -5], [-20.5, 4.3, -3.8], "#d6342c")
		wall.call([-17.2, 0.3, -3.8], [-16, 4.3, -0.5], "#bfc5cc")
		wall.call([-17.2, 0.3, 2], [-16, 4.3, 6], "#bfc5cc")
		wall.call([-17.2, 2.8, -0.5], [-16, 4.3, 2], "#1f6fd1")
		wall.call([-24, 0.3, 6], [-17.2, 2.5, 7.2], "#bfc5cc")
		var bxx := -27.1
		while bxx < -16.2:
			B.breakable_brick([bxx, 4.3, -5], [bxx + 0.8, 5.1, -3.8], "#9aa1a9", "hard", "bricks", true, {"rests": true})
			bxx += 1.6
		var bzz := -3.4
		while bzz < 5.8:
			B.breakable_brick([-17.2, 4.3, bzz], [-16, 5.1, bzz + 0.8], "#9aa1a9", "hard", "bricks", true, {"rests": true})
			bzz += 1.6
		# the Brick District objective stands on these two: they stay solid
		B.brick([-25, 0.3, 0], [-21, 2.3, 3], "#f08c1f")
		B.brick([-21, 0.3, 0.4], [-19.8, 1.3, 2.6], "#f2c12e")
		for i in 9:
			B.brick([-15, i, 7], [-13, i + 1, 9], C[(i + 2) % C.size()], "", i == 8)
		phys.box(Vector3(-14, 4.5, 8), Vector3(1, 4.5, 1), "plastic")
		for i in 6:
			B.brick([-15, 0.3 + i, -7.5], [-13, 1.3 + i, -5.5], C[(i + 4) % C.size()], "", i == 5)
		phys.box(Vector3(-14, 3.3, -6.5), Vector3(1, 3, 1), "plastic")
		B.breakable_brick([-14.5, 0, 1], [-12.6, 1.4, 5], "#d6342c", "soft", "brick-cover")
		B.breakable_brick([-27, 0.3, 8], [-25, 1.7, 9.6], "#1f6fd1", "soft", "brick-cover")
		B.breakable_brick([-12.5, 0, -10], [-10.5, 1.4, -6], "#f2c12e", "soft", "brick-cover")
		_add_sign(root, "BRICK DISTRICT", [-22, 6.6, -5.2], "#d6342c")

	# ---------------------------------------------------------------- loose bricks (dynamic)
	var brick_spots: Array = []
	if true:
		var r := U.seeded(7)
		var areas := [[-27, -16.5, -3.4, 5.6], [-15.5, -11, -4, 6], [-31, -27.5, 7, 9]]
		for i in 26:
			var a: Array = areas[i % areas.size()]
			brick_spots.append(Vector3(a[0] + r.next() * (a[1] - a[0]), 1 + (i % 3) * 0.7, a[2] + r.next() * (a[3] - a[2])))

	B.build_studs(root)
	batch.build(root)
	var loose := LooseBricks.new(phys, brick_spots, root, Vector3(-22, 3, 2))
	animated.append(loose.update)
	if not screen_tex.is_empty():
		var acc := [0.0]
		var upd: Callable = screen_tex.update
		animated.append(func(dt: float, t: float) -> void:
			acc[0] += dt
			if acc[0] > 0.1:
				acc[0] = 0.0
				upd.call(t))

	# ---------------------------------------------------------------- LIGHTING
	var sun_dir := Vector3(0.28, -0.55, 1).normalized()
	var sun := Lighting.sun(root, "#ffdcae", 6.2, sun_dir, 60)
	point_lights.append(omni(root, "#ffcf9e", 22, 40, 1.4, Vector3(4, 4, -2)))
	point_lights.append(omni(root, "#c9dcff", 10, 60, 1.2, Vector3(0, 24, 20)))

	# ---------------------------------------------------------------- GAMEPLAY DATA
	var zones := [
		{"name": "Closet Maze", "min": [19.5, -18.5], "max": [32, 6.5], "ambience": "closet"},
		{"name": "Desk Outpost", "min": [0, -36], "max": [32, -19], "ambience": "desk"},
		{"name": "Bed Fortress", "min": [-32, -36], "max": [0, -11], "ambience": "bed"},
		{"name": "Toy Garage", "min": [5, 11], "max": [32, 36], "ambience": "garage"},
		{"name": "Dinosaur Kingdom", "min": [-32, 11], "max": [-5, 36], "ambience": "dino"},
		{"name": "Brick District", "min": [-32, -11], "max": [-10, 11], "ambience": "brick"},
		{"name": "Play Rug", "min": [-32, -36], "max": [32, 36], "ambience": "rug"},
	]
	# [kind, x, z, probe-from-y]: dropped onto whatever is below once physics is ready
	var pickup_probes := [
		["health", -6.5, -15, 9], ["health", 25.5, -9.2, 2], ["health", 12, 21.5, 2], ["health", -30.4, 28.6, 2],
		["health", -1.5, -5, 2], ["health", 20.5, -27.5, 12], ["shield", -29.5, -5.5, 12], ["shield", 29.6, -3.2, 2],
		["turbo", 17, 18.5, 2], ["infinite", -25.5, -20.5, 2], ["power", 2, 1, 8],
		["health", 24, Z0 + 2.85, 23], ["health", -18, Z1 - 2.85, 23], ["shield", X1 - 2.85, 22, 23],
	]
	return {
		"root": root, "zones": zones, "pickup_probes": pickup_probes, "animated": animated, "sun": sun,
		"sun_dir": sun_dir, "point_lights": point_lights, "loose_bricks": loose,
		"bounds": AABB(Vector3(X0, 0, Z0), Vector3(X1 - X0, RH, Z1 - Z0)),
		"window": WIN,
	}


# ======================================================================== prop helpers
static func _stripe_ball_mat(a := "#ef476f", b := "#ffd166") -> StandardMaterial3D:
	var m := Mats.textured(Tex.stripe_ball(a, b), 0.3)
	m.clearcoat_enabled = true
	m.clearcoat = 0.8
	return m


static var _letter_mats := {}


static func _letter_block(B: Builder, center: Array, size: float, color: String, letter: String, yaw: float) -> void:
	var key := color + letter
	if not _letter_mats.has(key):
		_letter_mats[key] = Mats.textured(Tex.letter_block(color, letter), 0.55)
	B.geo(Geo.rounded_box(size, size, size, 2, 0.08), _letter_mats[key], center, E(0, yaw, 0))


static func _add_car(B: Builder, base: Array, yaw: float, color: String) -> void:
	var body := Mats.plastic(color, {"rough": 0.25, "clearcoat": 1})
	var rot := E(0, yaw, 0)
	var at := func(px: float, py: float, pz: float) -> Array:
		var p := rot * Vector3(px, py, pz)
		return [base[0] + p.x, base[1] + p.y, base[2] + p.z]
	B.geo(Geo.rounded_box(1.9, 0.8, 3.6, 3, 0.3), body, at.call(0, 0.75, 0), rot)
	# cabin: roof on four corner pillars, glass all round (the windows can be shot out)
	B.geo(Geo.rounded_box(1.6, 0.12, 1.9, 2, 0.06), body, at.call(0, 1.72, -0.2), rot)
	for cp in [[-0.74, 0.69], [0.74, 0.69], [-0.74, -1.09], [0.74, -1.09]]:
		B.geo(Geo.box(0.1, 0.6, 0.1), body, at.call(cp[0], 1.4, cp[1]), rot)
	var glass := Mats.translucent("#9fd8ff", 0.45)
	glass.roughness = 0.05
	# panes as boxes; the car turns in quarter turns for this, so they line up with the cabin
	var q := Basis(Vector3.UP, roundf(yaw / (PI / 2)) * (PI / 2))
	var pane := func(cx: float, cz: float, hx: float, hz: float) -> void:
		var c: Vector3 = Builder.v(at.call(cx, 1.4, cz))
		var h := (q * Vector3(hx, 0.29, hz)).abs()
		B.breakable_box([c.x - h.x, c.y - h.y, c.z - h.z], [c.x + h.x, c.y + h.y, c.z + h.z], glass, "glass", "car-glass", "glass")
	pane.call(0, 0.74, 0.7, 0.03)
	pane.call(0, -1.14, 0.7, 0.03)
	pane.call(-0.79, -0.2, 0.03, 0.85)
	pane.call(0.79, -0.2, 0.03, 0.85)
	for w in [[-0.95, 1.1], [0.95, 1.1], [-0.95, -1.15], [0.95, -1.15]]:
		B.geo(Geo.cylinder(0.45, 0.45, 0.35, 16), Mats.rubber("#1d1d1d"), at.call(w[0], 0.45, w[1]), E(0, yaw, PI / 2))
		B.geo(Geo.cylinder(0.22, 0.22, 0.37, 10), Mats.metal("#dddddd"), at.call(w[0], 0.45, w[1]), E(0, yaw, PI / 2))
	B.geo(Geo.sphere(0.16, 8, 6), Mats.glow("#fff6c2", 2), at.call(-0.6, 0.85, 1.8), rot)
	B.geo(Geo.sphere(0.16, 8, 6), Mats.glow("#fff6c2", 2), at.call(0.6, 0.85, 1.8), rot)
	B.phys.box(Builder.v(at.call(0, 0.58, 0)), Vector3(0.95, 0.58, 1.8), "plastic", rot)
	B.phys.box(Builder.v(at.call(0, 1.72, -0.2)), Vector3(0.8, 0.06, 0.95), "plastic", rot)


static func _add_sign(root: Node3D, txt: String, pos: Array, color: String) -> void:
	var m := Mats.textured(Tex.sign(txt, color), 0.5)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	root.add_child(Geo.plane(6, 1.5).mesh_instance(m, Builder.v(pos)))


static func _add_drawings(root: Node3D) -> void:
	var line := func(ci: CanvasItem, pts: PackedVector2Array, col: String) -> void:
		ci.draw_polyline(pts, Tex.c(col), 6, true)
	var sun_house := Tex.drawing("sunhouse", func(ci: CanvasItem):
		ci.draw_arc(Vector2(205, 45), 26, 0, TAU, 32, Tex.c("#ffb703"), 6, true)
		for i in 8:
			var a := i * 0.785
			line.call(ci, PackedVector2Array([Vector2(205 + cos(a) * 34, 45 + sin(a) * 34), Vector2(205 + cos(a) * 48, 45 + sin(a) * 48)]), "#ffb703")
		line.call(ci, PackedVector2Array([Vector2(50, 100), Vector2(140, 100), Vector2(140, 170), Vector2(50, 170), Vector2(50, 100)]), "#e63946")
		line.call(ci, PackedVector2Array([Vector2(40, 100), Vector2(95, 55), Vector2(150, 100)]), "#e63946")
		line.call(ci, PackedVector2Array([Vector2(0, 185), Vector2(256, 185)]), "#2a9d8f"))
	var dino := Tex.drawing("dino", func(ci: CanvasItem):
		line.call(ci, Tex.ellipse_points(120, 120, 60, 35), "#2a9d8f")
		line.call(ci, Tex.quad_points(Vector2(170, 105), Vector2(200, 40), Vector2(220, 50)), "#2a9d8f")
		ci.draw_arc(Vector2(222, 48), 10, 0, TAU, 20, Tex.c("#2a9d8f"), 6, true)
		line.call(ci, Tex.quad_points(Vector2(60, 120), Vector2(20, 130), Vector2(10, 100)), "#2a9d8f")
		for x in [90, 110, 140, 160]:
			line.call(ci, PackedVector2Array([Vector2(x, 150), Vector2(x, 185)]), "#2a9d8f")
		Tex.text(ci, Tex.FONT_BOLD, "REX!", 20, 32, 26, Tex.c("#e76f51"), "left"))
	var robot := Tex.drawing("robot", func(ci: CanvasItem):
		line.call(ci, PackedVector2Array([Vector2(90, 70), Vector2(170, 70), Vector2(170, 160), Vector2(90, 160), Vector2(90, 70)]), "#457b9d")
		line.call(ci, PackedVector2Array([Vector2(100, 25), Vector2(160, 25), Vector2(160, 70), Vector2(100, 70), Vector2(100, 25)]), "#457b9d")
		ci.draw_rect(Rect2(112, 38, 10, 10), Tex.c("#e63946"))
		ci.draw_rect(Rect2(138, 38, 10, 10), Tex.c("#e63946"))
		line.call(ci, PackedVector2Array([Vector2(130, 25), Vector2(130, 8)]), "#457b9d")
		line.call(ci, PackedVector2Array([Vector2(90, 90), Vector2(55, 120)]), "#457b9d")
		line.call(ci, PackedVector2Array([Vector2(170, 90), Vector2(205, 120)]), "#457b9d"))
	var frames := [[sun_house, Vector3(-14, 13, 35.7), PI], [dino, Vector3(16, 12, 35.7), PI], [robot, Vector3(-31.7, 14, 2), PI / 2]]
	var tape_m := Mats.std("#f1e3b5", 0.8)
	tape_m.albedo_color.a = 0.85
	tape_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for f in frames:
		var ry: float = f[2]
		var mi := Geo.plane(6.4, 5).mesh_instance(Mats.textured(f[0], 0.9), f[1], E(0, ry, 0), false)
		root.add_child(mi)
		var tp: Vector3 = f[1] + Vector3(0, 2.4, 0)
		if ry == PI / 2:
			tp.x += 0.02
		if ry == PI:
			tp.z -= 0.02
		root.add_child(Geo.plane(1.2, 0.4).mesh_instance(tape_m, tp, E(0, ry, 0.15), false))


static func _add_trex(B: Builder, phys: Phys, b: Array) -> void:
	var green := Mats.plastic("#4caf50", {"rough": 0.35})
	var belly := Mats.plastic("#c5e1a5", {"rough": 0.4})
	var x: float = b[0]
	var z: float = b[2]
	for dz in [-1.2, 1.2]:
		B.geo(Geo.capsule(0.9, 2.2, 6, 16), green, [x - 0.8, 2.2, z + dz])
		B.geo(Geo.rounded_box(2.2, 0.6, 1.4, 2, 0.25), green, [x - 0.4, 0.3, z + dz])
		phys.cylinder(Vector3(x - 0.8, 1.9, z + dz), 1.9, 0.85, "plastic")
	B.geo(Geo.capsule(1.8, 4, 8, 20), green, [x, 5, z], E(0, 0, PI / 2 + 0.35))
	B.geo(Geo.capsule(1.3, 3, 8, 16), belly, [x + 0.4, 4.6, z], E(0, 0, PI / 2 + 0.35), [1, 1, 1.1])
	phys.box(Vector3(x, 5, z), Vector3(3.2, 1.6, 1.6), "plastic", E(0, 0, 0.35))
	B.geo(Geo.cone(1.4, 7, 16), green, [x - 5.4, 3.2, z], E(0, 0, PI / 2 + 0.25))
	phys.box(Vector3(x - 4.6, 3.4, z), Vector3(2.4, 0.9, 0.9), "plastic", E(0, 0, 0.25))
	B.geo(Geo.capsule(1.1, 1.5, 6, 16), green, [x + 2.6, 7.2, z], E(0, 0, -0.6))
	B.geo(Geo.rounded_box(3.6, 1.8, 2.2, 3, 0.6), green, [x + 4, 8.2, z])
	B.geo(Geo.rounded_box(3.0, 0.7, 1.9, 2, 0.3), green, [x + 4.1, 7.1, z], E(0, 0, -0.15))
	phys.box(Vector3(x + 4, 7.8, z), Vector3(1.8, 1.2, 1.1), "plastic")
	for i in 6:
		B.geo(Geo.cone(0.12, 0.35, 6), Mats.plastic("#ffffff"), [x + 3.1 + i * 0.45, 7.45, z + 0.95], E(PI, 0, 0))
		B.geo(Geo.cone(0.12, 0.35, 6), Mats.plastic("#ffffff"), [x + 3.1 + i * 0.45, 7.45, z - 0.95], E(PI, 0, 0))
	for dz in [-0.95, 0.95]:
		B.geo(Geo.sphere(0.38, 16, 12), Mats.plastic("#ffffff"), [x + 4.4, 8.75, z + dz])
		B.geo(Geo.sphere(0.2, 12, 8), Mats.plastic("#111111"), [x + 4.55, 8.8, z + dz * 1.25])
		B.geo(Geo.capsule(0.25, 0.9, 4, 8), green, [x + 2.2, 5.2, z + dz * 1.5], E(0, 0, -1.1))


static func _add_triceratops(B: Builder, phys: Phys, b: Array) -> void:
	var col := Mats.plastic("#5e60ce", {"rough": 0.35})
	var frill := Mats.plastic("#ffafcc", {"rough": 0.4})
	var x: float = b[0]
	var z: float = b[2]
	B.geo(Geo.capsule(1.3, 3.2, 8, 16), col, [x, 2, z], E(0, 0, PI / 2))
	for d in [[-1.6, -0.9], [-1.6, 0.9], [1.4, -0.9], [1.4, 0.9]]:
		B.geo(Geo.cylinder(0.45, 0.5, 1.4, 10), col, [x + d[0], 0.7, z + d[1]])
	B.geo(Geo.rounded_box(2, 1.4, 1.6, 2, 0.5), col, [x + 3, 2.1, z])
	B.geo(Geo.cylinder(1.8, 1.8, 0.3, 24, 1, false, 0, PI), frill, [x + 2.3, 2.7, z], E(PI / 2, 0, PI / 2 + 0.3))
	for dz in [-0.5, 0.5]:
		B.geo(Geo.cone(0.18, 1.6, 8), Mats.plastic("#fffbe6"), [x + 3.8, 3.1, z + dz], E(0, 0, -1.2))
	B.geo(Geo.cone(0.15, 0.7, 8), Mats.plastic("#fffbe6"), [x + 4.1, 2.3, z], E(0, 0, -1.3))
	phys.box(Vector3(x + 0.6, 1.6, z), Vector3(3.3, 1.6, 1.4), "plastic")


static func _add_stego(B: Builder, phys: Phys, b: Array) -> void:
	var col := Mats.plastic("#f4a261", {"rough": 0.35})
	var plate := Mats.plastic("#e76f51", {"rough": 0.35})
	var x: float = b[0]
	var z: float = b[2]
	B.geo(Geo.capsule(1.0, 2.6, 8, 16), col, [x, 1.5, z], E(0, 0, PI / 2))
	for i in 5:
		B.geo(Geo.cone(0.55, 1.2, 4), plate, [x - 1.6 + i * 0.8, 2.75 - absf(i - 2) * 0.15, z], E(0, PI / 4, 0))
	for d in [[-1.2, -0.7], [-1.2, 0.7], [1.2, -0.7], [1.2, 0.7]]:
		B.geo(Geo.cylinder(0.35, 0.4, 1, 10), col, [x + d[0], 0.5, z + d[1]])
	B.geo(Geo.sphere(0.6, 16, 12), col, [x + 2.6, 1.3, z])
	phys.box(Vector3(x + 0.3, 1.3, z), Vector3(2.6, 1.3, 1.1), "plastic")


static func _add_brachio(B: Builder, phys: Phys) -> void:
	var col := Mats.plastic("#48cae4", {"rough": 0.35})
	var spots := Mats.plastic("#0096c7", {"rough": 0.35})
	B.geo(Geo.rounded_box(6.6, 3.2, 3.6, 3, 1.2), col, [-12, 4.4, 30])
	phys.box(Vector3(-12, 4.5, 30), Vector3(3.1, 1.5, 1.6), "plastic")
	for p in [[-14.2, 28.9], [-14.2, 31.1], [-9.8, 28.9], [-9.8, 31.1]]:
		B.geo(Geo.cylinder(0.6, 0.7, 3.2, 12), col, [p[0], 1.6, p[1]])
		phys.cylinder(Vector3(p[0], 1.5, p[1]), 1.5, 0.65, "plastic")
	for i in 6:
		B.geo(Geo.sphere(0.35, 10, 8), spots, [-14 + i * 0.8, 5.9, 29.3 + (i % 2) * 1.2], Basis(), [1, 0.3, 1])
	var neck_from := Vector3(-15, 5.5, 30)
	var neck_to := Vector3(-19.5, 13, 30)
	var mid := (neck_from + neck_to) * 0.5
	var length := neck_from.distance_to(neck_to)
	var ang := -atan2(neck_to.x - neck_from.x, neck_to.y - neck_from.y)
	B.geo(Geo.capsule(0.85, length, 6, 14), col, [mid.x, mid.y, mid.z], E(0, 0, ang))
	phys.box(mid, Vector3(0.8, length / 2, 0.8), "plastic", E(0, 0, ang))
	B.geo(Geo.rounded_box(2.4, 1.2, 1.4, 2, 0.5), col, [-20.2, 13.4, 30])
	for dz in [-0.6, 0.6]:
		B.geo(Geo.sphere(0.25, 12, 8), Mats.plastic("#ffffff"), [-20.4, 13.75, 30 + dz])
		B.geo(Geo.sphere(0.13, 8, 6), Mats.plastic("#111111"), [-20.55, 13.8, 30 + dz * 1.2])
	B.slab([-0.8, 0, 30], [-9, 6, 30], 2.8, 0.5, col, "plastic", 0.2)


static func _add_palm(B: Builder, phys: Phys, base: Array, s: float, rnd: U.Seeded) -> void:
	var trunk := Mats.plastic("#a0522d", {"rough": 0.6, "clearcoat": 0.2})
	var leaf := Mats.plastic("#2dc653", {"rough": 0.4})
	var y: float = base[1]
	for i in 6:
		B.geo(Geo.cylinder(0.42 * s, 0.55 * s, 1.2 * s, 10), trunk, [base[0] + i * 0.08, y + 0.6 * s, base[2]], E(0, 0, -0.05))
		y += 1.15 * s
	phys.cylinder(Vector3(base[0], y / 2, base[2]), y / 2, 0.5 * s, "wood")
	for i in 6:
		var a := float(i) / 6 * TAU + rnd.next()
		var g := Geo.cone(0.7 * s, 4.2 * s, 4).scale(1, 1, 0.25).translate(0, 2.1 * s, 0)
		var dir := Vector3(cos(a) * 0.95, 0.3, sin(a) * 0.95).normalized()
		B.geo(g, leaf, [base[0] + 0.48, y, base[2]], U.from_up(dir))
	for i in 3:
		B.geo(Geo.sphere(0.32 * s, 10, 8), Mats.plastic("#8b5a2b"), [base[0] + 0.48 + cos(i * 2) * 0.4, y - 0.3, base[2] + sin(i * 2) * 0.4])

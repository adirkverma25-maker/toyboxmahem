class_name ArenaBackyard
## Map 2: SANDBOX SHOWDOWN. A sunny backyard at toy scale (port of src/world/Backyard.ts).

const YARD := {"x0": -34.0, "x1": 34.0, "z0": -34.0, "z1": 34.0, "fence": 14.0, "deckY": 7.0}

## Jump pads up to the picnic table and the porch; ziplines (feet positions at each end). All ramps stay.
const PADS := [
	{"pos": Vector3(31.2, 0, -24), "to": Vector3(26.5, 7, -24)},  # picnic table
	{"pos": Vector3(24.5, 0, -5), "to": Vector3(30.5, 7, -5)},  # back porch
]
const ZIPS := [
	{"a": Vector3(-27.5, 11.0, -22.4), "b": Vector3(-25, 2.8, 22)},  # play tower <-> flower garden
	{"a": Vector3(27, 7.6, -18.6), "b": Vector3(30.5, 7.6, -9.4)},  # picnic table <-> back porch
	{"a": Vector3(27.6, 8.0, 7), "b": Vector3(20, 0.7, 18)},  # back porch <-> kiddie pool
	{"a": Vector3(14.4, 7.6, -24), "b": Vector3(0, 3.1, 0)},  # picnic table <-> sand castle
]

const HILL_SITES := [
	{"name": "the Sand Castle", "pos": Vector3(0, 2.5, 0), "radius": 3.8, "height": 4.0},
	{"name": "the Picnic Table", "pos": Vector3(21, 7, -24), "radius": 4.6, "height": 4.0},
	{"name": "the Back Porch", "pos": Vector3(30.5, 7, 1), "radius": 3.4, "height": 4.0},
	{"name": "the Kiddie Pool", "pos": Vector3(20, 0.12, 22), "radius": 5.0, "height": 5.0},
	{"name": "the Flower Garden", "pos": Vector3(-25, 2.2, 22), "radius": 4.6, "height": 4.0},
	{"name": "the Dump Truck", "pos": Vector3(-17, 0, 6), "radius": 4.4, "height": 5.0},
	{"name": "the Play Tower", "pos": Vector3(-26, 10, -26), "radius": 3.8, "height": 4.0},
]
## Sunrise = Play Tower, Moonbeam = Kiddie Pool, Clover = Flower Garden
const HOMES := [0, 2, 4]


static func sectors() -> Array:
	return [
		Modes.sector(HILL_SITES[6], "T", "Tower"),
		Modes.sector(HILL_SITES[1], "P", "Picnic"),
		Modes.sector(HILL_SITES[3], "K", "Pool"),
		Modes.sector(HILL_SITES[2], "H", "Porch"),
		Modes.sector(HILL_SITES[4], "F", "Garden"),
		Modes.sector(HILL_SITES[5], "D", "Truck"),
	]


## Grainy ground textures (grass with blades, sand, soil...). Drawn into an Image like the original's canvas.
static func noise_texture(base: String, amount: float, blades := 0, seed := 11) -> Texture2D:
	var key := "yardnoise:%s:%d:%d:%d" % [base, int(amount), blades, seed]
	if Tex.cache.has(key):
		return Tex.cache[key]
	var W := 256
	var img := Image.create(W, W, false, Image.FORMAT_RGBA8)
	var bc := Color(base)
	var r := U.seeded(seed)
	for y in W:
		for x in W:
			var n := (r.next() - 0.5) * amount / 255.0
			img.set_pixel(x, y, Color(clampf(bc.r + n, 0, 1), clampf(bc.g + n, 0, 1), clampf(bc.b + n * 0.6, 0, 1)))
	for i in blades:
		var x0 := r.next() * W
		var y0 := r.next() * W
		var light := r.next() < 0.5
		var col := Color(1, 1, 190 / 255.0, 0.16) if light else Color(20 / 255.0, 70 / 255.0, 20 / 255.0, 0.2)
		var x1 := x0 + (r.next() - 0.5) * 5
		var y1 := y0 - 4 - r.next() * 6
		var steps := 8
		for s in steps + 1:
			var k := float(s) / steps
			var px := posmod(int(x0 + (x1 - x0) * k), W)
			var py := posmod(int(y0 + (y1 - y0) * k), W)
			img.set_pixel(px, py, img.get_pixel(px, py).blend(col))
	var t := Tex.from_image(key, img)
	return t


static func siding_texture() -> Texture2D:
	if Tex.cache.has("siding"):
		return Tex.cache.siding
	var img := Image.create(64, 256, false, Image.FORMAT_RGBA8)
	var c0 := Color("#f1e6cf")
	var c1 := Color("#e2d2b2")
	var c2 := Color("#bda98a")
	for y in 256:
		var k := float(y % 32) / 32.0
		var c := c0.lerp(c1, k / 0.85) if k < 0.85 else c1.lerp(c2, (k - 0.85) / 0.15)
		for x in 64:
			img.set_pixel(x, y, c)
	return Tex.from_image("siding", img)


static func _ground_mat(tex: Texture2D, repeat: float, rough := 1.0) -> StandardMaterial3D:
	var m := Mats.textured(tex, rough)
	m.uv1_scale = Vector3(repeat, repeat, 1)
	return m


static func E(x: float, y: float, z: float) -> Basis:
	return U.euler(x, y, z)


static func build(root: Node3D, phys: Phys) -> Dictionary:
	var M := Mats.env()
	var batch := Batcher.new()
	var B := Builder.new(batch, phys)
	var animated := []
	var rnd := U.seeded(77)
	var Y := YARD
	var grass := _ground_mat(noise_texture("#5fae4a", 34, 2600), 18)
	var sand := _ground_mat(noise_texture("#ecd28f", 26, 0, 5), 6)
	var wet_sand := _ground_mat(noise_texture("#d9b76c", 24, 0, 6), 3, 0.95)
	var soil := _ground_mat(noise_texture("#5b3d26", 30, 0, 8), 4)
	var terracotta := Mats.std("#c8693d", 0.85)
	var leaf := Mats.std("#3f9b3a", 0.8)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	var hedge := _ground_mat(noise_texture("#2f7d32", 44, 900, 3), 6)
	var siding := Mats.textured(siding_texture(), 0.8)
	siding.uv1_scale = Vector3(1, 6, 1)
	var yellow := Mats.plastic("#ffd23f", {"rough": 0.3})
	var red := Mats.plastic("#e63946", {"rough": 0.3})
	var blue := Mats.plastic("#3a86ff", {"rough": 0.3})
	var white := Mats.plastic("#fffdf5", {"rough": 0.35})

	# ---------------------------------------------------------------- GROUND + FENCE
	B.box([Y.x0 - 2, -1, Y.z0 - 2], [Y.x1 + 2, 0, Y.z1 + 2], grass, "carpet")
	var F: float = Y.fence
	B.box([Y.x0 - 1, 0, Y.z0 - 1], [Y.x1 + 1, F, Y.z0], M.block_wood, "wood", {"tile": 1.0 / 10})
	B.box([Y.x0 - 1, 0, Y.z1], [Y.x1 + 1, F, Y.z1 + 1], M.block_wood, "wood", {"tile": 1.0 / 10})
	B.box([Y.x0 - 1, 0, Y.z0], [Y.x0, F, Y.z1], M.block_wood, "wood", {"tile": 1.0 / 10})
	# east side is the house wall
	B.box([Y.x1, 0, Y.z0], [Y.x1 + 1.5, 34, Y.z1], siding, "wood")
	# pickets + rails so the fence doesn't read as a flat wall
	var i := -33
	while i <= 33:
		B.box([i - 0.12, 0, Y.z0], [i + 0.12, F + 0.5, Y.z0 + 0.14], M.trim, "")
		B.box([i - 0.12, 0, Y.z1 - 0.14], [i + 0.12, F + 0.5, Y.z1], M.trim, "")
		B.box([Y.x0, 0, i - 0.12], [Y.x0 + 0.14, F + 0.5, i + 0.12], M.trim, "")
		i += 3
	for y in [3, 11]:
		B.box([Y.x0, y, Y.z0], [Y.x1, y + 0.5, Y.z0 + 0.3], M.bed_wood, "")
		B.box([Y.x0, y, Y.z1 - 0.3], [Y.x1, y + 0.5, Y.z1], M.bed_wood, "")
		B.box([Y.x0, y, Y.z0], [Y.x0 + 0.3, y + 0.5, Y.z1], M.bed_wood, "")
	# invisible walls above the fence + a lid, so nothing leaves the yard
	phys.box(Vector3(0, 28, Y.z0 - 0.5), Vector3(36, 14, 0.5), "wood")
	phys.box(Vector3(0, 28, Y.z1 + 0.5), Vector3(36, 14, 0.5), "wood")
	phys.box(Vector3(Y.x0 - 0.5, 28, 0), Vector3(0.5, 14, 36), "wood")
	phys.box(Vector3(0, 42.5, 0), Vector3(37, 0.5, 37), "wood")
	# hedges and a tree peeking over the fence
	for h in [[-40, -44, 40, -37], [-40, 37, 40, 44], [-44, -40, -37, 40]]:
		B.box([h[0], 0, h[1]], [h[2], 19, h[3]], hedge, "", {"round": 2.5, "cast": false})
	B.cyl([-41, 0, 30], 2.4, 30, Mats.std("#6b4a2f", 1), "", 10)
	for k in 9:
		var a := k * 2.4
		B.geo(Geo.icosahedron(6 + (k % 3) * 1.5, 1), leaf, [-41 + cos(a) * 7, 30 + (k % 4) * 2.5, 30 + sin(a) * 7])
	# house: door + window on the wall behind the porch
	B.box([Y.x1 - 0.15, 7, -3.5], [Y.x1 + 0.1, 22, 3.5], Mats.plastic("#4d6fa8", {"rough": 0.5}), "")
	B.box([Y.x1 - 0.25, 13.5, 2.2], [Y.x1 - 0.05, 14.5, 2.9], Mats.metal("#e2c36a", 0.3), "")
	B.box([Y.x1 - 0.15, 12, -9.5], [Y.x1 + 0.1, 20, -5], M.glass, "")
	B.box([Y.x1 - 0.2, 11.6, -9.9], [Y.x1 + 0.1, 12, -4.6], M.trim, "")
	B.box([Y.x1 - 0.2, 20, -9.9], [Y.x1 + 0.1, 20.4, -4.6], M.trim, "")

	# ---------------------------------------------------------------- SANDBOX + SAND CASTLE (center)
	var SB := {"x0": -12.0, "x1": 12.0, "z0": -10.0, "z1": 10.0, "h": 0.9, "sandY": 0.3}
	B.box([SB.x0, 0, SB.z0], [SB.x1, SB.h, SB.z0 + 1], M.block_wood, "wood", {"tile": 1.0 / 6})
	B.box([SB.x0, 0, SB.z1 - 1], [SB.x1, SB.h, SB.z1], M.block_wood, "wood", {"tile": 1.0 / 6})
	B.box([SB.x0, 0, SB.z0 + 1], [SB.x0 + 1, SB.h, SB.z1 - 1], M.block_wood, "wood", {"tile": 1.0 / 6})
	B.box([SB.x1 - 1, 0, SB.z0 + 1], [SB.x1, SB.h, SB.z1 - 1], M.block_wood, "wood", {"tile": 1.0 / 6})
	B.box([SB.x0 + 1, 0, SB.z0 + 1], [SB.x1 - 1, SB.sandY, SB.z1 - 1], sand, "carpet")
	# little ramps over the frame, outside and inside
	B.wedge([0, 0, SB.z1 + 1.6], PI, 1.6, SB.h, 3.2, M.bed_wood, "wood")
	B.wedge([0, 0, SB.z0 - 1.6], 0, 1.6, SB.h, 3.2, M.bed_wood, "wood")
	B.wedge([SB.x1 + 1.6, 0, 5], -PI / 2, 1.6, SB.h, 3.2, M.bed_wood, "wood")
	B.wedge([SB.x0 - 1.6, 0, -5], PI / 2, 1.6, SB.h, 3.2, M.bed_wood, "wood")
	B.wedge([0, SB.sandY, SB.z1 - 2.3], 0, 1.3, SB.h - SB.sandY, 3.2, wet_sand, "carpet")
	B.wedge([0, SB.sandY, SB.z0 + 2.3], PI, 1.3, SB.h - SB.sandY, 3.2, wet_sand, "carpet")
	B.wedge([SB.x1 - 2.3, SB.sandY, 5], PI / 2, 1.3, SB.h - SB.sandY, 3.2, wet_sand, "carpet")
	B.wedge([SB.x0 + 2.3, SB.sandY, -5], -PI / 2, 1.3, SB.h - SB.sandY, 3.2, wet_sand, "carpet")
	# castle: a raised courtyard with four towers and low battlements
	var CT := 2.5
	B.box([-4.5, SB.sandY, -4], [4.5, CT, 4], wet_sand, "carpet", {"round": 0.25})
	B.wedge([8.6, SB.sandY, 0], -PI / 2, 4.1, CT - SB.sandY, 3, wet_sand, "carpet")
	B.wedge([-8.6, SB.sandY, 0], PI / 2, 4.1, CT - SB.sandY, 3, wet_sand, "carpet")
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			B.cyl([sx * 4.5, SB.sandY, sz * 4], 1.25, 4.6, wet_sand, "carpet", 16)
			B.geo(Geo.cone(1.5, 1.8, 16), red, [sx * 4.5, SB.sandY + 4.6 + 0.9, sz * 4])
			for k in 6:
				var a := float(k) / 6 * TAU
				B.box([sx * 4.5 + cos(a) * 1.0 - 0.2, SB.sandY + 4.6, sz * 4 + sin(a) * 1.0 - 0.2], [sx * 4.5 + cos(a) * 1.0 + 0.2, SB.sandY + 4.95, sz * 4 + sin(a) * 1.0 + 0.2], wet_sand, "")
	for sz in [-1, 1]:
		for ab in [[-3, -1.2], [1.2, 3]]:
			B.box([ab[0], CT, sz * 4 - 0.25], [ab[1], CT + 0.85, sz * 4 + 0.25], wet_sand, "carpet")
	# bucket and spade
	B.cyl([7.6, SB.sandY, -6], 1.3, 2.7, blue, "plastic", 20, 1.6)
	B.geo(Geo.torus(1.6, 0.09, 6, 24, PI), white, [7.6, SB.sandY + 2.7, -6], E(0.5, 0.4, 0))
	B.obox([-7.4, SB.sandY + 0.12, 6.4], [0.9, 0.22, 3.2], E(0, 0.5, 0), red, "plastic", 0.08)
	B.obox([-6.4, SB.sandY + 0.16, 4.4], [1.6, 0.3, 1.6], E(0, 0.5, 0), red, "plastic", 0.12)
	B.geo(Geo.sphere(1.5, 16, 10, 0, TAU, 0, PI / 2), sand, [-7.5, SB.sandY, -5.5], Basis(), [1, 0.5, 1])
	B.geo(Geo.sphere(1.1, 16, 10, 0, TAU, 0, PI / 2), sand, [8, SB.sandY, 6.5], Basis(), [1, 0.45, 1])

	# ---------------------------------------------------------------- PICNIC TABLE (NE)
	var TY: float = Y.deckY
	B.box([13, TY - 0.5, -30], [29, TY, -18], M.desk, "wood", {"tile": 1.0 / 8})
	B.box([13, 3.1, -33.2], [29, 3.5, -31], M.desk, "wood", {"tile": 1.0 / 8})
	B.box([13, 3.1, -17], [29, 3.5, -14.8], M.desk, "wood", {"tile": 1.0 / 8})
	for x in [15, 27]:
		for z in [-28.8, -19.2]:
			B.box([x - 0.5, 0, z - 0.5], [x + 0.5, TY - 0.5, z + 0.5], M.bed_wood, "wood")
		for z in [-32.1, -15.9]:
			B.box([x - 0.4, 0, z - 0.4], [x + 0.4, 3.1, z + 0.4], M.bed_wood, "wood")
		B.box([x - 0.3, 2.6, -32.1], [x + 0.3, 3.1, -15.9], M.bed_wood, "")
	# gingham tablecloth strip down the middle
	B.box([13.2, TY, -25.6], [28.8, TY + 0.03, -22.4], Mats.plastic("#ef476f", {"rough": 0.9, "clearcoat": 0.0}), "", {"cast": false})
	var gx := 13.6
	while gx < 28.6:
		B.box([gx, TY + 0.03, -25.6], [gx + 0.8, TY + 0.04, -22.4], white, "", {"cast": false})
		gx += 1.6
	# plank up to the south bench, long plank up to the table top
	B.slab([21, 0, -8.8], [21, 3.5, -14.8], 2.6, 0.3, M.bed_wood, "wood")
	B.slab([3.2, 0, -24], [13, TY, -24], 2.8, 0.3, M.bed_wood, "wood")
	for k in range(1, 10):
		B.obox([3.2 + 9.8 * k / 10.0, TY * k / 10.0 + 0.05, -24], [0.16, 0.1, 2.6], E(0, 0, atan2(TY, 9.8)), M.trim, "")
	# things on the table to hide behind
	B.cyl([25.5, TY, -27.2], 1.5, 4.2, Mats.translucent("#ffe98a", 0.5), "glass", 20, 1.7)
	B.cyl([25.5, TY, -27.2], 1.35, 2.6, Mats.translucent("#ffd23f", 0.75), "", 20)
	B.cyl([16.2, TY, -20.6], 0.8, 3.2, red, "plastic", 14, 0.5)
	B.cyl([16.2, TY + 3.2, -20.6], 0.3, 0.5, white, "", 10)
	B.cyl([19.5, TY, -28], 1.7, 0.16, white, "plastic", 24)
	B.geo(Geo.sphere(1.0, 14, 10), Mats.plastic("#f4a261", {"rough": 0.8}), [19.5, TY + 0.6, -28], Basis(), [1, 0.6, 1])

	# ---------------------------------------------------------------- BACK PORCH (E)
	B.box([27, TY - 0.5, -10], [Y.x1, TY, 10], M.desk, "wood", {"tile": 1.0 / 8})
	for z in [-9.4, 0, 9.4]:
		B.box([26.8, 0, z - 0.4], [27.05, TY - 0.5, z + 0.4], M.trim, "")
	# lattice under the porch (solid so nobody gets lost under there)
	B.box([27, 0, -10], [Y.x1, TY - 0.5, 10], Mats.std("#d9cdb4", 0.9), "wood")
	B.wedge([17.4, 0, 6], PI / 2, 9.6, TY, 4, M.desk, "wood")
	# railing along the open edge, with gaps at the steps and the lift
	for ab in [[-10, -6.4], [-3.6, 4]]:
		B.box([27, TY + 0.9, ab[0]], [27.25, TY + 1.1, ab[1]], M.trim, "wood")
		var z: float = ab[0] + 0.3
		while z < ab[1]:
			B.box([27.05, TY, z - 0.06], [27.2, TY + 0.9, z + 0.06], M.trim, "")
			z += 0.9
		B.box([27, TY, ab[0]], [27.25, TY + 0.9, ab[1]], M.glass, "wood", {"visual": false})
	B.box([29, TY, -3.4], [33.6, TY + 0.06, 3.4], Mats.plastic("#7a5a3e", {"rough": 1.0, "clearcoat": 0.0}), "", {"cast": false})
	B.cyl([32, TY, 8], 1.2, 2.2, terracotta, "plastic", 16, 1.5)
	for k in 5:
		B.geo(Geo.cone(0.5, 2.6, 5), leaf, [32 + cos(k * 1.3) * 0.6, TY + 3.2, 8 + sin(k * 1.3) * 0.6], E(cos(k) * 0.3, 0, sin(k) * 0.3))
	B.box([30.6, TY, -8.8], [33.4, TY + 1.9, -6.6], M.cardboard_toys, "cardboard")

	# ---------------------------------------------------------------- KIDDIE POOL (SE)
	var PC := {"x": 20.0, "z": 22.0, "r": 8.5}
	var pool_mat := Mats.plastic("#48cae4", {"rough": 0.25})
	var N := 18
	for k in N:
		var a := float(k) / N * TAU
		var length: float = 2 * PC.r * tan(PI / N) + 0.35
		B.obox([PC.x + sin(a) * PC.r, 0.5, PC.z + cos(a) * PC.r], [length, 1.0, 0.9], E(0, a, 0), pool_mat if k % 2 else white, "plastic", 0.3)
	B.cyl([PC.x, 0, PC.z], PC.r - 0.3, 0.12, Mats.plastic("#90e0ef", {"rough": 0.4}), "plastic", 36)
	var wm := Mats.translucent("#7fd8ff", 0.42)
	wm.roughness = 0.05
	wm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	var water := Geo.circle(PC.r - 0.4, 40).mesh_instance(wm, Vector3(PC.x, 0.62, PC.z), Basis(Vector3.RIGHT, -PI / 2), false)
	root.add_child(water)
	animated.append(func(_dt: float, t: float) -> void: water.position.y = 0.62 + sin(t * 1.4) * 0.03)
	# rubber duck + beach ball
	B.cyl([PC.x + 1.5, 0.12, PC.z + 4], 1.5, 1.7, yellow, "plastic", 18)
	B.geo(Geo.sphere(1.7, 18, 12), yellow, [PC.x + 1.5, 1.2, PC.z + 4], Basis(), [1.15, 0.8, 1])
	B.geo(Geo.sphere(1.0, 16, 12), yellow, [PC.x + 2.6, 2.7, PC.z + 4])
	B.geo(Geo.cone(0.45, 0.9, 10), Mats.plastic("#ff7b00"), [PC.x + 3.7, 2.6, PC.z + 4], E(0, 0, -PI / 2))
	B.cyl([PC.x - 4, 0.12, PC.z - 2.5], 1.3, 2.6, white, "plastic", 14)
	var ball := [red, white, blue, yellow, white, Mats.plastic("#2dc653")]
	for k in 6:
		B.geo(Geo.sphere(1.5, 12, 10, float(k) / 6 * TAU, PI / 3), ball[k], [PC.x - 4, 1.6, PC.z - 2.5])

	# ---------------------------------------------------------------- PLAY TOWER + SLIDE (NW)
	var PT := 10.0
	B.box([-30, PT - 0.5, -30], [-22, PT, -22], M.bed_wood, "wood", {"tile": 1.0 / 6})
	for x in [-29.6, -22.4]:
		for z in [-29.6, -22.4]:
			B.box([x - 0.4, 0, z - 0.4], [x + 0.4, PT + 4.5, z + 0.4], M.block_wood, "wood")
	B.geo(Geo.cone(6.6, 3.6, 4), red, [-26, PT + 6.3, -26], E(0, PI / 4, 0))
	B.box([-30, PT, -30], [-22, PT + 1.1, -29.7], blue, "wood")
	B.box([-30, PT, -29.7], [-29.7, PT + 1.1, -22], blue, "wood")
	B.box([-25, PT, -22.3], [-22.8, PT + 1.1, -22], blue, "wood")
	B.box([-22.3, PT, -24.5], [-22, PT + 1.1, -22.8], blue, "wood")
	# the slide down to the east, and a climbing plank up from the south
	B.slab([-22, PT, -27.2], [-5.5, 0, -27.2], 3, 0.3, yellow, "plastic")
	var s_ang := atan2(PT, 16.5)
	var s_len := Vector2(PT, 16.5).length()
	for s in [-1, 1]:
		B.obox([-13.75, PT / 2 + 0.2, -27.2 + s * 1.45], [s_len, 0.5, 0.14], E(0, 0, -s_ang), Mats.plastic("#ff9f1c", {"rough": 0.3}), "")
	B.slab([-27.3, 0, -8.6], [-27.3, PT, -22], 2.6, 0.3, M.bed_wood, "wood")
	for k in range(1, 12):
		B.obox([-27.3, PT * k / 12.0 + 0.05, -8.6 - 13.4 * k / 12.0], [2.4, 0.1, 0.16], E(-atan2(PT, 13.4), 0, 0), M.trim, "")
	# bark chips under the tower
	B.box([-30.5, 0, -30.5], [-21.5, 0.04, -21.5], soil, "", {"cast": false})

	# ---------------------------------------------------------------- DUMP TRUCK (W)
	B.box([-31, 0, -5], [-19, 2, 1], Mats.plastic("#343a40", {"rough": 0.5}), "plastic", {"round": 0.2})
	B.box([-31, 2, -5], [-27.5, 5.5, 1], red, "plastic", {"round": 0.4})
	B.box([-27.6, 3.4, -4.4], [-27.4, 5, 0.4], M.glass, "")
	B.wedge([-19, 2, -2], -PI / 2, 8.5, 2.6, 5.6, yellow, "plastic")
	for z in [-4.9, 0.6]:
		B.obox([-23.25, 3.9, z], [8.9, 1.0, 0.3], E(0, 0, -atan2(2.6, 8.5)), yellow, "")
	B.wedge([-14.6, 0, -2], -PI / 2, 4.4, 2, 5.6, Mats.plastic("#ffbe0b", {"rough": 0.4}), "plastic")
	for x in [-29, -22]:
		for z in [-5.3, 1.3]:
			B.geo(Geo.cylinder(1.25, 1.25, 0.9, 18), Mats.plastic("#1d1d1f", {"rough": 0.8, "clearcoat": 0.0}), [x, 1.25, z], E(PI / 2, 0, 0))
	for xz in [[-15, 9.5], [-21.5, 8.5], [-13.5, -8]]:
		B.cyl([xz[0], 0, xz[1]], 0.75, 0.15, Mats.plastic("#ff7b00"), "", 12)
		B.cyl([xz[0], 0.15, xz[1]], 0.55, 1.7, Mats.plastic("#ff7b00"), "plastic", 12, 0.12)

	# ---------------------------------------------------------------- FLOWER GARDEN (SW)
	var GY := 2.2
	B.box([-32, 0, 14], [-18, GY - 0.1, 32], M.block_wood, "wood", {"tile": 1.0 / 6})
	B.box([-31.5, GY - 0.1, 14.5], [-18.5, GY, 31.5], soil, "carpet")
	B.wedge([-12.8, 0, 23], -PI / 2, 5.2, GY - 0.1, 3.4, M.bed_wood, "wood")
	B.wedge([-25, 0, 9.4], 0, 4.6, GY - 0.1, 3.2, M.bed_wood, "wood")
	var petals := ["#ff5d8f", "#ffd23f", "#c77dff", "#ff7b00", "#ffffff"]
	var flowers := [[-29.5, 17, 9], [-21, 17.5, 7.5], [-30, 24.5, 10.5], [-20.5, 29, 8.5], [-26, 30, 7]]
	for fi in flowers.size():
		var x: float = flowers[fi][0]
		var z: float = flowers[fi][1]
		var hgt: float = flowers[fi][2]
		B.cyl([x, GY, z], 0.32, hgt, leaf, "plastic", 8)
		var pm := Mats.plastic(petals[fi % petals.size()], {"rough": 0.5})
		for k in 7:
			var a := float(k) / 7 * TAU
			B.geo(Geo.sphere(1, 10, 8), pm, [x + cos(a) * 1.5, GY + hgt, z + sin(a) * 1.5], Basis(), [absf(cos(a)) * 0.5 + 0.7, 0.3, absf(sin(a)) * 0.5 + 0.7])
		B.geo(Geo.sphere(0.9, 12, 10), Mats.plastic("#7a4b12", {"rough": 0.9}), [x, GY + hgt + 0.1, z], Basis(), [1, 0.5, 1])
		B.geo(Geo.sphere(1.2, 8, 6), leaf, [x + 0.9, GY + hgt * 0.45, z], Basis(), [1, 0.12, 0.5])
	# gnome on the planter, pots on the lawn
	B.cyl([-28, GY, 28], 1.1, 2.6, blue, "plastic", 14, 0.8)
	B.geo(Geo.sphere(0.8, 14, 10), Mats.plastic("#ffd8b5", {"rough": 0.6}), [-28, GY + 3.1, 28])
	B.geo(Geo.cone(0.85, 2.2, 14), red, [-28, GY + 4.6, 28])
	B.geo(Geo.sphere(0.6, 10, 8), white, [-28, GY + 2.6, 27.4], Basis(), [1, 1.1, 0.5])
	B.cyl([-11.5, 0, 16], 1.8, 3.2, terracotta, "plastic", 18, 2.3)
	B.cyl([-11.5, 3.2, 16], 2.0, 0.1, soil, "", 18)
	B.cyl([-9, 0, 29], 1.4, 2.4, terracotta, "plastic", 16, 1.8)
	for k in 6:
		B.geo(Geo.cone(0.6, 3.4, 5), leaf, [-11.5 + cos(k * 1.1) * 0.9, 4.6, 16 + sin(k * 1.1) * 0.9], E(cos(k) * 0.35, 0, sin(k) * 0.35))

	# ---------------------------------------------------------------- LAWN PROPS
	# tree stump with a plank up it (south), soccer ball + skateboard (north), a few rocks
	B.cyl([1, 0, 24.2], 3.2, 2.6, Mats.std("#8a6238", 1), "wood", 14)
	B.cyl([1, 2.6, 24.2], 2.9, 0.05, M.block_wood, "", 14)
	B.wedge([1, 0, 16.6], 0, 4.5, 2.6, 3, M.bed_wood, "wood")
	B.cyl([-2, 0, -20], 2.1, 4.2, white, "plastic", 14)
	var soccer := Mats.std("#f8f9fa", 0.6)
	soccer.set_meta("flat", true)
	B.geo(Geo.icosahedron(2.5, 1), soccer, [-2, 2.4, -20])
	B.box([4.5, 0.55, -18.6], [12.5, 0.9, -16.2], Mats.plastic("#9b5de5", {"rough": 0.4}), "wood", {"round": 0.16})
	B.box([4.5, 0, -18.6], [12.5, 0.55, -16.2], M.glass, "wood", {"visual": false})
	for x in [5.8, 11.2]:
		for z in [-18.5, -16.3]:
			B.geo(Geo.cylinder(0.42, 0.42, 0.4, 12), yellow, [x, 0.42, z], E(PI / 2, 0, 0))
	for rk in [[14, 11, 1.3], [-14, 12.5, 1.1], [9, -12.5, 1.0], [-31, 4, 1.5], [8.5, 31, 1.4]]:
		var s: float = rk[2]
		B.geo(Geo.dodecahedron(s, 0), M.rock, [rk[0], s * 0.55, rk[1]], E(rnd.next(), rnd.next() * 3, rnd.next()))
		phys.cylinder(Vector3(rk[0], s * 0.5, rk[1]), s * 0.5, s * 0.8, "wood")
	# garden hose snaking across the lawn (decor)
	var hose := []
	for p in [[-33, 0.2, 10.5], [-24, 0.2, 11.5], [-14, 0.2, 14], [-6, 0.2, 13], [2, 0.2, 14.5], [9, 0.2, 13], [12, 0.2, 9]]:
		hose.append(Vector3(p[0], p[1], p[2]))
	B.geo(Geo.tube(hose, 60, 0.2, 8), Mats.plastic("#2dc653", {"rough": 0.5}), [0, 0, 0])
	B.cyl([12, 0, 9], 0.3, 0.6, Mats.metal("#d6b34a", 0.3), "", 10)
	# pinwheels
	for pw in [[-16.5, 13.2, "#ff5d8f"], [13.5, -11.5, "#3a86ff"]]:
		B.cyl([pw[0], 0, pw[1]], 0.08, 4.2, white, "", 6)
		var wheel := Node3D.new()
		for k in 4:
			wheel.add_child(Geo.cone(0.5, 1.5, 3).mesh_instance(Mats.plastic(pw[2] if k % 2 else "#ffd23f", {"rough": 0.4}), Vector3(cos(k * PI / 2) * 0.7, sin(k * PI / 2) * 0.7, 0), Basis(Vector3.BACK, k * PI / 2 - PI / 2)))
		wheel.position = Vector3(pw[0], 4.2, pw[1] + 0.15)
		root.add_child(wheel)
		animated.append(func(dt: float, _t: float) -> void: wheel.rotation.z += dt * 3.2)

	# ---------------------------------------------------------------- finish
	var block_spots := []
	var r := U.seeded(9)
	for k in 16:
		block_spots.append(Vector3(-10 + r.next() * 4.5, 1 + (k % 3) * 0.7, 5 + r.next() * 3.5))
	for k in 8:
		block_spots.append(Vector3(5.5 + r.next() * 4, 1 + (k % 3) * 0.7, -8 + r.next() * 1.6))
	B.build_studs(root)
	batch.build(root)
	var loose := LooseBricks.new(phys, block_spots, root, Vector3(-22, 3, 2))
	animated.append(loose.update)

	# ---------------------------------------------------------------- LIGHTING (afternoon sun)
	var sun_dir := Vector3(0.42, -0.78, 0.38).normalized()
	var sun := Lighting.sun(root, "#fff0cf", 5.4, sun_dir, 58)

	# ---------------------------------------------------------------- GAMEPLAY DATA
	var zones := [
		{"name": "Picnic Table", "min": [12, -34], "max": [34, -12], "ambience": "desk"},
		{"name": "Back Porch", "min": [24, -12], "max": [34, 11], "ambience": "closet"},
		{"name": "Kiddie Pool", "min": [10, 11], "max": [34, 34], "ambience": "garage"},
		{"name": "Flower Garden", "min": [-34, 9], "max": [-8, 34], "ambience": "dino"},
		{"name": "Play Tower", "min": [-34, -34], "max": [-12, -12], "ambience": "bed"},
		{"name": "Dump Truck", "min": [-34, -12], "max": [-13, 9], "ambience": "brick"},
		{"name": "Sandbox", "min": [-34, -34], "max": [34, 34], "ambience": "rug"},
	]
	var pickup_probes := [
		["health", 0, -14, 3], ["health", 8, 2.5, 2], ["health", -23.5, -2, 12], ["health", 21, -24, 5],
		["health", -24, 20, 8], ["health", 22, 18, 4], ["health", 31.5, 5.5, 12], ["health", -9, 20, 3],
		["shield", 0, 0, 8], ["shield", -28, -28, 13], ["turbo", -3.5, -27.2, 3], ["infinite", 1, 24.2, 6], ["power", 21, -24, 12],
	]
	return {
		"root": root, "zones": zones, "pickup_probes": pickup_probes, "animated": animated, "sun": sun, "sun_dir": sun_dir,
		"point_lights": [], "loose_bricks": loose,
		"bounds": AABB(Vector3(Y.x0, 0, Y.z0), Vector3(Y.x1 - Y.x0, 30, Y.z1 - Y.z0)),
		"window": {"x0": 0.0, "x1": 0.0, "y0": 0.0, "y1": 0.0, "z": 0.0},
	}

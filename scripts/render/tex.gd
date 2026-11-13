extends Node
## Procedural textures (port of src/render/textures.ts). Autoload "Tex".
## Textures are painted with CanvasItem draw calls inside an off-screen SubViewport, then copied into an
## ImageTexture with mipmaps. make() hands back the ImageTexture straight away; the picture lands a frame later.

const FONT_TITLE := preload("res://assets/fonts/luckiest-guy-latin-400-normal.woff2")
const FONT_BOLD := preload("res://assets/fonts/baloo-2-latin-700-normal.woff2")
const FONT_BODY := preload("res://assets/fonts/baloo-2-latin-500-normal.woff2")

var cache := {}
var _queue: Array = []
var _busy := false
var headless := false


class PaintNode extends Node2D:
	var fn: Callable

	func _draw() -> void:
		fn.call(self)


func _ready() -> void:
	headless = DisplayServer.get_name() == "headless"


## Queue a painted texture. draw(ci: CanvasItem) does the drawing in a w x h canvas.
## opts: mip (true), normal (bump->normal strength, 0 = off), bg (Color, clear color), placeholder (Color)
func make(key: String, w: int, h: int, draw: Callable, opts := {}) -> ImageTexture:
	if cache.has(key):
		return cache[key]
	var ph := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	ph.fill(opts.get("placeholder", Color(0.8, 0.78, 0.74)))
	var t := ImageTexture.create_from_image(ph)
	cache[key] = t
	if headless:
		return t
	_queue.append({"tex": t, "w": w, "h": h, "draw": draw, "opts": opts})
	if not _busy:
		_pump.call_deferred()
	return t


func _pump() -> void:
	if _busy:
		return
	_busy = true
	while _queue.size() > 0:
		var batch: Array = _queue.slice(0, 12)
		_queue = _queue.slice(12)
		var vps: Array = []
		for job in batch:
			var vp := SubViewport.new()
			vp.size = Vector2i(job.w, job.h)
			vp.transparent_bg = true
			vp.disable_3d = true
			vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
			vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
			var pn := PaintNode.new()
			pn.fn = job.draw
			vp.add_child(pn)
			add_child(vp)
			vps.append(vp)
		await RenderingServer.frame_post_draw
		for i in batch.size():
			var job: Dictionary = batch[i]
			var vp: SubViewport = vps[i]
			var img := vp.get_texture().get_image()
			if img:
				img.convert(Image.FORMAT_RGBA8)
				var o: Dictionary = job.opts
				if o.get("normal", 0.0) > 0.0:
					img.bump_map_to_normal_map(o.normal)
				if o.get("mip", true):
					img.generate_mipmaps()
				(job.tex as ImageTexture).set_image(img)
			vp.queue_free()
	_busy = false


## CPU-made image texture (noise etc.).
func from_image(key: String, img: Image, mip := true) -> ImageTexture:
	if cache.has(key):
		return cache[key]
	if mip:
		img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	cache[key] = t
	return t


static func noise_image(w: int, h: int, base: float, amp: float, seed: int) -> Image:
	var r := U.seeded(seed)
	var data := PackedByteArray()
	data.resize(w * h * 4)
	for i in w * h:
		var v := clampi(int(base + (r.next() - 0.5) * amp), 0, 255)
		data[i * 4] = v
		data[i * 4 + 1] = v
		data[i * 4 + 2] = v
		data[i * 4 + 3] = 255
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)


## Grey noise with alpha, drawn over painted textures to fake per-pixel "fiber" variation.
func grain(amp: float) -> Texture2D:
	var key := "grain%d" % int(amp)
	if cache.has(key):
		return cache[key]
	var r := U.seeded(1234 + int(amp))
	var data := PackedByteArray()
	var n := 256
	data.resize(n * n * 4)
	for i in n * n:
		var d := (r.next() - 0.5) * amp
		var v := 255 if d > 0 else 0
		data[i * 4] = v
		data[i * 4 + 1] = v
		data[i * 4 + 2] = v
		data[i * 4 + 3] = clampi(int(absf(d) * 2.0), 0, 255)
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	var t := ImageTexture.create_from_image(img)
	cache[key] = t
	return t


# ====================================================================== drawing helpers (canvas 2D API)
static func c(s, a := -1.0) -> Color:
	var col := U.col(s)
	if a >= 0:
		col.a = a
	return col


static func rgba(r: float, g: float, b: float, a := 1.0) -> Color:
	return Color(r / 255.0, g / 255.0, b / 255.0, a)


static func star_points(x: float, y: float, outer: float, inner: float, n := 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n * 2:
		var a := float(i) / (n * 2) * TAU + rot
		var rr := inner if i % 2 else outer
		pts.append(Vector2(x + cos(a) * rr, y + sin(a) * rr))
	return pts


static func ellipse_points(cx: float, cy: float, rx: float, ry: float, rot := 0.0, segs := 48) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var a := float(i) / segs * TAU
		var p := Vector2(cos(a) * rx, sin(a) * ry).rotated(rot)
		pts.append(Vector2(cx, cy) + p)
	return pts


static func quad_points(p0: Vector2, cp: Vector2, p1: Vector2, segs := 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segs + 1:
		var t := float(i) / segs
		pts.append(p0.lerp(cp, t).lerp(cp.lerp(p1, t), t))
	return pts


static func fill_poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	if pts.size() < 3:
		return
	var idx := Geometry2D.triangulate_polygon(pts)
	if idx.is_empty():
		ci.draw_colored_polygon(pts, col)
		return
	var i := 0
	while i + 2 < idx.size():
		ci.draw_colored_polygon(PackedVector2Array([pts[idx[i]], pts[idx[i + 1]], pts[idx[i + 2]]]), col)
		i += 3


static func round_rect(ci: CanvasItem, r: Rect2, radius: float, col: Color, filled := true, width := 1.0) -> void:
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(r.size.x - radius, radius), -PI / 2],
		[r.position + Vector2(r.size.x - radius, r.size.y - radius), 0.0],
		[r.position + Vector2(radius, r.size.y - radius), PI / 2],
		[r.position + Vector2(radius, radius), PI],
	]
	for cdef in corners:
		for k in 9:
			var a: float = cdef[1] + (PI / 2) * k / 8.0
			pts.append(cdef[0] + Vector2(cos(a), sin(a)) * radius)
	if filled:
		ci.draw_colored_polygon(pts, col)
	else:
		pts.append(pts[0])
		ci.draw_polyline(pts, col, width, true)


static func radial(ci: CanvasItem, center: Vector2, radius: float, stops: Array, segs := 48) -> void:
	# stops: [[t, Color], ...] t in 0..1
	for s in range(stops.size() - 1):
		var r0: float = radius * stops[s][0]
		var r1: float = radius * stops[s + 1][0]
		var c0: Color = stops[s][1]
		var c1: Color = stops[s + 1][1]
		for i in segs:
			var a0 := float(i) / segs * TAU
			var a1 := float(i + 1) / segs * TAU
			var d0 := Vector2(cos(a0), sin(a0))
			var d1 := Vector2(cos(a1), sin(a1))
			ci.draw_polygon(PackedVector2Array([center + d0 * r0, center + d0 * r1, center + d1 * r1, center + d1 * r0]),
				PackedColorArray([c0, c1, c1, c0]))


static func vgradient(ci: CanvasItem, r: Rect2, stops: Array) -> void:
	for s in range(stops.size() - 1):
		var y0: float = r.position.y + r.size.y * stops[s][0]
		var y1: float = r.position.y + r.size.y * stops[s + 1][0]
		var c0: Color = stops[s][1]
		var c1: Color = stops[s + 1][1]
		ci.draw_polygon(PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)]),
			PackedColorArray([c0, c0, c1, c1]))


## Text with canvas-style alignment ("center"/"left") and a vertically centered baseline.
static func text(ci: CanvasItem, font: Font, s: String, x: float, y: float, size: int, col: Color, align := "center", rot := 0.0) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := font.get_ascent(size)
	var desc := font.get_descent(size)
	var ox := -w / 2.0 if align == "center" else 0.0
	var oy := (asc - desc) / 2.0
	if rot != 0.0:
		ci.draw_set_transform(Vector2(x, y), rot, Vector2.ONE)
		ci.draw_string(font, Vector2(ox, oy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	else:
		ci.draw_string(font, Vector2(x + ox, y + oy), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func draw_grain(ci: CanvasItem, w: float, h: float, amp: float) -> void:
	ci.draw_texture_rect(grain(amp), Rect2(0, 0, w, h), true)


# ====================================================================== the textures
func scratch_roughness() -> Texture2D:
	return make("scratch", 512, 512, func(ci: CanvasItem):
		var r := U.seeded(11)
		ci.draw_rect(Rect2(0, 0, 512, 512), rgba(95, 95, 95))
		draw_grain(ci, 512, 512, 18)
		for i in 260:
			var x := r.next() * 512
			var y := r.next() * 512
			var a := r.next() * TAU
			var l := 6 + r.next() * 50
			var col := Color(1, 1, 1, 0.12 + r.next() * 0.3)
			var lw := 0.4 + r.next() * 1.1
			ci.draw_polyline(quad_points(Vector2(x, y), Vector2(x + cos(a + 0.3) * l * 0.5, y + sin(a + 0.3) * l * 0.5), Vector2(x + cos(a) * l, y + sin(a) * l), 8), col, lw, true)
		for i in 30:
			var col := rgba(160, 160, 160, 0.05 + r.next() * 0.08)
			ci.draw_circle(Vector2(r.next() * 512, r.next() * 512), 10 + r.next() * 40, col)
	, {"placeholder": Color(0.37, 0.37, 0.37)})


func wood(kind: String) -> Texture2D:
	return make("wood-" + kind, 1024, 1024, func(ci: CanvasItem):
		var W := 1024.0
		var H := 1024.0
		var r := U.seeded(kind.length() * 31 + 7)
		var pal: Array = {
			"floor": [[176, 120, 72], [160, 104, 60], [190, 134, 84], [150, 98, 58]],
			"desk": [[205, 160, 110], [196, 150, 100], [214, 170, 120]],
			"bed": [[236, 222, 200], [228, 214, 190]],
			"block": [[226, 190, 140], [216, 178, 126]],
		}[kind]
		var planks := 8 if kind == "floor" else (5 if kind == "desk" else 3)
		var ph := H / planks
		for p in planks:
			var col: Array = pal[p % pal.size()]
			var off := (r.next() - 0.5) * 18
			ci.draw_rect(Rect2(0, p * ph, W, ph), rgba(col[0] + off, col[1] + off, col[2] + off))
			for g in 70:
				var y0 := p * ph + r.next() * ph
				var gc := rgba(60 + r.next() * 40, 35 + r.next() * 20, 15, 0.06 + r.next() * 0.12)
				var lw := 0.6 + r.next() * 2.2
				var pts := PackedVector2Array()
				var wob := 2 + r.next() * 3
				var x := 0.0
				while x <= W:
					pts.append(Vector2(x, y0 + sin(x * 0.01 + g) * wob))
					x += 32
				ci.draw_polyline(pts, gc, lw, true)
			if r.next() > 0.4:
				var kx := r.next() * W
				var ky := p * ph + ph * (0.3 + r.next() * 0.4)
				for k in 6:
					ci.draw_polyline(ellipse_points(kx, ky, 18 - k * 2.5, 7 - k), rgba(80, 45, 20, 0.15 + k * 0.03), 1.5, true)
			if kind == "floor":
				ci.draw_rect(Rect2(0, p * ph, W, 3), rgba(40, 22, 10, 0.55))
				ci.draw_rect(Rect2(r.next() * W, p * ph, 3, ph), rgba(40, 22, 10, 0.55))
		for i in 120:
			var x := r.next() * W
			var y := r.next() * H
			ci.draw_line(Vector2(x, y), Vector2(x + (r.next() - 0.5) * 80, y + (r.next() - 0.5) * 20), rgba(255, 240, 220, 0.04 + r.next() * 0.08), 0.7, true)
	, {"placeholder": Color(0.7, 0.5, 0.32)})


func carpet() -> Texture2D:
	return make("carpet", 1024, 1024, func(ci: CanvasItem):
		var W := 1024.0
		ci.draw_rect(Rect2(0, 0, W, W), c("#4bb3a8"))
		ci.draw_circle(Vector2(W / 2, W / 2), W * 0.42, c("#f6c443"))
		ci.draw_circle(Vector2(W / 2, W / 2), W * 0.3, c("#ef6f6c"))
		ci.draw_circle(Vector2(W / 2, W / 2), W * 0.17, c("#5a7fd6"))
		fill_poly(ci, star_points(W / 2, W / 2, W * 0.12, W * 0.05), c("#fff3c4"))
		var corners := [Vector2(30, 30), Vector2(W - 30, 30), Vector2(W - 30, W - 30), Vector2(30, W - 30)]
		for i in 4:
			ci.draw_dashed_line(corners[i], corners[(i + 1) % 4], c("#fff6e0"), 10, 26)
		draw_grain(ci, W, W, 38)
	, {"placeholder": Color(0.3, 0.7, 0.66)})


func fiber_bump(seed := 3, scale := 1) -> Texture2D:
	var key := "fiber%d_%d" % [seed, scale]
	if cache.has(key):
		return cache[key]
	var img := noise_image(256, 256, 128, 120, seed)
	img.bump_map_to_normal_map(2.0)
	return from_image(key, img)


func quilt(a: String, b: String, stitch := "#ffffff") -> Texture2D:
	return make("quilt" + a + b, 512, 512, func(ci: CanvasItem):
		var W := 512.0
		var n := 4
		var s := W / n
		for i in n:
			for j in n:
				ci.draw_rect(Rect2(i * s, j * s, s, s), c(a if (i + j) % 2 else b))
				if (i + j) % 2 == 0:
					ci.draw_circle(Vector2(i * s + s / 2, j * s + s / 2), s * 0.18, Color(1, 1, 1, 0.35))
		var sc := c(stitch, 0.7)
		for i in n + 1:
			ci.draw_dashed_line(Vector2(i * s, 0), Vector2(i * s, W), sc, 3, 10)
			ci.draw_dashed_line(Vector2(0, i * s), Vector2(W, i * s), sc, 3, 10)
		draw_grain(ci, W, W, 20)
	, {"placeholder": U.col(a)})


func cardboard(label := "") -> Texture2D:
	return make("cardboard" + label, 512, 512, func(ci: CanvasItem):
		var W := 512.0
		var r := U.seeded(21 + label.length())
		ci.draw_rect(Rect2(0, 0, W, W), c("#c69a62"))
		var i := 0
		while i < W:
			ci.draw_rect(Rect2(i, 0, 2, W), rgba(120, 80, 40, 0.05 + r.next() * 0.05))
			i += 6
		for k in 400:
			ci.draw_rect(Rect2(r.next() * W, r.next() * W, 1 + r.next() * 4, 1 + r.next() * 4), rgba(90, 60, 30, r.next() * 0.12))
		ci.draw_rect(Rect2(W * 0.42, 0, W * 0.16, W), rgba(220, 190, 130, 0.75))
		if label != "":
			text(ci, FONT_TITLE, label, W / 2, W * 0.7 - 20, 64, rgba(160, 40, 30, 0.85), "center", -0.05)
	, {"placeholder": U.col("#c69a62")})


func wallpaper() -> Texture2D:
	return make("wallpaper", 512, 512, func(ci: CanvasItem):
		var W := 512.0
		ci.draw_rect(Rect2(0, 0, W, W), c("#bfe0f2"))
		for i in 8:
			ci.draw_rect(Rect2(i * (W / 8), 0, W / 16, W), Color(1, 1, 1, 0.35) if i % 2 else rgba(150, 200, 230, 0.25))
		var r := U.seeded(4)
		for i in 14:
			var sx := r.next() * W
			var sy := r.next() * W
			var ss := 10 + r.next() * 14
			fill_poly(ci, star_points(sx, sy, ss, ss * 0.42), c(["#ffe27a", "#ffffff", "#ffb3c7"][i % 3]))
		for i in 4:
			var x := r.next() * W
			var y := r.next() * W
			ci.draw_set_transform(Vector2(x, y), -0.6, Vector2.ONE)
			ci.draw_rect(Rect2(-6, -18, 12, 30), c("#ff7a6b"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-6, -18), Vector2(0, -30), Vector2(6, -18)]), c("#ff7a6b"))
			ci.draw_colored_polygon(PackedVector2Array([Vector2(-5, 12), Vector2(0, 24), Vector2(5, 12)]), c("#ffd25a"))
			ci.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	, {"placeholder": U.col("#bfe0f2")})


func sky() -> Texture2D:
	return make("sky", 1024, 512, func(ci: CanvasItem):
		var W := 1024.0
		var H := 512.0
		vgradient(ci, Rect2(0, 0, W, H), [[0.0, c("#7fb8ec")], [0.6, c("#ffd7a3")], [1.0, c("#ffe9c4")]])
		radial(ci, Vector2(W * 0.3, H * 0.45), 260, [[0.0, Color(1, 0.98, 0.9, 1)], [0.15, Color(1, 0.925, 0.706, 0.9)], [1.0, Color(1, 0.86, 0.63, 0)]])
		var r := U.seeded(12)
		for i in 9:
			var x := r.next() * W
			var y := 40 + r.next() * 160
			for k in 6:
				ci.draw_circle(Vector2(x + k * 26 - 60, y + sin(k) * 8), 22 + r.next() * 18, Color(1, 1, 1, 0.75))
		var hill := PackedVector2Array([Vector2(0, H)])
		var x2 := 0.0
		while x2 <= W:
			hill.append(Vector2(x2, H * 0.78 + sin(x2 * 0.008) * 30 + sin(x2 * 0.021) * 12))
			x2 += 16
		hill.append(Vector2(W, H))
		fill_poly(ci, hill, c("#7fae6a"))
		for i in 22:
			var x := r.next() * W
			var y := H * 0.8 + sin(x * 0.008) * 30
			ci.draw_circle(Vector2(x, y - 18), 14 + r.next() * 10, c("#5c8f55"))
	, {"placeholder": U.col("#ffd7a3")})


func soft_dot() -> Texture2D:
	return make("softdot", 64, 64, func(ci: CanvasItem):
		radial(ci, Vector2(32, 32), 32, [[0.0, Color(1, 1, 1, 1)], [0.4, Color(1, 1, 1, 0.6)], [1.0, Color(1, 1, 1, 0)]])
	, {"placeholder": Color(1, 1, 1, 0.3)})


func decal(kind: String) -> Texture2D:
	return make("decal" + kind, 128, 128, func(ci: CanvasItem):
		var W := 128.0
		var r := U.seeded(77 if kind == "impact" else 88)
		var o := Vector2(W / 2, W / 2)
		if kind == "impact":
			radial(ci, o, W * 0.4, [[0.0, Color(1, 1, 1, 1)], [0.35, Color(1, 1, 1, 0.7)], [1.0, Color(1, 1, 1, 0)]])
		else:
			ci.draw_circle(o, W * 0.24, Color.WHITE)
			for i in 14:
				var a := r.next() * TAU
				var d := W * (0.18 + r.next() * 0.22)
				var p := o + Vector2(cos(a), sin(a)) * d
				ci.draw_circle(p, 3 + r.next() * 9, Color.WHITE)
				ci.draw_line(o, p, Color.WHITE, 3 + r.next() * 4, true)
	, {"placeholder": Color(1, 1, 1, 0)})


func book(color: String, title: String) -> Texture2D:
	return make("book" + color + title, 256, 64, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 256, 64), c(color))
		ci.draw_rect(Rect2(0, 6, 256, 4), Color(1, 1, 1, 0.18))
		ci.draw_rect(Rect2(0, 54, 256, 4), Color(1, 1, 1, 0.18))
		text(ci, FONT_BOLD, title, 18, 33, 28, rgba(255, 250, 235, 0.9), "left")
	, {"placeholder": U.col(color)})


func keyboard_labels(rows: Array) -> Texture2D:
	return make("kblabels", 2048, 512, func(ci: CanvasItem):
		var W := 2048.0
		var H := 512.0
		var rh := H / rows.size()
		for ri in rows.size():
			var row: Array = rows[ri]
			var kw := W / row.size()
			for ki in row.size():
				text(ci, FONT_BOLD, row[ki], kw * (ki + 0.5), rh * (ri + 0.5), int(rh * 0.42), rgba(40, 40, 50, 0.85))
	, {"placeholder": Color(0, 0, 0, 0)})


func stripe_ball(a := "#ef476f", b := "#ffd166") -> Texture2D:
	return make("stripe" + a + b, 256, 128, func(ci: CanvasItem):
		var cols := [a, "#ffffff", b, "#118ab2"]
		for i in 8:
			ci.draw_rect(Rect2(i * 256.0 / 8, 0, 256.0 / 8 + 1, 128), c(cols[i % 4]))
	, {"placeholder": U.col(a)})


func letter_block(color: String, letter: String) -> Texture2D:
	return make("letter" + color + letter, 128, 128, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 128, 128), c("#e8cfa5"))
		ci.draw_rect(Rect2(8, 8, 112, 112), c(color))
		text(ci, FONT_TITLE, letter, 64, 66, 84, c("#fffaf0"))
	, {"placeholder": U.col(color)})


func sign(txt: String, color: String) -> Texture2D:
	return make("sign" + txt + color, 512, 128, func(ci: CanvasItem):
		round_rect(ci, Rect2(4, 4, 504, 120), 30, c(color))
		round_rect(ci, Rect2(4, 4, 504, 120), 30, Color.WHITE, false, 8)
		text(ci, FONT_TITLE, txt, 256, 66, 64, c("#fffaf0"))
	, {"placeholder": U.col(color)})


func face(kind: String, eye := "#222") -> Texture2D:
	return make("face" + kind + eye, 256, 256, func(ci: CanvasItem):
		if kind == "visor":
			var col := c(eye)
			for k in 6:
				var g := 20 - k * 4
				ci.draw_rect(Rect2(40 - g, 100 - g, 176 + g * 2, 40 + g * 2), Color(col.r, col.g, col.b, 0.06))
			ci.draw_rect(Rect2(40, 100, 176, 40), col)
	, {"placeholder": Color(0, 0, 0, 0)})


func fan_shadow() -> Texture2D:
	return make("fanshadow", 512, 512, func(ci: CanvasItem):
		var W := 512.0
		var o := Vector2(W / 2, W / 2)
		for i in 4:
			var rot := float(i) / 4 * TAU
			# a soft blade: ellipse that fades toward the tip
			for k in 10:
				var t := float(k) / 10
				var pts := ellipse_points(W * 0.24, 0, W * 0.22 * (1.0 - t * 0.6), W * 0.06 * (1.0 - t * 0.6), 0.08, 32)
				for j in pts.size():
					pts[j] = o + pts[j].rotated(rot)
				ci.draw_colored_polygon(pts, Color(0, 0, 0, 0.05))
		ci.draw_circle(o, W * 0.06, Color(0, 0, 0, 0.45))
	, {"placeholder": Color(0, 0, 0, 0)})


## A drawing pinned to the wall (crayon art). fn draws on a 256x200 page.
func drawing(key: String, fn: Callable) -> Texture2D:
	return make("drawing" + key, 256, 200, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 256, 200), c("#fffdf6"))
		fn.call(ci)
	, {"placeholder": U.col("#fffdf6")})


## Animated monitor screen: a live SubViewport (redrawn every frame), used as a ViewportTexture.
func monitor_screen() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = Vector2i(512, 320)
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var pn := PaintNode.new()
	var state := {"t": 0.0}
	pn.fn = func(ci: CanvasItem):
		var t: float = state.t
		ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(512, 0), Vector2(512, 320), Vector2(0, 320)]),
			PackedColorArray([c("#1d2b6b"), c("#3c2b77"), c("#5b2c83"), c("#3c2b77")]))
		text(ci, FONT_TITLE, "LEVEL 99", 256, 76, 44, c("#ffe36e"))
		for i in 8:
			var x := fmod(i * 70 + t * 60, 600.0) - 40
			ci.draw_rect(Rect2(x, 200 + sin(t * 3 + i) * 20, 28, 28), c(["#ff6b8b", "#6bf0ff", "#9dff6b"][i % 3]))
		var y := 0
		while y < 320:
			ci.draw_rect(Rect2(0, y, 512, 1), Color(1, 1, 1, 0.08))
			y += 4
	vp.add_child(pn)
	add_child(vp)
	return {"texture": vp.get_texture(), "update": func(time: float):
		state.t = time
		pn.queue_redraw()}

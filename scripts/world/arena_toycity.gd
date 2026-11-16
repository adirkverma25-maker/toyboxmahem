class_name ArenaToyCity
## Map 3: TOY CITY. A hobby-table model city: five model buildings around a fountain plaza, a park, a parking
## lot and a market street, with a model railway running round the edge of the table. Jump pads take you up
## to the rooftops and ziplines link them.

const CITY := {"x0": -34.0, "x1": 34.0, "z0": -34.0, "z1": 34.0}
## buildings: footprint, roof height, arcade side (open ground floor) and depth, colours
## buildings: footprint, roof height, arcade side (open ground floor) and depth, colours. All of them are hollow:
## doors on the ground floor, a floor per storey and a switchback staircase that ends in a roof hatch.
##  stairs: axis the flights run along, `a` = outer edge of lane A (against a wall), `bdir` = side lane B sits on,
##          `s` = where the first flight starts, `dir0` = direction the first flight climbs.
##  doors: [side, centre along that wall, width, height] on the ground-floor walls.
const BUILDINGS := {
	"townhall": {"x0": -9.0, "x1": 9.0, "z0": -25.0, "z1": -14.0, "roof": 9.0, "arcade": "s", "depth": 3.0, "wall": "#f1e3c8", "trim": "#b5651d", "win": "#7fb7d9", "floor": "#c9a27a",
		"stairs": {"axis": "x", "a": -24.4, "bdir": -1, "s": -4.9, "dir0": 1},
		"doors": [["s", -4.0, 2.4, 2.8], ["s", 4.0, 2.4, 2.8], ["e", -21.0, 2.0, 2.8], ["w", -19.0, 2.0, 2.8]]},
	"store": {"x0": 14.0, "x1": 25.0, "z0": -8.0, "z1": 8.0, "roof": 12.0, "arcade": "w", "depth": 3.0, "wall": "#e86a5c", "trim": "#fff3e0", "win": "#a9def9", "floor": "#d8d2c4",
		"stairs": {"axis": "z", "a": 24.2, "bdir": 1, "s": 0.8, "dir0": 1},
		"doors": [["w", 0.0, 3.0, 3.0], ["n", 19.5, 2.0, 2.8], ["s", 19.0, 2.0, 2.8]]},
	"apartments": {"x0": -25.0, "x1": -16.0, "z0": 12.0, "z1": 24.0, "roof": 16.0, "arcade": "n", "depth": 3.0, "wall": "#8ecae6", "trim": "#fefae0", "win": "#ffe8a3", "floor": "#b08968",
		"stairs": {"axis": "z", "a": -24.4, "bdir": -1, "s": 16.7, "dir0": 1},
		"doors": [["n", -18.6, 2.4, 2.8], ["e", 20.0, 2.0, 2.8]]},
	"firestation": {"x0": -25.0, "x1": -15.0, "z0": -10.0, "z1": 2.0, "roof": 7.0, "arcade": "e", "depth": 4.0, "wall": "#d62828", "trim": "#f8f9fa", "win": "#cde7f0", "floor": "#9aa5b1",
		"stairs": {"axis": "z", "a": -24.4, "bdir": -1, "s": -5.4, "dir0": 1},
		"doors": [["e", -2.5, 3.6, 3.2], ["s", -21.5, 2.0, 2.8]]},
	"hotel": {"x0": 12.0, "x1": 24.0, "z0": 14.0, "z1": 25.0, "roof": 10.0, "arcade": "n", "depth": 3.0, "wall": "#ffd166", "trim": "#7b2cbf", "win": "#bde0fe", "floor": "#8d5a97",
		"stairs": {"axis": "x", "a": 24.2, "bdir": 1, "s": 15.0, "dir0": 1},
		"doors": [["n", 15.5, 2.2, 2.8], ["n", 20.5, 2.2, 2.8], ["w", 20.0, 2.0, 2.8]]},
}

## jump pads: feet on the pad -> landing spot (y is snapped to whatever is below at load)
const PADS := [
	{"pos": Vector3(-3, 0, -9.5), "to": Vector3(-3, 9, -17)},  # plaza -> town hall
	{"pos": Vector3(6.5, 0, 6), "to": Vector3(20, 12, 4.5)},  # plaza -> department store
	{"pos": Vector3(-7, 0, 6), "to": Vector3(-20.5, 16, 18.5)},  # plaza -> apartments
	{"pos": Vector3(-10.5, 0, -6.5), "to": Vector3(-17.5, 7, -6.5)},  # avenue -> fire station
	{"pos": Vector3(7, 0, 11), "to": Vector3(17.5, 10, 20)},  # market -> hotel
	{"pos": Vector3(12.5, 0, -16), "to": Vector3(5, 9, -20)},  # park -> town hall
]
## ziplines: feet positions at each end (rooftop ends sit a metre above the roof, just inside the edge)
const ZIPS := [
	{"a": Vector3(-19, 17.0, 12.8), "b": Vector3(-6, 10.0, -14.8)},  # apartments <-> town hall
	{"a": Vector3(6.5, 10.0, -14.8), "b": Vector3(14.8, 13.0, -7.2)},  # town hall <-> department store
	{"a": Vector3(18, 13.0, 7.2), "b": Vector3(17, 11.0, 14.8)},  # department store <-> hotel
	{"a": Vector3(13.2, 11.0, 19), "b": Vector3(3, 0.6, 6.5)},  # hotel <-> plaza
	{"a": Vector3(-21, 17.0, 12.6), "b": Vector3(-19, 8.0, -0.8)},  # apartments <-> fire station
	{"a": Vector3(-16.3, 17.3, 12.3), "b": Vector3(-5, 0.6, 3.5)},  # apartments <-> plaza
]

const HILL_SITES := [
	{"name": "the Fountain Plaza", "pos": Vector3(0, 0, 0), "radius": 6.0, "height": 6.0},
	{"name": "the Town Hall roof", "pos": Vector3(2, 9, -17.5), "radius": 3.4, "height": 4.0},
	{"name": "the Department Store roof", "pos": Vector3(18.5, 12, 1), "radius": 4.0, "height": 4.0},
	{"name": "the Apartment roof", "pos": Vector3(-19.5, 16, 17.5), "radius": 3.0, "height": 4.0},
	{"name": "the Fire Station roof", "pos": Vector3(-17.8, 7, -5.5), "radius": 2.8, "height": 4.0},
	{"name": "the Hotel roof", "pos": Vector3(17.5, 10, 18.5), "radius": 3.5, "height": 4.0},
	{"name": "the Park", "pos": Vector3(18.5, 0, -19), "radius": 4.6, "height": 5.0},
]
## Sunrise = Apartments (SW), Moonbeam = Town Hall (N), Clover = Hotel (SE)
const HOMES := [0, 3, 5]


static func sectors() -> Array:
	return [
		Modes.sector(HILL_SITES[3], "A", "Apartments"),
		Modes.sector(HILL_SITES[4], "F", "Fire Station"),
		Modes.sector(HILL_SITES[0], "P", "Plaza"),
		Modes.sector(HILL_SITES[1], "T", "Town Hall"),
		Modes.sector(HILL_SITES[2], "D", "Store"),
		Modes.sector(HILL_SITES[5], "H", "Hotel"),
	]


static func E(x: float, y: float, z: float) -> Basis:
	return U.euler(x, y, z)


# ------------------------------------------------------------------ textures
## The painted baseboard of the whole model: grass flock, roads, pavements, plaza, park paths, parking bays,
## market square and the railway ballast. One texture over the 68 x 68 m table (north = top).
static func baseboard_texture() -> Texture2D:
	var S := 1024.0
	return Tex.make("toycity:board", 1024, 1024, func(ci: CanvasItem):
		var k := S / 68.0
		var R := func(x0: float, z0: float, x1: float, z1: float, col: Color) -> void:
			ci.draw_rect(Rect2((x0 + 34) * k, (z0 + 34) * k, (x1 - x0) * k, (z1 - z0) * k), col)
		var P := func(x: float, z: float) -> Vector2: return Vector2((x + 34) * k, (z + 34) * k)
		var grass := Color("#86b95b")
		var road := Color("#50545c")
		var walk := Color("#d9d0c1")
		var line := Color("#f5f1e6")
		ci.draw_rect(Rect2(0, 0, S, S), grass)
		# flock speckle
		var r := U.seeded(91)
		for i in 2600:
			var c := Color("#6fa34a") if i % 2 else Color("#9ccc6c")
			ci.draw_rect(Rect2(r.next() * S, r.next() * S, 3, 3), c)
		# railway ballast ring
		R.call(-31.6, -31.6, 31.6, 31.6, Color("#8d7b68"))
		R.call(-29.4, -29.4, 29.4, 29.4, grass)
		# ring road with a pavement on the inside
		R.call(-29.2, -29.2, 29.2, 29.2, road)
		R.call(-25.6, -25.6, 25.6, 25.6, walk)
		R.call(-25.0, -25.0, 25.0, 25.0, grass)
		for i in 30:
			var t := -27.0 + i * 1.9
			R.call(t, -27.55, t + 1.0, -27.35, line)
			R.call(t, 27.35, t + 1.0, 27.55, line)
			R.call(-27.55, t, -27.35, t + 1.0, line)
			R.call(27.35, t, 27.55, t + 1.0, line)
		# avenues: north (town hall), east (store), west (fire station), south (market)
		R.call(-5.2, -25.0, 5.2, 25.0, walk)
		R.call(-25.0, -5.2, 25.0, 5.2, walk)
		R.call(-4.0, -25.0, 4.0, 25.0, road)
		R.call(-25.0, -4.0, 25.0, 4.0, road)
		for i in 12:
			var t := -24.0 + i * 4.2
			R.call(t, -0.12, t + 2.2, 0.12, line)
			R.call(-0.12, t, 0.12, t + 2.2, line)
		# zebra crossings round the plaza
		for s in [-1, 1]:
			for i in 7:
				var o := -3.4 + i * 1.1
				R.call(o, s * 8.6 - 0.9, o + 0.55, s * 8.6 + 0.9, line)
				R.call(s * 8.6 - 0.9, o, s * 8.6 + 0.9, o + 0.55, line)
		# plaza: paved circle with a ring pattern
		ci.draw_circle(P.call(0, 0), 7.6 * k, Color("#e3d3b0"))
		ci.draw_arc(P.call(0, 0), 7.2 * k, 0, TAU, 64, Color("#c9b48a"), 4)
		ci.draw_arc(P.call(0, 0), 5.0 * k, 0, TAU, 64, Color("#c9b48a"), 3)
		for i in 16:
			var a := float(i) / 16 * TAU
			ci.draw_line(P.call(cos(a) * 3.6, sin(a) * 3.6), P.call(cos(a) * 7.2, sin(a) * 7.2), Color("#d2bf97"), 2)
		# pavements round the buildings
		for b in BUILDINGS.values():
			R.call(b.x0 - 1.2, b.z0 - 1.2, b.x1 + 1.2, b.z1 + 1.2, walk)
		# parking lot (NW)
		R.call(-25.0, -25.0, -11.5, -12.5, road)
		for i in 6:
			var x := -24.0 + i * 2.2
			R.call(x, -24.6, x + 0.15, -20.4, line)
			R.call(x, -17.2, x + 0.15, -12.9, line)
		# park (NE): darker lawn and a winding path
		R.call(11.5, -25.0, 25.0, -12.5, Color("#6aa84f"))
		var path := PackedVector2Array()
		for i in 21:
			var t := float(i) / 20
			path.append(P.call(11.5 + t * 13.5, -18.8 + sin(t * 6) * 2.2))
		ci.draw_polyline(path, Color("#d8c8a0"), 1.6 * k)
		ci.draw_circle(P.call(21, -21.5), 2.0 * k, Color("#5aa9e6"))
		# market square (S)
		R.call(-9.5, 13.0, 9.5, 25.0, Color("#cdbb9c"))
		for i in 9:
			for j in 6:
				if (i + j) % 2 == 0:
					R.call(-9.5 + i * 2.11, 13 + j * 2, -9.5 + i * 2.11 + 2.11, 15 + j * 2, Color("#c2ae8c"))
	, {"placeholder": Color("#86b95b")})


## One 3 x 3 m facade bay: wall, a framed window with a sill (or a shop window for ground floors).
static func facade_texture(key: String, wall: String, win: String, trim: String, shop := false, plain := false) -> Texture2D:
	return Tex.make("toycity:" + key + (":shop" if shop else "") + (":plain" if plain else ""), 128, 128, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 128, 128), Color(wall))
		# brick-ish texture lines
		var shade := Color(wall).darkened(0.08)
		for y in range(8, 128, 16):
			ci.draw_line(Vector2(0, y), Vector2(128, y), shade, 1)
		if plain:
			return  # the walls have real windows now (glass you can shoot out)
		if shop:
			ci.draw_rect(Rect2(14, 30, 100, 86), Color(trim))
			ci.draw_rect(Rect2(20, 36, 88, 80), Color(win))
			ci.draw_line(Vector2(64, 36), Vector2(64, 116), Color(trim), 4)
			ci.draw_rect(Rect2(10, 14, 108, 12), Color(trim))
		else:
			ci.draw_rect(Rect2(30, 24, 68, 78), Color(trim))
			ci.draw_rect(Rect2(36, 30, 56, 66), Color(win))
			ci.draw_line(Vector2(64, 30), Vector2(64, 96), Color(trim), 4)
			ci.draw_line(Vector2(36, 60), Vector2(92, 60), Color(trim), 4)
			ci.draw_rect(Rect2(26, 102, 76, 8), Color(trim).darkened(0.15))
			# a highlight in the glass
			ci.draw_line(Vector2(42, 36), Vector2(54, 48), Color(1, 1, 1, 0.55), 3)
	, {"placeholder": Color(wall)})


## Big painted sign (name of a building).
static func sign_mat(txt: String, bg: String, fg: String) -> StandardMaterial3D:
	var t := Tex.make("toycity:sign:" + txt, 512, 96, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 512, 96), Color(bg))
		ci.draw_rect(Rect2(6, 6, 500, 84), Color(fg), false, 4)
		Tex.text(ci, Tex.FONT_TITLE, txt, 256, 66, 54, Color(fg))
	, {"placeholder": Color(bg)})
	var m := Mats.textured(t, 0.5)
	return m


# ------------------------------------------------------------------ building
## Box between two corners with a rectangular hole cut out of it (hole = [min_x, min_z, max_x, max_z]).
static func _slab_with_hole(B: Builder, mn: Array, mx: Array, hole: Array, mat: Material, surf: String, opts := {}) -> void:
	if hole.is_empty():
		B.box(mn, mx, mat, surf, opts)
		return
	var hx0: float = maxf(hole[0], mn[0])
	var hz0: float = maxf(hole[1], mn[2])
	var hx1: float = minf(hole[2], mx[0])
	var hz1: float = minf(hole[3], mx[2])
	if hz0 > mn[2]:
		B.box(mn, [mx[0], mx[1], hz0], mat, surf, opts)
	if hz1 < mx[2]:
		B.box([mn[0], mn[1], hz1], mx, mat, surf, opts)
	if hx0 > mn[0]:
		B.box([mn[0], mn[1], hz0], [hx0, mx[1], hz1], mat, surf, opts)
	if hx1 < mx[0]:
		B.box([hx1, mn[1], hz0], [mx[0], mx[1], hz1], mat, surf, opts)


## One wall from a0 to a1 along `axis` ("x" or "z"), between c0..c1 across it, y0..y1, with doorways cut in.
## doors: [[centre, width, height], ...]
## With a `group`, the solid stretches are breakable "hard" panels about PANEL wide (lintels over the doors and
## the CORNER at each end of the run stay solid, so a building never ends up floating).
const PANEL := 1.8
const CORNER := 0.6
## windows: "" none, "home" (a window in each panel), "shop" (big shop windows): a real opening with a glass pane
## (breakable) and a frame round it (jambs, sill and header are hard pieces; the header and glass rest on them).
static var _glass_mat: StandardMaterial3D
static func _wall(B: Builder, axis: String, a0: float, a1: float, c0: float, c1: float, y0: float, y1: float, doors: Array, mat: Material, trim: Material, group := "", windows := "") -> void:
	if _glass_mat == null:
		_glass_mat = Mats.translucent("#bfe3f5", 0.38)
		_glass_mat.roughness = 0.05
	var piece := func(q0: float, q1: float, ya: float, yb: float, cls: String, rests: bool) -> void:
		if q1 - q0 < 0.03 or yb - ya < 0.03:
			return
		var origin2 := [a0, y0, c0] if axis == "x" else [c0, y0, a0]
		var m: Material = _glass_mat if cls == "glass" else mat
		var cc0 := c0
		var cc1 := c1
		if cls == "glass":
			var mid := (c0 + c1) / 2.0
			cc0 = mid - 0.03
			cc1 = mid + 0.03
		var opts := {"uv_origin": origin2, "rests": rests}
		if axis == "x":
			B.breakable_box([q0, ya, cc0], [q1, yb, cc1], m, cls, group, "glass" if cls == "glass" else "wood", opts)
		else:
			B.breakable_box([cc0, ya, q0], [cc1, yb, q1], m, cls, group, "glass" if cls == "glass" else "wood", opts)
	var solid := func(p0: float, p1: float, ya: float, yb: float) -> void:
		if p1 - p0 < 0.05 or yb - ya < 0.05:
			return
		if axis == "x":
			B.box([p0, ya, c0], [p1, yb, c1], mat, "wood", {"tile": 1.0 / 3})
		else:
			B.box([c0, ya, p0], [c1, yb, p1], mat, "wood", {"tile": 1.0 / 3})
	var origin := [a0, y0, c0] if axis == "x" else [c0, y0, a0]
	var box := func(p0: float, p1: float, ya: float, yb: float) -> void:
		if p1 - p0 < 0.05 or yb - ya < 0.05:
			return
		if group == "":
			solid.call(p0, p1, ya, yb)
			return
		# keep the building's corners solid
		if absf(p0 - a0) < 0.01:
			solid.call(p0, minf(p1, p0 + CORNER), ya, yb)
			p0 = minf(p1, p0 + CORNER)
		if absf(p1 - a1) < 0.01:
			solid.call(maxf(p0, p1 - CORNER), p1, ya, yb)
			p1 = maxf(p0, p1 - CORNER)
		if p1 - p0 < 0.05:
			return
		var n := maxi(1, roundi((p1 - p0) / PANEL))
		var step := (p1 - p0) / n
		for i in n:
			var q0 := p0 + i * step
			var q1 := q0 + step
			if windows == "" or step < 1.1 or yb - ya < 2.2:
				piece.call(q0, q1, ya, yb, "hard", false)
				continue
			# a window: jambs either side, a sill below, a header above, glass in the middle
			var ow := minf(1.3 if windows == "shop" else 1.0, step - 0.5)
			var jamb := (step - ow) / 2.0
			var sill: float = ya + (0.6 if windows == "shop" else 0.9)
			var head: float = minf(yb - 0.3, sill + (1.9 if windows == "shop" else 1.3))
			piece.call(q0, q0 + jamb, ya, yb, "hard", false)
			piece.call(q1 - jamb, q1, ya, yb, "hard", false)
			piece.call(q0 + jamb, q1 - jamb, ya, sill, "hard", false)
			piece.call(q0 + jamb, q1 - jamb, head, yb, "hard", true)
			piece.call(q0 + jamb, q1 - jamb, sill, head, "glass", true)
	var p := a0
	var ds := doors.duplicate()
	ds.sort_custom(func(x, y): return x[0] < y[0])
	for d in ds:
		var d0: float = d[0] - d[1] / 2.0
		var d1: float = d[0] + d[1] / 2.0
		var dh: float = d[2]
		box.call(p, d0, y0, y1)
		solid.call(d0, d1, y0 + dh, y1)  # lintel
		# door frame (visual)
		for e in [d0, d1]:
			if axis == "x":
				B.box([e - 0.12, y0, c0 - 0.08], [e + 0.12, y0 + dh + 0.12, c1 + 0.08], trim, "")
			else:
				B.box([c0 - 0.08, y0, e - 0.12], [c1 + 0.08, y0 + dh + 0.12, e + 0.12], trim, "")
		if axis == "x":
			B.box([d0 - 0.12, y0 + dh, c0 - 0.08], [d1 + 0.12, y0 + dh + 0.18, c1 + 0.08], trim, "")
		else:
			B.box([c0 - 0.08, y0 + dh, d0 - 0.12], [c1 + 0.08, y0 + dh + 0.18, d1 + 0.12], trim, "")
		p = d1
	box.call(p, a1, y0, y1)


## A model building you can walk into: ground floor with doors (and an open arcade on one side), a floor per
## storey, a switchback staircase up every storey and through a hatch onto the flat roof, windows on every face.
## Adds its interior light to `lights`.
static func _building(B: Builder, root: Node3D, d: Dictionary, key: String, lights: Array) -> void:
	var x0: float = d.x0
	var x1: float = d.x1
	var z0: float = d.z0
	var z1: float = d.z1
	var R: float = d.roof
	var dep: float = d.depth
	var GF := 3.6  # ground floor height
	var WT := 0.4  # wall thickness
	var SL := 0.3  # floor slab thickness
	var LANE := 1.8  # staircase lane width
	var wall := Mats.textured(facade_texture(key, d.wall, d.win, d.trim, false, true), 0.7)
	var shop := Mats.textured(facade_texture(key, d.wall, d.win, d.trim, true, true), 0.6)
	var trim := Mats.plastic(d.trim, {"rough": 0.4})
	var roof_m := Mats.std("#8d99ae", 0.9)
	var floor_m := Mats.textured(Tex.wood("floor"), 0.6, d.floor)
	var stair_m := Mats.plastic(d.floor, {"rough": 0.6, "clearcoat": 0.1})
	var tread_m := Mats.plastic("#3d405b", {"rough": 0.7, "clearcoat": 0.0})
	# ground footprint: set back on the arcade side
	var gx0 := x0
	var gx1 := x1
	var gz0 := z0
	var gz1 := z1
	match d.arcade:
		"n": gz0 = z0 + dep
		"s": gz1 = z1 - dep
		"w": gx0 = x0 + dep
		"e": gx1 = x1 - dep
	# floor levels: ground, first floor at GF, evenly spaced storeys, then the roof
	var n_up := maxi(1, floori((R - GF) / 3.0))
	var h := (R - GF) / n_up
	var levels := [0.0, GF]
	for k in range(1, n_up):
		levels.append(GF + k * h)
	levels.append(R)
	# ---- staircase: lane A against the wall, lane B beside it; flights alternate lanes and direction
	var st: Dictionary = d.stairs
	var sa: float = st.a
	var sb: float = sa - st.bdir * LANE
	var sc: float = sa - st.bdir * 2 * LANE
	var lane_a := [minf(sa, sb), maxf(sa, sb)]
	var lane_b := [minf(sb, sc), maxf(sb, sc)]
	var flights := []  # {lane, p0, p1, y0, y1, rail}
	var p: float = st.s
	for k in levels.size() - 1:
		var rise: float = levels[k + 1] - levels[k]
		var run := clampf(rise * 1.55, 5.0, 8.0)
		var dir: float = st.dir0 * (1 if k % 2 == 0 else -1)
		flights.append({"lane": lane_a if k % 2 == 0 else lane_b, "p0": p, "p1": p + dir * run, "y0": levels[k], "y1": levels[k + 1], "rail": sb if k % 2 == 0 else sc})
		p += dir * run
	# the opening above a flight: a little extra room past its foot, flush with the floor where it arrives
	var hole_of := func(f: Dictionary) -> Array:
		var up_dir: float = signf(f.p1 - f.p0)
		var foot: float = f.p0 - up_dir * 0.3
		var lo := minf(foot, f.p1)
		var hi := maxf(foot, f.p1)
		var c: Array = f.lane
		return [lo, c[0], hi, c[1]] if st.axis == "x" else [c[0], lo, c[1], hi]
	for f in flights:
		var c: Array = f.lane
		var cm: float = (c[0] + c[1]) / 2.0
		var from := [f.p0, f.y0, cm] if st.axis == "x" else [cm, f.y0, f.p0]
		var to := [f.p1, f.y1, cm] if st.axis == "x" else [cm, f.y1, f.p1]
		var r := B.slab(from, to, LANE, 0.25, stair_m, "wood")
		# treads (visual) and a handrail on the side away from the wall
		var vf := Builder.v(from)
		var vt := Builder.v(to)
		var steps := ceili(absf(float(f.p1) - float(f.p0)) / 0.45)
		var up: Vector3 = (r.basis as Basis) * Vector3.UP
		for i in range(1, steps):
			var q := vf.lerp(vt, float(i) / steps) + up * 0.02
			B.obox([q.x, q.y, q.z], [LANE, 0.05, 0.09], r.basis, tread_m, "")
		var rf := vf
		var rt := vt
		if st.axis == "x":
			rf.z = f.rail
			rt.z = f.rail
		else:
			rf.x = f.rail
			rt.x = f.rail
		B.geo(Geo.cylinder(0.05, 0.05, rf.distance_to(rt), 6), trim, [(rf.x + rt.x) / 2, (rf.y + rt.y) / 2 + 0.95, (rf.z + rt.z) / 2], Traversal._y_to((rt - rf).normalized()))
	# ---- ground floor walls (with doors) and floor
	var doors := {"n": [], "s": [], "w": [], "e": []}
	for dd in d.doors:
		doors[dd[0]].append([dd[1], dd[2], dd[3]])
	var gg := key + "-g"
	_wall(B, "x", gx0, gx1, gz0, gz0 + WT, 0, GF, doors.n, shop, trim, gg, "shop")
	_wall(B, "x", gx0, gx1, gz1 - WT, gz1, 0, GF, doors.s, shop, trim, gg, "shop")
	_wall(B, "z", gz0 + WT, gz1 - WT, gx0, gx0 + WT, 0, GF, doors.w, shop, trim, gg, "shop")
	_wall(B, "z", gz0 + WT, gz1 - WT, gx1 - WT, gx1, 0, GF, doors.e, shop, trim, gg, "shop")
	B.box([gx0 + WT, 0, gz0 + WT], [gx1 - WT, 0.03, gz1 - WT], floor_m, "", {"tile": 1.0 / 6, "cast": false})
	# ---- upper walls (full footprint, painted windows inside and out)
	# one band per storey, so a blast takes out a panel of one floor
	for k in range(1, levels.size() - 1):
		var b0: float = levels[k]
		var b1: float = levels[k + 1] if k + 2 < levels.size() else R - SL
		var sg := "%s-s%d" % [key, k]
		_wall(B, "x", x0, x1, z0, z0 + WT, b0, b1, [], wall, trim, sg, "home")
		_wall(B, "x", x0, x1, z1 - WT, z1, b0, b1, [], wall, trim, sg, "home")
		_wall(B, "z", z0 + WT, z1 - WT, x0, x0 + WT, b0, b1, [], wall, trim, sg, "home")
		_wall(B, "z", z0 + WT, z1 - WT, x1 - WT, x1, b0, b1, [], wall, trim, sg, "home")
	# ---- storey floors (each with the opening of the flight that arrives there) and the roof with its hatch
	for j in range(1, levels.size()):
		var y: float = levels[j]
		var hole: Array = hole_of.call(flights[j - 1])
		if j == levels.size() - 1:
			_slab_with_hole(B, [x0 - 0.25, y - SL, z0 - 0.25], [x1 + 0.25, y, z1 + 0.25], hole, roof_m, "wood")
			var hm := Mats.plastic("#ffd23f", {"rough": 0.4})
			B.box([hole[0] - 0.1, y, hole[1] - 0.1], [hole[2] + 0.1, y + 0.12, hole[1]], hm, "")
			B.box([hole[0] - 0.1, y, hole[3]], [hole[2] + 0.1, y + 0.12, hole[3] + 0.1], hm, "")
			B.box([hole[0] - 0.1, y, hole[1]], [hole[0], y + 0.12, hole[3]], hm, "")
			B.box([hole[2], y, hole[1]], [hole[2] + 0.1, y + 0.12, hole[3]], hm, "")
		else:
			_slab_with_hole(B, [x0 + WT, y - SL, z0 + WT], [x1 - WT, y, z1 - WT], hole, floor_m, "wood", {"tile": 1.0 / 6})
			if j == 1:
				# the arcade's ceiling strip along the outer edge
				match d.arcade:
					"n": B.box([x0, y - SL, z0], [x1, y, z0 + WT], trim, "wood")
					"s": B.box([x0, y - SL, z1 - WT], [x1, y, z1], trim, "wood")
					"w": B.box([x0, y - SL, z0], [x0 + WT, y, z1], trim, "wood")
					"e": B.box([x1 - WT, y - SL, z0], [x1, y, z1], trim, "wood")
	# ---- furniture on the upper storeys (cover), against the wall opposite the staircase
	var furn_cols := [d.trim, "#6c757d", "#e9c46a", "#2a9d8f"]
	var stairs_low: bool = sa < (((z0 + z1) / 2) if st.axis == "x" else ((x0 + x1) / 2))
	for j in range(1, levels.size() - 1):
		var y: float = levels[j]
		var fm := Mats.plastic(furn_cols[j % furn_cols.size()], {"rough": 0.5})
		for fr in [0.3, 0.7]:
			if st.axis == "x":
				var fx: float = lerpf(x0 + WT, x1 - WT, fr)
				var fz: float = (z1 - WT - 1.0) if stairs_low else (z0 + WT + 1.0)
				B.breakable_box([fx - 1.1, y, fz - 0.5], [fx + 1.1, y + 1.1, fz + 0.5], fm, "soft", key + "-f", "wood", {"round": 0.08})
			else:
				var fz2: float = lerpf(z0 + WT, z1 - WT, fr)
				var fx2: float = (x1 - WT - 1.0) if stairs_low else (x0 + WT + 1.0)
				B.breakable_box([fx2 - 0.5, y, fz2 - 1.1], [fx2 + 0.5, y + 1.1, fz2 + 1.1], fm, "soft", key + "-f", "wood", {"round": 0.08})
	# ---- arcade columns along the open edge
	var cols := []
	match d.arcade:
		"n", "s":
			var cz: float = (z0 + 0.45) if d.arcade == "n" else (z1 - 0.45)
			var x := x0 + 0.45
			while x <= x1 - 0.4:
				cols.append([x, cz])
				x += 3.0
			cols.append([x1 - 0.45, cz])
		"w", "e":
			var cx: float = (x0 + 0.45) if d.arcade == "w" else (x1 - 0.45)
			var z := z0 + 0.45
			while z <= z1 - 0.4:
				cols.append([cx, z])
				z += 3.0
			cols.append([cx, z1 - 0.45])
	for c in cols:
		B.box([c[0] - 0.4, 0, c[1] - 0.4], [c[0] + 0.4, GF - SL, c[1] + 0.4], trim, "wood", {"round": 0.08})
	# ---- exterior trim: floor bands and the cornice, as strips round the outside only
	var band := func(y0: float, y1: float, out: float) -> void:
		B.box([x0 - out, y0, z0 - out], [x1 + out, y1, z0], trim, "")
		B.box([x0 - out, y0, z1], [x1 + out, y1, z1 + out], trim, "")
		B.box([x0 - out, y0, z0], [x0, y1, z1], trim, "")
		B.box([x1, y0, z0], [x1 + out, y1, z1], trim, "")
	for j in range(1, levels.size() - 1):
		band.call(levels[j] - 0.15, levels[j] + 0.15, 0.12)
	band.call(R - 0.45, R - 0.25, 0.35)
	# ---- interior light (no shadows; it reaches every storey)
	lights.append(ArenaBedroom.omni(root, "#ffe9c4", 9, maxf(x1 - x0, z1 - z0) + R, 1.3, Vector3((x0 + x1) / 2, R * 0.5, (z0 + z1) / 2)))


static func _tree(B: Builder, base: Array, s: float, leaf: Material) -> void:
	var trunk := Mats.plastic("#8b5a2b", {"rough": 0.7, "clearcoat": 0.1})
	B.cyl(base, 0.3 * s, 2.6 * s, trunk, "wood", 10, 0.22 * s)
	var top: float = base[1] + 2.6 * s
	B.geo(Geo.icosahedron(1.7 * s, 1), leaf, [base[0], top + 0.9 * s, base[2]])
	B.geo(Geo.icosahedron(1.2 * s, 1), leaf, [base[0] + 0.9 * s, top + 0.3 * s, base[2] + 0.4 * s])
	B.geo(Geo.icosahedron(1.1 * s, 1), leaf, [base[0] - 0.8 * s, top + 0.4 * s, base[2] - 0.5 * s])


static func _lamp_post(B: Builder, base: Array, pole: Material, glow: Material) -> void:
	B.cyl(base, 0.12, 4.2, pole, "metal", 8)
	B.geo(Geo.sphere(0.32, 12, 8), glow, [base[0], base[1] + 4.4, base[2]])


static func _cone(B: Builder, base: Array, orange: Material, white: Material) -> void:
	B.cyl(base, 0.45, 1.1, orange, "plastic", 12, 0.08)
	B.geo(Geo.cylinder(0.27, 0.32, 0.18, 12), white, [base[0], base[1] + 0.55, base[2]])
	B.box([base[0] - 0.55, base[1], base[2] - 0.55], [base[0] + 0.55, base[1] + 0.12, base[2] + 0.55], orange, "")


static func _ac_unit(B: Builder, base: Array, yaw: float) -> void:
	var body := Mats.plastic("#ced4da", {"rough": 0.5})
	B.obox([base[0], base[1] + 0.6, base[2]], [1.8, 1.2, 1.2], E(0, yaw, 0), body, "metal", 0.08)
	B.geo(Geo.cylinder(0.42, 0.42, 0.06, 16), Mats.plastic("#495057"), [base[0], base[1] + 1.23, base[2]])


# ------------------------------------------------------------------ build
static func build(root: Node3D, phys: Phys) -> Dictionary:
	var C := CITY
	var M := Mats.env()
	var batch := Batcher.new()
	var B := Builder.new(batch, phys)
	var animated := []
	var white := Mats.plastic("#fffdf5", {"rough": 0.35})
	var red := Mats.plastic("#e63946", {"rough": 0.3})
	var yellow := Mats.plastic("#ffd23f", {"rough": 0.3})
	var blue := Mats.plastic("#3a86ff", {"rough": 0.3})
	var orange := Mats.plastic("#ff7b00", {"rough": 0.4})
	var green := Mats.plastic("#2dc653", {"rough": 0.35})
	var leaf := Mats.plastic("#3f9b3a", {"rough": 0.6, "clearcoat": 0.1})
	leaf.set_meta("flat", true)
	var leaf2 := Mats.plastic("#57b846", {"rough": 0.6, "clearcoat": 0.1})
	leaf2.set_meta("flat", true)
	var stone := Mats.std("#d6ccc2", 0.8)
	var pole := Mats.metal("#3d405b", 0.4)
	var lamp_glow := Mats.glow("#fff3c4", 2.5)
	var wood: StandardMaterial3D = M.desk

	# ---------------------------------------------------------------- THE TABLE
	# play surface (painted baseboard) and the table around it
	B.box([-37, -1.5, -37], [37, 0, 37], wood, "wood", {"visual": false})
	var board := Mats.textured(baseboard_texture(), 0.85)
	var bp := Geo.plane(68, 68).mesh_instance(board, Vector3(0, 0.005, 0), Basis(Vector3.RIGHT, -PI / 2))
	bp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bp)
	B.box([-37, -1.5, -37], [37, -0.02, 37], wood, "", {"tile": 1.0 / 10})
	# raised wooden lip round the edge, then invisible walls
	for e in [[[-34.6, 0, -34.6], [34.6, 0.5, -34.0]], [[-34.6, 0, 34.0], [34.6, 0.5, 34.6]], [[-34.6, 0, -34.0], [-34.0, 0.5, 34.0]], [[34.0, 0, -34.0], [34.6, 0.5, 34.0]]]:
		B.box(e[0], e[1], M.bed_wood, "wood", {"round": 0.12})
	phys.box(Vector3(0, 20, C.z0 - 0.5), Vector3(36, 21, 0.5), "wood")
	phys.box(Vector3(0, 20, C.z1 + 0.5), Vector3(36, 21, 0.5), "wood")
	phys.box(Vector3(C.x0 - 0.5, 20, 0), Vector3(0.5, 21, 36), "wood")
	phys.box(Vector3(C.x1 + 0.5, 20, 0), Vector3(0.5, 21, 36), "wood")
	# table legs and the hobby room far below and around (visual only)
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			B.box([sx * 33 - 2.5, -46, sz * 33 - 2.5], [sx * 33 + 2.5, -1.5, sz * 33 + 2.5], wood, "", {"cast": false})
	B.box([-160, -47, -160], [160, -46, 160], Mats.textured(Tex.wood("floor"), 0.6), "", {"tile": 1.0 / 24, "cast": false})
	var room_wall := Mats.std("#e9dfcf", 0.95)
	B.box([-160, -46, -121], [160, 80, -120], room_wall, "", {"cast": false})
	B.box([-160, -46, 120], [160, 80, 121], room_wall, "", {"cast": false})
	B.box([-121, -46, -120], [-120, 80, 120], room_wall, "", {"cast": false})
	B.box([120, -46, -120], [121, 80, 120], room_wall, "", {"cast": false})
	# a window in the north wall
	var sky_m := Mats.basic("#ffffff", Tex.sky())
	sky_m.disable_fog = true
	root.add_child(Geo.plane(70, 40).mesh_instance(sky_m, Vector3(-20, 30, -119.4), Basis(), false))
	B.box([-57, 8, -120], [17, 10, -117], M.trim, "", {"cast": false})
	B.box([-57, 50, -120], [17, 52, -117], M.trim, "", {"cast": false})
	# a shelf of paint pots and model kits on the west wall
	B.box([-120, 22, -40], [-108, 23.5, 40], wood, "", {"cast": false})
	var pot_cols := ["#e63946", "#ffd23f", "#3a86ff", "#2dc653", "#ff7b00", "#7b2cbf", "#f8f9fa", "#1d1d1f"]
	for i in 14:
		var z := -34.0 + i * 5
		B.geo(Geo.cylinder(1.6, 1.6, 3.4, 16), Mats.plastic(pot_cols[i % pot_cols.size()], {"rough": 0.3}), [-113, 25.2, z], Basis(), null, false)
		B.geo(Geo.cylinder(1.7, 1.7, 0.5, 16), Mats.plastic("#2b2d42"), [-113, 27.1, z], Basis(), null, false)
	for i in 4:
		B.box([-117, 23.5, -30 + i * 16], [-110, 30 + (i % 2) * 4, -22 + i * 16], Mats.plastic(pot_cols[(i * 3) % 8], {"rough": 0.6}), "", {"cast": false})
	# the big desk lamp clamped to the table's north-east corner (the light source)
	var lamp_m := Mats.metal("#2d6a4f", 0.35)
	B.cyl([37.5, -6, -37.5], 2.0, 8, lamp_m, "", 16)
	B.obox([36, 24, -36], [1.2, 60, 1.2], E(0.2, 0, -0.15), lamp_m, "")
	B.obox([24, 52, -24], [1.0, 36, 1.0], E(0.75, 0.0, 0.75), lamp_m, "")
	var shade := Mats.metal("#2d6a4f", 0.35)
	shade.cull_mode = BaseMaterial3D.CULL_DISABLED
	B.geo(Geo.cone(7, 9, 32, 1, true), shade, [12, 60, -12], E(0.35, 0, 0.35), null, false)
	B.geo(Geo.sphere(2.6, 16, 12), Mats.glow("#fff2c6", 5), [11, 56.5, -11], Basis(), null, false)

	# ---------------------------------------------------------------- MODEL RAILWAY (track is decor)
	var sleeper := Mats.plastic("#6b4f3a", {"rough": 0.8, "clearcoat": 0.0})
	var rail := Mats.metal("#9aa0a6", 0.35)
	var loop := ToyCityAmbient.loop_points(0.8)
	for i in loop.size():
		var p: Vector3 = loop[i][0]
		var t: Vector3 = loop[i][1]
		var yaw := atan2(t.x, t.z)
		B.geo(Geo.box(2.1, 0.08, 0.32), sleeper, [p.x, 0.04, p.z], E(0, yaw, 0), null, false)
		for s in [-0.55, 0.55]:
			var side: Vector3 = Vector3(t.z, 0, -t.x) * float(s)
			B.geo(Geo.box(0.1, 0.12, 0.84), rail, [p.x + side.x, 0.14, p.z + side.z], E(0, yaw, 0), null, false)
	# station platform (east side) with a little shelter
	B.box([31.8, 0, -6], [33.6, 0.5, 6], stone, "plastic")
	B.box([32.2, 0.5, -2.5], [33.6, 3.2, -2.2], white, "plastic")
	B.box([32.0, 3.2, -2.8], [33.8, 3.45, 2.8], red, "")

	# ---------------------------------------------------------------- BUILDINGS
	var lights := []
	for key in BUILDINGS:
		_building(B, root, BUILDINGS[key], key, lights)
	var tb: Dictionary = BUILDINGS.townhall
	# town hall: front steps, a clock gable and a flagpole on the roof
	for i in 3:
		B.box([-6.5 + i * 0.4, 0, tb.z1 + 1.4 - i * 0.45], [6.5 - i * 0.4, 0.22 * (i + 1), tb.z1 + 1.85 - i * 0.45 + 0.45], stone, "plastic")
	B.box([-3.5, tb.roof, -25.2], [3.5, tb.roof + 3.0, -24.2], Mats.plastic(tb.wall, {"rough": 0.6}), "wood")
	B.geo(Geo.cylinder(1.2, 1.2, 0.2, 24), white, [0, tb.roof + 1.6, -24.05], E(PI / 2, 0, 0))
	B.geo(Geo.box(0.12, 0.9, 0.05), Mats.plastic("#1d1d1f"), [0, tb.roof + 1.85, -23.92], Basis(), null, false)
	B.geo(Geo.box(0.6, 0.12, 0.05), Mats.plastic("#1d1d1f"), [0.25, tb.roof + 1.6, -23.92], Basis(), null, false)
	B.cyl([7.5, tb.roof, -23.5], 0.1, 5, pole, "", 8)
	B.geo(Geo.box(2.2, 1.3, 0.05), red, [6.3, tb.roof + 4.3, -23.5], Basis(), null, false)
	var th_sign := sign_mat("TOWN HALL", "#b5651d", "#fff3e0")
	root.add_child(Geo.plane(8, 1.5).mesh_instance(th_sign, Vector3(0, 6.1, tb.z1 + 0.13), Basis()))
	_ac_unit(B, [-7.5, tb.roof, -18.8], 0)
	_ac_unit(B, [4.5, tb.roof, -16.6], PI / 2)
	# department store: rooftop billboard (cover) and a sign over the arcade
	var sb: Dictionary = BUILDINGS.store
	B.box([23.2, sb.roof, -6.5], [23.6, sb.roof + 3.4, -0.8], white, "wood")
	root.add_child(Geo.plane(5.6, 3.0).mesh_instance(sign_mat("TOY STORE", "#ffd23f", "#e63946"), Vector3(23.15, sb.roof + 1.9, -3.65), Basis(Vector3.UP, -PI / 2)))
	root.add_child(Geo.plane(8, 1.5).mesh_instance(sign_mat("DEPARTMENT STORE", "#e86a5c", "#fff3e0"), Vector3(sb.x0 - 0.13, 6.1, 0), Basis(Vector3.UP, -PI / 2)))
	_ac_unit(B, [17, sb.roof, -1.5], 0)
	_ac_unit(B, [20.5, sb.roof, 3.5], PI / 2)
	# apartments: water tank on stilts, washing lines, balconies
	var ab: Dictionary = BUILDINGS.apartments
	for p in [[-19.6, 20.5], [-17.4, 20.5], [-19.6, 22.5], [-17.4, 22.5]]:
		B.box([p[0] - 0.15, ab.roof, p[1] - 0.15], [p[0] + 0.15, ab.roof + 1.6, p[1] + 0.15], pole, "metal")
	B.cyl([-18.5, ab.roof + 1.6, 21.5], 1.5, 2.4, Mats.plastic("#adb5bd", {"rough": 0.5}), "metal", 18)
	B.geo(Geo.cone(1.6, 0.8, 18), Mats.plastic("#6c757d"), [-18.5, ab.roof + 4.4, 21.5])
	for y in [6.6, 9.6, 12.6]:
		B.box([ab.x0 + 2.5, y - 0.15, ab.z1], [ab.x1 - 2.5, y, ab.z1 + 1.2], Mats.plastic(ab.trim), "plastic")
		B.box([ab.x0 + 2.5, y, ab.z1 + 1.1], [ab.x1 - 2.5, y + 0.8, ab.z1 + 1.2], pole, "")
	_ac_unit(B, [-23.5, ab.roof, 14.2], 0)
	# fire station: hose tower, big door frames on the open (east) side, a fire engine inside
	var fb: Dictionary = BUILDINGS.firestation
	B.box([-25, fb.roof, -10], [-22, 12, -7], Mats.textured(facade_texture("hose", fb.wall, fb.win, fb.trim), 0.7), "wood", {"tile": 1.0 / 3})
	B.box([-25.2, 12, -10.2], [-21.8, 12.4, -6.8], Mats.std("#8d99ae", 0.9), "wood")
	root.add_child(Geo.plane(7, 1.3).mesh_instance(sign_mat("FIRE STATION", "#f8f9fa", "#d62828"), Vector3(fb.x1 + 0.13, 4.9, -4), Basis(Vector3.UP, PI / 2)))
	# fire engine (cover in the garage)
	B.box([-20.5, 0.4, -7.5], [-16.3, 2.4, -5.2], red, "plastic", {"round": 0.2})
	B.box([-17.6, 2.4, -7.3], [-16.3, 3.3, -5.4], red, "plastic", {"round": 0.2})
	B.box([-20.3, 2.4, -6.9], [-17.8, 2.6, -5.8], Mats.metal("#ced4da"), "")
	for w in [[-19.6, -7.6], [-19.6, -5.1], [-17.0, -7.6], [-17.0, -5.1]]:
		B.geo(Geo.cylinder(0.45, 0.45, 0.3, 14), Mats.rubber("#1d1d1d"), [w[0], 0.45, w[1]], E(PI / 2, 0, 0))
	_ac_unit(B, [-17.5, fb.roof, -8.5], 0)
	# hotel: striped awning over the arcade and a roof sign
	var hb: Dictionary = BUILDINGS.hotel
	var stripe_t := Tex.make("toycity:awning", 64, 64, func(ci: CanvasItem):
		for i in 8:
			ci.draw_rect(Rect2(i * 8, 0, 8, 64), Color("#7b2cbf") if i % 2 else Color("#fffdf5"))
	, {"placeholder": Color("#7b2cbf")})
	var awning := Mats.textured(stripe_t, 0.6)
	awning.uv1_scale = Vector3(6, 1, 1)
	B.obox([(hb.x0 + hb.x1) / 2, 3.9, hb.z0 - 0.7], [hb.x1 - hb.x0, 0.12, 1.8], E(-0.25, 0, 0), awning, "")
	B.box([23.4, hb.roof, 15.0], [23.8, hb.roof + 2.6, 21.0], white, "wood")
	root.add_child(Geo.plane(5.8, 2.2).mesh_instance(sign_mat("HOTEL", "#7b2cbf", "#ffd23f"), Vector3(23.85, hb.roof + 1.4, 18.0), Basis(Vector3.UP, PI / 2)))
	_ac_unit(B, [21.8, hb.roof, 16.6], 0)

	# ---------------------------------------------------------------- PLAZA + FOUNTAIN (centre)
	B.cyl([0, 0, 0], 3.3, 0.8, stone, "plastic", 32)
	var water := Mats.translucent("#5aa9e6", 0.7)
	water.roughness = 0.05
	var wdisc := Geo.circle(2.95, 32).mesh_instance(water, Vector3(0, 0.82, 0), Basis(Vector3.RIGHT, -PI / 2), false)
	root.add_child(wdisc)
	B.cyl([0, 0.8, 0], 0.45, 2.2, stone, "plastic", 16)
	B.geo(Geo.cylinder(1.4, 0.6, 0.45, 24), stone, [0, 3.1, 0])
	B.geo(Geo.sphere(0.45, 14, 10), Mats.plastic("#ffd23f", {"rough": 0.3}), [0, 3.75, 0])
	animated.append(func(_dt: float, t: float) -> void: wdisc.position.y = 0.82 + sin(t * 1.7) * 0.02)
	# benches and trees round the plaza
	for a in [PI / 4, 3 * PI / 4, 5 * PI / 4, 7 * PI / 4]:
		var bx := cos(a) * 6.0
		var bz := sin(a) * 6.0
		B.obox([bx, 0.45, bz], [2.6, 0.2, 0.8], E(0, -a + PI / 2, 0), wood, "wood", 0.06)
		B.obox([bx, 0.2, bz], [2.2, 0.4, 0.5], E(0, -a + PI / 2, 0), pole, "")
	for p in [[-6.3, -2.8], [6.3, -2.8], [-2.8, 6.4], [2.8, -6.4]]:
		_tree(B, [p[0], 0, p[1]], 0.8, leaf2)
	for p in [[-5.2, -9], [5.2, -9], [-9, 5.2], [9, -5.2], [-5.2, 9], [9, 5.2]]:
		_lamp_post(B, [p[0], 0, p[1]], pole, lamp_glow)

	# ---------------------------------------------------------------- PARK (NE)
	for p in [[14, -23], [23.5, -14], [16.5, -14.5], [23.5, -24]]:
		_tree(B, [p[0], 0, p[1]], 1.15, leaf)
	B.cyl([21, 0, -21.5], 2.1, 0.35, stone, "plastic", 24)
	root.add_child(Geo.circle(1.9, 24).mesh_instance(water, Vector3(21, 0.37, -21.5), Basis(Vector3.RIGHT, -PI / 2), false))
	B.breakable_box([15, 0, -20], [17.6, 0.9, -19.2], wood, "soft", "park", "wood", {"round": 0.06})
	# bus shelter by the ring road (cover)
	B.box([12.5, 0, -11.6], [17.5, 0.15, -10.4], stone, "")
	for gx in [[12.6, 15.0], [15.0, 17.4]]:
		B.breakable_box([gx[0], 0.15, -11.55], [gx[1], 2.6, -11.35], Mats.translucent("#cde7f0", 0.45), "glass", "shelter", "glass")
	B.box([12.4, 2.6, -11.8], [17.6, 2.85, -10.2], blue, "plastic")
	for x in [12.6, 17.4]:
		B.box([x - 0.08, 0.15, -11.55], [x + 0.08, 2.6, -10.4], pole, "")
	# hedges along the park edge (low cover)
	var hedge := Mats.plastic("#2f7d32", {"rough": 0.8, "clearcoat": 0.0})
	for hz in [[-12.6, -9.8], [-9.8, -7.0]]:
		B.breakable_box([11.6, 0, hz[0]], [12.4, 1.1, hz[1]], hedge, "soft", "hedges", "plastic", {"round": 0.3})
	for hx in [[19.0, 22.0], [22.0, 25.0]]:
		B.breakable_box([hx[0], 0, -12.6], [hx[1], 1.1, -11.8], hedge, "soft", "hedges", "plastic", {"round": 0.3})

	# ---------------------------------------------------------------- PARKING LOT (NW)
	ArenaBedroom._add_car(B, [-21.8, 0, -22.4], 0, "#e63946")
	ArenaBedroom._add_car(B, [-15.2, 0, -22.4], 0.05, "#3a86ff")
	ArenaBedroom._add_car(B, [-19.6, 0, -15.0], PI, "#06d6a0")
	ArenaBedroom._add_car(B, [-13.0, 0, -15.0], PI + 0.08, "#ffbe0b")
	B.box([-24.8, 0, -19.2], [-12, 0.25, -18.4], stone, "plastic")
	for p in [[-11.8, -13], [-11.8, -24.5]]:
		_cone(B, [p[0], 0, p[1]], orange, white)

	# ---------------------------------------------------------------- MARKET SQUARE (S)
	var stall := func(cx: float, cz: float, col: String) -> void:
		var cm := Mats.plastic(col, {"rough": 0.5})
		B.breakable_box([cx - 2.2, 0, cz - 0.9], [cx + 2.2, 1.1, cz + 0.9], wood, "soft", "market", "wood", {"round": 0.06})
		for sx in [-2.0, 2.0]:
			B.box([cx + sx - 0.08, 1.1, cz + 0.65], [cx + sx + 0.08, 3.0, cz + 0.81], pole, "")
		B.obox([cx, 3.1, cz + 0.2], [4.8, 0.1, 2.4], E(0.2, 0, 0), cm, "")
		for i in 5:
			B.geo(Geo.sphere(0.28, 10, 8), Mats.plastic(["#e63946", "#ff7b00", "#ffd23f", "#2dc653", "#7b2cbf"][i], {"rough": 0.5}), [cx - 1.6 + i * 0.8, 1.38, cz])
	stall.call(-6.0, 17.0, "#e63946")
	stall.call(6.0, 17.0, "#2dc653")
	stall.call(-6.0, 22.5, "#3a86ff")
	# the bus parked on the market street (big cover)
	var bus := Mats.plastic("#ffbe0b", {"rough": 0.3})
	B.box([2.6, 0.6, 18.6], [9.2, 3.4, 21.0], bus, "plastic", {"round": 0.35})
	var bus_glass := Mats.translucent("#9fd8ff", 0.5)
	for bz in [[18.5, 18.56], [21.04, 21.1]]:
		for bx in [[2.9, 4.9], [5.0, 7.0], [7.1, 9.0]]:
			B.breakable_box([bx[0], 2.0, bz[0]], [bx[1], 2.9, bz[1]], bus_glass, "glass", "bus-glass", "glass")
	for w in [[3.8, 18.5], [3.8, 21.1], [8.0, 18.5], [8.0, 21.1]]:
		B.geo(Geo.cylinder(0.6, 0.6, 0.35, 16), Mats.rubber("#1d1d1d"), [w[0], 0.6, w[1]], E(PI / 2, 0, 0))
	_cone(B, [10.5, 0, 18.4], orange, white)
	_cone(B, [-10.2, 0, 13.6], orange, white)

	# ---------------------------------------------------------------- STREET PROPS
	for p in [[-12, -9], [12, 9.5], [-12, 9.5], [10, -9], [-27.3, -10], [27.3, 10], [-10, 27.3], [10, -27.3], [27.3, -20], [-27.3, 20]]:
		_lamp_post(B, [p[0], 0, p[1]], pole, lamp_glow)
	ArenaBedroom._add_car(B, [-27.4, 0, 4], 0, "#7b2cbf")
	ArenaBedroom._add_car(B, [27.4, 0, -14], PI, "#06d6a0")
	ArenaBedroom._add_car(B, [-6, 0, 27.4], PI / 2, "#e63946")
	ArenaBedroom._add_car(B, [10, 0, 1.8], -PI / 2, "#3a86ff")
	ArenaBedroom._add_car(B, [-11, 0, -2], PI / 2, "#ff7b00")
	for p in [[-10.8, 2.6], [10.8, -2.6], [-2.6, -12.2], [2.6, 12.2], [26.5, 26.5], [-26.5, -26.5], [26.5, -26.5]]:
		_cone(B, [p[0], 0, p[1]], orange, white)
	# hydrant + mailbox + phone box
	B.cyl([-10.4, 0, -11.2], 0.32, 1.0, red, "plastic", 12)
	B.geo(Geo.sphere(0.34, 10, 8), red, [-10.4, 1.0, -11.2])
	B.breakable_box([10.2, 0, 11.6], [10.9, 1.4, 12.3], blue, "soft", "props", "plastic", {"round": 0.15})
	B.box([-12.6, 0, 11.2], [-11.2, 3.2, 12.6], red, "plastic", {"round": 0.1})
	B.breakable_box([-12.5, 1.0, 11.12], [-11.3, 2.8, 11.19], Mats.translucent("#9fd8ff", 0.5), "glass", "phone-glass", "glass")
	# crates on the ring road corners (cover)
	for p in [[-27.5, -27.5], [27.5, 27.5], [-27.5, 27.5]]:
		B.breakable_box([p[0] - 0.9, 0, p[1] - 0.9], [p[0] + 0.9, 1.8, p[1] + 0.9], M.cardboard, "soft", "crates", "cardboard")

	# ---------------------------------------------------------------- finish
	var block_spots := []
	var r := U.seeded(17)
	for i in 10:
		block_spots.append(Vector3(-23 + r.next() * 8, 1 + (i % 3) * 0.7, -20 + r.next() * 4))
	B.build_studs(root)
	batch.build(root)
	var loose := LooseBricks.new(phys, block_spots, root, Vector3(-22, 3, 2))
	animated.append(loose.update)

	# ---------------------------------------------------------------- LIGHTING (the desk lamp over the table)
	var sun_dir := Vector3(-0.32, -0.85, 0.42).normalized()
	var sun := Lighting.sun(root, "#fff1d6", 4.6, sun_dir, 58)
	var lamp := ArenaBedroom.omni(root, "#ffe2b8", 34, 90, 1.4, Vector3(10, 50, -10))
	var fill := ArenaBedroom.omni(root, "#cfe0ff", 10, 70, 1.2, Vector3(-20, 30, 24))

	# ---------------------------------------------------------------- GAMEPLAY DATA
	var zones := [
		{"name": "Town Hall", "min": [-11, -27], "max": [11, -11], "ambience": "brick"},
		{"name": "Department Store", "min": [11.5, -9], "max": [27, 9], "ambience": "closet"},
		{"name": "Apartments", "min": [-27, 11], "max": [-13, 26], "ambience": "bed"},
		{"name": "Fire Station", "min": [-27, -11], "max": [-12, 4], "ambience": "garage"},
		{"name": "Hotel", "min": [11, 12], "max": [27, 27], "ambience": "desk"},
		{"name": "City Park", "min": [11, -27], "max": [27, -11], "ambience": "dino"},
		{"name": "Parking Lot", "min": [-27, -27], "max": [-11, -11], "ambience": "garage"},
		{"name": "Market Square", "min": [-11, 11], "max": [11, 27], "ambience": "brick"},
		{"name": "Fountain Plaza", "min": [-34, -34], "max": [34, 34], "ambience": "rug"},
	]
	var pickup_probes := [
		["health", 0, -10.5, 3], ["health", -10, 8, 3], ["health", 10, -10, 3], ["health", -20, -19, 3],
		["health", 20, -17, 3], ["health", 0, 15.5, 3], ["health", -4, -17.5, 12], ["health", 21, -4.5, 15],
		["shield", -19, 17.5, 19], ["shield", 19.5, 18, 13], ["turbo", -28, 0, 3], ["infinite", -17.5, -2.5, 10], ["health", 4, -20, 2.5], ["health", 21, -3, 2.5], ["shield", -18.5, 20, 2.5],
		["power", 5.2, -5.2, 3],
	]
	return {
		"root": root, "zones": zones, "pickup_probes": pickup_probes, "animated": animated, "sun": sun, "sun_dir": sun_dir,
		"point_lights": [lamp, fill] + lights, "loose_bricks": loose,
		"bounds": AABB(Vector3(C.x0, 0, C.z0), Vector3(C.x1 - C.x0, 28, C.z1 - C.z0)),
		"window": {"x0": -55.0, "x1": 15.0, "y0": 10.0, "y1": 50.0, "z": -120.0},
	}

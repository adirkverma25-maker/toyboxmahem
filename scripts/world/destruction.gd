class_name Destruction
extends Node3D
## Breakable walls, cover and glass. Every piece is a box with its own collider (on Phys.WORLD, so movement,
## bullets and sight lines treat it as solid) and HP. Pieces are drawn merged per group (one wall run, one
## prop), so a break only rebuilds that group's mesh. Ids follow build order, so host and guests agree.

const CLASSES := {
	"glass": {"hp": 20.0, "bullet": 1.0, "blast": 1.0},
	"soft": {"hp": 220.0, "bullet": 1.0, "blast": 3.0},
	"hard": {"hp": 700.0, "bullet": 0.0, "blast": 1.0},
}
## at or below this share of max HP a piece shows cracks
const CRACKED := 0.6

var phys: Phys
## [{id, mn, mx, mat, cls, group, surf, hp, max_hp, broken, body}]
var pieces: Array = []
## (id: int) after a piece breaks
var on_break := Callable()
## (id: int) when a piece first shows cracks (the host tells guests)
var on_crack := Callable()
## how many group meshes have been rebuilt (dev tests)
var rebuilds := 0
## (id: int, impulse_dir: Vector3) break effects (debris, dust, sound)
var on_break_fx := Callable()
## (id: int, point: Vector3, normal: Vector3, cracked_now: bool) hit effects
var on_hit_fx := Callable()

var _groups := {}  # group -> {node: Node3D, ids: Array}
var _dirty := {}  # groups to redraw at the end of this frame (many pieces can go in one blast)
var _dark := {}  # Material -> darker twin for cracked pieces


func _init(p: Phys) -> void:
	phys = p
	name = "Destruction"


## opts: round (rounded edges, untextured), tile (texture repeats per metre, default 1/3),
## uv_origin (Vector3 where the texture starts, so neighbouring panels of one wall line up; default mn),
## rests (it sits on the pieces right below it and breaks when any of them does: caps, stacked boxes),
## studs (pitch: toy-brick studs on top, drawn with the piece)
func add_piece(mn: Vector3, mx: Vector3, mat: Material, cls: String, group: String, surf: String, opts := {}) -> int:
	var id := pieces.size()
	var hp: float = CLASSES[cls].hp
	var body := StaticBody3D.new()
	body.name = "piece_%d" % id
	body.collision_layer = Phys.WORLD | Phys.PIECE
	body.collision_mask = 0
	body.set_meta("mat", surf if surf != "" else "plastic")
	body.set_meta("piece", id)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = (mx - mn).abs()
	cs.shape = sh
	body.add_child(cs)
	body.position = (mn + mx) / 2
	phys.add_child(body)
	pieces.append({"id": id, "mn": mn, "mx": mx, "mat": mat, "cls": cls, "group": group, "surf": surf,
		"hp": hp, "max_hp": hp, "broken": false, "body": body,
		"round": float(opts.get("round", 0.0)), "tile": float(opts.get("tile", 1.0 / 3)), "uv_origin": opts.get("uv_origin", mn),
		"rests": bool(opts.get("rests", false)), "studs": float(opts.get("studs", 0.0)), "supports": PackedInt32Array()})
	if not _groups.has(group):
		_groups[group] = {"node": null, "ids": []}
	_groups[group].ids.append(id)
	return id


## Draw every group (call once after the arena is built).
func build() -> void:
	_find_supports()
	for g in _groups:
		_rebuild(g)
	_dirty.clear()


## For every "rests" piece: the pieces whose tops it sits on.
func _find_supports() -> void:
	for p in pieces:
		if not p.rests:
			continue
		var sup := PackedInt32Array()
		for q in pieces:
			if q.id == p.id or absf(q.mx.y - p.mn.y) > 0.06:
				continue
			if q.mx.x > p.mn.x + 0.01 and q.mn.x < p.mx.x - 0.01 and q.mx.z > p.mn.z + 0.01 and q.mn.z < p.mx.z - 0.01:
				sup.append(q.id)
		if sup.is_empty():
			# nothing underneath (a lintel over a doorway): it hangs on the pieces either side of it
			for q in pieces:
				if q.id == p.id or q.mx.y < p.mn.y + 0.05 or q.mn.y > p.mx.y - 0.05:
					continue
				var touch_x: bool = (absf(q.mx.x - p.mn.x) < 0.06 or absf(q.mn.x - p.mx.x) < 0.06) and q.mx.z > p.mn.z + 0.01 and q.mn.z < p.mx.z - 0.01
				var touch_z: bool = (absf(q.mx.z - p.mn.z) < 0.06 or absf(q.mn.z - p.mx.z) < 0.06) and q.mx.x > p.mn.x + 0.01 and q.mn.x < p.mx.x - 0.01
				if touch_x or touch_z:
					sup.append(q.id)
		p.supports = sup


func is_broken(id: int) -> bool:
	return id >= 0 and id < pieces.size() and pieces[id].broken


func is_cracked(id: int) -> bool:
	var p: Dictionary = pieces[id]
	return not p.broken and p.hp <= p.max_hp * CRACKED


## Damage a piece. kind: "bullet" or "blast". Returns true if this broke it.
func damage(id: int, amount: float, kind: String, point: Vector3, normal: Vector3) -> bool:
	if id < 0 or id >= pieces.size() or amount <= 0:
		return false
	var p: Dictionary = pieces[id]
	if p.broken:
		return false
	var dmg: float = amount * float(CLASSES[p.cls][kind])
	if dmg <= 0:
		if on_hit_fx.is_valid():
			on_hit_fx.call(id, point, normal, false)
		return false
	var was_cracked := is_cracked(id)
	p.hp = maxf(0.0, p.hp - dmg)
	if p.hp <= 0:
		break_piece(id, -normal)
		return true
	var cracked_now := is_cracked(id) and not was_cracked
	if cracked_now:
		_dirty[p.group] = true
		if on_crack.is_valid():
			on_crack.call(id)
	if on_hit_fx.is_valid():
		on_hit_fx.call(id, point, normal, cracked_now)
	return false


func break_piece(id: int, impulse_dir: Vector3) -> void:
	if id < 0 or id >= pieces.size() or pieces[id].broken:
		return
	var p: Dictionary = pieces[id]
	p.broken = true
	p.hp = 0.0
	var body: StaticBody3D = p.body
	body.collision_layer = 0
	body.process_mode = Node.PROCESS_MODE_DISABLED
	_dirty[p.group] = true
	if on_break_fx.is_valid():
		on_break_fx.call(id, impulse_dir)
	if on_break.is_valid():
		on_break.call(id)
	# whatever was resting on it comes down too
	for q in pieces:
		if q.rests and not q.broken and q.supports.has(id):
			break_piece(q.id, Vector3.DOWN)


## Hook up break/hit effects: debris chunks, dust, chips, crack marks and sounds (fx / audio may be null).
func fx_hooks(debris: Debris, fx: Effects, audio: AudioEngine) -> void:
	on_break_fx = func(id: int, dir: Vector3) -> void:
		var p: Dictionary = pieces[id]
		var c := _color_of(p.mat)
		var center: Vector3 = (p.mn + p.mx) / 2
		if debris:
			debris.burst(p.mn, p.mx, c, p.cls, dir)
		if fx:
			# bullet holes, paint and crack marks are flat quads on the surface: they go with it
			var box := AABB(p.mn, p.mx - p.mn).grow(0.12)
			fx.impacts.clear_in(box)
			fx.splats.clear_in(box)
		if fx:
			var ext: Vector3 = p.mx - p.mn
			for i in (4 if p.cls == "glass" else 9):
				var at := Vector3(U.rand(p.mn.x, p.mx.x), U.rand(p.mn.y, p.mx.y), U.rand(p.mn.z, p.mx.z))
				fx.soft.emit(at, Vector3(U.rand(-1, 1), U.rand(0.2, 1.4), U.rand(-1, 1)), c.lerp(Color("#d8cfc2"), 0.6),
					U.rand(0.6, 1.2) * clampf(ext.length() / 2.5, 0.6, 1.6), U.rand(0.6, 1.2), {"grow": 2.2, "drag": 2.5, "alpha": 0.6})
		if audio:
			audio.break_piece(p.cls, center)
	on_hit_fx = func(id: int, point: Vector3, normal: Vector3, cracked_now: bool) -> void:
		if fx == null:
			return
		var p: Dictionary = pieces[id]
		fx.impact(point, normal, p.surf if p.surf != "" else "plastic", {"decal": p.cls != "glass"})
		if cracked_now:
			for i in 3:
				var off := Vector3(U.rand(-0.5, 0.5), U.rand(-0.6, 0.6), U.rand(-0.5, 0.5))
				fx.impacts.add((point + off).clamp(p.mn, p.mx), normal, U.rand(0.35, 0.6), "#1d1a17", 30, 0.7)


static func _color_of(mat: Material) -> Color:
	if mat is BaseMaterial3D:
		return (mat as BaseMaterial3D).albedo_color
	return Color(0.8, 0.8, 0.8)


func cracked_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in pieces:
		if is_cracked(p.id):
			out.append(p.id)
	return out


## Show cracks on these pieces (host -> guest; guests never learn exact HP).
func apply_cracked(ids: Array) -> void:
	for i in ids:
		var id := int(i)
		if id >= 0 and id < pieces.size() and not pieces[id].broken and not is_cracked(id):
			pieces[id].hp = minf(pieces[id].hp, pieces[id].max_hp * CRACKED)
			_dirty[pieces[id].group] = true


func _process(_dt: float) -> void:
	if _dirty.is_empty():
		return
	for g in _dirty:
		_rebuild(g)
	_dirty.clear()


func broken_ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in pieces:
		if p.broken:
			out.append(p.id)
	return out


## Break every listed piece that is still standing (host -> guest sync; unknown ids are ignored).
func apply_broken(ids: Array) -> void:
	for i in ids:
		var id := int(i)
		if id >= 0 and id < pieces.size() and not pieces[id].broken:
			break_piece(id, Vector3.ZERO)


## Every piece back to full HP with its collider, for a new match.
func reset() -> void:
	var dirty := {}
	for p in pieces:
		if p.broken or p.hp < p.max_hp:
			dirty[p.group] = true
		p.broken = false
		p.hp = p.max_hp
		var body: StaticBody3D = p.body
		body.collision_layer = Phys.WORLD | Phys.PIECE
		body.process_mode = Node.PROCESS_MODE_INHERIT
	for g in dirty:
		_dirty[g] = true


## Chips and dust where a hit landed, without any damage (shots replayed for the looks, guests' own hits).
func hit_fx(id: int, point: Vector3, normal: Vector3) -> void:
	if id >= 0 and id < pieces.size() and not pieces[id].broken and on_hit_fx.is_valid():
		on_hit_fx.call(id, point, normal, false)


## An explosion: every standing piece in range takes max_damage with the same falloff as toys get, unless
## something solid (another piece, a static wall) is between the blast and its nearest point.
## Returns the ids that were hit.
func blast(center: Vector3, radius: float, max_damage: float) -> Array[int]:
	var hit: Array[int] = []
	# apply after all the sight checks so pieces broken by this blast still shield the ones behind them
	for e in blast_hits(center, radius, max_damage):
		damage(e.id, e.dmg, "blast", e.point, e.normal)
		hit.append(e.id)
	return hit


## What a blast would do, without doing it: [{id, dmg, point, normal}].
func blast_hits(center: Vector3, radius: float, max_damage: float) -> Array:
	var hits := []
	for id in pieces_in_sphere(center, radius):
		var cp := closest_point(id, center)
		var dist := cp.distance_to(center)
		if dist > 0.05:
			var dir := (cp - center) / dist
			var h := phys.raycast(center, dir, dist + 0.05)
			if not h.is_empty() and piece_of(h.collider) != id and h.dist < dist - 0.05:
				continue
		var f := maxf(0.0, 1.0 - maxf(0.0, dist - 0.4) / radius)
		if f <= 0:
			continue
		var out := (cp - center).normalized() if dist > 0.05 else Vector3.UP
		hits.append({"id": id, "dmg": max_damage * f, "point": cp, "normal": -out})
	return hits


## While the nav graph is built, standing pieces leave the WORLD layer so walk tests ignore them.
func set_nav_mode(on: bool) -> void:
	for p in pieces:
		if not p.broken:
			(p.body as StaticBody3D).collision_layer = Phys.PIECE if on else Phys.WORLD | Phys.PIECE


## Standing pieces whose box comes within r of center.
func pieces_in_sphere(center: Vector3, r: float) -> Array[int]:
	var out: Array[int] = []
	for p in pieces:
		if p.broken:
			continue
		if closest_point(p.id, center).distance_to(center) <= r:
			out.append(p.id)
	return out


func closest_point(id: int, to: Vector3) -> Vector3:
	var p: Dictionary = pieces[id]
	return to.clamp(p.mn, p.mx)


func piece_of(collider: Object) -> int:
	if collider and collider.has_meta("piece"):
		return int(collider.get_meta("piece"))
	return -1


## Changes whenever the set of breakable pieces changes (part of the nav cache key).
func fingerprint() -> int:
	var parts := PackedStringArray()
	for p in pieces:
		parts.append("%s%s%s" % [(p.mn as Vector3).snapped(Vector3.ONE * 0.01), (p.mx as Vector3).snapped(Vector3.ONE * 0.01), p.cls])
	return hash("|".join(parts))


func _darker(mat: Material) -> Material:
	if not _dark.has(mat):
		var m := mat
		if mat is StandardMaterial3D:
			var s := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			s.albedo_color = s.albedo_color.darkened(0.25)
			m = s
		_dark[mat] = m
	return _dark[mat]


## A box whose texture is laid out from `origin` in world space, so a wall cut into panels looks like one wall.
static func _world_uv_box(size: Vector3, center: Vector3, origin: Vector3, tile: float) -> Geo:
	var g := Geo.box(size.x, size.y, size.z)
	for k in g.v.size():
		var w: Vector3 = g.v[k] + center - origin
		var nr: Vector3 = g.n[k]
		if absf(nr.x) > 0.5:
			g.uv[k] = Vector2(-w.z * signf(nr.x), w.y) * tile
		elif absf(nr.z) > 0.5:
			g.uv[k] = Vector2(w.x * signf(nr.z), w.y) * tile
		else:
			g.uv[k] = Vector2(w.x, w.z) * tile
	return g


func _rebuild(group: String) -> void:
	rebuilds += 1
	var g: Dictionary = _groups[group]
	if g.node:
		(g.node as Node).queue_free()
	var n := Node3D.new()
	n.name = "group_" + group.validate_node_name()
	add_child(n)
	g.node = n
	var b := Batcher.new()
	for id in g.ids:
		var p: Dictionary = pieces[id]
		if p.broken:
			continue
		var size: Vector3 = p.mx - p.mn
		var mat: Material = p.mat
		if is_cracked(id):
			mat = _darker(mat)
		var geo: Geo
		var center: Vector3 = (p.mn + p.mx) / 2
		if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			geo = _world_uv_box(size, center, p.uv_origin, p.tile)
		elif p.round > 0:
			geo = Geo.rounded_box(size.x, size.y, size.z, 2, p.round)
		else:
			geo = Geo.box(size.x, size.y, size.z)
		b.add_at(geo, mat, center)
		if p.studs > 0:
			var pitch: float = p.studs
			var stud := Geo.cylinder(pitch * 0.3, pitch * 0.3, pitch * 0.22, 14)
			var nx := maxi(1, int(floor(size.x / pitch + 0.001)))
			var nz := maxi(1, int(floor(size.z / pitch + 0.001)))
			var ox: float = p.mn.x + (size.x - nx * pitch) / 2.0 + pitch / 2.0
			var oz: float = p.mn.z + (size.z - nz * pitch) / 2.0 + pitch / 2.0
			for i in nx:
				for j in nz:
					b.add_at(stud, mat, Vector3(ox + i * pitch, p.mx.y + pitch * 0.11, oz + j * pitch))
	b.build(n)

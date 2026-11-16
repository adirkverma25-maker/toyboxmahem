class_name Builder
extends RefCounted
## Map building helpers (port of src/world/Builder.ts). Points are [x, y, z] arrays like the original code.

var batch: Batcher
var phys: Phys
var studs: Array = []
## breakable pieces go here (null: they are built as ordinary static boxes)
var destruction: Destruction


func _init(b: Batcher, p: Phys) -> void:
	batch = b
	phys = p
	if p and p.has_meta("destruction"):
		destruction = p.get_meta("destruction")


## A box that can be shot or blown apart. cls: glass | soft | hard; pieces in one group share a mesh.
## Returns the piece id, or -1 when this map isn't destructible (then it's a normal static box).
## opts: round, tile, uv_origin ([x, y, z]) - see Destruction.add_piece.
func breakable_box(mn: Array, mx: Array, mat: Material, cls: String, group: String, surf := "wood", opts := {}) -> int:
	if destruction == null:
		var o := {}
		if opts.has("round"):
			o.round = opts.round
		elif mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
			o.tile = opts.get("tile", 1.0 / 3)
		box(mn, mx, mat, surf, o)
		return -1
	var po := opts.duplicate()
	if po.has("uv_origin"):
		po.uv_origin = v(po.uv_origin)
	return destruction.add_piece(v(mn), v(mx), mat, cls, group, surf, po)


static func v(a) -> Vector3:
	if a is Vector3:
		return a
	return Vector3(a[0], a[1], a[2])


## Axis-aligned box from min to max corners. opts: round, tile, visual (true), cast (true)
func box(mn: Array, mx: Array, mat: Material, surf: String, opts := {}) -> Vector3:
	var w: float = mx[0] - mn[0]
	var h: float = mx[1] - mn[1]
	var d: float = mx[2] - mn[2]
	var c := Vector3((mn[0] + mx[0]) / 2.0, (mn[1] + mx[1]) / 2.0, (mn[2] + mx[2]) / 2.0)
	if opts.get("visual", true):
		var g: Geo
		if opts.get("round", 0.0) > 0.0:
			g = Geo.rounded_box(w, h, d, 2, opts.round)
		elif opts.get("tile", 0.0) > 0.0:
			g = Geo.tiled_box(w, h, d, opts.tile)
		else:
			g = Geo.box(w, h, d)
		batch.add_at(g, mat, c, Basis(), Vector3.ONE, opts.get("cast", true))
	if surf != "":
		phys.box(c, Vector3(w / 2, h / 2, d / 2), surf)
	return c


## Rotated box by center/size/rotation.
func obox(center: Array, size: Array, rot: Basis, mat: Material, surf: String, round := 0.0) -> void:
	var g := Geo.rounded_box(size[0], size[1], size[2], 2, round) if round > 0 else Geo.box(size[0], size[1], size[2])
	batch.add_at(g, mat, v(center), rot)
	if surf != "":
		phys.box(v(center), Vector3(size[0] / 2.0, size[1] / 2.0, size[2] / 2.0), surf, rot)


## Vertical cylinder standing on a base point.
func cyl(base: Array, r: float, h: float, mat: Material, surf: String, seg := 24, r_top := -1.0) -> void:
	var rt := r if r_top < 0 else r_top
	var g := Geo.cylinder(rt, r, h, seg)
	var c := Vector3(base[0], base[1] + h / 2.0, base[2])
	batch.add_at(g, mat, c)
	if surf != "":
		phys.cylinder(c, h / 2.0, maxf(r, rt), surf)


## Any geometry, visual only.
func geo(g: Geo, mat: Material, pos: Array, rot := Basis(), scale = null, cast := true) -> void:
	var s := Vector3.ONE if scale == null else v(scale)
	batch.add_at(g, mat, v(pos), rot, s, cast)


## Solid wedge ramp. `low` is the floor point at the middle of the low edge; yaw rotates the ramp (0 = +z).
func wedge(low: Array, yaw: float, length: float, height: float, width: float, mat: Material, surf: String) -> void:
	var g := Geo.wedge(length, height, width)
	var xf := Transform3D(Basis(Vector3.UP, yaw), v(low))
	batch.add(g, mat, xf)
	var w := width / 2.0
	var pts := []
	for p in [[-w, 0, 0], [w, 0, 0], [-w, 0, length], [w, 0, length], [-w, height, length], [w, height, length]]:
		pts.append(xf * Vector3(p[0], p[1], p[2]))
	phys.convex(pts, surf)


## Thin slab ramp between two surface points (open underneath).
func slab(from: Array, to: Array, width: float, thickness: float, mat: Material, surf: String, round := 0.0) -> Dictionary:
	var r := phys.ramp(v(from), v(to), width, surf, thickness)
	var g := Geo.rounded_box(width, thickness, r.length, 2, round) if round > 0 else Geo.tiled_box(width, thickness, r.length, 0.2)
	batch.add(g, mat, Transform3D(r.basis, r.center))
	return r


## A toy construction brick: box + studs on top.
func brick(mn: Array, mx: Array, color, surf := "plastic", with_studs := true, pitch := 0.8) -> void:
	box(mn, mx, Mats.plastic(color, {"rough": 0.3}), surf, {"round": 0.06})
	if with_studs:
		add_studs(mn[0], mx[0], mn[2], mx[2], mx[1], color, pitch)


func add_studs(x0: float, x1: float, z0: float, z1: float, y: float, color, pitch := 0.8) -> void:
	var c := U.col(color)
	var nx := maxi(1, int(floor((x1 - x0) / pitch + 0.001)))
	var nz := maxi(1, int(floor((z1 - z0) / pitch + 0.001)))
	var ox := x0 + (x1 - x0 - nx * pitch) / 2.0 + pitch / 2.0
	var oz := z0 + (z1 - z0 - nz * pitch) / 2.0 + pitch / 2.0
	for i in nx:
		for j in nz:
			studs.append([Vector3(ox + i * pitch, y, oz + j * pitch), c])


func build_studs(parent: Node3D, pitch := 0.8) -> void:
	if studs.is_empty():
		return
	var g := Geo.cylinder(pitch * 0.3, pitch * 0.3, pitch * 0.22, 14).translate(0, pitch * 0.11, 0)
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.3
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.6
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = g.to_mesh(mat)
	mm.instance_count = studs.size()
	for i in studs.size():
		mm.set_instance_transform(i, Transform3D(Basis(), studs[i][0]))
		mm.set_instance_color(i, studs[i][1])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	parent.add_child(mmi)
	studs = []

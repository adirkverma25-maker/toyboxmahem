class_name Batcher
extends RefCounted
## Collects static geometry and merges it per material into a handful of meshes (port of StaticBatcher).

var _groups := {}  # Material -> Geo
var _cast := {}  # Material -> bool
var _cols := {}  # Material -> PackedColorArray (vertex colours, for plastic twins)


func add(g: Geo, mat: Material, xf: Transform3D, cast := true) -> void:
	var t := g.transformed(xf)
	if mat.has_meta("flat"):
		t.flat_normals()
	# every colour of the same plastic shares one material: the colour goes into the vertices
	var col := Color.WHITE
	var key := mat
	if mat.has_meta("vc_key"):
		col = (mat as StandardMaterial3D).albedo_color
		key = Mats.vc_twin(mat)
	if not _groups.has(key):
		_groups[key] = Geo.new()
		_cast[key] = cast
		_cols[key] = PackedColorArray()
	(_groups[key] as Geo).merge(t)
	_cast[key] = _cast[key] or cast
	var ca: PackedColorArray = _cols[key]
	var start := ca.size()
	ca.resize(start + t.v.size())
	for i in t.v.size():
		ca[start + i] = col
	_cols[key] = ca


func add_at(g: Geo, mat: Material, pos: Vector3, rot := Basis(), scale := Vector3.ONE, cast := true) -> void:
	add(g, mat, Transform3D(rot * Basis.from_scale(scale), pos), cast)


func build(parent: Node3D) -> Array:
	var out := []
	for mat in _groups:
		var g: Geo = _groups[mat]
		if g.v.size() == 0:
			continue
		var mi := MeshInstance3D.new()
		if (mat as Material).has_meta("vc_key") or (mat is BaseMaterial3D and (mat as BaseMaterial3D).vertex_color_use_as_albedo):
			var a := g.arrays()
			var ca: PackedColorArray = _cols[mat]
			# arrays() flips each triangle's last two vertices; colours follow
			var i := 0
			while i + 2 < ca.size():
				var c1 := ca[i + 1]
				ca[i + 1] = ca[i + 2]
				ca[i + 2] = c1
				i += 3
			a[Mesh.ARRAY_COLOR] = ca
			var am := ArrayMesh.new()
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			am.surface_set_material(0, mat)
			mi.mesh = am
		else:
			mi.mesh = g.to_mesh(mat)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if _cast[mat] else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)
		out.append(mi)
	_groups.clear()
	_cast.clear()
	_cols.clear()
	return out

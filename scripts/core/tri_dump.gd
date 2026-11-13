class_name TriDump
## Dev: list the heaviest meshes in a scene (triangles x instances, shadow casting).


static func _tris(m: Mesh) -> int:
	if m == null:
		return 0
	var n := 0
	for s in m.get_surface_count():
		var a := m.surface_get_arrays(s)
		var idx = a[Mesh.ARRAY_INDEX]
		if idx != null and idx.size() > 0:
			n += idx.size() / 3
		else:
			n += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return n


static func dump(root: Node) -> void:
	var rows := []
	var by_owner := {}
	var cnt_by := {}
	var stack := [root]
	while stack.size():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var t := 0
		var label := ""
		if n is MeshInstance3D and (n as MeshInstance3D).is_visible_in_tree():
			t = _tris((n as MeshInstance3D).mesh)
			label = "mesh"
		elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).is_visible_in_tree() and (n as MultiMeshInstance3D).multimesh:
			var mm := (n as MultiMeshInstance3D).multimesh
			var cnt := mm.visible_instance_count if mm.visible_instance_count >= 0 else mm.instance_count
			t = _tris(mm.mesh) * cnt
			label = "multi x%d" % cnt
		if t == 0:
			continue
		var path := str(root.get_path_to(n))
		var parts := path.split("/")
		var key := "/".join(parts.slice(0, mini(4, parts.size())))
		var nk := "/".join(parts.slice(0, mini(5, parts.size() - 1)))
		by_owner[key] = by_owner.get(key, 0) + t
		cnt_by[nk] = cnt_by.get(nk, 0) + 1
		rows.append([t, "%s %s shadow=%d" % [path.substr(0, 90), label, (n as GeometryInstance3D).cast_shadow]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0
	for r in rows:
		total += r[0]
	print("[tris] total ", total, " in ", rows.size(), " instances")
	for i in mini(40, rows.size()):
		print("[tris] ", rows[i][0], "  ", rows[i][1])
	var groups := []
	for k in by_owner:
		groups.append([by_owner[k], k])
	groups.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(25, groups.size()):
		print("[tris-group] ", groups[i][0], "  ", groups[i][1])
	var cs := []
	for k in cnt_by:
		cs.append([cnt_by[k], k])
	cs.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(25, cs.size()):
		print("[inst] ", cs[i][0], "  ", cs[i][1])

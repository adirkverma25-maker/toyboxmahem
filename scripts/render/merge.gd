class_name Merge
## Fewer draw calls (port of src/render/merge.ts): merge meshes that share a material and move together.


## Merge the direct MeshInstance3D children of every node, per material. Meshes with children of their own,
## and anything `exclude` returns true for, are left alone.
static func merge_direct_children(root: Node, exclude: Callable) -> void:
	for c in root.get_children():
		merge_direct_children(c, exclude)
	var groups := {}
	for c in root.get_children():
		if not (c is MeshInstance3D):
			continue
		var m := c as MeshInstance3D
		if m.get_child_count() > 0 or exclude.call(m) or m.mesh == null or not m.visible:
			continue
		var mat = m.material_override
		if mat == null:
			continue
		if not groups.has(mat):
			groups[mat] = []
		groups[mat].append(m)
	for mat in groups:
		var list: Array = groups[mat]
		if list.size() < 2:
			continue
		var st := SurfaceTool.new()
		for m: MeshInstance3D in list:
			st.append_from(m.mesh, 0, m.transform)
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		merged.material_override = mat
		merged.cast_shadow = list[0].cast_shadow
		root.add_child(merged)
		for m: MeshInstance3D in list:
			root.remove_child(m)
			m.queue_free()


## Bake every mesh under `root` into one mesh per material, directly under root (non-mesh nodes stay).
static func flatten_by_material(root: Node3D) -> void:
	var groups := {}
	var stack := [[root, Transform3D()]]
	var victims := []
	while stack.size():
		var e: Array = stack.pop_back()
		var n: Node = e[0]
		var xf: Transform3D = e[1]
		for c in n.get_children():
			if not (c is Node3D):
				continue
			var cx: Transform3D = xf * (c as Node3D).transform
			if c is MeshInstance3D and (c as MeshInstance3D).mesh and (c as MeshInstance3D).material_override:
				var mat = (c as MeshInstance3D).material_override
				if not groups.has(mat):
					groups[mat] = SurfaceTool.new()
				(groups[mat] as SurfaceTool).append_from((c as MeshInstance3D).mesh, 0, cx)
				victims.append(c)
			stack.append([c, cx])
	for v in victims:
		var keep := false
		for c in v.get_children():
			if not (c is MeshInstance3D):
				keep = true
		if keep:
			(v as MeshInstance3D).mesh = null
		else:
			v.get_parent().remove_child(v)
			v.queue_free()
	for mat in groups:
		var mi := MeshInstance3D.new()
		mi.mesh = (groups[mat] as SurfaceTool).commit()
		mi.material_override = mat
		root.add_child(mi)

class_name Geo
extends RefCounted
## Triangle-list geometry using three.js conventions (counter-clockwise front faces, uv v=1 at the top).
## Every generator copies the matching three.js geometry so ported code keeps the same shapes and UVs.
## to_mesh()/the batcher flip the winding and the v coordinate for Godot.

var v := PackedVector3Array()
var n := PackedVector3Array()
var uv := PackedVector2Array()


func copy() -> Geo:
	var g := Geo.new()
	g.v = v.duplicate()
	g.n = n.duplicate()
	g.uv = uv.duplicate()
	return g


func transformed(xf: Transform3D) -> Geo:
	var g := Geo.new()
	g.v.resize(v.size())
	g.n.resize(n.size())
	g.uv = uv
	var nb := xf.basis.inverse().transposed()
	for i in v.size():
		g.v[i] = xf * v[i]
		g.n[i] = (nb * n[i]).normalized()
	return g


func translate(x: float, y: float, z: float) -> Geo:
	var o := Vector3(x, y, z)
	for i in v.size():
		v[i] += o
	return self


func scale(x: float, y: float, z: float) -> Geo:
	var s := Vector3(x, y, z)
	var inv := Vector3(1.0 / x, 1.0 / y, 1.0 / z)
	for i in v.size():
		v[i] *= s
		n[i] = (n[i] * inv).normalized()
	return self


func rotate_basis(b: Basis) -> Geo:
	for i in v.size():
		v[i] = b * v[i]
		n[i] = b * n[i]
	return self


func merge(o: Geo) -> Geo:
	v.append_array(o.v)
	n.append_array(o.n)
	uv.append_array(o.uv)
	return self


func flat_normals() -> Geo:
	var i := 0
	while i + 2 < v.size():
		var fn := (v[i + 1] - v[i]).cross(v[i + 2] - v[i]).normalized()
		n[i] = fn
		n[i + 1] = fn
		n[i + 2] = fn
		i += 3
	return self


## Smooth normals by averaging face normals of triangles that share a position.
func smooth_normals() -> Geo:
	var acc := {}
	var i := 0
	while i + 2 < v.size():
		var fn := (v[i + 1] - v[i]).cross(v[i + 2] - v[i])
		for k in 3:
			var key := v[i + k].snappedf(0.0001)
			acc[key] = acc.get(key, Vector3.ZERO) + fn
		i += 3
	for j in v.size():
		n[j] = (acc[v[j].snappedf(0.0001)] as Vector3).normalized()
	return self


func arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	var vv := PackedVector3Array()
	var nn := PackedVector3Array()
	var tt := PackedVector2Array()
	vv.resize(v.size())
	nn.resize(v.size())
	tt.resize(v.size())
	var i := 0
	while i + 2 < v.size():
		# flip winding: three.js is CCW-front, Godot is CW-front
		vv[i] = v[i]
		vv[i + 1] = v[i + 2]
		vv[i + 2] = v[i + 1]
		nn[i] = n[i]
		nn[i + 1] = n[i + 2]
		nn[i + 2] = n[i + 1]
		tt[i] = Vector2(uv[i].x, 1.0 - uv[i].y)
		tt[i + 1] = Vector2(uv[i + 2].x, 1.0 - uv[i + 2].y)
		tt[i + 2] = Vector2(uv[i + 1].x, 1.0 - uv[i + 1].y)
		i += 3
	a[Mesh.ARRAY_VERTEX] = vv
	a[Mesh.ARRAY_NORMAL] = nn
	a[Mesh.ARRAY_TEX_UV] = tt
	return a


func to_mesh(mat: Material = null) -> ArrayMesh:
	var m := ArrayMesh.new()
	if v.size() == 0:
		return m
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays())
	if mat:
		m.surface_set_material(0, mat)
	return m


func mesh_instance(mat: Material, pos := Vector3.ZERO, rot := Basis(), shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = to_mesh(mat)
	mi.transform = Transform3D(rot, pos)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


# ------------------------------------------------------------------ helpers
func _tri(p0: Vector3, p1: Vector3, p2: Vector3, n0: Vector3, n1: Vector3, n2: Vector3, t0: Vector2, t1: Vector2, t2: Vector2) -> void:
	v.append(p0)
	v.append(p1)
	v.append(p2)
	n.append(n0)
	n.append(n1)
	n.append(n2)
	uv.append(t0)
	uv.append(t1)
	uv.append(t2)


## Adds indexed triangles (three.js index order) from vertex/normal/uv lists.
func _indexed(pv: Array, pn: Array, pt: Array, idx: Array) -> void:
	var i := 0
	while i + 2 < idx.size():
		var a: int = idx[i]
		var b: int = idx[i + 1]
		var c: int = idx[i + 2]
		_tri(pv[a], pv[b], pv[c], pn[a], pn[b], pn[c], pt[a], pt[b], pt[c])
		i += 3


# ------------------------------------------------------------------ generators (three.js compatible)
static func box(w: float, h: float, d: float, ws := 1, hs := 1, ds := 1) -> Geo:
	var g := Geo.new()
	g._box_plane(2, 1, 0, -1, -1, d, h, w, ds, hs)
	g._box_plane(2, 1, 0, 1, -1, d, h, -w, ds, hs)
	g._box_plane(0, 2, 1, 1, 1, w, d, h, ws, ds)
	g._box_plane(0, 2, 1, 1, -1, w, d, -h, ws, ds)
	g._box_plane(0, 1, 2, 1, -1, w, h, d, ws, hs)
	g._box_plane(0, 1, 2, -1, -1, w, h, -d, ws, hs)
	return g


func _box_plane(u: int, vv: int, w: int, udir: float, vdir: float, width: float, height: float, depth: float, gx: int, gy: int) -> void:
	var seg_w := width / gx
	var seg_h := height / gy
	var pv := []
	var pn := []
	var pt := []
	for iy in gy + 1:
		var y := iy * seg_h - height / 2.0
		for ix in gx + 1:
			var x := ix * seg_w - width / 2.0
			var p := Vector3.ZERO
			p[u] = x * udir
			p[vv] = y * vdir
			p[w] = depth / 2.0
			pv.append(p)
			var nr := Vector3.ZERO
			nr[w] = 1.0 if depth > 0 else -1.0
			pn.append(nr)
			pt.append(Vector2(float(ix) / gx, 1.0 - float(iy) / gy))
	var idx := []
	for iy in gy:
		for ix in gx:
			var a := ix + (gx + 1) * iy
			var b := ix + (gx + 1) * (iy + 1)
			var c := (ix + 1) + (gx + 1) * (iy + 1)
			var dd := (ix + 1) + (gx + 1) * iy
			idx.append_array([a, b, dd, b, c, dd])
	_indexed(pv, pn, pt, idx)


## Box whose UVs tile in world units (density = repeats per unit).
static func tiled_box(w: float, h: float, d: float, density := 0.1) -> Geo:
	var g := box(w, h, d)
	var dims := [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]]
	for f in 6:
		for i in 6:
			var k := f * 6 + i
			g.uv[k] = Vector2(g.uv[k].x * dims[f][0] * density, g.uv[k].y * dims[f][1] * density)
	return g


## Box with rounded edges (same idea as three's RoundedBoxGeometry).
static func rounded_box(w: float, h: float, d: float, segs := 2, radius := 0.1) -> Geo:
	var r := minf(radius, minf(w / 2.01, minf(h / 2.01, d / 2.01)))
	if r <= 0.001:
		return box(w, h, d)
	var half := Vector3(w, h, d) / 2.0
	var inner := half - Vector3(r, r, r)
	var steps := maxi(1, segs)
	# grid positions along an axis: flat middle, `steps` subdivisions in each rounded band
	var cuts := func(hl: float) -> Array:
		var arr := []
		for i in steps + 1:
			arr.append(-hl + r - r * cos((PI / 2.0) * float(i) / steps))
		var mid := []
		for x in arr:
			mid.append(x)
		var top := []
		for i in range(arr.size() - 1, -1, -1):
			top.append(-arr[i])
		if absf(mid[mid.size() - 1] - top[0]) < 1e-5:
			top.remove_at(0)
		mid.append_array(top)
		return mid
	var cx: Array = cuts.call(half.x)
	var cy: Array = cuts.call(half.y)
	var cz: Array = cuts.call(half.z)
	var g := Geo.new()
	# 6 faces: build a grid on each face then push vertices onto the rounded surface
	var faces := [
		[0, 2, 1, Vector3(1, 0, 0), cz, cy, -1.0, 1.0],
		[0, 2, 1, Vector3(-1, 0, 0), cz, cy, 1.0, 1.0],
		[1, 0, 2, Vector3(0, 1, 0), cx, cz, 1.0, 1.0],
		[1, 0, 2, Vector3(0, -1, 0), cx, cz, 1.0, -1.0],
		[2, 0, 1, Vector3(0, 0, 1), cx, cy, 1.0, 1.0],
		[2, 0, 1, Vector3(0, 0, -1), cx, cy, -1.0, 1.0],
	]
	for f in faces:
		var axis: int = f[0]
		var ua: int = f[1]
		var va: int = f[2]
		var nrm: Vector3 = f[3]
		var us: Array = f[4]
		var vs: Array = f[5]
		var usign: float = f[6]
		var vsign: float = f[7]
		var nu := us.size()
		var nv := vs.size()
		var pv := []
		var pn := []
		var pt := []
		for j in nv:
			for i in nu:
				var p := Vector3.ZERO
				p[axis] = half[axis] * nrm[axis]
				p[ua] = us[i] * usign
				p[va] = vs[j] * vsign
				var c := Vector3(clampf(p.x, -inner.x, inner.x), clampf(p.y, -inner.y, inner.y), clampf(p.z, -inner.z, inner.z))
				var dir := p - c
				var nn := dir.normalized() if dir.length() > 1e-6 else nrm
				pv.append(c + nn * r)
				pn.append(nn)
				pt.append(Vector2(float(i) / (nu - 1), float(j) / (nv - 1)))
		var idx := []
		for j in nv - 1:
			for i in nu - 1:
				var a := i + nu * j
				var b := i + 1 + nu * j
				var c2 := i + 1 + nu * (j + 1)
				var dd := i + nu * (j + 1)
				idx.append_array([a, b, c2, a, c2, dd])
		g._indexed(pv, pn, pt, idx)
	# make sure every triangle faces outward
	var i2 := 0
	while i2 + 2 < g.v.size():
		var fn := (g.v[i2 + 1] - g.v[i2]).cross(g.v[i2 + 2] - g.v[i2])
		if fn.dot(g.n[i2] + g.n[i2 + 1] + g.n[i2 + 2]) < 0:
			var tv := g.v[i2 + 1]
			g.v[i2 + 1] = g.v[i2 + 2]
			g.v[i2 + 2] = tv
			var tn := g.n[i2 + 1]
			g.n[i2 + 1] = g.n[i2 + 2]
			g.n[i2 + 2] = tn
			var tt := g.uv[i2 + 1]
			g.uv[i2 + 1] = g.uv[i2 + 2]
			g.uv[i2 + 2] = tt
		i2 += 3
	return g


static func cylinder(r_top: float, r_bot: float, h: float, radial := 32, hseg := 1, open_ended := false, theta_start := 0.0, theta_len := TAU) -> Geo:
	var g := Geo.new()
	var hh := h / 2.0
	var slope := (r_bot - r_top) / h if h != 0 else 0.0
	var pv := []
	var pn := []
	var pt := []
	var grid := []
	var idx := 0
	for y in hseg + 1:
		var row := []
		var vv := float(y) / hseg
		var radius := vv * (r_bot - r_top) + r_top
		for x in radial + 1:
			var uu := float(x) / radial
			var th := uu * theta_len + theta_start
			pv.append(Vector3(radius * sin(th), -vv * h + hh, radius * cos(th)))
			pn.append(Vector3(sin(th), slope, cos(th)).normalized())
			pt.append(Vector2(uu, 1.0 - vv))
			row.append(idx)
			idx += 1
		grid.append(row)
	var ind := []
	for x in radial:
		for y in hseg:
			var a: int = grid[y][x]
			var b: int = grid[y + 1][x]
			var c: int = grid[y + 1][x + 1]
			var d: int = grid[y][x + 1]
			if r_top > 0 or y != 0:
				ind.append_array([a, b, d])
			if r_bot > 0 or y != hseg - 1:
				ind.append_array([b, c, d])
	g._indexed(pv, pn, pt, ind)
	if not open_ended:
		if r_top > 0:
			g._cyl_cap(true, r_top, hh, radial, theta_start, theta_len)
		if r_bot > 0:
			g._cyl_cap(false, r_bot, hh, radial, theta_start, theta_len)
	return g


func _cyl_cap(top: bool, radius: float, hh: float, radial: int, ts: float, tl: float) -> void:
	var sgn := 1.0 if top else -1.0
	var pv := []
	var pn := []
	var pt := []
	for x in radial + 1:
		pv.append(Vector3(0, hh * sgn, 0))
		pn.append(Vector3(0, sgn, 0))
		pt.append(Vector2(0.5, 0.5))
	for x in radial + 1:
		var th := float(x) / radial * tl + ts
		pv.append(Vector3(radius * sin(th), hh * sgn, radius * cos(th)))
		pn.append(Vector3(0, sgn, 0))
		pt.append(Vector2(cos(th) * 0.5 + 0.5, sin(th) * 0.5 * sgn + 0.5))
	var ind := []
	for x in radial:
		var c := x
		var i := radial + 1 + x
		if top:
			ind.append_array([i, i + 1, c])
		else:
			ind.append_array([i + 1, i, c])
	_indexed(pv, pn, pt, ind)


static func cone(r: float, h: float, radial := 32, hseg := 1, open_ended := false, ts := 0.0, tl := TAU) -> Geo:
	return cylinder(0.0, r, h, radial, hseg, open_ended, ts, tl)


static func sphere(r: float, ws := 32, hs := 16, phi_start := 0.0, phi_len := TAU, theta_start := 0.0, theta_len := PI) -> Geo:
	var g := Geo.new()
	ws = maxi(3, ws)
	hs = maxi(2, hs)
	var theta_end := minf(theta_start + theta_len, PI)
	var pv := []
	var pn := []
	var pt := []
	var grid := []
	var idx := 0
	for iy in hs + 1:
		var row := []
		var vv := float(iy) / hs
		var u_off := 0.0
		if iy == 0 and theta_start == 0:
			u_off = 0.5 / ws
		elif iy == hs and theta_end == PI:
			u_off = -0.5 / ws
		for ix in ws + 1:
			var uu := float(ix) / ws
			var p := Vector3(
				-r * cos(phi_start + uu * phi_len) * sin(theta_start + vv * theta_len),
				r * cos(theta_start + vv * theta_len),
				r * sin(phi_start + uu * phi_len) * sin(theta_start + vv * theta_len))
			pv.append(p)
			pn.append(p.normalized() if p.length() > 0 else Vector3.UP)
			pt.append(Vector2(uu + u_off, 1.0 - vv))
			row.append(idx)
			idx += 1
		grid.append(row)
	var ind := []
	for iy in hs:
		for ix in ws:
			var a: int = grid[iy][ix + 1]
			var b: int = grid[iy][ix]
			var c: int = grid[iy + 1][ix]
			var d: int = grid[iy + 1][ix + 1]
			if iy != 0 or theta_start > 0:
				ind.append_array([a, b, d])
			if iy != hs - 1 or theta_end < PI:
				ind.append_array([b, c, d])
	g._indexed(pv, pn, pt, ind)
	return g


static func torus(radius := 1.0, tube := 0.4, radial := 12, tubular := 48, arc := TAU) -> Geo:
	var g := Geo.new()
	var pv := []
	var pn := []
	var pt := []
	for j in radial + 1:
		for i in tubular + 1:
			var u := float(i) / tubular * arc
			var vv := float(j) / radial * TAU
			var p := Vector3((radius + tube * cos(vv)) * cos(u), (radius + tube * cos(vv)) * sin(u), tube * sin(vv))
			var c := Vector3(radius * cos(u), radius * sin(u), 0)
			pv.append(p)
			pn.append((p - c).normalized())
			pt.append(Vector2(float(i) / tubular, float(j) / radial))
	var ind := []
	for j in range(1, radial + 1):
		for i in range(1, tubular + 1):
			var a := (tubular + 1) * j + i - 1
			var b := (tubular + 1) * (j - 1) + i - 1
			var c := (tubular + 1) * (j - 1) + i
			var d := (tubular + 1) * j + i
			ind.append_array([a, b, d, b, c, d])
	g._indexed(pv, pn, pt, ind)
	return g


static func torus_knot(radius := 1.0, tube := 0.4, tubular := 64, radial := 8, p := 2, q := 3) -> Geo:
	var g := Geo.new()
	var pv := []
	var pn := []
	var pt := []
	var knot := func(u: float) -> Vector3:
		var cu := cos(u)
		var su := sin(u)
		var qp := q / float(p) * u
		var cs := cos(qp)
		return Vector3(radius * (2 + cs) * 0.5 * cu, radius * (2 + cs) * su * 0.5, radius * sin(qp) * 0.5)
	for i in tubular + 1:
		var u := float(i) / tubular * p * TAU
		var p1: Vector3 = knot.call(u)
		var p2: Vector3 = knot.call(u + 0.01)
		var T := p2 - p1
		var N := p2 + p1
		var B := T.cross(N).normalized()
		N = B.cross(T).normalized()
		for j in radial + 1:
			var vv := float(j) / radial * TAU
			var cx := -tube * cos(vv)
			var cy := tube * sin(vv)
			var vert := p1 + N * cx + B * cy
			pv.append(vert)
			pn.append((vert - p1).normalized())
			pt.append(Vector2(float(i) / tubular, float(j) / radial))
	var ind := []
	for j in range(1, tubular + 1):
		for i in range(1, radial + 1):
			var a := (radial + 1) * (j - 1) + (i - 1)
			var b := (radial + 1) * j + (i - 1)
			var c := (radial + 1) * j + i
			var d := (radial + 1) * (j - 1) + i
			ind.append_array([a, b, d, b, c, d])
	g._indexed(pv, pn, pt, ind)
	return g


## Lathe around Y (three's LatheGeometry). points are Vector2(radius, y).
static func lathe(points: Array, segments := 12, phi_start := 0.0, phi_len := TAU) -> Geo:
	var g := Geo.new()
	var np := points.size()
	var norms2 := []
	for j in np:
		var a: Vector2 = points[maxi(0, j - 1)]
		var b: Vector2 = points[mini(np - 1, j + 1)]
		var t := b - a
		var nn := Vector2(t.y, -t.x).normalized()
		norms2.append(nn)
	var pv := []
	var pn := []
	var pt := []
	for i in segments + 1:
		var phi := phi_start + float(i) / segments * phi_len
		var s := sin(phi)
		var c := cos(phi)
		for j in np:
			var p: Vector2 = points[j]
			pv.append(Vector3(p.x * s, p.y, p.x * c))
			var n2: Vector2 = norms2[j]
			pn.append(Vector3(n2.x * s, n2.y, n2.x * c).normalized())
			pt.append(Vector2(float(i) / segments, float(j) / (np - 1)))
	var ind := []
	for i in segments:
		for j in np - 1:
			var base := j + i * np
			var a := base
			var b := base + np
			var c := base + np + 1
			var d := base + 1
			ind.append_array([a, b, d, c, d, b])
	g._indexed(pv, pn, pt, ind)
	return g


## three's CapsuleGeometry(radius, length): `length` is the straight middle part.
static func capsule(radius := 1.0, length := 1.0, cap_segs := 4, radial := 8) -> Geo:
	var pts := []
	var steps := cap_segs * 2
	for i in steps + 1:
		var a := -PI / 2.0 + (PI / 2.0) * float(i) / steps
		pts.append(Vector2(radius * cos(a), -length / 2.0 + radius * sin(a)))
	for i in steps + 1:
		var a := (PI / 2.0) * float(i) / steps
		pts.append(Vector2(radius * cos(a), length / 2.0 + radius * sin(a)))
	pts[0] = Vector2(0.0, pts[0].y)
	pts[pts.size() - 1] = Vector2(0.0, pts[pts.size() - 1].y)
	var g := lathe(pts, radial)
	# proper sphere-cap normals
	for i in g.v.size():
		var p := g.v[i]
		var cy := clampf(p.y, -length / 2.0, length / 2.0)
		var d := p - Vector3(0, cy, 0)
		if d.length() > 1e-5:
			g.n[i] = d.normalized()
	return g


static func plane(w: float, h: float, wseg := 1, hseg := 1) -> Geo:
	var g := Geo.new()
	var pv := []
	var pn := []
	var pt := []
	var gx1 := wseg + 1
	for iy in hseg + 1:
		var y := iy * (h / hseg) - h / 2.0
		for ix in wseg + 1:
			var x := ix * (w / wseg) - w / 2.0
			pv.append(Vector3(x, -y, 0))
			pn.append(Vector3(0, 0, 1))
			pt.append(Vector2(float(ix) / wseg, 1.0 - float(iy) / hseg))
	var ind := []
	for iy in hseg:
		for ix in wseg:
			var a := ix + gx1 * iy
			var b := ix + gx1 * (iy + 1)
			var c := ix + 1 + gx1 * (iy + 1)
			var d := ix + 1 + gx1 * iy
			ind.append_array([a, b, d, b, c, d])
	g._indexed(pv, pn, pt, ind)
	return g


static func circle(r: float, segs := 32, ts := 0.0, tl := TAU) -> Geo:
	var g := Geo.new()
	var pv := [Vector3.ZERO]
	var pn := [Vector3(0, 0, 1)]
	var pt := [Vector2(0.5, 0.5)]
	for s in segs + 1:
		var a := ts + float(s) / segs * tl
		var p := Vector3(r * cos(a), r * sin(a), 0)
		pv.append(p)
		pn.append(Vector3(0, 0, 1))
		pt.append(Vector2((p.x / r + 1) / 2.0, (p.y / r + 1) / 2.0))
	var ind := []
	for i in range(1, segs + 1):
		ind.append_array([i, i + 1, 0])
	g._indexed(pv, pn, pt, ind)
	return g


static func ring(inner: float, outer: float, theta_segs := 32, phi_segs := 1, ts := 0.0, tl := TAU) -> Geo:
	var g := Geo.new()
	var pv := []
	var pn := []
	var pt := []
	var radius := inner
	var step := (outer - inner) / phi_segs
	for j in phi_segs + 1:
		for i in theta_segs + 1:
			var seg := ts + float(i) / theta_segs * tl
			var p := Vector3(radius * cos(seg), radius * sin(seg), 0)
			pv.append(p)
			pn.append(Vector3(0, 0, 1))
			pt.append(Vector2((p.x / outer + 1) / 2.0, (p.y / outer + 1) / 2.0))
		radius += step
	var ind := []
	for j in phi_segs:
		var off := j * (theta_segs + 1)
		for i in theta_segs:
			var seg := i + off
			var a := seg
			var b := seg + theta_segs + 1
			var c := seg + theta_segs + 2
			var d := seg + 1
			ind.append_array([a, b, d, b, c, d])
	g._indexed(pv, pn, pt, ind)
	return g


## Polyhedra (tetra/octa/icosa/dodeca) projected onto a sphere, with `detail` subdivisions.
static func polyhedron(verts: Array, faces: Array, radius := 1.0, detail := 0) -> Geo:
	var g := Geo.new()
	var pts := []
	for i in range(0, verts.size(), 3):
		pts.append(Vector3(verts[i], verts[i + 1], verts[i + 2]))
	for f in range(0, faces.size(), 3):
		var a: Vector3 = pts[faces[f]]
		var b: Vector3 = pts[faces[f + 1]]
		var c: Vector3 = pts[faces[f + 2]]
		var cols := detail + 1
		var grid := []
		for i in cols + 1:
			var aj := a.lerp(c, float(i) / cols)
			var bj := b.lerp(c, float(i) / cols)
			var rows := cols - i
			var row := []
			for j in rows + 1:
				if j == 0 and i == cols:
					row.append(aj)
				else:
					row.append(aj.lerp(bj, float(j) / rows) if rows > 0 else aj)
			grid.append(row)
		for i in cols:
			for j in 2 * (cols - i) - 1:
				var k := j >> 1
				var p0: Vector3
				var p1: Vector3
				var p2: Vector3
				if j % 2 == 0:
					p0 = grid[i][k + 1]
					p1 = grid[i + 1][k]
					p2 = grid[i][k]
				else:
					p0 = grid[i][k + 1]
					p1 = grid[i + 1][k + 1]
					p2 = grid[i + 1][k]
				p0 = p0.normalized() * radius
				p1 = p1.normalized() * radius
				p2 = p2.normalized() * radius
				g._tri(p0, p1, p2, p0.normalized(), p1.normalized(), p2.normalized(), _sph_uv(p0), _sph_uv(p1), _sph_uv(p2))
	if detail == 0:
		g.flat_normals()
	return g


static func _sph_uv(p: Vector3) -> Vector2:
	var u := atan2(p.z, -p.x) / TAU + 0.5
	var vv := atan2(-p.y, sqrt(p.x * p.x + p.z * p.z)) / PI + 0.5
	return Vector2(u, vv)


static func octahedron(radius := 1.0, detail := 0) -> Geo:
	return polyhedron([1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1, 0, 0, 0, 1, 0, 0, -1],
		[0, 2, 4, 0, 4, 3, 0, 3, 5, 0, 5, 2, 1, 2, 5, 1, 5, 3, 1, 3, 4, 1, 4, 2], radius, detail)


static func icosahedron(radius := 1.0, detail := 0) -> Geo:
	var t := (1.0 + sqrt(5.0)) / 2.0
	return polyhedron([-1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, 0, 0, -1, t, 0, 1, t, 0, -1, -t, 0, 1, -t, t, 0, -1, t, 0, 1, -t, 0, -1, -t, 0, 1],
		[0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8, 3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1], radius, detail)


static func tetrahedron(radius := 1.0, detail := 0) -> Geo:
	return polyhedron([1, 1, 1, -1, -1, 1, -1, 1, -1, 1, -1, -1], [2, 1, 0, 0, 3, 2, 1, 3, 0, 2, 3, 1], radius, detail)


static func dodecahedron(radius := 1.0, detail := 0) -> Geo:
	var t := (1.0 + sqrt(5.0)) / 2.0
	var r := 1.0 / t
	var verts := [
		-1, -1, -1, -1, -1, 1, -1, 1, -1, -1, 1, 1, 1, -1, -1, 1, -1, 1, 1, 1, -1, 1, 1, 1,
		0, -r, -t, 0, -r, t, 0, r, -t, 0, r, t, -r, -t, 0, -r, t, 0, r, -t, 0, r, t, 0,
		-t, 0, -r, t, 0, -r, -t, 0, r, t, 0, r]
	var faces := [
		3, 11, 7, 3, 7, 15, 3, 15, 13, 7, 19, 17, 7, 17, 6, 7, 6, 15, 17, 4, 8, 17, 8, 10, 17, 10, 6,
		8, 0, 16, 8, 16, 2, 8, 2, 10, 0, 12, 1, 0, 1, 18, 0, 18, 16, 6, 10, 2, 6, 2, 13, 6, 13, 15,
		2, 16, 18, 2, 18, 3, 2, 3, 13, 18, 1, 9, 18, 9, 11, 18, 11, 3, 4, 14, 12, 4, 12, 0, 4, 0, 8,
		11, 9, 5, 11, 5, 19, 11, 19, 7, 19, 5, 14, 19, 14, 4, 19, 4, 17, 1, 12, 14, 1, 14, 5, 1, 5, 9]
	return polyhedron(verts, faces, radius, detail)


## Triangular prism: low edge at z=0,y=0; high edge at z=len, y=height. x spans width.
static func wedge(length: float, height: float, width: float, uv_density := 0.15) -> Geo:
	var w := width / 2.0
	var A := Vector3(-w, 0, 0)
	var B := Vector3(w, 0, 0)
	var C := Vector3(-w, 0, length)
	var D := Vector3(w, 0, length)
	var E := Vector3(-w, height, length)
	var F := Vector3(w, height, length)
	var tris := [[A, C, D], [A, D, B], [C, E, F], [C, F, D], [A, B, F], [A, F, E], [A, E, C], [B, D, F]]
	var g := Geo.new()
	for t in tris:
		var t0: Vector3 = t[0]
		var t1: Vector3 = t[1]
		var t2: Vector3 = t[2]
		var uvs := []
		for p in t:
			uvs.append(Vector2((p.x + p.z) * uv_density, (p.y + p.z) * uv_density))
		var fn := (t1 - t0).cross(t2 - t0).normalized()
		g._tri(t0, t1, t2, fn, fn, fn, uvs[0], uvs[1], uvs[2])
	return g


## Flat polygon (XY plane, facing +Z) from a list of Vector2 points (simple polygon, any winding).
static func shape(points: PackedVector2Array) -> Geo:
	var g := Geo.new()
	var idx := Geometry2D.triangulate_polygon(points)
	var bb := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bb = bb.expand(p)
	var i := 0
	while i + 2 < idx.size():
		var a := points[idx[i]]
		var b := points[idx[i + 1]]
		var c := points[idx[i + 2]]
		var pa := Vector3(a.x, a.y, 0)
		var pb := Vector3(b.x, b.y, 0)
		var pc := Vector3(c.x, c.y, 0)
		if (pb - pa).cross(pc - pa).z < 0:
			var tmp := pb
			pb = pc
			pc = tmp
		var nz := Vector3(0, 0, 1)
		g._tri(pa, pb, pc, nz, nz, nz, Vector2(pa.x, pa.y), Vector2(pb.x, pb.y), Vector2(pc.x, pc.y))
		i += 3
	return g


## Extruded polygon along +Z from 0 to depth (three's ExtrudeGeometry without bevel).
static func extrude(points: PackedVector2Array, depth: float) -> Geo:
	var front := shape(points).translate(0, 0, depth)
	var back := shape(points)
	# flip the back face
	var i := 0
	while i + 2 < back.v.size():
		var t := back.v[i + 1]
		back.v[i + 1] = back.v[i + 2]
		back.v[i + 2] = t
		back.n[i] = Vector3(0, 0, -1)
		back.n[i + 1] = Vector3(0, 0, -1)
		back.n[i + 2] = Vector3(0, 0, -1)
		i += 3
	var g := Geo.new()
	g.merge(front)
	g.merge(back)
	# sides
	var area := 0.0
	for k in points.size():
		var p := points[k]
		var q := points[(k + 1) % points.size()]
		area += p.x * q.y - q.x * p.y
	var ccw := area > 0
	for k in points.size():
		var p := points[k]
		var q := points[(k + 1) % points.size()]
		if not ccw:
			var tmp := p
			p = q
			q = tmp
		var a := Vector3(p.x, p.y, 0)
		var b := Vector3(q.x, q.y, 0)
		var c := Vector3(q.x, q.y, depth)
		var d := Vector3(p.x, p.y, depth)
		var fn := (b - a).cross(c - a).normalized()
		var L := p.distance_to(q)
		g._tri(a, b, c, fn, fn, fn, Vector2(0, 0), Vector2(L, 0), Vector2(L, depth))
		g._tri(a, c, d, fn, fn, fn, Vector2(0, 0), Vector2(L, depth), Vector2(0, depth))
	return g


## Point on a uniform Catmull-Rom spline through `pts` at t in 0..1 (three's CatmullRomCurve3, open).
static func catmull(pts: Array, t: float) -> Vector3:
	var l := pts.size()
	var p := (l - 1) * t
	var i := int(floor(p))
	var w := p - i
	if i >= l - 1:
		i = l - 2
		w = 1.0
	var p0: Vector3 = pts[maxi(0, i - 1)] if i > 0 else (pts[0] as Vector3) * 2 - (pts[1] as Vector3)
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p3: Vector3 = pts[i + 2] if i + 2 < l else (pts[l - 1] as Vector3) * 2 - (pts[l - 2] as Vector3)
	var w2 := w * w
	var w3 := w2 * w
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * w + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * w2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * w3)


## Tube along a Catmull-Rom curve through `pts` (three's TubeGeometry).
static func tube(pts: Array, tubular := 64, radius := 0.1, radial := 8, closed := false) -> Geo:
	var g := Geo.new()
	var centers := []
	for i in tubular + 1:
		centers.append(catmull(pts, float(i) / tubular))
	# tangents + parallel-transport frames
	var tangents := []
	for i in tubular + 1:
		var a: Vector3 = centers[maxi(0, i - 1)]
		var b: Vector3 = centers[mini(tubular, i + 1)]
		tangents.append((b - a).normalized())
	var t0: Vector3 = tangents[0]
	var ref := Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT
	var normal := t0.cross(ref).normalized()
	var normals := []
	var binormals := []
	for i in tubular + 1:
		var t: Vector3 = tangents[i]
		normal = (normal - t * normal.dot(t)).normalized()
		if normal.length_squared() < 1e-6:
			normal = t.cross(ref).normalized()
		normals.append(normal)
		binormals.append(t.cross(normal).normalized())
	var ring := []
	var ringn := []
	for i in tubular + 1:
		var rv := []
		var rn := []
		for j in radial + 1:
			var a := float(j) / radial * TAU
			var nn: Vector3 = ((normals[i] as Vector3) * -cos(a) + (binormals[i] as Vector3) * sin(a)).normalized()
			rv.append((centers[i] as Vector3) + nn * radius)
			rn.append(nn)
		ring.append(rv)
		ringn.append(rn)
	for i in tubular:
		for j in radial:
			var a: Vector3 = ring[i][j]
			var b: Vector3 = ring[i + 1][j]
			var c: Vector3 = ring[i + 1][j + 1]
			var d: Vector3 = ring[i][j + 1]
			var ua := Vector2(float(i) / tubular, float(j) / radial)
			var ub := Vector2(float(i + 1) / tubular, float(j) / radial)
			var uc := Vector2(float(i + 1) / tubular, float(j + 1) / radial)
			var ud := Vector2(float(i) / tubular, float(j + 1) / radial)
			g._tri(a, b, d, ringn[i][j], ringn[i + 1][j], ringn[i][j + 1], ua, ub, ud)
			g._tri(b, c, d, ringn[i + 1][j], ringn[i + 1][j + 1], ringn[i][j + 1], ub, uc, ud)
	return g

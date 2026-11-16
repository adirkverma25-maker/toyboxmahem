class_name NavGraph
extends RefCounted
## Navigation graph generated automatically from the physics world (port of src/nav/NavGraph.ts):
## 1. Sample walkable surfaces on a grid (multi-level: floor, under the bed, bed top, desk, ramps...).
## 2. Link neighbours with a walk test (step height, slopes, drops, wall + head clearance).
## 3. Keep the strongly connected region so bots never path to places they can't leave.
## Nodes: {id, pos, links: [{to, cost, jump, pad, zip, blockers}], open, blockers}. The built graph is cached
## per map in user://. Breakable pieces are left out of the walk tests; each node/link remembers which standing
## pieces are in its way (`blockers`) and stays closed until they're all broken.

const CACHE_VERSION := 6
static var NONE := PackedInt32Array()

var phys: Phys
var nodes: Array = []
var _cell := 4.0
var _hash := {}
var _space: PhysicsDirectSpaceState3D
var _ray := PhysicsRayQueryParameters3D.new()
## breakable pieces (optional)
var destruction: Destruction
## bumps every time a piece breaks (bots compare it to re-plan)
var revision := 0


func _init(p: Phys) -> void:
	phys = p


func _cast(o: Vector3, d: Vector3, max_d: float) -> Dictionary:
	_ray.from = o
	_ray.to = o + d * max_d
	return _space.intersect_ray(_ray)


func _ray_dist(o: Vector3, d: Vector3, max_d: float) -> float:
	_ray.from = o
	_ray.to = o + d * max_d
	var r := _space.intersect_ray(_ray)
	return INF if r.is_empty() else o.distance_to(r.position)


## build() with breakable pieces taken out of the walk tests, then their blockers recorded.
func build_async(bounds: AABB, cache_key := "", step := 1.6, connectors := []) -> void:
	if destruction == null:
		build(bounds, cache_key, step, connectors)
		return
	destruction.set_nav_mode(true)
	await phys.refresh()
	build(bounds, cache_key, step, connectors)
	destruction.set_nav_mode(false)
	await phys.refresh()


## Which standing pieces sit in each node's capsule and each link's corridor (pieces are on Phys.PIECE only).
func _find_blockers() -> void:
	_space = phys.get_world_3d().direct_space_state
	var R: float = Cfg.MOVE.radius
	var cap := CapsuleShape3D.new()
	cap.radius = R - 0.04
	cap.height = Cfg.MOVE.standHalfHeight * 2 + cap.radius * 2
	var q := PhysicsShapeQueryParameters3D.new()
	q.collision_mask = Phys.PIECE
	q.shape = cap
	for n in nodes:
		var p: Vector3 = n.pos
		q.transform = Transform3D(Basis(), p + Vector3(0, cap.height / 2 + 0.06, 0))
		n.blockers = _ids(_space.intersect_shape(q, 8))
	var box := BoxShape3D.new()
	q.shape = box
	for n in nodes:
		for l in n.links:
			var a: Vector3 = n.pos
			var b: Vector3 = nodes[l.to].pos
			var flat := Vector3(b.x - a.x, 0, b.z - a.z)
			var len := flat.length()
			if len < 0.05:
				l.blockers = NONE
				continue
			var lo := maxf(a.y, b.y) + 0.3
			var hi := maxf(a.y, b.y) + 1.9
			box.size = Vector3(R * 1.2, hi - lo, len)
			var mid := (a + b) / 2
			q.transform = Transform3D(Basis.looking_at(flat / len, Vector3.UP), Vector3(mid.x, (lo + hi) / 2, mid.z))
			l.blockers = _ids(_space.intersect_shape(q, 8))


func _ids(hits: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for h in hits:
		var id := destruction.piece_of(h.collider) if destruction else -1
		if id >= 0 and not out.has(id):
			out.append(id)
	return out


## True when nothing standing blocks it.
func clear_of(blockers) -> bool:
	if blockers == null or destruction == null:
		return true
	for id in blockers:
		if not destruction.is_broken(id):
			return false
	return true


func node_open(id: int) -> bool:
	return clear_of(nodes[id].get("blockers"))


func open_piece(_id: int) -> void:
	revision += 1


## connectors: [[from, to, both_ways], ...] jump pads / ziplines. They only count for keeping the areas they
## reach (rooftops, the shelf) when unreachable islands are pruned; the real special links are added later.
func build(bounds: AABB, cache_key := "", step := 1.6, connectors := []) -> void:
	var t0 := Time.get_ticks_msec()
	if cache_key != "" and _load_cache(cache_key):
		print("[nav] %d nodes from cache in %d ms" % [nodes.size(), Time.get_ticks_msec() - t0])
		return
	_space = phys.get_world_3d().direct_space_state
	_ray.collision_mask = Phys.WORLD
	_ray.hit_from_inside = false
	_ray.hit_back_faces = true
	var mn := bounds.position
	var mx := bounds.end
	var cands := []
	var x := mn.x + 0.8
	while x <= mx.x - 0.8:
		var z := mn.z + 0.8
		while z <= mx.z - 0.8:
			var y := mx.y - 0.5
			var guard := 0
			while guard < 8 and y > -0.5:
				guard += 1
				var hit := _cast(Vector3(x, y, z), Vector3.DOWN, y + 1)
				if hit.is_empty():
					break
				var top: float = hit.position.y
				var ny: float = hit.normal.y
				if y - top > 0.001 and ny > 0.72:
					# on slopes the capsule's round bottom would touch the surface, so test a little higher
					var lift := 0.06 + (1 - ny) * 2.4
					if phys.capsule_fits(Vector3(x, top + lift, z), Cfg.MOVE.radius - 0.04, Cfg.MOVE.standHalfHeight):
						cands.append(Vector3(x, top, z))
				# continue below what we just hit (rays starting inside a shape skip it)
				y = top - 0.03
			z += step
		x += step
	nodes = []
	for i in cands.size():
		nodes.append({"id": i, "pos": cands[i], "links": [], "open": 0})
	_rehash()
	# links
	var max_d := step * 1.5
	for a in nodes:
		for bi in near(a.pos, max_d + 0.1):
			if bi == a.id:
				continue
			var b: Dictionary = nodes[bi]
			var ap: Vector3 = a.pos
			var bp: Vector3 = b.pos
			var dxz := Vector2(bp.x - ap.x, bp.z - ap.z).length()
			if dxz > max_d or dxz < 0.1:
				continue
			var wk := _walkable(ap, bp)
			if wk:
				var drop := ap.y - bp.y
				a.links.append({"to": b.id, "cost": ap.distance_to(bp) + (1.5 if drop > 1 else 0.0) + (2.0 if wk == 2 else 0.0), "jump": wk == 2, "pad": -1, "zip": -1})
	for c in connectors:
		var na := nearest(c[0], false, 4)
		var nb := nearest(c[1], false, 4)
		if na >= 0 and nb >= 0 and na != nb:
			nodes[na].links.append({"to": nb, "cost": 1.0, "jump": false, "pad": -1, "zip": -1, "temp": true})
			if c[2]:
				nodes[nb].links.append({"to": na, "cost": 1.0, "jump": false, "pad": -1, "zip": -1, "temp": true})
	_prune_to_main_region()
	for n in nodes:
		n.links = n.links.filter(func(l): return not l.get("temp", false))
		n.open = n.links.size()
	if destruction:
		_find_blockers()
	print("[nav] %d nodes in %d ms" % [nodes.size(), Time.get_ticks_msec() - t0])
	if cache_key != "":
		_save_cache(cache_key)


func _cache_path(k: String) -> String:
	return "user://nav-%s-v%d.json" % [k, CACHE_VERSION]


func _save_cache(k: String) -> void:
	var out := []
	for n in nodes:
		var links := []
		for l in n.links:
			links.append([l.to, snappedf(l.cost, 0.001), 1 if l.jump else 0, Array(l.get("blockers", NONE))])
		out.append([snappedf(n.pos.x, 0.0001), snappedf(n.pos.y, 0.0001), snappedf(n.pos.z, 0.0001), links, Array(n.get("blockers", NONE))])
	var f := FileAccess.open(_cache_path(k), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(out))


func _load_cache(k: String) -> bool:
	if not FileAccess.file_exists(_cache_path(k)):
		return false
	var data = JSON.parse_string(FileAccess.get_file_as_string(_cache_path(k)))
	if not (data is Array) or data.is_empty():
		return false
	nodes = []
	for i in data.size():
		var d: Array = data[i]
		var links := []
		for l in d[3]:
			links.append({"to": int(l[0]), "cost": float(l[1]), "jump": l[2] == 1, "pad": -1, "zip": -1, "blockers": _ints(l[3] if l.size() > 3 else [])})
		nodes.append({"id": i, "pos": Vector3(d[0], d[1], d[2]), "links": links, "open": links.size(), "blockers": _ints(d[4] if d.size() > 4 else [])})
	_rehash()
	return true


static func _ints(a: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in a:
		out.append(int(v))
	return out


func _rehash() -> void:
	_hash.clear()
	for n in nodes:
		var k := _key(n.pos.x, n.pos.z)
		if not _hash.has(k):
			_hash[k] = []
		_hash[k].append(n.id)


func _key(x: float, z: float) -> Vector2i:
	return Vector2i(floori(x / _cell), floori(z / _cell))


## Node ids whose XZ is within r of p.
func near(p: Vector3, r: float) -> Array:
	var out := []
	var x0 := floori((p.x - r) / _cell)
	var x1 := floori((p.x + r) / _cell)
	var z0 := floori((p.z - r) / _cell)
	var z1 := floori((p.z + r) / _cell)
	for i in range(x0, x1 + 1):
		for j in range(z0, z1 + 1):
			var l = _hash.get(Vector2i(i, j))
			if l == null:
				continue
			for id in l:
				var np: Vector3 = nodes[id].pos
				if (np.x - p.x) * (np.x - p.x) + (np.z - p.z) * (np.z - p.z) <= r * r:
					out.append(id)
	return out


## 0 = not walkable, 1 = walk, 2 = needs one jump (step up to ~1.15 m).
func _walkable(a: Vector3, b: Vector3) -> int:
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var n := maxi(2, ceili(dist / 0.45))
	var g := a.y
	var px := a.x
	var pz := a.z
	var jumped := false
	var R: float = Cfg.MOVE.radius
	var head: float = Cfg.MOVE.standHalfHeight * 2 + R * 2 - 0.1
	for i in range(1, n + 1):
		var t := float(i) / n
		var x := a.x + (b.x - a.x) * t
		var z := a.z + (b.z - a.z) * t
		# ground below the new sample (probe from high enough to find a jumpable ledge)
		var d := _ray_dist(Vector3(x, g + 1.2, z), Vector3.DOWN, 10)
		if d == INF or d < 0.001:
			return 0
		var ng := g + 1.2 - d
		if ng > g + 1.15:
			return 0
		if ng > g + 0.58:
			if jumped:
				return 0
			jumped = true
		if ng < g - 7:
			return 0  # too big a drop
		# horizontal clearance between samples, measured above the higher of the two grounds
		var base := maxf(g, ng)
		var hx := x - px
		var hz := z - pz
		var hl := Vector2(hx, hz).length()
		if hl > 1e-4:
			var dir := Vector3(hx / hl, 0, hz / hl)
			for h in [0.35, 1.45]:
				if _ray_dist(Vector3(px, base + h, pz), dir, hl + R * 0.6) != INF:
					return 0
		# head clearance at the new spot
		if _ray_dist(Vector3(x, ng + 0.1, z), Vector3.UP, head) != INF:
			return 0
		g = ng
		px = x
		pz = z
	if absf(g - b.y) >= 0.45:
		return 0
	return 2 if jumped else 1


func _prune_to_main_region() -> void:
	# seed: node closest to the middle of the play rug
	var seed := -1
	var best := INF
	for n in nodes:
		var p: Vector3 = n.pos
		var d := (p.x + 1) * (p.x + 1) + (p.z - 1) * (p.z - 1) + (p.y - 3.6) * (p.y - 3.6) * 4
		if p.y < 0.5 and d < best:
			best = d
			seed = n.id
	if seed < 0:
		return
	var fwd := {seed: true}
	var q := [seed]
	while q.size():
		var c: int = q.pop_back()
		for l in nodes[c].links:
			if not fwd.has(l.to):
				fwd[l.to] = true
				q.append(l.to)
	var rev := {}
	for n in nodes:
		for l in n.links:
			if not rev.has(l.to):
				rev[l.to] = []
			rev[l.to].append(n.id)
	var back := {seed: true}
	q.append(seed)
	while q.size():
		var c: int = q.pop_back()
		for p in rev.get(c, []):
			if not back.has(p):
				back[p] = true
				q.append(p)
	var keep := nodes.filter(func(n): return fwd.has(n.id) and back.has(n.id))
	var remap := {}
	for i in keep.size():
		remap[keep[i].id] = i
	var out := []
	for i in keep.size():
		var n: Dictionary = keep[i]
		var links := []
		for l in n.links:
			if remap.has(l.to):
				links.append({"to": remap[l.to], "cost": l.cost, "jump": l.jump, "pad": -1, "zip": -1, "temp": l.get("temp", false)})
		out.append({"id": i, "pos": n.pos, "open": 0, "links": links})
	nodes = out
	_rehash()


func _score(p: Vector3, id: int) -> float:
	var n: Vector3 = nodes[id].pos
	var dy := n.y - p.y
	return (n.x - p.x) * (n.x - p.x) + (n.z - p.z) * (n.z - p.z) + dy * dy * 6


## Closest node on roughly the same level, optionally requiring line of sight.
func nearest(p: Vector3, require_los := true, max_r := 8.0) -> int:
	var ids := near(p, max_r)
	ids.sort_custom(func(a, b): return _score(p, a) < _score(p, b))
	for id in ids:
		if not node_open(id):
			continue
		if require_los:
			var np: Vector3 = nodes[id].pos
			if not phys.los(Vector3(p.x, p.y + 0.6, p.z), Vector3(np.x, np.y + 0.6, np.z), true):
				continue
		return id
	if require_los:
		return nearest(p, false, max_r * 2)
	return -1


## A* path: node ids from start to goal (inclusive), or [] when there is none.
func path(start: int, goal: int) -> Array:
	if start < 0 or goal < 0:
		return []
	if start == goal:
		return [start]
	var N := nodes.size()
	var g := PackedFloat32Array()
	g.resize(N)
	g.fill(INF)
	var f := PackedFloat32Array()
	f.resize(N)
	f.fill(INF)
	var came := PackedInt32Array()
	came.resize(N)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(N)
	var heap := []
	var goal_pos: Vector3 = nodes[goal].pos
	g[start] = 0
	f[start] = (nodes[start].pos as Vector3).distance_to(goal_pos)
	_push(heap, f, start)
	var iter := 0
	while heap.size() and iter < 20000:
		iter += 1
		var c := _pop(heap, f)
		if c == goal:
			var out := [c]
			var k := c
			while came[k] >= 0:
				k = came[k]
				out.append(k)
			out.reverse()
			return out
		if closed[c]:
			continue
		closed[c] = 1
		for l in nodes[c].links:
			var to: int = l.to
			if closed[to]:
				continue
			if not clear_of(l.get("blockers")) or not node_open(to):
				continue
			var ng: float = g[c] + l.cost
			if ng < g[to]:
				g[to] = ng
				came[to] = c
				f[to] = ng + (nodes[to].pos as Vector3).distance_to(goal_pos)
				_push(heap, f, to)
	return []


static func _push(heap: Array, f: PackedFloat32Array, id: int) -> void:
	heap.append(id)
	var i := heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if f[heap[p]] <= f[heap[i]]:
			break
		var t = heap[p]
		heap[p] = heap[i]
		heap[i] = t
		i = p


static func _pop(heap: Array, f: PackedFloat32Array) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	if heap.size():
		heap[0] = last
		var i := 0
		while true:
			var l := 2 * i + 1
			var r := l + 1
			var m := i
			if l < heap.size() and f[heap[l]] < f[heap[m]]:
				m = l
			if r < heap.size() and f[heap[r]] < f[heap[m]]:
				m = r
			if m == i:
				break
			var t = heap[m]
			heap[m] = heap[i]
			heap[i] = t
			i = m
	return top


## Jump pad (one way, pad -> landing) or zipline (both ways) between the nodes nearest two points.
func add_special(from: Vector3, to: Vector3, kind: String, id: int, cost: float, both_ways: bool) -> bool:
	var na := nearest(from, false, 4)
	var nb := nearest(to, false, 4)
	if na < 0 or nb < 0 or na == nb:
		return false
	var a: Dictionary = nodes[na]
	var b: Dictionary = nodes[nb]
	if absf(a.pos.y - from.y) > 1.5 or absf(b.pos.y - to.y) > 1.5:
		return false
	a.links.append({"to": nb, "cost": cost, "jump": false, "pad": id if kind == "pad" else -1, "zip": id if kind == "zip" else -1})
	if both_ways:
		b.links.append({"to": na, "cost": cost, "jump": false, "pad": -1, "zip": id if kind == "zip" else -1})
	return true


func link_between(a: int, b: int):
	if a < 0 or a >= nodes.size():
		return null
	for l in nodes[a].links:
		if l.to == b:
			return l
	return null


func random(filter := Callable()) -> int:
	for i in 40:
		var id := randi() % nodes.size()
		if node_open(id) and (not filter.is_valid() or filter.call(nodes[id])):
			return id
	return randi() % nodes.size()


## Pick well-spread spawn points (farthest point sampling).
func spawn_points(count: int, filter := Callable()) -> Array:
	var cand := nodes.filter(func(n): return n.open >= 6) if not filter.is_valid() else nodes.filter(filter)
	cand = cand.filter(func(n): return node_open(n.id))
	if cand.is_empty():
		return [Vector3.ZERO]
	var out := [cand[cand.size() / 2].pos]
	while out.size() < count:
		var best = null
		var best_d := -1.0
		for n in cand:
			var dmin := INF
			for o in out:
				dmin = minf(dmin, (n.pos as Vector3).distance_squared_to(o))
			if dmin > best_d:
				best_d = dmin
				best = n
		if best == null:
			break
		out.append(best.pos)
	return out

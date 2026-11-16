class_name Phys
extends Node3D
## Physics wrapper (port of src/physics/Physics.ts). Static colliders are grouped into one StaticBody3D per
## surface material, so a ray hit tells you what it hit (wood, plastic, fabric...) for sounds and effects.

const WORLD := 1
const CHAR := 2
const DEBRIS := 4
## breakable pieces (also on WORLD while standing; the nav build looks at them on this layer alone)
const PIECE := 8
## break chunks: bounce off the world only (no toys, no bullets, no sight checks)
const CHUNK := 16
const DEFAULT_MASK := WORLD | DEBRIS

var _bodies := {}
var step_hooks: Array[Callable] = []


func _static_body(mat: String) -> StaticBody3D:
	if _bodies.has(mat):
		return _bodies[mat]
	var b := StaticBody3D.new()
	b.name = "static_" + mat
	b.collision_layer = WORLD
	b.collision_mask = 0
	b.set_meta("mat", mat)
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 0.6
	add_child(b)
	_bodies[mat] = b
	return b


func _add(shape: Shape3D, pos: Vector3, rot: Basis, mat: String) -> CollisionShape3D:
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.transform = Transform3D(rot, pos)
	_static_body(mat).add_child(cs)
	return cs


## A number that changes whenever the static level geometry changes (used to key the nav-graph cache).
func static_fingerprint() -> int:
	var parts := PackedStringArray()
	for mat in _bodies:
		for cs in (_bodies[mat] as Node).get_children():
			if cs is CollisionShape3D:
				var t: Transform3D = (cs as CollisionShape3D).transform
				var sh: Shape3D = (cs as CollisionShape3D).shape
				var size := ""
				if sh is BoxShape3D:
					size = str((sh as BoxShape3D).size.snapped(Vector3.ONE * 0.01))
				elif sh is CylinderShape3D:
					size = "%.2f/%.2f" % [(sh as CylinderShape3D).radius, (sh as CylinderShape3D).height]
				elif sh is SphereShape3D:
					size = "%.2f" % (sh as SphereShape3D).radius
				parts.append("%s%s%s" % [t.origin.snapped(Vector3.ONE * 0.01), t.basis.get_euler().snapped(Vector3.ONE * 0.001), size])
	parts.sort()
	return hash("|".join(parts))


## Static box. `half` are half extents.
func box(pos: Vector3, half: Vector3, mat: String, rot := Basis()) -> CollisionShape3D:
	var s := BoxShape3D.new()
	s.size = half * 2.0
	return _add(s, pos, rot, mat)


func cylinder(pos: Vector3, half_height: float, radius: float, mat: String, rot := Basis()) -> CollisionShape3D:
	var s := CylinderShape3D.new()
	s.height = half_height * 2.0
	s.radius = radius
	return _add(s, pos, rot, mat)


func cone(pos: Vector3, half_height: float, radius: float, mat: String) -> CollisionShape3D:
	var pts := PackedVector3Array([Vector3(0, half_height, 0)])
	for i in 16:
		var a := float(i) / 16 * TAU
		pts.append(Vector3(cos(a) * radius, -half_height, sin(a) * radius))
	var s := ConvexPolygonShape3D.new()
	s.points = pts
	return _add(s, pos, Basis(), mat)


func ball(pos: Vector3, radius: float, mat: String) -> CollisionShape3D:
	var s := SphereShape3D.new()
	s.radius = radius
	return _add(s, pos, Basis(), mat)


## Solid convex hull (wedges etc). Points are world-space.
func convex(points: Array, mat: String) -> CollisionShape3D:
	var s := ConvexPolygonShape3D.new()
	s.points = PackedVector3Array(points)
	return _add(s, Vector3.ZERO, Basis(), mat)


## Ramp built from a rotated box from `from` (low end, top-surface point) to `to` (high end).
func ramp(from: Vector3, to: Vector3, width: float, mat: String, thickness := 0.4) -> Dictionary:
	var dir := to - from
	var length := dir.length()
	var mid := (from + to) * 0.5
	var yaw := atan2(dir.x, dir.z)
	var pitch := -asin(dir.y / length)
	var q := U.euler(pitch, yaw, 0, "YXZ")
	var up := q * Vector3.UP
	mid += up * (-thickness / 2.0)
	var c := box(mid, Vector3(width / 2.0, thickness / 2.0, length / 2.0), mat, q)
	return {"collider": c, "center": mid, "basis": q, "length": length}


## Moving obstacle (rc cars, elevators): an AnimatableBody3D we move by setting its transform.
func kinematic_box(pos: Vector3, half: Vector3, mat: String) -> AnimatableBody3D:
	var b := AnimatableBody3D.new()
	b.sync_to_physics = false
	b.collision_layer = WORLD
	b.collision_mask = 0
	b.set_meta("mat", mat)
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.position = pos
	add_child(b)
	return b


## Dynamic debris (loose bricks, falling blocks).
func dynamic_box(pos: Vector3, half: Vector3, mat: String, density := 0.6, rot := Basis()) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.collision_layer = DEBRIS
	b.collision_mask = WORLD | DEBRIS | CHAR
	b.mass = maxf(0.05, half.x * half.y * half.z * 8.0 * density)
	b.continuous_cd = true
	b.linear_damp = 0.2
	b.angular_damp = 0.4
	b.physics_material_override = PhysicsMaterial.new()
	b.physics_material_override.friction = 0.7
	b.physics_material_override.bounce = 0.25
	b.set_meta("mat", mat)
	var cs := CollisionShape3D.new()
	var s := BoxShape3D.new()
	s.size = half * 2.0
	cs.shape = s
	b.add_child(cs)
	b.transform = Transform3D(rot, pos)
	add_child(b)
	return b


func mat_of(collider: Object) -> String:
	if collider and collider.has_meta("mat"):
		return collider.get_meta("mat")
	return "plastic"


func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state


## Raycast against world + debris (never characters). Returns {} on a miss.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, static_only := false) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist, WORLD if static_only else DEFAULT_MASK)
	q.hit_from_inside = true
	q.hit_back_faces = true
	var r := _space().intersect_ray(q)
	if r.is_empty():
		return {}
	var p: Vector3 = r.position
	var col: Object = r.collider
	return {
		"dist": origin.distance_to(p),
		"point": p,
		"normal": r.normal if (r.normal as Vector3).length() > 0.1 else -dir,
		"mat": mat_of(col),
		"collider": col,
		"dynamic_body": col if col is RigidBody3D else null,
	}


## Distance-only raycast (INF on a miss).
func ray_dist(origin: Vector3, dir: Vector3, max_dist: float, static_only := false) -> float:
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_dist, WORLD if static_only else DEFAULT_MASK)
	q.hit_from_inside = true
	var r := _space().intersect_ray(q)
	if r.is_empty():
		return INF
	return origin.distance_to(r.position)


## Line of sight between two points (world only).
func los(a: Vector3, b: Vector3, static_only := false) -> bool:
	var d := b - a
	var l := d.length()
	if l < 1e-4:
		return true
	return ray_dist(a, d / l, l - 0.05, static_only) == INF


## Does a capsule fit here (no overlap with the world)?
func capsule_fits(feet: Vector3, radius: float, half_height: float, static_only := true) -> bool:
	var s := CapsuleShape3D.new()
	s.radius = radius
	s.height = half_height * 2.0 + radius * 2.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = s
	q.transform = Transform3D(Basis(), Vector3(feet.x, feet.y + half_height + radius + 0.05, feet.z))
	q.collision_mask = WORLD if static_only else DEFAULT_MASK
	return _space().intersect_shape(q, 1).is_empty()


## Wait until freshly added colliders are visible to queries.
func refresh() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame


func _physics_process(dt: float) -> void:
	for h in step_hooks:
		h.call(dt)

class_name Debris
extends Node3D
## Chunks that fly off when a wall or prop breaks: a fixed pool of small rigid bodies (they bounce off the
## world but not off toys, and hurt nobody), drawn by one MultiMesh. When the pool is full the oldest chunk is
## reused. Chunks shrink away after LIFE seconds.

const MAX := 80
const LIFE := 6.0
const SHRINK := 0.6

var mm := MultiMesh.new()
var _node := MultiMeshInstance3D.new()
var _bodies: Array[RigidBody3D] = []
var _shapes: Array[BoxShape3D] = []
var _size := PackedVector3Array()
var _age := PackedFloat32Array()
var _live := PackedByteArray()
var _next := 0


func _ready() -> void:
	name = "Debris"
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	box.material = mat
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = box
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	_node.multimesh = mm
	add_child(_node)
	_size.resize(MAX)
	_age.resize(MAX)
	_live.resize(MAX)
	for i in MAX:
		var b := RigidBody3D.new()
		b.collision_layer = Phys.CHUNK
		b.collision_mask = Phys.WORLD
		b.mass = 0.4
		b.linear_damp = 0.3
		b.angular_damp = 0.6
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		cs.shape = sh
		b.add_child(cs)
		b.freeze = true
		b.process_mode = Node.PROCESS_MODE_DISABLED
		add_child(b)
		_bodies.append(b)
		_shapes.append(sh)


## Throw 4-8 chunks out of the box mn..mx (bigger pieces throw more), pushed along dir.
func burst(mn: Vector3, mx: Vector3, color: Color, cls: String, dir: Vector3) -> void:
	var ext := mx - mn
	var vol := ext.x * ext.y * ext.z
	var n := clampi(4 + int(vol * 2.0), 4, 8)
	var scale := 0.35 if cls == "hard" else (0.25 if cls == "soft" else 0.14)
	for k in n:
		var i := _take()
		var s := Vector3(U.rand(0.5, 1.2), U.rand(0.4, 1.0), U.rand(0.4, 1.0)) * scale
		if cls == "glass":
			s.z *= 0.2
		s = s.min(ext.max(Vector3.ONE * 0.05))
		var b := _bodies[i]
		_shapes[i].size = s
		_size[i] = s
		_age[i] = 0.0
		_live[i] = 1
		b.process_mode = Node.PROCESS_MODE_INHERIT
		b.freeze = false
		b.global_transform = Transform3D(Basis.from_euler(Vector3(U.rand(0, TAU), U.rand(0, TAU), U.rand(0, TAU))),
			Vector3(U.rand(mn.x, mx.x), U.rand(mn.y, mx.y), U.rand(mn.z, mx.z)))
		var push := dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
		b.linear_velocity = push * U.rand(2.0, 6.0) + Vector3(U.rand(-2, 2), U.rand(1.5, 4.5), U.rand(-2, 2))
		b.angular_velocity = Vector3(U.rand(-8, 8), U.rand(-8, 8), U.rand(-8, 8))
		b.sleeping = false
		mm.set_instance_color(i, color.darkened(U.rand(0.0, 0.25)))
		_write(i)
	_update_visible()


func live_count() -> int:
	var c := 0
	for i in MAX:
		c += _live[i]
	return c


func clear() -> void:
	for i in MAX:
		_kill(i)
	_update_visible()


## A free slot, or the oldest live one.
func _take() -> int:
	for k in MAX:
		var i := (_next + k) % MAX
		if _live[i] == 0:
			_next = (i + 1) % MAX
			return i
	var oldest := 0
	for i in MAX:
		if _age[i] > _age[oldest]:
			oldest = i
	return oldest


func _kill(i: int) -> void:
	_live[i] = 0
	var b := _bodies[i]
	b.freeze = true
	b.process_mode = Node.PROCESS_MODE_DISABLED
	mm.set_instance_transform(i, Transform3D(Basis.from_scale(Vector3.ZERO), Vector3.ZERO))


func _write(i: int) -> void:
	var k := 1.0
	if _age[i] > LIFE - SHRINK:
		k = clampf((LIFE - _age[i]) / SHRINK, 0.0, 1.0)
	var t := _bodies[i].global_transform
	mm.set_instance_transform(i, Transform3D(t.basis * Basis.from_scale(_size[i] * k), t.origin))


func _update_visible() -> void:
	var top := 0
	for i in MAX:
		if _live[i]:
			top = i + 1
	mm.visible_instance_count = top


func _process(dt: float) -> void:
	var any := false
	for i in MAX:
		if _live[i] == 0:
			continue
		_age[i] += dt
		if _age[i] >= LIFE or _bodies[i].global_position.y < -20:
			_kill(i)
			any = true
			continue
		_write(i)
	if any:
		_update_visible()

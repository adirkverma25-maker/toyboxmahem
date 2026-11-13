class_name Effects
extends Node3D
## Pooled visual effects: soft particles, bouncing plastic chips and springs, decals, tracers, flash lights
## (port of src/fx/Effects.ts). Each pool is one MultiMesh whose buffer is rewritten each frame.

const MAT_COLORS := {
	"plastic": ["#ff5d73", "#ffd166", "#06d6a0", "#4cc9f0", "#ffffff"],
	"wood": ["#c89f73", "#a87b51", "#e2c49c"],
	"fabric": ["#f1e6ff", "#d8e2ff", "#ffe5ec"],
	"carpet": ["#f2e6d0", "#d6c7a8"],
	"metal": ["#fff3b0", "#ffd166", "#ffffff"],
	"cardboard": ["#d4a373", "#e9c46a", "#f1dca7"],
	"glass": ["#e0fbfc", "#ffffff", "#c2f0ff"],
}


## Soft camera-facing particles.
class ParticlePool:
	var n: int
	var mm := MultiMesh.new()
	var node := MultiMeshInstance3D.new()
	var buf := PackedFloat32Array()
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var col := PackedColorArray()
	var size := PackedFloat32Array()
	var life := PackedFloat32Array()
	var mx := PackedFloat32Array()
	var grow := PackedFloat32Array()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var a0 := PackedFloat32Array()
	var next := 0
	var alive := 0
	var dirty := false

	func _init(count: int, additive: bool) -> void:
		n = count
		for a in [pos, vel]:
			a.resize(n)
		col.resize(n)
		for a in [size, life, mx, grow, grav, drag, a0]:
			a.resize(n)
		buf.resize(n * 16)
		var q := QuadMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/particle_add.gdshader" if additive else "res://shaders/particle.gdshader")
		mat.set_shader_parameter("uMap", Tex.soft_dot())
		mat.render_priority = 3 if additive else 2
		q.material = mat
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = q
		mm.instance_count = n
		mm.visible_instance_count = 0
		mm.buffer = buf
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))

	func emit(p: Vector3, v: Vector3, color: Color, sz: float, lf: float, opts := {}) -> void:
		var i := next
		next = (next + 1) % n
		if i >= mm.visible_instance_count:
			mm.visible_instance_count = i + 1
		if life[i] <= 0:
			alive += 1
		pos[i] = p
		vel[i] = v
		col[i] = color
		size[i] = sz
		life[i] = lf
		mx[i] = lf
		grow[i] = opts.get("grow", 0.0)
		grav[i] = opts.get("gravity", 0.0)
		drag[i] = opts.get("drag", 0.0)
		a0[i] = opts.get("alpha", 1.0)
		dirty = true

	func update(dt: float) -> void:
		if alive <= 0 and not dirty:
			return
		var count := 0
		var top := 0
		for i in n:
			if life[i] <= 0:
				continue
			life[i] -= dt
			var o := i * 16
			if life[i] <= 0:
				buf[o] = 0
				buf[o + 5] = 0
				buf[o + 10] = 0
				continue
			count += 1
			top = i + 1
			var k := maxf(0, life[i] / mx[i])
			var d := maxf(0, 1 - drag[i] * dt)
			var v := vel[i]
			v.x *= d
			v.y = v.y * d - grav[i] * dt
			v.z *= d
			vel[i] = v
			var p := pos[i] + v * dt
			pos[i] = p
			size[i] += grow[i] * dt
			var s := size[i]
			var c := col[i]
			buf[o] = s
			buf[o + 1] = 0
			buf[o + 2] = 0
			buf[o + 3] = p.x
			buf[o + 4] = 0
			buf[o + 5] = s
			buf[o + 6] = 0
			buf[o + 7] = p.y
			buf[o + 8] = 0
			buf[o + 9] = 0
			buf[o + 10] = s
			buf[o + 11] = p.z
			buf[o + 12] = c.r
			buf[o + 13] = c.g
			buf[o + 14] = c.b
			buf[o + 15] = a0[i] * (k / 0.6 if k < 0.6 else 1.0)
		alive = count
		mm.visible_instance_count = top
		mm.buffer = buf
		dirty = false

	func clear() -> void:
		life.fill(0)
		buf.fill(0)
		mm.buffer = buf
		mm.visible_instance_count = 0
		alive = 0


## Physical-ish bouncing pieces drawn with one MultiMesh.
class ChipPool:
	var n: int
	var mm := MultiMesh.new()
	var node := MultiMeshInstance3D.new()
	var buf := PackedFloat32Array()
	var p := PackedVector3Array()
	var v := PackedVector3Array()
	var r := PackedVector3Array()
	var w := PackedVector3Array()
	var s := PackedVector3Array()
	var life := PackedFloat32Array()
	var floor_y := PackedFloat32Array()
	var next := 0
	var alive := 0
	var dirty := false

	func _init(count: int, mesh: Mesh) -> void:
		n = count
		for a in [p, v, r, w, s]:
			a.resize(n)
		life.resize(n)
		floor_y.resize(n)
		buf.resize(n * 16)
		for i in n:
			buf[i * 16 + 12] = 1
			buf[i * 16 + 13] = 1
			buf[i * 16 + 14] = 1
			buf[i * 16 + 15] = 1
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = n
		mm.visible_instance_count = 0
		mm.buffer = buf
		node.multimesh = mm
		node.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))

	func emit(pos: Vector3, vel: Vector3, color, size: Vector3, lf: float, fy: float) -> void:
		var i := next
		next = (next + 1) % n
		if i >= mm.visible_instance_count:
			mm.visible_instance_count = i + 1
		if life[i] <= 0:
			alive += 1
		p[i] = pos
		v[i] = vel
		r[i] = Vector3(randf() * 6, randf() * 6, randf() * 6)
		w[i] = Vector3(U.rand(-12, 12), U.rand(-12, 12), U.rand(-12, 12))
		s[i] = size
		life[i] = lf
		floor_y[i] = fy
		var c := U.col(color).srgb_to_linear()
		buf[i * 16 + 12] = c.r
		buf[i * 16 + 13] = c.g
		buf[i * 16 + 14] = c.b
		dirty = true

	func update(dt: float) -> void:
		if alive <= 0 and not dirty:
			return
		var count := 0
		var top := 0
		for i in n:
			if life[i] <= 0:
				continue
			life[i] -= dt
			var o := i * 16
			if life[i] <= 0:
				for k in 12:
					buf[o + k] = 0
				continue
			count += 1
			top = i + 1
			var pv := v[i]
			pv.y -= 18 * dt
			var pp := p[i] + pv * dt
			var half := s[i].y * 0.5
			if pp.y < floor_y[i] + half and pv.y < 0:
				pp.y = floor_y[i] + half
				pv.y *= -0.38
				pv.x *= 0.7
				pv.z *= 0.7
				w[i] *= 0.6
				if absf(pv.y) < 0.6:
					pv.y = 0
			v[i] = pv
			p[i] = pp
			r[i] += w[i] * dt
			var fade := minf(1, life[i] / 0.4)
			var b := Basis.from_euler(r[i]).scaled_local(s[i] * fade)
			buf[o] = b.x.x
			buf[o + 1] = b.y.x
			buf[o + 2] = b.z.x
			buf[o + 3] = pp.x
			buf[o + 4] = b.x.y
			buf[o + 5] = b.y.y
			buf[o + 6] = b.z.y
			buf[o + 7] = pp.y
			buf[o + 8] = b.x.z
			buf[o + 9] = b.y.z
			buf[o + 10] = b.z.z
			buf[o + 11] = pp.z
		alive = count
		mm.visible_instance_count = top
		mm.buffer = buf
		dirty = false

	func clear() -> void:
		life.fill(0)
		for i in n:
			for k in 12:
				buf[i * 16 + k] = 0
		mm.buffer = buf
		mm.visible_instance_count = 0
		alive = 0


## Flat decals stuck to surfaces (bullet holes, paint).
class DecalPool:
	var n: int
	var fade: float
	var mm := MultiMesh.new()
	var node := MultiMeshInstance3D.new()
	var buf := PackedFloat32Array()
	var life := PackedFloat32Array()
	var a0 := PackedFloat32Array()
	var next := 0
	var alive := 0

	func _init(count: int, tex: Texture2D, fade_time: float) -> void:
		n = count
		fade = fade_time
		life.resize(n)
		a0.resize(n)
		buf.resize(n * 20)
		var q := QuadMesh.new()
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/decal.gdshader")
		mat.set_shader_parameter("uMap", tex)
		mat.render_priority = 1
		q.material = mat
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = q
		mm.instance_count = n
		mm.visible_instance_count = 0
		mm.buffer = buf
		node.multimesh = mm
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-500, -500, -500), Vector3(1000, 1000, 1000))

	func add(pt: Vector3, normal: Vector3, size: float, color, lf: float, alpha := 1.0) -> void:
		var i := next
		next = (next + 1) % n
		if i >= mm.visible_instance_count:
			mm.visible_instance_count = i + 1
		if life[i] <= 0:
			alive += 1
		var nn := normal.normalized()
		var b := _face(nn) * Basis(Vector3.BACK, randf() * TAU)
		b = b.scaled_local(Vector3(size, size, size))
		var p := pt + nn * 0.02
		var o := i * 20
		buf[o] = b.x.x
		buf[o + 1] = b.y.x
		buf[o + 2] = b.z.x
		buf[o + 3] = p.x
		buf[o + 4] = b.x.y
		buf[o + 5] = b.y.y
		buf[o + 6] = b.z.y
		buf[o + 7] = p.y
		buf[o + 8] = b.x.z
		buf[o + 9] = b.y.z
		buf[o + 10] = b.z.z
		buf[o + 11] = p.z
		var c := U.col(color)
		buf[o + 12] = c.r
		buf[o + 13] = c.g
		buf[o + 14] = c.b
		buf[o + 15] = 1
		buf[o + 16] = alpha
		life[i] = lf
		a0[i] = alpha
		mm.buffer = buf

	## Basis turning +Z toward `d` (three's setFromUnitVectors(z, d)).
	static func _face(d: Vector3) -> Basis:
		var z := Vector3.BACK
		var c := z.cross(d)
		if c.length() < 1e-6:
			return Basis() if d.z > 0 else Basis(Vector3.UP, PI)
		return Basis(c.normalized(), z.angle_to(d))

	func update(dt: float) -> void:
		if alive <= 0:
			return
		var count := 0
		var top := 0
		for i in n:
			if life[i] <= 0:
				continue
			life[i] -= dt
			buf[i * 20 + 16] = a0[i] * minf(1, maxf(0, life[i]) / fade)
			if life[i] > 0:
				count += 1
				top = i + 1
			else:
				for k in 12:
					buf[i * 20 + k] = 0
		alive = count
		mm.visible_instance_count = top
		mm.buffer = buf

	func clear() -> void:
		life.fill(0)
		buf.fill(0)
		mm.buffer = buf
		mm.visible_instance_count = 0
		alive = 0


var soft: ParticlePool
var glow: ParticlePool
var chips: ChipPool
var springs: ChipPool
var impacts: DecalPool
var splats: DecalPool
var _tracers: Array = []
var _tracer_mesh: ArrayMesh
var lights: Array = []
var _trails: Array = []
var reduced_motion := false
var _floor_below := func(p: Vector3) -> float: return maxf(0, p.y - 3)


func _init() -> void:
	name = "Effects"
	soft = ParticlePool.new(1400, false)
	glow = ParticlePool.new(1200, true)
	add_child(soft.node)
	add_child(glow.node)
	var chip_mat := StandardMaterial3D.new()
	chip_mat.roughness = 0.35
	chip_mat.clearcoat_enabled = true
	chip_mat.clearcoat = 0.6
	chip_mat.vertex_color_use_as_albedo = true
	chips = ChipPool.new(500, Geo.rounded_box(1, 1, 1, 1, 0.15).to_mesh(chip_mat))
	var helix := []
	for i in 30:
		helix.append(Vector3(cos(i * 0.9) * 0.5, float(i) / 30 - 0.5, sin(i * 0.9) * 0.5))
	var spring_mat := Mats.metal("#d9dde3", 0.25)
	springs = ChipPool.new(48, Geo.tube(helix, 60, 0.07, 6).to_mesh(spring_mat))
	add_child(chips.node)
	add_child(springs.node)
	impacts = DecalPool.new(220, Tex.decal("impact"), 2.5)
	splats = DecalPool.new(70, Tex.decal("splat"), 3)
	add_child(impacts.node)
	add_child(splats.node)
	_tracer_mesh = Geo.box(1, 1, 1).translate(0, 0, 0.5).to_mesh()
	for i in 90:
		var m := MeshInstance3D.new()
		m.mesh = _tracer_mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		m.material_override = mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		m.extra_cull_margin = 300
		add_child(m)
		_tracers.append({"mesh": m, "mat": mat, "life": 0.0, "max": 1.0, "from": Vector3.ZERO, "to": Vector3.ZERO, "travel": 0.0, "width": 0.05})
	for i in 3:
		var l := OmniLight3D.new()
		l.light_energy = 0
		l.omni_range = 12
		l.omni_attenuation = 2
		l.shadow_enabled = false
		add_child(l)
		lights.append({"light": l, "life": 0.0, "max": 1.0, "i0": 0.0})


func set_floor_probe(fn: Callable) -> void:
	_floor_below = fn


func flash_light(pos: Vector3, color, intensity: float, lf: float, distance := 12.0) -> void:
	var slot = null
	for l in lights:
		if l.life <= 0:
			slot = l
			break
	if slot == null:
		slot = lights[0]
		for l in lights:
			if l.life < slot.life:
				slot = l
	var light: OmniLight3D = slot.light
	light.position = pos
	light.light_color = U.col(color)
	light.omni_range = distance
	slot.i0 = intensity * Lighting.POINT_SCALE
	slot.life = lf
	slot.max = lf


func tracer(from: Vector3, to: Vector3, color, width: float, lf: float, travel := 0.0) -> void:
	var t = null
	for x in _tracers:
		if x.life <= 0:
			t = x
			break
	if t == null:
		t = _tracers[0]
	t.from = from
	t.to = to
	t.life = lf + travel
	t.max = lf + travel
	t.travel = travel
	t.width = width
	(t.mat as StandardMaterial3D).albedo_color = U.col(color)
	t.mesh.visible = true


func impact(point: Vector3, normal: Vector3, mat: String, opts := {}) -> void:
	var cols: Array = MAT_COLORS.get(mat, MAT_COLORS.plastic)
	var big: bool = opts.get("big", false)
	var count := 10 if big else 4
	var fl: float = _floor_below.call(point)
	for i in count:
		var v := normal * U.rand(2, 6) + Vector3(U.rand(-2.5, 2.5), U.rand(0, 3.5), U.rand(-2.5, 2.5))
		if mat == "plastic" or mat == "cardboard" or mat == "wood":
			var s := U.rand(0.06, 0.16) if mat == "cardboard" else U.rand(0.04, 0.1)
			chips.emit(point, v, opts.get("color", U.pick(cols)), Vector3(s, s * 0.2 if mat == "cardboard" else s, s), U.rand(0.8, 1.6), fl)
		else:
			glow.emit(point, v * 0.6, U.col(U.pick(cols)), U.rand(0.1, 0.18), U.rand(0.15, 0.35), {"gravity": 6, "drag": 2})
	# dust / puff
	var puff := U.col("#d9c2a0" if mat == "wood" else ("#f7f1ff" if mat == "fabric" or mat == "carpet" else ("#d8b98a" if mat == "cardboard" else "#ffffff")))
	for i in (4 if mat == "fabric" or mat == "wood" or mat == "carpet" else 2):
		soft.emit(point + normal * 0.1, normal * U.rand(0.5, 1.6) + Vector3(U.rand(-0.5, 0.5), U.rand(0, 0.6), U.rand(-0.5, 0.5)), puff, U.rand(0.35, 0.6), U.rand(0.4, 0.8), {"grow": 1.2, "drag": 3, "alpha": 0.55})
	if mat == "metal" or mat == "glass":
		glow.emit(point + normal * 0.05, Vector3.ZERO, U.col("#e6fbff" if mat == "glass" else "#fff1b8"), 0.6, 0.08)
	if opts.get("decal", true):
		impacts.add(point, normal, U.rand(0.18, 0.28), "#3b2615" if mat == "wood" else ("#7d6f80" if mat == "fabric" or mat == "carpet" else "#2a2a2a"), 8, 0.55)


## Soft spark when a bullet hits a toy.
func hit_spark(point: Vector3, color: String, shield: bool, head: bool) -> void:
	var c := U.col("#6fd3ff" if shield else ("#ffe066" if head else color))
	for i in (7 if head else 4):
		glow.emit(point, Vector3(U.rand(-3, 3), U.rand(-1, 4), U.rand(-3, 3)), c, U.rand(0.12, 0.22), U.rand(0.15, 0.3), {"gravity": 8, "drag": 2})
	var fl: float = _floor_below.call(point)
	for i in 2:
		chips.emit(point, Vector3(U.rand(-3, 3), U.rand(1, 4), U.rand(-3, 3)), "#bdeeff" if shield else color, Vector3(0.06, 0.06, 0.06), 1, fl)


func muzzle(pos: Vector3, dir: Vector3, color: String, scale := 1.0) -> void:
	var c := U.col(color)
	glow.emit(pos, Vector3.ZERO, c, 0.9 * scale, 0.06)
	glow.emit(pos + dir * (0.25 * scale), dir * 4, Color.WHITE, 0.45 * scale, 0.05)
	for i in 3:
		glow.emit(pos, dir * U.rand(3, 8) + Vector3(U.rand(-1, 1), U.rand(-1, 1), U.rand(-1, 1)), c, 0.12, 0.12, {"drag": 4})


## A toy pops apart into plastic pieces, springs and confetti.
func break_apart(pos: Vector3, colors: Array, reduced: bool) -> void:
	var fl: float = _floor_below.call(pos + Vector3(0, 0.5, 0))
	for i in (14 if reduced else 30):
		var s := U.rand(0.12, 0.32)
		chips.emit(pos + Vector3(U.rand(-0.3, 0.3), U.rand(0.2, 1.6), U.rand(-0.3, 0.3)), Vector3(U.rand(-5, 5), U.rand(3, 9), U.rand(-5, 5)),
			U.pick(colors), Vector3(s, s * U.rand(0.5, 1.4), s * U.rand(0.6, 1.5)), U.rand(2.6, 3.6), fl)
	for i in (2 if reduced else 4):
		springs.emit(pos + Vector3(0, 1, 0), Vector3(U.rand(-4, 4), U.rand(5, 10), U.rand(-4, 4)), "#ffffff", Vector3(0.45, 0.6, 0.45), 3, fl)
	var confetti := ["#ff5d8f", "#ffd166", "#06d6a0", "#4cc9f0", "#c77dff"] + colors
	for i in (20 if reduced else 50):
		glow.emit(pos + Vector3(0, 1, 0), Vector3(U.rand(-6, 6), U.rand(1, 9), U.rand(-6, 6)), U.col(U.pick(confetti)), U.rand(0.1, 0.2), U.rand(0.6, 1.2), {"gravity": 9, "drag": 1.5})
	for i in 6:
		soft.emit(pos + Vector3(0, 0.9, 0), Vector3(U.rand(-1.5, 1.5), U.rand(0.5, 2), U.rand(-1.5, 1.5)), Color.WHITE, U.rand(0.8, 1.4), U.rand(0.5, 0.9), {"grow": 2, "drag": 2, "alpha": 0.6})
	flash_light(pos + Vector3(0, 1, 0), "#ffd6a5", 30, 0.25, 10)


## Pieces fly in and snap together at a spawn point.
func reassemble(pos: Vector3, colors: Array) -> void:
	var c0 := pos + Vector3(0, 0.9, 0)
	for i in 28:
		var dir := Vector3(U.rand(-1, 1), U.rand(-0.2, 1), U.rand(-1, 1)).normalized()
		var start := c0 + dir * U.rand(1.5, 2.5)
		glow.emit(start, (c0 - start) / 0.35, U.col(U.pick(colors)), U.rand(0.14, 0.24), 0.35, {"alpha": 0.9})
	glow.emit(c0, Vector3.ZERO, Color.WHITE, 3, 0.3)


func explosion(pos: Vector3, normal: Vector3, colors: Array, reduced: bool) -> void:
	var fl: float = _floor_below.call(pos + Vector3(0, 0.3, 0))
	for i in (30 if reduced else 70):
		glow.emit(pos, Vector3(U.rand(-1, 1), U.rand(-0.3, 1), U.rand(-1, 1)).normalized() * U.rand(4, 13), U.col(U.pick(colors)), U.rand(0.18, 0.35), U.rand(0.4, 0.9), {"gravity": 10, "drag": 2})
	for i in (6 if reduced else 14):
		soft.emit(pos, Vector3(U.rand(-2.5, 2.5), U.rand(0.5, 3.5), U.rand(-2.5, 2.5)), U.col(U.pick(colors)).lerp(Color.WHITE, 0.4), U.rand(1.2, 2.2), U.rand(0.7, 1.3), {"grow": 3, "drag": 2.5, "alpha": 0.75})
	for i in 12:
		var s := U.rand(0.08, 0.2)
		chips.emit(pos + normal * 0.3, Vector3(U.rand(-7, 7), U.rand(3, 10), U.rand(-7, 7)), U.pick(colors), Vector3(s, s * 3, s), U.rand(1.5, 2.5), fl)
	glow.emit(pos, Vector3.ZERO, U.col("#fff4d6"), 7, 0.12)
	flash_light(pos, colors[0], 90, 0.3, 16)


func paint_splat(point: Vector3, normal: Vector3, color: String, size: float) -> void:
	splats.add(point, normal, size, color, 12, 0.92)


func bubble_burst(pos: Vector3, color: String) -> void:
	for i in 5:
		glow.emit(pos, Vector3(U.rand(-2, 2), U.rand(-1, 2.5), U.rand(-2, 2)), U.col(U.pick([color, "#ffffff", "#9be7ff", "#ffc6ff"])), U.rand(0.08, 0.16), U.rand(0.2, 0.4), {"gravity": 2, "drag": 3})
	soft.emit(pos, Vector3(0, 0.3, 0), U.col("#f0e6ff"), 0.5, 0.25, {"grow": 2, "alpha": 0.4})


func energy_hit(pos: Vector3, color: String) -> void:
	for i in 6:
		glow.emit(pos, Vector3(U.rand(-4, 4), U.rand(-2, 4), U.rand(-4, 4)), U.col(color), U.rand(0.08, 0.15), U.rand(0.15, 0.3), {"drag": 5})
	glow.emit(pos, Vector3.ZERO, Color.WHITE, 0.8, 0.07)
	flash_light(pos, color, 12, 0.08, 6)


func pickup_sparkle(pos: Vector3, color: String) -> void:
	for i in 18:
		glow.emit(pos + Vector3(0, 0.6, 0), Vector3(U.rand(-2, 2), U.rand(1, 4), U.rand(-2, 2)), U.col(color), U.rand(0.1, 0.2), U.rand(0.4, 0.7), {"gravity": 3, "drag": 2})


## Coil-shaped trail for the Wind-Up Dash.
func spring_trail(from: Vector3, to: Vector3, color: String) -> void:
	var dir := to - from
	var l := dir.length()
	if l < 0.5:
		return
	dir = dir.normalized()
	var side := dir.cross(Vector3.UP).normalized()
	var up := side.cross(dir).normalized()
	var pts := []
	var coils := maxi(4, int(floor(l * 1.2)))
	for i in coils * 10 + 1:
		var t := float(i) / (coils * 10)
		var a := t * coils * TAU
		pts.append(from + dir * (l * t) + side * (cos(a) * 0.35) + up * (sin(a) * 0.35 + 0.9))
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.albedo_color = U.col(color)
	mat.albedo_color.a = 0.9
	var mesh := Geo.tube(pts, pts.size(), 0.035, 5).mesh_instance(mat, Vector3.ZERO, Basis(), false)
	add_child(mesh)
	_trails.append({"mesh": mesh, "mat": mat, "life": 0.45, "max": 0.45})


func update(dt: float, _cam_pos := Vector3.ZERO) -> void:
	soft.update(dt)
	glow.update(dt)
	chips.update(dt)
	springs.update(dt)
	impacts.update(dt)
	splats.update(dt)
	for t in _tracers:
		if t.life <= 0:
			continue
		t.life -= dt
		if t.life <= 0:
			t.mesh.visible = false
			continue
		var age: float = t.max - t.life
		var mat: StandardMaterial3D = t.mat
		var from: Vector3 = t.from
		var to: Vector3 = t.to
		var total := from.distance_to(to)
		var head := total
		var tail := 0.0
		var op := 1.0
		if t.travel > 0:
			var k := minf(1, age / t.travel)
			head = total * k
			tail = maxf(0, head - minf(6, total * 0.35))
			if k >= 1:
				op = maxf(0, t.life / (t.max - t.travel))
		else:
			op = maxf(0, t.life / t.max)
		mat.albedo_color.a = op
		if total < 1e-4:
			t.mesh.visible = false
			continue
		var dir := (to - from) / total
		var w: float = t.width * (0.6 + 0.4 * op)
		var b := DecalPool._face(dir).scaled_local(Vector3(w, w, maxf(0.01, head - tail)))
		(t.mesh as Node3D).transform = Transform3D(b, from + dir * tail)
	for l in lights:
		if l.life <= 0:
			(l.light as OmniLight3D).light_energy = 0
			continue
		l.life -= dt
		(l.light as OmniLight3D).light_energy = l.i0 * maxf(0, l.life / l.max)
	for i in range(_trails.size() - 1, -1, -1):
		var tr: Dictionary = _trails[i]
		tr.life -= dt
		(tr.mat as StandardMaterial3D).albedo_color.a = maxf(0, tr.life / tr.max) * 0.9
		if tr.life <= 0:
			(tr.mesh as Node).queue_free()
			_trails.remove_at(i)


func clear() -> void:
	soft.clear()
	glow.clear()
	chips.clear()
	springs.clear()
	impacts.clear()
	splats.clear()
	for t in _tracers:
		t.life = 0
		t.mesh.visible = false
	for l in lights:
		l.life = 0
	for tr in _trails:
		(tr.mesh as Node).queue_free()
	_trails = []

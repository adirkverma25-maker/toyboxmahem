class_name ToyRig
extends Node3D
## Procedurally built and procedurally animated toy figure (port of the ToyRig half of ToyModels.ts).
## Hierarchy: root(yaw) > hips > torso > (neck > head), shoulders > arms; hips > legs.
## anim state: {speed, grounded, vy, crouch, aimPitch, reload, fireKick, hit, dashing, sliding}

const SKIN := "#ffd8b5"

var def: Dictionary
var hips := Node3D.new()
var torso := Node3D.new()
var neck := Node3D.new()
var head := Node3D.new()
var arm_l := Node3D.new()
var arm_r := Node3D.new()
var fore_l := Node3D.new()
var fore_r := Node3D.new()
var leg_l := Node3D.new()
var leg_r := Node3D.new()
var shin_l := Node3D.new()
var shin_r := Node3D.new()
var weapon_socket := Node3D.new()
var tail: Node3D = null
var antenna: Node3D = null
var cape: MeshInstance3D = null
var eyes: Array = []
var visor: MeshInstance3D = null
var phase := randf() * 10
var blink_t := randf() * 3
var idle_t := randf() * 5
var smooth_crouch := 0.0
var smooth_lean := 0.0
var outline_meshes: Array = []
var shimmer_mats: Array = []
var scale_in := 1.0
var _melee: Node3D = null
var _melee_kind := ""
var _cloak_mat: StandardMaterial3D = null
var _cloak_applied := false
var _outline_on := false
var _outline_mat: StandardMaterial3D = null
var _team_band: Node3D = null
var _team_extra: Array = []
var _visor_base := 0.0


## A part mesh. rot = three.js Euler XYZ, scale = per-axis scale.
static func mesh(g: Geo, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var o := MeshInstance3D.new()
	o.mesh = g.to_mesh()
	o.material_override = m
	o.transform = Transform3D(U.euler(rot.x, rot.y, rot.z).scaled_local(scl), pos)
	return o


static func rbox(w: float, h: float, d: float, r := 0.06) -> Geo:
	return Geo.rounded_box(w, h, d, 2, minf(minf(r, w / 2.01), minf(h / 2.01, d / 2.01)))


static func sphere(r: float, ws := 18, hs := 14) -> Geo:
	return Geo.sphere(r, ws, hs)


static func capsule(r: float, l: float) -> Geo:
	return Geo.capsule(r, l, 6, 14)


static func P(c, opts := {}) -> StandardMaterial3D:
	return Mats.plastic(c, opts)


func _init(d: Dictionary) -> void:
	def = d
	add_child(hips)
	hips.position.y = 0.78
	hips.add_child(torso)
	hips.add_child(leg_l)
	hips.add_child(leg_r)
	leg_l.position = Vector3(-0.17, 0, 0)
	leg_r.position = Vector3(0.17, 0, 0)
	torso.add_child(neck)
	torso.add_child(arm_l)
	torso.add_child(arm_r)
	neck.position.y = 0.58
	neck.add_child(head)
	arm_l.position = Vector3(-0.36, 0.48, 0)
	arm_r.position = Vector3(0.36, 0.48, 0)
	arm_l.add_child(fore_l)
	arm_r.add_child(fore_r)
	fore_l.position.y = -0.3
	fore_r.position.y = -0.3
	fore_r.add_child(weapon_socket)
	weapon_socket.position = Vector3(0, -0.28, 0.06)
	leg_l.add_child(shin_l)
	leg_r.add_child(shin_r)
	shin_l.position.y = -0.38
	shin_r.position.y = -0.38
	call("_build_" + def.get("base", def.id))
	if def.has("recolor"):
		_repaint(def.recolor)
	if has_method("_extra_" + def.id):
		call("_extra_" + def.id)
	# fewer draw calls: merge same-material parts that move together
	var vz := visor
	var cp := cape
	Merge.merge_direct_children(self, func(m): return m == vz or m == cp)
	if visor:
		_visor_base = (visor.material_override as StandardMaterial3D).emission_energy_multiplier


func _meshes(n: Node = self, out: Array = []) -> Array:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_meshes(c, out)
	return out


## Swap colors on every material whose base (or glow) color is in the map. Clones, never edits shared materials.
func _repaint(map: Dictionary) -> void:
	var norm := {}
	for k in map:
		norm[(k as String).to_lower().replace("#", "")] = map[k]
	var cache := {}
	for m: MeshInstance3D in _meshes():
		var mat = m.material_override
		if not (mat is StandardMaterial3D):
			continue
		if not cache.has(mat):
			var c: String = (mat as StandardMaterial3D).albedo_color.to_html(false)
			var e: String = (mat as StandardMaterial3D).emission.to_html(false) if (mat as StandardMaterial3D).emission_enabled else ""
			if norm.has(c) or (e != "" and norm.has(e)):
				var nm: StandardMaterial3D = mat.duplicate()
				if norm.has(c):
					nm.albedo_color = U.col(norm[c])
				if e != "" and norm.has(e):
					nm.emission = U.col(norm[e])
				cache[mat] = nm
			else:
				cache[mat] = mat
		m.material_override = cache[mat]


# ---- melee weapon (third person): in hand for melee fighters, the arm swings it
## t = seconds left on the swing, kind = sword / spear, swing = full swing length, held = it's their weapon
func set_melee(t: float, kind := "sword", swing := 0.5, held := false) -> void:
	if t <= 0 and not held:
		if _melee:
			_melee.visible = false
		for c in weapon_socket.get_children():
			if c != _melee:
				(c as Node3D).visible = true
		return
	if _melee == null or kind != _melee_kind:
		if _melee:
			_melee.queue_free()
		_melee = MeleeModel.build(kind)
		_melee.set_meta("no_outline", true)
		weapon_socket.add_child(_melee)
		_melee_kind = kind
	_melee.visible = true
	# held like the blasters are (the socket points it along the aim)
	_melee.transform = Transform3D(U.euler(PI / 2, PI, 0), Vector3(0, -0.02, 0.06))
	for c in weapon_socket.get_children():
		if c != _melee:
			(c as Node3D).visible = false
	if t > 0:
		var pose := MeleeModel.arm_dir(kind, 1 - t / maxf(swing, 0.01))
		arm_r.basis = _from_down(pose[0])
		fore_r.rotation = Vector3(pose[1], 0, 0)


## Cloak: opacity 0 = normal. Anything > 0 renders the toy as a ghostly shimmer at that opacity.
func set_cloak(opacity: float, t: float) -> void:
	if opacity <= 0:
		if not _cloak_applied:
			return
		_cloak_applied = false
		for m: MeshInstance3D in _meshes():
			if m.has_meta("pre_cloak"):
				m.material_override = m.get_meta("pre_cloak")
				m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				m.remove_meta("pre_cloak")
		for o in outline_meshes:
			o.visible = _outline_on
		return
	if _cloak_mat == null:
		_cloak_mat = StandardMaterial3D.new()
		_cloak_mat.albedo_color = U.col("#dff1ff")
		_cloak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_cloak_mat.roughness = 0.05
		_cloak_mat.metallic = 0.3
		_cloak_mat.clearcoat_enabled = true
		_cloak_mat.clearcoat = 1
		_cloak_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_cloak_mat.emission_enabled = true
		_cloak_mat.emission = U.col("#6fb8ff")
		_cloak_mat.emission_energy_multiplier = 0.2
	_cloak_mat.albedo_color.a = opacity * (0.75 + 0.25 * sin(t * 7 + phase))
	_cloak_applied = true
	for m: MeshInstance3D in _meshes():
		if outline_meshes.has(m):
			continue
		if not m.has_meta("pre_cloak"):
			m.set_meta("pre_cloak", m.material_override)
			m.material_override = _cloak_mat
			m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for o in outline_meshes:
		o.visible = false


## Generic limbs shared by most humanoid toys.
func limbs(body: Material, limb: Material, hand: Material, boot: Material, opts := {}) -> void:
	var t: float = opts.get("thick", 1.0)
	arm_l.add_child(mesh(capsule(0.085 * t, 0.2), limb, Vector3(0, -0.14, 0)))
	arm_r.add_child(mesh(capsule(0.085 * t, 0.2), limb, Vector3(0, -0.14, 0)))
	fore_l.add_child(mesh(capsule(0.08 * t, 0.18), limb, Vector3(0, -0.12, 0)))
	fore_r.add_child(mesh(capsule(0.08 * t, 0.18), limb, Vector3(0, -0.12, 0)))
	fore_l.add_child(mesh(sphere(0.095 * t), hand, Vector3(0, -0.28, 0)))
	fore_r.add_child(mesh(sphere(0.095 * t), hand, Vector3(0, -0.28, 0)))
	leg_l.add_child(mesh(capsule(0.11 * t, 0.22), body, Vector3(0, -0.18, 0)))
	leg_r.add_child(mesh(capsule(0.11 * t, 0.22), body, Vector3(0, -0.18, 0)))
	shin_l.add_child(mesh(capsule(0.1 * t, 0.2), limb, Vector3(0, -0.14, 0)))
	shin_r.add_child(mesh(capsule(0.1 * t, 0.2), limb, Vector3(0, -0.14, 0)))
	shin_l.add_child(mesh(rbox(0.22 * t, 0.14, 0.34, 0.06), boot, Vector3(0, -0.33, 0.06)))
	shin_r.add_child(mesh(rbox(0.22 * t, 0.14, 0.34, 0.06), boot, Vector3(0, -0.33, 0.06)))


## Cartoon eyes with pupils (blink by scaling).
func add_eyes(parent: Node3D, y: float, z: float, spread: float, size := 0.075, angry := 0.0) -> void:
	var white := P("#ffffff", {"rough": 0.2})
	var black := P("#151515", {"rough": 0.15})
	for s in [-1, 1]:
		var e := Node3D.new()
		e.position = Vector3(s * spread, y, z)
		e.add_child(mesh(sphere(size, 16, 12), white, Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.15, 0.6)))
		e.add_child(mesh(sphere(size * 0.55, 12, 10), black, Vector3(0, 0, size * 0.45)))
		e.add_child(mesh(sphere(size * 0.16, 8, 6), white, Vector3(size * 0.18, size * 0.22, size * 0.72)))
		if angry:
			e.add_child(mesh(rbox(size * 2.2, size * 0.45, size * 0.5, 0.02), black, Vector3(0, size * 1.35, size * 0.2), Vector3(0, 0, -s * angry)))
		parent.add_child(e)
		eyes.append(e)


## Team colors: a bright sash around the chest and a little pennant on the head. "" removes it.
func set_team(color: String) -> void:
	if _team_band:
		_team_band.queue_free()
		for o in _team_extra:
			(o as Node).queue_free()
		_team_band = null
		_team_extra = []
	if color == "":
		return
	var box := AABB()
	var first := true
	for c in torso.get_children():
		if c is MeshInstance3D:
			var bb: AABB = (c as MeshInstance3D).transform * (c as MeshInstance3D).mesh.get_aabb()
			box = bb if first else box.merge(bb)
			first = false
	var size := box.size
	var g := Node3D.new()
	var mat := P(color, {"rough": 0.3, "emissive": color, "emissive_intensity": 0.6})
	var band := mesh(Geo.torus(0.5, 0.1, 10, 28), mat, Vector3(0, 0.3, 0), Vector3(PI / 2, 0, 0), Vector3(maxf(0.3, size.x * 0.56 + 0.04), maxf(0.25, size.z * 0.56 + 0.04), 1))
	band.set_meta("no_outline", true)
	g.add_child(band)
	var pole := mesh(Geo.cylinder(0.018, 0.018, 0.6, 6), Mats.metal("#dddddd"), Vector3(0.14, 0.64, -0.12))
	var flag := mesh(Geo.box(0.03, 0.22, 0.34), mat, Vector3(0.14, 0.82, -0.3))
	pole.set_meta("no_outline", true)
	flag.set_meta("no_outline", true)
	head.add_child(pole)
	head.add_child(flag)
	torso.add_child(g)
	_team_band = g
	_team_extra = [pole, flag]


func set_weapon(model: Node3D) -> void:
	for c in weapon_socket.get_children():
		c.queue_free()
	if model:
		model.transform = Transform3D(U.euler(PI / 2, PI, 0).scaled_local(Vector3.ONE * 0.95), Vector3(0, -0.02, 0.06))
		weapon_socket.add_child(model)


## Inverted-hull outline (accessibility option, and teammates in team modes).
func set_outline(on: bool, color: String) -> void:
	_outline_on = on
	if on and outline_meshes.is_empty():
		_outline_mat = StandardMaterial3D.new()
		_outline_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_outline_mat.cull_mode = BaseMaterial3D.CULL_FRONT
		_outline_mat.grow = true
		_outline_mat.grow_amount = 0.025
		for m: MeshInstance3D in _meshes():
			if m.has_meta("no_outline") or (m.get_parent() and m.get_parent().has_meta("no_outline")):
				continue
			var o := MeshInstance3D.new()
			o.mesh = m.mesh
			o.material_override = _outline_mat
			o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			o.set_meta("no_outline", true)
			m.add_child(o)
			outline_meshes.append(o)
	if _outline_mat:
		_outline_mat.albedo_color = U.col(color)
	for o in outline_meshes:
		o.visible = on and not _cloak_applied


func set_shimmer(on: bool, t: float) -> void:
	if shimmer_mats.is_empty():
		var clones := {}
		for m: MeshInstance3D in _meshes():
			if m.has_meta("pre_cloak") or outline_meshes.has(m):
				continue
			var mat = m.material_override
			if mat is StandardMaterial3D:
				# per-rig material clones so the shimmer doesn't affect other toys sharing materials
				if not clones.has(mat):
					var mm: StandardMaterial3D = mat.duplicate()
					mm.set_meta("base_e", mm.emission if mm.emission_enabled else Color.BLACK)
					mm.set_meta("base_ei", mm.emission_energy_multiplier if mm.emission_enabled else 0.0)
					mm.emission_enabled = true
					if not mat.emission_enabled:
						mm.emission = Color.BLACK
					clones[mat] = mm
					shimmer_mats.append(mm)
				m.material_override = clones[mat]
				if m == visor:
					_visor_base = (clones[mat] as StandardMaterial3D).emission_energy_multiplier
	for m: StandardMaterial3D in shimmer_mats:
		if on:
			m.emission = U.col("#9fe8ff")
			m.emission_energy_multiplier = 0.35 + sin(t * 18) * 0.25
		elif m.emission_energy_multiplier != m.get_meta("base_ei") or m.emission != m.get_meta("base_e"):
			m.emission = m.get_meta("base_e")
			m.emission_energy_multiplier = m.get_meta("base_ei")


static func _from_down(d: Vector3) -> Basis:
	return U.from_up(-d)


func update(dt: float, s: Dictionary, time: float) -> void:
	var moving := clampf(s.speed / 6.0, 0, 1.4)
	phase += dt * (3 + s.speed * 1.5)
	var ph := phase
	smooth_crouch = U.damp(smooth_crouch, s.crouch, 12, dt)
	var c := smooth_crouch
	# legs
	var swing: float = sin(ph) * 0.75 * moving if s.grounded else 0.0
	var air := 0.0 if s.grounded else 1.0
	leg_l.rotation = Vector3(swing + air * -0.5 - c * 1.1, 0, 0)
	leg_r.rotation = Vector3(-swing + air * 0.3 - c * 1.1, 0, 0)
	shin_l.rotation = Vector3((maxf(0, -sin(ph)) * 0.9 * moving if s.grounded else 0.8) + c * 1.9, 0, 0)
	shin_r.rotation = Vector3((maxf(0, sin(ph)) * 0.9 * moving if s.grounded else 0.4) + c * 1.9, 0, 0)
	# body bob + lean
	var bob: float = absf(sin(ph)) * 0.06 * moving if s.grounded else 0.0
	hips.position.y = 0.78 - c * 0.36 + bob + (-0.3 if s.sliding else 0.0)
	smooth_lean = U.damp(smooth_lean, clampf(s.speed * 0.03, 0, 0.25) + (0.35 if s.dashing else 0.0) + (-0.5 if s.sliding else 0.0), 8, dt)
	torso.rotation = Vector3(smooth_lean + s.hit * -0.35 + c * 0.25, sin(ph) * 0.12 * moving, s.hit * sin(time * 40) * 0.08)
	# head follows aim pitch
	var neck_x: float = clampf(-s.aimPitch, -0.6, 0.6) * 0.6 - smooth_lean * 0.6
	var neck_y := neck.rotation.y
	# arms: right holds the weapon at the aim, left reaches for the front grip; reload pulls the left hand to the gun
	var ap: float = clampf(s.aimPitch, -0.9, 0.9) - smooth_lean * 0.6 + s.fireKick * 0.12
	var cp := cos(ap)
	var sp := sin(ap)
	var dir_r := Vector3(-0.12 * cp, sp, cp).normalized()
	arm_r.basis = _from_down(dir_r)
	fore_r.rotation = Vector3(-0.15, 0, 0)
	# left hand target: ahead of the right hand along the aim (torso space)
	var tgt := Vector3(0.36, 0.48, 0) + dir_r * 0.55 + (Vector3(-0.02, 0, 0) + dir_r * 0.32)
	if s.reload > 0:
		var r := sin(s.reload * PI)
		tgt += Vector3(-0.05, -0.18 * r, -0.25 * r)
	arm_l.basis = _from_down((tgt - Vector3(-0.36, 0.48, 0)).normalized())
	fore_l.rotation = Vector3.ZERO
	# personality idles
	idle_t += dt
	if tail:
		tail.rotation.y = sin(time * 3 + phase * 0.5) * (0.3 + moving * 0.3)
	if antenna:
		antenna.rotation.z = sin(time * 6) * 0.25 + sin(ph) * 0.2 * moving
	if cape:
		cape.rotation.x = 0.15 + moving * 0.45 + air * 0.4 + sin(time * 4) * 0.05
	if visor:
		var vm = visor.material_override
		if vm is StandardMaterial3D and not _cloak_applied:
			(vm as StandardMaterial3D).emission_energy_multiplier = 1.8 + sin(time * 5 + phase) * 0.6 + s.hit * 3
	if moving < 0.1 and s.grounded and s.reload == 0:
		# idle personality: little look-arounds and bounces
		var k := sin(idle_t * 0.9)
		neck_y = k * 0.35
		hips.position.y += sin(idle_t * 2.2) * 0.012
		if def.id == "princessPanic":
			torso.rotation.y = sin(idle_t * 1.7) * 0.25
		if def.id == "rexRampage":
			neck_x += sin(idle_t * 3) * 0.08
		if def.id == "boltBuddy":
			head.rotation.y = sin(idle_t * 0.7) * 0.6
	else:
		neck_y = U.damp(neck_y, 0, 6, dt)
		head.rotation.y = U.damp(head.rotation.y, 0, 6, dt)
	neck.rotation = Vector3(neck_x, neck_y, 0)
	# blinking
	blink_t -= dt
	var blink := 1.0
	if blink_t < 0.12:
		blink = absf(blink_t - 0.06) / 0.06
	if blink_t <= 0:
		blink_t = 2 + randf() * 3
	for e in eyes:
		(e as Node3D).scale.y = maxf(0.1, blink) * (1 - s.hit * 0.5)
	scale = Vector3.ONE * maxf(0.001, scale_in)


# ------------------------------------------------------------------------ character builders
func _build_captainClick() -> void:
	var olive := P("#5b7a3a", {"rough": 0.45})
	var dark := P("#3e5527", {"rough": 0.45})
	var tan := P("#c9b27c", {"rough": 0.5})
	torso.add_child(mesh(rbox(0.6, 0.62, 0.38, 0.12), olive, Vector3(0, 0.27, 0)))
	torso.add_child(mesh(rbox(0.62, 0.1, 0.4, 0.04), dark, Vector3(0, 0.0, 0)))
	torso.add_child(mesh(rbox(0.36, 0.42, 0.18, 0.08), dark, Vector3(0, 0.3, -0.26)))  # backpack
	torso.add_child(mesh(rbox(0.12, 0.08, 0.06, 0.02), tan, Vector3(-0.15, 0.4, 0.2)))
	torso.add_child(mesh(rbox(0.12, 0.08, 0.06, 0.02), tan, Vector3(0.15, 0.4, 0.2)))
	head.add_child(mesh(sphere(0.25), P(SKIN, {"rough": 0.5}), Vector3(0, 0.2, 0)))
	# helmet
	head.add_child(mesh(Geo.sphere(0.29, 20, 12, 0, TAU, 0, PI / 2), olive, Vector3(0, 0.26, 0)))
	head.add_child(mesh(Geo.cylinder(0.34, 0.34, 0.04, 24), olive, Vector3(0, 0.26, 0.02)))
	head.add_child(mesh(rbox(0.3, 0.03, 0.02, 0.01), dark, Vector3(0, 0.12, 0.23), Vector3(0.2, 0, 0)))
	add_eyes(head, 0.2, 0.2, 0.09, 0.06, 0.25)
	limbs(olive, olive, P(SKIN, {"rough": 0.5}), dark)


func _build_rexRampage() -> void:
	var g := P("#3fae49", {"rough": 0.35})
	var belly := P("#f4c27a", {"rough": 0.4})
	var white := P("#ffffff", {"rough": 0.3})
	torso.add_child(mesh(capsule(0.3, 0.3), g, Vector3(0, 0.28, 0), Vector3.ZERO, Vector3(1.05, 1, 0.9)))
	torso.add_child(mesh(capsule(0.2, 0.24), belly, Vector3(0, 0.26, 0.14), Vector3.ZERO, Vector3(1, 1, 0.6)))
	# spikes along the back
	for i in 4:
		torso.add_child(mesh(Geo.cone(0.07, 0.16, 4), P("#f77f00"), Vector3(0, 0.5 - i * 0.14, -0.27), Vector3(-0.6, 0, 0)))
	# dino head: big snout
	head.add_child(mesh(rbox(0.46, 0.38, 0.46, 0.16), g, Vector3(0, 0.22, 0.04)))
	head.add_child(mesh(rbox(0.38, 0.2, 0.36, 0.08), g, Vector3(0, 0.12, 0.32)))
	head.add_child(mesh(rbox(0.36, 0.1, 0.32, 0.04), P("#c1121f"), Vector3(0, 0.04, 0.3)))
	for i in 4:
		for s in [-1, 1]:
			head.add_child(mesh(Geo.cone(0.03, 0.07, 6), white, Vector3(s * (0.06 + i * 0.04), 0.03, 0.47 - i * 0.05), Vector3(PI, 0, 0)))
	head.add_child(mesh(sphere(0.03), P("#1b4332"), Vector3(-0.08, 0.2, 0.5)))
	head.add_child(mesh(sphere(0.03), P("#1b4332"), Vector3(0.08, 0.2, 0.5)))
	add_eyes(head, 0.34, 0.2, 0.14, 0.075, 0.35)
	# tail
	tail = Node3D.new()
	tail.position = Vector3(0, -0.02, -0.18)
	var parent: Node3D = tail
	for i in 4:
		var seg := Node3D.new()
		seg.position = Vector3(0, -0.03, 0.0 if i == 0 else -0.2)
		seg.add_child(mesh(sphere(0.17 - i * 0.035), g, Vector3(0, 0, -0.1)))
		parent.add_child(seg)
		parent = seg
	hips.add_child(tail)
	limbs(g, g, g, P("#2d6a4f"), {"thick": 1.15})


func _build_boltBuddy() -> void:
	var silver := P("#b8c4d6", {"rough": 0.25, "metal": 0.4})
	var blue := P("#3a86ff", {"rough": 0.3})
	torso.add_child(mesh(rbox(0.56, 0.58, 0.36, 0.08), silver, Vector3(0, 0.27, 0)))
	torso.add_child(mesh(rbox(0.3, 0.22, 0.04, 0.03), blue, Vector3(0, 0.32, 0.18)))
	var lights := ["#ff006e", "#ffbe0b", "#06d6a0"]
	for i in 3:
		torso.add_child(mesh(sphere(0.03), Mats.glow(lights[i], 2), Vector3(-0.08 + i * 0.08, 0.32, 0.21)))
	head.add_child(mesh(rbox(0.44, 0.38, 0.38, 0.1), silver, Vector3(0, 0.22, 0)))
	visor = mesh(rbox(0.36, 0.12, 0.04, 0.03), Mats.glow("#5af7ff", 2), Vector3(0, 0.24, 0.19))
	head.add_child(visor)
	head.add_child(mesh(rbox(0.1, 0.18, 0.1, 0.03), blue, Vector3(-0.25, 0.22, 0)))
	head.add_child(mesh(rbox(0.1, 0.18, 0.1, 0.03), blue, Vector3(0.25, 0.22, 0)))
	antenna = Node3D.new()
	antenna.position = Vector3(0, 0.41, 0)
	antenna.add_child(mesh(Geo.cylinder(0.015, 0.015, 0.22, 6), Mats.metal("#cccccc"), Vector3(0, 0.11, 0)))
	antenna.add_child(mesh(sphere(0.05), Mats.glow("#ffbe0b", 3), Vector3(0, 0.24, 0)))
	head.add_child(antenna)
	limbs(silver, blue, silver, blue, {"thick": 0.95})


func _build_princessPanic() -> void:
	var pink := P("#ff70a6", {"rough": 0.3})
	var purple := P("#c77dff", {"rough": 0.3})
	var gold := P("#ffd670", {"rough": 0.2, "metal": 0.5})
	torso.add_child(mesh(rbox(0.46, 0.5, 0.32, 0.12), pink, Vector3(0, 0.3, 0)))
	var skirt := purple.duplicate() as StandardMaterial3D
	skirt.cull_mode = BaseMaterial3D.CULL_DISABLED
	torso.add_child(mesh(Geo.cone(0.42, 0.5, 20, 1, true), skirt, Vector3(0, -0.02, 0), Vector3(PI, 0, 0)))
	torso.add_child(mesh(sphere(0.06), gold, Vector3(0, 0.38, 0.17)))
	head.add_child(mesh(sphere(0.24), P(SKIN, {"rough": 0.5}), Vector3(0, 0.2, 0)))
	head.add_child(mesh(sphere(0.26, 18, 14), P("#7b2cbf", {"rough": 0.5}), Vector3(0, 0.25, -0.05), Vector3.ZERO, Vector3(1, 0.95, 1)))
	head.add_child(mesh(capsule(0.08, 0.3), P("#7b2cbf", {"rough": 0.5}), Vector3(0, 0.1, -0.3), Vector3(0.5, 0, 0)))
	# crown
	var crown := Node3D.new()
	crown.position = Vector3(0, 0.44, 0)
	var band := gold.duplicate() as StandardMaterial3D
	band.cull_mode = BaseMaterial3D.CULL_DISABLED
	crown.add_child(mesh(Geo.cylinder(0.15, 0.16, 0.08, 16, 1, true), band))
	for i in 5:
		var a := float(i) / 5 * TAU
		crown.add_child(mesh(Geo.cone(0.035, 0.1, 6), gold, Vector3(cos(a) * 0.15, 0.08, sin(a) * 0.15)))
	crown.add_child(mesh(sphere(0.035), Mats.glow("#ff006e", 1.5), Vector3(0, 0.04, 0.16)))
	head.add_child(crown)
	add_eyes(head, 0.2, 0.2, 0.085, 0.065)
	# cape
	var cape_mat := Mats.std("#9d4edd", 0.8)
	cape_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cape = mesh(Geo.plane(0.62, 0.9, 1, 4).translate(0, -0.45, 0), cape_mat, Vector3(0, 0.55, -0.2))
	torso.add_child(cape)
	limbs(pink, P(SKIN, {"rough": 0.5}), P(SKIN, {"rough": 0.5}), purple, {"thick": 0.85})


func _build_turboTim() -> void:
	var red := P("#e63946", {"rough": 0.2, "clearcoat": 1.0})
	var white := P("#ffffff", {"rough": 0.25})
	var navy := P("#1d3557", {"rough": 0.3})
	torso.add_child(mesh(rbox(0.54, 0.6, 0.36, 0.12), red, Vector3(0, 0.27, 0)))
	torso.add_child(mesh(rbox(0.12, 0.62, 0.38, 0.04), white, Vector3(0, 0.27, 0)))
	# race number
	var tex := Tex.make("race7", 64, 64, func(ci: CanvasItem):
		ci.draw_circle(Vector2(32, 32), 30, Color.WHITE)
		Tex.text(ci, Tex.FONT_BOLD, "7", 32, 35, 44, Color("#1d3557"))
	, {"placeholder": Color(1, 1, 1, 0)})
	var num := Mats.textured(tex, 0.5)
	num.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torso.add_child(mesh(Geo.circle(0.12, 20), num, Vector3(0.15, 0.36, 0.185)))
	# helmet with visor
	head.add_child(mesh(sphere(0.28), red, Vector3(0, 0.22, 0)))
	head.add_child(mesh(rbox(0.1, 0.06, 0.52, 0.02), white, Vector3(0, 0.46, 0)))
	var vm := StandardMaterial3D.new()
	vm.albedo_color = U.col("#111827")
	vm.roughness = 0.05
	vm.clearcoat_enabled = true
	vm.clearcoat = 1
	vm.metallic = 0.3
	vm.emission_enabled = true
	vm.emission = U.col("#3a0ca3")
	vm.emission_energy_multiplier = 0.6
	vm.cull_mode = BaseMaterial3D.CULL_DISABLED
	visor = mesh(Geo.sphere(0.26, 20, 10, -0.9, 1.8, 1.0, 0.75), vm, Vector3(0, 0.22, 0.05))
	head.add_child(visor)
	# spoiler on the back
	torso.add_child(mesh(rbox(0.6, 0.04, 0.14, 0.02), navy, Vector3(0, 0.6, -0.3)))
	torso.add_child(mesh(rbox(0.04, 0.16, 0.06, 0.01), navy, Vector3(-0.2, 0.52, -0.26)))
	torso.add_child(mesh(rbox(0.04, 0.16, 0.06, 0.01), navy, Vector3(0.2, 0.52, -0.26)))
	limbs(red, white, white, navy)


func _build_mechaMax() -> void:
	var grey := P("#4a4e69", {"rough": 0.35, "metal": 0.3})
	var yellow := P("#ffb703", {"rough": 0.3})
	var dark := P("#22223b", {"rough": 0.4})
	torso.add_child(mesh(rbox(0.7, 0.62, 0.46, 0.1), grey, Vector3(0, 0.27, 0)))
	torso.add_child(mesh(rbox(0.4, 0.2, 0.06, 0.04), yellow, Vector3(0, 0.32, 0.23)))
	# huge shoulder pads
	arm_l.add_child(mesh(rbox(0.32, 0.22, 0.4, 0.08), yellow, Vector3(-0.06, 0.04, 0)))
	arm_r.add_child(mesh(rbox(0.32, 0.22, 0.4, 0.08), yellow, Vector3(0.06, 0.04, 0)))
	head.add_child(mesh(rbox(0.42, 0.34, 0.4, 0.08), grey, Vector3(0, 0.2, 0)))
	visor = mesh(rbox(0.34, 0.06, 0.04, 0.02), Mats.glow("#ff4d6d", 2.4), Vector3(0, 0.22, 0.2))
	head.add_child(visor)
	head.add_child(mesh(rbox(0.46, 0.06, 0.44, 0.02), yellow, Vector3(0, 0.39, 0)))
	torso.add_child(mesh(Geo.cylinder(0.08, 0.08, 0.4, 10), dark, Vector3(-0.18, 0.4, -0.3), Vector3(0.2, 0, 0)))
	torso.add_child(mesh(Geo.cylinder(0.08, 0.08, 0.4, 10), dark, Vector3(0.18, 0.4, -0.3), Vector3(0.2, 0, 0)))
	limbs(grey, dark, grey, dark, {"thick": 1.3})


func _build_blockhead() -> void:
	var red := P("#d6342c", {"rough": 0.3})
	var yellow := P("#f2c12e", {"rough": 0.3})
	var blue := P("#1f6fd1", {"rough": 0.3})
	torso.add_child(mesh(rbox(0.6, 0.6, 0.4, 0.04), blue, Vector3(0, 0.27, 0)))
	for x in [-0.15, 0.15]:
		for z in [-0.1, 0.1]:
			torso.add_child(mesh(Geo.cylinder(0.07, 0.07, 0.06, 12), blue, Vector3(x, 0.6, z)))
	# brick head with studs and a visor slot
	head.add_child(mesh(rbox(0.46, 0.4, 0.42, 0.03), red, Vector3(0, 0.22, 0)))
	for x in [-0.11, 0.11]:
		for z in [-0.1, 0.1]:
			head.add_child(mesh(Geo.cylinder(0.07, 0.07, 0.07, 12), red, Vector3(x, 0.455, z)))
	head.add_child(mesh(rbox(0.36, 0.07, 0.04, 0.01), P("#111111"), Vector3(0, 0.24, 0.21)))
	add_eyes(head, 0.24, 0.205, 0.09, 0.04)
	# brick shield on left arm
	var shield := mesh(rbox(0.08, 0.42, 0.32, 0.02), yellow, Vector3(-0.12, -0.18, 0.05))
	fore_l.add_child(shield)
	for y in [-0.08, 0.08]:
		shield.add_child(mesh(Geo.cylinder(0.05, 0.05, 0.05, 10), yellow, Vector3(-0.06, y, 0), Vector3(0, 0, PI / 2)))
	limbs(red, yellow, yellow, red, {"thick": 1.1})


func _build_player() -> void:
	_build_captainClick()


# ------------------------------------------------------------------------ extras: the newcomers aren't just repaints
func _extra_sergeantSnap() -> void:
	# sunglasses + a chevron patch
	var black := P("#111111", {"rough": 0.1, "clearcoat": 1.0})
	for s in [-1, 1]:
		head.add_child(mesh(rbox(0.13, 0.07, 0.03, 0.02), black, Vector3(s * 0.09, 0.2, 0.25)))
	head.add_child(mesh(rbox(0.06, 0.02, 0.02, 0.005), black, Vector3(0, 0.21, 0.25)))
	torso.add_child(mesh(Geo.cone(0.06, 0.06, 3), P("#ffd23f"), Vector3(0.17, 0.42, 0.2), Vector3(PI / 2, 0, 0)))


func _extra_dinaMite() -> void:
	# fuse sticking out of the head
	head.add_child(mesh(Geo.cylinder(0.015, 0.015, 0.18, 6), P("#5a3e2b"), Vector3(0, 0.5, -0.05), Vector3(-0.4, 0, 0)))
	head.add_child(mesh(sphere(0.035), Mats.glow("#ffb703", 3), Vector3(0, 0.6, -0.09)))


func _extra_sparky() -> void:
	# lightning bolt on the chest
	var bolt := PackedVector2Array([Vector2(0.02, 0.09), Vector2(-0.05, -0.005), Vector2(0.0, -0.005), Vector2(-0.02, -0.09), Vector2(0.05, 0.015), Vector2(0.0, 0.015)])
	torso.add_child(mesh(Geo.shape(bolt), Mats.glow("#3a86ff", 2), Vector3(0, 0.18, 0.185)))


func _extra_duchessDazzle() -> void:
	# monocle
	head.add_child(mesh(Geo.torus(0.05, 0.008, 6, 16), P("#ffd670", {"metal": 0.6}), Vector3(0.085, 0.2, 0.23)))


func _extra_nitroNina() -> void:
	# twin exhaust pipes on the back
	for x in [-0.12, 0.12]:
		torso.add_child(mesh(Geo.cylinder(0.04, 0.05, 0.22, 10), Mats.metal("#c0c6d0", 0.3), Vector3(x, 0.15, -0.24), Vector3(0.3, 0, 0)))


func _extra_gearboxGus() -> void:
	# chunky gear on the chest
	var gear := Node3D.new()
	gear.position = Vector3(0, 0.32, 0.26)
	var m := P("#e9ecef", {"metal": 0.5})
	gear.add_child(mesh(Geo.cylinder(0.08, 0.08, 0.03, 14), m, Vector3.ZERO, Vector3(PI / 2, 0, 0)))
	for i in 8:
		var a := float(i) / 8 * TAU
		gear.add_child(mesh(rbox(0.04, 0.04, 0.03, 0.005), m, Vector3(cos(a) * 0.09, sin(a) * 0.09, 0)))
	torso.add_child(gear)


func _extra_brickette() -> void:
	# bow on top of the brick head
	var pink := P("#e64980")
	for s in [-1, 1]:
		head.add_child(mesh(Geo.cone(0.08, 0.14, 4), pink, Vector3(s * 0.09, 0.53, 0), Vector3(0, 0, s * PI / 2)))
	head.add_child(mesh(sphere(0.045), pink, Vector3(0, 0.53, 0)))

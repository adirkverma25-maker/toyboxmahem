class_name Viewmodel
extends Node3D
## First-person toy hands + weapon (port of src/weapons/Viewmodel.ts). Lives in its own World3D (rendered by
## the viewmodel SubViewport over the game view) so it never clips into walls. The vm camera sits at the
## origin looking down -Z, so everything here is in camera space.
## ctx: {ws, ads, sprint, speed, grounded, crouch, mouseDX, mouseDY, now, reducedMotion, infinite, sliding, charge, cloaked}

var holder := Node3D.new()
var models := {}
var current: WeaponModel = null
var current_id := ""
var hand_r: Node3D
var hand_l: Node3D
var flash: MeshInstance3D
var flash_mat: StandardMaterial3D
var flash_t := 0.0
var equip_t := 1.0
var kick_z := [0.0, 0.0]
var kick_rot := [0.0, 0.0]
var kick_roll := [0.0, 0.0]
var land := [0.0, 0.0]
var sway_x := 0.0
var sway_y := 0.0
var bob_phase := 0.0
var bob_amt := 0.0
var sprint_t := 0.0
var inspect_t := 0.0
var fire_anim := 0.0
var spin_speed := 0.0
var bolt_t := 0.0
var reload_vis := 0.0
var time := 0.0
var jack_t := 0.0
## melee (sword / spear): the model, which one it is, the swing timer and its length
var melee_node := Node3D.new()
var melee_kind := ""
var melee_t := 0.0
var melee_len := 0.5
var melee_hold := false
var cloak_mat: StandardMaterial3D
var cloak_on := false
var scope_hidden := false
var optic: Node3D = null
## real-gun reloads: last reload fraction (to catch beats), whether the old mag was thrown yet
var _prev_rf := 0.0
var _dropped := false
## spent casings in flight [node, vel, spin, life] and dropped magazines [node, vel, spin, life]
var _casings := {}
var _flying: Array = []
var hand_shell: Node3D = null
var speedloader: Node3D = null
## revolver: how far the muzzle is tipped up to dump the empties; bolt action: last cycle point (for the casing)
var _rev_tip := 0.0
var _prev_bolt_k := 0.0


## semi-implicit damped spring [x, v], sub-stepped for frame-rate independence
static func spring_step(s: Array, k: float, c: float, dt: float) -> void:
	var n := maxi(1, ceili(dt / (1.0 / 240)))
	var h := dt / n
	for i in n:
		s[1] += (-k * s[0] - c * s[1]) * h
		s[0] += s[1] * h


static func star_texture() -> Texture2D:
	return Tex.make("vmstar", 128, 128, func(ci: CanvasItem):
		var o := Vector2(64, 64)
		var grad := func(r: float) -> Color:
			var t := r / 60.0
			if t < 0.3:
				return Color(1, 1, 1, 1).lerp(Color(1, 240 / 255.0, 200 / 255.0, 0.9), t / 0.3)
			return Color(1, 240 / 255.0, 200 / 255.0, 0.9).lerp(Color(1, 200 / 255.0, 120 / 255.0, 0), (t - 0.3) / 0.7)
		var pts := []
		for i in 16:
			var a := float(i) / 16 * TAU
			var r := 22.0 if i % 2 else 62.0
			pts.append([o + Vector2(cos(a), sin(a)) * r, r])
		for i in 16:
			var p0: Array = pts[i]
			var p1: Array = pts[(i + 1) % 16]
			ci.draw_polygon(PackedVector2Array([o, p0[0], p1[0]]), PackedColorArray([grad.call(0.0), grad.call(p0[1]), grad.call(p1[1])]))
	, {"placeholder": Color(1, 1, 1, 0)})


func _init(toy_color := "#1fb5ad", cuff_color := "#ff8c1a") -> void:
	name = "Viewmodel"
	add_child(holder)
	hand_r = _make_hand(toy_color, cuff_color, 1)
	hand_l = _make_hand(toy_color, cuff_color, -1)
	flash_mat = StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	flash_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	flash_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flash_mat.albedo_texture = star_texture()
	flash_mat.albedo_color = U.col("#ffd9a0")
	flash_mat.render_priority = 10
	flash = Geo.plane(0.32, 0.32).mesh_instance(flash_mat, Vector3.ZERO, Basis(), false)
	flash.visible = false
	melee_node.visible = false
	add_child(melee_node)
	cloak_mat = StandardMaterial3D.new()
	cloak_mat.albedo_color = Color(U.col("#d8ecff"), 0.22)
	cloak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloak_mat.roughness = 0.05
	cloak_mat.metallic = 0.2
	cloak_mat.clearcoat_enabled = true
	cloak_mat.clearcoat = 1
	cloak_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	cloak_mat.emission_enabled = true
	cloak_mat.emission = U.col("#5fb3ff")
	cloak_mat.emission_energy_multiplier = 0.25


## Melee swing (kind: sword / spear, swing: seconds).
func melee(kind: String, swing: float) -> void:
	_ensure_melee(kind)
	melee_len = swing
	melee_t = swing
	inspect_t = 0


## Sword / spear in hand (true) or put away (false).
func hold_melee(kind: String, on: bool) -> void:
	if on:
		_ensure_melee(kind)
	melee_hold = on


func _ensure_melee(kind: String) -> void:
	if kind == melee_kind:
		return
	for c in melee_node.get_children():
		c.queue_free()
	var m := MeleeModel.build(kind, true)
	m.scale = Vector3.ONE * (0.85 if kind == "spear" else 1.0)
	melee_node.add_child(m)
	melee_kind = kind


func _part(g: Geo, mat: Material, p: Vector3, r := Vector3.ZERO) -> MeshInstance3D:
	var o := MeshInstance3D.new()
	o.mesh = g.to_mesh()
	o.material_override = mat
	o.transform = Transform3D(U.euler(r.x, r.y, r.z), p)
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return o


func _make_hand(color: String, cuff: String, side: float) -> Node3D:
	var g := Node3D.new()
	var skin := Mats.plastic(color, {"rough": 0.35})
	var cuff_mat := Mats.plastic(cuff, {"rough": 0.35})
	var glv := Mats.plastic("#fff4e6", {"rough": 0.45})
	# mitten-style toy hand wrapped around the grip
	g.add_child(_part(Geo.rounded_box(0.085, 0.1, 0.075, 3, 0.035), glv, Vector3(side * 0.012, -0.01, 0)))
	g.add_child(_part(Geo.capsule(0.03, 0.05, 4, 10), glv, Vector3(-side * 0.025, -0.02, -0.035), Vector3(0, 0, PI / 2)))
	g.add_child(_part(Geo.capsule(0.018, 0.04, 4, 8), glv, Vector3(side * 0.045, 0.03, -0.02), Vector3(0.6, 0, side * 0.4)))
	g.add_child(_part(Geo.cylinder(0.05, 0.052, 0.04, 16), cuff_mat, Vector3(side * 0.01, -0.05, 0.06), Vector3(PI / 2 - 0.5, 0, 0)))
	g.add_child(_part(Geo.capsule(0.045, 0.42, 4, 12), skin, Vector3(side * 0.06, -0.15, 0.25), Vector3(PI / 2 - 0.55, 0, side * -0.25)))
	# seam line + joint dot on the toy arm
	g.add_child(_part(Geo.sphere(0.02, 10, 8), cuff_mat, Vector3(side * 0.05, -0.07, 0.11)))
	return g


func _get_model(id: String) -> WeaponModel:
	if not models.has(id):
		models[id] = WeaponModel.build(id)
	return models[id]


## Mount (or remove) the small on-gun optic for the current weapon.
func set_optic(kind: String) -> void:
	if optic:
		optic.queue_free()
		optic = null
	if current and current.parts.has("scope"):
		(current.parts.scope as Node3D).visible = true
	if current == null or current_id == "" or (kind != "dot" and kind != "ring"):
		return
	if current.parts.has("scope"):
		(current.parts.scope as Node3D).visible = false  # a small optic replaces the long scope
	var c: Dictionary = Cfg.WEAPONS[current_id].colors
	optic = WeaponModel.build_optic(kind, -current.ads_offset.y, c.accent, c.main)
	optic.position.z = current.ads_offset.z * 0.5 - 0.02
	current.add_child(optic)
	_restore_cloak()


func _restore_cloak() -> void:
	if not cloak_on:
		return
	for mm in _meshes(self):
		if mm.has_meta("pre_cloak"):
			mm.material_override = mm.get_meta("pre_cloak")
			mm.remove_meta("pre_cloak")
	cloak_on = false  # re-applied next frame


func _meshes(n: Node, out: Array = []) -> Array:
	for c in n.get_children():
		if c is MeshInstance3D:
			out.append(c)
		_meshes(c, out)
	return out


func set_weapon(id: String, instant := false) -> void:
	if optic:
		optic.queue_free()
		optic = null
	_restore_cloak()
	if current:
		for n in [hand_r, hand_l, flash]:
			if n.get_parent():
				n.get_parent().remove_child(n)
		holder.remove_child(current)
	current = null
	current_id = id
	if hand_shell:
		hand_shell.queue_free()
		hand_shell = null
	if speedloader:
		speedloader.queue_free()
		speedloader = null
	_rev_tip = 0.0
	if id == "":
		return
	var m := _get_model(id)
	current = m
	holder.add_child(m)
	m.add_child(hand_r)
	m.add_child(hand_l)
	m.add_child(flash)
	hand_r.position = m.right_grip
	hand_l.position = m.left_grip
	hand_r.rotation = Vector3(0.25, 0, 0)
	hand_l.rotation = Vector3.ZERO
	flash.position = m.muzzle.position
	equip_t = 1.0 if instant else 0.0
	inspect_t = 0
	_reset_parts()


func _reset_parts() -> void:
	if current == null:
		return
	for k in current.parts:
		if current.rest.has(k):
			(current.parts[k] as Node3D).transform = current.rest[k]


func inspect() -> void:
	if equip_t >= 1 and reload_vis == 0:
		inspect_t = 2.4


func cancel_inspect() -> void:
	inspect_t = 0


func on_fire(id: String, ads: bool, reduced: bool) -> void:
	var cfg: Dictionary = Cfg.WEAPONS[id]
	var k := 0.55 if ads else 1.0
	var mot := 0.5 if reduced else 1.0
	kick_z[1] += cfg.kick.back * 28 * k * mot
	kick_rot[1] += cfg.kick.up * 32 * k * mot
	kick_roll[1] += U.rand(-1, 1) * cfg.kick.roll * 30 * mot
	flash_t = 0.045
	flash.visible = true
	var s := U.rand(0.8, 1.25) * (1.6 if id == "crayonCannon" or id == "bubbleBlaster" or id == "sizzler" else (0.8 if id == "rapidRascal" else 1.0))
	flash.basis = Basis(Vector3.BACK, randf() * PI).scaled_local(Vector3.ONE * s)
	flash_mat.albedo_color = U.col(cfg.colors.glow)
	fire_anim = 1
	inspect_t = 0
	if current == null:
		return
	var p := current.parts
	if p.has("gear"):
		p.gear.rotation.x -= 0.9
	if p.has("gear2"):
		p.gear2.rotation.x += 1.3
	if p.has("chamber") and id == "foamFury":
		p.chamber.rotation.z += PI / 3
	if p.has("wheel"):
		p.wheel.rotation.x += TAU / 5
	if current.real and current.eject and current.casing != "" and not current.bolt_action:
		_throw_casing(current.casing)
	if p.has("cylinder"):
		(p.cylinder as Node3D).rotation.z += TAU / 6
	if current.bolt_action:
		bolt_t = 1
	if id == "thunderspring":
		bolt_t = 1
	if id == "jackBlaster":
		jack_t = 1


func on_land(strength: float) -> void:
	land[1] -= strength * 1.6


func update(dt: float, c: Dictionary) -> void:
	time += dt
	_update_flying(dt)
	if current and current.bolt_action:
		bolt_t = maxf(0, bolt_t - dt * 1.8)
	var m := current
	if m == null:
		return
	var ws: WeaponState = c.ws
	var parts := m.parts
	var rm := 0.35 if c.reducedMotion else 1.0
	equip_t = minf(1, equip_t + dt / 0.32)
	sprint_t = U.damp(sprint_t, c.sprint, 10, dt)
	spring_step(kick_z, 260, 22, dt)
	spring_step(kick_rot, 240, 20, dt)
	spring_step(kick_roll, 200, 18, dt)
	spring_step(land, 120, 14, dt)
	# mouse sway (weapon lags behind the view)
	sway_x = U.damp(sway_x, clampf(-c.mouseDX * 0.0009, -0.06, 0.06) * rm, 10, dt)
	sway_y = U.damp(sway_y, clampf(c.mouseDY * 0.0009, -0.05, 0.05) * rm, 10, dt)
	# walk bob
	var moving: float = clampf(c.speed / 7.0, 0, 1.2) if c.grounded and not c.sliding else 0.0
	bob_amt = U.damp(bob_amt, moving, 8, dt)
	bob_phase += dt * (6 + c.speed * 1.1)
	var bob_scale: float = (1 - c.ads * 0.85) * rm
	var bx := sin(bob_phase) * 0.014 * bob_amt * bob_scale
	var by := -absf(cos(bob_phase)) * 0.012 * bob_amt * bob_scale
	var breathe: float = sin(time * 1.6) * 0.003 * (1 - c.ads)
	# hip / ads / sprint poses
	var hip := Vector3(0.15, -0.125, -0.34)
	var ao := m.ads_offset
	var ads_p := Vector3(0, ao.y * 0.5, -0.26 + ao.z * 0.5)
	var pos := hip.lerp(ads_p, U.smoothstep(0, 1, c.ads))
	var rx := 0.0
	var ry := 0.0
	var rz := 0.0
	# sprint
	pos.x += sprint_t * -0.04
	pos.y += sprint_t * -0.05
	rx += sprint_t * -0.35
	ry += sprint_t * 0.75
	rz += sprint_t * 0.2
	# crouch/slide tilt
	rz += 0.25 if c.sliding else 0.0
	# equip raise
	var e := 1 - U.smoothstep(0, 1, equip_t)
	pos.y -= e * 0.3
	rx -= e * 0.9
	# inspect: show off the left side, then flip
	if inspect_t > 0:
		inspect_t -= dt
		var t := 1 - inspect_t / 2.4
		var k := U.smoothstep(0, 0.2, t) * (1 - U.smoothstep(0.8, 1, t))
		var flip := U.smoothstep(0.4, 0.6, t)
		ry += k * (-0.9 + flip * 1.6)
		rz += k * 0.35
		rx += k * 0.2
		pos.x -= k * 0.08
		pos.z += k * 0.06
	# reload pose
	var rf := 0.0
	if ws and ws.reloading:
		rf = (0.5 if not current.real else ws.shell_t()) if ws.cfg.has("reloadPerShell") else ws.reload_progress()
	var reload_on := 1.0 if ws and ws.reloading else 0.0
	reload_vis = U.damp(reload_vis, reload_on, 10, dt)
	var rv := reload_vis
	if rv > 0.001:
		var tilt := [0.2, -0.1, 0.55]
		if m.real:
			# real guns roll the other way: magwell / loading port turned toward you, pulled in to the middle
			tilt = [0.28 + _rev_tip * 0.9, 0.32, -0.6 + _rev_tip * 0.3]
			pos.x -= 0.05 * rv
			pos.y += 0.035 * rv
		match current_id if not m.real else "":
			"crayonCannon": tilt = [0.5, -0.2, 0.2]
			"bubbleBlaster": tilt = [0.15, 0.3, -0.7]
			"thunderspring": tilt = [0.2, 0.25, 0.5]
		rx += tilt[0] * rv
		ry += tilt[1] * rv
		rz += tilt[2] * rv
		pos.y += 0.02 * rv
		pos.x -= 0.04 * rv
	# fire animation of moving parts
	fire_anim = maxf(0, fire_anim - dt * 8)
	_animate_parts(dt, c, rf, rv)
	var kz: float = kick_z[0] * rm
	var kr: float = kick_rot[0] * rm
	var hpos := Vector3(pos.x + bx + sway_x, pos.y + by + breathe + sway_y + land[0] * 0.04 * rm, pos.z + kz)
	var hrot := Vector3(rx + kr + sway_y * 2, ry + sway_x * 2.5, rz + kick_roll[0] * rm + sway_x * 1.5)
	holder.visible = not (scope_hidden and c.ads > 0.9)
	# melee: the sword / spear swings across the view while the blaster dips out of the way
	# melee: keyframed swing (wind-up, strike, follow-through, recover) from the ready pose
	if melee_t > 0 or melee_hold:
		var k := 0.0
		if melee_t > 0:
			melee_t = maxf(0, melee_t - dt)
			k = 1 - melee_t / melee_len
		melee_node.visible = true
		var pz := MeleeModel.pose(melee_kind, k)
		var bob := sin(time * 2.0) * 0.006 if melee_t <= 0 else 0.0
		melee_node.transform = Transform3D(pz.basis, pz.origin + Vector3(sway_x, bob + sway_y, 0))
		if not melee_hold:
			var out := U.smoothstep(0, 0.2, k) if k < 0.2 else 1 - U.smoothstep(0.75, 1, k)
			hpos.y -= out * 0.25
			hrot.z -= out * 0.4
	else:
		melee_node.visible = false
	if melee_hold:
		holder.visible = false  # melee instead of a blaster: no gun in view
	# bow: limbs, string and arrow follow the draw
	if current_id == "plungerBow":
		var draw := U.smoothstep(0, 1, c.charge)
		m.aim_string(draw)
		if parts.has("arrow") and ws:
			(parts.arrow as Node3D).visible = ws.mag > 0 and (ws.drawing() or c.now >= ws.next_fire - 0.25)
		hand_r.position = Vector3(0, -0.01, (parts.nock.position.z if parts.has("nock") else 0.15) + 0.03)
		hand_r.rotation = Vector3(0.25, 0, 0)
		hpos.z += draw * 0.03
		hpos.y += draw * 0.02
		if draw > 0.98:
			hpos.x += sin(time * 31) * 0.0012  # straining at full draw
	holder.transform = Transform3D(U.euler(hrot.x, hrot.y, hrot.z).scaled_local(Vector3.ONE * 0.43), hpos)
	# cloak: ghostly see-through arms and gun
	if c.cloaked != cloak_on:
		cloak_on = c.cloaked
		for mm: MeshInstance3D in _meshes(self):
			if mm == flash:
				continue
			if c.cloaked:
				if not mm.has_meta("pre_cloak"):
					mm.set_meta("pre_cloak", mm.material_override)
				mm.material_override = cloak_mat
			elif mm.has_meta("pre_cloak"):
				mm.material_override = mm.get_meta("pre_cloak")
				mm.remove_meta("pre_cloak")
	if cloak_on:
		cloak_mat.albedo_color.a = 0.18 + sin(time * 6) * 0.05
	# muzzle flash
	if flash_t > 0:
		flash_t -= dt
		if flash_t <= 0:
			flash.visible = false
	# left hand follows the magazine during reloads
	var lg := m.left_grip
	if m.real:
		_real_reload(ws, rf, rv, c)
	elif rv > 0.01 and parts.has("mag"):
		var target: Vector3 = (parts.mag as Node3D).position + Vector3(-0.02, -0.04, 0.02)
		hand_l.position = lg.lerp(target, rv)
		hand_l.rotation = Vector3(-0.4 * rv, 0, -0.3 * rv)
	else:
		hand_l.position = lg
		hand_l.rotation = Vector3.ZERO
	# ammo indicators
	if ws:
		m.update_ammo_indicator(ws.mag / ws.cfg.magSize, ws.mag)


func _animate_parts(dt: float, c: Dictionary, rf: float, rv: float) -> void:
	var m := current
	var p := m.parts
	var rest := m.rest
	var ws: WeaponState = c.ws
	var id := current_id
	var firing: bool = c.now - ws.last_shot < 0.12 if ws else false
	# continuous animations
	if p.has("gear") and id != "plasti9":
		p.gear.rotation.x += dt * (18.0 if firing else 0.4)
	if p.has("spin"):
		spin_speed = U.damp(spin_speed, 40.0 if firing else 0.0, 8.0 if firing else 2.0, dt)
		p.spin.rotation.z += spin_speed * dt
	if p.has("rings"):
		spin_speed = U.damp(spin_speed, 25.0 if firing else 2.0, 4, dt)
		var i := 0
		for r in (p.rings as Node3D).get_children():
			r.rotation.z += spin_speed * dt * (-1 if i % 2 else 1)
			i += 1
	if p.has("chamber") and id == "bubbleBlaster":
		p.chamber.rotation.y += dt * (9.0 if firing else 1.5)
		p.chamber.rotation.x += dt * 0.7
	if p.has("needle"):
		p.needle.rotation.x = -0.6 + (ws.mag / ws.cfg.magSize if ws else 1.0) * 1.2 + sin(time * 30) * 0.03 * fire_anim
	if p.has("leds"):
		var i := 0
		for l in (p.leds as Node3D).get_children():
			l.visible = sin(time * 40 + i * 2) > 0 if firing else sin(time * 3 + i) > -0.3
			i += 1
	if p.has("arcs"):
		var on: bool = firing or (ws != null and ws.mag < ws.cfg.magSize)
		p.arcs.visible = on and randf() > 0.3
		p.arcs.rotation.z = randf() * PI
	if p.has("core") and ws:
		var core: MeshInstance3D = p.core
		var mat = core.material_override
		var charging: bool = ws.mag < ws.cfg.magSize and c.now - ws.last_shot > (ws.cfg.energy.rechargeDelay if ws.cfg.has("energy") else 99.0)
		var frac: float = ws.mag / ws.cfg.magSize
		if mat is StandardMaterial3D:
			(mat as StandardMaterial3D).emission_energy_multiplier = U.damp(mat.emission_energy_multiplier, ((4.5 + sin(time * 14) * 1.2) if charging else 1 + frac * 2.5) * (0.4 if ws.lockout else 1.0), 10, dt)
		core.scale = Vector3.ONE * (0.85 + frac * 0.15)
	if p.has("pistons") and rest.has("pistons"):
		p.pistons.position.z = (rest.pistons as Transform3D).origin.z + fire_anim * 0.04
	if p.has("shroud"):
		p.shroud.rotation.z += dt * (12.0 if firing else 0.0)
	if p.has("charge") and rest.has("charge") and id == "plasti9" and not m.real:
		p.charge.position.z = (rest.charge as Transform3D).origin.z + fire_anim * 0.05
	if p.has("spring") and id == "thunderspring":
		# fire: spring twangs; reload: compress then lock
		bolt_t = maxf(0, bolt_t - dt * 1.8)
		var twang := sin(bolt_t * 30) * bolt_t * 0.25 if bolt_t > 0 else 0.0
		var comp := 1.0
		if rv > 0.01:
			comp = 1 - 0.45 * U.smoothstep(0.45, 0.62, rf) * (1 - U.smoothstep(0.92, 1, rf))
		p.spring.scale.z = comp + twang
		if p.has("bolt") and rest.has("bolt"):
			p.bolt.position.z = (rest.bolt as Transform3D).origin.z + ((1 - bolt_t) * 0.08 if bolt_t > 0.4 else bolt_t * 0.12) + U.smoothstep(0.55, 0.7, rf) * 0.08 * rv * (1 - U.smoothstep(0.85, 1, rf))
	if m.real:
		return  # real guns: _real_reload moves the mag, slide and hand
	# reload choreography for magazines
	if p.has("mag") and rest.has("mag"):
		var r: Vector3 = (rest.mag as Transform3D).origin
		var mag: Node3D = p.mag
		var off := 0.0
		var out_x := 0.0
		if rv > 0.01:
			if id == "bubbleBlaster":
				# shells pushed in one at a time
				off = absf(sin(c.now * PI / 0.55)) * 0.03
			elif id == "crayonCannon":
				var out := U.smoothstep(0.15, 0.35, rf) * (1 - U.smoothstep(0.4, 0.6, rf))
				mag.position = Vector3(r.x, r.y, r.z - out * 0.35)
				mag.visible = not (rf > 0.33 and rf < 0.42)
			else:
				var out := U.smoothstep(0.1, 0.32, rf) * (1 - U.smoothstep(0.42, 0.6, rf))
				off = -out * 0.28
				out_x = out * -0.05
				mag.visible = not (rf > 0.3 and rf < 0.44)
		else:
			mag.visible = true
		if id != "crayonCannon":
			mag.position = Vector3(r.x + out_x, r.y + off, r.z + (-off if id == "bubbleBlaster" else 0.0))
	if p.has("charge") and rest.has("charge") and id != "plasti9":
		var pull := U.smoothstep(0.72, 0.8, rf) * (1 - U.smoothstep(0.84, 0.9, rf)) if rv > 0.01 else 0.0
		p.charge.position.z = (rest.charge as Transform3D).origin.z + pull * 0.07
	if p.has("pump") and rest.has("pump"):
		p.pump.position.z = (rest.pump as Transform3D).origin.z + ((1 - fire_anim) * 0.08 if fire_anim > 0.2 else fire_anim * 0.3)
	if p.has("crank"):
		p.crank.rotation.x -= dt * (fire_anim * 26 + (9.0 if rv > 0.01 else 0.0))
	if p.has("jack"):
		jack_t = maxf(0, jack_t - dt * 2.2)
		var boing := sin(jack_t * 26) * jack_t * 0.35
		p.jack.scale.y = maxf(0.01, 1 + boing + (-0.35 * rv if rv > 0.01 else 0.0))
	if p.has("needle") and id == "crayonCannon":
		p.needle.rotation.x = 0
	if p.has("needle2") and p.has("needle") and id == "crayonCannon":
		var pres: float = ws.mag / ws.cfg.magSize if ws else 1.0
		p.needle.rotation.y = -1 + pres * 2 + sin(time * 20) * 0.04 * fire_anim
		p.needle2.rotation.y = -0.6 + sin(time * 2) * 0.2



## Reload beat (fraction of the reload) by name, for the current gun.
func _beat(name: String, fallback: float) -> float:
	for b in WeaponState.RELOAD_BEATS.get(current_id, []):
		if b[1] == name:
			return b[0]
	return fallback


## Real-gun reload: thumb the release, the empty mag drops away, the hand fetches a fresh one (rounds on top),
## seats it with a shove, then racks the charging handle / drops the slide. Per-shell guns get shells pushed
## into the loading port one at a time. Also: slides and bolts cycle with each shot and lock back when empty.
func _real_reload(ws: WeaponState, rf: float, rv: float, c: Dictionary) -> void:
	var m := current
	var p := m.parts
	var lg := m.left_grip
	var hand := lg
	var hand_rot := Vector3.ZERO
	var reloading: bool = ws != null and ws.reloading
	var empty: bool = ws != null and ws.mag <= 0
	var pull := 0.0
	if not reloading:
		_dropped = false
		_prev_rf = 0.0
	if hand_shell:
		hand_shell.visible = false
	var pouch := lg + Vector3(-0.12, -0.6, -0.02)
	if reloading and ws.cfg.has("reloadPerShell"):
		# shells, one by one, into the port under the receiver
		var ph := ws.shell_phase()
		var t := ws.shell_t()
		var port := m.shell_port + Vector3(0, -0.035, 0.0)
		if ph == "open":
			hand = lg.lerp(pouch, U.smoothstep(0, 1, t))
		elif ph == "shells":
			_ensure_hand_shell()
			hand_shell.visible = t < 0.92
			if t < 0.5:
				hand = pouch.lerp(port + Vector3(0, -0.05, 0.02), U.smoothstep(0, 1, t / 0.5))
			elif t < 0.9:
				hand = (port + Vector3(0, -0.05, 0.02)).lerp(port + Vector3(0, 0.0, -0.03), U.smoothstep(0, 1, (t - 0.5) / 0.4))
			else:
				hand = (port + Vector3(0, 0.0, -0.03)).lerp(pouch, U.smoothstep(0, 1, (t - 0.9) / 0.1) * 0.3)
			hand_rot = Vector3(1.0, 0, 0.2)
		else:
			hand = pouch.lerp(lg, U.smoothstep(0, 1, t))
	elif reloading and m.revolver:
		_revolver_reload(rf)
		hand = _rev_hand
		hand_rot = Vector3(1.0, 0, 0.2)
	elif reloading and p.has("mag"):
		var mag: Node3D = p.mag
		var r: Transform3D = m.rest.mag
		var b_out := _beat("out", 0.12)
		var b_in := _beat("in", 0.55)
		var b_ch := _beat("charge", 0.82)
		var base: Vector3 = r.origin + m.mag_dir * 0.1
		var mag_off := 0.0
		if rf < b_out:
			hand = lg.lerp(base, U.smoothstep(0, b_out, rf))
		elif rf < b_in - 0.24:
			# old mag gone, hand down to the pouch
			if not _dropped:
				_drop_mag(ws.mag <= 0)
			mag.visible = false
			hand = base.lerp(pouch, U.smoothstep(b_out, b_in - 0.26, rf))
		elif rf < b_in:
			# fresh mag comes up and goes in
			mag.visible = true
			var k := U.smoothstep(b_in - 0.24, b_in, rf)
			mag_off = lerpf(0.5, 0.0, k)
			hand = pouch.lerp(base, k)
		else:
			mag.visible = true
			if _prev_rf < b_in:
				kick_rot[1] += 1.4  # seated with a shove
				kick_z[1] -= 0.6
			# rack the handle if it's out in front; if it's back by your face (AR), slap the bolt catch on the side
			var ch_at: Vector3 = (m.rest.charge.origin if m.rest.has("charge") else lg) + Vector3(0.0, 0.03, 0.03)
			var at_handle := ch_at.z < -0.05
			if not at_handle:
				ch_at = Vector3(-0.05, ch_at.y - 0.05, -0.08)
			if rf < b_in + 0.06:
				hand = base + Vector3(0, -0.015, 0)  # slap the baseplate
			elif rf < b_ch - 0.08:
				hand = base.lerp(ch_at, U.smoothstep(b_in + 0.06, b_ch - 0.1, rf))
			elif rf < b_ch + 0.04:
				hand = ch_at + Vector3(0, 0, U.smoothstep(b_ch - 0.08, b_ch - 0.02, rf) * 0.07 * (1 - U.smoothstep(b_ch, b_ch + 0.03, rf)))
				pull = U.smoothstep(b_ch - 0.08, b_ch - 0.02, rf) * (1 - U.smoothstep(b_ch, b_ch + 0.02, rf)) if at_handle else 0.0
				if _prev_rf < b_ch and rf >= b_ch:
					kick_rot[1] += 0.8
			else:
				hand = ch_at.lerp(lg, U.smoothstep(b_ch + 0.04, 1.0, rf))
			if not m.rest.has("charge"):
				hand = base.lerp(lg, U.smoothstep(b_in + 0.06, 1.0, rf))
		mag.position = r.origin + m.mag_dir * mag_off
		hand_rot = Vector3(1.15, 0, 0.25)  # forearm angled down and away, not across the view
		_prev_rf = rf
	elif p.has("mag"):
		(p.mag as Node3D).visible = true
		(p.mag as Node3D).transform = m.rest.mag
	if m.revolver and not reloading:
		(p.crane as Node3D).rotation.z = 0.0
		_rev_tip = 0.0
		if speedloader:
			speedloader.visible = false
	if m.rounds and not (reloading and m.revolver):
		m.rounds.visible = true
	if not reloading:
		_prev_rf = 0.0
	# pump action: the pump racks back and forward after each shot (the left hand rides it)
	if p.has("pump") and m.rest.has("pump"):
		var pz := (1 - fire_anim) * 0.08 if fire_anim > 0.2 else fire_anim * 0.3
		(p.pump as Node3D).position = m.rest.pump.origin + Vector3(0, 0, pz)
		if not reloading:
			hand = lg + Vector3(0, 0, pz)
	# slide / charging handle / bolt: cycles on each shot, locks back on an empty gun
	var fire_back := fire_anim * 0.045
	var locked: bool = empty and not (reloading and not ws.cfg.has("reloadPerShell") and rf >= _beat("charge", 0.82))
	if m.bolt_action and p.has("charge"):
		var bk := clampf((1 - bolt_t - 0.15) / 0.85, 0, 1) if bolt_t > 0 else 0.0
		if reloading and not ws.cfg.has("reloadPerShell"):
			var b_ch := _beat("charge", 0.72)
			bk = maxf(bk, U.smoothstep(b_ch - 0.14, b_ch + 0.06, rf) * (1.0 if rf < b_ch + 0.08 else 0.0))
		if _prev_bolt_k < 0.45 and bk >= 0.45 and m.eject:
			_throw_casing(m.casing)
		_prev_bolt_k = bk
		var up := U.smoothstep(0, 0.2, bk) * (1 - U.smoothstep(0.8, 1, bk))
		var back := U.smoothstep(0.2, 0.45, bk) * (1 - U.smoothstep(0.55, 0.8, bk))
		var ch: Node3D = p.charge
		ch.rotation.z = up * 1.1
		ch.position = m.rest.charge.origin + Vector3(0, 0, back * 0.09)
	elif p.has("charge") and m.rest.has("charge"):
		var z := pull * 0.07
		if m.charge_cycles:
			z = maxf(z, maxf(fire_back, 0.05 if locked else 0.0))
		(p.charge as Node3D).position = m.rest.charge.origin + Vector3(0, 0, z)
	if p.has("bcg") and m.rest.has("bcg"):
		(p.bcg as Node3D).position = m.rest.bcg.origin + Vector3(0, 0, maxf(fire_back, 0.04 if locked else 0.0))
	# the left hand: blend into the reload path and back to the grip
	var k2 := clampf(rv * 1.2, 0, 1)
	hand_l.position = lg.lerp(hand, k2)
	hand_l.rotation = hand_rot * k2


var _rev_hand := Vector3.ZERO


## Revolver: swing the cylinder out, tip the muzzle up and punch the six empties out, bring a speedloader up,
## drop six fresh rounds in, flick the cylinder shut.
func _revolver_reload(rf: float) -> void:
	var m := current
	var p := m.parts
	var crane: Node3D = p.crane
	var cyl: Node3D = p.cylinder
	var lg := m.left_grip
	var pouch := lg + Vector3(-0.12, -0.6, -0.02)
	var b_open := _beat("open", 0.1)
	var b_ej := _beat("eject", 0.22)
	var b_in := _beat("in", 0.62)
	var b_close := _beat("close", 0.85)
	crane.rotation.z = U.smoothstep(b_open - 0.06, b_open + 0.04, rf) * (1 - U.smoothstep(b_close - 0.04, b_close + 0.01, rf)) * 1.25
	var cyl_at: Vector3 = crane.transform * cyl.position
	_rev_tip = U.smoothstep(b_ej - 0.1, b_ej - 0.02, rf) * (1 - U.smoothstep(b_ej + 0.06, b_ej + 0.14, rf))
	if _prev_rf < b_ej and rf >= b_ej:
		_eject_cylinder(cyl_at)
	m.rounds.visible = rf < b_ej or rf >= b_in
	_ensure_speedloader()
	speedloader.visible = rf >= b_in - 0.24 and rf < b_in
	var at_cyl := cyl_at + Vector3(-0.02, -0.03, 0.03)
	var behind := cyl_at + Vector3(0, 0, 0.09)
	if rf < b_open:
		_rev_hand = lg.lerp(at_cyl, U.smoothstep(0, b_open, rf))
	elif rf < b_ej + 0.06:
		_rev_hand = at_cyl
	elif rf < b_in - 0.24:
		_rev_hand = at_cyl.lerp(pouch, U.smoothstep(b_ej + 0.06, b_in - 0.26, rf))
	elif rf < b_in:
		_rev_hand = pouch.lerp(behind, U.smoothstep(b_in - 0.24, b_in, rf))
	elif rf < b_close:
		_rev_hand = behind.lerp(at_cyl, U.smoothstep(b_in, b_close - 0.04, rf))
	else:
		_rev_hand = at_cyl.lerp(lg, U.smoothstep(b_close, 1.0, rf))
	if _prev_rf < b_close and rf >= b_close:
		kick_rot[1] += 1.2  # flicked shut
	_prev_rf = rf


func _ensure_speedloader() -> void:
	if speedloader:
		return
	speedloader = Node3D.new()
	var k := GunKit.new()
	k.add(speedloader, GunKit.mat("polymer"), GunKit.tube(0.03, 0.014, 12), Vector3(0, 0, 0.012))
	k.add(speedloader, GunKit.mat("polymer"), GunKit.tube(0.008, 0.03, 8), Vector3(0, 0, 0.03))
	for i in 6:
		var a := float(i) / 6 * TAU
		k.round_at(speedloader, Vector3(cos(a) * 0.021, sin(a) * 0.021, 0.004), 0.008, 0.04)
	k.bake()
	speedloader.position = Vector3(0.0, 0.06, -0.03)
	speedloader.visible = false
	hand_l.add_child(speedloader)


## Six empties drop out of the swung-out cylinder.
func _eject_cylinder(cyl_at: Vector3) -> void:
	var xf := holder.transform * current.transform
	for i in 6:
		var a := float(i) / 6 * TAU
		var lp := cyl_at + Vector3(cos(a) * 0.021, sin(a) * 0.021, 0.045)
		_launch_casing("pistol", xf * lp, xf.basis * Vector3(U.rand(-0.3, 0.3), U.rand(-1.2, -0.4), U.rand(0.6, 1.4)), xf.basis)

## Throw a copy of the magazine out of the gun: it falls away and disappears.
func _drop_mag(was_empty: bool) -> void:
	_dropped = true
	var mag: Node3D = current.parts.mag
	var d := mag.duplicate() as Node3D
	var r := d.get_node_or_null("rounds")
	if r and was_empty:
		r.visible = false
	add_child(d)
	d.transform = holder.transform * current.transform * mag.transform
	var v := holder.basis * (current.mag_dir * 2.2) + Vector3(U.rand(-0.1, 0.1), -0.3, 0.1)
	_flying.append([d, v, Vector3(U.rand(-4, 4), U.rand(-2, 2), U.rand(-3, 3)), 0.9, true])


func _ensure_hand_shell() -> void:
	if hand_shell:
		return
	hand_shell = Node3D.new()
	var k := GunKit.new()
	k.round_at(hand_shell, Vector3(0, 0, 0.03), 0.013, 0.07, current.casing == "shell")
	k.bake()
	hand_shell.position = Vector3(0, 0.05, -0.01)
	hand_shell.rotation = Vector3(-0.2, 0, 0)
	hand_l.add_child(hand_shell)


func _casing_node(kind: String) -> Node3D:
	if not _casings.has(kind):
		_casings[kind] = []
	for n: Node3D in _casings[kind]:
		if not n.visible:
			return n
	if (_casings[kind] as Array).size() >= 10:
		return null
	var n := Node3D.new()
	var k := GunKit.new()
	match kind:
		"shell": k.round_at(n, Vector3(0, 0, 0.035), 0.013, 0.07, true)
		"rifle": k.add(n, GunKit.mat("brass"), GunKit.tube(0.0055, 0.032, 10).translate(0, 0, 0), Vector3.ZERO)
		_: k.add(n, GunKit.mat("brass"), GunKit.tube(0.0065, 0.022, 10), Vector3.ZERO)
	k.bake()
	n.visible = false
	add_child(n)
	(_casings[kind] as Array).append(n)
	return n


## Spent brass out of the ejection port: up and to the right, tumbling.
func _throw_casing(kind: String) -> void:
	var n := _casing_node(kind)
	if n == null:
		return
	var xf := holder.transform * current.transform
	n.transform = Transform3D(xf.basis, xf * current.eject.position)
	n.visible = true
	var v: Vector3 = xf.basis * Vector3(U.rand(2.6, 3.6), U.rand(2.0, 3.0), U.rand(0.4, 1.2))
	_flying.append([n, v, Vector3(U.rand(-25, 25), U.rand(-15, 15), U.rand(-25, 25)), 0.55, false])


func _launch_casing(kind: String, pos: Vector3, v: Vector3, basis: Basis) -> void:
	var n := _casing_node(kind)
	if n == null:
		return
	n.transform = Transform3D(basis, pos)
	n.visible = true
	_flying.append([n, v, Vector3(U.rand(-12, 12), U.rand(-8, 8), U.rand(-12, 12)), 0.7, false])


func _update_flying(dt: float) -> void:
	if _flying.is_empty():
		return
	var keep := []
	for f in _flying:
		var n: Node3D = f[0]
		f[3] -= dt
		if f[3] <= 0 or not is_instance_valid(n):
			if is_instance_valid(n):
				if f[4]:
					n.queue_free()
				else:
					n.visible = false
			continue
		f[1] += Vector3(0, -6.0, 0) * dt
		n.position += f[1] * dt
		var sp: Vector3 = f[2]
		n.basis = n.basis * Basis.from_euler(sp * dt)
		keep.append(f)
	_flying = keep

## World-space approx of the muzzle for tracers (the viewmodel lives in its own world).
static func muzzle_world(cam_xf: Transform3D, ads: float) -> Vector3:
	return cam_xf * Vector3(0.18 * (1 - ads), -0.13 * (1 - ads) - 0.04 * ads, -0.75)

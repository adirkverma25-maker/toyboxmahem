class_name Barriers
extends Node3D
## Mesh Shield: a deployable hex-wire wall that eats enemy bullets, darts and splash (port of Barriers.ts).
## Teammates (and the owner) shoot straight through it.

const SHADER := preload("res://shaders/barrier.gdshader")

var list: Array = []
var _quad := QuadMesh.new()
var on_break := Callable()


## Does this barrier stop shots from `shooter`?
func blocks(b: Dictionary, shooter) -> bool:
	if b.dying > 0 or shooter == null or shooter == b.owner:
		return false
	if shooter.team >= 0:
		return shooter.team != b.team
	return true


func deploy(owner: Actor, pos: Vector3, yaw: float, color: String, now: float) -> Dictionary:
	# one shield per toy
	for b in list:
		if b.owner == owner and b.dying <= 0:
			b.dying = 0.3
	var cfg: Dictionary = Cfg.ABILITIES.shield
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("uColor", U.col(color))
	mat.set_shader_parameter("uSize", Vector2(cfg.width, cfg.height))
	mat.render_priority = 6
	var mesh := MeshInstance3D.new()
	mesh.mesh = _quad
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.extra_cull_margin = 4
	var center := Vector3(pos.x, pos.y + cfg.height / 2.0, pos.z)
	mesh.transform = Transform3D(Basis(Vector3.UP, yaw).scaled_local(Vector3(cfg.width, cfg.height, 1)), center)
	add_child(mesh)
	var b := {
		"owner": owner, "team": owner.team, "center": center, "normal": Vector3(-sin(yaw), 0, -cos(yaw)),
		"right": Vector3(cos(yaw), 0, -sin(yaw)), "up": Vector3.UP, "yaw": yaw,
		"halfW": cfg.width / 2.0, "halfH": cfg.height / 2.0,
		"hp": float(cfg.hp), "expireAt": now + cfg.duration, "born": now, "mesh": mesh, "mat": mat, "color": color,
		"flash": 0.0, "dying": 0.0,
	}
	list.append(b)
	return b


## Ray/segment test. Returns {b, t} for the nearest blocking barrier along unit `d`, or {}.
func trace(o: Vector3, d: Vector3, max_t: float, shooter) -> Dictionary:
	var best := {}
	for b in list:
		if not blocks(b, shooter):
			continue
		var n: Vector3 = b.normal
		var denom := d.dot(n)
		if absf(denom) < 1e-5:
			continue
		var t := ((b.center as Vector3) - o).dot(n) / denom
		if t < 0 or t > max_t:
			continue
		var p := o + d * t - (b.center as Vector3)
		if absf(p.dot(b.right)) > b.halfW or absf(p.y) > b.halfH:
			continue
		if best.is_empty() or t < best.t:
			best = {"b": b, "t": t}
	return best


## Is the straight line between two points cut by a barrier that blocks `shooter`?
func between(a: Vector3, c: Vector3, shooter) -> Dictionary:
	var d := c - a
	var l := d.length()
	if l < 1e-4:
		return {}
	return trace(a, d / l, l, shooter)


func damage(b: Dictionary, amount: float) -> void:
	if b.dying > 0:
		return
	b.hp -= amount
	b.flash = 1.0
	if b.hp <= 0:
		b.dying = 0.35
		if on_break.is_valid():
			on_break.call(b)


func update(dt: float, now: float) -> void:
	var H: float = Cfg.ABILITIES.shield.height
	var W: float = Cfg.ABILITIES.shield.width
	for i in range(list.size() - 1, -1, -1):
		var b: Dictionary = list[i]
		var m: ShaderMaterial = b.mat
		m.set_shader_parameter("uTime", now)
		b.flash = maxf(0, b.flash - dt * 5)
		m.set_shader_parameter("uFlash", b.flash)
		m.set_shader_parameter("uHealth", maxf(0, b.hp / Cfg.ABILITIES.shield.hp))
		if b.dying <= 0 and (now >= b.expireAt or not b.owner.alive):
			b.dying = 0.35
		var sy := H
		if b.dying > 0:
			b.dying -= dt
			m.set_shader_parameter("uAlpha", maxf(0, b.dying / 0.35))
			sy = H * (0.6 + 0.4 * maxf(0, b.dying / 0.35))
			if b.dying <= 0:
				(b.mesh as Node).queue_free()
				list.remove_at(i)
				continue
		else:
			var grow := minf(1, (now - b.born) / 0.25)
			m.set_shader_parameter("uAlpha", grow * (0.55 + 0.45 * sin(now * 20) if now > b.expireAt - 1.2 else 1.0))
			sy = H * grow
		(b.mesh as MeshInstance3D).transform = Transform3D(Basis(Vector3.UP, b.yaw).scaled_local(Vector3(W, maxf(0.001, sy), 1)), b.center)


func clear() -> void:
	for b in list:
		(b.mesh as Node).queue_free()
	list = []

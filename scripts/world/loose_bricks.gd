class_name LooseBricks
extends RefCounted
## Dynamic loose bricks that scatter from explosions (port of LooseBricks in Arena.ts).

const COLORS := ["#d6342c", "#f2c12e", "#1f6fd1", "#2f9e44", "#f4f4f4", "#f08c1f", "#7b3fb5"]

var bodies: Array[RigidBody3D] = []
var home: Vector3


func _init(phys: Phys, spots: Array, parent: Node3D, home_pos: Vector3) -> void:
	home = home_pos
	var rnd := U.seeded(99)
	var g := Geo.rounded_box(0.9, 0.55, 1.8, 2, 0.06)
	for i in spots.size():
		var b := phys.dynamic_box(spots[i], Vector3(0.45, 0.275, 0.9), "plastic", 0.5, Basis(Vector3.UP, rnd.next() * PI))
		var mat := Mats.plastic(COLORS[i % COLORS.size()], {"rough": 0.3, "clearcoat": 0.7})
		var mi := MeshInstance3D.new()
		mi.mesh = g.to_mesh(mat)
		b.add_child(mi)
		bodies.append(b)
	if parent:
		pass


func update(_dt := 0.0, _t := 0.0) -> void:
	for b in bodies:
		var p := b.global_position
		if p.y < -5 or absf(p.x) > 60 or absf(p.z) > 60:
			b.global_position = home
			b.linear_velocity = Vector3.ZERO


## Radial impulse from an explosion.
func blast(center: Vector3, radius: float, strength: float) -> void:
	for b in bodies:
		var d3 := b.global_position - center
		var d := d3.length()
		if d > radius * 1.6:
			continue
		var f := (1.0 - d / (radius * 1.6)) * strength
		var inv := 1.0 / maxf(0.3, d)
		b.apply_central_impulse(Vector3(d3.x * inv * f, (absf(d3.y) * inv + 0.9) * f, d3.z * inv * f))
		b.apply_torque_impulse(Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * f * 0.3)

class_name Ropes
extends Node3D
## Spring Hook visuals: a cord from the hand to a little claw stuck in the surface (port of Ropes.ts).

var _pool: Array = []


func _make() -> Dictionary:
	var cord := Geo.cylinder(0.03, 0.03, 1, 6).translate(0, 0.5, 0).mesh_instance(Mats.plastic("#ffd23f", {"rough": 0.4}))
	cord.extra_cull_margin = 50
	var hook := Node3D.new()
	var steel := Mats.metal("#d6dbe3", 0.25)
	hook.add_child(Geo.sphere(0.12, 10, 8).mesh_instance(Mats.plastic("#e63946")))
	for i in 3:
		var claw := Geo.torus(0.16, 0.035, 6, 10, PI).mesh_instance(steel, Vector3(0, -0.05, 0), Basis(Vector3.UP, float(i) / 3 * TAU))
		hook.add_child(claw)
	add_child(cord)
	add_child(hook)
	var r := {"cord": cord, "hook": hook, "used": false}
	_pool.append(r)
	return r


## Call begin(), then draw() for every active hook this frame, then end().
func begin() -> void:
	for r in _pool:
		r.used = false


func draw(from: Vector3, to: Vector3, t: float) -> void:
	var r = null
	for x in _pool:
		if not x.used:
			r = x
			break
	if r == null:
		r = _make()
	r.used = true
	# the hook flies out over the first ~0.12 s
	var k := minf(1, t / 0.12)
	var end := from.lerp(to, k)
	var d := end - from
	var l := maxf(0.01, d.length())
	var rot := U.from_up(d / l)
	(r.cord as Node3D).transform = Transform3D(rot.scaled_local(Vector3(1, l, 1)), from)
	(r.hook as Node3D).transform = Transform3D(rot, end)


func end() -> void:
	for r in _pool:
		r.cord.visible = r.used
		r.hook.visible = r.used


func clear() -> void:
	for r in _pool:
		r.cord.visible = false
		r.hook.visible = false

class_name ToyCityAmbient
extends Node3D
## Toy City background life: a model train doing laps of the table on the railway loop (visual only,
## it runs along the edge outside the streets) and its chuff and whistle. No hazards.

const HALF := 30.5  # loop half size
const CORNER := 4.0  # corner radius
const SPEED := 5.5

var audio
var ambience_on := false
var reduced := false
var cars: Array = []  # Node3D per car
var gaps: Array = []  # distance behind the engine
var s := 0.0
var _chug := 0.0
var _whistle := 12.0
var _len := 0.0


## Points along the loop every `step` metres: [[pos, tangent], ...]
static func loop_points(step: float) -> Array:
	var out := []
	var total := _length()
	var d := 0.0
	while d < total:
		out.append(_at(d))
		d += step
	return out


static func _length() -> float:
	var straight := 2 * (HALF - CORNER)
	return 4 * straight + TAU * CORNER


## Position + tangent at distance d along the loop (clockwise seen from above, starting on the north side).
static func _at(d: float) -> Array:
	var straight := 2 * (HALF - CORNER)
	var arc := PI / 2 * CORNER
	d = fposmod(d, _length())
	var h := HALF - CORNER
	# sides: north (-z) going +x, east going +z, south going -x, west going -z
	var sides := [
		[Vector3(-h, 0, -HALF), Vector3(1, 0, 0), Vector3(h, 0, -h)],
		[Vector3(HALF, 0, -h), Vector3(0, 0, 1), Vector3(h, 0, h)],
		[Vector3(h, 0, HALF), Vector3(-1, 0, 0), Vector3(-h, 0, h)],
		[Vector3(-HALF, 0, h), Vector3(0, 0, -1), Vector3(-h, 0, -h)],
	]
	for i in 4:
		var sd: Array = sides[i]
		if d < straight:
			return [sd[0] + sd[1] * d, sd[1]]
		d -= straight
		if d < arc:
			# corner: turn right (clockwise) around the corner centre
			var a := (d / CORNER)
			var c: Vector3 = sd[2]
			var start_dir: Vector3 = sd[1]
			var out_n := Vector3(-start_dir.z, 0, start_dir.x) * -1  # left normal flipped = outward
			var r0 := out_n * CORNER
			var rot := Basis(Vector3.UP, -a)
			var p: Vector3 = c + rot * r0
			var t: Vector3 = (rot * start_dir).normalized()
			return [p, t]
		d -= arc
	return [sides[0][0], sides[0][1]]


func _init(aud = null) -> void:
	name = "Ambient"
	audio = aud
	_len = _length()
	var engine_col := Mats.plastic("#2b2d42", {"rough": 0.35})
	var red := Mats.plastic("#e63946", {"rough": 0.3})
	var gold := Mats.plastic("#ffd23f", {"rough": 0.3})
	var wheel := Mats.rubber("#1d1d1d")
	var car_cols := ["#3a86ff", "#2dc653", "#ff7b00"]
	for i in 4:
		var car := Node3D.new()
		var body: Material = engine_col if i == 0 else Mats.plastic(car_cols[i - 1], {"rough": 0.4})
		car.add_child(Geo.rounded_box(1.5, 1.2, 3.0, 2, 0.15).mesh_instance(body, Vector3(0, 0.9, 0)))
		if i == 0:
			car.add_child(Geo.cylinder(0.6, 0.6, 2.0, 16).mesh_instance(engine_col, Vector3(0, 1.4, 0.5), Basis(Vector3.RIGHT, PI / 2)))
			car.add_child(Geo.cylinder(0.22, 0.3, 0.8, 12).mesh_instance(red, Vector3(0, 2.2, 1.1)))
			car.add_child(Geo.rounded_box(1.4, 1.0, 1.0, 2, 0.1).mesh_instance(red, Vector3(0, 1.9, -0.9)))
			car.add_child(Geo.sphere(0.2, 10, 8).mesh_instance(Mats.glow("#fff3b0", 2), Vector3(0, 1.4, 1.55), Basis(), false))
		else:
			car.add_child(Geo.box(1.55, 0.12, 3.05).mesh_instance(gold, Vector3(0, 1.55, 0)))
		for wz in [-1.0, 1.0]:
			for wx in [-0.72, 0.72]:
				car.add_child(Geo.cylinder(0.32, 0.32, 0.12, 14).mesh_instance(wheel, Vector3(wx, 0.32, wz), Basis(Vector3.BACK, PI / 2)))
		Merge.flatten_by_material(car)
		add_child(car)
		cars.append(car)
		gaps.append(i * 3.4)


func update(dt: float, _actors := [], _hurt := Callable(), listener := Vector3.ZERO) -> void:
	s = fposmod(s + dt * SPEED * (0.5 if reduced else 1.0), _len)
	for i in cars.size():
		var at := _at(s - gaps[i])
		var car: Node3D = cars[i]
		car.position = at[0] as Vector3
		var t: Vector3 = at[1]
		car.rotation = Vector3(0, atan2(t.x, t.z), 0)
	if not ambience_on or audio == null:
		return
	var engine: Vector3 = (cars[0] as Node3D).position
	_whistle -= dt
	if _whistle <= 0:
		_whistle = U.rand(30, 60)
		audio.train_whistle(engine)
	if engine.distance_to(listener) < 40:
		_chug -= dt
		if _chug <= 0:
			_chug = 0.42
			audio.train_chug(engine)


func block_drop(_nav = null, _count := 8, _spots = null) -> Array:
	return []


func clear_blocks() -> void:
	pass


func start_sounds() -> void:
	pass


func stop_sounds() -> void:
	pass


func set_reduced_motion(r: bool) -> void:
	reduced = r

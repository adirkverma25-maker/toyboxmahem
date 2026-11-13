class_name U
## Small math helpers shared by everything (port of src/core/math.ts).

const DEG := PI / 180.0


static func damp(a: float, b: float, lam: float, dt: float) -> float:
	return lerpf(a, b, 1.0 - exp(-lam * dt))


static func damp_v(a: Vector3, b: Vector3, lam: float, dt: float) -> Vector3:
	return a.lerp(b, 1.0 - exp(-lam * dt))


static func rand(a: float, b: float) -> float:
	return a + randf() * (b - a)


static func rand_int(a: int, b: int) -> int:
	return randi_range(a, b)


static func pick(arr: Array):
	return arr[randi() % arr.size()]


static func smoothstep(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func move_toward_f(v: float, target: float, max_delta: float) -> float:
	return target if absf(target - v) <= max_delta else v + signf(target - v) * max_delta


static func angle_wrap(a: float) -> float:
	while a > PI:
		a -= TAU
	while a < -PI:
		a += TAU
	return a


## three.js style Euler -> Basis. Orders match three.js ("XYZ" = Rx * Ry * Rz).
static func euler(x: float, y: float, z: float, order := "XYZ") -> Basis:
	var o := EULER_ORDER_XYZ
	match order:
		"YXZ": o = EULER_ORDER_YXZ
		"ZXY": o = EULER_ORDER_ZXY
		"ZYX": o = EULER_ORDER_ZYX
		"YZX": o = EULER_ORDER_YZX
		"XZY": o = EULER_ORDER_XZY
	return Basis.from_euler(Vector3(x, y, z), o)


static func xform(pos: Vector3, rot := Basis(), scale := Vector3.ONE) -> Transform3D:
	return Transform3D(rot.scaled_local(scale) if scale != Vector3.ONE else rot, pos)


## Basis that turns +Y into `dir` (three's Quaternion.setFromUnitVectors(up, dir)).
static func from_up(dir: Vector3) -> Basis:
	var d := dir.normalized()
	var up := Vector3.UP
	var c := up.cross(d)
	if c.length() < 1e-6:
		return Basis() if d.y > 0 else Basis(Vector3.RIGHT, PI)
	return Basis(c.normalized(), up.angle_to(d))


static func col(c) -> Color:
	if c is Color:
		return c
	if c is String:
		return Color.html(c)
	if c is int:
		return Color.hex((c << 8) | 0xff)
	return Color.WHITE


## Seeded PRNG (mulberry32) so procedural textures and layouts are the same every run.
class Seeded:
	var t: int

	func _init(seed: int) -> void:
		t = seed & 0xffffffff

	func next() -> float:
		t = (t + 0x6d2b79f5) & 0xffffffff
		var r := _imul(t ^ (t >> 15), 1 | t)
		r = (r ^ (r + _imul(r ^ (r >> 7), 61 | r))) & 0xffffffff
		return float((r ^ (r >> 14)) & 0xffffffff) / 4294967296.0

	static func _imul(a: int, b: int) -> int:
		return (a * b) & 0xffffffff


static func seeded(seed: int) -> Seeded:
	return Seeded.new(seed)


## Random direction inside a cone of half-angle `angle` (radians) around `dir`.
static func cone_direction(dir: Vector3, angle: float) -> Vector3:
	if angle <= 0.0:
		return dir
	var u := randf()
	var cos_a := 1.0 - u * (1.0 - cos(angle))
	var sin_a := sqrt(maxf(0.0, 1.0 - cos_a * cos_a))
	var phi := randf() * TAU
	var a := Vector3(1, 0, 0)
	if absf(dir.x) > 0.9:
		a = Vector3(0, 1, 0)
	var b := dir.cross(a).normalized()
	a = dir.cross(b).normalized()
	return (dir * cos_a + b * (sin_a * cos(phi)) + a * (sin_a * sin(phi))).normalized()


## Ray vs sphere. Returns distance along the (normalized) ray or -1.
static func ray_sphere(o: Vector3, d: Vector3, c: Vector3, r: float, max_t: float) -> float:
	var oc := o - c
	var b := oc.dot(d)
	var cc := oc.dot(oc) - r * r
	if cc > 0 and b > 0:
		return -1.0
	var disc := b * b - cc
	if disc < 0:
		return -1.0
	var t := -b - sqrt(disc)
	if t < 0:
		t = 0
	return t if t <= max_t else -1.0


## Ray vs capsule (segment a-b with radius r). Returns distance or -1. (Inigo Quilez)
static func ray_capsule(o: Vector3, d: Vector3, a: Vector3, b: Vector3, r: float, max_t: float) -> float:
	var ba := b - a
	var oa := o - a
	var baba := ba.dot(ba)
	var bard := ba.dot(d)
	var baoa := ba.dot(oa)
	var rdoa := d.dot(oa)
	var oaoa := oa.dot(oa)
	var A := baba - bard * bard
	var B := baba * rdoa - baoa * bard
	var C := baba * oaoa - baoa * baoa - r * r * baba
	var h := B * B - A * C
	if h >= 0 and absf(A) > 1e-9:
		var t := (-B - sqrt(h)) / A
		var y := baoa + t * bard
		if y > 0 and y < baba and t >= 0 and t <= max_t:
			return t
		var p := oa if y <= 0 else oa - ba
		B = d.dot(p)
		C = p.dot(p) - r * r
		h = B * B - C
		if h > 0:
			var t2 := -B - sqrt(h)
			if t2 >= 0 and t2 <= max_t:
				return t2
			if C < 0:
				return 0.0
	var seg_t := clampf(baoa / maxf(baba, 1e-9), 0.0, 1.0)
	var pp := a + ba * seg_t
	if pp.distance_squared_to(o) < r * r:
		return 0.0
	return -1.0


static func closest_point_on_segment(p: Vector3, a: Vector3, b: Vector3) -> Vector3:
	var ba := b - a
	var t := clampf((p - a).dot(ba) / maxf(1e-6, ba.length_squared()), 0.0, 1.0)
	return a + ba * t


static func format_time(sec: float) -> String:
	var s := int(ceil(maxf(0.0, sec)))
	return "%d:%02d" % [s / 60, s % 60]


## Horizontal forward vector for a yaw (three.js convention: yaw 0 looks down -Z).
static func yaw_fwd(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))

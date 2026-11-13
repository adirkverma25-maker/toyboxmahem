class_name CRSpline
extends RefCounted
## three.js CatmullRomCurve3 (centripetal / uniform, open or closed) with its arc-length helpers
## getPointAt / getTangentAt / getLength (200 arc-length divisions, like three's default).

var points: Array
var closed: bool
var centripetal: bool
var _lengths := PackedFloat32Array()
const DIVISIONS := 200


func _init(pts: Array, is_closed := false, curve_type := "centripetal") -> void:
	points = pts
	closed = is_closed
	centripetal = curve_type == "centripetal"
	_lengths.resize(DIVISIONS + 1)
	var last := get_point(0)
	var sum := 0.0
	_lengths[0] = 0
	for i in range(1, DIVISIONS + 1):
		var p := get_point(float(i) / DIVISIONS)
		sum += p.distance_to(last)
		_lengths[i] = sum
		last = p


static func _nonuniform(x0: float, x1: float, x2: float, x3: float, dt0: float, dt1: float, dt2: float, t: float) -> float:
	var t1 := ((x1 - x0) / dt0 - (x2 - x0) / (dt0 + dt1) + (x2 - x1) / dt1) * dt1
	var t2 := ((x2 - x1) / dt1 - (x3 - x1) / (dt1 + dt2) + (x3 - x2) / dt2) * dt1
	var c0 := x1
	var c1 := t1
	var c2 := -3 * x1 + 3 * x2 - 2 * t1 - t2
	var c3 := 2 * x1 - 2 * x2 + t1 + t2
	return c0 + c1 * t + c2 * t * t + c3 * t * t * t


func get_point(t: float) -> Vector3:
	var l := points.size()
	var p := (l - (0 if closed else 1)) * t
	var ip := floori(p)
	var w := p - ip
	if closed:
		ip += 0 if ip > 0 else (floori(absf(ip) / l) + 1) * l
	elif w == 0 and ip == l - 1:
		ip = l - 2
		w = 1
	var p0: Vector3
	var p3: Vector3
	if closed or ip > 0:
		p0 = points[(ip - 1) % l]
	else:
		p0 = (points[0] as Vector3) * 2 - (points[1] as Vector3)
	var p1: Vector3 = points[ip % l]
	var p2: Vector3 = points[(ip + 1) % l]
	if closed or ip + 2 < l:
		p3 = points[(ip + 2) % l]
	else:
		p3 = (points[l - 1] as Vector3) * 2 - (points[l - 2] as Vector3)
	if centripetal:
		var dt0 := pow(p0.distance_squared_to(p1), 0.25)
		var dt1 := pow(p1.distance_squared_to(p2), 0.25)
		var dt2 := pow(p2.distance_squared_to(p3), 0.25)
		if dt1 < 1e-4:
			dt1 = 1.0
		if dt0 < 1e-4:
			dt0 = dt1
		if dt2 < 1e-4:
			dt2 = dt1
		return Vector3(_nonuniform(p0.x, p1.x, p2.x, p3.x, dt0, dt1, dt2, w), _nonuniform(p0.y, p1.y, p2.y, p3.y, dt0, dt1, dt2, w), _nonuniform(p0.z, p1.z, p2.z, p3.z, dt0, dt1, dt2, w))
	return Geo.catmull(points, t)


func get_length() -> float:
	return _lengths[DIVISIONS]


## Arc-length u (0..1) -> curve parameter t.
func u_to_t(u: float) -> float:
	var target := u * _lengths[DIVISIONS]
	var lo := 0
	var hi := DIVISIONS
	while lo <= hi:
		var i := lo + (hi - lo) / 2
		var c := _lengths[i] - target
		if c < 0:
			lo = i + 1
		elif c > 0:
			hi = i - 1
		else:
			return float(i) / DIVISIONS
	var i := maxi(0, hi)
	if _lengths[i] == target:
		return float(i) / DIVISIONS
	var before := _lengths[i]
	var after := _lengths[mini(i + 1, DIVISIONS)]
	var seg := after - before
	var frac := (target - before) / seg if seg > 0 else 0.0
	return (i + frac) / DIVISIONS


func get_point_at(u: float) -> Vector3:
	return get_point(u_to_t(u))


func get_tangent_at(u: float) -> Vector3:
	var t := u_to_t(u)
	var d := 0.0001
	var t1 := maxf(0, t - d)
	var t2 := minf(1, t + d)
	return (get_point(t2) - get_point(t1)).normalized()

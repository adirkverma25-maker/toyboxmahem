class_name Traversal
extends Node3D
## Jump pads and ziplines (replace the old elevators on every map).
##  pads: [{pos: Vector3 (feet on the pad), to: Vector3 (landing spot)}] - step on to be launched on an arc to `to`.
##  zips: [{a: Vector3, b: Vector3}] - feet positions at each end; the cable hangs CABLE_UP above them.
##        Grab with the interact key (revive bind), ride toward the end you face, jump to let go.

const PAD_RADIUS := 1.15
const PAD_APEX := 2.5  # metres above the higher end of the arc
const PAD_COOLDOWN := 0.45
const CABLE_UP := 2.6  # cable height above the feet points
const REACH := 2.4  # how close your eyes must be to a cable to grab it
const MARGIN := 1.0  # riders stop this far before each end post

var phys: Phys
var audio
var fx
var pads: Array = []  # {pos, to, top: Node3D, ring: MeshInstance3D, squash: float}
var zips: Array = []  # {a, b, ca, cb, len, d}
var _cool := {}  # actor -> time it may be launched again
var _t := 0.0
## dev counters for the autotest: how often pads / ziplines were used
var uses := {"pad": 0, "zip": 0}


static func hazard_texture() -> Texture2D:
	return Tex.make("hazard", 256, 32, func(ci: CanvasItem):
		ci.draw_rect(Rect2(0, 0, 256, 32), Color("#ffd23f"))
		var x := -32
		while x < 288:
			ci.draw_colored_polygon(PackedVector2Array([Vector2(x, 32), Vector2(x + 16, 0), Vector2(x + 32, 0), Vector2(x + 16, 32)]), Color("#1d1d1f"))
			x += 32
	, {"placeholder": Color("#ffd23f")})


## Top of a pad: yellow disc with three dark chevrons pointing "forward" (-Y in texture space = launch direction).
static func pad_texture() -> Texture2D:
	return Tex.make("jumppad", 256, 256, func(ci: CanvasItem):
		ci.draw_circle(Vector2(128, 128), 128, Color("#ffd23f"))
		ci.draw_arc(Vector2(128, 128), 118, 0, TAU, 64, Color("#1d1d1f"), 8, true)
		for i in 3:
			var y := 168.0 - i * 44
			ci.draw_colored_polygon(PackedVector2Array([Vector2(78, y + 14), Vector2(128, y - 24), Vector2(178, y + 14), Vector2(178, y + 34), Vector2(128, y - 4), Vector2(78, y + 34)]), Color("#1d1d1f"))
	, {"placeholder": Color("#ffd23f")})


func _init(p: Phys, aud, effects, pad_list: Array, zip_list: Array) -> void:
	name = "Traversal"
	phys = p
	audio = aud
	fx = effects
	var base_m := Mats.plastic("#e63946", {"rough": 0.35})
	var top_m := StandardMaterial3D.new()
	top_m.albedo_texture = pad_texture()
	top_m.roughness = 0.4
	top_m.emission_enabled = true
	top_m.emission = Color("#ffb703")
	top_m.emission_energy_multiplier = 0.25
	var ring_m := Mats.plastic("#ffffff", {"rough": 0.3, "emissive": "#ffd23f", "emissive_intensity": 1.4})
	var spring_m := Mats.metal("#c9ced6", 0.3)
	for s in pad_list:
		var pos: Vector3 = _snap(s.pos)
		var to: Vector3 = _snap(s.to)
		var node := Node3D.new()
		node.position = pos
		node.rotation.y = atan2(-(to.x - pos.x), -(to.z - pos.z))
		add_child(node)
		node.add_child(Geo.cylinder(PAD_RADIUS + 0.1, PAD_RADIUS + 0.2, 0.12, 32).mesh_instance(base_m, Vector3(0, 0.06, 0)))
		# visible coil under the top
		node.add_child(Geo.torus(PAD_RADIUS * 0.7, 0.05, 6, 32).mesh_instance(spring_m, Vector3(0, 0.15, 0), Basis(Vector3.RIGHT, PI / 2)))
		var top := Node3D.new()
		top.position = Vector3(0, 0.2, 0)
		top.add_child(Geo.cylinder(PAD_RADIUS, PAD_RADIUS, 0.06, 32).mesh_instance(top_m))
		node.add_child(top)
		var ring := Geo.torus(PAD_RADIUS + 0.05, 0.04, 6, 40).mesh_instance(ring_m, Vector3(0, 0.3, 0), Basis(Vector3.RIGHT, PI / 2), false)
		node.add_child(ring)
		pads.append({"pos": pos, "to": to, "top": top, "ring": ring, "squash": 0.0})
	var cable_m := Mats.plastic("#2b2d42", {"rough": 0.5, "clearcoat": 0.0})
	var post_m := Mats.plastic("#ff7b00", {"rough": 0.4})
	var cap_m := Mats.plastic("#ffd23f", {"rough": 0.35})
	for s in zip_list:
		var a: Vector3 = s.a
		var b: Vector3 = s.b
		var ca := a + Vector3(0, CABLE_UP, 0)
		var cb := b + Vector3(0, CABLE_UP, 0)
		var len := ca.distance_to(cb)
		var d := (cb - ca) / maxf(0.01, len)
		zips.append({"a": a, "b": b, "ca": ca, "cb": cb, "len": len, "d": d})
		# cable
		add_child(Geo.cylinder(0.035, 0.035, len, 6).mesh_instance(cable_m, (ca + cb) / 2, _y_to(d), false))
		# end posts (from the feet point up past the cable) with a pulley cap
		for e in [[ca, a], [cb, b]]:
			var top: Vector3 = e[0]
			var foot: Vector3 = e[1]
			var h := top.y - foot.y + 0.4
			add_child(Geo.cylinder(0.09, 0.11, h, 10).mesh_instance(post_m, Vector3(top.x, foot.y + h / 2, top.z)))
			add_child(Geo.cylinder(0.16, 0.16, 0.12, 14).mesh_instance(cap_m, top, Basis(Vector3.RIGHT, PI / 2) * Basis(Vector3.UP, 0)))


## Drop a point onto whatever surface is just below it (pads sit on the floor / furniture they're placed on).
func _snap(p: Vector3) -> Vector3:
	var d := phys.ray_dist(p + Vector3(0, 1.5, 0), Vector3.DOWN, 6.0, true)
	if d == INF:
		return p
	return Vector3(p.x, p.y + 1.5 - d, p.z)


## Basis whose +Y points along d (for cylinders laid between two points).
static func _y_to(d: Vector3) -> Basis:
	var up := Vector3.UP
	var c := up.cross(d)
	if c.length() < 1e-5:
		return Basis() if d.y > 0 else Basis(Vector3.RIGHT, PI)
	return Basis(c.normalized(), up.angle_to(d))


# ------------------------------------------------------------------ nav
## Special links for the bots: pads one way (pad -> landing), ziplines both ways.
func link_nav(nav: NavGraph) -> int:
	var n := 0
	for i in pads.size():
		var p: Dictionary = pads[i]
		if nav.add_special(p.pos, p.to, "pad", i, 6.0 + (p.to as Vector3).distance_to(p.pos) * 0.3, false):
			n += 1
		else:
			push_warning("[nav] jump pad %d not linked" % i)
	for i in zips.size():
		var z: Dictionary = zips[i]
		if nav.add_special(z.a, z.b, "zip", i, 4.0 + z.len * 0.45, true):
			n += 1
		else:
			push_warning("[nav] zipline %d not linked" % i)
	return n


func views() -> Dictionary:
	return {"pads": pads, "zips": zips}


# ------------------------------------------------------------------ ziplines
## Where on line i the rider is when they hang from parameter t.
func cable_point(i: int, t: float) -> Vector3:
	var z: Dictionary = zips[i]
	return (z.ca as Vector3).lerp(z.cb, t)


## The zipline (index, t) within reach of these eyes, or [-1, 0].
func nearest_zip(eye: Vector3, look: Vector3) -> Array:
	var best := -1
	var best_t := 0.0
	var best_d := REACH
	for i in zips.size():
		var z: Dictionary = zips[i]
		var ca: Vector3 = z.ca
		var t := clampf((eye - ca).dot(z.d) / z.len, MARGIN / z.len, 1 - MARGIN / z.len)
		var p := ca.lerp(z.cb, t)
		var dist := eye.distance_to(p)
		# must be roughly above or in front of you, not behind
		var to := p - eye
		if dist < best_d and (to.dot(look) > -0.3 * dist or to.y > 0.3):
			best = i
			best_t = t
			best_d = dist
	return [best, best_t]


## Hook an actor onto line i at t, riding toward the end its look direction points at (or toward `toward`).
func attach(a: Actor, i: int, t: float, look: Vector3, now: float) -> void:
	var z: Dictionary = zips[i]
	var dir := 1 if look.dot(z.d) >= 0 else -1
	a.start_zip(i, z.ca, z.cb, t, dir, MARGIN, now)
	uses.zip += 1
	if audio:
		audio.zip_grab(a.pos + Vector3(0, 2, 0))


## Bots: grab line i from the end nearest `from` and ride to the other end.
func attach_from(a: Actor, i: int, from: Vector3, now: float) -> void:
	var z: Dictionary = zips[i]
	var from_a: bool = from.distance_to(z.a) <= from.distance_to(z.b)
	var t: float = MARGIN / z.len if from_a else 1 - MARGIN / z.len
	a.start_zip(i, z.ca, z.cb, t, 1 if from_a else -1, MARGIN, now)
	uses.zip += 1
	if audio and a.pos.distance_to(audio._listener) < 40:
		audio.zip_grab(a.pos + Vector3(0, 2, 0))


# ------------------------------------------------------------------ pads
## Launch velocity from p0 that lands on p1 (arc peaking PAD_APEX above the higher end).
static func launch_velocity(p0: Vector3, p1: Vector3) -> Vector3:
	var g: float = Cfg.MOVE.gravity
	var apex := maxf(p0.y, p1.y) + PAD_APEX
	var vy := sqrt(2 * g * (apex - p0.y))
	var t := vy / g + sqrt(2 * maxf(0.0, apex - p1.y) / g)
	return Vector3((p1.x - p0.x) / t, vy, (p1.z - p0.z) / t)


func update(dt: float, now: float, actors: Array, _listener: Vector3) -> void:
	_t += dt
	for p in pads:
		var pos: Vector3 = p.pos
		for a in actors:
			if not a.alive or a.zip != null:
				continue
			var dy: float = a.pos.y - pos.y
			if dy < -0.3 or dy > 0.5 or Vector2(a.pos.x - pos.x, a.pos.z - pos.z).length() > PAD_RADIUS:
				continue
			if now < _cool.get(a, -1.0) or a.vel.y > 2:
				continue
			_cool[a] = now + PAD_COOLDOWN
			a.launch(launch_velocity(a.pos, p.to))
			p.squash = 1.0
			uses.pad += 1
			if audio:
				audio.jump_pad(pos + Vector3(0, 0.4, 0))
			if fx:
				fx.pickup_sparkle(pos + Vector3(0, 0.3, 0), "#ffd23f")
		# squash + pulsing ring
		p.squash = maxf(0, p.squash - dt * 4)
		var s: float = 1 - 0.5 * sin(p.squash * PI)
		(p.top as Node3D).scale = Vector3(1, maxf(0.3, s), 1)
		(p.top as Node3D).position.y = 0.2 - 0.08 * (1 - s)
		var k := fmod(_t * 0.9 + pos.x * 0.05, 1.0)
		var ring := p.ring as MeshInstance3D
		ring.position.y = 0.25 + k * 0.9
		ring.scale = Vector3.ONE * (1 - k * 0.25)
		ring.transparency = k

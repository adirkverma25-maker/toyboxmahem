class_name WeaponModel
extends Node3D
## Procedural toy weapon models (port of src/weapons/WeaponModels.ts). Barrel points down -Z, grip near the origin.
## Named parts drive the reload / fire animations: mag, charge, gear, gear2, chamber, spring, bolt, pump, drum,
## spin, wheel, core, rings, needle, pistons, shroud, holo, indicator, crayon...

var parts := {}
var muzzle := Node3D.new()
var right_grip := Vector3.ZERO
var left_grip := Vector3.ZERO
## where the sight sits relative to the model origin
var ads_offset := Vector3.ZERO
## part name -> Transform3D at rest
var rest := {}
var indicator_mat: StandardMaterial3D = null
var holo: Dictionary = {}
## real-gun models: realistic reload choreography, spent casings, slide lock
var real := false
## casing thrown from the ejection port when firing: "", "pistol", "rifle" or "shell"
var casing := ""
var eject: Node3D = null
## the rounds showing at the top of the magazine (hidden on an empty mag that gets dropped)
var rounds: Node3D = null
## direction the magazine comes out (model space), from the mag's own down axis
var mag_dir := Vector3.DOWN
## the charging handle / slide moves back with every shot and locks back when empty
var charge_cycles := false
## where shells are pushed in, for tube-fed guns loaded one at a time
var shell_port := Vector3.ZERO
## bolt action: the bolt cycles after each shot
var bolt_action := false

static var _seam_mat: StandardMaterial3D


static func rb(w: float, h: float, d: float, r := 0.015) -> Geo:
	return Geo.rounded_box(w, h, d, 2, minf(minf(r, w / 2.01), minf(h / 2.01, d / 2.01)))


## Cylinder along z.
static func cyl(r: float, length: float, seg := 16, r2 := -1.0) -> Geo:
	return Geo.cylinder(r if r2 < 0 else r2, r, length, seg).rotate_basis(Basis(Vector3.RIGHT, PI / 2))


static func m(g: Geo, mat: Material, p := Vector3.ZERO, r := Vector3.ZERO) -> MeshInstance3D:
	var o := MeshInstance3D.new()
	o.mesh = g.to_mesh()
	o.material_override = mat
	o.transform = Transform3D(U.euler(r.x, r.y, r.z), p)
	o.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return o


static func gear(radius: float, mat: Material, teeth := 8) -> Node3D:
	var g := Node3D.new()
	g.add_child(m(Geo.cylinder(radius, radius, 0.012, 16), mat, Vector3.ZERO, Vector3(0, 0, PI / 2)))
	for i in teeth:
		var a := float(i) / teeth * TAU
		g.add_child(m(Geo.box(0.012, radius * 0.45, radius * 0.35), mat, Vector3(0, cos(a) * radius, sin(a) * radius), Vector3(a, 0, 0)))
	return g


static func helix(length: float, radius: float, coils: int, thick: float) -> Geo:
	var pts := []
	for i in coils * 12 + 1:
		var t := float(i) / (coils * 12)
		var a := t * coils * TAU
		pts.append(Vector3(cos(a) * radius, sin(a) * radius, -t * length))
	return Geo.tube(pts, coils * 12, thick, 6)


static func seam(length: float) -> Geo:
	return Geo.box(0.003, 0.003, length)


static func seam_mat() -> StandardMaterial3D:
	if _seam_mat == null:
		_seam_mat = StandardMaterial3D.new()
		_seam_mat.albedo_color = Color(0, 0, 0, 0.35)
		_seam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_seam_mat.roughness = 1
	return _seam_mat


## three's transparent MeshPhysicalMaterial (glassy plastic).
static func glass(color: String, opacity: float, depth_write := true) -> StandardMaterial3D:
	var g := StandardMaterial3D.new()
	var c := U.col(color)
	c.a = opacity
	g.albedo_color = c
	g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	g.roughness = 0.05
	g.clearcoat_enabled = true
	g.clearcoat = 1
	if not depth_write:
		g.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return g


static func emissive(color: String, e: String, ei: float) -> StandardMaterial3D:
	var s := StandardMaterial3D.new()
	s.albedo_color = U.col(color)
	s.emission_enabled = true
	s.emission = U.col(e)
	s.emission_energy_multiplier = ei
	return s


static func star_shape(outer: float, inner: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := float(i) / 10 * TAU + PI / 2
		var r := inner if i % 2 else outer
		pts.append(Vector2(cos(a) * r, sin(a) * r))
	return pts


func _finalize(muzzle_p: Vector3, right: Vector3, left: Vector3, ads: Vector3) -> void:
	muzzle.position = muzzle_p
	add_child(muzzle)
	right_grip = right
	left_grip = left
	ads_offset = ads
	if parts.has("mag"):
		mag_dir = -(parts.mag as Node3D).transform.basis.y.normalized()
	for k in parts:
		rest[k] = (parts[k] as Node3D).transform


func _eject_at(p: Vector3) -> void:
	eject = Node3D.new()
	eject.position = p
	add_child(eject)

## Holographic ammo display (drawn on a little canvas).
class HoloCanvas extends Node2D:
	var value := 0
	var frac := 1.0

	func _draw() -> void:
		var col := Color("#ff7b9c") if frac < 0.25 else Color("#7ff9ff")
		Tex.text(self, Tex.FONT_BOLD, str(value), 64, 26, 34, col)
		draw_rect(Rect2(8, 52, 112 * frac, 6), col)
		draw_rect(Rect2(8, 52, 112, 6), Color(127 / 255.0, 249 / 255.0, 1, 0.6), false, 1)


static func build(id: String) -> WeaponModel:
	var w := WeaponModel.new()
	w.call("_b_" + id)
	return w


func _b_plasti9() -> void:
	# compact striker pistol: gunmetal slide, polymer frame, toy-teal grip panels and an orange safety tip
	var k := GunKit.new()
	var teal := GunKit.accent("#1fb5ad")
	var orange := GunKit.accent("#ff8c1a")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var dark := GunKit.mat("dark")
	k.add(self, poly, GunKit.box(0.064, 0.045, 0.34, 0.01), Vector3(0, 0.005, -0.13))
	k.add(self, poly, GunKit.rail(0.08, 0.03), Vector3(0, -0.022, -0.24), Vector3(PI, 0, 0))
	k.add(self, poly, Geo.torus(0.038, 0.007, 6, 16, PI), Vector3(0, -0.03, -0.055), Vector3(0, PI / 2, PI))
	k.add(self, gm, GunKit.box(0.01, 0.035, 0.01, 0.003), Vector3(0, -0.03, -0.045), Vector3(-0.25, 0, 0))
	k.add(self, poly, GunKit.box(0.062, 0.2, 0.09, 0.02), Vector3(0, -0.11, 0.06), Vector3(-0.28, 0, 0))
	for s in [-1.0, 1.0]:
		k.add(self, teal, GunKit.box(0.006, 0.12, 0.066, 0.003), Vector3(s * 0.032, -0.115, 0.062), Vector3(-0.28, 0, 0))
	k.add(self, poly, GunKit.box(0.058, 0.025, 0.05, 0.01), Vector3(0, -0.002, 0.075))
	# slide (moves back on every shot, locks open when empty)
	var slide := Node3D.new()
	add_child(slide)
	parts.charge = slide
	k.add(slide, gm, GunKit.box(0.07, 0.068, 0.4, 0.012), Vector3(0, 0.062, -0.16))
	for s in [-1.0, 1.0]:
		k.add(slide, dark, GunKit.ridges(7, 0.05, 0.009), Vector3(s * 0.035, 0.062, 0.03))
		k.add(slide, dark, GunKit.ridges(4, 0.04, 0.009), Vector3(s * 0.035, 0.062, -0.27))
	k.add(slide, GunKit.mat("port"), GunKit.box(0.022, 0.012, 0.075, 0.002), Vector3(0.022, 0.094, -0.1))
	k.add(slide, GunKit.mat("brass"), GunKit.box(0.016, 0.008, 0.05, 0.002), Vector3(0.016, 0.094, -0.1))
	k.add(slide, gm, GunKit.box(0.05, 0.02, 0.018, 0.003), Vector3(0, 0.103, 0.025))
	k.add(slide, gm, GunKit.box(0.012, 0.02, 0.012, 0.003), Vector3(0, 0.103, -0.33))
	k.add(slide, GunKit.mat("dot"), Geo.sphere(0.0035, 8, 6), Vector3(0, 0.11, -0.337))
	for s in [-1.0, 1.0]:
		k.add(slide, GunKit.mat("dot"), Geo.sphere(0.0035, 8, 6), Vector3(s * 0.014, 0.108, 0.015))
	k.add(slide, orange, GunKit.box(0.072, 0.07, 0.014, 0.01), Vector3(0, 0.062, -0.357))
	k.add(slide, GunKit.mat("port"), GunKit.tube(0.011, 0.016), Vector3(0, 0.055, -0.358))
	# magazine in the grip, two rounds showing at the top
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.12, 0.062)
	mag.rotation = Vector3(-0.28, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, poly, GunKit.box(0.048, 0.2, 0.066, 0.008))
	k.add(mag, teal, GunKit.box(0.056, 0.016, 0.078, 0.005), Vector3(0, -0.1, 0.002))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(0, 0.103, 0.022), 0.0065, 0.032)
	k.round_at(rounds, Vector3(0.0055, 0.092, 0.022), 0.0065, 0.032)
	k.bake()
	real = true
	casing = "pistol"
	charge_cycles = true
	_eject_at(Vector3(0.03, 0.094, -0.1))
	_finalize(Vector3(0, 0.055, -0.37), Vector3(0, -0.1, 0.07), Vector3(0, -0.13, 0.035), Vector3(0, -0.113, 0))


func _b_walloper() -> void:
	# hand cannon: stainless slide, dark frame, toy-purple grips, gold trigger / baseplate / compensator ring
	var k := GunKit.new()
	var purple := GunKit.accent("#7b2cbf")
	var gold := Mats.metal("#ffd23f", 0.25)
	var gm := GunKit.mat("gunmetal")
	var steel := GunKit.mat("steel")
	var dark := GunKit.mat("dark")
	k.add(self, gm, GunKit.box(0.075, 0.05, 0.4, 0.012), Vector3(0, 0.0, -0.18))
	k.add(self, gm, GunKit.rail(0.1, 0.034), Vector3(0, -0.028, -0.3), Vector3(PI, 0, 0))
	k.add(self, gm, GunKit.box(0.07, 0.21, 0.1, 0.02), Vector3(0, -0.12, 0.08), Vector3(-0.25, 0, 0))
	for s in [-1.0, 1.0]:
		k.add(self, purple, GunKit.box(0.006, 0.15, 0.08, 0.003), Vector3(s * 0.036, -0.125, 0.08), Vector3(-0.25, 0, 0))
	k.add(self, gold, Geo.torus(0.045, 0.008, 6, 16, PI), Vector3(0, -0.035, -0.06), Vector3(0, PI / 2, PI))
	k.add(self, gold, GunKit.box(0.012, 0.035, 0.012, 0.003), Vector3(0, -0.035, -0.05), Vector3(-0.25, 0, 0))
	var slide := Node3D.new()
	add_child(slide)
	parts.charge = slide
	k.add(slide, steel, GunKit.box(0.08, 0.085, 0.5, 0.014), Vector3(0, 0.068, -0.2))
	for s in [-1.0, 1.0]:
		k.add(slide, dark, GunKit.ridges(8, 0.06, 0.01), Vector3(s * 0.04, 0.068, 0.03))
	k.add(slide, GunKit.mat("port"), GunKit.box(0.026, 0.014, 0.09, 0.002), Vector3(0.025, 0.106, -0.12))
	k.add(slide, GunKit.mat("brass"), GunKit.box(0.02, 0.01, 0.06, 0.002), Vector3(0.02, 0.106, -0.12))
	k.add(slide, gm, GunKit.box(0.05, 0.022, 0.02, 0.003), Vector3(0, 0.12, 0.03))
	k.add(slide, gm, GunKit.box(0.012, 0.022, 0.014, 0.003), Vector3(0, 0.12, -0.43))
	k.add(slide, GunKit.mat("dot"), Geo.sphere(0.004, 8, 6), Vector3(0, 0.128, -0.438))
	# barrel out front with a ported compensator
	k.add(self, steel, GunKit.tube(0.02, 0.1), Vector3(0, 0.07, -0.5))
	k.add(self, gm, GunKit.box(0.06, 0.06, 0.09, 0.008), Vector3(0, 0.07, -0.59))
	for i in 3:
		k.add(self, GunKit.mat("port"), GunKit.box(0.04, 0.006, 0.012, 0.001), Vector3(0, 0.1, -0.565 - i * 0.025))
	k.add(self, gold, GunKit.box(0.062, 0.062, 0.012, 0.008), Vector3(0, 0.07, -0.64))
	k.add(self, GunKit.mat("port"), GunKit.tube(0.013, 0.004), Vector3(0, 0.07, -0.647))
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.13, 0.085)
	mag.rotation = Vector3(-0.25, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, steel, GunKit.box(0.054, 0.2, 0.076, 0.008))
	k.add(mag, gold, GunKit.box(0.062, 0.018, 0.088, 0.006), Vector3(0, -0.1, 0.002))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(0, 0.104, 0.03), 0.0095, 0.05)
	k.bake()
	real = true
	casing = "pistol"
	charge_cycles = true
	_eject_at(Vector3(0.035, 0.105, -0.12))
	_finalize(Vector3(0, 0.07, -0.65), Vector3(0, -0.12, 0.09), Vector3(0, -0.15, 0.05), Vector3(0, -0.13, 0))


func _b_foamFury() -> void:
	# carbine: gunmetal receivers, toy-orange handguard, blue stock riser and baseplate, flip-up irons on the rail
	var k := GunKit.new()
	var orange := GunKit.accent("#ff7a1a")
	var blue := GunKit.accent("#2f6fe0")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	k.add(self, gm, GunKit.box(0.062, 0.06, 0.24, 0.008), Vector3(0, -0.025, -0.03))
	k.add(self, gm, GunKit.box(0.068, 0.07, 0.09, 0.008), Vector3(0, -0.06, -0.12))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.075, -0.02))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.06, -0.025), Vector3(-0.2, 0, 0))
	k.add(self, gm, GunKit.box(0.066, 0.06, 0.3, 0.008), Vector3(0, 0.035, -0.06))
	k.add(self, gm, GunKit.rail(0.3), Vector3(0, 0.069, -0.06))
	k.add(self, port, GunKit.box(0.004, 0.026, 0.08, 0.001), Vector3(0.033, 0.03, -0.08))
	k.add(self, gm, GunKit.box(0.006, 0.01, 0.08, 0.001), Vector3(0.036, 0.012, -0.08))
	k.add(self, gm, GunKit.tube(0.01, 0.04), Vector3(0.036, 0.045, 0.035))
	# handguard with slots and a full-length top rail
	k.add(self, orange, GunKit.box(0.07, 0.07, 0.33, 0.02), Vector3(0, 0.03, -0.375))
	for s in [-1.0, 1.0]:
		for i in 4:
			k.add(self, port, GunKit.box(0.004, 0.012, 0.035, 0.002), Vector3(s * 0.035, 0.03, -0.27 - i * 0.065))
	k.add(self, gm, GunKit.rail(0.32), Vector3(0, 0.069, -0.375))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.012, 0.11), Vector3(0, 0.03, -0.595))
	k.add(self, gm, GunKit.tube(0.018, 0.045, 8), Vector3(0, 0.03, -0.66))
	k.add(self, GunKit.mat("tip"), GunKit.tube(0.019, 0.012, 8), Vector3(0, 0.03, -0.685))
	# flip-up sights on the sight line (y 0.13)
	k.add(self, gm, GunKit.box(0.03, 0.05, 0.02, 0.004), Vector3(0, 0.1, -0.52))
	k.add(self, gm, GunKit.box(0.006, 0.03, 0.006, 0.002), Vector3(0, 0.125, -0.52))
	k.add(self, gm, GunKit.box(0.036, 0.04, 0.025, 0.004), Vector3(0, 0.095, 0.06))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.127, 0.06))
	# grip, buffer tube, stock, foregrip
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.11, 0.075), Vector3(-0.32, 0, 0))
	k.add(self, gm, GunKit.tube(0.02, 0.2), Vector3(0, 0.025, 0.19))
	k.add(self, poly, GunKit.box(0.06, 0.1, 0.16, 0.015), Vector3(0, 0.0, 0.26))
	k.add(self, blue, GunKit.box(0.062, 0.022, 0.11, 0.008), Vector3(0, 0.055, 0.25))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.062, 0.12, 0.02, 0.008), Vector3(0, -0.005, 0.345))
	k.add(self, poly, GunKit.box(0.035, 0.08, 0.035, 0.012), Vector3(0, -0.035, -0.36))
	# charging handle (pulled at the end of a reload) and the bolt carrier showing in the port
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.05, 0.012, 0.022, 0.004), Vector3(0, 0.062, 0.1))
	var bcg := Node3D.new()
	add_child(bcg)
	parts.bcg = bcg
	k.add(bcg, GunKit.mat("steel"), GunKit.box(0.003, 0.018, 0.06, 0.001), Vector3(0.032, 0.03, -0.08))
	# curved magazine with ribs, blue baseplate and two rounds on top
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.13, -0.12)
	mag.rotation = Vector3(0.1, 0, 0)
	add_child(mag)
	parts.mag = mag
	var poly2 := GunKit.mat("polymer2")
	k.add(mag, poly2, GunKit.box(0.05, 0.11, 0.08, 0.008), Vector3(0, 0.045, 0))
	k.add(mag, poly2, GunKit.box(0.05, 0.11, 0.08, 0.008), Vector3(0, -0.05, -0.012), Vector3(0.18, 0, 0))
	for s in [-1.0, 1.0]:
		for i in 3:
			k.add(mag, GunKit.mat("dark"), GunKit.box(0.003, 0.004, 0.06, 0.001), Vector3(s * 0.026, 0.05 - i * 0.045, -0.004 * i))
	k.add(mag, blue, GunKit.box(0.056, 0.016, 0.09, 0.006), Vector3(0, -0.108, -0.022), Vector3(0.18, 0, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(-0.007, 0.103, 0.028), 0.0055, 0.045)
	k.round_at(rounds, Vector3(0.007, 0.094, 0.028), 0.0055, 0.045)
	k.bake()
	real = true
	casing = "rifle"
	_eject_at(Vector3(0.036, 0.03, -0.08))
	_finalize(Vector3(0, 0.03, -0.69), Vector3(0, -0.1, 0.075), Vector3(0, -0.07, -0.36), Vector3(0, -0.128, 0))


func _b_popcornPopper() -> void:
	# bullpup burst carbine: long polymer shell, toy-yellow butt panels, red tip and baseplate, mag behind the grip
	var k := GunKit.new()
	var yellow := GunKit.accent("#ffd23f")
	var red := GunKit.accent("#e63946")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	k.add(self, poly, GunKit.box(0.07, 0.11, 0.62, 0.016), Vector3(0, 0.0, -0.02))
	for s in [-1.0, 1.0]:
		k.add(self, yellow, GunKit.box(0.004, 0.06, 0.18, 0.003), Vector3(s * 0.036, 0.0, 0.18))
	k.add(self, GunKit.mat("port"), GunKit.box(0.004, 0.024, 0.07, 0.001), Vector3(0.036, 0.03, 0.14))
	k.add(self, gm, GunKit.rail(0.42), Vector3(0, 0.064, -0.06))
	k.add(self, gm, GunKit.box(0.036, 0.04, 0.025, 0.004), Vector3(0, 0.095, 0.12))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.127, 0.12))
	k.add(self, gm, GunKit.box(0.03, 0.04, 0.02, 0.004), Vector3(0, 0.093, -0.25))
	k.add(self, gm, GunKit.box(0.006, 0.03, 0.006, 0.002), Vector3(0, 0.122, -0.25))
	k.add(self, gm, GunKit.box(0.06, 0.06, 0.16, 0.01), Vector3(0, 0.005, -0.4))
	for s in [-1.0, 1.0]:
		for i in 3:
			k.add(self, GunKit.mat("port"), GunKit.box(0.004, 0.012, 0.03, 0.002), Vector3(s * 0.031, 0.005, -0.35 - i * 0.045))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.012, 0.1), Vector3(0, 0.01, -0.52))
	k.add(self, gm, GunKit.tube(0.017, 0.04, 8), Vector3(0, 0.01, -0.575))
	k.add(self, red, GunKit.tube(0.018, 0.012, 8), Vector3(0, 0.01, -0.6))
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.06), Vector3(-0.3, 0, 0))
	k.add(self, poly, GunKit.box(0.012, 0.008, 0.12, 0.003), Vector3(0, -0.065, 0.0))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.05, 0.0), Vector3(-0.2, 0, 0))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.072, 0.115, 0.02, 0.008), Vector3(0, 0.0, 0.3))
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.024, 0.014, 0.02, 0.004), Vector3(-0.045, 0.04, -0.22))
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.12, 0.19)
	mag.rotation = Vector3(0.1, 0, 0)
	add_child(mag)
	parts.mag = mag
	var poly2 := GunKit.mat("polymer2")
	k.add(mag, poly2, GunKit.box(0.05, 0.1, 0.075, 0.008), Vector3(0, 0.04, 0))
	k.add(mag, poly2, GunKit.box(0.05, 0.1, 0.075, 0.008), Vector3(0, -0.045, -0.01), Vector3(0.16, 0, 0))
	k.add(mag, red, GunKit.box(0.056, 0.016, 0.084, 0.006), Vector3(0, -0.097, -0.018), Vector3(0.16, 0, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(-0.007, 0.093, 0.026), 0.0055, 0.045)
	k.round_at(rounds, Vector3(0.007, 0.084, 0.026), 0.0055, 0.045)
	k.bake()
	real = true
	casing = "rifle"
	_eject_at(Vector3(0.037, 0.03, 0.14))
	_finalize(Vector3(0, 0.01, -0.61), Vector3(0, -0.1, 0.07), Vector3(0, -0.06, -0.38), Vector3(0, -0.128, 0))


func _b_brickbreaker() -> void:
	# battle rifle: one-piece gunmetal upper, toy-yellow side panels / cheek / baseplate, big muzzle brake
	var k := GunKit.new()
	var yellow := GunKit.accent("#ffcc00")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	k.add(self, gm, GunKit.box(0.072, 0.075, 0.5, 0.01), Vector3(0, 0.025, -0.17))
	k.add(self, gm, GunKit.rail(0.5), Vector3(0, 0.067, -0.17))
	k.add(self, poly, GunKit.box(0.066, 0.055, 0.2, 0.01), Vector3(0, -0.035, -0.02))
	k.add(self, poly, GunKit.box(0.07, 0.06, 0.09, 0.01), Vector3(0, -0.065, -0.11))
	k.add(self, poly, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.08, -0.01))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.065, -0.015), Vector3(-0.2, 0, 0))
	for s in [-1.0, 1.0]:
		k.add(self, yellow, GunKit.box(0.004, 0.034, 0.22, 0.003), Vector3(s * 0.037, 0.01, -0.3))
		for i in 5:
			k.add(self, port, GunKit.box(0.004, 0.01, 0.025, 0.002), Vector3(s * 0.037, 0.045, -0.22 - i * 0.04))
	k.add(self, port, GunKit.box(0.004, 0.028, 0.09, 0.001), Vector3(0.037, 0.025, -0.05))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.014, 0.14), Vector3(0, 0.025, -0.49))
	k.add(self, gm, GunKit.box(0.045, 0.036, 0.07, 0.006), Vector3(0, 0.025, -0.6))
	for i in 3:
		for s in [-1.0, 1.0]:
			k.add(self, port, GunKit.box(0.004, 0.022, 0.012, 0.001), Vector3(s * 0.023, 0.025, -0.578 - i * 0.02))
	k.add(self, GunKit.mat("tip"), GunKit.box(0.047, 0.038, 0.012, 0.005), Vector3(0, 0.025, -0.64))
	# sights on the sight line (y 0.125)
	k.add(self, gm, GunKit.box(0.036, 0.04, 0.025, 0.004), Vector3(0, 0.092, 0.05))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.122, 0.05))
	k.add(self, gm, GunKit.box(0.03, 0.04, 0.02, 0.004), Vector3(0, 0.09, -0.4))
	k.add(self, gm, GunKit.box(0.006, 0.03, 0.006, 0.002), Vector3(0, 0.115, -0.4))
	# grip and folding stock
	k.add(self, poly, GunKit.box(0.056, 0.15, 0.078, 0.016), Vector3(0, -0.115, 0.095), Vector3(-0.32, 0, 0))
	k.add(self, poly, GunKit.box(0.055, 0.11, 0.2, 0.015), Vector3(0, -0.005, 0.2))
	k.add(self, yellow, GunKit.box(0.057, 0.02, 0.12, 0.007), Vector3(0, 0.055, 0.19))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.057, 0.125, 0.02, 0.008), Vector3(0, -0.01, 0.305))
	# side charging handle (left) and the bolt in the port
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.03, 0.014, 0.018, 0.004), Vector3(-0.05, 0.04, -0.22))
	var bcg := Node3D.new()
	add_child(bcg)
	parts.bcg = bcg
	k.add(bcg, GunKit.mat("steel"), GunKit.box(0.003, 0.02, 0.07, 0.001), Vector3(0.036, 0.025, -0.05))
	# straight 20-round magazine
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.14, -0.11)
	mag.rotation = Vector3(0.06, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.056, 0.19, 0.085, 0.008))
	for s in [-1.0, 1.0]:
		for i in 4:
			k.add(mag, GunKit.mat("dark"), GunKit.box(0.003, 0.005, 0.07, 0.001), Vector3(s * 0.029, 0.06 - i * 0.04, 0))
	k.add(mag, yellow, GunKit.box(0.062, 0.016, 0.092, 0.006), Vector3(0, -0.1, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(-0.008, 0.1, 0.03), 0.0068, 0.055)
	k.round_at(rounds, Vector3(0.008, 0.09, 0.03), 0.0068, 0.055)
	k.bake()
	real = true
	casing = "rifle"
	_eject_at(Vector3(0.038, 0.025, -0.05))
	_finalize(Vector3(0, 0.025, -0.65), Vector3(0, -0.1, 0.095), Vector3(0, -0.055, -0.3), Vector3(0, -0.123, 0))


func _b_bubbleBlaster() -> void:
	# pump shotgun: gunmetal receiver and tube, toy-purple pump and stock, pink end cap; still blows bubbles
	var k := GunKit.new()
	var purple := GunKit.accent("#9b5de5")
	var pink := GunKit.accent("#f15bb5")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	k.add(self, gm, GunKit.box(0.066, 0.08, 0.24, 0.012), Vector3(0, 0.02, -0.04))
	k.add(self, port, GunKit.box(0.004, 0.026, 0.07, 0.001), Vector3(0.034, 0.03, -0.04))
	k.add(self, port, GunKit.box(0.03, 0.004, 0.09, 0.001), Vector3(0, -0.02, -0.06))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.017, 0.42), Vector3(0, 0.04, -0.37))
	k.add(self, gm, GunKit.box(0.012, 0.006, 0.4, 0.002), Vector3(0, 0.059, -0.37))
	k.add(self, GunKit.mat("dot"), Geo.sphere(0.005, 8, 6), Vector3(0, 0.066, -0.565))
	k.add(self, gm, GunKit.tube(0.016, 0.36), Vector3(0, 0.0, -0.34))
	k.add(self, pink, GunKit.tube(0.019, 0.025), Vector3(0, 0.0, -0.53))
	k.add(self, pink, GunKit.tube(0.02, 0.012), Vector3(0, 0.04, -0.585))
	k.add(self, gm, GunKit.box(0.04, 0.06, 0.02, 0.006), Vector3(0, 0.02, -0.5))
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.09), Vector3(-0.3, 0, 0))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.035, 0.03))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.02, 0.03), Vector3(-0.2, 0, 0))
	k.add(self, purple, GunKit.box(0.055, 0.11, 0.2, 0.02), Vector3(0, -0.01, 0.2))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.058, 0.12, 0.022, 0.008), Vector3(0, -0.01, 0.31))
	var pump := Node3D.new()
	add_child(pump)
	parts.pump = pump
	k.add(pump, purple, GunKit.box(0.055, 0.05, 0.16, 0.016), Vector3(0, 0.005, -0.33))
	for s in [-1.0, 1.0]:
		k.add(pump, GunKit.mat("dark"), GunKit.ridges(7, 0.03, 0.02), Vector3(s * 0.028, 0.005, -0.27))
	k.bake()
	real = true
	casing = "shell"
	shell_port = Vector3(0, -0.022, -0.06)
	_eject_at(Vector3(0.035, 0.03, -0.04))
	_finalize(Vector3(0, 0.04, -0.59), Vector3(0, -0.1, 0.085), Vector3(0, -0.035, -0.33), Vector3(0, -0.067, 0))


func _b_thunderspring() -> void:
	# bolt-action sniper: toy-cobalt chassis, gunmetal action, long steel barrel with a brake, gold bolt knob
	var k := GunKit.new()
	var cobalt := GunKit.accent("#1f4fd1")
	var gold := Mats.metal("#f2c94c", 0.25)
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	k.add(self, cobalt, GunKit.box(0.06, 0.06, 0.32, 0.016), Vector3(0, -0.01, -0.36))
	k.add(self, gm, GunKit.tube(0.026, 0.27), Vector3(0, 0.035, -0.06))
	k.add(self, cobalt, GunKit.box(0.062, 0.05, 0.3, 0.012), Vector3(0, -0.005, -0.05))
	k.add(self, cobalt, GunKit.box(0.06, 0.11, 0.24, 0.016), Vector3(0, -0.02, 0.2))
	k.add(self, gold, GunKit.box(0.062, 0.02, 0.12, 0.006), Vector3(0, 0.045, 0.2))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.062, 0.12, 0.022, 0.008), Vector3(0, -0.02, 0.33))
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.085), Vector3(-0.3, 0, 0))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.045, 0.02), Vector3(-0.2, 0, 0))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.016, 0.6, 16, 0.012), Vector3(0, 0.035, -0.5))
	k.add(self, gm, GunKit.box(0.04, 0.035, 0.07, 0.006), Vector3(0, 0.035, -0.83))
	for i in 3:
		k.add(self, GunKit.mat("port"), GunKit.box(0.042, 0.016, 0.01, 0.001), Vector3(0, 0.035, -0.81 - i * 0.02))
	k.add(self, GunKit.mat("tip"), GunKit.box(0.042, 0.037, 0.012, 0.005), Vector3(0, 0.035, -0.87))
	k.add(self, gm, GunKit.rail(0.22), Vector3(0, 0.066, -0.07))
	# scope (hidden when a small optic is fitted instead)
	var scope := Node3D.new()
	add_child(scope)
	parts.scope = scope
	var sc := GunKit.mat("dark")
	k.add(scope, sc, GunKit.tube(0.022, 0.32), Vector3(0, 0.13, -0.08))
	k.add(scope, sc, GunKit.tube(0.034, 0.08, 16, 0.022), Vector3(0, 0.13, -0.27))
	k.add(scope, sc, GunKit.tube(0.03, 0.06, 16, 0.022), Vector3(0, 0.13, 0.1))
	k.add(scope, gm, GunKit.tube(0.012, 0.025), Vector3(0, 0.158, -0.08), Vector3(PI / 2, 0, 0))
	k.add(scope, gm, GunKit.tube(0.012, 0.025), Vector3(0.028, 0.13, -0.08), Vector3(0, PI / 2, 0))
	for z in [-0.17, 0.02]:
		k.add(scope, gm, GunKit.box(0.05, 0.05, 0.02, 0.006), Vector3(0, 0.1, z))
	var lens := emissive("#ff4d6d", "#ff4d6d", 0.4)
	lens.roughness = 0.05
	k.add(scope, lens, Geo.circle(0.03, 16).rotate_basis(Basis(Vector3.UP, PI)), Vector3(0, 0.13, -0.312))
	# bolt: handle on the right, knob in gold (rotates up, back, forward, down after each shot)
	var ch := Node3D.new()
	ch.position = Vector3(0, 0.035, 0)
	add_child(ch)
	parts.charge = ch
	k.add(ch, GunKit.mat("steel"), GunKit.tube(0.017, 0.07), Vector3(0, 0, 0.05))
	k.add(ch, GunKit.mat("steel"), GunKit.tube(0.006, 0.05), Vector3(0.035, 0, 0.04), Vector3(0, PI / 2, 0))
	k.add(ch, gold, Geo.sphere(0.014, 10, 8), Vector3(0.062, 0, 0.04))
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.07, -0.09)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.045, 0.08, 0.1, 0.008))
	k.add(mag, gold, GunKit.box(0.05, 0.014, 0.106, 0.005), Vector3(0, -0.044, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(0, 0.045, 0.04), 0.007, 0.075)
	k.bake()
	real = true
	casing = "rifle"
	bolt_action = true
	_eject_at(Vector3(0.03, 0.05, -0.02))
	_finalize(Vector3(0, 0.035, -0.88), Vector3(0, -0.1, 0.085), Vector3(0, -0.06, -0.4), Vector3(0, -0.13, 0.05))


func _b_rapidRascal() -> void:
	# compact SMG: boxy polymer receiver, toy-green panels, pink tip and baseplate, wire stock
	var k := GunKit.new()
	var green := GunKit.accent("#39ff88")
	var pink := GunKit.accent("#ff4fd8")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var steel := GunKit.mat("steel")
	k.add(self, poly, GunKit.box(0.07, 0.085, 0.34, 0.012), Vector3(0, 0.01, -0.12))
	k.add(self, gm, GunKit.rail(0.2), Vector3(0, 0.057, -0.09))
	for s in [-1.0, 1.0]:
		k.add(self, green, GunKit.box(0.004, 0.04, 0.12, 0.003), Vector3(s * 0.036, 0.0, -0.21))
	k.add(self, GunKit.mat("port"), GunKit.box(0.004, 0.022, 0.06, 0.001), Vector3(0.036, 0.03, -0.05))
	k.add(self, gm, GunKit.tube(0.02, 0.06), Vector3(0, 0.01, -0.32))
	k.add(self, steel, GunKit.tube(0.011, 0.07), Vector3(0, 0.01, -0.38))
	k.add(self, pink, GunKit.tube(0.016, 0.014), Vector3(0, 0.01, -0.42))
	# hooded front post and a rear aperture drum on the sight line (y 0.11)
	k.add(self, gm, GunKit.box(0.012, 0.03, 0.012, 0.003), Vector3(0, 0.085, -0.26))
	k.add(self, gm, Geo.torus(0.018, 0.003, 6, 16, PI), Vector3(0, 0.09, -0.26))
	k.add(self, gm, GunKit.box(0.03, 0.035, 0.03, 0.006), Vector3(0, 0.075, 0.025))
	k.add(self, gm, Geo.torus(0.007, 0.0025, 6, 14), Vector3(0, 0.106, 0.025))
	# grip with built-in trigger guard, vertical foregrip
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.07), Vector3(-0.3, 0, 0))
	k.add(self, poly, GunKit.box(0.05, 0.012, 0.1, 0.004), Vector3(0, -0.06, 0.0))
	k.add(self, gm, GunKit.box(0.01, 0.028, 0.01, 0.003), Vector3(0, -0.045, 0.01), Vector3(-0.2, 0, 0))
	k.add(self, poly, GunKit.box(0.038, 0.075, 0.04, 0.014), Vector3(0, -0.07, -0.2))
	# folding wire stock
	for s in [-1.0, 1.0]:
		k.add(self, steel, GunKit.tube(0.006, 0.22), Vector3(s * 0.026, 0.015, 0.16))
	k.add(self, poly, GunKit.box(0.065, 0.09, 0.016, 0.006), Vector3(0, 0.0, 0.27))
	k.add(self, pink, GunKit.box(0.066, 0.06, 0.008, 0.003), Vector3(0, 0.0, 0.28))
	# side cocking handle
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.02, 0.012, 0.03, 0.004), Vector3(-0.045, 0.035, -0.19))
	# straight stick magazine
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.12, -0.09)
	mag.rotation = Vector3(0.05, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.045, 0.18, 0.058, 0.007))
	k.add(mag, pink, GunKit.box(0.05, 0.015, 0.066, 0.005), Vector3(0, -0.095, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(-0.006, 0.095, 0.018), 0.0062, 0.03)
	k.round_at(rounds, Vector3(0.006, 0.085, 0.018), 0.0062, 0.03)
	k.bake()
	real = true
	casing = "pistol"
	_eject_at(Vector3(0.037, 0.03, -0.05))
	_finalize(Vector3(0, 0.01, -0.43), Vector3(0, -0.1, 0.07), Vector3(0, -0.12, -0.2), Vector3(0, -0.108, 0))


func _b_crayonCannon() -> void:
	# semi-auto grenade launcher: fat toy-red barrel, gunmetal receiver, box mag of crayon-tipped grenades
	var k := GunKit.new()
	var red := GunKit.accent("#e63946")
	var yellow := GunKit.accent("#ffd23f")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	k.add(self, gm, GunKit.box(0.08, 0.1, 0.3, 0.014), Vector3(0, 0.02, -0.02))
	k.add(self, red, GunKit.tube(0.045, 0.36, 20), Vector3(0, 0.04, -0.35))
	k.add(self, yellow, GunKit.tube(0.049, 0.02, 20), Vector3(0, 0.04, -0.52))
	k.add(self, GunKit.mat("port"), GunKit.tube(0.036, 0.004, 20), Vector3(0, 0.04, -0.531))
	for i in 4:
		k.add(self, GunKit.mat("dark"), GunKit.tube(0.047, 0.006, 20), Vector3(0, 0.04, -0.24 - i * 0.05))
	k.add(self, gm, GunKit.box(0.07, 0.03, 0.25, 0.008), Vector3(0, -0.02, -0.32))
	k.add(self, poly, GunKit.box(0.04, 0.08, 0.045, 0.014), Vector3(0, -0.07, -0.3))
	# leaf sight + front post on the sight line (y 0.125)
	k.add(self, gm, GunKit.box(0.04, 0.05, 0.008, 0.002), Vector3(0, 0.1, -0.08))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.122, -0.08))
	k.add(self, gm, GunKit.box(0.01, 0.04, 0.01, 0.002), Vector3(0, 0.105, -0.45))
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.07), Vector3(-0.3, 0, 0))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.04, 0.01))
	k.add(self, poly, GunKit.box(0.06, 0.1, 0.2, 0.016), Vector3(0, 0.0, 0.22))
	k.add(self, yellow, GunKit.box(0.062, 0.02, 0.12, 0.007), Vector3(0, 0.055, 0.21))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.062, 0.115, 0.022, 0.008), Vector3(0, 0.0, 0.33))
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.03, 0.016, 0.02, 0.004), Vector3(0.05, 0.04, -0.1))
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.13, -0.1)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.075, 0.17, 0.1, 0.01))
	k.add(mag, GunKit.mat("dark"), GunKit.box(0.003, 0.12, 0.02, 0.001), Vector3(0.039, 0, 0))
	k.add(mag, yellow, GunKit.box(0.08, 0.018, 0.106, 0.006), Vector3(0, -0.09, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.add(rounds, GunKit.mat("brass"), GunKit.tube(0.03, 0.04), Vector3(0, 0.09, 0.02))
	k.add(rounds, GunKit.accent("#06d6a0"), Geo.cone(0.03, 0.05, 14).rotate_basis(Basis(Vector3.RIGHT, -PI / 2)), Vector3(0, 0.09, -0.025))
	k.bake()
	real = true
	_finalize(Vector3(0, 0.04, -0.55), Vector3(0, -0.1, 0.075), Vector3(0, -0.11, -0.3), Vector3(0, -0.123, 0))


func _b_starlightZapper() -> void:
	# energy carbine: grey polymer with white shell panels, glowing core in the battery, cyan rings at the emitter
	var k := GunKit.new()
	var white := GunKit.accent("#f2f7ff")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var poly2 := GunKit.mat("polymer2")
	k.add(self, poly2, GunKit.box(0.07, 0.09, 0.4, 0.014), Vector3(0, 0.01, -0.08))
	for s in [-1.0, 1.0]:
		k.add(self, white, GunKit.box(0.005, 0.06, 0.3, 0.004), Vector3(s * 0.036, 0.01, -0.1))
	k.add(self, gm, GunKit.rail(0.3), Vector3(0, 0.064, -0.08))
	k.add(self, gm, GunKit.box(0.036, 0.04, 0.025, 0.004), Vector3(0, 0.088, 0.06))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.118, 0.06))
	k.add(self, gm, GunKit.box(0.03, 0.04, 0.02, 0.004), Vector3(0, 0.088, -0.28))
	k.add(self, gm, GunKit.box(0.006, 0.026, 0.006, 0.002), Vector3(0, 0.113, -0.28))
	k.add(self, gm, GunKit.box(0.05, 0.05, 0.18, 0.01), Vector3(0, 0.01, -0.36))
	for s in [-1.0, 1.0]:
		for i in 4:
			k.add(self, GunKit.mat("port"), GunKit.box(0.004, 0.03, 0.012, 0.001), Vector3(s * 0.026, 0.01, -0.3 - i * 0.035))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.014, 0.08), Vector3(0, 0.01, -0.48))
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.1, 0.08), Vector3(-0.3, 0, 0))
	k.add(self, poly, GunKit.box(0.04, 0.075, 0.045, 0.014), Vector3(0, -0.06, -0.2))
	k.add(self, poly, GunKit.box(0.05, 0.08, 0.18, 0.014), Vector3(0, -0.005, 0.23))
	k.add(self, white, GunKit.box(0.052, 0.09, 0.02, 0.008), Vector3(0, -0.005, 0.32))
	# battery pack under the receiver: glass window with the glowing core
	k.add(self, poly2, GunKit.box(0.06, 0.06, 0.16, 0.01), Vector3(0, -0.06, -0.04))
	k.bake()
	add_child(m(Geo.capsule(0.022, 0.1, 6, 12), glass("#d6fbff", 0.35, false), Vector3(0.0, -0.06, -0.04), Vector3(PI / 2, 0, 0)))
	var core := m(Geo.capsule(0.014, 0.09, 6, 10), Mats.glow("#5ff4ff", 3), Vector3(0.0, -0.06, -0.04), Vector3(PI / 2, 0, 0))
	add_child(core)
	parts.core = core
	var arcs := Node3D.new()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	line_mat.albedo_color = Color(U.col("#bffcff"), 0.9)
	for i in 3:
		var pts := PackedVector3Array()
		for j in 6:
			pts.append(Vector3((randf() - 0.5) * 0.02, (randf() - 0.5) * 0.02, -j * 0.02))
		var am := ArrayMesh.new()
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pts
		am.add_surface_from_arrays(Mesh.PRIMITIVE_LINE_STRIP, arr)
		var li := MeshInstance3D.new()
		li.mesh = am
		li.material_override = line_mat
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		arcs.add_child(li)
	arcs.position = Vector3(0, -0.06, 0.01)
	add_child(arcs)
	parts.arcs = arcs
	var rings := Node3D.new()
	rings.position = Vector3(0, 0.01, -0.47)
	for i in 3:
		rings.add_child(m(Geo.torus(0.03, 0.005, 8, 24), Mats.glow("#21e6ff", 2.2), Vector3(0, 0, i * 0.035), Vector3(0, 0, i * 0.4)))
	add_child(rings)
	parts.rings = rings
	var vp := SubViewport.new()
	vp.size = Vector2i(128, 64)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var hc := HoloCanvas.new()
	vp.add_child(hc)
	add_child(vp)
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.cull_mode = BaseMaterial3D.CULL_DISABLED
	hm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	hm.albedo_texture = vp.get_texture()
	hm.albedo_color = Color(1, 1, 1, 0.9)
	var plane := m(Geo.plane(0.1, 0.05), hm, Vector3(0.06, 0.07, 0.0), Vector3(0, PI / 2 - 0.4, 0))
	add_child(plane)
	parts.holo = plane
	holo = {"vp": vp, "canvas": hc, "last": -1}
	real = true
	_finalize(Vector3(0, 0.01, -0.52), Vector3(0, -0.1, 0.08), Vector3(0, -0.1, -0.2), Vector3(0, -0.118, 0))


func _b_jackBlaster() -> void:
	# mag-fed semi-auto shotgun: gunmetal receiver, toy-red handguard, yellow baseplate and butt pad
	var k := GunKit.new()
	var red := GunKit.accent("#e63946")
	var yellow := GunKit.accent("#ffd23f")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	k.add(self, gm, GunKit.box(0.07, 0.085, 0.3, 0.012), Vector3(0, 0.02, -0.06))
	k.add(self, gm, GunKit.rail(0.2), Vector3(0, 0.067, -0.03))
	k.add(self, port, GunKit.box(0.004, 0.03, 0.08, 0.001), Vector3(0.036, 0.03, -0.05))
	k.add(self, red, GunKit.box(0.076, 0.075, 0.2, 0.02), Vector3(0, 0.01, -0.31))
	for s in [-1.0, 1.0]:
		for i in 3:
			k.add(self, port, GunKit.box(0.004, 0.014, 0.03, 0.002), Vector3(s * 0.038, 0.012, -0.25 - i * 0.055))
	k.add(self, gm, GunKit.tube(0.013, 0.2), Vector3(0, 0.055, -0.31))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.02, 0.17), Vector3(0, 0.01, -0.495))
	k.add(self, gm, GunKit.tube(0.026, 0.05, 12), Vector3(0, 0.01, -0.585))
	for i in 3:
		k.add(self, port, GunKit.box(0.054, 0.006, 0.01, 0.001), Vector3(0, 0.01, -0.57 - i * 0.015))
	k.add(self, GunKit.mat("tip"), GunKit.tube(0.027, 0.012, 12), Vector3(0, 0.01, -0.615))
	# sights on the sight line (y 0.13)
	k.add(self, gm, GunKit.box(0.04, 0.03, 0.03, 0.005), Vector3(0, 0.075, -0.42))
	k.add(self, gm, GunKit.box(0.008, 0.04, 0.008, 0.002), Vector3(0, 0.105, -0.42))
	k.add(self, GunKit.mat("dot"), Geo.sphere(0.004, 8, 6), Vector3(0, 0.126, -0.424))
	k.add(self, gm, GunKit.box(0.036, 0.045, 0.02, 0.004), Vector3(0, 0.095, 0.02))
	# grip, trigger, skeleton stock with a yellow pad
	k.add(self, poly, GunKit.box(0.056, 0.15, 0.078, 0.016), Vector3(0, -0.11, 0.1), Vector3(-0.32, 0, 0))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.035, 0.03))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.02, 0.03), Vector3(-0.2, 0, 0))
	k.add(self, poly, GunKit.box(0.055, 0.1, 0.22, 0.016), Vector3(0, -0.005, 0.2))
	k.add(self, yellow, GunKit.box(0.058, 0.115, 0.024, 0.008), Vector3(0, -0.01, 0.315))
	# reciprocating charging handle on the right
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.03, 0.014, 0.014, 0.004), Vector3(0.05, 0.035, -0.02))
	# box magazine of shells
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.1, -0.12)
	mag.rotation = Vector3(0.08, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.062, 0.16, 0.11, 0.01))
	for s in [-1.0, 1.0]:
		k.add(mag, GunKit.mat("dark"), GunKit.box(0.003, 0.11, 0.004, 0.001), Vector3(s * 0.032, 0, 0.03))
	k.add(mag, yellow, GunKit.box(0.068, 0.016, 0.118, 0.006), Vector3(0, -0.085, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(0, 0.088, 0.035), 0.013, 0.07, true)
	k.bake()
	real = true
	casing = "shell"
	charge_cycles = true
	_eject_at(Vector3(0.038, 0.03, -0.05))
	_finalize(Vector3(0, 0.01, -0.62), Vector3(0, -0.1, 0.095), Vector3(0, -0.06, -0.31), Vector3(0, -0.128, 0))


func _b_sizzler() -> void:
	# semi-auto tube shotgun: gunmetal receiver, toy-orange heat shield, an ember-glowing muzzle, shells on the side
	var k := GunKit.new()
	var orange := GunKit.accent("#ff5a1f")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	k.add(self, gm, GunKit.box(0.068, 0.075, 0.26, 0.012), Vector3(0, 0.02, -0.05))
	k.add(self, gm, GunKit.rail(0.2), Vector3(0, 0.062, -0.05))
	k.add(self, port, GunKit.box(0.03, 0.004, 0.1, 0.001), Vector3(0, -0.018, -0.1))
	k.add(self, port, GunKit.box(0.004, 0.028, 0.07, 0.001), Vector3(0.035, 0.03, -0.06))
	k.add(self, gm, GunKit.tube(0.017, 0.3), Vector3(0, -0.01, -0.33))
	k.add(self, orange, GunKit.tube(0.02, 0.03), Vector3(0, -0.01, -0.495))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.016, 0.42), Vector3(0, 0.035, -0.39))
	k.add(self, orange, GunKit.box(0.046, 0.02, 0.3, 0.008), Vector3(0, 0.056, -0.36))
	for i in 6:
		k.add(self, port, GunKit.box(0.03, 0.004, 0.022, 0.002), Vector3(0, 0.0665, -0.24 - i * 0.045))
	k.add(self, GunKit.mat("ember"), GunKit.tube(0.02, 0.015), Vector3(0, 0.035, -0.605))
	k.add(self, port, GunKit.tube(0.012, 0.004), Vector3(0, 0.035, -0.613))
	k.add(self, poly, GunKit.box(0.06, 0.055, 0.2, 0.015), Vector3(0, 0.0, -0.33))
	for s in [-1.0, 1.0]:
		k.add(self, GunKit.mat("dark"), GunKit.ridges(8, 0.03, 0.02), Vector3(s * 0.031, 0.0, -0.26))
	k.add(self, gm, GunKit.box(0.05, 0.065, 0.02, 0.006), Vector3(0, 0.015, -0.47))
	# ghost-ring rear sight and a lit front post on the sight line (y 0.12)
	k.add(self, gm, GunKit.box(0.04, 0.035, 0.02, 0.004), Vector3(0, 0.085, 0.03))
	k.add(self, gm, Geo.torus(0.011, 0.003, 6, 16), Vector3(0, 0.118, 0.03))
	k.add(self, gm, GunKit.box(0.01, 0.035, 0.012, 0.003), Vector3(0, 0.07, -0.56))
	k.add(self, GunKit.mat("dot"), Geo.sphere(0.0045, 8, 6), Vector3(0, 0.091, -0.565))
	# grip, trigger, stock
	k.add(self, poly, GunKit.box(0.056, 0.15, 0.078, 0.016), Vector3(0, -0.105, 0.1), Vector3(-0.32, 0, 0))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.04, 0.03))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.025, 0.03), Vector3(-0.2, 0, 0))
	k.add(self, gm, GunKit.tube(0.016, 0.18), Vector3(0, 0.02, 0.17))
	k.add(self, poly, GunKit.box(0.055, 0.1, 0.14, 0.016), Vector3(0, 0.0, 0.25))
	k.add(self, orange, GunKit.box(0.057, 0.02, 0.1, 0.007), Vector3(0, 0.052, 0.24))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.057, 0.115, 0.02, 0.008), Vector3(0, -0.005, 0.33))
	# spare shells in a side saddle (left)
	for i in 4:
		k.round_at(self, Vector3(-0.046, 0.02, 0.0 - i * 0.032), 0.012, 0.065, true)
	# bolt handle (right): cycles with every shot, locks back when empty
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.026, 0.012, 0.012, 0.004), Vector3(0.048, 0.025, -0.06))
	k.add(ch, GunKit.mat("steel"), GunKit.box(0.003, 0.02, 0.05, 0.001), Vector3(0.034, 0.03, -0.06))
	k.bake()
	real = true
	casing = "shell"
	charge_cycles = true
	shell_port = Vector3(0, -0.025, -0.1)
	_eject_at(Vector3(0.036, 0.03, -0.06))
	_finalize(Vector3(0, 0.035, -0.62), Vector3(0, -0.1, 0.095), Vector3(0, -0.04, -0.33), Vector3(0, -0.12, 0))


func _b_tumbleweed() -> void:
	# long-range AR: full-length gunmetal rails, long fluted barrel with a brake, toy-sky-blue handguard / stock
	# panels and a flip-up rear sight; mid-length magwell with a curved 30-round mag
	var k := GunKit.new()
	var sky := GunKit.accent("#4cc9f0")
	var gm := GunKit.mat("gunmetal")
	var poly := GunKit.mat("polymer")
	var port := GunKit.mat("port")
	var steel := GunKit.mat("steel")
	k.add(self, gm, GunKit.box(0.062, 0.058, 0.26, 0.008), Vector3(0, -0.025, -0.03))
	k.add(self, gm, GunKit.box(0.068, 0.07, 0.09, 0.008), Vector3(0, -0.06, -0.12))
	k.add(self, gm, GunKit.box(0.012, 0.008, 0.09, 0.003), Vector3(0, -0.075, -0.02))
	k.add(self, gm, GunKit.box(0.01, 0.03, 0.01, 0.003), Vector3(0, -0.06, -0.025), Vector3(-0.2, 0, 0))
	k.add(self, gm, GunKit.box(0.066, 0.06, 0.32, 0.008), Vector3(0, 0.035, -0.07))
	k.add(self, gm, GunKit.rail(0.62), Vector3(0, 0.069, -0.2))
	k.add(self, port, GunKit.box(0.004, 0.026, 0.08, 0.001), Vector3(0.033, 0.03, -0.08))
	k.add(self, gm, GunKit.tube(0.01, 0.04), Vector3(0.036, 0.045, 0.04))
	# long free-float handguard with slots
	k.add(self, sky, GunKit.box(0.062, 0.062, 0.46, 0.014), Vector3(0, 0.032, -0.44))
	for s in [-1.0, 1.0]:
		for i in 6:
			k.add(self, port, GunKit.box(0.004, 0.012, 0.035, 0.002), Vector3(s * 0.031, 0.032, -0.28 - i * 0.065))
	k.add(self, GunKit.mat("steel"), GunKit.tube(0.011, 0.14), Vector3(0, 0.032, -0.74))
	k.add(self, gm, GunKit.box(0.04, 0.034, 0.07, 0.006), Vector3(0, 0.032, -0.82))
	for i in 3:
		for s in [-1.0, 1.0]:
			k.add(self, port, GunKit.box(0.004, 0.02, 0.012, 0.001), Vector3(s * 0.021, 0.032, -0.8 - i * 0.02))
	k.add(self, GunKit.mat("tip"), GunKit.box(0.042, 0.036, 0.012, 0.005), Vector3(0, 0.032, -0.86))
	# sights on the sight line (y 0.13): a folding rear aperture and a tall front post
	k.add(self, gm, GunKit.box(0.034, 0.04, 0.022, 0.004), Vector3(0, 0.096, 0.06))
	k.add(self, gm, Geo.torus(0.008, 0.003, 6, 14), Vector3(0, 0.128, 0.06))
	k.add(self, gm, GunKit.box(0.03, 0.05, 0.02, 0.004), Vector3(0, 0.1, -0.7))
	k.add(self, gm, GunKit.box(0.006, 0.04, 0.006, 0.002), Vector3(0, 0.13, -0.7))
	k.add(self, GunKit.mat("dot"), Geo.sphere(0.003, 8, 6), Vector3(0, 0.152, -0.7))
	# grip, buffer tube, cheek-riser stock
	k.add(self, poly, GunKit.box(0.055, 0.15, 0.075, 0.016), Vector3(0, -0.11, 0.075), Vector3(-0.32, 0, 0))
	k.add(self, gm, GunKit.tube(0.02, 0.2), Vector3(0, 0.025, 0.19))
	k.add(self, poly, GunKit.box(0.06, 0.1, 0.18, 0.015), Vector3(0, 0.0, 0.27))
	k.add(self, sky, GunKit.box(0.062, 0.022, 0.12, 0.008), Vector3(0, 0.055, 0.26))
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.062, 0.12, 0.02, 0.008), Vector3(0, -0.005, 0.355))
	k.add(self, poly, GunKit.box(0.035, 0.08, 0.035, 0.012), Vector3(0, -0.035, -0.4))
	var ch := Node3D.new()
	add_child(ch)
	parts.charge = ch
	k.add(ch, gm, GunKit.box(0.05, 0.012, 0.022, 0.004), Vector3(0, 0.062, 0.1))
	var bcg := Node3D.new()
	add_child(bcg)
	parts.bcg = bcg
	k.add(bcg, steel, GunKit.box(0.003, 0.018, 0.06, 0.001), Vector3(0.032, 0.03, -0.08))
	# short straight 12-round mag (small capacity, hits hard)
	var mag := Node3D.new()
	mag.position = Vector3(0, -0.125, -0.12)
	mag.rotation = Vector3(0.05, 0, 0)
	add_child(mag)
	parts.mag = mag
	k.add(mag, GunKit.mat("polymer2"), GunKit.box(0.05, 0.075, 0.08, 0.008))
	for s2 in [-1.0, 1.0]:
		for i2 in 2:
			k.add(mag, GunKit.mat("dark"), GunKit.box(0.003, 0.004, 0.06, 0.001), Vector3(s2 * 0.026, 0.015 - i2 * 0.03, 0))
	k.add(mag, sky, GunKit.box(0.056, 0.016, 0.09, 0.006), Vector3(0, -0.045, 0))
	rounds = Node3D.new()
	rounds.name = "rounds"
	mag.add_child(rounds)
	k.round_at(rounds, Vector3(-0.007, 0.038, 0.028), 0.0055, 0.05)
	k.round_at(rounds, Vector3(0.007, 0.03, 0.028), 0.0055, 0.05)
	k.bake()
	real = true
	casing = "rifle"
	_eject_at(Vector3(0.036, 0.03, -0.08))
	_finalize(Vector3(0, 0.032, -0.87), Vector3(0, -0.1, 0.075), Vector3(0, -0.07, -0.42), Vector3(0, -0.13, 0))


func _limb(sign: float, teal: Material, pink: Material) -> Node3D:
	var grp := Node3D.new()
	grp.position = Vector3(0, sign * 0.15, 0)
	for x in [-0.012, 0.012]:
		var pts := [Vector3(x, 0, 0), Vector3(x, sign * 0.08, 0.03), Vector3(x, sign * 0.15, 0.085)]
		grp.add_child(m(Geo.tube(pts, 12, 0.009, 6), teal))
	var tip := Vector3(0, sign * 0.155, 0.09)
	grp.add_child(m(Geo.cylinder(0.03, 0.03, 0.012, 18), GunKit.mat("gunmetal"), tip, Vector3(0, 0, PI / 2)))
	grp.add_child(m(Geo.torus(0.03, 0.004, 6, 18), pink, tip, Vector3(0, PI / 2, 0)))
	grp.set_meta("tip", tip + Vector3(0, 0, 0.03))
	add_child(grp)
	return grp


func _b_plungerBow() -> void:
	# compound bow: machined gunmetal riser, toy-teal split limbs on cams, sight pins, stabilizer, plunger arrows
	var gm := GunKit.mat("gunmetal")
	var pink := Mats.plastic("#ff4d6d", {"rough": 0.3})
	var teal := Mats.plastic("#2ec4b6", {"rough": 0.3})
	var k := GunKit.new()
	k.add(self, GunKit.mat("rubber"), GunKit.box(0.032, 0.1, 0.05, 0.014))
	k.add(self, gm, GunKit.box(0.028, 0.17, 0.035, 0.008), Vector3(0, 0.11, -0.025), Vector3(0.25, 0, 0))
	k.add(self, gm, GunKit.box(0.028, 0.17, 0.035, 0.008), Vector3(0, -0.11, -0.025), Vector3(-0.25, 0, 0))
	for sg in [-1.0, 1.0]:
		k.add(self, GunKit.mat("port"), GunKit.box(0.03, 0.06, 0.012, 0.004), Vector3(0, sg * 0.11, -0.03), Vector3(sg * 0.25, 0, 0))
		k.add(self, gm, GunKit.box(0.036, 0.03, 0.04, 0.008), Vector3(0, sg * 0.15, 0.0))
	k.add(self, gm, Geo.torus(0.024, 0.004, 6, 18), Vector3(-0.035, 0.06, -0.07))
	k.add(self, gm, GunKit.box(0.006, 0.006, 0.05, 0.002), Vector3(-0.022, 0.06, -0.045))
	for i in 3:
		k.add(self, GunKit.mat("dot"), Geo.sphere(0.0035, 8, 6), Vector3(-0.035, 0.07 - i * 0.01, -0.07))
	k.add(self, GunKit.mat("polymer"), GunKit.tube(0.01, 0.22), Vector3(0, -0.06, -0.15))
	k.add(self, pink, GunKit.tube(0.018, 0.03), Vector3(0, -0.06, -0.275))
	k.add(self, teal, GunKit.box(0.02, 0.012, 0.03, 0.004), Vector3(-0.028, 0.035, -0.005))
	k.bake()
	parts.limbU = _limb(1, teal, pink)
	parts.limbL = _limb(-1, teal, pink)
	var str_mat := Mats.plastic("#f8f9fa", {"rough": 0.6, "clearcoat": 0.0})
	var s_geo := Geo.cylinder(0.003, 0.003, 1, 5).translate(0, 0.5, 0)
	var su := m(s_geo, str_mat)
	var sl := m(s_geo, str_mat)
	add_child(su)
	add_child(sl)
	parts.stringU = su
	parts.stringL = sl
	var nock := Node3D.new()
	nock.position = Vector3(0, 0, 0.15)
	add_child(nock)
	parts.nock = nock
	# carbon arrow with teal vanes and the pink plunger cup
	var arrow := Node3D.new()
	arrow.position = Vector3(0, 0.035, 0.15)
	arrow.add_child(m(cyl(0.006, 0.66), GunKit.mat("dark"), Vector3(0, 0, -0.33)))
	arrow.add_child(m(Geo.cylinder(0.035, 0.012, 0.035, 14).rotate_basis(Basis(Vector3.RIGHT, PI / 2)), pink, Vector3(0, 0, -0.67)))
	for r in [0.0, PI * 2 / 3, PI * 4 / 3]:
		arrow.add_child(m(rb(0.002, 0.022, 0.06, 0.001), teal, Vector3(0, 0, -0.05), Vector3(0, 0, r)))
	add_child(arrow)
	parts.arrow = arrow
	_finalize(Vector3(0, 0.035, -0.52), Vector3(0, -0.01, 0.17), Vector3(0, -0.02, 0), Vector3(0, -0.12, 0.12))
	aim_string(0)


## Bow: bend the limbs, pull the nock back and re-aim the two string segments. `draw` is 0..1.
func aim_string(draw: float) -> void:
	if not parts.has("limbU") or not parts.has("nock"):
		return
	var lu: Node3D = parts.limbU
	var ll: Node3D = parts.limbL
	var nock: Node3D = parts.nock
	lu.rotation.x = draw * 0.32
	ll.rotation.x = -draw * 0.32
	nock.position.z = 0.15 + draw * 0.3
	if parts.has("arrow"):
		(parts.arrow as Node3D).position.z = nock.position.z
	for pair in [[lu, parts.stringU], [ll, parts.stringL]]:
		var limb: Node3D = pair[0]
		var seg: Node3D = pair[1]
		var t1: Vector3 = limb.transform * (limb.get_meta("tip") as Vector3)
		var t2 := nock.position - t1
		var l := t2.length()
		seg.transform = Transform3D(U.from_up(t2 / l).scaled_local(Vector3(1, l, 1)), t1)


## Update the holo display / indicator to reflect ammo. Cheap: only redraws on change.
func update_ammo_indicator(frac: float, value: float) -> void:
	if indicator_mat:
		var ind: Node3D = parts.indicator
		ind.scale.z = maxf(0.02, frac)
		ind.position.z = -0.14 + (1 - frac) * 0.095
		indicator_mat.emission_energy_multiplier = 2.5 if frac < 0.25 else 1.6
		indicator_mat.albedo_color = U.col("#ff6b6b" if frac < 0.25 else "#7dfff3")
		indicator_mat.emission = U.col("#ff2e2e" if frac < 0.25 else "#29e3d6")
	if not holo.is_empty() and holo.last != roundi(value):
		holo.last = roundi(value)
		var hc: HoloCanvas = holo.canvas
		hc.value = holo.last
		hc.frac = frac
		hc.queue_redraw()
		(holo.vp as SubViewport).render_target_update_mode = SubViewport.UPDATE_ONCE


## Small optic that sits on the gun for the 'dot' and 'ring' scopes, centered on the gun's sight line.
static func build_optic(kind: String, sight_y: float, color: String, accent: String) -> Node3D:
	var o := Node3D.new()
	var body := Mats.plastic(color, {"rough": 0.3})
	var trim := Mats.plastic(accent, {"rough": 0.3})
	var r := 0.03 if kind == "dot" else 0.045
	o.add_child(m(Geo.torus(r, 0.007 if kind == "dot" else 0.006, 8, 28), body))
	var hood_mat := Mats.std(color, 0.4)
	hood_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	o.add_child(m(Geo.cylinder(r + 0.004, r + 0.004, 0.05 if kind == "dot" else 0.02, 24, 1, true), hood_mat, Vector3.ZERO, Vector3(PI / 2, 0, 0)))
	var lens := glass("#cfefff", 0.12, false)
	lens.cull_mode = BaseMaterial3D.CULL_DISABLED
	o.add_child(m(Geo.circle(r, 24), lens))
	# post down to the gun + two toy knobs
	o.add_child(m(Geo.box(0.022, 0.05, 0.04), trim, Vector3(0, -r - 0.02, 0)))
	for s in [-1, 1]:
		o.add_child(m(Geo.cylinder(0.01, 0.01, 0.014, 10), trim, Vector3(s * (r + 0.012), 0, 0), Vector3(0, 0, PI / 2)))
	o.position = Vector3(0, sight_y, 0)
	return o

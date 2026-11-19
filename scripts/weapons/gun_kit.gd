class_name GunKit
extends RefCounted
## Real-gun parts for the weapon models: shared finishes (gunmetal, polymer, steel, brass) and detailed pieces
## (rails, serrations, cartridges, ribbed mags). Geometry is collected per (node, material) and baked into one
## mesh each, so a detailed gun is still only a handful of draw calls.

static var _mats := {}
var _acc := {}


## Shared finishes. Toy accents use Mats.plastic(color) instead.
static func mat(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var mm: StandardMaterial3D
	match kind:
		"gunmetal": mm = Mats.std("#2c2f34", 0.4, 0.85)
		"steel": mm = Mats.std("#8f959c", 0.28, 0.95)
		"dark": mm = Mats.std("#121315", 0.6, 0.6)
		"polymer": mm = Mats.std("#1d1f22", 0.78, 0.0)
		"polymer2": mm = Mats.std("#3a3e44", 0.72, 0.0)
		"brass": mm = Mats.std("#c9a14a", 0.3, 1.0)
		"copper": mm = Mats.std("#b8683a", 0.35, 1.0)
		"hull": mm = Mats.std("#a51f27", 0.55, 0.0)
		"rubber": mm = Mats.std("#111214", 0.92, 0.0)
		"port": mm = Mats.std("#050506", 0.95, 0.0)
		"tip": mm = Mats.std("#ff6a00", 0.45, 0.0)
		"dot":
			mm = Mats.std("#f4fff0", 0.3, 0.0)
			mm.emission_enabled = true
			mm.emission = Color("#9dff8a")
			mm.emission_energy_multiplier = 1.4
		"ember":
			mm = Mats.std("#ff7a1a", 0.4, 0.0)
			mm.emission_enabled = true
			mm.emission = Color("#ff5a1f")
			mm.emission_energy_multiplier = 2.2
	mm.roughness_texture = Tex.scratch_roughness()
	mm.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	_mats[kind] = mm
	return mm


## Toy accent colour (glossy plastic), the bit that says "toy".
static func accent(color: String) -> Material:
	return Mats.plastic(color, {"rough": 0.3})


func add(node: Node3D, m: Material, g: Geo, p := Vector3.ZERO, r := Vector3.ZERO) -> void:
	var key := "%d|%d" % [node.get_instance_id(), m.get_instance_id()]
	if not _acc.has(key):
		_acc[key] = [node, m, Geo.new()]
	(_acc[key][2] as Geo).merge(g.transformed(Transform3D(U.euler(r.x, r.y, r.z), p)))


## Bake everything collected into one mesh per (node, material).
func bake() -> void:
	for k in _acc:
		var e: Array = _acc[k]
		var g: Geo = e[2]
		if g.v.is_empty():
			continue
		(e[0] as Node3D).add_child(WeaponModel.m(g, e[1]))
	_acc.clear()


# ------------------------------------------------------------------ shapes (all point down -Z)
static func box(w: float, h: float, d: float, r := 0.006) -> Geo:
	return WeaponModel.rb(w, h, d, r) if r > 0 else Geo.box(w, h, d)


static func tube(r: float, length: float, seg := 16, r2 := -1.0) -> Geo:
	return WeaponModel.cyl(r, length, seg, r2)


## Picatinny rail, centred on the origin: a base with cross slots every 1.6 cm.
static func rail(length: float, w := 0.034) -> Geo:
	var g := Geo.box(w * 0.8, 0.008, length)
	var n := int(length / 0.016)
	for i in n:
		g.merge(Geo.box(w, 0.007, 0.009).translate(0, 0.0075, -length / 2 + 0.008 + i * 0.016))
	return g


## Row of grip / slide serrations (thin ridges) on one side, spread along z.
static func ridges(count: int, h: float, spacing: float, thick := 0.004) -> Geo:
	var g := Geo.new()
	for i in count:
		g.merge(Geo.box(thick, h, 0.004).translate(0, 0, -i * spacing))
	return g


## A cartridge lying along -Z with its base at z=0: brass case + copper bullet. Returns [case, bullet].
static func cartridge(r: float, length: float) -> Array:
	var case_len := length * 0.68
	var c := tube(r, case_len, 10).translate(0, 0, -case_len / 2)
	c.merge(tube(r * 1.06, 0.004, 10).translate(0, 0, -0.002))  # rim
	var bl := length - case_len
	var b := Geo.lathe([Vector2(0, -bl), Vector2(r * 0.45, -bl * 0.85), Vector2(r * 0.82, -bl * 0.4), Vector2(r * 0.86, 0)], 10)
	b.rotate_basis(Basis(Vector3.RIGHT, PI / 2)).translate(0, 0, -case_len)
	return [c, b]


## Shotgun shell along -Z: red hull + brass head. Returns [hull, head].
static func shell(r: float, length: float) -> Array:
	var head := tube(r * 1.04, length * 0.28, 12).translate(0, 0, -length * 0.14)
	var hull := tube(r, length * 0.72, 12).translate(0, 0, -length * 0.28 - length * 0.36)
	return [hull, head]


## Add a cartridge (or shell) to `node` at p, pointing down -Z.
func round_at(node: Node3D, p: Vector3, r: float, length: float, is_shell := false) -> void:
	if is_shell:
		var s := shell(r, length)
		add(node, mat("hull"), s[0], p)
		add(node, mat("brass"), s[1], p)
	else:
		var c := cartridge(r, length)
		add(node, mat("brass"), c[0], p)
		add(node, mat("copper"), c[1], p)

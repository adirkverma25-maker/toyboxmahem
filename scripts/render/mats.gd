class_name Mats
## Materials (port of src/render/materials.ts). three's MeshStandard/Physical materials map to StandardMaterial3D.

static var _plastic := {}
static var _env: EnvMats


static func std(color = "#ffffff", rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = U.col(color)
	m.roughness = rough
	m.metallic = metal
	return m


## Glossy toy plastic with clearcoat and subtle scratches. opts: rough, emissive, emissive_intensity, clearcoat, metal
static func plastic(color, opts := {}) -> StandardMaterial3D:
	var col := U.col(color)
	var key := "%s|%s|%s|%s|%s|%s" % [col.to_html(), opts.get("rough", 0.38), opts.get("emissive", ""), opts.get("emissive_intensity", 0), opts.get("clearcoat", 0.6), opts.get("metal", 0)]
	if _plastic.has(key):
		return _plastic[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = opts.get("rough", 0.38)
	m.metallic = opts.get("metal", 0.0)
	m.metallic_specular = 0.5
	m.roughness_texture = Tex.scratch_roughness()
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	var cc: float = opts.get("clearcoat", 0.6)
	if cc > 0:
		m.clearcoat_enabled = true
		m.clearcoat = cc
		m.clearcoat_roughness = 0.25
	if opts.has("emissive") and float(opts.get("emissive_intensity", 0)) > 0:
		m.emission_enabled = true
		m.emission = U.col(opts.emissive)
		m.emission_energy_multiplier = opts.emissive_intensity
	_plastic[key] = m
	# static geometry batches every colour of the same plastic into one mesh (colour moves to vertex colours)
	m.set_meta("vc_key", key.substr(key.find("|")))
	return m


static var _vc_twins := {}


## The white, vertex-coloured twin of a plastic material (same look when the vertices carry its albedo colour).
static func vc_twin(mat: Material) -> Material:
	if not mat.has_meta("vc_key"):
		return mat
	var k: String = mat.get_meta("vc_key")
	if not _vc_twins.has(k):
		var t := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		t.remove_meta("vc_key")
		t.albedo_color = Color.WHITE
		t.vertex_color_use_as_albedo = true
		t.vertex_color_is_srgb = true
		_vc_twins[k] = t
	return _vc_twins[k]


static func translucent(color, opacity := 0.55, emissive = null, ei := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var c := U.col(color)
	c.a = opacity
	m.albedo_color = c
	m.roughness = 0.12
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.clearcoat_enabled = true
	m.clearcoat = 1.0
	m.cull_mode = BaseMaterial3D.CULL_BACK
	if emissive != null and ei > 0:
		m.emission_enabled = true
		m.emission = U.col(emissive)
		m.emission_energy_multiplier = ei
	return m


static func rubber(color) -> StandardMaterial3D:
	return std(color, 0.85, 0.0)


static func metal(color, rough := 0.25) -> StandardMaterial3D:
	return std(color, rough, 1.0)


static func glow(color, intensity := 2.0) -> StandardMaterial3D:
	var m := std(color, 0.4)
	m.emission_enabled = true
	m.emission = U.col(color)
	m.emission_energy_multiplier = intensity
	return m


## Unlit (three's MeshBasicMaterial).
static func basic(color = "#ffffff", tex: Texture2D = null, transparent := false, double_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = U.col(color)
	if tex:
		m.albedo_texture = tex
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func textured(tex: Texture2D, rough := 0.5, color = "#ffffff") -> StandardMaterial3D:
	var m := std(color, rough)
	m.albedo_texture = tex
	return m


static func fabric(color, seed: int, double_sided := true, strength := 0.8) -> StandardMaterial3D:
	var m := std(color, 0.95)
	m.normal_enabled = true
	m.normal_texture = Tex.fiber_bump(seed, 4)
	m.normal_scale = strength
	m.uv1_scale = Vector3(4, 4, 4)
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


static func env() -> EnvMats:
	if _env == null:
		_env = EnvMats.new()
	return _env


## Shared environment materials, created once.
class EnvMats:
	var floor: StandardMaterial3D
	var desk: StandardMaterial3D
	var bed_wood: StandardMaterial3D
	var block_wood: StandardMaterial3D
	var carpet: StandardMaterial3D
	var blanket: StandardMaterial3D
	var sheet: StandardMaterial3D
	var pillow: StandardMaterial3D
	var pillow2: StandardMaterial3D
	var cardboard: StandardMaterial3D
	var cardboard_toys: StandardMaterial3D
	var cardboard_shoes: StandardMaterial3D
	var wallpaper: StandardMaterial3D
	var ceiling: StandardMaterial3D
	var trim: StandardMaterial3D
	var closet_wall: StandardMaterial3D
	var fabric_a: StandardMaterial3D
	var fabric_b: StandardMaterial3D
	var fabric_c: StandardMaterial3D
	var fabric_d: StandardMaterial3D
	var rock: StandardMaterial3D
	var paper: StandardMaterial3D
	var metal_steel: StandardMaterial3D
	var glass: StandardMaterial3D

	func _init() -> void:
		floor = Mats.textured(Tex.wood("floor"), 0.55)
		desk = Mats.textured(Tex.wood("desk"), 0.45)
		bed_wood = Mats.textured(Tex.wood("bed"), 0.5)
		block_wood = Mats.textured(Tex.wood("block"), 0.55)
		carpet = Mats.textured(Tex.carpet(), 0.97)
		carpet.normal_enabled = true
		carpet.normal_texture = Tex.fiber_bump(3, 8)
		carpet.normal_scale = 0.8
		blanket = Mats.textured(Tex.quilt("#6c8fe0", "#f2a65a"), 0.95)
		blanket.cull_mode = BaseMaterial3D.CULL_DISABLED
		sheet = Mats.fabric("#f4f1ea", 9, false, 0.4)
		pillow = Mats.fabric("#ffe7ef", 10, false, 0.4)
		pillow2 = Mats.fabric("#d9ecff", 10, false, 0.4)
		cardboard = Mats.textured(Tex.cardboard(), 0.9)
		cardboard_toys = Mats.textured(Tex.cardboard("TOYS"), 0.9)
		cardboard_shoes = Mats.textured(Tex.cardboard("SHOES"), 0.9)
		wallpaper = Mats.textured(Tex.wallpaper(), 0.9)
		ceiling = Mats.std("#fbf6ee", 0.95)
		trim = Mats.std("#fffaf0", 0.5)
		closet_wall = Mats.std("#6f6a8a", 0.9)
		fabric_a = Mats.fabric("#c0485a", 12)
		fabric_b = Mats.fabric("#3f6fb0", 13)
		fabric_c = Mats.fabric("#e8c35a", 14)
		fabric_d = Mats.fabric("#5f9e6e", 15)
		rock = Mats.std("#8d8478", 0.8)
		rock.set_meta("flat", true)
		paper = Mats.std("#fbf8ef", 0.85)
		metal_steel = Mats.metal("#c9ced6", 0.3)
		glass = Mats.std("#d8f0ff", 0.05)
		glass.albedo_color.a = 0.25
		glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glass.clearcoat_enabled = true
		glass.clearcoat = 1.0

class_name Loadout
## The player's loadout (port of src/weapons/loadout.ts, reworked for classes): a class (Light / Medium), one
## blaster from that class, the scope chosen for each blaster, two abilities and (from the gadget update on) one
## gadget. Each class keeps its own picks. Saved with the settings.


static func _scope_map() -> Dictionary:
	var m = JSON.parse_string(str(Settings.get_v("scopes")))
	return m if m is Dictionary else {}


static func _prog() -> Node:
	return Engine.get_main_loop().root.get_node("Progress")


## Default picks per class (free starter blasters only).
const DEFAULTS := {
	"light": {"gun": "foamFury", "abilities": ["dash"], "gadget": "fragGrenade"},
	"medium": {"gun": "jackBlaster", "abilities": ["shield"], "gadget": "explosiveMine"},
}


## {class: {gun, abilities}}. The first time, it is built from the 1.1 loadout: your old main blaster decides
## your class and stays your blaster; Light keeps whichever of its abilities you had.
static func _data() -> Dictionary:
	var raw := str(Settings.get_v("loadouts"))
	var d = JSON.parse_string(raw) if raw != "" else null
	if d is Dictionary and d.has("light") and d.has("medium"):
		return d
	d = DEFAULTS.duplicate(true)
	var old_gun := str(Settings.get_v("primary"))
	var c := "light"
	if Cfg.WEAPONS.has(old_gun):
		c = Cfg.class_of_gun(old_gun)
		if _prog().owns(old_gun):
			d[c].gun = old_gun
	var ab := []
	for x in str(Settings.get_v("abilities")).split(","):
		if Cfg.CLASSES.light.abilities.has(x) and not ab.has(x):
			ab.append(x)
	for x in ["dash", "grapple"]:
		if ab.size() < 1 and not ab.has(x):
			ab.append(x)
	d.light.abilities = ab.slice(0, 1)
	Settings.set_v("loadouts", JSON.stringify(d))
	if str(Settings.get_v("class")) == "":
		Settings.set_v("class", c)
	return d


static func _save(d: Dictionary) -> void:
	Settings.set_v("loadouts", JSON.stringify(d))


## light | medium
static func cls() -> String:
	_data()
	var c := str(Settings.get_v("class"))
	return c if Cfg.CLASSES.has(c) else "light"


static func set_cls(c: String) -> void:
	if Cfg.CLASSES.has(c):
		_data()
		Settings.set_v("class", c)


## Everything a class can take as its one weapon: its blasters plus its melee weapon.
static func weapons(c: String) -> Array:
	return (Cfg.CLASSES[c].guns as Array) + [Cfg.CLASSES[c].melee]


## The one weapon for a class (default: the current class): a blaster or the class's melee weapon. Locked or
## wrong-class picks fall back to the class's starter, so a loadout can never hold something you can't carry.
static func gun(c := "") -> String:
	if c == "":
		c = cls()
	var g := str(_data()[c].get("gun", ""))
	if g == Cfg.CLASSES[c].melee:
		return g
	if Cfg.CLASSES[c].guns.has(g) and _prog().owns(g):
		return g
	return DEFAULTS[c].gun


static func set_gun(id: String) -> void:
	var c := cls()
	if id != Cfg.CLASSES[c].melee and (not Cfg.CLASSES[c].guns.has(id) or not _prog().owns(id)):
		return
	var d := _data()
	d[c].gun = id
	_save(d)


static func scope(id: String) -> String:
	var pick = _scope_map().get(id)
	var fits: Array = Cfg.WEAPON_SCOPES[id]
	return pick if pick is String and fits.has(pick) else fits[0]


static func set_scope(id: String, s: String) -> void:
	var m := _scope_map()
	m[id] = s
	Settings.set_v("scopes", JSON.stringify(m))


## The one ability for a class (default: the current one), as a one-item list.
## Lights: Wind-Up Dash or Spring Hook. Mediums: Mesh Shield or Cloak.
static func abilities(c := "") -> Array:
	if c == "":
		c = cls()
	var allowed: Array = Cfg.CLASSES[c].abilities
	for x in _data()[c].get("abilities", []):
		if allowed.has(x):
			return [x]
	return [DEFAULTS[c].abilities[0]]


static func set_ability(id: String) -> void:
	var c := cls()
	if not Cfg.CLASSES[c].abilities.has(id):
		return
	var d := _data()
	d[c].abilities = [id]
	_save(d)


## Gadgets a class can take right now (the rest of its list is still being made).
static func gadgets_ready(c: String) -> Array:
	return (Cfg.CLASSES[c].gadgets as Array).filter(func(g): return Cfg.GADGETS.has(g))


## The one gadget for a class (default: the current one).
static func gadget(c := "") -> String:
	if c == "":
		c = cls()
	var g := str(_data()[c].get("gadget", ""))
	return g if gadgets_ready(c).has(g) else DEFAULTS[c].gadget


static func set_gadget(id: String) -> void:
	var c := cls()
	if not gadgets_ready(c).has(id):
		return
	var d := _data()
	d[c].gadget = id
	_save(d)

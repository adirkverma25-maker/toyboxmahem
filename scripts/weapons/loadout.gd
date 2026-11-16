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
	"light": {"gun": "foamFury", "abilities": ["dash", "grapple"]},
	"medium": {"gun": "jackBlaster", "abilities": ["shield", "jab"]},
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
	for x in ["dash", "grapple", "cloak"]:
		if ab.size() < 2 and not ab.has(x):
			ab.append(x)
	d.light.abilities = ab.slice(0, 2)
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


## The blaster for a class (default: the current class). Locked or wrong-class picks fall back to the class's
## starter, so a loadout can never hold something you haven't unlocked or can't carry.
static func gun(c := "") -> String:
	if c == "":
		c = cls()
	var g := str(_data()[c].get("gun", ""))
	if Cfg.CLASSES[c].guns.has(g) and _prog().owns(g):
		return g
	return DEFAULTS[c].gun


static func set_gun(id: String) -> void:
	var c := cls()
	if not Cfg.CLASSES[c].guns.has(id) or not _prog().owns(id):
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


## The two equipped abilities for a class (default: the current one). Mediums always get Shield + Punch;
## Lights pick two of Dash, Spring Hook and Cloak.
static func abilities(c := "") -> Array:
	if c == "":
		c = cls()
	var allowed: Array = Cfg.CLASSES[c].abilities
	if not Cfg.CLASSES[c].pick_abilities:
		return allowed.slice(0, 2)
	var uniq := []
	for x in _data()[c].get("abilities", []):
		if allowed.has(x) and not uniq.has(x):
			uniq.append(x)
	for x in DEFAULTS[c].abilities + allowed:
		if uniq.size() < 2 and not uniq.has(x):
			uniq.append(x)
	return [uniq[0], uniq[1]]


## Put an ability in slot 0 or 1 (Light only). Picking the other slot's ability swaps them.
static func set_ability(slot: int, id: String) -> void:
	var c := cls()
	if not Cfg.CLASSES[c].pick_abilities or not Cfg.CLASSES[c].abilities.has(id):
		return
	var cur := abilities(c)
	var other: String = cur[1 - slot]
	var nxt := cur.duplicate()
	nxt[slot] = id
	if other == id:
		nxt[1 - slot] = cur[slot]
	var d := _data()
	d[c].abilities = nxt
	_save(d)


## The gadget (the gadget update adds them): none yet.
static func gadget(_c := "") -> String:
	return ""

class_name Loadout
## The player's loadout: two weapons picked in the menu plus the scope chosen for each weapon, and the two
## abilities (port of src/weapons/loadout.ts). Saved with the settings.


static func _scope_map() -> Dictionary:
	var m = JSON.parse_string(str(Settings.get_v("scopes")))
	return m if m is Dictionary else {}


static func _prog() -> Node:
	return Engine.get_main_loop().root.get_node("Progress")


## Locked weapons fall back to a starter, so a loadout can never hold something you haven't unlocked.
static func primary() -> String:
	var p: String = Settings.get_v("primary")
	return _prog().owned_or(p if Cfg.WEAPONS.has(p) else "foamFury", "foamFury")


static func secondary() -> String:
	var s0: String = Settings.get_v("secondary")
	var s: String = _prog().owned_or(s0 if Cfg.WEAPONS.has(s0) else "plasti9", "plasti9")
	var p := primary()
	if s == p:
		return "foamFury" if p == "plasti9" else "plasti9"
	return s


## Put a weapon in slot 0 (primary) or 1 (secondary). Picking the other slot's weapon swaps them.
static func set_weapon(slot: int, id: String) -> void:
	if not _prog().owns(id):
		return
	var p := primary()
	var s := secondary()
	if slot == 0:
		Settings.set_v("primary", id)
		if id == s:
			Settings.set_v("secondary", p)
	else:
		Settings.set_v("secondary", id)
		if id == p:
			Settings.set_v("primary", s)


static func scope(id: String) -> String:
	var pick = _scope_map().get(id)
	var fits: Array = Cfg.WEAPON_SCOPES[id]
	return pick if pick is String and fits.has(pick) else fits[0]


static func set_scope(id: String, s: String) -> void:
	var m := _scope_map()
	m[id] = s
	Settings.set_v("scopes", JSON.stringify(m))


## The two equipped abilities: [Ability 1, Ability 2].
static func abilities() -> Array:
	var uniq := []
	for x in str(Settings.get_v("abilities")).split(","):
		if Cfg.ABILITY_ORDER.has(x) and not uniq.has(x):
			uniq.append(x)
	for d in ["dash", "grapple", "jab"]:
		if uniq.size() < 2 and not uniq.has(d):
			uniq.append(d)
	return [uniq[0], uniq[1]]


## Put an ability in slot 0 or 1. Picking the other slot's ability swaps them.
static func set_ability(slot: int, id: String) -> void:
	var cur := abilities()
	var other: String = cur[1 - slot]
	var nxt := cur.duplicate()
	nxt[slot] = id
	if other == id:
		nxt[1 - slot] = cur[slot]
	Settings.set_v("abilities", ",".join(nxt))

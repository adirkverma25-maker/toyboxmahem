extends Node
## Dev tests for Light/Medium classes and the per-class loadout.
## Run: sh tools/test_classes.sh   -> prints "[test] N failures"

var failures := 0
var phys: Phys


class AudioStub extends RefCounted:
	func pickup(_k, _p, _l) -> void:
		pass


func _ready() -> void:
	await _run()
	print("[test] %d failures" % failures)
	get_tree().quit(failures)


func check(cond: bool, label: String) -> void:
	if cond:
		print("ok   ", label)
	else:
		failures += 1
		print("FAIL ", label)


func _actor() -> Actor:
	return Actor.new(Chars.CHARACTERS["captainClick"], false, phys)


func _run() -> void:
	phys = Phys.new()
	add_child(phys)
	var L: Dictionary = Cfg.CLASSES.light
	var M: Dictionary = Cfg.CLASSES.medium
	check(Cfg.CLASS_ORDER == ["light", "medium"]
		and L.guns == ["rapidRascal", "bubbleBlaster", "thunderspring", "plungerBow", "starlightZapper", "plasti9"]
		and M.guns == ["foamFury", "brickbreaker", "popcornPopper", "crayonCannon", "jackBlaster", "walloper"]
		and L.abilities == ["dash", "grapple"] and M.abilities == ["shield", "cloak"]
		and L.gadgets == ["glitchJug", "stairs", "fragGrenade", "pyroGrenade", "flashbang"]
		and M.gadgets == ["turret", "healthInfuser", "breachDrill", "explosiveMine", "pyroMine"]
		and L.health == 100.0 and M.health == 150.0 and L.speed == 1.1 and M.speed == 0.9, "class_tables_match_spec")
	check(not L.abilities.has("cloak") and not M.abilities.has("dash") and not M.abilities.has("grapple") and not M.gadgets.has("fragGrenade") and not M.gadgets.has("pyroGrenade"), "medium_never_moves_or_throws")
	var one := true
	for wid in Cfg.WEAPON_ORDER:
		one = one and int(L.guns.has(wid)) + int(M.guns.has(wid)) == 1
	check(one and Cfg.class_of_gun("walloper") == "medium" and Cfg.class_of_gun("foamFury") == "medium" and Cfg.class_of_gun("plasti9") == "light", "every_gun_in_exactly_one_class")

	var a := _actor()
	a.set_class("medium")
	check(a.cls == "medium" and a.max_health == 150.0 and a.health == 150.0 and a.class_speed == 0.9, "set_class_sets_health_and_speed")
	a.alive = true
	a.health = 120
	a.last_damage_at = -100
	for i in 600:
		a.tick(0.05, 0.0)
	var regen_ok := a.health == 150.0
	a.health = 120
	var pk := Pickups.new([], Effects.new(), AudioStub.new(), Emitter.new())
	var item := {"kind": "health", "pos": Vector3.ZERO, "color": "#fff", "available": true, "respawnAt": 0.0}
	var can := pk._can_use(item, a)
	pk._take(item, a, 0.0)
	check(regen_ok and can and a.health <= 150.0 and a.health > 120.0, "regen_and_pickup_cap_at_class_max")
	var b := _actor()
	b.set_class("light")
	check(b.revive_health() == 60.0 and a.revive_health() == 90.0, "revive_is_60_percent")

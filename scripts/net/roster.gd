class_name Roster
extends RefCounted
## Who sits where in an online match (port of src/net/roster.ts and the RemoteToy bits of remote.ts).
## A seat is {key, name, team, shelf}: key "h:<netId>" for a human, "b:<characterId>" for a bot.
## Seat index = actor index on every machine; seat 0 is the host.


## Most toys a mode holds: its usual bots plus you.
static func toy_cap(mode: String) -> int:
	return int(Modes.MODES[mode].botCount) + 1


## How many bots can join `humans` players in this mode.
static func max_bots(mode: String, humans: int) -> int:
	return maxi(0, toy_cap(mode) - humans)


## Everyone in the match, in seat order: the host, then the other humans, then bots.
## Teams: humans are dealt round the teams starting with Sunrise; each bot then joins the smallest team.
static func build_seats(mode: String, humans: Array, bots: int) -> Array:
	var def: Dictionary = Modes.MODES[mode]
	var n := mini(maxi(0, bots), max_bots(mode, humans.size()))
	var seats := []
	for i in humans.size():
		seats.append({"key": "h:" + str(humans[i].id), "name": str(humans[i].name), "team": i % int(def.teamCount) if def.teams else -1, "shelf": false})
	var roster := []
	if mode == "ffa":
		# alternate floor and shelf toys so a short list still has newcomers up high
		for i in maxi(Chars.BOT_ROSTER.size(), Chars.SHELF_ROSTER.size()):
			if i < Chars.BOT_ROSTER.size():
				roster.append(Chars.BOT_ROSTER[i])
			if i < Chars.SHELF_ROSTER.size():
				roster.append(Chars.SHELF_ROSTER[i])
	else:
		roster = Chars.ALL_BOTS.duplicate()
		roster.shuffle()
	for id in roster.slice(0, n):
		var team := -1
		if def.teams:
			var sizes := []
			for t in int(def.teamCount):
				sizes.append(seats.filter(func(s): return s.team == t).size())
			team = sizes.find(sizes.min())
		seats.append({"key": "b:" + id, "name": Chars.CHARACTERS[id].name, "team": team, "shelf": mode == "ffa" and Chars.SHELF_ROSTER.has(id)})
	return seats


## The bot character in a seat, or "" for a human seat.
static func seat_bot(seat: Dictionary) -> String:
	var k: String = seat.key
	return k.substr(2) if k.begins_with("b:") else ""


## The network id of a human seat, or "" for a bot.
static func seat_human(seat: Dictionary) -> String:
	var k: String = seat.key
	return k.substr(2) if k.begins_with("h:") else ""


## Other humans look like the player toy, under their own name.
static func human_def(nm: String) -> Dictionary:
	var d: Dictionary = Chars.CHARACTERS.player.duplicate()
	d.name = nm
	return d


## A toy this machine does not move itself. Host: a guest's toy. Guest: every toy except your own.
static func new_remote(seat: int, net_id: String) -> Dictionary:
	# state = host: the latest state the guest sent; life = host: spawn counter (older states are ignored)
	return {"seat": seat, "net_id": net_id, "state": null, "life": 0, "revive_held": false, "reload": 0.0}


## Rig animation for a toy from its plain fields (the same thing Bot.anim_state gives).
static func actor_anim(a: Actor, now: float, reload: float) -> Dictionary:
	return {
		"speed": a.speed, "grounded": a.grounded, "vy": a.vel.y, "crouch": a.crouch_t, "aimPitch": a.pitch,
		"reload": reload, "fireKick": a.fire_kick, "hit": a.hit_flinch, "dashing": a.dashing, "sliding": a.sliding,
		"protectedShimmer": a.is_protected(now),
	}


## Weapons in the hands of remote toys: keeps each toy's weapon state and the model on its rig matching
## the weapon the network says it's holding.
class Gear:
	var models := {}  # actor -> {weapon id -> WeaponModel}
	var shown := {}  # actor -> weapon id

	func sync(a: Actor, wid: String, slot: int) -> void:
		if wid == "" or not Cfg.WEAPONS.has(wid):
			return
		if slot != 0 and slot != 1:
			slot = 0
		a.slot = slot
		if a.weapons[slot] == null or a.weapons[slot].id != wid:
			a.give_weapon(wid, slot)
		if a.model == null or shown.get(a, "") == wid:
			return
		var cache: Dictionary = models.get(a, {})
		models[a] = cache
		var m: WeaponModel = cache.get(wid)
		if m == null:
			m = WeaponModel.build(wid)
			Merge.flatten_by_material(m)
			cache[wid] = m
		# the rig frees whatever is in the socket: take our cached models out first
		for c in a.model.weapon_socket.get_children():
			a.model.weapon_socket.remove_child(c)
		if m.get_parent():
			m.get_parent().remove_child(m)
		a.model.set_weapon(m)
		shown[a] = wid

	## Where shots from this toy visibly leave the barrel.
	func muzzle(a: Actor) -> Vector3:
		var wid: String = shown.get(a, "")
		var m: WeaponModel = models.get(a, {}).get(wid) if wid != "" else null
		if m and m.is_inside_tree():
			return m.muzzle.global_position
		return a.eye_pos()

	func forget(a: Actor) -> void:
		for m in models.get(a, {}).values():
			if is_instance_valid(m):
				(m as Node).queue_free()
		models.erase(a)
		shown.erase(a)

	func clear() -> void:
		for a in models.keys():
			forget(a)

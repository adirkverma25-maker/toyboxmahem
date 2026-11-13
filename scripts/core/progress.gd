extends Node
## Coins and weapon unlocks (port of src/core/Progress.ts). Autoload "Progress".
## Saved per account; the guest profile uses the plain key.

signal changed

## What each weapon costs to unlock. 0 = starter (always owned).
const WEAPON_PRICES := {
	"foamFury": 0, "jackBlaster": 0, "plasti9": 0,
	"bubbleBlaster": 300, "rapidRascal": 300,
	"brickbreaker": 600, "starlightZapper": 600,
	"crayonCannon": 800,
	"thunderspring": 1000, "plungerBow": 1000,
	"popcornPopper": 1500,
	"walloper": 1800,
}
const TIER_COLORS := {"Starter": "#cfd8dc", "Common": "#7dff6b", "Rare": "#5ff4ff", "Epic": "#c77dff", "Legendary": "#ffd23f"}

## Coin rewards for one finished match.
const REWARDS := {
	"played": 25, "perPop": 10, "perHeadshot": 5, "perRevive": 15,
	"streak5": 25, "streak10": 50, "win": 75, "second": 40, "third": 20,
	"difficulty": {"easy": 0.75, "normal": 1.0, "hard": 1.35},
}

const KEY := "toybox-mayhem.progress.v1"

var coins := 0
var owned := {}
var earned_total := 0
var _ns := ""


static func starters() -> Array:
	return Cfg.WEAPON_ORDER.filter(func(id): return WEAPON_PRICES[id] == 0)


static func tier_of(id: String) -> String:
	var p: int = WEAPON_PRICES[id]
	return "Starter" if p == 0 else "Common" if p < 500 else "Rare" if p < 900 else "Epic" if p < 1400 else "Legendary"


func _ready() -> void:
	_load()


func _key() -> String:
	return KEY + ":" + _ns if _ns != "" else KEY


## Switch to another account's progress ('' = guest).
func use_profile(ns: String) -> void:
	_ns = ns
	_load()
	changed.emit()


func _load() -> void:
	coins = 0
	earned_total = 0
	owned = {}
	for id in starters():
		owned[id] = true
	var s = Store.get_json(_key())
	if s is Dictionary:
		if (s.get("coins") is float or s.get("coins") is int) and s.coins >= 0:
			coins = int(floor(s.coins))
		if s.get("earnedTotal") is float or s.get("earnedTotal") is int:
			earned_total = int(s.earnedTotal)
		for id in s.get("owned", []):
			if Cfg.WEAPONS.has(id):
				owned[id] = true


func _save() -> void:
	Store.set_json(_key(), {"coins": coins, "owned": owned.keys(), "earnedTotal": earned_total})


func owns(id: String) -> bool:
	return owned.has(id)


func price(id: String) -> int:
	return WEAPON_PRICES[id]


func can_afford(id: String) -> bool:
	return not owns(id) and coins >= WEAPON_PRICES[id]


## Spend coins on a weapon. Returns false if it's already owned or too expensive.
func unlock(id: String) -> bool:
	if not can_afford(id):
		return false
	coins -= WEAPON_PRICES[id]
	owned[id] = true
	_save()
	changed.emit()
	return true


## Work out and bank the coins for a finished match.
## r: {kills, headshots, revives, bestStreak, won, place, difficulty}
func award(r: Dictionary) -> Dictionary:
	var lines := [["Finished the match", REWARDS.played]]
	var k: int = r.kills
	if k:
		lines.append(["%d pop%s" % [k, "" if k == 1 else "s"], k * REWARDS.perPop])
	if r.headshots:
		lines.append(["%d headshot pop%s" % [r.headshots, "" if r.headshots == 1 else "s"], r.headshots * REWARDS.perHeadshot])
	if r.revives:
		lines.append(["%d revive%s" % [r.revives, "" if r.revives == 1 else "s"], r.revives * REWARDS.perRevive])
	if r.bestStreak >= 10:
		lines.append(["%d-pop streak" % r.bestStreak, REWARDS.streak10])
	elif r.bestStreak >= 5:
		lines.append(["%d-pop streak" % r.bestStreak, REWARDS.streak5])
	if r.won:
		lines.append(["1st place" if r.place else "Team win", REWARDS.win])
	elif r.place == 2:
		lines.append(["2nd place", REWARDS.second])
	elif r.place == 3:
		lines.append(["3rd place", REWARDS.third])
	var total := 0
	for l in lines:
		total += int(l[1])
	var mult: float = REWARDS.difficulty.get(r.difficulty, 1.0)
	if mult != 1.0:
		var extra := int(round(total * mult)) - total
		var d: String = r.difficulty
		lines.append(["%s difficulty ×%s" % [d.capitalize(), str(mult)], extra])
		total += extra
	coins += total
	earned_total += total
	_save()
	changed.emit()
	var affordable := Cfg.WEAPON_ORDER.filter(func(id): return can_afford(id))
	return {"lines": lines, "total": total, "coinsAfter": coins, "affordable": affordable}


## Redeem a code (Loadout screen). Returns a message, or "" if the code is wrong.
func redeem(code: String) -> String:
	var c := code.strip_edges().to_upper()
	if c == "TOYBOXFREE":
		var before := owned.size()
		for id in Cfg.WEAPON_ORDER:
			owned[id] = true
		_save()
		changed.emit()
		return "Every blaster is unlocked!" if owned.size() > before else "You already have every blaster."
	return ""


func grant(n: int) -> void:
	coins += maxi(0, n)
	_save()
	changed.emit()


## Keep the saved loadout on weapons you own.
func owned_or(id: String, fallback: String) -> String:
	return id if Cfg.WEAPONS.has(id) and owns(id) else fallback

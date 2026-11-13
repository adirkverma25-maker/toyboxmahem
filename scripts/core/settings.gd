extends Node
## Settings + career stats (port of src/core/Settings.ts). Autoload "Settings".
## Saved as JSON under user:// (on Windows: %APPDATA%/Godot/app_userdata/Toybox Mayhem).

signal changed(key: String)

const DEFAULTS := {
	"playerName": "You",
	"sensitivity": 1.0,
	"adsSensitivity": 0.85,
	"invertY": false,
	"padSensitivity": 1.0,
	"padAimAssist": true,
	"padVibration": true,
	"fov": 90.0,
	"quality": "medium",
	"masterVolume": 0.8,
	"musicVolume": 0.45,
	"sfxVolume": 0.9,
	"ambienceVolume": 0.6,
	"crosshairColor": "#ffffff",
	"crosshairSize": 1.0,
	"crosshairDot": true,
	"reducedMotion": false,
	"cameraShake": true,
	"motionBlur": false,
	"enemyOutlines": false,
	"damageNumbers": true,
	"difficulty": "normal",
	"showFps": false,
	"fullscreen": false,
	"map": "bedroom",
	"primary": "foamFury",
	"secondary": "plasti9",
	"scopes": "{}",
	"abilities": "dash,grapple",
	"binds": "{}",
	## online play: relay address ("" = the online server) and the last room code typed
	"serverUrl": "",
	"lastRoom": "",
}

const DEFAULT_STATS := {
	"matches": 0, "wins": 0, "kills": 0, "deaths": 0, "headshots": 0, "shotsFired": 0, "shotsHit": 0,
	"bestStreak": 0, "bestMatchKills": 0, "playTimeSec": 0.0,
}

const SKEY := "settings"
const TKEY := "stats"
const MAPKEY := "map"

var data: Dictionary = {}
var stats: Dictionary = {}
## account id whose settings + stats are loaded ('' = guest)
var ns := ""


func _ready() -> void:
	data = _load(SKEY, DEFAULTS)
	stats = _load(TKEY, DEFAULT_STATS)
	data.fov = clampf(data.fov, 70, 110)
	data.map = Store.get_str(MAPKEY, data.map)


func _skey() -> String:
	return SKEY + (":" + ns if ns != "" else "")


func _tkey() -> String:
	return TKEY + (":" + ns if ns != "" else "")


func _load(key: String, def: Dictionary) -> Dictionary:
	var out := def.duplicate(true)
	var raw = Store.get_json(key)
	if raw is Dictionary:
		for k in def:
			if raw.has(k) and typeof(raw[k]) == typeof(def[k]):
				out[k] = raw[k]
			elif raw.has(k) and (typeof(raw[k]) == TYPE_FLOAT or typeof(raw[k]) == TYPE_INT) and (typeof(def[k]) == TYPE_FLOAT or typeof(def[k]) == TYPE_INT):
				out[k] = float(raw[k]) if typeof(def[k]) == TYPE_FLOAT else int(raw[k])
	return out


func get_v(k: String):
	return data.get(k, DEFAULTS.get(k))


func set_v(k: String, v) -> void:
	data[k] = v
	Store.set_json(_skey(), data)
	if k == "map":
		Store.set_str(MAPKEY, str(v))
	changed.emit(k)


## Load another account's settings and career stats (see Settings.ts useProfile).
func use_profile(id: String, seed_from_current := false) -> void:
	var prev := data
	ns = id
	var saved := Store.has(_skey())
	data = _load(_skey(), DEFAULTS)
	if not saved and seed_from_current:
		data = prev.duplicate(true)
		for k in ["primary", "secondary", "scopes", "abilities"]:
			data[k] = DEFAULTS[k]
	data.map = Store.get_str(MAPKEY, prev.get("map", "bedroom"))
	data.fov = clampf(data.fov, 70, 110)
	Store.set_json(_skey(), data)
	stats = _load(_tkey(), DEFAULT_STATS)
	for k in data:
		changed.emit(k)


func reset() -> void:
	var keep := {}
	for k in ["map", "primary", "secondary", "scopes", "abilities", "binds"]:
		keep[k] = data[k]
	data = DEFAULTS.duplicate(true)
	data.merge(keep, true)
	Store.set_json(_skey(), data)
	for k in data:
		changed.emit(k)


func save_stats() -> void:
	Store.set_json(_tkey(), stats)


func reset_stats() -> void:
	stats = DEFAULT_STATS.duplicate(true)
	save_stats()

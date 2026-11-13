class_name Store
## Tiny key/value store on disk (the Godot stand-in for the browser's localStorage).
## Everything lives in one JSON file: user://toybox-save.json

const PATH := "user://toybox-save.json"
static var _data: Dictionary = {}
static var _loaded := false


static func _ensure() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var parsed = JSON.parse_string(f.get_as_text())
			if parsed is Dictionary:
				_data = parsed


static func _flush() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data))


static func has(key: String) -> bool:
	_ensure()
	return _data.has(key)


static func get_str(key: String, fallback := "") -> String:
	_ensure()
	var v = _data.get(key, fallback)
	return v if v is String else fallback


static func set_str(key: String, v: String) -> void:
	_ensure()
	_data[key] = v
	_flush()


static func get_json(key: String):
	_ensure()
	return _data.get(key, null)


static func set_json(key: String, v) -> void:
	_ensure()
	_data[key] = v
	_flush()


static func erase(key: String) -> void:
	_ensure()
	_data.erase(key)
	_flush()

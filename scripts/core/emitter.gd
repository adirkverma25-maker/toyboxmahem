class_name Emitter
extends RefCounted
## Tiny event bus (port of src/core/events.ts). Payloads are Dictionaries.

var _map := {}


func on(k: String, h: Callable) -> void:
	if not _map.has(k):
		_map[k] = []
	_map[k].append(h)


func emit(k: String, payload: Dictionary) -> void:
	for h in _map.get(k, []):
		if (h as Callable).is_valid():
			h.call(payload)


func clear() -> void:
	_map.clear()


func off(k: String, h: Callable) -> void:
	if _map.has(k):
		_map[k].erase(h)

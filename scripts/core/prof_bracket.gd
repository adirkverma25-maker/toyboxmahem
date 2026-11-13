class_name ProfBracket
extends Node
## Dev: times the whole process step (first node to last node) and the gap between frames.
var first := true
static var _start := 0
static var _last_end := 0


func _init(is_first: bool) -> void:
	first = is_first
	process_priority = -100000 if is_first else 100000


func _process(_dt: float) -> void:
	var now := Time.get_ticks_usec()
	if first:
		if _last_end:
			Prof.acc["outside"] = Prof.acc.get("outside", 0.0) + (now - _last_end) / 1000.0
		_start = now
	else:
		Prof.acc["all_process"] = Prof.acc.get("all_process", 0.0) + (now - _start) / 1000.0
		_last_end = now

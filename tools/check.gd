extends Node
## Dev helper: compile every script in res://scripts and report failures.
## Run: Godot --headless --path . res://tools/check.tscn

func _ready() -> void:
	var bad := 0
	var files := []
	_walk("res://scripts", files)
	for f in files:
		var s = load(f)
		if s == null:
			print("FAILED: ", f)
			bad += 1
	print("checked %d scripts, %d failed" % [files.size(), bad])
	get_tree().quit(1 if bad else 0)

func _walk(dir: String, out: Array) -> void:
	for d in DirAccess.get_directories_at(dir):
		_walk(dir + "/" + d, out)
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir + "/" + f)

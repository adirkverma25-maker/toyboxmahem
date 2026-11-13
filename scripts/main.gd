extends Node3D
## Entry point (port of src/main.ts): starts the game.


func _ready() -> void:
	add_child(Game.new())

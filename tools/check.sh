#!/bin/sh
# compile-check every script (autoloads included). Runs an import pass first so new class_names register.
GD="/c/Users/adive/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe"
cd "$(dirname "$0")/.." || exit 1
timeout 300 "$GD" --headless --path . --import >/dev/null 2>&1
timeout 300 "$GD" --headless --path . res://tools/check.tscn 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error|  at: GDScript|FAILED|checked" | head -${1:-40}

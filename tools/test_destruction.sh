#!/bin/sh
# Destruction dev tests; exits non-zero when any fail or any script error is printed.
GD="${GODOT:-/c/Users/adive/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
out=$(timeout 120 "$GD" --headless --path . --quit-after 3000 res://tools/test_destruction.tscn 2>&1)
echo "$out" | grep -E "SCRIPT ERROR|Parse Error|^FAIL|^\[test\]"
echo "$out" | grep -q "SCRIPT ERROR" && exit 1
echo "$out" | grep -q "^\[test\] 0 failures"

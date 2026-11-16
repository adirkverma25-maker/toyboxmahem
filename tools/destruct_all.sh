#!/bin/sh
# --screen=destruct on every map; non-zero exit if any map reports failures.
GD="${GODOT:-/c/Users/adive/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
bad=0
for m in toycity bedroom backyard; do
	r=$(timeout 240 "$GD" --headless --path . -- --screen=destruct --map=$m 2>&1 | grep -E "SCRIPT ERROR|\[destruct\] [0-9]+ failures" | tail -1)
	echo "$m: $r"
	echo "$r" | grep -q "\[destruct\] 0 failures" || bad=1
done
exit $bad

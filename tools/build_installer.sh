#!/bin/sh
# Export the game and wrap it in a Windows installer: build/ToyboxMayhem.exe -> build/ToyboxMayhem-Setup.exe
#   sh tools/build_installer.sh
# Needs Godot 4.7 with the Windows export templates, and Inno Setup 6 (winget install JRSoftware.InnoSetup).
# Override the tool paths with GODOT=... and ISCC=... if they live elsewhere.
GD="${GODOT:-/c/Users/adive/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
cd "$(dirname "$0")/.." || exit 1
if [ -z "$ISCC" ]; then
	for c in "$LOCALAPPDATA/Programs/Inno Setup 6/ISCC.exe" "/c/Program Files (x86)/Inno Setup 6/ISCC.exe" "/c/Program Files/Inno Setup 6/ISCC.exe"; do
		[ -f "$c" ] && ISCC="$c" && break
	done
fi
[ -f "$ISCC" ] || { echo "Inno Setup not found: winget install JRSoftware.InnoSetup"; exit 1; }
VERSION=$(sed -n 's/^config\/version="\(.*\)"/\1/p' project.godot)
mkdir -p build
echo "Exporting Toybox Mayhem $VERSION..."
"$GD" --headless --path . --export-release "Windows Desktop" build/ToyboxMayhem.exe 2>&1 | grep -iE "error|warning: .*export" | head -20
[ -f build/ToyboxMayhem.exe ] || { echo "Export failed"; exit 1; }
echo "Building the installer..."
"$ISCC" //Q "//DAppVersion=$VERSION" installer/toybox_mayhem.iss || exit 1
ls -la build/ToyboxMayhem-Setup.exe

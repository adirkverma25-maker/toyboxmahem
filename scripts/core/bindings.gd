extends Node
## Everything the player can rebind (port of src/core/Bindings.ts). Autoload "Binds".
## Keys use the browser's KeyboardEvent.code names ("KeyW", "Space", "Mouse0"...) so saved bindings match the
## original game; GInput translates Godot events into these names. Controller buttons use the standard
## gamepad mapping indexes (A=0 B=1 X=2 Y=3 LB=4 RB=5 LT=6 RT=7 View=8 Menu=9 L3=10 R3=11 D-pad 12-15).

const ACTIONS := [
	{"id": "forward", "label": "Move forward", "kb": ["KeyW", ""], "pad": -1, "stick": "Left stick"},
	{"id": "back", "label": "Move back", "kb": ["KeyS", ""], "pad": -1, "stick": "Left stick"},
	{"id": "left", "label": "Move left", "kb": ["KeyA", ""], "pad": -1, "stick": "Left stick"},
	{"id": "right", "label": "Move right", "kb": ["KeyD", ""], "pad": -1, "stick": "Left stick"},
	{"id": "jump", "label": "Jump", "kb": ["Space", ""], "pad": 0},
	{"id": "crouch", "label": "Crouch / slide", "kb": ["ControlLeft", "KeyC"], "pad": 1},
	{"id": "sprint", "label": "Sprint (controller: toggles)", "kb": ["ShiftLeft", ""], "pad": 10},
	{"id": "fire", "label": "Fire", "kb": ["Mouse0", ""], "pad": 7},
	{"id": "aim", "label": "Aim down sights", "kb": ["Mouse2", ""], "pad": 6},
	{"id": "reload", "label": "Reload / vent", "kb": ["KeyR", ""], "pad": 2},
	{"id": "revive", "label": "Revive teammate (hold)", "kb": ["KeyE", ""], "pad": 2},
	{"id": "swap", "label": "Switch weapon", "kb": ["", ""], "pad": 3},
	{"id": "weapon1", "label": "Primary weapon", "kb": ["Digit1", ""], "pad": -1},
	{"id": "weapon2", "label": "Secondary weapon", "kb": ["Digit2", ""], "pad": -1},
	{"id": "ability1", "label": "Ability 1", "kb": ["KeyQ", ""], "pad": 5},
	{"id": "ability2", "label": "Ability 2", "kb": ["KeyF", ""], "pad": 4},
	{"id": "inspect", "label": "Inspect weapon", "kb": ["KeyT", ""], "pad": 14},
	{"id": "scoreboard", "label": "Scoreboard (hold)", "kb": ["Tab", ""], "pad": 8},
]

## Reload and revive may share a button: the game reloads unless a downed teammate is right there.
const MAY_SHARE := [["reload", "revive"]]
## Buttons the controller keeps for itself (Menu = pause).
const PAD_RESERVED := [9]
const PAD_NAMES := ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "View", "Menu", "L3", "R3", "D-pad ↑", "D-pad ↓", "D-pad ←", "D-pad →", "Home"]
const PAD_SHORT := ["A", "B", "X", "Y", "LB", "RB", "LT", "RT", "⧉", "≡", "L3", "R3", "▲", "▼", "◀", "▶", "⌂"]
const KEY_LABELS := {
	"Mouse0": "Left click", "Mouse1": "Middle click", "Mouse2": "Right click", "Mouse3": "Mouse 4", "Mouse4": "Mouse 5",
	"Space": "Space", "ShiftLeft": "Shift", "ShiftRight": "R Shift", "ControlLeft": "Ctrl", "ControlRight": "R Ctrl",
	"AltLeft": "Alt", "AltRight": "R Alt", "Tab": "Tab", "CapsLock": "Caps", "Enter": "Enter", "Backquote": "`",
	"ArrowUp": "↑", "ArrowDown": "↓", "ArrowLeft": "←", "ArrowRight": "→", "Minus": "-", "Equal": "=",
	"BracketLeft": "[", "BracketRight": "]", "Semicolon": ";", "Quote": "'", "Comma": ",", "Period": ".", "Slash": "/", "Backslash": "\\",
}
const KEY_SHORT := {"Mouse0": "LMB", "Mouse1": "MMB", "Mouse2": "RMB", "Mouse3": "M4", "Mouse4": "M5", "Space": "SPC", "ControlLeft": "CTL", "ShiftLeft": "SHF", "CapsLock": "CAP"}

## action -> [code, code]
var kb := {}
## action -> button index
var pad := {}


func _ready() -> void:
	load_binds()


static func action_def(a: String) -> Dictionary:
	for d in ACTIONS:
		if d.id == a:
			return d
	return {}


static func _share_ok(a: String, b: String) -> bool:
	for g in MAY_SHARE:
		if g.has(a) and g.has(b):
			return true
	return false


static func pad_label(b: int) -> String:
	if b < 0:
		return ""
	return PAD_NAMES[b] if b < PAD_NAMES.size() else "Button %d" % b


static func pad_short(b: int) -> String:
	if b < 0:
		return ""
	return PAD_SHORT[b] if b < PAD_SHORT.size() else str(b)


static func key_label(code: String) -> String:
	if code == "":
		return ""
	if KEY_LABELS.has(code):
		return KEY_LABELS[code]
	if code.begins_with("Key"):
		return code.substr(3)
	if code.begins_with("Digit"):
		return code.substr(5)
	if code.begins_with("Numpad"):
		return "Num " + code.substr(6)
	return code


static func key_short(code: String) -> String:
	return KEY_SHORT.get(code, key_label(code))


func _defaults() -> void:
	for a in ACTIONS:
		kb[a.id] = (a.kb as Array).duplicate()
		pad[a.id] = a.pad


func load_binds() -> void:
	_defaults()
	var s = JSON.parse_string(str(Settings.get_v("binds")))
	if not (s is Dictionary):
		return
	for a in ACTIONS:
		var k = s.get("kb", {}).get(a.id) if s.get("kb") is Dictionary else null
		if k is Array and k.size() == 2 and k[0] is String and k[1] is String:
			kb[a.id] = [k[0], k[1]]
		var p = s.get("pad", {}).get(a.id) if s.get("pad") is Dictionary else null
		if (p is float or p is int) and p >= -1 and p < 17 and not a.has("stick"):
			pad[a.id] = int(p)


func _save() -> void:
	Settings.set_v("binds", JSON.stringify({"kb": kb, "pad": pad}))


func reset() -> void:
	_defaults()
	_save()


## Bind a key to an action's slot. If another action used that key, it gets this slot's old key (a swap).
func set_kb(action: String, slot: int, code: String) -> void:
	var old: String = kb[action][slot]
	if code != "":
		for a in ACTIONS:
			if a.id == action:
				continue
			var k: Array = kb[a.id]
			for i in 2:
				if k[i] == code:
					k[i] = old
		if kb[action][1 - slot] == code:
			kb[action][1 - slot] = ""
	kb[action][slot] = code
	_save()


## Bind a controller button. Conflicts swap, except reload/revive which may share.
func set_pad(action: String, btn: int) -> void:
	if PAD_RESERVED.has(btn):
		return
	var old: int = pad[action]
	if btn >= 0:
		for a in ACTIONS:
			if a.id != action and not a.has("stick") and pad[a.id] == btn and not _share_ok(a.id, action):
				pad[a.id] = old
	pad[action] = btn
	_save()


## "Q", "Left click", "RB"... for the device in use ('' when unbound).
func label(action: String, use_pad: bool, short := false) -> String:
	if use_pad:
		var d := action_def(action)
		if d.has("stick"):
			return d.stick
		return pad_short(pad[action]) if short else pad_label(pad[action])
	var k: Array = kb[action]
	var code: String = k[0] if k[0] != "" else k[1]
	return key_short(code) if short else key_label(code)


func is_bound(code: String) -> bool:
	for k in kb.values():
		if k[0] == code or k[1] == code:
			return true
	return false

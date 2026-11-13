class_name GInput
extends Node
## Keyboard + mouse input with mouse capture, plus a gamepad polled every frame (port of src/core/Input.ts).
## Game code asks for actions (act / act_pressed) which go through the player's bindings (Binds).
## "pressed" flags are edge-triggered and cleared every frame by end_frame().

const TRIGGER_ON := 0.3
## Standard-mapping buttons the menus use (fixed, not rebindable).
const PAD := {"A": 0, "B": 1, "X": 2, "Y": 3, "LB": 4, "RB": 5, "LT": 6, "RT": 7, "VIEW": 8, "MENU": 9, "L3": 10, "R3": 11, "UP": 12, "DOWN": 13, "LEFT": 14, "RIGHT": 15}
## standard index -> Godot JoyButton (LT/RT are axes, handled separately)
const STD_TO_GODOT := {0: JOY_BUTTON_A, 1: JOY_BUTTON_B, 2: JOY_BUTTON_X, 3: JOY_BUTTON_Y, 4: JOY_BUTTON_LEFT_SHOULDER, 5: JOY_BUTTON_RIGHT_SHOULDER,
	8: JOY_BUTTON_BACK, 9: JOY_BUTTON_START, 10: JOY_BUTTON_LEFT_STICK, 11: JOY_BUTTON_RIGHT_STICK, 12: JOY_BUTTON_DPAD_UP, 13: JOY_BUTTON_DPAD_DOWN,
	14: JOY_BUTTON_DPAD_LEFT, 15: JOY_BUTTON_DPAD_RIGHT, 16: JOY_BUTTON_GUIDE}

## Which device the player used last. The HUD and prompts switch their key names to match.
static var using_pad := false

var _down := {}
var _pressed := {}
var _released := {}
var _pad_now := {}
var _pad_pressed := {}
var mouse_dx := 0.0
var mouse_dy := 0.0
var wheel := 0
var locked := false
var enabled := true
var move_x := 0.0
var move_y := 0.0
var look_x := 0.0
var look_y := 0.0
var pad_sprint := false
var pad_connected := false
var _pad_index := -1
var _capture_fn := Callable()
var _capture_from := 0.0
var _swallow_until := 0.0
var on_lock_change := Callable()
var on_device_change := Callable()


## Name of the key/button bound to an action, for the device in use.
static func action_name(a: String, short := false) -> String:
	var s: String = Engine.get_main_loop().root.get_node("Binds").label(a, using_pad, short)
	return s if s != "" else "unbound"


static func _deadzone(x: float, y: float, dz: float) -> Vector2:
	var m := Vector2(x, y).length()
	if m < dz:
		return Vector2.ZERO
	var k := minf(1, (m - dz) / (1 - dz)) / m
	return Vector2(x * k, y * k)


static func _now_ms() -> float:
	return Time.get_ticks_msec()


## Godot key event -> browser KeyboardEvent.code name.
static func key_code(e: InputEventKey) -> String:
	var k := e.physical_keycode if e.physical_keycode != KEY_NONE else e.keycode
	var right := e.location == KEY_LOCATION_RIGHT
	if k >= KEY_A and k <= KEY_Z:
		return "Key" + char(k)
	if k >= KEY_0 and k <= KEY_9:
		return "Digit" + char(k)
	if k >= KEY_KP_0 and k <= KEY_KP_9:
		return "Numpad" + str(k - KEY_KP_0)
	if k >= KEY_F1 and k <= KEY_F12:
		return "F" + str(k - KEY_F1 + 1)
	match k:
		KEY_SPACE: return "Space"
		KEY_SHIFT: return "ShiftRight" if right else "ShiftLeft"
		KEY_CTRL: return "ControlRight" if right else "ControlLeft"
		KEY_ALT: return "AltRight" if right else "AltLeft"
		KEY_META: return "MetaRight" if right else "MetaLeft"
		KEY_TAB: return "Tab"
		KEY_CAPSLOCK: return "CapsLock"
		KEY_ENTER: return "Enter"
		KEY_KP_ENTER: return "NumpadEnter"
		KEY_ESCAPE: return "Escape"
		KEY_BACKSPACE: return "Backspace"
		KEY_DELETE: return "Delete"
		KEY_INSERT: return "Insert"
		KEY_HOME: return "Home"
		KEY_END: return "End"
		KEY_PAGEUP: return "PageUp"
		KEY_PAGEDOWN: return "PageDown"
		KEY_UP: return "ArrowUp"
		KEY_DOWN: return "ArrowDown"
		KEY_LEFT: return "ArrowLeft"
		KEY_RIGHT: return "ArrowRight"
		KEY_QUOTELEFT: return "Backquote"
		KEY_MINUS: return "Minus"
		KEY_EQUAL: return "Equal"
		KEY_BRACKETLEFT: return "BracketLeft"
		KEY_BRACKETRIGHT: return "BracketRight"
		KEY_SEMICOLON: return "Semicolon"
		KEY_APOSTROPHE: return "Quote"
		KEY_COMMA: return "Comma"
		KEY_PERIOD: return "Period"
		KEY_SLASH: return "Slash"
		KEY_BACKSLASH: return "Backslash"
	return OS.get_keycode_string(k)


static func mouse_code(b: int) -> String:
	match b:
		MOUSE_BUTTON_LEFT: return "Mouse0"
		MOUSE_BUTTON_MIDDLE: return "Mouse1"
		MOUSE_BUTTON_RIGHT: return "Mouse2"
		MOUSE_BUTTON_XBUTTON1: return "Mouse3"
		MOUSE_BUTTON_XBUTTON2: return "Mouse4"
	return ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.joy_connection_changed.connect(_on_joy)
	pad_connected = Input.get_connected_joypads().size() > 0


func _on_joy(device: int, connected: bool) -> void:
	if connected:
		pad_connected = true
		if _pad_index < 0:
			_pad_index = device
	else:
		if device == _pad_index:
			_pad_index = -1
		pad_connected = Input.get_connected_joypads().size() > 0
		if not pad_connected:
			_release_pad()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var e := event as InputEventKey
		var code := key_code(e)
		if e.pressed:
			if _capture_fn.is_valid():
				get_viewport().set_input_as_handled()
				if e.echo:
					return
				_finish_capture(null if code == "Escape" else {"kind": "kb", "code": code})
				return
			_set_device(false)
			if e.echo:
				return
			# keep game keys away from focused menu controls while playing (Tab, Space, bound keys)
			if locked and (code in ["Tab", "Space"] or Binds.is_bound(code)):
				get_viewport().set_input_as_handled()
			_down[code] = true
			_pressed[code] = true
		else:
			if _now_ms() < _swallow_until:
				get_viewport().set_input_as_handled()
				_swallow_until = 0
			_down.erase(code)
			_released[code] = true
	elif event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_WHEEL_UP or e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if e.pressed:
				wheel += -1 if e.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			return
		var code := mouse_code(e.button_index)
		if code == "":
			return
		if e.pressed:
			if _capture_fn.is_valid():
				if _now_ms() < _capture_from:
					return
				get_viewport().set_input_as_handled()
				_finish_capture({"kind": "kb", "code": code})
				return
			_set_device(false)
			if not locked:
				return
			_down[code] = true
			_pressed[code] = true
		else:
			if _now_ms() < _swallow_until:
				get_viewport().set_input_as_handled()
				_swallow_until = 0
			_down.erase(code)
			_released[code] = true
	elif event is InputEventMouseMotion:
		if not locked:
			return
		var r: Vector2 = (event as InputEventMouseMotion).screen_relative
		var dx := 0.0 if absf(r.x) > 400 else r.x
		var dy := 0.0 if absf(r.y) > 400 else r.y
		if absf(dx) + absf(dy) > 3:
			_set_device(false)
		mouse_dx += dx
		mouse_dy += dy


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		clear()
		if locked:
			locked = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if on_lock_change.is_valid():
				on_lock_change.call(false)


# ------------------------------------------------------------------ rebinding
## The next key, mouse button or controller button is passed to fn (null = cancelled with Esc / Menu).
func capture(fn: Callable) -> void:
	_capture_fn = fn
	_capture_from = _now_ms() + 120


func cancel_capture() -> void:
	_capture_fn = Callable()


func capturing() -> bool:
	return _capture_fn.is_valid()


func _finish_capture(c) -> void:
	var fn := _capture_fn
	_capture_fn = Callable()
	_swallow_until = 0.0 if (c != null and c.kind == "pad") else _now_ms() + 600
	if fn.is_valid():
		fn.call(c)


# ------------------------------------------------------------------ actions
## Is the action held (any of its keys, or its controller button)?
func act(a: String) -> bool:
	if not enabled:
		return false
	var k: Array = Binds.kb[a]
	if (k[0] != "" and _down.has(k[0])) or (k[1] != "" and _down.has(k[1])):
		return true
	var b: int = Binds.pad[a]
	return b >= 0 and _pad_now.has(b)


## Was the action pressed this frame?
func act_pressed(a: String) -> bool:
	if not enabled:
		return false
	var k: Array = Binds.kb[a]
	if (k[0] != "" and _pressed.has(k[0])) or (k[1] != "" and _pressed.has(k[1])):
		return true
	var b: int = Binds.pad[a]
	return b >= 0 and _pad_pressed.has(b)


func pad_held(btn: int) -> bool:
	return _pad_now.has(btn)


func pad_pressed(btn: int) -> bool:
	return _pad_pressed.has(btn)


func _set_device(p: bool) -> void:
	if using_pad == p:
		return
	using_pad = p
	if on_device_change.is_valid():
		on_device_change.call(p)


func _pad() -> int:
	var list := Input.get_connected_joypads()
	if list.is_empty():
		return -1
	if list.has(_pad_index):
		return _pad_index
	# no pad picked yet: take whichever one has a button held
	for d in list:
		for b in STD_TO_GODOT.values():
			if Input.is_joy_button_pressed(d, b):
				_pad_index = d
				return d
	_pad_index = list[0]
	return _pad_index


func _release_pad() -> void:
	_pad_now.clear()
	move_x = 0
	move_y = 0
	look_x = 0
	look_y = 0
	pad_sprint = false


## Read the gamepad. Call once at the start of every frame, before anything asks for input.
func poll_pad() -> void:
	var p := _pad()
	if p < 0:
		if _pad_now.size() or move_x != 0 or look_x != 0:
			_release_pad()
		return
	pad_connected = true
	var now := {}
	for std in STD_TO_GODOT:
		if Input.is_joy_button_pressed(p, STD_TO_GODOT[std]):
			now[std] = true
	if Input.get_joy_axis(p, JOY_AXIS_TRIGGER_LEFT) > TRIGGER_ON:
		now[6] = true
	if Input.get_joy_axis(p, JOY_AXIS_TRIGGER_RIGHT) > TRIGGER_ON:
		now[7] = true
	var mv := _deadzone(Input.get_joy_axis(p, JOY_AXIS_LEFT_X), Input.get_joy_axis(p, JOY_AXIS_LEFT_Y), 0.16)
	move_x = mv.x
	move_y = mv.y
	var lk := _deadzone(Input.get_joy_axis(p, JOY_AXIS_RIGHT_X), Input.get_joy_axis(p, JOY_AXIS_RIGHT_Y), 0.12)
	look_x = lk.x
	look_y = lk.y
	var fresh := []
	for b in now:
		if not _pad_now.has(b):
			fresh.append(b)
	fresh.sort()
	_pad_now = now
	if _capture_fn.is_valid():
		if fresh.size() and _now_ms() >= _capture_from:
			_finish_capture(null if fresh[0] == PAD.MENU else {"kind": "pad", "btn": fresh[0]})
		_set_device(true)
		return
	for b in fresh:
		_pad_pressed[b] = true
	# sprint latches until you let go of the stick or pull back
	var sb: int = Binds.pad.sprint
	if sb >= 0 and fresh.has(sb):
		pad_sprint = not pad_sprint
	if Vector2(move_x, move_y).length() < 0.3 or move_y > 0.5:
		pad_sprint = false
	if now.size() or Vector2(move_x, move_y).length() > 0.25 or Vector2(look_x, look_y).length() > 0.25:
		_set_device(true)


## Controller vibration. weak = high-frequency motor, strong = low-frequency motor.
func rumble(weak: float, strong: float, ms: float) -> void:
	if not using_pad or not Settings.get_v("padVibration"):
		return
	var p := _pad()
	if p >= 0:
		Input.start_joy_vibration(p, minf(1, weak), minf(1, strong), ms / 1000.0)


func request_lock() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not locked:
		locked = true
		if on_lock_change.is_valid():
			on_lock_change.call(true)


func exit_lock() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if locked:
		locked = false
		clear()


func is_down(code: String) -> bool:
	return enabled and _down.has(code)


func pressed(code: String) -> bool:
	return enabled and _pressed.has(code)


func released(code: String) -> bool:
	return _released.has(code)


## Forget this frame's presses (a menu already used them).
func consume_pressed() -> void:
	_pressed.clear()
	_pad_pressed.clear()


func clear() -> void:
	_down.clear()
	mouse_dx = 0
	mouse_dy = 0


func end_frame() -> void:
	_pressed.clear()
	_pad_pressed.clear()
	_released.clear()
	mouse_dx = 0
	mouse_dy = 0
	wheel = 0

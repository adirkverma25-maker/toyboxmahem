class_name PadNav
extends RefCounted
## Drives the menus with a controller (port of src/ui/PadNav.ts): the D-pad or left stick moves a highlight
## to the nearest control in that direction, A presses, B goes back, Start resumes. Sliders change with
## left/right while highlighted. Godot's GUI focus does the spatial search; this adds the stick, key repeat,
## the starting highlight and the back/start buttons.

var input: GInput
var root: Control
var hooks: Dictionary  # {back: Callable, start: Callable}
var _held := ""
var _repeat_at := 0.0


func _init(inp: GInput, r: Control, h: Dictionary) -> void:
	input = inp
	root = r
	hooks = h
	# the left stick is read here (with repeat); Godot's own stick mapping on ui_* would move the highlight twice
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		for e in InputMap.action_get_events(a):
			if e is InputEventJoypadMotion:
				InputMap.action_erase_event(a, e)


## A presses whatever is highlighted (Godot's ui_accept has no controller button by default).
func _accept() -> void:
	for pressed in [true, false]:
		var ev := InputEventAction.new()
		ev.action = "ui_accept"
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _dir_now() -> String:
	var i := input
	if i.pad_held(GInput.PAD.UP):
		return "up"
	if i.pad_held(GInput.PAD.DOWN):
		return "down"
	if i.pad_held(GInput.PAD.LEFT):
		return "left"
	if i.pad_held(GInput.PAD.RIGHT):
		return "right"
	var x := i.move_x
	var y := i.move_y
	if Vector2(x, y).length() < 0.55:
		return ""
	if absf(x) > absf(y):
		return "right" if x > 0 else "left"
	return "down" if y > 0 else "up"


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and (c as Control).is_visible_in_tree():
			if (c as Control).focus_mode == Control.FOCUS_ALL and not (c is LineEdit) and not (c is BaseButton and (c as BaseButton).disabled):
				return c
			var f := _first_focusable(c)
			if f:
				return f
	return null


## Call once a frame while a menu is showing.
func update(now: float) -> void:
	if not GInput.using_pad:
		return
	var vp := root.get_viewport()
	var cur := vp.gui_get_focus_owner()
	if cur == null or not root.is_ancestor_of(cur) or not cur.is_visible_in_tree():
		var first := _first_focusable(root)
		if first:
			first.grab_focus()
			_held = _dir_now()
			_repeat_at = now + 0.38
		return
	var d := _dir_now()
	var dpad := input.pad_held(GInput.PAD.UP) or input.pad_held(GInput.PAD.DOWN) or input.pad_held(GInput.PAD.LEFT) or input.pad_held(GInput.PAD.RIGHT)
	if d != _held:
		_held = d
		_repeat_at = now + 0.38
		# the D-pad's first press is handled by Godot's own focus navigation (ui_up/down/left/right)
		if d != "" and not dpad:
			_step(d, cur)
	elif d != "" and now >= _repeat_at:
		var adj := cur is Range and (d == "left" or d == "right")
		_repeat_at = now + (0.05 if adj else 0.13)
		_step(d, cur)
	if input.pad_pressed(GInput.PAD.A):
		_accept()
	if input.pad_pressed(GInput.PAD.B):
		hooks.back.call()
	if input.pad_pressed(GInput.PAD.MENU):
		hooks.start.call()


func _step(d: String, cur: Control) -> void:
	if cur is Range and (d == "left" or d == "right"):
		var r := cur as Range
		var st := maxf(r.step, (r.max_value - r.min_value) / 40.0)
		r.value = clampf(r.value + (st if d == "right" else -st), r.min_value, r.max_value)
		return
	var side := {"up": SIDE_TOP, "down": SIDE_BOTTOM, "left": SIDE_LEFT, "right": SIDE_RIGHT}[d] as int
	var n := cur.find_valid_focus_neighbor(side)
	if n:
		n.grab_focus()
		if n.get_parent() is Control:
			_scroll_into_view(n)


func _scroll_into_view(c: Control) -> void:
	var p := c.get_parent()
	while p:
		if p is ScrollContainer:
			(p as ScrollContainer).ensure_control_visible(c)
			return
		p = p.get_parent()

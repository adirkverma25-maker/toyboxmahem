class_name UI
## Shared look for every screen (port of src/ui/styles.css): "toy packaging" — grape cardboard backers, clear
## blister windows, sticker buttons. Sizes are written in the original's CSS pixels; screens scale them.

const GRAPE := Color("#2b1b4d")
const GRAPE2 := Color("#3d2a6b")
const GRAPE3 := Color("#55408f")
const ORANGE := Color("#ff7a1a")
const SUN := Color("#ffd23f")
const TEAL := Color("#1fb5ad")
const PINK := Color("#ff5d8f")
const PAPER := Color("#fff8ec")
const INK := Color("#1a1030")
const GOOD := Color("#4ade80")
const SHIELD := Color("#5ac8fa")
const DIM := Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.75)

static var DISPLAY: Font = preload("res://assets/fonts/luckiest-guy-latin-400-normal.woff2")
static var BODY: Font = preload("res://assets/fonts/baloo-2-latin-500-normal.woff2")
static var BOLD: Font = preload("res://assets/fonts/baloo-2-latin-700-normal.woff2")
static var hover_sound := Callable()
static var click_sound := Callable()


## Base units (the 1280x720 stretched canvas) per real screen pixel.
static func px(c: CanvasItem) -> float:
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 1.0
	return c.get_viewport().get_visible_rect().size.y / float(win.y)


static func win_size() -> Vector2:
	var w := DisplayServer.window_get_size()
	return Vector2(maxi(1, w.x), maxi(1, w.y))


static func sb(bg: Color, radius := 0, border := 0, border_col := Color.TRANSPARENT, pad := Vector4(0, 0, 0, 0)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(border)
	s.border_color = border_col
	s.content_margin_left = pad.x
	s.content_margin_top = pad.y
	s.content_margin_right = pad.z
	s.content_margin_bottom = pad.w
	s.anti_aliasing = true
	return s


static func card_style(pad := Vector4(32, 28, 32, 28)) -> StyleBoxFlat:
	var s := sb(Color("#34235c"), 28, 4, Color("#4b3685"), pad)
	s.shadow_color = Color(0, 0, 0, 0.45)
	s.shadow_size = 24
	s.shadow_offset = Vector2(0, 12)
	return s


static func blister_style(pad := Vector4(16, 14, 16, 14), radius := 22) -> StyleBoxFlat:
	return sb(Color(1, 1, 1, 0.09), radius, 2, Color(1, 1, 1, 0.28), pad)


static func panel(style: StyleBox) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", style)
	return p


static func card(pad := Vector4(32, 28, 32, 28)) -> PanelContainer:
	return panel(card_style(pad))


static func blister(pad := Vector4(16, 14, 16, 14)) -> PanelContainer:
	return panel(blister_style(pad))


static func label(text: String, font: Font = null, size := 17, color := PAPER, shadow := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font if font else BODY)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	if shadow:
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		l.add_theme_constant_override("shadow_offset_x", 0)
		l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func title(text: String, size := 44) -> Label:
	var l := label(text, DISPLAY, size, SUN)
	l.add_theme_color_override("font_shadow_color", ORANGE)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func para(text: String, size := 17, opacity := 0.85, width := 0.0) -> Label:
	var l := label(text, BODY, size, Color(PAPER, opacity))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if width > 0:
		l.custom_minimum_size.x = width
	return l


static func rich(bb: String, size := 15, font: Font = null, shadow := false) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF
	r.add_theme_font_override("normal_font", font if font else BODY)
	r.add_theme_font_override("bold_font", BOLD)
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_color_override("default_color", PAPER)
	if shadow:
		r.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
		r.add_theme_constant_override("shadow_offset_y", 2)
		r.add_theme_constant_override("shadow_offset_x", 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = bb
	return r


## BBCode for the display font at a size.
static func d(text: String, size: int, color := "") -> String:
	var inner := "[font=res://assets/fonts/luckiest-guy-latin-400-normal.woff2][font_size=%d]%s[/font_size][/font]" % [size, text]
	return "[color=%s]%s[/color]" % [color, inner] if color != "" else inner


static func esc(s: String) -> String:
	return s.replace("[", "[lb]")


static func hexs(c: Color) -> String:
	return "#" + c.to_html(false)


## Sticker button. kind: "" (paper), "primary" (orange), "ghost" (outline). small = the CSS .btn.small size.
static func btn(text: String, kind := "", small := false, cb := Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.alignment = HORIZONTAL_ALIGNMENT_CENTER if small else HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", DISPLAY)
	b.add_theme_font_size_override("font_size", 20 if small else 30)
	var pad := Vector4(16, 9, 16, 6) if small else Vector4(22, 12, 22, 8)
	var r := 18
	var normal: StyleBoxFlat
	var hover: StyleBoxFlat
	var fc := INK
	var fh := INK
	match kind:
		"primary":
			normal = sb(ORANGE, r, 0, Color.TRANSPARENT, pad)
			normal.shadow_color = Color("#b3500c")
			hover = sb(Color("#ff8f3d"), r, 0, Color.TRANSPARENT, pad)
			hover.shadow_color = Color("#b3500c")
			fc = Color.WHITE
			fh = Color.WHITE
		"ghost":
			normal = sb(Color(0, 0, 0, 0), r, 3, Color(1, 1, 1, 0.35), pad)
			hover = sb(Color(1, 1, 1, 0.12), r, 3, SUN, pad)
			fc = PAPER
			fh = SUN
		_:
			normal = sb(PAPER, r, 0, Color.TRANSPARENT, pad)
			normal.shadow_color = Color("#c9b9a0")
			hover = sb(SUN, r, 0, Color.TRANSPARENT, pad)
			hover.shadow_color = Color("#d39a00")
	if kind != "ghost":
		normal.shadow_size = 1
		normal.shadow_offset = Vector2(0, 6)
		hover.shadow_size = 1
		hover.shadow_offset = Vector2(0, 8)
	var pressed: StyleBoxFlat = normal.duplicate()
	pressed.shadow_offset = Vector2(0, 2)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color.a *= 0.5
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("focus", _focus_ring(r))
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("hover_pressed", hover)
	b.add_theme_stylebox_override("disabled", disabled)
	for k in ["font_color", "font_focus_color"]:
		b.add_theme_color_override(k, fc)
	for k in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, fh)
	if kind == "primary":
		b.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.2))
		b.add_theme_constant_override("shadow_offset_y", 2)
	_wire(b, cb)
	return b


static func _focus_ring(r: int) -> StyleBoxFlat:
	var f := sb(Color(0, 0, 0, 0), r + 3, 4, SUN)
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	f.draw_center = false
	return f


static func _wire(b: BaseButton, cb: Callable) -> void:
	b.mouse_entered.connect(func(): if hover_sound.is_valid(): hover_sound.call())
	b.focus_entered.connect(func(): if hover_sound.is_valid() and GInput.using_pad: hover_sound.call())
	b.pressed.connect(func():
		if click_sound.is_valid():
			click_sound.call()
		if cb.is_valid():
			cb.call())


## A choice card (the .seg / .mode-cards / .map-cards buttons): bold title + description, highlighted when chosen.
static func choice(title_text: String, desc: String, chosen: bool, cb := Callable(), tag := "", title_size := 24, desc_size := 14) -> Button:
	var b := Button.new()
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(140, 0)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pad := Vector4(14, 12, 14, 12)
	var n := sb(Color(1, 1, 1, 0.06), 18, 3, Color(1, 1, 1, 0.25), pad)
	var on := sb(Color(1, 210 / 255.0, 63 / 255.0, 0.16), 18, 3, SUN, pad)
	var st := on if chosen else n
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", on if chosen else sb(Color(1, 1, 1, 0.12), 18, 3, Color(1, 1, 1, 0.35), pad))
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", _focus_ring(18))
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.add_child(label(title_text, DISPLAY, title_size))
	if desc != "":
		var dl := para(desc, desc_size, 0.82)
		v.add_child(dl)
	if tag != "":
		var t := panel(sb(Color(1, 1, 1, 0.14), 99, 0, Color.TRANSPARENT, Vector4(8, 2, 8, 2)))
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		t.add_child(label(tag, BODY, 12))
		t.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		v.add_child(t)
	b.add_child(v)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_left = pad.x
	v.offset_top = pad.y
	v.offset_right = -pad.z
	v.offset_bottom = -pad.w
	var fit := func(): b.custom_minimum_size.y = _stack_height(v, b.size.x - pad.x - pad.z) + pad.y + pad.w
	b.resized.connect(fit)
	b.ready.connect(fit)
	_wire(b, cb)
	return b


## Height a VBox of labels needs at a given width (wrapped labels measured at that width, not their current one).
static func _stack_height(v: VBoxContainer, width: float) -> float:
	var h := 0.0
	var n := 0
	for c in v.get_children():
		if not (c is Control) or not (c as Control).visible:
			continue
		n += 1
		if c is Label and (c as Label).autowrap_mode != TextServer.AUTOWRAP_OFF:
			var l := c as Label
			var f := l.get_theme_font("font")
			var fs := l.get_theme_font_size("font_size")
			var lines := maxi(1, f.get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, maxf(1, width), fs).y / f.get_height(fs))
			h += lines * (f.get_height(fs) + l.get_theme_constant("line_spacing"))
		else:
			h += (c as Control).get_combined_minimum_size().y
	return h + maxi(0, n - 1) * v.get_theme_constant("separation")


## Small round chip (scope / saved account / code buttons).
static func chip(text: String, chosen := false, cb := Callable(), size := 14) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.add_theme_font_override("font", BODY)
	b.add_theme_font_size_override("font_size", size)
	var pad := Vector4(11, 5, 11, 5)
	var n := sb(Color(1, 1, 1, 0.08), 999, 2, Color(1, 1, 1, 0.25), pad)
	var on := sb(Color(1, 210 / 255.0, 63 / 255.0, 0.2), 999, 2, SUN, pad)
	b.add_theme_stylebox_override("normal", on if chosen else n)
	b.add_theme_stylebox_override("hover", on)
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("focus", _focus_ring(18))
	b.add_theme_color_override("font_color", PAPER)
	b.add_theme_color_override("font_hover_color", PAPER)
	_wire(b, cb)
	return b


static func hbox(sep := 10) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return h


static func vbox(sep := 10) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return v


static func grid(cols: int, hsep := 16, vsep := 16) -> GridContainer:
	var g := GridContainer.new()
	g.columns = cols
	g.add_theme_constant_override("h_separation", hsep)
	g.add_theme_constant_override("v_separation", vsep)
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return g


static func coin_bb(n: int) -> String:
	return "[color=#ffd23f]●[/color] [b]%s[/b]" % thousands(n)


static func thousands(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func slider(min_v: float, max_v: float, step: float, value: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(104, 22)
	s.focus_mode = Control.FOCUS_ALL
	s.add_theme_stylebox_override("slider", sb(Color(1, 1, 1, 0.22), 99, 0, Color.TRANSPARENT, Vector4(0, 3, 0, 3)))
	s.add_theme_stylebox_override("grabber_area", sb(SUN, 99, 0, Color.TRANSPARENT, Vector4(0, 3, 0, 3)))
	s.add_theme_stylebox_override("grabber_area_highlight", sb(SUN, 99, 0, Color.TRANSPARENT, Vector4(0, 3, 0, 3)))
	s.add_theme_stylebox_override("focus", _focus_ring(8))
	s.value_changed.connect(cb)
	return s


static func check(value: bool, cb: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.button_pressed = value
	c.focus_mode = Control.FOCUS_ALL
	c.add_theme_stylebox_override("focus", _focus_ring(6))
	c.toggled.connect(cb)
	c.mouse_entered.connect(func(): if hover_sound.is_valid(): hover_sound.call())
	return c


static func line_edit(placeholder := "", secret := false, max_len := 14) -> LineEdit:
	var e := LineEdit.new()
	e.placeholder_text = placeholder
	e.secret = secret
	e.max_length = max_len
	e.add_theme_font_override("font", BODY)
	e.add_theme_font_size_override("font_size", 18)
	e.add_theme_color_override("font_color", PAPER)
	e.add_theme_color_override("font_placeholder_color", Color(PAPER, 0.4))
	e.add_theme_stylebox_override("normal", sb(Color(0, 0, 0, 0.25), 12, 3, Color(1, 1, 1, 0.25), Vector4(12, 8, 12, 8)))
	e.add_theme_stylebox_override("focus", sb(Color(0, 0, 0, 0.25), 12, 3, SUN, Vector4(12, 8, 12, 8)))
	return e


## Full-screen dim backdrop (.screen.dim)
static func dim_backdrop() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(26 / 255.0, 16 / 255.0, 48 / 255.0, 0.65)
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	return c


## Scrollable centered panel card of a given CSS width (the .panel-wrap > .panel layout).
static func scroll_panel(width: float, pad := Vector4(32, 28, 32, 28)) -> Array:
	var c := card(pad)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size.x = width - pad.x - pad.z
	var v := vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	c.add_child(sc)
	return [c, sc, v]

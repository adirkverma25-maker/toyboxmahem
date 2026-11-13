extends Control
## The loading screen (port of the loader in src/main.ts): logo, progress bar and the current step.

var bar := HUD.Bar.new()
var step := Label.new()
var frac := 0.0
var shown := 0.0


func _init() -> void:
	name = "Loading"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.color = UI.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var glow := ColorRect.new()
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment(){ float d = distance(UV, vec2(0.5, 0.4)); COLOR = vec4(61.0/255.0, 42.0/255.0, 107.0/255.0, 1.0 - smoothstep(0.0, 0.7, d)); }"
	var sm := ShaderMaterial.new()
	sm.shader = sh
	glow.material = sm
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(glow)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var v := UI.vbox(14)
	var logo := UI.label("Toybox Mayhem", UI.DISPLAY, 56, UI.SUN)
	logo.add_theme_color_override("font_shadow_color", UI.ORANGE)
	logo.add_theme_constant_override("shadow_offset_y", 4)
	logo.rotation = deg_to_rad(-3)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(logo)
	bar.custom_minimum_size = Vector2(260, 14)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bar.bg = Color(1, 1, 1, 0.12)
	bar.border = 0
	bar.radius = 99
	bar.fill_a = UI.TEAL
	bar.fill_b = UI.SUN
	bar.frac = 0
	bar.ghost = 0
	v.add_child(bar)
	step = UI.label("Opening the toy box", UI.BODY, 15, Color(UI.PAPER, 0.8))
	step.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(step)
	c.add_child(v)


func _process(dt: float) -> void:
	var k := UI.px(self) * clampf(UI.win_size().y / 900.0, 0.7, 1.35)
	scale = Vector2.ONE
	shown += (frac - shown) * minf(1, dt * 8)
	bar.frac = shown
	bar.ghost = shown
	bar.queue_redraw()
	pivot_offset = size / 2
	(get_child(2) as Control).scale = Vector2(k, k)
	(get_child(2) as Control).pivot_offset = size / 2


func set_step(text: String, f: float) -> void:
	step.text = text
	frac = f


func finish() -> void:
	frac = 1.0
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.5)
	tw.tween_callback(queue_free)

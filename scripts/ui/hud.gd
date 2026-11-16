class_name HUD
extends Control
## In-match HUD (port of src/ui/HUD.ts): crosshair, scopes, hit markers, damage numbers, health/shield,
## weapon + ammo, abilities, timer and scores, kill feed, announcements, death screen, scoreboard, team tags,
## objective markers. Corner panels scale like the original's CSS zoom; screen-space marks stay pixel-sized.

const ABIL_UI := [["dash", "Dash"], ["jab", "Punch"], ["grapple", "Hook"], ["cloak", "Cloak"], ["shield", "Shield"]]
const STREAKS := {2: "Double pop!", 3: "Triple pop!", 4: "Toy box tantrum!", 5: "Unstoppable toy!", 7: "Playroom legend!", 10: "Toy of the year!"}
const FX_SHADER := preload("res://shaders/hud_fx.gdshader")

var fx_rect := ColorRect.new()
var fx_mat := ShaderMaterial.new()
var overlay := Overlay.new()
var panels := Control.new()
# panel widgets
var top_row := HBoxContainer.new()
var my_chip: Dictionary
var lead_chip: Dictionary
var third_chip: Dictionary
var timer_panel: PanelContainer
var timer_label: Label
var mini := PanelContainer.new()
var mini_box := VBoxContainer.new()
var feed := VBoxContainer.new()
var vitals := VBoxContainer.new()
var buffs_row := HBoxContainer.new()
var sh_bar := Bar.new()
var hp_bar := Bar.new()
var weapon_box := VBoxContainer.new()
var w_name: Label
var w_mag: Label
var w_res: Label
var w_energy := Bar.new()
var w_slots := HBoxContainer.new()
var abil_row := HBoxContainer.new()
var abil_icons: Array = []
var prompt := PanelContainer.new()
var prompt_label: Label
var center := VBoxContainer.new()
var announce_box := VBoxContainer.new()
var announce_label: Label
var announce_sub: Label
var countdown_label: Label
var pickups := VBoxContainer.new()
var zone_label: Label
var death := Control.new()
var death_box := PanelContainer.new()
var death_title: Label
var death_by: Label
var death_respawn: Label
var death_spec: Label
var board := PanelContainer.new()
var board_body := VBoxContainer.new()
var fps_label: Label
var obj_status := PanelContainer.new()
var obj_box := VBoxContainer.new()
# state
var nums: Array = []
var dirs: Array = []
var announce_t := 0.0
var center_t := 0.0
var hp_shown := 100.0
var sh_shown := 0.0
var last_hp := 100.0
var last_sh := 0.0
var hurt_t := 0.0
var shield_t := 0.0
var board_visible := false
var last_mini := ""
var last_weapon_key := ""
var last_buff_key := ""
var last_obj := ""
var last_board := 0.0
var killer_name := ""
var killer_weapon := ""
var fps_acc := 0.0
var fps_frames := 0
var hit_kind := ""
var hit_t := 0.0
var countdown_hide_at := -1.0
var clock := 0.0
var scope_kind := ""
var teams_mode := false
var conquest_mode := false
# snapshot for the overlay
var o := {}


func _init() -> void:
	name = "HUD"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx_mat.shader = FX_SHADER
	fx_rect.material = fx_mat
	fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(fx_rect)
	overlay.hud = self
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	panels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panels)
	_build_panels()
	for i in 32:
		nums.append({"pos": Vector3.ZERO, "life": 0.0, "drift": 0.0, "text": "", "kind": "body"})
	for i in 6:
		dirs.append({"from": Vector3.ZERO, "life": 0.0, "ang": 0.0})


static func _dark(alpha: float, radius := 14, pad := Vector4(12, 6, 12, 6)) -> StyleBoxFlat:
	return UI.sb(Color(43 / 255.0, 27 / 255.0, 77 / 255.0, alpha), radius, 0, Color.TRANSPARENT, pad)


func _chip() -> Dictionary:
	var p := UI.panel(_dark(0.65))
	var v := UI.vbox(0)
	var big := UI.label("0", UI.DISPLAY, 24, UI.PAPER, true)
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var small := UI.label("You", UI.BODY, 15, UI.PAPER, true)
	small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var meter := Bar.new()
	meter.custom_minimum_size = Vector2(0, 7)
	meter.bg = Color(1, 1, 1, 0.18)
	meter.radius = 99
	meter.visible = false
	v.add_child(big)
	v.add_child(small)
	v.add_child(meter)
	p.add_child(v)
	return {"panel": p, "big": big, "small": small, "meter": meter}


func _anchor(c: Control, preset: int, ox: float, oy: float) -> void:
	c.set_anchors_preset(preset)
	c.grow_horizontal = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_TOP_RIGHT, Control.PRESET_BOTTOM_RIGHT] else (Control.GROW_DIRECTION_BOTH if preset in [Control.PRESET_CENTER_TOP, Control.PRESET_CENTER_BOTTOM, Control.PRESET_CENTER] else Control.GROW_DIRECTION_END)
	c.grow_vertical = Control.GROW_DIRECTION_BEGIN if preset in [Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT, Control.PRESET_CENTER_BOTTOM] else Control.GROW_DIRECTION_END
	c.offset_left = ox
	c.offset_right = ox
	c.offset_top = oy
	c.offset_bottom = oy


func _build_panels() -> void:
	# top center: score chips + timer
	top_row.add_theme_constant_override("separation", 12)
	top_row.alignment = BoxContainer.ALIGNMENT_CENTER
	my_chip = _chip()
	lead_chip = _chip()
	third_chip = _chip()
	timer_panel = UI.panel(UI.sb(Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.78), 16, 3, Color(1, 1, 1, 0.2), Vector4(18, 8, 18, 3)))
	timer_label = UI.label("10:00", UI.DISPLAY, 30, UI.PAPER, true)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.custom_minimum_size.x = 68
	timer_panel.add_child(timer_label)
	timer_panel.pivot_offset = Vector2(52, 22)
	top_row.add_child(my_chip.panel)
	top_row.add_child(timer_panel)
	top_row.add_child(lead_chip.panel)
	top_row.add_child(third_chip.panel)
	third_chip.panel.visible = false
	panels.add_child(top_row)
	_anchor(top_row, Control.PRESET_CENTER_TOP, 0, 14)
	# mini scoreboard
	mini.add_theme_stylebox_override("panel", _dark(0.62, 16, Vector4(10, 8, 10, 8)))
	mini.custom_minimum_size.x = 230
	mini_box.add_theme_constant_override("separation", 1)
	mini.add_child(mini_box)
	panels.add_child(mini)
	_anchor(mini, Control.PRESET_TOP_LEFT, 14, 14)
	# kill feed
	feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	feed.add_theme_constant_override("separation", 5)
	panels.add_child(feed)
	_anchor(feed, Control.PRESET_TOP_RIGHT, -14, 14)
	# vitals
	vitals.custom_minimum_size.x = 330
	vitals.add_theme_constant_override("separation", 7)
	buffs_row.custom_minimum_size.y = 40
	buffs_row.add_theme_constant_override("separation", 8)
	sh_bar.custom_minimum_size = Vector2(330, 14)
	sh_bar.fill_a = Color("#38bdf8")
	sh_bar.fill_b = Color("#a5f3fc")
	sh_bar.text_size = 12
	hp_bar.custom_minimum_size = Vector2(330, 22)
	vitals.add_child(buffs_row)
	vitals.add_child(sh_bar)
	vitals.add_child(hp_bar)
	panels.add_child(vitals)
	_anchor(vitals, Control.PRESET_BOTTOM_LEFT, 22, -22)
	# weapon
	weapon_box.alignment = BoxContainer.ALIGNMENT_END
	weapon_box.add_theme_constant_override("separation", 0)
	w_name = UI.label("", UI.DISPLAY, 22, UI.PAPER, true)
	w_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var ammo := UI.hbox(6)
	ammo.alignment = BoxContainer.ALIGNMENT_END
	w_mag = UI.label("", UI.DISPLAY, 58, UI.PAPER, true)
	w_res = UI.label("", UI.DISPLAY, 26, Color(UI.PAPER, 0.7), true)
	w_res.size_flags_vertical = Control.SIZE_SHRINK_END
	ammo.add_child(w_mag)
	ammo.add_child(w_res)
	w_energy.custom_minimum_size = Vector2(210, 10)
	w_energy.size_flags_horizontal = Control.SIZE_SHRINK_END
	w_energy.bg = Color(1, 1, 1, 0.15)
	w_energy.border = 0
	w_energy.fill_a = Color("#21e6ff")
	w_energy.fill_b = Color("#b8fbff")
	w_energy.radius = 99
	w_slots.alignment = BoxContainer.ALIGNMENT_END
	w_slots.add_theme_constant_override("separation", 6)
	weapon_box.add_child(w_name)
	weapon_box.add_child(ammo)
	weapon_box.add_child(w_energy)
	weapon_box.add_child(w_slots)
	panels.add_child(weapon_box)
	_anchor(weapon_box, Control.PRESET_BOTTOM_RIGHT, -22, -20)
	# abilities
	abil_row.add_theme_constant_override("separation", 12)
	for u in ABIL_UI:
		var col := UI.vbox(3)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var icon := AbilIcon.new()
		icon.custom_minimum_size = Vector2(50, 50)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var l := UI.label(u[1], UI.BOLD, 13, UI.PAPER, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(icon)
		col.add_child(l)
		abil_row.add_child(col)
		abil_icons.append({"id": u[0], "col": col, "icon": icon})
	panels.add_child(abil_row)
	_anchor(abil_row, Control.PRESET_CENTER_BOTTOM, 0, -18)
	# interact prompt
	prompt.add_theme_stylebox_override("panel", _dark(0.8, 14, Vector4(16, 6, 16, 6)))
	prompt_label = UI.label("", UI.BODY, 17, UI.PAPER, true)
	prompt.add_child(prompt_label)
	panels.add_child(prompt)
	_anchor(prompt, Control.PRESET_CENTER_BOTTOM, 0, -110)
	# center message (eliminations, streaks)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	panels.add_child(center)
	# announcements
	announce_label = UI.label("", UI.DISPLAY, 46, UI.SUN)
	announce_label.add_theme_color_override("font_shadow_color", UI.ORANGE)
	announce_label.add_theme_constant_override("shadow_offset_y", 4)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_sub = UI.label("", UI.BODY, 19, UI.PAPER, true)
	announce_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_box.add_theme_constant_override("separation", 0)
	announce_box.add_child(announce_label)
	announce_box.add_child(announce_sub)
	announce_box.visible = false
	panels.add_child(announce_box)
	countdown_label = UI.label("3", UI.DISPLAY, 140, UI.SUN)
	countdown_label.add_theme_color_override("font_shadow_color", UI.ORANGE)
	countdown_label.add_theme_constant_override("shadow_offset_y", 8)
	countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	countdown_label.visible = false
	panels.add_child(countdown_label)
	# pickups + zone
	pickups.add_theme_constant_override("separation", 4)
	panels.add_child(pickups)
	_anchor(pickups, Control.PRESET_BOTTOM_LEFT, 22, -150)
	zone_label = UI.label("", UI.BODY, 14, Color(UI.PAPER, 0.7), true)
	panels.add_child(zone_label)
	_anchor(zone_label, Control.PRESET_BOTTOM_LEFT, 22, -125)
	# death overlay
	var dbg := ColorRect.new()
	dbg.color = Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.35)
	dbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dbg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	death.add_child(dbg)
	death.set_meta("bg", dbg)
	death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	death_box.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var dv := UI.vbox(2)
	dv.alignment = BoxContainer.ALIGNMENT_CENTER
	death_title = UI.label("Popped!", UI.DISPLAY, 52, UI.PINK)
	death_title.add_theme_color_override("font_shadow_color", Color("#7a1f3d"))
	death_title.add_theme_constant_override("shadow_offset_y", 4)
	death_by = UI.label("", UI.BODY, 20, UI.PAPER, true)
	death_respawn = UI.label("", UI.DISPLAY, 28, UI.SUN, true)
	death_spec = UI.label("", UI.BODY, 18, Color("#d7f5ff"), true)
	for l in [death_title, death_by, death_respawn, death_spec]:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dv.add_child(l)
	death_box.add_child(dv)
	death.add_child(death_box)
	death.visible = false
	panels.add_child(death)
	# scoreboard
	board.add_theme_stylebox_override("panel", UI.card_style(Vector4(22, 18, 22, 18)))
	board.custom_minimum_size.x = 760
	board.add_child(board_body)
	board.visible = false
	panels.add_child(board)
	fps_label = UI.label("", UI.BODY, 12, Color(UI.PAPER, 0.6))
	panels.add_child(fps_label)
	_anchor(fps_label, Control.PRESET_BOTTOM_RIGHT, -10, -4)
	# objective status
	obj_status.add_child(obj_box)
	obj_box.add_theme_constant_override("separation", 1)
	obj_status.visible = false
	panels.add_child(obj_status)


func _process(_dt: float) -> void:
	# panels zoom like the original: clamp(min(h/1000, w/1700), 0.62, 1.45) in screen pixels
	var win := UI.win_size()
	var k := UI.px(self)
	var z := clampf(minf(win.y / 1000.0, win.x / 1700.0), 0.62, 1.45) * k
	panels.scale = Vector2(z, z)
	panels.size = size / z
	fx_mat.set_shader_parameter("aspect", Vector2(size.x / maxf(1, size.y), 1.0))
	# centered elements
	var ps := panels.size
	center.position = Vector2((ps.x - center.size.x) / 2, ps.y * 0.27)
	announce_box.position = Vector2((ps.x - announce_box.size.x) / 2, ps.y * 0.16)
	announce_box.pivot_offset = announce_box.size / 2
	countdown_label.position = Vector2((ps.x - countdown_label.size.x) / 2, ps.y * 0.4 - countdown_label.size.y / 2)
	countdown_label.pivot_offset = countdown_label.size / 2
	death.position = Vector2.ZERO
	death.size = ps
	if death.has_meta("spectating") and death.get_meta("spectating"):
		death_box.position = Vector2((ps.x - death_box.size.x) / 2, ps.y - 150 - death_box.size.y)
	else:
		death_box.position = (ps - death_box.size) / 2
	board.position = (ps - board.size) / 2
	obj_status.position = Vector2((ps.x - obj_status.size.x) / 2, 92)


func _pop(c: Control, from := 0.4, dur := 0.35) -> void:
	c.pivot_offset = c.size / 2
	c.scale = Vector2.ONE * from
	c.modulate.a = 0
	var tw := c.create_tween().set_parallel()
	tw.tween_property(c, "scale", Vector2.ONE, dur).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, dur * 0.5)


## Called at match start so the top bar matches the mode.
func set_mode(m: Match) -> void:
	teams_mode = m.teams()
	conquest_mode = m.mode.id == "conquest"
	last_mini = ""
	last_obj = ""
	obj_status.visible = m.mode.id == "takeover" or m.mode.id == "conquest"
	third_chip.panel.visible = m.team_count() == 3
	for c in [my_chip, lead_chip, third_chip]:
		c.meter.visible = teams_mode
		var st: StyleBoxFlat = _dark(0.65)
		if teams_mode:
			st.set_border_width_all(3)
		c.panel.add_theme_stylebox_override("panel", st)
		c.panel.custom_minimum_size.x = (120 if conquest_mode else 150) if teams_mode else 0


func apply_settings() -> void:
	fps_label.visible = Settings.get_v("showFps")


func show_hud(on: bool) -> void:
	visible = on


func reset() -> void:
	for c in feed.get_children():
		c.queue_free()
	for c in pickups.get_children():
		c.queue_free()
	for c in center.get_children():
		c.queue_free()
	last_mini = ""
	last_weapon_key = ""
	last_buff_key = ""
	last_obj = ""
	for n in nums:
		n.life = 0
	for d in dirs:
		d.life = 0
	death.visible = false
	announce_box.visible = false
	countdown_label.visible = false
	hp_shown = 100
	sh_shown = 0


# ------------------------------------------------------------------ feedback
func hit(kind: String) -> void:
	hit_kind = kind
	hit_t = 0.22


func damage_number(pos: Vector3, amount: float, kind: String) -> void:
	if not Settings.get_v("damageNumbers"):
		return
	var n: Dictionary = nums[0]
	for x in nums:
		if x.life < n.life:
			n = x
	n.pos = pos
	n.life = 0.9
	n.drift = (randf() - 0.5) * 40
	n.kind = kind
	n.text = str(roundi(amount))


func damage_from(from: Vector3) -> void:
	var d: Dictionary = dirs[0]
	for x in dirs:
		if x.life < d.life:
			d = x
	d.from = from
	d.life = 1.2


func hurt(shield: bool) -> void:
	if shield:
		shield_t = 0.3
	else:
		hurt_t = 0.35


static func name_color(a: Actor) -> String:
	return Modes.TEAMS[a.team].light if a.team >= 0 else a.def.accent


func kill_feed(killer, victim: Actor, weapon: String, head: bool, mine: bool) -> void:
	var row := UI.panel(UI.sb(Color(1, 122 / 255.0, 26 / 255.0, 0.75) if mine else Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.7), 12, 0, Color.TRANSPARENT, Vector4(12, 4, 12, 4)))
	var kn := "[color=%s]%s[/color]" % [name_color(killer), UI.esc(killer.name)] if killer else ""
	var w := "[bgcolor=#ffffff2e] %s%s [/bgcolor]" % [UI.d(UI.esc(weapon), 13), " [color=#ffd23f]★[/color]" if head else ""]
	row.add_child(UI.rich("%s  %s  [color=%s]%s[/color]" % [kn, w, name_color(victim), UI.esc(victim.name)], 15, null, true))
	row.size_flags_horizontal = Control.SIZE_SHRINK_END
	feed.add_child(row)
	feed.move_child(row, 0)
	while feed.get_child_count() > 6:
		var last := feed.get_child(feed.get_child_count() - 1)
		feed.remove_child(last)
		last.queue_free()
	_pop_in(row)
	var tw := row.create_tween()
	tw.tween_interval(5.2)
	tw.tween_property(row, "modulate:a", 0.0, 0.6)
	tw.tween_callback(row.queue_free)


func _pop_in(c: Control) -> void:
	c.modulate.a = 0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.25)


func eliminated(nm: String, streak: int, head: bool) -> void:
	for c in center.get_children():
		c.queue_free()
	var e := UI.rich("[center]%s %s%s[/center]" % [UI.d("Popped " + UI.esc(nm), 34), UI.d("+1", 34, "#ffd23f"), ("\n[color=#ffd23f]Headshot[/color]" if head else "")], 17, null, true)
	e.custom_minimum_size.x = 700
	center.add_child(e)
	if STREAKS.has(streak):
		var s := UI.label(STREAKS[streak], UI.DISPLAY, 26, UI.PINK, true)
		s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		center.add_child(s)
		_pop(s)
	_pop(e)
	center_t = 2.2


func pickup(lbl: String, color: String) -> void:
	var st := _dark(0.75, 12, Vector4(12, 4, 12, 4))
	st.border_width_left = 6
	st.border_color = U.col(color)
	var row := UI.panel(st)
	row.add_child(UI.label(lbl, UI.BODY, 16, UI.PAPER, true))
	row.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	pickups.add_child(row)
	pickups.move_child(row, 0)
	while pickups.get_child_count() > 4:
		var last := pickups.get_child(pickups.get_child_count() - 1)
		pickups.remove_child(last)
		last.queue_free()
	_pop_in(row)
	var tw := row.create_tween()
	tw.tween_interval(2.5)
	tw.tween_property(row, "modulate:a", 0.0, 0.5)
	tw.tween_callback(row.queue_free)


func announce(text: String, sub := "", dur := 2.6) -> void:
	announce_label.text = text
	announce_sub.text = sub
	announce_sub.visible = sub != ""
	announce_box.visible = true
	announce_box.reset_size()
	_pop(announce_box, 0.4, 0.4)
	announce_t = dur


func countdown(v) -> void:
	if v == null:
		countdown_label.visible = false
		return
	countdown_label.text = "GO!" if v is String else str(v)
	countdown_label.visible = true
	countdown_label.reset_size()
	_pop(countdown_label, 0.4, 0.3)
	countdown_hide_at = clock + 0.8 if v is String else -1.0


func set_death(killer: String, weapon: String) -> void:
	killer_name = killer
	killer_weapon = weapon


func set_scoreboard(on: bool) -> void:
	board_visible = on
	board.visible = on


## The standings table (also used by the results screen).
static func build_board(actors: Array, m: Match, me) -> Control:
	var v := UI.vbox(5)
	var header := func() -> Control:
		return _board_row(["#", "Toy", "Pops", "Popped", "Best streak", "Damage"], false, true, "")
	if m.teams():
		for t in m.team_scores.size():
			var team: Dictionary = Modes.TEAMS[t]
			var head := UI.panel(UI.sb(Color(U.col(team.color), 0.55), 12, 0, Color.TRANSPARENT, Vector4(12, 4, 12, 2)))
			var hh := UI.hbox()
			var tl := UI.label("Team " + team.name, UI.DISPLAY, 22)
			tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var suffix := " / %d" % m.mode.scoreTarget if m.mode.id == "takeover" else (" / 6 sectors" if m.mode.id == "conquest" else "")
			hh.add_child(tl)
			hh.add_child(UI.label(str(floori(m.team_scores[t])) + suffix, UI.DISPLAY, 26))
			head.add_child(hh)
			v.add_child(head)
			v.add_child(header.call())
			var i := 1
			for a in m.standings(actors.filter(func(x): return x.team == t)):
				v.add_child(_board_row([str(i), a.name, str(a.kills), str(a.deaths), str(a.best_streak), str(roundi(a.damage_dealt))], a == me, false, a.def.accent))
				i += 1
		return v
	v.add_child(header.call())
	var i := 1
	for a in m.standings(actors):
		v.add_child(_board_row([str(i), a.name, str(a.kills), str(a.deaths), str(a.best_streak), str(roundi(a.damage_dealt))], a == me, false, a.def.accent))
		i += 1
	return v


static func _board_row(cells: Array, me: bool, head: bool, dot: String) -> Control:
	var p := UI.panel(StyleBoxEmpty.new() if head else UI.sb(Color(1, 210 / 255.0, 63 / 255.0, 0.2) if me else Color(1, 1, 1, 0.06), 12, 0, Color.TRANSPARENT, Vector4(10, 4, 10, 4)))
	var h := UI.hbox(8)
	var widths := [30, 0, 70, 80, 110, 90]
	for i in cells.size():
		var l: Control
		if i == 1 and not head:
			l = UI.rich("[color=%s]●[/color] %s" % [dot, UI.esc(cells[i])], 16)
		else:
			l = UI.label(cells[i], UI.DISPLAY if (i == 0 and not head) else UI.BODY, 14 if head else 16, Color(UI.PAPER, 0.65 if head else 1.0))
			if i >= 2:
				(l as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if widths[i] > 0:
			l.custom_minimum_size.x = widths[i]
		else:
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
	p.add_child(h)
	return p


# ------------------------------------------------------------------ per frame
func update(dt: float, now: float, p: Player, actors: Array, m: Match, cam: Camera3D, zone_name: String) -> void:
	clock += dt
	var a := p.actor
	fps_acc += dt
	fps_frames += 1
	if fps_acc > 0.5:
		fps_label.text = "%d fps" % roundi(fps_frames / fps_acc)
		fps_acc = 0
		fps_frames = 0
	var ws := a.weapon()
	var alive := a.alive
	hit_t = maxf(0, hit_t - dt)
	if countdown_hide_at > 0 and clock >= countdown_hide_at:
		countdown_label.visible = false
		countdown_hide_at = -1
	# vitals with smooth animation
	if a.health < last_hp - 0.5 or a.shield < last_sh - 0.5:
		hurt(a.shield < last_sh - 0.5 and a.health >= last_hp - 0.5)
	last_hp = a.health
	last_sh = a.shield
	hp_shown += (a.health - hp_shown) * minf(1, dt * 12)
	sh_shown += (a.shield - sh_shown) * minf(1, dt * 12)
	hp_bar.frac = clampf(hp_shown / a.max_health, 0, 1)
	hp_bar.ghost = a.health / a.max_health
	hp_bar.text = str(ceili(a.health))
	var low := a.health < 35
	hp_bar.fill_a = Color("#ef4444") if low else Color("#22c55e")
	hp_bar.fill_b = Color("#fb7185") if low else Color("#86efac")
	sh_bar.frac = clampf(sh_shown / Cfg.COMBAT.maxShield, 0, 1)
	sh_bar.ghost = a.shield / Cfg.COMBAT.maxShield
	sh_bar.text = str(ceili(a.shield)) if a.shield > 0 else ""
	sh_bar.modulate.a = 1.0 if a.shield > 0 else 0.45
	hp_bar.queue_redraw()
	sh_bar.queue_redraw()
	hurt_t = maxf(0, hurt_t - dt)
	shield_t = maxf(0, shield_t - dt)
	fx_mat.set_shader_parameter("vignette", clampf((45 - a.health) / 45, 0, 1) * 0.8 if alive else 0.0)
	fx_mat.set_shader_parameter("hurt", clampf(hurt_t * 2, 0, 1))
	fx_mat.set_shader_parameter("shield", clampf(shield_t * 2.5, 0, 1))
	fx_mat.set_shader_parameter("cloak", 1.0 if alive and a.cloaked else 0.0)
	# buffs
	var buff_list := ["turbo", "infinite", "power"].filter(func(k): return a.buffs[k] > now)
	var bkey := ",".join(buff_list)
	if bkey != last_buff_key:
		last_buff_key = bkey
		for c in buffs_row.get_children():
			c.queue_free()
		for k in buff_list:
			var b := BuffIcon.new()
			b.kind = k
			b.custom_minimum_size = Vector2(40, 40)
			buffs_row.add_child(b)
	for b in buffs_row.get_children():
		if b is BuffIcon:
			var total := 6.0 if b.kind == "infinite" else 8.0
			b.left = maxf(0, a.buffs[b.kind] - now) / total
			b.queue_redraw()
	# weapon
	if ws:
		var other = a.weapons[1 if a.slot == 0 else 0]
		var inf := a.has_buff("infinite", now)
		var key := "%s|%d|%d|%d|%s|%s|%s|%s|%s%s%s" % [ws.id, ceili(ws.mag), ws.reserve, a.slot, other.id if other else "", inf, ws.lockout, GInput.using_pad, GInput.action_name("swap"), GInput.action_name("weapon1"), GInput.action_name("weapon2")]
		if key != last_weapon_key:
			last_weapon_key = key
			var lowm: bool = ws.mag <= ws.cfg.magSize * 0.25
			var res: String = ("cooling" if ws.lockout else "energy") if ws.is_energy() else ("∞" if inf else str(ws.reserve))
			var cc: String = ws.cfg.colors.accent if ws.cfg.colors.main in ["#1d1d1f", "#f2f7ff"] else ws.cfg.colors.main
			w_name.text = ws.cfg.name
			w_name.add_theme_color_override("font_color", U.col(cc))
			w_mag.text = str(ceili(ws.mag))
			w_mag.add_theme_color_override("font_color", UI.PINK if lowm else UI.PAPER)
			w_res.text = "/ " + res
			w_energy.visible = ws.is_energy()
			for c in w_slots.get_children():
				c.queue_free()
			for i in a.weapons.size():
				var w = a.weapons[i]
				if w == null:
					continue
				var on: bool = i == a.slot
				var sp := UI.panel(UI.sb(Color(1, 210 / 255.0, 63 / 255.0, 0.3) if on else Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.6), 10, 0, Color.TRANSPARENT, Vector4(9, 3, 9, 3)))
				sp.modulate.a = 1.0 if on else 0.65
				var kk := _slot_key(i, a.slot)
				sp.add_child(UI.rich(("[bgcolor=#fff8ec][color=#1a1030][b] %s [/b][/color][/bgcolor] " % kk if kk != "" else "") + w.cfg.name, 13, null, true))
				w_slots.add_child(sp)
		if ws.is_energy():
			w_energy.frac = ws.mag / ws.cfg.magSize
			w_energy.queue_redraw()
	# abilities
	for i in abil_icons.size():
		var e: Dictionary = abil_icons[i]
		var id: String = e.id
		var slot := a.abilities.find(id)
		e.col.visible = slot >= 0
		if slot < 0:
			continue
		abil_row.move_child(e.col, mini(slot, abil_row.get_child_count() - 1))
		var k := GInput.action_name("ability2" if slot else "ability1", true)
		var icon: AbilIcon = e.icon
		icon.key = "–" if k == "unbound" else k
		var left := 0.0
		var total := 1.0
		var active := false
		var active_frac := 0.0
		match id:
			"dash":
				left = a.dash_ready_at - now
				total = Cfg.MOVE.dashCooldown
			"jab":
				left = a.jab_ready_at - now
				total = Cfg.ABILITIES.jab.cooldown
			"grapple":
				left = a.grapple_ready_at - now
				total = Cfg.ABILITIES.grapple.cooldown
				active = a.grapple != null
			"shield":
				left = a.shield_ready_at - now
				total = Cfg.ABILITIES.shield.cooldown
			_:
				if a.cloaked:
					active = true
					active_frac = 1 - (now - a.cloak_start) / Cfg.ABILITIES.cloak.maxActive
				else:
					left = a.cloak_ready_at - now
					total = maxf(left, Cfg.ABILITIES.cloak.baseCooldown)
		left = maxf(0, left)
		icon.is_ready = left <= 0 and not active
		icon.active = active
		icon.denied = p.denied.key == id and now - p.denied.at < 0.35
		icon.frac = minf(1, 1 - maxf(0, active_frac) if active else left / maxf(0.01, total))
		if active and id == "cloak":
			icon.cd = str(ceili(maxf(0, active_frac) * Cfg.ABILITIES.cloak.maxActive))
		elif left > 0:
			icon.cd = ("%.1f" % left) if left < 10 else str(ceili(left))
		else:
			icon.cd = ""
		icon.queue_redraw()
	# prompt
	prompt.visible = p.interact_prompt != ""
	if prompt.visible:
		prompt_label.text = p.interact_prompt
		prompt.reset_size()
	# timer + scores
	var t: float = m.mode.timeLimit if m.phase == "countdown" else m.time_left
	timer_label.text = U.format_time(t)
	var training: bool = m.mode.get("training", false)
	var tlow := t < 30 and m.phase == "playing" and not training
	timer_label.add_theme_color_override("font_color", UI.PINK if tlow else UI.PAPER)
	timer_panel.scale = Vector2.ONE * (1 + 0.06 * maxf(0, sin(clock * TAU)) if tlow and not Settings.get_v("reducedMotion") else 1.0)
	var standings := m.standings(actors)
	var leader: Actor = standings[0] if standings.size() else null
	var my_rank := standings.find(a) + 1
	if m.teams():
		var mine := maxi(0, a.team)
		var others := range(m.team_scores.size()).filter(func(x): return x != mine)
		var tgt: float = m.mode.scoreTarget
		var conq: bool = m.mode.id == "conquest"
		var chip := func(c: Dictionary, team: int) -> void:
			var sc: float = m.team_scores[team]
			c.big.text = str(floori(sc)) + ("/%d" % tgt if conq else "")
			c.small.text = "Team " + Modes.TEAMS[team].name
			c.meter.frac = minf(1, sc / tgt)
			c.meter.fill_a = U.col(Modes.TEAMS[team].color)
			c.meter.fill_b = c.meter.fill_a
			c.meter.queue_redraw()
			(c.panel.get_theme_stylebox("panel") as StyleBoxFlat).border_color = U.col(Modes.TEAMS[team].color)
		chip.call(my_chip, mine)
		if others.size() > 0:
			chip.call(lead_chip, others[0])
		if others.size() > 1:
			chip.call(third_chip, others[1])
		var mates := m.standings(actors.filter(func(x): return x.team == a.team))
		var mk := ""
		for x in mates:
			mk += "%d:%d:%s|" % [x.id, x.kills, x.alive]
		mk += m.mode.id
		if mk != last_mini:
			last_mini = mk
			var goal := "Hold the toy box. First to %d" % tgt if m.mode.id == "takeover" else ("Control %d of 6 sectors" % tgt if conq else "First team to %d pops" % tgt)
			_fill_mini(goal, mates.map(func(x): return [("●" if x.alive else "✕"), x.name, x.kills, x == a, "#ffd23f" if x == a else Modes.TEAMS[x.team].light, not x.alive]))
	elif training:
		# training: your own numbers instead of a leaderboard
		var acc := roundi(float(a.shots_hit) / a.shots_fired * 100) if a.shots_fired else 0
		my_chip.big.text = str(a.kills)
		my_chip.small.text = "Pops"
		lead_chip.big.text = "%d%%" % acc
		lead_chip.small.text = "Accuracy"
		var mk := "t%d:%d:%d:%d:%d:%d" % [a.kills, a.headshots, a.shots_hit, a.shots_fired, a.streak, a.best_streak]
		if mk != last_mini:
			last_mini = mk
			_fill_mini("Training range", [
				["", "Pops", a.kills, false, "#ffffff", false],
				["", "Headshots", a.headshots, false, "#ffffff", false],
				["", "Hits / shots", "%d/%d" % [a.shots_hit, a.shots_fired], false, "#ffffff", false],
				["", "Streak (best)", "%d (%d)" % [a.streak, a.best_streak], false, "#ffffff", false],
			])
	else:
		my_chip.big.text = str(a.kills)
		my_chip.small.text = "You"
		var leader_other: Actor = (standings[1] if standings.size() > 1 else null) if leader == a else leader
		lead_chip.big.text = str(leader_other.kills if leader_other else 0)
		lead_chip.small.text = "2nd" if leader == a else "Leader"
		var top := standings.slice(0, 4)
		if not top.has(a):
			top.append(a)
		var mk := ""
		for x in top:
			mk += "%d:%d|" % [x.id, x.kills]
		mk += str(my_rank)
		if mk != last_mini:
			last_mini = mk
			_fill_mini("First to %d pops" % m.kill_target(), top.map(func(x): return [str(standings.find(x) + 1), x.name, x.kills, x == a, "#ffd23f" if x == a else x.def.accent, false]))
	# damage numbers + direction indicators are drawn by the overlay; age them here
	for n in nums:
		if n.life > 0:
			n.life -= dt
	for d in dirs:
		if d.life > 0:
			d.life -= dt
			var dx: float = d.from.x - a.pos.x
			var dz: float = d.from.z - a.pos.z
			d.ang = atan2(-dx, -dz) - a.yaw
	# transient messages
	if center_t > 0:
		center_t -= dt
		if center_t <= 0:
			for c in center.get_children():
				c.queue_free()
	if announce_t > 0:
		announce_t -= dt
		if announce_t <= 0:
			announce_box.visible = false
	# death overlay
	death.visible = not alive and m.phase != "ended"
	if not alive:
		death_by.text = "by %s with %s" % [killer_name, killer_weapon] if killer_name != "" else killer_weapon
		death_respawn.text = "Reassembling in %.1f" % maxf(0, a.respawn_at - now)
		var sp := p.spectating
		death.set_meta("spectating", sp != null)
		(death.get_meta("bg") as ColorRect).visible = sp == null
		death_box.add_theme_stylebox_override("panel", _dark(0.72, 16, Vector4(22, 8, 22, 8)) if sp else StyleBoxEmpty.new())
		death_title.add_theme_font_size_override("font_size", 26 if sp else 52)
		death_respawn.add_theme_font_size_override("font_size", 20 if sp else 28)
		var note := ""
		if a.revive_t > 0 and a.reviver:
			note = "%s is reviving you  %d%%" % [a.reviver.name, roundi(a.revive_t / Cfg.COMBAT.reviveTime * 100)]
		elif a.reviver:
			note = "%s is coming to revive you" % a.reviver.name
		elif sp:
			note = "Spectating %s. Click for the next teammate" % sp.name
		elif m.teams():
			note = "A teammate can revive you by holding E on your body"
		death_spec.text = note
		death_box.reset_size()
	for el in [vitals, weapon_box, abil_row]:
		el.modulate.a = 1.0 if alive else 0.0
	if board_visible and clock - last_board > 0.25:
		last_board = clock
		for c in board_body.get_children():
			c.queue_free()
		board_body.add_child(UI.label(m.mode.name, UI.DISPLAY, 28, UI.SUN))
		board_body.add_child(build_board(actors, m, a))
		board.reset_size()
	_update_obj_status(now, a, m)
	zone_label.text = zone_name
	# snapshot for the overlay (screen-space drawing)
	o = {"p": p, "a": a, "ws": ws, "m": m, "cam": cam, "now": now, "actors": actors}
	overlay.queue_redraw()


func _slot_key(i: int, cur: int) -> String:
	if GInput.using_pad:
		var sw := GInput.action_name("swap", true)
		return "" if i == cur or sw == "unbound" else sw
	var k := GInput.action_name("weapon2" if i else "weapon1", true)
	return "" if k == "unbound" else k


func _fill_mini(goal: String, rows: Array) -> void:
	for c in mini_box.get_children():
		c.queue_free()
	var g := UI.label(goal, UI.BODY, 13, Color(UI.PAPER, 0.7), true)
	mini_box.add_child(g)
	for r in rows:
		var rp := UI.panel(UI.sb(Color(1, 210 / 255.0, 63 / 255.0, 0.22), 8, 0, Color.TRANSPARENT, Vector4(4, 2, 4, 2)) if r[3] else UI.sb(Color(0, 0, 0, 0), 8, 0, Color.TRANSPARENT, Vector4(4, 2, 4, 2)))
		var h := UI.hbox(6)
		var b := UI.label(r[0], UI.DISPLAY, 15, Color(UI.PAPER, 0.8), true)
		b.custom_minimum_size.x = 22
		var n := UI.label(r[1], UI.BODY, 15, U.col(r[4]), true)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.clip_text = true
		var s := UI.label(str(r[2]), UI.DISPLAY, 18, UI.PAPER, true)
		h.add_child(b)
		h.add_child(n)
		h.add_child(s)
		rp.add_child(h)
		if r[5]:
			rp.modulate.a = 0.5
		mini_box.add_child(rp)
	mini.reset_size()


func _update_obj_status(_now: float, a: Actor, m: Match) -> void:
	if not obj_status.visible:
		return
	var tc := "#ffffff"
	var key := ""
	var build := Callable()
	if m.sectors.size():
		var here := m.sector_of(a)
		var state: String
		if here >= 0:
			var s: Dictionary = m.sectors[here]
			var nm: String = s.def.name.trim_prefix("the ")
			if s.contested:
				state = "%s: contested, kill the enemies inside" % nm
			elif s.owner == a.team:
				state = ("%s: restoring %d%%" % [nm, roundi(s.progress * 100)]) if s.progress < 1 else "%s: yours, hold it" % nm
			elif s.owner >= 0:
				state = "%s: draining Team %s's hold %d%%" % [nm, Modes.TEAMS[s.owner].name, roundi((1 - s.progress) * 100)]
			else:
				state = "%s: capturing %d%%" % [nm, roundi((s.progress if s.progressTeam == a.team else 0.0) * 100)]
		else:
			state = "Your team holds %d of 6. Control 4 to win." % m.sectors_owned(a.team)
		tc = Modes.TEAMS[maxi(0, a.team)].color
		var strip := []
		key = state
		for i in m.sectors.size():
			var s: Dictionary = m.sectors[i]
			var owner_c: String = Modes.TEAMS[s.owner].color if s.owner >= 0 else "#fff6d8"
			var pc: String = "" if (s.owner >= 0 and s.progress >= 1) else (Modes.TEAMS[s.active].color if s.active >= 0 else (Modes.TEAMS[s.progressTeam].color if s.progressTeam >= 0 else "#ffffff"))
			strip.append([s.def.letter, s.def.short, owner_c, pc, s.progress, s.contested, i == here, s.owner == a.team])
			key += "|%s%s%d%s%s" % [owner_c, pc, roundi(s.progress * 50), s.contested, i == here]
		build = func():
			var row := UI.hbox(6)
			for sd in strip:
				var sec := SectorChip.new()
				sec.d = sd
				sec.custom_minimum_size = Vector2(52, 44)
				row.add_child(sec)
			obj_box.add_child(row)
			var l := UI.label(state, UI.BODY, 14, UI.PAPER, true)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			obj_box.add_child(l)
	elif m.hill != null and m.mode.id == "takeover":
		var h = m.hill
		var inside := m.in_hill(a)
		var state: String = "Contested" if h.contested else ("Empty" if h.owner < 0 else ("Your team is winding up" if h.owner == a.team else "Enemy team is winding up"))
		tc = "#ff4d8d" if h.contested else (Modes.TEAMS[h.owner].color if h.owner >= 0 else "#fff6d8")
		var l1: String = "Toy box: " + h.site.name
		var l2 := state + (" (you are in it)" if inside else "")
		var l3 := "Moves in %d s" % ceili(h.timeLeft)
		key = l1 + l2 + l3 + tc
		build = func():
			var a1 := UI.label(l1, UI.DISPLAY, 18, U.col(tc), true)
			var a2 := UI.label(l2, UI.BODY, 14, UI.PAPER, true)
			var a3 := UI.label(l3, UI.BODY, 13, Color(UI.PAPER, 0.75), true)
			for l in [a1, a2, a3]:
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				obj_box.add_child(l)
	if key == last_obj or not build.is_valid():
		return
	last_obj = key
	for c in obj_box.get_children():
		obj_box.remove_child(c)
		c.queue_free()
	var st := _dark(0.72, 14, Vector4(16, 6, 16, 5))
	st.border_width_bottom = 4
	st.border_color = U.col(tc)
	obj_status.add_theme_stylebox_override("panel", st)
	build.call()
	obj_status.reset_size()


# ======================================================================== widgets
## Health / shield / energy bar (styles.css .bar).
class Bar extends Control:
	var frac := 1.0
	var ghost := 1.0
	var text := ""
	var text_size := 16
	var bg := Color(26 / 255.0, 16 / 255.0, 48 / 255.0, 0.75)
	var border := 3
	var radius := 12
	var fill_a := Color("#22c55e")
	var fill_b := Color("#86efac")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		var rad := minf(radius, size.y / 2)
		draw_style_box(UI.sb(bg, int(rad), border, Color(1, 1, 1, 0.22)), r)
		var inner := r.grow(-border)
		if ghost > frac + 0.001:
			draw_style_box(UI.sb(Color(1, 1, 1, 0.55), int(maxf(0, rad - border))), Rect2(inner.position, Vector2(inner.size.x * clampf(ghost, 0, 1), inner.size.y)))
		var fw := inner.size.x * clampf(frac, 0, 1)
		if fw > 1:
			# horizontal gradient fill
			var steps := 12
			var fr := Rect2(inner.position, Vector2(fw, inner.size.y))
			var sbx := UI.sb(fill_a, int(maxf(0, rad - border)))
			draw_style_box(sbx, fr)
			for i in steps:
				var x0 := fr.position.x + fw * i / steps
				var c := fill_a.lerp(fill_b, (i + 0.5) / steps)
				draw_rect(Rect2(x0, fr.position.y + 2, fw / steps + 0.5, fr.size.y - 4), c)
			draw_rect(Rect2(fr.position.x + rad * 0.5, fr.position.y, maxf(0, fw - rad), 2), Color(1, 1, 1, 0.35))
		if text != "":
			var f: Font = UI.DISPLAY
			var ts := f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size)
			draw_string(f, Vector2(size.x - 8 - ts.x, size.y / 2 + ts.y * 0.32), text, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, UI.PAPER)


## Ability icon with cooldown ring (styles.css .abil).
class AbilIcon extends Control:
	var key := ""
	var cd := ""
	var frac := 0.0
	var is_ready := true
	var active := false
	var denied := false

	func _draw() -> void:
		var c := size / 2
		var r := 25.0
		var border := UI.SUN if is_ready else (Color("#7fd4ff") if active else (Color("#ff4d6d") if denied else Color(1, 1, 1, 0.22)))
		if is_ready:
			draw_circle(c, r + 6, Color(1, 210 / 255.0, 63 / 255.0, 0.12))
		if active:
			draw_circle(c, r + 6, Color(127 / 255.0, 212 / 255.0, 1, 0.15))
		draw_circle(c, r, Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.78))
		draw_arc(c, r - 1.5, 0, TAU, 40, border, 3, true)
		if not is_ready and frac > 0:
			var col := Color("#7fd4ff") if active else Color(1, 1, 1, 0.55)
			draw_arc(c, 28, -PI / 2, -PI / 2 + TAU * frac, 40, col, 4, true)
		var f: Font = UI.DISPLAY
		var fs := 13 if key.length() > 2 else 21
		var ts := f.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		draw_string(f, c + Vector2(-ts.x / 2, ts.y * 0.32), key, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UI.PAPER, 1.0 if is_ready or active else 0.55))
		if cd != "":
			var bf: Font = UI.BOLD
			var cs := bf.get_string_size(cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 12)
			var br := Rect2(Vector2(size.x + 6 - cs.x - 10, size.y - 16), Vector2(cs.x + 10, 16))
			draw_style_box(UI.sb(Color(0, 0, 0, 0.6), 8), br)
			draw_string(bf, br.position + Vector2(5, 12), cd, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, UI.PAPER)


## Power-up timer chip (styles.css .buff).
class BuffIcon extends Control:
	var kind := "turbo"
	var left := 1.0

	func _draw() -> void:
		var col := U.col(Pickups.INFO[kind].color)
		draw_style_box(UI.sb(Color(43 / 255.0, 27 / 255.0, 77 / 255.0, 0.75), 12, 2, col), Rect2(Vector2.ZERO, size))
		draw_arc(size / 2, 21, -PI / 2, -PI / 2 + TAU * left, 32, col, 3, true)
		var glyph := {"turbo": "T", "infinite": "∞", "power": "★"}[kind] as String
		var f: Font = UI.DISPLAY
		var ts := f.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(f, size / 2 + Vector2(-ts.x / 2, ts.y * 0.32), glyph, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)


## One sector in the Conquest strip (styles.css .obj-status .sec).
class SectorChip extends Control:
	var d: Array = []

	func _draw() -> void:
		if d.is_empty():
			return
		var oc := U.col(d[2])
		var border := oc
		if d[5]:
			border = Color("#ff4d8d") if fmod(Time.get_ticks_msec() / 500.0, 2.0) < 1 else Color.WHITE
			queue_redraw()
		var r := Rect2(Vector2.ZERO, size)
		draw_style_box(UI.sb(Color(1, 1, 1, 0.12) if d[7] else Color(0, 0, 0, 0.28), 10, 3, border), r)
		if d[6]:
			draw_style_box(UI.sb(Color(0, 0, 0, 0), 12, 2, Color.WHITE), r.grow(2))
		if d[3] != "":
			draw_rect(Rect2(3, size.y - 7, (size.x - 6) * d[4], 4), U.col(d[3]))
		var f: Font = UI.DISPLAY
		var ts := f.get_string_size(d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(f, Vector2((size.x - ts.x) / 2, 20), d[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, oc)
		var bf: Font = UI.BODY
		var ss := bf.get_string_size(d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10)
		draw_string(bf, Vector2((size.x - ss.x) / 2, 33), d[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(UI.PAPER, 0.8))


## Everything drawn in screen space at real pixel sizes: crosshair, scope, reticles, rings, hit markers,
## damage numbers, damage direction, ally tags and objective markers.
class Overlay extends Control:
	var hud

	func _draw() -> void:
		var o: Dictionary = hud.o
		if o.is_empty():
			return
		var k := UI.px(self)  # base units per real screen pixel
		var c := size / 2
		var a: Actor = o.a
		var ws: WeaponState = o.ws
		var p: Player = o.p
		var cam: Camera3D = o.cam
		var now: float = o.now
		var alive := a.alive
		var scoped := ws != null and ws.overlay() and a.ads > 0.9
		var lit: bool = ws != null and ws.scope.style == "reticle" and a.ads > 0.75 and alive
		# scope picture
		if scoped and alive:
			_draw_scope(c, ws, now, p.scope_kick)
		# lit reticle (small on-gun optics)
		if lit:
			var col := U.col(ws.cfg.colors.glow)
			col.a = clampf((a.ads - 0.75) * 6, 0, 1)
			var box := (150.0 if ws.scope.id == "ring" else 120.0) * k
			_mark(c, box / 120.0, Cfg.RETICLES[ws.id], col, true)
		# crosshair
		if alive and not scoped and not lit:
			var gap := clampf(tan(deg_to_rad(p.spread_deg)) / tan(deg_to_rad(cam.fov) / 2) * (size.y / 2) / k, 3, 120)
			var s: float = Settings.get_v("crosshairSize") * k
			var xc := U.col(Settings.get_v("crosshairColor"))
			var arm_a := 0.35 if a.ads > 0.6 else 1.0
			var line := func(r: Rect2, alpha: float) -> void:
				var rr := Rect2(c + r.position * s, r.size * s)
				draw_rect(rr.grow(1 * k), Color(0, 0, 0, 0.55 * alpha))
				draw_rect(rr, Color(xc, alpha))
			if ws and int(ws.cfg.get("pellets", 1)) > 1:
				# shotguns: the classic round reticle, four curved arcs on the spread circle
				var rad := (gap + 5) * s
				for q in 4:
					var mid := -PI / 2 + q * PI / 2
					var half := deg_to_rad(28)
					draw_arc(c, rad, mid - half, mid + half, 16, Color(0, 0, 0, 0.55 * arm_a), 3 * s + 2 * k, true)
					draw_arc(c, rad, mid - half, mid + half, 16, Color(xc, arm_a), 3 * s, true)
			else:
				line.call(Rect2(-1.5, -9 - gap, 3, 9), arm_a)
				line.call(Rect2(-1.5, gap, 3, 9), arm_a)
				line.call(Rect2(-9 - gap, -1.5, 9, 3), arm_a)
				line.call(Rect2(gap, -1.5, 9, 3), arm_a)
			if Settings.get_v("crosshairDot"):
				draw_circle(c, 2.5 * s, Color(0, 0, 0, 0.55))
				draw_circle(c, 2 * s, xc)
		# reload ring + text
		if ws and ws.reloading and alive:
			draw_arc(c, 22 * k, 0, TAU, 48, Color(0, 0, 0, 0.35), 4 * k, true)
			draw_arc(c, 22 * k, -PI / 2, -PI / 2 + TAU * ws.reload_progress(), 48, UI.SUN, 4 * k, true)
			_text("Reloading", c + Vector2(0, 46 * k + 18 * k), 18 * k, UI.SUN, true)
		# bow draw ring
		if alive and ws and ws.drawing():
			var ch := ws.charge_at(now)
			var full := ch >= 0.999
			draw_arc(c, 34 * k, 0, TAU, 48, Color(0, 0, 0, 0.3), 4 * k, true)
			draw_arc(c, 34 * k, -PI / 2, -PI / 2 + TAU * ch, 48, UI.SUN if full else Color("#ff8fab"), 4 * k, true)
			var dmg: float = ws.cfg.damage * pow(ch, ws.cfg.charge.curve)
			_text("%d / %d" % [roundi(dmg), roundi(dmg * ws.cfg.headMult)], c + Vector2(0, 40 * k + 16 * k), 12 * k, UI.PAPER, false, UI.BOLD)
		# hit marker
		if hud.hit_t > 0:
			var t: float = 1 - hud.hit_t / 0.22
			var sc := (1.3 - 0.3 * t) * k
			var alpha := 1 - t
			var hc := Color.WHITE
			var hlen := 11.0
			var hw := 3.0
			match hud.hit_kind:
				"head":
					hc = UI.SUN
					hlen = 14
				"shield":
					hc = UI.SHIELD
				"kill":
					hc = UI.PINK
					hlen = 16
					hw = 4
			for i in 4:
				var ang := PI / 4 + i * PI / 2
				var dir := Vector2(sin(ang), -cos(ang))
				var p0 := c + dir * 16 * sc
				var p1 := c + dir * (16 + hlen) * sc
				draw_line(p0, p1, Color(0, 0, 0, 0.6 * alpha), (hw + 2) * sc)
				draw_line(p0, p1, Color(hc, alpha), hw * sc)
		# damage direction indicators
		for d in hud.dirs:
			if d.life <= 0:
				continue
			var al := clampf(d.life, 0, 1)
			var rot: float = -d.ang
			var pts := PackedVector2Array()
			var cols := PackedColorArray()
			pts.append(c + Vector2(0, -144).rotated(rot) * k)
			cols.append(Color(1, 70 / 255.0, 90 / 255.0, 0.9 * al))
			for j in 13:
				var aa := PI + PI * j / 12.0
				var lp := Vector2(cos(aa) * 36, -144 + sin(aa) * 26)
				pts.append(c + lp.rotated(rot) * k)
				cols.append(Color(1, 70 / 255.0, 90 / 255.0, 0))
			draw_polygon(pts, cols)
		# damage numbers
		for n in hud.nums:
			if n.life <= 0:
				continue
			var wp: Vector3 = n.pos + Vector3(0, (0.9 - n.life) * 0.8, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp) + Vector2(n.drift * (0.9 - n.life) * k, 0)
			var s := 1 + maxf(0, n.life - 0.7) * 2.5
			var col := UI.SUN if n.kind == "head" else (UI.SHIELD if n.kind == "shield" else Color.WHITE)
			col.a = minf(1, n.life / 0.3)
			_text(n.text, sp, (27 if n.kind == "head" else 22) * s * k, col, true, UI.DISPLAY, true)
		var m: Match = o.m
		# floating name tags over teammates
		if m.teams():
			for t in o.actors:
				var down: bool = t.is_downed(now)
				if t == a or t.team != a.team or (not t.alive and not down):
					continue
				var wp: Vector3 = t.pos + Vector3(0, 2.9 if down else 2.25, 0)
				if cam.is_position_behind(wp):
					continue
				var sp := cam.unproject_position(wp)
				if sp.x < -0.05 * size.x or sp.x > 1.05 * size.x or sp.y < -0.05 * size.y or sp.y > 1.05 * size.y:
					continue
				var dist: float = t.pos.distance_to(a.pos)
				var tc := U.col(Modes.TEAMS[t.team].color)
				var al := 1.0 if down else clampf(1.2 - dist / 60, 0.45, 1)
				if down:
					var pulse := 1 + 0.18 * absf(sin(now * PI * 2))
					draw_circle(sp - Vector2(0, 8 * k), 8 * pulse * k, tc)
					draw_circle(sp - Vector2(0, 8 * k), 6 * pulse * k, Color.WHITE)
					var txt: String = ("%s  reviving %d%%" % [t.name, roundi(t.revive_t / Cfg.COMBAT.reviveTime * 100)]) if t.revive_t > 0 else "✚ %s  %ds" % [t.name, ceili(t.respawn_at - now)]
					var f: Font = UI.BOLD
					var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, int(15 * k))
					draw_style_box(UI.sb(Color(0, 0, 0, 0.45), 9), Rect2(sp + Vector2(-ts.x / 2 - 8 * k, -40 * k), Vector2(ts.x + 16 * k, 22 * k)))
					_text(txt, sp + Vector2(0, -24 * k), 15 * k, Color.WHITE, true, UI.BOLD)
				else:
					var dd := 7.0 * k
					var dpts := PackedVector2Array([sp + Vector2(0, -dd * 2), sp + Vector2(dd, -dd), sp + Vector2(0, 0), sp + Vector2(-dd, -dd)])
					draw_colored_polygon(dpts, Color(tc, al))
					draw_polyline(dpts + PackedVector2Array([dpts[0]]), Color(1, 1, 1, al), 2 * k, true)
					if dist < 30:
						_text(t.name, sp + Vector2(0, -dd * 2 - 4 * k), 13 * k, Color(1, 1, 1, al), true, UI.BOLD)
		# toy box objective marker, pinned to the screen edge when off-screen
		var h = m.hill
		if h != null and alive and not m.in_hill(a):
			var wp: Vector3 = h.pos + Vector3(0, h.site.height * 0.5, 0)
			var behind := cam.is_position_behind(wp)
			var sp := cam.unproject_position(wp)
			var ndc := Vector2(sp.x / size.x * 2 - 1, -(sp.y / size.y * 2 - 1))
			if behind:
				ndc = -ndc
			if behind or absf(ndc.x) > 0.92 or absf(ndc.y) > 0.86:
				var kk := maxf(maxf(absf(ndc.x) / 0.92, absf(ndc.y) / 0.86), 1e-3)
				ndc /= kk
				if behind and absf(ndc.y) < 0.86 and absf(ndc.x) < 0.92:
					ndc.y = -0.86
			var pos := Vector2((ndc.x * 0.5 + 0.5) * size.x, (-ndc.y * 0.5 + 0.5) * size.y)
			var col := U.col("#ff4d8d" if h.contested else (Modes.TEAMS[h.owner].color if h.owner >= 0 else "#fff6d8"))
			draw_set_transform(pos, -0.105, Vector2.ONE)
			var bs := 40.0 * k
			draw_circle(Vector2.ZERO, bs * 0.75, Color(col, 0.25))
			draw_style_box(UI.sb(col, int(12 * k), int(3 * k), Color.WHITE), Rect2(Vector2(-bs / 2, -bs / 2), Vector2(bs, bs)))
			_gear(Vector2.ZERO, 10 * k, UI.INK)
			draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
			_text("%d m" % roundi(a.pos.distance_to(h.pos)), pos + Vector2(0, bs / 2 + 16 * k), 15 * k, Color.WHITE, true, UI.DISPLAY)
		# conquest sector markers
		if m.sectors.size() and alive:
			var here := m.sector_of(a)
			for i in m.sectors.size():
				var s: Dictionary = m.sectors[i]
				if i == here:
					continue
				var wp: Vector3 = s.pos + Vector3(0, s.def.height + 1.2, 0)
				if cam.is_position_behind(wp):
					continue
				var sp := cam.unproject_position(wp)
				if sp.x < -0.025 * size.x or sp.x > 1.025 * size.x or sp.y < -0.025 * size.y or sp.y > 1.025 * size.y:
					continue
				var col := U.col("#ff4d8d" if s.contested else (Modes.TEAMS[s.owner].color if s.owner >= 0 else "#fff6d8"))
				var busy: bool = s.active >= 0 or s.contested
				var r := 15.0 * k * (1 + (0.18 * absf(sin(now * PI / 0.6)) if busy else 0.0))
				if s.owner == a.team:
					draw_circle(sp, r + 3 * k, Color(1, 1, 1, 0.9))
				draw_circle(sp, r, col)
				draw_arc(sp, r - k, 0, TAU, 32, Color.WHITE, 2 * k, true)
				_text(s.def.letter, sp + Vector2(0, 7 * k), 18 * k, UI.INK, false, UI.DISPLAY)
				_text("%d m" % roundi(a.pos.distance_to(s.pos)), sp + Vector2(0, r + 14 * k), 12 * k, Color.WHITE, true, UI.DISPLAY)

	func _text(s: String, at: Vector2, size_px: float, col: Color, shadow := false, font: Font = null, outline := false) -> void:
		var f: Font = font if font else UI.DISPLAY
		var fs := maxi(1, roundi(size_px))
		var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		var pos := at - Vector2(ts.x / 2, 0)
		if shadow:
			draw_string(f, pos + Vector2(0, 2), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.45 * col.a))
		if outline:
			draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, maxi(1, fs / 12), Color(0, 0, 0, 0.6 * col.a))
		draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

	func _gear(c: Vector2, r: float, col: Color) -> void:
		for i in 8:
			var ang := i * TAU / 8
			draw_line(c + Vector2(cos(ang), sin(ang)) * r * 0.6, c + Vector2(cos(ang), sin(ang)) * r * 1.15, col, r * 0.45)
		draw_circle(c, r * 0.75, col)
		draw_circle(c, r * 0.32, Color(1, 1, 1, 0.9))

	## A weapon's own reticle mark. `u` = screen units per mark unit.
	func _mark(c: Vector2, u: float, shape: String, col: Color, glow := false) -> void:
		var w := 2.2 * u
		var L := func(pts: Array) -> void:
			var pa := PackedVector2Array()
			for q in pts:
				pa.append(c + q * u)
			if glow:
				draw_polyline(pa, Color(col, col.a * 0.35), w * 3, true)
			draw_polyline(pa, col, w, true)
		var C := func(ctr: Vector2, r: float, filled: bool) -> void:
			if filled:
				if glow:
					draw_circle(c + ctr * u, r * u * 2, Color(col, col.a * 0.25))
				draw_circle(c + ctr * u, r * u, col)
			else:
				if glow:
					draw_arc(c + ctr * u, r * u, 0, TAU, 40, Color(col, col.a * 0.35), w * 3, true)
				draw_arc(c + ctr * u, r * u, 0, TAU, 40, col, w, true)
		match shape:
			"dot":
				C.call(Vector2.ZERO, 3.2, true)
			"chevron":
				L.call([Vector2(-9, 9), Vector2(0, 0), Vector2(9, 9)])
				C.call(Vector2.ZERO, 1.4, true)
			"brick":
				L.call([Vector2(-9, -6), Vector2(9, -6), Vector2(9, 6), Vector2(-9, 6), Vector2(-9, -6)])
				C.call(Vector2.ZERO, 1.6, true)
				L.call([Vector2(-5, -6), Vector2(-5, -9)])
				L.call([Vector2(5, -6), Vector2(5, -9)])
			"bubbles":
				for j in 12:
					var a0 := j * TAU / 12
					draw_arc(c, 15 * u, a0, a0 + TAU / 12 * 0.4, 6, col, w, true)
				C.call(Vector2(-6, 4), 3, false)
				C.call(Vector2(6, 2), 4, false)
				C.call(Vector2(0, -7), 2.4, false)
			"cross":
				C.call(Vector2.ZERO, 2, true)
				L.call([Vector2(-16, 0), Vector2(-7, 0)])
				L.call([Vector2(7, 0), Vector2(16, 0)])
				L.call([Vector2(0, -16), Vector2(0, -7)])
				L.call([Vector2(0, 7), Vector2(0, 16)])
			"circleDot":
				C.call(Vector2.ZERO, 10, false)
				C.call(Vector2.ZERO, 1.8, true)
			"crayon":
				L.call([Vector2(0, 0), Vector2(-5, 10), Vector2(5, 10), Vector2(0, 0)])
				L.call([Vector2(-14, 22), Vector2(14, 22)])
				L.call([Vector2(-9, 36), Vector2(9, 36)])
				L.call([Vector2(-5, 50), Vector2(5, 50)])
			"star":
				L.call([Vector2(0, -11), Vector2(3, -3), Vector2(11, -3), Vector2(5, 2), Vector2(7, 10), Vector2(0, 5), Vector2(-7, 10), Vector2(-5, 2), Vector2(-11, -3), Vector2(-3, -3), Vector2(0, -11)])
				C.call(Vector2.ZERO, 1.3, true)
			"jack":
				C.call(Vector2.ZERO, 13, false)
				C.call(Vector2(-4.5, -3), 1.4, true)
				C.call(Vector2(4.5, -3), 1.4, true)
				var smile := []
				for j in 9:
					var t := j / 8.0
					smile.append(Vector2(-6 + 12 * t, 4 + 6 * 4 * t * (1 - t) * 0.5 * 2))
				L.call(smile)
				C.call(Vector2(0, 1), 1.2, true)
			"boom":
				C.call(Vector2.ZERO, 9, false)
				L.call([Vector2(0, -17), Vector2(0, -11)])
				L.call([Vector2(0, 11), Vector2(0, 17)])
				L.call([Vector2(-17, 0), Vector2(-11, 0)])
				L.call([Vector2(11, 0), Vector2(17, 0)])
				C.call(Vector2.ZERO, 1.6, true)
			"kernels":
				C.call(Vector2(0, -7), 2.2, true)
				C.call(Vector2(-6.5, 5), 2.2, true)
				C.call(Vector2(6.5, 5), 2.2, true)
				C.call(Vector2.ZERO, 1, true)

	func _draw_scope(c: Vector2, ws: WeaponState, now: float, kick: float) -> void:
		var off := Vector2(sin(now * 40) * kick * 6, kick * 26) * UI.px(self)
		var cc := c + off
		var lens := size.y * 0.39
		var dark := Color("#0b1020")
		# everything outside the lens is black
		var big := maxf(size.x, size.y) * 2
		for half in [0, 1]:
			var pts := PackedVector2Array()
			var sgn := -1.0 if half == 0 else 1.0
			pts.append(cc + Vector2(-big, 0))
			pts.append(cc + Vector2(-big, sgn * big))
			pts.append(cc + Vector2(big, sgn * big))
			pts.append(cc + Vector2(big, 0))
			for j in 49:
				var ang := (j / 48.0) * PI
				pts.append(cc + Vector2(cos(ang) * lens, sgn * sin(ang) * lens))
			draw_colored_polygon(pts, dark)
		# inner shadow toward the edge of the lens
		for j in 8:
			draw_arc(cc, lens - j * lens * 0.02, 0, TAU, 96, Color(0, 0, 0, 0.12), lens * 0.02 + 1, true)
		# rim in the weapon's colors
		var col: Dictionary = Cfg.WEAPONS[ws.id].colors
		draw_arc(cc, size.y * 0.4 + 5, 0, TAU, 96, U.col(col.main), 10 * UI.px(self) + 2, true)
		draw_arc(cc, size.y * 0.4 + 12 * UI.px(self), 0, TAU, 96, U.col(col.accent), 4 * UI.px(self), true)
		# fine cross with range ticks + the weapon's mark (svg box -100..100 = lens diameter)
		var u := lens / 100.0
		var lc := Color("#0b1020")
		var seg := func(a: Vector2, b: Vector2, wdt: float) -> void: draw_line(cc + a * u, cc + b * u, lc, maxf(1, wdt * u), true)
		seg.call(Vector2(-100, 0), Vector2(-20, 0), 0.7)
		seg.call(Vector2(20, 0), Vector2(100, 0), 0.7)
		seg.call(Vector2(0, -100), Vector2(0, -20), 0.7)
		seg.call(Vector2(0, 20), Vector2(0, 100), 0.7)
		seg.call(Vector2(-100, 0), Vector2(-62, 0), 2.4)
		seg.call(Vector2(62, 0), Vector2(100, 0), 2.4)
		seg.call(Vector2(0, 62), Vector2(0, 100), 2.4)
		var zoom := ws.zoom()
		var n := 8 if zoom >= 6 else (5 if zoom >= 3.5 else 3)
		for i in range(1, n + 1):
			var dd := 18 + i * (70.0 / n) * 0.9
			var l := 2.5 if i % 2 else 4.0
			seg.call(Vector2(dd, -l), Vector2(dd, l), 0.7)
			seg.call(Vector2(-dd, -l), Vector2(-dd, l), 0.7)
			seg.call(Vector2(-l, dd), Vector2(l, dd), 0.7)
		var mark: String = "#ff4d6d" if ws.id == "thunderspring" else col.accent
		_mark(cc, u, Cfg.RETICLES[ws.id], U.col(mark))

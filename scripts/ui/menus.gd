class_name Menus
extends Control
## Every menu screen (port of src/ui/Menus.ts): login / create account, main menu, play (map + mode +
## difficulty), loadout and unlocks with a 3D blaster preview, settings, rebindable controls, credits, pause,
## results, and online play (host / join / lobby). Layouts use the original's CSS pixel sizes and the same
## screen zoom rule.
## cb: {start(difficulty, mode), resume(), quit(), play_again(), settings_changed(key), load_map(map_id, mode),
##      host_room(mode, bots), join_room(code), leave_online(), lobby_set({mode|bots}), lobby_map(id), lobby_start(),
##      back_to_lobby(), online_role() -> "host"|"guest"|"", lobby_info() -> {}, lobby_loading() -> int}

const ABILITY_INFO := {
	"dash": {"short": "Dash", "desc": "Burst forward a few meters. 5 s cooldown."},
	"grapple": {"short": "Hook", "desc": "Pull yourself to a spot up to 48 m away, up and over ledges. 7 s cooldown."},
	"cloak": {"short": "Cloak", "desc": "Invisible beyond 2.5 m for up to 15 s. Press again to drop it. Firing drops it."},
	"shield": {"short": "Shield", "desc": "Wall that stops 260 enemy damage for 7 s. 15 s cooldown."},
}
const MODE_TAGS := {"ffa": "15 toys, everyone for themselves", "tdm": "4 vs 4", "takeover": "4 vs 4, moving objective", "conquest": "3 vs 3 vs 3, six sectors"}

## set before reloading the scene for a map change: land back on the Play screen with this mode
static var resume_mode := ""

var cb: Dictionary
var audio
var input: GInput
var current := ""
var back := "main"
var difficulty := "normal"
var selected_weapon := "plasti9"
## names for the gadgets (the gadget update adds them to the game)
const GADGET_NAMES := {"glitchJug": "Glitch Jug", "stairs": "Pop-up Stairs", "fragGrenade": "Frag Grenade", "pyroGrenade": "Pyro Grenade",
	"turret": "Turret", "healthInfuser": "Health Infuser", "breachDrill": "Breach Drill", "explosiveMine": "Explosive Mine", "pyroMine": "Pyro Mine"}
var mode := "ffa"
var map_id := "bedroom"
var abil_slot := 0
var root := Control.new()
var preview: Dictionary = {}
var _resume_hint: Control = null
var training_mode := false  # set by the game when a Training Range session starts


func _init(callbacks: Dictionary, aud, inp: GInput) -> void:
	name = "Menus"
	cb = callbacks
	audio = aud
	input = inp
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	difficulty = Settings.get_v("difficulty")
	map_id = Maps.selected().id
	UI.hover_sound = func(): audio.ui_hover()
	UI.click_sound = func():
		audio.init()
		if audio.music:
			audio.music.start()
		audio.ui_click()


func _process(_dt: float) -> void:
	var win := UI.win_size()
	var z := clampf(minf(win.y / 900.0, win.x / 1500.0), 0.7, 1.35) * UI.px(self)
	root.scale = Vector2(z, z)
	root.size = size / z
	if preview.has("model") and is_instance_valid(preview.model):
		var t := Time.get_ticks_msec()
		(preview.model as Node3D).rotation = Vector3(sin(t * 0.0008) * 0.12, PI / 2 + sin(t * 0.0006) * 0.7, 0)


func _clear() -> void:
	preview = {}
	for c in root.get_children():
		root.remove_child(c)
		c.queue_free()


## A centered dimmed screen with one card of the given CSS width. Returns the card's content VBox.
func _screen(width := 980.0, dim := true) -> VBoxContainer:
	_clear()
	if dim:
		root.add_child(UI.dim_backdrop())
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	var parts := UI.scroll_panel(width)
	var c: PanelContainer = parts[0]
	var sc: ScrollContainer = parts[1]
	center.add_child(c)
	sc.custom_minimum_size.y = 0
	var v: VBoxContainer = parts[2]
	# cap the height at 92% of the screen, scroll beyond that
	v.resized.connect(func():
		var maxh := root.size.y * 0.92 - 56
		sc.custom_minimum_size.y = minf(v.size.y, maxh))
	return v


func _actions(btns: Array) -> HBoxContainer:
	var h := UI.hbox(8)
	for b in btns:
		h.add_child(b)
	return h


func hide_menus() -> void:
	_clear()
	current = ""


## After a map change, start the match that was asked for (otherwise open the main menu).
func open_after_load() -> void:
	if resume_mode != "":
		# "Start match" on another map: the scene was rebuilt for it, so go straight into the match
		mode = resume_mode
		resume_mode = ""
		cb.start.call(difficulty, mode)
		return
	if Accounts.needs_choice():
		login("register")
		return
	main()


# ------------------------------------------------------------------ accounts
func login(tab := "login", back_to := "") -> void:
	current = "login"
	var reg := tab == "register"
	var v := _screen(520)
	v.add_child(UI.title("Create an account" if reg else "Log in"))
	v.add_child(UI.para("Your account keeps your coins, unlocked blasters, stats, loadout and controls."))
	var tabs := UI.hbox(10)
	tabs.add_child(UI.choice("Log in", "", not reg, func(): login("login", back_to)))
	tabs.add_child(UI.choice("Create account", "", reg, func(): login("register", back_to)))
	v.add_child(tabs)
	var field := func(lbl: String, e: LineEdit) -> Control:
		var f := UI.vbox(4)
		f.add_child(UI.label(lbl.to_upper(), UI.BODY, 13, Color(UI.PAPER, 0.8)))
		f.add_child(e)
		return f
	var user := UI.line_edit("2 to 14 letters or numbers")
	var pw := UI.line_edit("at least %d characters" % Accounts.MIN_PASSWORD, true, 64)
	var pw2 := UI.line_edit("", true, 64)
	v.add_child(field.call("Name", user))
	v.add_child(field.call("Password", pw))
	if reg:
		v.add_child(field.call("Password again", pw2))
	var err := UI.label("", UI.BOLD, 16, Color("#ff8fa3"))
	err.custom_minimum_size.y = 22
	v.add_child(err)
	var submit := func():
		var msg := ""
		if reg:
			if pw.text != pw2.text:
				msg = "The two passwords don't match."
			else:
				msg = Accounts.register(user.text, pw.text)
		else:
			msg = Accounts.login(user.text, pw.text)
		if msg != "":
			err.text = msg
			return
		main()
	for e in [user, pw, pw2]:
		e.text_submitted.connect(func(_t): submit.call())
	var guest := func():
		if back_to != "":
			main()
			return
		Accounts.play_as_guest()
		main()
	v.add_child(_actions([UI.btn("Create account" if reg else "Log in", "primary", true, submit), UI.btn("Back" if back_to != "" else "Play as guest", "ghost", true, guest)]))
	var saved := Accounts.saved_names()
	if saved.size() and not reg:
		v.add_child(UI.label("Accounts on this computer", UI.BODY, 15, Color(UI.PAPER, 0.8)))
		var chips := HFlowContainer.new()
		chips.add_theme_constant_override("h_separation", 6)
		for n in saved:
			chips.add_child(UI.chip(n, false, func():
				user.text = n
				pw.grab_focus()))
		v.add_child(chips)
	v.add_child(UI.para("Accounts are saved on this computer (the password is stored as a salted hash, never as text). Use a password you don't use anywhere else. Playing as a guest saves progress too, just not under a name. Online accounts will come with multiplayer.", 14, 0.75))
	_focus_later(user)


# ------------------------------------------------------------------ main
func main() -> void:
	current = "main"
	_clear()
	var st: Dictionary = Settings.stats
	var acc := roundi(float(st.shotsHit) / float(st.shotsFired) * 100) if st.shotsFired else 0
	var acct := Accounts.current()
	# left column: logo + buttons
	var col := UI.vbox(0)
	col.custom_minimum_size.x = 440
	root.add_child(col)
	_pin(col, 0.06, 0.5, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BOTH)
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(440, 210)
	var l1 := UI.label("Toybox", UI.DISPLAY, 116, UI.SUN)
	l1.add_theme_color_override("font_outline_color", UI.INK)
	l1.add_theme_constant_override("outline_size", 6)
	l1.add_theme_color_override("font_shadow_color", UI.ORANGE)
	l1.add_theme_constant_override("shadow_offset_y", 6)
	var l2 := UI.label("Mayhem", UI.DISPLAY, 98, UI.TEAL)
	l2.add_theme_color_override("font_outline_color", UI.INK)
	l2.add_theme_constant_override("outline_size", 6)
	l2.add_theme_color_override("font_shadow_color", Color("#0f7a74"))
	l2.add_theme_constant_override("shadow_offset_y", 6)
	l1.position = Vector2(0, 0)
	l2.position = Vector2(34, 96)
	logo.add_child(l1)
	logo.add_child(l2)
	logo.rotation = deg_to_rad(-4)
	var burst := Burst.new()
	burst.text = "%d toy blasters, %d maps" % [Cfg.WEAPON_ORDER.size(), Maps.MAP_ORDER.size()]
	burst.position = Vector2(400, -30)
	burst.size = Vector2(118, 118)
	logo.add_child(burst)
	col.add_child(logo)
	var play_b := UI.btn("Play", "primary", false, play)
	var online_b := UI.btn("Multiplayer", "", false, func(): online_screen())
	var train_b := UI.btn("Training", "", false, func(): cb.start.call(difficulty, "training"))
	for b in [play_b, online_b, train_b, UI.btn("Loadout and unlocks", "", false, func(): collection("main")), UI.btn("Settings", "", false, func(): settings_screen("main")),
			UI.btn("Controls", "", false, func(): controls("main")), UI.btn("Credits", "", false, credits)]:
		b.custom_minimum_size.y = 58
		var wrap := MarginContainer.new()
		wrap.add_theme_constant_override("margin_top", 10)
		wrap.add_child(b)
		col.add_child(wrap)
	# account bar (top right)
	var ab := UI.card(Vector4(18, 10, 14, 10))
	var abh := UI.hbox(14)
	var who := UI.vbox(0)
	who.add_child(UI.label(("Playing as" if acct.guest else "Logged in as").to_upper(), UI.BODY, 12, Color(UI.PAPER, 0.7)))
	who.add_child(UI.label(acct.name, UI.DISPLAY, 22, UI.SUN))
	abh.add_child(who)
	abh.add_child(UI.rich(UI.coin_bb(Progress.coins), 20))
	abh.add_child(UI.btn("Log in" if acct.guest else "Switch account", "ghost", true, func(): login("login", "main")))
	if not acct.guest:
		abh.add_child(UI.btn("Log out", "ghost", true, func():
			Accounts.logout()
			main()))
	for c in abh.get_children():
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ab.add_child(abh)
	root.add_child(ab)
	_pin(ab, 0.96, 0.04, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_END)
	# career card (bottom right)
	var cc := UI.card(Vector4(18, 16, 18, 12))
	cc.custom_minimum_size.x = 250
	var cv := UI.vbox(6)
	cv.add_child(UI.label("Your toy record", UI.DISPLAY, 22, UI.SUN))
	var g := UI.grid(2, 10, 2)
	for row in [["Matches", st.matches], ["Wins", st.wins], ["Pops", st.kills], ["Times popped", st.deaths], ["Accuracy", "%d%%" % acc], ["Best streak", st.bestStreak], ["Blasters unlocked", "%d / %d" % [Progress.owned.size(), Cfg.WEAPON_ORDER.size()]]]:
		var dt := UI.label(row[0], UI.BODY, 15, Color(UI.PAPER, 0.75))
		dt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var dd := UI.label(str(row[1]), UI.BOLD, 15)
		dd.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(dt)
		g.add_child(dd)
	cv.add_child(g)
	cc.add_child(cv)
	root.add_child(cc)
	_pin(cc, 0.96, 0.96, Control.GROW_DIRECTION_BEGIN, Control.GROW_DIRECTION_BEGIN)
	var hint := UI.label("Plays with a mouse and keyboard or a controller (press any button on it to switch).", UI.BODY, 14, Color(UI.PAPER, 0.6), true)
	root.add_child(hint)
	_pin(hint, 0.06, 0.97, Control.GROW_DIRECTION_END, Control.GROW_DIRECTION_BEGIN)
	_focus_later(play_b)


## Pin a control at a fraction of the screen (like CSS left/top percentages); it keeps its own minimum size
## and grows away from that point. Works whatever size the screen is now or later.
static func _pin(c: Control, ax: float, ay: float, gh: Control.GrowDirection, gv: Control.GrowDirection) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = 0
	c.offset_right = 0
	c.offset_top = 0
	c.offset_bottom = 0
	c.grow_horizontal = gh
	c.grow_vertical = gv


## The pink starburst sticker on the logo.
class Burst extends Control:
	var text := ""
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var k := 0.5 - 0.5 * cos(t / 3.2 * TAU)
		var rot := deg_to_rad(14 - 6 * k)
		var s := 1 + 0.06 * k
		var c := size / 2
		draw_set_transform(c, rot, Vector2(s, s))
		var poly := [50, 0, 61, 15, 79, 8, 80, 27, 98, 30, 89, 47, 100, 61, 82, 69, 84, 88, 66, 85, 55, 100, 43, 87, 25, 95, 22, 77, 3, 72, 12, 55, 0, 40, 18, 32, 16, 13, 35, 15]
		var pts := PackedVector2Array()
		var sh := PackedVector2Array()
		for i in range(0, poly.size(), 2):
			var p := Vector2(poly[i] / 100.0 * size.x - c.x, poly[i + 1] / 100.0 * size.y - c.y)
			pts.append(p)
			sh.append(p + Vector2(0, 4))
		draw_colored_polygon(sh, Color("#a3264c"))
		draw_colored_polygon(pts, UI.PINK)
		var f: Font = UI.DISPLAY
		var words := text.split(" ")
		var lines := []
		var cur := ""
		for w in words:
			var test := (cur + " " + w).strip_edges()
			if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x > size.x - 28 and cur != "":
				lines.append(cur)
				cur = w
			else:
				cur = test
		lines.append(cur)
		var y0 := -lines.size() * 17 / 2.0 + 13
		for i in lines.size():
			var ts := f.get_string_size(lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
			draw_string(f, Vector2(-ts.x / 2, y0 + i * 17), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _loadout_bb() -> String:
	var c := Loadout.cls()
	var g := Loadout.gun()
	var ab := Loadout.abilities()
	return "[font_size=13][color=#fff8ecbf]Class[/color][/font_size] %s     [font_size=13][color=#fff8ecbf]Blaster[/color][/font_size] %s [font_size=13][color=#fff8ecbf]%s[/color][/font_size]     [font_size=13][color=#fff8ecbf]Abilities[/color][/font_size] %s" % [
		UI.d(Cfg.CLASSES[c].name, 17), UI.d(Cfg.WEAPONS[g].name, 17), Cfg.SCOPES[Loadout.scope(g)].name,
		UI.d(ABILITY_INFO[ab[0]].short + " + " + ABILITY_INFO[ab[1]].short, 17)]


func play() -> void:
	current = "play"
	var cur: String = Maps.selected().id
	var v := _screen()
	v.add_child(UI.title("Pick a map and a mode"))
	var maps := UI.grid(2, 10, 10)
	for id in Maps.MAP_ORDER:
		var md := Maps.get_map(id)
		maps.add_child(UI.choice(md.name, md.blurb, id == map_id, func():
			map_id = id
			play(), "", 21, 13))
	v.add_child(maps)
	var modes := UI.grid(4, 10, 10)
	for id in Modes.MODE_ORDER:
		var m: Dictionary = Modes.MODES[id]
		modes.add_child(UI.choice(m.short, m.blurb, id == mode, func():
			mode = id
			play(), MODE_TAGS[id]))
	v.add_child(modes)
	v.add_child(UI.label("Difficulty", UI.BODY, 15, Color(UI.PAPER, 0.8)))
	var seg := UI.hbox(10)
	for o in [["easy", "Easy", "Slow reactions, loose aim. Good for learning the room."], ["normal", "Normal", "Toys that fight back and use cover."], ["hard", "Hard", "Fast, accurate, and they go for heads."]]:
		seg.add_child(UI.choice(o[1], o[2], o[0] == difficulty, func():
			difficulty = o[0]
			Settings.set_v("difficulty", difficulty)
			play()))
	v.add_child(seg)
	var bar := UI.panel(UI.sb(Color(0, 0, 0, 0.2), 14, 0, Color.TRANSPARENT, Vector4(12, 8, 12, 8)))
	var bh := UI.hbox(10)
	var lb := UI.rich(_loadout_bb(), 15)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bh.add_child(lb)
	bh.add_child(UI.btn("Change loadout", "ghost", true, func(): collection("play")))
	bar.add_child(bh)
	v.add_child(bar)
	var go := UI.btn("Start match", "primary", true, func():
		if map_id == cur:
			cb.start.call(difficulty, mode)
			return
		# maps are built when the world loads: save the choice and rebuild, coming straight back here
		Settings.set_v("map", map_id)
		resume_mode = mode
		var lv := _screen(440)
		lv.add_child(UI.title("Loading " + Maps.get_map(map_id).name))
		lv.add_child(UI.para("The match starts as soon as the map is built."))
		cb.load_map.call(map_id, mode))
	v.add_child(_actions([go, UI.btn("Back", "ghost", true, main)]))
	go.set_meta("is_back", false)
	v.get_child(v.get_child_count() - 1).get_child(1).set_meta("is_back", true)
	_focus_later(go)


# ------------------------------------------------------------------ online
## Multiplayer: host a room, or join a friend's with its code.
func online_screen(msg := "") -> void:
	current = "online"
	back = "main"
	var v := _screen(760)
	v.add_child(UI.title("Multiplayer"))
	v.add_child(UI.para("Play with friends over the internet. One player hosts a room and runs the match (bots too); the others join with the room code. Up to %d players per room." % Net.MAX_HUMANS, 17))
	if msg == "" and Net.default_server() == "":
		msg = "Online play isn't set up yet: the game server hasn't been put online (see server/README.md). To test on this computer, run the relay and type its address in the Server box."
	if msg != "":
		var e := UI.label(msg, UI.BOLD, 17, Color("#ff8fa3"))
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(e)
	var nrow := UI.hbox(12)
	var nl := UI.label("Your name", UI.BODY, 17)
	nl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	nrow.add_child(nl)
	var name_e := UI.line_edit("what other players see", false, 14)
	var cur_name: String = Settings.get_v("playerName")
	name_e.text = cur_name if cur_name != "You" else ""
	name_e.custom_minimum_size.x = 320
	name_e.text_changed.connect(func(t: String):
		if t.strip_edges() != "":
			Settings.set_v("playerName", t.strip_edges()))
	nrow.add_child(name_e)
	v.add_child(nrow)
	# host
	var hc := UI.blister()
	var hv := UI.vbox(8)
	hv.add_child(UI.label("Host a game", UI.DISPLAY, 26, UI.SUN))
	hv.add_child(UI.para("Opens a room with a code to share. You pick the mode, the map and how many bots in the lobby, then start the match.", 15))
	var host_b := UI.btn("Host a room", "primary", true, func():
		connecting("Opening a room")
		cb.host_room.call(mode if Modes.MODE_ORDER.has(mode) else "ffa", 4))
	hv.add_child(_actions([host_b]))
	hc.add_child(hv)
	v.add_child(hc)
	# join
	var jc := UI.blister()
	var jv := UI.vbox(8)
	jv.add_child(UI.label("Join a friend", UI.DISPLAY, 26, UI.SUN))
	var jrow := UI.hbox(10)
	var code_e := UI.line_edit("room code", false, 8)
	code_e.text = str(Settings.get_v("lastRoom"))
	code_e.custom_minimum_size.x = 240
	var join := func():
		var c := Net.clean_code(code_e.text)
		if c == "":
			code_e.grab_focus()
			return
		connecting("Joining room " + c)
		cb.join_room.call(c)
	code_e.text_submitted.connect(func(_t): join.call())
	jrow.add_child(code_e)
	jrow.add_child(UI.btn("Join", "primary", true, join))
	jv.add_child(jrow)
	jc.add_child(jv)
	v.add_child(jc)
	# where the server is (empty = the online server)
	var srow := UI.hbox(12)
	var sl := UI.label("Server", UI.BODY, 15, Color(UI.PAPER, 0.75))
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	srow.add_child(sl)
	var srv := UI.line_edit("online server (leave empty)", false, 200)
	srv.text = str(Settings.get_v("serverUrl"))
	srv.custom_minimum_size.x = 460
	srv.add_theme_font_size_override("font_size", 15)
	srv.text_changed.connect(func(t: String): Settings.set_v("serverUrl", t.strip_edges()))
	srow.add_child(srv)
	v.add_child(srow)
	var back_b := UI.btn("Back", "ghost", true, main)
	back_b.set_meta("is_back", true)
	v.add_child(_actions([back_b]))
	_focus_later(host_b)


func connecting(text: String) -> void:
	current = "connecting"
	var v := _screen(500)
	v.add_child(UI.title(text, 38))
	v.add_child(UI.para("Connecting to the game server..."))
	var cancel := UI.btn("Cancel", "ghost", true, func():
		cb.leave_online.call()
		online_screen())
	cancel.set_meta("is_back", true)
	v.add_child(_actions([cancel]))
	_focus_later(cancel)


## The room: who's here, and (for the host) the mode, the map and the bots. `info` is the lobby from
## the host ({mode, map, bots, players, started, ready}); empty while it hasn't arrived yet.
func lobby(info: Dictionary) -> void:
	var role: String = cb.online_role.call()
	if role == "":
		online_screen()
		return
	current = "lobby"
	if info.is_empty():
		info = cb.lobby_info.call()
	var v := _screen(980)
	var head := UI.hbox(18)
	var tv := UI.vbox(0)
	tv.add_child(UI.label("ROOM CODE", UI.BODY, 14, Color(UI.PAPER, 0.7)))
	tv.add_child(UI.label(Net.room if Net.room != "" else "...", UI.DISPLAY, 58, UI.SUN))
	head.add_child(tv)
	var hint := UI.para("Tell your friends this code: they pick Multiplayer, type it and press Join." if role == "host" else "You're in! The host picks the mode and the map and starts the match.", 16, 0.85)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(hint)
	v.add_child(head)
	var leave := UI.btn("Leave room", "ghost", true, func():
		cb.leave_online.call()
		online_screen())
	leave.set_meta("is_back", true)
	if info.is_empty() or not info.has("mode"):
		v.add_child(UI.para("Waiting for the room..."))
		v.add_child(_actions([leave]))
		_focus_later(leave)
		return
	var mode_id: String = info.mode
	var map_id_l: String = info.map
	var map_name: String = Maps.get_map(map_id_l).name if Maps.MAP_ORDER.has(map_id_l) else map_id_l
	var players: Array = info.get("players", [])
	var ready_d: Dictionary = info.get("ready", {})
	var pc := UI.blister()
	var pv := UI.vbox(4)
	pv.add_child(UI.label("Players  %d / %d" % [players.size(), Net.MAX_HUMANS], UI.DISPLAY, 22, UI.SUN))
	for i in players.size():
		var pl: Dictionary = players[i]
		var tag := "host" if i == 0 else ("ready" if str(ready_d.get(pl.id, "")) == map_id_l else "loading the map...")
		pv.add_child(UI.rich("[b]%s[/b]%s   [color=#fff6d8aa]%s[/color]" % [UI.esc(str(pl.name)), "  (you)" if pl.id == Net.id else "", tag], 18))
	var nb := int(info.bots)
	pv.add_child(UI.para("+ %d bot%s" % [nb, "" if nb == 1 else "s"], 15, 0.75))
	pc.add_child(pv)
	v.add_child(pc)
	if role == "host":
		v.add_child(UI.label("Mode", UI.BODY, 15, Color(UI.PAPER, 0.8)))
		var modes := UI.grid(4, 10, 10)
		for id in Modes.MODE_ORDER:
			var md: Dictionary = Modes.MODES[id]
			modes.add_child(UI.choice(md.short, "", id == mode_id, func():
				mode = id
				cb.lobby_set.call({"mode": id}), MODE_TAGS[id], 21))
		v.add_child(modes)
		v.add_child(UI.label("Map", UI.BODY, 15, Color(UI.PAPER, 0.8)))
		var maps := UI.grid(3, 10, 10)
		for id in Maps.MAP_ORDER:
			var mp := Maps.get_map(id)
			maps.add_child(UI.choice(mp.name, "", id == map_id_l, func():
				if id != map_id_l:
					cb.lobby_map.call(id), "", 21, 13))
		v.add_child(maps)
		var brow := UI.hbox(12)
		var bl := UI.label("Bots", UI.BODY, 17)
		bl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		brow.add_child(bl)
		var maxb := Roster.max_bots(mode_id, players.size())
		brow.add_child(_shrink(UI.btn("-", "", true, func(): cb.lobby_set.call({"bots": maxi(0, nb - 1)}))))
		var bn := UI.label(str(nb), UI.DISPLAY, 28, UI.SUN)
		bn.custom_minimum_size.x = 40
		bn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		brow.add_child(bn)
		brow.add_child(_shrink(UI.btn("+", "", true, func(): cb.lobby_set.call({"bots": mini(maxb, nb + 1)}))))
		var bh := UI.label("up to %d in this mode with %d player%s" % [maxb, players.size(), "" if players.size() == 1 else "s"], UI.BODY, 14, Color(UI.PAPER, 0.7))
		bh.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		brow.add_child(bh)
		v.add_child(brow)
	else:
		v.add_child(UI.rich("[b]%s[/b] on [b]%s[/b]" % [Modes.MODES[mode_id].name if Modes.MODES.has(mode_id) else mode_id, map_name], 22))
		if info.get("started", false):
			v.add_child(UI.para("A match is on right now. You'll join the next one when the host is back in the lobby.", 16))
		else:
			v.add_child(UI.para("Waiting for the host to start the match...", 16))
	var bar := UI.panel(UI.sb(Color(0, 0, 0, 0.2), 14, 0, Color.TRANSPARENT, Vector4(12, 8, 12, 8)))
	var lh := UI.hbox(10)
	var lb := UI.rich(_loadout_bb(), 15)
	lb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lh.add_child(lb)
	lh.add_child(UI.btn("Change loadout", "ghost", true, func(): collection("lobby")))
	bar.add_child(lh)
	v.add_child(bar)
	var acts := []
	if role == "host":
		var n: int = cb.lobby_loading.call()
		acts.append(UI.btn("Start match" if n == 0 else "Start match (%d still loading)" % n, "primary", true, func(): cb.lobby_start.call()))
	acts.append(leave)
	v.add_child(_actions(acts))
	_focus_later(acts[0])


static func _shrink(c: Control) -> Control:
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.custom_minimum_size.x = 52
	return c


func loading_map(nm: String) -> void:
	current = "loading"
	var lv := _screen(460)
	lv.add_child(UI.title("Loading " + nm))
	lv.add_child(UI.para("Getting onto the room's map. You stay in the room."))


# ------------------------------------------------------------------ loadout
func collection(back_to: String) -> void:
	current = "collection"
	back = back_to
	var v := _screen()
	var tr := UI.hbox(12)
	var tl := UI.title("Loadout")
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tr.add_child(tl)
	var wallet := UI.panel(UI.sb(Color(0, 0, 0, 0.25), 999, 0, Color.TRANSPARENT, Vector4(14, 6, 14, 6)))
	wallet.add_child(UI.rich(UI.coin_bb(Progress.coins), 22))
	wallet.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.add_child(wallet)
	v.add_child(tr)
	v.add_child(UI.para("Pick a class, then its blaster, scope and abilities. Lights swing a Toy Sword, Mediums a Toy Spear (melee key)." + (" Changes apply the next time you respawn." if back_to == "pause" else "")))
	# class
	var cls := Loadout.cls()
	var crow := UI.grid(2, 10, 10)
	for c in Cfg.CLASS_ORDER:
		var cd: Dictionary = Cfg.CLASSES[c]
		var sub := "%d health, %s" % [cd.health, "faster, Dash / Spring Hook / Cloak, Toy Sword" if c == "light" else "slower and tougher, Mesh Shield + Cloak, Toy Spear"]
		crow.add_child(UI.choice(cd.name.to_upper(), sub, c == cls, func():
			Loadout.set_cls(c)
			selected_weapon = Loadout.gun()
			abil_slot = 0
			collection(back_to), "CLASS", 22))
	v.add_child(crow)
	if not Cfg.CLASSES[cls].guns.has(selected_weapon) and selected_weapon != Cfg.CLASSES[cls].melee:
		selected_weapon = Loadout.gun()
	# abilities: Lights pick 2 of 3, Mediums always have both of theirs
	var ab := Loadout.abilities()
	var picks: bool = Cfg.CLASSES[cls].pick_abilities
	v.add_child(UI.rich("[font_size=12][color=#fff8ecd9]ABILITIES[/color][/font_size]  [font_size=13][color=#fff8eccc]%s[/color][/font_size]" % ("pick 2 of 3: choose a slot, then an ability" if picks else "Mediums always carry these two"), 12))
	var slots := UI.grid(2, 10, 10)
	for i in 2:
		var key := GInput.action_name("ability2" if i else "ability1")
		var b := UI.choice(Cfg.ABILITIES[ab[i]].name, "" if picks else ABILITY_INFO[ab[i]].desc, picks and abil_slot == i, func():
			if picks:
				abil_slot = i
				collection(back_to), "ABILITY %d   [%s]" % [i + 1, key], 19)
		slots.add_child(b)
	v.add_child(slots)
	if picks:
		var chips := UI.grid(3, 8, 8)
		for id in Cfg.CLASSES[cls].abilities:
			var on := ab.find(id)
			chips.add_child(UI.choice(Cfg.ABILITIES[id].name + ("  (%d)" % (on + 1) if on >= 0 else ""), ABILITY_INFO[id].desc, on >= 0, func():
				if Loadout.abilities()[abil_slot] == id:
					return
				Loadout.set_ability(abil_slot, id)
				# the next pick fills the other slot, so two clicks set both
				abil_slot = 0 if abil_slot else 1
				collection(back_to), "", 15, 12))
		v.add_child(chips)
	# equipped blaster, melee weapon and gadget
	var eq := UI.grid(3, 10, 10)
	var gid := Loadout.gun()
	var gcard := UI.panel(UI.sb(Color(0, 0, 0, 0.22), 14, 3, U.col(_wcolor(gid)), Vector4(12, 8, 12, 8)))
	var gv := UI.vbox(0)
	gv.add_child(UI.label("BLASTER", UI.BODY, 12, Color(UI.PAPER, 0.75)))
	gv.add_child(UI.label(Cfg.WEAPONS[gid].name, UI.DISPLAY, 19))
	gv.add_child(UI.label(Cfg.SCOPES[Loadout.scope(gid)].name, UI.BODY, 13, Color(UI.PAPER, 0.85)))
	gcard.add_child(gv)
	gcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_child(gcard)
	var mid: String = Cfg.CLASSES[cls].melee
	var mcard := UI.panel(UI.sb(Color(0, 0, 0, 0.22), 14, 3, U.col(Cfg.MELEE[mid].color), Vector4(12, 8, 12, 8)))
	var mv := UI.vbox(0)
	mv.add_child(UI.label("MELEE", UI.BODY, 12, Color(UI.PAPER, 0.75)))
	mv.add_child(UI.label(Cfg.MELEE[mid].name, UI.DISPLAY, 19))
	mv.add_child(UI.label("Always carried: %s to hold, %s to swing" % [GInput.action_name("weapon2"), GInput.action_name("melee")], UI.BODY, 13, Color(UI.PAPER, 0.85)))
	mcard.add_child(mv)
	mcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_child(mcard)
	var dcard := UI.panel(UI.sb(Color(0, 0, 0, 0.22), 14, 3, Color(1, 1, 1, 0.25), Vector4(12, 8, 12, 8)))
	var dv := UI.vbox(0)
	dv.add_child(UI.label("GADGET  -  COMING SOON", UI.BODY, 12, Color(UI.PAPER, 0.75)))
	var gnames := []
	for g in Cfg.CLASSES[cls].gadgets:
		gnames.append(GADGET_NAMES.get(g, g))
	dv.add_child(UI.label(", ".join(gnames), UI.BODY, 14, Color(UI.PAPER, 0.5)))
	dcard.add_child(dv)
	dcard.modulate.a = 0.7
	dcard.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	eq.add_child(dcard)
	v.add_child(eq)
	# weapon list (this class's blasters) + viewer
	var colls := UI.hbox(18)
	var wl := UI.vbox(6)
	wl.custom_minimum_size.x = 220
	for id in Cfg.CLASSES[cls].guns:
		var owned: bool = Progress.owns(id)
		var chosen: bool = id == selected_weapon
		var bst := UI.sb(Color(1, 1, 1, 0.18) if chosen else Color(1, 1, 1, 0.07), 14, 0, Color.TRANSPARENT, Vector4(12, 9, 12, 6))
		bst.border_width_left = 8
		bst.border_color = U.col(_wcolor(id))
		var b := Button.new()
		b.text = Cfg.WEAPONS[id].name + ("" if owned else "   ● " + UI.thousands(Progress.price(id)))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", UI.DISPLAY)
		b.add_theme_font_size_override("font_size", 19)
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, bst)
		b.add_theme_stylebox_override("focus", UI._focus_ring(14))
		b.add_theme_color_override("font_color", UI.SUN if chosen else UI.PAPER)
		b.add_theme_color_override("font_hover_color", UI.SUN)
		b.modulate.a = 1.0 if owned or chosen else 0.62
		UI._wire(b, func():
			selected_weapon = id
			collection(back_to))
		wl.add_child(b)
	# the class's melee weapon (always carried)
	wl.add_child(UI.label("MELEE", UI.BODY, 12, Color(UI.PAPER, 0.75)))
	var mel: String = Cfg.CLASSES[cls].melee
	var mst := UI.sb(Color(1, 1, 1, 0.18) if selected_weapon == mel else Color(1, 1, 1, 0.07), 14, 0, Color.TRANSPARENT, Vector4(12, 9, 12, 6))
	mst.border_width_left = 8
	mst.border_color = U.col(Cfg.MELEE[mel].color)
	var mb := Button.new()
	mb.text = Cfg.MELEE[mel].name.to_upper()
	mb.alignment = HORIZONTAL_ALIGNMENT_LEFT
	mb.add_theme_font_override("font", UI.DISPLAY)
	mb.add_theme_font_size_override("font_size", 19)
	for st in ["normal", "hover", "pressed"]:
		mb.add_theme_stylebox_override(st, mst)
	mb.add_theme_stylebox_override("focus", UI._focus_ring(14))
	mb.add_theme_color_override("font_color", UI.SUN if selected_weapon == mel else UI.PAPER)
	mb.add_theme_color_override("font_hover_color", UI.SUN)
	UI._wire(mb, func():
		selected_weapon = mel
		collection(back_to))
	wl.add_child(mb)
	colls.add_child(wl)
	var view := UI.blister(Vector4(16, 12, 16, 16))
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vv := UI.vbox(6)
	vv.add_child(_preview_view())
	_weapon_info(vv, back_to)
	view.add_child(vv)
	colls.add_child(view)
	v.add_child(colls)
	# redeem a code
	var rd := UI.hbox(10)
	rd.add_child(UI.label("Have a code?", UI.BODY, 13, Color(UI.PAPER, 0.8)))
	var code := UI.line_edit("Enter code", false, 24)
	code.custom_minimum_size.x = 170
	code.add_theme_font_size_override("font_size", 15)
	rd.add_child(code)
	var out := UI.label("", UI.BOLD, 15)
	var redeem := func():
		var msg: String = Progress.redeem(code.text)
		out.text = msg if msg != "" else "That code didn't work."
		out.add_theme_color_override("font_color", Color("#7dff6b") if msg != "" else Color("#ff8fa3"))
		if msg == "":
			return
		code.text = ""
		audio.fanfare(true)
		var keep := out.text
		collection(back_to)
		_find_redeem_out(keep)
	code.text_submitted.connect(func(_t): redeem.call())
	rd.add_child(UI.btn("Redeem", "ghost", true, redeem))
	rd.add_child(out)
	out.set_meta("redeem_out", true)
	v.add_child(rd)
	var bk := UI.btn("Back", "ghost", true, func(): _go_back())
	bk.set_meta("is_back", true)
	v.add_child(_actions([bk]))


func _find_redeem_out(msg: String) -> void:
	var stack := [root]
	while stack.size():
		var n: Node = stack.pop_back()
		if n.has_meta("redeem_out"):
			(n as Label).text = msg
			(n as Label).add_theme_color_override("font_color", Color("#7dff6b"))
			return
		stack.append_array(n.get_children())


static func _wcolor(id: String) -> String:
	if Cfg.MELEE.has(id):
		return Cfg.MELEE[id].color
	var c: Dictionary = Cfg.WEAPONS[id].colors
	return c.accent if c.main in ["#1d1d1f", "#f2f7ff"] else c.main


func _preview_view() -> Control:
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(0, 260)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Lighting.environment({"background": "#000000", "fog": ["#000000", 1000.0, 2000.0], "exposure": 1.0, "hemi": ["#fff1dc", "#5a4a80", 1.2]})
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	env.environment.fog_enabled = false
	env.environment.glow_enabled = false
	vp.add_child(env)
	var key := DirectionalLight3D.new()
	key.light_color = U.col("#ffe2b8")
	key.light_energy = 2.5 * Lighting.SUN_SCALE
	vp.add_child(key)
	key.look_at_from_position(Vector3(2, 3, 2), Vector3.ZERO, Vector3.UP)
	var cam := Camera3D.new()
	cam.fov = 32
	cam.near = 0.1
	cam.far = 50
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0, 0.35, 2.9), Vector3.ZERO, Vector3.UP)
	var m: Node3D
	if Cfg.MELEE.has(selected_weapon):
		# lay the sword / spear sideways across the view (wrapped so its turn counts when it's sized)
		m = Node3D.new()
		var inner := MeleeModel.build(selected_weapon)
		inner.rotation = Vector3(0, PI / 2, 0.35)
		m.add_child(inner)
	else:
		m = WeaponModel.build(selected_weapon)
	var aabb := _model_aabb(m)
	var sz := aabb.size.length()
	var s := 1.6 / maxf(0.01, sz)
	m.scale = Vector3.ONE * s
	m.position = -aabb.get_center() * s
	var holder := Node3D.new()
	holder.add_child(m)
	vp.add_child(holder)
	preview = {"model": holder}
	return svc


static func _model_aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	var stack := [[n, Transform3D()]]
	while stack.size():
		var e: Array = stack.pop_back()
		var node: Node = e[0]
		var xf: Transform3D = e[1]
		for c in node.get_children():
			if c is Node3D:
				var cx: Transform3D = xf * (c as Node3D).transform
				if c is MeshInstance3D and (c as MeshInstance3D).mesh:
					var bb := cx * (c as MeshInstance3D).mesh.get_aabb()
					out = bb if first else out.merge(bb)
					first = false
				stack.append([c, cx])
	return out


func _weapon_info(vv: VBoxContainer, back_to: String) -> void:
	var id := selected_weapon
	if Cfg.MELEE.has(id):
		_melee_info(vv, id)
		return
	var w: Dictionary = Cfg.WEAPONS[id]
	var owned: bool = Progress.owns(id)
	var tier: String = Progress.tier_of(id)
	var c := _wcolor(id)
	vv.add_child(UI.label(w.name, UI.DISPLAY, 34, U.col(c)))
	vv.add_child(UI.rich("[color=#fff8ecbf]%s[/color]  [bgcolor=%s][color=#1a1030][font_size=11][b] %s [/b][/font_size][/color][/bgcolor]%s" % [w.category, Progress.TIER_COLORS[tier], tier.to_upper(), "" if owned else "  [bgcolor=#ff8fa3][color=#1a1030][font_size=11][b] LOCKED [/b][/font_size][/color][/bgcolor]"], 15))
	vv.add_child(UI.para(w.blurb, 16, 1.0))
	var dps: float
	if w.has("burst"):
		dps = w.damage * w.burst.count / (w.burst.count * w.burst.gap + 60.0 / w.rpm)
	else:
		dps = w.damage * w.pellets * w.rpm / 60.0
	var meters := [
		["Damage", minf(1, w.damage * w.pellets / 81.0), ("%d×%d" % [w.pellets, w.damage]) if w.pellets > 1 else ("0-%d" % w.damage if w.has("charge") else str(w.damage))],
		["Fire rate", minf(1, w.rpm / 1050.0), "%d-shot burst" % w.burst.count if w.has("burst") else "%d rpm" % w.rpm],
		["Damage/sec", minf(1, dps / 200.0), str(roundi(dps))],
		["Range", minf(1, w.effectiveRange / 80.0), "arc" if w.has("explosion") else ("arc, no falloff" if w.has("charge") else "%d m" % w.effectiveRange)],
		["Magazine", minf(1, w.magSize / 50.0), "%d energy" % w.magSize if w.has("energy") else str(w.magSize)],
		["Reload", 1.0 if w.has("energy") else maxf(0.05, 1 - w.reloadTime / 3.4), "recharges" if w.has("energy") else ("%ss/shell" % str(w.reloadPerShell) if w.has("reloadPerShell") else "%ss" % str(w.reloadTime))],
	]
	var g := UI.grid(3, 10, 6)
	for mt in meters:
		var n := UI.label(mt[0], UI.BODY, 15)
		n.custom_minimum_size.x = 110
		var bar := HUD.Bar.new()
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.bg = Color(1, 1, 1, 0.12)
		bar.border = 0
		bar.radius = 99
		bar.frac = mt[1]
		bar.ghost = mt[1]
		bar.fill_a = U.col(c)
		bar.fill_b = U.col(c)
		var t := UI.label(mt[2], UI.BODY, 15)
		t.custom_minimum_size.x = 70
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(n)
		g.add_child(bar)
		g.add_child(t)
	vv.add_child(g)
	# scope picker
	vv.add_child(UI.label("SCOPE", UI.BODY, 12, Color(UI.PAPER, 0.75)))
	var sc := HFlowContainer.new()
	sc.add_theme_constant_override("h_separation", 6)
	var cur_scope := Loadout.scope(id)
	for s in Cfg.WEAPON_SCOPES[id]:
		sc.add_child(UI.chip(Cfg.SCOPES[s].name, s == cur_scope, func():
			Loadout.set_scope(id, s)
			collection(back_to)))
	vv.add_child(sc)
	var sd: Dictionary = Cfg.SCOPES[cur_scope]
	var zoom: float = sd.zoom if sd.zoom != null else w.adsZoom
	var zs := ("%.2f" % zoom).trim_suffix("0")
	vv.add_child(UI.para("%s Zoom %sx." % [sd.blurb, zs], 13.5, 0.9))
	if owned:
		var row := UI.hbox(8)
		var is_eq := Loadout.gun() == id
		var b := UI.btn("Equipped" if is_eq else "Equip", "primary" if is_eq else "", true, func():
			Loadout.set_gun(id)
			collection(back_to))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		vv.add_child(row)
	else:
		var row := UI.hbox(8)
		var can: bool = Progress.can_afford(id)
		var ub := UI.btn("Unlock for ● " + UI.thousands(Progress.price(id)), "primary", true, func():
			if not Progress.unlock(id):
				return
			audio.fanfare(true)
			collection(back_to))
		ub.disabled = not can
		row.add_child(ub)
		if not can:
			var need := UI.para("You have %s. Earn %s more by finishing matches." % [UI.thousands(Progress.coins), UI.thousands(Progress.price(id) - Progress.coins)], 13, 0.8)
			need.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(need)
		vv.add_child(row)


## The melee weapon's page in Loadout: what it does and how to use it.
func _melee_info(vv: VBoxContainer, id: String) -> void:
	var md: Dictionary = Cfg.MELEE[id]
	vv.add_child(UI.label(md.name, UI.DISPLAY, 34, U.col(md.color)))
	vv.add_child(UI.rich("[color=#fff8ecbf]Melee - always carried by %ss[/color]" % ("Light" if id == "sword" else "Medium"), 15))
	vv.add_child(UI.para("Quick, wide swings that hit everyone in front of you." if id == "sword" else "Slower thrusts with long reach that hit everyone in front of you.", 16, 1.0))
	var meters := [
		["Damage", minf(1, md.damage / 81.0), str(int(md.damage))],
		["Reach", minf(1, md.range / 5.0), "%.1f m" % md.range],
		["Swing speed", clampf(1.2 - md.swing, 0.05, 1), "%.2f s" % md.swing],
		["Width", minf(1, md.arcDeg / 120.0), "%d°" % int(md.arcDeg)],
	]
	var g := UI.grid(3, 10, 6)
	for mt in meters:
		var n := UI.label(mt[0], UI.BODY, 15)
		n.custom_minimum_size.x = 110
		var bar := HUD.Bar.new()
		bar.custom_minimum_size = Vector2(0, 12)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.bg = Color(1, 1, 1, 0.12)
		bar.border = 0
		bar.radius = 99
		bar.frac = mt[1]
		bar.ghost = mt[1]
		bar.fill_a = U.col(md.color)
		bar.fill_b = U.col(md.color)
		var t := UI.label(mt[2], UI.BODY, 15)
		t.custom_minimum_size.x = 70
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		g.add_child(n)
		g.add_child(bar)
		g.add_child(t)
	vv.add_child(g)
	vv.add_child(UI.para("Press %s to take it out (then left click to swing, %s for your blaster), or %s for a quick swing any time." % [GInput.action_name("weapon2"), GInput.action_name("weapon1"), GInput.action_name("melee")], 14, 0.9))


# ------------------------------------------------------------------ settings
func settings_screen(back_to: String) -> void:
	current = "settings"
	back = back_to
	var v := _screen()
	v.add_child(UI.title("Settings"))
	v.add_child(UI.para("Changes apply right away and are saved on this computer."))
	var grid := UI.grid(3, 16, 16)
	var set_k := func(k: String, val) -> void:
		Settings.set_v(k, val)
		cb.settings_changed.call(k)
	var group := func(title_text: String) -> VBoxContainer:
		var p := UI.blister(Vector4(16, 14, 16, 14))
		p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		p.custom_minimum_size.x = 280
		var gv := UI.vbox(7)
		gv.add_child(UI.label(title_text, UI.DISPLAY, 22, UI.SUN))
		p.add_child(gv)
		grid.add_child(p)
		return gv
	var range_row := func(gv: VBoxContainer, k: String, lbl: String, mn: float, mx: float, st: float, fmt: Callable) -> void:
		var h := UI.hbox(8)
		var l := UI.label(lbl, UI.BODY, 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var o := UI.label(fmt.call(float(Settings.get_v(k))), UI.BODY, 14, Color(UI.PAPER, 0.85))
		o.custom_minimum_size.x = 40
		o.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var s := UI.slider(mn, mx, st, float(Settings.get_v(k)), func(val: float):
			set_k.call(k, val)
			o.text = fmt.call(val))
		h.add_child(l)
		h.add_child(s)
		h.add_child(o)
		gv.add_child(h)
	var check_row := func(gv: VBoxContainer, k: String, lbl: String) -> void:
		var h := UI.hbox(8)
		var l := UI.label(lbl, UI.BODY, 15)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(l)
		h.add_child(UI.check(bool(Settings.get_v(k)), func(on: bool): set_k.call(k, on)))
		gv.add_child(h)
	var f2 := func(x: float) -> String: return "%.2f" % x
	var pct := func(x: float) -> String: return str(roundi(x * 100))
	var g: VBoxContainer = group.call("Mouse")
	range_row.call(g, "sensitivity", "Sensitivity", 0.1, 3, 0.05, f2)
	range_row.call(g, "adsSensitivity", "Aiming sensitivity", 0.3, 1.5, 0.05, f2)
	check_row.call(g, "invertY", "Invert Y axis")
	g = group.call("Controller")
	range_row.call(g, "padSensitivity", "Look sensitivity", 0.3, 2.5, 0.05, f2)
	check_row.call(g, "padAimAssist", "Aim assist")
	check_row.call(g, "padVibration", "Vibration")
	g = group.call("Video")
	range_row.call(g, "fov", "Field of view", 70, 110, 1, func(x: float) -> String: return "%d°" % roundi(x))
	var qh := UI.hbox(8)
	var ql := UI.label("Graphics quality", UI.BODY, 15)
	ql.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qh.add_child(ql)
	var opt := OptionButton.new()
	for q in ["low", "medium", "high"]:
		opt.add_item(q.capitalize())
	opt.selected = ["low", "medium", "high"].find(Settings.get_v("quality"))
	opt.item_selected.connect(func(i: int): set_k.call("quality", ["low", "medium", "high"][i]))
	opt.add_theme_font_override("font", UI.BODY)
	opt.add_theme_stylebox_override("focus", UI._focus_ring(10))
	qh.add_child(opt)
	g.add_child(qh)
	check_row.call(g, "fullscreen", "Fullscreen")
	check_row.call(g, "motionBlur", "Motion blur")
	check_row.call(g, "showFps", "Show frame rate")
	g = group.call("Comfort")
	check_row.call(g, "reducedMotion", "Reduced motion")
	check_row.call(g, "cameraShake", "Camera shake")
	check_row.call(g, "enemyOutlines", "Outline enemy toys")
	check_row.call(g, "damageNumbers", "Floating damage numbers")
	g = group.call("Audio")
	range_row.call(g, "masterVolume", "Master", 0, 1, 0.01, pct)
	range_row.call(g, "musicVolume", "Music", 0, 1, 0.01, pct)
	range_row.call(g, "sfxVolume", "Effects", 0, 1, 0.01, pct)
	range_row.call(g, "ambienceVolume", "Ambience", 0, 1, 0.01, pct)
	g = group.call("Crosshair")
	var sw := UI.hbox(6)
	var swl := UI.label("Color", UI.BODY, 15)
	swl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sw.add_child(swl)
	for col in ["#ffffff", "#7dff6b", "#ffd23f", "#5ff4ff", "#ff6bd5", "#ff4d4d"]:
		var on: bool = col == Settings.get_v("crosshairColor")
		var b := Button.new()
		b.custom_minimum_size = Vector2(26, 26)
		var st := UI.sb(U.col(col), 13, 3, Color.WHITE if on else Color(1, 1, 1, 0.3))
		for s in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(s, st)
		b.add_theme_stylebox_override("focus", UI._focus_ring(13))
		UI._wire(b, func():
			set_k.call("crosshairColor", col)
			settings_screen(back_to))
		sw.add_child(b)
	g.add_child(sw)
	range_row.call(g, "crosshairSize", "Size", 0.6, 1.8, 0.05, f2)
	check_row.call(g, "crosshairDot", "Center dot")
	g = group.call("Player")
	var nh := UI.hbox(8)
	nh.add_child(UI.label("Name", UI.BODY, 15))
	var ne := UI.line_edit("", false, 14)
	ne.text = Settings.get_v("playerName")
	ne.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ne.text_changed.connect(func(t: String): set_k.call("playerName", t.strip_edges() if t.strip_edges() != "" else "You"))
	nh.add_child(ne)
	g.add_child(nh)
	v.add_child(grid)
	var bk := UI.btn("Back", "ghost", true, func(): _go_back())
	bk.set_meta("is_back", true)
	v.add_child(_actions([bk, UI.btn("Reset to defaults", "ghost", true, func():
		Settings.reset()
		for k in Settings.data:
			cb.settings_changed.call(k)
		settings_screen(back))]))


# ------------------------------------------------------------------ controls
func controls(back_to: String) -> void:
	current = "controls"
	back = back_to
	if input:
		input.cancel_capture()
	var ab := Loadout.abilities()
	var v := _screen()
	v.add_child(UI.title("Controls"))
	v.add_child(UI.para("Click a box (or highlight it and press A), then press the key, mouse button or controller button you want. Esc cancels, Backspace clears the box. If another action already used it, the two swap."))
	var head := _bind_row("ACTION", [UI.label("KEY", UI.BODY, 12, Color(UI.PAPER, 0.7)), UI.label("SECOND KEY", UI.BODY, 12, Color(UI.PAPER, 0.7)), UI.label("CONTROLLER", UI.BODY, 12, Color(UI.PAPER, 0.7))], true)
	v.add_child(head)
	for a in Binds.ACTIONS:
		var lbl: String = a.label
		if a.id == "ability1":
			lbl = "Ability 1 (%s)" % Cfg.ABILITIES[ab[0]].name
		elif a.id == "ability2":
			lbl = "Ability 2 (%s)" % Cfg.ABILITIES[ab[1]].name
		var k: Array = Binds.kb[a.id]
		var cells := [_bind_btn(a.id, "0", Binds.key_label(k[0])), _bind_btn(a.id, "1", Binds.key_label(k[1]))]
		if a.has("stick"):
			cells.append(UI.label(a.stick, UI.BODY, 14, Color(UI.PAPER, 0.6)))
		else:
			cells.append(_bind_btn(a.id, "pad", Binds.pad_label(Binds.pad[a.id])))
		v.add_child(_bind_row(lbl, cells, false))
	v.add_child(UI.para("Always the same: Esc or the controller's Menu button pauses, the mouse wheel switches weapons, the mouse or right stick looks. Choose which two abilities you bring on the Loadout screen. Reload and revive can share a controller button: next to a downed teammate it revives, otherwise it reloads.", 14, 0.75))
	v.add_child(UI.para("Any standard controller works (Xbox, PlayStation, Switch Pro...). On PlayStation pads A = Cross, B = Circle, X = Square, Y = Triangle, LB/RB = L1/R1, LT/RT = L2/R2. Look speed, aim assist and vibration are in Settings. Sprint into crouch to slide.", 14, 0.75))
	var bk := UI.btn("Back", "ghost", true, func():
		if input:
			input.cancel_capture()
		_go_back())
	bk.set_meta("is_back", true)
	v.add_child(_actions([bk, UI.btn("Reset controls", "ghost", true, func():
		Binds.reset()
		controls(back))]))


func _bind_row(lbl: String, cells: Array, head: bool) -> Control:
	var h := UI.hbox(8)
	var l := UI.label(lbl, UI.BODY, 12 if head else 15, Color(UI.PAPER, 0.7 if head else 1.0))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.size_flags_stretch_ratio = 1.6
	h.add_child(l)
	for c in cells:
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(c)
	return h


func _bind_btn(act: String, slot: String, text: String) -> Button:
	var b := Button.new()
	b.text = text if text != "" else "—"
	b.custom_minimum_size.y = 30
	b.add_theme_font_override("font", UI.BOLD)
	b.add_theme_font_size_override("font_size", 14)
	var st := UI.sb(UI.PAPER, 9, 0, Color.TRANSPARENT, Vector4(8, 5, 8, 5)) if text != "" else UI.sb(Color(1, 1, 1, 0.12), 9, 0, Color.TRANSPARENT, Vector4(8, 5, 8, 5))
	if text != "":
		st.shadow_color = Color("#b9a98f")
		st.shadow_size = 1
		st.shadow_offset = Vector2(0, 3)
	b.add_theme_stylebox_override("normal", st)
	b.add_theme_stylebox_override("hover", UI.sb(Color.WHITE, 9, 0, Color.TRANSPARENT, Vector4(8, 5, 8, 5)))
	b.add_theme_stylebox_override("pressed", st)
	b.add_theme_stylebox_override("focus", UI._focus_ring(9))
	b.add_theme_color_override("font_color", UI.INK if text != "" else Color(1, 1, 1, 0.55))
	b.add_theme_color_override("font_hover_color", UI.INK)
	UI._wire(b, func(): _listen_for(b, act, slot))
	return b


## Waits for the next key / mouse button / controller button and binds it to the clicked box.
func _listen_for(b: Button, act: String, slot: String) -> void:
	if input == null:
		return
	b.text = "Press a button…" if slot == "pad" else "Press a key…"
	b.add_theme_stylebox_override("normal", UI.sb(UI.SUN, 9, 0, Color.TRANSPARENT, Vector4(8, 5, 8, 5)))
	input.capture(func(c):
		if c != null:
			if slot == "pad":
				if c.kind == "pad":
					Binds.set_pad(act, c.btn)
				elif c.code == "Backspace" or c.code == "Delete":
					Binds.set_pad(act, -1)
				else:
					_listen_for(b, act, slot)  # a keyboard key on a controller box: keep waiting
					return
			elif c.kind == "kb":
				var clear: bool = c.code == "Backspace" or c.code == "Delete"
				Binds.set_kb(act, 1 if slot == "1" else 0, "" if clear else c.code)
		audio.ui_click()
		controls(back))


func credits() -> void:
	current = "credits"
	var v := _screen()
	v.add_child(UI.title("Credits"))
	v.add_child(UI.para("Toybox Mayhem is an original game. Every toy, room prop, weapon model, texture, sound effect and music track is generated in code at runtime, so there are no outside art or audio files."))
	var g := UI.grid(2, 26, 6)
	for row in [["Engine", "Godot 4.7"], ["Physics and character movement", "Jolt Physics"], ["Language", "GDScript"], ["Sound and music", "synthesized in code"], ["Fonts", "Luckiest Guy, Baloo 2 (OFL)"]]:
		var a := UI.label(row[0], UI.BODY, 16)
		a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var b := UI.label(row[1], UI.BOLD, 16)
		g.add_child(a)
		g.add_child(b)
	v.add_child(g)
	var bk := UI.btn("Back", "ghost", true, main)
	bk.set_meta("is_back", true)
	v.add_child(_actions([bk]))
	_focus_later(bk)


func _go_back() -> void:
	if back == "pause":
		pause()
	elif back == "lobby":
		lobby({})
	elif back == "play":
		play()
	else:
		main()


# ------------------------------------------------------------------ in-game
func pause() -> void:
	current = "pause"
	var v := _screen(440)
	v.add_child(UI.title("Paused"))
	var resume := UI.btn("Resume", "primary", false, func(): cb.resume.call())
	var role: String = cb.online_role.call()
	var extra := [UI.btn("Try a blaster", "", false, try_blaster)] if training_mode and role == "" else []
	var quit_text := "Quit to main menu" if role == "" else ("End match, close room" if role == "host" else "Leave online match")
	if role != "":
		v.add_child(UI.para("Online: the match keeps going while this menu is open.", 15, 0.8))
	for b in [resume] + extra + [UI.btn("Loadout and unlocks", "", false, func(): collection("pause")), UI.btn("Settings", "", false, func(): settings_screen("pause")),
			UI.btn("Controls", "", false, func(): controls("pause")), UI.btn(quit_text, "", false, func(): cb.quit.call())]:
		b.custom_minimum_size.y = 58
		v.add_child(b)
	_focus_later(resume)


## Training: pick any blaster (locked ones too) for the slot you're holding. It lasts for this session only.
func try_blaster() -> void:
	current = "try"
	back = "pause"
	var v := _screen(900)
	v.add_child(UI.title("Try a blaster"))
	v.add_child(UI.para("Swaps your blaster for this training session. Locked blasters work here too; buying them is still done in Loadout. A blaster from the other class switches your class (health, speed, abilities) from your next respawn."))
	var cur: String = cb.current_weapon.call()
	var g := UI.grid(3, 10, 10)
	var first: Control = null
	for wid in Cfg.WEAPON_ORDER:
		var w: Dictionary = Cfg.WEAPONS[wid]
		var tag := "" if Progress.owns(wid) else "Locked"
		var c := UI.choice(w.name, "%s - %s" % [Cfg.CLASSES[Cfg.class_of_gun(wid)].name, w.category], wid == cur, func():
			cb.training_try.call(wid)
			cb.resume.call(), tag, 20, 13)
		g.add_child(c)
		if wid == cur or first == null:
			first = c
	v.add_child(g)
	var back_b := UI.btn("Back", "ghost", true, pause)
	back_b.set_meta("is_back", true)
	v.add_child(_actions([back_b]))
	_focus_later(first)


func results(m: Match, actors: Array, me: Actor, reward: Dictionary) -> void:
	current = "results"
	var st := m.standings(actors)
	var place := st.find(me) + 1
	var won := m.is_winner(me)
	var acc := roundi(float(me.shots_hit) / me.shots_fired * 100) if me.shots_fired else 0
	var ord := func(n: int) -> String: return "%d%s" % [n, "st" if n == 1 else ("nd" if n == 2 else ("rd" if n == 3 else "th"))]
	var title_text: String
	var line: String
	if m.teams():
		var wt := m.winner_team
		var s := m.team_scores.map(func(x): return floori(x))
		title_text = "It’s a draw!" if wt == Modes.DRAW else ("Your team wins!" if won else "Team %s wins" % Modes.TEAMS[wt].name)
		var conq: bool = m.mode.id == "conquest"
		var why := "Time ran out."
		if m.end_reason == "score" and wt >= 0:
			why = ("Team %s took control of %d of the 6 sectors." % [Modes.TEAMS[wt].name, m.kill_target()]) if conq else "Team %s reached %d." % [Modes.TEAMS[wt].name, m.kill_target()]
		var mates := m.standings(actors.filter(func(a): return a.team == me.team))
		var finals := []
		for t in s.size():
			finals.append("%s %d%s" % [Modes.TEAMS[t].name, s[t], (" sector" if s[t] == 1 else " sectors") if conq else ""])
		line = "%s Final score: %s. You were %s on your team." % [why, ", ".join(finals), ord.call(mates.find(me) + 1)]
	else:
		var wn: String = m.winner.name if m.winner else "Nobody"
		title_text = "You win the toy box!" if won else "%s wins" % wn
		line = "%s You finished %s of %d." % ["%s reached %d pops." % [wn, m.kill_target()] if m.end_reason == "score" else "Time ran out.", ord.call(place), actors.size()]
	var v := _screen()
	var tl := UI.label(title_text, UI.DISPLAY, 52, UI.SUN)
	tl.add_theme_color_override("font_shadow_color", UI.ORANGE)
	tl.add_theme_constant_override("shadow_offset_y", 4)
	v.add_child(tl)
	v.add_child(UI.para(line, 20, 0.9))
	if not reward.is_empty():
		var rp := UI.blister(Vector4(16, 10, 16, 10))
		var rv := UI.vbox(4)
		rv.add_child(UI.label("+%s coins" % UI.thousands(reward.total), UI.DISPLAY, 28, UI.SUN))
		var rg := UI.grid(2, 18, 2)
		for ln in reward.lines:
			var row := UI.hbox()
			row.custom_minimum_size.x = 400
			var a := UI.label(ln[0], UI.BODY, 15)
			a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(a)
			row.add_child(UI.label(("+" if ln[1] >= 0 else "") + str(ln[1]), UI.BOLD, 15))
			rg.add_child(row)
		rv.add_child(rg)
		var aff := ""
		if reward.affordable.size():
			aff = " You can unlock [b]%s[/b] now in Loadout." % ", ".join(reward.affordable.map(func(id): return Cfg.WEAPONS[id].name))
		var rt := UI.rich("You have %s.%s" % [UI.coin_bb(reward.coinsAfter), aff], 15)
		rt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rv.add_child(rt)
		rp.add_child(rv)
		v.add_child(rp)
	v.add_child(HUD.build_board(actors, m, me))
	var ms := UI.grid(6, 8, 8)
	for s in [[me.kills, "Pops"], [me.deaths, "Times popped"], ["%d%%" % acc, "Accuracy"], [me.headshots, "Headshot pops"], [me.best_streak, "Best streak"], [roundi(me.damage_dealt), "Damage dealt"]]:
		var b := UI.blister(Vector4(10, 6, 10, 6))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var bv := UI.vbox(0)
		bv.add_child(UI.label(str(s[0]), UI.DISPLAY, 24, UI.SUN))
		bv.add_child(UI.label(s[1], UI.BODY, 14, Color(UI.PAPER, 0.8)))
		b.add_child(bv)
		ms.add_child(b)
	v.add_child(ms)
	if cb.online_role.call() != "":
		var to_lobby := UI.btn("Back to the lobby", "primary", true, func(): cb.back_to_lobby.call())
		v.add_child(_actions([to_lobby, UI.btn("Leave room", "ghost", true, func(): cb.quit.call())]))
		_focus_later(to_lobby)
		return
	var again := UI.btn("Play again", "primary", true, func(): cb.play_again.call())
	v.add_child(_actions([again, UI.btn("Loadout and unlocks", "ghost", true, func():
		cb.quit.call()
		collection("main")), UI.btn("Main menu", "ghost", true, func(): cb.quit.call())]))
	_focus_later(again)


## Controller B: the screen's Back button, or resume from the pause menu. Returns true if it did something.
func pad_back() -> bool:
	if current == "pause":
		cb.resume.call()
		return true
	var stack := [root]
	while stack.size():
		var n: Node = stack.pop_back()
		if n is Button and n.has_meta("is_back") and n.get_meta("is_back"):
			(n as Button).pressed.emit()
			return true
		stack.append_array(n.get_children())
	return false


## Controller Start/Menu: resumes from the pause menu.
func pad_start() -> bool:
	if current != "pause":
		return false
	cb.resume.call()
	return true


## "Click to keep playing" card (the original needed a click to re-grab the mouse).
func resume_hint(show_it: bool, on_click: Callable) -> void:
	if not show_it:
		if _resume_hint:
			_resume_hint.queue_free()
		_resume_hint = null
		return
	if _resume_hint:
		return
	var c := UI.card(Vector4(28, 18, 28, 18))
	var v := UI.vbox(2)
	v.add_child(UI.label("Click to keep playing", UI.DISPLAY, 30, UI.SUN))
	v.add_child(UI.label("The game needs a click to grab the mouse again.", UI.BODY, 16))
	c.add_child(v)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed:
			resume_hint(false, Callable())
			on_click.call())
	add_child(c)
	_pin(c, 0.5, 0.5, Control.GROW_DIRECTION_BOTH, Control.GROW_DIRECTION_BOTH)
	_resume_hint = c


func _focus_later(c: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(c) and c.is_inside_tree() and c.is_visible_in_tree():
		c.grab_focus()

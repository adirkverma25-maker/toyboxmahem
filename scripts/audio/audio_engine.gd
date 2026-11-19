class_name AudioEngine
extends Node3D
## Everything you hear is synthesized (port of src/audio/Audio.ts): no audio files. Each sound is a recipe of
## oscillator / filtered-noise layers rendered by Synth; a few random renders of every recipe are cached
## (warmed on a background thread) so shots still vary. Positional sounds use AudioStreamPlayer3D with the
## original's reference distances; sounds behind walls go through a muffled bus.

const MAX_VOICES := 56
const ZONE_LOOPS := [
	["closet", "brown", "lowpass", 120.0, 0.5],
	["desk", "pink", "bandpass", 2400.0, 0.04],
	["dino", "brown", "lowpass", 90.0, 0.6],
	["garage", "pink", "bandpass", 180.0, 0.18],
	["bed", "pink", "lowpass", 600.0, 0.05],
	["brick", "white", "bandpass", 5000.0, 0.015],
	["rug", "pink", "lowpass", 400.0, 0.03],
]
const RELOAD_PITCH := {"plasti9": 1.25, "foamFury": 1.0, "brickbreaker": 0.8, "bubbleBlaster": 1.1, "thunderspring": 0.9, "rapidRascal": 1.15, "crayonCannon": 0.7, "starlightZapper": 1.3, "jackBlaster": 0.95, "plungerBow": 1.1, "popcornPopper": 1.2, "walloper": 0.7, "sizzler": 0.9, "skybolt": 0.85}
const PICKUP_NOTES := {"health": [523, 659, 784], "shield": [392, 587, 784, 1175], "turbo": [440, 554, 659, 880], "infinite": [659, 523, 659, 880], "power": [523, 784, 1047, 1568], "weapon": [330, 494], "ammo": [660, 880]}

var music: Music = null
var occlusion := Callable()
var hrtf := true
var ready_ok := false
var _vol := {"master": 0.8, "music": 0.5, "sfx": 0.9, "amb": 0.6}
var _paused := false
var _voices := 0
var _p2d: Array = []
var _p3d: Array = []
var _cache := {}
var _mutex := Mutex.new()
var _pending := {}
var _main_thread := 0
var _tasks: Array[int] = []  # worker tasks still to be joined
var _quit := false
var _zone_loops := {}
var _vent: AudioStreamPlayer = null
var _listener := Vector3.ZERO


static func _bus(name: String, send: String) -> int:
	var i := AudioServer.get_bus_index(name)
	if i < 0:
		AudioServer.add_bus()
		i = AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, name)
	AudioServer.set_bus_send(i, send)
	return i


func _init() -> void:
	name = "Audio"


## Safe to call repeatedly.
func init() -> void:
	if ready_ok:
		return
	ready_ok = true
	var master := AudioServer.get_bus_index("Master")
	if AudioServer.get_bus_effect_count(master) == 0:
		var comp := AudioEffectCompressor.new()
		comp.threshold = -14
		comp.ratio = 4
		comp.attack_us = 3000
		comp.release_ms = 200
		AudioServer.add_bus_effect(master, comp)
	var sfx := _bus("SFX", "Master")
	if AudioServer.get_bus_effect_count(sfx) == 0:
		# small-room reverb (the original convolved with a 0.9 s bedroom impulse)
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.25
		rv.damping = 0.5
		rv.spread = 0.8
		rv.predelay_msec = 11
		rv.wet = 0.18
		rv.dry = 1.0
		AudioServer.add_bus_effect(sfx, rv)
	var occ := _bus("SFXOcc", "SFX")
	if AudioServer.get_bus_effect_count(occ) == 0:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 900
		AudioServer.add_bus_effect(occ, lp)
		AudioServer.set_bus_volume_db(occ, linear_to_db(0.6))
	_bus("UI", "Master")
	_bus("Amb", "Master")
	_bus("Music", "Master")
	Synth.ensure_noise()
	_main_thread = OS.get_thread_caller_id()
	_apply_volumes()
	music = Music.new()
	add_child(music)
	music.set_intensity(0)
	_tasks.append(WorkerThreadPool.add_task(_prewarm, true, "audio prewarm"))


func set_volumes(master: float, mus: float, sfx: float, amb: float) -> void:
	_vol = {"master": master, "music": mus, "sfx": sfx, "amb": amb}
	_apply_volumes()


func _set_db(bus: String, lin: float) -> void:
	var i := AudioServer.get_bus_index(bus)
	if i >= 0:
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(0.0001, lin)))


func _apply_volumes() -> void:
	if not ready_ok:
		return
	_set_db("Master", _vol.master * 0.35 if _paused else _vol.master)
	_set_db("Music", _vol.music * 0.55)
	_set_db("SFX", _vol.sfx)
	_set_db("UI", _vol.sfx * 0.8)
	_set_db("Amb", _vol.amb * 0.9)


func set_paused(p: bool) -> void:
	_paused = p
	_apply_volumes()


func update_listener(cam: Camera3D) -> void:
	_listener = cam.global_position


# ------------------------------------------------------------------ plumbing
func _variants_for(key: String) -> int:
	return 4 if key.begins_with("gun:") else 3


func _count(key: String) -> int:
	_mutex.lock()
	var n: int = _cache.get(key, []).size()
	_mutex.unlock()
	return n


## Render one more variation of a recipe into the cache (safe on any thread).
func _render_into(key: String, builder: Callable) -> void:
	var w := Synth.to_wav(Synth.render(builder.call()))
	_mutex.lock()
	if not _cache.has(key):
		_cache[key] = []
	if _cache[key].size() < _variants_for(key):
		_cache[key].append(w)
	_mutex.unlock()


## Fill every variation of a recipe (worker threads only).
func _warm(key: String, builder: Callable) -> void:
	while not _quit and _count(key) < _variants_for(key):
		_render_into(key, builder)


## A cached render, or null the very first time (the render is queued on a worker thread so the game never stalls).
func _get_stream(key: String, builder: Callable) -> AudioStreamWAV:
	var n := _count(key)
	_mutex.lock()
	var queue_it := n < _variants_for(key) and not _pending.has(key)
	if queue_it:
		_pending[key] = true
	_mutex.unlock()
	if queue_it:
		# no deferred call back into this node: at quit it could run after the node is gone
		_tasks.append(WorkerThreadPool.add_task(func():
			_warm(key, builder)
			_mutex.lock()
			_pending.erase(key)
			_mutex.unlock()))
	if n == 0:
		return null
	_mutex.lock()
	var list: Array = _cache[key]
	var w: AudioStreamWAV = list[randi() % list.size()]
	_mutex.unlock()
	return w


func _player(positional: bool) -> Node:
	var pool := _p3d if positional else _p2d
	for p in pool:
		if not p.playing:
			return p
	var p: Node
	if positional:
		var p3 := AudioStreamPlayer3D.new()
		p3.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p3.max_distance = 120
		p3.panning_strength = 1.0
		p3.attenuation_filter_cutoff_hz = 20500
		p = p3
	else:
		p = AudioStreamPlayer.new()
	add_child(p)
	pool.append(p)
	p.finished.connect(func(): _voices = maxi(0, _voices - 1))
	return p


## Play one render of a recipe. pos = null for sounds "in your head".
func _play(key: String, builder: Callable, gain: float, pos = null, bus := "SFX", ref_dist := 4.0) -> Node:
	if OS.get_thread_caller_id() != _main_thread:
		_warm(key, builder)  # called by the warm-up thread: render only
		return null
	if not ready_ok or _voices >= MAX_VOICES:
		return null
	if pos != null and (pos as Vector3).distance_to(_listener) > 110:
		return null
	var stream := _get_stream(key, builder)
	if stream == null:
		return null
	var positional := pos != null
	var p := _player(positional)
	if positional and bus == "SFX" and occlusion.is_valid() and occlusion.call(pos):
		bus = "SFXOcc"
	p.stream = stream
	p.bus = bus
	p.volume_db = linear_to_db(maxf(0.0001, gain))
	if positional:
		(p as AudioStreamPlayer3D).unit_size = ref_dist
		(p as AudioStreamPlayer3D).global_position = pos
	p.play()
	_voices += 1
	return p


## Render every sound the game uses on a worker thread at startup, so playing never has to synthesize.
func _prewarm() -> void:
	var o := Vector3.ZERO
	for w in Cfg.WEAPON_ORDER:
		gunshot(w, o, true)
	for m in ["plastic", "wood", "fabric", "carpet", "metal", "cardboard", "glass"]:
		impact(m, o)
		footstep(m, o)
	for c in ["glass", "soft", "hard"]:
		break_piece(c, o)
	hitmarker(false, false)
	hitmarker(true, false)
	hitmarker(false, true)
	for k in range(1, 7):
		kill_confirm(k)
	player_hurt(false)
	player_hurt(true)
	eliminated(o)
	explosion(o)
	jump()
	land("wood", 1.0)
	slide()
	dash()
	spawn_pop(o)
	empty()
	weapon_switch()
	for p in ["out", "in", "charge", "shell", "spring", "vent", "pump", "open", "close"]:
		for w in Cfg.WEAPON_ORDER:
			reload_part(w, p)
	for c in Chars.CHARACTERS.values():
		hurt(c.voicePitch, o)
	shield_break(o)
	for k in ["health", "shield", "turbo", "infinite", "power", "weapon", "ammo"]:
		pickup(k)
	bubble_pop(o)
	zap(o)
	punch(true)
	punch(false)
	grapple(o, true)
	grapple(o, false)
	cloak(true)
	cloak(false)
	shield_up()
	jump_pad(o)
	zip_grab(o)
	sector_captured(true)
	sector_captured(false)
	spring_wind()
	bow_draw()
	ui_hover()
	ui_click()
	ui_back()
	countdown(true)
	countdown(false)
	fanfare(true)
	fanfare(false)
	announce()
	train_whistle(o)
	train_chug(o)
	clock_tick(o, true)
	clock_tick(o, false)
	wind_up(o)
	creak(o)
	bird(o)
	rumble(o)
	clatter(o)
	block_land(o)
	_warm("whistle", func(): return [_T("sine", 1800, 500, 0, 2.2, {"a": 0.2, "d": 8.0, "peak": 0.12, "s": 1.0})])


# ------------------------------------------------------------------ recipes (same layers as Audio.ts)
static func _T(type: String, f0: float, f1: float, t: float, dur: float, e: Dictionary, glide := "exp", detune := 0.0, lfo := {}) -> Dictionary:
	return Synth.tone(type, f0, f1, t, dur, e, glide, detune, lfo)


static func _N(kind: String, ft: String, f: float, q: float, t: float, e: Dictionary, fe := 0.0, rate := 1.0) -> Dictionary:
	return Synth.noise(kind, ft, f, q, t, e, fe, rate)


static func _E(a: float, d: float, peak := 1.0, s := -1.0, r := 0.0) -> Dictionary:
	return Synth.env(a, d, peak, s, r)


static func _C(t: float, f := 3200.0, vol := 0.5, dur := 0.012) -> Dictionary:
	return Synth.click(t, f, vol, dur)


static func _r_gunshot(w: String) -> Array:
	var o := []
	var p := U.rand(0.93, 1.08)
	var variant := randi() % 3
	match w:
		"plasti9":
			o.append(_N("white", "highpass", 1600 * p, 0.7, 0, _E(0.001, 0.05, 0.9)))
			o.append(_T("triangle", 980 * p, 210 * p, 0, 0.06, _E(0.001, 0.07, 0.7)))
			o.append(_T("sine", 160, 70, 0, 0.08, _E(0.002, 0.09, 0.6)))
			o.append(_C(0.035, 4200 + variant * 500, 0.35))
			o.append(_T("square", 2600 + variant * 300, 2300, 0.004, 0.02, _E(0.001, 0.02, 0.08)))
		"foamFury":
			o.append(_N("pink", "bandpass", 900 * p, 1.2, 0, _E(0.001, 0.06, 1.1)))
			o.append(_T("sine", 140 * p, 60, 0, 0.07, _E(0.002, 0.08, 0.9)))
			o.append(_T("triangle", 620 * p, 300, 0, 0.04, _E(0.001, 0.05, 0.35)))
			for i in 2 + variant:
				o.append(_C(0.02 + i * 0.013, 2400 + randf() * 2400, 0.25))
		"brickbreaker":
			o.append(_N("brown", "lowpass", 1100 * p, 0.8, 0, _E(0.001, 0.16, 1.6), 300))
			o.append(_N("white", "bandpass", 2400, 1, 0, _E(0.001, 0.04, 0.6)))
			o.append(_T("sine", 95 * p, 42, 0, 0.14, _E(0.002, 0.16, 1.2)))
			for i in 3 + variant:
				o.append(_C(0.03 + i * 0.018, 1800 + randf() * 1500, 0.3))
		"bubbleBlaster":
			o.append(_N("pink", "lowpass", 1400, 1, 0, _E(0.001, 0.12, 1.2), 400))
			o.append(_T("sine", 260 * p, 900 * p, 0, 0.08, _E(0.002, 0.1, 0.8)))
			o.append(_T("sine", 70, 45, 0, 0.15, _E(0.002, 0.18, 1.0)))
			for i in 6:
				var tt := 0.05 + randf() * 0.18
				var f := U.rand(900, 2600)
				o.append(_T("sine", f, f * 1.8, tt, 0.03, _E(0.001, 0.035, 0.18)))
		"thunderspring":
			o.append(_N("white", "highpass", 2500, 0.8, 0, _E(0.001, 0.05, 1.0)))
			o.append(_T("sine", 120, 50, 0, 0.2, _E(0.002, 0.22, 1.2)))
			# metallic twang: detuned partials with vibrato decay
			var base := 196 * p * (1 + variant * 0.03)
			for ma in [[1.0, 0.5], [2.01, 0.35], [3.03, 0.25], [4.2, 0.15], [5.4, 0.1]]:
				o.append(_T("sawtooth", base * ma[0] * 1.06, base * ma[0], 0, 0.6, _E(0.003, 0.9, ma[1] * 0.45), "exp", 0, {"f": 7.0, "g0": 8.0 * ma[0], "g1": 8.0 * ma[0], "t0": 0.0, "t1": 1.0}))
		"rapidRascal":
			o.append(_T("square", 140 * p, 90, 0, 0.035, _E(0.001, 0.04, 0.35)))
			o.append(_N("white", "bandpass", 1800 * p, 1.5, 0, _E(0.001, 0.03, 0.8)))
			o.append(_T("sine", 300 * p, 120, 0, 0.04, _E(0.001, 0.04, 0.5)))
			if variant == 0:
				o.append(_C(0.012, 5200, 0.2))
		"crayonCannon":
			o.append(_T("sine", 72 * p, 32, 0, 0.3, _E(0.003, 0.32, 1.6)))
			o.append(_N("brown", "lowpass", 600, 0.7, 0, _E(0.002, 0.25, 1.4), 150))
			o.append(_T("triangle", 420, 180, 0, 0.12, _E(0.002, 0.12, 0.4)))
			o.append(_T("sine", 900 * p, 1500 * p, 0.05, 0.12, _E(0.003, 0.12, 0.12)))
		"starlightZapper":
			o.append(_T("sawtooth", 1900 * p, 420 * p, 0, 0.09, _E(0.001, 0.1, 0.28)))
			o.append(_T("square", 950 * p, 210 * p, 0, 0.08, _E(0.001, 0.09, 0.12), "exp", 7))
			o.append(_T("sine", 2400 + variant * 200, 3200, 0.01, 0.03, _E(0.001, 0.04, 0.15)))
			o.append(_N("white", "highpass", 5000, 0.5, 0, _E(0.001, 0.025, 0.25)))
		"popcornPopper":
			o.append(_N("white", "bandpass", 2100 * p, 1.4, 0, _E(0.001, 0.05, 1.0), 900))
			o.append(_T("square", 520 * p, 190, 0, 0.05, _E(0.001, 0.06, 0.3)))
			o.append(_T("sine", 170 * p, 80, 0, 0.06, _E(0.001, 0.07, 0.6)))
			o.append(_C(0.012, 3600 + variant * 250, 0.4))
		"jackBlaster":
			o.append(_N("pink", "lowpass", 1600 * p, 0.8, 0, _E(0.001, 0.14, 1.5), 400))
			o.append(_T("sine", 110 * p, 45, 0, 0.12, _E(0.002, 0.14, 1.0)))
			o.append(_N("white", "bandpass", 2600 * p, 1.2, 0, _E(0.001, 0.04, 0.6)))
			o.append(_T("triangle", 520 * p, 520 * p, 0.05, 0.3, _E(0.005, 0.32, 0.16), "exp", 0, {"f": 18.0, "g0": 220.0, "g1": 8.0, "t0": 0.05, "t1": 0.4}))
			for i in 3:
				o.append(_C(0.12 + i * 0.05, 3000 + variant * 300, 0.25))
		"walloper":
			o.append(_N("brown", "lowpass", 900 * p, 0.7, 0, _E(0.001, 0.42, 2.2), 160))
			o.append(_N("white", "bandpass", 3200 * p, 0.9, 0, _E(0.001, 0.06, 1.1)))
			o.append(_T("sine", 78 * p, 30, 0, 0.32, _E(0.002, 0.38, 1.8)))
			o.append(_T("triangle", 420 * p, 120, 0, 0.09, _E(0.001, 0.1, 0.5)))
			o.append(_N("pink", "lowpass", 500, 0.6, 0.08, _E(0.02, 0.6, 0.45), 120))
			o.append(_C(0.3, 2400 + variant * 200, 0.3))
		"skybolt":
			o.append(_N("brown", "lowpass", 1250 * p, 0.8, 0, _E(0.001, 0.2, 1.6), 300))
			o.append(_N("white", "bandpass", 2600, 1, 0, _E(0.001, 0.045, 0.7)))
			o.append(_T("sine", 105 * p, 46, 0, 0.16, _E(0.002, 0.18, 1.2)))
			o.append(_N("pink", "lowpass", 650, 0.6, 0.04, _E(0.02, 0.5, 0.3), 130))
			for i in 3 + variant:
				o.append(_C(0.04 + i * 0.02, 1700 + randf() * 1600, 0.3))
		"sizzler":
			o.append(_N("brown", "lowpass", 1300 * p, 0.8, 0, _E(0.001, 0.22, 1.8), 280))
			o.append(_T("sine", 85 * p, 36, 0, 0.2, _E(0.002, 0.22, 1.5)))
			o.append(_N("white", "bandpass", 2800 * p, 1.0, 0, _E(0.001, 0.05, 0.9)))
			o.append(_N("pink", "bandpass", 650, 0.7, 0.02, _E(0.03, 0.4, 0.55), 2400))
			o.append(_C(0.14 + variant * 0.01, 2400, 0.4))
			o.append(_C(0.17 + variant * 0.01, 1700, 0.3))
		"plungerBow":
			o.append(_T("triangle", 190 * p, 140 * p, 0, 0.22, _E(0.001, 0.25, 0.5)))
			o.append(_T("sine", 380 * p, 300 * p, 0, 0.15, _E(0.001, 0.16, 0.25)))
			o.append(_N("white", "bandpass", 1400, 0.7, 0.01, _E(0.01, 0.18, 0.45), 600))
			o.append(_C(0, 2600, 0.5))
	return o


static func _r_impact(mat: String) -> Array:
	var o := []
	var p := U.rand(0.9, 1.12)
	match mat:
		"plastic":
			o.append(_C(0, 3800 * p, 0.8, 0.02))
			o.append(_T("triangle", 1500 * p, 900, 0, 0.03, _E(0.001, 0.035, 0.25)))
		"wood":
			o.append(_T("sine", 340 * p, 260, 0, 0.08, _E(0.001, 0.09, 0.7)))
			o.append(_N("pink", "bandpass", 900 * p, 2, 0, _E(0.001, 0.05, 0.5)))
		"fabric", "carpet":
			o.append(_N("brown", "lowpass", 500 * p, 0.7, 0, _E(0.003, 0.09, 0.7)))
		"metal":
			for f in [2500, 3720, 5100]:
				o.append(_T("sine", f * p, f * p * 0.995, 0, 0.4, _E(0.001, 0.45, 0.12)))
			o.append(_C(0, 6000, 0.5))
		"cardboard":
			o.append(_N("pink", "lowpass", 380 * p, 1, 0, _E(0.002, 0.1, 0.9)))
			o.append(_T("sine", 120 * p, 80, 0, 0.08, _E(0.002, 0.09, 0.5)))
		"glass":
			for f in [3100, 4650, 6900]:
				o.append(_T("sine", f * p, f * p, 0, 0.25, _E(0.001, 0.3, 0.1)))
	return o


## A breakable piece giving way: glass shatters, wood/cardboard cracks, walls crumble.
static func _r_break(cls: String) -> Array:
	var o := []
	var p := U.rand(0.9, 1.1)
	match cls:
		"glass":
			o.append(_N("white", "highpass", 3500 * p, 0.7, 0, _E(0.001, 0.12, 0.9)))
			for i in 7:
				var f := U.rand(2600, 7800) * p
				o.append(_T("sine", f, f * 0.99, U.rand(0.0, 0.25), 0.2, _E(0.001, U.rand(0.08, 0.2), 0.12)))
		"soft":
			o.append(_C(0, 2200 * p, 0.9, 0.015))
			o.append(_N("pink", "bandpass", 700 * p, 1.2, 0, _E(0.001, 0.18, 0.9)))
			o.append(_T("sine", 220 * p, 90, 0, 0.18, _E(0.002, 0.16, 0.7)))
			o.append(_N("pink", "bandpass", 1600 * p, 2, 0.05, _E(0.001, 0.08, 0.4)))
		"hard":
			o.append(_T("sine", 75 * p, 38, 0, 0.45, _E(0.003, 0.4, 1.0)))
			o.append(_N("brown", "lowpass", 900 * p, 0.8, 0, _E(0.004, 0.5, 1.0), 200))
			for i in 6:
				o.append(_N("pink", "bandpass", U.rand(800, 2400), 3, U.rand(0.05, 0.45), _E(0.001, 0.05, 0.35)))
	return o


static func _r_footstep(mat: String) -> Array:
	var o := []
	var p := U.rand(0.85, 1.15)
	match mat:
		"wood":
			o.append(_T("sine", 190 * p, 140, 0, 0.05, _E(0.002, 0.06, 0.6)))
			o.append(_N("pink", "bandpass", 700 * p, 1.5, 0, _E(0.002, 0.04, 0.35)))
		"plastic", "metal", "glass":
			o.append(_C(0, 2600 * p, 0.45, 0.018))
			o.append(_T("triangle", 700 * p, 500, 0, 0.03, _E(0.001, 0.03, 0.2)))
		"carpet", "fabric":
			o.append(_N("brown", "lowpass", 350 * p, 0.7, 0, _E(0.006, 0.07, 0.6)))
		"cardboard":
			o.append(_N("pink", "lowpass", 500 * p, 1, 0, _E(0.003, 0.06, 0.6)))
			o.append(_N("white", "bandpass", 3000, 2, 0.01, _E(0.002, 0.03, 0.15)))
	return o


static func _r_reload(w: String, part: String) -> Array:
	var o := []
	var pitch: float = RELOAD_PITCH.get(w, 1.0)
	match part:
		"out":
			o.append(_N("white", "bandpass", 1500 * pitch, 2, 0, _E(0.002, 0.06, 0.5)))
			o.append(_C(0.05, 2600 * pitch, 0.4))
		"in":
			o.append(_N("pink", "bandpass", 900 * pitch, 1.5, 0, _E(0.003, 0.05, 0.6)))
			o.append(_C(0.04, 3400 * pitch, 0.6))
			o.append(_T("sine", 300 * pitch, 180, 0.04, 0.05, _E(0.001, 0.06, 0.3)))
		"charge":
			o.append(_N("white", "bandpass", 2000 * pitch, 2, 0, _E(0.01, 0.09, 0.4), 3500 * pitch))
			o.append(_C(0.1, 3800 * pitch, 0.6))
			o.append(_T("triangle", 700 * pitch, 1200 * pitch, 0.1, 0.12, _E(0.002, 0.15, 0.12)))
		"drop":
			o.append(_N("pink", "lowpass", 700 * pitch, 1.0, 0, _E(0.002, 0.08, 0.6)))
			o.append(_C(0.0, 2100 * pitch, 0.45, 0.02))
			o.append(_C(0.07, 2900 * pitch, 0.25, 0.015))
			o.append(_T("sine", 220 * pitch, 140, 0, 0.06, _E(0.002, 0.07, 0.35)))
		"shell":
			o.append(_C(0, 2600, 0.5))
			o.append(_T("sine", 500, 1300, 0, 0.05, _E(0.002, 0.06, 0.25)))
			o.append(_T("sine", 1800, 2400, 0.06, 0.03, _E(0.001, 0.03, 0.1)))
		"pump":
			o.append(_N("pink", "bandpass", 1200, 1.3, 0, _E(0.005, 0.08, 0.6)))
			o.append(_C(0.09, 2200, 0.7))
			o.append(_N("pink", "bandpass", 1500, 1.3, 0.12, _E(0.005, 0.06, 0.5)))
		"spring":
			for i in 9:
				o.append(_C(i * 0.06, 1500 + i * 220, 0.4))
			o.append(_T("triangle", 200, 900, 0, 0.55, _E(0.02, 0.55, 0.1)))
			o.append(_C(0.6, 4200, 0.8))
		"vent":
			o.append(_N("white", "highpass", 3000, 0.7, 0, _E(0.02, 0.4, 0.25), 8000))
			o.append(_T("sine", 400, 1600, 0, 0.5, _E(0.02, 0.5, 0.15)))
		"open":
			o.append(_N("pink", "bandpass", 700, 2, 0, _E(0.005, 0.08, 0.5)))
			o.append(_C(0.07, 1500, 0.5))
		"close":
			o.append(_C(0, 1300, 0.7))
			o.append(_T("sine", 180, 120, 0, 0.06, _E(0.001, 0.07, 0.4)))
	return o


# ------------------------------------------------------------------ weapons
func gunshot(w: String, pos = null, local := false) -> void:
	_play("gun:" + w, func(): return _r_gunshot(w), 0.55 if local else 0.75, null if local else pos, "SFX", 5)


## Bow string creaking while it's drawn.
func bow_draw(local := true, pos = null) -> void:
	_play("bowdraw", func():
		var o := [_T("sawtooth", 70, 110, 0, 0.9, _E(0.1, 0.9, 0.05))]
		for i in 6:
			o.append(_C(i * 0.13 + randf() * 0.04, 900 + i * 120, 0.12, 0.02))
		return o, 0.3 if local else 0.2, null if local else pos)


# ------------------------------------------------------------------ abilities
func punch(hit: bool, pos = null) -> void:
	_play("punch:%s" % hit, func():
		var o := [_T("triangle", 300, 1100, 0, 0.08, _E(0.002, 0.08, 0.25)), _N("white", "bandpass", 1500, 1, 0, _E(0.005, 0.08, 0.35), 3500)]
		if hit:
			o.append(_T("sine", 150, 55, 0.06, 0.16, _E(0.002, 0.18, 1.2)))
			o.append(_N("pink", "lowpass", 900, 1, 0.06, _E(0.002, 0.12, 1.0)))
			o.append(_C(0.06, 1800, 0.7, 0.02))
		return o, 0.7 if hit else 0.45, pos)


func grapple(pos = null, hit := true) -> void:
	_play("grapple:%s" % hit, func():
		var o := [_N("white", "bandpass", 2400, 2, 0, _E(0.005, 0.25, 0.4), 800)]
		for i in 6:
			o.append(_C(i * 0.03, 2500 + i * 300, 0.25))
		if hit:
			o.append(_C(0.18, 1200, 0.9, 0.03))
		return o, 0.5, pos)


func cloak(on: bool, pos = null) -> void:
	_play("cloak:%s" % on, func():
		return [_T("sine", 1400.0 if on else 300.0, 300.0 if on else 1400.0, 0, 0.5, _E(0.01, 0.5, 0.2)),
			_N("white", "highpass", 4000, 0.7, 0, _E(0.05, 0.45, 0.2), 9000.0 if on else 2500.0)], 0.4, pos)


func shield_up(pos = null) -> void:
	_play("shieldup", func():
		var o := [_T("square", 220, 880, 0, 0.25, _E(0.005, 0.28, 0.08)), _T("sine", 440, 1320, 0, 0.3, _E(0.005, 0.32, 0.25))]
		for i in 4:
			o.append(_C(0.05 + i * 0.05, 4000 - i * 400, 0.2))
		return o, 0.5, pos)


## Jump pad: a springy "boing" with a click.
func jump_pad(pos: Vector3) -> void:
	_play("jumppad", func():
		return [_T("sine", 180, 620, 0, 0.32, _E(0.004, 0.34, 0.9), "exp", 0, {"f": 18.0, "g0": 60.0, "g1": 4.0, "t0": 0.0, "t1": 0.32}),
			_T("triangle", 90, 300, 0, 0.25, _E(0.003, 0.26, 0.5)), _C(0, 2600, 0.6), _C(0.02, 1800, 0.4)], 0.6, pos, "SFX", 6)


## Grabbing a zipline: a clack and a rising whir as the trolley gets going.
func zip_grab(pos: Vector3) -> void:
	_play("zipgrab", func():
		return [_C(0, 1500, 0.8, 0.02), _C(0.03, 2400, 0.4),
			_N("white", "bandpass", 1800, 3, 0.02, _E(0.08, 1.4, 0.35), 3600),
			_T("sawtooth", 140, 260, 0.02, 1.3, _E(0.1, 1.3, 0.18))], 0.5, pos, "SFX", 5)


func sector_captured(mine: bool) -> void:
	_play("sector:%s" % mine, func():
		var notes := [523, 659, 784, 1047] if mine else [440, 415, 392, 330]
		var o := []
		for i in notes.size():
			o.append(_T("triangle", notes[i], notes[i], i * 0.08, 0.16, _E(0.003, 0.22, 0.3)))
		return o, 0.45, null, "UI")


## Spring winding after a Thunderspring shot.
func spring_wind(pos = null, local := true) -> void:
	_play("springwind", func():
		var o := []
		for i in 7:
			o.append(_C(i * 0.055, 2200 + i * 180, 0.35))
		o.append(_T("triangle", 300, 700, 0, 0.4, _E(0.02, 0.4, 0.08)))
		return o, 0.4, null if local else pos)


func reload_part(w: String, part: String, local := true, pos = null) -> void:
	_play("reload:%s:%s" % [w, part], func(): return _r_reload(w, part), 0.5 if local else 0.4, null if local else pos, "SFX", 2.5)


## Spent brass (or a shotgun hull) bouncing on the floor a moment after a shot.
func casing(kind: String) -> void:
	_play("casing:" + kind, func():
		var o := []
		var t0 := U.rand(0.32, 0.45)
		if kind == "shell":
			o.append(_T("sine", 520, 380, t0, 0.05, _E(0.002, 0.06, 0.3)))
			o.append(_C(t0 + 0.08, 1500, 0.2, 0.02))
		else:
			var f := 5200.0 if kind == "pistol" else 4300.0
			for i in 3:
				var tt := t0 + i * U.rand(0.06, 0.1)
				o.append(_T("sine", f * U.rand(0.95, 1.08), f, tt, 0.06, _E(0.001, 0.07, 0.22 / (i + 1))))
				o.append(_T("sine", f * 1.52, f * 1.5, tt, 0.04, _E(0.001, 0.05, 0.1 / (i + 1))))
		return o, 0.22, null, "SFX", 2)


func empty(_local := true) -> void:
	_play("empty", func(): return [_C(0, 1800, 0.7, 0.02), _C(0.02, 1100, 0.4, 0.02)], 0.5)


func weapon_switch() -> void:
	_play("switch", func(): return [_N("pink", "bandpass", 1100, 1.5, 0, _E(0.01, 0.08, 0.5)), _C(0.12, 2800, 0.5)], 0.35)


# ------------------------------------------------------------------ impacts & bodies
func break_piece(cls: String, pos: Vector3) -> void:
	_play("break:" + cls, func(): return _r_break(cls), 0.9 if cls == "hard" else 0.7, pos, "SFX", 6)


func impact(mat: String, pos: Vector3, vol := 1.0) -> void:
	_play("impact:" + mat, func(): return _r_impact(mat), 0.5 * vol, pos, "SFX", 3)


func footstep(mat: String, pos = null, vol := 1.0) -> void:
	_play("step:" + mat, func(): return _r_footstep(mat), 0.28 * vol, pos, "SFX", 2.5)


func jump(pos = null) -> void:
	_play("jump", func(): return [_T("sine", 300, 700, 0, 0.1, _E(0.005, 0.1, 0.25)), _N("pink", "bandpass", 1200, 1, 0, _E(0.005, 0.06, 0.25))], 0.3, pos)


func land(mat: String, strength: float, pos = null) -> void:
	footstep(mat, pos, 1 + strength * 1.5)
	_play("land", func(): return [_T("sine", 120, 60, 0, 0.1, _E(0.003, 0.12, 0.7))], 0.25 * strength, pos)


func slide() -> void:
	_play("slide", func(): return [_N("pink", "bandpass", 800, 0.8, 0, _E(0.03, 0.7, 0.6), 300)], 0.35)


func dash(pos = null) -> void:
	_play("dash", func():
		var o := []
		for i in 5:
			o.append(_C(i * 0.03, 2000 + i * 400, 0.4))
		o.append(_N("white", "bandpass", 900, 1, 0.1, _E(0.02, 0.35, 0.6), 4000))
		o.append(_T("sine", 400, 1200, 0.1, 0.25, _E(0.01, 0.3, 0.2)))
		return o, 0.5, pos)


func hitmarker(head: bool, shield: bool) -> void:
	var k := "head" if head else ("shield" if shield else "body")
	_play("hit:" + k, func():
		if head:
			return [_T("sine", 1900, 1900, 0, 0.1, _E(0.001, 0.14, 0.6)), _T("sine", 2850, 2850, 0.01, 0.1, _E(0.001, 0.12, 0.3))]
		if shield:
			return [_T("triangle", 1300, 1600, 0, 0.05, _E(0.001, 0.06, 0.4))]
		return [_C(0, 3200, 0.9, 0.015), _T("triangle", 1100, 900, 0, 0.03, _E(0.001, 0.04, 0.3))], 0.42, null, "UI")


func kill_confirm(streak: int) -> void:
	var k := mini(streak - 1, 5)
	_play("kill:%d" % k, func():
		var base := 660 * pow(2, k / 12.0)
		var o := []
		var semis := [0, 4, 7, 12]
		for i in 4:
			var f := base * pow(2, semis[i] / 12.0)
			o.append(_T("triangle", f, f, i * 0.045, 0.15, _E(0.002, 0.2, 0.35)))
		o.append(_T("sine", 120, 60, 0, 0.1, _E(0.002, 0.12, 0.4)))
		return o, 0.5, null, "UI")


## Toy breaks apart: clatter + spring boing.
func eliminated(pos: Vector3) -> void:
	_play("elim", func():
		var o := []
		for i in 9:
			o.append(_C(randf() * 0.35, U.rand(1500, 5000), U.rand(0.3, 0.7), 0.02))
		o.append(_T("sine", 300, 300, 0.05, 0.6, _E(0.003, 0.6, 0.4), "exp", 0, {"f": 16.0, "g0": 140.0, "g1": 5.0, "t0": 0.0, "t1": 0.6}))
		o.append(_N("pink", "lowpass", 1500, 0.8, 0, _E(0.002, 0.2, 0.6)))
		return o, 0.8, pos, "SFX", 6)


func hurt(pitch: float, pos = null) -> void:
	_play("hurt:%.2f" % pitch, func():
		return [_T("sine", 1300 * pitch, 800 * pitch, 0, 0.14, _E(0.005, 0.15, 0.35), "exp", 0, {"f": 30.0, "g0": 60.0, "g1": 60.0, "t0": 0.0, "t1": 0.2})], 0.3, pos)


func player_hurt(shield: bool) -> void:
	_play("phurt:%s" % shield, func():
		if shield:
			return [_T("triangle", 900, 500, 0, 0.1, _E(0.002, 0.12, 0.4))]
		return [_T("sine", 180, 90, 0, 0.12, _E(0.002, 0.14, 0.7)), _N("pink", "lowpass", 900, 1, 0, _E(0.002, 0.08, 0.4))], 0.45, null, "UI")


func shield_break(pos = null) -> void:
	_play("shieldbreak", func():
		var o := []
		for f in [2200, 2900, 3700]:
			o.append(_T("sine", f, f * 0.6, 0, 0.3, _E(0.001, 0.3, 0.15)))
		o.append(_N("white", "highpass", 3000, 0.7, 0, _E(0.001, 0.2, 0.5)))
		return o, 0.5, pos)


func pickup(kind: String, pos = null, local := true) -> void:
	_play("pickup:" + kind, func():
		var o := []
		var notes: Array = PICKUP_NOTES.get(kind, [660, 880])
		for i in notes.size():
			o.append(_T("sine" if kind == "shield" else "triangle", notes[i], notes[i], i * 0.06, 0.12, _E(0.002, 0.18, 0.3)))
		return o, 0.45 if local else 0.3, null if local else pos, "UI" if local else "SFX")
	if kind == "weapon":
		reload_part("foamFury", "charge")


func spawn_pop(pos = null) -> void:
	_play("spawnpop", func():
		var o := [_T("sine", 300, 1200, 0, 0.15, _E(0.005, 0.18, 0.4))]
		for i in 4:
			o.append(_C(0.12 + i * 0.03, 3000 + i * 600, 0.3))
		return o, 0.4, pos)


func explosion(pos: Vector3) -> void:
	_play("explosion", func():
		var o := [_T("sine", 90, 30, 0, 0.5, _E(0.003, 0.55, 1.4)), _N("brown", "lowpass", 1200, 0.7, 0, _E(0.003, 0.5, 1.6), 120),
			_N("white", "bandpass", 2500, 1, 0, _E(0.002, 0.1, 0.6)), _T("sine", 600, 1400, 0.02, 0.08, _E(0.002, 0.1, 0.35))]
		for i in 10:
			o.append(_C(0.08 + randf() * 0.4, U.rand(3000, 7000), U.rand(0.1, 0.3), 0.01))
		return o, 1.1, pos, "SFX", 7)


## Falling whistle that follows a crayon projectile. Returns a handle with move(p) / stop().
func whistle(pos: Vector3):
	if not ready_ok:
		return null
	var p := _play("whistle", func():
		return [_T("sine", 1800, 500, 0, 2.2, {"a": 0.2, "d": 8.0, "peak": 0.12, "s": 1.0})], 1.0, pos)
	if p == null:
		return null
	return Whistle.new(p)


class Whistle:
	var p: AudioStreamPlayer3D
	var stopped := false

	func _init(player) -> void:
		p = player

	func move(pos: Vector3) -> void:
		if not stopped and is_instance_valid(p):
			p.global_position = pos

	func stop() -> void:
		if stopped or not is_instance_valid(p):
			return
		stopped = true
		var tw := p.create_tween()
		tw.tween_property(p, "volume_db", -60.0, 0.05)
		tw.tween_callback(p.stop)
		tw.tween_callback(func(): p.finished.emit())


func bubble_pop(pos: Vector3) -> void:
	_play("bubblepop", func():
		var f := U.rand(1200, 3000)
		return [_T("sine", f, f * 2, 0, 0.025, _E(0.001, 0.03, 0.5))], 0.18, pos, "SFX", 2)


func zap(pos: Vector3) -> void:
	_play("zap", func(): return [_T("square", 3000, 800, 0, 0.05, _E(0.001, 0.06, 0.15))], 0.25, pos, "SFX", 2)


# ------------------------------------------------------------------ UI
func ui_hover() -> void:
	_play("uihover", func(): return [_T("sine", 1400, 1600, 0, 0.03, _E(0.001, 0.04, 0.25))], 0.15, null, "UI")


func ui_click() -> void:
	_play("uiclick", func(): return [_C(0, 2400, 0.6), _T("triangle", 880, 1320, 0, 0.06, _E(0.002, 0.08, 0.3))], 0.3, null, "UI")


func ui_back() -> void:
	_play("uiback", func(): return [_T("triangle", 900, 500, 0, 0.08, _E(0.002, 0.1, 0.3))], 0.25, null, "UI")


func countdown(final: bool) -> void:
	_play("count:%s" % final, func():
		var f := 1320.0 if final else 880.0
		return [_T("square", f, f, 0, 0.2, _E(0.002, 0.4 if final else 0.15, 0.15))], 0.4, null, "UI")


func fanfare(win: bool) -> void:
	_play("fanfare:%s" % win, func():
		var seq := [523, 659, 784, 1047, 784, 1047] if win else [523, 494, 466, 440]
		var o := []
		for i in seq.size():
			o.append(_T("triangle", seq[i], seq[i], i * 0.14, 0.3, _E(0.005, 0.9 if i == seq.size() - 1 else 0.2, 0.35)))
			o.append(_T("sine", seq[i] / 2.0, seq[i] / 2.0, i * 0.14, 0.3, _E(0.005, 0.2, 0.2)))
		return o, 0.5, null, "UI")


func announce() -> void:
	_play("announce", func():
		var o := []
		var fs := [784, 988, 1175]
		for i in 3:
			o.append(_T("sine", fs[i], fs[i], i * 0.09, 0.2, _E(0.003, 0.25, 0.25)))
		return o, 0.4, null, "UI")


# ------------------------------------------------------------------ ambience one-shots
func train_whistle(pos: Vector3) -> void:
	_play("trainwhistle", func():
		var o := []
		for fd in [[740.0, 0.0], [880.0, 0.02], [1110.0, 0.01]]:
			o.append(_T("sawtooth", fd[0], fd[0] * 0.98, fd[1], 0.9, _E(0.05, 0.25, 0.07, 0.6, 0.5)))
		o.append(_N("white", "bandpass", 2000, 1, 0, _E(0.05, 0.9, 0.12)))
		return o, 0.35, pos, "Amb", 10)


func train_chug(pos: Vector3) -> void:
	_play("chug", func(): return [_N("white", "bandpass", 1200, 1.2, 0, _E(0.005, 0.08, 0.6))], 0.18, pos, "Amb", 8)


func clock_tick(pos: Vector3, tock: bool) -> void:
	_play("tick:%s" % tock, func(): return [_C(0, 2300.0 if tock else 2900.0, 0.7, 0.012)], 0.25, pos, "Amb", 8)


func wind_up(pos: Vector3) -> void:
	_play("windup", func():
		var o := []
		for i in 8:
			o.append(_C(i * 0.07, 3000 + (i % 2) * 400, 0.4, 0.01))
		return o, 0.2, pos, "Amb", 6)


func creak(pos: Vector3) -> void:
	_play("creak", func():
		return [_N("pink", "bandpass", 380, 14, 0, _E(0.15, 0.8, 1.2), 620, 0.5), _T("sawtooth", 70, 95, 0, 0.9, _E(0.1, 0.8, 0.04), "lin")], 0.2, pos, "Amb", 8)


func bird(pos: Vector3) -> void:
	_play("bird", func():
		var o := []
		for i in 3:
			var f := U.rand(2200, 3200)
			o.append(_T("sine", f, f * 1.3, i * 0.12, 0.06, _E(0.005, 0.07, 0.3)))
		return o, 0.12, pos, "Amb", 6)


func rumble(pos: Vector3) -> void:
	_play("rumble", func(): return [_N("brown", "lowpass", 160, 0.7, 0, _E(0.4, 1.8, 1))], 0.4, pos, "Amb", 8)


func clatter(pos: Vector3) -> void:
	_play("clatter", func():
		var o := []
		for i in 5:
			o.append(_C(randf() * 0.3, U.rand(2000, 4500), 0.5))
		return o, 0.25, pos, "Amb", 6)


func block_land(pos: Vector3) -> void:
	_play("blockland", func(): return [_T("sine", 160, 90, 0, 0.15, _E(0.002, 0.18, 1)), _N("pink", "bandpass", 700, 1.5, 0, _E(0.002, 0.1, 0.7))], 0.7, pos, "SFX", 6)


## Continuous positional motor hum (rc cars). Returns a handle with move(p, speed) / stop().
func motor_loop(pos: Vector3):
	if not ready_ok:
		return null
	var key := "motor"
	_mutex.lock()
	var have: bool = _cache.has(key)
	_mutex.unlock()
	if not have:
		var o := [_T("sawtooth", 62, 62, 0, 2, {"a": 0.001, "d": 2.0, "peak": 1.0, "s": 1.0}), _T("square", 124.5, 124.5, 0, 2, {"a": 0.001, "d": 2.0, "peak": 0.3, "s": 1.0})]
		var raw := Synth.render(o, 0)
		# lowpass 700 Hz over the sum, then x0.05
		var c := Synth._coeffs("lowpass", 700, 0)
		var x1 := 0.0
		var x2 := 0.0
		var y1 := 0.0
		var y2 := 0.0
		for i in raw.size():
			var xin := raw[i]
			var y: float = c[0] * xin + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
			x2 = x1
			x1 = xin
			y2 = y1
			y1 = y
			raw[i] = y * 0.05
		_cache[key] = [Synth.to_wav(Synth.make_loopable(raw, 0.1), true)]
	var p := AudioStreamPlayer3D.new()
	p.stream = _cache[key][0]
	p.bus = "Amb"
	p.unit_size = 3
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.max_distance = 120
	add_child(p)
	p.global_position = pos
	p.play()
	return Motor.new(p)


class Motor:
	var p: AudioStreamPlayer3D

	func _init(player) -> void:
		p = player

	func move(pos: Vector3, speed: float) -> void:
		if is_instance_valid(p):
			p.global_position = pos
			p.pitch_scale = maxf(0.05, (50 + speed * 4) / 62.0)

	func stop() -> void:
		if is_instance_valid(p):
			p.queue_free()


func _noise_loop(kind: String, ftype: String, freq: float, q: float, seconds := 6.0) -> AudioStreamWAV:
	var key := "loop:%s:%s:%d" % [kind, ftype, int(freq)]
	if _cache.has(key):
		return _cache[key][0]
	var op := Synth.noise(kind, ftype, freq, q, 0, {"a": 0.001, "d": seconds, "peak": 1.0, "s": 1.0})
	op.offset = 0.0
	var raw := Synth.render([op], 0)
	var w := Synth.to_wav(Synth.make_loopable(raw.slice(int(0.05 * Synth.SR)), 0.3), true)
	_cache[key] = [w]
	return w


## Continuous room tone + per-zone loops, crossfaded by zone.
func start_ambience() -> void:
	if not ready_ok or _vent:
		return
	_vent = AudioStreamPlayer.new()
	_vent.stream = _noise_loop("brown", "lowpass", 380, 0)
	_vent.bus = "Amb"
	_vent.volume_db = linear_to_db(0.16)
	add_child(_vent)
	_vent.play()
	for z in ZONE_LOOPS:
		var p := AudioStreamPlayer.new()
		p.stream = _noise_loop(z[1], z[2], z[3], 2.0 if z[2] == "bandpass" else 0.7)
		p.bus = "Amb"
		p.pitch_scale = U.rand(0.9, 1.1)
		p.volume_db = -80
		add_child(p)
		p.play()
		_zone_loops[z[0]] = {"p": p, "target": z[4], "cur": 0.0, "want": 0.0}


func set_zone(z: String) -> void:
	for zone in _zone_loops:
		var l: Dictionary = _zone_loops[zone]
		l.want = l.target if zone == z else 0.0


func stop_ambience() -> void:
	for l in _zone_loops.values():
		(l.p as Node).queue_free()
	_zone_loops.clear()
	if _vent:
		_vent.queue_free()
	_vent = null


## Stop the synth workers before this node (and its cache/mutex) goes away.
func _exit_tree() -> void:
	_quit = true
	for id in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


func _process(dt: float) -> void:
	# join finished worker tasks
	var i := 0
	while i < _tasks.size():
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)
		else:
			i += 1
	# zone loop crossfades (setTargetAtTime with a 0.8 s time constant)
	var k := 1 - exp(-dt / 0.8)
	for l in _zone_loops.values():
		l.cur += (l.want - l.cur) * k
		(l.p as AudioStreamPlayer).volume_db = linear_to_db(maxf(0.0001, l.cur))


func random_creak_spot() -> Vector3:
	return Vector3(U.rand(-30, 30), 0, U.rand(-34, 34))

class_name Music
extends Node
## Small procedural music engine (port of src/audio/Music.ts): a playful toy-box groove (plucks, bass, toy
## drums, bells) that layers up as the match gets intense. Notes are pre-rendered with the same oscillator /
## filter / envelope shapes and mixed sample-accurately into an AudioStreamGenerator.

const LAYERS := ["pluck", "bass", "drums", "bells", "arp", "hats16"]
const PROG_A := [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]]  # C Am F G
const PROG_B := [[53, 57, 60], [55, 59, 62], [52, 55, 59], [57, 60, 64]]  # F G Em Am
const SCALE := [0, 2, 4, 7, 9]  # pentatonic
const MIX := {
	"pluck": [0.5, 0.45, 0.45, 0.45],
	"bass": [0.0, 0.55, 0.6, 0.65],
	"drums": [0.0, 0.35, 0.55, 0.65],
	"bells": [0.3, 0.22, 0.3, 0.35],
	"arp": [0.0, 0.0, 0.18, 0.26],
	"hats16": [0.0, 0.0, 0.0, 0.22],
}
const SR := Synth.SR

var intensity := 0
var _gain := {}
var _target := {}
var _step := 0
var _next := 0.0  # sample time of the next 16th
var _clock := 0  # samples written so far
var _tempo := 108.0
var _target_tempo := 108.0
var _melody: Array = []
var _playing := false
var _voices: Array = []  # [buffer, start sample, layer]
var _cache := {}
var _noise := PackedFloat32Array()
var _player := AudioStreamPlayer.new()
var _playback: AudioStreamGeneratorPlayback


static func midi(n: float) -> float:
	return 440.0 * pow(2.0, (n - 69) / 12.0)


func _init() -> void:
	name = "Music"
	for l in LAYERS:
		_gain[l] = 0.0
		_target[l] = 0.0
	var r := U.seeded(31)
	_noise.resize(SR)
	for i in SR:
		_noise[i] = r.next() * 2 - 1
	_make_melody(1)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = SR
	gen.buffer_length = 0.3
	_player.stream = gen
	_player.bus = "Music"
	add_child(_player)


func _make_melody(seed: int) -> void:
	var r := U.seeded(seed * 97 + 13)
	_melody = []
	var rhythm_a := []
	var rhythm_b := []
	for i in 8:
		rhythm_a.append(r.next() < 0.62)
	for i in 8:
		rhythm_b.append(r.next() < 0.5)
	for bar in 8:
		var rhythm: Array = rhythm_a if bar % 2 == 0 else rhythm_b
		var notes := []
		var deg := floori(r.next() * 5)
		for i in 8:
			if not rhythm[i]:
				notes.append(-1)
				continue
			deg = clampi(deg + floori(r.next() * 3) - 1, 0, 9)
			notes.append(72 + SCALE[deg % 5] + (deg / 5) * 12)
		_melody.append(notes)


## 0 = menu, 1 = match, 2 = late match, 3 = final moments
func set_intensity(level: int) -> void:
	intensity = level
	for l in LAYERS:
		_target[l] = MIX[l][level]
	_target_tempo = [96.0, 112.0, 120.0, 128.0][level]


func start() -> void:
	if _playing:
		return
	_playing = true
	_player.play()
	_playback = _player.get_stream_playback()
	_next = _clock + 0.1 * SR


func stop() -> void:
	_playing = false
	for l in LAYERS:
		_target[l] = 0.0


func new_song() -> void:
	_make_melody(randi() % 1000)
	_step = 0


func _on(l: String) -> bool:
	return _target[l] > 0.01 or _gain[l] > 0.01


func _process(dt: float) -> void:
	Prof.begin("music")
	_mix(dt)
	Prof.end("music")


func _mix(dt: float) -> void:
	if _playback == null:
		return
	# tempo glides toward the target for smooth intensity changes (0.02 per 25 ms tick)
	_tempo += (_target_tempo - _tempo) * (1 - pow(0.98, dt / 0.025))
	var n := _playback.get_frames_available()
	if n <= 0:
		return
	# schedule everything that starts inside this chunk (plus a little lookahead)
	if _playing:
		while _next < _clock + n + 0.12 * SR:
			_play_step(_step, int(_next))
			_next += 60.0 / _tempo / 4.0 * SR
			_step = (_step + 1) % (16 * 16)
	# layer gains glide like setTargetAtTime(…, 0.8)
	var k := 1 - exp(-float(n) / SR / 0.8)
	for l in LAYERS:
		_gain[l] += (_target[l] - _gain[l]) * k
	var mix := PackedFloat32Array()
	mix.resize(n)
	var keep := []
	for v in _voices:
		var buf: PackedFloat32Array = v[0]
		var start: int = v[1]
		var g: float = _gain[v[2]]
		var from := maxi(0, start - _clock)
		var to := mini(n, start + buf.size() - _clock)
		if g > 0.0001:
			for i in range(from, to):
				mix[i] += buf[i + _clock - start] * g
		if start + buf.size() > _clock + n:
			keep.append(v)
	_voices = keep
	var frames := PackedVector2Array()
	frames.resize(n)
	for i in n:
		var s := clampf(mix[i], -1, 1)
		frames[i] = Vector2(s, s)
	_playback.push_buffer(frames)
	_clock += n


func _add(buf: PackedFloat32Array, at: int, layer: String) -> void:
	_voices.append([buf, at, layer])


func _play_step(step: int, t: int) -> void:
	var bar := step / 16
	var s := step % 16
	var prog: Array = PROG_A if bar % 8 < 4 else PROG_B
	var chord: Array = prog[bar % 4]
	var sixteenth := 60.0 / _tempo / 4.0
	# plucked chord arpeggio on 8ths
	if s % 2 == 0 and _on("pluck"):
		var nn: int = chord[(s / 2) % 3] + (12 if s % 8 == 6 else 0)
		_add(_pluck(nn, 0.25, 0.22), t, "pluck")
	# bass: bouncy root/fifth
	if s in [0, 6, 8, 14] and _on("bass"):
		var root: int = chord[0] - 24
		var nn := root + 7 if s == 6 or s == 14 else root
		_add(_bass(nn, sixteenth * (3.5 if s == 0 or s == 8 else 1.6)), t, "bass")
	# drums
	if _on("drums"):
		if s == 0 or s == 8 or (s == 10 and bar % 2 == 1):
			_add(_kick(), t, "drums")
		if s == 4 or s == 12:
			_add(_snare(), t, "drums")
		if s % 2 == 0:
			_add(_hat(0.5 if s % 4 == 2 else 0.25), t, "drums")
	if s % 2 == 1 and _on("hats16"):
		_add(_hat(0.25), t, "hats16")
	# bells melody on 8ths
	if s % 2 == 0 and _on("bells"):
		var nn: int = _melody[bar % 8][s / 2]
		if nn > 0:
			_add(_bell(nn), t, "bells")
	# fast arp (late match)
	if _on("arp"):
		_add(_pluck(chord[s % 3] + 24, 0.12, 0.12), t, "arp")


# ---------------------------------------------------------------- note renders (cached)
static func _ramp_env(x: float, a: float, peak: float, end: float) -> float:
	if x < a:
		return 0.0001 * pow(peak / 0.0001, x / a)
	if x < end:
		return peak * pow(0.0001 / peak, (x - a) / (end - a))
	return 0.0001


func _pluck(note: int, dur: float, vol: float) -> PackedFloat32Array:
	var key := "p%d:%.2f:%.2f" % [note, dur, vol]
	if _cache.has(key):
		return _cache[key]
	var f := midi(note)
	var n := int((dur + 0.02) * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var c := []
	for i in n:
		var x := float(i) / SR
		if i % 16 == 0:
			c = Synth._coeffs("lowpass", f * 6 * pow(1.5 / 6.0, minf(1, x / dur)), 1)
		phase = fmod(phase + f / SR, 1.0)
		var xin := 1.0 - 4.0 * absf(phase - 0.5)
		var y: float = c[0] * xin + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xin
		y2 = y1
		y1 = y
		out[i] = y * _ramp_env(x, 0.004, vol, dur)
	_cache[key] = out
	return out


func _bass(note: int, dur: float) -> PackedFloat32Array:
	var key := "b%d:%.2f" % [note, dur]
	if _cache.has(key):
		return _cache[key]
	var f := midi(note)
	var n := int((dur + 0.02) * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var p1 := 0.0
	var p2 := 0.0
	for i in n:
		var x := float(i) / SR
		p1 = fmod(p1 + f / SR, 1.0)
		p2 = fmod(p2 + 2 * f / SR, 1.0)
		out[i] = (sin(TAU * p1) + (1.0 - 4.0 * absf(p2 - 0.5)) * 0.15) * _ramp_env(x, 0.01, 0.5, dur)
	_cache[key] = out
	return out


func _kick() -> PackedFloat32Array:
	if _cache.has("kick"):
		return _cache.kick
	var n := int(0.2 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var x := float(i) / SR
		var f := 140.0 * pow(45.0 / 140.0, minf(1, x / 0.12))
		ph = fmod(ph + f / SR, 1.0)
		out[i] = sin(TAU * ph) * (0.9 * pow(0.0001 / 0.9, minf(1, x / 0.18)))
	_cache.kick = out
	return out


func _snare() -> PackedFloat32Array:
	var key := "snare%d" % (randi() % 3)
	if _cache.has(key):
		return _cache[key]
	var n := int(0.16 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var c := Synth._coeffs("bandpass", 1800, 0.8)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var off := randi() % (SR / 2)
	var ph := 0.0
	for i in n:
		var x := float(i) / SR
		var xin := _noise[(off + i) % _noise.size()]
		var y: float = c[0] * xin + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xin
		y2 = y1
		y1 = y
		var v := y * 0.45 * pow(0.0001 / 0.45, minf(1, x / 0.14))
		if x < 0.1:
			var f := 200.0 * pow(120.0 / 200.0, minf(1, x / 0.06))
			ph = fmod(ph + f / SR, 1.0)
			v += (1.0 - 4.0 * absf(ph - 0.5)) * 0.3 * pow(0.0001 / 0.3, minf(1, x / 0.08))
		out[i] = v
	_cache[key] = out
	return out


func _hat(vol: float) -> PackedFloat32Array:
	var key := "hat%.2f:%d" % [vol, randi() % 3]
	if _cache.has(key):
		return _cache[key]
	var n := int(0.05 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var c := Synth._coeffs("highpass", 7000, 1)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var off := randi() % (SR / 2)
	var peak := vol * 0.35
	for i in n:
		var x := float(i) / SR
		var xin := _noise[(off + i) % _noise.size()]
		var y: float = c[0] * xin + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xin
		y2 = y1
		y1 = y
		out[i] = y * peak * pow(0.0001 / peak, minf(1, x / 0.04))
	_cache[key] = out
	return out


func _bell(note: int) -> PackedFloat32Array:
	var key := "bell%d" % note
	if _cache.has(key):
		return _cache[key]
	var f := midi(note)
	var n := int(0.75 * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	var parts := [[1.0, 1.0], [2.76, 0.25], [5.4, 0.08]]
	for i in n:
		var x := float(i) / SR
		var s := 0.0
		for p in parts:
			if f * p[0] < SR * 0.49:
				s += sin(TAU * f * p[0] * x) * p[1]
		out[i] = s * _ramp_env(x, 0.005, 0.25, 0.7)
	_cache[key] = out
	return out

class_name Synth
## Offline version of the Web Audio graph the original game built for every sound (src/audio/Audio.ts):
## oscillators with exponential/linear glides and LFO vibrato, filtered noise (white/pink/brown through
## RBJ biquads, with the Web Audio Q conventions) and exponential envelopes. A recipe is a list of layer ops;
## render() mixes them into a mono float buffer that to_wav() turns into an AudioStreamWAV.
##
## op "tone":  {type, f0, f1, t, dur, env, glide ("exp"|"lin"), detune (cents), lfo: {f, g0, g1, t0, t1}}
## op "noise": {kind, ftype, freq, q, t, env, freq_end, rate}
## env: {a, d, s, r, peak}

const SR := 24000

static var white := PackedFloat32Array()
static var pink := PackedFloat32Array()
static var brown := PackedFloat32Array()


## Seeded noise buffers (same generators as the original's makeNoise).
static func ensure_noise() -> void:
	if white.size():
		return
	white = _make_noise("white", 2)
	pink = _make_noise("pink", 3)
	brown = _make_noise("brown", 4)


static func _make_noise(kind: String, seconds: float) -> PackedFloat32Array:
	var n := int(SR * seconds)
	var d := PackedFloat32Array()
	d.resize(n)
	var r := U.seeded(kind.length() * 1000 + int(seconds))
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var last := 0.0
	for i in n:
		var w := r.next() * 2 - 1
		if kind == "white":
			d[i] = w
		elif kind == "pink":
			b0 = 0.997 * b0 + w * 0.029591
			b1 = 0.985 * b1 + w * 0.032534
			b2 = 0.95 * b2 + w * 0.048056
			d[i] = (b0 + b1 + b2 + w * 0.05) * 2.2
		else:
			last = (last + 0.02 * w) / 1.02
			d[i] = last * 3.5
	return d


static func env_end(e: Dictionary) -> float:
	return e.a + e.d + e.get("r", 0.0)


## Envelope value x seconds after the layer started (Web Audio exponential ramps).
static func env_at(e: Dictionary, x: float) -> float:
	var peak: float = e.get("peak", 1.0)
	var a := maxf(0.001, e.a)
	if x <= 0:
		return 0.0001
	if x < a:
		return 0.0001 * pow(peak / 0.0001, x / a)
	var sv := maxf(0.0001, peak * e.get("s", 0.0001))
	var d: float = e.d
	if x < e.a + d:
		return peak * pow(sv / peak, (x - e.a) / maxf(1e-6, d))
	if e.has("r") and e.r > 0:
		var rx: float = x - e.a - d
		if rx < e.r:
			return sv * pow(0.0001 / sv, rx / e.r)
		return 0.0001
	return sv


static func op_end(op: Dictionary) -> float:
	return op.t + env_end(op.env) + 0.05


static func render(ops: Array, extra := 0.05) -> PackedFloat32Array:
	ensure_noise()
	var length := 0.0
	for op in ops:
		length = maxf(length, op_end(op))
	var n := int((length + extra) * SR)
	var out := PackedFloat32Array()
	out.resize(n)
	for op in ops:
		if op.op == "tone":
			_tone(out, op)
		else:
			_noise(out, op)
	return out


static func _tone(out: PackedFloat32Array, op: Dictionary) -> void:
	var t0 := int(op.t * SR)
	var stop := int(op_end(op) * SR)
	var f0 := maxf(1.0, op.f0)
	var f1 := maxf(1.0, op.f1)
	var dur := maxf(1e-4, op.dur)
	var exp_glide: bool = op.get("glide", "exp") == "exp"
	var det := pow(2.0, op.get("detune", 0.0) / 1200.0)
	var lfo: Dictionary = op.get("lfo", {})
	var has_lfo := not lfo.is_empty()
	var typ: String = op.type
	var e: Dictionary = op.env
	var phase := 0.0
	var inv_sr := 1.0 / SR
	var n := out.size()
	for i in range(maxi(0, t0), mini(stop, n)):
		var x := (i - t0) * inv_sr
		var k := minf(1.0, x / dur)
		var f := (f0 * pow(f1 / f0, k) if exp_glide else f0 + (f1 - f0) * k) * det
		if has_lfo:
			var lx: float = x + op.t
			var g: float = lfo.g0
			if lfo.g1 != lfo.g0:
				var lk := clampf((lx - lfo.t0) / maxf(1e-4, lfo.t1 - lfo.t0), 0, 1)
				g = lfo.g0 * pow(lfo.g1 / lfo.g0, lk)
			if lx >= lfo.t0 and lx <= lfo.t1:
				f += g * sin(TAU * lfo.f * (lx - lfo.t0))
		var dt := f * inv_sr
		phase += dt
		phase -= floorf(phase)
		var s := 0.0
		match typ:
			"sine":
				s = sin(TAU * phase)
			"triangle":
				s = 1.0 - 4.0 * absf(phase - 0.5)
			"square":
				s = (1.0 if phase < 0.5 else -1.0) + _blep(phase, dt) - _blep(fmod(phase + 0.5, 1.0), dt)
			_:
				s = 2.0 * phase - 1.0 - _blep(phase, dt)
		out[i] += s * env_at(e, x)


## PolyBLEP correction (keeps square/saw from aliasing badly, like Web Audio's band-limited oscillators).
static func _blep(t: float, dt: float) -> float:
	if dt <= 0:
		return 0.0
	if t < dt:
		var x := t / dt
		return x + x - x * x - 1.0
	if t > 1.0 - dt:
		var x := (t - 1.0) / dt
		return x * x + x + x + 1.0
	return 0.0


static func _coeffs(ftype: String, freq: float, q: float) -> Array:
	var f := clampf(freq, 10.0, SR * 0.49)
	var w0 := TAU * f / SR
	var cw := cos(w0)
	var sw := sin(w0)
	var b0: float
	var b1: float
	var b2: float
	var alpha: float
	if ftype == "bandpass":
		alpha = sw / (2.0 * maxf(1e-4, q))
		b0 = alpha
		b1 = 0.0
		b2 = -alpha
	else:
		# Web Audio: lowpass/highpass Q is in dB
		alpha = sw / (2.0 * pow(10.0, q / 20.0))
		if ftype == "lowpass":
			b0 = (1 - cw) / 2
			b1 = 1 - cw
			b2 = (1 - cw) / 2
		else:
			b0 = (1 + cw) / 2
			b1 = -(1 + cw)
			b2 = (1 + cw) / 2
	var a0 := 1 + alpha
	return [b0 / a0, b1 / a0, b2 / a0, -2 * cw / a0, (1 - alpha) / a0]


static func _noise(out: PackedFloat32Array, op: Dictionary) -> void:
	var buf: PackedFloat32Array = white if op.kind == "white" else (pink if op.kind == "pink" else brown)
	var t0 := int(op.t * SR)
	var stop := int(op_end(op) * SR)
	var e: Dictionary = op.env
	var rate: float = op.get("rate", 1.0)
	var pos: float = op.get("offset", randf() * 1.2) * SR
	var freq: float = op.freq
	var fe: float = op.get("freq_end", 0.0)
	var sweep_t: float = e.a + e.d
	var c := _coeffs(op.ftype, freq, op.q)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var inv_sr := 1.0 / SR
	var n := out.size()
	var bl := buf.size()
	for i in range(maxi(0, t0), mini(stop, n)):
		var x := (i - t0) * inv_sr
		if fe > 0 and (i - t0) % 16 == 0:
			c = _coeffs(op.ftype, freq * pow(fe / freq, minf(1.0, x / maxf(1e-4, sweep_t))), op.q)
		var xi := int(pos) % bl
		var xin := buf[xi]
		pos += rate
		var y: float = c[0] * xin + c[1] * x1 + c[2] * x2 - c[3] * y1 - c[4] * y2
		x2 = x1
		x1 = xin
		y2 = y1
		y1 = y
		out[i] += y * env_at(e, x)


static func to_wav(data: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = data.size()
	return w


## Make a buffer loop without a click: crossfade its last `fade` seconds into the start.
static func make_loopable(d: PackedFloat32Array, fade := 0.2) -> PackedFloat32Array:
	var f := int(fade * SR)
	var n := d.size() - f
	var out := d.slice(0, n)
	for i in f:
		var k := float(i) / f
		out[i] = d[i] * k + d[n + i] * (1.0 - k)
	return out


# ---------------------------------------------------------------- recipe helpers
static func env(a: float, d: float, peak := 1.0, s := -1.0, r := 0.0) -> Dictionary:
	var e := {"a": a, "d": d, "peak": peak}
	if s >= 0:
		e.s = s
	if r > 0:
		e.r = r
	return e


static func tone(type: String, f0: float, f1: float, t: float, dur: float, e: Dictionary, glide := "exp", detune := 0.0, lfo := {}) -> Dictionary:
	return {"op": "tone", "type": type, "f0": f0, "f1": f1, "t": t, "dur": dur, "env": e, "glide": glide, "detune": detune, "lfo": lfo}


static func noise(kind: String, ftype: String, freq: float, q: float, t: float, e: Dictionary, freq_end := 0.0, rate := 1.0) -> Dictionary:
	return {"op": "noise", "kind": kind, "ftype": ftype, "freq": freq, "q": q, "t": t, "env": e, "freq_end": freq_end, "rate": rate, "offset": randf() * 1.2}


## A short plastic click (used everywhere).
static func click(t: float, freq := 3200.0, vol := 0.5, dur := 0.012) -> Dictionary:
	return noise("white", "bandpass", freq, 3, t, env(0.001, dur, vol))

import * as THREE from 'three';
import type { SurfaceMat } from '../physics/Physics';
import type { WeaponId } from '../weapons/weaponConfig';
import type { PickupKind } from '../match/Pickups';
import { rand, pick, seeded } from '../core/math';
import { Music } from './Music';

/**
 * Everything you hear is synthesized live with the Web Audio API (no audio files).
 * Each gun has several randomized layers so no two shots sound identical.
 */

type Env = { a: number; d: number; s?: number; r?: number; peak?: number };
export type ZoneAmb = 'bed' | 'desk' | 'closet' | 'garage' | 'dino' | 'brick' | 'rug';

interface Voice {
  out: GainNode;
  nodes: AudioNode[];
}

export class AudioEngine {
  ctx: AudioContext | null = null;
  master!: GainNode;
  sfx!: GainNode;
  ui!: GainNode;
  amb!: GainNode;
  musicBus!: GainNode;
  reverb!: ConvolverNode;
  reverbSend!: GainNode;
  music: Music | null = null;
  private white!: AudioBuffer;
  private brown!: AudioBuffer;
  private pink!: AudioBuffer;
  private voices = 0;
  private maxVoices = 56;
  hrtf = true;
  private listenerPos = new THREE.Vector3();
  occlusion: ((p: THREE.Vector3) => boolean) | null = null;
  private vol = { master: 0.8, music: 0.5, sfx: 0.9, amb: 0.6 };
  private zoneLoops = new Map<ZoneAmb, { gain: GainNode; src: AudioBufferSourceNode }>();
  private ventilation: GainNode | null = null;
  private ambTimers: number[] = [];
  private paused = false;

  /** Must be called from a user gesture. Safe to call repeatedly. */
  init() {
    if (this.ctx) {
      if (this.ctx.state === 'suspended') this.ctx.resume();
      return;
    }
    try {
      const AC: typeof AudioContext = window.AudioContext || (window as any).webkitAudioContext;
      this.ctx = new AC({ latencyHint: 'interactive' });
    } catch {
      this.ctx = null;
      return;
    }
    const c = this.ctx;
    const comp = c.createDynamicsCompressor();
    comp.threshold.value = -14;
    comp.knee.value = 10;
    comp.ratio.value = 4;
    comp.attack.value = 0.003;
    comp.release.value = 0.2;
    this.master = c.createGain();
    this.master.connect(comp).connect(c.destination);
    this.sfx = c.createGain();
    this.ui = c.createGain();
    this.amb = c.createGain();
    this.musicBus = c.createGain();
    this.sfx.connect(this.master);
    this.ui.connect(this.master);
    this.amb.connect(this.master);
    this.musicBus.connect(this.master);
    this.reverb = c.createConvolver();
    this.reverb.buffer = this.makeImpulse(0.9, 2.6);
    this.reverbSend = c.createGain();
    this.reverbSend.gain.value = 0.22;
    this.reverbSend.connect(this.reverb).connect(this.sfx);
    this.white = this.makeNoise('white', 2);
    this.pink = this.makeNoise('pink', 3);
    this.brown = this.makeNoise('brown', 4);
    this.applyVolumes();
    this.music = new Music(c, this.musicBus);
    this.music.setIntensity(0);
  }

  setVolumes(master: number, music: number, sfx: number, amb: number) {
    this.vol = { master, music, sfx, amb };
    this.applyVolumes();
  }
  private applyVolumes() {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    this.master.gain.setTargetAtTime(this.paused ? this.vol.master * 0.35 : this.vol.master, t, 0.05);
    this.musicBus.gain.setTargetAtTime(this.vol.music * 0.55, t, 0.05);
    this.sfx.gain.setTargetAtTime(this.vol.sfx, t, 0.05);
    this.ui.gain.setTargetAtTime(this.vol.sfx * 0.8, t, 0.05);
    this.amb.gain.setTargetAtTime(this.vol.amb * 0.9, t, 0.05);
  }
  setPaused(p: boolean) {
    this.paused = p;
    this.applyVolumes();
  }

  // ------------------------------------------------------------------ buffers
  private makeNoise(kind: 'white' | 'pink' | 'brown', seconds: number) {
    const c = this.ctx!;
    const len = Math.floor(c.sampleRate * seconds);
    const buf = c.createBuffer(1, len, c.sampleRate);
    const d = buf.getChannelData(0);
    const r = seeded(kind.length * 1000 + seconds);
    let b0 = 0, b1 = 0, b2 = 0, last = 0;
    for (let i = 0; i < len; i++) {
      const w = r() * 2 - 1;
      if (kind === 'white') d[i] = w;
      else if (kind === 'pink') {
        b0 = 0.997 * b0 + w * 0.029591;
        b1 = 0.985 * b1 + w * 0.032534;
        b2 = 0.95 * b2 + w * 0.048056;
        d[i] = (b0 + b1 + b2 + w * 0.05) * 2.2;
      } else {
        last = (last + 0.02 * w) / 1.02;
        d[i] = last * 3.5;
      }
    }
    return buf;
  }
  private makeImpulse(seconds: number, decay: number) {
    const c = this.ctx!;
    const len = Math.floor(c.sampleRate * seconds);
    const buf = c.createBuffer(2, len, c.sampleRate);
    const r = seeded(4242);
    for (let ch = 0; ch < 2; ch++) {
      const d = buf.getChannelData(ch);
      for (let i = 0; i < len; i++) {
        const t = i / len;
        // a few early reflections (small bedroom) then a soft tail
        const early = [0.011, 0.017, 0.023, 0.031, 0.043].some((e) => Math.abs(i / c.sampleRate - e - ch * 0.002) < 0.0006) ? 0.6 : 0;
        d[i] = ((r() * 2 - 1) * Math.pow(1 - t, decay) * 0.5 + early * (r() > 0.5 ? 1 : -1)) * (1 - t * 0.2);
      }
    }
    return buf;
  }

  // ------------------------------------------------------------------ plumbing
  updateListener(cam: THREE.Camera) {
    if (!this.ctx) return;
    const l = this.ctx.listener;
    const p = cam.getWorldPosition(new THREE.Vector3());
    this.listenerPos.copy(p);
    const f = new THREE.Vector3(0, 0, -1).applyQuaternion(cam.quaternion);
    const u = new THREE.Vector3(0, 1, 0).applyQuaternion(cam.quaternion);
    const t = this.ctx.currentTime;
    if (l.positionX) {
      l.positionX.setTargetAtTime(p.x, t, 0.015);
      l.positionY.setTargetAtTime(p.y, t, 0.015);
      l.positionZ.setTargetAtTime(p.z, t, 0.015);
      l.forwardX.setTargetAtTime(f.x, t, 0.015);
      l.forwardY.setTargetAtTime(f.y, t, 0.015);
      l.forwardZ.setTargetAtTime(f.z, t, 0.015);
      l.upX.setTargetAtTime(u.x, t, 0.015);
      l.upY.setTargetAtTime(u.y, t, 0.015);
      l.upZ.setTargetAtTime(u.z, t, 0.015);
    } else {
      (l as any).setPosition(p.x, p.y, p.z);
      (l as any).setOrientation(f.x, f.y, f.z, u.x, u.y, u.z);
    }
  }

  private voice(gain: number, pos?: THREE.Vector3, bus?: GainNode, dur = 1.5, reverb = 1, refDist = 4): Voice | null {
    const c = this.ctx;
    if (!c || c.state !== 'running') return null;
    if (this.voices >= this.maxVoices) return null;
    if (pos && pos.distanceTo(this.listenerPos) > 110) return null;
    this.voices++;
    const out = c.createGain();
    out.gain.value = gain;
    const nodes: AudioNode[] = [out];
    let tail: AudioNode = out;
    if (pos) {
      // material/occlusion: sounds behind solid objects are muffled
      if (this.occlusion && this.occlusion(pos)) {
        const lp = c.createBiquadFilter();
        lp.type = 'lowpass';
        lp.frequency.value = 900;
        const g = c.createGain();
        g.gain.value = 0.6;
        tail.connect(lp).connect(g);
        tail = g;
        nodes.push(lp, g);
      }
      const pan = c.createPanner();
      pan.panningModel = this.hrtf ? 'HRTF' : 'equalpower';
      pan.distanceModel = 'inverse';
      pan.refDistance = refDist;
      pan.rolloffFactor = 1.1;
      pan.maxDistance = 120;
      pan.positionX.value = pos.x;
      pan.positionY.value = pos.y;
      pan.positionZ.value = pos.z;
      tail.connect(pan);
      tail = pan;
      nodes.push(pan);
    }
    tail.connect(bus ?? this.sfx);
    if (reverb > 0 && (bus ?? this.sfx) === this.sfx) {
      const rs = c.createGain();
      rs.gain.value = reverb;
      tail.connect(rs).connect(this.reverbSend);
      nodes.push(rs);
    }
    window.setTimeout(() => {
      for (const n of nodes) {
        try { n.disconnect(); } catch { /* already gone */ }
      }
      this.voices--;
    }, (dur + 0.25) * 1000);
    return { out, nodes };
  }

  private env(g: AudioParam, t: number, e: Env) {
    const peak = e.peak ?? 1;
    g.setValueAtTime(0.0001, t);
    g.exponentialRampToValueAtTime(peak, t + Math.max(0.001, e.a));
    g.exponentialRampToValueAtTime(Math.max(0.0001, peak * (e.s ?? 0.0001)), t + e.a + e.d);
    if (e.r) g.exponentialRampToValueAtTime(0.0001, t + e.a + e.d + e.r);
  }

  private tone(v: Voice, type: OscillatorType, f0: number, f1: number, t: number, dur: number, e: Env, glide = 'exp' as 'exp' | 'lin', detune = 0) {
    const c = this.ctx!;
    const o = c.createOscillator();
    o.type = type;
    o.detune.value = detune;
    o.frequency.setValueAtTime(Math.max(1, f0), t);
    if (f1 !== f0) {
      if (glide === 'exp') o.frequency.exponentialRampToValueAtTime(Math.max(1, f1), t + dur);
      else o.frequency.linearRampToValueAtTime(f1, t + dur);
    }
    const g = c.createGain();
    this.env(g.gain, t, e);
    o.connect(g).connect(v.out);
    o.start(t);
    o.stop(t + e.a + e.d + (e.r ?? 0) + 0.05);
    v.nodes.push(o, g);
    return o;
  }

  private noise(v: Voice, kind: 'white' | 'pink' | 'brown', ftype: BiquadFilterType, freq: number, q: number, t: number, e: Env, freqEnd?: number, rate = 1) {
    const c = this.ctx!;
    const s = c.createBufferSource();
    s.buffer = kind === 'white' ? this.white : kind === 'pink' ? this.pink : this.brown;
    s.playbackRate.value = rate;
    const f = c.createBiquadFilter();
    f.type = ftype;
    f.frequency.setValueAtTime(freq, t);
    if (freqEnd) f.frequency.exponentialRampToValueAtTime(freqEnd, t + e.a + e.d);
    f.Q.value = q;
    const g = c.createGain();
    this.env(g.gain, t, e);
    s.connect(f).connect(g).connect(v.out);
    const off = Math.random() * 1.2;
    s.start(t, off);
    s.stop(t + e.a + e.d + (e.r ?? 0) + 0.05);
    v.nodes.push(s, f, g);
  }

  /** A short plastic click (used everywhere). */
  private click(v: Voice, t: number, freq = 3200, vol = 0.5, dur = 0.012) {
    this.noise(v, 'white', 'bandpass', freq, 3, t, { a: 0.001, d: dur, peak: vol });
  }

  get now() {
    return this.ctx?.currentTime ?? 0;
  }

  // ------------------------------------------------------------------ weapons
  gunshot(w: WeaponId, pos?: THREE.Vector3, local = false) {
    const v = this.voice(local ? 0.55 : 0.75, local ? undefined : pos, undefined, 1.2, local ? 0.9 : 1.2, 5);
    if (!v) return;
    const t = this.now;
    const p = rand(0.93, 1.08);
    const variant = Math.floor(Math.random() * 3);
    switch (w) {
      case 'plasti9':
        this.noise(v, 'white', 'highpass', 1600 * p, 0.7, t, { a: 0.001, d: 0.05, peak: 0.9 });
        this.tone(v, 'triangle', 980 * p, 210 * p, t, 0.06, { a: 0.001, d: 0.07, peak: 0.7 });
        this.tone(v, 'sine', 160, 70, t, 0.08, { a: 0.002, d: 0.09, peak: 0.6 });
        this.click(v, t + 0.035, 4200 + variant * 500, 0.35);
        this.tone(v, 'square', 2600 + variant * 300, 2300, t + 0.004, 0.02, { a: 0.001, d: 0.02, peak: 0.08 });
        break;
      case 'foamFury':
        this.noise(v, 'pink', 'bandpass', 900 * p, 1.2, t, { a: 0.001, d: 0.06, peak: 1.1 });
        this.tone(v, 'sine', 140 * p, 60, t, 0.07, { a: 0.002, d: 0.08, peak: 0.9 });
        this.tone(v, 'triangle', 620 * p, 300, t, 0.04, { a: 0.001, d: 0.05, peak: 0.35 });
        for (let i = 0; i < 2 + variant; i++) this.click(v, t + 0.02 + i * 0.013, 2400 + Math.random() * 2400, 0.25);
        break;
      case 'brickbreaker':
        this.noise(v, 'brown', 'lowpass', 1100 * p, 0.8, t, { a: 0.001, d: 0.16, peak: 1.6 }, 300);
        this.noise(v, 'white', 'bandpass', 2400, 1, t, { a: 0.001, d: 0.04, peak: 0.6 });
        this.tone(v, 'sine', 95 * p, 42, t, 0.14, { a: 0.002, d: 0.16, peak: 1.2 });
        for (let i = 0; i < 3 + variant; i++) this.click(v, t + 0.03 + i * 0.018, 1800 + Math.random() * 1500, 0.3);
        break;
      case 'bubbleBlaster':
        this.noise(v, 'pink', 'lowpass', 1400, 1, t, { a: 0.001, d: 0.12, peak: 1.2 }, 400);
        this.tone(v, 'sine', 260 * p, 900 * p, t, 0.08, { a: 0.002, d: 0.1, peak: 0.8 });
        this.tone(v, 'sine', 70, 45, t, 0.15, { a: 0.002, d: 0.18, peak: 1.0 });
        for (let i = 0; i < 6; i++) {
          const tt = t + 0.05 + Math.random() * 0.18;
          const f = rand(900, 2600);
          this.tone(v, 'sine', f, f * 1.8, tt, 0.03, { a: 0.001, d: 0.035, peak: 0.18 });
        }
        break;
      case 'thunderspring': {
        this.noise(v, 'white', 'highpass', 2500, 0.8, t, { a: 0.001, d: 0.05, peak: 1.0 });
        this.tone(v, 'sine', 120, 50, t, 0.2, { a: 0.002, d: 0.22, peak: 1.2 });
        // metallic twang: detuned partials with vibrato decay
        const base = 196 * p * (1 + variant * 0.03);
        for (const [mult, amp] of [[1, 0.5], [2.01, 0.35], [3.03, 0.25], [4.2, 0.15], [5.4, 0.1]] as const) {
          const o = this.tone(v, 'sawtooth', base * mult * 1.06, base * mult, t, 0.6, { a: 0.003, d: 0.9, peak: amp * 0.45 });
          const lfo = this.ctx!.createOscillator();
          const lg = this.ctx!.createGain();
          lfo.frequency.value = 7;
          lg.gain.value = 8 * mult;
          lfo.connect(lg).connect(o.frequency);
          lfo.start(t);
          lfo.stop(t + 1);
          v.nodes.push(lfo, lg);
        }
        break;
      }
      case 'rapidRascal':
        this.tone(v, 'square', 140 * p, 90, t, 0.035, { a: 0.001, d: 0.04, peak: 0.35 });
        this.noise(v, 'white', 'bandpass', 1800 * p, 1.5, t, { a: 0.001, d: 0.03, peak: 0.8 });
        this.tone(v, 'sine', 300 * p, 120, t, 0.04, { a: 0.001, d: 0.04, peak: 0.5 });
        if (variant === 0) this.click(v, t + 0.012, 5200, 0.2);
        break;
      case 'crayonCannon':
        this.tone(v, 'sine', 72 * p, 32, t, 0.3, { a: 0.003, d: 0.32, peak: 1.6 });
        this.noise(v, 'brown', 'lowpass', 600, 0.7, t, { a: 0.002, d: 0.25, peak: 1.4 }, 150);
        this.tone(v, 'triangle', 420, 180, t, 0.12, { a: 0.002, d: 0.12, peak: 0.4 });
        this.tone(v, 'sine', 900 * p, 1500 * p, t + 0.05, 0.12, { a: 0.003, d: 0.12, peak: 0.12 }); // comic 'thwomp' tail
        break;
      case 'starlightZapper':
        this.tone(v, 'sawtooth', 1900 * p, 420 * p, t, 0.09, { a: 0.001, d: 0.1, peak: 0.28 });
        this.tone(v, 'square', 950 * p, 210 * p, t, 0.08, { a: 0.001, d: 0.09, peak: 0.12 }, 'exp', 7);
        this.tone(v, 'sine', 2400 + variant * 200, 3200, t + 0.01, 0.03, { a: 0.001, d: 0.04, peak: 0.15 });
        this.noise(v, 'white', 'highpass', 5000, 0.5, t, { a: 0.001, d: 0.025, peak: 0.25 });
        break;
      case 'popcornPopper':
        // dry little pops, like kernels going off
        this.noise(v, 'white', 'bandpass', 2100 * p, 1.4, t, { a: 0.001, d: 0.05, peak: 1.0 }, 900);
        this.tone(v, 'square', 520 * p, 190, t, 0.05, { a: 0.001, d: 0.06, peak: 0.3 });
        this.tone(v, 'sine', 170 * p, 80, t, 0.06, { a: 0.001, d: 0.07, peak: 0.6 });
        this.click(v, t + 0.012, 3600 + variant * 250, 0.4);
        break;
      case 'jackBlaster':
        // tight shotgun pop + a jack-in-the-box spring boing
        this.noise(v, 'pink', 'lowpass', 1600 * p, 0.8, t, { a: 0.001, d: 0.14, peak: 1.5 }, 400);
        this.tone(v, 'sine', 110 * p, 45, t, 0.12, { a: 0.002, d: 0.14, peak: 1.0 });
        this.noise(v, 'white', 'bandpass', 2600 * p, 1.2, t, { a: 0.001, d: 0.04, peak: 0.6 });
        {
          const o = this.tone(v, 'triangle', 520 * p, 520 * p, t + 0.05, 0.3, { a: 0.005, d: 0.32, peak: 0.16 });
          const lfo = this.ctx!.createOscillator();
          const lg = this.ctx!.createGain();
          lfo.frequency.value = 18;
          lg.gain.setValueAtTime(220, t + 0.05);
          lg.gain.exponentialRampToValueAtTime(8, t + 0.4);
          lfo.connect(lg).connect(o.frequency);
          lfo.start(t + 0.05);
          lfo.stop(t + 0.45);
          v.nodes.push(lfo, lg);
        }
        for (let i = 0; i < 3; i++) this.click(v, t + 0.12 + i * 0.05, 3000 + variant * 300, 0.25);
        break;
      case 'walloper':
        // a huge boom: deep thump, cracking top end, and a rolling tail
        this.noise(v, 'brown', 'lowpass', 900 * p, 0.7, t, { a: 0.001, d: 0.42, peak: 2.2 }, 160);
        this.noise(v, 'white', 'bandpass', 3200 * p, 0.9, t, { a: 0.001, d: 0.06, peak: 1.1 });
        this.tone(v, 'sine', 78 * p, 30, t, 0.32, { a: 0.002, d: 0.38, peak: 1.8 });
        this.tone(v, 'triangle', 420 * p, 120, t, 0.09, { a: 0.001, d: 0.1, peak: 0.5 });
        this.noise(v, 'pink', 'lowpass', 500, 0.6, t + 0.08, { a: 0.02, d: 0.6, peak: 0.45 }, 120);
        this.click(v, t + 0.3, 2400 + variant * 200, 0.3);
        break;
      case 'plungerBow':
        // string twang + whoosh
        this.tone(v, 'triangle', 190 * p, 140 * p, t, 0.22, { a: 0.001, d: 0.25, peak: 0.5 });
        this.tone(v, 'sine', 380 * p, 300 * p, t, 0.15, { a: 0.001, d: 0.16, peak: 0.25 });
        this.noise(v, 'white', 'bandpass', 1400, 0.7, t + 0.01, { a: 0.01, d: 0.18, peak: 0.45 }, 600);
        this.click(v, t, 2600, 0.5);
        break;
    }
  }

  /** Bow string creaking while it's drawn. */
  bowDraw(local = true, pos?: THREE.Vector3) {
    const v = this.voice(local ? 0.3 : 0.2, local ? undefined : pos, undefined, 1.1, 0.4);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sawtooth', 70, 110, t, 0.9, { a: 0.1, d: 0.9, peak: 0.05 });
    for (let i = 0; i < 6; i++) this.click(v, t + i * 0.13 + Math.random() * 0.04, 900 + i * 120, 0.12, 0.02);
  }

  // ------------------------------------------------------------------ abilities
  punch(hit: boolean, pos?: THREE.Vector3) {
    const v = this.voice(hit ? 0.7 : 0.45, pos, undefined, 0.7, 0.6);
    if (!v) return;
    const t = this.now;
    // spring release
    this.tone(v, 'triangle', 300, 1100, t, 0.08, { a: 0.002, d: 0.08, peak: 0.25 });
    this.noise(v, 'white', 'bandpass', 1500, 1, t, { a: 0.005, d: 0.08, peak: 0.35 }, 3500);
    if (hit) {
      this.tone(v, 'sine', 150, 55, t + 0.06, 0.16, { a: 0.002, d: 0.18, peak: 1.2 });
      this.noise(v, 'pink', 'lowpass', 900, 1, t + 0.06, { a: 0.002, d: 0.12, peak: 1.0 });
      this.click(v, t + 0.06, 1800, 0.7, 0.02);
    }
  }
  grapple(pos?: THREE.Vector3, hit = true) {
    const v = this.voice(0.5, pos, undefined, 0.8, 0.5);
    if (!v) return;
    const t = this.now;
    this.noise(v, 'white', 'bandpass', 2400, 2, t, { a: 0.005, d: 0.25, peak: 0.4 }, 800);
    for (let i = 0; i < 6; i++) this.click(v, t + i * 0.03, 2500 + i * 300, 0.25);
    if (hit) this.click(v, t + 0.18, 1200, 0.9, 0.03);
  }
  cloak(on: boolean, pos?: THREE.Vector3) {
    const v = this.voice(0.4, pos, undefined, 0.8, 0.8);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', on ? 1400 : 300, on ? 300 : 1400, t, 0.5, { a: 0.01, d: 0.5, peak: 0.2 });
    this.noise(v, 'white', 'highpass', 4000, 0.7, t, { a: 0.05, d: 0.45, peak: 0.2 }, on ? 9000 : 2500);
  }
  shieldUp(pos?: THREE.Vector3) {
    const v = this.voice(0.5, pos, undefined, 0.8, 0.6);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'square', 220, 880, t, 0.25, { a: 0.005, d: 0.28, peak: 0.08 });
    this.tone(v, 'sine', 440, 1320, t, 0.3, { a: 0.005, d: 0.32, peak: 0.25 });
    for (let i = 0; i < 4; i++) this.click(v, t + 0.05 + i * 0.05, 4000 - i * 400, 0.2);
  }
  elevatorDing(pos: THREE.Vector3) {
    const v = this.voice(0.35, pos, undefined, 1.2, 0.8, 5);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', 1318, 1318, t, 0.5, { a: 0.002, d: 0.6, peak: 0.3 });
    this.tone(v, 'sine', 1046, 1046, t + 0.18, 0.6, { a: 0.002, d: 0.7, peak: 0.3 });
  }
  sectorCaptured(mine: boolean) {
    const v = this.voice(0.45, undefined, this.ui, 1, 0);
    if (!v) return;
    const t = this.now;
    const notes = mine ? [523, 659, 784, 1047] : [440, 415, 392, 330];
    notes.forEach((f, i) => this.tone(v, 'triangle', f, f, t + i * 0.08, 0.16, { a: 0.003, d: 0.22, peak: 0.3 }));
  }

  /** Spring winding after a Thunderspring shot. */
  springWind(pos?: THREE.Vector3, local = true) {
    const v = this.voice(0.4, local ? undefined : pos, undefined, 0.8);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 7; i++) this.click(v, t + i * 0.055, 2200 + i * 180, 0.35);
    this.tone(v, 'triangle', 300, 700, t, 0.4, { a: 0.02, d: 0.4, peak: 0.08 });
  }

  reloadPart(w: WeaponId, part: 'out' | 'in' | 'charge' | 'shell' | 'spring' | 'vent' | 'pump' | 'open' | 'close', local = true, pos?: THREE.Vector3) {
    const v = this.voice(local ? 0.5 : 0.4, local ? undefined : pos, undefined, 0.8, 0.6, 2.5);
    if (!v) return;
    const t = this.now;
    const pitch: number = { plasti9: 1.25, foamFury: 1, brickbreaker: 0.8, bubbleBlaster: 1.1, thunderspring: 0.9, rapidRascal: 1.15, crayonCannon: 0.7, starlightZapper: 1.3, jackBlaster: 0.95, plungerBow: 1.1, popcornPopper: 1.2, walloper: 0.7 }[w];
    switch (part) {
      case 'out':
        this.noise(v, 'white', 'bandpass', 1500 * pitch, 2, t, { a: 0.002, d: 0.06, peak: 0.5 });
        this.click(v, t + 0.05, 2600 * pitch, 0.4);
        break;
      case 'in':
        this.noise(v, 'pink', 'bandpass', 900 * pitch, 1.5, t, { a: 0.003, d: 0.05, peak: 0.6 });
        this.click(v, t + 0.04, 3400 * pitch, 0.6);
        this.tone(v, 'sine', 300 * pitch, 180, t + 0.04, 0.05, { a: 0.001, d: 0.06, peak: 0.3 });
        break;
      case 'charge':
        this.noise(v, 'white', 'bandpass', 2000 * pitch, 2, t, { a: 0.01, d: 0.09, peak: 0.4 }, 3500 * pitch);
        this.click(v, t + 0.1, 3800 * pitch, 0.6);
        this.tone(v, 'triangle', 700 * pitch, 1200 * pitch, t + 0.1, 0.12, { a: 0.002, d: 0.15, peak: 0.12 });
        break;
      case 'shell':
        this.click(v, t, 2600, 0.5);
        this.tone(v, 'sine', 500, 1300, t, 0.05, { a: 0.002, d: 0.06, peak: 0.25 });
        this.tone(v, 'sine', 1800, 2400, t + 0.06, 0.03, { a: 0.001, d: 0.03, peak: 0.1 });
        break;
      case 'pump':
        this.noise(v, 'pink', 'bandpass', 1200, 1.3, t, { a: 0.005, d: 0.08, peak: 0.6 });
        this.click(v, t + 0.09, 2200, 0.7);
        this.noise(v, 'pink', 'bandpass', 1500, 1.3, t + 0.12, { a: 0.005, d: 0.06, peak: 0.5 });
        break;
      case 'spring':
        for (let i = 0; i < 9; i++) this.click(v, t + i * 0.06, 1500 + i * 220, 0.4);
        this.tone(v, 'triangle', 200, 900, t, 0.55, { a: 0.02, d: 0.55, peak: 0.1 });
        this.click(v, t + 0.6, 4200, 0.8);
        break;
      case 'vent':
        this.noise(v, 'white', 'highpass', 3000, 0.7, t, { a: 0.02, d: 0.4, peak: 0.25 }, 8000);
        this.tone(v, 'sine', 400, 1600, t, 0.5, { a: 0.02, d: 0.5, peak: 0.15 });
        break;
      case 'open':
        this.noise(v, 'pink', 'bandpass', 700, 2, t, { a: 0.005, d: 0.08, peak: 0.5 });
        this.click(v, t + 0.07, 1500, 0.5);
        break;
      case 'close':
        this.click(v, t, 1300, 0.7);
        this.tone(v, 'sine', 180, 120, t, 0.06, { a: 0.001, d: 0.07, peak: 0.4 });
        break;
    }
  }

  empty(local = true) {
    const v = this.voice(0.5, undefined, undefined, 0.3, 0.3);
    if (!v) return;
    const t = this.now;
    this.click(v, t, 1800, 0.7, 0.02);
    this.click(v, t + 0.02, 1100, 0.4, 0.02);
    void local;
  }

  weaponSwitch() {
    const v = this.voice(0.35, undefined, undefined, 0.4, 0.4);
    if (!v) return;
    const t = this.now;
    this.noise(v, 'pink', 'bandpass', 1100, 1.5, t, { a: 0.01, d: 0.08, peak: 0.5 });
    this.click(v, t + 0.12, 2800, 0.5);
  }

  // ------------------------------------------------------------------ impacts & bodies
  impact(mat: SurfaceMat, pos: THREE.Vector3, vol = 1) {
    const v = this.voice(0.5 * vol, pos, undefined, 0.6, 0.8, 3);
    if (!v) return;
    const t = this.now;
    const p = rand(0.9, 1.12);
    switch (mat) {
      case 'plastic':
        this.click(v, t, 3800 * p, 0.8, 0.02);
        this.tone(v, 'triangle', 1500 * p, 900, t, 0.03, { a: 0.001, d: 0.035, peak: 0.25 });
        break;
      case 'wood':
        this.tone(v, 'sine', 340 * p, 260, t, 0.08, { a: 0.001, d: 0.09, peak: 0.7 });
        this.noise(v, 'pink', 'bandpass', 900 * p, 2, t, { a: 0.001, d: 0.05, peak: 0.5 });
        break;
      case 'fabric':
      case 'carpet':
        this.noise(v, 'brown', 'lowpass', 500 * p, 0.7, t, { a: 0.003, d: 0.09, peak: 0.7 });
        break;
      case 'metal':
        for (const f of [2500, 3720, 5100]) this.tone(v, 'sine', f * p, f * p * 0.995, t, 0.4, { a: 0.001, d: 0.45, peak: 0.12 });
        this.click(v, t, 6000, 0.5);
        break;
      case 'cardboard':
        this.noise(v, 'pink', 'lowpass', 380 * p, 1, t, { a: 0.002, d: 0.1, peak: 0.9 });
        this.tone(v, 'sine', 120 * p, 80, t, 0.08, { a: 0.002, d: 0.09, peak: 0.5 });
        break;
      case 'glass':
        for (const f of [3100, 4650, 6900]) this.tone(v, 'sine', f * p, f * p, t, 0.25, { a: 0.001, d: 0.3, peak: 0.1 });
        break;
    }
  }

  footstep(mat: SurfaceMat, pos: THREE.Vector3 | undefined, vol = 1) {
    const v = this.voice(0.28 * vol, pos, undefined, 0.3, 0.4, 2.5);
    if (!v) return;
    const t = this.now;
    const p = rand(0.85, 1.15);
    switch (mat) {
      case 'wood':
        this.tone(v, 'sine', 190 * p, 140, t, 0.05, { a: 0.002, d: 0.06, peak: 0.6 });
        this.noise(v, 'pink', 'bandpass', 700 * p, 1.5, t, { a: 0.002, d: 0.04, peak: 0.35 });
        break;
      case 'plastic':
      case 'metal':
      case 'glass':
        this.click(v, t, 2600 * p, 0.45, 0.018);
        this.tone(v, 'triangle', 700 * p, 500, t, 0.03, { a: 0.001, d: 0.03, peak: 0.2 });
        break;
      case 'carpet':
      case 'fabric':
        this.noise(v, 'brown', 'lowpass', 350 * p, 0.7, t, { a: 0.006, d: 0.07, peak: 0.6 });
        break;
      case 'cardboard':
        this.noise(v, 'pink', 'lowpass', 500 * p, 1, t, { a: 0.003, d: 0.06, peak: 0.6 });
        this.noise(v, 'white', 'bandpass', 3000, 2, t + 0.01, { a: 0.002, d: 0.03, peak: 0.15 });
        break;
    }
  }

  jump(pos?: THREE.Vector3) {
    const v = this.voice(0.3, pos, undefined, 0.3, 0.3);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', 300, 700, t, 0.1, { a: 0.005, d: 0.1, peak: 0.25 });
    this.noise(v, 'pink', 'bandpass', 1200, 1, t, { a: 0.005, d: 0.06, peak: 0.25 });
  }
  land(mat: SurfaceMat, strength: number, pos?: THREE.Vector3) {
    this.footstep(mat, pos, 1 + strength * 1.5);
    const v = this.voice(0.25 * strength, pos, undefined, 0.3, 0.3);
    if (!v) return;
    this.tone(v, 'sine', 120, 60, this.now, 0.1, { a: 0.003, d: 0.12, peak: 0.7 });
  }
  slide() {
    const v = this.voice(0.35, undefined, undefined, 0.9, 0.3);
    if (!v) return;
    this.noise(v, 'pink', 'bandpass', 800, 0.8, this.now, { a: 0.03, d: 0.7, peak: 0.6 }, 300);
  }
  dash(pos?: THREE.Vector3) {
    const v = this.voice(0.5, pos, undefined, 0.9, 0.5);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 5; i++) this.click(v, t + i * 0.03, 2000 + i * 400, 0.4);
    this.noise(v, 'white', 'bandpass', 900, 1, t + 0.1, { a: 0.02, d: 0.35, peak: 0.6 }, 4000);
    this.tone(v, 'sine', 400, 1200, t + 0.1, 0.25, { a: 0.01, d: 0.3, peak: 0.2 });
  }

  hitmarker(head: boolean, shield: boolean) {
    const v = this.voice(0.42, undefined, this.ui, 0.3, 0);
    if (!v) return;
    const t = this.now;
    if (head) {
      this.tone(v, 'sine', 1900, 1900, t, 0.1, { a: 0.001, d: 0.14, peak: 0.6 });
      this.tone(v, 'sine', 2850, 2850, t + 0.01, 0.1, { a: 0.001, d: 0.12, peak: 0.3 });
    } else if (shield) {
      this.tone(v, 'triangle', 1300, 1600, t, 0.05, { a: 0.001, d: 0.06, peak: 0.4 });
    } else {
      this.click(v, t, 3200, 0.9, 0.015);
      this.tone(v, 'triangle', 1100, 900, t, 0.03, { a: 0.001, d: 0.04, peak: 0.3 });
    }
  }
  killConfirm(streak: number) {
    const v = this.voice(0.5, undefined, this.ui, 0.8, 0);
    if (!v) return;
    const t = this.now;
    const base = 660 * Math.pow(2, Math.min(streak - 1, 5) / 12);
    [0, 4, 7, 12].forEach((s, i) => this.tone(v, 'triangle', base * Math.pow(2, s / 12), base * Math.pow(2, s / 12), t + i * 0.045, 0.15, { a: 0.002, d: 0.2, peak: 0.35 }));
    this.tone(v, 'sine', 120, 60, t, 0.1, { a: 0.002, d: 0.12, peak: 0.4 });
  }
  /** Toy breaks apart: clatter + spring boing. */
  eliminated(pos: THREE.Vector3) {
    const v = this.voice(0.8, pos, undefined, 1.2, 1, 6);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 9; i++) this.click(v, t + Math.random() * 0.35, rand(1500, 5000), rand(0.3, 0.7), 0.02);
    const o = this.tone(v, 'sine', 300, 300, t + 0.05, 0.6, { a: 0.003, d: 0.6, peak: 0.4 });
    const lfo = this.ctx!.createOscillator();
    const lg = this.ctx!.createGain();
    lfo.frequency.value = 16;
    lg.gain.setValueAtTime(140, t);
    lg.gain.exponentialRampToValueAtTime(5, t + 0.6);
    lfo.connect(lg).connect(o.frequency);
    lfo.start(t);
    lfo.stop(t + 0.7);
    v.nodes.push(lfo, lg);
    this.noise(v, 'pink', 'lowpass', 1500, 0.8, t, { a: 0.002, d: 0.2, peak: 0.6 });
  }
  hurt(pitch: number, pos?: THREE.Vector3) {
    const v = this.voice(0.3, pos, undefined, 0.4, 0.4);
    if (!v) return;
    const t = this.now;
    // toy squeaker
    const o = this.tone(v, 'sine', 1300 * pitch, 800 * pitch, t, 0.14, { a: 0.005, d: 0.15, peak: 0.35 });
    const lfo = this.ctx!.createOscillator();
    const lg = this.ctx!.createGain();
    lfo.frequency.value = 30;
    lg.gain.value = 60;
    lfo.connect(lg).connect(o.frequency);
    lfo.start(t);
    lfo.stop(t + 0.2);
    v.nodes.push(lfo, lg);
  }
  playerHurt(shield: boolean) {
    const v = this.voice(0.45, undefined, this.ui, 0.4, 0);
    if (!v) return;
    const t = this.now;
    if (shield) this.tone(v, 'triangle', 900, 500, t, 0.1, { a: 0.002, d: 0.12, peak: 0.4 });
    else {
      this.tone(v, 'sine', 180, 90, t, 0.12, { a: 0.002, d: 0.14, peak: 0.7 });
      this.noise(v, 'pink', 'lowpass', 900, 1, t, { a: 0.002, d: 0.08, peak: 0.4 });
    }
  }
  shieldBreak(pos?: THREE.Vector3) {
    const v = this.voice(0.5, pos, undefined, 0.6, 0.6);
    if (!v) return;
    const t = this.now;
    for (const f of [2200, 2900, 3700]) this.tone(v, 'sine', f, f * 0.6, t, 0.3, { a: 0.001, d: 0.3, peak: 0.15 });
    this.noise(v, 'white', 'highpass', 3000, 0.7, t, { a: 0.001, d: 0.2, peak: 0.5 });
  }
  pickup(kind: PickupKind | 'weapon' | 'ammo', pos?: THREE.Vector3, local = true) {
    const v = this.voice(local ? 0.45 : 0.3, local ? undefined : pos, local ? this.ui : undefined, 0.9, 0.2);
    if (!v) return;
    const t = this.now;
    const notes: Record<string, number[]> = {
      health: [523, 659, 784], shield: [392, 587, 784, 1175], turbo: [440, 554, 659, 880], infinite: [659, 523, 659, 880],
      power: [523, 784, 1047, 1568], weapon: [330, 494], ammo: [660, 880],
    };
    notes[kind].forEach((f, i) => this.tone(v, kind === 'shield' ? 'sine' : 'triangle', f, f, t + i * 0.06, 0.12, { a: 0.002, d: 0.18, peak: 0.3 }));
    if (kind === 'weapon') this.reloadPart('foamFury', 'charge');
  }
  spawnPop(pos?: THREE.Vector3) {
    const v = this.voice(0.4, pos, undefined, 0.6, 0.5);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', 300, 1200, t, 0.15, { a: 0.005, d: 0.18, peak: 0.4 });
    for (let i = 0; i < 4; i++) this.click(v, t + 0.12 + i * 0.03, 3000 + i * 600, 0.3);
  }
  explosion(pos: THREE.Vector3) {
    const v = this.voice(1.1, pos, undefined, 1.6, 1.3, 7);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', 90, 30, t, 0.5, { a: 0.003, d: 0.55, peak: 1.4 });
    this.noise(v, 'brown', 'lowpass', 1200, 0.7, t, { a: 0.003, d: 0.5, peak: 1.6 }, 120);
    this.noise(v, 'white', 'bandpass', 2500, 1, t, { a: 0.002, d: 0.1, peak: 0.6 });
    // colorful 'pop' + confetti crackle
    this.tone(v, 'sine', 600, 1400, t + 0.02, 0.08, { a: 0.002, d: 0.1, peak: 0.35 });
    for (let i = 0; i < 10; i++) this.click(v, t + 0.08 + Math.random() * 0.4, rand(3000, 7000), rand(0.1, 0.3), 0.01);
  }
  /** Falling whistle that follows a crayon projectile. Returns a handle to move/stop it. */
  whistle(pos: THREE.Vector3) {
    const c = this.ctx;
    if (!c || c.state !== 'running') return null;
    const o = c.createOscillator();
    o.type = 'sine';
    o.frequency.value = 1800;
    o.frequency.exponentialRampToValueAtTime(500, c.currentTime + 2.2);
    const g = c.createGain();
    g.gain.value = 0.0001;
    g.gain.exponentialRampToValueAtTime(0.12, c.currentTime + 0.2);
    const pan = c.createPanner();
    pan.panningModel = this.hrtf ? 'HRTF' : 'equalpower';
    pan.refDistance = 4;
    pan.positionX.value = pos.x;
    pan.positionY.value = pos.y;
    pan.positionZ.value = pos.z;
    o.connect(g).connect(pan).connect(this.sfx);
    o.start();
    let stopped = false;
    return {
      move: (p: THREE.Vector3) => {
        if (stopped) return;
        pan.positionX.value = p.x;
        pan.positionY.value = p.y;
        pan.positionZ.value = p.z;
      },
      stop: () => {
        if (stopped) return;
        stopped = true;
        const t = c.currentTime;
        g.gain.cancelScheduledValues(t);
        g.gain.setValueAtTime(Math.max(0.0001, g.gain.value), t);
        g.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
        o.stop(t + 0.08);
        window.setTimeout(() => { try { o.disconnect(); g.disconnect(); pan.disconnect(); } catch { /* */ } }, 200);
      },
    };
  }
  bubblePop(pos: THREE.Vector3) {
    const v = this.voice(0.18, pos, undefined, 0.2, 0.3, 2);
    if (!v) return;
    const f = rand(1200, 3000);
    this.tone(v, 'sine', f, f * 2, this.now, 0.025, { a: 0.001, d: 0.03, peak: 0.5 });
  }
  zap(pos: THREE.Vector3) {
    const v = this.voice(0.25, pos, undefined, 0.3, 0.4, 2);
    if (!v) return;
    this.tone(v, 'square', 3000, 800, this.now, 0.05, { a: 0.001, d: 0.06, peak: 0.15 });
  }

  // ------------------------------------------------------------------ UI
  uiHover() {
    const v = this.voice(0.15, undefined, this.ui, 0.15, 0);
    if (!v) return;
    this.tone(v, 'sine', 1400, 1600, this.now, 0.03, { a: 0.001, d: 0.04, peak: 0.25 });
  }
  uiClick() {
    const v = this.voice(0.3, undefined, this.ui, 0.3, 0);
    if (!v) return;
    const t = this.now;
    this.click(v, t, 2400, 0.6);
    this.tone(v, 'triangle', 880, 1320, t, 0.06, { a: 0.002, d: 0.08, peak: 0.3 });
  }
  uiBack() {
    const v = this.voice(0.25, undefined, this.ui, 0.3, 0);
    if (!v) return;
    this.tone(v, 'triangle', 900, 500, this.now, 0.08, { a: 0.002, d: 0.1, peak: 0.3 });
  }
  countdown(final: boolean) {
    const v = this.voice(0.4, undefined, this.ui, 0.6, 0);
    if (!v) return;
    const f = final ? 1320 : 880;
    this.tone(v, 'square', f, f, this.now, 0.2, { a: 0.002, d: final ? 0.4 : 0.15, peak: 0.15 });
  }
  fanfare(win: boolean) {
    const v = this.voice(0.5, undefined, this.ui, 2.5, 0);
    if (!v) return;
    const t = this.now;
    const seq = win ? [523, 659, 784, 1047, 784, 1047] : [523, 494, 466, 440];
    seq.forEach((f, i) => {
      this.tone(v, 'triangle', f, f, t + i * 0.14, 0.3, { a: 0.005, d: i === seq.length - 1 ? 0.9 : 0.2, peak: 0.35 });
      this.tone(v, 'sine', f / 2, f / 2, t + i * 0.14, 0.3, { a: 0.005, d: 0.2, peak: 0.2 });
    });
  }
  announce() {
    const v = this.voice(0.4, undefined, this.ui, 1, 0);
    if (!v) return;
    const t = this.now;
    [784, 988, 1175].forEach((f, i) => this.tone(v, 'sine', f, f, t + i * 0.09, 0.2, { a: 0.003, d: 0.25, peak: 0.25 }));
  }

  // ------------------------------------------------------------------ ambience
  /** Positional one-shots used by the ambient system. */
  trainWhistle(pos: THREE.Vector3) {
    const v = this.voice(0.35, pos, this.amb, 1.6, 0, 10);
    if (!v) return;
    const t = this.now;
    for (const [f, d] of [[740, 0], [880, 0.02], [1110, 0.01]] as const) {
      this.tone(v, 'sawtooth', f, f * 0.98, t + d, 0.9, { a: 0.05, d: 0.25, s: 0.6, r: 0.5, peak: 0.07 });
    }
    this.noise(v, 'white', 'bandpass', 2000, 1, t, { a: 0.05, d: 0.9, peak: 0.12 });
  }
  trainChug(pos: THREE.Vector3) {
    const v = this.voice(0.18, pos, this.amb, 0.3, 0, 8);
    if (!v) return;
    this.noise(v, 'white', 'bandpass', 1200, 1.2, this.now, { a: 0.005, d: 0.08, peak: 0.6 });
  }
  clockTick(pos: THREE.Vector3, tock: boolean) {
    const v = this.voice(0.25, pos, this.amb, 0.2, 0, 8);
    if (!v) return;
    this.click(v, this.now, tock ? 2300 : 2900, 0.7, 0.012);
  }
  windUp(pos: THREE.Vector3) {
    const v = this.voice(0.2, pos, this.amb, 0.8, 0, 6);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 8; i++) this.click(v, t + i * 0.07, 3000 + (i % 2) * 400, 0.4, 0.01);
  }
  creak(pos: THREE.Vector3) {
    const v = this.voice(0.2, pos, this.amb, 1.4, 0, 8);
    if (!v) return;
    const t = this.now;
    // woody creak: resonant filtered noise sweeping slowly + a low buzz
    this.noise(v, 'pink', 'bandpass', 380, 14, t, { a: 0.15, d: 0.8, peak: 1.2 }, 620, 0.5);
    this.tone(v, 'sawtooth', 70, 95, t, 0.9, { a: 0.1, d: 0.8, peak: 0.04 }, 'lin');
  }
  bird(pos: THREE.Vector3) {
    const v = this.voice(0.12, pos, this.amb, 0.8, 0, 6);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 3; i++) {
      const f = rand(2200, 3200);
      this.tone(v, 'sine', f, f * 1.3, t + i * 0.12, 0.06, { a: 0.005, d: 0.07, peak: 0.3 });
    }
  }
  rumble(pos: THREE.Vector3) {
    const v = this.voice(0.4, pos, this.amb, 2.5, 0, 8);
    if (!v) return;
    this.noise(v, 'brown', 'lowpass', 160, 0.7, this.now, { a: 0.4, d: 1.8, peak: 1 });
  }
  clatter(pos: THREE.Vector3) {
    const v = this.voice(0.25, pos, this.amb, 0.8, 0, 6);
    if (!v) return;
    const t = this.now;
    for (let i = 0; i < 5; i++) this.click(v, t + Math.random() * 0.3, rand(2000, 4500), 0.5);
  }
  blockLand(pos: THREE.Vector3) {
    const v = this.voice(0.7, pos, undefined, 0.6, 1, 6);
    if (!v) return;
    const t = this.now;
    this.tone(v, 'sine', 160, 90, t, 0.15, { a: 0.002, d: 0.18, peak: 1 });
    this.noise(v, 'pink', 'bandpass', 700, 1.5, t, { a: 0.002, d: 0.1, peak: 0.7 });
  }

  /** Continuous positional motor hum (rc cars). */
  motorLoop(pos: THREE.Vector3) {
    const c = this.ctx;
    if (!c) return null;
    const o = c.createOscillator();
    o.type = 'sawtooth';
    o.frequency.value = 62;
    const o2 = c.createOscillator();
    o2.type = 'square';
    o2.frequency.value = 124.5;
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 700;
    const g = c.createGain();
    g.gain.value = 0.05;
    const g2 = c.createGain();
    g2.gain.value = 0.3;
    const pan = c.createPanner();
    pan.panningModel = 'equalpower';
    pan.refDistance = 3;
    pan.rolloffFactor = 1.4;
    pan.positionX.value = pos.x;
    pan.positionY.value = pos.y;
    pan.positionZ.value = pos.z;
    o.connect(lp);
    o2.connect(g2).connect(lp);
    lp.connect(g).connect(pan).connect(this.amb);
    o.start();
    o2.start();
    let alive = true;
    return {
      move: (p: THREE.Vector3, speed: number) => {
        if (!alive) return;
        pan.positionX.value = p.x;
        pan.positionY.value = p.y;
        pan.positionZ.value = p.z;
        o.frequency.value = 50 + speed * 4;
        o2.frequency.value = 100 + speed * 8.1;
      },
      stop: () => {
        if (!alive) return;
        alive = false;
        try { o.stop(); o2.stop(); o.disconnect(); o2.disconnect(); lp.disconnect(); g.disconnect(); g2.disconnect(); pan.disconnect(); } catch { /* */ }
      },
    };
  }

  /** Continuous room tone + per-zone loops. Crossfaded by zone. */
  startAmbience() {
    const c = this.ctx;
    if (!c || this.ventilation) return;
    const vent = c.createBufferSource();
    vent.buffer = this.brown;
    vent.loop = true;
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.value = 380;
    this.ventilation = c.createGain();
    this.ventilation.gain.value = 0.16;
    vent.connect(lp).connect(this.ventilation).connect(this.amb);
    vent.start();
    const loops: [ZoneAmb, AudioBuffer, BiquadFilterType, number, number][] = [
      ['closet', this.brown, 'lowpass', 120, 0.5],
      ['desk', this.pink, 'bandpass', 2400, 0.04],
      ['dino', this.brown, 'lowpass', 90, 0.6],
      ['garage', this.pink, 'bandpass', 180, 0.18],
      ['bed', this.pink, 'lowpass', 600, 0.05],
      ['brick', this.white, 'bandpass', 5000, 0.015],
      ['rug', this.pink, 'lowpass', 400, 0.03],
    ];
    for (const [zone, buf, ft, f, vol] of loops) {
      const s = c.createBufferSource();
      s.buffer = buf;
      s.loop = true;
      s.playbackRate.value = rand(0.9, 1.1);
      const fl = c.createBiquadFilter();
      fl.type = ft;
      fl.frequency.value = f;
      fl.Q.value = ft === 'bandpass' ? 2 : 0.7;
      const g = c.createGain();
      g.gain.value = 0;
      s.connect(fl).connect(g).connect(this.amb);
      s.start();
      (g as any).__target = vol;
      this.zoneLoops.set(zone, { gain: g, src: s });
    }
  }
  setZone(z: ZoneAmb) {
    if (!this.ctx) return;
    const t = this.ctx.currentTime;
    for (const [zone, l] of this.zoneLoops) {
      l.gain.gain.setTargetAtTime(zone === z ? (l.gain as any).__target : 0, t, 0.8);
    }
  }
  stopAmbience() {
    for (const l of this.zoneLoops.values()) {
      try { l.src.stop(); l.src.disconnect(); l.gain.disconnect(); } catch { /* */ }
    }
    this.zoneLoops.clear();
    this.ventilation?.disconnect();
    this.ventilation = null;
    for (const t of this.ambTimers) clearTimeout(t);
    this.ambTimers = [];
  }

  randomCreakSpot(): THREE.Vector3 {
    return new THREE.Vector3(rand(-30, 30), 0, rand(-34, 34));
  }
  pickAmb<T>(a: readonly T[]) {
    return pick(a);
  }
}

export const audio = new AudioEngine();

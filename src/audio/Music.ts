import { seeded } from '../core/math';

/**
 * Small procedural music engine: a playful toy-box groove (plucks, bass, toy drums, bells)
 * that layers up as the match gets intense. Uses a lookahead scheduler for tight timing.
 */
type Layer = 'pluck' | 'bass' | 'drums' | 'bells' | 'arp' | 'hats16';

const midi = (n: number) => 440 * Math.pow(2, (n - 69) / 12);

const PROG_A = [
  [60, 64, 67], // C
  [57, 60, 64], // Am
  [53, 57, 60], // F
  [55, 59, 62], // G
];
const PROG_B = [
  [53, 57, 60], // F
  [55, 59, 62], // G
  [52, 55, 59], // Em
  [57, 60, 64], // Am
];
const SCALE = [0, 2, 4, 7, 9]; // pentatonic

export class Music {
  private layers = new Map<Layer, GainNode>();
  private timer: number | null = null;
  private step = 0;
  private nextTime = 0;
  private tempo = 108;
  private targetTempo = 108;
  intensity = 0;
  private melody: number[][] = [];
  private playing = false;
  private noiseBuf: AudioBuffer;
  private target = new Map<Layer, number>();
  private on(l: Layer) {
    return (this.target.get(l) ?? 0) > 0.01 || this.layers.get(l)!.gain.value > 0.01;
  }

  constructor(private ctx: AudioContext, private out: GainNode) {
    for (const l of ['pluck', 'bass', 'drums', 'bells', 'arp', 'hats16'] as Layer[]) {
      const g = ctx.createGain();
      g.gain.value = 0;
      g.connect(out);
      this.layers.set(l, g);
    }
    const len = ctx.sampleRate;
    this.noiseBuf = ctx.createBuffer(1, len, ctx.sampleRate);
    const d = this.noiseBuf.getChannelData(0);
    const r = seeded(31);
    for (let i = 0; i < len; i++) d[i] = r() * 2 - 1;
    this.makeMelody(1);
  }

  private makeMelody(seed: number) {
    const r = seeded(seed * 97 + 13);
    this.melody = [];
    const rhythmA = Array.from({ length: 8 }, () => r() < 0.62);
    const rhythmB = Array.from({ length: 8 }, () => r() < 0.5);
    for (let bar = 0; bar < 8; bar++) {
      const rhythm = bar % 2 === 0 ? rhythmA : rhythmB;
      const notes: number[] = [];
      let deg = Math.floor(r() * 5);
      for (let i = 0; i < 8; i++) {
        if (!rhythm[i]) {
          notes.push(-1);
          continue;
        }
        deg = Math.max(0, Math.min(9, deg + Math.floor(r() * 3) - 1));
        const oct = Math.floor(deg / 5);
        notes.push(72 + SCALE[deg % 5] + oct * 12);
      }
      this.melody.push(notes);
    }
  }

  /** 0 = menu, 1 = match, 2 = late match, 3 = final moments */
  setIntensity(level: number) {
    this.intensity = level;
    const t = this.ctx.currentTime;
    const mix: Record<Layer, number[]> = {
      pluck: [0.5, 0.45, 0.45, 0.45],
      bass: [0.0, 0.55, 0.6, 0.65],
      drums: [0.0, 0.35, 0.55, 0.65],
      bells: [0.3, 0.22, 0.3, 0.35],
      arp: [0.0, 0.0, 0.18, 0.26],
      hats16: [0, 0, 0, 0.22],
    };
    for (const [l, g] of this.layers) {
      g.gain.setTargetAtTime(mix[l][level], t, 0.8);
      this.target.set(l, mix[l][level]);
    }
    this.targetTempo = [96, 112, 120, 128][level];
  }

  start() {
    if (this.playing) return;
    this.playing = true;
    this.nextTime = this.ctx.currentTime + 0.1;
    this.timer = window.setInterval(() => this.schedule(), 25);
  }
  stop() {
    this.playing = false;
    if (this.timer !== null) clearInterval(this.timer);
    this.timer = null;
    for (const g of this.layers.values()) g.gain.setTargetAtTime(0, this.ctx.currentTime, 0.2);
  }
  newSong() {
    this.makeMelody(Math.floor(Math.random() * 1000));
    this.step = 0;
  }

  private schedule() {
    if (!this.playing) return;
    // tempo glides toward the target for smooth intensity changes
    this.tempo += (this.targetTempo - this.tempo) * 0.02;
    while (this.nextTime < this.ctx.currentTime + 0.12) {
      this.playStep(this.step, this.nextTime);
      this.nextTime += 60 / this.tempo / 4; // 16th notes
      this.step = (this.step + 1) % (16 * 16);
    }
  }

  private playStep(step: number, t: number) {
    const bar = Math.floor(step / 16);
    const s = step % 16;
    const prog = bar % 8 < 4 ? PROG_A : PROG_B;
    const chord = prog[bar % 4];
    const sixteenth = 60 / this.tempo / 4;
    const L = (l: Layer) => this.layers.get(l)!;
    // plucked chord arpeggio on 8ths
    if (s % 2 === 0 && this.on('pluck')) {
      const n = chord[(s / 2) % 3] + (s % 8 === 6 ? 12 : 0);
      this.pluck(L('pluck'), midi(n), t, 0.25, 0.22);
    }
    // bass: bouncy root/fifth
    if ([0, 6, 8, 14].includes(s) && this.on('bass')) {
      const root = chord[0] - 24;
      const n = s === 6 || s === 14 ? root + 7 : root;
      this.bass(L('bass'), midi(n), t, sixteenth * (s === 0 || s === 8 ? 3.5 : 1.6));
    }
    // drums
    if (this.on('drums')) {
      if (s === 0 || s === 8 || (s === 10 && bar % 2 === 1)) this.kick(L('drums'), t);
      if (s === 4 || s === 12) this.snare(L('drums'), t);
      if (s % 2 === 0) this.hat(L('drums'), t, s % 4 === 2 ? 0.5 : 0.25);
    }
    if (s % 2 === 1 && this.on('hats16')) this.hat(L('hats16'), t, 0.25);
    // bells melody on 8ths
    if (s % 2 === 0 && this.on('bells')) {
      const n = this.melody[bar % 8][s / 2];
      if (n > 0) this.bell(L('bells'), midi(n), t);
    }
    // fast arp (late match)
    if (this.on('arp')) {
      const n = chord[s % 3] + 24;
      this.pluck(L('arp'), midi(n), t, 0.12, 0.12);
    }
  }

  private pluck(out: GainNode, f: number, t: number, dur: number, vol: number) {
    const c = this.ctx;
    const o = c.createOscillator();
    o.type = 'triangle';
    o.frequency.value = f;
    const lp = c.createBiquadFilter();
    lp.type = 'lowpass';
    lp.frequency.setValueAtTime(f * 6, t);
    lp.frequency.exponentialRampToValueAtTime(f * 1.5, t + dur);
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(lp).connect(g).connect(out);
    o.start(t);
    o.stop(t + dur + 0.02);
    o.onended = () => { o.disconnect(); lp.disconnect(); g.disconnect(); };
  }
  private bass(out: GainNode, f: number, t: number, dur: number) {
    const c = this.ctx;
    const o = c.createOscillator();
    o.type = 'sine';
    o.frequency.value = f;
    const o2 = c.createOscillator();
    o2.type = 'triangle';
    o2.frequency.value = f * 2;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.5, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    const g2 = c.createGain();
    g2.gain.value = 0.15;
    o.connect(g);
    o2.connect(g2).connect(g);
    g.connect(out);
    o.start(t);
    o2.start(t);
    o.stop(t + dur + 0.02);
    o2.stop(t + dur + 0.02);
    o.onended = () => { o.disconnect(); o2.disconnect(); g.disconnect(); g2.disconnect(); };
  }
  private kick(out: GainNode, t: number) {
    const c = this.ctx;
    const o = c.createOscillator();
    o.frequency.setValueAtTime(140, t);
    o.frequency.exponentialRampToValueAtTime(45, t + 0.12);
    const g = c.createGain();
    g.gain.setValueAtTime(0.9, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.18);
    o.connect(g).connect(out);
    o.start(t);
    o.stop(t + 0.2);
    o.onended = () => { o.disconnect(); g.disconnect(); };
  }
  private snare(out: GainNode, t: number) {
    const c = this.ctx;
    const s = c.createBufferSource();
    s.buffer = this.noiseBuf;
    const f = c.createBiquadFilter();
    f.type = 'bandpass';
    f.frequency.value = 1800;
    f.Q.value = 0.8;
    const g = c.createGain();
    g.gain.setValueAtTime(0.45, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.14);
    s.connect(f).connect(g).connect(out);
    s.start(t, Math.random() * 0.5);
    s.stop(t + 0.16);
    const o = c.createOscillator();
    o.type = 'triangle';
    o.frequency.setValueAtTime(200, t);
    o.frequency.exponentialRampToValueAtTime(120, t + 0.06);
    const g2 = c.createGain();
    g2.gain.setValueAtTime(0.3, t);
    g2.gain.exponentialRampToValueAtTime(0.0001, t + 0.08);
    o.connect(g2).connect(out);
    o.start(t);
    o.stop(t + 0.1);
    s.onended = () => { s.disconnect(); f.disconnect(); g.disconnect(); o.disconnect(); g2.disconnect(); };
  }
  private hat(out: GainNode, t: number, vol: number) {
    const c = this.ctx;
    const s = c.createBufferSource();
    s.buffer = this.noiseBuf;
    const f = c.createBiquadFilter();
    f.type = 'highpass';
    f.frequency.value = 7000;
    const g = c.createGain();
    g.gain.setValueAtTime(vol * 0.35, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.04);
    s.connect(f).connect(g).connect(out);
    s.start(t, Math.random() * 0.5);
    s.stop(t + 0.05);
    s.onended = () => { s.disconnect(); f.disconnect(); g.disconnect(); };
  }
  private bell(out: GainNode, f: number, t: number) {
    const c = this.ctx;
    const g = c.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.25, t + 0.005);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.7);
    g.connect(out);
    const os: OscillatorNode[] = [];
    for (const [m, a] of [[1, 1], [2.76, 0.25], [5.4, 0.08]] as const) {
      const o = c.createOscillator();
      o.type = 'sine';
      o.frequency.value = f * m;
      const og = c.createGain();
      og.gain.value = a;
      o.connect(og).connect(g);
      o.start(t);
      o.stop(t + 0.75);
      os.push(o);
      o.onended = () => { o.disconnect(); og.disconnect(); };
    }
    os[0].addEventListener('ended', () => g.disconnect());
  }
}

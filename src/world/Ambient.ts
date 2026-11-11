import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import type RAPIER from '@dimforge/rapier3d-compat';
import { Physics } from '../physics/Physics';
import { AudioEngine } from '../audio/Audio';
import { Effects } from '../fx/Effects';
import { plastic, metal, glow, rubber } from '../render/materials';
import { fanShadowTexture, softDotTexture } from '../render/textures';
import { ArenaInfo, ROOM, SHELF } from './Arena';
import { Actor } from '../entities/Actor';
import { rand, pick } from '../core/math';
import { NavGraph } from '../nav/NavGraph';

/**
 * Living room details: toy train on the high shelf, wind-up robots, rc cars, ceiling fan shadow,
 * sunbeam dust, volcano smoke, the wall clock, falling building blocks and ambient sound beats.
 */

interface RcCar {
  group: THREE.Group;
  body: RAPIER.RigidBody;
  angle: number;
  speed: number;
  pos: THREE.Vector3;
  yaw: number;
  hum: { move(p: THREE.Vector3, s: number): void; stop(): void } | null;
}
interface Robot {
  group: THREE.Group;
  legs: THREE.Object3D[];
  key: THREE.Object3D;
  a: THREE.Vector3;
  b: THREE.Vector3;
  t: number;
  dir: number;
  speed: number;
  pause: number;
}
interface Block {
  mesh: THREE.Mesh;
  body: RAPIER.RigidBody;
  life: number;
  hit: Set<number>;
  landed: boolean;
}
interface Warning {
  ring: THREE.Mesh;
  pos: THREE.Vector3;
  t: number;
  dropped: boolean;
}

const BEAM_VS = /* glsl */ `
varying vec3 vWorld;
void main() {
  vec4 w = modelMatrix * vec4(position, 1.0);
  vWorld = w.xyz;
  gl_Position = projectionMatrix * viewMatrix * w;
}`;
const BEAM_FS = /* glsl */ `
uniform float uTime;
uniform float uStrength;
varying vec3 vWorld;
void main() {
  float h = smoothstep(0.0, 9.0, vWorld.y) * (1.0 - smoothstep(22.0, 27.0, vWorld.y));
  float streak = 0.75 + 0.25 * sin(vWorld.x * 0.9 + vWorld.z * 0.4 + uTime * 0.3);
  float a = 0.045 * h * streak * uStrength;
  gl_FragColor = vec4(1.0, 0.86, 0.62, a);
}`;

export class Ambient {
  group = new THREE.Group();
  private trainCurve: THREE.CatmullRomCurve3;
  private trainCars: THREE.Group[] = [];
  private trainU = 0;
  private trainSpeed = 6;
  private trainStopT = 0;
  private trainWheels: THREE.Object3D[] = [];
  private fanBlades = new THREE.Group();
  private fanShadow: THREE.Mesh;
  private dust: THREE.Points;
  private dustVel: Float32Array;
  private beam: THREE.Mesh;
  private rc: RcCar[] = [];
  private robots: Robot[] = [];
  private clockHands: { s: THREE.Object3D; m: THREE.Object3D; h: THREE.Object3D } | null = null;
  private clockPos = new THREE.Vector3(-24, 15, ROOM.z1 - 0.3);
  private timers = { tick: 0, creak: rand(8, 20), wind: rand(4, 10), whistle: rand(20, 40), chug: 0, bird: rand(3, 8), smoke: rand(4, 9), clatter: rand(8, 16), smokeOn: 0 };
  private tock = false;
  blocks: Block[] = [];
  private warnings: Warning[] = [];
  private blockMat: THREE.Material[] = [];
  private blockGeo = new RoundedBoxGeometry(1.6, 1.6, 1.6, 2, 0.12);
  private time = 0;
  ambienceOn = false;
  private soundsOn = false;
  private reduced = false;

  constructor(scene: THREE.Scene, private arena: ArenaInfo, private phys: Physics, private fx: Effects, private audio: AudioEngine) {
    scene.add(this.group);
    // ------------------------------------------------ train track on the shelf
    const y = SHELF.y + 0.02;
    const ix = ROOM.x1 - SHELF.trackInset, iz = ROOM.z1 - SHELF.trackInset, r = 1.0;
    const pts: THREE.Vector3[] = [];
    const corner = (cx: number, cz: number, a0: number) => {
      for (let i = 0; i <= 4; i++) {
        const a = a0 + (i / 4) * (Math.PI / 2);
        pts.push(new THREE.Vector3(cx + Math.cos(a) * r, y, cz + Math.sin(a) * r));
      }
    };
    corner(ix - r, iz - r, 0);
    corner(-ix + r, iz - r, Math.PI / 2);
    corner(-ix + r, -iz + r, Math.PI);
    corner(ix - r, -iz + r, Math.PI * 1.5);
    this.trainCurve = new THREE.CatmullRomCurve3(pts, true, 'centripetal');
    this.buildTrack();
    this.buildTrain();
    // ------------------------------------------------ ceiling fan + fake rotating shadow over the sun patch
    const fan = new THREE.Group();
    fan.position.set(2, ROOM.h, 1);
    fan.add(new THREE.Mesh(new THREE.CylinderGeometry(0.15, 0.15, 2.4, 10), metal('#d9d9d9')));
    (fan.children[0] as THREE.Mesh).position.y = -1.2;
    const motor = new THREE.Mesh(new THREE.CylinderGeometry(0.9, 0.7, 0.8, 24), plastic('#ffffff', { rough: 0.4 }));
    motor.position.y = -2.6;
    fan.add(motor);
    this.fanBlades.position.y = -2.8;
    for (let i = 0; i < 4; i++) {
      const blade = new THREE.Mesh(new RoundedBoxGeometry(5.5, 0.12, 1.3, 2, 0.05), plastic('#e9d8bf', { rough: 0.6, clearcoat: 0 }));
      blade.position.set(Math.cos((i * Math.PI) / 2) * 3.4, 0, Math.sin((i * Math.PI) / 2) * 3.4);
      blade.rotation.y = -(i * Math.PI) / 2;
      blade.rotation.x = 0.12;
      this.fanBlades.add(blade);
    }
    fan.add(this.fanBlades);
    fan.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
    this.group.add(fan);
    this.fanShadow = new THREE.Mesh(
      new THREE.PlaneGeometry(18, 18),
      new THREE.MeshBasicMaterial({ map: fanShadowTexture(), color: '#000000', transparent: true, opacity: 0.35, depthWrite: false }),
    );
    this.fanShadow.rotation.x = -Math.PI / 2;
    this.fanShadow.position.set(10, 0.1, -2);
    this.fanShadow.renderOrder = 1;
    this.group.add(this.fanShadow);
    // ------------------------------------------------ sunbeam volume + dust motes
    const W = arena.window;
    const d = arena.sunDir;
    const proj = (p: THREE.Vector3) => p.clone().addScaledVector(d, (p.y - 0) / -d.y);
    const corners = [new THREE.Vector3(W.x0, W.y0, W.z + 0.2), new THREE.Vector3(W.x1, W.y0, W.z + 0.2), new THREE.Vector3(W.x1, W.y1, W.z + 0.2), new THREE.Vector3(W.x0, W.y1, W.z + 0.2)];
    const floor = corners.map(proj);
    const verts = [...corners, ...floor];
    const idx = [0, 1, 5, 0, 5, 4, 1, 2, 6, 1, 6, 5, 2, 3, 7, 2, 7, 6, 3, 0, 4, 3, 4, 7];
    const bg = new THREE.BufferGeometry().setFromPoints(verts);
    bg.setIndex(idx);
    this.beam = new THREE.Mesh(bg, new THREE.ShaderMaterial({ vertexShader: BEAM_VS, fragmentShader: BEAM_FS, uniforms: { uTime: { value: 0 }, uStrength: { value: 1 } }, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
    this.beam.renderOrder = 4;
    this.beam.frustumCulled = false;
    this.group.add(this.beam);
    const N = 420;
    const dp = new Float32Array(N * 3);
    this.dustVel = new Float32Array(N * 3);
    for (let i = 0; i < N; i++) {
      const p = this.randomBeamPoint();
      dp.set([p.x, p.y, p.z], i * 3);
      this.dustVel.set([rand(-0.05, 0.05), rand(-0.03, 0.03), rand(-0.05, 0.05)], i * 3);
    }
    const dg = new THREE.BufferGeometry();
    dg.setAttribute('position', new THREE.BufferAttribute(dp, 3).setUsage(THREE.DynamicDrawUsage));
    this.dust = new THREE.Points(dg, new THREE.PointsMaterial({ map: softDotTexture(), color: '#fff1d0', size: 0.09, transparent: true, opacity: 0.85, depthWrite: false, blending: THREE.AdditiveBlending, sizeAttenuation: true }));
    this.dust.frustumCulled = false;
    this.group.add(this.dust);
    // ------------------------------------------------ rc cars on the garage track
    for (let i = 0; i < 2; i++) {
      const g = this.buildRcCar(i === 0 ? '#ff006e' : '#3a86ff');
      this.group.add(g);
      const { body } = phys.kinematicBox(new THREE.Vector3(0, -20, 0), new THREE.Vector3(0.55, 0.4, 0.95), 'plastic');
      this.rc.push({ group: g, body, angle: i * Math.PI, speed: i === 0 ? 0.95 : 0.8, pos: new THREE.Vector3(), yaw: 0, hum: null });
    }
    // ------------------------------------------------ wind-up robots in the background
    const sill = ROOM.z0 + 1.2;
    this.robots.push(this.buildRobot('#e63946', new THREE.Vector3(-5, 12, sill), new THREE.Vector3(9, 12, sill)));
    // two more patrol the shelf walkway (they shove toys out of the way)
    const walk = SHELF.depth - 1.0;
    this.robots.push(this.buildRobot('#3a86ff', new THREE.Vector3(-26, SHELF.y, ROOM.z1 - walk), new THREE.Vector3(-8, SHELF.y, ROOM.z1 - walk)));
    this.robots.push(this.buildRobot('#06d6a0', new THREE.Vector3(ROOM.x0 + walk, SHELF.y, -22), new THREE.Vector3(ROOM.x0 + walk, SHELF.y, 8)));
    // ------------------------------------------------ wall clock
    this.buildClock();
    // block materials
    for (const [c, l] of [['#e63946', 'A'], ['#2a9d8f', 'B'], ['#f4a261', 'C'], ['#457b9d', 'D'], ['#8ab17d', 'E']] as const) {
      const cv = document.createElement('canvas');
      cv.width = cv.height = 128;
      const ctx = cv.getContext('2d')!;
      ctx.fillStyle = '#e8cfa5';
      ctx.fillRect(0, 0, 128, 128);
      ctx.fillStyle = c;
      ctx.fillRect(10, 10, 108, 108);
      ctx.fillStyle = '#fff';
      ctx.font = 'bold 80px "Luckiest Guy", Impact, sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(l, 64, 70);
      const t = new THREE.CanvasTexture(cv);
      t.colorSpace = THREE.SRGBColorSpace;
      this.blockMat.push(new THREE.MeshStandardMaterial({ map: t, roughness: 0.55 }));
    }
  }

  private randomBeamPoint() {
    const W = this.arena.window;
    const d = this.arena.sunDir;
    const p = new THREE.Vector3(rand(W.x0, W.x1), rand(W.y0, W.y1), W.z + 0.3);
    const k = rand(0.5, p.y / -d.y);
    return p.addScaledVector(d, k);
  }

  private buildTrack() {
    const N = 600;
    const rails: THREE.Vector3[][] = [[], []];
    const up = new THREE.Vector3(0, 1, 0);
    for (let i = 0; i < N; i++) {
      const u = i / N;
      const p = this.trainCurve.getPointAt(u);
      const t = this.trainCurve.getTangentAt(u);
      const side = new THREE.Vector3().crossVectors(t, up).normalize();
      rails[0].push(p.clone().addScaledVector(side, 0.28).setY(p.y + 0.12));
      rails[1].push(p.clone().addScaledVector(side, -0.28).setY(p.y + 0.12));
    }
    const railMat = metal('#b8bcc4', 0.3);
    for (const r of rails) {
      const m = new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(r, true), N, 0.04, 5, true), railMat);
      this.group.add(m);
    }
    const tieGeo = new THREE.BoxGeometry(0.85, 0.08, 0.18);
    const count = Math.floor(this.trainCurve.getLength() / 0.7);
    const ties = new THREE.InstancedMesh(tieGeo, new THREE.MeshStandardMaterial({ color: '#7b4a2a', roughness: 0.8 }), count);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    for (let i = 0; i < count; i++) {
      const u = i / count;
      const p = this.trainCurve.getPointAt(u);
      const t = this.trainCurve.getTangentAt(u);
      q.setFromUnitVectors(new THREE.Vector3(0, 0, 1), t);
      m.compose(p.clone().setY(p.y + 0.04), q, new THREE.Vector3(1, 1, 1));
      ties.setMatrixAt(i, m);
    }
    this.group.add(ties);
  }

  private buildTrain() {
    const colors = ['#d62828', '#f77f00', '#2a9d8f', '#3a86ff'];
    for (let i = 0; i < 4; i++) {
      const g = new THREE.Group();
      const c = plastic(colors[i], { rough: 0.25 });
      const bodyLen = i === 0 ? 2.2 : 1.8;
      const body = new THREE.Mesh(new RoundedBoxGeometry(1.1, 0.9, bodyLen, 2, 0.15), c);
      body.position.y = 0.75;
      g.add(body);
      if (i === 0) {
        const boiler = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, 1.3, 18), plastic('#1d3557'));
        boiler.rotation.x = Math.PI / 2;
        boiler.position.set(0, 1.0, 0.45);
        g.add(boiler);
        const stack = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.12, 0.6, 12), plastic('#222'));
        stack.position.set(0, 1.6, 0.8);
        g.add(stack);
        const cab = new THREE.Mesh(new RoundedBoxGeometry(1.1, 0.8, 0.8, 2, 0.12), c);
        cab.position.set(0, 1.55, -0.6);
        g.add(cab);
        const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.14, 10, 8), glow('#fff3b0', 3));
        lamp.position.set(0, 1.0, 1.15);
        g.add(lamp);
      } else {
        // cargo: blocks / balls
        const cargo = new THREE.Mesh(i === 2 ? new THREE.SphereGeometry(0.4, 14, 10) : new RoundedBoxGeometry(0.7, 0.6, 0.9, 2, 0.1), plastic(pick(['#ffbe0b', '#8338ec', '#06d6a0'])));
        cargo.position.y = 1.5;
        g.add(cargo);
      }
      for (const z of [-bodyLen * 0.3, bodyLen * 0.3])
        for (const x of [-0.5, 0.5]) {
          const w = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.22, 0.12, 14), rubber('#111'));
          w.rotation.z = Math.PI / 2;
          w.position.set(x, 0.3, z);
          g.add(w);
          this.trainWheels.push(w);
        }
      g.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
      this.group.add(g);
      this.trainCars.push(g);
    }
  }

  private buildRcCar(color: string) {
    const g = new THREE.Group();
    const body = new THREE.Mesh(new RoundedBoxGeometry(1.1, 0.45, 1.9, 2, 0.15), plastic(color, { rough: 0.2, clearcoat: 1 }));
    body.position.y = 0.45;
    g.add(body);
    const top = new THREE.Mesh(new RoundedBoxGeometry(0.9, 0.35, 0.8, 2, 0.12), plastic('#111827', { rough: 0.1 }));
    top.position.set(0, 0.8, -0.1);
    g.add(top);
    const spoiler = new THREE.Mesh(new THREE.BoxGeometry(1.1, 0.06, 0.3), plastic('#ffbe0b'));
    spoiler.position.set(0, 0.95, -0.85);
    g.add(spoiler);
    const ant = new THREE.Mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.8, 6), metal('#ccc'));
    ant.position.set(0.35, 1.1, -0.6);
    g.add(ant);
    for (const z of [-0.6, 0.6])
      for (const x of [-0.55, 0.55]) {
        const w = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.28, 0.25, 16), rubber('#1d1d1d'));
        w.rotation.z = Math.PI / 2;
        w.position.set(x, 0.28, z);
        g.add(w);
      }
    g.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
    return g;
  }

  private buildRobot(color: string, a: THREE.Vector3, b: THREE.Vector3): Robot {
    const g = new THREE.Group();
    const c = plastic(color, { rough: 0.3, metal: 0.2 });
    const body = new THREE.Mesh(new RoundedBoxGeometry(0.7, 0.8, 0.5, 2, 0.08), c);
    body.position.y = 0.9;
    g.add(body);
    const head = new THREE.Mesh(new RoundedBoxGeometry(0.55, 0.45, 0.45, 2, 0.08), metal('#c0c6d0', 0.3));
    head.position.y = 1.55;
    g.add(head);
    for (const x of [-0.12, 0.12]) {
      const e = new THREE.Mesh(new THREE.SphereGeometry(0.06, 8, 6), glow('#fff07a', 2.5));
      e.position.set(x, 1.6, 0.23);
      g.add(e);
    }
    const legs: THREE.Object3D[] = [];
    for (const x of [-0.18, 0.18]) {
      const leg = new THREE.Group();
      leg.position.set(x, 0.5, 0);
      const l = new THREE.Mesh(new RoundedBoxGeometry(0.18, 0.5, 0.22, 2, 0.05), metal('#8d99ae', 0.4));
      l.position.y = -0.25;
      leg.add(l);
      g.add(leg);
      legs.push(leg);
    }
    const key = new THREE.Group();
    key.position.set(0, 1.0, -0.3);
    key.add(new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.25, 8), metal('#d4af37')).rotateX(Math.PI / 2));
    const bow = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.04, 6, 16), metal('#d4af37'));
    bow.position.z = -0.18;
    key.add(bow);
    g.add(key);
    g.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
    g.position.copy(a);
    this.group.add(g);
    return { group: g, legs, key, a, b, t: Math.random(), dir: 1, speed: rand(0.6, 0.9), pause: 0 };
  }

  private buildClock() {
    const g = new THREE.Group();
    g.position.copy(this.clockPos);
    const face = new THREE.Mesh(new THREE.CylinderGeometry(2.2, 2.2, 0.3, 40), plastic('#ffffff', { rough: 0.4 }));
    face.rotation.x = Math.PI / 2;
    g.add(face);
    const rim = new THREE.Mesh(new THREE.TorusGeometry(2.2, 0.22, 10, 40), plastic('#ef476f'));
    g.add(rim);
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      const tick = new THREE.Mesh(new THREE.BoxGeometry(0.12, i % 3 === 0 ? 0.45 : 0.25, 0.05), plastic('#1d3557'));
      tick.position.set(Math.sin(a) * 1.8, Math.cos(a) * 1.8, -0.18);
      tick.rotation.z = -a;
      g.add(tick);
    }
    const hand = (len: number, w: number, col: string) => {
      const h = new THREE.Group();
      const m = new THREE.Mesh(new THREE.BoxGeometry(w, len, 0.05), plastic(col));
      m.position.y = len / 2 - 0.15;
      h.add(m);
      h.position.z = -0.22;
      g.add(h);
      return h;
    };
    this.clockHands = { h: hand(1.1, 0.14, '#1d3557'), m: hand(1.6, 0.09, '#1d3557'), s: hand(1.7, 0.04, '#e63946') };
    g.rotation.y = Math.PI;
    this.group.add(g);
  }

  /** Falling block event: marks landing spots, then drops wooden blocks from the ceiling. */
  blockDrop(nav: NavGraph, count = 8) {
    for (let i = 0; i < count; i++) {
      const id = nav.random((n) => n.pos.y < 0.5 && n.open >= 7);
      const p = nav.nodes[id]?.pos;
      if (!p) continue;
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.2, 1.1, 32), new THREE.MeshBasicMaterial({ color: '#ff4d4d', transparent: true, opacity: 0.0, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
      ring.rotation.x = -Math.PI / 2;
      ring.position.set(p.x, p.y + 0.06, p.z);
      this.group.add(ring);
      this.warnings.push({ ring, pos: p.clone(), t: -i * 0.35, dropped: false });
    }
  }

  private spawnBlock(p: THREE.Vector3) {
    const { body } = this.phys.dynamicBox(new THREE.Vector3(p.x, 26, p.z), new THREE.Vector3(0.8, 0.8, 0.8), 'wood', 0.8, new THREE.Euler(rand(0, 1), rand(0, 3), rand(0, 1)));
    body.setLinvel({ x: 0, y: -6, z: 0 }, true);
    body.setAngvel({ x: rand(-2, 2), y: rand(-2, 2), z: rand(-2, 2) }, true);
    const mesh = new THREE.Mesh(this.blockGeo, pick(this.blockMat));
    mesh.castShadow = mesh.receiveShadow = true;
    this.group.add(mesh);
    this.blocks.push({ mesh, body, life: 40, hit: new Set(), landed: false });
  }

  clearBlocks() {
    for (const b of this.blocks) {
      this.phys.removeBody(b.body);
      this.group.remove(b.mesh);
    }
    this.blocks = [];
    for (const w of this.warnings) {
      this.group.remove(w.ring);
      w.ring.geometry.dispose();
    }
    this.warnings = [];
  }

  startSounds() {
    if (this.soundsOn) return;
    this.soundsOn = true;
    for (const c of this.rc) c.hum = this.audio.motorLoop(c.pos);
  }
  stopSounds() {
    this.soundsOn = false;
    for (const c of this.rc) {
      c.hum?.stop();
      c.hum = null;
    }
  }

  setReducedMotion(r: boolean) {
    this.reduced = r;
  }

  update(dt: number, actors: Actor[], hurt: (a: Actor, dmg: number, pos: THREE.Vector3) => void, listener: THREE.Vector3) {
    this.time += dt;
    const t = this.time;
    // train: runs, pauses at the "station" now and then
    if (this.trainStopT > 0) this.trainStopT -= dt;
    else {
      this.trainU = (this.trainU + (this.trainSpeed * dt) / this.trainCurve.getLength()) % 1;
      if (Math.random() < dt * 0.01) this.trainStopT = rand(4, 9);
    }
    const len = this.trainCurve.getLength();
    this.trainCars.forEach((car, i) => {
      const u = (this.trainU - (i * 2.4) / len + 1) % 1;
      const p = this.trainCurve.getPointAt(u);
      const tan = this.trainCurve.getTangentAt(u);
      car.position.copy(p);
      car.rotation.y = Math.atan2(tan.x, tan.z);
    });
    if (this.trainStopT <= 0) for (const w of this.trainWheels) w.rotation.x += dt * this.trainSpeed * 4;
    // the train shoves toys off its track (toward the room side)
    if (this.trainStopT <= 0) {
      this.trainCars.forEach((car, i) => {
        const yaw = car.rotation.y;
        const fx = Math.sin(yaw), fz = Math.cos(yaw);
        const sx = fz, sz = -fx; // lateral axis
        const hl = (i === 0 ? 1.1 : 0.9) + 0.42, hw = 0.55 + 0.42;
        // which lateral side faces the middle of the room
        const inward = Math.sign((2 - car.position.x) * sx + (1 - car.position.z) * sz) || 1;
        for (const a of actors) {
          if (!a.alive || Math.abs(a.pos.y - SHELF.y) > 1.3) continue;
          const dx = a.pos.x - car.position.x, dz = a.pos.z - car.position.z;
          const lf = dx * fx + dz * fz, ls = dx * sx + dz * sz;
          if (Math.abs(lf) > hl || Math.abs(ls) > hw) continue;
          const push = inward * hw - ls;
          a.pos.x += sx * push + fx * 0.05;
          a.pos.z += sz * push + fz * 0.05;
          a.vel.x += sx * inward * 2.5 + fx * this.trainSpeed * 0.4;
          a.vel.z += sz * inward * 2.5 + fz * this.trainSpeed * 0.4;
          a.sync();
        }
      });
    }
    // fan
    this.fanBlades.rotation.y += dt * (this.reduced ? 1.2 : 2.6);
    this.fanShadow.rotation.z = this.fanBlades.rotation.y;
    (this.beam.material as THREE.ShaderMaterial).uniforms.uTime.value = t;
    // dust
    const pa = this.dust.geometry.getAttribute('position') as THREE.BufferAttribute;
    const arr = pa.array as Float32Array;
    for (let i = 0; i < arr.length; i += 3) {
      arr[i] += (this.dustVel[i] + Math.sin(t * 0.3 + i) * 0.02) * dt;
      arr[i + 1] += (this.dustVel[i + 1] + Math.sin(t * 0.21 + i * 0.7) * 0.015) * dt;
      arr[i + 2] += this.dustVel[i + 2] * dt;
      if (arr[i + 1] < 0.3 || arr[i + 1] > 27 || Math.random() < dt * 0.01) {
        const p = this.randomBeamPoint();
        arr[i] = p.x;
        arr[i + 1] = p.y;
        arr[i + 2] = p.z;
      }
    }
    pa.needsUpdate = true;
    // rc cars
    for (const c of this.rc) {
      c.angle += dt * c.speed;
      const x = 17 + Math.cos(c.angle) * 8.4, z = 18.5 + Math.sin(c.angle) * 4.2;
      const tx = -Math.sin(c.angle) * 8.4, tz = Math.cos(c.angle) * 4.2;
      c.yaw = Math.atan2(tx, tz);
      c.pos.set(x, 0, z);
      c.group.position.copy(c.pos);
      c.group.rotation.y = c.yaw;
      c.group.rotation.z = Math.sin(t * 20) * 0.01;
      const q = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, c.yaw, 0));
      c.body.setNextKinematicTranslation({ x, y: 0.45, z });
      c.body.setNextKinematicRotation({ x: q.x, y: q.y, z: q.z, w: q.w });
      c.hum?.move(c.pos.clone().setY(0.5), Math.hypot(tx, tz) * c.speed);
      // bump toys out of the way
      const cos = Math.cos(-c.yaw), sin = Math.sin(-c.yaw);
      for (const a of actors) {
        if (!a.alive || a.pos.y > 1.2) continue;
        const dx = a.pos.x - x, dz = a.pos.z - z;
        const lx = dx * cos + dz * sin, lz = -dx * sin + dz * cos;
        const hx = 0.55 + 0.42, hz = 0.95 + 0.42;
        if (Math.abs(lx) < hx && Math.abs(lz) < hz) {
          const px = hx - Math.abs(lx), pz = hz - Math.abs(lz);
          let ox = 0, oz = 0;
          if (px < pz) ox = Math.sign(lx) * px;
          else oz = Math.sign(lz) * pz;
          const wx = ox * Math.cos(c.yaw) + oz * Math.sin(c.yaw);
          const wz = -ox * Math.sin(c.yaw) + oz * Math.cos(c.yaw);
          a.pos.x += wx;
          a.pos.z += wz;
          a.vel.x += wx * 8 + Math.sin(c.yaw) * 2;
          a.vel.z += wz * 8 + Math.cos(c.yaw) * 2;
          a.sync();
        }
      }
    }
    // robots
    for (const r of this.robots) {
      if (r.pause > 0) {
        r.pause -= dt;
        r.key.rotation.z += dt * 1;
        continue;
      }
      const L = r.a.distanceTo(r.b);
      r.t += (r.dir * r.speed * dt) / L;
      if (r.t > 1 || r.t < 0) {
        r.dir *= -1;
        r.t = Math.max(0, Math.min(1, r.t));
        r.pause = rand(1, 3);
      }
      r.group.position.lerpVectors(r.a, r.b, r.t);
      for (const a of actors) {
        if (!a.alive || Math.abs(a.pos.y - r.group.position.y) > 1.2) continue;
        const dx = a.pos.x - r.group.position.x, dz = a.pos.z - r.group.position.z;
        const d = Math.hypot(dx, dz);
        const min = 0.42 + 0.4;
        if (d >= min) continue;
        const nx = d > 1e-3 ? dx / d : 1, nz = d > 1e-3 ? dz / d : 0;
        a.pos.x += nx * (min - d);
        a.pos.z += nz * (min - d);
        a.sync();
      }
      const dir = r.b.clone().sub(r.a).multiplyScalar(r.dir);
      r.group.rotation.y = Math.atan2(dir.x, dir.z);
      r.legs[0].rotation.x = Math.sin(t * 9) * 0.5;
      r.legs[1].rotation.x = -Math.sin(t * 9) * 0.5;
      r.group.position.y += Math.abs(Math.sin(t * 9)) * 0.05;
      r.key.rotation.z += dt * 6;
    }
    // clock (game time)
    if (this.clockHands) {
      const sec = Math.floor(t);
      this.clockHands.s.rotation.z = -(sec / 60) * Math.PI * 2;
      this.clockHands.m.rotation.z = -((t / 3600) * Math.PI * 2 + 1.1);
      this.clockHands.h.rotation.z = -((t / 43200) * Math.PI * 2 + 4.3);
    }
    // block-drop warnings and falling blocks
    for (let i = this.warnings.length - 1; i >= 0; i--) {
      const w = this.warnings[i];
      w.t += dt;
      const m = w.ring.material as THREE.MeshBasicMaterial;
      if (w.t > 0) {
        m.opacity = Math.min(0.75, w.t) * (0.7 + Math.sin(w.t * 14) * 0.3);
        w.ring.scale.setScalar(0.6 + Math.min(1, w.t / 1.5) * 0.6);
      }
      if (w.t > 1.6 && !w.dropped) {
        w.dropped = true;
        this.spawnBlock(w.pos);
      }
      if (w.t > 3) {
        this.group.remove(w.ring);
        w.ring.geometry.dispose();
        m.dispose();
        this.warnings.splice(i, 1);
      }
    }
    for (let i = this.blocks.length - 1; i >= 0; i--) {
      const b = this.blocks[i];
      const p = b.body.translation();
      const r = b.body.rotation();
      b.mesh.position.set(p.x, p.y, p.z);
      b.mesh.quaternion.set(r.x, r.y, r.z, r.w);
      const v = b.body.linvel();
      if (v.y < -7) {
        for (const a of actors) {
          if (!a.alive || b.hit.has(a.id)) continue;
          const dx = a.pos.x - p.x, dz = a.pos.z - p.z;
          if (dx * dx + dz * dz < 1.5 && p.y - 0.8 < a.pos.y + 1.8 && p.y + 0.8 > a.pos.y) {
            b.hit.add(a.id);
            hurt(a, 40, new THREE.Vector3(p.x, p.y, p.z));
          }
        }
      } else if (!b.landed && p.y < 3 && Math.abs(v.y) < 3) {
        b.landed = true;
        this.audio.blockLand(new THREE.Vector3(p.x, p.y, p.z));
        this.fx.impact(new THREE.Vector3(p.x, p.y - 0.8, p.z), new THREE.Vector3(0, 1, 0), 'wood', { big: true, decal: false });
      }
      b.life -= dt;
      if (b.life < 1) b.mesh.scale.setScalar(Math.max(0.01, b.life));
      if (b.life <= 0 || p.y < -5) {
        this.phys.removeBody(b.body);
        this.group.remove(b.mesh);
        this.blocks.splice(i, 1);
      }
    }
    // volcano smoke + embers
    this.timers.smoke -= dt;
    if (this.timers.smoke <= 0) {
      this.timers.smoke = rand(7, 14);
      this.timers.smokeOn = 2.5;
      if (this.ambienceOn) this.audio.rumble(new THREE.Vector3(-23, 8, 29));
    }
    if (this.timers.smokeOn > 0) {
      this.timers.smokeOn -= dt;
      if (Math.random() < dt * 30) this.fx.soft.emit(new THREE.Vector3(-23 + rand(-0.6, 0.6), 7.6, 29 + rand(-0.6, 0.6)), new THREE.Vector3(rand(-0.3, 0.3), rand(1.5, 2.5), rand(-0.3, 0.3)), new THREE.Color(pick(['#e9e3dc', '#cfc7be', '#f7f2ec'])), rand(1.2, 2), rand(2.5, 4), { grow: 1.4, drag: 0.4, alpha: 0.55 });
      if (Math.random() < dt * 25) this.fx.glow.emit(new THREE.Vector3(-23, 7.4, 29), new THREE.Vector3(rand(-1.5, 1.5), rand(3, 6), rand(-1.5, 1.5)), new THREE.Color(pick(['#ff7b00', '#ffb703', '#ff4d00'])), rand(0.1, 0.2), rand(0.8, 1.4), { gravity: 4 });
    }
    // ambient sound beats
    if (this.ambienceOn) this.ambientSounds(dt, listener);
  }

  private ambientSounds(dt: number, listener: THREE.Vector3) {
    const tm = this.timers;
    tm.tick -= dt;
    if (tm.tick <= 0) {
      tm.tick += 1;
      this.tock = !this.tock;
      this.audio.clockTick(this.clockPos, this.tock);
    }
    tm.creak -= dt;
    if (tm.creak <= 0) {
      tm.creak = rand(14, 32);
      this.audio.creak(this.audio.randomCreakSpot());
    }
    tm.wind -= dt;
    if (tm.wind <= 0) {
      tm.wind = rand(6, 14);
      this.audio.windUp(pick(this.robots).group.position);
    }
    const engine = this.trainCars[0].position;
    tm.whistle -= dt;
    if (tm.whistle <= 0) {
      tm.whistle = rand(30, 60);
      this.audio.trainWhistle(engine);
    }
    if (this.trainStopT <= 0 && engine.distanceTo(listener) < 40) {
      tm.chug -= dt;
      if (tm.chug <= 0) {
        tm.chug = 0.36;
        this.audio.trainChug(engine);
      }
    }
    tm.bird -= dt;
    if (tm.bird <= 0) {
      tm.bird = rand(4, 9);
      this.audio.bird(new THREE.Vector3(rand(-31, -8), rand(4, 9), rand(13, 35)));
    }
    tm.clatter -= dt;
    if (tm.clatter <= 0) {
      tm.clatter = rand(10, 22);
      this.audio.clatter(new THREE.Vector3(rand(-30, -14), 1, rand(-6, 9)));
    }
  }
}

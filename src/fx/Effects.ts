import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { softDotTexture, decalTexture } from '../render/textures';
import type { SurfaceMat } from '../physics/Physics';
import { rand, pick } from '../core/math';

/**
 * Pooled visual effects: soft particles, bouncing plastic chips and springs, decals, tracers, flash lights.
 * Nothing here allocates per frame once warmed up.
 */

const PARTICLE_VS = /* glsl */ `
attribute float aSize;
attribute float aAlpha;
attribute vec3 aColor;
varying float vAlpha;
varying vec3 vColor;
uniform float uScale;
void main() {
  vec4 mv = modelViewMatrix * vec4(position, 1.0);
  gl_Position = projectionMatrix * mv;
  gl_PointSize = aSize * uScale / max(0.1, -mv.z);
  vAlpha = aAlpha;
  vColor = aColor;
}`;
const PARTICLE_FS = /* glsl */ `
uniform sampler2D uMap;
varying float vAlpha;
varying vec3 vColor;
void main() {
  vec4 t = texture2D(uMap, gl_PointCoord);
  float a = t.a * vAlpha;
  if (a < 0.01) discard;
  gl_FragColor = vec4(vColor * t.rgb, a);
}`;

class ParticlePool {
  points: THREE.Points;
  private pos: Float32Array;
  private col: Float32Array;
  private size: Float32Array;
  private alpha: Float32Array;
  private vel: Float32Array;
  private life: Float32Array;
  private max: Float32Array;
  private grow: Float32Array;
  private grav: Float32Array;
  private drag: Float32Array;
  private a0: Float32Array;
  private next = 0;
  private active = 0;
  mat: THREE.ShaderMaterial;
  constructor(public n: number, additive: boolean) {
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(n * 3);
    this.col = new Float32Array(n * 3);
    this.size = new Float32Array(n);
    this.alpha = new Float32Array(n);
    this.vel = new Float32Array(n * 3);
    this.life = new Float32Array(n);
    this.max = new Float32Array(n);
    this.grow = new Float32Array(n);
    this.grav = new Float32Array(n);
    this.drag = new Float32Array(n);
    this.a0 = new Float32Array(n);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aColor', new THREE.BufferAttribute(this.col, 3).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aSize', new THREE.BufferAttribute(this.size, 1).setUsage(THREE.DynamicDrawUsage));
    g.setAttribute('aAlpha', new THREE.BufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    this.mat = new THREE.ShaderMaterial({
      vertexShader: PARTICLE_VS,
      fragmentShader: PARTICLE_FS,
      uniforms: { uMap: { value: softDotTexture() }, uScale: { value: 400 } },
      transparent: true,
      depthWrite: false,
      blending: additive ? THREE.AdditiveBlending : THREE.NormalBlending,
    });
    this.points = new THREE.Points(g, this.mat);
    this.points.frustumCulled = false;
    this.points.renderOrder = additive ? 3 : 2;
  }
  emit(p: THREE.Vector3, v: THREE.Vector3, color: THREE.Color, size: number, life: number, opts: { grow?: number; gravity?: number; drag?: number; alpha?: number } = {}) {
    const i = this.next;
    this.next = (this.next + 1) % this.n;
    this.pos.set([p.x, p.y, p.z], i * 3);
    this.vel.set([v.x, v.y, v.z], i * 3);
    this.col.set([color.r, color.g, color.b], i * 3);
    this.size[i] = size;
    this.life[i] = life;
    this.max[i] = life;
    this.grow[i] = opts.grow ?? 0;
    this.grav[i] = opts.gravity ?? 0;
    this.drag[i] = opts.drag ?? 0;
    this.a0[i] = opts.alpha ?? 1;
    this.alpha[i] = this.a0[i];
    this.active = Math.max(this.active, 1);
  }
  update(dt: number) {
    let any = false;
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0) {
        if (this.alpha[i] !== 0) this.alpha[i] = 0;
        continue;
      }
      any = true;
      this.life[i] -= dt;
      const k = Math.max(0, this.life[i] / this.max[i]);
      const d = Math.max(0, 1 - this.drag[i] * dt);
      this.vel[i * 3] *= d;
      this.vel[i * 3 + 1] = this.vel[i * 3 + 1] * d - this.grav[i] * dt;
      this.vel[i * 3 + 2] *= d;
      this.pos[i * 3] += this.vel[i * 3] * dt;
      this.pos[i * 3 + 1] += this.vel[i * 3 + 1] * dt;
      this.pos[i * 3 + 2] += this.vel[i * 3 + 2] * dt;
      this.size[i] += this.grow[i] * dt;
      this.alpha[i] = this.a0[i] * (k < 0.6 ? k / 0.6 : 1);
    }
    if (any || this.active) {
      const g = this.points.geometry;
      (g.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true;
      (g.getAttribute('aColor') as THREE.BufferAttribute).needsUpdate = true;
      (g.getAttribute('aSize') as THREE.BufferAttribute).needsUpdate = true;
      (g.getAttribute('aAlpha') as THREE.BufferAttribute).needsUpdate = true;
      this.active = any ? 1 : 0;
    }
  }
  clear() {
    this.life.fill(0);
    this.alpha.fill(0);
  }
}

/** Physical-ish bouncing pieces drawn with one InstancedMesh. */
class ChipPool {
  mesh: THREE.InstancedMesh;
  private p: THREE.Vector3[] = [];
  private v: THREE.Vector3[] = [];
  private r: THREE.Euler[] = [];
  private w: THREE.Vector3[] = [];
  private s: THREE.Vector3[] = [];
  private life: number[] = [];
  private floor: number[] = [];
  private next = 0;
  private m = new THREE.Matrix4();
  private q = new THREE.Quaternion();
  private zero = new THREE.Matrix4().makeScale(0, 0, 0);
  private dirty = true;
  constructor(public n: number, geo: THREE.BufferGeometry, mat: THREE.Material) {
    this.mesh = new THREE.InstancedMesh(geo, mat, n);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.castShadow = true;
    this.mesh.frustumCulled = false;
    for (let i = 0; i < n; i++) {
      this.p.push(new THREE.Vector3());
      this.v.push(new THREE.Vector3());
      this.r.push(new THREE.Euler());
      this.w.push(new THREE.Vector3());
      this.s.push(new THREE.Vector3(1, 1, 1));
      this.life.push(0);
      this.floor.push(0);
      this.mesh.setMatrixAt(i, this.zero);
      this.mesh.setColorAt(i, new THREE.Color(1, 1, 1));
    }
  }
  emit(pos: THREE.Vector3, vel: THREE.Vector3, color: THREE.ColorRepresentation, size: THREE.Vector3, life: number, floorY: number) {
    const i = this.next;
    this.next = (this.next + 1) % this.n;
    this.p[i].copy(pos);
    this.v[i].copy(vel);
    this.r[i].set(Math.random() * 6, Math.random() * 6, Math.random() * 6);
    this.w[i].set(rand(-12, 12), rand(-12, 12), rand(-12, 12));
    this.s[i].copy(size);
    this.life[i] = life;
    this.floor[i] = floorY;
    this.mesh.setColorAt(i, new THREE.Color(color));
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
    this.dirty = true;
  }
  update(dt: number) {
    let any = false;
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0) continue;
      any = true;
      this.life[i] -= dt;
      const p = this.p[i], v = this.v[i];
      v.y -= 18 * dt;
      p.addScaledVector(v, dt);
      const half = this.s[i].y * 0.5;
      if (p.y < this.floor[i] + half && v.y < 0) {
        p.y = this.floor[i] + half;
        v.y *= -0.38;
        v.x *= 0.7;
        v.z *= 0.7;
        this.w[i].multiplyScalar(0.6);
        if (Math.abs(v.y) < 0.6) v.y = 0;
      }
      this.r[i].x += this.w[i].x * dt;
      this.r[i].y += this.w[i].y * dt;
      this.r[i].z += this.w[i].z * dt;
      const fade = Math.min(1, this.life[i] / 0.4);
      this.q.setFromEuler(this.r[i]);
      this.m.compose(p, this.q, this.s[i].clone().multiplyScalar(fade));
      this.mesh.setMatrixAt(i, this.life[i] > 0 ? this.m : this.zero);
    }
    if (any || this.dirty) {
      this.mesh.instanceMatrix.needsUpdate = true;
      this.dirty = any;
    }
  }
  clear() {
    for (let i = 0; i < this.n; i++) {
      this.life[i] = 0;
      this.mesh.setMatrixAt(i, this.zero);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
  }
}

const DECAL_VS = /* glsl */ `
attribute float aAlpha;
varying float vAlpha;
varying vec2 vUv;
varying vec3 vCol;
void main() {
  vUv = uv;
  vAlpha = aAlpha;
  #ifdef USE_INSTANCING_COLOR
  vCol = instanceColor;
  #else
  vCol = vec3(1.0);
  #endif
  gl_Position = projectionMatrix * modelViewMatrix * instanceMatrix * vec4(position, 1.0);
}`;
const DECAL_FS = /* glsl */ `
uniform sampler2D uMap;
varying float vAlpha;
varying vec2 vUv;
varying vec3 vCol;
void main() {
  vec4 t = texture2D(uMap, vUv);
  float a = t.a * vAlpha;
  if (a < 0.01) discard;
  gl_FragColor = vec4(vCol, a);
  #include <colorspace_fragment>
}`;

class DecalPool {
  mesh: THREE.InstancedMesh;
  private alpha: Float32Array;
  private life: Float32Array;
  private max: Float32Array;
  private a0: Float32Array;
  private next = 0;
  private m = new THREE.Matrix4();
  private q = new THREE.Quaternion();
  constructor(public n: number, tex: THREE.Texture, private fade: number) {
    const geo = new THREE.PlaneGeometry(1, 1);
    this.alpha = new Float32Array(n);
    this.life = new Float32Array(n);
    this.max = new Float32Array(n);
    this.a0 = new Float32Array(n);
    geo.setAttribute('aAlpha', new THREE.InstancedBufferAttribute(this.alpha, 1).setUsage(THREE.DynamicDrawUsage));
    const mat = new THREE.ShaderMaterial({
      vertexShader: DECAL_VS,
      fragmentShader: DECAL_FS,
      uniforms: { uMap: { value: tex } },
      transparent: true,
      depthWrite: false,
      polygonOffset: true,
      polygonOffsetFactor: -4,
      polygonOffsetUnits: -4,
    });
    this.mesh = new THREE.InstancedMesh(geo, mat, n);
    this.mesh.frustumCulled = false;
    this.mesh.renderOrder = 1;
    const zero = new THREE.Matrix4().makeScale(0, 0, 0);
    for (let i = 0; i < n; i++) {
      this.mesh.setMatrixAt(i, zero);
      this.mesh.setColorAt(i, new THREE.Color(0, 0, 0));
    }
  }
  add(p: THREE.Vector3, normal: THREE.Vector3, size: number, color: THREE.ColorRepresentation, life: number, alpha = 1) {
    const i = this.next;
    this.next = (this.next + 1) % this.n;
    this.q.setFromUnitVectors(new THREE.Vector3(0, 0, 1), normal);
    const spin = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.random() * Math.PI * 2);
    this.q.multiply(spin);
    this.m.compose(p.clone().addScaledVector(normal, 0.02), this.q, new THREE.Vector3(size, size, size));
    this.mesh.setMatrixAt(i, this.m);
    this.mesh.setColorAt(i, new THREE.Color(color));
    this.mesh.instanceMatrix.needsUpdate = true;
    if (this.mesh.instanceColor) this.mesh.instanceColor.needsUpdate = true;
    this.life[i] = life;
    this.max[i] = life;
    this.a0[i] = alpha;
    this.alpha[i] = alpha;
  }
  update(dt: number) {
    let any = false;
    for (let i = 0; i < this.n; i++) {
      if (this.life[i] <= 0) continue;
      any = true;
      this.life[i] -= dt;
      this.alpha[i] = this.a0[i] * Math.min(1, Math.max(0, this.life[i]) / this.fade);
    }
    if (any) (this.mesh.geometry.getAttribute('aAlpha') as THREE.BufferAttribute).needsUpdate = true;
  }
  clear() {
    this.life.fill(0);
    this.alpha.fill(0);
    (this.mesh.geometry.getAttribute('aAlpha') as THREE.BufferAttribute).needsUpdate = true;
  }
}

interface Tracer {
  mesh: THREE.Mesh;
  life: number;
  max: number;
  from: THREE.Vector3;
  to: THREE.Vector3;
  travel: number; // seconds for the streak head to reach the end (0 = instant beam)
  width: number;
}

const MAT_COLORS: Record<SurfaceMat, string[]> = {
  plastic: ['#ff5d73', '#ffd166', '#06d6a0', '#4cc9f0', '#ffffff'],
  wood: ['#c89f73', '#a87b51', '#e2c49c'],
  fabric: ['#f1e6ff', '#d8e2ff', '#ffe5ec'],
  carpet: ['#f2e6d0', '#d6c7a8'],
  metal: ['#fff3b0', '#ffd166', '#ffffff'],
  cardboard: ['#d4a373', '#e9c46a', '#f1dca7'],
  glass: ['#e0fbfc', '#ffffff', '#c2f0ff'],
};

export class Effects {
  group = new THREE.Group();
  soft: ParticlePool;
  glow: ParticlePool;
  chips: ChipPool;
  springs: ChipPool;
  impacts: DecalPool;
  splats: DecalPool;
  private tracers: Tracer[] = [];
  private tracerGeo: THREE.BufferGeometry;
  lights: { light: THREE.PointLight; life: number; max: number; i0: number }[] = [];
  private trails: { mesh: THREE.Mesh; life: number; max: number }[] = [];
  reducedMotion = false;

  constructor(scene: THREE.Scene) {
    scene.add(this.group);
    this.soft = new ParticlePool(1400, false);
    this.glow = new ParticlePool(1200, true);
    this.group.add(this.soft.points, this.glow.points);
    const chipGeo = new RoundedBoxGeometry(1, 1, 1, 1, 0.15);
    this.chips = new ChipPool(500, chipGeo, new THREE.MeshPhysicalMaterial({ roughness: 0.35, clearcoat: 0.6 }));
    const helix = new THREE.CatmullRomCurve3(Array.from({ length: 30 }, (_, i) => new THREE.Vector3(Math.cos(i * 0.9) * 0.5, i / 30 - 0.5, Math.sin(i * 0.9) * 0.5)));
    const springGeo = new THREE.TubeGeometry(helix, 60, 0.07, 6, false);
    this.springs = new ChipPool(48, springGeo, new THREE.MeshStandardMaterial({ color: '#d9dde3', metalness: 1, roughness: 0.25 }));
    this.group.add(this.chips.mesh, this.springs.mesh);
    this.impacts = new DecalPool(220, decalTexture('impact'), 2.5);
    this.splats = new DecalPool(70, decalTexture('splat'), 3);
    this.group.add(this.impacts.mesh, this.splats.mesh);
    this.tracerGeo = new THREE.BoxGeometry(1, 1, 1);
    this.tracerGeo.translate(0, 0, 0.5);
    for (let i = 0; i < 90; i++) {
      const m = new THREE.Mesh(this.tracerGeo, new THREE.MeshBasicMaterial({ color: '#fff', transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
      m.visible = false;
      m.frustumCulled = false;
      this.group.add(m);
      this.tracers.push({ mesh: m, life: 0, max: 1, from: new THREE.Vector3(), to: new THREE.Vector3(), travel: 0, width: 0.05 });
    }
    for (let i = 0; i < 3; i++) {
      const l = new THREE.PointLight('#ffffff', 0, 12, 2);
      l.visible = true;
      this.group.add(l);
      this.lights.push({ light: l, life: 0, max: 1, i0: 0 });
    }
  }

  setScale(heightPx: number, fovDeg: number) {
    const s = heightPx / (2 * Math.tan((fovDeg * Math.PI) / 360));
    this.soft.mat.uniforms.uScale.value = s;
    this.glow.mat.uniforms.uScale.value = s;
  }

  flashLight(pos: THREE.Vector3, color: THREE.ColorRepresentation, intensity: number, life: number, distance = 12) {
    let slot = this.lights.find((l) => l.life <= 0) ?? this.lights.reduce((a, b) => (a.life < b.life ? a : b));
    slot.light.position.copy(pos);
    slot.light.color.set(color);
    slot.light.distance = distance;
    slot.i0 = intensity;
    slot.life = life;
    slot.max = life;
  }

  tracer(from: THREE.Vector3, to: THREE.Vector3, color: THREE.ColorRepresentation, width: number, life: number, travel = 0) {
    const t = this.tracers.find((x) => x.life <= 0) ?? this.tracers[0];
    t.from.copy(from);
    t.to.copy(to);
    t.life = life + travel;
    t.max = life + travel;
    t.travel = travel;
    t.width = width;
    (t.mesh.material as THREE.MeshBasicMaterial).color.set(color);
    t.mesh.visible = true;
  }

  private floorBelow: (p: THREE.Vector3) => number = (p) => Math.max(0, p.y - 3);
  setFloorProbe(fn: (p: THREE.Vector3) => number) {
    this.floorBelow = fn;
  }

  impact(point: THREE.Vector3, normal: THREE.Vector3, mat: SurfaceMat, opts: { color?: string; big?: boolean; decal?: boolean } = {}) {
    const cols = MAT_COLORS[mat];
    const n = opts.big ? 10 : 4;
    const floor = this.floorBelow(point);
    const v = new THREE.Vector3();
    for (let i = 0; i < n; i++) {
      v.copy(normal).multiplyScalar(rand(2, 6)).add(new THREE.Vector3(rand(-2.5, 2.5), rand(0, 3.5), rand(-2.5, 2.5)));
      if (mat === 'plastic' || mat === 'cardboard' || mat === 'wood') {
        const s = mat === 'cardboard' ? rand(0.06, 0.16) : rand(0.04, 0.1);
        this.chips.emit(point, v, opts.color ?? pick(cols), new THREE.Vector3(s, mat === 'cardboard' ? s * 0.2 : s, s), rand(0.8, 1.6), floor);
      } else {
        this.glow.emit(point, v.multiplyScalar(0.6), new THREE.Color(pick(cols)), rand(0.1, 0.18), rand(0.15, 0.35), { gravity: 6, drag: 2 });
      }
    }
    // dust / puff
    const puffCol = new THREE.Color(mat === 'wood' ? '#d9c2a0' : mat === 'fabric' || mat === 'carpet' ? '#f7f1ff' : mat === 'cardboard' ? '#d8b98a' : '#ffffff');
    for (let i = 0; i < (mat === 'fabric' || mat === 'wood' || mat === 'carpet' ? 4 : 2); i++)
      this.soft.emit(point.clone().addScaledVector(normal, 0.1), normal.clone().multiplyScalar(rand(0.5, 1.6)).add(new THREE.Vector3(rand(-0.5, 0.5), rand(0, 0.6), rand(-0.5, 0.5))), puffCol, rand(0.35, 0.6), rand(0.4, 0.8), { grow: 1.2, drag: 3, alpha: 0.55 });
    if (mat === 'metal' || mat === 'glass') {
      this.glow.emit(point.clone().addScaledVector(normal, 0.05), new THREE.Vector3(), new THREE.Color(mat === 'glass' ? '#e6fbff' : '#fff1b8'), 0.6, 0.08);
    }
    if (opts.decal !== false) this.impacts.add(point, normal, rand(0.18, 0.28), mat === 'wood' ? '#3b2615' : mat === 'fabric' || mat === 'carpet' ? '#7d6f80' : '#2a2a2a', 8, 0.55);
  }

  /** Soft spark when a bullet hits a toy. */
  hitSpark(point: THREE.Vector3, color: string, shield: boolean, head: boolean) {
    const c = new THREE.Color(shield ? '#6fd3ff' : head ? '#ffe066' : color);
    for (let i = 0; i < (head ? 7 : 4); i++) {
      this.glow.emit(point, new THREE.Vector3(rand(-3, 3), rand(-1, 4), rand(-3, 3)), c, rand(0.12, 0.22), rand(0.15, 0.3), { gravity: 8, drag: 2 });
    }
    // foam chunks
    const floor = this.floorBelow(point);
    for (let i = 0; i < 2; i++) this.chips.emit(point, new THREE.Vector3(rand(-3, 3), rand(1, 4), rand(-3, 3)), shield ? '#bdeeff' : color, new THREE.Vector3(0.06, 0.06, 0.06), 1, floor);
  }

  muzzle(pos: THREE.Vector3, dir: THREE.Vector3, color: string, scale = 1) {
    const c = new THREE.Color(color);
    this.glow.emit(pos, new THREE.Vector3(), c, 0.9 * scale, 0.06);
    this.glow.emit(pos.clone().addScaledVector(dir, 0.25 * scale), dir.clone().multiplyScalar(4), new THREE.Color('#ffffff'), 0.45 * scale, 0.05);
    for (let i = 0; i < 3; i++) this.glow.emit(pos, dir.clone().multiplyScalar(rand(3, 8)).add(new THREE.Vector3(rand(-1, 1), rand(-1, 1), rand(-1, 1))), c, 0.12, 0.12, { drag: 4 });
  }

  /** A toy pops apart into plastic pieces, springs and confetti. */
  breakApart(pos: THREE.Vector3, colors: string[], reduced: boolean) {
    const floor = this.floorBelow(pos.clone().setY(pos.y + 0.5));
    const n = reduced ? 14 : 30;
    for (let i = 0; i < n; i++) {
      const s = rand(0.12, 0.32);
      const shape = new THREE.Vector3(s, s * rand(0.5, 1.4), s * rand(0.6, 1.5));
      this.chips.emit(
        pos.clone().add(new THREE.Vector3(rand(-0.3, 0.3), rand(0.2, 1.6), rand(-0.3, 0.3))),
        new THREE.Vector3(rand(-5, 5), rand(3, 9), rand(-5, 5)),
        pick(colors), shape, rand(2.6, 3.6), floor,
      );
    }
    for (let i = 0; i < (reduced ? 2 : 4); i++) {
      this.springs.emit(pos.clone().setY(pos.y + 1), new THREE.Vector3(rand(-4, 4), rand(5, 10), rand(-4, 4)), '#ffffff', new THREE.Vector3(0.45, 0.6, 0.45), 3, floor);
    }
    for (let i = 0; i < (reduced ? 20 : 50); i++) {
      this.glow.emit(pos.clone().setY(pos.y + 1), new THREE.Vector3(rand(-6, 6), rand(1, 9), rand(-6, 6)), new THREE.Color(pick(['#ff5d8f', '#ffd166', '#06d6a0', '#4cc9f0', '#c77dff', ...colors])), rand(0.1, 0.2), rand(0.6, 1.2), { gravity: 9, drag: 1.5 });
    }
    for (let i = 0; i < 6; i++) this.soft.emit(pos.clone().setY(pos.y + 0.9), new THREE.Vector3(rand(-1.5, 1.5), rand(0.5, 2), rand(-1.5, 1.5)), new THREE.Color('#ffffff'), rand(0.8, 1.4), rand(0.5, 0.9), { grow: 2, drag: 2, alpha: 0.6 });
    this.flashLight(pos.clone().setY(pos.y + 1), '#ffd6a5', 30, 0.25, 10);
  }

  /** Pieces fly in and snap together at a spawn point. */
  reassemble(pos: THREE.Vector3, colors: string[]) {
    for (let i = 0; i < 28; i++) {
      const dir = new THREE.Vector3(rand(-1, 1), rand(-0.2, 1), rand(-1, 1)).normalize();
      const start = pos.clone().setY(pos.y + 0.9).addScaledVector(dir, rand(1.5, 2.5));
      const vel = pos.clone().setY(pos.y + 0.9).sub(start).multiplyScalar(1 / 0.35);
      this.glow.emit(start, vel, new THREE.Color(pick(colors)), rand(0.14, 0.24), 0.35, { alpha: 0.9 });
    }
    this.glow.emit(pos.clone().setY(pos.y + 0.9), new THREE.Vector3(), new THREE.Color('#ffffff'), 3, 0.3);
  }

  explosion(pos: THREE.Vector3, normal: THREE.Vector3, colors: string[], reduced: boolean) {
    const floor = this.floorBelow(pos.clone().setY(pos.y + 0.3));
    for (let i = 0; i < (reduced ? 30 : 70); i++) {
      const c = new THREE.Color(pick(colors));
      this.glow.emit(pos, new THREE.Vector3(rand(-1, 1), rand(-0.3, 1), rand(-1, 1)).normalize().multiplyScalar(rand(4, 13)), c, rand(0.18, 0.35), rand(0.4, 0.9), { gravity: 10, drag: 2 });
    }
    for (let i = 0; i < (reduced ? 6 : 14); i++)
      this.soft.emit(pos, new THREE.Vector3(rand(-2.5, 2.5), rand(0.5, 3.5), rand(-2.5, 2.5)), new THREE.Color(pick(colors)).lerp(new THREE.Color('#ffffff'), 0.4), rand(1.2, 2.2), rand(0.7, 1.3), { grow: 3, drag: 2.5, alpha: 0.75 });
    for (let i = 0; i < 12; i++) {
      const s = rand(0.08, 0.2);
      this.chips.emit(pos.clone().addScaledVector(normal, 0.3), new THREE.Vector3(rand(-7, 7), rand(3, 10), rand(-7, 7)), pick(colors), new THREE.Vector3(s, s * 3, s), rand(1.5, 2.5), floor);
    }
    this.glow.emit(pos, new THREE.Vector3(), new THREE.Color('#fff4d6'), 7, 0.12);
    this.flashLight(pos, colors[0], 90, 0.3, 16);
  }

  paintSplat(point: THREE.Vector3, normal: THREE.Vector3, color: string, size: number) {
    this.splats.add(point, normal, size, color, 12, 0.92);
  }

  bubbleBurst(pos: THREE.Vector3, color: string) {
    for (let i = 0; i < 5; i++) {
      this.glow.emit(pos, new THREE.Vector3(rand(-2, 2), rand(-1, 2.5), rand(-2, 2)), new THREE.Color(pick([color, '#ffffff', '#9be7ff', '#ffc6ff'])), rand(0.08, 0.16), rand(0.2, 0.4), { gravity: 2, drag: 3 });
    }
    this.soft.emit(pos, new THREE.Vector3(0, 0.3, 0), new THREE.Color('#f0e6ff'), 0.5, 0.25, { grow: 2, alpha: 0.4 });
  }

  energyHit(pos: THREE.Vector3, color: string) {
    for (let i = 0; i < 6; i++) this.glow.emit(pos, new THREE.Vector3(rand(-4, 4), rand(-2, 4), rand(-4, 4)), new THREE.Color(color), rand(0.08, 0.15), rand(0.15, 0.3), { drag: 5 });
    this.glow.emit(pos, new THREE.Vector3(), new THREE.Color('#ffffff'), 0.8, 0.07);
    this.flashLight(pos, color, 12, 0.08, 6);
  }

  pickupSparkle(pos: THREE.Vector3, color: string) {
    for (let i = 0; i < 18; i++) {
      this.glow.emit(pos.clone().setY(pos.y + 0.6), new THREE.Vector3(rand(-2, 2), rand(1, 4), rand(-2, 2)), new THREE.Color(color), rand(0.1, 0.2), rand(0.4, 0.7), { gravity: 3, drag: 2 });
    }
  }

  /** Coil-shaped trail for the Wind-Up Dash. */
  springTrail(from: THREE.Vector3, to: THREE.Vector3, color: string) {
    const dir = to.clone().sub(from);
    const len = dir.length();
    if (len < 0.5) return;
    dir.normalize();
    const side = new THREE.Vector3().crossVectors(dir, new THREE.Vector3(0, 1, 0)).normalize();
    const up = new THREE.Vector3().crossVectors(side, dir).normalize();
    const pts: THREE.Vector3[] = [];
    const coils = Math.max(4, Math.floor(len * 1.2));
    for (let i = 0; i <= coils * 10; i++) {
      const t = i / (coils * 10);
      const a = t * coils * Math.PI * 2;
      pts.push(from.clone().addScaledVector(dir, len * t).addScaledVector(side, Math.cos(a) * 0.35).addScaledVector(up, Math.sin(a) * 0.35 + 0.9));
    }
    const geo = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), pts.length, 0.035, 5, false);
    const mesh = new THREE.Mesh(geo, new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false }));
    mesh.frustumCulled = false;
    this.group.add(mesh);
    this.trails.push({ mesh, life: 0.45, max: 0.45 });
  }

  update(dt: number, camPos: THREE.Vector3) {
    this.soft.update(dt);
    this.glow.update(dt);
    this.chips.update(dt);
    this.springs.update(dt);
    this.impacts.update(dt);
    this.splats.update(dt);
    const tmp = new THREE.Vector3();
    for (const t of this.tracers) {
      if (t.life <= 0) continue;
      t.life -= dt;
      if (t.life <= 0) {
        t.mesh.visible = false;
        continue;
      }
      const age = t.max - t.life;
      const mat = t.mesh.material as THREE.MeshBasicMaterial;
      const total = t.from.distanceTo(t.to);
      let head = total, tail = 0;
      if (t.travel > 0) {
        const k = Math.min(1, age / t.travel);
        head = total * k;
        tail = Math.max(0, head - Math.min(6, total * 0.35));
        mat.opacity = 1;
        if (k >= 1) mat.opacity = Math.max(0, t.life / (t.max - t.travel));
      } else {
        mat.opacity = Math.max(0, t.life / t.max);
      }
      const dir = tmp.subVectors(t.to, t.from).normalize();
      t.mesh.position.copy(t.from).addScaledVector(dir, tail);
      t.mesh.lookAt(t.mesh.position.clone().add(dir));
      const w = t.width * (0.6 + 0.4 * mat.opacity);
      t.mesh.scale.set(w, w, Math.max(0.01, head - tail));
    }
    for (const l of this.lights) {
      if (l.life <= 0) {
        l.light.intensity = 0;
        continue;
      }
      l.life -= dt;
      l.light.intensity = l.i0 * Math.max(0, l.life / l.max);
    }
    for (let i = this.trails.length - 1; i >= 0; i--) {
      const tr = this.trails[i];
      tr.life -= dt;
      (tr.mesh.material as THREE.MeshBasicMaterial).opacity = Math.max(0, tr.life / tr.max) * 0.9;
      if (tr.life <= 0) {
        this.group.remove(tr.mesh);
        tr.mesh.geometry.dispose();
        (tr.mesh.material as THREE.Material).dispose();
        this.trails.splice(i, 1);
      }
    }
    void camPos;
  }

  clear() {
    this.soft.clear();
    this.glow.clear();
    this.chips.clear();
    this.springs.clear();
    this.impacts.clear();
    this.splats.clear();
    for (const t of this.tracers) {
      t.life = 0;
      t.mesh.visible = false;
    }
    for (const l of this.lights) l.life = 0;
    for (const tr of this.trails) {
      this.group.remove(tr.mesh);
      tr.mesh.geometry.dispose();
    }
    this.trails = [];
  }
}

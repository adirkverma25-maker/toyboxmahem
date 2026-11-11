import * as THREE from 'three';

export const DEG = Math.PI / 180;
export const clamp = (v: number, a: number, b: number) => (v < a ? a : v > b ? b : v);
export const lerp = (a: number, b: number, t: number) => a + (b - a) * t;
export const rand = (a: number, b: number) => a + Math.random() * (b - a);
export const randInt = (a: number, b: number) => Math.floor(rand(a, b + 1));
export const pick = <T>(arr: readonly T[]): T => arr[Math.floor(Math.random() * arr.length)];
export const damp = (a: number, b: number, lambda: number, dt: number) => lerp(a, b, 1 - Math.exp(-lambda * dt));
export const smoothstep = (a: number, b: number, x: number) => {
  const t = clamp((x - a) / (b - a), 0, 1);
  return t * t * (3 - 2 * t);
};
export const moveToward = (v: number, target: number, maxDelta: number) =>
  Math.abs(target - v) <= maxDelta ? target : v + Math.sign(target - v) * maxDelta;

export function angleWrap(a: number) {
  while (a > Math.PI) a -= Math.PI * 2;
  while (a < -Math.PI) a += Math.PI * 2;
  return a;
}

/** Seeded PRNG (mulberry32) so procedural textures and sounds are repeatable. */
export function seeded(seed: number) {
  let t = seed >>> 0;
  return () => {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r ^= r + Math.imul(r ^ (r >>> 7), 61 | r);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

/** Random direction inside a cone of half-angle `angle` (radians) around `dir`. */
const _tmpA = new THREE.Vector3();
const _tmpB = new THREE.Vector3();
export function coneDirection(dir: THREE.Vector3, angle: number, out: THREE.Vector3) {
  if (angle <= 0) return out.copy(dir);
  const u = Math.random();
  const cosA = 1 - u * (1 - Math.cos(angle)); // uniform over cap
  const sinA = Math.sqrt(1 - cosA * cosA);
  const phi = Math.random() * Math.PI * 2;
  _tmpA.set(1, 0, 0);
  if (Math.abs(dir.x) > 0.9) _tmpA.set(0, 1, 0);
  _tmpB.crossVectors(dir, _tmpA).normalize();
  _tmpA.crossVectors(dir, _tmpB).normalize();
  return out
    .copy(dir)
    .multiplyScalar(cosA)
    .addScaledVector(_tmpB, sinA * Math.cos(phi))
    .addScaledVector(_tmpA, sinA * Math.sin(phi))
    .normalize();
}

/** Ray vs sphere. Returns distance along the (normalized) ray or -1. */
export function raySphere(o: THREE.Vector3, d: THREE.Vector3, c: THREE.Vector3, r: number, maxT: number) {
  const ox = o.x - c.x, oy = o.y - c.y, oz = o.z - c.z;
  const b = ox * d.x + oy * d.y + oz * d.z;
  const cc = ox * ox + oy * oy + oz * oz - r * r;
  if (cc > 0 && b > 0) return -1;
  const disc = b * b - cc;
  if (disc < 0) return -1;
  let t = -b - Math.sqrt(disc);
  if (t < 0) t = 0;
  return t <= maxT ? t : -1;
}

/** Ray vs capsule (segment a-b with radius r). Returns distance or -1. */
const _ba = new THREE.Vector3();
const _oa = new THREE.Vector3();
const _p = new THREE.Vector3();
export function rayCapsule(o: THREE.Vector3, d: THREE.Vector3, a: THREE.Vector3, b: THREE.Vector3, r: number, maxT: number) {
  // Inigo Quilez capsule intersection
  _ba.subVectors(b, a);
  _oa.subVectors(o, a);
  const baba = _ba.dot(_ba);
  const bard = _ba.dot(d);
  const baoa = _ba.dot(_oa);
  const rdoa = d.dot(_oa);
  const oaoa = _oa.dot(_oa);
  const A = baba - bard * bard;
  let B = baba * rdoa - baoa * bard;
  let C = baba * oaoa - baoa * baoa - r * r * baba;
  let h = B * B - A * C;
  if (h >= 0) {
    const t = (-B - Math.sqrt(h)) / A;
    const y = baoa + t * bard;
    if (y > 0 && y < baba && t >= 0 && t <= maxT) return t;
    // caps
    _p.copy(y <= 0 ? _oa : _oa.clone().sub(_ba));
    B = d.dot(_p);
    C = _p.dot(_p) - r * r;
    h = B * B - C;
    if (h > 0) {
      const t2 = -B - Math.sqrt(h);
      if (t2 >= 0 && t2 <= maxT) return t2;
      if (C < 0) return 0; // origin inside cap
    }
  }
  // origin already inside the capsule
  const segT = clamp(baoa / baba, 0, 1);
  _p.copy(a).addScaledVector(_ba, segT);
  if (_p.distanceToSquared(o) < r * r) return 0;
  return -1;
}

export function closestPointOnSegment(p: THREE.Vector3, a: THREE.Vector3, b: THREE.Vector3, out: THREE.Vector3) {
  _ba.subVectors(b, a);
  const t = clamp(_oa.subVectors(p, a).dot(_ba) / Math.max(1e-6, _ba.lengthSq()), 0, 1);
  return out.copy(a).addScaledVector(_ba, t);
}

export function formatTime(sec: number) {
  sec = Math.max(0, Math.ceil(sec));
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/** Simple object pool. */
export class Pool<T> {
  private free: T[] = [];
  constructor(private make: () => T, prefill = 0) {
    for (let i = 0; i < prefill; i++) this.free.push(make());
  }
  get(): T {
    return this.free.pop() ?? this.make();
  }
  release(o: T) {
    this.free.push(o);
  }
}

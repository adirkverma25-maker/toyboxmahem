import * as THREE from 'three';
import type { Actor } from '../entities/Actor';
import { ABILITIES } from '../weapons/weaponConfig';

const VS = /* glsl */ `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;
// hexagon wire mesh with a bright rim, ripple on hits and a fade in/out
const FS = /* glsl */ `
uniform vec3 uColor;
uniform float uTime;
uniform float uAlpha;
uniform float uFlash;
uniform float uHealth;
uniform vec2 uSize;
varying vec2 vUv;
float hexDist(vec2 p) {
  p = abs(p);
  return max(dot(p, normalize(vec2(1.0, 1.7320508))), p.x);
}
void main() {
  vec2 p = (vUv - 0.5) * uSize * 3.2;
  vec2 r = vec2(1.0, 1.7320508);
  vec2 h = r * 0.5;
  vec2 a = mod(p, r) - h;
  vec2 b = mod(p - h, r) - h;
  vec2 g = dot(a, a) < dot(b, b) ? a : b;
  float d = hexDist(g);
  float wire = smoothstep(0.42, 0.5, d);
  vec2 e = min(vUv, 1.0 - vUv) * uSize;
  float rim = 1.0 - smoothstep(0.0, 0.09, min(e.x, e.y));
  float scan = 0.5 + 0.5 * sin(vUv.y * 40.0 - uTime * 6.0);
  float crack = (1.0 - uHealth) * step(0.75, fract(sin(dot(floor(p * 1.3), vec2(12.9898, 78.233))) * 43758.5453));
  float a2 = wire * (0.55 + 0.2 * scan) + rim * 0.9 + 0.06 + uFlash * 0.5 - crack * 0.2;
  vec3 col = mix(uColor, vec3(1.0), rim * 0.4 + uFlash * 0.6);
  gl_FragColor = vec4(col, clamp(a2, 0.0, 1.0) * uAlpha);
}`;

export interface Barrier {
  owner: Actor;
  team: number;
  center: THREE.Vector3;
  normal: THREE.Vector3;
  right: THREE.Vector3;
  up: THREE.Vector3;
  halfW: number;
  halfH: number;
  hp: number;
  expireAt: number;
  born: number;
  mesh: THREE.Mesh;
  mat: THREE.ShaderMaterial;
  flash: number;
  dying: number; // >0 while fading out
}

const _p = new THREE.Vector3();

/**
 * Mesh Shield: a deployable hex-wire wall that eats enemy bullets, darts and splash.
 * Teammates (and the owner) shoot straight through it.
 */
export class Barriers {
  list: Barrier[] = [];
  private group = new THREE.Group();
  private geo = new THREE.PlaneGeometry(1, 1);
  onBreak: ((b: Barrier) => void) | null = null;

  constructor(scene: THREE.Scene) {
    scene.add(this.group);
  }

  /** Does this barrier stop shots from `shooter`? */
  blocks(b: Barrier, shooter: Actor | null) {
    if (b.dying > 0) return false;
    if (!shooter) return false;
    if (shooter === b.owner) return false;
    if (shooter.team >= 0) return shooter.team !== b.team;
    return true;
  }

  deploy(owner: Actor, pos: THREE.Vector3, yaw: number, color: string, now: number) {
    // one shield per toy
    for (const b of this.list) if (b.owner === owner && b.dying <= 0) b.dying = 0.3;
    const cfg = ABILITIES.shield;
    const mat = new THREE.ShaderMaterial({
      vertexShader: VS,
      fragmentShader: FS,
      uniforms: {
        uColor: { value: new THREE.Color(color) },
        uTime: { value: 0 },
        uAlpha: { value: 0 },
        uFlash: { value: 0 },
        uHealth: { value: 1 },
        uSize: { value: new THREE.Vector2(cfg.width, cfg.height) },
      },
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
      blending: THREE.AdditiveBlending,
      toneMapped: false,
    });
    const mesh = new THREE.Mesh(this.geo, mat);
    mesh.scale.set(cfg.width, cfg.height, 1);
    mesh.renderOrder = 6;
    mesh.frustumCulled = false;
    const normal = new THREE.Vector3(-Math.sin(yaw), 0, -Math.cos(yaw));
    const center = pos.clone().setY(pos.y + cfg.height / 2);
    mesh.position.copy(center);
    mesh.rotation.set(0, yaw, 0);
    this.group.add(mesh);
    const b: Barrier = {
      owner, team: owner.team, center, normal,
      right: new THREE.Vector3(Math.cos(yaw), 0, -Math.sin(yaw)),
      up: new THREE.Vector3(0, 1, 0),
      halfW: cfg.width / 2, halfH: cfg.height / 2,
      hp: cfg.hp, expireAt: now + cfg.duration, born: now, mesh, mat, flash: 0, dying: 0,
    };
    this.list.push(b);
    return b;
  }

  /** Ray/segment test. Returns the nearest blocking barrier and distance along `d` (unit). */
  trace(o: THREE.Vector3, d: THREE.Vector3, maxT: number, shooter: Actor | null): { b: Barrier; t: number } | null {
    let best: { b: Barrier; t: number } | null = null;
    for (const b of this.list) {
      if (!this.blocks(b, shooter)) continue;
      const denom = d.dot(b.normal);
      if (Math.abs(denom) < 1e-5) continue;
      const t = _p.subVectors(b.center, o).dot(b.normal) / denom;
      if (t < 0 || t > maxT) continue;
      _p.copy(o).addScaledVector(d, t).sub(b.center);
      if (Math.abs(_p.dot(b.right)) > b.halfW || Math.abs(_p.y) > b.halfH) continue;
      if (!best || t < best.t) best = { b, t };
    }
    return best;
  }

  /** Is the straight line between two points cut by a barrier that blocks `shooter`? */
  between(a: THREE.Vector3, c: THREE.Vector3, shooter: Actor | null) {
    const d = c.clone().sub(a);
    const len = d.length();
    if (len < 1e-4) return null;
    d.divideScalar(len);
    return this.trace(a, d, len, shooter);
  }

  damage(b: Barrier, amount: number) {
    if (b.dying > 0) return;
    b.hp -= amount;
    b.flash = 1;
    if (b.hp <= 0) {
      b.dying = 0.35;
      this.onBreak?.(b);
    }
  }

  update(dt: number, now: number) {
    for (let i = this.list.length - 1; i >= 0; i--) {
      const b = this.list[i];
      const u = b.mat.uniforms;
      u.uTime.value = now;
      b.flash = Math.max(0, b.flash - dt * 5);
      u.uFlash.value = b.flash;
      u.uHealth.value = Math.max(0, b.hp / ABILITIES.shield.hp);
      if (b.dying <= 0 && (now >= b.expireAt || !b.owner.alive)) b.dying = 0.35;
      if (b.dying > 0) {
        b.dying -= dt;
        u.uAlpha.value = Math.max(0, b.dying / 0.35);
        b.mesh.scale.y = ABILITIES.shield.height * (0.6 + 0.4 * Math.max(0, b.dying / 0.35));
        if (b.dying <= 0) {
          this.group.remove(b.mesh);
          b.mat.dispose();
          this.list.splice(i, 1);
        }
        continue;
      }
      const grow = Math.min(1, (now - b.born) / 0.25);
      u.uAlpha.value = grow * (now > b.expireAt - 1.2 ? 0.55 + 0.45 * Math.sin(now * 20) : 1);
      b.mesh.scale.y = ABILITIES.shield.height * grow;
    }
  }

  clear() {
    for (const b of this.list) {
      this.group.remove(b.mesh);
      b.mat.dispose();
    }
    this.list = [];
  }
}

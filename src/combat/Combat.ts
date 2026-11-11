import * as THREE from 'three';
import { Physics, RayHit, SurfaceMat } from '../physics/Physics';
import { Effects } from '../fx/Effects';
import { AudioEngine } from '../audio/Audio';
import { Emitter } from '../core/events';
import { Actor } from '../entities/Actor';
import { ABILITIES, COMBAT, PICKUPS, WeaponConfig, WeaponId, ProjectileVisual } from '../weapons/weaponConfig';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { Barriers, Barrier } from './Barriers';
import { WeaponState } from '../weapons/WeaponState';
import { coneDirection, DEG, raySphere, rayCapsule, rand, pick } from '../core/math';
import { LooseBricks } from '../world/Arena';

export type DamageSource = WeaponId | 'block' | 'jab';

export interface GameEvents extends Record<string, unknown> {
  damage: { attacker: Actor | null; target: Actor; amount: number; shieldDmg: number; healthDmg: number; head: boolean; point: THREE.Vector3; weapon: DamageSource; fromDir: THREE.Vector3; shieldBroke: boolean };
  kill: { killer: Actor | null; victim: Actor; weapon: DamageSource; head: boolean; time: number };
  shot: { shooter: Actor; weapon: WeaponId; pos: THREE.Vector3 };
  explosion: { pos: THREE.Vector3; radius: number };
  hit: { attacker: Actor; target: Actor; head: boolean; shield: boolean };
  pickup: { actor: Actor; kind: string; label: string };
  spawn: { actor: Actor };
  announce: { text: string; sub?: string };
}

interface Projectile {
  active: boolean;
  visual: ProjectileVisual;
  pos: THREE.Vector3;
  prev: THREE.Vector3;
  vel: THREE.Vector3;
  offset: THREE.Vector3; // visual offset (muzzle -> eye convergence)
  gravity: number;
  drag: number;
  radius: number;
  life: number;
  shooter: Actor;
  cfg: WeaponConfig;
  traveled: number;
  hits: Set<number>;
  color: string;
  whistle: { move(p: THREE.Vector3): void; stop(): void } | null;
  power: number;
  charge: number;
}

const PROJ_POOL: Record<ProjectileVisual, number> = { dart: 140, bubble: 160, crayon: 20, bolt: 120, arrow: 40 };
const STUCK = 40;

/** Suction-cup arrow, pointing down +Z (cup at the front). */
function arrowGeometry() {
  const shaft = new THREE.CylinderGeometry(0.028, 0.028, 0.9, 8);
  shaft.rotateX(Math.PI / 2);
  const cup = new THREE.CylinderGeometry(0.1, 0.035, 0.1, 14);
  cup.rotateX(Math.PI / 2);
  cup.translate(0, 0, 0.5);
  const parts = [shaft, cup];
  for (const r of [0, Math.PI / 2]) {
    const f = new THREE.BoxGeometry(0.16, 0.012, 0.18);
    f.rotateZ(r);
    f.translate(0, 0, -0.36);
    parts.push(f as unknown as THREE.CylinderGeometry);
  }
  const g = mergeGeometries(parts.map((x) => x.toNonIndexed()), false)!;
  return g;
}
const PAINT = ['#ef476f', '#ffd166', '#06d6a0', '#118ab2', '#8338ec', '#ff8c42'];

const _a = new THREE.Vector3();
const _b = new THREE.Vector3();
const _h = new THREE.Vector3();
const _dir = new THREE.Vector3();
const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _z = new THREE.Vector3(0, 0, 1);

export class Combat {
  private projectiles: Projectile[] = [];
  private meshes: Record<ProjectileVisual, THREE.InstancedMesh>;
  private group = new THREE.Group();
  now = 0;
  reducedMotion = false;
  barriers: Barriers;
  private stuck: THREE.InstancedMesh;
  private stuckLife: number[] = [];
  private stuckNext = 0;

  constructor(
    scene: THREE.Scene,
    private phys: Physics,
    private fx: Effects,
    private audio: AudioEngine,
    public events: Emitter<GameEvents>,
    private actors: () => Actor[],
    private bricks: LooseBricks,
  ) {
    scene.add(this.group);
    this.barriers = new Barriers(scene);
    this.barriers.onBreak = (b) => {
      this.audio.shieldBreak(b.center);
      for (let i = 0; i < 24; i++) this.fx.glow.emit(b.center.clone().addScaledVector(b.right, rand(-b.halfW, b.halfW)).setY(b.center.y + rand(-b.halfH, b.halfH)), new THREE.Vector3(rand(-3, 3), rand(-1, 3), rand(-3, 3)), new THREE.Color((b.mat.uniforms.uColor.value as THREE.Color).getStyle()), rand(0.1, 0.2), rand(0.3, 0.6), { gravity: 6, drag: 2 });
    };
    const arrowGeo = arrowGeometry();
    this.stuck = new THREE.InstancedMesh(arrowGeo, new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.5 }), STUCK);
    this.stuck.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.stuck.frustumCulled = false;
    this.stuck.castShadow = true;
    for (let i = 0; i < STUCK; i++) {
      this.stuck.setMatrixAt(i, new THREE.Matrix4().makeScale(0, 0, 0));
      this.stuck.setColorAt(i, new THREE.Color('#ffffff'));
      this.stuckLife.push(0);
    }
    this.group.add(this.stuck);
    const dartGeo = new THREE.CapsuleGeometry(0.045, 0.22, 4, 8);
    dartGeo.rotateX(Math.PI / 2);
    const bubbleGeo = new THREE.SphereGeometry(0.15, 14, 10);
    const crayonGeo = new THREE.CylinderGeometry(0.12, 0.12, 0.7, 12);
    crayonGeo.rotateX(Math.PI / 2);
    const boltGeo = new THREE.CapsuleGeometry(0.05, 0.5, 4, 8);
    boltGeo.rotateX(Math.PI / 2);
    this.meshes = {
      dart: new THREE.InstancedMesh(dartGeo, new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.7, emissive: '#ff8a3d', emissiveIntensity: 0.25 }), PROJ_POOL.dart),
      bubble: new THREE.InstancedMesh(bubbleGeo, new THREE.MeshPhysicalMaterial({ color: '#ffffff', roughness: 0.02, transparent: true, opacity: 0.5, clearcoat: 1, iridescence: 1, iridescenceIOR: 1.3, emissive: '#b388ff', emissiveIntensity: 0.4, depthWrite: false }), PROJ_POOL.bubble),
      crayon: new THREE.InstancedMesh(crayonGeo, new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.6 }), PROJ_POOL.crayon),
      bolt: new THREE.InstancedMesh(boltGeo, new THREE.MeshBasicMaterial({ color: '#ffffff', toneMapped: false }), PROJ_POOL.bolt),
      arrow: new THREE.InstancedMesh(arrowGeo, new THREE.MeshStandardMaterial({ color: '#ffffff', roughness: 0.5, emissive: '#ff4d6d', emissiveIntensity: 0.15 }), PROJ_POOL.arrow),
    };
    for (const k of Object.keys(this.meshes) as ProjectileVisual[]) {
      const im = this.meshes[k];
      im.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
      im.frustumCulled = false;
      im.castShadow = k !== 'bolt' && k !== 'bubble';
      for (let i = 0; i < PROJ_POOL[k]; i++) {
        im.setMatrixAt(i, new THREE.Matrix4().makeScale(0, 0, 0));
        im.setColorAt(i, new THREE.Color('#ffffff'));
      }
      this.group.add(im);
      for (let i = 0; i < PROJ_POOL[k]; i++) {
        this.projectiles.push({
          active: false, visual: k, pos: new THREE.Vector3(), prev: new THREE.Vector3(), vel: new THREE.Vector3(), offset: new THREE.Vector3(),
          gravity: 0, drag: 0, radius: 0.1, life: 0, shooter: null as unknown as Actor, cfg: null as unknown as WeaponConfig, traveled: 0,
          hits: new Set(), color: '#fff', whistle: null, power: 1, charge: 1,
        });
      }
    }
  }

  /**
   * Fire one trigger pull of `ws` from `origin` (eye) toward `dir`.
   * `muzzle` is where visuals (tracers / projectile meshes) start.
   */
  fire(shooter: Actor, ws: WeaponState, origin: THREE.Vector3, dir: THREE.Vector3, muzzle: THREE.Vector3, spreadDeg: number) {
    const cfg = ws.cfg;
    const power = shooter.hasBuff('power', this.now) ? PICKUPS.powerMult : 1;
    // bows: damage and arrow speed scale with how long the string was held
    const charge = cfg.charge ? ws.lastCharge : 1;
    shooter.shotsFired += cfg.pellets;
    shooter.revealAt = this.now; // attacking drops cloak
    for (let p = 0; p < cfg.pellets; p++) {
      const d = coneDirection(dir, spreadDeg * DEG, new THREE.Vector3());
      if (cfg.projectile.kind === 'hitscan') this.hitscan(shooter, cfg, origin, d, muzzle, power);
      else this.spawnProjectile(shooter, cfg, origin, d, muzzle, power, charge);
    }
    this.events.emit('shot', { shooter, weapon: cfg.id, pos: origin.clone() });
  }

  private damageFalloff(cfg: WeaponConfig, dist: number) {
    if (dist <= cfg.effectiveRange) return 1;
    if (dist >= cfg.falloffEnd) return cfg.minDamageMult;
    const t = (dist - cfg.effectiveRange) / (cfg.falloffEnd - cfg.effectiveRange);
    return 1 + (cfg.minDamageMult - 1) * t;
  }

  /** Nearest character hit along a segment (excluding shooter + already-hit). */
  private traceActors(o: THREE.Vector3, d: THREE.Vector3, maxT: number, shooter: Actor | null, inflate: number, skip?: Set<number>) {
    let best: { actor: Actor; t: number; head: boolean } | null = null;
    for (const a of this.actors()) {
      if (!a.alive || a === shooter || (skip && skip.has(a.id))) continue;
      if (shooter && shooter.team >= 0 && a.team === shooter.team) continue; // no friendly fire: shots pass through teammates
      // cheap reject
      a.chestPos(_h);
      const proj = _a.subVectors(_h, o).dot(d);
      if (proj < -1.5 || proj > maxT + 1.5) continue;
      const hb = a.def.hitbox;
      a.headPos(_h);
      const th = raySphere(o, d, _h, hb.headR + inflate, maxT);
      a.bodySegment(_a, _b);
      const tb = rayCapsule(o, d, _a, _b, hb.bodyR + inflate, maxT);
      let t = -1, head = false;
      if (th >= 0 && (tb < 0 || th <= tb + 0.05)) {
        t = th;
        head = true;
      } else if (tb >= 0) t = tb;
      if (t >= 0 && (!best || t < best.t)) best = { actor: a, t, head };
    }
    return best;
  }

  private hitscan(shooter: Actor, cfg: WeaponConfig, origin: THREE.Vector3, d: THREE.Vector3, muzzle: THREE.Vector3, power: number) {
    const maxRange = 220;
    const world = this.phys.raycast(origin, d, maxRange);
    const wt = world ? world.dist : maxRange;
    let hit = this.traceActors(origin, d, wt, shooter, 0);
    const shield = this.barriers.trace(origin, d, hit ? hit.t : wt, shooter);
    if (shield) hit = null;
    const end = origin.clone().addScaledVector(d, shield ? shield.t : hit ? hit.t : wt);
    const tr = cfg.projectile.kind === 'hitscan' ? cfg.projectile.tracer : 'pellet';
    const tc = cfg.colors.tracer;
    if (tr === 'precision') {
      this.fx.tracer(muzzle, end, tc, 0.06, 0.45);
      this.fx.tracer(muzzle, end, '#ffffff', 0.02, 0.3);
    } else if (tr === 'heavy') this.fx.tracer(muzzle, end, tc, 0.05, 0.05, Math.min(0.08, (hit ? hit.t : wt) / 260));
    else if (tr === 'buzz') this.fx.tracer(muzzle, end, tc, 0.03, 0.03, Math.min(0.06, (hit ? hit.t : wt) / 300));
    else this.fx.tracer(muzzle, end, tc, 0.045, 0.04, Math.min(0.09, (hit ? hit.t : wt) / 240));
    if (shield) {
      this.hitBarrier(shield.b, end, cfg.damage * this.damageFalloff(cfg, shield.t) * power);
    } else if (hit) {
      shooter.shotsHit++;
      const dmg = cfg.damage * (hit.head ? cfg.headMult : 1) * this.damageFalloff(cfg, hit.t) * power;
      this.applyDamage(hit.actor, shooter, dmg, hit.head, end, cfg.id, d);
      if (cfg.knockback && hit.actor.alive) {
        // heavy rounds shove the target back along the shot and pop them off the ground a little
        const k = cfg.knockback * this.damageFalloff(cfg, hit.t);
        const flat = _a.set(d.x, 0, d.z).normalize();
        hit.actor.vel.x += flat.x * k;
        hit.actor.vel.z += flat.z * k;
        hit.actor.vel.y = Math.max(hit.actor.vel.y, 3);
      }
    } else if (world) {
      this.worldImpact(world, cfg, d);
    }
  }

  private hitBarrier(b: Barrier, point: THREE.Vector3, dmg: number) {
    this.barriers.damage(b, dmg);
    this.fx.hitSpark(point, '#bdeeff', true, false);
    if (Math.random() < 0.5) this.audio.zap(point);
  }

  private worldImpact(hit: RayHit, cfg: WeaponConfig, d: THREE.Vector3) {
    if (hit.dynamicBody) {
      hit.dynamicBody.applyImpulseAtPoint({ x: d.x * 0.6, y: d.y * 0.6 + 0.2, z: d.z * 0.6 }, hit.point, true);
    }
    const big = cfg.id === 'thunderspring' || cfg.id === 'walloper';
    this.fx.impact(hit.point, hit.normal, hit.mat, { big });
    if (Math.random() < 0.7 || big) this.audio.impact(hit.mat, hit.point, big ? 1.5 : 0.8);
  }

  private spawnProjectile(shooter: Actor, cfg: WeaponConfig, origin: THREE.Vector3, d: THREE.Vector3, muzzle: THREE.Vector3, power: number, charge = 1) {
    if (cfg.projectile.kind !== 'projectile') return;
    const spec = cfg.projectile;
    const p = this.projectiles.find((x) => !x.active && x.visual === spec.visual);
    if (!p) return;
    p.active = true;
    p.pos.copy(origin);
    p.prev.copy(origin);
    const speed = cfg.charge ? cfg.charge.minSpeed + (cfg.charge.maxSpeed - cfg.charge.minSpeed) * charge : spec.speed;
    p.vel.copy(d).multiplyScalar(speed * (spec.visual === 'bubble' ? rand(0.85, 1.1) : 1));
    p.charge = charge;
    p.offset.subVectors(muzzle, origin);
    p.gravity = spec.gravity;
    p.drag = spec.drag ?? 0;
    p.radius = spec.radius;
    p.life = spec.life;
    p.shooter = shooter;
    p.cfg = cfg;
    p.traveled = 0;
    p.hits.clear();
    p.power = power * (cfg.charge ? Math.pow(charge, cfg.charge.curve) : 1);
    p.color = spec.visual === 'arrow' ? cfg.colors.accent : spec.visual === 'crayon' ? pick(PAINT) : spec.visual === 'bubble' ? pick(['#e0aaff', '#9be7ff', '#ffc6ff', '#caffbf']) : cfg.colors.tracer;
    const im = this.meshes[spec.visual];
    const idx = this.indexOf(p);
    im.setColorAt(idx, new THREE.Color(spec.visual === 'dart' ? (Math.random() < 0.5 ? '#ff7a1a' : '#2f6fe0') : p.color));
    if (im.instanceColor) im.instanceColor.needsUpdate = true;
    p.whistle = spec.visual === 'crayon' ? this.audio.whistle(origin) : null;
  }

  private indexOf(p: Projectile) {
    let i = 0;
    for (const q of this.projectiles) {
      if (q === p) return i;
      if (q.visual === p.visual) i++;
    }
    return 0;
  }

  update(dt: number) {
    const counters: Record<ProjectileVisual, number> = { dart: 0, bubble: 0, crayon: 0, bolt: 0, arrow: 0 };
    this.barriers.update(dt, this.now);
    // arrows stuck in walls fade away
    let stuckDirty = false;
    for (let i = 0; i < STUCK; i++) {
      if (this.stuckLife[i] <= 0) continue;
      this.stuckLife[i] -= dt;
      if (this.stuckLife[i] <= 0) {
        this.stuck.setMatrixAt(i, _m.makeScale(0, 0, 0));
        stuckDirty = true;
      }
    }
    if (stuckDirty) this.stuck.instanceMatrix.needsUpdate = true;
    for (const p of this.projectiles) {
      const idx = counters[p.visual]++;
      const im = this.meshes[p.visual];
      if (!p.active) {
        continue;
      }
      p.prev.copy(p.pos);
      p.vel.y -= p.gravity * dt;
      if (p.drag) p.vel.multiplyScalar(Math.max(0, 1 - p.drag * dt));
      _dir.copy(p.vel).multiplyScalar(dt);
      const segLen = _dir.length();
      p.life -= dt;
      let done = false;
      if (segLen > 1e-5) {
        const d = _dir.clone().divideScalar(segLen);
        const world = this.phys.raycast(p.prev, d, segLen + p.radius);
        const wt = world ? world.dist : Infinity;
        const hit = this.traceActors(p.prev, d, Math.min(segLen, wt), p.shooter, p.radius, p.hits);
        const shield = this.barriers.trace(p.prev, d, Math.min(segLen + p.radius, wt, hit ? hit.t : Infinity), p.shooter);
        if (shield) {
          const point = p.prev.clone().addScaledVector(d, shield.t);
          p.pos.copy(point);
          if (p.cfg.explosion) this.explode(point, shield.b.normal.clone().multiplyScalar(Math.sign(-d.dot(shield.b.normal)) || 1), p, null);
          else this.hitBarrier(shield.b, point, p.cfg.damage * p.power);
          done = true;
        } else if (hit && hit.t <= wt) {
          p.hits.add(hit.actor.id);
          p.shooter.shotsHit++;
          const point = p.prev.clone().addScaledVector(d, hit.t);
          const dist = p.traveled + hit.t;
          if (p.cfg.explosion) {
            this.applyDamage(hit.actor, p.shooter, p.cfg.damage * p.power, false, point, p.cfg.id, d);
            this.explode(point, d.clone().negate(), p, hit.actor);
          } else {
            const dmg = p.cfg.damage * (hit.head ? p.cfg.headMult : 1) * this.damageFalloff(p.cfg, dist) * p.power;
            this.applyDamage(hit.actor, p.shooter, dmg, hit.head, point, p.cfg.id, d);
            if (p.visual === 'bubble') this.fx.bubbleBurst(point, p.color);
            if (p.visual === 'bolt') this.fx.energyHit(point, p.cfg.colors.glow);
            if (p.visual === 'arrow' && p.charge > 0.85) hit.actor.vel.addScaledVector(d, 2.5);
          }
          done = true;
        } else if (world) {
          p.pos.copy(world.point);
          if (p.cfg.explosion) this.explode(world.point, world.normal, p, null);
          else if (p.visual === 'bubble') {
            this.fx.bubbleBurst(world.point, p.color);
            if (Math.random() < 0.4) this.audio.bubblePop(world.point);
          } else if (p.visual === 'bolt') {
            this.fx.energyHit(world.point, p.cfg.colors.glow);
            this.fx.impacts.add(world.point, world.normal, 0.3, '#3a1b5c', 6, 0.5);
            if (Math.random() < 0.5) this.audio.zap(world.point);
          } else if (p.visual === 'arrow') {
            this.stickArrow(world.point, d, p.color);
            this.audio.impact(world.mat, world.point, 0.7);
            this.fx.impact(world.point, world.normal, world.mat, { decal: false });
          } else this.worldImpact(world, p.cfg, d);
          if (world.dynamicBody && !p.cfg.explosion) world.dynamicBody.applyImpulseAtPoint({ x: d.x * 0.4, y: 0.2, z: d.z * 0.4 }, world.point, true);
          done = true;
        } else {
          p.pos.add(_dir);
          p.traveled += segLen;
        }
      }
      if (!done && p.life <= 0) {
        if (p.visual === 'bubble') this.fx.bubbleBurst(p.pos, p.color);
        if (p.cfg.explosion) this.explode(p.pos, new THREE.Vector3(0, 1, 0), p, null);
        done = true;
      }
      if (p.whistle) p.whistle.move(p.pos);
      if (done) {
        p.active = false;
        p.whistle?.stop();
        p.whistle = null;
        im.setMatrixAt(idx, _m.makeScale(0, 0, 0));
        im.instanceMatrix.needsUpdate = true;
        continue;
      }
      // visual: converge from muzzle to the true path, stretch along velocity for a motion trail
      p.offset.multiplyScalar(Math.max(0, 1 - dt * 14));
      _a.copy(p.pos).add(p.offset);
      const sp = p.vel.length();
      _q.setFromUnitVectors(_z, _b.copy(p.vel).divideScalar(Math.max(1e-4, sp)));
      const stretch = p.visual === 'arrow' ? 1 : p.visual === 'bubble' ? 1 + Math.min(0.4, sp * 0.004) : p.visual === 'bolt' ? 1 + Math.min(3, sp * 0.02) : 1 + Math.min(1.2, sp * 0.008);
      const sz = p.visual === 'bubble' ? rand(0.9, 1.1) : 1;
      _s.set(sz, sz, stretch * sz);
      _m.compose(_a, _q, _s);
      im.setMatrixAt(idx, _m);
      im.instanceMatrix.needsUpdate = true;
    }
  }

  explode(point: THREE.Vector3, normal: THREE.Vector3, p: Projectile, direct: Actor | null) {
    const ex = p.cfg.explosion!;
    const center = point.clone().addScaledVector(normal, 0.25);
    const colors = [p.color, pick(PAINT), pick(PAINT), '#ffffff'];
    this.fx.explosion(center, normal, colors, this.reducedMotion);
    this.fx.paintSplat(point, normal, p.color, 2.6);
    // extra paint splats on nearby surfaces
    for (let i = 0; i < 5; i++) {
      const d = new THREE.Vector3(rand(-1, 1), rand(-1, 0.4), rand(-1, 1)).normalize();
      const h = this.phys.raycast(center, d, ex.radius);
      if (h) this.fx.paintSplat(h.point, h.normal, pick([p.color, ...PAINT]), rand(0.8, 1.6));
    }
    this.audio.explosion(center);
    this.bricks.blast(center, ex.radius, 3.2);
    for (const a of this.actors()) {
      if (!a.alive || a === direct) continue;
      if (a !== p.shooter && p.shooter.team >= 0 && a.team === p.shooter.team) continue;
      a.chestPos(_h);
      const dist = _h.distanceTo(center);
      if (dist > ex.radius + 0.4) continue;
      if (!this.phys.los(center, _h, true)) continue;
      const f = Math.max(0, 1 - Math.max(0, dist - 0.4) / ex.radius);
      const wall = this.barriers.between(center, _h, p.shooter);
      if (wall) {
        this.barriers.damage(wall.b, ex.maxDamage * f * p.power * 0.5);
        continue;
      }
      let dmg = ex.maxDamage * f * p.power;
      if (a === p.shooter) dmg *= ex.selfDamageMult;
      if (dmg < 1) continue;
      this.applyDamage(a, p.shooter, dmg, false, _h.clone(), p.cfg.id, _h.clone().sub(center).normalize());
      // knockback
      const push = _h.clone().sub(center).setY(0.6).normalize().multiplyScalar(6 * f);
      a.vel.add(push);
    }
    this.events.emit('explosion', { pos: center, radius: ex.radius });
  }

  private stickArrow(point: THREE.Vector3, d: THREE.Vector3, color: string) {
    const i = this.stuckNext;
    this.stuckNext = (this.stuckNext + 1) % STUCK;
    _q.setFromUnitVectors(_z, d);
    _a.copy(point).addScaledVector(d, -0.5);
    this.stuck.setMatrixAt(i, _m.compose(_a, _q, _s.set(1, 1, 1)));
    this.stuck.setColorAt(i, new THREE.Color(color));
    this.stuck.instanceMatrix.needsUpdate = true;
    if (this.stuck.instanceColor) this.stuck.instanceColor.needsUpdate = true;
    this.stuckLife[i] = 8;
  }

  /**
   * Spring Punch: a spring-loaded boxing glove pops out and hits the closest enemy in front.
   * Returns the toy that got punched (or null on a whiff).
   */
  jab(attacker: Actor): Actor | null {
    const J = ABILITIES.jab;
    const eye = attacker.eyePos();
    const fwd = attacker.forward(new THREE.Vector3());
    attacker.revealAt = this.now;
    attacker.spawnProtectUntil = Math.min(attacker.spawnProtectUntil, this.now);
    const cosMax = Math.cos(J.coneDeg * DEG);
    let best: Actor | null = null;
    let bestD = Infinity;
    for (const a of this.actors()) {
      if (!a.alive || !attacker.isEnemy(a)) continue;
      const c = a.chestPos();
      const to = c.clone().sub(eye);
      const dist = to.length();
      if (dist > J.range + a.def.hitbox.bodyR + 0.4) continue;
      // be generous vertically: compare against the flattened aim when they're right next to us
      const dir = to.clone().divideScalar(Math.max(1e-4, dist));
      const flatF = fwd.clone().setY(0).normalize();
      const flatD = dir.clone().setY(0).normalize();
      if (dir.dot(fwd) < cosMax && (dist > 1.6 || flatD.dot(flatF) < cosMax)) continue;
      if (!this.phys.los(eye, c, true)) continue;
      if (this.barriers.between(eye, c, attacker)) continue;
      if (dist < bestD) {
        bestD = dist;
        best = a;
      }
    }
    if (!best) {
      // maybe we punched an enemy shield
      const wall = this.barriers.trace(eye, fwd, J.range, attacker);
      if (wall) this.hitBarrier(wall.b, eye.clone().addScaledVector(fwd, wall.t), J.damage);
      return null;
    }
    const point = best.chestPos();
    const push = point.clone().sub(attacker.pos).setY(0).normalize();
    const power = attacker.hasBuff('power', this.now) ? PICKUPS.powerMult : 1;
    attacker.shotsFired++;
    attacker.shotsHit++;
    this.applyDamage(best, attacker, J.damage * power, false, point, 'jab', push);
    best.vel.x += push.x * J.knockback;
    best.vel.z += push.z * J.knockback;
    best.vel.y = Math.max(best.vel.y, 3.5);
    this.fx.hitSpark(point, '#ff4d6d', false, true);
    for (let i = 0; i < 10; i++) this.fx.glow.emit(point, new THREE.Vector3(rand(-3, 3), rand(0, 4), rand(-3, 3)), new THREE.Color(pick(['#ffd166', '#ffffff', '#ff4d6d'])), rand(0.1, 0.2), rand(0.2, 0.4), { gravity: 6, drag: 3 });
    return best;
  }

  /** Single authority for damage + eliminations. */
  applyDamage(target: Actor, attacker: Actor | null, amount: number, head: boolean, point: THREE.Vector3, weapon: DamageSource, dir: THREE.Vector3) {
    if (!target.alive || amount <= 0) return;
    if (attacker && attacker !== target && attacker.team >= 0 && attacker.team === target.team) return;
    if (target.isProtected(this.now)) {
      this.fx.hitSpark(point, '#bdeeff', true, false);
      return;
    }
    // breaking spawn protection early if the protected toy fires is handled by the shooter code
    const shieldDmg = Math.min(target.shield, amount);
    target.shield -= shieldDmg;
    const healthDmg = Math.min(target.health, amount - shieldDmg);
    target.health -= amount - shieldDmg;
    target.lastDamageAt = this.now;
    target.recentDamage.push({ t: this.now, amount });
    target.hitFlinch = Math.min(1, target.hitFlinch + 0.6);
    if (attacker && attacker !== target) {
      target.lastAttacker = attacker;
      target.lastAttackerAt = this.now;
      attacker.damageDealt += shieldDmg + healthDmg;
    }
    const shieldBroke = shieldDmg > 0 && target.shield <= 0;
    this.fx.hitSpark(point, target.def.colors[0], shieldDmg > 0 && healthDmg <= 0, head);
    const fromDir = attacker ? attacker.eyePos().sub(target.eyePos()).normalize() : dir.clone().negate();
    this.events.emit('damage', { attacker, target, amount: shieldDmg + healthDmg, shieldDmg, healthDmg, head, point: point.clone(), weapon, fromDir, shieldBroke });
    if (attacker && attacker !== target) this.events.emit('hit', { attacker, target, head, shield: shieldDmg > 0 && healthDmg <= 0 });
    if (target.health <= 0) this.eliminate(target, attacker, weapon, head);
  }

  private eliminate(victim: Actor, killer: Actor | null, weapon: DamageSource, head: boolean) {
    if (!victim.alive) return; // never double-count
    victim.alive = false;
    victim.health = 0;
    victim.deaths++;
    victim.streak = 0;
    victim.respawnAt = this.now + COMBAT.respawnTime;
    victim.despawn();
    // credit: direct killer, or whoever hurt them last (falling blocks / self splash)
    let credit = killer && killer !== victim ? killer : null;
    if (!credit && victim.lastAttacker && victim.lastAttacker !== victim && this.now - victim.lastAttackerAt < 5) credit = victim.lastAttacker;
    if (credit) {
      credit.kills++;
      credit.streak++;
      credit.bestStreak = Math.max(credit.bestStreak, credit.streak);
      credit.scoreAt = this.now;
      if (head) credit.headshots++;
    }
    const pos = victim.pos.clone();
    this.fx.breakApart(pos, victim.def.colors, this.reducedMotion);
    this.audio.eliminated(pos.clone().setY(pos.y + 1));
    this.events.emit('kill', { killer: credit, victim, weapon, head, time: this.now });
  }

  clear() {
    this.barriers.clear();
    for (let i = 0; i < STUCK; i++) {
      this.stuckLife[i] = 0;
      this.stuck.setMatrixAt(i, _m.makeScale(0, 0, 0));
    }
    this.stuck.instanceMatrix.needsUpdate = true;
    for (const p of this.projectiles) {
      p.active = false;
      p.whistle?.stop();
      p.whistle = null;
    }
    for (const im of Object.values(this.meshes)) {
      for (let i = 0; i < im.count; i++) im.setMatrixAt(i, _m.makeScale(0, 0, 0));
      im.instanceMatrix.needsUpdate = true;
    }
  }
}

export type { SurfaceMat };

import * as THREE from 'three';
import type RAPIER from '@dimforge/rapier3d-compat';
import { Physics, SurfaceMat } from '../physics/Physics';
import { ABILITIES, AbilityId, COMBAT, MOVE, PICKUPS, ScopeId, WeaponId } from '../weapons/weaponConfig';
import { WeaponState } from '../weapons/WeaponState';
import { CharacterDef, ToyRig } from './ToyModels';
import { clamp, damp } from '../core/math';

export interface MoveIntent {
  wish: THREE.Vector3; // world-space XZ, length 0..1
  sprint: boolean;
  jump: boolean; // pressed this frame
  crouch: boolean; // held
  crouchPressed: boolean;
  dash: boolean; // pressed
  ads: boolean;
}

export const emptyIntent = (): MoveIntent => ({ wish: new THREE.Vector3(), sprint: false, jump: false, crouch: false, crouchPressed: false, dash: false, ads: false });

export interface MoveEvents {
  onJump?: (a: Actor) => void;
  onLand?: (a: Actor, impact: number) => void;
  onSlide?: (a: Actor) => void;
  onDash?: (a: Actor, from: THREE.Vector3) => void;
  onFootstep?: (a: Actor) => void;
  onGrappleEnd?: (a: Actor) => void;
}

const _v = new THREE.Vector3();
const _down = new THREE.Vector3(0, -1, 0);

/** Anything that walks, shoots and can be eliminated: the player and every bot. */
export class Actor {
  static nextId = 1;
  id = Actor.nextId++;
  name: string;
  collider: RAPIER.Collider;
  cc: RAPIER.KinematicCharacterController;
  pos = new THREE.Vector3();
  vel = new THREE.Vector3();
  yaw = 0;
  pitch = 0;
  grounded = false;
  groundMat: SurfaceMat = 'wood';
  lastGrounded = -10;
  jumpBufferAt = -10;
  jumped = false;
  crouching = false;
  crouchT = 0;
  sliding = false;
  slideT = 0;
  slideReadyAt = 0;
  private slideBufferAt = -10;
  private slideDir = new THREE.Vector3();
  dashing = false;
  dashT = 0;
  dashReadyAt = 0;
  private dashDir = new THREE.Vector3();
  private dashFrom = new THREE.Vector3();
  private halfHeight = MOVE.standHalfHeight;
  health = COMBAT.maxHealth;
  shield = 0;
  alive = true;
  respawnAt = 0;
  lastDamageAt = -99;
  spawnProtectUntil = 0;
  weapons: (WeaponState | null)[] = [null, null];
  slot = 0;
  buffs = { turbo: 0, infinite: 0, power: 0 };
  kills = 0;
  deaths = 0;
  streak = 0;
  bestStreak = 0;
  damageDealt = 0;
  shotsFired = 0;
  shotsHit = 0;
  headshots = 0;
  /** -1 = no team (free-for-all), 0 = Sunrise, 1 = Moonbeam */
  team = -1;
  lastAttacker: Actor | null = null;
  lastAttackerAt = -99;
  ads = 0;
  fireKick = 0;
  hitFlinch = 0;
  model: ToyRig | null = null;
  private stepAcc = 0;
  private groundProbeT = 0;
  lastFootstepSide = 0;
  /** horizontal speed last frame */
  speed = 0;
  scoreAt = 0; // time the actor last scored (tie break)
  // ---- abilities
  /** the two abilities this toy brought (player: from the loadout; bots: from their personality) */
  abilities: AbilityId[] = ['dash', 'grapple'];
  has(id: AbilityId) {
    return this.abilities.includes(id);
  }
  /** last time this toy attacked (firing or punching breaks cloak) */
  revealAt = -99;
  jabReadyAt = 0;
  grappleReadyAt = 0;
  cloakReadyAt = 0;
  shieldReadyAt = 0;
  cloaked = false;
  cloakStart = 0;
  /** seconds left on the punch animation */
  jabT = 0;
  grapple: { anchor: THREE.Vector3; start: number; checkAt: number; checkDist: number; climbing: boolean } | null = null;
  // ---- revive (team modes)
  /** seconds a teammate has been holding on to this downed toy */
  reviveT = 0;
  /** teammate who is reviving (or on the way to revive) this toy */
  reviver: Actor | null = null;
  revives = 0;
  /** Popped but still revivable: team modes only, until the respawn timer runs out. */
  isDowned(now: number) {
    return !this.alive && this.team >= 0 && this.respawnAt > now;
  }
  /** recent damage taken (bots use it to decide when to run) */
  recentDamage: { t: number; amount: number }[] = [];
  /** short window after a hook lands below a ledge: keep pushing up and over it */
  private mantle: { until: number; dir: THREE.Vector3 } | null = null;

  constructor(public def: CharacterDef, public isPlayer: boolean, private phys: Physics) {
    this.name = def.name;
    const c = phys.character(new THREE.Vector3(0, -50, 0), MOVE.radius, MOVE.standHalfHeight);
    this.collider = c.collider;
    this.cc = phys.controller();
  }

  get weapon(): WeaponState | null {
    return this.weapons[this.slot];
  }
  get eyeHeight() {
    return MOVE.standEye + (MOVE.crouchEye - MOVE.standEye) * this.crouchT;
  }
  eyePos(out = new THREE.Vector3()) {
    return out.set(this.pos.x, this.pos.y + this.eyeHeight, this.pos.z);
  }
  chestPos(out = new THREE.Vector3()) {
    return out.set(this.pos.x, this.pos.y + 1.05 - this.crouchT * 0.38, this.pos.z);
  }
  headPos(out = new THREE.Vector3()) {
    return out.set(this.pos.x, this.pos.y + this.def.hitbox.headY - this.crouchT * 0.42, this.pos.z);
  }
  bodySegment(a: THREE.Vector3, b: THREE.Vector3) {
    const hb = this.def.hitbox;
    a.set(this.pos.x, this.pos.y + hb.bodyBottom + hb.bodyR, this.pos.z);
    b.set(this.pos.x, this.pos.y + Math.max(hb.bodyBottom + hb.bodyR + 0.05, hb.bodyTop - hb.bodyR - this.crouchT * 0.4), this.pos.z);
  }
  forward(out = new THREE.Vector3()) {
    return out.set(-Math.sin(this.yaw) * Math.cos(this.pitch), Math.sin(this.pitch), -Math.cos(this.yaw) * Math.cos(this.pitch));
  }
  isEnemy(o: Actor) {
    return o !== this && (this.team < 0 || o.team !== this.team);
  }
  isProtected(now: number) {
    return now < this.spawnProtectUntil;
  }
  hasBuff(k: keyof Actor['buffs'], now: number) {
    return this.buffs[k] > now;
  }
  speedMult(now: number) {
    return this.hasBuff('turbo', now) ? PICKUPS.turboMult : 1;
  }

  giveWeapon(id: WeaponId, slot: number, scope?: ScopeId) {
    this.weapons[slot] = new WeaponState(id, scope);
  }

  teleport(feet: THREE.Vector3) {
    this.pos.copy(feet);
    this.vel.set(0, 0, 0);
    this.syncCollider();
  }
  /** Push the collider to the current position without touching velocity. */
  sync() {
    this.syncCollider();
  }
  private syncCollider() {
    if (this.disposed) return;
    this.collider.setTranslation({ x: this.pos.x, y: this.pos.y + this.halfHeight + MOVE.radius, z: this.pos.z });
  }
  private setHalfHeight(h: number) {
    if (this.disposed) return;
    if (Math.abs(this.halfHeight - h) < 1e-3) return;
    this.halfHeight = h;
    this.collider.setHalfHeight(h);
    this.syncCollider();
  }

  /** Cloak toggles: on if ready, off if already active. Cooldown = time spent cloaked + base. */
  toggleCloak(now: number) {
    if (this.cloaked) {
      this.endCloak(now);
      return true;
    }
    if (now < this.cloakReadyAt) return false;
    this.cloaked = true;
    this.cloakStart = now;
    return true;
  }
  endCloak(now: number) {
    if (!this.cloaked) return;
    const active = Math.min(ABILITIES.cloak.maxActive, now - this.cloakStart);
    this.cloaked = false;
    this.cloakReadyAt = now + active + ABILITIES.cloak.baseCooldown;
  }
  startGrapple(anchor: THREE.Vector3, now: number) {
    this.grapple = { anchor: anchor.clone(), start: now, checkAt: now + 0.3, checkDist: Infinity, climbing: false };
    this.grappleReadyAt = now + ABILITIES.grapple.cooldown;
    this.dashing = this.sliding = false;
    this.grounded = false;
  }
  private grappleEndTime = 0;
  private releaseGrapple(jumped: boolean, ev: MoveEvents) {
    const g = this.grapple;
    if (!g) return;
    this.grapple = null;
    this.vel.multiplyScalar(0.7);
    // pop up over the ledge we were pulled to, and keep moving onto it
    this.vel.y = Math.min(this.vel.y, 7);
    if (g.anchor.y > this.pos.y + 0.3) this.vel.y = Math.max(this.vel.y, 6);
    const hx = g.anchor.x - this.pos.x, hz = g.anchor.z - this.pos.z;
    const hl = Math.hypot(hx, hz);
    if (hl > 0.3 && hl < 3 && Math.abs(g.anchor.y - this.pos.y) < 2.5) {
      const s = Math.max(4.5, Math.hypot(this.vel.x, this.vel.z));
      this.vel.x = (hx / hl) * s;
      this.vel.z = (hz / hl) * s;
      if (g.anchor.y > this.pos.y - 0.2) {
        this.vel.y = Math.max(this.vel.y, 7.5);
        this.mantle = { until: this.grappleEndTime + 0.45, dir: new THREE.Vector3(hx / hl, 0, hz / hl) };
      }
    }
    if (jumped) this.vel.y = Math.max(this.vel.y, 7.5);
    this.jumped = true;
    ev.onGrappleEnd?.(this);
  }
  damageInLast(seconds: number, now: number) {
    let s = 0;
    for (const d of this.recentDamage) if (now - d.t <= seconds) s += d.amount;
    return s;
  }

  spawn(at: THREE.Vector3, yaw: number, now: number) {
    this.alive = true;
    this.reviveT = 0;
    this.reviver = null;
    this.cloaked = false;
    this.grapple = null;
    this.mantle = null;
    this.jabT = 0;
    this.recentDamage = [];
    this.health = COMBAT.maxHealth;
    this.shield = 0;
    this.buffs = { turbo: 0, infinite: 0, power: 0 };
    this.lastDamageAt = -99;
    this.spawnProtectUntil = now + COMBAT.spawnProtection;
    this.yaw = yaw;
    this.pitch = 0;
    this.sliding = this.dashing = false;
    this.crouching = false;
    this.crouchT = 0;
    this.setHalfHeight(MOVE.standHalfHeight);
    this.lastAttacker = null;
    this.collider.setEnabled(true);
    this.teleport(at);
    this.grounded = false;
    this.hitFlinch = 0;
  }
  despawn() {
    this.cloaked = false;
    this.grapple = null;
    if (this.disposed) return;
    this.collider.setEnabled(false);
  }

  /** Shared locomotion for player and bots. */
  move(intent: MoveIntent, dt: number, now: number, ev: MoveEvents = {}) {
    if (!this.alive || this.disposed) return;
    const hspeed = Math.hypot(this.vel.x, this.vel.z);
    const sm = this.speedMult(now);
    // --- slide start
    if (intent.crouchPressed) this.slideBufferAt = now;
    const slideWanted = now - this.slideBufferAt < 0.15 && intent.crouch;
    if (slideWanted && (this.grounded || now - this.lastGrounded < 0.08) && !this.sliding && hspeed > MOVE.walkSpeed * 1.15 && now >= this.slideReadyAt) {
      this.slideBufferAt = -10;
      this.sliding = true;
      this.slideT = MOVE.slideDuration;
      this.slideDir.set(this.vel.x, 0, this.vel.z).normalize();
      const boost = Math.max(hspeed, MOVE.slideBoost * sm);
      this.vel.x = this.slideDir.x * boost;
      this.vel.z = this.slideDir.z * boost;
      ev.onSlide?.(this);
    }
    // --- crouch (stay crouched if there's no head room)
    let wantCrouch = intent.crouch || this.sliding;
    if (!wantCrouch && this.crouching) {
      if (!this.phys.capsuleFits(this.pos, MOVE.radius - 0.02, MOVE.standHalfHeight)) wantCrouch = true;
    }
    this.crouching = wantCrouch;
    this.setHalfHeight(this.crouching ? MOVE.crouchHalfHeight : MOVE.standHalfHeight);
    this.crouchT = damp(this.crouchT, this.crouching ? 1 : 0, 14, dt);
    // --- grapple pull (overrides everything else)
    if (this.grapple) {
      const g = this.grapple;
      const to = _v.set(g.anchor.x - this.pos.x, g.anchor.y - (this.pos.y + 1.0), g.anchor.z - this.pos.z);
      const dist = to.length();
      const t = now - g.start;
      let stalled = false;
      // pressed against a wall below the ledge: climb straight up it until we're level with the top
      if (g.climbing && this.pos.y >= g.anchor.y - 0.3) g.climbing = false;
      if (now >= g.checkAt && g.climbing) {
        g.checkDist = dist;
        g.checkAt = now + 0.25;
      }
      if (now >= g.checkAt) {
        // barely got closer in the last quarter second = something is in the way
        stalled = g.checkDist - dist < 1.2;
        g.checkDist = dist;
        g.checkAt = now + 0.25;
      }
      if (dist < 1.3 || t > ABILITIES.grapple.maxTime || stalled || (intent.jump && t > 0.12)) {
        this.grappleEndTime = now;
        this.releaseGrapple(intent.jump && t > 0.12, ev);
        intent.jump = false;
        this.jumpBufferAt = -10;
      } else {
        const sp = ABILITIES.grapple.speed * Math.min(1, 0.45 + t * 3);
        if (g.climbing) this.vel.set(0, sp * 0.8, 0);
        else this.vel.copy(to).multiplyScalar(sp / Math.max(1e-3, dist));
      }
    }
    // --- mantle over the ledge we hooked
    if (this.mantle) {
      if (now > this.mantle.until || this.grounded) this.mantle = null;
      else {
        const along = this.vel.x * this.mantle.dir.x + this.vel.z * this.mantle.dir.z;
        if (along < 4.5) {
          this.vel.x += this.mantle.dir.x * (4.5 - along);
          this.vel.z += this.mantle.dir.z * (4.5 - along);
        }
        if (this.vel.y < 2) this.vel.y = 2;
      }
    }
    // --- dash
    if (intent.dash && this.has('dash') && now >= this.dashReadyAt && !this.dashing && !this.grapple) {
      this.dashing = true;
      this.dashT = MOVE.dashDuration;
      this.dashReadyAt = now + MOVE.dashCooldown;
      if (intent.wish.lengthSq() > 0.01) this.dashDir.copy(intent.wish).setY(0).normalize();
      else this.dashDir.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
      this.dashFrom.copy(this.pos);
      this.sliding = false;
      ev.onDash?.(this, this.dashFrom);
    }
    // --- target speed
    let target = MOVE.walkSpeed;
    const fwd = _v.set(-Math.sin(this.yaw), 0, -Math.cos(this.yaw));
    const forwardish = intent.wish.lengthSq() > 0.01 && intent.wish.dot(fwd) > 0.5;
    if (this.crouching) target = MOVE.crouchSpeed;
    else if (intent.sprint && forwardish && this.ads < 0.3) target = MOVE.walkSpeed * MOVE.sprintMult;
    const w = this.weapon;
    if (w && this.ads > 0) target *= 1 + (w.cfg.adsMoveMult - 1) * this.ads;
    if (w && w.drawing && w.cfg.charge) target = Math.min(target, MOVE.walkSpeed) * w.cfg.charge.moveMult;
    target *= sm;

    if (this.grapple) {
      // velocity already set by the hook
    } else if (this.dashing) {
      this.dashT -= dt;
      const sp = MOVE.dashSpeed * sm;
      this.vel.x = this.dashDir.x * sp;
      this.vel.z = this.dashDir.z * sp;
      if (this.vel.y < 0) this.vel.y = 0;
      if (this.dashT <= 0) {
        this.dashing = false;
        // keep some momentum
        this.vel.x *= 0.45;
        this.vel.z *= 0.45;
      }
    } else if (this.sliding) {
      this.slideT -= dt;
      const cur = Math.hypot(this.vel.x, this.vel.z);
      const ns = Math.max(MOVE.crouchSpeed, cur - 9 * dt);
      // slight steering
      if (intent.wish.lengthSq() > 0.01) this.slideDir.lerp(intent.wish, 1.5 * dt).normalize();
      this.vel.x = this.slideDir.x * ns;
      this.vel.z = this.slideDir.z * ns;
      if (this.slideT <= 0 || !this.grounded && now - this.lastGrounded > 0.25) {
        this.sliding = false;
        this.slideReadyAt = now + MOVE.slideCooldown;
      }
    } else if (this.grounded) {
      const tx = intent.wish.x * target, tz = intent.wish.z * target;
      const dx = tx - this.vel.x, dz = tz - this.vel.z;
      const dl = Math.hypot(dx, dz);
      const accel = intent.wish.lengthSq() > 0.01 ? MOVE.groundAccel : MOVE.groundDecel;
      const step = Math.min(dl, accel * dt);
      if (dl > 1e-5) {
        this.vel.x += (dx / dl) * step;
        this.vel.z += (dz / dl) * step;
      }
    } else {
      // small air control: steer without exceeding current/ target speed
      const cur = Math.hypot(this.vel.x, this.vel.z);
      this.vel.x += intent.wish.x * MOVE.airAccel * dt;
      this.vel.z += intent.wish.z * MOVE.airAccel * dt;
      const ns = Math.hypot(this.vel.x, this.vel.z);
      const cap = Math.max(cur, target * MOVE.airControl + cur * (1 - MOVE.airControl), target * 0.6);
      if (ns > cap) {
        this.vel.x *= cap / ns;
        this.vel.z *= cap / ns;
      }
    }
    // --- jump with coyote time + input buffer
    if (intent.jump) this.jumpBufferAt = now;
    const canJump = (this.grounded || now - this.lastGrounded < MOVE.coyoteTime) && !this.jumped;
    if (now - this.jumpBufferAt <= MOVE.jumpBuffer && canJump && !this.dashing && !this.grapple) {
      this.vel.y = MOVE.jumpVelocity;
      this.grounded = false;
      this.jumped = true;
      this.jumpBufferAt = -10;
      if (this.sliding) {
        this.sliding = false;
        this.slideReadyAt = now + MOVE.slideCooldown;
      }
      ev.onJump?.(this);
    }
    // --- gravity
    if (!this.dashing && !this.grapple) this.vel.y -= MOVE.gravity * dt;
    if (this.vel.y < -40) this.vel.y = -40;

    // --- collide & slide
    const desired = { x: this.vel.x * dt, y: this.vel.y * dt, z: this.vel.z * dt };
    this.cc.computeColliderMovement(this.collider, desired, undefined, this.phys.charQueryGroups());
    const mv = this.cc.computedMovement();
    this.pos.x += mv.x;
    this.pos.y += mv.y;
    this.pos.z += mv.z;
    this.syncCollider();
    const wasGrounded = this.grounded;
    this.grounded = this.cc.computedGrounded();
    if (this.grounded) {
      this.lastGrounded = now;
      if (this.vel.y <= 0) {
        if (!wasGrounded && this.vel.y < -3) ev.onLand?.(this, clamp(-this.vel.y / 14, 0, 1));
        this.vel.y = 0;
        this.jumped = false;
      }
    }
    // stop velocity building up against walls / ceilings
    if (dt > 0) {
      const dh = Math.hypot(desired.x, desired.z);
      const mh = Math.hypot(mv.x, mv.z);
      if (dh > 1e-4 && mh < dh * 0.7 && !this.dashing && !this.grapple && !this.mantle) {
        this.vel.x = (mv.x / dt) * 0.9 + this.vel.x * 0.1;
        this.vel.z = (mv.z / dt) * 0.9 + this.vel.z * 0.1;
      }
      if (desired.y > 0 && mv.y < desired.y * 0.4 && !this.grapple) this.vel.y = Math.min(this.vel.y, 0);
      const gr = this.grapple;
      if (gr && !gr.climbing && dh > 1e-3 && mh < dh * 0.4 && gr.anchor.y > this.pos.y + 0.2) gr.climbing = true;
    }
    // fell out of the world: put back on the rug
    if (this.pos.y < -5) this.teleport(new THREE.Vector3(2, 6, 1));
    this.speed = Math.hypot(this.vel.x, this.vel.z);
    // ground material probe (for footsteps)
    this.groundProbeT -= dt;
    if (this.grounded && this.groundProbeT <= 0) {
      this.groundProbeT = 0.15;
      const hit = this.phys.raycast(_v.set(this.pos.x, this.pos.y + 0.3, this.pos.z), _down, 0.8);
      if (hit) this.groundMat = hit.mat;
    }
    // footsteps by distance travelled
    if (this.grounded && !this.sliding && this.speed > 1) {
      this.stepAcc += this.speed * dt;
      const stride = this.speed > 7 ? 2.3 : this.crouching ? 1.4 : 1.9;
      if (this.stepAcc > stride) {
        this.stepAcc = 0;
        this.lastFootstepSide ^= 1;
        ev.onFootstep?.(this);
      }
    }
  }

  /** Called every frame for regen, buffs, timers. */
  tick(dt: number, now: number) {
    if (!this.alive) return;
    if (now - this.lastDamageAt > COMBAT.regenDelay && this.health < COMBAT.maxHealth) {
      this.health = Math.min(COMBAT.maxHealth, this.health + COMBAT.regenRate * dt);
    }
    this.fireKick = Math.max(0, this.fireKick - dt * 6);
    this.jabT = Math.max(0, this.jabT - dt);
    if (this.cloaked && (now - this.cloakStart >= ABILITIES.cloak.maxActive || this.revealAt > this.cloakStart)) this.endCloak(now);
    if (this.recentDamage.length && now - this.recentDamage[0].t > 5) this.recentDamage.shift();
    this.hitFlinch = Math.max(0, this.hitFlinch - dt * 4);
    for (const w of this.weapons) if (w) w.update(dt, now);
  }

  disposed = false;
  dispose(phys: Physics) {
    if (this.disposed) return;
    this.disposed = true;
    phys.world.removeCollider(this.collider, false);
    phys.world.removeCharacterController(this.cc);
  }
}

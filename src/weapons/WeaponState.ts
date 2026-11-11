import { SCOPES, ScopeDef, ScopeId, WEAPONS, WEAPON_SCOPES, WeaponConfig, WeaponId } from './weaponConfig';
import { clamp, moveToward, rand } from '../core/math';

export type ReloadPart = 'out' | 'in' | 'charge' | 'shell' | 'spring' | 'vent' | 'pump' | 'open' | 'close';

/** Timeline of reload sounds/animation beats, as fractions of the reload. */
const RELOAD_BEATS: Partial<Record<WeaponId, [number, ReloadPart][]>> = {
  plasti9: [[0.12, 'out'], [0.55, 'in'], [0.82, 'charge']],
  foamFury: [[0.12, 'out'], [0.5, 'in'], [0.78, 'charge']],
  brickbreaker: [[0.15, 'out'], [0.52, 'in'], [0.8, 'charge']],
  thunderspring: [[0.1, 'out'], [0.4, 'in'], [0.62, 'spring']],
  rapidRascal: [[0.14, 'out'], [0.55, 'in'], [0.85, 'charge']],
  crayonCannon: [[0.15, 'out'], [0.55, 'in'], [0.82, 'charge']],
  jackBlaster: [[0.12, 'open'], [0.45, 'in'], [0.75, 'spring'], [0.92, 'close']],
  plungerBow: [[0.15, 'out'], [0.55, 'in'], [0.85, 'charge']],
  popcornPopper: [[0.12, 'out'], [0.52, 'in'], [0.8, 'charge']],
  walloper: [[0.12, 'out'], [0.5, 'in'], [0.82, 'charge']],
};

/**
 * Runtime state of one equipped weapon: ammo, reload, fire timing, bloom and recoil bookkeeping.
 * Shared by the player and the bots so both follow identical rules.
 */
export class WeaponState {
  cfg: WeaponConfig;
  mag: number;
  reserve: number;
  reloading = false;
  reloadT = 0;
  /** shotgun: shell-by-shell */
  private shellPhase: 'open' | 'shells' | 'close' = 'open';
  private shellTimer = 0;
  private beatIdx = 0;
  nextFire = 0;
  shotIndex = 0;
  lastShot = -10;
  bloom = 0;
  recoilPitch = 0;
  recoilYaw = 0;
  lockout = false;
  equipT = 0;
  /** charge weapons (bow): time the draw started, -1 when not drawing */
  drawStart = -1;
  /** charge (0..1) of the shot that was just released */
  lastCharge = 1;
  onReloadBeat: ((part: ReloadPart) => void) | null = null;
  onReloadDone: (() => void) | null = null;

  scope: ScopeDef;
  /** shots left in the current burst */
  private burstLeft = 0;
  private burstNext = 0;

  constructor(public id: WeaponId, scope?: ScopeId) {
    this.cfg = WEAPONS[id];
    const fits = WEAPON_SCOPES[id];
    this.scope = SCOPES[scope && fits.includes(scope) ? scope : fits[0]];
    this.mag = this.cfg.magSize;
    this.reserve = this.cfg.reserve;
  }

  /** zoom factor when fully aimed */
  get zoom() {
    return this.scope.zoom ?? this.cfg.adsZoom;
  }
  get adsTime() {
    return this.cfg.adsTime * this.scope.adsTimeMult;
  }
  /** full-screen scope picture when aimed */
  get overlay() {
    return this.scope.style === 'overlay';
  }
  get isEnergy() {
    return !!this.cfg.energy;
  }
  get reloadDuration() {
    return this.cfg.reloadTime;
  }
  /** 0..1 progress for HUD */
  get reloadProgress() {
    if (!this.reloading) return 0;
    if (this.cfg.reloadPerShell) {
      const need = this.cfg.magSize;
      return clamp(this.mag / need, 0, 1);
    }
    return clamp(this.reloadT / this.cfg.reloadTime, 0, 1);
  }
  get interval() {
    return 60 / this.cfg.rpm;
  }

  get isCharge() {
    return !!this.cfg.charge;
  }
  get drawing() {
    return this.drawStart >= 0;
  }
  /** 0..1 how far the bow is drawn right now */
  chargeAt(now: number) {
    if (!this.cfg.charge || this.drawStart < 0) return 0;
    return clamp((now - this.drawStart) / this.cfg.charge.time, 0, 1);
  }
  cancelDraw() {
    this.drawStart = -1;
  }

  equip(now: number, time = 0.32) {
    this.cancelReload();
    this.cancelDraw();
    this.burstLeft = 0;
    this.equipT = time;
    this.nextFire = Math.max(this.nextFire, now + time * 0.8);
  }

  canStartReload() {
    if (this.isEnergy || this.reloading) return false;
    return this.mag < this.cfg.magSize && this.reserve > 0;
  }
  startReload() {
    if (!this.canStartReload()) return false;
    this.cancelDraw();
    this.reloading = true;
    this.burstLeft = 0;
    this.reloadT = 0;
    this.beatIdx = 0;
    this.shellPhase = 'open';
    this.shellTimer = 0.25;
    if (this.cfg.reloadPerShell) this.onReloadBeat?.('open');
    return true;
  }
  /** Interrupting never refills: ammo is only granted when the reload (or a shell) completes. */
  cancelReload() {
    this.reloading = false;
    this.reloadT = 0;
    this.beatIdx = 0;
  }

  /** Energy weapon manual vent: skips the recharge delay. */
  vent(now: number) {
    if (!this.isEnergy || this.mag >= this.cfg.magSize) return false;
    this.lastShot = now - (this.cfg.energy!.rechargeDelay + 0.01);
    this.onReloadBeat?.('vent');
    return true;
  }

  /**
   * Returns how many shots should be fired this frame (0..2) given trigger state.
   * Consumes ammo. Infinite = Infinite Springs power-up.
   */
  pullTrigger(now: number, pressed: boolean, held: boolean, infinite: boolean): number {
    if (this.equipT > 0) return 0;
    if (this.cfg.charge) return this.pullCharge(now, pressed, held, infinite);
    if (this.cfg.burst) return this.pullBurst(now, held, infinite);
    const wants = this.cfg.auto ? held : pressed;
    if (!wants) return 0;
    if (this.lockout) return 0;
    if (this.mag <= 0 && !infinite) return -1; // dry fire
    if (this.reloading) {
      if (this.cfg.reloadPerShell && this.mag > 0) this.cancelReload();
      else if (!infinite) return 0;
      else this.cancelReload();
    }
    if (now < this.nextFire) return 0;
    let shots = 0;
    // catch up at most one extra shot for low frame rates, never bank shots after a pause
    if (this.nextFire < now - this.interval * 2) this.nextFire = now;
    while (now >= this.nextFire && shots < 2 && (this.mag > 0 || infinite)) {
      shots++;
      this.nextFire += this.interval;
      if (!infinite) this.mag -= this.isEnergy ? this.cfg.energy!.perShot : 1;
      if (!this.cfg.auto) break;
    }
    if (this.nextFire < now) this.nextFire = now + this.interval;
    if (this.isEnergy && this.mag <= 0) {
      this.mag = 0;
      this.lockout = true;
    }
    if (shots > 0) {
      if (now - this.lastShot > Math.max(0.28, this.interval * 2.2)) this.shotIndex = 0;
      this.lastShot = now;
    }
    return shots;
  }

  /** Burst fire: one pull starts a burst that finishes on its own; holding the trigger keeps bursting. */
  private pullBurst(now: number, held: boolean, infinite: boolean): number {
    const b = this.cfg.burst!;
    if (this.burstLeft <= 0) {
      if (!held) return 0;
      if (this.mag <= 0 && !infinite) return -1;
      if (this.reloading) {
        if (!infinite) return 0;
        this.cancelReload();
      }
      if (now < this.nextFire) return 0;
      this.burstLeft = b.count;
      this.burstNext = now;
      if (now - this.lastShot > Math.max(0.28, this.interval * 1.5)) this.shotIndex = 0;
    }
    if (now < this.burstNext) return 0;
    if (this.mag <= 0 && !infinite) {
      this.burstLeft = 0;
      this.nextFire = now + this.interval;
      return 0;
    }
    if (!infinite) this.mag -= 1;
    this.burstLeft--;
    this.burstNext = now + b.gap;
    this.lastShot = now;
    if (this.burstLeft <= 0) this.nextFire = now + this.interval;
    return 1;
  }

  /**
   * Bow: hold to draw, release to loose. Damage scales with how long it was held (see lastCharge).
   * Returns 1 on release, -1 for a dry pull, else 0.
   */
  private pullCharge(now: number, pressed: boolean, held: boolean, infinite: boolean): number {
    if (this.drawStart >= 0) {
      if (held) return 0;
      // released: loose the arrow
      this.lastCharge = this.chargeAt(now);
      this.drawStart = -1;
      if (!infinite) this.mag -= 1;
      this.nextFire = now + this.interval;
      if (now - this.lastShot > 1) this.shotIndex = 0;
      this.lastShot = now;
      return 1;
    }
    if (!held) return 0;
    if (this.mag <= 0 && !infinite) return pressed ? -1 : 0;
    if (this.reloading) {
      if (!pressed) return 0;
      this.cancelReload();
    }
    if (now < this.nextFire) return 0;
    this.drawStart = now;
    return 0;
  }

  /** Computes the recoil kick (deg) for the current shot and advances the spray index. */
  kick(ads: boolean): { pitch: number; yaw: number } {
    const r = this.cfg.recoil;
    let pitch = 0, yaw = 0;
    const i = this.shotIndex;
    if (r.kind === 'pattern') {
      let k = i;
      if (k >= r.pitch.length) k = r.loopFrom + ((k - r.loopFrom) % (r.pitch.length - r.loopFrom));
      pitch = r.pitch[k] + rand(-r.jitter, r.jitter);
      yaw = r.yaw[k] + rand(-r.jitter, r.jitter);
    } else {
      pitch = Math.min(r.pitchMax, r.pitch + r.pitchGrowth * i);
      const yv = r.yaw + r.yawGrowth * i;
      yaw = rand(-yv, yv) + r.yawBias * Math.min(i, 8);
    }
    const mult = ads ? this.cfg.adsRecoilMult : 1;
    pitch *= mult;
    yaw *= mult;
    this.recoilPitch += pitch;
    this.recoilYaw += yaw;
    this.bloom = Math.min(this.cfg.spread.bloomMax, this.bloom + this.cfg.spread.bloomPerShot);
    this.shotIndex++;
    return { pitch, yaw };
  }

  /** Current spread cone half-angle in degrees. */
  spread(ads: number, moving: number, airborne: boolean) {
    const s = this.cfg.spread;
    const base = s.hip + (s.ads - s.hip) * ads;
    return base + s.move * moving * (1 - ads * 0.6) + (airborne ? s.air : 0) + this.bloom;
  }

  update(dt: number, now: number) {
    if (this.equipT > 0) this.equipT = Math.max(0, this.equipT - dt);
    this.bloom = moveToward(this.bloom, 0, this.cfg.spread.bloomDecay * dt * (now - this.lastShot > 0.15 ? 1 : 0.35));
    // camera recoil recovery
    if (now - this.lastShot > this.cfg.recoveryDelay) {
      const rate = this.cfg.recoveryRate * dt;
      this.recoilPitch = moveToward(this.recoilPitch, 0, rate);
      this.recoilYaw = moveToward(this.recoilYaw, 0, rate * 0.8);
    }
    // energy recharge
    if (this.isEnergy) {
      const e = this.cfg.energy!;
      if (now - this.lastShot > e.rechargeDelay && this.mag < this.cfg.magSize) {
        this.mag = Math.min(this.cfg.magSize, this.mag + e.rechargeRate * dt);
      }
      if (this.lockout && this.mag >= e.lockoutUntil) this.lockout = false;
      return;
    }
    if (!this.reloading) return;
    if (this.cfg.reloadPerShell) {
      this.shellTimer -= dt;
      if (this.shellTimer <= 0) {
        if (this.shellPhase === 'open') {
          this.shellPhase = 'shells';
          this.shellTimer = this.cfg.reloadPerShell;
        } else if (this.shellPhase === 'shells') {
          if (this.mag < this.cfg.magSize && this.reserve > 0) {
            this.mag++;
            this.reserve--;
            this.onReloadBeat?.('shell');
          }
          if (this.mag >= this.cfg.magSize || this.reserve <= 0) {
            this.shellPhase = 'close';
            this.shellTimer = 0.3;
            this.onReloadBeat?.('pump');
          } else this.shellTimer = this.cfg.reloadPerShell;
        } else {
          this.reloading = false;
          this.onReloadDone?.();
        }
      }
      return;
    }
    this.reloadT += dt;
    const beats = RELOAD_BEATS[this.id] ?? [];
    const f = this.reloadT / this.cfg.reloadTime;
    while (this.beatIdx < beats.length && f >= beats[this.beatIdx][0]) {
      this.onReloadBeat?.(beats[this.beatIdx][1]);
      this.beatIdx++;
    }
    if (this.reloadT >= this.cfg.reloadTime) {
      const need = this.cfg.magSize - this.mag;
      const take = Math.min(need, this.reserve);
      this.mag += take;
      this.reserve -= take;
      this.reloading = false;
      this.onReloadDone?.();
    }
  }

  /** Refill from an ammo pickup (same weapon picked up again). */
  addAmmo() {
    if (this.isEnergy) {
      this.mag = this.cfg.magSize;
      return;
    }
    this.reserve = Math.min(this.cfg.reserve * 1.5, this.reserve + Math.ceil(this.cfg.reserve * 0.6));
  }
}

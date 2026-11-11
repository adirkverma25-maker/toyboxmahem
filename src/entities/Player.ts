import * as THREE from 'three';
import { Actor, MoveIntent, emptyIntent } from './Actor';
import { Input } from '../core/Input';
import { settings } from '../core/Settings';
import { Viewmodel } from '../weapons/Viewmodel';
import { Combat } from '../combat/Combat';
import { AudioEngine } from '../audio/Audio';
import { Effects } from '../fx/Effects';
import { DEG, clamp, damp } from '../core/math';
import { AbilityId, MOVE } from '../weapons/weaponConfig';
import { Physics } from '../physics/Physics';
import { tryCloak, tryGrapple, tryJab, tryShield } from './abilities';

export interface PlayerDeps {
  input: Input;
  combat: Combat;
  audio: AudioEngine;
  fx: Effects;
  phys: Physics;
  nearbyPrompt: (a: Actor) => string | null;
  /** living teammates to watch while you're down (empty in free-for-all) */
  teammates: () => Actor[];
  /** enemies the controller aim assist may help with */
  aimTargets?: () => Actor[];
}

/** controller look speed at full stick, rad/s (about 200°/s) */
const PAD_TURN = 3.5;
/** vertical turns a bit slower than horizontal */
const PAD_PITCH_RATIO = 0.7;
const _eye = new THREE.Vector3();
const _tgt = new THREE.Vector3();

/** Converts horizontal FOV (what players expect in settings) to the vertical FOV three.js uses. */
export function hFovToV(hDeg: number, aspect: number) {
  return (2 * Math.atan(Math.tan((hDeg * DEG) / 2) / aspect)) / DEG;
}

export class Player {
  intent: MoveIntent = emptyIntent();
  recoilPitch = 0; // deg
  recoilYaw = 0; // deg
  private trauma = 0;
  private shakeT = Math.random() * 100;
  private landDip = { x: 0, v: 0 };
  private bob = 0;
  private bobAmt = 0;
  private fovKick = 0;
  private tilt = 0;
  private sprintAmt = 0;
  private autoReloadAt = 0;
  scopeKick = 0;
  /** crosshair spread in degrees (for the HUD) */
  spreadDeg = 0;
  deathPos = new THREE.Vector3();
  killer: Actor | null = null;
  private deathCamT = 0;
  interactPrompt: string | null = null;
  private wasAlive = true;
  private lastMouse = { dx: 0, dy: 0 };
  private wasDrawing = false;
  private prevAds = 0;
  /** teammate being watched while down */
  spectating: Actor | null = null;
  /** true while E is held (reviving) */
  reviveHeld = false;
  /** last ability that failed because it was cooling down (HUD flashes it) */
  denied: { key: string; at: number } = { key: '', at: -9 };

  constructor(public actor: Actor, public camera: THREE.PerspectiveCamera, public vm: Viewmodel, private deps: PlayerDeps) {}

  addTrauma(t: number) {
    this.trauma = Math.min(1, this.trauma + t);
  }

  equipCurrent(instant = false) {
    const ws = this.actor.weapon;
    if (!ws) return;
    this.vm.setWeapon(ws.id, instant);
    this.vm.scopeHidden = ws.overlay;
    this.vm.setOptic(ws.scope.style === 'reticle' ? ws.scope.id : null);
    ws.onReloadBeat = (part) => this.deps.audio.reloadPart(ws.id, part);
  }

  switchTo(slot: number, now: number) {
    const a = this.actor;
    if (slot === a.slot || !a.weapons[slot]) return;
    a.weapon?.cancelReload();
    a.slot = slot;
    a.weapon!.equip(now);
    this.equipCurrent();
    this.deps.audio.weaponSwitch();
  }

  /** Called when the player respawns. */
  onSpawn() {
    this.recoilPitch = this.recoilYaw = 0;
    this.trauma = 0;
    this.equipCurrent(false);
    this.wasAlive = true;
  }

  /**
   * Mouse + right-stick look. Also used on its own during the countdown.
   * The stick turns at a rate (rad/s) with a response curve, so small pushes give fine aim.
   */
  look(dt: number, assist = true) {
    const { input } = this.deps;
    const a = this.actor;
    const s = settings.data;
    const ws = a.weapon;
    const adsZoom = ws ? 1 + (ws.zoom - 1) * a.ads : 1;
    const adsScale = a.ads > 0.5 ? s.adsSensitivity / adsZoom : 1;
    const sens = s.sensitivity * 0.0022 * adsScale;
    const dx = input.mouseDX, dy = input.mouseDY * (s.invertY ? -1 : 1);
    this.lastMouse = { dx, dy };
    if (!a.alive) return;
    // right stick
    const curve = (v: number) => Math.sign(v) * Math.pow(Math.abs(v), 1.9);
    const rate = PAD_TURN * s.padSensitivity * adsScale;
    let padYaw = curve(input.lookX) * rate * dt;
    let padPitch = curve(input.lookY) * rate * PAD_PITCH_RATIO * dt * (s.invertY ? -1 : 1);
    if (assist && input.usingPad && s.padAimAssist) {
      const help = this.aimAssist(dt, Math.hypot(input.lookX, input.lookY) > 0.08 || Math.hypot(input.moveX, input.moveY) > 0.2);
      padYaw *= help;
      padPitch *= help;
    }
    a.yaw -= dx * sens + padYaw;
    let dp = -dy * sens - padPitch;
    // pulling down against recoil "absorbs" it so recovery never overshoots
    if (dp < 0 && this.recoilPitch > 0) {
      const absorb = Math.min(this.recoilPitch * DEG, -dp);
      this.recoilPitch -= absorb / DEG;
      dp += absorb;
    }
    a.pitch = clamp(a.pitch + dp, -1.5, 1.5);
  }

  /**
   * Controller aim assist against the closest visible enemy near the crosshair:
   * - returns a look-speed multiplier (slower while the crosshair is on or near them)
   * - pulls gently toward them while you're moving or steering ("rotational" assist)
   * - snaps part of the way when you start aiming down sights near one
   */
  private aimAssist(dt: number, steering: boolean): number {
    const a = this.actor;
    const targets = this.deps.aimTargets?.() ?? [];
    if (!targets.length) return 1;
    const eye = a.eyePos(_eye);
    const cp = Math.cos(a.pitch);
    let best: { yawErr: number; pitchErr: number; ang: number; radius: number } | null = null;
    for (const o of targets) {
      if (!o.alive || o.cloaked) continue;
      const c = o.chestPos(_tgt);
      const dx = c.x - eye.x, dy = c.y - eye.y, dz = c.z - eye.z;
      const dist = Math.hypot(dx, dy, dz);
      if (dist > 70 || dist < 0.5) continue;
      const ty = Math.atan2(-dx, -dz);
      const tp = Math.asin(clamp(dy / dist, -1, 1));
      let yawErr = ty - a.yaw;
      yawErr = Math.atan2(Math.sin(yawErr), Math.cos(yawErr));
      const pitchErr = tp - a.pitch;
      const ang = Math.hypot(yawErr * cp, pitchErr);
      // about a toy's width either side, never tiny at range, never huge up close
      const radius = clamp(Math.atan2(0.9, dist), 2.2 * DEG, 9 * DEG);
      if (ang > radius * 1.8) continue;
      if (best && ang / radius >= best.ang / best.radius) continue;
      if (!this.deps.phys.los(eye, c, true)) continue;
      best = { yawErr, pitchErr, ang, radius };
    }
    const adsStart = a.ads > 0 && this.prevAds === 0;
    this.prevAds = a.ads;
    if (!best) return 1;
    const near = 1 - clamp(best.ang / (best.radius * 1.8), 0, 1); // 1 on target, 0 at the edge
    if (adsStart && best.ang < best.radius * 1.6) {
      a.yaw += best.yawErr * 0.55;
      a.pitch = clamp(a.pitch + best.pitchErr * 0.55, -1.5, 1.5);
      return 1;
    }
    if (steering) {
      const pull = (a.ads > 0.5 ? 4.5 : 2.8) * near * dt;
      a.yaw += best.yawErr * Math.min(1, pull);
      a.pitch = clamp(a.pitch + best.pitchErr * Math.min(1, pull), -1.5, 1.5);
    }
    return 1 - near * (a.ads > 0.5 ? 0.55 : 0.4);
  }

  update(dt: number, now: number) {
    const { input, combat, audio } = this.deps;
    const a = this.actor;
    const s = settings.data;
    const reduced = s.reducedMotion;
    // ---------------- look
    const ws = a.weapon;
    this.look(dt);
    // ---------------- movement intent
    const it = this.intent;
    it.wish.set(0, 0, 0);
    if (a.alive) {
      // keys and the left stick add up; a half-pushed stick walks slower
      const f = clamp((input.act('forward') ? 1 : 0) - (input.act('back') ? 1 : 0) - input.moveY, -1, 1);
      const r = clamp((input.act('right') ? 1 : 0) - (input.act('left') ? 1 : 0) + input.moveX, -1, 1);
      const sy = Math.sin(a.yaw), cy = Math.cos(a.yaw);
      it.wish.set(-sy * f + cy * r, 0, -cy * f - sy * r);
      if (it.wish.lengthSq() > 1) it.wish.normalize();
    }
    it.crouchPressed = input.actPressed('crouch');
    it.crouch = input.act('crouch');
    it.sprint = input.act('sprint') || input.padSprint;
    it.jump = input.actPressed('jump');
    it.dash = false; // set below if dash is one of your two abilities and you pressed its button
    const adsHeld = input.act('aim') && a.alive && !(ws?.reloading && !ws.cfg.reloadPerShell);
    it.ads = adsHeld;
    if (ws) a.ads = clamp(a.ads + (adsHeld ? dt / ws.adsTime : -dt / (ws.adsTime * 0.8)), 0, 1);
    if (it.sprint && it.wish.lengthSq() > 0.01) a.ads = Math.max(0, a.ads - dt * 6);
    // aiming cancels the controller's sprint latch, like on most console shooters
    if (adsHeld) input.padSprint = false;

    // ---------------- weapons
    // reload, unless it shares a button with revive and a downed teammate is right here
    const reloadPressed = input.actPressed('reload') && !(this.interactPrompt && input.act('revive'));
    if (a.alive && ws) {
      if (input.actPressed('weapon1')) this.switchTo(0, now);
      if (input.actPressed('weapon2')) this.switchTo(1, now);
      if (input.wheel !== 0 || input.actPressed('swap')) this.switchTo(a.slot === 0 ? 1 : 0, now);
      const cw = a.weapon!;
      if (reloadPressed) {
        if (cw.isEnergy) cw.vent(now);
        else if (cw.startReload()) this.vm.cancelInspect();
      }
      if (input.actPressed('inspect')) this.vm.inspect();
      const infinite = a.hasBuff('infinite', now);
      const res = cw.pullTrigger(now, input.actPressed('fire'), input.act('fire'), infinite);
      if (cw.drawing && !this.wasDrawing) audio.bowDraw();
      this.wasDrawing = cw.drawing;
      if (res === -1 && input.actPressed('fire')) {
        audio.empty();
        if (cw.canStartReload()) cw.startReload();
      }
      const moving = clamp(a.speed / MOVE.walkSpeed, 0, 1.4);
      this.spreadDeg = cw.spread(a.ads, moving, !a.grounded);
      if (res > 0) {
        a.spawnProtectUntil = Math.min(a.spawnProtectUntil, now); // firing ends spawn protection
        for (let i = 0; i < res; i++) {
          const eye = a.eyePos();
          const dir = this.aimDir(new THREE.Vector3());
          const muzzle = this.vm.muzzleWorld(this.camera, new THREE.Vector3(), a.ads);
          const sp = cw.spread(a.ads, moving, !a.grounded);
          combat.fire(a, cw, eye, dir, muzzle, sp);
          const k = cw.kick(a.ads > 0.5);
          this.recoilPitch += k.pitch;
          this.recoilYaw += k.yaw;
          this.vm.onFire(cw.id, a.ads > 0.5, reduced);
          audio.gunshot(cw.id, eye, true);
          if (cw.id === 'thunderspring') window.setTimeout(() => audio.springWind(undefined, true), 280);
          this.addTrauma(cw.cfg.kick.shake * 0.6);
          input.rumble(0.25 + cw.cfg.kick.shake * 0.5, cw.cfg.kick.shake * 0.6, cw.cfg.auto ? 60 : 110);
          this.scopeKick = cw.overlay ? 1 : this.scopeKick;
          a.fireKick = 1;
        }
        if (cw.mag <= 0 && !cw.isEnergy && cw.reserve > 0) this.autoReloadAt = now + 0.3;
      }
      if (this.autoReloadAt > 0 && now >= this.autoReloadAt) {
        this.autoReloadAt = 0;
        if (a.weapon === cw && cw.mag <= 0) cw.startReload();
      }
      // recoil recovery (frame-rate independent, after a short delay)
      if (now - cw.lastShot > cw.cfg.recoveryDelay) {
        const rate = cw.cfg.recoveryRate * dt;
        this.recoilPitch = Math.max(0, this.recoilPitch - rate) + Math.min(0, this.recoilPitch + rate);
        if (this.recoilPitch < 0) this.recoilPitch = Math.min(0, this.recoilPitch + rate);
        const yr = rate * 0.8;
        this.recoilYaw = Math.abs(this.recoilYaw) <= yr ? 0 : this.recoilYaw - Math.sign(this.recoilYaw) * yr;
      }
    }
    // ---------------- abilities (Q dash is part of movement)
    if (a.alive) {
      const deps = { combat, phys: this.deps.phys, audio };
      const deny = (key: string) => (this.denied = { key, at: now });
      // your two equipped abilities, on the Ability 1 / Ability 2 buttons
      const use = (id: AbilityId) => {
        if (id === 'dash') {
          it.dash = true;
          if (now < a.dashReadyAt && !a.dashing) deny('dash');
        } else if (id === 'jab') {
          if (tryJab(a, now, deps)) {
            this.vm.punch();
            this.addTrauma(0.12);
          } else deny('jab');
        } else if (id === 'grapple') {
          const r = tryGrapple(a, this.aimDir(new THREE.Vector3()), now, deps);
          if (r === false) deny('grapple');
          else if (r !== 'miss') this.addTrauma(0.1);
        } else if (id === 'cloak') {
          if (!tryCloak(a, now, deps)) deny('cloak');
        } else if (!tryShield(a, now, deps)) deny('shield');
      };
      if (input.actPressed('ability1') && a.abilities[0]) use(a.abilities[0]);
      if (input.actPressed('ability2') && a.abilities[1]) use(a.abilities[1]);
    }
    this.reviveHeld = a.alive && input.act('revive');
    this.interactPrompt = a.alive ? this.deps.nearbyPrompt(a) : null;
    // ---------------- spectating teammates while down
    if (a.alive) this.spectating = null;
    else {
      const mates = this.deps.teammates();
      if (this.spectating && !mates.includes(this.spectating)) this.spectating = null;
      if (mates.length && this.deathCamT > 1.3) {
        const i = this.spectating ? mates.indexOf(this.spectating) : -1;
        if (!this.spectating) this.spectating = mates[0];
        else if (input.actPressed('fire') || input.actPressed('jump')) this.spectating = mates[(i + 1) % mates.length];
        else if (input.actPressed('aim')) this.spectating = mates[(i - 1 + mates.length) % mates.length];
      }
      if (!mates.length) this.spectating = null;
    }
    this.scopeKick = Math.max(0, this.scopeKick - dt * 1.8);
  }

  /** View direction including recoil. */
  aimDir(out: THREE.Vector3) {
    const a = this.actor;
    const p = a.pitch + this.recoilPitch * DEG;
    const y = a.yaw - this.recoilYaw * DEG;
    return out.set(-Math.sin(y) * Math.cos(p), Math.sin(p), -Math.cos(y) * Math.cos(p)).normalize();
  }

  onLand(strength: number) {
    this.landDip.v -= strength * 2.2;
    this.vm.onLand(strength);
  }
  onDamaged(amount: number) {
    this.addTrauma(Math.min(0.35, amount / 120));
    this.deps.input.rumble(0.3, Math.min(1, 0.2 + amount / 60), 140);
  }
  onDeath(killer: Actor | null) {
    this.killer = killer;
    this.deathPos.copy(this.actor.pos);
    this.deathCamT = 0;
    this.wasAlive = false;
    this.spectating = null;
  }

  /** Apply camera transform (after movement). */
  updateCamera(dt: number, now: number) {
    const a = this.actor;
    const s = settings.data;
    const cam = this.camera;
    const reduced = s.reducedMotion;
    const shakeOn = s.cameraShake ? (reduced ? 0.3 : 1) : 0;
    const ws = a.weapon;
    // vertical FOV from horizontal setting, plus ADS zoom and a little sprint kick
    const sprinting = a.alive && this.intent.sprint && a.speed > MOVE.walkSpeed * 1.1 && !a.crouching;
    this.sprintAmt = damp(this.sprintAmt, sprinting ? 1 : 0, 8, dt);
    this.fovKick = damp(this.fovKick, (sprinting && !reduced ? 4 : 0) + (a.dashing && !reduced ? 8 : 0), 8, dt);
    const zoom = ws && a.alive ? 1 + (ws.zoom - 1) * a.ads : 1;
    const baseV = hFovToV(s.fov + this.fovKick, cam.aspect);
    const v = (2 * Math.atan(Math.tan((baseV * DEG) / 2) / zoom)) / DEG;
    if (Math.abs(cam.fov - v) > 0.01) {
      cam.fov = v;
      cam.updateProjectionMatrix();
    }
    if (!a.alive) {
      // death cam: rise above the pieces and look at whoever got you
      this.deathCamT += dt;
      const sp = this.spectating;
      if (sp && sp.alive) {
        // chase cam behind the teammate, pulled in if a wall is in the way
        const eye = sp.eyePos();
        const f = sp.forward(new THREE.Vector3());
        const back = f.clone().multiplyScalar(-1).setY(-f.y * 0.5 + 0.22).normalize();
        const room = this.deps.phys.rayDist(eye, back, 3.8, true);
        const want = eye.clone().addScaledVector(back, Math.max(0.6, Math.min(3.6, room - 0.3)));
        cam.position.lerp(want, 1 - Math.exp(-10 * dt));
        const m = new THREE.Matrix4().lookAt(cam.position, eye.clone().addScaledVector(f, 6), new THREE.Vector3(0, 1, 0));
        cam.quaternion.slerp(new THREE.Quaternion().setFromRotationMatrix(m), 1 - Math.exp(-12 * dt));
        cam.updateMatrixWorld();
        return;
      }
      const t = Math.min(1, this.deathCamT / 0.8);
      const target = this.killer && this.killer.alive ? this.killer.chestPos() : this.deathPos.clone().setY(this.deathPos.y + 0.5);
      const back = new THREE.Vector3(Math.sin(a.yaw), 0, Math.cos(a.yaw)).multiplyScalar(3);
      const want = this.deathPos.clone().add(back).setY(this.deathPos.y + 2.8 + t * 0.5);
      cam.position.lerp(want, 1 - Math.exp(-4 * dt));
      const m = new THREE.Matrix4().lookAt(cam.position, target, new THREE.Vector3(0, 1, 0));
      const q = new THREE.Quaternion().setFromRotationMatrix(m);
      cam.quaternion.slerp(q, 1 - Math.exp(-5 * dt));
      return;
    }
    // landing spring
    const n = Math.max(1, Math.ceil(dt * 240));
    for (let i = 0; i < n; i++) {
      const h = dt / n;
      this.landDip.v += (-120 * this.landDip.x - 14 * this.landDip.v) * h;
      this.landDip.x += this.landDip.v * h;
    }
    // head bob
    const moving = a.grounded && !a.sliding ? clamp(a.speed / 7, 0, 1.2) : 0;
    this.bobAmt = damp(this.bobAmt, moving * (1 - a.ads * 0.8), 8, dt);
    this.bob += dt * (6 + a.speed * 1.1);
    const bobK = reduced ? 0.25 : 1;
    const bobY = Math.sin(this.bob * 2) * 0.025 * this.bobAmt * bobK;
    const bobRoll = Math.sin(this.bob) * 0.004 * this.bobAmt * bobK;
    this.tilt = damp(this.tilt, (a.sliding ? 0.07 : 0) * (reduced ? 0.3 : 1), 10, dt);
    // shake (trauma^2, smooth noise)
    this.trauma = Math.max(0, this.trauma - dt * 1.6);
    this.shakeT += dt * 22;
    const sh = this.trauma * this.trauma * shakeOn;
    const nx = (Math.sin(this.shakeT * 1.13) + Math.sin(this.shakeT * 2.71 + 1.3) * 0.5) * sh * 1.2 * DEG;
    const ny = (Math.sin(this.shakeT * 1.37 + 2.1) + Math.sin(this.shakeT * 3.11) * 0.5) * sh * 1.2 * DEG;
    const nr = Math.sin(this.shakeT * 0.93 + 4) * sh * 1.5 * DEG;

    const eye = a.eyePos();
    cam.position.set(eye.x, eye.y + bobY + this.landDip.x * 0.06 * (reduced ? 0.4 : 1), eye.z);
    const pitch = a.pitch + this.recoilPitch * DEG + ny;
    const yaw = a.yaw - this.recoilYaw * DEG + nx;
    cam.rotation.set(pitch, yaw, bobRoll + this.tilt + nr, 'YXZ');
    cam.updateMatrixWorld();
    void now;
  }

  updateViewmodel(dt: number, now: number) {
    const a = this.actor;
    this.vm.root.visible = a.alive;
    if (!a.alive) return;
    this.vm.update(dt, {
      ws: a.weapon,
      ads: a.ads,
      sprint: this.sprintAmt,
      speed: a.speed,
      grounded: a.grounded,
      crouch: a.crouchT,
      mouseDX: this.lastMouse.dx,
      mouseDY: this.lastMouse.dy,
      now,
      reducedMotion: settings.data.reducedMotion,
      infinite: a.hasBuff('infinite', now),
      sliding: a.sliding,
      charge: a.weapon?.chargeAt(now) ?? 0,
      cloaked: a.cloaked,
    });
  }
}

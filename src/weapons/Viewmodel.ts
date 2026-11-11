import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { buildWeaponModel, updateAmmoIndicator, WeaponModel, aimString, buildOptic } from './WeaponModels';
import { WeaponId, WEAPONS } from './weaponConfig';
import { WeaponState } from './WeaponState';
import { plastic, metal } from '../render/materials';
import { clamp, damp, smoothstep, rand } from '../core/math';

interface Spring {
  x: number;
  v: number;
}
const springStep = (s: Spring, k: number, c: number, dt: number) => {
  // semi-implicit damped spring, sub-stepped for frame-rate independence
  const n = Math.max(1, Math.ceil(dt / (1 / 240)));
  const h = dt / n;
  for (let i = 0; i < n; i++) {
    s.v += (-k * s.x - c * s.v) * h;
    s.x += s.v * h;
  }
};

function starTexture() {
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const ctx = c.getContext('2d')!;
  ctx.translate(64, 64);
  const g = ctx.createRadialGradient(0, 0, 0, 0, 0, 60);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.3, 'rgba(255,240,200,0.9)');
  g.addColorStop(1, 'rgba(255,200,120,0)');
  ctx.fillStyle = g;
  ctx.beginPath();
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2;
    const r = i % 2 ? 22 : 62;
    ctx.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  ctx.fill();
  const t = new THREE.CanvasTexture(c);
  return t;
}

export interface VmContext {
  ws: WeaponState | null;
  ads: number;
  sprint: number;
  speed: number;
  grounded: boolean;
  crouch: number;
  mouseDX: number;
  mouseDY: number;
  now: number;
  reducedMotion: boolean;
  infinite: boolean;
  sliding: boolean;
  /** bow draw 0..1 */
  charge: number;
  cloaked: boolean;
}

/** First-person toy hands + weapon, rendered in its own scene so it never clips into walls. */
export class Viewmodel {
  root = new THREE.Group();
  private holder = new THREE.Group();
  private models = new Map<WeaponId, WeaponModel>();
  current: WeaponModel | null = null;
  currentId: WeaponId | null = null;
  private handR: THREE.Group;
  private handL: THREE.Group;
  private flash: THREE.Mesh;
  private flashT = 0;
  private equipT = 1;
  private kickZ: Spring = { x: 0, v: 0 };
  private kickRot: Spring = { x: 0, v: 0 };
  private kickRoll: Spring = { x: 0, v: 0 };
  private land: Spring = { x: 0, v: 0 };
  private swayX = 0;
  private swayY = 0;
  private bobPhase = 0;
  private bobAmt = 0;
  private sprintT = 0;
  private inspectT = 0;
  private fireAnim = 0;
  private spinSpeed = 0;
  private boltT = 0;
  private reloadVis = 0;
  private time = 0;
  private jackT = 0;
  private glove = new THREE.Group();
  private gloveSpring = new THREE.Group();
  private punchT = 0;
  private cloakMat = new THREE.MeshPhysicalMaterial({ color: '#d8ecff', transparent: true, opacity: 0.22, roughness: 0.05, metalness: 0.2, clearcoat: 1, depthWrite: false, emissive: '#5fb3ff', emissiveIntensity: 0.25 });
  private cloakOn = false;
  scopeHidden = false;

  constructor(private scene: THREE.Scene, toyColor = '#1fb5ad', cuffColor = '#ff8c1a') {
    scene.add(this.root);
    this.root.add(this.holder);
    this.handR = this.makeHand(toyColor, cuffColor, 1);
    this.handL = this.makeHand(toyColor, cuffColor, -1);
    const fm = new THREE.MeshBasicMaterial({ map: starTexture(), transparent: true, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, color: '#ffd9a0' });
    this.flash = new THREE.Mesh(new THREE.PlaneGeometry(0.32, 0.32), fm);
    this.flash.visible = false;
    this.flash.renderOrder = 10;
    // Spring Punch: boxing glove on a spring that pops out from the lower right
    const red = plastic('#e63946', { rough: 0.3 });
    const g = new THREE.Group();
    g.add(new THREE.Mesh(new RoundedBoxGeometry(0.12, 0.11, 0.13, 3, 0.05), red));
    const thumb = new THREE.Mesh(new THREE.CapsuleGeometry(0.03, 0.05, 4, 8), red);
    thumb.position.set(-0.06, 0.0, -0.01);
    thumb.rotation.x = Math.PI / 2;
    g.add(thumb);
    const cuff = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.05, 14), plastic('#ffffff', { rough: 0.4 }));
    cuff.rotation.x = Math.PI / 2;
    cuff.position.z = 0.08;
    g.add(cuff);
    this.glove.add(g);
    const pts: THREE.Vector3[] = [];
    for (let i = 0; i <= 96; i++) {
      const a = (i / 96) * 8 * Math.PI * 2;
      pts.push(new THREE.Vector3(Math.cos(a) * 0.03, Math.sin(a) * 0.03, i / 96));
    }
    this.gloveSpring.add(new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 96, 0.006, 5, false), metal('#d6dbe3', 0.2)));
    this.glove.add(this.gloveSpring);
    this.glove.visible = false;
    this.root.add(this.glove);
  }

  /** Spring Punch animation. */
  punch() {
    this.punchT = 0.32;
    this.inspectT = 0;
  }

  private makeHand(color: string, cuff: string, side: 1 | -1) {
    const g = new THREE.Group();
    const skin = plastic(color, { rough: 0.35 });
    const cuffMat = plastic(cuff, { rough: 0.35 });
    const glove = plastic('#fff4e6', { rough: 0.45 });
    // mitten-style toy hand wrapped around the grip
    const palm = new THREE.Mesh(new RoundedBoxGeometry(0.085, 0.1, 0.075, 3, 0.035), glove);
    palm.position.set(side * 0.012, -0.01, 0);
    g.add(palm);
    const fingers = new THREE.Mesh(new THREE.CapsuleGeometry(0.03, 0.05, 4, 10), glove);
    fingers.rotation.z = Math.PI / 2;
    fingers.position.set(-side * 0.025, -0.02, -0.035);
    g.add(fingers);
    const thumb = new THREE.Mesh(new THREE.CapsuleGeometry(0.018, 0.04, 4, 8), glove);
    thumb.rotation.set(0.6, 0, side * 0.4);
    thumb.position.set(side * 0.045, 0.03, -0.02);
    g.add(thumb);
    const cuffM = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.052, 0.04, 16), cuffMat);
    cuffM.rotation.x = Math.PI / 2 - 0.5;
    cuffM.position.set(side * 0.01, -0.05, 0.06);
    g.add(cuffM);
    const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.045, 0.42, 4, 12), skin);
    arm.rotation.x = Math.PI / 2 - 0.55;
    arm.rotation.z = side * -0.25;
    arm.position.set(side * 0.06, -0.15, 0.25);
    g.add(arm);
    // seam line + joint dot on the toy arm
    const joint = new THREE.Mesh(new THREE.SphereGeometry(0.02, 10, 8), cuffMat);
    joint.position.set(side * 0.05, -0.07, 0.11);
    g.add(joint);
    return g;
  }

  private getModel(id: WeaponId) {
    let m = this.models.get(id);
    if (!m) {
      m = buildWeaponModel(id);
      this.models.set(id, m);
    }
    return m;
  }

  private optic: THREE.Group | null = null;
  /** Mount (or remove) the small on-gun optic for the current weapon. */
  setOptic(kind: 'dot' | 'ring' | string | null) {
    if (this.optic) {
      this.optic.parent?.remove(this.optic);
      this.optic = null;
    }
    if (!this.current || !this.currentId || (kind !== 'dot' && kind !== 'ring')) return;
    const c = WEAPONS[this.currentId].colors;
    this.optic = buildOptic(kind, -this.current.userData.adsOffset.y, c.accent, c.main);
    this.optic.position.z = this.current.userData.adsOffset.z * 0.5 - 0.02;
    this.current.add(this.optic);
    this.cloakOn = false; // re-apply the ghost look to the new part if cloaked
  }

  setWeapon(id: WeaponId | null, instant = false) {
    if (this.optic) {
      this.optic.parent?.remove(this.optic);
      this.optic = null;
    }
    if (this.current && this.cloakOn) {
      // give the outgoing gun its real materials back; the cloak re-applies next frame
      this.current.traverse((o) => {
        const mm = o as THREE.Mesh;
        if (mm.isMesh && mm.userData.preCloak) {
          mm.material = mm.userData.preCloak;
          delete mm.userData.preCloak;
        }
      });
      this.cloakOn = false;
    }
    if (this.current) this.holder.remove(this.current);
    this.current = null;
    this.currentId = id;
    if (!id) return;
    const m = this.getModel(id);
    this.current = m;
    this.holder.add(m);
    m.add(this.handR, this.handL, this.flash);
    this.handR.position.copy(m.userData.rightGrip);
    this.handL.position.copy(m.userData.leftGrip);
    this.handR.rotation.set(0.25, 0, 0);
    this.handL.rotation.set(0, 0, 0);
    this.flash.position.copy(m.userData.muzzle.position);
    this.equipT = instant ? 1 : 0;
    this.inspectT = 0;
    this.resetParts();
  }

  private resetParts() {
    if (!this.current) return;
    for (const [k, o] of Object.entries(this.current.userData.parts)) {
      const r = this.current.userData.rest[k];
      if (!r) continue;
      o.position.copy(r.p);
      o.rotation.copy(r.r);
      o.scale.copy(r.s);
    }
  }

  inspect() {
    if (this.equipT >= 1 && this.reloadVis === 0) this.inspectT = 2.4;
  }
  cancelInspect() {
    this.inspectT = 0;
  }

  onFire(id: WeaponId, ads: boolean, reduced: boolean) {
    const cfg = WEAPONS[id];
    const k = ads ? 0.55 : 1;
    const mot = reduced ? 0.5 : 1;
    this.kickZ.v += cfg.kick.back * 28 * k * mot;
    this.kickRot.v += cfg.kick.up * 32 * k * mot;
    this.kickRoll.v += rand(-1, 1) * cfg.kick.roll * 30 * mot;
    this.flashT = 0.045;
    this.flash.visible = true;
    this.flash.rotation.z = Math.random() * Math.PI;
    const s = rand(0.8, 1.25) * (id === 'crayonCannon' || id === 'bubbleBlaster' ? 1.6 : id === 'rapidRascal' ? 0.8 : 1);
    this.flash.scale.setScalar(s);
    (this.flash.material as THREE.MeshBasicMaterial).color.set(cfg.colors.glow);
    this.fireAnim = 1;
    this.inspectT = 0;
    const p = this.current?.userData.parts;
    if (!p) return;
    if (p.gear) p.gear.rotation.x -= 0.9;
    if (p.gear2) p.gear2.rotation.x += 1.3;
    if (p.chamber && id === 'foamFury') p.chamber.rotation.z += Math.PI / 3;
    if (p.wheel) p.wheel.rotation.x += (Math.PI * 2) / 5;
    if (id === 'thunderspring') this.boltT = 1;
    if (id === 'jackBlaster') this.jackT = 1;
  }

  onLand(strength: number) {
    this.land.v -= strength * 1.6;
  }

  update(dt: number, c: VmContext) {
    this.time += dt;
    const m = this.current;
    if (!m) return;
    const ws = c.ws;
    const parts = m.userData.parts;
    const rm = c.reducedMotion ? 0.35 : 1;
    this.equipT = Math.min(1, this.equipT + dt / 0.32);
    this.sprintT = damp(this.sprintT, c.sprint, 10, dt);
    springStep(this.kickZ, 260, 22, dt);
    springStep(this.kickRot, 240, 20, dt);
    springStep(this.kickRoll, 200, 18, dt);
    springStep(this.land, 120, 14, dt);
    // mouse sway (weapon lags behind the view)
    this.swayX = damp(this.swayX, clamp(-c.mouseDX * 0.0009, -0.06, 0.06) * rm, 10, dt);
    this.swayY = damp(this.swayY, clamp(c.mouseDY * 0.0009, -0.05, 0.05) * rm, 10, dt);
    // walk bob
    const moving = c.grounded && !c.sliding ? clamp(c.speed / 7, 0, 1.2) : 0;
    this.bobAmt = damp(this.bobAmt, moving, 8, dt);
    this.bobPhase += dt * (6 + c.speed * 1.1);
    const bobScale = (1 - c.ads * 0.85) * rm;
    const bx = Math.sin(this.bobPhase) * 0.014 * this.bobAmt * bobScale;
    const by = -Math.abs(Math.cos(this.bobPhase)) * 0.012 * this.bobAmt * bobScale;
    const breathe = Math.sin(this.time * 1.6) * 0.003 * (1 - c.ads);

    // hip / ads / sprint poses
    const hip = new THREE.Vector3(0.15, -0.125, -0.34);
    const ao = m.userData.adsOffset;
    const adsP = new THREE.Vector3(0, ao.y * 0.5, -0.26 + ao.z * 0.5);
    const pos = hip.clone().lerp(adsP, smoothstep(0, 1, c.ads));
    let rx = 0, ry = 0, rz = 0;
    // sprint
    pos.x += this.sprintT * -0.04;
    pos.y += this.sprintT * -0.05;
    rx += this.sprintT * -0.35;
    ry += this.sprintT * 0.75;
    rz += this.sprintT * 0.2;
    // crouch/slide tilt
    rz += c.sliding ? 0.25 : 0;
    // equip raise
    const e = 1 - smoothstep(0, 1, this.equipT);
    pos.y -= e * 0.3;
    rx -= e * 0.9;
    // inspect: show off the left side, then flip
    if (this.inspectT > 0) {
      this.inspectT -= dt;
      const t = 1 - this.inspectT / 2.4;
      const k = smoothstep(0, 0.2, t) * (1 - smoothstep(0.8, 1, t));
      const flip = smoothstep(0.4, 0.6, t);
      ry += k * (-0.9 + flip * 1.6);
      rz += k * 0.35;
      rx += k * 0.2;
      pos.x -= k * 0.08;
      pos.z += k * 0.06;
    }
    // reload pose
    let rf = 0;
    if (ws && ws.reloading) rf = ws.cfg.reloadPerShell ? 0.5 : ws.reloadProgress;
    const reloadOn = ws?.reloading ? 1 : 0;
    this.reloadVis = damp(this.reloadVis, reloadOn, 10, dt);
    const rv = this.reloadVis;
    if (rv > 0.001) {
      const id = this.currentId!;
      const tilt = id === 'crayonCannon' ? [0.5, -0.2, 0.2] : id === 'bubbleBlaster' ? [0.15, 0.3, -0.7] : id === 'thunderspring' ? [0.2, 0.25, 0.5] : [0.2, -0.1, 0.55];
      rx += tilt[0] * rv;
      ry += tilt[1] * rv;
      rz += tilt[2] * rv;
      pos.y += 0.02 * rv;
      pos.x -= 0.04 * rv;
    }
    // fire animation of moving parts
    this.fireAnim = Math.max(0, this.fireAnim - dt * 8);
    this.animateParts(dt, c, rf, rv);

    const kz = this.kickZ.x * rm;
    const kr = this.kickRot.x * rm;
    this.holder.position.set(pos.x + bx + this.swayX, pos.y + by + breathe + this.swayY + this.land.x * 0.04 * rm, pos.z + kz);
    this.holder.rotation.set(rx + kr + this.swayY * 2, ry + this.swayX * 2.5, rz + this.kickRoll.x * rm + this.swayX * 1.5);
    this.holder.scale.setScalar(0.43);
    this.holder.visible = !(this.scopeHidden && c.ads > 0.9);
    // spring punch glove
    if (this.punchT > 0) {
      this.punchT = Math.max(0, this.punchT - dt);
      const t = 1 - this.punchT / 0.32;
      const out = t < 0.3 ? smoothstep(0, 0.3, t) : 1 - smoothstep(0.45, 1, t);
      this.glove.visible = true;
      const base = new THREE.Vector3(0.1, -0.2, -0.05);
      const reach = 0.25 + out * 0.32;
      this.glove.position.set(base.x - out * 0.06, base.y + out * 0.1, base.z - reach);
      this.gloveSpring.scale.set(1, 1, reach);
      this.gloveSpring.position.set(0, 0, 0.06);
      this.glove.rotation.set(0.1, 0.15, 0);
      // the gun dips out of the way
      this.holder.position.y -= out * 0.06;
      this.holder.rotation.z -= out * 0.2;
    } else this.glove.visible = false;
    // bow: limbs, string and arrow follow the draw
    if (this.currentId === 'plungerBow') {
      const draw = smoothstep(0, 1, c.charge);
      aimString(m, draw);
      if (parts.arrow && ws) parts.arrow.visible = ws.mag > 0 && (ws.drawing || c.now >= ws.nextFire - 0.25);
      this.handR.position.set(0, -0.01, (parts.nock?.position.z ?? 0.15) + 0.03);
      this.handR.rotation.set(0.25, 0, 0);
      this.holder.position.z += draw * 0.03;
      this.holder.position.y += draw * 0.02;
      if (draw > 0.98) this.holder.position.x += Math.sin(this.time * 31) * 0.0012; // straining at full draw
    }
    // cloak: ghostly see-through arms and gun
    if (c.cloaked !== this.cloakOn) {
      this.cloakOn = c.cloaked;
      this.root.traverse((o) => {
        const mm = o as THREE.Mesh;
        if (!mm.isMesh || o === this.flash) return;
        if (c.cloaked) {
          if (!mm.userData.preCloak) mm.userData.preCloak = mm.material;
          mm.material = this.cloakMat;
        } else if (mm.userData.preCloak) {
          mm.material = mm.userData.preCloak;
          delete mm.userData.preCloak;
        }
      });
    }
    if (this.cloakOn) this.cloakMat.opacity = 0.18 + Math.sin(this.time * 6) * 0.05;
    // muzzle flash
    if (this.flashT > 0) {
      this.flashT -= dt;
      if (this.flashT <= 0) this.flash.visible = false;
    }
    // left hand follows the magazine during reloads
    const lg = m.userData.leftGrip;
    const mag = parts.mag;
    if (rv > 0.01 && mag) {
      const target = mag.position.clone().add(new THREE.Vector3(-0.02, -0.04, 0.02));
      this.handL.position.lerpVectors(lg, target, rv);
      this.handL.rotation.set(-0.4 * rv, 0, -0.3 * rv);
    } else {
      this.handL.position.copy(lg);
      this.handL.rotation.set(0, 0, 0);
    }
    // ammo indicators
    if (ws) updateAmmoIndicator(m, ws.mag / ws.cfg.magSize, ws.mag);
  }

  private animateParts(dt: number, c: VmContext, rf: number, rv: number) {
    const m = this.current!;
    const p = m.userData.parts;
    const rest = m.userData.rest;
    const ws = c.ws;
    const id = this.currentId!;
    const firing = ws ? c.now - ws.lastShot < 0.12 : false;
    // continuous animations
    if (p.gear && id !== 'plasti9') p.gear.rotation.x += dt * (firing ? 18 : 0.4);
    if (p.spin) {
      this.spinSpeed = damp(this.spinSpeed, firing ? 40 : 0, firing ? 8 : 2, dt);
      p.spin.rotation.z += this.spinSpeed * dt;
    }
    if (p.rings) {
      this.spinSpeed = damp(this.spinSpeed, firing ? 25 : 2, 4, dt);
      p.rings.children.forEach((r, i) => (r.rotation.z += this.spinSpeed * dt * (i % 2 ? -1 : 1)));
    }
    if (p.chamber && id === 'bubbleBlaster') {
      p.chamber.rotation.y += dt * (firing ? 9 : 1.5);
      p.chamber.rotation.x += dt * 0.7;
    }
    if (p.needle) p.needle.rotation.x = -0.6 + (ws ? ws.mag / ws.cfg.magSize : 1) * 1.2 + Math.sin(this.time * 30) * 0.03 * this.fireAnim;
    if (p.leds) p.leds.children.forEach((l, i) => ((l as THREE.Mesh).visible = firing ? Math.sin(this.time * 40 + i * 2) > 0 : Math.sin(this.time * 3 + i) > -0.3));
    if (p.arcs) {
      const on = firing || (ws && ws.mag < ws.cfg.magSize);
      p.arcs.visible = !!on && Math.random() > 0.3;
      p.arcs.rotation.z = Math.random() * Math.PI;
    }
    if (p.core && ws) {
      const mat = (p.core as THREE.Mesh).material as THREE.MeshStandardMaterial;
      const charging = ws.mag < ws.cfg.magSize && c.now - ws.lastShot > (ws.cfg.energy?.rechargeDelay ?? 99);
      const frac = ws.mag / ws.cfg.magSize;
      mat.emissiveIntensity = damp(mat.emissiveIntensity, (charging ? 4.5 + Math.sin(this.time * 14) * 1.2 : 1 + frac * 2.5) * (ws.lockout ? 0.4 : 1), 10, dt);
      (p.core as THREE.Mesh).scale.setScalar(0.85 + frac * 0.15);
    }
    if (p.pistons && rest.pistons) p.pistons.position.z = rest.pistons.p.z + this.fireAnim * 0.04;
    if (p.shroud) p.shroud.rotation.z += dt * (firing ? 12 : 0);
    if (p.charge && rest.charge && id === 'plasti9') p.charge.position.z = rest.charge.p.z + this.fireAnim * 0.05;
    if (p.spring && id === 'thunderspring') {
      // fire: spring twangs; reload: compress then lock
      this.boltT = Math.max(0, this.boltT - dt * 1.8);
      const twang = this.boltT > 0 ? Math.sin(this.boltT * 30) * this.boltT * 0.25 : 0;
      let comp = 1;
      if (rv > 0.01) comp = 1 - 0.45 * smoothstep(0.45, 0.62, rf) * (1 - smoothstep(0.92, 1, rf));
      p.spring.scale.z = comp + twang;
      if (p.bolt && rest.bolt) p.bolt.position.z = rest.bolt.p.z + (this.boltT > 0.4 ? (1 - this.boltT) * 0.08 : this.boltT * 0.12) + smoothstep(0.55, 0.7, rf) * 0.08 * rv * (1 - smoothstep(0.85, 1, rf));
    }
    // reload choreography for magazines
    if (p.mag && rest.mag) {
      const r = rest.mag;
      let off = 0, outX = 0;
      if (rv > 0.01) {
        if (id === 'bubbleBlaster') {
          // shells pushed in one at a time
          off = Math.abs(Math.sin(c.now * Math.PI / 0.55)) * 0.03;
        } else if (id === 'crayonCannon') {
          const out = smoothstep(0.15, 0.35, rf) * (1 - smoothstep(0.4, 0.6, rf));
          p.mag.position.set(r.p.x, r.p.y, r.p.z - out * 0.35);
          p.mag.visible = !(rf > 0.33 && rf < 0.42);
        } else {
          const out = smoothstep(0.1, 0.32, rf) * (1 - smoothstep(0.42, 0.6, rf));
          off = -out * 0.28;
          outX = out * -0.05;
          p.mag.visible = !(rf > 0.3 && rf < 0.44);
        }
      } else p.mag.visible = true;
      if (id !== 'crayonCannon') p.mag.position.set(r.p.x + outX, r.p.y + off, r.p.z + (id === 'bubbleBlaster' ? -off : 0));
    }
    if (p.charge && rest.charge && id !== 'plasti9') {
      const pull = rv > 0.01 ? smoothstep(0.72, 0.8, rf) * (1 - smoothstep(0.84, 0.9, rf)) : 0;
      p.charge.position.z = rest.charge.p.z + pull * 0.07;
    }
    if (p.pump && rest.pump) {
      p.pump.position.z = rest.pump.p.z + (this.fireAnim > 0.2 ? (1 - this.fireAnim) * 0.08 : this.fireAnim * 0.3);
    }
    if (p.crank) p.crank.rotation.x -= dt * (this.fireAnim * 26 + (rv > 0.01 ? 9 : 0));
    if (p.jack) {
      this.jackT = Math.max(0, this.jackT - dt * 2.2);
      const boing = Math.sin(this.jackT * 26) * this.jackT * 0.35;
      p.jack.scale.y = 1 + boing + (rv > 0.01 ? -0.35 * rv : 0);
    }
    if (p.needle && id === 'crayonCannon') p.needle.rotation.x = 0;
    if (p.needle2 && p.needle && id === 'crayonCannon') {
      const pres = ws ? ws.mag / ws.cfg.magSize : 1;
      p.needle.rotation.y = -1 + pres * 2 + Math.sin(this.time * 20) * 0.04 * this.fireAnim;
      p.needle2.rotation.y = -0.6 + Math.sin(this.time * 2) * 0.2;
    }
  }

  /** World-space approx of the muzzle for tracers (viewmodel lives in its own scene). */
  muzzleWorld(camera: THREE.Camera, out: THREE.Vector3, ads: number) {
    const local = new THREE.Vector3(0.18 * (1 - ads), -0.13 * (1 - ads) - 0.04 * ads, -0.75);
    return out.copy(local).applyMatrix4(camera.matrixWorld);
  }

  dispose() {
    this.scene.remove(this.root);
  }
}

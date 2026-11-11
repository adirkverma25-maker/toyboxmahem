import * as THREE from 'three';
import { Actor } from '../entities/Actor';
import { Effects } from '../fx/Effects';
import { AudioEngine } from '../audio/Audio';
import { Emitter } from '../core/events';
import type { GameEvents } from '../combat/Combat';
import { COMBAT, PICKUPS, WEAPONS, WeaponId } from '../weapons/weaponConfig';
import { buildWeaponModel } from '../weapons/WeaponModels';
import { flattenByMaterial } from '../render/merge';
import { plastic, glow, metal } from '../render/materials';
import { softDotTexture } from '../render/textures';
import { WeaponState } from '../weapons/WeaponState';

export type PickupKind = 'health' | 'shield' | 'turbo' | 'infinite' | 'power';

export const PICKUP_INFO: Record<PickupKind, { label: string; color: string; icon: string }> = {
  health: { label: 'Health Battery +35', color: '#4ade80', icon: '🔋' },
  shield: { label: 'Bubble Shield +50', color: '#5ac8fa', icon: '🫧' },
  turbo: { label: 'Turbo Wheels', color: '#ff9f1c', icon: '🛞' },
  infinite: { label: 'Infinite Springs', color: '#f2c94c', icon: '♾️' },
  power: { label: 'Power Star', color: '#ffe14d', icon: '⭐' },
};

interface Item {
  kind: PickupKind | 'weapon';
  weapon?: WeaponId;
  pos: THREE.Vector3;
  group: THREE.Group;
  spinner: THREE.Group;
  halo: THREE.Sprite;
  ring: THREE.Mesh;
  available: boolean;
  respawnAt: number;
  phase: number;
  color: string;
}

function starShape(outer: number, inner: number) {
  const s = new THREE.Shape();
  for (let i = 0; i < 10; i++) {
    const a = (i / 10) * Math.PI * 2 + Math.PI / 2;
    const r = i % 2 ? inner : outer;
    const x = Math.cos(a) * r, y = Math.sin(a) * r;
    if (i === 0) s.moveTo(x, y);
    else s.lineTo(x, y);
  }
  s.closePath();
  return s;
}

function buildPickupModel(kind: PickupKind): THREE.Group {
  const g = new THREE.Group();
  switch (kind) {
    case 'health': {
      g.add(new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.26, 0.8, 24), plastic('#22c55e', { rough: 0.25, clearcoat: 1 })));
      const band = new THREE.Mesh(new THREE.CylinderGeometry(0.265, 0.265, 0.25, 24), plastic('#111827', { rough: 0.3 }));
      band.position.y = -0.2;
      g.add(band);
      const cap = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.1, 16), metal('#d4d4d8', 0.2));
      cap.position.y = 0.45;
      g.add(cap);
      const plus1 = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.05, 0.05), glow('#ffffff', 1.5));
      plus1.position.set(0, 0.12, 0.27);
      const plus2 = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.2, 0.05), glow('#ffffff', 1.5));
      plus2.position.set(0, 0.12, 0.27);
      g.add(plus1, plus2);
      break;
    }
    case 'shield': {
      g.add(new THREE.Mesh(new THREE.SphereGeometry(0.42, 28, 20), new THREE.MeshPhysicalMaterial({ color: '#bde7ff', transparent: true, opacity: 0.45, roughness: 0.02, clearcoat: 1, iridescence: 1, emissive: '#3aa0ff', emissiveIntensity: 0.4, depthWrite: false })));
      const hex = new THREE.Mesh(new THREE.CylinderGeometry(0.2, 0.2, 0.06, 6), glow('#5ac8fa', 2));
      hex.rotation.x = Math.PI / 2;
      g.add(hex);
      break;
    }
    case 'turbo': {
      for (const x of [-0.25, 0.25]) {
        const w = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.09, 12, 24), plastic('#1f2937', { rough: 0.7, clearcoat: 0 }));
        w.rotation.y = Math.PI / 2;
        w.position.x = x;
        g.add(w);
        const hub = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.1, 0.12, 16), plastic('#ff9f1c'));
        hub.rotation.z = Math.PI / 2;
        hub.position.x = x;
        g.add(hub);
      }
      const axle = new THREE.Mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.5, 8), metal('#cbd5e1'));
      axle.rotation.z = Math.PI / 2;
      g.add(axle);
      const flame = new THREE.Mesh(new THREE.ConeGeometry(0.12, 0.35, 12), glow('#ff6b00', 2.5));
      flame.rotation.x = Math.PI / 2;
      flame.position.z = -0.25;
      g.add(flame);
      break;
    }
    case 'infinite': {
      const pts: THREE.Vector3[] = [];
      for (let i = 0; i <= 200; i++) {
        const t = (i / 200) * Math.PI * 2;
        const s = Math.sin(t), c = Math.cos(t);
        const d = 1 + s * s;
        const lx = (0.42 * c) / d, ly = (0.42 * s * c) / d;
        const coil = 0.05;
        pts.push(new THREE.Vector3(lx + Math.cos(t * 24) * coil * 0.3, ly + Math.sin(t * 24) * coil, Math.cos(t * 24) * coil));
      }
      g.add(new THREE.Mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts, true), 300, 0.025, 6, true), metal('#f2c94c', 0.2)));
      break;
    }
    case 'power': {
      const geo = new THREE.ExtrudeGeometry(starShape(0.42, 0.19), { depth: 0.14, bevelEnabled: true, bevelSize: 0.04, bevelThickness: 0.04, bevelSegments: 3 });
      geo.center();
      g.add(new THREE.Mesh(geo, new THREE.MeshPhysicalMaterial({ color: '#ffe14d', emissive: '#ffb703', emissiveIntensity: 0.9, roughness: 0.2, clearcoat: 1 })));
      for (const x of [-0.08, 0.08]) {
        const eye = new THREE.Mesh(new THREE.SphereGeometry(0.035, 8, 6), plastic('#222'));
        eye.position.set(x, 0.04, 0.12);
        g.add(eye);
      }
      break;
    }
  }
  return g;
}

export class Pickups {
  items: Item[] = [];
  private root = new THREE.Group();

  constructor(
    scene: THREE.Scene,
    spots: { kind: PickupKind; pos: THREE.Vector3 }[],
    weaponSpots: { weapon: WeaponId; pos: THREE.Vector3 }[],
    private fx: Effects,
    private audio: AudioEngine,
    private events: Emitter<GameEvents>,
  ) {
    scene.add(this.root);
    for (const s of spots) this.items.push(this.makeItem(s.kind, s.pos, PICKUP_INFO[s.kind].color, buildPickupModel(s.kind)));
    for (const w of weaponSpots) {
      const model = buildWeaponModel(w.weapon);
      flattenByMaterial(model);
      model.scale.setScalar(1.5);
      model.rotation.y = Math.PI / 2;
      const holder = new THREE.Group();
      holder.add(model);
      const it = this.makeItem('weapon', w.pos, WEAPONS[w.weapon].colors.glow, holder);
      it.weapon = w.weapon;
      // pedestal
      const ped = new THREE.Mesh(new THREE.CylinderGeometry(0.7, 0.8, 0.18, 24), plastic('#ffffff', { rough: 0.3 }));
      ped.position.y = 0.09;
      ped.castShadow = ped.receiveShadow = true;
      it.group.add(ped);
      this.items.push(it);
    }
  }

  private makeItem(kind: Item['kind'], pos: THREE.Vector3, color: string, model: THREE.Object3D): Item {
    const group = new THREE.Group();
    group.position.copy(pos);
    const spinner = new THREE.Group();
    spinner.position.y = 1.0;
    spinner.add(model);
    model.traverse((o) => {
      if ((o as THREE.Mesh).isMesh) (o as THREE.Mesh).castShadow = true;
    });
    group.add(spinner);
    const halo = new THREE.Sprite(new THREE.SpriteMaterial({ map: softDotTexture(), color, transparent: true, opacity: 0.55, blending: THREE.AdditiveBlending, depthWrite: false }));
    halo.scale.setScalar(kind === 'weapon' ? 2.2 : 1.6);
    halo.position.y = 1.0;
    group.add(halo);
    const ring = new THREE.Mesh(new THREE.RingGeometry(0.55, 0.75, 32), new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.6, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide, toneMapped: false }));
    ring.rotation.x = -Math.PI / 2;
    ring.position.y = 0.04;
    group.add(ring);
    this.root.add(group);
    return { kind, pos: pos.clone(), group, spinner, halo, ring, available: true, respawnAt: 0, phase: Math.random() * 6, color };
  }

  reset() {
    for (const it of this.items) {
      it.available = true;
      it.group.visible = true;
      it.spinner.scale.setScalar(1);
    }
  }

  /** For bots: what's on the map. */
  list() {
    return this.items.map((i) => ({ pos: i.pos, kind: i.kind === 'weapon' ? `weapon:${i.weapon}` : i.kind, available: i.available }));
  }

  private respawnTime(it: Item) {
    return PICKUPS.respawn[it.kind] ?? 20;
  }

  private canUse(it: Item, a: Actor) {
    switch (it.kind) {
      case 'health':
        return a.health < COMBAT.maxHealth || a.weapons.some((w) => w && !w.isEnergy && w.reserve < w.cfg.reserve * 0.5);
      case 'shield':
        return a.shield < COMBAT.maxShield;
      default:
        return true;
    }
  }

  private take(it: Item, a: Actor, now: number) {
    it.available = false;
    it.respawnAt = now + this.respawnTime(it);
    this.fx.pickupSparkle(it.pos, it.color);
    let label = '';
    switch (it.kind) {
      case 'health':
        a.health = Math.min(COMBAT.maxHealth, a.health + PICKUPS.healthAmount);
        label = PICKUP_INFO.health.label;
        break;
      case 'shield':
        a.shield = Math.min(COMBAT.maxShield, a.shield + PICKUPS.shieldAmount);
        label = PICKUP_INFO.shield.label;
        break;
      case 'turbo':
        a.buffs.turbo = now + PICKUPS.turboTime;
        label = PICKUP_INFO.turbo.label;
        break;
      case 'infinite':
        a.buffs.infinite = now + PICKUPS.infiniteTime;
        label = PICKUP_INFO.infinite.label;
        break;
      case 'power':
        a.buffs.power = now + PICKUPS.powerTime;
        label = PICKUP_INFO.power.label;
        break;
    }
    // no weapon pedestals any more: every pick-up also tops up the ammo of both your weapons
    let ammo = false;
    for (const w of a.weapons) {
      if (!w || w.isEnergy || w.reserve >= w.cfg.reserve) continue;
      w.reserve = Math.min(w.cfg.reserve, w.reserve + Math.ceil(w.cfg.reserve * 0.5));
      ammo = true;
    }
    if (ammo) label += ' + ammo';
    if (a.isPlayer) this.audio.pickup(it.kind as PickupKind, it.pos, true);
    else this.audio.pickup(it.kind as PickupKind, it.pos, false);
    this.events.emit('pickup', { actor: a, kind: it.kind, label });
  }

  nearestWeapon(a: Actor, r = 2.3) {
    let best: Item | null = null;
    let bd = r * r;
    for (const it of this.items) {
      if (it.kind !== 'weapon' || !it.available) continue;
      const d = it.pos.distanceToSquared(a.pos);
      if (d < bd && Math.abs(it.pos.y - a.pos.y) < 2) {
        bd = d;
        best = it;
      }
    }
    return best;
  }

  prompt(a: Actor): string | null {
    const it = this.nearestWeapon(a);
    if (!it || !it.weapon) return null;
    const has = a.weapons.some((w) => w?.id === it.weapon);
    return has ? `Press E to grab ${WEAPONS[it.weapon].name} ammo` : `Press E to pick up ${WEAPONS[it.weapon].name}`;
  }

  /** Swap / ammo pickup. Returns the slot that changed or -1. */
  interact(a: Actor, now: number): number {
    const it = this.nearestWeapon(a);
    if (!it || !it.weapon) return -1;
    const id = it.weapon;
    const existing = a.weapons.findIndex((w) => w?.id === id);
    let slot: number;
    if (existing >= 0) {
      a.weapons[existing]!.addAmmo();
      slot = existing;
      this.events.emit('pickup', { actor: a, kind: 'ammo', label: `${WEAPONS[id].name} ammo` });
      this.audio.pickup('ammo', it.pos, a.isPlayer);
    } else {
      const empty = a.weapons.findIndex((w) => !w);
      slot = empty >= 0 ? empty : a.slot;
      a.weapon?.cancelReload();
      a.weapons[slot] = new WeaponState(id);
      a.slot = slot;
      a.weapons[slot]!.equip(now);
      this.events.emit('pickup', { actor: a, kind: 'weapon', label: WEAPONS[id].name });
      this.audio.pickup('weapon', it.pos, a.isPlayer);
    }
    it.available = false;
    it.respawnAt = now + this.respawnTime(it);
    this.fx.pickupSparkle(it.pos, it.color);
    return slot;
  }

  update(dt: number, now: number, actors: Actor[], botWantsWeapon: (a: Actor, id: WeaponId) => boolean, onBotWeapon: (a: Actor) => void) {
    for (const it of this.items) {
      it.phase += dt;
      if (!it.available) {
        if (now >= it.respawnAt) {
          it.available = true;
          it.spinner.scale.setScalar(0.01);
          this.fx.pickupSparkle(it.pos, it.color);
          this.audio.spawnPop(it.pos.clone().setY(it.pos.y + 1));
        }
        it.group.visible = it.available;
        continue;
      }
      it.group.visible = true;
      // grow back in, spin, bob, pulse
      const s = Math.min(1, it.spinner.scale.x + dt * 3);
      it.spinner.scale.setScalar(s);
      it.spinner.rotation.y += dt * (it.kind === 'weapon' ? 0.9 : 1.8);
      it.spinner.position.y = 1.0 + Math.sin(it.phase * 2.2) * 0.12;
      it.halo.material.opacity = 0.4 + Math.sin(it.phase * 4) * 0.15;
      const rs = 1 + Math.sin(it.phase * 3) * 0.08;
      it.ring.scale.set(rs, rs, rs);
      // auto-collect
      for (const a of actors) {
        if (!a.alive) continue;
        const dx = a.pos.x - it.pos.x, dz = a.pos.z - it.pos.z, dy = a.pos.y - it.pos.y;
        if (dx * dx + dz * dz > 1.5 || Math.abs(dy) > 1.6) continue;
        if (it.kind === 'weapon') {
          // bots grab weapons they like by walking over them; the player uses E
          if (!a.isPlayer && it.weapon && botWantsWeapon(a, it.weapon)) {
            this.interact(a, now);
            onBotWeapon(a);
          }
          continue;
        }
        if (this.canUse(it, a)) {
          this.take(it, a, now);
          break;
        }
      }
    }
  }
}

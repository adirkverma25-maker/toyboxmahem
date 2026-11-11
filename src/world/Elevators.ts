import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import type RAPIER from '@dimforge/rapier3d-compat';
import { Physics } from '../physics/Physics';
import { AudioEngine } from '../audio/Audio';
import { plastic, metal, glow } from '../render/materials';
/** (x, z) is the shaft center, `exit` points from the shaft onto the upper floor. */
export interface ElevatorSite {
  x: number;
  z: number;
  exit: [number, number];
  name: string;
}
import type { Actor } from '../entities/Actor';
import type { NavGraph } from '../nav/NavGraph';
import type { ElevatorView } from '../entities/Bot';
import { smoothstep } from '../core/math';

/** Timing of the automatic cycle: wait, ride up, wait, ride down. */
export const LIFT = { wait: 3, travel: 5, half: 1.2, thick: 0.3 };

type Phase = 'waitBottom' | 'up' | 'waitTop' | 'down';

interface Lift {
  center: THREE.Vector3;
  exit: THREE.Vector3; // unit, toward the shelf
  side: THREE.Vector3; // unit, across the shaft
  collider: RAPIER.Collider;
  platform: THREE.Group;
  cable: THREE.Mesh;
  lamp: THREE.MeshStandardMaterial;
  y: number; // platform top
  phase: Phase;
  t: number; // seconds left in this phase
  view: ElevatorView;
}

function hazardTexture() {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 32;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = '#ffd23f';
  ctx.fillRect(0, 0, 256, 32);
  ctx.fillStyle = '#1d1d1f';
  for (let x = -32; x < 288; x += 32) {
    ctx.beginPath();
    ctx.moveTo(x, 32);
    ctx.lineTo(x + 16, 0);
    ctx.lineTo(x + 32, 0);
    ctx.lineTo(x + 16, 32);
    ctx.fill();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = THREE.RepeatWrapping;
  return t;
}

/**
 * Three toy construction lifts that run between the floor and the high shelf on a loop.
 * The platform is a collider we teleport every frame; toys standing on it are carried,
 * toys standing underneath a descending platform get nudged out of the shaft.
 */
export class Elevators {
  list: Lift[] = [];
  group = new THREE.Group();
  private bottomY = LIFT.thick;
  constructor(scene: THREE.Scene, private phys: Physics, private audio: AudioEngine, sites: ElevatorSite[], private topY: number) {
    scene.add(this.group);
    const hz = hazardTexture();
    const deck = plastic('#ffbe0b', { rough: 0.4 });
    const edge = new THREE.MeshStandardMaterial({ map: hz, roughness: 0.5 });
    const red = plastic('#e63946', { rough: 0.3 });
    const steel = metal('#c9ced6', 0.3);
    sites.forEach((s, i) => {
      const center = new THREE.Vector3(s.x, 0, s.z);
      const exit = new THREE.Vector3(s.exit[0], 0, s.exit[1]);
      const side = new THREE.Vector3(-exit.z, 0, exit.x);
      const yaw = Math.atan2(exit.x, exit.z);
      // platform
      const platform = new THREE.Group();
      const H = LIFT.half;
      const top = new THREE.Mesh(new RoundedBoxGeometry(H * 2, LIFT.thick, H * 2, 2, 0.06), deck);
      top.position.y = -LIFT.thick / 2;
      platform.add(top);
      for (let k = 0; k < 4; k++) {
        const strip = new THREE.Mesh(new THREE.BoxGeometry(H * 2, 0.12, 0.02), edge);
        const a = (k * Math.PI) / 2;
        strip.position.set(Math.sin(a) * (H + 0.005), -0.12, Math.cos(a) * (H + 0.005));
        strip.rotation.y = a;
        (strip.material as THREE.MeshStandardMaterial).map!.repeat.set(4, 1);
        platform.add(strip);
      }
      // little corner posts + a back rail (decor)
      for (const [u, v] of [[-1, -1], [-1, 1]] as const) {
        const p = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.9, 8), red);
        p.position.set(v * (H - 0.08), 0.45, u * (H - 0.08));
        platform.add(p);
      }
      const rail = new THREE.Mesh(new THREE.CylinderGeometry(0.04, 0.04, H * 2 - 0.16, 8), red);
      rail.rotation.z = Math.PI / 2;
      rail.position.set(0, 0.9, -(H - 0.08));
      platform.add(rail);
      const lampMat = new THREE.MeshStandardMaterial({ color: '#2dc653', emissive: '#2dc653', emissiveIntensity: 2.5 });
      const lamp = new THREE.Mesh(new THREE.SphereGeometry(0.09, 10, 8), lampMat);
      lamp.position.set(0, 1.0, -(H - 0.08));
      platform.add(lamp);
      platform.rotation.y = yaw;
      platform.traverse((o) => ((o as THREE.Mesh).isMesh ? (((o as THREE.Mesh).castShadow = true), ((o as THREE.Mesh).receiveShadow = true)) : null));
      this.group.add(platform);
      // tower: two posts at the shelf side, a crossbar and a pulley
      const postH = this.topY + 3.2;
      for (const v of [-1, 1]) {
        const pos = center.clone().addScaledVector(exit, H + 0.12).addScaledVector(side, v * (H + 0.12));
        const post = new THREE.Mesh(new THREE.BoxGeometry(0.24, postH, 0.24), red);
        post.position.set(pos.x, postH / 2, pos.z);
        post.castShadow = post.receiveShadow = true;
        this.group.add(post);
        phys.box(new THREE.Vector3(pos.x, postH / 2, pos.z), new THREE.Vector3(0.12, postH / 2, 0.12), 'plastic');
        // ladder rungs for the toy look
        for (let y = 1; y < postH - 1; y += 1.2) {
          const r = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.05, 0.05), steel);
          r.position.set(pos.x, y, pos.z);
          r.rotation.y = yaw;
          this.group.add(r);
        }
      }
      const barPos = center.clone().addScaledVector(exit, H + 0.12);
      const bar = new THREE.Mesh(new THREE.BoxGeometry(H * 2 + 0.5, 0.28, 0.28), red);
      bar.position.set(barPos.x, postH, barPos.z);
      bar.rotation.y = yaw;
      this.group.add(bar);
      const arm = new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.2, H + 0.3), red);
      arm.position.copy(center).addScaledVector(exit, (H + 0.12) / 2).setY(postH);
      arm.rotation.y = yaw;
      this.group.add(arm);
      const pulley = new THREE.Mesh(new THREE.TorusGeometry(0.32, 0.08, 8, 20), steel);
      pulley.position.set(center.x, postH - 0.35, center.z);
      pulley.rotation.y = yaw + Math.PI / 2;
      this.group.add(pulley);
      const cable = new THREE.Mesh(new THREE.CylinderGeometry(0.025, 0.025, 1, 6), plastic('#222222'));
      this.group.add(cable);
      // the collider we teleport around
      const collider = phys.box(new THREE.Vector3(center.x, this.bottomY - LIFT.thick / 2, center.z), new THREE.Vector3(H, LIFT.thick / 2, H), 'plastic', new THREE.Euler(0, yaw, 0));
      const phase: Phase = i === 1 ? 'waitTop' : 'waitBottom';
      const y = phase === 'waitTop' ? this.topY : this.bottomY;
      const view: ElevatorView = { center, bottomY: this.bottomY, topY: this.topY, platformY: y, parked: phase === 'waitTop' ? 'top' : 'bottom', leaveIn: LIFT.wait };
      this.list.push({ center, exit, side, collider, platform, cable, lamp: lampMat, y, phase, t: LIFT.wait + i * 1.3, view });
    });
    for (const l of this.list) this.place(l);
    void glow;
  }

  /** Waiting spots next to each shaft for the bots' nav graph. */
  linkNav(nav: NavGraph) {
    let ok = 0;
    this.list.forEach((l, i) => {
      const bottom = l.center.clone().addScaledVector(l.exit, -(LIFT.half + 1.4)).setY(0);
      const top = l.center.clone().addScaledVector(l.exit, LIFT.half + 1.5).setY(this.topY);
      if (nav.addElevator(bottom, top, i)) ok++;
    });
    return ok;
  }

  views() {
    return this.list.map((l) => l.view);
  }

  private place(l: Lift) {
    l.platform.position.set(l.center.x, l.y, l.center.z);
    l.collider.setTranslation({ x: l.center.x, y: l.y - LIFT.thick / 2, z: l.center.z });
    const top = this.topY + 3.2 - 0.35;
    const len = Math.max(0.1, top - (l.y + 1.0));
    l.cable.position.set(l.center.x, l.y + 1.0 + len / 2, l.center.z);
    l.cable.scale.y = len;
  }

  update(dt: number, now: number, actors: Actor[], listener: THREE.Vector3) {
    const H = LIFT.half;
    for (const l of this.list) {
      const prevY = l.y;
      l.t -= dt;
      if (l.t <= 0) {
        const next: Record<Phase, Phase> = { waitBottom: 'up', up: 'waitTop', waitTop: 'down', down: 'waitBottom' };
        l.phase = next[l.phase];
        l.t = l.phase === 'up' || l.phase === 'down' ? LIFT.travel : LIFT.wait;
        if ((l.phase === 'waitTop' || l.phase === 'waitBottom') && l.center.distanceTo(listener) < 40) {
          this.audio.elevatorDing(l.center.clone().setY(l.phase === 'waitTop' ? this.topY + 1 : 1.2));
        }
      }
      if (l.phase === 'up') l.y = this.bottomY + (this.topY - this.bottomY) * smoothstep(0, 1, 1 - l.t / LIFT.travel);
      else if (l.phase === 'down') l.y = this.topY - (this.topY - this.bottomY) * smoothstep(0, 1, 1 - l.t / LIFT.travel);
      else l.y = l.phase === 'waitTop' ? this.topY : this.bottomY;
      const dy = l.y - prevY;
      // lamp: green while parked, amber when about to go, red while moving
      const parked = l.phase === 'waitTop' || l.phase === 'waitBottom';
      l.lamp.color.set(parked ? (l.t < 0.8 ? '#ffbe0b' : '#2dc653') : '#ff3b30');
      l.lamp.emissive.copy(l.lamp.color);
      l.view.platformY = l.y;
      l.view.parked = l.phase === 'waitTop' ? 'top' : l.phase === 'waitBottom' ? 'bottom' : 'moving';
      l.view.leaveIn = parked ? l.t : 0;
      if (Math.abs(dy) > 1e-6) {
        for (const a of actors) {
          if (!a.alive || a.grapple) continue;
          const rx = a.pos.x - l.center.x, rz = a.pos.z - l.center.z;
          let u = rx * l.exit.x + rz * l.exit.z;
          let v = rx * l.side.x + rz * l.side.z;
          const near = Math.abs(u) < H + 0.1 && Math.abs(v) < H + 0.1;
          if (near && a.pos.y >= prevY - 0.5 && a.pos.y <= prevY + 0.45) {
            if (dy < 0 && prevY > this.topY - 0.05 && u > H - 0.45) {
              // was mostly on the shelf when the lift left: stay on the shelf
              u = H + 0.48;
            } else {
              // ride along, kept clear of the shelf edge and the posts
              u = Math.max(-H + 0.35, Math.min(H - 0.45, u));
              v = Math.max(-H + 0.35, Math.min(H - 0.35, v));
              a.pos.y = l.y;
              a.vel.y = dy > 0 ? Math.max(0, a.vel.y) : 0;
              a.grounded = true;
              a.lastGrounded = now;
            }
            a.pos.x = l.center.x + l.exit.x * u + l.side.x * v;
            a.pos.z = l.center.z + l.exit.z * u + l.side.z * v;
            a.sync();
          } else if (dy < 0 && Math.abs(u) < H + 0.42 && Math.abs(v) < H + 0.42 && a.pos.y < prevY - 0.5 && a.pos.y + 1.95 > l.y - LIFT.thick - 0.05) {
            // standing in the shaft under a descending platform: shove out the nearest open side
            const outs = [
              { d: H + 0.5 - u, du: 1, dv: 0 },
              { d: H + 0.5 + u, du: -1, dv: 0 },
              { d: H + 0.5 - v, du: 0, dv: 1 },
              { d: H + 0.5 + v, du: 0, dv: -1 },
            ].sort((p, q) => p.d - q.d)[0];
            u += outs.du * outs.d;
            v += outs.dv * outs.d;
            a.pos.x = l.center.x + l.exit.x * u + l.side.x * v;
            a.pos.z = l.center.z + l.exit.z * u + l.side.z * v;
            a.sync();
          }
        }
      }
      this.place(l);
    }
  }
}

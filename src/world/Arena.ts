import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { Physics, SurfaceMat } from '../physics/Physics';
import { EnvMats, StaticBatcher, plastic, glow, metal, rubber, tiledBox } from '../render/materials';
import { bookTexture, keyboardLabelTexture, monitorScreenTexture, skyTexture } from '../render/textures';
import { Builder, V3, v3 } from './Builder';
import { seeded } from '../core/math';
import type { PickupKind } from '../match/Pickups';
import type { WeaponId } from '../weapons/weaponConfig';

export interface Zone {
  name: string;
  min: [number, number];
  max: [number, number];
  ambience: 'bed' | 'desk' | 'closet' | 'garage' | 'dino' | 'brick' | 'rug';
}

export interface Animated {
  update(dt: number, t: number): void;
}

export interface ArenaInfo {
  root: THREE.Group;
  zones: Zone[];
  pickupSpots: { kind: PickupKind; pos: THREE.Vector3 }[];
  weaponSpots: { weapon: WeaponId; pos: THREE.Vector3 }[];
  animated: Animated[];
  sun: THREE.DirectionalLight;
  hemi: THREE.HemisphereLight;
  sunDir: THREE.Vector3;
  pointLights: THREE.PointLight[];
  looseBricks: LooseBricks;
  bounds: { min: THREE.Vector3; max: THREE.Vector3 };
  /** window rectangle in world space (for sunbeam / dust) */
  window: { x0: number; x1: number; y0: number; y1: number; z: number };
}

export const ROOM = { x0: -32, x1: 32, z0: -36, z1: 36, h: 30 };
/** The high wall shelf that runs around the whole room. The toy train runs along the wall side. */
export const SHELF = { y: 21, depth: 4.2, trackInset: 0.95 };
/**
 * Toy elevators from the floor to the shelf. (x, z) is the shaft center, `exit` points from the shaft onto the shelf.
 */
export const ELEVATOR_SITES: { x: number; z: number; exit: [number, number]; name: string }[] = [
  { x: 3.2, z: ROOM.z1 - SHELF.depth - 1.2, exit: [0, 1], name: 'south' },
  { x: ROOM.x1 - SHELF.depth - 1.2, z: 10.2, exit: [1, 0], name: 'east' },
  { x: ROOM.x0 + SHELF.depth + 1.2, z: -9.3, exit: [-1, 0], name: 'west' },
];

const BRICK_COLORS = ['#d6342c', '#f2c12e', '#1f6fd1', '#2f9e44', '#f4f4f4', '#f08c1f', '#7b3fb5'];

/** Dynamic loose bricks that scatter from explosions. Drawn with one InstancedMesh. */
export class LooseBricks implements Animated {
  mesh: THREE.InstancedMesh;
  bodies: import('@dimforge/rapier3d-compat').RigidBody[] = [];
  private m = new THREE.Matrix4();
  private q = new THREE.Quaternion();
  private p = new THREE.Vector3();
  private s = new THREE.Vector3(1, 1, 1);
  constructor(private phys: Physics, spots: THREE.Vector3[], parent: THREE.Object3D) {
    const geo = new RoundedBoxGeometry(0.9, 0.55, 1.8, 2, 0.06);
    const mat = new THREE.MeshPhysicalMaterial({ roughness: 0.3, clearcoat: 0.7 });
    this.mesh = new THREE.InstancedMesh(geo, mat, spots.length);
    this.mesh.castShadow = this.mesh.receiveShadow = true;
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    const rnd = seeded(99);
    spots.forEach((s, i) => {
      const { body } = phys.dynamicBox(s, v3(0.45, 0.275, 0.9), 'plastic', 0.5, new THREE.Euler(0, rnd() * Math.PI, 0));
      this.bodies.push(body);
      this.mesh.setColorAt(i, new THREE.Color(BRICK_COLORS[i % BRICK_COLORS.length]));
    });
    this.mesh.frustumCulled = false;
    parent.add(this.mesh);
    this.update();
  }
  update() {
    for (let i = 0; i < this.bodies.length; i++) {
      const b = this.bodies[i];
      const t = b.translation();
      const r = b.rotation();
      this.p.set(t.x, t.y, t.z);
      this.q.set(r.x, r.y, r.z, r.w);
      // a brick that somehow escaped the room gets put back
      if (t.y < -5 || Math.abs(t.x) > 40 || Math.abs(t.z) > 40) {
        b.setTranslation({ x: -22, y: 3, z: 2 }, true);
        b.setLinvel({ x: 0, y: 0, z: 0 }, true);
      }
      this.m.compose(this.p, this.q, this.s);
      this.mesh.setMatrixAt(i, this.m);
    }
    this.mesh.instanceMatrix.needsUpdate = true;
  }
  /** Radial impulse from an explosion. */
  blast(center: THREE.Vector3, radius: number, strength: number) {
    for (const b of this.bodies) {
      const t = b.translation();
      const dx = t.x - center.x, dy = t.y - center.y, dz = t.z - center.z;
      const d = Math.sqrt(dx * dx + dy * dy + dz * dz);
      if (d > radius * 1.6) continue;
      const f = (1 - d / (radius * 1.6)) * strength;
      const inv = 1 / Math.max(0.3, d);
      b.applyImpulse({ x: dx * inv * f, y: (Math.abs(dy) * inv + 0.9) * f, z: dz * inv * f }, true);
      b.applyTorqueImpulse({ x: (Math.random() - 0.5) * f * 0.3, y: (Math.random() - 0.5) * f * 0.3, z: (Math.random() - 0.5) * f * 0.3 }, true);
    }
  }
}

/** Cloth panel with gentle procedural sway (blankets, curtains, drapes). */
function swayCloth(width: number, height: number, mat: THREE.Material, segW: number, segH: number, amp: number, speed: number, sag = 0): THREE.Mesh & Animated {
  const geo = new THREE.PlaneGeometry(width, height, segW, segH);
  geo.translate(0, -height / 2, 0); // pivot at top edge
  const pos = geo.getAttribute('position') as THREE.BufferAttribute;
  const base = Float32Array.from(pos.array as Float32Array);
  const mesh = new THREE.Mesh(geo, mat) as unknown as THREE.Mesh & Animated;
  mesh.castShadow = true;
  mesh.receiveShadow = true;
  const phase = Math.random() * 10;
  mesh.update = (_dt: number, t: number) => {
    for (let i = 0; i < pos.count; i++) {
      const bx = base[i * 3], by = base[i * 3 + 1];
      const k = Math.min(1, -by / height); // 0 at top, 1 at bottom
      const wave = Math.sin(t * speed + bx * 0.6 + phase) * 0.6 + Math.sin(t * speed * 1.7 + bx * 1.3 + phase * 2) * 0.4;
      pos.setZ(i, wave * amp * k * k + sag * Math.sin((bx / width + 0.5) * Math.PI) * (1 - k * 0.3));
    }
    pos.needsUpdate = true;
    geo.computeVertexNormals();
  };
  mesh.update(0, 0);
  return mesh;
}

export function buildArena(scene: THREE.Scene, phys: Physics): ArenaInfo {
  const root = new THREE.Group();
  root.name = 'arena';
  scene.add(root);
  const M = new EnvMats();
  const batch = new StaticBatcher();
  const B = new Builder(batch, phys);
  const animated: Animated[] = [];
  const pointLights: THREE.PointLight[] = [];
  const rnd = seeded(2024);

  // ---------------------------------------------------------------- ROOM SHELL
  B.box([ROOM.x0 - 1, -1, ROOM.z0 - 1], [ROOM.x1 + 1, 0, ROOM.z1 + 1], M.floor, 'wood', { tile: 1 / 16 });
  B.box([ROOM.x0 - 1, ROOM.h, ROOM.z0 - 1], [ROOM.x1 + 1, ROOM.h + 1, ROOM.z1 + 1], M.ceiling, 'wood', { cast: false });
  const WIN = { x0: -6, x1: 10, y0: 12, y1: 26, z: ROOM.z0 };
  // north wall with a window hole
  B.box([ROOM.x0 - 1, 0, ROOM.z0 - 1], [WIN.x0, ROOM.h, ROOM.z0], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([WIN.x1, 0, ROOM.z0 - 1], [ROOM.x1 + 1, ROOM.h, ROOM.z0], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([WIN.x0, 0, ROOM.z0 - 1], [WIN.x1, WIN.y0, ROOM.z0], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([WIN.x0, WIN.y1, ROOM.z0 - 1], [WIN.x1, ROOM.h, ROOM.z0], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([ROOM.x0 - 1, 0, ROOM.z1], [ROOM.x1 + 1, ROOM.h, ROOM.z1 + 1], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([ROOM.x0 - 1, 0, ROOM.z0], [ROOM.x0, ROOM.h, ROOM.z1], M.wallpaper, 'wood', { tile: 1 / 12 });
  B.box([ROOM.x1, 0, ROOM.z0], [ROOM.x1 + 1, ROOM.h, ROOM.z1], M.wallpaper, 'wood', { tile: 1 / 12 });
  // baseboards
  B.box([ROOM.x0, 0, ROOM.z0], [ROOM.x1, 1.1, ROOM.z0 + 0.35], M.trim, null);
  B.box([ROOM.x0, 0, ROOM.z1 - 0.35], [ROOM.x1, 1.1, ROOM.z1], M.trim, null);
  B.box([ROOM.x0, 0, ROOM.z0], [ROOM.x0 + 0.35, 1.1, ROOM.z1], M.trim, null);
  B.box([ROOM.x1 - 0.35, 0, ROOM.z0], [ROOM.x1, 1.1, ROOM.z1], M.trim, null);
  // window frame, mullions, sill
  B.box([WIN.x0 - 0.6, WIN.y0 - 0.6, ROOM.z0 - 0.2], [WIN.x0, WIN.y1 + 0.6, ROOM.z0 + 0.5], M.trim, 'wood');
  B.box([WIN.x1, WIN.y0 - 0.6, ROOM.z0 - 0.2], [WIN.x1 + 0.6, WIN.y1 + 0.6, ROOM.z0 + 0.5], M.trim, 'wood');
  B.box([WIN.x0, WIN.y1, ROOM.z0 - 0.2], [WIN.x1, WIN.y1 + 0.6, ROOM.z0 + 0.5], M.trim, 'wood');
  B.box([(WIN.x0 + WIN.x1) / 2 - 0.25, WIN.y0, ROOM.z0 - 0.6], [(WIN.x0 + WIN.x1) / 2 + 0.25, WIN.y1, ROOM.z0 - 0.2], M.trim, 'wood');
  B.box([WIN.x0, (WIN.y0 + WIN.y1) / 2 - 0.25, ROOM.z0 - 0.6], [WIN.x1, (WIN.y0 + WIN.y1) / 2 + 0.25, ROOM.z0 - 0.2], M.trim, 'wood');
  B.box([WIN.x0 - 1.2, WIN.y0 - 0.5, ROOM.z0 - 0.6], [WIN.x1 + 1.2, WIN.y0, ROOM.z0 + 2.4], M.trim, 'wood');
  // sky outside
  const sky = new THREE.Mesh(new THREE.PlaneGeometry(90, 45), new THREE.MeshBasicMaterial({ map: skyTexture(), toneMapped: false, fog: false }));
  sky.position.set(2, 18, ROOM.z0 - 14);
  root.add(sky);
  // curtains
  for (const [x, m] of [[WIN.x0 - 2.2, M.fabricA], [WIN.x1 + 2.2, M.fabricA]] as const) {
    const c = swayCloth(4, 18, m, 8, 16, 0.35, 0.9);
    c.position.set(x, 28.5, ROOM.z0 + 0.9);
    root.add(c);
    animated.push(c);
  }
  B.cyl([WIN.x0 - 5, 28.6, ROOM.z0 + 0.9], 0.18, 0.1, M.metalSteel, null);
  B.obox([(WIN.x0 + WIN.x1) / 2, 28.6, ROOM.z0 + 0.9], [WIN.x1 - WIN.x0 + 9, 0.3, 0.3], new THREE.Euler(), M.metalSteel, null);

  // high wall shelf: the toy train circles on the wall side, the rest is a walkway you can fight on
  const SH = SHELF.y;
  const SD = SHELF.depth;
  const shelfMat = M.desk;
  B.box([ROOM.x0, SH - 0.5, ROOM.z0], [ROOM.x1, SH, ROOM.z0 + SD], shelfMat, 'wood');
  B.box([ROOM.x0, SH - 0.5, ROOM.z1 - SD], [ROOM.x1, SH, ROOM.z1], shelfMat, 'wood');
  B.box([ROOM.x0, SH - 0.5, ROOM.z0 + SD], [ROOM.x0 + SD, SH, ROOM.z1 - SD], shelfMat, 'wood');
  B.box([ROOM.x1 - SD, SH - 0.5, ROOM.z0 + SD], [ROOM.x1, SH, ROOM.z1 - SD], shelfMat, 'wood');
  // painted edge stripe so the drop is easy to read
  for (const [a, b] of [
    [[ROOM.x0 + SD, SH - 0.52, ROOM.z0 + SD - 0.12], [ROOM.x1 - SD, SH + 0.02, ROOM.z0 + SD]],
    [[ROOM.x0 + SD, SH - 0.52, ROOM.z1 - SD], [ROOM.x1 - SD, SH + 0.02, ROOM.z1 - SD + 0.12]],
    [[ROOM.x0 + SD - 0.12, SH - 0.52, ROOM.z0 + SD], [ROOM.x0 + SD, SH + 0.02, ROOM.z1 - SD]],
    [[ROOM.x1 - SD, SH - 0.52, ROOM.z0 + SD], [ROOM.x1 - SD + 0.12, SH + 0.02, ROOM.z1 - SD]],
  ] as [V3, V3][]) B.box(a, b, plastic('#ffd23f', { rough: 0.4 }), null);
  // shelf brackets
  for (let x = -28; x <= 28; x += 8) {
    if (x > WIN.x0 - 1 && x < WIN.x1 + 1) continue;
    B.box([x - 0.2, SH - 2.6, ROOM.z0], [x + 0.2, SH - 0.5, ROOM.z0 + SD - 0.6], M.trim, null);
    B.box([x - 0.2, SH - 2.6, ROOM.z1 - SD + 0.6], [x + 0.2, SH - 0.5, ROOM.z1], M.trim, null);
  }
  for (let z = -24; z <= 24; z += 8) {
    B.box([ROOM.x0, SH - 2.6, z - 0.2], [ROOM.x0 + SD - 0.6, SH - 0.5, z + 0.2], M.trim, null);
    B.box([ROOM.x1 - SD + 0.6, SH - 2.6, z - 0.2], [ROOM.x1, SH - 0.5, z + 0.2], M.trim, null);
  }
  // ramps up to the shelf: plank from the bed, race track from beside the desk, building-block bridge from the dinos
  {
    const bedTop = 6;
    B.slab([-22.5, bedTop, -12.6], [-22.5, SH, ROOM.z0 + SD], 3, 0.35, M.bedWood, 'wood');
    for (let i = 1; i < 22; i++) {
      const t = i / 22;
      B.obox([-22.5, bedTop + (SH - bedTop) * t + 0.05, -12.6 + (ROOM.z0 + SD + 12.6) * t], [2.8, 0.1, 0.18], new THREE.Euler(Math.atan2(SH - bedTop, -12.6 - ROOM.z0 - SD), 0, 0), M.trim, null);
    }
    const track = plastic('#ff7b00', { rough: 0.35, clearcoat: 0.6 });
    const deskFrom: V3 = [12.4, 0, -4.9], deskTo: V3 = [12.4, SH, ROOM.z0 + SD];
    B.slab(deskFrom, deskTo, 2.8, 0.3, track, 'plastic');
    const ang = Math.atan2(SH, deskFrom[2] - deskTo[2]);
    const len = Math.hypot(SH, deskFrom[2] - deskTo[2]);
    for (const s of [-1, 1]) {
      // low side rails (decor + a little lip)
      B.obox([12.4 + s * 1.35, SH / 2 + 0.12, (deskFrom[2] + deskTo[2]) / 2], [0.1, 0.24, len], new THREE.Euler(ang, 0, 0), plastic('#ffd23f', { rough: 0.3 }), null);
    }
    B.box([11.2, 0, -5.4], [13.6, 0.12, -3.6], track, null);
    const block = plastic('#3a86ff', { rough: 0.3 });
    const dinoFrom: V3 = [-0.9, 0, 13.9], dinoTo: V3 = [ROOM.x0 + SD, SH, 13.9];
    B.slab(dinoFrom, dinoTo, 2.8, 0.45, block, 'plastic');
    const dang = Math.atan2(SH, dinoFrom[0] - dinoTo[0]);
    for (let i = 1; i < 16; i++) {
      const t = i / 16;
      // studs along the block bridge
      for (const dz of [-0.7, 0.7]) B.geo(new THREE.CylinderGeometry(0.18, 0.18, 0.14, 12), block, [dinoFrom[0] + (dinoTo[0] - dinoFrom[0]) * t, SH * t + 0.06, 13.9 + dz], new THREE.Euler(0, 0, -dang));
    }
  }

  // south wall door (decor, shorter than the shelf) + crayon drawings
  B.box([-5, 0, ROOM.z1 - 0.3], [5, 19.4, ROOM.z1], plastic('#f7f1e3', { rough: 0.6, clearcoat: 0.1 }), null);
  B.box([-5.6, 0, ROOM.z1 - 0.45], [-5, 20, ROOM.z1], M.trim, null);
  B.box([5, 0, ROOM.z1 - 0.45], [5.6, 20, ROOM.z1], M.trim, null);
  B.box([-5, 19.4, ROOM.z1 - 0.45], [5, 20, ROOM.z1], M.trim, null);
  const knob = new THREE.SphereGeometry(0.45, 16, 12);
  B.geo(knob, metal('#d4af37', 0.25), [3.8, 10, ROOM.z1 - 0.7]);
  addDrawings(root);

  // ---------------------------------------------------------------- PLAY RUG (center)
  {
    const rug = new THREE.Mesh(new THREE.CylinderGeometry(12, 12, 0.08, 64), M.carpet);
    rug.position.set(2, 0.04, 1);
    rug.receiveShadow = true;
    root.add(rug);
    phys.cylinder(v3(2, 0.04, 1), 0.04, 12, 'carpet');
    // alphabet block pyramid
    const blockCols = ['#e63946', '#2a9d8f', '#f4a261', '#457b9d', '#e9c46a', '#8ab17d'];
    const S = 1.2;
    const letters = 'TOYBOXMAYHEM';
    let li = 0;
    const tiers: [number, number][] = [[3, 0], [2, 1], [1, 2]];
    for (const [n, tier] of tiers) {
      const off = (3 - n) * S * 0.5;
      for (let i = 0; i < n; i++)
        for (let j = 0; j < n; j++) {
          const x = 2 - 1.5 * S + off + i * S + S / 2;
          const z = 1 - 1.5 * S + off + j * S + S / 2;
          const y = tier * S;
          const col = blockCols[(i + j * 2 + tier) % blockCols.length];
          addLetterBlock(B, [x, y + S / 2, z], S * 0.98, col, letters[li++ % letters.length], rnd() * 0.15 - 0.075);
        }
      phys.box(v3(2, tier * S + S / 2, 1), v3((n * S) / 2, S / 2, (n * S) / 2), 'wood');
    }
    // giant striped ball
    const ballGeo = new THREE.SphereGeometry(2, 32, 20);
    B.geo(ballGeo, stripeBallMat(), [-5, 2, 6.5], new THREE.Euler(0.4, 0.3, 0.2));
    phys.ball(v3(-5, 2, 6.5), 2, 'plastic');
    // toy drum
    B.cyl([9, 0, -4], 1.9, 2.2, plastic('#d62828'), 'plastic', 32);
    B.cyl([9, 2.2, -4], 1.95, 0.08, rubber('#f8f4e3'), null, 32);
    for (let i = 0; i < 12; i++) {
      const a = (i / 12) * Math.PI * 2;
      B.obox([9 + Math.cos(a) * 1.92, 1.1, -4 + Math.sin(a) * 1.92], [0.12, 2.4, 0.12], new THREE.Euler(0.4 * Math.sin(i), 0, 0.4 * Math.cos(i)), metal('#f2d16b', 0.3), null);
    }
    B.obox([9.8, 2.6, -3.5], [0.18, 0.18, 3], new THREE.Euler(0.6, 0.4, 0), plastic('#f1c40f'), null);
    // stacking rings
    B.cyl([10.5, 0, 6.5], 1.9, 0.5, plastic('#3d405b'), null, 32);
    const ringCols = ['#e63946', '#f4a261', '#e9c46a', '#2a9d8f', '#457b9d'];
    for (let i = 0; i < 5; i++) {
      const r = 1.7 - i * 0.28;
      const tor = new THREE.TorusGeometry(r - 0.35, 0.36, 12, 32);
      B.geo(tor, plastic(ringCols[i]), [10.5, 0.85 + i * 0.68, 6.5], new THREE.Euler(Math.PI / 2, 0, 0));
    }
    B.cyl([10.5, 0.5, 6.5], 0.35, 3.6, plastic('#3d405b'), null);
    B.geo(new THREE.SphereGeometry(0.6, 16, 12), plastic('#e63946'), [10.5, 4.3, 6.5]);
    phys.cylinder(v3(10.5, 2, 6.5), 2, 1.8, 'plastic');
    // spinning top lying on its side
    B.geo(new THREE.ConeGeometry(1.1, 1.6, 24), plastic('#9b5de5'), [-6, 1.1, -4], new THREE.Euler(0, 0, Math.PI / 2 + 0.4));
    phys.cylinder(v3(-6, 0.9, -4), 0.8, 1.0, 'plastic', new THREE.Euler(0, 0, Math.PI / 2));
    // scattered crayons
    const crayonCols = ['#e63946', '#2a9d8f', '#ffbe0b', '#3a86ff', '#8338ec', '#fb5607'];
    for (let i = 0; i < 9; i++) {
      const a = rnd() * Math.PI * 2;
      const r = 4 + rnd() * 6;
      const x = 2 + Math.cos(a) * r, z = 1 + Math.sin(a) * r;
      if (Math.hypot(x - 2, z - 1) < 3.2 || Math.hypot(x + 5, z - 6.5) < 2.8 || Math.hypot(x - 9, z + 4) < 2.6 || Math.hypot(x - 10.5, z - 6.5) < 2.6) continue;
      const g = new THREE.CylinderGeometry(0.2, 0.2, 2.2, 8);
      B.geo(g, plastic(crayonCols[i % crayonCols.length], { rough: 0.6, clearcoat: 0 }), [x, 0.28, z], new THREE.Euler(Math.PI / 2, 0, rnd() * Math.PI));
    }
  }

  // ---------------------------------------------------------------- BED FORTRESS (NW)
  {
    const bx0 = -32, bx1 = -19, bz0 = -35, bz1 = -12;
    B.box([bx0, 0, -36], [bx1, 12, -35], M.bedWood, 'wood', { round: 0.4 });
    B.box([bx0 + 0.6, 11.4, -36.2], [bx1 - 0.6, 12.6, -34.8], M.bedWood, null, { round: 0.5 });
    for (const [x, z] of [[bx0 + 0.7, bz0 + 0.7], [bx1 - 0.7, bz0 + 0.7], [bx0 + 0.7, bz1 - 0.7], [bx1 - 0.7, bz1 - 0.7], [-25.5, -24]] as const) {
      B.box([x - 0.6, 0, z - 0.6], [x + 0.6, 2.7, z + 0.6], M.bedWood, 'wood', { round: 0.15 });
    }
    B.box([bx0, 2.6, bz0], [bx1, 3.6, bz1], M.bedWood, null, { round: 0.2 });
    B.box([bx0 + 0.2, 3.6, bz0 + 0.2], [bx1 - 0.2, 5.6, bz1 - 0.2], M.sheet, null, { round: 0.6 });
    phys.box(v3((bx0 + bx1) / 2, 4.3, (bz0 + bz1) / 2), v3((bx1 - bx0) / 2, 1.7, (bz1 - bz0) / 2), 'fabric');
    // quilt over the lower 2/3
    B.box([bx0 - 0.2, 5.55, -29], [bx1 + 0.2, 6.05, bz1 + 0.2], M.blanket, null, { round: 0.25 });
    // draped quilt edges (animated)
    const drapeE = swayCloth(17.2, 3.3, M.blanket, 18, 5, 0.12, 0.7);
    drapeE.position.set(bx1 + 0.25, 5.95, (-29 + bz1) / 2);
    drapeE.rotation.y = Math.PI / 2;
    root.add(drapeE);
    animated.push(drapeE);
    const drapeS = swayCloth(13.4, 3.3, M.blanket, 14, 5, 0.12, 0.8);
    drapeS.position.set((bx0 + bx1) / 2, 5.95, bz1 + 0.25);
    root.add(drapeS);
    animated.push(drapeS);
    // pillows (cover)
    for (const [x0, x1, m] of [[-31.3, -26, M.pillow], [-25, -19.7, M.pillow2]] as const) {
      B.box([x0, 6, -34.6], [x1, 7.9, -30.4], m, 'fabric', { round: 0.8 });
    }
    // blanket slope: solid wedge from the floor up to the mattress
    B.wedge([-9.6, 0, -27], -Math.PI / 2, 9.6, 6, 6, M.blanket, 'fabric');
    // rolled blanket bumps at the base of the slope (decor)
    B.geo(new THREE.CapsuleGeometry(0.45, 5, 6, 16), M.blanket, [-9.4, 0.4, -27], new THREE.Euler(Math.PI / 2, 0, 0));
    // under-bed clutter
    B.box([-29, 0, -22], [-26, 1.7, -17.5], M.cardboardShoes, 'cardboard', { round: 0.05 });
    B.box([-23.5, 0, -31], [-21.5, 0.8, -27], M.fabricB, 'fabric', { round: 0.35 });
    B.geo(new THREE.SphereGeometry(1.1, 24, 16), stripeBallMat('#ff006e', '#ffbe0b'), [-22.5, 1.1, -16.5]);
    phys.ball(v3(-22.5, 1.1, -16.5), 1.1, 'plastic');
    // toy chest + lid
    const chestMat = new THREE.MeshStandardMaterial({ map: M.blockWood.map, color: '#e98a7a', roughness: 0.5 });
    B.box([-10, 0, -19], [-3, 5.5, -11], chestMat, 'wood', { round: 0.2 });
    B.box([-10.3, 5.5, -19.3], [-2.7, 6, -10.7], plastic('#f2c14e', { rough: 0.45 }), 'wood', { round: 0.15 });
    B.box([-7, 4, -10.95], [-6, 5.2, -10.7], metal('#d4af37'), null);
    B.geo(new THREE.TorusGeometry(0.9, 0.15, 8, 20), plastic('#ffffff'), [-6.5, 2.6, -10.92]);
    // cardboard ramp up to the chest
    B.slab([6, 0, -15], [-3, 6, -15], 4, 0.35, M.cardboard, 'cardboard');
    B.box([5.5, 0, -17], [6.5, 0.35, -13], M.cardboard, null);
    // blanket bridge (bed -> chest)
    const bridge = swayCloth(9.4, 4.2, M.blanket, 14, 6, 0.03, 0.6, -0.25);
    bridge.rotation.set(-Math.PI / 2, 0, 0);
    bridge.position.set(-14.5, 5.92, -17.1);
    root.add(bridge);
    animated.push(bridge);
    phys.box(v3(-14.5, 5.75, -15), v3(4.7, 0.2, 2.1), 'fabric');
    for (const [x, z] of [[-19.2, -17.1], [-19.2, -12.9], [-9.8, -17.1], [-9.8, -12.9]] as const) {
      B.geo(new THREE.TorusKnotGeometry(0.25, 0.08, 32, 6), plastic('#ffffff', { rough: 0.8 }), [x, 6.05, z]);
    }
  }

  // ---------------------------------------------------------------- DESK OUTPOST (NE)
  let screenTex: ReturnType<typeof monitorScreenTexture> | null = null;
  {
    B.box([14, 7.4, -36], [32, 8, -24], M.desk, 'wood', { round: 0.12 });
    for (const z of [-24.6, -35.4]) B.box([14, 0, z - 0.6], [15.2, 7.4, z + 0.6], M.desk, 'wood', { round: 0.1 });
    B.box([26, 0, -36], [32, 7.4, -24.3], M.desk, 'wood', { round: 0.1 });
    for (const y of [1.2, 3.8]) {
      B.box([26.4, y, -24.4], [31.6, y + 2.2, -24.2], plastic('#e9d8bf', { rough: 0.6, clearcoat: 0 }), null);
      B.box([28.4, y + 1, -24.25], [29.6, y + 1.3, -23.9], metal('#c0c0c0'), null);
    }
    // ruler ramp from the floor
    const rulerMat = plastic('#f6d743', { rough: 0.25, clearcoat: 1 });
    B.slab([2, 0, -25.6], [14, 8, -25.6], 2.6, 0.3, rulerMat, 'plastic');
    {
      const dir = v3(12, 8, 0).normalize();
      for (let i = 1; i < 28; i++) {
        const p = v3(2, 0, -25.6).addScaledVector(dir, i * 0.5);
        const long = i % 4 === 0;
        B.obox([p.x, p.y + 0.02, p.z - 1.3 + (long ? 0.45 : 0.25)], [0.06, 0.04, long ? 0.9 : 0.5], new THREE.Euler(0, 0, Math.atan2(8, 12)), plastic('#222'), null);
      }
    }
    // book staircase (real steps, 0.5 tall)
    const bookCols = ['#c0392b', '#2471a3', '#229954', '#d68910', '#7d3c98', '#117a65', '#ba4a00', '#2e4053'];
    for (let i = 0; i < 16; i++) {
      const y0 = i * 0.5;
      const zFront = -8 - i * 1.0;
      const jitter = (rnd() - 0.5) * 0.4;
      const tex = bookTexture(bookCols[i % 8], ['ATLAS', 'DINOS', 'SPACE', 'PUZZLES', 'POEMS', 'BUGS', 'MAPS', 'ROBOTS'][i % 8], i);
      const mat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6 });
      B.box([14.4 + jitter, y0, -24], [19.4 + jitter * 0.5, y0 + 0.5, zFront], mat, 'cardboard', { round: 0.04 });
      B.box([14.5 + jitter, y0 + 0.04, -23.95], [19.3 + jitter * 0.5, y0 + 0.46, zFront - 0.04], M.paper, null);
    }
    // keyboard (high ground)
    B.box([16, 8, -31], [28, 8.45, -27], plastic('#3a3f4b', { rough: 0.4 }), null, { round: 0.2 });
    phys.box(v3(22, 8.45, -29), v3(6, 0.45, 2), 'plastic');
    {
      const rows = [
        ['ESC', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', '-', '=', '⌫'],
        ['TAB', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', '[', ']', '\\'],
        ['CAPS', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', ';', "'", '⏎', '⏎'],
        ['⇧', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', ',', '.', '/', '⇧', '▲', 'FN'],
      ];
      const keyGeo = new RoundedBoxGeometry(0.72, 0.42, 0.78, 2, 0.1);
      const keyMat = plastic('#f1f1ee', { rough: 0.35 });
      const n = 14 * 4;
      const keys = new THREE.InstancedMesh(keyGeo, keyMat, n);
      const m = new THREE.Matrix4();
      let k = 0;
      for (let r = 0; r < 4; r++)
        for (let c = 0; c < 14; c++) {
          m.makeTranslation(16.43 + c * 0.855, 8.66, -30.5 + r * 0.98);
          keys.setMatrixAt(k++, m);
        }
      keys.castShadow = keys.receiveShadow = true;
      root.add(keys);
      const labels = new THREE.Mesh(
        new THREE.PlaneGeometry(14 * 0.855, 4 * 0.98),
        new THREE.MeshBasicMaterial({ map: keyboardLabelTexture(rows), transparent: true, depthWrite: false }),
      );
      labels.rotation.x = -Math.PI / 2;
      labels.position.set(16.43 - 0.4275 + (14 * 0.855) / 2, 8.875, -30.5 - 0.49 + (4 * 0.98) / 2);
      root.add(labels);
    }
    // monitor
    B.box([20.5, 8, -35.2], [23.5, 8.3, -32], plastic('#2b2d33'), 'plastic', { round: 0.12 });
    B.box([21.6, 8.3, -34.4], [22.4, 11, -33.6], plastic('#2b2d33'), 'plastic', { round: 0.1 });
    B.box([15.6, 10.4, -35.4], [28.4, 17.6, -34.2], plastic('#1d1f24', { rough: 0.3 }), 'plastic', { round: 0.25 });
    screenTex = monitorScreenTexture();
    const screen = new THREE.Mesh(new THREE.PlaneGeometry(12.2, 6.6), new THREE.MeshBasicMaterial({ map: screenTex.texture, toneMapped: false }));
    screen.position.set(22, 14, -34.17);
    root.add(screen);
    const screenLight = new THREE.PointLight('#8a7dff', 6, 14, 2);
    screenLight.position.set(22, 13, -31);
    root.add(screenLight);
    pointLights.push(screenLight);
    // pencil cup with pencils
    B.cyl([15.9, 8, -33.5], 1.1, 3.6, plastic('#3a86ff'), 'plastic', 24);
    const pencilCols = ['#ffbe0b', '#fb5607', '#8338ec', '#06d6a0'];
    for (let i = 0; i < 4; i++) {
      const a = (i / 4) * Math.PI * 2;
      B.geo(new THREE.CylinderGeometry(0.22, 0.22, 7, 6), plastic(pencilCols[i], { rough: 0.5 }), [15.9 + Math.cos(a) * 0.45, 12, -33.5 + Math.sin(a) * 0.45], new THREE.Euler(Math.cos(a) * 0.15, 0, Math.sin(a) * 0.15));
    }
    // book pile on desk (cover)
    let yy = 8;
    for (let i = 0; i < 4; i++) {
      const h = 0.55 + rnd() * 0.2;
      const tex = bookTexture(bookCols[(i + 3) % 8], ['FAIRY', 'COMICS', 'TRAINS', 'SPORTS'][i], i + 20);
      B.box([28.4 + rnd() * 0.3, yy, -31.2 + rnd() * 0.3], [31.4 + rnd() * 0.3, yy + h, -25.2 - rnd() * 0.3], new THREE.MeshStandardMaterial({ map: tex, roughness: 0.6 }), null, { round: 0.05 });
      yy += h;
    }
    phys.box(v3(29.9, (8 + yy) / 2, -28.2), v3(1.6, (yy - 8) / 2, 3.1), 'cardboard');
    // giant pencil lying flat (low cover)
    B.geo(new THREE.CylinderGeometry(0.42, 0.42, 8, 6), plastic('#ffbe0b', { rough: 0.5 }), [21.5, 8.42, -25.4], new THREE.Euler(0, 0, Math.PI / 2));
    B.geo(new THREE.ConeGeometry(0.42, 1.2, 6), M.desk, [26.1, 8.42, -25.4], new THREE.Euler(0, 0, -Math.PI / 2));
    B.geo(new THREE.CylinderGeometry(0.44, 0.44, 0.9, 12), plastic('#ff8fab'), [17.05, 8.42, -25.4], new THREE.Euler(0, 0, Math.PI / 2));
    phys.box(v3(21.6, 8.42, -25.4), v3(4.9, 0.42, 0.42), 'wood');
    // desk lamp
    B.cyl([30.5, 8, -33.8], 1.5, 0.4, metal('#2d6a4f', 0.35), 'metal', 24);
    B.obox([30.5, 11, -33.4], [0.35, 6.2, 0.35], new THREE.Euler(0.15, 0, 0), metal('#2d6a4f', 0.35), 'metal');
    B.obox([29.4, 14.3, -32.4], [0.35, 4, 0.35], new THREE.Euler(0.4, 0, 0.9), metal('#2d6a4f', 0.35), null);
    B.geo(new THREE.ConeGeometry(1.4, 2, 24, 1, true), metal('#2d6a4f', 0.35), [27.8, 15.2, -31.6], new THREE.Euler(0.3, 0, 0.6));
    B.geo(new THREE.SphereGeometry(0.6, 16, 12), glow('#fff2c6', 4), [27.6, 14.6, -31.4]);
    const lamp = new THREE.PointLight('#ffd7a0', 16, 26, 2);
    lamp.position.set(27.2, 13.6, -30.8);
    root.add(lamp);
    pointLights.push(lamp);
    // sticky notes
    B.box([29, 8, -26], [31, 8.12, -24.4], plastic('#fff275', { rough: 0.8, clearcoat: 0 }), null);
  }

  // ---------------------------------------------------------------- CLOSET MAZE (E)
  {
    const cw = M.closetWall;
    const top = 18;
    // walls with two doorways on the west side
    B.box([19.5, 0, -18.5], [20, top, -14], cw, 'wood');
    B.box([19.5, 0, -9], [20, top, -3], cw, 'wood');
    B.box([19.5, 0, 2], [20, top, 6.5], cw, 'wood');
    B.box([19.5, 9, -14], [20, top, -9], cw, 'wood');
    B.box([19.5, 9, -3], [20, top, 2], cw, 'wood');
    B.box([20, 0, -18.5], [32, top, -18], cw, 'wood');
    B.box([20, 0, 6], [32, top, 6.5], cw, 'wood');
    B.box([19.5, top, -18.5], [32, top + 0.5, 6.5], cw, 'wood');
    // outside face wallpaper + door trims
    B.box([19.3, 0, -18.5], [19.5, top, -14], M.wallpaper, null, { tile: 1 / 12 });
    B.box([19.3, 0, -9], [19.5, top, -3], M.wallpaper, null, { tile: 1 / 12 });
    B.box([19.3, 0, 2], [19.5, top, 6.5], M.wallpaper, null, { tile: 1 / 12 });
    B.box([19.3, 9, -14], [19.5, top, -9], M.wallpaper, null, { tile: 1 / 12 });
    B.box([19.3, 9, -3], [19.5, top, 2], M.wallpaper, null, { tile: 1 / 12 });
    for (const [z0, z1] of [[-14, -9], [-3, 2]] as const) {
      B.box([19.1, 0, z0 - 0.4], [19.6, 9.4, z0], M.trim, null);
      B.box([19.1, 0, z1], [19.6, 9.4, z1 + 0.4], M.trim, null);
      B.box([19.1, 9, z0 - 0.4], [19.6, 9.4, z1 + 0.4], M.trim, null);
    }
    // closet floor rug
    B.box([20, 0, -18], [32, 0.06, 6], M.fabricB, 'fabric', { cast: false });
    // shoebox maze walls
    const shoe = (x0: number, z0: number, x1: number, z1: number, h: number) => {
      // stack boxes of ~1.4 tall
      const layers = Math.round(h / 1.4);
      const lh = h / layers;
      for (let l = 0; l < layers; l++) {
        const inset = (l % 2) * 0.1;
        const mat = l % 2 ? M.cardboardShoes : M.cardboard;
        B.box([x0 + inset, l * lh, z0 + inset], [x1 - inset, (l + 1) * lh - 0.02, z1 - inset], mat, null, { round: 0.05 });
      }
      phys.box(v3((x0 + x1) / 2, h / 2, (z0 + z1) / 2), v3((x1 - x0) / 2, h / 2, (z1 - z0) / 2), 'cardboard');
    };
    shoe(23, -18, 24.5, -11, 3.2);
    shoe(24.5, -12.5, 30, -11, 3.2);
    shoe(27, -7.5, 32, -6, 3.2);
    shoe(22.5, -7.5, 24, -1.5, 3.2);
    shoe(24, -1.5, 28.5, 0, 2.6);
    shoe(26, 2.5, 32, 4, 1.25);
    // storage bins (translucent plastic look but solid)
    for (const [x0, z0, x1, z1, c] of [[29.6, -17.6, 32, -13.6, '#7fc8f8'], [20.4, 3, 22.6, 5.8, '#ffafcc']] as const) {
      B.box([x0, 0, z0], [x1, 2.6, z1], plastic(c, { rough: 0.15, clearcoat: 1 }), 'plastic', { round: 0.2 });
      B.box([x0 - 0.1, 2.6, z0 - 0.1], [x1 + 0.1, 2.9, z1 + 0.1], plastic('#ffffff', { rough: 0.3 }), 'plastic', { round: 0.1 });
    }
    // clothes rod and hanging clothes
    B.obox([31, 15.6, -6], [0.25, 0.25, 24], new THREE.Euler(), metal('#d0d0d0', 0.2), null);
    const clothesMats = [M.fabricA, M.fabricB, M.fabricC, M.fabricD];
    for (let i = 0; i < 9; i++) {
      const z = -16.5 + i * 2.6;
      const long = i === 2 || i === 5 || i === 7;
      const bottom = long ? 1.6 : 7 + rnd() * 2;
      const mat = clothesMats[i % 4];
      B.geo(new THREE.TorusGeometry(0.5, 0.06, 6, 12, Math.PI), metal('#bbbbbb'), [31, 15.4, z], new THREE.Euler(0, Math.PI / 2, 0));
      B.box([29.4, bottom, z - 0.35], [32, 15.2, z + 0.35], mat, long ? 'fabric' : null, { round: 0.3 });
    }
    // night light + dim cool light
    B.geo(new THREE.OctahedronGeometry(0.6), glow('#b8a6ff', 3), [31.6, 4, -9]);
    const nl = new THREE.PointLight('#8f7bff', 10, 22, 1.6);
    nl.position.set(27, 5, -6);
    root.add(nl);
    pointLights.push(nl);
    const nl2 = new THREE.PointLight('#4f9dff', 6, 18, 1.6);
    nl2.position.set(25, 4, -15);
    root.add(nl2);
    pointLights.push(nl2);
  }

  // ---------------------------------------------------------------- TOY GARAGE (SE)
  {
    // oval race track (flat)
    const track = new THREE.Mesh(new THREE.RingGeometry(3.2, 5.2, 64, 1), plastic('#4a4e69', { rough: 0.6, clearcoat: 0.2 }));
    track.rotation.x = -Math.PI / 2;
    track.scale.set(2.0, 1, 1);
    track.position.set(17, 0.03, 18.5);
    track.receiveShadow = true;
    root.add(track);
    const dash = new THREE.Mesh(new THREE.RingGeometry(4.12, 4.28, 64, 1), plastic('#ffffff', { rough: 0.6 }));
    dash.rotation.x = -Math.PI / 2;
    dash.scale.set(2.0, 1, 1);
    dash.position.set(17, 0.04, 18.5);
    root.add(dash);
    // parking deck
    const deckMat = plastic('#9aa5b1', { rough: 0.5 });
    B.box([22, 3.6, 24], [32, 4, 36], deckMat, 'plastic', { round: 0.08 });
    for (const [x, z] of [[22.5, 24.5], [22.5, 35.5], [27, 24.5], [31.5, 24.5], [27, 35.5], [22.5, 27.6], [22.5, 32.4]] as const) {
      B.box([x - 0.4, 0, z - 0.4], [x + 0.4, 3.6, z + 0.4], plastic('#f4a261'), 'plastic', { round: 0.1 });
    }
    B.box([22.4, 4, 24], [32, 5, 24.4], plastic('#e76f51'), 'plastic');
    B.box([22, 4, 24], [22.4, 5, 28], plastic('#e76f51'), 'plastic');
    B.box([22, 4, 32], [22.4, 5, 36], plastic('#e76f51'), 'plastic');
    // helipad mark
    const hp = new THREE.Mesh(new THREE.CircleGeometry(2.6, 32), plastic('#ffd166', { rough: 0.5 }));
    hp.rotation.x = -Math.PI / 2;
    hp.position.set(28, 4.02, 31);
    root.add(hp);
    // ramp up to deck
    B.slab([14, 0, 30], [22, 4, 30], 4, 0.3, plastic('#6c757d', { rough: 0.6 }), 'plastic');
    for (let i = 0; i < 6; i++) {
      const t = (i + 0.5) / 6;
      B.obox([14 + 8 * t, 4 * t + 0.03, 30], [0.4, 0.04, 3.6], new THREE.Euler(0, 0, Math.atan2(4, 8)), plastic('#ffd166'), null);
    }
    // jump kicker
    B.wedge([24, 0, 16], Math.PI / 2, 4, 1.6, 3.5, plastic('#fb8500'), 'plastic');
    // parked cars (cover)
    addCar(B, [9.5, 0, 33], 0, '#e63946');
    addCar(B, [16.5, 0, 34.5], 0.1, '#3a86ff');
    addCar(B, [26.5, 0, 30], Math.PI / 2, '#06d6a0');
    addCar(B, [29.5, 4, 33.5], Math.PI / 2 + 0.2, '#ffbe0b');
    addCar(B, [8, 0, 13.5], -0.2, '#8338ec');
    // cones + tires + pump
    for (const [x, z] of [[12, 24], [13.4, 25.6], [20.5, 13]] as const) {
      B.cyl([x, 0, z], 0.6, 1.3, plastic('#fb5607'), 'plastic', 16, 0.12);
      B.box([x - 0.75, 0, z - 0.75], [x + 0.75, 0.15, z + 0.75], plastic('#fb5607'), null);
    }
    for (let i = 0; i < 3; i++) {
      const g = new THREE.TorusGeometry(1.0, 0.42, 12, 24);
      B.geo(g, rubber('#222222'), [7.6, 0.42 + i * 0.8, 18], new THREE.Euler(Math.PI / 2, 0, 0));
    }
    phys.cylinder(v3(7.6, 1.2, 18), 1.2, 1.4, 'plastic');
    B.box([6.5, 0, 22], [8.3, 2.8, 24], plastic('#ef233c'), 'plastic', { round: 0.2 });
    B.box([6.7, 1.6, 21.9], [8.1, 2.4, 22], glow('#fff3b0', 1.2), null);
    // garage sign
    addSign(root, 'TOY GARAGE', [27, 7.2, 24.3], '#e76f51');
  }

  // ---------------------------------------------------------------- DINOSAUR KINGDOM (SW)
  {
    B.box([-32, 0, 12], [-6, 0.12, 36], M.fabricD, 'fabric', { cast: false });
    // volcano
    {
      const pts: THREE.Vector2[] = [];
      for (let i = 0; i <= 12; i++) {
        const t = i / 12;
        const r = 6.6 - t * 4.6 + Math.sin(t * 9) * 0.25;
        pts.push(new THREE.Vector2(r, t * 8));
      }
      pts.push(new THREE.Vector2(1.6, 7.6), new THREE.Vector2(1.2, 6.6));
      const lathe = new THREE.LatheGeometry(pts, 40);
      const vMat = new THREE.MeshStandardMaterial({ color: '#7a4b35', roughness: 0.85, flatShading: true });
      B.geo(lathe, vMat, [-23, 0, 29]);
      const lava = new THREE.Mesh(new THREE.CircleGeometry(1.6, 24), glow('#ff6b1a', 3.5));
      lava.rotation.x = -Math.PI / 2;
      lava.position.set(-23, 7.0, 29);
      root.add(lava);
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2 + 0.3;
        const g = new THREE.CapsuleGeometry(0.28, 3 + (i % 2), 4, 8);
        const r0 = 2.2 + i * 0.25;
        B.geo(g, glow('#ff7b00', 1.6), [-23 + Math.cos(a) * r0 * 1.1, 6.1 - i * 0.2, 29 + Math.sin(a) * r0 * 1.1], new THREE.Euler(Math.sin(a) * 0.6, 0, -Math.cos(a) * 0.6));
      }
      phys.cone(v3(-23, 4, 29), 4, 6.6, 'plastic');
      const vl = new THREE.PointLight('#ff7a1a', 14, 20, 1.8);
      vl.position.set(-23, 9.5, 29);
      root.add(vl);
      pointLights.push(vl);
      animated.push({
        update: (_dt, t) => {
          vl.intensity = 12 + Math.sin(t * 2.3) * 3 + Math.sin(t * 7.1) * 1.5;
          (lava.material as THREE.MeshStandardMaterial).emissiveIntensity = 3 + Math.sin(t * 3) * 0.6;
        },
      });
    }
    addTRex(B, phys, [-15, 0, 18]);
    addTriceratops(B, phys, [-27, 0, 15]);
    addBrachio(B, phys);
    addStego(B, phys, [-10, 0, 23.5]);
    const rockMat = M.rock;
    for (const [x, z, r] of [[-19, 23.5, 1.5], [-8.6, 14.2, 1.3], [-31, 21, 1.5], [-21, 13.6, 1.2], [-30.6, 33.6, 1.8]] as const) {
      const g = new THREE.DodecahedronGeometry(r, 1);
      B.geo(g, rockMat, [x, r * 0.55, z], new THREE.Euler(rnd(), rnd(), rnd()), [1, 0.8, 1.1]);
      phys.ball(v3(x, r * 0.45, z), r * 0.92, 'plastic');
    }
    for (const [x, z, s] of [[-30.4, 13.2, 1], [-11.5, 34.6, 1.2], [-17.5, 35, 0.9], [-7.5, 19.5, 0.9], [-31, 26.5, 1.1]] as const) {
      addPalm(B, phys, [x, 0, z], s, rnd);
    }
  }

  // ---------------------------------------------------------------- BRICK DISTRICT (W-center)
  {
    const base = '#3a9d47';
    B.box([-31.5, 0, -7.5], [-13.5, 0.3, 9.5], plastic(base, { rough: 0.4 }), 'plastic');
    B.addStuds(-31.5, -13.5, -7.5, 9.5, 0.3, base, 1.6);
    const C = BRICK_COLORS;
    // tower
    for (let i = 0; i < 7; i++) B.brick([-31.5, 0.3 + i, -7.5], [-27.5, 1.3 + i, -3.5], C[i % C.length], null, i === 6);
    phys.box(v3(-29.5, 3.8, -5.5), v3(2, 3.5, 2), 'plastic');
    // tower ramp (slope bricks)
    B.wedge([-30, 0.3, 6], Math.PI, 9.5, 7, 3, plastic('#f2c12e', { rough: 0.35 }), 'plastic');
    // castle walls with arches
    const wall = (min: V3, max: V3, col: string) => B.brick(min, max, col, 'plastic', true);
    wall([-27.5, 0.3, -5], [-23, 4.3, -3.8], '#bfc5cc');
    wall([-20.5, 0.3, -5], [-16, 4.3, -3.8], '#bfc5cc');
    wall([-23, 2.8, -5], [-20.5, 4.3, -3.8], '#d6342c');
    wall([-17.2, 0.3, -3.8], [-16, 4.3, -0.5], '#bfc5cc');
    wall([-17.2, 0.3, 2], [-16, 4.3, 6], '#bfc5cc');
    wall([-17.2, 2.8, -0.5], [-16, 4.3, 2], '#1f6fd1');
    wall([-24, 0.3, 6], [-17.2, 2.5, 7.2], '#bfc5cc');
    // battlements
    for (let x = -27.1; x < -16.2; x += 1.6) B.brick([x, 4.3, -5], [x + 0.8, 5.1, -3.8], '#9aa1a9', 'plastic', true);
    for (let z = -3.4; z < 5.8; z += 1.6) B.brick([-17.2, 4.3, z], [-16, 5.1, z + 0.8], '#9aa1a9', 'plastic', true);
    // keep with a step
    B.brick([-25, 0.3, 0], [-21, 2.3, 3], '#f08c1f');
    B.brick([-21, 0.3, 0.4], [-19.8, 1.3, 2.6], '#f2c12e');
    // brick columns + cover bricks
    for (let i = 0; i < 9; i++) B.brick([-15, i, 7], [-13, i + 1, 9], C[(i + 2) % C.length], null, i === 8);
    phys.box(v3(-14, 4.5, 8), v3(1, 4.5, 1), 'plastic');
    for (let i = 0; i < 6; i++) B.brick([-15, 0.3 + i, -7.5], [-13, 1.3 + i, -5.5], C[(i + 4) % C.length], null, i === 5);
    phys.box(v3(-14, 3.3, -6.5), v3(1, 3, 1), 'plastic');
    B.brick([-14.5, 0, 1], [-12.6, 1.4, 5], '#d6342c');
    B.brick([-27, 0.3, 8], [-25, 1.7, 9.6], '#1f6fd1');
    B.brick([-12.5, 0, -10], [-10.5, 1.4, -6], '#f2c12e');
    addSign(root, 'BRICK DISTRICT', [-22, 6.6, -5.2], '#d6342c');
  }

  // ---------------------------------------------------------------- loose bricks (dynamic)
  const brickSpots: THREE.Vector3[] = [];
  {
    const r = seeded(7);
    const areas: [number, number, number, number][] = [[-27, -16.5, -3.4, 5.6], [-15.5, -11, -4, 6], [-31, -27.5, 7, 9]];
    for (let i = 0; i < 26; i++) {
      const a = areas[i % areas.length];
      brickSpots.push(v3(a[0] + r() * (a[1] - a[0]), 1 + (i % 3) * 0.7, a[2] + r() * (a[3] - a[2])));
    }
  }

  B.buildStuds(root);
  batch.build(root);
  phys.refreshQueries();
  const looseBricks = new LooseBricks(phys, brickSpots, root);
  animated.push(looseBricks);
  if (screenTex) {
    const st = screenTex;
    let acc = 0;
    animated.push({ update: (dt, t) => { acc += dt; if (acc > 0.1) { acc = 0; st.update(t); } } });
  }

  // ---------------------------------------------------------------- LIGHTING
  const sunDir = v3(0.28, -0.55, 1).normalize();
  const sun = new THREE.DirectionalLight('#ffdcae', 6.2);
  const target = v3(2, 0, -4);
  sun.position.copy(target).addScaledVector(sunDir, -90);
  sun.target.position.copy(target);
  sun.castShadow = true;
  const sc = sun.shadow.camera;
  sc.left = -60; sc.right = 60; sc.top = 60; sc.bottom = -60; sc.near = 20; sc.far = 190;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.04;
  sun.shadow.radius = 3;
  root.add(sun, sun.target);
  const hemi = new THREE.HemisphereLight('#fff1dc', '#7a5a3e', 0.62);
  root.add(hemi);
  // soft bounce light where the sun patch lands
  const bounce = new THREE.PointLight('#ffcf9e', 22, 40, 1.4);
  bounce.position.set(4, 4, -2);
  root.add(bounce);
  pointLights.push(bounce);
  const fill = new THREE.PointLight('#c9dcff', 10, 60, 1.2);
  fill.position.set(0, 24, 20);
  root.add(fill);
  pointLights.push(fill);

  // ---------------------------------------------------------------- GAMEPLAY DATA
  const zones: Zone[] = [
    { name: 'Closet Maze', min: [19.5, -18.5], max: [32, 6.5], ambience: 'closet' },
    { name: 'Desk Outpost', min: [0, -36], max: [32, -19], ambience: 'desk' },
    { name: 'Bed Fortress', min: [-32, -36], max: [0, -11], ambience: 'bed' },
    { name: 'Toy Garage', min: [5, 11], max: [32, 36], ambience: 'garage' },
    { name: 'Dinosaur Kingdom', min: [-32, 11], max: [-5, 36], ambience: 'dino' },
    { name: 'Brick District', min: [-32, -11], max: [-10, 11], ambience: 'brick' },
    { name: 'Play Rug', min: [-32, -36], max: [32, 36], ambience: 'rug' },
  ];
  const ground = (x: number, z: number, fromY: number) => {
    const d = phys.rayDist(v3(x, fromY, z), v3(0, -1, 0), fromY + 2, true);
    return v3(x, d === Infinity ? 0 : fromY - d, z);
  };
  const pickupSpots: ArenaInfo['pickupSpots'] = [
    { kind: 'health', pos: ground(-6.5, -15, 9) },
    { kind: 'health', pos: ground(25.5, -9.2, 2) },
    { kind: 'health', pos: ground(12, 21.5, 2) },
    { kind: 'health', pos: ground(-30.4, 28.6, 2) },
    { kind: 'health', pos: ground(-1.5, -5, 2) },
    { kind: 'health', pos: ground(20.5, -27.5, 12) },
    { kind: 'shield', pos: ground(-29.5, -5.5, 12) },
    { kind: 'shield', pos: ground(29.6, -3.2, 2) },
    { kind: 'turbo', pos: ground(17, 18.5, 2) },
    { kind: 'infinite', pos: ground(-25.5, -20.5, 2) },
    { kind: 'power', pos: ground(2, 1, 8) },
    // up on the shelves
    { kind: 'health', pos: ground(24, ROOM.z0 + 2.85, 23) },
    { kind: 'health', pos: ground(-18, ROOM.z1 - 2.85, 23) },
    { kind: 'shield', pos: ground(ROOM.x1 - 2.85, 22, 23) },
  ];
  const weaponSpots: ArenaInfo['weaponSpots'] = [
    { weapon: 'foamFury', pos: ground(-5.5, -8.5, 2) },
    { weapon: 'brickbreaker', pos: ground(-20.2, 4.6, 3) },
    { weapon: 'bubbleBlaster', pos: ground(26.5, -15.5, 2) },
    { weapon: 'thunderspring', pos: ground(19, -29, 12) },
    { weapon: 'rapidRascal', pos: ground(26.5, 27.5, 6) },
    { weapon: 'crayonCannon', pos: ground(-12, 30, 9) },
    { weapon: 'starlightZapper', pos: ground(-24.5, -22, 9) },
    { weapon: 'plasti9', pos: ground(6, 9, 2) },
    // the two shelf-only weapons
    { weapon: 'jackBlaster', pos: ground(-15, ROOM.z0 + 2.85, 23) },
    { weapon: 'jackBlaster', pos: ground(17, ROOM.z1 - 2.85, 23) },
    { weapon: 'plungerBow', pos: ground(ROOM.x0 + 2.85, -2, 23) },
    { weapon: 'plungerBow', pos: ground(ROOM.x1 - 2.85, -22, 23) },
  ];

  return {
    root, zones, pickupSpots, weaponSpots, animated, sun, hemi, sunDir, pointLights, looseBricks,
    bounds: { min: v3(ROOM.x0, 0, ROOM.z0), max: v3(ROOM.x1, ROOM.h, ROOM.z1) },
    window: WIN,
  };
}

// ======================================================================== prop helpers

function stripeBallMat(a = '#ef476f', b = '#ffd166') {
  const c = document.createElement('canvas');
  c.width = 256;
  c.height = 128;
  const ctx = c.getContext('2d')!;
  const cols = [a, '#ffffff', b, '#118ab2'];
  for (let i = 0; i < 8; i++) {
    ctx.fillStyle = cols[i % 4];
    ctx.fillRect((i * 256) / 8, 0, 256 / 8 + 1, 128);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return new THREE.MeshPhysicalMaterial({ map: t, roughness: 0.3, clearcoat: 0.8 });
}

const letterMatCache = new Map<string, THREE.Material>();
function addLetterBlock(B: Builder, center: V3, size: number, color: string, letter: string, yaw: number) {
  const key = color + letter;
  let mat = letterMatCache.get(key);
  if (!mat) {
    const c = document.createElement('canvas');
    c.width = c.height = 128;
    const ctx = c.getContext('2d')!;
    ctx.fillStyle = '#e8cfa5';
    ctx.fillRect(0, 0, 128, 128);
    ctx.fillStyle = color;
    ctx.fillRect(8, 8, 112, 112);
    ctx.fillStyle = '#fffaf0';
    ctx.font = 'bold 84px "Luckiest Guy", Impact, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(letter, 64, 70);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    mat = new THREE.MeshStandardMaterial({ map: t, roughness: 0.55 });
    letterMatCache.set(key, mat);
  }
  B.geo(new RoundedBoxGeometry(size, size, size, 2, 0.08), mat, center, new THREE.Euler(0, yaw, 0));
}

function addCar(B: Builder, base: V3, yaw: number, color: string) {
  const body = plastic(color, { rough: 0.25, clearcoat: 1 });
  const rot = new THREE.Euler(0, yaw, 0);
  const q = new THREE.Quaternion().setFromEuler(rot);
  const at = (x: number, y: number, z: number): V3 => {
    const p = v3(x, y, z).applyQuaternion(q);
    return [base[0] + p.x, base[1] + p.y, base[2] + p.z];
  };
  B.geo(new RoundedBoxGeometry(1.9, 0.8, 3.6, 3, 0.3), body, at(0, 0.75, 0), rot);
  B.geo(new RoundedBoxGeometry(1.6, 0.7, 1.9, 3, 0.3), body, at(0, 1.4, -0.2), rot);
  B.geo(new RoundedBoxGeometry(1.5, 0.5, 1.7, 2, 0.2), new THREE.MeshPhysicalMaterial({ color: '#9fd8ff', roughness: 0.05, clearcoat: 1, metalness: 0.2 }), at(0, 1.45, -0.2), rot, [1.08, 1, 1.08]);
  for (const [x, z] of [[-0.95, 1.1], [0.95, 1.1], [-0.95, -1.15], [0.95, -1.15]] as const) {
    B.geo(new THREE.CylinderGeometry(0.45, 0.45, 0.35, 16), rubber('#1d1d1d'), at(x, 0.45, z), new THREE.Euler(0, yaw, Math.PI / 2));
    B.geo(new THREE.CylinderGeometry(0.22, 0.22, 0.37, 10), metal('#dddddd'), at(x, 0.45, z), new THREE.Euler(0, yaw, Math.PI / 2));
  }
  B.geo(new THREE.SphereGeometry(0.16, 8, 6), glow('#fff6c2', 2), at(-0.6, 0.85, 1.8), rot);
  B.geo(new THREE.SphereGeometry(0.16, 8, 6), glow('#fff6c2', 2), at(0.6, 0.85, 1.8), rot);
  B.phys.box(v3(...at(0, 0.85, 0)), v3(0.95, 0.85, 1.8), 'plastic', rot);
}

function addSign(root: THREE.Object3D, text: string, pos: V3, color: string) {
  const c = document.createElement('canvas');
  c.width = 512;
  c.height = 128;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.roundRect(4, 4, 504, 120, 30);
  ctx.fill();
  ctx.strokeStyle = '#ffffff';
  ctx.lineWidth = 8;
  ctx.stroke();
  ctx.fillStyle = '#fffaf0';
  ctx.font = '64px "Luckiest Guy", Impact, sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(text, 256, 70);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  const m = new THREE.Mesh(new THREE.PlaneGeometry(6, 1.5), new THREE.MeshStandardMaterial({ map: t, roughness: 0.5, side: THREE.DoubleSide }));
  m.position.set(...pos);
  m.castShadow = true;
  root.add(m);
}

function addDrawings(root: THREE.Object3D) {
  const draw = (fn: (ctx: CanvasRenderingContext2D) => void) => {
    const c = document.createElement('canvas');
    c.width = 256;
    c.height = 200;
    const ctx = c.getContext('2d')!;
    ctx.fillStyle = '#fffdf6';
    ctx.fillRect(0, 0, 256, 200);
    ctx.lineWidth = 6;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    fn(ctx);
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    return new THREE.MeshStandardMaterial({ map: t, roughness: 0.9 });
  };
  const sunHouse = draw((ctx) => {
    ctx.strokeStyle = '#ffb703';
    ctx.beginPath(); ctx.arc(205, 45, 26, 0, 7); ctx.stroke();
    for (let i = 0; i < 8; i++) { const a = i * 0.785; ctx.beginPath(); ctx.moveTo(205 + Math.cos(a) * 34, 45 + Math.sin(a) * 34); ctx.lineTo(205 + Math.cos(a) * 48, 45 + Math.sin(a) * 48); ctx.stroke(); }
    ctx.strokeStyle = '#e63946'; ctx.strokeRect(50, 100, 90, 70);
    ctx.beginPath(); ctx.moveTo(40, 100); ctx.lineTo(95, 55); ctx.lineTo(150, 100); ctx.stroke();
    ctx.strokeStyle = '#2a9d8f'; ctx.beginPath(); ctx.moveTo(0, 185); ctx.lineTo(256, 185); ctx.stroke();
  });
  const dino = draw((ctx) => {
    ctx.strokeStyle = '#2a9d8f';
    ctx.beginPath(); ctx.ellipse(120, 120, 60, 35, 0, 0, 7); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(170, 105); ctx.quadraticCurveTo(200, 40, 220, 50); ctx.stroke();
    ctx.beginPath(); ctx.arc(222, 48, 10, 0, 7); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(60, 120); ctx.quadraticCurveTo(20, 130, 10, 100); ctx.stroke();
    for (const x of [90, 110, 140, 160]) { ctx.beginPath(); ctx.moveTo(x, 150); ctx.lineTo(x, 185); ctx.stroke(); }
    ctx.fillStyle = '#e76f51'; ctx.font = 'bold 26px Comic Sans MS, sans-serif'; ctx.fillText('REX!', 20, 40);
  });
  const robot = draw((ctx) => {
    ctx.strokeStyle = '#457b9d'; ctx.strokeRect(90, 70, 80, 90); ctx.strokeRect(100, 25, 60, 45);
    ctx.fillStyle = '#e63946'; ctx.fillRect(112, 38, 10, 10); ctx.fillRect(138, 38, 10, 10);
    ctx.beginPath(); ctx.moveTo(130, 25); ctx.lineTo(130, 8); ctx.stroke();
    ctx.beginPath(); ctx.moveTo(90, 90); ctx.lineTo(55, 120); ctx.moveTo(170, 90); ctx.lineTo(205, 120); ctx.stroke();
  });
  const frames: [THREE.Material, V3, number][] = [
    [sunHouse, [-14, 13, 35.7], Math.PI],
    [dino, [16, 12, 35.7], Math.PI],
    [robot, [-31.7, 14, 2], Math.PI / 2],
  ];
  for (const [mat, p, ry] of frames) {
    const m = new THREE.Mesh(new THREE.PlaneGeometry(6.4, 5), mat);
    m.position.set(...p);
    m.rotation.y = ry;
    root.add(m);
    const tape = new THREE.Mesh(new THREE.PlaneGeometry(1.2, 0.4), new THREE.MeshStandardMaterial({ color: '#f1e3b5', roughness: 0.8, transparent: true, opacity: 0.85 }));
    tape.position.copy(m.position).add(v3(0, 2.4, 0).add(v3(0, 0, 0)));
    tape.position.x += ry === Math.PI / 2 ? 0.02 : 0;
    tape.position.z += ry === Math.PI ? -0.02 : 0;
    tape.rotation.y = ry;
    tape.rotation.z = 0.15;
    root.add(tape);
  }
}

function addTRex(B: Builder, phys: Physics, b: V3) {
  const green = plastic('#4caf50', { rough: 0.35 });
  const belly = plastic('#c5e1a5', { rough: 0.4 });
  const [x, , z] = b;
  // legs
  for (const dz of [-1.2, 1.2]) {
    B.geo(new THREE.CapsuleGeometry(0.9, 2.2, 6, 16), green, [x - 0.8, 2.2, z + dz]);
    B.geo(new RoundedBoxGeometry(2.2, 0.6, 1.4, 2, 0.25), green, [x - 0.4, 0.3, z + dz]);
    phys.cylinder(v3(x - 0.8, 1.9, z + dz), 1.9, 0.85, 'plastic');
  }
  // body
  B.geo(new THREE.CapsuleGeometry(1.8, 4, 8, 20), green, [x, 5, z], new THREE.Euler(0, 0, Math.PI / 2 + 0.35));
  B.geo(new THREE.CapsuleGeometry(1.3, 3, 8, 16), belly, [x + 0.4, 4.6, z], new THREE.Euler(0, 0, Math.PI / 2 + 0.35), [1, 1, 1.1]);
  phys.box(v3(x, 5, z), v3(3.2, 1.6, 1.6), 'plastic', new THREE.Euler(0, 0, 0.35));
  // tail
  B.geo(new THREE.ConeGeometry(1.4, 7, 16), green, [x - 5.4, 3.2, z], new THREE.Euler(0, 0, Math.PI / 2 + 0.25));
  phys.box(v3(x - 4.6, 3.4, z), v3(2.4, 0.9, 0.9), 'plastic', new THREE.Euler(0, 0, 0.25));
  // neck + head
  B.geo(new THREE.CapsuleGeometry(1.1, 1.5, 6, 16), green, [x + 2.6, 7.2, z], new THREE.Euler(0, 0, -0.6));
  B.geo(new RoundedBoxGeometry(3.6, 1.8, 2.2, 3, 0.6), green, [x + 4, 8.2, z]);
  B.geo(new RoundedBoxGeometry(3.0, 0.7, 1.9, 2, 0.3), green, [x + 4.1, 7.1, z], new THREE.Euler(0, 0, -0.15));
  phys.box(v3(x + 4, 7.8, z), v3(1.8, 1.2, 1.1), 'plastic');
  // teeth, eyes, arms
  for (let i = 0; i < 6; i++) {
    B.geo(new THREE.ConeGeometry(0.12, 0.35, 6), plastic('#ffffff'), [x + 3.1 + i * 0.45, 7.45, z + 0.95], new THREE.Euler(Math.PI, 0, 0));
    B.geo(new THREE.ConeGeometry(0.12, 0.35, 6), plastic('#ffffff'), [x + 3.1 + i * 0.45, 7.45, z - 0.95], new THREE.Euler(Math.PI, 0, 0));
  }
  for (const dz of [-0.95, 0.95]) {
    B.geo(new THREE.SphereGeometry(0.38, 16, 12), plastic('#ffffff'), [x + 4.4, 8.75, z + dz]);
    B.geo(new THREE.SphereGeometry(0.2, 12, 8), plastic('#111111'), [x + 4.55, 8.8, z + dz * 1.25]);
    B.geo(new THREE.CapsuleGeometry(0.25, 0.9, 4, 8), green, [x + 2.2, 5.2, z + dz * 1.5], new THREE.Euler(0, 0, -1.1));
  }
}

function addTriceratops(B: Builder, phys: Physics, b: V3) {
  const col = plastic('#5e60ce', { rough: 0.35 });
  const frill = plastic('#ffafcc', { rough: 0.4 });
  const [x, , z] = b;
  B.geo(new THREE.CapsuleGeometry(1.3, 3.2, 8, 16), col, [x, 2, z], new THREE.Euler(0, 0, Math.PI / 2));
  for (const [dx, dz] of [[-1.6, -0.9], [-1.6, 0.9], [1.4, -0.9], [1.4, 0.9]] as const) B.geo(new THREE.CylinderGeometry(0.45, 0.5, 1.4, 10), col, [x + dx, 0.7, z + dz]);
  B.geo(new RoundedBoxGeometry(2, 1.4, 1.6, 2, 0.5), col, [x + 3, 2.1, z]);
  B.geo(new THREE.CylinderGeometry(1.8, 1.8, 0.3, 24, 1, false, 0, Math.PI), frill, [x + 2.3, 2.7, z], new THREE.Euler(Math.PI / 2, 0, Math.PI / 2 + 0.3));
  for (const dz of [-0.5, 0.5]) B.geo(new THREE.ConeGeometry(0.18, 1.6, 8), plastic('#fffbe6'), [x + 3.8, 3.1, z + dz], new THREE.Euler(0, 0, -1.2));
  B.geo(new THREE.ConeGeometry(0.15, 0.7, 8), plastic('#fffbe6'), [x + 4.1, 2.3, z], new THREE.Euler(0, 0, -1.3));
  phys.box(v3(x + 0.6, 1.6, z), v3(3.3, 1.6, 1.4), 'plastic');
}

function addStego(B: Builder, phys: Physics, b: V3) {
  const col = plastic('#f4a261', { rough: 0.35 });
  const plate = plastic('#e76f51', { rough: 0.35 });
  const [x, , z] = b;
  B.geo(new THREE.CapsuleGeometry(1.0, 2.6, 8, 16), col, [x, 1.5, z], new THREE.Euler(0, 0, Math.PI / 2));
  for (let i = 0; i < 5; i++) B.geo(new THREE.ConeGeometry(0.55, 1.2, 4), plate, [x - 1.6 + i * 0.8, 2.75 - Math.abs(i - 2) * 0.15, z], new THREE.Euler(0, Math.PI / 4, 0));
  for (const [dx, dz] of [[-1.2, -0.7], [-1.2, 0.7], [1.2, -0.7], [1.2, 0.7]] as const) B.geo(new THREE.CylinderGeometry(0.35, 0.4, 1, 10), col, [x + dx, 0.5, z + dz]);
  B.geo(new THREE.SphereGeometry(0.6, 16, 12), col, [x + 2.6, 1.3, z]);
  phys.box(v3(x + 0.3, 1.3, z), v3(2.6, 1.3, 1.1), 'plastic');
}

function addBrachio(B: Builder, phys: Physics) {
  const col = plastic('#48cae4', { rough: 0.35 });
  const spots = plastic('#0096c7', { rough: 0.35 });
  // body platform (walkable back)
  B.geo(new RoundedBoxGeometry(6.6, 3.2, 3.6, 3, 1.2), col, [-12, 4.4, 30]);
  phys.box(v3(-12, 4.5, 30), v3(3.1, 1.5, 1.6), 'plastic');
  for (const [x, z] of [[-14.2, 28.9], [-14.2, 31.1], [-9.8, 28.9], [-9.8, 31.1]] as const) {
    B.geo(new THREE.CylinderGeometry(0.6, 0.7, 3.2, 12), col, [x, 1.6, z]);
    phys.cylinder(v3(x, 1.5, z), 1.5, 0.65, 'plastic');
  }
  for (let i = 0; i < 6; i++) B.geo(new THREE.SphereGeometry(0.35, 10, 8), spots, [-14 + i * 0.8, 5.9, 29.3 + (i % 2) * 1.2], undefined, [1, 0.3, 1]);
  // neck + head (not walkable)
  const neckFrom = v3(-15, 5.5, 30), neckTo = v3(-19.5, 13, 30);
  const mid = neckFrom.clone().add(neckTo).multiplyScalar(0.5);
  const len = neckFrom.distanceTo(neckTo);
  B.geo(new THREE.CapsuleGeometry(0.85, len, 6, 14), col, [mid.x, mid.y, mid.z], new THREE.Euler(0, 0, Math.atan2(neckTo.x - neckFrom.x, neckTo.y - neckFrom.y) * -1));
  phys.box(mid, v3(0.8, len / 2, 0.8), 'plastic', new THREE.Euler(0, 0, -Math.atan2(neckTo.x - neckFrom.x, neckTo.y - neckFrom.y)));
  B.geo(new RoundedBoxGeometry(2.4, 1.2, 1.4, 2, 0.5), col, [-20.2, 13.4, 30]);
  for (const dz of [-0.6, 0.6]) {
    B.geo(new THREE.SphereGeometry(0.25, 12, 8), plastic('#ffffff'), [-20.4, 13.75, 30 + dz]);
    B.geo(new THREE.SphereGeometry(0.13, 8, 6), plastic('#111111'), [-20.55, 13.8, 30 + dz * 1.2]);
  }
  // tail = walkable slab from the floor up to its back
  B.slab([-0.8, 0, 30], [-9, 6, 30], 2.8, 0.5, col, 'plastic', 0.2);
}

function addPalm(B: Builder, phys: Physics, base: V3, s: number, rnd: () => number) {
  const trunk = plastic('#a0522d', { rough: 0.6, clearcoat: 0.2 });
  const leaf = plastic('#2dc653', { rough: 0.4 });
  let y = base[1];
  for (let i = 0; i < 6; i++) {
    B.geo(new THREE.CylinderGeometry(0.42 * s, 0.55 * s, 1.2 * s, 10), trunk, [base[0] + i * 0.08, y + 0.6 * s, base[2]], new THREE.Euler(0, 0, -0.05));
    y += 1.15 * s;
  }
  phys.cylinder(v3(base[0], y / 2, base[2]), y / 2, 0.5 * s, 'wood');
  for (let i = 0; i < 6; i++) {
    const a = (i / 6) * Math.PI * 2 + rnd();
    const g = new THREE.ConeGeometry(0.7 * s, 4.2 * s, 4);
    g.scale(1, 1, 0.25);
    g.translate(0, 2.1 * s, 0);
    const dir = v3(Math.cos(a) * 0.95, 0.3, Math.sin(a) * 0.95).normalize();
    const e = new THREE.Euler().setFromQuaternion(new THREE.Quaternion().setFromUnitVectors(v3(0, 1, 0), dir));
    B.geo(g, leaf, [base[0] + 0.48, y, base[2]], e);
  }
  for (let i = 0; i < 3; i++) B.geo(new THREE.SphereGeometry(0.32 * s, 10, 8), plastic('#8b5a2b'), [base[0] + 0.48 + Math.cos(i * 2) * 0.4, y - 0.3, base[2] + Math.sin(i * 2) * 0.4]);
}

export type { SurfaceMat };

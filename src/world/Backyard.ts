import * as THREE from 'three';
import { Physics } from '../physics/Physics';
import { EnvMats, StaticBatcher, plastic, metal, translucent } from '../render/materials';
import { Builder, V3, v3 } from './Builder';
import { seeded } from '../core/math';
import { ArenaInfo, Animated, LooseBricks, Zone } from './Arena';
import type { HillSite, SectorDef } from '../match/modes';
import type { ElevatorSite } from './Elevators';

/** Map 2: SANDBOX SHOWDOWN. A sunny backyard at toy scale. */
export const YARD = { x0: -34, x1: 34, z0: -34, z1: 34, fence: 14, deckY: 7 };

export const YARD_ELEVATORS: ElevatorSite[] = [
  { x: 30.2, z: -24, exit: [-1, 0], name: 'picnic table' },
  { x: 25.8, z: -5, exit: [1, 0], name: 'back porch' },
];

export const YARD_HILL_SITES: HillSite[] = [
  { name: 'the Sand Castle', pos: new THREE.Vector3(0, 2.5, 0), radius: 3.8, height: 4 },
  { name: 'the Picnic Table', pos: new THREE.Vector3(21, 7, -24), radius: 4.6, height: 4 },
  { name: 'the Back Porch', pos: new THREE.Vector3(30.5, 7, 1), radius: 3.4, height: 4 },
  { name: 'the Kiddie Pool', pos: new THREE.Vector3(20, 0.12, 22), radius: 5, height: 5 },
  { name: 'the Flower Garden', pos: new THREE.Vector3(-25, 2.2, 22), radius: 4.6, height: 4 },
  { name: 'the Dump Truck', pos: new THREE.Vector3(-17, 0, 6), radius: 4.4, height: 5 },
  { name: 'the Play Tower', pos: new THREE.Vector3(-26, 10, -26), radius: 3.8, height: 4 },
];
export const YARD_SECTORS: SectorDef[] = [
  { ...YARD_HILL_SITES[6], letter: 'T', short: 'Tower' },
  { ...YARD_HILL_SITES[1], letter: 'P', short: 'Picnic' },
  { ...YARD_HILL_SITES[3], letter: 'K', short: 'Pool' },
  { ...YARD_HILL_SITES[2], letter: 'H', short: 'Porch' },
  { ...YARD_HILL_SITES[4], letter: 'F', short: 'Garden' },
  { ...YARD_HILL_SITES[5], letter: 'D', short: 'Truck' },
];
/** Sunrise = Play Tower, Moonbeam = Kiddie Pool, Clover = Flower Garden */
export const YARD_HOMES = [0, 2, 4];

function noiseTexture(base: string, amount: number, repeat: number, blades = 0, seed = 11) {
  const W = 256;
  const c = document.createElement('canvas');
  c.width = c.height = W;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = base;
  ctx.fillRect(0, 0, W, W);
  const r = seeded(seed);
  const img = ctx.getImageData(0, 0, W, W);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (r() - 0.5) * amount;
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n * 0.6;
  }
  ctx.putImageData(img, 0, 0);
  for (let i = 0; i < blades; i++) {
    const x = r() * W, y = r() * W;
    ctx.strokeStyle = r() < 0.5 ? 'rgba(255,255,190,0.16)' : 'rgba(20,70,20,0.2)';
    ctx.lineWidth = 1.2;
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + (r() - 0.5) * 5, y - 4 - r() * 6);
    ctx.stroke();
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.anisotropy = 4;
  return t;
}

function sidingTexture() {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 256;
  const ctx = c.getContext('2d')!;
  for (let y = 0; y < 256; y += 32) {
    const g = ctx.createLinearGradient(0, y, 0, y + 32);
    g.addColorStop(0, '#f1e6cf');
    g.addColorStop(0.85, '#e2d2b2');
    g.addColorStop(1, '#bda98a');
    ctx.fillStyle = g;
    ctx.fillRect(0, y, 64, 32);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(1, 6);
  return t;
}

export function buildBackyard(scene: THREE.Scene, phys: Physics): ArenaInfo {
  const root = new THREE.Group();
  root.name = 'arena';
  scene.add(root);
  const M = new EnvMats();
  const batch = new StaticBatcher();
  const B = new Builder(batch, phys);
  const animated: Animated[] = [];
  const rnd = seeded(77);
  const Y = YARD;

  const grass = new THREE.MeshStandardMaterial({ map: noiseTexture('#5fae4a', 34, 18, 2600), roughness: 1 });
  const sand = new THREE.MeshStandardMaterial({ map: noiseTexture('#ecd28f', 26, 6, 0, 5), roughness: 1 });
  const wetSand = new THREE.MeshStandardMaterial({ map: noiseTexture('#d9b76c', 24, 3, 0, 6), roughness: 0.95 });
  const soil = new THREE.MeshStandardMaterial({ map: noiseTexture('#5b3d26', 30, 4, 0, 8), roughness: 1 });
  const terracotta = new THREE.MeshStandardMaterial({ color: '#c8693d', roughness: 0.85 });
  const leaf = new THREE.MeshStandardMaterial({ color: '#3f9b3a', roughness: 0.8, side: THREE.DoubleSide });
  const hedge = new THREE.MeshStandardMaterial({ map: noiseTexture('#2f7d32', 44, 6, 900, 3), roughness: 1 });
  const siding = new THREE.MeshStandardMaterial({ map: sidingTexture(), roughness: 0.8 });
  const yellow = plastic('#ffd23f', { rough: 0.3 });
  const red = plastic('#e63946', { rough: 0.3 });
  const blue = plastic('#3a86ff', { rough: 0.3 });
  const white = plastic('#fffdf5', { rough: 0.35 });

  // ---------------------------------------------------------------- GROUND + FENCE
  B.box([Y.x0 - 2, -1, Y.z0 - 2], [Y.x1 + 2, 0, Y.z1 + 2], grass, 'carpet');
  const F = Y.fence;
  B.box([Y.x0 - 1, 0, Y.z0 - 1], [Y.x1 + 1, F, Y.z0], M.blockWood, 'wood', { tile: 1 / 10 });
  B.box([Y.x0 - 1, 0, Y.z1], [Y.x1 + 1, F, Y.z1 + 1], M.blockWood, 'wood', { tile: 1 / 10 });
  B.box([Y.x0 - 1, 0, Y.z0], [Y.x0, F, Y.z1], M.blockWood, 'wood', { tile: 1 / 10 });
  // east side is the house wall
  B.box([Y.x1, 0, Y.z0], [Y.x1 + 1.5, 34, Y.z1], siding, 'wood');
  // pickets + rails so the fence doesn't read as a flat wall
  for (let i = -33; i <= 33; i += 3) {
    B.box([i - 0.12, 0, Y.z0], [i + 0.12, F + 0.5, Y.z0 + 0.14], M.trim, null);
    B.box([i - 0.12, 0, Y.z1 - 0.14], [i + 0.12, F + 0.5, Y.z1], M.trim, null);
    B.box([Y.x0, 0, i - 0.12], [Y.x0 + 0.14, F + 0.5, i + 0.12], M.trim, null);
  }
  for (const y of [3, 11]) {
    B.box([Y.x0, y, Y.z0], [Y.x1, y + 0.5, Y.z0 + 0.3], M.bedWood, null);
    B.box([Y.x0, y, Y.z1 - 0.3], [Y.x1, y + 0.5, Y.z1], M.bedWood, null);
    B.box([Y.x0, y, Y.z0], [Y.x0 + 0.3, y + 0.5, Y.z1], M.bedWood, null);
  }
  // invisible walls above the fence + a lid, so nothing leaves the yard
  phys.box(v3(0, 28, Y.z0 - 0.5), v3(36, 14, 0.5), 'wood');
  phys.box(v3(0, 28, Y.z1 + 0.5), v3(36, 14, 0.5), 'wood');
  phys.box(v3(Y.x0 - 0.5, 28, 0), v3(0.5, 14, 36), 'wood');
  phys.box(v3(0, 42.5, 0), v3(37, 0.5, 37), 'wood');
  // hedges and a tree peeking over the fence
  for (const [x0, z0, x1, z1] of [[-40, -44, 40, -37], [-40, 37, 40, 44], [-44, -40, -37, 40]]) B.box([x0, 0, z0], [x1, 19, z1], hedge, null, { round: 2.5, cast: false });
  B.cyl([-41, 0, 30], 2.4, 30, new THREE.MeshStandardMaterial({ color: '#6b4a2f', roughness: 1 }), null, 10);
  for (let i = 0; i < 9; i++) {
    const a = i * 2.4;
    B.geo(new THREE.IcosahedronGeometry(6 + (i % 3) * 1.5, 1), leaf, [-41 + Math.cos(a) * 7, 30 + (i % 4) * 2.5, 30 + Math.sin(a) * 7], undefined, undefined, true);
  }
  // house: door + window on the wall behind the porch
  B.box([Y.x1 - 0.15, 7, -3.5], [Y.x1 + 0.1, 22, 3.5], plastic('#4d6fa8', { rough: 0.5 }), null);
  B.box([Y.x1 - 0.25, 13.5, 2.2], [Y.x1 - 0.05, 14.5, 2.9], metal('#e2c36a', 0.3), null);
  B.box([Y.x1 - 0.15, 12, -9.5], [Y.x1 + 0.1, 20, -5], M.glass, null);
  B.box([Y.x1 - 0.2, 11.6, -9.9], [Y.x1 + 0.1, 12, -4.6], M.trim, null);
  B.box([Y.x1 - 0.2, 20, -9.9], [Y.x1 + 0.1, 20.4, -4.6], M.trim, null);

  // ---------------------------------------------------------------- SANDBOX + SAND CASTLE (center)
  const SB = { x0: -12, x1: 12, z0: -10, z1: 10, h: 0.9, sandY: 0.3 };
  B.box([SB.x0, 0, SB.z0], [SB.x1, SB.h, SB.z0 + 1], M.blockWood, 'wood', { tile: 1 / 6 });
  B.box([SB.x0, 0, SB.z1 - 1], [SB.x1, SB.h, SB.z1], M.blockWood, 'wood', { tile: 1 / 6 });
  B.box([SB.x0, 0, SB.z0 + 1], [SB.x0 + 1, SB.h, SB.z1 - 1], M.blockWood, 'wood', { tile: 1 / 6 });
  B.box([SB.x1 - 1, 0, SB.z0 + 1], [SB.x1, SB.h, SB.z1 - 1], M.blockWood, 'wood', { tile: 1 / 6 });
  B.box([SB.x0 + 1, 0, SB.z0 + 1], [SB.x1 - 1, SB.sandY, SB.z1 - 1], sand, 'carpet');
  // little ramps over the frame, outside and inside
  B.wedge([0, 0, SB.z1 + 1.6], Math.PI, 1.6, SB.h, 3.2, M.bedWood, 'wood');
  B.wedge([0, 0, SB.z0 - 1.6], 0, 1.6, SB.h, 3.2, M.bedWood, 'wood');
  B.wedge([SB.x1 + 1.6, 0, 5], -Math.PI / 2, 1.6, SB.h, 3.2, M.bedWood, 'wood');
  B.wedge([SB.x0 - 1.6, 0, -5], Math.PI / 2, 1.6, SB.h, 3.2, M.bedWood, 'wood');
  B.wedge([0, SB.sandY, SB.z1 - 2.3], 0, 1.3, SB.h - SB.sandY, 3.2, wetSand, 'carpet');
  B.wedge([0, SB.sandY, SB.z0 + 2.3], Math.PI, 1.3, SB.h - SB.sandY, 3.2, wetSand, 'carpet');
  B.wedge([SB.x1 - 2.3, SB.sandY, 5], Math.PI / 2, 1.3, SB.h - SB.sandY, 3.2, wetSand, 'carpet');
  B.wedge([SB.x0 + 2.3, SB.sandY, -5], -Math.PI / 2, 1.3, SB.h - SB.sandY, 3.2, wetSand, 'carpet');
  // castle: a raised courtyard with four towers and low battlements
  const CT = 2.5;
  B.box([-4.5, SB.sandY, -4], [4.5, CT, 4], wetSand, 'carpet', { round: 0.25 });
  B.wedge([8.6, SB.sandY, 0], -Math.PI / 2, 4.1, CT - SB.sandY, 3, wetSand, 'carpet');
  B.wedge([-8.6, SB.sandY, 0], Math.PI / 2, 4.1, CT - SB.sandY, 3, wetSand, 'carpet');
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) {
    B.cyl([sx * 4.5, SB.sandY, sz * 4], 1.25, 4.6, wetSand, 'carpet', 16);
    B.geo(new THREE.ConeGeometry(1.5, 1.8, 16), red, [sx * 4.5, SB.sandY + 4.6 + 0.9, sz * 4]);
    for (let k = 0; k < 6; k++) {
      const a = (k / 6) * Math.PI * 2;
      B.box([sx * 4.5 + Math.cos(a) * 1.0 - 0.2, SB.sandY + 4.6, sz * 4 + Math.sin(a) * 1.0 - 0.2], [sx * 4.5 + Math.cos(a) * 1.0 + 0.2, SB.sandY + 4.95, sz * 4 + Math.sin(a) * 1.0 + 0.2], wetSand, null);
    }
  }
  for (const sz of [-1, 1]) for (const [a, b] of [[-3, -1.2], [1.2, 3]]) B.box([a, CT, sz * 4 - 0.25], [b, CT + 0.85, sz * 4 + 0.25], wetSand, 'carpet');
  // bucket and spade
  B.cyl([7.6, SB.sandY, -6], 1.3, 2.7, blue, 'plastic', 20, 1.6);
  B.geo(new THREE.TorusGeometry(1.6, 0.09, 6, 24, Math.PI), white, [7.6, SB.sandY + 2.7, -6], new THREE.Euler(0.5, 0.4, 0));
  B.obox([-7.4, SB.sandY + 0.12, 6.4], [0.9, 0.22, 3.2], new THREE.Euler(0, 0.5, 0), red, 'plastic', 0.08);
  B.obox([-6.4, SB.sandY + 0.16, 4.4], [1.6, 0.3, 1.6], new THREE.Euler(0, 0.5, 0), red, 'plastic', 0.12);
  B.geo(new THREE.SphereGeometry(1.5, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), sand, [-7.5, SB.sandY, -5.5], undefined, [1, 0.5, 1]);
  B.geo(new THREE.SphereGeometry(1.1, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), sand, [8, SB.sandY, 6.5], undefined, [1, 0.45, 1]);

  // ---------------------------------------------------------------- PICNIC TABLE (NE)
  const TY = Y.deckY;
  B.box([13, TY - 0.5, -30], [29, TY, -18], M.desk, 'wood', { tile: 1 / 8 });
  B.box([13, 3.1, -33.2], [29, 3.5, -31], M.desk, 'wood', { tile: 1 / 8 });
  B.box([13, 3.1, -17], [29, 3.5, -14.8], M.desk, 'wood', { tile: 1 / 8 });
  for (const x of [15, 27]) {
    for (const z of [-28.8, -19.2]) B.box([x - 0.5, 0, z - 0.5], [x + 0.5, TY - 0.5, z + 0.5], M.bedWood, 'wood');
    for (const z of [-32.1, -15.9]) B.box([x - 0.4, 0, z - 0.4], [x + 0.4, 3.1, z + 0.4], M.bedWood, 'wood');
    B.box([x - 0.3, 2.6, -32.1], [x + 0.3, 3.1, -15.9], M.bedWood, null);
  }
  // gingham tablecloth strip down the middle
  B.box([13.2, TY, -25.6], [28.8, TY + 0.03, -22.4], plastic('#ef476f', { rough: 0.9, clearcoat: 0 }), null, { cast: false });
  for (let x = 13.6; x < 28.6; x += 1.6) B.box([x, TY + 0.03, -25.6], [x + 0.8, TY + 0.04, -22.4], white, null, { cast: false });
  // plank up to the south bench, long plank up to the table top
  B.slab([21, 0, -8.8], [21, 3.5, -14.8], 2.6, 0.3, M.bedWood, 'wood');
  B.slab([3.2, 0, -24], [13, TY, -24], 2.8, 0.3, M.bedWood, 'wood');
  for (let i = 1; i < 10; i++) B.obox([3.2 + (9.8 * i) / 10, (TY * i) / 10 + 0.05, -24], [0.16, 0.1, 2.6], new THREE.Euler(0, 0, Math.atan2(TY, 9.8)), M.trim, null);
  // things on the table to hide behind
  B.cyl([25.5, TY, -27.2], 1.5, 4.2, translucent('#ffe98a', 0.5), 'glass', 20, 1.7);
  B.cyl([25.5, TY, -27.2], 1.35, 2.6, translucent('#ffd23f', 0.75), null, 20);
  B.cyl([16.2, TY, -20.6], 0.8, 3.2, red, 'plastic', 14, 0.5);
  B.cyl([16.2, TY + 3.2, -20.6], 0.3, 0.5, white, null, 10);
  B.cyl([19.5, TY, -28], 1.7, 0.16, white, 'plastic', 24);
  B.geo(new THREE.SphereGeometry(1.0, 14, 10), plastic('#f4a261', { rough: 0.8 }), [19.5, TY + 0.6, -28], undefined, [1, 0.6, 1]);

  // ---------------------------------------------------------------- BACK PORCH (E)
  B.box([27, TY - 0.5, -10], [Y.x1, TY, 10], M.desk, 'wood', { tile: 1 / 8 });
  for (const z of [-9.4, 0, 9.4]) B.box([26.8, 0, z - 0.4], [27.05, TY - 0.5, z + 0.4], M.trim, null);
  // lattice under the porch (solid so nobody gets lost under there)
  B.box([27, 0, -10], [Y.x1, TY - 0.5, 10], new THREE.MeshStandardMaterial({ color: '#d9cdb4', roughness: 0.9 }), 'wood');
  B.wedge([17.4, 0, 6], Math.PI / 2, 9.6, TY, 4, M.desk, 'wood');
  // railing along the open edge, with gaps at the steps and the lift
  for (const [a, b] of [[-10, -6.4], [-3.6, 4]]) {
    B.box([27, TY + 0.9, a], [27.25, TY + 1.1, b], M.trim, 'wood');
    for (let z = a + 0.3; z < b; z += 0.9) B.box([27.05, TY, z - 0.06], [27.2, TY + 0.9, z + 0.06], M.trim, null);
    B.box([27, TY, a], [27.25, TY + 0.9, b], M.glass, 'wood', { visual: false });
  }
  B.box([29, TY, -3.4], [33.6, TY + 0.06, 3.4], plastic('#7a5a3e', { rough: 1, clearcoat: 0 }), null, { cast: false });
  B.cyl([32, TY, 8], 1.2, 2.2, terracotta, 'plastic', 16, 1.5);
  for (let i = 0; i < 5; i++) B.geo(new THREE.ConeGeometry(0.5, 2.6, 5), leaf, [32 + Math.cos(i * 1.3) * 0.6, TY + 3.2, 8 + Math.sin(i * 1.3) * 0.6], new THREE.Euler(Math.cos(i) * 0.3, 0, Math.sin(i) * 0.3));
  B.box([30.6, TY, -8.8], [33.4, TY + 1.9, -6.6], M.cardboardToys, 'cardboard');

  // ---------------------------------------------------------------- KIDDIE POOL (SE)
  const PC = { x: 20, z: 22, r: 8.5 };
  const poolMat = plastic('#48cae4', { rough: 0.25 });
  const N = 18;
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2;
    const len = 2 * PC.r * Math.tan(Math.PI / N) + 0.35;
    B.obox([PC.x + Math.sin(a) * PC.r, 0.5, PC.z + Math.cos(a) * PC.r], [len, 1.0, 0.9], new THREE.Euler(0, a, 0), i % 2 ? poolMat : white, 'plastic', 0.3);
  }
  B.cyl([PC.x, 0, PC.z], PC.r - 0.3, 0.12, plastic('#90e0ef', { rough: 0.4 }), 'plastic', 36);
  const water = new THREE.Mesh(new THREE.CircleGeometry(PC.r - 0.4, 40), new THREE.MeshPhysicalMaterial({ color: '#7fd8ff', transparent: true, opacity: 0.42, roughness: 0.05, clearcoat: 1, depthWrite: false }));
  water.rotation.x = -Math.PI / 2;
  water.position.set(PC.x, 0.62, PC.z);
  root.add(water);
  animated.push({ update: (_dt, t) => (water.position.y = 0.62 + Math.sin(t * 1.4) * 0.03) });
  // rubber duck + beach ball
  B.cyl([PC.x + 1.5, 0.12, PC.z + 4], 1.5, 1.7, yellow, 'plastic', 18);
  B.geo(new THREE.SphereGeometry(1.7, 18, 12), yellow, [PC.x + 1.5, 1.2, PC.z + 4], undefined, [1.15, 0.8, 1]);
  B.geo(new THREE.SphereGeometry(1.0, 16, 12), yellow, [PC.x + 2.6, 2.7, PC.z + 4]);
  B.geo(new THREE.ConeGeometry(0.45, 0.9, 10), plastic('#ff7b00'), [PC.x + 3.7, 2.6, PC.z + 4], new THREE.Euler(0, 0, -Math.PI / 2));
  B.cyl([PC.x - 4, 0.12, PC.z - 2.5], 1.3, 2.6, white, 'plastic', 14);
  for (let i = 0; i < 6; i++) {
    B.geo(new THREE.SphereGeometry(1.5, 12, 10, (i / 6) * Math.PI * 2, Math.PI / 3), [red, white, blue, yellow, white, plastic('#2dc653')][i], [PC.x - 4, 1.6, PC.z - 2.5]);
  }

  // ---------------------------------------------------------------- PLAY TOWER + SLIDE (NW)
  const PT = 10;
  B.box([-30, PT - 0.5, -30], [-22, PT, -22], M.bedWood, 'wood', { tile: 1 / 6 });
  for (const x of [-29.6, -22.4]) for (const z of [-29.6, -22.4]) B.box([x - 0.4, 0, z - 0.4], [x + 0.4, PT + 4.5, z + 0.4], M.blockWood, 'wood');
  B.geo(new THREE.ConeGeometry(6.6, 3.6, 4), red, [-26, PT + 6.3, -26], new THREE.Euler(0, Math.PI / 4, 0));
  B.box([-30, PT, -30], [-22, PT + 1.1, -29.7], blue, 'wood');
  B.box([-30, PT, -29.7], [-29.7, PT + 1.1, -22], blue, 'wood');
  B.box([-25, PT, -22.3], [-22.8, PT + 1.1, -22], blue, 'wood');
  B.box([-22.3, PT, -24.5], [-22, PT + 1.1, -22.8], blue, 'wood');
  // the slide down to the east, and a climbing plank up from the south
  B.slab([-22, PT, -27.2], [-5.5, 0, -27.2], 3, 0.3, yellow, 'plastic');
  const sAng = Math.atan2(PT, 16.5), sLen = Math.hypot(PT, 16.5);
  for (const s of [-1, 1]) B.obox([-13.75, PT / 2 + 0.2, -27.2 + s * 1.45], [sLen, 0.5, 0.14], new THREE.Euler(0, 0, -sAng), plastic('#ff9f1c', { rough: 0.3 }), null);
  B.slab([-27.3, 0, -8.6], [-27.3, PT, -22], 2.6, 0.3, M.bedWood, 'wood');
  for (let i = 1; i < 12; i++) B.obox([-27.3, (PT * i) / 12 + 0.05, -8.6 - (13.4 * i) / 12], [2.4, 0.1, 0.16], new THREE.Euler(-Math.atan2(PT, 13.4), 0, 0), M.trim, null);
  // bark chips under the tower
  B.box([-30.5, 0, -30.5], [-21.5, 0.04, -21.5], soil, null, { cast: false });

  // ---------------------------------------------------------------- DUMP TRUCK (W)
  B.box([-31, 0, -5], [-19, 2, 1], plastic('#343a40', { rough: 0.5 }), 'plastic', { round: 0.2 });
  B.box([-31, 2, -5], [-27.5, 5.5, 1], red, 'plastic', { round: 0.4 });
  B.box([-27.6, 3.4, -4.4], [-27.4, 5, 0.4], M.glass, null);
  B.wedge([-19, 2, -2], -Math.PI / 2, 8.5, 2.6, 5.6, yellow, 'plastic');
  for (const z of [-4.9, 0.6]) B.obox([-23.25, 3.9, z], [8.9, 1.0, 0.3], new THREE.Euler(0, 0, -Math.atan2(2.6, 8.5)), yellow, null);
  B.wedge([-14.6, 0, -2], -Math.PI / 2, 4.4, 2, 5.6, plastic('#ffbe0b', { rough: 0.4 }), 'plastic');
  for (const x of [-29, -22]) for (const z of [-5.3, 1.3]) B.geo(new THREE.CylinderGeometry(1.25, 1.25, 0.9, 18), plastic('#1d1d1f', { rough: 0.8, clearcoat: 0 }), [x, 1.25, z], new THREE.Euler(Math.PI / 2, 0, 0));
  for (const [x, z] of [[-15, 9.5], [-21.5, 8.5], [-13.5, -8]]) {
    B.cyl([x, 0, z], 0.75, 0.15, plastic('#ff7b00'), null, 12);
    B.cyl([x, 0.15, z], 0.55, 1.7, plastic('#ff7b00'), 'plastic', 12, 0.12);
  }

  // ---------------------------------------------------------------- FLOWER GARDEN (SW)
  const GY = 2.2;
  B.box([-32, 0, 14], [-18, GY - 0.1, 32], M.blockWood, 'wood', { tile: 1 / 6 });
  B.box([-31.5, GY - 0.1, 14.5], [-18.5, GY, 31.5], soil, 'carpet');
  B.wedge([-12.8, 0, 23], -Math.PI / 2, 5.2, GY - 0.1, 3.4, M.bedWood, 'wood');
  B.wedge([-25, 0, 9.4], 0, 4.6, GY - 0.1, 3.2, M.bedWood, 'wood');
  const petals = ['#ff5d8f', '#ffd23f', '#c77dff', '#ff7b00', '#ffffff'];
  [[-29.5, 17, 9], [-21, 17.5, 7.5], [-30, 24.5, 10.5], [-20.5, 29, 8.5], [-26, 30, 7]].forEach(([x, z, hgt], i) => {
    B.cyl([x, GY, z], 0.32, hgt, leaf, 'plastic', 8);
    const pm = plastic(petals[i % petals.length], { rough: 0.5 });
    for (let k = 0; k < 7; k++) {
      const a = (k / 7) * Math.PI * 2;
      B.geo(new THREE.SphereGeometry(1, 10, 8), pm, [x + Math.cos(a) * 1.5, GY + hgt, z + Math.sin(a) * 1.5], undefined, [1, 0.3, 0.7].map((v, j) => (j === 0 ? Math.abs(Math.cos(a)) * 0.5 + 0.7 : j === 2 ? Math.abs(Math.sin(a)) * 0.5 + 0.7 : v)) as V3);
    }
    B.geo(new THREE.SphereGeometry(0.9, 12, 10), plastic('#7a4b12', { rough: 0.9 }), [x, GY + hgt + 0.1, z], undefined, [1, 0.5, 1]);
    B.geo(new THREE.SphereGeometry(1.2, 8, 6), leaf, [x + 0.9, GY + hgt * 0.45, z], undefined, [1, 0.12, 0.5]);
  });
  // gnome on the planter, pots on the lawn
  B.cyl([-28, GY, 28], 1.1, 2.6, blue, 'plastic', 14, 0.8);
  B.geo(new THREE.SphereGeometry(0.8, 14, 10), plastic('#ffd8b5', { rough: 0.6 }), [-28, GY + 3.1, 28]);
  B.geo(new THREE.ConeGeometry(0.85, 2.2, 14), red, [-28, GY + 4.6, 28]);
  B.geo(new THREE.SphereGeometry(0.6, 10, 8), white, [-28, GY + 2.6, 27.4], undefined, [1, 1.1, 0.5]);
  B.cyl([-11.5, 0, 16], 1.8, 3.2, terracotta, 'plastic', 18, 2.3);
  B.cyl([-11.5, 3.2, 16], 2.0, 0.1, soil, null, 18);
  B.cyl([-9, 0, 29], 1.4, 2.4, terracotta, 'plastic', 16, 1.8);
  for (let i = 0; i < 6; i++) B.geo(new THREE.ConeGeometry(0.6, 3.4, 5), leaf, [-11.5 + Math.cos(i * 1.1) * 0.9, 4.6, 16 + Math.sin(i * 1.1) * 0.9], new THREE.Euler(Math.cos(i) * 0.35, 0, Math.sin(i) * 0.35));

  // ---------------------------------------------------------------- LAWN PROPS
  // tree stump with a plank up it (south), soccer ball + skateboard (north), a few rocks
  B.cyl([1, 0, 24.2], 3.2, 2.6, new THREE.MeshStandardMaterial({ color: '#8a6238', roughness: 1 }), 'wood', 14);
  B.cyl([1, 2.6, 24.2], 2.9, 0.05, M.blockWood, null, 14);
  B.wedge([1, 0, 16.6], 0, 4.5, 2.6, 3, M.bedWood, 'wood');
  B.cyl([-2, 0, -20], 2.1, 4.2, white, 'plastic', 14);
  B.geo(new THREE.IcosahedronGeometry(2.5, 1), new THREE.MeshStandardMaterial({ color: '#f8f9fa', roughness: 0.6, flatShading: true }), [-2, 2.4, -20]);
  B.box([4.5, 0.55, -18.6], [12.5, 0.9, -16.2], plastic('#9b5de5', { rough: 0.4 }), 'wood', { round: 0.16 });
  B.box([4.5, 0, -18.6], [12.5, 0.55, -16.2], M.glass, 'wood', { visual: false });
  for (const x of [5.8, 11.2]) for (const z of [-18.5, -16.3]) B.geo(new THREE.CylinderGeometry(0.42, 0.42, 0.4, 12), yellow, [x, 0.42, z], new THREE.Euler(Math.PI / 2, 0, 0));
  for (const [x, z, s] of [[14, 11, 1.3], [-14, 12.5, 1.1], [9, -12.5, 1.0], [-31, 4, 1.5], [8.5, 31, 1.4]]) {
    B.geo(new THREE.DodecahedronGeometry(s, 0), M.rock, [x, s * 0.55, z], new THREE.Euler(rnd(), rnd() * 3, rnd()));
    phys.cylinder(v3(x, s * 0.5, z), s * 0.5, s * 0.8, 'wood');
  }
  // garden hose snaking across the lawn (decor)
  {
    const pts = [[-33, 0.2, 10.5], [-24, 0.2, 11.5], [-14, 0.2, 14], [-6, 0.2, 13], [2, 0.2, 14.5], [9, 0.2, 13], [12, 0.2, 9]].map((p) => v3(p[0], p[1], p[2]));
    B.geo(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 60, 0.2, 8), plastic('#2dc653', { rough: 0.5 }), [0, 0, 0]);
    B.cyl([12, 0, 9], 0.3, 0.6, metal('#d6b34a', 0.3), null, 10);
  }
  // pinwheels
  for (const [x, z, col] of [[-16.5, 13.2, '#ff5d8f'], [13.5, -11.5, '#3a86ff']] as const) {
    B.cyl([x, 0, z], 0.08, 4.2, white, null, 6);
    const wheel = new THREE.Group();
    for (let k = 0; k < 4; k++) {
      const blade = new THREE.Mesh(new THREE.ConeGeometry(0.5, 1.5, 3), plastic(k % 2 ? col : '#ffd23f', { rough: 0.4 }));
      blade.position.set(Math.cos((k * Math.PI) / 2) * 0.7, Math.sin((k * Math.PI) / 2) * 0.7, 0);
      blade.rotation.z = (k * Math.PI) / 2 - Math.PI / 2;
      blade.castShadow = true;
      wheel.add(blade);
    }
    wheel.position.set(x, 4.2, z + 0.15);
    root.add(wheel);
    animated.push({ update: (dt) => (wheel.rotation.z += dt * 3.2) });
  }

  // ---------------------------------------------------------------- finish
  const blockSpots: THREE.Vector3[] = [];
  {
    const r = seeded(9);
    for (let i = 0; i < 16; i++) blockSpots.push(v3(-10 + r() * 4.5, 1 + (i % 3) * 0.7, 5 + r() * 3.5));
    for (let i = 0; i < 8; i++) blockSpots.push(v3(5.5 + r() * 4, 1 + (i % 3) * 0.7, -8 + r() * 1.6));
  }
  B.buildStuds(root);
  batch.build(root);
  phys.refreshQueries();
  const looseBricks = new LooseBricks(phys, blockSpots, root);
  animated.push(looseBricks);

  // ---------------------------------------------------------------- LIGHTING (afternoon sun)
  const sunDir = v3(0.42, -0.78, 0.38).normalize();
  const sun = new THREE.DirectionalLight('#fff0cf', 5.4);
  const target = v3(0, 0, 0);
  sun.position.copy(target).addScaledVector(sunDir, -100);
  sun.target.position.copy(target);
  sun.castShadow = true;
  const sc = sun.shadow.camera;
  sc.left = -58; sc.right = 58; sc.top = 58; sc.bottom = -58; sc.near = 20; sc.far = 200;
  sun.shadow.bias = -0.0004;
  sun.shadow.normalBias = 0.04;
  sun.shadow.radius = 3;
  root.add(sun, sun.target);
  const hemi = new THREE.HemisphereLight('#cfe9ff', '#6f9b52', 0.85);
  root.add(hemi);

  // ---------------------------------------------------------------- GAMEPLAY DATA
  const zones: Zone[] = [
    { name: 'Picnic Table', min: [12, -34], max: [34, -12], ambience: 'desk' },
    { name: 'Back Porch', min: [24, -12], max: [34, 11], ambience: 'closet' },
    { name: 'Kiddie Pool', min: [10, 11], max: [34, 34], ambience: 'garage' },
    { name: 'Flower Garden', min: [-34, 9], max: [-8, 34], ambience: 'dino' },
    { name: 'Play Tower', min: [-34, -34], max: [-12, -12], ambience: 'bed' },
    { name: 'Dump Truck', min: [-34, -12], max: [-13, 9], ambience: 'brick' },
    { name: 'Sandbox', min: [-34, -34], max: [34, 34], ambience: 'rug' },
  ];
  const ground = (x: number, z: number, fromY: number) => {
    const d = phys.rayDist(v3(x, fromY, z), v3(0, -1, 0), fromY + 2, true);
    return v3(x, d === Infinity ? 0 : fromY - d, z);
  };
  const pickupSpots: ArenaInfo['pickupSpots'] = [
    { kind: 'health', pos: ground(0, -14, 3) },
    { kind: 'health', pos: ground(8, 2.5, 2) },
    { kind: 'health', pos: ground(-23.5, -2, 12) },
    { kind: 'health', pos: ground(21, -24, 5) },
    { kind: 'health', pos: ground(-24, 20, 8) },
    { kind: 'health', pos: ground(22, 18, 4) },
    { kind: 'health', pos: ground(31.5, 5.5, 12) },
    { kind: 'health', pos: ground(-9, 20, 3) },
    { kind: 'shield', pos: ground(0, 0, 8) },
    { kind: 'shield', pos: ground(-28, -28, 13) },
    { kind: 'turbo', pos: ground(-3.5, -27.2, 3) },
    { kind: 'infinite', pos: ground(1, 24.2, 6) },
    { kind: 'power', pos: ground(21, -24, 12) },
  ];

  return {
    root, zones, pickupSpots, weaponSpots: [], animated, sun, hemi, sunDir, pointLights: [], looseBricks,
    bounds: { min: v3(Y.x0, 0, Y.z0), max: v3(Y.x1, 30, Y.z1) },
    window: { x0: 0, x1: 0, y0: 0, y1: 0, z: 0 },
  };
}

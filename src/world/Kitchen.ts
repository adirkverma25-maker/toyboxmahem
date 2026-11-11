import * as THREE from 'three';
import { Physics } from '../physics/Physics';
import { EnvMats, StaticBatcher, plastic, metal, translucent } from '../render/materials';
import { softDotTexture } from '../render/textures';
import { Builder, v3 } from './Builder';
import { seeded } from '../core/math';
import { ArenaInfo, Animated, LooseBricks, Zone } from './Arena';
import type { HillSite, SectorDef } from '../match/modes';
import type { ElevatorSite } from './Elevators';
import type { AmbientLike } from './YardAmbient';

/**
 * Map 3: KITCHEN CLASH. A family kitchen at toy scale.
 * Three high spots share one height (DECK): the kitchen island in the middle, the dining table (SE)
 * and the long counter along the north wall. Lower ledges: the pulled-out freezer drawer (W) and
 * the open oven door (E). Ground fights around cereal-box city (N), the pantry (SW) and the dog bowl (NW).
 */
export const KITCHEN = { x0: -34, x1: 34, z0: -34, z1: 34, wall: 32, deck: 8, drawer: 3.2, ovenDoor: 2.6 };

const K = KITCHEN;
const ISLAND = { x0: -7, x1: 7, z0: -5, z1: 7 };
const TABLE = { x0: 12, x1: 28, z0: 16, z1: 30 };
const COUNTER = { x0: -20, x1: 34, z0: -34, z1: -27 };

export const KITCHEN_ELEVATORS: ElevatorSite[] = [
  { x: ISLAND.x1 + 1.2, z: 1, exit: [-1, 0], name: 'kitchen island' },
  { x: TABLE.x1 + 1.2, z: 20, exit: [-1, 0], name: 'dining table' },
  { x: 2, z: COUNTER.z1 + 1.2, exit: [0, -1], name: 'counter' },
];

export const KITCHEN_HILL_SITES: HillSite[] = [
  { name: 'the Kitchen Island', pos: new THREE.Vector3(0, K.deck, 1), radius: 4, height: 4 },
  { name: 'the Dining Table', pos: new THREE.Vector3(20, K.deck, 23), radius: 4.5, height: 4 },
  { name: 'the Freezer Drawer', pos: new THREE.Vector3(-22.5, K.drawer, -4), radius: 3.2, height: 4 },
  { name: 'the Oven Door', pos: new THREE.Vector3(24, K.ovenDoor, 4), radius: 3, height: 4 },
  { name: 'Cereal City', pos: new THREE.Vector3(13, 0, -19), radius: 4.5, height: 5 },
  { name: 'the Pantry', pos: new THREE.Vector3(-19, 0, 19), radius: 4.5, height: 5 },
  { name: 'the Dog Bowl', pos: new THREE.Vector3(-18, 0, -20), radius: 3.6, height: 4 },
];
export const KITCHEN_SECTORS: SectorDef[] = [
  { ...KITCHEN_HILL_SITES[6], letter: 'D', short: 'Bowl' },
  { ...KITCHEN_HILL_SITES[2], letter: 'F', short: 'Freezer' },
  { ...KITCHEN_HILL_SITES[4], letter: 'C', short: 'Cereal' },
  { ...KITCHEN_HILL_SITES[3], letter: 'O', short: 'Oven' },
  { ...KITCHEN_HILL_SITES[1], letter: 'T', short: 'Table' },
  { ...KITCHEN_HILL_SITES[5], letter: 'P', short: 'Pantry' },
];
/** Sunrise = Dog Bowl (NW), Moonbeam = Oven (E), Clover = Pantry (SW) */
export const KITCHEN_HOMES = [0, 3, 5];

function tileTexture() {
  const W = 256;
  const c = document.createElement('canvas');
  c.width = c.height = W;
  const ctx = c.getContext('2d')!;
  const r = seeded(21);
  for (let i = 0; i < 4; i++)
    for (let j = 0; j < 4; j++) {
      ctx.fillStyle = (i + j) % 2 ? '#f6efe2' : '#cf4a4a';
      ctx.fillRect(i * 64, j * 64, 64, 64);
    }
  // grout + a little wear
  ctx.strokeStyle = 'rgba(80,60,40,0.35)';
  ctx.lineWidth = 2;
  for (let k = 0; k <= 4; k++) {
    ctx.beginPath();
    ctx.moveTo(k * 64, 0);
    ctx.lineTo(k * 64, W);
    ctx.moveTo(0, k * 64);
    ctx.lineTo(W, k * 64);
    ctx.stroke();
  }
  const img = ctx.getImageData(0, 0, W, W);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (r() - 0.5) * 14;
    img.data[i] += n;
    img.data[i + 1] += n;
    img.data[i + 2] += n;
  }
  ctx.putImageData(img, 0, 0);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(9, 9);
  t.anisotropy = 4;
  return t;
}

function stripeTexture(a: string, b: string, n = 8) {
  const c = document.createElement('canvas');
  c.width = 64;
  c.height = 64;
  const ctx = c.getContext('2d')!;
  for (let i = 0; i < n; i++) {
    ctx.fillStyle = i % 2 ? a : b;
    ctx.fillRect(0, (i * 64) / n, 64, 64 / n);
  }
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return t;
}

/** A cereal box: colored carton with a band and a big round logo. */
function cerealMat(main: string, band: string, logo: string, word: string) {
  const c = document.createElement('canvas');
  c.width = 128;
  c.height = 192;
  const ctx = c.getContext('2d')!;
  ctx.fillStyle = main;
  ctx.fillRect(0, 0, 128, 192);
  ctx.fillStyle = band;
  ctx.fillRect(0, 24, 128, 34);
  ctx.fillStyle = logo;
  ctx.beginPath();
  ctx.arc(64, 118, 38, 0, Math.PI * 2);
  ctx.fill();
  ctx.fillStyle = band.toLowerCase() === '#ffffff' || band.toLowerCase() === '#ffd23f' ? '#1d1d1f' : '#ffffff';
  ctx.font = 'bold 22px Arial Black, Arial, sans-serif';
  ctx.textAlign = 'center';
  ctx.fillText(word, 64, 49);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return new THREE.MeshStandardMaterial({ map: t, roughness: 0.75 });
}

export function buildKitchen(scene: THREE.Scene, phys: Physics): ArenaInfo {
  const root = new THREE.Group();
  root.name = 'arena';
  scene.add(root);
  const M = new EnvMats();
  const batch = new StaticBatcher();
  const B = new Builder(batch, phys);
  const animated: Animated[] = [];

  const tiles = new THREE.MeshStandardMaterial({ map: tileTexture(), roughness: 0.35 });
  const wallPaint = new THREE.MeshStandardMaterial({ color: '#fbe8c8', roughness: 0.9 });
  const backsplash = new THREE.MeshStandardMaterial({ map: stripeTexture('#bfe3e0', '#e8f6f4', 16), roughness: 0.3 });
  const cabinet = plastic('#5b8fb9', { rough: 0.5, clearcoat: 0.2 });
  const cabinetDark = plastic('#40698c', { rough: 0.5, clearcoat: 0.1 });
  const counterTop = new THREE.MeshStandardMaterial({ color: '#efe9e1', roughness: 0.35 });
  const steel = metal('#cfd5dc', 0.25);
  const darkSteel = metal('#6c757d', 0.35);
  const white = plastic('#fffdf5', { rough: 0.35 });
  const red = plastic('#e63946', { rough: 0.3 });
  const yellow = plastic('#ffd23f', { rough: 0.3 });
  const green = plastic('#2dc653', { rough: 0.35 });
  const orange = plastic('#ff8c1a', { rough: 0.45 });
  const wood = M.desk;

  // ---------------------------------------------------------------- FLOOR, WALLS, CEILING
  B.box([K.x0 - 2, -1, K.z0 - 2], [K.x1 + 2, 0, K.z1 + 2], tiles, 'wood');
  B.box([K.x0 - 1.5, 0, K.z0 - 1.5], [K.x1 + 1.5, K.wall, K.z0], wallPaint, 'wood');
  B.box([K.x0 - 1.5, 0, K.z1], [K.x1 + 1.5, K.wall, K.z1 + 1.5], wallPaint, 'wood');
  B.box([K.x0 - 1.5, 0, K.z0], [K.x0, K.wall, K.z1], wallPaint, 'wood');
  B.box([K.x1, 0, K.z0], [K.x1 + 1.5, K.wall, K.z1], wallPaint, 'wood');
  // the ceiling doesn't cast shadows so the "sunlight" still reaches the floor
  B.box([K.x0 - 1.5, K.wall, K.z0 - 1.5], [K.x1 + 1.5, K.wall + 1, K.z1 + 1.5], M.ceiling, 'wood', { cast: false });
  // baseboards
  for (const [a, b] of [[[K.x0, 0, K.z1 - 0.3], [K.x1, 0.8, K.z1]], [[K.x0, 0, K.z0], [K.x0 + 0.3, 0.8, K.z1]], [[K.x1 - 0.3, 0, K.z0], [K.x1, 0.8, K.z1]]] as const)
    B.box([...a] as [number, number, number], [...b] as [number, number, number], M.trim, null, { cast: false });
  // window over the sink (north wall), with a sunny view painted behind it
  B.box([4, 13, K.z0 + 0.05], [18, 23, K.z0 + 0.15], new THREE.MeshBasicMaterial({ color: '#9ad7ff' }), null, { cast: false });
  B.box([4, 13, K.z0 + 0.15], [18, 23, K.z0 + 0.3], M.glass, null, { cast: false });
  for (const [x0, y0, x1, y1] of [[3.6, 12.6, 18.4, 13], [3.6, 23, 18.4, 23.4], [3.6, 12.6, 4, 23.4], [18, 12.6, 18.4, 23.4], [10.8, 13, 11.2, 23]])
    B.box([x0, y0, K.z0 + 0.1], [x1, y1, K.z0 + 0.5], M.trim, null, { cast: false });
  // a wall clock and a calendar on the south wall (decor)
  B.cyl([0, 20, K.z1 - 0.3], 2.2, 0.25, white, null, 28);
  B.geo(new THREE.TorusGeometry(2.2, 0.18, 8, 32), red, [0, 20, K.z1 - 0.3]);
  B.box([10, 14, K.z1 - 0.2], [15, 21, K.z1 - 0.05], M.paper, null, { cast: false });

  // ---------------------------------------------------------------- NORTH COUNTER (long high lane)
  B.box([COUNTER.x0, 0, COUNTER.z0], [COUNTER.x1, K.deck - 0.4, COUNTER.z1 + 0.2], cabinet, 'wood');
  B.box([COUNTER.x0 - 0.3, K.deck - 0.4, COUNTER.z0], [COUNTER.x1, K.deck, COUNTER.z1 + 0.5], counterTop, 'wood');
  B.box([COUNTER.x0, 0, COUNTER.z1 + 0.15], [COUNTER.x1, 0.6, COUNTER.z1 + 0.35], cabinetDark, null, { cast: false });
  for (let x = COUNTER.x0 + 1; x < COUNTER.x1 - 1; x += 4.5) {
    B.box([x, 1, COUNTER.z1 + 0.2], [x + 4, K.deck - 1, COUNTER.z1 + 0.3], cabinetDark, null, { cast: false });
    B.box([x + 3.2, 4, COUNTER.z1 + 0.3], [x + 3.5, 5.5, COUNTER.z1 + 0.55], steel, null, { cast: false });
  }
  B.box([COUNTER.x0, K.deck, K.z0 + 0.01], [COUNTER.x1, 13, K.z0 + 0.2], backsplash, null, { cast: false });
  // sink (sunken basin) + faucet under the window
  B.box([6, K.deck - 0.05, -33], [16, K.deck + 0.02, -28], darkSteel, null, { cast: false });
  B.cyl([11, K.deck, -33.2], 0.35, 4, steel, 'plastic', 10);
  B.obox([11, K.deck + 4, -31.8], [0.5, 0.5, 3], new THREE.Euler(0, 0, 0), steel, null, 0.2);
  // things on the counter to fight around: toaster, blender, kettle, knife block
  B.box([-16, K.deck, -32.5], [-11, K.deck + 3.6, -29.5], red, 'plastic', { round: 0.5 });
  B.box([-15.2, K.deck + 3.6, -31.6], [-14, K.deck + 3.8, -30.4], darkSteel, null);
  B.box([-12.8, K.deck + 3.6, -31.6], [-11.8, K.deck + 3.8, -30.4], darkSteel, null);
  B.cyl([22, K.deck, -31], 1.6, 1.2, darkSteel, 'plastic', 18);
  B.cyl([22, K.deck + 1.2, -31], 1.3, 4.2, translucent('#cfefff', 0.4), 'glass', 18, 1.7);
  B.cyl([30, K.deck, -31], 1.8, 3.2, plastic('#2a9d8f', { rough: 0.3 }), 'plastic', 20, 1.4);
  B.box([-4, K.deck, -32.6], [-1, K.deck + 3.4, -29.6], wood, 'wood', { round: 0.2 });
  // cutting-board plank from the floor up to the counter (east end), with grip slats
  B.slab([25, 0, -11], [25, K.deck, -26.8], 3, 0.3, wood, 'wood');
  for (let i = 1; i < 12; i++) B.obox([25, (K.deck * i) / 12 + 0.08, -11 - (15.8 * i) / 12], [2.8, 0.1, 0.16], new THREE.Euler(-Math.atan2(K.deck, 15.8), 0, 0), M.trim, null);

  // ---------------------------------------------------------------- FRIDGE + FREEZER DRAWER (W)
  const fridge = plastic('#f1f3f5', { rough: 0.25, clearcoat: 0.6 });
  B.box([K.x0, 0, -14], [-26, 27, 6], fridge, 'metal', { round: 0.4 });
  B.box([-26.1, 4, -13.6], [-25.9, 4.15, 5.6], darkSteel, null, { cast: false });
  B.box([-25.9, 12, 3.6], [-25.2, 22, 4.4], steel, null);
  // magnets
  [['#ff5d8f', 10], ['#3a86ff', 16], ['#ffd23f', 19], ['#2dc653', 13]].forEach(([c, y], i) => B.box([-25.95, y as number, -10 + i * 2.8], [-25.7, (y as number) + 1.2, -9 + i * 2.8], plastic(c as string), null));
  // pulled-out freezer drawer: a walkable box with a lip
  B.box([-26, 0, -12], [-19, K.drawer, 4], plastic('#e9ecef', { rough: 0.3 }), 'metal', { round: 0.15 });
  B.box([-19.4, K.drawer, -12], [-19, K.drawer + 0.8, 4], plastic('#dee2e6', { rough: 0.3 }), 'metal');
  B.box([-19.2, 1.2, -6], [-18.6, 1.8, -2], steel, null);
  // frosty ice cubes in the drawer
  for (const [x, z] of [[-24, -9], [-22.5, -1], [-24.5, 2]]) B.box([x - 0.8, K.drawer, z - 0.8], [x + 0.8, K.drawer + 1.4, z + 0.8], translucent('#dff6ff', 0.55), 'glass', { round: 0.2 });
  // ramp up to the drawer, gap in the lip
  B.wedge([-12.4, 0, -4], -Math.PI / 2, 6.6, K.drawer, 4, M.bedWood, 'wood');
  B.box([-19.45, K.drawer - 0.01, -6], [-18.95, K.drawer + 0.85, -2], M.glass, null, { visual: false });

  // ---------------------------------------------------------------- STOVE + OPEN OVEN (E)
  B.box([27, 0, -4], [K.x1, K.deck, 12], plastic('#f8f9fa', { rough: 0.3, clearcoat: 0.5 }), 'metal');
  B.box([27, K.deck, -4], [K.x1, K.deck + 0.2, 12], plastic('#212529', { rough: 0.4 }), 'metal');
  for (const [x, z] of [[29.5, -1], [29.5, 7], [32, 3], [32, 9.5]]) {
    B.geo(new THREE.TorusGeometry(1.1, 0.12, 6, 20), darkSteel, [x, K.deck + 0.25, z], new THREE.Euler(Math.PI / 2, 0, 0));
  }
  // a pot of soup on the stove (steam comes off it)
  B.cyl([29.5, K.deck + 0.2, 7], 2, 3, plastic('#e76f51', { rough: 0.35 }), 'plastic', 22);
  B.box([26.9, 6, -3], [27.05, 7.4, 11], darkSteel, null, { cast: false });
  // oven cavity (dark) and the open door as a ledge
  B.box([28, 0.6, -2.4], [K.x1, 5.6, 10.4], plastic('#2b2d42', { rough: 0.8 }), null, { cast: false });
  for (const y of [2.2, 4]) for (let z = -2; z < 10.4; z += 1.2) B.box([28, y, z], [33.5, y + 0.08, z + 0.12], darkSteel, null, { cast: false });
  B.box([21, K.ovenDoor - 0.45, -2.5], [27, K.ovenDoor, 10.5], plastic('#f8f9fa', { rough: 0.3 }), 'metal');
  B.box([21.4, K.ovenDoor - 0.05, 0], [26.4, K.ovenDoor + 0.01, 8], M.glass, null, { cast: false });
  B.box([20.6, K.ovenDoor - 1, 0], [21, K.ovenDoor - 0.5, 8], steel, null);
  B.wedge([15.4, 0, 4], Math.PI / 2, 5.6, K.ovenDoor - 0.45, 3.6, M.bedWood, 'wood');

  // ---------------------------------------------------------------- KITCHEN ISLAND (center)
  B.box([ISLAND.x0 + 0.6, 0, ISLAND.z0 + 0.6], [ISLAND.x1 - 0.6, K.deck - 0.5, ISLAND.z1 - 0.6], cabinet, 'wood');
  B.box([ISLAND.x0, K.deck - 0.5, ISLAND.z0], [ISLAND.x1, K.deck, ISLAND.z1], counterTop, 'wood', { round: 0.15 });
  B.box([ISLAND.x0 + 0.6, 0, ISLAND.z0 + 0.6], [ISLAND.x1 - 0.6, 0.6, ISLAND.z1 - 0.6], cabinetDark, null, { cast: false });
  // fruit bowl and a cookie jar on the west half (the east half stays open for the lift)
  B.cyl([-4.4, K.deck, -2.6], 1.7, 1.2, plastic('#ffe8d6', { rough: 0.5 }), 'plastic', 24, 2.2);
  for (const [x, z, c] of [[-5, -3, orange], [-3.8, -2.1, orange], [-4.6, -1.9, red], [-3.9, -3.2, green]] as const)
    B.geo(new THREE.SphereGeometry(0.75, 14, 10), c, [x, K.deck + 1.7, z]);
  B.cyl([-4.8, K.deck, 4.6], 1.2, 3, translucent('#ffe8b0', 0.55), 'glass', 18, 1.05);
  B.cyl([-4.8, K.deck + 3, 4.6], 1.1, 0.45, wood, null, 18);
  // stools on the west side (stepping stones up)
  for (const z of [-1.5, 3.5]) {
    B.cyl([ISLAND.x0 - 2.6, 0, z], 0.3, 4.2, steel, 'metal', 8);
    B.cyl([ISLAND.x0 - 2.6, 4.2, z], 1.6, 0.6, red, 'plastic', 20);
  }
  // long cutting-board ramp from the south up onto the island
  B.wedge([0, 0, ISLAND.z1 + 13], Math.PI, 13, K.deck, 3.2, wood, 'wood');

  // ---------------------------------------------------------------- DINING TABLE + CHAIRS (SE)
  B.box([TABLE.x0, K.deck - 0.5, TABLE.z0], [TABLE.x1, K.deck, TABLE.z1], wood, 'wood', { tile: 1 / 8 });
  for (const x of [TABLE.x0 + 1, TABLE.x1 - 1]) for (const z of [TABLE.z0 + 1, TABLE.z1 - 1]) B.box([x - 0.5, 0, z - 0.5], [x + 0.5, K.deck - 0.5, z + 0.5], M.bedWood, 'wood');
  // tablecloth runner, plates, a milk carton, salt + pepper
  B.box([TABLE.x0 + 0.5, K.deck, 21.6], [TABLE.x1 - 0.5, K.deck + 0.03, 24.4], plastic('#3a86ff', { rough: 0.9, clearcoat: 0 }), null, { cast: false });
  for (const x of [15, 20, 25]) B.cyl([x, K.deck, 18.4], 1.6, 0.15, white, null, 22);
  B.box([16.5, K.deck, 25.5], [19, K.deck + 4.5, 28], new THREE.MeshStandardMaterial({ map: stripeTexture('#ffffff', '#3a86ff', 6), roughness: 0.7 }), 'cardboard');
  B.cyl([23, K.deck, 26.5], 0.7, 2.4, white, 'plastic', 12);
  B.cyl([24.8, K.deck, 26.5], 0.7, 2.4, darkSteel, 'plastic', 12);
  // chairs on the north side of the table: seat + back
  for (const x of [15.5, 24.5]) {
    B.box([x - 2, 0, 11.6], [x + 2, 4.2, 15.4], M.bedWood, 'wood');
    B.box([x - 2, 4.2, 11.4], [x + 2, 9.5, 12], M.bedWood, 'wood');
  }
  // plank up the west end of the table
  B.slab([-2, 0, 23], [TABLE.x0, K.deck, 23], 2.8, 0.3, M.bedWood, 'wood');
  for (let i = 1; i < 12; i++) B.obox([-2 + (14 * i) / 12, (K.deck * i) / 12 + 0.08, 23], [0.16, 0.1, 2.6], new THREE.Euler(0, 0, Math.atan2(K.deck, 14)), M.trim, null);

  // ---------------------------------------------------------------- CEREAL CITY (N, on the floor)
  const boxes: [number, number, number, number, number, THREE.Material][] = [
    [5, -24, 3, 5, 7, cerealMat('#ffb703', '#e63946', '#fb8500', 'CRUNCH')],
    [10.5, -22.5, 2.6, 4.4, 5, cerealMat('#8338ec', '#ffd23f', '#ff006e', 'LOOPS')],
    [16, -24.5, 3, 5, 8.5, cerealMat('#2a9d8f', '#ffd23f', '#e9c46a', 'OATIES')],
    [20.5, -21, 2.4, 4, 4, cerealMat('#e63946', '#ffffff', '#ffd23f', 'FLAKES')],
    [8, -16, 2.6, 4.2, 4.6, cerealMat('#3a86ff', '#ffd23f', '#ffffff', 'PUFFS')],
    [15.5, -15.5, 2.8, 4.4, 6, cerealMat('#fb5607', '#ffbe0b', '#3a86ff', 'BLASTS')],
  ];
  for (const [x, z, w, d, h, mat] of boxes) B.box([x - w / 2, 0, z - d / 2], [x + w / 2, h, z + d / 2], mat, 'cardboard');
  // spilled cereal + a tipped bowl
  const rr = seeded(5);
  for (let i = 0; i < 26; i++) B.geo(new THREE.TorusGeometry(0.3, 0.12, 6, 10), plastic(['#ff006e', '#ffbe0b', '#3a86ff', '#2dc653'][i % 4], { rough: 0.6 }), [11 + rr() * 8, 0.12, -20 + rr() * 6], new THREE.Euler(Math.PI / 2, 0, rr() * 3));
  B.geo(new THREE.SphereGeometry(2.2, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), white, [12.5, 0, -10.5], new THREE.Euler(Math.PI * 0.62, 0, 0.3));
  phys.cylinder(v3(12.5, 1, -10.5), 1, 2, 'plastic');

  // ---------------------------------------------------------------- PANTRY CORNER (SW)
  // big stock pot with a lid you can stand on, and a ramp up to it
  B.cyl([-25, 0, 25], 4.2, 5.2, steel, 'metal', 28);
  B.cyl([-25, 5.2, 25], 4.4, 0.35, darkSteel, 'metal', 28);
  B.cyl([-25, 5.55, 25], 0.6, 0.5, plastic('#1d1d1f'), null, 12);
  for (const s of [-1, 1]) B.box([-25 + s * 4.2 - (s > 0 ? 0 : 1), 3.8, 24.5], [-25 + s * 4.2 + (s > 0 ? 1 : 0), 4.2, 25.5], darkSteel, null);
  B.wedge([-25, 0, 13], 0, 7.6, 5.4, 3, M.bedWood, 'wood');
  // cans of soup and beans (cover)
  for (const [x, z, c] of [[-15, 28.5, '#e63946'], [-12.4, 29.5, '#2a9d8f'], [-14, 25.6, '#ffb703'], [-30.5, 11, '#e63946'], [-28, 12.8, '#3a86ff']] as const) {
    B.cyl([x, 0, z], 1.3, 3.2, plastic(c, { rough: 0.5 }), 'metal', 18);
    B.cyl([x, 3.2, z], 1.25, 0.06, steel, null, 18);
  }
  // colander dome
  B.geo(new THREE.SphereGeometry(3, 22, 12, 0, Math.PI * 2, 0, Math.PI / 2), plastic('#2dc653', { rough: 0.35 }), [-14, 0, 18]);
  phys.cylinder(v3(-14, 1.1, 18), 1.1, 2.6, 'plastic');
  // frying pan lying on the floor (low step + handle)
  B.cyl([-20, 0, 9], 3, 0.4, darkSteel, 'metal', 26);
  B.obox([-15.4, 0.25, 9], [3.6, 0.35, 0.7], new THREE.Euler(0, 0, 0), plastic('#1d1d1f', { rough: 0.6 }), null, 0.15);

  // ---------------------------------------------------------------- DOG CORNER (NW)
  const bowlC = { x: -18, z: -20 };
  for (let i = 0; i < 16; i++) {
    const a = (i / 16) * Math.PI * 2;
    B.obox([bowlC.x + Math.sin(a) * 3.6, 0.55, bowlC.z + Math.cos(a) * 3.6], [1.5, 1.1, 0.6], new THREE.Euler(0, a, 0), i % 2 ? red : plastic('#d62828', { rough: 0.3 }), 'plastic', 0.2);
  }
  B.cyl([bowlC.x, 0, bowlC.z], 3.3, 0.2, plastic('#c1121f'), null, 28);
  for (let i = 0; i < 18; i++) {
    const a = rr() * Math.PI * 2, d = rr() * 2.4;
    B.geo(new THREE.DodecahedronGeometry(0.4, 0), plastic('#8a5a2b', { rough: 0.9, clearcoat: 0 }), [bowlC.x + Math.cos(a) * d, 0.45, bowlC.z + Math.sin(a) * d], new THREE.Euler(rr(), rr(), rr()));
  }
  B.cyl([-26.5, 0, -24.5], 2.6, 0.9, plastic('#48cae4', { rough: 0.2 }), 'plastic', 24);
  B.box([-31, 0, -32], [-10, 0.06, -12], plastic('#bc6c25', { rough: 1, clearcoat: 0 }), null, { cast: false });
  // mop bucket (tall cover) and a squeaky bone
  B.cyl([-30, 0, -15], 2.2, 4.4, yellow, 'plastic', 20, 2.6);
  B.obox([-12, 0.5, -26], [3.2, 0.7, 0.8], new THREE.Euler(0, 0.6, 0), white, 'plastic', 0.3);

  // ---------------------------------------------------------------- MID-FLOOR COVER
  // lunchbox, a rolled-away orange, a toy block tower
  B.box([-11, 0, -12], [-6.5, 2.8, -8.5], plastic('#ff006e', { rough: 0.35 }), 'plastic', { round: 0.3 });
  B.geo(new THREE.SphereGeometry(1.4, 16, 12), orange, [7.5, 1.4, 11]);
  phys.cylinder(v3(7.5, 1.2, 11), 1.2, 1.3, 'plastic');
  B.brick([-6, 0, 13], [-3, 1.6, 16], '#3a86ff');
  B.brick([-5.6, 1.6, 13.4], [-3.4, 3.2, 15.6], '#ffd23f');
  B.brick([14, 0, 4], [16.4, 1.6, 7], '#2dc653');

  // ---------------------------------------------------------------- finish
  const blockSpots: THREE.Vector3[] = [];
  {
    const r = seeded(13);
    for (let i = 0; i < 12; i++) blockSpots.push(v3(-9 + r() * 3, 1 + (i % 3) * 0.7, 18 + r() * 3));
  }
  B.buildStuds(root);
  batch.build(root);
  phys.refreshQueries();
  const looseBricks = new LooseBricks(phys, blockSpots, root);
  animated.push(looseBricks);

  // ---------------------------------------------------------------- LIGHTING (afternoon light through the window)
  const sunDir = v3(-0.32, -0.8, 0.5).normalize();
  const sun = new THREE.DirectionalLight('#fff1d6', 4.2);
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
  const hemi = new THREE.HemisphereLight('#fff6e6', '#b08968', 1.0);
  root.add(hemi);
  const lamp = new THREE.PointLight('#ffe2b8', 30, 60, 1.6);
  lamp.position.set(0, 26, 0);
  root.add(lamp);

  // ---------------------------------------------------------------- GAMEPLAY DATA
  const zones: Zone[] = [
    { name: 'Counter', min: [-20, -34], max: [34, -26] },
    { name: 'Cereal City', min: [2, -26], max: [24, -12] },
    { name: 'Dog Corner', min: [-34, -34], max: [-8, -14] },
    { name: 'Fridge', min: [-34, -14], max: [-12, 8] },
    { name: 'Stove', min: [14, -6], max: [34, 12] },
    { name: 'Dining Table', min: [8, 12], max: [34, 34] },
    { name: 'Pantry', min: [-34, 8], max: [-6, 34] },
    { name: 'Kitchen Island', min: [-34, -34], max: [34, 34] },
  ].map((z, i) => ({ ...z, ambience: (['desk', 'brick', 'dino', 'closet', 'garage', 'bed', 'brick', 'rug'] as const)[i] }) as Zone);
  const ground = (x: number, z: number, fromY: number) => {
    const d = phys.rayDist(v3(x, fromY, z), v3(0, -1, 0), fromY + 2, true);
    return v3(x, d === Infinity ? 0 : fromY - d, z);
  };
  const pickupSpots: ArenaInfo['pickupSpots'] = [
    { kind: 'health', pos: ground(0, -14, 3) },
    { kind: 'health', pos: ground(-22.5, -8, 6) },
    { kind: 'health', pos: ground(24, 8, 4) },
    { kind: 'health', pos: ground(-16, 13, 3) },
    { kind: 'health', pos: ground(-20, -27, 3) },
    { kind: 'health', pos: ground(14, 9, 3) },
    { kind: 'health', pos: ground(20, 20, 10) },
    { kind: 'health', pos: ground(-5, -29.5, 10) },
    { kind: 'shield', pos: ground(2.5, -1, 10) },
    { kind: 'shield', pos: ground(-25, 25, 8) },
    { kind: 'turbo', pos: ground(-1, 26, 3) },
    { kind: 'infinite', pos: ground(13, -19, 3) },
    { kind: 'power', pos: ground(27.5, -30.5, 10) },
  ];

  return {
    root, zones, pickupSpots, weaponSpots: [], animated, sun, hemi, sunDir, pointLights: [lamp], looseBricks,
    bounds: { min: v3(K.x0, 0, K.z0), max: v3(K.x1, 28, K.z1) },
    window: { x0: 4, x1: 18, y0: 13, y1: 23, z: K.z0 },
  };
}

/** Kitchen background life: steam off the soup pot and a fly doing laps. No hazards. */
export class KitchenAmbient implements AmbientLike {
  ambienceOn = false;
  private puffs: { s: THREE.Sprite; t: number; life: number }[] = [];
  private fly: THREE.Group;
  private t = 0;
  private reduced = false;

  constructor(scene: THREE.Scene) {
    const dot = softDotTexture();
    for (let i = 0; i < 10; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: dot, color: '#ffffff', transparent: true, opacity: 0, depthWrite: false }));
      scene.add(s);
      this.puffs.push({ s, t: (i / 10) * 3, life: 3 });
    }
    this.fly = new THREE.Group();
    const body = new THREE.Mesh(new THREE.SphereGeometry(0.18, 8, 6), new THREE.MeshStandardMaterial({ color: '#1d1d1f' }));
    const wingMat = new THREE.MeshBasicMaterial({ color: '#dfe8ff', transparent: true, opacity: 0.6, side: THREE.DoubleSide });
    for (const s of [-1, 1]) {
      const w = new THREE.Mesh(new THREE.CircleGeometry(0.22, 8), wingMat);
      w.position.set(s * 0.2, 0.1, 0);
      w.rotation.x = -Math.PI / 2;
      this.fly.add(w);
    }
    this.fly.add(body);
    scene.add(this.fly);
  }

  update(dt: number) {
    this.t += dt;
    for (const p of this.puffs) {
      p.t += dt;
      if (p.t > p.life) p.t -= p.life;
      const k = p.t / p.life;
      p.s.position.set(29.5 + Math.sin(this.t * 0.7 + p.life * k * 3) * 0.6 * k, KITCHEN.deck + 3.4 + k * 7, 7 + Math.cos(this.t * 0.5 + k * 4) * 0.5 * k);
      p.s.scale.setScalar(1 + k * 3);
      (p.s.material as THREE.SpriteMaterial).opacity = Math.sin(k * Math.PI) * 0.35;
    }
    const a = this.t * (this.reduced ? 0.25 : 0.6);
    this.fly.position.set(Math.cos(a) * 9 + Math.sin(a * 2.7) * 2, 12 + Math.sin(a * 1.9) * 2, Math.sin(a * 1.3) * 9);
    this.fly.rotation.y = -a;
  }
  blockDrop() {}
  clearBlocks() {}
  startSounds() {}
  stopSounds() {}
  setReducedMotion(r: boolean) {
    this.reduced = r;
  }
}

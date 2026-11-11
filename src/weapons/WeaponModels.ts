import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { plastic, rubber, metal, glow } from '../render/materials';
import type { WeaponId } from './weaponConfig';

/**
 * Procedural toy weapon models. Barrel points down -Z, grip near the origin.
 * Named parts (userData.parts) drive the reload / fire animations:
 *   mag, charge, gear, gear2, chamber, spring, bolt, pump, drum, spin, wheel, core, rings, needle, pistons, shroud, holo, indicator, crayon
 * userData.muzzle: Object3D at the barrel tip.  userData.leftGrip / rightGrip: hand anchor points.
 */

export interface WeaponModel extends THREE.Group {
  userData: {
    parts: Record<string, THREE.Object3D>;
    muzzle: THREE.Object3D;
    leftGrip: THREE.Vector3;
    rightGrip: THREE.Vector3;
    adsOffset: THREE.Vector3; // where the sight sits relative to the model origin
    rest: Record<string, { p: THREE.Vector3; r: THREE.Euler; s: THREE.Vector3 }>;
    holo?: { canvas: HTMLCanvasElement; ctx: CanvasRenderingContext2D; tex: THREE.CanvasTexture; last: number };
    indicatorMat?: THREE.MeshStandardMaterial;
  };
}

const rb = (w: number, h: number, d: number, r = 0.015) => new RoundedBoxGeometry(w, h, d, 2, Math.min(r, w / 2.01, h / 2.01, d / 2.01));
const cyl = (r: number, len: number, seg = 16, r2?: number) => {
  const g = new THREE.CylinderGeometry(r2 ?? r, r, len, seg);
  g.rotateX(Math.PI / 2); // along z
  return g;
};
function m(g: THREE.BufferGeometry, mat: THREE.Material, p: [number, number, number] = [0, 0, 0], r: [number, number, number] = [0, 0, 0]) {
  const o = new THREE.Mesh(g, mat);
  o.position.set(...p);
  o.rotation.set(...r);
  return o;
}
function gear(radius: number, mat: THREE.Material, teeth = 8) {
  const g = new THREE.Group();
  g.add(m(new THREE.CylinderGeometry(radius, radius, 0.012, 16), mat, [0, 0, 0], [0, 0, Math.PI / 2]));
  for (let i = 0; i < teeth; i++) {
    const a = (i / teeth) * Math.PI * 2;
    g.add(m(new THREE.BoxGeometry(0.012, radius * 0.45, radius * 0.35), mat, [0, Math.cos(a) * radius, Math.sin(a) * radius], [a, 0, 0]));
  }
  return g;
}
function helix(len: number, radius: number, coils: number, thick: number) {
  const pts: THREE.Vector3[] = [];
  for (let i = 0; i <= coils * 12; i++) {
    const t = i / (coils * 12);
    const a = t * coils * Math.PI * 2;
    pts.push(new THREE.Vector3(Math.cos(a) * radius, Math.sin(a) * radius, -t * len));
  }
  return new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), coils * 12, thick, 6, false);
}
function seam(len: number, axis: 'z' | 'y' = 'z') {
  return axis === 'z' ? new THREE.BoxGeometry(0.003, 0.003, len) : new THREE.BoxGeometry(0.003, len, 0.003);
}
const seamMat = new THREE.MeshStandardMaterial({ color: '#000000', transparent: true, opacity: 0.35, roughness: 1 });

function finalize(g: THREE.Group, parts: Record<string, THREE.Object3D>, muzzle: [number, number, number], right: [number, number, number], left: [number, number, number], ads: [number, number, number]): WeaponModel {
  const mz = new THREE.Object3D();
  mz.position.set(...muzzle);
  g.add(mz);
  const w = g as WeaponModel;
  const rest: WeaponModel['userData']['rest'] = {};
  for (const [k, o] of Object.entries(parts)) rest[k] = { p: o.position.clone(), r: o.rotation.clone(), s: o.scale.clone() };
  w.userData = { ...w.userData, parts, muzzle: mz, rightGrip: new THREE.Vector3(...right), leftGrip: new THREE.Vector3(...left), adsOffset: new THREE.Vector3(...ads), rest };
  g.traverse((o) => {
    const mm = o as THREE.Mesh;
    if (mm.isMesh) {
      mm.castShadow = false;
      mm.receiveShadow = false;
    }
  });
  return w;
}

function holoDisplay(color: string) {
  const canvas = document.createElement('canvas');
  canvas.width = 128;
  canvas.height = 64;
  const ctx = canvas.getContext('2d')!;
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  const mat = new THREE.MeshBasicMaterial({ map: tex, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false, toneMapped: false, side: THREE.DoubleSide });
  void color;
  return { canvas, ctx, tex, mat, last: -1 };
}

export function buildWeaponModel(id: WeaponId): WeaponModel {
  const g = new THREE.Group();
  const parts: Record<string, THREE.Object3D> = {};
  switch (id) {
    case 'plasti9': {
      const teal = plastic('#1fb5ad', { rough: 0.3 });
      const orange = plastic('#ff8c1a', { rough: 0.3 });
      const grip = rubber('#20313a');
      g.add(m(rb(0.1, 0.11, 0.4, 0.03), teal, [0, 0.01, -0.12]));
      g.add(m(rb(0.085, 0.05, 0.36, 0.02), plastic('#16938c', { rough: 0.3 }), [0, 0.075, -0.13]));
      g.add(m(cyl(0.032, 0.14), orange, [0, 0.02, -0.38]));
      g.add(m(new THREE.TorusGeometry(0.035, 0.008, 6, 16), orange, [0, 0.02, -0.45]));
      g.add(m(rb(0.085, 0.2, 0.1, 0.03), grip, [0, -0.11, 0.04], [0.25, 0, 0]));
      for (let i = 0; i < 4; i++) g.add(m(new THREE.BoxGeometry(0.088, 0.01, 0.08), rubber('#2d4654'), [0, -0.05 - i * 0.04, 0.035 + i * 0.01], [0.25, 0, 0]));
      g.add(m(new THREE.TorusGeometry(0.045, 0.008, 6, 16, Math.PI), orange, [0, -0.05, -0.05], [0, Math.PI / 2, Math.PI]));
      const gr = gear(0.03, metal('#ffd166', 0.3), 8);
      gr.position.set(0.056, -0.03, -0.03);
      g.add(gr);
      parts.gear = gr;
      // translucent ammo indicator with a fill bar
      g.add(m(rb(0.012, 0.035, 0.2, 0.006), new THREE.MeshPhysicalMaterial({ color: '#bff9ff', transparent: true, opacity: 0.35, roughness: 0.05, clearcoat: 1 }), [0.052, 0.015, -0.14]));
      const indMat = new THREE.MeshStandardMaterial({ color: '#7dfff3', emissive: '#29e3d6', emissiveIntensity: 1.6 });
      const ind = m(new THREE.BoxGeometry(0.008, 0.024, 0.19), indMat, [0.053, 0.015, -0.14]);
      g.add(ind);
      parts.indicator = ind;
      g.add(m(seam(0.4), seamMat, [0.051, 0.055, -0.12]));
      g.add(m(seam(0.4), seamMat, [-0.051, 0.055, -0.12]));
      const mag = m(rb(0.06, 0.12, 0.07, 0.015), plastic('#ff8c1a', { rough: 0.4 }), [0, -0.2, 0.065], [0.25, 0, 0]);
      g.add(mag);
      parts.mag = mag;
      const slide = new THREE.Group();
      g.add(slide);
      parts.charge = slide;
      slide.add(m(rb(0.06, 0.03, 0.08, 0.01), teal, [0, 0.105, 0.03]));
      g.add(m(rb(0.01, 0.02, 0.01, 0.003), orange, [0, 0.115, -0.3]));
      const w = finalize(g, parts, [0, 0.02, -0.47], [0, -0.1, 0.06], [0, -0.13, 0.02], [0, -0.115, 0]);
      w.userData.indicatorMat = indMat;
      return w;
    }
    case 'walloper': {
      const purple = plastic('#7b2cbf', { rough: 0.28 });
      const dark = plastic('#3c1361', { rough: 0.35 });
      const gold = metal('#ffd23f', 0.25);
      const grip = rubber('#24112f');
      // frame and top strap
      g.add(m(rb(0.13, 0.13, 0.36, 0.035), purple, [0, 0.01, -0.08]));
      g.add(m(rb(0.1, 0.05, 0.42, 0.02), dark, [0, 0.09, -0.12]));
      // long heavy barrel with a gold muzzle ring and vent ports
      g.add(m(rb(0.085, 0.085, 0.36, 0.025), purple, [0, 0.03, -0.42]));
      g.add(m(cyl(0.03, 0.05), dark, [0, 0.03, -0.61]));
      g.add(m(new THREE.TorusGeometry(0.042, 0.012, 8, 18), gold, [0, 0.03, -0.6]));
      for (let i = 0; i < 4; i++) g.add(m(new THREE.BoxGeometry(0.087, 0.012, 0.03), dark, [0, 0.074, -0.3 - i * 0.07]));
      // big drum-style cylinder (just for looks) with gold studs
      g.add(m(cyl(0.07, 0.13, 18), dark, [0, 0.02, -0.03]));
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2;
        g.add(m(new THREE.SphereGeometry(0.014, 8, 6), gold, [Math.cos(a) * 0.072, 0.02 + Math.sin(a) * 0.072, -0.03]));
      }
      // grip, trigger guard, sights
      g.add(m(rb(0.09, 0.22, 0.11, 0.035), grip, [0, -0.13, 0.08], [0.3, 0, 0]));
      for (let i = 0; i < 4; i++) g.add(m(new THREE.BoxGeometry(0.093, 0.012, 0.09), rubber('#3b1d4a'), [0, -0.07 - i * 0.045, 0.075 + i * 0.012], [0.3, 0, 0]));
      g.add(m(new THREE.TorusGeometry(0.048, 0.009, 6, 16, Math.PI), gold, [0, -0.065, -0.03], [0, Math.PI / 2, Math.PI]));
      g.add(m(rb(0.016, 0.03, 0.02, 0.004), gold, [0, 0.13, -0.56]));
      g.add(m(rb(0.05, 0.028, 0.02, 0.006), gold, [0, 0.13, 0.05]));
      // magazine in the grip (3 big rounds)
      const mag = m(rb(0.07, 0.12, 0.08, 0.018), plastic('#ffd23f', { rough: 0.35 }), [0, -0.23, 0.11], [0.3, 0, 0]);
      g.add(mag);
      parts.mag = mag;
      // hammer: cocks back at the end of a reload
      const hammer = new THREE.Group();
      hammer.add(m(rb(0.04, 0.07, 0.03, 0.01), gold, [0, 0.11, 0.1], [-0.4, 0, 0]));
      g.add(hammer);
      parts.charge = hammer;
      g.add(m(seam(0.36), seamMat, [0.066, 0.06, -0.08]));
      g.add(m(seam(0.36), seamMat, [-0.066, 0.06, -0.08]));
      return finalize(g, parts, [0, 0.03, -0.64], [0, -0.12, 0.09], [0, -0.15, 0.05], [0, -0.135, 0]);
    }
    case 'foamFury': {
      const orange = plastic('#ff7a1a', { rough: 0.3 });
      const blue = plastic('#2f6fe0', { rough: 0.3 });
      g.add(m(rb(0.12, 0.15, 0.6, 0.04), orange, [0, 0, -0.15]));
      g.add(m(rb(0.13, 0.05, 0.3, 0.02), blue, [0, 0.085, -0.05]));
      g.add(m(cyl(0.035, 0.22), orange, [0, 0.01, -0.54]));
      g.add(m(new THREE.TorusGeometry(0.04, 0.012, 6, 16), blue, [0, 0.01, -0.64]));
      g.add(m(rb(0.08, 0.18, 0.09, 0.03), rubber('#1d3557'), [0, -0.13, 0.06], [0.3, 0, 0]));
      g.add(m(rb(0.1, 0.12, 0.22, 0.04), blue, [0, -0.01, 0.24]));
      g.add(m(rb(0.06, 0.14, 0.05, 0.02), blue, [0, -0.08, -0.36]));
      // oversized foam dart magazine
      const mag = new THREE.Group();
      mag.position.set(0, -0.15, -0.18);
      mag.add(m(rb(0.1, 0.26, 0.14, 0.03), blue));
      for (let i = 0; i < 3; i++) mag.add(m(new THREE.SphereGeometry(0.018, 8, 6), plastic('#ff7a1a'), [-0.03 + i * 0.03, 0.13, -0.04]));
      g.add(mag);
      parts.mag = mag;
      // translucent dart chamber on top with darts inside
      const chamber = new THREE.Group();
      chamber.position.set(0, 0.12, -0.2);
      chamber.add(m(cyl(0.05, 0.16), new THREE.MeshPhysicalMaterial({ color: '#d7f2ff', transparent: true, opacity: 0.3, roughness: 0.05, clearcoat: 1, depthWrite: false })));
      for (let i = 0; i < 6; i++) {
        const a = (i / 6) * Math.PI * 2;
        chamber.add(m(cyl(0.012, 0.14), plastic(i % 2 ? '#2f6fe0' : '#ff7a1a'), [Math.cos(a) * 0.028, Math.sin(a) * 0.028, 0]));
      }
      g.add(chamber);
      parts.chamber = chamber;
      const g1 = gear(0.04, metal('#ffd166', 0.3), 10);
      g1.position.set(0.064, 0.01, -0.02);
      g.add(g1);
      parts.gear = g1;
      const g2 = gear(0.028, metal('#c0c0c0', 0.3), 8);
      g2.position.set(0.064, 0.045, -0.075);
      g.add(g2);
      parts.gear2 = g2;
      const charge = m(rb(0.03, 0.03, 0.06, 0.01), plastic('#ffd166'), [0.07, 0.06, 0.08]);
      g.add(charge);
      parts.charge = charge;
      g.add(m(seam(0.6), seamMat, [0.061, 0.0, -0.15]));
      g.add(m(new THREE.BoxGeometry(0.01, 0.04, 0.01), plastic('#1d3557'), [0, 0.12, -0.42]));
      return finalize(g, parts, [0, 0.01, -0.66], [0, -0.1, 0.07], [0, -0.09, -0.36], [0, -0.13, 0]);
    }
    case 'popcornPopper': {
      const yellow = plastic('#ffd23f', { rough: 0.3 });
      const red = plastic('#e63946', { rough: 0.3 });
      const white = plastic('#fffdf5', { rough: 0.35 });
      // red-and-white striped popcorn-box receiver
      g.add(m(rb(0.11, 0.14, 0.42, 0.03), white, [0, 0, -0.08]));
      for (let i = 0; i < 5; i++) g.add(m(rb(0.114, 0.144, 0.034, 0.008), red, [0, 0, -0.25 + i * 0.085]));
      g.add(m(rb(0.12, 0.035, 0.3, 0.012), yellow, [0, 0.085, -0.08]));
      // three stubby barrels in a triangle
      for (const [x, y] of [[0, 0.04], [-0.03, -0.012], [0.03, -0.012]]) {
        g.add(m(cyl(0.02, 0.26), yellow, [x, y, -0.4]));
        g.add(m(new THREE.TorusGeometry(0.022, 0.007, 6, 12), red, [x, y, -0.53]));
      }
      g.add(m(rb(0.1, 0.1, 0.05, 0.02), red, [0, 0.01, -0.29]));
      // clear hopper of popcorn kernels on top (the 'mag')
      const mag = new THREE.Group();
      mag.position.set(0, -0.15, -0.1);
      mag.add(m(rb(0.085, 0.22, 0.11, 0.025), yellow));
      mag.add(m(rb(0.09, 0.03, 0.115, 0.01), red, [0, -0.1, 0]));
      g.add(mag);
      parts.mag = mag;
      const hopper = new THREE.Group();
      hopper.position.set(0, 0.135, 0.02);
      hopper.add(m(new THREE.SphereGeometry(0.06, 16, 10, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.MeshPhysicalMaterial({ color: '#fff8dc', transparent: true, opacity: 0.32, roughness: 0.05, clearcoat: 1, depthWrite: false }), [0, -0.03, 0]));
      for (let i = 0; i < 7; i++) {
        const a = i * 2.4;
        hopper.add(m(new THREE.IcosahedronGeometry(0.016, 0), plastic(i % 3 ? '#fff3b0' : '#ffe066'), [Math.cos(a) * 0.028, -0.015 + (i % 3) * 0.012, Math.sin(a) * 0.028]));
      }
      g.add(hopper);
      parts.chamber = hopper;
      const charge = m(rb(0.03, 0.03, 0.06, 0.01), red, [0.065, 0.05, 0.06]);
      g.add(charge);
      parts.charge = charge;
      g.add(m(rb(0.075, 0.17, 0.085, 0.03), rubber('#7a1f2b'), [0, -0.13, 0.1], [0.3, 0, 0]));
      g.add(m(rb(0.09, 0.11, 0.2, 0.035), red, [0, -0.01, 0.23]));
      g.add(m(new THREE.BoxGeometry(0.012, 0.035, 0.012), red, [0, 0.12, -0.2]));
      g.add(m(seam(0.42), seamMat, [0.056, 0.0, -0.08]));
      return finalize(g, parts, [0, 0.01, -0.55], [0, -0.1, 0.11], [0, -0.06, -0.32], [0, -0.135, 0]);
    }
    case 'brickbreaker': {
      const black = plastic('#1d1d1f', { rough: 0.35 });
      const yellow = plastic('#ffcc00', { rough: 0.3 });
      const red = plastic('#ff3b30', { rough: 0.3 });
      // interlocking brick panels with studs
      for (let i = 0; i < 4; i++) {
        const col = i % 2 ? yellow : black;
        g.add(m(rb(0.13, 0.13, 0.16, 0.01), col, [0, 0, 0.12 - i * 0.16]));
        for (const x of [-0.03, 0.03]) g.add(m(new THREE.CylinderGeometry(0.018, 0.018, 0.02, 10), col, [x, 0.075, 0.12 - i * 0.16]));
      }
      g.add(m(rb(0.1, 0.1, 0.12, 0.01), black, [0, 0.0, 0.28]));
      g.add(m(rb(0.08, 0.16, 0.08, 0.02), rubber('#2b2b2b'), [0, -0.13, 0.08], [0.25, 0, 0]));
      const shroud = new THREE.Group();
      shroud.position.set(0, 0.0, -0.46);
      shroud.add(m(cyl(0.055, 0.2, 8), red));
      for (let i = 0; i < 4; i++) shroud.add(m(new THREE.BoxGeometry(0.012, 0.13, 0.04), black, [0, 0, -0.06 + i * 0.04], [0, 0, (i * Math.PI) / 4]));
      g.add(shroud);
      parts.shroud = shroud;
      g.add(m(cyl(0.025, 0.12), metal('#888'), [0, 0.0, -0.6]));
      const pistons = new THREE.Group();
      for (const s of [-1, 1]) {
        pistons.add(m(cyl(0.015, 0.2), metal('#c0c0c0', 0.25), [s * 0.075, 0.03, -0.12]));
        pistons.add(m(cyl(0.022, 0.06), yellow, [s * 0.075, 0.03, -0.24]));
      }
      g.add(pistons);
      parts.pistons = pistons;
      const mag = new THREE.Group();
      mag.position.set(0, -0.15, -0.08);
      mag.add(m(rb(0.08, 0.2, 0.12, 0.01), yellow, [0, 0, 0], [0.15, 0, 0]));
      mag.add(m(new THREE.CylinderGeometry(0.016, 0.016, 0.02, 8), yellow, [0, -0.11, 0.0]));
      g.add(mag);
      parts.mag = mag;
      const charge = m(rb(0.04, 0.03, 0.05, 0.01), red, [-0.08, 0.05, 0.05]);
      g.add(charge);
      parts.charge = charge;
      g.add(m(rb(0.03, 0.05, 0.03, 0.005), red, [0, 0.11, -0.3]));
      return finalize(g, parts, [0, 0.0, -0.67], [0, -0.1, 0.09], [0, -0.07, -0.3], [0, -0.125, 0]);
    }
    case 'bubbleBlaster': {
      const purple = new THREE.MeshPhysicalMaterial({ color: '#9b5de5', roughness: 0.15, clearcoat: 1, transparent: true, opacity: 0.82 });
      const pink = plastic('#f15bb5', { rough: 0.3 });
      g.add(m(rb(0.13, 0.14, 0.45, 0.05), purple, [0, 0, -0.1]));
      g.add(m(rb(0.08, 0.18, 0.09, 0.03), rubber('#3c096c'), [0, -0.13, 0.08], [0.3, 0, 0]));
      // wide circular barrel
      g.add(m(cyl(0.085, 0.2, 24, 0.07), purple, [0, 0.0, -0.42]));
      g.add(m(new THREE.TorusGeometry(0.085, 0.015, 8, 24), pink, [0, 0.0, -0.52]));
      // bubble chamber with swirling liquid
      const chamber = new THREE.Group();
      chamber.position.set(0, 0.12, -0.08);
      chamber.add(m(new THREE.SphereGeometry(0.085, 20, 14), new THREE.MeshPhysicalMaterial({ color: '#e0aaff', transparent: true, opacity: 0.35, roughness: 0.02, clearcoat: 1, depthWrite: false })));
      const swirl = m(new THREE.TorusKnotGeometry(0.035, 0.012, 48, 6, 2, 3), glow('#c77dff', 1.6));
      chamber.add(swirl);
      g.add(chamber);
      parts.chamber = swirl;
      // pressure meter
      g.add(m(new THREE.CylinderGeometry(0.03, 0.03, 0.01, 20), glow('#fff3b0', 0.8), [0.068, 0.03, 0.04], [0, 0, Math.PI / 2]));
      const needle = new THREE.Group();
      needle.position.set(0.075, 0.03, 0.04);
      needle.add(m(new THREE.BoxGeometry(0.002, 0.022, 0.003), plastic('#d00000'), [0, 0.01, 0]));
      g.add(needle);
      parts.needle = needle;
      const pump = m(rb(0.09, 0.07, 0.14, 0.03), pink, [0, -0.08, -0.3]);
      g.add(pump);
      parts.pump = pump;
      const shellPort = m(rb(0.03, 0.05, 0.08, 0.01), pink, [-0.066, -0.02, -0.12]);
      g.add(shellPort);
      parts.mag = shellPort;
      return finalize(g, parts, [0, 0.0, -0.54], [0, -0.1, 0.08], [0, -0.1, -0.3], [0, -0.11, 0]);
    }
    case 'thunderspring': {
      const cobalt = plastic('#1f4fd1', { rough: 0.25 });
      const gold = metal('#f2c94c', 0.25);
      const silver = metal('#d6dbe3', 0.2);
      g.add(m(rb(0.09, 0.1, 0.62, 0.03), cobalt, [0, 0, -0.18]));
      g.add(m(cyl(0.03, 0.42), cobalt, [0, 0.01, -0.68]));
      g.add(m(new THREE.TorusGeometry(0.034, 0.01, 6, 16), gold, [0, 0.01, -0.9]));
      g.add(m(rb(0.08, 0.14, 0.26, 0.04), cobalt, [0, -0.03, 0.25]));
      g.add(m(rb(0.07, 0.17, 0.08, 0.02), rubber('#1b263b'), [0, -0.12, 0.06], [0.3, 0, 0]));
      for (const s of [-1, 1]) g.add(m(cyl(0.006, 0.55), silver, [s * 0.05, 0.04, -0.4]));
      const spring = new THREE.Group();
      spring.position.set(0.0, -0.06, -0.12);
      spring.add(m(helix(0.36, 0.028, 9, 0.006), gold));
      g.add(spring);
      parts.spring = spring;
      // telescopic scope
      const scope = new THREE.Group();
      scope.position.set(0, 0.11, -0.12);
      scope.add(m(cyl(0.03, 0.3), plastic('#14213d', { rough: 0.25 })));
      scope.add(m(cyl(0.038, 0.05), cobalt, [0, 0, -0.15]));
      scope.add(m(cyl(0.034, 0.04), cobalt, [0, 0, 0.14]));
      scope.add(m(new THREE.CircleGeometry(0.03, 16), new THREE.MeshPhysicalMaterial({ color: '#ff4d6d', roughness: 0.05, clearcoat: 1, emissive: '#ff4d6d', emissiveIntensity: 0.4 }), [0, 0, -0.176], [0, Math.PI, 0]));
      scope.add(m(rb(0.02, 0.05, 0.02, 0.005), silver, [0, -0.045, -0.05]));
      scope.add(m(rb(0.02, 0.05, 0.02, 0.005), silver, [0, -0.045, 0.06]));
      g.add(scope);
      parts.scope = scope;
      const bolt = new THREE.Group();
      bolt.position.set(0.06, 0.03, 0.06);
      bolt.add(m(cyl(0.008, 0.06), silver, [0.02, 0, 0], [0, Math.PI / 2, 0]));
      bolt.add(m(new THREE.SphereGeometry(0.018, 10, 8), gold, [0.05, 0, 0]));
      g.add(bolt);
      parts.bolt = bolt;
      const mag = m(rb(0.06, 0.08, 0.1, 0.01), gold, [0, -0.085, -0.06]);
      g.add(mag);
      parts.mag = mag;
      return finalize(g, parts, [0, 0.01, -0.92], [0, -0.1, 0.08], [0, -0.06, -0.42], [0, -0.21, 0.12]);
    }
    case 'rapidRascal': {
      const green = plastic('#39ff88', { rough: 0.3 });
      const pink = plastic('#ff4fd8', { rough: 0.3 });
      g.add(m(rb(0.11, 0.13, 0.38, 0.04), green, [0, 0, -0.08]));
      g.add(m(rb(0.115, 0.04, 0.3, 0.02), pink, [0, 0.07, -0.1]));
      g.add(m(rb(0.08, 0.17, 0.08, 0.03), rubber('#3a0ca3'), [0, -0.12, 0.06], [0.25, 0, 0]));
      // translucent side panels
      for (const s of [-1, 1]) g.add(m(rb(0.006, 0.07, 0.16, 0.003), new THREE.MeshPhysicalMaterial({ color: '#b9fbc0', transparent: true, opacity: 0.4, roughness: 0.05, clearcoat: 1 }), [s * 0.057, 0, -0.1]));
      // spinning multi-barrel
      const spin = new THREE.Group();
      spin.position.set(0, 0.0, -0.33);
      for (let i = 0; i < 5; i++) {
        const a = (i / 5) * Math.PI * 2;
        spin.add(m(cyl(0.012, 0.16), metal('#d9d9d9', 0.25), [Math.cos(a) * 0.028, Math.sin(a) * 0.028, -0.02]));
      }
      spin.add(m(cyl(0.045, 0.02), pink, [0, 0, 0.04]));
      spin.add(m(cyl(0.045, 0.02), pink, [0, 0, -0.09]));
      g.add(spin);
      parts.spin = spin;
      // drum magazine
      const drum = new THREE.Group();
      drum.position.set(0, -0.13, -0.12);
      const d = m(new THREE.CylinderGeometry(0.085, 0.085, 0.07, 24), pink, [0, 0, 0], [0, 0, Math.PI / 2]);
      drum.add(d);
      drum.add(m(new THREE.CylinderGeometry(0.03, 0.03, 0.075, 12), green, [0, 0, 0], [0, 0, Math.PI / 2]));
      g.add(drum);
      parts.mag = drum;
      parts.drum = d;
      // LEDs
      const leds = new THREE.Group();
      for (let i = 0; i < 4; i++) leds.add(m(new THREE.SphereGeometry(0.008, 8, 6), glow(['#ff006e', '#ffbe0b', '#3a86ff', '#06d6a0'][i], 3), [0.058, 0.03, -0.02 - i * 0.04]));
      g.add(leds);
      parts.leds = leds;
      // star decal
      g.add(m(new THREE.CircleGeometry(0.02, 5), plastic('#ffbe0b'), [-0.057, 0.0, 0.03], [0, -Math.PI / 2, 0]));
      const charge = m(rb(0.03, 0.025, 0.04, 0.008), pink, [0, 0.1, 0.06]);
      g.add(charge);
      parts.charge = charge;
      return finalize(g, parts, [0, 0.0, -0.44], [0, -0.1, 0.07], [0, -0.13, -0.15], [0, -0.11, 0]);
    }
    case 'crayonCannon': {
      const red = plastic('#e63946', { rough: 0.3 });
      const yellow = plastic('#ffd23f', { rough: 0.3 });
      g.add(m(cyl(0.11, 0.7, 24), red, [0, 0.04, -0.22]));
      g.add(m(new THREE.TorusGeometry(0.11, 0.022, 10, 24), yellow, [0, 0.04, -0.57]));
      g.add(m(new THREE.TorusGeometry(0.11, 0.018, 10, 24), yellow, [0, 0.04, 0.12]));
      // paint splatters
      const cols = ['#06d6a0', '#118ab2', '#ffd23f', '#ef476f', '#8338ec'];
      for (let i = 0; i < 9; i++) {
        const a = Math.random() * Math.PI * 2;
        g.add(m(new THREE.SphereGeometry(0.018 + Math.random() * 0.02, 8, 6), plastic(cols[i % 5]), [Math.cos(a) * 0.105, 0.04 + Math.sin(a) * 0.105, -0.5 + Math.random() * 0.55], [0, 0, 0]));
      }
      g.add(m(rb(0.08, 0.18, 0.09, 0.03), rubber('#2b2d42'), [0, -0.14, 0.04], [0.25, 0, 0]));
      g.add(m(rb(0.07, 0.15, 0.07, 0.03), rubber('#2b2d42'), [0, -0.12, -0.3], [-0.1, 0, 0]));
      // color selector wheel
      const wheel = new THREE.Group();
      wheel.position.set(0.11, 0.04, -0.02);
      for (let i = 0; i < 5; i++) {
        wheel.add(m(new THREE.CylinderGeometry(0.06, 0.06, 0.015, 12, 1, false, (i / 5) * Math.PI * 2, (Math.PI * 2) / 5), plastic(cols[i]), [0, 0, 0], [0, 0, Math.PI / 2]));
      }
      g.add(wheel);
      parts.wheel = wheel;
      // pressure gauges
      for (const [z, n] of [[0.02, 'needle'], [-0.12, 'needle2']] as const) {
        g.add(m(new THREE.CylinderGeometry(0.032, 0.032, 0.02, 16), plastic('#ffffff'), [-0.1, 0.12, z], [0, 0, 0.5]));
        const nd = new THREE.Group();
        nd.position.set(-0.106, 0.133, z);
        nd.rotation.z = 0.5;
        nd.add(m(new THREE.BoxGeometry(0.003, 0.004, 0.024), plastic('#d00000'), [0, 0, 0.0]));
        g.add(nd);
        parts[n] = nd;
      }
      // giant crayon visible in the tube
      const crayon = new THREE.Group();
      crayon.position.set(0, 0.04, -0.47);
      crayon.add(m(cyl(0.07, 0.2), plastic('#06d6a0', { rough: 0.6, clearcoat: 0 })));
      crayon.add(m(new THREE.ConeGeometry(0.07, 0.1, 16), plastic('#06d6a0', { rough: 0.6, clearcoat: 0 }), [0, 0, -0.15], [-Math.PI / 2, 0, 0]));
      g.add(crayon);
      parts.crayon = crayon;
      parts.mag = crayon;
      g.add(m(rb(0.04, 0.05, 0.04, 0.01), yellow, [0, 0.17, -0.3]));
      return finalize(g, parts, [0, 0.04, -0.6], [0, -0.1, 0.06], [0, -0.1, -0.3], [0, -0.21, 0]);
    }
    case 'starlightZapper': {
      const white = plastic('#f2f7ff', { rough: 0.2, clearcoat: 1 });
      const cyan = plastic('#21e6ff', { rough: 0.25 });
      g.add(m(rb(0.11, 0.12, 0.42, 0.05), white, [0, 0, -0.1]));
      g.add(m(rb(0.06, 0.05, 0.34, 0.02), cyan, [0, -0.07, -0.12]));
      g.add(m(rb(0.08, 0.17, 0.08, 0.03), rubber('#1b263b'), [0, -0.12, 0.08], [0.25, 0, 0]));
      g.add(m(cyl(0.028, 0.24), white, [0, 0.01, -0.4]));
      // power core
      g.add(m(new THREE.CapsuleGeometry(0.04, 0.12, 6, 12), new THREE.MeshPhysicalMaterial({ color: '#d6fbff', transparent: true, opacity: 0.35, roughness: 0.02, clearcoat: 1, depthWrite: false }), [0, 0.1, -0.03], [Math.PI / 2, 0, 0]));
      const core = m(new THREE.CapsuleGeometry(0.022, 0.1, 6, 10), glow('#5ff4ff', 3), [0, 0.1, -0.03], [Math.PI / 2, 0, 0]);
      g.add(core);
      parts.core = core;
      // electric arcs
      const arcs = new THREE.Group();
      for (let i = 0; i < 3; i++) {
        const pts = Array.from({ length: 6 }, (_, k) => new THREE.Vector3((Math.random() - 0.5) * 0.03, (Math.random() - 0.5) * 0.03, -k * 0.025));
        arcs.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts), new THREE.LineBasicMaterial({ color: '#bffcff', transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, toneMapped: false })));
      }
      arcs.position.set(0, 0.1, 0.04);
      g.add(arcs);
      parts.arcs = arcs;
      // rotating illuminated barrel rings
      const rings = new THREE.Group();
      rings.position.set(0, 0.01, -0.45);
      for (let i = 0; i < 3; i++) rings.add(m(new THREE.TorusGeometry(0.045, 0.007, 8, 24), glow('#21e6ff', 2.2), [0, 0, i * 0.05], [0, 0, i * 0.4]));
      g.add(rings);
      parts.rings = rings;
      // holographic ammo display
      const holo = holoDisplay('#5ff4ff');
      const plane = m(new THREE.PlaneGeometry(0.12, 0.06), holo.mat, [0.075, 0.07, 0.02], [0, Math.PI / 2 - 0.4, 0]);
      g.add(plane);
      parts.holo = plane;
      const w = finalize(g, parts, [0, 0.01, -0.53], [0, -0.1, 0.08], [0, -0.1, -0.2], [0, -0.12, 0]);
      w.userData.holo = { canvas: holo.canvas, ctx: holo.ctx, tex: holo.tex, last: -1 };
      return w;
    }
    case 'jackBlaster': {
      const red = plastic('#e63946', { rough: 0.3 });
      const yellow = plastic('#ffd23f', { rough: 0.3 });
      const white = plastic('#fff8ec', { rough: 0.35 });
      const blue = plastic('#3a86ff', { rough: 0.3 });
      // jack-in-the-box receiver with yellow trim and star stickers
      g.add(m(rb(0.15, 0.15, 0.2, 0.02), red, [0, 0.0, -0.02]));
      for (const y of [-0.074, 0.074]) for (const x of [-0.074, 0.074]) g.add(m(rb(0.012, 0.012, 0.205, 0.004), yellow, [x, y, -0.02]));
      for (const s of [-1, 1]) {
        const star = new THREE.Shape();
        for (let i = 0; i < 10; i++) {
          const a = (i / 10) * Math.PI * 2 + Math.PI / 2;
          const r = i % 2 ? 0.014 : 0.032;
          if (i === 0) star.moveTo(Math.cos(a) * r, Math.sin(a) * r);
          else star.lineTo(Math.cos(a) * r, Math.sin(a) * r);
        }
        g.add(m(new THREE.ShapeGeometry(star), yellow, [s * 0.0765, 0, -0.02], [0, (s * Math.PI) / 2, 0]));
      }
      // striped candy barrel
      g.add(m(cyl(0.042, 0.42), white, [0, 0.015, -0.33]));
      for (let i = 0; i < 4; i++) g.add(m(cyl(0.044, 0.035), red, [0, 0.015, -0.18 - i * 0.09]));
      // clown-collar muzzle
      g.add(m(new THREE.TorusGeometry(0.05, 0.016, 8, 20), yellow, [0, 0.015, -0.545]));
      for (let i = 0; i < 8; i++) {
        const a = (i / 8) * Math.PI * 2;
        g.add(m(new THREE.SphereGeometry(0.018, 8, 6), i % 2 ? blue : red, [Math.cos(a) * 0.066, 0.015 + Math.sin(a) * 0.066, -0.54]));
      }
      g.add(m(new THREE.SphereGeometry(0.012, 8, 6), yellow, [0, 0.07, -0.5]));
      // shell tube under the barrel (the 'mag')
      const mag = m(cyl(0.028, 0.26), yellow, [0, -0.055, -0.28]);
      g.add(mag);
      parts.mag = mag;
      // crank on the right side
      const crank = new THREE.Group();
      crank.position.set(0.09, 0.0, -0.02);
      crank.add(m(cyl(0.012, 0.04), metal('#d6dbe3', 0.2), [0.01, 0, 0], [0, Math.PI / 2, 0]));
      crank.add(m(rb(0.012, 0.09, 0.02, 0.005), metal('#d6dbe3', 0.2), [0.03, -0.04, 0]));
      crank.add(m(new THREE.SphereGeometry(0.02, 10, 8), red, [0.045, -0.085, 0]));
      g.add(crank);
      parts.crank = crank;
      // the jack: a little clown on a spring, also the rear sight
      const jack = new THREE.Group();
      jack.position.set(0, 0.075, 0.03);
      jack.add(m(helix(0.07, 0.016, 5, 0.004), metal('#d6dbe3', 0.2), [0, 0, 0], [-Math.PI / 2, 0, 0]));
      jack.add(m(new THREE.SphereGeometry(0.03, 14, 10), white, [0, 0.09, 0]));
      jack.add(m(new THREE.SphereGeometry(0.01, 8, 6), red, [0, 0.088, -0.03]));
      jack.add(m(new THREE.ConeGeometry(0.024, 0.05, 12), blue, [0, 0.135, 0]));
      jack.add(m(new THREE.SphereGeometry(0.008, 6, 6), yellow, [0, 0.162, 0]));
      g.add(jack);
      parts.jack = jack;
      // grip + stock
      g.add(m(rb(0.075, 0.17, 0.08, 0.03), rubber('#1d3557'), [0, -0.12, 0.08], [0.3, 0, 0]));
      g.add(m(rb(0.07, 0.11, 0.2, 0.03), blue, [0, -0.02, 0.18]));
      g.add(m(rb(0.075, 0.13, 0.03, 0.01), red, [0, -0.02, 0.28]));
      return finalize(g, parts, [0, 0.015, -0.57], [0, -0.1, 0.08], [0, -0.075, -0.3], [0, -0.17, 0.06]);
    }
    case 'plungerBow': {
      const wood = plastic('#8d5a2b', { rough: 0.55, clearcoat: 0.2 });
      const pink = plastic('#ff4d6d', { rough: 0.3 });
      const teal = plastic('#2ec4b6', { rough: 0.3 });
      // riser (hand grip) with a wrap
      g.add(m(rb(0.045, 0.26, 0.06, 0.02), wood, [0, 0, 0]));
      g.add(m(rb(0.05, 0.09, 0.065, 0.02), pink, [0, -0.01, 0]));
      g.add(m(rb(0.02, 0.03, 0.03, 0.008), teal, [-0.03, 0.035, -0.005])); // arrow rest
      // limbs bend at the riser ends
      const limb = (sign: 1 | -1) => {
        const grp = new THREE.Group();
        grp.position.set(0, sign * 0.12, 0);
        const pts = [new THREE.Vector3(0, 0, 0), new THREE.Vector3(0, sign * 0.17, 0.02), new THREE.Vector3(0, sign * 0.33, 0.09), new THREE.Vector3(0, sign * 0.4, 0.15)];
        grp.add(m(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 16, 0.016, 8, false), teal));
        grp.add(m(new THREE.SphereGeometry(0.022, 10, 8), pink, [0, sign * 0.4, 0.15]));
        const tip = new THREE.Object3D();
        tip.position.set(0, sign * 0.4, 0.15);
        grp.add(tip);
        grp.userData.tip = tip;
        g.add(grp);
        return grp;
      };
      parts.limbU = limb(1);
      parts.limbL = limb(-1);
      // string: two thin segments, re-aimed every frame by the viewmodel
      const strMat = plastic('#f8f9fa', { rough: 0.6, clearcoat: 0 });
      const sGeo = new THREE.CylinderGeometry(0.003, 0.003, 1, 5);
      sGeo.translate(0, 0.5, 0);
      const sU = m(sGeo, strMat);
      const sL = m(sGeo, strMat);
      g.add(sU, sL);
      parts.stringU = sU;
      parts.stringL = sL;
      const nock = new THREE.Object3D();
      nock.position.set(0, 0, 0.15);
      g.add(nock);
      parts.nock = nock;
      // suction-cup arrow
      const arrow = new THREE.Group();
      arrow.position.set(0, 0.035, 0.15);
      arrow.add(m(cyl(0.008, 0.66), plastic('#ffffff', { rough: 0.4 }), [0, 0, -0.33]));
      arrow.add(m(new THREE.CylinderGeometry(0.035, 0.012, 0.035, 14).rotateX(Math.PI / 2), pink, [0, 0, -0.67]));
      for (const r of [0, Math.PI / 2]) arrow.add(m(rb(0.05, 0.003, 0.06, 0.001), teal, [0, 0, -0.04], [0, 0, r]));
      g.add(arrow);
      parts.arrow = arrow;
      // stringless model for third-person/pickups: draw the string once at rest
      const w = finalize(g, parts, [0, 0.035, -0.52], [0, -0.01, 0.17], [0, -0.02, 0], [0, -0.12, 0.12]);
      aimString(w, 0);
      return w;
    }
  }
}

const _t1 = new THREE.Vector3();
const _t2 = new THREE.Vector3();
const _up = new THREE.Vector3(0, 1, 0);
/** Bow: bend the limbs, pull the nock back and re-aim the two string segments. `draw` is 0..1. */
export function aimString(w: WeaponModel, draw: number) {
  const p = w.userData.parts;
  if (!p.limbU || !p.nock) return;
  p.limbU.rotation.x = draw * 0.32;
  p.limbL.rotation.x = -draw * 0.32;
  p.nock.position.z = 0.15 + draw * 0.3;
  if (p.arrow) p.arrow.position.z = p.nock.position.z;
  p.limbU.updateMatrix();
  p.limbL.updateMatrix();
  for (const [limb, seg] of [[p.limbU, p.stringU], [p.limbL, p.stringL]] as const) {
    const tip = limb.userData.tip as THREE.Object3D;
    _t1.copy(tip.position).applyMatrix4(limb.matrix);
    _t2.copy(p.nock.position).sub(_t1);
    const len = _t2.length();
    seg.position.copy(_t1);
    seg.quaternion.setFromUnitVectors(_up, _t2.divideScalar(len));
    seg.scale.set(1, len, 1);
  }
}

/** Update the holo display / indicator to reflect ammo. Cheap: only redraws on change. */
export function updateAmmoIndicator(w: WeaponModel, frac: number, value: number) {
  if (w.userData.indicatorMat) {
    const ind = w.userData.parts.indicator;
    ind.scale.z = Math.max(0.02, frac);
    ind.position.z = -0.14 + (1 - frac) * 0.095;
    w.userData.indicatorMat.emissiveIntensity = frac < 0.25 ? 2.5 : 1.6;
    w.userData.indicatorMat.color.set(frac < 0.25 ? '#ff6b6b' : '#7dfff3');
    w.userData.indicatorMat.emissive.set(frac < 0.25 ? '#ff2e2e' : '#29e3d6');
  }
  const h = w.userData.holo;
  if (h && h.last !== Math.round(value)) {
    h.last = Math.round(value);
    const { ctx } = h;
    ctx.clearRect(0, 0, 128, 64);
    ctx.fillStyle = frac < 0.25 ? '#ff7b9c' : '#7ff9ff';
    ctx.font = 'bold 34px "Baloo 2", monospace';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(String(h.last), 64, 26);
    ctx.fillRect(8, 52, 112 * frac, 6);
    ctx.strokeStyle = 'rgba(127,249,255,0.6)';
    ctx.strokeRect(8, 52, 112, 6);
    h.tex.needsUpdate = true;
  }
}


/**
 * Small optic that sits on the gun for the 'dot' and 'ring' scopes. Its hoop is centered on the gun's
 * sight line, so when you aim the lit reticle (drawn by the HUD) sits in the middle of it.
 */
export function buildOptic(kind: 'dot' | 'ring', sightY: number, color: string, accent: string): THREE.Group {
  const o = new THREE.Group();
  const body = plastic(color, { rough: 0.3 });
  const trim = plastic(accent, { rough: 0.3 });
  const r = kind === 'dot' ? 0.03 : 0.045;
  const hoop = new THREE.Mesh(new THREE.TorusGeometry(r, kind === 'dot' ? 0.007 : 0.006, 8, 28), body);
  o.add(hoop);
  const hood = new THREE.Mesh(new THREE.CylinderGeometry(r + 0.004, r + 0.004, kind === 'dot' ? 0.05 : 0.02, 24, 1, true), new THREE.MeshStandardMaterial({ color, roughness: 0.4, side: THREE.DoubleSide }));
  hood.rotation.x = Math.PI / 2;
  o.add(hood);
  const lens = new THREE.Mesh(new THREE.CircleGeometry(r, 24), new THREE.MeshPhysicalMaterial({ color: '#cfefff', transparent: true, opacity: 0.12, roughness: 0.02, clearcoat: 1, depthWrite: false, side: THREE.DoubleSide }));
  o.add(lens);
  // post down to the gun + two toy knobs
  const post = new THREE.Mesh(new THREE.BoxGeometry(0.022, 0.05, 0.04), trim);
  post.position.y = -r - 0.02;
  o.add(post);
  for (const s of [-1, 1]) {
    const knob = new THREE.Mesh(new THREE.CylinderGeometry(0.01, 0.01, 0.014, 10), trim);
    knob.rotation.z = Math.PI / 2;
    knob.position.set(s * (r + 0.012), 0, 0);
    o.add(knob);
  }
  o.position.set(0, sightY, 0.0);
  return o;
}

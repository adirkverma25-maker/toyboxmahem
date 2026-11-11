import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { plastic, rubber, glow, metal } from '../render/materials';
import { clamp, damp } from '../core/math';
import { mergeDirectChildren } from '../render/merge';

export type CharacterId =
  | 'captainClick' | 'rexRampage' | 'boltBuddy' | 'princessPanic' | 'turboTim' | 'mechaMax' | 'blockhead'
  | 'sergeantSnap' | 'dinaMite' | 'sparky' | 'duchessDazzle' | 'nitroNina' | 'gearboxGus' | 'brickette'
  | 'player';

export interface Hitbox {
  headY: number; // head sphere center above feet (standing)
  headR: number;
  bodyBottom: number;
  bodyTop: number;
  bodyR: number;
}

export interface CharacterDef {
  id: CharacterId;
  name: string;
  colors: string[]; // debris palette
  accent: string; // kill feed / name color
  hitbox: Hitbox;
  voicePitch: number;
  /** variants reuse another toy's body with new paint (old hex -> new hex) and a small extra */
  base?: CharacterId;
  recolor?: Record<string, string>;
}

export const CHARACTERS: Record<CharacterId, CharacterDef> = {
  captainClick: { id: 'captainClick', name: 'Captain Click', colors: ['#5b7a3a', '#7c9a52', '#3e5527', '#c9b27c'], accent: '#8fbf5a', hitbox: { headY: 1.56, headR: 0.27, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.36 }, voicePitch: 0.9 },
  rexRampage: { id: 'rexRampage', name: 'Rex Rampage', colors: ['#3fae49', '#f4a261', '#2d6a4f', '#ffffff'], accent: '#5cd65c', hitbox: { headY: 1.58, headR: 0.32, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.4 }, voicePitch: 0.7 },
  boltBuddy: { id: 'boltBuddy', name: 'Bolt Buddy', colors: ['#b8c4d6', '#3a86ff', '#e0e7ff', '#ffbe0b'], accent: '#5aa9ff', hitbox: { headY: 1.55, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.36 }, voicePitch: 1.4 },
  princessPanic: { id: 'princessPanic', name: 'Princess Panic', colors: ['#ff70a6', '#c77dff', '#ffd670', '#ffffff'], accent: '#ff8fc7', hitbox: { headY: 1.55, headR: 0.27, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.36 }, voicePitch: 1.5 },
  turboTim: { id: 'turboTim', name: 'Turbo Tim', colors: ['#e63946', '#ffffff', '#1d3557', '#ffd166'], accent: '#ff5c5c', hitbox: { headY: 1.56, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.35 }, voicePitch: 1.15 },
  mechaMax: { id: 'mechaMax', name: 'Mecha Max', colors: ['#4a4e69', '#ffb703', '#22223b', '#9a8c98'], accent: '#ffc23d', hitbox: { headY: 1.58, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.32, bodyR: 0.42 }, voicePitch: 0.6 },
  blockhead: { id: 'blockhead', name: 'Blockhead', colors: ['#d6342c', '#f2c12e', '#1f6fd1', '#2f9e44'], accent: '#ff9f1c', hitbox: { headY: 1.56, headR: 0.3, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.38 }, voicePitch: 1.0 },
  sergeantSnap: { id: 'sergeantSnap', name: 'Sergeant Snap', base: 'captainClick', recolor: { '#5b7a3a': '#c2a36b', '#3e5527': '#7a5c33', '#c9b27c': '#3b3024' }, colors: ['#c2a36b', '#7a5c33', '#3b3024', '#ffd8b5'], accent: '#e7c98a', hitbox: { headY: 1.56, headR: 0.27, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.36 }, voicePitch: 0.8 },
  dinaMite: { id: 'dinaMite', name: 'Dina-Mite', base: 'rexRampage', recolor: { '#3fae49': '#9b5de5', '#f4c27a': '#fee440', '#f77f00': '#00f5d4', '#2d6a4f': '#5a189a', '#1b4332': '#240046' }, colors: ['#9b5de5', '#fee440', '#5a189a', '#00f5d4'], accent: '#c39bff', hitbox: { headY: 1.58, headR: 0.32, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.4 }, voicePitch: 0.85 },
  sparky: { id: 'sparky', name: 'Sparky', base: 'boltBuddy', recolor: { '#b8c4d6': '#ffd60a', '#3a86ff': '#ff006e' }, colors: ['#ffd60a', '#ff006e', '#fff3b0', '#3a86ff'], accent: '#ffe14d', hitbox: { headY: 1.55, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.36 }, voicePitch: 1.6 },
  duchessDazzle: { id: 'duchessDazzle', name: 'Duchess Dazzle', base: 'princessPanic', recolor: { '#ff70a6': '#2ec4b6', '#c77dff': '#3a0ca3', '#7b2cbf': '#f4a261', '#9d4edd': '#4361ee' }, colors: ['#2ec4b6', '#3a0ca3', '#f4a261', '#ffd670'], accent: '#5ef0e0', hitbox: { headY: 1.55, headR: 0.27, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.36 }, voicePitch: 1.35 },
  nitroNina: { id: 'nitroNina', name: 'Nitro Nina', base: 'turboTim', recolor: { '#e63946': '#2dc653', '#1d3557': '#3c096c' }, colors: ['#2dc653', '#ffffff', '#3c096c', '#ffd166'], accent: '#4dff88', hitbox: { headY: 1.56, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.28, bodyR: 0.35 }, voicePitch: 1.3 },
  gearboxGus: { id: 'gearboxGus', name: 'Gearbox Gus', base: 'mechaMax', recolor: { '#4a4e69': '#9d0208', '#ffb703': '#e9ecef', '#22223b': '#370617', '#ff4d6d': '#4dd6ff' }, colors: ['#9d0208', '#e9ecef', '#370617', '#4dd6ff'], accent: '#ff6b6b', hitbox: { headY: 1.58, headR: 0.28, bodyBottom: 0.15, bodyTop: 1.32, bodyR: 0.42 }, voicePitch: 0.55 },
  brickette: { id: 'brickette', name: 'Brickette', base: 'blockhead', recolor: { '#d6342c': '#2f9e44', '#1f6fd1': '#ff922b', '#f2c12e': '#e64980' }, colors: ['#2f9e44', '#ff922b', '#e64980', '#ffffff'], accent: '#69db7c', hitbox: { headY: 1.56, headR: 0.3, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.38 }, voicePitch: 1.2 },
  player: { id: 'player', name: 'You', colors: ['#1fb5ad', '#ff8c1a', '#ffffff', '#ffd23f'], accent: '#ffd23f', hitbox: { headY: 1.56, headR: 0.27, bodyBottom: 0.15, bodyTop: 1.3, bodyR: 0.36 }, voicePitch: 1.0 },
};

/** The original seven */
export const BOT_ROSTER: CharacterId[] = ['captainClick', 'rexRampage', 'boltBuddy', 'princessPanic', 'turboTim', 'mechaMax', 'blockhead'];
/** The seven newcomers (in Free-for-All they start on the high shelves) */
export const SHELF_ROSTER: CharacterId[] = ['sergeantSnap', 'dinaMite', 'sparky', 'duchessDazzle', 'nitroNina', 'gearboxGus', 'brickette'];
export const ALL_BOTS: CharacterId[] = [...BOT_ROSTER, ...SHELF_ROSTER];

export interface AnimState {
  speed: number; // horizontal m/s
  grounded: boolean;
  vy: number;
  crouch: number; // 0..1
  aimPitch: number; // radians
  reload: number; // 0 = not reloading, else 0..1 progress
  fireKick: number; // 0..1 decays
  hit: number; // 0..1 flinch
  dashing: boolean;
  sliding: boolean;
  protectedShimmer: boolean;
}

const SKIN = '#ffd8b5';
const _down = new THREE.Vector3(0, -1, 0);
const _dirR = new THREE.Vector3();
const _dirL = new THREE.Vector3();
const _tgt = new THREE.Vector3();
const _off = new THREE.Vector3();
const _shL = new THREE.Vector3();

function mesh(g: THREE.BufferGeometry, m: THREE.Material, pos?: [number, number, number], rot?: [number, number, number], scale?: [number, number, number]) {
  const o = new THREE.Mesh(g, m);
  if (pos) o.position.set(...pos);
  if (rot) o.rotation.set(...rot);
  if (scale) o.scale.set(...scale);
  o.castShadow = true;
  o.receiveShadow = true;
  return o;
}
const rbox = (w: number, h: number, d: number, r = 0.06) => new RoundedBoxGeometry(w, h, d, 2, Math.min(r, w / 2.01, h / 2.01, d / 2.01));
const sphere = (r: number, ws = 18, hs = 14) => new THREE.SphereGeometry(r, ws, hs);
const capsule = (r: number, l: number) => new THREE.CapsuleGeometry(r, l, 6, 14);

/**
 * Procedurally built and procedurally animated toy figure.
 * Hierarchy: root(yaw) > hips > torso > (neck > head), shoulders > arms; hips > legs.
 */
export class ToyRig {
  root = new THREE.Group();
  hips = new THREE.Group();
  torso = new THREE.Group();
  neck = new THREE.Group();
  head = new THREE.Group();
  armL = new THREE.Group();
  armR = new THREE.Group();
  foreL = new THREE.Group();
  foreR = new THREE.Group();
  legL = new THREE.Group();
  legR = new THREE.Group();
  shinL = new THREE.Group();
  shinR = new THREE.Group();
  weaponSocket = new THREE.Group();
  tail: THREE.Group | null = null;
  antenna: THREE.Group | null = null;
  cape: THREE.Mesh | null = null;
  eyes: THREE.Object3D[] = [];
  visor: THREE.Mesh | null = null;
  private phase = Math.random() * 10;
  private blinkT = Math.random() * 3;
  private idleT = Math.random() * 5;
  private smoothCrouch = 0;
  private smoothLean = 0;
  private outlineMeshes: THREE.Mesh[] = [];
  private shimmerMats: THREE.MeshPhysicalMaterial[] = [];
  scaleIn = 1;

  constructor(public def: CharacterDef) {
    this.root.add(this.hips);
    this.hips.position.y = 0.78;
    this.hips.add(this.torso, this.legL, this.legR);
    this.legL.position.set(-0.17, 0, 0);
    this.legR.position.set(0.17, 0, 0);
    this.torso.add(this.neck, this.armL, this.armR);
    this.neck.position.y = 0.58;
    this.neck.add(this.head);
    this.armL.position.set(-0.36, 0.48, 0);
    this.armR.position.set(0.36, 0.48, 0);
    this.armL.add(this.foreL);
    this.armR.add(this.foreR);
    this.foreL.position.y = -0.3;
    this.foreR.position.y = -0.3;
    this.foreR.add(this.weaponSocket);
    this.weaponSocket.position.set(0, -0.28, 0.06);
    this.legL.add(this.shinL);
    this.legR.add(this.shinR);
    this.shinL.position.y = -0.38;
    this.shinR.position.y = -0.38;
    BUILDERS[def.base ?? def.id](this);
    if (def.recolor) this.repaint(def.recolor);
    EXTRAS[def.id]?.(this);
    // fewer draw calls: merge same-material parts that move together
    mergeDirectChildren(this.root, (o) => o === this.visor || o === this.cape);
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh) {
        m.castShadow = true;
        m.receiveShadow = true;
      }
    });
  }

  /** materials this rig created for itself (shared cached plastics are never disposed) */
  private ownedMats = new Set<THREE.Material>();
  /** Free GPU memory when the match ends: every geometry is unique to the rig after merging. */
  dispose() {
    const geos = new Set<THREE.BufferGeometry>();
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (m.isMesh && m.geometry) geos.add(m.geometry);
    });
    for (const g of geos) g.dispose();
    for (const m of this.ownedMats) m.dispose();
    this.cloakMat?.dispose();
    this.ownedMats.clear();
  }

  /** Swap colors on every material whose base (or glow) color is in the map. Clones, never edits shared materials. */
  private repaint(map: Record<string, string>) {
    const norm: Record<string, string> = {};
    for (const [k, v] of Object.entries(map)) norm[k.toLowerCase().replace('#', '')] = v;
    const cache = new Map<THREE.Material, THREE.Material>();
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh) return;
      const mat = m.material as THREE.MeshStandardMaterial;
      if (!mat || !(mat as THREE.MeshStandardMaterial).color) return;
      let out = cache.get(mat);
      if (!out) {
        const c = mat.color.getHexString();
        const e = mat.emissive ? mat.emissive.getHexString() : '';
        if (norm[c] || (e && norm[e])) {
          const nm = mat.clone();
          this.ownedMats.add(nm);
          if (norm[c]) nm.color.set(norm[c]);
          if (e && norm[e]) nm.emissive.set(norm[e]);
          out = nm;
        } else out = mat;
        cache.set(mat, out);
      }
      m.material = out;
    });
  }

  // ---- Spring Punch glove (third person)
  private glove: THREE.Group | null = null;
  private gloveSpring: THREE.Mesh | null = null;
  private ensureGlove() {
    if (this.glove) return;
    const g = new THREE.Group();
    const red = plastic('#e63946', { rough: 0.3 });
    g.add(mesh(rbox(0.2, 0.18, 0.2, 0.08), red, [0, 0, 0]));
    const pts: THREE.Vector3[] = [];
    for (let i = 0; i <= 60; i++) {
      const a = (i / 60) * 6 * Math.PI * 2;
      pts.push(new THREE.Vector3(Math.cos(a) * 0.05, Math.sin(a) * 0.05, i / 60));
    }
    const spring = mesh(new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 60, 0.01, 4, false), metal('#d6dbe3', 0.2));
    spring.userData.noOutline = true;
    g.userData.noOutline = true;
    this.gloveSpring = spring;
    this.torso.add(g, spring);
    g.visible = spring.visible = false;
    this.glove = g;
  }
  /** t = seconds left on the punch (0.32 .. 0) */
  setPunch(t: number) {
    if (t <= 0 && !this.glove) return;
    this.ensureGlove();
    const on = t > 0;
    this.glove!.visible = this.gloveSpring!.visible = on;
    if (!on) return;
    const k = 1 - t / 0.32;
    const out = k < 0.3 ? k / 0.3 : Math.max(0, 1 - (k - 0.45) / 0.55);
    const reach = 0.15 + out * 0.75;
    this.glove!.position.set(-0.18, 0.4, 0.2 + reach);
    this.gloveSpring!.position.set(-0.18, 0.4, 0.2);
    this.gloveSpring!.scale.set(1, 1, reach);
  }

  // ---- Cloak: swap every material for a faint see-through one
  private cloakMat: THREE.MeshPhysicalMaterial | null = null;
  private cloakApplied = false;
  private outlineOn = false;
  /** opacity 0 = normal. Anything > 0 renders the toy as a ghostly shimmer at that opacity. */
  setCloak(opacity: number, t: number) {
    if (opacity <= 0) {
      if (!this.cloakApplied) return;
      this.cloakApplied = false;
      this.root.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && m.userData.preCloak) {
          m.material = m.userData.preCloak;
          m.castShadow = true;
          delete m.userData.preCloak;
        }
      });
      for (const o of this.outlineMeshes) o.visible = this.outlineOn;
      return;
    }
    if (!this.cloakMat) this.cloakMat = new THREE.MeshPhysicalMaterial({ color: '#dff1ff', transparent: true, opacity, roughness: 0.05, metalness: 0.3, clearcoat: 1, depthWrite: false, emissive: '#6fb8ff', emissiveIntensity: 0.2 });
    this.cloakMat.opacity = opacity * (0.75 + 0.25 * Math.sin(t * 7 + this.phase));
    this.cloakApplied = true;
    this.root.traverse((o) => {
      const m = o as THREE.Mesh;
      if (!m.isMesh || this.outlineMeshes.includes(m)) return;
      if (!m.userData.preCloak) {
        m.userData.preCloak = m.material;
        m.material = this.cloakMat!;
        m.castShadow = false;
      }
    });
    for (const o of this.outlineMeshes) o.visible = false;
  }

  /** Generic limbs shared by most humanoid toys. */
  limbs(body: THREE.Material, limb: THREE.Material, hand: THREE.Material, boot: THREE.Material, opts: { thick?: number; legLen?: number } = {}) {
    const t = opts.thick ?? 1;
    this.armL.add(mesh(capsule(0.085 * t, 0.2), limb, [0, -0.14, 0]));
    this.armR.add(mesh(capsule(0.085 * t, 0.2), limb, [0, -0.14, 0]));
    this.foreL.add(mesh(capsule(0.08 * t, 0.18), limb, [0, -0.12, 0]));
    this.foreR.add(mesh(capsule(0.08 * t, 0.18), limb, [0, -0.12, 0]));
    this.foreL.add(mesh(sphere(0.095 * t), hand, [0, -0.28, 0]));
    this.foreR.add(mesh(sphere(0.095 * t), hand, [0, -0.28, 0]));
    this.legL.add(mesh(capsule(0.11 * t, 0.22), body, [0, -0.18, 0]));
    this.legR.add(mesh(capsule(0.11 * t, 0.22), body, [0, -0.18, 0]));
    this.shinL.add(mesh(capsule(0.1 * t, 0.2), limb, [0, -0.14, 0]));
    this.shinR.add(mesh(capsule(0.1 * t, 0.2), limb, [0, -0.14, 0]));
    this.shinL.add(mesh(rbox(0.22 * t, 0.14, 0.34, 0.06), boot, [0, -0.33, 0.06]));
    this.shinR.add(mesh(rbox(0.22 * t, 0.14, 0.34, 0.06), boot, [0, -0.33, 0.06]));
    void body;
  }

  /** Cartoon eyes with pupils (blink by scaling). */
  addEyes(parent: THREE.Object3D, y: number, z: number, spread: number, size = 0.075, angry = 0) {
    const white = plastic('#ffffff', { rough: 0.2 });
    const black = plastic('#151515', { rough: 0.15 });
    for (const s of [-1, 1]) {
      const e = new THREE.Group();
      e.position.set(s * spread, y, z);
      e.add(mesh(sphere(size, 16, 12), white, [0, 0, 0], undefined, [1, 1.15, 0.6]));
      e.add(mesh(sphere(size * 0.55, 12, 10), black, [0, 0, size * 0.45]));
      e.add(mesh(sphere(size * 0.16, 8, 6), white, [size * 0.18, size * 0.22, size * 0.72]));
      if (angry) e.add(mesh(rbox(size * 2.2, size * 0.45, size * 0.5, 0.02), black, [0, size * 1.35, size * 0.2], [0, 0, -s * angry]));
      parent.add(e);
      this.eyes.push(e);
    }
  }

  private teamBand: THREE.Group | null = null;
  /** Team colors: a bright sash around the chest and a little pennant on the head. null removes it. */
  setTeam(color: string | null) {
    if (this.teamBand) {
      this.teamBand.userData.cleanup?.();
      this.teamBand.parent?.remove(this.teamBand);
      this.teamBand = null;
    }
    if (!color) return;
    const box = new THREE.Box3();
    for (const c of this.torso.children) if ((c as THREE.Mesh).isMesh) box.expandByObject(c);
    const size = box.getSize(new THREE.Vector3());
    const g = new THREE.Group();
    const mat = plastic(color, { rough: 0.3, emissive: color, emissiveIntensity: 0.6 });
    const band = new THREE.Mesh(new THREE.TorusGeometry(0.5, 0.1, 10, 28), mat);
    band.rotation.x = Math.PI / 2;
    band.scale.set(Math.max(0.3, size.x * 0.56 + 0.04), Math.max(0.25, size.z * 0.56 + 0.04), 1);
    band.position.y = 0.3;
    band.userData.noOutline = true;
    g.add(band);
    const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.6, 6), metal('#dddddd'));
    pole.position.set(0.14, 0.64, -0.12);
    const flag = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.22, 0.34), mat);
    flag.position.set(0.14, 0.82, -0.3);
    pole.userData.noOutline = flag.userData.noOutline = true;
    this.head.add(pole, flag);
    g.userData.extra = [pole, flag];
    this.torso.add(g);
    this.teamBand = g;
    g.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
    g.userData.cleanup = () => {
      pole.parent?.remove(pole);
      flag.parent?.remove(flag);
    };
  }

  setWeapon(model: THREE.Object3D | null) {
    this.weaponSocket.clear();
    if (model) {
      model.scale.setScalar(0.95);
      model.rotation.set(Math.PI / 2, Math.PI, 0);
      model.position.set(0, -0.02, 0.06);
      model.traverse((o) => {
        if ((o as THREE.Mesh).isMesh) (o as THREE.Mesh).castShadow = true;
      });
      this.weaponSocket.add(model);
    }
  }

  /** Inverted-hull outline for the accessibility option. */
  setOutline(on: boolean, color: string) {
    this.outlineOn = on;
    if (on && !this.outlineMeshes.length) {
      const mat = outlineMaterial(color);
      this.ownedMats.add(mat);
      const list: THREE.Mesh[] = [];
      this.root.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && !(m.userData.noOutline)) list.push(m);
      });
      for (const m of list) {
        const o = new THREE.Mesh(m.geometry, mat);
        o.userData.noOutline = true;
        o.castShadow = false;
        m.add(o);
        this.outlineMeshes.push(o);
      }
    }
    for (const o of this.outlineMeshes) {
      o.visible = on && !this.cloakApplied;
      (o.material as THREE.ShaderMaterial).uniforms.uColor.value.set(color);
    }
  }

  setShimmer(on: boolean, t: number) {
    if (!this.shimmerMats.length) {
      this.root.traverse((o) => {
        const m = o as THREE.Mesh;
        if (m.isMesh && !m.userData.preCloak && (m.material as THREE.MeshPhysicalMaterial).isMeshStandardMaterial) {
          // per-rig material clones so the shimmer doesn't affect other toys sharing materials
          const mm = (m.material as THREE.MeshPhysicalMaterial).clone();
          m.material = mm;
          this.shimmerMats.push(mm);
          this.ownedMats.add(mm);
          mm.userData.baseEmissive = mm.emissive.clone();
          mm.userData.baseEI = mm.emissiveIntensity;
        }
      });
    }
    for (const m of this.shimmerMats) {
      if (on) {
        m.emissive.set('#9fe8ff');
        m.emissiveIntensity = 0.35 + Math.sin(t * 18) * 0.25;
      } else {
        m.emissive.copy(m.userData.baseEmissive);
        m.emissiveIntensity = m.userData.baseEI;
      }
    }
  }

  update(dt: number, s: AnimState, time: number) {
    const moving = clamp(s.speed / 6, 0, 1.4);
    this.phase += dt * (3 + s.speed * 1.5);
    const ph = this.phase;
    this.smoothCrouch = damp(this.smoothCrouch, s.crouch, 12, dt);
    const c = this.smoothCrouch;
    // legs
    const swing = s.grounded ? Math.sin(ph) * 0.75 * moving : 0;
    const air = s.grounded ? 0 : 1;
    this.legL.rotation.x = swing + air * -0.5 - c * 1.1;
    this.legR.rotation.x = -swing + air * 0.3 - c * 1.1;
    this.shinL.rotation.x = (s.grounded ? Math.max(0, -Math.sin(ph)) * 0.9 * moving : 0.8) + c * 1.9;
    this.shinR.rotation.x = (s.grounded ? Math.max(0, Math.sin(ph)) * 0.9 * moving : 0.4) + c * 1.9;
    // body bob + lean
    const bob = s.grounded ? Math.abs(Math.sin(ph)) * 0.06 * moving : 0;
    this.hips.position.y = 0.78 - c * 0.36 + bob + (s.sliding ? -0.3 : 0);
    this.smoothLean = damp(this.smoothLean, clamp(s.speed * 0.03, 0, 0.25) + (s.dashing ? 0.35 : 0) + (s.sliding ? -0.5 : 0), 8, dt);
    this.torso.rotation.x = this.smoothLean + s.hit * -0.35 + c * 0.25;
    this.torso.rotation.y = Math.sin(ph) * 0.12 * moving;
    this.torso.rotation.z = s.hit * Math.sin(time * 40) * 0.08;
    // head follows aim pitch
    this.neck.rotation.x = clamp(-s.aimPitch, -0.6, 0.6) * 0.6 - this.smoothLean * 0.6;
    // arms: right holds the weapon at the aim, left reaches for the front grip; reload pulls the left hand to the gun
    const ap = clamp(s.aimPitch, -0.9, 0.9) - this.smoothLean * 0.6 + s.fireKick * 0.12;
    const cp = Math.cos(ap), sp = Math.sin(ap);
    _dirR.set(-0.12 * cp, sp, cp).normalize();
    this.armR.quaternion.setFromUnitVectors(_down, _dirR);
    this.foreR.rotation.set(-0.15, 0, 0);
    // left hand target: ahead of the right hand along the aim (torso space)
    _tgt.set(0.36, 0.48, 0).addScaledVector(_dirR, 0.55).add(_off.set(-0.02, 0.0, 0).addScaledVector(_dirR, 0.32));
    if (s.reload > 0) {
      const r = Math.sin(s.reload * Math.PI);
      _tgt.add(_off.set(-0.05, -0.18 * r, -0.25 * r));
    }
    _dirL.subVectors(_tgt, _shL.set(-0.36, 0.48, 0)).normalize();
    this.armL.quaternion.setFromUnitVectors(_down, _dirL);
    this.foreL.rotation.set(0, 0, 0);
    // personality idles
    this.idleT += dt;
    if (this.tail) this.tail.rotation.y = Math.sin(time * 3 + this.phase * 0.5) * (0.3 + moving * 0.3);
    if (this.antenna) this.antenna.rotation.z = Math.sin(time * 6) * 0.25 + Math.sin(ph) * 0.2 * moving;
    if (this.cape) {
      this.cape.rotation.x = 0.15 + moving * 0.45 + air * 0.4 + Math.sin(time * 4) * 0.05;
    }
    if (this.visor) {
      const m = this.visor.material as THREE.MeshStandardMaterial;
      m.emissiveIntensity = 1.8 + Math.sin(time * 5 + this.phase) * 0.6 + s.hit * 3;
    }
    if (moving < 0.1 && s.grounded && s.reload === 0) {
      // idle personality: little look-arounds and bounces
      const k = Math.sin(this.idleT * 0.9);
      this.neck.rotation.y = k * 0.35;
      this.hips.position.y += Math.sin(this.idleT * 2.2) * 0.012;
      if (this.def.id === 'princessPanic') this.torso.rotation.y = Math.sin(this.idleT * 1.7) * 0.25;
      if (this.def.id === 'rexRampage') this.neck.rotation.x += Math.sin(this.idleT * 3) * 0.08;
      if (this.def.id === 'boltBuddy') this.head.rotation.y = Math.sin(this.idleT * 0.7) * 0.6;
    } else {
      this.neck.rotation.y = damp(this.neck.rotation.y, 0, 6, dt);
      this.head.rotation.y = damp(this.head.rotation.y, 0, 6, dt);
    }
    // blinking
    this.blinkT -= dt;
    let blink = 1;
    if (this.blinkT < 0.12) blink = Math.abs(this.blinkT - 0.06) / 0.06;
    if (this.blinkT <= 0) this.blinkT = 2 + Math.random() * 3;
    for (const e of this.eyes) e.scale.y = Math.max(0.1, blink) * (1 - s.hit * 0.5);
    this.root.scale.setScalar(this.scaleIn);
  }
}

function outlineMaterial(color: string) {
  return new THREE.ShaderMaterial({
    uniforms: { uColor: { value: new THREE.Color(color) }, uThick: { value: 0.025 } },
    vertexShader: /* glsl */ `
      uniform float uThick;
      void main() {
        vec3 p = position + normal * uThick;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      void main() { gl_FragColor = vec4(uColor, 1.0); }`,
    side: THREE.BackSide,
  });
}

// ------------------------------------------------------------------------ character builders

const BUILDERS: Record<CharacterId, (r: ToyRig) => void> = {
  captainClick(r) {
    const olive = plastic('#5b7a3a', { rough: 0.45 });
    const dark = plastic('#3e5527', { rough: 0.45 });
    const tan = plastic('#c9b27c', { rough: 0.5 });
    r.torso.add(mesh(rbox(0.6, 0.62, 0.38, 0.12), olive, [0, 0.27, 0]));
    r.torso.add(mesh(rbox(0.62, 0.1, 0.4, 0.04), dark, [0, 0.0, 0]));
    r.torso.add(mesh(rbox(0.36, 0.42, 0.18, 0.08), dark, [0, 0.3, -0.26])); // backpack
    r.torso.add(mesh(rbox(0.12, 0.08, 0.06, 0.02), tan, [-0.15, 0.4, 0.2]));
    r.torso.add(mesh(rbox(0.12, 0.08, 0.06, 0.02), tan, [0.15, 0.4, 0.2]));
    r.head.add(mesh(sphere(0.25), plastic(SKIN, { rough: 0.5 }), [0, 0.2, 0]));
    // helmet
    r.head.add(mesh(new THREE.SphereGeometry(0.29, 20, 12, 0, Math.PI * 2, 0, Math.PI / 2), olive, [0, 0.26, 0]));
    r.head.add(mesh(new THREE.CylinderGeometry(0.34, 0.34, 0.04, 24), olive, [0, 0.26, 0.02]));
    r.head.add(mesh(rbox(0.3, 0.03, 0.02, 0.01), dark, [0, 0.12, 0.23], [0.2, 0, 0]));
    r.addEyes(r.head, 0.2, 0.2, 0.09, 0.06, 0.25);
    r.limbs(olive, olive, plastic(SKIN, { rough: 0.5 }), dark);
  },
  rexRampage(r) {
    const g = plastic('#3fae49', { rough: 0.35 });
    const belly = plastic('#f4c27a', { rough: 0.4 });
    const white = plastic('#ffffff', { rough: 0.3 });
    r.torso.add(mesh(capsule(0.3, 0.3), g, [0, 0.28, 0], undefined, [1.05, 1, 0.9]));
    r.torso.add(mesh(capsule(0.2, 0.24), belly, [0, 0.26, 0.14], undefined, [1, 1, 0.6]));
    // spikes along the back
    for (let i = 0; i < 4; i++) r.torso.add(mesh(new THREE.ConeGeometry(0.07, 0.16, 4), plastic('#f77f00'), [0, 0.5 - i * 0.14, -0.27], [-0.6, 0, 0]));
    // dino head: big snout
    r.head.add(mesh(rbox(0.46, 0.38, 0.46, 0.16), g, [0, 0.22, 0.04]));
    r.head.add(mesh(rbox(0.38, 0.2, 0.36, 0.08), g, [0, 0.12, 0.32]));
    r.head.add(mesh(rbox(0.36, 0.1, 0.32, 0.04), plastic('#c1121f'), [0, 0.04, 0.3]));
    for (let i = 0; i < 4; i++) for (const s of [-1, 1]) r.head.add(mesh(new THREE.ConeGeometry(0.03, 0.07, 6), white, [s * (0.06 + i * 0.04), 0.03, 0.47 - i * 0.05], [Math.PI, 0, 0]));
    r.head.add(mesh(sphere(0.03), plastic('#1b4332'), [-0.08, 0.2, 0.5]));
    r.head.add(mesh(sphere(0.03), plastic('#1b4332'), [0.08, 0.2, 0.5]));
    r.addEyes(r.head, 0.34, 0.2, 0.14, 0.075, 0.35);
    // tail
    r.tail = new THREE.Group();
    r.tail.position.set(0, -0.02, -0.18);
    let parent: THREE.Object3D = r.tail;
    for (let i = 0; i < 4; i++) {
      const seg = new THREE.Group();
      seg.position.set(0, -0.03, i === 0 ? 0 : -0.2);
      seg.add(mesh(sphere(0.17 - i * 0.035), g, [0, 0, -0.1]));
      parent.add(seg);
      parent = seg;
    }
    r.hips.add(r.tail);
    r.limbs(g, g, g, plastic('#2d6a4f'), { thick: 1.15 });
  },
  boltBuddy(r) {
    const silver = plastic('#b8c4d6', { rough: 0.25, metal: 0.4 });
    const blue = plastic('#3a86ff', { rough: 0.3 });
    r.torso.add(mesh(rbox(0.56, 0.58, 0.36, 0.08), silver, [0, 0.27, 0]));
    r.torso.add(mesh(rbox(0.3, 0.22, 0.04, 0.03), blue, [0, 0.32, 0.18]));
    for (let i = 0; i < 3; i++) r.torso.add(mesh(sphere(0.03), glow(['#ff006e', '#ffbe0b', '#06d6a0'][i], 2), [-0.08 + i * 0.08, 0.32, 0.21]));
    r.head.add(mesh(rbox(0.44, 0.38, 0.38, 0.1), silver, [0, 0.22, 0]));
    const visor = mesh(rbox(0.36, 0.12, 0.04, 0.03), glow('#5af7ff', 2), [0, 0.24, 0.19]);
    r.visor = visor;
    r.head.add(visor);
    r.head.add(mesh(rbox(0.1, 0.18, 0.1, 0.03), blue, [-0.25, 0.22, 0]));
    r.head.add(mesh(rbox(0.1, 0.18, 0.1, 0.03), blue, [0.25, 0.22, 0]));
    r.antenna = new THREE.Group();
    r.antenna.position.set(0, 0.41, 0);
    r.antenna.add(mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.22, 6), metal('#cccccc'), [0, 0.11, 0]));
    r.antenna.add(mesh(sphere(0.05), glow('#ffbe0b', 3), [0, 0.24, 0]));
    r.head.add(r.antenna);
    r.limbs(silver, blue, silver, blue, { thick: 0.95 });
  },
  princessPanic(r) {
    const pink = plastic('#ff70a6', { rough: 0.3 });
    const purple = plastic('#c77dff', { rough: 0.3 });
    const gold = plastic('#ffd670', { rough: 0.2, metal: 0.5 });
    r.torso.add(mesh(rbox(0.46, 0.5, 0.32, 0.12), pink, [0, 0.3, 0]));
    r.torso.add(mesh(new THREE.ConeGeometry(0.42, 0.5, 20, 1, true), purple, [0, -0.02, 0], [Math.PI, 0, 0]));
    r.torso.add(mesh(sphere(0.06), gold, [0, 0.38, 0.17]));
    r.head.add(mesh(sphere(0.24), plastic(SKIN, { rough: 0.5 }), [0, 0.2, 0]));
    r.head.add(mesh(sphere(0.26, 18, 14), plastic('#7b2cbf', { rough: 0.5 }), [0, 0.25, -0.05], undefined, [1, 0.95, 1]));
    r.head.add(mesh(capsule(0.08, 0.3), plastic('#7b2cbf', { rough: 0.5 }), [0, 0.1, -0.3], [0.5, 0, 0]));
    // crown
    const crown = new THREE.Group();
    crown.position.set(0, 0.44, 0);
    crown.add(mesh(new THREE.CylinderGeometry(0.15, 0.16, 0.08, 16, 1, true), gold));
    for (let i = 0; i < 5; i++) {
      const a = (i / 5) * Math.PI * 2;
      crown.add(mesh(new THREE.ConeGeometry(0.035, 0.1, 6), gold, [Math.cos(a) * 0.15, 0.08, Math.sin(a) * 0.15]));
    }
    crown.add(mesh(sphere(0.035), glow('#ff006e', 1.5), [0, 0.04, 0.16]));
    r.head.add(crown);
    r.addEyes(r.head, 0.2, 0.2, 0.085, 0.065);
    // cape
    const capeGeo = new THREE.PlaneGeometry(0.62, 0.9, 1, 4);
    capeGeo.translate(0, -0.45, 0);
    r.cape = mesh(capeGeo, new THREE.MeshStandardMaterial({ color: '#9d4edd', roughness: 0.8, side: THREE.DoubleSide }), [0, 0.55, -0.2]);
    r.torso.add(r.cape);
    r.limbs(pink, plastic(SKIN, { rough: 0.5 }), plastic(SKIN, { rough: 0.5 }), purple, { thick: 0.85 });
  },
  turboTim(r) {
    const red = plastic('#e63946', { rough: 0.2, clearcoat: 1 });
    const white = plastic('#ffffff', { rough: 0.25 });
    const navy = plastic('#1d3557', { rough: 0.3 });
    r.torso.add(mesh(rbox(0.54, 0.6, 0.36, 0.12), red, [0, 0.27, 0]));
    r.torso.add(mesh(rbox(0.12, 0.62, 0.38, 0.04), white, [0, 0.27, 0]));
    // race number
    const c = document.createElement('canvas');
    c.width = c.height = 64;
    const ctx = c.getContext('2d')!;
    ctx.fillStyle = '#ffffff';
    ctx.beginPath();
    ctx.arc(32, 32, 30, 0, 7);
    ctx.fill();
    ctx.fillStyle = '#1d3557';
    ctx.font = 'bold 44px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('7', 32, 35);
    const tex = new THREE.CanvasTexture(c);
    tex.colorSpace = THREE.SRGBColorSpace;
    r.torso.add(mesh(new THREE.CircleGeometry(0.12, 20), new THREE.MeshStandardMaterial({ map: tex, transparent: true }), [0.15, 0.36, 0.185]));
    // helmet with visor
    r.head.add(mesh(sphere(0.28), red, [0, 0.22, 0]));
    r.head.add(mesh(rbox(0.1, 0.06, 0.52, 0.02), white, [0, 0.46, 0]));
    const visor = mesh(new THREE.SphereGeometry(0.26, 20, 10, -0.9, 1.8, 1.0, 0.75), new THREE.MeshPhysicalMaterial({ color: '#111827', roughness: 0.05, clearcoat: 1, metalness: 0.3, emissive: '#3a0ca3', emissiveIntensity: 0.6 }), [0, 0.22, 0.05], [0, 0, 0]);
    r.visor = visor;
    r.head.add(visor);
    // spoiler on the back
    r.torso.add(mesh(rbox(0.6, 0.04, 0.14, 0.02), navy, [0, 0.6, -0.3]));
    r.torso.add(mesh(rbox(0.04, 0.16, 0.06, 0.01), navy, [-0.2, 0.52, -0.26]));
    r.torso.add(mesh(rbox(0.04, 0.16, 0.06, 0.01), navy, [0.2, 0.52, -0.26]));
    r.limbs(red, white, white, navy);
  },
  mechaMax(r) {
    const grey = plastic('#4a4e69', { rough: 0.35, metal: 0.3 });
    const yellow = plastic('#ffb703', { rough: 0.3 });
    const dark = plastic('#22223b', { rough: 0.4 });
    r.torso.add(mesh(rbox(0.7, 0.62, 0.46, 0.1), grey, [0, 0.27, 0]));
    r.torso.add(mesh(rbox(0.4, 0.2, 0.06, 0.04), yellow, [0, 0.32, 0.23]));
    // huge shoulder pads
    r.armL.add(mesh(rbox(0.32, 0.22, 0.4, 0.08), yellow, [-0.06, 0.04, 0]));
    r.armR.add(mesh(rbox(0.32, 0.22, 0.4, 0.08), yellow, [0.06, 0.04, 0]));
    r.head.add(mesh(rbox(0.42, 0.34, 0.4, 0.08), grey, [0, 0.2, 0]));
    const visor = mesh(rbox(0.34, 0.06, 0.04, 0.02), glow('#ff4d6d', 2.4), [0, 0.22, 0.2]);
    r.visor = visor;
    r.head.add(visor);
    r.head.add(mesh(rbox(0.46, 0.06, 0.44, 0.02), yellow, [0, 0.39, 0]));
    r.torso.add(mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.4, 10), dark, [-0.18, 0.4, -0.3], [0.2, 0, 0]));
    r.torso.add(mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.4, 10), dark, [0.18, 0.4, -0.3], [0.2, 0, 0]));
    r.limbs(grey, dark, grey, dark, { thick: 1.3 });
  },
  blockhead(r) {
    const red = plastic('#d6342c', { rough: 0.3 });
    const yellow = plastic('#f2c12e', { rough: 0.3 });
    const blue = plastic('#1f6fd1', { rough: 0.3 });
    r.torso.add(mesh(rbox(0.6, 0.6, 0.4, 0.04), blue, [0, 0.27, 0]));
    for (const x of [-0.15, 0.15]) for (const z of [-0.1, 0.1]) r.torso.add(mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.06, 12), blue, [x, 0.6, z]));
    // brick head with studs and a visor slot
    r.head.add(mesh(rbox(0.46, 0.4, 0.42, 0.03), red, [0, 0.22, 0]));
    for (const x of [-0.11, 0.11]) for (const z of [-0.1, 0.1]) r.head.add(mesh(new THREE.CylinderGeometry(0.07, 0.07, 0.07, 12), red, [x, 0.455, z]));
    r.head.add(mesh(rbox(0.36, 0.07, 0.04, 0.01), plastic('#111'), [0, 0.24, 0.21]));
    r.addEyes(r.head, 0.24, 0.205, 0.09, 0.04);
    // brick shield on left arm
    const shield = mesh(rbox(0.08, 0.42, 0.32, 0.02), yellow, [-0.12, -0.18, 0.05]);
    r.foreL.add(shield);
    for (const y of [-0.08, 0.08]) shield.add(mesh(new THREE.CylinderGeometry(0.05, 0.05, 0.05, 10), yellow, [-0.06, y, 0], [0, 0, Math.PI / 2]));
    r.limbs(red, yellow, yellow, red, { thick: 1.1 });
  },
  player(r) {
    BUILDERS.captainClick(r);
  },
  // variants are built from their base toy (see CharacterDef.base); these never run
  sergeantSnap: (r) => BUILDERS.captainClick(r),
  dinaMite: (r) => BUILDERS.rexRampage(r),
  sparky: (r) => BUILDERS.boltBuddy(r),
  duchessDazzle: (r) => BUILDERS.princessPanic(r),
  nitroNina: (r) => BUILDERS.turboTim(r),
  gearboxGus: (r) => BUILDERS.mechaMax(r),
  brickette: (r) => BUILDERS.blockhead(r),
};

/** Small add-ons so the newcomers aren't just repaints. */
const EXTRAS: Partial<Record<CharacterId, (r: ToyRig) => void>> = {
  sergeantSnap(r) {
    // sunglasses + a chevron patch
    const black = plastic('#111111', { rough: 0.1, clearcoat: 1 });
    for (const s of [-1, 1]) r.head.add(mesh(rbox(0.13, 0.07, 0.03, 0.02), black, [s * 0.09, 0.2, 0.25]));
    r.head.add(mesh(rbox(0.06, 0.02, 0.02, 0.005), black, [0, 0.21, 0.25]));
    r.torso.add(mesh(new THREE.ConeGeometry(0.06, 0.06, 3), plastic('#ffd23f'), [0.17, 0.42, 0.2], [Math.PI / 2, 0, 0]));
  },
  dinaMite(r) {
    // fuse sticking out of the head
    r.head.add(mesh(new THREE.CylinderGeometry(0.015, 0.015, 0.18, 6), plastic('#5a3e2b'), [0, 0.5, -0.05], [-0.4, 0, 0]));
    r.head.add(mesh(sphere(0.035), glow('#ffb703', 3), [0, 0.6, -0.09]));
  },
  sparky(r) {
    // lightning bolt on the chest
    const bolt = new THREE.Shape();
    bolt.moveTo(0.02, 0.09);
    bolt.lineTo(-0.05, -0.005);
    bolt.lineTo(0.0, -0.005);
    bolt.lineTo(-0.02, -0.09);
    bolt.lineTo(0.05, 0.015);
    bolt.lineTo(0.0, 0.015);
    bolt.closePath();
    r.torso.add(mesh(new THREE.ShapeGeometry(bolt), glow('#3a86ff', 2), [0, 0.18, 0.185]));
  },
  duchessDazzle(r) {
    // monocle
    r.head.add(mesh(new THREE.TorusGeometry(0.05, 0.008, 6, 16), plastic('#ffd670', { metal: 0.6 }), [0.085, 0.2, 0.23]));
  },
  nitroNina(r) {
    // twin exhaust pipes on the back
    for (const x of [-0.12, 0.12]) r.torso.add(mesh(new THREE.CylinderGeometry(0.04, 0.05, 0.22, 10), metal('#c0c6d0', 0.3), [x, 0.15, -0.24], [0.3, 0, 0]));
  },
  gearboxGus(r) {
    // spinning gear on the chest (static, but chunky)
    const gear = new THREE.Group();
    gear.position.set(0, 0.32, 0.26);
    gear.add(mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.03, 14), plastic('#e9ecef', { metal: 0.5 }), [0, 0, 0], [Math.PI / 2, 0, 0]));
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * Math.PI * 2;
      gear.add(mesh(rbox(0.04, 0.04, 0.03, 0.005), plastic('#e9ecef', { metal: 0.5 }), [Math.cos(a) * 0.09, Math.sin(a) * 0.09, 0]));
    }
    r.torso.add(gear);
  },
  brickette(r) {
    // bow on top of the brick head
    const pink = plastic('#e64980');
    for (const s of [-1, 1]) r.head.add(mesh(new THREE.ConeGeometry(0.08, 0.14, 4), pink, [s * 0.09, 0.53, 0], [0, 0, (s * Math.PI) / 2]));
    r.head.add(mesh(sphere(0.045), pink, [0, 0.53, 0]));
  },
};

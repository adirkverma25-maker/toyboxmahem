import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import {
  scratchRoughness, woodTexture, carpetTexture, fiberBump, quiltTexture, cardboardTexture, wallpaperTexture,
} from './textures';

const plasticCache = new Map<string, THREE.MeshPhysicalMaterial>();

/** Box whose UVs tile in world units (density = repeats per unit). */
export function tiledBox(w: number, h: number, d: number, density = 0.1) {
  const g = new THREE.BoxGeometry(w, h, d);
  const uv = g.getAttribute('uv') as THREE.BufferAttribute;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++)
    for (let i = 0; i < 4; i++) {
      const idx = f * 4 + i;
      uv.setXY(idx, uv.getX(idx) * dims[f][0] * density, uv.getY(idx) * dims[f][1] * density);
    }
  return g;
}

/** Glossy toy plastic with clearcoat and subtle scratches. */
export function plastic(color: THREE.ColorRepresentation, opts: { rough?: number; emissive?: THREE.ColorRepresentation; emissiveIntensity?: number; clearcoat?: number; metal?: number } = {}) {
  const key = `${new THREE.Color(color).getHexString()}|${opts.rough ?? 0.38}|${opts.emissive ?? ''}|${opts.emissiveIntensity ?? 0}|${opts.clearcoat ?? 0.6}|${opts.metal ?? 0}`;
  let m = plasticCache.get(key);
  if (!m) {
    m = new THREE.MeshPhysicalMaterial({
      color,
      roughness: opts.rough ?? 0.38,
      metalness: opts.metal ?? 0,
      roughnessMap: scratchRoughness(),
      clearcoat: opts.clearcoat ?? 0.6,
      clearcoatRoughness: 0.25,
      emissive: opts.emissive ?? 0x000000,
      emissiveIntensity: opts.emissiveIntensity ?? 0,
    });
    plasticCache.set(key, m);
  }
  return m;
}

export function translucent(color: THREE.ColorRepresentation, opacity = 0.55, emissive?: THREE.ColorRepresentation, ei = 0) {
  return new THREE.MeshPhysicalMaterial({
    color,
    roughness: 0.12,
    transmission: 0,
    transparent: true,
    opacity,
    clearcoat: 1,
    emissive: emissive ?? 0x000000,
    emissiveIntensity: ei,
    depthWrite: false,
  });
}

export function rubber(color: THREE.ColorRepresentation) {
  return new THREE.MeshStandardMaterial({ color, roughness: 0.85, metalness: 0 });
}
export function metal(color: THREE.ColorRepresentation, rough = 0.25) {
  return new THREE.MeshStandardMaterial({ color, roughness: rough, metalness: 1 });
}
export function glow(color: THREE.ColorRepresentation, intensity = 2) {
  return new THREE.MeshStandardMaterial({ color, emissive: color, emissiveIntensity: intensity, roughness: 0.4 });
}

/** Shared environment materials. Created once. */
export class EnvMats {
  floor = new THREE.MeshStandardMaterial({ map: woodTexture('floor'), roughness: 0.55, metalness: 0 });
  desk = new THREE.MeshStandardMaterial({ map: woodTexture('desk'), roughness: 0.45 });
  bedWood = new THREE.MeshStandardMaterial({ map: woodTexture('bed'), roughness: 0.5 });
  blockWood = new THREE.MeshStandardMaterial({ map: woodTexture('block'), roughness: 0.55 });
  carpet = new THREE.MeshStandardMaterial({ map: carpetTexture(), roughness: 0.97, bumpMap: fiberBump(3, 8), bumpScale: 1.2 });
  blanket = new THREE.MeshStandardMaterial({ map: quiltTexture('#6c8fe0', '#f2a65a'), roughness: 0.95, bumpMap: fiberBump(8, 6), bumpScale: 0.8, side: THREE.DoubleSide });
  sheet = new THREE.MeshStandardMaterial({ color: '#f4f1ea', roughness: 0.95, bumpMap: fiberBump(9, 6), bumpScale: 0.6 });
  pillow = new THREE.MeshStandardMaterial({ color: '#ffe7ef', roughness: 0.92, bumpMap: fiberBump(10, 4), bumpScale: 0.6 });
  pillow2 = new THREE.MeshStandardMaterial({ color: '#d9ecff', roughness: 0.92, bumpMap: fiberBump(10, 4), bumpScale: 0.6 });
  cardboard = new THREE.MeshStandardMaterial({ map: cardboardTexture(), roughness: 0.9 });
  cardboardToys = new THREE.MeshStandardMaterial({ map: cardboardTexture('TOYS'), roughness: 0.9 });
  cardboardShoes = new THREE.MeshStandardMaterial({ map: cardboardTexture('SHOES'), roughness: 0.9 });
  wallpaper = new THREE.MeshStandardMaterial({ map: wallpaperTexture(), roughness: 0.9 });
  ceiling = new THREE.MeshStandardMaterial({ color: '#fbf6ee', roughness: 0.95 });
  trim = new THREE.MeshStandardMaterial({ color: '#fffaf0', roughness: 0.5 });
  closetWall = new THREE.MeshStandardMaterial({ color: '#6f6a8a', roughness: 0.9 });
  fabricA = new THREE.MeshStandardMaterial({ color: '#c0485a', roughness: 0.95, bumpMap: fiberBump(12, 4), bumpScale: 0.8, side: THREE.DoubleSide });
  fabricB = new THREE.MeshStandardMaterial({ color: '#3f6fb0', roughness: 0.95, bumpMap: fiberBump(13, 4), bumpScale: 0.8, side: THREE.DoubleSide });
  fabricC = new THREE.MeshStandardMaterial({ color: '#e8c35a', roughness: 0.95, bumpMap: fiberBump(14, 4), bumpScale: 0.8, side: THREE.DoubleSide });
  fabricD = new THREE.MeshStandardMaterial({ color: '#5f9e6e', roughness: 0.95, bumpMap: fiberBump(15, 4), bumpScale: 0.8, side: THREE.DoubleSide });
  rock = new THREE.MeshStandardMaterial({ color: '#8d8478', roughness: 0.8, bumpMap: fiberBump(16, 2), bumpScale: 2.5, flatShading: true });
  paper = new THREE.MeshStandardMaterial({ color: '#fbf8ef', roughness: 0.85 });
  metalSteel = metal('#c9ced6', 0.3);
  glass = new THREE.MeshPhysicalMaterial({ color: '#d8f0ff', roughness: 0.05, transparent: true, opacity: 0.25, clearcoat: 1, depthWrite: false });
}

/**
 * Collects static meshes and merges them by material into a handful of draw calls.
 * Every add() bakes the transform into a cloned geometry.
 */
export class StaticBatcher {
  private groups = new Map<THREE.Material, THREE.BufferGeometry[]>();
  private flags = new Map<THREE.Material, { cast: boolean; receive: boolean }>();

  add(geo: THREE.BufferGeometry, mat: THREE.Material, matrix: THREE.Matrix4, cast = true, receive = true) {
    let g = geo.index ? geo.toNonIndexed() : geo.clone();
    // normalize attributes so everything can be merged
    if (!g.getAttribute('uv')) {
      const n = g.getAttribute('position').count;
      g.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(n * 2), 2));
    }
    for (const name of Object.keys(g.attributes)) {
      if (!['position', 'normal', 'uv'].includes(name)) g.deleteAttribute(name);
    }
    if (!g.getAttribute('normal')) g.computeVertexNormals();
    g.applyMatrix4(matrix);
    g.groups = [];
    let list = this.groups.get(mat);
    if (!list) {
      list = [];
      this.groups.set(mat, list);
      this.flags.set(mat, { cast, receive });
    }
    list.push(g);
    const f = this.flags.get(mat)!;
    f.cast = f.cast || cast;
    f.receive = f.receive || receive;
  }

  /** Convenience: add a mesh-like description using position/rotation/scale. */
  addAt(geo: THREE.BufferGeometry, mat: THREE.Material, pos: THREE.Vector3, rot?: THREE.Euler, scale?: THREE.Vector3, cast = true) {
    const m = new THREE.Matrix4().compose(
      pos,
      new THREE.Quaternion().setFromEuler(rot ?? new THREE.Euler()),
      scale ?? new THREE.Vector3(1, 1, 1),
    );
    this.add(geo, mat, m, cast);
  }

  build(parent: THREE.Object3D) {
    const meshes: THREE.Mesh[] = [];
    for (const [mat, list] of this.groups) {
      // merge in chunks to keep index ranges sane
      const merged = mergeGeometries(list, false);
      if (!merged) continue;
      merged.computeBoundingSphere();
      const mesh = new THREE.Mesh(merged, mat);
      const f = this.flags.get(mat)!;
      mesh.castShadow = f.cast;
      mesh.receiveShadow = f.receive;
      mesh.matrixAutoUpdate = false;
      mesh.updateMatrix();
      parent.add(mesh);
      meshes.push(mesh);
      for (const g of list) g.dispose();
    }
    this.groups.clear();
    return meshes;
  }
}

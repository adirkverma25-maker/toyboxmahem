import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

function normalize(g: THREE.BufferGeometry, m: THREE.Matrix4) {
  const out = g.index ? g.toNonIndexed() : g.clone();
  for (const name of Object.keys(out.attributes)) if (!['position', 'normal', 'uv'].includes(name)) out.deleteAttribute(name);
  if (!out.getAttribute('uv')) out.setAttribute('uv', new THREE.BufferAttribute(new Float32Array(out.getAttribute('position').count * 2), 2));
  if (!out.getAttribute('normal')) out.computeVertexNormals();
  out.applyMatrix4(m);
  out.groups = [];
  return out;
}

/**
 * Flattens every mesh under `root` (that `keep` doesn't protect) into one mesh per material,
 * parented directly to root. Cuts draw calls a lot for static multi-part models.
 */
export function flattenByMaterial(root: THREE.Object3D, keep: (o: THREE.Object3D) => boolean = () => false) {
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const buckets = new Map<THREE.Material, THREE.BufferGeometry[]>();
  const shadow = new Map<THREE.Material, boolean>();
  const remove: THREE.Mesh[] = [];
  root.traverse((o) => {
    const m = o as THREE.Mesh;
    if (!m.isMesh || Array.isArray(m.material) || keep(m)) return;
    // never merge something that has a protected ancestor
    let p: THREE.Object3D | null = m.parent;
    while (p && p !== root) {
      if (keep(p)) return;
      p = p.parent;
    }
    const rel = new THREE.Matrix4().multiplyMatrices(inv, m.matrixWorld);
    const mat = m.material as THREE.Material;
    let list = buckets.get(mat);
    if (!list) buckets.set(mat, (list = []));
    list.push(normalize(m.geometry, rel));
    shadow.set(mat, (shadow.get(mat) ?? false) || m.castShadow);
    remove.push(m);
  });
  for (const m of remove) m.parent?.remove(m);
  for (const [mat, list] of buckets) {
    const g = mergeGeometries(list, false);
    for (const x of list) x.dispose();
    if (!g) continue;
    g.computeBoundingSphere();
    const mesh = new THREE.Mesh(g, mat);
    mesh.castShadow = shadow.get(mat) ?? false;
    mesh.receiveShadow = true;
    root.add(mesh);
  }
}

/** Merge only the direct mesh children of each group (keeps the skeleton hierarchy animatable). */
export function mergeDirectChildren(root: THREE.Object3D, keep: (o: THREE.Object3D) => boolean = () => false) {
  const groups: THREE.Object3D[] = [];
  root.traverse((o) => {
    if (!(o as THREE.Mesh).isMesh) groups.push(o);
  });
  for (const grp of groups) {
    if (keep(grp)) continue;
    const buckets = new Map<THREE.Material, THREE.Mesh[]>();
    for (const c of grp.children) {
      const m = c as THREE.Mesh;
      if (!m.isMesh || m.children.length || keep(m) || Array.isArray(m.material)) continue;
      const mat = m.material as THREE.Material;
      let l = buckets.get(mat);
      if (!l) buckets.set(mat, (l = []));
      l.push(m);
    }
    for (const [mat, list] of buckets) {
      if (list.length < 2) continue;
      const geos = list.map((m) => {
        m.updateMatrix();
        return normalize(m.geometry, m.matrix);
      });
      const g = mergeGeometries(geos, false);
      for (const x of geos) x.dispose();
      if (!g) continue;
      g.computeBoundingSphere();
      const mesh = new THREE.Mesh(g, mat);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      for (const m of list) grp.remove(m);
      grp.add(mesh);
    }
  }
}

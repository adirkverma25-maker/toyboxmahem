import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { StaticBatcher, tiledBox, plastic } from '../render/materials';
import { Physics, SurfaceMat } from '../physics/Physics';

export type V3 = [number, number, number];
export const v3 = (x: number, y: number, z: number) => new THREE.Vector3(x, y, z);

export interface BoxOpts {
  round?: number;
  tile?: number;
  visual?: boolean;
  cast?: boolean;
}

/** Triangular prism: low edge at z=0,y=0; high edge at z=len, y=height. x spans width. */
export function wedgeGeometry(len: number, height: number, width: number, uvDensity = 0.15) {
  const w = width / 2;
  const A = [-w, 0, 0], B = [w, 0, 0], C = [-w, 0, len], D = [w, 0, len], E = [-w, height, len], F = [w, height, len];
  const tris: number[][][] = [
    [A, C, D], [A, D, B], // bottom (facing down)
    [C, E, F], [C, F, D], // back
    [A, B, F], [A, F, E], // slope
    [A, E, C], // left side
    [B, D, F], // right side
  ];
  const pos: number[] = [];
  const uv: number[] = [];
  for (const t of tris)
    for (const p of t) {
      pos.push(p[0], p[1], p[2]);
      uv.push((p[0] + p[2]) * uvDensity, (p[1] + p[2]) * uvDensity);
    }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.computeVertexNormals();
  return g;
}

export class Builder {
  studs: { pos: THREE.Vector3; color: THREE.Color }[] = [];
  constructor(public batch: StaticBatcher, public phys: Physics) {}

  box(min: V3, max: V3, mat: THREE.Material, surf: SurfaceMat | null, opts: BoxOpts = {}) {
    const w = max[0] - min[0], h = max[1] - min[1], d = max[2] - min[2];
    const c = v3((min[0] + max[0]) / 2, (min[1] + max[1]) / 2, (min[2] + max[2]) / 2);
    if (opts.visual !== false) {
      const geo = opts.round
        ? new RoundedBoxGeometry(w, h, d, 2, Math.min(opts.round, w / 2.01, h / 2.01, d / 2.01))
        : opts.tile
          ? tiledBox(w, h, d, opts.tile)
          : new THREE.BoxGeometry(w, h, d);
      this.batch.addAt(geo, mat, c, undefined, undefined, opts.cast ?? true);
      geo.dispose();
    }
    if (surf) this.phys.box(c, v3(w / 2, h / 2, d / 2), surf);
    return c;
  }

  /** Rotated box by center/size/euler. */
  obox(center: V3, size: V3, rot: THREE.Euler, mat: THREE.Material, surf: SurfaceMat | null, round = 0) {
    const geo = round ? new RoundedBoxGeometry(size[0], size[1], size[2], 2, Math.min(round, size[0] / 2.01, size[1] / 2.01, size[2] / 2.01)) : new THREE.BoxGeometry(...size);
    this.batch.addAt(geo, mat, v3(...center), rot);
    geo.dispose();
    if (surf) this.phys.box(v3(...center), v3(size[0] / 2, size[1] / 2, size[2] / 2), surf, rot);
  }

  /** Vertical cylinder standing on base point. */
  cyl(base: V3, r: number, h: number, mat: THREE.Material, surf: SurfaceMat | null, seg = 24, rTop?: number) {
    const geo = new THREE.CylinderGeometry(rTop ?? r, r, h, seg);
    const c = v3(base[0], base[1] + h / 2, base[2]);
    this.batch.addAt(geo, mat, c);
    geo.dispose();
    if (surf) this.phys.cylinder(c, h / 2, Math.max(r, rTop ?? r), surf);
  }

  /** Any geometry, visual only. */
  geo(g: THREE.BufferGeometry, mat: THREE.Material, pos: V3, rot?: THREE.Euler, scale?: V3, cast = true) {
    this.batch.addAt(g, mat, v3(...pos), rot, scale ? v3(...scale) : undefined, cast);
    g.dispose();
  }

  /** Solid wedge ramp. `low` is the floor point at the middle of the low edge, yaw rotates the ramp direction (0 = +z). */
  wedge(low: V3, yaw: number, len: number, height: number, width: number, mat: THREE.Material, surf: SurfaceMat) {
    const g = wedgeGeometry(len, height, width);
    const m = new THREE.Matrix4().compose(v3(...low), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, yaw, 0)), v3(1, 1, 1));
    this.batch.add(g, mat, m);
    const w = width / 2;
    const pts = [
      [-w, 0, 0], [w, 0, 0], [-w, 0, len], [w, 0, len], [-w, height, len], [w, height, len],
    ].map((p) => v3(p[0], p[1], p[2]).applyMatrix4(m));
    this.phys.convex(pts, surf);
    g.dispose();
  }

  /** Thin slab ramp between two surface points (open underneath). */
  slab(from: V3, to: V3, width: number, thickness: number, mat: THREE.Material, surf: SurfaceMat, round = 0) {
    const r = this.phys.ramp(v3(...from), v3(...to), width, surf, thickness);
    const geo = round ? new RoundedBoxGeometry(width, thickness, r.length, 2, round) : tiledBox(width, thickness, r.length, 0.2);
    const m = new THREE.Matrix4().compose(r.center, r.quat, v3(1, 1, 1));
    this.batch.add(geo, mat, m);
    geo.dispose();
    return r;
  }

  /** A toy construction brick: box + studs on top. */
  brick(min: V3, max: V3, color: THREE.ColorRepresentation, surf: SurfaceMat | null = 'plastic', studs = true, pitch = 0.8) {
    this.box(min, max, plastic(color, { rough: 0.3 }), surf, { round: 0.06 });
    if (studs) this.addStuds(min[0], max[0], min[2], max[2], max[1], color, pitch);
  }
  addStuds(x0: number, x1: number, z0: number, z1: number, y: number, color: THREE.ColorRepresentation, pitch = 0.8) {
    const c = new THREE.Color(color);
    const nx = Math.max(1, Math.floor((x1 - x0) / pitch + 0.001));
    const nz = Math.max(1, Math.floor((z1 - z0) / pitch + 0.001));
    const ox = x0 + (x1 - x0 - nx * pitch) / 2 + pitch / 2;
    const oz = z0 + (z1 - z0 - nz * pitch) / 2 + pitch / 2;
    for (let i = 0; i < nx; i++) for (let j = 0; j < nz; j++) this.studs.push({ pos: v3(ox + i * pitch, y, oz + j * pitch), color: c });
  }

  buildStuds(parent: THREE.Object3D, pitch = 0.8) {
    if (!this.studs.length) return;
    const geo = new THREE.CylinderGeometry(pitch * 0.3, pitch * 0.3, pitch * 0.22, 14);
    geo.translate(0, pitch * 0.11, 0);
    const mat = new THREE.MeshPhysicalMaterial({ roughness: 0.3, clearcoat: 0.6, color: 0xffffff });
    const inst = new THREE.InstancedMesh(geo, mat, this.studs.length);
    const m = new THREE.Matrix4();
    this.studs.forEach((s, i) => {
      m.makeTranslation(s.pos.x, s.pos.y, s.pos.z);
      inst.setMatrixAt(i, m);
      inst.setColorAt(i, s.color);
    });
    inst.castShadow = true;
    inst.receiveShadow = true;
    inst.computeBoundingSphere();
    parent.add(inst);
    this.studs = [];
  }
}

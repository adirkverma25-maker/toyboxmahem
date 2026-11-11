import * as THREE from 'three';
import RAPIER from '@dimforge/rapier3d-compat';
import { Physics, GROUP_WORLD, groups } from '../physics/Physics';
import { MOVE } from '../weapons/weaponConfig';

export interface NavLink {
  to: number;
  cost: number;
  jump?: boolean;
  /** index of the elevator that carries you along this link */
  elevator?: number;
}
export interface NavNode {
  id: number;
  pos: THREE.Vector3; // feet position
  links: NavLink[];
  /** how open the spot is (number of linked neighbors) */
  open: number;
}

/**
 * Navigation graph generated automatically from the physics world:
 * 1. Sample walkable surfaces on a grid (multi-level: floor, under the bed, bed top, desk, ramps...).
 * 2. Link neighbours with a walk test (step height, slopes, drops, wall + head clearance).
 * 3. Keep the strongly connected region so bots never path to places they can't leave.
 */
export class NavGraph {
  nodes: NavNode[] = [];
  private cell = 4;
  private hash = new Map<string, number[]>();
  private qGroups = groups(0xffff, GROUP_WORLD);

  constructor(private phys: Physics) {}

  build(bounds: { min: THREE.Vector3; max: THREE.Vector3 }, step = 1.6) {
    const t0 = performance.now();
    const w = this.phys.world;
    const cands: THREE.Vector3[] = [];
    for (let x = bounds.min.x + 0.8; x <= bounds.max.x - 0.8; x += step) {
      for (let z = bounds.min.z + 0.8; z <= bounds.max.z - 0.8; z += step) {
        let y = bounds.max.y - 0.5;
        for (let guard = 0; guard < 8 && y > -0.5; guard++) {
          const ray = new RAPIER.Ray({ x, y, z }, { x: 0, y: -1, z: 0 });
          const hit = w.castRayAndGetNormal(ray, y + 1, true, undefined, this.qGroups);
          if (!hit) break;
          const top = y - hit.timeOfImpact;
          if (hit.timeOfImpact > 0.001 && hit.normal.y > 0.72) {
            const p = new THREE.Vector3(x, top, z);
            // on slopes the capsule's round bottom would touch the surface, so test a little higher
            const lift = 0.06 + (1 - hit.normal.y) * 2.4;
            if (this.phys.capsuleFits(new THREE.Vector3(x, top + lift, z), MOVE.radius - 0.04, MOVE.standHalfHeight)) cands.push(p);
          }
          // find the underside of what we just hit, then continue below it
          const r2 = new RAPIER.Ray({ x, y: top - 0.01, z }, { x: 0, y: -1, z: 0 });
          const exit = w.castRay(r2, top + 1, false, undefined, this.qGroups);
          if (!exit) break;
          y = top - 0.01 - exit.timeOfImpact - 0.02;
          if (exit.timeOfImpact <= 0.001) y = top - 0.3;
        }
      }
    }
    this.nodes = cands.map((pos, id) => ({ id, pos, links: [], open: 0 }));
    this.rehash();
    // links
    const maxD = step * 1.5;
    for (const a of this.nodes) {
      for (const bi of this.near(a.pos, maxD + 0.1)) {
        if (bi === a.id) continue;
        const b = this.nodes[bi];
        const dxz = Math.hypot(b.pos.x - a.pos.x, b.pos.z - a.pos.z);
        if (dxz > maxD || dxz < 0.1) continue;
        const wk = this.walkable(a.pos, b.pos);
        if (wk) {
          const drop = a.pos.y - b.pos.y;
          a.links.push({ to: b.id, cost: a.pos.distanceTo(b.pos) + (drop > 1 ? 1.5 : 0) + (wk === 2 ? 2 : 0), jump: wk === 2 });
        }
      }
    }
    this.pruneToMainRegion();
    for (const n of this.nodes) n.open = n.links.length;
    console.info(`[nav] ${this.nodes.length} nodes in ${(performance.now() - t0).toFixed(0)} ms`);
  }

  private rehash() {
    this.hash.clear();
    for (const n of this.nodes) {
      const k = this.key(n.pos.x, n.pos.z);
      let l = this.hash.get(k);
      if (!l) this.hash.set(k, (l = []));
      l.push(n.id);
    }
  }
  private key(x: number, z: number) {
    return `${Math.floor(x / this.cell)},${Math.floor(z / this.cell)}`;
  }
  /** Node ids whose XZ is within r of p. */
  near(p: THREE.Vector3, r: number): number[] {
    const out: number[] = [];
    const x0 = Math.floor((p.x - r) / this.cell), x1 = Math.floor((p.x + r) / this.cell);
    const z0 = Math.floor((p.z - r) / this.cell), z1 = Math.floor((p.z + r) / this.cell);
    for (let i = x0; i <= x1; i++)
      for (let j = z0; j <= z1; j++) {
        const l = this.hash.get(`${i},${j}`);
        if (!l) continue;
        for (const id of l) {
          const n = this.nodes[id];
          if ((n.pos.x - p.x) ** 2 + (n.pos.z - p.z) ** 2 <= r * r) out.push(id);
        }
      }
    return out;
  }

  private _o = new THREE.Vector3();
  private _d = new THREE.Vector3();
  /** 0 = not walkable, 1 = walk, 2 = needs one jump (step up to ~1.15 m). */
  private walkable(a: THREE.Vector3, b: THREE.Vector3): 0 | 1 | 2 {
    const dist = Math.hypot(b.x - a.x, b.z - a.z);
    const n = Math.max(2, Math.ceil(dist / 0.45));
    let g = a.y;
    let px = a.x, pz = a.z;
    let jumped = false;
    const down = new THREE.Vector3(0, -1, 0);
    for (let i = 1; i <= n; i++) {
      const t = i / n;
      const x = a.x + (b.x - a.x) * t;
      const z = a.z + (b.z - a.z) * t;
      // ground below the new sample (probe from high enough to find a jumpable ledge)
      this._o.set(x, g + 1.2, z);
      const d = this.phys.rayDist(this._o, down, 10, true);
      if (d === Infinity || d < 0.001) return 0;
      const ng = g + 1.2 - d;
      if (ng > g + 1.15) return 0;
      if (ng > g + 0.58) {
        if (jumped) return 0;
        jumped = true;
      }
      if (ng < g - 7) return 0; // too big a drop
      // horizontal clearance between samples, measured above the higher of the two grounds
      const base = Math.max(g, ng);
      for (const h of [0.35, 1.45]) {
        this._o.set(px, base + h, pz);
        const hx = x - px, hz = z - pz;
        const hl = Math.hypot(hx, hz);
        if (hl > 1e-4) {
          this._d.set(hx / hl, 0, hz / hl);
          if (this.phys.rayDist(this._o, this._d, hl + MOVE.radius * 0.6, true) !== Infinity) return 0;
        }
      }
      // head clearance at the new spot
      this._o.set(x, ng + 0.1, z);
      this._d.set(0, 1, 0);
      if (this.phys.rayDist(this._o, this._d, MOVE.standHalfHeight * 2 + MOVE.radius * 2 - 0.1, true) !== Infinity) return 0;
      g = ng;
      px = x;
      pz = z;
    }
    if (Math.abs(g - b.y) >= 0.45) return 0;
    return jumped ? 2 : 1;
  }

  private pruneToMainRegion() {
    // seed: node closest to the middle of the play rug
    let seed = -1;
    let best = Infinity;
    for (const n of this.nodes) {
      const d = (n.pos.x + 1) ** 2 + (n.pos.z - 1) ** 2 + (n.pos.y - 3.6) ** 2 * 4;
      if (n.pos.y < 0.5 && d < best) {
        best = d;
        seed = n.id;
      }
    }
    if (seed < 0) return;
    const fwd = new Set<number>([seed]);
    const q = [seed];
    while (q.length) {
      const c = q.pop()!;
      for (const l of this.nodes[c].links) if (!fwd.has(l.to)) { fwd.add(l.to); q.push(l.to); }
    }
    const rev = new Map<number, number[]>();
    for (const n of this.nodes) for (const l of n.links) {
      let r = rev.get(l.to);
      if (!r) rev.set(l.to, (r = []));
      r.push(n.id);
    }
    const back = new Set<number>([seed]);
    q.push(seed);
    while (q.length) {
      const c = q.pop()!;
      for (const p of rev.get(c) ?? []) if (!back.has(p)) { back.add(p); q.push(p); }
    }
    const keep = this.nodes.filter((n) => fwd.has(n.id) && back.has(n.id));
    const remap = new Map<number, number>();
    keep.forEach((n, i) => remap.set(n.id, i));
    this.nodes = keep.map((n, i) => ({
      id: i,
      pos: n.pos,
      open: 0,
      links: n.links.filter((l) => remap.has(l.to)).map((l) => ({ to: remap.get(l.to)!, cost: l.cost, jump: l.jump })),
    }));
    this.rehash();
  }

  /** Closest node on roughly the same level, optionally requiring line of sight. */
  nearest(p: THREE.Vector3, requireLos = true, maxR = 8): number {
    let best = -1;
    let bestD = Infinity;
    const ids = this.near(p, maxR);
    const eye = new THREE.Vector3();
    const tgt = new THREE.Vector3();
    ids.sort((a, b) => this.score(p, a) - this.score(p, b));
    for (const id of ids) {
      const d = this.score(p, id);
      if (d >= bestD) break;
      if (requireLos) {
        eye.set(p.x, p.y + 0.6, p.z);
        tgt.copy(this.nodes[id].pos).setY(this.nodes[id].pos.y + 0.6);
        if (!this.phys.los(eye, tgt, true)) continue;
      }
      best = id;
      bestD = d;
      break;
    }
    if (best < 0 && requireLos) return this.nearest(p, false, maxR * 2);
    return best;
  }
  private score(p: THREE.Vector3, id: number) {
    const n = this.nodes[id].pos;
    const dy = n.y - p.y;
    return (n.x - p.x) ** 2 + (n.z - p.z) ** 2 + dy * dy * 6;
  }

  /** A* path, returns node ids from start to goal (inclusive) or null. */
  path(start: number, goal: number): number[] | null {
    if (start < 0 || goal < 0) return null;
    if (start === goal) return [start];
    const N = this.nodes.length;
    const g = new Float32Array(N).fill(Infinity);
    const f = new Float32Array(N).fill(Infinity);
    const came = new Int32Array(N).fill(-1);
    const closed = new Uint8Array(N);
    const heap: number[] = [];
    const push = (id: number) => {
      heap.push(id);
      let i = heap.length - 1;
      while (i > 0) {
        const p = (i - 1) >> 1;
        if (f[heap[p]] <= f[heap[i]]) break;
        [heap[p], heap[i]] = [heap[i], heap[p]];
        i = p;
      }
    };
    const pop = () => {
      const top = heap[0];
      const last = heap.pop()!;
      if (heap.length) {
        heap[0] = last;
        let i = 0;
        for (;;) {
          const l = 2 * i + 1, r = l + 1;
          let m = i;
          if (l < heap.length && f[heap[l]] < f[heap[m]]) m = l;
          if (r < heap.length && f[heap[r]] < f[heap[m]]) m = r;
          if (m === i) break;
          [heap[m], heap[i]] = [heap[i], heap[m]];
          i = m;
        }
      }
      return top;
    };
    const goalPos = this.nodes[goal].pos;
    g[start] = 0;
    f[start] = this.nodes[start].pos.distanceTo(goalPos);
    push(start);
    let iter = 0;
    while (heap.length && iter++ < 20000) {
      const c = pop();
      if (c === goal) {
        const out = [c];
        let k = c;
        while (came[k] >= 0) {
          k = came[k];
          out.push(k);
        }
        return out.reverse();
      }
      if (closed[c]) continue;
      closed[c] = 1;
      for (const l of this.nodes[c].links) {
        if (closed[l.to]) continue;
        const ng = g[c] + l.cost;
        if (ng < g[l.to]) {
          g[l.to] = ng;
          came[l.to] = c;
          f[l.to] = ng + this.nodes[l.to].pos.distanceTo(goalPos);
          push(l.to);
        }
      }
    }
    return null;
  }

  /**
   * Connect the floor and shelf ends of an elevator shaft with a special link both ways.
   * `bottom`/`top` are the spots next to the shaft where toys wait.
   */
  addElevator(bottom: THREE.Vector3, top: THREE.Vector3, id: number, cost = 32) {
    const nb = this.nearest(bottom, false, 4);
    const nt = this.nearest(top, false, 4);
    if (nb < 0 || nt < 0) return false;
    const a = this.nodes[nb], b = this.nodes[nt];
    if (Math.abs(a.pos.y - bottom.y) > 1.2 || Math.abs(b.pos.y - top.y) > 1.2) return false;
    a.links.push({ to: nt, cost, elevator: id });
    b.links.push({ to: nb, cost, elevator: id });
    return true;
  }

  linkBetween(a: number, b: number) {
    return this.nodes[a]?.links.find((l) => l.to === b);
  }

  random(filter?: (n: NavNode) => boolean): number {
    for (let i = 0; i < 40; i++) {
      const id = Math.floor(Math.random() * this.nodes.length);
      if (!filter || filter(this.nodes[id])) return id;
    }
    return Math.floor(Math.random() * this.nodes.length);
  }

  /** Pick well-spread spawn points (farthest point sampling). */
  spawnPoints(count: number, filter: (n: NavNode) => boolean = (n) => n.open >= 6): THREE.Vector3[] {
    const cand = this.nodes.filter(filter);
    if (!cand.length) return [new THREE.Vector3()];
    const out: THREE.Vector3[] = [cand[Math.floor(cand.length / 2)].pos.clone()];
    while (out.length < count) {
      let best: NavNode | null = null;
      let bestD = -1;
      for (const n of cand) {
        let dmin = Infinity;
        for (const o of out) dmin = Math.min(dmin, n.pos.distanceToSquared(o));
        if (dmin > bestD) {
          bestD = dmin;
          best = n;
        }
      }
      if (!best) break;
      out.push(best.pos.clone());
    }
    return out;
  }
}

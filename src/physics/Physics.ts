import RAPIER from '@dimforge/rapier3d-compat';
import * as THREE from 'three';

export type SurfaceMat = 'wood' | 'plastic' | 'fabric' | 'metal' | 'cardboard' | 'glass' | 'carpet';

export const GROUP_WORLD = 0x0001;
export const GROUP_CHAR = 0x0002;
export const GROUP_DEBRIS = 0x0004;
export const groups = (membership: number, filter: number) => (((membership & 0xffff) << 16) | (filter & 0xffff)) >>> 0;

export interface RayHit {
  dist: number;
  point: THREE.Vector3;
  normal: THREE.Vector3;
  mat: SurfaceMat;
  collider: RAPIER.Collider;
  dynamicBody: RAPIER.RigidBody | null;
}

const _q = new THREE.Quaternion();

export class Physics {
  world!: RAPIER.World;
  R = RAPIER;
  private matByHandle = new Map<number, SurfaceMat>();
  private acc = 0;
  readonly fixedDt = 1 / 60;
  private worldQueryGroups = groups(0xffff, GROUP_WORLD | GROUP_DEBRIS);
  private staticOnlyGroups = groups(0xffff, GROUP_WORLD);
  stepHooks: ((dt: number) => void)[] = [];

  static async create() {
    await RAPIER.init();
    const p = new Physics();
    p.world = new RAPIER.World({ x: 0, y: -18, z: 0 });
    p.world.timestep = p.fixedDt;
    return p;
  }

  private rot(rot?: THREE.Euler | THREE.Quaternion) {
    if (!rot) return { x: 0, y: 0, z: 0, w: 1 };
    if (rot instanceof THREE.Euler) _q.setFromEuler(rot);
    else _q.copy(rot);
    return { x: _q.x, y: _q.y, z: _q.z, w: _q.w };
  }

  private finishStatic(desc: RAPIER.ColliderDesc, pos: THREE.Vector3, rot: THREE.Euler | THREE.Quaternion | undefined, mat: SurfaceMat) {
    desc.setTranslation(pos.x, pos.y, pos.z).setRotation(this.rot(rot)).setFriction(0.6);
    desc.setCollisionGroups(groups(GROUP_WORLD, 0xffff));
    const c = this.world.createCollider(desc);
    this.matByHandle.set(c.handle, mat);
    return c;
  }

  /** Static box. `half` are half extents. */
  box(pos: THREE.Vector3, half: THREE.Vector3, mat: SurfaceMat, rot?: THREE.Euler | THREE.Quaternion) {
    return this.finishStatic(RAPIER.ColliderDesc.cuboid(half.x, half.y, half.z), pos, rot, mat);
  }
  cylinder(pos: THREE.Vector3, halfHeight: number, radius: number, mat: SurfaceMat, rot?: THREE.Euler | THREE.Quaternion) {
    return this.finishStatic(RAPIER.ColliderDesc.cylinder(halfHeight, radius), pos, rot, mat);
  }
  cone(pos: THREE.Vector3, halfHeight: number, radius: number, mat: SurfaceMat) {
    return this.finishStatic(RAPIER.ColliderDesc.cone(halfHeight, radius), pos, undefined, mat);
  }
  ball(pos: THREE.Vector3, radius: number, mat: SurfaceMat) {
    return this.finishStatic(RAPIER.ColliderDesc.ball(radius), pos, undefined, mat);
  }
  /** Solid convex hull (wedges etc). Points are world-space. */
  convex(points: THREE.Vector3[], mat: SurfaceMat) {
    const arr = new Float32Array(points.length * 3);
    points.forEach((p, i) => arr.set([p.x, p.y, p.z], i * 3));
    const desc = RAPIER.ColliderDesc.convexHull(arr);
    if (!desc) throw new Error('convex hull failed');
    return this.finishStatic(desc, new THREE.Vector3(), undefined, mat);
  }
  /**
   * A ramp built from a rotated box: goes from `from` (low end, top-surface point) to `to` (high end).
   * `width` across, `thickness` below the walking surface.
   */
  ramp(from: THREE.Vector3, to: THREE.Vector3, width: number, mat: SurfaceMat, thickness = 0.4) {
    const dir = new THREE.Vector3().subVectors(to, from);
    const len = dir.length();
    const mid = new THREE.Vector3().addVectors(from, to).multiplyScalar(0.5);
    const yaw = Math.atan2(dir.x, dir.z);
    const pitch = -Math.asin(dir.y / len);
    const e = new THREE.Euler(pitch, yaw, 0, 'YXZ');
    const q = new THREE.Quaternion().setFromEuler(e);
    // push the box down by half thickness along the ramp's local up so the top face is the walking surface
    const up = new THREE.Vector3(0, 1, 0).applyQuaternion(q);
    mid.addScaledVector(up, -thickness / 2);
    const c = this.box(mid, new THREE.Vector3(width / 2, thickness / 2, len / 2), mat, q);
    return { collider: c, center: mid, quat: q, length: len };
  }

  /** Kinematic body for moving obstacles (rc cars). */
  kinematicBox(pos: THREE.Vector3, half: THREE.Vector3, mat: SurfaceMat) {
    const body = this.world.createRigidBody(RAPIER.RigidBodyDesc.kinematicPositionBased().setTranslation(pos.x, pos.y, pos.z));
    const desc = RAPIER.ColliderDesc.cuboid(half.x, half.y, half.z).setCollisionGroups(groups(GROUP_WORLD, 0xffff));
    const c = this.world.createCollider(desc, body);
    this.matByHandle.set(c.handle, mat);
    return { body, collider: c };
  }

  /** Dynamic debris (loose bricks, falling blocks). */
  dynamicBox(pos: THREE.Vector3, half: THREE.Vector3, mat: SurfaceMat, density = 0.6, rot?: THREE.Euler | THREE.Quaternion) {
    const body = this.world.createRigidBody(
      RAPIER.RigidBodyDesc.dynamic().setTranslation(pos.x, pos.y, pos.z).setRotation(this.rot(rot)).setCcdEnabled(true).setLinearDamping(0.2).setAngularDamping(0.4),
    );
    const desc = RAPIER.ColliderDesc.cuboid(half.x, half.y, half.z)
      .setDensity(density)
      .setFriction(0.7)
      .setRestitution(0.25)
      .setCollisionGroups(groups(GROUP_DEBRIS, 0xffff));
    const c = this.world.createCollider(desc, body);
    this.matByHandle.set(c.handle, mat);
    return { body, collider: c };
  }
  removeBody(body: RAPIER.RigidBody) {
    body.collider(0) && this.matByHandle.delete(body.collider(0).handle);
    this.world.removeRigidBody(body);
  }

  /**
   * Character capsule. It is a body-less collider that we teleport every frame, so the
   * character controller always sees its exact current position regardless of frame rate.
   */
  character(feet: THREE.Vector3, radius: number, halfHeight: number) {
    const collider = this.world.createCollider(
      RAPIER.ColliderDesc.capsule(halfHeight, radius)
        .setTranslation(feet.x, feet.y + halfHeight + radius, feet.z)
        .setCollisionGroups(groups(GROUP_CHAR, GROUP_WORLD | GROUP_DEBRIS)),
    );
    return { collider };
  }
  controller() {
    const cc = this.world.createCharacterController(0.02);
    cc.setUp({ x: 0, y: 1, z: 0 });
    cc.setMaxSlopeClimbAngle(50 * (Math.PI / 180));
    cc.setMinSlopeSlideAngle(55 * (Math.PI / 180));
    cc.enableAutostep(0.56, 0.2, false);
    cc.enableSnapToGround(0.35);
    cc.setSlideEnabled(true);
    cc.setApplyImpulsesToDynamicBodies(true);
    cc.setCharacterMass(4);
    return cc;
  }
  charQueryGroups() {
    return groups(GROUP_CHAR, GROUP_WORLD | GROUP_DEBRIS);
  }

  matOf(c: RAPIER.Collider): SurfaceMat {
    return this.matByHandle.get(c.handle) ?? 'plastic';
  }

  /** Raycast against world + debris (never characters). */
  raycast(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number, staticOnly = false): RayHit | null {
    const ray = new RAPIER.Ray({ x: origin.x, y: origin.y, z: origin.z }, { x: dir.x, y: dir.y, z: dir.z });
    const hit = this.world.castRayAndGetNormal(ray, maxDist, true, undefined, staticOnly ? this.staticOnlyGroups : this.worldQueryGroups);
    if (!hit) return null;
    const t = hit.timeOfImpact;
    const parent = hit.collider.parent();
    return {
      dist: t,
      point: new THREE.Vector3(origin.x + dir.x * t, origin.y + dir.y * t, origin.z + dir.z * t),
      normal: new THREE.Vector3(hit.normal.x, hit.normal.y, hit.normal.z),
      mat: this.matOf(hit.collider),
      collider: hit.collider,
      dynamicBody: parent && parent.isDynamic() ? parent : null,
    };
  }
  /** Fast distance-only raycast. */
  rayDist(origin: THREE.Vector3, dir: THREE.Vector3, maxDist: number, staticOnly = false) {
    const ray = new RAPIER.Ray({ x: origin.x, y: origin.y, z: origin.z }, { x: dir.x, y: dir.y, z: dir.z });
    const hit = this.world.castRay(ray, maxDist, true, undefined, staticOnly ? this.staticOnlyGroups : this.worldQueryGroups);
    return hit ? hit.timeOfImpact : Infinity;
  }
  private _d = new THREE.Vector3();
  /** Line of sight between two points (world only). */
  los(a: THREE.Vector3, b: THREE.Vector3, staticOnly = false) {
    this._d.subVectors(b, a);
    const len = this._d.length();
    if (len < 1e-4) return true;
    this._d.divideScalar(len);
    return this.rayDist(a, this._d, len - 0.05, staticOnly) === Infinity;
  }
  /** Does a capsule fit here (no overlap with world)? */
  capsuleFits(feet: THREE.Vector3, radius: number, halfHeight: number, staticOnly = true) {
    const shape = new RAPIER.Capsule(halfHeight, radius);
    let hit = false;
    this.world.intersectionsWithShape(
      { x: feet.x, y: feet.y + halfHeight + radius + 0.05, z: feet.z },
      { x: 0, y: 0, z: 0, w: 1 },
      shape,
      () => {
        hit = true;
        return false;
      },
      undefined,
      staticOnly ? this.staticOnlyGroups : this.worldQueryGroups,
    );
    return !hit;
  }

  /** Make freshly created colliders visible to raycasts before the first step. */
  refreshQueries() {
    this.world.propagateModifiedBodyPositionsToColliders();
    this.world.updateSceneQueries();
  }

  update(dt: number) {
    this.acc += dt;
    let steps = 0;
    while (this.acc >= this.fixedDt && steps < 4) {
      for (const h of this.stepHooks) h(this.fixedDt);
      this.world.step();
      this.acc -= this.fixedDt;
      steps++;
    }
    if (steps === 4) this.acc = 0;
  }
}

import * as THREE from 'three';
import { metal, plastic } from '../render/materials';

/** Spring Hook visuals: a coiled-looking cord from the hand to a little claw stuck in the surface. */
export class Ropes {
  private group = new THREE.Group();
  private pool: { cord: THREE.Mesh; hook: THREE.Group; used: boolean }[] = [];
  private up = new THREE.Vector3(0, 1, 0);

  constructor(scene: THREE.Scene) {
    scene.add(this.group);
  }

  private make() {
    const geo = new THREE.CylinderGeometry(0.03, 0.03, 1, 6);
    geo.translate(0, 0.5, 0);
    const cord = new THREE.Mesh(geo, plastic('#ffd23f', { rough: 0.4 }));
    cord.frustumCulled = false;
    const hook = new THREE.Group();
    const steel = metal('#d6dbe3', 0.25);
    hook.add(new THREE.Mesh(new THREE.SphereGeometry(0.12, 10, 8), plastic('#e63946')));
    for (let i = 0; i < 3; i++) {
      const claw = new THREE.Mesh(new THREE.TorusGeometry(0.16, 0.035, 6, 10, Math.PI), steel);
      claw.rotation.y = (i / 3) * Math.PI * 2;
      claw.position.y = -0.05;
      hook.add(claw);
    }
    this.group.add(cord, hook);
    const r = { cord, hook, used: false };
    this.pool.push(r);
    return r;
  }

  /** Call begin(), then draw() for every active hook this frame, then end(). */
  begin() {
    for (const r of this.pool) r.used = false;
  }
  draw(from: THREE.Vector3, to: THREE.Vector3, t: number) {
    const r = this.pool.find((x) => !x.used) ?? this.make();
    r.used = true;
    // the hook flies out over the first ~0.12 s
    const k = Math.min(1, t / 0.12);
    const end = from.clone().lerp(to, k);
    const d = end.clone().sub(from);
    const len = Math.max(0.01, d.length());
    r.cord.position.copy(from);
    r.cord.quaternion.setFromUnitVectors(this.up, d.divideScalar(len));
    r.cord.scale.set(1, len, 1);
    r.hook.position.copy(end);
    r.hook.quaternion.copy(r.cord.quaternion);
  }
  end() {
    for (const r of this.pool) r.cord.visible = r.hook.visible = r.used;
  }
  clear() {
    for (const r of this.pool) r.cord.visible = r.hook.visible = false;
  }
}

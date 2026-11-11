import * as THREE from 'three';
import { softDotTexture } from '../render/textures';
import type { Actor } from '../entities/Actor';
import type { NavGraph } from '../nav/NavGraph';

/** What the game needs from a map's background life. */
export interface AmbientLike {
  ambienceOn: boolean;
  update(dt: number, actors: Actor[], hurt: (a: Actor, dmg: number, pos: THREE.Vector3) => void, listener: THREE.Vector3): void;
  blockDrop(nav: NavGraph, count?: number): void;
  clearBlocks(): void;
  startSounds(): void;
  stopSounds(): void;
  setReducedMotion(r: boolean): void;
}

/** Backyard background life: drifting clouds and butterflies. No hazards. */
export class YardAmbient implements AmbientLike {
  ambienceOn = false;
  private clouds: THREE.Sprite[] = [];
  private flies: { g: THREE.Group; wings: THREE.Mesh[]; c: THREE.Vector3; r: number; sp: number; ph: number; h: number }[] = [];
  private t = 0;
  private reduced = false;

  constructor(scene: THREE.Scene) {
    const dot = softDotTexture();
    for (let i = 0; i < 14; i++) {
      const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: dot, color: '#ffffff', transparent: true, opacity: 0.85, depthWrite: false, fog: false }));
      const big = 26 + (i % 4) * 9;
      s.scale.set(big * 2.1, big, 1);
      s.position.set(-150 + ((i * 53) % 300), 62 + (i % 5) * 9, -150 + ((i * 97) % 300));
      scene.add(s);
      this.clouds.push(s);
    }
    const cols = ['#ff9f1c', '#ffd23f', '#9b5de5', '#48cae4', '#ff5d8f', '#ffffff'];
    for (let i = 0; i < 9; i++) {
      const g = new THREE.Group();
      const mat = new THREE.MeshBasicMaterial({ color: cols[i % cols.length], side: THREE.DoubleSide });
      const wings: THREE.Mesh[] = [];
      for (const s of [-1, 1]) {
        const geo = new THREE.CircleGeometry(0.28, 8);
        geo.translate(0.26, 0, 0);
        const w = new THREE.Mesh(geo, mat);
        w.rotation.x = -Math.PI / 2;
        w.scale.x = s;
        g.add(w);
        wings.push(w);
      }
      scene.add(g);
      this.flies.push({ g, wings, c: new THREE.Vector3(-26 + ((i * 17) % 52), 0, -26 + ((i * 29) % 52)), r: 3 + (i % 4) * 1.6, sp: 0.5 + (i % 3) * 0.22, ph: i * 1.7, h: 3 + (i % 5) * 1.5 });
    }
  }

  update(dt: number) {
    this.t += dt;
    for (const c of this.clouds) {
      c.position.x += dt * 1.6;
      if (c.position.x > 160) c.position.x = -160;
    }
    const k = this.reduced ? 0.4 : 1;
    for (const f of this.flies) {
      const a = this.t * f.sp * k + f.ph;
      f.g.position.set(f.c.x + Math.cos(a) * f.r, f.h + Math.sin(a * 2.3) * 0.8, f.c.z + Math.sin(a * 1.3) * f.r);
      f.g.rotation.y = -a;
      const flap = Math.sin(this.t * 22 * k + f.ph) * 0.9;
      f.wings[0].rotation.y = flap;
      f.wings[1].rotation.y = -flap;
    }
  }
  blockDrop() {}
  clearBlocks() {}
  startSounds() {}
  stopSounds() {}
  setReducedMotion(r: boolean) {
    this.reduced = r;
  }
}

import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/examples/jsm/geometries/RoundedBoxGeometry.js';
import { plastic, metal } from '../render/materials';
import { cardboardTexture } from '../render/textures';
import type { HillState } from '../match/Match';
import { TEAMS } from '../match/modes';

export const WALL_VS = /* glsl */ `
varying vec2 vUv;
void main() {
  vUv = uv;
  gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0);
}`;
export const WALL_FS = /* glsl */ `
uniform vec3 uColor;
uniform float uTime;
uniform float uAlpha;
varying vec2 vUv;
void main() {
  float fade = pow(1.0 - vUv.y, 1.6);
  float stripes = 0.65 + 0.35 * sin(vUv.x * 120.0 + uTime * 3.0);
  float rise = 0.5 + 0.5 * sin(vUv.y * 18.0 - uTime * 4.0);
  float a = (fade * 0.42 + fade * rise * 0.18 + 0.04) * stripes * uAlpha;
  gl_FragColor = vec4(uColor, a);
}`;

/** The giant toy box capture zone for Toy Box Takeover. */
export class HillZone {
  group = new THREE.Group();
  private wall: THREE.Mesh;
  private ring: THREE.Mesh;
  private box = new THREE.Group();
  private key = new THREE.Group();
  private wallMat: THREE.ShaderMaterial;
  private ringMat: THREE.MeshBasicMaterial;
  private dropT = 1;
  private sitePos = new THREE.Vector3();
  private radius = 4;
  private height = 4;
  private color = new THREE.Color('#ffffff');
  private time = 0;

  constructor(scene: THREE.Scene) {
    scene.add(this.group);
    this.wallMat = new THREE.ShaderMaterial({
      vertexShader: WALL_VS,
      fragmentShader: WALL_FS,
      uniforms: { uColor: { value: new THREE.Color('#ffffff') }, uTime: { value: 0 }, uAlpha: { value: 1 } },
      transparent: true,
      depthWrite: false,
      side: THREE.DoubleSide,
    });
    this.wall = new THREE.Mesh(new THREE.CylinderGeometry(1, 1, 1, 64, 1, true), this.wallMat);
    this.wall.frustumCulled = false;
    this.wall.renderOrder = 5;
    this.ringMat = new THREE.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false, toneMapped: false });
    this.ring = new THREE.Mesh(new THREE.RingGeometry(0.93, 1, 72), this.ringMat);
    this.ring.rotation.x = -Math.PI / 2;
    this.ring.renderOrder = 5;
    // floating open toy box with a wind-up key on top
    const card = new THREE.MeshStandardMaterial({ map: cardboardTexture('TOYS'), roughness: 0.85 });
    const s = 1.5;
    const wallGeo = new RoundedBoxGeometry(s, s * 0.8, 0.08, 1, 0.02);
    for (let i = 0; i < 4; i++) {
      const w = new THREE.Mesh(wallGeo, card);
      const a = (i * Math.PI) / 2;
      w.position.set(Math.sin(a) * s * 0.5, 0, Math.cos(a) * s * 0.5);
      w.rotation.y = a;
      this.box.add(w);
      const flap = new THREE.Mesh(new RoundedBoxGeometry(s, 0.06, s * 0.45, 1, 0.02), card);
      flap.position.set(Math.sin(a) * s * 0.68, s * 0.42, Math.cos(a) * s * 0.68);
      flap.rotation.y = a;
      flap.rotateX(-0.7);
      this.box.add(flap);
    }
    const bottom = new THREE.Mesh(new RoundedBoxGeometry(s, 0.08, s, 1, 0.02), card);
    bottom.position.y = -s * 0.4;
    this.box.add(bottom);
    // toys peeking out
    const toyCols = ['#ef476f', '#ffd166', '#06d6a0', '#118ab2'];
    toyCols.forEach((c, i) => {
      const t = new THREE.Mesh(i % 2 ? new THREE.SphereGeometry(0.25, 14, 10) : new RoundedBoxGeometry(0.4, 0.4, 0.4, 2, 0.08), plastic(c));
      t.position.set((i % 2 ? 0.3 : -0.3) * (i > 1 ? -1 : 1), 0.25, (i > 1 ? 0.3 : -0.3));
      this.box.add(t);
    });
    const shaft = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.08, 0.9, 10), metal('#d4af37', 0.25));
    shaft.position.y = 0.45;
    this.key.add(shaft);
    for (const x of [-0.4, 0.4]) {
      const loop = new THREE.Mesh(new THREE.TorusGeometry(0.3, 0.08, 10, 24), metal('#d4af37', 0.25));
      loop.position.set(x, 1.05, 0);
      this.key.add(loop);
    }
    this.key.position.y = s * 0.3;
    this.box.add(this.key);
    this.box.traverse((o) => ((o as THREE.Mesh).isMesh ? ((o as THREE.Mesh).castShadow = true) : null));
    this.group.add(this.wall, this.ring, this.box);
    this.group.visible = false;
  }

  hide() {
    this.group.visible = false;
  }

  /** Move to a new site with a little drop-in animation. */
  place(pos: THREE.Vector3, radius: number, height: number, animate = true) {
    this.sitePos.copy(pos);
    this.radius = radius;
    this.height = height;
    this.group.visible = true;
    this.wall.scale.set(radius, height, radius);
    this.wall.position.set(pos.x, pos.y + height / 2, pos.z);
    this.ring.scale.set(radius, radius, radius);
    this.ring.position.set(pos.x, pos.y + 0.07, pos.z);
    this.dropT = animate ? 0 : 1;
  }

  update(dt: number, h: HillState | null, reduced: boolean) {
    if (!h) {
      this.group.visible = false;
      return;
    }
    this.time += dt;
    this.dropT = Math.min(1, this.dropT + dt / 0.9);
    const e = 1 - Math.pow(1 - this.dropT, 3);
    const hover = this.sitePos.y + this.height + 1.2;
    this.box.position.set(this.sitePos.x, hover + (1 - e) * 14 + (reduced ? 0 : Math.sin(this.time * 1.5) * 0.15), this.sitePos.z);
    this.box.rotation.y += dt * 0.35;
    const scoring = h.owner >= 0;
    this.key.rotation.y += dt * (scoring ? 6 : 0.8);
    // color: team when held, flashing pink when contested, white when empty
    if (h.contested) this.color.set(Math.sin(this.time * 12) > 0 ? '#ff4d8d' : '#ffffff');
    else if (h.owner >= 0) this.color.set(TEAMS[h.owner].color);
    else this.color.set('#fff6d8');
    this.wallMat.uniforms.uColor.value.lerp(this.color, Math.min(1, dt * 10));
    this.wallMat.uniforms.uTime.value = this.time;
    this.wallMat.uniforms.uAlpha.value = (0.75 + (scoring ? 0.35 : 0)) * e;
    this.ringMat.color.copy(this.wallMat.uniforms.uColor.value);
    // pulse in the last 10 seconds before it moves
    const warn = h.timeLeft < 10 ? 0.5 + 0.5 * Math.sin(this.time * 10) : 1;
    this.ringMat.opacity = 0.85 * warn;
  }
}

import * as THREE from 'three';
import { plastic, metal } from '../render/materials';
import { WALL_FS, WALL_VS } from './HillZone';
import type { SectorState } from '../match/Match';
import { TEAMS } from '../match/modes';

interface Visual {
  group: THREE.Group;
  wallMat: THREE.ShaderMaterial;
  ringMat: THREE.MeshBasicMaterial;
  flag: THREE.Mesh;
  flagMat: THREE.MeshStandardMaterial;
  badge: THREE.Sprite;
  badgeCanvas: HTMLCanvasElement;
  badgeTex: THREE.CanvasTexture;
  lastBadge: string;
  height: number;
  color: THREE.Color;
}

const NEUTRAL = '#fff6d8';
const CONTESTED = '#ff4d8d';

/** The six Conquest sectors: soft cylinder wall, floor ring, a flag that climbs as a team captures, and a letter badge. */
export class SectorZones {
  group = new THREE.Group();
  private vis: Visual[] = [];
  private time = 0;

  constructor(scene: THREE.Scene) {
    scene.add(this.group);
    this.group.visible = false;
  }

  build(sectors: SectorState[]) {
    this.clear();
    for (const s of sectors) {
      const g = new THREE.Group();
      g.position.copy(s.pos);
      const r = s.def.radius, h = s.def.height;
      const wallMat = new THREE.ShaderMaterial({
        vertexShader: WALL_VS,
        fragmentShader: WALL_FS,
        uniforms: { uColor: { value: new THREE.Color(NEUTRAL) }, uTime: { value: 0 }, uAlpha: { value: 0.55 } },
        transparent: true,
        depthWrite: false,
        side: THREE.DoubleSide,
      });
      const wall = new THREE.Mesh(new THREE.CylinderGeometry(r, r, h, 56, 1, true), wallMat);
      wall.position.y = h / 2;
      wall.renderOrder = 5;
      const ringMat = new THREE.MeshBasicMaterial({ color: NEUTRAL, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false, toneMapped: false });
      const ring = new THREE.Mesh(new THREE.RingGeometry(r - 0.3, r, 64), ringMat);
      ring.rotation.x = -Math.PI / 2;
      ring.position.y = 0.07;
      ring.renderOrder = 5;
      // flag pole in the middle
      const poleH = h + 2.2;
      const pole = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.09, poleH, 10), metal('#e0e0e0', 0.3));
      pole.position.y = poleH / 2;
      pole.castShadow = true;
      const knob = new THREE.Mesh(new THREE.SphereGeometry(0.16, 12, 10), plastic('#ffd23f'));
      knob.position.y = poleH + 0.1;
      const flagMat = new THREE.MeshStandardMaterial({ color: NEUTRAL, roughness: 0.7, side: THREE.DoubleSide, emissive: NEUTRAL, emissiveIntensity: 0.25 });
      const fg = new THREE.PlaneGeometry(1.5, 0.95, 6, 1);
      fg.translate(0.75, 0, 0);
      const flag = new THREE.Mesh(fg, flagMat);
      flag.castShadow = true;
      const base = new THREE.Mesh(new THREE.CylinderGeometry(0.5, 0.6, 0.25, 16), plastic('#555b6e'));
      base.position.y = 0.12;
      // floating letter badge
      const badgeCanvas = document.createElement('canvas');
      badgeCanvas.width = badgeCanvas.height = 128;
      const badgeTex = new THREE.CanvasTexture(badgeCanvas);
      badgeTex.colorSpace = THREE.SRGBColorSpace;
      const badge = new THREE.Sprite(new THREE.SpriteMaterial({ map: badgeTex, depthWrite: false, transparent: true, toneMapped: false }));
      badge.scale.setScalar(1.5);
      badge.position.y = poleH + 1.3;
      g.add(wall, ring, pole, knob, flag, base, badge);
      this.group.add(g);
      const v: Visual = { group: g, wallMat, ringMat, flag, flagMat, badge, badgeCanvas, badgeTex, lastBadge: '', height: poleH, color: new THREE.Color(NEUTRAL) };
      this.vis.push(v);
    }
    this.group.visible = sectors.length > 0;
  }

  private drawBadge(v: Visual, letter: string, color: string, ring: string, progress: number) {
    const key = `${letter}|${color}|${ring}|${Math.round(progress * 20)}`;
    if (key === v.lastBadge) return;
    v.lastBadge = key;
    const ctx = v.badgeCanvas.getContext('2d')!;
    ctx.clearRect(0, 0, 128, 128);
    ctx.beginPath();
    ctx.arc(64, 64, 52, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.lineWidth = 10;
    ctx.strokeStyle = 'rgba(0,0,0,0.35)';
    ctx.stroke();
    if (progress > 0 && progress < 1) {
      ctx.beginPath();
      ctx.arc(64, 64, 58, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * progress);
      ctx.strokeStyle = ring;
      ctx.lineWidth = 10;
      ctx.stroke();
    }
    ctx.fillStyle = '#1d1d1f';
    ctx.font = 'bold 66px "Luckiest Guy", Impact, sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText(letter, 64, 70);
    v.badgeTex.needsUpdate = true;
  }

  update(dt: number, sectors: SectorState[]) {
    if (!sectors.length || !this.vis.length) {
      this.group.visible = false;
      return;
    }
    this.group.visible = true;
    this.time += dt;
    sectors.forEach((s, i) => {
      const v = this.vis[i];
      if (!v) return;
      const ownerCol = s.owner >= 0 ? TEAMS[s.owner].color : NEUTRAL;
      const actCol = s.active >= 0 ? TEAMS[s.active].color : ownerCol;
      let target: string;
      if (s.contested) target = Math.sin(this.time * 12) > 0 ? CONTESTED : '#ffffff';
      else if (s.active >= 0 && s.active !== s.owner) target = Math.sin(this.time * 8) > 0 ? actCol : ownerCol;
      else target = ownerCol;
      v.color.lerp(new THREE.Color(target), Math.min(1, dt * 10));
      v.wallMat.uniforms.uColor.value.copy(v.color);
      v.wallMat.uniforms.uTime.value = this.time;
      v.wallMat.uniforms.uAlpha.value = s.owner >= 0 ? 0.7 : 0.5;
      v.ringMat.color.copy(v.color);
      // flag: owned = flag at the top in the owner's color, shrinking as it's drained;
      // neutral = the capturing team's flag climbing with progress
      const flagTeam = s.owner >= 0 ? s.owner : s.progressTeam;
      const h = s.owner >= 0 ? s.progress : s.progressTeam >= 0 ? s.progress : 0;
      v.flagMat.color.set(flagTeam >= 0 ? TEAMS[flagTeam].color : NEUTRAL);
      v.flagMat.emissive.copy(v.flagMat.color);
      v.flag.position.y = 0.6 + (v.height - 1.2) * h;
      v.flag.rotation.y = Math.sin(this.time * 2 + i) * 0.25;
      const pos = v.flag.geometry.getAttribute('position') as THREE.BufferAttribute;
      for (let k = 0; k < pos.count; k++) {
        const x = pos.getX(k);
        pos.setZ(k, Math.sin(x * 3 - this.time * 6 + i) * 0.08 * x);
      }
      pos.needsUpdate = true;
      this.drawBadge(v, s.def.letter, s.owner >= 0 ? TEAMS[s.owner].light : '#fff6d8', s.active >= 0 ? TEAMS[s.active].color : '#ffffff', s.owner >= 0 ? (s.progress < 1 ? s.progress : 0) : s.progress);
    });
  }

  clear() {
    for (const v of this.vis) {
      this.group.remove(v.group);
      v.wallMat.dispose();
      v.ringMat.dispose();
      v.flagMat.dispose();
      v.badgeTex.dispose();
    }
    this.vis = [];
    this.group.visible = false;
  }
}

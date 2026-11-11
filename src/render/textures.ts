import * as THREE from 'three';
import { seeded } from '../core/math';

/** Procedural canvas textures. Everything is generated at startup so the game needs no external assets. */

function canvas(w: number, h: number) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  const ctx = c.getContext('2d')!;
  return { c, ctx };
}

function tex(c: HTMLCanvasElement, srgb: boolean, repeat = 1) {
  const t = new THREE.CanvasTexture(c);
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(repeat, repeat);
  t.colorSpace = srgb ? THREE.SRGBColorSpace : THREE.NoColorSpace;
  t.anisotropy = 8;
  t.needsUpdate = true;
  return t;
}

function noiseFill(ctx: CanvasRenderingContext2D, w: number, h: number, base: number, amp: number, rnd: () => number) {
  const img = ctx.getImageData(0, 0, w, h);
  for (let i = 0; i < img.data.length; i += 4) {
    const n = base + (rnd() - 0.5) * amp;
    img.data[i] = img.data[i + 1] = img.data[i + 2] = n;
    img.data[i + 3] = 255;
  }
  ctx.putImageData(img, 0, 0);
}

const cache = new Map<string, THREE.Texture>();
function cached(key: string, make: () => THREE.Texture) {
  let t = cache.get(key);
  if (!t) {
    t = make();
    cache.set(key, t);
  }
  return t;
}

/** Roughness map with fine scratches for plastic. Grey ~ base roughness, lighter lines = scuffs. */
export function scratchRoughness() {
  return cached('scratch', () => {
    const { c, ctx } = canvas(512, 512);
    const r = seeded(11);
    noiseFill(ctx, 512, 512, 95, 18, r);
    ctx.lineCap = 'round';
    for (let i = 0; i < 260; i++) {
      const x = r() * 512, y = r() * 512;
      const a = r() * Math.PI * 2;
      const len = 6 + r() * 50;
      ctx.strokeStyle = `rgba(255,255,255,${0.12 + r() * 0.3})`;
      ctx.lineWidth = 0.4 + r() * 1.1;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.quadraticCurveTo(x + Math.cos(a + 0.3) * len * 0.5, y + Math.sin(a + 0.3) * len * 0.5, x + Math.cos(a) * len, y + Math.sin(a) * len);
      ctx.stroke();
    }
    // a few soft smudges
    for (let i = 0; i < 30; i++) {
      const g = ctx.createRadialGradient(r() * 512, r() * 512, 0, 0, 0, 0);
      void g;
      ctx.fillStyle = `rgba(160,160,160,${0.05 + r() * 0.08})`;
      ctx.beginPath();
      ctx.arc(r() * 512, r() * 512, 10 + r() * 40, 0, Math.PI * 2);
      ctx.fill();
    }
    return tex(c, false, 1);
  });
}

export function woodTexture(kind: 'floor' | 'desk' | 'bed' | 'block') {
  return cached('wood-' + kind, () => {
    const W = 1024, H = 1024;
    const { c, ctx } = canvas(W, H);
    const r = seeded(kind.length * 31 + 7);
    const palettes: Record<string, [number, number, number][]> = {
      floor: [[176, 120, 72], [160, 104, 60], [190, 134, 84], [150, 98, 58]],
      desk: [[205, 160, 110], [196, 150, 100], [214, 170, 120]],
      bed: [[236, 222, 200], [228, 214, 190]],
      block: [[226, 190, 140], [216, 178, 126]],
    };
    const pal = palettes[kind];
    const planks = kind === 'floor' ? 8 : kind === 'desk' ? 5 : 3;
    const ph = H / planks;
    for (let p = 0; p < planks; p++) {
      const col = pal[p % pal.length];
      const off = (r() - 0.5) * 18;
      ctx.fillStyle = `rgb(${col[0] + off},${col[1] + off},${col[2] + off})`;
      ctx.fillRect(0, p * ph, W, ph);
      // grain lines
      for (let g = 0; g < 70; g++) {
        const y0 = p * ph + r() * ph;
        ctx.strokeStyle = `rgba(${60 + r() * 40},${35 + r() * 20},${15},${0.06 + r() * 0.12})`;
        ctx.lineWidth = 0.6 + r() * 2.2;
        ctx.beginPath();
        ctx.moveTo(0, y0);
        for (let x = 0; x <= W; x += 32) ctx.lineTo(x, y0 + Math.sin(x * 0.01 + g) * (2 + r() * 3));
        ctx.stroke();
      }
      // knots
      if (r() > 0.4) {
        const kx = r() * W, ky = p * ph + ph * (0.3 + r() * 0.4);
        for (let k = 0; k < 6; k++) {
          ctx.strokeStyle = `rgba(80,45,20,${0.15 + k * 0.03})`;
          ctx.lineWidth = 1.5;
          ctx.beginPath();
          ctx.ellipse(kx, ky, 18 - k * 2.5, 7 - k, 0, 0, Math.PI * 2);
          ctx.stroke();
        }
      }
      // plank seam
      if (kind === 'floor') {
        ctx.fillStyle = 'rgba(40,22,10,0.55)';
        ctx.fillRect(0, p * ph, W, 3);
        const seamX = r() * W;
        ctx.fillRect(seamX, p * ph, 3, ph);
      }
    }
    // scratches on top
    for (let i = 0; i < 120; i++) {
      ctx.strokeStyle = `rgba(255,240,220,${0.04 + r() * 0.08})`;
      ctx.lineWidth = 0.7;
      const x = r() * W, y = r() * H;
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(x + (r() - 0.5) * 80, y + (r() - 0.5) * 20);
      ctx.stroke();
    }
    return tex(c, true, 1);
  });
}

export function carpetTexture() {
  return cached('carpet', () => {
    const W = 1024;
    const { c, ctx } = canvas(W, W);
    const r = seeded(5);
    // Play rug: soft teal with a big colorful pattern
    ctx.fillStyle = '#4bb3a8';
    ctx.fillRect(0, 0, W, W);
    ctx.fillStyle = '#f6c443';
    ctx.beginPath();
    ctx.arc(W / 2, W / 2, W * 0.42, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#ef6f6c';
    ctx.beginPath();
    ctx.arc(W / 2, W / 2, W * 0.3, 0, Math.PI * 2);
    ctx.fill();
    ctx.fillStyle = '#5a7fd6';
    ctx.beginPath();
    ctx.arc(W / 2, W / 2, W * 0.17, 0, Math.PI * 2);
    ctx.fill();
    // star in the middle
    ctx.fillStyle = '#fff3c4';
    ctx.beginPath();
    for (let i = 0; i < 10; i++) {
      const a = (i / 10) * Math.PI * 2 - Math.PI / 2;
      const rr = i % 2 ? W * 0.05 : W * 0.12;
      ctx.lineTo(W / 2 + Math.cos(a) * rr, W / 2 + Math.sin(a) * rr);
    }
    ctx.fill();
    // stitched border
    ctx.strokeStyle = '#fff6e0';
    ctx.lineWidth = 10;
    ctx.setLineDash([26, 18]);
    ctx.strokeRect(30, 30, W - 60, W - 60);
    ctx.setLineDash([]);
    // fiber noise
    const img = ctx.getImageData(0, 0, W, W);
    for (let i = 0; i < img.data.length; i += 4) {
      const n = (r() - 0.5) * 38;
      img.data[i] += n;
      img.data[i + 1] += n;
      img.data[i + 2] += n;
    }
    ctx.putImageData(img, 0, 0);
    return tex(c, true, 1);
  });
}

export function fiberBump(seed = 3, scale = 1) {
  return cached('fiber' + seed + scale, () => {
    const { c, ctx } = canvas(256, 256);
    const r = seeded(seed);
    noiseFill(ctx, 256, 256, 128, 120, r);
    const t = tex(c, false, scale);
    return t;
  });
}

export function quiltTexture(a: string, b: string, stitch = '#ffffff') {
  return cached('quilt' + a + b, () => {
    const W = 512;
    const { c, ctx } = canvas(W, W);
    const n = 4;
    const s = W / n;
    for (let i = 0; i < n; i++)
      for (let j = 0; j < n; j++) {
        ctx.fillStyle = (i + j) % 2 ? a : b;
        ctx.fillRect(i * s, j * s, s, s);
        if ((i + j) % 2 === 0) {
          ctx.fillStyle = 'rgba(255,255,255,0.35)';
          ctx.beginPath();
          ctx.arc(i * s + s / 2, j * s + s / 2, s * 0.18, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    ctx.strokeStyle = stitch;
    ctx.globalAlpha = 0.7;
    ctx.lineWidth = 3;
    ctx.setLineDash([10, 8]);
    for (let i = 0; i <= n; i++) {
      ctx.beginPath();
      ctx.moveTo(i * s, 0);
      ctx.lineTo(i * s, W);
      ctx.stroke();
      ctx.beginPath();
      ctx.moveTo(0, i * s);
      ctx.lineTo(W, i * s);
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
    ctx.setLineDash([]);
    const r = seeded(9);
    const img = ctx.getImageData(0, 0, W, W);
    for (let i = 0; i < img.data.length; i += 4) {
      const v = (r() - 0.5) * 20;
      img.data[i] += v;
      img.data[i + 1] += v;
      img.data[i + 2] += v;
    }
    ctx.putImageData(img, 0, 0);
    return tex(c, true, 1);
  });
}

export function cardboardTexture(label?: string) {
  return cached('cardboard' + (label ?? ''), () => {
    const W = 512;
    const { c, ctx } = canvas(W, W);
    const r = seeded(21 + (label?.length ?? 0));
    ctx.fillStyle = '#c69a62';
    ctx.fillRect(0, 0, W, W);
    for (let i = 0; i < W; i += 6) {
      ctx.fillStyle = `rgba(120,80,40,${0.05 + r() * 0.05})`;
      ctx.fillRect(i, 0, 2, W);
    }
    for (let i = 0; i < 400; i++) {
      ctx.fillStyle = `rgba(90,60,30,${r() * 0.12})`;
      ctx.fillRect(r() * W, r() * W, 1 + r() * 4, 1 + r() * 4);
    }
    // tape strip
    ctx.fillStyle = 'rgba(220,190,130,0.75)';
    ctx.fillRect(W * 0.42, 0, W * 0.16, W);
    if (label) {
      ctx.save();
      ctx.translate(W / 2, W * 0.7);
      ctx.rotate(-0.05);
      ctx.font = 'bold 64px "Luckiest Guy", Impact, sans-serif';
      ctx.textAlign = 'center';
      ctx.fillStyle = 'rgba(160,40,30,0.85)';
      ctx.fillText(label, 0, 0);
      ctx.restore();
    }
    return tex(c, true, 1);
  });
}

export function wallpaperTexture() {
  return cached('wallpaper', () => {
    const W = 512;
    const { c, ctx } = canvas(W, W);
    ctx.fillStyle = '#bfe0f2';
    ctx.fillRect(0, 0, W, W);
    for (let i = 0; i < 8; i++) {
      ctx.fillStyle = i % 2 ? 'rgba(255,255,255,0.35)' : 'rgba(150,200,230,0.25)';
      ctx.fillRect(i * (W / 8), 0, W / 16, W);
    }
    const r = seeded(4);
    const drawStar = (x: number, y: number, s: number, col: string) => {
      ctx.fillStyle = col;
      ctx.beginPath();
      for (let i = 0; i < 10; i++) {
        const a = (i / 10) * Math.PI * 2 - Math.PI / 2;
        const rr = i % 2 ? s * 0.42 : s;
        ctx.lineTo(x + Math.cos(a) * rr, y + Math.sin(a) * rr);
      }
      ctx.fill();
    };
    for (let i = 0; i < 14; i++) drawStar(r() * W, r() * W, 10 + r() * 14, ['#ffe27a', '#ffffff', '#ffb3c7'][i % 3]);
    // little rockets
    for (let i = 0; i < 4; i++) {
      const x = r() * W, y = r() * W;
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(-0.6);
      ctx.fillStyle = '#ff7a6b';
      ctx.fillRect(-6, -18, 12, 30);
      ctx.beginPath();
      ctx.moveTo(-6, -18);
      ctx.lineTo(0, -30);
      ctx.lineTo(6, -18);
      ctx.fill();
      ctx.fillStyle = '#ffd25a';
      ctx.beginPath();
      ctx.moveTo(-5, 12);
      ctx.lineTo(0, 24);
      ctx.lineTo(5, 12);
      ctx.fill();
      ctx.restore();
    }
    return tex(c, true, 1);
  });
}

export function skyTexture() {
  return cached('sky', () => {
    const W = 1024, H = 512;
    const { c, ctx } = canvas(W, H);
    const g = ctx.createLinearGradient(0, 0, 0, H);
    g.addColorStop(0, '#7fb8ec');
    g.addColorStop(0.6, '#ffd7a3');
    g.addColorStop(1, '#ffe9c4');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, H);
    // sun glow
    const sg = ctx.createRadialGradient(W * 0.3, H * 0.45, 0, W * 0.3, H * 0.45, 260);
    sg.addColorStop(0, 'rgba(255,250,230,1)');
    sg.addColorStop(0.15, 'rgba(255,236,180,0.9)');
    sg.addColorStop(1, 'rgba(255,220,160,0)');
    ctx.fillStyle = sg;
    ctx.fillRect(0, 0, W, H);
    const r = seeded(12);
    // clouds
    for (let i = 0; i < 9; i++) {
      const x = r() * W, y = 40 + r() * 160;
      ctx.fillStyle = 'rgba(255,255,255,0.75)';
      for (let k = 0; k < 6; k++) {
        ctx.beginPath();
        ctx.arc(x + k * 26 - 60, y + Math.sin(k) * 8, 22 + r() * 18, 0, Math.PI * 2);
        ctx.fill();
      }
    }
    // hills + trees
    ctx.fillStyle = '#7fae6a';
    ctx.beginPath();
    ctx.moveTo(0, H);
    for (let x = 0; x <= W; x += 16) ctx.lineTo(x, H * 0.78 + Math.sin(x * 0.008) * 30 + Math.sin(x * 0.021) * 12);
    ctx.lineTo(W, H);
    ctx.fill();
    ctx.fillStyle = '#5c8f55';
    for (let i = 0; i < 22; i++) {
      const x = r() * W;
      const y = H * 0.8 + Math.sin(x * 0.008) * 30;
      ctx.beginPath();
      ctx.arc(x, y - 18, 14 + r() * 10, 0, Math.PI * 2);
      ctx.fill();
    }
    return tex(c, true, 1);
  });
}

export function fanShadowTexture() {
  return cached('fanshadow', () => {
    const W = 512;
    const { c, ctx } = canvas(W, W);
    ctx.clearRect(0, 0, W, W);
    ctx.translate(W / 2, W / 2);
    for (let i = 0; i < 4; i++) {
      ctx.save();
      ctx.rotate((i / 4) * Math.PI * 2);
      const g = ctx.createLinearGradient(0, 0, W * 0.45, 0);
      g.addColorStop(0, 'rgba(0,0,0,0.5)');
      g.addColorStop(1, 'rgba(0,0,0,0.0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.ellipse(W * 0.24, 0, W * 0.22, W * 0.06, 0.08, 0, Math.PI * 2);
      ctx.fill();
      ctx.restore();
    }
    ctx.fillStyle = 'rgba(0,0,0,0.45)';
    ctx.beginPath();
    ctx.arc(0, 0, W * 0.06, 0, Math.PI * 2);
    ctx.fill();
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.NoColorSpace;
    return t;
  });
}

export function softDotTexture() {
  return cached('softdot', () => {
    const W = 64;
    const { c, ctx } = canvas(W, W);
    const g = ctx.createRadialGradient(W / 2, W / 2, 0, W / 2, W / 2, W / 2);
    g.addColorStop(0, 'rgba(255,255,255,1)');
    g.addColorStop(0.4, 'rgba(255,255,255,0.6)');
    g.addColorStop(1, 'rgba(255,255,255,0)');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, W, W);
    const t = new THREE.CanvasTexture(c);
    return t;
  });
}

export function decalTexture(kind: 'impact' | 'splat') {
  return cached('decal' + kind, () => {
    const W = 128;
    const { c, ctx } = canvas(W, W);
    const r = seeded(kind === 'impact' ? 77 : 88);
    ctx.translate(W / 2, W / 2);
    if (kind === 'impact') {
      const g = ctx.createRadialGradient(0, 0, 0, 0, 0, W * 0.4);
      g.addColorStop(0, 'rgba(255,255,255,1)');
      g.addColorStop(0.35, 'rgba(255,255,255,0.7)');
      g.addColorStop(1, 'rgba(255,255,255,0)');
      ctx.fillStyle = g;
      ctx.beginPath();
      ctx.arc(0, 0, W * 0.4, 0, Math.PI * 2);
      ctx.fill();
    } else {
      ctx.fillStyle = 'white';
      ctx.beginPath();
      ctx.arc(0, 0, W * 0.24, 0, Math.PI * 2);
      ctx.fill();
      for (let i = 0; i < 14; i++) {
        const a = r() * Math.PI * 2;
        const d = W * (0.18 + r() * 0.22);
        ctx.beginPath();
        ctx.arc(Math.cos(a) * d, Math.sin(a) * d, 3 + r() * 9, 0, Math.PI * 2);
        ctx.fill();
        ctx.lineWidth = 3 + r() * 4;
        ctx.strokeStyle = 'white';
        ctx.beginPath();
        ctx.moveTo(0, 0);
        ctx.lineTo(Math.cos(a) * d, Math.sin(a) * d);
        ctx.stroke();
      }
    }
    const t = new THREE.CanvasTexture(c);
    return t;
  });
}

export function bookTexture(color: string, title: string, seed: number) {
  return cached('book' + color + title, () => {
    const { c, ctx } = canvas(256, 64);
    ctx.fillStyle = color;
    ctx.fillRect(0, 0, 256, 64);
    ctx.fillStyle = 'rgba(255,255,255,0.18)';
    ctx.fillRect(0, 6, 256, 4);
    ctx.fillRect(0, 54, 256, 4);
    ctx.font = 'bold 28px "Baloo 2", sans-serif';
    ctx.fillStyle = 'rgba(255,250,235,0.9)';
    ctx.textBaseline = 'middle';
    ctx.fillText(title, 18, 33);
    void seed;
    return tex(c, true, 1);
  });
}

/** Keyboard top: rows of key labels drawn as a texture laid over instanced keycaps. */
export function keyboardLabelTexture(rows: string[][]) {
  return cached('kblabels', () => {
    const W = 2048, H = 512;
    const { c, ctx } = canvas(W, H);
    ctx.clearRect(0, 0, W, H);
    ctx.fillStyle = 'rgba(40,40,50,0.85)';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    const rh = H / rows.length;
    rows.forEach((row, ri) => {
      const kw = W / row.length;
      ctx.font = `bold ${Math.floor(rh * 0.42)}px "Baloo 2", sans-serif`;
      row.forEach((k, ki) => ctx.fillText(k, kw * (ki + 0.5), rh * (ri + 0.5)));
    });
    const t = new THREE.CanvasTexture(c);
    t.colorSpace = THREE.SRGBColorSpace;
    t.anisotropy = 8;
    return t;
  });
}

export function monitorScreenTexture() {
  const { c, ctx } = canvas(512, 320);
  const draw = (t: number) => {
    const g = ctx.createLinearGradient(0, 0, 512, 320);
    g.addColorStop(0, '#1d2b6b');
    g.addColorStop(1, '#5b2c83');
    ctx.fillStyle = g;
    ctx.fillRect(0, 0, 512, 320);
    ctx.fillStyle = '#ffe36e';
    ctx.font = 'bold 44px "Luckiest Guy", Impact, sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText('LEVEL 99', 256, 90);
    for (let i = 0; i < 8; i++) {
      const x = ((i * 70 + t * 60) % 600) - 40;
      ctx.fillStyle = ['#ff6b8b', '#6bf0ff', '#9dff6b'][i % 3];
      ctx.fillRect(x, 200 + Math.sin(t * 3 + i) * 20, 28, 28);
    }
    ctx.fillStyle = 'rgba(255,255,255,0.08)';
    for (let y = 0; y < 320; y += 4) ctx.fillRect(0, y, 512, 1);
  };
  draw(0);
  const t = new THREE.CanvasTexture(c);
  t.colorSpace = THREE.SRGBColorSpace;
  return { texture: t, update: (time: number) => { draw(time); t.needsUpdate = true; } };
}

export function faceTexture(kind: 'happy' | 'angry' | 'determined' | 'visor', eye = '#222') {
  return cached('face' + kind + eye, () => {
    const W = 256;
    const { c, ctx } = canvas(W, W);
    ctx.clearRect(0, 0, W, W);
    if (kind === 'visor') {
      ctx.fillStyle = eye;
      ctx.shadowColor = eye;
      ctx.shadowBlur = 20;
      ctx.fillRect(40, 100, 176, 40);
    }
    return new THREE.CanvasTexture(c);
  });
}

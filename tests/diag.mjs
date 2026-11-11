import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.addInitScript((q) => { try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = q; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} }, process.env.Q || 'medium');
page.setDefaultTimeout(400000);
await page.goto('http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
const r = await page.evaluate(() => {
  window.__autotest = true;
  const g = window.__toybox;
  const nav = g.nav.nodes;
  const zoneOf = (p) => g.arena.zones.find((z) => p.x >= z.min[0] && p.x <= z.max[0] && p.z >= z.min[1] && p.z <= z.max[1])?.name;
  const navStats = { total: nav.length, elevated: nav.filter((n) => n.pos.y > 2).length, bedTop: nav.filter((n) => n.pos.y > 5.5 && n.pos.y < 6.5 && n.pos.x < -19).length, desk: nav.filter((n) => n.pos.y > 7.5 && n.pos.x > 14).length, underBed: nav.filter((n) => n.pos.y < 0.5 && n.pos.x < -19 && n.pos.z < -12).length, closet: nav.filter((n) => n.pos.x > 20 && n.pos.z > -18 && n.pos.z < 6).length, deck: nav.filter((n) => n.pos.y > 3.5 && n.pos.x > 22 && n.pos.z > 24).length, brachio: nav.filter((n) => n.pos.y > 5 && n.pos.x > -16 && n.pos.x < -8 && n.pos.z > 27).length, tower: nav.filter((n) => n.pos.y > 7 && n.pos.x < -27).length, chest: nav.filter((n) => n.pos.y > 5.5 && n.pos.x > -11 && n.pos.x < -2).length, keyboard: nav.filter((n) => n.pos.y > 8.6 && n.pos.x > 15 && n.pos.x < 29).length };
  g.startMatch('normal');
  g.debugStep(3.5);
  g.debug.invulnerable = true;
  const heat = {}; const elev = {}; let samples = 0;
  for (let i = 0; i < 240; i++) {
    g.debugStep(0.5);
    for (const b of g.bots) { if (!b.actor.alive) continue; const z = zoneOf(b.actor.pos) || '?'; heat[z] = (heat[z] || 0) + 1; samples++; if (b.actor.pos.y > 2) elev[z] = (elev[z] || 0) + 1; }
    if (i === 60) g.ambient.blockDrop(g.nav, 8);
  }
  const kills = g.actors.map((a) => `${a.name}:${a.kills}/${a.deaths}`);
  // render stats
  g.r.render();
  const info = g.r.renderer.info;
  return { navStats, heat, elev, samples, kills, blocks: g.ambient.blocks.length, calls: info.render.calls, tris: info.render.triangles, geos: info.memory.geometries, tex: info.memory.textures, programs: info.programs?.length, time: Math.round(g.match.timeLeft) };
});
console.log(JSON.stringify(r, null, 1));
console.log(logs.slice(0, 20).join('\n'));
await browser.close();

// Per-map sanity: nav, elevators, objective sites reachable, every mode runs. MAP=bedroom|backyard
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const MAP = process.env.MAP || 'backyard';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => { if (m.text().startsWith('[t]')) console.log(m.text()); else if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
page.on('crash', () => { console.log('PAGE CRASHED'); process.exit(2); });
await page.addInitScript((map) => { window.AudioContext = undefined; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify({ quality: 'low', map })); }, MAP);
page.setDefaultTimeout(900000);
await page.goto(process.env.URL || 'http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
const res = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  g.debug.manual = true;
  const breathe = () => new Promise((r) => setTimeout(r, 20));
  const step = async (sec) => { for (let t = 0; t < sec - 1e-9; t += 0.5) { g.debugStep(Math.min(0.5, sec - t)); await breathe(); } };
  const out = { map: g.map.id };
  const ok = (n, c, info) => { out[n] = c ? 'PASS' : `FAIL ${info !== undefined ? JSON.stringify(info) : ''}`; console.log('[t] ' + n + ' ' + out[n]); };
  const nav = g.nav;
  out.nodes = nav.nodes.length;
  const links = nav.nodes.reduce((s, n) => s + n.links.filter((l) => l.elevator !== undefined).length, 0);
  ok('elevators linked', links === g.map.elevators.sites.length * 2, links);
  ok('enough normal spawns', g.spawnPoints.length >= 16, g.spawnPoints.length);
  ok('enough high spawns', g.shelfSpawns.length >= 7, g.shelfSpawns.length);
  // every objective site sits on walkable ground that the bots can path to
  const from = nav.nearest(g.spawnPoints[0], false, 6);
  const bad = [];
  for (const s of g.map.hillSites) {
    const n = nav.nearest(s.pos, false, 3.5);
    if (n < 0 || Math.abs(nav.nodes[n].pos.y - s.pos.y) > 1.2 || !nav.path(from, n)) bad.push(s.name);
  }
  ok('all 7 objective sites reachable', bad.length === 0, bad);
  const hi = nav.nearest(g.shelfSpawns[0], false, 4);
  ok('high ground reachable on foot', !!nav.path(from, hi));
  for (const mode of ['ffa', 'tdm', 'takeover', 'conquest']) {
    g.startMatch('normal', mode);
    g.debug.invulnerable = true;
    const r = { actors: g.actors.length };
    if (mode === 'ffa') r.high = g.actors.filter((a) => a.pos.y > g.map.highY - 0.5).length;
    await step(mode === 'conquest' ? 45 : 14);
    r.kills = g.actors.reduce((s, a) => s + a.kills, 0);
    r.stuck = g.bots.filter((b) => b.actor.alive && b.actor.pos.y < -2).length;
    r.weapons = [...new Set(g.bots.map((b) => b.actor.weapons[0]?.id))].join(',');
    if (g.match.sectors.length) r.sectors = g.match.sectors.map((s) => `${s.def.letter}${s.owner}`).join(' ');
    out[mode] = r;
    ok(`${mode} runs`, g.match.phase !== 'countdown' && r.stuck === 0, r);
    if (mode === 'ffa') ok('ffa: 7 newcomers start on high ground', r.high === 7, r.high);
  }
  // sandbox bounds: nobody escaped the map
  const B = g.arena.bounds;
  ok('everyone inside the map', g.actors.every((a) => a.pos.x > B.min.x - 1 && a.pos.x < B.max.x + 1 && a.pos.z > B.min.z - 1 && a.pos.z < B.max.z + 1));
  return out;
});
console.log(JSON.stringify(res, null, 1));
console.log(logs.slice(0, 20).join('\n') || 'no console errors');
await browser.close();

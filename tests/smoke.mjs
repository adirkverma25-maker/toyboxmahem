// Quick load + per-mode simulation smoke test; prints errors and a few stats.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 960, height: 540 } });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
await page.addInitScript(() => { try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = 'low'; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} });
page.setDefaultTimeout(600000);
await page.goto('http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
const SECS = Number(process.env.SECS || 30);
const res = await page.evaluate(async (SECS) => {
  window.__autotest = true;
  const g = window.__toybox;
  const out = {};
  const nav = g.nav;
  out.nodes = nav.nodes.length;
  out.shelfNodes = nav.nodes.filter((n) => n.pos.y > 20).length;
  out.elevatorLinks = nav.nodes.reduce((s, n) => s + n.links.filter((l) => l.elevator !== undefined).length, 0);
  out.shelfSpawns = g.shelfSpawns.length;
  out.spawns = g.spawnPoints.length;
  for (const mode of (globalThis.MODES_TO_RUN || ['ffa', 'tdm', 'takeover', 'conquest'])) {
    g.startMatch('normal', mode);
    const r = { actors: g.actors.length, teams: g.actors.map((a) => a.team).join('') };
    if (mode === 'ffa') r.onShelf = g.actors.filter((a) => a.pos.y > 20).length;
    const t0 = performance.now();
    g.debug.invulnerable = true;
    g.debugStep(SECS);
    r.ms = Math.round(performance.now() - t0);
    r.kills = g.actors.reduce((s, a) => s + a.kills, 0);
    r.states = {};
    for (const b of g.bots) r.states[b.state] = (r.states[b.state] || 0) + 1;
    r.onShelfNow = g.actors.filter((a) => a.alive && a.pos.y > 20).length;
    r.cloaked = g.actors.filter((a) => a.cloaked).length;
    r.weapons = [...new Set(g.actors.flatMap((a) => a.weapons.filter(Boolean).map((w) => w.id)))].join(',');
    r.scores = g.match.teamScores.map((x) => Math.floor(x)).join('/');
    if (g.match.sectors.length) r.sectors = g.match.sectors.map((s) => `${s.def.letter}:${s.owner}:${s.progress.toFixed(2)}`).join(' ');
    r.phase = g.match.phase;
    out[mode] = r;
  }
  return out;
}, SECS);
console.log(JSON.stringify(res, null, 1));
console.log(logs.filter((l) => !l.includes('[vite]') && !l.includes('[debug]')).slice(0, 40).join('\n'));
await page.screenshot({ path: '/tmp/claude-0/-home-claude/de948a53-d568-5773-8f30-10b629e537d6/scratchpad/smoke.png' });
await browser.close();

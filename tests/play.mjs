// Automated smoke test: boots the game, starts a match, simulates gameplay, reports state + errors.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const url = process.argv[2] || 'http://localhost:5173/';
const out = process.argv[3] || '/tmp/claude-0/shots';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
const quality = process.env.Q || 'low';
await page.addInitScript((q) => { try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = q; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} }, quality);
page.setDefaultTimeout(120000);
await page.goto(url);
await page.waitForFunction(() => window.__ready === true, null, { timeout: 180000 });
await page.waitForTimeout(800);
await page.screenshot({ path: `${out}/menu.png` });
const r = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  g.startMatch('normal');
  g.debugStep(3.5);
  const snap = () => g.actors.map((a) => ({ n: a.name, k: a.kills, d: a.deaths, hp: Math.round(a.health), alive: a.alive, w: a.weapon?.id, p: a.pos.toArray().map((v) => +v.toFixed(1)), fired: a.shotsFired, hit: a.shotsHit }));
  const s0 = snap();
  const states = {};
  const t0 = performance.now();
  for (let i = 0; i < 60; i++) {
    g.debugStep(1);
    for (const b of g.bots) states[b.state] = (states[b.state] || 0) + 1;
  }
  const ms = performance.now() - t0;
  return { phase: g.match.phase, timeLeft: g.match.timeLeft, s0, s1: snap(), states, simMsPer60s: Math.round(ms), nav: g.nav.nodes.length, spawns: g.spawnPoints.length };
});
console.log(JSON.stringify(r, null, 1));
await page.waitForTimeout(500);
await page.screenshot({ path: `${out}/ingame.png` });
console.log(logs.slice(0, 40).join('\n'));
await browser.close();

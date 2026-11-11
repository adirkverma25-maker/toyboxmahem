// Starts a match and takes screenshots of scripted situations.
// usage: Q=medium node tests/scene.mjs '<json [[name, js], ...]>'
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const shots = JSON.parse(process.argv[2]);
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const W = +(process.env.W || 1280), H = +(process.env.H || 720);
const page = await browser.newPage({ viewport: { width: W, height: H } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
const quality = process.env.Q || 'medium';
await page.addInitScript((q) => { window.AudioContext = undefined; try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = q[0]; if (q[1]) s.map = q[1]; if (q[2]) Object.assign(s, JSON.parse(q[2])); localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} }, [quality, process.env.MAP || '', process.env.SET || '']);
page.setDefaultTimeout(600000);
await page.goto(process.env.URL || 'http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 240000 });
if (!process.env.NOSTART) await page.evaluate((mode) => {
  window.__autotest = true;
  const g = window.__toybox;
  g.startMatch('normal', mode);
  g.debug.invulnerable = true;
  g.debugStep(3.5);
  // helper: place the player
  window.place = (x, y, z, yaw, pitch = 0) => { const a = g.player.actor; a.teleport(a.pos.clone().set(x, y, z)); a.yaw = yaw; a.pitch = pitch; g.debugStep(0.25); };
  // helper: freeze bots in a lineup in front of the player
  window.lineup = (ids, dist = 4) => { const a = g.player.actor; const f = a.forward(); f.y = 0; f.normalize(); const side = f.clone().set(-f.z, 0, f.x); g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); b.intent.jump = b.intent.dash = b.intent.sprint = b.intent.crouch = false; }); g.bots.forEach((b, i) => { if (!ids.includes(i)) { b.actor.teleport(b.actor.pos.clone().set(-30 + i * 2, 0, 34)); return; } const k = ids.indexOf(i) - (ids.length - 1) / 2; const p = a.pos.clone().addScaledVector(f, dist).addScaledVector(side, k * 1.6); b.actor.alive = true; b.actor.health = 100; b.actor.collider.setEnabled(true); b.actor.teleport(p); b.actor.yaw = a.yaw + Math.PI; b.actor.spawnProtectUntil = 0; b.update = () => {}; b.fire = () => 0; }); g.debugStep(0.4); };
}, process.env.MODE || 'ffa');
for (const [name, js] of shots) {
  const r = await page.evaluate(js);
  if (r !== undefined) console.log(name, JSON.stringify(r));
  await page.waitForTimeout(+(process.env.WAIT || 1500));
  await page.screenshot({ path: `/tmp/claude-0/shots/${name}.png` });
}
console.log(logs.slice(0, 30).join('\n'));
await browser.close();

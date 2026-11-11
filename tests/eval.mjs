// usage: node tests/eval.mjs '<js expression>'  (runs after boot, low quality)
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}`));
await page.addInitScript(() => { try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = 'low'; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} });
page.setDefaultTimeout(400000);
await page.goto('http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
const r = await page.evaluate(process.argv[2]);
console.log(JSON.stringify(r, null, 1));
if (process.env.LOGS) console.log(logs.slice(-30).join('\n'));
await browser.close();

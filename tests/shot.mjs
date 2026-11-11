// usage: node tests/shot.mjs <url> <out.png> [jsBefore]
import { chromium } from 'playwright';
const [,, url, out, js] = process.argv;
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell', args: ['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs = [];
page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`));
page.on('pageerror', e => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
await page.goto(url);
await page.waitForFunction(() => window.__ready === true, null, { timeout: 120000 }).catch(e => logs.push('TIMEOUT waiting ready'));
if (js) { const r = await page.evaluate(js); if (r !== undefined) console.log('eval:', JSON.stringify(r)); }
await page.waitForTimeout(1500);
await page.screenshot({ path: out });
console.log(logs.join('\n'));
await browser.close();

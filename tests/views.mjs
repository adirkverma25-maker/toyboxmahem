import { chromium } from 'playwright';
const P='/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
const logs=[]; page.on('console', m => logs.push(`[${m.type()}] ${m.text()}`)); page.on('pageerror', e => logs.push(`[pageerror] ${e.message}`));
await page.goto(process.argv[2] || 'http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 120000 });
const views = JSON.parse(process.argv[3]);
for (const [name, pos, look, js] of views) {
  await page.evaluate(([pos,look,js]) => { const d=window.__dbg; d.r.camera.position.set(...pos); d.r.camera.lookAt(...look); if (js) eval(js); }, [pos,look,js]);
  await page.waitForTimeout(1200);
  await page.screenshot({ path: `/tmp/claude-0/shots/${name}.png` });
}
console.log(logs.join('\n'));
await browser.close();

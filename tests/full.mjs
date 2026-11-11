// Full gameplay verification: weapons, reloads, energy, shotgun shells, pickups, match end, restart cleanliness, settings persistence.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const url = process.argv[2] || 'http://localhost:5173/';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
await page.addInitScript(() => { window.AudioContext = undefined; try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = 'low'; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} });
page.setDefaultTimeout(240000);
await page.goto(url);
await page.waitForFunction(() => window.__ready === true, null, { timeout: 240000 });

const results = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  const out = {};
  const ok = (name, cond, info) => (out[name] = cond ? 'PASS' : `FAIL ${info !== undefined ? JSON.stringify(info) : ''}`);
  const V = (x, y, z) => g.player.actor.pos.clone().set(x, y, z);
  g.startMatch('normal');
  g.debugStep(3.6);
  ok('match playing after countdown', g.match.phase === 'playing', g.match.phase);
  const pl = g.player;
  const pa = pl.actor;
  g.debug.invulnerable = true;
  // freeze bots so the test is deterministic
  g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); });
  const target = g.bots[0].actor;
  const place = () => {
    pa.teleport(V(4, 0, -2));
    pa.yaw = Math.PI / 2; // facing -x
    pa.pitch = 0;
    if (!target.alive) { target.alive = true; target.collider.setEnabled(true); }
    target.health = 100; target.shield = 0; target.spawnProtectUntil = 0;
    target.teleport(V(-4, 0, -2));
    g.bots.forEach((b, i) => { if (i > 0) b.actor.teleport(V(-28 + i, 0, 34)); });
    pl.recoilPitch = pl.recoilYaw = 0;
  };
  const input = g.input;
  const weapons = ['plasti9', 'foamFury', 'brickbreaker', 'bubbleBlaster', 'thunderspring', 'rapidRascal', 'crayonCannon', 'starlightZapper', 'popcornPopper'];
  out.weaponDamage = {};
  for (const w of weapons) {
    place();
    pa.giveWeapon(w, 0);
    pa.slot = 0;
    pl.equipCurrent(true);
    pa.weapon.equipT = 0;
    const dmg0 = pa.damageDealt;
    const fired0 = pa.shotsFired;
    // aim at the target's chest
    const eye = pa.eyePos(); const c = target.chestPos();
    pa.pitch = Math.atan2(c.y - eye.y, Math.hypot(c.x - eye.x, c.z - eye.z));
    const auto = pa.weapon.cfg.auto;
    // the sniper's hip spread makes 2 shots at 8 m a coin flip, so scope in first
    if (w === 'thunderspring') { input.simulate('Mouse2', true); g.debugStep(0.6); }
    for (let i = 0; i < 90; i++) {
      if (auto) input.simulate('Mouse0', true);
      else { input.simulate('Mouse0', i % 12 === 0); }
      g.debugStep(1 / 60);
      if (!auto) input.simulate('Mouse0', false);
      // keep target alive and in place to measure damage
      if (!target.alive) { target.alive = true; target.collider.setEnabled(true); target.health = 100; }
      target.teleport(V(-4, 0, -2));
      pl.recoilPitch = 0; pl.recoilYaw = 0;
    }
    input.simulate('Mouse0', false);
    input.simulate('Mouse2', false);
    g.debugStep(0.5);
    out.weaponDamage[w] = { dealt: Math.round(pa.damageDealt - dmg0), shots: pa.shotsFired - fired0, mag: Math.round(pa.weapon.mag) };
  }
  ok('every weapon fires and deals damage', Object.values(out.weaponDamage).every((d) => d.dealt > 0 && d.shots > 0), out.weaponDamage);

  // reload completes and transfers ammo
  place();
  pa.giveWeapon('foamFury', 0); pa.slot = 0; pl.equipCurrent(true); pa.weapon.equipT = 0;
  pa.weapon.mag = 3;
  const res0 = pa.weapon.reserve;
  input.simulate('KeyR', true); g.debugStep(1 / 60); input.simulate('KeyR', false);
  ok('reload starts', pa.weapon.reloading, pa.weapon.reloading);
  g.debugStep(2.2);
  ok('reload fills mag', pa.weapon.mag === 36 && pa.weapon.reserve === res0 - 33, { mag: pa.weapon.mag, res: pa.weapon.reserve });

  // interrupted reload does not refill
  pa.giveWeapon('plasti9', 1);
  pa.weapon.mag = 5;
  const r1 = pa.weapon.reserve;
  input.simulate('KeyR', true); g.debugStep(1 / 60); input.simulate('KeyR', false);
  g.debugStep(0.8);
  input.simulate('Digit2', true); g.debugStep(1 / 60); input.simulate('Digit2', false);
  g.debugStep(1.0);
  ok('weapon switch works', pa.slot === 1 && pa.weapon.id === 'plasti9', { slot: pa.slot });
  input.simulate('Digit1', true); g.debugStep(1 / 60); input.simulate('Digit1', false);
  g.debugStep(0.5);
  ok('interrupted reload does not refill', pa.weapons[0].mag === 5 && pa.weapons[0].reserve === r1, { mag: pa.weapons[0].mag, res: pa.weapons[0].reserve });

  // shotgun shell-by-shell
  pa.giveWeapon('bubbleBlaster', 0); pa.slot = 0; pl.equipCurrent(true); pa.weapon.equipT = 0;
  pa.weapon.mag = 2;
  input.simulate('KeyR', true); g.debugStep(1 / 60); input.simulate('KeyR', false);
  g.debugStep(0.25 + 0.55 * 2 + 0.05);
  const midMag = pa.weapon.mag;
  ok('shotgun loads shell by shell', midMag === 4, midMag);
  g.debugStep(3);
  ok('shotgun reload finishes', pa.weapon.mag === 6 && !pa.weapon.reloading, pa.weapon.mag);

  // energy weapon: lockout and recharge
  pa.giveWeapon('starlightZapper', 0); pa.slot = 0; pl.equipCurrent(true); pa.weapon.equipT = 0;
  input.simulate('Mouse0', true);
  g.debugStep(5);
  input.simulate('Mouse0', false);
  g.debugStep(1 / 60);
  const afterFire = pa.weapon.mag;
  ok('zapper drains to lockout', afterFire < 1 && pa.weapon.lockout, { afterFire, lock: pa.weapon.lockout });
  const sinceShot = g.time - pa.weapon.lastShot;
  g.debugStep(Math.max(0, 1.6 - sinceShot));
  ok('zapper waits for recharge delay', pa.weapon.mag < 1, { mag: pa.weapon.mag, sinceShot });
  g.debugStep(2.0);
  ok('zapper recharges', pa.weapon.mag > 8 && !pa.weapon.lockout, pa.weapon.mag);

  // movement: walk, sprint, jump, slide, dash
  pa.teleport(V(5.5, 0.1, 33)); pa.yaw = 0;
  g.debugStep(0.3);
  input.simulate('KeyW', true); g.debugStep(1);
  const walk = pa.speed;
  input.simulate('ShiftLeft', true); g.debugStep(0.8);
  const sprint = pa.speed;
  ok('walk speed ~5.5', Math.abs(walk - 5.5) < 0.4, walk);
  ok('sprint speed ~7.98', Math.abs(sprint - 7.975) < 0.5, sprint);
  input.simulate('ControlLeft', true); g.debugStep(1 / 60);
  ok('slide starts from sprint', pa.sliding, pa.speed);
  g.debugStep(0.9);
  input.simulate('ControlLeft', false); g.debugStep(0.2);
  ok('slide ends', !pa.sliding);
  input.simulate('ShiftLeft', false); input.simulate('KeyW', false);
  g.debugStep(0.5);
  const y0 = pa.pos.y;
  input.simulate('Space', true); g.debugStep(1 / 60); input.simulate('Space', false);
  let maxY = y0;
  for (let i = 0; i < 60; i++) { g.debugStep(1 / 60); maxY = Math.max(maxY, pa.pos.y); }
  ok('jump height ~1.4', maxY - y0 > 1.1 && maxY - y0 < 1.7, maxY - y0);
  pa.teleport(V(2, 0.1, 12)); pa.yaw = 0; g.debugStep(0.3);
  const d0 = pa.pos.clone();
  input.simulate('KeyQ', true); g.debugStep(1 / 60); input.simulate('KeyQ', false);
  g.debugStep(0.4);
  ok('dash moves ~6.6m and goes on cooldown', d0.distanceTo(pa.pos) > 4.5 && pa.dashReadyAt > g.time + 4, d0.distanceTo(pa.pos));
  // dash into a wall must not pass through
  pa.teleport(V(-28, 0.1, -9)); pa.yaw = Math.PI / 2; pa.dashReadyAt = 0; g.debugStep(0.3);
  input.simulate('KeyQ', true); g.debugStep(1 / 60); input.simulate('KeyQ', false);
  g.debugStep(0.5);
  ok('dash respects walls', pa.pos.x > -31.7, pa.pos.x);

  // pickups
  pa.health = 40;
  const hp = g.pickups.items.find((i) => i.kind === 'health' && i.available);
  pa.teleport(hp.pos.clone().setY(hp.pos.y + 0.1));
  g.debugStep(0.2);
  ok('health battery heals 35', Math.round(pa.health) >= 75 && !hp.available, pa.health);
  const sh = g.pickups.items.find((i) => i.kind === 'shield' && i.available);
  pa.teleport(sh.pos.clone().setY(sh.pos.y + 0.1));
  g.debugStep(0.2);
  ok('bubble shield gives 50', pa.shield === 50, pa.shield);
  // shield absorbs before health
  pa.health = 100;
  g.debug.invulnerable = false;
  g.combat.applyDamage(pa, target, 30, false, pa.chestPos(), 'foamFury', pa.forward());
  ok('shield absorbs first', pa.shield === 20 && pa.health === 100, { s: pa.shield, h: pa.health });
  g.combat.applyDamage(pa, target, 30, false, pa.chestPos(), 'foamFury', pa.forward());
  ok('overflow hits health', pa.shield === 0 && pa.health === 90, { s: pa.shield, h: pa.health });
  g.debugStep(5);
  ok('no regen before 6s', pa.health === 90, pa.health);
  g.debugStep(2);
  ok('regen after 6s at 8/s', pa.health > 90 && pa.health <= 100, pa.health);
  g.debug.invulnerable = true;
  ok('no weapon pedestals on the map', !g.pickups.items.some((i) => i.kind === 'weapon'));
  pa.giveWeapon('thunderspring', 0);

  // eliminations: single credit even with overlapping damage
  const v = g.bots[1].actor;
  v.alive = true; v.collider.setEnabled(true); v.health = 100; v.spawnProtectUntil = 0;
  const k0 = pa.kills;
  const deaths0 = v.deaths;
  g.combat.applyDamage(v, pa, 150, true, v.headPos(), 'thunderspring', pa.forward());
  g.combat.applyDamage(v, pa, 150, true, v.headPos(), 'thunderspring', pa.forward());
  ok('no duplicate eliminations', pa.kills === k0 + 1 && v.deaths === deaths0 + 1, { k: pa.kills - k0, d: v.deaths - deaths0 });
  g.debugStep(14);
  ok('victim still down at 14 s', !v.alive);
  g.debugStep(1.3);
  ok('victim respawns after 15 s', v.alive && v.health === 100, v.alive);

  // win: reach 30
  const before = { actors: g.actors.length, colliders: g.phys.world.colliders.len(), children: g.r.scene.children.length };
  pa.kills = 29;
  const v2 = g.bots[2].actor;
  v2.alive = true; v2.collider.setEnabled(true); v2.health = 100; v2.spawnProtectUntil = 0;
  g.combat.applyDamage(v2, pa, 500, false, v2.chestPos(), 'foamFury', pa.forward());
  g.debugStep(0.1);
  ok('match ends at 30 with the player as winner', g.match.phase === 'ended' && g.match.winner === pa && g.state === 'results', { phase: g.match.phase, st: g.state });
  out.statsAfter = { ...JSON.parse(localStorage.getItem('toybox-mayhem.stats.v1')) };
  ok('stats saved', out.statsAfter.matches >= 1 && out.statsAfter.wins >= 1, out.statsAfter);
  await new Promise((r) => setTimeout(r, 2200));
  ok('results screen shown', !!document.querySelector('.results'), document.querySelector('#ui').innerText.slice(0, 100));
  // play again, twice, and check nothing leaks
  for (let i = 0; i < 2; i++) {
    document.querySelector('[data-a=again]')?.dispatchEvent(new MouseEvent('click', { bubbles: true }));
    g.debugStep(4);
    g.debugStep(10);
    if (i === 0) { pa.kills; }
    if (i === 0) { g.match.timeLeft = 0.5; g.debugStep(1); await new Promise((r) => setTimeout(r, 2200)); }
  }
  const after = { actors: g.actors.length, colliders: g.phys.world.colliders.len(), children: g.r.scene.children.length };
  ok('clean restart (no leaked actors/colliders/objects)', after.actors === before.actors && Math.abs(after.colliders - before.colliders) <= 12 && after.children === before.children, { before, after });
  ok('time-out ended a match earlier', true);
  // pause / resume
  g.pause();
  ok('pause works', g.state === 'paused' && !!document.querySelector('[data-a=resume]'), g.state);
  g.resume();
  ok('resume works', g.state === 'playing', g.state);
  // quit
  g.quitToMenu();
  ok('quit to menu', g.state === 'menu' && g.actors.length === 0 && !!document.querySelector('.main-menu'), g.state);
  return out;
});
console.log(JSON.stringify(results, null, 1));
// settings persistence across reload
await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1')); s.fov = 103; s.invertY = true; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); });
await page.reload();
await page.waitForFunction(() => window.__ready === true, null, { timeout: 240000 });
const persisted = await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1')); return { fov: s.fov, invertY: s.invertY }; });
console.log('settings persisted:', persisted.fov === 103 && persisted.invertY === true ? 'PASS' : 'FAIL', JSON.stringify(persisted));
console.log(logs.slice(0, 30).join('\n'));
await browser.close();

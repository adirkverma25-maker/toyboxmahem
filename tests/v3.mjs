// Checks for the loadout / scopes / revive / spectate / burst gun / buffs update.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => { if (m.text().startsWith('[t]')) console.log(m.text()); else if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
page.on('crash', () => { console.log('PAGE CRASHED'); process.exit(2); });
await page.addInitScript(() => { window.AudioContext = undefined; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify({ quality: 'low', map: 'bedroom', primary: 'popcornPopper', secondary: 'plungerBow', scopes: JSON.stringify({ popcornPopper: 'x4', plungerBow: 'hawk' }) })); });
page.setDefaultTimeout(900000);
await page.goto('http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });
const res = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  g.debug.manual = true;
  const breathe = () => new Promise((r) => setTimeout(r, 20));
  const step = async (sec) => { for (let t = 0; t < sec - 1e-9; t += 0.5) { g.debugStep(Math.min(0.5, sec - t)); await breathe(); } };
  const out = {};
  const ok = (n, c, info) => { out[n] = c ? 'PASS' : `FAIL ${info !== undefined ? JSON.stringify(info) : ''}`; console.log('[t] ' + n + ' ' + out[n]); };
  const V = (x, y, z) => g.player.actor.pos.clone().set(x, y, z);
  const reset = (a) => { a.health = 100; a.shield = 0; a.spawnProtectUntil = 0; a.vel.set(0, 0, 0); };
  const freeze = (list = g.bots) => list.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); });
  const face = (a, p) => { const e = a.eyePos(); const d = p.clone().sub(e); a.yaw = Math.atan2(-d.x, -d.z); a.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z)); };
  const kill = (v, by) => { reset(v); g.combat.applyDamage(v, by, 999, false, v.chestPos(), 'foamFury', by.forward()); };

  // ---------- loadout + no ground weapons
  g.startMatch('normal', 'ffa');
  const pa = g.player.actor;
  ok('loadout: spawn with the weapons picked in the menu', pa.weapons[0].id === 'popcornPopper' && pa.weapons[1].id === 'plungerBow', pa.weapons.map((w) => w.id));
  ok('loadout: chosen scopes are fitted (4x on the Popper)', pa.weapons[0].scope.id === 'x4' && pa.weapons[0].zoom === 4 && pa.weapons[0].overlay, pa.weapons[0].scope);
  ok('bow scope only zooms the crosshair', pa.weapons[1].scope.style === 'zoom' && pa.weapons[1].zoom === 4 && !pa.weapons[1].overlay, pa.weapons[1].scope);
  ok('no weapons on the ground', g.pickups.items.every((i) => i.kind !== 'weapon'), g.pickups.items.filter((i) => i.kind === 'weapon').length);
  await step(3.5);
  freeze();
  g.debug.invulnerable = true;
  const foe = g.bots[0].actor;
  const lane = (dist) => {
    for (let x = -12; x <= 18; x += 2) for (let z = -8; z <= 24; z += 2) {
      const ga = g.phys.rayDist(V(x, 3, z), V(0, -1, 0), 4, true), gb = g.phys.rayDist(V(x, 3, z - dist), V(0, -1, 0), 4, true);
      if (Math.abs(ga - 3) > 0.15 || Math.abs(gb - 3) > 0.15) continue;
      let clear = true;
      for (const h of [0.4, 1.0, 1.6]) if (!g.phys.los(V(x, h, z), V(x, h, z - dist), false)) clear = false;
      if (clear) return [V(x, 0.05, z), V(x, 0.05, z - dist)];
    }
    return [V(2, 0.05, 6), V(2, 0.05, 6 - dist)];
  };
  const place = async (dist) => {
    const [la, lb] = lane(dist);
    for (const b of g.bots) if (b.actor !== foe) b.actor.teleport(V(-25, 0.1, 30));
    pa.teleport(la); reset(pa); foe.teleport(lb); reset(foe); foe.crouchT = 0; foe.crouching = false;
    await step(0.1); reset(foe);
  };
  // ---------- scope picture in the HUD
  await place(12); face(pa, foe.chestPos());
  pa.slot = 0; g.player.equipCurrent(true); pa.weapon.equipT = 0;
  g.input.simulate('Mouse2', true); await step(0.8);
  const hud = document.getElementById('hud');
  ok('scoped: 4x scope picture is up and the fov is narrow', hud.querySelector('.scope').style.opacity === '1' && g.r.camera.fov < 20, { op: hud.querySelector('.scope').style.opacity, fov: g.r.camera.fov });
  g.input.simulate('Mouse2', false); await step(0.5);
  pa.slot = 1; g.player.equipCurrent(true); pa.weapon.equipT = 0;
  g.input.simulate('Mouse2', true); await step(0.8);
  ok('bow aimed: zoomed in, no scope picture, crosshair still there', hud.querySelector('.scope').style.opacity === '0' && hud.querySelector('.crosshair, .xh')?.style.display !== 'none' && g.r.camera.fov < 20, { fov: g.r.camera.fov });
  g.input.simulate('Mouse2', false); await step(0.5);

  // ---------- burst gun
  pa.slot = 0; g.player.equipCurrent(true); const pop = pa.weapon; pop.equipT = 0; pop.nextFire = 0;
  await place(10); face(pa, foe.chestPos());
  const m0 = pop.mag;
  g.input.simulate('Mouse2', true); await step(0.6); face(pa, foe.chestPos()); // aimed, so hip spread can't throw a shot wide
  g.input.simulate('Mouse0', true); g.debugStep(1 / 60); g.input.simulate('Mouse0', false);
  await step(0.5); g.input.simulate('Mouse2', false);
  ok('burst gun: one click fires exactly 3', m0 - pop.mag === 3, m0 - pop.mag);
  ok('burst gun: all 3 hit (63 body, up to 73.5 if recoil walks the last one onto the head)', 100 - foe.health >= 62.9 && 100 - foe.health <= 74, foe.health);
  // ---------- bow
  pa.slot = 1; g.player.equipCurrent(true); const bow = pa.weapon; bow.equipT = 0;
  const shoot = async (hold, head, dist) => {
    await place(dist);
    const tgt = head ? foe.headPos() : foe.chestPos();
    face(pa, tgt);
    bow.nextFire = 0; bow.mag = 12;
    bow.pullTrigger(g.time, true, true, false);
    bow.pullTrigger(g.time + hold, false, false, false);
    const before = foe.health, t0 = g.time;
    const eye = pa.eyePos();
    g.combat.fire(pa, bow, eye, tgt.clone().sub(eye).normalize(), eye, 0);
    let t = 0;
    while (foe.health === before && foe.alive && t < 1.5) { g.debugStep(1 / 60); t += 1 / 60; }
    return { dmg: before - foe.health, time: +(g.time - t0).toFixed(3), alive: foe.alive };
  };
  const tap = await shoot(0.05, false, 14);
  ok('bow: tap still does ~nothing', tap.dmg < 1.5, tap);
  const body = await shoot(1.2, false, 22);
  ok('bow: full draw body = 80', Math.abs(body.dmg - 80) < 1, body);
  ok('bow: arrow crosses 22 m in under 0.12 s (was ~0.2 s)', body.time < 0.12, body);
  await step(11);
  const head = await shoot(1.2, true, 22);
  ok('bow: full draw headshot pops a full-health toy', !head.alive || head.dmg >= 100, head);
  // ---------- crayon cannon speed / reach
  await step(16);
  {
    pa.giveWeapon('crayonCannon', 0); pa.slot = 0; g.player.equipCurrent(true);
    await place(22);
    const eye = pa.eyePos();
    const dir = foe.chestPos().sub(eye).normalize();
    const before = foe.health, t0 = g.time;
    g.combat.fire(pa, pa.weapon, eye, dir, eye, 0);
    let t = 0;
    while (foe.health === before && t < 2) { g.debugStep(1 / 60); t += 1 / 60; }
    ok('crayon cannon: aimed straight at a toy 22 m away it hits in under 0.4 s', before - foe.health >= 60 && g.time - t0 < 0.4, { dmg: before - foe.health, t: g.time - t0 });
  }

  // ---------- respawn 15 s (ffa)
  const v = g.bots[1].actor;
  kill(v, pa);
  ok('respawn timer is 5 s', Math.abs(v.respawnAt - g.time - 5) < 0.01, v.respawnAt - g.time);
  ok('ffa: no reviving (nobody is on your team)', !v.isDowned(g.time));
  await breathe();

  // ---------- team mode: revive + spectate
  g.startMatch('normal', 'tdm');
  await step(3.5);
  g.debug.invulnerable = false;
  const me = g.player.actor;
  const mates = g.bots.filter((b) => b.actor.team === 0);
  const foes = g.bots.filter((b) => b.actor.team === 1);
  freeze();
  for (const b of foes) b.actor.teleport(V(-25, 0.1, 30));
  const [la, lb] = lane(6);
  const buddy = mates[0].actor;
  for (const b of mates.slice(1)) b.actor.teleport(V(-25, 0.1, -30 + Math.random()));
  me.teleport(la); reset(me);
  buddy.teleport(lb); reset(buddy);
  await step(0.2);
  const spot = buddy.pos.clone();
  kill(buddy, foes[0].actor);
  ok('downed teammate stays on the floor as a body', buddy.isDowned(g.time) && buddy.model.root.visible !== false);
  await step(1);
  ok('body is shown lying down', buddy.model.root.visible === true && Math.abs(buddy.model.root.rotation.x) > 1);
  // too far away: holding E does nothing
  g.input.simulate('KeyE', true); await step(1);
  ok('revive needs you next to the body', buddy.reviveT === 0, buddy.reviveT);
  me.teleport(spot.clone().add(V(1.2, 0, 0))); await step(1.5);
  ok('revive: progress while holding E', buddy.reviveT > 1.2 && !buddy.alive, buddy.reviveT);
  g.input.simulate('KeyE', false); await step(1);
  ok('revive: letting go loses the progress', buddy.reviveT === 0 && !buddy.alive, buddy.reviveT);
  g.input.simulate('KeyE', true); await step(2.5);
  ok('revive: not yet at 2.5 s', !buddy.alive);
  await step(0.6);
  g.input.simulate('KeyE', false);
  ok('revive: back up after holding 3 s, same spot, 60 health', buddy.alive && buddy.health === 60 && buddy.pos.distanceTo(spot) < 0.6, { alive: buddy.alive, hp: buddy.health, d: buddy.pos.distanceTo(spot) });
  // bots revive: you go down next to a teammate bot
  const medic = mates[0];
  medic.update = Object.getPrototypeOf(medic).update.bind(medic);
  medic.fire = Object.getPrototypeOf(medic).fire.bind(medic);
  reset(buddy); buddy.health = 100;
  buddy.teleport(lb);
  me.teleport(la); reset(me);
  await step(0.3);
  const where = me.pos.clone();
  kill(me, foes[0].actor);
  ok('you are down, not out', me.isDowned(g.time));
  await step(2);
  ok('spectate: camera follows a living teammate', !!g.player.spectating && g.player.spectating.team === 0 && g.r.camera.position.distanceTo(g.player.spectating.pos) < 7, { sp: g.player.spectating?.name });
  const first = g.player.spectating;
  g.input.simulate('Mouse0', true); g.debugStep(1 / 60); g.input.simulate('Mouse0', false); g.debugStep(1 / 60);
  ok('spectate: click switches to the next teammate', g.player.spectating && g.player.spectating !== first, g.player.spectating?.name);
  let t = 0;
  while (!me.alive && t < 11) { await step(0.5); t += 0.5; }
  ok('a bot teammate revives you where you fell', me.alive && me.pos.distanceTo(where) < 1 && me.health === 60, { alive: me.alive, t, state: medic.state, d: me.pos.distanceTo(where) });
  ok('spectating stops when you are back', !g.player.spectating);
  // not revived: normal respawn at 15 s
  freeze();
  kill(me, foes[0].actor);
  await step(14.5);
  ok('still down at 14.5 s', !me.alive);
  await step(1);
  ok('respawns on its own at 15 s with full health', me.alive && me.health === 100);
  return out;
});
console.log(JSON.stringify(res, null, 1));
console.log(logs.slice(0, 20).join('\n') || 'no console errors');
const fails = Object.values(res).filter((v) => typeof v === 'string' && v.startsWith('FAIL'));
console.log(fails.length ? `${fails.length} FAILED` : 'ALL PASS');
await browser.close();

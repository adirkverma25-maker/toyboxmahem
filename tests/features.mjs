// Verifies everything added in the Conquest / abilities / shelves update.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--enable-precise-memory-info'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => { if (m.text().startsWith('[t]')) console.log(m.text()); if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
page.on('crash', () => { console.log('[t] PAGE CRASHED'); process.exit(2); });
await page.addInitScript((sec) => { window.__section = sec; window.AudioContext = undefined; window.webkitAudioContext = undefined; try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = 'low'; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} }, process.env.SEC || "all");
page.setDefaultTimeout(900000);
await page.goto('http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });

const res = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  const THREE = g.r.scene.constructor === undefined ? null : null;
  const V = (x, y, z) => g.player.actor.pos.clone().set(x, y, z);
  const out = {};
  const ok = (n, c, info) => { out[n] = c ? 'PASS' : `FAIL ${info !== undefined ? JSON.stringify(info) : ''}`; console.log('[t] ' + n + ' ' + out[n] + ' heap=' + Math.round(performance.memory.usedJSHeapSize / 1e6) + 'MB t=' + Math.round(g.time)); };
  const breathe = () => new Promise((r) => setTimeout(r, 20));
  g.debug.manual = true;
  const step = async (sec) => { for (let t = 0; t < sec - 1e-9; t += 0.5) { g.debugStep(Math.min(0.5, sec - t)); await breathe(); } };
  const freeze = () => g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); });
  const reset = (a) => { a.health = 100; a.shield = 0; a.spawnProtectUntil = 0; a.vel.set(0, 0, 0); };
  const face = (a, p) => { const e = a.eyePos(); const d = p.clone().sub(e); a.yaw = Math.atan2(-d.x, -d.z); a.pitch = Math.atan2(d.y, Math.hypot(d.x, d.z)); };

  const SEC = window.__section || 'all';
  if (SEC !== 'b') {
  // ================= FFA roster + shelves
  g.startMatch('normal', 'ffa');
  ok('ffa: 15 toys (you + 14)', g.actors.length === 15, g.actors.length);
  const shelfStart = g.actors.filter((a) => a.pos.y > 20).map((a) => a.name);
  ok('ffa: the 7 newcomers start on the shelves', shelfStart.length === 7, shelfStart);
  const names = new Set(g.actors.map((a) => a.name));
  ok('ffa: all toys distinct', names.size === 15, [...names]);
  await step(3.5);
  freeze();
  const pa = g.player.actor;
  // respawn timer 10 s
  const victim = g.bots[0].actor;
  reset(victim);
  g.combat.applyDamage(victim, pa, 500, false, victim.chestPos(), 'foamFury', pa.forward());
  ok('respawn timer is 5 s', !victim.alive && Math.abs(victim.respawnAt - g.time - 5) < 0.01, victim.respawnAt - g.time);
  await step(14.5);
  ok('still down at 14.5 s', !victim.alive);
  await step(0.7);
  ok('back after 15 s', victim.alive);
  // shelf newcomer respawns on the shelf
  const nb = g.bots.find((b) => b.actor.name === 'Sparky').actor;
  reset(nb);
  g.combat.applyDamage(nb, pa, 500, false, nb.chestPos(), 'foamFury', pa.forward());
  await step(15.3);
  ok('newcomer respawns on a shelf', nb.alive && nb.pos.y > 20, nb.pos);

  // ================= dash cooldown
  pa.teleport(V(2, 0.1, 1)); reset(pa);
  pa.dashReadyAt = 0;
  g.player.intent; // noop
  g.input.simulate('KeyQ', true); g.debugStep(1 / 60); g.input.simulate('KeyQ', false);
  ok('dash cooldown is 5 s', Math.abs(pa.dashReadyAt - g.time - 5) < 0.05, pa.dashReadyAt - g.time);

  // helper: find an open stretch of floor with a clear line of sight
  const lane = (dist) => {
    for (let x = -12; x <= 18; x += 2) for (let z = -8; z <= 24; z += 2) {
      const a = V(x, 0, z), b = V(x, 0, z - dist);
      const ga = g.phys.rayDist(V(x, 3, z), V(0, -1, 0), 4, true), gb = g.phys.rayDist(V(x, 3, z - dist), V(0, -1, 0), 4, true);
      if (Math.abs(ga - 3) > 0.15 || Math.abs(gb - 3) > 0.15) continue;
      let clear = true;
      for (const h of [0.4, 1.0, 1.6]) if (!g.phys.los(V(x, h, z), V(x, h, z - dist), false)) clear = false;
      if (clear && g.phys.capsuleFits(a, 0.42, 0.5) && g.phys.capsuleFits(b, 0.42, 0.5)) return [a, b];
    }
    return [V(2, 0, 6), V(2, 0, 6 - dist)];
  };
  // helper: put a frozen enemy in front of the player
  const foe = g.bots[1].actor;
  const place = async (dist) => {
    const [la, lb] = lane(dist);
    for (const b of g.bots) if (b.actor !== foe) b.actor.teleport(V(-25, 0.1, 30));
    pa.teleport(la.clone().setY(la.y + 0.05)); reset(pa); pa.weapons.forEach((w) => w && (w.reserve = 99));
    foe.teleport(lb.clone().setY(lb.y + 0.05)); reset(foe); foe.yaw = 0;
    foe.crouching = false; foe.crouchT = 0;
    await step(0.05);
    reset(foe); reset(pa);
  };
  // ================= bow
  pa.giveWeapon('plungerBow', 0); pa.slot = 0; g.player.equipCurrent(true);
  const bow = pa.weapon; bow.equipT = 0;
  const shootBow = async (hold, head) => {
    await place(14);
    const tgt = head ? foe.headPos() : foe.chestPos();
    face(pa, tgt);
    bow.nextFire = 0; bow.mag = 12;
    const t0 = g.time;
    bow.pullTrigger(t0, true, true, false);
    const r = bow.pullTrigger(t0 + hold, false, false, false);
    const before = foe.health;
    const eye = pa.eyePos();
    const dir = tgt.clone().sub(eye).normalize();
    // compensate drop like a player would at long draws
    g.combat.fire(pa, bow, eye, dir, eye, 0);
    await step(0.8);
    return { r, dmg: before - foe.health, c: bow.lastCharge };
  };
  const tap = await shootBow(0.06, false);
  ok('bow: quick tap does ~no damage', tap.r === 1 && tap.dmg < 1.5, tap);
  const fullBody = await shootBow(1.2, false);
  ok('bow: full draw body = 80', fullBody.dmg > 75 && fullBody.dmg <= 80.5, fullBody);
  const half = await shootBow(0.5, false);
  ok('bow: half draw in between', half.dmg > 15 && half.dmg < 30, half);
  const fullHead = await shootBow(1.2, true);
  ok('bow: full draw headshot pops a full-health toy', fullHead.dmg >= 100, fullHead);
  await step(15.5); // let the target respawn
  // ================= jack blaster
  pa.giveWeapon('jackBlaster', 0); pa.slot = 0; g.player.equipCurrent(true);
  await place(12);
  face(pa, foe.chestPos());
  const jb = pa.weapon;
  const hb = foe.health;
  g.combat.fire(pa, jb, pa.eyePos(), foe.chestPos().sub(pa.eyePos()).normalize(), pa.eyePos(), jb.cfg.spread.ads);
  const jd = hb - foe.health;
  ok('jack blaster: tight pellets at 12 m (45..90 dmg)', jd >= 45 && jd <= 90, jd);

  // ================= spring punch
  await place(1.6);
  face(pa, foe.chestPos());
  pa.jabReadyAt = 0;
  g.input.simulate('KeyV', true); g.debugStep(1 / 60); g.input.simulate('KeyV', false);
  ok('punch: 50 damage up close', Math.abs(100 - foe.health - 50) < 0.5, foe.health);
  ok('punch: on cooldown', pa.jabReadyAt > g.time + 2.5);
  await place(6); face(pa, foe.chestPos()); pa.jabReadyAt = 0;
  g.input.simulate('KeyV', true); g.debugStep(1 / 60); g.input.simulate('KeyV', false);
  ok('punch: misses at 6 m', foe.health === 100, foe.health);

  await breathe();
  // ================= cloak
  const watcher = g.bots[2];
  { const [la, lb] = lane(14); pa.teleport(la.clone().setY(0.05)); watcher.actor.teleport(lb.clone().setY(0.05)); }
  reset(pa); pa.cloaked = false; pa.cloakReadyAt = 0;
  reset(watcher.actor); watcher.actor.yaw = Math.PI; // facing +z (toward player)
  watcher.target = null;
  // let the frozen bot think once
  const perceive = () => { watcher.target = null; watcher['perceive'](g.time); return watcher.target; };
  for (const b of g.bots) if (b !== watcher) b.actor.teleport(V(-25, 0.1, 30));
  watcher.actor.yaw = Math.atan2(-(pa.pos.x - watcher.actor.pos.x), -(pa.pos.z - watcher.actor.pos.z));
  ok('cloak: bot sees you normally', perceive() === pa);
  g.input.simulate('KeyZ', true); g.debugStep(1 / 60); g.input.simulate('KeyZ', false);
  ok('cloak: turns on', pa.cloaked);
  ok('cloak: bot can no longer see you', perceive() !== pa);
  await step(4);
  g.input.simulate('KeyZ', true); g.debugStep(1 / 60); g.input.simulate('KeyZ', false);
  const cd1 = pa.cloakReadyAt - g.time;
  ok('cloak: cooldown = time active + 5 s', !pa.cloaked && Math.abs(cd1 - (4 + 5)) < 0.15, cd1);
  pa.cloakReadyAt = 0;
  g.input.simulate('KeyZ', true); g.debugStep(1 / 60); g.input.simulate('KeyZ', false);
  await step(16);
  const cd2 = pa.cloakReadyAt - g.time;
  ok('cloak: maxes out at 15 s, then 20 s cooldown', !pa.cloaked && cd2 > 18 && cd2 <= 20.01, cd2);
  pa.cloakReadyAt = 0;
  g.input.simulate('KeyZ', true); g.debugStep(1 / 60); g.input.simulate('KeyZ', false);
  pa.giveWeapon('foamFury', 0); pa.slot = 0; g.player.equipCurrent(true); pa.weapon.equipT = 0;
  g.input.simulate('Mouse0', true); await step(0.1); g.input.simulate('Mouse0', false); await step(0.05);
  ok('cloak: shooting drops it', !pa.cloaked);

  await breathe();
  // ================= mesh shield
  await place(10);
  face(foe, pa.chestPos());
  foe.shieldReadyAt = 0;
  const deps = { combat: g.combat, phys: g.phys, audio: g.combat['audio'] };
  const mod = await import('/src/entities/abilities.ts');
  mod.tryShield(foe, g.time, deps, foe.yaw);
  await step(0.3);
  ok('shield: deployed', g.combat.barriers.list.length === 1);
  const sb = g.combat.barriers.list[0];
  pa.giveWeapon('brickbreaker', 0); pa.slot = 0;
  g.combat.fire(pa, pa.weapon, pa.eyePos(), foe.chestPos().sub(pa.eyePos()).normalize(), pa.eyePos(), 0);
  ok('shield: stops enemy hitscan', foe.health === 100 && sb.hp < 260, { h: foe.health, hp: sb.hp });
  pa.giveWeapon('foamFury', 0); pa.slot = 0;
  g.combat.fire(pa, pa.weapon, pa.eyePos(), foe.chestPos().sub(pa.eyePos()).normalize(), pa.eyePos(), 0);
  await step(0.3);
  ok('shield: stops enemy darts', foe.health === 100, foe.health);
  // owner shoots out through it
  const hpa = pa.health;
  foe.giveWeapon('brickbreaker', 0); foe.slot = 0;
  g.combat.fire(foe, foe.weapon, foe.eyePos(), pa.chestPos().sub(foe.eyePos()).normalize(), foe.eyePos(), 0);
  ok('shield: owner shoots through it', pa.health < hpa, pa.health);
  for (let i = 0; i < 12; i++) g.combat.fire(pa, (pa.giveWeapon('brickbreaker', 0), pa.weapon), pa.eyePos(), foe.chestPos().sub(pa.eyePos()).normalize(), pa.eyePos(), 0);
  await step(0.5);
  ok('shield: breaks after enough damage', g.combat.barriers.list.length === 0);

  // ================= grapple up to the shelf
  pa.teleport(V(14, 0.05, 15)); reset(pa); pa.grappleReadyAt = 0;
  // look at the front edge of the east shelf
  face(pa, V(27.8, 20.75, 15));
  g.input.simulate('KeyF', true); g.debugStep(1 / 60); g.input.simulate('KeyF', false);
  const hooked = !!pa.grapple;
  await step(3);
  ok('hook: latches and pulls you up onto the shelf', hooked && pa.pos.y > 20.5, { hooked, pos: pa.pos });
  ok('hook: on cooldown afterwards', pa.grappleReadyAt > g.time);

  await breathe();
  console.log('[t] -- elevator section');
  { const L0 = g.elevators.list[0]; console.log('[t] lift state ' + L0.phase + ' ' + L0.t.toFixed(2) + ' ' + L0.y.toFixed(2)); }
  // ================= elevator
  const lifts = g.elevators.list;
  const L = lifts[0];
  // wait until it is parked at the bottom
  let guard = 0;
  while (!(L.phase === 'waitBottom' && L.t > 1.5) && guard++ < 2000) { g.debugStep(1 / 30); if (guard % 30 === 0) { console.log('[t] wait ' + guard + ' ' + L.phase + ' ' + L.t.toFixed(2)); await breathe(); } }
  console.log('[t] lift parked, riding');
  pa.teleport(L.center.clone().setY(L.y + 0.05)); reset(pa);
  await step(L.t + 5.5);
  ok('elevator: carries you up to the shelf', pa.pos.y > 20.5 && Math.hypot(pa.pos.x - L.center.x, pa.pos.z - L.center.z) < 1.3, { pos: pa.pos, phase: L.phase });
  // ride back down
  await step(L.t + 5.5);
  ok('elevator: and back down', pa.pos.y < 1, pa.pos);

  await breathe();
  console.log('[t] -- ramps section');
  // ================= ramps: a bot walks from the floor to the shelf without lifts
  {
    g.startMatch('normal', 'ffa');
    await step(3.5);
    const bot = g.bots.find((b) => b.actor.pos.y < 2);
    for (const b of g.bots) if (b !== bot) { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); b.actor.teleport(V(-20, 0.1, 30)); }
    g.player.actor.teleport(V(-20, 0.1, 31)); g.debug.invulnerable = true;
    const nav = g.nav;
    // remove elevator links temporarily so only ramps count
    const saved = nav.nodes.map((n) => n.links);
    nav.nodes.forEach((n) => (n.links = n.links.filter((l) => l.elevator === undefined)));
    const goal = nav.nodes.find((n) => n.pos.y > 20.5 && n.pos.x > 18 && n.pos.z < -32);
    bot.actor.teleport(V(12.4, 0.1, 2)); reset(bot.actor);
    bot['state'] = 'patrol';
    bot['randomPatrolGoal'] = () => goal.pos;
    bot['think'] = () => {};
    bot['useAbilities'] = () => {};
    bot['hasGoal'] = false;
    let reached = false;
    for (let i = 0; i < 60 && !reached; i++) { await breathe(); await step(1); reached = bot.actor.pos.y > 20.5; }
    nav.nodes.forEach((n, i) => (n.links = saved[i]));
    ok('ramps: a bot walks up to the shelf', reached, bot.actor.pos);
    // elevator ride by a bot
    const goal2 = nav.nodes.find((n) => n.pos.y > 20.5 && Math.abs(n.pos.x - 3.2) < 3 && n.pos.z > 32);
    const b2 = g.bots.find((b) => b !== bot);
    b2.update = Object.getPrototypeOf(b2).update.bind(b2);
    b2.actor.teleport(V(3.2, 0.1, 24)); reset(b2.actor);
    b2['state'] = 'patrol'; b2['think'] = () => {}; b2['useAbilities'] = () => {};
    b2['randomPatrolGoal'] = () => goal2.pos; b2['hasGoal'] = false;
    let reached2 = false, rode = false;
    for (let i = 0; i < 40 && !reached2; i++) {
      await breathe();
      await step(1);
      reached2 = b2.actor.pos.y > 20.5;
      const p = b2.path;
      if (p && p.some((id, k) => k > 0 && nav.linkBetween(p[k - 1], id)?.elevator !== undefined)) rode = true;
    }
    ok('elevator: a bot paths through and rides it up', reached2 && rode, { pos: b2.actor.pos, rode });
  }

  }
  if (SEC !== 'a') {
  await breathe();
  console.log('[t] -- wariness section');
  // ================= bot wariness
  {
    g.startMatch('normal', 'tdm');
    await step(3.5);
    const pa2 = g.player.actor;
    const b = g.bots.find((x) => x.actor.team === 1);
    for (const o of g.bots) if (o !== b) { o.update = () => {}; o.fire = () => 0; o.actor.teleport(V(-20, 0.1, 30)); }
    pa2.teleport(V(2, 0.05, 10)); reset(pa2); g.debug.invulnerable = true;
    b.actor.teleport(V(2, 0.05, -4)); reset(b.actor); b.actor.yaw = Math.PI;
    b.personality = { ...b.personality, caution: 0.2 };
    await step(1);
    const s1 = b.state;
    b.actor.health = 52; b.actor.lastDamageAt = g.time; b.actor.lastAttacker = pa2; b.actor.lastAttackerAt = g.time;
    b.actor.recentDamage.push({ t: g.time, amount: 48 });
    b['stateT'] = -99;
    await step(0.6);
    ok('bots: run when health drops to ~half', ['retreat', 'seekPickup'].includes(b.state), { before: s1, after: b.state });
  }

  await breathe();
  console.log('[t] -- conquest section');
  // ================= conquest
  {
    g.startMatch('normal', 'conquest');
    const m = g.match;
    const cnt = [0, 1, 2].map((t) => g.actors.filter((a) => a.team === t).length);
    ok('conquest: 3 teams of 3', cnt.join() === '3,3,3', cnt);
    ok('conquest: each team starts with 1 sector, 3 neutral', m.sectors.filter((s) => s.owner < 0).length === 3 && [0, 1, 2].every((t) => m.sectorsOwned(t) === 1));
    ok('conquest: Sunrise starts at the Bed, Moonbeam the Closet, Clover the Dinos', m.sectors[0].owner === 0 && m.sectors[2].owner === 1 && m.sectors[4].owner === 2);
    await step(3.5);
    // the player captures a neutral sector alone
    const pa3 = g.player.actor;
    const keep = g.bots.map((b) => b.update);
    g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); b.actor.teleport(V(-5, 0.1, -32)); });
    const desk = m.sectors[1];
    pa3.teleport(desk.pos.clone().setY(desk.pos.y + 0.1)); reset(pa3);
    g.debug.invulnerable = true;
    await step(4);
    ok('conquest: capture in progress', desk.progressTeam === 0 && desk.progress > 0.4 && desk.progress < 0.6, desk.progress);
    await step(4.5);
    ok('conquest: captured after ~8 s', desk.owner === 0 && m.teamScores[0] === 2, { owner: desk.owner, s: m.teamScores });
    // an enemy alone drains it
    const enemy = g.bots.find((b) => b.actor.team === 1).actor;
    pa3.teleport(V(-5, 0.1, -32));
    enemy.teleport(desk.pos.clone().setY(desk.pos.y + 0.1));
    await step(8.3);
    ok('conquest: enemy neutralizes it in ~8 s', desk.owner === -1, desk);
    // contested freezes
    pa3.teleport(desk.pos.clone().setY(desk.pos.y + 0.1));
    const p0 = desk.progress;
    await step(2);
    ok('conquest: contested sector freezes', desk.contested && Math.abs(desk.progress - p0) < 1e-6, desk);
    // win at 4
    m.sectors[1].owner = 0; m.sectors[3].owner = 0; m.sectors[5].owner = 0; m.sectors.forEach((s) => (s.progress = 1));
    enemy.teleport(V(-5, 0.1, -32)); pa3.teleport(V(2, 0.1, 1));
    await step(0.2);
    ok('conquest: 4 of 6 sectors wins', m.phase === 'ended' && m.winnerTeam === 0, { phase: m.phase, w: m.winnerTeam, s: m.teamScores });
    // bots play it on their own
    g.startMatch('normal', 'conquest');
    g.debug.invulnerable = true;
    g.player.actor.teleport(V(-5, 0.1, -32));
    const changes = [];
    let prev = g.match.sectors.map((s) => s.owner).join();
    for (let i = 0; i < 150 && g.match.phase !== 'ended'; i++) {
      await breathe();
      await step(1);
      g.player.actor.teleport(V(-5, 21.1, -34));
      const cur = g.match.sectors.map((s) => s.owner).join();
      if (cur !== prev) changes.push(`${Math.round(g.time)}s ${cur}`);
      prev = cur;
    }
    const assigned = [...g['assignment'].values()];
    ok('conquest: bots capture sectors on their own', changes.length >= 2, changes);
    ok('conquest: bots spread over several sectors', new Set(assigned).size >= 3, assigned);
    out.conquestTimeline = changes.slice(0, 12);
    out.conquestEnd = { phase: g.match.phase, scores: g.match.teamScores, winner: g.match.winnerTeam, t: Math.round(g.time) };
  }
  }
  return out;
});
console.log(JSON.stringify(res, null, 1));
console.log(logs.slice(0, 30).join('\n'));
const fails = Object.entries(res).filter(([, v]) => typeof v === 'string' && v.startsWith('FAIL'));
console.log(fails.length ? `${fails.length} FAILED` : 'ALL PASS');
await browser.close();

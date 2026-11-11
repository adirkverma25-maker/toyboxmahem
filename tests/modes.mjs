// Verifies every game mode: team setup, friendly fire, scoring, objective, end + restart.
import { chromium } from 'playwright';
const P = '/opt/pw-browsers/chromium_headless_shell-1194/chrome-linux/headless_shell';
const browser = await chromium.launch({ executablePath: P, args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--autoplay-policy=no-user-gesture-required'] });
const page = await browser.newPage({ viewport: { width: 640, height: 360 } });
const logs = [];
page.on('console', (m) => { if (m.type() === 'error' || m.type() === 'warning') logs.push(`[${m.type()}] ${m.text()}`); });
page.on('pageerror', (e) => logs.push(`[pageerror] ${e.message}\n${e.stack}`));
await page.addInitScript(() => { window.AudioContext = undefined; try { const s = JSON.parse(localStorage.getItem('toybox-mayhem.settings.v1') || '{}'); s.quality = 'low'; localStorage.setItem('toybox-mayhem.settings.v1', JSON.stringify(s)); } catch {} });
page.setDefaultTimeout(600000);
await page.goto(process.env.URL || 'http://localhost:5173/');
await page.waitForFunction(() => window.__ready === true, null, { timeout: 300000 });

const res = await page.evaluate(async () => {
  window.__autotest = true;
  const g = window.__toybox;
  const out = {};
  const ok = (n, c, info) => (out[n] = c ? 'PASS' : `FAIL ${info !== undefined ? JSON.stringify(info) : ''}`);
  // ---------------- TDM
  g.startMatch('normal', 'tdm');
  g.debugStep(3.6);
  const teams = g.actors.map((a) => a.team);
  ok('tdm: 4v4 teams, player on team 0', teams.filter((t) => t === 0).length === 4 && teams.filter((t) => t === 1).length === 4 && g.player.actor.team === 0, teams);
  // friendly fire is off
  const pa = g.player.actor;
  const mate = g.actors.find((a) => a !== pa && a.team === 0);
  const foe = g.actors.find((a) => a.team === 1);
  mate.spawnProtectUntil = 0; foe.spawnProtectUntil = 0;
  const mh = mate.health;
  g.combat.applyDamage(mate, pa, 50, false, mate.chestPos(), 'foamFury', pa.forward());
  ok('tdm: no friendly fire damage', mate.health === mh, mate.health);
  // hitscan passes through a teammate standing in front of an enemy
  pa.teleport(pa.pos.clone().set(4, 0, -2)); pa.yaw = Math.PI / 2; pa.pitch = 0;
  g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); });
  mate.teleport(pa.pos.clone().set(1.5, 0, -2)); foe.teleport(pa.pos.clone().set(-3, 0, -2));
  foe.health = 100; foe.shield = 0; foe.spawnProtectUntil = 0;
  const eye = pa.eyePos(); const c = foe.chestPos();
  const dir = c.clone().sub(eye).normalize();
  pa.giveWeapon('brickbreaker', 0); pa.slot = 0;
  g.combat.fire(pa, pa.weapon, eye, dir, eye, 0);
  ok('tdm: shots pass through teammates and hit the enemy behind', foe.health < 100 && mate.health === mh, { foe: foe.health, mate: mate.health });
  // a pop scores for the team
  const s0 = g.match.teamScores[0];
  g.combat.applyDamage(foe, pa, 500, false, foe.chestPos(), 'brickbreaker', dir);
  ok('tdm: enemy pop scores for your team', g.match.teamScores[0] === s0 + 1, g.match.teamScores);
  // let the bots play it out for a while
  const fresh = () => { /* new bots are created on restart, so nothing to undo */ };
  g.startMatch('normal', 'tdm');
  g.debug.invulnerable = true;
  for (let i = 0; i < 24; i++) g.debugStep(5);
  const tdmScores = [...g.match.teamScores];
  const sumKills = [0, 1].map((t) => g.actors.filter((a) => a.team === t).reduce((s, a) => s + a.kills, 0));
  ok('tdm: team scores equal team pops after 2 minutes of bots', tdmScores[0] === sumKills[0] && tdmScores[1] === sumKills[1] && tdmScores[0] + tdmScores[1] > 5, { tdmScores, sumKills });
  out.tdmAfter2min = tdmScores;
  // finish: force score to 49 and pop one more
  g.match.teamScores[1] = 49;
  const a1 = g.actors.find((a) => a.team === 1 && a.alive && !a.isPlayer);
  const v0 = g.actors.find((a) => a.team === 0 && a.alive && !a.isPlayer);
  v0.spawnProtectUntil = 0;
  g.combat.applyDamage(v0, a1, 500, false, v0.chestPos(), 'foamFury', a1.forward());
  g.debugStep(0.1);
  ok('tdm: team 1 wins at 50, player counted as loser', g.match.phase === 'ended' && g.match.winnerTeam === 1 && !g.match.isWinner(g.player.actor) && g.state === 'results', { ph: g.match.phase, wt: g.match.winnerTeam });
  await new Promise((r) => setTimeout(r, 2200));
  ok('tdm: results show team headers', document.querySelectorAll('.results .team-head').length === 2 && /Moonbeam wins/.test(document.querySelector('.results .winner').textContent), document.querySelector('.results .winner')?.textContent);

  // ---------------- TAKEOVER
  g.startMatch('normal', 'takeover');
  g.debugStep(3.6);
  ok('takeover: hill exists', !!g.match.hill && g.hillZone.group.visible, !!g.match.hill);
  const site0 = g.match.hill.site.name;
  // put the player in the box alone -> team 0 scores
  g.bots.forEach((b) => { b.update = () => {}; b.fire = () => 0; b.intent.wish.set(0, 0, 0); b.actor.teleport(b.actor.pos.clone().set(-30 + b.actor.id * 0.5, 0, 34)); });
  const h = g.match.hill;
  const pa2 = g.player.actor;
  pa2.teleport(h.pos.clone().setY(h.pos.y + 0.1));
  g.debug.invulnerable = true;
  g.debugStep(5);
  ok('takeover: holding alone scores ~1/s', g.match.teamScores[0] > 4 && g.match.teamScores[0] < 6 && g.match.teamScores[1] === 0 && h.owner === 0, { s: g.match.teamScores, owner: h.owner, inHill: g.match.inHill(pa2) });
  // an enemy inside contests it
  const enemy = g.actors.find((a) => a.team === 1);
  enemy.teleport(h.pos.clone().setY(h.pos.y + 0.1).add(new pa2.pos.constructor(1, 0, 0)));
  const before = g.match.teamScores[0];
  g.debugStep(3);
  ok('takeover: contested stops scoring', h.contested && Math.abs(g.match.teamScores[0] - before) < 0.01, { c: h.contested, s: g.match.teamScores });
  // it moves after 60 s
  g.debugStep(60);
  ok('takeover: toy box moves after 60 s', g.match.hill.site.name !== site0, { from: site0, to: g.match.hill.site.name });
  // check every site is reachable for bots (nav nodes inside each zone)
  const { HILL_SITES } = await import('/src/match/modes.ts');
  const reach = HILL_SITES.map((s) => {
    const ids = g.nav.near(s.pos, s.radius - 0.6).filter((id) => Math.abs(g.nav.nodes[id].pos.y - s.pos.y) < 1.5);
    return `${s.name}:${ids.length}`;
  });
  ok('takeover: every toy box site has walkable nav nodes', reach.every((r) => +r.split(':')[1] > 3), reach);
  // bots actually go for the box
  g.startMatch('normal', 'takeover');
  g.debug.invulnerable = true;
  let insideSamples = 0, samples = 0;
  for (let i = 0; i < 60; i++) {
    g.debugStep(2);
    for (const b of g.bots) { if (!b.actor.alive) continue; samples++; if (g.match.inHill(b.actor)) insideSamples++; }
  }
  out.takeoverScores = g.match.teamScores.map((x) => Math.round(x));
  out.botsInBoxPct = Math.round((insideSamples / samples) * 100);
  ok('takeover: bots contest the box (some time inside, points scored)', insideSamples / samples > 0.1 && g.match.teamScores[0] + g.match.teamScores[1] > 20, { pct: out.botsInBoxPct, scores: out.takeoverScores });
  // play to the end on bots alone
  let t = 0;
  while (g.state === 'playing' && t < 700) { g.debugStep(5); t += 5; }
  ok('takeover: match ends', g.match.phase === 'ended', { t, scores: g.match.teamScores });
  out.takeoverEnd = { t, reason: g.match.endReason, scores: g.match.teamScores.map((x) => Math.floor(x)), winner: g.match.winnerTeam };

  // ---------------- FFA still FFA
  g.startMatch('normal', 'ffa');
  g.debugStep(3.6);
  ok('ffa: no teams, no hill', g.actors.every((a) => a.team === -1) && !g.match.hill && !g.hillZone.group.visible);
  const b1 = g.bots[0].actor, b2 = g.bots[1].actor;
  b2.spawnProtectUntil = 0;
  const hp = b2.health;
  g.combat.applyDamage(b2, b1, 20, false, b2.chestPos(), 'foamFury', b1.forward());
  ok('ffa: everyone can hurt everyone', b2.health === hp - 20, b2.health);
  // restart cleanliness across modes
  const counts = [];
  const seq = ['tdm', 'ffa', 'conquest', 'takeover', 'tdm', 'ffa', 'conquest', 'takeover'];
  for (const m of seq) { g.startMatch('normal', m); g.debugStep(5); counts.push([g.actors.length, g.phys.world.colliders.len(), g.r.scene.children.length]); }
  ok('mode switching leaves nothing behind', counts.slice(0, 4).every((c, i) => c[0] === counts[i + 4][0] && Math.abs(c[1] - counts[i + 4][1]) <= 14 && c[2] === counts[i + 4][2]), counts);
  g.quitToMenu();
  return out;
});
console.log(JSON.stringify(res, null, 1));
console.log(logs.slice(0, 20).join('\n') || 'no console errors');
await browser.close();

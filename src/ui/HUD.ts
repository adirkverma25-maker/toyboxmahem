import * as THREE from 'three';
import type { Player } from '../entities/Player';
import type { Actor } from '../entities/Actor';
import type { Match } from '../match/Match';
import { settings } from '../core/Settings';
import { inputDevice, actionName } from '../core/Input';
import { formatTime, DEG, clamp } from '../core/math';
import { ABILITIES, COMBAT, MOVE, RETICLES, ReticleShape, WEAPONS } from '../weapons/weaponConfig';
import { PICKUP_INFO } from '../match/Pickups';
import { TEAMS } from '../match/modes';

/** All five ability icons exist; only the two the player equipped are shown, in slot order. */
const ABIL_UI: { k: 'dash' | 'jab' | 'grapple' | 'cloak' | 'shield'; name: string }[] = [
  { k: 'dash', name: 'Dash' },
  { k: 'jab', name: 'Punch' },
  { k: 'grapple', name: 'Hook' },
  { k: 'cloak', name: 'Cloak' },
  { k: 'shield', name: 'Shield' },
];

/** Key hint next to a weapon slot: the swap button on a controller, 1 / 2 on the keyboard. */
function slotKey(i: number, cur: number) {
  if (inputDevice.pad) {
    const sw = actionName('swap', true);
    return i === cur || sw === 'unbound' ? '' : `<kbd>${esc(sw)}</kbd>`;
  }
  const k = actionName(i ? 'weapon2' : 'weapon1', true);
  return k === 'unbound' ? '' : `<kbd>${esc(k)}</kbd>`;
}

/** Name color: team color in team modes, the toy's own accent otherwise. */
const nameColor = (a: Actor) => (a.team >= 0 ? TEAMS[a.team].light : a.def.accent);

const h = <K extends keyof HTMLElementTagNameMap>(tag: K, cls?: string, html?: string) => {
  const e = document.createElement(tag);
  if (cls) e.className = cls;
  if (html !== undefined) e.innerHTML = html;
  return e;
};
/** textContent writes replace the text node even when nothing changed, so skip no-op updates */
const setText = (el: HTMLElement, t: string) => {
  if (el.textContent !== t) el.textContent = t;
};
/** The center mark every weapon draws in its scope. Coordinates are in a -100..100 box. */
function reticleMark(shape: ReticleShape, c: string): string {
  const st = `fill="none" stroke="${c}" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"`;
  switch (shape) {
    case 'dot': return `<circle r="3.2" fill="${c}"/>`;
    case 'chevron': return `<path d="M-9 9 L0 0 L9 9" ${st}/><circle r="1.4" fill="${c}"/>`;
    case 'brick': return `<rect x="-9" y="-6" width="18" height="12" rx="1.5" ${st}/><circle r="1.6" fill="${c}"/><path d="M-5 -6 v-3 M5 -6 v-3" ${st}/>`;
    case 'bubbles': return `<circle r="15" ${st} stroke-dasharray="3 5"/><circle cx="-6" cy="4" r="3" ${st}/><circle cx="6" cy="2" r="4" ${st}/><circle cx="0" cy="-7" r="2.4" ${st}/>`;
    case 'cross': return `<circle r="2" fill="${c}"/><path d="M-16 0 h9 M7 0 h9 M0 -16 v9 M0 7 v9" ${st}/>`;
    case 'circleDot': return `<circle r="10" ${st}/><circle r="1.8" fill="${c}"/>`;
    case 'crayon': return `<path d="M0 0 L-5 10 L5 10 Z" ${st}/><path d="M-14 22 h28 M-9 36 h18 M-5 50 h10" ${st}/>`;
    case 'star': return `<path d="M0 -11 L3 -3 L11 -3 L5 2 L7 10 L0 5 L-7 10 L-5 2 L-11 -3 L-3 -3 Z" ${st}/><circle r="1.3" fill="${c}"/>`;
    case 'jack': return `<circle r="13" ${st}/><circle cx="-4.5" cy="-3" r="1.4" fill="${c}"/><circle cx="4.5" cy="-3" r="1.4" fill="${c}"/><path d="M-6 4 Q0 10 6 4" ${st}/><circle r="1.2" cy="1" fill="${c}"/>`;
    case 'boom': return `<circle r="9" ${st}/><path d="M0 -17 v6 M0 11 v6 M-17 0 h6 M11 0 h6" ${st}/><circle r="1.6" fill="${c}"/>`;
    case 'kernels': return `<circle cy="-7" r="2.2" fill="${c}"/><circle cx="-6.5" cy="5" r="2.2" fill="${c}"/><circle cx="6.5" cy="5" r="2.2" fill="${c}"/><circle r="1" fill="${c}"/>`;
  }
}
/** Full scope picture: fine black cross with range ticks, plus the weapon's own mark in the middle. */
function scopeSvg(shape: ReticleShape, c: string, zoom: number): string {
  const ticks: string[] = [];
  const n = zoom >= 6 ? 8 : zoom >= 3.5 ? 5 : 3;
  for (let i = 1; i <= n; i++) {
    const d = 18 + i * (70 / n) * 0.9;
    const l = i % 2 ? 2.5 : 4;
    ticks.push(`<path d="M${d} ${-l} v${l * 2} M${-d} ${-l} v${l * 2} M${-l} ${d} h${l * 2}"/>`);
  }
  return `<svg viewBox="-100 -100 200 200"><g stroke="#0b1020" stroke-width="0.7" fill="none"><path d="M-100 0 H-20 M20 0 H100 M0 -100 V-20 M0 20 V100"/><path d="M-100 0 H-62 M62 0 H100 M0 62 V100" stroke-width="2.4"/>${ticks.join('')}</g>${reticleMark(shape, c)}</svg>`;
}
const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

interface DmgNum {
  el: HTMLDivElement;
  pos: THREE.Vector3;
  life: number;
  drift: number;
}
interface DirInd {
  el: HTMLElement;
  from: THREE.Vector3;
  life: number;
}

const STREAKS: Record<number, string> = { 2: 'Double pop!', 3: 'Triple pop!', 4: 'Toy box tantrum!', 5: 'Unstoppable toy!', 7: 'Playroom legend!', 10: 'Toy of the year!' };

export class HUD {
  root = h('div');
  /** corner panels are scaled with the window; crosshair/markers stay pixel-exact */
  private panels = h('div', 'hud-panels');
  private xh = h('div', 'xh');
  private reloadRing = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  private reloadFg!: SVGCircleElement;
  private hitmark = h('div', 'hitmark', '<i></i><i></i><i></i><i></i>');
  private dmgLayer = h('div');
  private dirLayer = h('div');
  private vignette = h('div', 'vignette');
  private hurtFlash = h('div', 'hurtflash');
  private shieldFlash = h('div', 'shieldflash');
  private scope = h('div', 'scope', '<div class="lens"></div><div class="rim"></div><div class="ret"></div>');
  /** lit reticle for the small on-gun optics (Gumdrop Dot, Hula Ring) */
  private reticle = h('div', 'reticle');
  private scopeKey = '';
  private timer = h('div', 'timer shadow');
  private myScore = h('div', 'score-chip shadow');
  private leadScore = h('div', 'score-chip shadow');
  private thirdScore = h('div', 'score-chip shadow');
  private chargeRing = h('div', 'charge-ring', '<svg viewBox="0 0 80 80"><circle class="bg" cx="40" cy="40" r="34"></circle><circle class="fg" cx="40" cy="40" r="34"></circle></svg><span></span>');
  private cloakFx = h('div', 'cloak-fx');
  private abilEls: { el: HTMLElement; ring: SVGCircleElement; cd: HTMLElement; key: HTMLElement }[] = [];
  private sectorMarkers: HTMLElement[] = [];
  private mini = h('div', 'mini shadow');
  private feed = h('div', 'feed shadow');
  private vitals = h('div', 'vitals');
  private hpBar = h('div', 'bar hp', '<div class="ghost"></div><div class="fill"></div><span></span>');
  private shBar = h('div', 'bar sh', '<div class="ghost"></div><div class="fill"></div><span></span>');
  private buffs = h('div', 'buffs');
  private weapon = h('div', 'weapon-hud shadow');
  private ability = h('div', 'ability shadow');
  private prompt = h('div', 'prompt shadow');
  private reloading = h('div', 'reloading shadow', 'Reloading');
  private center = h('div', 'center-msg');
  private announceEl = h('div', 'announce');
  private countdownEl = h('div', 'countdown');
  private pickups = h('div', 'pickups shadow');
  private death = h('div', 'death', '<div class="box shadow"><h2>Popped!</h2><p class="by"></p><p class="respawn"></p><p class="spec"></p></div>');
  private board = h('div', 'scoreboard card');
  private fps = h('div', 'fps');
  private zone = h('div', 'zone shadow');
  private nums: DmgNum[] = [];
  private dirs: DirInd[] = [];
  private announceT = 0;
  private centerT = 0;
  private hpShown = 100;
  private shShown = 0;
  private lastHp = 100;
  private lastSh = 0;
  private hurtT = 0;
  private shieldT = 0;
  private boardVisible = false;
  private lastMini = '';
  private lastWeaponKey = '';
  private lastBuffKey = '';
  private v = new THREE.Vector3();
  private killerName = '';
  private killerWeapon = '';
  private allyTags: HTMLElement[] = [];
  private objMarker = h('div', 'obj-marker', '<div class="ico">⚙</div><div class="lbl"></div>');
  private objStatus = h('div', 'obj-status shadow');
  private fpsAcc = 0;
  private fpsFrames = 0;

  constructor(parent: HTMLElement) {
    this.root.id = 'hud';
    parent.appendChild(this.root);
    this.xh.innerHTML = '<i class="t"></i><i class="b"></i><i class="l"></i><i class="r"></i><i class="d"></i>';
    const ns = 'http://www.w3.org/2000/svg';
    this.reloadRing.setAttribute('class', 'reload-ring');
    this.reloadRing.setAttribute('viewBox', '0 0 54 54');
    const bg = document.createElementNS(ns, 'circle');
    bg.setAttribute('class', 'bg');
    bg.setAttribute('cx', '27');
    bg.setAttribute('cy', '27');
    bg.setAttribute('r', '22');
    this.reloadFg = document.createElementNS(ns, 'circle');
    this.reloadFg.setAttribute('class', 'fg');
    this.reloadFg.setAttribute('cx', '27');
    this.reloadFg.setAttribute('cy', '27');
    this.reloadFg.setAttribute('r', '22');
    this.reloadFg.setAttribute('stroke-dasharray', `${2 * Math.PI * 22}`);
    this.reloadRing.append(bg, this.reloadFg);
    const top = h('div', 'top-center');
    top.append(this.myScore, this.timer, this.leadScore, this.thirdScore);
    this.thirdScore.style.display = 'none';
    this.vitals.append(this.buffs, this.shBar, this.hpBar);
    // five ability slots along the bottom
    this.ability.className = 'abilities shadow';
    for (const u of ABIL_UI) {
      const el = h('div', 'abil', `<div class="icon"><span class="key"></span><span class="cd"></span></div><small>${u.name}</small>`);
      const svg = document.createElementNS(ns, 'svg');
      svg.setAttribute('viewBox', '0 0 56 56');
      const ring = document.createElementNS(ns, 'circle');
      ring.setAttribute('cx', '28');
      ring.setAttribute('cy', '28');
      ring.setAttribute('r', '25');
      ring.setAttribute('stroke-dasharray', `${2 * Math.PI * 25}`);
      svg.append(ring);
      el.querySelector('.icon')!.append(svg);
      this.ability.append(el);
      this.abilEls.push({ el, ring, cd: el.querySelector('.cd') as HTMLElement, key: el.querySelector('.key') as HTMLElement });
    }
    for (let i = 0; i < 6; i++) {
      const mk = h('div', 'obj-marker sector', '<div class="ico"></div><div class="lbl"></div>');
      mk.style.display = 'none';
      this.sectorMarkers.push(mk);
      this.root.append(mk);
    }
    for (let i = 0; i < 8; i++) {
      const t = h('div', 'ally-tag', '<i></i><span></span>');
      t.style.display = 'none';
      this.allyTags.push(t);
      this.root.append(t);
    }
    this.objMarker.style.display = 'none';
    this.objStatus.style.display = 'none';
    this.root.append(this.objMarker);
    this.root.append(this.cloakFx, this.chargeRing, this.reticle);
    this.root.append(this.scope, this.vignette, this.hurtFlash, this.shieldFlash, this.dirLayer, this.dmgLayer, this.xh, this.reloadRing, this.hitmark, this.reloading, this.panels);
    this.panels.append(this.objStatus);
    this.panels.append(top, this.mini, this.feed, this.vitals, this.weapon, this.ability, this.prompt, this.center, this.announceEl, this.countdownEl, this.pickups, this.zone, this.death, this.board, this.fps);
    const rescale = () => {
      const z = clamp(Math.min(window.innerHeight / 1000, window.innerWidth / 1700), 0.62, 1.45);
      this.panels.style.zoom = String(z);
    };
    rescale();
    window.addEventListener('resize', rescale);
    for (let i = 0; i < 32; i++) {
      const el = h('div', 'dmgnum') as HTMLDivElement;
      el.style.opacity = '0';
      this.dmgLayer.append(el);
      this.nums.push({ el, pos: new THREE.Vector3(), life: 0, drift: 0 });
    }
    for (let i = 0; i < 6; i++) {
      const wrap = h('div', 'dirind', '<i></i>');
      wrap.style.opacity = '0';
      this.dirLayer.append(wrap);
      this.dirs.push({ el: wrap, from: new THREE.Vector3(), life: 0 });
    }
    this.board.classList.add('hidden');
    this.death.classList.add('hidden');
    this.announceEl.classList.add('hidden');
    this.countdownEl.classList.add('hidden');
    this.applySettings();
  }

  /** Called at match start so the top bar matches the mode. */
  setMode(match: Match) {
    this.root.classList.toggle('teams', match.teams);
    this.root.classList.toggle('conquest', match.mode.id === 'conquest');
    this.lastMini = '';
    this.lastHtml.clear();
    this.objStatus.style.display = match.mode.id === 'takeover' || match.mode.id === 'conquest' ? '' : 'none';
    this.thirdScore.style.display = match.teamCount === 3 ? '' : 'none';
    for (const mk of this.sectorMarkers) mk.style.display = 'none';
    if (!match.teams) {
      this.myScore.style.removeProperty('--tc');
      this.leadScore.style.removeProperty('--tc');
    }
  }

  private updateTeamWidgets(now: number, p: Player, actors: Actor[], match: Match, cam: THREE.PerspectiveCamera) {
    const a = p.actor;
    const W = window.innerWidth, H = window.innerHeight;
    // floating name tags over teammates
    let i = 0;
    if (match.teams) {
      for (const o of actors) {
        const down = o.isDowned(now);
        if (o === a || o.team !== a.team || (!o.alive && !down) || i >= this.allyTags.length) continue;
        const tag = this.allyTags[i++];
        tag.classList.toggle('down', down);
        this.v.copy(o.pos).setY(o.pos.y + (down ? 2.9 : 2.25)).project(cam);
        if (this.v.z > 1 || Math.abs(this.v.x) > 1.1 || Math.abs(this.v.y) > 1.1) {
          tag.style.display = 'none';
          continue;
        }
        const d = o.pos.distanceTo(a.pos);
        tag.style.display = '';
        tag.style.setProperty('--tc', TEAMS[o.team].color);
        tag.style.opacity = String(clamp(1.2 - d / 60, 0.45, 1));
        tag.style.transform = `translate(${((this.v.x * 0.5 + 0.5) * W).toFixed(1)}px, ${((-this.v.y * 0.5 + 0.5) * H).toFixed(1)}px) translate(-50%, -100%)`;
        if (down) {
          tag.style.opacity = '1';
          setText(tag.lastChild as HTMLElement, o.reviveT > 0 ? `${o.name}  reviving ${Math.round((o.reviveT / COMBAT.reviveTime) * 100)}%` : `✚ ${o.name}  ${Math.ceil(o.respawnAt - now)}s`);
        } else setText((tag.lastChild as HTMLElement), d < 30 ? o.name : '');
      }
    }
    for (; i < this.allyTags.length; i++) this.allyTags[i].style.display = 'none';
    // toy box objective marker, pinned to the screen edge when off-screen
    const hill = match.hill;
    if (!hill || !a.alive) {
      this.objMarker.style.display = 'none';
    } else {
      this.v.copy(hill.pos).setY(hill.pos.y + hill.site.height * 0.5);
      const toCam = this.v.clone().applyMatrix4(cam.matrixWorldInverse);
      const behind = toCam.z > 0;
      this.v.project(cam);
      let x = this.v.x, y = this.v.y;
      if (behind) {
        x = -x;
        y = -y;
      }
      const edge = behind || Math.abs(x) > 0.92 || Math.abs(y) > 0.86;
      if (edge) {
        const k = Math.max(Math.abs(x) / 0.92, Math.abs(y) / 0.86, 1e-3);
        x /= k;
        y /= k;
        if (behind && Math.abs(y) < 0.86 && Math.abs(x) < 0.92) y = -0.86;
      }
      const inside = match.inHill(a);
      const col = hill.contested ? '#ff4d8d' : hill.owner >= 0 ? TEAMS[hill.owner].color : '#fff6d8';
      this.objMarker.style.display = inside ? 'none' : '';
      this.objMarker.style.setProperty('--tc', col);
      this.objMarker.style.transform = `translate(${((x * 0.5 + 0.5) * W).toFixed(1)}px, ${((-y * 0.5 + 0.5) * H).toFixed(1)}px) translate(-50%, -50%)`;
      setText((this.objMarker.lastChild as HTMLElement), `${Math.round(a.pos.distanceTo(hill.pos))} m`);
    }
    // conquest: a marker over every sector you can see, and the sector strip
    if (match.sectors.length) {
      const here = match.sectorOf(a);
      match.sectors.forEach((s, i) => {
        const mk = this.sectorMarkers[i];
        if (!a.alive || i === here) {
          mk.style.display = 'none';
          return;
        }
        this.v.copy(s.pos).setY(s.pos.y + s.def.height + 1.2);
        const vc = this.v.clone().applyMatrix4(cam.matrixWorldInverse);
        this.v.project(cam);
        if (vc.z > 0 || Math.abs(this.v.x) > 1.05 || Math.abs(this.v.y) > 1.05) {
          mk.style.display = 'none';
          return;
        }
        const col = s.contested ? '#ff4d8d' : s.owner >= 0 ? TEAMS[s.owner].color : '#fff6d8';
        mk.style.display = '';
        mk.style.setProperty('--tc', col);
        mk.classList.toggle('mine', s.owner === a.team);
        mk.classList.toggle('busy', s.active >= 0 || s.contested);
        mk.style.transform = `translate(${((this.v.x * 0.5 + 0.5) * W).toFixed(1)}px, ${((-this.v.y * 0.5 + 0.5) * H).toFixed(1)}px) translate(-50%, -50%)`;
        setText((mk.firstChild as HTMLElement), s.def.letter);
        setText((mk.lastChild as HTMLElement), `${Math.round(a.pos.distanceTo(s.pos))} m`);
      });
      const strip = match.sectors
        .map((s, i) => {
          const owner = s.owner >= 0 ? TEAMS[s.owner].color : '#fff6d8';
          const prog = s.owner >= 0 ? s.progress : s.progress;
          const pc = s.owner >= 0 && s.progress >= 1 ? 'transparent' : s.active >= 0 ? TEAMS[s.active].color : s.progressTeam >= 0 ? TEAMS[s.progressTeam].color : '#fff';
          const cls = `${s.contested ? 'contested' : ''}${i === here ? ' here' : ''}${s.owner === a.team ? ' ours' : ''}`;
          return `<div class="sec ${cls}" style="--oc:${owner};--pc:${pc}"><b>${s.def.letter}</b><i style="width:${(prog * 100).toFixed(0)}%"></i><span>${esc(s.def.short)}</span></div>`;
        })
        .join('');
      let state: string;
      if (here >= 0) {
        const s = match.sectors[here];
        const name = s.def.name.replace(/^the /, '');
        if (s.contested) state = `${name}: contested, kill the enemies inside`;
        else if (s.owner === a.team) state = s.progress < 1 ? `${name}: restoring ${Math.round(s.progress * 100)}%` : `${name}: yours, hold it`;
        else if (s.owner >= 0) state = `${name}: draining Team ${TEAMS[s.owner].name}'s hold ${Math.round((1 - s.progress) * 100)}%`;
        else state = `${name}: capturing ${Math.round((s.progressTeam === a.team ? s.progress : 0) * 100)}%`;
      } else {
        const n = match.sectorsOwned(a.team);
        state = `Your team holds ${n} of 6. Control 4 to win.`;
      }
      this.objStatus.style.setProperty('--tc', TEAMS[Math.max(0, a.team)].color);
      this.setObj(`<div class="strip">${strip}</div><span>${esc(state)}</span>`);
    }
    if (hill && match.mode.id === 'takeover') {
      const inside = match.inHill(a);
      const state = hill.contested ? 'Contested' : hill.owner < 0 ? 'Empty' : hill.owner === a.team ? 'Your team is winding up' : 'Enemy team is winding up';
      const col = hill.contested ? '#ff4d8d' : hill.owner >= 0 ? TEAMS[hill.owner].color : '#fff6d8';
      this.objStatus.style.setProperty('--tc', col);
      this.setObj(`<b>Toy box: ${esc(hill.site.name)}</b><span>${state}${inside ? ' (you are in it)' : ''}</span><span class="mv">Moves in ${Math.ceil(hill.timeLeft)} s</span>`);
    }
    void now;
  }

  private lastHtml = new Map<HTMLElement, string>();
  /** Only touch the DOM when the markup actually changed (rebuilding it every frame churns memory). */
  private setHtml(el: HTMLElement, html: string) {
    if (this.lastHtml.get(el) === html) return;
    this.lastHtml.set(el, html);
    el.innerHTML = html;
  }
  private setObj(html: string) {
    this.setHtml(this.objStatus, html);
  }

  applySettings() {
    const s = settings.data;
    this.root.style.setProperty('--xh-color', s.crosshairColor);
    this.root.style.setProperty('--xh-size', String(s.crosshairSize));
    (this.xh.querySelector('.d') as HTMLElement).style.display = s.crosshairDot ? '' : 'none';
    this.fps.style.display = s.showFps ? '' : 'none';
  }

  show(on: boolean) {
    this.root.style.display = on ? '' : 'none';
  }

  reset() {
    this.feed.innerHTML = '';
    this.pickups.innerHTML = '';
    this.center.innerHTML = '';
    this.lastMini = '';
    this.lastWeaponKey = '';
    this.lastBuffKey = '';
    for (const n of this.nums) {
      n.life = 0;
      n.el.style.opacity = '0';
    }
    for (const d of this.dirs) {
      d.life = 0;
      d.el.style.opacity = '0';
    }
    this.death.classList.add('hidden');
    this.announceEl.classList.add('hidden');
    this.countdownEl.classList.add('hidden');
    this.hpShown = 100;
    this.shShown = 0;
  }

  // ------------------------------------------------------------------ feedback
  hit(kind: 'body' | 'head' | 'shield' | 'kill') {
    const m = this.hitmark;
    m.className = 'hitmark';
    void m.offsetWidth; // restart animation
    m.className = `hitmark on ${kind}`;
  }

  damageNumber(pos: THREE.Vector3, amount: number, kind: 'body' | 'head' | 'shield') {
    if (!settings.data.damageNumbers) return;
    const n = this.nums.reduce((a, b) => (a.life < b.life ? a : b));
    n.pos.copy(pos);
    n.life = 0.9;
    n.drift = (Math.random() - 0.5) * 40;
    n.el.className = `dmgnum ${kind === 'body' ? '' : kind}`;
    n.el.textContent = String(Math.round(amount));
  }

  damageFrom(from: THREE.Vector3) {
    const d = this.dirs.reduce((a, b) => (a.life < b.life ? a : b));
    d.from.copy(from);
    d.life = 1.2;
  }

  hurt(shield: boolean) {
    if (shield) this.shieldT = 0.3;
    else this.hurtT = 0.35;
  }

  killFeed(killer: Actor | null, victim: Actor, weapon: string, head: boolean, mine: boolean) {
    const row = h('div', mine ? 'mine' : '');
    const kn = killer ? `<span style="color:${nameColor(killer)}">${esc(killer.name)}</span>` : '';
    row.innerHTML = `${kn}<span class="w">${esc(weapon)}${head ? ' <span class="hs">★</span>' : ''}</span><span style="color:${nameColor(victim)}">${esc(victim.name)}</span>`;
    this.feed.prepend(row);
    while (this.feed.children.length > 6) this.feed.lastChild!.remove();
    window.setTimeout(() => (row.style.opacity = '0'), 5200);
    window.setTimeout(() => row.remove(), 6000);
  }

  eliminated(name: string, streak: number, head: boolean) {
    this.center.innerHTML = '';
    const e = h('div', 'elim shadow', `Popped ${esc(name)}<span class="plus">+1</span>${head ? '<small>Headshot</small>' : ''}`);
    this.center.append(e);
    if (STREAKS[streak]) this.center.append(h('div', 'streak shadow', STREAKS[streak]));
    this.centerT = 2.2;
  }

  pickup(label: string, color: string) {
    const row = h('div', '', esc(label));
    row.style.setProperty('--c', color);
    this.pickups.prepend(row);
    while (this.pickups.children.length > 4) this.pickups.lastChild!.remove();
    window.setTimeout(() => (row.style.opacity = '0'), 2500);
    window.setTimeout(() => row.remove(), 3100);
  }

  announce(text: string, sub = '', dur = 2.6) {
    this.announceEl.innerHTML = `${esc(text)}${sub ? `<small>${esc(sub)}</small>` : ''}`;
    this.announceEl.classList.remove('hidden');
    this.announceEl.style.animation = 'none';
    void this.announceEl.offsetWidth;
    this.announceEl.style.animation = '';
    this.announceT = dur;
  }

  countdown(v: number | 'GO' | null) {
    if (v === null) {
      this.countdownEl.classList.add('hidden');
      return;
    }
    this.countdownEl.textContent = v === 'GO' ? 'GO!' : String(v);
    this.countdownEl.classList.remove('hidden');
    this.countdownEl.style.animation = 'none';
    void this.countdownEl.offsetWidth;
    this.countdownEl.style.animation = '';
    if (v === 'GO') window.setTimeout(() => this.countdownEl.classList.add('hidden'), 800);
  }

  setDeath(killer: string, weapon: string) {
    this.killerName = killer;
    this.killerWeapon = weapon;
  }

  setScoreboard(on: boolean) {
    this.boardVisible = on;
    this.board.classList.toggle('hidden', !on);
  }

  boardHtml(actors: Actor[], match: Match, me: Actor | null) {
    if (match.teams) {
      const head = `<thead><tr><th>#</th><th>Toy</th><th class="num">Pops</th><th class="num">Popped</th><th class="num">Best streak</th><th class="num">Damage</th></tr></thead>`;
      return match.teamScores
        .map((_, t) => t)
        .map((t) => {
          const team = TEAMS[t];
          const rows = match.standings(actors.filter((a) => a.team === t))
            .map((a, i) => `<tr class="${a === me ? 'me' : ''}"><td>${i + 1}</td><td><span class="dot" style="background:${a.def.accent}"></span>${esc(a.name)}</td><td class="num">${a.kills}</td><td class="num">${a.deaths}</td><td class="num">${a.bestStreak}</td><td class="num">${Math.round(a.damageDealt)}</td></tr>`)
            .join('');
          const score = Math.floor(match.teamScores[t]);
          const suffix = match.mode.id === 'takeover' ? ` / ${match.mode.scoreTarget}` : match.mode.id === 'conquest' ? ` / 6 sectors` : '';
          return `<div class="team-head" style="--tc:${team.color}"><span>Team ${team.name}</span><b>${score}${suffix}</b></div><table class="board team">${head}<tbody>${rows}</tbody></table>`;
        })
        .join('');
    }
    const rows = match.standings(actors)
      .map((a, i) => `<tr class="${a === me ? 'me' : ''}"><td>${i + 1}</td><td><span class="dot" style="background:${a.def.accent}"></span>${esc(a.name)}</td><td class="num">${a.kills}</td><td class="num">${a.deaths}</td><td class="num">${a.bestStreak}</td><td class="num">${Math.round(a.damageDealt)}</td></tr>`)
      .join('');
    return `<table class="board"><thead><tr><th>#</th><th>Toy</th><th class="num">Pops</th><th class="num">Popped</th><th class="num">Best streak</th><th class="num">Damage</th></tr></thead><tbody>${rows}</tbody></table>`;
  }

  // ------------------------------------------------------------------ per frame
  update(dt: number, now: number, p: Player, actors: Actor[], match: Match, cam: THREE.PerspectiveCamera, zoneName: string) {
    const a = p.actor;
    const W = window.innerWidth, H = window.innerHeight;
    // fps
    this.fpsAcc += dt;
    this.fpsFrames++;
    if (this.fpsAcc > 0.5) {
      this.fps.textContent = `${Math.round(this.fpsFrames / this.fpsAcc)} fps`;
      this.fpsAcc = 0;
      this.fpsFrames = 0;
    }
    const ws = a.weapon;
    const alive = a.alive;
    // crosshair spread (degrees -> pixels)
    const scoped = !!ws?.overlay && a.ads > 0.9;
    const lit = !!ws && ws.scope.style === 'reticle' && a.ads > 0.75 && alive;
    if (ws) {
      const key = `${ws.id}|${ws.scope.id}`;
      if (key !== this.scopeKey) {
        this.scopeKey = key;
        const col = WEAPONS[ws.id].colors;
        const mark = ws.id === 'thunderspring' ? '#ff4d6d' : col.accent;
        this.scope.style.setProperty('--rim', col.main);
        this.scope.style.setProperty('--rim2', col.accent);
        (this.scope.lastChild as HTMLElement).innerHTML = ws.overlay ? scopeSvg(RETICLES[ws.id], mark, ws.zoom) : '';
        this.reticle.innerHTML = ws.scope.style === 'reticle' ? `<svg viewBox="-60 -60 120 120">${reticleMark(RETICLES[ws.id], col.glow)}</svg>` : '';
        this.reticle.style.setProperty('--glow', col.glow);
        this.reticle.classList.toggle('big', ws.scope.id === 'ring');
      }
    }
    this.reticle.style.opacity = lit ? String(clamp((a.ads - 0.75) * 6, 0, 1)) : '0';
    const px = (Math.tan(p.spreadDeg * DEG) / Math.tan((cam.fov * DEG) / 2)) * (H / 2);
    this.root.style.setProperty('--xh-gap', `${clamp(px, 3, 120).toFixed(1)}px`);
    this.xh.classList.toggle('ads', a.ads > 0.6);
    this.xh.style.display = alive && !scoped && !lit ? '' : 'none';
    // scope
    this.scope.style.opacity = scoped && alive ? '1' : '0';
    if (scoped) {
      const k = p.scopeKick;
      (this.scope as HTMLElement).style.transform = `translate(${(Math.sin(now * 40) * k * 6).toFixed(1)}px, ${(k * 26).toFixed(1)}px)`;
    }
    // reload ring
    const rl = ws?.reloading ?? false;
    this.reloadRing.style.display = rl && alive ? '' : 'none';
    this.reloading.style.display = rl && alive ? '' : 'none';
    if (rl && ws) this.reloadFg.setAttribute('stroke-dashoffset', `${2 * Math.PI * 22 * (1 - ws.reloadProgress)}`);
    // vitals with smooth animation
    if (a.health < this.lastHp - 0.5 || a.shield < this.lastSh - 0.5) this.hurt(a.shield < this.lastSh - 0.5 && a.health >= this.lastHp - 0.5);
    this.lastHp = a.health;
    this.lastSh = a.shield;
    this.hpShown += (a.health - this.hpShown) * Math.min(1, dt * 12);
    this.shShown += (a.shield - this.shShown) * Math.min(1, dt * 12);
    const hpPct = clamp(this.hpShown / COMBAT.maxHealth, 0, 1) * 100;
    const shPct = clamp(this.shShown / COMBAT.maxShield, 0, 1) * 100;
    (this.hpBar.querySelector('.fill') as HTMLElement).style.width = `${hpPct}%`;
    (this.hpBar.querySelector('.ghost') as HTMLElement).style.width = `${(a.health / COMBAT.maxHealth) * 100}%`;
    setText((this.hpBar.querySelector('span') as HTMLElement), String(Math.ceil(a.health)));
    this.hpBar.classList.toggle('low', a.health < 35);
    (this.shBar.querySelector('.fill') as HTMLElement).style.width = `${shPct}%`;
    (this.shBar.querySelector('.ghost') as HTMLElement).style.width = `${(a.shield / COMBAT.maxShield) * 100}%`;
    setText((this.shBar.querySelector('span') as HTMLElement), a.shield > 0 ? String(Math.ceil(a.shield)) : '');
    this.shBar.style.opacity = a.shield > 0 ? '1' : '0.45';
    this.vignette.style.opacity = alive ? String(clamp((45 - a.health) / 45, 0, 1) * 0.8) : '0';
    this.hurtT = Math.max(0, this.hurtT - dt);
    this.shieldT = Math.max(0, this.shieldT - dt);
    this.hurtFlash.style.opacity = String(this.hurtT * 2);
    this.shieldFlash.style.opacity = String(this.shieldT * 2.5);
    // buffs
    const buffList = (['turbo', 'infinite', 'power'] as const).filter((k) => a.buffs[k] > now);
    const bkey = buffList.join(',');
    if (bkey !== this.lastBuffKey) {
      this.lastBuffKey = bkey;
      this.buffs.innerHTML = buffList
        .map((k) => `<div class="buff" data-k="${k}" style="--c:${PICKUP_INFO[k].color}" title="${PICKUP_INFO[k].label}">${PICKUP_INFO[k].icon}<svg viewBox="0 0 44 44"><circle cx="22" cy="22" r="19" stroke-dasharray="${2 * Math.PI * 19}"></circle></svg></div>`)
        .join('');
    }
    for (const el of Array.from(this.buffs.children) as HTMLElement[]) {
      const k = el.dataset.k as 'turbo' | 'infinite' | 'power';
      const total = k === 'infinite' ? 6 : 8;
      const left = Math.max(0, a.buffs[k] - now);
      el.querySelector('circle')!.setAttribute('stroke-dashoffset', `${2 * Math.PI * 19 * (1 - left / total)}`);
    }
    // weapon
    if (ws) {
      const other = a.weapons[a.slot === 0 ? 1 : 0];
      const inf = a.hasBuff('infinite', now);
      const key = `${ws.id}|${Math.ceil(ws.mag)}|${ws.reserve}|${a.slot}|${other?.id}|${inf}|${ws.lockout}|${inputDevice.pad}|${actionName('swap')}${actionName('weapon1')}${actionName('weapon2')}`;
      if (key !== this.lastWeaponKey) {
        this.lastWeaponKey = key;
        const low = ws.mag <= ws.cfg.magSize * 0.25;
        const res = ws.isEnergy ? (ws.lockout ? 'cooling' : 'energy') : inf ? '∞' : String(ws.reserve);
        this.weapon.style.setProperty('--c', ws.cfg.colors.main === '#1d1d1f' || ws.cfg.colors.main === '#f2f7ff' ? ws.cfg.colors.accent : ws.cfg.colors.main);
        const slots = a.weapons.map((w, i) => (w ? `<div class="${i === a.slot ? 'on' : ''}">${slotKey(i, a.slot)}${w.cfg.name}</div>` : '')).join('');
        this.weapon.innerHTML = `<div class="name">${ws.cfg.name}</div><div class="ammo"><span class="mag ${low ? 'low' : ''}">${Math.ceil(ws.mag)}</span><span class="res">/ ${res}</span></div>${ws.isEnergy ? `<div class="energy"><i style="width:${(ws.mag / ws.cfg.magSize) * 100}%"></i></div>` : ''}<div class="slots">${slots}</div>`;
      }
    }
    // abilities
    const C = 2 * Math.PI * 25;
    ABIL_UI.forEach((u, i) => {
      const e = this.abilEls[i];
      const slot = a.abilities.indexOf(u.k);
      e.el.style.display = slot < 0 ? 'none' : '';
      if (slot < 0) return;
      e.el.style.order = String(slot);
      const k = actionName(slot ? 'ability2' : 'ability1', true);
      setText(e.key, k === 'unbound' ? '–' : k);
      e.key.classList.toggle('long', k.length > 2);
      let left = 0, total = 1, active = false, activeFrac = 0;
      if (u.k === 'dash') (left = a.dashReadyAt - now), (total = MOVE.dashCooldown);
      else if (u.k === 'jab') (left = a.jabReadyAt - now), (total = ABILITIES.jab.cooldown);
      else if (u.k === 'grapple') (left = a.grappleReadyAt - now), (total = ABILITIES.grapple.cooldown), (active = !!a.grapple);
      else if (u.k === 'shield') (left = a.shieldReadyAt - now), (total = ABILITIES.shield.cooldown);
      else {
        if (a.cloaked) {
          active = true;
          activeFrac = 1 - (now - a.cloakStart) / ABILITIES.cloak.maxActive;
        } else (left = a.cloakReadyAt - now), (total = Math.max(left, ABILITIES.cloak.baseCooldown));
      }
      left = Math.max(0, left);
      const ready = left <= 0 && !active;
      e.el.classList.toggle('ready', ready);
      e.el.classList.toggle('active', active);
      e.el.classList.toggle('denied', p.denied.key === u.k && now - p.denied.at < 0.35);
      const frac = active ? 1 - Math.max(0, activeFrac) : left / Math.max(0.01, total);
      e.ring.setAttribute('stroke-dashoffset', `${C * Math.min(1, frac)}`);
      setText(e.cd, active && u.k === 'cloak' ? `${Math.ceil(Math.max(0, activeFrac) * ABILITIES.cloak.maxActive)}` : left > 0 ? (left < 10 ? left.toFixed(1) : String(Math.ceil(left))) : '');
    });
    // bow draw ring
    const drawing = alive && !!ws && ws.drawing;
    this.chargeRing.style.display = drawing ? '' : 'none';
    if (drawing && ws) {
      const c = ws.chargeAt(now);
      const fg = this.chargeRing.querySelector('.fg') as SVGCircleElement;
      const CC = 2 * Math.PI * 34;
      fg.setAttribute('stroke-dasharray', `${CC}`);
      fg.setAttribute('stroke-dashoffset', `${CC * (1 - c)}`);
      this.chargeRing.classList.toggle('full', c >= 0.999);
      const dmg = ws.cfg.damage * Math.pow(c, ws.cfg.charge!.curve);
      setText((this.chargeRing.lastChild as HTMLElement), `${Math.round(dmg)} / ${Math.round(dmg * ws.cfg.headMult)}`);
    }
    this.cloakFx.style.opacity = alive && a.cloaked ? '1' : '0';
    // prompt
    this.prompt.style.display = p.interactPrompt ? '' : 'none';
    if (p.interactPrompt) setText(this.prompt, p.interactPrompt);
    // timer + scores
    const t = match.phase === 'countdown' ? match.mode.timeLimit : match.timeLeft;
    setText(this.timer, formatTime(t));
    this.timer.classList.toggle('low', t < 30 && match.phase === 'playing');
    const standings = match.standings(actors);
    const leader = standings[0];
    const myRank = standings.indexOf(a) + 1;
    const leaderOther = leader === a ? standings[1] : leader;
    if (match.teams) {
      // your team on the left, always
      const mine = Math.max(0, a.team);
      const others = match.teamScores.map((_, t) => t).filter((t) => t !== mine);
      const tgt = match.mode.scoreTarget;
      const conq = match.mode.id === 'conquest';
      const chip = (team: number, label: string) => {
        const s = match.teamScores[team];
        const pct = Math.min(100, (s / tgt) * 100);
        return `<b>${Math.floor(s)}${conq ? `<small>/${tgt}</small>` : ''}</b>${label}<i class="meter"><i style="width:${pct.toFixed(1)}%;background:${TEAMS[team].color}"></i></i>`;
      };
      this.setHtml(this.myScore, chip(mine, `Team ${TEAMS[mine].name}`));
      this.myScore.style.setProperty('--tc', TEAMS[mine].color);
      [this.leadScore, this.thirdScore].forEach((el, i) => {
        const t = others[i];
        if (t === undefined) return;
        this.setHtml(el, chip(t, `Team ${TEAMS[t].name}`));
        el.style.setProperty('--tc', TEAMS[t].color);
      });
      const mates = match.standings(actors.filter((x) => x.team === a.team));
      const miniKey = mates.map((x) => `${x.id}:${x.kills}:${x.alive}`).join('|') + match.mode.id;
      if (miniKey !== this.lastMini) {
        this.lastMini = miniKey;
        const goal = match.mode.id === 'takeover' ? `Hold the toy box. First to ${tgt}` : conq ? `Control ${tgt} of 6 sectors` : `First team to ${tgt} pops`;
        this.mini.innerHTML = `<span class="goal">${goal}</span>` + mates.map((x) => `<div class="${x === a ? 'me' : ''}${x.alive ? '' : ' down'}"><b>${x.alive ? '●' : '✕'}</b><span style="color:${x === a ? 'var(--sun)' : TEAMS[x.team].light}">${esc(x.name)}</span><span>${x.kills}</span></div>`).join('');
      }
    } else {
    this.setHtml(this.myScore, `<b>${a.kills}</b>You`);
    this.setHtml(this.leadScore, `<b>${leaderOther?.kills ?? 0}</b>${leader === a ? '2nd' : 'Leader'}`);
    // mini scoreboard (top 4 + you)
    const top = standings.slice(0, 4);
    if (!top.includes(a)) top.push(a);
    const miniKey = top.map((x) => `${x.id}:${x.kills}`).join('|') + myRank;
    if (miniKey !== this.lastMini) {
      this.lastMini = miniKey;
      this.mini.innerHTML = `<span class="goal">First to ${match.killTarget} pops</span>` + top.map((x) => `<div class="${x === a ? 'me' : ''}"><b>${standings.indexOf(x) + 1}</b><span style="color:${x === a ? 'var(--sun)' : x.def.accent}">${esc(x.name)}</span><span>${x.kills}</span></div>`).join('');
    }
    }
    // damage numbers
    for (const n of this.nums) {
      if (n.life <= 0) continue;
      n.life -= dt;
      this.v.copy(n.pos);
      this.v.y += (0.9 - n.life) * 0.8;
      this.v.project(cam);
      if (this.v.z > 1 || n.life <= 0) {
        n.el.style.opacity = '0';
        continue;
      }
      const x = (this.v.x * 0.5 + 0.5) * W + n.drift * (0.9 - n.life);
      const y = (-this.v.y * 0.5 + 0.5) * H;
      const s = 1 + Math.max(0, n.life - 0.7) * 2.5;
      n.el.style.opacity = String(Math.min(1, n.life / 0.3));
      n.el.style.transform = `translate(${x.toFixed(1)}px, ${y.toFixed(1)}px) translate(-50%, -50%) scale(${s.toFixed(2)})`;
    }
    // damage direction indicators
    for (const d of this.dirs) {
      if (d.life <= 0) continue;
      d.life -= dt;
      const dx = d.from.x - a.pos.x, dz = d.from.z - a.pos.z;
      const ang = Math.atan2(-dx, -dz) - a.yaw; // relative to view
      d.el.style.opacity = String(clamp(d.life, 0, 1));
      d.el.style.transform = `rotate(${(-ang).toFixed(3)}rad)`;
    }
    // transient messages
    if (this.centerT > 0) {
      this.centerT -= dt;
      if (this.centerT <= 0) this.center.innerHTML = '';
    }
    if (this.announceT > 0) {
      this.announceT -= dt;
      if (this.announceT <= 0) this.announceEl.classList.add('hidden');
    }
    // death overlay
    this.death.classList.toggle('hidden', alive || match.phase === 'ended');
    if (!alive) {
      setText((this.death.querySelector('.by') as HTMLElement), this.killerName ? `by ${this.killerName} with ${this.killerWeapon}` : this.killerWeapon);
      setText((this.death.querySelector('.respawn') as HTMLElement), `Reassembling in ${Math.max(0, a.respawnAt - now).toFixed(1)}`);
      const sp = p.spectating;
      this.death.classList.toggle('spectating', !!sp);
      let note = '';
      if (a.reviveT > 0 && a.reviver) note = `${a.reviver.name} is reviving you  ${Math.round((a.reviveT / COMBAT.reviveTime) * 100)}%`;
      else if (a.reviver) note = `${a.reviver.name} is coming to revive you`;
      else if (sp) note = `Spectating ${sp.name}. Click for the next teammate`;
      else if (match.teams) note = 'A teammate can revive you by holding E on your body';
      setText(this.death.querySelector('.spec') as HTMLElement, note);
    }
    for (const el of [this.vitals, this.weapon, this.ability]) el.style.visibility = alive ? 'visible' : 'hidden';
    if (this.boardVisible) this.setHtml(this.board, `<h3>${match.mode.name}</h3>${this.boardHtml(actors, match, a)}`);
    this.updateTeamWidgets(now, p, actors, match, cam);
    setText(this.zone, zoneName);
  }
}

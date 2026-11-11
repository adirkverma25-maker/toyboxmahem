import * as THREE from 'three';
import { settings, Difficulty, Quality, Settings } from '../core/Settings';
import { ABILITIES, ABILITY_ORDER, AbilityId, SCOPES, ScopeId, WEAPONS, WEAPON_ORDER, WEAPON_SCOPES, WeaponId } from '../weapons/weaponConfig';
import { ACTIONS, Action, binds, keyLabel, padLabel } from '../core/Bindings';
import { actionName, type Input } from '../core/Input';
import { accounts, MIN_PASSWORD } from '../core/Accounts';
import { progress, tierOf, TIER_COLORS, type Reward } from '../core/Progress';
import { loadout } from '../weapons/loadout';
import { MAPS, MAP_ORDER, MapId, selectedMap } from '../world/maps';
import { buildWeaponModel } from '../weapons/WeaponModels';
import { RoomEnvironment } from 'three/examples/jsm/environments/RoomEnvironment.js';
import type { Actor } from '../entities/Actor';
import type { Match } from '../match/Match';
import type { AudioEngine } from '../audio/Audio';
import { MODES, MODE_ORDER, ModeId, TEAMS, DRAW } from '../match/modes';

const esc = (s: string) => s.replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]!);

export interface MenuCallbacks {
  start(d: Difficulty, mode: ModeId): void;
  resume(): void;
  quit(): void;
  playAgain(): void;
  settingsChanged(s: Settings, key: keyof Settings): void;
}

type ScreenName = 'main' | 'play' | 'collection' | 'settings' | 'controls' | 'credits' | 'pause' | 'results' | 'login' | null;
const coin = (n: number) => `<span class="coins"><i class="coin"></i>${n.toLocaleString()}</span>`;


/** Short names and one-line descriptions for the ability picker. */
const ABILITY_INFO: Record<AbilityId, { short: string; desc: string }> = {
  dash: { short: 'Dash', desc: `Burst forward a few meters. ${ABILITIES.dash.cooldown} s cooldown.` },
  jab: { short: 'Punch', desc: `${ABILITIES.jab.damage} damage up close and a shove. ${ABILITIES.jab.cooldown} s cooldown.` },
  grapple: { short: 'Hook', desc: `Pull yourself to a spot up to ${ABILITIES.grapple.range} m away, up and over ledges. ${ABILITIES.grapple.cooldown} s cooldown.` },
  cloak: { short: 'Cloak', desc: `Invisible beyond ${ABILITIES.cloak.revealDistance} m for up to ${ABILITIES.cloak.maxActive} s. Press again to drop it. Firing drops it.` },
  shield: { short: 'Shield', desc: `Wall that stops ${ABILITIES.shield.hp} enemy damage for ${ABILITIES.shield.duration} s. ${ABILITIES.shield.cooldown} s cooldown.` },
};

export class Menus {
  root = document.createElement('div');
  current: ScreenName = null;
  private back: ScreenName = 'main';
  private difficulty: Difficulty = settings.data.difficulty;
  private preview: { renderer: THREE.WebGLRenderer; scene: THREE.Scene; cam: THREE.PerspectiveCamera; model: THREE.Object3D | null; raf: number } | null = null;
  private selectedWeapon: WeaponId = 'plasti9';
  private mode: ModeId = 'ffa';
  private map: MapId = selectedMap().id;
  /** set by the game: used to listen for the key/button when rebinding */
  input: Input | null = null;
  /** which ability slot the next pick goes into on the loadout screen */
  private abilSlot: 0 | 1 = 0;

  /** After a map change reloads the page, land back on the Play screen instead of the main menu. */
  openAfterLoad() {
    try {
      const raw = sessionStorage.getItem('toybox-mayhem.resume');
      if (raw) {
        sessionStorage.removeItem('toybox-mayhem.resume');
        const m = JSON.parse(raw).mode;
        if (m in MODES) this.mode = m;
        return this.play();
      }
    } catch {
      /* fall through */
    }
    if (accounts.needsChoice()) return this.login('register');
    this.main();
  }

  // ------------------------------------------------------------------ accounts
  /** Log in / create account / play as guest. */
  login(tab: 'login' | 'register' = 'login', back: ScreenName = null) {
    this.current = 'login';
    const reg = tab === 'register';
    const saved = accounts.savedNames();
    this.set(
      `<div class="panel card login">
        <h2 class="title">${reg ? 'Create an account' : 'Log in'}</h2>
        <p class="lede">Your account keeps your coins, unlocked blasters, stats, loadout and controls.</p>
        <div class="seg tabs" role="group" aria-label="Account"><button data-tab="login" aria-pressed="${!reg}"><b>Log in</b></button><button data-tab="register" aria-pressed="${reg}"><b>Create account</b></button></div>
        <form class="login-form" autocomplete="off" novalidate>
          <label class="field"><span>Name</span><input name="user" maxlength="14" autocomplete="username" spellcheck="false" placeholder="2 to 14 letters or numbers"></label>
          <label class="field"><span>Password</span><input name="pass" type="password" autocomplete="${reg ? 'new-password' : 'current-password'}" placeholder="at least ${MIN_PASSWORD} characters"></label>
          ${reg ? '<label class="field"><span>Password again</span><input name="pass2" type="password" autocomplete="new-password"></label>' : ''}
          <p class="err" role="alert"></p>
          <div class="actions"><button type="submit" class="btn primary small">${reg ? 'Create account' : 'Log in'}</button><button type="button" class="btn ghost small" data-a="guest">${back ? 'Back' : 'Play as guest'}</button></div>
        </form>
        ${saved.length && !reg ? `<p class="label">Accounts on this computer</p><div class="chips saved">${saved.map((n) => `<button type="button" data-name="${esc(n)}">${esc(n)}</button>`).join('')}</div>` : ''}
        <p class="note">Accounts are saved in this browser on this computer (the password is stored as a salted hash, never as text). Use a password you don't use anywhere else. Playing as a guest saves progress too, just not under a name. Online accounts will come with multiplayer.</p>
      </div>`,
      'panel-wrap dim',
    );
    const form = this.root.querySelector('form') as HTMLFormElement;
    const err = this.root.querySelector('.err') as HTMLElement;
    const user = form.elements.namedItem('user') as HTMLInputElement;
    this.root.querySelectorAll<HTMLButtonElement>('[data-tab]').forEach((b) => b.addEventListener('click', () => this.login(b.dataset.tab as 'login' | 'register', back)));
    this.root.querySelectorAll<HTMLButtonElement>('[data-name]').forEach((b) =>
      b.addEventListener('click', () => {
        user.value = b.dataset.name!;
        (form.elements.namedItem('pass') as HTMLInputElement).focus();
      }),
    );
    this.on('[data-a=guest]', () => {
      if (back) return this.main();
      accounts.playAsGuest();
      this.main();
    });
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const name = user.value;
      const pass = (form.elements.namedItem('pass') as HTMLInputElement).value;
      err.textContent = '';
      try {
        if (reg) {
          const pass2 = (form.elements.namedItem('pass2') as HTMLInputElement).value;
          if (pass !== pass2) throw new Error("The two passwords don't match.");
          await accounts.register(name, pass);
        } else await accounts.login(name, pass);
        this.audio.uiClick();
        this.main();
      } catch (ex) {
        err.textContent = (ex as Error).message;
      }
    });
    setTimeout(() => user.focus(), 0);
  }

  constructor(parent: HTMLElement, private cb: MenuCallbacks, private audio: AudioEngine) {
    parent.appendChild(this.root);
    const rescale = () => (this.root.style.zoom = String(Math.min(1.35, Math.max(0.7, Math.min(window.innerHeight / 900, window.innerWidth / 1500)))));
    rescale();
    window.addEventListener('resize', rescale);
    // click / hover sounds for every button
    this.root.addEventListener('pointerover', (e) => {
      const t = e.target as HTMLElement;
      if (t.closest('button')) this.audio.uiHover();
    });
    this.root.addEventListener('click', (e) => {
      const t = e.target as HTMLElement;
      if (t.closest('button')) {
        this.audio.init();
        this.audio.music?.start();
        this.audio.uiClick();
      }
    });
  }

  private set(html: string, cls: string) {
    this.stopPreview();
    this.root.innerHTML = `<div class="screen ${cls}">${html}</div>`;
  }
  private on(sel: string, fn: () => void) {
    this.root.querySelector(sel)?.addEventListener('click', fn);
  }

  hide() {
    this.stopPreview();
    this.root.innerHTML = '';
    this.current = null;
  }

  // ------------------------------------------------------------------ main
  main() {
    this.current = 'main';
    const st = settings.stats;
    const acc = st.shotsFired ? Math.round((st.shotsHit / st.shotsFired) * 100) : 0;
    const acct = accounts.current();
    this.set(
      `<div class="col">
        <div class="logo" aria-label="Toybox Mayhem"><span class="l1">Toybox</span><span class="l2">Mayhem</span>
          <div class="burst"><span>${WEAPON_ORDER.length} toy blasters, ${MAP_ORDER.length} maps</span></div></div>
        <button class="btn primary" data-a="play">Play</button>
        <button class="btn" data-a="collection">Loadout and unlocks</button>
        <button class="btn" data-a="settings">Settings</button>
        <button class="btn" data-a="controls">Controls</button>
        <button class="btn" data-a="credits">Credits</button>
      </div>
      <div class="account-bar card"><div class="who"><small>${acct.guest ? 'Playing as' : 'Logged in as'}</small><b>${esc(acct.name)}</b></div>${coin(progress.coins)}<button class="btn ghost small" data-a="account">${acct.guest ? 'Log in' : 'Switch account'}</button>${acct.guest ? '' : '<button class="btn ghost small" data-a="logout">Log out</button>'}</div>
      <div class="career card"><h3>Your toy record</h3><dl>
        <dt>Matches</dt><dd>${st.matches}</dd><dt>Wins</dt><dd>${st.wins}</dd>
        <dt>Pops</dt><dd>${st.kills}</dd><dt>Times popped</dt><dd>${st.deaths}</dd>
        <dt>Accuracy</dt><dd>${acc}%</dd><dt>Best streak</dt><dd>${st.bestStreak}</dd>
        <dt>Blasters unlocked</dt><dd>${progress.owned.size} / ${WEAPON_ORDER.length}</dd></dl></div>
      <div class="footer-hint shadow">Plays with a mouse and keyboard or a controller (press any button on it to switch).</div>`,
      'main-menu',
    );
    this.on('[data-a=play]', () => this.play());
    this.on('[data-a=collection]', () => this.collection('main'));
    this.on('[data-a=settings]', () => this.settings('main'));
    this.on('[data-a=controls]', () => this.controls('main'));
    this.on('[data-a=credits]', () => this.credits());
    this.on('[data-a=account]', () => this.login('login', 'main'));
    this.on('[data-a=logout]', () => {
      accounts.logout();
      this.main();
    });
    (this.root.querySelector('[data-a=play]') as HTMLElement)?.focus();
  }

  play() {
    this.current = 'play';
    const opts: [Difficulty, string, string][] = [
      ['easy', 'Easy', 'Slow reactions, loose aim. Good for learning the room.'],
      ['normal', 'Normal', 'Toys that fight back and use cover.'],
      ['hard', 'Hard', 'Fast, accurate, and they go for heads.'],
    ];
    const cur = selectedMap().id;
    const lo = () => `<span><small>Primary</small> <b>${WEAPONS[loadout.primary].name}</b> <small>${SCOPES[loadout.scope(loadout.primary)].name}</small></span><span><small>Secondary</small> <b>${WEAPONS[loadout.secondary].name}</b> <small>${SCOPES[loadout.scope(loadout.secondary)].name}</small></span><span><small>Abilities</small> <b>${loadout.abilities.map((a) => ABILITY_INFO[a].short).join(' + ')}</b></span>`;
    const tag: Record<ModeId, string> = { ffa: '15 toys, everyone for themselves', tdm: '4 vs 4', takeover: '4 vs 4, moving objective', conquest: '3 vs 3 vs 3, six sectors' };
    this.set(
      `<div class="panel card">
        <h2 class="title">Pick a map and a mode</h2>
        <div class="map-cards" role="group" aria-label="Map">${MAP_ORDER.map((id) => `<button data-map="${id}" aria-pressed="${id === this.map}"><b>${MAPS[id].name}</b><span>${esc(MAPS[id].blurb)}</span></button>`).join('')}</div>
        <div class="mode-cards" role="group" aria-label="Game mode">${MODE_ORDER.map((id) => `<button data-m="${id}" aria-pressed="${id === this.mode}"><b>${MODES[id].short}</b><span>${esc(MODES[id].blurb)}</span><em>${tag[id]}</em></button>`).join('')}</div>
        <p class="label">Difficulty</p>
        <div class="seg" role="group" aria-label="Difficulty">${opts
          .map(([k, n, d]) => `<button data-d="${k}" aria-pressed="${k === this.difficulty}"><b>${n}</b><span>${d}</span></button>`)
          .join('')}</div>
        <div class="loadout-bar">${lo()}<button class="btn ghost small" data-a="loadout">Change loadout</button></div>
        <div class="actions"><button class="btn primary small" data-a="go">${this.map === cur ? 'Start match' : 'Load this map'}</button><button class="btn ghost small" data-a="back">Back</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.root.querySelectorAll<HTMLButtonElement>('[data-map]').forEach((b) =>
      b.addEventListener('click', () => {
        this.map = b.dataset.map as MapId;
        this.root.querySelectorAll('[data-map]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
        (this.root.querySelector('[data-a=go]') as HTMLElement).textContent = this.map === cur ? 'Start match' : 'Load this map';
      }),
    );
    this.on('[data-a=loadout]', () => this.collection('play'));
    this.root.querySelectorAll<HTMLButtonElement>('[data-m]').forEach((b) =>
      b.addEventListener('click', () => {
        this.mode = b.dataset.m as ModeId;
        this.root.querySelectorAll('[data-m]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      }),
    );
    this.root.querySelectorAll<HTMLButtonElement>('[data-d]').forEach((b) =>
      b.addEventListener('click', () => {
        this.difficulty = b.dataset.d as Difficulty;
        settings.set('difficulty', this.difficulty);
        this.root.querySelectorAll('[data-d]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
      }),
    );
    this.on('[data-a=go]', () => {
      if (this.map === cur) return this.cb.start(this.difficulty, this.mode);
      // maps are built when the page loads: save the choice, reload, and come straight back to this screen
      settings.set('map', this.map);
      try {
        sessionStorage.setItem('toybox-mayhem.resume', JSON.stringify({ mode: this.mode }));
      } catch {
        /* no session storage: the main menu shows instead */
      }
      this.set(`<div class="panel card" style="width:min(440px,92vw)"><h2 class="title">Loading ${esc(MAPS[this.map].name)}</h2><p class="lede">One moment.</p></div>`, 'panel-wrap dim');
      window.setTimeout(() => location.reload(), 60);
    });
    this.on('[data-a=back]', () => this.main());
  }

  // ------------------------------------------------------------------ weapon collection
  collection(back: ScreenName) {
    this.current = 'collection';
    this.back = back;
    this.set(
      `<div class="panel card">
        <div class="title-row"><h2 class="title">Loadout</h2><div class="wallet">${coin(progress.coins)}</div></div>
        <p class="lede">Pick two abilities, then the two blasters you spawn with and a scope for each.${back === 'pause' ? ' Changes apply the next time you respawn.' : ''}</p>
        <div class="abil-pick"></div>
        <div class="slots"></div>
        <div class="collection">
          <div class="wlist">${this.weaponListHtml()}</div>
          <div class="wview blister"><canvas></canvas><div class="info"></div></div>
        </div>
        <form class="redeem" autocomplete="off"><label><span>Have a code?</span><input name="code" maxlength="24" spellcheck="false" placeholder="Enter code"></label><button type="submit" class="btn ghost small">Redeem</button><em role="status"></em></form>
        <div class="actions"><button class="btn ghost small" data-a="back">Back</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.bindWeaponList();
    this.on('[data-a=back]', () => this.goBack());
    const redeem = this.root.querySelector('form.redeem') as HTMLFormElement;
    redeem.addEventListener('submit', (e) => {
      e.preventDefault();
      const input = redeem.elements.namedItem('code') as HTMLInputElement;
      const msg = progress.redeem(input.value);
      const out = redeem.querySelector('em') as HTMLElement;
      out.textContent = msg ?? "That code didn't work.";
      out.className = msg ? 'ok' : 'bad';
      if (!msg) return;
      input.value = '';
      this.audio.fanfare(true);
      const list = this.root.querySelector('.wlist') as HTMLElement | null;
      if (list) {
        list.innerHTML = this.weaponListHtml();
        this.bindWeaponList();
      }
      this.showWeapon(false);
    });
    this.startPreview(this.root.querySelector('canvas')!);
    this.selectedWeapon = loadout.primary;
    this.root.querySelectorAll('[data-w]').forEach((x) => x.setAttribute('aria-pressed', String((x as HTMLElement).dataset.w === this.selectedWeapon)));
    this.showSlots();
    this.showAbilities();
    this.showWeapon();
  }

  /** Two ability slots (Ability 1 / Ability 2) and the five abilities to put in them. */
  private showAbilities() {
    const el = this.root.querySelector('.abil-pick') as HTMLElement | null;
    if (!el) return;
    const cur = loadout.abilities;
    const slot = (i: 0 | 1) =>
      `<button class="abil-slot" data-abslot="${i}" aria-pressed="${this.abilSlot === i}"><em>Ability ${i + 1} <kbd>${esc(actionName(i ? 'ability2' : 'ability1'))}</kbd></em><b>${ABILITIES[cur[i]].name}</b></button>`;
    el.innerHTML = `<div class="lbl">Abilities <small>pick 2 of 5: choose a slot, then an ability</small></div>
      <div class="abil-slots">${slot(0)}${slot(1)}</div>
      <div class="abil-chips">${ABILITY_ORDER.map((id) => {
        const on = cur.indexOf(id);
        return `<button data-ab="${id}" aria-pressed="${on >= 0}"><b>${ABILITIES[id].name}${on >= 0 ? ` <i>${on + 1}</i>` : ''}</b><span>${esc(ABILITY_INFO[id].desc)}</span></button>`;
      }).join('')}</div>`;
    el.querySelectorAll<HTMLButtonElement>('[data-abslot]').forEach((b) =>
      b.addEventListener('click', () => {
        this.abilSlot = Number(b.dataset.abslot) as 0 | 1;
        this.showAbilities();
        (this.root.querySelector(`[data-abslot="${this.abilSlot}"]`) as HTMLElement)?.focus();
      }),
    );
    el.querySelectorAll<HTMLButtonElement>('[data-ab]').forEach((b) =>
      b.addEventListener('click', () => {
        const id = b.dataset.ab as AbilityId;
        if (loadout.abilities[this.abilSlot] === id) return;
        loadout.setAbility(this.abilSlot, id);
        // the next pick fills the other slot, so two clicks set both
        this.abilSlot = this.abilSlot ? 0 : 1;
        this.showAbilities();
        (this.root.querySelector(`[data-ab="${id}"]`) as HTMLElement)?.focus();
      }),
    );
  }

  private bindWeaponList() {
    this.root.querySelectorAll<HTMLButtonElement>('[data-w]').forEach((b) =>
      b.addEventListener('click', () => {
        this.selectedWeapon = b.dataset.w as WeaponId;
        this.root.querySelectorAll('[data-w]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
        this.showWeapon();
      }),
    );
  }

  private weaponListHtml() {
    return WEAPON_ORDER.map((id) => {
      const c = WEAPONS[id].colors.main === '#1d1d1f' || WEAPONS[id].colors.main === '#f2f7ff' ? WEAPONS[id].colors.accent : WEAPONS[id].colors.main;
      const owned = progress.owns(id);
      return `<button data-w="${id}" class="${owned ? '' : 'locked'}" style="--c:${c}" aria-pressed="${id === this.selectedWeapon}">${WEAPONS[id].name}${owned ? '' : `<small class="price">${coin(progress.price(id))}</small>`}</button>`;
    }).join('');
  }

  private showSlots() {
    const el = this.root.querySelector('.slots') as HTMLElement | null;
    if (!el) return;
    const card = (label: string, id: WeaponId) => {
      const w = WEAPONS[id];
      const c = w.colors.main === '#1d1d1f' || w.colors.main === '#f2f7ff' ? w.colors.accent : w.colors.main;
      return `<div style="--c:${c}"><em>${label}</em><b>${w.name}</b><small>${SCOPES[loadout.scope(id)].name}</small></div>`;
    };
    el.innerHTML = card('Primary', loadout.primary) + card('Secondary', loadout.secondary);
  }

  private showWeapon(rebuildModel = true) {
    const w = WEAPONS[this.selectedWeapon];
    const info = this.root.querySelector('.info') as HTMLElement;
    const owned = progress.owns(w.id);
    const tier = tierOf(w.id);
    const c = w.colors.main === '#1d1d1f' || w.colors.main === '#f2f7ff' ? w.colors.accent : w.colors.main;
    const dps = w.burst ? (w.damage * w.burst.count) / (w.burst.count * w.burst.gap + 60 / w.rpm) : (w.damage * w.pellets * w.rpm) / 60;
    const meters: [string, number, string][] = [
      ['Damage', Math.min(1, (w.damage * w.pellets) / 81), w.pellets > 1 ? `${w.pellets}×${w.damage}` : w.charge ? `0-${w.damage}` : String(w.damage)],
      ['Fire rate', Math.min(1, w.rpm / 1050), w.burst ? `${w.burst.count}-shot burst` : `${w.rpm} rpm`],
      ['Damage/sec', Math.min(1, dps / 200), String(Math.round(dps))],
      ['Range', Math.min(1, w.effectiveRange / 80), w.explosion ? 'arc' : w.charge ? 'arc, no falloff' : `${w.effectiveRange} m`],
      ['Magazine', Math.min(1, w.magSize / 50), w.energy ? `${w.magSize} energy` : String(w.magSize)],
      ['Reload', w.energy ? 1 : Math.max(0.05, 1 - w.reloadTime / 3.4), w.energy ? 'recharges' : w.reloadPerShell ? `${w.reloadPerShell}s/shell` : `${w.reloadTime}s`],
    ];
    info.innerHTML = `<h3 style="color:${c}">${w.name}</h3><div class="cat">${w.category} <span class="tier" style="--t:${TIER_COLORS[tier]}">${tier}</span>${owned ? '' : ' <span class="tier locked-tag">Locked</span>'}</div><div>${esc(w.blurb)}</div>
      <div class="stats" style="--c:${c}">${meters.map(([n, v, t]) => `<span>${n}</span><div class="meter"><i style="width:${(v * 100).toFixed(0)}%"></i></div><span>${t}</span>`).join('')}</div>
      <div class="scope-pick"><div class="lbl">Scope</div><div class="chips">${WEAPON_SCOPES[w.id].map((s) => `<button data-s="${s}" aria-pressed="${s === loadout.scope(w.id)}">${SCOPES[s].name}</button>`).join('')}</div><p>${esc(SCOPES[loadout.scope(w.id)].blurb)} Zoom ${(SCOPES[loadout.scope(w.id)].zoom ?? w.adsZoom).toFixed(2).replace(/0$/, '')}x.</p></div>
      ${owned
        ? `<div class="equip-row"><button class="btn small ${loadout.primary === w.id ? 'primary' : ''}" data-eq="0">${loadout.primary === w.id ? 'Equipped as primary' : 'Equip as primary'}</button><button class="btn small ${loadout.secondary === w.id ? 'primary' : ''}" data-eq="1">${loadout.secondary === w.id ? 'Equipped as secondary' : 'Equip as secondary'}</button></div>`
        : `<div class="equip-row unlock"><button class="btn small primary" data-unlock ${progress.canAfford(w.id) ? '' : 'disabled'}>Unlock for ${coin(progress.price(w.id))}</button><span class="need">${progress.canAfford(w.id) ? '' : `You have ${progress.coins.toLocaleString()}. Earn ${(progress.price(w.id) - progress.coins).toLocaleString()} more by finishing matches.`}</span></div>`}`;
    info.querySelector('[data-unlock]')?.addEventListener('click', () => {
      if (!progress.unlock(w.id)) return;
      this.audio.fanfare(true);
      const list = this.root.querySelector('.wlist') as HTMLElement | null;
      if (list) {
        list.innerHTML = this.weaponListHtml();
        this.bindWeaponList();
      }
      const wallet = this.root.querySelector('.wallet') as HTMLElement | null;
      if (wallet) wallet.innerHTML = coin(progress.coins);
      this.showWeapon(false);
      (this.root.querySelector('[data-eq="0"]') as HTMLElement | null)?.focus();
    });
    info.querySelectorAll<HTMLButtonElement>('[data-s]').forEach((b) =>
      b.addEventListener('click', () => {
        loadout.setScope(w.id, b.dataset.s as ScopeId);
        this.showSlots();
        this.showWeapon(false);
      }),
    );
    info.querySelectorAll<HTMLButtonElement>('[data-eq]').forEach((b) =>
      b.addEventListener('click', () => {
        loadout.set(Number(b.dataset.eq) as 0 | 1, w.id);
        this.showSlots();
        this.showWeapon(false);
      }),
    );
    if (!rebuildModel) return;
    if (this.preview) {
      if (this.preview.model) this.preview.scene.remove(this.preview.model);
      const m = buildWeaponModel(this.selectedWeapon);
      const box = new THREE.Box3().setFromObject(m);
      const size = box.getSize(new THREE.Vector3()).length();
      m.scale.setScalar(1.6 / size);
      const center = box.getCenter(new THREE.Vector3()).multiplyScalar(1.6 / size);
      const holder = new THREE.Group();
      m.position.sub(center);
      holder.add(m);
      this.preview.model = holder;
      this.preview.scene.add(holder);
    }
  }

  private startPreview(canvas: HTMLCanvasElement) {
    try {
      const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
      renderer.setPixelRatio(Math.min(2, window.devicePixelRatio));
      renderer.toneMapping = THREE.ACESFilmicToneMapping;
      renderer.outputColorSpace = THREE.SRGBColorSpace;
      const scene = new THREE.Scene();
      const pm = new THREE.PMREMGenerator(renderer);
      scene.environment = pm.fromScene(new RoomEnvironment(), 0.04).texture;
      pm.dispose();
      scene.add(new THREE.HemisphereLight('#fff1dc', '#5a4a80', 1.2));
      const key = new THREE.DirectionalLight('#ffe2b8', 2.5);
      key.position.set(2, 3, 2);
      scene.add(key);
      const cam = new THREE.PerspectiveCamera(32, 2, 0.1, 50);
      cam.position.set(0, 0.35, 2.9);
      cam.lookAt(0, 0, 0);
      const p = { renderer, scene, cam, model: null as THREE.Object3D | null, raf: 0 };
      this.preview = p;
      const tick = (t: number) => {
        const w = canvas.clientWidth, h = canvas.clientHeight;
        if (canvas.width !== Math.floor(w * renderer.getPixelRatio()) || canvas.height !== Math.floor(h * renderer.getPixelRatio())) {
          renderer.setSize(w, h, false);
          cam.aspect = w / Math.max(1, h);
          cam.updateProjectionMatrix();
        }
        if (p.model) {
          p.model.rotation.y = Math.PI / 2 + Math.sin(t * 0.0006) * 0.7;
          p.model.rotation.x = Math.sin(t * 0.0008) * 0.12;
        }
        renderer.render(scene, cam);
        p.raf = requestAnimationFrame(tick);
      };
      p.raf = requestAnimationFrame(tick);
    } catch {
      this.preview = null;
    }
  }
  private stopPreview() {
    if (!this.preview) return;
    cancelAnimationFrame(this.preview.raf);
    this.preview.renderer.dispose();
    this.preview.renderer.forceContextLoss();
    this.preview = null;
  }

  // ------------------------------------------------------------------ settings
  settings(back: ScreenName) {
    this.current = 'settings';
    this.back = back;
    const s = settings.data;
    const range = (k: keyof Settings, label: string, min: number, max: number, step: number, fmt: (v: number) => string) =>
      `<label class="row"><span>${label}</span><input type="range" data-k="${k}" min="${min}" max="${max}" step="${step}" value="${s[k]}"><output data-o="${k}">${fmt(s[k] as number)}</output></label>`;
    const check = (k: keyof Settings, label: string) => `<label class="row check"><span>${label}</span><input type="checkbox" data-k="${k}" ${s[k] ? 'checked' : ''}></label>`;
    const colors = ['#ffffff', '#7dff6b', '#ffd23f', '#5ff4ff', '#ff6bd5', '#ff4d4d'];
    this.set(
      `<div class="panel card">
        <h2 class="title">Settings</h2>
        <p class="lede">Changes apply right away and are saved on this computer.</p>
        <div class="settings-grid">
          <div class="group blister"><h3>Mouse</h3>
            ${range('sensitivity', 'Sensitivity', 0.1, 3, 0.05, (v) => v.toFixed(2))}
            ${range('adsSensitivity', 'Aiming sensitivity', 0.3, 1.5, 0.05, (v) => v.toFixed(2))}
            ${check('invertY', 'Invert Y axis')}
          </div>
          <div class="group blister"><h3>Controller</h3>
            ${range('padSensitivity', 'Look sensitivity', 0.3, 2.5, 0.05, (v) => v.toFixed(2))}
            ${check('padAimAssist', 'Aim assist')}
            ${check('padVibration', 'Vibration')}
          </div>
          <div class="group blister"><h3>Video</h3>
            ${range('fov', 'Field of view', 70, 110, 1, (v) => `${v}°`)}
            <label class="row wide"><span>Graphics quality</span><select data-k="quality">${(['low', 'medium', 'high'] as Quality[]).map((q) => `<option value="${q}" ${q === s.quality ? 'selected' : ''}>${q[0].toUpperCase() + q.slice(1)}</option>`).join('')}</select></label>
            <label class="row check"><span>Fullscreen</span><input type="checkbox" data-fs ${document.fullscreenElement ? 'checked' : ''}></label>
            ${check('motionBlur', 'Motion blur')}
            ${check('showFps', 'Show frame rate')}
          </div>
          <div class="group blister"><h3>Comfort</h3>
            ${check('reducedMotion', 'Reduced motion')}
            ${check('cameraShake', 'Camera shake')}
            ${check('enemyOutlines', 'Outline enemy toys')}
            ${check('damageNumbers', 'Floating damage numbers')}
          </div>
          <div class="group blister"><h3>Audio</h3>
            ${range('masterVolume', 'Master', 0, 1, 0.01, (v) => `${Math.round(v * 100)}`)}
            ${range('musicVolume', 'Music', 0, 1, 0.01, (v) => `${Math.round(v * 100)}`)}
            ${range('sfxVolume', 'Effects', 0, 1, 0.01, (v) => `${Math.round(v * 100)}`)}
            ${range('ambienceVolume', 'Ambience', 0, 1, 0.01, (v) => `${Math.round(v * 100)}`)}
          </div>
          <div class="group blister"><h3>Crosshair</h3>
            <div class="row"><span>Color</span><div class="swatches">${colors.map((c) => `<button data-color="${c}" style="background:${c}" aria-label="Crosshair color ${c}" aria-pressed="${c === s.crosshairColor}"></button>`).join('')}</div></div>
            ${range('crosshairSize', 'Size', 0.6, 1.8, 0.05, (v) => v.toFixed(2))}
            ${check('crosshairDot', 'Center dot')}
          </div>
          <div class="group blister"><h3>Player</h3>
            <label class="row wide"><span>Name</span><input type="text" maxlength="14" data-k="playerName" value="${esc(s.playerName)}"></label>
          </div>
        </div>
        <div class="actions"><button class="btn ghost small" data-a="back">Back</button><button class="btn ghost small" data-a="reset">Reset to defaults</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.root.querySelectorAll<HTMLInputElement | HTMLSelectElement>('[data-k]').forEach((el) => {
      const k = el.dataset.k as keyof Settings;
      const ev = el instanceof HTMLInputElement && el.type === 'range' ? 'input' : 'change';
      el.addEventListener(ev, () => {
        let v: unknown;
        if (el instanceof HTMLInputElement && el.type === 'checkbox') v = el.checked;
        else if (el instanceof HTMLInputElement && el.type === 'range') v = parseFloat(el.value);
        else v = el.value;
        if (k === 'playerName') v = String(v).trim() || 'You';
        settings.set(k, v as never);
        const o = this.root.querySelector(`[data-o="${k}"]`);
        if (o && typeof v === 'number') o.textContent = k === 'fov' ? `${v}°` : k.endsWith('Volume') ? String(Math.round(v * 100)) : v.toFixed(2);
        this.cb.settingsChanged(settings.data, k);
      });
    });
    this.root.querySelectorAll<HTMLButtonElement>('[data-color]').forEach((b) =>
      b.addEventListener('click', () => {
        settings.set('crosshairColor', b.dataset.color!);
        this.root.querySelectorAll('[data-color]').forEach((x) => x.setAttribute('aria-pressed', String(x === b)));
        this.cb.settingsChanged(settings.data, 'crosshairColor');
      }),
    );
    this.root.querySelector<HTMLInputElement>('[data-fs]')?.addEventListener('change', (e) => {
      const on = (e.target as HTMLInputElement).checked;
      if (on) document.documentElement.requestFullscreen?.().then(() => (navigator as any).keyboard?.lock?.().catch(() => {})).catch(() => {});
      else if (document.fullscreenElement) document.exitFullscreen();
    });
    this.on('[data-a=back]', () => this.goBack());
    this.on('[data-a=reset]', () => {
      settings.reset();
      for (const k of Object.keys(settings.data) as (keyof Settings)[]) this.cb.settingsChanged(settings.data, k);
      this.settings(this.back);
    });
  }

  controls(back: ScreenName) {
    this.current = 'controls';
    this.back = back;
    this.input?.cancelCapture();
    const ab = loadout.abilities;
    const label = (id: Action, l: string) => (id === 'ability1' ? `Ability 1 (${ABILITIES[ab[0]].name})` : id === 'ability2' ? `Ability 2 (${ABILITIES[ab[1]].name})` : l);
    const rows = ACTIONS.map((a) => {
      const [k1, k2] = binds.kb[a.id];
      const cell = (slot: '0' | '1' | 'pad', text: string) => `<button class="bind${text ? '' : ' empty'}" data-act="${a.id}" data-slot="${slot}">${esc(text || '—')}</button>`;
      return `<div class="bind-row"><span>${esc(label(a.id, a.label))}</span>${cell('0', keyLabel(k1))}${cell('1', keyLabel(k2))}${a.stick ? `<span class="bind fixed">${a.stick}</span>` : cell('pad', padLabel(binds.pad[a.id]))}</div>`;
    }).join('');
    this.set(
      `<div class="panel card">
        <h2 class="title">Controls</h2>
        <p class="lede">Click a box (or highlight it and press A), then press the key, mouse button or controller button you want. Esc cancels, Backspace clears the box. If another action already used it, the two swap.</p>
        <div class="binds">
          <div class="bind-row head"><span>Action</span><span>Key</span><span>Second key</span><span>Controller</span></div>
          ${rows}
        </div>
        <p class="note">Always the same: Esc or the controller's Menu button pauses, the mouse wheel switches weapons, the mouse or right stick looks. Choose which two abilities you bring on the Loadout screen. Reload and revive can share a controller button: next to a downed teammate it revives, otherwise it reloads.</p>
        <p class="note">Any standard controller works in Chrome or Edge (Xbox, PlayStation, Switch Pro...). On PlayStation pads A = Cross, B = Circle, X = Square, Y = Triangle, LB/RB = L1/R1, LT/RT = L2/R2. Look speed, aim assist and vibration are in Settings. Sprint into crouch to slide.</p>
        <div class="actions"><button class="btn ghost small" data-a="back">Back</button><button class="btn ghost small" data-a="resetbinds">Reset controls</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.root.querySelectorAll<HTMLButtonElement>('button.bind').forEach((b) => b.addEventListener('click', () => this.listenFor(b)));
    this.on('[data-a=back]', () => {
      this.input?.cancelCapture();
      this.goBack();
    });
    this.on('[data-a=resetbinds]', () => {
      binds.reset();
      this.controls(this.back);
    });
  }

  /** Waits for the next key / mouse button / controller button and binds it to the clicked box. */
  private listenFor(b: HTMLButtonElement) {
    const input = this.input;
    if (!input) return;
    const act = b.dataset.act as Action;
    const slot = b.dataset.slot!;
    this.root.querySelectorAll('.bind.listening').forEach((x) => x.classList.remove('listening'));
    b.classList.add('listening');
    b.textContent = slot === 'pad' ? 'Press a button…' : 'Press a key…';
    const refresh = () => {
      const panel0 = this.root.querySelector('.panel') as HTMLElement | null;
      const scroll = panel0?.scrollTop ?? 0;
      this.controls(this.back);
      const panel = this.root.querySelector('.panel') as HTMLElement | null;
      if (panel) panel.scrollTop = scroll;
      (this.root.querySelector(`.bind[data-act="${act}"][data-slot="${slot}"]`) as HTMLElement | null)?.focus({ preventScroll: true });
    };
    input.capture((c) => {
      if (c) {
        if (slot === 'pad') {
          if (c.kind === 'pad') binds.setPad(act, c.btn);
          else if (c.code === 'Backspace' || c.code === 'Delete') binds.setPad(act, -1);
          else return this.listenFor(b); // a keyboard key on a controller box: keep waiting
        } else if (c.kind === 'kb') {
          const clear = c.code === 'Backspace' || c.code === 'Delete';
          binds.setKb(act, slot === '1' ? 1 : 0, clear ? '' : c.code);
        }
      }
      this.audio.uiClick();
      refresh();
    });
  }

  credits() {
    this.current = 'credits';
    this.set(
      `<div class="panel card">
        <h2 class="title">Credits</h2>
        <p class="lede">Toybox Mayhem is an original game. Every toy, room prop, weapon model, texture, sound effect and music track is generated in code at runtime, so there are no outside art or audio files.</p>
        <div class="keys">
          <div><span>Rendering</span><span>three.js</span></div>
          <div><span>Physics and character movement</span><span>Rapier</span></div>
          <div><span>Build tool</span><span>Vite + TypeScript</span></div>
          <div><span>Sound and music</span><span>Web Audio synthesis</span></div>
          <div><span>Fonts</span><span>Luckiest Guy, Baloo 2 (OFL)</span></div>
        </div>
        <div class="actions"><button class="btn ghost small" data-a="back">Back</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.on('[data-a=back]', () => this.main());
  }

  private goBack() {
    if (this.back === 'pause') this.pause();
    else if (this.back === 'play') this.play();
    else this.main();
  }

  // ------------------------------------------------------------------ in-game
  pause() {
    this.current = 'pause';
    this.set(
      `<div class="panel card" style="width:min(440px,92vw)">
        <h2 class="title">Paused</h2>
        <button class="btn primary" data-a="resume">Resume</button>
        <button class="btn" data-a="loadout">Loadout and unlocks</button>
        <button class="btn" data-a="settings">Settings</button>
        <button class="btn" data-a="controls">Controls</button>
        <button class="btn" data-a="quit">Quit to main menu</button>
      </div>`,
      'panel-wrap dim',
    );
    this.on('[data-a=resume]', () => this.cb.resume());
    this.on('[data-a=loadout]', () => this.collection('pause'));
    this.on('[data-a=settings]', () => this.settings('pause'));
    this.on('[data-a=controls]', () => this.controls('pause'));
    this.on('[data-a=quit]', () => this.cb.quit());
    (this.root.querySelector('[data-a=resume]') as HTMLElement)?.focus();
  }

  results(match: Match, actors: Actor[], me: Actor, boardHtml: string, reward?: Reward) {
    this.current = 'results';
    const st = match.standings(actors);
    const place = st.indexOf(me) + 1;
    const won = match.isWinner(me);
    const acc = me.shotsFired ? Math.round((me.shotsHit / me.shotsFired) * 100) : 0;
    const ord = (n: number) => `${n}${n === 1 ? 'st' : n === 2 ? 'nd' : n === 3 ? 'rd' : 'th'}`;
    let title: string, line: string;
    if (match.teams) {
      const wt = match.winnerTeam;
      const s = match.teamScores.map((x) => Math.floor(x));
      title = wt === DRAW ? 'It’s a draw!' : won ? 'Your team wins!' : `Team ${TEAMS[wt].name} wins`;
      const conq = match.mode.id === 'conquest';
      const why =
        match.endReason === 'score' && wt >= 0
          ? conq ? `Team ${TEAMS[wt].name} took control of ${match.killTarget} of the 6 sectors.` : `Team ${TEAMS[wt].name} reached ${match.killTarget}.`
          : 'Time ran out.';
      const mates = match.standings(actors.filter((a) => a.team === me.team));
      const finals = s.map((x, t) => `${TEAMS[t].name} ${x}${conq ? (x === 1 ? ' sector' : ' sectors') : ''}`).join(', ');
      line = `${why} Final score: ${finals}. You were ${ord(mates.indexOf(me) + 1)} on your team.`;
    } else {
      title = won ? 'You win the toy box!' : `${esc(match.winner?.name ?? 'Nobody')} wins`;
      line = `${match.endReason === 'score' ? `${esc(match.winner?.name ?? 'Nobody')} reached ${match.killTarget} pops.` : 'Time ran out.'} You finished ${ord(place)} of ${actors.length}.`;
    }
    this.set(
      `<div class="panel card results">
        <p class="winner">${title}</p>
        <p class="place">${line}</p>
        ${reward ? `<div class="reward blister"><h3>+${reward.total.toLocaleString()} coins</h3><ul>${reward.lines.map(([t, n]) => `<li><span>${esc(t)}</span><b>${n >= 0 ? '+' : ''}${n}</b></li>`).join('')}</ul><p>You have ${coin(reward.coinsAfter)}.${reward.affordable.length ? ` You can unlock <b>${reward.affordable.map((id) => WEAPONS[id].name).join(', ')}</b> now in Loadout.` : ''}</p></div>` : ''}
        ${boardHtml}
        <div class="mystats">
          <div class="blister"><b>${me.kills}</b><span>Pops</span></div>
          <div class="blister"><b>${me.deaths}</b><span>Times popped</span></div>
          <div class="blister"><b>${acc}%</b><span>Accuracy</span></div>
          <div class="blister"><b>${me.headshots}</b><span>Headshot pops</span></div>
          <div class="blister"><b>${me.bestStreak}</b><span>Best streak</span></div>
          <div class="blister"><b>${Math.round(me.damageDealt)}</b><span>Damage dealt</span></div>
        </div>
        <div class="actions"><button class="btn primary small" data-a="again">Play again</button><button class="btn ghost small" data-a="loadout">Loadout and unlocks</button><button class="btn ghost small" data-a="menu">Main menu</button></div>
      </div>`,
      'panel-wrap dim',
    );
    this.on('[data-a=again]', () => this.cb.playAgain());
    this.on('[data-a=menu]', () => this.cb.quit());
    this.on('[data-a=loadout]', () => {
      this.cb.quit();
      this.collection('main');
    });
  }

  /** Controller B: the screen's Back button, or resume from the pause menu. Returns true if it did something. */
  padBack(): boolean {
    if (this.current === 'pause') {
      this.cb.resume();
      return true;
    }
    const b = this.root.querySelector<HTMLElement>('[data-a=back]');
    if (!b) return false;
    b.click();
    return true;
  }
  /** Controller Start/Menu: resumes from the pause menu. */
  padStart(): boolean {
    if (this.current !== 'pause') return false;
    this.cb.resume();
    return true;
  }
  hover() {
    this.audio.uiHover();
  }

  resumeHint(show: boolean, onClick: () => void) {
    let el = document.getElementById('resume-hint');
    if (!show) {
      el?.remove();
      return;
    }
    if (el) return;
    el = document.createElement('div');
    el.id = 'resume-hint';
    el.className = 'resume-hint card';
    el.innerHTML = '<b>Click to keep playing</b>The browser needs a click to grab the mouse again.';
    el.addEventListener('click', () => {
      el!.remove();
      onClick();
    });
    document.body.appendChild(el);
  }
}

import * as THREE from 'three';
import { Renderer } from '../render/Renderer';
import { Physics } from '../physics/Physics';
import { ArenaInfo, Zone } from '../world/Arena';
import type { AmbientLike } from '../world/YardAmbient';
import { MapDef, selectedMap } from '../world/maps';
import { loadout } from '../weapons/loadout';
import { COMBAT } from '../weapons/weaponConfig';
import { NavGraph } from '../nav/NavGraph';
import { Effects } from '../fx/Effects';
import { audio } from '../audio/Audio';
import { Emitter } from './events';
import { Combat, GameEvents } from '../combat/Combat';
import { Actor, MoveEvents } from '../entities/Actor';
import { Player } from '../entities/Player';
import { Bot, PERSONALITIES, pickBotLoadout, pickBotAbilities } from '../entities/Bot';
import { CHARACTERS, BOT_ROSTER, SHELF_ROSTER, ALL_BOTS, ToyRig, CharacterId } from '../entities/ToyModels';
import { Viewmodel } from '../weapons/Viewmodel';
import { Pickups, PICKUP_INFO, PickupKind } from '../match/Pickups';
import { Match } from '../match/Match';
import { HUD } from '../ui/HUD';
import { Menus } from '../ui/Menus';
import { Input, PAD, actionName } from './Input';
import { PadNav } from '../ui/PadNav';
import { accounts } from './Accounts';
import { progress } from './Progress';
import { NetClient } from '../net/NetClient';
import { settings, Difficulty, Settings } from './Settings';
import { WEAPONS, WeaponId } from '../weapons/weaponConfig';
import { clamp } from './math';
import { MODES, ModeId, TEAMS, DRAW, CONQUEST_HOMES, useMapSites } from '../match/modes';
import { HillZone } from '../world/HillZone';
import { Elevators } from '../world/Elevators';
import { SectorZones } from '../world/SectorZones';
import { Ropes } from '../fx/Ropes';
import { SectorEvent } from '../match/Match';

type GameState = 'menu' | 'playing' | 'paused' | 'results';

export interface LoadProgress {
  (step: string, frac: number): void;
}

/** Owns every system and runs the main loop. One instance for the lifetime of the page. */
export class Game {
  state: GameState = 'menu';
  r!: Renderer;
  phys!: Physics;
  arena!: ArenaInfo;
  ambient!: AmbientLike;
  map!: MapDef;
  nav!: NavGraph;
  fx!: Effects;
  events = new Emitter<GameEvents>();
  combat!: Combat;
  pickups!: Pickups;
  match!: Match;
  hud!: HUD;
  menus!: Menus;
  input!: Input;
  vm!: Viewmodel;
  player: Player | null = null;
  actors: Actor[] = [];
  bots: Bot[] = [];
  private botByActor = new Map<Actor, Bot>();
  spawnPoints: THREE.Vector3[] = [];
  time = 0; // simulation clock (seconds, affected by slow-mo)
  private last = 0;
  private timeScale = 1;
  private slowmoT = 0;
  private menuT = 0;
  private dashFrom = new Map<Actor, THREE.Vector3>();
  private lastZone = '';
  private raf = 0;
  private matchSeconds = 0;
  private difficulty: Difficulty = 'normal';
  mode: ModeId = 'ffa';
  hillZone!: HillZone;
  sectorZones!: SectorZones;
  elevators!: Elevators;
  ropes!: Ropes;
  /** FFA newcomers start (and respawn) up on the high shelves */
  shelfSpawns: THREE.Vector3[] = [];
  private shelfStarters = new Set<Actor>();
  /** conquest: which sector each bot is sent to */
  private assignment = new Map<Actor, number>();
  private directorAt = 0;
  private lastHillNote = -10;
  private moveEvents!: MoveEvents;
  private lockWatch = 0;
  private padNav!: PadNav;
  /**
   * Multiplayer groundwork. Not used by the menus yet; from the browser console:
   *   __toybox.net.connect('ws://localhost:8787', 'Me')   (after `npm run server`)
   * While connected, your position/aim/health is sent 20 times a second and other players arrive in net.remotes.
   */
  net = new NetClient();
  private netSendAt = 0;
  /** test hooks: `manual` stops the real-time loop from simulating (it still renders) so tests can drive time */
  debug = { invulnerable: false, manual: false };

  async init(canvas: HTMLCanvasElement, uiRoot: HTMLElement, progress: LoadProgress) {
    progress('Unboxing the renderer', 0.05);
    this.r = new Renderer(canvas);
    this.input = new Input(canvas);
    progress('Loading physics', 0.12);
    this.phys = await Physics.create();
    await tick();
    this.map = selectedMap();
    useMapSites(this.map.hillSites, this.map.sectors, this.map.homes);
    progress(this.map.loading, 0.25);
    this.arena = this.map.build(this.r.scene, this.phys);
    const sky = this.map.sky;
    this.r.scene.background = new THREE.Color(sky.background);
    this.r.scene.fog = new THREE.Fog(sky.fog[0], sky.fog[1], sky.fog[2]);
    this.r.scene.environmentIntensity = sky.env;
    this.r.renderer.toneMappingExposure = sky.exposure;
    this.r.sun = this.arena.sun;
    this.r.pointLights = this.arena.pointLights;
    await tick();
    progress('Teaching toys to walk', 0.5);
    this.nav = new NavGraph(this.phys);
    this.nav.build(this.arena.bounds);
    // regular spawns stay below the shelf; the shelf has its own pool
    const hy = this.map.highY;
    this.spawnPoints = this.nav.spawnPoints(22, (n) => n.open >= 6 && n.pos.y < hy - 1);
    this.shelfSpawns = this.nav.spawnPoints(10, (n) => n.pos.y > hy && n.open >= 3);
    await tick();
    progress('Filling the toy box', 0.65);
    this.fx = new Effects(this.r.scene);
    this.fx.setFloorProbe((p) => {
      const d = this.phys.rayDist(p, new THREE.Vector3(0, -1, 0), 40, true);
      return d === Infinity ? 0 : p.y - d;
    });
    this.ambient = this.map.ambient(this.r.scene, this.arena, this.phys, this.fx, audio);
    this.elevators = new Elevators(this.r.scene, this.phys, audio, this.map.elevators.sites, this.map.elevators.topY);
    this.phys.refreshQueries();
    const links = this.elevators.linkNav(this.nav);
    if (links < this.map.elevators.sites.length) console.warn(`[nav] only ${links}/${this.map.elevators.sites.length} elevators linked`);
    this.combat = new Combat(this.r.scene, this.phys, this.fx, audio, this.events, () => this.actors, this.arena.looseBricks);
    // weapons come from the loadout menu now, so no weapon pedestals
    this.pickups = new Pickups(this.r.scene, this.arena.pickupSpots, [], this.fx, audio, this.events);
    this.match = new Match(this.phys, this.spawnPoints);
    this.hillZone = new HillZone(this.r.scene);
    this.sectorZones = new SectorZones(this.r.scene);
    this.ropes = new Ropes(this.r.scene);
    this.vm = new Viewmodel(this.r.vmScene);
    audio.occlusion = (p) => !this.phys.los(this.r.camera.position, p, true);
    this.hud = new HUD(uiRoot);
    this.hud.show(false);
    this.menus = new Menus(uiRoot, {
      start: (d, m) => this.startMatch(d, m),
      resume: () => this.resume(),
      quit: () => this.quitToMenu(),
      playAgain: () => this.startMatch(this.difficulty, this.mode),
      settingsChanged: (s, k) => this.applySettings(s, k),
    }, audio);
    this.registerEvents();
    this.applySettings(settings.data, 'quality');
    this.applySettings(settings.data, 'masterVolume');
    this.menus.input = this.input;
    this.padNav = new PadNav(this.input, () => [this.menus.root], {
      back: () => this.menus.padBack(),
      start: () => this.menus.padStart(),
      hover: () => this.menus.hover(),
    });
    this.input.onDeviceChange = (pad) => {
      if (pad) this.menus.resumeHint(false, () => {});
      else {
        this.padNav.clear();
        if (this.state === 'playing' && !this.input.locked) this.checkLockSoon();
      }
    };
    // switching account swaps settings, bindings, stats, loadout and coins: re-apply everything
    accounts.onSwitch(() => {
      for (const k of Object.keys(settings.data) as (keyof Settings)[]) this.applySettings(settings.data, k);
    });
    this.input.onLockChange = (locked) => {
      if (!locked && this.state === 'playing' && this.match.phase !== 'ended') this.pause();
    };
    window.addEventListener('resize', () => {
      this.r.resize();
      this.fx.setScale(this.r.renderer.domElement.height, this.r.camera.fov);
    });
    document.addEventListener('visibilitychange', () => {
      if (document.hidden && this.state === 'playing') this.pause();
    });
    progress('Warming up shaders', 0.82);
    this.menuCamera(0);
    this.r.setMenuBlur(true);
    try {
      this.r.renderer.compile(this.r.scene, this.r.camera);
      this.r.render();
    } catch (e) {
      console.warn('shader warmup failed', e);
    }
    progress('Ready', 1);
    this.menus.openAfterLoad();
    this.last = performance.now();
    this.raf = requestAnimationFrame(this.loop);
  }

  // ------------------------------------------------------------------ settings
  applySettings(s: Settings, k: keyof Settings) {
    if (k === 'quality') {
      this.r.setQuality(s.quality);
      audio.hrtf = s.quality !== 'low';
      this.fx.setScale(this.r.renderer.domElement.height, this.r.camera.fov);
    }
    if (k.endsWith('Volume')) audio.setVolumes(s.masterVolume, s.musicVolume, s.sfxVolume, s.ambienceVolume);
    if (k === 'motionBlur') this.r.setMotionBlur(s.motionBlur);
    if (k === 'enemyOutlines') this.refreshOutlines();
    if (k === 'reducedMotion') {
      this.combat.reducedMotion = s.reducedMotion;
      this.ambient.setReducedMotion(s.reducedMotion);
    }
    if (k === 'playerName' && this.player) this.player.actor.name = s.playerName;
    this.hud.applySettings();
  }

  // ------------------------------------------------------------------ events
  private registerEvents() {
    const ev = this.events;
    ev.on('damage', (d) => {
      const pl = this.player?.actor;
      if (d.target === pl && this.player) {
        if (this.debug.invulnerable) {
          d.target.health = 100;
          d.target.alive = true;
        }
        this.hud.damageFrom(d.attacker ? d.attacker.pos.clone() : d.point.clone().sub(d.fromDir));
        this.player.onDamaged(d.amount);
        audio.playerHurt(d.healthDmg <= 0);
      }
      if (d.attacker === pl && d.target !== pl) {
        const kind = d.head ? 'head' : d.shieldDmg > 0 && d.healthDmg <= 0 ? 'shield' : 'body';
        if (d.shieldDmg > 0 && d.healthDmg > 0) {
          this.hud.damageNumber(d.point.clone().add(new THREE.Vector3(0.25, 0.15, 0)), d.shieldDmg, 'shield');
          this.hud.damageNumber(d.point, d.healthDmg, d.head ? 'head' : 'body');
        } else this.hud.damageNumber(d.point, d.amount, kind);
        if (d.target.alive) this.hud.hit(kind);
        audio.hitmarker(d.head, kind === 'shield');
      }
      const bot = this.botByActor.get(d.target);
      if (bot) {
        bot.onDamaged(d.attacker, this.time);
        if (Math.random() < 0.5 && d.target.alive) audio.hurt(d.target.def.voicePitch, d.target.headPos());
      }
      if (d.shieldBroke) audio.shieldBreak(d.target.chestPos());
    });
    ev.on('kill', (k) => {
      const pl = this.player?.actor;
      this.match.onKill(k.killer, k.victim);
      const wname = k.weapon === 'block' ? 'FALLING BLOCK' : k.weapon === 'jab' ? 'SPRING PUNCH' : WEAPONS[k.weapon as WeaponId]?.name ?? '';
      this.hud.killFeed(k.killer, k.victim, wname, k.head, k.killer === pl || k.victim === pl);
      if (k.victim === pl && this.player) {
        this.player.onDeath(k.killer);
        this.hud.setDeath(k.killer ? k.killer.name : '', k.killer ? wname : k.weapon === 'block' ? 'a falling block' : 'your own crayon');
      }
      if (k.killer === pl && k.victim !== pl && pl) {
        this.hud.hit('kill');
        this.hud.eliminated(k.victim.name, pl.streak, k.head);
        audio.killConfirm(pl.streak);
        if (!settings.data.reducedMotion) {
          this.slowmoT = 0.22;
          this.timeScale = 0.35;
        }
      }
      // the body drops to the floor where it was popped (teammates can revive it there in team modes)
      const v = k.victim;
      const g = this.phys.rayDist(v.pos.clone().setY(v.pos.y + 0.6), new THREE.Vector3(0, -1, 0), 60, true);
      if (g !== Infinity) v.pos.y = v.pos.y + 0.6 - g;
      v.reviveT = 0;
      v.reviver = null;
      if (this.match.teams && v.team === pl?.team && v !== pl) this.hud.pickup(`${v.name} is down. Hold ${actionName('revive')} on them to revive`, TEAMS[v.team].light);
    });
    ev.on('shot', (s) => {
      const loud = s.weapon === 'crayonCannon' || s.weapon === 'thunderspring' || s.weapon === 'brickbreaker' ? 1.4 : s.weapon === 'starlightZapper' ? 0.8 : 1;
      for (const b of this.bots) b.onSound(s.pos, s.shooter, this.time, loud);
    });
    ev.on('explosion', (e) => {
      if (!this.player) return;
      const d = this.player.actor.pos.distanceTo(e.pos);
      if (d < 14) this.player.addTrauma(clamp(1 - d / 14, 0, 1) * 0.55);
    });
    ev.on('pickup', (p) => {
      if (p.actor !== this.player?.actor) return;
      const color = p.kind in PICKUP_INFO ? PICKUP_INFO[p.kind as PickupKind].color : '#ffd23f';
      this.hud.pickup(p.kind === 'weapon' ? `Picked up ${p.label}` : p.label, color);
      if (p.kind === 'weapon' || p.kind === 'ammo') this.player.equipCurrent();
    });
  }

  // ------------------------------------------------------------------ match lifecycle
  private clearMatch() {
    for (const a of this.actors) {
      if (a.model) {
        this.r.scene.remove(a.model.root);
        a.model.dispose();
      }
      a.dispose(this.phys);
    }
    for (const b of this.bots) b.dispose();
    this.actors = [];
    this.bots = [];
    this.botByActor.clear();
    this.player = null;
    this.dashFrom.clear();
    this.combat.clear();
    this.fx.clear();
    this.ambient.clearBlocks();
    this.pickups.reset();
    this.hud.reset();
    this.hillZone.hide();
    this.sectorZones.clear();
    this.ropes.clear();
    this.shelfStarters.clear();
    this.assignment.clear();
    for (const b of this.beacons.values()) {
      this.r.scene.remove(b);
      b.traverse((o) => (o as THREE.Mesh).geometry?.dispose());
    }
    this.beacons.clear();
  }

  startMatch(d: Difficulty, mode: ModeId = this.mode) {
    audio.init();
    this.difficulty = d;
    this.mode = mode;
    this.match.setMode(mode);
    const def = MODES[mode];
    const teamMode = def.teams;
    this.clearMatch();
    this.time = 0;
    this.matchSeconds = 0;
    // player
    const pdef = { ...CHARACTERS.player, name: settings.data.playerName || 'You' };
    const pa = new Actor(pdef, true, this.phys);
    pa.name = pdef.name;
    this.actors.push(pa);
    this.player = new Player(pa, this.r.camera, this.vm, {
      input: this.input,
      combat: this.combat,
      audio,
      fx: this.fx,
      phys: this.phys,
      nearbyPrompt: (a) => {
        const d = this.downedNear(a);
        if (!d) return null;
        return d.reviver === a && d.reviveT > 0 ? `Reviving ${d.name}  ${Math.round((d.reviveT / COMBAT.reviveTime) * 100)}%` : `Hold ${actionName('revive')} to revive ${d.name}`;
      },
      teammates: () => (pa.team >= 0 ? this.actors.filter((o) => o !== pa && o.alive && o.team === pa.team) : []),
      aimTargets: () => this.actors.filter((o) => o !== pa && o.alive && (pa.team < 0 || o.team !== pa.team)),
    });
    // bots
    const world = {
      nav: this.nav, phys: this.phys, combat: this.combat, audio, fx: this.fx,
      actors: () => this.actors,
      player: () => this.player?.actor ?? null,
      pickups: () => this.pickups.list(),
      spawnPoints: this.spawnPoints,
      zones: this.arena.zones,
      difficulty: d,
      listenerPos: this.r.camera.position,
      objective: (a: Actor) => {
        if (this.match.phase !== 'playing') return null;
        const h = this.match.hill;
        if (h) return { pos: h.pos, radius: h.site.radius, height: h.site.height };
        const si = this.assignment.get(a);
        if (si === undefined) return null;
        const s = this.match.sectors[si];
        return s ? { pos: s.pos, radius: s.def.radius, height: s.def.height } : null;
      },
      teamMode,
      mode,
      elevators: () => this.elevators.views(),
    };
    // roster: FFA = all fourteen; team modes = a random pick
    const roster = mode === 'ffa' ? [...ALL_BOTS] : [...ALL_BOTS].sort(() => Math.random() - 0.5).slice(0, def.botCount);
    for (const id of roster) {
      const def = CHARACTERS[id];
      const a = new Actor(def, false, this.phys);
      const rig = new ToyRig(def);
      a.model = rig;
      this.r.scene.add(rig.root);
      const bot = new Bot(a, PERSONALITIES[id as Exclude<CharacterId, 'player'>], world);
      a.abilities = pickBotAbilities(bot.personality);
      this.actors.push(a);
      this.bots.push(bot);
      this.botByActor.set(a, bot);
      if (mode === 'ffa' && SHELF_ROSTER.includes(id)) this.shelfStarters.add(a);
    }
    // teams: you are always on Sunrise; everyone else is dealt round the teams so sizes match
    if (teamMode) {
      pa.team = 0;
      const n = def.teamCount;
      const order = [...this.bots].sort(() => Math.random() - 0.5);
      // seat 0 is you, so the first bot goes to team 1, etc.
      order.forEach((b, i) => (b.actor.team = (i + 1) % n));
      for (const b of this.bots) b.actor.model!.setTeam(TEAMS[b.actor.team].color);
    }
    this.refreshOutlines();
    // spawn everyone
    this.match.reset(this.time);
    this.match.shelfSpawns = this.shelfSpawns;
    if (this.match.hill) this.hillZone.place(this.match.hill.pos, this.match.hill.site.radius, this.match.hill.site.height);
    this.sectorZones.build(this.match.sectors);
    this.directorAt = 0;
    if (mode === 'conquest') this.runDirector(true);
    for (const a of this.actors) {
      a.alive = false;
      a.respawnAt = -1;
      a.kills = a.deaths = a.streak = a.bestStreak = a.headshots = a.shotsFired = a.shotsHit = 0;
      a.damageDealt = 0;
      this.respawn(a, true);
    }
    this.moveEvents = {
      onJump: (a) => {
        if (a.isPlayer) audio.jump();
      },
      onLand: (a, s) => {
        if (a.isPlayer) {
          audio.land(a.groundMat, s);
          this.player?.onLand(s);
        } else if (a.pos.distanceTo(this.r.camera.position) < 20) audio.land(a.groundMat, s * 0.6, a.pos);
      },
      onSlide: (a) => {
        if (a.isPlayer) audio.slide();
      },
      onDash: (a, from) => {
        this.dashFrom.set(a, from.clone());
        audio.dash(a.isPlayer ? undefined : a.pos.clone());
      },
      onFootstep: (a) => {
        if (a.isPlayer) audio.footstep(a.groundMat, undefined, a.crouching ? 0.5 : 1);
        else if (a.pos.distanceTo(this.r.camera.position) < 22) audio.footstep(a.groundMat, a.pos.clone(), 0.8);
      },
    };
    this.state = 'playing';
    this.menus.hide();
    this.hud.show(true);
    this.r.setMenuBlur(false);
    this.r.setViewmodelVisible(true);
    this.input.requestLock();
    this.checkLockSoon();
    audio.music?.newSong();
    audio.music?.start();
    audio.music?.setIntensity(1);
    audio.startAmbience();
    this.ambient.ambienceOn = true;
    this.ambient.startSounds();
    this.hud.countdown(3);
    audio.countdown(false);
    this.hud.setMode(this.match);
    if (teamMode) {
      const sub =
        mode === 'takeover' ? `Hold the toy box. First to ${def.scoreTarget} wins.`
        : mode === 'conquest' ? `You start with ${this.match.sectors[CONQUEST_HOMES[0]].def.name}. Control 4 of the 6 sectors to win.`
        : `First team to ${def.scoreTarget} pops wins.`;
      this.hud.announce(`You're on Team ${TEAMS[0].name}`, sub, 3.4);
    } else this.hud.announce('Free-for-All', this.map.ffaIntro, 3.2);
  }

  /**
   * Conquest brain for the bots: every couple of seconds each team decides which sectors to defend
   * and which to attack, and sends its toys there (nearest first, spread out, sticky so they don't dither).
   */
  private runDirector(force = false) {
    const m = this.match;
    if (!m.sectors.length) return;
    const now = this.time;
    if (!force && now < this.directorAt) return;
    this.directorAt = now + 2;
    const teams = m.teamCount;
    for (let t = 0; t < teams; t++) {
      const bots = this.bots.filter((b) => b.actor.team === t && b.actor.alive);
      if (!bots.length) continue;
      const owned = m.sectorsOwned(t);
      const leader = Math.max(...m.teamScores.map((s, i) => (i === t ? -1 : s)));
      const value = m.sectors.map((s) => {
        const enemies = s.counts.reduce((acc, c, i) => acc + (i !== t ? c : 0), 0);
        if (s.owner === t) {
          if (enemies > 0 || s.progress < 1) return 3.2; // under attack: defend
          return owned >= 3 ? 0.9 : 0.35; // quiet: light guard, more when we're close to winning
        }
        if (s.owner < 0) return s.progressTeam === t && s.progress > 0 ? 2.8 : 2.3;
        // enemy sector: worth more if that team is about to win
        const threat = m.sectorsOwned(s.owner) >= 3 ? 1.6 : 0;
        return 1.5 + threat + (m.teamScores[s.owner] === leader ? 0.3 : 0);
      });
      const load = new Map<number, number>();
      // keep sticky assignments first
      const order = [...bots].sort((a, b) => (this.assignment.has(a.actor) ? 0 : 1) - (this.assignment.has(b.actor) ? 0 : 1));
      for (const b of order) {
        const a = b.actor;
        const cur = this.assignment.get(a);
        let best = -1, bestScore = -Infinity;
        m.sectors.forEach((s, i) => {
          const d = Math.hypot(a.pos.x - s.pos.x, a.pos.z - s.pos.z) + Math.abs(a.pos.y - s.pos.y) * 1.5;
          const crowd = (load.get(i) ?? 0) * (value[i] >= 3 ? 0.5 : 1.1);
          const score = value[i] - d / 38 - crowd + (i === cur ? 0.6 : 0);
          if (score > bestScore) {
            bestScore = score;
            best = i;
          }
        });
        if (best >= 0) {
          this.assignment.set(a, best);
          load.set(best, (load.get(best) ?? 0) + 1);
        }
      }
    }
  }

  /** Allies always get a team-colored outline in team modes; enemy outlines follow the setting. */
  private refreshOutlines() {
    const me = this.player?.actor;
    for (const a of this.actors) {
      if (!a.model) continue;
      const ally = !!me && me.team >= 0 && a.team === me.team;
      if (ally) a.model.setOutline(true, TEAMS[a.team].light);
      else a.model.setOutline(settings.data.enemyOutlines, '#ff2d55');
    }
  }

  private respawn(a: Actor, initial = false) {
    const pool = this.shelfStarters.has(a) && this.shelfSpawns.length ? this.shelfSpawns : undefined;
    const { pos, yaw } = this.match.pickSpawn(a, this.actors, pool);
    a.spawn(pos, yaw, this.time);
    a.slot = 0;
    if (a.isPlayer) {
      // your loadout from the menu (changes made mid-match apply here, on the next respawn)
      a.giveWeapon(loadout.primary, 0, loadout.scope(loadout.primary));
      a.giveWeapon(loadout.secondary, 1, loadout.scope(loadout.secondary));
      a.abilities = [...loadout.abilities];
      this.player!.onSpawn();
      this.player!.actor.weapon!.equip(this.time, 0.3);
    } else {
      const bot = this.botByActor.get(a)!;
      const [p1, p2] = pickBotLoadout(bot.personality);
      a.giveWeapon(p1, 0);
      a.giveWeapon(p2, 1);
      bot.onSpawn(this.time);
      a.model!.root.visible = true;
      a.model!.scaleIn = 0.01;
    }
    this.fx.reassemble(pos, a.def.colors);
    if (!initial) audio.spawnPop(pos.clone().setY(pos.y + 1));
  }

  // ------------------------------------------------------------------ revives (team modes)
  /** The downed teammate this toy is standing next to (closest one), or null. */
  private downedNear(a: Actor): Actor | null {
    if (!this.match.teams || !a.alive) return null;
    let best: Actor | null = null;
    let bestD: number = COMBAT.reviveRange;
    for (const o of this.actors) {
      if (o === a || o.team !== a.team || !o.isDowned(this.time)) continue;
      if (Math.abs(o.pos.y - a.pos.y) > 2.2) continue;
      const d = Math.hypot(o.pos.x - a.pos.x, o.pos.z - a.pos.z);
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    return best;
  }

  /** Holding on to a downed teammate for 3 s puts them back together on the spot. */
  private updateRevives(dt: number, now: number) {
    if (!this.match.teams || this.match.phase !== 'playing') return;
    const pl = this.player!;
    const playerTarget = pl.reviveHeld ? this.downedNear(pl.actor) : null;
    for (const d of this.actors) {
      if (!d.isDowned(now)) {
        d.reviveT = 0;
        d.reviver = null;
        continue;
      }
      let helper: Actor | null = playerTarget === d ? pl.actor : null;
      if (!helper) {
        for (const b of this.bots) {
          if (b.reviving !== d || !b.actor.alive) continue;
          if (Math.abs(b.actor.pos.y - d.pos.y) < 2.2 && Math.hypot(b.actor.pos.x - d.pos.x, b.actor.pos.z - d.pos.z) < COMBAT.reviveRange) {
            helper = b.actor;
            break;
          }
        }
      }
      if (helper) {
        d.reviver = helper;
        d.reviveT += dt;
        if (d.reviveT >= COMBAT.reviveTime) this.revive(d, helper);
      } else {
        d.reviveT = Math.max(0, d.reviveT - dt * 2);
        // a bot that is still running over keeps its claim; anyone else lets go
        const r = d.reviver;
        if (r && (!r.alive || r.isPlayer || this.botByActor.get(r)?.reviving !== d)) d.reviver = null;
      }
    }
  }

  private revive(d: Actor, by: Actor) {
    const pos = d.pos.clone().setY(d.pos.y + 0.05);
    d.spawn(pos, d.yaw, this.time);
    d.health = COMBAT.reviveHealth;
    d.lastDamageAt = this.time; // no instant regen: the usual 6 s wait applies
    d.respawnAt = -1;
    by.revives++;
    for (const w of d.weapons) w?.equip(this.time, 0.3);
    if (d.isPlayer) {
      this.player!.onSpawn();
      this.hud.announce('Back in the fight!', `${by.name} revived you`, 2);
    } else {
      this.botByActor.get(d)!.onSpawn(this.time);
      d.model!.root.visible = true;
      d.model!.scaleIn = 0.6;
    }
    this.fx.reassemble(pos, d.def.colors);
    audio.spawnPop(pos.clone().setY(pos.y + 1));
    const me = this.player!.actor;
    if (by === me) this.hud.pickup(`You revived ${d.name}`, '#7dff6b');
    else if (d !== me && d.team === me.team) this.hud.pickup(`${by.name} revived ${d.name}`, TEAMS[d.team].light);
  }

  pause() {
    if (this.state !== 'playing') return;
    this.state = 'paused';
    this.input.exitLock();
    this.menus.pause();
    this.r.setMenuBlur(true);
    audio.setPaused(true);
    this.hud.setScoreboard(false);
  }
  resume() {
    if (this.state !== 'paused') return;
    this.state = 'playing';
    this.menus.hide();
    this.r.setMenuBlur(false);
    audio.setPaused(false);
    this.input.requestLock();
    this.checkLockSoon();
    this.last = performance.now();
  }
  /** Chrome blocks re-locking for ~1s after Esc; if the lock didn't take, ask for a click. */
  private checkLockSoon() {
    window.clearTimeout(this.lockWatch);
    this.lockWatch = window.setTimeout(() => {
      // a controller player doesn't need the mouse captured
      if (this.state === 'playing' && !this.input.locked && !this.input.usingPad && !(window as any).__autotest) {
        this.menus.resumeHint(true, () => {
          this.input.requestLock();
          this.checkLockSoon();
        });
      } else this.menus.resumeHint(false, () => {});
    }, 600);
  }
  quitToMenu() {
    this.state = 'menu';
    this.input.exitLock();
    this.clearMatch();
    this.hud.show(false);
    this.menus.resumeHint(false, () => {});
    this.menus.main();
    this.r.setMenuBlur(true);
    this.r.setViewmodelVisible(false);
    audio.setPaused(false);
    audio.music?.setIntensity(0);
    this.ambient.stopSounds();
  }

  private endMatch() {
    const pl = this.player!.actor;
    this.state = 'results';
    this.input.exitLock();
    this.hud.setScoreboard(false);
    const st = settings.stats;
    st.matches++;
    const won = this.match.isWinner(pl);
    const reward = progress.award({
      kills: pl.kills,
      headshots: pl.headshots,
      revives: pl.revives,
      bestStreak: pl.bestStreak,
      won,
      place: this.match.teams ? 0 : this.match.standings(this.actors).indexOf(pl) + 1,
      difficulty: this.difficulty,
    });
    if (won) st.wins++;
    st.kills += pl.kills;
    st.deaths += pl.deaths;
    st.headshots += pl.headshots;
    st.shotsFired += pl.shotsFired;
    st.shotsHit += pl.shotsHit;
    st.bestStreak = Math.max(st.bestStreak, pl.bestStreak);
    st.bestMatchKills = Math.max(st.bestMatchKills, pl.kills);
    st.playTimeSec += this.matchSeconds;
    settings.saveStats();
    audio.fanfare(won);
    audio.music?.setIntensity(0);
    const m = this.match;
    const title = m.teams ? (m.winnerTeam === DRAW ? 'Draw!' : won ? 'Your team wins!' : `Team ${TEAMS[m.winnerTeam].name} wins!`) : won ? 'Victory!' : `${m.winner?.name ?? 'Nobody'} wins!`;
    const sub = m.mode.id === 'conquest' && m.winnerTeam >= 0 && m.endReason === 'score' ? `Team ${TEAMS[m.winnerTeam].name} controls 4 of 6 sectors` : '';
    this.hud.announce(title, sub, 2);
    window.setTimeout(() => {
      if (this.state !== 'results') return;
      this.menus.results(this.match, this.actors, pl, this.hud.boardHtml(this.actors, this.match, pl), reward);
      this.hud.show(false);
      this.r.setMenuBlur(true);
    }, 1800);
  }

  // ------------------------------------------------------------------ main loop
  private loop = (t: number) => {
    this.raf = requestAnimationFrame(this.loop);
    let realDt = (t - this.last) / 1000;
    this.last = t;
    if (!(realDt > 0)) realDt = 0;
    realDt = Math.min(realDt, 0.05);
    try {
      this.input.pollPad();
      if (this.state !== 'playing' && !this.input.capturing) {
        this.padNav.update(t / 1000);
        // a press that just started or resumed the match shouldn't also jump/pause in it
        if ((this.state as GameState) === 'playing') this.input.consumePressed();
      }
      this.frame(realDt);
    } catch (err) {
      console.error('[frame]', err);
    }
    this.input.endFrame();
  };

  private frame(realDt: number) {
    // slow-mo after the player's eliminations
    if (this.slowmoT > 0) {
      this.slowmoT -= realDt;
      if (this.slowmoT <= 0) this.timeScale = 1;
    } else this.timeScale += (1 - this.timeScale) * Math.min(1, realDt * 10);
    const dt = realDt * this.timeScale;
    if (this.state === 'menu') {
      this.menuT += realDt;
      this.menuCamera(this.menuT);
      this.worldTick(realDt, false);
    } else if (this.state === 'playing') {
      if (!this.debug.manual) this.gameTick(dt, realDt);
    } else if (this.state === 'results') {
      this.menuT += realDt;
      this.worldTick(realDt, true);
      this.updateRigs(realDt);
    } else {
      // paused: keep rendering, nothing moves
    }
    audio.updateListener(this.r.camera);
    this.r.render();
  }

  /** Things that animate regardless of the match: train, fan, dust, debris physics, effects. */
  private worldTick(dt: number, withActors: boolean) {
    this.time += dt;
    for (const a of this.arena.animated) a.update(dt, this.time);
    this.ambient.update(dt, withActors ? this.actors : [], () => {}, this.r.camera.position);
    this.elevators.update(dt, this.time, withActors ? this.actors : [], this.r.camera.position);
    this.phys.update(dt);
    this.combat.now = this.time;
    this.combat.update(dt);
    this.fx.update(dt, this.r.camera.position);
  }

  private gameTick(dt: number, realDt: number) {
    const now = (this.time += dt);
    const pl = this.player!;
    const pa = pl.actor;
    const m = this.match;
    this.matchSeconds += dt;
    this.combat.now = now;
    const frozen = m.phase === 'countdown';
    // scoreboard
    this.hud.setScoreboard(this.input.act('scoreboard'));
    if (this.input.pressed('Escape') || this.input.padPressed(PAD.MENU)) this.pause();
    // player input + weapons
    if (!frozen) pl.update(dt, now);
    else {
      // allow looking around during the countdown (mouse or right stick)
      pl.look(dt, false);
    }
    // bots think + move
    for (const b of this.bots) {
      if (frozen) b.intent.wish.set(0, 0, 0);
      else b.update(dt, now);
    }
    for (const a of this.actors) {
      if (!a.alive) continue;
      const intent = a.isPlayer ? pl.intent : this.botByActor.get(a)!.intent;
      if (frozen) {
        intent.wish.set(0, 0, 0);
        intent.jump = intent.dash = intent.crouchPressed = false;
      }
      const wasDashing = a.dashing;
      a.move(intent, dt, now, this.moveEvents);
      if (wasDashing && !a.dashing) {
        const from = this.dashFrom.get(a);
        if (from) this.fx.springTrail(from, a.pos.clone(), a.isPlayer ? '#ffd23f' : a.def.accent);
      }
      a.tick(dt, now);
      if (!a.isPlayer) a.ads = 0;
    }
    this.separate();
    if (!frozen) for (const b of this.bots) b.fire(now);
    this.combat.update(dt);
    this.phys.update(dt);
    for (const a of this.arena.animated) a.update(dt, now);
    this.pickups.update(dt, now, this.actors, (a, id) => this.botWants(a, id), (a) => this.botByActor.get(a)?.setModelWeapon());
    this.ambient.update(dt, this.actors, (a, dmg, p) => this.combat.applyDamage(a, null, dmg, false, p, 'block', new THREE.Vector3(0, -1, 0)), this.r.camera.position);
    this.elevators.update(dt, now, this.actors, this.r.camera.position);
    if (m.mode.id === 'conquest' && m.phase === 'playing') this.runDirector();
    // match rules
    for (const e of m.update(dt, this.actors, now)) {
      if (typeof e === 'number') {
        this.hud.countdown(e);
        audio.countdown(false);
      } else if (e === 'go') {
        this.hud.countdown('GO');
        audio.countdown(true);
      } else if (e === 'blockdrop') {
        if (!this.map.blockDrops) continue;
        this.ambient.blockDrop(this.nav, 8);
        this.hud.announce('Block drop!', 'Wooden blocks are falling. Watch for red rings.');
        audio.announce();
      } else if (e === 'end') {
        this.endMatch();
      } else if (e === 'hillwarn' && m.hill) {
        this.hud.announce('Toy box moving soon', `Next stop: ${m.hill.next.name}`, 2.5);
        audio.announce();
      } else if (e === 'hillmove' && m.hill) {
        this.hillZone.place(m.hill.pos, m.hill.site.radius, m.hill.site.height);
        this.hud.announce('The toy box moved!', `Now at ${m.hill.site.name}`, 2.8);
        audio.announce();
        audio.blockLand(m.hill.pos.clone().setY(m.hill.pos.y + 2));
      } else if (typeof e === 'object') {
        this.onSectorEvent(e);
      } else if ((e === 'hilltaken' || e === 'hillcontested') && m.hill && now - this.lastHillNote > 4) {
        this.lastHillNote = now;
        const mine = m.hill.owner === pa.team;
        const text = e === 'hillcontested' ? 'Toy box contested!' : mine ? 'Your team has the toy box' : 'The enemy took the toy box!';
        this.hud.pickup(text, e === 'hillcontested' ? '#ff4d8d' : TEAMS[Math.max(0, m.hill.owner)].color);
      }
    }
    this.hillZone.update(dt, m.hill, settings.data.reducedMotion);
    this.sectorZones.update(dt, m.sectors);
    this.updateRevives(dt, now);
    // respawns
    if (m.phase !== 'ended') {
      for (const a of this.actors) if (!a.alive && a.respawnAt >= 0 && now >= a.respawnAt) this.respawn(a);
    }
    this.updateRigs(dt);
    // camera + viewmodel
    pl.updateCamera(realDt, now);
    pl.updateViewmodel(realDt, now);
    this.r.setViewmodelVisible(pa.alive);
    this.fx.update(dt, this.r.camera.position);
    // zone ambience + music intensity
    const zone = this.zoneAt(pa.pos);
    if (zone && zone.name !== this.lastZone) {
      this.lastZone = zone.name;
      audio.setZone(zone.ambience);
    }
    const inten = m.intensity(this.actors);
    if (audio.music && audio.music.intensity !== inten) audio.music.setIntensity(inten);
    if (m.phase === 'playing' && m.timeLeft < 60.05 && m.timeLeft > 59.95 - dt) this.hud.announce('One minute left!', '', 2);
    this.hud.update(realDt, now, pl, this.actors, m, this.r.camera, zone?.name ?? '');
    if (this.net.status === 'online' && now >= this.netSendAt) {
      this.netSendAt = now + 0.05;
      this.net.sendState({ x: pa.pos.x, y: pa.pos.y, z: pa.pos.z, yaw: pa.yaw, pitch: pa.pitch, hp: Math.round(pa.health), weapon: pa.weapon?.id ?? '', alive: pa.alive });
    }
  }

  /**
   * Saves the current map's level geometry as a .glb file (opens in Godot, Blender, etc.).
   * From the browser console: __toybox.exportMapGLB()
   */
  async exportMapGLB(download = true): Promise<ArrayBuffer> {
    const { GLTFExporter } = await import('three/examples/jsm/exporters/GLTFExporter.js');
    const glb = (await new GLTFExporter().parseAsync(this.arena.root, { binary: true, onlyVisible: true })) as ArrayBuffer;
    if (download) {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob([glb], { type: 'model/gltf-binary' }));
      a.download = `toybox-${this.map.id}.glb`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    }
    return glb;
  }

  private onSectorEvent(e: SectorEvent) {
    const pa = this.player?.actor;
    if (!pa) return;
    const s = this.match.sectors[e.sector];
    const name = s.def.name.replace(/^the /, '');
    const mine = e.team === pa.team;
    if (e.kind === 'captured') {
      this.hud.pickup(mine ? `Your team captured ${name}` : `Team ${TEAMS[e.team].name} captured ${name}`, TEAMS[e.team].color);
      audio.sectorCaptured(mine);
      const n = this.match.sectorsOwned(e.team);
      if (n === 3) this.hud.announce(mine ? 'Your team holds 3 sectors' : `Team ${TEAMS[e.team].name} holds 3 sectors`, mine ? 'One more wins it!' : 'Take one back before they get a fourth!', 2.6);
    } else if (e.kind === 'neutralized') {
      this.hud.pickup(mine ? `You lost ${name}` : `${name} is neutral again`, mine ? '#ff4d6d' : '#fff6d8');
      if (mine) audio.sectorCaptured(false);
    } else if (e.kind === 'attacked' && mine) {
      this.hud.pickup(`${name} is under attack!`, '#ff4d8d');
    }
  }

  /** Test hook: run the simulation without rendering. */
  debugStep(seconds: number, dt = 1 / 60) {
    const n = Math.round(seconds / dt);
    for (let i = 0; i < n && this.state === 'playing'; i++) {
      this.gameTick(dt, dt);
      this.input.endFrame();
    }
  }

  private botWants(a: Actor, id: WeaponId) {
    const b = this.botByActor.get(a);
    if (!b) return false;
    if (a.weapons.some((w) => w?.id === id)) return a.weapons.find((w) => w?.id === id)!.reserve < WEAPONS[id].reserve * 0.5;
    return b.personality.favorite.includes(id) || (a.weapons[0]?.mag ?? 0) + (a.weapons[0]?.reserve ?? 0) <= 0;
  }

  private zoneAt(p: THREE.Vector3): Zone | undefined {
    return this.arena.zones.find((z) => p.x >= z.min[0] && p.x <= z.max[0] && p.z >= z.min[1] && p.z <= z.max[1]);
  }

  /** Toys don't physically collide with each other; gently push overlapping ones apart. */
  private separate() {
    const A = this.actors;
    for (let i = 0; i < A.length; i++) {
      const a = A[i];
      if (!a.alive) continue;
      for (let j = i + 1; j < A.length; j++) {
        const b = A[j];
        if (!b.alive) continue;
        if (Math.abs(a.pos.y - b.pos.y) > 1.6) continue;
        const dx = b.pos.x - a.pos.x, dz = b.pos.z - a.pos.z;
        const d2 = dx * dx + dz * dz;
        const min = 0.78;
        if (d2 >= min * min) continue;
        const d = Math.sqrt(d2) || 0.01;
        const push = (min - d) * 0.5;
        const nx = d2 > 1e-6 ? dx / d : Math.random() - 0.5, nz = d2 > 1e-6 ? dz / d : Math.random() - 0.5;
        this.nudge(a, -nx * push, -nz * push);
        this.nudge(b, nx * push, nz * push);
      }
    }
  }
  private nudge(a: Actor, dx: number, dz: number) {
    a.cc.computeColliderMovement(a.collider, { x: dx, y: 0, z: dz }, undefined, this.phys.charQueryGroups());
    const mv = a.cc.computedMovement();
    a.pos.x += mv.x;
    a.pos.z += mv.z;
    a.sync();
  }

  private updateRigs(dt: number) {
    for (const b of this.bots) {
      const a = b.actor;
      const rig = a.model!;
      rig.root.rotation.order = 'YXZ';
      if (!a.alive) {
        // team modes: the toy lies where it fell until it is revived or the respawn timer runs out
        const down = a.isDowned(this.time) && this.match.phase !== 'ended';
        rig.root.visible = down;
        if (down) {
          rig.setCloak(0, this.time);
          rig.setPunch(0);
          rig.scaleIn = 1;
          rig.root.scale.setScalar(1);
          rig.root.position.set(a.pos.x, a.pos.y + 0.32, a.pos.z);
          rig.root.rotation.set(-Math.PI / 2 + 0.06, a.yaw + Math.PI, 0);
        }
        continue;
      }
      rig.root.rotation.x = 0;
      rig.root.visible = true;
      rig.scaleIn = Math.min(1, rig.scaleIn + dt * 3.5);
      rig.root.position.copy(a.pos);
      rig.root.rotation.y = a.yaw + Math.PI;
      rig.update(dt, b.animState(this.time), this.time);
      rig.setShimmer(a.isProtected(this.time), this.time);
      rig.setPunch(a.jabT);
      // cloaked toys: teammates see a ghost, enemies barely a shimmer (a bit more up close)
      const me = this.player?.actor;
      let op = 0;
      if (a.cloaked) {
        const ally = !!me && me.team >= 0 && a.team === me.team;
        const d = me ? me.pos.distanceTo(a.pos) : 99;
        op = ally ? 0.3 : d < 3 ? 0.12 : 0.045;
      }
      rig.setCloak(op, this.time);
    }
    this.updateBeacons();
    // Spring Hook cords
    this.ropes.begin();
    for (const a of this.actors) {
      if (!a.alive || !a.grapple) continue;
      let from: THREE.Vector3;
      if (a.isPlayer) from = new THREE.Vector3(-0.22, -0.22, -0.5).applyMatrix4(this.r.camera.matrixWorld);
      else from = a.chestPos().add(new THREE.Vector3(-Math.sin(a.yaw), 0.15, -Math.cos(a.yaw)).multiplyScalar(0.4));
      this.ropes.draw(from, a.grapple.anchor, this.time - a.grapple.start);
    }
    this.ropes.end();
  }

  private beacons = new Map<Actor, THREE.Group>();
  /** A pulsing team-colored ring with a plus over every downed toy, so bodies are easy to find. */
  private updateBeacons() {
    const now = this.time;
    for (const a of this.actors) {
      const down = a.isDowned(now) && this.match.phase !== 'ended';
      let b = this.beacons.get(a);
      if (!down) {
        if (b) b.visible = false;
        continue;
      }
      if (!b) {
        b = new THREE.Group();
        const mat = new THREE.MeshBasicMaterial({ color: TEAMS[a.team].color, transparent: true, opacity: 0.9, depthWrite: false, toneMapped: false, side: THREE.DoubleSide });
        const ring = new THREE.Mesh(new THREE.RingGeometry(0.95, 1.15, 40), mat);
        ring.rotation.x = -Math.PI / 2;
        ring.position.y = 0.06;
        const fill = new THREE.Mesh(new THREE.RingGeometry(0.01, 0.95, 40, 1, 0, 0.001), mat.clone());
        fill.rotation.x = -Math.PI / 2;
        fill.position.y = 0.05;
        (fill.material as THREE.MeshBasicMaterial).opacity = 0.45;
        const plus = new THREE.Group();
        plus.add(new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.2, 0.2), mat), new THREE.Mesh(new THREE.BoxGeometry(0.2, 0.7, 0.2), mat));
        plus.position.y = 2.1;
        b.add(ring, fill, plus);
        b.userData = { fill, plus, ring };
        this.r.scene.add(b);
        this.beacons.set(a, b);
      }
      b.visible = true;
      b.position.copy(a.pos);
      const u = b.userData as { fill: THREE.Mesh; plus: THREE.Group; ring: THREE.Mesh };
      u.plus.rotation.y = now * 2;
      u.plus.position.y = 2.1 + Math.sin(now * 3) * 0.12;
      u.ring.scale.setScalar(1 + Math.sin(now * 5) * 0.06);
      // the pie fills up while someone is reviving
      const frac = Math.round(Math.min(1, a.reviveT / COMBAT.reviveTime) * 36) / 36;
      if (b.userData.frac !== frac) {
        b.userData.frac = frac;
        u.fill.geometry.dispose();
        u.fill.geometry = new THREE.RingGeometry(0.01, 0.95, 40, 1, Math.PI / 2, Math.max(0.001, frac * Math.PI * 2));
      }
    }
  }

  /** Slow flyover of the bedroom behind the menus. */
  private menuCamera(t: number) {
    const cam = this.r.camera;
    const a = t * 0.045;
    const mc = this.map.menuCam;
    const pos = new THREE.Vector3(2 + Math.cos(a) * (mc.r - 1), mc.h + Math.sin(a * 1.7) * 2.5, 1 + Math.sin(a) * (mc.r + 1));
    const look = new THREE.Vector3(2 + Math.cos(a + 2.2) * 6, 3, 1 + Math.sin(a + 2.2) * 6);
    cam.position.copy(pos);
    cam.lookAt(look);
    const v = 2 * Math.atan(Math.tan((75 * Math.PI) / 360) / cam.aspect) * (180 / Math.PI);
    if (Math.abs(cam.fov - v) > 0.01) {
      cam.fov = v;
      cam.updateProjectionMatrix();
    }
  }
}

const tick = () => new Promise<void>((r) => setTimeout(r, 0));

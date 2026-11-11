import * as THREE from 'three';
import { Actor, MoveIntent, emptyIntent } from './Actor';
import { NavGraph } from '../nav/NavGraph';
import { Physics } from '../physics/Physics';
import { Combat } from '../combat/Combat';
import { AudioEngine } from '../audio/Audio';
import { Effects } from '../fx/Effects';
import { CharacterId } from './ToyModels';
import { ABILITIES, ABILITY_ORDER, AbilityId, WeaponId, WEAPONS } from '../weapons/weaponConfig';
import { tryCloak, tryGrapple, tryJab, tryShield, grapplePoint } from './abilities';
import type { ModeId } from '../match/modes';
import { buildWeaponModel, WeaponModel } from '../weapons/WeaponModels';
import { flattenByMaterial } from '../render/merge';
import { Difficulty } from '../core/Settings';
import { DEG, angleWrap, clamp, rand, pick } from '../core/math';

export type BotState = 'patrol' | 'search' | 'engage' | 'retreat' | 'reload' | 'seekPickup' | 'objective' | 'revive';

export interface Personality {
  aggression: number; // 0..1 closes distance, chases
  caution: number; // 0..1 retreat earlier, more cover
  jumpiness: number; // 0..1 strafe/jump frequency
  speed: number; // move multiplier on top of base
  favorite: WeaponId[];
  dashUse: number;
  headshotBias: number;
}

export const PERSONALITIES: Record<Exclude<CharacterId, 'player'>, Personality> = {
  captainClick: { aggression: 0.5, caution: 0.5, jumpiness: 0.3, speed: 1, favorite: ['foamFury', 'brickbreaker', 'popcornPopper'], dashUse: 0.3, headshotBias: 0.25 },
  rexRampage: { aggression: 0.95, caution: 0.15, jumpiness: 0.5, speed: 1.02, favorite: ['bubbleBlaster', 'rapidRascal'], dashUse: 0.7, headshotBias: 0.1 },
  boltBuddy: { aggression: 0.6, caution: 0.4, jumpiness: 0.6, speed: 1.1, favorite: ['starlightZapper', 'foamFury'], dashUse: 0.5, headshotBias: 0.2 },
  princessPanic: { aggression: 0.7, caution: 0.3, jumpiness: 0.95, speed: 1.04, favorite: ['foamFury', 'rapidRascal'], dashUse: 0.5, headshotBias: 0.15 },
  turboTim: { aggression: 0.75, caution: 0.3, jumpiness: 0.6, speed: 1.12, favorite: ['rapidRascal', 'bubbleBlaster', 'jackBlaster'], dashUse: 0.9, headshotBias: 0.15 },
  mechaMax: { aggression: 0.25, caution: 0.85, jumpiness: 0.1, speed: 0.95, favorite: ['thunderspring', 'brickbreaker', 'plungerBow'], dashUse: 0.2, headshotBias: 0.45 },
  blockhead: { aggression: 0.55, caution: 0.45, jumpiness: 0.35, speed: 1, favorite: ['crayonCannon', 'brickbreaker'], dashUse: 0.3, headshotBias: 0.1 },
  sergeantSnap: { aggression: 0.45, caution: 0.6, jumpiness: 0.25, speed: 1, favorite: ['popcornPopper', 'jackBlaster'], dashUse: 0.3, headshotBias: 0.35 },
  dinaMite: { aggression: 0.9, caution: 0.2, jumpiness: 0.55, speed: 1.04, favorite: ['crayonCannon', 'bubbleBlaster'], dashUse: 0.7, headshotBias: 0.1 },
  sparky: { aggression: 0.6, caution: 0.35, jumpiness: 0.7, speed: 1.1, favorite: ['starlightZapper', 'rapidRascal'], dashUse: 0.6, headshotBias: 0.2 },
  duchessDazzle: { aggression: 0.35, caution: 0.7, jumpiness: 0.4, speed: 1, favorite: ['thunderspring', 'plungerBow', 'walloper'], dashUse: 0.3, headshotBias: 0.5 },
  nitroNina: { aggression: 0.8, caution: 0.25, jumpiness: 0.6, speed: 1.12, favorite: ['rapidRascal', 'jackBlaster'], dashUse: 0.9, headshotBias: 0.15 },
  gearboxGus: { aggression: 0.3, caution: 0.8, jumpiness: 0.1, speed: 0.95, favorite: ['brickbreaker', 'plungerBow', 'walloper'], dashUse: 0.2, headshotBias: 0.45 },
  brickette: { aggression: 0.6, caution: 0.4, jumpiness: 0.45, speed: 1.02, favorite: ['brickbreaker', 'jackBlaster'], dashUse: 0.4, headshotBias: 0.2 },
};

/**
 * Each bot brings two of the five abilities, leaning on its personality: rushers like dash and punch,
 * careful toys like shield and cloak, jumpy ones like the hook. Some randomness so matches differ.
 */
export function pickBotAbilities(p: Personality): AbilityId[] {
  const w: Record<AbilityId, number> = {
    dash: 0.4 + p.dashUse,
    jab: 0.2 + p.aggression * 0.9,
    grapple: 0.5 + p.jumpiness * 0.5,
    cloak: 0.3 + p.caution * 0.5 + p.aggression * 0.3,
    shield: 0.2 + p.caution * 1.0,
  };
  const out: AbilityId[] = [];
  for (let n = 0; n < 2; n++) {
    const left = ABILITY_ORDER.filter((id) => !out.includes(id));
    let r = Math.random() * left.reduce((s, id) => s + w[id], 0);
    let pick = left[left.length - 1];
    for (const id of left) {
      r -= w[id];
      if (r <= 0) {
        pick = id;
        break;
      }
    }
    out.push(pick);
  }
  return out;
}

/** Weapons that only exist as pickups up on the shelves (bots go get them, they don't spawn with them). */
export const SHELF_WEAPONS: WeaponId[] = ['jackBlaster', 'plungerBow'];

export interface ElevatorView {
  center: THREE.Vector3; // xz of the shaft, y = floor
  bottomY: number; // platform top when down
  topY: number; // platform top when up
  platformY: number; // current platform top
  /** 'bottom' | 'top' = parked with the doors open, 'moving' otherwise */
  parked: 'bottom' | 'top' | 'moving';
  /** seconds until it leaves (when parked) */
  leaveIn: number;
}

export const DIFFICULTY: Record<Difficulty, { reaction: number; aimError: number; turn: number; view: number; fov: number; recoilComp: number; fireAngle: number; burst: number; headshot: number; hearing: number }> = {
  easy: { reaction: 0.75, aimError: 5.5, turn: 200, view: 42, fov: 100, recoilComp: 0.2, fireAngle: 7, burst: 0.45, headshot: 0.05, hearing: 22 },
  normal: { reaction: 0.42, aimError: 2.9, turn: 340, view: 62, fov: 115, recoilComp: 0.55, fireAngle: 5, burst: 0.75, headshot: 0.18, hearing: 32 },
  hard: { reaction: 0.24, aimError: 1.5, turn: 560, view: 85, fov: 125, recoilComp: 0.8, fireAngle: 3.5, burst: 1, headshot: 0.32, hearing: 42 },
};

export interface BotWorld {
  nav: NavGraph;
  phys: Physics;
  combat: Combat;
  audio: AudioEngine;
  fx: Effects;
  actors: () => Actor[];
  player: () => Actor | null;
  pickups: () => { pos: THREE.Vector3; kind: string; available: boolean }[];
  spawnPoints: THREE.Vector3[];
  zones: { name: string; min: [number, number]; max: [number, number] }[];
  difficulty: Difficulty;
  listenerPos: THREE.Vector3;
  /** where this toy should be fighting for (toy box / assigned sector) in objective modes */
  objective: (a: Actor) => { pos: THREE.Vector3; radius: number; height: number } | null;
  teamMode: boolean;
  mode: ModeId;
  elevators: () => ElevatorView[];
}

const _v = new THREE.Vector3();
const _w = new THREE.Vector3();

export class Bot {
  intent: MoveIntent = emptyIntent();
  state: BotState = 'patrol';
  private stateT = 0;
  target: Actor | null = null;
  private targetVisible = false;
  private targetSeenAt = -99;
  private lastKnown = new THREE.Vector3();
  private reactionUntil = 0;
  private heard: { pos: THREE.Vector3; t: number } | null = null;
  private path: number[] | null = null;
  private pathIdx = 0;
  private goal = new THREE.Vector3();
  private hasGoal = false;
  private thinkAt = Math.random() * 0.2;
  private progressAt = 0;
  private progressPos = new THREE.Vector3();
  private stuckCount = 0;
  private unstickUntil = 0;
  private unstickDir = new THREE.Vector3();
  private strafeDir = 1;
  private strafeChangeAt = 0;
  private jumpAt = 0;
  private aimNoise = new THREE.Vector2();
  private aimNoiseTarget = new THREE.Vector2();
  private aimNoiseAt = 0;
  private triggerHeld = false;
  private burstUntil = 0;
  private pauseUntil = 0;
  private nextSemiAt = 0;
  private aimHead = false;
  private coverUntil = 0;
  private pickupTarget: THREE.Vector3 | null = null;
  private lookAround = 0;
  private weaponModels = new Map<WeaponId, WeaponModel>();
  private crouchUntil = 0;
  private wantDash = false;
  private noLosSince = 0;
  /** objective modes: holders sit in the toy box, hunters roam around it */
  role: 'holder' | 'hunter' = 'holder';
  private holdAt = 0;
  private waitingLift = false;
  private wasGrappling = false;
  private abilityCheckAt = 0;
  private sneaking = false;
  /** running to a health battery to get away from a fight */
  private fleeing = false;
  private reviveTarget: Actor | null = null;
  /** the downed teammate this bot is currently trying to revive */
  get reviving(): Actor | null {
    return this.state === 'revive' ? this.reviveTarget : null;
  }
  /** Closest downed teammate worth running to (nobody else on it, enough time left on their timer). */
  private findDowned(now: number, maxD = 26): Actor | null {
    const a = this.actor;
    let best: Actor | null = null;
    let bestD = maxD;
    for (const o of this.w.actors()) {
      if (o === a || o.team !== a.team || !o.isDowned(now)) continue;
      if (o.reviver && o.reviver !== a && o.reviver.alive) continue;
      const d = o.pos.distanceTo(a.pos);
      // need time to get there (sprinting ~8 m/s) plus the 3 s hold
      if (o.respawnAt - now < d / 7 + 3.4 - o.reviveT) continue;
      if (d < bestD) {
        bestD = d;
        best = o;
      }
    }
    return best;
  }

  constructor(public actor: Actor, public personality: Personality, private w: BotWorld) {}

  get diff() {
    return DIFFICULTY[this.w.difficulty];
  }

  setModelWeapon() {
    const ws = this.actor.weapon;
    if (!this.actor.model || !ws) return;
    let m = this.weaponModels.get(ws.id);
    if (!m) {
      m = buildWeaponModel(ws.id);
      flattenByMaterial(m);
      this.weaponModels.set(ws.id, m);
    }
    this.actor.model.setWeapon(m);
    ws.onReloadBeat = (part) => {
      if (this.actor.pos.distanceTo(this.w.listenerPos) < 18) this.w.audio.reloadPart(ws.id, part, false, this.actor.pos.clone().setY(this.actor.pos.y + 1.2));
    };
  }
  muzzleWorld(out: THREE.Vector3) {
    const m = this.actor.weapon ? this.weaponModels.get(this.actor.weapon.id) : null;
    if (m && this.actor.model) {
      this.actor.model.root.updateMatrixWorld(true);
      return m.userData.muzzle.getWorldPosition(out);
    }
    return this.actor.eyePos(out);
  }

  private get abilityDeps() {
    return { combat: this.w.combat, phys: this.w.phys, audio: this.w.audio };
  }

  onSpawn(now: number) {
    this.role = this.w.mode === 'conquest' || Math.random() < 0.75 ? 'holder' : 'hunter';
    this.sneaking = false;
    this.fleeing = false;
    this.reviveTarget = null;
    this.waitingLift = false;
    this.state = 'patrol';
    this.target = null;
    this.path = null;
    this.hasGoal = false;
    this.heard = null;
    this.stuckCount = 0;
    this.progressAt = now + 1;
    this.progressPos.copy(this.actor.pos);
    this.setModelWeapon();
  }

  /** Called by the game when this bot takes damage. */
  onDamaged(attacker: Actor | null, now: number) {
    if (!attacker || attacker === this.actor) return;
    // we know roughly where it came from
    if (!this.target || !this.targetVisible) {
      this.lastKnown.copy(attacker.pos).add(new THREE.Vector3(rand(-2, 2), 0, rand(-2, 2)));
      this.targetSeenAt = now - 1;
      if (this.state === 'patrol' || this.state === 'seekPickup') this.setState('search', now);
      this.target = attacker;
      this.reactionUntil = Math.max(this.reactionUntil, now + this.diff.reaction * 0.6);
    }
    if (this.personality.caution > 0.6 && Math.random() < 0.4) this.coverUntil = now + rand(1, 2);
  }
  /** Gunshot heard somewhere. */
  onSound(pos: THREE.Vector3, shooter: Actor, now: number, loud: number) {
    if (shooter === this.actor) return;
    const d = pos.distanceTo(this.actor.pos);
    if (d > this.diff.hearing * loud) return;
    if (this.targetVisible) return;
    this.heard = { pos: pos.clone(), t: now };
  }

  private setState(s: BotState, now: number) {
    if (this.state === s) return;
    this.state = s;
    this.stateT = now;
    this.path = null;
    this.hasGoal = false;
  }

  // ------------------------------------------------------------------ perception
  private perceive(now: number) {
    const a = this.actor;
    const d = this.diff;
    const eye = a.eyePos();
    const fwd = _w.set(-Math.sin(a.yaw), 0, -Math.cos(a.yaw));
    let best: Actor | null = null;
    let bestScore = Infinity;
    let curVisible = false;
    for (const o of this.w.actors()) {
      if (o === a || !o.alive || !a.isEnemy(o)) continue;
      const to = _v.subVectors(o.pos, a.pos);
      const dist = to.length();
      if (dist > d.view) continue;
      if (o.cloaked && dist > ABILITIES.cloak.revealDistance) continue;
      const recentlyHurtMe = a.lastAttacker === o && now - a.lastAttackerAt < 2.5;
      const flat = to.clone().setY(0).normalize();
      const ang = Math.acos(clamp(flat.dot(fwd), -1, 1)) / DEG;
      if (ang > d.fov / 2 && dist > 5 && !recentlyHurtMe && o !== this.target) continue;
      // line of sight to head or chest
      const vis = this.w.phys.los(eye, o.headPos()) || this.w.phys.los(eye, o.chestPos());
      if (!vis) continue;
      let score = dist;
      if (recentlyHurtMe) score -= 12;
      if (o === this.target) score -= 8;
      if (o.health + o.shield < 50) score -= 4;
      if (o.isPlayer) score -= 2;
      if (o.isProtected(now)) score += 30;
      if (score < bestScore) {
        bestScore = score;
        best = o;
      }
      if (o === this.target) curVisible = true;
    }
    if (best) {
      if (best !== this.target) {
        this.reactionUntil = now + d.reaction * rand(0.8, 1.3);
        this.aimHead = Math.random() < d.headshot + this.personality.headshotBias * 0.3;
      }
      this.target = best;
      this.targetVisible = true;
      this.targetSeenAt = now;
      this.lastKnown.copy(best.pos);
      this.noLosSince = now;
    } else {
      this.targetVisible = false;
      if (this.target && (!this.target.alive || now - this.targetSeenAt > 5)) this.target = null;
    }
    void curVisible;
  }

  // ------------------------------------------------------------------ decisions
  private think(now: number) {
    const a = this.actor;
    const p = this.personality;
    this.perceive(now);
    const ws = a.weapon;
    const hpFrac = (a.health + a.shield) / 100;
    // wary: run once health starts dropping (earlier for careful toys), or after a sudden burst of damage
    const retreatAt = 0.35 + p.caution * 0.3;
    const burst = a.damageInLast(3, now);
    const scared = hpFrac < retreatAt || (burst > 35 && a.health < 75);
    // weapon choice by distance
    if (this.target && this.targetVisible) this.chooseWeapon(this.target.pos.distanceTo(a.pos), now);
    if (ws && ws.mag <= 0 && !ws.isEnergy) {
      const other = a.weapons[a.slot === 0 ? 1 : 0];
      if (this.targetVisible && other && other.mag > 0 && p.aggression > 0.4) this.switchSlot(a.slot === 0 ? 1 : 0, now);
      else if (ws.reserve > 0 && !ws.reloading) ws.startReload();
    }
    if (ws && !this.targetVisible && !ws.reloading && !ws.isEnergy && ws.mag < ws.cfg.magSize * 0.4 && ws.reserve > 0) ws.startReload();

    if (scared && (this.targetVisible || burst > 0) && this.state !== 'retreat' && !(this.state === 'seekPickup' && this.fleeing) && now - this.stateT > 0.8) {
      this.startRetreat(now);
      return;
    }
    if (this.state === 'retreat') {
      if ((hpFrac > 0.8 || now - this.stateT > 9) && now - a.lastDamageAt > 2.5) this.setState(this.target ? 'search' : 'patrol', now);
      return;
    }
    if (this.state === 'seekPickup' && this.fleeing) {
      // keep running for the battery; fall back to plain retreat if it's gone
      const still = this.w.pickups().find((x) => x.available && this.pickupTarget && x.pos.distanceToSquared(this.pickupTarget) < 0.5);
      if (!still || now - this.stateT > 10) {
        this.fleeing = false;
        this.setState(hpFrac > 0.8 ? 'patrol' : 'retreat', now);
      }
      return;
    }
    this.fleeing = false;
    if (ws?.reloading && this.targetVisible && p.caution > 0.4) {
      this.setState('reload', now);
      return;
    }
    const obj = this.w.objective(a);
    const inObj = obj ? this.inZone(obj) : false;
    if (this.target && this.targetVisible) {
      const far = this.target.pos.distanceTo(a.pos) > 20;
      // holders don't get dragged into long-range fights away from the toy box (they still shoot while moving)
      if (obj && this.role === 'holder' && !inObj && far) {
        this.setState('objective', now);
        return;
      }
      this.setState('engage', now);
      return;
    }
    // nobody shooting at us right now: pick up a downed teammate
    if (this.w.teamMode) {
      const keep = this.state === 'revive' && this.reviveTarget && this.reviveTarget.isDowned(now) ? this.reviveTarget : null;
      const d = keep ?? (hpFrac > 0.4 && now - a.lastDamageAt > 1.5 ? this.findDowned(now, obj && this.role === 'holder' ? 11 : 26) : null);
      if (d) {
        if (this.reviveTarget !== d || this.state !== 'revive') {
          this.reviveTarget = d;
          d.reviver = a;
          this.setState('revive', now);
        }
        return;
      }
      this.reviveTarget = null;
      if (this.state === 'revive') this.setState('patrol', now);
    }
    if (obj && this.role === 'holder' && hpFrac > 0.35) {
      this.setState('objective', now);
      return;
    }
    if (this.state === 'engage' && this.target && now - this.targetSeenAt < 3.5) {
      // lost sight: push to last known position
      this.setState('search', now);
      return;
    }
    if (this.heard && now - this.heard.t < 6 && this.state !== 'seekPickup') {
      this.lastKnown.copy(this.heard.pos);
      this.heard = null;
      this.setState('search', now);
      return;
    }
    if (this.state === 'search' && now - this.stateT > 9) this.setState('patrol', now);
    if (this.state === 'reload' && !ws?.reloading) this.setState('patrol', now);
    // pickups: health when hurt, otherwise occasionally power-ups / better guns
    // objective holders only detour for pickups when they are actually hurt
    const stayOnObj = !!obj && this.role === 'holder' && hpFrac >= 0.6 && !!ws && (ws.isEnergy || ws.reserve > 0);
    if (!stayOnObj && (this.state === 'patrol' || (this.state === 'search' && hpFrac < 0.5))) {
      const pk = this.pickPickup(hpFrac, now);
      if (pk) {
        this.pickupTarget = pk;
        this.setState('seekPickup', now);
      }
    }
    if (this.state === 'seekPickup') {
      const still = this.w.pickups().find((x) => x.available && this.pickupTarget && x.pos.distanceToSquared(this.pickupTarget) < 0.5);
      if (!still || now - this.stateT > 14) this.setState('patrol', now);
    }
  }

  /** Get out of the fight: grab a nearby health battery if it isn't toward the enemy, else run for cover. */
  private startRetreat(now: number) {
    const a = this.actor;
    const p = this.personality;
    const from = this.target?.pos ?? a.lastAttacker?.pos ?? null;
    let best: THREE.Vector3 | null = null;
    let bestD = 28;
    for (const pk of this.w.pickups()) {
      if (!pk.available || pk.kind !== 'health') continue;
      const d = pk.pos.distanceTo(a.pos);
      if (d > bestD) continue;
      if (from) {
        const toPk = _v.subVectors(pk.pos, a.pos).setY(0).normalize();
        const toEnemy = _w.subVectors(from, a.pos).setY(0).normalize();
        if (toPk.dot(toEnemy) > 0.5 && from.distanceTo(pk.pos) < d) continue;
      }
      best = pk.pos;
      bestD = d;
    }
    if (best) {
      this.pickupTarget = best.clone();
      this.setState('seekPickup', now);
      this.fleeing = true;
    } else this.setState('retreat', now);
    this.wantDash = Math.random() < p.dashUse + 0.2;
    // escape tools
    const deps = this.abilityDeps;
    if (a.has('cloak') && now >= a.cloakReadyAt && !a.cloaked && Math.random() < 0.45 + p.caution * 0.4) {
      if (tryCloak(a, now, deps)) this.sneaking = true;
    } else if (a.has('shield') && this.target && this.targetVisible && now >= a.shieldReadyAt && Math.random() < 0.6) {
      const t = this.target.pos;
      tryShield(a, now, deps, Math.atan2(-(t.x - a.pos.x), -(t.z - a.pos.z)));
    }
    if (from && a.has('grapple') && now >= a.grappleReadyAt && Math.random() < 0.35) this.grappleAway(from, now);
  }

  /** Spring Hook to a higher spot pointing away from the threat. */
  private grappleAway(from: THREE.Vector3, now: number) {
    const a = this.actor;
    const nav = this.w.nav;
    const eye = a.eyePos();
    for (let i = 0; i < 6; i++) {
      const id = nav.random((n) => {
        const d = n.pos.distanceTo(a.pos);
        return d > 10 && d < ABILITIES.grapple.range - 4 && n.pos.y > a.pos.y + 2.5 && n.pos.distanceTo(from) > a.pos.distanceTo(from) + 4;
      });
      const n = nav.nodes[id];
      if (!n || n.pos.y <= a.pos.y + 2.5) continue;
      const tgt = n.pos.clone().setY(n.pos.y + 0.3);
      if (!this.w.phys.los(eye, tgt, true)) continue;
      const dir = tgt.sub(eye).normalize();
      const pt = grapplePoint(a, dir, this.w.phys);
      if (!pt || pt.distanceTo(n.pos) > 3) continue;
      a.yaw = Math.atan2(-dir.x, -dir.z);
      if (tryGrapple(a, dir, now, this.abilityDeps)) return true;
    }
    return false;
  }

  /** Spring Hook straight toward a point (used to climb toward a goal or a target that's high above). */
  private grappleToward(p: THREE.Vector3, now: number) {
    const a = this.actor;
    const eye = a.eyePos();
    const tgt = p.clone().setY(p.y + 0.3);
    if (eye.distanceTo(tgt) > ABILITIES.grapple.range - 2 || !this.w.phys.los(eye, tgt, true)) return false;
    const dir = tgt.sub(eye).normalize();
    const pt = grapplePoint(a, dir, this.w.phys);
    if (!pt || pt.distanceTo(p) > 3.5) return false;
    return !!tryGrapple(a, dir, now, this.abilityDeps);
  }

  /** Abilities that depend on the fight: punch up close, shield when pinned, hook up to high targets/goals. */
  private useAbilities(now: number) {
    const a = this.actor;
    const p = this.personality;
    const t = this.target;
    const deps = this.abilityDeps;
    const ws = a.weapon;
    if (t && this.targetVisible && t.alive) {
      const dist = t.pos.distanceTo(a.pos);
      const to = _v.subVectors(t.pos, a.pos).setY(0).normalize();
      const facing = to.dot(_w.set(-Math.sin(a.yaw), 0, -Math.cos(a.yaw)));
      if (a.has('jab') && dist < ABILITIES.jab.range && facing > 0.8 && now >= a.jabReadyAt && now >= this.reactionUntil) {
        if (tryJab(a, now, deps)) a.jabT = 0.32;
      }
      if (now >= this.abilityCheckAt) {
        this.abilityCheckAt = now + 0.5;
        const pinned = a.damageInLast(2, now) > 22 || (ws?.reloading ?? false);
        if (pinned && a.has('shield') && dist > 6 && now >= a.shieldReadyAt && Math.random() < 0.35 + p.caution * 0.4) {
          tryShield(a, now, deps, Math.atan2(-(t.pos.x - a.pos.x), -(t.pos.z - a.pos.z)));
        }
        // they're up on a ledge / shelf: hook up after them
        if (a.has('grapple') && t.pos.y - a.pos.y > 4 && dist < 34 && now >= a.grappleReadyAt && Math.random() < 0.25 + p.aggression * 0.3) {
          this.grappleToward(t.pos, now);
        }
        // sneak in invisible to get close (aggressive toys)
        if (a.has('cloak') && !a.cloaked && now >= a.cloakReadyAt && dist > 14 && dist < 30 && Math.random() < p.aggression * 0.08) {
          if (tryCloak(a, now, deps)) this.sneaking = true;
        }
      }
      return;
    }
    if (now < this.abilityCheckAt) return;
    this.abilityCheckAt = now + 0.6;
    // long climb ahead (shelves, desk, bed): hook to the goal when it's in sight
    if (a.has('grapple') && this.hasGoal && this.goal.y - a.pos.y > 5 && now >= a.grappleReadyAt && Math.random() < 0.3) {
      if (this.grappleToward(this.goal, now)) return;
      // or to a node on the way up
      if (this.path) {
        for (let i = this.path.length - 1; i > this.pathIdx; i -= 2) {
          const n = this.w.nav.nodes[this.path[i]].pos;
          if (n.y - a.pos.y > 4 && this.grappleToward(n, now)) return;
        }
      }
    }
    // conquest: sometimes slip into a contested sector unseen
    const obj = this.w.objective(a);
    if (obj && a.has('cloak') && !a.cloaked && now >= a.cloakReadyAt && this.state === 'objective') {
      const d = a.pos.distanceTo(obj.pos);
      if (d > 12 && d < 30 && Math.random() < 0.12) {
        if (tryCloak(a, now, deps)) this.sneaking = true;
      }
    }
  }

  private pickPickup(hpFrac: number, now: number): THREE.Vector3 | null {
    const a = this.actor;
    const list = this.w.pickups().filter((x) => x.available);
    let best: THREE.Vector3 | null = null;
    let bestD = Infinity;
    for (const pk of list) {
      const d = pk.pos.distanceTo(a.pos);
      let want = 0;
      if ((pk.kind === 'health') && hpFrac < 0.8) want = 1;
      else if (pk.kind === 'shield' && a.shield < 25) want = 0.35;
      else if (['power', 'turbo', 'infinite'].includes(pk.kind)) want = 0.25;
      else if (pk.kind.startsWith('weapon:')) {
        const wid = pk.kind.slice(7) as WeaponId;
        if (this.personality.favorite.includes(wid) && !a.weapons.some((w) => w?.id === wid)) want = 0.5;
      }
      if (want <= 0 || d > 34) continue;
      if (Math.random() > want) continue;
      if (d < bestD) {
        bestD = d;
        best = pk.pos;
      }
    }
    void now;
    return best ? best.clone() : null;
  }

  private chooseWeapon(dist: number, now: number) {
    const a = this.actor;
    const cur = a.weapon;
    if (!cur || (cur.reloading && cur.reloadProgress > 0.5)) return;
    const other = a.weapons[a.slot === 0 ? 1 : 0];
    if (!other || (other.mag <= 0 && other.reserve <= 0 && !other.isEnergy)) return;
    const fit = (id: WeaponId) => {
      const [lo, hi] = WEAPONS[id].botRange;
      return dist < lo ? lo - dist : dist > hi ? dist - hi : 0;
    };
    if (fit(other.id) + 4 < fit(cur.id) && now - cur.lastShot > 0.4) this.switchSlot(a.slot === 0 ? 1 : 0, now);
  }

  private switchSlot(slot: number, now: number) {
    const a = this.actor;
    if (!a.weapons[slot] || slot === a.slot) return;
    a.weapon?.cancelReload();
    a.slot = slot;
    a.weapon!.equip(now, 0.4);
    this.setModelWeapon();
  }

  // ------------------------------------------------------------------ navigation
  private setGoal(p: THREE.Vector3) {
    if (this.hasGoal && this.goal.distanceToSquared(p) < 4 && this.path) return;
    this.goal.copy(p);
    this.hasGoal = true;
    const nav = this.w.nav;
    const s = nav.nearest(this.actor.pos, true, 6);
    const g = nav.nearest(p, false, 6);
    this.path = nav.path(s, g);
    this.pathIdx = 0;
    if (!this.path) this.hasGoal = false;
  }
  private inZone(o: { pos: THREE.Vector3; radius: number; height: number }) {
    const a = this.actor;
    const dx = a.pos.x - o.pos.x, dz = a.pos.z - o.pos.z;
    return dx * dx + dz * dz < (o.radius - 0.4) ** 2 && a.pos.y > o.pos.y - 1.2 && a.pos.y < o.pos.y + o.height;
  }
  /** A walkable spot inside the capture zone. */
  private zoneSpot(o: { pos: THREE.Vector3; radius: number; height: number }) {
    const nav = this.w.nav;
    const ids = nav.near(o.pos, o.radius - 0.6).filter((id) => {
      const y = nav.nodes[id].pos.y;
      return y > o.pos.y - 1 && y < o.pos.y + o.height;
    });
    return ids.length ? nav.nodes[pick(ids)].pos.clone() : o.pos.clone();
  }
  private randomPatrolGoal() {
    const nav = this.w.nav;
    const spawns = this.w.spawnPoints;
    // objective modes: hunters prowl the approaches to the toy box
    const obj = this.w.objective(this.actor);
    if (obj && this.role === 'hunter') {
      const id = nav.random((n) => n.pos.distanceTo(obj.pos) > obj.radius + 2 && n.pos.distanceTo(obj.pos) < 16);
      if (nav.nodes[id]) return nav.nodes[id].pos;
    }
    // team modes: sometimes regroup with a teammate
    if (this.w.teamMode && Math.random() < 0.4) {
      const mates = this.w.actors().filter((o) => o !== this.actor && o.alive && o.team === this.actor.team);
      if (mates.length) {
        const m = pick(mates);
        const id = nav.random((n) => n.pos.distanceTo(m.pos) < 7 && n.pos.distanceTo(this.actor.pos) > 4);
        if (nav.nodes[id] && nav.nodes[id].pos.distanceTo(m.pos) < 7) return nav.nodes[id].pos;
      }
    }
    // pick a zone first so toys spread around the whole room instead of clumping in the middle
    const zones = this.w.zones.filter((z) => z.name !== 'Play Rug');
    const z = Math.random() < 0.8 ? pick(zones) : null;
    const id = nav.random(
      (n) =>
        n.open >= 4 &&
        !spawns.some((s) => s.distanceToSquared(n.pos) < 30) &&
        n.pos.distanceTo(this.actor.pos) > 10 &&
        (!z || (n.pos.x >= z.min[0] && n.pos.x <= z.max[0] && n.pos.z >= z.min[1] && n.pos.z <= z.max[1])),
    );
    return nav.nodes[id]?.pos ?? this.actor.pos;
  }
  private findCover(from: THREE.Vector3): THREE.Vector3 | null {
    const nav = this.w.nav;
    const a = this.actor;
    const ids = nav.near(a.pos, 14);
    let best: THREE.Vector3 | null = null;
    let bestScore = Infinity;
    const eye = from.clone().setY(from.y + 1.5);
    let checks = 0;
    for (let i = ids.length - 1; i > 0 && checks < 24; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [ids[i], ids[j]] = [ids[j], ids[i]];
    }
    for (const id of ids) {
      const n = nav.nodes[id];
      if (Math.abs(n.pos.y - a.pos.y) > 3) continue;
      checks++;
      if (checks > 24) break;
      const chest = n.pos.clone().setY(n.pos.y + 1.1);
      if (this.w.phys.los(eye, chest)) continue;
      const score = n.pos.distanceTo(a.pos) - n.pos.distanceTo(from) * 0.5;
      if (score < bestScore) {
        bestScore = score;
        best = n.pos;
      }
    }
    return best ? best.clone() : null;
  }
  /** Steering toward the current path node. Returns world wish direction (unnormalized). */
  private followPath(out: THREE.Vector3): boolean {
    const a = this.actor;
    if (!this.path || this.pathIdx >= this.path.length) {
      if (this.hasGoal) {
        out.subVectors(this.goal, a.pos).setY(0);
        if (out.length() < 0.8) {
          this.hasGoal = false;
          return false;
        }
        return true;
      }
      return false;
    }
    const nav = this.w.nav;
    // riding an elevator: wait for it, step on, stand still, step off
    if (this.pathIdx > 0) {
      const l = nav.linkBetween(this.path[this.pathIdx - 1], this.path[this.pathIdx]);
      if (l && l.elevator !== undefined) {
        const e = this.w.elevators()[l.elevator];
        if (e) return this.rideElevator(e, nav.nodes[this.path[this.pathIdx - 1]].pos, nav.nodes[this.path[this.pathIdx]].pos, out);
      }
    }
    this.waitingLift = false;
    let node = nav.nodes[this.path[this.pathIdx]].pos;
    const dx = node.x - a.pos.x, dz = node.z - a.pos.z;
    if (dx * dx + dz * dz < 0.9 && Math.abs(node.y - a.pos.y) < 1.4) {
      this.pathIdx++;
      if (this.pathIdx >= this.path.length) {
        out.subVectors(this.goal, a.pos).setY(0);
        return out.lengthSq() > 0.6;
      }
      node = nav.nodes[this.path[this.pathIdx]].pos;
    }
    // look one node ahead to smooth corners
    if (this.pathIdx + 1 < this.path.length) {
      const nxt = nav.nodes[this.path[this.pathIdx + 1]].pos;
      if (Math.abs(nxt.y - a.pos.y) < 0.4 && Math.abs(node.y - a.pos.y) < 0.4 && a.pos.distanceTo(node) < 2.2) {
        if (this.w.phys.los(_v.set(a.pos.x, a.pos.y + 0.6, a.pos.z), _w.set(nxt.x, nxt.y + 0.6, nxt.z), true)) node = nxt;
      }
    }
    out.set(node.x - a.pos.x, 0, node.z - a.pos.z);
    // ledges that need a hop
    if (this.pathIdx > 0) {
      const l = nav.linkBetween(this.path[this.pathIdx - 1], this.path[this.pathIdx]);
      if (l?.jump && a.grounded && out.length() < 1.7 && node.y > a.pos.y + 0.4) this.intent.jump = true;
    }
    return true;
  }

  private rideElevator(e: ElevatorView, from: THREE.Vector3, to: THREE.Vector3, out: THREE.Vector3): boolean {
    const a = this.actor;
    const up = to.y > from.y;
    const destParked = up ? 'top' : 'bottom';
    const hereParked = up ? 'bottom' : 'top';
    const dxz = Math.hypot(a.pos.x - e.center.x, a.pos.z - e.center.z);
    const onPlat = dxz < 1.15 && Math.abs(a.pos.y - e.platformY) < 0.6;
    this.waitingLift = true;
    if (onPlat) {
      if (e.parked === destParked) {
        // arrived: walk off to the exit node
        out.set(to.x - a.pos.x, 0, to.z - a.pos.z);
        if (out.lengthSq() < 0.8) this.pathIdx++;
        return true;
      }
      // ride: stay in the middle
      out.set(e.center.x - a.pos.x, 0, e.center.z - a.pos.z);
      if (out.lengthSq() < 0.15) out.set(0, 0, 0);
      return true;
    }
    if (Math.abs(a.pos.y - to.y) < 1 && Math.hypot(a.pos.x - to.x, a.pos.z - to.z) < 2.5) {
      // already off at the far end (or carried there): carry on
      this.pathIdx++;
      this.waitingLift = false;
      return true;
    }
    if (e.parked === hereParked && e.leaveIn > 0.8) {
      out.set(e.center.x - a.pos.x, 0, e.center.z - a.pos.z);
      return true;
    }
    // wait next to the shaft (never underneath it)
    out.set(from.x - a.pos.x, 0, from.z - a.pos.z);
    if (out.lengthSq() < 0.5) out.set(0, 0, 0);
    if (Math.abs(a.pos.y - from.y) > 3 && Math.abs(a.pos.y - to.y) > 3) {
      // fell off somewhere in between: give up on this path
      this.path = null;
      this.hasGoal = false;
      this.waitingLift = false;
      return false;
    }
    return true;
  }

  // ------------------------------------------------------------------ main update
  update(dt: number, now: number) {
    const a = this.actor;
    const it = this.intent;
    it.jump = it.dash = it.crouchPressed = false;
    it.sprint = false;
    it.crouch = false;
    it.wish.set(0, 0, 0);
    if (!a.alive) return;
    this.thinkAt -= dt;
    if (this.thinkAt <= 0) {
      this.thinkAt = rand(0.12, 0.2);
      this.think(now);
    }
    // after a Spring Hook the old path is useless
    if (this.wasGrappling && !a.grapple) {
      this.path = null;
      this.hasGoal = false;
      this.progressAt = now + 1;
      this.progressPos.copy(a.pos);
    }
    this.wasGrappling = !!a.grapple;
    if (!a.cloaked) this.sneaking = false;
    if (!a.grapple) this.useAbilities(now);
    const p = this.personality;
    const tgt = this.target;
    const dir = new THREE.Vector3();
    let moving = false;
    switch (this.state) {
      case 'patrol': {
        if (!this.hasGoal) this.setGoal(this.randomPatrolGoal());
        moving = this.followPath(dir);
        if (!moving) this.hasGoal = false;
        it.sprint = Math.random() < 0.02 ? !it.sprint : p.aggression > 0.6;
        break;
      }
      case 'search': {
        if (!this.hasGoal) this.setGoal(this.lastKnown);
        moving = this.followPath(dir);
        it.sprint = p.aggression > 0.5;
        if (!moving) {
          this.lookAround += dt;
          a.yaw += dt * 1.6;
          if (this.lookAround > 2.2) {
            this.lookAround = 0;
            this.setState('patrol', now);
          }
        }
        break;
      }
      case 'objective': {
        const obj = this.w.objective(a);
        if (!obj) {
          this.setState('patrol', now);
          break;
        }
        const inside = this.inZone(obj);
        if (!inside) {
          if (!this.hasGoal || this.goal.distanceTo(obj.pos) > obj.radius + 0.5) this.setGoal(this.zoneSpot(obj));
          moving = this.followPath(dir);
          it.sprint = true;
          if (!moving) this.hasGoal = false;
          if (a.pos.distanceTo(obj.pos) > 25 && Math.random() < p.dashUse * 0.01) it.dash = true;
        } else {
          // hold the box: shuffle around inside it and watch the approaches
          if (now > this.holdAt || !this.hasGoal) {
            this.holdAt = now + rand(1.5, 3.5);
            this.setGoal(this.zoneSpot(obj));
          }
          moving = this.followPath(dir);
          if (!moving) {
            a.yaw += dt * 0.9 * (Math.sin(now * 0.7 + this.actor.id) > 0 ? 1 : -1);
            a.pitch *= 1 - Math.min(1, dt * 3);
          }
          it.crouch = p.caution > 0.6 && Math.sin(now * 0.9 + a.id) > 0.3;
        }
        break;
      }
      case 'revive': {
        const t = this.reviveTarget;
        if (!t) break;
        const d = Math.hypot(t.pos.x - a.pos.x, t.pos.z - a.pos.z);
        if (d < 1.5 && Math.abs(t.pos.y - a.pos.y) < 2) {
          // kneel next to them and hold on
          it.crouch = true;
          moving = false;
        } else {
          if (!this.hasGoal) this.setGoal(t.pos);
          moving = this.followPath(dir);
          it.sprint = true;
          if (!moving && d < 2.3) moving = false;
          else if (!moving) this.hasGoal = false;
        }
        break;
      }
      case 'seekPickup': {
        if (this.pickupTarget && !this.hasGoal) this.setGoal(this.pickupTarget);
        moving = this.followPath(dir);
        it.sprint = true;
        if (!moving) this.setState('patrol', now);
        break;
      }
      case 'retreat':
      case 'reload': {
        if (!this.hasGoal && tgt) {
          const c = this.findCover(tgt.pos);
          if (c) this.setGoal(c);
          else {
            // run directly away
            const away = a.pos.clone().sub(tgt.pos).setY(0).normalize().multiplyScalar(8).add(a.pos);
            this.setGoal(away);
          }
        }
        moving = this.followPath(dir);
        it.sprint = !this.targetVisible || this.state === 'retreat';
        if (this.wantDash && moving) {
          it.dash = true;
          this.wantDash = false;
        }
        break;
      }
      case 'engage': {
        if (!tgt) break;
        const dist = tgt.pos.distanceTo(a.pos);
        const ws = a.weapon;
        const [lo, hi] = ws ? ws.cfg.botRange : [5, 30];
        const ideal = lo + (hi - lo) * (0.55 - p.aggression * 0.4);
        const toT = _v.subVectors(tgt.pos, a.pos).setY(0).normalize();
        const side = _w.set(-toT.z, 0, toT.x).multiplyScalar(this.strafeDir);
        if (now > this.strafeChangeAt) {
          this.strafeDir = Math.random() < 0.5 ? -1 : 1;
          this.strafeChangeAt = now + rand(0.5, 1.8) * (1.3 - p.jumpiness * 0.6);
        }
        if (now < this.coverUntil) {
          if (!this.hasGoal) {
            const c = this.findCover(tgt.pos);
            if (c) this.setGoal(c);
          }
          moving = this.followPath(dir);
        } else if (dist > hi * 1.05 || (!this.targetVisible && now - this.noLosSince > 0.6)) {
          if (!this.hasGoal || this.goal.distanceToSquared(tgt.pos) > 16) this.setGoal(tgt.pos);
          moving = this.followPath(dir);
          it.sprint = dist > 14;
          if (dist > 22 && Math.random() < p.dashUse * 0.01) it.dash = true;
        } else {
          this.hasGoal = false;
          dir.copy(side);
          if (dist > ideal + 3) dir.addScaledVector(toT, 0.8);
          else if (dist < ideal - 3) dir.addScaledVector(toT, -0.8);
          moving = true;
          // don't walk off high ledges while strafing
          const probe = a.pos.clone().addScaledVector(dir.clone().normalize(), 1.2).setY(a.pos.y + 0.5);
          const drop = this.w.phys.rayDist(probe, new THREE.Vector3(0, -1, 0), 3, true);
          if (drop > 1.6) {
            this.strafeDir *= -1;
            dir.copy(side).negate();
          }
          if (now > this.jumpAt) {
            this.jumpAt = now + rand(1.2, 4) / (0.3 + p.jumpiness);
            if (Math.random() < p.jumpiness * 0.6) it.jump = true;
            if (p.caution > 0.6 && Math.random() < 0.4) this.crouchUntil = now + rand(0.6, 1.5);
          }
          if (dist < 8 && p.dashUse > 0.6 && Math.random() < 0.004) it.dash = true;
        }
        it.crouch = now < this.crouchUntil;
        break;
      }
    }
    if (moving && dir.lengthSq() > 1e-4) it.wish.copy(dir.setY(0).normalize()).multiplyScalar(p.speed > 1 ? 1 : p.speed);

    // ---------------- unstuck
    if (now > this.progressAt) {
      const moved = a.pos.distanceTo(this.progressPos);
      if (moving && moved < 0.7 && this.state !== 'engage' && !this.waitingLift && !a.grapple) {
        this.stuckCount++;
        this.unstickUntil = now + 0.6;
        this.unstickDir.set(rand(-1, 1), 0, rand(-1, 1)).normalize();
        it.jump = true;
        if (this.stuckCount >= 2) {
          this.hasGoal = false;
          this.path = null;
        }
        if (this.stuckCount >= 5) {
          // last resort: hop to the nearest nav node
          const n = this.w.nav.nearest(a.pos, false, 10);
          if (n >= 0) a.teleport(this.w.nav.nodes[n].pos.clone().setY(this.w.nav.nodes[n].pos.y + 0.05));
          this.stuckCount = 0;
        }
      } else if (moved > 1.5) this.stuckCount = 0;
      this.progressAt = now + 1;
      this.progressPos.copy(a.pos);
    }
    if (now < this.unstickUntil) it.wish.copy(this.unstickDir);

    // ---------------- aim + fire
    this.aim(dt, now, moving);
    // face movement when nothing to look at
    if (!tgt || (!this.targetVisible && this.state !== 'search')) {
      if (it.wish.lengthSq() > 0.01) {
        const want = Math.atan2(-it.wish.x, -it.wish.z);
        a.yaw += clamp(angleWrap(want - a.yaw), -dt * 5, dt * 5);
        a.pitch *= 1 - Math.min(1, dt * 4);
      }
    }
  }

  private aim(dt: number, now: number, moving: boolean) {
    const a = this.actor;
    const t = this.target;
    const d = this.diff;
    const ws = a.weapon;
    this.triggerHeld = false;
    if (!t || !ws) return;
    // aim point: chest or head, with lead for projectile weapons
    const aimPt = this.aimHead ? t.headPos() : t.chestPos();
    if (!this.targetVisible) aimPt.copy(this.lastKnown).setY(this.lastKnown.y + 1.1);
    const eye = a.eyePos();
    const dist = eye.distanceTo(aimPt);
    const wantCharge = ws.cfg.charge ? clamp(0.5 + dist / 28, 0.6, 1) : 1;
    if (ws.cfg.projectile.kind === 'projectile' && this.targetVisible) {
      const spd = ws.cfg.charge ? ws.cfg.charge.minSpeed + (ws.cfg.charge.maxSpeed - ws.cfg.charge.minSpeed) * wantCharge : ws.cfg.projectile.speed;
      const tt = dist / spd;
      aimPt.addScaledVector(t.vel, tt * (0.6 + 0.4 * (1 - d.aimError / 6)));
      if (ws.cfg.projectile.gravity > 0) aimPt.y += 0.5 * ws.cfg.projectile.gravity * tt * tt;
    }
    // smoothly wandering aim error, worse when moving or the target is moving fast
    if (now > this.aimNoiseAt) {
      this.aimNoiseAt = now + rand(0.25, 0.5);
      const err = d.aimError * (1 + (moving ? 0.5 : 0) + clamp(t.speed / 8, 0, 1) * 0.6) * (now < this.reactionUntil + 0.4 ? 1.6 : 1);
      this.aimNoiseTarget.set(rand(-err, err), rand(-err, err) * 0.7);
    }
    this.aimNoise.lerp(this.aimNoiseTarget, 1 - Math.exp(-6 * dt));
    const to = aimPt.sub(eye);
    const wantYaw = Math.atan2(-to.x, -to.z) + this.aimNoise.x * DEG;
    const wantPitch = Math.atan2(to.y, Math.hypot(to.x, to.z)) + this.aimNoise.y * DEG + ws.recoilPitch * DEG * (1 - d.recoilComp);
    const maxTurn = d.turn * DEG * dt;
    const dy = angleWrap(wantYaw - a.yaw);
    a.yaw += clamp(dy, -maxTurn, maxTurn);
    a.pitch += clamp(wantPitch - a.pitch, -maxTurn, maxTurn);
    a.pitch = clamp(a.pitch, -1.4, 1.4);
    // bow: keep the string drawn while we have a target, loose it once it's drawn far enough and on target
    if (ws.cfg.charge) {
      const seen = this.targetVisible || now - this.targetSeenAt < 1.2;
      if (!seen || !t.alive || t.isProtected(now) || (a.cloaked && this.sneaking && dist > 8)) {
        ws.cancelDraw();
        return;
      }
      if (now < this.reactionUntil) {
        this.triggerHeld = ws.drawing;
        return;
      }
      const off = Math.abs(angleWrap(wantYaw - a.yaw)) / DEG + Math.abs(wantPitch - a.pitch) / DEG;
      if (!ws.drawing) {
        this.triggerHeld = off < 25 && dist < ws.cfg.botRange[1] * 1.6;
        return;
      }
      const ready = ws.chargeAt(now) >= wantCharge - 0.02;
      this.triggerHeld = !(ready && this.targetVisible && off < d.fireAngle + 0.6);
      return;
    }
    if (!this.targetVisible || now < this.reactionUntil || t.isProtected(now) || !t.alive) return;
    // sneaking under cloak: don't give ourselves away until it's worth it
    if (a.cloaked && this.sneaking && dist > 9 && this.state !== 'engage') return;
    if (a.cloaked && this.sneaking && dist > 6 && this.state === 'retreat') return;
    const off = Math.abs(angleWrap(wantYaw - a.yaw)) / DEG + Math.abs(wantPitch - a.pitch) / DEG;
    const range = ws.cfg.botRange[1] * 1.6;
    if (off > d.fireAngle + ws.cfg.spread.hip * 0.5 || dist > range) return;
    // trigger discipline: bursts for automatics, human cadence for semi-autos
    if (ws.cfg.auto) {
      if (now > this.burstUntil && now > this.pauseUntil) {
        this.burstUntil = now + rand(0.25, 0.8) * (0.5 + d.burst) * (dist < 12 ? 1.6 : 1);
        this.pauseUntil = this.burstUntil + rand(0.15, 0.45) * (1.4 - d.burst);
      }
      this.triggerHeld = now < this.burstUntil;
    } else {
      this.triggerHeld = now >= this.nextSemiAt;
    }
  }

  /** Fire step (after aim) – returns shots fired this frame. */
  fire(now: number): number {
    const a = this.actor;
    const ws = a.weapon;
    if (!ws || !a.alive) return 0;
    const infinite = a.hasBuff('infinite', now);
    const wasDrawing = ws.drawing;
    const res = ws.pullTrigger(now, this.triggerHeld, this.triggerHeld, infinite);
    if (ws.drawing && !wasDrawing && a.pos.distanceTo(this.w.listenerPos) < 18) this.w.audio.bowDraw(false, a.chestPos());
    if (res <= 0) return 0;
    if (!ws.cfg.auto) this.nextSemiAt = now + ws.interval + rand(0.05, 0.3) * (ws.cfg.id === 'thunderspring' ? 2 : 1);
    a.spawnProtectUntil = Math.min(a.spawnProtectUntil, now);
    const eye = a.eyePos();
    const muzzle = this.muzzleWorld(new THREE.Vector3());
    for (let i = 0; i < res; i++) {
      const dir = a.forward(new THREE.Vector3());
      const spread = ws.spread(ws.overlay ? 0.85 : 0.3, clamp(a.speed / 5.5, 0, 1.3), !a.grounded);
      this.w.combat.fire(a, ws, eye, dir, muzzle, spread);
      ws.kick(false);
      a.fireKick = 1;
      this.w.fx.muzzle(muzzle, dir, ws.cfg.colors.glow, ws.cfg.pellets > 1 || ws.id === 'crayonCannon' ? 1.4 : 0.8);
      if (ws.id === 'starlightZapper') this.w.fx.flashLight(muzzle, ws.cfg.colors.glow, 6, 0.05, 6);
      const dl = muzzle.distanceTo(this.w.listenerPos);
      if (dl < 80) this.w.audio.gunshot(ws.id, muzzle, false);
    }
    return res;
  }

  animState(now: number) {
    const a = this.actor;
    const ws = a.weapon;
    return {
      speed: a.speed,
      grounded: a.grounded,
      vy: a.vel.y,
      crouch: a.crouchT,
      aimPitch: a.pitch,
      reload: ws?.reloading ? Math.max(0.01, ws.reloadProgress) : 0,
      fireKick: a.fireKick,
      hit: a.hitFlinch,
      dashing: a.dashing,
      sliding: a.sliding,
      protectedShimmer: a.isProtected(now),
    };
  }

  dispose() {
    for (const m of this.weaponModels.values()) m.traverse((o) => (o as THREE.Mesh).isMesh && (o as THREE.Mesh).geometry.dispose());
    this.weaponModels.clear();
  }
}

/** Bots bring one of their favorite weapons plus the pistol (weapons come from loadouts, not pick-ups). */
export const pickBotLoadout = (p: Personality): [WeaponId, WeaponId] => [pick(p.favorite), 'plasti9'];

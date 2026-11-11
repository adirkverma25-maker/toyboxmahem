import * as THREE from 'three';
import { Actor } from '../entities/Actor';
import { Physics } from '../physics/Physics';
import { rand } from '../core/math';
import { CONQUEST, CONQUEST_HOMES, DRAW, HILL_SITES, HillSite, MODES, ModeDef, ModeId, SECTORS, SectorDef, TAKEOVER } from './modes';

export type MatchPhase = 'countdown' | 'playing' | 'ended';
export interface SectorEvent {
  kind: 'captured' | 'neutralized' | 'attacked';
  sector: number;
  team: number; // capturing team / team that lost it
}
export type MatchEvent = number | 'go' | 'end' | 'blockdrop' | 'hillwarn' | 'hillmove' | 'hilltaken' | 'hillcontested' | SectorEvent;

export interface HillState {
  site: HillSite;
  pos: THREE.Vector3; // snapped to the surface
  next: HillSite;
  timeLeft: number;
  counts: number[];
  owner: number; // team currently scoring, -1 none
  contested: boolean;
}

export interface SectorState {
  def: SectorDef;
  pos: THREE.Vector3; // snapped to the surface
  /** team that controls it (-1 neutral) */
  owner: number;
  /** 0..1. Owned: how much of the hold is left. Neutral: how far `progressTeam` has captured it. */
  progress: number;
  progressTeam: number;
  counts: number[];
  contested: boolean;
  /** team whose toys are changing it right now (-1 none) */
  active: number;
  lastAttackNote: number;
}

/**
 * Match rules for every mode.
 *  ffa      - first actor to the target, or most pops at time
 *  tdm      - team pops, first team to the target
 *  takeover - teams score by holding the moving toy box
 *  conquest - three teams capture sectors, first to hold 4 of 6
 */
export class Match {
  mode: ModeDef = MODES.ffa;
  phase: MatchPhase = 'countdown';
  countdown = 3;
  timeLeft = 600;
  winner: Actor | null = null;
  /** -1 = no team result (ffa), team index for a team win, DRAW (-2) for a tie */
  winnerTeam = -1;
  endReason: 'score' | 'time' = 'score';
  /** pops (tdm), wind-up (takeover) or sectors held (conquest) per team */
  teamScores: number[] = [0, 0];
  hill: HillState | null = null;
  sectors: SectorState[] = [];
  startedAt = 0;
  blockDropsEnabled = Math.random() < 0.65;
  nextBlockDrop = rand(70, 130);
  endedAt = 0;
  private lastCount = 4;
  private siteBag: HillSite[] = [];
  /** extra spawn pool for actors that should start on the high shelves (FFA newcomers) */
  shelfSpawns: THREE.Vector3[] = [];

  constructor(private phys: Physics, public spawnPoints: THREE.Vector3[]) {}

  get killTarget() {
    return this.mode.scoreTarget;
  }
  get teams() {
    return this.mode.teams;
  }
  get teamCount() {
    return this.mode.teamCount;
  }

  setMode(id: ModeId) {
    this.mode = MODES[id];
  }

  reset(now: number) {
    this.phase = 'countdown';
    this.countdown = 3;
    this.timeLeft = this.mode.timeLimit;
    this.winner = null;
    this.winnerTeam = -1;
    this.teamScores = Array.from({ length: Math.max(2, this.mode.teamCount) }, () => 0);
    this.startedAt = now;
    this.blockDropsEnabled = Math.random() < 0.65;
    this.nextBlockDrop = rand(70, 130);
    this.lastCount = 4;
    this.siteBag = [];
    this.hill = null;
    this.sectors = [];
    if (this.mode.id === 'takeover') {
      const first = this.drawSite();
      this.hill = { site: first, pos: this.snap(first), next: this.drawSite(first), timeLeft: TAKEOVER.hillDuration, counts: [0, 0], owner: -1, contested: false };
    }
    if (this.mode.id === 'conquest') {
      this.sectors = SECTORS.map((def, i) => {
        const home = CONQUEST_HOMES.indexOf(i);
        return { def, pos: this.snap(def), owner: home, progress: home >= 0 ? 1 : 0, progressTeam: home, counts: [0, 0, 0], contested: false, active: -1, lastAttackNote: -99 };
      });
      this.refreshSectorScores();
    }
  }

  private drawSite(avoid?: HillSite): HillSite {
    if (!this.siteBag.length) this.siteBag = [...HILL_SITES].sort(() => Math.random() - 0.5);
    let s = this.siteBag.pop()!;
    if (s === avoid) {
      if (!this.siteBag.length) this.siteBag = HILL_SITES.filter((x) => x !== avoid).sort(() => Math.random() - 0.5);
      const other = this.siteBag.pop()!;
      this.siteBag.unshift(s);
      s = other;
    }
    return s;
  }
  /** Put the zone exactly on whatever surface is there. */
  private snap(site: HillSite) {
    const p = site.pos.clone();
    const d = this.phys.rayDist(new THREE.Vector3(p.x, p.y + 2.5, p.z), new THREE.Vector3(0, -1, 0), 6, true);
    if (d !== Infinity) p.y = p.y + 2.5 - d;
    return p;
  }

  /** Called for every elimination. Returns true if it scored. */
  onKill(killer: Actor | null, victim: Actor) {
    if (this.phase !== 'playing') return false;
    if (this.mode.id === 'tdm' && killer && killer !== victim && killer.team >= 0 && killer.team !== victim.team) {
      this.teamScores[killer.team]++;
      return true;
    }
    return false;
  }

  /** Ranked standings of individual toys. */
  standings(actors: Actor[]) {
    return [...actors].sort((a, b) => b.kills - a.kills || a.deaths - b.deaths || a.scoreAt - b.scoreAt);
  }
  leader(actors: Actor[]) {
    return this.standings(actors)[0];
  }
  /** Score shown for an actor or team leader comparisons. */
  topScore(actors: Actor[]) {
    if (this.teams) return Math.max(...this.teamScores);
    return this.leader(actors)?.kills ?? 0;
  }
  /** Teams ordered best first. */
  teamOrder() {
    return this.teamScores.map((s, t) => ({ t, s })).sort((a, b) => b.s - a.s).map((x) => x.t);
  }

  private inCylinder(a: Actor, pos: THREE.Vector3, radius: number, height: number) {
    if (!a.alive) return false;
    const dx = a.pos.x - pos.x, dz = a.pos.z - pos.z;
    return dx * dx + dz * dz <= radius * radius && a.pos.y > pos.y - 1.2 && a.pos.y < pos.y + height;
  }
  inHill(a: Actor) {
    const h = this.hill;
    return !!h && this.inCylinder(a, h.pos, h.site.radius, h.site.height);
  }
  /** Index of the conquest sector this actor is standing in, or -1. */
  sectorOf(a: Actor) {
    for (let i = 0; i < this.sectors.length; i++) {
      const s = this.sectors[i];
      if (this.inCylinder(a, s.pos, s.def.radius, s.def.height)) return i;
    }
    return -1;
  }
  sectorsOwned(team: number) {
    let n = 0;
    for (const s of this.sectors) if (s.owner === team) n++;
    return n;
  }
  private refreshSectorScores() {
    for (let t = 0; t < this.teamScores.length; t++) this.teamScores[t] = this.sectorsOwned(t);
  }

  private updateSectors(dt: number, actors: Actor[], now: number, out: MatchEvent[]) {
    for (let i = 0; i < this.sectors.length; i++) {
      const s = this.sectors[i];
      const counts = [0, 0, 0];
      for (const a of actors) if (a.team >= 0 && this.inCylinder(a, s.pos, s.def.radius, s.def.height)) counts[a.team]++;
      s.counts = counts;
      const present = counts.map((c, t) => (c > 0 ? t : -1)).filter((t) => t >= 0);
      s.contested = present.length > 1;
      s.active = -1;
      if (s.contested) continue; // frozen while two or more teams are inside
      if (present.length === 0) {
        // abandoned half-captures drain away; a damaged hold slowly repairs itself only with someone inside
        if (s.owner < 0 && s.progress > 0) {
          s.progress = Math.max(0, s.progress - CONQUEST.decayRate * dt);
          if (s.progress <= 0) s.progressTeam = -1;
        }
        continue;
      }
      const t = present[0];
      const speed = 1 + Math.min(2, counts[t] - 1) * CONQUEST.bonusPerExtraToy;
      if (s.owner === t) {
        if (s.progress < 1) {
          s.progress = Math.min(1, s.progress + (dt * speed) / CONQUEST.neutralizeTime);
          s.active = t;
        }
      } else if (s.owner >= 0) {
        // enemy sector: drain it to neutral
        s.active = t;
        s.progress -= (dt * speed) / CONQUEST.neutralizeTime;
        if (now - s.lastAttackNote > 6) {
          s.lastAttackNote = now;
          out.push({ kind: 'attacked', sector: i, team: s.owner });
        }
        if (s.progress <= 0) {
          const lost = s.owner;
          s.owner = -1;
          s.progress = 0;
          s.progressTeam = -1;
          out.push({ kind: 'neutralized', sector: i, team: lost });
        }
      } else {
        // neutral: someone else's half-capture has to be undone first
        s.active = t;
        if (s.progressTeam >= 0 && s.progressTeam !== t) {
          s.progress -= (dt * speed) / CONQUEST.captureTime;
          if (s.progress <= 0) {
            s.progress = 0;
            s.progressTeam = t;
          }
        } else {
          s.progressTeam = t;
          s.progress += (dt * speed) / CONQUEST.captureTime;
          if (s.progress >= 1) {
            s.progress = 1;
            s.owner = t;
            out.push({ kind: 'captured', sector: i, team: t });
          }
        }
      }
    }
    this.refreshSectorScores();
  }

  update(dt: number, actors: Actor[], now: number): MatchEvent[] {
    const out: MatchEvent[] = [];
    if (this.phase === 'countdown') {
      this.countdown -= dt;
      const c = Math.ceil(this.countdown);
      if (c < this.lastCount && c > 0) {
        out.push(c);
        this.lastCount = c;
      }
      if (this.countdown <= 0) {
        this.phase = 'playing';
        out.push('go');
      }
      return out;
    }
    if (this.phase !== 'playing') return out;
    this.timeLeft -= dt;
    if (this.blockDropsEnabled) {
      this.nextBlockDrop -= dt;
      if (this.nextBlockDrop <= 0) {
        this.nextBlockDrop = rand(80, 150);
        if (this.timeLeft > 20) out.push('blockdrop');
      }
    }
    // toy box takeover scoring + movement
    const h = this.hill;
    if (h) {
      const counts = [0, 0];
      for (const a of actors) if (a.team >= 0 && this.inHill(a)) counts[a.team]++;
      const prevOwner = h.owner, prevContested = h.contested;
      h.counts = counts;
      h.contested = counts[0] > 0 && counts[1] > 0;
      h.owner = h.contested ? -1 : counts[0] > 0 ? 0 : counts[1] > 0 ? 1 : -1;
      if (h.owner >= 0) {
        const extra = Math.min(2, counts[h.owner] - 1);
        this.teamScores[h.owner] = Math.min(this.mode.scoreTarget, this.teamScores[h.owner] + dt * (TAKEOVER.pointsPerSecond + extra * TAKEOVER.bonusPerExtraToy));
      }
      if (h.owner >= 0 && h.owner !== prevOwner) out.push('hilltaken');
      if (h.contested && !prevContested) out.push('hillcontested');
      const before = h.timeLeft;
      h.timeLeft -= dt;
      if (before > TAKEOVER.warnBefore && h.timeLeft <= TAKEOVER.warnBefore) out.push('hillwarn');
      if (h.timeLeft <= 0) {
        h.site = h.next;
        h.pos = this.snap(h.site);
        h.next = this.drawSite(h.site);
        h.timeLeft = TAKEOVER.hillDuration;
        h.owner = -1;
        h.contested = false;
        out.push('hillmove');
      }
    }
    if (this.sectors.length) this.updateSectors(dt, actors, now, out);
    // end conditions
    if (this.teams) {
      const target = this.mode.scoreTarget;
      const reached = this.teamScores.findIndex((s) => s >= target);
      if (reached >= 0) {
        this.endTeam(reached, 'score', actors, now);
        out.push('end');
      } else if (this.timeLeft <= 0) {
        this.timeLeft = 0;
        const fl = this.teamScores.map((s) => Math.floor(s));
        const best = Math.max(...fl);
        const leaders = fl.map((s, t) => (s === best ? t : -1)).filter((t) => t >= 0);
        this.endTeam(leaders.length === 1 ? leaders[0] : DRAW, 'time', actors, now);
        out.push('end');
      }
    } else {
      const top = this.leader(actors);
      if (top && top.kills >= this.killTarget) {
        this.end(top, 'score', now);
        out.push('end');
      } else if (this.timeLeft <= 0) {
        this.timeLeft = 0;
        this.end(top, 'time', now);
        out.push('end');
      }
    }
    return out;
  }

  private end(winner: Actor | null, reason: 'score' | 'time', now: number) {
    if (this.phase === 'ended') return;
    this.phase = 'ended';
    this.winner = winner;
    this.endReason = reason;
    this.endedAt = now;
  }
  private endTeam(team: number, reason: 'score' | 'time', actors: Actor[], now: number) {
    this.winnerTeam = team;
    // MVP of the winning side (or overall on a draw) for the stats screen
    const pool = team >= 0 ? actors.filter((a) => a.team === team) : actors;
    this.end(this.standings(pool)[0] ?? null, reason, now);
  }

  /** Did this actor win? (team win counts for every member) */
  isWinner(a: Actor) {
    if (this.teams) return this.winnerTeam >= 0 && this.winnerTeam === a.team;
    return this.winner === a;
  }

  /** 0 calm .. 3 final moments */
  intensity(actors: Actor[]) {
    if (this.phase !== 'playing') return 1;
    const top = this.topScore(actors);
    const t = this.mode.scoreTarget;
    if (this.mode.id === 'conquest') {
      if (this.timeLeft < 30 || top >= t - 1) return 3;
      if (this.timeLeft < 120 || top >= t - 2) return 2;
      return 1;
    }
    if (this.timeLeft < 30 || top >= t * 0.93) return 3;
    if (this.timeLeft < 120 || top >= t * 0.8) return 2;
    return 1;
  }

  /**
   * Pick a safe spawn: far from living enemies and out of their sight, near your team's side in team modes
   * (near your sectors in Conquest). Picks randomly among the best few so spawns don't become predictable.
   */
  pickSpawn(actor: Actor, actors: Actor[], pool: THREE.Vector3[] = this.spawnPoints) {
    const enemies = actors.filter((a) => a !== actor && a.alive && (actor.team < 0 || a.team !== actor.team));
    const friends = actor.team >= 0 ? actors.filter((a) => a !== actor && a.alive && a.team === actor.team) : [];
    const owned = this.sectors.filter((s) => s.owner === actor.team && actor.team >= 0);
    const scored = pool.map((p) => {
      let minD = 999;
      let seen = 0;
      const eye = p.clone().setY(p.y + 1.5);
      for (const e of enemies) {
        const d = e.pos.distanceTo(p);
        minD = Math.min(minD, d);
        if (d < 40 && this.phys.los(e.eyePos(), eye, true)) seen++;
      }
      let score = Math.min(minD, 40) - seen * 14 + rand(0, 6);
      if (actor.team >= 0 && this.sectors.length) {
        // conquest: spawn behind your own sectors, never on top of someone else's
        if (owned.length) {
          let d = 999;
          for (const s of owned) d = Math.min(d, Math.hypot(p.x - s.pos.x, p.z - s.pos.z));
          score += d < 20 ? 16 - d * 0.3 : -d * 0.25;
        }
        for (const s of this.sectors) {
          if (s.owner === actor.team) continue;
          if (Math.hypot(p.x - s.pos.x, p.z - s.pos.z) < s.def.radius + 6) score -= 30;
        }
      } else if (actor.team >= 0) {
        // Sunrise starts on the bed/desk (north) half, Moonbeam on the dino/garage (south) half
        const own = actor.team === 0 ? p.z < 2 : p.z > -2;
        score += own ? 14 : -10;
      }
      if (friends.length) {
        let fd = 999;
        for (const f of friends) fd = Math.min(fd, f.pos.distanceTo(p));
        if (fd < 18) score += 4;
      }
      if (this.hill) {
        const d = Math.hypot(p.x - this.hill.pos.x, p.z - this.hill.pos.z);
        if (d < this.hill.site.radius + 7) score -= 30;
      }
      return { p, score };
    });
    scored.sort((a, b) => b.score - a.score);
    const pick = scored[Math.floor(Math.random() * Math.min(3, scored.length))];
    // face the middle of the room (forward = (-sin yaw, 0, -cos yaw))
    const yaw = Math.atan2(pick.p.x - 2, pick.p.z - 1);
    return { pos: pick.p.clone().setY(pick.p.y + 0.05), yaw };
  }
}

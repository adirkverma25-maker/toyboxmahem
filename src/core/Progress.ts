import { WEAPON_ORDER, WeaponId, WEAPONS } from '../weapons/weaponConfig';
import type { Difficulty } from './Settings';

/**
 * Coins and weapon unlocks. Saved per account (see Accounts.ts); the guest profile uses the plain key.
 * Everyone starts with the three starters and earns coins by finishing matches.
 */

/** What each weapon costs to unlock. 0 = starter (always owned). */
export const WEAPON_PRICES: Record<WeaponId, number> = {
  foamFury: 0,
  jackBlaster: 0,
  plasti9: 0,
  bubbleBlaster: 300,
  rapidRascal: 300,
  brickbreaker: 600,
  starlightZapper: 600,
  crayonCannon: 800,
  thunderspring: 1000,
  plungerBow: 1000,
  popcornPopper: 1500,
  walloper: 1800,
};
export const STARTERS: WeaponId[] = WEAPON_ORDER.filter((id) => WEAPON_PRICES[id] === 0);

export type Tier = 'Starter' | 'Common' | 'Rare' | 'Epic' | 'Legendary';
export function tierOf(id: WeaponId): Tier {
  const p = WEAPON_PRICES[id];
  return p === 0 ? 'Starter' : p < 500 ? 'Common' : p < 900 ? 'Rare' : p < 1400 ? 'Epic' : 'Legendary';
}
export const TIER_COLORS: Record<Tier, string> = { Starter: '#cfd8dc', Common: '#7dff6b', Rare: '#5ff4ff', Epic: '#c77dff', Legendary: '#ffd23f' };

/** Coin rewards for one finished match. */
export const REWARDS = {
  played: 25,
  perPop: 10,
  perHeadshot: 5,
  perRevive: 15,
  streak5: 25,
  streak10: 50,
  win: 75,
  second: 40,
  third: 20,
  difficulty: { easy: 0.75, normal: 1, hard: 1.35 } as Record<Difficulty, number>,
};

export interface MatchResult {
  kills: number;
  headshots: number;
  revives: number;
  bestStreak: number;
  won: boolean;
  /** free-for-all finishing place (1 = first); 0 in team modes */
  place: number;
  difficulty: Difficulty;
}
export interface Reward {
  lines: [string, number][];
  total: number;
  coinsAfter: number;
  /** locked weapons you can now afford */
  affordable: WeaponId[];
}

interface Saved {
  coins: number;
  owned: string[];
  earnedTotal: number;
}

const KEY = 'toybox-mayhem.progress.v1';

class ProgressStore {
  coins = 0;
  owned = new Set<WeaponId>(STARTERS);
  earnedTotal = 0;
  private ns = '';
  private listeners: (() => void)[] = [];

  constructor() {
    this.load();
  }
  private key() {
    return this.ns ? `${KEY}:${this.ns}` : KEY;
  }
  /** Switch to another account's progress (''= guest). */
  useProfile(ns: string) {
    this.ns = ns;
    this.load();
    this.emit();
  }
  private load() {
    this.coins = 0;
    this.earnedTotal = 0;
    this.owned = new Set(STARTERS);
    try {
      const raw = localStorage.getItem(this.key());
      if (raw) {
        const s: Saved = JSON.parse(raw);
        if (typeof s.coins === 'number' && s.coins >= 0) this.coins = Math.floor(s.coins);
        if (typeof s.earnedTotal === 'number') this.earnedTotal = s.earnedTotal;
        for (const id of s.owned ?? []) if (id in WEAPONS) this.owned.add(id as WeaponId);
      }
    } catch {
      /* bad save: fresh start */
    }
  }
  private save() {
    try {
      const s: Saved = { coins: this.coins, owned: [...this.owned], earnedTotal: this.earnedTotal };
      localStorage.setItem(this.key(), JSON.stringify(s));
    } catch {
      /* storage blocked: progress lasts for this session */
    }
  }
  onChange(fn: () => void) {
    this.listeners.push(fn);
  }
  private emit() {
    for (const l of this.listeners) l();
  }

  owns(id: WeaponId) {
    return this.owned.has(id);
  }
  price(id: WeaponId) {
    return WEAPON_PRICES[id];
  }
  canAfford(id: WeaponId) {
    return !this.owns(id) && this.coins >= WEAPON_PRICES[id];
  }
  /** Spend coins on a weapon. Returns false if it's already owned or too expensive. */
  unlock(id: WeaponId) {
    if (!this.canAfford(id)) return false;
    this.coins -= WEAPON_PRICES[id];
    this.owned.add(id);
    this.save();
    this.emit();
    return true;
  }

  /** Work out and bank the coins for a finished match. */
  award(r: MatchResult): Reward {
    const lines: [string, number][] = [['Finished the match', REWARDS.played]];
    if (r.kills) lines.push([`${r.kills} pop${r.kills === 1 ? '' : 's'}`, r.kills * REWARDS.perPop]);
    if (r.headshots) lines.push([`${r.headshots} headshot pop${r.headshots === 1 ? '' : 's'}`, r.headshots * REWARDS.perHeadshot]);
    if (r.revives) lines.push([`${r.revives} revive${r.revives === 1 ? '' : 's'}`, r.revives * REWARDS.perRevive]);
    if (r.bestStreak >= 10) lines.push([`${r.bestStreak}-pop streak`, REWARDS.streak10]);
    else if (r.bestStreak >= 5) lines.push([`${r.bestStreak}-pop streak`, REWARDS.streak5]);
    if (r.won) lines.push([r.place ? '1st place' : 'Team win', REWARDS.win]);
    else if (r.place === 2) lines.push(['2nd place', REWARDS.second]);
    else if (r.place === 3) lines.push(['3rd place', REWARDS.third]);
    let total = lines.reduce((s, l) => s + l[1], 0);
    const mult = REWARDS.difficulty[r.difficulty] ?? 1;
    if (mult !== 1) {
      const extra = Math.round(total * mult) - total;
      lines.push([`${r.difficulty[0].toUpperCase() + r.difficulty.slice(1)} difficulty ×${mult}`, extra]);
      total += extra;
    }
    this.coins += total;
    this.earnedTotal += total;
    this.save();
    this.emit();
    const affordable = WEAPON_ORDER.filter((id) => this.canAfford(id));
    return { lines, total, coinsAfter: this.coins, affordable };
  }

  /**
   * Redeem a code (Loadout screen). Returns a message for the player, or null if the code is wrong.
   * TOYBOXFREE unlocks every blaster for the current account.
   */
  redeem(code: string): string | null {
    const c = code.trim().toUpperCase();
    if (c === 'TOYBOXFREE') {
      const before = this.owned.size;
      for (const id of WEAPON_ORDER) this.owned.add(id);
      this.save();
      this.emit();
      return this.owned.size > before ? 'Every blaster is unlocked!' : 'You already have every blaster.';
    }
    return null;
  }

  /** Testing / admin helper: not used by the UI. */
  grant(coins: number) {
    this.coins += Math.max(0, Math.floor(coins));
    this.save();
    this.emit();
  }
}

export const progress = new ProgressStore();

/** Keep the saved loadout on weapons you own. */
export function ownedOr(id: string, fallback: WeaponId): WeaponId {
  return id in WEAPONS && progress.owns(id as WeaponId) ? (id as WeaponId) : fallback;
}

import { settings } from '../core/Settings';
import { progress, ownedOr } from '../core/Progress';
import { ABILITY_ORDER, AbilityId, ScopeId, WEAPONS, WEAPON_SCOPES, WeaponId } from './weaponConfig';

/**
 * The player's loadout: two weapons picked in the menu (there are no weapon pick-ups on the maps)
 * plus the scope chosen for each weapon. Saved with the settings.
 */
const valid = (id: string): id is WeaponId => id in WEAPONS;

function scopeMap(): Partial<Record<WeaponId, ScopeId>> {
  try {
    const m = JSON.parse(settings.data.scopes || '{}');
    return m && typeof m === 'object' ? m : {};
  } catch {
    return {};
  }
}

export const loadout = {
  /** Locked weapons fall back to a starter, so a loadout can never hold something you haven't unlocked. */
  get primary(): WeaponId {
    return ownedOr(valid(settings.data.primary) ? settings.data.primary : 'foamFury', 'foamFury');
  },
  get secondary(): WeaponId {
    const s = ownedOr(valid(settings.data.secondary) ? settings.data.secondary : 'plasti9', 'plasti9');
    return s === this.primary ? (this.primary === 'plasti9' ? 'foamFury' : 'plasti9') : s;
  },
  /** Put a weapon in slot 0 (primary) or 1 (secondary). Picking the other slot's weapon swaps them. */
  set(slot: 0 | 1, id: WeaponId) {
    if (!progress.owns(id)) return;
    const p = this.primary, s = this.secondary;
    if (slot === 0) {
      settings.set('primary', id);
      if (id === s) settings.set('secondary', p);
    } else {
      settings.set('secondary', id);
      if (id === p) settings.set('primary', s);
    }
  },
  scope(id: WeaponId): ScopeId {
    const pick = scopeMap()[id];
    return pick && WEAPON_SCOPES[id].includes(pick) ? pick : WEAPON_SCOPES[id][0];
  },
  /** The two equipped abilities: [Ability 1, Ability 2]. */
  get abilities(): [AbilityId, AbilityId] {
    const ids = (settings.data.abilities || '').split(',').filter((x): x is AbilityId => (ABILITY_ORDER as string[]).includes(x));
    const uniq = [...new Set(ids)];
    for (const d of ['dash', 'grapple', 'jab'] as AbilityId[]) if (uniq.length < 2 && !uniq.includes(d)) uniq.push(d);
    return [uniq[0], uniq[1]];
  },
  /** Put an ability in slot 0 or 1. Picking the other slot's ability swaps them. */
  setAbility(slot: 0 | 1, id: AbilityId) {
    const cur = this.abilities;
    const other = cur[slot ? 0 : 1];
    const next: AbilityId[] = [...cur];
    next[slot] = id;
    if (other === id) next[slot ? 0 : 1] = cur[slot];
    settings.set('abilities', next.join(','));
  },
  setScope(id: WeaponId, scope: ScopeId) {
    const m = scopeMap();
    m[id] = scope;
    settings.set('scopes', JSON.stringify(m));
  },
};

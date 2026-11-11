export type Quality = 'low' | 'medium' | 'high';
export type Difficulty = 'easy' | 'normal' | 'hard';

export interface Settings {
  playerName: string;
  sensitivity: number; // 0.1 .. 3
  adsSensitivity: number; // multiplier while aiming
  invertY: boolean;
  /** controller look speed multiplier */
  padSensitivity: number; // 0.3 .. 2.5
  /** controller aim assist: slows the look near an enemy and helps follow them */
  padAimAssist: boolean;
  padVibration: boolean;
  fov: number; // 70..110
  quality: Quality;
  masterVolume: number;
  musicVolume: number;
  sfxVolume: number;
  ambienceVolume: number;
  crosshairColor: string;
  crosshairSize: number; // 0.6..1.8
  crosshairDot: boolean;
  reducedMotion: boolean;
  cameraShake: boolean;
  motionBlur: boolean;
  enemyOutlines: boolean;
  damageNumbers: boolean;
  difficulty: Difficulty;
  showFps: boolean;
  /** which map to load ('bedroom' | 'backyard') */
  map: string;
  /** loadout: weapon ids and a JSON map of weapon -> scope */
  primary: string;
  secondary: string;
  scopes: string;
  /** the two equipped abilities, comma separated (e.g. 'dash,grapple') */
  abilities: string;
  /** custom key / controller bindings (JSON, see Bindings.ts) */
  binds: string;
}

export const DEFAULT_SETTINGS: Settings = {
  playerName: 'You',
  sensitivity: 1,
  adsSensitivity: 0.85,
  invertY: false,
  padSensitivity: 1,
  padAimAssist: true,
  padVibration: true,
  fov: 90,
  quality: 'medium',
  masterVolume: 0.8,
  musicVolume: 0.45,
  sfxVolume: 0.9,
  ambienceVolume: 0.6,
  crosshairColor: '#ffffff',
  crosshairSize: 1,
  crosshairDot: true,
  reducedMotion: false,
  cameraShake: true,
  motionBlur: false,
  enemyOutlines: false,
  damageNumbers: true,
  difficulty: 'normal',
  showFps: false,
  map: 'bedroom',
  primary: 'foamFury',
  secondary: 'plasti9',
  scopes: '{}',
  abilities: 'dash,grapple',
  binds: '{}',
};

export interface Stats {
  matches: number;
  wins: number;
  kills: number;
  deaths: number;
  headshots: number;
  shotsFired: number;
  shotsHit: number;
  bestStreak: number;
  bestMatchKills: number;
  playTimeSec: number;
}

export const DEFAULT_STATS: Stats = {
  matches: 0, wins: 0, kills: 0, deaths: 0, headshots: 0, shotsFired: 0, shotsHit: 0,
  bestStreak: 0, bestMatchKills: 0, playTimeSec: 0,
};

const SKEY = 'toybox-mayhem.settings.v1';
/** The map is chosen for the whole browser (it's built at page load, before an account is applied). */
const MAPKEY = 'toybox-mayhem.map.v1';
function globalMap(fallback: string) {
  try {
    return localStorage.getItem(MAPKEY) || fallback;
  } catch {
    return fallback;
  }
}
const TKEY = 'toybox-mayhem.stats.v1';

function load<T extends object>(key: string, def: T): T {
  try {
    const raw = localStorage.getItem(key);
    if (!raw) return { ...def };
    const parsed = JSON.parse(raw);
    const out: any = { ...def };
    for (const k of Object.keys(def)) {
      if (k in parsed && typeof parsed[k] === typeof (def as any)[k]) out[k] = parsed[k];
    }
    return out;
  } catch {
    return { ...def };
  }
}
function save(key: string, v: object) {
  try {
    localStorage.setItem(key, JSON.stringify(v));
  } catch {
    /* storage blocked: settings still work for this session */
  }
}

type Listener = (s: Settings) => void;

class SettingsStore {
  data: Settings = load(SKEY, DEFAULT_SETTINGS);
  stats: Stats = load(TKEY, DEFAULT_STATS);
  private listeners: Listener[] = [];
  /** account id whose settings + stats are loaded ('' = guest, which uses the original keys) */
  private ns = '';

  constructor() {
    this.data.fov = Math.min(110, Math.max(70, this.data.fov));
    this.data.map = globalMap(this.data.map);
  }
  private skey() {
    return this.ns ? `${SKEY}:${this.ns}` : SKEY;
  }
  private tkey() {
    return this.ns ? `${TKEY}:${this.ns}` : TKEY;
  }
  /**
   * Load another account's settings and career stats. A brand-new account can start from the current
   * settings (controls, video, audio) but always gets the default loadout and empty stats.
   * The map choice stays as it is, because the map is built when the page loads.
   */
  useProfile(ns: string, seedFromCurrent = false) {
    const prev = this.data;
    this.ns = ns;
    let saved = false;
    try {
      saved = !!localStorage.getItem(this.skey());
    } catch {
      /* no storage */
    }
    this.data = load(this.skey(), DEFAULT_SETTINGS);
    if (!saved && seedFromCurrent) {
      this.data = { ...prev, primary: DEFAULT_SETTINGS.primary, secondary: DEFAULT_SETTINGS.secondary, scopes: DEFAULT_SETTINGS.scopes, abilities: DEFAULT_SETTINGS.abilities };
    }
    this.data.map = globalMap(prev.map);
    this.data.fov = Math.min(110, Math.max(70, this.data.fov));
    save(this.skey(), this.data);
    this.stats = load(this.tkey(), DEFAULT_STATS);
    for (const l of this.listeners) l(this.data);
  }
  set<K extends keyof Settings>(k: K, v: Settings[K]) {
    this.data[k] = v;
    save(this.skey(), this.data);
    if (k === 'map') {
      try {
        localStorage.setItem(MAPKEY, String(v));
      } catch {
        /* no storage */
      }
    }
    for (const l of this.listeners) l(this.data);
  }
  reset() {
    // the map and loadout are not "settings" a reset should wipe
    const keep = { map: this.data.map, primary: this.data.primary, secondary: this.data.secondary, scopes: this.data.scopes, abilities: this.data.abilities, binds: this.data.binds };
    this.data = { ...DEFAULT_SETTINGS, ...keep };
    save(this.skey(), this.data);
    for (const l of this.listeners) l(this.data);
  }
  onChange(l: Listener) {
    this.listeners.push(l);
  }
  saveStats() {
    save(this.tkey(), this.stats);
  }
  resetStats() {
    this.stats = { ...DEFAULT_STATS };
    this.saveStats();
  }
}

export const settings = new SettingsStore();

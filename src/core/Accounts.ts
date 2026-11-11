import { settings } from './Settings';
import { progress } from './Progress';
import { binds } from './Bindings';

/**
 * Player accounts, saved in this browser.
 *
 * Each account gets its own coins, unlocks, career stats, loadout, settings and key bindings
 * (they live under storage keys suffixed with the account id). Passwords are never stored:
 * only a salted PBKDF2-SHA256 hash (or a salted, iterated SHA-256 if the browser has no WebCrypto).
 *
 * This is the local implementation of `AccountService`. When the multiplayer server exists, a
 * server-backed implementation can replace it without the menus changing (see docs/multiplayer-and-godot.md).
 */

export interface AccountInfo {
  /** storage id (lower case) */
  id: string;
  /** display name as typed */
  name: string;
  guest: boolean;
}

export interface AccountService {
  current(): AccountInfo;
  register(name: string, password: string): Promise<AccountInfo>;
  login(name: string, password: string): Promise<AccountInfo>;
  playAsGuest(): AccountInfo;
  logout(): void;
  /** true until the player has chosen to log in, register or play as guest once */
  needsChoice(): boolean;
  onSwitch(fn: (a: AccountInfo) => void): void;
}

interface StoredUser {
  name: string;
  salt: string;
  hash: string;
  algo: 'pbkdf2' | 'sha256x';
  iter: number;
  created: number;
}
interface Store {
  users: Record<string, StoredUser>;
  /** logged-in account id, '__guest__' for guest, or null if nobody has chosen yet */
  session: string | null;
}

const KEY = 'toybox-mayhem.accounts.v1';
const GUEST = '__guest__';
const GUEST_INFO: AccountInfo = { id: '', name: 'Guest', guest: true };
export const NAME_RULE = /^[A-Za-z0-9 _-]{2,14}$/;
export const MIN_PASSWORD = 4;

function readStore(): Store {
  try {
    const s = JSON.parse(localStorage.getItem(KEY) || '{}');
    return { users: s.users && typeof s.users === 'object' ? s.users : {}, session: typeof s.session === 'string' ? s.session : null };
  } catch {
    return { users: {}, session: null };
  }
}
function writeStore(s: Store) {
  try {
    localStorage.setItem(KEY, JSON.stringify(s));
  } catch {
    /* storage blocked: the account lasts for this session only */
  }
}

const hex = (b: ArrayBuffer | Uint8Array) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, '0')).join('');
function randomSalt() {
  const a = new Uint8Array(16);
  crypto.getRandomValues(a);
  return hex(a);
}

// ---- small SHA-256 for browsers without crypto.subtle (e.g. some file:// setups)
function sha256(bytes: Uint8Array): Uint8Array {
  const K = new Uint32Array([
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
    0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
    0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ]);
  const H = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
  const l = bytes.length;
  const n = (((l + 9) >> 6) + 1) << 6;
  const m = new Uint8Array(n);
  m.set(bytes);
  m[l] = 0x80;
  const dv = new DataView(m.buffer);
  dv.setUint32(n - 4, l * 8);
  dv.setUint32(n - 8, Math.floor((l * 8) / 2 ** 32));
  const w = new Uint32Array(64);
  const r = (x: number, k: number) => (x >>> k) | (x << (32 - k));
  for (let o = 0; o < n; o += 64) {
    for (let i = 0; i < 16; i++) w[i] = dv.getUint32(o + i * 4);
    for (let i = 16; i < 64; i++) {
      const s0 = r(w[i - 15], 7) ^ r(w[i - 15], 18) ^ (w[i - 15] >>> 3);
      const s1 = r(w[i - 2], 17) ^ r(w[i - 2], 19) ^ (w[i - 2] >>> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) | 0;
    }
    let [a, b, c, d, e, f, g, h] = H;
    for (let i = 0; i < 64; i++) {
      const t1 = (h + (r(e, 6) ^ r(e, 11) ^ r(e, 25)) + ((e & f) ^ (~e & g)) + K[i] + w[i]) | 0;
      const t2 = ((r(a, 2) ^ r(a, 13) ^ r(a, 22)) + ((a & b) ^ (a & c) ^ (b & c))) | 0;
      h = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b; b = a; a = (t1 + t2) | 0;
    }
    H[0] += a; H[1] += b; H[2] += c; H[3] += d; H[4] += e; H[5] += f; H[6] += g; H[7] += h;
  }
  const out = new Uint8Array(32);
  const od = new DataView(out.buffer);
  H.forEach((v, i) => od.setUint32(i * 4, v));
  return out;
}

async function hashPassword(password: string, salt: string, algo: StoredUser['algo'], iter: number): Promise<string> {
  const enc = new TextEncoder();
  if (algo === 'pbkdf2') {
    const key = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
    const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt: enc.encode(salt), iterations: iter }, key, 256);
    return hex(bits);
  }
  let h = sha256(enc.encode(salt + ':' + password));
  for (let i = 1; i < iter; i++) h = sha256(h);
  return hex(h);
}
const hasSubtle = () => typeof crypto !== 'undefined' && !!crypto.subtle && typeof crypto.subtle.deriveBits === 'function';

class LocalAccounts implements AccountService {
  private info: AccountInfo = GUEST_INFO;
  private listeners: ((a: AccountInfo) => void)[] = [];

  constructor() {
    const s = readStore();
    const u = s.session && s.session !== GUEST ? s.users[s.session] : null;
    if (u) this.apply({ id: s.session!, name: u.name, guest: false }, false);
  }

  current() {
    return this.info;
  }
  needsChoice() {
    return readStore().session === null;
  }
  onSwitch(fn: (a: AccountInfo) => void) {
    this.listeners.push(fn);
  }

  /** Point settings, stats, bindings and progress at this account's storage. */
  private apply(a: AccountInfo, notify = true, seedFromCurrent = false) {
    this.info = a;
    settings.useProfile(a.id, seedFromCurrent);
    if (!a.guest) settings.set('playerName', a.name);
    binds.load();
    progress.useProfile(a.id);
    if (notify) for (const l of this.listeners) l(a);
  }

  async register(name: string, password: string) {
    name = name.trim();
    if (!NAME_RULE.test(name)) throw new Error('Names are 2 to 14 letters, numbers, spaces, - or _.');
    if (password.length < MIN_PASSWORD) throw new Error(`Passwords need at least ${MIN_PASSWORD} characters.`);
    const s = readStore();
    const id = name.toLowerCase();
    if (id === GUEST || s.users[id]) throw new Error('That name is taken on this computer. Try another, or log in.');
    const algo: StoredUser['algo'] = hasSubtle() ? 'pbkdf2' : 'sha256x';
    const iter = algo === 'pbkdf2' ? 120000 : 4000;
    const salt = randomSalt();
    const hash = await hashPassword(password, salt, algo, iter);
    s.users[id] = { name, salt, hash, algo, iter, created: Date.now() };
    s.session = id;
    writeStore(s);
    // a new account keeps your controls and settings but starts its own coins, unlocks and stats
    this.apply({ id, name, guest: false }, true, true);
    return this.info;
  }

  async login(name: string, password: string) {
    const s = readStore();
    const id = name.trim().toLowerCase();
    const u = s.users[id];
    if (!u) throw new Error('No account with that name on this computer.');
    if (u.algo === 'pbkdf2' && !hasSubtle()) throw new Error('This browser page cannot check that password. Open the game in Chrome or Edge.');
    const hash = await hashPassword(password, u.salt, u.algo, u.iter);
    if (hash !== u.hash) throw new Error('Wrong password.');
    s.session = id;
    writeStore(s);
    this.apply({ id, name: u.name, guest: false });
    return this.info;
  }

  playAsGuest() {
    const s = readStore();
    s.session = GUEST;
    writeStore(s);
    this.apply(GUEST_INFO);
    return this.info;
  }

  logout() {
    this.playAsGuest();
  }

  /** Names of accounts saved in this browser (for the login screen). */
  savedNames(): string[] {
    return Object.values(readStore().users).map((u) => u.name);
  }
}

export const accounts = new LocalAccounts();

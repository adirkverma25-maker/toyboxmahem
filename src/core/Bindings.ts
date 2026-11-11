import { settings } from './Settings';

/** Everything the player can rebind. Esc (pause), the mouse wheel (swap weapon) and the controller's
 * Menu button (pause) and D-pad-in-menus are fixed. */
export type Action =
  | 'forward' | 'back' | 'left' | 'right'
  | 'jump' | 'crouch' | 'sprint'
  | 'fire' | 'aim' | 'reload' | 'revive'
  | 'swap' | 'weapon1' | 'weapon2'
  | 'ability1' | 'ability2'
  | 'inspect' | 'scoreboard';

export interface ActionDef {
  id: Action;
  label: string;
  /** default keyboard/mouse codes (KeyboardEvent.code or Mouse0..4), '' = none */
  kb: [string, string];
  /** default controller button (standard mapping index), -1 = none */
  pad: number;
  /** movement comes from the left stick on a controller */
  stick?: string;
}

export const ACTIONS: ActionDef[] = [
  { id: 'forward', label: 'Move forward', kb: ['KeyW', ''], pad: -1, stick: 'Left stick' },
  { id: 'back', label: 'Move back', kb: ['KeyS', ''], pad: -1, stick: 'Left stick' },
  { id: 'left', label: 'Move left', kb: ['KeyA', ''], pad: -1, stick: 'Left stick' },
  { id: 'right', label: 'Move right', kb: ['KeyD', ''], pad: -1, stick: 'Left stick' },
  { id: 'jump', label: 'Jump', kb: ['Space', ''], pad: 0 },
  { id: 'crouch', label: 'Crouch / slide', kb: ['ControlLeft', 'KeyC'], pad: 1 },
  { id: 'sprint', label: 'Sprint (controller: toggles)', kb: ['ShiftLeft', ''], pad: 10 },
  { id: 'fire', label: 'Fire', kb: ['Mouse0', ''], pad: 7 },
  { id: 'aim', label: 'Aim down sights', kb: ['Mouse2', ''], pad: 6 },
  { id: 'reload', label: 'Reload / vent', kb: ['KeyR', ''], pad: 2 },
  { id: 'revive', label: 'Revive teammate (hold)', kb: ['KeyE', ''], pad: 2 },
  { id: 'swap', label: 'Switch weapon', kb: ['', ''], pad: 3 },
  { id: 'weapon1', label: 'Primary weapon', kb: ['Digit1', ''], pad: -1 },
  { id: 'weapon2', label: 'Secondary weapon', kb: ['Digit2', ''], pad: -1 },
  { id: 'ability1', label: 'Ability 1', kb: ['KeyQ', ''], pad: 5 },
  { id: 'ability2', label: 'Ability 2', kb: ['KeyF', ''], pad: 4 },
  { id: 'inspect', label: 'Inspect weapon', kb: ['KeyT', ''], pad: 14 },
  { id: 'scoreboard', label: 'Scoreboard (hold)', kb: ['Tab', ''], pad: 8 },
];

/** Reload and revive may share a button: the game reloads unless a downed teammate is right there. */
const MAY_SHARE: Action[][] = [['reload', 'revive']];
const shareOk = (a: Action, b: Action) => MAY_SHARE.some((g) => g.includes(a) && g.includes(b));

/** Buttons the controller keeps for itself. */
export const PAD_RESERVED = [9]; // Menu / Start = pause

const PAD_NAMES = ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', 'View', 'Menu', 'L3', 'R3', 'D-pad ↑', 'D-pad ↓', 'D-pad ←', 'D-pad →', 'Home'];
export const padLabel = (b: number) => (b < 0 ? '' : PAD_NAMES[b] ?? `Button ${b}`);
/** Short version for the HUD ability icons. */
export const padShort = (b: number) => (b < 0 ? '' : ['A', 'B', 'X', 'Y', 'LB', 'RB', 'LT', 'RT', '⧉', '≡', 'L3', 'R3', '▲', '▼', '◀', '▶', '⌂'][b] ?? `${b}`);

export function keyLabel(code: string): string {
  if (!code) return '';
  const m: Record<string, string> = {
    Mouse0: 'Left click', Mouse1: 'Middle click', Mouse2: 'Right click', Mouse3: 'Mouse 4', Mouse4: 'Mouse 5',
    Space: 'Space', ShiftLeft: 'Shift', ShiftRight: 'R Shift', ControlLeft: 'Ctrl', ControlRight: 'R Ctrl',
    AltLeft: 'Alt', AltRight: 'R Alt', Tab: 'Tab', CapsLock: 'Caps', Enter: 'Enter', Backquote: '`',
    ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→', Minus: '-', Equal: '=',
    BracketLeft: '[', BracketRight: ']', Semicolon: ';', Quote: "'", Comma: ',', Period: '.', Slash: '/', Backslash: '\\',
  };
  if (m[code]) return m[code];
  if (code.startsWith('Key')) return code.slice(3);
  if (code.startsWith('Digit')) return code.slice(5);
  if (code.startsWith('Numpad')) return 'Num ' + code.slice(6);
  return code;
}
/** Short version for the HUD ability icons. */
export function keyShort(code: string): string {
  const s: Record<string, string> = { Mouse0: 'LMB', Mouse1: 'MMB', Mouse2: 'RMB', Mouse3: 'M4', Mouse4: 'M5', Space: 'SPC', ControlLeft: 'CTL', ShiftLeft: 'SHF', CapsLock: 'CAP' };
  return s[code] ?? keyLabel(code);
}

type Saved = { kb?: Partial<Record<Action, [string, string]>>; pad?: Partial<Record<Action, number>> };

class Bindings {
  kb = {} as Record<Action, [string, string]>;
  pad = {} as Record<Action, number>;

  constructor() {
    this.load();
  }
  private defaults() {
    for (const a of ACTIONS) {
      this.kb[a.id] = [...a.kb] as [string, string];
      this.pad[a.id] = a.pad;
    }
  }
  load() {
    this.defaults();
    try {
      const s: Saved = JSON.parse(settings.data.binds || '{}');
      for (const a of ACTIONS) {
        const k = s.kb?.[a.id];
        if (Array.isArray(k) && k.length === 2 && k.every((x) => typeof x === 'string')) this.kb[a.id] = [k[0], k[1]];
        const p = s.pad?.[a.id];
        if (typeof p === 'number' && p >= -1 && p < 17 && !a.stick) this.pad[a.id] = p;
      }
    } catch {
      /* bad save: defaults */
    }
  }
  private save() {
    settings.set('binds', JSON.stringify({ kb: this.kb, pad: this.pad }));
  }
  reset() {
    this.defaults();
    this.save();
  }

  /** Bind a key to an action's slot. If another action used that key, it gets this slot's old key (a swap). */
  setKb(action: Action, slot: 0 | 1, code: string) {
    const old = this.kb[action][slot];
    if (code) {
      for (const a of ACTIONS) {
        if (a.id === action) continue;
        const k = this.kb[a.id];
        for (const i of [0, 1] as const) if (k[i] === code) k[i] = old;
      }
      // same key in both of this action's slots is pointless
      if (this.kb[action][slot ? 0 : 1] === code) this.kb[action][slot ? 0 : 1] = '';
    }
    this.kb[action][slot] = code;
    this.save();
  }
  /** Bind a controller button. Conflicts swap, except reload/revive which may share. */
  setPad(action: Action, btn: number) {
    if (PAD_RESERVED.includes(btn)) return;
    const old = this.pad[action];
    if (btn >= 0) for (const a of ACTIONS) if (a.id !== action && !a.stick && this.pad[a.id] === btn && !shareOk(a.id, action)) this.pad[a.id] = old;
    this.pad[action] = btn;
    this.save();
  }

  /** "Q", "Left click", "RB"... for the device in use ('' when unbound). */
  label(action: Action, pad: boolean, short = false): string {
    if (pad) {
      const def = ACTIONS.find((a) => a.id === action)!;
      if (def.stick) return def.stick;
      return short ? padShort(this.pad[action]) : padLabel(this.pad[action]);
    }
    const [a, b] = this.kb[action];
    const f = short ? keyShort : keyLabel;
    return f(a || b);
  }
}

export const binds = new Bindings();

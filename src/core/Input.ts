import { settings } from './Settings';
import { Action, binds } from './Bindings';

const TRIGGER_ON = 0.3;
/** Standard-mapping buttons the menus use (fixed, not rebindable). */
export const PAD = { A: 0, B: 1, X: 2, Y: 3, LB: 4, RB: 5, LT: 6, RT: 7, VIEW: 8, MENU: 9, L3: 10, R3: 11, UP: 12, DOWN: 13, LEFT: 14, RIGHT: 15 } as const;

/** Which device the player used last. The HUD and prompts switch their key names to match. */
export const inputDevice = { pad: false };
/** Name of the key/button bound to an action, for the device in use. */
export const actionName = (a: Action, short = false) => binds.label(a, inputDevice.pad, short) || 'unbound';

export type Captured = { kind: 'kb'; code: string } | { kind: 'pad'; btn: number };

/** Radial deadzone, rescaled so the stick still reaches 1 at the edge. */
function deadzone(x: number, y: number, dz: number): [number, number] {
  const m = Math.hypot(x, y);
  if (m < dz) return [0, 0];
  const k = Math.min(1, (m - dz) / (1 - dz)) / m;
  return [x * k, y * k];
}

/**
 * Keyboard + mouse input with pointer lock, plus a gamepad (polled every frame).
 * Game code asks for actions (act / actPressed) which go through the player's bindings.
 * Uses KeyboardEvent.code so it works on any layout.
 * "pressed" flags are edge-triggered and cleared every frame by endFrame().
 */
export class Input {
  private down = new Set<string>();
  private pressedSet = new Set<string>();
  private releasedSet = new Set<string>();
  /** controller buttons held / pressed this frame (kept apart from the keyboard so neither clears the other) */
  private padNow = new Set<number>();
  private padPressedSet = new Set<number>();
  mouseDX = 0;
  mouseDY = 0;
  wheel = 0;
  locked = false;
  enabled = true;
  /** left stick (move), -1..1, y is down-positive like the Gamepad API */
  moveX = 0;
  moveY = 0;
  /** right stick (look), -1..1 */
  lookX = 0;
  lookY = 0;
  /** the controller's sprint button latches sprint until the stick is let go */
  padSprint = false;
  padConnected = false;
  private padIndex = -1;
  /** while set, the next key / mouse button / controller button goes here instead of the game (rebinding) */
  private captureFn: ((c: Captured | null) => void) | null = null;
  private captureFrom = 0;
  /** swallow the click / keyup that follows a captured press so it doesn't also press a menu button */
  private swallowUntil = 0;
  private swallowKind: 'key' | 'mouse' = 'key';
  onLockChange: ((locked: boolean) => void) | null = null;
  onDeviceChange: ((pad: boolean) => void) | null = null;
  private handlers: [EventTarget, string, EventListener][] = [];

  constructor(private canvas: HTMLElement) {
    this.listen(window, 'keydown', (e) => {
      const ev = e as KeyboardEvent;
      if (this.captureFn) {
        ev.preventDefault();
        ev.stopPropagation();
        if (ev.repeat) return;
        this.finishCapture(ev.code === 'Escape' ? null : { kind: 'kb', code: ev.code });
        return;
      }
      // stop the browser from eating game keys (Ctrl+W, Space scroll, Tab focus)
      if (this.locked && (['Tab', 'Space', 'ControlLeft', 'ControlRight'].includes(ev.code) || this.isBound(ev.code))) ev.preventDefault();
      const typing = ev.target instanceof HTMLInputElement || ev.target instanceof HTMLTextAreaElement || ev.target instanceof HTMLSelectElement;
      if (ev.code === 'Tab' && !typing) ev.preventDefault();
      this.setDevice(false);
      if (ev.repeat) return;
      this.down.add(ev.code);
      this.pressedSet.add(ev.code);
    });
    this.listen(window, 'keyup', (e) => {
      const ev = e as KeyboardEvent;
      if (this.swallowKind === 'key' && performance.now() < this.swallowUntil) {
        ev.preventDefault();
        ev.stopPropagation();
        this.swallowUntil = 0;
      }
      this.down.delete(ev.code);
      this.releasedSet.add(ev.code);
    });
    this.listen(window, 'mousedown', (e) => {
      const ev = e as MouseEvent;
      if (this.captureFn) {
        if (performance.now() < this.captureFrom) return; // the click that started the rebind
        ev.preventDefault();
        ev.stopPropagation();
        this.finishCapture({ kind: 'kb', code: 'Mouse' + ev.button });
        return;
      }
      this.setDevice(false);
      if (!this.locked) return;
      const code = 'Mouse' + ev.button;
      this.down.add(code);
      this.pressedSet.add(code);
    });
    this.listen(window, 'mouseup', (e) => {
      const ev = e as MouseEvent;
      const code = 'Mouse' + ev.button;
      this.down.delete(code);
      this.releasedSet.add(code);
    });
    this.listen(window, 'mousemove', (e) => {
      const ev = e as MouseEvent;
      if (!this.locked) return;
      // Clamp absurd spikes some browsers produce right after locking.
      const dx = Math.abs(ev.movementX) > 400 ? 0 : ev.movementX;
      const dy = Math.abs(ev.movementY) > 400 ? 0 : ev.movementY;
      if (Math.abs(dx) + Math.abs(dy) > 3) this.setDevice(false);
      this.mouseDX += dx;
      this.mouseDY += dy;
    });
    this.listen(window, 'wheel', (e) => {
      this.wheel += Math.sign((e as WheelEvent).deltaY);
    });
    this.listen(window, 'contextmenu', (e) => e.preventDefault());
    for (const t of ['click', 'auxclick', 'mouseup']) {
      this.listen(window, t, (e) => {
        if (this.swallowKind === 'mouse' && performance.now() < this.swallowUntil) {
          e.preventDefault();
          e.stopPropagation();
          if (t !== 'mouseup') this.swallowUntil = 0;
        }
      });
    }
    this.listen(document, 'pointerlockchange', () => {
      this.locked = document.pointerLockElement === this.canvas;
      if (!this.locked) this.clear();
      this.onLockChange?.(this.locked);
    });
    this.listen(window, 'blur', () => this.clear());
    this.listen(window, 'gamepadconnected', (e) => {
      this.padConnected = true;
      if (this.padIndex < 0) this.padIndex = (e as GamepadEvent).gamepad.index;
    });
    this.listen(window, 'gamepaddisconnected', (e) => {
      if ((e as GamepadEvent).gamepad.index === this.padIndex) this.padIndex = -1;
      this.padConnected = !!this.pads().length;
      if (!this.padConnected) this.releasePad();
    });
  }

  private listen(t: EventTarget, type: string, fn: EventListener) {
    t.addEventListener(type, fn, { passive: false, capture: true } as AddEventListenerOptions);
    this.handlers.push([t, type, fn]);
  }

  private isBound(code: string) {
    for (const k of Object.values(binds.kb)) if (k[0] === code || k[1] === code) return true;
    return false;
  }

  // ------------------------------------------------------------------ rebinding
  /** The next key, mouse button or controller button is passed to fn (null = cancelled with Esc / Menu). */
  capture(fn: (c: Captured | null) => void) {
    this.captureFn = fn;
    this.captureFrom = performance.now() + 120;
  }
  cancelCapture() {
    this.captureFn = null;
  }
  get capturing() {
    return !!this.captureFn;
  }
  private finishCapture(c: Captured | null) {
    const fn = this.captureFn;
    this.captureFn = null;
    // only the release of the very press that was captured is swallowed
    this.swallowKind = c?.kind === 'kb' && c.code.startsWith('Mouse') ? 'mouse' : 'key';
    this.swallowUntil = c?.kind === 'pad' ? 0 : performance.now() + 600;
    fn?.(c);
  }

  // ------------------------------------------------------------------ actions
  /** Is the action held (any of its keys, or its controller button)? */
  act(a: Action) {
    if (!this.enabled) return false;
    const [k1, k2] = binds.kb[a];
    if ((k1 && this.down.has(k1)) || (k2 && this.down.has(k2))) return true;
    const b = binds.pad[a];
    return b >= 0 && this.padNow.has(b);
  }
  /** Was the action pressed this frame? */
  actPressed(a: Action) {
    if (!this.enabled) return false;
    const [k1, k2] = binds.kb[a];
    if ((k1 && this.pressedSet.has(k1)) || (k2 && this.pressedSet.has(k2))) return true;
    const b = binds.pad[a];
    return b >= 0 && this.padPressedSet.has(b);
  }
  /** Raw controller button (menus, pause). */
  padHeld(btn: number) {
    return this.padNow.has(btn);
  }
  padPressed(btn: number) {
    return this.padPressedSet.has(btn);
  }

  private setDevice(pad: boolean) {
    if (inputDevice.pad === pad) return;
    inputDevice.pad = pad;
    this.onDeviceChange?.(pad);
  }
  /** true when the player last touched the controller */
  get usingPad() {
    return inputDevice.pad;
  }

  private pads(): Gamepad[] {
    try {
      return (navigator.getGamepads?.() ?? []).filter((p): p is Gamepad => !!p && p.connected);
    } catch {
      return [];
    }
  }
  private pad(): Gamepad | null {
    const list = this.pads();
    if (!list.length) return null;
    const cur = list.find((p) => p.index === this.padIndex);
    if (cur) return cur;
    // no pad picked yet: take whichever one has a button held
    const active = list.find((p) => p.buttons.some((b) => b.pressed)) ?? list[0];
    this.padIndex = active.index;
    return active;
  }

  private releasePad() {
    this.padNow.clear();
    this.moveX = this.moveY = this.lookX = this.lookY = 0;
    this.padSprint = false;
  }

  /** Read the gamepad. Call once at the start of every frame, before anything asks for input. */
  pollPad() {
    const p = this.pad();
    if (!p) {
      if (this.padNow.size || this.moveX || this.lookX) this.releasePad();
      return;
    }
    this.padConnected = true;
    const now = new Set<number>();
    p.buttons.forEach((b, i) => {
      // analog triggers count once they're pulled about a third of the way
      const on = i === PAD.LT || i === PAD.RT ? b.value > TRIGGER_ON || (b.pressed && b.value === 0) : b.pressed;
      if (on) now.add(i);
    });
    const ax = (i: number) => p.axes[i] ?? 0;
    [this.moveX, this.moveY] = deadzone(ax(0), ax(1), 0.16);
    [this.lookX, this.lookY] = deadzone(ax(2), ax(3), 0.12);
    const fresh = [...now].filter((b) => !this.padNow.has(b));
    this.padNow = now;
    if (this.captureFn) {
      // rebinding: the first new button is the answer (Menu cancels)
      if (fresh.length && performance.now() >= this.captureFrom) this.finishCapture(fresh[0] === PAD.MENU ? null : { kind: 'pad', btn: fresh[0] });
      this.setDevice(true);
      return;
    }
    for (const b of fresh) this.padPressedSet.add(b);
    // sprint latches until you let go of the stick or pull back
    const sb = binds.pad.sprint;
    if (sb >= 0 && fresh.includes(sb)) this.padSprint = !this.padSprint;
    if (Math.hypot(this.moveX, this.moveY) < 0.3 || this.moveY > 0.5) this.padSprint = false;
    if (now.size || Math.hypot(this.moveX, this.moveY) > 0.25 || Math.hypot(this.lookX, this.lookY) > 0.25) this.setDevice(true);
  }

  /** Controller vibration (Chrome/Edge). weak = high-frequency motor, strong = low-frequency motor. */
  rumble(weak: number, strong: number, ms: number) {
    if (!inputDevice.pad || !settings.data.padVibration) return;
    try {
      const act = (this.pad() as any)?.vibrationActuator;
      act?.playEffect?.('dual-rumble', { duration: ms, weakMagnitude: Math.min(1, weak), strongMagnitude: Math.min(1, strong) })?.catch?.(() => {});
    } catch {
      /* no rumble on this pad/browser */
    }
  }

  requestLock() {
    try {
      const p = (this.canvas as any).requestPointerLock?.({ unadjustedMovement: true });
      if (p && typeof p.catch === 'function') {
        p.catch(() => {
          try { (this.canvas as any).requestPointerLock?.()?.catch?.(() => {}); } catch { /* ignore */ }
        });
      }
    } catch {
      try { (this.canvas as any).requestPointerLock?.(); } catch { /* ignore */ }
    }
  }
  exitLock() {
    if (document.pointerLockElement) document.exitPointerLock();
  }

  isDown(code: string) {
    return this.enabled && this.down.has(code);
  }
  pressed(code: string) {
    return this.enabled && this.pressedSet.has(code);
  }
  released(code: string) {
    return this.releasedSet.has(code);
  }
  /** Allow scripted tests to drive input. */
  simulate(code: string, isDown: boolean) {
    if (isDown) {
      if (!this.down.has(code)) this.pressedSet.add(code);
      this.down.add(code);
    } else {
      this.down.delete(code);
      this.releasedSet.add(code);
    }
  }
  /** Forget this frame's presses (a menu already used them). */
  consumePressed() {
    this.pressedSet.clear();
    this.padPressedSet.clear();
  }
  clear() {
    this.down.clear();
    this.mouseDX = this.mouseDY = 0;
  }
  endFrame() {
    this.pressedSet.clear();
    this.padPressedSet.clear();
    this.releasedSet.clear();
    this.mouseDX = 0;
    this.mouseDY = 0;
    this.wheel = 0;
  }
  dispose() {
    for (const [t, type, fn] of this.handlers) t.removeEventListener(type, fn, true);
    this.handlers = [];
  }
}

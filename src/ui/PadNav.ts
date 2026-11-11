import { PAD, type Input } from '../core/Input';

type Dir = 'up' | 'down' | 'left' | 'right';

const FOCUSABLE = 'button, input:not([type=hidden]), select, [data-pad]';

/**
 * Drives the menus with a controller: D-pad or left stick moves a highlight between buttons
 * (spatially, to the nearest one in that direction), A presses, B goes back, Start resumes.
 * Sliders and dropdowns change with left/right while highlighted.
 */
export class PadNav {
  private held: Dir | null = null;
  private repeatAt = 0;
  private focused: HTMLElement | null = null;

  constructor(
    private input: Input,
    private roots: () => HTMLElement[],
    private hooks: { back: () => boolean; start: () => boolean; hover: () => void },
  ) {}

  /** Visible, enabled controls the pad can reach, in every menu root. */
  private items(): HTMLElement[] {
    const out: HTMLElement[] = [];
    for (const r of this.roots()) {
      r.querySelectorAll<HTMLElement>(FOCUSABLE).forEach((el) => {
        if ((el as HTMLButtonElement).disabled) return;
        if (el instanceof HTMLInputElement && el.type === 'text') return; // typing needs a keyboard
        const rect = el.getBoundingClientRect();
        if (rect.width < 2 || rect.height < 2) return;
        if (rect.bottom < 0 || rect.top > window.innerHeight * 3) return;
        out.push(el);
      });
    }
    return out;
  }

  private setFocus(el: HTMLElement | null, sound = true) {
    if (this.focused === el) return;
    this.focused?.classList.remove('pad-focus');
    this.focused = el;
    if (!el) return;
    el.classList.add('pad-focus');
    try {
      el.focus({ preventScroll: true });
    } catch {
      el.focus();
    }
    el.scrollIntoView({ block: 'nearest', inline: 'nearest' });
    if (sound) this.hooks.hover();
  }

  /** Drop the highlight (e.g. when the mouse or keyboard takes over). */
  clear() {
    this.focused?.classList.remove('pad-focus');
    this.focused = null;
  }

  private dirNow(): Dir | null {
    const i = this.input;
    if (i.padHeld(PAD.UP)) return 'up';
    if (i.padHeld(PAD.DOWN)) return 'down';
    if (i.padHeld(PAD.LEFT)) return 'left';
    if (i.padHeld(PAD.RIGHT)) return 'right';
    const x = i.moveX, y = i.moveY;
    if (Math.hypot(x, y) < 0.55) return null;
    return Math.abs(x) > Math.abs(y) ? (x > 0 ? 'right' : 'left') : y > 0 ? 'down' : 'up';
  }

  /** Call once a frame while a menu is showing. */
  update(now: number) {
    const i = this.input;
    if (!i.usingPad) return;
    const items = this.items();
    if (!items.length) {
      this.clear();
      return;
    }
    // keep the highlight on something that still exists (screens rebuild their HTML)
    if (!this.focused || !items.includes(this.focused)) {
      const active = document.activeElement as HTMLElement | null;
      // start on the first control; if it's one of a set of choices, on the chosen one
      const first = items[0];
      const chosen = first.parentElement?.querySelector<HTMLElement>(':scope > [aria-pressed=true]');
      const pick = (active && items.includes(active) ? active : null) ?? (chosen && items.includes(chosen) ? chosen : first);
      this.focused = null;
      this.setFocus(pick, false);
      // the press that brought the highlight up shouldn't also move it
      this.held = this.dirNow();
      this.repeatAt = now + 0.38;
      return;
    }
    // direction with key-repeat
    const d = this.dirNow();
    if (d !== this.held) {
      this.held = d;
      this.repeatAt = now + 0.38;
      if (d) this.step(d, items);
    } else if (d && now >= this.repeatAt) {
      this.repeatAt = now + (this.isAdjustable(this.focused) && (d === 'left' || d === 'right') ? 0.05 : 0.13);
      this.step(d, items);
    }
    // buttons
    if (i.padPressed(PAD.A)) this.activate();
    if (i.padPressed(PAD.B)) this.hooks.back();
    if (i.padPressed(PAD.MENU)) this.hooks.start();
  }

  private isAdjustable(el: HTMLElement | null) {
    return (el instanceof HTMLInputElement && el.type === 'range') || el instanceof HTMLSelectElement;
  }

  private step(d: Dir, items: HTMLElement[]) {
    const cur = this.focused;
    if (cur && (d === 'left' || d === 'right')) {
      if (cur instanceof HTMLInputElement && cur.type === 'range') {
        const min = +cur.min, max = +cur.max, st = +cur.step || 1;
        const stepSize = Math.max(st, (max - min) / 40);
        const v = clamp(+cur.value + (d === 'right' ? stepSize : -stepSize), min, max);
        cur.value = String(Math.round(v / st) * st);
        cur.dispatchEvent(new Event('input', { bubbles: true }));
        return;
      }
      if (cur instanceof HTMLSelectElement) {
        const n = cur.options.length;
        cur.selectedIndex = clamp(cur.selectedIndex + (d === 'right' ? 1 : -1), 0, n - 1);
        cur.dispatchEvent(new Event('change', { bubbles: true }));
        return;
      }
    }
    this.setFocus(cur ? this.nearest(cur, d, items) ?? cur : items[0]);
  }

  /** Closest control in direction d, favoring ones lined up with the current one. */
  private nearest(from: HTMLElement, d: Dir, items: HTMLElement[]): HTMLElement | null {
    const a = from.getBoundingClientRect();
    const ax = a.left + a.width / 2, ay = a.top + a.height / 2;
    let best: HTMLElement | null = null, bestScore = Infinity;
    for (const el of items) {
      if (el === from) continue;
      const b = el.getBoundingClientRect();
      const bx = b.left + b.width / 2, by = b.top + b.height / 2;
      let along: number, across: number;
      if (d === 'up' || d === 'down') {
        along = d === 'down' ? b.top - a.bottom : a.top - b.bottom;
        if ((d === 'down' ? by - ay : ay - by) <= 2) continue;
        // overlap in x counts as lined up
        across = Math.max(0, Math.max(a.left, b.left) - Math.min(a.right, b.right) > 0 ? Math.abs(bx - ax) : 0);
      } else {
        along = d === 'right' ? b.left - a.right : a.left - b.right;
        if ((d === 'right' ? bx - ax : ax - bx) <= 2) continue;
        across = Math.max(a.top, b.top) - Math.min(a.bottom, b.bottom) > 0 ? Math.abs(by - ay) : 0;
      }
      const score = Math.max(0, along) + across * 2.5;
      if (score < bestScore) {
        bestScore = score;
        best = el;
      }
    }
    return best;
  }

  private activate() {
    const el = this.focused;
    if (!el) return;
    if (el instanceof HTMLSelectElement) {
      el.selectedIndex = (el.selectedIndex + 1) % el.options.length;
      el.dispatchEvent(new Event('change', { bubbles: true }));
      return;
    }
    if (el instanceof HTMLInputElement && el.type === 'range') return;
    el.click();
  }
}

function clamp(v: number, lo: number, hi: number) {
  return Math.min(hi, Math.max(lo, v));
}

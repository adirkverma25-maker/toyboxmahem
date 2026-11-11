import { ClientMsg, decode, encode, PlayerState, PROTOCOL_VERSION, ServerMsg } from './protocol';

export type NetStatus = 'offline' | 'connecting' | 'online' | 'error';

/**
 * Browser side of multiplayer: one WebSocket to the game server.
 * - reconnects with back-off if the connection drops (until disconnect() is called)
 * - measures round-trip time with pings
 * - keeps a short history of snapshots per remote player so they can be drawn smoothly
 *   ~100 ms in the past (snapshot interpolation), the standard way to hide 20 Hz updates
 *
 * Not wired into a match yet: see docs/multiplayer-and-godot.md for the next steps.
 */
export class NetClient {
  status: NetStatus = 'offline';
  id = '';
  room = '';
  /** round-trip time in ms (smoothed) */
  rtt = 0;
  /** server clock minus our clock, ms (from pings) */
  clockOffset = 0;
  /** how far in the past remote players are drawn */
  interpDelayMs = 100;
  readonly remotes = new Map<string, { name: string; history: { at: number; s: PlayerState }[] }>();
  onStatus: ((s: NetStatus, why?: string) => void) | null = null;
  onChat: ((from: string, text: string) => void) | null = null;

  private ws: WebSocket | null = null;
  private wanted = false;
  private retry = 0;
  private pingTimer = 0;
  private url = '';
  private hello: ClientMsg | null = null;

  connect(url: string, name: string, room = 'lobby') {
    this.url = url;
    this.hello = { t: 'hello', v: PROTOCOL_VERSION, name, room };
    this.wanted = true;
    this.open();
  }

  disconnect() {
    this.wanted = false;
    window.clearInterval(this.pingTimer);
    this.ws?.close();
    this.ws = null;
    this.remotes.clear();
    this.setStatus('offline');
  }

  send(m: ClientMsg) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(encode(m));
  }

  /** Our own state, sent every frame or two while connected (relay mode). */
  sendState(s: Omit<PlayerState, 'id' | 'name'>) {
    this.send({ t: 'state', s });
  }

  /** Where a remote player should be drawn right now (interpolated between snapshots). */
  sample(id: string, now = performance.now()): PlayerState | null {
    const r = this.remotes.get(id);
    if (!r || !r.history.length) return null;
    const target = now + this.clockOffset - this.interpDelayMs;
    const h = r.history;
    if (target <= h[0].at) return h[0].s;
    for (let i = h.length - 1; i > 0; i--) {
      const a = h[i - 1], b = h[i];
      if (target >= a.at && target <= b.at) {
        const k = (target - a.at) / Math.max(1, b.at - a.at);
        const lerp = (x: number, y: number) => x + (y - x) * k;
        let dyaw = b.s.yaw - a.s.yaw;
        dyaw = Math.atan2(Math.sin(dyaw), Math.cos(dyaw));
        return { ...b.s, x: lerp(a.s.x, b.s.x), y: lerp(a.s.y, b.s.y), z: lerp(a.s.z, b.s.z), yaw: a.s.yaw + dyaw * k, pitch: lerp(a.s.pitch, b.s.pitch) };
      }
    }
    return h[h.length - 1].s;
  }

  private open() {
    this.setStatus('connecting');
    let ws: WebSocket;
    try {
      ws = new WebSocket(this.url);
    } catch (e) {
      this.setStatus('error', (e as Error).message);
      return;
    }
    this.ws = ws;
    ws.onopen = () => {
      this.retry = 0;
      if (this.hello) ws.send(encode(this.hello));
      window.clearInterval(this.pingTimer);
      this.pingTimer = window.setInterval(() => this.send({ t: 'ping', at: performance.now() }), 1000);
    };
    ws.onmessage = (ev) => {
      const m = decode<ServerMsg>(typeof ev.data === 'string' ? ev.data : '');
      if (m) this.handle(m);
    };
    ws.onclose = () => {
      window.clearInterval(this.pingTimer);
      if (this.ws !== ws) return;
      this.ws = null;
      if (!this.wanted) return;
      this.setStatus('connecting', 'connection lost, retrying');
      const wait = Math.min(8000, 500 * 2 ** this.retry++);
      window.setTimeout(() => this.wanted && this.open(), wait);
    };
    ws.onerror = () => this.setStatus('error', `can't reach ${this.url}`);
  }

  private handle(m: ServerMsg) {
    switch (m.t) {
      case 'welcome':
        this.id = m.id;
        this.room = m.room;
        this.remotes.clear();
        for (const p of m.players) if (p.id !== this.id) this.remotes.set(p.id, { name: p.name, history: [] });
        this.setStatus('online');
        break;
      case 'join':
        if (m.p.id !== this.id) this.remotes.set(m.p.id, { name: m.p.name, history: [] });
        break;
      case 'leave':
        this.remotes.delete(m.id);
        break;
      case 'snap':
        for (const p of m.players) {
          if (p.id === this.id) continue;
          let r = this.remotes.get(p.id);
          if (!r) this.remotes.set(p.id, (r = { name: p.name, history: [] }));
          r.history.push({ at: m.at, s: p });
          if (r.history.length > 30) r.history.shift();
        }
        break;
      case 'pong': {
        const now = performance.now();
        const rtt = now - m.at;
        this.rtt = this.rtt ? this.rtt * 0.8 + rtt * 0.2 : rtt;
        this.clockOffset = m.server + rtt / 2 - now;
        break;
      }
      case 'chat':
        this.onChat?.(m.from, m.text);
        break;
      case 'error':
        this.setStatus('error', m.message);
        break;
    }
  }

  private setStatus(s: NetStatus, why?: string) {
    this.status = s;
    this.onStatus?.(s, why);
  }
}

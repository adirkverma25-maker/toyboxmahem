// Toybox Mayhem relay: routes online-play messages between the players in a room.
// Runs on Cloudflare Workers, with one Durable Object per room code.
//
//   npm install                 (once, in this folder)
//   npm run dev                 -> ws://127.0.0.1:8787/ws   (local, no Cloudflare account needed)
//   npm run deploy              -> wss://toybox-mayhem-relay.<your-account>.workers.dev/ws
//
// It does NOT run the game. One player per room is the HOST (their game runs the real match); the
// others are GUESTS. Guest messages go to the host; host messages go to one guest (`to`) or all of them.
// Message shapes match scripts/net/net_client.gd and the sessions in scripts/net/.
//
// Clients connect to /ws?room=<CODE> and then send {t:"hello", v, name, room, role}.

const PROTOCOL_VERSION = 116;
const MAX_HUMANS = 8;
const IDLE_KICK_MS = 30_000;

/** Room codes: letters and digits only, upper case, at most 8. */
const roomCode = (s) => String(s ?? '').replace(/[^a-z0-9]/gi, '').toUpperCase().slice(0, 8);
const cleanName = (s) => String(s ?? '').replace(/[^\w \-]/g, '').trim().slice(0, 14) || 'Toy';

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    if (url.pathname === '/' || url.pathname === '/health') {
      return new Response(`Toybox Mayhem relay is running (protocol ${PROTOCOL_VERSION}).\n`, { headers: { 'content-type': 'text/plain; charset=utf-8' } });
    }
    if (url.pathname !== '/ws') return new Response('not found', { status: 404 });
    if ((req.headers.get('Upgrade') || '').toLowerCase() !== 'websocket') return new Response('expected a websocket', { status: 426 });
    const code = roomCode(url.searchParams.get('room'));
    if (!code) return new Response('missing room code', { status: 400 });
    const stub = env.ROOMS.get(env.ROOMS.idFromName(code));
    return stub.fetch(req);
  },
};

/** One room: its host, its members, and the routing between them. */
export class Room {
  constructor(state, env) {
    this.state = state;
    this.code = '';
    this.host = null;
    /** id -> {id, name, role, ws, seenAt} */
    this.members = new Map();
    this.nextId = 1;
    this.startedAt = Date.now();
    this.idle = null;
  }

  async fetch(req) {
    this.code = roomCode(new URL(req.url).searchParams.get('room'));
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    server.accept();
    this.attach(server);
    return new Response(null, { status: 101, webSocket: client });
  }

  now() {
    return Date.now() - this.startedAt;
  }

  attach(ws) {
    let me = null;
    const send = (m) => raw(ws, JSON.stringify(m));
    const fail = (code, message) => {
      send({ t: 'error', code, message });
      try {
        ws.close(1000, code);
      } catch {}
    };
    ws.addEventListener('message', (ev) => {
      let m;
      try {
        m = JSON.parse(typeof ev.data === 'string' ? ev.data : new TextDecoder().decode(ev.data));
      } catch {
        return;
      }
      if (!m || typeof m.t !== 'string') return;
      if (!me) {
        if (m.t !== 'hello') return;
        if (m.v !== PROTOCOL_VERSION) return fail('version', `Your game is a different version from this server's (${m.v} vs ${PROTOCOL_VERSION}). Update the game.`);
        const code = this.code || roomCode(m.room);
        if (!code) return fail('bad', 'Type a room code.');
        const role = m.role === 'host' ? 'host' : 'guest';
        if (role === 'host') {
          if (this.host) return fail('hostTaken', `Someone is already hosting room ${code}.`);
        } else {
          if (!this.host) return fail('noHost', `Nobody is hosting room ${code} right now.`);
          if (this.members.size >= MAX_HUMANS) return fail('full', `Room ${code} is full (${MAX_HUMANS} players).`);
        }
        me = { id: `p${this.nextId++}`, name: cleanName(m.name), role, ws, seenAt: Date.now() };
        if (role === 'host') this.host = me;
        const peers = [...this.members.values()].map((c) => ({ id: c.id, name: c.name }));
        this.members.set(me.id, me);
        send({ t: 'welcome', id: me.id, room: code, role, hostId: this.host.id, peers });
        const joined = JSON.stringify({ t: 'join', p: { id: me.id, name: me.name } });
        for (const c of this.members.values()) if (c !== me) raw(c.ws, joined);
        this.startIdleCheck();
        return;
      }
      me.seenAt = Date.now();
      if (m.t === 'ping') return send({ t: 'pong', at: m.at, server: this.now() });
      if (m.t !== 'relay' || !m.m) return;
      const out = JSON.stringify({ t: 'relay', from: me.id, m: m.m });
      if (me.role === 'guest') {
        if (this.host) raw(this.host.ws, out);
      } else if (m.to) {
        const c = this.members.get(m.to);
        if (c) raw(c.ws, out);
      } else {
        for (const c of this.members.values()) if (c !== me) raw(c.ws, out);
      }
    });
    const gone = () => {
      if (!me || !this.members.has(me.id)) return;
      this.members.delete(me.id);
      if (me === this.host) {
        // the match lives in the host's game: without it the room is over
        this.host = null;
        const left = JSON.stringify({ t: 'hostLeft' });
        for (const c of this.members.values()) {
          raw(c.ws, left);
          try {
            c.ws.close(1000, 'hostLeft');
          } catch {}
        }
        this.members.clear();
      } else {
        const left = JSON.stringify({ t: 'leave', id: me.id });
        for (const c of this.members.values()) raw(c.ws, left);
      }
      if (!this.members.size) this.stopIdleCheck();
    };
    ws.addEventListener('close', gone);
    ws.addEventListener('error', gone);
  }

  startIdleCheck() {
    if (this.idle) return;
    this.idle = setInterval(() => {
      const t = Date.now();
      for (const c of [...this.members.values()]) {
        if (t - c.seenAt > IDLE_KICK_MS) {
          try {
            c.ws.close(1001, 'idle');
          } catch {}
        }
      }
    }, 5000);
  }

  stopIdleCheck() {
    if (this.idle) clearInterval(this.idle);
    this.idle = null;
  }
}

function raw(ws, s) {
  try {
    ws.send(s);
  } catch {
    /* already closed */
  }
}

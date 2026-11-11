// Toybox Mayhem dev game server (multiplayer groundwork).
//
//   npm run server            -> ws://localhost:8787
//   PORT=9000 npm run server  -> another port
//
// Today it's a RELAY: each client sends its own position/aim/health ('state'), the server keeps the
// latest one per player and broadcasts everyone in the room 20 times a second ('snap').
// The next step is making it AUTHORITATIVE: clients send inputs ('input'), the server runs the match
// (movement, hits, scores) and the snapshots become the truth. See docs/multiplayer-and-godot.md.
//
// The message shapes match src/net/protocol.ts.
import { WebSocketServer } from 'ws';

const PORT = Number(process.env.PORT || 8787);
const PROTOCOL_VERSION = 1;
const TICK_RATE = 20;
const MAX_PER_ROOM = 8;
const IDLE_KICK_MS = 30_000;

/** room name -> Map<id, client> */
const rooms = new Map();
let nextId = 1;
const startedAt = Date.now();
const now = () => Date.now() - startedAt;

const wss = new WebSocketServer({ port: PORT, maxPayload: 16 * 1024 });

function send(ws, msg) {
  if (ws.readyState === 1) ws.send(JSON.stringify(msg));
}
function broadcast(room, msg, except) {
  const s = JSON.stringify(msg);
  for (const c of rooms.get(room)?.values() ?? []) if (c !== except && c.ws.readyState === 1) c.ws.send(s);
}
function publicState(c) {
  return { id: c.id, name: c.name, ...c.state };
}
const clean = (s, max) => String(s ?? '').replace(/[^\w \-]/g, '').trim().slice(0, max);
const num = (v, lo, hi) => (typeof v === 'number' && Number.isFinite(v) ? Math.min(hi, Math.max(lo, v)) : 0);

wss.on('connection', (ws) => {
  let client = null;
  ws.on('message', (raw) => {
    let m;
    try {
      m = JSON.parse(String(raw));
    } catch {
      return;
    }
    if (!m || typeof m.t !== 'string') return;
    if (!client) {
      if (m.t !== 'hello') return;
      if (m.v !== PROTOCOL_VERSION) return send(ws, { t: 'error', message: `server speaks protocol ${PROTOCOL_VERSION}, client sent ${m.v}` });
      const room = clean(m.room, 24) || 'lobby';
      if (!rooms.has(room)) rooms.set(room, new Map());
      const members = rooms.get(room);
      if (members.size >= MAX_PER_ROOM) return send(ws, { t: 'error', message: 'room is full' });
      client = {
        id: `p${nextId++}`,
        name: clean(m.name, 14) || 'Toy',
        room,
        ws,
        seenAt: Date.now(),
        state: { x: 0, y: 0, z: 0, yaw: 0, pitch: 0, hp: 100, weapon: 'foamFury', alive: true },
      };
      members.set(client.id, client);
      send(ws, { t: 'welcome', id: client.id, room, tick: 0, players: [...members.values()].map(publicState) });
      broadcast(room, { t: 'join', p: publicState(client) }, client);
      console.log(`[join] ${client.name} (${client.id}) -> ${room} [${members.size}]`);
      return;
    }
    client.seenAt = Date.now();
    switch (m.t) {
      case 'state': {
        const s = m.s ?? {};
        client.state = {
          x: num(s.x, -500, 500), y: num(s.y, -50, 200), z: num(s.z, -500, 500),
          yaw: num(s.yaw, -1e4, 1e4), pitch: num(s.pitch, -2, 2), hp: num(s.hp, 0, 150),
          weapon: clean(s.weapon, 24) || client.state.weapon, alive: s.alive !== false,
        };
        break;
      }
      case 'input':
        // authoritative mode will simulate these; the relay only uses them to keep the client alive
        break;
      case 'ping':
        send(ws, { t: 'pong', at: m.at, server: now() });
        break;
      case 'chat': {
        const text = String(m.text ?? '').slice(0, 140);
        if (text.trim()) broadcast(client.room, { t: 'chat', from: client.name, text });
        break;
      }
    }
  });
  ws.on('close', () => {
    if (!client) return;
    const members = rooms.get(client.room);
    members?.delete(client.id);
    broadcast(client.room, { t: 'leave', id: client.id });
    if (members && !members.size) rooms.delete(client.room);
    console.log(`[leave] ${client.name} (${client.id})`);
  });
});

// snapshots + idle kick
let tick = 0;
setInterval(() => {
  tick++;
  const t = Date.now();
  for (const [room, members] of rooms) {
    for (const c of members.values()) if (t - c.seenAt > IDLE_KICK_MS) c.ws.terminate();
    if (members.size) broadcast(room, { t: 'snap', tick, at: now(), players: [...members.values()].map(publicState) });
  }
}, 1000 / TICK_RATE);

console.log(`Toybox Mayhem dev server on ws://localhost:${PORT} (protocol ${PROTOCOL_VERSION}, ${TICK_RATE} Hz)`);

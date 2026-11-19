// Checks a running relay: node test-relay.mjs [ws://127.0.0.1:8787]
// Host + two guests join a room, messages route the right way, errors and host-leaving work.
const base = (process.argv[2] || 'ws://127.0.0.1:8787').replace(/\/+$/, '');
const V = 111;
const room = 'T' + Math.random().toString(36).slice(2, 7).toUpperCase();

function client(role, name, code = room) {
  const ws = new WebSocket(`${base}/ws?room=${code}`);
  const inbox = [];
  const waiters = [];
  ws.onmessage = (ev) => {
    const m = JSON.parse(ev.data);
    const i = waiters.findIndex((w) => w.pred(m));
    if (i >= 0) waiters.splice(i, 1)[0].resolve(m);
    else inbox.push(m);
  };
  const next = (pred, ms = 4000) => {
    const i = inbox.findIndex(pred);
    if (i >= 0) return Promise.resolve(inbox.splice(i, 1)[0]);
    return new Promise((resolve, reject) => {
      const w = { pred, resolve };
      waiters.push(w);
      setTimeout(() => reject(new Error(`${name}: timed out waiting`)), ms);
    });
  };
  const open = new Promise((r, j) => {
    ws.onopen = () => {
      ws.send(JSON.stringify({ t: 'hello', v: V, name, room: code, role }));
      r();
    };
    ws.onerror = () => j(new Error(`${name}: can't connect to ${base}`));
  });
  return { ws, next, open, send: (m) => ws.send(JSON.stringify(m)) };
}

let failed = 0;
const check = (ok, what) => {
  console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`);
  if (!ok) failed++;
};

try {
  const lonely = client('guest', 'Early');
  await lonely.open;
  const e = await lonely.next((m) => m.t === 'error');
  check(e.code === 'noHost', 'joining a room nobody hosts is refused');

  const host = client('host', 'Hosty');
  await host.open;
  const hw = await host.next((m) => m.t === 'welcome');
  check(hw.role === 'host' && hw.room === room, `host gets welcome for room ${room}`);

  const host2 = client('host', 'Other');
  await host2.open;
  check((await host2.next((m) => m.t === 'error')).code === 'hostTaken', 'a second host is refused');

  const g1 = client('guest', 'Gus');
  await g1.open;
  const gw = await g1.next((m) => m.t === 'welcome');
  check(gw.hostId === hw.id && gw.peers.some((p) => p.name === 'Hosty'), 'guest welcome lists the host');
  check((await host.next((m) => m.t === 'join')).p.name === 'Gus', 'host hears the guest join');

  const g2 = client('guest', 'Gwen');
  await g2.open;
  const g2w = await g2.next((m) => m.t === 'welcome');
  await host.next((m) => m.t === 'join');
  await g1.next((m) => m.t === 'join');

  g1.send({ t: 'relay', m: { g: 'gstate', s: { x: 1 } } });
  const r1 = await host.next((m) => m.t === 'relay');
  check(r1.from === gw.id && r1.m.g === 'gstate', 'guest -> host relay');

  host.send({ t: 'relay', m: { g: 'snap', tick: 1 } });
  const [a, b] = await Promise.all([g1.next((m) => m.t === 'relay'), g2.next((m) => m.t === 'relay')]);
  check(a.m.g === 'snap' && b.m.g === 'snap', 'host broadcast reaches both guests');

  host.send({ t: 'relay', to: g2w.id, m: { g: 'ev', ev: { e: 'impulse' } } });
  check((await g2.next((m) => m.t === 'relay')).m.g === 'ev', 'host -> one guest');

  const t0 = Date.now();
  g1.send({ t: 'ping', at: 123 });
  const pong = await g1.next((m) => m.t === 'pong');
  check(pong.at === 123 && typeof pong.server === 'number', `ping/pong (${Date.now() - t0} ms round trip)`);

  g2.ws.close();
  check((await host.next((m) => m.t === 'leave')).id === g2w.id, 'host hears a guest leave');

  host.ws.close();
  check((await g1.next((m) => m.t === 'hostLeft')).t === 'hostLeft', 'guests are told when the host leaves');

  const bad = client('host', 'Old', room + 'X');
  bad.ws.onopen = () => bad.ws.send(JSON.stringify({ t: 'hello', v: 2, name: 'Old', room: room + 'X', role: 'host' }));
  check((await bad.next((m) => m.t === 'error')).code === 'version', 'an older game version is refused');
} catch (err) {
  console.log('FAIL', err.message);
  failed++;
}
console.log(failed ? `${failed} check(s) failed` : 'relay OK');
process.exit(failed ? 1 : 0);

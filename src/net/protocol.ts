/**
 * Wire format shared by the browser client (src/net/NetClient.ts) and the dev server (server/index.mjs).
 * Plain JSON for now; every message has a `t` (type) field. Bump PROTOCOL_VERSION on breaking changes.
 *
 * The plan (docs/multiplayer-and-godot.md): clients send their inputs, the server runs the match and
 * sends snapshots back. Today the server is a relay (it trusts and rebroadcasts each client's own state),
 * which is enough to see each other move and to build the rest on.
 */
export const PROTOCOL_VERSION = 1;
/** Server snapshot rate (per second). */
export const TICK_RATE = 20;

/** Buttons packed into one number so input frames stay small. */
export const BTN = {
  fire: 1 << 0,
  aim: 1 << 1,
  jump: 1 << 2,
  crouch: 1 << 3,
  sprint: 1 << 4,
  reload: 1 << 5,
  ability1: 1 << 6,
  ability2: 1 << 7,
} as const;

/** One frame of what a player is doing (what an authoritative server needs to simulate them). */
export interface InputFrame {
  seq: number;
  /** wish direction in world space, -1..1 */
  mx: number;
  mz: number;
  yaw: number;
  pitch: number;
  buttons: number;
}

/** What other players need to draw someone. */
export interface PlayerState {
  id: string;
  name: string;
  x: number;
  y: number;
  z: number;
  yaw: number;
  pitch: number;
  hp: number;
  weapon: string;
  alive: boolean;
}

export type ClientMsg =
  | { t: 'hello'; v: number; name: string; room?: string }
  | { t: 'input'; f: InputFrame }
  | { t: 'state'; s: Omit<PlayerState, 'id' | 'name'> }
  | { t: 'ping'; at: number }
  | { t: 'chat'; text: string };

export type ServerMsg =
  | { t: 'welcome'; id: string; room: string; tick: number; players: PlayerState[] }
  | { t: 'join'; p: PlayerState }
  | { t: 'leave'; id: string }
  | { t: 'snap'; tick: number; at: number; players: PlayerState[] }
  | { t: 'pong'; at: number; server: number }
  | { t: 'chat'; from: string; text: string }
  | { t: 'error'; message: string };

export function encode(m: ClientMsg | ServerMsg): string {
  return JSON.stringify(m);
}
export function decode<T extends ClientMsg | ServerMsg>(raw: string): T | null {
  try {
    const m = JSON.parse(raw);
    return m && typeof m.t === 'string' ? (m as T) : null;
  } catch {
    return null;
  }
}

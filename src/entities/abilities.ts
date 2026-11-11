import * as THREE from 'three';
import type { Actor } from './Actor';
import type { Combat } from '../combat/Combat';
import type { Physics } from '../physics/Physics';
import type { AudioEngine } from '../audio/Audio';
import { ABILITIES } from '../weapons/weaponConfig';
import { TEAMS } from '../match/modes';

/**
 * The four extra abilities, shared by the player and the bots so both follow the same rules.
 * Dash lives in Actor.move (it's part of movement). Each toy only has the two it equipped (Actor.abilities).
 */
export interface AbilityDeps {
  combat: Combat;
  phys: Physics;
  audio: AudioEngine;
}

const _d = new THREE.Vector3();
const _o = new THREE.Vector3();

export function abilityColor(a: Actor) {
  return a.team >= 0 ? TEAMS[a.team].color : a.isPlayer ? '#ffd23f' : a.def.accent;
}

/** Spring Punch. Returns false if on cooldown. */
export function tryJab(a: Actor, now: number, deps: AbilityDeps) {
  if (!a.alive || !a.has('jab') || now < a.jabReadyAt) return false;
  a.jabReadyAt = now + ABILITIES.jab.cooldown;
  a.jabT = 0.32;
  const hit = deps.combat.jab(a);
  deps.audio.punch(!!hit, a.isPlayer ? undefined : a.chestPos());
  return true;
}

/**
 * Where a Spring Hook fired along `dir` would latch, or null on a miss.
 * Hooking the front of a ledge latches onto its top edge so the pull carries you up and over.
 */
export function grapplePoint(a: Actor, dir: THREE.Vector3, phys: Physics): THREE.Vector3 | null {
  const eye = a.eyePos(_o);
  const hit = phys.raycast(eye, dir, ABILITIES.grapple.range, true);
  if (!hit || hit.dist < 2.5) return null;
  const p = hit.point.clone();
  if (hit.normal.y < -0.5) return p.addScaledVector(hit.normal, 0.6); // underside of something: hang below it
  if (hit.normal.y < 0.5) {
    // wall or ledge face: look for a floor just above and behind the hit
    const into = _d.copy(hit.normal).setY(0).normalize().negate();
    const probe = p.clone().addScaledVector(into, 0.7).setY(p.y + 2.4);
    const down = phys.raycast(probe, new THREE.Vector3(0, -1, 0), 2.6, true);
    if (down && down.normal.y > 0.7 && down.point.y > p.y - 0.2) return down.point.setY(down.point.y + 0.4);
    return p.addScaledVector(hit.normal, 0.5);
  }
  return p.setY(p.y + 0.4);
}

/** Spring Hook. Returns the anchor, 'miss' or false (cooldown). */
export function tryGrapple(a: Actor, dir: THREE.Vector3, now: number, deps: AbilityDeps): THREE.Vector3 | 'miss' | false {
  if (!a.alive || !a.has('grapple') || now < a.grappleReadyAt || a.grapple) return false;
  const anchor = grapplePoint(a, dir, deps.phys);
  if (!anchor) {
    a.grappleReadyAt = now + ABILITIES.grapple.missCooldown;
    deps.audio.grapple(a.isPlayer ? undefined : a.chestPos(), false);
    return 'miss';
  }
  a.startGrapple(anchor, now);
  deps.audio.grapple(a.isPlayer ? undefined : a.chestPos(), true);
  return anchor;
}

/** Cloak toggle. */
export function tryCloak(a: Actor, now: number, deps: AbilityDeps) {
  if (!a.alive || (!a.has('cloak') && !a.cloaked)) return false;
  const was = a.cloaked;
  if (!a.toggleCloak(now)) return false;
  deps.audio.cloak(!was, a.isPlayer ? undefined : a.chestPos());
  return true;
}

/** Mesh Shield: plants a hex-wire wall a step in front of you, facing where you look. */
export function tryShield(a: Actor, now: number, deps: AbilityDeps, yaw = a.yaw) {
  if (!a.alive || !a.has('shield') || now < a.shieldReadyAt) return false;
  a.shieldReadyAt = now + ABILITIES.shield.cooldown;
  const fwd = _d.set(-Math.sin(yaw), 0, -Math.cos(yaw));
  const p = a.pos.clone().addScaledVector(fwd, 1.5);
  // sit it on whatever floor is there (but never above our own feet + a step)
  const g = deps.phys.rayDist(_o.set(p.x, a.pos.y + 1.2, p.z), new THREE.Vector3(0, -1, 0), 4, true);
  p.y = g === Infinity ? a.pos.y : Math.min(a.pos.y + 0.6, a.pos.y + 1.2 - g);
  deps.combat.barriers.deploy(a, p, yaw, abilityColor(a), now);
  deps.audio.shieldUp(a.isPlayer ? undefined : p);
  return true;
}

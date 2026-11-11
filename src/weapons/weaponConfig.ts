/**
 * ALL weapon balance lives here. Edit these numbers to rebalance; nothing else in the engine hardcodes them.
 * Angles are in degrees, distances in meters (1 unit = 1 toy-meter), times in seconds.
 */

export type WeaponId =
  | 'plasti9'
  | 'foamFury'
  | 'brickbreaker'
  | 'bubbleBlaster'
  | 'thunderspring'
  | 'rapidRascal'
  | 'crayonCannon'
  | 'starlightZapper'
  | 'jackBlaster'
  | 'plungerBow'
  | 'popcornPopper'
  | 'walloper';

export type ProjectileVisual = 'dart' | 'bubble' | 'crayon' | 'bolt' | 'arrow';

export type RecoilSpec =
  | {
      kind: 'pattern';
      /** per-shot pitch kick (deg) indexed by shot number in the current spray */
      pitch: number[];
      /** per-shot yaw kick (deg) */
      yaw: number[];
      /** after the table runs out, repeat from this index */
      loopFrom: number;
      /** small random variation added to each kick (deg) */
      jitter: number;
    }
  | {
      kind: 'random';
      pitch: number; // base vertical kick per shot
      pitchGrowth: number; // extra vertical per shot in the spray
      pitchMax: number; // cap for vertical kick per shot
      yaw: number; // +- horizontal variance
      yawGrowth: number; // horizontal variance growth per shot
      yawBias: number; // constant drift per shot (+ = right)
    };

export interface WeaponConfig {
  id: WeaponId;
  name: string;
  category: string;
  blurb: string;
  slotHint: 1 | 2;
  damage: number;
  headMult: number;
  pellets: number;
  magSize: number;
  reserve: number;
  rpm: number;
  auto: boolean;
  reloadTime: number;
  /** if set, reloads one round at a time (shotgun) */
  reloadPerShell?: number;
  effectiveRange: number;
  falloffEnd: number;
  minDamageMult: number;
  adsZoom: number;
  adsTime: number;
  adsMoveMult: number;
  /** burst fire: `count` shots `gap` seconds apart per trigger pull; rpm then sets the pause between bursts */
  burst?: { count: number; gap: number };
  projectile:
    | { kind: 'hitscan'; tracer: 'pellet' | 'heavy' | 'precision' | 'buzz' }
    | { kind: 'projectile'; visual: ProjectileVisual; speed: number; gravity: number; radius: number; life: number; drag?: number };
  explosion?: { radius: number; maxDamage: number; selfDamageMult: number };
  /**
   * Hold-to-draw weapons (bow). Damage = damage * charge^curve, so a tap does ~nothing and a full draw hits hard.
   * Projectile speed and gravity also scale with the draw.
   */
  charge?: { time: number; curve: number; minSpeed: number; maxSpeed: number; moveMult: number };
  energy?: { capacity: number; perShot: number; rechargeDelay: number; rechargeRate: number; lockoutUntil: number };
  spread: { hip: number; ads: number; move: number; air: number; bloomPerShot: number; bloomMax: number; bloomDecay: number };
  recoil: RecoilSpec;
  recoveryRate: number; // deg/s camera recoil recovery
  recoveryDelay: number; // seconds after last shot before recovery starts
  adsRecoilMult: number;
  kick: { back: number; up: number; roll: number; shake: number };
  colors: { main: string; accent: string; glow: string; tracer: string };
  /** bot preference: [ideal min, ideal max] engagement distance */
  botRange: [number, number];
  /** shoves the target back on a hit (m/s added, horizontal), plus a small hop */
  knockback?: number;
}

const fill = (n: number, v: number) => Array.from({ length: n }, () => v);

export const WEAPONS: Record<WeaponId, WeaponConfig> = {
  plasti9: {
    id: 'plasti9', name: 'PLASTI-9', category: 'Semi-auto toy pistol', slotHint: 2,
    blurb: 'Snappy teal sidearm. Fires as fast as you can click, up to 360 RPM.',
    damage: 22, headMult: 1.6, pellets: 1, magSize: 15, reserve: 75, rpm: 360, auto: false,
    reloadTime: 1.4, effectiveRange: 25, falloffEnd: 50, minDamageMult: 0.6,
    adsZoom: 1.2, adsTime: 0.14, adsMoveMult: 0.8,
    projectile: { kind: 'hitscan', tracer: 'pellet' },
    spread: { hip: 1.1, ads: 0.2, move: 0.9, air: 2.5, bloomPerShot: 0.35, bloomMax: 2.4, bloomDecay: 6 },
    recoil: { kind: 'random', pitch: 0.7, pitchGrowth: 0, pitchMax: 0.7, yaw: 0.25, yawGrowth: 0, yawBias: 0.08 },
    recoveryRate: 10, recoveryDelay: 0.09, adsRecoilMult: 0.8,
    kick: { back: 0.06, up: 0.05, roll: 0.03, shake: 0.05 },
    colors: { main: '#1fb5ad', accent: '#ff8c1a', glow: '#7dfff3', tracer: '#ffb347' },
    botRange: [3, 22],
  },
  foamFury: {
    id: 'foamFury', name: 'FOAM FURY', category: 'Automatic foam dart rifle', slotHint: 1,
    blurb: 'Reliable 750 RPM dart rifle. Learn the up-right-left climb and it lasers.',
    damage: 16, headMult: 1.5, pellets: 1, magSize: 36, reserve: 144, rpm: 750, auto: true,
    reloadTime: 2.0, effectiveRange: 35, falloffEnd: 70, minDamageMult: 0.65,
    adsZoom: 1.3, adsTime: 0.2, adsMoveMult: 0.7,
    projectile: { kind: 'projectile', visual: 'dart', speed: 110, gravity: 3, radius: 0.06, life: 1.2 },
    spread: { hip: 2.1, ads: 0.45, move: 1.2, air: 3, bloomPerShot: 0.12, bloomMax: 2.0, bloomDecay: 5 },
    recoil: {
      kind: 'pattern',
      // shots 1-5 climb 0.4 each, 6-12 drift right, 13-20 drift left
      pitch: [...fill(5, 0.4), ...fill(7, 0.16), ...fill(8, 0.12)],
      yaw: [...fill(5, 0), ...fill(7, 0.22), ...fill(8, -0.26)],
      loopFrom: 5,
      jitter: 0.05,
    },
    recoveryRate: 8, recoveryDelay: 0.12, adsRecoilMult: 0.75,
    kick: { back: 0.035, up: 0.025, roll: 0.02, shake: 0.04 },
    colors: { main: '#ff7a1a', accent: '#2f6fe0', glow: '#ffd08a', tracer: '#ff9a3c' },
    botRange: [6, 32],
  },
  brickbreaker: {
    id: 'brickbreaker', name: 'BRICKBREAKER', category: 'Heavy toy assault rifle', slotHint: 1,
    blurb: 'Hard-hitting brick rifle. Strong first-six climb, then a right-left-right sway.',
    damage: 24, headMult: 1.5, pellets: 1, magSize: 24, reserve: 120, rpm: 540, auto: true,
    reloadTime: 2.4, effectiveRange: 45, falloffEnd: 90, minDamageMult: 0.7,
    adsZoom: 1.45, adsTime: 0.24, adsMoveMult: 0.65,
    projectile: { kind: 'hitscan', tracer: 'heavy' },
    spread: { hip: 2.6, ads: 0.35, move: 1.4, air: 3.5, bloomPerShot: 0.14, bloomMax: 2.2, bloomDecay: 5 },
    recoil: {
      kind: 'pattern',
      pitch: [1.15, 1.1, 1.05, 1.0, 0.95, 0.9, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7, 0.7],
      // horizontal kicks whose running total swings right -> left -> right inside +-0.5 deg
      yaw: [0.12, 0.13, 0.15, 0.1, -0.12, -0.2, -0.25, -0.25, -0.15, 0.15, 0.25, 0.25, 0.15, -0.15, -0.25, -0.25, -0.15, 0.15],
      loopFrom: 6,
      jitter: 0.04,
    },
    recoveryRate: 7, recoveryDelay: 0.13, adsRecoilMult: 0.6,
    kick: { back: 0.06, up: 0.04, roll: 0.025, shake: 0.08 },
    colors: { main: '#1d1d1f', accent: '#ffcc00', glow: '#ff3b30', tracer: '#ffd54a' },
    botRange: [10, 42],
  },
  bubbleBlaster: {
    id: 'bubbleBlaster', name: 'BUBBLE BLASTER', category: 'Close-range toy shotgun', slotHint: 1,
    blurb: 'Nine bubbles per pump, 25 each. Pops anyone inside 5 m in one shot, even with a full shield. Weak past 16 m.',
    // 25 x 9 = 225. At 5 m, even moving, at least 6 bubbles land (150) = 100 health + 50 shield.
    damage: 25, headMult: 1.2, pellets: 9, magSize: 6, reserve: 36, rpm: 85, auto: false,
    reloadTime: 0.55 * 6, reloadPerShell: 0.55, effectiveRange: 5, falloffEnd: 16, minDamageMult: 0.15,
    adsZoom: 1.1, adsTime: 0.18, adsMoveMult: 0.8,
    projectile: { kind: 'projectile', visual: 'bubble', speed: 62, gravity: -0.8, radius: 0.16, life: 0.55, drag: 0.6 },
    spread: { hip: 5.2, ads: 3.8, move: 0.6, air: 1.5, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 2.8, pitchGrowth: 0, pitchMax: 2.8, yaw: 0.45, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 9.5, recoveryDelay: 0.05, adsRecoilMult: 0.85,
    kick: { back: 0.16, up: 0.12, roll: 0.06, shake: 0.18 },
    colors: { main: '#9b5de5', accent: '#f15bb5', glow: '#c77dff', tracer: '#e0aaff' },
    botRange: [0, 10],
  },
  thunderspring: {
    id: 'thunderspring', name: 'THUNDERSPRING', category: 'Spring-powered marksman rifle', slotHint: 1,
    blurb: 'Cobalt spring rifle. 58 body, 101 to the head. Scope in, breathe, twang.',
    damage: 58, headMult: 1.75, pellets: 1, magSize: 5, reserve: 25, rpm: 55, auto: false,
    reloadTime: 2.8, effectiveRange: 80, falloffEnd: 140, minDamageMult: 0.8,
    adsZoom: 3.2, adsTime: 0.3, adsMoveMult: 0.5,
    projectile: { kind: 'hitscan', tracer: 'precision' },
    spread: { hip: 4.5, ads: 0, move: 2.2, air: 5, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 3.2, pitchGrowth: 0, pitchMax: 3.2, yaw: 0.35, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 5.8, recoveryDelay: 0.02, adsRecoilMult: 1,
    kick: { back: 0.18, up: 0.1, roll: 0.05, shake: 0.2 },
    colors: { main: '#1f4fd1', accent: '#f2c94c', glow: '#8fb8ff', tracer: '#bfe3ff' },
    botRange: [22, 80],
  },
  rapidRascal: {
    id: 'rapidRascal', name: 'RAPID RASCAL', category: 'Compact toy SMG', slotHint: 1,
    blurb: 'A 1050 RPM drum of chaos. Tight hip-fire, climbs and jitters the longer you hold.',
    damage: 11, headMult: 1.4, pellets: 1, magSize: 50, reserve: 200, rpm: 1050, auto: true,
    reloadTime: 2.3, effectiveRange: 18, falloffEnd: 40, minDamageMult: 0.5,
    adsZoom: 1.2, adsTime: 0.15, adsMoveMult: 0.85,
    projectile: { kind: 'hitscan', tracer: 'buzz' },
    spread: { hip: 1.5, ads: 1.1, move: 0.5, air: 2, bloomPerShot: 0.07, bloomMax: 2.6, bloomDecay: 4.5 },
    recoil: { kind: 'random', pitch: 0.12, pitchGrowth: 0.014, pitchMax: 0.42, yaw: 0.05, yawGrowth: 0.012, yawBias: 0 },
    recoveryRate: 9, recoveryDelay: 0.1, adsRecoilMult: 0.85,
    kick: { back: 0.025, up: 0.012, roll: 0.03, shake: 0.03 },
    colors: { main: '#39ff88', accent: '#ff4fd8', glow: '#9dffcb', tracer: '#ff8ae6' },
    botRange: [0, 16],
  },
  crayonCannon: {
    id: 'crayonCannon', name: 'CRAYON CANNON', category: 'Explosive projectile launcher', slotHint: 1,
    blurb: 'Fires giant crayons fast and far on a shallow arc. 65 direct, up to 35 splash in 3.5 m. Paints the room.',
    damage: 65, headMult: 1.0, pellets: 1, magSize: 4, reserve: 20, rpm: 75, auto: false,
    reloadTime: 3.0, effectiveRange: 999, falloffEnd: 999, minDamageMult: 1,
    adsZoom: 1.15, adsTime: 0.22, adsMoveMult: 0.7,
    projectile: { kind: 'projectile', visual: 'crayon', speed: 70, gravity: 5, radius: 0.22, life: 8 },
    explosion: { radius: 3.5, maxDamage: 35, selfDamageMult: 0.5 },
    spread: { hip: 0.8, ads: 0.25, move: 0.6, air: 1.5, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 3.8, pitchGrowth: 0, pitchMax: 3.8, yaw: 0.6, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 4.2, recoveryDelay: 0.08, adsRecoilMult: 0.9,
    kick: { back: 0.3, up: 0.14, roll: 0.08, shake: 0.25 },
    colors: { main: '#e63946', accent: '#ffd23f', glow: '#ffef9f', tracer: '#ffd23f' },
    botRange: [8, 55],
  },
  starlightZapper: {
    id: 'starlightZapper', name: 'STARLIGHT ZAPPER', category: 'Energy toy blaster', slotHint: 1,
    blurb: '40-unit battery, no reloads. Recharges 1.8 s after you stop. Bloom builds as you hold.',
    damage: 19, headMult: 1.4, pellets: 1, magSize: 40, reserve: 0, rpm: 660, auto: true,
    reloadTime: 0, effectiveRange: 40, falloffEnd: 80, minDamageMult: 0.65,
    adsZoom: 1.35, adsTime: 0.18, adsMoveMult: 0.75,
    projectile: { kind: 'projectile', visual: 'bolt', speed: 135, gravity: 0, radius: 0.07, life: 0.8 },
    energy: { capacity: 40, perShot: 1, rechargeDelay: 1.8, rechargeRate: 12, lockoutUntil: 8 },
    spread: { hip: 1.3, ads: 0.35, move: 0.8, air: 2.5, bloomPerShot: 0.09, bloomMax: 3.2, bloomDecay: 3 },
    recoil: { kind: 'random', pitch: 0.3, pitchGrowth: 0, pitchMax: 0.3, yaw: 0.05, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 10, recoveryDelay: 0.08, adsRecoilMult: 0.8,
    kick: { back: 0.02, up: 0.01, roll: 0.01, shake: 0.02 },
    colors: { main: '#f2f7ff', accent: '#21e6ff', glow: '#5ff4ff', tracer: '#7ff9ff' },
    botRange: [6, 38],
  },
  jackBlaster: {
    id: 'jackBlaster', name: 'JACK-IN-THE-BLASTER', category: 'Marksman toy shotgun', slotHint: 1,
    blurb: 'A crank-powered jack-in-the-box that fires a tight 6-pellet choke. Reaches way further than a normal shotgun.',
    damage: 15, headMult: 1.3, pellets: 6, magSize: 6, reserve: 30, rpm: 105, auto: false,
    reloadTime: 2.4, effectiveRange: 26, falloffEnd: 55, minDamageMult: 0.45,
    adsZoom: 1.5, adsTime: 0.22, adsMoveMult: 0.7,
    projectile: { kind: 'hitscan', tracer: 'pellet' },
    spread: { hip: 2.4, ads: 1.05, move: 0.8, air: 2, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 2.2, pitchGrowth: 0, pitchMax: 2.2, yaw: 0.35, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 8, recoveryDelay: 0.05, adsRecoilMult: 0.8,
    kick: { back: 0.14, up: 0.1, roll: 0.05, shake: 0.15 },
    colors: { main: '#e63946', accent: '#ffd23f', glow: '#ffe8a3', tracer: '#ffd23f' },
    botRange: [4, 26],
  },
  plungerBow: {
    id: 'plungerBow', name: 'PLUNGER LONGBOW', category: 'Charge bow', slotHint: 1,
    blurb: 'Hold to draw, release to fire a suction-cup arrow. A tap barely tickles; a full 1-second draw does 80, and 128 to the head.',
    damage: 80, headMult: 1.6, pellets: 1, magSize: 12, reserve: 24, rpm: 75, auto: false,
    reloadTime: 2.2, effectiveRange: 999, falloffEnd: 999, minDamageMult: 1,
    adsZoom: 1.6, adsTime: 0.25, adsMoveMult: 0.7,
    projectile: { kind: 'projectile', visual: 'arrow', speed: 260, gravity: 2.5, radius: 0.08, life: 6 },
    charge: { time: 1.0, curve: 1.8, minSpeed: 90, maxSpeed: 260, moveMult: 0.72 },
    spread: { hip: 0.7, ads: 0.1, move: 0.6, air: 2, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 0.8, pitchGrowth: 0, pitchMax: 0.8, yaw: 0.2, yawGrowth: 0, yawBias: 0 },
    recoveryRate: 8, recoveryDelay: 0.05, adsRecoilMult: 0.8,
    kick: { back: 0.06, up: 0.02, roll: 0.02, shake: 0.06 },
    colors: { main: '#8d5a2b', accent: '#ff4d6d', glow: '#ffd6e0', tracer: '#ffd6e0' },
    botRange: [12, 75],
  },
  popcornPopper: {
    id: 'popcornPopper', name: 'POPCORN POPPER', category: '3-round burst carbine', slotHint: 1,
    blurb: 'Pop-pop-pop. Three kernels per trigger pull, 0.07 s apart. All three to the head is 96.',
    damage: 21, headMult: 1.5, pellets: 1, magSize: 30, reserve: 120, rpm: 190, auto: true,
    burst: { count: 3, gap: 0.07 },
    reloadTime: 2.1, effectiveRange: 42, falloffEnd: 85, minDamageMult: 0.7,
    adsZoom: 1.4, adsTime: 0.2, adsMoveMult: 0.7,
    projectile: { kind: 'hitscan', tracer: 'pellet' },
    spread: { hip: 1.9, ads: 0.25, move: 1.1, air: 3, bloomPerShot: 0.1, bloomMax: 1.2, bloomDecay: 6 },
    recoil: { kind: 'pattern', pitch: [0.55, 0.5, 0.6], yaw: [0.05, -0.12, 0.1], loopFrom: 0, jitter: 0.05 },
    recoveryRate: 9, recoveryDelay: 0.1, adsRecoilMult: 0.7,
    kick: { back: 0.04, up: 0.03, roll: 0.02, shake: 0.05 },
    colors: { main: '#ffd23f', accent: '#e63946', glow: '#fff3b0', tracer: '#fff3b0' },
    botRange: [8, 40],
  },
  walloper: {
    id: 'walloper', name: 'WALLOPER', category: 'Heavy marksman pistol', slotHint: 2,
    blurb: 'A hand cannon that hits like a truck. 90 body, 160 to the head, and it knocks toys off their feet. Only 3 rounds and a slow hammer.',
    damage: 90, headMult: 160 / 90, pellets: 1, magSize: 3, reserve: 18, rpm: 48, auto: false,
    reloadTime: 2.6, effectiveRange: 55, falloffEnd: 110, minDamageMult: 0.75,
    adsZoom: 1.6, adsTime: 0.24, adsMoveMult: 0.7,
    projectile: { kind: 'hitscan', tracer: 'precision' },
    spread: { hip: 1.6, ads: 0.05, move: 1.6, air: 3.5, bloomPerShot: 0, bloomMax: 0, bloomDecay: 5 },
    recoil: { kind: 'random', pitch: 6.5, pitchGrowth: 0, pitchMax: 6.5, yaw: 1.1, yawGrowth: 0, yawBias: 0.3 },
    recoveryRate: 9, recoveryDelay: 0.12, adsRecoilMult: 0.85,
    kick: { back: 0.32, up: 0.3, roll: 0.14, shake: 0.38 },
    colors: { main: '#7b2cbf', accent: '#ffd23f', glow: '#ffe8a3', tracer: '#ffd23f' },
    botRange: [10, 60],
    knockback: 9,
  },
};

// ---------------------------------------------------------------------------- scopes
/**
 * Scopes you can put on a weapon in the loadout menu.
 *  style 'none'    = the gun's own sights
 *  style 'reticle' = small optic on the gun + a lit reticle when aiming
 *  style 'overlay' = full scope picture when aiming
 *  style 'zoom'    = nothing on screen changes except the zoom; the normal crosshair stays (bow)
 */
export type ScopeId = 'iron' | 'dot' | 'ring' | 'x2' | 'x4' | 'x8' | 'bare' | 'eagle' | 'hawk';
export interface ScopeDef {
  id: ScopeId;
  name: string;
  blurb: string;
  /** null = use the weapon's own zoom */
  zoom: number | null;
  style: 'none' | 'reticle' | 'overlay' | 'zoom';
  /** how much slower you aim in (1 = same) */
  adsTimeMult: number;
}
export const SCOPES: Record<ScopeId, ScopeDef> = {
  iron: { id: 'iron', name: 'Toy Sights', blurb: "The gun's built-in sights. Fastest to aim.", zoom: null, style: 'none', adsTimeMult: 1 },
  dot: { id: 'dot', name: 'Gumdrop Dot', blurb: '1.35x lit dot. Quick and clean for close fights.', zoom: 1.35, style: 'reticle', adsTimeMult: 1 },
  ring: { id: 'ring', name: 'Hula Ring', blurb: '1.75x ring sight. Good all-rounder.', zoom: 1.75, style: 'reticle', adsTimeMult: 1.1 },
  x2: { id: 'x2', name: 'Peekaboo 2.5x', blurb: '2.5x scope. Mid range.', zoom: 2.5, style: 'overlay', adsTimeMult: 1.2 },
  x4: { id: 'x4', name: 'Spyglass 4x', blurb: '4x scope for long shots. Slower to aim.', zoom: 4, style: 'overlay', adsTimeMult: 1.35 },
  x8: { id: 'x8', name: 'Telescope 8x', blurb: '8x. Across-the-map shots, very slow to aim.', zoom: 8, style: 'overlay', adsTimeMult: 1.7 },
  bare: { id: 'bare', name: 'Bare Bow 1.6x', blurb: 'Zooms the crosshair in a little. Nothing else on screen.', zoom: 1.6, style: 'zoom', adsTimeMult: 1 },
  eagle: { id: 'eagle', name: 'Eagle Eye 2.5x', blurb: 'Zooms the crosshair in 2.5x. No scope picture.', zoom: 2.5, style: 'zoom', adsTimeMult: 1.1 },
  hawk: { id: 'hawk', name: 'Hawk Eye 4x', blurb: 'Zooms the crosshair in 4x. No scope picture.', zoom: 4, style: 'zoom', adsTimeMult: 1.25 },
};
/** Which scopes fit which weapon. The first one is the default (bots always use it). */
export const WEAPON_SCOPES: Record<WeaponId, ScopeId[]> = {
  plasti9: ['iron', 'dot'],
  foamFury: ['iron', 'dot', 'ring', 'x2'],
  brickbreaker: ['iron', 'dot', 'ring', 'x2', 'x4'],
  bubbleBlaster: ['iron', 'dot'],
  thunderspring: ['x4', 'x2', 'x8'],
  rapidRascal: ['iron', 'dot', 'ring'],
  crayonCannon: ['iron', 'ring', 'x2'],
  starlightZapper: ['iron', 'dot', 'ring', 'x2'],
  jackBlaster: ['iron', 'dot', 'ring', 'x2', 'x4'],
  plungerBow: ['bare', 'eagle', 'hawk'],
  popcornPopper: ['iron', 'dot', 'ring', 'x2', 'x4'],
  walloper: ['iron', 'dot', 'ring', 'x2'],
};
/** Every weapon draws its own reticle shape inside whatever scope is fitted. */
export type ReticleShape = 'dot' | 'chevron' | 'brick' | 'bubbles' | 'cross' | 'circleDot' | 'crayon' | 'star' | 'jack' | 'kernels' | 'boom';
export const RETICLES: Record<WeaponId, ReticleShape> = {
  plasti9: 'dot',
  foamFury: 'chevron',
  brickbreaker: 'brick',
  bubbleBlaster: 'bubbles',
  thunderspring: 'cross',
  rapidRascal: 'circleDot',
  crayonCannon: 'crayon',
  starlightZapper: 'star',
  jackBlaster: 'jack',
  plungerBow: 'dot',
  popcornPopper: 'kernels',
  walloper: 'boom',
};

export const WEAPON_ORDER: WeaponId[] = [
  'plasti9', 'foamFury', 'brickbreaker', 'bubbleBlaster', 'thunderspring', 'rapidRascal', 'crayonCannon', 'starlightZapper', 'jackBlaster', 'plungerBow', 'popcornPopper', 'walloper',
];

/** Movement + ability tuning, also editable in one place. */
export const MOVE = {
  walkSpeed: 5.5,
  sprintMult: 1.45,
  crouchSpeed: 2.8,
  jumpVelocity: 6.5,
  gravity: 15,
  groundAccel: 65,
  groundDecel: 50,
  airAccel: 14,
  airControl: 0.3,
  coyoteTime: 0.12,
  jumpBuffer: 0.13,
  slideDuration: 0.8,
  slideCooldown: 2.0,
  slideBoost: 10.5,
  dashDuration: 0.35,
  dashCooldown: 5,
  dashSpeed: 19,
  radius: 0.4,
  standHalfHeight: 0.5,
  crouchHalfHeight: 0.2,
  standEye: 1.55,
  crouchEye: 0.98,
};

export const COMBAT = {
  maxHealth: 100,
  maxShield: 50,
  regenDelay: 6,
  regenRate: 8,
  respawnTime: 5,
  /** team modes: hold E on a downed teammate this long to bring them back */
  reviveTime: 3,
  reviveRange: 2.4,
  reviveHealth: 60,
  spawnProtection: 1.5,
  killTarget: 30,
  matchTime: 600,
};

export const PICKUPS = {
  healthAmount: 35,
  shieldAmount: 50,
  turboMult: 1.25,
  turboTime: 8,
  infiniteTime: 6,
  powerMult: 1.2,
  powerTime: 8,
  respawn: { health: 15, shield: 25, turbo: 40, infinite: 40, power: 45, weapon: 18 } as Record<string, number>,
};

/** Abilities (all keys can be rebound in Player.ts). */
export type AbilityId = 'dash' | 'jab' | 'grapple' | 'cloak' | 'shield';
export const ABILITIES = {
  dash: { name: 'Wind-Up Dash', key: 'Q', cooldown: 5 },
  jab: { name: 'Spring Punch', key: 'V', cooldown: 3, damage: 50, range: 2.6, coneDeg: 38, knockback: 7 },
  grapple: { name: 'Spring Hook', key: 'F', cooldown: 7, missCooldown: 1, range: 48, speed: 27, maxTime: 2.4 },
  /** active up to maxActive; cooldown = time it was active + baseCooldown */
  cloak: { name: 'Cloak', key: 'Z', maxActive: 15, baseCooldown: 5, revealDistance: 2.5 },
  shield: { name: 'Mesh Shield', key: 'X', cooldown: 15, duration: 7, hp: 260, width: 2.8, height: 2.2 },
} as const;
export const ABILITY_ORDER: AbilityId[] = ['dash', 'jab', 'grapple', 'cloak', 'shield'];

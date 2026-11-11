import * as THREE from 'three';

/** Game mode definitions. Tweak targets / timers here. */
export type ModeId = 'ffa' | 'tdm' | 'takeover' | 'conquest';

export interface ModeDef {
  id: ModeId;
  name: string;
  short: string;
  blurb: string;
  teams: boolean;
  /** 0 = free-for-all */
  teamCount: number;
  /** AI toys in the match (the player is extra) */
  botCount: number;
  scoreTarget: number;
  timeLimit: number; // seconds
  scoreLabel: string; // what the score counts
}

export const MODES: Record<ModeId, ModeDef> = {
  ffa: {
    id: 'ffa',
    name: 'Toybox Free-for-All',
    short: 'Free-for-All',
    blurb: 'You and fourteen toys, everyone for themselves. Seven of them start up on the high shelves. First to 30 pops wins, or whoever leads when the 10-minute timer runs out.',
    teams: false,
    teamCount: 0,
    botCount: 14,
    scoreTarget: 30,
    timeLimit: 600,
    scoreLabel: 'pops',
  },
  tdm: {
    id: 'tdm',
    name: 'Team Deathmatch',
    short: 'Team Deathmatch',
    blurb: 'Four toys a side: Team Sunrise against Team Moonbeam. Every pop scores for your team. First team to 50 wins. No friendly fire.',
    teams: true,
    teamCount: 2,
    botCount: 7,
    scoreTarget: 50,
    timeLimit: 600,
    scoreLabel: 'pops',
  },
  takeover: {
    id: 'takeover',
    name: 'Toy Box Takeover',
    short: 'Toy Box Takeover',
    blurb: 'A giant toy box lands somewhere in the room and moves every 60 seconds. Stand inside it with no enemies around to wind up your team’s key. First team to 150 wins.',
    teams: true,
    teamCount: 2,
    botCount: 7,
    scoreTarget: 150,
    timeLimit: 600,
    scoreLabel: 'wind-up',
  },
  conquest: {
    id: 'conquest',
    name: 'Conquest',
    short: 'Conquest',
    blurb: 'Three teams of three fight over the six sectors of the room. Every team starts with one sector, three are up for grabs. Stand in a sector to capture it. The first team to control 4 of the 6 wins.',
    teams: true,
    teamCount: 3,
    botCount: 8,
    scoreTarget: 4,
    timeLimit: 600,
    scoreLabel: 'sectors',
  },
};

export const MODE_ORDER: ModeId[] = ['ffa', 'tdm', 'takeover', 'conquest'];

export interface TeamDef {
  name: string;
  color: string; // main
  light: string; // text on dark
  dark: string;
}

export const TEAMS: TeamDef[] = [
  { name: 'Sunrise', color: '#ff9f1c', light: '#ffc46b', dark: '#a85a00' },
  { name: 'Moonbeam', color: '#4c8dff', light: '#8fb8ff', dark: '#1f3f99' },
  { name: 'Clover', color: '#3ddc84', light: '#8ff0b6', dark: '#1a7a45' },
];
/** winnerTeam value for a tie */
export const DRAW = -2;

/** Where the toy box can land. Center is the floor point; radius in meters. */
export interface HillSite {
  name: string;
  pos: THREE.Vector3;
  radius: number;
  height: number; // how tall the capture volume is
}

export const HILL_SITES: HillSite[] = [
  { name: 'the Play Rug', pos: new THREE.Vector3(2, 0, 1), radius: 5.2, height: 6 },
  { name: 'the Bed Fortress', pos: new THREE.Vector3(-25.5, 6, -21), radius: 4.6, height: 4 },
  { name: 'the Toy Garage deck', pos: new THREE.Vector3(27.5, 4, 30), radius: 4.2, height: 4 },
  { name: 'the Desk Outpost', pos: new THREE.Vector3(20.5, 8, -28.5), radius: 4.6, height: 4.5 },
  { name: 'Dinosaur Kingdom', pos: new THREE.Vector3(-15, 0, 26.5), radius: 5, height: 5 },
  { name: 'the Brick District', pos: new THREE.Vector3(-22, 0.3, 1.5), radius: 4.6, height: 5 },
  { name: 'the Closet Maze', pos: new THREE.Vector3(25.5, 0, -3.8), radius: 4.2, height: 4 },
];

export const TAKEOVER = {
  hillDuration: 60, // seconds the box stays put
  warnBefore: 10, // seconds of "moving soon" warning
  pointsPerSecond: 1,
  bonusPerExtraToy: 0.25, // extra rate per additional teammate inside (max +0.5)
};

/** Conquest: the six sectors are the Toy Box Takeover sites minus the Play Rug in the middle. */
export interface SectorDef extends HillSite {
  letter: string;
  short: string;
}
export const SECTORS: SectorDef[] = [
  { ...HILL_SITES[1], letter: 'B', short: 'Bed' },
  { ...HILL_SITES[3], letter: 'D', short: 'Desk' },
  { ...HILL_SITES[6], letter: 'C', short: 'Closet' },
  { ...HILL_SITES[2], letter: 'G', short: 'Garage' },
  { ...HILL_SITES[4], letter: 'K', short: 'Dino' },
  { ...HILL_SITES[5], letter: 'R', short: 'Bricks' },
];
/** Starting sector of each team (index into SECTORS): Sunrise = Bed, Moonbeam = Closet, Clover = Dinosaur Kingdom. */
export const CONQUEST_HOMES = [0, 2, 4];

/** Swap in another map's objective spots (the arrays above are edited in place so every importer sees them). */
export function useMapSites(hill: HillSite[], sectors: SectorDef[], homes: number[]) {
  HILL_SITES.splice(0, HILL_SITES.length, ...hill);
  SECTORS.splice(0, SECTORS.length, ...sectors);
  CONQUEST_HOMES.splice(0, CONQUEST_HOMES.length, ...homes);
}

export const CONQUEST = {
  sectorsToWin: 4,
  neutralizeTime: 8, // seconds for one toy to drain an enemy sector to neutral
  captureTime: 8, // seconds for one toy to fill a neutral sector
  bonusPerExtraToy: 0.25, // +25% speed per extra teammate inside (max 2 extra)
  decayRate: 0.06, // abandoned half-captures drain back per second
};

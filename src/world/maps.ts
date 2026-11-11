import * as THREE from 'three';
import type { Physics } from '../physics/Physics';
import type { Effects } from '../fx/Effects';
import type { AudioEngine } from '../audio/Audio';
import { ArenaInfo, buildArena, ELEVATOR_SITES, SHELF } from './Arena';
import { Ambient } from './Ambient';
import { buildBackyard, YARD, YARD_ELEVATORS, YARD_HILL_SITES, YARD_HOMES, YARD_SECTORS } from './Backyard';
import { AmbientLike, YardAmbient } from './YardAmbient';
import { buildKitchen, KITCHEN, KITCHEN_ELEVATORS, KITCHEN_HILL_SITES, KITCHEN_HOMES, KITCHEN_SECTORS, KitchenAmbient } from './Kitchen';
import type { ElevatorSite } from './Elevators';
import { CONQUEST_HOMES, HILL_SITES, HillSite, SECTORS, SectorDef } from '../match/modes';
import { settings } from '../core/Settings';

export type MapId = 'bedroom' | 'backyard' | 'kitchen';

export interface MapDef {
  id: MapId;
  name: string;
  blurb: string;
  loading: string;
  build(scene: THREE.Scene, phys: Physics): ArenaInfo;
  ambient(scene: THREE.Scene, arena: ArenaInfo, phys: Physics, fx: Effects, audio: AudioEngine): AmbientLike;
  elevators: { sites: ElevatorSite[]; topY: number };
  hillSites: HillSite[];
  sectors: SectorDef[];
  homes: number[];
  /** nav nodes above this height are the "high ground" the seven newcomers start on in Free-for-All */
  highY: number;
  /** falling-block events (bedroom only) */
  blockDrops: boolean;
  sky: { background: string; fog: [string, number, number]; env: number; exposure: number };
  menuCam: { r: number; h: number };
  ffaIntro: string;
}

export const MAPS: Record<MapId, MapDef> = {
  bedroom: {
    id: 'bedroom',
    name: 'Bedroom Brawl',
    blurb: "The original kid's bedroom: bed fortress, desk, closet maze, and a high shelf with a toy train.",
    loading: 'Building the bedroom',
    build: buildArena,
    ambient: (scene, arena, phys, fx, audio) => new Ambient(scene, arena, phys, fx, audio),
    elevators: { sites: ELEVATOR_SITES, topY: SHELF.y },
    // copies: the live arrays in modes.ts get overwritten when a map is applied
    hillSites: [...HILL_SITES],
    sectors: [...SECTORS],
    homes: [...CONQUEST_HOMES],
    highY: 20,
    blockDrops: true,
    sky: { background: '#f2e2cc', fog: ['#f1dfc6', 70, 190], env: 0.42, exposure: 0.98 },
    menuCam: { r: 18, h: 9 },
    ffaIntro: 'Seven toys are up on the shelves. Ramps and elevators lead up there.',
  },
  backyard: {
    id: 'backyard',
    name: 'Sandbox Showdown',
    blurb: 'A sunny backyard: sand castle in the middle, picnic table, back porch, kiddie pool, flower garden, dump truck, and a play tower with a slide.',
    loading: 'Mowing the lawn',
    build: buildBackyard,
    ambient: (scene) => new YardAmbient(scene),
    elevators: { sites: YARD_ELEVATORS, topY: YARD.deckY },
    hillSites: YARD_HILL_SITES,
    sectors: YARD_SECTORS,
    homes: YARD_HOMES,
    highY: 6.4,
    blockDrops: false,
    sky: { background: '#8fd0ff', fog: ['#bfe6ff', 120, 420], env: 0.5, exposure: 0.8 },
    menuCam: { r: 22, h: 12 },
    ffaIntro: 'Seven toys start up high: on the picnic table, the porch and the play tower.',
  },
  kitchen: {
    id: 'kitchen',
    name: 'Kitchen Clash',
    blurb: 'New. A family kitchen: the island in the middle, a dining table, a long counter, the open oven, a pulled-out freezer drawer, cereal-box city and the dog bowl.',
    loading: 'Wiping down the counters',
    build: buildKitchen,
    ambient: (scene) => new KitchenAmbient(scene),
    elevators: { sites: KITCHEN_ELEVATORS, topY: KITCHEN.deck },
    hillSites: KITCHEN_HILL_SITES,
    sectors: KITCHEN_SECTORS,
    homes: KITCHEN_HOMES,
    highY: 6.5,
    blockDrops: false,
    sky: { background: '#fbe8c8', fog: ['#f6e7cf', 90, 230], env: 0.5, exposure: 0.95 },
    menuCam: { r: 20, h: 12 },
    ffaIntro: 'Seven toys start up high: on the island, the dining table and the counter.',
  },
};
export const MAP_ORDER: MapId[] = ['bedroom', 'backyard', 'kitchen'];

/** The map chosen in the menu (maps are built once per page load; changing it reloads the page). */
export function selectedMap(): MapDef {
  return MAPS[(settings.data.map as MapId) in MAPS ? (settings.data.map as MapId) : 'bedroom'];
}

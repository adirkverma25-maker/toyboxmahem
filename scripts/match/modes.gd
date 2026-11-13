class_name Modes
## Game mode definitions (port of src/match/modes.ts). Tweak targets / timers here.

const MODES := {
	"ffa": {
		"id": "ffa", "name": "Toybox Free-for-All", "short": "Free-for-All",
		"blurb": "You and fourteen toys, everyone for themselves. Seven of them start up on the high shelves. First to 30 pops wins, or whoever leads when the 10-minute timer runs out.",
		"teams": false, "teamCount": 0, "botCount": 14, "scoreTarget": 30, "timeLimit": 600.0, "scoreLabel": "pops",
	},
	"tdm": {
		"id": "tdm", "name": "Team Deathmatch", "short": "Team Deathmatch",
		"blurb": "Four toys a side: Team Sunrise against Team Moonbeam. Every pop scores for your team. First team to 50 wins. No friendly fire.",
		"teams": true, "teamCount": 2, "botCount": 7, "scoreTarget": 50, "timeLimit": 600.0, "scoreLabel": "pops",
	},
	"takeover": {
		"id": "takeover", "name": "Toy Box Takeover", "short": "Toy Box Takeover",
		"blurb": "A giant toy box lands somewhere in the room and moves every 60 seconds. Stand inside it with no enemies around to wind up your team’s key. First team to 150 wins.",
		"teams": true, "teamCount": 2, "botCount": 7, "scoreTarget": 150, "timeLimit": 600.0, "scoreLabel": "wind-up",
	},
	"conquest": {
		"id": "conquest", "name": "Conquest", "short": "Conquest",
		"blurb": "Three teams of three fight over the six sectors of the room. Every team starts with one sector, three are up for grabs. Stand in a sector to capture it. The first team to control 4 of the 6 wins.",
		"teams": true, "teamCount": 3, "botCount": 8, "scoreTarget": 4, "timeLimit": 600.0, "scoreLabel": "sectors",
	},
	"training": {
		"id": "training", "name": "Training Range", "short": "Training",
		"blurb": "Practice on the current map. Six toys run around but never shoot back, ammo never runs out, there is no timer, and you can try any blaster from the pause menu. Nothing counts toward your record.",
		"teams": false, "teamCount": 0, "botCount": 6, "scoreTarget": 0, "timeLimit": 0.0, "scoreLabel": "pops", "training": true,
	},
}
## the Play screen's modes (Training has its own button on the main menu)
const MODE_ORDER := ["ffa", "tdm", "takeover", "conquest"]

const TEAMS := [
	{"name": "Sunrise", "color": "#ff9f1c", "light": "#ffc46b", "dark": "#a85a00"},
	{"name": "Moonbeam", "color": "#4c8dff", "light": "#8fb8ff", "dark": "#1f3f99"},
	{"name": "Clover", "color": "#3ddc84", "light": "#8ff0b6", "dark": "#1a7a45"},
]
## winner_team value for a tie
const DRAW := -2

const TAKEOVER := {
	"hillDuration": 60.0,  # seconds the box stays put
	"warnBefore": 10.0,  # seconds of "moving soon" warning
	"pointsPerSecond": 1.0,
	"bonusPerExtraToy": 0.25,  # extra rate per additional teammate inside (max +0.5)
}

const CONQUEST := {
	"sectorsToWin": 4,
	"neutralizeTime": 8.0,  # seconds for one toy to drain an enemy sector to neutral
	"captureTime": 8.0,  # seconds for one toy to fill a neutral sector
	"bonusPerExtraToy": 0.25,  # +25% speed per extra teammate inside (max 2 extra)
	"decayRate": 0.06,  # abandoned half-captures drain back per second
}

## Where the toy box can land: {name, pos (floor point), radius, height}. Swapped per map (use_map_sites).
static var HILL_SITES: Array = [
	{"name": "the Play Rug", "pos": Vector3(2, 0, 1), "radius": 5.2, "height": 6.0},
	{"name": "the Bed Fortress", "pos": Vector3(-25.5, 6, -21), "radius": 4.6, "height": 4.0},
	{"name": "the Toy Garage deck", "pos": Vector3(27.5, 4, 30), "radius": 4.2, "height": 4.0},
	{"name": "the Desk Outpost", "pos": Vector3(20.5, 8, -28.5), "radius": 4.6, "height": 4.5},
	{"name": "Dinosaur Kingdom", "pos": Vector3(-15, 0, 26.5), "radius": 5.0, "height": 5.0},
	{"name": "the Brick District", "pos": Vector3(-22, 0.3, 1.5), "radius": 4.6, "height": 5.0},
	{"name": "the Closet Maze", "pos": Vector3(25.5, 0, -3.8), "radius": 4.2, "height": 4.0},
]
## Conquest sectors: hill site + {letter, short}
static var SECTORS: Array = []
## Starting sector of each team (index into SECTORS)
static var CONQUEST_HOMES: Array = [0, 2, 4]


static func sector(site: Dictionary, letter: String, short: String) -> Dictionary:
	var s := site.duplicate()
	s.letter = letter
	s.short = short
	return s


static func _static_init() -> void:
	SECTORS = [
		sector(HILL_SITES[1], "B", "Bed"),
		sector(HILL_SITES[3], "D", "Desk"),
		sector(HILL_SITES[6], "C", "Closet"),
		sector(HILL_SITES[2], "G", "Garage"),
		sector(HILL_SITES[4], "K", "Dino"),
		sector(HILL_SITES[5], "R", "Bricks"),
	]


## Swap in another map's objective spots.
static func use_map_sites(hill: Array, sectors: Array, homes: Array) -> void:
	HILL_SITES = hill
	SECTORS = sectors
	CONQUEST_HOMES = homes

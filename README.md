# TOYBOX MAYHEM

A 3D first-person arena shooter where living toys fight over a kid's bedroom and backyard. You plus up to 14 AI toys, four modes, three maps, twelve blasters to unlock, and saved accounts.

## Maps

Pick the map on the Play screen. A map is built when the page loads, so choosing the other one reloads the page and drops you back on the Play screen.

| Map | What's in it |
| --- | --- |
| **Bedroom Brawl** | the original: Bed Fortress, Desk Outpost, Closet Maze, Toy Garage, Dinosaur Kingdom, Brick District, and the high shelf with the toy train (3 ramps, 3 elevators) |
| **Kitchen Clash** (new) | a family kitchen: the kitchen island in the middle (cutting-board ramp, stools, elevator), a dining table with chairs (plank + elevator), the long counter along the north wall (cutting-board plank + elevator, toaster/blender/kettle as cover), the open oven door (E) and a pulled-out freezer drawer (W) as ledges, cereal-box city, the pantry with a stock pot you can stand on, and the dog bowl. Conquest sectors: Dog Bowl (Sunrise), Oven Door (Moonbeam), Pantry (Clover), with Freezer Drawer, Cereal City and Dining Table up for grabs |
| **Sandbox Showdown** | a sunny backyard: sandbox with a sand castle in the middle, picnic table (planks up, plus an elevator), back porch (steps, plus an elevator), kiddie pool with a rubber duck, flower garden planter, toy dump truck you can run up, and a play tower with a slide. Conquest sectors: Play Tower (Sunrise), Kiddie Pool (Moonbeam), Flower Garden (Clover), with Picnic Table, Back Porch and Dump Truck up for grabs |

Map-specific code: `src/world/Arena.ts` (bedroom), `src/world/Backyard.ts` (backyard), `src/world/Kitchen.ts` (kitchen), and `src/world/maps.ts` ties each map to its objectives, elevators and sky.

## Accounts, coins and unlocks

- **Accounts.** The first time the game opens it asks you to **create an account**, **log in** or **play as a guest**. Each account has its own coins, unlocked blasters, career stats, loadout, settings and key bindings. Switch or log out from the bar at the top right of the main menu. Accounts are saved in this browser on this computer; the password is stored only as a salted PBKDF2 hash. Online accounts will come with multiplayer (see `docs/multiplayer-and-godot.md`). Code: `src/core/Accounts.ts`.
- **Coins.** Every finished match pays out, and the results screen shows the breakdown: 25 for finishing, 10 per pop, +5 per headshot pop, 15 per revive, 25 for a 5-pop streak (50 for 10), 75 for a win (FFA: 40 for 2nd, 20 for 3rd), then x0.75 on Easy and x1.35 on Hard. Quitting early pays nothing.
- **Unlocks.** You start with three blasters: **Foam Fury**, **Jack-in-the-Blaster** and **Plasti-9**. Unlock the rest with coins on the Loadout screen. Locked blasters show their price; picking one shows an **Unlock** button.

| Tier | Blasters | Price |
| --- | --- | --- |
| Starter | Foam Fury, Jack-in-the-Blaster, Plasti-9 | free |
| Common | Bubble Blaster, Rapid Rascal | 300 |
| Rare | Brickbreaker, Starlight Zapper / Crayon Cannon | 600 / 800 |
| Epic | Thunderspring, Plunger Longbow | 1,000 |
| Legendary | Popcorn Popper / **Walloper** | 1,500 / 1,800 |

Prices and rewards are in `src/core/Progress.ts`. Bots aren't limited by unlocks.

**Unlock everything:** on the Loadout screen, type the code `TOYBOXFREE` in **Have a code?** and press Redeem. Every blaster unlocks for the account you're logged into.

## Loadout and scopes

There are no weapon pick-ups on the maps any more. On the main menu open **Loadout and unlocks** (also on the Play screen and the pause menu) and pick a primary and a secondary from the blasters you've unlocked, plus a scope for each. It's saved in the browser. Changing it mid-match applies on your next respawn. Every pick-up (health battery, shield, power-ups) also refills half your reserve ammo for both weapons.

| Scope | Zoom | What you see when aiming |
| --- | --- | --- |
| Toy Sights | the gun's own | the gun's built-in sights |
| Gumdrop Dot | 1.35x | small hoop on the gun + a lit reticle |
| Hula Ring | 1.75x | bigger hoop + lit reticle |
| Peekaboo | 2.5x | full scope picture |
| Spyglass | 4x | full scope picture, slower to aim |
| Telescope | 8x | full scope picture, slowest (Thunderspring only) |
| Bare Bow / Eagle Eye / Hawk Eye | 1.6x / 2.5x / 4x | bow only: nothing but the zoom, the normal crosshair stays |

Every weapon draws its own reticle inside whatever scope is fitted (chevron on the Foam Fury, a brick on the Brickbreaker, a star on the Zapper, three kernels on the Popcorn Popper, a jack-in-the-box face on the Jack-in-the-Blaster, and so on), and the scope ring takes the weapon's colors. Which scopes fit which gun, and all the zoom numbers, are in `SCOPES` / `WEAPON_SCOPES` at the bottom of `src/weapons/weaponConfig.ts`.

## Revive and spectate (team modes)

- Respawn takes 5 seconds in every mode.
- In Team Deathmatch, Toy Box Takeover and Conquest a popped toy lies where it fell, with a team-colored ring and a spinning plus over it. Stand next to a downed teammate and **hold E for 3 seconds** to put them back together on the spot with 60 health. Let go and the progress drains away. If nobody gets there, they respawn normally when the 5 seconds are up. The pop still counts for whoever got it.
- Bot teammates revive too: if one is close enough to make it in time, has decent health and isn't being shot at, it runs over and holds on. They revive you as well.
- While you're down the camera follows a living teammate from behind. Left click (or Space) for the next one, right click for the previous one.
- Free-for-All has no teammates, so no revive and the old death camera.

## Game modes

| Mode | Teams | How you win |
| --- | --- | --- |
| **Free-for-All** | everyone for themselves (15 toys: you + 14; the 7 newcomers start and respawn up on the high shelves) | first to 30 pops, or most pops after 10 minutes |
| **Team Deathmatch** | 4 vs 4: Team Sunrise (orange) vs Team Moonbeam (blue) | first team to 50 pops, or most after 10 minutes |
| **Conquest** | 3 vs 3 vs 3: Sunrise (orange), Moonbeam (blue), Clover (green) | six sectors (the Toy Box Takeover spots minus the Play Rug). Each team starts with one (Sunrise = Bed Fortress, Moonbeam = Closet Maze, Clover = Dinosaur Kingdom), the Desk, Garage and Brick District start empty. Stand in a sector to take it: about 8 s to drain an enemy sector to neutral, 8 s to capture a neutral one, +25% per extra teammate inside, frozen while two teams are inside. The first team to control 4 of 6 wins on the spot. At the 10-minute mark the team with the most sectors wins (a tie is a draw) |
| **Toy Box Takeover** | 4 vs 4 | a giant toy box lands in one part of the room and moves every 60 s (10 s warning). Stand inside it with no enemies in it to wind up your team's key: 1 point per second, +0.25 per extra teammate inside. Enemies inside too = contested, nobody scores. First to 150, or most after 10 minutes |

Team modes: you're always on Team Sunrise. No friendly fire (your shots pass straight through teammates). Teammates wear an orange sash and flag, get an orange outline, and have a name tag over their head. Sunrise spawns on the bed/desk half of the room, Moonbeam on the dino/garage half. In Takeover a marker shows where the toy box is (pinned to the screen edge when it's behind you) and the bar under the timer says who's holding it and when it moves.

Bots in Takeover split into holders (go sit in the box) and hunters (patrol the approaches). In Team Deathmatch they regroup with teammates now and then. In Conquest every team has a "director" that re-plans every 2 seconds: defend sectors that are under attack, grab empty ones, and gang up on whichever team is about to reach 4. Bots stick to their assignment unless something more urgent comes up, so they don't run in circles.

Every mode: respawn takes 5 seconds (see Revive above). Bots are warier than before: they back off once their health drops to roughly 35-65% (careful toys earlier) or after taking a burst of damage, head for a health battery if one is nearby and not toward the enemy, and use cloak, the mesh shield or the hook to get away.

All mode numbers live in `src/match/modes.ts`.

## Play it

### Option A: no install (quickest)
Open `standalone/ToyboxMayhem.html` in Chrome or Edge (double-click it). Everything (code, physics, fonts) is inside that one file.
Click **Play**, pick a mode and a difficulty, then **Start match**. Click the game window if the mouse isn't captured.

### Option B: from source (for editing the code)
Needs Node.js 18+ (https://nodejs.org).

```bash
npm install
npm run dev          # opens http://localhost:5173
```

Other commands:

```bash
npm run build              # production build into dist/
npm run build:standalone   # rebuilds standalone/ToyboxMayhem.html (rename index.html in that folder)
npm run typecheck          # TypeScript check only
npm run server             # multiplayer dev server on ws://localhost:8787 (see docs/multiplayer-and-godot.md)
```

### Multiplayer (groundwork) and Godot

Multiplayer isn't playable from the menus yet. What exists: a message protocol (`src/net/protocol.ts`), a browser client with reconnects, ping and smooth interpolation (`src/net/NetClient.ts`), and a relay server with rooms (`server/index.mjs`). During a match you can run `__toybox.net.connect('ws://localhost:8787', 'Me', 'room1')` in the browser console to join a room. `__toybox.exportMapGLB()` saves the current map as a `.glb` model for Godot or Blender. The research on Godot vs staying in the browser, and the roadmap, are in **[docs/multiplayer-and-godot.md](docs/multiplayer-and-godot.md)**.

## Controls

**Every control can be rebound.** Open **Controls** (main menu or pause menu), click a box (or highlight it with the D-pad and press A), then press the key, mouse button or controller button you want. Each action gets a key, an optional second key and a controller button. Esc cancels, Backspace clears a box, and if the new key was already used by another action the two swap. **Reset controls** puts the defaults back. Your bindings are saved in the browser. Fixed: Esc / the controller's Menu button pause, the mouse wheel switches weapons, mouse / right stick look, left stick moves.

Defaults:

| Action | Keyboard / mouse | Controller (Xbox names) |
| --- | --- | --- |
| Move | W A S D | Left stick |
| Look | Mouse | Right stick |
| Fire (hold to draw the bow) | Left click | RT |
| Aim down sights | Right click | LT |
| Sprint (controller: toggles, stops when you let go of the stick or aim) | Shift | Click left stick |
| Jump | Space | A |
| Crouch / slide (crouch while sprinting) | Ctrl or C | B |
| Reload (vent on the Starlight Zapper) | R | X |
| Revive a downed teammate (hold 3 s, team modes) | E | Hold X (next to a downed teammate X revives instead of reloading) |
| Switch weapon | 1 / 2 / mouse wheel | Y |
| **Ability 1** | Q | RB |
| **Ability 2** | F | LB |
| Inspect weapon | T | D-pad left |
| While down: next / previous teammate to watch | Left click or Space / Right click | A or RT / LT |
| Scoreboard | Tab | View |
| Pause | Esc | Menu |

PlayStation: A = Cross, B = Circle, X = Square, Y = Triangle, LB/RB = L1/R1, LT/RT = L2/R2.

Browsers reserve Ctrl+W (close tab). Use C to crouch, or turn on Fullscreen in Settings, which asks the browser to lock the keyboard.

### Abilities: pick 2 of 5

On the **Loadout** screen choose which two abilities you bring (click a slot, then an ability; two clicks fill both slots). They go on the Ability 1 and Ability 2 buttons, and the HUD shows just those two. Changing them mid-match applies on your next respawn. Default: Dash + Hook.

| Ability | What it does |
| --- | --- |
| Wind-Up Dash | Burst forward a few meters (respects walls). 5 s cooldown |
| Spring Punch | 50 damage up close plus a shove. 3 s cooldown |
| Spring Hook | Grapple to a spot up to 48 m away; aim at a ledge face and it pulls you up and over. 7 s cooldown |
| Cloak | Press to turn on, press again to drop it. Invisible beyond 2.5 m for up to 15 s; cooldown = how long it was on + 5 s. Firing or punching drops it |
| Mesh Shield | Hex-wire wall in front of you for 7 s or 260 damage. Enemy shots stop on it, yours and your team's pass through. 15 s cooldown |

Bots also carry only two each, picked to suit their personality (rushers lean to Dash and Punch, careful toys to Shield and Cloak, jumpy ones to the Hook), and they only try to use the ones they have.

### Controller

Any standard controller works in Chrome or Edge (Xbox, PlayStation, Switch Pro and most others). Plug it in or pair it, then press any button so the browser notices it. The game switches to the controller as soon as you touch it and back to mouse and keyboard when you use those; the HUD button labels switch too. Menus work with the D-pad or left stick, A to select, B to go back.

Settings has a **Controller** section: look sensitivity, aim assist (on by default: slows your aim a little over an enemy, helps you follow them while you move, and nudges toward them when you start aiming down sights) and vibration. Invert Y applies to both mouse and stick. Code: `src/core/Bindings.ts` (actions and default bindings), `src/core/Input.ts` (keyboard, mouse, gamepad), `src/ui/PadNav.ts` (menus), aim assist in `src/entities/Player.ts`.

## What's in it

- **Arena**: one big bedroom at toy scale (you're ~15 cm tall). Bed Fortress (blanket slope, pillow cover, tunnels under the bed, blanket bridge to the toy chest), Brick District (castle walls, arches, a tower, loose bricks that scatter from explosions), Toy Garage (parking deck, ramps, rc cars driving a track), Desk Outpost (ruler ramp, book staircase, keyboard high ground, monitor), Dinosaur Kingdom (volcano that smokes, walkable brachiosaurus tail), Closet Maze (dark, shoebox walls, coats you can crouch under).
- **The high shelf** runs around all four walls at 21 m and is now a 4.2 m deep play space. Get up there by the wooden plank from the bed, the orange race-track ramp beside the desk, the blue building-block bridge from Dinosaur Kingdom, or one of the 3 toy elevators (south wall by the door, east wall past the closet, west wall by the Brick District). The elevators run on a loop: wait 3 s, ride 5 s; the lamp is green when it's parked, amber just before it leaves, red while moving. The toy train still runs along the wall side of the shelf and shoves you out of its way.
- **Background life**: toy train, wind-up robots (two now patrol the shelf walkway), ceiling fan shadow, sunbeam dust, wall clock, falling block events in some matches.
- **12 weapons**, all stats in `src/weapons/weaponConfig.ts`. New: the **WALLOPER**, a heavy marksman pistol: 90 body / 160 head (a one-shot headshot), 3-round magazine, 48 rpm, 2.6 s reload, big recoil, and every hit shoves the target back about 9 m/s and pops them off the ground. The rest: PLASTI-9, FOAM FURY, BRICKBREAKER, BUBBLE BLASTER (9 bubbles x 25: pops anyone within 5 m in one shot, even with a full shield), THUNDERSPRING, RAPID RASCAL, CRAYON CANNON (crayons now fly at 70 m/s on a shallow arc, was 22), STARLIGHT ZAPPER, **JACK-IN-THE-BLASTER** (marksman shotgun: 6 tight pellets x 15), the **PLUNGER LONGBOW** (hold to draw for up to 1 s; damage = 80 x draw^1.8, so a tap does about nothing and a full draw does 80 body / 128 head, which pops a full-health toy; arrows leave at 90 to 260 m/s depending on the draw and barely drop) and the **POPCORN POPPER** (3-round burst carbine: 21 per kernel, 0.07 s apart, hold the trigger to keep bursting). Mix of hitscan and real projectiles (swept raycasts, so nothing tunnels through walls).
- **Recoil** split into weapon-model kick, camera recoil (deterministic patterns for rifles, controlled randomness for automatics), bullet spread/bloom, recovery and ADS modifiers. All frame-rate independent.
- **Movement**: 5.5 m/s walk, 1.45x sprint, 2.8 m/s crouch, 6.5 m/s jump, 0.8 s slide with 2 s cooldown, coyote time, jump buffering, air control, Wind-Up Dash (5 s cooldown, respects walls), Spring Hook (aim at a ledge face and it latches onto the top so you get pulled up and over; jump to let go early).
- **Combat**: 100 HP, up to 50 shield (absorbs first, no regen), health regen 8 HP/s after 6 s, headshots, damage falloff, damage numbers (white body, yellow head, blue shield), hit markers, direction indicators.
- **AI**: 14 toys with personalities (Captain Click, Rex Rampage, Bolt Buddy, Princess Panic, Turbo Tim, Mecha Max, Blockhead, and the newcomers Sergeant Snap, Dina-Mite, Sparky, Duchess Dazzle, Nitro Nina, Gearbox Gus, Brickette). Each bot brings two of the five abilities and uses whichever it has: punch when you're in their face, shield when they're pinned or reloading, hook up to you if you're on a ledge or to their goal, cloak to escape or sneak, and they ride the elevators. Cloaked enemies are invisible to bots beyond 2.5 m. State machine (patrol, search, engage, retreat, reload, seek pickup), A* on an auto-generated navigation graph, line-of-sight checks, hearing gunshots, cover, weapon switching by range, unstuck logic, 3 difficulties.
- **Pickups**: Health Battery, Bubble Shield, Turbo Wheels, Infinite Springs, Power Star, plus weapon pedestals.
- **Audio**: everything synthesized with Web Audio (no sound files): per-weapon layered shots with variations, reloads, material impacts and footsteps, spatial audio with occlusion, small-room reverb, zone ambience, adaptive music.
- **Settings** (saved in the browser): sensitivity, ADS sensitivity, invert Y, horizontal FOV 70 to 110, graphics Low/Medium/High, volumes, fullscreen, crosshair color/size/dot, reduced motion, camera shake, motion blur, enemy outlines, damage numbers, player name. Career stats are saved too.

## Graphics quality

- **Low**: no shadows, no post-processing, reduced resolution. Use this on integrated graphics.
- **Medium**: soft shadows, bloom, 2x MSAA.
- **High**: sharper shadows, bloom, ambient occlusion, 4x MSAA.

Turn on **Show frame rate** in Settings to check performance on your machine.

## Project layout

```
src/
  core/      Game loop, input + key bindings, settings, accounts, coins/unlocks, events, math
  net/       Multiplayer protocol + WebSocket client (groundwork)
  render/    Renderer + post-processing, procedural textures and materials
  world/     Bedroom arena, props, ambient animation (train, fan, rc cars...), toy box zone
  physics/   Rapier wrapper (colliders, character controller, raycasts)
  nav/       Navigation graph + A*
  entities/  Actor (shared movement), Player, Bot AI, toy character models
  weapons/   Weapon config, weapon state (ammo/reload/recoil), models, first-person viewmodel
  combat/    Hitscan, projectiles, explosions, damage authority
  fx/        Pooled particles, debris, decals, tracers
  audio/     Web Audio sound engine + procedural music
  match/     Mode definitions (modes.ts), match rules for all modes, pickups
  ui/        HUD, menus, styles
server/      Multiplayer dev server (Node + ws)
docs/        Design notes: multiplayer roadmap and the Godot research
tests/       Headless browser tests (need Playwright; not needed to play)
```

## Notes

- All art is procedural (built from shapes in code), so there are no downloaded assets or licensed characters. The fonts are Luckiest Guy and Baloo 2 (SIL Open Font License), bundled through npm.
- The tests in `tests/` were written for a headless Chromium. To run them yourself: `npm i -D playwright`, `npx playwright install chromium`, start `npm run dev`, then `node tests/full.mjs` (edit the browser path at the top of each file).

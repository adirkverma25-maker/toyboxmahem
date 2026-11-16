# Destructible environments (phase 1 of the realism overhaul)

Status: approved by the owner on 2026-11-15 ("done, ship this first").

## Why

The owner wants Toybox Mayhem to move toward the feel of a destruction-heavy arena shooter. The game takes its *ideas* (blowing new paths through walls, gadgets that use that, realistic-looking weapons) and keeps its own maps, names and look.

The overhaul has four projects, done in this order:
1. **Destruction** (this doc).
2. **New loadout plus nine gadgets.** Several gadgets use destruction.
3. **Realistic environment art.** Free CC0 libraries (Poly Haven, ambientCG) and real recorded sound, built on the destruction system so nothing has to be rebuilt.
4. **Realistic toy guns.** Godot-built multi-part guns with real reloads and real recorded sounds.

Destruction comes first because the new art has to be made of breakable pieces.

## Goals
- Props and cover shatter.
- Building walls and doors break into doorway-wide panels, so players can blast new entrances and sightlines.
- What breaks depends on material:
  - **Glass and thin cover:** any hit breaks it.
  - **Wood and cardboard:** bullets wear it down, and explosions break it fast.
  - **Brick and concrete:** only explosions damage it.
- Damage shows in stages: intact → cracked → broken.
- Breaking spawns flying chunks, dust and a crunch sound. Chunks are harmless, fade after a few seconds and are capped in number.
- Bots use holes that players open.
- Online, the host decides what breaks and every player sees the same holes.
- Every match starts with the map fully intact.

## Non-goals (this phase)
- **Floors, roofs, stairs and ramps never break.** Dropping through floors is "plan B", for later.
- **No structural collapse or building-falls-down physics.**
- **Bots don't deliberately blast walls.** That comes with the gadgets (breach drill, mines).
- **No new art style.** The pieces use the current materials; the realism pass reskins them later.

## Anti-goals (failure even if it works)
- **Frame rate drops more than about 10%** versus today on Toy City (windowed autotest `[perf]` / `[gpu]`).
- **Buildings left floating, or holes that strand players.** Corners, pillars, door frames, slabs and traversal anchors (pads, zip ends) never break.
- **Host and guest disagree about what's broken.**
- **An ordinary gunfight erases a building.** Hard walls take explosion damage only.
- **Anything that reads as a copy of THE FINALS** (names, look, maps).

## Constraints
- **Godot 4.7, GDScript, Jolt.** Everything is still built in code for this phase.
- **Static geometry is merged per material by `Batcher` for draw-call budget.** Breakable pieces must not each become a draw call.
- **Nav graph (`NavGraph`) is cached per map.** The key includes `Phys.static_fingerprint()`.
- **Online is host-authoritative with guest claims** (`Combat.local_auth`). Changing message types needs a protocol bump. The relay checks the version, so `server/worker.js` is redeployed with it.
- **Shipped as a new installer release.** Bump `config/version`, then `tools/build_installer.sh`, then a GitHub release.

## Approaches considered
- **A: walls and cover (chosen).** Props, cover, glass, building wall panels and doors break. Floors, stairs, roofs and the frame stay. Low risk for frame rate, bots and online sync, while still changing fights a lot.
- **B: A plus floors.** Holes in floors and roofs to drop through. Needs drop-down nav links and storeys built in pieces. Deferred; A is designed so B can be added.
- **C: full building collapse.** Hundreds of simultaneous rigid bodies, a structural support graph, heavy sync. Too slow for the owner's laptop and online play, and closest to copying THE FINALS. Rejected.

## Design

### Breakable pieces
- **A new `Destruction` node** (`scripts/world/destruction.gd`) owns every breakable piece on the map.
- **Each piece:** id (assigned in build order, so host and guests agree), axis-aligned box(es), material class, max/current HP, stage, a parent "group" (for mesh merging), and a collider.
- **Colliders:** a `StaticBody3D` on the `WORLD` layer, so movement, bullets and line of sight treat it as solid. Each one is tagged with meta `piece` = id.
- **Arena code adds pieces through new `Builder` calls** (e.g. `B.breakable_box(mn, mx, mat, cls, group)`). These go to `Destruction` instead of `Batcher`/static `Phys`.
  - `ArenaToyCity._wall` cuts each wall run into panels about 1.5–2 m wide between the door frames and corners.
  - Upper-storey walls are cut the same way, per storey band.
  - Corners, door frames, lintels over existing doors, floor bands and the cornice stay static.
- **Rendering:** pieces in the same group (one wall run, one prop) merge into one mesh per material. Breaking a piece rebuilds only its group's mesh. That keeps draw calls about equal to today and makes a rebuild a few dozen boxes.
- **Material classes and HP** (numbers to tune in play):

  | Class | HP | Bullets | Explosions | Examples |
  |---|---|---|---|---|
  | `glass` | 20 | ×1 | ×1 | windows, car windows, thin panels |
  | `soft` | 220 | ×1 | ×3 | cardboard, wood, crates, fences, benches |
  | `hard` | 700 | ×0 | ×1 | building walls, block walls |

- **Damage stages:** at ≤60% HP a piece is "cracked" (crack decals on it plus a darker tint); at 0 it breaks.

### What breaks on each map (the plan lists exact pieces)
- **Toy City:** building walls on every storey, except corners, pillars and frames. Also doors, shop windows, kiosks, benches, cones, crates and car windows. Cars themselves stay as cover.
- **Bedroom:** cardboard boxes and walls, the block walls of the Brick District, book stacks used as cover, crates. The bed, desk, shelves, floor and room walls stay.
- **Backyard:** fences, crates, planters, and the shed and porch walls where they're cover. Ground, the play tower frame, the pool and the house stay.
- **Never breakable:** anything a jump pad, zip end, hill zone, sector centre or spawn point stands on or depends on.

### Damage sources
- **Hitscan and projectile hits on a piece** call `Destruction.damage(id, amount, "bullet", point, normal)`, using the weapon's damage.
- **`Combat.explode`** damages every piece whose box is within the blast radius, with the same falloff as player splash, as `"blast"`.
- **Melee (Spring Punch) counts as `"bullet"`.**
- **Line-of-sight and AI raycasts are unchanged:** pieces are solid until broken.

### Breaking
- **On break:** remove the collider, rebuild the group mesh, then spawn chunks.
- **Chunks:** 4–8 small boxes in the piece's material, from a pooled `RigidBody3D` set on the `DEBRIS` layer.
  - Max 80 live, oldest recycled first.
  - They collide with the world but not characters, take an impulse away from the hit, sleep, then fade at about 6 s.
- **Plus:** a dust burst from the existing particle pools (keep `visible_instance_count` behaviour) and a synthesized crunch per material class in `audio_engine` (glass shatter, wood crack, masonry thud).
- **Chunks do no damage.**

### Bots / nav
- **Nav graph is built with breakable pieces on a separate collision layer** (or disabled), so it sees the space as open.
- **After the build, each link and node is tested against the breakable pieces:** the same horizontal rays at 0.35 / 1.45 m, plus the head and ground checks. The ids of pieces that block it are stored (`blockers`).
  - Nodes on top of a breakable piece are not created.
  - Nodes inside a piece's volume get that piece as a blocker.
- **`NavGraph.path` and `nearest` skip anything whose blockers include an unbroken piece.**
  - When a piece breaks, its links open with no rebuild.
  - Bots already moving re-path if their next link opens a shorter route. Optional: just on the next repath.
- **The cache stores blockers.** The cache key includes a fingerprint of the breakable pieces. Bump `CACHE_VERSION`.

### Online
- **The host is authoritative for piece HP and breaks.**
- **Guests send a claim `{g:"gpiece", id, dmg, kind}`** for their hits on pieces. They're sent the same way and as often as hit claims. The host caps and applies them.
- **The host sends `{e:"break", ids:[...]}` events** (batched per tick).
- **Joiners:** the match `start` message, and a periodic low-rate snapshot field, carry the list of broken ids, so late joiners and missed packets converge.
- **Guests show cracks and chips locally** for their own hits. They only remove pieces when the host says so.
- **Debris is never sent.**
- **`PROTOCOL_VERSION` goes to 101** in the game and in `server/worker.js`; the relay is redeployed.

### Reset
- **The map is rebuilt for each match,** as today, so every piece starts intact.

## Testing / done means
- **`sh tools/check.sh`** is clean.
- **New `--screen=destruct --map=<id>` (headless OK).** On each map it:
  - finds a path that is blocked by a wall;
  - breaks the pieces on it with an explosion;
  - checks the path now goes through the hole;
  - runs a bot through it;
  - checks that hard walls ignore bullets and that glass breaks on one hit.
  - Prints `[destruct] N failures`.
- **Headless autotests on all three maps:** no script errors, bots not below the floor.
- **Online test (host + guest, local relay):** the host blows walls. Both print the same sorted broken-id list.
- **Windowed perf on Toy City:** frame and GPU time within about 10% of before, measured as interleaved runs (timings on this laptop vary between runs).
- **Screenshots** of a cracked wall, a fresh hole with debris, and bedroom and backyard breakables.

## Shipping
- **Version 1.1.0:** rebuild the installer, redeploy the relay at protocol 101, publish a GitHub release.
- **The release notes say everyone needs the new version to play online together.**

## Left to the builder
- Exact panel widths and per-map piece lists, within the rules above.
- Crack decal look, chunk counts and sizes, sound recipes.
- Whether bots re-path immediately when a wall opens or on their next repath.
- HP tuning after playtesting the numbers above.

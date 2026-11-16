# Destructible Walls and Cover Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Props, cover, glass and building wall panels break (with cracks, debris, dust and sound), bots path through new holes, online stays in sync, shipped as 1.1.0.

**Architecture:** A `Destruction` node owns every breakable piece. Each piece is its own `StaticBody3D` collider on `Phys.WORLD`, with meta `piece`. Pieces are drawn as one merged mesh per group per material, and a group is rebuilt when one of its pieces changes. Combat routes world hits and explosions to it. `NavGraph` is built as if pieces were absent and stores the piece ids that block each node and link. The host owns HP and breaks; guests send claims.

**Tech Stack:** Godot 4.7 GDScript, Jolt, existing `Batcher`/`Builder`/`Phys`/`Effects`/`AudioEngine`, Cloudflare relay.

**Spec:** `docs/superpowers/specs/2026-11-15-destruction-design.md`

## Global Constraints
- Classes and HP: `glass` 20 HP (bullet ×1, blast ×1); `soft` 220 HP (bullet ×1, blast ×3); `hard` 700 HP (bullet ×0, blast ×1). A piece is cracked at ≤ 60% HP.
- Debris: 4–8 chunks per break, max 80 live (oldest recycled), `DEBRIS` layer, no collision with characters, no damage, fade at about 6 s.
- Never breakable: floors, roofs, stairs, ramps, corners, pillars, door frames, lintels over built doors, floor bands, cornice, and anything a pad, zip end, hill zone, sector centre or spawn stands on.
- Pools drawn with MultiMesh set `visible_instance_count` to the highest live slot.
- Frame/GPU time on Toy City within about 10% of before, using interleaved windowed runs.
- `PROTOCOL_VERSION` 101 in `scripts/net/net_client.gd` and `server/worker.js`. Ship `config/version` 1.1.0.
- No names, look or maps copied from THE FINALS.

## Review Focus
- **Explosion behind an unbroken piece:** pieces shielded by another unbroken piece on the line from the blast centre take no blast damage. Test: Task 3, `blast_is_blocked_by_nearer_piece`.
- **Guest claim on an already-broken or unknown piece id:** ignored with no error. Test: Task 6, `stale_piece_claim_ignored`.
- **Back to menu, then a new match on the same map:** every piece is intact again, with colliders, meshes and nav blockers restored. Test: Task 3, `reset_restores_everything`.
- **Bot mid-path when a wall opens:** keeps moving with no stall. A bot standing inside a just-broken crate's volume isn't stranded. Test: Task 4 `--screen=destruct` bot run.
- **Debris pool overflow under rapid blasts:** never more than 80 live chunks, and the oldest are recycled. Test: Task 2, `debris_caps_at_80`.

---

### Task 1: Destruction core (pieces, damage, breaking, reset)

**Files:**
- Create: `scripts/world/destruction.gd`, `tools/test_destruction.gd`
- Modify: `scripts/world/builder.gd`

**Interfaces:**
- Produces:
  - `class_name Destruction extends Node3D`
  - `const CLASSES := {"glass": {"hp": 20.0, "bullet": 1.0, "blast": 1.0}, "soft": {"hp": 220.0, "bullet": 1.0, "blast": 3.0}, "hard": {"hp": 700.0, "bullet": 0.0, "blast": 1.0}}`
  - `func _init(phys: Phys) -> void`
  - `func add_piece(mn: Vector3, mx: Vector3, mat: Material, cls: String, group: String, surf: String) -> int`: returns the id, which is its index in build order.
  - `func build() -> void`: creates the group meshes, called once after the arena build.
  - `func damage(id: int, amount: float, kind: String, point: Vector3, normal: Vector3) -> bool`: `kind` is `"bullet"` or `"blast"`. Returns true if this call broke the piece. Does nothing when `authority == false` except the local crack and chip effects.
  - `func break_piece(id: int, impulse_dir: Vector3) -> void`
  - `func is_broken(id: int) -> bool`
  - `func broken_ids() -> PackedInt32Array`, sorted.
  - `func apply_broken(ids: Array) -> void`: breaks any listed piece that is still intact, without making new claims.
  - `func reset() -> void`
  - `func pieces_in_sphere(center: Vector3, r: float) -> Array[int]`
  - `func piece_of(collider: Object) -> int`: -1 if the collider isn't a piece.
  - `var authority := true`
  - `var on_break := Callable()`: called as `(id: int)`.
  - `var on_damage := Callable()`: called as `(id: int, amount: float, kind: String)`.
  - Each piece dict: `{id, mn, mx, mat, cls, group, surf, hp, max_hp, broken, body: StaticBody3D}`.
  - Builder: `func breakable_box(mn: Array, mx: Array, mat: Material, cls: String, group: String, surf := "wood") -> int`. When `B.destruction` is null it falls back to `box()`, so maps keep working before they're wired.

- [ ] **Step 1: Write the failing test.** `tools/test_destruction.gd` extends `SceneTree`. It builds a `Phys` plus a `Destruction` with one piece of each class.
  - `glass_breaks_on_one_bullet`: `damage(glass, 25, "bullet")` returns true, then `is_broken` is true.
  - `hard_ignores_bullets`: `damage(hard, 9999, "bullet")` returns false and `hp == 700`.
  - `soft_blast_triples`: `damage(soft, 80, "blast")` returns true (80 × 3 ≥ 220).
  - `cracked_stage`: soft hit for 90 gives `hp/max_hp ≤ 0.6`, so cracked.
  - `collider_removed_on_break`: after breaking, a `phys.raycast` through the piece misses.
  - `reset_restores_everything`: after `reset()`, `broken_ids()` is empty, `hp == max_hp` and the raycast hits again.
  - `apply_broken_idempotent`: `apply_broken([id, id, 999])` breaks the piece once and doesn't error.
  - It prints `[test] N failures` and quits with the failure count.
- [ ] **Step 2: Run it and confirm it fails.** Run `Godot --headless --path . -s tools/test_destruction.gd`. Expected: a parse error or failures, because `Destruction` doesn't exist yet.
- [ ] **Step 3: Implement `Destruction` and `Builder.breakable_box`.**
  - Each piece gets its own `StaticBody3D` (`collision_layer = Phys.WORLD`, meta `mat` = surf, meta `piece` = id) with a `BoxShape3D`.
  - Group meshes: one `Batcher` per group (`Geo.tiled_box` with tile 1/3 for textured mats, plain box otherwise). Rebuild = free the group's MeshInstances, then re-add the unbroken pieces.
  - Cracked pieces go in with their colour darkened 25%, using the vertex-colour path for `vc_key` mats and a cached darker duplicate otherwise.
  - The breakables' fingerprint feeds `Phys.static_fingerprint()`: add `func fingerprint() -> int` (hash of the mn/mx/cls list) and include it in the nav cache key in Task 4.
- [ ] **Step 4: Run the test again.** Expected: `[test] 0 failures`. `sh tools/check.sh` reports 0 failed.
- [ ] **Step 5: Commit.** Message: "Destruction core: breakable pieces with HP classes, cracks, reset".

### Task 2: Break effects (debris chunks, dust, sound)

**Files:**
- Create: `scripts/fx/debris.gd`
- Modify: `scripts/world/destruction.gd`, `scripts/audio/audio_engine.gd`, `tools/test_destruction.gd`

**Interfaces:**
- Consumes: `Destruction.break_piece`.
- Produces:
  - `class_name Debris extends Node3D`
  - `const MAX := 80`
  - `func burst(mn: Vector3, mx: Vector3, color: Color, cls: String, dir: Vector3) -> void`
  - `func live_count() -> int`
  - `func clear() -> void`
  - `AudioEngine.break_piece(cls: String, pos: Vector3) -> void`. Recipes: `break_glass` (bright noise burst with tinkles), `break_soft` (wood crack, mid noise and click), `break_hard` (low thud and gravel noise). All three are added to `_prewarm`.
  - `Destruction.fx_hooks(debris: Debris, fx: Effects, audio: AudioEngine) -> void`

- [ ] **Step 1: Add the failing test `debris_caps_at_80`.** Fire 20 `burst` calls of 8 chunks each, then assert `live_count() == 80`.
- [ ] **Step 2: Run the test.** Expected: FAIL, because `Debris` doesn't exist yet.
- [ ] **Step 3: Implement `Debris`.**
  - 80 pooled `RigidBody3D` with `BoxShape3D`: layer `DEBRIS`, mask `WORLD`. Drawn by one `MultiMesh` that copies body transforms every frame.
  - Slot recycle is oldest-first.
  - Each chunk is a random size within the piece and gets an impulse along `dir` plus some up.
  - At 6 s the chunk shrinks out, gets disabled, and lowers `visible_instance_count` to the highest live slot.
  - `break_piece` calls `debris.burst`, `fx.soft` dust (8 puffs tinted to the material), and `audio.break_piece`.
  - On `damage`, a `fx.impact` chip appears at the hit point, and a crack decal appears from `fx.impacts` when the piece first reaches cracked.
- [ ] **Step 4: Run the test.** Expected: `[test] 0 failures`, and `check.sh` is clean.
- [ ] **Step 5: Commit.** Message: "Break effects: pooled debris chunks, dust, crunch sounds".

### Task 3: Hook into the game and combat

**Files:**
- Modify: `scripts/game.gd` (around line 104 for the arena build, line 139 for Combat, `start_match`, `_back_to_menu`), `scripts/combat/combat.gd` (`_hitscan`, the projectile world branch at about 456, `jab`, `explode`), `tools/test_destruction.gd`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - Arenas return `"destruction": Destruction` in their dict.
  - `game.destruction` is set.
  - `Combat.destruction: Destruction` is set after construction.
  - `Combat._hit_piece(world: Dictionary, dmg: float, d: Vector3) -> bool`

- [ ] **Step 1: Add failing tests.** These use a `Combat` with stub fx and audio, or call the pure helper `Combat.blast_pieces(center, radius, max_damage)`.
  - `blast_is_blocked_by_nearer_piece`: two soft pieces in a line from the blast. The near one takes damage; the far one takes none.
  - `blast_falloff`: a piece at the edge of the radius takes less than one at the centre.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement the hooks.**
  - In `game.gd`, create `Destruction` before `map.build`. Arenas get it via `Builder.destruction` (a new `var destruction: Destruction` on `Builder`, set by each arena's `build`, which takes it from `phys.get_meta("destruction")`, set by `game.gd`). Call `destruction.build()` after the arena build. Add it under `r.world`. Call `destruction.reset()` plus `debris.clear()` in `start_match` and `_back_to_menu`.
  - World hits whose collider is a piece get `damage(id, dmg, "bullet", point, normal)`. That covers hitscan, non-explosive projectiles and the jab: a jab with no actor target raycasts 2.6 m forward and hits pieces with the jab damage.
  - `explode` calls `blast_pieces(center, ex.radius, ex.maxDamage * p.power)`. Each piece in `pieces_in_sphere` takes damage based on the distance from the centre to its closest point. Falloff is `f = max(0, 1 - max(0, dist - 0.4) / radius)`, as for players. A raycast from the centre to the closest point must hit that piece or nothing.
- [ ] **Step 4: Verify.** The tests pass. `--autotest=ffa --seconds=20` on each map runs with no script errors (no pieces exist yet, so behaviour is unchanged).
- [ ] **Step 5: Commit.** Message: "Route shots, jabs and explosions into Destruction".

### Task 4: Bots path through new holes

**Files:**
- Modify: `scripts/nav/nav_graph.gd`, `scripts/entities/bot.gd` (repath on break), `scripts/game.gd` (cache key, break hook), `tools/test_destruction.gd`

**Interfaces:**
- Consumes: `Destruction.piece_of`, `is_broken`, `on_break`, `fingerprint`.
- Produces:
  - Nodes and links get a `blockers: PackedInt32Array` field.
  - `NavGraph.destruction: Destruction`
  - `NavGraph.build(bounds, cache_key, step, connectors)` is unchanged; it reads `destruction` when set.
  - `NavGraph.open_piece(id: int) -> void` bumps an internal revision.
  - `Bot.repath_soon() -> void`
  - `CACHE_VERSION := 6`

- [ ] **Step 1: Add failing tests** using a floor, a wall with a 2 m soft panel in its only gap, and nodes on both sides.
  - `path_blocked_until_broken`: `path(a, b)` is empty, then after `break_piece` it's non-empty and crosses the gap.
  - `cache_roundtrip_keeps_blockers`: save, load, then blockers are equal.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement the blockers.**
  - During `build`, set every piece body's `collision_layer` to 0, then restore it afterwards.
  - Afterwards, for each link, cast the same 0.35 / 1.45 m horizontal rays and the head ray against pieces only, with the layer temporarily set to a dedicated `Phys.PIECE := 8` and the query mask `PIECE`. Store the hit piece ids in `blockers`.
  - Nodes whose capsule overlaps a piece get it as a blocker. Drop nodes whose ground hit is a piece top.
  - `path` / `nearest` / `random` / `spawn_points` treat a node or link as closed if any blocker isn't broken.
  - The cache saves blockers as a 4th or 5th element. The cache key in `game.gd` includes `destruction.fingerprint()`.
  - `game.gd` sets `destruction.on_break` to `nav.open_piece`, then every bot's `repath_soon()`. A bot re-paths on its next think tick if its goal path changed.
- [ ] **Step 4: Verify.** Tests pass, and the headless autotest on each map runs with no errors and `bots below the floor: 0`.
- [ ] **Step 5: Commit.** Message: "Nav: breakable pieces block routes until they break".

### Task 5: Toy City breakables plus the `--screen=destruct` test

**Files:**
- Modify: `scripts/world/arena_toycity.gd` (`_wall`, the upper walls at lines 341–344, props), `scripts/game.gd` (new screen test)

**Interfaces:**
- Consumes: `Builder.breakable_box`, `Destruction`, `NavGraph` blockers.
- Produces: `--screen=destruct --map=<id>` prints `[destruct] N failures` (works headless).

- [ ] **Step 1: Write the screen test** (in `game.gd`, next to the other `--screen=` tests). It fails now because Toy City has no pieces.
  - It asserts the map has at least 1 hard and 1 soft piece.
  - It picks the hard wall panel nearest a building entrance and finds a nav path between nodes 1 m either side that is longer than 10 m, or empty.
  - It calls `combat.explode` at the panel with a Crayon Cannon config ×3 and asserts the panel broke.
  - It asserts the path is now under 4 m, then teleports a bot to one side with that goal and checks it crosses within 6 s.
  - It asserts that a hitscan Brickbreaker shot doesn't change a hard panel's HP, and that one Plasti-9 shot breaks a glass piece.
- [ ] **Step 2: Run it.** Command: `Godot --headless --path . -- --screen=destruct --map=toycity`. Expected: failures, because there are no pieces yet.
- [ ] **Step 3: Make Toy City breakable.**
  - `_wall` cuts each solid run into panels about 1.8 m wide (`hard`, group `"<building>-<side>-g"`). Door frames and lintels stay static.
  - The upper walls (lines 341–344) become a `_wall` per storey band without doors, with panels about 1.8 m wide. The 0.6 m at each corner stays static.
  - Upper-floor furniture, benches, kiosks, cones and crates become `soft`. Shop windows and car windows become `glass`. Car bodies stay static.
  - Leave alone anything within 1.5 m of a pad, zip end, `HILL_SITES` centre or sector centre.
- [ ] **Step 4: Verify.**
  - `--screen=destruct --map=toycity` prints `[destruct] 0 failures`.
  - `--screen=interiors --map=toycity` still passes, and `--screen=traversal --map=toycity` prints 0 failures.
  - A windowed screenshot (`--shots`) of a cracked wall and a fresh hole with debris looks right.
- [ ] **Step 5: Commit.** Message: "Toy City: breakable wall panels, glass and street cover".

### Task 6: Bedroom and backyard breakables

**Files:**
- Modify: `scripts/world/arena_bedroom.gd`, `scripts/world/arena_backyard.gd`

**Interfaces:**
- Consumes: Task 5's screen test. It must pick a piece that exists on each map.

- [ ] **Step 1: Run the test before changing anything.** Run `--screen=destruct --map=bedroom` and `--map=backyard`. Expected: failures, because there are no pieces yet.
- [ ] **Step 2: Make the bedroom breakable.** Cardboard boxes and cardboard walls are `soft`. The Brick District's block walls are `hard`, in panels about 1.6 m wide. Book stacks used as cover and crates are `soft`. The bed, desk, shelves, floor, room walls and anything carrying a pad or zip end stay static.
- [ ] **Step 3: Make the backyard breakable.** Fences, in about 1.6 m sections, crates and planters are `soft`. Shed and porch walls that act as cover are `hard` panels. The ground, play tower frame, pool and house stay static.
- [ ] **Step 4: Verify.**
  - `--screen=destruct` prints 0 failures on both maps.
  - `--screen=traversal` prints 0 failures on both.
  - The headless autotests (ffa, conquest) show no errors and `bots below the floor: 0`.
  - Screenshots look right.
- [ ] **Step 5: Commit.** Message: "Bedroom and backyard: breakable cover and walls".

### Task 7: Online sync (protocol 101)

**Files:**
- Modify: `scripts/net/host_session.gd` (`_on_guest_msg`, `start`, `update`), `scripts/net/guest_session.gd` (`_on_event`, `_on_host_msg` start/snap, claims), `scripts/net/snapshot.gd` (`pack_match`/`unpack_match_into`), `scripts/net/net_client.gd` and `server/worker.js` (version 101), `scripts/game.gd` (the `_online_test` prints)

**Interfaces:**
- Consumes: `Destruction.authority`, `on_damage`, `on_break`, `apply_broken`, `broken_ids`.
- Produces:
  - Guest to host: `{g:"gpiece", id:int, dmg:float, kind:String}`
  - Host to all: `{e:"break", ids:[int]}`, batched per host tick.
  - The match snapshot field `bk` holds the full sorted broken ids, sent every 2 s.
  - The `start` info carries `broken: []`.

- [ ] **Step 1: Add a failing check to the online test.** Each side prints `[online] broken <sorted ids>` at the end. The host's dev test also fires the Crayon Cannon at the nearest hard panel 3 times, 5 s into the match.
- [ ] **Step 2: Run it.** Start a local relay (`cd server && npm run dev`), then the host and the guest on Toy City as in CLAUDE.md. Expected: the guest's list is empty or differs from the host's.
- [ ] **Step 3: Implement the sync.**
  - Guests set `destruction.authority = false`, and `on_damage` sends `gpiece` (dmg capped at 400).
  - The host's `_on_guest_msg` `"gpiece"` handler ignores unknown or broken ids (that covers `stale_piece_claim_ignored`, which the test exercises by sending id 99999 and a just-broken id). Otherwise it calls `damage`.
  - The host's `on_break` queues ids. `update` sends the `break` event, and adds `bk` to the snapshot every 2 s.
  - The guest's `_on_event` `"break"` handler and the `bk` field call `apply_broken`.
  - Bump `PROTOCOL_VERSION` to 101 in both files.
- [ ] **Step 4: Verify.**
  - The host and guest print identical `[online] broken` lists.
  - `node server/test-relay.mjs` passes against the local relay (update its version constant to 101).
  - A guest at version 100 is refused.
- [ ] **Step 5: Commit.** Message: "Online: host-authoritative destruction sync (protocol 101)".

### Task 8: Perf check and ship 1.1.0

**Files:**
- Modify: `project.godot` (`config/version="1.1.0"`), `CLAUDE.md` (destruction notes, the `--screen=destruct` test, protocol 101), `README.md` (one line under Modes: walls and cover can be blown apart)

- [ ] **Step 1: Measure perf.** Run windowed `--autotest=ffa --seconds=30 --map=toycity` 3 times on the commit before Task 1 and 3 times now, interleaved. Compare the median `[perf] frame` and `[gpu] main gpu`. Expected: within about 10%. If not, merge more pieces per group and profile with `--tris`.
- [ ] **Step 2: Run the full regression.** That means `check.sh`, the autotests for all modes on all maps, `--screen=destruct`, `traversal` and `interiors`, and the online test. Expected: all clean.
- [ ] **Step 3: Ship it.**
  - Run `cd server && npm run deploy`, then `node test-relay.mjs <live url>` (it must report version 101).
  - Run `sh tools/build_installer.sh`.
  - Commit and push to `main`.
  - Create the GitHub release `v1.1.0` with asset `ToyboxMayhem-Setup.exe`. Its notes include "everyone needs 1.1.0 to play online together".
  - Check that `releases/latest/download/ToyboxMayhem-Setup.exe` returns the new file.
- [ ] **Step 4: Commit.** Message: "Release 1.1.0: destructible environments".

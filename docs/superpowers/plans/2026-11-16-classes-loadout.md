# Light / Medium Classes and the New Loadout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every toy is a Light or a Medium (health, speed, allowed guns/abilities/gadgets). The loadout becomes one gun, two abilities and one gadget slot (empty this batch). Bots play to their class. Online carries the class. Shipped as 1.2.0.

**Architecture:**
- `Cfg.CLASSES` is the single source of class rules.
- `Actor` gets `cls`, `max_health` and `speed_mult`, applied by `Actor.set_class()` at spawn. Every former use of `COMBAT.maxHealth` or the raw move speeds goes through them.
- `Loadout` stores the class plus per-class picks, and migrates 1.1 saves.
- Bots get a class from a balancer and nudged personality values.
- Online adds the guest's class to `gstate` and max health to snapshots (protocol 102).

**Tech Stack:** Godot 4.7 GDScript, existing Settings/Progress/Loadout/Bot/HostSession/GuestSession, Cloudflare relay.

**Spec:** `docs/superpowers/specs/2026-11-16-classes-loadout-design.md`

## Global Constraints
- **Light:** 100 HP, speed ×1.10.
  - Guns: foamFury, rapidRascal, bubbleBlaster, thunderspring, plungerBow, starlightZapper, plasti9.
  - Abilities (pick 2): dash, grapple, cloak.
  - Gadgets: glitchJug, stairs, fragGrenade, pyroGrenade.
- **Medium:** 150 HP, speed ×0.90.
  - Guns: brickbreaker, popcornPopper, crayonCannon, jackBlaster, walloper.
  - Abilities: shield, jab (always both).
  - Gadgets: turret, healthInfuser, breachDrill, explosiveMine, pyroMine.
  - Never: dash, grapple, fragGrenade, pyroGrenade.
- **Shield** stays 50 for both. Regen and pickups top up to `max_health`. Revive health is `0.6 × max_health`.
- **Default loadouts:**
  - Light: foamFury with dash + grapple.
  - Medium: jackBlaster with shield + jab.
- **Bot nudges:**
  - Light: aggression +0.25, caution −0.25. Chases a seen target below 50% health.
  - Medium: caution +0.25, aggression −0.2. Retreats below 40% health.
  - Sliders are clamped to 0..1.
- **One weapon slot (slot 0).** The weapon1/weapon2/swap binds stay but do nothing.
- **Training:** dummies are Mediums. "Try a blaster" offers all guns, and the class follows the gun.
- **Release:** `PROTOCOL_VERSION` 102 in `net_client.gd`, `server/worker.js` and `server/test-relay.mjs`. Version 1.2.0.
- **Gadget slot:** shown greyed with "coming soon". No gadget logic this batch.

## Review Focus
- **Old 1.1 save** with `primary=walloper`, `abilities=dash,grapple`: the player loads as a Medium with shield + jab, never with dash. (Test: Task 2 `migrates_old_save`.)
- **Changing class from the pause menu mid-life:** the current life keeps its health and speed, and the new class applies at the next respawn. (Test: Task 3 `class_change_waits_for_respawn` in `--screen=classes`.)
- **Health pickup or regen on a Medium** reaches 150, not 100. (Test: Task 1 `regen_and_pickup_cap_at_class_max`.)
- **Training "Try a blaster"** with a Medium gun turns the player into a Medium. (Test: Task 3 `try_blaster_sets_class`.)
- **A guest playing Medium** has 150 max health on the host, and the guest's HUD shows 150. (Test: Task 6 online check.)

---

### Task 1: Class table and per-actor health and speed

**Files:**
- Modify: `scripts/weapons/cfg.gd` (add `CLASSES`, `CLASS_ORDER`, `class_of_gun()`)
- Modify: `scripts/entities/actor.gd` (vars at about line 61; reset at 379; regen at 693; speeds at 487/563-594)
- Modify: `scripts/match/pickups.gd:152,171`
- Modify: `scripts/ui/hud.gd:595-596`
- Modify: `scripts/game.gd:271,1119,1890`
- Create: `tools/test_classes.gd`, `tools/test_classes.tscn`, `tools/test_classes.sh` (same runner style as `tools/test_destruction.sh`)

**Interfaces:**
- Produces:
  - `Cfg.CLASSES: Dictionary` keyed `"light"`/`"medium"`, each `{"name", "health": float, "speed": float, "guns": Array, "abilities": Array, "gadgets": Array, "pick_abilities": bool}`.
  - `Cfg.CLASS_ORDER := ["light", "medium"]`.
  - `static func Cfg.class_of_gun(wid: String) -> String`.
  - `Actor.cls: String = "light"`, `Actor.max_health: float`, `Actor.speed_mult: float`.
  - `func Actor.set_class(c: String) -> void`, which sets the three fields and fills health.
  - `func Actor.revive_health() -> float`.

- [ ] **Step 1: Write the failing tests** in `tools/test_classes.gd`:
  - `class_tables_match_spec`: the exact gun, ability and gadget lists from Global Constraints; `health` 100/150; `speed` 1.10/0.90.
  - `medium_never_moves_or_throws`: `not medium.abilities.has("dash")`, no `"grapple"`, no `"fragGrenade"`, no `"pyroGrenade"`.
  - `every_gun_in_exactly_one_class`: each id in `Cfg.WEAPON_ORDER` has one class; `class_of_gun("walloper") == "medium"`.
  - `set_class_sets_health_and_speed`: `Actor.set_class("medium")` gives `max_health == 150`, `health == 150` and `speed_mult == 0.9`.
  - `regen_and_pickup_cap_at_class_max`: a Medium at 120 HP after regen time ends at 150; the health pickup path caps at 150.
  - `revive_is_60_percent`: 60 for a Light, 90 for a Medium.
- [ ] **Step 2: Run** `sh tools/test_classes.sh`. Expected: failures or parse errors.
- [ ] **Step 3: Implement the class table and actor fields.**
  - Build the table from the constraints.
  - Replace every `Cfg.COMBAT.maxHealth` with `a.max_health` (actor, pickups, hud, the snipertest in game.gd).
  - Replace revives with `a.revive_health()`.
  - Multiply `M.walkSpeed`, `M.crouchSpeed` and the sprint target by `speed_mult` in `actor.gd`, at the target-speed block (about lines 563-594) and the slide threshold (487).
- [ ] **Step 4: Verify.** `sh tools/test_classes.sh` gives `[test] 0 failures`; `sh tools/check.sh` is clean; `--autotest=ffa --seconds=15 --map=toycity` has no script errors.
- [ ] **Step 5: Commit.** Message: "Classes: Light/Medium table, per-toy max health and speed".

### Task 2: Per-class loadout and migrating 1.1 saves

**Files:**
- Modify: `scripts/weapons/loadout.gd`, `scripts/core/settings.gd` (new keys `"class"`, `"loadouts"`; old keys kept for migration)
- Test: `tools/test_classes.gd`

**Interfaces:**
- Consumes: `Cfg.CLASSES`, `Cfg.class_of_gun`.
- Produces:
  - `static func Loadout.cls() -> String`
  - `static func Loadout.set_cls(c: String) -> void`
  - `static func Loadout.gun() -> String`: owned and in the class, else the class default.
  - `static func Loadout.set_gun(id: String) -> void`: ignores guns that aren't owned or are outside the class.
  - `Loadout.abilities() -> Array`: always 2 and always allowed for the class. A Medium always gets `["shield", "jab"]`.
  - `Loadout.set_ability(slot, id)`: Light only, ids from the Light list.
  - `static func Loadout.gadget() -> String`: returns `""` this batch.
  - The `"loadouts"` setting is JSON `{"light": {"gun", "abilities"}, "medium": {"gun"}}`.
  - `Loadout.primary()` / `secondary()` are removed. Callers move to `gun()` (Tasks 3 and 5).

- [ ] **Step 1: Write the failing tests.** Each one sets the Settings values directly, then reads through `Loadout`.
  - `defaults_per_class`: Light gives `foamFury` + `["dash", "grapple"]`; Medium gives `jackBlaster` + `["shield", "jab"]`.
  - `migrates_old_save`: with no `"loadouts"` and `primary=walloper, secondary=plasti9, abilities=dash,grapple`, `cls() == "medium"`, `gun() == "walloper"` and `abilities() == ["shield", "jab"]`. With `primary=rapidRascal, abilities=cloak,shield`: `cls() == "light"`, `gun() == "rapidRascal"`, and the abilities are `cloak` plus `dash`.
  - `wrong_class_gun_falls_back`: `set_cls("medium")`, then `set_gun("foamFury")`, still gives `gun() == "jackBlaster"`.
  - `class_switch_keeps_each_loadout`: Light set to rapidRascal and Medium to walloper, then switching back and forth returns each.
  - `light_ability_pick_swaps`: the existing swap semantics, with only Light ids accepted.
- [ ] **Step 2: Run** `sh tools/test_classes.sh`. Expected: failures.
- [ ] **Step 3: Implement it in `loadout.gd`.**
  - Migration runs once, inside `cls()` / `_data()`, when `"loadouts"` is missing:
    - class = `class_of_gun(primary)`;
    - that class's gun = `primary` (if owned);
    - Light abilities = the old allowed ones, padded with dash then grapple.
  - Then save `"loadouts"` and `"class"`.
- [ ] **Step 4: Verify.** Tests pass. `check.sh` will show the callers of `primary()` / `secondary()` failing until Task 3; Tasks 2 and 3 commit together if needed.
- [ ] **Step 5: Commit** with Task 3.

### Task 3: Spawning with a class and one gun (player, training, bots)

**Files:**
- Modify: `scripts/game.gd`:
  - `_respawn` player and bot branches, about lines 1030-1050;
  - `_make_bot` at 918;
  - `training_weapons` at 9/762/1037/1181;
  - `remote_ability` at 1880;
  - `start_match` roster setup.
- Modify: `scripts/entities/player.gd:215-220` (weapon keys do nothing).
- Modify: `scripts/entities/bot.gd` (`pick_bot_loadout`, `pick_bot_abilities` take a class).
- Modify: `scripts/ui/menus.gd:1130` (`try_blaster` single gun).
- Create: `scripts/dev/classes_test.gd` (`--screen=classes`).

**Interfaces:**
- Consumes: Task 1 `Actor.set_class`; Task 2 `Loadout.cls/gun/abilities`.
- Produces:
  - `Game.training_gun: String = ""` replaces `training_weapons`.
  - `static func Bot.pick_bot_loadout(p: Dictionary, cls: String) -> String`: a favourite that fits the class, else a random gun from the class.
  - `static func Bot.pick_bot_abilities(p: Dictionary, cls: String) -> Array`: Medium is fixed; Light uses the existing weights over dash, grapple, cloak.
  - `Bot.cls: String`.
  - `static func Game.assign_bot_classes(teams: Array) -> Array`: given each bot's team (−1 for FFA), returns a class per bot. Team modes alternate within each team; FFA alternates. Seeded by `randi()`.
  - `--screen=classes` prints `[classes] N failures`.

- [ ] **Step 1: Write the failing screen test** `DestructTest`-style in `scripts/dev/classes_test.gd`, wired in `game.gd` next to `"destruct"`. It starts a TDM match.
  - `max_health_by_class`: the player as Light has 100; after `Loadout.set_cls("medium")` and a forced respawn, 150.
  - `speed_ratio`: holding sprint for 1.5 s on flat ground, the measured horizontal speed is Light/Medium = 1.10/0.90 ±4%.
  - `medium_cannot_dash_or_hook`: as a Medium, `a.has("dash")` and `a.has("grapple")` are false, and `Abilities.try_grapple` returns null.
  - `one_gun`: `a.weapons[1] == null`; pressing `weapon2` and `swap` leaves `a.slot == 0`.
  - `bots_have_both_classes_per_team`: in TDM, each team has at least one Light and one Medium bot, and every bot's gun is in its class.
  - `class_change_waits_for_respawn`: alive as a Light, `set_cls("medium")` leaves `max_health` at 100 until the next respawn, then 150.
  - `try_blaster_sets_class`: in a training match, `try_blaster` with `walloper` makes the player a Medium on respawn.
- [ ] **Step 2: Run** `Godot --headless --path . -- --screen=classes --map=toycity`. Expected: failures or errors.
- [ ] **Step 3: Implement spawning.**
  - **Player spawn:** class from `Loadout.cls()`, or the class of `training_gun` when that is set. Call `a.set_class`, give one weapon in slot 0, and set abilities from `Loadout`.
  - **Bots:** `start_match` builds the bot team list, then calls `assign_bot_classes`, storing `bot.cls`. The personality is copied and nudged per Global Constraints and clamped. Training dummies are `"medium"`. Spawn calls `a.set_class(bot.cls)` and gives one gun.
  - **`remote_ability`:** never grants shield to a Light; it uses the class's abilities.
- [ ] **Step 4: Verify.** `--screen=classes` gives 0 failures; `tools/test_classes.sh` passes; `check.sh` is clean; the headless autotest on all 5 modes on toycity has no errors.
- [ ] **Step 5: Commit** (with Task 2). Message: "Loadout per class, one gun, class-aware spawning for players, training and bots".

### Task 4: Bots play to their class

**Files:**
- Modify: `scripts/entities/bot.gd` (`_think` around 299/335-360/431, `_find_cover` 666)
- Modify: `scripts/dev/classes_test.gd`

**Interfaces:**
- Consumes: `Bot.cls`, `Actor.max_health`.

- [ ] **Step 1: Add the failing test `class_behaviour`.** Run an FFA with 14 bots for 25 s.
  - For each bot, sample every 0.5 s the distance to its current target while it has one.
  - The Light median must be at least 15% below the Medium median.
  - Medium bots must have spent more time in `"retreat"` per minute than Light bots.
- [ ] **Step 2: Run the test.** Expected: a FAIL, or margins below threshold.
- [ ] **Step 3: Implement class behaviour.**
  - **Light:** a target below 50% of its `max_health`, seen within 12 s instead of 5, keeps being pursued to its last known position, sprinting.
  - **Medium:** retreats when `health / max_health < 0.4` (instead of the personality's own threshold, if lower). When choosing a spot during `engage`, it prefers `_find_cover` positions 10-22 m from the target.
  - Health checks use `max_health`, not 100.
- [ ] **Step 4: Verify.** `--screen=classes` gives 0 failures twice in a row; the headless autotests on all three maps have no errors and `bots below the floor: 0`.
- [ ] **Step 5: Commit.** Message: "Bots: Lights hunt, Mediums hold cover".

### Task 5: Loadout screen and pause menu

**Files:**
- Modify: `scripts/ui/menus.gd` (the loadout screen around 600-650 and 784-860; `_loadout_bb` at 329; pause at 1112; `try_blaster` at 1130; the 994 abilities summary)

**Interfaces:**
- Consumes: Task 2 `Loadout` API.

- [ ] **Step 1: Add the failing screenshot checks.** Extend the `--screen=loadout` path so that `--screen=loadout:medium` sets the class first, and it prints `[loadout] class=<c> guns=<n> abilities=<list>`. Expected for Light: `guns=7` and the abilities list has 3 options. For Medium: `guns=5` and the abilities are shown fixed.
- [ ] **Step 2: Run** `Godot --path . -- --screen=loadout:medium --shots=<dir>`. Expected: the old screen, wrong counts.
- [ ] **Step 3: Build the screen.**
  - **Class row:** two big buttons, "LIGHT — 100 HP, faster" and "MEDIUM — 150 HP, tougher", calling `Loadout.set_cls`.
  - **One "BLASTER" grid** limited to the class (locked guns still show their price).
  - **Abilities:** Light picks 2 of 3, as today. Medium shows Mesh Shield + Spring Punch as fixed cards.
  - **"GADGET" box:** the class's gadget names, greyed, "Coming soon".
  - The pause-menu summary (`_loadout_bb`) shows class + gun + abilities.
  - `try_blaster` lists all 12 guns and sets `training_gun`.
- [ ] **Step 4: Verify.** Both screenshots look right at 1080p; the printed counts match; `check.sh` is clean.
- [ ] **Step 5: Commit.** Message: "Loadout screen: class picker, one blaster, gadget slot".

### Task 6: Online class sync (protocol 102)

**Files:**
- Modify: `scripts/net/guest_session.gd` (`_own_state` adds `"cls"`)
- Modify: `scripts/net/host_session.gd` (`gstate`: when `s.cls` differs from the remote's, store it and apply on the next spawn)
- Modify: `scripts/game.gd` (remote spawn applies `set_class`; `_online_test` accepts `--class=<c>` and prints `[online] <role>: <name> class <c> max <n>` for every human)
- Modify: `scripts/net/snapshot.gd` (new `MAX_HEALTH := 38`, `LENGTH := 39`; pack/unpack)
- Modify: `net_client.gd`, `server/worker.js`, `server/test-relay.mjs` (protocol 102)

**Interfaces:**
- Consumes: `Actor.set_class`, `Actor.max_health`.

- [ ] **Step 1: Add the failing online check.** The guest runs with `--class=medium`. Both sides print every human's class and max health.
- [ ] **Step 2: Run the online test** with a local relay. Expected: the host shows the guest as a Light with 100 max.
- [ ] **Step 3: Implement the sync.** As per Interfaces; the guest HUD reads its own `max_health` from the snapshot.
- [ ] **Step 4: Verify.**
  - Host and guest both print `Guesty class medium max 150`.
  - `node server/test-relay.mjs` passes at 102 locally.
  - The previous online destruction lists still match.
- [ ] **Step 5: Commit.** Message: "Online: classes travel with the guest (protocol 102)".

### Task 7: Ship 1.2.0

**Files:** `project.godot` (1.2.0), `export_presets.cfg` (1.2.0.0), `CLAUDE.md` (class notes, tests, protocol 102), `README.md` (a Classes section: Light/Medium and what each can equip)

- [ ] **Step 1: Run the full regression.**
  - `check.sh`, `test_classes.sh`, `test_destruction.sh`, `destruct_all.sh`;
  - autotests for all modes on all maps;
  - `--screen=classes`, traversal on all maps;
  - the online test.
  - Expected: all clean (the known rare exit crash aside).
- [ ] **Step 2: Final whole-branch review,** then fixes.
- [ ] **Step 3: Ship.**
  - `cd server && npm run deploy` (it must report protocol 102), then `sh tools/build_installer.sh`.
  - Smoke-test the exported exe (`--screen=classes`).
  - Fast-forward `main` and push.
  - Create GitHub release `v1.2.0` with `ToyboxMayhem-Setup.exe`; its notes say everyone needs 1.2.0 to play online.
  - Verify the latest-download link.
- [ ] **Step 4: Commit** the version and docs before the build. Message: "Release 1.2.0: Light and Medium classes".

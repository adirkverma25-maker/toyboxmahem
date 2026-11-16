# Classes (Light / Medium) and the new loadout — batch 1 of guns and gadgets

Status: awaiting approval, 2026-11-16.

## Why
The owner is moving the game toward class-based, destruction-heavy fights. Every player picks a class, and the class decides health, speed and what they may equip. The loadout becomes **one gun, two abilities and one gadget**.

The work ships in batches:
1. **This batch: classes and the new loadout.** The gadget slot is shown but empty.
2. **Later batches:** the nine gadgets, a few at a time.

## Decided by the owner
- **Two classes.**
  - **Medium:** 150 health, slower, no movement abilities (no Wind-Up Dash or Spring Hook), cautious bots.
  - **Light:** 100 health, faster, aggressive bots that chase players down.
- **Guns.**
  - **Light:** Foam Fury, Rapid Rascal, Bubble Blaster, Thunderspring, Plunger Longbow, Starlight Zapper, Plasti-9.
  - **Medium:** Brickbreaker, Popcorn Popper, Crayon Cannon, Jack-in-the-Blaster, Walloper.
- **Abilities.**
  - **Light:** pick 2 of Wind-Up Dash, Spring Hook, Cloak.
  - **Medium:** Mesh Shield and Spring Punch.
- **Gadgets (for later batches).**
  - **Light:** glitch jug, stairs, frag grenade, pyro grenade.
  - **Medium:** turret, health infuser, breach drill, explosive mine, pyro mine.
  - **Mediums never get frag or pyro grenades.**
  - **Frag grenades damage walls:** two frags break a hard wall (700 HP), so each frag deals about 350+ to pieces.
- **Ship in batches.**

## My calls (owner may correct)
- **Speed.**
  - **Light:** 1.10 × the current movement speeds (walk, sprint and crouch).
  - **Medium:** 0.90 ×.
  - Jump height is unchanged.
- **Medium abilities:** Mediums always get both of their abilities, so their loadout has no ability pick.
- **Shield and regen.** Both classes keep the same 50-point shield and the same regen rules. Regen tops up to the class's max health.
  - **Revive health** scales with class: 60% of max (60 for a Light, 90 for a Medium).
- **Choosing a class.** A Light / Medium toggle at the top of the Loadout screen.
  - The gun, ability and gadget lists show only that class's items.
  - The loadout is saved separately for each class, and switching class restores that class's last loadout.
  - **Defaults:**
    - **Light:** Foam Fury with Dash + Spring Hook.
    - **Medium:** Jack-in-the-Blaster with Shield + Punch.
    - Both use only free starter guns.
- **Unlocks and coins** work as now. A class's gun list shows locked guns with their price, as today.
- **One gun.**
  - The second weapon slot is gone. The "Primary/Secondary" keys (1/2) and swap do nothing in a match; their binds stay so nothing breaks.
  - Players switch class or gun between lives from the pause menu's loadout, as today.
- **Gadget slot.** The Loadout screen shows a gadget box with the class's gadget list greyed out and labelled "coming soon". The HUD shows no gadget yet.
- **Bot classes.**
  - Bots get a class at random. In team modes, each team gets a balanced mix (as even as possible). In FFA it's 50/50.
  - A bot's gun comes from its class list, preferring its personality favourites that fit the class.
  - A bot's abilities come from its class list.
- **Bot behaviour by class.** Each personality is nudged toward its class. Behaviour sliders are clamped to 0..1.
  - **Light:** aggression +0.25, caution −0.25. It chases a target it has seen that is below 50% health, even past its usual give-up distance.
  - **Medium:** caution +0.25, aggression −0.2. It prefers cover spots and fighting from mid range, and it retreats to cover when below 40% health.
- **Training Range.**
  - "Try a blaster" offers every gun regardless of class, with the class following the gun picked.
  - Dummies are Mediums: 150 health, so a full-health target is tougher to pop.
- **Online.**
  - The guest's class travels with its state, as a `cls` field in the 30 Hz `gstate` (one byte).
  - The host applies max health and speed at spawn, and snapshots carry `maxHealth` for the HUD.
  - The protocol goes to 102 (relay redeployed), since 1.1 hosts wouldn't understand classes.
- **Release:** 1.2.0.

## Non-goals (this batch)
- No gadgets yet: no grenades, mines, turret, infuser, drill, stairs or glitch jug.
- No new guns, models, reloads or sounds. That's the realistic-guns project.
- No new abilities, and no change to how existing abilities work (except who may use them).
- No Heavy class.

## Anti-goals
- **A Medium who can still Dash or Spring Hook** by any route: an old saved loadout, bots, online state or training.
- **A loadout with a gun from the wrong class**, including old 1.1 saves (they are migrated at load).
- **Bot class behaviour that makes bots stand still or walk into walls.**
- **Online desync of health:** a guest's Medium must have 150 HP on the host's side too.

## Approaches
There is one sensible way: extend what's there.
- Actors already carry `abilities`.
- `Loadout` already saves two abilities and weapon picks.
- Bots already have personality sliders.
- Health and speed are single constants.

A class therefore becomes a table in `Cfg.CLASSES` (health, speed multiplier, guns, abilities, gadgets). Each actor gets `cls`, `max_health` and `speed_mult`, set at spawn. `Loadout` gains `class()` and per-class picks.

Alternatives were rejected:
- **Separate toy characters per class:** this mixes up character looks with class rules.
- **Hard-coding class checks across the code:** these scatter, and the anti-goals become hard to guarantee.

## Testing
- **Unit tests:**
  - Class tables are complete and disjoint where required (no grenade in Medium gadgets, no Dash or Hook in Medium abilities).
  - Old 1.1 settings migrate to a valid loadout.
  - `Loadout` never returns a gun or ability outside the class.
- **Headless autotests on every mode and map:** no errors, and the scoreboard shows both classes among bots.
- **A class check screen (`--screen=classes`).** It spawns a Light and a Medium and checks:
  - max health 100 / 150;
  - measured sprint speed ratio about 1.10 / 0.90 of the old speed;
  - a Medium cannot use Dash or Spring Hook;
  - Light bots close distance on a weak target, and Medium bots keep further back on average over a short fight.
- **Online test:** a guest picks Medium. The host's copy shows 150 max health, and damage taken matches on both sides.
- **Screenshot** of the new Loadout screen in each class.

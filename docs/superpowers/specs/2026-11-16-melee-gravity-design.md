# Melee weapons, no Spring Punch, Medium Cloak, stronger gravity (1.3.0)

Approved by the owner on 2026-11-16 ("Yes").

- **Spring Punch is removed** from the game everywhere: abilities, menus, bots, HUD, online.
- **Mediums always carry Mesh Shield + Cloak.** They still can't take Dash or Spring Hook. Lights pick 2 of Dash, Spring Hook and Cloak.
- **Melee is a quick swing on its own key** (V / right-stick click, rebindable as "Melee"). Your blaster stays in your hand.
  - **Toy Sword (Light):** 55 damage, 3.2 m reach, 90° arc, 0.55 s swing.
  - **Toy Spear (Medium):** 70 damage, 4.2 m reach, 50° arc, 0.8 s swing.
  - **Generous hit zone:** a toy is hit if its feet, chest or head is inside the reach (plus its body radius) and the arc (widened by its body width up close), within 2.2 m up or down, with clear sight.
  - **Multiple hits:** every enemy in the zone is hit.
  - **Shields and props:** shields soak the blow, and walls and props in front take a chip.
- **Gravity goes from 15 to 22 m/s².** Jump speed rises from 6.5 to 7.87 m/s, so jump height stays 1.4 m (ledges, steps and bot routes still work). Jump pads aim with the new gravity.
- **Online:** snapshots carry each toy's class (so guests see the right melee weapon). Protocol 103.
- **Not tested before release,** at the owner's request (same as 1.2): compile check only.

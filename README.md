# DungeonCrawler

A procedurally generated dungeon crawler built in Godot 4. Roguelike runs across
multiple biomes, with item drops, enchanting, status effects, bosses, and a
local leaderboard.

## Gameplay loop

Title screen → pick a biome → run through procedurally generated floors,
portal-to-portal → boss fight every 5 floors → die or escape → end-of-run
summary saved to leaderboard and run history.

Difficulty climbs each portal (faster in some biomes than others). Player level
and unlocks persist across runs; everything else resets.

## Biomes

- **Dungeon** — baseline.
- **Catacombs** — undead-leaning, faster climb rate.
- **Ice Cavern** — slippery floors, frozen blocks, freeze-leaning enemies.
- **Lava Rift** — fire patches, lava tiles, burn-leaning enemies.

## Player systems

- **HP** — base 10, +5 per VIT. Restored at shrines or via potions.
- **Mana** — base 100, regens with WIS. Powers wand shots and abilities.
- **Stamina** — base 100, regens with END. Spent on dashing.
- **XP / Level** — quadratic curve; each level grants +1 to all stats.
- **Stats** — STR, DEX, VIT, END, WIS, DEF, plus speed and crit modifiers from gear.
- **Status effects** — slow, poison (DoT), disorient (scrambled controls), burn,
  freeze (chilled, takes +25% damage), shock (chains).

## Enemies

17+ archetypes including Archer, Sniper, Charger, Chaser, Shooter, Tank, Spider,
Wizard, SpiralMage, Enchanter, Summoner, Grenadier, MineLayer, MissileTurret,
BeamSweep, plus three boss variants (Brute, Architect, Wraith).

## Hazards & interactables

Spike traps, spin traps, mines, fire patches, poison clouds, lava tiles, ice
tiles, frozen blocks, breakable walls, pressure plates, secret doors,
teleporters, portals.

## Items & inventory

- 25-slot bag, 7 equipment slots (wand, hat, robes, feet, ring, necklace, offhand).
- **Wands** — 9 procedural shoot types: pierce, ricochet, shotgun, freeze, fire,
  shock, beam, homing, nova. Legendary wands stack effects.
- **Flaws** — wands can roll backwards firing, clunky cadence, sloppy spread, or
  slow projectiles.
- **Armor / accessories** — stat bonuses across hat, robes, boots, ring, necklace.
- **Tomes** — increase projectile count.
- **Potions** — stackable consumables (e.g. health potion restores 30% max HP).
- **Valuables** — sell-only loot.

### Enchanting

At an Enchant Table, spend gold to:

- Reroll affixes
- Forge a new affix
- Fuse two items
- Refine a flaw into a perk

Prices scale down as run difficulty climbs.

## Economy

- **Gold** drops from enemies, chests, and loot bags.
- **Sell Chest** converts items to gold.
- **Shrines** offer one of: heal, random +5 stat, mana surge, or 100g checkpoint.
- **Boss kills** guarantee a signature legendary wand drop.

## Floor modifiers

Random per floor: CURSED (enemies +50% speed), BLOODLUST (enemies 2× HP),
HAUNTED (all elite), ARCANE (2× mana regen), HASTE (player +30% speed).

## Meta-progression

- **Leaderboard** — local top-10 across portals used, gold earned, damage dealt;
  per-biome bests.
- **Run history** — last 5 runs auto-saved.
- **Persistent player level** — XP carries between runs; higher levels unlock
  better procedural drops.

## Controls

| Key / Button     | Action                                |
|------------------|---------------------------------------|
| W A S D          | Move                                  |
| Left mouse       | Shoot (hold to rapid-fire)            |
| Right mouse      | Shield (drains mana while held)       |
| Shift            | Dash (35 stamina, i-frames)           |
| Space            | Levitate (50 mana, float over things) |
| Q                | Nova spell (100 mana)                 |
| E                | Interact (chests, shrines, doors)     |
| I                | Toggle inventory                      |
| Esc              | Pause menu                            |

## Project structure

```
dungeon_crawler/
├── project.godot
├── scenes/         # Player, World, TitleScreen, all enemies, pickups, traps, UI
├── scripts/        # Gameplay logic + autoloads
│   ├── GameState.gd          # autoload — stats, difficulty, biome
│   ├── InventoryManager.gd   # autoload — bag + equipment
│   ├── Leaderboard.gd        # autoload — local high scores
│   ├── RunHistory.gd         # autoload — recent run log
│   ├── SoundManager.gd       # autoload — audio
│   ├── Player.gd             # movement, shooting, abilities, HUD
│   ├── World.gd              # procedural generation (BSP rooms/cave/halls)
│   ├── ItemDB.gd             # item generation, affixes, legendaries
│   └── Enemy*.gd             # per-archetype AI
└── shaders/
    ├── crt_overlay.gdshader  # optional CRT post-effect
    └── floor_dots.gdshader   # ASCII grid floor
```

## Setup

1. Clone the repo.
2. Open **Godot 4.6** (4.3+ should work).
3. In the Project Manager, click **Import** and select `project.godot`.
4. Hit **F5** to run. The main scene is `TitleScreen.tscn`.

The project uses the Forward+ renderer; switch to Mobile or Compatibility in
**Project Settings → Rendering → Renderer** if your hardware needs it.

## Roadmap

- [x] Player movement and shooting
- [x] Multiple enemy archetypes and bosses
- [x] Procedural floor generation
- [x] HP / mana / stamina systems
- [x] Inventory and equipment
- [x] Item drops, enchanting, sell chest
- [x] Shrines, secret doors, traps, hazards
- [x] Status effects (burn, freeze, shock, poison, slow, disorient)
- [x] Biomes with distinct themes
- [x] Local leaderboard and run history
- [ ] Sound and music pass
- [ ] Additional biomes
- [ ] More boss variants
- [ ] Controller support

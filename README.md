# DungeonCrawler

A procedurally generated ASCII roguelike built in **Godot 4.6**. Runs play out across
multiple biomes with item drops, enchanting, status effects, bosses, and a local + online
leaderboard — and the whole game can be played in **top-down, third-person, or first-person**
(the world renders as ASCII either way).

## Gameplay loop

Title screen → village hub → descend into procedurally generated floors, portal-to-portal →
boss fight every 5 floors → die or escape → end-of-run summary saved to the leaderboard and run
history. There's also a standalone **Survival Arena** mode.

Difficulty climbs each portal (faster in some biomes than others). Player level and unlocks
persist across runs; everything else resets.

## View modes

The signature feature: cycle the camera with **F1** between three renderings of the same world —

- **Top-down** — 2D ASCII overhead view with a glyph minimap.
- **Third-person** — the wizard billboard pulled back into a 3D ASCII corridor.
- **First-person** — a dungeon-crawler eye view. Rendered by `FirstPersonRig.gd` using two
  stacked SubViewports: the environment passes through an ASCII post-shader
  (`shaders/ascii_post.gdshader`) whose glyph density tracks scene brightness, while entities
  render as crisp billboarded ASCII glyphs over the top. Walls are real 3D geometry, so the
  DOOM-style systems below (doors, lighting) only exist here.

## Biomes

- **Dungeon** — baseline.
- **Catacombs** — undead-leaning, faster climb rate, 10% of deaths reanimate as zombies.
- **Ice Cavern** — slippery floors, frozen blocks, freeze-leaning enemies (start pre-chilled).
- **Lava Rift** — fire patches, periodic eruptions, lava tiles, burn-leaning enemies.

## Player systems

- **HP** — base 10, +5 per VIT. Restored at shrines or via potions.
- **Mana** — base 100, regens with WIS. Powers wand shots and abilities.
- **Stamina** — base 100, regens with END. Spent on dashing.
- **XP / Level** — quadratic curve; each level grants +1 to all stats.
- **Stats** — STR, DEX, VIT, END, WIS, DEF, plus speed and crit modifiers from gear.
- **Abilities** — Dash (i-frames; passes through enemies), Levitate (float over floor hazards),
  Nova (radial burst), and a held Shield.
- **Status effects** — slow, poison (DoT), disorient (scrambled controls), burn, freeze
  (chilled, takes +25% damage), shock (chains to nearby foes).

## Enemies

~25 archetypes, each its own AI script extending `EnemyBase.gd`:

Archer, Banshee, BeamSweep, Berserker, Bomber, BoneDrake, Chaser, Charger, Enchanter,
FrostSentinel, Grenadier, MagmaSlug, MineLayer, MissileTurret, Phantom, Reflector, Shooter,
Sniper, Spider, SpiralMage, Splitter, Stalker, Summoner, Tank, Wizard.

**Elite** variants (chance scales with difficulty) roll a modifier: shielded, splitting, enraged,
haste, or volatile. **Bosses** appear every 5th floor — **Brute**, **Architect**, **Wraith**,
**Lich**, **Magma Tyrant**, and **The Devourer** — each with HP-threshold "gate" phases.

## Geometry & encounters (first-person systems)

DOOM-inspired moving geometry and triggers (see `DOOM_DESIGN.md`):

- **Animated doors** — wall sections that sink into the floor as you approach and rise behind
  you; also remotely controllable (seal/open).
- **Beam-trap corridors** — wall-to-wall energy beams that telegraph then fire; dash through
  the gap. High and floor-level (levitate-able) variants.
- **Wall switches** — shoot a switch to open a door sealing a dead-end loot alcove.
- **Ambush rooms** — stepping in seals the doorways and springs a monster-closet wave; clearing
  it (or a safety timeout) reopens the seal and drops a reward.
- **Sector lighting** — a flickering player torch plus per-room light levels; some rooms are
  **dark** (torch-only pools) or **flickering** (broken-light strobe). Because the ASCII shader
  is brightness-driven, darkness literally thins the world into sparse glyphs.

Floors also seed **themed rooms** (Spider Den, Sniper Alley, Charger Pit, Minefield,
Beam Crossfire, Summoner Nest, …) that replace the normal enemy mix with a flavored encounter.

## Hazards & interactables

Spike traps, spin traps, mines, fire patches, poison clouds, lava tiles, ice tiles, frozen
blocks, breakable walls, secret doors, pressure plates, beam traps, animated doors, wall
switches, teleporters, and floor-to-floor portals.

## Items & inventory

- A **25-cell inventory grid** whose first 5 cells are **wand slots** (mouse-wheel cycles the
  active wand), plus equipment slots: **hat, robes, feet, ring, necklace**.
- **Wands** — 9 procedural shoot types: pierce, ricochet, shotgun, freeze, fire, shock, beam,
  homing, nova. Legendary wands stack effects.
- **Flaws** — wands can roll backwards firing, clunky cadence, sloppy spread, or slow
  projectiles (refine them into perks at the Enchant Table).
- **Armor / accessories** — stat bonuses across hat, robes, boots, ring, necklace.
- **Tomes** — increase projectile count.
- **Potions** — stackable consumables (e.g. health potion restores 30% max HP).
- **Valuables** — sell-only loot.

### Enchanting

At an Enchant Table, spend gold to **reroll affixes**, **forge a new affix**, **fuse two items**,
or **refine a flaw into a perk**. Prices scale down as run difficulty climbs.

## Village & meta hub

Between runs the village offers: a **Bank** and a **Persistent Stash** (carry gear/gold across
runs), a **Quest Board** + quest log, an **Inn**, a **Shop**, a **Sell Chest**, an
**Enchant Table**, and a **Reroller**. Runs are entered via the **Descend Portal** and exited
(with loot banked) via the **Exit Portal**.

## Economy

- **Gold** drops from enemies, chests, and loot bags.
- **Sell Chest** / Bank convert items to gold and store them.
- **Shrines** offer one of: heal, random +5 stat, mana surge, or a 100g checkpoint.
- **Boss kills** guarantee a signature legendary wand drop.

> Late-game note: live enemies and loose loot bags are capped (overflow loot auto-sells to gold)
> so heavily-farmed high-tier floors stay stable.

## Floor modifiers

Random per floor: **CURSED** (enemies +50% speed), **BLOODLUST** (enemies 2× HP), **HAUNTED**
(all enemies elite), **ARCANE** (2× mana regen), **HASTE** (player +30% speed). Higher
difficulties can stack two.

## Meta-progression

- **Leaderboards** — local top-10 (portals used, gold earned, damage dealt; per-biome bests)
  plus an online leaderboard.
- **Run history** — last few runs auto-saved.
- **Persistent player level + stash** — XP and banked gear carry between runs; higher levels
  unlock better procedural drops.

## Controls

| Key / Button  | Action                                          |
|---------------|-------------------------------------------------|
| W A S D       | Move                                            |
| Left mouse    | Shoot (hold to rapid-fire)                      |
| Right mouse   | Shield (drains mana while held)                 |
| Shift         | Dash (stamina, i-frames, pass through enemies)  |
| Space         | Levitate (mana, float over floor hazards)       |
| Q             | Nova spell                                       |
| E             | Interact (chests, shrines, switches, portals)   |
| I             | Toggle inventory                                |
| F1            | Cycle view: top-down → 3rd person → 1st person  |
| Esc           | Pause menu                                       |

**Debug / accessibility:** `H` toggles a hitbox-visualization overlay, `Shift+D` toggles
first-person limb-drift, `0` toggles autoplay (a self-driving demo bot), and the pause menu has
a **Reduce Flashing** toggle that tames strobing effects.

## Project structure

```
dungeon_crawler/
├── project.godot
├── README.md / DOOM_DESIGN.md   # this file + the DOOM-systems design roadmap
├── scenes/          # Player, World, Village, TitleScreen, enemies, pickups,
│                    # hazards (Door, BeamTrap, Switch, AmbushController, …), UI
├── scripts/
│   ├── GameState.gd          # autoload — stats, difficulty, biome, render mode
│   ├── InventoryManager.gd   # autoload — bag + equipment
│   ├── Leaderboard.gd        # autoload — local high scores
│   ├── OnlineLeaderboard.gd  # autoload — online scores
│   ├── RunHistory.gd         # autoload — recent run log
│   ├── PersistentStash.gd    # autoload — cross-run storage
│   ├── QuestLog.gd           # autoload — quest tracking
│   ├── SoundManager.gd       # autoload — audio
│   ├── Player.gd             # movement, shooting, abilities, HUD, input
│   ├── World.gd              # procedural gen (BSP/cave/halls), spawns, hazards
│   ├── FirstPersonRig.gd     # 3D ASCII first/third-person rendering rig
│   ├── EnemyBase.gd          # shared enemy AI; Enemy*.gd extend it
│   ├── ItemDB.gd             # item generation, affixes, legendaries
│   └── Door / BeamTrap / Switch / AmbushController …  # DOOM-style geometry/triggers
└── shaders/
    ├── ascii_post.gdshader   # first-person ASCII post-effect (brightness → glyphs)
    ├── crt_overlay.gdshader  # optional CRT post-effect
    └── floor_dots.gdshader   # ASCII grid floor
```

## Setup

1. Clone the repo.
2. Open **Godot 4.6** (4.3+ should work).
3. In the Project Manager, click **Import** and select `project.godot`.
4. Hit **F5** to run. The main scene is `TitleScreen.tscn`.

The project uses the Forward+ renderer (required for the first-person 3D lighting); switch to
Mobile or Compatibility in **Project Settings → Rendering → Renderer** if your hardware needs it.

## Roadmap

- [x] Player movement, shooting, abilities (dash / levitate / nova / shield)
- [x] ~25 enemy archetypes + 6 bosses with gate phases
- [x] Procedural floor generation, themed rooms, biomes
- [x] HP / mana / stamina, inventory, enchanting, sell chest, bank, stash
- [x] Status effects (burn, freeze, shock, poison, slow, disorient)
- [x] First-person & third-person ASCII rendering
- [x] DOOM-style geometry & triggers (doors, beam traps, switches, ambush rooms)
- [x] Sector lighting (dark / flickering rooms, torch flicker)
- [x] Late-game stability caps (live enemies + loot bags)
- [x] Local + online leaderboards, run history, persistent progression
- [ ] Sound and music pass
- [ ] Lifts / crushers / per-tile floor height (DOOM_DESIGN.md "next")
- [ ] Keys & locked doors
- [ ] Additional biomes / boss variants
- [ ] Controller support

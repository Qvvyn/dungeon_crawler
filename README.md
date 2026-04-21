# DungeonCrawler

A work-in-progress procedurally generated dungeon crawler built in Godot 4.

## Current features
- WASD movement with `CharacterBody2D`
- Mouse-aimed projectile shooting (left click / hold)
- Projectiles disappear on contact with any hitbox

## Project structure

```
dungeon_crawler/
├── project.godot          # Engine config & input map
├── scenes/
│   ├── World.tscn         # Main scene (contains player + test targets)
│   ├── Player.tscn        # Player node (CharacterBody2D + collision + visual)
│   └── Projectile.tscn    # Projectile node (Area2D + collision + visual)
└── scripts/
    ├── Player.gd           # Movement + shooting logic
    └── Projectile.gd       # Projectile movement + collision + lifetime
```

## Setup

1. Clone the repo
2. Open **Godot 4.x** (4.3+ recommended)
3. In the Project Manager, click **Import** and select the `project.godot` file
4. Hit **F5** to run

## Controls

| Key / Button | Action |
|---|---|
| W A S D | Move |
| Left mouse button | Shoot (hold to rapid-fire) |

## Godot version

Tested on **Godot 4.3**. The project uses Forward+ renderer; switch to Mobile or
Compatibility in Project Settings → Rendering → Renderer if needed.

## Roadmap

- [ ] Enemy nodes with basic AI
- [ ] Procedural room/dungeon generation
- [ ] Health system
- [ ] Pickups / loot

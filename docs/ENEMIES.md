# Enemy Reference

Living catalog of every enemy: behavior, stats, how it damages/impedes the
player, spawn conditions, and its assigned ASCII sprite. Keep this updated when
enemies or sprites change.

> **HP note:** all enemy HP scales ~**+50% per +1.0 difficulty**; the numbers
> below are the floor-1 base. Damage/speed values are flat.

## Damage & impede types (quick map)
- **Contact** (touching you): Spider, Charger, Bomber
- **Telegraphed melee swing**: Chaser, Tank, Berserker, Stalker, BoneDrake
- **Projectiles**: Shooter, Archer, Sniper, Wizard, Phantom, Spiral Mage, Missile Turret, Grenadier
- **Zone / AoE**: Banshee (pulse), Magma Slug (lava trail), Frost Sentinel (ice), Beam Sweep (beam), Mine Layer (mines)
- **Impede (not damage)**: Tank knockback, Devourer tether-pull, Spider web-slow, Ice-biome/Frost Sentinel freeze, Enchanter (buffs other enemies)

## Sprite assignments
Sprites live in `scripts/AsciiSprites.gd` (art in `assets/ascii/sprites/*.txt`).
Wired via `EnemyBase.SCRIPT_TO_KEY` (EnemyBase subclasses) or a manual driver
in the script (standalone enemies). Size tiers: 1 tiny/low · 2 small · 3 human ·
4 large · 5 towering (`AsciiSprites.SIZE_HEIGHTS`).

| Enemy | Sprite | Size | Notes |
|---|---|---|---|
| Chaser | `goblin` | 2 | flip-animated run |
| Spider | `spider2` | 3 | y-axis flip-animated scuttle |
| Tank | `tank_man` | 4 | |
| Berserker | `knight` | 3 | armored two-weapon humanoid |
| Charger | `minotaur` | 4 | y-axis flip animation |
| Stalker | `bat` | 1 | flying (eye level); faint when hidden |
| Banshee | `ghost_big` | 3 | |
| Phantom | `ghost_big` | 3 | fades between shots |
| Enchanter | `fairy` | 1 | flying |
| Spiral Mage | `jester` | 3 | y-axis flip animation |
| Beam Sweep | `jester_head` | 2 | flying (eye level) |
| Summoner | `gnome` | 2 | gnome necromancer |
| Sniper | `swimmer` | 2 | y-axis flip; aim telegraph via tint/laser |
| Splitter | `ghost` | — | Chaser variant; bursts into two on death |
| Mine Layer | `brute` | 3 | |
| Reflector | `reflector` | 3 | flying arcane mirror-mage |
| Bone Drake | `bone_drake` | 4 | tall skeletal dragon |
| Shooter | `shooter` | 3 | grinning dragon-skull turret |
| Missile Turret | `eye2` | 1 | flying ornate eye |
| Frost Sentinel | `ice_sentinel` | 4 | tall ornate ice golem |
| Grenadier | `grenadier` | 2 | y-axis flip (rotate-on-axis) |
| Bomber | `bomber` | 3 | spherical lit-fuse bomb |
| Boss (Brute) | `boss_brute` | 4 | |
| *(all others)* | original inline glyph | — | not yet wired |

---

## Regular enemies

### Melee / rushers
- **Chaser** — HP 10, spd 150. Flanks in with separation steering; telegraphed melee (1 dmg). Patrols until it spots you (sight 300). *Catacombs:* 10% of corpses reanimate into a Chaser after 5s.
- **Spider** — HP 2, spd 310. Fast swarm fodder; phases through other enemies. Contact = 1 dmg + a brief **web slow** (0.55s cd). Sight 560.
- **Tank** — HP 100, spd 52. A slow wall. Melee 2 dmg + heavy **knockback** (380); periodically **charges** (560 spd, 0.45s telegraph, 4–7.5s cd).
- **Berserker** — spd 95, melee 2 dmg (reach 28, 1.0s). Moves & attacks **faster as HP drops** (rage).
- **Charger** — spd 95. Closes, then **dashes in a straight line** (720 spd, 0.7s telegraph, range 360) for 4 contact dmg; 1.2s cd.
- **Stalker** — HP 14. Near-**invisible** (20% alpha) until it has line of sight; spots (0.4s), **rushes** (220) and bites (4 dmg), retreats (1.6s), re-hides. Sight 720 both directions.
- **Bomber** — spd 145. Rushes and **self-detonates** on contact (within 36px) or after an 8s fuse — 8 dmg in a 70px radius (0.55s warning flash).
- **BoneDrake** *(Catacombs)* — approaches (130) / retreats (95); **2-hit melee combo** (3 dmg each, 2.5s period).

### Ranged / kiters
*(kite at a preferred distance, telegraph before firing, won't shoot through walls)*
- **Shooter** — HP 10, kites ~350. Straight bolt (320 spd) every 2s. Sight 320.
- **Archer** — HP 14, kites ~280. **Arcing lob** at your predicted position (240 spd, 2 dmg, 3.5s). Sight 340.
- **Sniper** — HP 12, kites far (~480, sight 900). 1.5s wind-up → long-range shot (5s cycle); retreats fast (200) if approached.
- **Wizard** — HP 55, kites ~300. Fires a **real, lootable wand** (random school) and **drops that wand** on death. One spawns per portal room guarding the exit.
- **Phantom** — **fades to ~15% alpha** between shots, flickering visible only as it fires (380-spd bolt, 2 dmg, 1.6s).
- **Spiral Mage** — fires a continuous **rotating spiral** barrage (4 shots / 0.28s, slow 175-spd bullets, 1 dmg) — bullet-hell zoning.
- **Missile Turret** — **stationary**. Locks on, fires a slow missile (200 spd, 4 dmg, 4s).
- **Grenadier** — kites ~280. **Lobs grenades** with a ground warning circle (230 spd, 5 dmg, 3.6s, 0.55s telegraph).

### Hazard / zone
- **Magma Slug** *(Lava Rift)* — very slow (30). Leaves a **trail of damaging lava tiles** (every 1.6s / 64px moved).
- **Frost Sentinel** *(Ice Cavern)* — slow (50). Spawns **5 ice patches** around itself every 4s (within 80px) that chill/freeze you.
- **Beam Sweep** — telegraphs 0.85s, then **sweeps a ~99° beam** (range 380; ticks 1 dmg / 0.25s; 4.5s period).
- **Mine Layer** — kites ~380. Drops **proximity mines** (max 4 active, every 2.5s).
- **Banshee** — floats. Telegraphed (1.4s) **AoE scream pulse** around itself (6 dmg, 130px radius, every 4s).

### Support / special
- **Enchanter** — HP 10. Ignores you; chases the nearest ally and **buffs it** (2× speed/attack) via a tethered cast (5s). Kill it first.
- **Summoner** — HP 8, keeps ~290 distance. **Summons minions** (up to 3 alive).
- **Reflector** — very slow (35). **Reflects your projectiles** back in a 110° frontal arc — flank it.
- **Splitter** — a Chaser that **bursts into two half-HP Chasers** on death.
- **Spawner / Nest** — **static, hidden** until seen; HP 90×(1+diff·0.5). Continuously **spawns one fixed species** (3–7 cap) until destroyed. *Diff ≥ 4 only*, in the farthest room. Rich drops.

---

## Bosses
Spawn on every **5th floor** (`portals_used % 5 == 4`); **floor 50** is a 3-boss gauntlet. A **mini-boss** (reduced-HP boss) can also appear on non-boss floors at diff ≥ 4 (chance up to 40%).

- **Brute / Void Herald** — HP 200. 3 phases (50%, 25% HP); radial **bullet-hell** bursts (4 → 8 → 16 shots) + melee + teleport. PREFERRED 250.
- **Lich** — HP 280. **Summons 3 minions** every 5s and **self-heals 12%** when below half HP — attrition fight.
- **Wraith** — HP 220. Mobile; fast **aimed** shots.
- **Magma Boss** — HP 280. **5-shot fan** (70° arc, 4.5s) + a close melt AoE (90px).
- **Architect** — HP 260. Aimed **spread** + 12-shot **nova** + lays **mines** + deploys **turrets**. SPEED 130.
- **Devourer** — HP 600 (tankiest). Heavy **bite** (12 dmg, 90px) + a **tether that yanks you in** from up to 280px.

---

## Spawn system
- **Floors:** boss arena every 5th; floor 50 gauntlet. Portal **Wizard** guards the exit each non-boss floor (floor ≥1). **Mini-boss** at diff ≥ 4 (≤40%). **Nests** at diff ≥ 4 (2 at diff ≥15, 3 at diff ≥30).
- **Difficulty gates** (the "surprise" pool): Bomber ≥1.5, Berserker ≥2.0, Phantom/Stalker ≥2.5, Banshee ≥3.0 (30%), Reflector ≥3.5 (25%); Splitter any (35%). The base pool (Chaser, Shooter, Tank, Sniper, Archer, Spider, Enchanter, Summoner, Spiral, Grenadier, Charger, Mine Layer, Beam Sweep, Missile Turret) is always eligible; counts/HP scale with difficulty (higher = fewer but bulkier).
- **Biomes:** 0 Dungeon · 1 Catacombs (+BoneDrake, corpse revives) · 2 Ice Cavern (+Frost Sentinel; enemies spawn **pre-frozen**) · 3 Lava Rift (+Magma Slug; periodic eruptions).
- **Elite/Champion modifiers** (any enemy): Shielded (blocks 1 hit), Splitting, Enraged (speeds up at low HP), Volatile (explodes on death). Champions at diff ≥4 (2/floor). The **HAUNTED** floor modifier makes *every* enemy elite.
- **Cap:** 45 live enemies (`World.MAX_LIVE_ENEMIES`).

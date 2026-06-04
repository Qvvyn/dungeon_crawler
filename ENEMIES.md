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
| Archer | `archer` | 2 | 2-frame bow-draw |
| Spawner | `spawner` | 4 | flying portal, 2-frame eye flicker |
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

## ASCII forms & attack glyphs

### Projectile / attack glyph reference
The character an attack draws in **top-down 2D** (set in `Projectile.gd`). In
**first-person every enemy projectile renders as a red `o`** regardless of type.

| shoot_type | 2D glyph | colour | used by (enemies) |
|---|---|---|---|
| regular | `'` | white | Shooter, Phantom, Spiral Mage, all boss bolts |
| arc | `)` | orange | Archer |
| grenade | `O` | orange | Grenadier |
| missile | `>` | red | Missile Turret |
| pierce | `)` | blue | Wizard (pierce wand) |
| freeze | `*` | ice-blue | Wizard (freeze wand) |
| fire | `@` | red-orange | Wizard (fire wand) |
| shock | `~` (FP `z`) | purple | Wizard (shock wand) |
| shotgun | `#` | grey | Wizard (shotgun wand) |

*(ricochet `o`, homing `^`, nova `+`↔`x`, nova_shard `✦`, love `<3` are player-only wand types.)*

**Non-projectile attackers** use beams / rings / hazard tiles instead of a glyph:
beam enemies (Beam Sweep, Sniper, Devourer tether, Boss charge) mirror into FP via
`set_enemy_beam` — a dotted `·` line during the telegraph, a solid beam on the hit;
Banshee/Bomber use expanding ring `Line2D`s; melee enemies show the FP `><` impact
flash; hazard enemies drop tiles (lava `~`, ice patches, mines `[#X#]`).

### Per-enemy forms & attacks
Sprite-driven enemies render the listed `.txt` frame(s) (browse them in the **F9
gallery**); **+flip** = horizontal y-axis mirror frame, **tint** = recoloured death
frame. Each enemy also keeps a small inline-art fallback drawn only if its sprite
fails to load.

**Melee / rushers**
- **Chaser** — `goblin.txt` idle/walk (+flip run cycle), death tint. *Attack:* melee swing, no glyph; FP `><` flash.
- **Spider** — `spider2.txt` idle/walk (+flip), death tint. *Attack:* contact + brief web-slow, no glyph.
- **Tank** — `tank_man.txt` idle, death tint. *Attack:* melee + knockback, plus a telegraphed straight charge; no glyph; FP `><`.
- **Berserker** — `knight.txt` idle, death tint. *Attack:* rage-scaled melee swing; FP `><`.
- **Charger** — `minotaur.txt` idle/walk (+flip), death tint. *Attack:* telegraphed straight dash, contact; no glyph.
- **Stalker** — `bat1.txt`↔`bat2.txt` wing-flap idle/walk, death. *Attack:* melee bite after a rush; near-invisible until it has LOS.
- **Bomber** — `bomber.txt` idle, death tint. *Attack:* contact self-detonation (orange shockwave ring), no glyph.
- **BoneDrake** — `bone_drake.txt` idle, death tint. *Attack:* 2-hit melee combo; FP `><`.

**Ranged / kiters**
- **Shooter** — `shooter.txt` idle, death tint. *Attack:* regular bolt `'` (FP `o`).
- **Archer** — `archer1.txt`↔`archer2.txt` 2-frame bow-draw, death tint. *Attack:* arcing lob `)` orange (FP `o`).
- **Sniper** — `swimmer.txt` idle (+flip), death tint. *Attack:* hitscan beam — orange aim line → red shot; FP red laser tube.
- **Wizard** — sprite ` (*-*)`↔` (*3*)`, death ` (x_x)`. *Attack:* its equipped wand's type — pierce `)` / freeze `*` / fire `@` / shock `~` (FP `z`) / shotgun `#` / default `'`. Drops the wand on death.
- **Phantom** — `ghost_big` (`ghost.txt`↔`ghost_blink.txt`, hurt `ghost_hurt.txt`). *Attack:* regular bolt `'` (FP `o`); fades to ~15% alpha between shots.
- **Spiral Mage** — `jester.txt` idle/walk (+flip), death tint. *Attack:* rotating spiral of regular bolts `'` (FP `o`).
- **Missile Turret** — `eye2.txt` idle, death tint. *Attack:* homing missile `>` red (FP `o`); pulsing red lock telegraph.
- **Grenadier** — `grenadier.txt` idle/walk (+flip), death tint. *Attack:* grenade `O` orange (FP `o`) with a ground warning ring.

**Hazard / zone**
- **Magma Slug** — inline `()(`↔`)()` art (`magma_slug` gallery sprite; not driver-wired). *Attack:* trail of lava `~` hazard tiles; no glyph.
- **Frost Sentinel** — `ice_sentinel.txt` idle, death tint. *Attack:* spawns 5 ice patches around itself; no glyph.
- **Beam Sweep** — `jester_head.txt` idle↔attack, hurt, death. *Attack:* swept beam — 0.85 s telegraph (FP dotted `·`) → orange beam.
- **Mine Layer** — `brute` sprite (inline idle/walk/hurt/death frames). *Attack:* drops `Mine` (`[#X#]` armed) that detonate by proximity.
- **Banshee** — `ghost_big` (`ghost.txt`↔`ghost_blink.txt`, hurt). *Attack:* AoE scream — expanding purple→red ring; no glyph.

**Support / special**
- **Enchanter** — `fairy.txt` idle, death tint. *Attack:* non-damaging buff projectile (own scene) + purple tether to the ally it buffs.
- **Summoner** — `gnome.txt` idle, death tint. *Attack:* summons Chaser minions (≤3); glyph swap `|o|`↔`|*|` on cast.
- **Reflector** — `reflector.txt` idle, death tint. *Attack:* 110° teal reflect arc that bounces your shots back; no glyph of its own.
- **Splitter** — `ghost` sprite (inline idle/walk/hurt/death). *Attack:* melee (Chaser-inherited); bursts into 2 half-HP Chasers on death.
- **Spawner / Nest** — `spawner1.txt`↔`spawner2.txt` (2-frame eye flicker), death tint. *Attack:* none — continuously spawns one fixed species.

**Bosses** *(inline art shown is the actual sprite; idle alternates F0↔F1, death tints F1)*
- **Brute / Void Herald** — `boss_brute` (`brute_boss.txt`), death tint. *Attack:* spiral + radial bursts of regular bolts `'` (FP `o`) + melee charge dash (FP yellow wind-up beam).
- **Architect** — `.+.`/`>*<`/`.+.` ↔ `-+-`/`>X<`/`-+-`. *Attack:* aimed spread + 12-shot nova (regular `'`, FP `o`) + lays Mines `[#X#]` + deploys turrets.
- **Devourer** — `/(O)\`/`\m/` ↔ `/(o)\`/`/M\`. *Attack:* tether yank (orange line → hot pull beam; FP beam) + contact bite AoE; no glyph.
- **Lich** — `/=\`/`|O|`/`/^\` ↔ `/=\`/`|o|`/`/v\`. *Attack:* summons Chaser minions every 5 s + self-heal below half HP; no projectile.
- **Magma Tyrant** — `/^\`/`[#X#]`/`/|\` ↔ `\^/`/`(#X#)`/`/|\`. *Attack:* fireball (regular `'`, FP `o`) + erupt ring of lava `~` tiles.
- **Wraith** — `/W\`/`~~` ↔ `\W/`/`~~~`. *Attack:* blink + multi-shot volley (regular `'`, FP `o`); more shots at ≤45% HP.

---

## Spawn system
- **Floors:** boss arena every 5th; floor 50 gauntlet. Portal **Wizard** guards the exit each non-boss floor (floor ≥1). **Mini-boss** at diff ≥ 4 (≤40%). **Nests** at diff ≥ 4 (2 at diff ≥15, 3 at diff ≥30).
- **Difficulty gates** (the "surprise" pool): Bomber ≥1.5, Berserker ≥2.0, Phantom/Stalker ≥2.5, Banshee ≥3.0 (30%), Reflector ≥3.5 (25%); Splitter any (35%). The base pool (Chaser, Shooter, Tank, Sniper, Archer, Spider, Enchanter, Summoner, Spiral, Grenadier, Charger, Mine Layer, Beam Sweep, Missile Turret) is always eligible; counts/HP scale with difficulty (higher = fewer but bulkier).
- **Biomes:** 0 Dungeon · 1 Catacombs (+BoneDrake, corpse revives) · 2 Ice Cavern (+Frost Sentinel; enemies spawn **pre-frozen**) · 3 Lava Rift (+Magma Slug; periodic eruptions).
- **Elite/Champion modifiers** (any enemy): Shielded (blocks 1 hit), Splitting, Enraged (speeds up at low HP), Volatile (explodes on death). Champions at diff ≥4 (2/floor). The **HAUNTED** floor modifier makes *every* enemy elite.
- **Cap:** 45 live enemies (`World.MAX_LIVE_ENEMIES`).

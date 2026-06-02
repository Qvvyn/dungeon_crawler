# DOOM Design & Efficiency Roadmap

A living reference for techniques borrowed from id Software's DOOM (1993). This game
organically grew into a DOOM-shaped engine; this doc maps what DOOM did onto our actual
code so we can adopt the *useful* parts deliberately and skip the parts a modern GPU makes
irrelevant.

Not a backlog of tasks — a map. Concrete TODOs still live in `^.txt`. Every code reference
below is `file:line` so a future session can jump straight to it. Line numbers drift; treat
them as starting points, not gospel.

---

## 0. Status

**Shipped** (branch `doom-systems-and-stability`):

- **Animated wall-segment primitive** — `FirstPersonRig.add_wall_segment` /
  `set_wall_segment_open` / `remove_wall_segment`. Segments live in `_world3d` on `LAYER_ENV`,
  never baked into the chunked wall MultiMesh (`_wall_chunks`), so animating a height never
  triggers a rebuild. This is the §3 "core capability", realized.
- **Sector-chunked wall MultiMesh** — walls split into `WALL_CHUNK_SIZE`×`WALL_CHUNK_SIZE`
  (8×8 tile) chunks, each its own `MultiMeshInstance3D` in `_wall_chunks`. `rebuild_walls()`
  still does a full rebuild for now; the new `rebuild_wall_chunk_for_tile(gx, gy)` will let
  per-tile height changes (lifts, crushers) invalidate only their chunk once §3 lands.
- **Doors** — `Door.gd` / `Door.tscn`: auto-open on approach (sink into floor), plus
  `remote_only` + `start_open` + `open()/close()` for seals. Placed by `World._spawn_doors`.
- **Beam-trap corridors** — `BeamTrap.gd` (high + floor-level / levitate-able variants),
  placed by `World._spawn_beam_traps`.
- **Triggers & ambushes** — `EnemyBase.alert_by_sound(pos, radius)`; `World.spawn_ambush_wave`;
  `AmbushController.gd` (tripwire → seal doorways + spawn wave → clear/timeout reopens + reward);
  shootable `Switch.gd` → opens a door sealing a dead-end loot alcove (`World._spawn_switch_alcove`).
- **FP render efficiency** — deduped per-frame enemy walk; HP-bar text cache (`_hp_bar_fill`).
  (Two of the §2 findings below, now done.)
- **Sector lighting** — torch flicker + per-room DARK / FLICKER levels
  (`FirstPersonRig.set_room_lighting` / `_update_lighting`, `World._assign_room_lighting`).
  Realizes the "darkness" idea for first-person.
- **Late-game stability caps** — `World.MAX_LIVE_ENEMIES` + `can_spawn_enemy()` honored by every
  runtime spawner (splitter, zombie reanimation, dungeon-queue drain); `MAX_LIVE_LOOT_BAGS` +
  `enforce_loot_cap()` (farthest overflow bags auto-sell to gold). Addresses the §2 "absurd
  number of enemies" concern.

**Next** (not yet built):

- Lifts / moving-floor platforms — reuse the segment primitive (§3 phase 2).
- Per-tile **static** floor height — steps / pits / raised ground (§3 phase 3).
- **Crusher** hazard — segment primitive + damage zone; the `BeamTrap`-as-crusher idea (§3 phase 4).
- **Keys / locked doors** — gate `Door.open()` behind an inventory key item.
- **Sound-propagation alerting** — the `alert_by_sound` hook exists; just call it from loud events.
- 2D top-down **vision radius** + a shader **"blinded"** vignette (a darkness uniform in
  `ascii_post.gdshader`).
- **Height-aware occlusion** (§3 follow-on) — only once partial-height geometry must hide entities.
- Entity spatial buckets / PVS (§2) — only if profiling demands it.

The technique map below is unchanged; treat §0 as the live checklist over it.

---

## 1. What we already share with DOOM

We arrived here without trying, which is why the borrowing is natural:

| Our engine | DOOM equivalent | Where |
| --- | --- | --- |
| Tile grid `_grid[y][x]`, binary `FLOOR=0`/`WALL=1` | The **blockmap** (spatial grid for fast lookups) | `World.gd:4-8` |
| Billboarded `Label3D` enemies that always face the camera | **Sprite monsters** (2D cutouts, no 3D models) | `FirstPersonRig.gd` entity loop |
| Uniform 1.5-tall box walls, flat floor + flat ceiling | DOOM's **2.5D** constraint (no room-over-room) | `FirstPersonRig.gd:359` `rebuild_walls()`, `_WALL_H` |
| **BSP** partitioning to lay out rooms | DOOM used BSP too — but for *rendering*, we use it for *generation* | `World.gd:218` `BSPNode`, `World.gd:799` `_bsp_split()` |

One thing that is **ours, not DOOM's**: the two-SubViewport split — an ASCII-shaded
environment viewport plus a crisp un-shaded entity viewport. This matters because it shapes
which optimizations apply: walls/floor go through the post-process shader, entities don't, and
the cameras are mirrored every frame. Any rendering change has to respect that the env pass is
already a fixed-cost full-screen shader regardless of scene complexity.

---

## 2. Efficiency thread — "only touch the potentially visible"

DOOM's whole performance story is restraint: the BSP tree, the potentially-visible-set (PVS),
and the reject table all exist so the engine never processes geometry or monsters it can't see.
Our hot path violates that in a few spots. None are emergencies — they're the cheap wins to
take opportunistically.

### Findings (from a render-loop audit)

- **The entity sync loop is the dominant per-frame cost.** `FirstPersonRig._process` walks
  every registered entity and, for each, syncs glyph text, status overlays, rotation, and
  billboard orientation. It allocates inside the loop — e.g. `live_text.split("\n")` per
  multi-line entity per frame. **Lesson:** early-out for entities past the cull distance
  *before* doing string work; cache the `.split()` result and only recompute when the source
  text actually changed.

- **The enemy list is re-scanned every frame to auto-register stragglers.** A per-frame walk of
  the whole `"enemy"` group exists to catch enemies that didn't self-register on `_ready`.
  **Lesson:** register on spawn (or via a signal) so the steady state isn't an O(enemies) poll
  every frame.

- **HP-bar text is rebuilt every frame.** The `"=".repeat(filled) + "-".repeat(empty)` bar
  string is reconstructed per enemy per frame (`FirstPersonRig.gd` ~L1481). **Lesson:** only
  rebuild when the fill *bucket* changes (e.g. integer count of filled segments), not every
  frame.

- **The occlusion raycast is already doing it right — keep it as the template.**
  `_raycast_to_grid` (`FirstPersonRig.gd:179`) is a DDA grid walk, 0.10-tile step (≈80 steps
  across the 8-tile cull radius). It's throttled to ~1/3 of entities per frame (staggered by
  instance id) and cached in `_occlusion_cache`. The DOOM analog is a precomputed PVS — **only**
  worth building if profiling ever shows this raycast dominating. Right now it's the model to
  copy, not the thing to fix.

- **Entity visibility is a linear scan; there is no spatial partition.** DOOM's blockmap bucketed
  things by cell so a query only touched nearby buckets. If entity counts climb (this directly
  ties to the late-game "absurd number of enemies" item in `^.txt`), bucket entities by grid
  cell and have the loop visit only cells near the camera. **Optional** — do it only when the
  numbers demand it.

### Explicit non-goals (don't port these)

- **BSP draw-ordering / painter's algorithm.** DOOM sorted walls front-to-back via BSP because
  it had no z-buffer. Godot has one. Skip.
- **Visplanes / per-column texture mapping.** Obsoleted by the GPU. Skip.
- **Fixed-point math.** A 1993 CPU concern. Skip.

---

## 3. Design thread — animated floor/ceiling height (the core capability)

This is the headline idea, and it is **not** "doors." The thing worth stealing from DOOM is the
*sector* model: every area carries a floor height and a ceiling height, and those heights can
**animate over time**. Once you have that one capability, a whole family of features falls out
of it for free. The wall-door is merely the simplest example — listed here as *an* application,
not the goal:

- **Door** — a tile whose wall/ceiling segment animates between full height (blocked) and 0
  (open). The classic DOOM door is a ceiling that drops to the floor.
- **Lift / elevator** — a floor tile whose height animates between two levels.
- **Crusher** — a ceiling that descends to deal damage (our `BeamTrap` could become one).
- **Pits / steps / raised platforms** — *static* per-tile height variation, purely for level
  texture and readability.
- **Boss arena gimmick** — many segments animating in concert (pairs naturally with the
  "fill the arena with preemptive warning lines, force the player into the gaps" idea already
  in `^.txt`).

### Current limits to overcome

- The grid is binary (`FLOOR`/`WALL`) — no per-tile height data exists.
- Wall height is a single global constant (`FirstPersonRig.gd` `_WALL_H`).
- `rebuild_walls()` (`FirstPersonRig.gd:359`) does a **full** MultiMesh rebuild on any change.
  That's fine for rare events (a secret opening) but far too costly to run per frame for a
  smooth animation.
- Geometry changes today are **instantaneous** — there's no interpolation step. But the
  *mutation hook already exists*: `open_secret_passage` and `notify_wall_destroyed` (both in
  `World.gd`) flip grid cells and call `rig.set_grid()` / `rebuild_walls()`. We'd be adding
  animation on top of a path that already works, not inventing the path.

### Key implementation note

Animated segments should be **separate `MeshInstance3D` nodes** added to `_world3d`, *not* baked
into the chunked wall MultiMesh (`_wall_chunks`). That way changing a height tweens a single
node's transform and never triggers a rebuild. *Static* height variation (steps, pits) lives in
the baked chunks; call `rebuild_wall_chunk_for_tile(gx, gy)` to invalidate only the affected
chunk instead of doing a whole-wall rebuild. For anything triggered, reuse the `SpikeTrap` /
`BeamTrap` state-machine + `attach_fp_visual` patterns we already have.

### Follow-on

`_raycast_to_grid` assumes binary walls, so it can't yet reason about partial-height geometry
hiding things. Height-aware occlusion is later work — only needed once a segment can be
"half up" and expected to occlude accordingly.

### Suggested phasing (each ships independently)

1. The height-animated segment **primitive** + one example use (a door is the cheapest).
2. Lift / moving-floor platform.
3. Per-tile **static** height map for level texture (steps, pits, raised ground).
4. Crusher hazard (reskin of the segment primitive + damage zone).
5. Height-aware occlusion (only if partial-height geometry needs to hide entities).

---

## 4. Suggested ordering across both threads

| Priority | Item | Why now / why wait |
| --- | --- | --- |
| Opportunistic | HP-bar text cache, register-enemy-on-spawn, early-cull before allocs | Cheap, low-risk, pure wins; fold in whenever touching `FirstPersonRig._process` |
| First real slice | Height-animated segment primitive (proven via one door) | Validates the whole sector direction with minimal surface area |
| Gated on "is it fun" | Lifts, static height map, crusher | Bigger; only worth it if the primitive feels good in play |
| Gated on profiling | Entity spatial buckets, PVS | Only if entity counts or raycasts actually dominate a frame |

The litmus test stays DOOM's own: **don't pay for what you can't see, and let one general
mechanic (animated height) earn its keep across many features before generalizing further.**

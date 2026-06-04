# ASCII art tooling

Offline authoring helpers. **Nothing here is loaded by the game at runtime** —
these turn source images into the `.txt` files that live in
`res://assets/ascii/` and get shown by `AsciiSetPiece`.

## The generation + approval workflow

ASCII art can't be judged until it's rendered in the real font at the real
size — so generation and review are one loop. Anchor: **hybrid by scale.**

1. **Generate** (by scale):
   - *Entity sprites* (3–6 rows): drafted as text (Claude/hand), authored
     straight into `scripts/AsciiSprites.gd` — it's pure data, easy to add/remove.
   - *Large set-pieces* (20–60 rows): curate from `ascii art i like..txt` or
     ASCII archives, or convert an image (below). Save as `.txt` in
     `res://assets/ascii/`.
2. **Review in the gallery** — open `res://scenes/SpriteGallery.tscn` (F6 in the
   editor, or `Godot <project> res://scenes/SpriteGallery.tscn`). It renders
   every `AsciiSprites` entry and every `assets/ascii/*.txt` in the real
   MonoFont, at real size, on a 32px tile grid. `←/→` sprite · `1-4` play
   idle/walk/hurt/death · `F` cycle font · `G` grid · `+/-` zoom · `R` reload.
3. **Approve / tweak** — thumbs-up keeps it; otherwise tweak the frames and
   press `R`. Once blessed it's already in the right place (library or assets).

## When to use a converter vs. hand-author

| Scale | What | How |
|-------|------|-----|
| **Large set-pieces** (title, boss reveal, NPC portrait, death screen) | 20–60 rows | Convert an image with `chafa` or `img2ascii.py`, then hand-clean. |
| **Entity sprites** (enemies, player, projectiles) | 3–6 rows | **Hand-author** in `scripts/AsciiSprites.gd`. Auto-conversion at this scale is unreadable noise. |

## Option A — chafa (recommended, highest fidelity)

Install (Windows): `scoop install chafa`, or grab a build from the chafa releases.

```
chafa --format symbols --symbols ascii --size 60x36 --fg-only -c none in.png > ../assets/ascii/dragon.txt
```

- `--symbols ascii` keeps it to plain ASCII (drop it for richer Unicode blocks).
- `--size WxH` locks the character grid.
- `--fg-only -c none` strips colour so the game can tint the art itself.

## Option B — img2ascii.py (dependency-light fallback)

```
pip install pillow
python img2ascii.py in.png -w 60 -o ../assets/ascii/dragon.txt
python img2ascii.py in.png -w 80 --invert      # light subject on dark background
```

`--aspect` corrects for monospace cells being ~2× taller than wide (default 0.5).

## After converting

1. Open the `.txt` and hand-tidy — converters always need a cleanup pass.
2. Drop it in `res://assets/ascii/`.
3. Show it via `AsciiSetPiece`:
   ```gdscript
   var piece := preload("res://scenes/AsciiSetPiece.tscn").instantiate()
   add_child(piece)
   piece.show_file("res://assets/ascii/dragon.txt", Color(0.8, 0.3, 0.3))
   ```
4. For simple animation (e.g. drifting hair wisps), put multiple frames in one
   file separated by a line containing only `---`, and call
   `piece.show_file(path, color, true)` to cycle them.

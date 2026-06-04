class_name AsciiSprites

# Central ASCII-art sprite library. One entry per `sprite_key`, holding the
# label styling (font size / colour / outline / box) plus an `anims` map of
# state -> ordered frames. AsciiSpriteDriver pulls from here to drive an
# entity's existing AsciiChar Label.
#
# Authoring rules (these keep both the 2D Label and the FP billboard happy):
#   * Pad every line of every frame to the SAME width, and give every state
#     of a sprite the SAME row count. The first-person rig bakes an entity's
#     row count at registration time and sizes it by that count forever, so a
#     death frame with a different height would rescale the whole body mid-
#     animation. Pad short rows/frames with spaces / blank lines instead.
#   * Backslashes must be escaped ("\\") and newlines written as "\n", exactly
#     like the existing inline art in EnemyChaser.gd / Player.gd.
#   * Frames are Dictionaries: {"t": <text>, "d": <seconds>, "mod": <Color?>}.
#     "mod" sets a one-off font_color override for that frame (used by death
#     frames to blacken the corpse); omit it to use the sprite's base colour.
#
# States the driver understands:
#   idle   - looped, shown when the entity is roughly stationary
#   walk   - looped, shown when moving (falls back to idle if absent)
#   hurt   - one-shot, played on taking damage then returns to idle/walk
#   death  - one-shot, holds its last frame; the driver also fades the label

# 5 enemy size tiers → world-unit height (TILE = 1 unit; player ≈ tier 3).
# 1 tiny/low · 2 small · 3 human · 4 large/looming · 5 towering. A sprite sets
# "size": N (default 3) and optional "flying": true. Drives both the gallery
# preview and the FP rig (via AsciiSpriteDriver.fp_metas).
const SIZE_HEIGHTS := {1: 0.45, 2: 0.75, 3: 1.05, 4: 1.7, 5: 2.8}

# ── Spider (EnemyBase pilot) ──────────────────────────────────────────────
# Compact 3-row / 5-col scuttler, inspired by the long-legged spider in
# "ascii art i like..txt" but shrunk to swarm-fodder scale.
const _SPIDER_IDLE_A := " \\|/ \n-(o)-\n /|\\ "
const _SPIDER_IDLE_B := " \\|/ \n-(O)-\n /|\\ "
const _SPIDER_WALK_A := " \\|/ \n-(*)-\n /|\\ "
const _SPIDER_WALK_B := " /|\\ \n=(o)=\n \\|/ "
const _SPIDER_HURT   := ">\\|/<\n-(x)-\n>/|\\<"
const _SPIDER_DEAD_A := " \\|/ \n-(X)-\n /|\\ "
const _SPIDER_DEAD_B := " \\ / \n (X) \n /_\\ "

# ── Ghost / Phantom (DRAFT — not wired to an enemy yet) ───────────────────
# Wispy specter, 4 rows / 5 cols. Blinks on idle, tail waves on walk.
const _GHOST_IDLE_A := " .-. \n(o o)\n )_( \n ' ' "
const _GHOST_IDLE_B := " .-. \n(- -)\n )_( \n ' ' "
const _GHOST_WALK_A := " .-. \n(o o)\n )~( \n '~' "
const _GHOST_WALK_B := " .-. \n(o o)\n )_( \n ~ ~ "
const _GHOST_HURT   := " .-. \n(x x)\n )_( \n ' ' "
const _GHOST_DEAD_A := " .-. \n(x x)\n )_( \n ' ' "
const _GHOST_DEAD_B := "  .  \n ' ' \n     \n     "

# ── Slime (DRAFT) ─────────────────────────────────────────────────────────
# Blobby 3-row / 5-col gel. Squashes on the offbeat of its hop.
const _SLIME_IDLE_A := " ___ \n(o o)\n\\___/"
const _SLIME_IDLE_B := " ___ \n(- -)\n\\___/"
const _SLIME_WALK_A := " ___ \n(o o)\n\\___/"
const _SLIME_WALK_B := "     \n ___ \n(o_o)"
const _SLIME_HURT   := " ___ \n(x x)\n\\___/"
const _SLIME_DEAD_A := " ___ \n(x x)\n\\___/"
const _SLIME_DEAD_B := "     \n     \n.___."

# ── Watcher eye (DRAFT — fits the "must be looked at" stalker idea) ────────
# Floating eyeball, 3 rows / 5 cols. Pupil drifts; lid shuts on death.
const _EYE_IDLE_A := ".---.\n( @ )\n'---'"
const _EYE_IDLE_B := ".---.\n(@  )\n'---'"
const _EYE_WALK_A := ".---.\n(  @)\n'---'"
const _EYE_WALK_B := ".---.\n( @ )\n'---'"
const _EYE_HURT   := ".---.\n( X )\n'---'"
const _EYE_DEAD_A := ".---.\n( X )\n'---'"
const _EYE_DEAD_B := ".---.\n(---)\n'---'"

# ── Brute (DRAFT — bulky horned melee) ────────────────────────────────────
# 5 rows / 7 cols. Legs stomp side to side on walk; slumps on death.
const _BRUTE_IDLE_A := " \\,-,/ \n (o o) \n/| O |\\\n | | | \n ^   ^ "
const _BRUTE_IDLE_B := " \\,-,/ \n (o o) \n/| o |\\\n | | | \n ^   ^ "
const _BRUTE_WALK_A := " \\,-,/ \n (o o) \n/| O |\\\n /| |\\ \n ^   ^ "
const _BRUTE_WALK_B := " \\,-,/ \n (o o) \n/| O |\\\n \\| |/ \n ^   ^ "
const _BRUTE_HURT   := " \\,-,/ \n (x x) \n/| O |\\\n | | | \n ^   ^ "
const _BRUTE_DEAD_A := " \\,-,/ \n (x x) \n/| O |\\\n | | | \n ^   ^ "
const _BRUTE_DEAD_B := "       \n \\,-,/ \n (x x) \n_(   )_\n  ___  "

# ── Bat (DRAFT — small flapping flyer) ────────────────────────────────────
# 3 rows. Idle/walk alternate raised (A) and lowered (B) wings = flapping.
const _BAT_A    := "\\__   __/\n  \\(oo)/\n   `--`"
const _BAT_B    := "__     __\n \\_(oo)_/\n  `----`"
const _BAT_HURT := "__     __\n \\_(xx)_/\n  `----`"
const _BAT_DEAD := "__  .  __\n \\_(xx)_/\n   `--`"

const SPRITES := {
	# Long-legged spider (file-backed); animates by horizontal flip ("mirror")
	# instead of hand-drawn legs — the scuttle reads from the axis swap.
	"spider": {
		"font_size": 13, "line_sep": -2, "color": Color(0.78, 0.55, 0.92), "size": 1,
		"outline": 3, "crop": true, "box": Rect2(-70.0, -60.0, 150.0, 120.0),
		"fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/spider.txt", "d": 0.5},
					 {"file": "res://assets/ascii/sprites/spider.txt", "mirror": true, "d": 0.5}],
			"walk": [{"file": "res://assets/ascii/sprites/spider.txt", "d": 0.16},
					 {"file": "res://assets/ascii/sprites/spider.txt", "mirror": true, "d": 0.16}],
			"death": [{"file": "res://assets/ascii/sprites/spider.txt", "d": 0.5, "mod": Color(0.2, 0.16, 0.22)}],
		},
	},

	# ── DRAFTS (in the gallery for review; not wired to enemies yet) ──────
	"ghost": {
		"font_size": 16, "line_sep": -4, "color": Color(0.82, 0.90, 1.0),
		"outline": 3, "box": Rect2(-24.0, -26.0, 48.0, 52.0),
		"fp_pixel_size": 0.013, "fp_outline_size": 11,
		"anims": {
			"idle":  [{"t": _GHOST_IDLE_A, "d": 0.6}, {"t": _GHOST_IDLE_B, "d": 0.18}],
			"walk":  [{"t": _GHOST_WALK_A, "d": 0.22}, {"t": _GHOST_WALK_B, "d": 0.22}],
			"hurt":  [{"t": _GHOST_HURT, "d": 0.14}],
			"death": [{"t": _GHOST_DEAD_A, "d": 0.14, "mod": Color(0.6, 0.6, 0.7)},
					  {"t": _GHOST_DEAD_B, "d": 0.26, "mod": Color(0.2, 0.2, 0.3)}],
		},
	},
	"slime": {
		"font_size": 16, "line_sep": -4, "color": Color(0.55, 0.90, 0.45), "size": 2,
		"outline": 3, "box": Rect2(-22.0, -20.0, 44.0, 40.0),
		"fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": _SLIME_IDLE_A, "d": 0.55}, {"t": _SLIME_IDLE_B, "d": 0.18}],
			"walk":  [{"t": _SLIME_WALK_A, "d": 0.18}, {"t": _SLIME_WALK_B, "d": 0.18}],
			"hurt":  [{"t": _SLIME_HURT, "d": 0.14}],
			"death": [{"t": _SLIME_DEAD_A, "d": 0.14, "mod": Color(0.45, 0.6, 0.4)},
					  {"t": _SLIME_DEAD_B, "d": 0.24, "mod": Color(0.18, 0.25, 0.16)}],
		},
	},
	"eye": {
		"font_size": 16, "line_sep": -4, "color": Color(0.92, 0.78, 0.98), "size": 1,
		"outline": 3, "box": Rect2(-22.0, -20.0, 44.0, 40.0),
		"fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": _EYE_IDLE_A, "d": 0.5}, {"t": _EYE_IDLE_B, "d": 0.5}],
			"walk":  [{"t": _EYE_WALK_A, "d": 0.3}, {"t": _EYE_WALK_B, "d": 0.3}],
			"hurt":  [{"t": _EYE_HURT, "d": 0.14}],
			"death": [{"t": _EYE_DEAD_A, "d": 0.14, "mod": Color(0.6, 0.55, 0.65)},
					  {"t": _EYE_DEAD_B, "d": 0.24, "mod": Color(0.2, 0.18, 0.22)}],
		},
	},
	"brute": {
		"font_size": 15, "line_sep": -5, "color": Color(0.86, 0.46, 0.36),
		"outline": 3, "box": Rect2(-28.0, -32.0, 56.0, 62.0),
		"fp_pixel_size": 0.016, "fp_outline_size": 13,
		"anims": {
			"idle":  [{"t": _BRUTE_IDLE_A, "d": 0.5}, {"t": _BRUTE_IDLE_B, "d": 0.5}],
			"walk":  [{"t": _BRUTE_WALK_A, "d": 0.26}, {"t": _BRUTE_WALK_B, "d": 0.26}],
			"hurt":  [{"t": _BRUTE_HURT, "d": 0.16}],
			"death": [{"t": _BRUTE_DEAD_A, "d": 0.16, "mod": Color(0.6, 0.5, 0.45)},
					  {"t": _BRUTE_DEAD_B, "d": 0.28, "mod": Color(0.22, 0.16, 0.14)}],
		},
	},

	# ── HIGH-FIDELITY DRAFTS (curated from "ascii art i like..txt") ──────
	# Large file-backed art, left-aligned (leading-whitespace layout). Static
	# idle for now — the fidelity is the point; animation comes after approval.
	# Death reuses the art with a dark tint + the driver's fade-out.
	"gnome": {
		"font_size": 15, "line_sep": -2, "color": Color(0.74, 0.62, 0.42), "size": 2,
		"outline": 3, "box": Rect2(-54.0, -110.0, 108.0, 200.0),
		"fp_pixel_size": 0.020, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/gnome.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/gnome.txt", "d": 0.5, "mod": Color(0.22, 0.18, 0.15)}],
		},
	},
	"ghost_big": {
		"font_size": 14, "line_sep": -2, "color": Color(0.80, 0.90, 1.0),
		"outline": 3, "box": Rect2(-70.0, -80.0, 150.0, 150.0),
		"fp_pixel_size": 0.018, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/ghost.txt", "d": 1.4},
					  {"file": "res://assets/ascii/sprites/ghost_blink.txt", "d": 0.18}],
			"hurt":  [{"file": "res://assets/ascii/sprites/ghost_hurt.txt", "d": 0.16}],
			"death": [{"file": "res://assets/ascii/sprites/ghost_hurt.txt", "d": 0.6, "mod": Color(0.25, 0.28, 0.35)}],
		},
	},
	"knight": {
		"font_size": 15, "line_sep": -2, "color": Color(0.72, 0.76, 0.86),
		"outline": 3, "box": Rect2(-64.0, -104.0, 128.0, 190.0),
		"fp_pixel_size": 0.020, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/knight.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/knight.txt", "d": 0.5, "mod": Color(0.22, 0.23, 0.28)}],
		},
	},
	"gollum": {
		"font_size": 13, "line_sep": -2, "color": Color(0.62, 0.72, 0.52),
		"outline": 3, "box": Rect2(-72.0, -140.0, 150.0, 260.0),
		"fp_pixel_size": 0.024, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/gollum.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/gollum.txt", "d": 0.5, "mod": Color(0.20, 0.24, 0.17)}],
		},
	},

	# ── MODULAR ARMORED HUMANOID (proof of concept) ──────────────────────
	# One base body (parts/humanoid_base.txt) + stamped weapon/shield parts =
	# many variants. Positions are a first pass — eyeball them in the gallery
	# and tell me the nudges. align:left because the base is grid-laid-out.
	"knight_sword": {
		"font_size": 15, "line_sep": -2, "color": Color(0.74, 0.78, 0.88),
		"outline": 3, "box": Rect2(-64.0, -104.0, 140.0, 200.0),
		"fp_pixel_size": 0.020, "fp_outline_size": 8,
		"anims": {
			"idle": [{"compose": {
				"base_file": "res://assets/ascii/sprites/parts/humanoid_base.txt",
				"layers": [{"art_file": "res://assets/ascii/sprites/parts/sword.txt", "row": 1, "col": 8}],
			}, "d": 1.0}],
		},
	},
	"knight_axe": {
		"font_size": 15, "line_sep": -2, "color": Color(0.80, 0.74, 0.66),
		"outline": 3, "box": Rect2(-64.0, -104.0, 140.0, 200.0),
		"fp_pixel_size": 0.020, "fp_outline_size": 8,
		"anims": {
			"idle": [{"compose": {
				"base_file": "res://assets/ascii/sprites/parts/humanoid_base.txt",
				"layers": [{"art_file": "res://assets/ascii/sprites/parts/axe.txt", "row": 1, "col": 8}],
			}, "d": 1.0}],
		},
	},
	"knight_shield": {
		"font_size": 15, "line_sep": -2, "color": Color(0.70, 0.80, 0.82),
		"outline": 3, "box": Rect2(-64.0, -104.0, 150.0, 200.0),
		"fp_pixel_size": 0.020, "fp_outline_size": 8,
		"anims": {
			"idle": [{"compose": {
				"base_file": "res://assets/ascii/sprites/parts/humanoid_base.txt",
				"layers": [
					{"art_file": "res://assets/ascii/sprites/parts/sword.txt", "row": 1, "col": 8},
					{"art_file": "res://assets/ascii/sprites/parts/shield.txt", "row": 4, "col": 0},
				],
			}, "d": 1.0}],
		},
	},
	# ── Bat (animated small flyer) ───────────────────────────────────────
	"bat": {   # 2-frame wing-flap (file-backed), small floating flyer
		"font_size": 16, "line_sep": -2, "color": Color(0.62, 0.55, 0.72), "size": 1, "flying": true,
		"outline": 3, "box": Rect2(-44.0, -26.0, 90.0, 52.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/bat1.txt", "d": 0.22},
					 {"file": "res://assets/ascii/sprites/bat2.txt", "d": 0.22}],
			"walk": [{"file": "res://assets/ascii/sprites/bat1.txt", "d": 0.11},
					 {"file": "res://assets/ascii/sprites/bat2.txt", "d": 0.11}],
			"hurt": [{"file": "res://assets/ascii/sprites/bat1.txt", "d": 0.14}],
			"death": [{"file": "res://assets/ascii/sprites/bat1.txt", "d": 0.4, "mod": Color(0.2, 0.16, 0.22)}],
		},
	},

	# ── Curated creatures (file-backed; "crop" strips the wide canvas margin) ──
	# Static idle for now (these are the high-fidelity beasts/figures); animate
	# the keepers after review.
	"centaur": {
		"font_size": 13, "line_sep": -2, "color": Color(0.80, 0.66, 0.5), "outline": 3, "size": 4,
		"crop": true, "box": Rect2(-90.0, -130.0, 190.0, 250.0),
		"fp_pixel_size": 0.024, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/centaur.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/centaur.txt", "d": 0.5, "mod": Color(0.22, 0.18, 0.14)}],
		},
	},
	"jester": {   # → Spiral Mage. Animates by y-axis flip (symmetric juggling).
		"font_size": 14, "line_sep": -2, "color": Color(0.85, 0.45, 0.7), "outline": 3,
		"crop": true, "box": Rect2(-70.0, -130.0, 150.0, 250.0),
		"fp_pixel_size": 0.022, "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/jester.txt", "d": 0.5},
					 {"file": "res://assets/ascii/sprites/jester.txt", "mirror": true, "d": 0.5}],
			"walk": [{"file": "res://assets/ascii/sprites/jester.txt", "d": 0.22},
					 {"file": "res://assets/ascii/sprites/jester.txt", "mirror": true, "d": 0.22}],
			"death": [{"file": "res://assets/ascii/sprites/jester.txt", "d": 0.5, "mod": Color(0.28, 0.16, 0.24)}],
		},
	},
	"lion": {
		"font_size": 12, "line_sep": -2, "color": Color(0.85, 0.7, 0.35), "outline": 3, "size": 4,
		"crop": true, "box": Rect2(-110.0, -90.0, 230.0, 180.0),
		"fp_pixel_size": 0.026, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/lion.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/lion.txt", "d": 0.5, "mod": Color(0.26, 0.2, 0.12)}],
		},
	},
	"minotaur": {   # → Charger. Animates by y-axis flip.
		"font_size": 13, "line_sep": -2, "color": Color(0.78, 0.45, 0.35), "outline": 3, "size": 4,
		"crop": true, "box": Rect2(-100.0, -120.0, 210.0, 240.0),
		"fp_pixel_size": 0.024, "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/minotaur.txt", "d": 0.5},
					 {"file": "res://assets/ascii/sprites/minotaur.txt", "mirror": true, "d": 0.5}],
			"walk": [{"file": "res://assets/ascii/sprites/minotaur.txt", "d": 0.22},
					 {"file": "res://assets/ascii/sprites/minotaur.txt", "mirror": true, "d": 0.22}],
			"death": [{"file": "res://assets/ascii/sprites/minotaur.txt", "d": 0.5, "mod": Color(0.26, 0.16, 0.13)}],
		},
	},
	"gryphon": {
		"font_size": 13, "line_sep": -2, "color": Color(0.78, 0.72, 0.5), "outline": 3, "size": 4, "flying": true,
		"crop": true, "box": Rect2(-90.0, -130.0, 190.0, 250.0),
		"fp_pixel_size": 0.024, "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/gryphon.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/gryphon.txt", "d": 0.5, "mod": Color(0.22, 0.2, 0.14)}],
		},
	},
	# ── Wired enemy art (curated) ────────────────────────────────────────
	"goblin": {   # → Chaser. Animates by flip (run cycle).
		"font_size": 13, "line_sep": -2, "color": Color(0.55, 0.85, 0.45), "size": 2,
		"outline": 3, "crop": true, "box": Rect2(-95.0, -75.0, 200.0, 160.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/goblin.txt", "d": 0.4},
					 {"file": "res://assets/ascii/sprites/goblin.txt", "mirror": true, "d": 0.4}],
			"walk": [{"file": "res://assets/ascii/sprites/goblin.txt", "d": 0.18},
					 {"file": "res://assets/ascii/sprites/goblin.txt", "mirror": true, "d": 0.18}],
			"death": [{"file": "res://assets/ascii/sprites/goblin.txt", "d": 0.5, "mod": Color(0.2, 0.25, 0.16)}],
		},
	},
	"tank_man": {   # → Tank.
		"font_size": 14, "line_sep": -2, "color": Color(0.75, 0.78, 0.85), "size": 4,
		"outline": 3, "crop": true, "box": Rect2(-80.0, -120.0, 170.0, 240.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/tank_man.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/tank_man.txt", "d": 0.5, "mod": Color(0.24, 0.25, 0.28)}],
		},
	},
	"jester_head": {   # → Beam Sweep (floating head; idle pulses idle↔attack).
		"font_size": 14, "line_sep": -2, "color": Color(0.95, 0.55, 0.85), "size": 2, "flying": true,
		"outline": 3, "crop": true, "box": Rect2(-80.0, -70.0, 170.0, 150.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/jester_head.txt", "d": 0.7},
					 {"file": "res://assets/ascii/sprites/jester_head_attack.txt", "d": 0.4}],
			"hurt": [{"file": "res://assets/ascii/sprites/jester_head_attack.txt", "d": 0.16}],
			"death": [{"file": "res://assets/ascii/sprites/jester_head.txt", "d": 0.5, "mod": Color(0.3, 0.18, 0.26)}],
		},
	},
	"fairy": {   # → Enchanter (replaces gnome). Floats.
		"font_size": 13, "line_sep": -2, "color": Color(0.95, 0.9, 0.6), "size": 1, "flying": true,
		"outline": 3, "crop": true, "box": Rect2(-80.0, -130.0, 170.0, 250.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/fairy.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/fairy.txt", "d": 0.5, "mod": Color(0.28, 0.26, 0.16)}],
		},
	},
	"boss_brute": {   # → Boss (Brute).
		"font_size": 12, "line_sep": -2, "color": Color(0.85, 0.5, 0.4), "size": 4,
		"outline": 3, "crop": true, "box": Rect2(-95.0, -140.0, 200.0, 270.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/brute_boss.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/brute_boss.txt", "d": 0.5, "mod": Color(0.26, 0.16, 0.13)}],
		},
	},
	# ── Gallery drafts (not yet wired) ───────────────────────────────────
	"spider2": {   # ornate long-legged spider; animates by flip (reflection walk).
		"font_size": 13, "line_sep": -2, "color": Color(0.6, 0.7, 0.55), "size": 3,
		"outline": 3, "crop": true, "box": Rect2(-95.0, -120.0, 200.0, 240.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/spider2.txt", "d": 0.45},
					 {"file": "res://assets/ascii/sprites/spider2.txt", "mirror": true, "d": 0.45}],
			"walk": [{"file": "res://assets/ascii/sprites/spider2.txt", "d": 0.2},
					 {"file": "res://assets/ascii/sprites/spider2.txt", "mirror": true, "d": 0.2}],
			"death": [{"file": "res://assets/ascii/sprites/spider2.txt", "d": 0.5, "mod": Color(0.2, 0.24, 0.18)}],
		},
	},
	"swimmer": {   # diving/swimming figure; animates by y-axis flip.
		"font_size": 12, "line_sep": -2, "color": Color(0.5, 0.78, 0.88), "size": 2,
		"outline": 3, "crop": true, "box": Rect2(-130.0, -90.0, 270.0, 190.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/swimmer.txt", "d": 0.5},
					 {"file": "res://assets/ascii/sprites/swimmer.txt", "mirror": true, "d": 0.5}],
			"walk": [{"file": "res://assets/ascii/sprites/swimmer.txt", "d": 0.22},
					 {"file": "res://assets/ascii/sprites/swimmer.txt", "mirror": true, "d": 0.22}],
			"death": [{"file": "res://assets/ascii/sprites/swimmer.txt", "d": 0.5, "mod": Color(0.18, 0.28, 0.32)}],
		},
	},
	"eye2": {   # ornate floating eye
		"font_size": 14, "line_sep": -2, "color": Color(0.7, 0.6, 0.85), "size": 1, "flying": true,
		"outline": 3, "crop": true, "box": Rect2(-90.0, -75.0, 190.0, 160.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/eye2.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/eye2.txt", "d": 0.5, "mod": Color(0.24, 0.2, 0.3)}],
		},
	},
	"cute_ghost": {   # block-character (██ ░░) cute ghost; floating
		"font_size": 9, "line_sep": -3, "color": Color(0.82, 0.86, 0.95), "size": 2, "flying": true,
		"outline": 2, "crop": true, "box": Rect2(-110.0, -110.0, 230.0, 230.0), "fp_outline_size": 6,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/cute_ghost.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/cute_ghost.txt", "d": 0.5, "mod": Color(0.28, 0.3, 0.36)}],
		},
	},
	"reflector": {   # → Reflector. Floating arcane mirror-mage.
		"font_size": 11, "line_sep": -2, "color": Color(0.7, 0.85, 0.95), "size": 3, "flying": true,
		"outline": 3, "crop": true, "box": Rect2(-150.0, -110.0, 310.0, 230.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/reflector.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/reflector.txt", "d": 0.5, "mod": Color(0.22, 0.27, 0.3)}],
		},
	},
	"bone_drake": {   # → Bone Drake. Tall skeletal dragon.
		"font_size": 11, "line_sep": -2, "color": Color(0.88, 0.86, 0.78), "size": 4,
		"outline": 3, "crop": true, "box": Rect2(-130.0, -150.0, 270.0, 300.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/bone_drake.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/bone_drake.txt", "d": 0.5, "mod": Color(0.3, 0.29, 0.24)}],
		},
	},
	"shooter": {   # → Shooter. Grinning dragon-skull turret.
		"font_size": 11, "line_sep": -2, "color": Color(0.7, 0.82, 0.6), "size": 3,
		"outline": 3, "crop": true, "box": Rect2(-150.0, -85.0, 310.0, 180.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/shooter.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/shooter.txt", "d": 0.5, "mod": Color(0.24, 0.28, 0.2)}],
		},
	},
	"ice_sentinel": {   # → Frost Sentinel. Tall ornate ice golem.
		"font_size": 11, "line_sep": -2, "color": Color(0.7, 0.92, 1.0), "size": 4,
		"outline": 3, "crop": true, "box": Rect2(-110.0, -150.0, 230.0, 300.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/ice_sentinel.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/ice_sentinel.txt", "d": 0.5, "mod": Color(0.3, 0.4, 0.45)}],
		},
	},
	"grenadier": {   # → Grenadier. Animates by y-axis flip (rotate on axis).
		"font_size": 12, "line_sep": -2, "color": Color(0.7, 0.78, 0.5), "size": 2,
		"outline": 3, "crop": true, "box": Rect2(-110.0, -130.0, 230.0, 260.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/grenadier.txt", "d": 0.5},
					 {"file": "res://assets/ascii/sprites/grenadier.txt", "mirror": true, "d": 0.5}],
			"walk": [{"file": "res://assets/ascii/sprites/grenadier.txt", "d": 0.22},
					 {"file": "res://assets/ascii/sprites/grenadier.txt", "mirror": true, "d": 0.22}],
			"death": [{"file": "res://assets/ascii/sprites/grenadier.txt", "d": 0.5, "mod": Color(0.28, 0.3, 0.2)}],
		},
	},
	"bomber": {   # → Bomber. Big spherical bomb with a lit fuse.
		"font_size": 11, "line_sep": -2, "color": Color(0.8, 0.55, 0.45), "size": 3,
		"outline": 3, "crop": true, "box": Rect2(-130.0, -130.0, 270.0, 260.0), "fp_outline_size": 8,
		"anims": {
			"idle":  [{"file": "res://assets/ascii/sprites/bomber.txt", "d": 1.0}],
			"death": [{"file": "res://assets/ascii/sprites/bomber.txt", "d": 0.5, "mod": Color(0.3, 0.2, 0.16)}],
		},
	},
	"archer": {   # → Archer. 2-frame bow-draw idle.
		"font_size": 13, "line_sep": -2, "color": Color(0.6, 0.78, 0.55), "size": 2,
		"outline": 3, "crop": true, "box": Rect2(-90.0, -110.0, 190.0, 220.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/archer1.txt", "d": 0.55},
					 {"file": "res://assets/ascii/sprites/archer2.txt", "d": 0.55}],
			"walk": [{"file": "res://assets/ascii/sprites/archer1.txt", "d": 0.25},
					 {"file": "res://assets/ascii/sprites/archer2.txt", "d": 0.25}],
			"death": [{"file": "res://assets/ascii/sprites/archer1.txt", "d": 0.5, "mod": Color(0.24, 0.3, 0.22)}],
		},
	},
	"spawner": {   # → Spawner. 2-frame portal with a flickering eye.
		"font_size": 9, "line_sep": -2, "color": Color(0.7, 0.6, 0.92), "size": 4, "flying": true,
		"outline": 3, "crop": true, "box": Rect2(-150.0, -160.0, 310.0, 320.0), "fp_outline_size": 8,
		"anims": {
			"idle": [{"file": "res://assets/ascii/sprites/spawner1.txt", "d": 0.7},
					 {"file": "res://assets/ascii/sprites/spawner2.txt", "d": 0.7}],
			"death": [{"file": "res://assets/ascii/sprites/spawner1.txt", "d": 0.5, "mod": Color(0.26, 0.22, 0.34)}],
		},
	},
	# ── Remaining enemies (current in-game art, in the gallery for review) ────
	"wizard": {   # → Enemy Wizard
		"font_size": 15, "line_sep": -4, "color": Color(0.70, 0.50, 0.95), "size": 3,
		"outline": 3, "box": Rect2(-44.0, -48.0, 90.0, 96.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": "   >\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|", "d": 0.6},
					 {"t": "   >\n__/_\\__\n (*3*)\n /)V(\\|\n /___\\|", "d": 0.6}],
			"death": [{"t": "   >\n__/_\\__\n (x_x)\n /)V(\\|\n /___\\|", "d": 0.5, "mod": Color(0.32, 0.22, 0.4)}],
		},
	},
	"magma_slug": {   # → Magma Slug
		"font_size": 16, "line_sep": -4, "color": Color(1.0, 0.5, 0.2), "size": 2,
		"outline": 3, "box": Rect2(-30.0, -28.0, 60.0, 56.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": " ()(\n((O))\n ))( ", "d": 0.55}, {"t": " )()\n((o))\n )(( ", "d": 0.55}],
			"death": [{"t": " )()\n((o))\n )(( ", "d": 0.5, "mod": Color(0.35, 0.18, 0.08)}],
		},
	},
	"boss_architect": {   # → The Architect (boss)
		"font_size": 18, "line_sep": -4, "color": Color(0.5, 0.8, 0.9), "size": 4,
		"outline": 3, "box": Rect2(-30.0, -30.0, 60.0, 60.0), "fp_pixel_size": 0.02, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": ".+.\n>*<\n.+.", "d": 0.5}, {"t": "-+-\n>X<\n-+-", "d": 0.5}],
			"death": [{"t": "-+-\n>X<\n-+-", "d": 0.5, "mod": Color(0.2, 0.3, 0.34)}],
		},
	},
	"boss_devourer": {   # → The Devourer (boss)
		"font_size": 18, "line_sep": -4, "color": Color(1.0, 0.45, 0.10), "size": 4,
		"outline": 3, "box": Rect2(-34.0, -26.0, 70.0, 56.0), "fp_pixel_size": 0.02, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": "/(O)\\\n \\m/ ", "d": 0.5}, {"t": "/(o)\\\n /M\\ ", "d": 0.5}],
			"death": [{"t": "/(o)\\\n /M\\ ", "d": 0.5, "mod": Color(0.35, 0.16, 0.05)}],
		},
	},
	"boss_lich": {   # → The Lich (boss)
		"font_size": 18, "line_sep": -4, "color": Color(0.55, 1.0, 0.55), "size": 4,
		"outline": 3, "box": Rect2(-30.0, -30.0, 60.0, 60.0), "fp_pixel_size": 0.02, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": " /=\\ \n |O| \n /^\\ ", "d": 0.5}, {"t": " /=\\ \n |o| \n /v\\ ", "d": 0.5}],
			"death": [{"t": " /=\\ \n |o| \n /v\\ ", "d": 0.5, "mod": Color(0.22, 0.4, 0.22)}],
		},
	},
	"boss_magma": {   # → Magma Tyrant (boss)
		"font_size": 18, "line_sep": -4, "color": Color(1.0, 0.45, 0.10), "size": 4,
		"outline": 3, "box": Rect2(-32.0, -30.0, 66.0, 60.0), "fp_pixel_size": 0.02, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": " /^\\\n[#X#]\n /|\\", "d": 0.5}, {"t": " \\^/\n(#X#)\n /|\\", "d": 0.5}],
			"death": [{"t": " \\^/\n(#X#)\n /|\\", "d": 0.5, "mod": Color(0.35, 0.16, 0.05)}],
		},
	},
	"boss_wraith": {   # → The Wraith (boss)
		"font_size": 18, "line_sep": -4, "color": Color(0.7, 0.1, 1.0), "size": 3,
		"outline": 3, "box": Rect2(-26.0, -24.0, 52.0, 48.0), "fp_pixel_size": 0.018, "fp_outline_size": 10,
		"anims": {
			"idle": [{"t": "/W\\\n ~~", "d": 0.4}, {"t": "\\W/\n~~~", "d": 0.4}],
			"death": [{"t": "\\W/\n~~~", "d": 0.5, "mod": Color(0.28, 0.06, 0.4)}],
		},
	},
	# ── Objects / interactables (current in-game art, for gallery reference) ──
	"shrine": {   # → Shrine
		"font_size": 16, "line_sep": -4, "color": Color(0.75, 0.95, 1.0), "size": 2,
		"outline": 3, "box": Rect2(-26.0, -26.0, 52.0, 52.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": " /^\\ \n[ + ]\n \\v/ ", "d": 1.0}],
			"death": [{"t": " ,_, \n[ . ]\n '_' ", "d": 0.5, "mod": Color(0.4, 0.4, 0.5)}],
		},
	},
	"loot_bag": {   # → Loot Bag
		"font_size": 18, "line_sep": -4, "color": Color(0.85, 0.55, 0.15), "size": 1,
		"outline": 3, "box": Rect2(-24.0, -20.0, 48.0, 40.0), "fp_pixel_size": 0.011, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": ",---,\n)___(", "d": 1.0}],
			"death": [{"t": ",---,\n)___(", "d": 0.5, "mod": Color(0.3, 0.2, 0.08)}],
		},
	},
	"enchant_table": {   # → Enchant Table
		"font_size": 16, "line_sep": -4, "color": Color(0.85, 0.45, 1.0), "size": 2,
		"outline": 3, "box": Rect2(-26.0, -26.0, 52.0, 52.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": " ___ \n[✦✦✦]\n |_| ", "d": 1.0}],
			"death": [{"t": " ___ \n[✦✦✦]\n |_| ", "d": 0.5, "mod": Color(0.3, 0.16, 0.36)}],
		},
	},
	"mine": {   # → Mine (idle unarmed, walk = arming pulse)
		"font_size": 16, "line_sep": -4, "color": Color(0.9, 0.9, 0.9), "size": 1,
		"outline": 3, "box": Rect2(-26.0, -26.0, 52.0, 52.0), "fp_pixel_size": 0.011, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": " ,_, \n( . )\n '_' ", "d": 1.0}],
			"walk":  [{"t": " \\!/ \n(>X<)\n /_\\ ", "d": 0.18}, {"t": " -!- \n[#X#]\n /_\\ ", "d": 0.18}],
			"death": [{"t": " -!- \n[#X#]\n /_\\ ", "d": 0.5, "mod": Color(0.45, 0.2, 0.1)}],
		},
	},
	"training_dummy": {   # → Training Dummy
		"font_size": 16, "line_sep": -4, "color": Color(0.95, 0.82, 0.55), "size": 2,
		"outline": 3, "box": Rect2(-26.0, -26.0, 52.0, 52.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {
			"idle":  [{"t": "[O_O]\n |Y| \n /_\\ ", "d": 1.0}],
			"death": [{"t": "[x_x]\n |Y| \n /_\\ ", "d": 0.5, "mod": Color(0.4, 0.32, 0.2)}],
		},
	},
	"exit_portal": {   # → Exit Portal
		"font_size": 13, "line_sep": -3, "color": Color(0.4, 1.0, 0.7), "size": 3,
		"outline": 3, "box": Rect2(-60.0, -44.0, 124.0, 90.0), "fp_pixel_size": 0.012, "fp_outline_size": 9,
		"anims": {
			"idle": [{"t": "  ,-^^^-.  \n /  ###  \\ \n|>> [EX] >>|\n \\  ###  / \n  `-vvv-'  ", "d": 0.4},
					 {"t": "  ,-^^^-.  \n /  ###  \\ \n|>> [XE] >>|\n \\  ###  / \n  `-vvv-'  ", "d": 0.4}],
			"death": [{"t": "  ,-^^^-.  \n /  ###  \\ \n|>> [==] >>|\n \\  ###  / \n  `-vvv-'  ", "d": 0.5, "mod": Color(0.18, 0.4, 0.3)}],
		},
	},
	"portal": {   # → Portal
		"font_size": 13, "line_sep": -3, "color": Color(0.6, 0.8, 1.0), "size": 3,
		"outline": 3, "box": Rect2(-60.0, -44.0, 124.0, 90.0), "fp_pixel_size": 0.012, "fp_outline_size": 9,
		"anims": {
			"idle": [{"t": "  ,-===-.  \n /  >>>  \\ \n|>> [<>] >>|\n \\  >>>  / \n  `-===-'  ", "d": 0.4},
					 {"t": "  ,-===-.  \n /  >>>  \\ \n|>> [><] >>|\n \\  >>>  / \n  `-===-'  ", "d": 0.4}],
			"death": [{"t": "  ,-===-.  \n /  >>>  \\ \n|>> [==] >>|\n \\  >>>  / \n  `-===-'  ", "d": 0.5, "mod": Color(0.24, 0.32, 0.4)}],
		},
	},
	# Single-glyph objects — minimal entries so they still show in the gallery.
	"teleporter": {
		"font_size": 22, "line_sep": -4, "color": Color(0.30, 0.65, 1.0), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "O", "d": 1.0}]},
	},
	"descend_portal": {
		"font_size": 22, "line_sep": -4, "color": Color(0.65, 0.45, 1.0), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "v", "d": 1.0}]},
	},
	"gold_pickup": {
		"font_size": 22, "line_sep": -4, "color": Color(1.0, 0.95, 0.30), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "$", "d": 1.0}]},
	},
	"bank": {
		"font_size": 22, "line_sep": -4, "color": Color(0.55, 1.0, 0.55), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "B", "d": 1.0}]},
	},
	"shop": {
		"font_size": 22, "line_sep": -4, "color": Color(0.55, 1.0, 0.55), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "S", "d": 1.0}]},
	},
	"quest_board": {
		"font_size": 22, "line_sep": -4, "color": Color(1.0, 0.95, 0.45), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "!", "d": 1.0}]},
	},
	"reroller": {
		"font_size": 22, "line_sep": -4, "color": Color(0.95, 0.65, 1.0), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "?", "d": 1.0}]},
	},
	"sell_chest": {
		"font_size": 22, "line_sep": -4, "color": Color(0.95, 0.65, 0.30), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "[", "d": 1.0}]},
	},
	"spike_trap": {
		"font_size": 22, "line_sep": -4, "color": Color(0.9, 0.5, 0.5), "size": 1,
		"outline": 3, "box": Rect2(-18.0, -18.0, 36.0, 36.0), "fp_pixel_size": 0.012, "fp_outline_size": 10,
		"anims": {"idle": [{"t": "^", "d": 1.0}]},
	},
}

static var _file_cache: Dictionary = {}

# Per-sprite tuning chosen in the gallery (size tier + vertical height_offset),
# persisted here so the values picked while previewing carry over to the actual
# enemies in-game and across runs. Merged over the SPRITES defaults by meta().
const OVERRIDES_PATH := "res://assets/ascii/sprite_overrides.json"
static var _overrides: Dictionary = {}
static var _overrides_loaded: bool = false

static func _ensure_overrides() -> void:
	if _overrides_loaded:
		return
	_overrides_loaded = true
	if not FileAccess.file_exists(OVERRIDES_PATH):
		return
	var f := FileAccess.open(OVERRIDES_PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_overrides = data

static func has(key: String) -> bool:
	return SPRITES.has(key)

static func meta(key: String) -> Dictionary:
	_ensure_overrides()
	var base: Dictionary = SPRITES.get(key, {}) as Dictionary
	if base.is_empty():
		return {}
	var ov: Dictionary = _overrides.get(key, {}) as Dictionary
	if ov.is_empty():
		return base
	# Shallow-copy the top level (cheap) and lay the tuned fields on top. The
	# nested "anims" array is shared by reference — fine, overrides never touch it.
	var merged: Dictionary = base.duplicate(false)
	for k in ov:
		var v: Variant = ov[k]
		# Colour is persisted as an "rrggbb" html string (JSON has no Color);
		# rebuild a Color so consumers (driver base_color, 2D label, FP) get the
		# type they expect.
		if k == "color" and v is String:
			v = Color(v as String)
		merged[k] = v
	return merged

# Records a tuned field (e.g. "size", "height_offset") for a sprite. Call
# save_overrides() to persist to disk.
static func set_override(key: String, field: String, value: Variant) -> void:
	_ensure_overrides()
	var ov: Dictionary = _overrides.get(key, {}) as Dictionary
	ov[field] = value
	_overrides[key] = ov

static func override_value(key: String, field: String, default_value: Variant) -> Variant:
	_ensure_overrides()
	return (_overrides.get(key, {}) as Dictionary).get(field, default_value)

static func save_overrides() -> void:
	_ensure_overrides()
	var f := FileAccess.open(OVERRIDES_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("AsciiSprites: could not write " + OVERRIDES_PATH)
		return
	f.store_string(JSON.stringify(_overrides, "\t"))

static func anims(key: String) -> Dictionary:
	return (SPRITES.get(key, {}) as Dictionary).get("anims", {}) as Dictionary

# Returns the frames for a state, resolving any frame that points at a .txt
# file (large hand-curated art is stored as raw files to avoid escaping every
# backslash). Resolved frames get their loaded text in "t" so callers (driver,
# gallery) treat file-backed and inline frames identically.
static func frames(key: String, state: String) -> Array:
	var raw: Array = anims(key).get(state, []) as Array
	var out: Array = []
	for f in raw:
		var fr: Dictionary = f as Dictionary
		var text: String = ""
		if fr.has("t"):
			text = String(fr["t"])
		elif fr.has("file"):
			text = _load_file(String(fr["file"]))
		elif fr.has("compose"):
			# Modular sprite: a base body with weapon/armor parts stamped on.
			# base/art may be inline strings ("base"/"art") or file-backed
			# ("base_file"/"art_file") so the art needs no backslash escaping.
			var spec: Dictionary = fr["compose"] as Dictionary
			var base: String = String(spec["base"]) if spec.has("base") \
				else _load_file(String(spec.get("base_file", "")))
			var layers: Array = []
			for lr in (spec.get("layers", []) as Array):
				var ld: Dictionary = (lr as Dictionary).duplicate()
				if ld.has("art_file") and not ld.has("art"):
					ld["art"] = _load_file(String(ld["art_file"]))
				layers.append(ld)
			text = AsciiCompositor.compose(base, layers)
		# Curated art often carries a big common left margin (it was laid out
		# centred on a wide canvas). Opt-in crop strips that shared indent +
		# blank edges so the sprite isn't tiny and offset.
		if bool(meta(key).get("crop", false)):
			text = crop_block(text)
		if fr.has("mirror"):
			text = mirror_block(text)
		# Pad every line to the block's max width. With equal-width lines,
		# center alignment (used by the 2D Label AND the FP billboard) shifts
		# each line identically, so the column grid is preserved instead of
		# short lines drifting toward center. A fresh dict avoids mutating the
		# const SPRITES table.
		var nd: Dictionary = fr.duplicate()
		nd["t"] = pad_block(text)
		out.append(nd)
	return out

# Horizontal mirror of a block — reverses each line and swaps directional
# glyph pairs. Lets a sprite animate by flipping (run cycle, scuttle) instead
# of hand-drawn frames: idle = [art, {..., "mirror": true}].
const _MIRROR_MAP := {
	"(": ")", ")": "(", "[": "]", "]": "[", "{": "}", "}": "{",
	"<": ">", ">": "<", "/": "\\", "\\": "/", "d": "b", "b": "d", "p": "q", "q": "p",
}
static func mirror_block(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var w: int = 0
	for l in lines:
		w = maxi(w, l.length())
	var out: PackedStringArray = []
	for l in lines:
		var padded: String = l.rpad(w)
		var rev: String = ""
		for i in range(padded.length() - 1, -1, -1):
			var c: String = padded[i]
			rev += String(_MIRROR_MAP.get(c, c))
		out.append(rev)
	return "\n".join(out)

# Strips fully-blank top/bottom rows and the largest common leading-space
# indent shared by all non-blank rows. Preserves the internal column grid
# (every row loses the SAME number of leading chars).
static func crop_block(text: String) -> String:
	var lines: Array = Array(text.split("\n"))
	while not lines.is_empty() and String(lines[0]).strip_edges() == "":
		lines.pop_front()
	while not lines.is_empty() and String(lines[lines.size() - 1]).strip_edges() == "":
		lines.pop_back()
	if lines.is_empty():
		return ""
	var min_lead: int = 1 << 30
	for l in lines:
		var s: String = l
		if s.strip_edges() == "":
			continue
		min_lead = mini(min_lead, s.length() - s.lstrip(" ").length())
	if min_lead <= 0 or min_lead >= (1 << 30):
		return "\n".join(lines)
	var out: Array = []
	for l in lines:
		var s2: String = l
		out.append(s2.substr(min_lead) if s2.length() >= min_lead else "")
	return "\n".join(out)

# Right-pads every line with spaces to the longest line's width so the block
# is a true rectangle. Essential for center-aligned multi-line ASCII art.
static func pad_block(text: String) -> String:
	var lines: PackedStringArray = text.split("\n")
	var w: int = 0
	for l in lines:
		w = maxi(w, l.length())
	var out: PackedStringArray = []
	for l in lines:
		out.append(l.rpad(w))
	return "\n".join(out)

static func _load_file(path: String) -> String:
	if not _file_cache.has(path):
		if FileAccess.file_exists(path):
			# Trim a single trailing newline so the file's terminator doesn't
			# add a phantom blank row under the art.
			_file_cache[path] = FileAccess.get_file_as_string(path).rstrip("\n")
		else:
			_file_cache[path] = "(missing %s)" % path
	return _file_cache[path] as String

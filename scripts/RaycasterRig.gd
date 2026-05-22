extends CanvasLayer

# Option B: Pure software raycaster. Every frame, casts one ray per screen
# column against World._grid using DDA, fills a character buffer with wall
# slabs (per-distance glyph ramp), then projects registered entities onto
# the column range matching their angular position. The whole view is one
# monospace Label whose text is rebuilt each frame.
#
# No 3D pipeline, no shader — output is unambiguously a grid of ASCII cells.

const TILE_PX: float = 32.0
const COLS: int = 140
const ROWS: int = 44
const FOV: float = 1.20   # ~69° — close to classic Doom
# Wall density ramp by distance bucket. Bright/dense near, fade far.
const RAMP := "@#%xo+:-. "

var _label: RichTextLabel = null
var _grid: Array = []
var _grid_w: int = 0
var _grid_h: int = 0
var _entities: Dictionary = {}   # body InstanceID → {body, glyph, color}

func _ready() -> void:
	layer = 1
	visible = false
	_build_label()

func _build_label() -> void:
	# Background plate so the ASCII pops against a dark surface even when
	# the row mostly contains spaces.
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 1.0)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_label = RichTextLabel.new()
	_label.anchor_right = 1.0
	_label.anchor_bottom = 1.0
	_label.bbcode_enabled = true
	_label.fit_content = false
	_label.scroll_active = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_override("normal_font", MonoFont.get_font())
	_label.add_theme_font_size_override("normal_font_size", 14)
	_label.add_theme_color_override("default_color", Color(0.85, 0.85, 0.92))
	_label.add_theme_constant_override("line_separation", -2)
	add_child(_label)

func set_grid(grid: Array, grid_w: int, grid_h: int) -> void:
	_grid = grid
	_grid_w = grid_w
	_grid_h = grid_h

func register_entity(body: Node2D, glyph: String = "D", color: Color = Color(1.0, 0.4, 0.4)) -> void:
	if not is_instance_valid(body):
		return
	var key := body.get_instance_id()
	_entities[key] = {"body": body, "glyph": glyph, "color": color}

func unregister_entity(body: Node2D) -> void:
	if not is_instance_valid(body):
		return
	_entities.erase(body.get_instance_id())

func clear_entities() -> void:
	# Drop every entry so a rig that's been inactive doesn't crash when
	# re-activated against stale (now-freed) bodies. World calls this on
	# mode toggle before bulk-re-registering live entities.
	_entities.clear()

func _process(_delta: float) -> void:
	if not visible or _grid.is_empty():
		return
	var player: Node = get_tree().get_first_node_in_group("player")
	if not is_instance_valid(player) or not (player is Node2D):
		return
	var pp: Vector2 = (player as Node2D).global_position
	# Convert pixels to tile coordinates so DDA can walk integer cells.
	var px_tile: float = pp.x / TILE_PX
	var py_tile: float = pp.y / TILE_PX
	var aim: Vector2 = Vector2.RIGHT
	if player.has_method("get_aim_direction"):
		aim = player.get_aim_direction()
	var heading: float = atan2(aim.y, aim.x)

	# Cast COLS rays — each fills a column with a wall slab.
	# wall_dist[c] = perpendicular distance in tile units (or 0 if no hit)
	var wall_dist := PackedFloat32Array()
	wall_dist.resize(COLS)
	var wall_dist_max: float = float(maxi(_grid_w, _grid_h)) * 2.0
	for c in COLS:
		var t: float = (float(c) / float(COLS - 1)) - 0.5   # -0.5..0.5
		var ray_ang: float = heading + t * FOV
		var rdx: float = cos(ray_ang)
		var rdy: float = sin(ray_ang)
		var dist: float = _dda(px_tile, py_tile, rdx, rdy, wall_dist_max)
		# Perpendicular distance (fisheye correction).
		wall_dist[c] = dist * cos(t * FOV)

	# Build the character buffer.
	var lines: PackedStringArray = PackedStringArray()
	lines.resize(ROWS)
	# Pre-fill rows with spaces.
	var blank: String = " ".repeat(COLS)
	for r in ROWS:
		lines[r] = blank
	# Per-column wall slabs.
	var half_rows: float = float(ROWS) * 0.5
	for c in COLS:
		var d: float = wall_dist[c]
		if d <= 0.01:
			# No hit — leave column blank (will look like distant void).
			continue
		var slab_h: float = clampf(float(ROWS) / d, 1.0, float(ROWS))
		var slab_top: int = int(round(half_rows - slab_h * 0.5))
		var slab_bot: int = int(round(half_rows + slab_h * 0.5))
		slab_top = clampi(slab_top, 0, ROWS - 1)
		slab_bot = clampi(slab_bot, 0, ROWS - 1)
		var glyph: String = _wall_glyph_for_distance(d)
		for r in range(slab_top, slab_bot + 1):
			lines[r] = _set_char(lines[r], c, glyph)
		# Floor — dotted band below the slab. Closer = denser dots.
		for r in range(slab_bot + 1, ROWS):
			if r % 2 == 0:
				lines[r] = _set_char(lines[r], c, ".")
		# Ceiling — empty (looks like a vault overhead).

	# Project entities onto columns.
	var sin_h: float = sin(-heading)
	var cos_h: float = cos(-heading)
	# Collect stale keys first — modifying _entities during iteration would
	# either silently skip elements or crash depending on engine version.
	var stale: Array = []
	for key in _entities.keys():
		var entry: Dictionary = _entities[key]
		# Variant first so a freed-since-last-frame body doesn't crash the
		# typed-assignment path.
		var body_v: Variant = entry["body"]
		if not is_instance_valid(body_v) or not (body_v is Node2D):
			stale.append(key)
			continue
		var body: Node2D = body_v as Node2D
		var bp: Vector2 = body.global_position
		var ex: float = bp.x / TILE_PX - px_tile
		var ey: float = bp.y / TILE_PX - py_tile
		# Rotate into camera-space.
		var cam_x: float = cos_h * ex - sin_h * ey
		var cam_y: float = sin_h * ex + cos_h * ey
		# Near-cull — entities right next to / inside the camera (e.g. a
		# projectile that just spawned at the player position) would
		# otherwise smear across half the screen. 0.6 tiles ≈ 20 px feels
		# right for a "barrel of the gun" exclusion zone.
		if cam_x <= 0.6:
			continue
		# Angle relative to heading: atan2(cam_y, cam_x).
		var ang: float = atan2(cam_y, cam_x)
		if absf(ang) > FOV * 0.5:
			continue
		var col: int = int(round((ang / FOV + 0.5) * float(COLS - 1)))
		col = clampi(col, 0, COLS - 1)
		# Z-test against wall column distance.
		if wall_dist[col] > 0.01 and wall_dist[col] < cam_x:
			continue
		# Sprite size scales inversely with depth. Max height capped at
		# ROWS * 0.25 so even a body-glyph close up only fills a quarter
		# of the screen vertically (used to be 0.5 — too dominating).
		var sprite_h: float = clampf(6.0 / cam_x, 1.0, float(ROWS) * 0.25)
		var sprite_r: int = int(round(half_rows + sprite_h * 0.35))
		sprite_r = clampi(sprite_r, 0, ROWS - 1)
		# Live glyph from the body's AsciiChar child (carries 2-frame
		# enemy animations + status text). Fall back to the stored glyph
		# from registration for entities without an AsciiChar.
		var glyph: String = entry["glyph"]
		var ascii_child: Node = body.get_node_or_null("AsciiChar")
		if ascii_child != null and ascii_child is Label:
			var al: Label = ascii_child as Label
			if al.text != "":
				# Take only the first non-whitespace character — multi-line
				# enemy labels (e.g. "d\n_") would otherwise blow up the
				# single-column splat.
				var t: String = al.text.strip_edges()
				if t.length() > 0:
					glyph = t.substr(0, 1)
		# Multi-column splat for nearer enemies so they read as a body.
		# Small glyphs (projectiles, sparks) stay one column wide.
		var is_small_g: bool = glyph in ["*", "o", ".", "+", ","]
		var width: int = 1 if is_small_g else maxi(1, int(round(sprite_h * 0.4)))
		for dc in range(-width / 2, width / 2 + 1):
			var tc: int = col + dc
			if tc < 0 or tc >= COLS:
				continue
			lines[sprite_r] = _set_char(lines[sprite_r], tc, glyph)

	# Drop stale entity entries collected during projection.
	for k in stale:
		_entities.erase(k)
	# Crosshair at screen center so the player can see where shots will go.
	var crosshair_r: int = int(half_rows)
	var crosshair_c: int = COLS / 2
	if crosshair_r >= 0 and crosshair_r < ROWS:
		lines[crosshair_r] = _set_char(lines[crosshair_r], crosshair_c, "+")
		if crosshair_r > 0:
			lines[crosshair_r - 1] = _set_char(lines[crosshair_r - 1], crosshair_c, "|")
		if crosshair_r < ROWS - 1:
			lines[crosshair_r + 1] = _set_char(lines[crosshair_r + 1], crosshair_c, "|")
		if crosshair_c > 0:
			lines[crosshair_r] = _set_char(lines[crosshair_r], crosshair_c - 1, "-")
		if crosshair_c < COLS - 1:
			lines[crosshair_r] = _set_char(lines[crosshair_r], crosshair_c + 1, "-")

	# Join and assign. BBCode color tags would be nice but per-char tagging
	# bloats the string heavily; v1 ships in the default text color.
	_label.text = "\n".join(lines)

func _set_char(s: String, idx: int, c: String) -> String:
	# GDScript strings are immutable; cheap concat is fine at COLS×ROWS scale.
	if idx < 0 or idx >= s.length():
		return s
	return s.substr(0, idx) + c + s.substr(idx + 1)

func _wall_glyph_for_distance(d: float) -> String:
	# Map distance (in tile units) to a ramp index. ~0 → '@' (densest);
	# far → '.' (sparse). Clamped against the ramp length.
	var max_d: float = 30.0
	var t: float = clampf(d / max_d, 0.0, 1.0)
	var idx: int = clampi(int(round(t * float(RAMP.length() - 1))), 0, RAMP.length() - 1)
	return RAMP[idx]

# DDA grid traversal: walk integer cells from (px, py) in direction (rdx, rdy)
# until we hit a WALL or exceed max_dist. Returns the perpendicular distance
# in tile units, or 0 if no wall was hit.
func _dda(px: float, py: float, rdx: float, rdy: float, max_dist: float) -> float:
	var map_x: int = int(floor(px))
	var map_y: int = int(floor(py))
	# Avoid divide-by-zero — Float.INF wherever the direction is flat.
	var delta_x: float = 1.0e30 if rdx == 0.0 else absf(1.0 / rdx)
	var delta_y: float = 1.0e30 if rdy == 0.0 else absf(1.0 / rdy)
	var step_x: int = 1 if rdx > 0.0 else -1
	var step_y: int = 1 if rdy > 0.0 else -1
	var side_x: float = (float(map_x) + 1.0 - px) * delta_x if rdx > 0.0 else (px - float(map_x)) * delta_x
	var side_y: float = (float(map_y) + 1.0 - py) * delta_y if rdy > 0.0 else (py - float(map_y)) * delta_y

	var dist: float = 0.0
	while dist < max_dist:
		var side_hit: int
		if side_x < side_y:
			dist = side_x
			side_x += delta_x
			map_x += step_x
			side_hit = 0
		else:
			dist = side_y
			side_y += delta_y
			map_y += step_y
			side_hit = 1
		# Bounds + wall check.
		if map_x < 0 or map_x >= _grid_w or map_y < 0 or map_y >= _grid_h:
			return 0.0
		if int((_grid[map_y] as Array)[map_x]) == 1:   # WALL
			# Re-compute distance to the wall face we just crossed (perpendicular
			# to the player's facing — handled in the caller via FOV cosine).
			if side_hit == 0:
				return (float(map_x) - px + (1.0 - float(step_x)) * 0.5) / rdx
			else:
				return (float(map_y) - py + (1.0 - float(step_y)) * 0.5) / rdy
	return 0.0

extends Node2D

# Renders ASCII border glyphs along the inner faces of every wall tile that
# touches a floor: "_" along the top/bottom edges and "|" along the left/right
# edges, plus "+" at outer corners where two perpendicular edges meet. One
# character per edge per tile, sized so a single glyph spans the tile
# dimension — placement is computed from the font's actual ascent/descent so
# strokes land at the wall/floor boundary rather than drifting inside.
# One node, one _draw() call — Godot caches the canvas item so cost is paid
# once.

const FLOOR_VAL := 0
const WALL_VAL  := 1

var _grid: Array          = []
var _grid_w: int          = 0
var _grid_h: int          = 0
var _tile: int            = 32
var _glyph_color: Color   = Color.WHITE
var _outline_color: Color = Color.BLACK
var _font: Font           = null
var _doorways: Array      = []   # Array[Vector2i] — tiles to mark with "="
var _doorway_color: Color = Color(0.85, 0.7, 0.3)

func setup(grid: Array, grid_w: int, grid_h: int, tile: int,
		glyph_col: Color, outline_col: Color) -> void:
	_grid          = grid
	_grid_w        = grid_w
	_grid_h        = grid_h
	_tile          = tile
	_glyph_color   = glyph_col
	_outline_color = outline_col
	_font = MonoFont.get_font()
	queue_redraw()

func set_doorways(tiles: Array, glyph_col: Color = Color(0.85, 0.7, 0.3)) -> void:
	_doorways      = tiles
	_doorway_color = glyph_col
	queue_redraw()

func _is_floor(x: int, y: int) -> bool:
	if x < 0 or x >= _grid_w or y < 0 or y >= _grid_h:
		return false
	return int((_grid[y] as Array)[x]) == FLOOR_VAL

func _draw() -> void:
	if _font == null or _grid.is_empty():
		return
	# Pick a font size so a single "|" almost spans a tile vertically. This
	# also keeps a single "_" comfortably wide enough that ~2 of them cover
	# a tile horizontally without leaving a gap at the centre.
	var fs: int = maxi(12, int(round(float(_tile) * 0.95)))
	var t  := float(_tile)
	var ascent: float  = _font.get_ascent(fs)
	var descent: float = _font.get_descent(fs)

	# How many "_" glyphs to span one tile width — round up so we always
	# overshoot rather than leaving a gap mid-tile.
	var underscore_w: float = maxf(1.0, _font.get_string_size("_",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var horiz_count: int = maxi(1, int(ceil(t / underscore_w)))
	var horiz_text: String = "_".repeat(horiz_count)
	var horiz_text_w: float = _font.get_string_size(horiz_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var horiz_off_x: float = (t - horiz_text_w) * 0.5

	# Pipe metrics — width centres the bar on the boundary, the y baseline
	# centres the bar vertically inside the tile.
	var pipe_w: float = _font.get_string_size("|",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var pipe_baseline_off_y: float = t * 0.5 + (ascent - descent) * 0.5

	# Corner "+" metrics — centred on the corner of the wall tile.
	var corner_size: Vector2 = _font.get_string_size("+",
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var corner_baseline_off_y: float = t * 0.5 + (ascent - descent) * 0.5

	var top_baseline_y_offset: float    = 1.0           # stroke at y0 + ~1
	var bottom_baseline_y_offset: float = t - 1.0       # stroke at y1 - ~1

	for y in _grid_h:
		var row: Array = _grid[y]
		for x in _grid_w:
			if int(row[x]) != WALL_VAL:
				continue
			var x0: float = float(x) * t
			var y0: float = float(y) * t
			var x1: float = x0 + t
			var y1: float = y0 + t
			var floor_top: bool    = _is_floor(x, y - 1)
			var floor_bottom: bool = _is_floor(x, y + 1)
			var floor_left: bool   = _is_floor(x - 1, y)
			var floor_right: bool  = _is_floor(x + 1, y)
			# Top edge — floor above
			if floor_top:
				_draw_text_outlined(horiz_text,
					Vector2(x0 + horiz_off_x, y0 + top_baseline_y_offset), fs)
			# Bottom edge — floor below
			if floor_bottom:
				_draw_text_outlined(horiz_text,
					Vector2(x0 + horiz_off_x, y0 + bottom_baseline_y_offset), fs)
			# Left edge
			if floor_left:
				_draw_text_outlined("|",
					Vector2(x0, y0 + pipe_baseline_off_y), fs)
			# Right edge
			if floor_right:
				_draw_text_outlined("|",
					Vector2(x1 - pipe_w, y0 + pipe_baseline_off_y), fs)
			# ── Corner glyphs ───────────────────────────────────────────────
			# Outer corners: two perpendicular edges meet at this tile corner.
			# We draw a "+" overlaid on the intersection so the stroke ends
			# meet cleanly instead of looking like a T-junction.
			if floor_top and floor_left:
				_draw_text_outlined("+",
					Vector2(x0, y0 + corner_baseline_off_y - t * 0.5 + corner_size.y * 0.20), fs)
			if floor_top and floor_right:
				_draw_text_outlined("+",
					Vector2(x1 - corner_size.x, y0 + corner_baseline_off_y - t * 0.5 + corner_size.y * 0.20), fs)
			if floor_bottom and floor_left:
				_draw_text_outlined("+",
					Vector2(x0, y0 + corner_baseline_off_y + t * 0.5 - corner_size.y * 0.20), fs)
			if floor_bottom and floor_right:
				_draw_text_outlined("+",
					Vector2(x1 - corner_size.x, y0 + corner_baseline_off_y + t * 0.5 - corner_size.y * 0.20), fs)
	# Doorway markers — drawn last so they sit on top of any wall glyphs.
	if not _doorways.is_empty():
		var eq_size: Vector2 = _font.get_string_size("=",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
		for d in _doorways:
			var dt: Vector2i = d
			var dx: float = float(dt.x) * t + (t - eq_size.x) * 0.5
			var dy: float = float(dt.y) * t + t * 0.5 + (ascent - descent) * 0.5
			# Outline pass
			for ox in [-1.0, 1.0]:
				for oy in [-1.0, 1.0]:
					draw_string(_font, Vector2(dx + ox, dy + oy), "=",
						HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _outline_color)
			draw_string(_font, Vector2(dx, dy), "=",
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _doorway_color)

func _draw_text_outlined(text: String, pos: Vector2, fs: int) -> void:
	# 4-corner offset outline so the glyphs stay readable against the dark
	# wall fill or the floor pattern, whichever side they peek over.
	for ox in [-1.0, 1.0]:
		for oy in [-1.0, 1.0]:
			draw_string(_font, pos + Vector2(ox, oy), text,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _outline_color)
	draw_string(_font, pos, text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, _glyph_color)

extends Node2D

# Minimap renderer — draws "." per floor tile and "#" per wall tile in a
# compact monospace font. One _draw() call covers the whole map; Godot
# caches the canvas item so the cost is paid once per floor.

const FLOOR_VAL := 0
const WALL_VAL  := 1

var _grid: Array      = []
var _grid_w: int      = 0
var _grid_h: int      = 0
var _cell_w: float    = 3.0
var _cell_h: float    = 4.0
var _font: Font       = null
var _font_size: int   = 6
var _floor_color: Color = Color(0.45, 0.42, 0.6, 0.85)
var _wall_color: Color  = Color(0.85, 0.85, 0.95, 1.0)

func setup(grid: Array, grid_w: int, grid_h: int, cell_w: float, cell_h: float) -> void:
	_grid   = grid
	_grid_w = grid_w
	_grid_h = grid_h
	_cell_w = cell_w
	_cell_h = cell_h
	_font = MonoFont.get_font()
	# Pick a font_size that visually approximates the cell dimensions.
	_font_size = maxi(4, int(round(_cell_h * 1.5)))
	queue_redraw()

func _draw() -> void:
	if _font == null or _grid.is_empty():
		return
	var fs := _font_size
	# Baseline offset so each glyph sits inside its cell; small descent shrink
	# so chars don't bleed into the next row.
	var ascent: float  = _font.get_ascent(fs)
	var baseline_off: float = ascent * 0.85
	for y in _grid_h:
		var row: Array = _grid[y]
		var cy: float = float(y) * _cell_h + baseline_off
		for x in _grid_w:
			var ch: String
			var col: Color
			if int(row[x]) == FLOOR_VAL:
				ch = "."
				col = _floor_color
			else:
				ch = "#"
				col = _wall_color
			draw_string(_font, Vector2(float(x) * _cell_w, cy), ch,
				HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)

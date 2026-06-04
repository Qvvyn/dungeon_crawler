class_name AsciiCompositor

# Overlays layered ASCII "parts" onto a base body grid. Lets one armored-
# humanoid base spawn many variants by stamping different weapons / helmets /
# shields / armor tweaks at fixed slot positions. Each layer's non-transparent
# characters are painted onto the base at a (row, col) offset; the grid grows
# as needed so parts can extend past the base silhouette (a raised sword, etc.).
#
#   AsciiCompositor.compose(BASE, [
#       {"art": SWORD,  "row": 0, "col": 11},   # right hand, held high
#       {"art": PLUME,  "row": 0, "col": 5},    # helmet crest
#   ])
#
# Transparency defaults to space, so parts only paint their ink and let the
# base show through the gaps.

static func compose(base: String, layers: Array) -> String:
	var grid: Array = _to_grid(base)
	for layer in layers:
		var l: Dictionary = layer as Dictionary
		_stamp(grid, String(l.get("art", "")), int(l.get("row", 0)),
			int(l.get("col", 0)), String(l.get("transparent", " ")))
	return _grid_to_string(grid)

static func _to_grid(s: String) -> Array:
	var rows: Array = []
	for line in s.split("\n"):
		var ls: String = line
		var chars: Array = []
		for i in ls.length():
			chars.append(ls[i])
		rows.append(chars)
	return rows

static func _stamp(grid: Array, art: String, row: int, col: int, transparent: String) -> void:
	var lines: PackedStringArray = art.split("\n")
	for r in lines.size():
		var gr: int = row + r
		if gr < 0:
			continue
		while gr >= grid.size():
			grid.append([])
		var line: String = lines[r]
		var grow: Array = grid[gr]
		for c in line.length():
			var ch: String = line[c]
			if ch == transparent:
				continue
			var gc: int = col + c
			if gc < 0:
				continue
			while gc >= grow.size():
				grow.append(" ")
			grow[gc] = ch

static func _grid_to_string(grid: Array) -> String:
	var out: PackedStringArray = []
	for grow in grid:
		var s: String = ""
		for ch in grow:
			s += String(ch)
		out.append(s)
	return "\n".join(out)

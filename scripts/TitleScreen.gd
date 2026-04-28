extends Control

# Centered 1600x900 design rect that holds the title art, buttons, borders,
# etc. The outer TitleScreen Control still fills the full viewport (so the
# black bg covers the whole browser window even on ultra-wide displays);
# the design_root keeps the layout content centered within it.
var _design_root: Control = null

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	# Title is the neutral lobby — clear any village hub state so a
	# Village → Title → Dungeon path doesn't accidentally preserve
	# in-hub flags (which would skip the dungeon's run reset).
	GameState.in_hub = false
	_build_ui()

func _build_ui() -> void:
	# ── Background ────────────────────────────────────────────────────────────
	# Full-viewport so the dark backdrop covers the whole browser window
	# regardless of how the canvas is stretched.
	var bg := ColorRect.new()
	bg.color         = Color(0.02, 0.01, 0.05)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# Centered design rect — every UI element below is added to this so the
	# whole title menu stays centered when the browser is wider than 1600x900.
	_design_root = Control.new()
	_design_root.anchor_left   = 0.5
	_design_root.anchor_top    = 0.5
	_design_root.anchor_right  = 0.5
	_design_root.anchor_bottom = 0.5
	_design_root.offset_left   = -800.0
	_design_root.offset_top    = -450.0
	_design_root.offset_right  = 800.0
	_design_root.offset_bottom = 450.0
	_design_root.mouse_filter  = Control.MOUSE_FILTER_PASS
	# On phones the design rect ends up tiny under stretch_aspect=expand;
	# scale it up around the viewport center so labels and buttons stay
	# readable. Scale-from-center is implicit because the design_root's
	# pivot defaults to (0,0) but its anchors are at 0.5, so it expands
	# around the viewport center as the rendered rect grows.
	if GameState.is_mobile:
		_design_root.pivot_offset = Vector2(800.0, 450.0)
		_design_root.scale = Vector2(1.5, 1.5)
	add_child(_design_root)

	# ── Border ────────────────────────────────────────────────────────────────
	_line(Vector2(60, 60),   Vector2(1540, 60))
	_line(Vector2(60, 840),  Vector2(1540, 840))
	_line(Vector2(60, 60),   Vector2(60, 840))
	_line(Vector2(1540, 60), Vector2(1540, 840))

	for cx: float in [60.0, 1540.0]:
		for cy: float in [60.0, 840.0]:
			_lbl("╬", Vector2(cx - 7, cy - 12), 20, Color(0.4, 0.3, 0.6))

	# ── Title (ASCII art, full-width, centered) ──────────────────────────────
	# Five-row block-letter rendering of "WIZARD WALK". Wrapped in parens so
	# the multi-line concatenation doesn't need fragile `\` line-continuation.
	# Each \\ in source is one literal backslash in the final string.
	var title_ascii: String = (
		"__        __  ___  _____     _     ____   ____      __        __     _      _      _  __\n"
		+ "\\ \\      / / |_ _||__  /   / \\   |  _ \\ |  _ \\     \\ \\      / /   / \\    | |    | |/ /\n"
		+ " \\ \\ /\\ / /   | |   / /   / _ \\  | |_) || | | |     \\ \\ /\\ / /   / _ \\   | |    | ' / \n"
		+ "  \\ V  V /    | |  / /_  / ___ \\ |  _ < | |_| |      \\ V  V /   / ___ \\  | |___ | . \\ \n"
		+ "   \\_/\\_/    |___|/____|/_/   \\_\\|_| \\_\\|____/        \\_/\\_/   /_/   \\_\\ |_____||_|\\_\\"
	)
	_lbl_ascii(title_ascii, 80, 20, Color(0.75, 0.55, 1.0))

	# ── Subtitle ──────────────────────────────────────────────────────────────
	_lbl_c("~ A procedurally generated ASCII roguelike ~", 240, 16, Color(0.32, 0.22, 0.52))

	# ── Horizontal rule ───────────────────────────────────────────────────────
	_line(Vector2(160, 294), Vector2(1440, 294))

	# ── Buttons (centered) ────────────────────────────────────────────────────
	_menu_button_c("[ ENTER WIZARD VILLAGE ]", 332, 24, Color(0.78, 0.62, 1.0), _on_village)
	_menu_button_c("[ STRAIGHT TO DUNGEON ]",  376, 18, Color(0.2, 0.85, 0.45), _on_start)
	# CONTINUE RUN — only enabled when there's a saved run to resume. The
	# save file is written by the in-pause "SAVE RUN" button, the shrine
	# checkpoint, or sleeping at the Inn.
	var has_save: bool = FileAccess.file_exists("user://save_run.json")
	if has_save:
		_menu_button_c("[ CONTINUE RUN ]", 414, 18, Color(0.95, 0.7, 0.4), _on_continue_run)
	else:
		_disabled_label_c("[ CONTINUE RUN ]", 414, 18, Color(0.32, 0.28, 0.40))
	_menu_button_c("[ RUN HISTORY ]",        452, 18, Color(0.5, 0.7, 1.0),   _on_history)
	_menu_button_c("[ GLOBAL LEADERBOARD ]", 490, 18, Color(1.0, 0.85, 0.3),  _on_global_lb)
	_menu_button_c("[ QUIT ]",               528, 18, Color(0.55, 0.55, 0.65), _on_quit)

	# ── Blinking prompt ───────────────────────────────────────────────────────
	var blink := _lbl_c("PRESS ENTER TO START", 560, 18, Color(0.6, 0.5, 0.9))
	var tw := blink.create_tween()
	tw.set_loops()
	tw.tween_property(blink, "modulate:a", 0.15, 0.75)
	tw.tween_property(blink, "modulate:a", 1.0,  0.75)

	# ── Controls hint (centered) ──────────────────────────────────────────────
	_lbl_c(
		"WASD move  |  LMB shoot  |  E interact  |  I inventory  |  SHIFT dash  |  ESC pause",
		660, 13, Color(0.35, 0.35, 0.45))

# ── Helpers ───────────────────────────────────────────────────────────────────

# Multi-line ASCII art label, monospace, centered horizontally. Used for
# the title's block-letter "WIZARD WALK" so the columns line up cleanly.
func _lbl_ascii(txt: String, y: float, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = Vector2(0, y)
	l.size = Vector2(1600, sz * 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.05))
	l.add_theme_constant_override("outline_size", 2)
	l.add_theme_constant_override("line_separation", -2)
	# Monospace so the slashes / underscores in the block letters align.
	var mono := MonoFont.get_font()
	l.add_theme_font_override("font", mono)
	_design_root.add_child(l)
	return l

func _lbl_c(txt: String, y: float, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text     = txt
	l.position = Vector2(0, y)
	l.size     = Vector2(1600, sz * 3 + 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	_design_root.add_child(l)
	return l

# Greyed-out menu entry — same layout as a button but no Button node, so
# it can't be clicked or hovered. Used for CONTINUE RUN when no save exists.
func _disabled_label_c(txt: String, y: float, sz: int, col: Color) -> void:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = Vector2(0, y)
	lbl.size     = Vector2(1600, sz + 24)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	_design_root.add_child(lbl)

func _menu_button_c(txt: String, y: float, sz: int, col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = Vector2(0, y)
	lbl.size     = Vector2(1600, sz + 24)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	_design_root.add_child(lbl)

	var btn := Button.new()
	btn.text     = ""
	btn.flat     = true
	btn.position = Vector2(0, y)
	btn.size     = Vector2(1600, sz + 24)
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col.lightened(0.35)))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col))
	btn.pressed.connect(cb)
	_design_root.add_child(btn)

func _line(from: Vector2, to: Vector2) -> void:
	var seg := ColorRect.new()
	var is_horiz: bool = abs(to.y - from.y) < 2.0
	if is_horiz:
		seg.position = from
		seg.size = Vector2(to.x - from.x, 2)
	else:
		seg.position = from
		seg.size = Vector2(2, to.y - from.y)
	seg.color = Color(0.28, 0.18, 0.45)
	_design_root.add_child(seg)

func _lbl(txt: String, pos: Vector2, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text     = txt
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	_design_root.add_child(l)
	return l

# Returns a centered 1600×900 Control intended to host all the inner
# UI of an overlay (dungeon select, run history, global LB). On mobile
# the returned Control is scaled 1.5× around its center so panels and
# text stay readable on a phone.
func _make_overlay_content_root() -> Control:
	var c := Control.new()
	c.anchor_left   = 0.5
	c.anchor_top    = 0.5
	c.anchor_right  = 0.5
	c.anchor_bottom = 0.5
	c.offset_left   = -800.0
	c.offset_top    = -450.0
	c.offset_right  = 800.0
	c.offset_bottom = 450.0
	c.mouse_filter  = Control.MOUSE_FILTER_PASS
	if GameState.is_mobile:
		c.pivot_offset = Vector2(800.0, 450.0)
		c.scale = Vector2(1.5, 1.5)
	return c

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_SPACE:
		_on_start()
	elif event.physical_keycode == KEY_ESCAPE:
		_on_quit()

func _on_start() -> void:
	_show_dungeon_select()

func _on_village() -> void:
	# Drop straight into the village hub — handles the bank, shop, and
	# inn flow before the player picks a dungeon to delve into.
	get_tree().change_scene_to_file("res://scenes/Village.tscn")

# Loads the most recent saved run directly — Player._ready picks up
# user://save_run.json and restores HP / mana / gold / level / difficulty
# from it (then deletes the file so the continue is one-shot). We don't
# touch GameState.starting_difficulty here; the saved difficulty value
# overrides it when Player._ready calls _try_load_save.
func _on_continue_run() -> void:
	GameState.test_mode = false
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _show_dungeon_select() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.88)
	dim.anchor_right  = 1.0
	dim.anchor_bottom = 1.0
	add_child(dim)
	# Centered, optionally-scaled content root. Existing builder code
	# below still uses `overlay` and treats it as the parent for all
	# panel content; close handlers free the outer `dim` so the dim and
	# its children all go away together.
	var overlay := _make_overlay_content_root()
	dim.add_child(overlay)
	# Wire the close button (built later in this function) to free the
	# whole overlay tree, not just the content root.
	var _close_target: ColorRect = dim

	var border := ColorRect.new()
	border.color    = Color(0.28, 0.18, 0.45, 0.9)
	border.position = Vector2(317, 117)
	border.size     = Vector2(966, 754)
	overlay.add_child(border)

	var panel := ColorRect.new()
	panel.color    = Color(0.03, 0.015, 0.08)
	panel.position = Vector2(320, 120)
	panel.size     = Vector2(960, 748)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "— CHOOSE YOUR DESCENT —"
	title.position = Vector2(320, 140)
	title.size = Vector2(960, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	overlay.add_child(title)

	var sub := Label.new()
	sub.text = "Harder floors promise greater rewards."
	sub.position = Vector2(320, 188)
	sub.size = Vector2(960, 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.32, 0.22, 0.52))
	overlay.add_child(sub)

	# climb = per-portal difficulty increment (locked by the chosen tier;
	# higher tiers climb faster). Decoupled from start diff so tiers that
	# share a starting value (Catacombs + Dungeon both at 1.0) can still
	# escalate at different rates.
	const TIERS: Array = [
		{"name": "CELLAR",    "diff": 0.5, "climb": 0.25, "loot": 0.8,  "stars": 1,
		 "col": Color(0.3, 0.9, 0.4),    "desc": "A forgotten wine cellar.  Mostly harmless."},
		{"name": "DUNGEON",   "diff": 1.0, "climb": 0.50, "loot": 1.0,  "stars": 2,
		 "col": Color(0.4, 0.7, 1.0),    "desc": "The standard delve.  Familiar dangers await."},
		{"name": "CATACOMBS", "diff": 2.0, "climb": 1.00, "loot": 1.3,  "stars": 3,
		 "col": Color(0.95, 0.85, 0.2),  "desc": "Ancient halls.  Something stirs in the dark."},
		{"name": "ABYSS",     "diff": 3.0, "climb": 1.50, "loot": 1.7,  "stars": 4,
		 "col": Color(1.0, 0.5, 0.1),    "desc": "Darkness given form.  Very few return."},
		{"name": "HELLPIT",   "diff": 5.0, "climb": 2.00, "loot": 2.5,  "stars": 5,
		 "col": Color(1.0, 0.18, 0.12),  "desc": "Pure malice.  You will not survive."},
	]

	const ROW_H  := 80.0
	const ROW_Y0 := 218.0

	for i in TIERS.size():
		var tier: Dictionary = TIERS[i]
		var ry := ROW_Y0 + i * ROW_H
		var col: Color = tier["col"]
		var stars := ""
		for s in 5:
			stars += "●" if s < int(tier["stars"]) else "○"

		var name_lbl := Label.new()
		name_lbl.text = "[ %s ]" % tier["name"]
		name_lbl.position = Vector2(348, ry + 6)
		name_lbl.size = Vector2(360, 34)
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", col)
		overlay.add_child(name_lbl)

		var stats_lbl := Label.new()
		stats_lbl.text = "Diff  %s     Loot  x%.1f" % [stars, float(tier["loot"])]
		stats_lbl.position = Vector2(720, ry + 10)
		stats_lbl.size = Vector2(520, 26)
		stats_lbl.add_theme_font_size_override("font_size", 15)
		stats_lbl.add_theme_color_override("font_color", col.darkened(0.15))
		overlay.add_child(stats_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = tier["desc"]
		desc_lbl.position = Vector2(348, ry + 46)
		desc_lbl.size = Vector2(900, 20)
		desc_lbl.add_theme_font_size_override("font_size", 13)
		desc_lbl.add_theme_color_override("font_color", Color(0.38, 0.32, 0.52))
		overlay.add_child(desc_lbl)

		# Separator line
		if i < TIERS.size() - 1:
			var sep := ColorRect.new()
			sep.color    = Color(0.18, 0.12, 0.28)
			sep.position = Vector2(336, ry + ROW_H - 2)
			sep.size     = Vector2(928, 1)
			overlay.add_child(sep)

		var _d: float = tier["diff"]
		var _l: float = tier["loot"]
		var _climb: float = tier["climb"]
		var row_btn := Button.new()
		row_btn.flat     = true
		row_btn.position = Vector2(330, ry)
		row_btn.size     = Vector2(940, ROW_H - 4)
		row_btn.mouse_entered.connect(func() -> void:
			name_lbl.add_theme_color_override("font_color", col.lightened(0.3))
			stats_lbl.add_theme_color_override("font_color", col.lightened(0.1)))
		row_btn.mouse_exited.connect(func() -> void:
			name_lbl.add_theme_color_override("font_color", col)
			stats_lbl.add_theme_color_override("font_color", col.darkened(0.15)))
		row_btn.pressed.connect(func() -> void:
			GameState.test_mode           = false
			GameState.starting_difficulty = _d
			GameState.starting_climb_rate = _climb
			GameState.difficulty          = _d
			GameState.loot_multiplier     = _l
			GameState.save_settings()
			# A new run from this screen is intended to start at the
			# selected difficulty — wipe any leftover save so Player._ready
			# doesn't load over our chosen settings (CONTINUE RUN is the
			# only path that should resume a save now).
			if FileAccess.file_exists("user://save_run.json"):
				DirAccess.remove_absolute("user://save_run.json")
			get_tree().change_scene_to_file("res://scenes/World.tscn"))
		overlay.add_child(row_btn)

	# ── Separator before testing grounds ──────────────────────────────────────
	var test_sep := ColorRect.new()
	test_sep.color    = Color(0.15, 0.35, 0.35)
	test_sep.position = Vector2(336, ROW_Y0 + TIERS.size() * ROW_H + 4)
	test_sep.size     = Vector2(928, 1)
	overlay.add_child(test_sep)

	# ── Testing Grounds row ────────────────────────────────────────────────────
	var test_y := ROW_Y0 + TIERS.size() * ROW_H + 10.0
	var test_col := Color(0.25, 0.95, 0.85)

	var test_name := Label.new()
	test_name.text = "[ TESTING GROUNDS ]"
	test_name.position = Vector2(348, test_y + 4)
	test_name.size = Vector2(360, 30)
	test_name.add_theme_font_size_override("font_size", 20)
	test_name.add_theme_color_override("font_color", test_col)
	overlay.add_child(test_name)

	var test_desc := Label.new()
	test_desc.text = "Endless waves · scaling HP · passive until struck · best gear spawned"
	test_desc.position = Vector2(348, test_y + 36)
	test_desc.size = Vector2(900, 18)
	test_desc.add_theme_font_size_override("font_size", 12)
	test_desc.add_theme_color_override("font_color", Color(0.25, 0.55, 0.55))
	overlay.add_child(test_desc)

	var test_btn := Button.new()
	test_btn.flat     = true
	test_btn.position = Vector2(330, test_y - 2)
	test_btn.size     = Vector2(940, 60)
	test_btn.mouse_entered.connect(func() -> void:
		test_name.add_theme_color_override("font_color", test_col.lightened(0.3)))
	test_btn.mouse_exited.connect(func() -> void:
		test_name.add_theme_color_override("font_color", test_col))
	test_btn.pressed.connect(func() -> void:
		GameState.test_mode           = true
		GameState.starting_difficulty = 1.0
		GameState.starting_climb_rate = 0.5
		GameState.difficulty          = 1.0
		GameState.loot_multiplier     = 1.0
		# Same reasoning as the tier rows above — testing grounds is a
		# fresh start, ignore any leftover save.
		if FileAccess.file_exists("user://save_run.json"):
			DirAccess.remove_absolute("user://save_run.json")
		get_tree().change_scene_to_file("res://scenes/World.tscn"))
	overlay.add_child(test_btn)

	var close_lbl := Label.new()
	close_lbl.text = "[ BACK ]"
	close_lbl.position = Vector2(680, test_y + 70)
	close_lbl.size = Vector2(240, 30)
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.add_theme_font_size_override("font_size", 18)
	close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9))
	overlay.add_child(close_lbl)

	var close_btn := Button.new()
	close_btn.flat     = true
	close_btn.position = Vector2(680, test_y + 68)
	close_btn.size     = Vector2(240, 34)
	close_btn.pressed.connect(func() -> void: _close_target.queue_free())
	close_btn.mouse_entered.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0)))
	close_btn.mouse_exited.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9)))
	overlay.add_child(close_btn)

func _on_quit() -> void:
	get_tree().quit()

func _on_history() -> void:
	_show_history_overlay()

func _on_global_lb() -> void:
	_show_global_lb_overlay()

func _show_history_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.color        = Color(0.0, 0.0, 0.0, 0.88)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	add_child(overlay)

	var panel := ColorRect.new()
	panel.color    = Color(0.04, 0.02, 0.10)
	panel.position = Vector2(320, 140)
	panel.size     = Vector2(960, 580)
	overlay.add_child(panel)

	var border := ColorRect.new()
	border.color    = Color(0.28, 0.18, 0.45, 0.9)
	border.position = Vector2(317, 137)
	border.size     = Vector2(966, 586)
	overlay.add_child(border)
	overlay.move_child(panel, 1)

	var title := Label.new()
	title.text = "— RUN HISTORY —"
	title.position = Vector2(320, 155)
	title.size = Vector2(960, 48)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	overlay.add_child(title)

	const BIOME_NAMES_H := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]

	var runs: Array = RunHistory.runs
	if runs.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No runs recorded yet."
		empty_lbl.position = Vector2(320, 360)
		empty_lbl.size = Vector2(960, 32)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 18)
		empty_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.6))
		overlay.add_child(empty_lbl)
	else:
		# Header
		var hdr := Label.new()
		hdr.text = "#    Floors   Kills   Gold    Damage  Biome          Date"
		hdr.position = Vector2(336, 220)
		hdr.size = Vector2(928, 22)
		hdr.add_theme_font_size_override("font_size", 14)
		hdr.add_theme_color_override("font_color", Color(0.55, 0.55, 0.75))
		overlay.add_child(hdr)

		for i in runs.size():
			var run: Dictionary = runs[i]
			var biome_idx: int = clampi(int(run.get("biome", 0)), 0, 3)
			var row_text := "%d    F%-6d  %-7d %-7d %-7d %-14s %s" % [
				i + 1,
				int(run.get("portals", 0)) + 1,
				int(run.get("kills",   0)),
				int(run.get("gold",    0)),
				int(run.get("damage",  0)),
				BIOME_NAMES_H[biome_idx],
				str(run.get("date", "?")),
			]
			var row := Label.new()
			row.text = row_text
			row.position = Vector2(336, 252 + i * 44)
			row.size = Vector2(928, 38)
			row.add_theme_font_size_override("font_size", 15)
			var row_col := Color(0.85, 0.75, 1.0) if i == 0 else Color(0.55, 0.55, 0.7)
			row.add_theme_color_override("font_color", row_col)
			overlay.add_child(row)

	# Biome records
	var records := Leaderboard.get_biome_records()
	var deepest: Dictionary = records.get("deepest", {})
	var rec_txt := "Records — "
	for key in ["dungeon", "catacombs", "ice", "lava"]:
		rec_txt += "%s: F%d  " % [key.capitalize(), int(deepest.get(key, 0)) + 1]
	var rec_lbl := Label.new()
	rec_lbl.text = rec_txt
	rec_lbl.position = Vector2(336, 660)
	rec_lbl.size = Vector2(928, 22)
	rec_lbl.add_theme_font_size_override("font_size", 12)
	rec_lbl.add_theme_color_override("font_color", Color(0.5, 0.75, 0.5))
	overlay.add_child(rec_lbl)

	# Close button
	var close_lbl := Label.new()
	close_lbl.text = "[ CLOSE ]"
	close_lbl.position = Vector2(680, 692)
	close_lbl.size = Vector2(240, 30)
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.add_theme_font_size_override("font_size", 18)
	close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9))
	overlay.add_child(close_lbl)

	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.position = Vector2(680, 690)
	close_btn.size = Vector2(240, 34)
	close_btn.pressed.connect(func() -> void: overlay.queue_free())
	close_btn.mouse_entered.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0)))
	close_btn.mouse_exited.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9)))
	overlay.add_child(close_btn)

# Global leaderboard overlay — fetches scores from the Cloudflare Worker
# and renders three columns (PORTALS / GOLD / DAMAGE), top 10 each. Falls
# back to a status message on network or configuration failure so the
# offline experience still feels intentional.
func _show_global_lb_overlay() -> void:
	var overlay := ColorRect.new()
	overlay.color        = Color(0.0, 0.0, 0.0, 0.88)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	add_child(overlay)

	var border := ColorRect.new()
	border.color    = Color(0.55, 0.42, 0.18, 0.9)
	border.position = Vector2(157, 117)
	border.size     = Vector2(1286, 686)
	overlay.add_child(border)

	var panel := ColorRect.new()
	panel.color    = Color(0.04, 0.03, 0.08)
	panel.position = Vector2(160, 120)
	panel.size     = Vector2(1280, 680)
	overlay.add_child(panel)

	var title := Label.new()
	title.text = "— GLOBAL LEADERBOARD —"
	title.position = Vector2(160, 140)
	title.size = Vector2(1280, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	overlay.add_child(title)

	var status := Label.new()
	status.name = "Status"
	status.text = "Loading…"
	status.position = Vector2(160, 200)
	status.size = Vector2(1280, 28)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 14)
	status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.75))
	overlay.add_child(status)

	# Close button (always present)
	var close_lbl := Label.new()
	close_lbl.text = "[ CLOSE ]"
	close_lbl.position = Vector2(680, 750)
	close_lbl.size = Vector2(240, 30)
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.add_theme_font_size_override("font_size", 18)
	close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9))
	overlay.add_child(close_lbl)

	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.position = Vector2(680, 748)
	close_btn.size = Vector2(240, 34)
	close_btn.pressed.connect(func() -> void: overlay.queue_free())
	close_btn.mouse_entered.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0)))
	close_btn.mouse_exited.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9)))
	overlay.add_child(close_btn)

	if not OnlineLeaderboard.is_configured():
		status.text = "Leaderboard URL not configured. See OnlineLeaderboard.gd."
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))
		return

	var on_received := func(scores: Dictionary) -> void:
		if not is_instance_valid(overlay):
			return
		status.queue_free()
		_render_global_lb_columns(overlay, scores)
	var on_failed := func(reason: String) -> void:
		if not is_instance_valid(overlay):
			return
		status.text = "Couldn't reach leaderboard: %s" % reason
		status.add_theme_color_override("font_color", Color(1.0, 0.5, 0.4))

	OnlineLeaderboard.scores_received.connect(on_received, CONNECT_ONE_SHOT)
	OnlineLeaderboard.scores_failed.connect(on_failed, CONNECT_ONE_SHOT)
	OnlineLeaderboard.fetch_scores()

func _render_global_lb_columns(parent: Node, scores: Dictionary) -> void:
	var cats: Array = [
		{"key": "portals", "title": "PORTALS", "x": 220.0, "color": Color(0.55, 0.85, 1.0)},
		{"key": "gold",    "title": "GOLD",    "x": 640.0, "color": Color(1.0, 0.85, 0.2)},
		{"key": "damage",  "title": "DAMAGE",  "x": 1060.0,"color": Color(1.0, 0.45, 0.45)},
	]
	for cat: Dictionary in cats:
		_render_global_lb_column(parent, cat["title"], scores.get(cat["key"], []),
			Vector2(cat["x"] - 180.0, 210), cat["color"])

func _render_global_lb_column(parent: Node, title: String, entries: Array, pos: Vector2, color: Color) -> void:
	var col_w := 360.0
	var header := Label.new()
	header.text = title
	header.position = pos
	header.size = Vector2(col_w, 28)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 18)
	header.add_theme_color_override("font_color", color)
	parent.add_child(header)

	if entries.is_empty():
		var empty := Label.new()
		empty.text = "(no entries yet)"
		empty.position = pos + Vector2(0, 38)
		empty.size = Vector2(col_w, 24)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		parent.add_child(empty)
		return

	for i in entries.size():
		var entry: Dictionary = entries[i]
		var row := Label.new()
		row.text = "%2d.  %-16s  %d" % [i + 1, str(entry.get("name", "?")), int(entry.get("value", 0))]
		row.position = pos + Vector2(0, 38 + i * 26)
		row.size = Vector2(col_w, 22)
		row.add_theme_font_size_override("font_size", 14)
		var row_col := Color(1.0, 0.95, 0.4) if i == 0 else (Color(0.85, 0.85, 0.9) if i < 3 else Color(0.6, 0.6, 0.7))
		row.add_theme_color_override("font_color", row_col)
		row.add_theme_font_override("font", MonoFont.get_font())
		parent.add_child(row)

extends Control

func _ready() -> void:
	anchor_right  = 1.0
	anchor_bottom = 1.0
	_build_ui()

func _build_ui() -> void:
	# ── Background ────────────────────────────────────────────────────────────
	var bg := ColorRect.new()
	bg.color         = Color(0.02, 0.01, 0.05)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
	add_child(bg)

	# ── Border ────────────────────────────────────────────────────────────────
	_line(Vector2(60, 60),   Vector2(1540, 60))
	_line(Vector2(60, 840),  Vector2(1540, 840))
	_line(Vector2(60, 60),   Vector2(60, 840))
	_line(Vector2(1540, 60), Vector2(1540, 840))

	for cx: float in [60.0, 1540.0]:
		for cy: float in [60.0, 840.0]:
			_lbl("╬", Vector2(cx - 7, cy - 12), 20, Color(0.4, 0.3, 0.6))

	# ── Title (full-width, centered) ──────────────────────────────────────────
	_lbl_c("DUNGEON  CRAWLER", 150, 72, Color(0.75, 0.55, 1.0))

	# ── Subtitle ──────────────────────────────────────────────────────────────
	_lbl_c("~ A procedurally generated ASCII dungeon crawler ~", 258, 16, Color(0.32, 0.22, 0.52))

	# ── Horizontal rule ───────────────────────────────────────────────────────
	_line(Vector2(160, 294), Vector2(1440, 294))

	# ── Buttons (centered) ────────────────────────────────────────────────────
	_menu_button_c("[ ENTER THE DUNGEON ]", 340, 28, Color(0.2, 0.85, 0.45), _on_start)
	_menu_button_c("[ RUN HISTORY ]",      420, 18, Color(0.5, 0.7, 1.0),   _on_history)
	_menu_button_c("[ QUIT ]",             478, 18, Color(0.55, 0.55, 0.65), _on_quit)

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

func _lbl_c(txt: String, y: float, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text     = txt
	l.position = Vector2(0, y)
	l.size     = Vector2(1600, sz * 3 + 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l

func _menu_button_c(txt: String, y: float, sz: int, col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = Vector2(0, y)
	lbl.size     = Vector2(1600, sz + 24)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", sz)
	lbl.add_theme_color_override("font_color", col)
	add_child(lbl)

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
	add_child(btn)

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
	add_child(seg)

func _lbl(txt: String, pos: Vector2, sz: int, col: Color) -> Label:
	var l := Label.new()
	l.text     = txt
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode == KEY_ENTER or event.physical_keycode == KEY_SPACE:
		_on_start()
	elif event.physical_keycode == KEY_ESCAPE:
		_on_quit()

func _on_start() -> void:
	_show_dungeon_select()

func _show_dungeon_select() -> void:
	var overlay := ColorRect.new()
	overlay.color        = Color(0.0, 0.0, 0.0, 0.88)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	add_child(overlay)

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

	const TIERS: Array = [
		{"name": "CELLAR",    "diff": 0.5, "loot": 0.8,  "stars": 1,
		 "col": Color(0.3, 0.9, 0.4),    "desc": "A forgotten wine cellar.  Mostly harmless."},
		{"name": "DUNGEON",   "diff": 1.0, "loot": 1.0,  "stars": 2,
		 "col": Color(0.4, 0.7, 1.0),    "desc": "The standard delve.  Familiar dangers await."},
		{"name": "CATACOMBS", "diff": 1.8, "loot": 1.3,  "stars": 3,
		 "col": Color(0.95, 0.85, 0.2),  "desc": "Ancient halls.  Something stirs in the dark."},
		{"name": "ABYSS",     "diff": 3.2, "loot": 1.7,  "stars": 4,
		 "col": Color(1.0, 0.5, 0.1),    "desc": "Darkness given form.  Very few return."},
		{"name": "HELLPIT",   "diff": 5.5, "loot": 2.5,  "stars": 5,
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
			GameState.difficulty          = _d
			GameState.loot_multiplier     = _l
			GameState.save_settings()
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
		GameState.difficulty          = 1.0
		GameState.loot_multiplier     = 1.0
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
	close_btn.pressed.connect(func() -> void: overlay.queue_free())
	close_btn.mouse_entered.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 1.0)))
	close_btn.mouse_exited.connect(func() -> void:
		close_lbl.add_theme_color_override("font_color", Color(0.6, 0.5, 0.9)))
	overlay.add_child(close_btn)

func _on_quit() -> void:
	get_tree().quit()

func _on_history() -> void:
	_show_history_overlay()

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

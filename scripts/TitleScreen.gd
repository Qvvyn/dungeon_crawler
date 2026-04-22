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

	# ── ASCII block art (full-width, centered) ────────────────────────────────
	_lbl_c(
		"██████╗ ██╗   ██╗███╗   ██╗ ██████╗ ███████╗ ██████╗ ███╗   ██╗\n" +
		"██╔══██╗██║   ██║████╗  ██║██╔════╝ ██╔════╝██╔═══██╗████╗  ██║\n" +
		"██║  ██║██║   ██║██╔██╗ ██║██║  ███╗█████╗  ██║   ██║██╔██╗ ██║\n" +
		"██║  ██║██║   ██║██║╚██╗██║██║   ██║██╔══╝  ██║   ██║██║╚██╗██║\n" +
		"██████╔╝╚██████╔╝██║ ╚████║╚██████╔╝███████╗╚██████╔╝██║ ╚████║\n" +
		"╚═════╝  ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝ ╚═════╝ ╚═╝  ╚═══╝",
		308, 11, Color(0.24, 0.16, 0.40))

	# ── Second rule ───────────────────────────────────────────────────────────
	_line(Vector2(160, 410), Vector2(1440, 410))

	# ── Buttons (centered) ────────────────────────────────────────────────────
	_menu_button_c("[ ENTER THE DUNGEON ]", 450, 28, Color(0.2, 0.85, 0.45), _on_start)
	_menu_button_c("[ QUIT ]",              530, 20, Color(0.55, 0.55, 0.65), _on_quit)

	# ── Blinking prompt ───────────────────────────────────────────────────────
	var blink := _lbl_c("PRESS ENTER TO START", 630, 18, Color(0.6, 0.5, 0.9))
	var tw := blink.create_tween()
	tw.set_loops()
	tw.tween_property(blink, "modulate:a", 0.15, 0.75)
	tw.tween_property(blink, "modulate:a", 1.0,  0.75)

	# ── Controls hint (centered) ──────────────────────────────────────────────
	_lbl_c(
		"WASD move  |  LMB shoot  |  E interact  |  I inventory  |  SHIFT dash  |  ESC pause",
		770, 13, Color(0.35, 0.35, 0.45))

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
	get_tree().change_scene_to_file("res://scenes/World.tscn")

func _on_quit() -> void:
	get_tree().quit()

extends Area2D

# Village → Dungeon portal. Interaction opens a small overlay menu:
#   * If a saved run exists (player exited via ExitPortal), the menu
#     offers CONTINUE? to resume from that floor + state, plus a
#     "NEW RUN" path that re-opens the tier picker.
#   * Otherwise the tier picker is shown directly so the player can
#     choose CELLAR / DUNGEON / CATACOMBS / ABYSS / HELLPIT and start
#     a fresh delve at the matching scaling.

const SAVE_PATH := "user://save_run.json"

# Tier definitions mirror TitleScreen.TIERS so the village picker stays
# in lockstep with the title screen. Bumping one without the other will
# desync starting difficulty/climb/loot for whichever path the player
# uses to enter the dungeon.
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

var _player_in_range: bool = false
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("interactable")   # bullets pass through (Projectile group check)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.attach_fp_visual(self, "v", Color(0.65, 0.45, 1.0), 0.50)

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact") and _ui == null:
		_open_menu()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = true
		var hint := get_node_or_null("InteractHint")
		if hint != null:
			hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		var hint := get_node_or_null("InteractHint")
		if hint != null:
			hint.visible = false
		_close_menu()

# ── Menu orchestration ────────────────────────────────────────────────────

func _open_menu() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 28
	get_tree().current_scene.add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_ui.add_child(dim)

	# Branch on whether a saved run is restorable. The save file is what
	# Player._try_load_save consumes on World scene entry.
	if FileAccess.file_exists(SAVE_PATH):
		_build_resume_panel()
	else:
		_build_tier_panel()

func _close_menu() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null

# ── Resume panel ──────────────────────────────────────────────────────────

func _build_resume_panel() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.06, 0.10, 0.97)
	panel.position = Vector2(440, 220)
	panel.size = Vector2(720, 460)
	_ui.add_child(panel)
	var border := ColorRect.new()
	border.color = Color(0.55, 0.85, 1.0, 0.65)
	border.position = Vector2(437, 217)
	border.size = Vector2(726, 466)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— PORTAL TO THE DUNGEON —"
	title.position = Vector2(440, 240)
	title.size = Vector2(720, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	_ui.add_child(title)

	# Run summary so the player knows what they're resuming.
	var info := Label.new()
	var save_summary := _read_save_summary()
	info.text = save_summary
	info.position = Vector2(460, 290)
	info.size = Vector2(680, 90)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_ui.add_child(info)

	_add_menu_button("[ CONTINUE? ]", Vector2(540, 410),
		Color(0.55, 1.0, 0.65), _on_continue)
	_add_menu_button("[ NEW RUN — pick a tier ]", Vector2(540, 470),
		Color(1.0, 0.85, 0.40), _on_new_run_picker)
	_add_menu_button("[ CANCEL ]", Vector2(540, 530),
		Color(0.6, 0.6, 0.7), _close_menu)

# Pulls the saved-run dictionary just enough to render a one-line summary.
# Failures (corrupt file, missing keys) fall back to a generic message —
# the actual load on World entry will handle the malformed-save case.
func _read_save_summary() -> String:
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return "Saved run found."
	var raw: Variant = JSON.parse_string(f.get_as_text())
	f = null
	if not (raw is Dictionary):
		return "Saved run found."
	var d := raw as Dictionary
	const BIOME_NAMES := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]
	var biome_idx: int = clampi(int(d.get("biome", 0)), 0, BIOME_NAMES.size() - 1)
	var floor_n: int = int(d.get("portals_used", 0)) + 1
	return "Resume floor %d of the %s\nLevel %d  ·  %d gold  ·  %d kills  ·  diff %.1f" % [
		floor_n, BIOME_NAMES[biome_idx],
		int(d.get("level", 1)), int(d.get("gold", 0)),
		int(d.get("kills", 0)), float(d.get("difficulty", 1.0))]

func _on_continue() -> void:
	# CONTINUE leaves save_run.json in place. World loads → Player._ready
	# → _try_load_save consumes the file and restores HP/mana/gold/level/
	# inventory/floor. Don't wipe inventory or reset run stats here; the
	# save replaces them.
	GameState.test_mode = false
	GameState.in_hub = false
	# Peek the save into GameState BEFORE the scene change so World._ready
	# generates the floor at the saved difficulty / biome / portal-count.
	# Without this peek, the scene loaded with stale GameState.difficulty,
	# generated a low-tier floor, and Player._ready then "fixed" diff
	# afterwards — too late to influence enemy spawns.
	GameState.peek_save_run_state()
	get_tree().change_scene_to_file("res://scenes/World.tscn")

# ── Tier picker ───────────────────────────────────────────────────────────

func _on_new_run_picker() -> void:
	# Tear down the resume panel and rebuild as the tier picker. Saved
	# run is only wiped once a tier is actually selected (so CANCEL on
	# the picker still preserves the resumable run).
	for child in _ui.get_children():
		if not (child is ColorRect and child.anchor_right == 1.0):
			# Keep the dim background; rebuild everything else.
			child.queue_free()
	_build_tier_panel()

func _build_tier_panel() -> void:
	var panel := ColorRect.new()
	panel.color = Color(0.04, 0.03, 0.10, 0.97)
	panel.position = Vector2(360, 130)
	panel.size = Vector2(880, 700)
	_ui.add_child(panel)
	var border := ColorRect.new()
	border.color = Color(0.55, 0.40, 0.85, 0.75)
	border.position = Vector2(357, 127)
	border.size = Vector2(886, 706)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— CHOOSE YOUR DESCENT —"
	title.position = Vector2(360, 152)
	title.size = Vector2(880, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.78, 0.62, 1.0))
	_ui.add_child(title)

	var sub := Label.new()
	sub.text = "Harder floors promise greater rewards."
	sub.position = Vector2(360, 192)
	sub.size = Vector2(880, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", Color(0.45, 0.40, 0.65))
	_ui.add_child(sub)

	var row_h: float = 70.0
	var row_y0: float = 226.0
	for i in TIERS.size():
		var tier: Dictionary = TIERS[i]
		var ry: float = row_y0 + float(i) * row_h
		var col: Color = tier["col"]
		var stars := ""
		for s in 5:
			stars += "●" if s < int(tier["stars"]) else "○"

		var name_lbl := Label.new()
		name_lbl.text = "[ %s ]" % tier["name"]
		name_lbl.position = Vector2(388, ry + 6)
		name_lbl.size = Vector2(320, 30)
		name_lbl.add_theme_font_size_override("font_size", 19)
		name_lbl.add_theme_color_override("font_color", col)
		_ui.add_child(name_lbl)

		var stats_lbl := Label.new()
		stats_lbl.text = "Diff %s    Loot ×%.1f" % [stars, float(tier["loot"])]
		stats_lbl.position = Vector2(720, ry + 10)
		stats_lbl.size = Vector2(480, 22)
		stats_lbl.add_theme_font_size_override("font_size", 13)
		stats_lbl.add_theme_color_override("font_color", col.darkened(0.15))
		_ui.add_child(stats_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = tier["desc"]
		desc_lbl.position = Vector2(388, ry + 38)
		desc_lbl.size = Vector2(800, 20)
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.40, 0.35, 0.55))
		_ui.add_child(desc_lbl)

		var d: float = tier["diff"]
		var l: float = tier["loot"]
		var climb: float = tier["climb"]
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2(372, ry)
		btn.size = Vector2(852, row_h - 4)
		# Guard the hover callbacks — _start_new_run queues a scene
		# change, and mouse_exited fires for the about-to-be-freed button
		# during teardown. Without is_instance_valid the callback hits
		# `null.add_theme_color_override(...)` and errors out.
		btn.mouse_entered.connect(func() -> void:
			if is_instance_valid(name_lbl):
				name_lbl.add_theme_color_override("font_color", col.lightened(0.25)))
		btn.mouse_exited.connect(func() -> void:
			if is_instance_valid(name_lbl):
				name_lbl.add_theme_color_override("font_color", col))
		btn.pressed.connect(func() -> void:
			_start_new_run(d, climb, l))
		_ui.add_child(btn)

	_add_menu_button("[ CANCEL ]", Vector2(560, row_y0 + float(TIERS.size()) * row_h + 14),
		Color(0.6, 0.6, 0.7), _close_menu)

func _start_new_run(diff: float, climb: float, loot: float) -> void:
	GameState.test_mode           = false
	GameState.starting_difficulty = diff
	GameState.starting_climb_rate = climb
	GameState.difficulty          = diff
	GameState.loot_multiplier     = loot
	GameState.save_settings()
	# NEW RUN explicitly discards any resumable save — the player chose
	# to reroll. carry_level still applies (it survives in autoload), so
	# leveling up in the village or via prior runs keeps that progression.
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	GameState.in_hub = false
	GameState.portals_used = 0
	GameState.kills        = 0
	GameState.damage_dealt = 0
	GameState.gold         = 0   # bank gold survives via PersistentStash
	# Wipe the run bag (grid) so the dungeon starts fresh, but keep the
	# equipped loadout.
	for i in InventoryManager.grid.size():
		InventoryManager.grid[i] = null
	InventoryManager.inventory_changed.emit()
	GameState.run_start_msec = Time.get_ticks_msec()
	get_tree().change_scene_to_file("res://scenes/World.tscn")

# ── Shared button helper ──────────────────────────────────────────────────

func _add_menu_button(text: String, pos: Vector2, col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.size = Vector2(240, 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", col)
	_ui.add_child(lbl)
	var btn := Button.new()
	btn.flat = true
	btn.position = pos
	btn.size = Vector2(240, 40)
	btn.mouse_entered.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", col.lightened(0.25)))
	btn.mouse_exited.connect(func() -> void:
		if is_instance_valid(lbl):
			lbl.add_theme_color_override("font_color", col))
	btn.pressed.connect(cb)
	_ui.add_child(btn)

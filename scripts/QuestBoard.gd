extends Area2D

# Village Quest Board — reads QuestLog autoload state and shows a
# scrolling overlay of every active quest with progress bars + reward
# preview. Click a quest to inspect its description + flavor.

var _player_in_range: bool = false
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("interactable")   # bullets pass through (Projectile group check)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.attach_fp_visual(self, "!", Color(1.0, 0.95, 0.45), 0.55)

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		_open()

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

func _open() -> void:
	if is_instance_valid(_ui):
		return
	_ui = CanvasLayer.new()
	_ui.layer = 28
	get_tree().current_scene.add_child(_ui)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_ui.add_child(dim)

	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.04, 0.10, 0.97)
	panel.position = Vector2(280, 100)
	panel.size = Vector2(1040, 700)
	_ui.add_child(panel)

	var border := ColorRect.new()
	border.color = Color(0.85, 0.65, 0.30, 0.65)
	border.position = Vector2(277, 97)
	border.size = Vector2(1046, 706)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— QUEST BOARD —"
	title.position = Vector2(280, 116)
	title.size = Vector2(1040, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.85, 0.65, 0.30))
	_ui.add_child(title)

	var sub := Label.new()
	sub.text = "Bank gold and legendary drops sent to your stash on completion."
	sub.position = Vector2(280, 168)
	sub.size = Vector2(1040, 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.add_theme_color_override("font_color", Color(0.6, 0.55, 0.7))
	_ui.add_child(sub)

	# Render each quest as one row: title, desc, progress bar, reward.
	var y: float = 210.0
	for q: Dictionary in QuestLog.QUESTS:
		var entry: Dictionary = QuestLog.state.get(q["id"], {"progress": 0, "complete": false})
		var prog: int = int(entry.get("progress", 0))
		var amount: int = int(q["amount"])
		var done: bool = bool(entry.get("complete", false))
		var ratio: float = clampf(float(prog) / float(maxi(1, amount)), 0.0, 1.0)
		var col: Color = Color(0.55, 0.95, 0.55) if done else Color(0.85, 0.85, 0.95)

		var name_lbl := Label.new()
		name_lbl.text = ("✓ " if done else "    ") + String(q["title"])
		name_lbl.position = Vector2(310, y)
		name_lbl.size = Vector2(360, 22)
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.add_theme_color_override("font_color", col)
		_ui.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = String(q["desc"])
		desc_lbl.position = Vector2(310, y + 22)
		desc_lbl.size = Vector2(640, 18)
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", col.darkened(0.30))
		_ui.add_child(desc_lbl)

		var bar_bg := ColorRect.new()
		bar_bg.color = Color(0.10, 0.10, 0.18)
		bar_bg.position = Vector2(680, y + 4)
		bar_bg.size = Vector2(320, 16)
		_ui.add_child(bar_bg)

		var bar_fg := ColorRect.new()
		bar_fg.color = col
		bar_fg.position = Vector2(681, y + 5)
		bar_fg.size = Vector2(318.0 * ratio, 14)
		_ui.add_child(bar_fg)

		var prog_lbl := Label.new()
		prog_lbl.text = "%d / %d" % [prog, amount]
		prog_lbl.position = Vector2(680, y + 22)
		prog_lbl.size = Vector2(320, 18)
		prog_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		prog_lbl.add_theme_font_size_override("font_size", 11)
		prog_lbl.add_theme_color_override("font_color", col.darkened(0.20))
		_ui.add_child(prog_lbl)

		var reward_str: String = "%dg" % int(q.get("reward_gold", 0))
		if bool(q.get("reward_legendary", false)):
			reward_str += "  +★ Legendary"
		var reward_lbl := Label.new()
		reward_lbl.text = reward_str
		reward_lbl.position = Vector2(1010, y + 4)
		reward_lbl.size = Vector2(180, 22)
		reward_lbl.add_theme_font_size_override("font_size", 12)
		reward_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
		_ui.add_child(reward_lbl)

		y += 70.0

	# Close button
	var close_lbl := Label.new()
	close_lbl.text = "[ CLOSE ]"
	close_lbl.position = Vector2(680, 760)
	close_lbl.size = Vector2(240, 30)
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.add_theme_font_size_override("font_size", 16)
	close_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_ui.add_child(close_lbl)
	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.position = Vector2(680, 760)
	close_btn.size = Vector2(240, 30)
	close_btn.pressed.connect(func() -> void: _ui.queue_free())
	_ui.add_child(close_btn)

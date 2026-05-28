extends Area2D

# Village Reroll Station — pay gold, randomize the distribution of points
# the player has accumulated in run_stat_bonuses (Shrine sacrifices etc).
# Per-visit lockout: only one reroll per village entry; the Reroller is
# rebuilt on every Village._ready() so the lockout resets naturally when
# the player descends and returns.
#
# Cost scales with player level so late-game rerolls aren't trivial:
#   cost = BASE_COST + LEVEL_SCALE * GameState.level
# A level-1 player pays ~75g; a level-20 player pays ~550g.

const BASE_COST: int  = 50
const LEVEL_SCALE: int = 25

var _player_in_range: bool = false
var _used: bool = false
var _ui: CanvasLayer = null

func _ready() -> void:
	add_to_group("interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.attach_fp_visual(self, "?", Color(0.95, 0.65, 1.0), 0.55)

func _process(_delta: float) -> void:
	if _player_in_range and Input.is_action_just_pressed("interact"):
		if is_instance_valid(_ui):
			_close()
		else:
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
		_close()

func _cost() -> int:
	return BASE_COST + LEVEL_SCALE * maxi(1, GameState.level)

func _total_points() -> int:
	var t: int = 0
	for k in GameState.run_stat_bonuses.keys():
		if k in GameState.STAT_NAMES:
			t += int(GameState.run_stat_bonuses[k])
	return t

func _open() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 28
	# Stay interactive while the game is paused below.
	_ui.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_ui)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ply := get_tree().get_first_node_in_group("player")
	if ply != null and ply.has_method("set_interface_open"):
		ply.set_interface_open(true)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.78)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	_ui.add_child(dim)

	var panel := ColorRect.new()
	panel.color = Color(0.07, 0.04, 0.12, 0.97)
	panel.position = Vector2(500, 230)
	panel.size = Vector2(600, 440)
	_ui.add_child(panel)

	var border := ColorRect.new()
	border.color = Color(0.95, 0.65, 1.0, 0.65)
	border.position = Vector2(497, 227)
	border.size = Vector2(606, 446)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— REROLL STATION —"
	title.position = Vector2(500, 248)
	title.size = Vector2(600, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.65, 1.0))
	_ui.add_child(title)

	var blurb := Label.new()
	blurb.text = "Pay gold to shuffle accumulated stat points across the eight stats.\nOnly one reroll per visit — descend and return to use it again."
	blurb.position = Vector2(520, 292)
	blurb.size = Vector2(560, 50)
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.add_theme_font_size_override("font_size", 13)
	blurb.add_theme_color_override("font_color", Color(0.65, 0.55, 0.80))
	_ui.add_child(blurb)

	# Current allocation listing.
	var alloc_lbl := Label.new()
	alloc_lbl.text = _format_allocation()
	alloc_lbl.position = Vector2(540, 354)
	alloc_lbl.size = Vector2(520, 180)
	alloc_lbl.add_theme_font_override("font", MonoFont.get_font())
	alloc_lbl.add_theme_font_size_override("font_size", 14)
	alloc_lbl.add_theme_color_override("font_color", Color(0.85, 0.78, 1.0))
	_ui.add_child(alloc_lbl)

	# Action button — colored by whether the reroll is currently available.
	var pts: int = _total_points()
	var can_reroll: bool = (not _used) and (pts > 0) and (GameState.gold >= _cost())
	var btn_text := "[ REROLL — %dg ]" % _cost()
	if _used:
		btn_text = "[ ALREADY USED ]"
	elif pts <= 0:
		btn_text = "[ NO POINTS TO SHUFFLE ]"
	elif GameState.gold < _cost():
		btn_text = "[ NEED %dg ]" % _cost()

	var btn_lbl := Label.new()
	btn_lbl.text = btn_text
	btn_lbl.position = Vector2(540, 580)
	btn_lbl.size = Vector2(520, 34)
	btn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn_lbl.add_theme_font_size_override("font_size", 18)
	btn_lbl.add_theme_color_override("font_color",
		Color(0.95, 0.65, 1.0) if can_reroll else Color(0.40, 0.30, 0.45))
	_ui.add_child(btn_lbl)

	var btn := Button.new()
	btn.flat = true
	btn.position = Vector2(540, 580)
	btn.size = Vector2(520, 34)
	btn.disabled = not can_reroll
	btn.pressed.connect(_do_reroll)
	_ui.add_child(btn)

	var close_hint := Label.new()
	close_hint.text = "[E] close"
	close_hint.position = Vector2(540, 630)
	close_hint.size = Vector2(520, 22)
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 12)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.4, 0.6))
	_ui.add_child(close_hint)

func _format_allocation() -> String:
	var lines: Array = []
	for s in GameState.STAT_NAMES:
		var v: int = int(GameState.run_stat_bonuses.get(s, 0))
		lines.append("  %s   %+d" % [s, v])
	lines.append("")
	lines.append("  Total reroll-able:  %d" % _total_points())
	lines.append("  Gold:               %dg" % GameState.gold)
	return "\n".join(lines)

func _do_reroll() -> void:
	if _used:
		return
	var pts: int = _total_points()
	if pts <= 0:
		return
	if GameState.gold < _cost():
		return
	GameState.gold -= _cost()
	# Clear current allocation across stats, then redistribute the same
	# total point count by drawing random stats one point at a time. This
	# preserves how many points the player invested but moves them around.
	for s in GameState.STAT_NAMES:
		GameState.run_stat_bonuses[s] = 0
	for i in pts:
		var pick: String = GameState.STAT_NAMES[randi() % GameState.STAT_NAMES.size()]
		GameState.run_stat_bonuses[pick] = int(GameState.run_stat_bonuses.get(pick, 0)) + 1
	_used = true
	# Refresh equip stats so derived numbers (HP, mana, regen) re-key off
	# the new allocation immediately.
	var p := get_tree().get_first_node_in_group("player")
	if p and p.has_method("update_equip_stats"):
		p.update_equip_stats()
	if SoundManager:
		SoundManager.play("save_run", randf_range(0.95, 1.05))
	FloatingText.spawn_str(global_position + Vector2(0, -48),
		"REROLLED!", Color(0.95, 0.65, 1.0), get_tree().current_scene)
	_close()

func _close() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()
		_ui = null
		var ply := get_tree().get_first_node_in_group("player")
		if ply != null and ply.has_method("set_interface_open"):
			ply.set_interface_open(false)
		process_mode = Node.PROCESS_MODE_INHERIT

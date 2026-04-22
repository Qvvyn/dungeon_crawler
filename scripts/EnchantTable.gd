extends Area2D

var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null
var _cell_rects: Array = []
var _cell_indices: Array = []

const REROLL_COST := 40
const CELL_W := 110.0
const CELL_H := 90.0
const GAP    := 8.0

# Value ranges for rerolling each stat
const STAT_RANGES := {
	"speed":              [10.0,  60.0],
	"max_health":         [1.0,   4.0],
	"fire_rate_reduction":[0.01,  0.09],
	"block_chance":       [0.05,  0.35],
	"projectile_count":   [1.0,   3.0],
}

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_hint = Label.new()
	_hint.text = "[E] Enchant"
	_hint.position = Vector2(-36.0, -32.0)
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(0.6, 0.3, 1.0))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint.add_theme_constant_override("outline_size", 2)
	add_child(_hint)

func _process(_delta: float) -> void:
	if _player_nearby and Input.is_action_just_pressed("interact"):
		if _popup == null:
			_open_popup()
		else:
			_close_popup()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		_hint.visible = true

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_hint.visible = false
		_close_popup()

# ── Popup ─────────────────────────────────────────────────────────────────────

func _open_popup() -> void:
	_popup = CanvasLayer.new()
	_popup.layer = 12
	get_tree().current_scene.add_child(_popup)
	_build_ui()

func _build_ui() -> void:
	for child in _popup.get_children():
		child.free()
	_cell_rects.clear()
	_cell_indices.clear()

	# Only show rerollable (non-legendary) items with stat bonuses
	var rerollable: Array = []
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i]
		if item != null and item.rarity != Item.RARITY_LEGENDARY and not item.stat_bonuses.is_empty():
			rerollable.append(i)

	var count   := rerollable.size()
	var cols    := clampi(count, 1, 8)
	var rows    := ceili(float(maxi(count, 1)) / float(cols))
	var row_w   := float(cols) * CELL_W + float(cols - 1) * GAP
	var panel_w := row_w + 48.0
	var panel_h := 56.0 + float(rows) * (CELL_H + GAP) + 24.0
	var ox      := (1600.0 - panel_w) / 2.0
	var oy      := (900.0 - panel_h) / 2.0

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.12, 0.97)
	bg.position = Vector2(ox, oy)
	bg.size = Vector2(panel_w, panel_h)
	_popup.add_child(bg)

	var strip := ColorRect.new()
	strip.color = Color(0.5, 0.1, 0.9, 1.0)
	strip.position = Vector2(ox, oy)
	strip.size = Vector2(panel_w, 3.0)
	_popup.add_child(strip)

	var title := Label.new()
	title.text = "✦  ENCHANTING TABLE  ✦   —   %dg per reroll   |   [E] close" % REROLL_COST
	title.position = Vector2(ox, oy + 8.0)
	title.size = Vector2(panel_w, 22.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0))
	_popup.add_child(title)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: " + str(GameState.gold) + "g"
	gold_lbl.position = Vector2(ox, oy + 30.0)
	gold_lbl.size = Vector2(panel_w, 18.0)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_popup.add_child(gold_lbl)

	if count == 0:
		var empty := Label.new()
		empty.text = "No rerollable items in bag."
		empty.position = Vector2(ox, oy + 56.0)
		empty.size = Vector2(panel_w, 28.0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_popup.add_child(empty)
		return

	var cells_ox := ox + (panel_w - row_w) / 2.0
	var cy := oy + 54.0
	for i in count:
		var grid_idx: int = rerollable[i]
		var item: Item = InventoryManager.grid[grid_idx]
		var col_i := i % cols
		var row_i := i / cols
		var ix := cells_ox + float(col_i) * (CELL_W + GAP)
		var iy := cy + float(row_i) * (CELL_H + GAP)

		_cell_rects.append(Rect2(ix, iy, CELL_W, CELL_H))
		_cell_indices.append(grid_idx)

		var can_afford := GameState.gold >= REROLL_COST
		var cell := ColorRect.new()
		cell.color = item.color.darkened(0.55)
		cell.position = Vector2(ix, iy)
		cell.size = Vector2(CELL_W, CELL_H)
		_popup.add_child(cell)

		# Build stat summary string
		var stat_str := ""
		for key in item.stat_bonuses:
			stat_str += key.substr(0, 4) + ":" + ("%.2f" % item.stat_bonuses[key]) + " "

		var lbl := Label.new()
		lbl.text = item.icon_char + " " + item.display_name + "\n" + stat_str.strip_edges() + "\n[REROLL %dg]" % REROLL_COST
		lbl.position = Vector2(ix + 4.0, iy + 4.0)
		lbl.size = Vector2(CELL_W - 8.0, CELL_H - 8.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color",
			item.color.lightened(0.3) if can_afford else item.color.darkened(0.3))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_popup.add_child(lbl)

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_cell_rects.clear()
	_cell_indices.clear()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _popup == null or not _player_nearby:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var mp := get_viewport().get_mouse_position()
	for i in _cell_rects.size():
		if not _cell_rects[i].has_point(mp):
			continue
		if GameState.gold < REROLL_COST:
			var player := InventoryManager._player_ref
			if player:
				FloatingText.spawn_str(player.global_position,
					"Need " + str(REROLL_COST) + "g",
					Color(1.0, 0.3, 0.3), get_tree().current_scene)
		else:
			var grid_idx: int = _cell_indices[i]
			var item: Item = InventoryManager.grid[grid_idx]
			if item != null:
				GameState.gold -= REROLL_COST
				_reroll(item)
				InventoryManager.inventory_changed.emit()
				_build_ui()
		get_viewport().set_input_as_handled()
		return

func _reroll(item: Item) -> void:
	var new_bonuses := {}
	for key in item.stat_bonuses:
		if key in STAT_RANGES:
			var range_arr: Array = STAT_RANGES[key]
			var lo: float = range_arr[0]
			var hi: float = range_arr[1]
			if key == "max_health" or key == "projectile_count":
				new_bonuses[key] = float(randi_range(int(lo), int(hi)))
			else:
				new_bonuses[key] = randf_range(lo, hi)
		else:
			new_bonuses[key] = item.stat_bonuses[key]
	item.stat_bonuses = new_bonuses
	# Reapply equip stats in case this item is equipped
	var player := InventoryManager._player_ref
	if player and player.has_method("update_equip_stats"):
		player.update_equip_stats()

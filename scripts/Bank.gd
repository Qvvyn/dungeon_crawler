extends Area2D

# Village Bank — persistent cross-run storage. Click an item in your run
# inventory to deposit it; click one in the stash to withdraw it.
# Bank Gold survives runs; per-run Gold does not.

var _player_in_range: bool = false
var _ui: CanvasLayer = null
var _grid_btn_holder: Control = null
var _stash_btn_holder: Control = null
var _gold_label: Label = null

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

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

# ── UI ─────────────────────────────────────────────────────────────────────

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
	panel.position = Vector2(180, 100)
	panel.size = Vector2(1240, 700)
	_ui.add_child(panel)

	var border := ColorRect.new()
	border.color = Color(1.0, 0.85, 0.30, 0.65)
	border.position = Vector2(177, 97)
	border.size = Vector2(1246, 706)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— WIZARD'S BANK —"
	title.position = Vector2(180, 116)
	title.size = Vector2(1240, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_ui.add_child(title)

	# Gold strip — run gold on the left, bank gold on the right, with
	# deposit / withdraw buttons in between.
	_gold_label = Label.new()
	_gold_label.position = Vector2(180, 168)
	_gold_label.size = Vector2(1240, 40)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 18)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_ui.add_child(_gold_label)

	var deposit_gold_btn := _make_text_button("[ DEPOSIT GOLD → ]",
		Vector2(420, 214), Vector2(220, 36), Color(0.55, 0.95, 0.6),
		_deposit_all_gold)
	_ui.add_child(deposit_gold_btn["btn"])
	_ui.add_child(deposit_gold_btn["lbl"])

	var withdraw_gold_btn := _make_text_button("[ ← WITHDRAW GOLD ]",
		Vector2(960, 214), Vector2(220, 36), Color(0.85, 0.7, 1.0),
		_withdraw_all_gold)
	_ui.add_child(withdraw_gold_btn["btn"])
	_ui.add_child(withdraw_gold_btn["lbl"])

	# Two columns of items: run inventory (left) and stash (right).
	var left_title := Label.new()
	left_title.text = "RUN INVENTORY  (click to deposit)"
	left_title.position = Vector2(220, 270)
	left_title.size = Vector2(560, 28)
	left_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left_title.add_theme_font_size_override("font_size", 16)
	left_title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.55))
	_ui.add_child(left_title)

	var right_title := Label.new()
	right_title.text = "BANK STASH  (click to withdraw)"
	right_title.position = Vector2(820, 270)
	right_title.size = Vector2(560, 28)
	right_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right_title.add_theme_font_size_override("font_size", 16)
	right_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_ui.add_child(right_title)

	_grid_btn_holder = Control.new()
	_grid_btn_holder.position = Vector2(220, 308)
	_grid_btn_holder.size = Vector2(560, 440)
	_ui.add_child(_grid_btn_holder)

	_stash_btn_holder = Control.new()
	_stash_btn_holder.position = Vector2(820, 308)
	_stash_btn_holder.size = Vector2(560, 440)
	_ui.add_child(_stash_btn_holder)

	# Close button
	var close := _make_text_button("[ CLOSE ]",
		Vector2(680, 760), Vector2(240, 36), Color(0.75, 0.75, 0.85),
		func() -> void: _close())
	_ui.add_child(close["btn"])
	_ui.add_child(close["lbl"])

	_refresh_all()

func _close() -> void:
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null

func _refresh_all() -> void:
	_refresh_gold()
	_refresh_grid_column()
	_refresh_stash_column()

func _refresh_gold() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Run Gold: %d        Bank Gold: %d" % [
		GameState.gold, PersistentStash.bank_gold]

func _refresh_grid_column() -> void:
	if _grid_btn_holder == null:
		return
	for c in _grid_btn_holder.get_children():
		c.queue_free()
	var rows: int = 12
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		var b := _item_button(item, _grid_btn_holder.get_child_count(), rows)
		var idx := i
		b.pressed.connect(func() -> void: _deposit(idx))
		_grid_btn_holder.add_child(b)

func _refresh_stash_column() -> void:
	if _stash_btn_holder == null:
		return
	for c in _stash_btn_holder.get_children():
		c.queue_free()
	var rows: int = 12
	for i in PersistentStash.slots.size():
		var item: Item = PersistentStash.slots[i] as Item
		if item == null:
			continue
		var b := _item_button(item, _stash_btn_holder.get_child_count(), rows)
		var idx := i
		b.pressed.connect(func() -> void: _withdraw(idx))
		_stash_btn_holder.add_child(b)

func _item_button(item: Item, idx: int, rows: int) -> Button:
	@warning_ignore("integer_division")
	var col_n: int = idx / rows
	var row_n: int = idx % rows
	var b := Button.new()
	b.text = item.display_name if item.display_name != "" else "?"
	b.position = Vector2(col_n * 280, row_n * 36)
	b.size = Vector2(270, 32)
	b.flat = true
	b.add_theme_font_size_override("font_size", 13)
	b.add_theme_color_override("font_color", _rarity_color(item.rarity))
	b.add_theme_color_override("font_color_hover", _rarity_color(item.rarity).lightened(0.30))
	return b

func _rarity_color(rarity: int) -> Color:
	match rarity:
		Item.RARITY_LEGENDARY: return Color(1.0, 0.6, 0.2)
		Item.RARITY_RARE:      return Color(0.55, 0.7, 1.0)
		_:                     return Color(0.85, 0.85, 0.95)

func _deposit(grid_idx: int) -> void:
	var it: Item = InventoryManager.grid[grid_idx] as Item
	if it == null:
		return
	if not PersistentStash.deposit(it):
		FloatingText.spawn_str(global_position, "STASH FULL",
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	InventoryManager.grid[grid_idx] = null
	InventoryManager.inventory_changed.emit()
	_refresh_all()

func _withdraw(stash_idx: int) -> void:
	var it: Item = PersistentStash.slots[stash_idx] as Item
	if it == null:
		return
	# Try to find an empty grid slot first.
	for i in InventoryManager.grid.size():
		if InventoryManager.grid[i] == null:
			InventoryManager.grid[i] = it
			PersistentStash.withdraw(stash_idx)
			InventoryManager.inventory_changed.emit()
			_refresh_all()
			return
	FloatingText.spawn_str(global_position, "INVENTORY FULL",
		Color(1.0, 0.4, 0.4), get_tree().current_scene)

func _deposit_all_gold() -> void:
	if GameState.gold <= 0:
		return
	PersistentStash.add_gold(GameState.gold)
	GameState.gold = 0
	_refresh_gold()

func _withdraw_all_gold() -> void:
	if PersistentStash.bank_gold <= 0:
		return
	GameState.gold += PersistentStash.bank_gold
	PersistentStash.bank_gold = 0
	PersistentStash.add_gold(0)   # forces save
	_refresh_gold()

# ── Helpers ────────────────────────────────────────────────────────────────

func _make_text_button(text: String, pos: Vector2, sz: Vector2,
		col: Color, cb: Callable) -> Dictionary:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = pos
	lbl.size = sz
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", col)
	var btn := Button.new()
	btn.text = ""
	btn.flat = true
	btn.position = pos
	btn.size = sz
	btn.pressed.connect(cb)
	return {"btn": btn, "lbl": lbl}

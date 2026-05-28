extends Area2D

# Village Bank — persistent cross-run storage. Click an item in your run
# inventory to deposit it; click one in the stash to withdraw it.
# Bank Gold survives runs; per-run Gold does not.

var _player_in_range: bool = false
var _ui: CanvasLayer = null
var _grid_btn_holder: Control = null
var _stash_btn_holder: Control = null
var _equip_btn_holder: Control = null
var _gold_label: Label = null

func _ready() -> void:
	add_to_group("interactable")   # bullets pass through (Projectile group check)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.attach_fp_visual(self, "B", Color(0.55, 1.0, 0.55), 0.55)

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

	# Three columns of items: equipped (left), run bag (middle), stash
	# (right). Equipped column lets the player bank their kit (e.g. swap
	# wands between runs without losing anything).
	var equip_title := Label.new()
	equip_title.text = "EQUIPPED  (click to unequip + deposit)"
	equip_title.position = Vector2(200, 270)
	equip_title.size = Vector2(380, 28)
	equip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_title.add_theme_font_size_override("font_size", 14)
	equip_title.add_theme_color_override("font_color", Color(0.85, 0.6, 1.0))
	_ui.add_child(equip_title)

	var bag_title := Label.new()
	bag_title.text = "RUN BAG  (click to deposit)"
	bag_title.position = Vector2(600, 270)
	bag_title.size = Vector2(400, 28)
	bag_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bag_title.add_theme_font_size_override("font_size", 14)
	bag_title.add_theme_color_override("font_color", Color(0.85, 0.95, 0.55))
	_ui.add_child(bag_title)

	var stash_title := Label.new()
	stash_title.text = "BANK STASH  (click to withdraw)"
	stash_title.position = Vector2(1020, 270)
	stash_title.size = Vector2(380, 28)
	stash_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stash_title.add_theme_font_size_override("font_size", 14)
	stash_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	_ui.add_child(stash_title)

	_equip_btn_holder = Control.new()
	_equip_btn_holder.position = Vector2(200, 308)
	_equip_btn_holder.size = Vector2(380, 440)
	_ui.add_child(_equip_btn_holder)

	_grid_btn_holder = Control.new()
	_grid_btn_holder.position = Vector2(600, 308)
	_grid_btn_holder.size = Vector2(400, 440)
	_ui.add_child(_grid_btn_holder)

	_stash_btn_holder = Control.new()
	_stash_btn_holder.position = Vector2(1020, 308)
	_stash_btn_holder.size = Vector2(380, 440)
	_ui.add_child(_stash_btn_holder)

	# Close button
	var close := _make_text_button("[ CLOSE ]",
		Vector2(680, 760), Vector2(240, 36), Color(0.75, 0.75, 0.85),
		func() -> void: _close())
	_ui.add_child(close["btn"])
	_ui.add_child(close["lbl"])

	_refresh_all()

func _close() -> void:
	var was_open := is_instance_valid(_ui)
	if is_instance_valid(_ui):
		_ui.queue_free()
	_ui = null
	if was_open:
		var ply := get_tree().get_first_node_in_group("player")
		if ply != null and ply.has_method("set_interface_open"):
			ply.set_interface_open(false)
		process_mode = Node.PROCESS_MODE_INHERIT

func _refresh_all() -> void:
	_refresh_gold()
	_refresh_equip_column()
	_refresh_grid_column()
	_refresh_stash_column()

func _refresh_equip_column() -> void:
	if _equip_btn_holder == null:
		return
	for c in _equip_btn_holder.get_children():
		c.queue_free()
	# Show every equip slot in a fixed order so the layout doesn't jump.
	# Empty slots render as dim placeholders; the player can see at a
	# glance what's filled vs open.
	var slots: Array = ["wand", "hat", "robes", "feet", "ring", "necklace"]
	for i in slots.size():
		var slot_name: String = slots[i]
		var item: Item = InventoryManager.equipped.get(slot_name) as Item
		var b := Button.new()
		b.position = Vector2(0, i * 36)
		b.size = Vector2(370, 32)
		b.flat = true
		b.add_theme_font_size_override("font_size", 13)
		if item == null:
			b.text = "%s :  (empty)" % slot_name.to_upper()
			b.disabled = true
			b.add_theme_color_override("font_color_disabled",
				Color(0.45, 0.40, 0.55))
		else:
			b.text = "%s :  %s" % [slot_name.to_upper(), item.display_name]
			b.add_theme_color_override("font_color", _rarity_color(item.rarity))
			b.add_theme_color_override("font_color_hover",
				_rarity_color(item.rarity).lightened(0.30))
			b.pressed.connect(func() -> void: _deposit_equipped(slot_name))
		_equip_btn_holder.add_child(b)

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
	var rows: int = 13
	# Use the actual grid index (i) to lay out the button — NOT
	# get_child_count(). With get_child_count(), depositing an item
	# would empty its slot in the grid, the next refresh would skip
	# the now-null slot, and every later item would renumber and
	# visually shift up one row. Anchoring on `i` keeps each item
	# fixed at its grid position.
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		var b := _item_button(item, i, rows)
		var idx := i
		b.pressed.connect(func() -> void: _deposit(idx))
		_grid_btn_holder.add_child(b)

func _refresh_stash_column() -> void:
	if _stash_btn_holder == null:
		return
	for c in _stash_btn_holder.get_children():
		c.queue_free()
	var rows: int = 13
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
	b.position = Vector2(col_n * 190, row_n * 32)
	b.size = Vector2(184, 28)
	b.flat = true
	b.add_theme_font_size_override("font_size", 12)
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

func _deposit_equipped(slot_name: String) -> void:
	var it: Item = InventoryManager.equipped.get(slot_name) as Item
	if it == null:
		return
	if not PersistentStash.deposit(it):
		FloatingText.spawn_str(global_position, "STASH FULL",
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	# Wand path goes through the wand-row helper so equipped["wand"] is
	# kept in sync with grid[active_wand_slot]. Other slots assign null
	# directly since they don't share state with the grid.
	if slot_name == "wand":
		# Find which wand slot this Item lives in and clear it. Then
		# resync — the active pointer may need to skip to the next held
		# wand or fall back to null.
		for i in InventoryManager.WAND_SLOTS:
			if InventoryManager.grid[i] == it:
				InventoryManager.grid[i] = null
		InventoryManager._sync_active_wand()
	else:
		InventoryManager.equipped[slot_name] = null
		# Clear any matching grid copy too — auto-equip historically
		# leaves the same Item in both the equipped slot and the bag.
		for i in InventoryManager.grid.size():
			if InventoryManager.grid[i] == it:
				InventoryManager.grid[i] = null
	InventoryManager.inventory_changed.emit()
	# Notify Player so equip-stat caches recompute.
	var p := get_tree().get_first_node_in_group("player")
	if p != null and p.has_method("update_equip_stats"):
		p.call("update_equip_stats")
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

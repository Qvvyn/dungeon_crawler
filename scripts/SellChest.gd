extends Area2D

var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null

# Shop (legendaries to buy)
var _shop_stock: Array = []   # Array of Item
var _shop_bought: Array = []  # Array of bool

# Parallel rect lists rebuilt each _build_ui call
var _buy_rects: Array = []
var _sell_rects: Array = []
var _sell_grid_indices: Array = []

const SHOP_SLOTS := 3
const CELL_W     := 120.0
const CELL_H     := 95.0
const GAP        := 10.0

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_hint = Label.new()
	_hint.text = "[E] Arcane Shop"
	_hint.position = Vector2(-50.0, -38.0)
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_hint.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_hint.add_theme_constant_override("outline_size", 2)
	add_child(_hint)

	# Randomise a fixed legendary stock for this chest
	var pool := ItemDB.legendary_items()
	pool.shuffle()
	for i in mini(SHOP_SLOTS, pool.size()):
		_shop_stock.append(pool[i])
		_shop_bought.append(false)

func _process(_delta: float) -> void:
	if _player_nearby and Input.is_action_just_pressed("interact"):
		if _popup == null:
			_open_popup()
		else:
			_close_popup()

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = true
		if _hint:
			_hint.visible = true
		# Autoplay: sell junk and buy any affordable upgrade automatically.
		if body.get("_autoplay") == true:
			_auto_use(body)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if _hint:
			_hint.visible = false
		_close_popup()

# Autoplay handler — silently runs the optimal actions at this chest:
#   1) Buy any legendary in stock that is a strict upgrade for its slot
#      (compared with whatever's currently equipped). Wands use the
#      player's _wand_score so flaws/cost are factored in.
#   2) Sell anything in the bag that isn't an upgrade for its slot, isn't
#      a wand (handled separately by the wand cap / shatter sweep), and
#      isn't a stack of potions.
func _auto_use(player: Node) -> void:
	# --- Buy upgrades first so we don't sell off gold we'd need ---
	for i in _shop_stock.size():
		if _shop_bought[i]:
			continue
		var item: Item = _shop_stock[i]
		var price: int = int(round(float(item.sell_value) * 2.0 * GameState.price_multiplier()))
		if GameState.gold < price:
			continue
		var slot := item.get_equip_slot_name()
		if slot == "":
			continue   # offhand etc. — currently disabled
		var current: Item = InventoryManager.equipped.get(slot) as Item
		var is_upgrade := false
		if slot == "wand" and player.has_method("_wand_score"):
			# Wand comparison via the bot's own scoring — rarity alone misses
			# flaw-laden legendaries that a clean rare actually beats.
			is_upgrade = current == null \
				or float(player.call("_wand_score", item)) > float(player.call("_wand_score", current)) * 1.05
		else:
			is_upgrade = current == null or item.rarity > current.rarity
		if is_upgrade:
			GameState.gold -= price
			_shop_bought[i] = true
			InventoryManager.add_item(item)
			FloatingText.spawn_str(player.global_position,
				"BOUGHT %s" % item.display_name,
				Color(1.0, 0.85, 0.25), get_tree().current_scene)
	# --- Sell junk ---
	# Build a set of equipped item ids so we never sell something currently
	# slotted (auto-equip leaves the equipped wand mirrored in the grid).
	var eq_ids := {}
	for slot in InventoryManager.EQUIP_SLOTS:
		var it: Item = InventoryManager.equipped.get(slot)
		if it != null:
			eq_ids[it.get_instance_id()] = true
	var sold_total := 0
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		if eq_ids.has(item.get_instance_id()):
			continue
		# Hold onto wands — the wand cap / shatter sweep manages those.
		# Hold onto potion stacks (they're our heal supply).
		if item.type == Item.Type.WAND or item.type == Item.Type.POTION:
			continue
		# If this item is a strict upgrade for its slot, skip — auto-equip
		# may use it next tick. Otherwise, sell.
		var slot2 := item.get_equip_slot_name()
		if slot2 != "":
			var cur2: Item = InventoryManager.equipped.get(slot2) as Item
			if cur2 == null or item.rarity > cur2.rarity:
				continue
		GameState.gold += item.sell_value
		sold_total += item.sell_value
		InventoryManager.grid[i] = null
	if sold_total > 0:
		FloatingText.spawn(player.global_position, sold_total, true,
			get_tree().current_scene, Color(1.0, 0.85, 0.1))
	InventoryManager.inventory_changed.emit()
	if player.has_method("update_equip_stats"):
		player.update_equip_stats()

# ── Popup ─────────────────────────────────────────────────────────────────────

func _open_popup() -> void:
	_popup = CanvasLayer.new()
	_popup.layer = 12
	get_tree().current_scene.add_child(_popup)
	_build_ui()

func _build_ui() -> void:
	for child in _popup.get_children():
		child.free()
	_buy_rects.clear()
	_sell_rects.clear()
	_sell_grid_indices.clear()

	# --- Pre-calculate layout ---
	var shop_count := _shop_stock.size()
	var shop_row_w := float(shop_count) * CELL_W + float(shop_count - 1) * GAP

	var sellable: Array = []
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i]
		if item != null:
			sellable.append(i)
	var sell_count  := sellable.size()
	var sell_cols   := clampi(sell_count, 1, 10)
	var sell_rows   := ceili(float(maxi(sell_count, 1)) / float(sell_cols))
	var sell_row_w  := float(sell_cols) * CELL_W + float(sell_cols - 1) * GAP

	var panel_w := maxf(shop_row_w, sell_row_w) + 48.0

	# Fixed top area height: title(26) + gold_lbl(22) + shop_row(CELL_H) + gap(16)
	#   + divider(6) + sell_header(24) = 94 + CELL_H
	var fixed_h    := 8.0 + 26.0 + 22.0 + CELL_H + 16.0 + 6.0 + 24.0
	var sell_content_h: float
	if sell_count == 0:
		sell_content_h = 28.0
	else:
		sell_content_h = float(sell_rows - 1) * GAP + float(sell_rows) * CELL_H
	var panel_h := fixed_h + sell_content_h + 24.0

	var ox := (1600.0 - panel_w) / 2.0
	var oy := (900.0 - panel_h) / 2.0

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.12, 0.97)
	bg.position = Vector2(ox, oy)
	bg.size = Vector2(panel_w, panel_h)
	_popup.add_child(bg)

	# Gold accent strip
	var strip := ColorRect.new()
	strip.color = Color(0.7, 0.5, 0.0, 1.0)
	strip.position = Vector2(ox, oy)
	strip.size = Vector2(panel_w, 3.0)
	_popup.add_child(strip)

	var cy := oy + 8.0

	# Shop title
	var title := Label.new()
	title.text = "★  ARCANE SHOP  ★"
	title.position = Vector2(ox, cy)
	title.size = Vector2(panel_w, 24.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_popup.add_child(title)
	cy += 26.0

	# Gold display
	var gold_lbl := Label.new()
	gold_lbl.text = "Your gold: " + str(GameState.gold) + "g   |   [E] close"
	gold_lbl.position = Vector2(ox, cy)
	gold_lbl.size = Vector2(panel_w, 18.0)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_popup.add_child(gold_lbl)
	cy += 22.0

	# Shop item cells
	var shop_ox := ox + (panel_w - shop_row_w) / 2.0
	for i in shop_count:
		var item: Item = _shop_stock[i]
		var bought: bool = _shop_bought[i]
		var buy_price := int(round(float(item.sell_value) * 2.0 * GameState.price_multiplier()))
		var can_afford := (not bought) and (GameState.gold >= buy_price)

		var ix := shop_ox + float(i) * (CELL_W + GAP)
		var iy := cy
		_buy_rects.append(Rect2(ix, iy, CELL_W, CELL_H))

		var cell := ColorRect.new()
		cell.color = Color(0.1, 0.1, 0.1) if bought else item.color.darkened(0.58)
		cell.position = Vector2(ix, iy)
		cell.size = Vector2(CELL_W, CELL_H)
		_popup.add_child(cell)

		# Gold border for available legendary
		if not bought:
			var border := ColorRect.new()
			border.color = Color(0.8, 0.6, 0.0, 1.0)
			border.position = Vector2(ix, iy)
			border.size = Vector2(CELL_W, 2.0)
			_popup.add_child(border)
			var border2 := ColorRect.new()
			border2.color = Color(0.8, 0.6, 0.0, 1.0)
			border2.position = Vector2(ix, iy + CELL_H - 2.0)
			border2.size = Vector2(CELL_W, 2.0)
			_popup.add_child(border2)

		var txt_col: Color
		if bought:
			txt_col = Color(0.35, 0.35, 0.35)
		elif can_afford:
			txt_col = item.color.lightened(0.45)
		else:
			txt_col = item.color.darkened(0.25)

		# Icon + name (upper portion)
		var name_txt := ("★ " if not bought else "") + item.icon_char + " " + item.display_name
		var name_lbl := Label.new()
		name_lbl.text = name_txt
		name_lbl.position = Vector2(ix + 4.0, iy + 4.0)
		name_lbl.size = Vector2(CELL_W - 8.0, CELL_H - 26.0)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 10)
		name_lbl.add_theme_color_override("font_color", txt_col)
		name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_popup.add_child(name_lbl)

		# Price / status (bottom strip)
		var price_txt := "[PURCHASED]" if bought else str(buy_price) + "g"
		var price_lbl := Label.new()
		price_lbl.text = price_txt
		price_lbl.position = Vector2(ix + 4.0, iy + CELL_H - 22.0)
		price_lbl.size = Vector2(CELL_W - 8.0, 18.0)
		price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		price_lbl.add_theme_font_size_override("font_size", 11)
		price_lbl.add_theme_color_override("font_color", txt_col)
		_popup.add_child(price_lbl)

	cy += CELL_H + 16.0

	# Divider
	var div := ColorRect.new()
	div.color = Color(0.35, 0.28, 0.5, 0.9)
	div.position = Vector2(ox + 12.0, cy)
	div.size = Vector2(panel_w - 24.0, 1.0)
	_popup.add_child(div)
	cy += 6.0

	# Sell section header
	var sell_hdr := Label.new()
	sell_hdr.text = "SELL ITEMS"
	sell_hdr.position = Vector2(ox, cy)
	sell_hdr.size = Vector2(panel_w, 22.0)
	sell_hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_hdr.add_theme_font_size_override("font_size", 12)
	sell_hdr.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
	_popup.add_child(sell_hdr)
	cy += 24.0

	if sell_count == 0:
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing in bag to sell."
		empty_lbl.position = Vector2(ox, cy)
		empty_lbl.size = Vector2(panel_w, 28.0)
		empty_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_lbl.add_theme_font_size_override("font_size", 12)
		empty_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_popup.add_child(empty_lbl)
	else:
		var sell_ox := ox + (panel_w - sell_row_w) / 2.0
		for i in sell_count:
			var grid_idx: int = sellable[i]
			var item: Item = InventoryManager.grid[grid_idx]
			var col_i := i % sell_cols
			var row_i := i / sell_cols
			var ix := sell_ox + float(col_i) * (CELL_W + GAP)
			var iy := cy + float(row_i) * (CELL_H + GAP)

			_sell_rects.append(Rect2(ix, iy, CELL_W, CELL_H))
			_sell_grid_indices.append(grid_idx)

			var cell := ColorRect.new()
			cell.color = item.color.darkened(0.5)
			cell.position = Vector2(ix, iy)
			cell.size = Vector2(CELL_W, CELL_H)
			_popup.add_child(cell)

			var s_name_lbl := Label.new()
			s_name_lbl.text = item.icon_char + " " + item.display_name
			s_name_lbl.position = Vector2(ix + 4.0, iy + 4.0)
			s_name_lbl.size = Vector2(CELL_W - 8.0, CELL_H - 26.0)
			s_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_name_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			s_name_lbl.add_theme_font_size_override("font_size", 10)
			s_name_lbl.add_theme_color_override("font_color", item.color.lightened(0.3))
			s_name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_popup.add_child(s_name_lbl)

			var s_price_lbl := Label.new()
			s_price_lbl.text = str(item.sell_value) + "g  [click to sell]"
			s_price_lbl.position = Vector2(ix + 4.0, iy + CELL_H - 22.0)
			s_price_lbl.size = Vector2(CELL_W - 8.0, 18.0)
			s_price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			s_price_lbl.add_theme_font_size_override("font_size", 10)
			s_price_lbl.add_theme_color_override("font_color", item.color.lightened(0.3))
			_popup.add_child(s_price_lbl)

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_buy_rects.clear()
	_sell_rects.clear()
	_sell_grid_indices.clear()

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

	# Buy clicks
	for i in _buy_rects.size():
		var r: Rect2 = _buy_rects[i]
		if r.has_point(mp):
			if i < _shop_stock.size() and not _shop_bought[i]:
				var item: Item = _shop_stock[i]
				var price := int(round(float(item.sell_value) * 2.0 * GameState.price_multiplier()))
				if GameState.gold >= price:
					GameState.gold -= price
					_shop_bought[i] = true
					InventoryManager.add_item(item)
					var player := InventoryManager._player_ref
					if player:
						FloatingText.spawn_str(player.global_position,
							"-" + str(price) + "g",
							Color(1.0, 0.75, 0.1), get_tree().current_scene)
					_build_ui()
				else:
					var player := InventoryManager._player_ref
					if player:
						var price_val := int(round(float(item.sell_value) * 2.0 * GameState.price_multiplier()))
						FloatingText.spawn_str(player.global_position,
							"Need " + str(price_val) + "g",
							Color(1.0, 0.3, 0.3), get_tree().current_scene)
			get_viewport().set_input_as_handled()
			return

	# Sell clicks
	for i in _sell_rects.size():
		if i >= _sell_grid_indices.size():
			break
		var r: Rect2 = _sell_rects[i]
		if r.has_point(mp):
			var grid_idx: int = _sell_grid_indices[i]
			var item: Item = InventoryManager.grid[grid_idx]
			if item != null:
				GameState.gold += item.sell_value
				var player := InventoryManager._player_ref
				if player:
					FloatingText.spawn(player.global_position, item.sell_value,
						true, get_tree().current_scene, Color(1.0, 0.85, 0.1))
				InventoryManager.grid[grid_idx] = null
				InventoryManager.inventory_changed.emit()
				_build_ui()
			get_viewport().set_input_as_handled()
			return

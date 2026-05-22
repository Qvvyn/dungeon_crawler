extends Area2D

var items: Array = []
var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null
# Visible-cell tracking. _popup_rects is parallel to _popup_item_indices —
# index i in both corresponds to the i-th rendered cell. The actual items[]
# index is _popup_item_indices[i], which differs from i when the popup is
# scrolled. Hit detection maps clicks → cell rect → real items[] index.
var _popup_rects: Array = []
var _popup_item_indices: Array = []
# Scroll offset (in rows). Mouse wheel scrolls a row at a time. Reset to
# 0 every time the popup opens so a returning visit starts at the top.
var _scroll_offset_rows: int = 0
const MAX_VISIBLE_ROWS: int = 5
# Mega bag — set true by World._on_room_cleared when this bag is the
# room-clear merge of all the floor's loose bags. Drives a bigger, fancier
# glyph so the convergence payoff reads as a real reward, not just another
# regular bag with a long item list.
var is_mega: bool = false

func _ready() -> void:
	add_to_group("loot_bag")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	# Only generate random items if none were pre-set (e.g. from a discard)
	if items.is_empty():
		var count := randi_range(1, 3)
		for _i in count:
			items.append(ItemDB.random_drop())
	# Pre-stack identical stackables (gems, coins, crystals, potions) so a
	# mega bag merging three sub-bags doesn't display "Gem", "Gem", "Gem"
	# in three separate cells. Mirrors the cap behaviour of the inventory
	# (Item.STACK_CAP per cell, with overflow into additional cells).
	_merge_stacks()

	# Re-style the Visual label for the multi-line ASCII bag glyph that
	# _recolor_by_rarity stamps in. Mega bags get a bigger, fancier 4-row
	# silhouette and a wider label box; regular bags keep the compact 5×2
	# drawstring sack.
	var visual := get_node_or_null("Visual") as Label
	if visual:
		if is_mega:
			visual.add_theme_font_size_override("font_size", 18)
			visual.add_theme_constant_override("line_separation", -4)
			visual.offset_left   = -38.0
			visual.offset_top    = -32.0
			visual.offset_right  =  38.0
			visual.offset_bottom =  32.0
		else:
			visual.add_theme_font_size_override("font_size", 13)
			visual.add_theme_constant_override("line_separation", -3)
			visual.offset_left   = -20.0
			visual.offset_top    = -14.0
			visual.offset_right  =  20.0
			visual.offset_bottom =  14.0

	_recolor_by_rarity()

	_hint = Label.new()
	_hint.text = "[E] Loot"
	_hint.position = Vector2(-28.0, -38.0)
	_hint.visible = false
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
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
		if _hint:
			_hint.visible = true
		# Auto-pickup of health potions — always grabbed on walk-over so
		# the player doesn't need to E-loot a bag just for a stack of pots.
		# Other items still require the popup interact. If only potions
		# were in the bag, it disappears once they're consumed.
		_auto_grab_potions()

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		if _hint:
			_hint.visible = false
		_close_popup()

# ── Popup ─────────────────────────────────────────────────────────────────────

func _open_popup() -> void:
	if items.is_empty():
		queue_free()
		return

	# Sort by type so the omni-bag groups potions / wands / gear / valuables
	# instead of presenting them in pickup order. Within a type, rarity desc
	# then name keeps the strongest picks at the front.
	_sort_items_for_display()

	_popup_rects.clear()
	_popup_item_indices.clear()
	_popup = CanvasLayer.new()
	_popup.layer = 12
	get_tree().current_scene.add_child(_popup)

	var cell_w := 110.0
	var cell_h := 90.0
	var gap    := 8.0
	var count  := items.size()
	# Wrap into a grid — single-row layout overflows the screen when the
	# room-clear merge produces a 30+ item bag. Cap at 10 cols and let
	# rows grow downward.
	var cols := clampi(count, 1, 10)
	@warning_ignore("integer_division")
	var rows := (count + cols - 1) / cols
	# Window scrolling — only MAX_VISIBLE_ROWS render at a time. Mouse
	# wheel adjusts _scroll_offset_rows so mega-bags with 30+ items
	# stay on-screen. Clamp the offset every rebuild so removing items
	# (clicks, auto-grab) doesn't leave us scrolled past the end.
	var visible_rows: int = mini(rows, MAX_VISIBLE_ROWS)
	_scroll_offset_rows = clampi(_scroll_offset_rows, 0, maxi(0, rows - visible_rows))
	var row_w := float(cols) * cell_w + float(cols - 1) * gap + 24.0
	var total_h := float(visible_rows) * cell_h + float(maxi(0, visible_rows - 1)) * gap
	var ox := (1600.0 - row_w) / 2.0
	var oy := maxf(80.0, (900.0 - total_h) * 0.5)

	# Background
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.12, 0.97)
	bg.position = Vector2(ox - 4.0, oy - 28.0)
	bg.size = Vector2(row_w + 8.0, total_h + 48.0)
	_popup.add_child(bg)

	# Title — adds a scroll hint when scrolling is needed.
	var title := Label.new()
	if rows > visible_rows:
		title.text = "[ LOOT BAG ]  —  click to collect  |  scroll to page  |  [E] close   (%d items)" % count
	else:
		title.text = "[ LOOT BAG ]  —  click item to collect  |  [E] close"
	title.position = Vector2(ox, oy - 22.0)
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.9, 0.75, 0.3))
	_popup.add_child(title)

	# Scroll-position indicator on the right edge of the panel.
	if rows > visible_rows:
		var pos_lbl := Label.new()
		var top_row: int = _scroll_offset_rows + 1
		var bot_row: int = mini(rows, _scroll_offset_rows + visible_rows)
		pos_lbl.text = "rows %d–%d / %d" % [top_row, bot_row, rows]
		pos_lbl.position = Vector2(ox + row_w - 124.0, oy + total_h + 4.0)
		pos_lbl.size = Vector2(120.0, 16.0)
		pos_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pos_lbl.add_theme_font_size_override("font_size", 10)
		pos_lbl.add_theme_color_override("font_color", Color(0.65, 0.55, 0.35))
		_popup.add_child(pos_lbl)

	# Item cells — render only the visible window (visible_rows × cols).
	var first_idx: int = _scroll_offset_rows * cols
	var last_idx: int = mini(count, first_idx + visible_rows * cols)
	for actual_idx in range(first_idx, last_idx):
		var item: Item = items[actual_idx]
		var rel: int = actual_idx - first_idx
		@warning_ignore("integer_division")
		var col_i: int = rel % cols
		@warning_ignore("integer_division")
		var row_i: int = rel / cols
		var ix := ox + float(col_i) * (cell_w + gap)
		var iy := oy + float(row_i) * (cell_h + gap)

		_popup_rects.append(Rect2(ix, iy, cell_w, cell_h))
		_popup_item_indices.append(actual_idx)

		# Upgrade halo — green border behind the cell when this item beats
		# what's currently equipped in its slot. Mirrors the inventory's
		# upgrade indicator so the player can spot good drops at a glance
		# without inspecting every item.
		var is_upgrade: bool = _is_upgrade_for_equipped(item)
		if is_upgrade:
			var border := ColorRect.new()
			border.color = Color(0.30, 1.00, 0.45, 0.90)
			border.position = Vector2(ix - 3.0, iy - 3.0)
			border.size = Vector2(cell_w + 6.0, cell_h + 6.0)
			_popup.add_child(border)

		var cell := ColorRect.new()
		cell.color = item.color.darkened(0.5)
		cell.position = Vector2(ix, iy)
		cell.size = Vector2(cell_w, cell_h)
		_popup.add_child(cell)

		# Tier badge — top-right corner. Only rendered when tier > 0
		# (potions / fixed legendaries / valuables stay unbadged).
		if item.tier > 0:
			var tier_lbl := Label.new()
			tier_lbl.text = "T%d" % item.tier
			tier_lbl.position = Vector2(ix + cell_w - 28.0, iy + 2.0)
			tier_lbl.size = Vector2(26.0, 12.0)
			tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			tier_lbl.add_theme_font_size_override("font_size", 9)
			tier_lbl.add_theme_color_override("font_color", item.color.lightened(0.4))
			tier_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
			tier_lbl.add_theme_constant_override("outline_size", 2)
			_popup.add_child(tier_lbl)

		var lbl := Label.new()
		var stack_suffix := "  x%d" % item.quantity if item.quantity > 1 else ""
		var prefix := "▲ " if is_upgrade else ""
		lbl.text = prefix + item.icon_char + stack_suffix + "\n" + item.display_name
		lbl.position = Vector2(ix + 4.0, iy + 4.0)
		lbl.size = Vector2(cell_w - 8.0, cell_h - 8.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", item.color.lightened(0.3))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_popup.add_child(lbl)

func receive_item(item: Item) -> void:
	items.append(item)
	# Re-merge after each addition so room-clear bag merges produce a
	# consolidated view rather than parallel duplicate entries.
	_merge_stacks()
	_recolor_by_rarity()
	if _popup != null:
		_close_popup()
		_open_popup()

# Folds duplicate stackables into stacks of up to Item.STACK_CAP. Items
# of the same display_name + type collapse into the first matching slot
# until full, then overflow into a fresh slot. Non-stackables (wands,
# gear) are passed through unchanged.
func _merge_stacks() -> void:
	var stack_chains: Dictionary = {}   # key → Array[Item]
	var keep: Array = []
	for it in items:
		var item: Item = it as Item
		if item == null:
			continue
		if item.is_stackable():
			var key: String = "%d|%s" % [int(item.type), item.display_name]
			var chain: Array = stack_chains.get(key, [])
			var remaining: int = item.quantity
			for primary in chain:
				if remaining <= 0:
					break
				var room: int = Item.STACK_CAP - (primary as Item).quantity
				if room <= 0:
					continue
				var moved: int = mini(room, remaining)
				(primary as Item).quantity += moved
				remaining -= moved
			if remaining <= 0:
				continue
			item.quantity = mini(Item.STACK_CAP, remaining)
			remaining -= item.quantity
			chain.append(item)
			stack_chains[key] = chain
			keep.append(item)
			while remaining > 0:
				var overflow := Item.from_dict(item.to_dict())
				overflow.quantity = mini(Item.STACK_CAP, remaining)
				remaining -= overflow.quantity
				chain.append(overflow)
				keep.append(overflow)
			continue
		keep.append(item)
	items = keep

# Pulls health-potion items out of the bag into the dedicated potion
# slot, capped at InventoryManager.MAX_POTIONS. Anything past the cap
# stays in the bag — the player can still E-loot it manually if they
# want to send it to the grid. Called when the player overlaps the bag.
func _auto_grab_potions() -> bool:
	if items.is_empty():
		return false
	var grabbed: int = 0
	var i: int = 0
	while i < items.size():
		var it: Item = items[i] as Item
		if it == null or it.type != Item.Type.POTION:
			i += 1
			continue
		var room: int = InventoryManager.potion_slot_room()
		if room <= 0:
			break   # slot full — leave the rest of the potions on the floor
		var added: int = InventoryManager.add_potions_to_slot(it, it.quantity)
		grabbed += added
		it.quantity -= added
		if it.quantity <= 0:
			items.remove_at(i)
			continue
		# Slot full mid-stack — stop grabbing, leave remainder in the bag.
		break
	if grabbed > 0:
		var ply := get_tree().get_first_node_in_group("player")
		if ply is Node2D:
			FloatingText.spawn_str((ply as Node2D).global_position + Vector2(0.0, -24.0),
				"+%d potion%s" % [grabbed, "s" if grabbed > 1 else ""],
				Color(0.55, 1.0, 0.55), get_tree().current_scene)
		_recolor_by_rarity()
		# If the bag is now empty (potion-only bag), free it. The popup
		# will reopen empty otherwise.
		if items.is_empty():
			queue_free()
			return true
	return grabbed > 0

# Tints the ASCII glyph by the highest-rarity item still in the bag, so the
# player can spot good drops at a glance:
#   LEGENDARY → purple "$", RARE → white "$", COMMON → bronze "$".
func _recolor_by_rarity() -> void:
	var visual := get_node_or_null("Visual") as Label
	if visual == null:
		return
	var max_r: int = -1
	for it in items:
		if it is Item and (it as Item).rarity > max_r:
			max_r = (it as Item).rarity
	var col: Color
	# Two glyphs: regular drawstring sack vs. fancy 4-row mega bag drawn
	# with diamond accents and a clear "$" inside. The mega variant is
	# only used when room-clear merge produces a single combined bag.
	var glyph: String
	if is_mega:
		glyph = "  ,~~~,\n /  $  \\\n( $$$$$ )\n '-----'"
	else:
		glyph = ",---,\n)___("
	match max_r:
		Item.RARITY_LEGENDARY:
			col = Color(0.78, 0.32, 1.00)   # purple — top tier
		Item.RARITY_RARE:
			col = Color(0.95, 0.95, 0.95)   # white — rare
		Item.RARITY_UNCOMMON:
			col = Color(0.45, 1.00, 0.55)   # green — uncommon
		Item.RARITY_COMMON:
			col = Color(0.85, 0.55, 0.15)   # bronze — common (brighter so it reads on dark floors)
		_:
			col = Color(0.55, 0.55, 0.55)   # empty/unknown — gray
	visual.text = glyph
	visual.add_theme_color_override("font_color", col)
	visual.add_theme_color_override("font_outline_color", col.darkened(0.7))

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_popup_rects.clear()
	_popup_item_indices.clear()
	# Reset scroll so the next open starts fresh. Mid-popup scroll state
	# would feel surprising if it persisted across an open/close cycle.
	_scroll_offset_rows = 0
	if items.is_empty():
		queue_free()

# Reorders the bag's items for display: by group (potions → wands → gear by
# slot → valuables), then rarity desc, then name. Mirrors the inventory
# sort. Mutates `items` directly so the popup cells render in the new
# order and click-to-grab indices stay aligned.
func _sort_items_for_display() -> void:
	items.sort_custom(func(a: Item, b: Item) -> bool:
		var ga: int = _sort_group(a)
		var gb: int = _sort_group(b)
		if ga != gb:
			return ga < gb
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0)

func _sort_group(it: Item) -> int:
	match it.type:
		Item.Type.POTION:   return 0
		Item.Type.WAND:     return 1
		Item.Type.HAT:      return 2
		Item.Type.ROBES:    return 3
		Item.Type.FEET:     return 4
		Item.Type.RING:     return 5
		Item.Type.NECKLACE: return 6
		Item.Type.SHIELD:   return 7
		Item.Type.TOME:     return 8
		Item.Type.VALUABLE: return 9
	return 10

# True if `item` is gear/wand that beats whatever's in its equip slot.
# Mirrors InventoryUI._is_upgrade_for_equipped — same comparison rules
# (empty slot = upgrade; wand-vs-wand by DPS proxy; gear by rarity then
# sell_value). Non-equippables return false.
func _is_upgrade_for_equipped(item: Item) -> bool:
	if item == null:
		return false
	var slot := item.get_equip_slot_name()
	if slot == "":
		return false
	var equipped: Item = InventoryManager.equipped.get(slot) as Item
	if equipped == item:
		return false
	if equipped == null:
		return true
	if item.type == Item.Type.WAND and equipped.type == Item.Type.WAND:
		return _wand_dps_score(item) > _wand_dps_score(equipped)
	if item.rarity != equipped.rarity:
		return item.rarity > equipped.rarity
	return item.sell_value > equipped.sell_value

# Same DPS proxy used by InventoryUI._wand_dps. Re-implemented locally
# rather than depending on the InventoryUI script, since LootBag instances
# exist in scenes where InventoryUI may not be open.
func _wand_dps_score(w: Item) -> float:
	if w == null or w.type != Item.Type.WAND:
		return 0.0
	var rate: float = maxf(w.wand_fire_rate, 0.04)
	var dps: float = float(w.wand_damage) / rate
	if w.wand_shoot_type == "beam":
		dps *= 1.4
	dps *= (1.0 + 0.25 * float(w.wand_pierce))
	dps *= (1.0 + 0.25 * float(w.wand_ricochet))
	return dps

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if _popup == null or not _player_nearby:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return

	# Mouse wheel paginates by one row at a time. Up = scroll back,
	# Down = scroll forward. Rebuild the popup so the new window renders.
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		if _scroll_offset_rows > 0:
			_scroll_offset_rows -= 1
			_close_popup()
			_open_popup()
		get_viewport().set_input_as_handled()
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_scroll_offset_rows += 1   # _open_popup clamps to valid range
		_close_popup()
		_open_popup()
		get_viewport().set_input_as_handled()
		return

	if mb.button_index != MOUSE_BUTTON_LEFT:
		return

	var mp := get_viewport().get_mouse_position()
	for i in _popup_rects.size():
		var r: Rect2 = _popup_rects[i]
		if r.has_point(mp):
			# Map rendered cell index → real items[] index. The two only
			# differ when the popup is scrolled; without the map a click
			# on row 1 cell 0 of a scrolled popup would steal the wrong
			# item.
			var actual_idx: int = int(_popup_item_indices[i])
			if actual_idx >= items.size():
				return
			var item: Item = items[actual_idx]
			if InventoryManager.add_item(item):
				items.remove_at(actual_idx)
				_close_popup()
				if not items.is_empty():
					_open_popup()
			get_viewport().set_input_as_handled()
			return

extends CanvasLayer

const LOOT_BAG_SCENE := preload("res://scenes/LootBag.tscn")

# ── Layout constants (screen pixels) ─────────────────────────────────────────
const PX: float = 380.0
const PY: float = 130.0
const PW: float = 840.0
const PH: float = 620.0

const CELL: float = 72.0
const GAP: float  = 5.0
const GX: float   = 400.0   # PX + 20
const GY: float   = 182.0   # PY + 52

const EX: float   = 801.0   # GX + 5*(CELL+GAP) + 16  =  400 + 385 + 16
const EW: float   = 116.0
const EH: float   = 84.0
const EGAP: float = 8.0

const EQUIP_SLOTS: Array = ["wand","hat","robes","feet","ring","necklace","offhand"]
const EQUIP_LABEL: Dictionary = {
	"wand":    "WAND",
	"hat":     "HAT",
	"robes":   "ROBES",
	"feet":    "FEET",
	"ring":    "RING",
	"necklace":"NECKLACE",
	"offhand": "OFFHAND"
}
# Two-column layout: [col, row] for each slot in EQUIP_SLOTS order
const EQUIP_LAYOUT: Array = [[0,0],[1,0],[0,1],[1,1],[0,2],[1,2],[0,3]]

# ── Node refs ─────────────────────────────────────────────────────────────────
var _grid_cells: Array = []
var _grid_labels: Array = []
var _equip_cells: Dictionary = {}
var _equip_item_labels: Dictionary = {}
var _cursor_label: Label
var _tooltip: Label

func _ready() -> void:
	layer = 10
	visible = false
	_build_ui()
	InventoryManager.inventory_changed.connect(_refresh)

# ── Build ─────────────────────────────────────────────────────────────────────

@warning_ignore("integer_division")
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.1, 0.97)
	bg.position = Vector2(PX, PY)
	bg.size = Vector2(PW, PH)
	add_child(bg)

	_add_label("[ INVENTORY ]", Vector2(PX + 12.0, PY + 8.0), 18, Color(0.8, 0.7, 1.0))
	_add_label("[I] close  |  RMB use potion", Vector2(PX + PW - 270.0, PY + 10.0), 12, Color(0.45, 0.45, 0.45))
	_add_label("Bag (25 slots)", Vector2(GX, GY - 20.0), 13, Color(0.55, 0.55, 0.75))
	_add_label("Equipment",      Vector2(EX, GY - 20.0), 13, Color(0.55, 0.55, 0.75))

	# 5×5 grid
	for i in 25:
		var col: int = i % 5
		var row: int = i / 5
		var cx: float = GX + float(col) * (CELL + GAP)
		var cy: float = GY + float(row) * (CELL + GAP)

		var cell := _make_cell(Vector2(cx, cy), Vector2(CELL, CELL), Color(0.11, 0.11, 0.20))
		_grid_cells.append(cell)

		var lbl := Label.new()
		lbl.position = Vector2(cx + 3.0, cy + 3.0)
		lbl.size = Vector2(CELL - 6.0, CELL - 6.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(lbl)
		_grid_labels.append(lbl)

	# Equipment slots (2 cols × 3 rows)
	for i in EQUIP_SLOTS.size():
		var slot: String = EQUIP_SLOTS[i]
		var layout: Array = EQUIP_LAYOUT[i]
		var cx: float = EX + float(int(layout[0])) * (EW + EGAP)
		var cy: float = GY + float(int(layout[1])) * (EH + EGAP)

		var cell := _make_cell(Vector2(cx, cy), Vector2(EW, EH), Color(0.09, 0.09, 0.17))
		_equip_cells[slot] = cell
		_add_label(EQUIP_LABEL[slot], Vector2(cx + 3.0, cy + 2.0), 10, Color(0.4, 0.4, 0.6))

		var ilbl := Label.new()
		ilbl.position = Vector2(cx + 3.0, cy + 16.0)
		ilbl.size = Vector2(EW - 6.0, EH - 18.0)
		ilbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ilbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		ilbl.add_theme_font_size_override("font_size", 11)
		ilbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(ilbl)
		_equip_item_labels[slot] = ilbl

	# Tooltip bar
	_tooltip = Label.new()
	_tooltip.position = Vector2(PX + 10.0, PY + PH - 24.0)
	_tooltip.size = Vector2(PW - 20.0, 20.0)
	_tooltip.add_theme_font_size_override("font_size", 12)
	_tooltip.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(_tooltip)

	# Floating cursor label (shown while dragging)
	_cursor_label = Label.new()
	_cursor_label.z_index = 50
	_cursor_label.visible = false
	_cursor_label.add_theme_font_size_override("font_size", 13)
	_cursor_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_cursor_label.add_theme_constant_override("outline_size", 2)
	add_child(_cursor_label)

func _make_cell(pos: Vector2, sz: Vector2, col: Color) -> ColorRect:
	var cell := ColorRect.new()
	cell.position = pos
	cell.size = sz
	cell.color = col
	add_child(cell)
	return cell

func _add_label(txt: String, pos: Vector2, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.position = pos
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	add_child(l)
	return l

# ── Toggle ────────────────────────────────────────────────────────────────────

func toggle() -> void:
	visible = not visible
	if not visible:
		InventoryManager.cancel_drag()
	else:
		_refresh()

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.physical_keycode == KEY_I and event.pressed and not event.echo:
		toggle()
		get_viewport().set_input_as_handled()
		return

	if not visible:
		return

	if event is InputEventMouseButton and event.pressed:
		var mp := get_viewport().get_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(mp)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mp)
			get_viewport().set_input_as_handled()

func _handle_left_click(mp: Vector2) -> void:
	for i in 25:
		if _cell_rect(_grid_cells[i]).has_point(mp):
			_click_grid(i)
			return
	for slot in EQUIP_SLOTS:
		if _cell_rect(_equip_cells[slot]).has_point(mp):
			_click_equip(slot)
			return
	if not Rect2(Vector2(PX, PY), Vector2(PW, PH)).has_point(mp):
		_discard_drag()

func _handle_right_click(mp: Vector2) -> void:
	if InventoryManager.drag_item != null:
		InventoryManager.cancel_drag()
		return
	for i in 25:
		if _cell_rect(_grid_cells[i]).has_point(mp):
			var item: Item = InventoryManager.grid[i]
			if item == null:
				return
			if item.type == Item.Type.POTION:
				if InventoryManager.use_potion_at(i):
					_tooltip.text = "Potion used!"
				return
			# Right-click equippable → equip it directly (swap with current)
			var slot := item.get_equip_slot_name()
			if slot == "":
				return
			var displaced: Item = InventoryManager.equipped[slot]
			InventoryManager.equipped[slot] = item
			InventoryManager.grid[i] = displaced   # null if slot was empty
			InventoryManager.inventory_changed.emit()
			_notify_player_stats()
			return

func _click_grid(index: int) -> void:
	if InventoryManager.drag_item != null:
		InventoryManager.drop_to_grid(index)
	else:
		var item: Item = InventoryManager.grid[index]
		if item == null:
			return
		InventoryManager.grid[index] = null
		InventoryManager.begin_drag(item, "grid_%d" % index)
		InventoryManager.inventory_changed.emit()

func _click_equip(slot: String) -> void:
	if InventoryManager.drag_item != null:
		InventoryManager.drop_to_equip(slot)
		_notify_player_stats()
	else:
		var item: Item = InventoryManager.equipped[slot]
		if item == null:
			return
		InventoryManager.equipped[slot] = null
		InventoryManager.begin_drag(item, "equip_%s" % slot)
		InventoryManager.inventory_changed.emit()
		_notify_player_stats()

func _discard_drag() -> void:
	var item: Item = InventoryManager.drag_item
	if item == null:
		return
	# Clear drag state first — item now belongs to no one
	InventoryManager.drag_item = null
	InventoryManager.drag_source = ""

	var player := InventoryManager._player_ref
	if player == null:
		return

	# Prefer dropping into a bag the player is already touching
	for bag in get_tree().get_nodes_in_group("loot_bag"):
		if bag.global_position.distance_to(player.global_position) < 80.0:
			bag.receive_item(item)
			InventoryManager.inventory_changed.emit()
			return

	# No nearby bag — spawn a new one at the player's feet
	var bag := LOOT_BAG_SCENE.instantiate()
	bag.items = [item]
	bag.global_position = player.global_position + Vector2(randf_range(-24.0, 24.0), randf_range(-24.0, 24.0))
	get_tree().current_scene.add_child(bag)
	InventoryManager.inventory_changed.emit()

func _notify_player_stats() -> void:
	var p := InventoryManager._player_ref
	if p and p.has_method("update_equip_stats"):
		p.update_equip_stats()

# ── Process ───────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not visible:
		return
	var dragging: Item = InventoryManager.drag_item
	if dragging:
		_cursor_label.visible = true
		_cursor_label.text = dragging.icon_char + " " + dragging.display_name
		_cursor_label.position = get_viewport().get_mouse_position() + Vector2(10.0, -14.0)
		_cursor_label.add_theme_color_override("font_color", _rarity_name_color(dragging))
	else:
		_cursor_label.visible = false
		_update_tooltip()

func _rarity_name_color(item: Item) -> Color:
	match item.rarity:
		Item.RARITY_LEGENDARY: return Color(1.0, 0.85, 0.12)   # gold
		Item.RARITY_RARE:      return Color(0.55, 0.78, 1.0)   # blue
		_:                     return item.color.lightened(0.3) # thematic

func _rarity_cell_color(item: Item, equip_slot: bool) -> Color:
	var dark := 0.5 if equip_slot else 0.45
	match item.rarity:
		Item.RARITY_LEGENDARY: return Color(0.22, 0.15, 0.02)  # dark gold
		Item.RARITY_RARE:      return Color(0.04, 0.07, 0.22)  # dark blue
		_:                     return item.color.darkened(dark)

func _format_item_tooltip(item: Item) -> String:
	# Rarity prefix on the name
	var prefix: String
	match item.rarity:
		Item.RARITY_LEGENDARY: prefix = "★★ "
		Item.RARITY_RARE:      prefix = "★ "
		_:                     prefix = ""
	var parts: Array = [prefix + item.display_name]

	if item.type == Item.Type.WAND:
		# Wand stats — never show the stored description here (it duplicates these)
		parts.append(item.wand_shoot_type.to_upper())
		parts.append("%d dmg" % item.wand_damage)
		parts.append("%.1f mana/shot" % item.wand_mana_cost)
		parts.append("%.2fs cd" % item.wand_fire_rate)
		if item.wand_pierce > 0:
			parts.append("+%d pierce" % item.wand_pierce)
		if item.wand_ricochet > 0:
			parts.append("+%d bounce" % item.wand_ricochet)
		if item.wand_chain > 0:
			parts.append("+%d chain" % item.wand_chain)
		if not item.wand_flaws.is_empty():
			parts.append("FLAW: " + ", ".join(item.wand_flaws))
	elif not item.stat_bonuses.is_empty():
		# Show computed stats (not description, which just restates them)
		for stat in item.stat_bonuses:
			var val: float = float(item.stat_bonuses[stat])
			match stat:
				"speed":               parts.append("+%.0f spd" % val)
				"max_health":          parts.append("+%d max HP" % int(val))
				"fire_rate_reduction": parts.append("-%dms cooldown" % int(val * 1000.0))
				"block_chance":        parts.append("%.0f%% block" % (val * 100.0))
				"projectile_count":    parts.append("+%d projectiles" % int(val))
				"wisdom":              parts.append("+%.0f mana/s" % val)
	else:
		# No stats (valuables, potions) — show the description text
		if item.description != "":
			parts.append(item.description)
	parts.append("%dg" % item.sell_value)
	return "  |  ".join(parts)

func _update_tooltip() -> void:
	var mp := get_viewport().get_mouse_position()
	for i in 25:
		if _cell_rect(_grid_cells[i]).has_point(mp):
			var item: Item = InventoryManager.grid[i]
			if item:
				_tooltip.text = _format_item_tooltip(item)
			return
	for slot in EQUIP_SLOTS:
		if _cell_rect(_equip_cells[slot]).has_point(mp):
			var item: Item = InventoryManager.equipped[slot]
			if item:
				_tooltip.text = _format_item_tooltip(item)
			return
	_tooltip.text = ""

# ── Refresh display ───────────────────────────────────────────────────────────

func _refresh() -> void:
	for i in 25:
		var item: Item = InventoryManager.grid[i]
		var cell: ColorRect = _grid_cells[i]
		var lbl: Label = _grid_labels[i]
		if item:
			cell.color = _rarity_cell_color(item, false)
			lbl.text = item.icon_char + "\n" + item.display_name
			lbl.add_theme_color_override("font_color", _rarity_name_color(item))
		else:
			cell.color = Color(0.11, 0.11, 0.20)
			lbl.text = ""
	for slot in EQUIP_SLOTS:
		var item: Item = InventoryManager.equipped[slot]
		var cell: ColorRect = _equip_cells[slot]
		var lbl: Label = _equip_item_labels[slot]
		if item:
			cell.color = _rarity_cell_color(item, true)
			lbl.text = item.icon_char + " " + item.display_name
			lbl.add_theme_color_override("font_color", _rarity_name_color(item))
		else:
			cell.color = Color(0.09, 0.09, 0.17)
			lbl.text = ""

# ── Util ──────────────────────────────────────────────────────────────────────

func _cell_rect(cell: ColorRect) -> Rect2:
	return Rect2(cell.position, cell.size)

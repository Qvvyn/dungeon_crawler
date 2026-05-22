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

# Wand was removed from the equipment column — it now lives in the
# first row of the bag grid (slots 0-4) with mouse-wheel cycling. The
# remaining gear slots fill the right column.
const EQUIP_SLOTS: Array = ["hat","robes","feet","ring","necklace"]
const EQUIP_LABEL: Dictionary = {
	"hat":     "HAT",
	"robes":   "ROBES",
	"feet":    "FEET",
	"ring":    "RING",
	"necklace":"NECKLACE",
}
# Two-column layout: [col, row] for each slot in EQUIP_SLOTS order.
# Offhand and wand both removed; this leaves a 2×3 grid that ends one row
# earlier than before. The potion bag positioning constant compensates.
const EQUIP_LAYOUT: Array = [[0,0],[1,0],[0,1],[1,1],[0,2]]

# ── Node refs ─────────────────────────────────────────────────────────────────
var _grid_cells: Array = []
var _grid_labels: Array = []
# Per-cell upgrade indicator — a slightly oversized ColorRect drawn behind
# the cell that pulses green when the held gear beats what's equipped in
# the same slot. Hidden by default. Built parallel to _grid_cells so the
# indices line up.
var _upgrade_borders: Array = []
# Per-cell tier badge — small "T5" Label in the top-right corner of each
# grid cell. Hidden when the item has no tier (potions, valuables, fixed
# legendaries). Built parallel to _grid_cells.
var _tier_badges: Array = []
var _equip_cells: Dictionary = {}
var _equip_item_labels: Dictionary = {}
# Dedicated potion bag — single cell that displays the count of health
# potions in the InventoryManager.potion_slot. Right-click drinks one.
var _potion_cell: ColorRect = null
var _potion_label: Label = null
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
	_add_label("Bag — wands row · scroll wheel cycles  ·  loot below",
		Vector2(GX, GY - 20.0), 12, Color(0.55, 0.55, 0.75))
	_add_label("Equipment",      Vector2(EX, GY - 20.0), 13, Color(0.55, 0.55, 0.75))

	# SORT button — sits next to the bag header. Calls InventoryManager
	# directly; the inventory_changed signal it emits triggers _refresh
	# and the grid repaints in-place.
	var sort_lbl := Label.new()
	sort_lbl.text = "[ SORT ]"
	sort_lbl.position = Vector2(GX + 110.0, GY - 22.0)
	sort_lbl.size = Vector2(70.0, 18.0)
	sort_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sort_lbl.add_theme_font_size_override("font_size", 12)
	sort_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 0.55))
	add_child(sort_lbl)
	var sort_btn := Button.new()
	sort_btn.flat = true
	sort_btn.position = Vector2(GX + 110.0, GY - 24.0)
	sort_btn.size = Vector2(70.0, 22.0)
	sort_btn.pressed.connect(InventoryManager.sort_grid)
	sort_btn.mouse_entered.connect(func() -> void:
		sort_lbl.add_theme_color_override("font_color", Color(0.85, 1.0, 0.70)))
	sort_btn.mouse_exited.connect(func() -> void:
		sort_lbl.add_theme_color_override("font_color", Color(0.65, 0.85, 0.55)))
	add_child(sort_btn)

	# 5×5 grid
	for i in 25:
		var col: int = i % 5
		var row: int = i / 5
		var cx: float = GX + float(col) * (CELL + GAP)
		var cy: float = GY + float(row) * (CELL + GAP)

		# Upgrade-indicator border — added BEFORE the cell so it sits behind
		# and shows as a 2 px green rim around upgrade items. Sized 4 px
		# larger on each axis (2 px per side) for that visible halo effect.
		var border := _make_cell(
			Vector2(cx - 2.0, cy - 2.0),
			Vector2(CELL + 4.0, CELL + 4.0),
			Color(0.30, 1.00, 0.45, 0.90))
		border.visible = false
		_upgrade_borders.append(border)

		var cell := _make_cell(Vector2(cx, cy), Vector2(CELL, CELL), Color(0.11, 0.11, 0.20))
		_grid_cells.append(cell)

		# Tier badge — small "T5" in the top-right corner. Right-anchored
		# inside the cell so it doesn't fight the centered name label.
		var tier_lbl := Label.new()
		tier_lbl.position = Vector2(cx + CELL - 24.0, cy + 1.0)
		tier_lbl.size = Vector2(22.0, 12.0)
		tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tier_lbl.add_theme_font_size_override("font_size", 9)
		tier_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
		tier_lbl.add_theme_constant_override("outline_size", 2)
		tier_lbl.visible = false
		add_child(tier_lbl)
		_tier_badges.append(tier_lbl)

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

	# Dedicated potion bag — sits directly below the equipment column.
	# Wider than an equip slot (spans both columns) so the count + max
	# label reads clearly. Right-click drinks one (input handled below).
	# Row 3 now (was row 4) — offhand slot was removed so the column ends
	# at row 2 (ring/necklace) and the potion bag sits at row 3.
	var pot_cy: float = GY + 3.0 * (EH + EGAP)
	var pot_w: float = 2.0 * EW + EGAP
	_potion_cell = _make_cell(
		Vector2(EX, pot_cy), Vector2(pot_w, EH * 0.7), Color(0.06, 0.14, 0.07))
	_add_label("HEALTH POTIONS", Vector2(EX + 4.0, pot_cy + 2.0),
		10, Color(0.45, 0.7, 0.45))
	_potion_label = Label.new()
	_potion_label.position = Vector2(EX + 4.0, pot_cy + 18.0)
	_potion_label.size = Vector2(pot_w - 8.0, EH * 0.7 - 22.0)
	_potion_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_potion_label.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_potion_label.add_theme_font_size_override("font_size", 14)
	_potion_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.60))
	add_child(_potion_label)

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
			# Shift+left-click drops the clicked item to the ground as a
			# LootBag tagged "player_dropped" so autoplay won't grab it
			# back. Bypasses the normal click→drag flow.
			if event.shift_pressed and _try_shift_drop(mp):
				get_viewport().set_input_as_handled()
				return
			_handle_left_click(mp)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_handle_right_click(mp)
			get_viewport().set_input_as_handled()

func _try_shift_drop(mp: Vector2) -> bool:
	# Bag inventory cells
	for i in 25:
		if _cell_rect(_grid_cells[i]).has_point(mp):
			var item: Item = InventoryManager.grid[i]
			if item == null:
				return true   # consumed the click but nothing to drop
			InventoryManager.grid[i] = null
			InventoryManager.inventory_changed.emit()
			_spawn_player_dropped_bag(item)
			return true
	# Equipment slots — drop equipped gear too
	for slot in EQUIP_SLOTS:
		if _cell_rect(_equip_cells[slot]).has_point(mp):
			var eq: Item = InventoryManager.equipped[slot]
			if eq == null:
				return true
			InventoryManager.equipped[slot] = null
			InventoryManager.inventory_changed.emit()
			_notify_player_stats()
			_spawn_player_dropped_bag(eq)
			return true
	return false

func _spawn_player_dropped_bag(item: Item) -> void:
	var p := get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return
	var bag_scene: PackedScene = preload("res://scenes/LootBag.tscn")
	var bag := bag_scene.instantiate()
	bag.items = [item]
	# Mark so the autoplay loot picker skips this bag — the player asked
	# for it to be on the ground; the bot shouldn't undo that decision.
	bag.add_to_group("player_dropped")
	# Drop a half-tile in front of the player so it doesn't spawn under
	# them and instantly re-trigger pickup.
	(bag as Node2D).global_position = (p as Node2D).global_position + Vector2(0, 24)
	get_tree().current_scene.add_child(bag)
	if SoundManager:
		SoundManager.play("thud", randf_range(0.85, 1.0))

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
	# Dedicated potion bag — right-click drinks one. Checked first so the
	# player can hammer the potion cell repeatedly without the click ever
	# falling through to the grid.
	if _potion_cell != null and _cell_rect(_potion_cell).has_point(mp):
		if InventoryManager.use_potion_from_slot():
			_tooltip.text = "Potion used!"
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
			# Wand cell — right-click sets this slot as the active wand
			# instead of doing an equip-swap (the slot row IS the wand
			# inventory now; there's no separate equip cell).
			if item.type == Item.Type.WAND and i < InventoryManager.WAND_SLOTS:
				InventoryManager._active_wand_slot = i
				InventoryManager._sync_active_wand()
				InventoryManager.inventory_changed.emit()
				_notify_player_stats()
				return
			# Right-click equippable (non-wand) → equip it directly.
			var slot := item.get_equip_slot_name()
			if slot == "" or slot == "wand":
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
		Item.RARITY_UNCOMMON:  return Color(0.55, 1.0, 0.55)   # green
		_:                     return item.color.lightened(0.3) # thematic

func _rarity_cell_color(item: Item, equip_slot: bool) -> Color:
	var dark := 0.5 if equip_slot else 0.45
	match item.rarity:
		Item.RARITY_LEGENDARY: return Color(0.22, 0.15, 0.02)  # dark gold
		Item.RARITY_RARE:      return Color(0.04, 0.07, 0.22)  # dark blue
		Item.RARITY_UNCOMMON:  return Color(0.05, 0.18, 0.07)  # dark green
		_:                     return item.color.darkened(dark)

# True if `item` is gear/wand that beats whatever's in its equip slot.
# - Empty equip slot → any equippable item is an upgrade.
# - Wand → compare _wand_dps (already exists for the tooltip line).
# - Gear → compare sell_value as a power proxy (ItemDB.generate_gear
#   bakes rarity + stat magnitudes into sell_value, so it tracks power
#   well enough for the upgrade-or-not decision).
# Returns false for non-equippable items (potions, valuables) and for
# the currently-equipped item itself.
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
		return _wand_dps(item) > _wand_dps(equipped)
	# Gear: rarity wins ties broken by sell_value. Equal sell_value is
	# *not* an upgrade — avoids the bag flashing green for sidegrades.
	if item.rarity != equipped.rarity:
		return item.rarity > equipped.rarity
	return item.sell_value > equipped.sell_value

# Rough DPS estimate for a wand. Uses base damage × shots-per-second,
# adjusted for pierce/ricochet (more targets = more value) and beam (which
# is continuous). Doesn't model status procs or projectile_count tomes
# since those vary by build, but it's accurate enough to drive the
# swap-or-keep decision in the inventory tooltip.
func _wand_dps(w: Item) -> float:
	if w == null or w.type != Item.Type.WAND:
		return 0.0
	var rate: float = maxf(w.wand_fire_rate, 0.04)
	var dps: float = float(w.wand_damage) / rate
	# Beam wands deal damage continuously while held, so the per-second
	# value is roughly damage * (1/cd-as-tick), close to what the formula
	# above gives. Bump 1.4× to reflect typical sustained uptime.
	if w.wand_shoot_type == "beam":
		dps *= 1.4
	# Pierce / ricochet add ~25% per stack since multi-hits are common in
	# typical room density.
	dps *= (1.0 + 0.25 * float(w.wand_pierce))
	dps *= (1.0 + 0.25 * float(w.wand_ricochet))
	return dps

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
		if item.is_limited_use():
			# Pip strip — visible-at-a-glance charge bar. Filled = remaining,
			# empty = spent. Tail count keeps the exact numbers handy.
			var pips := ""
			for ci in item.wand_max_charges:
				pips += ("■" if ci < item.wand_charges else "□")
			parts.append("⚡ %s  (%d/%d)" % [pips, item.wand_charges, item.wand_max_charges])
		if not item.wand_flaws.is_empty():
			parts.append("FLAW: " + ", ".join(item.wand_flaws))
		# Vs-equipped DPS comparison so the player can decide swap-or-keep
		# without doing the math. Skips when this item IS the equipped wand
		# (no useful self-vs-self comparison).
		var equipped: Item = InventoryManager.equipped.get("wand") as Item
		if equipped != null and equipped != item and equipped.type == Item.Type.WAND:
			var item_dps: float = _wand_dps(item)
			var eq_dps: float   = _wand_dps(equipped)
			if eq_dps > 0.0:
				var pct: float = (item_dps / eq_dps - 1.0) * 100.0
				var sign: String = "+" if pct >= 0.0 else ""
				parts.append("vs equipped: %s%.0f%% DPS" % [sign, pct])
	elif not item.stat_bonuses.is_empty():
		# Show computed stats (not description, which just restates them)
		for stat in item.stat_bonuses:
			var val: float = float(item.stat_bonuses[stat])
			# Synergy markers (syn_pyromaniac, syn_glacial, …) are invisible
			# flags — the legendary's description text already describes
			# the effect, so don't render the raw flag name in this list.
			if (stat as String).begins_with("syn_"):
				continue
			match stat:
				"speed":               parts.append("+%.0f spd" % val)
				"max_health":          parts.append("+%d max HP" % int(val))
				"fire_rate_reduction": parts.append("-%dms cooldown" % int(val * 1000.0))
				"DEF":                 parts.append("+%d DEF" % int(val))
				"projectile_count":    parts.append("+%d projectiles" % int(val))
				"wisdom":              parts.append("+%.0f mana/s" % val)
				"stam_regen":          parts.append("+%.0f stam regen" % val)
				"VIT":                 parts.append("+%d VIT (+%d max HP)" % [int(val), int(val) * 5])
				"INT":                 parts.append("+%d INT" % int(val))
				"DEX":                 parts.append("+%d DEX" % int(val))
				"AGI":                 parts.append("+%d AGI" % int(val))
				"END":                 parts.append("+%d END" % int(val))
				"WIS":                 parts.append("+%d WIS" % int(val))
				"MIND":                parts.append("+%d MIND (+%d max mana)" % [int(val), int(val) * 5])
				"SPR":                 parts.append("+%d SPR" % int(val))
				"LCK":                 parts.append("+%d LCK" % int(val))
				_:                     parts.append("+%g %s" % [val, stat])
	else:
		# No stats (valuables, potions) — show the description text
		if item.description != "":
			parts.append(item.description)
	# Set-tag readout — "Set: Arcane (2/3)" with the counter reflecting
	# how many pieces of the matching set are currently equipped.
	# Three-piece sets are the bonus tier across all set families
	# (arcane / iron / swift), so the denominator stays at 3.
	if item.set_tag != "":
		var equipped_count: int = 0
		for slot in InventoryManager.EQUIP_SLOTS:
			var eq: Item = InventoryManager.equipped.get(slot) as Item
			if eq != null and eq.set_tag == item.set_tag:
				equipped_count += 1
		parts.append("Set: %s (%d/3)" % [item.set_tag.capitalize(), equipped_count])
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
	var active_wand_idx: int = InventoryManager.active_wand_slot()
	for i in 25:
		var item: Item = InventoryManager.grid[i]
		var cell: ColorRect = _grid_cells[i]
		var lbl: Label = _grid_labels[i]
		var border: ColorRect = _upgrade_borders[i] if i < _upgrade_borders.size() else null
		var tier_lbl: Label = _tier_badges[i] if i < _tier_badges.size() else null
		var is_wand_slot: bool = i < InventoryManager.WAND_SLOTS
		var is_active_wand: bool = is_wand_slot and i == active_wand_idx and item != null
		if item:
			cell.color = _rarity_cell_color(item, false)
			# Active-wand cells get a brighter background lerp toward cyan
			# so the row reads at a glance: dim wand cells = held, bright
			# = currently equipped.
			if is_active_wand:
				cell.color = cell.color.lerp(Color(0.30, 0.85, 1.0), 0.35)
			var upgrade: bool = _is_upgrade_for_equipped(item)
			var prefix: String = ""
			if is_active_wand:
				prefix = "▶ "
			elif upgrade:
				prefix = "▲ "
			var stack_suffix := "  x%d" % item.quantity if item.quantity > 1 else ""
			lbl.text = prefix + item.icon_char + stack_suffix + "\n" + item.display_name
			lbl.add_theme_color_override("font_color", _rarity_name_color(item))
			if border != null:
				if is_active_wand:
					# Cyan rim for the active wand — distinct from the
					# green upgrade rim. Both can't fire at once since
					# active overrides upgrade.
					border.color = Color(0.30, 0.85, 1.0, 0.95)
					border.visible = true
				else:
					border.color = Color(0.30, 1.00, 0.45, 0.90)
					border.visible = upgrade
			if tier_lbl != null:
				if item.tier > 0:
					tier_lbl.text = "T%d" % item.tier
					tier_lbl.add_theme_color_override("font_color",
						_rarity_name_color(item))
					tier_lbl.visible = true
				else:
					tier_lbl.visible = false
		else:
			# Wand slots stay tinted differently when empty so the row is
			# visibly the wand row even with no wands held.
			if is_wand_slot:
				cell.color = Color(0.10, 0.13, 0.18)
			else:
				cell.color = Color(0.11, 0.11, 0.20)
			lbl.text = "[wand]" if is_wand_slot else ""
			lbl.add_theme_color_override("font_color", Color(0.30, 0.30, 0.40))
			if border != null:
				border.visible = false
			if tier_lbl != null:
				tier_lbl.visible = false
	for slot in EQUIP_SLOTS:
		var item: Item = InventoryManager.equipped[slot]
		var cell: ColorRect = _equip_cells[slot]
		var lbl: Label = _equip_item_labels[slot]
		if item:
			cell.color = _rarity_cell_color(item, true)
			# Suffix the equipped item's name with its tier so the player
			# sees their current power level inline. Equipment cells are
			# wider than bag cells, so a separate corner badge isn't worth
			# the layout pass.
			var tier_suffix := ("  T%d" % item.tier) if item.tier > 0 else ""
			lbl.text = item.icon_char + " " + item.display_name + tier_suffix
			lbl.add_theme_color_override("font_color", _rarity_name_color(item))
		else:
			cell.color = Color(0.09, 0.09, 0.17)
			lbl.text = ""
	# Potion bag readout — green tint that shifts toward red as the bag
	# empties so a glance tells the player when they're low on heal supply.
	if _potion_label != null:
		var qty: int = InventoryManager.potion_count()
		_potion_label.text = "♥  %d / %d" % [qty, InventoryManager.MAX_POTIONS]
		var t: float = float(qty) / float(InventoryManager.MAX_POTIONS)
		_potion_label.add_theme_color_override("font_color",
			Color(lerpf(1.0, 0.55, t), lerpf(0.45, 1.0, t), lerpf(0.45, 0.6, t)))
		if _potion_cell != null:
			# Brighten the cell when full, dim when empty.
			var bg: float = lerpf(0.06, 0.20, t)
			_potion_cell.color = Color(bg, lerpf(0.10, 0.30, t), bg + 0.02)

# ── Util ──────────────────────────────────────────────────────────────────────

func _cell_rect(cell: ColorRect) -> Rect2:
	return Rect2(cell.position, cell.size)

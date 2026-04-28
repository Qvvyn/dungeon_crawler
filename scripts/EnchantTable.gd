extends Area2D

var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null
var _cell_rects: Array = []
var _cell_indices: Array = []
var _tab: int = 0
var _fuse_selected: Array = []
var _fuse_cell_rects: Array = []
var _fuse_cell_indices: Array = []

const REROLL_COST := 40
const FORGE_COST  := 60
const FUSE_COST   := 80
const REFINE_COST := 110   # transforms one flaw into a stronger perk affix

# Difficulty-scaled price helpers — apply GameState.price_multiplier() so
# upgrade costs come down at high tiers and the player can actually afford
# to keep their gear matching the harder fights. Existing call sites that
# still reference the BASE constants are fine; new code should use these.
func _reroll_cost() -> int: return int(round(float(REROLL_COST) * GameState.price_multiplier()))
func _forge_cost()  -> int: return int(round(float(FORGE_COST)  * GameState.price_multiplier()))
func _fuse_cost()   -> int: return int(round(float(FUSE_COST)   * GameState.price_multiplier()))
func _refine_cost() -> int: return int(round(float(REFINE_COST) * GameState.price_multiplier()))
const CELL_W := 110.0
const CELL_H := 90.0
const GAP    := 8.0

const AFFIX_POOL := [
	{"name": "+1 Damage",    "stat": "wand_damage",     "val": 1},
	{"name": "+1 Pierce",    "stat": "wand_pierce",     "val": 1},
	{"name": "+1 Ricochet",  "stat": "wand_ricochet",   "val": 1},
	{"name": "Faster Fire",  "stat": "wand_fire_rate",  "val": -0.02},
	{"name": "-15% Mana",    "stat": "wand_mana_cost",  "val": -0.15},
	{"name": "+60 ProjSpd",  "stat": "wand_proj_speed", "val": 60.0},
]

# Value ranges for rerolling each stat
const STAT_RANGES := {
	"speed":              [10.0,  60.0],
	"max_health":         [1.0,   4.0],
	"fire_rate_reduction":[0.01,  0.09],
	"DEF":                [5.0,   35.0],
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
		# Autoplay: silently use the table to upgrade gear when affordable.
		# Doesn't open the popup; just runs the optimal action(s) once.
		if body.get("_autoplay") == true:
			_auto_upgrade(body)

func _on_body_exited(body: Node2D) -> void:
	if body.is_in_group("player"):
		_player_nearby = false
		_hint.visible = false
		_close_popup()

# Autoplay handler — runs the most valuable affordable action(s) on this
# table without opening the popup UI. Priorities:
#   1) Refine the equipped wand if it has a flaw (best gold-per-power swap).
#   2) Forge an extra affix onto the wand if we have plenty of gold.
#   3) Reroll one non-legendary stat-bonus item per visit.
# Caps actions per visit so the bot doesn't drain its whole gold reserve on
# a single table.
func _auto_upgrade(player: Node) -> void:
	var did_anything := false
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	# Refine flaw → strong affix.
	if wand != null and wand.type == Item.Type.WAND \
			and not (wand.wand_flaws as Array).is_empty() \
			and GameState.gold >= _refine_cost():
		GameState.gold -= _refine_cost()
		var removed: String = String(wand.wand_flaws[0])
		wand.wand_flaws.remove_at(0)
		_apply_affix(wand, AFFIX_POOL[randi() % AFFIX_POOL.size()], 1.6)
		FloatingText.spawn_str(player.global_position,
			"REFINED: -%s" % removed.to_upper(),
			Color(0.85, 0.55, 1.0), get_tree().current_scene)
		did_anything = true
	# Forge — only if we still have a comfortable gold buffer afterward, so
	# the bot doesn't bankrupt itself on every floor's table.
	elif wand != null and wand.type == Item.Type.WAND \
			and GameState.gold >= _forge_cost() + 80:
		GameState.gold -= _forge_cost()
		_apply_affix(wand, AFFIX_POOL[randi() % AFFIX_POOL.size()], 1.0)
		FloatingText.spawn_str(player.global_position,
			"FORGED!",
			Color(1.0, 0.75, 0.2), get_tree().current_scene)
		did_anything = true
	# Reroll a single non-legendary stat-bonus item — picks the lowest-rarity
	# item with stats so the gold goes toward improving weak gear, not the
	# already-good rare pieces.
	if GameState.gold >= _reroll_cost():
		var pick_idx: int = -1
		var pick_rarity: int = 99
		for i in InventoryManager.grid.size():
			var it: Item = InventoryManager.grid[i]
			if it == null:
				continue
			if it.rarity == Item.RARITY_LEGENDARY:
				continue
			if it.stat_bonuses.is_empty():
				continue
			if it.rarity < pick_rarity:
				pick_rarity = it.rarity
				pick_idx = i
		if pick_idx >= 0:
			GameState.gold -= _reroll_cost()
			_reroll(InventoryManager.grid[pick_idx])
			FloatingText.spawn_str(player.global_position,
				"REROLLED!",
				Color(0.75, 1.0, 0.85), get_tree().current_scene)
			did_anything = true
	if did_anything:
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
	_cell_rects.clear()
	_cell_indices.clear()
	_fuse_cell_rects.clear()
	_fuse_cell_indices.clear()

	var wand: Item = InventoryManager.equipped.get("wand") as Item
	var has_wand := wand != null and wand.type == Item.Type.WAND

	var rerollable: Array = []
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i]
		if item != null and item.rarity != Item.RARITY_LEGENDARY and not item.stat_bonuses.is_empty():
			rerollable.append(i)

	var count   := rerollable.size()
	var cols    := clampi(count, 1, 8)
	var rows    := ceili(float(maxi(count, 1)) / float(cols))
	var row_w   := float(cols) * CELL_W + float(cols - 1) * GAP
	var panel_w := maxf(row_w + 48.0, 380.0)
	var cells_h := float(rows) * (CELL_H + GAP) if count > 0 else 28.0
	var panel_h := 30.0 + 56.0 + cells_h + 24.0 + (108.0 if has_wand else 0.0)
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

	# ── Tab strip ─────────────────────────────────────────────────────────────
	var tab_w := panel_w / 2.0
	for t in 2:
		var tab_col := Color(0.35, 0.12, 0.6, 1.0) if t == _tab else Color(0.18, 0.08, 0.3, 1.0)
		var tab_bg := ColorRect.new()
		tab_bg.color = tab_col
		tab_bg.position = Vector2(ox + float(t) * tab_w, oy + 3.0)
		tab_bg.size = Vector2(tab_w, 27.0)
		_popup.add_child(tab_bg)
		var tab_lbl := Label.new()
		tab_lbl.text = "REROLL" if t == 0 else ("FUSE  %dg" % _fuse_cost())
		tab_lbl.position = Vector2(ox + float(t) * tab_w, oy + 5.0)
		tab_lbl.size = Vector2(tab_w, 22.0)
		tab_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tab_lbl.add_theme_font_size_override("font_size", 12)
		tab_lbl.add_theme_color_override("font_color",
			Color(0.85, 0.6, 1.0) if t == _tab else Color(0.45, 0.35, 0.6))
		_popup.add_child(tab_lbl)
		var tab_btn := Button.new()
		tab_btn.flat = true
		tab_btn.text = ""
		tab_btn.position = Vector2(ox + float(t) * tab_w, oy + 3.0)
		tab_btn.size = Vector2(tab_w, 27.0)
		var t_cap := t
		tab_btn.pressed.connect(func() -> void:
			_tab = t_cap
			_fuse_selected.clear()
			_build_ui())
		_popup.add_child(tab_btn)

	var title := Label.new()
	title.text = ("✦  ENCHANTING TABLE  ✦   —   %dg reroll   |   [E] close" % _reroll_cost()) if _tab == 0 else "✦  ITEM FUSION  ✦   —   Select 2 items to combine   |   [E] close"
	title.position = Vector2(ox, oy + 38.0)
	title.size = Vector2(panel_w, 22.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.7, 0.4, 1.0))
	_popup.add_child(title)

	var gold_lbl := Label.new()
	gold_lbl.text = "Gold: " + str(GameState.gold) + "g"
	gold_lbl.position = Vector2(ox, oy + 60.0)
	gold_lbl.size = Vector2(panel_w, 18.0)
	gold_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gold_lbl.add_theme_font_size_override("font_size", 11)
	gold_lbl.add_theme_color_override("font_color", Color(0.8, 0.75, 0.5))
	_popup.add_child(gold_lbl)

	if _tab == 1:
		_build_fuse_content(ox, oy, panel_w, panel_h)
		return

	# ── Reroll content ────────────────────────────────────────────────────────
	if count == 0:
		var empty := Label.new()
		empty.text = "No rerollable items in bag."
		empty.position = Vector2(ox, oy + 86.0)
		empty.size = Vector2(panel_w, 28.0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_popup.add_child(empty)
		if not has_wand:
			return
	else:
		var cells_ox := ox + (panel_w - row_w) / 2.0
		var cy := oy + 84.0
		for i in count:
			var grid_idx: int = rerollable[i]
			var item: Item = InventoryManager.grid[grid_idx]
			var col_i := i % cols
			var row_i := i / cols
			var ix := cells_ox + float(col_i) * (CELL_W + GAP)
			var iy := cy + float(row_i) * (CELL_H + GAP)

			_cell_rects.append(Rect2(ix, iy, CELL_W, CELL_H))
			_cell_indices.append(grid_idx)

			var can_afford := GameState.gold >= _reroll_cost()
			var cell := ColorRect.new()
			cell.color = item.color.darkened(0.55)
			cell.position = Vector2(ix, iy)
			cell.size = Vector2(CELL_W, CELL_H)
			_popup.add_child(cell)

			var stat_str := ""
			for key in item.stat_bonuses:
				stat_str += key.substr(0, 4) + ":" + ("%.2f" % item.stat_bonuses[key]) + " "

			var lbl := Label.new()
			lbl.text = item.icon_char + " " + item.display_name + "\n" + stat_str.strip_edges() + "\n[REROLL %dg]" % _reroll_cost()
			lbl.position = Vector2(ix + 4.0, iy + 4.0)
			lbl.size = Vector2(CELL_W - 8.0, CELL_H - 8.0)
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
			lbl.add_theme_font_size_override("font_size", 10)
			lbl.add_theme_color_override("font_color",
				item.color.lightened(0.3) if can_afford else item.color.darkened(0.3))
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_popup.add_child(lbl)

	# ── Forge section ─────────────────────────────────────────────────────────
	if has_wand:
		var sep_y := oy + panel_h - 108.0
		var sep := ColorRect.new()
		sep.color = Color(0.45, 0.2, 0.7, 0.5)
		sep.position = Vector2(ox + 8.0, sep_y)
		sep.size = Vector2(panel_w - 16.0, 1.0)
		_popup.add_child(sep)

		var forge_title := Label.new()
		forge_title.text = "⚒  FORGE AFFIX  —  %dg  —  adds a stat (no flaw effect)" % _forge_cost()
		forge_title.position = Vector2(ox, sep_y + 6.0)
		forge_title.size = Vector2(panel_w, 20.0)
		forge_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		forge_title.add_theme_font_size_override("font_size", 11)
		forge_title.add_theme_color_override("font_color", Color(0.85, 0.6, 0.15))
		_popup.add_child(forge_title)

		var can_forge := GameState.gold >= _forge_cost()
		var forge_lbl := Label.new()
		forge_lbl.text = "[ FORGE WAND ]"
		forge_lbl.position = Vector2(ox, sep_y + 26.0)
		forge_lbl.size = Vector2(panel_w, 26.0)
		forge_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		forge_lbl.add_theme_font_size_override("font_size", 15)
		forge_lbl.add_theme_color_override("font_color",
			Color(0.9, 0.6, 0.15) if can_forge else Color(0.35, 0.3, 0.25))
		_popup.add_child(forge_lbl)

		var forge_btn := Button.new()
		forge_btn.flat = true
		forge_btn.text = ""
		forge_btn.position = Vector2(ox, sep_y + 26.0)
		forge_btn.size = Vector2(panel_w, 26.0)
		forge_btn.pressed.connect(_forge_wand)
		forge_btn.mouse_entered.connect(func() -> void:
			if GameState.gold >= _forge_cost():
				forge_lbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.3)))
		forge_btn.mouse_exited.connect(func() -> void:
			forge_lbl.add_theme_color_override("font_color",
				Color(0.9, 0.6, 0.15) if GameState.gold >= _forge_cost() else Color(0.35, 0.3, 0.25)))
		_popup.add_child(forge_btn)

		# Refine — separate action that re-rolls one flaw into a stronger affix
		var has_flaws: bool = not (wand.wand_flaws as Array).is_empty()
		var can_refine := GameState.gold >= _refine_cost() and has_flaws
		var refine_title := Label.new()
		refine_title.text = "✦  REFINE FLAW  —  %dg  —  removes a flaw and grants a perk" % _refine_cost()
		refine_title.position = Vector2(ox, sep_y + 56.0)
		refine_title.size = Vector2(panel_w, 20.0)
		refine_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		refine_title.add_theme_font_size_override("font_size", 11)
		refine_title.add_theme_color_override("font_color",
			Color(0.65, 0.4, 1.0) if has_flaws else Color(0.4, 0.3, 0.55))
		_popup.add_child(refine_title)

		var refine_lbl := Label.new()
		refine_lbl.text = "[ REFINE WAND ]" if has_flaws else "[ NO FLAWS ]"
		refine_lbl.position = Vector2(ox, sep_y + 76.0)
		refine_lbl.size = Vector2(panel_w, 26.0)
		refine_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		refine_lbl.add_theme_font_size_override("font_size", 15)
		refine_lbl.add_theme_color_override("font_color",
			Color(0.75, 0.5, 1.0) if can_refine else Color(0.35, 0.28, 0.45))
		_popup.add_child(refine_lbl)

		var refine_btn := Button.new()
		refine_btn.flat = true
		refine_btn.text = ""
		refine_btn.position = Vector2(ox, sep_y + 76.0)
		refine_btn.size = Vector2(panel_w, 26.0)
		refine_btn.disabled = not can_refine
		refine_btn.pressed.connect(_refine_wand)
		refine_btn.mouse_entered.connect(func() -> void:
			if can_refine:
				refine_lbl.add_theme_color_override("font_color", Color(0.95, 0.7, 1.0)))
		refine_btn.mouse_exited.connect(func() -> void:
			refine_lbl.add_theme_color_override("font_color",
				Color(0.75, 0.5, 1.0) if can_refine else Color(0.35, 0.28, 0.45)))
		_popup.add_child(refine_btn)

func _build_fuse_content(ox: float, oy: float, panel_w: float, _panel_h: float) -> void:
	var fusable: Array = []
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i]
		if item != null and not item.stat_bonuses.is_empty() and item.type != Item.Type.WAND:
			fusable.append(i)

	if fusable.size() < 2:
		var empty := Label.new()
		empty.text = "Need 2+ items with stats to fuse."
		empty.position = Vector2(ox, oy + 86.0)
		empty.size = Vector2(panel_w, 28.0)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_font_size_override("font_size", 13)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		_popup.add_child(empty)
		return

	var fc := fusable.size()
	var fcols := clampi(fc, 1, 8)
	var frow_w := float(fcols) * CELL_W + float(fcols - 1) * GAP
	var fcells_ox := ox + (panel_w - frow_w) / 2.0
	var cy := oy + 84.0

	for i in fc:
		var grid_idx: int = fusable[i]
		var item: Item = InventoryManager.grid[grid_idx]
		var col_i := i % fcols
		var row_i := i / fcols
		var ix := fcells_ox + float(col_i) * (CELL_W + GAP)
		var iy := cy + float(row_i) * (CELL_H + GAP)

		_fuse_cell_rects.append(Rect2(ix, iy, CELL_W, CELL_H))
		_fuse_cell_indices.append(grid_idx)

		var is_sel := grid_idx in _fuse_selected
		var cell := ColorRect.new()
		cell.color = item.color.darkened(0.3) if is_sel else item.color.darkened(0.6)
		cell.position = Vector2(ix, iy)
		cell.size = Vector2(CELL_W, CELL_H)
		_popup.add_child(cell)

		if is_sel:
			var sel_border := ColorRect.new()
			sel_border.color = Color(1.0, 0.85, 0.1, 0.6)
			sel_border.position = Vector2(ix - 2.0, iy - 2.0)
			sel_border.size = Vector2(CELL_W + 4.0, CELL_H + 4.0)
			sel_border.z_index = -1
			_popup.add_child(sel_border)

		var stat_str := ""
		for key in item.stat_bonuses:
			stat_str += key.substr(0, 4) + ":" + ("%.2f" % item.stat_bonuses[key]) + " "

		var rarity_tag := " [R]" if item.rarity == Item.RARITY_RARE else (" [L]" if item.rarity == Item.RARITY_LEGENDARY else "")
		var lbl := Label.new()
		lbl.text = item.icon_char + " " + item.display_name + rarity_tag + "\n" + stat_str.strip_edges()
		if is_sel:
			lbl.text += "\n[SELECTED]"
		else:
			lbl.text += "\n[click to select]"
		lbl.position = Vector2(ix + 4.0, iy + 4.0)
		lbl.size = Vector2(CELL_W - 8.0, CELL_H - 8.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 9)
		lbl.add_theme_color_override("font_color",
			Color(1.0, 0.9, 0.3) if is_sel else item.color.lightened(0.2))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_popup.add_child(lbl)

	# Fuse button — only when 2 selected
	if _fuse_selected.size() == 2:
		var btn_y := cy + float(ceili(float(fc) / float(fcols))) * (CELL_H + GAP) + 8.0
		var can_fuse := GameState.gold >= _fuse_cost()
		var fuse_lbl := Label.new()
		fuse_lbl.text = "[ FUSE ITEMS — %dg ]" % _fuse_cost()
		fuse_lbl.position = Vector2(ox, btn_y)
		fuse_lbl.size = Vector2(panel_w, 34.0)
		fuse_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fuse_lbl.add_theme_font_size_override("font_size", 18)
		fuse_lbl.add_theme_color_override("font_color",
			Color(0.9, 0.7, 0.1) if can_fuse else Color(0.35, 0.3, 0.25))
		_popup.add_child(fuse_lbl)

		var fuse_btn := Button.new()
		fuse_btn.flat = true
		fuse_btn.text = ""
		fuse_btn.position = Vector2(ox, btn_y)
		fuse_btn.size = Vector2(panel_w, 34.0)
		fuse_btn.pressed.connect(_fuse_items)
		fuse_btn.mouse_entered.connect(func() -> void:
			if GameState.gold >= _fuse_cost():
				fuse_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3)))
		fuse_btn.mouse_exited.connect(func() -> void:
			fuse_lbl.add_theme_color_override("font_color",
				Color(0.9, 0.7, 0.1) if GameState.gold >= _fuse_cost() else Color(0.35, 0.3, 0.25)))
		_popup.add_child(fuse_btn)

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
	_cell_rects.clear()
	_cell_indices.clear()
	_fuse_cell_rects.clear()
	_fuse_cell_indices.clear()
	_fuse_selected.clear()
	_tab = 0

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

	if _tab == 1:
		for i in _fuse_cell_rects.size():
			if _fuse_cell_rects[i].has_point(mp):
				var grid_idx: int = _fuse_cell_indices[i]
				_toggle_fuse_select(grid_idx)
				_build_ui()
				get_viewport().set_input_as_handled()
				return
		return

	for i in _cell_rects.size():
		if not _cell_rects[i].has_point(mp):
			continue
		if GameState.gold < _reroll_cost():
			var player := InventoryManager._player_ref
			if player:
				FloatingText.spawn_str(player.global_position,
					"Need " + str(_reroll_cost()) + "g",
					Color(1.0, 0.3, 0.3), get_tree().current_scene)
		else:
			var grid_idx: int = _cell_indices[i]
			var item: Item = InventoryManager.grid[grid_idx]
			if item != null:
				GameState.gold -= _reroll_cost()
				_reroll(item)
				InventoryManager.inventory_changed.emit()
				_build_ui()
		get_viewport().set_input_as_handled()
		return

func _toggle_fuse_select(grid_idx: int) -> void:
	if grid_idx in _fuse_selected:
		_fuse_selected.erase(grid_idx)
	elif _fuse_selected.size() < 2:
		_fuse_selected.append(grid_idx)
	else:
		_fuse_selected[0] = _fuse_selected[1]
		_fuse_selected[1] = grid_idx

func _fuse_items() -> void:
	if _fuse_selected.size() < 2:
		return
	if GameState.gold < _fuse_cost():
		var player := InventoryManager._player_ref
		if player:
			FloatingText.spawn_str(player.global_position,
				"Need %dg" % _fuse_cost(), Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	var idx_a: int = _fuse_selected[0]
	var idx_b: int = _fuse_selected[1]
	var item_a: Item = InventoryManager.grid[idx_a]
	var item_b: Item = InventoryManager.grid[idx_b]
	if item_a == null or item_b == null:
		return

	GameState.gold -= _fuse_cost()

	var fused := Item.new()
	fused.type = item_a.type
	fused.icon_char = item_a.icon_char
	fused.rarity = Item.RARITY_RARE
	fused.display_name = "Fused " + item_a.display_name
	fused.description = "Fused from " + item_a.display_name + " + " + item_b.display_name
	fused.color = item_a.color.lerp(item_b.color, 0.5).lightened(0.1)
	fused.sell_value = (item_a.sell_value + item_b.sell_value) / 2
	var merged := {}
	for key in item_a.stat_bonuses:
		merged[key] = item_a.stat_bonuses[key]
	for key in item_b.stat_bonuses:
		if key in merged:
			merged[key] = merged[key] + item_b.stat_bonuses[key] * 0.6
		else:
			merged[key] = item_b.stat_bonuses[key] * 0.6
	fused.stat_bonuses = merged

	InventoryManager.grid[idx_a] = fused
	InventoryManager.grid[idx_b] = null

	_fuse_selected.clear()
	var player := InventoryManager._player_ref
	if player and player.has_method("update_equip_stats"):
		player.update_equip_stats()
	if player:
		FloatingText.spawn_str(player.global_position,
			"FUSED!", Color(1.0, 0.8, 0.2), get_tree().current_scene)
	InventoryManager.inventory_changed.emit()
	_build_ui()

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
	var player := InventoryManager._player_ref
	if player and player.has_method("update_equip_stats"):
		player.update_equip_stats()

func _forge_wand() -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		return
	var player := InventoryManager._player_ref
	if GameState.gold < _forge_cost():
		if player:
			FloatingText.spawn_str(player.global_position,
				"Need %dg" % _forge_cost(), Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	GameState.gold -= _forge_cost()
	_apply_affix(wand, AFFIX_POOL[randi() % AFFIX_POOL.size()], 1.0)
	if player:
		FloatingText.spawn_str(player.global_position,
			"FORGED!", Color(1.0, 0.75, 0.2), get_tree().current_scene)
	InventoryManager.inventory_changed.emit()
	_build_ui()

# Re-rolls one of the wand's flaws into a stronger-than-forge affix. Costs
# more than a plain forge but only when the wand actually has a flaw to trade.
func _refine_wand() -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		return
	if (wand.wand_flaws as Array).is_empty():
		return
	var player := InventoryManager._player_ref
	if GameState.gold < _refine_cost():
		if player:
			FloatingText.spawn_str(player.global_position,
				"Need %dg" % _refine_cost(), Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	GameState.gold -= _refine_cost()
	var removed: String = String(wand.wand_flaws[0])
	wand.wand_flaws.remove_at(0)
	# Refine grants a 1.6× scaled affix — meaningfully better than a forge.
	_apply_affix(wand, AFFIX_POOL[randi() % AFFIX_POOL.size()], 1.6)
	if player:
		FloatingText.spawn_str(player.global_position,
			"REFINED: -%s" % removed.to_upper(), Color(0.85, 0.55, 1.0), get_tree().current_scene)
	InventoryManager.inventory_changed.emit()
	_build_ui()

# Shared affix-application helper — `scale` multiplies the affix's value so
# REFINE can grant a stronger version than FORGE while reusing the same pool.
func _apply_affix(wand: Item, affix: Dictionary, scale: float) -> void:
	var v_int: int = int(round(float(affix["val"]) * scale))
	var v_flt: float = float(affix["val"]) * scale
	match affix["stat"]:
		"wand_damage":     wand.wand_damage     = maxi(1, wand.wand_damage + v_int)
		"wand_pierce":     wand.wand_pierce     = mini(8, wand.wand_pierce + v_int)
		"wand_ricochet":   wand.wand_ricochet   = mini(8, wand.wand_ricochet + v_int)
		"wand_fire_rate":  wand.wand_fire_rate  = maxf(0.04, wand.wand_fire_rate + v_flt)
		"wand_mana_cost":  wand.wand_mana_cost  = maxf(1.0, wand.wand_mana_cost * (1.0 + v_flt))
		"wand_proj_speed": wand.wand_proj_speed = minf(1200.0, wand.wand_proj_speed + v_flt)

extends Area2D

var _player_nearby: bool = false
var _hint: Label = null
var _popup: CanvasLayer = null
var _cell_rects: Array = []
var _cell_indices: Array = []

const REROLL_COST   := 40
const FORGE_COST    := 60
const REFINE_COST   := 110   # transforms one flaw into a stronger perk affix
const TRANSMUTE_COST := 200  # picks the wand's shoot type, rerolls type-keyed stats
# Imbue tier costs — Common→Rare is cheap so early upgrades are accessible,
# Rare→Legendary is the milestone that costs real money. Single flat 250g
# cost for both tiers made the second jump trivial relative to the value
# delta and the first jump too steep.
const IMBUE_COST_TO_RARE      := 150
const IMBUE_COST_TO_LEGENDARY := 800

# Difficulty-scaled price helpers — apply GameState.price_multiplier() so
# upgrade costs come down at high tiers and the player can actually afford
# to keep their gear matching the harder fights. Existing call sites that
# still reference the BASE constants are fine; new code should use these.
func _reroll_cost() -> int: return int(round(float(REROLL_COST) * GameState.price_multiplier()))
func _forge_cost()  -> int:
	# Two stacking modifiers:
	#   1. Per-wand escalation — each prior forge on the equipped wand
	#      multiplies the next one's price by 1.5. A FRESH wand resets to
	#      base since wand_forge_count starts at 0.
	#   2. Difficulty surcharge — base cost climbs with the active floor
	#      difficulty so deep-floor forging stays a meaningful gold sink.
	#      +20 % per +1 difficulty above the first floor; capped at 5×.
	# Note: forge intentionally does NOT use GameState.price_multiplier()
	# (which DISCOUNTS at high diff for shop / fuse / etc.) because the
	# user wants forging to feel pricier as the dungeon gets harder.
	var stack: float = 1.0
	var w: Item = InventoryManager.equipped.get("wand") as Item
	if w != null and w.type == Item.Type.WAND and w.wand_forge_count > 0:
		stack = pow(1.5, float(w.wand_forge_count))
	var d: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	var diff_scale: float = clampf(1.0 + maxf(0.0, d - 1.0) * 0.20, 1.0, 5.0)
	return int(round(float(FORGE_COST) * diff_scale * stack))
func _refine_cost() -> int: return int(round(float(REFINE_COST) * GameState.price_multiplier()))
func _transmute_cost() -> int: return int(round(float(TRANSMUTE_COST) * GameState.price_multiplier()))
# Imbue cost depends on the equipped wand's *current* rarity (the cost to
# bump it up one tier). Cheap for the early rarity steps, expensive for
# the legendary jump. Falls back to the legendary cost when the wand is
# missing or already legendary so the label still reads sensibly.
func _imbue_cost() -> int:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		return int(round(float(IMBUE_COST_TO_LEGENDARY) * GameState.price_multiplier()))
	var base: int = IMBUE_COST_TO_LEGENDARY
	match wand.rarity:
		Item.RARITY_COMMON:    base = IMBUE_COST_TO_RARE       # → uncommon
		Item.RARITY_UNCOMMON:  base = IMBUE_COST_TO_RARE       # → rare
		Item.RARITY_RARE:      base = IMBUE_COST_TO_LEGENDARY  # → legendary
	return int(round(float(base) * GameState.price_multiplier()))
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

# Affix-compatibility filter. Pierce and ricochet are mutually exclusive
# on non-legendary wands — only legendaries can carry both. Forge / refine
# / imbue / autoplay forge all roll affixes through this picker so the
# rule holds regardless of which call site does the application.
func _random_compatible_affix(wand: Item) -> Dictionary:
	var pool: Array = AFFIX_POOL
	if wand != null and wand.rarity < Item.RARITY_LEGENDARY:
		if wand.wand_pierce > 0:
			# Wand already has pierce → ricochet affix is off the table.
			pool = AFFIX_POOL.filter(func(a: Dictionary) -> bool:
				return a["stat"] != "wand_ricochet")
		elif wand.wand_ricochet > 0:
			# Wand already has ricochet → pierce affix is off the table.
			pool = AFFIX_POOL.filter(func(a: Dictionary) -> bool:
				return a["stat"] != "wand_pierce")
	return pool[randi() % pool.size()]

# Value ranges for rerolling each stat
const STAT_RANGES := {
	"speed":              [10.0,  60.0],
	"max_health":         [1.0,   4.0],
	"fire_rate_reduction":[0.01,  0.09],
	"DEF":                [5.0,   35.0],
	"projectile_count":   [1.0,   3.0],
}

func _ready() -> void:
	add_to_group("interactable")   # bullets pass through (Projectile group check)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Show the full 2D ASCII table standing upright in FP, not a bare "+".
	set_meta("fp_multiline", true)
	set_meta("fp_pixel_size", 0.011)
	GameState.attach_fp_visual(self, " ___ \n[✦✦✦]\n |_| ", Color(0.85, 0.45, 1.0), 0.55)

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
		_apply_affix(wand, _random_compatible_affix(wand), 1.6)
		FloatingText.spawn_str(player.global_position,
			"REFINED: -%s" % removed.to_upper(),
			Color(0.85, 0.55, 1.0), get_tree().current_scene)
		did_anything = true
	# Forge — only if we still have a comfortable gold buffer afterward, so
	# the bot doesn't bankrupt itself on every floor's table.
	elif wand != null and wand.type == Item.Type.WAND \
			and GameState.gold >= _forge_cost() + 80:
		GameState.gold -= _forge_cost()
		_apply_affix(wand, _random_compatible_affix(wand), 1.0)
		wand.wand_forge_count += 1   # match manual forge cost-escalation
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
	# PROCESS_MODE_ALWAYS so the popup's buttons keep handling clicks while the
	# tree is paused (set_interface_open pauses the game below).
	_popup.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_popup)
	# Self ALWAYS too, so _process keeps polling the [E] close key under pause.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ply := get_tree().get_first_node_in_group("player")
	if ply != null and ply.has_method("set_interface_open"):
		ply.set_interface_open(true)
	_build_ui()

func _build_ui() -> void:
	# Remove-from-tree + queue_free instead of plain free(). _build_ui is
	# called from Button.pressed handlers (forge / refine / imbue / fuse /
	# transmute), so the Button that fired the click is among the popup's
	# children. Calling free() on it while it's mid-dispatch crashes
	# Godot's signal stack on the next input event. Removing it first
	# drops it from the tree (subsequent input traversal skips it) and
	# queue_free schedules the actual deletion for next idle, after the
	# pressed signal has finished unwinding.
	for child in _popup.get_children():
		_popup.remove_child(child)
		child.queue_free()
	_cell_rects.clear()
	_cell_indices.clear()

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
	# Wand action panel grew 108 → 158 to fit the TRANSMUTE row beneath
	# IMBUE without overlapping the inventory grid.
	var panel_h := 30.0 + 56.0 + cells_h + 24.0 + (158.0 if has_wand else 0.0)
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
	title.text = "✦  ENCHANTING TABLE  ✦   —   %dg reroll   |   [E] close" % _reroll_cost()
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

	# ── Forge / Refine / Imbue / Transmute section ───────────────────────────
	# sep_y bumped further to fit the fourth action row (transmute). Overall
	# math: title 20 + button 26 = 46 px per row, four rows = 184 px, with
	# the current 30 + 56 (tabs/title) plus 24 padding = ~206. The panel_h
	# baseline has 158 reserved.
	if has_wand:
		var sep_y := oy + panel_h - 206.0
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

		# Imbue — third row. Bumps wand rarity by one step
		# (common → uncommon → rare → legendary). Disabled when the
		# wand is already legendary or gold is short.
		var is_max_tier: bool = wand.rarity >= Item.RARITY_LEGENDARY
		var can_imbue := GameState.gold >= _imbue_cost() and not is_max_tier
		var imbue_title := Label.new()
		var tier_text: String = "MAX TIER"
		if not is_max_tier:
			match wand.rarity:
				Item.RARITY_COMMON:   tier_text = "COMMON → UNCOMMON"
				Item.RARITY_UNCOMMON: tier_text = "UNCOMMON → RARE"
				Item.RARITY_RARE:     tier_text = "RARE → LEGENDARY"
		imbue_title.text = "★  IMBUE WAND  —  %dg  —  %s" % [_imbue_cost(), tier_text]
		imbue_title.position = Vector2(ox, sep_y + 106.0)
		imbue_title.size = Vector2(panel_w, 20.0)
		imbue_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		imbue_title.add_theme_font_size_override("font_size", 11)
		imbue_title.add_theme_color_override("font_color",
			Color(1.0, 0.7, 1.0) if not is_max_tier else Color(0.45, 0.35, 0.55))
		_popup.add_child(imbue_title)

		var imbue_lbl := Label.new()
		imbue_lbl.text = "[ MAX TIER ]" if is_max_tier else "[ IMBUE WAND ]"
		imbue_lbl.position = Vector2(ox, sep_y + 126.0)
		imbue_lbl.size = Vector2(panel_w, 26.0)
		imbue_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		imbue_lbl.add_theme_font_size_override("font_size", 15)
		imbue_lbl.add_theme_color_override("font_color",
			Color(1.0, 0.75, 1.0) if can_imbue else Color(0.45, 0.30, 0.55))
		_popup.add_child(imbue_lbl)

		var imbue_btn := Button.new()
		imbue_btn.flat = true
		imbue_btn.text = ""
		imbue_btn.position = Vector2(ox, sep_y + 126.0)
		imbue_btn.size = Vector2(panel_w, 26.0)
		imbue_btn.disabled = not can_imbue
		imbue_btn.pressed.connect(_imbue_wand)
		imbue_btn.mouse_entered.connect(func() -> void:
			if can_imbue:
				imbue_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 1.0)))
		imbue_btn.mouse_exited.connect(func() -> void:
			imbue_lbl.add_theme_color_override("font_color",
				Color(1.0, 0.75, 1.0) if can_imbue else Color(0.45, 0.30, 0.55)))
		_popup.add_child(imbue_btn)

		# Transmute — picks the wand's shoot type. Opens a sub-popup with
		# the 8 shoot types so the player can target a specific build (e.g.
		# convert a Sloppy Beam to a clean Pierce). Costs more than a forge
		# (200g base) since it dramatically reshapes the wand.
		var can_transmute := GameState.gold >= _transmute_cost()
		var trans_title := Label.new()
		trans_title.text = "↻  TRANSMUTE WAND  —  %dg  —  pick a new shoot type" % _transmute_cost()
		trans_title.position = Vector2(ox, sep_y + 156.0)
		trans_title.size = Vector2(panel_w, 20.0)
		trans_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trans_title.add_theme_font_size_override("font_size", 11)
		trans_title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.85))
		_popup.add_child(trans_title)

		var trans_lbl := Label.new()
		trans_lbl.text = "[ TRANSMUTE WAND ]"
		trans_lbl.position = Vector2(ox, sep_y + 176.0)
		trans_lbl.size = Vector2(panel_w, 26.0)
		trans_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		trans_lbl.add_theme_font_size_override("font_size", 15)
		trans_lbl.add_theme_color_override("font_color",
			Color(0.55, 1.0, 0.85) if can_transmute else Color(0.30, 0.45, 0.40))
		_popup.add_child(trans_lbl)

		var trans_btn := Button.new()
		trans_btn.flat = true
		trans_btn.text = ""
		trans_btn.position = Vector2(ox, sep_y + 176.0)
		trans_btn.size = Vector2(panel_w, 26.0)
		trans_btn.disabled = not can_transmute
		trans_btn.pressed.connect(_open_transmute_picker)
		trans_btn.mouse_entered.connect(func() -> void:
			if can_transmute:
				trans_lbl.add_theme_color_override("font_color", Color(0.75, 1.0, 0.95)))
		trans_btn.mouse_exited.connect(func() -> void:
			trans_lbl.add_theme_color_override("font_color",
				Color(0.55, 1.0, 0.85) if can_transmute else Color(0.30, 0.45, 0.40)))
		_popup.add_child(trans_btn)

func _close_popup() -> void:
	if _popup:
		_popup.queue_free()
		_popup = null
		var ply := get_tree().get_first_node_in_group("player")
		if ply != null and ply.has_method("set_interface_open"):
			ply.set_interface_open(false)
		process_mode = Node.PROCESS_MODE_INHERIT
	_close_transmute_picker()
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
	_apply_affix(wand, _random_compatible_affix(wand), 1.0)
	wand.wand_forge_count += 1   # next forge on this wand is 1.5× pricier
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
	_apply_affix(wand, _random_compatible_affix(wand), 1.6)
	if player:
		FloatingText.spawn_str(player.global_position,
			"REFINED: -%s" % removed.to_upper(), Color(0.85, 0.55, 1.0), get_tree().current_scene)
	InventoryManager.inventory_changed.emit()
	_build_ui()

# Imbue — bumps a wand's rarity tier. COMMON → RARE → LEGENDARY (capped).
# Also hard-rerolls damage on the new tier band and grants a free affix
# so the upgrade is visibly stronger, not just a name change. Steep cost
# (250g base) keeps it as a milestone payoff rather than a routine action.
func _imbue_wand() -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		return
	var player := InventoryManager._player_ref
	if wand.rarity >= Item.RARITY_LEGENDARY:
		if player:
			FloatingText.spawn_str(player.global_position,
				"ALREADY LEGENDARY", Color(1.0, 0.6, 0.2), get_tree().current_scene)
		return
	if GameState.gold < _imbue_cost():
		if player:
			FloatingText.spawn_str(player.global_position,
				"Need %dg" % _imbue_cost(), Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	GameState.gold -= _imbue_cost()
	wand.rarity += 1
	# Damage tier-up — pull a fresh roll from the new rarity band so the
	# upgrade actually packs more punch. Mirrors the bands in
	# ItemDB.generate_wand: COMMON 2-3, UNCOMMON 2-4, RARE 3-5, LEGENDARY 5-10.
	match wand.rarity:
		Item.RARITY_UNCOMMON:  wand.wand_damage = maxi(wand.wand_damage, randi_range(2, 4))
		Item.RARITY_RARE:      wand.wand_damage = maxi(wand.wand_damage, randi_range(3, 5))
		Item.RARITY_LEGENDARY: wand.wand_damage = maxi(wand.wand_damage, randi_range(5, 10))
	# Free bonus affix at 1.4× scale — between forge (1.0×) and refine (1.6×).
	# Note: imbue increments rarity FIRST, so a wand that just became
	# legendary in this call already passes the legendary check inside
	# _random_compatible_affix and can roll either pierce or ricochet.
	_apply_affix(wand, _random_compatible_affix(wand), 1.4)
	# Visual color shift to match the new tier (mirrors ItemDB).
	match wand.rarity:
		Item.RARITY_LEGENDARY:
			wand.color = wand.color.lerp(Color(1.0, 0.55, 1.0), 0.45)
		Item.RARITY_RARE:
			wand.color = wand.color.lerp(Color(1.0, 0.92, 0.45), 0.30)
		Item.RARITY_UNCOMMON:
			wand.color = wand.color.lerp(Color(0.45, 1.0, 0.55), 0.25)
	if player:
		var label: String = "IMBUED!"
		match wand.rarity:
			Item.RARITY_UNCOMMON:  label = "IMBUED → UNCOMMON"
			Item.RARITY_RARE:      label = "IMBUED → RARE"
			Item.RARITY_LEGENDARY: label = "IMBUED → LEGENDARY"
		FloatingText.spawn_str(player.global_position,
			label, Color(1.0, 0.7, 1.0), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("crystal", randf_range(0.95, 1.10))
	InventoryManager.inventory_changed.emit()
	_build_ui()

# Sub-overlay for picking the transmute target shoot type. Spawns above
# the main enchant popup so the user can cancel without losing context.
# Each tile costs the player 0g — the gold is deducted in _do_transmute
# only when a type is actually chosen.
const _TRANS_TYPES: Array = ["pierce", "ricochet", "shotgun", "freeze",
	"fire", "shock", "homing", "nova"]

var _transmute_overlay: CanvasLayer = null

func _open_transmute_picker() -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		return
	if GameState.gold < _transmute_cost():
		var p1 := InventoryManager._player_ref
		if p1:
			FloatingText.spawn_str(p1.global_position,
				"Need %dg" % _transmute_cost(),
				Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	if is_instance_valid(_transmute_overlay):
		_transmute_overlay.queue_free()
	_transmute_overlay = CanvasLayer.new()
	_transmute_overlay.layer = 14
	get_tree().current_scene.add_child(_transmute_overlay)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_transmute_overlay.add_child(dim)

	var pw := 560.0
	var ph := 280.0
	var ox2 := (1600.0 - pw) / 2.0
	var oy2 := (900.0 - ph) / 2.0
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.10, 0.08, 0.97)
	bg.position = Vector2(ox2, oy2)
	bg.size = Vector2(pw, ph)
	_transmute_overlay.add_child(bg)
	var border := ColorRect.new()
	border.color = Color(0.30, 0.85, 0.65, 0.85)
	border.position = Vector2(ox2 - 2.0, oy2 - 2.0)
	border.size = Vector2(pw + 4.0, ph + 4.0)
	border.z_index = -1
	_transmute_overlay.add_child(border)

	var title := Label.new()
	title.text = "↻  TRANSMUTE — pick a shoot type  (current: %s)" % wand.wand_shoot_type.to_upper()
	title.position = Vector2(ox2, oy2 + 12.0)
	title.size = Vector2(pw, 24.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.85))
	_transmute_overlay.add_child(title)

	# 4×2 grid of type tiles.
	var tw := 120.0
	var th := 56.0
	var gap := 8.0
	var grid_x: float = ox2 + (pw - (4.0 * tw + 3.0 * gap)) / 2.0
	var grid_y: float = oy2 + 50.0
	for i in _TRANS_TYPES.size():
		var stype: String = _TRANS_TYPES[i]
		var col_i: int = i % 4
		var row_i: int = i / 4
		var tx: float = grid_x + float(col_i) * (tw + gap)
		var ty: float = grid_y + float(row_i) * (th + gap)
		var tile := ColorRect.new()
		var tcol: Color = _shoot_type_tint(stype)
		tile.color = tcol.darkened(0.55)
		tile.position = Vector2(tx, ty)
		tile.size = Vector2(tw, th)
		_transmute_overlay.add_child(tile)
		var lbl := Label.new()
		lbl.text = stype.to_upper()
		lbl.position = Vector2(tx, ty + 18.0)
		lbl.size = Vector2(tw, 22.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.add_theme_color_override("font_color",
			Color(0.55, 0.55, 0.55) if stype == wand.wand_shoot_type
			else tcol.lightened(0.35))
		_transmute_overlay.add_child(lbl)
		var btn := Button.new()
		btn.flat = true
		btn.position = Vector2(tx, ty)
		btn.size = Vector2(tw, th)
		btn.disabled = (stype == wand.wand_shoot_type)
		var t_cap := stype
		btn.pressed.connect(func() -> void:
			_do_transmute(t_cap))
		_transmute_overlay.add_child(btn)

	var cancel_lbl := Label.new()
	cancel_lbl.text = "[ CANCEL ]"
	cancel_lbl.position = Vector2(ox2, oy2 + ph - 36.0)
	cancel_lbl.size = Vector2(pw, 22.0)
	cancel_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cancel_lbl.add_theme_font_size_override("font_size", 13)
	cancel_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_transmute_overlay.add_child(cancel_lbl)
	var cancel_btn := Button.new()
	cancel_btn.flat = true
	cancel_btn.position = Vector2(ox2, oy2 + ph - 36.0)
	cancel_btn.size = Vector2(pw, 22.0)
	cancel_btn.pressed.connect(_close_transmute_picker)
	_transmute_overlay.add_child(cancel_btn)

func _close_transmute_picker() -> void:
	if is_instance_valid(_transmute_overlay):
		_transmute_overlay.queue_free()
	_transmute_overlay = null

func _do_transmute(target_type: String) -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		_close_transmute_picker()
		return
	if GameState.gold < _transmute_cost():
		_close_transmute_picker()
		return
	if target_type == wand.wand_shoot_type:
		_close_transmute_picker()
		return
	GameState.gold -= _transmute_cost()
	wand.wand_shoot_type = target_type
	# Clear type-specific stat fields so the new type doesn't drag legacy
	# values from the old one (e.g. a pierce wand transmuted to nova
	# shouldn't keep its pierce count).
	wand.wand_pierce        = 0
	wand.wand_ricochet      = 0
	wand.wand_status_stacks = 0
	# Reseed the type-specific fields with sensible defaults for the new
	# shoot type — mirrors the shoot-type adjustments in ItemDB.generate_wand.
	match target_type:
		"pierce":   wand.wand_pierce        = randi_range(1, 2 + wand.rarity)
		"ricochet": wand.wand_ricochet      = randi_range(1, 2 + wand.rarity)
		"freeze", "fire", "shock":
			wand.wand_status_stacks = randi_range(1, 1 + wand.rarity)
	# Update the wand's icon glyph so the inventory matches the new type.
	wand.icon_char = ItemDB._wand_icon_for_type(target_type)
	# Visual feedback
	var p2 := InventoryManager._player_ref
	if p2:
		FloatingText.spawn_str(p2.global_position,
			"TRANSMUTED → %s" % target_type.to_upper(),
			_shoot_type_tint(target_type), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("crystal", randf_range(0.92, 1.08))
	_close_transmute_picker()
	InventoryManager.inventory_changed.emit()
	if p2 and p2.has_method("update_equip_stats"):
		p2.update_equip_stats()
	_build_ui()

# Per-shoot-type tint for the transmute picker tiles. Mirrors the wand
# colour palette in ItemDB so the player makes the visual association.
func _shoot_type_tint(stype: String) -> Color:
	match stype:
		"pierce":   return Color(0.95, 0.95, 0.30)
		"ricochet": return Color(0.35, 1.00, 0.50)
		"shotgun":  return Color(1.00, 0.65, 0.20)
		"freeze":   return Color(0.30, 0.75, 1.00)
		"fire":     return Color(1.00, 0.40, 0.10)
		"shock":    return Color(0.90, 0.95, 0.30)
		"homing":   return Color(0.55, 0.30, 1.00)
		"nova":     return Color(0.85, 0.40, 1.00)
	return Color(0.70, 0.70, 0.70)

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

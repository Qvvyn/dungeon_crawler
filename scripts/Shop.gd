extends Area2D

# Village Shop — fixed-price buys (potions + bottom-tier wand) and a
# one-click "sell all junk" that liquidates non-equipped commons for gold.
# Charges Run Gold; if you want it to come from the Bank, deposit + use
# the Bank's withdraw flow first.

const POTION_COST          := 40
const COMMON_WAND_COST     := 120
const RARE_WAND_COST       := 400
const LEGENDARY_WAND_COST  := 1200

# Wands rolled by ItemDB scale up with the active difficulty, so deep-tier
# shops sell deep-tier wands. Without this the village shop trivialised
# the upgrade pipeline once a player started doing Catacombs / Hellpit
# runs (a 1200g legendary that auto-rolls at +diff was a steal). Linear
# slope: each +1 difficulty adds 50% to the base price.
func _wand_price_scale() -> float:
	var d: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	return 1.0 + maxf(0.0, d - 1.0) * 0.5

func _common_wand_cost()    -> int: return int(round(float(COMMON_WAND_COST)    * _wand_price_scale()))
func _rare_wand_cost()      -> int: return int(round(float(RARE_WAND_COST)      * _wand_price_scale()))
func _legendary_wand_cost() -> int: return int(round(float(LEGENDARY_WAND_COST) * _wand_price_scale()))

var _player_in_range: bool = false
var _ui: CanvasLayer = null
var _gold_label: Label = null

func _ready() -> void:
	add_to_group("interactable")   # bullets pass through (Projectile group check)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	GameState.attach_fp_visual(self, "S", Color(0.55, 1.0, 0.55), 0.55)

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
	panel.color = Color(0.05, 0.06, 0.10, 0.97)
	panel.position = Vector2(380, 140)
	panel.size = Vector2(840, 620)
	_ui.add_child(panel)

	var border := ColorRect.new()
	border.color = Color(0.55, 0.80, 1.0, 0.65)
	border.position = Vector2(377, 137)
	border.size = Vector2(846, 626)
	_ui.add_child(border)
	_ui.move_child(panel, -1)

	var title := Label.new()
	title.text = "— ITEM SHOP —"
	title.position = Vector2(380, 156)
	title.size = Vector2(840, 44)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.55, 0.80, 1.0))
	_ui.add_child(title)

	_gold_label = Label.new()
	_gold_label.position = Vector2(380, 208)
	_gold_label.size = Vector2(840, 28)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	_ui.add_child(_gold_label)

	# Buy buttons — tiered wand offerings + a single potion.
	_add_shop_row("Health Potion (+30% HP)", POTION_COST,
		Vector2(420, 260), Color(0.55, 0.95, 0.55), _buy_potion)
	_add_shop_row("Common Wand (random roll)", _common_wand_cost(),
		Vector2(420, 308), Color(0.85, 0.85, 0.95), _buy_common_wand)
	_add_shop_row("Rare Wand (random roll)", _rare_wand_cost(),
		Vector2(420, 356), Color(0.55, 0.7, 1.0), _buy_rare_wand)
	_add_shop_row("Legendary Wand (random roll)", _legendary_wand_cost(),
		Vector2(420, 404), Color(1.0, 0.6, 0.2), _buy_legendary_wand)

	# Sell rows — separate buttons for commons (half) and rares+ (half too,
	# but it's a deliberate choice rather than a one-button "sell all").
	var sell_lbl := Label.new()
	sell_lbl.text = "[ SELL ALL COMMON & UNCOMMON (half value) ]"
	sell_lbl.position = Vector2(420, 472)
	sell_lbl.size = Vector2(760, 36)
	sell_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_lbl.add_theme_font_size_override("font_size", 17)
	sell_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	_ui.add_child(sell_lbl)

	var sell_btn := Button.new()
	sell_btn.flat = true
	sell_btn.position = Vector2(420, 472)
	sell_btn.size = Vector2(760, 36)
	sell_btn.pressed.connect(_sell_all_commons)
	_ui.add_child(sell_btn)

	var sell_rare_lbl := Label.new()
	sell_rare_lbl.text = "[ SELL ALL RARES & LEGENDARIES (half value) ]"
	sell_rare_lbl.position = Vector2(420, 516)
	sell_rare_lbl.size = Vector2(760, 36)
	sell_rare_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sell_rare_lbl.add_theme_font_size_override("font_size", 16)
	sell_rare_lbl.add_theme_color_override("font_color", Color(0.7, 0.55, 1.0))
	_ui.add_child(sell_rare_lbl)

	var sell_rare_btn := Button.new()
	sell_rare_btn.flat = true
	sell_rare_btn.position = Vector2(420, 516)
	sell_rare_btn.size = Vector2(760, 36)
	sell_rare_btn.pressed.connect(_sell_all_rares)
	_ui.add_child(sell_rare_btn)

	# Close
	var close_lbl := Label.new()
	close_lbl.text = "[ CLOSE ]"
	close_lbl.position = Vector2(680, 700)
	close_lbl.size = Vector2(240, 36)
	close_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_lbl.add_theme_font_size_override("font_size", 16)
	close_lbl.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	_ui.add_child(close_lbl)

	var close_btn := Button.new()
	close_btn.flat = true
	close_btn.position = Vector2(680, 700)
	close_btn.size = Vector2(240, 36)
	close_btn.pressed.connect(func() -> void: _close())
	_ui.add_child(close_btn)

	_refresh_gold()

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

func _refresh_gold() -> void:
	if _gold_label == null:
		return
	_gold_label.text = "Run Gold: %d   Bank Gold: %d" % [
		GameState.gold, PersistentStash.bank_gold]

func _add_shop_row(name: String, cost: int, pos: Vector2,
		col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text = "[ BUY: %s — %dg ]" % [name, cost]
	lbl.position = pos
	lbl.size = Vector2(760, 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", col)
	_ui.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.position = pos
	btn.size = Vector2(760, 36)
	btn.pressed.connect(cb)
	_ui.add_child(btn)

# ── Transactions ───────────────────────────────────────────────────────────

func _buy_potion() -> void:
	if not _spend(POTION_COST):
		return
	# Pull the Health Potion template out of the master item table. The
	# `add_item` flow handles stacking with any potions already in the bag.
	var pot: Item = null
	for it in ItemDB.all_items():
		if it != null and it.type == Item.Type.POTION \
				and it.display_name == "Health Potion":
			pot = it
			break
	if pot == null:
		GameState.gold += POTION_COST
		return
	# Clone so the shop's master template doesn't share quantity with
	# the player's inventory.
	pot = Item.from_dict(pot.to_dict())
	if not InventoryManager.add_item(pot):
		# Inventory full — refund.
		GameState.gold += POTION_COST
		FloatingText.spawn_str(global_position, "INVENTORY FULL",
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	FloatingText.spawn_str(global_position, "+ Health Potion",
		Color(0.55, 0.95, 0.55), get_tree().current_scene)
	_refresh_gold()

func _buy_common_wand() -> void:    _buy_wand_at(Item.RARITY_COMMON,    _common_wand_cost(),    Color(0.85, 0.85, 0.95))
func _buy_rare_wand() -> void:      _buy_wand_at(Item.RARITY_RARE,      _rare_wand_cost(),      Color(0.55, 0.7, 1.0))
func _buy_legendary_wand() -> void: _buy_wand_at(Item.RARITY_LEGENDARY, _legendary_wand_cost(), Color(1.0, 0.6, 0.2))

func _buy_wand_at(rarity: int, cost: int, announce_col: Color) -> void:
	if not _spend(cost):
		return
	var w := ItemDB.generate_wand(rarity)
	if w == null:
		GameState.gold += cost
		return
	if not InventoryManager.add_item(w):
		GameState.gold += cost
		FloatingText.spawn_str(global_position, "INVENTORY FULL",
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	FloatingText.spawn_str(global_position, "+ %s" % w.display_name,
		announce_col, get_tree().current_scene)
	_refresh_gold()

func _sell_all_commons() -> void:
	# Bundle uncommon with common so the low-tier auto-sell catches both
	# instead of leaving uncommons stuck in the bag.
	_sell_all_of_rarity([Item.RARITY_COMMON, Item.RARITY_UNCOMMON],
		Color(1.0, 0.85, 0.40))

func _sell_all_rares() -> void:
	_sell_all_of_rarity([Item.RARITY_RARE, Item.RARITY_LEGENDARY],
		Color(0.7, 0.55, 1.0))

func _sell_all_of_rarity(rarities: Array, announce_col: Color) -> void:
	var earned := 0
	for i in InventoryManager.grid.size():
		var it: Item = InventoryManager.grid[i] as Item
		if it == null:
			continue
		if not (it.rarity in rarities):
			continue
		# Stack-aware: a slot of 8 gems credits 8× the per-item half value.
		earned += int(it.sell_value * 0.5) * maxi(1, it.quantity)
		InventoryManager.grid[i] = null
	if earned > 0:
		GameState.gold += earned
		InventoryManager.inventory_changed.emit()
		FloatingText.spawn_str(global_position, "+ %dg" % earned,
			announce_col, get_tree().current_scene)
	else:
		FloatingText.spawn_str(global_position, "NOTHING TO SELL",
			Color(0.7, 0.7, 0.8), get_tree().current_scene)
	_refresh_gold()

func _spend(cost: int) -> bool:
	if GameState.gold < cost:
		FloatingText.spawn_str(global_position,
			"Need %dg" % cost,
			Color(1.0, 0.45, 0.45),
			get_tree().current_scene)
		return false
	GameState.gold -= cost
	return true

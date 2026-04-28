extends Area2D

# A one-time room feature. When the player walks onto it, a small UI overlay
# shows three blessings — Heal, Random Stat boost (+5 for the run), or Mana
# Surge (refill + temp speed buff). The shrine becomes inactive after use.

const F_ACTIVE := " /^\\ \n[ + ]\n \\v/ "
const F_USED   := " ,_, \n[ . ]\n '_' "
const CHECKPOINT_COST: int = 100
# Cost to refill the equipped limited-use wand. Cheap relative to the wand's
# sell value so investing in a fresh charge is a real option, not strictly
# worse than buying anything else.
const RECHARGE_COST:   int = 60

var _used: bool       = false
var _ui_layer: CanvasLayer = null
var _player: Node2D = null
var _label: Label   = null
var _anim_t: float  = 0.0
var _anim_pulse: float = 0.0

static var _shared_font: Font = null

func _ready() -> void:
	add_to_group("shrine")
	body_entered.connect(_on_body_entered)
	if _shared_font == null:
		_shared_font = MonoFont.get_font()
	_label = $AsciiChar
	if _label:
		_label.add_theme_font_override("font", _shared_font)
		_label.text = F_ACTIVE

func _process(delta: float) -> void:
	if _used or _label == null:
		return
	# Soft glow pulse so the shrine reads as "interactive"
	_anim_pulse += delta
	var p := sin(_anim_pulse * 1.6) * 0.18 + 0.82
	_label.modulate = Color(p, p * 0.95, 1.0, 1.0)

func _on_body_entered(body: Node) -> void:
	if _used:
		return
	if not body.is_in_group("player"):
		return
	_player = body as Node2D
	# Autoplay skips the choice UI and picks intelligently
	if _player.get("_autoplay") == true:
		_auto_pick()
	else:
		_open_choice_ui()

func _auto_pick() -> void:
	# Heal if low HP, otherwise random between stat boost and mana surge.
	# Bot grabs a checkpoint when reasonably deep and gold-rich — saves
	# progress so it doesn't lose the run to a one-shot mistake later.
	var hp: int = int(_player.get("health"))
	var max_hp: int = int(_player.call("_max_hp")) if _player.has_method("_max_hp") else 10
	var hp_ratio: float = 1.0 if max_hp <= 0 else float(hp) / float(max_hp)
	if hp_ratio < 0.55:
		_choose_heal()
	elif GameState.portals_used >= 3 and GameState.gold >= CHECKPOINT_COST + 50:
		_choose_checkpoint()
	elif randf() < 0.65:
		_choose_stat()
	else:
		_choose_mana()

func _open_choice_ui() -> void:
	if _ui_layer != null:
		return
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 22
	_ui_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().current_scene.add_child(_ui_layer)
	get_tree().paused = true
	if is_instance_valid(_player):
		_player.set("_is_paused", true)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(dim)

	var border := ColorRect.new()
	border.color = Color(0.35, 0.45, 0.65, 0.95)
	border.position = Vector2(540, 270)
	border.size     = Vector2(520, 410)
	_ui_layer.add_child(border)
	var inner := ColorRect.new()
	inner.color = Color(0.04, 0.05, 0.10, 0.97)
	inner.position = Vector2(543, 273)
	inner.size     = Vector2(514, 404)
	_ui_layer.add_child(inner)

	var title := Label.new()
	title.text = "— SHRINE OF REST —"
	title.position = Vector2(543, 286)
	title.size     = Vector2(514, 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_ui_layer.add_child(title)

	_make_choice_btn("Restore HP & Mana",   Vector2(580, 320), Color(0.5, 1.0, 0.6), _choose_heal)
	_make_choice_btn("+5 Random Stat (run)", Vector2(580, 372), Color(1.0, 0.85, 0.3), _choose_stat)
	_make_choice_btn("Mana Surge + Haste",   Vector2(580, 424), Color(0.5, 0.7, 1.0), _choose_mana)
	# Recharge option only visible when a limited-use wand is equipped — keeps
	# the menu un-cluttered when the player isn't holding a chargeable wand.
	var equipped_wand: Item = InventoryManager.equipped.get("wand") as Item
	if equipped_wand != null and equipped_wand.is_limited_use():
		var rc_label := "Recharge Wand (%dg)" % RECHARGE_COST
		var rc_color := Color(1.0, 0.85, 0.3) if GameState.gold >= RECHARGE_COST else Color(0.4, 0.35, 0.2)
		_make_choice_btn(rc_label, Vector2(580, 476), rc_color, _choose_recharge)
		var ck_label := "Checkpoint (%dg)" % CHECKPOINT_COST
		var ck_color := Color(0.85, 0.55, 1.0) if GameState.gold >= CHECKPOINT_COST else Color(0.4, 0.3, 0.5)
		_make_choice_btn(ck_label, Vector2(580, 528), ck_color, _choose_checkpoint)
		_make_choice_btn("Walk Away",        Vector2(580, 580), Color(0.6, 0.6, 0.7), _choose_skip)
	else:
		var ck_label := "Checkpoint (%dg)" % CHECKPOINT_COST
		var ck_color := Color(0.85, 0.55, 1.0) if GameState.gold >= CHECKPOINT_COST else Color(0.4, 0.3, 0.5)
		_make_choice_btn(ck_label, Vector2(580, 520), ck_color, _choose_checkpoint)
		_make_choice_btn("Walk Away",        Vector2(580, 580), Color(0.6, 0.6, 0.7), _choose_skip)

func _make_choice_btn(txt: String, pos: Vector2, col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text = "[ %s ]" % txt
	lbl.position = pos
	lbl.size     = Vector2(440, 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", col)
	_ui_layer.add_child(lbl)
	var btn := Button.new()
	btn.flat     = true
	btn.position = pos - Vector2(4, 2)
	btn.size     = Vector2(448, 40)
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col.lightened(0.35)))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col))
	btn.pressed.connect(cb)
	_ui_layer.add_child(btn)

func _close_ui() -> void:
	# Only un-pause if we actually paused (auto-pick path skips UI entirely)
	if is_instance_valid(_ui_layer):
		get_tree().paused = false
		if is_instance_valid(_player):
			_player.set("_is_paused", false)
		_ui_layer.queue_free()
	_ui_layer = null

func _consume() -> void:
	_used = true
	_close_ui()
	if _label:
		_label.text = F_USED
		_label.add_theme_color_override("font_color", Color(0.35, 0.30, 0.40, 0.6))
	if SoundManager:
		SoundManager.play("room_clear")

func _choose_heal() -> void:
	if is_instance_valid(_player) and _player.has_method("heal_to_full"):
		_player.heal_to_full()
	FloatingText.spawn_str(global_position, "RESTORED!", Color(0.5, 1.0, 0.6), get_tree().current_scene)
	_consume()

func _choose_stat() -> void:
	var stat_name: String = GameState.STAT_NAMES[randi() % GameState.STAT_NAMES.size()]
	var current: int = int(GameState.run_stat_bonuses.get(stat_name, 0))
	GameState.run_stat_bonuses[stat_name] = current + 5
	# Notify player so equip-derived stats refresh (max HP, stamina, etc.)
	if is_instance_valid(_player) and _player.has_method("update_equip_stats"):
		_player.update_equip_stats()
	FloatingText.spawn_str(global_position, "+5 " + stat_name + "!", Color(1.0, 0.85, 0.3), get_tree().current_scene)
	_consume()

func _choose_mana() -> void:
	if is_instance_valid(_player):
		_player.set("mana", _player.get("max_mana"))
		if _player.has_method("apply_buff"):
			_player.apply_buff(15.0)   # existing 2x speed/firerate buff
	FloatingText.spawn_str(global_position, "MANA SURGE!", Color(0.5, 0.7, 1.0), get_tree().current_scene)
	_consume()

func _choose_checkpoint() -> void:
	if GameState.gold < CHECKPOINT_COST:
		FloatingText.spawn_str(global_position, "Need %dg" % CHECKPOINT_COST,
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	GameState.gold -= CHECKPOINT_COST
	if is_instance_valid(_player) and _player.has_method("_save_run"):
		_player._save_run()
	FloatingText.spawn_str(global_position, "CHECKPOINT!",
		Color(0.85, 0.55, 1.0), get_tree().current_scene)
	_consume()

func _choose_recharge() -> void:
	if GameState.gold < RECHARGE_COST:
		FloatingText.spawn_str(global_position, "Need %dg" % RECHARGE_COST,
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or not wand.is_limited_use():
		# Defensive — UI shouldn't have shown this option, but bail rather
		# than charge gold for nothing if the equipped wand changed mid-pick.
		FloatingText.spawn_str(global_position, "No charged wand!",
			Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	GameState.gold -= RECHARGE_COST
	wand.wand_charges = wand.wand_max_charges
	InventoryManager.inventory_changed.emit()
	FloatingText.spawn_str(global_position, "RECHARGED!",
		Color(1.0, 0.85, 0.3), get_tree().current_scene)
	_consume()

func _choose_skip() -> void:
	_close_ui()

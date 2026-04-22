extends CharacterBody2D

const INVENTORY_UI_SCENE := preload("res://scenes/InventoryUI.tscn")

@export var speed: float = 300.0
@export var fire_rate: float = 0.15
@export var max_health: int = 10
@export var projectile_scene: PackedScene

var health: int = 10
var _shoot_cooldown: float = 0.0
var _is_dead: bool = false
var _is_paused: bool = false
var _pause_menu: CanvasLayer = null
var _buff_timer: float = 0.0
var _speed_multiplier: float = 1.0
var _fire_rate_multiplier: float = 1.0

# Equipment stat bonuses (applied by InventoryManager)
var _equip_speed_bonus: float = 0.0
var _equip_health_bonus: int = 0
var _equip_fire_rate_bonus: float = 0.0
var _equip_block_chance: float = 0.0
var _equip_projectile_count: int = 0
var _equip_wisdom_bonus: float = 0.0

# Mana
var mana: float = 10.0
var max_mana: float = 100.0
const BASE_WISDOM: float = 25.0   # mana/sec base regen
var _mana_bar_fg: ColorRect = null
var _mana_label: Label = null

# Beam wand
var _beam_line: Line2D = null

var _inventory_ui: Node = null

# Status effects
var _slow_timer:   float = 0.0
var _poison_timer: float = 0.0
var _poison_tick:  float = 0.0

# Dash
var _dash_cooldown:    float = 0.0
var _dash_timer:       float = 0.0   # > 0 while actively dashing
var _dash_dir:         Vector2 = Vector2.ZERO
var _is_invincible:    bool = false
const DASH_SPEED           := 900.0
const DASH_DURATION        := 0.18
const DASH_COOLDOWN        := 1.5
const BASE_SHOT_MANA_COST  := 3.0   # mana cost when firing without a wand equipped

# Levitate
var _is_levitating:         bool = false
const LEVITATE_MANA_COST    := 50.0

# Shield
var _is_shielding:          bool = false
var _shield_area:            Area2D = null
var _shield_visual:          Line2D = null
var _shield_glow:            Line2D = null
const SHIELD_MANA_PER_SEC   := 10.0
const SHIELD_MANA_PER_DMG   := 5.0
const SHIELD_RADIUS          := 48.0

# HUD references created programmatically
var _gold_label: Label = null

# Wizard ASCII animation
const WIZARD_F0 := "/^\\\n(o)\n/|\\"
const WIZARD_F1 := "/^\\\n(o)\n\\|/"
var _ascii_label: Label   = null
var _anim_timer: float    = 0.0
var _anim_frame: int      = 0
var _level_label: Label = null
var _xp_bar_fg: ColorRect = null

func _ready() -> void:
	# Player must always process so ESC (pause toggle) works while tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Restore HP if arriving via portal, otherwise start fresh (or load saved run)
	if GameState.has_saved_state:
		health = GameState.player_health
		GameState.has_saved_state = false
	else:
		_try_load_save()
		if not GameState.has_saved_state:
			health = max_health
			GameState.reset_run_stats()
		else:
			health = GameState.player_health
			GameState.has_saved_state = false

	_update_health_bar()

	if projectile_scene == null:
		projectile_scene = load("res://scenes/Projectile.tscn")

	$HUD/DeathMenu/RetryButton.pressed.connect(_on_retry)
	$HUD/DeathMenu/QuitButton.pressed.connect(_on_quit)
	$HUD/DeathMenu/TitleButton.pressed.connect(_on_title)

	GameState.leveled_up.connect(_on_level_up)
	_setup_hud_additions()
	# Register dash action if not already in the project input map
	if not InputMap.has_action("dash"):
		InputMap.add_action("dash")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("dash", ev)

	if not InputMap.has_action("levitate"):
		InputMap.add_action("levitate")
		var ev_lev := InputEventKey.new()
		ev_lev.physical_keycode = KEY_SPACE
		InputMap.action_add_event("levitate", ev_lev)

	_setup_pause_menu()
	_setup_shield()

	_ascii_label = $AsciiChar
	_ascii_label.text = WIZARD_F0

	# Inventory UI
	var inv_ui := INVENTORY_UI_SCENE.instantiate()
	add_child(inv_ui)
	_inventory_ui = inv_ui
	InventoryManager.register_player(self)
	# Reapply all equipment bonuses — required after portal reloads
	update_equip_stats()

func _setup_hud_additions() -> void:
	var hud := $HUD

	# Gold label — below the kills label
	_gold_label = Label.new()
	_gold_label.name = "GoldLabel"
	_gold_label.text = "G: 0"
	_gold_label.position = Vector2(220, 32)
	_gold_label.size = Vector2(160, 18)
	_gold_label.add_theme_font_size_override("font_size", 13)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	hud.add_child(_gold_label)

	# XP bar background (bottom-center, 400 px wide)
	var xp_bg := ColorRect.new()
	xp_bg.name = "XPBarBG"
	xp_bg.color = Color(0.1, 0.05, 0.2)
	xp_bg.position = Vector2(600, 878)
	xp_bg.size = Vector2(400, 14)
	hud.add_child(xp_bg)

	# XP bar foreground — width updated each frame
	_xp_bar_fg = ColorRect.new()
	_xp_bar_fg.name = "XPBarFG"
	_xp_bar_fg.color = Color(0.5, 0.1, 1.0)
	_xp_bar_fg.position = Vector2(600, 878)
	_xp_bar_fg.size = Vector2(0.0, 14.0)
	hud.add_child(_xp_bar_fg)

	# Mana bar background (sits just below the health bar)
	var mana_bg := ColorRect.new()
	mana_bg.name = "ManaBarBG"
	mana_bg.color = Color(0.05, 0.05, 0.25)
	mana_bg.position = Vector2(10, 33)
	mana_bg.size = Vector2(202, 12)
	hud.add_child(mana_bg)

	_mana_bar_fg = ColorRect.new()
	_mana_bar_fg.name = "ManaBarFG"
	_mana_bar_fg.color = Color(0.15, 0.45, 1.0)
	_mana_bar_fg.position = Vector2(11, 34)
	_mana_bar_fg.size = Vector2(10.0, 10.0)   # width updated each frame
	hud.add_child(_mana_bar_fg)

	_mana_label = Label.new()
	_mana_label.name = "ManaLabel"
	_mana_label.position = Vector2(10, 45)
	_mana_label.size = Vector2(120, 16)
	_mana_label.add_theme_font_size_override("font_size", 10)
	_mana_label.add_theme_color_override("font_color", Color(0.4, 0.65, 1.0))
	hud.add_child(_mana_label)

	# Dash cooldown label
	var dash_lbl := Label.new()
	dash_lbl.name = "DashLabel"
	dash_lbl.text = "DASH [SHIFT]"
	dash_lbl.position = Vector2(10, 55)
	dash_lbl.size = Vector2(150, 18)
	dash_lbl.add_theme_font_size_override("font_size", 11)
	dash_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	hud.add_child(dash_lbl)

	# Level label — just left of the XP bar
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.text = "LVL 1"
	_level_label.position = Vector2(530, 872)
	_level_label.size = Vector2(65, 20)
	_level_label.add_theme_font_size_override("font_size", 13)
	_level_label.add_theme_color_override("font_color", Color(0.8, 0.6, 1.0))
	hud.add_child(_level_label)

	# Ability status labels
	var lev_lbl := Label.new()
	lev_lbl.name = "LevitateLabel"
	lev_lbl.text = "LEVITATE [SPACE]"
	lev_lbl.position = Vector2(10, 69)
	lev_lbl.size = Vector2(200, 16)
	lev_lbl.add_theme_font_size_override("font_size", 11)
	lev_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	hud.add_child(lev_lbl)

	var shd_lbl := Label.new()
	shd_lbl.name = "ShieldLabel"
	shd_lbl.text = "SHIELD [RMB]"
	shd_lbl.position = Vector2(10, 83)
	shd_lbl.size = Vector2(200, 16)
	shd_lbl.add_theme_font_size_override("font_size", 11)
	shd_lbl.add_theme_color_override("font_color", Color(0.35, 0.6, 1.0))
	hud.add_child(shd_lbl)

# ── Pause menu ────────────────────────────────────────────────────────────────

func _setup_pause_menu() -> void:
	_pause_menu = CanvasLayer.new()
	_pause_menu.layer        = 25
	_pause_menu.visible      = false
	_pause_menu.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_pause_menu)

	var bg := ColorRect.new()
	bg.color  = Color(0.0, 0.0, 0.0, 0.72)
	bg.position = Vector2.ZERO
	bg.size     = Vector2(1600, 900)
	_pause_menu.add_child(bg)

	var border := ColorRect.new()
	border.color    = Color(0.28, 0.18, 0.45, 0.9)
	border.position = Vector2(580, 250)
	border.size     = Vector2(440, 340)
	_pause_menu.add_child(border)

	var inner := ColorRect.new()
	inner.color    = Color(0.04, 0.02, 0.09, 0.97)
	inner.position = Vector2(583, 253)
	inner.size     = Vector2(434, 334)
	_pause_menu.add_child(inner)

	var title := Label.new()
	title.text     = "— PAUSED —"
	title.position = Vector2(586, 268)
	title.size     = Vector2(428, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_pause_menu.add_child(title)

	_pause_btn("RESUME",       Vector2(640, 340), Color(0.4, 0.9, 0.5),  _resume_game)
	_pause_btn("SAVE RUN",     Vector2(640, 410), Color(0.5, 0.75, 1.0), _save_run)
	_pause_btn("TITLE SCREEN", Vector2(640, 480), Color(0.7, 0.55, 1.0), _on_title)
	_pause_btn("QUIT",         Vector2(640, 550), Color(0.55, 0.55, 0.6),_on_quit)

func _pause_btn(txt: String, pos: Vector2, col: Color, cb: Callable) -> void:
	var lbl := Label.new()
	lbl.text     = "[ %s ]" % txt
	lbl.position = pos
	lbl.size     = Vector2(320, 36)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", col)
	_pause_menu.add_child(lbl)

	var btn := Button.new()
	btn.flat     = true
	btn.text     = ""
	btn.position = pos - Vector2(4, 2)
	btn.size     = Vector2(328, 40)
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col.lightened(0.35)))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col))
	btn.pressed.connect(cb)
	_pause_menu.add_child(btn)

func _toggle_pause() -> void:
	_is_paused = not _is_paused
	_pause_menu.visible = _is_paused
	get_tree().paused = _is_paused
	if _inventory_ui:
		_inventory_ui.visible = false

func _resume_game() -> void:
	_is_paused = false
	_pause_menu.visible = false
	get_tree().paused = false

func _save_run() -> void:
	var data := {
		"health": health,
		"mana": mana,
		"gold": GameState.gold,
		"kills": GameState.kills,
		"level": GameState.level,
		"xp": GameState.xp,
		"portals_used": GameState.portals_used,
		"difficulty": GameState.difficulty,
		"biome": GameState.biome,
		"damage_dealt": GameState.damage_dealt,
	}
	var f := FileAccess.open("user://save_run.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	FloatingText.spawn_str(global_position, "SAVED!", Color(0.4, 1.0, 0.6), get_tree().current_scene)

func _try_load_save() -> void:
	if not FileAccess.file_exists("user://save_run.json"):
		return
	var f := FileAccess.open("user://save_run.json", FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f = null
	DirAccess.remove_absolute("user://save_run.json")
	if not (parsed is Dictionary):
		return
	var data := parsed as Dictionary
	GameState.player_health  = int(data.get("health",       max_health))
	mana                     = float(data.get("mana",        10.0))
	GameState.gold           = int(data.get("gold",          0))
	GameState.kills          = int(data.get("kills",         0))
	GameState.level          = int(data.get("level",         1))
	GameState.xp             = int(data.get("xp",            0))
	GameState.portals_used   = int(data.get("portals_used",  0))
	GameState.difficulty     = float(data.get("difficulty",  1.0))
	GameState.biome          = int(data.get("biome",         0))
	GameState.damage_dealt   = int(data.get("damage_dealt",  0))
	GameState.has_saved_state = true

# ── Debug menu ─────────────────────────────────────────────────────────────────

func _debug_random_wand() -> void:
	var pool: Array = []
	for item in ItemDB.all_items():
		if item.type == Item.Type.WAND:
			pool.append(item)
	for item in ItemDB.legendary_items():
		if item.type == Item.Type.WAND:
			pool.append(item)
	if pool.is_empty():
		return
	var wand: Item = pool[randi() % pool.size()]
	InventoryManager.equipped["wand"] = wand
	InventoryManager.inventory_changed.emit()
	update_equip_stats()
	FloatingText.spawn_str(global_position, wand.display_name, Color(1.0, 0.85, 0.15), get_tree().current_scene)

func _debug_best_gear() -> void:
	var all_pool: Array = []
	all_pool.append_array(ItemDB.all_items())
	all_pool.append_array(ItemDB.legendary_items())

	for slot in ["hat", "robes", "feet", "ring", "necklace", "offhand"]:
		var best: Item = null
		var best_score := -999.0
		for candidate: Item in all_pool:
			if candidate.get_equip_slot_name() != slot:
				continue
			var s := 0.0
			s += candidate.stat_bonuses.get("max_health",          0.0) * 15.0
			s += candidate.stat_bonuses.get("speed",               0.0) * 0.4
			s += candidate.stat_bonuses.get("fire_rate_reduction",  0.0) * 120.0
			s += candidate.stat_bonuses.get("block_chance",        0.0) * 60.0
			s += candidate.stat_bonuses.get("projectile_count",    0.0) * 25.0
			s += candidate.stat_bonuses.get("wisdom",              0.0) * 2.5
			if s > best_score:
				best_score = s
				best = candidate
		if best != null:
			InventoryManager.equipped[slot] = best

	InventoryManager.inventory_changed.emit()
	update_equip_stats()
	FloatingText.spawn_str(global_position, "BEST GEAR EQUIPPED", Color(1.0, 0.85, 0.15), get_tree().current_scene)

func _debug_perfect_wand() -> void:
	var wand: Item = InventoryManager.equipped.get("wand") as Item
	if wand == null or wand.type != Item.Type.WAND:
		FloatingText.spawn_str(global_position, "No wand equipped!", Color(1.0, 0.4, 0.4), get_tree().current_scene)
		return
	wand.wand_flaws.clear()
	wand.wand_damage     = 8
	wand.wand_fire_rate  = 0.08
	wand.wand_mana_cost  = 3.0
	wand.wand_proj_speed = 900.0
	match wand.wand_shoot_type:
		"pierce":    wand.wand_pierce    = 6
		"ricochet":  wand.wand_ricochet  = 6
		"chain":     wand.wand_chain     = 8
		"beam":
			wand.wand_damage     = 15
			wand.wand_mana_cost  = 6.0
		"freeze", "fire":
			wand.wand_status_stacks = 3
	InventoryManager.inventory_changed.emit()
	FloatingText.spawn_str(global_position, "WAND PERFECTED!", Color(0.3, 1.0, 0.8), get_tree().current_scene)

# ── Mana bar ──────────────────────────────────────────────────────────────────

func _update_mana_bar() -> void:
	if _mana_bar_fg == null:
		return
	var ratio := clampf(mana / max_mana, 0.0, 1.0)
	_mana_bar_fg.size.x = 200.0 * ratio
	if _mana_label:
		_mana_label.text = "%d / %d MP" % [int(mana), int(max_mana)]

func _process(_delta: float) -> void:
	if _is_paused:
		return
	$HUD/KillsLabel.text = "Kills: " + str(GameState.kills)
	if _gold_label:
		_gold_label.text = "G: " + str(GameState.gold)
	if _level_label:
		_level_label.text = "LVL " + str(GameState.level)
	_update_xp_bar()
	_update_mana_bar()
	var dash_lbl := $HUD.get_node_or_null("DashLabel")
	if dash_lbl:
		if _dash_timer > 0.0:
			dash_lbl.text = "DASHING"
			dash_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))
		elif _dash_cooldown > 0.0:
			dash_lbl.text = "DASH %.1fs" % _dash_cooldown
			dash_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
		else:
			dash_lbl.text = "DASH [SHIFT]"
			dash_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	var lev_lbl := $HUD.get_node_or_null("LevitateLabel")
	if lev_lbl:
		if _is_levitating:
			lev_lbl.text = "** LEVITATING **"
			lev_lbl.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
		else:
			lev_lbl.text = "LEVITATE [SPACE]"
			lev_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	var shd_lbl := $HUD.get_node_or_null("ShieldLabel")
	if shd_lbl:
		if _is_shielding:
			shd_lbl.text = "** SHIELDING **"
			shd_lbl.add_theme_color_override("font_color", Color(0.2, 0.55, 1.0))
		else:
			shd_lbl.text = "SHIELD [RMB]"
			shd_lbl.add_theme_color_override("font_color", Color(0.35, 0.6, 1.0))

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if not _is_dead:
				_toggle_pause()
				get_viewport().set_input_as_handled()
		KEY_BRACKETLEFT:   # [  →  random wand
			if not _is_dead and not _is_paused:
				_debug_random_wand()
				get_viewport().set_input_as_handled()
		KEY_BRACKETRIGHT:  # ]  →  best gear
			if not _is_dead and not _is_paused:
				_debug_best_gear()
				get_viewport().set_input_as_handled()
		KEY_BACKSLASH:     # \  →  perfect wand
			if not _is_dead and not _is_paused:
				_debug_perfect_wand()
				get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if _is_dead or _is_paused:
		return
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_fire_rate_multiplier = 1.0
	# Mana regen
	var wisdom := BASE_WISDOM + _equip_wisdom_bonus
	mana = minf(mana + wisdom * delta, max_mana)
	_tick_status(delta)
	_tick_dash(delta)
	_handle_levitate(delta)
	_handle_shield(delta)
	_handle_movement()
	_handle_shooting(delta)
	_tick_wizard_anim(delta)
	_update_player_visual()

func _tick_wizard_anim(delta: float) -> void:
	if _ascii_label == null:
		return
	# Animate when moving or recently shot
	var is_active := velocity.length_squared() > 100.0 or _shoot_cooldown > 0.0
	if is_active:
		_anim_timer += delta
		if _anim_timer >= 0.22:
			_anim_timer = 0.0
			_anim_frame = 1 - _anim_frame
	else:
		_anim_frame = 0
		_anim_timer = 0.0
	_ascii_label.text = WIZARD_F0 if _anim_frame == 0 else WIZARD_F1

func _tick_status(delta: float) -> void:
	if _slow_timer > 0.0:
		_slow_timer -= delta
	if _poison_timer > 0.0:
		_poison_timer -= delta
		_poison_tick -= delta
		if _poison_tick <= 0.0:
			_poison_tick = 2.0
			health = max(0, health - 1)
			FloatingText.spawn_str(global_position, "POISON", Color(0.3, 0.9, 0.3), get_tree().current_scene)
			_update_health_bar()
			if health == 0:
				_on_death()

func _tick_dash(delta: float) -> void:
	if _dash_cooldown > 0.0:
		_dash_cooldown -= delta
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_is_invincible = false
			# modulate reset handled by _update_player_visual()
			# Restore physical collision with enemies now that dash is over
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(enemy):
					remove_collision_exception_with(enemy)
	elif Input.is_action_just_pressed("dash") and _dash_cooldown <= 0.0 and not _is_dead:
		_start_dash()

func _update_player_visual() -> void:
	if _dash_timer > 0.0:
		modulate = Color(0.5, 0.8, 1.0, 0.6)
	elif _is_levitating:
		modulate = Color(0.72, 0.88, 1.0, 1.0)
	else:
		modulate = Color(1.0, 1.0, 1.0, 1.0)

func _handle_levitate(delta: float) -> void:
	var cost := LEVITATE_MANA_COST * delta
	if Input.is_action_pressed("levitate") and mana >= cost:
		_is_levitating = true
		mana -= cost
	else:
		_is_levitating = false

func _setup_shield() -> void:
	_shield_area = Area2D.new()
	_shield_area.add_to_group("shield")
	_shield_area.collision_layer = 1
	_shield_area.collision_mask  = 1
	add_child(_shield_area)

	# 90-degree sector polygon pointing right (+X)
	var steps := 12
	var sector: PackedVector2Array = []
	sector.append(Vector2.ZERO)
	for i in steps + 1:
		var a := deg_to_rad(-45.0) + (deg_to_rad(90.0) / float(steps)) * float(i)
		sector.append(Vector2(cos(a), sin(a)) * SHIELD_RADIUS)
	var poly := CollisionPolygon2D.new()
	poly.polygon = sector
	_shield_area.add_child(poly)

	# Arc visual points (curved edge only)
	var arc_pts: PackedVector2Array = []
	for i in steps + 1:
		var a := deg_to_rad(-45.0) + (deg_to_rad(90.0) / float(steps)) * float(i)
		arc_pts.append(Vector2(cos(a), sin(a)) * SHIELD_RADIUS)

	_shield_glow = Line2D.new()
	_shield_glow.width = 10.0
	_shield_glow.default_color = Color(0.2, 0.5, 1.0, 0.28)
	_shield_glow.z_index = 2
	_shield_glow.points = arc_pts
	_shield_glow.visible = false
	add_child(_shield_glow)

	_shield_visual = Line2D.new()
	_shield_visual.width = 3.0
	_shield_visual.default_color = Color(0.4, 0.78, 1.0, 0.92)
	_shield_visual.z_index = 3
	_shield_visual.points = arc_pts
	_shield_visual.visible = false
	add_child(_shield_visual)

	_shield_area.area_entered.connect(_on_shield_absorb)

func _handle_shield(delta: float) -> void:
	var cost := SHIELD_MANA_PER_SEC * delta
	var wants := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and mana >= cost
	if wants:
		_is_shielding = true
		mana -= cost
		var mouse_dir := (get_global_mouse_position() - global_position).normalized()
		var angle := mouse_dir.angle()
		_shield_area.rotation   = angle
		_shield_visual.rotation = angle
		_shield_glow.rotation   = angle
		_shield_area.visible    = true
		_shield_visual.visible  = true
		_shield_glow.visible    = true
	else:
		_is_shielding           = false
		_shield_area.visible    = false
		_shield_visual.visible  = false
		_shield_glow.visible    = false

func _on_shield_absorb(area: Area2D) -> void:
	if not _is_shielding:
		return
	var src: Variant = area.get("source")
	if src == null or str(src) != "enemy":
		return
	var dmg: Variant = area.get("damage")
	var cost := float(dmg if dmg != null else 1) * SHIELD_MANA_PER_DMG
	mana = maxf(0.0, mana - cost)
	FloatingText.spawn_str(global_position, "SHIELD -%dMP" % int(cost),
		Color(0.3, 0.65, 1.0), get_tree().current_scene)
	if is_instance_valid(area):
		area.queue_free()

func _start_dash() -> void:
	# Dash in movement direction; fall back to mouse direction
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):    dir.y -= 1
	if Input.is_action_pressed("move_down"):  dir.y += 1
	if Input.is_action_pressed("move_left"):  dir.x -= 1
	if Input.is_action_pressed("move_right"): dir.x += 1
	if dir == Vector2.ZERO:
		dir = (get_global_mouse_position() - global_position).normalized()
	else:
		dir = dir.normalized()
	_dash_dir       = dir
	_dash_timer     = DASH_DURATION
	_dash_cooldown  = DASH_COOLDOWN
	_is_invincible  = true
	modulate        = Color(0.5, 0.8, 1.0, 0.6)
	# Pass through enemies physically during invincibility
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			add_collision_exception_with(enemy)

func apply_status(effect: String, duration: float) -> void:
	match effect:
		"slow":
			_slow_timer = maxf(_slow_timer, duration)
			FloatingText.spawn_str(global_position, "SLOW", Color(0.4, 0.6, 1.0), get_tree().current_scene)
		"poison":
			if _poison_timer <= 0.0:
				_poison_tick = 2.0   # first tick in 2 s
			_poison_timer = maxf(_poison_timer, duration)
			FloatingText.spawn_str(global_position, "POISON", Color(0.3, 0.9, 0.3), get_tree().current_scene)

func _handle_movement() -> void:
	if _dash_timer > 0.0:
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		return
	var direction := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		direction.y -= 1
	if Input.is_action_pressed("move_down"):
		direction.y += 1
	if Input.is_action_pressed("move_left"):
		direction.x -= 1
	if Input.is_action_pressed("move_right"):
		direction.x += 1
	if direction != Vector2.ZERO:
		direction = direction.normalized()
	var slow_mult := 0.5 if _slow_timer > 0.0 else 1.0
	velocity = direction * (speed + _equip_speed_bonus) * _speed_multiplier * slow_mult
	move_and_slide()

func _handle_shooting(delta: float) -> void:
	_shoot_cooldown -= delta
	if _inventory_ui and _inventory_ui.visible:
		if _beam_line:
			_beam_line.visible = false
		return

	var wand: Item = InventoryManager.equipped.get("wand") as Item

	# Beam wand — separate continuous path
	if wand != null and wand.wand_shoot_type == "beam":
		_handle_beam(delta, wand)
		return

	# Hide beam line if we switched away from beam
	if _beam_line:
		_beam_line.visible = false

	var actual_rate: float
	if wand != null:
		actual_rate = wand.wand_fire_rate
		if "clunky" in wand.wand_flaws:
			actual_rate *= 2.0
	else:
		actual_rate = maxf(0.05, (fire_rate - _equip_fire_rate_bonus) / _fire_rate_multiplier)

	if Input.is_action_pressed("shoot") and _shoot_cooldown <= 0.0:
		var mana_cost: float
		if wand != null:
			mana_cost = wand.wand_mana_cost
			if "mana_guzzle" in wand.wand_flaws:
				mana_cost *= 2.0
		else:
			mana_cost = BASE_SHOT_MANA_COST
		if mana >= mana_cost:
			mana -= mana_cost
			_fire(wand)
			_shoot_cooldown = actual_rate

func _handle_beam(delta: float, wand: Item) -> void:
	if not Input.is_action_pressed("shoot"):
		if _beam_line:
			_beam_line.visible = false
		return

	var drain: float = wand.wand_mana_cost  # per second
	if "mana_guzzle" in wand.wand_flaws:
		drain *= 2.0
	var drain_this_frame := drain * delta
	if mana < drain_this_frame:
		if _beam_line:
			_beam_line.visible = false
		return

	mana -= drain_this_frame

	var mouse_dir := (get_global_mouse_position() - global_position).normalized()
	var space := get_world_2d().direct_space_state
	var params := PhysicsRayQueryParameters2D.create(
		global_position,
		global_position + mouse_dir * 700.0
	)
	params.exclude = [get_rid()]
	var hit := space.intersect_ray(params)

	var end_pos: Vector2 = global_position + mouse_dir * 700.0
	if not hit.is_empty():
		end_pos = hit.get("position", end_pos)
		var collider: Object = hit.get("collider")
		if collider != null and collider.is_in_group("enemy"):
			_shoot_cooldown -= delta
			if _shoot_cooldown <= 0.0:
				_shoot_cooldown = 0.08
				if collider.has_method("take_damage"):
					collider.take_damage(wand.wand_damage)
					GameState.damage_dealt += wand.wand_damage
				if collider.has_method("apply_status"):
					collider.apply_status("burn_hit", 0.0)

	if _beam_line == null:
		_beam_line = Line2D.new()
		_beam_line.width = 4.0
		_beam_line.default_color = Color(0.3, 0.8, 1.0, 0.85)
		add_child(_beam_line)
	_beam_line.visible = true
	_beam_line.clear_points()
	_beam_line.add_point(Vector2.ZERO)
	_beam_line.add_point(to_local(end_pos))

func _fire(wand: Item = null) -> void:
	if projectile_scene == null:
		push_warning("Player: projectile_scene is not set!")
		return

	var base_dir := (get_global_mouse_position() - global_position).normalized()

	if wand != null:
		if "backwards" in wand.wand_flaws:
			base_dir = -base_dir
		if "erratic" in wand.wand_flaws:
			base_dir = base_dir.rotated(randf_range(-0.7, 0.7))

		var proj := projectile_scene.instantiate()
		proj.global_position = global_position
		proj.direction = base_dir
		proj.set("source", "player")
		proj.set("damage", wand.wand_damage)
		proj.set("pierce_remaining", wand.wand_pierce)
		proj.set("ricochet_remaining", wand.wand_ricochet)
		proj.set("chain_remaining", wand.wand_chain)
		proj.set("apply_freeze", wand.wand_shoot_type == "freeze")
		proj.set("apply_burn", wand.wand_shoot_type == "fire")
		proj.set("apply_shock", wand.wand_shoot_type == "shock")
		var proj_speed := wand.wand_proj_speed
		if "slow_shots" in wand.wand_flaws:
			proj_speed *= 0.5
		proj.set("speed", proj_speed)
		var drift := 0.0
		if "drift" in wand.wand_flaws:
			drift = randf_range(60.0, 120.0) * (1.0 if randf() > 0.5 else -1.0)
		proj.set("drift_speed", drift)
		get_tree().current_scene.add_child(proj)
	else:
		# No wand equipped — fire basic free shot from base stats
		var count := 1 + _equip_projectile_count
		for i in count:
			var projectile := projectile_scene.instantiate()
			projectile.global_position = global_position
			if count > 1:
				var spread := deg_to_rad(15.0) * (float(i) - float(count - 1) * 0.5)
				projectile.direction = base_dir.rotated(spread)
			else:
				projectile.direction = base_dir
			get_tree().current_scene.add_child(projectile)

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, max_health)
	var gained := health - prev
	if gained > 0:
		FloatingText.spawn(global_position, gained, true, get_tree().current_scene)
	_update_health_bar()

func apply_buff(duration: float) -> void:
	_speed_multiplier = 2.0
	_fire_rate_multiplier = 2.0
	_buff_timer += duration

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	if _is_invincible:
		return
	if _is_shielding:
		var cost := float(amount) * SHIELD_MANA_PER_DMG
		if mana >= cost:
			mana -= cost
			FloatingText.spawn_str(global_position, "SHIELD -%dMP" % int(cost),
				Color(0.3, 0.65, 1.0), get_tree().current_scene)
			return
		else:
			mana = 0.0  # drain remaining mana, still take the hit
	if _equip_block_chance > 0.0 and randf() < _equip_block_chance:
		FloatingText.spawn_str(global_position, "BLOCK", Color(0.3, 0.8, 1.0), get_tree().current_scene)
		return
	health = max(0, health - amount)
	_update_health_bar()
	if health == 0:
		_on_death()

func save_state() -> void:
	GameState.player_health = health
	GameState.has_saved_state = true

func _update_health_bar() -> void:
	var bar := get_node_or_null("HUD/HealthBarFG")
	if bar == null:
		return
	var ratio := float(health) / float(max_health)
	bar.offset_right = 11.0 + 200.0 * ratio

func _update_xp_bar() -> void:
	if _xp_bar_fg == null:
		return
	var next := GameState.xp_to_next_level()
	if next <= 0:
		return
	var ratio := clampf(float(GameState.xp) / float(next), 0.0, 1.0)
	_xp_bar_fg.size.x = 400.0 * ratio

func _on_level_up() -> void:
	var lbl := Label.new()
	lbl.text = "LEVEL UP!"
	lbl.add_theme_font_size_override("font_size", 32)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = Vector2(700, 380)
	$HUD.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0, -90), 1.5)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.5)
	tw.tween_callback(lbl.queue_free)

func _on_death() -> void:
	_is_dead = true
	var ranks := Leaderboard.submit(GameState.portals_used, GameState.gold, GameState.damage_dealt)
	_build_death_leaderboard(ranks)
	$HUD/DeathMenu.visible = true

func _build_death_leaderboard(ranks: Dictionary) -> void:
	var dm := $HUD/DeathMenu

	# Panel that sits below the existing retry/quit buttons
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.03, 0.08, 0.97)
	panel.position = Vector2(100, 548)
	panel.size = Vector2(1400, 336)
	dm.add_child(panel)

	# Current run stats
	var summary := Label.new()
	summary.text = "Kills: %d    Portals: %d    Gold: %d    Damage: %d" % [
		GameState.kills, GameState.portals_used,
		GameState.gold, GameState.damage_dealt
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.position = Vector2(100, 558)
	summary.size = Vector2(1400, 22)
	summary.add_theme_font_size_override("font_size", 14)
	summary.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	dm.add_child(summary)

	# Thin separator
	var sep := ColorRect.new()
	sep.color = Color(0.35, 0.2, 0.55)
	sep.position = Vector2(130, 585)
	sep.size = Vector2(1340, 2)
	dm.add_child(sep)

	# Leaderboard heading
	var lb_title := Label.new()
	lb_title.text = "- LEADERBOARD -"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.position = Vector2(100, 593)
	lb_title.size = Vector2(1400, 24)
	lb_title.add_theme_font_size_override("font_size", 16)
	lb_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	dm.add_child(lb_title)

	# Three columns: x positions calculated for equal thirds across 1400px panel (100-1500)
	_add_lb_column(dm, "PORTALS USED",      Leaderboard.get_top("portals", 5), Vector2(130,  624), ranks.get("portals", -1))
	_add_lb_column(dm, "GOLD (SINGLE RUN)", Leaderboard.get_top("gold",    5), Vector2(600,  624), ranks.get("gold",    -1))
	_add_lb_column(dm, "DAMAGE DEALT",      Leaderboard.get_top("damage",  5), Vector2(1070, 624), ranks.get("damage",  -1))

func _add_lb_column(parent: Node, title: String, entries: Array, pos: Vector2, highlight_rank: int = -1) -> void:
	var col_w := 400.0

	var header := Label.new()
	header.text = title
	header.position = pos
	header.size = Vector2(col_w, 20)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.55, 0.8, 1.0))
	parent.add_child(header)

	var shown := 0
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if entry.get("value", 0) == 0:
			continue
		var is_this_run := (i + 1 == highlight_rank)
		var row := Label.new()
		row.text = "%d.  %d" % [i + 1, entry.get("value", 0)]
		row.position = pos + Vector2(0, 24 + shown * 22)
		row.size = Vector2(col_w, 20)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_theme_font_size_override("font_size", 13)
		row.add_theme_color_override("font_color",
			Color(1.0, 0.85, 0.2) if is_this_run else Color(0.82, 0.82, 0.82))
		parent.add_child(row)
		shown += 1

func update_equip_stats() -> void:
	_equip_speed_bonus      = InventoryManager.get_stat("speed")
	_equip_fire_rate_bonus  = InventoryManager.get_stat("fire_rate_reduction")
	_equip_block_chance     = InventoryManager.get_stat("block_chance")
	_equip_projectile_count = int(InventoryManager.get_stat("projectile_count"))
	_equip_wisdom_bonus     = InventoryManager.get_stat("wisdom")
	var new_bonus := int(InventoryManager.get_stat("max_health"))
	if new_bonus != _equip_health_bonus:
		_equip_health_bonus = new_bonus
		health = mini(health, max_health + _equip_health_bonus)
		_update_health_bar()

func _on_retry() -> void:
	InventoryManager.reset()
	get_tree().reload_current_scene()

func _on_quit() -> void:
	get_tree().paused = false
	get_tree().quit()

func _on_title() -> void:
	get_tree().paused = false
	InventoryManager.reset()
	get_tree().change_scene_to_file("res://scenes/TitleScreen.tscn")

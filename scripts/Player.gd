extends CharacterBody2D

const INVENTORY_UI_SCENE := preload("res://scenes/InventoryUI.tscn")

@export var speed: float = 300.0
@export var fire_rate: float = 0.15
@export var max_health: int = 20
@export var projectile_scene: PackedScene

var health: int = 20
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
var _equip_projectile_count: int = 0
var _equip_wisdom_bonus: float = 0.0
var _set_def_bonus: int = 0

var _syn_pyromaniac: bool    = false  # fire patches bigger/longer
var _syn_glacial: bool       = false  # freeze bolts bonus vs chilled
var _syn_arc_conductor: bool = false  # shock bolts pierce once
var _syn_void_lens: bool     = false  # nova fires 16 shards
var _syn_assassin_mark: bool = false  # homing deals double damage

# Mana
var mana: float = 10.0
var max_mana: float = 100.0
const BASE_WISDOM: float = 25.0   # mana/sec base regen
var _mana_bar_fg: ColorRect = null
var _mana_label: Label = null

# Beam wand
var _beam_line: Line2D = null
var _beam_hum_t: float = 0.0

var _inventory_ui: Node = null

# Status effects
var _slow_timer:   float = 0.0
var _poison_timer: float = 0.0
var _poison_tick:  float = 0.0

# Disorient (spinning view + remapped controls)
var _disorient_timer: float = 0.0
var _disorient_angle: float = 0.0
const DISORIENT_SPIN_RATE := 2.1   # rad/sec while active
const DISORIENT_RECOVERY  := 4.5   # rad/sec when fading back to 0

# Dash
var _dash_cooldown:    float = 0.0
var _dash_timer:       float = 0.0   # > 0 while actively dashing
var _dash_dir:         Vector2 = Vector2.ZERO
var _is_invincible:    bool = false
const DASH_SPEED           := 900.0
const DASH_DURATION        := 0.18
var _dash_base_cooldown: float = 1.5
const BASE_SHOT_MANA_COST  := 3.0   # mana cost when firing without a wand equipped

# Stamina
var stamina:           float = 100.0
var max_stamina:       float = 100.0
var _stam_bar_fg:      ColorRect = null
var _perk_stam_bonus:  float = 0.0
var _stam_regen_bonus: float = 0.0
const STAMINA_REGEN      := 18.0
const DASH_STAMINA_COST  := 35.0

# Nova spell
var _spell_cooldown: float = 0.0
const SPELL_COOLDOWN   := 8.0
const NOVA_MANA_COST   := 22.0
const SPELL_ORB_SCRIPT = preload("res://scripts/SpellOrb.gd")

# Screen shake / hit-stop
var _hit_stop_end_ms: int = 0
var _shake_tween: Tween   = null

# Damage feedback
var _damage_flash: ColorRect = null
var _damage_flash_tween: Tween = null

# Test-mode wand cycling (KEY_1 / KEY_2)
var _test_wand_index: int = -1

# Autoplay (KEY_0): drives movement, aim, fire, perk picks
var _autoplay: bool           = false
var _autoplay_enemy: Node2D   = null   # current visible enemy to shoot at
var _autoplay_move_to: Node2D = null   # current movement objective (enemy/loot/portal)
var _autoplay_target_t: float = 0.0
var _autoplay_perk_t: float   = 0.5
var _autoplay_equip_t: float  = 0.0
var _autoplay_loot_t: float   = 0.0
# Stuck detection / escape — when the player can't make progress for a while,
# overrides the kite logic with a random escape vector to break free of corners.
var _autoplay_last_pos: Vector2 = Vector2.ZERO
var _autoplay_stuck_t: float    = 0.0
var _autoplay_escape_t: float   = 0.0
var _autoplay_escape_dir: Vector2 = Vector2.ZERO

# A* pathfinding (rebuilt per-floor). Follows the World tilemap to navigate
# corridors that local wall-avoidance can't escape on its own.
var _astar: AStarGrid2D = null
var _astar_world_id: int = 0
var _autoplay_path: PackedVector2Array = PackedVector2Array()
var _autoplay_path_idx: int = 0
var _autoplay_repath_t: float = 0.0

# Auto-action timers (rate-limit nova/shield/dash/potion/equip/cleanup checks)
var _autoplay_nova_t: float    = 0.0
var _autoplay_dash_t: float    = 0.0
var _autoplay_potion_t: float  = 0.0
var _autoplay_clean_t: float   = 4.0
# How long we've been actively pursuing the current loot bag — if we can't
# reach it in N seconds, blacklist and move on so we don't loiter forever
var _autoplay_loot_target_t: float = 0.0
# Sprint mode: ignore loot, B-line through floors
var _autoplay_sprint: bool     = false
# HUD/debug overlays
var _autoplay_hud_label: Label = null
var _autoplay_path_line: Line2D = null
var _autoplay_target_marker: Node2D = null
# Bags the bot has touched but couldn't fully loot (inventory full) — skip them
# so it doesn't oscillate between a couple of unreachable items.
var _autoplay_skipped_bags: Dictionary = {}
# Enemies the bot has been firing at without dealing damage (wall-clipped
# foes, etc). They're skipped from shoot targeting so the bot doesn't lock up.
var _autoplay_skipped_enemies: Dictionary = {}
var _autoplay_enemy_last_hp: int = -1
var _autoplay_enemy_dmg_t: float = 0.0
# World positions the bot has decided to route around (e.g. teleporter pads it
# has already triggered once). Marked solid in the A* grid on rebuild.
var _autoplay_avoid_positions: Array = []

# Knockback
var _knockback_vel:   Vector2 = Vector2.ZERO
var _knockback_timer: float   = 0.0
const KNOCKBACK_DURATION      := 0.35

# Perk system
const PERKS := [
	{"id": "hp_up",        "name": "+3 Max HP",        "desc": "Permanently gain 3 max health"},
	{"id": "mana_up",      "name": "+25 Max Mana",      "desc": "Expand your mana pool by 25"},
	{"id": "speed_up",     "name": "+40 Move Speed",    "desc": "Move permanently faster"},
	{"id": "fire_rate_up", "name": "Rapid Fire",        "desc": "Reduce shot delay by 0.04s"},
	{"id": "dash_up",      "name": "+20 Max Stamina",   "desc": "Dash stamina pool +20, more dashes"},
	{"id": "wisdom_up",    "name": "+15% Mana Regen",   "desc": "Regenerate mana 15% faster"},
	{"id": "proj_up",      "name": "Extra Shot",        "desc": "+1 base projectile (no wand)"},
	{"id": "heal_now",     "name": "Vitality",          "desc": "Fully restore HP right now"},
]
var _perk_queue: int            = 0
var _perk_screen: CanvasLayer   = null
var _is_perk_selecting: bool    = false
var _perk_proj_bonus: int       = 0
var _perk_wisdom_bonus_p: float = 0.0
var _perk_dash_reduction: float = 0.0
var _perk_mana_bonus: float     = 0.0

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
const WIZARD_F0 := "   ^\n__/_\\__\n (*-*)\n /)V(\\|\n /___\\|"
const WIZARD_F1 := "   ^\n__/_\\__\n (*3*)\n /)V(\\|\n /___\\|"
var _ascii_label: Label   = null
var _anim_timer: float    = 0.0
var _anim_frame: int      = 0
var _level_label: Label = null
var _xp_bar_fg: ColorRect = null
var _stats_label: Label = null
var _hp_regen_acc: float = 0.0

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
	_setup_damage_flash()
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

	if not InputMap.has_action("nova_spell"):
		InputMap.add_action("nova_spell")
		var ev_nova := InputEventKey.new()
		ev_nova.physical_keycode = KEY_Q
		InputMap.action_add_event("nova_spell", ev_nova)

	_setup_pause_menu()
	_setup_shield()

	_ascii_label = $AsciiChar
	_ascii_label.text = WIZARD_F0
	var _mono := SystemFont.new()
	_mono.font_names = PackedStringArray(["Consolas", "Courier New", "Lucida Console"])
	_ascii_label.add_theme_font_override("font", _mono)
	_ascii_label.add_theme_constant_override("line_separation", -6)
	_ascii_label.add_theme_constant_override("outline_size", 3)
	_ascii_label.add_theme_color_override("font_outline_color", Color(0.1, 0.65, 1.0, 0.85))
	z_index = 10
	var _aura := ColorRect.new()
	_aura.size     = Vector2(32.0, 38.0)
	_aura.color    = Color(0.1, 0.5, 1.0, 0.18)
	_aura.position = Vector2(-16.0, -19.0)
	_aura.z_index  = -1
	add_child(_aura)

	# Inventory UI
	var inv_ui := INVENTORY_UI_SCENE.instantiate()
	add_child(inv_ui)
	_inventory_ui = inv_ui
	InventoryManager.register_player(self)
	# Reapply all equipment bonuses — required after portal reloads
	update_equip_stats()
	# Restore autoplay across portal transitions. Keep the carried-over health
	# (with the +10 portal heal already applied) — don't reset to full.
	if GameState.autoplay_active:
		_autoplay = true
		_autoplay_sprint = GameState.autoplay_sprint
		_autoplay_last_pos = global_position
		GameState.run_stat_bonuses["VIT"] = 90
		update_equip_stats()
		health = mini(health, _max_hp())
		_update_health_bar()
		# Clear any leftover hit-stop slow-motion from prior floor
		Engine.time_scale = 1.0
		_hit_stop_end_ms = 0

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

	# Stats panel — top-right, two columns of five stats. Sits BELOW the
	# minimap (which occupies roughly y=8..140 on the right side).
	var stats_bg := ColorRect.new()
	stats_bg.name = "StatsBG"
	stats_bg.color = Color(0.05, 0.04, 0.10, 0.55)
	stats_bg.position = Vector2(1424, 156)
	stats_bg.size = Vector2(180, 110)
	hud.add_child(stats_bg)
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	_stats_label.position = Vector2(1430, 160)
	_stats_label.size = Vector2(170, 110)
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_stats_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_stats_label.add_theme_constant_override("outline_size", 2)
	_stats_label.add_theme_constant_override("line_separation", 1)
	hud.add_child(_stats_label)

	# Autoplay HUD strip (objective + sprint indicator) — sits below stats
	_autoplay_hud_label = Label.new()
	_autoplay_hud_label.name = "AutoplayLabel"
	_autoplay_hud_label.position = Vector2(1424, 274)
	_autoplay_hud_label.size = Vector2(180, 38)
	_autoplay_hud_label.add_theme_font_size_override("font_size", 13)
	_autoplay_hud_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
	_autoplay_hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_autoplay_hud_label.add_theme_constant_override("outline_size", 2)
	_autoplay_hud_label.visible = false
	hud.add_child(_autoplay_hud_label)

	# Path-debug Line2D in world space (child of scene so coords stay world-aligned)
	_autoplay_path_line = Line2D.new()
	_autoplay_path_line.width = 2.0
	_autoplay_path_line.default_color = Color(0.4, 0.9, 1.0, 0.45)
	_autoplay_path_line.z_index = -2
	_autoplay_path_line.visible = false
	get_tree().current_scene.add_child(_autoplay_path_line)

	# Target marker — small ring drawn around the bot's current shoot target
	_autoplay_target_marker = Node2D.new()
	var marker_ring := Line2D.new()
	marker_ring.width = 1.5
	marker_ring.default_color = Color(1.0, 0.4, 0.3, 0.8)
	var segs := 12
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		marker_ring.add_point(Vector2(cos(ang), sin(ang)) * 18.0)
	_autoplay_target_marker.add_child(marker_ring)
	_autoplay_target_marker.visible = false
	get_tree().current_scene.add_child(_autoplay_target_marker)

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
	_mana_label.position = Vector2(10, 25)
	_mana_label.size = Vector2(200, 12)
	_mana_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mana_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_mana_label.z_index = 2
	_mana_label.add_theme_font_size_override("font_size", 9)
	_mana_label.add_theme_color_override("font_color", Color(0.88, 0.93, 1.0))
	hud.add_child(_mana_label)

	# Stamina bar background
	var stam_bg := ColorRect.new()
	stam_bg.name = "StamBarBG"
	stam_bg.color = Color(0.05, 0.2, 0.05)
	stam_bg.position = Vector2(10, 49)
	stam_bg.size = Vector2(202, 8)
	hud.add_child(stam_bg)

	_stam_bar_fg = ColorRect.new()
	_stam_bar_fg.name = "StamBarFG"
	_stam_bar_fg.color = Color(0.3, 0.9, 0.25)
	_stam_bar_fg.position = Vector2(11, 50)
	_stam_bar_fg.size = Vector2(200.0, 6.0)
	hud.add_child(_stam_bar_fg)

	# Dash label
	var dash_lbl := Label.new()
	dash_lbl.name = "DashLabel"
	dash_lbl.text = "DASH [SHIFT]"
	dash_lbl.position = Vector2(10, 62)
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
	lev_lbl.position = Vector2(10, 76)
	lev_lbl.size = Vector2(200, 16)
	lev_lbl.add_theme_font_size_override("font_size", 11)
	lev_lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	hud.add_child(lev_lbl)

	var shd_lbl := Label.new()
	shd_lbl.name = "ShieldLabel"
	shd_lbl.text = "SHIELD [RMB]"
	shd_lbl.position = Vector2(10, 90)
	shd_lbl.size = Vector2(200, 16)
	shd_lbl.add_theme_font_size_override("font_size", 11)
	shd_lbl.add_theme_color_override("font_color", Color(0.35, 0.6, 1.0))
	hud.add_child(shd_lbl)

	var nova_lbl := Label.new()
	nova_lbl.name = "NovaLabel"
	nova_lbl.text = "NOVA [Q]"
	nova_lbl.position = Vector2(10, 104)
	nova_lbl.size = Vector2(200, 16)
	nova_lbl.add_theme_font_size_override("font_size", 11)
	nova_lbl.add_theme_color_override("font_color", Color(0.75, 0.3, 1.0))
	hud.add_child(nova_lbl)

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
	border.position = Vector2(580, 230)
	border.size     = Vector2(440, 556)
	_pause_menu.add_child(border)

	var inner := ColorRect.new()
	inner.color    = Color(0.04, 0.02, 0.09, 0.97)
	inner.position = Vector2(583, 233)
	inner.size     = Vector2(434, 550)
	_pause_menu.add_child(inner)

	# Stat reference panel — sits to the right of the main menu, always visible while paused
	var stats_border := ColorRect.new()
	stats_border.color    = Color(0.22, 0.28, 0.35, 0.9)
	stats_border.position = Vector2(1030, 230)
	stats_border.size     = Vector2(280, 380)
	_pause_menu.add_child(stats_border)
	var stats_inner := ColorRect.new()
	stats_inner.color    = Color(0.04, 0.05, 0.09, 0.97)
	stats_inner.position = Vector2(1033, 233)
	stats_inner.size     = Vector2(274, 374)
	_pause_menu.add_child(stats_inner)
	var stats_title := Label.new()
	stats_title.text = "— STAT REFERENCE —"
	stats_title.position = Vector2(1033, 244)
	stats_title.size     = Vector2(274, 24)
	stats_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_title.add_theme_font_size_override("font_size", 14)
	stats_title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_pause_menu.add_child(stats_title)
	var stats_help := Label.new()
	stats_help.text = "STR  +1 damage per point\nDEX  faster firing per point\nAGI  +4 move speed per point\nVIT  +1 max HP per point\nEND  +4 max stamina per point\nINT  scales elemental effects\nWIS  +1.5 mana/sec per point\nSPR  +0.05 HP/sec per point\nDEF  +1% block per point\nLCK  +0.5% crit per point"
	stats_help.position = Vector2(1048, 282)
	stats_help.size     = Vector2(260, 320)
	stats_help.add_theme_font_size_override("font_size", 13)
	stats_help.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	stats_help.add_theme_constant_override("line_separation", 8)
	_pause_menu.add_child(stats_help)

	var title := Label.new()
	title.text     = "— PAUSED —"
	title.position = Vector2(586, 248)
	title.size     = Vector2(428, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_pause_menu.add_child(title)

	_pause_btn("RESUME",       Vector2(640, 308), Color(0.4, 0.9, 0.5),  _resume_game)
	_pause_btn("SAVE RUN",     Vector2(640, 368), Color(0.5, 0.75, 1.0), _save_run)
	_pause_btn("TITLE SCREEN", Vector2(640, 428), Color(0.7, 0.55, 1.0), _on_title)
	_pause_btn("QUIT",         Vector2(640, 488), Color(0.55, 0.55, 0.6),_on_quit)
	_add_crt_toggle(Vector2(640, 548))
	_add_volume_slider(612)
	_add_difficulty_slider(672)

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

func _add_crt_toggle(pos: Vector2) -> void:
	var col_on  := Color(0.55, 1.0, 0.55)
	var col_off := Color(0.45, 0.45, 0.55)
	var lbl := Label.new()
	lbl.text = "[ CRT: %s ]" % ("ON" if GameState.crt_enabled else "OFF")
	lbl.position = pos
	lbl.size = Vector2(320, 32)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", col_on if GameState.crt_enabled else col_off)
	_pause_menu.add_child(lbl)
	var btn := Button.new()
	btn.flat = true
	btn.position = pos - Vector2(4, 2)
	btn.size = Vector2(328, 36)
	btn.mouse_entered.connect(func() -> void:
		lbl.add_theme_color_override("font_color", lbl.get_theme_color("font_color").lightened(0.3)))
	btn.mouse_exited.connect(func() -> void:
		lbl.add_theme_color_override("font_color", col_on if GameState.crt_enabled else col_off))
	btn.pressed.connect(func() -> void:
		GameState.crt_enabled = not GameState.crt_enabled
		GameState.save_settings()
		lbl.text = "[ CRT: %s ]" % ("ON" if GameState.crt_enabled else "OFF")
		lbl.add_theme_color_override("font_color", col_on if GameState.crt_enabled else col_off)
		var scene := get_tree().current_scene
		if scene.has_method("_apply_crt_state"):
			scene._apply_crt_state())
	_pause_menu.add_child(btn)

func _add_volume_slider(y: float) -> void:
	var col := Color(0.6, 0.85, 1.0)
	var lbl := Label.new()
	lbl.position = Vector2(640, y)
	lbl.size     = Vector2(320, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", col)
	lbl.text = "VOLUME: %d%%" % int(GameState.master_volume * 100.0)
	_pause_menu.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value    = 0.0
	slider.max_value    = 100.0
	slider.step         = 1.0
	slider.value        = GameState.master_volume * 100.0
	slider.position     = Vector2(608, y + 26)
	slider.size         = Vector2(384, 24)
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.add_child(slider)
	slider.value_changed.connect(func(v: float) -> void:
		GameState.master_volume = v / 100.0
		GameState._apply_volume()
		GameState.save_settings()
		lbl.text = "VOLUME: %d%%" % int(v))

func _add_difficulty_slider(y: float) -> void:
	var col := Color(1.0, 0.72, 0.35)
	var lbl := Label.new()
	lbl.position = Vector2(640, y)
	lbl.size     = Vector2(320, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", col)
	var cur_diff := GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	lbl.text = "DIFFICULTY: %.1fx" % cur_diff
	_pause_menu.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value    = 0.5
	slider.max_value    = 20.0 if GameState.test_mode else 5.0
	slider.step         = 0.1
	slider.value        = cur_diff
	slider.position     = Vector2(608, y + 26)
	slider.size         = Vector2(384, 24)
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	_pause_menu.add_child(slider)
	slider.value_changed.connect(func(v: float) -> void:
		if GameState.test_mode:
			GameState.test_difficulty = v
		else:
			GameState.difficulty = v
		lbl.text = "DIFFICULTY: %.1fx" % v)

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
			s += candidate.stat_bonuses.get("DEF",                 0.0) * 0.6
			s += candidate.stat_bonuses.get("projectile_count",    0.0) * 25.0
			s += candidate.stat_bonuses.get("wisdom",              0.0) * 2.5
			if s > best_score:
				best_score = s
				best = candidate
		if best != null:
			InventoryManager.equipped[slot] = best

	# Always give a perfected beam wand with best gear
	var beam := ItemDB.generate_wand(Item.RARITY_LEGENDARY)
	beam.wand_shoot_type = "beam"
	beam.wand_damage     = 20
	beam.wand_mana_cost  = 5.0
	beam.wand_fire_rate  = 0.06
	beam.wand_flaws.clear()
	beam.display_name    = "Annihilation Ray"
	beam.color           = Color(0.3, 1.0, 0.8)
	InventoryManager.equipped["wand"] = beam

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
		"beam":
			wand.wand_damage     = 15
			wand.wand_mana_cost  = 6.0
		"freeze", "fire":
			wand.wand_status_stacks = 3
	InventoryManager.inventory_changed.emit()
	FloatingText.spawn_str(global_position, "WAND PERFECTED!", Color(0.3, 1.0, 0.8), get_tree().current_scene)

func _cycle_test_wand(dir: int) -> void:
	var types := ["regular", "pierce", "ricochet", "freeze", "fire", "shock", "beam", "shotgun", "homing", "nova", "melee"]
	_test_wand_index = posmod(_test_wand_index + dir, types.size())
	var t: String = types[_test_wand_index]
	var w := ItemDB.generate_wand(Item.RARITY_LEGENDARY)
	w.wand_shoot_type = t
	w.wand_flaws.clear()
	w.wand_damage     = 8
	w.wand_fire_rate  = 0.08
	w.wand_mana_cost  = 3.0
	w.wand_proj_speed = 900.0
	match t:
		"pierce":          w.wand_pierce         = 6
		"ricochet":        w.wand_ricochet        = 6
		"beam":
			w.wand_damage    = 15
			w.wand_mana_cost = 6.0
		"freeze", "fire":  w.wand_status_stacks   = 3
	w.display_name = t.capitalize() + " [%d/%d]" % [_test_wand_index + 1, types.size()]
	InventoryManager.equipped["wand"] = w
	InventoryManager.inventory_changed.emit()
	update_equip_stats()
	FloatingText.spawn_str(global_position, w.display_name, Color(0.3, 1.0, 0.8), get_tree().current_scene)

# ── Mana bar ──────────────────────────────────────────────────────────────────

func _update_mana_bar() -> void:
	if _mana_bar_fg == null:
		return
	var ratio := clampf(mana / max_mana, 0.0, 1.0)
	_mana_bar_fg.size.x = 200.0 * ratio
	if _mana_label:
		_mana_label.text = "%d / %d MP" % [int(mana), int(max_mana)]

func _update_stam_bar() -> void:
	if _stam_bar_fg == null:
		return
	var ratio := clampf(stamina / max_stamina, 0.0, 1.0)
	_stam_bar_fg.size.x = 200.0 * ratio

func _cast_nova_spell() -> void:
	if mana < NOVA_MANA_COST:
		FloatingText.spawn_str(global_position, "Need %dMP" % int(NOVA_MANA_COST),
			Color(0.8, 0.3, 0.8), get_tree().current_scene)
		return
	if _spell_cooldown > 0.0:
		return
	mana -= NOVA_MANA_COST
	_spell_cooldown = SPELL_COOLDOWN
	var orb := Node2D.new()
	orb.set_script(SPELL_ORB_SCRIPT)
	orb.global_position = global_position
	orb.set("target_pos", _get_aim_pos())
	orb.set("proj_scene", projectile_scene)
	get_tree().current_scene.add_child(orb)

func _setup_damage_flash() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 20   # above HUD, below pause menu (layer 25)
	add_child(layer)
	_damage_flash = ColorRect.new()
	_damage_flash.color = Color(0.85, 0.0, 0.0, 0.0)
	_damage_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_damage_flash)

func _trigger_damage_flash(amount: int) -> void:
	if _damage_flash == null: return
	if is_instance_valid(_damage_flash_tween) and _damage_flash_tween.is_running():
		_damage_flash_tween.kill()
	var alpha := clampf(0.10 + float(amount) * 0.06, 0.18, 0.55)
	_damage_flash.color.a = alpha
	_damage_flash_tween = create_tween()
	_damage_flash_tween.tween_property(_damage_flash, "color:a", 0.0, 0.32)

func camera_shake(intensity: float, duration: float) -> void:
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if is_instance_valid(_shake_tween) and _shake_tween.is_running():
		if cam.offset.length() > intensity:
			return
		_shake_tween.kill()
	_shake_tween = create_tween()
	var peak := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
	_shake_tween.tween_property(cam, "offset", peak, duration * 0.25)
	_shake_tween.tween_property(cam, "offset", Vector2.ZERO, duration * 0.75)

func start_hit_stop(duration_ms: int) -> void:
	# During autoplay, the bot kills enemies so fast that stacking hit-stops
	# would put the entire game in permanent slow-motion. Skip entirely.
	if _autoplay:
		return
	# Don't extend an in-progress hit-stop — single duration only, otherwise
	# rapid kills chain hit-stops indefinitely and lock the world at 0.08x.
	var now := Time.get_ticks_msec()
	if _hit_stop_end_ms > now:
		return
	Engine.time_scale = 0.08
	_hit_stop_end_ms = now + duration_ms

func _process(_delta: float) -> void:
	# Auto-pick a perk when in autoplay (perk screen pauses the tree, so this
	# runs while _is_paused/perk_selecting is set — _process keeps ticking).
	if _autoplay and _is_perk_selecting:
		_autoplay_perk_t -= _delta
		if _autoplay_perk_t <= 0.0:
			_autoplay_perk_t = 0.5
			_apply_perk(PERKS[randi() % PERKS.size()])
			return
	if _is_paused:
		return
	if _hit_stop_end_ms > 0 and Time.get_ticks_msec() >= _hit_stop_end_ms:
		Engine.time_scale = 1.0
		_hit_stop_end_ms = 0
	$HUD/KillsLabel.text = "Kills: " + str(GameState.kills)
	if _gold_label:
		_gold_label.text = "G: " + str(GameState.gold)
	if _level_label:
		_level_label.text = "LVL " + str(GameState.level)
	if _stats_label:
		_stats_label.text = "STR %d  INT %d\nDEX %d  WIS %d\nAGI %d  SPR %d\nVIT %d  DEF %d\nEND %d  LCK %d" % [
			GameState.get_stat("STR"), GameState.get_stat("INT"),
			GameState.get_stat("DEX"), GameState.get_stat("WIS"),
			GameState.get_stat("AGI"), GameState.get_stat("SPR"),
			GameState.get_stat("VIT"), GameState.get_stat("DEF"),
			GameState.get_stat("END"), GameState.get_stat("LCK"),
		]
	_update_xp_bar()
	_update_mana_bar()
	var dash_lbl := $HUD.get_node_or_null("DashLabel")
	if dash_lbl:
		if _dash_timer > 0.0:
			dash_lbl.text = "DASHING"
			dash_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 1.0))
		elif stamina < DASH_STAMINA_COST:
			dash_lbl.text = "DASH (LOW STAM)"
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
	var nova_lbl := $HUD.get_node_or_null("NovaLabel")
	if nova_lbl:
		if _spell_cooldown > 0.0:
			nova_lbl.text = "NOVA [Q] %.1fs" % _spell_cooldown
			nova_lbl.add_theme_color_override("font_color", Color(0.4, 0.3, 0.5))
		else:
			nova_lbl.text = "NOVA [Q]"
			nova_lbl.add_theme_color_override("font_color", Color(0.75, 0.3, 1.0))
	_update_stam_bar()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _is_perk_selecting:
		get_viewport().set_input_as_handled()
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
		KEY_1:
			if not _is_dead and not _is_paused and GameState.test_mode:
				_cycle_test_wand(-1)
				get_viewport().set_input_as_handled()
		KEY_2:
			if not _is_dead and not _is_paused and GameState.test_mode:
				_cycle_test_wand(1)
				get_viewport().set_input_as_handled()
		KEY_0:
			if not _is_dead:
				_autoplay = not _autoplay
				GameState.autoplay_active = _autoplay
				_autoplay_enemy = null
				_autoplay_move_to = null
				_autoplay_last_pos = global_position
				_autoplay_stuck_t = 0.0
				_autoplay_escape_t = 0.0
				_autoplay_path = PackedVector2Array()
				_autoplay_path_idx = 0
				_autoplay_repath_t = 0.0
				_autoplay_skipped_bags.clear()
				_autoplay_skipped_enemies.clear()
				_autoplay_avoid_positions.clear()
				_autoplay_enemy_last_hp = -1
				_autoplay_enemy_dmg_t = 0.0
				_astar = null   # rebuild on demand for current floor
				if _autoplay:
					# +90 VIT (effective stat = 100) → +90 max HP, beefs the
					# bot without permanently inflating max_health.
					GameState.run_stat_bonuses["VIT"] = 90
					update_equip_stats()
					heal_to_full()
					# Clear any leftover hit-stop slow-motion
					Engine.time_scale = 1.0
					_hit_stop_end_ms = 0
				else:
					GameState.run_stat_bonuses.erase("VIT")
					update_equip_stats()
					health = mini(health, _max_hp())
					_update_health_bar()
					_autoplay_sprint = false
					GameState.autoplay_sprint = false
				FloatingText.spawn_str(global_position,
					"AUTOPLAY: " + ("ON" if _autoplay else "OFF"),
					Color(1.0, 0.95, 0.3), get_tree().current_scene)
				get_viewport().set_input_as_handled()
		KEY_MINUS:
			# Sprint mode — autoplay ignores loot, B-lines through floors
			if _autoplay:
				_autoplay_sprint = not _autoplay_sprint
				GameState.autoplay_sprint = _autoplay_sprint
				FloatingText.spawn_str(global_position,
					"SPRINT: " + ("ON" if _autoplay_sprint else "OFF"),
					Color(0.6, 1.0, 0.4), get_tree().current_scene)
				get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if _is_dead or _is_paused or _is_perk_selecting:
		return
	if _buff_timer > 0.0:
		_buff_timer -= delta
		if _buff_timer <= 0.0:
			_speed_multiplier = 1.0
			_fire_rate_multiplier = 1.0
	# Mana regen
	var wisdom := BASE_WISDOM + _equip_wisdom_bonus + float(GameState.get_stat_bonus("WIS")) * 1.5
	var mana_mult := 2.0 if GameState.floor_modifier == "arcane" else 1.0
	mana = minf(mana + wisdom * delta * mana_mult, max_mana)
	# Stamina regen
	stamina = minf(stamina + (STAMINA_REGEN + _stam_regen_bonus) * delta, max_stamina)
	# HP regen via SPR (slow trickle, scales with stat bonus)
	var spr_bonus := GameState.get_stat_bonus("SPR")
	if spr_bonus > 0 and health > 0 and health < _max_hp():
		_hp_regen_acc += float(spr_bonus) * 0.05 * delta
		if _hp_regen_acc >= 1.0:
			var heal_amt := int(_hp_regen_acc)
			_hp_regen_acc -= float(heal_amt)
			health = mini(_max_hp(), health + heal_amt)
			_update_health_bar()
	# Spell cooldown
	if _spell_cooldown > 0.0:
		_spell_cooldown -= delta
	if Input.is_action_just_pressed("nova_spell") and not _is_dead:
		_cast_nova_spell()
	if _autoplay:
		_autoplay_tick(delta)
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
	# Disorient: while timer is active, accumulate spin; otherwise unwind to 0
	if _disorient_timer > 0.0:
		_disorient_timer -= delta
		_disorient_angle = wrapf(_disorient_angle + DISORIENT_SPIN_RATE * delta, -PI, PI)
	elif _disorient_angle != 0.0:
		_disorient_angle = move_toward(_disorient_angle, 0.0, DISORIENT_RECOVERY * delta)
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam:
		cam.rotation = _disorient_angle
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
	if _dash_timer > 0.0:
		_dash_timer -= delta
		if _dash_timer <= 0.0:
			_is_invincible = false
			# modulate reset handled by _update_player_visual()
			# Restore physical collision with enemies now that dash is over
			for enemy in get_tree().get_nodes_in_group("enemy"):
				if is_instance_valid(enemy):
					remove_collision_exception_with(enemy)
	elif Input.is_action_just_pressed("dash") and stamina >= DASH_STAMINA_COST and not _is_dead:
		_start_dash()
	elif _autoplay and _autoplay_dash_t <= 0.0 and _autoplay_wants_dash():
		_autoplay_dash_t = 1.5
		_start_dash()
	if _autoplay_dash_t > 0.0:
		_autoplay_dash_t -= delta

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
	var bot_wants_shield := _autoplay and _autoplay_wants_shield()
	var wants := (Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) or bot_wants_shield) and mana >= cost
	if wants:
		_is_shielding = true
		mana -= cost
		var aim_pos: Vector2
		if bot_wants_shield:
			aim_pos = _autoplay_shield_aim_pos()
		else:
			aim_pos = get_global_mouse_position()
		var mouse_dir := (aim_pos - global_position).normalized()
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
	_dash_dir      = dir
	_dash_timer    = DASH_DURATION
	stamina       -= DASH_STAMINA_COST
	_is_invincible = true
	modulate        = Color(0.5, 0.8, 1.0, 0.6)
	_spawn_dash_afterimages()
	# Pass through enemies physically during invincibility
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(enemy):
			add_collision_exception_with(enemy)

func _spawn_dash_afterimages() -> void:
	var scene_root := get_tree().current_scene
	for i in 3:
		var ghost := ColorRect.new()
		ghost.size = Vector2(18.0, 30.0)
		ghost.color = Color(0.45, 0.78, 1.0, 0.38 - float(i) * 0.08)
		ghost.position = global_position - Vector2(9.0, 16.0) - _dash_dir * float(i + 1) * 7.0
		ghost.z_index = -1
		scene_root.add_child(ghost)
		var tw := ghost.create_tween()
		tw.tween_property(ghost, "modulate:a", 0.0, 0.18 + float(i) * 0.04)
		tw.tween_callback(ghost.queue_free)

func apply_knockback(force: Vector2) -> void:
	if _is_invincible or _is_dead:
		return
	_knockback_vel   = force
	_knockback_timer = KNOCKBACK_DURATION

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
		"disorient":
			_disorient_timer = maxf(_disorient_timer, duration)
			FloatingText.spawn_str(global_position, "DISORIENTED", Color(0.85, 0.5, 1.0), get_tree().current_scene)

func _get_aim_pos() -> Vector2:
	if _autoplay and is_instance_valid(_autoplay_enemy):
		var enemy_pos: Vector2 = (_autoplay_enemy as Node2D).global_position
		# Lead the target — predict where they'll be when the shot arrives
		var enemy_vel := Vector2.ZERO
		if "velocity" in _autoplay_enemy:
			enemy_vel = _autoplay_enemy.velocity
		var proj_speed: float = 600.0
		var w: Item = InventoryManager.equipped.get("wand") as Item
		if w != null and w.wand_proj_speed > 0.0:
			proj_speed = w.wand_proj_speed
		var dist := global_position.distance_to(enemy_pos)
		var flight_time: float = dist / max(proj_speed, 100.0)
		# Cap lookahead so very fast/distant enemies don't make us aim at the wall
		flight_time = clampf(flight_time, 0.0, 0.6)
		return enemy_pos + enemy_vel * flight_time
	return get_global_mouse_position()

func _wants_shoot() -> bool:
	if _autoplay:
		# If cached target is dead or now blocked, lazily pick a fresh visible
		# one this frame so the bot keeps firing whenever ANY target is
		# shootable (no waiting for the next refresh tick).
		if not is_instance_valid(_autoplay_enemy) \
				or not _autoplay_los_clear((_autoplay_enemy as Node2D).global_position):
			_autoplay_enemy = _autoplay_find_visible_enemy()
		if not is_instance_valid(_autoplay_enemy):
			return false
		if not _autoplay_los_clear((_autoplay_enemy as Node2D).global_position):
			return false
		# Don't gate on a mana buffer — _handle_shooting already skips firing
		# if the actual cost can't be paid, and over-gating means the bot
		# stops firing the moment mana dips below a comfortable level.
		return true
	return Input.is_action_pressed("shoot")

# True if there's no wall between us and target_pos. Other enemies/the player
# do NOT block — projectiles handle them naturally.
func _autoplay_los_clear(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return not (hit.get("collider") is StaticBody2D)

func _autoplay_find_visible_enemy() -> Node2D:
	# Threat-based scoring: prefer bosses → low-HP "easy kill" finishes →
	# closer enemies. Picks the highest-threat visible target.
	var best: Node2D = null
	var best_score: float = -INF
	# Cap engagement range so we don't raycast every enemy in a packed room.
	# Bosses are always considered regardless of range so the bot keeps firing
	# during boss fights even from across the arena.
	const ENGAGE_R_SQ := 700.0 * 700.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if _autoplay_skipped_enemies.has(e.get_instance_id()):
			continue
		var ne := e as Node2D
		var is_boss := ne.is_in_group("boss")
		var d_sq: float = global_position.distance_squared_to(ne.global_position)
		if not is_boss and d_sq > ENGAGE_R_SQ:
			continue
		if not _autoplay_los_clear(ne.global_position):
			continue
		var d: float = sqrt(d_sq)
		var score: float = 1500.0 / max(d, 30.0)   # closer = higher base score
		# Boss priority — anything with the boss group always wins ties
		if is_boss:
			score += 8000.0
		# Easy-kill bonus: low-HP-ratio enemies are worth finishing first
		if "health" in ne and "max_health" in ne:
			var max_hp_e: float = maxf(1.0, float(ne.get("max_health")))
			var hp_ratio: float = float(ne.get("health")) / max_hp_e
			score += (1.0 - hp_ratio) * 800.0
		if score > best_score:
			best_score = score
			best = ne
	return best

# True if the bag contains anything worth detouring for: any wand (always
# considered) or any equipment piece that beats the current slot by rarity.
# Potions/valuables are picked up if the bot happens to walk past, but they
# don't justify a detour.
func _autoplay_bag_has_upgrade(bag: Node) -> bool:
	if not "items" in bag:
		return false
	for it in bag.get("items"):
		if not (it is Item):
			continue
		var item: Item = it as Item
		if item.type == Item.Type.WAND:
			return true   # always worth checking new wands
		var slot := item.get_equip_slot_name()
		if slot == "":
			continue
		var current: Item = InventoryManager.equipped.get(slot) as Item
		if current == null or item.rarity > current.rarity:
			return true
	return false

# Picks the bag worth going to. Filters to bags with actual upgrades, then
# prefers higher-rarity contents, tie-broken by distance. Skipped bags are
# excluded so the bot doesn't loop on something it can't fully loot.
func _autoplay_find_nearest_loot() -> Node2D:
	var best: Node2D = null
	var best_score := INF
	for b in get_tree().get_nodes_in_group("loot_bag"):
		if not is_instance_valid(b):
			continue
		if _autoplay_skipped_bags.has(b.get_instance_id()):
			continue
		if not _autoplay_bag_has_upgrade(b):
			continue
		var nb := b as Node2D
		var max_r: int = -1
		if "items" in nb:
			for it in nb.get("items"):
				if it is Item and (it as Item).rarity > max_r:
					max_r = (it as Item).rarity
		var d: float = global_position.distance_to(nb.global_position)
		var score: float = -float(max_r) * 1500.0 + d
		if score < best_score:
			best_score = score
			best = nb
	return best

# Pulls items out of any nearby loot bag straight into the inventory.
# If the inventory is full, the bag gets blacklisted so the bot stops loitering.
func _autoplay_try_loot() -> void:
	var resolved_any := false
	for b in get_tree().get_nodes_in_group("loot_bag"):
		if not is_instance_valid(b):
			continue
		if global_position.distance_to((b as Node2D).global_position) > 36.0:
			continue
		if "items" in b:
			var bag_items: Array = b.get("items")
			var any_failed := false
			var i := 0
			while i < bag_items.size():
				var it: Item = bag_items[i] as Item
				if it != null and InventoryManager.add_item(it):
					bag_items.remove_at(i)
				else:
					any_failed = true
					i += 1
			b.set("items", bag_items)
			if bag_items.is_empty():
				(b as Node).queue_free()
				resolved_any = true
			elif any_failed:
				# Couldn't fit everything — don't come back to this bag again
				_autoplay_skipped_bags[b.get_instance_id()] = true
				resolved_any = true
	# Immediately re-pick a target so the bot doesn't loiter on a freed/blacklisted bag
	if resolved_any:
		_autoplay_refresh_targets()
		_autoplay_loot_target_t = 0.0

# Probe several angles around our intended direction and pick the most-aligned
# clear path. This handles concave corners and sliding-into-corner cases that
# a single ray + slide can't escape.
func _autoplay_clear_dir(dir: Vector2, dist: float) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, global_position + dir * dist)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	return not (hit.get("collider") is StaticBody2D)

func _autoplay_avoid_walls(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	# Try increasingly-deflected angles; first clear one wins. Includes both
	# halves so the player picks whichever side around an obstacle is open.
	var offsets: Array = [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]
	for off in offsets:
		var test := dir.rotated(off)
		if _autoplay_clear_dir(test, 42.0):
			return test
	# Everything within 42px is blocked — nudge perpendicular and let
	# stuck-detection take over if we're truly cornered.
	return dir.rotated(PI * 0.5)

func _autoplay_move_dir() -> Vector2:
	# Wiggle override — when we've been stuck, grind forward with randomized
	# angular jitter every frame so the player physics finds an opening.
	if _autoplay_stuck_t > 0.20:
		var goal_dir := Vector2.ZERO
		if is_instance_valid(_autoplay_move_to):
			goal_dir = ((_autoplay_move_to as Node2D).global_position - global_position).normalized()
		if goal_dir == Vector2.ZERO:
			goal_dir = Vector2.RIGHT
		# Jitter angle scales with how stuck we are — small wiggle at first,
		# bigger sweeps if it keeps not working.
		var amp: float = clampf(0.6 + (_autoplay_stuck_t - 0.20) * 1.5, 0.6, 1.6)
		var jitter: float = randf_range(-amp, amp)
		return goal_dir.rotated(jitter)
	var base := Vector2.ZERO
	# Follow A* path waypoints when one is computed
	var pdir := _autoplay_path_dir()
	if pdir != Vector2.ZERO:
		base = pdir
	elif is_instance_valid(_autoplay_move_to):
		var to_t: Vector2 = (_autoplay_move_to as Node2D).global_position - global_position
		if to_t.length() > 4.0:
			base = _autoplay_avoid_walls(to_t.normalized())
	if base == Vector2.ZERO:
		return Vector2.ZERO
	# Blend in projectile-dodge force — heavier weighting when shots are close
	var dodge := _autoplay_dodge_force()
	var ds := dodge.length()
	if ds > 0.55:
		return (base * 0.35 + dodge.normalized()).normalized()
	if ds > 0.0:
		return (base + dodge.normalized() * 0.7).normalized()
	return base

# Returns a sidestep vector summed across nearby incoming enemy projectiles.
# Each contribution is perpendicular to the projectile's flight, biased to
# whichever side moves us further from its line of travel; weight scales with
# proximity. Aggregate vector magnitude conveys urgency.
func _autoplay_dodge_force() -> Vector2:
	var total := Vector2.ZERO
	const DODGE_R := 200.0
	const DODGE_R_SQ := DODGE_R * DODGE_R
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(p):
			continue
		var proj := p as Node2D
		var to_us: Vector2 = global_position - proj.global_position
		# Cheap squared-distance gate avoids the sqrt for far-off projectiles,
		# which dominates the loop in busy rooms with many shots in flight.
		var d_sq := to_us.length_squared()
		if d_sq > DODGE_R_SQ or d_sq < 0.0001:
			continue
		var pdir: Vector2 = Vector2.ZERO
		if "direction" in proj:
			pdir = (proj.direction as Vector2).normalized()
		if pdir == Vector2.ZERO:
			continue
		var dist := sqrt(d_sq)
		# Skip projectiles already past us / not actually incoming
		var to_us_n := to_us / dist
		var alignment := pdir.dot(to_us_n)
		if alignment < 0.35:
			continue
		# Sidestep perpendicular, picking whichever side moves us out of the line
		var perp := pdir.rotated(PI * 0.5)
		var s: float = 1.0 if perp.dot(to_us_n) > 0.0 else -1.0
		var weight := clampf(1.0 - dist / DODGE_R, 0.05, 1.0) * (0.4 + alignment * 0.6)
		total += perp * s * weight
	return total

func _autoplay_refresh_targets() -> void:
	# Shoot at any visible enemy (LOS-only — no chasing through walls)
	_autoplay_enemy = _autoplay_find_visible_enemy()
	# Movement objective: portal first, but divert to loot if it's close enough
	# to be worth picking up on the way. Sprint mode skips loot entirely;
	# critical HP forces a temporary sprint so the bot prioritises survival.
	var portal := get_tree().get_first_node_in_group("portal")
	var hp_ratio: float = float(health) / maxf(1.0, float(_max_hp()))
	var force_sprint: bool = hp_ratio < 0.25
	# Boss focus — if any boss is alive on this floor, the portal is locked.
	# Path to the nearest living boss instead of the portal so the bot actually
	# closes the distance and engages, rather than idling near a locked portal.
	var boss: Node2D = _autoplay_nearest_boss()
	var loot: Node2D = null
	# When hunting a boss, skip the loot detour entirely so the bot doesn't
	# wander off mid-fight to grab a bag.
	if boss == null and not _autoplay_sprint and not force_sprint:
		loot = _autoplay_find_nearest_loot()
	var goal: Node2D = portal as Node2D
	if boss != null:
		goal = boss
	elif is_instance_valid(loot):
		# Pull range scales with rarity — purple bags warp the bot from further
		var max_r := -1
		if "items" in loot:
			for it in loot.get("items"):
				if it is Item and (it as Item).rarity > max_r:
					max_r = (it as Item).rarity
		var pull_range := 280.0 + 220.0 * float(max_r + 1)
		if global_position.distance_to(loot.global_position) < pull_range:
			goal = loot
	if goal == null and is_instance_valid(loot):
		goal = loot
	if goal != _autoplay_move_to:
		_autoplay_move_to = goal
		if is_instance_valid(goal):
			_autoplay_compute_path((goal as Node2D).global_position)

func _autoplay_nearest_boss() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for b in get_tree().get_nodes_in_group("boss"):
		if not is_instance_valid(b):
			continue
		var nb := b as Node2D
		var d: float = global_position.distance_to(nb.global_position)
		if d < best_d:
			best_d = d
			best = nb
	return best

# ── A* pathfinding ──────────────────────────────────────────────────────────
func _autoplay_build_astar() -> void:
	var world := get_tree().current_scene
	if world == null:
		return
	if not "_grid" in world:
		_astar = null
		return
	if world.get_instance_id() == _astar_world_id and _astar != null:
		return   # already built for this floor
	var grid: Array = world._grid
	var grid_w: int = int(world.GRID_W)
	var grid_h: int = int(world.GRID_H)
	var tile: int   = int(world.TILE)
	_astar = AStarGrid2D.new()
	_astar.region    = Rect2i(0, 0, grid_w, grid_h)
	_astar.cell_size = Vector2i(tile, tile)
	# Diagonal moves only when BOTH adjacent cells are walkable — prevents the
	# bot from cutting through corner pinches it can't physically squeeze past.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.update()
	for y in grid_h:
		for x in grid_w:
			if int((grid[y] as Array)[x]) != 0:   # FLOOR=0, WALL=1
				_astar.set_point_solid(Vector2i(x, y), true)
	# Secret doors are StaticBody2Ds sitting on tiles the grid still says are
	# floor — weight them moderately so paths prefer alternatives, but allow
	# routing through (the bot auto-opens any door it physically touches via
	# SecretDoor.gd). Letting paths go through means the bot actually
	# *finds* secret-room loot instead of perpetually skipping past.
	for door in get_tree().get_nodes_in_group("secret_door"):
		if not is_instance_valid(door):
			continue
		var dpos: Vector2 = (door as Node2D).global_position
		var dx: int = int(dpos.x / float(tile))
		var dy: int = int(dpos.y / float(tile))
		if dx >= 0 and dx < grid_w and dy >= 0 and dy < grid_h:
			_astar.set_point_weight_scale(Vector2i(dx, dy), 4.0)
	# Traps (spike + spin) — heavily weighted so paths avoid stepping on them
	# unless there's no alternative. Also weight the 4 cardinal neighbors so
	# the bot doesn't graze the trap's edge by accident.
	for tr in get_tree().get_nodes_in_group("trap"):
		if not is_instance_valid(tr):
			continue
		var tpos: Vector2 = (tr as Node2D).global_position
		var tx: int = int(tpos.x / float(tile))
		var ty: int = int(tpos.y / float(tile))
		if tx >= 0 and tx < grid_w and ty >= 0 and ty < grid_h:
			_astar.set_point_weight_scale(Vector2i(tx, ty), 15.0)
			# Penumbra — small extra cost on adjacent tiles so paths stay clear
			for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var ax: int = tx + off.x
				var ay: int = ty + off.y
				if ax >= 0 and ax < grid_w and ay >= 0 and ay < grid_h:
					if int((grid[ay] as Array)[ax]) == 0:
						# Don't override existing heavy weights (pinches etc)
						var current_weight := _astar.get_point_weight_scale(Vector2i(ax, ay))
						if current_weight < 3.0:
							_astar.set_point_weight_scale(Vector2i(ax, ay), 3.0)
	# Biome hazards (lava / poison / ice) — moderate weight so the bot routes
	# around them when feasible but still crosses if it's the only path.
	for hz in get_tree().get_nodes_in_group("hazard"):
		if not is_instance_valid(hz):
			continue
		var hpos: Vector2 = (hz as Node2D).global_position
		var hx: int = int(hpos.x / float(tile))
		var hy: int = int(hpos.y / float(tile))
		if hx >= 0 and hx < grid_w and hy >= 0 and hy < grid_h:
			_astar.set_point_weight_scale(Vector2i(hx, hy), 5.0)
	# Teleporters the bot has already triggered once — mark solid so future
	# paths route around them instead of stepping back onto the same pad.
	for pos in _autoplay_avoid_positions:
		var bx: int = int((pos as Vector2).x / float(tile))
		var by: int = int((pos as Vector2).y / float(tile))
		if bx >= 0 and bx < grid_w and by >= 0 and by < grid_h:
			_astar.set_point_solid(Vector2i(bx, by), true)
	# Weight floor tiles by adjacent wall count, with a special heavy penalty
	# for "pinch" cells — single-tile-wide corridors (walls on both N+S or
	# both E+W). The player's 24x18 collision can technically fit, but the
	# tight clearance causes hangups, so A* should route around them via any
	# wider corridor that exists.
	for y in grid_h:
		for x in grid_w:
			if int((grid[y] as Array)[x]) != 0:
				continue
			var wall_neighbors := 0
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var nx: int = x + dx
					var ny: int = y + dy
					if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
						continue
					if int((grid[ny] as Array)[nx]) != 0:
						wall_neighbors += 1
			# Detect 1-wide corridor tiles: walls on opposite perpendicular sides
			var n_wall: bool = y > 0           and int((grid[y - 1] as Array)[x]) != 0
			var s_wall: bool = y < grid_h - 1  and int((grid[y + 1] as Array)[x]) != 0
			var e_wall: bool = x < grid_w - 1  and int((grid[y] as Array)[x + 1]) != 0
			var w_wall: bool = x > 0           and int((grid[y] as Array)[x - 1]) != 0
			var pinch: bool = (n_wall and s_wall) or (e_wall and w_wall)
			if pinch:
				# 8× cost — discouraged but the bot will use 1-wide passages
				# when they shorten the route meaningfully (and the wiggle
				# logic handles physically threading through them)
				_astar.set_point_weight_scale(Vector2i(x, y), 8.0)
			elif wall_neighbors >= 4:
				_astar.set_point_weight_scale(Vector2i(x, y), 12.0)
			elif wall_neighbors > 0:
				_astar.set_point_weight_scale(Vector2i(x, y),
					1.0 + float(wall_neighbors) * 0.65)
	_astar_world_id = world.get_instance_id()

# Called by Teleporter.gd when the bot steps on a teleporter pad. Records the
# world position so the next A* rebuild marks that tile solid, forcing future
# paths to detour around it.
func _autoplay_blacklist_pos(pos: Vector2) -> void:
	for existing in _autoplay_avoid_positions:
		if (existing as Vector2).distance_squared_to(pos) < 4.0:
			return   # already recorded
	_autoplay_avoid_positions.append(pos)
	# Force a rebuild so the new solid takes effect on the next path query.
	_astar = null
	_astar_world_id = 0
	_autoplay_path = PackedVector2Array()
	_autoplay_path_idx = 0
	_autoplay_repath_t = 0.0

func _autoplay_compute_path(target_world: Vector2) -> void:
	_autoplay_build_astar()
	if _astar == null:
		_autoplay_path = PackedVector2Array()
		return
	var world := get_tree().current_scene
	var tile: int = int(world.TILE)
	var grid_w: int = int(world.GRID_W)
	var grid_h: int = int(world.GRID_H)
	var s := Vector2i(int(global_position.x / float(tile)), int(global_position.y / float(tile)))
	var e := Vector2i(int(target_world.x / float(tile)), int(target_world.y / float(tile)))
	s.x = clampi(s.x, 0, grid_w - 1)
	s.y = clampi(s.y, 0, grid_h - 1)
	e.x = clampi(e.x, 0, grid_w - 1)
	e.y = clampi(e.y, 0, grid_h - 1)
	if _astar.is_point_solid(s) or _astar.is_point_solid(e):
		# Endpoint became solid (we may be edge-clipping a wall, or the goal
		# is inside a wall) — force a fresh A* and try one more time, then
		# give up gracefully.
		_astar = null
		_astar_world_id = 0
		_autoplay_build_astar()
		if _astar == null or _astar.is_point_solid(s) or _astar.is_point_solid(e):
			_autoplay_path = PackedVector2Array()
			return
	_autoplay_path = _astar.get_point_path(s, e)
	_autoplay_path_idx = 0
	# Empty path despite both endpoints walkable usually means the world
	# changed (secret door opened, breakable wall destroyed). Rebuild A* once.
	if _autoplay_path.is_empty() and s != e:
		_astar = null
		_astar_world_id = 0
		_autoplay_build_astar()
		if _astar != null and not _astar.is_point_solid(s) and not _astar.is_point_solid(e):
			_autoplay_path = _astar.get_point_path(s, e)
			_autoplay_path_idx = 0

func _autoplay_path_dir() -> Vector2:
	if _autoplay_path.is_empty():
		return Vector2.ZERO
	var world := get_tree().current_scene
	var half := Vector2(float(int(world.TILE)) * 0.5, float(int(world.TILE)) * 0.5)
	while _autoplay_path_idx < _autoplay_path.size():
		var wp: Vector2 = _autoplay_path[_autoplay_path_idx] + half
		var to_wp := wp - global_position
		if to_wp.length() < 14.0:
			_autoplay_path_idx += 1
			continue
		return _autoplay_steer_from_walls(to_wp.normalized())
	return Vector2.ZERO

# Probes left/right of the current direction. If a wall is close on one side
# only, biases the direction away from it so the player stays in the middle
# of corridors instead of grazing edges and getting hung up.
func _autoplay_steer_from_walls(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	var space := get_world_2d().direct_space_state
	var probe_dist := 22.0
	var perp := dir.rotated(PI * 0.5)
	var right_blocked := false
	var left_blocked  := false
	var q1 := PhysicsRayQueryParameters2D.create(global_position, global_position + perp * probe_dist)
	q1.exclude = [get_rid()]
	var h1 := space.intersect_ray(q1)
	if not h1.is_empty() and h1.get("collider") is StaticBody2D:
		right_blocked = true
	var q2 := PhysicsRayQueryParameters2D.create(global_position, global_position - perp * probe_dist)
	q2.exclude = [get_rid()]
	var h2 := space.intersect_ray(q2)
	if not h2.is_empty() and h2.get("collider") is StaticBody2D:
		left_blocked = true
	if right_blocked and not left_blocked:
		return (dir - perp * 0.6).normalized()
	elif left_blocked and not right_blocked:
		return (dir + perp * 0.6).normalized()
	return dir

func _autoplay_tick(delta: float) -> void:
	_autoplay_target_t -= delta
	if _autoplay_target_t <= 0.0:
		_autoplay_target_t = 0.35
		_autoplay_refresh_targets()
	# Periodically repath toward the current move target — handles drift from
	# knockback, doors opening, the goal changing, etc.
	_autoplay_repath_t -= delta
	if _autoplay_repath_t <= 0.0:
		_autoplay_repath_t = 0.7
		if is_instance_valid(_autoplay_move_to):
			_autoplay_compute_path((_autoplay_move_to as Node2D).global_position)
	_autoplay_loot_t -= delta
	if _autoplay_loot_t <= 0.0:
		_autoplay_loot_t = 0.25
		_autoplay_try_loot()
	_autoplay_equip_t -= delta
	if _autoplay_equip_t <= 0.0:
		_autoplay_equip_t = 1.5
		_autoplay_auto_equip()
	# Nova when surrounded
	_autoplay_nova_t -= delta
	if _autoplay_nova_t <= 0.0:
		_autoplay_nova_t = 0.5
		_autoplay_try_nova()
	# Health potion when very low
	_autoplay_potion_t -= delta
	if _autoplay_potion_t <= 0.0:
		_autoplay_potion_t = 0.6
		_autoplay_try_potion()
	# Periodically clear junk so the inventory doesn't fill up with valuables
	# / worse-tier duplicates and block new pickups
	_autoplay_clean_t -= delta
	if _autoplay_clean_t <= 0.0:
		_autoplay_clean_t = 4.0
		_autoplay_clear_junk()
	# Loot-pursuit timeout — if we've been chasing the same bag for too long
	# without successfully looting it, blacklist and move on
	if is_instance_valid(_autoplay_move_to) and _autoplay_move_to.is_in_group("loot_bag"):
		_autoplay_loot_target_t += delta
		if _autoplay_loot_target_t > 5.0:
			_autoplay_skipped_bags[_autoplay_move_to.get_instance_id()] = true
			_autoplay_loot_target_t = 0.0
			_autoplay_refresh_targets()
	else:
		_autoplay_loot_target_t = 0.0
	# Track damage progress on the current shoot target — if its HP isn't
	# dropping after we've been firing at it for a while, it's likely wall-
	# clipped or otherwise unreachable. Blacklist so the bot moves on.
	if is_instance_valid(_autoplay_enemy):
		var hp_now: int = -1
		if "health" in _autoplay_enemy:
			hp_now = int(_autoplay_enemy.get("health"))
		if _autoplay_enemy_last_hp == -1 or _autoplay_enemy_last_hp == 0:
			_autoplay_enemy_last_hp = hp_now
			_autoplay_enemy_dmg_t = 0.0
		elif hp_now < _autoplay_enemy_last_hp:
			_autoplay_enemy_last_hp = hp_now
			_autoplay_enemy_dmg_t = 0.0
		else:
			_autoplay_enemy_dmg_t += delta
			if _autoplay_enemy_dmg_t > 6.0:
				_autoplay_skipped_enemies[_autoplay_enemy.get_instance_id()] = true
				_autoplay_enemy = null
				_autoplay_enemy_last_hp = -1
				_autoplay_enemy_dmg_t = 0.0
	else:
		_autoplay_enemy_last_hp = -1
		_autoplay_enemy_dmg_t = 0.0

	# Update overlays
	_autoplay_update_overlays()

	# ── Stuck detection ──────────────────────────────────────────────────
	# Track actual displacement per physics frame. The stuck timer accumulates
	# when we're not making progress and decays when we are — once it crosses
	# a threshold, _autoplay_move_dir switches to a wiggle override that
	# grinds toward the goal with growing angular jitter until something gives.
	var moved := global_position.distance_to(_autoplay_last_pos)
	_autoplay_last_pos = global_position
	# Only count as stuck if we're TRYING to get somewhere — don't accumulate
	# while standing on a goal we already reached
	var goal_dist := INF
	if is_instance_valid(_autoplay_move_to):
		goal_dist = global_position.distance_to((_autoplay_move_to as Node2D).global_position)
	if is_instance_valid(_autoplay_move_to) and goal_dist > 30.0 and moved < 1.5:
		_autoplay_stuck_t += delta
	else:
		_autoplay_stuck_t = maxf(0.0, _autoplay_stuck_t - delta * 1.6)

# Updates HUD label, path-debug Line2D, and target ring each frame.
func _autoplay_update_overlays() -> void:
	# HUD status text
	if _autoplay_hud_label:
		_autoplay_hud_label.visible = _autoplay
		if _autoplay:
			var line: String = "AUTO"
			var hp_ratio: float = float(health) / maxf(1.0, float(_max_hp()))
			if hp_ratio < 0.25:
				line += " · RETREAT"
			elif _autoplay_sprint:
				line += " · SPRINT"
			# Boss tag if any boss is alive on this floor
			for b in get_tree().get_nodes_in_group("boss"):
				if is_instance_valid(b):
					line += " · BOSS"
					break
			line += "\n→ "
			if _autoplay_stuck_t > 0.20:
				line += "WIGGLE"
			elif is_instance_valid(_autoplay_move_to):
				if _autoplay_move_to == _autoplay_enemy:
					line += "ENEMY"
				elif _autoplay_move_to.is_in_group("loot_bag"):
					line += "LOOT"
				elif _autoplay_move_to.is_in_group("portal"):
					line += "PORTAL"
				else:
					line += "MOVE"
			else:
				line += "—"
			_autoplay_hud_label.text = line
	# Path debug
	if _autoplay_path_line:
		if _autoplay and not _autoplay_path.is_empty():
			_autoplay_path_line.clear_points()
			_autoplay_path_line.add_point(global_position)
			var half := Vector2(16.0, 16.0)
			for i in range(_autoplay_path_idx, _autoplay_path.size()):
				_autoplay_path_line.add_point(_autoplay_path[i] + half)
			_autoplay_path_line.visible = true
		else:
			_autoplay_path_line.visible = false
	# Target marker ring
	if _autoplay_target_marker:
		if _autoplay and is_instance_valid(_autoplay_enemy):
			_autoplay_target_marker.global_position = (_autoplay_enemy as Node2D).global_position
			_autoplay_target_marker.visible = true
		else:
			_autoplay_target_marker.visible = false

func _autoplay_auto_equip() -> void:
	if InventoryManager == null:
		return
	# For each equipment slot, equip the highest-rarity item that beats what's
	# currently slotted. Wand variety is handled by Portal mutating the
	# equipped wand's shoot_type on each floor — no fresh-type preference here.
	var dirty := false
	for it in InventoryManager.grid:
		var item: Item = it as Item
		if item == null:
			continue
		var slot := item.get_equip_slot_name()
		if slot == "":
			continue
		var current: Item = InventoryManager.equipped.get(slot) as Item
		if current == null or item.rarity > current.rarity:
			InventoryManager.equipped[slot] = item
			dirty = true
	if dirty:
		InventoryManager.inventory_changed.emit()
		update_equip_stats()

# Nova-bombs the room when a meaningful cluster of enemies is in range.
func _autoplay_try_nova() -> void:
	if _spell_cooldown > 0.0:
		return
	if mana < NOVA_MANA_COST:
		return
	var cluster := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_to((e as Node2D).global_position) < 230.0:
			cluster += 1
			if cluster >= 4:
				break
	if cluster >= 4:
		_cast_nova_spell()

# Sweeps the inventory grid: keeps only items that are useful to the bot.
# Caps potions at MAX_POTIONS so they don't fill the grid and block new pickups.
const AUTOPLAY_MAX_POTIONS: int = 2
func _autoplay_clear_junk() -> void:
	if InventoryManager == null:
		return
	var changed := false
	var potions_kept := 0
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		if item.type == Item.Type.WAND:
			continue   # always keep wands (auto-equip picks the best)
		if item.type == Item.Type.POTION:
			if potions_kept < AUTOPLAY_MAX_POTIONS:
				potions_kept += 1
				continue
			# Drop extras — bot only ever needs a couple of healing pots
			InventoryManager.grid[i] = null
			changed = true
			continue
		# Equipment that's an upgrade for its slot — keep
		var slot := item.get_equip_slot_name()
		if slot != "":
			var current: Item = InventoryManager.equipped.get(slot) as Item
			if current == null or item.rarity > current.rarity:
				continue
		# Junk — drop it
		InventoryManager.grid[i] = null
		changed = true
	if changed:
		InventoryManager.inventory_changed.emit()

# Drinks a Health Potion when the bot drops below 35% HP.
func _autoplay_try_potion() -> void:
	if InventoryManager == null:
		return
	var max_hp := _max_hp()
	if max_hp <= 0:
		return
	if float(health) / float(max_hp) > 0.35:
		return
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item != null and item.type == Item.Type.POTION:
			InventoryManager.use_potion_at(i)
			return

# Dash to break out of contact when very low HP and an enemy is on top of us.
func _autoplay_wants_dash() -> bool:
	if not _autoplay:
		return false
	if stamina < DASH_STAMINA_COST:
		return false
	var max_hp := _max_hp()
	if max_hp <= 0 or float(health) / float(max_hp) > 0.30:
		return false
	if not is_instance_valid(_autoplay_enemy):
		return false
	return global_position.distance_to((_autoplay_enemy as Node2D).global_position) < 100.0

# Where to face the shield while autoplaying — bias toward the densest cone
# of incoming enemy projectiles. Falls back to nearest visible enemy, then
# to mouse position as a last resort.
func _autoplay_shield_aim_pos() -> Vector2:
	# Average position of projectiles converging on us within 220px
	var avg := Vector2.ZERO
	var count := 0
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(p):
			continue
		var proj := p as Node2D
		var to_us: Vector2 = global_position - proj.global_position
		var dist := to_us.length()
		if dist > 220.0 or dist < 0.001:
			continue
		var pdir: Vector2 = Vector2.ZERO
		if "direction" in proj:
			pdir = (proj.direction as Vector2).normalized()
		if pdir == Vector2.ZERO:
			continue
		if pdir.dot(to_us.normalized()) < 0.35:
			continue
		avg += proj.global_position
		count += 1
	if count > 0:
		return avg / float(count)
	# Fallback: face nearest visible enemy
	var nearest := _autoplay_find_visible_enemy()
	if is_instance_valid(nearest):
		return (nearest as Node2D).global_position
	return get_global_mouse_position()

# Pop the shield when projectiles are converging. Eager-shield when low HP:
# threshold drops from 3 to 1 so any incoming shot triggers protection.
func _autoplay_wants_shield() -> bool:
	var hp_ratio: float = float(health) / maxf(1.0, float(_max_hp()))
	var trigger: int = 1 if hp_ratio < 0.30 else 3
	var threats := 0
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(p):
			continue
		var proj := p as Node2D
		var to_us: Vector2 = global_position - proj.global_position
		var dist := to_us.length()
		if dist > 180.0 or dist < 0.001:
			continue
		var pdir: Vector2 = Vector2.ZERO
		if "direction" in proj:
			pdir = (proj.direction as Vector2).normalized()
		if pdir == Vector2.ZERO:
			continue
		if pdir.dot(to_us.normalized()) > 0.5:
			threats += 1
			if threats >= trigger:
				return true
	return false

func _handle_movement() -> void:
	if _knockback_timer > 0.0:
		_knockback_timer -= get_physics_process_delta_time()
		velocity = _knockback_vel * maxf(0.0, _knockback_timer / KNOCKBACK_DURATION)
		move_and_slide()
		if _knockback_timer <= 0.0:
			_knockback_vel = Vector2.ZERO
		return
	if _dash_timer > 0.0:
		velocity = _dash_dir * DASH_SPEED
		move_and_slide()
		return
	var direction := Vector2.ZERO
	if _autoplay:
		direction = _autoplay_move_dir()
	else:
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
	# Disorient: WASD is mapped to the rotated view, so "up" is up on the spinning screen
	# (Skip for autoplay — it already produces a world-space direction toward the target)
	if _disorient_angle != 0.0 and direction != Vector2.ZERO and not _autoplay:
		direction = direction.rotated(_disorient_angle)
	var slow_mult := 0.5 if _slow_timer > 0.0 else 1.0
	var haste_mult := 1.3 if GameState.floor_modifier == "haste" else 1.0
	var agi_bonus := float(GameState.get_stat_bonus("AGI")) * 4.0
	velocity = direction * (speed + _equip_speed_bonus + agi_bonus) * _speed_multiplier * slow_mult * haste_mult
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
	# DEX shaves a small percentage off cooldown (capped 60% reduction)
	var dex_mult := clampf(1.0 - float(GameState.get_stat_bonus("DEX")) * 0.005, 0.4, 1.0)
	actual_rate = maxf(0.04, actual_rate * dex_mult)

	if _wants_shoot() and _shoot_cooldown <= 0.0:
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
	if not _wants_shoot():
		if _beam_line:
			_beam_line.visible = false
		return

	var drain: float = wand.wand_mana_cost
	if "mana_guzzle" in wand.wand_flaws:
		drain *= 2.0
	var drain_this_frame := drain * delta
	if mana < drain_this_frame:
		if _beam_line:
			_beam_line.visible = false
		return

	mana -= drain_this_frame

	_beam_hum_t -= delta
	if _beam_hum_t <= 0.0:
		_beam_hum_t = 0.4
		if SoundManager:
			SoundManager.play("beam_hum", randf_range(0.95, 1.06))

	var intel      := clampi(1 + (GameState.level - 1) / 2, 1, 8)
	var beam_dmg   := wand.wand_damage + intel * 2 + GameState.get_stat_bonus("STR")
	var mouse_dir  := (_get_aim_pos() - global_position).normalized()
	var space      := get_world_2d().direct_space_state
	var end_pos    := global_position + mouse_dir * 700.0
	var excluded: Array[RID] = [get_rid()]

	_shoot_cooldown -= delta
	var do_dmg := _shoot_cooldown <= 0.0
	if do_dmg:
		_shoot_cooldown = 0.08

	var from_pos := global_position
	# Beam pierces every enemy in its path; only walls block. The 32-iteration
	# cap is just a safety net against infinite loops if something goes weird.
	for _pass in 32:
		var params := PhysicsRayQueryParameters2D.create(from_pos, global_position + mouse_dir * 700.0)
		params.exclude = excluded
		var hit := space.intersect_ray(params)
		if hit.is_empty():
			break
		var collider: Object = hit.get("collider")
		var hit_pos: Vector2 = hit.get("position", end_pos)
		if collider == null or not collider.is_in_group("enemy"):
			end_pos = hit_pos   # stop visual at wall
			break
		if do_dmg:
			var dmg_to_deal := beam_dmg
			var crit := GameState.roll_crit()
			if crit:
				dmg_to_deal *= 2
			if collider.has_method("take_damage"):
				collider.take_damage(dmg_to_deal)
				GameState.damage_dealt += dmg_to_deal
			if crit and collider is Node2D:
				FloatingText.spawn_str((collider as Node2D).global_position, "CRIT %d" % dmg_to_deal, Color(1.0, 0.85, 0.1), get_tree().current_scene)
			if collider.has_method("apply_status"):
				collider.apply_status("burn_hit", 0.0)
		excluded.append(collider.get_rid())
		from_pos = hit_pos + mouse_dir * 2.0  # nudge past enemy to continue

	if _beam_line == null:
		_beam_line = Line2D.new()
		_beam_line.default_color = Color(0.3, 0.8, 1.0, 0.85)
		add_child(_beam_line)
	_beam_line.width   = 3.5 + float(intel) * 1.5
	_beam_line.visible = true
	_beam_line.clear_points()
	_beam_line.add_point(Vector2.ZERO)
	_beam_line.add_point(to_local(end_pos))

func _fire(wand: Item = null) -> void:
	if projectile_scene == null:
		push_warning("Player: projectile_scene is not set!")
		return

	var base_dir := (_get_aim_pos() - global_position).normalized()
	if SoundManager and (wand == null or wand.wand_shoot_type != "melee"):
		var sfx := "shoot"
		if wand != null:
			match wand.wand_shoot_type:
				"pierce":   sfx = "shoot_pierce"
				"ricochet": sfx = "shoot_ricochet"
				"freeze":   sfx = "shoot_freeze"
				"fire":     sfx = "shoot_fire"
				"shock":    sfx = "shoot_shock"
				"shotgun":  sfx = "shoot_shotgun"
				"homing":   sfx = "shoot_homing"
				"nova":     sfx = "shoot_nova"
				"beam":     sfx = ""   # beam handles its own continuous hum
		if sfx != "":
			SoundManager.play(sfx, randf_range(0.92, 1.08))

	if wand != null:
		if "backwards" in wand.wand_flaws:
			base_dir = -base_dir
		if "erratic" in wand.wand_flaws:
			base_dir = base_dir.rotated(randf_range(-0.7, 0.7))

		if wand.wand_shoot_type == "melee":
			_fire_melee(wand, base_dir)
			return

		var _intel := clampi(1 + (GameState.level - 1) / 2, 1, 8)
		var _str_bonus := GameState.get_stat_bonus("STR")
		if wand.wand_shoot_type == "shotgun":
			var spread_total := deg_to_rad(48.0)
			for i in 5:
				var angle_offset := -spread_total * 0.5 + spread_total * (float(i) / 4.0)
				var sProj := projectile_scene.instantiate()
				sProj.global_position = global_position
				sProj.direction = base_dir.rotated(angle_offset)
				sProj.set("source", "player")
				sProj.set("damage", wand.wand_damage + _str_bonus)
				sProj.set("shoot_type", "shotgun")
				sProj.set("player_intelligence", _intel)
				var sSpd := wand.wand_proj_speed
				if "slow_shots" in wand.wand_flaws:
					sSpd *= 0.5
				sProj.set("speed", sSpd)
				sProj.set("drift_speed", 0.0)
				get_tree().current_scene.add_child(sProj)
			return

		var proj := projectile_scene.instantiate()
		proj.global_position = global_position
		proj.direction = base_dir
		proj.set("source", "player")
		proj.set("damage", wand.wand_damage + _str_bonus)
		proj.set("pierce_remaining", wand.wand_pierce)
		proj.set("ricochet_remaining", wand.wand_ricochet)
		proj.set("shoot_type", wand.wand_shoot_type)
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
		if wand.wand_shoot_type == "fire" and _syn_pyromaniac:
			proj.set("fire_patch_upgraded", true)
		if wand.wand_shoot_type == "freeze" and _syn_glacial:
			proj.set("glacial_bonus", true)
		if wand.wand_shoot_type == "shock" and _syn_arc_conductor:
			proj.set("pierce_remaining", wand.wand_pierce + 1)
		if wand.wand_shoot_type == "nova" and _syn_void_lens:
			proj.set("void_lens_active", true)
		if wand.wand_shoot_type == "homing" and _syn_assassin_mark:
			proj.set("assassin_mark", true)
		proj.set("player_intelligence", _intel)
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

func _fire_melee(wand: Item, _base_dir: Vector2) -> void:
	# Strike lands at the mouse cursor (capped at MAX_REACH so it stays melee-ish)
	var max_reach := 320.0
	var radius    := 48.0
	var aim_pos := _get_aim_pos()
	var to_mouse := aim_pos - global_position
	var hit_pos: Vector2
	if to_mouse.length() <= max_reach:
		hit_pos = aim_pos
	else:
		hit_pos = global_position + to_mouse.normalized() * max_reach

	var intel  := clampi(1 + (GameState.level - 1) / 2, 1, 8)
	var dmg    := wand.wand_damage + intel * 3 + GameState.get_stat_bonus("STR")

	# Instant overlap query
	var space  := get_world_2d().direct_space_state
	var query  := PhysicsShapeQueryParameters2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	query.shape     = circle
	query.transform = Transform2D(0.0, hit_pos)
	query.collision_mask = 0xFFFFFFFF
	query.exclude = [get_rid()]
	var any_hit := false
	for res in space.intersect_shape(query, 32):
		var body: Object = res.get("collider")
		if body == null or not (body as Node).is_in_group("enemy"):
			continue
		if (body as Node).has_method("take_damage"):
			var actual := dmg
			var crit := GameState.roll_crit()
			if crit:
				actual *= 2
			(body as Node).take_damage(actual)
			GameState.damage_dealt += actual
			any_hit = true
			if crit:
				FloatingText.spawn_str((body as Node2D).global_position, "CRIT %d" % actual, Color(1.0, 0.85, 0.1), get_tree().current_scene)
	if SoundManager:
		SoundManager.play("punch", randf_range(0.95, 1.05))
		if any_hit:
			SoundManager.play("punch_hit", randf_range(0.92, 1.08))

	# Visual: knuckles rushing AT the viewer — start small, slam outward
	var art_node := Node2D.new()
	art_node.global_position = hit_pos
	art_node.scale = Vector2(0.4, 0.4)
	var lbl := Label.new()
	lbl.text = _melee_fist_art()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0.25, 0.05, 0.0))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.size     = Vector2(140, 150)
	lbl.position = Vector2(-70, -75)
	lbl.z_index  = 5
	art_node.add_child(lbl)
	get_tree().current_scene.add_child(art_node)
	# Slam: scale up rapidly (knuckles getting closer), then fade
	var tw := art_node.create_tween()
	tw.tween_property(art_node, "scale", Vector2(1.7, 1.7), 0.10)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.18)
	tw.tween_callback(art_node.queue_free)

func _melee_fist_art() -> String:
	return " \\\\_______// \n.-----------.\n|##|##|##|##|\n|##|##|##|##|\n'-----------'\n //       \\\\ "

func heal(amount: int) -> void:
	var prev := health
	health = mini(health + amount, _max_hp())
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
	var def_total: int = GameState.get_stat_bonus("DEF") + _set_def_bonus
	var damage_reduction: float = clampf(float(def_total) * 0.01, 0.0, 0.5)
	var reduced: int = max(0, int(round(float(amount) * (1.0 - damage_reduction))))
	if damage_reduction > 0.0 and reduced < amount:
		FloatingText.spawn_str(global_position, "-%d%%" % int(damage_reduction * 100.0),
			Color(0.3, 0.8, 1.0), get_tree().current_scene)
	amount = reduced
	if amount <= 0:
		return
	health = max(0, health - amount)
	_update_health_bar()
	# Visceral feedback: shake + red flash + varied hurt grunt
	var shake_intensity := clampf(3.0 + float(amount) * 1.6, 4.0, 18.0)
	var shake_duration  := clampf(0.10 + float(amount) * 0.025, 0.14, 0.42)
	camera_shake(shake_intensity, shake_duration)
	_trigger_damage_flash(amount)
	if SoundManager:
		SoundManager.play("player_hurt", randf_range(0.88, 1.12))
	if health == 0:
		_on_death()

func save_state() -> void:
	GameState.player_health = health
	GameState.has_saved_state = true

func _update_health_bar() -> void:
	var bar := get_node_or_null("HUD/HealthBarFG")
	if bar == null:
		return
	var max_hp := _max_hp()
	var ratio := float(health) / float(max_hp)
	bar.offset_right = 11.0 + 200.0 * ratio
	var lbl := get_node_or_null("HUD/HPLabel")
	if lbl:
		lbl.text = "%d / %d" % [health, max_hp]

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
	# perk selection disabled
	pass

# ── Perk selection screen ─────────────────────────────────────────────────────

func _show_perk_screen() -> void:
	if _is_perk_selecting or _perk_queue <= 0:
		return
	_is_perk_selecting = true
	get_tree().paused = true
	_perk_screen = CanvasLayer.new()
	_perk_screen.layer = 28
	_perk_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_perk_screen)
	_build_perk_ui()

func _build_perk_ui() -> void:
	var overlay := ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.72)
	overlay.position = Vector2.ZERO
	overlay.size = Vector2(1600.0, 900.0)
	_perk_screen.add_child(overlay)

	var title := Label.new()
	title.text = "— LEVEL UP —   Choose a Perk"
	title.position = Vector2(440.0, 300.0)
	title.size = Vector2(720.0, 52.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	title.add_theme_constant_override("outline_size", 3)
	_perk_screen.add_child(title)

	var shuffled: Array = PERKS.duplicate()
	shuffled.shuffle()
	var card_w := 280.0
	var card_h := 200.0
	var gap    := 30.0
	var total_w := card_w * 3.0 + gap * 2.0
	var start_x := (1600.0 - total_w) / 2.0
	for i in 3:
		_build_perk_card(shuffled[i], Vector2(start_x + float(i) * (card_w + gap), 390.0), card_w, card_h)

func _build_perk_card(perk: Dictionary, pos: Vector2, w: float, h: float) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.05, 0.18, 0.97)
	bg.position = pos
	bg.size = Vector2(w, h)
	_perk_screen.add_child(bg)

	var top_bar := ColorRect.new()
	top_bar.color = Color(0.55, 0.25, 0.9, 1.0)
	top_bar.position = pos
	top_bar.size = Vector2(w, 3.0)
	_perk_screen.add_child(top_bar)

	var name_lbl := Label.new()
	name_lbl.text = perk["name"]
	name_lbl.position = pos + Vector2(0.0, 14.0)
	name_lbl.size = Vector2(w, 36.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 1.0))
	_perk_screen.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = perk["desc"]
	desc_lbl.position = pos + Vector2(12.0, 64.0)
	desc_lbl.size = Vector2(w - 24.0, 80.0)
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72))
	_perk_screen.add_child(desc_lbl)

	var select_lbl := Label.new()
	select_lbl.text = "[ SELECT ]"
	select_lbl.position = pos + Vector2(0.0, h - 38.0)
	select_lbl.size = Vector2(w, 28.0)
	select_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_lbl.add_theme_font_size_override("font_size", 14)
	select_lbl.add_theme_color_override("font_color", Color(0.45, 0.8, 0.45))
	_perk_screen.add_child(select_lbl)

	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.position = pos
	btn.size = Vector2(w, h)
	btn.mouse_entered.connect(func() -> void:
		bg.color = Color(0.14, 0.08, 0.28, 0.97)
		select_lbl.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6)))
	btn.mouse_exited.connect(func() -> void:
		bg.color = Color(0.08, 0.05, 0.18, 0.97)
		select_lbl.add_theme_color_override("font_color", Color(0.45, 0.8, 0.45)))
	btn.pressed.connect(func() -> void: _apply_perk(perk))
	_perk_screen.add_child(btn)

func _apply_perk(perk: Dictionary) -> void:
	match perk["id"]:
		"hp_up":
			max_health += 3
			health = mini(health + 3, _max_hp())
			_update_health_bar()
		"mana_up":
			_perk_mana_bonus += 25.0
			update_equip_stats()
		"speed_up":
			speed += 40.0
		"fire_rate_up":
			fire_rate = maxf(0.04, fire_rate - 0.04)
		"dash_up":
			_perk_stam_bonus += 20.0
			update_equip_stats()
		"wisdom_up":
			_perk_wisdom_bonus_p += 0.15
			update_equip_stats()
		"proj_up":
			_perk_proj_bonus += 1
			update_equip_stats()
		"heal_now":
			health = _max_hp()
			_update_health_bar()
	FloatingText.spawn_str(global_position, perk["name"], Color(1.0, 0.85, 0.3), get_tree().current_scene)
	_close_perk_screen()

func _close_perk_screen() -> void:
	if _perk_screen:
		_perk_screen.queue_free()
		_perk_screen = null
	_perk_queue -= 1
	if _perk_queue > 0:
		call_deferred("_show_perk_screen")
	else:
		_is_perk_selecting = false
		if not _is_paused:
			get_tree().paused = false

func _on_death() -> void:
	if GameState.test_mode:
		_respawn_test()
		return
	_is_dead = true
	var ranks := Leaderboard.submit(GameState.portals_used, GameState.gold, GameState.damage_dealt)
	Leaderboard.submit_biome_record(GameState.biome, GameState.portals_used, GameState.gold)
	RunHistory.add_run(GameState.portals_used, GameState.kills, GameState.gold,
		GameState.damage_dealt, GameState.biome)
	_build_death_leaderboard(ranks)
	$HUD/DeathMenu.visible = true

func _respawn_test() -> void:
	health = _max_hp()
	mana   = max_mana
	_update_health_bar()
	_update_mana_bar()
	global_position  = GameState.test_spawn_pos
	_is_invincible   = true
	velocity         = Vector2.ZERO
	modulate         = Color(0.5, 1.0, 0.6, 0.6)
	FloatingText.spawn_str(global_position, "RESPAWN", Color(0.4, 1.0, 0.5), get_tree().current_scene)
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void:
		_is_invincible = false
		modulate = Color.WHITE)

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

func _max_hp() -> int:
	# +2 max HP per VIT point above 10 (was +1) — meaningful tank scaling
	return max_health + _equip_health_bonus + GameState.get_stat_bonus("VIT") * 2

func heal_to_full() -> void:
	health = _max_hp()
	mana = max_mana
	_update_health_bar()

func update_equip_stats() -> void:
	_equip_speed_bonus      = InventoryManager.get_stat("speed")
	_equip_fire_rate_bonus  = InventoryManager.get_stat("fire_rate_reduction")
	_equip_projectile_count = int(InventoryManager.get_stat("projectile_count"))
	_equip_wisdom_bonus     = InventoryManager.get_stat("wisdom")
	var new_bonus           := int(InventoryManager.get_stat("max_health"))

	var sb := _get_set_bonuses()
	_equip_speed_bonus      += sb.get("speed",        0.0)
	_equip_wisdom_bonus     += BASE_WISDOM * sb.get("wisdom_pct", 0.0)
	_set_def_bonus          = int(sb.get("DEF", 0))
	new_bonus               += int(sb.get("max_health", 0))
	max_mana = 100.0 + sb.get("max_mana", 0.0) + _perk_mana_bonus
	max_stamina = 100.0 + _perk_stam_bonus + float(GameState.get_stat_bonus("END")) * 4.0
	_stam_regen_bonus = InventoryManager.get_stat("stam_regen") + sb.get("stam_regen", 0.0)

	_equip_projectile_count += _perk_proj_bonus
	_equip_wisdom_bonus     += BASE_WISDOM * _perk_wisdom_bonus_p

	var delta := new_bonus - _equip_health_bonus
	_equip_health_bonus = new_bonus
	if delta > 0:
		health = mini(health + delta, _max_hp())
	else:
		health = maxi(1, mini(health, _max_hp()))
	_update_health_bar()

	_syn_pyromaniac    = InventoryManager.get_stat("syn_pyromaniac")    > 0.0
	_syn_glacial       = InventoryManager.get_stat("syn_glacial")       > 0.0
	_syn_arc_conductor = InventoryManager.get_stat("syn_arc_conductor") > 0.0
	_syn_void_lens     = InventoryManager.get_stat("syn_void_lens")     > 0.0
	_syn_assassin_mark = InventoryManager.get_stat("syn_assassin_mark") > 0.0

func _get_set_bonuses() -> Dictionary:
	var counts := {"arcane": 0, "iron": 0, "swift": 0}
	for slot in InventoryManager.equipped:
		var item: Item = InventoryManager.equipped[slot] as Item
		if item == null:
			continue
		var tag: String = item.get("set_tag") if "set_tag" in item else ""
		if tag in counts:
			counts[tag] += 1
	var bonuses := {}
	if counts["arcane"] >= 2: bonuses["max_mana"]       = 25.0
	if counts["arcane"] >= 3: bonuses["wisdom_pct"]     = 0.20
	if counts["iron"]   >= 2: bonuses["DEF"]            = 8.0
	if counts["iron"]   >= 3: bonuses["max_health"]     = 4
	if counts["swift"]  >= 2: bonuses["speed"]          = 40.0
	if counts["swift"]  >= 3: bonuses["stam_regen"] = 8.0
	return bonuses

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

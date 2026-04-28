extends CharacterBody2D

const INVENTORY_UI_SCENE := preload("res://scenes/InventoryUI.tscn")

@export var speed: float = 300.0
@export var fire_rate: float = 0.15
@export var max_health: int = 50   # base 10 VIT × +5/pt scaling — keeps HP matched to the stat curve at level 1
@export var projectile_scene: PackedScene

var health: int = 20
var _shoot_cooldown: float = 0.0
var _is_dead: bool = false
var _is_paused: bool = false
var _pause_menu: CanvasLayer = null
var _pause_autoplay_label: Label = null
# Mobile-only run-stats line shown on the pause menu (kills / gold / floor).
# Built unconditionally; visibility is gated on GameState.is_mobile so the
# desktop layout is unaffected.
var _pause_run_stats_label: Label = null

# Mobile-only "auto-engage" toggle. When true the player still moves
# manually via the touch stick, but the game picks the highest-threat
# visible enemy each frame and fires the equipped wand at it. Cleaner
# than full _autoplay because it leaves pathing / loot detours / perk
# selection alone — the human just drives the joystick.
var _mobile_auto_combat: bool = false

# Inner widths of the HP/Mana/Stam fill bars — used by the per-frame
# update methods (offset_right = offset_left + width * ratio). Defaults
# match the desktop layout; _apply_mobile_hud_scale bumps them when
# running on a phone so the bars stay readable on small screens.
var _hp_bar_inner_width: float   = 200.0
var _mana_bar_inner_width: float = 200.0
var _stam_bar_inner_width: float = 200.0
var _pause_weapons_label: Label = null
# Current sort key for the pause-menu weapon panel — "damage" / "kills" / "floors" / "type".
var _pause_weapons_sort: String = "damage"
# Settings sub-panel — overlays the main pause panel when visible.
var _settings_root: Node = null
var _pause_main_buttons: Array = []   # nodes hidden when settings is open
var _buff_timer: float = 0.0
var _speed_multiplier: float = 1.0
var _fire_rate_multiplier: float = 1.0

# Equipment stat bonuses (applied by InventoryManager)
var _equip_speed_bonus: float = 0.0
var _equip_health_bonus: int = 0
# True once update_equip_stats has run for the first time. The first call
# happens during _ready after a portal reload — at that point _equip_health_bonus
# starts at 0 but the player's saved health already accounts for whatever
# +max_health gear was equipped, so the usual "delta > 0 → heal" path would
# pump health up by the full bonus on every portal (e.g. Shroud of the Undying
# kept resetting HP back to 1000). Skipped on the first call, applied normally
# afterward when the player actually equips/removes gear during play.
var _equip_stats_initialized: bool = false
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
# Equipped-wand charge readout — visible only when a limited-use wand is
# in the slot. Sits just below the mana bar so the charge count is easy to
# spot at a glance during play instead of needing to open the inventory.
var _wand_charge_label: Label = null
# Active-debuff strip — shows tags like "SLOW · POISON · DISORIENT" in
# bright red whenever the player has at least one debuff timer running,
# hidden otherwise. Sits below the wand charge readout in the top-left.
var _debuff_label: Label = null
# Persistent panel showing the equipped wand's name and combat stats so the
# player can see at-a-glance what they're shooting without opening inventory.
var _wand_info_label: Label = null
# Difficulty readout — a horizontal slider-style bar that fills as
# GameState.difficulty climbs across portals. Visible in both regular and
# test modes so the current threat tier is always at-a-glance.
var _difficulty_bar_bg: ColorRect = null
var _difficulty_bar_fg: ColorRect = null
var _difficulty_label: Label = null

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
var _dash_timer:       float = 0.0   # > 0 while actively dashing
var _dash_dir:         Vector2 = Vector2.ZERO
var _is_invincible:    bool = false
const DASH_SPEED           := 900.0
const DASH_DURATION        := 0.18
const BASE_SHOT_MANA_COST  := 2.0   # mana cost when firing without a wand equipped
# Fire rate is DEX-driven: every wand starts from this base cooldown and DEX
# scales it down. Wand flaws (clunky / sloppy) modify on top. The wand's
# own wand_fire_rate is no longer used as the primary rate — DEX is the
# main lever now.
const BASE_FIRE_RATE_DEX   := 0.30
const BASE_FIRE_DEX_SCALE  := 0.06   # each DEX point = 6 % faster

# Computes the effective per-shot cooldown the player will actually fire at
# given a wand (or null for the basic free shot). Mirrors the math inside
# _handle_shooting so HUD / debug snapshots can display the real number
# instead of the stale wand_fire_rate value the wand itself carries.
func _effective_fire_rate(wand: Item) -> float:
	var dex := float(GameState.get_stat_bonus("DEX"))
	var rate: float = BASE_FIRE_RATE_DEX / (1.0 + maxf(0.0, dex) * BASE_FIRE_DEX_SCALE)
	if wand != null:
		if "clunky" in wand.wand_flaws:
			rate *= 2.0
		if "sloppy" in wand.wand_flaws:
			rate /= 1.5
	return maxf(0.04, (rate - _equip_fire_rate_bonus) / _fire_rate_multiplier)

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
const SPELL_COOLDOWN   := 0.0   # nova has no cooldown anymore — gated purely by mana cost
const NOVA_MANA_COST   := 100.0
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
# Brief cooldown after a successful loot pickup. Suppresses loot detours
# for ~3 s so the bot resumes toward the portal instead of immediately
# being pulled into the next nearest bag, which on packed late-game floors
# (43+ bags!) was producing visible "walking loop" behavior.
var _autoplay_post_loot_cd: float = 0.0
# Per-floor detour budget and floor-age timer — once either limit trips,
# the bot abandons loot for the rest of the floor and bee-lines for the
# portal. Without this the bot can spend 100 minutes grinding 50+ bags
# on a single floor, never progressing.
var _autoplay_floor_loot_detours: int = 0
var _autoplay_floor_age: float = 0.0
const AUTOPLAY_MAX_FLOOR_DETOURS: int = 10
const AUTOPLAY_FLOOR_AGE_LIMIT: float = 60.0
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
# Sprint mode normally ignores loot. We allow one detour per floor for a
# clearly-worth-it bag (rare+) — counter resets when scene reloads.
var _autoplay_sprint_detours_used: int = 0

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
var _aim_reticle: Label = null   # `+` glyph at cursor — non-autoplay only

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
	elif GameState.in_hub:
		# Visiting the Wizard Village — preserve current level/xp/items
		# from any in-progress dungeon run; just heal up so the hub is
		# pleasant to walk around.
		health = _max_hp()
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
	# Touch HUD — only spawned on mobile browsers (iOS/Android user-agent
	# or any web client reporting a touchscreen). Safe no-op on desktop.
	if GameState.is_mobile:
		var mobile_hud_scr: Script = load("res://scripts/MobileHUD.gd")
		if mobile_hud_scr != null:
			var hud_node: CanvasLayer = CanvasLayer.new()
			hud_node.set_script(mobile_hud_scr)
			hud_node.name = "MobileHUD"
			add_child(hud_node)
	# Mobile zoom — narrow portrait viewports get heavily downscaled by
	# stretch_aspect=expand (a 9:19 phone scales by ~0.47×, making sprites
	# half size). Compensate by zooming the camera so gameplay reads at
	# roughly the same pixel scale as on landscape. Re-applied on
	# orientation changes via the viewport's size_changed signal.
	_apply_mobile_camera_zoom()
	get_viewport().size_changed.connect(_apply_mobile_camera_zoom)
	# Bigger HP / Mana / Stam bars on mobile, and hide the per-stat panel
	# (player can still check stats via the pause-menu reference).
	if GameState.is_mobile:
		_apply_mobile_hud_scale()

	_ascii_label = $AsciiChar
	_ascii_label.text = WIZARD_F0
	var _mono := MonoFont.get_font()
	_ascii_label.add_theme_font_override("font", _mono)
	_ascii_label.add_theme_constant_override("line_separation", -6)
	_ascii_label.add_theme_constant_override("outline_size", 3)
	_ascii_label.add_theme_color_override("font_outline_color", Color(0.55, 0.20, 1.0, 0.85))
	z_index = 10
	var _aura := ColorRect.new()
	_aura.size     = Vector2(32.0, 38.0)
	_aura.color    = Color(0.55, 0.20, 1.0, 0.18)
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
	# Top off mana on every level entry. Each floor is a fresh start; running
	# the bot dry from the previous fight would just leave the first room
	# without firepower while regen catches up.
	mana = max_mana
	_update_mana_bar()
	# Random wand on every floor entry. Skips test mode (which hands out
	# best-gear via a separate path) and skips when the player already has
	# a wand equipped (continuing a save, or autoplay's portal-drop already
	# generated a fallback). Rarity weighted: 60 % common, 30 % rare, 10 %
	# legendary. Adds a fresh combat archetype to try each floor.
	if not GameState.test_mode:
		var has_wand: bool = InventoryManager.equipped.get("wand") != null
		if not has_wand:
			var roll := randi() % 100
			var pick_rarity: int = Item.RARITY_COMMON
			if roll < 10:
				pick_rarity = Item.RARITY_LEGENDARY
			elif roll < 40:
				pick_rarity = Item.RARITY_RARE
			var fresh_wand := ItemDB.generate_wand(pick_rarity)
			InventoryManager.equipped["wand"] = fresh_wand
			InventoryManager.inventory_changed.emit()
			update_equip_stats()
	# Reset per-floor autoplay counters — detour budget and age timer both
	# scoped to a single floor so the budget renews when the player ports.
	_autoplay_floor_loot_detours = 0
	_autoplay_floor_age = 0.0
	# Restore autoplay across portal transitions. Keep the carried-over health
	# (with the +10 portal heal already applied) — don't reset to full.
	if GameState.autoplay_active:
		_autoplay = true
		_autoplay_sprint = GameState.autoplay_sprint
		_autoplay_last_pos = global_position
		# Autoplay-only VIT subsidy. With VIT now worth +5 max HP per point,
		# +10 VIT = +50 max HP — enough cushion that the bot can survive a
		# few cheap shots while still dying to real mistakes (was +90).
		GameState.run_stat_bonuses["VIT"] = 10
		update_equip_stats()
		health = mini(health, _max_hp())
		_update_health_bar()
		# Clear any leftover hit-stop slow-motion from prior floor
		Engine.time_scale = 1.0
		_hit_stop_end_ms = 0

## Anchors a Control to the viewport's right edge so it follows the actual
## window edge when the user resizes. design_x / top_y / w / h are in the
## 1600x900 design space; the right margin is computed once and the
## control's anchors keep it pinned to the right edge afterward.
## The constant offset below shifts the entire right HUD column closer to
## the edge — used to be ~130 px of margin, now down to ~20 px so the
## panels hug the right side instead of floating in mid-screen.
const _RIGHT_HUD_TIGHTEN: float = 110.0
func _anchor_top_right(c: Control, design_x: float, top_y: float, w: float, h: float) -> void:
	var right_margin: float = 1600.0 - (design_x + w) - _RIGHT_HUD_TIGHTEN
	if right_margin < 0.0:
		right_margin = 0.0
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = -(w + right_margin)
	c.offset_right = -right_margin
	c.offset_top = top_y
	c.offset_bottom = top_y + h

## Same idea but anchors to the bottom of the viewport. design_x stays a
## left-edge x coord (no horizontal anchoring), bottom_y is how far above
## the viewport's bottom edge the control's bottom should sit.
func _anchor_bottom_left(c: Control, design_x: float, bottom_y: float, w: float, h: float) -> void:
	var bottom_margin: float = bottom_y
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_top = -(h + bottom_margin)
	c.offset_bottom = -bottom_margin
	c.offset_left = design_x
	c.offset_right = design_x + w

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

	# Aim reticle — `+` at cursor in the equipped wand's color. Updated
	# each frame in _process_aim_reticle. Hidden during autoplay so the
	# bot's targeting doesn't fight a stale cursor visual.
	_aim_reticle = Label.new()
	_aim_reticle.name = "AimReticle"
	_aim_reticle.text = "+"
	_aim_reticle.size = Vector2(18.0, 18.0)
	_aim_reticle.add_theme_font_size_override("font_size", 18)
	_aim_reticle.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 0.85))
	_aim_reticle.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_aim_reticle.add_theme_constant_override("outline_size", 2)
	_aim_reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_aim_reticle.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
	_aim_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_aim_reticle.visible = false
	hud.add_child(_aim_reticle)

	# Difficulty readout — slider-style bar between the minimap labels and
	# the stats panel. Always visible (regular + test modes) so the current
	# threat tier is on-screen at all times.
	_difficulty_bar_bg = ColorRect.new()
	_difficulty_bar_bg.name = "DifficultyBarBG"
	_difficulty_bar_bg.color = Color(0.06, 0.05, 0.10, 0.85)
	hud.add_child(_difficulty_bar_bg)
	_anchor_top_right(_difficulty_bar_bg, 1290, 180, 180, 18)
	_difficulty_bar_fg = ColorRect.new()
	_difficulty_bar_fg.name = "DifficultyBarFG"
	_difficulty_bar_fg.color = Color(0.4, 0.85, 0.4)   # recolored each frame
	hud.add_child(_difficulty_bar_fg)
	_anchor_top_right(_difficulty_bar_fg, 1291, 181, 0, 16)   # width updated each frame
	_difficulty_label = Label.new()
	_difficulty_label.name = "DifficultyLabel"
	hud.add_child(_difficulty_label)
	_anchor_top_right(_difficulty_label, 1290, 180, 180, 18)
	_difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_difficulty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_difficulty_label.add_theme_font_size_override("font_size", 11)
	_difficulty_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	_difficulty_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_difficulty_label.add_theme_constant_override("outline_size", 3)
	_difficulty_label.z_index = 2

	# Stats panel — top-right, two columns of five stats. Sits BELOW the
	# minimap labels and the difficulty bar. Height tightened to fit just
	# the 5 stat lines so the wand-info panel below can move up.
	var stats_bg := ColorRect.new()
	stats_bg.name = "StatsBG"
	stats_bg.color = Color(0.05, 0.04, 0.10, 0.55)
	hud.add_child(stats_bg)
	_anchor_top_right(stats_bg, 1290, 204, 180, 84)
	_stats_label = Label.new()
	_stats_label.name = "StatsLabel"
	hud.add_child(_stats_label)
	_anchor_top_right(_stats_label, 1296, 208, 170, 80)
	_stats_label.add_theme_font_size_override("font_size", 12)
	_stats_label.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_stats_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_stats_label.add_theme_constant_override("outline_size", 2)
	_stats_label.add_theme_constant_override("line_separation", 1)

	# Equipped wand info panel — sits below the stats panel. Lists the
	# equipped wand's name, shoot type, damage, fire rate, mana cost, and any
	# pierce/ricochet/status modifiers. Hidden when no wand is equipped.
	var wand_bg := ColorRect.new()
	wand_bg.name = "WandInfoBG"
	wand_bg.color = Color(0.06, 0.05, 0.10, 0.55)
	hud.add_child(wand_bg)
	# Pushed down to y=320 (was 296) so it sits well clear of the stats
	# panel above (which ends at y=288); the extra gap lets the rarity-
	# starred wand name breathe instead of butting against the stats text.
	_anchor_top_right(wand_bg, 1290, 320, 180, 110)
	_wand_info_label = Label.new()
	_wand_info_label.name = "WandInfoLabel"
	hud.add_child(_wand_info_label)
	_anchor_top_right(_wand_info_label, 1296, 324, 170, 106)
	_wand_info_label.add_theme_font_size_override("font_size", 11)
	_wand_info_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.65))
	_wand_info_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_wand_info_label.add_theme_constant_override("outline_size", 2)
	_wand_info_label.add_theme_constant_override("line_separation", 1)

	# Autoplay HUD strip (objective + sprint indicator) — sits below the
	# wand info panel.
	_autoplay_hud_label = Label.new()
	_autoplay_hud_label.name = "AutoplayLabel"
	_autoplay_hud_label.add_theme_font_size_override("font_size", 13)
	_autoplay_hud_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.3))
	_autoplay_hud_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_autoplay_hud_label.add_theme_constant_override("outline_size", 2)
	_autoplay_hud_label.visible = false
	hud.add_child(_autoplay_hud_label)
	_anchor_top_right(_autoplay_hud_label, 1290, 438, 180, 38)

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
	marker_ring.default_color = Color(0.75, 0.45, 1.0, 0.85)
	var segs := 12
	for i in segs + 1:
		var ang := (TAU / float(segs)) * float(i)
		marker_ring.add_point(Vector2(cos(ang), sin(ang)) * 18.0)
	_autoplay_target_marker.add_child(marker_ring)
	_autoplay_target_marker.visible = false
	get_tree().current_scene.add_child(_autoplay_target_marker)

	# XP bar background — anchored to the bottom-center of the viewport so
	# it tracks the bottom edge as the browser window resizes (stretch mode
	# is canvas_items + aspect expand, so the visible area can grow taller
	# than the 900px design height).
	var xp_bg := ColorRect.new()
	xp_bg.name = "XPBarBG"
	xp_bg.color = Color(0.1, 0.05, 0.2)
	xp_bg.anchor_left = 0.5
	xp_bg.anchor_right = 0.5
	xp_bg.anchor_top = 1.0
	xp_bg.anchor_bottom = 1.0
	xp_bg.offset_left = -200.0
	xp_bg.offset_right = 200.0
	xp_bg.offset_top = -22.0
	xp_bg.offset_bottom = -8.0
	hud.add_child(xp_bg)

	# XP bar foreground — same anchors as the BG; offset_right is updated
	# each frame in _update_xp_bar() to grow the bar from offset_left.
	_xp_bar_fg = ColorRect.new()
	_xp_bar_fg.name = "XPBarFG"
	_xp_bar_fg.color = Color(0.5, 0.1, 1.0)
	_xp_bar_fg.anchor_left = 0.5
	_xp_bar_fg.anchor_right = 0.5
	_xp_bar_fg.anchor_top = 1.0
	_xp_bar_fg.anchor_bottom = 1.0
	_xp_bar_fg.offset_left = -200.0
	_xp_bar_fg.offset_right = -200.0  # 0 width until first _update_xp_bar
	_xp_bar_fg.offset_top = -22.0
	_xp_bar_fg.offset_bottom = -8.0
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

	# Wand charge readout — sits below the ability list (Nova/Shield/etc) so
	# it isn't covered by the stamina bar or ability labels at the top of the
	# HUD. Only visible when a limited-use wand is equipped.
	_wand_charge_label = Label.new()
	_wand_charge_label.name = "WandChargeLabel"
	_wand_charge_label.position = Vector2(10, 124)
	_wand_charge_label.size = Vector2(202, 20)
	_wand_charge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wand_charge_label.add_theme_font_size_override("font_size", 14)
	_wand_charge_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
	_wand_charge_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_wand_charge_label.add_theme_constant_override("outline_size", 3)
	_wand_charge_label.visible = false
	hud.add_child(_wand_charge_label)

	# Debuff strip — visible only when at least one player-side timer is
	# running (slow / poison / disorient). Bright red so it pops against
	# the gameplay area; sits just below the wand charge readout.
	_debuff_label = Label.new()
	_debuff_label.name = "DebuffLabel"
	_debuff_label.position = Vector2(10, 148)
	_debuff_label.size = Vector2(202, 20)
	_debuff_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debuff_label.add_theme_font_size_override("font_size", 13)
	_debuff_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	_debuff_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0))
	_debuff_label.add_theme_constant_override("outline_size", 3)
	_debuff_label.visible = false
	hud.add_child(_debuff_label)

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

	# Level label — just left of the XP bar, bottom-anchored so it tracks
	# the XP bar when the viewport resizes.
	_level_label = Label.new()
	_level_label.name = "LevelLabel"
	_level_label.text = "LVL 1"
	_level_label.anchor_left = 0.5
	_level_label.anchor_right = 0.5
	_level_label.anchor_top = 1.0
	_level_label.anchor_bottom = 1.0
	_level_label.offset_left = -270.0
	_level_label.offset_right = -205.0
	_level_label.offset_top = -28.0
	_level_label.offset_bottom = -8.0
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

	# Anchored to fill the entire viewport, not just the 1600x900 design rect,
	# so the dim covers the full stretched window when the browser canvas
	# extends beyond the design size (stretch aspect = expand).
	var bg := ColorRect.new()
	bg.color  = Color(0.0, 0.0, 0.0, 0.72)
	bg.anchor_right  = 1.0
	bg.anchor_bottom = 1.0
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
	stats_border.size     = Vector2(280, 580)
	_pause_menu.add_child(stats_border)
	var stats_inner := ColorRect.new()
	stats_inner.color    = Color(0.04, 0.05, 0.09, 0.97)
	stats_inner.position = Vector2(1033, 233)
	stats_inner.size     = Vector2(274, 574)
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
	stats_help.text = "INT  +1 damage / point, scales elements\nDEX  faster firing per point\nAGI  +4 move speed per point\nVIT  +5 max HP per point\nEND  +4 max stamina per point\nWIS  +2 mana/sec, +5 max mana / point\nSPR  +0.05 HP/sec per point\nDEF  +1% block per point\nLCK  +0.5% crit per point"
	stats_help.position = Vector2(1048, 282)
	stats_help.size     = Vector2(260, 280)
	stats_help.add_theme_font_size_override("font_size", 13)
	stats_help.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	stats_help.add_theme_constant_override("line_separation", 8)
	_pause_menu.add_child(stats_help)

	# Per-weapon usage panel — sits to the left of the main pause panel.
	# Lists kills, damage, and floors used for each shoot_type the player has
	# touched this run. Refreshed every time the menu opens.
	var w_border := ColorRect.new()
	w_border.color    = Color(0.35, 0.22, 0.20, 0.9)
	w_border.position = Vector2(280, 230)
	w_border.size     = Vector2(290, 380)
	_pause_menu.add_child(w_border)
	var w_inner := ColorRect.new()
	w_inner.color    = Color(0.07, 0.04, 0.04, 0.97)
	w_inner.position = Vector2(283, 233)
	w_inner.size     = Vector2(284, 374)
	_pause_menu.add_child(w_inner)
	var w_title := Label.new()
	w_title.text = "— WEAPON USE —  (click to cycle sort)"
	w_title.position = Vector2(283, 244)
	w_title.size     = Vector2(284, 24)
	w_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	w_title.add_theme_font_size_override("font_size", 12)
	w_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	_pause_menu.add_child(w_title)
	# Click anywhere on the title bar to cycle the sort key.
	var sort_btn := Button.new()
	sort_btn.flat = true
	sort_btn.position = Vector2(283, 244)
	sort_btn.size     = Vector2(284, 24)
	sort_btn.pressed.connect(_cycle_pause_weapons_sort)
	_pause_menu.add_child(sort_btn)
	_pause_weapons_label = Label.new()
	_pause_weapons_label.position = Vector2(296, 280)
	_pause_weapons_label.size     = Vector2(264, 320)
	_pause_weapons_label.add_theme_font_size_override("font_size", 12)
	_pause_weapons_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	_pause_weapons_label.add_theme_constant_override("line_separation", 4)
	# Monospace font so the kill/damage/floor columns line up
	var mono := MonoFont.get_font()
	_pause_weapons_label.add_theme_font_override("font", mono)
	_pause_menu.add_child(_pause_weapons_label)

	var title := Label.new()
	title.text     = "— PAUSED —"
	title.position = Vector2(586, 248)
	title.size     = Vector2(428, 50)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
	_pause_menu.add_child(title)

	_pause_btn("RESUME",       Vector2(640, 296), Color(0.4, 0.9, 0.5),  _resume_game,    true)
	# Autoplay toggle — label refreshes via _refresh_autoplay_pause_label()
	# whenever the pause menu opens or the toggle is pressed.
	_pause_autoplay_btn(Vector2(640, 348))
	_pause_btn("SAVE RUN",     Vector2(640, 400), Color(0.5, 0.75, 1.0), _save_run,       true)
	_pause_btn("SETTINGS",     Vector2(640, 452), Color(0.85, 0.7, 1.0), _open_settings,  true)
	_pause_btn("TITLE SCREEN", Vector2(640, 504), Color(0.7, 0.55, 1.0), _on_title,       true)
	_pause_btn("QUIT",         Vector2(640, 556), Color(0.55, 0.55, 0.6),_on_quit,        true)
	# Volume slider lives directly on the main pause panel so the player
	# doesn't need to dive into the settings sub-panel just to nudge volume.
	# Track the just-added widgets so they hide alongside the other main
	# buttons when SETTINGS opens.
	var _pre_count: int = _pause_menu.get_child_count()
	_add_volume_slider(612, _pause_menu)
	# Mobile run-stats line — only visible on phones since the HUD's gold
	# / kills / floor readouts are hidden there. Refreshed on every
	# pause-menu open via _refresh_pause_run_stats().
	_pause_run_stats_label = Label.new()
	_pause_run_stats_label.position = Vector2(586, 656)
	_pause_run_stats_label.size = Vector2(428, 60)
	_pause_run_stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_run_stats_label.add_theme_font_size_override("font_size", 14)
	_pause_run_stats_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.95))
	_pause_run_stats_label.add_theme_constant_override("line_separation", 4)
	_pause_run_stats_label.visible = GameState.is_mobile
	_pause_menu.add_child(_pause_run_stats_label)
	_pause_main_buttons.append(_pause_run_stats_label)
	for ci in range(_pre_count, _pause_menu.get_child_count()):
		_pause_main_buttons.append(_pause_menu.get_child(ci))
	_build_settings_panel()

func _pause_autoplay_btn(pos: Vector2) -> void:
	# Custom variant of _pause_btn that retains a reference to its label
	# so the ON/OFF text can update without rebuilding the menu.
	_pause_autoplay_label = Label.new()
	_pause_autoplay_label.position = pos
	_pause_autoplay_label.size = Vector2(320, 36)
	_pause_autoplay_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_autoplay_label.add_theme_font_size_override("font_size", 20)
	_pause_menu.add_child(_pause_autoplay_label)

	var btn := Button.new()
	btn.flat = true
	btn.text = ""
	btn.position = pos - Vector2(4, 2)
	btn.size = Vector2(328, 40)
	btn.pressed.connect(func() -> void:
		_set_autoplay(not _autoplay)
		_refresh_autoplay_pause_label())
	btn.mouse_entered.connect(func() -> void:
		var col: Color = _autoplay_pause_btn_color()
		_pause_autoplay_label.add_theme_color_override("font_color", col.lightened(0.35)))
	btn.mouse_exited.connect(func() -> void:
		_pause_autoplay_label.add_theme_color_override("font_color",
			_autoplay_pause_btn_color()))
	_pause_menu.add_child(btn)
	# Hide alongside other main buttons when SETTINGS opens.
	_pause_main_buttons.append(_pause_autoplay_label)
	_pause_main_buttons.append(btn)
	_refresh_autoplay_pause_label()

func _autoplay_pause_btn_color() -> Color:
	# Green when ON (active), neutral grey when OFF.
	return Color(0.4, 0.9, 0.5) if _autoplay else Color(0.65, 0.65, 0.7)

func _refresh_autoplay_pause_label() -> void:
	if _pause_autoplay_label == null:
		return
	_pause_autoplay_label.text = "[ AUTOPLAY: %s ]" % ("ON" if _autoplay else "OFF")
	_pause_autoplay_label.add_theme_color_override("font_color",
		_autoplay_pause_btn_color())

func _refresh_pause_run_stats() -> void:
	if _pause_run_stats_label == null:
		return
	if not GameState.is_mobile:
		return   # desktop reads these on the live HUD
	const BIOMES := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]
	var biome_idx: int = clampi(GameState.biome, 0, BIOMES.size() - 1)
	var biome_name: String = BIOMES[biome_idx]
	_pause_run_stats_label.text = "Floor %d  %s\nKills %d   Gold %d   Damage %d   Diff %.2fx" % [
		GameState.portals_used + 1, biome_name,
		GameState.kills, GameState.gold,
		GameState.damage_dealt, GameState.difficulty,
	]

func _pause_btn(txt: String, pos: Vector2, col: Color, cb: Callable, is_main: bool = false) -> void:
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
	if is_main:
		_pause_main_buttons.append(lbl)
		_pause_main_buttons.append(btn)

# Builds the settings sub-panel inside the pause menu — initially hidden.
# Pressing the SETTINGS button toggles it on; BACK toggles it off.
func _build_settings_panel() -> void:
	_settings_root = Control.new()
	_settings_root.position = Vector2.ZERO
	_settings_root.size = Vector2(1600, 900)
	_settings_root.visible = false
	_settings_root.mouse_filter = Control.MOUSE_FILTER_PASS
	_pause_menu.add_child(_settings_root)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.04, 0.1, 0.97)
	bg.position = Vector2(583, 290)
	bg.size = Vector2(434, 460)
	_settings_root.add_child(bg)

	var title := Label.new()
	title.text = "— SETTINGS —"
	title.position = Vector2(586, 304)
	title.size     = Vector2(428, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	_settings_root.add_child(title)

	_add_crt_toggle(Vector2(640, 360), _settings_root)
	_add_volume_slider(420, _settings_root)
	_add_difficulty_slider(496, _settings_root)

	# BACK button
	var back_lbl := Label.new()
	back_lbl.text = "[ BACK ]"
	back_lbl.position = Vector2(640, 678)
	back_lbl.size = Vector2(320, 36)
	back_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_lbl.add_theme_font_size_override("font_size", 20)
	var back_col := Color(0.6, 0.85, 1.0)
	back_lbl.add_theme_color_override("font_color", back_col)
	_settings_root.add_child(back_lbl)
	var back_btn := Button.new()
	back_btn.flat = true
	back_btn.position = Vector2(636, 676)
	back_btn.size = Vector2(328, 40)
	back_btn.mouse_entered.connect(func() -> void:
		back_lbl.add_theme_color_override("font_color", back_col.lightened(0.35)))
	back_btn.mouse_exited.connect(func() -> void:
		back_lbl.add_theme_color_override("font_color", back_col))
	back_btn.pressed.connect(_close_settings)
	_settings_root.add_child(back_btn)

func _open_settings() -> void:
	if _settings_root == null:
		return
	_settings_root.visible = true
	for n in _pause_main_buttons:
		if is_instance_valid(n):
			(n as CanvasItem).visible = false

func _close_settings() -> void:
	if _settings_root == null:
		return
	_settings_root.visible = false
	for n in _pause_main_buttons:
		if is_instance_valid(n):
			(n as CanvasItem).visible = true

func _add_crt_toggle(pos: Vector2, parent: Node = null) -> void:
	if parent == null:
		parent = _pause_menu
	var col_on  := Color(0.55, 1.0, 0.55)
	var col_off := Color(0.45, 0.45, 0.55)
	var lbl := Label.new()
	lbl.text = "[ CRT: %s ]" % ("ON" if GameState.crt_enabled else "OFF")
	lbl.position = pos
	lbl.size = Vector2(320, 32)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", col_on if GameState.crt_enabled else col_off)
	parent.add_child(lbl)
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
	parent.add_child(btn)

func _add_volume_slider(y: float, parent: Node = null) -> void:
	if parent == null:
		parent = _pause_menu
	var col := Color(0.6, 0.85, 1.0)
	var lbl := Label.new()
	lbl.position = Vector2(640, y)
	lbl.size     = Vector2(320, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", col)
	lbl.text = "VOLUME: %d%%" % int(GameState.master_volume * 100.0)
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value    = 0.0
	slider.max_value    = 100.0
	slider.step         = 1.0
	slider.value        = GameState.master_volume * 100.0
	slider.position     = Vector2(608, y + 26)
	slider.size         = Vector2(384, 24)
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(slider)
	slider.value_changed.connect(func(v: float) -> void:
		GameState.master_volume = v / 100.0
		GameState._apply_volume()
		GameState.save_settings()
		lbl.text = "VOLUME: %d%%" % int(v))

func _add_difficulty_slider(y: float, parent: Node = null) -> void:
	if parent == null:
		parent = _pause_menu
	var col := Color(1.0, 0.72, 0.35)
	var lbl := Label.new()
	lbl.position = Vector2(640, y)
	lbl.size     = Vector2(320, 22)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", col)
	var cur_diff := GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	lbl.text = "DIFFICULTY: %.1fx" % cur_diff
	parent.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value    = 0.5
	slider.max_value    = 20.0 if GameState.test_mode else 5.0
	slider.step         = 0.1
	slider.value        = cur_diff
	slider.position     = Vector2(608, y + 26)
	slider.size         = Vector2(384, 24)
	slider.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(slider)
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
	if _is_paused:
		_refresh_weapon_stats_panel()
		_refresh_autoplay_pause_label()
		_refresh_pause_run_stats()
	else:
		# Make sure the settings sub-panel doesn't linger on next pause-open.
		_close_settings()

# Formats GameState.weapon_stats into the pause-menu label. Sorted by total
# damage so the most-used weapons appear first.
func _refresh_weapon_stats_panel() -> void:
	if _pause_weapons_label == null:
		return
	if GameState.weapon_stats.is_empty():
		_pause_weapons_label.text = "(no weapons used yet)"
		return
	var rows: Array = []
	for k in GameState.weapon_stats.keys():
		var s: Dictionary = GameState.weapon_stats[k]
		rows.append({
			"type":   String(k),
			"kills":  int(s.get("kills", 0)),
			"damage": int(s.get("damage", 0)),
			"floors": int((s.get("floors", {}) as Dictionary).size()),
		})
	var sort_key: String = _pause_weapons_sort
	if sort_key == "type":
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return String(a["type"]) < String(b["type"]))
	else:
		rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a[sort_key]) > int(b[sort_key]))
	# Header marks the active sort column with "*"
	var col_marker := func(col: String) -> String:
		return "*" if col == sort_key else " "
	var lines: Array = ["%-9s%s%4s%s%6s%s%3s" % [
			"TYPE",   col_marker.call("type"),
			"KILL",   col_marker.call("kills"),
			"DMG",    col_marker.call("damage"),
			"FL",     col_marker.call("floors"),
		]]
	for r in rows:
		var t: String = String(r["type"]).to_upper()
		if t.length() > 9:
			t = t.substr(0, 9)
		lines.append("%-9s %4d  %6d  %3d" % [t, int(r["kills"]), int(r["damage"]), int(r["floors"])])
	_pause_weapons_label.text = "\n".join(lines)

# Cycles through sort keys — called by the weapon panel header button.
func _cycle_pause_weapons_sort() -> void:
	const ORDER := ["damage", "kills", "floors", "type"]
	var idx := ORDER.find(_pause_weapons_sort)
	idx = (idx + 1) % ORDER.size()
	_pause_weapons_sort = ORDER[idx]
	_refresh_weapon_stats_panel()

func _resume_game() -> void:
	_is_paused = false
	_pause_menu.visible = false
	get_tree().paused = false

func _save_run() -> void:
	# Serialize inventory + equipment so a CONTINUE RUN actually preserves
	# wands (with their remaining charges), potion stacks, and gear. Item
	# instances are RefCounted with custom fields so they round-trip via
	# Item.to_dict / from_dict.
	var grid_dicts: Array = []
	for it in InventoryManager.grid:
		if it != null:
			grid_dicts.append((it as Item).to_dict())
		else:
			grid_dicts.append(null)
	var equip_dicts: Dictionary = {}
	for slot in InventoryManager.EQUIP_SLOTS:
		var eq: Item = InventoryManager.equipped.get(slot) as Item
		# Spelled out instead of a ternary because Dictionary vs null are
		# incompatible types and the parser flags the inline form.
		if eq != null:
			equip_dicts[slot] = eq.to_dict()
		else:
			equip_dicts[slot] = null
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
		"floor_modifiers": GameState.floor_modifiers,
		"run_stat_bonuses": GameState.run_stat_bonuses.duplicate(),
		"inventory_grid": grid_dicts,
		"equipped": equip_dicts,
	}
	var f := FileAccess.open("user://save_run.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))
	FloatingText.spawn_str(global_position, "SAVED!", Color(0.4, 1.0, 0.6), get_tree().current_scene)

func _try_load_save() -> void:
	# Village uses Player.tscn for movement/HUD too, but we don't want
	# visiting the hub to eat a saved dungeon run. The hub flips this
	# flag right before spawning the player; we honor it once and clear.
	if GameState.skip_save_load_once:
		GameState.skip_save_load_once = false
		return
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
	# Run-scoped extras added later — guard with .has() so older saves
	# without these keys still load cleanly.
	if data.has("run_stat_bonuses"):
		GameState.run_stat_bonuses = (data["run_stat_bonuses"] as Dictionary).duplicate()
	if data.has("floor_modifiers"):
		var mods_in: Array = data["floor_modifiers"]
		GameState.floor_modifiers = []
		for m in mods_in:
			GameState.floor_modifiers.append(String(m))
		GameState.floor_modifier = GameState.floor_modifiers[0] if not GameState.floor_modifiers.is_empty() else ""
	# Inventory restore — wand charges, potion stacks, equipped gear.
	if data.has("inventory_grid"):
		var grid_in: Array = data["inventory_grid"]
		for i in mini(grid_in.size(), InventoryManager.GRID_SIZE):
			var slot_data: Variant = grid_in[i]
			if slot_data is Dictionary:
				InventoryManager.grid[i] = Item.from_dict(slot_data as Dictionary)
			else:
				InventoryManager.grid[i] = null
	if data.has("equipped"):
		var eq_in: Dictionary = data["equipped"]
		for slot in InventoryManager.EQUIP_SLOTS:
			var slot_data: Variant = eq_in.get(slot)
			if slot_data is Dictionary:
				InventoryManager.equipped[slot] = Item.from_dict(slot_data as Dictionary)
			else:
				InventoryManager.equipped[slot] = null
	InventoryManager.inventory_changed.emit()
	GameState.has_saved_state = true

# ── Debug menu ─────────────────────────────────────────────────────────────────

# ── Debug snapshot logger ─────────────────────────────────────────────────────
# Press Shift+/ (?) in-game. Writes a structured snapshot of the bot's current
# state to user://autoplay_debug.log so we can review stuck/looping scenarios
# after the fact. Append-only — every press adds a new entry to the bottom.
const _DEBUG_LOG_PATH := "user://autoplay_debug.log"

func _debug_log_snapshot() -> void:
	var lines: Array[String] = []
	var now := Time.get_datetime_dict_from_system()
	lines.append("=== SNAPSHOT %02d:%02d:%02d  (frame %d) ===" % [
		int(now.get("hour", 0)), int(now.get("minute", 0)),
		int(now.get("second", 0)), Engine.get_physics_frames()])
	# Floor / world context
	var biome_names := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]
	var biome_name: String = "?"
	if GameState.biome >= 0 and GameState.biome < biome_names.size():
		biome_name = biome_names[GameState.biome]
	lines.append("Floor: %d (%s)  difficulty=%.2f" % [
		GameState.portals_used + 1, biome_name, GameState.difficulty])
	# Player physics + vitals
	lines.append("Position: (%.1f, %.1f)  velocity=(%.1f, %.1f) mag=%.1f" % [
		global_position.x, global_position.y,
		velocity.x, velocity.y, velocity.length()])
	lines.append("Last pos: (%.1f, %.1f)  Δ since last frame=%.2f" % [
		_autoplay_last_pos.x, _autoplay_last_pos.y,
		global_position.distance_to(_autoplay_last_pos)])
	lines.append("HP: %d/%d  Mana: %.0f/%.0f  Stam: %.0f/%.0f  defensive=%s" % [
		health, _max_hp(), mana, max_mana, stamina, max_stamina,
		str(_autoplay_is_defensive())])
	# Autoplay state
	lines.append("Autoplay: %s  sprint=%s  force_sprint(<25%%hp)=%s" % [
		str(_autoplay), str(_autoplay_sprint),
		str(float(health) / maxf(1.0, float(_max_hp())) < 0.25)])
	lines.append("Stuck timer: %.2fs  (wiggle@>0.20, jitter@>0.60)" % _autoplay_stuck_t)
	# Movement target
	if is_instance_valid(_autoplay_move_to):
		var mt := _autoplay_move_to as Node2D
		var mt_groups: Array = []
		for g in ["boss", "loot_bag", "portal", "enemy"]:
			if mt.is_in_group(g):
				mt_groups.append(g)
		lines.append("Move target: %s  groups=%s  pos=(%.1f, %.1f)  dist=%.1f" % [
			mt.name, str(mt_groups),
			mt.global_position.x, mt.global_position.y,
			global_position.distance_to(mt.global_position)])
	else:
		lines.append("Move target: <none>")
	# Path state
	if _autoplay_path.size() > 0:
		var world := get_tree().current_scene
		var tile := 32.0
		if world and "TILE" in world:
			tile = float(int(world.TILE))
		var half := Vector2(tile * 0.5, tile * 0.5)
		var idx := mini(_autoplay_path_idx, _autoplay_path.size() - 1)
		var next_wp: Vector2 = _autoplay_path[idx] + half
		lines.append("Path: %d waypoints, idx=%d  next_wp=(%.1f, %.1f) dist=%.1f" % [
			_autoplay_path.size(), _autoplay_path_idx,
			next_wp.x, next_wp.y, global_position.distance_to(next_wp)])
	else:
		lines.append("Path: <empty>  (A* failed or not yet computed)")
	# Direction + composite forces
	var pdir := _autoplay_path_dir() if _autoplay_path.size() > 0 else Vector2.ZERO
	var ddir := _autoplay_dodge_force()
	var pforce := _autoplay_enemy_pressure_force()
	var mdir := _autoplay_move_dir()
	lines.append("Dirs: path=(%.2f,%.2f) move=(%.2f,%.2f) dodge=(%.2f,%.2f) pressure=(%.2f,%.2f)" % [
		pdir.x, pdir.y, mdir.x, mdir.y,
		ddir.x, ddir.y, pforce.x, pforce.y])
	# Shoot target + LOS
	if is_instance_valid(_autoplay_enemy):
		var en := _autoplay_enemy as Node2D
		lines.append("Shoot target: %s  pos=(%.1f, %.1f)  dist=%.1f  los=%s" % [
			en.name, en.global_position.x, en.global_position.y,
			global_position.distance_to(en.global_position),
			str(_autoplay_los_clear(en.global_position))])
	else:
		lines.append("Shoot target: <none>")
	# Equipped wand
	var w: Item = InventoryManager.equipped.get("wand") as Item
	if w != null:
		var charges_str := "%d/%d" % [w.wand_charges, w.wand_max_charges] if w.is_limited_use() else "∞"
		lines.append("Wand: %s  type=%s  dmg=%d  rate=%.2fs (eff)  cost=%.1f  charges=%s  flaws=%s" % [
			w.display_name, w.wand_shoot_type, w.wand_damage,
			_effective_fire_rate(w), w.wand_mana_cost, charges_str,
			str(w.wand_flaws)])
	else:
		lines.append("Wand: <none>")
	# Boss + counts
	var boss_count := 0
	for b in get_tree().get_nodes_in_group("boss"):
		if is_instance_valid(b):
			boss_count += 1
	var enemy_count := 0
	var aggro_count := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		enemy_count += 1
		if "_has_aggro" in e and bool(e.get("_has_aggro")):
			aggro_count += 1
	lines.append("World: %d enemies (%d aggro), %d bosses, %d enemy projectiles, %d loot bags" % [
		enemy_count, aggro_count, boss_count,
		get_tree().get_nodes_in_group("enemy_projectile").size(),
		get_tree().get_nodes_in_group("loot_bag").size()])
	lines.append("Skipped: %d enemies, %d bags" % [
		_autoplay_skipped_enemies.size(), _autoplay_skipped_bags.size()])

	# Mode flags — important for distinguishing what the bot is allowed to do.
	lines.append("Modes: autoplay=%s mobile_auto=%s mobile_dev=%s sprint=%s defensive=%s test=%s" % [
		str(_autoplay), str(_mobile_auto_combat), str(GameState.is_mobile),
		str(_autoplay_sprint), str(_autoplay_is_defensive()), str(GameState.test_mode)])

	# Player status timers — if movement seems wrong, check these first
	# (slow, poison ticks, disorient remap of move actions).
	lines.append("Status: slow=%.2fs poison=%.2fs disorient=%.2fs invincible=%s shielding=%s" % [
		maxf(0.0, _slow_timer), maxf(0.0, _poison_timer),
		maxf(0.0, _disorient_timer),
		str(_is_invincible), str(_is_shielding)])

	# Per-frame force magnitudes — comparing kite to base move dir explains
	# why the bot held / abandoned its goal direction this frame.
	var kite_dbg: Vector2 = _autoplay_kite_force()
	var pressure_dbg: Vector2 = _autoplay_enemy_pressure_force()
	lines.append("Forces: kite=%.2f pressure=%.2f dodge=%.2f" % [
		kite_dbg.length(), pressure_dbg.length(), _autoplay_dodge_force().length()])

	# Top 5 nearest enemies — distance, HP fraction, aggro, status flags.
	# Lets us see at a glance whether the bot's shoot target makes sense
	# vs. who's actually pressuring it. Frozen / enflamed flags surface
	# enemies that are crowd-controlled (likely safe to ignore).
	var ranked: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var ne := e as Node2D
		ranked.append({"node": ne,
			"d": global_position.distance_to(ne.global_position)})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["d"] < b["d"])
	var roster_count: int = mini(5, ranked.size())
	lines.append("Nearest %d enemies:" % roster_count)
	for i in roster_count:
		var entry: Dictionary = ranked[i]
		var ne_r: Node2D = entry["node"]
		var hp_str := "?"
		if "health" in ne_r and "max_health" in ne_r:
			var max_hp_e := maxf(1.0, float(ne_r.get("max_health")))
			hp_str = "%d/%d (%.0f%%)" % [int(ne_r.get("health")),
				int(ne_r.get("max_health")),
				float(ne_r.get("health")) / max_hp_e * 100.0]
		var aggro_str := "?"
		if "_has_aggro" in ne_r:
			aggro_str = "yes" if bool(ne_r.get("_has_aggro")) else "no"
		var flags: Array = []
		if "_frozen"     in ne_r and bool(ne_r.get("_frozen")):     flags.append("frozen")
		if "_chill_stacks" in ne_r and int(ne_r.get("_chill_stacks")) > 0:
			flags.append("chill" + str(ne_r.get("_chill_stacks")))
		if "_enflamed"   in ne_r and bool(ne_r.get("_enflamed")):   flags.append("enflamed")
		if "_burn_stacks" in ne_r and int(ne_r.get("_burn_stacks")) > 0:
			flags.append("burn" + str(ne_r.get("_burn_stacks")))
		if "_stun_timer" in ne_r and float(ne_r.get("_stun_timer")) > 0.0:
			flags.append("stunned")
		if "_poisoned"   in ne_r and bool(ne_r.get("_poisoned")):   flags.append("poisoned")
		var script_path := "?"
		var s_ref: Script = ne_r.get_script() as Script
		if s_ref != null:
			script_path = s_ref.resource_path.get_file()
		var los_str: String = "yes" if _autoplay_los_clear(ne_r.global_position) else "no"
		lines.append("  %d. %-22s d=%5.0f hp=%-14s aggro=%-3s los=%-3s flags=%s" % [
			i + 1, script_path, entry["d"], hp_str, aggro_str, los_str,
			"-" if flags.is_empty() else ",".join(PackedStringArray(flags))])

	# Loot/portal-loop diagnosis — surface the gates that could cause
	# oscillation between bag detours and the portal.
	lines.append("Detours: post_loot_cd=%.2fs floor_loot_detours=%d/%d floor_age=%.1fs/%ds" % [
		maxf(0.0, _autoplay_post_loot_cd), _autoplay_floor_loot_detours,
		AUTOPLAY_MAX_FLOOR_DETOURS, _autoplay_floor_age,
		AUTOPLAY_FLOOR_AGE_LIMIT])
	lines.append("=================================================")
	lines.append("")
	# Append to file
	var f := FileAccess.open(_DEBUG_LOG_PATH, FileAccess.READ_WRITE)
	if f == null:
		f = FileAccess.open(_DEBUG_LOG_PATH, FileAccess.WRITE)
	if f == null:
		FloatingText.spawn_str(global_position, "LOG FAILED",
			Color(1.0, 0.3, 0.3), get_tree().current_scene)
		return
	f.seek_end()
	for line in lines:
		f.store_line(line)
	f.close()
	# On-screen confirmation
	FloatingText.spawn_str(global_position + Vector2(0.0, -40.0),
		"SNAPSHOT LOGGED",
		Color(0.45, 1.0, 0.6),
		get_tree().current_scene)
	print("[debug] Snapshot appended to ", _DEBUG_LOG_PATH,
		" (resolves to ", ProjectSettings.globalize_path(_DEBUG_LOG_PATH), ")")

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
			s += candidate.stat_bonuses.get("VIT",                 0.0) * 25.0
			s += candidate.stat_bonuses.get("speed",               0.0) * 0.4
			s += candidate.stat_bonuses.get("fire_rate_reduction",  0.0) * 120.0
			s += candidate.stat_bonuses.get("DEF",                 0.0) * 0.6
			s += candidate.stat_bonuses.get("projectile_count",    0.0) * 25.0
			s += candidate.stat_bonuses.get("wisdom",              0.0) * 2.5
			if s > best_score:
				best_score = s
				best = candidate
		if best != null:
			# Best gear is a debug power-up — stamp +50 VIT onto every
			# equipped item so the player has a clearly oversized HP pool
			# (each VIT point = +5 max HP, so 6 slots × 50 = 1500 max HP
			# bonus on top of base + each item's rolled stats).
			best.stat_bonuses["VIT"] = 50.0
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
	_mana_bar_fg.size.x = _mana_bar_inner_width * ratio
	if _mana_label:
		_mana_label.text = "%d / %d MP" % [int(mana), int(max_mana)]
	# Active-debuff strip — joins all currently-running player debuff
	# timers into one short tag list. Hidden when no debuff is active so
	# the HUD stays clean during normal play.
	if _debuff_label:
		var dtags: Array = []
		if _slow_timer > 0.0:
			dtags.append("SLOW %.1fs" % _slow_timer)
		if _poison_timer > 0.0:
			dtags.append("POISON %.1fs" % _poison_timer)
		if _disorient_timer > 0.0:
			dtags.append("DISORIENT %.1fs" % _disorient_timer)
		if dtags.is_empty():
			_debuff_label.visible = false
		else:
			_debuff_label.text = " · ".join(dtags)
			_debuff_label.visible = true
	# Equipped-wand readouts (charge counter + info panel). Both are driven
	# from the same wand reference so they stay in sync.
	var w: Item = null
	if InventoryManager:
		w = InventoryManager.equipped.get("wand") as Item
	if _wand_charge_label:
		if w != null and w.type == Item.Type.WAND and w.is_limited_use():
			_wand_charge_label.text = "⚡ %d / %d charges" % [w.wand_charges, w.wand_max_charges]
			var ratio_c: float = float(w.wand_charges) / float(maxi(1, w.wand_max_charges))
			# Yellow when full → orange → red as charges drop.
			_wand_charge_label.add_theme_color_override("font_color",
				Color(1.0, lerpf(0.25, 0.85, ratio_c), lerpf(0.05, 0.25, ratio_c)))
			_wand_charge_label.visible = true
		else:
			_wand_charge_label.visible = false
	if _wand_info_label:
		if w != null and w.type == Item.Type.WAND:
			var lines: Array[String] = []
			# Rarity stars in front of the name so legendaries / rares pop.
			var prefix := ""
			match w.rarity:
				Item.RARITY_LEGENDARY: prefix = "★★ "
				Item.RARITY_RARE:      prefix = "★ "
			lines.append(prefix + w.display_name)
			lines.append(w.wand_shoot_type.to_upper())
			lines.append("DMG %d   FR %.2fs" % [w.wand_damage, _effective_fire_rate(w)])
			lines.append("MP %.1f / shot" % w.wand_mana_cost)
			var extras: Array = []
			if w.wand_pierce > 0:
				extras.append("Pierce %d" % w.wand_pierce)
			if w.wand_ricochet > 0:
				extras.append("Bounce %d" % w.wand_ricochet)
			if w.wand_shoot_type in ["fire", "freeze", "shock"] and w.wand_status_stacks > 1:
				extras.append("Stacks %d" % w.wand_status_stacks)
			if not extras.is_empty():
				lines.append(", ".join(extras))
			if w.is_limited_use():
				lines.append("Charges: %d / %d" % [w.wand_charges, w.wand_max_charges])
			if not (w.wand_flaws as Array).is_empty():
				lines.append("FLAW: " + ", ".join(w.wand_flaws))
			_wand_info_label.text = "\n".join(lines)
			_wand_info_label.add_theme_color_override("font_color",
				w.color.lerp(Color(1.0, 1.0, 1.0), 0.35))
			_wand_info_label.visible = true
		else:
			_wand_info_label.text = "(no wand equipped)"
			_wand_info_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
			_wand_info_label.visible = true
	# Difficulty bar — uses the active difficulty (test mode has its own).
	# Visual fill maps the *current tier* to 0..100 % so the bar always
	# shows progress within whatever tier we're in (1-2, 2-3, 3-4, 4-5, 5+).
	# Tier label appears alongside the multiplier so deep floors aren't
	# stuck reading "5.00x" indefinitely.
	if _difficulty_bar_fg and _difficulty_label:
		var diff_val: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
		var tier: int = 1
		var tier_lo: float = 1.0
		var tier_hi: float = 2.0
		if diff_val >= 5.0:
			tier = 5; tier_lo = 5.0; tier_hi = 7.0   # T5 spans wider since +2/portal
		elif diff_val >= 4.0:
			tier = 4; tier_lo = 4.0; tier_hi = 5.0
		elif diff_val >= 3.0:
			tier = 3; tier_lo = 3.0; tier_hi = 4.0
		elif diff_val >= 2.0:
			tier = 2; tier_lo = 2.0; tier_hi = 3.0
		var ratio_d: float = clampf((diff_val - tier_lo) / (tier_hi - tier_lo), 0.0, 1.0)
		_difficulty_bar_fg.size.x = 178.0 * ratio_d
		# Tier-based color: green T1, yellow-green T2, yellow T3, orange T4, red T5+.
		var tier_colors: Array = [
			Color(0.40, 0.85, 0.40),
			Color(0.75, 0.90, 0.30),
			Color(0.95, 0.85, 0.20),
			Color(1.00, 0.55, 0.15),
			Color(0.95, 0.25, 0.20),
		]
		_difficulty_bar_fg.color = tier_colors[mini(tier - 1, 4)] as Color
		_difficulty_label.text = "T%d  DIFFICULTY  %.2fx" % [tier, diff_val]

func _update_stam_bar() -> void:
	if _stam_bar_fg == null:
		return
	var ratio := clampf(stamina / max_stamina, 0.0, 1.0)
	_stam_bar_fg.size.x = _stam_bar_inner_width * ratio

func _cast_nova_spell() -> void:
	if mana < NOVA_MANA_COST:
		FloatingText.spawn_str(global_position, "Need %dMP" % int(NOVA_MANA_COST),
			Color(0.8, 0.3, 0.8), get_tree().current_scene)
		return
	mana -= NOVA_MANA_COST
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

# Bumps Camera2D.zoom proportionally on mobile when the viewport is
# narrower than the 1600x900 design rect. With stretch_aspect=expand,
# narrow portrait phones uniformly downscale 2D content (~0.47x on a
# 9:19 phone) which makes sprites unreadable. Zooming the camera in by
# the inverse of the aspect ratio (clamped) restores readable scale at
# the cost of seeing less world horizontally — which is the right
# trade-off for one-handed phone play. Desktop and landscape mobile
# fall through with zoom 1.0.
func _apply_mobile_camera_zoom() -> void:
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	if not GameState.is_mobile:
		cam.zoom = Vector2.ONE
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var actual_aspect: float = vp.x / vp.y
	const DESIGN_ASPECT: float = 1600.0 / 900.0  # ≈ 1.78
	if actual_aspect >= DESIGN_ASPECT:
		cam.zoom = Vector2.ONE   # landscape phone or wide enough — no boost needed
		return
	# z = how much narrower than design we are. ~1.8 on portrait, capped so
	# the player still has enough horizon to react to incoming threats.
	var z: float = clampf(DESIGN_ASPECT / actual_aspect, 1.0, 2.0)
	cam.zoom = Vector2(z, z)

# Mobile HUD scale — bumps the HP / Mana / Stam bars to ~1.6× their
# desktop size so they read on a small phone screen, hides the per-stat
# panel (INT/DEX/VIT/etc.), and shifts the rows below the bars down to
# accommodate the new heights. The stat panel can still be reviewed
# through the pause menu's STAT REFERENCE block.
func _apply_mobile_hud_scale() -> void:
	# Hide the live-stats readout in the top-right.
	var stats_bg := get_node_or_null("HUD/StatsBG") as CanvasItem
	if stats_bg != null:
		stats_bg.visible = false
	if _stats_label != null:
		_stats_label.visible = false

	# Hide the kills / gold / floor (difficulty-bar) readouts. Same info
	# is rendered on the pause-menu run-stats panel for mobile so the
	# player can still check it without burning HUD real estate during
	# combat.
	var to_hide := [
		"HUD/KillsLabel", "HUD/GoldLabel",
		"HUD/DifficultyLabel", "HUD/DifficultyBarBG", "HUD/DifficultyBarFG",
	]
	for path in to_hide:
		var n := get_node_or_null(path) as CanvasItem
		if n != null:
			n.visible = false

	# Make the wand-info square act as a pause-button on mobile — the
	# desktop ESC key isn't reachable, the dedicated [II] mobile button
	# is fine but easy to miss, and the wand panel is a big obvious
	# tap target that doesn't carry critical real-time info.
	var wand_bg := get_node_or_null("HUD/WandInfoBG") as Control
	if wand_bg != null:
		var btn := Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.anchor_left   = wand_bg.anchor_left
		btn.anchor_top    = wand_bg.anchor_top
		btn.anchor_right  = wand_bg.anchor_right
		btn.anchor_bottom = wand_bg.anchor_bottom
		btn.offset_left   = wand_bg.offset_left
		btn.offset_top    = wand_bg.offset_top
		btn.offset_right  = wand_bg.offset_right
		btn.offset_bottom = wand_bg.offset_bottom
		btn.pressed.connect(_toggle_pause)
		wand_bg.get_parent().add_child(btn)

	# HP bar — outer 320×32 at (10,10), inner 318×30 at (11,11).
	var hp_bg := get_node_or_null("HUD/HealthBarBG") as Control
	var hp_fg := get_node_or_null("HUD/HealthBarFG") as Control
	var hp_lb := get_node_or_null("HUD/HPLabel") as Label
	if hp_bg != null:
		hp_bg.offset_right  = 330.0
		hp_bg.offset_bottom = 42.0
	if hp_fg != null:
		hp_fg.offset_right  = 329.0   # initial; per-frame update overrides
		hp_fg.offset_bottom = 41.0
	if hp_lb != null:
		hp_lb.offset_right  = 330.0
		hp_lb.offset_bottom = 42.0
		hp_lb.add_theme_font_size_override("font_size", 16)
	_hp_bar_inner_width = 318.0

	# Mana bar — moved down to y=50, sized 322×20.
	var mana_bg := get_node_or_null("HUD/ManaBarBG") as Control
	if mana_bg != null:
		mana_bg.position = Vector2(10, 50)
		mana_bg.size     = Vector2(322, 20)
	if _mana_bar_fg != null:
		_mana_bar_fg.position = Vector2(11, 51)
		_mana_bar_fg.size     = Vector2(0, 18)
	if _mana_label != null:
		_mana_label.position = Vector2(10, 51)
		_mana_label.size     = Vector2(322, 18)
		_mana_label.add_theme_font_size_override("font_size", 12)
	_mana_bar_inner_width = 320.0

	# Stam bar — moved down to y=78, sized 322×14.
	var stam_bg := get_node_or_null("HUD/StamBarBG") as Control
	if stam_bg != null:
		stam_bg.position = Vector2(10, 78)
		stam_bg.size     = Vector2(322, 14)
	if _stam_bar_fg != null:
		_stam_bar_fg.position = Vector2(11, 79)
		_stam_bar_fg.size     = Vector2(0, 12)
	_stam_bar_inner_width = 320.0

	# Dash hint shifts down and grows a bit.
	var dash_lbl := get_node_or_null("HUD/DashLabel") as Label
	if dash_lbl != null:
		dash_lbl.position = Vector2(10, 96)
		dash_lbl.size     = Vector2(220, 22)
		dash_lbl.add_theme_font_size_override("font_size", 13)

	# Bigger / re-positioned death-menu buttons + title so tap targets
	# are reachable and readable on a phone.
	var dm := get_node_or_null("HUD/DeathMenu") as Control
	if dm != null:
		var dm_title := dm.get_node_or_null("Title") as Label
		if dm_title != null:
			dm_title.position = Vector2(540, 220)
			dm_title.size     = Vector2(520, 130)
			dm_title.add_theme_font_size_override("font_size", 84)
		# Retry / Quit / TitleScreen — wider rows, bigger font, vertically
		# stacked instead of horizontal so they fit a portrait viewport.
		var btn_specs := [
			["RetryButton", 360.0],
			["QuitButton",  450.0],
			["TitleButton", 540.0],
		]
		for spec: Array in btn_specs:
			var btn := dm.get_node_or_null(spec[0]) as Button
			if btn == null:
				continue
			btn.position = Vector2(560, spec[1])
			btn.size     = Vector2(480, 76)
			btn.add_theme_font_size_override("font_size", 28)

const _SHAKE_INTENSITY_CAP: float = 22.0
func camera_shake(intensity: float, duration: float) -> void:
	var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D
	if cam == null:
		return
	# Hard cap on peak amplitude so back-to-back hits don't compound into a
	# screen-flinging jitter — better feel than unbounded stacking.
	intensity = minf(intensity, _SHAKE_INTENSITY_CAP)
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
			_apply_perk(_autoplay_pick_perk())
			return
	if _is_paused:
		return
	if _hit_stop_end_ms > 0 and Time.get_ticks_msec() >= _hit_stop_end_ms:
		Engine.time_scale = 1.0
		_hit_stop_end_ms = 0
	$HUD/KillsLabel.text = "Kills: " + str(GameState.kills)
	if _gold_label:
		_gold_label.text = "G: " + str(GameState.gold)
	# Aim reticle — position at cursor, recolor by equipped wand. Hidden
	# during autoplay so the bot's targeting isn't visually doubled by
	# a stale cursor.
	if _aim_reticle:
		if _autoplay or _is_dead:
			_aim_reticle.visible = false
		else:
			_aim_reticle.visible = true
			var mp: Vector2 = get_viewport().get_mouse_position()
			_aim_reticle.position = mp - Vector2(9.0, 9.0)
			var wand: Item = InventoryManager.equipped.get("wand") as Item
			var col := Color(1.0, 0.95, 0.55, 0.85) if wand == null \
				else Color(wand.color.r, wand.color.g, wand.color.b, 0.85)
			_aim_reticle.add_theme_color_override("font_color", col)
	if _level_label:
		_level_label.text = "LVL " + str(GameState.level)
	if _stats_label:
		# STR was removed; INT moved into the top-left slot it used to fill.
		_stats_label.text = "INT %d  DEX %d\nWIS %d  AGI %d\nSPR %d  VIT %d\nDEF %d  END %d\nLCK %d" % [
			GameState.get_stat("INT"), GameState.get_stat("DEX"),
			GameState.get_stat("WIS"), GameState.get_stat("AGI"),
			GameState.get_stat("SPR"), GameState.get_stat("VIT"),
			GameState.get_stat("DEF"), GameState.get_stat("END"),
			GameState.get_stat("LCK"),
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
		KEY_SLASH:         # ? (Shift+/)  →  debug snapshot
			# Captures autoplay/movement/path state to user://autoplay_debug.log
			# so we can pinpoint stuck-but-trying scenarios after the fact.
			if event.shift_pressed:
				_debug_log_snapshot()
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
				_set_autoplay(not _autoplay)
				get_viewport().set_input_as_handled()
		KEY_MINUS:
			# Sprint mode — autoplay ignores loot, B-lines through floors
			if _autoplay:
				_autoplay_sprint = not _autoplay_sprint
				GameState.autoplay_sprint = _autoplay_sprint
				GameState.save_settings()
				if SoundManager:
					SoundManager.play("whoosh",
						1.20 if _autoplay_sprint else 0.85)
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
	var wisdom := BASE_WISDOM + _equip_wisdom_bonus + float(GameState.get_stat_bonus("WIS")) * 2.0
	# ARCANE floor scales with difficulty — 2× at low diff, up to 3× at high.
	var mana_mult: float = 1.0
	if GameState.has_floor_modifier("arcane"):
		mana_mult = 2.0 + 0.20 * maxf(0.0, GameState.difficulty - 1.0)
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
			# 1% of max HP per tick, ticking once per second. Combined with
			# the poison cloud's 10 s status duration, that comes out to
			# the spec: 10 % of max HP over 10 s. Min 1 damage so very-low
			# max-HP players still feel it instead of rounding to zero.
			_poison_tick = 1.0
			var poison_dmg: int = maxi(1, int(round(float(_max_hp()) * 0.01)))
			health = max(0, health - poison_dmg)
			FloatingText.spawn(global_position, poison_dmg, false, get_tree().current_scene)
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
	# Bot lifts off automatically when about to step on a trap or hazard.
	# Player input still wins if pressed.
	var want_lev: bool = Input.is_action_pressed("levitate")
	if not want_lev and _autoplay:
		want_lev = _autoplay_should_levitate()
	if want_lev and mana >= cost:
		_is_levitating = true
		mana -= cost
	else:
		_is_levitating = false

# Returns true if the bot is on / about to step on a trap or hazard tile and
# has enough mana to sustain a brief levitation. Lookahead uses current
# velocity so the lift triggers slightly before the actual collision.
func _autoplay_should_levitate() -> bool:
	# Reserve ~0.3 s of mana so we don't drop mid-trap and immediately eat it.
	if mana < LEVITATE_MANA_COST * 0.30:
		return false
	var probe := global_position + velocity * 0.18
	var radius_sq := 36.0 * 36.0
	for grp in ["trap", "hazard"]:
		for n in get_tree().get_nodes_in_group(grp):
			if not is_instance_valid(n) or not (n is Node2D):
				continue
			var p: Vector2 = (n as Node2D).global_position
			if global_position.distance_squared_to(p) < radius_sq:
				return true
			if probe.distance_squared_to(p) < radius_sq:
				return true
	return false

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
	# Difficulty stretches enemy-applied debuff durations: +20 % per +1.0
	# difficulty above the first floor, capped at +120 %. Compounds with
	# the +40 % damage taken scaling — debuffs become real threats at high
	# tiers instead of mostly cosmetic.
	var d: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	var dur_mult: float = 1.0 + clampf(maxf(0.0, d - 1.0) * 0.20, 0.0, 1.2)
	var eff_dur: float = duration * dur_mult
	match effect:
		"slow":
			_slow_timer = maxf(_slow_timer, eff_dur)
			FloatingText.spawn_str(global_position, "SLOW", Color(0.4, 0.6, 1.0), get_tree().current_scene)
		"poison":
			if _poison_timer <= 0.0:
				_poison_tick = 1.0   # first tick in 1 s — 1 %/tick × 10 s = 10 %
			_poison_timer = maxf(_poison_timer, eff_dur)
		"disorient":
			_disorient_timer = maxf(_disorient_timer, eff_dur)
			FloatingText.spawn_str(global_position, "DISORIENTED", Color(0.85, 0.5, 1.0), get_tree().current_scene)

func _get_aim_pos() -> Vector2:
	if (_autoplay or _mobile_auto_combat) and is_instance_valid(_autoplay_enemy):
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
		# Fire bolts arc back and forth via a sine wave (≈ ±22°), so the
		# linear velocity-lead used for straight shots actually pushes the
		# zigzag *away* from the target on every other half-cycle. Skip the
		# lead for fire wands and aim directly at the enemy — the arc
		# averages around that line so most of the wave clips the target.
		# Beam wands are also lead-free: the raycast is instantaneous, so
		# any lead becomes pure miss (visible especially against bosses
		# like the Architect that are constantly drifting).
		if w != null and w.wand_shoot_type in ["fire", "beam"]:
			flight_time = 0.0
		var aim_target: Vector2 = enemy_pos + enemy_vel * flight_time
		# `_fire` already skips the backwards-flaw flip for autoplay, so the
		# returned aim point should be the *real* enemy position. The old
		# pre-mirror (aim' = 2P - aim) ran on top of that skip and double-
		# compensated, sending bot shots 180° away from the target. It also
		# poisoned _autoplay_los_clear since LOS got checked toward the
		# mirrored point instead of the enemy. Leave aim_target alone here.
		return aim_target
	return get_global_mouse_position()

func _wants_shoot() -> bool:
	if _autoplay or _mobile_auto_combat:
		# Always rescan for a visible enemy — the bot should fire on ANY
		# target the moment one shows up (movement to portal, mid-corridor,
		# whatever). Mobile auto-combat picks strictly nearest in LOS so
		# the player's manual movement determines target priority; full
		# autoplay still uses threat-weighted scoring (boss > low-HP > etc).
		var fresh: Node2D = (_find_nearest_visible_enemy()
			if _mobile_auto_combat and not _autoplay
			else _autoplay_find_visible_enemy())
		if is_instance_valid(fresh):
			_autoplay_enemy = fresh
		elif not is_instance_valid(_autoplay_enemy) \
				or not _autoplay_los_clear((_autoplay_enemy as Node2D).global_position):
			return false
		if not (is_instance_valid(_autoplay_enemy) \
				and _autoplay_los_clear((_autoplay_enemy as Node2D).global_position)):
			return false
		# Mana gate — don't ask _handle_shooting to fire a wand we can't pay
		# for. Lets the bot save its remaining mana for spells / shield rather
		# than burning per-frame attempts on an unaffordable wand.
		var w: Item = InventoryManager.equipped.get("wand") as Item
		var cost: float = BASE_SHOT_MANA_COST
		if w != null:
			cost = w.wand_mana_cost
			if "mana_guzzle" in w.wand_flaws:
				cost *= 2.0
		cost *= _difficulty_mana_multiplier()
		return mana >= cost
	return Input.is_action_pressed("shoot")

# True if the centre ray from player → target_pos is unobstructed (no
# StaticBody2D wall in the way). The bot fires along this exact line, so
# any wall on the centreline means the projectile would smack into it —
# regardless of clearance to either side. The previous "any of 3 parallel
# rays clears" version was too lenient: when the centre hit a wall but
# Mobile-only auto-engage toggle. Driven by the AUTO button in MobileHUD.
# Selects + aims + fires at visible enemies; movement remains under the
# joystick's control. Resets the cached enemy when turning off so the
# next engage starts from a fresh scan.
func set_mobile_auto_combat(state: bool) -> void:
	_mobile_auto_combat = state
	if not state and not _autoplay:
		_autoplay_enemy = null
	FloatingText.spawn_str(global_position,
		"AUTO: " + ("ON" if state else "OFF"),
		Color(1.0, 0.95, 0.3), get_tree().current_scene)

# Toggles autoplay on/off and resets all the per-target/path state so the
# bot starts fresh. Used by KEY_0 input, the pause-menu toggle button, and
# (potentially) external callers like the mobile HUD.
func _set_autoplay(state: bool) -> void:
	_autoplay = state
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
		# +10 VIT subsidy for the bot — with VIT @ +5 max HP/point that's a
		# +50 HP cushion, enough to absorb a few unlucky hits without the
		# bot becoming nearly invincible.
		GameState.run_stat_bonuses["VIT"] = 10
		update_equip_stats()
		heal_to_full()
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

# a 3-px side ray didn't, the bot would happily fire into the wall.
func _autoplay_los_clear(target_pos: Vector2) -> bool:
	var space := get_world_2d().direct_space_state
	var to := target_pos - global_position
	if to.length() < 0.001:
		return true
	var query := PhysicsRayQueryParameters2D.create(global_position, target_pos)
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	# Empty hit OR first thing the ray hits is non-wall (an enemy, an item,
	# etc.) → there's a clear shot path to the target.
	return hit.is_empty() or not (hit.get("collider") is StaticBody2D)

# Strict "closest enemy with line-of-sight" picker. Used by mobile
# auto-combat where the player drives movement and just wants the wand
# pointed at whatever is nearest and shootable. Bosses/elites/etc. get
# no priority bump — proximity wins. Walls block, walls-only block; if
# the ray hits an enemy first that's a clear target.
func _find_nearest_visible_enemy() -> Node2D:
	var best: Node2D = null
	var best_d_sq: float = INF
	# Same engagement cap as full autoplay — keeps the per-frame raycast
	# cost bounded in packed rooms. Bosses are exempt because boss-arena
	# fights routinely happen across distances larger than ENGAGE_R.
	const ENGAGE_R_SQ := 700.0 * 700.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var ne := e as Node2D
		var is_boss := ne.is_in_group("boss")
		var d_sq: float = global_position.distance_squared_to(ne.global_position)
		if not is_boss and d_sq > ENGAGE_R_SQ:
			continue
		if d_sq >= best_d_sq:
			continue   # already have a closer candidate, skip the LOS raycast
		if not _autoplay_los_clear(ne.global_position):
			continue
		best_d_sq = d_sq
		best = ne
	return best

func _autoplay_find_visible_enemy() -> Node2D:
	# Threat-based scoring: prefer bosses → low-HP "easy kill" finishes →
	# closer enemies. Picks the highest-threat visible target.
	var best: Node2D = null
	var best_score: float = -INF
	# Cap engagement range so we don't raycast every enemy in a packed room.
	# Bosses are always considered regardless of range so the bot keeps firing
	# during boss fights even from across the arena.
	const ENGAGE_R_SQ := 700.0 * 700.0
	# Anything within DANGER_R of the player is a "you're being rushed"
	# situation; the bonus below is large enough to outrank a far-away
	# boss / support priority so the bot deals with the immediate threat
	# instead of staying locked on a distant target.
	const DANGER_R: float = 180.0
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
		# Danger-zone override — close enemies dominate scoring so a charger
		# rushing the bot wins over a distant boss/support target. Bonus
		# scales with proximity (max +18000 when point-blank, 0 at DANGER_R).
		if d < DANGER_R:
			score += (DANGER_R - d) * 100.0
		# Boss priority — anything with the boss group always wins ties
		if is_boss:
			score += 8000.0
		# Easy-kill bonus: low-HP-ratio enemies are worth finishing first
		if "health" in ne and "max_health" in ne:
			var max_hp_e: float = maxf(1.0, float(ne.get("max_health")))
			var hp_ratio: float = float(ne.get("health")) / max_hp_e
			score += (1.0 - hp_ratio) * 800.0
		# Support enemies are force multipliers — kill them first so they stop
		# buffing/spawning waves of others. Identify by script path.
		var script_ref: Script = ne.get_script() as Script
		if script_ref != null:
			var path := script_ref.resource_path
			if path.contains("EnemyEnchanter") or path.contains("EnemySummoner"):
				score += 1200.0
		# Frozen / chilled enemies take +25% damage (see EnemyBase.take_damage),
		# and stunned ones can't fight back — both are great kill priorities.
		if "_frozen" in ne and bool(ne.get("_frozen")):
			score += 700.0
		elif "_chill_stacks" in ne and int(ne.get("_chill_stacks")) > 0:
			score += 250.0
		if "_stun_timer" in ne and float(ne.get("_stun_timer")) > 0.0:
			score += 400.0
		if score > best_score:
			best_score = score
			best = ne
	return best

# Sprint mode only detours for clearly-valuable bags: any wand, or a rare /
# legendary equipment upgrade. Cheaper commons aren't worth pausing the run.
func _autoplay_bag_worth_sprint_detour(bag: Node) -> bool:
	if not "items" in bag:
		return false
	for it in bag.get("items"):
		if not (it is Item):
			continue
		var item: Item = it as Item
		if item.type == Item.Type.WAND:
			return true
		var slot := item.get_equip_slot_name()
		if slot == "":
			continue
		if item.rarity < Item.RARITY_RARE:
			continue
		var current: Item = InventoryManager.equipped.get(slot) as Item
		if current == null or item.rarity > current.rarity:
			return true
	return false

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
		# Prune right after pickup so the next bag has somewhere to land
		_autoplay_clear_junk()
		# In sprint mode, count this as our one allowed detour for the floor
		# so the bot doesn't keep diverting.
		if _autoplay_sprint:
			_autoplay_sprint_detours_used += 1
		# Loot pickup cooldown + per-floor detour count. Both serve to break
		# bag-grinding loops on floors saturated with loot bags.
		_autoplay_post_loot_cd = 3.0
		_autoplay_floor_loot_detours += 1
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

# Defensive stance — triggered when HP drops below half in non-sprint runs.
# Skips the close-range wand override, weights dodge force more heavily, and
# adds an enemy-pressure repulsion force so the bot peels away from chasers.
func _autoplay_is_defensive() -> bool:
	if not _autoplay or _autoplay_sprint:
		return false
	var max_hp := _max_hp()
	if max_hp <= 0:
		return false
	return float(health) / float(max_hp) < 0.50

# Standard-mode kiting force — push away from any enemy within ~150 px so the
# bot doesn't let melee/charger types close into contact range. Tighter and
# more close-range-biased than the defensive pressure force; falls off to
# zero by 150 px so it doesn't pull us off our objective from across a room.
func _autoplay_kite_force() -> Vector2:
	var total := Vector2.ZERO
	# Bumped from 150 → 200 so the bot starts peeling off earlier — fast
	# rushers like chargers (720 px/s dash) eat 150 px in 0.21 s, faster
	# than the blend can react. 200 px gives ~0.28 s of reaction time.
	const KITE_R := 200.0
	const KITE_R_SQ := KITE_R * KITE_R
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var ne := e as Node2D
		var to_e: Vector2 = ne.global_position - global_position
		var d_sq := to_e.length_squared()
		if d_sq > KITE_R_SQ or d_sq < 0.0001:
			continue
		var d := sqrt(d_sq)
		# Quadratic falloff — close enemies dominate; ones at the edge of
		# the radius barely contribute.
		var t: float = 1.0 - d / KITE_R
		total -= (to_e / d) * (t * t)
	return total

# Sums an away-from-nearby-enemies vector. Closer enemies push harder; far
# enemies don't contribute. Used as an extra term in defensive movement.
func _autoplay_enemy_pressure_force() -> Vector2:
	var total := Vector2.ZERO
	const PRESSURE_R := 220.0
	const PRESSURE_R_SQ := PRESSURE_R * PRESSURE_R
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var ne := e as Node2D
		var to_e: Vector2 = ne.global_position - global_position
		var d_sq := to_e.length_squared()
		if d_sq > PRESSURE_R_SQ or d_sq < 0.0001:
			continue
		var d := sqrt(d_sq)
		var weight := clampf(1.0 - d / PRESSURE_R, 0.0, 1.0)
		total -= (to_e / d) * weight
	return total

# Boss orbit movement — strafe tangentially around the boss at a fixed
# radius. Direction (CW vs CCW) flips occasionally so the bot doesn't get
# pinned in a corner from rotating one way forever. If we're far from the
# orbit band we close in / back off until we're at the right distance.
const _BOSS_ORBIT_RADIUS: float = 220.0
var _boss_orbit_sign: int = 1
var _boss_orbit_flip_t: float = 0.0
func _autoplay_boss_orbit_dir(boss: Node2D) -> Vector2:
	var to_boss: Vector2 = boss.global_position - global_position
	var dist: float = to_boss.length()
	if dist < 0.001:
		return Vector2.ZERO
	# Periodically flip rotation so we don't rail into a wall
	_boss_orbit_flip_t -= get_physics_process_delta_time()
	if _boss_orbit_flip_t <= 0.0:
		_boss_orbit_flip_t = randf_range(2.5, 4.5)
		_boss_orbit_sign = -_boss_orbit_sign
	var radial: Vector2 = to_boss / dist
	var tangent: Vector2 = radial.rotated(PI * 0.5) * float(_boss_orbit_sign)
	# Mix: outside band → step in, inside band → step out, in band → strafe
	var error: float = dist - _BOSS_ORBIT_RADIUS
	var inward_weight: float = clampf(error / 80.0, -1.0, 1.0)
	# When inward_weight > 0 we move toward the boss; < 0 we move away.
	return (tangent * 0.85 + radial * inward_weight * 0.6).normalized()

func _autoplay_avoid_walls(dir: Vector2) -> Vector2:
	if dir == Vector2.ZERO:
		return dir
	# Try increasingly-deflected angles; first clear one wins. Includes both
	# halves so the player picks whichever side around an obstacle is open.
	# ±PI/4 (0.785) is in the list specifically so diagonal headings can snap
	# cleanly to horizontal/vertical at corners, which is where the bot used
	# to pin itself trying to skim a wall corner.
	var offsets: Array = [0.0, 0.5, -0.5, 0.785, -0.785, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4]
	for off in offsets:
		var test := dir.rotated(off)
		if _autoplay_clear_dir(test, 42.0):
			return test
	# Everything within 42px is blocked — nudge perpendicular and let
	# stuck-detection take over if we're truly cornered.
	return dir.rotated(PI * 0.5)

func _autoplay_move_dir() -> Vector2:
	# Wiggle override — kick in when we're stuck. avoid_walls already returns
	# a deflected, *clear* direction, so for the first stretch of being stuck
	# we just commit to that without randomization. Per-frame random jitter
	# from the previous design caused the bot to vibrate in place on path
	# corners (each frame picked a fresh random angle, net velocity ~ zero).
	# Only once we've been stuck a full 0.6 s and the clear direction still
	# isn't getting us anywhere do we start jittering — and even then the
	# jitter amplitude grows slowly.
	if _autoplay_stuck_t > 0.20:
		var goal_dir := _autoplay_path_dir()
		if goal_dir == Vector2.ZERO and is_instance_valid(_autoplay_move_to):
			goal_dir = ((_autoplay_move_to as Node2D).global_position - global_position).normalized()
		if goal_dir == Vector2.ZERO:
			goal_dir = Vector2.RIGHT
		var clear_dir := _autoplay_avoid_walls(goal_dir)
		if _autoplay_stuck_t < 0.6:
			return clear_dir
		var amp: float = clampf((_autoplay_stuck_t - 0.6) * 0.7, 0.25, 0.9)
		return clear_dir.rotated(randf_range(-amp, amp))
	var base := Vector2.ZERO
	# Boss orbit stance — when fighting a boss, hold a fixed radius around it
	# instead of charging in. Only kicks in once we're actually in the arena
	# (line of sight + within ~2× orbit radius). Otherwise the orbital pull
	# steers us straight into the wall between us and the boss room; the A*
	# branch below has to drive movement until we arrive.
	if is_instance_valid(_autoplay_move_to) and (_autoplay_move_to as Node2D).is_in_group("boss"):
		var boss_node := _autoplay_move_to as Node2D
		var boss_dist: float = global_position.distance_to(boss_node.global_position)
		if boss_dist < _BOSS_ORBIT_RADIUS * 2.0 and _autoplay_los_clear(boss_node.global_position):
			base = _autoplay_boss_orbit_dir(boss_node)
			if base != Vector2.ZERO:
				# Same dodge blend as below
				var dodge_b := _autoplay_dodge_force()
				var ds_b := dodge_b.length()
				if ds_b > 0.55:
					return (base * 0.4 + dodge_b.normalized()).normalized()
				if ds_b > 0.0:
					return (base + dodge_b.normalized() * 0.7).normalized()
				return base
	# Follow A* path waypoints when one is computed
	var pdir := _autoplay_path_dir()
	if pdir != Vector2.ZERO:
		base = pdir
	elif is_instance_valid(_autoplay_move_to):
		var to_t: Vector2 = (_autoplay_move_to as Node2D).global_position - global_position
		if to_t.length() > 4.0:
			base = _autoplay_avoid_walls(to_t.normalized())
	if base == Vector2.ZERO:
		# Even with no goal direction, defensive mode still tries to peel away
		# from any enemy crowding us so we don't sit still being chewed on.
		if _autoplay_is_defensive():
			var pressure_only := _autoplay_enemy_pressure_force()
			if pressure_only.length() > 0.05:
				return pressure_only.normalized()
		return Vector2.ZERO
	# Blend in projectile-dodge force — heavier weighting when shots are close.
	# Defensive mode bumps both the dodge weighting and adds an enemy-pressure
	# repulsion so the bot keeps distance instead of sticking to its goal.
	var defensive: bool = _autoplay_is_defensive()
	var dodge := _autoplay_dodge_force()
	var ds := dodge.length()
	if defensive:
		var pressure := _autoplay_enemy_pressure_force()
		if pressure.length() > 0.0:
			# Enemy-repulsion pulls us off the direct path proportionally — but
			# weight the goal heavier so a single enemy directly between us and
			# the portal can't cancel the forward push and leave us stalled.
			var blend := base * 0.7 + pressure.normalized() * 0.4
			if blend.length() < 0.25:
				# Pressure roughly cancels the goal — keep forward bias and let
				# physics shave off any side component naturally.
				blend = base * 0.85 + pressure.normalized() * 0.2
			base = blend.normalized()
		if ds > 0.55:
			return (base * 0.20 + dodge.normalized()).normalized()
		if ds > 0.0:
			return (base + dodge.normalized() * 1.1).normalized()
		return base
	# Standard-mode kiting — blend in away-from-nearby-enemies push so melee
	# threats get held at arm's length while we keep advancing toward our
	# goal (and the shoot loop still fires constantly at whatever's in LOS).
	# Skipped on the path to a boss/loot to avoid pulling us off objectives
	# the bot is supposed to actively close on.
	var kite := _autoplay_kite_force()
	if kite.length() > 0.05:
		# Guard the cast — _autoplay_move_to can briefly hold a freed loot bag
		# or enemy after pickup/death, and `as Node2D` on a freed Object errors
		# with "Trying to cast a freed object".
		var keep_kite := true
		if is_instance_valid(_autoplay_move_to):
			var move_to_node := _autoplay_move_to as Node2D
			keep_kite = not (move_to_node.is_in_group("boss") \
				or move_to_node.is_in_group("loot_bag"))
		if keep_kite:
			# Raw-magnitude blend — kite_force's length already encodes how
			# close the rusher is (quadratic falloff), so multiplying by a
			# constant lets the kite dominate at point-blank without us
			# needing a separate "danger threshold" branch. With the 1.6
			# coefficient, point-blank kite (~0.85+) outweighs base (1.0)
			# and the bot peels off; mid-range kite (~0.3) gently bends
			# the trajectory while base still wins.
			base = (base + kite * 1.6).normalized()
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
	# wander off mid-fight to grab a bag. Also skip during the post-loot
	# cooldown, after the per-floor detour cap, or once the floor's been
	# active too long — these together break the bag-grind loops we kept
	# seeing on bag-saturated late floors.
	var loot_cap_reached: bool = _autoplay_floor_loot_detours >= AUTOPLAY_MAX_FLOOR_DETOURS
	var floor_too_old: bool = _autoplay_floor_age >= AUTOPLAY_FLOOR_AGE_LIMIT
	if boss == null and not _autoplay_sprint and not force_sprint \
			and _autoplay_post_loot_cd <= 0.0 \
			and not loot_cap_reached and not floor_too_old:
		loot = _autoplay_find_nearest_loot()
	# Hard commitment: if we're already heading to a still-valid bag, keep
	# going to it regardless of the on-the-way cone. Without this the bot
	# oscillates between portal and bag whenever it crosses the cone
	# threshold mid-detour. Suppressed once the per-floor detour cap or
	# age limit kicks in — those gates are supposed to *break* the chase,
	# not lock the current one in indefinitely.
	if loot == null and is_instance_valid(_autoplay_move_to) \
			and (_autoplay_move_to as Node2D).is_in_group("loot_bag") \
			and not loot_cap_reached and not floor_too_old:
		loot = _autoplay_move_to as Node2D
	# Sprint detour budget — one rare+/wand bag per floor is worth pausing for.
	elif boss == null and _autoplay_sprint and not force_sprint and _autoplay_sprint_detours_used == 0:
		var candidate: Node2D = _autoplay_find_nearest_loot()
		if is_instance_valid(candidate) and _autoplay_bag_worth_sprint_detour(candidate):
			loot = candidate
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
		# Hysteresis — once committed to a bag, hold on past the original
		# pull range. Without this, the bot drifts toward the portal, the bag
		# falls outside range, goal flips back to portal, the bot moves a tile,
		# the bag is in range again... ad infinitum. The 1.6× sticky band lets
		# us actually walk over and pick it up.
		var stick: float = 1.6 if _autoplay_move_to == loot else 1.0
		if global_position.distance_to(loot.global_position) < pull_range * stick:
			# On-the-way gate — only divert to bags that are roughly toward
			# the portal we're heading for. Skipping this caused the bot to
			# loop: portal → reach a bag → pick it up → portal again → another
			# bag pops into range behind us → reverse → loop. Once committed
			# (sticky), we keep going to that bag regardless of angle so we
			# don't drop it mid-pickup.
			var on_the_way: bool = (_autoplay_move_to == loot)
			if not on_the_way and is_instance_valid(portal):
				var to_portal: Vector2 = (portal as Node2D).global_position - global_position
				var to_loot:   Vector2 = loot.global_position - global_position
				if to_portal.length() > 1.0 and to_loot.length() > 1.0:
					on_the_way = to_portal.normalized().dot(to_loot.normalized()) > 0.3
				else:
					on_the_way = true   # already on top of one of them
			if on_the_way:
				goal = loot
	if goal == null and is_instance_valid(loot):
		goal = loot
	# Standard-mode aggro clearance — if the bot was about to head for the
	# portal but there are still enemies actively chasing/firing at it, pivot
	# to clear them out first. Skipped during sprint/force-sprint (point of
	# those modes is to bee-line) and on boss floors (boss already dominates).
	# Loot detour still wins so the bot can pick up bags on the way to a fight.
	if goal == portal and boss == null \
			and not _autoplay_sprint and not force_sprint:
		var aggro_target: Node2D = _autoplay_nearest_aggro_enemy()
		if aggro_target != null:
			goal = aggro_target
	# Wand-aware close-quarters override — for melee, shotgun, or wands whose
	# projectiles drift / spray erratically, the bot can't reliably hit at
	# range. When such a wand is equipped and a visible enemy is too far,
	# pivot the movement goal onto the enemy so we close the gap. Bosses
	# already pull us in, so we don't override that target. Defensive mode
	# also skips this — we don't want to charge in while wounded.
	if boss == null and is_instance_valid(_autoplay_enemy) and not _autoplay_is_defensive():
		var close_r: float = _autoplay_wand_close_range()
		if close_r > 0.0:
			var d_enemy: float = global_position.distance_to((_autoplay_enemy as Node2D).global_position)
			var was_chasing: bool = _autoplay_move_to == _autoplay_enemy
			if d_enemy > close_r and _autoplay_path_reachable((_autoplay_enemy as Node2D).global_position):
				goal = _autoplay_enemy
			elif was_chasing:
				# Stay locked on the enemy we were already chasing instead of
				# snapping back to the portal the instant we cross close_r —
				# otherwise we drift back out next frame and oscillate. Held
				# until the enemy dies (invalidates _autoplay_enemy) or the
				# damage-progress watchdog blacklists it for being unkillable.
				goal = _autoplay_enemy
			elif d_enemy > close_r:
				# Unreachable target with a close-range wand — blacklist briefly
				# so we don't keep firing into the void from across a wall.
				_autoplay_skipped_enemies[(_autoplay_enemy as Node).get_instance_id()] = true
				_autoplay_enemy = _autoplay_find_visible_enemy()
	if goal != _autoplay_move_to:
		_autoplay_move_to = goal
		if is_instance_valid(goal):
			_autoplay_compute_path((goal as Node2D).global_position)

# True when an A* path exists from our tile to the target world position.
# Used to gate close-range overrides so we don't try to chase an enemy that
# sits behind solid walls.
func _autoplay_path_reachable(target_world: Vector2) -> bool:
	_autoplay_build_astar()
	if _astar == null:
		return true   # no astar = no info, fall back to permissive
	var world := get_tree().current_scene
	if world == null or not "TILE" in world:
		return true
	var tile: int   = int(world.TILE)
	var grid_w: int = int(world.GRID_W)
	var grid_h: int = int(world.GRID_H)
	var s := Vector2i(int(global_position.x / float(tile)), int(global_position.y / float(tile)))
	var e := Vector2i(int(target_world.x / float(tile)), int(target_world.y / float(tile)))
	s.x = clampi(s.x, 0, grid_w - 1)
	s.y = clampi(s.y, 0, grid_h - 1)
	e.x = clampi(e.x, 0, grid_w - 1)
	e.y = clampi(e.y, 0, grid_h - 1)
	if _astar.is_point_solid(s) or _astar.is_point_solid(e):
		return false
	var path: PackedVector2Array = _astar.get_point_path(s, e)
	return not path.is_empty()

# Effective max distance at which the equipped wand can reliably hit. Returns
# 0.0 for "any range works" (regular ranged shots, beam, homing, nova, etc.).
# A positive value means we should close to within that distance before we
# expect to land hits — used to override the autoplay movement goal.
func _autoplay_wand_close_range() -> float:
	var w: Item = InventoryManager.equipped.get("wand") as Item
	if w == null:
		return 0.0
	# Drift flaw is the "swirly shot" — projectile curves sideways, so any
	# distance lets the curve carry the shot off-target. Hug the enemy.
	if "drift" in w.wand_flaws:
		return 110.0
	if "erratic" in w.wand_flaws:
		return 130.0
	if "slow_shots" in w.wand_flaws:
		# Slow projectiles let mobile enemies sidestep — close in to shorten flight.
		return 220.0
	match w.wand_shoot_type:
		"melee":
			return 56.0
		"shotgun":
			# Shotgun is a 48° cone of 5 pellets. At 170px the pattern is ~135px
			# wide and small targets (spiders, archers) often slip between
			# pellets. 95px keeps the spread tight (~75px wide) so multiple
			# pellets land even on tiny enemies — the bot rushes in instead of
			# plinking from across a corridor.
			return 95.0
	return 0.0

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

# Nearest enemy that has spotted / been damaged by us (EnemyBase._has_aggro).
# Used by standard-mode aggro clearance — the bot stays in the room until
# pursuing enemies are dealt with rather than walking past them to the portal.
# Blacklisted (wall-clipped / unkillable) enemies are excluded so we don't
# burn paths trying to reach them.
func _autoplay_nearest_aggro_enemy() -> Node2D:
	var best: Node2D = null
	var best_d: float = INF
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if _autoplay_skipped_enemies.has(e.get_instance_id()):
			continue
		if not ("_has_aggro" in e):
			continue
		if not bool(e.get("_has_aggro")):
			continue
		var ne := e as Node2D
		var d: float = global_position.distance_to(ne.global_position)
		if d < best_d:
			best_d = d
			best = ne
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
	for trap_node in get_tree().get_nodes_in_group("trap"):
		if not is_instance_valid(trap_node):
			continue
		var tpos: Vector2 = (trap_node as Node2D).global_position
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
	# When the player's body is jammed against a wall, int-truncating its
	# world position can land the start tile inside the wall. Snap to the
	# nearest walkable tile so A* still returns a path instead of bailing.
	# Same logic protects the goal (e.g. boss collider overlapping a pillar).
	if _astar.is_point_solid(s):
		s = _autoplay_nearest_walkable(s, grid_w, grid_h)
	if _astar.is_point_solid(e):
		e = _autoplay_nearest_walkable(e, grid_w, grid_h)
	if s.x < 0 or e.x < 0:
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

# Returns the closest walkable tile to `t` via spiral search, or Vector2i(-1,-1)
# if none found within a small radius. Used to recover from edge-clipped start
# tiles where the player's body straddles a wall and the truncated tile coord
# lands on solid ground.
func _autoplay_nearest_walkable(t: Vector2i, grid_w: int, grid_h: int) -> Vector2i:
	for r in range(1, 5):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if abs(dx) != r and abs(dy) != r:
					continue   # only ring at radius r
				var nx: int = t.x + dx
				var ny: int = t.y + dy
				if nx < 0 or nx >= grid_w or ny < 0 or ny >= grid_h:
					continue
				if _astar.is_point_solid(Vector2i(nx, ny)):
					continue
				var d: float = float(dx * dx + dy * dy)
				if d < best_d:
					best_d = d
					best = Vector2i(nx, ny)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)

func _autoplay_path_dir() -> Vector2:
	if _autoplay_path.is_empty():
		return Vector2.ZERO
	var world := get_tree().current_scene
	var half := Vector2(float(int(world.TILE)) * 0.5, float(int(world.TILE)) * 0.5)
	while _autoplay_path_idx < _autoplay_path.size():
		var wp: Vector2 = _autoplay_path[_autoplay_path_idx] + half
		var to_wp := wp - global_position
		var d := to_wp.length()
		if d < 14.0:
			_autoplay_path_idx += 1
			continue
		# Diagonal-corner unstick: if we're close-ish to this waypoint but
		# the straight line to it is blocked by a wall (the path skirts the
		# corner of one), skip ahead — aiming further along the path lets the
		# steering pick up the orthogonal component naturally instead of
		# pinning us into the corner trying to reach an unreachable tile.
		if d < 36.0 and not _autoplay_clear_dir(to_wp / d, d):
			_autoplay_path_idx += 1
			continue
		return _autoplay_steer_from_walls(to_wp / d)
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
	if _autoplay_post_loot_cd > 0.0:
		_autoplay_post_loot_cd -= delta
	# Floor age accumulates only while the bot is actually doing things —
	# pausing/menus shouldn't burn the timer.
	_autoplay_floor_age += delta
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
	# Nova spell is intentionally disabled for autoplay — the bot would
	# burn the 100-mana spell every time it caught two enemies in range
	# and end up mana-starved for actual wand fire. The player can still
	# cast Q manually.
	# Health potion when very low
	_autoplay_potion_t -= delta
	if _autoplay_potion_t <= 0.0:
		_autoplay_potion_t = 0.6
		_autoplay_try_potion()
	# Periodically clear junk so the inventory doesn't fill up with valuables
	# / worse-tier duplicates and block new pickups. Runs frequently because
	# we also want to enforce the minimum-free-slots invariant.
	_autoplay_clean_t -= delta
	if _autoplay_clean_t <= 0.0:
		_autoplay_clean_t = 1.0
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
			# Bosses are exempt from the unkillable-watchdog. Their HP pools
			# are large enough (and their invuln windows long enough) that
			# a 6 s no-damage stretch is normal mid-fight; blacklisting them
			# would permanently disengage from the room's main objective and
			# the bot would never attack them again on the floor.
			var is_boss_target: bool = (_autoplay_enemy as Node).is_in_group("boss")
			if _autoplay_enemy_dmg_t > 6.0 and not is_boss_target:
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
	# For each equipment slot, equip the strongest grid item that beats what's
	# currently slotted. When equipping, the displaced item gets swapped INTO
	# the grid slot the new one came from — without this, the same wand ends
	# up referenced by both equipped[] and grid[i], which made debug-randomize
	# / shrine effects appear to "revert" (the next auto-equip tick re-picked
	# the still-present grid copy).
	var dirty := false
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		var slot := item.get_equip_slot_name()
		if slot == "":
			continue
		var current: Item = InventoryManager.equipped.get(slot) as Item
		var should_equip := false
		if slot == "wand":
			# Burn through limited-use wands first — strict preference over
			# permanent wands regardless of score, since the consumables are
			# meant to be used and discarded. Among multiple limited wands,
			# pick the one with the highest score; among permanents, same.
			var item_limited: bool = item.wand_max_charges > 0
			var current_limited: bool = current != null and current.wand_max_charges > 0
			# Hard skip "backwards"-flaw wands. With autoplay's LOS / fire
			# loop, a backwards wand passes the can-shoot gate and then
			# fires projectiles 180° away from the target, draining mana
			# while doing zero damage. Better to keep the current wand
			# (or even no wand) than to equip this.
			var item_backwards: bool = "backwards" in item.wand_flaws
			if item_backwards and current != null:
				continue
			if item_limited and not current_limited:
				should_equip = true
			elif item_limited and current_limited:
				should_equip = _wand_score(item) > _wand_score(current)
			elif not item_limited and not current_limited:
				should_equip = current == null or _wand_score(item) > _wand_score(current)
			# else: candidate is permanent and current is limited — keep
			# using the limited one until it shatters.
		else:
			should_equip = current == null or item.rarity > current.rarity
		if should_equip:
			InventoryManager.equipped[slot] = item
			InventoryManager.grid[i] = current   # swap (current may be null)
			dirty = true
			# Fanfare — announce the bot's pick so the player can see what
			# it just decided to wield. Color cues rarity (white→gold→purple).
			var rarity_col: Color = Color(0.85, 0.85, 0.85)
			if item.rarity == Item.RARITY_RARE:
				rarity_col = Color(1.0, 0.85, 0.20)
			elif item.rarity == Item.RARITY_LEGENDARY:
				rarity_col = Color(0.85, 0.30, 1.00)
			FloatingText.spawn_str(global_position + Vector2(0.0, -56.0),
				"★ EQUIP: " + item.display_name, rarity_col, get_tree().current_scene)
	if dirty:
		InventoryManager.inventory_changed.emit()
		update_equip_stats()

# Heuristic damage-per-second score for a wand. Folds rarity, raw DPS, pierce
# / ricochet / status-stack bonuses, and flaw penalties so the auto-equipper
# can pick the genuinely-stronger wand instead of just the higher rarity.
# Also granted a small "novelty" bonus when the equipped shoot_type has no
# weapon-stat history this run, encouraging variety in the death recap.
func _wand_score(w: Item) -> float:
	if w == null or w.type != Item.Type.WAND:
		return 0.0
	var rate: float = maxf(0.04, w.wand_fire_rate)
	var dps: float = float(w.wand_damage) / rate
	# Variety bonus — push fresh shoot_types over near-equal current pick.
	if not GameState.weapon_stats.has(w.wand_shoot_type):
		dps *= 1.10
	# Multi-hit & status modifiers — rough multipliers, not exact.
	dps *= 1.0 + 0.30 * float(w.wand_pierce)
	dps *= 1.0 + 0.20 * float(w.wand_ricochet)
	if w.wand_shoot_type in ["fire", "freeze", "shock"]:
		dps *= 1.0 + 0.10 * float(w.wand_status_stacks)
	# Elemental wands scale with INT — fire patches & shock chain procs
	# multiply with INT bonus, freeze profits from shatter combos. Lift the
	# score for these on high-INT runs so the bot stops preferring a flat
	# pierce wand when an elemental would dominate.
	if w.wand_shoot_type in ["fire", "freeze", "shock", "nova"]:
		var int_bonus: int = GameState.get_stat_bonus("INT")
		dps *= 1.0 + 0.05 * float(maxi(0, int_bonus))
	if w.wand_shoot_type == "beam":
		dps *= 1.4   # continuous, pierces all
	if w.wand_shoot_type == "shotgun":
		dps *= 1.6   # 5 pellets per shot
	if w.wand_shoot_type == "nova":
		dps *= 1.3
	if w.wand_shoot_type == "homing":
		dps *= 1.15
	# Flaw penalties — drift / erratic / backwards / slow_shots all hurt
	# real-world hit rate. clunky / sloppy / mana_guzzle each trade something
	# tangible for a damage- or rate-side payoff so they're balanced flaws
	# rather than pure penalties.
	for f in w.wand_flaws:
		match String(f):
			"backwards":   dps *= 0.50
			"drift":       dps *= 0.65
			"erratic":     dps *= 0.55
			"slow_shots":  dps *= 0.70
			"clunky":      dps *= 0.85   # 0.5× rate × 1.5× dmg ≈ 0.75, +0.10 for harder hits
			"sloppy":      dps *= 0.85   # 1.5× rate but ~half hit rate from arc
			"mana_guzzle": dps *= 0.90   # 2× cost × 2× dmg = neutral DPS,
										 # mana sustainability handled below
	# Sustainability — fold the per-shot mana cost into the score. A wand
	# that costs more mana than the bot can realistically pay (e.g. pierce +
	# mana_guzzle scaled by difficulty) ends up unable to fire even when an
	# enemy is right in front of it. Without this, auto-equip kept picking
	# such wands purely on theoretical DPS and the bot would stand there
	# unable to shoot. Effective cost includes the same flaw / difficulty
	# multipliers _handle_shooting applies, so the score reflects what
	# actually leaves the muzzle.
	var eff_cost: float = w.wand_mana_cost
	if "mana_guzzle" in w.wand_flaws:
		eff_cost *= 2.0
	eff_cost *= _difficulty_mana_multiplier()
	var max_m: float = max_mana
	if max_m > 0.0 and eff_cost > 0.0:
		# Above 30 % of the mana pool per shot the wand starves itself —
		# scale the score down progressively. A wand that costs 100 % of
		# max mana per shot ends up at ~30 % of its raw DPS rating.
		var ratio: float = eff_cost / (max_m * 0.30)
		if ratio > 1.0:
			dps /= ratio
	# Rarity tie-break — equal-DPS comparison favours the higher rarity.
	return dps + float(w.rarity) * 0.001

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
	# Heavily-pressured panic — when 5+ enemies are right on top of us, dash
	# away from the cluster centroid the moment cooldowns allow. Bypasses
	# _start_dash's movement-input read by setting _dash_dir directly.
	if cluster >= 5 and stamina >= DASH_STAMINA_COST and _autoplay_dash_t <= 0.0 and _dash_timer <= 0.0:
		_autoplay_panic_dash()

# Computes the centroid of nearby enemies and dashes opposite that vector.
func _autoplay_panic_dash() -> void:
	var centroid := Vector2.ZERO
	var n := 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var ne := e as Node2D
		if global_position.distance_to(ne.global_position) < 230.0:
			centroid += ne.global_position
			n += 1
	if n == 0:
		return
	centroid /= float(n)
	var away := global_position - centroid
	if away.length_squared() < 1.0:
		away = Vector2.RIGHT.rotated(randf_range(0.0, TAU))
	_dash_dir   = away.normalized()
	_dash_timer = DASH_DURATION
	stamina    -= DASH_STAMINA_COST
	_is_invincible = true
	modulate    = Color(0.5, 0.8, 1.0, 0.6)
	_spawn_dash_afterimages()
	_autoplay_dash_t = 1.5

# Sweeps the inventory grid: keeps only items that are useful to the bot.
# Caps potions at MAX_POTIONS so they don't fill the grid and block new pickups.
# After the first pass, enforces AUTOPLAY_MIN_FREE_SLOTS by discarding the
# lowest-value remaining items so there's always headroom for fresh loot.
const AUTOPLAY_MAX_POTIONS: int = 2
const AUTOPLAY_MIN_FREE_SLOTS: int = 5
const AUTOPLAY_MAX_WANDS: int = 5
func _autoplay_clear_junk() -> void:
	if InventoryManager == null:
		return
	var changed := false
	# Sweep out any spent limited-use wands first — _shatter_wand handles the
	# equipped one, but a depleted wand sitting unequipped in the grid would
	# never re-enter that path. Delete them here so the cap and auto-equip
	# logic don't keep treating zero-charge wands as valid candidates.
	for i in InventoryManager.grid.size():
		var spent: Item = InventoryManager.grid[i] as Item
		if spent != null and spent.type == Item.Type.WAND \
				and spent.wand_max_charges > 0 and spent.wand_charges <= 0:
			InventoryManager.grid[i] = null
			changed = true
	var potions_kept := 0
	for i in InventoryManager.grid.size():
		var item: Item = InventoryManager.grid[i] as Item
		if item == null:
			continue
		if item.type == Item.Type.WAND:
			continue   # wand cap is enforced separately below
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
	# Wand cap — keep at most AUTOPLAY_MAX_WANDS extra wands in the grid (the
	# equipped wand doesn't count, even though auto-equip leaves a copy in the
	# grid). Limited-use wands stay first since the bot is meant to burn
	# through them; among permanents we drop the lowest-score ones. Forces the
	# bot to refresh its arsenal instead of hoarding every wand it picks up.
	var equipped_wand: Item = InventoryManager.equipped.get("wand") as Item
	var wand_idxs: Array = []
	for i in InventoryManager.grid.size():
		var w_item: Item = InventoryManager.grid[i] as Item
		if w_item != null and w_item.type == Item.Type.WAND and w_item != equipped_wand:
			wand_idxs.append(i)
	if wand_idxs.size() > AUTOPLAY_MAX_WANDS:
		wand_idxs.sort_custom(func(a: int, b: int) -> bool:
			var ia: Item = InventoryManager.grid[a] as Item
			var ib: Item = InventoryManager.grid[b] as Item
			# Limited-use wands are kept preferentially (bigger keep_score) so
			# they survive the cull; otherwise rank by _wand_score.
			var sa: float = _wand_score(ia) + (1000.0 if ia.is_limited_use() else 0.0)
			var sb: float = _wand_score(ib) + (1000.0 if ib.is_limited_use() else 0.0)
			return sa > sb)   # best first; lowest-ranked at the tail get dropped
		for k in range(AUTOPLAY_MAX_WANDS, wand_idxs.size()):
			InventoryManager.grid[int(wand_idxs[k])] = null
			changed = true
	# Headroom enforcement — pick the lowest-value items still held and drop
	# them until we hit AUTOPLAY_MIN_FREE_SLOTS.
	var free := _autoplay_count_free_slots()
	if free < AUTOPLAY_MIN_FREE_SLOTS:
		var candidates: Array = []
		for i in InventoryManager.grid.size():
			var it: Item = InventoryManager.grid[i] as Item
			if it == null:
				continue
			if it.type == Item.Type.WAND:
				continue
			# Score lower = drop sooner. Rarity dominates so we never trash a
			# legendary, then sell value tie-breaks among same-rarity items.
			candidates.append({"idx": i, "score": int(it.rarity) * 1000 + int(it.sell_value)})
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["score"]) < int(b["score"]))
		var need: int = AUTOPLAY_MIN_FREE_SLOTS - free
		for c in candidates:
			if need <= 0:
				break
			InventoryManager.grid[int(c["idx"])] = null
			changed = true
			need -= 1
	if changed:
		InventoryManager.inventory_changed.emit()

func _autoplay_count_free_slots() -> int:
	if InventoryManager == null:
		return 0
	var c := 0
	for i in InventoryManager.grid.size():
		if InventoryManager.grid[i] == null:
			c += 1
	return c

# Late-game mana stays meaningful — wand mana costs scale up with difficulty
# so player WIS investment matters at the higher tiers.
func _difficulty_mana_multiplier() -> float:
	# Mana cost grows with difficulty but caps at 2.5× so deep-floor wands
	# stay fireable. Past ~floor 9 the previous uncapped formula made every
	# wand cost more than the player's pool refilled per shot.
	var d: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	return clampf(1.0 + maxf(0.0, d - 1.0) * 0.18, 1.0, 2.5)

# Picks the perk most useful right now. Heals when HP is low, otherwise leans
# into long-term survival/DPS multipliers; falls back to any perk so the bot
# never stalls if the preferred ones aren't in PERKS.
func _autoplay_pick_perk() -> Dictionary:
	var max_hp := _max_hp()
	var hp_ratio: float = 1.0 if max_hp <= 0 else float(health) / float(max_hp)
	# Order from highest to lowest preference. The first matching id from PERKS wins.
	var preference: Array = []
	if hp_ratio < 0.55:
		preference.append("heal_now")
	preference.append_array([
		"hp_up",
		"fire_rate_up",
		"wisdom_up",
		"mana_up",
		"dash_up",
		"speed_up",
		"proj_up",
		"heal_now",
	])
	for pid in preference:
		for p: Dictionary in PERKS:
			if String(p.get("id", "")) == String(pid):
				return p
	return PERKS[randi() % PERKS.size()]

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
	# Dash when any enemy is in contact / about to be. Was previously gated
	# behind <30 % HP + a 100 px range — too late to actually escape damage.
	# Now: any enemy within 38 px (their hitbox is touching us) triggers a
	# burst dash, regardless of HP. Lets the bot peel away from chargers and
	# spider swarms before they tag us.
	const _CONTACT_R: float = 38.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		if global_position.distance_squared_to((e as Node2D).global_position) <= _CONTACT_R * _CONTACT_R:
			return true
	return false

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

# Pop the shield only when projectiles are *imminent* and there are enough
# of them that the dodge-force won't peel us out of the line in time. Tuned
# to be miserly with mana — the previous version popped on any 3 loosely-
# aimed shots within 180 px, which spent mana on shots that would have
# missed anyway. Now:
#   • require ≥ 25 mana to bother (don't drain the pool for one shield tick)
#   • range tightened 180 → 110 px (genuinely about-to-hit shots only)
#   • cone tightened dot 0.5 → 0.7 (wider angles aren't really aimed at us)
#   • trigger raised 3 → 4 normally, 1 → 2 below 30 % HP
# Combined effect: shield comes up for genuine swarms / panic moments rather
# than reflexively flinching at every stray projectile.
func _autoplay_wants_shield() -> bool:
	if mana < 25.0:
		return false
	var hp_ratio: float = float(health) / maxf(1.0, float(_max_hp()))
	var trigger: int = 2 if hp_ratio < 0.30 else 4
	var threats := 0
	for p in get_tree().get_nodes_in_group("enemy_projectile"):
		if not is_instance_valid(p):
			continue
		var proj := p as Node2D
		var to_us: Vector2 = global_position - proj.global_position
		var dist := to_us.length()
		if dist > 110.0 or dist < 0.001:
			continue
		var pdir: Vector2 = Vector2.ZERO
		if "direction" in proj:
			pdir = (proj.direction as Vector2).normalized()
		if pdir == Vector2.ZERO:
			continue
		if pdir.dot(to_us.normalized()) > 0.7:
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
	# HASTE floor scales with difficulty — base 30 % bump, +5 % per diff step,
	# capped so high-tier haste floors don't spiral into 2.5×+ multipliers
	# that combined with mana-surge buffs put the player at 1800 px/s.
	var haste_mult: float = 1.0
	if GameState.has_floor_modifier("haste"):
		haste_mult = clampf(1.3 + 0.05 * maxf(0.0, GameState.difficulty - 1.0), 1.3, 1.8)
	var agi_bonus := float(GameState.get_stat_bonus("AGI")) * 4.0
	velocity = direction * (speed + _equip_speed_bonus + agi_bonus) * _speed_multiplier * slow_mult * haste_mult
	# Hard ceiling on player speed. Past ~600 px/s the bot teleports across
	# tiles fast enough to bypass pathing / LOS / dodge logic and clip into
	# corners. The cap is generous (3× base) so haste/agi builds still feel
	# fast without breaking the AI assumptions.
	const _MAX_PLAYER_SPEED: float = 600.0
	if velocity.length() > _MAX_PLAYER_SPEED:
		velocity = velocity.normalized() * _MAX_PLAYER_SPEED
	move_and_slide()

# Auto-unequips a limited-use wand whose charges have run out and removes it
# from the inventory grid entirely. These aren't refillable — leaving the
# spent wand in the bag would just clutter the cap and give auto-equip a
# zero-charge wand to keep "preferring" since it's still flagged limited-use.
func _shatter_wand(wand: Item) -> void:
	if wand == null:
		return
	if InventoryManager.equipped.get("wand") == wand:
		InventoryManager.equipped["wand"] = null
	for i in InventoryManager.grid.size():
		if InventoryManager.grid[i] == wand:
			InventoryManager.grid[i] = null
	InventoryManager.inventory_changed.emit()
	update_equip_stats()
	if SoundManager:
		SoundManager.play("explosion", randf_range(0.55, 0.7))
	FloatingText.spawn_str(global_position + Vector2(0.0, -32.0),
		"WAND SHATTERED!",
		Color(1.0, 0.45, 0.65),
		get_tree().current_scene)

func _handle_shooting(delta: float) -> void:
	_shoot_cooldown -= delta
	if _inventory_ui and _inventory_ui.visible:
		if _beam_line:
			_beam_line.visible = false
		return

	var wand: Item = InventoryManager.equipped.get("wand") as Item
	# Safety net: a limited-use wand at 0 charges should never block firing.
	# Normally _shatter_wand removes it after the killing shot, but if a spent
	# wand somehow ended up equipped (re-equipped from a duplicate, manual
	# drag, etc.) the player would press fire and see nothing happen because
	# this branch's later "fire then decrement" still fires but visually the
	# wand looks broken to the user. Shatter immediately so the next frame
	# falls back to a fresh wand or basic shots.
	if wand != null and wand.is_limited_use() and wand.wand_charges <= 0:
		_shatter_wand(wand)
		wand = null
	# Also sweep the grid for any other spent limited wands so they can't be
	# re-equipped later. Cheap (grid is 25 slots).
	var grid_dirty := false
	for i in InventoryManager.grid.size():
		var g_it: Item = InventoryManager.grid[i] as Item
		if g_it != null and g_it.type == Item.Type.WAND \
				and g_it.is_limited_use() and g_it.wand_charges <= 0:
			InventoryManager.grid[i] = null
			grid_dirty = true
	if grid_dirty:
		InventoryManager.inventory_changed.emit()

	# Beam wand — separate continuous path
	if wand != null and wand.wand_shoot_type == "beam":
		_handle_beam(delta, wand)
		return

	# Hide beam line if we switched away from beam
	if _beam_line:
		_beam_line.visible = false

	# Fire rate is now DEX-driven. Start from the base cooldown, divide by a
	# DEX-derived factor, then apply per-wand flaw modifiers (clunky slows,
	# sloppy speeds up). Wand-specific wand_fire_rate is no longer the
	# primary rate — DEX is.
	var dex := float(GameState.get_stat_bonus("DEX"))
	var actual_rate: float = BASE_FIRE_RATE_DEX / (1.0 + maxf(0.0, dex) * BASE_FIRE_DEX_SCALE)
	if wand != null:
		if "clunky" in wand.wand_flaws:
			actual_rate *= 2.0   # half rate; +50 % damage handled in _fire
		if "sloppy" in wand.wand_flaws:
			actual_rate /= 1.5   # 1.5× rate; ±13° aim arc handled in _fire
	# Equipment fire-rate-reduction items still chip a bit off the cooldown.
	actual_rate = maxf(0.04, (actual_rate - _equip_fire_rate_bonus) / _fire_rate_multiplier)

	if _wants_shoot() and _shoot_cooldown <= 0.0:
		var mana_cost: float
		if wand != null:
			mana_cost = wand.wand_mana_cost
			if "mana_guzzle" in wand.wand_flaws:
				mana_cost *= 2.0
		else:
			mana_cost = BASE_SHOT_MANA_COST
		mana_cost *= _difficulty_mana_multiplier()
		if mana >= mana_cost:
			mana -= mana_cost
			_fire(wand)
			_shoot_cooldown = actual_rate
			# Limited-use wands burn a charge per shot. When the meter hits
			# zero the wand auto-unequips and shatters (autoplay's auto-equip
			# tick will then pick the next-best wand from the bag).
			if wand != null and wand.is_limited_use():
				wand.wand_charges -= 1
				if wand.wand_charges <= 0:
					_shatter_wand(wand)

func _handle_beam(delta: float, wand: Item) -> void:
	if not _wants_shoot():
		if _beam_line:
			_beam_line.visible = false
		return

	var drain: float = wand.wand_mana_cost
	if "mana_guzzle" in wand.wand_flaws:
		drain *= 2.0
	drain *= _difficulty_mana_multiplier()
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

	@warning_ignore("integer_division")
	var intel      := clampi(1 + (GameState.level - 1) / 2, 1, 8)
	# INT drives damage scaling now (STR was removed). intel is the level-
	# derived intelligence cap (1..8); GameState.get_stat_bonus("INT") is
	# the per-point INT investment via levels / gear / shrines.
	var beam_dmg   := wand.wand_damage + intel * 2 + GameState.get_stat_bonus("INT")
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
				dmg_to_deal = int(round(float(dmg_to_deal) * GameState.crit_damage_mult()))
			if collider.has_method("take_damage"):
				collider.take_damage(dmg_to_deal)
				GameState.damage_dealt += dmg_to_deal
				GameState.record_weapon_damage("beam", dmg_to_deal)
				if (collider as Node).is_queued_for_deletion():
					GameState.record_weapon_kill("beam")
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
	# Muzzle flash — brief glyph in the wand's color/icon at the player
	# position. Skipped for melee (handled visually by _fire_melee).
	if wand != null and wand.wand_shoot_type != "melee":
		var flash_glyph := wand.icon_char if wand.icon_char != "" else "*"
		EffectFx.spawn_muzzle_flash(global_position + base_dir * 18.0,
			flash_glyph, wand.color, get_tree().current_scene)
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
			# Autoplay (and mobile auto-combat) neutralize the flip — the
			# bot effectively pre-aims opposite, so the flaw's reversal
			# lands the projectile back on the actual target. Without
			# this, auto-fire wastes mana firing 180° from any visible
			# enemy.
			if not (_autoplay or _mobile_auto_combat):
				base_dir = -base_dir
		if "erratic" in wand.wand_flaws:
			base_dir = base_dir.rotated(randf_range(-0.7, 0.7))
		# Sloppy — shots come out off-target by up to ±13° (≈ ±0.227 rad).
		# Smaller arc than erratic, but stacks if both somehow roll.
		if "sloppy" in wand.wand_flaws:
			base_dir = base_dir.rotated(deg_to_rad(randf_range(-13.0, 13.0)))

		if wand.wand_shoot_type == "melee":
			_fire_melee(wand, base_dir)
			return

		@warning_ignore("integer_division")
		var _intel := clampi(1 + (GameState.level - 1) / 2, 1, 8)
		# INT now scales damage too (STR was removed). The variable name
		# stays "_str_bonus" for minimal blast radius — it's just sourcing
		# from INT now.
		var _str_bonus := GameState.get_stat_bonus("INT")
		# Flaw-driven damage multipliers stack:
		#   clunky      → +50 % damage (paired with halved fire rate)
		#   mana_guzzle → +100 % damage (paired with doubled mana cost)
		# Net effect: a "clunky + guzzle" wand is a slow, expensive nuke that
		# hits at 3× damage per shot — viable burst flavor without breaking
		# DPS-per-mana balance.
		var dmg_mult: float = 1.0
		if "clunky" in wand.wand_flaws:
			dmg_mult *= 1.5
		if "mana_guzzle" in wand.wand_flaws:
			dmg_mult *= 2.0
		if wand.wand_shoot_type == "shotgun":
			var spread_total := deg_to_rad(48.0)
			for i in 5:
				var angle_offset := -spread_total * 0.5 + spread_total * (float(i) / 4.0)
				var sProj := projectile_scene.instantiate()
				sProj.global_position = global_position
				sProj.direction = base_dir.rotated(angle_offset)
				sProj.set("source", "player")
				sProj.set("damage", int(round(float(wand.wand_damage + _str_bonus) * dmg_mult)))
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
		proj.set("damage", int(round(float(wand.wand_damage + _str_bonus) * dmg_mult)))
		proj.set("pierce_remaining", wand.wand_pierce)
		proj.set("ricochet_remaining", wand.wand_ricochet)
		proj.set("shoot_type", wand.wand_shoot_type)
		proj.set("apply_freeze", wand.wand_shoot_type == "freeze")
		proj.set("apply_burn", wand.wand_shoot_type == "fire")
		proj.set("apply_shock", wand.wand_shoot_type == "shock")
		# Pass the wand's per-shot stack count so freeze/fire/shock apply
		# multiple stacks per hit (was effectively 1 regardless of value).
		proj.set("status_stacks", maxi(1, wand.wand_status_stacks))
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
	# Strike lands wherever the cursor is — the fist wand reaches as far as
	# the player aims, no MAX_REACH cap. Mana cost still gates spam.
	var radius  := 48.0
	var hit_pos := _get_aim_pos()

	@warning_ignore("integer_division")
	var intel  := clampi(1 + (GameState.level - 1) / 2, 1, 8)
	# Melee strikes also use INT for the damage-scaling stat now.
	var dmg    := wand.wand_damage + intel * 3 + GameState.get_stat_bonus("INT")
	# Same flaw-driven damage multipliers as ranged fires:
	#   clunky      → 1.5× per swing (halved swing rate)
	#   mana_guzzle → 2.0× per swing (doubled mana cost)
	if "clunky" in wand.wand_flaws:
		dmg = int(round(float(dmg) * 1.5))
	if "mana_guzzle" in wand.wand_flaws:
		dmg = int(round(float(dmg) * 2.0))

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
				actual = int(round(float(actual) * GameState.crit_damage_mult()))
			(body as Node).take_damage(actual)
			GameState.damage_dealt += actual
			GameState.record_weapon_damage("melee", actual)
			if (body as Node).is_queued_for_deletion():
				GameState.record_weapon_kill("melee")
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
	# Higher difficulties make enemies more deadly — scale incoming damage
	# before shield/DEF so both sources of mitigation apply consistently.
	var diff_for_dmg: float = GameState.test_difficulty if GameState.test_mode else GameState.difficulty
	var dmg_mult: float = 1.0 + maxf(0.0, diff_for_dmg - 1.0) * 0.40
	if dmg_mult > 1.0:
		amount = max(1, int(round(float(amount) * dmg_mult)))
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
	FloatingText.spawn(global_position, amount, false, get_tree().current_scene)
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
	bar.offset_right = 11.0 + _hp_bar_inner_width * ratio
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
	# Bar is anchored to bottom-center; offset_left is fixed at -200, so the
	# right edge moves from -200 (empty) to +200 (full) as xp ratio grows.
	_xp_bar_fg.offset_right = -200.0 + 400.0 * ratio

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
	# If the run cracked the local top 10 in any category, prompt for a name
	# and submit to the global leaderboard.
	if _made_top_10(ranks) and OnlineLeaderboard.is_configured():
		_show_global_submit_prompt()

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

	# Panel that sits below the existing retry/quit buttons. Tall enough to
	# host run stats, leaderboard, run summary, and weapon panel side-by-side.
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.03, 0.08, 0.97)
	panel.position = Vector2(40, 488)
	panel.size = Vector2(1520, 396)
	dm.add_child(panel)

	# Current run stats — top line, full-width
	var biome_name: String = "Dungeon"
	const BIOMES := ["Dungeon", "Catacombs", "Ice Cavern", "Lava Rift"]
	if GameState.biome >= 0 and GameState.biome < BIOMES.size():
		biome_name = BIOMES[GameState.biome]
	var run_secs: float = GameState.run_seconds()
	var summary := Label.new()
	summary.text = "Biome: %s    Kills: %d    Portals: %d    Gold: %d    Damage: %d    Time: %s" % [
		biome_name,
		GameState.kills, GameState.portals_used,
		GameState.gold, GameState.damage_dealt,
		_format_run_time(run_secs)
	]
	summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary.position = Vector2(40, 498)
	summary.size = Vector2(1520, 22)
	summary.add_theme_font_size_override("font_size", 14)
	summary.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	dm.add_child(summary)

	var rates := Label.new()
	rates.text = "Gold/sec: %.2f    Damage/sec: %.1f    Avg dmg/kill: %.1f" % [
		float(GameState.gold) / run_secs,
		float(GameState.damage_dealt) / run_secs,
		float(GameState.damage_dealt) / maxf(1.0, float(GameState.kills)),
	]
	rates.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rates.position = Vector2(40, 522)
	rates.size = Vector2(1520, 18)
	rates.add_theme_font_size_override("font_size", 12)
	rates.add_theme_color_override("font_color", Color(0.55, 0.7, 0.85))
	dm.add_child(rates)

	# Thin separator
	var sep := ColorRect.new()
	sep.color = Color(0.35, 0.2, 0.55)
	sep.position = Vector2(70, 548)
	sep.size = Vector2(1460, 2)
	dm.add_child(sep)

	# Leaderboard heading
	var lb_title := Label.new()
	lb_title.text = "- LEADERBOARD -"
	lb_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lb_title.position = Vector2(40, 558)
	lb_title.size = Vector2(1100, 22)
	lb_title.add_theme_font_size_override("font_size", 14)
	lb_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	dm.add_child(lb_title)

	# Three leaderboard columns occupy left ~1100px; weapon panel occupies the right
	_add_lb_column(dm, "PORTALS",       Leaderboard.get_top("portals", 5), Vector2(70,  584), ranks.get("portals", -1))
	_add_lb_column(dm, "GOLD",          Leaderboard.get_top("gold",    5), Vector2(420, 584), ranks.get("gold",    -1))
	_add_lb_column(dm, "DAMAGE",        Leaderboard.get_top("damage",  5), Vector2(770, 584), ranks.get("damage",  -1))

	# Weapon panel on the right
	_build_death_weapon_panel(dm, Vector2(1170, 558), Vector2(360, 316))

func _made_top_10(ranks: Dictionary) -> bool:
	for cat in ["portals", "gold", "damage"]:
		var r: int = int(ranks.get(cat, -1))
		if r >= 1 and r <= 10:
			return true
	return false

# Modal name-entry overlay for global leaderboard submission. Sits on top
# of the death menu; player can submit, skip, and either way the death
# menu's RETRY/QUIT/TITLE buttons remain reachable underneath.
func _show_global_submit_prompt() -> void:
	var dm := $HUD/DeathMenu

	var overlay := ColorRect.new()
	overlay.name = "GlobalSubmitOverlay"
	overlay.color = Color(0.0, 0.0, 0.0, 0.78)
	overlay.anchor_right  = 1.0
	overlay.anchor_bottom = 1.0
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	dm.add_child(overlay)

	var panel := ColorRect.new()
	panel.color = Color(0.05, 0.03, 0.12, 0.98)
	panel.position = Vector2(560, 320)
	panel.size = Vector2(480, 240)
	overlay.add_child(panel)

	var border := ColorRect.new()
	border.color = Color(0.45, 0.30, 0.75, 0.9)
	border.position = Vector2(557, 317)
	border.size = Vector2(486, 246)
	overlay.add_child(border)
	overlay.move_child(panel, -1)

	var title := Label.new()
	title.text = "★ TOP 10 — SUBMIT TO GLOBAL BOARD ★"
	title.position = Vector2(560, 340)
	title.size = Vector2(480, 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	overlay.add_child(title)

	var hint := Label.new()
	hint.text = "Enter a name (max 16 characters):"
	hint.position = Vector2(560, 380)
	hint.size = Vector2(480, 20)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.85))
	overlay.add_child(hint)

	var name_input := LineEdit.new()
	name_input.position = Vector2(640, 410)
	name_input.size = Vector2(320, 36)
	name_input.max_length = 16
	name_input.placeholder_text = "WIZARD"
	name_input.text = GameState.player_name
	name_input.add_theme_font_size_override("font_size", 18)
	overlay.add_child(name_input)
	name_input.grab_focus()

	var submit := Button.new()
	submit.text = "SUBMIT"
	submit.position = Vector2(640, 470)
	submit.size = Vector2(140, 36)
	overlay.add_child(submit)

	var skip := Button.new()
	skip.text = "SKIP"
	skip.position = Vector2(820, 470)
	skip.size = Vector2(140, 36)
	overlay.add_child(skip)

	var do_submit := func() -> void:
		var entered: String = name_input.text.strip_edges().substr(0, 16)
		if entered.is_empty():
			return
		GameState.player_name = entered
		GameState.save_settings()
		OnlineLeaderboard.submit(entered,
			GameState.portals_used, GameState.gold, GameState.damage_dealt)
		overlay.queue_free()

	submit.pressed.connect(do_submit)
	name_input.text_submitted.connect(func(_t: String) -> void: do_submit.call())
	skip.pressed.connect(func() -> void: overlay.queue_free())

func _format_run_time(secs: float) -> String:
	var s: int = int(round(secs))
	@warning_ignore("integer_division")
	var m: int = s / 60
	var rs: int = s - m * 60
	return "%d:%02d" % [m, rs]

# Mirrors the pause menu's weapon stats — kills/damage/floors per shoot type,
# sorted by damage. Rendered into the death-menu panel.
func _build_death_weapon_panel(parent: Node, pos: Vector2, size: Vector2) -> void:
	var title := Label.new()
	title.text = "- WEAPON USE -"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = pos
	title.size = Vector2(size.x, 22)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	parent.add_child(title)

	var body := Label.new()
	body.position = pos + Vector2(8.0, 26.0)
	body.size     = Vector2(size.x - 16.0, size.y - 28.0)
	body.add_theme_font_size_override("font_size", 12)
	body.add_theme_color_override("font_color", Color(0.95, 0.9, 0.85))
	body.add_theme_constant_override("line_separation", 4)
	# Monospace so the columns line up
	var mono := MonoFont.get_font()
	body.add_theme_font_override("font", mono)
	parent.add_child(body)

	if GameState.weapon_stats.is_empty():
		body.text = "(no weapons used)"
		return
	var rows: Array = []
	for k in GameState.weapon_stats.keys():
		var s: Dictionary = GameState.weapon_stats[k]
		rows.append({
			"type":   String(k),
			"kills":  int(s.get("kills", 0)),
			"damage": int(s.get("damage", 0)),
			"floors": int((s.get("floors", {}) as Dictionary).size()),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["damage"]) > int(b["damage"]))
	var lines: Array = ["%-9s  %4s  %6s  %2s" % ["TYPE", "KILL", "DMG", "FL"]]
	for r in rows:
		var t: String = String(r["type"]).to_upper()
		if t.length() > 9:
			t = t.substr(0, 9)
		lines.append("%-9s  %4d  %6d  %2d" % [t, int(r["kills"]), int(r["damage"]), int(r["floors"])])
	body.text = "\n".join(lines)

func _add_lb_column(parent: Node, title: String, entries: Array, pos: Vector2, highlight_rank: int = -1) -> void:
	var col_w := 320.0

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
	# +5 max HP per VIT point — investing in VIT now meaningfully tanks up.
	return max_health + _equip_health_bonus + GameState.get_stat_bonus("VIT") * 5

func heal_to_full() -> void:
	health = _max_hp()
	mana = max_mana
	_update_health_bar()

func update_equip_stats() -> void:
	_equip_speed_bonus      = InventoryManager.get_stat("speed")
	_equip_fire_rate_bonus  = InventoryManager.get_stat("fire_rate_reduction")
	# Projectile-count item bonuses are disabled for now (offhand tomes etc.).
	# The proj_up perk still applies via _perk_proj_bonus added below.
	_equip_projectile_count = 0
	_equip_wisdom_bonus     = InventoryManager.get_stat("wisdom")
	var new_bonus           := int(InventoryManager.get_stat("max_health"))

	var sb := _get_set_bonuses()
	_equip_speed_bonus      += sb.get("speed",        0.0)
	_equip_wisdom_bonus     += BASE_WISDOM * sb.get("wisdom_pct", 0.0)
	_set_def_bonus          = int(sb.get("DEF", 0))
	new_bonus               += int(sb.get("max_health", 0))
	# +5 max mana per WIS stat point — investing in WIS now expands the pool
	# directly, on top of its existing mana-regen contribution.
	max_mana = 100.0 + sb.get("max_mana", 0.0) + _perk_mana_bonus \
		+ float(GameState.get_stat_bonus("WIS")) * 5.0
	max_stamina = 100.0 + _perk_stam_bonus + float(GameState.get_stat_bonus("END")) * 4.0
	_stam_regen_bonus = InventoryManager.get_stat("stam_regen") + sb.get("stam_regen", 0.0)

	_equip_projectile_count += _perk_proj_bonus
	_equip_wisdom_bonus     += BASE_WISDOM * _perk_wisdom_bonus_p

	var delta := new_bonus - _equip_health_bonus
	_equip_health_bonus = new_bonus
	if not _equip_stats_initialized:
		# First call right after _ready — equipment was already accounted for
		# in the saved health, so don't grant the full max_health bonus as a
		# heal here (otherwise +1000 max-HP gear teleports the player back to
		# full every portal).
		_equip_stats_initialized = true
		health = maxi(1, mini(health, _max_hp()))
	elif delta > 0:
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

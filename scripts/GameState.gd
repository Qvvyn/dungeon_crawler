extends Node

# Bump on each release. Surfaced on the title screen and available to
# leaderboard submissions / debug snapshots so issues filed by players
# can be matched against the build they were on.
const GAME_VERSION := "v0.2.4"

signal leveled_up

# Emitted whenever the active render mode changes (TOPDOWN ↔ either FP mode).
# World.gd, Player.gd, EnemyBase.gd, Projectile.gd connect to flip visibility on
# their top-down visuals and to swap in / out the active first-person rig.
signal render_mode_changed(mode: int)

# Cycle order (F1): TOPDOWN → THIRD_PERSON_SHADER → FIRSTPERSON_SHADER → TOPDOWN.
# FIRSTPERSON_RAYCASTER (the full-ASCII raycast renderer) was dropped to keep
# the cycle to the three core perspectives. Reserved as enum slot 3 in case
# we re-enable it later.
enum RenderMode { TOPDOWN, THIRD_PERSON, FIRSTPERSON_SHADER }
const RENDER_MODE_NAMES := ["TOP-DOWN", "3RD PERSON", "1ST PERSON"]
# Non-TOPDOWN render modes lose at-a-glance information (corner peek, etc),
# so the engine ticks slower in those modes to give the player time to read
# the pixelated scene and react. TOPDOWN stays at 1.0×.
const NON_TOPDOWN_TIME_SCALE: float = 0.75

# Default to 3rd-person on first launch (no saved settings yet). Players who
# explicitly cycled to TOPDOWN / 1st-person have their choice persisted via
# save_settings() and restored on reload.
var render_mode: int = RenderMode.THIRD_PERSON
# The currently-active first-person rig node (FirstPersonRig or RaycasterRig)
# during a run, or null while TOPDOWN. World.gd publishes it here when it
# instantiates the rig so entities can register / unregister visuals without
# needing a direct reference. Cleared on scene change.
var active_rig: Node = null

# Register a 2D body (interactable, hazard, loot, etc) so the active
# first-person rig draws a glyph at its world position. Stores the glyph/color
# as metadata + adds to the "fp_visible" group so World can bulk re-register
# on mode toggle (entities created during top-down play still need to show
# when the player cycles to an FP mode). Safe to call when no rig is active.
# Optional `height` is in tile units (0 = floor, 1 = ceiling). Defaults to
# chest height so a body / interactable reads at eye-ish level.
func attach_fp_visual(body: Node2D, glyph: String, color: Color, height: float = 0.5) -> void:
	if not is_instance_valid(body):
		return
	body.set_meta("fp_glyph", glyph)
	body.set_meta("fp_color", color)
	body.set_meta("fp_height", height)
	if not body.is_in_group("fp_visible"):
		body.add_to_group("fp_visible")
	if active_rig != null and is_instance_valid(active_rig) \
			and active_rig.has_method("register_entity"):
		active_rig.register_entity(body, glyph, color)
		# Bind self-cleanup on tree exit so the rig doesn't hold a freed ref.
		var cb: Callable = _detach_fp_visual.bind(body)
		if not body.tree_exiting.is_connected(cb):
			body.tree_exiting.connect(cb)

func _detach_fp_visual(body: Node) -> void:
	if active_rig != null and is_instance_valid(active_rig) \
			and active_rig.has_method("unregister_entity"):
		active_rig.unregister_entity(body)

# Cohesive per-biome enemy tint for FP/3rd-person, replacing the old flat red.
# Indexed by biome; readable + bright against the dim biome wall colors.
const BIOME_ENEMY_COLORS: Array[Color] = [
	Color(0.95, 0.45, 0.35),   # Dungeon    — clay red
	Color(0.65, 0.95, 0.45),   # Catacombs  — sickly green
	Color(0.55, 0.85, 1.00),   # Ice Cavern — icy cyan
	Color(1.00, 0.55, 0.20),   # Lava Rift  — molten orange
]

# Enemy FP color by tier (0 normal, 1 elite, 2 champion/rare, 3 boss). Higher
# tiers lighten the base biome hue so they visibly "glow" through the ASCII
# shader, keeping the floor's enemies cohesive while flagging the dangerous ones.
func enemy_fp_color(tier: int = 0) -> Color:
	var idx: int = clampi(biome, 0, BIOME_ENEMY_COLORS.size() - 1)
	var base: Color = BIOME_ENEMY_COLORS[idx]
	match tier:
		1: return base.lightened(0.25)
		2: return base.lightened(0.45)
		3: return base.lightened(0.55)
		_: return base

# FP colour for an enemy: prefer its AsciiChar's explicit font_color (an
# AsciiSprite's tuned base colour, or an elite tint applied at spawn) over the
# generic biome enemy tint. This is why sprite-driven enemies kept rendering
# clay-red/molten-orange in FP — they were registered with the biome colour
# instead of the colour the sprite was actually set to.
func enemy_fp_color_for(body: Node, tier: int = 0) -> Color:
	var lbl := body.get_node_or_null("AsciiChar")
	if lbl is Label and (lbl as Label).has_theme_color_override("font_color"):
		return (lbl as Label).get_theme_color("font_color")
	return enemy_fp_color(tier)

# Refresh an already-attached entity's FP glyph/color without re-registering.
# Used by LootBag when its rarity tier changes mid-floor so the FP bag re-
# shapes and re-tints to match the 2D view. Also updates the meta fields so
# a future re-register (mode toggle) replays the latest values.
func update_fp_visual(body: Node2D, glyph: String, color: Color) -> void:
	if not is_instance_valid(body):
		return
	body.set_meta("fp_glyph", glyph)
	body.set_meta("fp_color", color)
	if active_rig != null and is_instance_valid(active_rig) \
			and active_rig.has_method("update_fp_visual"):
		active_rig.update_fp_visual(body, glyph, color)

func set_render_mode(mode: int) -> void:
	mode = clampi(mode, 0, RenderMode.size() - 1)
	if mode == render_mode:
		return
	render_mode = mode
	# Apply the per-mode time scale here so every entry point (F1 cycle,
	# Village force-TOPDOWN, save-restore) goes through one switch — leaving
	# any FP mode for the Village hub will snap speed back to 1.0× without
	# the caller having to remember.
	Engine.time_scale = 1.0 if mode == RenderMode.TOPDOWN else NON_TOPDOWN_TIME_SCALE
	render_mode_changed.emit(mode)

func cycle_render_mode() -> void:
	set_render_mode((render_mode + 1) % RenderMode.size())

var has_saved_state: bool = false
var player_health: int = 10

# Level carry-through for the village → dungeon round trip. ExitPortal
# stashes the current level/xp into these; the next reset_run_stats restores
# them so the player doesn't get knocked back to level 1 just for visiting
# the hub. Cleared on death (run_stats reset clears them along with the
# transient run state). 0 means "no carry pending."
var carry_level: int = 0
var carry_xp: int = 0

# Levitate toggle state. Player presses SPACE to toggle on/off; the
# bool persists in this autoload so the next floor (or village → dungeon
# round trip) restores it without the player re-pressing. Cleared on
# death so a new run doesn't inherit a stale lift.
var levitate_toggled: bool = false

# Per-floor drop history — set of template display_names that have
# already dropped this floor. Used by ItemDB.random_drop to bias the
# fixed-pool fallback toward templates the player hasn't seen yet, so
# the same "Pointed Hat" doesn't show up three times in one room.
# World._generate_floor clears this on floor entry.
var floor_drop_history: Dictionary = {}

# Run seed — when non-zero, all RNG for the run derives from this value so
# two players who pick the same seed get identical floors / loot / events.
# 0 means "random run, no fixed seed". Set by TitleScreen before scene
# change and applied in reset_run_stats().
var run_seed: int = 0
# True when the active run was launched from the Daily Challenge button.
# Surfaced on the death screen so leaderboard entries can be filtered.
var is_daily_run: bool = false

# Returns today's deterministic Daily Challenge seed. Same value for every
# player on a given UTC date so the day's leaderboard is comparable.
func daily_seed() -> int:
	var d: Dictionary = Time.get_date_dict_from_system(true)
	# Pack year/month/day into a single int — safe across years and easy
	# to debug if you eyeball it (20260502 = May 2 2026).
	return int(d.get("year", 1970)) * 10000 \
		+ int(d.get("month", 1)) * 100 \
		+ int(d.get("day", 1))

# One-shot guard: when true, the next Player._try_load_save() returns
# immediately without consuming user://save_run.json. The Village sets
# this before spawning its idle Player so visiting the hub doesn't eat
# a saved dungeon run.
var skip_save_load_once: bool = false

# Set by the Village while the player is in the hub. Player._ready
# checks this to skip reset_run_stats so XP / level / inventory carry
# across the hub visit. DescendPortal flips it back to false before
# loading World.tscn.
var in_hub: bool = false

# True when running in a mobile browser (iOS/Android) or on any
# touchscreen-only web context. Set once at startup; the Player scene
# uses it to decide whether to spawn the touch HUD overlay.
var is_mobile: bool = false

# User preferences (persist across sessions)
var crt_enabled: bool    = false
var master_volume: float = 1.0   # 0.0 – 1.0
# Accessibility — when true, suppresses the high-contrast / high-frequency
# visual flashes (player damage screen flash, enemy hit-flash modulate,
# rapid mine flicker, banshee pulse intensity, level-up pop). Slow sine
# pulses and animation frame swaps stay since they're softer.
var disable_flashing: bool = false
# FP limb-drift master toggle (Shift+D). When true (default) each row of a
# multi-line ASCII entity is its own camera-facing billboard offset along the
# camera-right vector, so rows swing independently as the camera orbits. When
# false the whole entity renders as one rigid camera-facing plane (rows'
# billboarding disabled, parent Y-billboards toward the camera) so multi-line
# art reads solid with no inter-row wobble.
var fp_limb_drift: bool = false
# Debug / playtest toggle — when true, _spend_mana_or_hp short-circuits to
# success so wand shots, nova, shield, levitate, etc. cost nothing. The
# only thing that still gates is wand_charges (limited-use wands).
var infinite_mana: bool = false
# Debug cheat: damage to the player is silently swallowed when on. Toggled
# with F2 alongside infinite_mana so the two stay in lockstep (one "god
# mode" feel). take_damage() early-returns when this is true.
var infinite_health: bool = false
# Index into MonoFont.FONTS — drives which typeface MonoFont.get_font()
# returns. Cycled via the debug menu. Persists across sessions; takes
# effect on the next FP rig rebuild / scene reload since existing
# Label3Ds / Labels hold their font reference at creation time.
var font_choice: int = 0
var show_hitboxes: bool = false
# Debug overlay: floats each enemy's script-derived name above their head
# in FP. Toggled with KEY_N. Useful for ID'ing which enemy type is which
# when balancing or chasing a behavior bug.
var show_enemy_names: bool = false
# Debug toggle: force-apply the FP "blinded" vignette (radial darkness in
# the ASCII post-shader). Sticky across render-mode flips — re-applied to
# the rig in _apply_render_mode. Drives FirstPersonRig.set_blinded().
var fp_blinded: bool = false
# Debug toggle: force the FP rig into "fully illuminated" mode (uniform
# bright ambient + boosted torch + extended cull distance). Mutually
# exclusive with fp_blinded in the debug menu cycle — only one can be on
# at a time. Re-applied on render-mode flips via _apply_fp_lighting_to_rig.
var fp_illuminated: bool = false
# Debug toggle: overrides every freeze / fire / shock projectile's
# status_stacks to 100 per hit, so a single shot pops ENFLAMED / FROZEN /
# ELECTRIFIED instantly. Mainly for stress-testing the status overlays and
# checking how fast a build can cycle elemental procs. Session-only — not
# persisted to settings.json.
var debug_status_x100: bool = false
# FP render resolution — when true, the SubViewport renders at half size
# (with proportionally smaller cell_px) so the GPU processes 75% fewer
# pixels. Same number of ASCII characters on screen; slightly softer look.
# Takes effect the next time a dungeon floor loads.
var fp_low_res: bool = false
# Player wizard tint — applied to the wizard's 2D glyph + FP/3rd-person body.
# Customizable via the pause-menu hex field. Default is the classic purple.
var wizard_color: Color = Color(0.85, 0.55, 1.0)
# Display name for global leaderboard submissions. Empty until the player
# fills in the prompt that appears on first top-10 death.
var player_name: String  = ""

const SETTINGS_PATH := "user://settings.json"
const SAVE_RUN_PATH := "user://save_run.json"

# Reads run-state fields (difficulty, level, biome, portal count, etc.)
# from save_run.json into GameState WITHOUT touching inventory or
# deleting the file. Called by the CONTINUE flows (Village → Dungeon
# DescendPortal, Title Screen → CONTINUE RUN) before scene change so
# World._ready can generate the floor at the saved difficulty. Player.
# _try_load_save still runs after the scene loads to restore inventory
# and consume the file.
# Returns true if the save was found and applied; false otherwise.
func peek_save_run_state() -> bool:
	if not FileAccess.file_exists(SAVE_RUN_PATH):
		return false
	var f := FileAccess.open(SAVE_RUN_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		return false
	var data := parsed as Dictionary
	gold         = int(data.get("gold", 0))
	kills        = int(data.get("kills", 0))
	level        = int(data.get("level", 1))
	xp           = int(data.get("xp", 0))
	portals_used = int(data.get("portals_used", 0))
	difficulty   = float(data.get("difficulty", starting_difficulty))
	biome        = int(data.get("biome", 0))
	damage_dealt = int(data.get("damage_dealt", 0))
	if data.has("run_stat_bonuses"):
		run_stat_bonuses = (data["run_stat_bonuses"] as Dictionary).duplicate()
	if data.has("floor_modifiers"):
		var mods_in: Array = data["floor_modifiers"]
		floor_modifiers = []
		for m in mods_in:
			floor_modifiers.append(String(m))
		floor_modifier = floor_modifiers[0] if not floor_modifiers.is_empty() else ""
	return true

func _ready() -> void:
	_load_settings()
	# Mobile detection — Godot's web export sets web_ios / web_android based
	# on the user agent. Fall back to touchscreen capability for cases where
	# the UA isn't matched (e.g. some embedded browsers).
	is_mobile = OS.has_feature("web_ios") or OS.has_feature("web_android") \
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"crt_enabled":         crt_enabled,
		"master_volume":       master_volume,
		"autoplay_sprint":     autoplay_sprint,
		"starting_difficulty": starting_difficulty,
		"starting_climb_rate": starting_climb_rate,
		"player_name":         player_name,
		"disable_flashing":    disable_flashing,
		"fp_limb_drift":       fp_limb_drift,
		"wizard_color":        wizard_color.to_html(false),
		"render_mode":         render_mode,
		"infinite_mana":       infinite_mana,
		"infinite_health":     infinite_health,
		"font_choice":         font_choice,
		"fp_low_res":          fp_low_res,
	}))
	f.close()

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if f == null:
		return
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if result is Dictionary:
		crt_enabled         = bool(result.get("crt_enabled", false))
		master_volume       = clampf(float(result.get("master_volume", 1.0)), 0.0, 1.0)
		autoplay_sprint     = bool(result.get("autoplay_sprint", false))
		starting_difficulty = clampf(float(result.get("starting_difficulty", 1.0)), 1.0, 6.0)
		starting_climb_rate = clampf(float(result.get("starting_climb_rate", 0.5)), 0.1, 4.0)
		player_name         = String(result.get("player_name", "")).substr(0, 16)
		disable_flashing    = bool(result.get("disable_flashing", false))
		fp_limb_drift       = bool(result.get("fp_limb_drift", true))
		var wc: String = String(result.get("wizard_color", ""))
		if wc != "" and Color.html_is_valid(wc):
			wizard_color = Color.html(wc)
		render_mode         = clampi(int(result.get("render_mode", RenderMode.THIRD_PERSON)),
									 0, RenderMode.size() - 1)
		infinite_mana       = bool(result.get("infinite_mana", false))
		infinite_health     = bool(result.get("infinite_health", false))
		font_choice         = clampi(int(result.get("font_choice", 0)), 0, 99)
		fp_low_res          = bool(result.get("fp_low_res",   false))
		# Mirror the loaded difficulty into the active run value so the title
		# screen's slider starts where the player last left it.
		difficulty = starting_difficulty
	_apply_volume()

func _apply_volume() -> void:
	var db := linear_to_db(maxf(master_volume, 0.0001))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), db)

# Persistent progression (survives death)
var level: int = 1
var xp: int = 0

# ── Player stats (base 10, +1 per level) ─────────────────────────────────────
# All ten stats are equal and derived from level. get_stat_bonus returns the
# delta above the base of 10, used by Player.gd to scale gameplay effects.
# STR was removed — INT now drives damage scaling alongside its elemental
# duties, so a separate physical-damage stat just doubled up. Existing
# saves with run_stat_bonuses["STR"] are harmless (get_stat_bonus("STR")
# still returns the stored value but nothing reads it anymore).
const STAT_NAMES := ["DEX", "AGI", "VIT", "END", "INT", "WIS", "DEF", "LCK"]
const STAT_BASE  := 10

# Run-scoped stat bonuses (e.g., from shrines). Cleared at run reset.
var run_stat_bonuses: Dictionary = {}

func get_stat(stat_name: String) -> int:
	# DEF starts at 0 and never auto-scales — it only comes from gear and
	# run shrines, so the player has to actively build into it instead of
	# getting passive damage reduction every level.
	if stat_name == "DEF":
		return get_stat_bonus(stat_name)
	return STAT_BASE + get_stat_bonus(stat_name)

func get_stat_bonus(stat_name: String) -> int:
	var equip_bonus: int = 0
	if InventoryManager:
		equip_bonus = int(InventoryManager.get_stat(stat_name))
	var run_bonus: int = int(run_stat_bonuses.get(stat_name, 0))
	# DEF skips the per-level bonus too. Other stats still get +1 per level.
	if stat_name == "DEF":
		return equip_bonus + run_bonus
	var level_bonus: int = max(0, level - 1)
	return level_bonus + equip_bonus + run_bonus

func roll_crit() -> bool:
	var bonus: int = get_stat_bonus("LCK")
	return randf() < clampf(float(bonus) * 0.005, 0.0, 0.5)

# Crit damage multiplier — base 2.0× plus +5 % per LCK point (capped at 4×).
# Stat investment now scales the *size* of crits, not just their frequency,
# giving the player a power curve that matches the enemy difficulty ramp.
func crit_damage_mult() -> float:
	var bonus: int = get_stat_bonus("LCK")
	return clampf(2.0 + float(bonus) * 0.05, 2.0, 4.0)

# Discount applied to shop / enchant-table prices as difficulty climbs so
# the upgrade pipeline keeps pace with the harder fights. Returns a
# multiplier in [0.55, 1.0]:  ≥3 → 0.85,  ≥5 → 0.70,  ≥7 → 0.55.
func price_multiplier() -> float:
	var d: float = test_difficulty if test_mode else difficulty
	if d >= 7.0: return 0.55
	if d >= 5.0: return 0.70
	if d >= 3.0: return 0.85
	return 1.0

# Per-run stats (reset on new run, persist across portals within a run)
var kills: int = 0
var gold: int = 0
var damage_dealt: int = 0
var portals_used: int = 0
var difficulty: float = 1.0
var biome: int = 0   # 0=Dungeon 1=Catacombs 2=Ice Cavern 3=Lava Rift
# Wall-clock seconds when the current run started — used for the end-of-run
# summary's gold/sec and damage/sec rates.
var run_start_msec: int = 0
# Timestamp of the most recent enemy death — set by EnemyBase. The
# Ice Cavern hypothermia mechanic reads this to decide whether stamina
# regen is at full speed or halved (penalty kicks in after 4 s without
# a kill).
var last_kill_msec: int = 0
# Delta-accumulated "seconds since last kill". Player ticks this each frame
# with delta so it respects Engine.time_scale (non-TOPDOWN modes slow the
# clock to 0.75×). Reset to 0 in EnemyBase when an enemy dies. Hypothermia
# (Player.gd) checks this instead of the wall-clock last_kill_msec so the
# 4 s threshold fires at in-game time, not real time.
var since_kill_s: float = 0.0

# Testing-arena enemy override. When non-empty, _tick_test_wave only
# spawns enemies of this scene name (matches a key in the enemy
# scene-by-name table in World.gd). Empty string = default mixed-pool
# behavior. Set via the test-mode pause menu's spawn dropdown.
var test_spawn_override: String = ""

# Test-mode drops toggle. When false, EnemyBase skips its loot/gold
# drop block entirely (champion + regular paths). When true, enemy
# drops scale to GameState.test_difficulty (instead of starting_diff).
# Defaults to true so tweaking test difficulty without flipping this
# behaves like the regular game.
var test_drops_enabled: bool = true

# Per-shot-type stats keyed by wand shoot_type ("regular", "fire", "beam", ...).
# Each entry: { "kills": int, "damage": int, "floors": Dictionary }
# `floors` is used as a set (keys are floor indices) so unique floors collapse.
var weapon_stats: Dictionary = {}

# Set by dungeon select — persists for the whole run
var starting_difficulty: float = 1.0
var loot_multiplier: float = 1.0
# Per-portal difficulty climb rate. Set by the title-screen dungeon select
# alongside starting_difficulty so each tier owns its climb rate even when
# two tiers happen to start at the same difficulty value (e.g. Catacombs
# and Dungeon both start at 1.0 now but climb at +1.0 and +0.5 per portal
# respectively).
var starting_climb_rate: float = 0.5

# Testing grounds
var test_mode: bool         = false
var test_spawn_pos: Vector2 = Vector2.ZERO
var test_difficulty: float  = 1.0

# Autoplay persists across scene reloads (e.g., portal transitions)
var autoplay_active: bool = false
var autoplay_sprint: bool = false

# Floor modifier (re-rolled each floor, cleared on new run). The
# legacy `floor_modifier` is kept synced to floor_modifiers[0] so older
# call sites that compare it directly keep working. New code should use
# has_floor_modifier(name) which checks the full stacked list.
var floor_modifier: String = ""
var floor_modifiers: Array[String] = []

func has_floor_modifier(name: String) -> bool:
	return floor_modifiers.has(name)

func reset_run_stats() -> void:
	kills = 0
	gold = 0
	damage_dealt = 0
	portals_used = 0
	difficulty = starting_difficulty
	biome = 0
	# Level carry-through — if the player exited to the village mid-run,
	# ExitPortal stashed level/xp into carry_level/carry_xp so a subsequent
	# DescendPortal preserves their progression. Otherwise it's a fresh
	# level-1 run.
	if carry_level > 0:
		level = carry_level
		xp = carry_xp
		carry_level = 0
		carry_xp = 0
	else:
		level = 1
		xp = 0
	run_stat_bonuses.clear()
	weapon_stats.clear()
	# Death (which calls reset_run_stats indirectly through the new-run
	# path) wipes the levitate toggle so a fresh life starts grounded.
	levitate_toggled = false
	run_start_msec = Time.get_ticks_msec()
	# Apply the run seed if one was set by the title screen. Calling
	# `seed()` reseeds Godot's global RNG, so every randi/randf in floor
	# generation, loot, modifiers, etc. derives deterministically from
	# this value. run_seed == 0 means "no fixed seed" — leave RNG as-is.
	if run_seed != 0:
		seed(run_seed)

func run_seconds() -> float:
	return maxf(0.001, float(Time.get_ticks_msec() - run_start_msec) / 1000.0)

func _wstat(wtype: String) -> Dictionary:
	if not weapon_stats.has(wtype):
		weapon_stats[wtype] = {"kills": 0, "damage": 0, "floors": {}}
	return weapon_stats[wtype]

func record_weapon_damage(wtype: String, amount: int) -> void:
	if wtype == "" or amount <= 0:
		return
	var s := _wstat(wtype)
	s["damage"] = int(s["damage"]) + amount
	(s["floors"] as Dictionary)[portals_used] = true

func record_weapon_kill(wtype: String) -> void:
	if wtype == "":
		return
	var s := _wstat(wtype)
	s["kills"] = int(s["kills"]) + 1
	(s["floors"] as Dictionary)[portals_used] = true

func add_xp(amount: int) -> void:
	# Higher-difficulty kills give more XP — keeps progression matched to
	# the threat ramp. +20 % XP per +1.0 difficulty above the first floor.
	# Test mode keeps a flat rate so its leaderboard stays comparable.
	var diff_used: float = test_difficulty if test_mode else difficulty
	var diff_mult: float = 1.0 + maxf(0.0, diff_used - 1.0) * 0.20
	xp += int(round(float(amount) * diff_mult))
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		leveled_up.emit()

func xp_to_next_level() -> int:
	# Geometric curve — each level costs 20% more XP than the previous.
	#   xp_to_next(L) = 42 * 1.20^(L - 1)
	#
	# Sample values (rounded):
	#   L1   42       L2   50       L5   87       L10  217
	#   L20  1,342    L30  8,308    L40  51,442   L50  318,544
	#
	# Cumulative to reach (closed-form: 42·(1.20^L − 1)/0.20):
	#   L10  ~1,090    L20  ~7,840     L30  ~49,644
	#   L40  ~308,448  L50  ~1.9M      L100 ~17B
	#
	# The 20% slope makes the late game a genuine vertical wall — L40+
	# is for committed runs, L50 is meta-progression territory, and
	# anything past L60 is essentially decorative without test-mode
	# input. Power is meant to come from gear at deep difficulty, not
	# stat-grinding levels.
	return int(round(42.0 * pow(1.20, float(level - 1))))

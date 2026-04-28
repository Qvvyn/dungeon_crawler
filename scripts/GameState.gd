extends Node

signal leveled_up

var has_saved_state: bool = false
var player_health: int = 10

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
# Display name for global leaderboard submissions. Empty until the player
# fills in the prompt that appears on first top-10 death.
var player_name: String  = ""

const SETTINGS_PATH := "user://settings.json"

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
const STAT_NAMES := ["DEX", "AGI", "VIT", "END", "INT", "WIS", "SPR", "DEF", "LCK"]
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
	level = 1
	xp = 0
	run_stat_bonuses.clear()
	weapon_stats.clear()
	run_start_msec = Time.get_ticks_msec()

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

@warning_ignore("integer_division")
func xp_to_next_level() -> int:
	# Smooth quadratic curve — replaces the old "double every 10 levels"
	# step function with a gradual climb. Lets early levels pop quickly
	# while late levels still take meaningful effort, without the cliff
	# that hit at every decade boundary in the old system.
	#   L1   65 XP    L5   137 XP   L10  250 XP
	#   L20  550 XP   L30  950 XP   L50 2050 XP
	# Formula: 50 + level*15 + level*level/2
	return 50 + level * 15 + (level * level) / 2

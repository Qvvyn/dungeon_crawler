extends Node

signal leveled_up

var has_saved_state: bool = false
var player_health: int = 10

# User preferences (persist across sessions)
var crt_enabled: bool    = false
var master_volume: float = 1.0   # 0.0 – 1.0

const SETTINGS_PATH := "user://settings.json"

func _ready() -> void:
	_load_settings()

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"crt_enabled":         crt_enabled,
		"master_volume":       master_volume,
		"autoplay_sprint":     autoplay_sprint,
		"starting_difficulty": starting_difficulty,
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
const STAT_NAMES := ["STR", "DEX", "AGI", "VIT", "END", "INT", "WIS", "SPR", "DEF", "LCK"]
const STAT_BASE  := 10

# Run-scoped stat bonuses (e.g., from shrines). Cleared at run reset.
var run_stat_bonuses: Dictionary = {}

func get_stat(stat_name: String) -> int:
	return STAT_BASE + get_stat_bonus(stat_name)

func get_stat_bonus(stat_name: String) -> int:
	var level_bonus: int = max(0, level - 1)
	var equip_bonus: int = 0
	if InventoryManager:
		equip_bonus = int(InventoryManager.get_stat(stat_name))
	var run_bonus: int = int(run_stat_bonuses.get(stat_name, 0))
	return level_bonus + equip_bonus + run_bonus

func roll_crit() -> bool:
	var bonus: int = get_stat_bonus("LCK")
	return randf() < clampf(float(bonus) * 0.005, 0.0, 0.5)

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

# Testing grounds
var test_mode: bool         = false
var test_spawn_pos: Vector2 = Vector2.ZERO
var test_difficulty: float  = 1.0

# Autoplay persists across scene reloads (e.g., portal transitions)
var autoplay_active: bool = false
var autoplay_sprint: bool = false

# Floor modifier (re-rolled each floor, cleared on new run)
var floor_modifier: String = ""

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
	xp += amount
	while xp >= xp_to_next_level():
		xp -= xp_to_next_level()
		level += 1
		leveled_up.emit()

@warning_ignore("integer_division")
func xp_to_next_level() -> int:
	# XP cost doubles every 10 levels.
	# Every 10-level block costs as much as all prior blocks combined.
	# Levels 1–20: 42 XP per level | 21–30: 84 | 31–40: 168 | etc.
	return 42 * (1 << max(0, (level - 11) / 10))

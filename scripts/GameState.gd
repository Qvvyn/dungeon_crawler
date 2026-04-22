extends Node

signal leveled_up

var has_saved_state: bool = false
var player_health: int = 10

# User preferences (persist across sessions)
var crt_enabled: bool = false

const SETTINGS_PATH := "user://settings.json"

func _ready() -> void:
	_load_settings()

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({"crt_enabled": crt_enabled}))
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
		crt_enabled = bool(result.get("crt_enabled", false))

# Persistent progression (survives death)
var level: int = 1
var xp: int = 0

# Per-run stats (reset on new run, persist across portals within a run)
var kills: int = 0
var gold: int = 0
var damage_dealt: int = 0
var portals_used: int = 0
var difficulty: float = 1.0
var biome: int = 0   # 0=Dungeon 1=Catacombs 2=Ice Cavern 3=Lava Rift

# Set by dungeon select — persists for the whole run
var starting_difficulty: float = 1.0
var loot_multiplier: float = 1.0

# Testing grounds
var test_mode: bool = false

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

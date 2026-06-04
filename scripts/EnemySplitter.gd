extends "res://scripts/EnemyChaser.gd"

# Splitter — Chaser variant that bursts into two halflings on death.
# Reuses Chaser's existing elite_modifier=2 split machinery instead of
# duplicating it. Halflings are regular Chasers at half HP with no
# further split, so the split itself is the threat (one Splitter ≈ 2
# half-HP Chasers in the room after burst).

const SPLIT_SCENE := preload("res://scenes/EnemyChaser.tscn")

func _ready() -> void:
	super._ready()
	# Flip on Chaser's split-on-death path: elite_modifier=2 + a scene
	# to instantiate. Chaser._do_split already spawns 2 clones at half
	# max_health and clears their elite_modifier, so we don't have to
	# manage halfling lifecycle ourselves.
	elite_modifier = 2
	_split_scene = SPLIT_SCENE

# Splitters use the ghost sprite (gallery #2) instead of the goblin.
func _chaser_sprite_key() -> String:
	return "ghost"

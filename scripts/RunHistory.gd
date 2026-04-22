extends Node

const SAVE_PATH := "user://run_history.json"
const MAX_RUNS  := 5

var runs: Array = []

func _ready() -> void:
	_load()

func add_run(portals: int, kills: int, gold: int, damage: int, biome: int) -> void:
	var entry := {
		"portals": portals,
		"kills":   kills,
		"gold":    gold,
		"damage":  damage,
		"biome":   biome,
		"date":    Time.get_date_string_from_system(),
	}
	runs.push_front(entry)
	if runs.size() > MAX_RUNS:
		runs.resize(MAX_RUNS)
	_save()

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(runs, "\t"))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var result: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if result is Array:
		runs = result

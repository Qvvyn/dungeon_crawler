extends Node

const SAVE_PATH   := "user://leaderboard.json"
const MAX_ENTRIES := 10

var data: Dictionary = {
	"portals": [],
	"gold":    [],
	"damage":  []
}

func _ready() -> void:
	_load()

## Returns a dict of {category: 1-based rank} for the submitted values.
## A rank of -1 means it didn't make the top 10.
func submit(portals: int, gold: int, damage: int) -> Dictionary:
	var ranks := {}
	ranks["portals"] = _insert("portals", {"value": portals})
	ranks["gold"]    = _insert("gold",    {"value": gold})
	ranks["damage"]  = _insert("damage",  {"value": damage})
	_save()
	return ranks

func get_top(category: String, count: int = 10) -> Array:
	return data.get(category, []).slice(0, count)

## Inserts entry into category, keeps top MAX_ENTRIES sorted descending.
## Returns the 1-based rank of the new entry, or -1 if it was cut off.
func _insert(category: String, entry: Dictionary) -> int:
	# Tag entry with a unique marker so we can find it after sorting
	var marker := randi()
	entry["_m"] = marker
	var arr: Array = data.get(category, [])
	arr.append(entry)
	arr.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["value"] > b["value"])
	if arr.size() > MAX_ENTRIES:
		arr.resize(MAX_ENTRIES)
	data[category] = arr
	# Locate the inserted entry and strip the marker
	for i in arr.size():
		if arr[i].get("_m") == marker:
			arr[i].erase("_m")
			return i + 1   # 1-based rank
	return -1              # cut off — didn't make top 10

func _save() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

func _load() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var result = JSON.parse_string(f.get_as_text())
	f.close()
	if result is Dictionary:
		for key in result:
			if key in data:
				data[key] = result[key]

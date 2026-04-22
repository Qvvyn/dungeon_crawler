extends Node

const SAVE_PATH    := "user://leaderboard.json"
const MAX_ENTRIES  := 10
const BIOME_KEYS   := ["dungeon", "catacombs", "ice", "lava"]

var data: Dictionary = {
	"portals": [],
	"gold":    [],
	"damage":  [],
	"biome_deepest": {"dungeon": 0, "catacombs": 0, "ice": 0, "lava": 0},
	"biome_gold":    {"dungeon": 0, "catacombs": 0, "ice": 0, "lava": 0},
}

func _ready() -> void:
	_load()

func submit_biome_record(biome: int, portals: int, gold: int) -> void:
	var key: String = BIOME_KEYS[clampi(biome, 0, 3)]
	var deepest: Dictionary = data.get("biome_deepest", {})
	if portals > int(deepest.get(key, 0)):
		deepest[key] = portals
		data["biome_deepest"] = deepest
	var gold_bests: Dictionary = data.get("biome_gold", {})
	if gold > int(gold_bests.get(key, 0)):
		gold_bests[key] = gold
		data["biome_gold"] = gold_bests
	_save()

func get_biome_records() -> Dictionary:
	return {
		"deepest": data.get("biome_deepest", {}),
		"gold":    data.get("biome_gold",    {}),
	}

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
		for key: String in result:
			if key in data:
				data[key] = result[key]
		# Ensure biome dicts exist after loading older save files
		if not data.has("biome_deepest"):
			data["biome_deepest"] = {"dungeon": 0, "catacombs": 0, "ice": 0, "lava": 0}
		if not data.has("biome_gold"):
			data["biome_gold"] = {"dungeon": 0, "catacombs": 0, "ice": 0, "lava": 0}
